// /api/admin routes + GET /admin page against an in-memory fake db (no real database).
const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve } = require('./fake_db');

const fake = install();
const C = require('../services/coins_service');
const adminRouter = require('../routes/admin');
// Record push events instead of sending them.
const push = require('../services/push_service');
const pushed = [];
let topicResult = { sent: true };
push.sendToUser = async (userId, msg, opts) => { pushed.push({ userId, ...msg, opts }); return {}; };
push.sendToTopic = async (topic, msg) => { pushed.push({ topic, ...msg }); return topicResult; };

const KEY = 'test-admin-key-0123456789abcdef';
process.env.ADMIN_KEY = KEY;

let s; // store
function seed() {
  s = {
    users: [
      { id: 1, full_name: 'Asha Verma', email: 'asha@x.com', role: 'user' },
      { id: 2, full_name: 'Ravi Kumar', email: 'ravi@x.com', role: 'user' },
      { id: 3, full_name: 'Guest User', email: 'g@guest', role: 'guest' },
    ],
    buddy_profiles: [
      { user_id: 1, display_name: 'Asha', is_active: true, show_nearby: true, banned_at: null },
      { user_id: 2, display_name: 'Ravi', is_active: true, show_nearby: true, banned_at: null },
    ],
    trip_requests: [
      { id: 1, user_id: 1, buddy_user_id: 2, temple_id: 'tirupati', preferred_month: '2026-12', status: 'pending', coins_spent: 10000, note: null, created_at: new Date('2026-11-01T00:00:00Z'), updated_at: null },
      { id: 2, user_id: 2, buddy_user_id: 1, temple_id: 'kedarnath', preferred_month: '2027-05', status: 'pending', coins_spent: 10000, note: null, created_at: new Date('2026-11-02T00:00:00Z'), updated_at: null },
      { id: 3, user_id: 1, buddy_user_id: 2, temple_id: 'tirupati', preferred_month: '2026-12', status: 'cancelled', coins_spent: 10000, note: null, created_at: new Date('2026-10-01T00:00:00Z'), updated_at: null },
    ],
    buddy_reports: [
      { id: 1, reporter_id: 1, reported_user_id: 2, reason: 'harassment', details: '<b>rude</b>', status: 'open', created_at: new Date('2026-11-03T00:00:00Z'), resolved_at: null },
      { id: 2, reporter_id: 3, reported_user_id: 2, reason: 'spam', details: null, status: 'open', created_at: new Date('2026-11-04T00:00:00Z'), resolved_at: null },
      { id: 3, reporter_id: 2, reported_user_id: 1, reason: 'fake', details: null, status: 'open', created_at: new Date('2026-11-04T01:00:00Z'), resolved_at: null },
    ],
    broadcasts: [],
    coin_ledger: [
      { id: 1, user_id: 1, amount: 20000, reason: 'question', ref: 'seed', created_at: new Date() },
      { id: 2, user_id: 1, amount: -10000, reason: 'trip', ref: 'trip:1', created_at: new Date() },
      { id: 3, user_id: 2, amount: -10000, reason: 'trip', ref: 'trip:2', created_at: new Date() },
      { id: 4, user_id: 1, amount: 10000, reason: 'trip_refund', ref: 'trip:3', created_at: new Date() },
    ],
  };
}

const norm = (x) => String(x).replace(/\s+/g, ' ').trim();
const userBy = (id) => s.users.find((u) => u.id === id) || {};
const profileBy = (id) => s.buddy_profiles.find((b) => b.user_id === id) || {};

function tripRow(t) {
  return {
    ...t,
    owner_full_name: userBy(t.user_id).full_name, owner_email: userBy(t.user_id).email, owner_display_name: profileBy(t.user_id).display_name,
    buddy_full_name: userBy(t.buddy_user_id).full_name, buddy_email: userBy(t.buddy_user_id).email, buddy_display_name: profileBy(t.buddy_user_id).display_name,
  };
}
function reportRow(r) {
  return {
    ...r,
    reporter_full_name: userBy(r.reporter_id).full_name, reporter_email: userBy(r.reporter_id).email, reporter_display_name: profileBy(r.reporter_id).display_name,
    reported_full_name: userBy(r.reported_user_id).full_name, reported_email: userBy(r.reported_user_id).email, reported_display_name: profileBy(r.reported_user_id).display_name,
    reported_profile_active: profileBy(r.reported_user_id).is_active,
  };
}

