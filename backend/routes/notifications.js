// Notification inbox, device tokens and push preferences (/api/notifications).
//
// The inbox merges two sources, newest first:
//   - the user's own rows in `notifications`   -> id "n:<id>"
//   - admin `broadcasts` created since signup   -> id "b:<id>", type "announcement"
// Ordering is (created_at DESC, kind DESC, id DESC) with kind n=1, b=0, which is total across both
// tables. The pagination cursor is simply the id of the last item already shown:
//   GET /api/notifications?before=n:34&limit=30
// The server resolves that item's created_at (full precision) and returns strictly older items, so
// rows sharing a timestamp are never skipped or repeated. A cursor that no longer exists yields [].
//
// Guests (and requests without a registered account) read empty results; writes answer 403.
// SQL statements carry a /*q:name*/ tag (the fake db in test/notifications.test.js dispatches on it).
const express = require('express');
const db = require('../db');
const { authenticateToken } = require('./auth');
const { _internals: { PREF_KEYS } } = require('../services/push_service');

const router = express.Router();
const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 50;
const MAX_READ_IDS = 200;
const MAX_INT = 2147483647;
const PLATFORMS = ['android', 'ios'];
const DEFAULT_PREFS = Object.freeze(Object.fromEntries(PREF_KEYS.map((k) => [k, true])));

const isGuest = (req) => !req.user || req.user.role === 'guest';

function wrap(fn) {
  return async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      console.error('Notifications route error:', err);
      res.status(500).json({ error: 'Something went wrong. Please try again.' });
    }
  };
}

function registeredOnly(req, res, next) {
  if (isGuest(req)) return res.status(403).json({ error: 'Please log in to manage notifications', code: 'LOGIN_REQUIRED' });
  return next();
}

