// /api/admin user detail + control actions (routes/admin_users.js) and the analytics additions
// (routes/admin_analytics.js) against a stub db. No real database is touched: db.js is replaced in
// require.cache before any route loads. Queries are answered by their /*q:name*/ tag from a small
// in-memory store; withTransaction snapshots the store and restores it on error, like a ROLLBACK.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const Module = require('module');
const express = require('express');

const KEY = 'test-admin-key-0123456789abcdef';
process.env.ADMIN_KEY = KEY;
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-jwt-secret-0123456789abcdef';

let s; // store
const calls = []; // { name, sql, params, tx }
let overrides = {}; // name -> (params) => result, for read endpoints

function seed() {
  s = {
    users: [
      { id: 1, full_name: 'Asha Verma', email: 'asha@x.com', role: 'user', created_at: new Date('2026-10-01T00:00:00Z'), wallet_balance: 250, invite_code: 'ASHA01', google_id: 'g-1', signup_method: 'google', last_login_method: 'google', last_login_at: new Date('2026-11-12T04:00:00Z'), is_blocked: false, blocked_reason: null, blocked_at: null },
      { id: 2, full_name: 'Pt. Rishi', email: 'rishi@astroai.com', role: 'pandit', created_at: new Date('2026-09-01T00:00:00Z'), wallet_balance: 0, invite_code: null, google_id: null, signup_method: 'email', is_blocked: false },
      { id: 3, full_name: 'Guest', email: 'guest_9@x.astroai.com', role: 'guest', created_at: new Date('2026-11-10T00:00:00Z'), wallet_balance: 250, google_id: null, signup_method: 'guest', is_blocked: false },
      { id: 4, full_name: 'Sneaky Pandit', email: 'sp@x.com', role: 'user', created_at: new Date('2026-09-01T00:00:00Z'), wallet_balance: 0, signup_method: 'email', is_blocked: false },
    ],
    pandits: [{ id: 10, user_id: 2 }, { id: 11, user_id: 4 }],
    ledger: [
      { id: 1, user_id: 1, amount: 500, reason: 'question', ref: 'q1' },
      { id: 2, user_id: 1, amount: -100, reason: 'trip', ref: 'trip:9' },
    ],
    audit: [],
    chats: [
      { id: 1, user_id: 1, role: 'system', content: 'sys' },
      { id: 2, user_id: 1, role: 'user', content: 'hi' },
      { id: 3, user_id: 1, role: 'assistant', content: 'hello' },
      { id: 4, user_id: 3, role: 'user', content: 'yo' },
    ],
    deletedSteps: [],
  };
}
seed();

const isGuestRow = (u) => u.role === 'guest' || /^guest_.*@.*astroai\.com$/i.test(u.email || '');
const userRow = (id) => {
  const u = s.users.find((x) => x.id === id);
  if (!u) return null;
  const coins = s.ledger.filter((l) => l.user_id === id).reduce((a, l) => a + l.amount, 0);
  return { ...u, google_linked: !!u.google_id, is_guest: isGuestRow(u), coins };
};

function answer(name, sql, p) {
  if (overrides[name]) return overrides[name](p, sql);
  switch (name) {
    case 'userSelect': { const r = userRow(p[0]); return { rows: r ? [r] : [] }; }
    case 'userExists':
    case 'userLock': { const u = s.users.find((x) => x.id === p[0]); return { rows: u ? [u] : [] }; }
    case 'panditOf': return { rows: s.pandits.filter((x) => x.user_id === p[0]) };
    case 'block':
    case 'unblock': {
      const u = s.users.find((x) => x.id === p[0]);
      if (!u) return { rows: [] };
      if (name === 'block') Object.assign(u, { is_blocked: true, blocked_reason: p[1], blocked_at: new Date() });
      else Object.assign(u, { is_blocked: false, blocked_reason: null, blocked_at: null });
      return { rows: [{ id: u.id }] };
    }
    case 'auditInsert': {
      const row = { id: s.audit.length + 1, action: p[0], target_user_id: p[1], details: JSON.parse(p[2]), created_at: new Date() };
      s.audit.push(row);
      return { rows: [{ id: row.id }] };
    }
    case 'clearChats': {
      const before = s.chats.length;
      s.chats = s.chats.filter((c) => c.user_id !== p[0]);
      return { rows: [], rowCount: before - s.chats.length };
    }
    case 'tablesPresent': return { rows: p[0].filter((t) => ['chat_messages', 'coin_ledger'].includes(t)).map((t) => ({ table_name: t })) };
    case 'deleteUser': s.users = s.users.filter((u) => u.id !== p[0]); return { rows: [], rowCount: 1 };
    case 'auditList': {
      const rows = s.audit.filter((a) => p[0] === null || a.target_user_id === p[0]).slice().reverse().slice(0, p[1]);
      return { rows };
    }
    default: return { rows: [] };
  }
}

