// Buddy matching + routes (no database: routes run against an in-memory fake `db`). Run: npm test
process.env.NEON_DATABASE_URL = '';
process.env.DATABASE_URL = '';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'buddy-test-secret-0123456789';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const express = require('express');

const A = require('../services/astrology_service');
const GM = require('../services/guna_milan');
const M = require('../services/buddy_matching');

// ---------------------------------------------------------------------------
// Fake db: dispatches on the /*q:name*/ tag each buddy.js statement starts with.
// ---------------------------------------------------------------------------
function createFakeDb() {
  const t = {
    users: [], birth_details: [], kundlis: [], buddy_profiles: [], buddy_connections: [],
    buddy_messages: [], buddy_blocks: [], buddy_reports: [], mindset_answers: []
  };
  let seq = 1;
  let clock = Date.parse('2026-11-05T06:00:00Z');
  const now = () => new Date(clock += 1000);
  const log = [];
  const find = (tbl, uid) => t[tbl].find((r) => r.user_id === uid);

  function person(uid, fromUsers) {
    const u = t.users.find((x) => x.id === uid);
    const bp = find('buddy_profiles', uid);
    const bd = find('birth_details', uid);
    const k = find('kundlis', uid);
    if (!u) return null;
    if (!fromUsers && (!bp || !bd || !k)) return null;
    return {
      user_id: u.id, full_name: u.full_name, role: u.role, user_gender: u.gender,
      date_of_birth: bd ? bd.date_of_birth : null, birth_gender: bd ? bd.gender : null,
      moon_sign: k ? k.moon_sign : null, nakshatra: k ? k.nakshatra : null, ascendant: k ? k.ascendant : null,
      moon_longitude: k && k.kundli_data ? String(k.kundli_data.moonLongitude) : null,
      bp_user_id: bp ? bp.user_id : null,
      ...(bp ? {
        display_name: bp.display_name, bio: bp.bio, intents: bp.intents, gender: bp.gender, interested_in: bp.interested_in,
        city: bp.city, lat: bp.lat, lng: bp.lng, photo_url: bp.photo_url, languages: bp.languages,
        show_nearby: bp.show_nearby, is_active: bp.is_active, banned_at: bp.banned_at || null, created_at: bp.created_at, updated_at: bp.updated_at
      } : {})
    };
  }
  const blocked = (a, b) => t.buddy_blocks.some((x) => (x.user_id === a && x.blocked_user_id === b) || (x.user_id === b && x.blocked_user_id === a));

  const handlers = {
    me: ([uid]) => [person(uid, true)].filter(Boolean),
    person: ([uid]) => [person(uid, false)].filter(Boolean),
    answers: ([ids]) => t.mindset_answers.filter((a) => ids.includes(a.user_id)),
    blockedPair: ([a, b]) => (blocked(a, b) ? [{ '?column?': 1 }] : []),
    connectionPair: ([a, b]) => t.buddy_connections.filter((c) => (c.from_user_id === a && c.to_user_id === b) || (c.from_user_id === b && c.to_user_id === a)),
    blocks: ([me]) => t.buddy_blocks.filter((b) => b.user_id === me || b.blocked_user_id === me),
    myConnections: ([me]) => t.buddy_connections.filter((c) => c.from_user_id === me || c.to_user_id === me),
    candidates: ([me, excluded, cutoff, intent, intentsAny, minLat, maxLat, minLng, maxLng, nearbyOnly, limit]) => t.buddy_profiles
      .filter((bp) => bp.is_active && !bp.banned_at && bp.user_id !== me && !excluded.includes(bp.user_id))
      .map((bp) => person(bp.user_id, false)).filter(Boolean)
      .filter((p) => (p.role || 'user') !== 'guest' && p.date_of_birth <= cutoff)
      .filter((p) => intent === null || p.intents.includes(intent))
      .filter((p) => intentsAny === null || p.intents.some((i) => intentsAny.includes(i)))
      .filter((p) => minLat === null || (p.lat >= minLat && p.lat <= maxLat && p.lng >= minLng && p.lng <= maxLng))
      .filter((p) => !nearbyOnly || p.show_nearby)
      .slice(0, limit),
    upsertProfile: ([uid, display_name, bio, intents, gender, interested_in, city, languages, photo_url, show_nearby, is_active]) => {
      let bp = find('buddy_profiles', uid);
      if (!bp) { bp = { user_id: uid, lat: null, lng: null, created_at: now() }; t.buddy_profiles.push(bp); }
      Object.assign(bp, { display_name, bio, intents, gender, interested_in, city, languages, photo_url, show_nearby: bp.banned_at ? false : show_nearby, is_active: bp.banned_at ? false : is_active, updated_at: now() });
      return [];
    },
    deactivate: ([uid]) => { const bp = find('buddy_profiles', uid); if (bp) bp.is_active = false; return []; },
    location: ([uid, lat, lng, city]) => {
      const bp = find('buddy_profiles', uid);
      if (!bp || bp.banned_at) return [];
      Object.assign(bp, { lat, lng, city: city === null ? bp.city : city, updated_at: now() });
      return [{ user_id: uid }];
    },
    nearbyChecked: () => [],
    setStatus: ([id, to, from]) => {
      const c = t.buddy_connections.find((x) => x.id === id && x.status === from);
      if (!c) return [];
      Object.assign(c, { status: to, responded_at: now() });
      return [{ ...c }];
    },
    insertConnection: ([from, to, intent, message, score]) => {
      const ex = t.buddy_connections.find((c) => c.from_user_id === from && c.to_user_id === to);
      if (ex) {
        if (ex.status !== 'cancelled') return [];
        Object.assign(ex, { intent, message, score, status: 'pending', created_at: now(), responded_at: null });
        return [{ ...ex }];
      }
      const c = { id: seq++, from_user_id: from, to_user_id: to, intent, message, status: 'pending', score, created_at: now(), responded_at: null };
      t.buddy_connections.push(c);
      return [{ ...c }];
    },
    connectionById: ([id]) => t.buddy_connections.filter((c) => c.id === id).map((c) => ({ ...c })),
    connectionList: ([me]) => t.buddy_connections
      .filter((c) => (c.from_user_id === me || c.to_user_id === me) && ['pending', 'accepted'].includes(c.status))
      .map((c) => {
        const oid = c.from_user_id === me ? c.to_user_id : c.from_user_id;
        if (blocked(me, oid)) return null;
        if ((find('buddy_profiles', oid) || {}).banned_at) return null;
        const ou = t.users.find((u) => u.id === oid);
        const obp = find('buddy_profiles', oid);
        const obd = find('birth_details', oid);
        const msgs = t.buddy_messages.filter((m) => m.connection_id === c.id);
        const lm = msgs[msgs.length - 1];
        return {
          ...c, other_id: oid, other_full_name: ou.full_name, other_display_name: obp ? obp.display_name : null,
          other_city: obp ? obp.city : null, other_photo_url: obp ? obp.photo_url : null, other_dob: obd ? obd.date_of_birth : null,
          last_body: lm ? lm.body : null, last_created_at: lm ? lm.created_at : null, last_sender_id: lm ? lm.sender_id : null,
          unread: msgs.filter((m) => m.sender_id !== me && !m.read_at).length
        };
      }).filter(Boolean),
    messagesAfter: ([cid, after]) => t.buddy_messages.filter((m) => m.connection_id === cid && m.id > after),
    recentMessages: ([cid]) => t.buddy_messages.filter((m) => m.connection_id === cid).slice(-100).reverse(),
    markRead: ([cid, me]) => { t.buddy_messages.forEach((m) => { if (m.connection_id === cid && m.sender_id !== me && !m.read_at) m.read_at = now(); }); return []; },
    insertMessage: ([cid, sender, body]) => {
      const m = { id: seq++, connection_id: cid, sender_id: sender, body, created_at: now(), read_at: null };
      t.buddy_messages.push(m);
      return [{ ...m }];
    },
    bannedPair: ([ids]) => t.buddy_profiles.filter((bp) => ids.includes(bp.user_id) && bp.banned_at).map((bp) => ({ user_id: bp.user_id })),
    recentSent: ([uid]) => [{ n: t.buddy_messages.filter((m) => m.sender_id === uid && clock - m.created_at.getTime() < 60000).length }],
    recentRequests: ([uid]) => [{ n: t.buddy_connections.filter((c) => c.from_user_id === uid && clock - new Date(c.created_at).getTime() < 86400000).length }],
    recentReports: ([uid]) => [{ n: t.buddy_reports.filter((r) => r.reporter_id === uid).length }],
    userExists: ([id]) => t.users.filter((u) => u.id === id).map((u) => ({ id: u.id })),
    block: ([a, b]) => { if (!t.buddy_blocks.some((x) => x.user_id === a && x.blocked_user_id === b)) t.buddy_blocks.push({ user_id: a, blocked_user_id: b }); return []; },
    report: ([reporter, reported, reason, details]) => { t.buddy_reports.push({ reporter_id: reporter, reported_user_id: reported, reason, details }); return []; }
  };

  return {
    tables: t,
    log,
    async query(sql, params = []) {
      // routes/auth.js re-checks guest tokens against the users table
      if (/^SELECT role FROM users WHERE id = \$1$/.test(sql.trim())) {
        return { rows: t.users.filter((u) => u.id === params[0]).map((u) => ({ role: u.role })) };
      }
      const m = /^\s*\/\*q:(\w+)\*\//.exec(sql);
      if (!m) throw new Error(`untagged query: ${sql.slice(0, 60)}`);
      const h = handlers[m[1]];
      if (!h) throw new Error(`fake db: no handler for ${m[1]}`);
      log.push(m[1]);
      return { rows: h(params) };
    },
    async withTransaction(fn) { return fn(this); }
  };
}

