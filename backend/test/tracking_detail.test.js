// Detailed admin tracking against a stub db (no real database):
// api_requests logging (services/usage_tracking.js), auth_events + users sign-up/login columns
// (routes/auth.js) and blocked accounts (services/user_blocks.js).
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const Module = require('module');
const express = require('express');

// Stub ../db before anything loads it: records every query, answers through `reply`.
const calls = [];
let reply = () => ({ rows: [] });
const dbPath = path.join(__dirname, '..', 'db.js');
const stub = new Module(dbPath);
stub.loaded = true;
stub.exports = {
  query: async (text, params) => {
    const sql = String(text).replace(/\s+/g, ' ').trim();
    calls.push({ sql, params });
    return reply(sql, params);
  },
  withTransaction: async (fn) => fn(stub.exports),
};
require.cache[dbPath] = stub;

process.env.JWT_SECRET = 'test-jwt-secret-0123456789abcdef';
const bcrypt = require('bcryptjs');
const auth = require('../routes/auth');
const usage = require('../services/usage_tracking');
const userBlocks = require('../services/user_blocks');
const { normalizeRoute, shouldLogRequest, recordApiRequest } = usage._internals;

const { signToken, authenticateToken, optionalAuthenticateToken, guestOrAuthenticateToken } = auth;
const BLOCKED = { error: 'Your account has been suspended. Contact support.', code: 'ACCOUNT_BLOCKED' };

function serve(app) {
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

async function post(base, pathname, body, headers = {}) {
  const res = await fetch(base + pathname, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Client-Platform': 'android', ...headers },
    body: JSON.stringify(body),
  });
  let json = null;
  try { json = await res.json(); } catch (_) { /* empty */ }
  return { status: res.status, body: json };
}

const waitFor = async (pred, ms = 1000) => {
  const end = Date.now() + ms;
  while (!pred()) {
    if (Date.now() > end) throw new Error('timed out waiting');
    await new Promise((r) => setTimeout(r, 5));
  }
};

const authEvents = () => calls.filter((c) => c.sql.startsWith('INSERT INTO auth_events')).map((c) => c.params);
const loginUpdates = () => calls.filter((c) => c.sql.startsWith('UPDATE users SET signup_method')).map((c) => c.params);

// Blocked ids answered by the stub for `SELECT id FROM users WHERE is_blocked`.
let blockedIds = [];
function baseReply(sql) {
  if (sql === 'SELECT id FROM users WHERE is_blocked') return { rows: blockedIds.map((id) => ({ id })) };
  return null;
}

// ---------------------------------------------------------------------------------------------
test('normalizeRoute collapses ids, UUIDs, long tokens, emails and file names', () => {
  assert.equal(normalizeRoute('/api/kundli/family/12'), '/api/kundli/family/:id');
  assert.equal(normalizeRoute('/api/kundli/family/12?x=1&y=2'), '/api/kundli/family/:id');
  assert.equal(normalizeRoute('/api/meetups/7/rsvp'), '/api/meetups/:id/rsvp');
  assert.equal(normalizeRoute('/api/x/3fa85f64-5717-4562-b3fc-2c963f66afa6/y'), '/api/x/:id/y');
  assert.equal(normalizeRoute('/api/family/AbCdEfGhIjKlMnOpQrStUvWxYz012345'), '/api/family/:id');
  assert.equal(normalizeRoute('/api/users/someone@example.com'), '/api/users/:id');
  assert.equal(normalizeRoute('/api/files/photo.png'), '/api/files/:id');
  assert.equal(normalizeRoute('/api/chat/send'), '/api/chat/send');
  assert.equal(normalizeRoute('/api/horoscope/daily/'), '/api/horoscope/daily/');
  assert.equal(normalizeRoute(''), '/');
  assert.equal(normalizeRoute(undefined), '/');
  const long = '/api/' + Array.from({ length: 40 }, () => 'abcdef').join('/');
  assert.equal(normalizeRoute(long).length, 120);
  // also exported at the top level for other modules
  assert.equal(usage.normalizeRoute, normalizeRoute);
});

