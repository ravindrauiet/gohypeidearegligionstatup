// Satsang meetups (/api/meetups): small group events at public places (temples, ghats, halls).
// Group events are a safer first meeting than one-to-one, so this is where strangers meet.
//
// - Admins create official events (approved immediately) through `adminRouter` (mounted by
//   routes/admin.js at /api/admin/meetups behind x-admin-key). Verified users
//   (buddy_profiles.verified_at) can propose an event: it stays `pending` until an admin approves.
// - Venue coordinates are public places, but they still never leave the server: clients get the
//   venue's public address and an integer distance only.
// - Attendee previews (display name + initials + verified only) are shown to people who are going.
// - Check-in (+100 coins once, reason meetup_checkin, ref event:<id>) needs the venue within 300 m,
//   or the host's 6-digit code, from 30 minutes before the start until the end.
// Every SQL statement starts with a /*q:name*/ tag (the fake db in test/meetups.test.js uses it).
const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const C = require('../services/coins_service');
const M = require('../services/buddy_matching');
const push = require('../services/push_service');
const TEMPLES = require('../data/temples.json');

const router = express.Router();
const adminRouter = express.Router();

const TYPES = ['aarti', 'bhajan_sandhya', 'seva', 'yoga', 'satsang', 'kirtan', 'other'];
const STATUSES = ['pending', 'approved', 'rejected', 'cancelled', 'completed'];
const TEMPLE_BY_ID = new Map(TEMPLES.map((t) => [t.id, t]));
const MIN_AGE = 18;
const MIN_CAPACITY = 5;
const MAX_CAPACITY = 50;
const DEFAULT_RADIUS_KM = 25;
const MAX_RADIUS_KM = 100;
const LIST_POOL = 300;
const LIST_MAX = 100;
const PREVIEW_MAX = 5;
const CHECKIN_EARLY_MS = 30 * 60 * 1000;
const CHECKIN_RADIUS_M = 300;
const CHECKIN_COINS = C.MEETUP_CHECKIN_COINS || 100;
const CHECKIN_REASON = C.MEETUP_CHECKIN_REASON || 'meetup_checkin';
const MAX_CODE_ATTEMPTS = 5;
const PROPOSALS_PER_WEEK = 2;
const PROPOSAL_MIN_LEAD_MS = 12 * 3600 * 1000; // time for an admin to review
const MAX_AHEAD_MS = 90 * 24 * 3600 * 1000;
const MIN_DURATION_MS = 15 * 60 * 1000;
const MAX_DURATION_MS = 12 * 3600 * 1000;
const MAX_INT = 2147483647;
const IST = 'Asia/Kolkata';
const GOING = ['going', 'checked_in'];

// Clock (tests move it).
let clock = () => Date.now();
const nowMs = () => clock();

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
    res.json(await fn(req, res));
  } catch (err) {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message, code: err.code });
    console.error('Meetups route error:', err);
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
};

function requireRegistered(req, res, next) {
  if (!req.user || req.user.role === 'guest') {
    return res.status(401).json({ error: 'Please log in to join meetups', code: 'LOGIN_REQUIRED' });
  }
  return next();
}
const registered = [optionalAuthenticateToken, requireRegistered];

function toInt(v) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 && n <= MAX_INT ? n : null;
}
function iso(v) {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}
const ms = (v) => (v instanceof Date ? v.getTime() : new Date(v).getTime());
const cleanText = (v, max) => String(v === undefined || v === null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max);
const num = (v) => (v === null || v === undefined || v === '' ? NaN : Number(v));
const firstName = (full) => (String(full || '').trim().split(/\s+/)[0] || '').slice(0, 40);
const nameOf = (displayName, fullName) => cleanText(displayName, 40) || firstName(fullName) || 'Member';
function initials(name) {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  const s = parts.slice(0, 2).map((p) => p[0]).join('').toUpperCase();
  return s || '?';
}
function isoDate(v) {
  if (!v) return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.toISOString().slice(0, 10);
  return String(v).slice(0, 10);
}
function istDateTime(v) {
  try {
    return new Intl.DateTimeFormat('en-IN', {
      timeZone: IST, weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit',
    }).format(new Date(v));
  } catch (_) { return iso(v) || ''; }
}
const metersBetween = (aLat, aLng, bLat, bLng) => {
  const km = M.haversineKm(aLat, aLng, bLat, bLng);
  return km === null ? null : km * 1000;
};
const newCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');
function codesMatch(given, expected) {
  const a = crypto.createHash('sha256').update(String(given)).digest();
  const b = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(a, b);
}