// Install the fake db before the routes load `../db` (never touches the real database).
const fakeDb = createFakeDb();
const dbPath = require.resolve(path.join(__dirname, '..', 'db.js'));
require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: fakeDb };
const { signToken } = require('../routes/auth');
const buddyRouter = require('../routes/buddy');
const { eligibility, validateProfile, adultCutoff } = buddyRouter._internal;

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------
test('ageOn: birthdays, leap days and invalid input', () => {
  assert.equal(M.ageOn('2008-11-05', '2026-11-05'), 18);
  assert.equal(M.ageOn('2008-11-06', '2026-11-05'), 17);
  assert.equal(M.ageOn('2008-12-01', '2026-11-05'), 17);
  assert.equal(M.ageOn('2008-02-29', '2026-02-28'), 17);
  assert.equal(M.ageOn('2008-02-29', '2026-03-01'), 18);
  assert.equal(M.ageOn('1990-05-15', '2026-11-05'), 36);
  assert.equal(M.ageOn(null, '2026-11-05'), null);
  assert.equal(M.ageOn('2030-01-01', '2026-11-05'), null);
  assert.equal(adultCutoff('2026-11-05'), '2008-11-05');
  assert.equal(adultCutoff('2028-02-29'), '2010-02-28');
});

test('location: rounding, validation, haversine and display km', () => {
  assert.equal(M.roundCoord(28.61349), 28.61);
  assert.equal(M.roundCoord(-77.2051), -77.21);
  assert.equal(M.roundCoord('x'), null);
  assert.ok(M.validLatLng(28.6, 77.2));
  assert.ok(!M.validLatLng(91, 0));
  assert.ok(!M.validLatLng(0, 181));
  const delhiMumbai = M.haversineKm(28.61, 77.21, 19.08, 72.88);
  assert.ok(delhiMumbai > 1100 && delhiMumbai < 1200, String(delhiMumbai));
  assert.equal(M.haversineKm(null, 1, 2, 3), null);
  assert.equal(M.displayKm(0.2), 1);
  assert.equal(M.displayKm(3.4), 3);
  assert.equal(M.displayKm(null), null);
  const box = M.boundingBox(28.61, 77.21, 10);
  assert.ok(box.minLat < 28.53 && box.maxLat > 28.69 && box.minLng < 77.11 && box.maxLng > 77.31);
});

