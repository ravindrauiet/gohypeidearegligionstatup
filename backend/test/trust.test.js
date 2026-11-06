// v3 trust: verified badge (selfie queue), phone check, biodata, family links. No database: the
// routes run against an in-memory fake `db` that dispatches on the /*q:name*/ tag of each query.
process.env.NEON_DATABASE_URL = '';
process.env.DATABASE_URL = '';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'trust-test-secret-0123456789';
delete process.env.FIREBASE_SERVICE_ACCOUNT;

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const express = require('express');

// ---------------------------------------------------------------------------
// Fake db
// ---------------------------------------------------------------------------
function createFakeDb() {
  const t = {};
  const reset = () => {
    Object.assign(t, {
      users: [], birth_details: [], kundlis: [], buddy_profiles: [], buddy_connections: [], buddy_blocks: [],
      mindset_answers: [], buddy_verifications: [], phone_verifications: [], family_links: [], family_notes: [], coin_ledger: [],
    });
  };
  reset();
  let seq = 100;
  const find = (tbl, uid) => t[tbl].find((r) => r.user_id === uid);
  const DAY = 86400000;

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
      moon_longitude: k ? String(k.moonLongitude) : null,
      bp_user_id: bp ? bp.user_id : null,
      ...(bp ? {
        display_name: bp.display_name, bio: bp.bio, intents: bp.intents, gender: bp.gender, interested_in: bp.interested_in,
        city: bp.city, lat: bp.lat, lng: bp.lng, photo_url: null, languages: bp.languages,
        show_nearby: bp.show_nearby, is_active: bp.is_active, banned_at: bp.banned_at || null, created_at: bp.created_at, updated_at: bp.updated_at,
        verified_at: bp.verified_at || null, phone_verified_at: bp.phone_verified_at || null, biodata: bp.biodata || {},
      } : {}),
    };
  }
  const blocked = (a, b) => t.buddy_blocks.some((x) => (x.user_id === a && x.blocked_user_id === b) || (x.user_id === b && x.blocked_user_id === a));
  const live = (l) => !l.revoked_at && l.expires_at.getTime() > Date.now();
  const linkRow = (l) => {
    const mbp = l.match_user_id ? find('buddy_profiles', l.match_user_id) : null;
    const mu = l.match_user_id ? t.users.find((u) => u.id === l.match_user_id) : null;
    return { ...l, match_display_name: mbp ? mbp.display_name : null, match_full_name: mu ? mu.full_name : null, notes_count: t.family_notes.filter((n) => n.link_id === l.id).length };
  };
  const recent = (d) => Date.now() - new Date(d).getTime() < DAY;

  const handlers = {
    me: ([uid]) => [person(uid, true)].filter(Boolean),
    person: ([uid]) => [person(uid, false)].filter(Boolean),
    answers: ([ids]) => t.mindset_answers.filter((a) => ids.includes(a.user_id)),
    blockedPair: ([a, b]) => (blocked(a, b) ? [{ '?column?': 1 }] : []),
    connectionPair: ([a, b]) => t.buddy_connections.filter((c) => (c.from_user_id === a && c.to_user_id === b) || (c.from_user_id === b && c.to_user_id === a)),
    blocks: ([me]) => t.buddy_blocks.filter((b) => b.user_id === me || b.blocked_user_id === me),
    myConnections: ([me]) => t.buddy_connections.filter((c) => c.from_user_id === me || c.to_user_id === me),
    candidates: ([me, excluded, cutoff, intent, intentsAny, minLat, , , , nearbyOnly, limit, verifiedOnly]) => t.buddy_profiles
      .filter((bp) => bp.is_active && !bp.banned_at && bp.user_id !== me && !excluded.includes(bp.user_id))
      .filter((bp) => !verifiedOnly || bp.verified_at)
      .map((bp) => person(bp.user_id, false)).filter(Boolean)
      .filter((p) => p.date_of_birth <= cutoff)
      .filter((p) => intent === null || p.intents.includes(intent))
      .filter((p) => intentsAny === null || p.intents.some((i) => intentsAny.includes(i)))
      .filter(() => minLat === null)
      .filter((p) => !nearbyOnly || p.show_nearby)
      .slice(0, limit),
    connectionList: ([me]) => t.buddy_connections
      .filter((c) => (c.from_user_id === me || c.to_user_id === me) && ['pending', 'accepted'].includes(c.status))
      .map((c) => {
        const oid = c.from_user_id === me ? c.to_user_id : c.from_user_id;
        const obp = find('buddy_profiles', oid) || {};
        if (obp.banned_at || blocked(me, oid)) return null;
        return {
          ...c, other_id: oid, other_full_name: t.users.find((u) => u.id === oid).full_name, other_display_name: obp.display_name,
          other_city: obp.city, other_photo_url: null, other_dob: (find('birth_details', oid) || {}).date_of_birth,
          other_verified_at: obp.verified_at || null, other_phone_verified_at: obp.phone_verified_at || null,
          last_body: null, unread: 0,
        };
      }).filter(Boolean),

    // verification
    verificationLatest: ([uid]) => t.buddy_verifications.filter((v) => v.user_id === uid).sort((a, b) => b.id - a.id).slice(0, 1).map((v) => ({ ...v })),
    verificationsToday: ([uid]) => [{ n: t.buddy_verifications.filter((v) => v.user_id === uid && recent(v.created_at)).length }],
    verificationPending: ([uid]) => t.buddy_verifications.filter((v) => v.user_id === uid && v.status === 'pending').map((v) => ({ id: v.id })),
    verificationInsert: ([uid, gesture, selfie]) => {
      if (t.buddy_verifications.some((v) => v.user_id === uid && v.status === 'pending')) {
        const e = new Error('duplicate key'); e.code = '23505'; throw e;
      }
      t.buddy_verifications.push({ id: ++seq, user_id: uid, gesture, selfie, status: 'pending', reason: null, created_at: new Date(), decided_at: null });
      return [];
    },
    adminVerifications: ([status]) => t.buddy_verifications
      .filter((v) => status === 'all' || v.status === status)
      .sort((a, b) => (status === 'pending' ? a.id - b.id : b.id - a.id))
      .map((v) => {
        const u = t.users.find((x) => x.id === v.user_id);
        const bp = find('buddy_profiles', v.user_id) || {};
        return { ...v, selfie: v.status === 'pending' ? v.selfie : null, full_name: u.full_name, email: u.email, display_name: bp.display_name, city: bp.city, banned_at: bp.banned_at || null, verified_at: bp.verified_at || null, date_of_birth: (find('birth_details', v.user_id) || {}).date_of_birth };
      }),
    adminVerificationLock: ([id]) => t.buddy_verifications.filter((v) => v.id === id).map((v) => ({ id: v.id, user_id: v.user_id, status: v.status, banned_at: (find('buddy_profiles', v.user_id) || {}).banned_at || null })),
    adminVerificationDecide: ([id, status, reason]) => {
      Object.assign(t.buddy_verifications.find((v) => v.id === id), { status, reason, decided_at: new Date(), selfie: null });
      return [];
    },
    adminVerifiedProfile: ([uid]) => {
      const bp = find('buddy_profiles', uid);
      if (bp && !bp.banned_at && !bp.verified_at) bp.verified_at = new Date();
      return [];
    },

    // phone
    phoneOwner: ([hash]) => t.phone_verifications.filter((p) => p.phone_hash === hash).map((p) => ({ user_id: p.user_id })),
    phoneClearMine: ([uid]) => { t.phone_verifications = t.phone_verifications.filter((p) => p.user_id !== uid); return []; },
    phoneInsert: ([hash, uid]) => {
      if (t.phone_verifications.some((p) => p.phone_hash === hash)) return [];
      t.phone_verifications.push({ phone_hash: hash, user_id: uid, verified_at: new Date() });
      return [{ user_id: uid }];
    },
    phoneVerified: ([uid]) => { const bp = find('buddy_profiles', uid); if (bp && !bp.banned_at) bp.phone_verified_at = new Date(); return []; },

    // biodata
    biodataSave: ([uid, json]) => {
      const bp = find('buddy_profiles', uid);
      if (!bp || bp.banned_at) return [];
      bp.biodata = JSON.parse(json);
      return [{ biodata: bp.biodata }];
    },

    // family
    familyActiveCount: ([uid]) => [{ n: t.family_links.filter((l) => l.user_id === uid && live(l)).length }],
    familyInsertLink: ([token, uid, kind, matchId, days]) => {
      const l = { id: ++seq, token, user_id: uid, kind, match_user_id: matchId, created_at: new Date(), expires_at: new Date(Date.now() + days * DAY), revoked_at: null };
      t.family_links.push(l);
      return [{ id: l.id }];
    },
    familyLinkById: ([id]) => t.family_links.filter((l) => l.id === id).map(linkRow),
    familyListLinks: ([uid]) => t.family_links.filter((l) => l.user_id === uid).sort((a, b) => b.id - a.id).map(linkRow),
    familyRevoke: ([id, uid]) => {
      const l = t.family_links.find((x) => x.id === id && x.user_id === uid);
      if (!l) return [];
      l.revoked_at = l.revoked_at || new Date();
      return [{ id }];
    },
    familyLinkByToken: ([token]) => t.family_links.filter((l) => l.token === token).map((l) => ({ ...l })),
    familyPlanets: ([uid]) => t.kundlis.filter((k) => k.user_id === uid).map((k) => ({ planetary_positions: k.planetary_positions || null })),
    familyNoteCounts: ([linkId, ip]) => {
      const rows = t.family_notes.filter((n) => n.link_id === linkId && recent(n.created_at));
      return [{ by_ip: rows.filter((n) => n.ip_hash === ip).length, by_link: rows.length }];
    },
    familyInsertNote: ([linkId, uid, name, relation, message, ip]) => {
      const n = { id: ++seq, link_id: linkId, user_id: uid, name, relation, message, ip_hash: ip, created_at: new Date() };
      t.family_notes.push(n);
      return [{ id: n.id, created_at: n.created_at }];
    },
    familyListNotes: ([uid]) => t.family_notes.filter((n) => n.user_id === uid).sort((a, b) => b.id - a.id).map((n) => {
      const l = t.family_links.find((x) => x.id === n.link_id);
      return { ...n, kind: l.kind, match_user_id: l.match_user_id, match_display_name: l.match_user_id ? (find('buddy_profiles', l.match_user_id) || {}).display_name : null };
    }),
    familyDeleteNote: ([id, uid]) => {
      const i = t.family_notes.findIndex((n) => n.id === id && n.user_id === uid);
      if (i < 0) return [];
      t.family_notes.splice(i, 1);
      return [{ id }];
    },
  };

  const db = {
    tables: t,
    reset,
    async query(sql, params = []) {
      const s = String(sql).replace(/\s+/g, ' ').trim();
      if (/^SELECT role FROM users WHERE id = \$1$/.test(s)) return { rows: t.users.filter((u) => u.id === params[0]).map((u) => ({ role: u.role })) };
      if (s.startsWith('INSERT INTO coin_ledger')) {
        const [userId, amount, reason, ref, note] = params;
        if (t.coin_ledger.some((r) => r.user_id === userId && r.reason === reason && r.ref === ref)) return { rows: [] };
        t.coin_ledger.push({ id: t.coin_ledger.length + 1, user_id: userId, amount, reason, ref, note });
        return { rows: [{ id: t.coin_ledger.length }] };
      }
      const m = /^\/\*q:(\w+)\*\//.exec(s);
      if (!m) throw new Error(`untagged query: ${s.slice(0, 80)}`);
      const h = handlers[m[1]];
      if (!h) throw new Error(`fake db: no handler for ${m[1]}`);
      return { rows: h(params) };
    },
    async withTransaction(fn) { return fn(db); },
    ensureInitialized: async () => {},
  };
  return db;
}

