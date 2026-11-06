// Jap mala rewards (v3 jap): POST /api/coins/jap and GET /api/coins/jap/today against the in-memory
// fake db (no real database). Clock is injected through rewardsRouter.clock.
const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve, call } = require('./fake_db');

const fake = install();
const C = require('../services/coins_service');
const { signToken } = require('../routes/auth');
const rewardsRouter = require('../routes/rewards');

const realNow = rewardsRouter.clock.now;
test.after(() => { rewardsRouter.clock.now = realNow; });

test('jap constants and earn rule match the contract', () => {
  assert.equal(C.JAP_REASON, 'jap_mala');
  assert.equal(C.JAP_COINS, 5);
  assert.equal(C.JAP_DAILY_CAP, 3);
  assert.equal(C.JAP_MIN_GAP_SECONDS, 90);
  const rule = C.EARN_RULES.find((r) => r.key === 'jap_mala');
  assert.ok(rule, 'jap rule listed in ways to earn');
  assert.equal(rule.coins, 5);
  assert.ok(rule.title && rule.note.includes('3'));
});

test('japDecision: slots, cap and the 90 s gap', () => {
  const d = rewardsRouter.japDecision;
  const day = '2026-11-05';
  const t0 = Date.parse('2026-11-05T04:00:00Z');
  assert.deepEqual(d([], day, t0), { paidToday: 0, nextIndex: 1, dailyCapReached: false, retryAfterSeconds: 0 });
  const one = [{ ref: `${day}:1`, created_at: new Date(t0) }];
  assert.equal(d(one, day, t0 + 30e3).retryAfterSeconds, 60);
  assert.equal(d(one, day, t0 + 89.5e3).retryAfterSeconds, 1);
  assert.deepEqual(d(one, day, t0 + 90e3), { paidToday: 1, nextIndex: 2, dailyCapReached: false, retryAfterSeconds: 0 });
  // other days' refs are ignored; a gap in slots is filled first
  const mixed = [{ ref: '2026-11-04:1', created_at: new Date(t0) }, { ref: `${day}:2`, created_at: new Date(t0 - 600e3) }];
  assert.deepEqual(d(mixed, day, t0), { paidToday: 1, nextIndex: 1, dailyCapReached: false, retryAfterSeconds: 0 });
  const full = [1, 2, 3].map((n) => ({ ref: `${day}:${n}`, created_at: new Date(t0) }));
  assert.deepEqual(d(full, day, t0 + 1e3), { paidToday: 3, nextIndex: null, dailyCapReached: true, retryAfterSeconds: 0 });
  // ISO string timestamps (pg may hand them back as strings)
  assert.equal(d([{ ref: `${day}:1`, created_at: new Date(t0).toISOString() }], day, t0 + 10e3).retryAfterSeconds, 80);
});