test('distance, mindset shrinkage and weighted total', () => {
  assert.equal(M.distanceScore(0), 100);
  assert.equal(M.distanceScore(50), 50);
  assert.equal(M.distanceScore(150), 0);
  assert.equal(M.distanceScore(5, 10), 50);
  assert.equal(M.distanceScore(null), 50);

  assert.equal(M.mindsetScore({}, {}).score, 50);
  const three = M.mindsetScore({ q01: 0, q02: 1, q03: 2 }, { q01: 0, q02: 1, q03: 2, q04: 3 });
  assert.equal(three.shared, 3);
  assert.equal(three.agree, 3);
  assert.equal(three.score, 65); // 50 + (100-50) * 3/10
  const a = {};
  const b = {};
  for (let i = 1; i <= 20; i++) { const q = `q${String(i).padStart(2, '0')}`; a[q] = 0; b[q] = i <= 15 ? 0 : 1; }
  const twenty = M.mindsetScore(a, b);
  assert.equal(twenty.shared, 20);
  assert.equal(twenty.agree, 15);
  assert.equal(twenty.score, 75);
  // category weights: agreeing on the heavier category for the intent scores higher
  const cat = (q) => (q === 'q01' ? 'career_money' : 'travel');
  const x = { q01: 0, q02: 0 };
  const agreeCareer = { q01: 0, q02: 1 };
  assert.ok(M.mindsetScore(x, agreeCareer, cat, 'business').raw > M.mindsetScore(x, agreeCareer, cat, 'travel').raw);

  assert.equal(M.totalScore('life_partner', { kundli: 80, mindset: 60, distance: 100 }), 74);
  assert.equal(M.totalScore('friend', { kundli: 80, mindset: 60, distance: 100 }), 72);
});

test('kundli: life_partner uses Guna Milan %, others use element + gana + lagna harmony', () => {
  const k1 = { moonSign: 'Cancer', nakshatra: 'Pushya', ascendant: 'Leo', moonLongitude: 100 };
  const k2 = { moonSign: 'Scorpio', nakshatra: 'Anuradha', ascendant: 'Aries', moonLongitude: 215 };
  const direct = GM.calculateAshtakoot(k1, k2).total;
  const g = M.gunaKundliScore(k1, k2, 'male', 'female');
  assert.equal(g.score, Math.round((direct / 36) * 100));
  const reversed = M.gunaKundliScore(k1, k2, 'female', 'male');
  assert.equal(reversed.score, Math.round((GM.calculateAshtakoot(k2, k1).total / 36) * 100));
  const avg = M.gunaKundliScore(k1, k2, null, null);
  assert.equal(avg.gunaTotal, (GM.calculateAshtakoot(k1, k2).total + GM.calculateAshtakoot(k2, k1).total) / 2);
  assert.equal(M.gunaKundliScore({}, {}, 'male', 'female').score, 50);

  const h = M.harmonyKundliScore(k1, k2);
  assert.equal(h.parts.element, 100); // both water
  assert.equal(h.parts.lagna, 100); // Sun & Mars are mutual friends
  assert.ok(h.score >= 0 && h.score <= 100);
  assert.equal(M.harmonyKundliScore({}, {}).score, 50);
  assert.equal(M.elementHarmony('fire', 'air'), 85);
  assert.equal(M.ganaHarmony('Deva', 'Rakshasa'), 25);
  assert.equal(M.lordFriendship('Sun', 'Saturn'), 10);
});

test('guna_milan module is the same function the astrology service exposes', () => {
  for (let i = 0; i < 360; i += 13.7) {
    for (let j = 0; j < 360; j += 29.3) {
      assert.deepEqual(GM.calculateAshtakoot({ moonLongitude: i }, { moonLongitude: j }), A.calculateAshtakoot({ moonLongitude: i }, { moonLongitude: j }));
    }
  }
  assert.throws(() => GM.calculateAshtakoot({}, {}), A.AstrologyInputError);
  // known reference pair keeps its score
  assert.equal(GM.calculateAshtakoot({ moonSign: 'Aries', nakshatra: 'Ashwini' }, { moonSign: 'Aries', nakshatra: 'Ashwini' }).total, 28);
});

