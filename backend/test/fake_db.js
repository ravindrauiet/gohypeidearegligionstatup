// In-memory stand-in for ../db used by the coins / trips / videos route tests.
// It installs itself in require.cache BEFORE any route is loaded, so the real Postgres pool
// (and backend/.env) is never touched. Only the SQL shapes used by those routes are supported;
// anything else throws so a changed query fails loudly in tests.
const path = require('path');
const Module = require('module');

const DB_PATH = path.join(__dirname, '..', 'db.js');

function createStore() {
  return {
    ledger: [],
    answers: new Map(), // `${userId}:${qid}` -> optionIndex
    users: new Map(), // id -> {role, full_name}
    buddyProfiles: new Map(), // id -> {lat, lng, display_name}
    birth: new Map(), // id -> {latitude, longitude}
    connections: [], // {from_user_id, to_user_id, status}
    blocks: [], // {user_id, blocked_user_id}
    trips: [],
    log: [],
  };
}

function makeQuery(store) {
  return async function query(text, params = []) {
    const sql = String(text).replace(/\s+/g, ' ').trim();
    store.log.push(sql);
    const p = params;

    // --- auth.js guest check
    if (sql.startsWith('SELECT role FROM users WHERE id = $1')) {
      const u = store.users.get(p[0]);
      return { rows: u ? [{ role: u.role }] : [] };
    }

    // --- auth.js admin-dashboard tracking (best-effort writes) + blocked-user cache
    if (sql.startsWith('INSERT INTO auth_events')) {
      (store.authEvents = store.authEvents || []).push({ user_id: p[0], event: p[1], method: p[2], platform: p[3] });
      return { rows: [] };
    }
    if (sql.startsWith('UPDATE users SET signup_method = COALESCE($2, signup_method)')) return { rows: [] };
    if (sql === 'SELECT id FROM users WHERE is_blocked') {
      return { rows: [...store.users].filter(([, u]) => u.is_blocked).map(([id]) => ({ id })) };
    }

    // --- coin_ledger
    if (sql.startsWith('INSERT INTO coin_ledger')) {
      const [userId, amount, reason, ref, note] = p;
      if (store.ledger.some((r) => r.user_id === userId && r.reason === reason && r.ref === ref)) return { rows: [] };
      const row = { id: store.ledger.length + 1, user_id: userId, amount, reason, ref, note, created_at: new Date() };
      store.ledger.push(row);
      return { rows: [{ id: row.id }] };
    }
    if (sql.startsWith('SELECT COALESCE(SUM(amount), 0) AS balance FROM coin_ledger')) {
      const balance = store.ledger.filter((r) => r.user_id === p[0]).reduce((s, r) => s + r.amount, 0);
      return { rows: [{ balance }] };
    }
    if (sql.includes('AS earned FROM coin_ledger')) {
      const earned = store.ledger.filter((r) => r.user_id === p[0] && r.amount > 0 && r.reason !== 'trip_refund').reduce((s, r) => s + r.amount, 0);
      return { rows: [{ earned }] };
    }
    if (sql.startsWith("SELECT 1 FROM coin_ledger WHERE user_id = $1 AND reason = 'daily_login' AND ref = $2")) {
      return { rows: store.ledger.filter((r) => r.user_id === p[0] && r.reason === 'daily_login' && r.ref === p[1]).map(() => ({ '?column?': 1 })) };
    }
    if (sql.startsWith("SELECT ref FROM coin_ledger WHERE user_id = $1 AND reason = 'daily_login'")) {
      return { rows: store.ledger.filter((r) => r.user_id === p[0] && r.reason === 'daily_login').map((r) => ({ ref: r.ref })) };
    }
    // v3 jap (agent J): today's paid jap malas (ref LIKE '<IST date>:%')
    if (sql.startsWith("SELECT ref, created_at FROM coin_ledger WHERE user_id = $1 AND reason = 'jap_mala' AND ref LIKE $2")) {
      const prefix = String(p[1]).replace(/%$/, '');
      return { rows: store.ledger.filter((r) => r.user_id === p[0] && r.reason === 'jap_mala' && r.ref.startsWith(prefix)).map((r) => ({ ref: r.ref, created_at: r.created_at })) };
    }
    if (sql.startsWith("SELECT ref FROM coin_ledger WHERE user_id = $1 AND reason = 'video' AND ref = ANY")) {
      return { rows: store.ledger.filter((r) => r.user_id === p[0] && r.reason === 'video' && p[1].includes(r.ref)).map((r) => ({ ref: r.ref })) };
    }
    if (sql.startsWith("SELECT COUNT(*) AS n FROM coin_ledger WHERE user_id = $1 AND reason = 'video'")) {
      const { istDate } = require('../services/coins_service');
      return { rows: [{ n: store.ledger.filter((r) => r.user_id === p[0] && r.reason === 'video' && istDate(r.created_at) === p[1]).length }] };
    }
    if (sql.startsWith('SELECT id, amount, reason, ref, note, created_at FROM coin_ledger')) {
      return { rows: store.ledger.filter((r) => r.user_id === p[0]).sort((a, b) => b.id - a.id).slice(0, 30) };
    }

    // --- mindset_answers
    if (sql.startsWith('SELECT question_id, option_index FROM mindset_answers')) {
      const rows = [];
      for (const [k, v] of store.answers) {
        const [uid, qid] = k.split(':');
        if (Number(uid) === p[0]) rows.push({ question_id: qid, option_index: v });
      }
      return { rows };
    }
    if (sql.startsWith('INSERT INTO mindset_answers')) {
      store.answers.set(`${p[0]}:${p[1]}`, p[2]);
      return { rows: [] };
    }
    if (sql.startsWith('SELECT COUNT(*) AS n FROM mindset_answers')) {
      let n = 0;
      for (const k of store.answers.keys()) {
        const [uid, qid] = k.split(':');
        if (Number(uid) === p[0] && p[1].includes(qid)) n++;
      }
      return { rows: [{ n }] };
    }

    // --- trips
    if (sql.startsWith('SELECT id FROM users WHERE id = $1 FOR UPDATE')) {
      store.lockedUsers = (store.lockedUsers || 0) + 1;
      return { rows: store.users.has(p[0]) ? [{ id: p[0] }] : [] };
    }
    if (sql.startsWith('SELECT bp.lat AS bp_lat')) {
      if (!store.users.has(p[0])) return { rows: [] };
      const bp = store.buddyProfiles.get(p[0]) || {};
      const bd = store.birth.get(p[0]) || {};
      return { rows: [{ bp_lat: bp.lat ?? null, bp_lng: bp.lng ?? null, bd_lat: bd.latitude ?? null, bd_lng: bd.longitude ?? null }] };
    }
    if (sql.startsWith('SELECT 1 FROM buddy_connections')) {
      const [a, b] = p;
      const ok = store.connections.some((c) => c.status === 'accepted' &&
        ((c.from_user_id === a && c.to_user_id === b) || (c.from_user_id === b && c.to_user_id === a)));
      const blocked = store.blocks.some((x) => (x.user_id === a && x.blocked_user_id === b) || (x.user_id === b && x.blocked_user_id === a));
      const banned = [a, b].some((id) => (store.buddyProfiles.get(id) || {}).banned_at);
      return { rows: ok && !blocked && !banned ? [{ '?column?': 1 }] : [] };
    }
    if (sql.startsWith('INSERT INTO trip_requests')) {
      const row = { id: store.trips.length + 1, user_id: p[0], buddy_user_id: p[1], temple_id: p[2], preferred_month: p[3], status: 'pending', coins_spent: p[4], created_at: new Date() };
      store.trips.push(row);
      return { rows: [{ id: row.id }] };
    }
    const withNames = (t) => {
      const name = (id) => {
        const bp = store.buddyProfiles.get(id);
        if (bp && bp.display_name) return bp.display_name;
        const u = store.users.get(id);
        return u ? String(u.full_name || '').split(' ')[0] : null;
      };
      return { ...t, buddy_name: name(t.buddy_user_id), owner_name: name(t.user_id) };
    };
    if (sql.startsWith('SELECT t.*,') && sql.endsWith('WHERE t.id = $1')) {
      return { rows: store.trips.filter((t) => t.id === p[0]).map(withNames) };
    }
    if (sql.startsWith('SELECT t.*,') && sql.includes('WHERE t.user_id = $1 OR t.buddy_user_id = $1')) {
      return { rows: store.trips.filter((t) => t.user_id === p[0] || t.buddy_user_id === p[0]).sort((a, b) => b.id - a.id).map(withNames) };
    }
    if (sql.startsWith('SELECT * FROM trip_requests WHERE id = $1 AND user_id = $2 FOR UPDATE')) {
      return { rows: store.trips.filter((t) => t.id === p[0] && t.user_id === p[1]).map((t) => ({ ...t })) };
    }
    if (sql.startsWith("UPDATE trip_requests SET status = 'cancelled'")) {
      const t = store.trips.find((x) => x.id === p[0]);
      if (t) t.status = 'cancelled';
      return { rows: [] };
    }

    throw new Error(`fake_db: unhandled SQL: ${sql}`);
  };
}