test('jap routes', async (t) => {
  const srv = await serve(rewardsRouter, '/api/coins');
  t.after(() => srv.close());
  const store = fake.reset();
  store.users.set(1, { role: 'user', full_name: 'Asha Rao' });
  store.users.set(2, { role: 'guest', full_name: 'Guest' });
  store.users.set(3, { role: 'user', full_name: 'Ravi' });
  const user = signToken({ userId: 1, role: 'user' });
  const guest = signToken({ userId: 2, role: 'guest' });
  const other = signToken({ userId: 3, role: 'user' });

  // 10:00 IST on 2026-11-05
  let now = Date.parse('2026-11-05T04:30:00Z');
  rewardsRouter.clock.now = () => now;
  // The fake stamps created_at with the real time; re-stamp new jap rows with the test clock.
  const claim = async (token, body = {}) => {
    const before = new Set(fake.store.ledger.map((x) => x.id));
    const r = await call(srv.url, 'POST', '/jap', { token, body });
    for (const row of fake.store.ledger) if (!before.has(row.id)) row.created_at = new Date(now);
    return r;
  };
  const japRows = (uid) => fake.store.ledger.filter((r) => r.user_id === uid && r.reason === 'jap_mala');

  await t.test('guests and anonymous callers need an account', async () => {
    for (const [m, p] of [['POST', '/jap'], ['GET', '/jap/today']]) {
      const none = await call(srv.url, m, p, { body: m === 'POST' ? {} : undefined });
      assert.equal(none.status, 401, `${m} ${p}`);
      assert.equal(none.body.code, 'LOGIN_REQUIRED');
      const g = await call(srv.url, m, p, { token: guest, body: m === 'POST' ? {} : undefined });
      assert.equal(g.status, 401);
      assert.equal(g.body.code, 'LOGIN_REQUIRED');
    }
    assert.equal(store.ledger.length, 0);
  });

  await t.test('today starts empty', async () => {
    const r = await call(srv.url, 'GET', '/jap/today', { token: user });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { day: '2026-11-05', paidToday: 0, cap: 3, coinsPerMala: 5, dailyCapReached: false, retryAfterSeconds: 0 });
  });

  await t.test('a completed mala pays 5 coins', async () => {
    const r = await claim(user, { malaIndex: 1 });
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { awarded: 5, balance: 5, paidToday: 1, cap: 3, dailyCapReached: false });
    assert.deepEqual(japRows(1).map((x) => x.ref), ['2026-11-05:1']);
    assert.equal(japRows(1)[0].amount, 5);
  });

  await t.test('a second mala within 90 s is rejected, then paid after the gap', async () => {
    now += 45e3;
    const r = await claim(user, { malaIndex: 2 });
    assert.equal(r.status, 429);
    assert.equal(r.body.code, 'JAP_TOO_SOON');
    assert.equal(r.body.retryAfterSeconds, 45);
    assert.equal(r.body.paidToday, 1);
    assert.equal(japRows(1).length, 1);
    const today = await call(srv.url, 'GET', '/jap/today', { token: user });
    assert.equal(today.body.retryAfterSeconds, 45);
    now += 45e3; // exactly 90 s after the first
    const ok = await claim(user, { malaIndex: 2 });
    assert.deepEqual(ok.body, { awarded: 5, balance: 10, paidToday: 2, cap: 3, dailyCapReached: false });
  });

  await t.test('stops at 3 paid malas a day', async () => {
    now += 91e3;
    const third = await claim(user, { malaIndex: 3 });
    assert.deepEqual(third.body, { awarded: 5, balance: 15, paidToday: 3, cap: 3, dailyCapReached: true });
    now += 600e3;
    const fourth = await claim(user, { malaIndex: 4 });
    assert.equal(fourth.status, 200);
    assert.deepEqual(fourth.body, { awarded: 0, balance: 15, paidToday: 3, cap: 3, dailyCapReached: true });
    // malaIndex cannot pick a slot or bypass the cap
    const forged = await claim(user, { malaIndex: 1 });
    assert.equal(forged.body.awarded, 0);
    assert.deepEqual(japRows(1).map((x) => x.ref).sort(), ['2026-11-05:1', '2026-11-05:2', '2026-11-05:3']);
    const today = await call(srv.url, 'GET', '/jap/today', { token: user });
    assert.equal(today.body.paidToday, 3);
    assert.equal(today.body.dailyCapReached, true);
  });

  await t.test('refs are idempotent in the ledger', async () => {
    assert.equal(await C.awardCoins(fake, 1, 5, 'jap_mala', '2026-11-05:2', 'dup'), 0);
    assert.equal(await C.balanceOf(fake, 1), 15);
  });

  await t.test('the cap is per account', async () => {
    const r = await claim(other, {});
    assert.deepEqual(r.body, { awarded: 5, balance: 5, paidToday: 1, cap: 3, dailyCapReached: false });
  });

  await t.test('the day rolls over at IST midnight, not UTC', async () => {
    // 23:59 IST on 2026-11-05 is still the same day: capped.
    now = Date.parse('2026-11-05T18:29:00Z');
    const late = await claim(user, {});
    assert.equal(late.body.dailyCapReached, true);
    assert.equal(late.body.awarded, 0);
    // 00:00:30 IST on 2026-11-06 (still 2026-11-05 in UTC): a fresh day with fresh slots. The previous
    // paid mala was yesterday, so the 90 s rule does not carry over midnight.
    now = Date.parse('2026-11-05T18:30:30Z');
    const today = await call(srv.url, 'GET', '/jap/today', { token: user });
    assert.deepEqual(today.body, { day: '2026-11-06', paidToday: 0, cap: 3, coinsPerMala: 5, dailyCapReached: false, retryAfterSeconds: 0 });
    const fresh = await claim(user, {});
    assert.deepEqual(fresh.body, { awarded: 5, balance: 20, paidToday: 1, cap: 3, dailyCapReached: false });
    assert.ok(japRows(1).some((x) => x.ref === '2026-11-06:1'));
  });

  await t.test('GET /api/coins lists jap in ways to earn', async () => {
    const r = await call(srv.url, 'GET', '', { token: user });
    assert.equal(r.status, 200);
    assert.ok(r.body.earnRules.some((x) => x.key === 'jap_mala' && x.coins === 5));
  });
});
