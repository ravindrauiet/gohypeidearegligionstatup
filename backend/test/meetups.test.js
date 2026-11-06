// Satsang meetups (routes/meetups.js + its admin router). No database: an in-memory fake `db`
// dispatches on the /*q:name*/ tag each statement starts with. Run: npm test
process.env.NEON_DATABASE_URL = '';
process.env.DATABASE_URL = '';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'meetups-test-secret-0123456789';
process.env.ADMIN_KEY = 'meetups-admin-key-0123456789';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const express = require('express');

// ---------------------------------------------------------------------------
// Fake db
// ---------------------------------------------------------------------------
const NOW = Date.parse('2026-11-05T06:00:00Z');
let now = NOW;
const H = 3600 * 1000;

let t;
let seq;
let noVerifiedColumn = false;
const log = [];
function reset() {
  t = { users: [], birth: [], bp: [], blocks: [], meetups: [], rsvps: [], ledger: [] };
  seq = 1;
  noVerifiedColumn = false;
  log.length = 0;
  now = NOW;
}
reset();
const tick = () => new Date(now + (seq++));
const find = (tbl, uid) => t[tbl].find((r) => r.user_id === uid);
const isGoing = (s) => s === 'going' || s === 'checked_in';
const sleep = () => new Promise((r) => setImmediate(r));

function meetupRow(m) {
  const hu = t.users.find((u) => u.id === m.host_user_id);
  const hbp = find('bp', m.host_user_id);
  const rs = t.rsvps.filter((r) => r.meetup_id === m.id);
  return {
    ...m,
    going_count: rs.filter((r) => isGoing(r.status)).length,
    checked_in_count: rs.filter((r) => r.status === 'checked_in').length,
    host_full_name: hu ? hu.full_name : null,
    host_email: hu ? hu.email : null,
    host_display_name: hbp ? hbp.display_name : null,
    host_banned_at: hbp ? hbp.banned_at || null : null,
    host_verified_at: hbp && !noVerifiedColumn ? hbp.verified_at || null : null,
  };
}

const handlers = {
  mtViewer: ([uid]) => {
    const u = t.users.find((x) => x.id === uid);
    if (!u) return [];
    const bd = find('birth', uid) || {};
    const bp = find('bp', uid);
    return [{
      id: u.id, role: u.role, full_name: u.full_name, user_gender: u.gender || null,
      date_of_birth: bd.date_of_birth || null, birth_gender: bd.gender || null,
      bp_user_id: bp ? uid : null, display_name: bp ? bp.display_name : null, gender: bp ? bp.gender : null,
      city: bp ? bp.city : null, lat: bp ? bp.lat : null, lng: bp ? bp.lng : null,
      banned_at: bp ? bp.banned_at || null : null, verified_at: bp && !noVerifiedColumn ? bp.verified_at || null : null,
    }];
  },
  mtBlocks: ([me]) => t.blocks.filter((b) => b.user_id === me || b.blocked_user_id === me),
  mtGet: ([id]) => t.meetups.filter((m) => m.id === id).map(meetupRow),
  mtMyRsvps: ([me, ids]) => t.rsvps.filter((r) => r.user_id === me && ids.includes(r.meetup_id)),
  mtAttendees: ([ids]) => t.rsvps.filter((r) => ids.includes(r.meetup_id) && isGoing(r.status))
    .sort((a, b) => a.created_at - b.created_at)
    .map((r) => {
      const u = t.users.find((x) => x.id === r.user_id);
      const bp = find('bp', r.user_id);
      return {
        meetup_id: r.meetup_id, user_id: r.user_id, status: r.status, full_name: u.full_name,
        display_name: bp ? bp.display_name : null, banned_at: bp ? bp.banned_at || null : null,
        is_active: bp ? bp.is_active !== false : null, bp_user_id: bp ? r.user_id : null,
        verified_at: bp && !noVerifiedColumn ? bp.verified_at || null : null,
      };
    }),
  mtList: ([nowIso, type, minLat, maxLat, minLng, maxLng, city, limit]) => t.meetups
    .filter((m) => m.status === 'approved' && Date.parse(m.ends_at) > Date.parse(nowIso))
    .filter((m) => type === null || m.type === type)
    .filter((m) => minLat === null || (m.lat >= minLat && m.lat <= maxLat && m.lng >= minLng && m.lng <= maxLng))
    .filter((m) => city === null || String(m.city).toLowerCase() === city.toLowerCase())
    .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
    .slice(0, limit).map(meetupRow),
  mtMine: ([me]) => t.rsvps.filter((r) => r.user_id === me && isGoing(r.status))
    .map((r) => ({ ...meetupRow(t.meetups.find((m) => m.id === r.meetup_id)), my_status: r.status, my_checked_in_at: r.checked_in_at || null }))
    .sort((a, b) => Date.parse(b.starts_at) - Date.parse(a.starts_at)),
  mtHosted: ([me]) => t.meetups.filter((m) => m.host_user_id === me).map(meetupRow),
  mtRecentProposals: ([me, since]) => [{ n: t.meetups.filter((m) => m.host_user_id === me && m.created_at > new Date(since)).length }],
  mtInsert: (p) => {
    const [title, type, description, venue_name, temple_id, address, lat, lng, city, starts_at, ends_at, capacity, women_only, host_user_id, status, checkin_code] = p;
    const row = { id: t.meetups.length + 1, title, type, description, venue_name, temple_id, address, lat, lng, city, starts_at, ends_at, capacity, women_only, host_user_id, status, checkin_code, admin_note: null, created_at: tick(), updated_at: tick() };
    t.meetups.push(row);
    return [{ id: row.id }];
  },
  mtLock: ([id]) => t.meetups.filter((m) => m.id === id).map((m) => ({ ...m })),
  mtRsvpGet: ([mid, uid]) => t.rsvps.filter((r) => r.meetup_id === mid && r.user_id === uid).map((r) => ({ ...r })),
  mtGoingCount: ([mid]) => [{ n: t.rsvps.filter((r) => r.meetup_id === mid && isGoing(r.status)).length }],
  mtRsvpUpsert: ([mid, uid]) => {
    const ex = t.rsvps.find((r) => r.meetup_id === mid && r.user_id === uid);
    if (ex) Object.assign(ex, { status: 'going', created_at: tick(), checked_in_at: null });
    else t.rsvps.push({ meetup_id: mid, user_id: uid, status: 'going', code_attempts: 0, created_at: tick(), checked_in_at: null });
    return [];
  },
  mtRsvpCancel: ([mid, uid]) => {
    const r = t.rsvps.find((x) => x.meetup_id === mid && x.user_id === uid && x.status === 'going');
    if (!r) return [];
    r.status = 'cancelled';
    return [{ meetup_id: mid }];
  },
  mtHostCancel: ([id, uid, nowIso]) => {
    const m = t.meetups.find((x) => x.id === id && x.host_user_id === uid && ['pending', 'approved'].includes(x.status) && Date.parse(x.ends_at) > Date.parse(nowIso));
    if (!m) return [];
    m.status = 'cancelled';
    return [{ ...m }];
  },
  mtCodeAttempt: ([mid, uid]) => {
    const r = t.rsvps.find((x) => x.meetup_id === mid && x.user_id === uid);
    if (r) r.code_attempts = (r.code_attempts || 0) + 1;
    return [];
  },
  mtCheckin: ([mid, uid]) => {
    const r = t.rsvps.find((x) => x.meetup_id === mid && x.user_id === uid && x.status === 'going');
    if (!r) return [];
    Object.assign(r, { status: 'checked_in', checked_in_at: tick() });
    return [{ meetup_id: mid }];
  },
  mtGoingUsers: ([mid]) => t.rsvps.filter((r) => r.meetup_id === mid && isGoing(r.status)).map((r) => ({ user_id: r.user_id })),
  mtAdminList: ([status, nowIso]) => t.meetups
    .filter((m) => status === 'all' || (status === 'upcoming' && m.status === 'approved' && Date.parse(m.ends_at) > Date.parse(nowIso)) || m.status === status)
    .map(meetupRow),
  mtAdminStatus: ([id, to, note, from]) => {
    const m = t.meetups.find((x) => x.id === id && from.includes(x.status));
    if (!m) return [];
    m.status = to;
    if (note) m.admin_note = note;
    return [{ ...m }];
  },
};

