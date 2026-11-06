// Buddy: opt-in matching (Kundli + mindset quiz + distance), connection requests, chat and safety.
// Privacy: other people's coordinates, birth details, Kundli data and quiz answers never leave the
// server; candidates carry only score, breakdown, short highlights and shared-answer counts.
// Every SQL statement starts with a /*q:name*/ tag (used by the fake db in test/buddy.test.js).
const fs = require('fs');
const path = require('path');
const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const { todayISO } = require('../services/astrology_service');
const M = require('../services/buddy_matching');
const push = require('../services/push_service');
const T = require('../services/trust_service');
const FA = require('../services/firebase_auth_service');

const QUIZ_TOTAL = 50;
// Discover ranking boost (sorting only; the score people see is unchanged): a selfie-verified
// candidate ranks as if their score were 3 points higher, a phone-verified one 1 point higher.
const VERIFIED_RANK_BOOST = 3;
const PHONE_RANK_BOOST = 1;
const MIN_AGE = 18;
const NEARBY_KM = 10;
const NEARBY_MIN_SCORE = 60;
const NEARBY_MAX = 5;
const CANDIDATE_POOL = 300; // SQL prefilter cap before scoring in JS
const REPORT_REASONS = ['fake', 'harassment', 'inappropriate', 'scam', 'underage', 'other'];
const GENDERS = ['male', 'female', 'other'];
const INTERESTED_IN = ['male', 'female', 'any'];
const MAX_INT = 2147483647; // Postgres INTEGER: larger ids would make the query throw (500)
// Abuse limits (counted in the database, so they hold across serverless instances)
const MESSAGES_PER_MINUTE = 20;
const REQUESTS_PER_DAY = 30;
const REPORTS_PER_DAY = 10;

// ---------------------------------------------------------------------------
// Mindset question categories (backend/data/mindset_questions.json, owned by the rewards route)
// ---------------------------------------------------------------------------
let questionCategories = null;
function categoryOf(qid) {
  if (!questionCategories) {
    questionCategories = new Map();
    try {
      const raw = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'data', 'mindset_questions.json'), 'utf8'));
      const list = Array.isArray(raw) ? raw : (raw && raw.questions) || [];
      for (const q of list) if (q && q.id) questionCategories.set(String(q.id), q.category);
    } catch (_) { /* file missing: answers are compared without category weights */ }
  }
  return questionCategories.get(String(qid));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
const bad = (message, code = 'INVALID_INPUT') => new HttpError(400, message, code);

const wrap = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    if (err instanceof HttpError) {
      return res.status(err.status).json(err.code ? { error: err.message, code: err.code } : { error: err.message });
    }
    console.error('Buddy route error:', err);
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
};

function requireRegistered(req, res, next) {
  if (!req.user || req.user.role === 'guest') {
    return res.status(401).json({ error: 'Please log in to use Buddies', code: 'LOGIN_REQUIRED' });
  }
  return next();
}
const registered = [optionalAuthenticateToken, requireRegistered];

const todayIST = () => todayISO('Asia/Kolkata');

function isoDate(v) {
  if (!v) return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.toISOString().slice(0, 10);
  return String(v).slice(0, 10);
}
function iso(v) {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
/** Latest birth date that is 18+ today (IST), for the SQL prefilter. */
function adultCutoff(today) {
  const [y, m, d] = today.split('-');
  const md = m === '02' && d === '29' ? '02-28' : `${m}-${d}`;
  return `${Number(y) - MIN_AGE}-${md}`;
}
function firstName(full) {
  const s = String(full || '').trim().split(/\s+/)[0] || '';
  return s.slice(0, 40);
}
function toInt(v) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 && n <= MAX_INT ? n : null;
}
async function countSince(tag, sql, params) {
  const r = await db.query(`/*q:${tag}*/ ${sql}`, params);
  return Number(r.rows[0] && r.rows[0].n) || 0;
}
const asArray = (v) => (Array.isArray(v) ? v : typeof v === 'string' && v.startsWith('{')
  ? v.slice(1, -1).split(',').filter(Boolean).map((s) => s.replace(/^"|"$/g, ''))
  : []);
// Same wording as BuddyIntent.label in the app (lib/services/buddy_service.dart).
const INTENT_LABELS = {
  life_partner: 'Life partner', business: 'Business partner', friend: 'Friend', travel: 'Travel buddy', spiritual: 'Satsang buddy'
};
const intentLabel = (intent) => INTENT_LABELS[intent] || 'Buddy';
const buddyName = (row) => (row && (row.display_name || firstName(row.full_name))) || 'Someone';

// ---------------------------------------------------------------------------
// Push events (services/push_service never throws and caps itself at a few seconds)
// ---------------------------------------------------------------------------
async function nameOf(userId) {
  try { return buddyName(await loadMe(userId)); } catch (_) { return 'Someone'; }
}
function notifyRequest(toUserId, conn, fromName) {
  return push.sendToUser(toUserId, {
    type: 'buddy_request',
    title: 'New buddy request',
    body: `${fromName} wants to be your ${intentLabel(conn.intent).toLowerCase()}`,
    data: { connectionId: conn.id },
  }, { pref: 'buddy' });
}
function notifyAccepted(toUserId, conn, accepterName) {
  return push.sendToUser(toUserId, {
    type: 'buddy_accepted',
    title: 'Request accepted',
    body: `${accepterName} accepted your request. Say namaste!`,
    data: { connectionId: conn.id, name: accepterName },
  }, { pref: 'buddy' });
}
function notifyMessage(toUserId, connectionId, senderName, text) {
  const body = text.length > 80 ? `${text.slice(0, 79)}…` : text;
  return push.sendToUser(toUserId, {
    type: 'buddy_message',
    title: senderName,
    body,
    data: { connectionId, name: senderName },
    collapseKey: `buddy_chat_${connectionId}`,
  }, { pref: 'messages', inbox: false });
}

const cleanText = (v, max) => String(v === undefined || v === null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max);

// Columns describing another person (joined from buddy_profiles + users + birth_details + kundlis).
const PERSON_COLS = `u.id AS user_id, u.full_name, u.role, u.gender AS user_gender,
  bd.date_of_birth, bd.gender AS birth_gender,
  k.moon_sign, k.nakshatra, k.ascendant, k.kundli_data->>'moonLongitude' AS moon_longitude,
  bp.user_id AS bp_user_id, bp.display_name, bp.bio, bp.intents, bp.gender, bp.interested_in, bp.city,
  bp.lat, bp.lng, bp.photo_url, bp.languages, bp.show_nearby, bp.is_active, bp.banned_at, bp.created_at, bp.updated_at,
  bp.verified_at, bp.phone_verified_at, bp.biodata`;