function query(text, params = [], tx = false) {
  const sql = String(text).replace(/\s+/g, ' ').trim();
  const m = sql.match(/\/\*q:(\w+)\*\//);
  const name = m ? m[1] : null;
  calls.push({ name, sql, params, tx });
  if (name) return answer(name, sql, params);
  // Untagged helpers from coins_service and the account delete steps from auth.js.
  if (sql.startsWith('INSERT INTO coin_ledger')) {
    const [userId, amount, reason, ref, note] = params;
    if (s.ledger.some((r) => r.user_id === userId && r.reason === reason && r.ref === ref)) return { rows: [] };
    const row = { id: s.ledger.length + 1, user_id: userId, amount, reason, ref, note };
    s.ledger.push(row);
    return { rows: [{ id: row.id }] };
  }
  if (sql.startsWith('SELECT COALESCE(SUM(amount), 0) AS balance FROM coin_ledger')) {
    return { rows: [{ balance: s.ledger.filter((l) => l.user_id === params[0]).reduce((a, l) => a + l.amount, 0) }] };
  }
  if (/^(DELETE|UPDATE) /.test(sql)) { s.deletedSteps.push(sql); return { rows: [], rowCount: 0 }; }
  return { rows: [] };
}

const dbPath = path.join(__dirname, '..', 'db.js');
const stub = new Module(dbPath);
stub.loaded = true;
stub.exports = {
  query: async (text, params) => query(text, params, false),
  withTransaction: async (fn) => {
    const snapshot = structuredClone(s);
    const client = { query: async (text, params) => query(text, params, true) };
    try {
      return await fn(client);
    } catch (err) {
      s = snapshot;
      throw err;
    }
  },
  ensureInitialized: async () => {},
};
require.cache[dbPath] = stub;

// services/user_blocks.js is written by another agent; stub it so this test does not depend on it.
let refreshes = 0;
const blocksPath = path.join(__dirname, '..', 'services', 'user_blocks.js');
const blocksStub = new Module(blocksPath);
blocksStub.loaded = true;
blocksStub.exports = { refresh: () => { refreshes += 1; }, isBlocked: async () => false };
require.cache[blocksPath] = blocksStub;

const push = require('../services/push_service');
const pushed = [];
let pushResult = { inboxId: 7, sent: 2, failed: 0, removed: 0, skipped: null };
push.sendToUser = async (userId, msg, opts) => { pushed.push({ userId, msg, opts }); return pushResult; };

const adminRouter = require('../routes/admin');

function serve() {
  const app = express();
  app.use(express.json());
  app.use('/api/admin', adminRouter);
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

let srv;
test.before(async () => { srv = await serve(); });
test.after(() => srv.server.close());
test.beforeEach(() => { adminRouter._internals.failures.clear(); seed(); calls.length = 0; overrides = {}; pushed.length = 0; refreshes = 0; });

async function call(method, url, body, key = KEY) {
  const headers = {};
  if (key) headers['x-admin-key'] = key;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(`${srv.base}/api/admin${url}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: res.status, body: await res.json() };
}
const named = (name) => calls.filter((c) => c.name === name);

test('every new route needs the admin key', async () => {
  const routes = [
    ['GET', '/users/1'], ['GET', '/users/1/requests'], ['GET', '/users/1/chats'],
    ['POST', '/users/1/block', { reason: 'x' }], ['POST', '/users/1/unblock'],
    ['POST', '/users/1/coins', { amount: 5, note: 'x' }], ['POST', '/users/1/notify', { title: 't', body: 'b' }],
    ['DELETE', '/users/1/chats'], ['DELETE', '/users/1', { confirm: 'DELETE' }],
    ['GET', '/chats'], ['GET', '/kundlis'], ['GET', '/audit'],
    ['GET', '/analytics/endpoints'], ['GET', '/analytics/logins'], ['GET', '/analytics/live'],
  ];
  for (const [m, u, b] of routes) {
    adminRouter._internals.failures.clear(); // the 10-wrong-keys lockout would turn later 401s into 429s
    const r = await call(m, u, b, null);
    assert.equal(r.status, 401, `${m} ${u}`);
  }
  assert.equal(calls.length, 0);
  assert.equal(s.audit.length, 0);
});

test('GET /users/:id: 404 for unknown or malformed ids', async () => {
  for (const id of ['99', 'abc', '0', '-1', '1.5', '99999999999']) {
    const r = await call('GET', `/users/${id}`);
    assert.equal(r.status, 404, id);
    assert.equal(r.body.code, 'USER_NOT_FOUND');
  }
});

test('GET /users/:id returns the full detail shape', async () => {
  overrides = {
    birth: () => ({ rows: [{ full_name: 'Asha V', gender: 'female', date_of_birth: '1995-04-02', time_of_birth: '06:30:00', place_of_birth: 'Pune', latitude: 18.52, longitude: 73.85, timezone: 'Asia/Kolkata' }] }),
    kundli: () => ({ rows: [{ ascendant: 'Leo', sun_sign: 'Aries', moon_sign: 'Cancer', nakshatra: 'Pushya', nakshatra_pada: 2, created_at: new Date('2026-10-02T00:00:00Z'), updated_at: null, has_ai_report: true }] }),
    family: () => ({ rows: [{ id: 5, full_name: 'Mom', relationship: 'mother', date_of_birth: '1970-01-01', place_of_birth: 'Delhi', created_at: new Date('2026-10-03T00:00:00Z') }] }),
    activityStats: () => ({ rows: [{ total_requests: 120, requests_today: 7, active_days: 9, first_seen: new Date('2026-10-01T01:00:00Z'), last_seen: new Date('2026-11-12T05:00:00Z'), platforms: ['android', 'web'] }] }),
    chatCount: () => ({ rows: [{ n: 2 }] }),
    aiTotals: () => ({ rows: [{ calls: 3, tokens: 4500, cost: 0.0123 }] }),
    todayByRoute: () => ({ rows: [{ method: 'POST', route: '/api/chat', calls: 4, errors: 1, last_at: new Date('2026-11-12T05:00:00Z') }] }),
    aiByFeature: () => ({ rows: [{ feature: 'chat', calls: 3, tokens: 4500, cost: 0.0123 }] }),
    authEvents: () => ({ rows: [{ event: 'login', method: 'google', platform: 'android', created_at: new Date('2026-11-12T04:00:00Z') }] }),
    activityDaily: () => ({ rows: [{ day: '2026-11-12', requests: 7, platforms: ['android'] }] }),
    buddy: () => ({ rows: [{ display_name: 'Asha', is_active: true, banned_at: null }] }),
  };
  const r = await call('GET', '/users/1');
  assert.equal(r.status, 200);
  const d = r.body;
  assert.deepEqual(d.user, {
    id: 1, name: 'Asha Verma', email: 'asha@x.com', role: 'user', isGuest: false, signupMethod: 'google',
    lastLoginMethod: 'google', lastLoginAt: '2026-11-12T04:00:00.000Z', createdAt: '2026-10-01T00:00:00.000Z',
    isBlocked: false, blockedReason: null, blockedAt: null, googleLinked: true, coins: 400, walletBalance: 250, inviteCode: 'ASHA01',
  });
  assert.deepEqual(d.birth, { fullName: 'Asha V', gender: 'female', dateOfBirth: '1995-04-02', timeOfBirth: '06:30:00', placeOfBirth: 'Pune', latitude: 18.52, longitude: 73.85, timezone: 'Asia/Kolkata' });
  assert.deepEqual(d.kundli, { ascendant: 'Leo', sunSign: 'Aries', moonSign: 'Cancer', nakshatra: 'Pushya', nakshatraPada: 2, createdAt: '2026-10-02T00:00:00.000Z', updatedAt: null, hasAiReport: true });
  assert.deepEqual(d.familyKundlis, [{ id: 5, name: 'Mom', relation: 'mother', dateOfBirth: '1970-01-01', placeOfBirth: 'Delhi', createdAt: '2026-10-03T00:00:00.000Z' }]);
  assert.deepEqual(d.stats, { totalRequests: 120, requestsToday: 7, activeDays: 9, firstSeen: '2026-10-01T01:00:00.000Z', lastSeen: '2026-11-12T05:00:00.000Z', platforms: ['android', 'web'], chatMessages: 2, aiCalls: 3, aiTokens: 4500, aiCostUsd: 0.0123 });
  assert.deepEqual(d.todayByRoute, [{ method: 'POST', route: '/api/chat', calls: 4, errors: 1, lastAt: '2026-11-12T05:00:00.000Z' }]);
  assert.deepEqual(d.aiByFeature, [{ feature: 'chat', calls: 3, tokens: 4500, costUsd: 0.0123 }]);
  assert.deepEqual(d.authEvents, [{ event: 'login', method: 'google', platform: 'android', at: '2026-11-12T04:00:00.000Z' }]);
  assert.deepEqual(d.activityDaily, [{ day: '2026-11-12', requests: 7, platforms: ['android'] }]);
  assert.deepEqual(d.buddy, { displayName: 'Asha', isActive: true, bannedAt: null });
  // every per-user query is parameterised with the id
  for (const c of calls) assert.equal(c.params[0], 1, c.name);
});

test('GET /users/:id: empty sections are null / [] and guests are flagged', async () => {
  const r = await call('GET', '/users/3');
  assert.equal(r.status, 200);
  assert.equal(r.body.user.isGuest, true);
  assert.equal(r.body.user.role, 'guest');
  assert.equal(r.body.birth, null);
  assert.equal(r.body.kundli, null);
  assert.equal(r.body.buddy, null);
  assert.deepEqual(r.body.familyKundlis, []);
  assert.deepEqual(r.body.stats.platforms, []);
  assert.equal(r.body.stats.totalRequests, 0);
});

test('GET /users/:id/requests validates day and clamps limit', async () => {
  for (const day of ['2026-02-31', 'yesterday', '2026-1-1', "2026-11-12' OR 1=1"]) {
    const r = await call('GET', `/users/1/requests?day=${encodeURIComponent(day)}`);
    assert.equal(r.status, 400, day);
    assert.equal(r.body.code, 'BAD_DAY');
  }
  overrides.userRequests = () => ({ rows: [{ method: 'GET', route: '/api/kundli/family/:id', status: 200, duration_ms: 42, platform: 'android', created_at: new Date('2026-11-10T06:00:00Z') }] });
  const r = await call('GET', '/users/1/requests?day=2026-11-10&limit=5000');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { day: '2026-11-10', requests: [{ at: '2026-11-10T06:00:00.000Z', method: 'GET', route: '/api/kundli/family/:id', status: 200, ms: 42, platform: 'android' }] });
  assert.deepEqual(named('userRequests')[0].params, [1, '2026-11-10', 1000]);

  calls.length = 0;
  const d = await call('GET', '/users/1/requests');
  assert.match(d.body.day, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(named('userRequests')[0].params[2], 200);
});

test('GET /users/:id/chats pages newest first with hasMore', async () => {
  overrides.userChats = (p) => {
    const rows = s.chats.filter((c) => c.user_id === p[0] && c.role !== 'system' && (p[1] === null || c.id < p[1]))
      .sort((a, b) => b.id - a.id).slice(0, p[2])
      .map((c) => ({ ...c, astrologer_name: 'Guru', specialty: 'Vedic', created_at: new Date('2026-11-12T00:00:00Z') }));
    return { rows };
  };
  const r = await call('GET', '/users/1/chats?limit=1');
  assert.equal(r.status, 200);
  assert.equal(r.body.hasMore, true);
  assert.deepEqual(r.body.messages, [{ id: 3, role: 'assistant', content: 'hello', astrologerName: 'Guru', specialty: 'Vedic', at: '2026-11-12T00:00:00.000Z' }]);
  assert.deepEqual(named('userChats')[0].params, [1, null, 2]);

  const older = await call('GET', '/users/1/chats?before=3&limit=1');
  assert.equal(older.body.hasMore, false);
  assert.equal(older.body.messages[0].id, 2);

  for (const b of ['abc', '-3', '1.5']) {
    const bad = await call('GET', `/users/1/chats?before=${b}`);
    assert.equal(bad.status, 400, b);
    assert.equal(bad.body.code, 'BAD_CURSOR');
  }
});

test('POST /users/:id/block validates reason, blocks, audits and refreshes the cache', async () => {
  for (const body of [{}, { reason: '' }, { reason: '   ' }, { reason: 42 }, { reason: 'x'.repeat(301) }]) {
    const r = await call('POST', '/users/1/block', body);
    assert.equal(r.status, 400);
    assert.equal(r.body.code, 'BAD_REASON');
  }
  assert.equal((await call('POST', '/users/99/block', { reason: 'spam' })).status, 404);
  assert.equal(s.audit.length, 0);

  const r = await call('POST', '/users/1/block', { reason: '  abusive   messages ' });
  assert.equal(r.status, 200);
  assert.equal(r.body.user.isBlocked, true);
  assert.equal(r.body.user.blockedReason, 'abusive messages');
  assert.match(r.body.user.blockedAt, /^\d{4}-/);
  assert.equal(r.body.user.coins, 400);
  assert.deepEqual(s.audit.map((a) => [a.action, a.target_user_id, a.details]), [['block', 1, { reason: 'abusive messages' }]]);
  assert.ok(named('block').every((c) => c.tx) && named('auditInsert').every((c) => c.tx));
  assert.equal(refreshes, 1);

  const u = await call('POST', '/users/1/unblock');
  assert.equal(u.status, 200);
  assert.equal(u.body.user.isBlocked, false);
  assert.equal(u.body.user.blockedReason, null);
  assert.equal(u.body.user.blockedAt, null);
  assert.deepEqual(s.audit.map((a) => a.action), ['block', 'unblock']);
  assert.equal(refreshes, 2);
  assert.equal((await call('POST', '/users/99/unblock')).status, 404);
});

test('POST /users/:id/coins validates amount and note', async () => {
  const bad = [
    [{ note: 'x' }, 'BAD_AMOUNT'], [{ amount: 0, note: 'x' }, 'BAD_AMOUNT'], [{ amount: 1.5, note: 'x' }, 'BAD_AMOUNT'],
    [{ amount: 'abc', note: 'x' }, 'BAD_AMOUNT'], [{ amount: 100001, note: 'x' }, 'BAD_AMOUNT'], [{ amount: -100001, note: 'x' }, 'BAD_AMOUNT'],
    [{ amount: true, note: 'x' }, 'BAD_AMOUNT'], [{ amount: '1e3', note: 'x' }, 'BAD_AMOUNT'],
    [{ amount: 10 }, 'BAD_NOTE'], [{ amount: 10, note: '' }, 'BAD_NOTE'], [{ amount: 10, note: 'x'.repeat(201) }, 'BAD_NOTE'],
  ];
  for (const [body, code] of bad) {
    const r = await call('POST', '/users/1/coins', body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.body.code, code, JSON.stringify(body));
  }
  assert.equal(s.ledger.length, 2);
  assert.equal(s.audit.length, 0);
  assert.equal((await call('POST', '/users/99/coins', { amount: 5, note: 'x' })).status, 404);
});

test('POST /users/:id/coins grants and debits through the ledger with an audit-based ref', async () => {
  const g = await call('POST', '/users/1/coins', { amount: 1000, note: 'Diwali bonus' });
  assert.equal(g.status, 200);
  assert.deepEqual(g.body, { coins: 1400 });
  const grant = s.ledger[s.ledger.length - 1];
  assert.equal(grant.reason, 'admin');
  assert.equal(grant.ref, 'admin:1');
  assert.equal(grant.amount, 1000);
  assert.deepEqual(s.audit[0].details, { amount: 1000, note: 'Diwali bonus', balanceBefore: 400, balanceAfter: 1400 });
  assert.equal(s.audit[0].action, 'coins');
  // users row locked before the balance is read (same lock as /api/trips)
  const order = calls.filter((c) => c.tx).map((c) => c.name || c.sql.slice(0, 20));
  assert.equal(order[0], 'userLock');
  assert.match(named('userLock')[0].sql, /FOR UPDATE/);

  // a second identical grant is a separate ledger row (unique ref)
  const g2 = await call('POST', '/users/1/coins', { amount: 1000, note: 'Diwali bonus' });
  assert.deepEqual(g2.body, { coins: 2400 });

  const d = await call('POST', '/users/1/coins', { amount: '-2400', note: 'clawback' });
  assert.equal(d.status, 200);
  assert.deepEqual(d.body, { coins: 0 });
  assert.equal(s.ledger[s.ledger.length - 1].amount, -2400);
  assert.equal(s.audit.length, 3);
});

test('POST /users/:id/coins refuses a debit below zero and rolls back', async () => {
  const r = await call('POST', '/users/1/coins', { amount: -401, note: 'too much' });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'INSUFFICIENT_COINS');
  assert.equal(s.ledger.length, 2);
  assert.equal(s.audit.length, 0);
  const ok = await call('POST', '/users/1/coins', { amount: -400, note: 'exact' });
  assert.deepEqual(ok.body, { coins: 0 });
  // guests start at 0
  const g = await call('POST', '/users/3/coins', { amount: -1, note: 'x' });
  assert.equal(g.status, 409);
});

test('POST /users/:id/notify validates, pushes admin_message and audits', async () => {
  for (const [body, code] of [[{ body: 'b' }, 'BAD_TITLE'], [{ title: 'x'.repeat(81), body: 'b' }, 'BAD_TITLE'], [{ title: 't' }, 'BAD_BODY'], [{ title: 't', body: 'x'.repeat(301) }, 'BAD_BODY']]) {
    const r = await call('POST', '/users/1/notify', body);
    assert.equal(r.status, 400);
    assert.equal(r.body.code, code);
  }
  assert.equal((await call('POST', '/users/99/notify', { title: 't', body: 'b' })).status, 404);
  assert.equal(pushed.length, 0);

  const r = await call('POST', '/users/1/notify', { title: ' Hello  there ', body: 'Line one\nline two' });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { sent: true, devices: 2 });
  assert.deepEqual(pushed[0], { userId: 1, msg: { type: 'admin_message', title: 'Hello there', body: 'Line one\nline two', data: {} }, opts: undefined });
  assert.deepEqual(s.audit[0].details, { title: 'Hello there', body: 'Line one\nline two', sent: true, devices: 2 });

  pushResult = { error: 'boom' };
  const f = await call('POST', '/users/1/notify', { title: 't', body: 'b' });
  assert.deepEqual(f.body, { sent: false, devices: 0 });
  assert.equal(s.audit.length, 2);
  pushResult = { inboxId: 7, sent: 2, failed: 0, removed: 0, skipped: null };
});

test('DELETE /users/:id/chats clears the history and audits the count', async () => {
  const r = await call('DELETE', '/users/1/chats');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { deleted: 3 });
  assert.equal(s.chats.filter((c) => c.user_id === 1).length, 0);
  assert.equal(s.chats.length, 1);
  assert.deepEqual(s.audit.map((a) => [a.action, a.target_user_id, a.details]), [['clear_chats', 1, { deleted: 3 }]]);
  assert.ok(named('clearChats')[0].tx);
  assert.equal((await call('DELETE', '/users/99/chats')).status, 404);
});

test('DELETE /users/:id needs confirm, refuses pandits, deletes and audits', async () => {
  for (const body of [undefined, {}, { confirm: 'delete' }, { confirm: true }]) {
    const r = await call('DELETE', '/users/1', body);
    assert.equal(r.status, 400);
    assert.equal(r.body.code, 'CONFIRM_REQUIRED');
  }
  for (const id of [2, 4]) { // role pandit, and a 'user' that owns a pandits row
    const r = await call('DELETE', `/users/${id}`, { confirm: 'DELETE' });
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'PANDIT_ACCOUNT');
  }
  assert.equal((await call('DELETE', '/users/99', { confirm: 'DELETE' })).status, 404);
  assert.equal(s.users.length, 4);
  assert.equal(s.audit.length, 0);

  const r = await call('DELETE', '/users/1', { confirm: 'DELETE' });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { deleted: true });
  assert.equal(s.users.some((u) => u.id === 1), false);
  assert.deepEqual(s.audit.map((a) => [a.action, a.target_user_id, a.details]), [['delete_user', 1, { email: 'asha@x.com', name: 'Asha Verma', role: 'user' }]]);
  // the same child-first steps as DELETE /api/auth/account, only for tables that exist
  assert.ok(s.deletedSteps.includes('DELETE FROM chat_messages WHERE user_id = $1'));
  assert.ok(s.deletedSteps.includes('DELETE FROM coin_ledger WHERE user_id = $1'));
  assert.ok(!s.deletedSteps.some((x) => x.includes('device_tokens')));
  assert.ok(named('deleteUser')[0].tx);
});

test('GET /chats groups by user, escapes the search and clamps limit', async () => {
  overrides.chatList = () => ({ rows: [
    { user_id: 1, messages: 2, last_at: new Date('2026-11-12T05:00:00Z'), full_name: 'Asha Verma', email: 'asha@x.com', is_guest: false, last_user: 'hi', last_assistant: 'hello' },
    { user_id: 3, messages: 1, last_at: new Date('2026-11-11T05:00:00Z'), full_name: 'Guest', email: 'guest_9@x.astroai.com', is_guest: true, last_user: 'yo', last_assistant: null },
  ] });
  const r = await call('GET', '/chats?q=50%25_off&limit=999&days=7');
  assert.equal(r.status, 200);
  assert.equal(r.body.days, 7);
  assert.deepEqual(r.body.conversations[0], { userId: 1, userName: 'Asha Verma', email: 'asha@x.com', messages: 2, lastAt: '2026-11-12T05:00:00.000Z', lastUserMessage: 'hi', lastAssistantMessage: 'hello' });
  assert.equal(r.body.conversations[1].email, null);
  const p = named('chatList')[0].params;
  assert.equal(p[1], '%50\\%\\_off%');
  assert.equal(p[2], 200);
});

test('GET /kundlis returns total and rows', async () => {
  overrides.kundliList = () => ({ rows: [{ user_id: 1, full_name: 'Asha Verma', email: 'asha@x.com', is_guest: false, ascendant: 'Leo', sun_sign: 'Aries', moon_sign: 'Cancer', nakshatra: 'Pushya', place_of_birth: 'Pune', date_of_birth: '1995-04-02', created_at: new Date('2026-10-02T00:00:00Z'), family_count: 2, total: 37 }] });
  const r = await call('GET', '/kundlis?q=pu');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { total: 37, kundlis: [{ userId: 1, userName: 'Asha Verma', email: 'asha@x.com', ascendant: 'Leo', sunSign: 'Aries', moonSign: 'Cancer', nakshatra: 'Pushya', placeOfBirth: 'Pune', dateOfBirth: '1995-04-02', createdAt: '2026-10-02T00:00:00.000Z', familyCount: 2 }] });
  assert.deepEqual(named('kundliList')[0].params, ['%pu%', 100]);
  overrides = {};
  assert.deepEqual((await call('GET', '/kundlis')).body, { total: 0, kundlis: [] });
});

test('GET /audit lists entries newest first, optional userId filter', async () => {
  await call('POST', '/users/1/block', { reason: 'spam' });
  await call('POST', '/users/3/coins', { amount: 5, note: 'hi' });
  const r = await call('GET', '/audit');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.entries.map((e) => [e.action, e.targetUserId]), [['coins', 3], ['block', 1]]);
  assert.deepEqual(Object.keys(r.body.entries[0]).sort(), ['action', 'at', 'details', 'id', 'targetUserId']);
  const f = await call('GET', '/audit?userId=1&limit=9999');
  assert.deepEqual(f.body.entries.map((e) => e.action), ['block']);
  assert.deepEqual(named('auditList').pop().params, [1, 500]);
  assert.equal((await call('GET', '/audit?userId=abc')).status, 400);
});

test('analytics: endpoints, logins and live shapes', async () => {
  overrides = {
    endpointTotals: () => ({ rows: [{ total: 900, today: 40 }] }),
    endpointRoutes: () => ({ rows: [{ method: 'POST', route: '/api/chat', calls: 300, calls_today: 12, users: 25, errors: 3, avg_ms: 812.4, p95_ms: 2100.7 }] }),
    loginsByMethod: () => ({ rows: [{ method: 'google', signups: 4, logins: 20, failed: 0, blocked: 1 }] }),
    loginsDaily: () => ({ rows: [{ day: '2026-11-12', register: 1, login: 5, guest_created: 2, guest_upgraded: 1, failed: 3, blocked: null }] }),
    signupMethods: () => ({ rows: [{ method: 'email', users: 10 }, { method: 'unknown', users: 2 }] }),
    liveCounts: () => ({ rows: [{ requests_5m: 17, users_15m: 4 }] }),
    liveRecent: () => ({ rows: [{ created_at: new Date('2026-11-12T05:00:00Z'), user_id: null, full_name: null, method: 'GET', route: '/api/temples', status: 200, duration_ms: 9, platform: 'web' }] }),
  };
  const e = await call('GET', '/analytics/endpoints?days=7');
  assert.equal(e.status, 200);
  assert.equal(e.body.days, 7);
  assert.equal(e.body.totalRequests, 900);
  assert.equal(e.body.todayRequests, 40);
  assert.match(e.body.start, /^\d{4}-\d{2}-\d{2}$/);
  assert.match(e.body.today, /^\d{4}-\d{2}-\d{2}$/);
  assert.deepEqual(e.body.routes, [{ method: 'POST', route: '/api/chat', calls: 300, callsToday: 12, users: 25, errors: 3, avgMs: 812, p95Ms: 2101 }]);
  assert.match(named('endpointRoutes')[0].sql, /percentile_cont\(0\.95\)/);

  const l = await call('GET', '/analytics/logins?days=500');
  assert.equal(l.body.days, 365);
  assert.deepEqual(l.body.byMethod, [{ method: 'google', signups: 4, logins: 20, failed: 0, blocked: 1 }]);
  assert.deepEqual(l.body.daily, [{ day: '2026-11-12', register: 1, login: 5, guest_created: 2, guest_upgraded: 1, failed: 3, blocked: 0 }]);
  assert.deepEqual(l.body.signupMethods, [{ method: 'email', users: 10 }, { method: 'unknown', users: 2 }]);

  const v = await call('GET', '/analytics/live');
  assert.deepEqual(v.body, { requestsLast5m: 17, activeUsersLast15m: 4, recent: [{ at: '2026-11-12T05:00:00.000Z', userId: null, userName: null, method: 'GET', route: '/api/temples', status: 200, ms: 9, platform: 'web' }] });
});

test('analytics/users rows carry signup/login method, blocked flag and requests in range', async () => {
  overrides = {};
  // untagged query: match by its FROM users u
  const r0 = { id: 5, full_name: 'Asha', email: 'asha@x.com', role: 'user', created_at: new Date('2026-11-01T00:00:00Z'), is_guest: false, signup_method: 'google', last_login_method: 'email', is_blocked: true, requests: 77, calls: 1, tokens: 2, cost: 0.1, last_ai: null, last_seen: null, active_days: 1, platforms: 'web' };
  stub.exports.query = async (text, params) => {
    query(text, params);
    return String(text).includes('FROM users u') ? { rows: [r0] } : { rows: [] };
  };
  try {
    const r = await call('GET', '/analytics/users');
    assert.equal(r.status, 200);
    const u = r.body.users[0];
    assert.equal(u.signupMethod, 'google');
    assert.equal(u.lastLoginMethod, 'email');
    assert.equal(u.isBlocked, true);
    assert.equal(u.requestsInRange, 77);
    assert.equal(u.aiCostUsd, 0.1); // existing fields still there
    assert.match(calls[calls.length - 1].sql, /FROM api_requests WHERE user_id IS NOT NULL/);
  } finally {
    stub.exports.query = async (text, params) => query(text, params, false);
  }
});