test('shouldLogRequest skips OPTIONS, admin, track, health and non-API paths', () => {
  const r = (method, originalUrl) => ({ method, originalUrl });
  assert.equal(shouldLogRequest(r('GET', '/api/chat/history')), true);
  assert.equal(shouldLogRequest(r('POST', '/api/auth/login')), true);
  assert.equal(shouldLogRequest(r('OPTIONS', '/api/chat/history')), false);
  assert.equal(shouldLogRequest(r('GET', '/api/admin/analytics')), false);
  assert.equal(shouldLogRequest(r('GET', '/api/admin')), false);
  assert.equal(shouldLogRequest(r('POST', '/api/track/open')), false);
  assert.equal(shouldLogRequest(r('GET', '/api/health')), false);
  assert.equal(shouldLogRequest(r('GET', '/api/healthy')), true);
  assert.equal(shouldLogRequest(r('GET', '/admin/dashboard')), false);
  assert.equal(shouldLogRequest(r('GET', '/f/token')), false);
});

test('recordApiRequest writes one row, prunes ~1 in 500, never throws', async () => {
  calls.length = 0; reply = () => ({ rows: [] });
  await recordApiRequest({ userId: 5, method: 'get', route: '/api/x', status: 200, durationMs: 12.6, platform: 'web' }, () => 0.5);
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /^INSERT INTO api_requests \(user_id, method, route, status, duration_ms, platform, app_version\)/);
  assert.deepEqual(calls[0].params, [5, 'GET', '/api/x', 200, 13, 'web', null]);

  calls.length = 0;
  await recordApiRequest({ userId: 5, method: 'GET', route: '/api/x', status: 200, durationMs: 1, platform: 'android', appVersion: '1.3.2+7' }, () => 0.5);
  assert.equal(calls[0].params[6], '1.3.2+7');

  calls.length = 0;
  await recordApiRequest({ userId: null, method: 'POST', route: '/api/x', status: 500, durationMs: 1, platform: 'app' }, () => 0);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].params[0], null);
  assert.match(calls[1].sql, /^DELETE FROM api_requests WHERE created_at < NOW\(\) - INTERVAL '90 days'$/);

  calls.length = 0;
  reply = () => { throw new Error('db down'); };
  await recordApiRequest({ method: 'GET', route: '/api/x', status: 200, durationMs: 1, platform: 'web' });
  reply = () => ({ rows: [] });
});