test('scoreMatch + highlights: 2-4 short lines, no private details', () => {
  const answers = {};
  for (let i = 1; i <= 12; i++) answers[`q${String(i).padStart(2, '0')}`] = i % 4;
  const me = { kundli: { moonSign: 'Cancer', nakshatra: 'Pushya', ascendant: 'Leo', moonLongitude: 100 }, gender: 'female', answers, lat: 28.61, lng: 77.21, languages: ['Hindi'] };
  const other = { kundli: { moonSign: 'Pisces', nakshatra: 'Revati', ascendant: 'Sagittarius', moonLongitude: 355 }, gender: 'male', answers: { ...answers, q12: 1 }, lat: 28.64, lng: 77.22, languages: ['hindi', 'English'] };
  for (const intent of M.INTENTS) {
    const r = M.scoreMatch(me, other, { intent });
    assert.ok(Number.isInteger(r.score) && r.score >= 0 && r.score <= 100);
    for (const v of Object.values(r.breakdown)) assert.ok(v >= 0 && v <= 100);
    assert.ok(r.highlights.length >= 2 && r.highlights.length <= 4, JSON.stringify(r.highlights));
    for (const h of r.highlights) {
      assert.ok(h.length <= 70, h);
      for (const s of [...A.ZODIAC_SIGNS, ...A.NAKSHATRAS, 'Sagittarius', '1990']) assert.ok(!h.includes(s), `leaks ${s}: ${h}`);
    }
    assert.equal(r.sharedAnswers, 12);
    assert.equal(r.agreeAnswers, 11);
    assert.equal(r.distanceKm, 3);
  }
  const lp = M.scoreMatch(me, other, { intent: 'life_partner' });
  assert.ok(lp.highlights.some((h) => /Gunas|water signs|agree|km|speak/.test(h)));
  const bare = M.scoreMatch({ kundli: {} }, { kundli: {} }, { intent: 'friend' });
  assert.equal(bare.highlights.length, 2);
  assert.equal(bare.distanceKm, null);
  assert.equal(bare.breakdown.distance, 50);
});

test('life partner filter, shared intents and exclusions', () => {
  const f = { gender: 'female', interestedIn: 'male', intents: ['life_partner', 'friend'] };
  const m = { gender: 'male', interestedIn: 'female', intents: ['life_partner', 'friend'] };
  const m2 = { gender: 'male', interestedIn: 'male', intents: ['life_partner', 'friend'] };
  assert.ok(M.lifePartnerCompatible(f, m));
  assert.ok(!M.lifePartnerCompatible(f, m2));
  assert.ok(M.lifePartnerCompatible({ gender: 'male', interestedIn: 'any' }, { gender: null, interestedIn: 'any' }));
  assert.deepEqual(M.sharedIntents(f, m), ['life_partner', 'friend']);
  assert.deepEqual(M.sharedIntents(f, m2), ['friend']);
  const ex = M.excludedUserIds(1, [{ user_id: 1, blocked_user_id: 2 }, { user_id: 3, blocked_user_id: 1 }], [
    { from_user_id: 1, to_user_id: 4, status: 'pending' },
    { from_user_id: 5, to_user_id: 1, status: 'declined' },
    { from_user_id: 1, to_user_id: 6, status: 'cancelled' }
  ]);
  assert.deepEqual(ex.sort(), [2, 3, 4, 5]);
});

test('eligibility and profile validation', () => {
  const base = { user_id: 1, role: 'user', full_name: 'Asha Rao', date_of_birth: '1995-03-10', moon_sign: 'Leo', nakshatra: 'Magha' };
  assert.deepEqual(eligibility(base, '2026-11-05'), { eligible: true, age: 31 });
  assert.equal(eligibility({ ...base, moon_sign: null }, '2026-11-05').reason, 'NO_KUNDLI');
  assert.equal(eligibility({ ...base, date_of_birth: '2010-01-01' }, '2026-11-05').reason, 'UNDER_18');
  assert.equal(eligibility({ ...base, role: 'guest' }).reason, 'LOGIN_REQUIRED');
  assert.equal(eligibility(null).reason, 'LOGIN_REQUIRED');

  const p = validateProfile({ intents: ['friend', 'friend', 'travel'], bio: '  hi  ', displayName: '   ', languages: [' Hindi ', 'hindi', 'English'] }, { ...base, birth_gender: 'Female' });
  assert.equal(p.displayName, 'Asha');
  assert.equal(p.bio, 'hi');
  assert.deepEqual(p.intents, ['friend', 'travel']);
  assert.deepEqual(p.languages, ['Hindi', 'English']);
  assert.equal(p.gender, 'female');
  assert.equal(p.interestedIn, 'any');
  assert.equal(p.showNearby, true);
  assert.throws(() => validateProfile({ intents: [] }, base), /between 1 and 5/);
  assert.throws(() => validateProfile({ intents: ['dating'] }, base), /Unknown/);
  assert.throws(() => validateProfile({ intents: ['friend'], bio: 'x'.repeat(501) }, base), /500/);
  assert.throws(() => validateProfile({ intents: ['friend'], photoUrl: 'javascript:alert(1)' }, base), /https/);
  assert.throws(() => validateProfile({ intents: ['friend'], interestedIn: 'robots' }, base), /interestedIn/);
  assert.throws(() => validateProfile({ intents: ['friend'], showNearby: 'yes' }, base), /true or false/);
});