function iso(v) {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** "n:34" / "b:12" (a bare number means "n") -> {kind, id}, or null. */
function parseItemId(raw) {
  const m = /^(?:([nb]):)?(\d{1,10})$/.exec(String(raw === undefined || raw === null ? '' : raw).trim());
  if (!m) return null;
  const id = Number(m[2]);
  if (!Number.isInteger(id) || id <= 0 || id > MAX_INT) return null;
  return { kind: m[1] || 'n', id };
}

function parseData(v) {
  if (v && typeof v === 'object') return v;
  if (typeof v === 'string') {
    try { const o = JSON.parse(v); return o && typeof o === 'object' ? o : {}; } catch (_) { return {}; }
  }
  return {};
}

function itemView(r) {
  const type = r.type || (r.kind === 'b' ? 'announcement' : 'inbox');
  return {
    id: `${r.kind}:${r.id}`,
    type,
    title: r.title,
    body: r.body || '',
    data: { ...parseData(r.data), type },
    read: r.read === true,
    createdAt: iso(r.created_at),
  };
}

async function unreadCount(userId) {
  const r = await db.query(
    `/*q:notifUnread*/ SELECT
       (SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND read_at IS NULL)
       + (SELECT COUNT(*) FROM broadcasts b JOIN users u ON u.id = $1
          WHERE b.created_at >= u.created_at
            AND NOT EXISTS (SELECT 1 FROM broadcast_reads br WHERE br.broadcast_id = b.id AND br.user_id = $1)
         ) AS unread`,
    [userId]
  );
  return Number(r.rows[0] && r.rows[0].unread) || 0;
}

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

// POST /api/notifications/devices {token, platform} -> upsert; a token moves to the current user.
router.post('/devices', authenticateToken, registeredOnly, wrap(async (req, res) => {
  const body = req.body || {};
  const token = typeof body.token === 'string' ? body.token.trim() : '';
  if (!token || token.length > 4096 || /\s/.test(token)) return res.status(400).json({ error: 'A valid device token is required' });
  const platform = body.platform === undefined || body.platform === null ? 'android' : String(body.platform).toLowerCase();
  if (!PLATFORMS.includes(platform)) return res.status(400).json({ error: 'platform must be android or ios' });
  await db.query(
    `/*q:tokenUpsert*/ INSERT INTO device_tokens (token, user_id, platform, updated_at)
     VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
     ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = CURRENT_TIMESTAMP`,
    [token, req.user.userId, platform]
  );
  res.json({ success: true });
}));

// DELETE /api/notifications/devices {token} (on logout). Only removes the caller's own token.
router.delete('/devices', authenticateToken, registeredOnly, wrap(async (req, res) => {
  const token = typeof (req.body || {}).token === 'string' ? req.body.token.trim() : '';
  if (!token || token.length > 4096) return res.status(400).json({ error: 'A valid device token is required' });
  await db.query('/*q:tokenDelete*/ DELETE FROM device_tokens WHERE token = $1 AND user_id = $2', [token, req.user.userId]);
  res.json({ success: true });
}));

// ---------------------------------------------------------------------------
// Inbox
// ---------------------------------------------------------------------------

// GET /api/notifications?before=<item id>&limit=30
router.get('/', authenticateToken, wrap(async (req, res) => {
  if (isGuest(req)) return res.json({ items: [], unread: 0, hasMore: false });
  let limit = req.query.limit === undefined || req.query.limit === '' ? DEFAULT_LIMIT : Number(req.query.limit);
  if (!Number.isInteger(limit) || limit < 1) return res.status(400).json({ error: 'Invalid limit' });
  limit = Math.min(limit, MAX_LIMIT);
  let cursor = null;
  if (req.query.before !== undefined && req.query.before !== '') {
    cursor = parseItemId(req.query.before);
    if (!cursor) return res.status(400).json({ error: 'Invalid cursor' });
  }
  const userId = req.user.userId;
  const r = await db.query(
    `/*q:notifList*/ WITH items AS (
       SELECT 'n' AS kind, 1 AS rank, n.id, n.type, n.title, n.body, n.data, n.created_at, (n.read_at IS NOT NULL) AS read
       FROM notifications n WHERE n.user_id = $1
       UNION ALL
       SELECT 'b' AS kind, 0 AS rank, b.id, 'announcement' AS type, b.title, b.body, b.data, b.created_at,
              (br.user_id IS NOT NULL) AS read
       FROM broadcasts b
       JOIN users u ON u.id = $1
       LEFT JOIN broadcast_reads br ON br.broadcast_id = b.id AND br.user_id = $1
       WHERE b.created_at >= u.created_at
     ),
     cursor_row AS (
       SELECT created_at, 1 AS rank, id FROM notifications WHERE $2::text = 'n' AND id = $3 AND user_id = $1
       UNION ALL
       SELECT created_at, 0 AS rank, id FROM broadcasts WHERE $2::text = 'b' AND id = $3
     )
     SELECT kind, id, type, title, body, data, created_at, read FROM items
     WHERE $2::text IS NULL OR (created_at, rank, id) < (SELECT created_at, rank, id FROM cursor_row LIMIT 1)
     ORDER BY created_at DESC, rank DESC, id DESC
     LIMIT $4`,
    [userId, cursor ? cursor.kind : null, cursor ? cursor.id : null, limit + 1]
  );
  const rows = r.rows.slice(0, limit);
  res.json({ items: rows.map(itemView), unread: await unreadCount(userId), hasMore: r.rows.length > limit });
}));

// GET /api/notifications/unread-count
router.get('/unread-count', authenticateToken, wrap(async (req, res) => {
  if (isGuest(req)) return res.json({ unread: 0 });
  res.json({ unread: await unreadCount(req.user.userId) });
}));

// POST /api/notifications/read {ids:["n:34","b:12"]} or {all:true}
router.post('/read', authenticateToken, registeredOnly, wrap(async (req, res) => {
  const body = req.body || {};
  const userId = req.user.userId;
  if (body.all === true) {
    await db.query('/*q:readAllNotifs*/ UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND read_at IS NULL', [userId]);
    await db.query(
      `/*q:readAllBroadcasts*/ INSERT INTO broadcast_reads (user_id, broadcast_id)
       SELECT $1, b.id FROM broadcasts b JOIN users u ON u.id = $1 WHERE b.created_at >= u.created_at
       ON CONFLICT DO NOTHING`,
      [userId]
    );
    return res.json({ success: true, unread: await unreadCount(userId) });
  }
  if (!Array.isArray(body.ids) || body.ids.length > MAX_READ_IDS) {
    return res.status(400).json({ error: `Send ids (at most ${MAX_READ_IDS}) or all: true` });
  }
  const n = new Set();
  const b = new Set();
  for (const raw of body.ids) {
    const p = parseItemId(raw);
    if (!p) return res.status(400).json({ error: 'Invalid notification id' });
    (p.kind === 'b' ? b : n).add(p.id);
  }
  if (n.size) {
    await db.query(
      '/*q:readNotifs*/ UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND id = ANY($2::int[]) AND read_at IS NULL',
      [userId, [...n]]
    );
  }
  if (b.size) {
    await db.query(
      `/*q:readBroadcasts*/ INSERT INTO broadcast_reads (user_id, broadcast_id)
       SELECT $1, b.id FROM broadcasts b JOIN users u ON u.id = $1
       WHERE b.id = ANY($2::int[]) AND b.created_at >= u.created_at
       ON CONFLICT DO NOTHING`,
      [userId, [...b]]
    );
  }
  res.json({ success: true, unread: await unreadCount(userId) });
}));

// ---------------------------------------------------------------------------
// Preferences (gate push sends server side; inbox rows are stored regardless)
// ---------------------------------------------------------------------------

function prefsView(row) {
  const out = { ...DEFAULT_PREFS };
  if (row) for (const k of PREF_KEYS) out[k] = row[k] !== false;
  return out;
}

router.get('/prefs', authenticateToken, wrap(async (req, res) => {
  if (isGuest(req)) return res.json({ ...DEFAULT_PREFS });
  const r = await db.query(
    `/*q:prefsGet*/ SELECT ${PREF_KEYS.join(', ')} FROM notification_prefs WHERE user_id = $1`,
    [req.user.userId]
  );
  res.json(prefsView(r.rows[0]));
}));

router.put('/prefs', authenticateToken, registeredOnly, wrap(async (req, res) => {
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const values = [];
  for (const k of PREF_KEYS) {
    if (body[k] === undefined || body[k] === null) { values.push(null); continue; }
    if (typeof body[k] !== 'boolean') return res.status(400).json({ error: `${k} must be true or false` });
    values.push(body[k]);
  }
  const cols = PREF_KEYS.join(', ');
  const inserts = PREF_KEYS.map((_, i) => `COALESCE($${i + 2}::boolean, TRUE)`).join(', ');
  const updates = PREF_KEYS.map((k, i) => `${k} = COALESCE($${i + 2}::boolean, notification_prefs.${k})`).join(', ');
  const r = await db.query(
    `/*q:prefsUpsert*/ INSERT INTO notification_prefs (user_id, ${cols}) VALUES ($1, ${inserts})
     ON CONFLICT (user_id) DO UPDATE SET ${updates}, updated_at = CURRENT_TIMESTAMP
     RETURNING ${cols}`,
    [req.user.userId, ...values]
  );
  res.json(prefsView(r.rows[0]));
}));

router._internals = { parseItemId, itemView, DEFAULT_PREFS };
module.exports = router;