const isBanned = (row) => !!(row && row.banned_at);
const isVerified = (row) => !!(row && row.verified_at) && !isBanned(row);
const isPhoneVerified = (row) => !!(row && row.phone_verified_at) && !isBanned(row);
const BANNED_MSG = 'Your buddy profile has been suspended after a safety review';

/** Eligibility from a person row: registered, has a Kundli, 18+ (IST today). */
function eligibility(row, today = todayIST()) {
  if (!row || row.role === 'guest') return { eligible: false, reason: 'LOGIN_REQUIRED', age: null };
  const age = M.ageOn(isoDate(row.date_of_birth), today);
  if (!row.date_of_birth || !row.moon_sign || !row.nakshatra) return { eligible: false, reason: 'NO_KUNDLI', age };
  if (age === null || age < MIN_AGE) return { eligible: false, reason: 'UNDER_18', age };
  return { eligible: true, age };
}

function ownProfile(row) {
  if (!row || !row.bp_user_id) return null;
  return {
    userId: Number(row.user_id),
    displayName: row.display_name,
    bio: row.bio || '',
    intents: asArray(row.intents),
    gender: row.gender || null,
    interestedIn: row.interested_in || 'any',
    city: row.city || null,
    languages: asArray(row.languages),
    photoUrl: row.photo_url || null,
    showNearby: row.show_nearby !== false,
    isActive: row.is_active !== false && !isBanned(row),
    banned: isBanned(row),
    hasLocation: row.lat !== null && row.lat !== undefined && row.lng !== null && row.lng !== undefined,
    verified: isVerified(row),
    phoneVerified: isPhoneVerified(row),
    verifiedAt: iso(row.verified_at),
    biodata: T.biodataView(row.biodata),
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at)
  };
}

/** Matching input for a person row (+ their answers). Private data stays inside the server. */
function matchInput(row, answers = {}) {
  return {
    userId: Number(row.user_id),
    kundli: { moonSign: row.moon_sign, nakshatra: row.nakshatra, ascendant: row.ascendant, moonLongitude: row.moon_longitude },
    gender: row.gender || M.normalizeGender(row.birth_gender || row.user_gender),
    interestedIn: row.interested_in || 'any',
    intents: asArray(row.intents),
    languages: asArray(row.languages),
    answers,
    lat: row.lat === null || row.lat === undefined ? null : Number(row.lat),
    lng: row.lng === null || row.lng === undefined ? null : Number(row.lng)
  };
}

function connectionView(c, meId) {
  if (!c) return null;
  const outgoing = Number(c.from_user_id) === meId;
  return {
    id: Number(c.id),
    intent: c.intent,
    status: c.status,
    message: c.message || null,
    direction: outgoing ? 'outgoing' : 'incoming',
    otherUserId: Number(outgoing ? c.to_user_id : c.from_user_id),
    createdAt: iso(c.created_at),
    respondedAt: iso(c.responded_at)
  };
}
const candidateConnection = (c, meId) => (c && ['pending', 'accepted', 'declined'].includes(c.status)
  ? { id: Number(c.id), status: c.status, direction: Number(c.from_user_id) === meId ? 'outgoing' : 'incoming' }
  : null);

/**
 * Another person. Everyone sees the badges plus education/profession; the full biodata only
 * goes to accepted buddies (`fullBiodata`) and to family links (routes/family.js).
 */
function candidateView(row, match, today, connection = null, { fullBiodata = false } = {}) {
  const bio = T.biodataView(row.biodata);
  return {
    userId: Number(row.user_id),
    displayName: row.display_name || firstName(row.full_name) || 'Buddy',
    age: M.ageOn(isoDate(row.date_of_birth), today),
    city: row.city || null,
    distanceKm: match.distanceKm,
    photoUrl: row.photo_url || null,
    intents: asArray(row.intents),
    bio: row.bio || '',
    languages: asArray(row.languages),
    score: match.score,
    breakdown: match.breakdown,
    highlights: match.highlights,
    sharedAnswers: match.sharedAnswers,
    agreeAnswers: match.agreeAnswers,
    matchIntent: match.intent,
    verified: isVerified(row),
    phoneVerified: isPhoneVerified(row),
    education: bio.education || null,
    profession: bio.profession || null,
    ...(fullBiodata ? { biodata: bio } : {}),
    connection
  };
}

// ---------------------------------------------------------------------------
// Data access
// ---------------------------------------------------------------------------
async function loadMe(userId) {
  const r = await db.query(
    `/*q:me*/ SELECT ${PERSON_COLS}
     FROM users u
     LEFT JOIN birth_details bd ON bd.user_id = u.id
     LEFT JOIN kundlis k ON k.user_id = u.id
     LEFT JOIN buddy_profiles bp ON bp.user_id = u.id
     WHERE u.id = $1`,
    [userId]
  );
  return r.rows[0] || null;
}

async function loadPerson(userId) {
  const r = await db.query(
    `/*q:person*/ SELECT ${PERSON_COLS}
     FROM buddy_profiles bp
     JOIN users u ON u.id = bp.user_id
     JOIN birth_details bd ON bd.user_id = bp.user_id
     JOIN kundlis k ON k.user_id = bp.user_id
     WHERE bp.user_id = $1`,
    [userId]
  );
  return r.rows[0] || null;
}

async function answersFor(userIds) {
  const map = new Map(userIds.map((id) => [Number(id), {}]));
  if (!userIds.length) return map;
  const r = await db.query(
    '/*q:answers*/ SELECT user_id, question_id, option_index FROM mindset_answers WHERE user_id = ANY($1::int[])',
    [userIds]
  );
  for (const a of r.rows) {
    const m = map.get(Number(a.user_id));
    if (m) m[a.question_id] = Number(a.option_index);
  }
  return map;
}

async function bannedEither(a, b) {
  const r = await db.query(
    '/*q:bannedPair*/ SELECT user_id FROM buddy_profiles WHERE user_id = ANY($1::int[]) AND banned_at IS NOT NULL LIMIT 1',
    [[a, b]]
  );
  return r.rows.length > 0;
}

async function blockedPair(a, b) {
  const r = await db.query(
    `/*q:blockedPair*/ SELECT 1 FROM buddy_blocks
     WHERE (user_id = $1 AND blocked_user_id = $2) OR (user_id = $2 AND blocked_user_id = $1) LIMIT 1`,
    [a, b]
  );
  return r.rows.length > 0;
}

async function connectionsBetween(a, b) {
  const r = await db.query(
    `/*q:connectionPair*/ SELECT * FROM buddy_connections
     WHERE (from_user_id = $1 AND to_user_id = $2) OR (from_user_id = $2 AND to_user_id = $1)`,
    [a, b]
  );
  return r.rows;
}