// ---------------------------------------------------------------------------
// Routes against the fake db
// ---------------------------------------------------------------------------
function seed(db) {
  const t = db.tables;
  const add = (id, full_name, gender, dob, kundli, role = 'user') => {
    t.users.push({ id, full_name, role, gender });
    if (dob) t.birth_details.push({ user_id: id, date_of_birth: dob, gender });
    if (kundli) t.kundlis.push({ user_id: id, ...kundli, kundli_data: { moonLongitude: kundli.moonLongitude } });
  };
  add(1, 'Asha Rao', 'Female', '1995-03-10', { moon_sign: 'Cancer', nakshatra: 'Pushya', ascendant: 'Leo', moonLongitude: 100 });
  add(2, 'Ravi Kumar', 'Male', '1992-07-21', { moon_sign: 'Pisces', nakshatra: 'Revati', ascendant: 'Aries', moonLongitude: 355 });
  add(3, 'Meera Teen', 'Female', '2010-01-01', { moon_sign: 'Leo', nakshatra: 'Magha', ascendant: 'Leo', moonLongitude: 125 });
  add(4, 'Kiran NoChart', 'Male', null, null);
  add(5, 'Dev Shah', 'Male', '1990-01-15', { moon_sign: 'Scorpio', nakshatra: 'Anuradha', ascendant: 'Cancer', moonLongitude: 215 });
  add(6, 'Guest', null, null, null, 'guest');
  // under-18 user's profile row exists (e.g. created before a chart change) but must never surface
  t.buddy_profiles.push({ user_id: 3, display_name: 'Meera', bio: '', intents: ['friend'], gender: 'female', interested_in: 'any', city: 'Delhi', lat: 28.61, lng: 77.21, photo_url: null, languages: [], show_nearby: true, is_active: true, created_at: new Date(), updated_at: new Date() });
  for (let i = 1; i <= 12; i++) {
    const q = `q${String(i).padStart(2, '0')}`;
    t.mindset_answers.push({ user_id: 1, question_id: q, option_index: i % 4 });
    t.mindset_answers.push({ user_id: 2, question_id: q, option_index: i <= 10 ? i % 4 : 0 });
  }
}