const fakeDb = createFakeDb();
const dbPath = require.resolve(path.join(__dirname, '..', 'db.js'));
require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: fakeDb };

const { signToken } = require('../routes/auth');
const buddyRouter = require('../routes/buddy');
const adminTrust = require('../routes/admin_trust');
const familyRouter = require('../routes/family');
const TS = require('../services/trust_service');
const FA = require('../services/firebase_auth_service');
const C = require('../services/coins_service');
const push = require('../services/push_service');

const pushed = [];
push.sendToUser = async (userId, msg, opts) => { pushed.push({ userId, ...msg, opts }); return {}; };

// ---------------------------------------------------------------------------
// Seed + server
// ---------------------------------------------------------------------------
function seed() {
  fakeDb.reset();
  const t = fakeDb.tables;
  const add = (id, full_name, gender, dob, kundli, profile) => {
    t.users.push({ id, full_name, role: 'user', gender, email: `${id}@x.com` });
    t.birth_details.push({ user_id: id, date_of_birth: dob, gender, time_of_birth: '05:45:00', place_of_birth: 'Varanasi' });
    t.kundlis.push({ user_id: id, ...kundli });
    if (profile) {
      t.buddy_profiles.push({
        user_id: id, bio: '', intents: ['friend', 'life_partner'], gender: gender.toLowerCase(), interested_in: 'any', city: 'Delhi',
        lat: 28.61, lng: 77.21, languages: ['Hindi'], show_nearby: true, is_active: true, banned_at: null,
        created_at: new Date(), updated_at: new Date(), biodata: {}, ...profile,
      });
    }
  };
  add(1, 'Asha Rao', 'Female', '1995-03-10', { moon_sign: 'Cancer', nakshatra: 'Pushya', ascendant: 'Leo', moonLongitude: 100, planetary_positions: [{ name: 'Mars', house: 7 }] }, { display_name: 'Asha', interested_in: 'male' });
  add(2, 'Ravi Kumar', 'Male', '1992-07-21', { moon_sign: 'Pisces', nakshatra: 'Revati', ascendant: 'Aries', moonLongitude: 355, planetary_positions: [{ name: 'Mars', house: 3 }] }, { display_name: 'Ravi', interested_in: 'female' });
  add(5, 'Dev Shah', 'Male', '1990-01-15', { moon_sign: 'Scorpio', nakshatra: 'Anuradha', ascendant: 'Cancer', moonLongitude: 215 }, { display_name: 'Dev', interested_in: 'female' });
  add(7, 'Banned Guy', 'Male', '1991-01-15', { moon_sign: 'Leo', nakshatra: 'Magha', ascendant: 'Leo', moonLongitude: 125 }, { display_name: 'Bad', banned_at: new Date(), is_active: false });
  add(8, 'No Profile', 'Male', '1991-01-15', { moon_sign: 'Leo', nakshatra: 'Magha', ascendant: 'Leo', moonLongitude: 125 }, null);
  t.buddy_connections.push({ id: 1, from_user_id: 1, to_user_id: 2, intent: 'life_partner', status: 'accepted', score: 70, created_at: new Date(), responded_at: new Date() });
  pushed.length = 0;
  return t;
}