let lock = Promise.resolve();
const fakeDb = {
  async query(sql, params = []) {
    const s = String(sql).replace(/\s+/g, ' ').trim();
    if (s === 'SELECT role FROM users WHERE id = $1') return { rows: t.users.filter((u) => u.id === params[0]).map((u) => ({ role: u.role })) };
    if (s.startsWith('INSERT INTO coin_ledger')) {
      const [userId, amount, reason, ref] = params;
      if (t.ledger.some((r) => r.user_id === userId && r.reason === reason && r.ref === ref)) return { rows: [] };
      t.ledger.push({ id: t.ledger.length + 1, user_id: userId, amount, reason, ref });
      return { rows: [{ id: t.ledger.length }] };
    }
    if (s.startsWith('SELECT COALESCE(SUM(amount), 0) AS balance FROM coin_ledger')) {
      return { rows: [{ balance: t.ledger.filter((r) => r.user_id === params[0]).reduce((a, r) => a + r.amount, 0) }] };
    }
    const m = /^\/\*q:(\w+)\*\//.exec(s);
    if (!m) throw new Error(`untagged query: ${s.slice(0, 80)}`);
    if (noVerifiedColumn && /\.verified_at/.test(s)) {
      const err = new Error('column bp.verified_at does not exist');
      err.code = '42703';
      throw err;
    }
    const h = handlers[m[1]];
    if (!h) throw new Error(`fake db: no handler for ${m[1]}`);
    log.push(m[1]);
    await sleep(); // let concurrent requests interleave like a real pool would
    return { rows: h(params) };
  },
  // Serialised like row locks (FOR UPDATE) would serialise RSVPs to one event.
  async withTransaction(fn) {
    const prev = lock;
    let release;
    lock = new Promise((r) => { release = r; });
    await prev;
    const snap = JSON.stringify({ rsvps: t.rsvps, ledger: t.ledger });
    try {
      return await fn(fakeDb);
    } catch (err) {
      const back = JSON.parse(snap);
      t.rsvps = back.rsvps.map((r) => ({ ...r, created_at: new Date(r.created_at) }));
      t.ledger = back.ledger;
      throw err;
    } finally {
      release();
    }
  },
  ensureInitialized: async () => {},
};
const dbPath = require.resolve(path.join(__dirname, '..', 'db.js'));
require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: fakeDb };

const { signToken } = require('../routes/auth');
const meetups = require('../routes/meetups');
const push = require('../services/push_service');
const pushed = [];
push.sendToUser = async (userId, msg, opts) => { pushed.push({ userId, ...msg, opts }); return {}; };
const I = meetups._internal;
I.setClock(() => now);

