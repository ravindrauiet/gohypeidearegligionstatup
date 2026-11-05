// DELETE /api/auth/account against an in-memory fake db (no real database).
// The fake has NO cascades: every user-linked row must be removed by the route's explicit deletes.
const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve, call } = require('./fake_db');

const fake = install();
const { router: authRouter, signToken } = require('../routes/auth');

// Column(s) in each table that reference users.id.
const USER_COLS = {
  users: ['id'],
  birth_details: ['user_id'], kundlis: ['user_id'], family_kundlis: ['user_id'], chat_messages: ['user_id'],
  daily_horoscopes: ['user_id'], pandits: ['user_id'], consultation_queue: ['user_id'], pandit_reviews: ['user_id'],
  consultation_prescriptions: ['user_id'], wallet_transactions: ['user_id'], consultation_messages: ['sender_user_id'],
  forecast_cache: ['user_id'], game_profiles: ['user_id'], game_mission_log: ['user_id'], game_cards: ['user_id'],
  game_set_claims: ['user_id'], moksha_players: ['user_id'], moksha_moves: ['user_id'],
  friend_links: ['user_id', 'friend_user_id'], coin_ledger: ['user_id'], mindset_answers: ['user_id'],
  buddy_profiles: ['user_id'], buddy_connections: ['from_user_id', 'to_user_id'], buddy_messages: ['sender_id'],
  buddy_blocks: ['user_id', 'blocked_user_id'], buddy_reports: ['reporter_id', 'reported_user_id'],
  trip_requests: ['user_id', 'buddy_user_id'],
  device_tokens: ['user_id'], notifications: ['user_id'], broadcast_reads: ['user_id'], notification_prefs: ['user_id'],
};

let db; // table name -> rows
let failOn = null; // SQL substring that makes the fake throw (to test rollback)

function seed({ skipTables = [] } = {}) {
  db = {};
  for (const t of Object.keys(USER_COLS)) if (!skipTables.includes(t)) db[t] = [];
  for (const id of [1, 2]) {
    db.users.push({ id, role: 'user', full_name: `User ${id}` });
    for (const t of Object.keys(USER_COLS)) {
      if (!db[t] || t === 'users' || t === 'consultation_messages' || t === 'buddy_messages') continue;
      const row = { id: db[t].length + 1 };
      for (const c of USER_COLS[t]) row[c] = id;
      if (USER_COLS[t].length === 2) row[USER_COLS[t][1]] = id === 1 ? 2 : 1; // pair rows link both users
      db[t].push(row);
    }
  }
  db.users.push({ id: 3, role: 'guest', full_name: 'Guest User' });
  db.users.push({ id: 4, role: 'pandit', full_name: 'Pt. Test' });
  if (db.consultation_queue) {
    db.consultation_queue.push({ id: 99, user_id: 2 }); // user 2's session
    if (db.consultation_messages) {
      db.consultation_messages.push({ id: 1, session_id: db.consultation_queue[0].id, sender_user_id: 1 });
      db.consultation_messages.push({ id: 2, session_id: 99, sender_user_id: 1 }); // user 1 wrote in user 2's session
      db.consultation_messages.push({ id: 3, session_id: 99, sender_user_id: 2 });
    }
  }
  if (db.buddy_messages && db.buddy_connections) {
    const conn = db.buddy_connections[0].id;
    db.buddy_messages.push({ id: 1, connection_id: conn, sender_id: 2 }); // other user's message in user 1's chat
  }
}

const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
const refs = (row, cols, uid) => cols.some((c) => row[c] === uid);