/** The connection that best describes a pair: accepted > pending > declined > other, newest first. */
function primaryConnection(rows) {
  const rank = { accepted: 4, pending: 3, declined: 2 };
  const t = (c) => new Date(c.created_at || 0).getTime() || 0;
  return rows.slice().sort((x, y) => ((rank[y.status] || 0) - (rank[x.status] || 0)) || (t(y) - t(x)))[0] || null;
}

/** Ids hidden from me in discover/nearby: blocks either way + pending/accepted/declined pairs. */
async function hiddenIds(meId) {
  const [blocks, conns] = await Promise.all([
    db.query('/*q:blocks*/ SELECT user_id, blocked_user_id FROM buddy_blocks WHERE user_id = $1 OR blocked_user_id = $1', [meId]),
    db.query('/*q:myConnections*/ SELECT id, from_user_id, to_user_id, status FROM buddy_connections WHERE from_user_id = $1 OR to_user_id = $1', [meId])
  ]);
  return M.excludedUserIds(meId, blocks.rows, conns.rows);
}

async function findCandidates(meId, { excluded, today, intent, intentsAny, box, nearbyOnly, verifiedOnly }) {
  const r = await db.query(
    `/*q:candidates*/ SELECT ${PERSON_COLS}
     FROM buddy_profiles bp
     JOIN users u ON u.id = bp.user_id
     JOIN birth_details bd ON bd.user_id = bp.user_id
     JOIN kundlis k ON k.user_id = bp.user_id
     WHERE bp.is_active = TRUE
       AND bp.banned_at IS NULL
       AND bp.user_id <> $1
       AND NOT (bp.user_id = ANY($2::int[]))
       AND COALESCE(u.role, 'user') <> 'guest'
       AND bd.date_of_birth <= $3::date
       AND ($4::text IS NULL OR $4::text = ANY(bp.intents))
       AND ($5::text[] IS NULL OR bp.intents && $5::text[])
       AND ($6::numeric IS NULL OR (bp.lat BETWEEN $6::numeric AND $7::numeric AND bp.lng BETWEEN $8::numeric AND $9::numeric))
       AND ($10::boolean = FALSE OR bp.show_nearby = TRUE)
       AND ($12::boolean = FALSE OR bp.verified_at IS NOT NULL)
     ORDER BY bp.updated_at DESC
     LIMIT $11`,
    [meId, excluded, adultCutoff(today), intent || null, intentsAny || null,
      box ? box.minLat : null, box ? box.maxLat : null, box ? box.minLng : null, box ? box.maxLng : null,
      !!nearbyOnly, CANDIDATE_POOL, !!verifiedOnly]
  );
  return verifiedOnly ? r.rows.filter(isVerified) : r.rows;
}

