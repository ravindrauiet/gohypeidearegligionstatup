// Push notifications (Firebase Cloud Messaging) + the per-user notification inbox.
//
// firebase-admin is used only when FIREBASE_SERVICE_ACCOUNT is set (the service-account JSON, raw
// or base64-encoded). Without it, or when initialisation fails, every send is a no-op that is
// logged once; inbox rows are still stored so the in-app inbox keeps working.
//
// Nothing here ever throws into the request path: every public function resolves (never rejects)
// and the whole send is capped by SEND_TIMEOUT_MS so a slow FCM call cannot hold a Vercel request.
// Tests swap the FCM client with setMessagingClient(fake) (null = disabled, undefined = lazy init).
// SQL statements carry a /*q:name*/ tag like routes/buddy.js, so the fake dbs can dispatch on it.
const db = require('../db');

const SEND_TIMEOUT_MS = 3000;
const MAX_TOKENS_PER_USER = 20;
const PREF_KEYS = ['buddy', 'messages', 'trips', 'rewards', 'announcements'];
// FCM error codes meaning the token will never work again.
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

let messaging; // undefined: not initialised yet; null: disabled; otherwise a Messaging-like client
let loggedDisabled = false;

function logDisabledOnce(reason) {
  if (loggedDisabled) return;
  loggedDisabled = true;
  console.warn(`Push disabled: ${reason}. Inbox rows are still stored.`);
}

function parseServiceAccount(raw) {
  const s = String(raw || '').trim();
  if (!s) return null;
  const json = s.startsWith('{') ? s : Buffer.from(s, 'base64').toString('utf8');
  const sa = JSON.parse(json);
  if (sa && typeof sa.private_key === 'string') sa.private_key = sa.private_key.replace(/\\n/g, '\n');
  if (!sa || !sa.project_id || !sa.client_email || !sa.private_key) throw new Error('service account JSON is incomplete');
  return sa;
}

function getMessagingClient() {
  if (messaging !== undefined) return messaging;
  messaging = null;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw || !String(raw).trim()) {
    logDisabledOnce('FIREBASE_SERVICE_ACCOUNT is not set');
    return null;
  }
  try {
    const sa = parseServiceAccount(raw);
    const { initializeApp, getApps, cert } = require('firebase-admin/app');
    const { getMessaging } = require('firebase-admin/messaging');
    const NAME = 'cosmicguide-push';
    const app = getApps().find((a) => a.name === NAME) || initializeApp({ credential: cert(sa), projectId: sa.project_id }, NAME);
    messaging = getMessaging(app);
  } catch (err) {
    messaging = null;
    logDisabledOnce(`firebase-admin init failed (${err.message})`);
  }
  return messaging;
}

/** Test hook: a fake client ({sendEachForMulticast, send}), null to disable, undefined to re-init lazily. */
function setMessagingClient(client) {
  messaging = client;
  loggedDisabled = false;
}

/** FCM data payloads must be flat string maps. Drops null/undefined, JSON-encodes objects. */
function stringifyData(data) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === 'object' ? JSON.stringify(v) : String(v);
  }
  return out;
}

function channelFor(type) {
  const t = String(type || '');
  if (t.startsWith('buddy_') || t === 'nearby_buddy') return 'buddy';
  if (t === 'trip_update' || t === 'coins') return 'rewards';
  return 'announcements';
}

function clip(s, n) {
  const v = String(s === undefined || s === null ? '' : s).replace(/\s+/g, ' ').trim();
  return v.length > n ? `${v.slice(0, n - 1)}…` : v;
}

/** Builds the FCM message body shared by multicast and topic sends (no tokens/topic). */
function buildMessage({ type, title, body, data, collapseKey }) {
  const payload = stringifyData({ ...(data || {}), type });
  const android = {
    priority: 'high',
    notification: { channelId: channelFor(type), sound: 'default' },
  };
  const apns = { payload: { aps: { sound: 'default' } } };
  if (collapseKey) {
    const key = String(collapseKey).slice(0, 64);
    android.collapseKey = key;
    android.notification.tag = key; // newer messages from the same chat replace the old one
    apns.headers = { 'apns-collapse-id': key };
    apns.payload.aps['thread-id'] = key;
  }
  return {
    notification: { title: clip(title, 200), body: clip(body, 500) },
    data: payload,
    android,
    apns,
  };
}

function withTimeout(promise, ms) {
  let timer;
  const t = new Promise((resolve) => {
    timer = setTimeout(() => resolve({ timedOut: true }), ms);
    if (timer.unref) timer.unref();
  });
  return Promise.race([promise, t]).finally(() => clearTimeout(timer));
}

