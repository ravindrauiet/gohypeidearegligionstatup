// Coins: pure helpers + /api/coins routes against an in-memory fake db (no real database).
const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve, call } = require('./fake_db');

const fake = install();
const C = require('../services/coins_service');
const { signToken } = require('../routes/auth');
const rewardsRouter = require('../routes/rewards');
const QUESTIONS = require('../data/mindset_questions.json');

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------
test('istDate uses Asia/Kolkata', () => {
  assert.equal(C.istDate(Date.parse('2026-11-05T18:29:59Z')), '2026-11-05');
  assert.equal(C.istDate(Date.parse('2026-11-05T18:30:00Z')), '2026-11-06'); // IST midnight
  assert.equal(C.istDate(new Date('2026-01-01T00:00:00Z')), '2026-01-01');
  assert.equal(C.istMonth(Date.parse('2026-12-31T19:00:00Z')), '2027-01');
});

test('addDays crosses months and years', () => {
  assert.equal(C.addDays('2026-03-01', -1), '2026-02-28');
  assert.equal(C.addDays('2024-03-01', -1), '2024-02-29');
  assert.equal(C.addDays('2026-12-31', 1), '2027-01-01');
});

test('streakDays counts consecutive days ending today or yesterday', () => {
  const today = '2026-11-05';
  assert.equal(C.streakDays([], today), 0);
  assert.equal(C.streakDays(['2026-11-05'], today), 1);
  assert.equal(C.streakDays(['2026-11-05', '2026-11-04', '2026-11-03', '2026-11-01'], today), 3);
  assert.equal(C.streakDays(['2026-11-04', '2026-11-03'], today), 2, 'yesterday still counts');
  assert.equal(C.streakDays(['2026-11-03', '2026-11-02'], today), 0, 'gap of a day breaks it');
  assert.equal(C.streakDays(['2026-11-05', '2026-11-05', '2026-11-04'], today), 2, 'duplicates ignored');
  assert.equal(C.streakDays(['2026-10-31', '2026-11-01'], '2026-11-01'), 2, 'across months');
});

test('isVideoId accepts only 11-char YouTube ids', () => {
  assert.ok(C.isVideoId('dQw4w9WgXcQ'));
  assert.ok(C.isVideoId('a-b_c-d_e-f'));
  for (const bad of ['', 'short', 'dQw4w9WgXcQx', 'dQw4w9WgXc!', null, 12345678901, "dQw4w9Wg'; "]) assert.equal(C.isVideoId(bad), false, String(bad));
});

test('earn rules and constants match the contract', () => {
  assert.equal(C.GOAL, 10000);
  const byKey = Object.fromEntries(C.EARN_RULES.map((r) => [r.key, r]));
  assert.equal(byKey.daily_login.coins, 1);
  assert.equal(byKey.game.coins, 10);
  assert.equal(byKey.video.coins, 1);
  assert.equal(byKey.question.coins, 50);
  for (const r of C.EARN_RULES) assert.ok(r.title && r.note);
  assert.equal(C.gameRef('quest', Date.parse('2026-11-05T20:00:00Z')), 'quest:2026-11-06');
});

test('awardCoins returns the amount once, 0 on repeat', async () => {
  const store = fake.reset();
  assert.equal(await C.awardCoins(fake, 7, 10, 'game', 'quest:2026-11-05', 'x'), 10);
  assert.equal(await C.awardCoins(fake, 7, 10, 'game', 'quest:2026-11-05', 'x'), 0);
  assert.equal(await C.awardCoins(fake, 7, 10, 'game', 'cards:2026-11-05'), 10);
  assert.equal(await C.balanceOf(fake, 7), 20);
  assert.equal(store.ledger.length, 2);
  assert.ok(store.log.every((s) => !s.startsWith('INSERT') || s.includes('ON CONFLICT (user_id, reason, ref) DO NOTHING')));
});

