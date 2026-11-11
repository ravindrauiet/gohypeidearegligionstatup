// Admin moderation API (/api/admin) + the tiny admin page (GET /admin, see `page` below).
// Every API call needs the header `x-admin-key` equal to process.env.ADMIN_KEY. When ADMIN_KEY
// is unset (or shorter than 16 characters) the whole API answers 503 "admin disabled".
const express = require('express');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const db = require('../db');
const C = require('../services/coins_service');
const push = require('../services/push_service');
const TEMPLES = require('../data/temples.json');

const router = express.Router();
const TEMPLE_BY_ID = new Map(TEMPLES.map((t) => [t.id, t]));
const MIN_KEY_LENGTH = 16;
const TRIP_STATUSES = ['pending', 'approved', 'completed', 'rejected', 'cancelled'];
const REPORT_STATUSES = ['open', 'dismissed', 'banned'];
// Allowed admin transitions. Refunds happen only on -> rejected.
const TRIP_TRANSITIONS = {
  pending: ['approved', 'rejected'],
  approved: ['completed', 'rejected'],
};
// Ledger key for an admin rejection refund. Distinct from the user-cancel refund
// (trip_refund / trip:<id>) but the same reason, so "earned" totals keep excluding it.
const REFUND_REASON = 'trip_refund';
const refundRef = (tripId) => `trip:${tripId}:rejected`;

class AdminError extends Error {
  constructor(statusCode, code, message) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
  }
}