// ---------------------------------------------------------------------------
// Server + seed
// ---------------------------------------------------------------------------
let base;
let adminBase;
let server;
test.before(async () => {
  const app = express();
  app.use(express.json());
  app.use('/api/meetups', meetups);
  app.use('/api/admin', require('../routes/admin'));
  await new Promise((r) => { server = app.listen(0, '127.0.0.1', r); });
  base = `http://127.0.0.1:${server.address().port}/api/meetups`;
  adminBase = `http://127.0.0.1:${server.address().port}/api/admin/meetups`;
});
test.after(() => new Promise((r) => server.close(r)));

const DELHI = { lat: 28.6129, lng: 77.2295 }; // India Gate
const VENUE = { lat: 28.5535, lng: 77.2588 }; // ~7 km away
const NOIDA = { lat: 28.5355, lng: 77.391 }; // ~18 km away
const MUMBAI = { lat: 19.076, lng: 72.8777 };

function addUser(id, { name = `User ${id}`, role = 'user', dob = '1992-04-10', gender = 'male', bp = true, verified = false, banned = false, loc = DELHI } = {}) {
  t.users.push({ id, role, full_name: name, gender, email: `u${id}@example.com` });
  if (dob) t.birth.push({ user_id: id, date_of_birth: dob, gender });
  if (bp) {
    t.bp.push({
      user_id: id, display_name: name.split(' ')[0], gender, city: 'Delhi', lat: loc ? loc.lat : null, lng: loc ? loc.lng : null,
      is_active: true, banned_at: banned ? new Date(NOW - H) : null, verified_at: verified ? new Date(NOW - 24 * H) : null,
    });
  }
}
function addMeetup(over = {}) {
  const row = {
    id: t.meetups.length + 1, title: 'Sandhya aarti together', type: 'aarti', description: 'Join us', venue_name: 'ISKCON Delhi',
    temple_id: null, address: 'Hare Krishna Hill, East of Kailash', lat: VENUE.lat, lng: VENUE.lng, city: 'Delhi',
    starts_at: new Date(NOW + 48 * H).toISOString(), ends_at: new Date(NOW + 50 * H).toISOString(), capacity: 20,
    women_only: false, host_user_id: null, status: 'approved', checkin_code: '123456', admin_note: null,
    created_at: new Date(NOW - 24 * H), updated_at: new Date(NOW - 24 * H), ...over,
  };
  t.meetups.push(row);
  return row;
}
function seed() {
  reset();
  pushed.length = 0;
  addUser(1, { name: 'Asha Verma', gender: 'female', verified: true });
  addUser(2, { name: 'Ravi Kumar' });
  addUser(3, { name: 'Kid Young', dob: '2012-01-01' });
  addUser(4, { name: 'Bad Actor', banned: true });
  addUser(5, { name: 'Meera Shah', gender: 'female' });
  addUser(6, { name: 'No Birth', dob: null, bp: false });
  addUser(7, { name: 'Vikram Rao', verified: true });
  addUser(99, { name: 'Guest', role: 'guest', dob: null, bp: false });
}
test.beforeEach(seed);

const tok = (id, role = 'user') => signToken({ userId: id, role });
async function call(method, url, { as, body, admin } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (as) headers.Authorization = `Bearer ${tok(as, as === 99 ? 'guest' : 'user')}`;
  if (admin) headers['x-admin-key'] = admin === true ? process.env.ADMIN_KEY : admin;
  const res = await fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  let json = null;
  try { json = await res.json(); } catch (_) { /* empty */ }
  return { status: res.status, body: json };
}
const api = (method, p, opts) => call(method, base + p, opts);
const adminApi = (method, p, opts = {}) => call(method, adminBase + p, { admin: true, ...opts });
const rsvp = (id, as) => api('POST', `/${id}/rsvp`, { as });

function proposal(over = {}) {
  return {
    title: 'Hanuman Chalisa satsang', type: 'satsang', description: 'We will chant together.',
    venueName: 'Prachin Hanuman Mandir', address: 'Baba Kharak Singh Marg, Connaught Place', city: 'New Delhi',
    lat: 28.6315, lng: 77.2167,
    startsAt: new Date(NOW + 72 * H).toISOString(), endsAt: new Date(NOW + 74 * H).toISOString(), capacity: 15, ...over,
  };
}

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------
test('helpers: initials, meters, check-in window', () => {
  assert.equal(I.initials('Asha Verma'), 'AV');
  assert.equal(I.initials('  ravi '), 'R');
  assert.equal(I.initials(''), '?');
  const d = I.metersBetween(28.6129, 77.2295, 28.6129, 77.2325);
  assert.ok(d > 280 && d < 310, String(d));
  const m = { starts_at: new Date(NOW + H).toISOString(), ends_at: new Date(NOW + 3 * H).toISOString() };
  assert.equal(I.checkinOpen(m, NOW), false);
  assert.equal(I.checkinOpen(m, NOW + 30 * 60 * 1000), true);
  assert.equal(I.checkinOpen(m, NOW + 3 * H), true);
  assert.equal(I.checkinOpen(m, NOW + 3 * H + 1), false);
});