// buddy_profiles.verified_at is added by the trust feature. Until that column exists the queries
// fall back to NULL (nobody verified) instead of failing.
let hasVerifiedCol = true;
async function vquery(tag, build, params, client = db) {
  const run = () => client.query(`/*q:${tag}*/ ${build((alias) => (hasVerifiedCol ? `${alias}.verified_at` : 'NULL::timestamptz'))}`, params);
  try {
    return await run();
  } catch (err) {
    if (hasVerifiedCol && err && err.code === '42703' && /verified_at/.test(String(err.message))) {
      hasVerifiedCol = false;
      return run();
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Viewer (who is asking)
// ---------------------------------------------------------------------------
async function loadViewer(userId) {
  if (!userId) return null;
  const r = await vquery('mtViewer', (v) => `SELECT u.id, u.role, u.full_name, u.gender AS user_gender,
       bd.date_of_birth, bd.gender AS birth_gender,
       bp.user_id AS bp_user_id, bp.display_name, bp.gender, bp.city, bp.lat, bp.lng, bp.banned_at, ${v('bp')} AS verified_at
     FROM users u
     LEFT JOIN birth_details bd ON bd.user_id = u.id
     LEFT JOIN buddy_profiles bp ON bp.user_id = u.id
     WHERE u.id = $1`, [userId]);
  const row = r.rows[0];
  if (!row) return null;
  const today = C.istDate(new Date(nowMs()));
  return {
    id: Number(row.id),
    guest: row.role === 'guest',
    name: nameOf(row.display_name, row.full_name),
    gender: M.normalizeGender(row.gender || row.birth_gender || row.user_gender),
    age: M.ageOn(isoDate(row.date_of_birth), today),
    hasBirthDate: !!row.date_of_birth,
    banned: !!row.banned_at,
    verified: !!row.verified_at,
    city: row.city || null,
    lat: row.lat === null || row.lat === undefined ? null : Number(row.lat),
    lng: row.lng === null || row.lng === undefined ? null : Number(row.lng),
  };
}
const viewerFor = (req) => (req.user && req.user.role !== 'guest' ? loadViewer(req.user.userId) : Promise.resolve(null));

function requireAdult(viewer) {
  if (!viewer) throw new HttpError(401, 'Please log in to join meetups', 'LOGIN_REQUIRED');
  if (viewer.banned) throw new HttpError(403, 'Your account cannot join meetups after a safety review', 'BANNED');
  if (!viewer.hasBirthDate) throw new HttpError(403, 'Add your birth details first. Meetups are for people aged 18 and over.', 'NO_BIRTH_DETAILS');
  if (viewer.age === null || viewer.age < MIN_AGE) throw new HttpError(403, 'Meetups are for people aged 18 and over', 'UNDER_18');
}

/** Ids I blocked or who blocked me. */
async function blockedIds(meId) {
  if (!meId) return new Set();
  const r = await db.query('/*q:mtBlocks*/ SELECT user_id, blocked_user_id FROM buddy_blocks WHERE user_id = $1 OR blocked_user_id = $1', [meId]);
  const out = new Set();
  for (const b of r.rows) out.add(Number(b.user_id) === meId ? Number(b.blocked_user_id) : Number(b.user_id));
  return out;
}

// ---------------------------------------------------------------------------
// Meetup rows and views
// ---------------------------------------------------------------------------
const MEETUP_COLS = (v) => `m.id, m.title, m.type, m.description, m.venue_name, m.temple_id, m.address, m.lat, m.lng, m.city,
  m.starts_at, m.ends_at, m.capacity, m.women_only, m.host_user_id, m.status, m.checkin_code, m.admin_note,
  m.created_at, m.updated_at,
  (SELECT COUNT(*) FROM meetup_rsvps r WHERE r.meetup_id = m.id AND r.status IN ('going', 'checked_in')) AS going_count,
  (SELECT COUNT(*) FROM meetup_rsvps r WHERE r.meetup_id = m.id AND r.status = 'checked_in') AS checked_in_count,
  hu.full_name AS host_full_name, hu.email AS host_email, hbp.display_name AS host_display_name,
  hbp.banned_at AS host_banned_at, ${v('hbp')} AS host_verified_at`;
const MEETUP_FROM = `FROM meetups m
  LEFT JOIN users hu ON hu.id = m.host_user_id
  LEFT JOIN buddy_profiles hbp ON hbp.user_id = m.host_user_id`;

async function loadMeetup(id) {
  const r = await vquery('mtGet', (v) => `SELECT ${MEETUP_COLS(v)} ${MEETUP_FROM} WHERE m.id = $1`, [id]);
  return r.rows[0] || null;
}

async function myRsvps(meId, ids) {
  const map = new Map();
  if (!meId || !ids.length) return map;
  const r = await db.query(
    '/*q:mtMyRsvps*/ SELECT meetup_id, status, checked_in_at FROM meetup_rsvps WHERE user_id = $1 AND meetup_id = ANY($2::int[])',
    [meId, ids]
  );
  for (const x of r.rows) map.set(Number(x.meetup_id), x);
  return map;
}

/** Going + checked-in attendees of the given events (oldest RSVP first). */
async function attendeesOf(ids) {
  const map = new Map(ids.map((id) => [Number(id), []]));
  if (!ids.length) return map;
  const r = await vquery('mtAttendees', (v) => `SELECT r.meetup_id, r.user_id, r.status, u.full_name, bp.display_name,
       bp.banned_at, bp.is_active, bp.user_id AS bp_user_id, ${v('bp')} AS verified_at
     FROM meetup_rsvps r
     JOIN users u ON u.id = r.user_id
     LEFT JOIN buddy_profiles bp ON bp.user_id = r.user_id
     WHERE r.meetup_id = ANY($1::int[]) AND r.status IN ('going', 'checked_in')
     ORDER BY r.created_at ASC`, [ids]);
  for (const a of r.rows) {
    const list = map.get(Number(a.meetup_id));
    if (list) list.push(a);
  }
  return map;
}

const phaseOf = (m, t = nowMs()) => (t < ms(m.starts_at) ? 'upcoming' : t <= ms(m.ends_at) ? 'live' : 'ended');
const checkinOpen = (m, t = nowMs()) => t >= ms(m.starts_at) - CHECKIN_EARLY_MS && t <= ms(m.ends_at);

/** Whether `viewer` may see this event at all. */
function canSee(m, viewer, blocked, rsvp) {
  const hostId = m.host_user_id === null || m.host_user_id === undefined ? null : Number(m.host_user_id);
  const isHost = !!viewer && hostId === viewer.id;
  if (isHost) return true;
  if (m.status === 'pending' || m.status === 'rejected') return false;
  if (hostId && blocked.has(hostId)) return false;
  if (rsvp) return true; // people who RSVP'd keep seeing it (e.g. "cancelled")
  if (m.status !== 'approved' && m.status !== 'completed') return false;
  if (m.women_only && (!viewer || viewer.gender !== 'female')) return false;
  if (hostId && m.host_banned_at) return false;
  return true;
}

function hostView(m) {
  if (m.host_user_id === null || m.host_user_id === undefined) return null;
  return { displayName: nameOf(m.host_display_name, m.host_full_name), verified: !!m.host_verified_at };
}

function personPreview(a) {
  const name = nameOf(a.display_name, a.full_name);
  return { displayName: name, initials: initials(name), verified: !!a.verified_at };
}

/** Attendees safe to show `viewer`: not me, not blocked either way, not banned. */
function visibleAttendees(list, viewer, blocked) {
  return (list || []).filter((a) => Number(a.user_id) !== viewer.id && !blocked.has(Number(a.user_id)) && !a.banned_at);
}

function mapsUrl(m) {
  const q = [m.venue_name, m.address, m.city].filter(Boolean).join(', ');
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}

function meetupView(m, { viewer = null, rsvp = null, origin = null, attendees = null, blocked = new Set(), detail = false } = {}) {
  const going = Number(m.going_count) || 0;
  const capacity = Number(m.capacity) || 0;
  const myStatus = rsvp ? rsvp.status : null;
  const amGoing = !!myStatus && GOING.includes(myStatus);
  const isHost = !!viewer && m.host_user_id !== null && m.host_user_id !== undefined && Number(m.host_user_id) === viewer.id;
  let distanceKm = null;
  if (origin) distanceKm = M.displayKm(M.haversineKm(origin.lat, origin.lng, num(m.lat), num(m.lng)));
  const out = {
    id: Number(m.id),
    title: m.title,
    type: m.type,
    status: m.status,
    phase: phaseOf(m),
    venueName: m.venue_name,
    templeId: m.temple_id || null,
    city: m.city || null,
    address: m.address || '',
    startsAt: iso(m.starts_at),
    endsAt: iso(m.ends_at),
    distanceKm,
    capacity,
    goingCount: going,
    spotsLeft: Math.max(0, capacity - going),
    womenOnly: !!m.women_only,
    official: m.host_user_id === null || m.host_user_id === undefined,
    host: hostView(m),
    isHost,
    myStatus,
    attendees: null,
  };
  const canSeePeople = !!viewer && !viewer.banned && (amGoing || isHost);
  if (canSeePeople && attendees) {
    out.attendees = visibleAttendees(attendees, viewer, blocked).slice(0, PREVIEW_MAX).map(personPreview);
  }
  if (detail) {
    out.description = m.description || '';
    out.mapsUrl = mapsUrl(m);
    out.checkinOpensAt = new Date(ms(m.starts_at) - CHECKIN_EARLY_MS).toISOString();
    out.checkinOpen = m.status === 'approved' && checkinOpen(m);
    out.checkedInAt = rsvp && rsvp.checked_in_at ? iso(rsvp.checked_in_at) : null;
    out.coinsForCheckin = CHECKIN_COINS;
    if (isHost) {
      out.checkinCode = m.checkin_code;
      out.checkedInCount = Number(m.checked_in_count) || 0;
      out.adminNote = m.admin_note || null;
    }
    // After checking in: the other checked-in attendees ("People you met").
    if (viewer && !viewer.banned && myStatus === 'checked_in' && attendees) {
      out.peopleYouMet = visibleAttendees(attendees, viewer, blocked)
        .filter((a) => a.status === 'checked_in')
        .map((a) => ({ userId: Number(a.user_id), ...personPreview(a), canConnect: !!a.bp_user_id && a.is_active !== false }));
    }
  }
  return out;
}

async function detailFor(id, viewer) {
  const m = await loadMeetup(id);
  if (!m) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const [blocked, rsvps] = await Promise.all([blockedIds(viewer && viewer.id), myRsvps(viewer && viewer.id, [Number(m.id)])]);
  const rsvp = rsvps.get(Number(m.id)) || null;
  if (!canSee(m, viewer, blocked, rsvp)) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const isHost = !!viewer && Number(m.host_user_id) === viewer.id;
  const needPeople = !!viewer && !viewer.banned && ((rsvp && GOING.includes(rsvp.status)) || isHost);
  const attendees = needPeople ? (await attendeesOf([Number(m.id)])).get(Number(m.id)) : null;
  const origin = viewer && viewer.lat !== null && viewer.lng !== null ? { lat: viewer.lat, lng: viewer.lng } : null;
  return { m, rsvp, blocked, view: meetupView(m, { viewer, rsvp, origin, attendees, blocked, detail: true }) };
}

// ---------------------------------------------------------------------------
// Validation (shared by proposals and admin-created events)
// ---------------------------------------------------------------------------
function validateMeetup(body, { admin = false, viewer = null } = {}) {
  const b = body || {};
  const type = typeof b.type === 'string' ? b.type.trim() : '';
  if (!TYPES.includes(type)) throw bad(`type must be one of: ${TYPES.join(', ')}`);
  const title = cleanText(b.title, 200);
  if (title.length < 4 || title.length > 80) throw bad('Title must be 4 to 80 characters');
  const description = String(b.description === undefined || b.description === null ? '' : b.description).trim();
  if (description.length > 1000) throw bad('Description can be at most 1000 characters');

  let templeId = null;
  let venueName = cleanText(b.venueName, 200);
  let address = cleanText(b.address, 400);
  let city = cleanText(b.city, 200);
  let lat = num(b.lat);
  let lng = num(b.lng);
  if (b.templeId !== undefined && b.templeId !== null && b.templeId !== '') {
    const t = TEMPLE_BY_ID.get(String(b.templeId));
    if (!t) throw bad('Unknown temple');
    templeId = t.id;
    venueName = venueName || t.name;
    city = city || t.city;
    address = address || [t.name, t.city, t.state].filter(Boolean).join(', ');
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) { lat = t.lat; lng = t.lng; }
  }
  if (venueName.length < 2 || venueName.length > 120) throw bad('Venue name must be 2 to 120 characters');
  if (address.length < 5 || address.length > 300) throw bad('Add the venue address (5 to 300 characters)');
  if (city.length < 2 || city.length > 80) throw bad('City must be 2 to 80 characters');
  if (!M.validLatLng(lat, lng) || (lat === 0 && lng === 0)) throw bad('A valid venue location is required');

  const start = Date.parse(b.startsAt);
  const end = Date.parse(b.endsAt);
  if (!Number.isFinite(start) || !Number.isFinite(end)) throw bad('Start and end times are required');
  const t = nowMs();
  const lead = admin ? 0 : PROPOSAL_MIN_LEAD_MS;
  if (start < t + lead) {
    throw bad(admin ? 'The event must start in the future' : 'Propose events at least 12 hours ahead so our team can review them', 'TOO_SOON');
  }
  if (start > t + MAX_AHEAD_MS) throw bad('Events can be at most 90 days ahead');
  if (end - start < MIN_DURATION_MS || end - start > MAX_DURATION_MS) throw bad('Events must last between 15 minutes and 12 hours');

  const capacity = Number(b.capacity);
  if (!Number.isInteger(capacity) || capacity < MIN_CAPACITY || capacity > MAX_CAPACITY) {
    throw bad(`Capacity must be between ${MIN_CAPACITY} and ${MAX_CAPACITY}`);
  }
  if (b.womenOnly !== undefined && b.womenOnly !== null && typeof b.womenOnly !== 'boolean') throw bad('womenOnly must be true or false');
  const womenOnly = b.womenOnly === true;
  if (womenOnly && !admin && (!viewer || viewer.gender !== 'female')) {
    throw new HttpError(403, 'Only women can host a women-only event', 'WOMEN_ONLY');
  }
  return {
    type, title, description, templeId, venueName, address, city,
    lat: Math.round(lat * 1e6) / 1e6, lng: Math.round(lng * 1e6) / 1e6,
    startsAt: new Date(start).toISOString(), endsAt: new Date(end).toISOString(), capacity, womenOnly,
  };
}

async function insertMeetup(v, hostUserId, status) {
  const r = await db.query(
    `/*q:mtInsert*/ INSERT INTO meetups
       (title, type, description, venue_name, temple_id, address, lat, lng, city, starts_at, ends_at,
        capacity, women_only, host_user_id, status, checkin_code)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
     RETURNING id`,
    [v.title, v.type, v.description, v.venueName, v.templeId, v.address, v.lat, v.lng, v.city, v.startsAt, v.endsAt,
      v.capacity, v.womenOnly, hostUserId, status, newCode()]
  );
  return Number(r.rows[0].id);
}

// ---------------------------------------------------------------------------
// Notifications (push_service never throws). Pref: 'buddy' (meetups are part of the buddy space).
// ---------------------------------------------------------------------------
const NOTIFY_TEXT = {
  rsvp_confirmed: (m) => ({ title: "You're going!", body: `${m.title} · ${istDateTime(m.starts_at)} at ${m.venue_name}` }),
  approved: (m) => ({ title: 'Your meetup is approved', body: `${m.title} is now open for RSVPs.` }),
  rejected: (m) => ({ title: 'Meetup not approved', body: `${m.title} could not be approved this time.` }),
  cancelled: (m) => ({ title: 'Meetup cancelled', body: `${m.title} (${istDateTime(m.starts_at)}) has been cancelled.` }),
};
function notify(userId, m, kind) {
  const t = NOTIFY_TEXT[kind](m);
  return push.sendToUser(userId, {
    type: 'meetup_update',
    title: t.title,
    body: t.body,
    data: { meetupId: Number(m.id), kind },
  }, { pref: 'buddy' });
}
async function notifyAttendees(m, kind, exceptUserId = null) {
  const r = await db.query(
    "/*q:mtGoingUsers*/ SELECT user_id FROM meetup_rsvps WHERE meetup_id = $1 AND status IN ('going', 'checked_in')",
    [m.id]
  );
  const ids = [...new Set(r.rows.map((x) => Number(x.user_id)))].filter((id) => id !== exceptUserId);
  if (m.host_user_id && Number(m.host_user_id) !== exceptUserId && !ids.includes(Number(m.host_user_id))) ids.push(Number(m.host_user_id));
  await Promise.all(ids.map((id) => notify(id, m, kind)));
  return ids.length;
}

// ---------------------------------------------------------------------------
// User API
// ---------------------------------------------------------------------------

function parseOrigin(q, viewer) {
  const hasLat = q.lat !== undefined && q.lat !== '';
  const hasLng = q.lng !== undefined && q.lng !== '';
  if (hasLat || hasLng) {
    const lat = num(q.lat);
    const lng = num(q.lng);
    if (!M.validLatLng(lat, lng)) throw bad('A valid location is required');
    return { lat, lng };
  }
  if (viewer && viewer.lat !== null && viewer.lng !== null) return { lat: viewer.lat, lng: viewer.lng };
  return null;
}

// GET /api/meetups?lat&lng&radiusKm=25&type&city
router.get('/', optionalAuthenticateToken, wrap(async (req) => {
  const q = req.query || {};
  const type = typeof q.type === 'string' && q.type && q.type !== 'all' ? q.type : null;
  if (type && !TYPES.includes(type)) throw bad('Unknown meetup type');
  let radiusKm = DEFAULT_RADIUS_KM;
  if (q.radiusKm !== undefined && q.radiusKm !== '') {
    radiusKm = Number(q.radiusKm);
    if (!(radiusKm > 0)) throw bad('radiusKm must be a positive number');
    radiusKm = Math.min(radiusKm, MAX_RADIUS_KM);
  }
  const viewer = await viewerFor(req);
  const origin = parseOrigin(q, viewer);
  const city = !origin && typeof q.city === 'string' && q.city.trim() ? cleanText(q.city, 80) : null;
  const box = origin ? M.boundingBox(origin.lat, origin.lng, radiusKm) : null;

  const r = await vquery('mtList', (v) => `SELECT ${MEETUP_COLS(v)} ${MEETUP_FROM}
     WHERE m.status = 'approved' AND m.ends_at > $1
       AND ($2::text IS NULL OR m.type = $2::text)
       AND ($3::numeric IS NULL OR (m.lat BETWEEN $3::numeric AND $4::numeric AND m.lng BETWEEN $5::numeric AND $6::numeric))
       AND ($7::text IS NULL OR LOWER(m.city) = LOWER($7::text))
     ORDER BY m.starts_at ASC
     LIMIT $8`,
  [new Date(nowMs()).toISOString(), type, box ? box.minLat : null, box ? box.maxLat : null,
    box ? box.minLng : null, box ? box.maxLng : null, city, LIST_POOL]);

  const blocked = await blockedIds(viewer && viewer.id);
  let rows = r.rows;
  const rsvps = await myRsvps(viewer && viewer.id, rows.map((m) => Number(m.id)));
  rows = rows.filter((m) => canSee(m, viewer, blocked, rsvps.get(Number(m.id)) || null));
  let items = rows.map((m) => {
    const km = origin ? M.haversineKm(origin.lat, origin.lng, num(m.lat), num(m.lng)) : null;
    return { m, km };
  });
  if (origin) items = items.filter((x) => x.km !== null && x.km <= radiusKm);
  items.sort((a, b) => (ms(a.m.starts_at) - ms(b.m.starts_at)) || ((a.km ?? 0) - (b.km ?? 0)));
  items = items.slice(0, LIST_MAX);

  const goingIds = viewer && !viewer.banned
    ? items.filter((x) => {
      const s = rsvps.get(Number(x.m.id));
      return (s && GOING.includes(s.status)) || Number(x.m.host_user_id) === viewer.id;
    }).map((x) => Number(x.m.id))
    : [];
  const attendees = await attendeesOf(goingIds);
  return {
    origin: origin ? 'location' : city ? 'city' : 'none',
    radiusKm: origin ? radiusKm : null,
    types: TYPES,
    meetups: items.map(({ m }) => meetupView(m, {
      viewer, rsvp: rsvps.get(Number(m.id)) || null, origin, attendees: attendees.get(Number(m.id)) || null, blocked,
    })),
  };
}));

// GET /api/meetups/mine -> {upcoming, past, hosting}
router.get('/mine', registered, wrap(async (req) => {
  const viewer = await loadViewer(req.user.userId);
  if (!viewer) throw new HttpError(401, 'Please log in to join meetups', 'LOGIN_REQUIRED');
  const [joined, hosted, blocked] = await Promise.all([
    vquery('mtMine', (v) => `SELECT ${MEETUP_COLS(v)}, mr.status AS my_status, mr.checked_in_at AS my_checked_in_at
       FROM meetup_rsvps mr
       JOIN meetups m ON m.id = mr.meetup_id
       LEFT JOIN users hu ON hu.id = m.host_user_id
       LEFT JOIN buddy_profiles hbp ON hbp.user_id = m.host_user_id
       WHERE mr.user_id = $1 AND mr.status IN ('going', 'checked_in')
       ORDER BY m.starts_at DESC
       LIMIT 100`, [viewer.id]),
    vquery('mtHosted', (v) => `SELECT ${MEETUP_COLS(v)} ${MEETUP_FROM}
       WHERE m.host_user_id = $1
       ORDER BY m.starts_at DESC
       LIMIT 50`, [viewer.id]),
    blockedIds(viewer.id),
  ]);
  const t = nowMs();
  const upcoming = [];
  const past = [];
  for (const m of joined.rows) {
    const rsvp = { status: m.my_status, checked_in_at: m.my_checked_in_at };
    if (m.host_user_id && blocked.has(Number(m.host_user_id))) continue;
    const view = meetupView(m, { viewer, rsvp, blocked });
    if (ms(m.ends_at) > t) upcoming.push(view); else past.push(view);
  }
  upcoming.reverse(); // soonest first
  return {
    upcoming,
    past,
    hosting: hosted.rows.map((m) => meetupView(m, { viewer, blocked })),
  };
}));

// GET /api/meetups/can-propose -> {canPropose, reason?, remainingThisWeek}
router.get('/can-propose', optionalAuthenticateToken, wrap(async (req) => {
  const viewer = await viewerFor(req);
  if (!viewer) return { canPropose: false, reason: 'LOGIN_REQUIRED', remainingThisWeek: 0 };
  const used = await proposalsThisWeek(viewer.id);
  const remaining = Math.max(0, PROPOSALS_PER_WEEK - used);
  let reason = null;
  if (viewer.banned) reason = 'BANNED';
  else if (viewer.age === null || viewer.age < MIN_AGE) reason = viewer.hasBirthDate ? 'UNDER_18' : 'NO_BIRTH_DETAILS';
  else if (!viewer.verified) reason = 'NOT_VERIFIED';
  else if (!remaining) reason = 'RATE_LIMITED';
  return { canPropose: !reason, ...(reason ? { reason } : {}), remainingThisWeek: remaining, canHostWomenOnly: viewer.gender === 'female' };
}));

async function proposalsThisWeek(userId) {
  const r = await db.query(
    '/*q:mtRecentProposals*/ SELECT COUNT(*) AS n FROM meetups WHERE host_user_id = $1 AND created_at > $2',
    [userId, new Date(nowMs() - 7 * 24 * 3600 * 1000).toISOString()]
  );
  return Number(r.rows[0] && r.rows[0].n) || 0;
}

// POST /api/meetups  (verified users propose; status pending until an admin approves)
router.post('/', registered, wrap(async (req) => {
  const viewer = await loadViewer(req.user.userId);
  requireAdult(viewer);
  if (!viewer.verified) throw new HttpError(403, 'Get verified to host meetups', 'NOT_VERIFIED');
  const v = validateMeetup(req.body, { viewer });
  if (await proposalsThisWeek(viewer.id) >= PROPOSALS_PER_WEEK) {
    throw new HttpError(429, `You can propose up to ${PROPOSALS_PER_WEEK} meetups a week`, 'RATE_LIMITED');
  }
  const id = await insertMeetup(v, viewer.id, 'pending');
  return { meetup: (await detailFor(id, viewer)).view };
}));

// GET /api/meetups/:id
router.get('/:id', optionalAuthenticateToken, wrap(async (req) => {
  const id = toInt(req.params.id);
  if (!id) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const viewer = await viewerFor(req);
  return { meetup: (await detailFor(id, viewer)).view };
}));

// POST /api/meetups/:id/rsvp
router.post('/:id/rsvp', registered, wrap(async (req) => {
  const id = toInt(req.params.id);
  if (!id) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const viewer = await loadViewer(req.user.userId);
  requireAdult(viewer);
  const blocked = await blockedIds(viewer.id);

  const result = await db.withTransaction(async (client) => {
    // Row lock: concurrent RSVPs for one event are serialised, so capacity can't be exceeded.
    const cur = await client.query('/*q:mtLock*/ SELECT * FROM meetups WHERE id = $1 FOR UPDATE', [id]);
    const m = cur.rows[0];
    if (!m || m.status !== 'approved') throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
    if (m.host_user_id && blocked.has(Number(m.host_user_id))) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
    if (m.women_only && viewer.gender !== 'female') throw new HttpError(403, 'This meetup is for women only', 'WOMEN_ONLY');
    if (nowMs() >= ms(m.starts_at)) throw new HttpError(409, 'This meetup has already started', 'STARTED');
    const ex = await client.query('/*q:mtRsvpGet*/ SELECT * FROM meetup_rsvps WHERE meetup_id = $1 AND user_id = $2', [id, viewer.id]);
    if (ex.rows[0] && GOING.includes(ex.rows[0].status)) return { m, changed: false };
    const c = await client.query(
      "/*q:mtGoingCount*/ SELECT COUNT(*) AS n FROM meetup_rsvps WHERE meetup_id = $1 AND status IN ('going', 'checked_in')",
      [id]
    );
    if ((Number(c.rows[0] && c.rows[0].n) || 0) >= Number(m.capacity)) throw new HttpError(409, 'This meetup is full', 'FULL');
    await client.query(
      `/*q:mtRsvpUpsert*/ INSERT INTO meetup_rsvps (meetup_id, user_id, status) VALUES ($1, $2, 'going')
       ON CONFLICT (meetup_id, user_id) DO UPDATE SET status = 'going', created_at = CURRENT_TIMESTAMP, checked_in_at = NULL`,
      [id, viewer.id]
    );
    return { m, changed: true };
  });
  if (result.changed) await notify(viewer.id, result.m, 'rsvp_confirmed');
  return { meetup: (await detailFor(id, viewer)).view, changed: result.changed };
}));

// POST /api/meetups/:id/cancel  (cancel my RSVP; a checked-in RSVP stays)
router.post('/:id/cancel', registered, wrap(async (req) => {
  const id = toInt(req.params.id);
  if (!id) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const viewer = await loadViewer(req.user.userId);
  if (!viewer) throw new HttpError(401, 'Please log in to join meetups', 'LOGIN_REQUIRED');
  const r = await db.query(
    "/*q:mtRsvpCancel*/ UPDATE meetup_rsvps SET status = 'cancelled' WHERE meetup_id = $1 AND user_id = $2 AND status = 'going' RETURNING meetup_id",
    [id, viewer.id]
  );
  if (!r.rows.length) {
    const cur = await db.query('/*q:mtRsvpGet*/ SELECT * FROM meetup_rsvps WHERE meetup_id = $1 AND user_id = $2', [id, viewer.id]);
    const s = cur.rows[0] && cur.rows[0].status;
    if (s === 'checked_in') throw new HttpError(409, 'You have already checked in to this meetup', 'CHECKED_IN');
    if (s !== 'cancelled') throw new HttpError(404, 'You have not RSVPed to this meetup', 'NOT_GOING');
  }
  return { meetup: (await detailFor(id, viewer).catch(() => ({ view: null }))).view };
}));

// POST /api/meetups/:id/cancel-event  (host withdraws their own pending/approved event)
router.post('/:id/cancel-event', registered, wrap(async (req) => {
  const id = toInt(req.params.id);
  if (!id) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const viewer = await loadViewer(req.user.userId);
  if (!viewer) throw new HttpError(401, 'Please log in to join meetups', 'LOGIN_REQUIRED');
  const r = await db.query(
    `/*q:mtHostCancel*/ UPDATE meetups SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP
     WHERE id = $1 AND host_user_id = $2 AND status IN ('pending', 'approved') AND ends_at > $3 RETURNING *`,
    [id, viewer.id, new Date(nowMs()).toISOString()]
  );
  if (!r.rows.length) throw new HttpError(409, 'This meetup can no longer be cancelled', 'NOT_CANCELLABLE');
  await notifyAttendees(r.rows[0], 'cancelled', viewer.id);
  return { meetup: (await detailFor(id, viewer)).view };
}));

// POST /api/meetups/:id/checkin {lat, lng} | {code}
router.post('/:id/checkin', registered, wrap(async (req) => {
  const id = toInt(req.params.id);
  if (!id) throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const viewer = await loadViewer(req.user.userId);
  if (!viewer) throw new HttpError(401, 'Please log in to join meetups', 'LOGIN_REQUIRED');
  if (viewer.banned) throw new HttpError(403, 'Your account cannot join meetups after a safety review', 'BANNED');
  const body = req.body || {};
  const m = await loadMeetup(id);
  if (!m || m.status !== 'approved') throw new HttpError(404, 'This meetup is not available', 'NOT_FOUND');
  const rr = await db.query('/*q:mtRsvpGet*/ SELECT * FROM meetup_rsvps WHERE meetup_id = $1 AND user_id = $2', [id, viewer.id]);
  const rsvp = rr.rows[0];
  if (rsvp && rsvp.status === 'checked_in') {
    return { checkedIn: true, alreadyCheckedIn: true, coinsAwarded: 0, balance: await C.balanceOf(db, viewer.id), meetup: (await detailFor(id, viewer)).view };
  }
  if (!rsvp || rsvp.status !== 'going') throw new HttpError(403, 'RSVP to this meetup first', 'NOT_GOING');
  const t = nowMs();
  if (t < ms(m.starts_at) - CHECKIN_EARLY_MS) throw new HttpError(409, 'Check-in opens 30 minutes before the start', 'CHECKIN_NOT_OPEN');
  if (t > ms(m.ends_at)) throw new HttpError(409, 'Check-in has closed for this meetup', 'CHECKIN_CLOSED');

  const hasCode = body.code !== undefined && body.code !== null && body.code !== '';
  let method;
  if (hasCode) {
    if (Number(m.host_user_id) === viewer.id) throw new HttpError(403, 'Hosts check in with their location', 'HOST_CODE');
    if ((Number(rsvp.code_attempts) || 0) >= MAX_CODE_ATTEMPTS) {
      throw new HttpError(429, 'Too many wrong codes. Please check in with your location or ask the host.', 'RATE_LIMITED');
    }
    const code = String(body.code).replace(/\s+/g, '');
    if (!/^\d{6}$/.test(code) || !codesMatch(code, m.checkin_code)) {
      await db.query('/*q:mtCodeAttempt*/ UPDATE meetup_rsvps SET code_attempts = code_attempts + 1 WHERE meetup_id = $1 AND user_id = $2', [id, viewer.id]);
      throw bad('That code is not right. Ask the host for the 6-digit code.', 'BAD_CODE');
    }
    method = 'code';
  } else {
    const lat = num(body.lat);
    const lng = num(body.lng);
    if (typeof body.lat !== 'number' || typeof body.lng !== 'number' || !M.validLatLng(lat, lng)) {
      throw bad('Your location is needed to check in (or enter the host code)', 'LOCATION_REQUIRED');
    }
    const d = metersBetween(lat, lng, num(m.lat), num(m.lng));
    if (d === null || d > CHECKIN_RADIUS_M) {
      const err = new HttpError(409, `You need to be at the venue to check in (within ${CHECKIN_RADIUS_M} m)`, 'TOO_FAR');
      throw err;
    }
    method = 'location';
  }

  const out = await db.withTransaction(async (client) => {
    const up = await client.query(
      `/*q:mtCheckin*/ UPDATE meetup_rsvps SET status = 'checked_in', checked_in_at = CURRENT_TIMESTAMP
       WHERE meetup_id = $1 AND user_id = $2 AND status = 'going' RETURNING meetup_id`,
      [id, viewer.id]
    );
    const awarded = up.rows.length
      ? await C.awardCoins(client, viewer.id, CHECKIN_COINS, CHECKIN_REASON, `event:${id}`, `Satsang check-in: ${m.title}`)
      : 0;
    return { awarded, balance: await C.balanceOf(client, viewer.id) };
  });
  return {
    checkedIn: true, method, coinsAwarded: out.awarded, awarded: out.awarded, balance: out.balance,
    meetup: (await detailFor(id, viewer)).view,
  };
}));

// ---------------------------------------------------------------------------
// Admin API (mounted by routes/admin.js at /api/admin/meetups, after requireAdmin)
// ---------------------------------------------------------------------------
class AdminErr extends HttpError {}
function adminView(m) {
  return {
    id: Number(m.id),
    title: m.title,
    type: m.type,
    status: m.status,
    phase: phaseOf(m),
    description: m.description || '',
    venueName: m.venue_name,
    templeId: m.temple_id || null,
    address: m.address || '',
    city: m.city || null,
    lat: num(m.lat),
    lng: num(m.lng),
    startsAt: iso(m.starts_at),
    endsAt: iso(m.ends_at),
    capacity: Number(m.capacity) || 0,
    goingCount: Number(m.going_count) || 0,
    checkedInCount: Number(m.checked_in_count) || 0,
    womenOnly: !!m.women_only,
    checkinCode: m.checkin_code,
    adminNote: m.admin_note || null,
    host: m.host_user_id === null || m.host_user_id === undefined ? null : {
      userId: Number(m.host_user_id),
      name: m.host_display_name || m.host_full_name || null,
      email: m.host_email || null,
      verified: !!m.host_verified_at,
      banned: !!m.host_banned_at,
    },
    createdAt: iso(m.created_at),
  };
}
async function adminLoad(id) {
  const m = id ? await loadMeetup(id) : null;
  if (!m) throw new AdminErr(404, 'Meetup not found', 'MEETUP_NOT_FOUND');
  return m;
}

// GET /api/admin/meetups?status=pending|approved|rejected|cancelled|completed|upcoming|all
adminRouter.get('/', wrap(async (req) => {
  const status = typeof req.query.status === 'string' && req.query.status.trim() ? req.query.status.trim() : 'pending';
  if (status !== 'all' && status !== 'upcoming' && !STATUSES.includes(status)) {
    throw new AdminErr(400, `status must be one of: all, upcoming, ${STATUSES.join(', ')}`, 'BAD_STATUS');
  }
  const r = await vquery('mtAdminList', (v) => `SELECT ${MEETUP_COLS(v)} ${MEETUP_FROM}
     WHERE ($1::text = 'all' OR ($1::text = 'upcoming' AND m.status = 'approved' AND m.ends_at > $2) OR m.status = $1::text)
     ORDER BY m.starts_at ASC
     LIMIT 200`, [status, new Date(nowMs()).toISOString()]);
  return { meetups: r.rows.map(adminView) };
}));

// GET /api/admin/meetups/temples
adminRouter.get('/temples', wrap(async () => ({
  temples: TEMPLES.map((t) => ({ id: t.id, name: t.name, city: t.city, state: t.state, lat: t.lat, lng: t.lng })),
  types: TYPES,
})));

// POST /api/admin/meetups  (official event, approved immediately)
adminRouter.post('/', wrap(async (req) => {
  const v = validateMeetup(req.body, { admin: true });
  const id = await insertMeetup(v, null, 'approved');
  return { meetup: adminView(await adminLoad(id)) };
}));

async function adminTransition(req, from, to) {
  const id = toInt(req.params.id);
  const m = await adminLoad(id);
  if (!from.includes(m.status)) throw new AdminErr(409, `A ${m.status} meetup cannot be marked ${to}`, 'BAD_TRANSITION');
  const note = cleanText((req.body || {}).note, 500) || null;
  const r = await db.query(
    `/*q:mtAdminStatus*/ UPDATE meetups SET status = $2, admin_note = COALESCE($3, admin_note), updated_at = CURRENT_TIMESTAMP
     WHERE id = $1 AND status = ANY($4::text[]) RETURNING *`,
    [id, to, note, from]
  );
  if (!r.rows.length) throw new AdminErr(409, 'This meetup was just updated. Please refresh.', 'BAD_TRANSITION');
  return r.rows[0];
}

// POST /api/admin/meetups/:id/approve
adminRouter.post('/:id/approve', wrap(async (req) => {
  const m = await adminTransition(req, ['pending'], 'approved');
  if (m.host_user_id) await notify(Number(m.host_user_id), m, 'approved');
  return { meetup: adminView(await adminLoad(Number(m.id))) };
}));

// POST /api/admin/meetups/:id/reject {note?}
adminRouter.post('/:id/reject', wrap(async (req) => {
  const m = await adminTransition(req, ['pending'], 'rejected');
  if (m.host_user_id) await notify(Number(m.host_user_id), m, 'rejected');
  return { meetup: adminView(await adminLoad(Number(m.id))) };
}));

// POST /api/admin/meetups/:id/cancel {note?}  (notifies everyone going + the host)
adminRouter.post('/:id/cancel', wrap(async (req) => {
  const m = await adminTransition(req, ['pending', 'approved'], 'cancelled');
  const notified = await notifyAttendees(m, 'cancelled');
  return { meetup: adminView(await adminLoad(Number(m.id))), notified };
}));

module.exports = router;
module.exports.adminRouter = adminRouter;
module.exports._internal = {
  TYPES, validateMeetup, canSee, meetupView, initials, metersBetween, checkinOpen,
  CHECKIN_COINS, CHECKIN_RADIUS_M, PROPOSALS_PER_WEEK, MAX_CODE_ATTEMPTS,
  setClock(fn) { clock = fn || (() => Date.now()); },
  resetVerifiedColumn() { hasVerifiedCol = true; },
};
