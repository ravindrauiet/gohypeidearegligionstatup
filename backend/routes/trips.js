// Temple trips (/api/trips): 10,000 coins buys a temple trip with an accepted buddy, arranged by
// the team. Temples live in data/temples.json. Coins move through coin_ledger only.
const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const C = require('../services/coins_service');
const TEMPLES = require('../data/temples.json');

const TEMPLE_BY_ID = new Map(TEMPLES.map((t) => [t.id, t]));
const RECOMMEND_COUNT = 5;
const MONTH_RE = /^(\d{4})-(0[1-9]|1[0-2])$/;
const MAX_MONTHS_AHEAD = 24;

const auth = [optionalAuthenticateToken, C.requireRegistered('Please log in to plan a temple trip.')];

// ---------------------------------------------------------------------------
// Geo helpers (pure)
// ---------------------------------------------------------------------------
const toRad = (d) => (d * Math.PI) / 180;
const toDeg = (r) => (r * 180) / Math.PI;

function validPoint(p) {
  return !!p && Number.isFinite(p.lat) && Number.isFinite(p.lng) && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;
}

function haversineKm(a, b) {
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

// Geographic midpoint of two points on a sphere.
function midpoint(a, b) {
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLng = toRad(b.lng - a.lng);
  const bx = Math.cos(lat2) * Math.cos(dLng);
  const by = Math.cos(lat2) * Math.sin(dLng);
  const lat = Math.atan2(Math.sin(lat1) + Math.sin(lat2), Math.sqrt((Math.cos(lat1) + bx) ** 2 + by ** 2));
  const lng = toRad(a.lng) + Math.atan2(by, Math.cos(lat1) + bx);
  return { lat: toDeg(lat), lng: ((toDeg(lng) + 540) % 360) - 180 };
}

// Where to measure from: midpoint of both when both known, else whoever is known, else null.
function originFor(me, buddy) {
  const a = validPoint(me) ? me : null;
  const b = validPoint(buddy) ? buddy : null;
  if (a && b) return { point: midpoint(a, b), shared: true };
  if (a) return { point: a, shared: false };
  if (b) return { point: b, shared: true };
  return { point: null, shared: false };
}

// Temples with distanceKm from `origin` (null when unknown) and the top recommendations.
// When the origin involves the buddy's location, distances are rounded to 10 km so the
// buddy's position can't be worked back out from them.
function rankTemples(temples, origin, { coarse = false, count = RECOMMEND_COUNT } = {}) {
  const list = temples.map((t) => {
    let distanceKm = null;
    if (validPoint(origin)) {
      const d = haversineKm(origin, t);
      distanceKm = coarse ? Math.max(10, Math.round(d / 10) * 10) : Math.round(d);
    }
    return {
      id: t.id,
      name: t.name,
      deity: t.deity,
      city: t.city,
      state: t.state,
      lat: t.lat,
      lng: t.lng,
      ...(t.image ? { image: t.image } : {}),
      tags: t.tags || [],
      distanceKm,
      why: t.why,
    };
  });
  let recommended;
  if (validPoint(origin)) {
    const exact = temples.map((t) => ({ id: t.id, d: haversineKm(origin, t) })).sort((x, y) => x.d - y.d);
    recommended = exact.slice(0, count).map((x) => x.id);
    const order = new Map(exact.map((x, i) => [x.id, i]));
    list.sort((x, y) => order.get(x.id) - order.get(y.id));
  } else {
    recommended = temples.filter((t) => t.popular).slice(0, count).map((t) => t.id);
    for (const t of temples) {
      if (recommended.length >= count) break;
      if (!recommended.includes(t.id)) recommended.push(t.id);
    }
  }
  return { temples: list, recommended };
}

// 'YYYY-MM' that is this IST month or later, and not too far ahead.
function validMonth(month, now = new Date()) {
  const m = typeof month === 'string' ? month.match(MONTH_RE) : null;
  if (!m) return false;
  const [cy, cm] = C.istMonth(now).split('-').map(Number);
  const diff = (Number(m[1]) - cy) * 12 + (Number(m[2]) - cm);
  return diff >= 0 && diff <= MAX_MONTHS_AHEAD;
}

// ---------------------------------------------------------------------------
// DB helpers
// ---------------------------------------------------------------------------
function num(x) {
  if (x === null || x === undefined || x === '') return NaN;
  return Number(x);
}

// My location: buddy profile (rounded) or, failing that, my birth place. Another person's birth
// details are private, so for a buddy only their (rounded) buddy-profile location is used.
async function locationOf(q, userId, { birthPlaceFallback = true } = {}) {
  const r = await q.query(
    `SELECT bp.lat AS bp_lat, bp.lng AS bp_lng, bd.latitude AS bd_lat, bd.longitude AS bd_lng
     FROM users u
     LEFT JOIN buddy_profiles bp ON bp.user_id = u.id
     LEFT JOIN birth_details bd ON bd.user_id = u.id
     WHERE u.id = $1`,
    [userId]
  );
  const row = r.rows[0];
  if (!row) return null;
  const bp = { lat: num(row.bp_lat), lng: num(row.bp_lng) };
  if (validPoint(bp)) return bp;
  if (!birthPlaceFallback) return null;
  const bd = { lat: num(row.bd_lat), lng: num(row.bd_lng) };
  return validPoint(bd) ? bd : null;
}

async function areBuddies(q, a, b) {
  const r = await q.query(
    `SELECT 1 FROM buddy_connections
     WHERE status = 'accepted'
       AND ((from_user_id = $1 AND to_user_id = $2) OR (from_user_id = $2 AND to_user_id = $1))
       AND NOT EXISTS (
         SELECT 1 FROM buddy_blocks
         WHERE (user_id = $1 AND blocked_user_id = $2) OR (user_id = $2 AND blocked_user_id = $1)
       )
       AND NOT EXISTS (
         SELECT 1 FROM buddy_profiles WHERE user_id IN ($1, $2) AND banned_at IS NOT NULL
       )
     LIMIT 1`,
    [a, b]
  );
  return r.rows.length > 0;
}

function templeLite(id) {
  const t = TEMPLE_BY_ID.get(id);
  if (!t) return { id, name: id, deity: null, city: null, state: null };
  return { id: t.id, name: t.name, deity: t.deity, city: t.city, state: t.state };
}

function requestView(row, meId) {
  const mine = Number(row.user_id) === Number(meId);
  const otherId = mine ? row.buddy_user_id : row.user_id;
  const otherName = mine ? row.buddy_name : row.owner_name;
  return {
    id: row.id,
    temple: templeLite(row.temple_id),
    buddy: otherId ? { userId: Number(otherId), displayName: otherName || 'Your buddy' } : null,
    preferredMonth: row.preferred_month,
    status: row.status,
    coinsSpent: Number(row.coins_spent) || 0,
    mine,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at,
  };
}

const REQUEST_SELECT = `
  SELECT t.*,
         COALESCE(NULLIF(bb.display_name, ''), split_part(bu.full_name, ' ', 1)) AS buddy_name,
         COALESCE(NULLIF(ob.display_name, ''), split_part(ou.full_name, ' ', 1)) AS owner_name
  FROM trip_requests t
  LEFT JOIN users bu ON bu.id = t.buddy_user_id
  LEFT JOIN buddy_profiles bb ON bb.user_id = t.buddy_user_id
  LEFT JOIN users ou ON ou.id = t.user_id
  LEFT JOIN buddy_profiles ob ON ob.user_id = t.user_id`;

class TripError extends Error {
  constructor(statusCode, code, message, extra) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.extra = extra;
  }
}