async function query(text, params = []) {
  const sql = norm(text);
  const [uid] = params;
  if (failOn && sql.includes(failOn)) throw new Error('boom');
  if (sql.startsWith('SELECT role FROM users WHERE id = $1')) {
    const u = db.users.find((x) => x.id === uid);
    return { rows: u ? [{ role: u.role }] : [] };
  }
  if (sql.startsWith('SELECT id, role FROM users WHERE id = $1 FOR UPDATE')) {
    return { rows: db.users.filter((u) => u.id === uid).map((u) => ({ id: u.id, role: u.role })) };
  }
  if (sql.includes('FROM information_schema.tables')) {
    return { rows: params[0].filter((t) => db[t]).map((t) => ({ table_name: t })) };
  }
  let m = sql.match(/^DELETE FROM buddy_messages WHERE sender_id = \$1 OR connection_id IN \(SELECT id FROM buddy_connections WHERE from_user_id = \$1 OR to_user_id = \$1\)$/);
  if (m) {
    const conns = (db.buddy_connections || []).filter((c) => c.from_user_id === uid || c.to_user_id === uid).map((c) => c.id);
    db.buddy_messages = db.buddy_messages.filter((r) => !(r.sender_id === uid || conns.includes(r.connection_id)));
    return { rows: [] };
  }
  m = sql.match(/^DELETE FROM consultation_messages WHERE session_id IN \(SELECT id FROM consultation_queue WHERE user_id = \$1\)$/);
  if (m) {
    const sess = (db.consultation_queue || []).filter((c) => c.user_id === uid).map((c) => c.id);
    db.consultation_messages = db.consultation_messages.filter((r) => !sess.includes(r.session_id));
    return { rows: [] };
  }
  m = sql.match(/^DELETE FROM (\w+) WHERE (\w+) = \$1(?: OR (\w+) = \$1)?$/);
  if (m) {
    const [, table, c1, c2] = m;
    if (!db[table]) throw Object.assign(new Error(`relation "${table}" does not exist`), { code: '42P01' });
    db[table] = db[table].filter((r) => !refs(r, [c1, c2].filter(Boolean), uid));
    return { rows: [] };
  }
  m = sql.match(/^UPDATE (\w+) SET (\w+) = NULL WHERE (\w+) = \$1$/);
  if (m && m[2] === m[3]) {
    if (!db[m[1]]) throw Object.assign(new Error(`relation "${m[1]}" does not exist`), { code: '42P01' });
    for (const r of db[m[1]]) if (r[m[2]] === uid) r[m[2]] = null;
    return { rows: [] };
  }
  throw new Error(`account fake: unhandled SQL: ${sql}`);
}

fake.query = query;
fake.withTransaction = async (fn) => {
  const snap = JSON.stringify(db);
  try {
    return await fn({ query });
  } catch (err) {
    db = JSON.parse(snap);
    throw err;
  }
};

function remainingFor(uid) {
  const out = [];
  for (const [t, rows] of Object.entries(db)) {
    for (const r of rows) if (refs(r, USER_COLS[t], uid)) out.push(t);
  }
  return out;
}

let srv;
test.before(async () => { srv = await serve(authRouter, '/api/auth'); });
test.after(async () => { await srv.close(); });
test.beforeEach(() => { failOn = null; seed(); });

const tokenFor = (id, role = 'user') => signToken({ userId: id, email: `u${id}@x.com`, role });

test('requires a token', async () => {
  const r = await call(srv.url, 'DELETE', '/account', { body: { confirm: 'DELETE' } });
  assert.equal(r.status, 401);
  assert.ok(db.users.find((u) => u.id === 1));
});

test('requires confirm: "DELETE"', async () => {
  for (const body of [undefined, {}, { confirm: 'delete' }, { confirm: true }, { confirm: 'YES' }]) {
    const r = await call(srv.url, 'DELETE', '/account', { token: tokenFor(1), body });
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.body.code, 'CONFIRM_REQUIRED');
  }
  assert.equal(remainingFor(1).length > 5, true, 'nothing deleted');
});

