// Trips: geo helpers, temples data and /api/trips routes against an in-memory fake db.
const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve, call } = require('./fake_db');

const fake = install();
const C = require('../services/coins_service');
const { signToken } = require('../routes/auth');
const tripsRouter = require('../routes/trips');

const T = tripsRouter._internals;

test('haversineKm matches known distances', () => {
  const delhi = { lat: 28.6139, lng: 77.209 };
  const mumbai = { lat: 19.076, lng: 72.8777 };
  const d = T.haversineKm(delhi, mumbai);
  assert.ok(d > 1140 && d < 1160, String(d));
  assert.equal(T.haversineKm(delhi, delhi), 0);
});

test('midpoint lies between both points and is equidistant', () => {
  const a = { lat: 28.61, lng: 77.21 };
  const b = { lat: 13.08, lng: 80.27 };
  const m = T.midpoint(a, b);
  assert.ok(Math.abs(T.haversineKm(a, m) - T.haversineKm(b, m)) < 1);
  assert.ok(m.lat < a.lat && m.lat > b.lat);
  const same = T.midpoint(a, a);
  assert.ok(Math.abs(same.lat - a.lat) < 1e-9 && Math.abs(same.lng - a.lng) < 1e-9);
});

test('originFor falls back sensibly', () => {
  const a = { lat: 10, lng: 76 };
  const b = { lat: 20, lng: 78 };
  assert.equal(T.originFor(null, null).point, null);
  assert.deepEqual(T.originFor(a, null), { point: a, shared: false });
  assert.deepEqual(T.originFor(null, b), { point: b, shared: true });
  assert.equal(T.originFor(a, b).shared, true);
  assert.equal(T.originFor({ lat: NaN, lng: 1 }, null).point, null);
});

test('temples.json is well formed and inside India', () => {
  const ids = new Set();
  assert.ok(T.TEMPLES.length >= 55 && T.TEMPLES.length <= 70, String(T.TEMPLES.length));
  for (const t of T.TEMPLES) {
    assert.ok(/^[a-z0-9_]+$/.test(t.id) && !ids.has(t.id), t.id);
    ids.add(t.id);
    for (const k of ['name', 'deity', 'city', 'state', 'why']) assert.ok(typeof t[k] === 'string' && t[k].length > 1, `${t.id}.${k}`);
    assert.ok(t.lat > 6 && t.lat < 36 && t.lng > 68 && t.lng < 98, `${t.id} coords`);
    assert.ok(t.why.length <= 120, `${t.id} why too long`);
  }
  assert.equal(T.TEMPLES.filter((t) => (t.tags || []).includes('Jyotirlinga')).length, 12);
  for (const id of ['tirupati', 'vaishno_devi', 'golden_temple', 'kedarnath', 'badrinath', 'jagannath_puri', 'dwarkadhish', 'rameswaram']) assert.ok(ids.has(id), id);
});

test('rankTemples recommends the nearest five, or popular ones without a location', () => {
  const varanasi = { lat: 25.32, lng: 83.0 };
  const r = T.rankTemples(T.TEMPLES, varanasi);
  assert.equal(r.recommended.length, 5);
  assert.equal(r.recommended[0], 'kashi_vishwanath');
  assert.equal(r.temples[0].id, 'kashi_vishwanath');
  assert.ok(r.temples.every((t, i, arr) => i === 0 || t.distanceKm >= arr[i - 1].distanceKm - 1));
  const coarse = T.rankTemples(T.TEMPLES, varanasi, { coarse: true });
  assert.ok(coarse.temples.every((t) => t.distanceKm % 10 === 0 && t.distanceKm >= 10));
  const none = T.rankTemples(T.TEMPLES, null);
  assert.equal(none.recommended.length, 5);
  assert.ok(none.temples.every((t) => t.distanceKm === null));
  for (const id of none.recommended) assert.ok(T.TEMPLES.find((t) => t.id === id).popular);
});

test('validMonth: this IST month up to 24 months ahead', () => {
  const now = Date.parse('2026-11-05T06:00:00Z');
  assert.ok(T.validMonth('2026-11', now));
  assert.ok(T.validMonth('2028-11', now));
  assert.equal(T.validMonth('2028-12', now), false);
  assert.equal(T.validMonth('2026-10', now), false);
  assert.equal(T.validMonth('2026-13', now), false);
  assert.equal(T.validMonth('2026-1', now), false);
  assert.equal(T.validMonth(202611, now), false);
});

