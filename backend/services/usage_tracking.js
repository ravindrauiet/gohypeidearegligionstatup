// Usage tracking for the admin dashboard (routes/admin_analytics.js).
//
// - requestContext: keeps the current request in AsyncLocalStorage, so code deep inside a
//   request (openai_client.js) can tell which user and feature an AI call belongs to.
// - trackActivity: marks the caller active for today (IST) on their platform in daily_activity.
//   Each server instance writes a given (day, person, platform) row at most once every
//   WRITE_EVERY_MS, so the request counts are approximate but the DB load stays tiny.
// - openRoute: POST /api/track/open, the app's "I was opened" ping (counts web/app visitors
//   even before they have an account).
// - recordAiUsage: one ai_usage row per successful OpenAI call, with an estimated USD cost.
// - logRequests: one api_requests row per /api request (normalised route, status, duration).
// Tracking never fails or noticeably slows a request: errors are logged and swallowed.
const { AsyncLocalStorage } = require('async_hooks');
const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../db');
const { istDate } = require('./coins_service');

const als = new AsyncLocalStorage();
const WRITE_EVERY_MS = 5 * 60 * 1000;
const WRITE_WAIT_MS = 1500; // longest a request waits for its tracking write
const MAX_KEYS = 20000;
const PLATFORMS = ['android', 'ios', 'web'];

// USD per 1M tokens [input, output]. Longest matching prefix wins; unknown models are priced as
// gpt-4o so spend is never under-reported. Override with AI_PRICES_JSON, e.g.
// {"gpt-4o":[2.5,10],"gpt-4o-mini":[0.15,0.6]}
const DEFAULT_PRICES = {
  'gpt-4o-mini': [0.15, 0.6],
  'gpt-4o': [2.5, 10],
  'gpt-4.1-nano': [0.1, 0.4],
  'gpt-4.1-mini': [0.4, 1.6],
  'gpt-4.1': [2, 8],
};
function prices() {
  try {
    const custom = JSON.parse(process.env.AI_PRICES_JSON || '{}');
    return { ...DEFAULT_PRICES, ...custom };
  } catch (_) {
    return DEFAULT_PRICES;
  }
}

function costUsd(model, promptTokens, completionTokens) {
  const table = prices();
  const m = String(model || '').toLowerCase();
  const key = Object.keys(table).filter((k) => m.startsWith(k)).sort((a, b) => b.length - a.length)[0] || 'gpt-4o';
  const [inp, out] = table[key] || DEFAULT_PRICES['gpt-4o'];
  return ((Number(promptTokens) || 0) * inp + (Number(completionTokens) || 0) * out) / 1e6;
}

// "1.3.2+7" from the app's X-App-Version header (null for browsers / old app builds).
function appVersionOf(req) {
  const v = String((req && req.headers && req.headers['x-app-version']) || '').trim();
  return /^[0-9A-Za-z.+_-]{1,20}$/.test(v) ? v : null;
}