test('logRequests writes user, method, route, status, duration and platform on finish', async () => {
  calls.length = 0; blockedIds = []; userBlocks.refresh();
  reply = (sql) => baseReply(sql) || { rows: [] };
  const app = express();
  app.use(usage.logRequests);
  app.use(express.json());
  app.get('/api/kundli/family/:id', authenticateToken, async (req, res) => {
    await new Promise((r) => setTimeout(r, 15));
    res.status(201).json({ ok: true });
  });
  app.get('/api/admin/analytics', (req, res) => res.json({}));
  app.get('/api/health', (req, res) => res.json({}));
  app.post('/api/track/open', (req, res) => res.status(204).end());
  app.post('/api/echo', (req, res) => res.json(req.body));
  app.use((err, req, res, next) => res.status(400).json({ error: 'bad' })); // eslint-disable-line no-unused-vars
  app.use((req, res) => res.status(404).json({ error: 'nf' }));
  const { server, base } = await serve(app);
  try {
    const tok = signToken({ userId: 9, email: 'a@b.c', role: 'user' });
    let res = await fetch(`${base}/api/kundli/family/12?q=1`, { headers: { Authorization: `Bearer ${tok}`, 'X-Client-Platform': 'ios' } });
    assert.equal(res.status, 201);
    await waitFor(() => calls.some((c) => c.sql.startsWith('INSERT INTO api_requests')));
    const row = calls.find((c) => c.sql.startsWith('INSERT INTO api_requests')).params;
    assert.deepEqual(row.slice(0, 4), [9, 'GET', '/api/kundli/family/:id', 201]);
    assert.ok(row[4] >= 10, `duration ${row[4]}`);
    assert.equal(row[5], 'ios');

    // skipped paths, and OPTIONS
    calls.length = 0;
    await fetch(`${base}/api/admin/analytics`);
    await fetch(`${base}/api/health`);
    await fetch(`${base}/api/track/open`, { method: 'POST' });
    await fetch(`${base}/api/kundli/family/1`, { method: 'OPTIONS' });
    // anonymous 404 and a malformed body (logger is mounted before the body parser) are logged
    await fetch(`${base}/api/nothing/here`, { headers: { 'User-Agent': 'Dart/3.5 (dart:io)' } });
    await fetch(`${base}/api/echo`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{bad' });
    await waitFor(() => calls.filter((c) => c.sql.startsWith('INSERT INTO api_requests')).length >= 2);
    await new Promise((r) => setTimeout(r, 30));
    const rows = calls.filter((c) => c.sql.startsWith('INSERT INTO api_requests')).map((c) => c.params);
    assert.equal(rows.length, 2, JSON.stringify(rows));
    assert.deepEqual(rows.map((r) => [r[0], r[1], r[2], r[3], r[5]]).sort((a, b) => a[2].localeCompare(b[2])), [
      [null, 'POST', '/api/echo', 400, 'other'],
      [null, 'GET', '/api/nothing/here', 404, 'app'],
    ]);

    // a failing insert never changes the response
    reply = (sql) => { if (sql.startsWith('INSERT INTO api_requests')) throw new Error('db down'); return baseReply(sql) || { rows: [] }; };
    res = await fetch(`${base}/api/kundli/family/3`, { headers: { Authorization: `Bearer ${tok}` } });
    assert.equal(res.status, 201);
    await new Promise((r) => setTimeout(r, 30));
  } finally {
    server.close();
    reply = () => ({ rows: [] });
  }
});

// ---------------------------------------------------------------------------------------------
test('user_blocks: cached set, refresh(), failed load = nobody blocked', async () => {
  calls.length = 0; blockedIds = [4]; userBlocks.refresh();
  reply = (sql) => baseReply(sql) || { rows: [] };
  assert.equal(await userBlocks.isBlocked(4), true);
  assert.equal(await userBlocks.isBlocked(5), false);
  assert.equal(await userBlocks.isBlocked('4'), true);
  assert.equal(await userBlocks.isBlocked(null), false);
  assert.equal(calls.filter((c) => c.sql === 'SELECT id FROM users WHERE is_blocked').length, 1, 'one load for many checks');

  blockedIds = [];
  assert.equal(await userBlocks.isBlocked(4), true, 'still cached');
  userBlocks.refresh();
  assert.equal(await userBlocks.isBlocked(4), false, 'reloaded after refresh');

  // concurrent callers share one load
  calls.length = 0; userBlocks.refresh();
  await Promise.all([1, 2, 3].map((id) => userBlocks.isBlocked(id)));
  assert.equal(calls.length, 1);

  reply = () => { throw new Error('no such column'); };
  userBlocks.refresh();
  assert.equal(await userBlocks.isBlocked(4), false);
  reply = () => ({ rows: [] });
  userBlocks.refresh();
});

test('authenticateToken / optional / guest middleware: 403 ACCOUNT_BLOCKED for blocked users', async () => {
  blockedIds = [7]; userBlocks.refresh();
  reply = (sql) => baseReply(sql) || (sql.startsWith('SELECT role FROM users WHERE id = $1') ? { rows: [{ role: 'guest' }] } : { rows: [] });
  const app = express();
  app.get('/a', authenticateToken, (req, res) => res.json({ id: req.user.userId }));
  app.get('/o', optionalAuthenticateToken, (req, res) => res.json({ id: req.user && req.user.userId }));
  app.get('/g', guestOrAuthenticateToken, (req, res) => res.json({ id: req.user.userId }));
  const { server, base } = await serve(app);
  try {
    const blocked = signToken({ userId: 7, email: 'x@y.z', role: 'user' });
    const blockedGuest = signToken({ userId: 7, email: 'guest_1@guest.astroai.com', role: 'guest' });
    const ok = signToken({ userId: 8, email: 'o@k.z', role: 'user' });
    for (const p of ['/a', '/o', '/g']) {
      let r = await fetch(base + p, { headers: { Authorization: `Bearer ${blocked}` } });
      assert.equal(r.status, 403, p);
      assert.deepEqual(await r.json(), BLOCKED);
      r = await fetch(base + p, { headers: { Authorization: `Bearer ${blockedGuest}` } });
      assert.equal(r.status, 403, `${p} guest`);
      r = await fetch(base + p, { headers: { Authorization: `Bearer ${ok}` } });
      assert.equal(r.status, 200, p);
      assert.deepEqual(await r.json(), { id: 8 });
    }
    // other token problems stay 401
    const r = await fetch(`${base}/a`, { headers: { Authorization: 'Bearer forged.token.x' } });
    assert.equal(r.status, 401);
    assert.equal((await r.json()).error, 'Invalid or expired token');
  } finally {
    server.close();
    blockedIds = []; userBlocks.refresh();
    reply = () => ({ rows: [] });
  }
});

test('guestOrAuthenticateToken records guest_created and sets signup_method guest', async () => {
  calls.length = 0; blockedIds = []; userBlocks.refresh();
  reply = (sql) => baseReply(sql) || (sql.startsWith('INSERT INTO users') ? { rows: [{ id: 31, email: 'guest_x@guest.astroai.com' }] } : { rows: [] });
  const app = express();
  app.get('/g', guestOrAuthenticateToken, (req, res) => res.json({ id: req.user.userId }));
  const { server, base } = await serve(app);
  try {
    const r = await fetch(`${base}/g`, { headers: { 'X-Client-Platform': 'web' } });
    assert.equal(r.status, 200);
    assert.ok(r.headers.get('x-guest-token'));
    assert.deepEqual(authEvents(), [[31, 'guest_created', 'guest', 'web']]);
    assert.deepEqual(loginUpdates(), [[31, 'guest', 'guest']]);

    // a failing tracking write never breaks guest creation
    calls.length = 0;
    reply = (sql) => {
      if (sql.startsWith('INSERT INTO auth_events') || sql.startsWith('UPDATE users SET signup_method')) throw new Error('no table');
      return baseReply(sql) || (sql.startsWith('INSERT INTO users') ? { rows: [{ id: 32, email: 'g@guest.astroai.com' }] } : { rows: [] });
    };
    const r2 = await fetch(`${base}/g`);
    assert.equal(r2.status, 200);
    assert.deepEqual(await r2.json(), { id: 32 });
  } finally {
    server.close();
    reply = () => ({ rows: [] });
  }
});

// ---------------------------------------------------------------------------------------------
test('register / login / google record auth_events and login columns', async (t) => {
  const app = express();
  app.use(express.json());
  app.use('/api/auth', auth.router);
  const { server, base } = await serve(app);
  const origVerify = auth.router.verifyGoogleIdToken;
  const hash = await bcrypt.hash('secret123', 4);
  // users by email for the login SELECT *
  let users = {};
  const kundliEmpty = { rows: [] };
  const authReply = (extra) => (sql, p) => {
    const b = baseReply(sql); if (b) return b;
    if (extra) { const e = extra(sql, p); if (e) return e; }
    if (sql.startsWith('SELECT id FROM users WHERE LOWER(email) = $1')) return { rows: users[p[0]] ? [{ id: users[p[0]].id }] : [] };
    if (sql.startsWith('SELECT * FROM users WHERE LOWER(email) = $1')) return { rows: users[p[0]] ? [users[p[0]]] : [] };
    if (sql.startsWith('SELECT bd.full_name')) return kundliEmpty;
    return { rows: [] };
  };
  const reset = (extra) => { calls.length = 0; reply = authReply(extra); };
  blockedIds = []; userBlocks.refresh();

  try {
    await t.test('register (email) -> register/email', async () => {
      users = {};
      reset((sql, p) => sql.startsWith('INSERT INTO users') ? { rows: [{ id: 40, email: p[0], full_name: 'A', gender: 'x', role: 'user', created_at: new Date() }] } : null);
      const r = await post(base, '/api/auth/register', { email: 'new@x.com', password: 'secret123', fullName: 'A' });
      assert.equal(r.status, 201);
      assert.deepEqual(authEvents(), [[40, 'register', 'email', 'android']]);
      assert.deepEqual(loginUpdates(), [[40, 'email', 'email']]);
    });

    await t.test('register from a guest session -> guest_upgraded/email', async () => {
      users = {};
      reset((sql, p) => sql.startsWith('UPDATE users SET email = $1') ? { rows: [{ id: 41, email: p[0], full_name: 'G', gender: 'x', role: 'user', created_at: new Date() }] } : null);
      const guestTok = signToken({ userId: 41, email: 'guest_1@guest.astroai.com', role: 'guest' });
      const r = await post(base, '/api/auth/register', { email: 'g@x.com', password: 'secret123', fullName: 'G' }, { Authorization: `Bearer ${guestTok}` });
      assert.equal(r.status, 201);
      assert.deepEqual(authEvents(), [[41, 'guest_upgraded', 'email', 'android']]);
      assert.deepEqual(loginUpdates(), [[41, 'email', 'email']]);
    });

    await t.test('register from a blocked guest session -> 403 + blocked', async () => {
      users = {}; blockedIds = [42]; userBlocks.refresh();
      reset();
      const guestTok = signToken({ userId: 42, email: 'guest_2@guest.astroai.com', role: 'guest' });
      const r = await post(base, '/api/auth/register', { email: 'b@x.com', password: 'secret123', fullName: 'B' }, { Authorization: `Bearer ${guestTok}` });
      assert.equal(r.status, 403);
      assert.deepEqual(r.body, BLOCKED);
      assert.deepEqual(authEvents(), [[42, 'blocked', 'email', 'android']]);
      assert.ok(!calls.some((c) => c.sql.startsWith('UPDATE users SET email')), 'guest not upgraded');
      blockedIds = []; userBlocks.refresh();
    });

    await t.test('login success -> login/email, keeps signup_method', async () => {
      users = { 'u@x.com': { id: 43, email: 'u@x.com', password_hash: hash, full_name: 'U', role: 'user', is_blocked: false } };
      reset();
      const r = await post(base, '/api/auth/login', { email: 'U@x.com', password: 'secret123' });
      assert.equal(r.status, 200);
      assert.deepEqual(authEvents(), [[43, 'login', 'email', 'android']]);
      assert.deepEqual(loginUpdates(), [[43, null, 'email']]);
    });

    await t.test('wrong password -> failed_login with user id; bad unknown email -> failed_login null', async () => {
      reset();
      let r = await post(base, '/api/auth/login', { email: 'u@x.com', password: 'wrong-pass' });
      assert.equal(r.status, 401);
      assert.deepEqual(authEvents(), [[43, 'failed_login', 'email', 'android']]);
      assert.deepEqual(loginUpdates(), []);
      reset();
      r = await post(base, '/api/auth/login', { email: 'nobody@x.com', password: '123' });
      assert.equal(r.status, 400);
      assert.deepEqual(authEvents(), [[null, 'failed_login', 'email', 'android']]);
    });

    await t.test('login with an unknown email creates the account -> register/email', async () => {
      users = {};
      reset((sql, p) => sql.startsWith('INSERT INTO users') ? { rows: [{ id: 44, email: p[0], full_name: 'n', gender: 'x', role: 'user', created_at: new Date() }] } : null);
      const r = await post(base, '/api/auth/login', { email: 'n@x.com', password: 'secret123' });
      assert.equal(r.status, 200);
      assert.deepEqual(authEvents(), [[44, 'register', 'email', 'android']]);
      assert.deepEqual(loginUpdates(), [[44, 'email', 'email']]);
    });

    await t.test('blocked account: right password -> 403 + blocked; wrong password stays 401', async () => {
      users = { 'b@x.com': { id: 45, email: 'b@x.com', password_hash: hash, full_name: 'B', role: 'user', is_blocked: true } };
      reset();
      let r = await post(base, '/api/auth/login', { email: 'b@x.com', password: 'secret123' });
      assert.equal(r.status, 403);
      assert.deepEqual(r.body, BLOCKED);
      assert.deepEqual(authEvents(), [[45, 'blocked', 'email', 'android']]);
      assert.deepEqual(loginUpdates(), []);
      reset();
      r = await post(base, '/api/auth/login', { email: 'b@x.com', password: 'nope-nope' });
      assert.equal(r.status, 401);
      assert.deepEqual(authEvents(), [[45, 'failed_login', 'email', 'android']]);
    });

    await t.test('tracking failures never change the login response', async () => {
      users = { 'u@x.com': { id: 43, email: 'u@x.com', password_hash: hash, full_name: 'U', role: 'user', is_blocked: false } };
      reset((sql) => {
        if (sql.startsWith('INSERT INTO auth_events') || sql.startsWith('UPDATE users SET signup_method')) throw new Error('relation does not exist');
        return null;
      });
      const r = await post(base, '/api/auth/login', { email: 'u@x.com', password: 'secret123' });
      assert.equal(r.status, 200);
      assert.ok(r.body.token);
    });

    const googlePayload = (email, sub) => async () => ({ sub, email, email_verified: true, name: 'Goo' });

    await t.test('google: new account -> register/google, signup google', async () => {
      auth.router.verifyGoogleIdToken = googlePayload('gnew@x.com', 'g-1');
      reset((sql, p) => {
        if (sql.startsWith('SELECT * FROM users WHERE google_id = $1')) return { rows: [] };
        if (sql.startsWith('INSERT INTO users')) return { rows: [{ id: 50, email: p[0], full_name: 'Goo', role: 'user', google_id: 'g-1', is_blocked: false }] };
        return null;
      });
      const r = await post(base, '/api/auth/google', { idToken: 'x' });
      assert.equal(r.status, 200);
      assert.equal(r.body.isNewUser, true);
      assert.deepEqual(authEvents(), [[50, 'register', 'google', 'android']]);
      assert.deepEqual(loginUpdates(), [[50, 'google', 'google']]);
    });

    await t.test('google: existing account -> login/google, signup untouched', async () => {
      auth.router.verifyGoogleIdToken = googlePayload('gold@x.com', 'g-2');
      reset((sql) => sql.startsWith('SELECT * FROM users WHERE google_id = $1')
        ? { rows: [{ id: 51, email: 'gold@x.com', full_name: 'Old', role: 'user', google_id: 'g-2', is_blocked: false }] } : null);
      const r = await post(base, '/api/auth/google', { idToken: 'x' });
      assert.equal(r.status, 200);
      assert.equal(r.body.isNewUser, false);
      assert.deepEqual(authEvents(), [[51, 'login', 'google', 'android']]);
      assert.deepEqual(loginUpdates(), [[51, null, 'google']]);
    });

    await t.test('google: guest upgrade -> guest_upgraded/google', async () => {
      auth.router.verifyGoogleIdToken = googlePayload('gg@x.com', 'g-3');
      reset((sql, p) => {
        if (sql.startsWith('SELECT * FROM users WHERE google_id = $1')) return { rows: [] };
        if (sql.startsWith('UPDATE users SET email = $1')) return { rows: [{ id: 52, email: p[0], full_name: 'Goo', role: 'user', google_id: 'g-3', is_blocked: false }] };
        return null;
      });
      const guestTok = signToken({ userId: 52, email: 'guest_3@guest.astroai.com', role: 'guest' });
      const r = await post(base, '/api/auth/google', { idToken: 'x' }, { Authorization: `Bearer ${guestTok}` });
      assert.equal(r.status, 200);
      assert.deepEqual(authEvents(), [[52, 'guest_upgraded', 'google', 'android']]);
      assert.deepEqual(loginUpdates(), [[52, 'google', 'google']]);
    });

    await t.test('google: blocked account -> 403 + blocked, google id not linked', async () => {
      auth.router.verifyGoogleIdToken = googlePayload('gb@x.com', 'g-4');
      reset((sql) => sql.startsWith('SELECT * FROM users WHERE google_id = $1')
        ? { rows: [{ id: 53, email: 'gb@x.com', full_name: 'Bl', role: 'user', google_id: null, is_blocked: true }] } : null);
      const r = await post(base, '/api/auth/google', { idToken: 'x' });
      assert.equal(r.status, 403);
      assert.deepEqual(r.body, BLOCKED);
      assert.deepEqual(authEvents(), [[53, 'blocked', 'google', 'android']]);
      assert.ok(!calls.some((c) => c.sql.startsWith('UPDATE users SET google_id')));
    });
  } finally {
    auth.router.verifyGoogleIdToken = origVerify;
    server.close();
    reply = () => ({ rows: [] });
  }
});

test('appVersionOf accepts app build strings only', () => {
  const { appVersionOf } = require('../services/usage_tracking')._internals;
  assert.equal(appVersionOf({ headers: { 'x-app-version': '1.3.2+7' } }), '1.3.2+7');
  assert.equal(appVersionOf({ headers: { 'x-app-version': '<script>' } }), null);
  assert.equal(appVersionOf({ headers: { 'x-app-version': 'x'.repeat(21) } }), null);
  assert.equal(appVersionOf({ headers: {} }), null);
});