async function query(text, p = []) {
  const sql = norm(text);
  if (sql.includes('FROM trip_requests t')) {
    if (sql.endsWith('WHERE t.id = $1')) return { rows: s.trip_requests.filter((t) => t.id === p[0]).map(tripRow) };
    if (sql.includes('WHERE t.status = $1')) return { rows: s.trip_requests.filter((t) => t.status === p[0]).sort((a, b) => a.id - b.id).map(tripRow) };
    return { rows: [...s.trip_requests].sort((a, b) => b.id - a.id).map(tripRow) };
  }
  if (sql === 'SELECT * FROM trip_requests WHERE id = $1 FOR UPDATE') return { rows: s.trip_requests.filter((t) => t.id === p[0]).map((t) => ({ ...t })) };
  if (sql === 'SELECT id FROM users WHERE id = $1 FOR UPDATE') return { rows: s.users.filter((u) => u.id === p[0]).map((u) => ({ id: u.id })) };
  if (sql.startsWith('UPDATE trip_requests SET status = $2, note = COALESCE($3, note)')) {
    const t = s.trip_requests.find((x) => x.id === p[0]);
    t.status = p[1];
    if (p[2] !== null) t.note = p[2];
    t.updated_at = new Date();
    return { rows: [] };
  }
  if (sql.startsWith('INSERT INTO coin_ledger')) {
    const [userId, amount, reason, ref, note] = p;
    if (s.coin_ledger.some((r) => r.user_id === userId && r.reason === reason && r.ref === ref)) return { rows: [] };
    const row = { id: s.coin_ledger.length + 1, user_id: userId, amount, reason, ref, note, created_at: new Date() };
    s.coin_ledger.push(row);
    return { rows: [{ id: row.id }] };
  }
  if (sql.startsWith('SELECT COALESCE(SUM(amount), 0) AS balance FROM coin_ledger')) {
    return { rows: [{ balance: s.coin_ledger.filter((r) => r.user_id === p[0]).reduce((a, r) => a + r.amount, 0) }] };
  }
  if (sql.includes('FROM buddy_reports r')) {
    if (sql.endsWith('WHERE r.id = $1')) return { rows: s.buddy_reports.filter((r) => r.id === p[0]).map(reportRow) };
    if (sql.includes('WHERE r.status = $1')) return { rows: s.buddy_reports.filter((r) => r.status === p[0]).sort((a, b) => a.id - b.id).map(reportRow) };
    return { rows: [...s.buddy_reports].sort((a, b) => b.id - a.id).map(reportRow) };
  }
  if (sql === 'SELECT id, reported_user_id, status FROM buddy_reports WHERE id = $1 FOR UPDATE') {
    return { rows: s.buddy_reports.filter((r) => r.id === p[0]).map(({ id, reported_user_id, status }) => ({ id, reported_user_id, status })) };
  }
  if (sql.startsWith('UPDATE buddy_profiles SET is_active = FALSE, show_nearby = FALSE')) {
    const bp = s.buddy_profiles.find((b) => b.user_id === p[0]);
    if (!bp) return { rows: [] };
    Object.assign(bp, { is_active: false, show_nearby: false, banned_at: bp.banned_at || new Date() });
    return { rows: [{ user_id: bp.user_id }] };
  }
  if (sql.startsWith("UPDATE buddy_reports SET status = 'banned'")) {
    for (const r of s.buddy_reports) {
      if (r.id === p[0] || (r.reported_user_id === p[1] && r.status === 'open')) Object.assign(r, { status: 'banned', resolved_at: new Date() });
    }
    return { rows: [] };
  }
  if (sql.startsWith("UPDATE buddy_reports SET status = 'dismissed'")) {
    Object.assign(s.buddy_reports.find((r) => r.id === p[0]), { status: 'dismissed', resolved_at: new Date() });
    return { rows: [] };
  }
  if (sql.startsWith('SELECT (SELECT COUNT(*) FROM users')) {
    return { rows: [{
      users: s.users.filter((u) => u.role !== 'guest').length,
      guests: s.users.filter((u) => u.role === 'guest').length,
      buddy_profiles: s.buddy_profiles.length,
      active_buddy_profiles: s.buddy_profiles.filter((b) => b.is_active).length,
      pending_trips: s.trip_requests.filter((t) => t.status === 'pending').length,
      open_reports: s.buddy_reports.filter((r) => r.status === 'open').length,
      coins_issued_today: s.coin_ledger.filter((r) => r.amount > 0 && r.reason !== 'trip_refund').reduce((a, r) => a + r.amount, 0),
    }] };
  }
  if (sql.startsWith('INSERT INTO broadcasts (title, body, data) VALUES ($1, $2, $3::jsonb)')) {
    const row = { id: s.broadcasts.length + 1, title: p[0], body: p[1], data: JSON.parse(p[2]), created_at: new Date() };
    s.broadcasts.push(row);
    return { rows: [{ ...row }] };
  }
  if (sql === 'SELECT id, title, body, data, created_at FROM broadcasts ORDER BY id DESC LIMIT 50') {
    return { rows: [...s.broadcasts].sort((a, b) => b.id - a.id).slice(0, 50) };
  }
  throw new Error(`admin fake: unhandled SQL: ${sql}`);
}
fake.query = query;
fake.withTransaction = async (fn) => {
  const snap = JSON.stringify(s);
  try {
    return await fn({ query });
  } catch (err) {
    s = JSON.parse(snap);
    throw err;
  }
};