test('validateMeetup: types, capacity, times, temple defaults, women-only hosts', () => {
  const v = I.validateMeetup(proposal(), { viewer: { gender: 'male' } });
  assert.equal(v.capacity, 15);
  assert.throws(() => I.validateMeetup(proposal({ type: 'party' })), /type must be/);
  assert.throws(() => I.validateMeetup(proposal({ capacity: 4 })), /Capacity/);
  assert.throws(() => I.validateMeetup(proposal({ capacity: 51 })), /Capacity/);
  assert.throws(() => I.validateMeetup(proposal({ startsAt: new Date(NOW + H).toISOString() })), /12 hours/);
  assert.throws(() => I.validateMeetup(proposal({ endsAt: new Date(NOW + 72 * H).toISOString() })), /15 minutes/);
  assert.throws(() => I.validateMeetup(proposal({ lat: 200 })), /location/);
  assert.throws(() => I.validateMeetup(proposal({ womenOnly: true }), { viewer: { gender: 'male' } }), /women/);
  assert.equal(I.validateMeetup(proposal({ womenOnly: true }), { viewer: { gender: 'female' } }).womenOnly, true);
  // Admin: any future time, any host gender rule does not apply.
  assert.ok(I.validateMeetup(proposal({ startsAt: new Date(NOW + H).toISOString(), endsAt: new Date(NOW + 2 * H).toISOString(), womenOnly: true }), { admin: true }));
  const temple = I.validateMeetup({ templeId: 'somnath', type: 'aarti', title: 'Somnath aarti', startsAt: new Date(NOW + 24 * H).toISOString(), endsAt: new Date(NOW + 25 * H).toISOString(), capacity: 10 }, { admin: true });
  assert.equal(temple.venueName, 'Somnath Temple');
  assert.equal(temple.templeId, 'somnath');
  assert.ok(temple.address.includes('Gujarat'));
  assert.equal(temple.lat, 20.888);
  assert.throws(() => I.validateMeetup({ ...proposal(), templeId: 'nope' }), /Unknown temple/);
});

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------
test('list: radius, sort by start then distance, no coordinates leaked', async () => {
  addMeetup({ title: 'Near later', starts_at: new Date(NOW + 30 * H).toISOString(), ends_at: new Date(NOW + 31 * H).toISOString() });
  addMeetup({ title: 'Far same time', lat: NOIDA.lat, lng: NOIDA.lng, starts_at: new Date(NOW + 10 * H).toISOString(), ends_at: new Date(NOW + 11 * H).toISOString() });
  addMeetup({ title: 'Near same time', starts_at: new Date(NOW + 10 * H).toISOString(), ends_at: new Date(NOW + 11 * H).toISOString() });
  addMeetup({ title: 'Mumbai', lat: MUMBAI.lat, lng: MUMBAI.lng, city: 'Mumbai' });
  addMeetup({ title: 'Ended', starts_at: new Date(NOW - 5 * H).toISOString(), ends_at: new Date(NOW - 4 * H).toISOString() });
  addMeetup({ title: 'Pending', status: 'pending' });
  addMeetup({ title: 'Live now', starts_at: new Date(NOW - H).toISOString(), ends_at: new Date(NOW + H).toISOString() });

  const r = await api('GET', `/?lat=${DELHI.lat}&lng=${DELHI.lng}`);
  assert.equal(r.status, 200);
  assert.equal(r.body.origin, 'location');
  assert.equal(r.body.radiusKm, 25);
  assert.deepEqual(r.body.meetups.map((m) => m.title), ['Live now', 'Near same time', 'Far same time', 'Near later']);
  const near = r.body.meetups[1];
  assert.equal(near.distanceKm, 7);
  assert.equal(Number.isInteger(near.distanceKm), true);
  assert.equal(near.lat, undefined);
  assert.equal(near.lng, undefined);
  assert.equal(near.official, true);
  assert.equal(near.host, null);
  assert.equal(near.spotsLeft, 20);
  assert.equal(near.myStatus, null);
  assert.equal(near.attendees, null);
  assert.equal(r.body.meetups[0].phase, 'live');

  const small = await api('GET', `/?lat=${DELHI.lat}&lng=${DELHI.lng}&radiusKm=10`);
  assert.deepEqual(small.body.meetups.map((m) => m.title), ['Live now', 'Near same time', 'Near later']);
  const big = await api('GET', `/?lat=${DELHI.lat}&lng=${DELHI.lng}&radiusKm=5000`);
  assert.equal(big.body.radiusKm, 100);
  assert.equal(big.body.meetups.some((m) => m.title === 'Mumbai'), false);

  const typed = await api('GET', `/?lat=${DELHI.lat}&lng=${DELHI.lng}&type=yoga`);
  assert.equal(typed.body.meetups.length, 0);
  assert.equal((await api('GET', '/?type=party')).status, 400);
  assert.equal((await api('GET', '/?lat=999&lng=1')).status, 400);
});

test('list without location: by city or all upcoming; signed-in users default to their profile location', async () => {
  addMeetup({ title: 'Delhi' });
  addMeetup({ title: 'Mumbai', lat: MUMBAI.lat, lng: MUMBAI.lng, city: 'Mumbai' });
  const all = await api('GET', '/');
  assert.equal(all.body.origin, 'none');
  assert.equal(all.body.meetups.length, 2);
  assert.equal(all.body.meetups[0].distanceKm, null);
  const city = await api('GET', '/?city=mumbai');
  assert.equal(city.body.origin, 'city');
  assert.deepEqual(city.body.meetups.map((m) => m.title), ['Mumbai']);
  const mine = await api('GET', '/', { as: 2 }); // Ravi's buddy profile is in Delhi
  assert.equal(mine.body.origin, 'location');
  assert.deepEqual(mine.body.meetups.map((m) => m.title), ['Delhi']);
});

test('women-only events: hidden from non-women and guests, RSVP blocked', async () => {
  const w = addMeetup({ title: 'Mahila satsang', women_only: true });
  const forAsha = await api('GET', '/', { as: 1 });
  assert.equal(forAsha.body.meetups[0].womenOnly, true);
  assert.equal((await api('GET', '/', { as: 2 })).body.meetups.length, 0);
  assert.equal((await api('GET', '/')).body.meetups.length, 0);
  assert.equal((await api('GET', `/${w.id}`, { as: 2 })).status, 404);
  const r = await rsvp(w.id, 2);
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'WOMEN_ONLY');
  assert.equal((await rsvp(w.id, 5)).status, 200);
});