// Single shared fake module; tests swap the store with reset().
const fake = {
  store: createStore(),
  reset() {
    fake.store = createStore();
    return fake.store;
  },
  query: (...a) => makeQuery(fake.store)(...a),
  async withTransaction(fn) {
    // Snapshot so a thrown error "rolls back" like Postgres would
    const snap = JSON.stringify({ ledger: fake.store.ledger, trips: fake.store.trips, answers: [...fake.store.answers] });
    try {
      return await fn({ query: fake.query });
    } catch (err) {
      const s = JSON.parse(snap);
      fake.store.ledger = s.ledger.map((r) => ({ ...r, created_at: new Date(r.created_at) }));
      fake.store.trips = s.trips.map((r) => ({ ...r, created_at: new Date(r.created_at) }));
      fake.store.answers = new Map(s.answers);
      throw err;
    }
  },
  ensureInitialized: async () => {},
  pool: null,
};

function install() {
  if (!require.cache[DB_PATH] || require.cache[DB_PATH].exports !== fake) {
    const m = new Module(DB_PATH, module);
    m.filename = DB_PATH;
    m.loaded = true;
    m.exports = fake;
    require.cache[DB_PATH] = m;
  }
  process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-unit-tests-only-0123456789';
  return fake;
}

// Starts an express app with `router` mounted at `mount`; returns {url, close}.
async function serve(router, mount) {
  const express = require('express');
  const app = express();
  app.use(express.json());
  app.use(mount, router);
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const url = `http://127.0.0.1:${server.address().port}${mount}`;
  return { url, close: () => new Promise((r) => server.close(r)) };
}

async function call(base, method, pathname, { token, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(base + pathname, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  let json = null;
  try { json = await res.json(); } catch (_) { /* empty */ }
  return { status: res.status, body: json };
}

module.exports = { install, serve, call, fake };