// 'android' | 'ios' | 'web' from the app's X-Client-Platform header; otherwise guessed from the
// User-Agent (browsers say Mozilla, the native Dart http client says Dart/x.y).
function platformOf(req) {
  const h = String(req.headers['x-client-platform'] || '').toLowerCase().trim();
  if (PLATFORMS.includes(h)) return h;
  const ua = String(req.headers['user-agent'] || '');
  if (/^Dart\//.test(ua)) return 'app';
  if (/Mozilla\//.test(ua)) return 'web';
  return 'other';
}

// 'chat', 'horoscope/compatibility', ... from the request path (ids dropped).
function featureOf(req) {
  const parts = String(req.originalUrl || req.url || '').split('?')[0].split('/').filter(Boolean);
  if (parts[0] === 'api') parts.shift();
  const named = parts.filter((p) => /^[a-z][a-z0-9_-]*$/i.test(p)).slice(0, 2);
  return (named.join('/') || 'other').slice(0, 40);
}

// User id from the request: the one auth middleware set, else the Bearer token (signature and
// expiry checked, no DB lookup). Null when there is no valid token.
function userIdOf(req) {
  if (!req) return null;
  if (req.user && Number.isInteger(Number(req.user.userId))) return Number(req.user.userId);
  const h = req.headers && req.headers.authorization;
  if (typeof h !== 'string') return null;
  const [scheme, token] = h.split(' ');
  if (!/^Bearer$/i.test(scheme) || !token) return null;
  try {
    const { JWT_SECRET } = require('../routes/auth'); // lazy: auth.js loads db and other routes
    const decoded = jwt.verify(token, JWT_SECRET);
    const id = Number(decoded && decoded.userId);
    return Number.isInteger(id) && id > 0 ? id : null;
  } catch (_) {
    return null;
  }
}

function withTimeout(promise) {
  let timer;
  return Promise.race([
    promise,
    new Promise((resolve) => { timer = setTimeout(resolve, WRITE_WAIT_MS); }),
  ]).finally(() => clearTimeout(timer));
}

const pending = new Map(); // `${day}|${visitorKey}|${platform}` -> { at, requests, opens }

async function noteActivity({ visitorKey, userId = null, platform, open = false }, now = Date.now()) {
  const day = istDate(new Date(now));
  const k = `${day}|${visitorKey}|${platform}`;
  let e = pending.get(k);
  if (!e) {
    if (pending.size >= MAX_KEYS) pending.clear();
    e = { at: 0, requests: 0, opens: 0 };
    pending.set(k, e);
  }
  if (open) e.opens += 1; else e.requests += 1;
  if (now - e.at < WRITE_EVERY_MS) return;
  const { requests, opens } = e;
  e.at = now; e.requests = 0; e.opens = 0;
  try {
    await db.query(
      `INSERT INTO daily_activity (day, visitor_key, user_id, platform, requests, opens)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (day, visitor_key, platform) DO UPDATE SET
         requests = daily_activity.requests + EXCLUDED.requests,
         opens = daily_activity.opens + EXCLUDED.opens,
         user_id = COALESCE(EXCLUDED.user_id, daily_activity.user_id),
         last_seen = CURRENT_TIMESTAMP`,
      [day, visitorKey, userId, platform, requests, opens]
    );
  } catch (err) {
    console.warn('Activity tracking failed:', err.message);
  }
}

function requestContext(req, res, next) {
  als.run({ req }, next);
}

const SKIP = /^\/api\/(admin|track|health)(\/|$)/;

function trackActivity(req, res, next) {
  if (req.method === 'OPTIONS' || !String(req.originalUrl || '').startsWith('/api/') || SKIP.test(req.originalUrl)) {
    return next();
  }
  const userId = userIdOf(req);
  if (!userId) return next(); // anonymous requests are counted by the open ping instead
  withTimeout(noteActivity({ visitorKey: `u:${userId}`, userId, platform: platformOf(req) }))
    .then(() => next(), () => next());
}

// --- Per-request log (api_requests) -------------------------------------------------------
// One row per /api request with its normalised route, status and duration, for the dashboard's
// "API traffic", per-user request log and "Live" views. Old rows are pruned now and then so the
// table stays small without a cron job.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PRUNE_ONE_IN = 500;
const ROUTE_MAX = 120;

// '/api/kundli/family/12?x=1' -> '/api/kundli/family/:id'. Ids, UUIDs, long tokens and anything
// that looks like an email / file name / URL-encoded value are collapsed so routes group together
// (and personal data such as emails in a path never lands in the table).
function normalizeRoute(path) {
  const clean = String(path || '').split('?')[0].split('#')[0];
  const out = clean.split('/').map((seg) => {
    if (!seg) return seg;
    if (/^\d+$/.test(seg) || UUID_RE.test(seg) || seg.length > 24 || /[.@%]/.test(seg)) return ':id';
    return seg;
  }).join('/');
  return (out || '/').slice(0, ROUTE_MAX);
}

// Paths that are not logged: admin traffic (it would drown the real usage), the tracking pings
// themselves and health checks.
function shouldLogRequest(req) {
  if (!req || req.method === 'OPTIONS') return false;
  const url = String(req.originalUrl || req.url || '');
  return url.startsWith('/api/') && !SKIP.test(url);
}

function keepAlive(promise) {
  try {
    require('@vercel/functions').waitUntil(promise);
  } catch (_) {
    // Package missing or not on Vercel: the write still runs, just without the guarantee.
  }
}

// Writes one api_requests row. Never throws. `rand` is injectable so tests can force a prune.
async function recordApiRequest({ userId, method, route, status, durationMs, platform, appVersion = null }, rand = Math.random) {
  try {
    await db.query(
      `INSERT INTO api_requests (user_id, method, route, status, duration_ms, platform, app_version)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        userId || null,
        String(method || 'GET').toUpperCase().slice(0, 8),
        String(route || '/').slice(0, ROUTE_MAX),
        Math.max(0, Math.min(999, Number(status) || 0)),
        Math.max(0, Math.round(Number(durationMs) || 0)),
        String(platform || 'other').slice(0, 20),
        appVersion ? String(appVersion).slice(0, 20) : null,
      ]
    );
    if (rand() < 1 / PRUNE_ONE_IN) {
      await db.query(`DELETE FROM api_requests WHERE created_at < NOW() - INTERVAL '90 days'`);
    }
  } catch (err) {
    console.warn('API request logging failed:', err.message);
  }
}

// Middleware: logs the request once the response is finished (status and duration are known
// then, and req.user has been set by the route's auth middleware). Never delays the request.
function logRequests(req, res, next) {
  if (!shouldLogRequest(req)) return next();
  const started = process.hrtime.bigint();
  res.on('finish', () => {
    try {
      const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
      const write = recordApiRequest({
        userId: userIdOf(req),
        method: req.method,
        route: normalizeRoute(req.originalUrl || req.url),
        status: res.statusCode,
        durationMs,
        platform: platformOf(req),
        appVersion: appVersionOf(req),
      }).catch(() => {});
      // On Vercel the function can be frozen once the response is sent; waitUntil keeps it
      // alive until the write finishes. Elsewhere it is a no-op and the promise just runs.
      keepAlive(write);
    } catch (err) {
      console.warn('API request logging failed:', err.message);
    }
  });
  return next();
}

// POST /api/track/open { installId }  -> 204. installId: random id the app keeps per install.
const openRoute = express.Router();
openRoute.post('/open', async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const userId = userIdOf(req);
  const installId = req.body && typeof req.body.installId === 'string' ? req.body.installId.trim() : '';
  const validInstall = /^[A-Za-z0-9_-]{8,64}$/.test(installId);
  if (!userId && !validInstall) return res.status(400).json({ error: 'installId required' });
  await withTimeout(noteActivity({
    visitorKey: userId ? `u:${userId}` : `d:${installId}`,
    userId,
    platform: platformOf(req),
    open: true,
  }));
  res.status(204).end();
});

// Called by openai_client.js after a successful completion. Never throws.
async function recordAiUsage({ model, usage }) {
  if (!usage) return;
  const ctx = als.getStore();
  const req = ctx && ctx.req;
  const prompt = Number(usage.prompt_tokens) || 0;
  const completion = Number(usage.completion_tokens) || 0;
  const total = Number(usage.total_tokens) || prompt + completion;
  try {
    await withTimeout(db.query(
      `INSERT INTO ai_usage (user_id, feature, model, platform, prompt_tokens, completion_tokens, total_tokens, cost_usd)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        userIdOf(req),
        req ? featureOf(req) : 'background',
        String(model || 'unknown').slice(0, 60),
        req ? platformOf(req) : null,
        prompt, completion, total,
        costUsd(model, prompt, completion),
      ]
    ));
  } catch (err) {
    console.warn('AI usage tracking failed:', err.message);
  }
}

module.exports = {
  requestContext,
  trackActivity,
  logRequests,
  openRoute,
  recordAiUsage,
  normalizeRoute,
  _internals: {
    costUsd, platformOf, appVersionOf, featureOf, userIdOf, noteActivity, pending, WRITE_EVERY_MS,
    normalizeRoute, shouldLogRequest, recordApiRequest, PRUNE_ONE_IN,
  },
};