test('blocks: events hosted by people I blocked / who blocked me are hidden', async () => {
  const m = addMeetup({ title: 'Asha hosts', host_user_id: 1 });
  assert.equal((await api('GET', '/', { as: 2 })).body.meetups.length, 1);
  t.blocks.push({ user_id: 1, blocked_user_id: 2 });
  assert.equal((await api('GET', '/', { as: 2 })).body.meetups.length, 0);
  assert.equal((await api('GET', `/${m.id}`, { as: 2 })).status, 404);
  assert.equal((await rsvp(m.id, 2)).status, 404);
  t.blocks = [{ user_id: 2, blocked_user_id: 1 }];
  assert.equal((await api('GET', '/', { as: 2 })).body.meetups.length, 0);
  // Host banned -> hidden from the public list
  t.blocks = [];
  find('bp', 1).banned_at = new Date();
  assert.equal((await api('GET', '/', { as: 2 })).body.meetups.length, 0);
});

test('attendee previews: only for people going, never for banned users, blocked attendees left out', async () => {
  const m = addMeetup();
  for (const id of [1, 5, 7]) assert.equal((await rsvp(m.id, id)).status, 200);
  const outsider = await api('GET', `/${m.id}`, { as: 2 });
  assert.equal(outsider.body.meetup.attendees, null);
  assert.equal(outsider.body.meetup.goingCount, 3);
  const asha = await api('GET', `/${m.id}`, { as: 1 });
  assert.deepEqual(asha.body.meetup.attendees, [
    { displayName: 'Meera', initials: 'M', verified: false },
    { displayName: 'Vikram', initials: 'V', verified: true },
  ]);
  for (const a of asha.body.meetup.attendees) assert.deepEqual(Object.keys(a).sort(), ['displayName', 'initials', 'verified']);
  t.blocks.push({ user_id: 7, blocked_user_id: 1 });
  const again = await api('GET', '/', { as: 1 });
  assert.deepEqual(again.body.meetups[0].attendees.map((a) => a.displayName), ['Meera']);
  // Banned user cannot RSVP (so never sees the list either)
  const banned = await rsvp(m.id, 4);
  assert.equal(banned.status, 403);
  assert.equal(banned.body.code, 'BANNED');
  assert.equal((await api('GET', `/${m.id}`, { as: 4 })).body.meetup.attendees, null);
  // More than 5 going -> preview capped at 5
  for (let id = 10; id < 17; id++) addUser(id);
  for (let id = 10; id < 17; id++) await rsvp(m.id, id);
  assert.equal((await api('GET', `/${m.id}`, { as: 1 })).body.meetup.attendees.length, 5);
});

// ---------------------------------------------------------------------------
// RSVP / cancel
// ---------------------------------------------------------------------------
test('rsvp: 18+, birth details, login, idempotent, push, not after start', async () => {
  const m = addMeetup();
  assert.equal((await rsvp(m.id)).status, 401);
  assert.equal((await rsvp(m.id, 99)).status, 401);
  const kid = await rsvp(m.id, 3);
  assert.equal(kid.status, 403);
  assert.equal(kid.body.code, 'UNDER_18');
  assert.equal((await rsvp(m.id, 6)).body.code, 'NO_BIRTH_DETAILS');

  const ok = await rsvp(m.id, 2);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.meetup.myStatus, 'going');
  assert.equal(ok.body.meetup.goingCount, 1);
  assert.equal(ok.body.meetup.spotsLeft, 19);
  assert.equal(pushed.length, 1);
  assert.deepEqual({ userId: pushed[0].userId, type: pushed[0].type, data: pushed[0].data, pref: pushed[0].opts.pref },
    { userId: 2, type: 'meetup_update', data: { meetupId: m.id, kind: 'rsvp_confirmed' }, pref: 'buddy' });
  const again = await rsvp(m.id, 2);
  assert.equal(again.body.changed, false);
  assert.equal(pushed.length, 1);
  assert.equal(t.rsvps.length, 1);

  const started = addMeetup({ starts_at: new Date(NOW - 60 * 1000).toISOString(), ends_at: new Date(NOW + H).toISOString() });
  const late = await rsvp(started.id, 2);
  assert.equal(late.status, 409);
  assert.equal(late.body.code, 'STARTED');
  const pending = addMeetup({ status: 'pending' });
  assert.equal((await rsvp(pending.id, 2)).status, 404);
  assert.equal((await rsvp(9999, 2)).status, 404);
});

test('rsvp capacity holds under a race (row lock), and a freed spot can be taken', async () => {
  const m = addMeetup({ capacity: 5 });
  const ids = [];
  for (let id = 20; id < 32; id++) { addUser(id); ids.push(id); }
  const results = await Promise.all(ids.map((id) => rsvp(m.id, id)));
  const ok = results.filter((r) => r.status === 200);
  const full = results.filter((r) => r.status === 409);
  assert.equal(ok.length, 5);
  assert.equal(full.length, 7);
  assert.ok(full.every((r) => r.body.code === 'FULL'));
  assert.equal(t.rsvps.filter((r) => r.status === 'going').length, 5);
  const winner = t.rsvps[0].user_id;
  const loser = ids.find((id) => !t.rsvps.some((r) => r.user_id === id));
  assert.equal((await api('POST', `/${m.id}/cancel`, { as: winner })).status, 200);
  const r = await rsvp(m.id, loser);
  assert.equal(r.status, 200);
  assert.equal(r.body.meetup.spotsLeft, 0);
});