let server;
let base;
test.before(async () => {
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use('/api/buddy', buddyRouter);
  app.use('/api/admin', adminTrust);
  app.use('/api/family', familyRouter);
  app.get('/f/:token', familyRouter.page);
  server = await new Promise((resolve) => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
  base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => new Promise((r) => server.close(r)));

async function call(uid, method, p, body, headers = {}) {
  const h = { 'Content-Type': 'application/json', ...headers };
  if (uid) h.Authorization = `Bearer ${signToken({ userId: uid, role: 'user' })}`;
  const r = await fetch(base + p, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
  let json = null;
  try { json = await r.json(); } catch (_) { /* html */ }
  return { status: r.status, body: json, headers: r.headers };
}
const jpeg = (bytes = 4000) => {
  const b = Buffer.alloc(bytes, 7);
  b[0] = 0xff; b[1] = 0xd8; b[2] = 0xff;
  return b.toString('base64');
};
const G = TS.GESTURES[0];

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------
test('selfie validation: JPEG/PNG only, size capped, data URIs accepted', () => {
  assert.equal(TS.cleanSelfie(jpeg()).mime, 'image/jpeg');
  assert.equal(TS.cleanSelfie(`data:image/jpeg;base64,${jpeg()}`).bytes, 4000);
  const png = Buffer.alloc(3000, 1);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png);
  assert.equal(TS.cleanSelfie(png.toString('base64')).mime, 'image/png');
  assert.throws(() => TS.cleanSelfie(jpeg(TS.MAX_SELFIE_BYTES + 1)), /too large/);
  assert.doesNotThrow(() => TS.cleanSelfie(jpeg(TS.MAX_SELFIE_BYTES)));
  assert.throws(() => TS.cleanSelfie(Buffer.alloc(5000, 65).toString('base64')), /JPEG or PNG/);
  assert.throws(() => TS.cleanSelfie('not base64!!'), /could not be read/);
  assert.throws(() => TS.cleanSelfie(''), /selfie/);
  assert.throws(() => TS.cleanSelfie(null), /selfie/);
});

test('biodata validation: types, ranges, lengths; empty fields dropped; unknown keys ignored', () => {
  const b = TS.validateBiodata({
    heightCm: 170, education: '  B.Tech   (IIT) ', profession: 'Engineer', incomeRange: '10_20l', diet: 'veg',
    community: 'Brahmin', gotra: '', aboutFamily: 'Close  knit\n\n\n\nfamily', foo: 'bar', partnerExpectations: null,
  });
  assert.deepEqual(b, { heightCm: 170, education: 'B.Tech (IIT)', profession: 'Engineer', incomeRange: '10_20l', diet: 'veg', community: 'Brahmin', aboutFamily: 'Close knit\n\nfamily' });
  assert.throws(() => TS.validateBiodata({ heightCm: 90 }), /Height/);
  assert.throws(() => TS.validateBiodata({ heightCm: 170.5 }), /Height/);
  assert.throws(() => TS.validateBiodata({ diet: 'paleo' }), /diet/);
  assert.throws(() => TS.validateBiodata({ incomeRange: 'lots' }), /income/);
  assert.throws(() => TS.validateBiodata({ gotra: 'x'.repeat(41) }), /40/);
  assert.throws(() => TS.validateBiodata({ aboutFamily: 'x'.repeat(301) }), /300/);
  assert.throws(() => TS.validateBiodata({ education: 5 }), /text/);
  assert.throws(() => TS.validateBiodata([]), /object/);
  assert.deepEqual(TS.biodataView('{"education":"MBA","heightCm":999,"junk":1}'), { education: 'MBA' });
  assert.deepEqual(TS.biodataView(null), {});
});

test('phone hash: stable, never the number, peppered when configured', () => {
  const h = TS.phoneHash('+919876543210');
  assert.match(h, /^[0-9a-f]{64}$/);
  assert.equal(h, TS.phoneHash('+91 98765-43210'));
  assert.ok(!h.includes('9876543210'));
  process.env.PHONE_HASH_PEPPER = 'pepper-1';
  assert.notEqual(TS.phoneHash('+919876543210'), h);
  delete process.env.PHONE_HASH_PEPPER;
  assert.equal(TS.manglikFrom([{ name: 'Mars', house: 8 }]), true);
  assert.equal(TS.manglikFrom([{ name: 'Mars (R)', house: 3 }]), false);
  assert.equal(TS.manglikFrom(null), null);
});

test('coins constant for the verified badge', () => {
  assert.equal(C.VERIFIED_COINS, 50);
  assert.equal(C.VERIFIED_REASON, 'verified');
  assert.equal(C.VERIFIED_REF, 'selfie');
  assert.match(fs.readFileSync(path.join(__dirname, '..', 'routes', 'admin.js'), 'utf8'), /require\('\.\/admin_trust'\)/, 'admin.js mounts the queue behind its key check');
});

// ---------------------------------------------------------------------------
// Verified badge
// ---------------------------------------------------------------------------
test('verification: submit, one pending at a time, admin approve deletes the selfie, pays once, badge everywhere', async () => {
  const t = seed();
  let r = await call(1, 'GET', '/api/buddy/verification');
  assert.equal(r.status, 200);
  assert.equal(r.body.status, 'none');
  assert.equal(r.body.verified, false);
  assert.equal(r.body.phoneAvailable, false);
  assert.deepEqual(r.body.gestures, TS.GESTURES);
  assert.equal(r.body.dailyLimit, 3);

  assert.equal((await call(null, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() })).status, 401);
  assert.equal((await call(1, 'POST', '/api/buddy/verification', { gesture: 'Dance', imageBase64: jpeg() })).body.code, 'BAD_GESTURE');
  assert.equal((await call(1, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg(TS.MAX_SELFIE_BYTES + 10) })).body.code, 'BAD_IMAGE');
  assert.equal((await call(8, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() })).body.code, 'NO_PROFILE');
  r = await call(7, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'BANNED', 'banned users cannot verify');
  assert.equal(t.buddy_verifications.length, 0);

  r = await call(1, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: `data:image/jpeg;base64,${jpeg()}` });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.status, 'pending');
  assert.equal(r.body.latest.gesture, G);
  assert.ok(!('selfie' in r.body.latest), 'the selfie is never echoed back');
  assert.equal(t.buddy_verifications.length, 1);
  assert.ok(t.buddy_verifications[0].selfie.startsWith('/9j/'));
  r = await call(1, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'PENDING');

  // admin queue shows photo + gesture + name/age/city
  r = await call(null, 'GET', '/api/admin/verifications');
  assert.equal(r.status, 200);
  assert.equal(r.body.verifications.length, 1);
  const v = r.body.verifications[0];
  assert.equal(v.gesture, G);
  assert.match(v.selfie, /^data:image\/jpeg;base64,\/9j\//);
  assert.deepEqual([v.user.name, v.user.age, v.user.city], ['Asha', 31, 'Delhi']);
  assert.equal((await call(null, 'GET', '/api/admin/verifications?status=nope')).status, 400);
  assert.equal((await call(null, 'POST', `/api/admin/verifications/${v.id}/decide`, { action: 'maybe' })).status, 400);
  assert.equal((await call(null, 'POST', '/api/admin/verifications/999/decide', { action: 'approve' })).status, 404);

  r = await call(null, 'POST', `/api/admin/verifications/${v.id}/decide`, { action: 'approve' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.coins, 50);
  const row = t.buddy_verifications[0];
  assert.equal(row.status, 'approved');
  assert.equal(row.selfie, null, 'selfie bytes deleted on decision');
  assert.ok(row.decided_at);
  assert.ok(t.buddy_profiles.find((p) => p.user_id === 1).verified_at);
  assert.deepEqual(t.coin_ledger.map((c) => [c.user_id, c.amount, c.reason, c.ref]), [[1, 50, 'verified', 'selfie']]);
  assert.deepEqual(pushed.map((p) => [p.userId, p.type, p.data.status, p.data.verificationId]), [[1, 'verification_update', 'approved', v.id]]);
  // deciding twice is refused; the approved list has no photo
  assert.equal((await call(null, 'POST', `/api/admin/verifications/${v.id}/decide`, { action: 'approve' })).body.code, 'NOT_PENDING');
  assert.equal((await call(null, 'GET', '/api/admin/verifications?status=approved')).body.verifications[0].selfie, null);

  r = await call(1, 'GET', '/api/buddy/verification');
  assert.equal(r.body.status, 'verified');
  assert.equal(r.body.verified, true);
  assert.equal((await call(1, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() })).body.code, 'ALREADY_VERIFIED');
  assert.equal((await call(1, 'GET', '/api/buddy/profile')).body.profile.verified, true);

  // coins once even if a second approval somehow happens (new request after a manual reset)
  t.buddy_profiles.find((p) => p.user_id === 1).verified_at = null;
  await call(1, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  const v2 = t.buddy_verifications[1].id;
  r = await call(null, 'POST', `/api/admin/verifications/${v2}/decide`, { action: 'approve' });
  assert.equal(r.body.coins, 0);
  assert.equal(t.coin_ledger.length, 1, 'the 50 coins are paid only once');

  // the badge shows up in every person payload
  r = await call(2, 'GET', '/api/buddy/discover');
  assert.equal(r.status, 200, JSON.stringify(r.body));
  for (const c of r.body.candidates) assert.equal(typeof c.verified, 'boolean');
  r = await call(2, 'GET', '/api/buddy/user/1');
  assert.equal(r.body.candidate.verified, true);
  r = await call(2, 'GET', '/api/buddy/connections');
  assert.equal(r.body.buddies[0].other.verified, true);
  assert.equal(r.body.buddies[0].other.phoneVerified, false);
});