let srv;
let pageSrv;
test.before(async () => {
  srv = await serve(adminRouter, '/api/admin');
  const express = require('express');
  const app = express();
  app.get('/admin', adminRouter.page);
  pageSrv = await new Promise((resolve) => { const x = app.listen(0, '127.0.0.1', () => resolve(x)); });
});
test.after(async () => {
  await srv.close();
  await new Promise((r) => pageSrv.close(r));
});
test.beforeEach(() => { process.env.ADMIN_KEY = KEY; seed(); pushed.length = 0; topicResult = { sent: true }; });

async function admin(method, path, { key = KEY, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (key !== null) headers['x-admin-key'] = key;
  const res = await fetch(srv.url + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  let json = null;
  try { json = await res.json(); } catch (_) { /* empty */ }
  return { status: res.status, body: json, headers: res.headers };
}
const balance = (uid) => s.coin_ledger.filter((r) => r.user_id === uid).reduce((a, r) => a + r.amount, 0);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------
test('admin key: missing -> 401, wrong -> 401, correct -> 200', async () => {
  assert.equal((await admin('GET', '/stats', { key: null })).status, 401);
  assert.equal((await admin('GET', '/stats', { key: '' })).status, 401);
  assert.equal((await admin('GET', '/stats', { key: KEY.slice(0, -1) })).status, 401);
  assert.equal((await admin('GET', '/stats', { key: KEY + 'x' })).status, 401);
  const ok = await admin('GET', '/stats');
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get('cache-control'), 'no-store');
});

test('ADMIN_KEY too short -> 503 admin disabled, even with a matching header', async () => {
  process.env.ADMIN_KEY = 'short';
  const r = await admin('GET', '/trips', { key: 'short' });
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'admin disabled');
  assert.equal(s.trip_requests[0].status, 'pending');
});

test('ADMIN_KEY unset or blank -> the built-in password (and only it) works', async () => {
  adminRouter._internals.failures.clear();
  for (const env of [undefined, '   ']) {
    if (env === undefined) delete process.env.ADMIN_KEY; else process.env.ADMIN_KEY = env;
    assert.equal((await admin('GET', '/stats', { key: 'RavindraIIT' })).status, 200);
    assert.equal((await admin('GET', '/stats', { key: 'ravindraiit' })).status, 401);
    assert.equal((await admin('GET', '/stats', { key: '' })).status, 401);
    assert.equal((await admin('POST', '/trips/1/status', { key: '   ', body: { status: 'rejected' } })).status, 401);
  }
  assert.equal(s.trip_requests[0].status, 'pending');
  adminRouter._internals.failures.clear();
});

