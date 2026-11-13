// Admin: one user in detail + control actions, and the cross-user chats / kundlis / audit lists.
// Mounted inside routes/admin.js after requireAdmin, so every route here needs the x-admin-key.
//   GET    /api/admin/users/:id                       profile, birth, kundli, activity, AI, auth events
//   GET    /api/admin/users/:id/requests?day=&limit=  API request log for one IST day (newest first)
//   GET    /api/admin/users/:id/chats?before=&limit=  AI chat transcript, newest first, paged by id
//   POST   /api/admin/users/:id/block {reason}        suspend (auth.js rejects blocked sessions)
//   POST   /api/admin/users/:id/unblock
//   POST   /api/admin/users/:id/coins {amount, note}  ledger grant / debit (never below 0)
//   POST   /api/admin/users/:id/notify {title, body}  inbox row + push
//   DELETE /api/admin/users/:id/chats                 clear AI chat history
//   DELETE /api/admin/users/:id {confirm:"DELETE"}    delete the account (not pandits)
//   GET    /api/admin/chats?days=&q=&limit=           latest AI conversations, one row per user
//   GET    /api/admin/kundlis?q=&limit=               kundlis, newest first
//   GET    /api/admin/audit?limit=&userId=            admin_audit log
// Every control action writes one admin_audit row, in the same transaction as the change where
// there is one, so the log can never claim something that was rolled back.
// SQL is /*q:name*/-tagged so the stub db in test/admin_users.test.js can answer by name.
const express = require('express');
const db = require('../db');
const C = require('../services/coins_service');
const push = require('../services/push_service');
const { range, isGuest } = require('./admin_analytics')._internals;

const router = express.Router();
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
// ts($n): start of the IST day held in parameter $n, as a timestamptz (same as admin_analytics).
const ts = (n) => `($${n}::date::timestamp AT TIME ZONE 'Asia/Kolkata')`;
const COIN_REASON = 'admin';
const NOTIFY_TITLE_MAX = 80;
const NOTIFY_BODY_MAX = 300;
const BLOCK_REASON_MAX = 300;
const COIN_NOTE_MAX = 200;
const COIN_AMOUNT_MAX = 100000;
const PREVIEW_CHARS = 300;

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
      console.error('Admin users error:', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  };
}

const num = (x) => Number(x) || 0;
const iso = (d) => (d instanceof Date ? d.toISOString() : d || null);
const isoDate = (v) => (!v ? null : v instanceof Date ? v.toISOString().slice(0, 10) : String(v).slice(0, 10));
const notFound = () => new AdminError(404, 'USER_NOT_FOUND', 'User not found');

function userId(req) {
  const n = Number(req.params.id);
  if (!/^\d{1,10}$/.test(String(req.params.id)) || !Number.isInteger(n) || n <= 0 || n > 2147483647) throw notFound();
  return n;
}

// Integer query param clamped to [min, max]; junk -> fallback.
function intParam(x, fallback, min, max) {
  const n = Number.parseInt(x, 10);
  return Number.isInteger(n) ? Math.min(Math.max(n, min), max) : fallback;
}

// Required text field: whitespace collapsed (multi-line allowed when keepLines), 1..max chars.
function text(value, max, code, label, keepLines = false) {
  const s = typeof value === 'string'
    ? (keepLines ? value.replace(/[ \t]+/g, ' ') : value.replace(/\s+/g, ' ')).trim()
    : '';
  if (!s || s.length > max) throw new AdminError(400, code, `${label} must be 1 to ${max} characters`);
  return s;
}