test('verification: reject keeps the reason (shown for retry), deletes the selfie, 3 submissions a day', async () => {
  const t = seed();
  await call(2, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  const id = t.buddy_verifications[0].id;
  let r = await call(null, 'POST', `/api/admin/verifications/${id}/decide`, { action: 'reject', reason: 'x'.repeat(301) });
  assert.equal(r.status, 400);
  r = await call(null, 'POST', `/api/admin/verifications/${id}/decide`, { action: 'reject', reason: '  Face not visible  ' });
  assert.equal(r.status, 200);
  assert.equal(r.body.coins, 0);
  assert.equal(t.buddy_verifications[0].selfie, null);
  assert.equal(t.buddy_verifications[0].reason, 'Face not visible');
  assert.equal(t.coin_ledger.length, 0);
  assert.deepEqual(pushed.at(-1).data, { status: 'rejected', verificationId: id, reason: 'Face not visible' });
  r = await call(2, 'GET', '/api/buddy/verification');
  assert.equal(r.body.status, 'rejected');
  assert.equal(r.body.latest.reason, 'Face not visible');
  assert.equal(r.body.submissionsToday, 1);

  // retry allowed; third rejected; fourth is rate limited
  await call(2, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  await call(null, 'POST', `/api/admin/verifications/${t.buddy_verifications[1].id}/decide`, { action: 'reject' });
  assert.match(t.buddy_verifications[1].reason, /did not clearly show/);
  await call(2, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  await call(null, 'POST', `/api/admin/verifications/${t.buddy_verifications[2].id}/decide`, { action: 'reject' });
  r = await call(2, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  assert.equal(r.status, 429);
  assert.equal(r.body.code, 'RATE_LIMITED');
  // yesterday's submissions no longer count
  for (const v of t.buddy_verifications) v.created_at = new Date(Date.now() - 2 * 86400000);
  assert.equal((await call(2, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() })).status, 200);
});

test('verification: a user banned while pending cannot be approved; a banned verified user loses the badge', async () => {
  const t = seed();
  await call(5, 'POST', '/api/buddy/verification', { gesture: G, imageBase64: jpeg() });
  const bp5 = t.buddy_profiles.find((p) => p.user_id === 5);
  bp5.banned_at = new Date();
  const id = t.buddy_verifications[0].id;
  let r = await call(null, 'POST', `/api/admin/verifications/${id}/decide`, { action: 'approve' });
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'USER_BANNED');
  assert.equal(bp5.verified_at, undefined);
  assert.equal(t.coin_ledger.length, 0);
  r = await call(null, 'POST', `/api/admin/verifications/${id}/decide`, { action: 'reject' });
  assert.equal(r.status, 200);
  assert.equal(t.buddy_verifications[0].selfie, null);

  // isVerified() ignores verified_at once banned
  const { isVerified } = buddyRouter._internal;
  assert.equal(isVerified({ verified_at: new Date(), banned_at: new Date() }), false);
  assert.equal(isVerified({ verified_at: new Date(), banned_at: null }), true);
});

test('discover: verifiedOnly filter and a small ranking boost for verified people', async () => {
  const t = seed();
  t.buddy_profiles.find((p) => p.user_id === 1).verified_at = new Date();
  let r = await call(5, 'GET', '/api/buddy/discover?intent=friend');
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const all = r.body.candidates;
  assert.deepEqual(all.map((c) => c.userId).sort(), [1, 2]);
  assert.equal(all.find((c) => c.userId === 1).verified, true);
  assert.equal(all.find((c) => c.userId === 2).verified, false);
  const { VERIFIED_RANK_BOOST, PHONE_RANK_BOOST } = buddyRouter._internal;
  const rank = (c) => c.score + (c.verified ? VERIFIED_RANK_BOOST : 0) + (c.phoneVerified ? PHONE_RANK_BOOST : 0);
  for (let i = 1; i < all.length; i++) assert.ok(rank(all[i - 1]) >= rank(all[i]), 'sorted by score + trust boost');

  r = await call(5, 'GET', '/api/buddy/discover?intent=friend&verifiedOnly=1');
  assert.deepEqual(r.body.candidates.map((c) => c.userId), [1]);
  r = await call(5, 'GET', '/api/buddy/discover?intent=friend&verifiedOnly=0');
  assert.equal(r.body.candidates.length, 2);
});

// ---------------------------------------------------------------------------
// Phone check
// ---------------------------------------------------------------------------
test('phone verification: mocked firebase-admin, number never stored, one number per account', async () => {
  const t = seed();
  const tokens = {
    'token-asha-0000000000000': { uid: 'f1', phone_number: '+919876543210' },
    'token-ravi-same-number-000': { uid: 'f2', phone_number: '+919876543210' },
    'token-ravi-own-number-0000': { uid: 'f3', phone_number: '+919812345678' },
    'token-email-only-000000000': { uid: 'f4', email: 'a@b.c' },
  };
  // Server without Firebase: 503, option reported unavailable.
  FA.setAuthClient(null);
  assert.equal((await call(1, 'POST', '/api/buddy/verification/phone', { idToken: 'token-asha-0000000000000' })).body.code, 'PHONE_UNAVAILABLE');

  FA.setAuthClient({ verifyIdToken: async (tok) => { if (!tokens[tok]) throw new Error('bad'); return tokens[tok]; } });
  try {
    assert.equal((await call(1, 'GET', '/api/buddy/verification')).body.phoneAvailable, true);
    assert.equal((await call(1, 'POST', '/api/buddy/verification/phone', {})).status, 400);
    assert.equal((await call(1, 'POST', '/api/buddy/verification/phone', { idToken: 'token-forged-000000000000' })).body.code, 'BAD_TOKEN');
    assert.equal((await call(1, 'POST', '/api/buddy/verification/phone', { idToken: 'token-email-only-000000000' })).body.code, 'NO_PHONE');
    assert.equal((await call(7, 'POST', '/api/buddy/verification/phone', { idToken: 'token-asha-0000000000000' })).body.code, 'BANNED');

    let r = await call(1, 'POST', '/api/buddy/verification/phone', { idToken: 'token-asha-0000000000000' });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.phoneVerified, true);
    assert.equal(t.phone_verifications.length, 1);
    assert.equal(t.phone_verifications[0].phone_hash, TS.phoneHash('+919876543210'));
    const dump = JSON.stringify(t);
    assert.ok(!dump.includes('9876543210'), 'the phone number itself is never stored');
    assert.ok(!JSON.stringify(r.body).includes('9876543210'));
    // re-verifying the same number is fine
    assert.equal((await call(1, 'POST', '/api/buddy/verification/phone', { idToken: 'token-asha-0000000000000' })).status, 200);

    // the same number cannot verify a second account
    r = await call(2, 'POST', '/api/buddy/verification/phone', { idToken: 'token-ravi-same-number-000' });
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'PHONE_IN_USE');
    assert.equal(t.buddy_profiles.find((p) => p.user_id === 2).phone_verified_at, undefined);
    r = await call(2, 'POST', '/api/buddy/verification/phone', { idToken: 'token-ravi-own-number-0000' });
    assert.equal(r.status, 200);
    assert.equal(t.phone_verifications.length, 2);

    r = await call(2, 'GET', '/api/buddy/user/1');
    assert.equal(r.body.candidate.phoneVerified, true);
    assert.ok(!JSON.stringify(r.body).includes('98765'));
  } finally {
    FA.setAuthClient(undefined);
  }
});