async function storeInbox(userId, msg) {
  const data = { ...stringifyData(msg.data), type: String(msg.type) };
  const r = await db.query(
    `/*q:notifInsert*/ INSERT INTO notifications (user_id, type, title, body, data)
     VALUES ($1, $2, $3, $4, $5::jsonb) RETURNING id`,
    [userId, String(msg.type), clip(msg.title, 200), clip(msg.body, 500), JSON.stringify(data)]
  );
  return r.rows[0] ? Number(r.rows[0].id) : null;
}

async function prefAllows(userId, pref) {
  if (!PREF_KEYS.includes(pref)) return true;
  const r = await db.query(`/*q:notifPrefs*/ SELECT ${pref} AS allowed FROM notification_prefs WHERE user_id = $1`, [userId]);
  return !r.rows[0] || r.rows[0].allowed !== false;
}

async function removeDeadTokens(tokens, responses) {
  const dead = [];
  (responses || []).forEach((res, i) => {
    const code = res && !res.success && res.error && (res.error.code || (res.error.errorInfo && res.error.errorInfo.code));
    if (code && DEAD_TOKEN_CODES.has(code)) dead.push(tokens[i]);
  });
  if (dead.length) await db.query('/*q:tokenDeleteMany*/ DELETE FROM device_tokens WHERE token = ANY($1::text[])', [dead]);
  return dead.length;
}

async function deliver(userId, msg, opts) {
  const out = { inboxId: null, sent: 0, failed: 0, removed: 0, skipped: null };
  if (opts.inbox !== false) out.inboxId = await storeInbox(userId, msg);
  const client = getMessagingClient();
  if (!client) { out.skipped = 'disabled'; return out; }
  if (opts.pref && !(await prefAllows(userId, opts.pref))) { out.skipped = 'pref'; return out; }
  const r = await db.query(
    '/*q:tokensForUser*/ SELECT token FROM device_tokens WHERE user_id = $1 ORDER BY updated_at DESC LIMIT $2',
    [userId, MAX_TOKENS_PER_USER]
  );
  const tokens = r.rows.map((x) => x.token);
  if (!tokens.length) { out.skipped = 'no_tokens'; return out; }
  const base = buildMessage(msg);
  if (out.inboxId) base.data.notificationId = `n:${out.inboxId}`;
  const resp = await client.sendEachForMulticast({ ...base, tokens });
  out.sent = Number(resp && resp.successCount) || 0;
  out.failed = Number(resp && resp.failureCount) || 0;
  if (out.failed) out.removed = await removeDeadTokens(tokens, resp.responses);
  return out;
}

/**
 * Stores an inbox row (unless opts.inbox === false) and pushes to every device of `userId`
 * when the `opts.pref` category is enabled. msg = {type, title, body, data, collapseKey}.
 * Never rejects; resolves to {inboxId, sent, failed, removed, skipped} or {error}.
 */
async function sendToUser(userId, msg, opts = {}) {
  try {
    const id = Number(userId);
    if (!Number.isInteger(id) || id <= 0 || !msg || !msg.type || !msg.title) return { skipped: 'invalid' };
    // .catch keeps a late failure (after the timeout won) from becoming an unhandled rejection
    const work = deliver(id, msg, opts).catch((err) => { console.error('Push send failed:', err.message); return { error: err.message }; });
    const r = await withTimeout(work, SEND_TIMEOUT_MS);
    if (r && r.timedOut) console.warn(`Push to user ${id} (${msg.type}) timed out`);
    return r;
  } catch (err) {
    console.error('Push send failed:', err.message);
    return { error: err.message };
  }
}

/** Sends one message to an FCM topic (e.g. 'announcements'). Never rejects. */
async function sendToTopic(topic, msg) {
  try {
    const client = getMessagingClient();
    if (!client) return { sent: false, skipped: 'disabled' };
    const work = Promise.resolve().then(() => client.send({ ...buildMessage(msg), topic: String(topic) }))
      .catch((err) => { console.error('Push topic send failed:', err.message); return { error: err.message }; });
    const r = await withTimeout(work, SEND_TIMEOUT_MS);
    if (r && r.error) return { sent: false, error: r.error };
    if (r && r.timedOut) return { sent: false, timedOut: true };
    return { sent: true, messageId: r || null };
  } catch (err) {
    console.error('Push topic send failed:', err.message);
    return { sent: false, error: err.message };
  }
}

module.exports = {
  sendToUser,
  sendToTopic,
  setMessagingClient,
  _internals: { buildMessage, stringifyData, channelFor, parseServiceAccount, getMessagingClient, PREF_KEYS, SEND_TIMEOUT_MS },
};