async function withServer(fn) {
  const app = express();
  app.use(express.json());
  app.use('/api/buddy', buddyRouter);
  const server = await new Promise((resolve) => { const s = app.listen(0, () => resolve(s)); });
  const base = `http://127.0.0.1:${server.address().port}/api/buddy`;
  const call = async (uid, method, p, body) => {
    const headers = { 'Content-Type': 'application/json' };
    if (uid) headers.Authorization = `Bearer ${signToken({ userId: uid, role: uid === 6 ? 'guest' : 'user' })}`;
    const r = await fetch(base + p, { method, headers, body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await r.json() };
  };
  try { await fn(call); } finally { server.close(); }
}

test('routes: profile, discover, connect -> accept -> chat, block and report', async () => {
  seed(fakeDb);
  const t = fakeDb.tables;
  await withServer(async (call) => {
    // auth & eligibility
    let r = await call(null, 'GET', '/profile');
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { profile: null, eligible: false, banned: false, reason: 'LOGIN_REQUIRED', age: null, quizAnswered: 0, quizTotal: 50 });
    r = await call(null, 'GET', '/discover');
    assert.equal(r.status, 401);
    assert.equal(r.body.code, 'LOGIN_REQUIRED');
    r = await call(6, 'PUT', '/profile', { intents: ['friend'] });
    assert.equal(r.body.code, 'LOGIN_REQUIRED');
    r = await call(3, 'PUT', '/profile', { intents: ['friend'] });
    assert.equal(r.status, 403);
    assert.equal(r.body.code, 'UNDER_18');
    r = await call(4, 'GET', '/profile');
    assert.equal(r.body.eligible, false);
    assert.equal(r.body.reason, 'NO_KUNDLI');
    r = await call(1, 'GET', '/profile');
    assert.deepEqual(r.body, { profile: null, eligible: true, banned: false, age: 31, quizAnswered: 12, quizTotal: 50 });
    r = await call(1, 'GET', '/discover');
    assert.equal(r.body.code, 'NO_PROFILE');

    // profiles + location
    r = await call(1, 'PUT', '/profile', { bio: 'Love temples and chai', intents: ['friend', 'life_partner', 'spiritual'], interestedIn: 'male', city: 'Delhi', languages: ['Hindi'] });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.profile.displayName, 'Asha');
    assert.equal(r.body.profile.gender, 'female');
    assert.equal(r.body.profile.hasLocation, false);
    assert.equal((await call(1, 'PUT', '/profile', { intents: [] })).status, 400);
    r = await call(2, 'PUT', '/profile', { displayName: 'Ravi', intents: ['friend', 'life_partner', 'travel'], gender: 'male', interestedIn: 'female', languages: ['Hindi', 'English'] });
    assert.equal(r.status, 200);
    r = await call(5, 'PUT', '/profile', { intents: ['friend'], gender: 'male' });
    assert.equal(r.status, 200);
    assert.equal((await call(1, 'PUT', '/location', { lat: 28.61349, lng: 77.20871 })).body.ok, true);
    assert.equal((await call(2, 'PUT', '/location', { lat: 28.6421, lng: 77.2219, city: 'New Delhi' })).body.ok, true);
    assert.equal((await call(5, 'PUT', '/location', { lat: 28.5902, lng: 77.1901 })).body.ok, true);
    assert.equal((await call(1, 'PUT', '/location', { lat: 200, lng: 0 })).status, 400);
    const p1 = t.buddy_profiles.find((p) => p.user_id === 1);
    assert.equal(p1.lat, 28.61);
    assert.equal(p1.lng, 77.21);
    assert.equal(t.buddy_profiles.find((p) => p.user_id === 2).city, 'New Delhi');

    // discover: not self, not under-18, no coordinates leak
    r = await call(1, 'GET', '/discover?intent=all&limit=20');
    assert.equal(r.status, 200);
    let ids = r.body.candidates.map((c) => c.userId);
    assert.deepEqual(ids.sort(), [2, 5]);
    for (const c of r.body.candidates) {
      for (const k of ['userId', 'displayName', 'age', 'city', 'distanceKm', 'photoUrl', 'intents', 'bio', 'languages', 'score', 'breakdown', 'highlights', 'sharedAnswers', 'agreeAnswers', 'connection']) {
        assert.ok(k in c, `missing ${k}`);
      }
      for (const k of ['lat', 'lng', 'date_of_birth', 'dateOfBirth', 'moonSign', 'nakshatra', 'answers']) assert.ok(!(k in c), `leaks ${k}`);
      assert.ok(Number.isInteger(c.distanceKm) && c.distanceKm >= 1);
      assert.ok(c.highlights.length >= 2 && c.highlights.length <= 4);
    }
    const ravi = r.body.candidates.find((c) => c.userId === 2);
    assert.equal(ravi.sharedAnswers, 12);
    assert.equal(ravi.agreeAnswers, 11);
    r = await call(1, 'GET', '/discover?intent=life_partner');
    assert.deepEqual(r.body.candidates.map((c) => c.userId), [2]);
    r = await call(1, 'GET', '/discover?intent=dating');
    assert.equal(r.status, 400);
    r = await call(1, 'GET', '/discover?maxKm=1');
    assert.deepEqual(r.body.candidates, []);
    r = await call(1, 'GET', '/nearby');
    assert.ok(r.body.candidates.length <= 5);
    for (const c of r.body.candidates) assert.ok(c.distanceKm <= 10 && c.score >= 60);

    // connect -> chat blocked until accepted -> accept -> chat
    assert.equal((await call(1, 'POST', '/connect', { userId: 5, intent: 'life_partner' })).body.code, 'INTENT_MISMATCH');
    r = await call(1, 'POST', '/connect', { userId: 2, intent: 'life_partner', message: 'Namaste!' });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const conn = r.body.connection;
    assert.equal(conn.status, 'pending');
    assert.equal(conn.direction, 'outgoing');
    r = await call(1, 'POST', '/connect', { userId: 2, intent: 'life_partner' });
    assert.equal(r.body.connection.id, conn.id); // idempotent
    r = await call(1, 'GET', '/discover');
    assert.deepEqual(r.body.candidates.map((c) => c.userId), [5]); // pending pair hidden
    r = await call(1, 'GET', '/user/2');
    assert.deepEqual(r.body.candidate.connection, { id: conn.id, status: 'pending', direction: 'outgoing' });

    r = await call(2, 'GET', '/connections');
    assert.equal(r.body.incoming.length, 1);
    assert.equal(r.body.incoming[0].other.displayName, 'Asha');
    assert.equal(r.body.incoming[0].message, 'Namaste!');
    assert.equal(r.body.incoming[0].unread, 0);
    assert.equal((await call(1, 'POST', `/chat/${conn.id}`, { body: 'hi' })).body.code, 'NOT_ACCEPTED');
    assert.equal((await call(1, 'POST', `/connections/${conn.id}/accept`)).status, 403); // sender cannot accept
    assert.equal((await call(5, 'POST', `/connections/${conn.id}/accept`)).status, 404); // stranger
    r = await call(2, 'POST', `/connections/${conn.id}/accept`);
    assert.equal(r.body.connection.status, 'accepted');
    assert.equal(r.body.connection.direction, 'incoming');

    assert.equal((await call(1, 'POST', `/chat/${conn.id}`, { body: '   ' })).status, 400);
    assert.equal((await call(1, 'POST', `/chat/${conn.id}`, { body: 'x'.repeat(2001) })).status, 400);
    r = await call(1, 'POST', `/chat/${conn.id}`, { body: '  Hello Ravi  ' });
    assert.equal(r.body.message.body, 'Hello Ravi');
    assert.equal(r.body.message.mine, true);
    const firstId = r.body.message.id;
    await call(1, 'POST', `/chat/${conn.id}`, { body: 'Shall we visit the temple?' });
    r = await call(2, 'GET', '/connections');
    assert.equal(r.body.buddies.length, 1);
    assert.equal(r.body.buddies[0].unread, 2);
    assert.deepEqual({ body: r.body.buddies[0].lastMessage.body, mine: r.body.buddies[0].lastMessage.mine }, { body: 'Shall we visit the temple?', mine: false });
    r = await call(2, 'GET', `/chat/${conn.id}`);
    assert.deepEqual(r.body.messages.map((m) => [m.body, m.mine]), [['Hello Ravi', false], ['Shall we visit the temple?', false]]);
    assert.equal(r.body.connection.status, 'accepted');
    r = await call(2, 'GET', `/chat/${conn.id}?after=${firstId}`);
    assert.equal(r.body.messages.length, 1);
    assert.equal((await call(2, 'GET', '/connections')).body.buddies[0].unread, 0);
    assert.equal((await call(5, 'GET', `/chat/${conn.id}`)).status, 404);

    // reverse pending request is auto-accepted
    r = await call(5, 'POST', '/connect', { userId: 2, intent: 'friend' });
    assert.equal(r.body.connection.status, 'pending');
    r = await call(2, 'POST', '/connect', { userId: 5, intent: 'friend' });
    assert.equal(r.body.connection.status, 'accepted');
    assert.equal(t.buddy_connections.filter((c) => [c.from_user_id, c.to_user_id].sort().join() === '2,5').length, 1);

    // decline + cancel
    r = await call(5, 'POST', '/connect', { userId: 1, intent: 'friend' });
    const c51 = r.body.connection.id;
    assert.equal((await call(5, 'POST', `/connections/${c51}/decline`)).status, 403);
    assert.equal((await call(1, 'POST', `/connections/${c51}/decline`)).body.connection.status, 'declined');
    assert.equal((await call(5, 'POST', '/connect', { userId: 1, intent: 'friend' })).body.code, 'DECLINED');
    assert.equal((await call(1, 'GET', '/discover')).body.candidates.length, 0); // declined pair hidden too

    // block: hides both ways everywhere and stops chat
    const c25 = t.buddy_connections.find((c) => c.from_user_id === 5 && c.to_user_id === 2).id;
    assert.equal((await call(2, 'POST', '/block', { userId: 2 })).status, 400);
    assert.equal((await call(2, 'POST', '/block', { userId: 999 })).status, 404);
    assert.equal((await call(2, 'POST', '/block', { userId: 5 })).body.ok, true);
    assert.equal((await call(5, 'GET', '/user/2')).status, 404);
    assert.equal((await call(2, 'GET', '/user/5')).status, 404);
    assert.equal((await call(5, 'POST', `/chat/${c25}`, { body: 'hello?' })).body.code, 'BLOCKED');
    assert.deepEqual((await call(5, 'GET', '/connections')).body.buddies, []);
    assert.equal((await call(5, 'POST', '/connect', { userId: 2, intent: 'friend' })).status, 404);

    // a fresh user sees neither side of a block in discover
    t.buddy_connections.length = 0;
    t.buddy_blocks.length = 0;
    await call(1, 'POST', '/block', { userId: 5 });
    assert.deepEqual((await call(1, 'GET', '/discover')).body.candidates.map((c) => c.userId), [2]);
    assert.deepEqual((await call(5, 'GET', '/discover')).body.candidates.map((c) => c.userId), [2]);

    // report validates the reason and also blocks
    assert.equal((await call(1, 'POST', '/report', { userId: 2, reason: 'meh' })).status, 400);
    r = await call(1, 'POST', '/report', { userId: 2, reason: 'scam', details: '  asked for money  ' });
    assert.equal(r.body.ok, true);
    assert.deepEqual(t.buddy_reports[0], { reporter_id: 1, reported_user_id: 2, reason: 'scam', details: 'asked for money' });
    assert.ok(t.buddy_blocks.some((b) => b.user_id === 1 && b.blocked_user_id === 2));
    assert.deepEqual((await call(1, 'GET', '/discover')).body.candidates, []);

    // pause hides the profile
    r = await call(2, 'DELETE', '/profile');
    assert.equal(r.body.profile.isActive, false);
    assert.deepEqual((await call(5, 'GET', '/discover')).body.candidates, []);
    assert.equal((await call(2, 'GET', '/discover')).body.code, 'PROFILE_PAUSED');
  });
});