test('deletes the user and every user-linked row without relying on cascades', async () => {
  const before2 = remainingFor(2).length;
  const r = await call(srv.url, 'DELETE', '/account', { token: tokenFor(1), body: { confirm: 'DELETE' } });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { success: true });
  assert.deepEqual(remainingFor(1), [], 'no row still references user 1');
  assert.equal(db.users.find((u) => u.id === 1), undefined);
  // Messages inside user 1's chats/sessions are gone, including the other person's side
  assert.equal(db.buddy_messages.length, 0);
  assert.deepEqual(db.consultation_messages.map((m) => m.id).sort(), [2, 3]);
  assert.equal(db.consultation_messages.find((m) => m.id === 2).sender_user_id, null, 'anonymised in user 2 session');
  // User 2 keeps their own rows; only shared pair rows (connections, blocks, ...) went away
  assert.ok(db.users.find((u) => u.id === 2));
  for (const t of ['birth_details', 'kundlis', 'coin_ledger', 'buddy_profiles', 'chat_messages', 'game_profiles']) {
    assert.equal(db[t].filter((x) => x.user_id === 2).length, 1, t);
  }
  assert.ok(remainingFor(2).length < before2);
  // User 2's trip that named user 1 as buddy is kept with the buddy cleared
  const trip2 = db.trip_requests.find((x) => x.user_id === 2);
  assert.ok(trip2);
  assert.equal(trip2.buddy_user_id, null);
});

test('second call after deletion: 404 (registered token) and nothing else touched', async () => {
  await call(srv.url, 'DELETE', '/account', { token: tokenFor(1), body: { confirm: 'DELETE' } });
  const again = await call(srv.url, 'DELETE', '/account', { token: tokenFor(1), body: { confirm: 'DELETE' } });
  assert.equal(again.status, 404);
  assert.ok(db.users.find((u) => u.id === 2));
});

test('guest accounts can delete themselves', async () => {
  const r = await call(srv.url, 'DELETE', '/account', { token: tokenFor(3, 'guest'), body: { confirm: 'DELETE' } });
  assert.equal(r.status, 200);
  assert.equal(db.users.find((u) => u.id === 3), undefined);
});

test('pandit accounts are refused (would cascade into seekers\' history)', async () => {
  const r = await call(srv.url, 'DELETE', '/account', { token: tokenFor(4, 'pandit'), body: { confirm: 'DELETE' } });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'PANDIT_ACCOUNT');
  assert.ok(db.users.find((u) => u.id === 4));
});

test('tables missing from an older database are skipped', async () => {
  seed({ skipTables: ['game_profiles', 'moksha_moves', 'buddy_messages', 'trip_requests', 'consultation_messages'] });
  const r = await call(srv.url, 'DELETE', '/account', { token: tokenFor(1), body: { confirm: 'DELETE' } });
  assert.equal(r.status, 200);
  assert.deepEqual(remainingFor(1), []);
});

test('a failure rolls everything back', async () => {
  failOn = 'DELETE FROM users WHERE id = $1';
  const r = await call(srv.url, 'DELETE', '/account', { token: tokenFor(1), body: { confirm: 'DELETE' } });
  assert.equal(r.status, 500);
  assert.ok(db.users.find((u) => u.id === 1));
  assert.equal(db.coin_ledger.filter((x) => x.user_id === 1).length, 1);
  assert.equal(db.buddy_messages.length, 1);
});

test('every user-referencing table in schema.sql without a cascade is covered by the delete steps', () => {
  const fs = require('fs');
  const path = require('path');
  const sql = fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8');
  const covered = new Set(authRouter._accountDeleteSteps.map(([t]) => t));
  const re = /CREATE TABLE IF NOT EXISTS (\w+) \(([\s\S]*?)\n\);/g;
  let m;
  const missing = [];
  while ((m = re.exec(sql))) {
    const userRefs = m[2].split('\n').filter((l) => /REFERENCES users\(id\)/.test(l));
    const uncascaded = userRefs.some((l) => !/ON DELETE (CASCADE|SET NULL)/.test(l));
    if (m[1] !== 'users' && uncascaded && !covered.has(m[1])) missing.push(m[1]);
  }
  // The tables that existed before cascades were relied on are all handled explicitly.
  for (const t of ['birth_details', 'kundlis', 'chat_messages', 'pandits', 'wallet_transactions', 'coin_ledger', 'buddy_profiles', 'trip_requests']) {
    assert.ok(covered.has(t), t);
  }
  assert.deepEqual(missing, [], 'add these tables to ACCOUNT_DELETE_STEPS in routes/auth.js');
});