test('cancel my RSVP: going -> cancelled, re-RSVP works, checked-in cannot cancel', async () => {
  const m = addMeetup();
  assert.equal((await api('POST', `/${m.id}/cancel`, { as: 2 })).status, 404);
  await rsvp(m.id, 2);
  const c = await api('POST', `/${m.id}/cancel`, { as: 2 });
  assert.equal(c.status, 200);
  assert.equal(c.body.meetup.myStatus, 'cancelled');
  assert.equal(c.body.meetup.goingCount, 0);
  assert.equal((await api('POST', `/${m.id}/cancel`, { as: 2 })).status, 200); // idempotent
  assert.equal((await rsvp(m.id, 2)).body.meetup.myStatus, 'going');
  t.rsvps[0].status = 'checked_in';
  const ci = await api('POST', `/${m.id}/cancel`, { as: 2 });
  assert.equal(ci.status, 409);
  assert.equal(ci.body.code, 'CHECKED_IN');
});

test('mine: upcoming (soonest first), past, hosting', async () => {
  const a = addMeetup({ title: 'Soon', starts_at: new Date(NOW + 5 * H).toISOString(), ends_at: new Date(NOW + 6 * H).toISOString() });
  const b = addMeetup({ title: 'Later' });
  const old = addMeetup({ title: 'Old', starts_at: new Date(NOW - 50 * H).toISOString(), ends_at: new Date(NOW - 48 * H).toISOString() });
  await rsvp(b.id, 2);
  await rsvp(a.id, 2);
  t.rsvps.push({ meetup_id: old.id, user_id: 2, status: 'checked_in', created_at: new Date(NOW - 60 * H), checked_in_at: new Date(NOW - 49 * H) });
  addMeetup({ title: 'Ravi proposed', host_user_id: 2, status: 'pending' });
  const r = await api('GET', '/mine', { as: 2 });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.upcoming.map((m) => m.title), ['Soon', 'Later']);
  assert.deepEqual(r.body.past.map((m) => m.title), ['Old']);
  assert.equal(r.body.past[0].myStatus, 'checked_in');
  assert.deepEqual(r.body.hosting.map((m) => [m.title, m.status, m.isHost]), [['Ravi proposed', 'pending', true]]);
  assert.equal((await api('GET', '/mine')).status, 401);
});

// ---------------------------------------------------------------------------
// Check-in
// ---------------------------------------------------------------------------
test('check-in: window, radius, coins once, balance', async () => {
  const m = addMeetup({ starts_at: new Date(NOW + 2 * H).toISOString(), ends_at: new Date(NOW + 4 * H).toISOString() });
  const at = { lat: VENUE.lat + 0.001, lng: VENUE.lng }; // ~110 m
  assert.equal((await api('POST', `/${m.id}/checkin`, { as: 2, body: at })).body.code, 'NOT_GOING');
  await rsvp(m.id, 2);
  const early = await api('POST', `/${m.id}/checkin`, { as: 2, body: at });
  assert.equal(early.status, 409);
  assert.equal(early.body.code, 'CHECKIN_NOT_OPEN');
  now = NOW + 2 * H - 29 * 60 * 1000; // 29 minutes before
  const far = await api('POST', `/${m.id}/checkin`, { as: 2, body: { lat: VENUE.lat + 0.004, lng: VENUE.lng } }); // ~445 m
  assert.equal(far.status, 409);
  assert.equal(far.body.code, 'TOO_FAR');
  assert.equal((await api('POST', `/${m.id}/checkin`, { as: 2, body: {} })).body.code, 'LOCATION_REQUIRED');
  assert.equal((await api('POST', `/${m.id}/checkin`, { as: 2, body: { lat: '28.5', lng: '77.2' } })).body.code, 'LOCATION_REQUIRED');

  const ok = await api('POST', `/${m.id}/checkin`, { as: 2, body: at });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.checkedIn, true);
  assert.equal(ok.body.method, 'location');
  assert.equal(ok.body.coinsAwarded, 100);
  assert.equal(ok.body.balance, 100);
  assert.equal(ok.body.meetup.myStatus, 'checked_in');
  assert.ok(ok.body.meetup.checkedInAt);
  assert.deepEqual(t.ledger.map((r) => [r.reason, r.ref, r.amount]), [['meetup_checkin', `event:${m.id}`, 100]]);

  const twice = await api('POST', `/${m.id}/checkin`, { as: 2, body: at });
  assert.equal(twice.status, 200);
  assert.equal(twice.body.alreadyCheckedIn, true);
  assert.equal(twice.body.coinsAwarded, 0);
  assert.equal(twice.body.balance, 100);
  assert.equal(t.ledger.length, 1);

  // Ledger dedupe even if the RSVP is reset and re-checked-in.
  t.rsvps[0].status = 'going';
  const third = await api('POST', `/${m.id}/checkin`, { as: 2, body: at });
  assert.equal(third.body.coinsAwarded, 0);
  assert.equal(t.ledger.length, 1);

  // After the end
  await rsvp(m.id, 7);
  now = NOW + 4 * H + 1000;
  assert.equal((await api('POST', `/${m.id}/checkin`, { as: 7, body: at })).body.code, 'CHECKIN_CLOSED');
});