function likePattern(q) {
  const raw = typeof q === 'string' ? q.trim().slice(0, 100) : '';
  return raw ? `%${raw.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : '';
}

// Real calendar day, so '2026-02-31' is refused instead of silently rolling into March.
function validDay(s) {
  if (!DAY_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

// Lazy so this router loads even before services/user_blocks.js exists; refresh() only clears
// this instance's cache, other serverless instances pick the change up within their 30 s refresh.
function refreshBlocks() {
  try {
    require('../services/user_blocks').refresh();
  } catch (err) {
    console.warn('user_blocks refresh failed:', err.message);
  }
}

async function audit(client, action, targetUserId, details) {
  const r = await client.query(
    `/*q:auditInsert*/ INSERT INTO admin_audit (action, target_user_id, details) VALUES ($1, $2, $3::jsonb) RETURNING id`,
    [action, targetUserId, JSON.stringify(details || {})]
  );
  return r.rows[0] ? Number(r.rows[0].id) : null;
}

const USER_SELECT = `
  SELECT u.id, u.full_name, u.email, u.role, u.created_at, u.wallet_balance, u.invite_code,
         (u.google_id IS NOT NULL) AS google_linked, u.signup_method, u.last_login_method, u.last_login_at,
         u.is_blocked, u.blocked_reason, u.blocked_at, ${isGuest('u.')} AS is_guest,
         (SELECT COALESCE(SUM(amount), 0) FROM coin_ledger WHERE user_id = u.id) AS coins
  FROM users u WHERE u.id = $1`;

function userView(u) {
  return {
    id: Number(u.id),
    name: u.full_name || null,
    email: u.email || null,
    role: u.is_guest ? 'guest' : u.role || 'user',
    isGuest: !!u.is_guest,
    signupMethod: u.signup_method || null,
    lastLoginMethod: u.last_login_method || null,
    lastLoginAt: iso(u.last_login_at),
    createdAt: iso(u.created_at),
    isBlocked: !!u.is_blocked,
    blockedReason: u.blocked_reason || null,
    blockedAt: iso(u.blocked_at),
    googleLinked: !!u.google_linked,
    coins: num(u.coins),
    walletBalance: num(u.wallet_balance),
    inviteCode: u.invite_code || null,
  };
}

async function loadUser(client, id) {
  const r = await client.query(`/*q:userSelect*/ ${USER_SELECT}`, [id]);
  if (!r.rows[0]) throw notFound();
  return userView(r.rows[0]);
}

// ---------------------------------------------------------------------------
// Read endpoints
// ---------------------------------------------------------------------------

router.get('/users/:id', handle(async (req) => {
  const id = userId(req);
  const user = await loadUser(db, id);
  const { today, start } = range({ query: { days: 30 } });

  const [birth, kundli, family, act, chats, ai, todayRoutes, aiFeatures, authEvents, daily, buddy] = await Promise.all([
    db.query(
      `/*q:birth*/ SELECT full_name, gender, date_of_birth, time_of_birth, place_of_birth, latitude, longitude, timezone
       FROM birth_details WHERE user_id = $1`, [id]),
    db.query(
      `/*q:kundli*/ SELECT ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada, created_at, updated_at,
              (ai_report IS NOT NULL AND ai_report <> '') AS has_ai_report
       FROM kundlis WHERE user_id = $1`, [id]),
    db.query(
      `/*q:family*/ SELECT id, full_name, relationship, date_of_birth, place_of_birth, created_at
       FROM family_kundlis WHERE user_id = $1 ORDER BY id LIMIT 100`, [id]),
    // daily_activity rather than api_requests: it holds the full history (api_requests is
    // pruned at 90 days and only exists since request logging started).
    db.query(
      `/*q:activityStats*/ SELECT COALESCE(SUM(requests), 0) AS total_requests,
              COALESCE(SUM(requests) FILTER (WHERE day = $2::date), 0) AS requests_today,
              COUNT(DISTINCT day) AS active_days, MIN(first_seen) AS first_seen, MAX(last_seen) AS last_seen,
              array_remove(array_agg(DISTINCT platform), NULL) AS platforms
       FROM daily_activity WHERE user_id = $1`, [id, today]),
    db.query(`/*q:chatCount*/ SELECT COUNT(*) AS n FROM chat_messages WHERE user_id = $1 AND role <> 'system'`, [id]),
    db.query(
      `/*q:aiTotals*/ SELECT COUNT(*) AS calls, COALESCE(SUM(total_tokens), 0) AS tokens, COALESCE(SUM(cost_usd), 0) AS cost
       FROM ai_usage WHERE user_id = $1`, [id]),
    db.query(
      `/*q:todayByRoute*/ SELECT method, route, COUNT(*) AS calls, COUNT(*) FILTER (WHERE status >= 400) AS errors,
              MAX(created_at) AS last_at
       FROM api_requests WHERE user_id = $1 AND created_at >= ${ts(2)}
       GROUP BY method, route ORDER BY calls DESC, last_at DESC LIMIT 200`, [id, today]),
    db.query(
      `/*q:aiByFeature*/ SELECT feature, COUNT(*) AS calls, COALESCE(SUM(total_tokens), 0) AS tokens,
              COALESCE(SUM(cost_usd), 0) AS cost
       FROM ai_usage WHERE user_id = $1 GROUP BY feature ORDER BY cost DESC, calls DESC LIMIT 50`, [id]),
    db.query(
      `/*q:authEvents*/ SELECT event, method, platform, created_at FROM auth_events
       WHERE user_id = $1 ORDER BY id DESC LIMIT 30`, [id]),
    db.query(
      `/*q:activityDaily*/ SELECT day::text AS day, COALESCE(SUM(requests), 0) AS requests,
              array_agg(DISTINCT platform) AS platforms
       FROM daily_activity WHERE user_id = $1 AND day >= $2::date GROUP BY day ORDER BY day`, [id, start]),
    db.query(`/*q:buddy*/ SELECT display_name, is_active, banned_at FROM buddy_profiles WHERE user_id = $1`, [id]),
  ]);

  const b = birth.rows[0];
  const k = kundli.rows[0];
  const s = act.rows[0] || {};
  const a = ai.rows[0] || {};
  const bp = buddy.rows[0];
  return {
    user,
    birth: b ? {
      fullName: b.full_name || null,
      gender: b.gender || null,
      dateOfBirth: isoDate(b.date_of_birth),
      timeOfBirth: b.time_of_birth || null,
      placeOfBirth: b.place_of_birth || null,
      latitude: b.latitude === null || b.latitude === undefined ? null : Number(b.latitude),
      longitude: b.longitude === null || b.longitude === undefined ? null : Number(b.longitude),
      timezone: b.timezone || null,
    } : null,
    kundli: k ? {
      ascendant: k.ascendant, sunSign: k.sun_sign, moonSign: k.moon_sign, nakshatra: k.nakshatra,
      nakshatraPada: k.nakshatra_pada === null || k.nakshatra_pada === undefined ? null : Number(k.nakshatra_pada),
      createdAt: iso(k.created_at), updatedAt: iso(k.updated_at), hasAiReport: !!k.has_ai_report,
    } : null,
    familyKundlis: family.rows.map((f) => ({
      id: Number(f.id), name: f.full_name, relation: f.relationship,
      dateOfBirth: isoDate(f.date_of_birth), placeOfBirth: f.place_of_birth || null, createdAt: iso(f.created_at),
    })),
    stats: {
      totalRequests: num(s.total_requests),
      requestsToday: num(s.requests_today),
      activeDays: num(s.active_days),
      firstSeen: iso(s.first_seen),
      lastSeen: iso(s.last_seen),
      platforms: Array.isArray(s.platforms) ? s.platforms : [],
      chatMessages: num(chats.rows[0] && chats.rows[0].n),
      aiCalls: num(a.calls),
      aiTokens: num(a.tokens),
      aiCostUsd: num(a.cost),
    },
    todayByRoute: todayRoutes.rows.map((r) => ({
      method: r.method, route: r.route, calls: num(r.calls), errors: num(r.errors), lastAt: iso(r.last_at),
    })),
    aiByFeature: aiFeatures.rows.map((r) => ({ feature: r.feature, calls: num(r.calls), tokens: num(r.tokens), costUsd: num(r.cost) })),
    authEvents: authEvents.rows.map((r) => ({ event: r.event, method: r.method, platform: r.platform || null, at: iso(r.created_at) })),
    activityDaily: daily.rows.map((r) => ({
      day: isoDate(r.day), requests: num(r.requests), platforms: Array.isArray(r.platforms) ? r.platforms.filter(Boolean) : [],
    })),
    buddy: bp ? { displayName: bp.display_name, isActive: bp.is_active !== false, bannedAt: iso(bp.banned_at) } : null,
  };
}));

// GET /api/admin/users/:id/requests?day=YYYY-MM-DD&limit=200
router.get('/users/:id/requests', handle(async (req) => {
  const id = userId(req);
  const { today } = range({ query: {} });
  const day = req.query.day === undefined || req.query.day === '' ? today : String(req.query.day);
  if (!validDay(day)) throw new AdminError(400, 'BAD_DAY', 'day must be a date like 2026-11-12');
  const limit = intParam(req.query.limit, 200, 1, 1000);
  const r = await db.query(
    `/*q:userRequests*/ SELECT method, route, status, duration_ms, platform, app_version, created_at FROM api_requests
     WHERE user_id = $1 AND created_at >= ${ts(2)} AND created_at < ${ts(2)} + INTERVAL '1 day'
     ORDER BY created_at DESC, id DESC LIMIT $3`,
    [id, day, limit]
  );
  return {
    day,
    requests: r.rows.map((x) => ({
      at: iso(x.created_at), method: x.method, route: x.route, status: num(x.status), ms: num(x.duration_ms), platform: x.platform,
      appVersion: x.app_version || null,
    })),
  };
}));

// GET /api/admin/users/:id/chats?before=<messageId>&limit=100  (newest first; system prompts skipped)
router.get('/users/:id/chats', handle(async (req) => {
  const id = userId(req);
  let before = null;
  if (req.query.before !== undefined && req.query.before !== '') {
    before = Number(req.query.before);
    if (!/^\d{1,10}$/.test(String(req.query.before)) || before <= 0 || before > 2147483647) {
      throw new AdminError(400, 'BAD_CURSOR', 'before must be a message id');
    }
  }
  const limit = intParam(req.query.limit, 100, 1, 200);
  // One extra row tells us whether an older page exists.
  const r = await db.query(
    `/*q:userChats*/ SELECT id, role, content, astrologer_name, specialty, created_at FROM chat_messages
     WHERE user_id = $1 AND role <> 'system' AND ($2::int IS NULL OR id < $2::int)
     ORDER BY id DESC LIMIT $3`,
    [id, before, limit + 1]
  );
  const rows = r.rows.slice(0, limit);
  return {
    messages: rows.map((m) => ({
      id: Number(m.id), role: m.role, content: m.content,
      astrologerName: m.astrologer_name || null, specialty: m.specialty || null, at: iso(m.created_at),
    })),
    hasMore: r.rows.length > limit,
  };
}));

// GET /api/admin/chats?days=30&q=&limit=50: one row per user, latest activity first. With q, only
// matching messages count and pick the users; the previews are still each user's latest messages.
router.get('/chats', handle(async (req) => {
  const { days, start } = range(req);
  const q = likePattern(req.query.q);
  const limit = intParam(req.query.limit, 50, 1, 200);
  const r = await db.query(
    `/*q:chatList*/ WITH m AS (
       SELECT user_id, COUNT(*) AS messages, MAX(created_at) AS last_at
       FROM chat_messages
       WHERE user_id IS NOT NULL AND role <> 'system' AND created_at >= ${ts(1)}
         AND ($2 = '' OR content ILIKE $2)
       GROUP BY user_id ORDER BY last_at DESC LIMIT $3)
     SELECT m.user_id, m.messages, m.last_at, u.full_name, u.email, ${isGuest('u.')} AS is_guest,
            (SELECT LEFT(c.content, ${PREVIEW_CHARS}) FROM chat_messages c
              WHERE c.user_id = m.user_id AND c.role = 'user' ORDER BY c.id DESC LIMIT 1) AS last_user,
            (SELECT LEFT(c.content, ${PREVIEW_CHARS}) FROM chat_messages c
              WHERE c.user_id = m.user_id AND c.role = 'assistant' ORDER BY c.id DESC LIMIT 1) AS last_assistant
     FROM m JOIN users u ON u.id = m.user_id
     ORDER BY m.last_at DESC`,
    [start, q, limit]
  );
  return {
    days, start,
    conversations: r.rows.map((x) => ({
      userId: Number(x.user_id),
      userName: x.full_name || null,
      email: x.is_guest ? null : x.email || null,
      messages: num(x.messages),
      lastAt: iso(x.last_at),
      lastUserMessage: x.last_user || null,
      lastAssistantMessage: x.last_assistant || null,
    })),
  };
}));

// GET /api/admin/kundlis?q=&limit=100  (q matches name, email or place of birth)
router.get('/kundlis', handle(async (req) => {
  const q = likePattern(req.query.q);
  const limit = intParam(req.query.limit, 100, 1, 500);
  const r = await db.query(
    `/*q:kundliList*/ SELECT k.user_id, u.full_name, u.email, ${isGuest('u.')} AS is_guest,
            k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, b.place_of_birth, b.date_of_birth, k.created_at,
            (SELECT COUNT(*) FROM family_kundlis f WHERE f.user_id = k.user_id) AS family_count,
            COUNT(*) OVER () AS total
     FROM kundlis k
     JOIN users u ON u.id = k.user_id
     LEFT JOIN birth_details b ON b.user_id = k.user_id
     WHERE ($1 = '' OR u.full_name ILIKE $1 OR u.email ILIKE $1 OR b.place_of_birth ILIKE $1)
     ORDER BY k.created_at DESC NULLS LAST, k.id DESC
     LIMIT $2`,
    [q, limit]
  );
  return {
    total: r.rows.length ? num(r.rows[0].total) : 0,
    kundlis: r.rows.map((x) => ({
      userId: Number(x.user_id),
      userName: x.full_name || null,
      email: x.is_guest ? null : x.email || null,
      ascendant: x.ascendant, sunSign: x.sun_sign, moonSign: x.moon_sign, nakshatra: x.nakshatra,
      placeOfBirth: x.place_of_birth || null,
      dateOfBirth: isoDate(x.date_of_birth),
      createdAt: iso(x.created_at),
      familyCount: num(x.family_count),
    })),
  };
}));

// GET /api/admin/audit?limit=100&userId=  (userId optional: one user's entries)
router.get('/audit', handle(async (req) => {
  const limit = intParam(req.query.limit, 100, 1, 500);
  let target = null;
  if (req.query.userId !== undefined && req.query.userId !== '') {
    target = Number(req.query.userId);
    if (!Number.isInteger(target) || target <= 0 || target > 2147483647) throw new AdminError(400, 'BAD_USER', 'userId must be a user id');
  }
  const r = await db.query(
    `/*q:auditList*/ SELECT id, action, target_user_id, details, created_at FROM admin_audit
     WHERE ($1::int IS NULL OR target_user_id = $1::int) ORDER BY id DESC LIMIT $2`,
    [target, limit]
  );
  return {
    entries: r.rows.map((x) => ({
      id: Number(x.id),
      action: x.action,
      targetUserId: x.target_user_id === null || x.target_user_id === undefined ? null : Number(x.target_user_id),
      details: x.details && typeof x.details === 'object' ? x.details : (() => { try { return JSON.parse(x.details || '{}'); } catch (_) { return {}; } })(),
      at: iso(x.created_at),
    })),
  };
}));

// ---------------------------------------------------------------------------
// Control actions
// ---------------------------------------------------------------------------

// POST /api/admin/users/:id/block {reason}
router.post('/users/:id/block', handle(async (req) => {
  const id = userId(req);
  const reason = text((req.body || {}).reason, BLOCK_REASON_MAX, 'BAD_REASON', 'reason');
  const user = await db.withTransaction(async (client) => {
    const upd = await client.query(
      `/*q:block*/ UPDATE users SET is_blocked = TRUE, blocked_reason = $2, blocked_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING id`,
      [id, reason]
    );
    if (!upd.rows[0]) throw notFound();
    await audit(client, 'block', id, { reason });
    return loadUser(client, id);
  });
  refreshBlocks(); // after commit, so the cache never reloads the pre-change set
  return { user };
}));

// POST /api/admin/users/:id/unblock
router.post('/users/:id/unblock', handle(async (req) => {
  const id = userId(req);
  const user = await db.withTransaction(async (client) => {
    const upd = await client.query(
      `/*q:unblock*/ UPDATE users SET is_blocked = FALSE, blocked_reason = NULL, blocked_at = NULL
       WHERE id = $1 RETURNING id`,
      [id]
    );
    if (!upd.rows[0]) throw notFound();
    await audit(client, 'unblock', id, {});
    return loadUser(client, id);
  });
  refreshBlocks();
  return { user };
}));

// POST /api/admin/users/:id/coins {amount, note}
// Positive: a grant. Negative: a debit, refused (409) if it would take the balance below 0.
// The users row is locked first, the same lock /api/trips takes before spending, so a trip
// purchase and an admin debit can never both pass their balance checks.
router.post('/users/:id/coins', handle(async (req) => {
  const id = userId(req);
  const b = req.body || {};
  const amount = typeof b.amount === 'number' || (typeof b.amount === 'string' && /^-?\d+$/.test(b.amount.trim()))
    ? Number(b.amount) : NaN;
  if (!Number.isInteger(amount) || amount === 0 || Math.abs(amount) > COIN_AMOUNT_MAX) {
    throw new AdminError(400, 'BAD_AMOUNT', `amount must be a non-zero whole number between -${COIN_AMOUNT_MAX} and ${COIN_AMOUNT_MAX}`);
  }
  const note = text(b.note, COIN_NOTE_MAX, 'BAD_NOTE', 'note');
  return db.withTransaction(async (client) => {
    const lock = await client.query('/*q:userLock*/ SELECT id, role FROM users WHERE id = $1 FOR UPDATE', [id]);
    if (!lock.rows[0]) throw notFound();
    const before = await C.balanceOf(client, id);
    if (before + amount < 0) {
      throw new AdminError(409, 'INSUFFICIENT_COINS', `This user has only ${before} coins, so at most ${before} can be removed.`);
    }
    // The audit id makes the ledger ref unique, so the ledger's (user, reason, ref) guard never
    // swallows a second adjustment with the same amount.
    const auditId = await audit(client, 'coins', id, { amount, note, balanceBefore: before, balanceAfter: before + amount });
    const applied = await C.awardCoins(client, id, amount, COIN_REASON, `admin:${auditId}`, `Admin: ${note}`);
    if (applied !== amount) throw new Error('admin coin ledger row was not written');
    return { coins: await C.balanceOf(client, id) };
  });
}));

// POST /api/admin/users/:id/notify {title, body}: inbox row + push to the user's devices.
// `sent` is true when the message reached the user (stored in their inbox or pushed to a device).
router.post('/users/:id/notify', handle(async (req) => {
  const id = userId(req);
  const b = req.body || {};
  const title = text(b.title, NOTIFY_TITLE_MAX, 'BAD_TITLE', 'title');
  const body = text(b.body, NOTIFY_BODY_MAX, 'BAD_BODY', 'body', true);
  const exists = await db.query('/*q:userExists*/ SELECT id FROM users WHERE id = $1', [id]);
  if (!exists.rows[0]) throw notFound();
  const r = await push.sendToUser(id, { type: 'admin_message', title, body, data: {} });
  const devices = num(r && r.sent);
  const sent = !!(r && !r.error && !r.timedOut && (r.inboxId || devices > 0));
  await audit(db, 'notify', id, { title, body, sent, devices });
  return { sent, devices };
}));

// DELETE /api/admin/users/:id/chats: clears the AI astrologer history.
router.delete('/users/:id/chats', handle(async (req) => {
  const id = userId(req);
  return db.withTransaction(async (client) => {
    const exists = await client.query('/*q:userLock*/ SELECT id, role FROM users WHERE id = $1 FOR UPDATE', [id]);
    if (!exists.rows[0]) throw notFound();
    const del = await client.query('/*q:clearChats*/ DELETE FROM chat_messages WHERE user_id = $1', [id]);
    const deleted = num(del.rowCount);
    await audit(client, 'clear_chats', id, { deleted });
    return { deleted };
  });
}));

// DELETE /api/admin/users/:id {confirm:"DELETE"}
// Same steps as the user's own DELETE /api/auth/account (children first, so it never depends on
// ON DELETE CASCADE existing on older tables), plus the audit row, in one transaction. Pandits are
// refused like there: their row cascades into other seekers' sessions and wallet history.
router.delete('/users/:id', handle(async (req) => {
  const id = userId(req);
  if ((req.body || {}).confirm !== 'DELETE') {
    throw new AdminError(400, 'CONFIRM_REQUIRED', 'To delete this user, send confirm: "DELETE".');
  }
  const steps = (() => {
    try { return require('./auth').router._accountDeleteSteps || []; } catch (_) { return []; }
  })();
  await db.withTransaction(async (client) => {
    const lock = await client.query('/*q:userLock*/ SELECT id, role, email, full_name FROM users WHERE id = $1 FOR UPDATE', [id]);
    const u = lock.rows[0];
    if (!u) throw notFound();
    const pandit = await client.query('/*q:panditOf*/ SELECT id FROM pandits WHERE user_id = $1', [id]);
    if (u.role === 'pandit' || pandit.rows.length) {
      throw new AdminError(409, 'PANDIT_ACCOUNT', 'Pandit accounts cannot be deleted from the dashboard.');
    }
    const tables = [...new Set(steps.map(([t]) => t))];
    if (tables.length) {
      const present = await client.query(
        `/*q:tablesPresent*/ SELECT table_name FROM information_schema.tables
         WHERE table_schema = current_schema() AND table_name = ANY($1)`,
        [tables]
      );
      const existing = new Set(present.rows.map((r) => r.table_name));
      for (const [table, sql] of steps) {
        if (existing.has(table)) await client.query(sql, [id]);
      }
    }
    await client.query('/*q:deleteUser*/ DELETE FROM users WHERE id = $1', [id]);
    // admin_audit has no FK to users, so this row outlives the account.
    await audit(client, 'delete_user', id, { email: u.email || null, name: u.full_name || null, role: u.role || null });
  });
  refreshBlocks(); // a deleted blocked user no longer needs to be in the cached set
  return { deleted: true };
}));

router._internals = { validDay, likePattern, userView, COIN_REASON };
module.exports = router;