test('routes: rate limits on messages, requests and reports; oversized ids are a 400, not a 500', async () => {
  const t = fakeDb.tables;
  for (const k of Object.keys(t)) t[k].length = 0;
  seed(fakeDb);
  const { MESSAGES_PER_MINUTE, REQUESTS_PER_DAY, REPORTS_PER_DAY, toInt } = buddyRouter._internal;
  assert.equal(toInt('2147483647'), 2147483647);
  assert.equal(toInt('2147483648'), null);
  assert.equal(toInt('1e3'), 1000);
  await withServer(async (call) => {
    assert.equal((await call(1, 'PUT', '/profile', { intents: ['friend'] })).status, 200);
    assert.equal((await call(2, 'PUT', '/profile', { intents: ['friend'] })).status, 200);
    assert.equal((await call(5, 'PUT', '/profile', { intents: ['friend'] })).status, 200);

    // ids beyond Postgres INTEGER
    for (const [m, p] of [['GET', '/user/99999999999'], ['POST', '/connections/99999999999/accept'], ['GET', '/chat/99999999999']]) {
      assert.equal((await call(1, m, p)).status, 400, p);
    }
    assert.equal((await call(1, 'POST', '/connect', { userId: 99999999999, intent: 'friend' })).status, 400);

    const conn = (await call(1, 'POST', '/connect', { userId: 2, intent: 'friend' })).body.connection;
    assert.equal((await call(2, 'POST', `/connections/${conn.id}/accept`)).body.connection.status, 'accepted');
    assert.equal((await call(1, 'GET', `/chat/${conn.id}?after=99999999999`)).status, 400);

    for (let i = 0; i < MESSAGES_PER_MINUTE; i++) {
      assert.equal((await call(1, 'POST', `/chat/${conn.id}`, { body: `m${i}` })).status, 200);
    }
    const flood = await call(1, 'POST', `/chat/${conn.id}`, { body: 'one more' });
    assert.equal(flood.status, 429);
    assert.equal(flood.body.code, 'RATE_LIMITED');
    assert.equal(t.buddy_messages.length, MESSAGES_PER_MINUTE);
    // the other person is not affected
    assert.equal((await call(2, 'POST', `/chat/${conn.id}`, { body: 'hi' })).status, 200);

    // new connection requests per day
    for (let i = 0; i < REQUESTS_PER_DAY; i++) {
      t.buddy_connections.push({ id: 5000 + i, from_user_id: 1, to_user_id: 9000 + i, intent: 'friend', status: 'cancelled', created_at: new Date(Date.parse('2026-11-05T06:00:00Z') + 1000), responded_at: null });
    }
    const spam = await call(1, 'POST', '/connect', { userId: 5, intent: 'friend' });
    assert.equal(spam.status, 429);
    assert.equal(spam.body.code, 'RATE_LIMITED');
    // accepting someone else's request is never limited
    const fromFive = (await call(5, 'POST', '/connect', { userId: 1, intent: 'friend' })).body.connection;
    assert.equal(fromFive.status, 'pending');
    assert.equal((await call(1, 'POST', '/connect', { userId: 5, intent: 'friend' })).body.connection.status, 'accepted');

    // reports per day: blocking still happens, the report row is not stored past the limit
    for (let i = 0; i < REPORTS_PER_DAY; i++) t.buddy_reports.push({ reporter_id: 1, reported_user_id: 9000 + i, reason: 'other', details: null });
    const r = await call(1, 'POST', '/report', { userId: 5, reason: 'harassment' });
    assert.equal(r.status, 200);
    assert.equal(t.buddy_reports.length, REPORTS_PER_DAY);
    assert.ok(t.buddy_blocks.some((b) => b.user_id === 1 && b.blocked_user_id === 5));
  });
});

