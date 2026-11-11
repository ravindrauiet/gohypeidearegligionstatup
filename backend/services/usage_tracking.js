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
  openRoute,
  recordAiUsage,
  _internals: { costUsd, platformOf, featureOf, userIdOf, noteActivity, pending, WRITE_EVERY_MS },
};
