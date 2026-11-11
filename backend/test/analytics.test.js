// Usage tracking (services/usage_tracking.js) + /api/admin/analytics against a stub db.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const Module = require('module');
const express = require('express');

// Stub ../db before anything loads it: records every query, answers with canned rows.
const calls = [];
let reply = () => ({ rows: [] });
const dbPath = path.join(__dirname, '..', 'db.js');
const stub = new Module(dbPath);
stub.loaded = true;
stub.exports = {
  query: async (text, params) => { calls.push({ sql: String(text).replace(/\s+/g, ' ').trim(), params }); return reply(text, params); },
  withTransaction: async (fn) => fn(stub.exports),
};
require.cache[dbPath] = stub;

process.env.JWT_SECRET = 'test-jwt-secret-0123456789abcdef';
process.env.ADMIN_KEY = 'test-admin-key-0123456789abcdef';
const { signToken } = require('../routes/auth');
const usage = require('../services/usage_tracking');
const { costUsd, platformOf, featureOf, userIdOf, noteActivity, pending, WRITE_EVERY_MS } = usage._internals;

function serve(app) {
  return new Promise((resolve) => {
    const server = app.listen(0, () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` }));
  });
}

test('costUsd prices by longest model prefix, unknown models as gpt-4o', () => {
  assert.equal(costUsd('gpt-4o-mini-2024-07-18', 1e6, 1e6), 0.75);
  assert.equal(costUsd('gpt-4o-2024-08-06', 1e6, 0), 2.5);
  assert.equal(costUsd('some-new-model', 0, 1e6), 10);
});

test('platformOf: header first, then User-Agent', () => {
  const r = (h) => ({ headers: h });
  assert.equal(platformOf(r({ 'x-client-platform': 'Android' })), 'android');
  assert.equal(platformOf(r({ 'x-client-platform': 'evil', 'user-agent': 'Dart/3.5 (dart:io)' })), 'app');
  assert.equal(platformOf(r({ 'user-agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/130' })), 'web');
  assert.equal(platformOf(r({})), 'other');
});

test('featureOf drops /api and ids', () => {
  assert.equal(featureOf({ originalUrl: '/api/chat/send?x=1' }), 'chat/send');
  assert.equal(featureOf({ originalUrl: '/api/horoscope/compatibility/42' }), 'horoscope/compatibility');
  assert.equal(featureOf({ originalUrl: '/api/kundli/123/report' }), 'kundli/report');
});

test('userIdOf reads req.user, else a valid Bearer token only', () => {
  const tok = signToken({ userId: 7, email: 'a@b.c', role: 'user' });
  assert.equal(userIdOf({ user: { userId: 3 }, headers: {} }), 3);
  assert.equal(userIdOf({ headers: { authorization: `Bearer ${tok}` } }), 7);
  assert.equal(userIdOf({ headers: { authorization: 'Bearer forged.token.here' } }), null);
  assert.equal(userIdOf({ headers: {} }), null);
});

test('noteActivity writes once per window and carries the counts forward', async () => {
  calls.length = 0; pending.clear();
  const t0 = Date.parse('2026-11-12T06:00:00Z');
  await noteActivity({ visitorKey: 'u:1', userId: 1, platform: 'web' }, t0);
  await noteActivity({ visitorKey: 'u:1', userId: 1, platform: 'web' }, t0 + 1000);
  await noteActivity({ visitorKey: 'u:1', userId: 1, platform: 'web' }, t0 + 2000);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].params, ['2026-11-12', 'u:1', 1, 'web', 1, 0]);
  await noteActivity({ visitorKey: 'u:1', userId: 1, platform: 'web' }, t0 + WRITE_EVERY_MS + 1);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1].params.slice(4), [3, 0]); // the 2 held back + this one
});

test('AI usage is attributed to the user and feature of the request', async () => {
  calls.length = 0; pending.clear();
  const app = express();
  app.use(express.json());
  app.use(usage.requestContext);
  app.use(usage.trackActivity);
  app.post('/api/chat/send', async (req, res) => {
    await new Promise((r) => setTimeout(r, 5)); // context must survive async hops
    await usage.recordAiUsage({ model: 'gpt-4o-mini', usage: { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 } });
    res.json({ ok: true });
  });
  const { server, base } = await serve(app);
  try {
    const tok = signToken({ userId: 42, email: 'x@y.z', role: 'user' });
    const res = await fetch(`${base}/api/chat/send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${tok}`, 'X-Client-Platform': 'ios', 'Content-Type': 'application/json' },
      body: '{}',
    });
    assert.equal(res.status, 200);
  } finally {
    server.close();
  }
  const act = calls.find((c) => c.sql.startsWith('INSERT INTO daily_activity'));
  assert.deepEqual(act.params.slice(1, 4), ['u:42', 42, 'ios']);
  const ai = calls.find((c) => c.sql.startsWith('INSERT INTO ai_usage'));
  assert.deepEqual(ai.params.slice(0, 7), [42, 'chat/send', 'gpt-4o-mini', 'ios', 1000, 500, 1500]);
  assert.ok(Math.abs(ai.params[7] - 0.00045) < 1e-12);
});

test('POST /api/track/open counts anonymous installs and rejects junk', async () => {
  calls.length = 0; pending.clear();
  const app = express();
  app.use(express.json());
  app.use('/api/track', usage.openRoute);
  const { server, base } = await serve(app);
  try {
    const post = (body, headers = {}) => fetch(`${base}/api/track/open`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body),
    });
    assert.equal((await post({ installId: 'abcdef0123456789' }, { 'User-Agent': 'Mozilla/5.0' })).status, 204);
    assert.equal((await post({ installId: 'bad id!' })).status, 400);
    assert.equal((await post({})).status, 400);
  } finally {
    server.close();
  }
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].params.slice(1, 6), ['d:abcdef0123456789', null, 'web', 0, 1]);
});

test('admin analytics: key required, numbers shaped, users search escaped', async () => {
  const adminRouter = require('../routes/admin');
  const app = express();
  app.use(express.json());
  app.use('/api/admin', adminRouter);
  reply = (sql) => {
    const s = String(sql);
    if (s.includes('AS users_total')) return { rows: [{ users_total: 10, guests_total: 4, signups_today: 1, signups_range: 6, active_today: 3, active_range: 9 }] };
    if (s.includes('GROUP BY platform')) return { rows: [{ platform: 'web', active_today: 2, active_range: 5, opens: 8, requests: 40 }] };
    if (s.includes('AS calls_today')) return { rows: [{ calls_today: 2, tokens_today: 3000, cost_today: 0.01, calls_range: 9, tokens_range: 20000, cost_range: 0.2, users_range: 3, calls_all: 9, tokens_all: 20000, cost_all: 0.2 }] };
    if (s.includes('generate_series')) return { rows: [{ day: '2026-11-12', active: 3, web: 2, app: 1, signups: 1, calls: 2, tokens: 3000, cost: 0.01 }] };
    if (s.includes('GROUP BY feature, model')) return { rows: [{ feature: 'chat/send', model: 'gpt-4o', calls: 9, prompt_tokens: 15000, completion_tokens: 5000, tokens: 20000, cost: 0.2 }] };
    if (s.includes('FROM users u')) return { rows: [{ id: 5, full_name: 'Asha', email: 'asha@x.com', role: 'user', created_at: new Date('2026-11-01T00:00:00Z'), calls: 9, tokens: 20000, cost: 0.2, last_ai: null, last_seen: null, active_days: 4, platforms: 'android, web' }] };
    return { rows: [] };
  };
  const { server, base } = await serve(app);
  try {
    assert.equal((await fetch(`${base}/api/admin/analytics`)).status, 401);
    const h = { 'x-admin-key': process.env.ADMIN_KEY };
    const o = await (await fetch(`${base}/api/admin/analytics?days=7`, { headers: h })).json();
    assert.equal(o.days, 7);
    assert.equal(o.users.activeToday, 3);
    assert.equal(o.ai.inRange.costUsd, 0.2);
    assert.equal(o.daily[0].web, 2);
    assert.equal(o.features[0].feature, 'chat/send');

    calls.length = 0;
    const u = await (await fetch(`${base}/api/admin/analytics/users?q=50%25_off&sort=bogus`, { headers: h })).json();
    assert.equal(u.sort, 'cost');
    assert.equal(u.users[0].aiTokens, 20000);
    assert.equal(calls[0].params[1], '%50\\%\\_off%');
  } finally {
    server.close();
    reply = () => ({ rows: [] });
  }
});