function handle(fn) {
  return async (req, res) => {
    try {
      res.json(await fn(req));
    } catch (err) {
      if (err instanceof TripError) {
        return res.status(err.statusCode).json({ error: err.message, code: err.code, ...(err.extra || {}) });
      }
      console.error('Trips error:', err);
      res.status(500).json({ error: 'Something went wrong with your trip. Please try again.' });
    }
  };
}

// Positive Postgres INTEGER, else null (bigger values would make the query throw a 500).
function parseUserId(x) {
  const n = Number(x);
  return Number.isInteger(n) && n > 0 && n <= 2147483647 ? n : null;
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
router.get('/temples', auth, handle(async (req) => {
  const me = req.user.userId;
  const buddyId = req.query.buddyId !== undefined && req.query.buddyId !== '' ? parseUserId(req.query.buddyId) : null;
  const myLoc = await locationOf(db, me);
  let buddyLoc = null;
  // Only an accepted buddy's location is ever used, and never returned.
  if (buddyId && buddyId !== me && (await areBuddies(db, me, buddyId))) {
    buddyLoc = await locationOf(db, buddyId, { birthPlaceFallback: false });
  }
  const origin = originFor(myLoc, buddyLoc);
  return rankTemples(TEMPLES, origin.point, { coarse: origin.shared });
}));

router.post('/request', auth, handle(async (req) => {
  const me = req.user.userId;
  const body = req.body || {};
  const buddyId = parseUserId(body.buddyId);
  const temple = TEMPLE_BY_ID.get(typeof body.templeId === 'string' ? body.templeId : '');
  const preferredMonth = typeof body.preferredMonth === 'string' ? body.preferredMonth.trim() : '';
  if (!buddyId || buddyId === me) throw new TripError(400, 'BAD_BUDDY', 'Choose one of your buddies for this trip.');
  if (!temple) throw new TripError(400, 'BAD_TEMPLE', 'Choose a temple from the list.');
  if (!validMonth(preferredMonth)) throw new TripError(400, 'BAD_MONTH', 'Choose a month from this month up to two years ahead.');

  return db.withTransaction(async (client) => {
    // Serialise all coin spending for this account so the balance can never go negative
    const lock = await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [me]);
    if (!lock.rows[0]) throw new TripError(401, 'LOGIN_REQUIRED', 'Your session is no longer valid. Please log in again.');
    if (!(await areBuddies(client, me, buddyId))) {
      throw new TripError(403, 'NOT_BUDDIES', 'You can plan a trip only with an accepted buddy.');
    }
    const balance = await C.balanceOf(client, me);
    if (balance < C.TRIP_COST) {
      throw new TripError(409, 'INSUFFICIENT_COINS', `You need ${C.TRIP_COST.toLocaleString('en-IN')} coins for a temple trip.`, {
        balance,
        needed: C.TRIP_COST - balance,
      });
    }
    const ins = await client.query(
      `INSERT INTO trip_requests (user_id, buddy_user_id, temple_id, preferred_month, status, coins_spent)
       VALUES ($1, $2, $3, $4, 'pending', $5) RETURNING id`,
      [me, buddyId, temple.id, preferredMonth, C.TRIP_COST]
    );
    const id = ins.rows[0].id;
    await C.awardCoins(client, me, -C.TRIP_COST, 'trip', `trip:${id}`, `Temple trip: ${temple.name}`);
    const row = await client.query(`${REQUEST_SELECT} WHERE t.id = $1`, [id]);
    return { request: requestView(row.rows[0], me), balance: await C.balanceOf(client, me) };
  });
}));