/** Loads me and insists on an eligible, active buddy profile. */
async function requireActiveMe(userId) {
  const me = await loadMe(userId);
  if (!me) throw new HttpError(401, 'Please log in to use Buddies', 'LOGIN_REQUIRED');
  const el = eligibility(me);
  if (!el.eligible) throw new HttpError(403, el.reason === 'UNDER_18' ? 'Buddies is for people aged 18 and over' : 'Create your Kundli first to use Buddies', el.reason);
  if (!me.bp_user_id) throw new HttpError(409, 'Set up your buddy profile first', 'NO_PROFILE');
  if (isBanned(me)) throw new HttpError(403, BANNED_MSG, 'BANNED');
  if (me.is_active === false) throw new HttpError(409, 'Your buddy profile is paused', 'PROFILE_PAUSED');
  return me;
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

// GET /api/buddy/profile
router.get('/profile', optionalAuthenticateToken, wrap(async (req, res) => {
  if (!req.user || req.user.role === 'guest') {
    return res.json({ profile: null, eligible: false, banned: false, reason: 'LOGIN_REQUIRED', age: null, quizAnswered: 0, quizTotal: QUIZ_TOTAL });
  }
  const me = await loadMe(req.user.userId);
  if (!me) throw new HttpError(401, 'Please log in to use Buddies', 'LOGIN_REQUIRED');
  const el = eligibility(me);
  const answers = (await answersFor([Number(me.user_id)])).get(Number(me.user_id)) || {};
  const banned = isBanned(me);
  const out = { profile: ownProfile(me), eligible: el.eligible && !banned, banned, age: el.age, quizAnswered: Object.keys(answers).length, quizTotal: QUIZ_TOTAL };
  if (!el.eligible) out.reason = el.reason;
  else if (banned) out.reason = 'BANNED';
  res.json(out);
}));

/** Validates and normalises a profile body, merged over the existing profile. Throws HttpError(400). */
function validateProfile(body, me) {
  const cur = ownProfile(me) || {};
  const has = (k) => Object.prototype.hasOwnProperty.call(body, k) && body[k] !== undefined;

  let displayName = has('displayName') ? cleanText(body.displayName, 40) : (cur.displayName || '');
  if (!displayName) displayName = firstName(me.full_name) || 'Buddy';

  const bioRaw = has('bio') ? String(body.bio === null ? '' : body.bio).trim() : (cur.bio || '');
  if (bioRaw.length > 500) throw bad('Bio can be at most 500 characters');

  let intents = cur.intents || [];
  if (has('intents')) {
    if (!Array.isArray(body.intents)) throw bad('Pick what you are looking for');
    intents = [...new Set(body.intents.map((i) => String(i).trim()))];
    if (intents.some((i) => !M.INTENTS.includes(i))) throw bad('Unknown buddy type');
  }
  if (intents.length < 1 || intents.length > 5) throw bad('Pick between 1 and 5 buddy types');

  let gender = has('gender') ? body.gender : (cur.gender || M.normalizeGender(me.birth_gender || me.user_gender));
  if (gender !== null && gender !== undefined && gender !== '') {
    gender = M.normalizeGender(gender);
    if (!GENDERS.includes(gender)) throw bad('Gender must be male, female or other');
  } else gender = null;

  let interestedIn = has('interestedIn') ? String(body.interestedIn || 'any').trim().toLowerCase() : (cur.interestedIn || 'any');
  if (!INTERESTED_IN.includes(interestedIn)) throw bad('interestedIn must be male, female or any');

  const city = has('city') ? (cleanText(body.city, 120) || null) : (cur.city || null);

  let languages = cur.languages || [];
  if (has('languages')) {
    if (!Array.isArray(body.languages)) throw bad('Languages must be a list');
    const seen = new Set();
    languages = [];
    for (const l of body.languages) {
      const s = cleanText(l, 30);
      if (s && !seen.has(s.toLowerCase())) { seen.add(s.toLowerCase()); languages.push(s); }
    }
    languages = languages.slice(0, 8);
  }

  let photoUrl = has('photoUrl') ? body.photoUrl : (cur.photoUrl || null);
  if (photoUrl === '' || photoUrl === null || photoUrl === undefined) photoUrl = null;
  else {
    photoUrl = String(photoUrl).trim();
    if (photoUrl.length > 500 || !/^https:\/\/[^\s]+$/i.test(photoUrl)) throw bad('Photo must be an https link');
  }

  const bool = (k, fallback) => {
    if (!has(k)) return fallback;
    if (typeof body[k] !== 'boolean') throw bad(`${k} must be true or false`);
    return body[k];
  };
  const showNearby = bool('showNearby', cur.showNearby !== undefined ? cur.showNearby : true);
  const isActive = bool('isActive', true);

  return { displayName, bio: bioRaw, intents, gender, interestedIn, city, languages, photoUrl, showNearby, isActive };
}

// PUT /api/buddy/profile
router.put('/profile', registered, wrap(async (req, res) => {
  const me = await loadMe(req.user.userId);
  if (!me) throw new HttpError(401, 'Please log in to use Buddies', 'LOGIN_REQUIRED');
  const el = eligibility(me);
  if (!el.eligible) {
    throw new HttpError(403, el.reason === 'UNDER_18' ? 'Buddies is for people aged 18 and over' : 'Create your Kundli first to use Buddies', el.reason);
  }
  const p = validateProfile(req.body || {}, me);
  if (isBanned(me)) { p.isActive = false; p.showNearby = false; }
  await db.query(
    `/*q:upsertProfile*/ INSERT INTO buddy_profiles
       (user_id, display_name, bio, intents, gender, interested_in, city, languages, photo_url, show_nearby, is_active)
     VALUES ($1, $2, $3, $4::text[], $5, $6, $7, $8::text[], $9, $10, $11)
     ON CONFLICT (user_id) DO UPDATE SET
       display_name = EXCLUDED.display_name, bio = EXCLUDED.bio, intents = EXCLUDED.intents,
       gender = EXCLUDED.gender, interested_in = EXCLUDED.interested_in, city = EXCLUDED.city,
       languages = EXCLUDED.languages, photo_url = EXCLUDED.photo_url,
       -- a ban (set by an admin, possibly mid-request) always wins over the body
       show_nearby = CASE WHEN buddy_profiles.banned_at IS NOT NULL THEN FALSE ELSE EXCLUDED.show_nearby END,
       is_active = CASE WHEN buddy_profiles.banned_at IS NOT NULL THEN FALSE ELSE EXCLUDED.is_active END,
       updated_at = CURRENT_TIMESTAMP`,
    [me.user_id, p.displayName, p.bio, p.intents, p.gender, p.interestedIn, p.city, p.languages, p.photoUrl, p.showNearby, p.isActive]
  );
  res.json({ profile: ownProfile(await loadMe(req.user.userId)) });
}));

// DELETE /api/buddy/profile -> pause (hidden from everyone; data kept)
router.delete('/profile', registered, wrap(async (req, res) => {
  await db.query('/*q:deactivate*/ UPDATE buddy_profiles SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1', [req.user.userId]);
  res.json({ ok: true, profile: ownProfile(await loadMe(req.user.userId)) });
}));

// PUT /api/buddy/location {lat, lng, city?}
router.put('/location', registered, wrap(async (req, res) => {
  const { lat, lng } = req.body || {};
  if (typeof lat !== 'number' || typeof lng !== 'number' || !M.validLatLng(lat, lng)) throw bad('A valid location is required');
  const city = req.body.city === undefined || req.body.city === null ? null : (cleanText(req.body.city, 120) || null);
  const r = await db.query(
    `/*q:location*/ UPDATE buddy_profiles SET lat = $2, lng = $3, city = COALESCE($4, city), updated_at = CURRENT_TIMESTAMP
     WHERE user_id = $1 AND banned_at IS NULL RETURNING user_id`,
    [req.user.userId, M.roundCoord(lat), M.roundCoord(lng), city]
  );
  if (!r.rows.length) {
    if (isBanned(await loadMe(req.user.userId))) throw new HttpError(403, BANNED_MSG, 'BANNED');
    throw new HttpError(409, 'Set up your buddy profile first', 'NO_PROFILE');
  }
  res.json({ ok: true });
}));

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/** Scores candidate rows against me; drops anyone failing the life_partner gender filter. */
async function scoreRows(me, rows, { intent, maxKm, fallbackIntent }) {
  const ids = [Number(me.user_id), ...rows.map((r) => Number(r.user_id))];
  const answers = await answersFor(ids);
  const meInput = matchInput(me, answers.get(Number(me.user_id)));
  const today = todayIST();
  const out = [];
  for (const row of rows) {
    const age = M.ageOn(isoDate(row.date_of_birth), today);
    if (age === null || age < MIN_AGE || !row.moon_sign || isBanned(row)) continue;
    const other = matchInput(row, answers.get(Number(row.user_id)));
    if (intent === 'life_partner' && !M.lifePartnerCompatible(meInput, other)) continue;
    const match = M.bestMatch(meInput, other, { intent: intent === 'all' ? null : intent, maxKm, categoryOf }, fallbackIntent);
    if (!match) continue;
    out.push({ row, match });
  }
  out.sort((a, b) => rankOf(b) - rankOf(a) || (a.match.km ?? Infinity) - (b.match.km ?? Infinity));
  return out;
}
/** Sort key for lists: score + the trust boosts documented at the top of this file. */
function rankOf({ row, match }) {
  return match.score + (isVerified(row) ? VERIFIED_RANK_BOOST : 0) + (isPhoneVerified(row) ? PHONE_RANK_BOOST : 0);
}

// GET /api/buddy/discover?intent=<intent|all>&maxKm=<n>&limit=20
router.get('/discover', registered, wrap(async (req, res) => {
  const me = await requireActiveMe(req.user.userId);
  const intent = typeof req.query.intent === 'string' && req.query.intent ? req.query.intent : 'all';
  if (intent !== 'all' && !M.INTENTS.includes(intent)) throw bad('Unknown buddy type');
  const maxKmRaw = req.query.maxKm === undefined || req.query.maxKm === '' ? null : Number(req.query.maxKm);
  if (maxKmRaw !== null && !(maxKmRaw > 0)) throw bad('maxKm must be a positive number');
  const maxKm = maxKmRaw === null ? null : Math.min(maxKmRaw, 20000);
  const limit = Math.max(1, Math.min(50, toInt(req.query.limit) || 20));
  const verifiedOnly = ['1', 'true'].includes(String(req.query.verifiedOnly || '').toLowerCase());

  const myIntents = asArray(me.intents);
  const hasLoc = me.lat !== null && me.lat !== undefined && me.lng !== null && me.lng !== undefined;
  const box = maxKm !== null && hasLoc ? M.boundingBox(Number(me.lat), Number(me.lng), maxKm) : null;
  const rows = await findCandidates(Number(me.user_id), {
    excluded: await hiddenIds(Number(me.user_id)),
    today: todayIST(),
    intent: intent === 'all' ? null : intent,
    intentsAny: intent === 'all' ? myIntents : null,
    box,
    verifiedOnly
  });
  let scored = await scoreRows(me, rows, { intent, maxKm: maxKm || M.DEFAULT_MAX_KM });
  if (box) scored = scored.filter((s) => s.match.km !== null && s.match.km <= maxKm);
  const today = todayIST();
  res.json({ candidates: scored.slice(0, limit).map((s) => candidateView(s.row, s.match, today, null)) });
}));

// GET /api/buddy/nearby -> strong matches within 10 km (both people opted into nearby)
router.get('/nearby', registered, wrap(async (req, res) => {
  const me = await requireActiveMe(req.user.userId);
  const hasLoc = me.lat !== null && me.lat !== undefined && me.lng !== null && me.lng !== undefined;
  if (!hasLoc || me.show_nearby === false) return res.json({ candidates: [] });
  const rows = await findCandidates(Number(me.user_id), {
    excluded: await hiddenIds(Number(me.user_id)),
    today: todayIST(),
    intentsAny: null,
    box: M.boundingBox(Number(me.lat), Number(me.lng), NEARBY_KM),
    nearbyOnly: true
  });
  const scored = (await scoreRows(me, rows, { intent: 'all', maxKm: M.DEFAULT_MAX_KM, fallbackIntent: 'friend' }))
    .filter((s) => s.match.km !== null && s.match.km <= NEARBY_KM && s.match.score >= NEARBY_MIN_SCORE)
    .slice(0, NEARBY_MAX);
  await db.query('/*q:nearbyChecked*/ UPDATE buddy_profiles SET last_nearby_check = CURRENT_TIMESTAMP WHERE user_id = $1', [me.user_id]);
  const today = todayIST();
  res.json({ candidates: scored.map((s) => candidateView(s.row, s.match, today, null)) });
}));

/**
 * Someone is visible to me when not blocked either way, registered, eligible and active
 * (a paused profile stays visible to people already connected with it).
 */
async function visiblePerson(meId, otherId) {
  if (otherId === meId) return null;
  const [row, blocked, conns] = await Promise.all([loadPerson(otherId), blockedPair(meId, otherId), connectionsBetween(meId, otherId)]);
  if (!row || blocked || isBanned(row)) return null;
  const el = eligibility(row);
  if (!el.eligible) return null;
  const conn = primaryConnection(conns);
  const connected = conn && ['pending', 'accepted'].includes(conn.status);
  if (row.is_active === false && !connected) return null;
  return { row, conn, conns };
}

// GET /api/buddy/user/:userId
router.get('/user/:userId', registered, wrap(async (req, res) => {
  const otherId = toInt(req.params.userId);
  if (!otherId) throw bad('Invalid user');
  const me = await requireActiveMe(req.user.userId);
  const v = await visiblePerson(Number(me.user_id), otherId);
  if (!v) throw new HttpError(404, 'This person is not available', 'NOT_FOUND');
  const intentHint = v.conn && M.INTENTS.includes(v.conn.intent) ? v.conn.intent : null;
  const [scored] = await scoreRows(me, [v.row], { intent: intentHint || 'all', maxKm: M.DEFAULT_MAX_KM, fallbackIntent: 'friend' });
  if (!scored) throw new HttpError(404, 'This person is not available', 'NOT_FOUND');
  const accepted = !!(v.conn && v.conn.status === 'accepted');
  res.json({ candidate: candidateView(v.row, scored.match, todayIST(), candidateConnection(v.conn, Number(me.user_id)), { fullBiodata: accepted }) });
}));

// ---------------------------------------------------------------------------
// Connections
// ---------------------------------------------------------------------------

async function setStatus(id, from, to) {
  const r = await db.query(
    `/*q:setStatus*/ UPDATE buddy_connections SET status = $2, responded_at = CURRENT_TIMESTAMP
     WHERE id = $1 AND status = $3 RETURNING *`,
    [id, to, from]
  );
  return r.rows[0] || null;
}

// POST /api/buddy/connect {userId, intent, message?}
router.post('/connect', registered, wrap(async (req, res) => {
  const body = req.body || {};
  const otherId = toInt(body.userId);
  if (!otherId) throw bad('Choose who to connect with');
  if (!M.INTENTS.includes(body.intent)) throw bad('Unknown buddy type');
  const message = body.message === undefined || body.message === null ? null : String(body.message).trim();
  if (message !== null && message.length > 300) throw bad('Message can be at most 300 characters');

  const me = await requireActiveMe(req.user.userId);
  const meId = Number(me.user_id);
  if (otherId === meId) throw bad('You cannot connect with yourself');
  const v = await visiblePerson(meId, otherId);
  if (!v || v.row.is_active === false) throw new HttpError(404, 'This person is not available', 'NOT_FOUND');

  const reverse = v.conns.find((c) => Number(c.from_user_id) === otherId);
  const mine = v.conns.find((c) => Number(c.from_user_id) === meId);
  if (reverse && reverse.status === 'accepted') return res.json({ connection: connectionView(reverse, meId) });
  if (mine && mine.status === 'accepted') return res.json({ connection: connectionView(mine, meId) });
  // They already asked me: accept their request instead of creating a second one.
  if (reverse && reverse.status === 'pending') {
    const accepted = await setStatus(reverse.id, 'pending', 'accepted');
    if (accepted) await notifyAccepted(otherId, accepted, buddyName(me));
    return res.json({ connection: connectionView(accepted || reverse, meId) });
  }
  if (mine && mine.status === 'pending') return res.json({ connection: connectionView(mine, meId) });
  if (mine && mine.status === 'declined') throw new HttpError(409, 'This request was not accepted', 'DECLINED');

  const meInput = matchInput(me);
  const otherInput = matchInput(v.row);
  if (!otherInput.intents.includes(body.intent)) throw bad('This person is not looking for that kind of buddy', 'INTENT_MISMATCH');
  if (body.intent === 'life_partner' && !M.lifePartnerCompatible(meInput, otherInput)) {
    throw bad('This person is not looking for that kind of buddy', 'INTENT_MISMATCH');
  }
  const sentToday = await countSince('recentRequests',
    "SELECT COUNT(*) AS n FROM buddy_connections WHERE from_user_id = $1 AND created_at > NOW() - INTERVAL '1 day'", [meId]);
  if (sentToday >= REQUESTS_PER_DAY) {
    throw new HttpError(429, 'You have sent a lot of requests today. Please try again tomorrow.', 'RATE_LIMITED');
  }
  const [scored] = await scoreRows(me, [v.row], { intent: body.intent, maxKm: M.DEFAULT_MAX_KM });
  const ins = await db.query(
    `/*q:insertConnection*/ INSERT INTO buddy_connections (from_user_id, to_user_id, intent, message, status, score)
     VALUES ($1, $2, $3, $4, 'pending', $5)
     ON CONFLICT (from_user_id, to_user_id) DO UPDATE SET
       intent = EXCLUDED.intent, message = EXCLUDED.message, score = EXCLUDED.score,
       status = 'pending', created_at = CURRENT_TIMESTAMP, responded_at = NULL
     WHERE buddy_connections.status = 'cancelled'
     RETURNING *`,
    [meId, otherId, body.intent, message || null, scored ? scored.match.score : null]
  );
  let conn = ins.rows[0];
  if (conn) await notifyRequest(otherId, conn, buddyName(me));
  else conn = (await connectionsBetween(meId, otherId)).find((c) => Number(c.from_user_id) === meId);
  res.json({ connection: connectionView(conn, meId) });
}));

async function ownConnection(req) {
  const id = toInt(req.params.id || req.params.connectionId);
  if (!id) throw bad('Invalid connection');
  const r = await db.query('/*q:connectionById*/ SELECT * FROM buddy_connections WHERE id = $1', [id]);
  const c = r.rows[0];
  const meId = req.user.userId;
  if (!c || (Number(c.from_user_id) !== meId && Number(c.to_user_id) !== meId)) throw new HttpError(404, 'Request not found', 'NOT_FOUND');
  const otherId = Number(c.from_user_id) === meId ? Number(c.to_user_id) : Number(c.from_user_id);
  return { c, meId, otherId };
}

function respond(action) {
  return wrap(async (req, res) => {
    const { c, meId, otherId } = await ownConnection(req);
    const incoming = Number(c.to_user_id) === meId;
    let updated = null;
    if (action === 'accept' || action === 'decline') {
      if (!incoming) throw new HttpError(403, 'Only the person who received this request can answer it', 'FORBIDDEN');
      if (c.status !== 'pending') throw new HttpError(409, 'This request is no longer pending', 'NOT_PENDING');
      if (action === 'accept' && (await blockedPair(meId, otherId) || await bannedEither(meId, otherId))) {
        throw new HttpError(404, 'Request not found', 'NOT_FOUND');
      }
      updated = await setStatus(c.id, 'pending', action === 'accept' ? 'accepted' : 'declined');
    } else {
      // cancel: the sender withdraws a pending request; either person can end an accepted connection
      if (c.status === 'pending' && !incoming) updated = await setStatus(c.id, 'pending', 'cancelled');
      else if (c.status === 'accepted') updated = await setStatus(c.id, 'accepted', 'cancelled');
      else if (c.status === 'pending') throw new HttpError(403, 'Only the sender can cancel this request', 'FORBIDDEN');
      else throw new HttpError(409, 'This request is no longer active', 'NOT_PENDING');
    }
    if (!updated) throw new HttpError(409, 'This request was just updated. Please refresh.', 'NOT_PENDING');
    if (action === 'accept') await notifyAccepted(otherId, updated, await nameOf(meId));
    res.json({ connection: connectionView(updated, meId) });
  });
}
router.post('/connections/:id/accept', registered, respond('accept'));
router.post('/connections/:id/decline', registered, respond('decline'));
router.post('/connections/:id/cancel', registered, respond('cancel'));

// GET /api/buddy/connections
router.get('/connections', registered, wrap(async (req, res) => {
  const meId = req.user.userId;
  const r = await db.query(
    `/*q:connectionList*/ SELECT c.id, c.from_user_id, c.to_user_id, c.intent, c.message, c.status, c.score, c.created_at, c.responded_at,
       ou.id AS other_id, ou.full_name AS other_full_name, obp.display_name AS other_display_name,
       obp.city AS other_city, obp.photo_url AS other_photo_url, obd.date_of_birth AS other_dob,
       obp.verified_at AS other_verified_at, obp.phone_verified_at AS other_phone_verified_at,
       lm.body AS last_body, lm.created_at AS last_created_at, lm.sender_id AS last_sender_id,
       (SELECT COUNT(*) FROM buddy_messages um WHERE um.connection_id = c.id AND um.sender_id <> $1 AND um.read_at IS NULL) AS unread
     FROM buddy_connections c
     JOIN users ou ON ou.id = CASE WHEN c.from_user_id = $1 THEN c.to_user_id ELSE c.from_user_id END
     LEFT JOIN buddy_profiles obp ON obp.user_id = ou.id
     LEFT JOIN birth_details obd ON obd.user_id = ou.id
     LEFT JOIN LATERAL (
       SELECT m.body, m.created_at, m.sender_id FROM buddy_messages m WHERE m.connection_id = c.id ORDER BY m.id DESC LIMIT 1
     ) lm ON TRUE
     WHERE (c.from_user_id = $1 OR c.to_user_id = $1)
       AND c.status IN ('pending', 'accepted')
       AND obp.banned_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM buddy_blocks b
         WHERE (b.user_id = $1 AND b.blocked_user_id = ou.id) OR (b.user_id = ou.id AND b.blocked_user_id = $1)
       )
     ORDER BY COALESCE(lm.created_at, c.responded_at, c.created_at) DESC
     LIMIT 300`,
    [meId]
  );
  const today = todayIST();
  const out = { incoming: [], outgoing: [], buddies: [] };
  for (const c of r.rows) {
    const conn = {
      id: Number(c.id),
      intent: c.intent,
      status: c.status,
      message: c.message || null,
      createdAt: iso(c.created_at),
      other: {
        userId: Number(c.other_id),
        displayName: c.other_display_name || firstName(c.other_full_name) || 'Buddy',
        age: M.ageOn(isoDate(c.other_dob), today),
        city: c.other_city || null,
        photoUrl: c.other_photo_url || null,
        score: c.score === null || c.score === undefined ? null : Number(c.score),
        verified: !!c.other_verified_at,
        phoneVerified: !!c.other_phone_verified_at
      },
      unread: Number(c.unread) || 0
    };
    if (c.last_body !== null && c.last_body !== undefined) {
      conn.lastMessage = { body: c.last_body, createdAt: iso(c.last_created_at), mine: Number(c.last_sender_id) === meId };
    }
    if (c.status === 'accepted') out.buddies.push(conn);
    else if (Number(c.to_user_id) === meId) out.incoming.push(conn);
    else out.outgoing.push(conn);
  }
  res.json(out);
}));

// ---------------------------------------------------------------------------
// Chat (accepted connections only, never across a block)
// ---------------------------------------------------------------------------

async function chatConnection(req) {
  const { c, meId, otherId } = await ownConnection(req);
  if (c.status !== 'accepted') throw new HttpError(403, 'You can chat once the request is accepted', 'NOT_ACCEPTED');
  if (await blockedPair(meId, otherId)) throw new HttpError(403, 'This chat is not available', 'BLOCKED');
  if (await bannedEither(meId, otherId)) throw new HttpError(403, 'This chat is not available', 'BANNED');
  return { c, meId, otherId };
}
const messageView = (m, meId) => ({ id: Number(m.id), body: m.body, createdAt: iso(m.created_at), mine: Number(m.sender_id) === meId });

// GET /api/buddy/chat/:connectionId?after=<messageId>
router.get('/chat/:connectionId', registered, wrap(async (req, res) => {
  const { c, meId } = await chatConnection(req);
  const after = req.query.after === undefined || req.query.after === '' ? null : Number(req.query.after);
  if (after !== null && !(Number.isInteger(after) && after >= 0 && after <= MAX_INT)) throw bad('Invalid message id');
  let rows;
  if (after !== null) {
    rows = (await db.query(
      '/*q:messagesAfter*/ SELECT id, sender_id, body, created_at FROM buddy_messages WHERE connection_id = $1 AND id > $2 ORDER BY id ASC LIMIT 200',
      [c.id, after]
    )).rows;
  } else {
    rows = (await db.query(
      '/*q:recentMessages*/ SELECT id, sender_id, body, created_at FROM buddy_messages WHERE connection_id = $1 ORDER BY id DESC LIMIT 100',
      [c.id]
    )).rows.reverse();
  }
  await db.query(
    '/*q:markRead*/ UPDATE buddy_messages SET read_at = CURRENT_TIMESTAMP WHERE connection_id = $1 AND sender_id <> $2 AND read_at IS NULL',
    [c.id, meId]
  );
  res.json({ messages: rows.map((m) => messageView(m, meId)), connection: connectionView(c, meId) });
}));

// POST /api/buddy/chat/:connectionId {body}
router.post('/chat/:connectionId', registered, wrap(async (req, res) => {
  const text = typeof (req.body || {}).body === 'string' ? req.body.body.trim() : '';
  if (text.length < 1 || text.length > 2000) throw bad('Message must be 1 to 2000 characters');
  const { c, meId, otherId } = await chatConnection(req);
  const recent = await countSince('recentSent',
    "SELECT COUNT(*) AS n FROM buddy_messages WHERE sender_id = $1 AND created_at > NOW() - INTERVAL '1 minute'", [meId]);
  if (recent >= MESSAGES_PER_MINUTE) throw new HttpError(429, 'You are sending messages too fast. Please wait a moment.', 'RATE_LIMITED');
  const r = await db.query(
    '/*q:insertMessage*/ INSERT INTO buddy_messages (connection_id, sender_id, body) VALUES ($1, $2, $3) RETURNING id, sender_id, body, created_at',
    [c.id, meId, text]
  );
  // chatConnection already refused blocked / banned pairs, so this never reaches a blocker.
  await notifyMessage(otherId, Number(c.id), await nameOf(meId), text);
  res.json({ message: messageView(r.rows[0], meId) });
}));

// ---------------------------------------------------------------------------
// Safety
// ---------------------------------------------------------------------------

async function blockUser(meId, otherId) {
  const u = await db.query('/*q:userExists*/ SELECT id FROM users WHERE id = $1', [otherId]);
  if (!u.rows.length) throw new HttpError(404, 'User not found', 'NOT_FOUND');
  await db.query('/*q:block*/ INSERT INTO buddy_blocks (user_id, blocked_user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [meId, otherId]);
}

// POST /api/buddy/block {userId}
router.post('/block', registered, wrap(async (req, res) => {
  const otherId = toInt((req.body || {}).userId);
  if (!otherId || otherId === req.user.userId) throw bad('Invalid user');
  await blockUser(req.user.userId, otherId);
  res.json({ ok: true });
}));

// POST /api/buddy/report {userId, reason, details?} (also blocks)
router.post('/report', registered, wrap(async (req, res) => {
  const body = req.body || {};
  const otherId = toInt(body.userId);
  if (!otherId || otherId === req.user.userId) throw bad('Invalid user');
  if (!REPORT_REASONS.includes(body.reason)) throw bad('Choose a reason for the report');
  const details = body.details === undefined || body.details === null ? null : String(body.details).trim().slice(0, 1000) || null;
  // Blocking always happens (safety first); past the daily limit the report itself is not stored again.
  await blockUser(req.user.userId, otherId);
  const reportsToday = await countSince('recentReports',
    "SELECT COUNT(*) AS n FROM buddy_reports WHERE reporter_id = $1 AND created_at > NOW() - INTERVAL '1 day'", [req.user.userId]);
  if (reportsToday >= REPORTS_PER_DAY) return res.json({ ok: true });
  await db.query(
    '/*q:report*/ INSERT INTO buddy_reports (reporter_id, reported_user_id, reason, details) VALUES ($1, $2, $3, $4)',
    [req.user.userId, otherId, body.reason, details]
  );
  res.json({ ok: true });
}));

// ---------------------------------------------------------------------------
// v3 trust: verified badge (selfie + gesture, reviewed in routes/admin_trust.js), phone check,
// biodata. Selfies are never shown to other users and are deleted when an admin decides.
// ---------------------------------------------------------------------------

/** Me with a buddy profile that is not banned (paused is fine). */
async function requireProfileMe(userId) {
  const me = await loadMe(userId);
  if (!me) throw new HttpError(401, 'Please log in to use Buddies', 'LOGIN_REQUIRED');
  const el = eligibility(me);
  if (!el.eligible) throw new HttpError(403, el.reason === 'UNDER_18' ? 'Buddies is for people aged 18 and over' : 'Create your Kundli first to use Buddies', el.reason);
  if (!me.bp_user_id) throw new HttpError(409, 'Set up your buddy profile first', 'NO_PROFILE');
  if (isBanned(me)) throw new HttpError(403, BANNED_MSG, 'BANNED');
  return me;
}

const verificationRowView = (v) => (v ? {
  id: Number(v.id),
  gesture: v.gesture,
  status: v.status,
  reason: v.reason || null,
  createdAt: iso(v.created_at),
  decidedAt: iso(v.decided_at)
} : null);

async function verificationState(me) {
  const uid = Number(me.user_id);
  const [latestR, today] = await Promise.all([
    db.query('/*q:verificationLatest*/ SELECT id, gesture, status, reason, created_at, decided_at FROM buddy_verifications WHERE user_id = $1 ORDER BY id DESC LIMIT 1', [uid]),
    countSince('verificationsToday', "SELECT COUNT(*) AS n FROM buddy_verifications WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 day'", [uid])
  ]);
  const latest = verificationRowView(latestR.rows[0]);
  const verified = isVerified(me);
  return {
    status: verified ? 'verified' : latest && ['pending', 'rejected'].includes(latest.status) ? latest.status : 'none',
    verified,
    verifiedAt: verified ? iso(me.verified_at) : null,
    phoneVerified: isPhoneVerified(me),
    phoneAvailable: FA.available(),
    latest,
    submissionsToday: today,
    dailyLimit: T.VERIFICATIONS_PER_DAY,
    gestures: T.GESTURES
  };
}

// GET /api/buddy/verification
router.get('/verification', registered, wrap(async (req, res) => {
  res.json(await verificationState(await requireProfileMe(req.user.userId)));
}));

// POST /api/buddy/verification {gesture, imageBase64}
router.post('/verification', registered, wrap(async (req, res) => {
  const body = req.body || {};
  const gesture = typeof body.gesture === 'string' ? body.gesture.trim() : '';
  if (!T.GESTURES.includes(gesture)) throw bad('Unknown gesture. Please start again.', 'BAD_GESTURE');
  let selfie;
  try { selfie = T.cleanSelfie(body.imageBase64); } catch (e) { throw bad(e.message, 'BAD_IMAGE'); }
  const me = await requireProfileMe(req.user.userId);
  const uid = Number(me.user_id);
  if (isVerified(me)) throw new HttpError(409, 'You are already verified', 'ALREADY_VERIFIED');
  const pending = await db.query("/*q:verificationPending*/ SELECT id FROM buddy_verifications WHERE user_id = $1 AND status = 'pending' LIMIT 1", [uid]);
  if (pending.rows.length) throw new HttpError(409, 'Your selfie is already being reviewed', 'PENDING');
  const today = await countSince('verificationsToday', "SELECT COUNT(*) AS n FROM buddy_verifications WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 day'", [uid]);
  if (today >= T.VERIFICATIONS_PER_DAY) {
    throw new HttpError(429, `You can send ${T.VERIFICATIONS_PER_DAY} selfies a day. Please try again tomorrow.`, 'RATE_LIMITED');
  }
  try {
    await db.query(
      "/*q:verificationInsert*/ INSERT INTO buddy_verifications (user_id, gesture, selfie, status) VALUES ($1, $2, $3, 'pending')",
      [uid, gesture, selfie.base64]
    );
  } catch (err) {
    // uniq_buddy_verification_pending: a second device submitted at the same moment
    if (err && err.code === '23505') throw new HttpError(409, 'Your selfie is already being reviewed', 'PENDING');
    throw err;
  }
  res.json(await verificationState(me));
}));

// POST /api/buddy/verification/phone {idToken}: Firebase phone sign-in ID token.
// Stores phone_verified_at and a hash of the number (never the number itself).
router.post('/verification/phone', registered, wrap(async (req, res) => {
  const idToken = (req.body || {}).idToken;
  if (typeof idToken !== 'string' || idToken.length < 20 || idToken.length > 8000) throw bad('Missing phone confirmation');
  const me = await requireProfileMe(req.user.userId);
  const uid = Number(me.user_id);
  let phone;
  try {
    phone = await FA.phoneFromIdToken(idToken);
  } catch (e) {
    if (e.code === 'UNAVAILABLE') throw new HttpError(503, e.message, 'PHONE_UNAVAILABLE');
    throw bad(e.message, e.code || 'BAD_TOKEN');
  }
  const hash = T.phoneHash(phone);
  phone = null; // never kept past this point
  await db.withTransaction(async (client) => {
    const owner = await client.query('/*q:phoneOwner*/ SELECT user_id FROM phone_verifications WHERE phone_hash = $1 FOR UPDATE', [hash]);
    const ownerId = owner.rows[0] ? Number(owner.rows[0].user_id) : null;
    if (ownerId !== null && ownerId !== uid) {
      throw new HttpError(409, 'This phone number has already verified another account', 'PHONE_IN_USE');
    }
    if (ownerId === null) {
      await client.query('/*q:phoneClearMine*/ DELETE FROM phone_verifications WHERE user_id = $1', [uid]);
      const ins = await client.query(
        '/*q:phoneInsert*/ INSERT INTO phone_verifications (phone_hash, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING user_id',
        [hash, uid]
      );
      if (!ins.rows.length) throw new HttpError(409, 'This phone number has already verified another account', 'PHONE_IN_USE');
    }
    await client.query(
      '/*q:phoneVerified*/ UPDATE buddy_profiles SET phone_verified_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND banned_at IS NULL',
      [uid]
    );
  });
  res.json(await verificationState(await loadMe(uid)));
}));

// GET /api/buddy/biodata -> my own biodata (all fields)
router.get('/biodata', registered, wrap(async (req, res) => {
  const me = await requireProfileMe(req.user.userId);
  res.json({ biodata: T.biodataView(me.biodata) });
}));

// PUT /api/buddy/biodata {biodata: {...}} (replaces the whole biodata; empty fields are dropped)
router.put('/biodata', registered, wrap(async (req, res) => {
  const body = req.body || {};
  const input = body.biodata !== undefined ? body.biodata : body;
  let biodata;
  try { biodata = T.validateBiodata(input); } catch (e) { throw bad(e.message, 'INVALID_BIODATA'); }
  const me = await requireProfileMe(req.user.userId);
  const r = await db.query(
    `/*q:biodataSave*/ UPDATE buddy_profiles SET biodata = $2::jsonb, updated_at = CURRENT_TIMESTAMP
     WHERE user_id = $1 AND banned_at IS NULL RETURNING biodata`,
    [me.user_id, JSON.stringify(biodata)]
  );
  if (!r.rows.length) throw new HttpError(403, BANNED_MSG, 'BANNED');
  res.json({ biodata: T.biodataView(r.rows[0].biodata) });
}));

module.exports = router;
// Exposed for unit tests and routes/family.js.
module.exports._internal = {
  INTENT_LABELS, eligibility, validateProfile, adultCutoff, primaryConnection, categoryOf, toInt,
  MESSAGES_PER_MINUTE, REQUESTS_PER_DAY, REPORTS_PER_DAY, VERIFIED_RANK_BOOST, PHONE_RANK_BOOST,
  loadMe, loadPerson, scoreRows, blockedPair, connectionsBetween, isBanned, isVerified, isPhoneVerified,
  firstName, isoDate, todayIST, intentLabel, buddyName
};