test('Guna Milan: a missing (null / empty) Moon longitude falls back to sign + nakshatra, not 0 degrees', () => {
  const bySign = { moonSign: 'Scorpio', nakshatra: 'Anuradha' };
  const other = { moonSign: 'Cancer', nakshatra: 'Pushya' };
  const expected = GM.calculateAshtakoot(bySign, other);
  for (const moonLongitude of [null, '', '  ', undefined]) {
    assert.deepEqual(GM.calculateAshtakoot({ ...bySign, moonLongitude }, other), expected, String(moonLongitude));
  }
  // numeric strings (kundli_data->>'moonLongitude') still win over the sign names
  assert.deepEqual(GM.calculateAshtakoot({ ...bySign, moonLongitude: '215' }, other), GM.calculateAshtakoot({ moonLongitude: 215 }, other));
  // buddy rows carry SQL NULL when the chart has no stored longitude
  const a = { moonSign: 'Scorpio', nakshatra: 'Anuradha', ascendant: 'Leo', moonLongitude: null };
  const b = { moonSign: 'Cancer', nakshatra: 'Pushya', ascendant: 'Aries', moonLongitude: null };
  assert.equal(M.gunaKundliScore(a, b, 'male', 'female').gunaTotal, GM.calculateAshtakoot(bySign, other).total);
});

test('routes: an admin ban cannot be undone by the user and hides them everywhere', async () => {
  const t = fakeDb.tables;
  for (const k of Object.keys(t)) t[k].length = 0;
  seed(fakeDb);
  await withServer(async (call) => {
    for (const uid of [1, 2, 5]) assert.equal((await call(uid, 'PUT', '/profile', { intents: ['friend'] })).status, 200);
    await call(1, 'PUT', '/location', { lat: 28.61, lng: 77.21 });
    await call(2, 'PUT', '/location', { lat: 28.64, lng: 77.22 });
    const c12 = (await call(1, 'POST', '/connect', { userId: 2, intent: 'friend' })).body.connection;
    await call(2, 'POST', `/connections/${c12.id}/accept`);
    const c51 = (await call(5, 'POST', '/connect', { userId: 2, intent: 'friend' })).body.connection; // pending to 2

    // admin bans user 2 (what routes/admin.js does)
    Object.assign(t.buddy_profiles.find((p) => p.user_id === 2), { is_active: false, show_nearby: false, banned_at: new Date() });

    let r = await call(2, 'GET', '/profile');
    assert.equal(r.body.banned, true);
    assert.equal(r.body.eligible, false);
    assert.equal(r.body.reason, 'BANNED');
    assert.equal(r.body.profile.banned, true);
    assert.equal(r.body.profile.isActive, false);

    // re-activating through the profile body does not work
    r = await call(2, 'PUT', '/profile', { intents: ['friend'], isActive: true, showNearby: true });
    assert.equal(r.status, 200);
    assert.equal(r.body.profile.isActive, false);
    assert.equal(r.body.profile.showNearby, false);
    const bp2 = t.buddy_profiles.find((p) => p.user_id === 2);
    assert.equal(bp2.is_active, false);
    assert.equal(bp2.show_nearby, false);
    // even a stale is_active=true row stays hidden while banned_at is set
    bp2.is_active = true;

    assert.equal((await call(2, 'PUT', '/location', { lat: 19.07, lng: 72.87 })).body.code, 'BANNED');
    for (const p of ['/discover', '/nearby', '/user/1']) assert.equal((await call(2, 'GET', p)).body.code, 'BANNED', p);
    assert.equal((await call(2, 'POST', '/connect', { userId: 1, intent: 'friend' })).body.code, 'BANNED');

    assert.ok(!(await call(1, 'GET', '/discover')).body.candidates.some((c) => c.userId === 2));
    assert.ok(!(await call(5, 'GET', '/discover')).body.candidates.some((c) => c.userId === 2));
    assert.equal((await call(1, 'GET', '/user/2')).status, 404);
    assert.equal((await call(1, 'POST', '/connect', { userId: 2, intent: 'friend' })).status, 404);
    assert.deepEqual((await call(1, 'GET', '/connections')).body.buddies, []);
    assert.equal((await call(1, 'POST', `/chat/${c12.id}`, { body: 'hi' })).status, 403);
    assert.equal((await call(2, 'POST', `/chat/${c12.id}`, { body: 'hi' })).status, 403);
    assert.equal((await call(2, 'POST', `/connections/${c51.id}/accept`)).status, 404);
  });
});