router.get('/', auth, handle(async (req) => {
  const me = req.user.userId;
  const r = await db.query(
    `${REQUEST_SELECT} WHERE t.user_id = $1 OR t.buddy_user_id = $1 ORDER BY t.id DESC LIMIT 50`,
    [me]
  );
  return { requests: r.rows.map((row) => requestView(row, me)) };
}));

router.post('/:id/cancel', auth, handle(async (req) => {
  const me = req.user.userId;
  const id = parseUserId(req.params.id);
  if (!id) throw new TripError(404, 'TRIP_NOT_FOUND', 'Trip request not found.');
  return db.withTransaction(async (client) => {
    // Lock order trip -> user, the same as POST /api/admin/trips/:id/status, so a user cancel racing
    // an admin reject cannot deadlock. Both need status 'pending' under the trip lock: one refund only.
    const cur = await client.query('SELECT * FROM trip_requests WHERE id = $1 AND user_id = $2 FOR UPDATE', [id, me]);
    const trip = cur.rows[0];
    if (!trip) throw new TripError(404, 'TRIP_NOT_FOUND', 'Trip request not found.');
    await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [me]);
    if (trip.status !== 'pending') throw new TripError(409, 'NOT_PENDING', 'Only a pending trip request can be cancelled.');
    await client.query(`UPDATE trip_requests SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP WHERE id = $1`, [id]);
    const refund = Number(trip.coins_spent) || 0;
    if (refund > 0) await C.awardCoins(client, me, refund, 'trip_refund', `trip:${id}`, `Refund: ${templeLite(trip.temple_id).name}`);
    const row = await client.query(`${REQUEST_SELECT} WHERE t.id = $1`, [id]);
    return { request: requestView(row.rows[0], me), balance: await C.balanceOf(client, me) };
  });
}));

router._internals = { parseUserId, haversineKm, midpoint, originFor, rankTemples, validMonth, validPoint, requestView, TEMPLES };

module.exports = router;