test('keysMatch is exact', () => {
  const { keysMatch } = adminRouter._internals;
  assert.equal(keysMatch('abc', 'abc'), true);
  assert.equal(keysMatch('abc', 'abd'), false);
  assert.equal(keysMatch('abc', 'abcd'), false);
});

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------
test('GET /stats returns the counts', async () => {
  const r = await admin('GET', '/stats');
  assert.equal(r.status, 200);
  assert.equal(r.body.users, 2);
  assert.equal(r.body.guests, 1);
  assert.equal(r.body.buddyProfiles, 2);
  assert.equal(r.body.pendingTrips, 2);
  assert.equal(r.body.openReports, 3);
  assert.equal(r.body.coinsIssuedToday, 20000, 'refunds are not "issued"');
  assert.match(r.body.date, /^\d{4}-\d{2}-\d{2}$/);
});

// ---------------------------------------------------------------------------
// Trips
// ---------------------------------------------------------------------------
test('GET /trips lists by status with both people and the temple', async () => {
  const r = await admin('GET', '/trips?status=pending');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.trips.map((t) => t.id), [1, 2]);
  const t = r.body.trips[0];
  assert.equal(t.temple.id, 'tirupati');
  assert.ok(t.temple.name && t.temple.name !== 'tirupati');
  assert.deepEqual(t.user, { userId: 1, name: 'Asha', fullName: 'Asha Verma', email: 'asha@x.com' });
  assert.equal(t.buddy.email, 'ravi@x.com');
  assert.equal((await admin('GET', '/trips')).body.trips.length, 3);
  assert.equal((await admin('GET', '/trips?status=all')).body.trips.length, 3);
  assert.equal((await admin('GET', '/trips?status=bogus')).status, 400);
});

