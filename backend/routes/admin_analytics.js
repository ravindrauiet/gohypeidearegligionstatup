// Admin analytics API (/api/admin/analytics), read by the dashboard page (GET /admin/dashboard).
// requireAdmin in routes/admin.js guards every route here. Days are IST calendar days.
//   GET /api/admin/analytics?days=30                     overview, platforms, daily series, AI by feature
//   GET /api/admin/analytics/users?days=30&sort=cost&q=  per-user activity and AI spend (100 rows)
//   GET /api/admin/analytics/endpoints?days=30           API traffic per route (api_requests)
//   GET /api/admin/analytics/logins?days=30              signups / logins / failures (auth_events)
//   GET /api/admin/analytics/live                        last few minutes of API requests
const express = require('express');
const db = require('../db');
const { istDate } = require('../services/coins_service');

const router = express.Router();
const DAY_MS = 24 * 60 * 60 * 1000;
// ts($n): start of the IST day held in parameter $n, as a timestamptz.
const ts = (n) => `($${n}::date::timestamp AT TIME ZONE 'Asia/Kolkata')`;
const IST_DAY = (col) => `(${col} AT TIME ZONE 'Asia/Kolkata')::date`;
// Guests: role 'guest', plus older guest accounts created with role 'user' and a
// guest_<n>@...astroai.com address (registering replaces the address, so real users never match).
const isGuest = (t = '') => `COALESCE(${t}role = 'guest' OR ${t}email ILIKE 'guest\\_%@%astroai.com', FALSE)`;
const NOT_GUEST = `NOT ${isGuest()}`;

function range(req, now = new Date()) {
  const n = Number.parseInt(req.query.days, 10);
  const days = Number.isInteger(n) ? Math.min(Math.max(n, 1), 365) : 30;
  return { days, today: istDate(now), start: istDate(new Date(now.getTime() - (days - 1) * DAY_MS)) };
}

const num = (x) => Number(x) || 0;
const iso = (d) => (d instanceof Date ? d.toISOString() : d || null);
const usdToInr = () => {
  const r = Number(process.env.AI_USD_TO_INR);
  return Number.isFinite(r) && r > 0 ? r : 88;
};