test('awardGameCoins pays registered users only, once per game per day', async () => {
  fake.reset();
  const now = Date.parse('2026-11-05T06:00:00Z');
  assert.equal(await C.awardGameCoins(fake, 1, 'moksha', false, now), 0, 'guest');
  assert.equal(await C.awardGameCoins(fake, 1, 'unknown', true, now), 0, 'unknown game');
  assert.equal(await C.awardGameCoins(fake, 1, 'moksha', true, now), 10);
  assert.equal(await C.awardGameCoins(fake, 1, 'moksha', true, now + 3600e3), 0);
  assert.equal(await C.awardGameCoins(fake, 1, 'moksha', true, now + 86400e3), 10, 'next IST day');
});

// ---------------------------------------------------------------------------
// Mindset questions content
// ---------------------------------------------------------------------------
test('mindset_questions.json: 50 questions, q01..q50, 4 options, all categories', () => {
  assert.equal(QUESTIONS.length, 50);
  QUESTIONS.forEach((q, i) => {
    assert.equal(q.id, `q${String(i + 1).padStart(2, '0')}`);
    assert.ok(typeof q.text === 'string' && q.text.length > 8 && q.text.length < 90, q.id);
    assert.equal(q.options.length, 4, q.id);
    assert.equal(new Set(q.options).size, 4, `${q.id} duplicate options`);
    for (const o of q.options) assert.ok(o.length > 0 && o.length <= 40, `${q.id}: ${o}`);
  });
  const cats = new Set(QUESTIONS.map((q) => q.category));
  assert.deepEqual([...cats].sort(), ['career_money', 'lifestyle', 'relationships', 'social', 'spiritual', 'travel', 'values']);
  for (const c of cats) assert.ok(QUESTIONS.filter((q) => q.category === c).length >= 5, c);
  const banned = /caste|salary|income|disease|illness|sexual|weight|religion is/i;
  for (const q of QUESTIONS) assert.ok(!banned.test(q.text), q.id);
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
test('coins routes', async (t) => {
  const srv = await serve(rewardsRouter, '/api/coins');
  t.after(() => srv.close());
  const store = fake.reset();
  store.users.set(1, { role: 'user', full_name: 'Asha Rao' });
  store.users.set(2, { role: 'guest', full_name: 'Guest' });
  const user = signToken({ userId: 1, role: 'user' });
  const guest = signToken({ userId: 2, role: 'guest' });

  await t.test('login required', async () => {
    for (const [m, p] of [['GET', ''], ['POST', '/daily'], ['POST', '/video'], ['GET', '/questions'], ['POST', '/questions/q01/answer']]) {
      const none = await call(srv.url, m, p, { body: m === 'POST' ? {} : undefined });
      assert.equal(none.status, 401, `${m} ${p}`);
      assert.equal(none.body.code, 'LOGIN_REQUIRED');
      const g = await call(srv.url, m, p, { token: guest, body: m === 'POST' ? {} : undefined });
      assert.equal(g.status, 401);
      assert.equal(g.body.code, 'LOGIN_REQUIRED');
    }
  });

  await t.test('daily check-in is idempotent', async () => {
    const a = await call(srv.url, 'POST', '/daily', { token: user });
    assert.equal(a.status, 200);
    assert.deepEqual(a.body, { awarded: 1, balance: 1, streakDays: 1 });
    const b = await call(srv.url, 'POST', '/daily', { token: user });
    assert.deepEqual(b.body, { awarded: 0, balance: 1, streakDays: 1 });
  });

  await t.test('streak includes earlier days', async () => {
    const today = C.istDate();
    store.ledger.push({ id: 900, user_id: 1, amount: 1, reason: 'daily_login', ref: C.addDays(today, -1), note: null, created_at: new Date() });
    store.ledger.push({ id: 901, user_id: 1, amount: 1, reason: 'daily_login', ref: C.addDays(today, -2), note: null, created_at: new Date() });
    const r = await call(srv.url, 'POST', '/daily', { token: user });
    assert.equal(r.body.streakDays, 3);
    assert.equal(r.body.balance, 3);
  });

  await t.test('video reward once per video, validates id', async () => {
    const bad = await call(srv.url, 'POST', '/video', { token: user, body: { videoId: 'nope' } });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.code, 'BAD_VIDEO_ID');
    const a = await call(srv.url, 'POST', '/video', { token: user, body: { videoId: 'dQw4w9WgXcQ', title: 'Aarti' } });
    assert.deepEqual(a.body, { awarded: 1, balance: 4 });
    const b = await call(srv.url, 'POST', '/video', { token: user, body: { videoId: 'dQw4w9WgXcQ' } });
    assert.deepEqual(b.body, { awarded: 0, balance: 4 });
  });

  await t.test('questions list and answering', async () => {
    const list = await call(srv.url, 'GET', '/questions', { token: user });
    assert.equal(list.status, 200);
    assert.equal(list.body.questions.length, 50);
    assert.deepEqual(Object.keys(list.body.questions[0]).sort(), ['category', 'id', 'options', 'text']);
    assert.deepEqual(list.body.answers, {});
    assert.equal(list.body.answeredCount, 0);
    assert.equal(list.body.coinsPerQuestion, 50);

    const nf = await call(srv.url, 'POST', '/questions/q99/answer', { token: user, body: { optionIndex: 0 } });
    assert.equal(nf.status, 404);
    for (const optionIndex of [-1, 4, 1.5, 'x', null]) {
      const r = await call(srv.url, 'POST', '/questions/q01/answer', { token: user, body: { optionIndex } });
      assert.equal(r.status, 400, String(optionIndex));
    }
    const a = await call(srv.url, 'POST', '/questions/q01/answer', { token: user, body: { optionIndex: 2 } });
    assert.deepEqual(a.body, { awarded: 50, balance: 54, answeredCount: 1 });
    const again = await call(srv.url, 'POST', '/questions/q01/answer', { token: user, body: { optionIndex: 3 } });
    assert.deepEqual(again.body, { awarded: 0, balance: 54, answeredCount: 1 });
    const after = await call(srv.url, 'GET', '/questions', { token: user });
    assert.deepEqual(after.body.answers, { q01: 3 });
    assert.equal(after.body.answeredCount, 1);
  });

  await t.test('GET /api/coins summary', async () => {
    const r = await call(srv.url, 'GET', '', { token: user });
    assert.equal(r.status, 200);
    const b = r.body;
    assert.equal(b.balance, 54);
    assert.equal(b.goal, 10000);
    assert.equal(b.dailyClaimed, true);
    assert.equal(b.streakDays, 3);
    assert.ok(Number.isInteger(b.todayEarned));
    assert.ok(Array.isArray(b.earnRules) && b.earnRules.length >= 4);
    assert.ok(b.recent.length >= 3 && b.recent.length <= 30);
    const row = b.recent[0];
    assert.deepEqual(Object.keys(row).sort(), ['amount', 'createdAt', 'id', 'note', 'reason', 'ref']);
    assert.equal(typeof row.createdAt, 'string');
  });

  await t.test('video rewards stop at the daily cap (no farming with made-up ids)', async () => {
    const paid = store.ledger.filter((r) => r.user_id === 1 && r.reason === 'video').length;
    for (let i = paid; i < C.VIDEO_DAILY_CAP; i++) {
      store.ledger.push({ id: 1000 + i, user_id: 1, amount: 1, reason: 'video', ref: `cap${String(i).padStart(8, '0')}`, note: null, created_at: new Date() });
    }
    const balance = store.ledger.filter((r) => r.user_id === 1).reduce((s, r) => s + r.amount, 0);
    const capped = await call(srv.url, 'POST', '/video', { token: user, body: { videoId: 'ZZZZZZZZZZZ' } });
    assert.equal(capped.status, 200);
    assert.deepEqual(capped.body, { awarded: 0, balance, dailyCapReached: true });
    assert.ok(!store.ledger.some((r) => r.ref === 'ZZZZZZZZZZZ'));
    // earlier days do not count toward today's cap
    for (const r of store.ledger) if (r.reason === 'video') r.created_at = new Date(Date.now() - 2 * 86400e3);
    const next = await call(srv.url, 'POST', '/video', { token: user, body: { videoId: 'ZZZZZZZZZZZ' } });
    assert.deepEqual(next.body, { awarded: 1, balance: balance + 1 });
  });
});