test('trips routes', async (t) => {
  const srv = await serve(tripsRouter, '/api/trips');
  t.after(() => srv.close());
  const store = fake.reset();
  store.users.set(1, { role: 'user', full_name: 'Asha Rao' });
  store.users.set(2, { role: 'user', full_name: 'Vikram Singh' });
  store.users.set(3, { role: 'user', full_name: 'Stranger Person' });
  store.users.set(9, { role: 'guest', full_name: 'Guest' });
  store.buddyProfiles.set(1, { lat: 28.61, lng: 77.21, display_name: 'Asha' }); // Delhi
  store.buddyProfiles.set(2, { lat: 26.91, lng: 75.79 }); // Jaipur (rounded buddy-profile location)
  store.birth.set(2, { latitude: 12.97, longitude: 77.59 }); // Bengaluru birth place: private, never used for a buddy
  store.buddyProfiles.set(3, { lat: 9.93, lng: 76.26, display_name: 'Stranger' }); // Kochi
  store.connections.push({ from_user_id: 2, to_user_id: 1, status: 'accepted' });
  store.connections.push({ from_user_id: 1, to_user_id: 3, status: 'pending' });
  const asha = signToken({ userId: 1, role: 'user' });
  const vikram = signToken({ userId: 2, role: 'user' });
  const month = C.istMonth();

  await t.test('login required', async () => {
    for (const [m, p] of [['GET', '/temples'], ['GET', '/'], ['POST', '/request'], ['POST', '/1/cancel']]) {
      assert.equal((await call(srv.url, m, p, { body: m === 'POST' ? {} : undefined })).body.code, 'LOGIN_REQUIRED');
      assert.equal((await call(srv.url, m, p, { token: signToken({ userId: 9, role: 'guest' }), body: m === 'POST' ? {} : undefined })).status, 401);
    }
  });

  await t.test('temples near me, then near the midpoint with my buddy', async () => {
    const mine = await call(srv.url, 'GET', '/temples', { token: asha });
    assert.equal(mine.status, 200);
    assert.equal(mine.body.recommended.length, 5);
    assert.equal(mine.body.temples.length, T.TEMPLES.length);
    assert.equal(mine.body.recommended[0], 'akshardham_delhi');

    const pair = await call(srv.url, 'GET', '/temples?buddyId=2', { token: asha });
    assert.equal(pair.status, 200);
    assert.ok(pair.body.temples.every((x) => x.distanceKm % 10 === 0), 'coarse distances with a buddy');
    assert.notDeepEqual(pair.body.recommended, mine.body.recommended);

    // Not an accepted buddy: their location is ignored
    const stranger = await call(srv.url, 'GET', '/temples?buddyId=3', { token: asha });
    assert.deepEqual(stranger.body.recommended, mine.body.recommended);

    // A buddy without a buddy-profile location: their birth place is NOT used
    const saved = store.buddyProfiles.get(2);
    store.buddyProfiles.delete(2);
    const noLoc = await call(srv.url, 'GET', '/temples?buddyId=2', { token: asha });
    store.buddyProfiles.set(2, saved);
    assert.deepEqual(noLoc.body.recommended, mine.body.recommended);
    assert.deepEqual(noLoc.body.temples.map((x) => x.distanceKm), mine.body.temples.map((x) => x.distanceKm));

    // My own birth place is still a fine fallback for me
    const savedMe = store.buddyProfiles.get(1);
    store.buddyProfiles.delete(1);
    store.birth.set(1, { latitude: 25.32, longitude: 83.0 }); // Varanasi
    const byBirth = await call(srv.url, 'GET', '/temples', { token: asha });
    store.buddyProfiles.set(1, savedMe);
    assert.equal(byBirth.body.recommended[0], 'kashi_vishwanath');
  });

  await t.test('request validation and buddy check', async () => {
    assert.equal(T.parseUserId('2147483648'), null);
    assert.equal((await call(srv.url, 'POST', '/99999999999/cancel', { token: asha })).status, 404);
    assert.equal((await call(srv.url, 'GET', '/temples?buddyId=99999999999', { token: asha })).status, 200);
    const huge = await call(srv.url, 'POST', '/request', { token: asha, body: { buddyId: 99999999999, templeId: 'tirupati', preferredMonth: month } });
    assert.equal(huge.body.code, 'BAD_BUDDY');
    const bad = [
      [{ buddyId: 1, templeId: 'tirupati', preferredMonth: month }, 'BAD_BUDDY'],
      [{ buddyId: 2, templeId: 'nowhere', preferredMonth: month }, 'BAD_TEMPLE'],
      [{ buddyId: 2, templeId: 'tirupati', preferredMonth: '2020-01' }, 'BAD_MONTH'],
    ];
    for (const [body, code] of bad) {
      const r = await call(srv.url, 'POST', '/request', { token: asha, body });
      assert.equal(r.status, 400);
      assert.equal(r.body.code, code);
    }
    store.ledger.push({ id: 500, user_id: 1, amount: 12000, reason: 'question', ref: 'seed', note: null, created_at: new Date() });
    const nb = await call(srv.url, 'POST', '/request', { token: asha, body: { buddyId: 3, templeId: 'tirupati', preferredMonth: month } });
    assert.equal(nb.status, 403);
    assert.equal(nb.body.code, 'NOT_BUDDIES');
    // a buddy banned by the team is no longer a valid trip partner
    store.buddyProfiles.get(2).banned_at = new Date();
    const banned = await call(srv.url, 'POST', '/request', { token: asha, body: { buddyId: 2, templeId: 'tirupati', preferredMonth: month } });
    delete store.buddyProfiles.get(2).banned_at;
    assert.equal(banned.body.code, 'NOT_BUDDIES');
    assert.equal(store.trips.length, 0);
  });

  await t.test('request deducts 10000 once; second is refused for low balance', async () => {
    const r = await call(srv.url, 'POST', '/request', { token: asha, body: { buddyId: 2, templeId: 'tirupati', preferredMonth: month } });
    assert.equal(r.status, 200);
    assert.equal(r.body.balance, 2000);
    assert.equal(r.body.request.status, 'pending');
    assert.equal(r.body.request.temple.id, 'tirupati');
    assert.deepEqual(r.body.request.buddy, { userId: 2, displayName: 'Vikram' });
    assert.equal(r.body.request.preferredMonth, month);
    assert.ok(store.log.some((s) => s === 'SELECT id FROM users WHERE id = $1 FOR UPDATE'), 'locks the user row');
    const tripRow = store.ledger.find((x) => x.reason === 'trip');
    assert.equal(tripRow.amount, -10000);
    assert.equal(tripRow.ref, `trip:${r.body.request.id}`);

    const again = await call(srv.url, 'POST', '/request', { token: asha, body: { buddyId: 2, templeId: 'kedarnath', preferredMonth: month } });
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'INSUFFICIENT_COINS');
    assert.equal(again.body.balance, 2000);
    assert.equal(store.trips.length, 1);
  });

  await t.test('list shows the trip to both people', async () => {
    const a = await call(srv.url, 'GET', '/', { token: asha });
    assert.equal(a.body.requests.length, 1);
    assert.equal(a.body.requests[0].mine, true);
    const v = await call(srv.url, 'GET', '/', { token: vikram });
    assert.equal(v.body.requests.length, 1);
    assert.equal(v.body.requests[0].mine, false);
    assert.deepEqual(v.body.requests[0].buddy, { userId: 1, displayName: 'Asha' });
  });

  await t.test('cancel refunds once; only the requester can cancel', async () => {
    const id = store.trips[0].id;
    const other = await call(srv.url, 'POST', `/${id}/cancel`, { token: vikram });
    assert.equal(other.status, 404);
    const r = await call(srv.url, 'POST', `/${id}/cancel`, { token: asha });
    assert.equal(r.status, 200);
    assert.equal(r.body.request.status, 'cancelled');
    assert.equal(r.body.balance, 12000);
    const again = await call(srv.url, 'POST', `/${id}/cancel`, { token: asha });
    assert.equal(again.status, 409);
    assert.equal(store.ledger.filter((x) => x.reason === 'trip_refund').length, 1);
  });
});