// ---------------------------------------------------------------------------
// Biodata
// ---------------------------------------------------------------------------
test('biodata: save + validation; discover shows only education/profession; full biodata only for accepted buddies', async () => {
  const t = seed();
  const full = { heightCm: 175, education: 'MBA', profession: 'Banker', incomeRange: '20_35l', diet: 'veg', gotra: 'Kashyap', fatherOccupation: 'Teacher', aboutFamily: 'Joint family in Patna', partnerExpectations: 'Kind and honest' };
  assert.equal((await call(2, 'PUT', '/api/buddy/biodata', { biodata: { heightCm: 400 } })).body.code, 'INVALID_BIODATA');
  assert.equal((await call(8, 'PUT', '/api/buddy/biodata', { biodata: full })).body.code, 'NO_PROFILE');
  assert.equal((await call(7, 'PUT', '/api/buddy/biodata', { biodata: full })).body.code, 'BANNED');
  let r = await call(2, 'PUT', '/api/buddy/biodata', { biodata: full });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.deepEqual(r.body.biodata, full);
  assert.deepEqual((await call(2, 'GET', '/api/buddy/biodata')).body.biodata, full);
  assert.deepEqual((await call(2, 'GET', '/api/buddy/profile')).body.profile.biodata, full);

  // stranger (5) in discover: education + profession only
  r = await call(5, 'GET', '/api/buddy/discover?intent=friend');
  const ravi = r.body.candidates.find((c) => c.userId === 2);
  assert.ok(ravi, JSON.stringify(r.body));
  assert.equal(ravi.education, 'MBA');
  assert.equal(ravi.profession, 'Banker');
  assert.ok(!('biodata' in ravi));
  assert.ok(!JSON.stringify(r.body).includes('Kashyap'));
  r = await call(5, 'GET', '/api/buddy/user/2');
  assert.ok(!('biodata' in r.body.candidate), 'not for strangers');
  // accepted buddy (1) sees everything
  r = await call(1, 'GET', '/api/buddy/user/2');
  assert.deepEqual(r.body.candidate.biodata, full);
  // clearing
  r = await call(2, 'PUT', '/api/buddy/biodata', { biodata: {} });
  assert.deepEqual(r.body.biodata, {});
  assert.deepEqual(t.buddy_profiles.find((p) => p.user_id === 2).biodata, {});
});