test('reject refunds the held coins exactly once', async () => {
  assert.equal(balance(1), 20000);
  const r = await admin('POST', '/trips/1/status', { body: { status: 'rejected', note: '  Temple closed  that month ' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.trip.status, 'rejected');
  assert.equal(r.body.trip.note, 'Temple closed that month');
  assert.equal(r.body.refunded, 10000);
  assert.equal(balance(1), 30000);
  const refunds = s.coin_ledger.filter((x) => x.user_id === 1 && x.ref === 'trip:1:rejected');
  assert.equal(refunds.length, 1);
  assert.equal(refunds[0].reason, 'trip_refund');

  // Retried / double-clicked reject: no second refund
  const again = await admin('POST', '/trips/1/status', { body: { status: 'rejected' } });
  assert.equal(again.status, 200);
  assert.equal(again.body.unchanged, true);
  assert.equal(again.body.refunded, 0);
  assert.equal(balance(1), 30000);
  // Concurrent rejects also pay once
  await Promise.all([1, 2, 3].map(() => admin('POST', '/trips/2/status', { body: { status: 'rejected' } })));
  assert.equal(s.coin_ledger.filter((x) => x.ref === 'trip:2:rejected').length, 1);
  assert.equal(balance(2), 0);
  // A rejected trip is final
  assert.equal((await admin('POST', '/trips/1/status', { body: { status: 'approved' } })).status, 409);
});

test('approve -> completed, no coins move; illegal transitions are refused', async () => {
  const before = s.coin_ledger.length;
  let r = await admin('POST', '/trips/1/status', { body: { status: 'approved' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.trip.status, 'approved');
  assert.equal(r.body.refunded, 0);
  r = await admin('POST', '/trips/1/status', { body: { status: 'completed' } });
  assert.equal(r.body.trip.status, 'completed');
  assert.equal(s.coin_ledger.length, before);
  // completed is final
  r = await admin('POST', '/trips/1/status', { body: { status: 'rejected' } });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'BAD_TRANSITION');
  assert.equal(balance(1), 20000, 'unchanged');
  // pending -> completed skips approval
  assert.equal((await admin('POST', '/trips/2/status', { body: { status: 'completed' } })).status, 409);
  // a user-cancelled trip (already refunded) cannot be rejected for a second refund
  r = await admin('POST', '/trips/3/status', { body: { status: 'rejected' } });
  assert.equal(r.status, 409);
  assert.equal(s.coin_ledger.filter((x) => String(x.ref).startsWith('trip:3')).length, 1);
});

test('approved trips can still be rejected, with a refund', async () => {
  await admin('POST', '/trips/1/status', { body: { status: 'approved' } });
  const r = await admin('POST', '/trips/1/status', { body: { status: 'rejected' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.refunded, 10000);
});

test('trip status validation', async () => {
  assert.equal((await admin('POST', '/trips/1/status', { body: { status: 'cancelled' } })).status, 400);
  assert.equal((await admin('POST', '/trips/1/status', { body: {} })).status, 400);
  assert.equal((await admin('POST', '/trips/999/status', { body: { status: 'approved' } })).status, 404);
  assert.equal((await admin('POST', '/trips/abc/status', { body: { status: 'approved' } })).status, 404);
  assert.equal(s.trip_requests[0].status, 'pending');
});

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------
test('GET /reports defaults to open, with names and reasons', async () => {
  const r = await admin('GET', '/reports');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.reports.map((x) => x.id), [1, 2, 3]);
  const first = r.body.reports[0];
  assert.equal(first.reason, 'harassment');
  assert.equal(first.reporter.name, 'Asha');
  assert.equal(first.reported.name, 'Ravi');
  assert.equal(first.reported.email, 'ravi@x.com');
  assert.equal(first.reported.profileActive, true);
  assert.equal(r.body.reports[1].reporter.name, 'Guest User', 'falls back to full name without a buddy profile');
  assert.equal((await admin('GET', '/reports?status=nope')).status, 400);
});

test('dismiss closes only that report', async () => {
  const r = await admin('POST', '/reports/1/resolve', { body: { action: 'dismiss' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.report.status, 'dismissed');
  assert.ok(r.body.report.resolvedAt);
  assert.equal(r.body.profileHidden, false);
  assert.equal(s.buddy_reports.find((x) => x.id === 2).status, 'open');
  assert.equal(profileBy(2).is_active, true);
  const open = await admin('GET', '/reports?status=open');
  assert.deepEqual(open.body.reports.map((x) => x.id), [2, 3]);
});

test('ban hides the reported buddy profile and closes their open reports', async () => {
  const r = await admin('POST', '/reports/1/resolve', { body: { action: 'ban' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.profileHidden, true);
  assert.equal(r.body.report.status, 'banned');
  assert.equal(r.body.report.reported.profileActive, false);
  const bp = profileBy(2);
  assert.equal(bp.is_active, false);
  assert.equal(bp.show_nearby, false);
  assert.ok(bp.banned_at);
  assert.equal(s.buddy_reports.find((x) => x.id === 2).status, 'banned', 'other open report on same user closed');
  assert.equal(s.buddy_reports.find((x) => x.id === 3).status, 'open', 'reports about other people untouched');
  assert.equal(profileBy(1).is_active, true);
  assert.equal((await admin('GET', '/stats')).body.openReports, 1);
});

test('report resolve validation', async () => {
  assert.equal((await admin('POST', '/reports/1/resolve', { body: { action: 'delete' } })).status, 400);
  assert.equal((await admin('POST', '/reports/999/resolve', { body: { action: 'dismiss' } })).status, 404);
  assert.equal((await admin('POST', '/reports/1/resolve', { key: 'wrong', body: { action: 'ban' } })).status, 401);
  assert.equal(profileBy(2).is_active, true);
});

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
test('GET /admin serves the self-contained page without needing the key', async () => {
  const res = await fetch(`http://127.0.0.1:${pageSrv.address().port}/admin`);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  assert.match(res.headers.get('x-robots-tag'), /noindex/);
  assert.match(res.headers.get('content-security-policy'), /connect-src 'self'/);
  const html = await res.text();
  assert.match(html, /<title>CosmicGuide Admin<\/title>/);
  assert.match(html, /x-admin-key/);
  assert.match(html, /sessionStorage/);
  assert.doesNotMatch(html, /<script[^>]+src=|<link[^>]+href=["']?https?:/i, 'no external dependencies');
  assert.doesNotMatch(html, /innerHTML/, 'user text is rendered with textContent only');
});

test('constants stay aligned with the coins service', () => {
  assert.equal(C.TRIP_COST, 10000);
  assert.equal(adminRouter._internals.refundRef(7), 'trip:7:rejected');
  assert.equal(adminRouter._internals.REFUND_REASON, 'trip_refund');
});

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
test('trip status changes notify the requester and the buddy (after commit, not when unchanged)', async () => {
  let r = await admin('POST', '/trips/1/status', { body: { status: 'approved' } });
  assert.equal(r.status, 200);
  assert.deepEqual(pushed.map((x) => [x.userId, x.type, x.data.tripId, x.data.status, x.opts.pref]), [
    [1, 'trip_update', 1, 'approved', 'trips'],
    [2, 'trip_update', 1, 'approved', 'trips'],
  ]);
  assert.match(pushed[0].body, /Your trip to Sri Venkateswara Temple, Tirumala is approved/);
  pushed.length = 0;
  // same status again with only a note: no notification
  await admin('POST', '/trips/1/status', { body: { status: 'approved', note: 'call on Monday' } });
  assert.equal(pushed.length, 0);
  // rejection tells the requester about the refund, the buddy only about the outcome
  r = await admin('POST', '/trips/1/status', { body: { status: 'rejected' } });
  assert.equal(r.body.refunded, 10000);
  assert.match(pushed[0].body, /10,000 coins were refunded/);
  assert.doesNotMatch(pushed[1].body, /refunded/);
  pushed.length = 0;
  // illegal transition: nothing sent
  assert.equal((await admin('POST', '/trips/3/status', { body: { status: 'approved' } })).status, 409);
  assert.equal(pushed.length, 0);
});

test('trip without a buddy notifies only the requester', async () => {
  s.trip_requests[1].buddy_user_id = null;
  await admin('POST', '/trips/2/status', { body: { status: 'approved' } });
  assert.deepEqual(pushed.map((x) => x.userId), [2]);
});

test('POST /broadcast needs the admin key, validates, stores one row and sends to the topic', async () => {
  assert.equal((await admin('POST', '/broadcast', { key: null, body: { title: 'Hi', body: 'There' } })).status, 401);
  assert.equal((await admin('GET', '/broadcasts', { key: 'wrong-key-0123456789abc' })).status, 401);
  assert.equal(s.broadcasts.length, 0);
  assert.equal((await admin('POST', '/broadcast', { body: { title: '', body: 'x' } })).body.code, 'BAD_TITLE');
  assert.equal((await admin('POST', '/broadcast', { body: { title: 'x'.repeat(81), body: 'x' } })).body.code, 'BAD_TITLE');
  assert.equal((await admin('POST', '/broadcast', { body: { title: 'x', body: 'y'.repeat(301) } })).body.code, 'BAD_BODY');
  assert.equal((await admin('POST', '/broadcast', { body: { title: 'x', body: 'y', data: 'nope' } })).body.code, 'BAD_DATA');
  assert.equal((await admin('POST', '/broadcast', { body: { title: 'x', body: 'y', data: { type: 'coins' } } })).body.code, 'BAD_DATA');
  assert.equal((await admin('POST', '/broadcast', { body: { title: 'x', body: 'y', data: { url: 'javascript:alert(1)' } } })).body.code, 'BAD_DATA');
  assert.equal(pushed.length, 0);

  let r = await admin('POST', '/broadcast', { body: { title: '  Diwali   special ', body: 'Double coins today', data: { url: 'https://example.com/d' } } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.pushed, true);
  assert.equal(r.body.broadcast.id, 'b:1');
  assert.equal(r.body.broadcast.title, 'Diwali special');
  assert.deepEqual(r.body.broadcast.data, { url: 'https://example.com/d' });
  assert.deepEqual(pushed, [{ topic: 'announcements', type: 'announcement', title: 'Diwali special', body: 'Double coins today', data: { url: 'https://example.com/d', broadcastId: 'b:1' } }]);

  topicResult = { sent: false, skipped: 'disabled' };
  r = await admin('POST', '/broadcast', { body: { title: 'Second', body: 'Still stored without Firebase' } });
  assert.equal(r.body.pushed, false);
  assert.equal(s.broadcasts.length, 2);

  r = await admin('GET', '/broadcasts');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.broadcasts.map((b) => b.id), ['b:2', 'b:1']);
  assert.ok(r.body.broadcasts[0].createdAt);
});

test('admin page has the announcement composer', async () => {
  const html = await (await fetch(`http://127.0.0.1:${pageSrv.address().port}/admin`)).text();
  assert.match(html, /Send announcement/);
  assert.match(html, /maxlength="80"/);
  assert.match(html, /maxlength="300"/);
  assert.ok(html.includes("'/broadcast'"));
  assert.ok(html.includes('confirm('));
});