test('check-in with the host code: works without location, wrong codes are limited, host cannot self-code', async () => {
  const m = addMeetup({ host_user_id: 1, starts_at: new Date(NOW + 10 * 60 * 1000).toISOString(), ends_at: new Date(NOW + 2 * H).toISOString(), checkin_code: '482913' });
  await rsvp(m.id, 2);
  await rsvp(m.id, 1);
  const hostView = await api('GET', `/${m.id}`, { as: 1 });
  assert.equal(hostView.body.meetup.checkinCode, '482913');
  assert.equal(hostView.body.meetup.isHost, true);
  const guestView = await api('GET', `/${m.id}`, { as: 2 });
  assert.equal(guestView.body.meetup.checkinCode, undefined);
  assert.equal(guestView.body.meetup.checkinOpen, true);
  assert.equal(guestView.body.meetup.host.displayName, 'Asha');
  assert.equal(guestView.body.meetup.host.verified, true);
  assert.equal((await api('GET', `/${m.id}`)).body.meetup.checkinCode, undefined);

  const wrong = await api('POST', `/${m.id}/checkin`, { as: 2, body: { code: '000000' } });
  assert.equal(wrong.status, 400);
  assert.equal(wrong.body.code, 'BAD_CODE');
  const ok = await api('POST', `/${m.id}/checkin`, { as: 2, body: { code: '482 913' } });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.method, 'code');
  assert.equal(ok.body.coinsAwarded, 100);
  const self = await api('POST', `/${m.id}/checkin`, { as: 1, body: { code: '482913' } });
  assert.equal(self.status, 403);
  assert.equal(self.body.code, 'HOST_CODE');

  await rsvp(m.id, 7);
  for (let i = 0; i < I.MAX_CODE_ATTEMPTS; i++) {
    assert.equal((await api('POST', `/${m.id}/checkin`, { as: 7, body: { code: '111111' } })).body.code, 'BAD_CODE');
  }
  const locked = await api('POST', `/${m.id}/checkin`, { as: 7, body: { code: '482913' } });
  assert.equal(locked.status, 429);
  // GPS still works after the code lockout
  assert.equal((await api('POST', `/${m.id}/checkin`, { as: 7, body: VENUE })).status, 200);
});

test('people you met: checked-in attendees only, after my own check-in, minus blocked', async () => {
  const m = addMeetup({ starts_at: new Date(NOW - H).toISOString(), ends_at: new Date(NOW + H).toISOString() });
  for (const id of [1, 2, 5, 7]) t.rsvps.push({ meetup_id: m.id, user_id: id, status: 'going', code_attempts: 0, created_at: tick(), checked_in_at: null });
  for (const id of [1, 5, 7]) assert.equal((await api('POST', `/${m.id}/checkin`, { as: id, body: VENUE })).status, 200);
  const notYet = await api('GET', `/${m.id}`, { as: 2 });
  assert.equal(notYet.body.meetup.peopleYouMet, undefined);
  t.blocks.push({ user_id: 7, blocked_user_id: 1 });
  const asha = await api('GET', `/${m.id}`, { as: 1 });
  assert.deepEqual(asha.body.meetup.peopleYouMet, [{ userId: 5, displayName: 'Meera', initials: 'M', verified: false, canConnect: true }]);
});

// ---------------------------------------------------------------------------
// Proposals
// ---------------------------------------------------------------------------
test('proposals: verified users only, pending until approved, 2 per week', async () => {
  const notVerified = await api('POST', '/', { as: 2, body: proposal() });
  assert.equal(notVerified.status, 403);
  assert.equal(notVerified.body.code, 'NOT_VERIFIED');
  assert.equal((await api('GET', '/can-propose', { as: 2 })).body.reason, 'NOT_VERIFIED');
  assert.equal((await api('GET', '/can-propose')).body.reason, 'LOGIN_REQUIRED');
  assert.equal((await api('POST', '/', { as: 3, body: proposal() })).body.code, 'UNDER_18');
  assert.equal((await api('POST', '/', { body: proposal() })).status, 401);

  const cp = await api('GET', '/can-propose', { as: 1 });
  assert.deepEqual(cp.body, { canPropose: true, remainingThisWeek: 2, canHostWomenOnly: true });
  const first = await api('POST', '/', { as: 1, body: proposal({ womenOnly: true }) });
  assert.equal(first.status, 200);
  assert.equal(first.body.meetup.status, 'pending');
  assert.equal(first.body.meetup.isHost, true);
  assert.match(first.body.meetup.checkinCode, /^\d{6}$/);
  // Not public while pending
  assert.equal((await api('GET', '/', { as: 5 })).body.meetups.length, 0);
  assert.equal((await api('GET', `/${first.body.meetup.id}`, { as: 5 })).status, 404);
  assert.equal((await rsvp(first.body.meetup.id, 5)).status, 404);

  assert.equal((await api('POST', '/', { as: 1, body: proposal({ capacity: 3 }) })).status, 400);
  assert.equal((await api('POST', '/', { as: 1, body: proposal() })).status, 200);
  const third = await api('POST', '/', { as: 1, body: proposal() });
  assert.equal(third.status, 429);
  assert.equal(third.body.code, 'RATE_LIMITED');
  assert.equal((await api('GET', '/can-propose', { as: 1 })).body.reason, 'RATE_LIMITED');
  // A week later the limit resets
  now = NOW + 8 * 24 * H;
  assert.equal((await api('POST', '/', { as: 1, body: proposal({ startsAt: new Date(now + 24 * H).toISOString(), endsAt: new Date(now + 25 * H).toISOString() }) })).status, 200);
  // Men cannot host women-only
  const vikram = await api('POST', '/', { as: 7, body: proposal({ womenOnly: true, startsAt: new Date(now + 24 * H).toISOString(), endsAt: new Date(now + 25 * H).toISOString() }) });
  assert.equal(vikram.status, 403);
  assert.equal(vikram.body.code, 'WOMEN_ONLY');
});