// ---------------------------------------------------------------------------
// Family links
// ---------------------------------------------------------------------------
test('family links: create, public payload has no birth data or contact, revoke, expire, max 5 active', async () => {
  const t = seed();
  t.buddy_profiles.find((p) => p.user_id === 1).biodata = { education: 'MA', gotra: 'Bharadwaj' };
  t.buddy_profiles.find((p) => p.user_id === 1).verified_at = new Date();
  assert.equal((await call(null, 'POST', '/api/family/links', {})).status, 401);
  assert.equal((await call(8, 'POST', '/api/family/links', {})).body.code, 'NO_PROFILE');
  assert.equal((await call(7, 'POST', '/api/family/links', {})).body.code, 'BANNED');
  assert.equal((await call(1, 'POST', '/api/family/links', { kind: 'enemy' })).status, 400);

  let r = await call(1, 'POST', '/api/family/links', {}, { 'X-Forwarded-Host': 'cosmic.example.com' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const link = r.body.link;
  assert.equal(link.kind, 'self');
  assert.match(link.token, /^[A-Za-z0-9_-]{24,}$/);
  assert.equal(link.url, `https://cosmic.example.com/f/${link.token}`);
  assert.equal(link.active, true);
  const days = (new Date(link.expiresAt) - Date.now()) / 86400000;
  assert.ok(days > 29.9 && days <= 30, String(days));

  // public, no login
  r = await call(null, 'GET', `/api/family/${link.token}`);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.match(r.headers.get('cache-control'), /no-store/);
  assert.match(r.headers.get('x-robots-tag'), /noindex/);
  const p = r.body.person;
  assert.equal(p.displayName, 'Asha');
  assert.equal(p.age, 31);
  assert.equal(p.city, 'Delhi');
  assert.equal(p.verified, true);
  assert.deepEqual(p.kundli, { moonSign: 'Cancer', nakshatra: 'Pushya', manglik: true });
  assert.deepEqual(p.biodata, { education: 'MA', gotra: 'Bharadwaj' });
  const s = JSON.stringify(r.body);
  for (const leak of ['1995-03-10', '05:45', 'Varanasi', '28.61', '77.21', '1@x.com', '"lat"', '"lng"', 'dateOfBirth', 'timeOfBirth', 'placeOfBirth', 'email', 'phone"', 'notes', 'selfie', 'ascendant', 'Leo']) {
    assert.ok(!s.includes(leak), `family payload leaks ${leak}`);
  }

  // the page itself
  const page = await fetch(`${base}/f/${link.token}`);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type'), /text\/html/);
  assert.match(page.headers.get('x-robots-tag'), /noindex/);
  assert.match(page.headers.get('cache-control'), /no-store/);
  const html = await page.text();
  assert.match(html, /<meta name="robots" content="noindex/);
  assert.doesNotMatch(html, /innerHTML|<script[^>]+src=|<link[^>]+href=["']?https?:/i, 'textContent only, no external dependencies');

  // bad / unknown tokens
  assert.equal((await call(null, 'GET', '/api/family/short')).body.code, 'NOT_FOUND');
  assert.equal((await call(null, 'GET', `/api/family/${'A'.repeat(32)}`)).body.code, 'NOT_FOUND');

  // list + revoke (others cannot revoke)
  r = await call(1, 'GET', '/api/family/links');
  assert.equal(r.body.links.length, 1);
  assert.equal(r.body.maxActive, 5);
  assert.equal((await call(2, 'DELETE', `/api/family/links/${link.id}`)).status, 404);
  r = await call(1, 'DELETE', `/api/family/links/${link.id}`);
  assert.equal(r.body.link.active, false);
  assert.ok(r.body.link.revokedAt);
  assert.equal((await call(null, 'GET', `/api/family/${link.token}`)).body.code, 'LINK_EXPIRED');

  // max 5 active; an expired one frees a slot
  const made = [];
  for (let i = 0; i < 5; i++) made.push((await call(1, 'POST', '/api/family/links', {})).body.link);
  r = await call(1, 'POST', '/api/family/links', {});
  assert.equal(r.status, 409);
  assert.equal(r.body.code, 'LINK_LIMIT');
  t.family_links.find((l) => l.id === made[0].id).expires_at = new Date(Date.now() - 1000);
  assert.equal((await call(null, 'GET', `/api/family/${made[0].token}`)).body.code, 'LINK_EXPIRED');
  assert.equal((await call(1, 'POST', '/api/family/links', {})).status, 200);

  // a ban turns every link off
  t.buddy_profiles.find((x) => x.user_id === 1).banned_at = new Date();
  assert.equal((await call(null, 'GET', `/api/family/${made[1].token}`)).status, 404);
});

test('family notes: validation, push to the owner, per token+IP rate limit, list and delete', async () => {
  const t = seed();
  const link = (await call(2, 'POST', '/api/family/links', {})).body.link;
  const note = { name: 'Sunita', relation: 'Mother', message: 'Beta, she seems lovely. Call me tonight.' };
  for (const bad of [{ ...note, name: '' }, { ...note, name: 'x'.repeat(41) }, { ...note, relation: 'Uncle' }, { ...note, message: '' }, { ...note, message: 'x'.repeat(501) }]) {
    assert.equal((await call(null, 'POST', `/api/family/${link.token}/notes`, bad)).status, 400, JSON.stringify(bad));
  }
  let r = await call(null, 'POST', `/api/family/${link.token}/notes`, note, { 'X-Real-IP': '203.0.113.5' });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.deepEqual(pushed.map((p) => [p.userId, p.type]), [[2, 'family_note']]);
  assert.equal(pushed[0].data.linkId, link.id);
  assert.ok(pushed[0].data.noteId);
  assert.ok(!t.family_notes[0].ip_hash.includes('203.0.113.5'), 'IP is stored only as a hash');
  for (let i = 0; i < 4; i++) {
    assert.equal((await call(null, 'POST', `/api/family/${link.token}/notes`, note, { 'X-Real-IP': '203.0.113.5' })).status, 200);
  }
  r = await call(null, 'POST', `/api/family/${link.token}/notes`, note, { 'X-Real-IP': '203.0.113.5' });
  assert.equal(r.status, 429);
  assert.equal(r.body.code, 'RATE_LIMITED');
  // another relative on another network is not blocked
  assert.equal((await call(null, 'POST', `/api/family/${link.token}/notes`, { ...note, name: 'Ramesh', relation: 'Father' }, { 'X-Real-IP': '198.51.100.9' })).status, 200);

  r = await call(2, 'GET', '/api/family/notes');
  assert.equal(r.body.notes.length, 6);
  assert.equal(r.body.notes[0].name, 'Ramesh');
  assert.equal(r.body.notes[0].relation, 'Father');
  assert.equal((await call(1, 'GET', '/api/family/notes')).body.notes.length, 0, 'notes are private to the owner');
  assert.equal((await call(1, 'DELETE', `/api/family/notes/${r.body.notes[0].id}`)).status, 404);
  assert.equal((await call(2, 'DELETE', `/api/family/notes/${r.body.notes[0].id}`)).body.ok, true);
  assert.equal((await call(2, 'GET', '/api/family/notes')).body.notes.length, 5);
  // public payload never includes notes
  assert.ok(!JSON.stringify((await call(null, 'GET', `/api/family/${link.token}`)).body).includes('Sunita'));
  // revoked link takes no more notes
  await call(2, 'DELETE', `/api/family/links/${link.id}`);
  assert.equal((await call(null, 'POST', `/api/family/${link.token}/notes`, { ...note, name: 'Late' }, { 'X-Real-IP': '192.0.2.1' })).status, 404);
});

test('family match share: only accepted buddies, includes our score, stops when the connection ends', async () => {
  const t = seed();
  t.buddy_profiles.find((p) => p.user_id === 2).biodata = { profession: 'Doctor' };
  // 5 is a stranger to 1: refused
  let r = await call(1, 'POST', '/api/family/links', { kind: 'match', matchUserId: 5 });
  assert.equal(r.status, 403);
  assert.equal(r.body.code, 'NOT_BUDDIES');
  assert.equal((await call(1, 'POST', '/api/family/links', { kind: 'match' })).status, 400);
  // pending is not enough
  t.buddy_connections.push({ id: 2, from_user_id: 1, to_user_id: 5, intent: 'friend', status: 'pending', created_at: new Date() });
  assert.equal((await call(1, 'POST', '/api/family/links', { kind: 'match', matchUserId: 5 })).body.code, 'NOT_BUDDIES');

  r = await call(1, 'POST', '/api/family/links', { kind: 'match', matchUserId: 2 });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const link = r.body.link;
  assert.equal(link.kind, 'match');
  assert.deepEqual(link.match, { userId: 2, displayName: 'Ravi' });
  r = await call(null, 'GET', `/api/family/${link.token}`);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.kind, 'match');
  assert.equal(r.body.sharedBy.displayName, 'Asha');
  assert.equal(r.body.person.displayName, 'Ravi');
  assert.equal(r.body.person.kundli.manglik, false);
  assert.deepEqual(r.body.person.biodata, { profession: 'Doctor' });
  assert.ok(Number.isInteger(r.body.compatibility.score));
  assert.ok(r.body.compatibility.breakdown);
  for (const leak of ['1992-07-21', '1995-03-10', 'Varanasi', '2@x.com', 'lat"', 'lng"']) assert.ok(!JSON.stringify(r.body).includes(leak), leak);

  // a note on a match link goes to the person who shared it
  await call(null, 'POST', `/api/family/${link.token}/notes`, { name: 'Papa', relation: 'Father', message: 'Looks good' });
  assert.equal(pushed.at(-1).userId, 1);
  assert.equal((await call(1, 'GET', '/api/family/notes')).body.notes[0].about, 'Ravi');

  // block or ending the connection turns the match link off
  t.buddy_blocks.push({ user_id: 2, blocked_user_id: 1 });
  assert.equal((await call(null, 'GET', `/api/family/${link.token}`)).body.code, 'UNAVAILABLE');
  t.buddy_blocks.length = 0;
  t.buddy_connections[0].status = 'cancelled';
  assert.equal((await call(null, 'GET', `/api/family/${link.token}`)).status, 404);
});

test('family internals: token shape, base url', () => {
  const F = familyRouter._internals;
  const tok = F.newToken();
  assert.match(tok, F.TOKEN_RE);
  assert.ok(tok.length >= 24);
  assert.notEqual(tok, F.newToken());
  const req = (host) => ({ get: (h) => (h.toLowerCase() === 'host' ? host : undefined) });
  assert.equal(F.baseUrl(req('api.example.com')), 'https://api.example.com');
  assert.equal(F.baseUrl(req('localhost:5000')), 'http://localhost:5000');
  process.env.PUBLIC_BASE_URL = 'https://cg.example.org/';
  assert.equal(F.baseUrl(req('x')), 'https://cg.example.org');
  delete process.env.PUBLIC_BASE_URL;
  assert.equal(F.LINK_DAYS, 30);
  assert.equal(F.MAX_ACTIVE_LINKS, 5);
});