function handle(fn) {
  return async (req, res) => {
    try {
      res.json(await fn(req));
    } catch (err) {
      if (err instanceof AdminError) return res.status(err.statusCode).json({ error: err.message, code: err.code });
      console.error('Admin error:', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  };
}

// Constant-time comparison (hashing first makes the lengths equal).
function keysMatch(given, expected) {
  const a = crypto.createHash('sha256').update(String(given)).digest();
  const b = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(a, b);
}

function requireAdmin(req, res, next) {
  res.setHeader('Cache-Control', 'no-store');
  const expected = (process.env.ADMIN_KEY || '').trim();
  if (expected.length < MIN_KEY_LENGTH) {
    return res.status(503).json({ error: 'admin disabled', code: 'ADMIN_DISABLED' });
  }
  const given = req.headers['x-admin-key'];
  if (typeof given !== 'string' || !given || !keysMatch(given, expected)) {
    return res.status(401).json({ error: 'Invalid admin key', code: 'BAD_ADMIN_KEY' });
  }
  return next();
}

router.use(requireAdmin);

function toId(x) {
  const n = Number(x);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function iso(d) {
  return d instanceof Date ? d.toISOString() : d || null;
}

function cleanNote(note) {
  if (note === undefined || note === null) return null;
  const s = String(note).replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, 500) : null;
}

function temple(id) {
  const t = TEMPLE_BY_ID.get(id);
  return t ? { id: t.id, name: t.name, city: t.city, state: t.state } : { id, name: id, city: null, state: null };
}

const TRIP_SELECT = `
  SELECT t.id, t.user_id, t.buddy_user_id, t.temple_id, t.preferred_month, t.status, t.coins_spent, t.note,
         t.created_at, t.updated_at,
         ou.full_name AS owner_full_name, ou.email AS owner_email, ob.display_name AS owner_display_name,
         bu.full_name AS buddy_full_name, bu.email AS buddy_email, bb.display_name AS buddy_display_name
  FROM trip_requests t
  LEFT JOIN users ou ON ou.id = t.user_id
  LEFT JOIN buddy_profiles ob ON ob.user_id = t.user_id
  LEFT JOIN users bu ON bu.id = t.buddy_user_id
  LEFT JOIN buddy_profiles bb ON bb.user_id = t.buddy_user_id`;

function tripView(r) {
  const person = (id, fullName, displayName, email) =>
    id ? { userId: Number(id), name: displayName || fullName || null, fullName: fullName || null, email: email || null } : null;
  return {
    id: r.id,
    status: r.status,
    temple: temple(r.temple_id),
    preferredMonth: r.preferred_month,
    coinsSpent: Number(r.coins_spent) || 0,
    note: r.note || null,
    user: person(r.user_id, r.owner_full_name, r.owner_display_name, r.owner_email),
    buddy: person(r.buddy_user_id, r.buddy_full_name, r.buddy_display_name, r.buddy_email),
    createdAt: iso(r.created_at),
    updatedAt: iso(r.updated_at),
  };
}

// GET /api/admin/trips?status=pending  (status omitted or 'all' -> every status)
router.get('/trips', handle(async (req) => {
  const status = typeof req.query.status === 'string' ? req.query.status.trim() : '';
  if (status && status !== 'all' && !TRIP_STATUSES.includes(status)) {
    throw new AdminError(400, 'BAD_STATUS', `status must be one of: all, ${TRIP_STATUSES.join(', ')}`);
  }
  const r = status && status !== 'all'
    ? await db.query(`${TRIP_SELECT} WHERE t.status = $1 ORDER BY t.id ASC LIMIT 200`, [status])
    : await db.query(`${TRIP_SELECT} ORDER BY t.id DESC LIMIT 200`, []);
  return { trips: r.rows.map(tripView) };
}));

// POST /api/admin/trips/:id/status { status: approved|rejected|completed, note? }
// Rejecting refunds the held coins once (idempotent ledger row).
router.post('/trips/:id/status', handle(async (req) => {
  const id = toId(req.params.id);
  const body = req.body || {};
  const next = body.status;
  if (!['approved', 'rejected', 'completed'].includes(next)) {
    throw new AdminError(400, 'BAD_STATUS', 'status must be approved, rejected or completed');
  }
  if (!id) throw new AdminError(404, 'TRIP_NOT_FOUND', 'Trip request not found');
  const note = cleanNote(body.note);

  const result = await db.withTransaction(async (client) => {
    const cur = await client.query('SELECT * FROM trip_requests WHERE id = $1 FOR UPDATE', [id]);
    const trip = cur.rows[0];
    if (!trip) throw new AdminError(404, 'TRIP_NOT_FOUND', 'Trip request not found');
    // Same lock order as /api/trips so balance checks there stay serialised.
    await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [trip.user_id]);

    const unchanged = trip.status === next;
    if (!unchanged && !(TRIP_TRANSITIONS[trip.status] || []).includes(next)) {
      throw new AdminError(409, 'BAD_TRANSITION', `A ${trip.status} trip cannot be marked ${next}`);
    }
    if (!unchanged || note !== null) {
      await client.query(
        'UPDATE trip_requests SET status = $2, note = COALESCE($3, note), updated_at = CURRENT_TIMESTAMP WHERE id = $1',
        [id, next, note]
      );
    }
    let refunded = 0;
    const amount = Number(trip.coins_spent) || 0;
    if (next === 'rejected' && amount > 0) {
      refunded = await C.awardCoins(client, trip.user_id, amount, REFUND_REASON, refundRef(id),
        `Refund: trip to ${temple(trip.temple_id).name} not approved`);
    }
    const row = await client.query(`${TRIP_SELECT} WHERE t.id = $1`, [id]);
    return { trip: tripView(row.rows[0]), refunded, unchanged };
  });
  // After commit, so a rolled-back change never notifies anyone.
  if (!result.unchanged) await notifyTrip(result.trip, result.refunded);
  return result;
}));

const TRIP_STATUS_TEXT = {
  approved: (place) => `Your trip to ${place} is approved. Our team will contact you with the plan.`,
  completed: (place) => `Your trip to ${place} is complete. Hope you had a blessed darshan!`,
  rejected: (place, refunded) => `Your trip to ${place} could not be arranged.${refunded ? ` ${refunded.toLocaleString('en-IN')} coins were refunded.` : ''}`,
};

// trip_update to the requester and (if set) the buddy going with them. Never throws.
async function notifyTrip(trip, refunded) {
  const text = TRIP_STATUS_TEXT[trip.status];
  if (!text) return;
  const place = trip.temple.name;
  const msg = (forOwner) => ({
    type: 'trip_update',
    title: `Temple trip ${trip.status}`,
    body: forOwner ? text(place, refunded) : text(place, 0),
    data: { tripId: trip.id, status: trip.status },
  });
  const sends = [];
  if (trip.user) sends.push(push.sendToUser(trip.user.userId, msg(true), { pref: 'trips' }));
  if (trip.buddy && (!trip.user || trip.buddy.userId !== trip.user.userId)) {
    sends.push(push.sendToUser(trip.buddy.userId, msg(false), { pref: 'trips' }));
  }
  await Promise.all(sends);
}

// ---------------------------------------------------------------------------
// Announcements: one broadcasts row (shown in every inbox for users who signed up before it)
// + one FCM send to the 'announcements' topic (clients subscribe/unsubscribe per their pref).
// ---------------------------------------------------------------------------
const BROADCAST_TITLE_MAX = 80;
const BROADCAST_BODY_MAX = 300;

function broadcastView(r) {
  const data = r.data && typeof r.data === 'object' ? r.data : (() => { try { return JSON.parse(r.data || '{}'); } catch (_) { return {}; } })();
  return { id: `b:${r.id}`, title: r.title, body: r.body, data, createdAt: iso(r.created_at) };
}

function cleanBroadcastData(data) {
  if (data === undefined || data === null) return {};
  if (typeof data !== 'object' || Array.isArray(data)) throw new AdminError(400, 'BAD_DATA', 'data must be an object of strings');
  const out = {};
  const keys = Object.keys(data);
  if (keys.length > 10) throw new AdminError(400, 'BAD_DATA', 'data can have at most 10 keys');
  for (const k of keys) {
    if (!/^[A-Za-z][A-Za-z0-9_]{0,39}$/.test(k) || ['type', 'from', 'notification', 'message_type'].includes(k) || /^(google|gcm)/i.test(k)) {
      throw new AdminError(400, 'BAD_DATA', `data key "${k}" is not allowed`);
    }
    const v = data[k];
    if (v === null || v === undefined) continue;
    if (typeof v === 'object') throw new AdminError(400, 'BAD_DATA', 'data values must be strings');
    const sv = String(v);
    if (sv.length > 500) throw new AdminError(400, 'BAD_DATA', 'data values can be at most 500 characters');
    out[k] = sv;
  }
  if (out.url !== undefined && !/^https:\/\/\S+$/i.test(out.url)) throw new AdminError(400, 'BAD_DATA', 'url must start with https://');
  return out;
}

// POST /api/admin/broadcast {title (<=80), body (<=300), data?}
router.post('/broadcast', handle(async (req) => {
  const b = req.body || {};
  const title = typeof b.title === 'string' ? b.title.replace(/\s+/g, ' ').trim() : '';
  const body = typeof b.body === 'string' ? b.body.trim() : '';
  if (!title || title.length > BROADCAST_TITLE_MAX) throw new AdminError(400, 'BAD_TITLE', `title must be 1 to ${BROADCAST_TITLE_MAX} characters`);
  if (!body || body.length > BROADCAST_BODY_MAX) throw new AdminError(400, 'BAD_BODY', `body must be 1 to ${BROADCAST_BODY_MAX} characters`);
  const data = cleanBroadcastData(b.data);
  const ins = await db.query(
    'INSERT INTO broadcasts (title, body, data) VALUES ($1, $2, $3::jsonb) RETURNING id, title, body, data, created_at',
    [title, body, JSON.stringify(data)]
  );
  const row = ins.rows[0];
  const sent = await push.sendToTopic('announcements', {
    type: 'announcement', title, body, data: { ...data, broadcastId: `b:${row.id}` },
  });
  return { broadcast: broadcastView(row), pushed: !!(sent && sent.sent) };
}));

// GET /api/admin/broadcasts (latest 50)
router.get('/broadcasts', handle(async () => {
  const r = await db.query('SELECT id, title, body, data, created_at FROM broadcasts ORDER BY id DESC LIMIT 50', []);
  return { broadcasts: r.rows.map(broadcastView) };
}));

const REPORT_SELECT = `
  SELECT r.id, r.reporter_id, r.reported_user_id, r.reason, r.details, r.status, r.created_at, r.resolved_at,
         ru.full_name AS reporter_full_name, ru.email AS reporter_email, rb.display_name AS reporter_display_name,
         tu.full_name AS reported_full_name, tu.email AS reported_email, tb.display_name AS reported_display_name,
         tb.is_active AS reported_profile_active
  FROM buddy_reports r
  LEFT JOIN users ru ON ru.id = r.reporter_id
  LEFT JOIN buddy_profiles rb ON rb.user_id = r.reporter_id
  LEFT JOIN users tu ON tu.id = r.reported_user_id
  LEFT JOIN buddy_profiles tb ON tb.user_id = r.reported_user_id`;

function reportView(r) {
  return {
    id: r.id,
    status: r.status,
    reason: r.reason,
    details: r.details || null,
    reporter: { userId: Number(r.reporter_id), name: r.reporter_display_name || r.reporter_full_name || null, email: r.reporter_email || null },
    reported: {
      userId: Number(r.reported_user_id),
      name: r.reported_display_name || r.reported_full_name || null,
      email: r.reported_email || null,
      profileActive: r.reported_profile_active === null || r.reported_profile_active === undefined ? null : r.reported_profile_active !== false,
    },
    createdAt: iso(r.created_at),
    resolvedAt: iso(r.resolved_at),
  };
}

// GET /api/admin/reports?status=open  (default open; 'all' -> every status)
router.get('/reports', handle(async (req) => {
  const status = typeof req.query.status === 'string' && req.query.status.trim() ? req.query.status.trim() : 'open';
  if (status !== 'all' && !REPORT_STATUSES.includes(status)) {
    throw new AdminError(400, 'BAD_STATUS', `status must be one of: all, ${REPORT_STATUSES.join(', ')}`);
  }
  const r = status === 'all'
    ? await db.query(`${REPORT_SELECT} ORDER BY r.id DESC LIMIT 200`, [])
    : await db.query(`${REPORT_SELECT} WHERE r.status = $1 ORDER BY r.id ASC LIMIT 200`, [status]);
  return { reports: r.rows.map(reportView) };
}));

// POST /api/admin/reports/:id/resolve { action: dismiss|ban }
// ban hides the reported person's buddy profile (is_active = false, show_nearby = false) and
// closes every open report against them.
router.post('/reports/:id/resolve', handle(async (req) => {
  const id = toId(req.params.id);
  const action = (req.body || {}).action;
  if (!['dismiss', 'ban'].includes(action)) throw new AdminError(400, 'BAD_ACTION', 'action must be dismiss or ban');
  if (!id) throw new AdminError(404, 'REPORT_NOT_FOUND', 'Report not found');

  return db.withTransaction(async (client) => {
    const cur = await client.query('SELECT id, reported_user_id, status FROM buddy_reports WHERE id = $1 FOR UPDATE', [id]);
    const report = cur.rows[0];
    if (!report) throw new AdminError(404, 'REPORT_NOT_FOUND', 'Report not found');
    let profileHidden = false;
    if (action === 'ban') {
      const upd = await client.query(
        `UPDATE buddy_profiles SET is_active = FALSE, show_nearby = FALSE, banned_at = COALESCE(banned_at, CURRENT_TIMESTAMP),
                updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $1 RETURNING user_id`,
        [report.reported_user_id]
      );
      profileHidden = upd.rows.length > 0;
      await client.query(
        `UPDATE buddy_reports SET status = 'banned', resolved_at = CURRENT_TIMESTAMP
         WHERE (id = $1 OR (reported_user_id = $2 AND status = 'open'))`,
        [id, report.reported_user_id]
      );
    } else {
      await client.query(
        `UPDATE buddy_reports SET status = 'dismissed', resolved_at = CURRENT_TIMESTAMP WHERE id = $1`,
        [id]
      );
    }
    const row = await client.query(`${REPORT_SELECT} WHERE r.id = $1`, [id]);
    return { report: reportView(row.rows[0]), profileHidden };
  });
}));

// GET /api/admin/stats
router.get('/stats', handle(async () => {
  const r = await db.query(
    `SELECT
       (SELECT COUNT(*) FROM users WHERE role IS DISTINCT FROM 'guest') AS users,
       (SELECT COUNT(*) FROM users WHERE role = 'guest') AS guests,
       (SELECT COUNT(*) FROM buddy_profiles) AS buddy_profiles,
       (SELECT COUNT(*) FROM buddy_profiles WHERE is_active = TRUE) AS active_buddy_profiles,
       (SELECT COUNT(*) FROM trip_requests WHERE status = 'pending') AS pending_trips,
       (SELECT COUNT(*) FROM buddy_reports WHERE status = 'open') AS open_reports,
       (SELECT COALESCE(SUM(amount), 0) FROM coin_ledger
         WHERE amount > 0 AND reason <> 'trip_refund'
           AND created_at >= (date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')
       ) AS coins_issued_today`,
    []
  );
  const s = r.rows[0] || {};
  const n = (x) => Number(x) || 0;
  return {
    users: n(s.users),
    guests: n(s.guests),
    buddyProfiles: n(s.buddy_profiles),
    activeBuddyProfiles: n(s.active_buddy_profiles),
    pendingTrips: n(s.pending_trips),
    openReports: n(s.open_reports),
    coinsIssuedToday: n(s.coins_issued_today),
    date: C.istDate(),
  };
}));

// ---------------------------------------------------------------------------
// v3 meetups (agent M): /api/admin/meetups — pending proposals, official events, cancel, RSVP
// counts and check-in codes. The handlers live in routes/meetups.js (adminRouter); requireAdmin
// above already guards them.
// ---------------------------------------------------------------------------
router.use('/meetups', require('./meetups').adminRouter);

// ---------------------------------------------------------------------------
// v3 trust (agent T): /api/admin/verifications — the "Verification queue" (selfie + gesture,
// approve / reject; the selfie is deleted on decision). Handlers live in routes/admin_trust.js;
// requireAdmin above already guards them.
// ---------------------------------------------------------------------------
router.use(require('./admin_trust'));

// Analytics for the dashboard page (GET /admin/dashboard): users, platforms, AI tokens and spend.
router.use('/analytics', require('./admin_analytics'));

// GET /admin: the static admin page (no key needed to load it; every API call needs the key).
// Read with fs at a fixed path so Vercel's file tracing bundles it.
const pageCache = {};
function servePage(file) {
  const filePath = path.join(__dirname, '..', 'public', file);
  return function (req, res) {
    try {
      if (!pageCache[file]) pageCache[file] = fs.readFileSync(filePath, 'utf8');
    } catch (err) {
      console.error('Admin page missing:', err.message);
      return res.status(404).json({ error: 'Admin page not found' });
    }
    sendPage(res, pageCache[file]);
  };
}
function sendPage(res, html) {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Content-Security-Policy',
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  res.send(html);
}

router.page = servePage('admin.html');
router.dashboardPage = servePage('admin_dashboard.html');
router._internals = { notifyTrip, cleanBroadcastData, keysMatch, TRIP_TRANSITIONS, refundRef, REFUND_REASON };

module.exports = router;