function handle(fn) {
  return async (req, res) => {
    try {
      res.json(await fn(req));
    } catch (err) {
      console.error('Admin analytics error:', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  };
}

router.get('/', handle(async (req) => {
  const { days, today, start } = range(req);
  const p = [today, start];

  const [overview, platforms, ai, daily, features] = await Promise.all([
    db.query(
      `SELECT
         (SELECT COUNT(*) FROM users WHERE ${NOT_GUEST}) AS users_total,
         (SELECT COUNT(*) FROM users WHERE ${isGuest()}) AS guests_total,
         (SELECT COUNT(*) FROM users WHERE ${NOT_GUEST} AND created_at >= ${ts(1)}) AS signups_today,
         (SELECT COUNT(*) FROM users WHERE ${NOT_GUEST} AND created_at >= ${ts(2)}) AS signups_range,
         (SELECT COUNT(DISTINCT visitor_key) FROM daily_activity WHERE day = $1::date) AS active_today,
         (SELECT COUNT(DISTINCT visitor_key) FROM daily_activity WHERE day >= $2::date) AS active_range`,
      p
    ),
    db.query(
      `SELECT platform,
              COUNT(DISTINCT visitor_key) FILTER (WHERE day = $1::date) AS active_today,
              COUNT(DISTINCT visitor_key) AS active_range,
              COALESCE(SUM(opens), 0) AS opens,
              COALESCE(SUM(requests), 0) AS requests
       FROM daily_activity WHERE day >= $2::date
       GROUP BY platform ORDER BY active_range DESC`,
      p
    ),
    db.query(
      `SELECT
         COUNT(*) FILTER (WHERE created_at >= ${ts(1)}) AS calls_today,
         COALESCE(SUM(total_tokens) FILTER (WHERE created_at >= ${ts(1)}), 0) AS tokens_today,
         COALESCE(SUM(cost_usd) FILTER (WHERE created_at >= ${ts(1)}), 0) AS cost_today,
         COUNT(*) FILTER (WHERE created_at >= ${ts(2)}) AS calls_range,
         COALESCE(SUM(total_tokens) FILTER (WHERE created_at >= ${ts(2)}), 0) AS tokens_range,
         COALESCE(SUM(cost_usd) FILTER (WHERE created_at >= ${ts(2)}), 0) AS cost_range,
         COUNT(DISTINCT user_id) FILTER (WHERE created_at >= ${ts(2)}) AS users_range,
         COUNT(*) AS calls_all,
         COALESCE(SUM(total_tokens), 0) AS tokens_all,
         COALESCE(SUM(cost_usd), 0) AS cost_all
       FROM ai_usage`,
      p
    ),
    db.query(
      `WITH d AS (SELECT generate_series($2::date, $1::date, interval '1 day')::date AS day),
       act AS (
         SELECT day,
                COUNT(DISTINCT visitor_key) AS active,
                COUNT(DISTINCT visitor_key) FILTER (WHERE platform = 'web') AS web,
                COUNT(DISTINCT visitor_key) FILTER (WHERE platform IN ('android', 'ios', 'app')) AS app
         FROM daily_activity WHERE day >= $2::date GROUP BY day),
       su AS (
         SELECT ${IST_DAY('created_at')} AS day, COUNT(*) AS signups
         FROM users WHERE ${NOT_GUEST} AND created_at >= ${ts(2)} GROUP BY 1),
       ai AS (
         SELECT ${IST_DAY('created_at')} AS day, COUNT(*) AS calls, SUM(total_tokens) AS tokens, SUM(cost_usd) AS cost
         FROM ai_usage WHERE created_at >= ${ts(2)} GROUP BY 1)
       SELECT d.day::text AS day, act.active, act.web, act.app, su.signups, ai.calls, ai.tokens, ai.cost
       FROM d
       LEFT JOIN act ON act.day = d.day
       LEFT JOIN su ON su.day = d.day
       LEFT JOIN ai ON ai.day = d.day
       ORDER BY d.day`,
      p
    ),
    db.query(
      `SELECT feature, model, COUNT(*) AS calls,
              SUM(prompt_tokens) AS prompt_tokens, SUM(completion_tokens) AS completion_tokens,
              SUM(total_tokens) AS tokens, SUM(cost_usd) AS cost
       FROM ai_usage WHERE created_at >= ${ts(1)}
       GROUP BY feature, model ORDER BY cost DESC, calls DESC LIMIT 50`,
      [start]
    ),
  ]);

  const o = overview.rows[0] || {};
  const a = ai.rows[0] || {};
  return {
    days, today, start, usdToInr: usdToInr(),
    users: {
      total: num(o.users_total),
      guests: num(o.guests_total),
      signupsToday: num(o.signups_today),
      signupsInRange: num(o.signups_range),
      activeToday: num(o.active_today),
      activeInRange: num(o.active_range),
    },
    platforms: platforms.rows.map((r) => ({
      platform: r.platform,
      activeToday: num(r.active_today),
      activeInRange: num(r.active_range),
      opens: num(r.opens),
      requests: num(r.requests),
    })),
    ai: {
      today: { calls: num(a.calls_today), tokens: num(a.tokens_today), costUsd: num(a.cost_today) },
      inRange: { calls: num(a.calls_range), tokens: num(a.tokens_range), costUsd: num(a.cost_range), users: num(a.users_range) },
      allTime: { calls: num(a.calls_all), tokens: num(a.tokens_all), costUsd: num(a.cost_all) },
    },
    daily: daily.rows.map((r) => ({
      day: r.day,
      active: num(r.active), web: num(r.web), app: num(r.app),
      signups: num(r.signups),
      aiCalls: num(r.calls), aiTokens: num(r.tokens), aiCostUsd: num(r.cost),
    })),
    features: features.rows.map((r) => ({
      feature: r.feature, model: r.model, calls: num(r.calls),
      promptTokens: num(r.prompt_tokens), completionTokens: num(r.completion_tokens),
      tokens: num(r.tokens), costUsd: num(r.cost),
    })),
  };
}));

const SORTS = {
  cost: 'ai.cost DESC NULLS LAST, ai.tokens DESC NULLS LAST, u.id DESC',
  active: 'act.last_seen DESC NULLS LAST, u.id DESC',
  recent: 'u.created_at DESC NULLS LAST, u.id DESC',
};

router.get('/users', handle(async (req) => {
  const { days, start } = range(req);
  const sort = SORTS[req.query.sort] ? req.query.sort : 'cost';
  const raw = typeof req.query.q === 'string' ? req.query.q.trim().slice(0, 100) : '';
  const q = raw ? `%${raw.replace(/[\\%_]/g, (c) => `\\${c}`)}%` : '';
  const guests = req.query.guests === '1';

  const r = await db.query(
    `WITH ai AS (
       SELECT user_id, COUNT(*) AS calls, SUM(total_tokens) AS tokens, SUM(cost_usd) AS cost, MAX(created_at) AS last_ai
       FROM ai_usage WHERE user_id IS NOT NULL AND created_at >= ${ts(1)} GROUP BY user_id),
     act AS (
       SELECT user_id, MAX(last_seen) AS last_seen, COUNT(DISTINCT day) AS active_days,
              string_agg(DISTINCT platform, ', ') AS platforms
       FROM daily_activity WHERE user_id IS NOT NULL AND day >= $1::date GROUP BY user_id),
     req AS (
       SELECT user_id, COUNT(*) AS requests
       FROM api_requests WHERE user_id IS NOT NULL AND created_at >= ${ts(1)} GROUP BY user_id)
     SELECT u.id, u.full_name, u.email, u.role, u.created_at, ${isGuest('u.')} AS is_guest,
            u.signup_method, u.last_login_method, u.is_blocked,
            ai.calls, ai.tokens, ai.cost, ai.last_ai, act.last_seen, act.active_days, act.platforms,
            req.requests
     FROM users u
     LEFT JOIN ai ON ai.user_id = u.id
     LEFT JOIN act ON act.user_id = u.id
     LEFT JOIN req ON req.user_id = u.id
     WHERE ($2 = '' OR u.full_name ILIKE $2 OR u.email ILIKE $2)
       AND ($3 OR NOT ${isGuest('u.')})
     ORDER BY ${SORTS[sort]}
     LIMIT 100`,
    [start, q, guests]
  );
  return {
    days, start, sort, usdToInr: usdToInr(),
    users: r.rows.map((u) => ({
      id: u.id,
      name: u.full_name || null,
      email: u.is_guest ? null : u.email,
      role: u.is_guest ? 'guest' : u.role || 'user',
      createdAt: iso(u.created_at),
      lastSeen: iso(u.last_seen),
      activeDays: num(u.active_days),
      platforms: u.platforms || null,
      aiCalls: num(u.calls),
      aiTokens: num(u.tokens),
      aiCostUsd: num(u.cost),
      lastAi: iso(u.last_ai),
      signupMethod: u.signup_method || null,
      lastLoginMethod: u.last_login_method || null,
      isBlocked: !!u.is_blocked,
      requestsInRange: num(u.requests),
    })),
  };
}));

// API traffic per route over the range (top 100 by calls). errors = responses with status >= 400.
router.get('/endpoints', handle(async (req) => {
  const { days, today, start } = range(req);
  const p = [today, start];
  const [totals, routes] = await Promise.all([
    db.query(
      `/*q:endpointTotals*/ SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE created_at >= ${ts(1)}) AS today
       FROM api_requests WHERE created_at >= ${ts(2)}`,
      p
    ),
    db.query(
      `/*q:endpointRoutes*/ SELECT method, route, COUNT(*) AS calls,
              COUNT(*) FILTER (WHERE created_at >= ${ts(1)}) AS calls_today,
              COUNT(DISTINCT user_id) AS users,
              COUNT(*) FILTER (WHERE status >= 400) AS errors,
              AVG(duration_ms) AS avg_ms,
              percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95_ms
       FROM api_requests WHERE created_at >= ${ts(2)}
       GROUP BY method, route ORDER BY calls DESC, route LIMIT 100`,
      p
    ),
  ]);
  const t = totals.rows[0] || {};
  return {
    days, start, today,
    totalRequests: num(t.total),
    todayRequests: num(t.today),
    routes: routes.rows.map((r) => ({
      method: r.method, route: r.route,
      calls: num(r.calls), callsToday: num(r.calls_today), users: num(r.users), errors: num(r.errors),
      avgMs: Math.round(num(r.avg_ms)), p95Ms: Math.round(num(r.p95_ms)),
    })),
  };
}));

// Sign-ups and logins (auth_events) over the range. A signup is a new account of any kind:
// register, guest_created, or guest_upgraded (a guest turning into a real account).
router.get('/logins', handle(async (req) => {
  const { days, today, start } = range(req);
  const [byMethod, daily, methods] = await Promise.all([
    db.query(
      `/*q:loginsByMethod*/ SELECT method,
              COUNT(*) FILTER (WHERE event IN ('register', 'guest_created', 'guest_upgraded')) AS signups,
              COUNT(*) FILTER (WHERE event = 'login') AS logins,
              COUNT(*) FILTER (WHERE event = 'failed_login') AS failed,
              COUNT(*) FILTER (WHERE event = 'blocked') AS blocked
       FROM auth_events WHERE created_at >= ${ts(1)}
       GROUP BY method ORDER BY method`,
      [start]
    ),
    db.query(
      `/*q:loginsDaily*/ WITH d AS (SELECT generate_series($2::date, $1::date, interval '1 day')::date AS day),
       e AS (
         SELECT ${IST_DAY('created_at')} AS day,
                COUNT(*) FILTER (WHERE event = 'register') AS register,
                COUNT(*) FILTER (WHERE event = 'login') AS login,
                COUNT(*) FILTER (WHERE event = 'guest_created') AS guest_created,
                COUNT(*) FILTER (WHERE event = 'guest_upgraded') AS guest_upgraded,
                COUNT(*) FILTER (WHERE event = 'failed_login') AS failed,
                COUNT(*) FILTER (WHERE event = 'blocked') AS blocked
         FROM auth_events WHERE created_at >= ${ts(2)} GROUP BY 1)
       SELECT d.day::text AS day, e.register, e.login, e.guest_created, e.guest_upgraded, e.failed, e.blocked
       FROM d LEFT JOIN e ON e.day = d.day ORDER BY d.day`,
      [today, start]
    ),
    db.query(
      `/*q:signupMethods*/ SELECT COALESCE(signup_method, 'unknown') AS method, COUNT(*) AS users
       FROM users GROUP BY 1 ORDER BY users DESC`,
      []
    ),
  ]);
  return {
    days, start, today,
    byMethod: byMethod.rows.map((r) => ({
      method: r.method, signups: num(r.signups), logins: num(r.logins), failed: num(r.failed), blocked: num(r.blocked),
    })),
    daily: daily.rows.map((r) => ({
      day: r.day, register: num(r.register), login: num(r.login), guest_created: num(r.guest_created),
      guest_upgraded: num(r.guest_upgraded), failed: num(r.failed), blocked: num(r.blocked),
    })),
    signupMethods: methods.rows.map((r) => ({ method: r.method, users: num(r.users) })),
  };
}));

// The latest 50 API requests plus short-window counters; the Live tab polls this every 10 s.
router.get('/live', handle(async () => {
  const [counts, recent] = await Promise.all([
    db.query(
      `/*q:liveCounts*/ SELECT
         (SELECT COUNT(*) FROM api_requests WHERE created_at >= NOW() - INTERVAL '5 minutes') AS requests_5m,
         (SELECT COUNT(DISTINCT user_id) FROM api_requests
           WHERE user_id IS NOT NULL AND created_at >= NOW() - INTERVAL '15 minutes') AS users_15m`,
      []
    ),
    db.query(
      `/*q:liveRecent*/ SELECT a.created_at, a.user_id, u.full_name, a.method, a.route, a.status, a.duration_ms, a.platform
       FROM api_requests a LEFT JOIN users u ON u.id = a.user_id
       ORDER BY a.id DESC LIMIT 50`,
      []
    ),
  ]);
  const c = counts.rows[0] || {};
  return {
    requestsLast5m: num(c.requests_5m),
    activeUsersLast15m: num(c.users_15m),
    recent: recent.rows.map((r) => ({
      at: iso(r.created_at),
      userId: r.user_id === null || r.user_id === undefined ? null : Number(r.user_id),
      userName: r.full_name || null,
      method: r.method, route: r.route, status: num(r.status), ms: num(r.duration_ms), platform: r.platform,
    })),
  };
}));

router._internals = { range, isGuest };
module.exports = router;