test('verified_at column missing: queries fall back and nobody counts as verified', async () => {
  noVerifiedColumn = true;
  I.resetVerifiedColumn();
  addMeetup({ host_user_id: 1 });
  const list = await api('GET', '/', { as: 2 });
  assert.equal(list.status, 200);
  assert.equal(list.body.meetups[0].host.verified, false);
  const p = await api('POST', '/', { as: 1, body: proposal() });
  assert.equal(p.status, 403);
  assert.equal(p.body.code, 'NOT_VERIFIED');
  noVerifiedColumn = false;
  I.resetVerifiedColumn();
});

test('host can cancel their own event; attendees are notified', async () => {
  const m = addMeetup({ host_user_id: 1 });
  await rsvp(m.id, 2);
  await rsvp(m.id, 5);
  pushed.length = 0;
  assert.equal((await api('POST', `/${m.id}/cancel-event`, { as: 2 })).status, 409);
  const r = await api('POST', `/${m.id}/cancel-event`, { as: 1 });
  assert.equal(r.status, 200);
  assert.equal(r.body.meetup.status, 'cancelled');
  assert.deepEqual(pushed.map((p) => [p.userId, p.data.kind]).sort(), [[2, 'cancelled'], [5, 'cancelled']]);
  // Attendee still sees it (as cancelled), outsiders don't
  assert.equal((await api('GET', `/${m.id}`, { as: 2 })).body.meetup.status, 'cancelled');
  assert.equal((await api('GET', `/${m.id}`, { as: 7 })).status, 404);
  assert.equal((await rsvp(m.id, 7)).status, 404);
});

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------
test('admin: key required, list pending, approve notifies proposer, reject', async () => {
  assert.equal((await call('GET', `${adminBase}/`)).status, 401);
  assert.equal((await call('GET', `${adminBase}/`, { admin: 'wrong-key-0123456789' })).status, 401);
  const p1 = (await api('POST', '/', { as: 1, body: proposal() })).body.meetup;
  const p2 = (await api('POST', '/', { as: 1, body: proposal({ title: 'Second one' }) })).body.meetup;
  const list = await adminApi('GET', '/');
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.meetups.map((m) => m.id), [p1.id, p2.id]);
  const row = list.body.meetups[0];
  assert.equal(row.host.userId, 1);
  assert.equal(row.host.verified, true);
  assert.match(row.checkinCode, /^\d{6}$/);
  assert.equal(row.goingCount, 0);

  pushed.length = 0;
  const ap = await adminApi('POST', `/${p1.id}/approve`);
  assert.equal(ap.status, 200);
  assert.equal(ap.body.meetup.status, 'approved');
  assert.deepEqual(pushed.map((p) => [p.userId, p.type, p.data.kind, p.data.meetupId]), [[1, 'meetup_update', 'approved', p1.id]]);
  assert.equal((await adminApi('POST', `/${p1.id}/approve`)).status, 409);
  assert.equal((await api('GET', '/', { as: 2 })).body.meetups.length, 1);

  const rj = await adminApi('POST', `/${p2.id}/reject`, { body: { note: 'Venue unclear' } });
  assert.equal(rj.body.meetup.status, 'rejected');
  assert.equal(rj.body.meetup.adminNote, 'Venue unclear');
  assert.equal(pushed[pushed.length - 1].data.kind, 'rejected');
  assert.equal((await adminApi('GET', '/?status=bogus')).status, 400);
  assert.equal((await adminApi('POST', '/999/approve')).status, 404);
});

test('admin: create official event from a temple or custom venue, cancel notifies attendees', async () => {
  const temples = await adminApi('GET', '/temples');
  assert.ok(temples.body.temples.length > 10);
  assert.ok(temples.body.types.includes('bhajan_sandhya'));
  const official = await adminApi('POST', '/', {
    body: { templeId: 'somnath', type: 'aarti', title: 'Somnath sandhya aarti', startsAt: new Date(NOW + 5 * H).toISOString(), endsAt: new Date(NOW + 6 * H).toISOString(), capacity: 30 },
  });
  assert.equal(official.status, 200);
  assert.equal(official.body.meetup.status, 'approved');
  assert.equal(official.body.meetup.host, null);
  assert.equal(official.body.meetup.venueName, 'Somnath Temple');
  const custom = await adminApi('POST', '/', { body: proposal({ startsAt: new Date(NOW + 2 * H).toISOString(), endsAt: new Date(NOW + 3 * H).toISOString() }) });
  assert.equal(custom.status, 200);
  assert.equal((await adminApi('POST', '/', { body: proposal({ capacity: 60 }) })).status, 400);
  const listed = await api('GET', '/?city=New%20Delhi');
  assert.deepEqual(listed.body.meetups.map((m) => [m.title, m.official]), [['Hanuman Chalisa satsang', true]]);

  const id = custom.body.meetup.id;
  await rsvp(id, 2);
  await rsvp(id, 5);
  pushed.length = 0;
  const c = await adminApi('POST', `/${id}/cancel`, { body: { note: 'Rain' } });
  assert.equal(c.status, 200);
  assert.equal(c.body.meetup.status, 'cancelled');
  assert.equal(c.body.notified, 2);
  assert.deepEqual(pushed.map((p) => [p.userId, p.data.kind]).sort(), [[2, 'cancelled'], [5, 'cancelled']]);
  assert.equal((await api('GET', '/mine', { as: 2 })).body.upcoming[0].status, 'cancelled');
  const up = await adminApi('GET', '/?status=upcoming');
  assert.deepEqual(up.body.meetups.map((m) => m.title), ['Somnath sandhya aarti']);
  assert.equal(up.body.meetups[0].goingCount, 0);
});
