// /api/notifications + services/push_service against an in-memory fake db and a fake FCM client
// (no real database, no Firebase). Run: npm test
process.env.NEON_DATABASE_URL = '';
process.env.DATABASE_URL = '';
delete process.env.FIREBASE_SERVICE_ACCOUNT;

const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve, call } = require('./fake_db');

const fake = install();
const { signToken } = require('../routes/auth');
const push = require('../services/push_service');
const notificationsRouter = require('../routes/notifications');

// ---------------------------------------------------------------------------
// Fake db: dispatches on the /*q:name*/ tag of each statement.
// ---------------------------------------------------------------------------
let t;
let clock;
const tick = () => new Date((clock += 1000));
function seed() {
  clock = Date.parse('2026-11-01T00:00:00Z');
  t = {
    users: [
      { id: 1, role: 'user', created_at: new Date('2026-10-01T00:00:00Z') },
      { id: 2, role: 'user', created_at: new Date('2026-10-01T00:00:00Z') },
      { id: 3, role: 'guest', created_at: new Date('2026-10-01T00:00:00Z') },
    ],
    device_tokens: [], notifications: [], broadcasts: [], broadcast_reads: [], notification_prefs: [],
  };
}
const norm = (x) => String(x).replace(/\s+/g, ' ').trim();
const userCreated = (uid) => t.users.find((u) => u.id === uid).created_at.getTime();
const visibleBroadcasts = (uid) => t.broadcasts.filter((b) => b.created_at.getTime() >= userCreated(uid));
const isRead = (uid, bid) => t.broadcast_reads.some((r) => r.user_id === uid && r.broadcast_id === bid);
// (created_at, rank, id) DESC, rank n=1 b=0 — same as the SQL
const cmp = (a, b) => (b.created_at - a.created_at) || (b.rank - a.rank) || (b.id - a.id);

const handlers = {
  tokenUpsert: ([token, uid, platform]) => {
    const ex = t.device_tokens.find((d) => d.token === token);
    if (ex) Object.assign(ex, { user_id: uid, platform, updated_at: tick() });
    else t.device_tokens.push({ token, user_id: uid, platform, updated_at: tick() });
    return [];
  },
  tokenDelete: ([token, uid]) => { t.device_tokens = t.device_tokens.filter((d) => !(d.token === token && d.user_id === uid)); return []; },
  tokenDeleteMany: ([tokens]) => { t.device_tokens = t.device_tokens.filter((d) => !tokens.includes(d.token)); return []; },
  tokensForUser: ([uid, limit]) => t.device_tokens.filter((d) => d.user_id === uid)
    .sort((a, b) => b.updated_at - a.updated_at).slice(0, limit).map((d) => ({ token: d.token })),
  notifInsert: ([uid, type, title, body, data]) => {
    const row = { id: t.notifications.length + 1, user_id: uid, type, title, body, data: JSON.parse(data), read_at: null, created_at: tick() };
    t.notifications.push(row);
    return [{ id: row.id }];
  },
  notifPrefs: ([uid], sql) => {
    const col = /SELECT (\w+) AS allowed/.exec(sql)[1];
    return t.notification_prefs.filter((p) => p.user_id === uid).map((p) => ({ allowed: p[col] }));
  },
  notifUnread: ([uid]) => [{
    unread: t.notifications.filter((n) => n.user_id === uid && !n.read_at).length
      + visibleBroadcasts(uid).filter((b) => !isRead(uid, b.id)).length,
  }],
  notifList: ([uid, kind, id, limit]) => {
    const items = [
      ...t.notifications.filter((n) => n.user_id === uid).map((n) => ({ kind: 'n', rank: 1, ...n, read: !!n.read_at })),
      ...visibleBroadcasts(uid).map((b) => ({ kind: 'b', rank: 0, ...b, type: 'announcement', read: isRead(uid, b.id) })),
    ].sort(cmp);
    let rows = items;
    if (kind !== null) {
      const c = kind === 'n'
        ? t.notifications.filter((n) => n.id === id && n.user_id === uid).map((n) => ({ ...n, rank: 1 }))[0]
        : t.broadcasts.filter((b) => b.id === id).map((b) => ({ ...b, rank: 0 }))[0];
      rows = c ? items.filter((x) => cmp(c, x) < 0) : []; // strictly after the cursor in list order
    }
    return rows.slice(0, limit).map((x) => ({ kind: x.kind, id: x.id, type: x.type, title: x.title, body: x.body, data: x.data, created_at: x.created_at, read: x.read }));
  },
  readAllNotifs: ([uid]) => { t.notifications.forEach((n) => { if (n.user_id === uid && !n.read_at) n.read_at = tick(); }); return []; },
  readAllBroadcasts: ([uid]) => { visibleBroadcasts(uid).forEach((b) => { if (!isRead(uid, b.id)) t.broadcast_reads.push({ user_id: uid, broadcast_id: b.id }); }); return []; },
  readNotifs: ([uid, ids]) => { t.notifications.forEach((n) => { if (n.user_id === uid && ids.includes(n.id) && !n.read_at) n.read_at = tick(); }); return []; },
  readBroadcasts: ([uid, ids]) => {
    visibleBroadcasts(uid).forEach((b) => { if (ids.includes(b.id) && !isRead(uid, b.id)) t.broadcast_reads.push({ user_id: uid, broadcast_id: b.id }); });
    return [];
  },
  prefsGet: ([uid]) => t.notification_prefs.filter((p) => p.user_id === uid).map((p) => ({ ...p })),
  prefsUpsert: ([uid, ...vals]) => {
    const keys = ['buddy', 'messages', 'trips', 'rewards', 'announcements'];
    let p = t.notification_prefs.find((x) => x.user_id === uid);
    if (!p) { p = { user_id: uid }; keys.forEach((k, i) => { p[k] = vals[i] === null ? true : vals[i]; }); t.notification_prefs.push(p); }
    else keys.forEach((k, i) => { if (vals[i] !== null) p[k] = vals[i]; });
    return [{ ...p }];
  },
};

const log = [];
fake.query = async (text, params = []) => {
  const sql = norm(text);
  if (sql === 'SELECT role FROM users WHERE id = $1') return { rows: t.users.filter((u) => u.id === params[0]).map((u) => ({ role: u.role })) };
  const m = /^\/\*q:(\w+)\*\//.exec(sql);
  if (!m || !handlers[m[1]]) throw new Error(`notifications fake: unhandled SQL: ${sql.slice(0, 80)}`);
  log.push(m[1]);
  return { rows: handlers[m[1]](params, sql) };
};

// ---------------------------------------------------------------------------
// Fake FCM client
// ---------------------------------------------------------------------------
function fakeMessaging(errors = {}) {
  const sent = [];
  return {
    sent,
    async sendEachForMulticast(msg) {
      sent.push(msg);
      const responses = msg.tokens.map((tok) => (errors[tok] ? { success: false, error: { code: errors[tok] } } : { success: true, messageId: `m-${tok}` }));
      return { successCount: responses.filter((r) => r.success).length, failureCount: responses.filter((r) => !r.success).length, responses };
    },
    async send(msg) { sent.push(msg); return 'projects/x/messages/1'; },
  };
}

const tokenFor = (uid) => signToken({ userId: uid, role: uid === 3 ? 'guest' : 'user' });
let srv;
test.before(async () => { srv = await serve(notificationsRouter, '/api/notifications'); });
test.after(async () => { await srv.close(); push.setMessagingClient(undefined); });
test.beforeEach(() => { seed(); log.length = 0; push.setMessagingClient(null); });
const api = (uid, method, p, body) => call(srv.url, method, p, { token: uid ? tokenFor(uid) : undefined, body });

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------
test('devices: upsert, reassign to the current user, delete only your own; guests 403', async () => {
  assert.equal((await api(null, 'POST', '/devices', { token: 'tokA', platform: 'android' })).status, 401);
  assert.equal((await api(3, 'POST', '/devices', { token: 'tokA', platform: 'android' })).status, 403);
  assert.equal((await api(3, 'DELETE', '/devices', { token: 'tokA' })).status, 403);
  assert.equal((await api(1, 'POST', '/devices', { token: '', platform: 'android' })).status, 400);
  assert.equal((await api(1, 'POST', '/devices', { token: 'tokA', platform: 'web' })).status, 400);

  let r = await api(1, 'POST', '/devices', { token: 'tokA', platform: 'android' });
  assert.deepEqual(r.body, { success: true });
  await api(1, 'POST', '/devices', { token: 'tokA', platform: 'android' }); // repeat = no duplicate
  await api(1, 'POST', '/devices', { token: 'tokB', platform: 'ios' });
  assert.deepEqual(t.device_tokens.map((d) => [d.token, d.user_id, d.platform]), [['tokA', 1, 'android'], ['tokB', 1, 'ios']]);

  // same phone, different account: the token moves
  await api(2, 'POST', '/devices', { token: 'tokA', platform: 'android' });
  assert.deepEqual(t.device_tokens.map((d) => [d.token, d.user_id]), [['tokA', 2], ['tokB', 1]]);

  // user 1 cannot delete user 2's token
  r = await api(1, 'DELETE', '/devices', { token: 'tokA' });
  assert.deepEqual(r.body, { success: true });
  assert.equal(t.device_tokens.length, 2);
  await api(1, 'DELETE', '/devices', { token: 'tokB' });
  assert.deepEqual(t.device_tokens.map((d) => d.token), ['tokA']);
  assert.equal((await api(1, 'DELETE', '/devices', {})).status, 400);
});

// ---------------------------------------------------------------------------
// Inbox
// ---------------------------------------------------------------------------
function seedInbox() {
  const at = (iso) => new Date(iso);
  t.broadcasts.push({ id: 1, title: 'Old news', body: 'before signup', data: {}, created_at: at('2026-09-01T00:00:00Z') });
  t.broadcasts.push({ id: 2, title: 'Diwali', body: 'Double coins', data: { url: 'https://x.test' }, created_at: at('2026-10-10T00:00:00Z') });
  t.broadcasts.push({ id: 3, title: 'Tie', body: 'same instant as n:2', data: {}, created_at: at('2026-10-20T00:00:00Z') });
  const n = (id, uid, iso, type = 'buddy_request') => t.notifications.push({ id, user_id: uid, type, title: `N${id}`, body: '', data: { type, connectionId: String(id) }, read_at: null, created_at: at(iso) });
  n(1, 1, '2026-10-05T00:00:00Z');
  n(2, 1, '2026-10-20T00:00:00Z');
  n(3, 2, '2026-10-21T00:00:00Z'); // someone else's
  n(4, 1, '2026-10-25T00:00:00Z', 'trip_update');
  n(5, 1, '2026-10-20T00:00:00Z'); // ties with n:2 and b:3
}

test('list merges own rows and broadcasts since signup, newest first, with stable cursor pagination', async () => {
  seedInbox();
  let r = await api(1, 'GET', '/');
  assert.equal(r.status, 200);
  const all = r.body.items.map((i) => i.id);
  // tie at 2026-10-20: n before b, higher id first
  assert.deepEqual(all, ['n:4', 'n:5', 'n:2', 'b:3', 'b:2', 'n:1']);
  assert.equal(r.body.hasMore, false);
  assert.equal(r.body.unread, 6);
  const first = r.body.items[0];
  assert.deepEqual(Object.keys(first).sort(), ['body', 'createdAt', 'data', 'id', 'read', 'title', 'type']);
  assert.equal(first.type, 'trip_update');
  assert.equal(first.data.type, 'trip_update');
  assert.equal(first.read, false);
  const diwali = r.body.items.find((i) => i.id === 'b:2');
  assert.deepEqual(diwali.data, { url: 'https://x.test', type: 'announcement' });
  assert.equal(diwali.type, 'announcement');

  // walk pages of 2 using the last id as the cursor
  const seen = [];
  let before = '';
  for (let page = 0; page < 10; page++) {
    r = await api(1, 'GET', `/?limit=2${before ? `&before=${encodeURIComponent(before)}` : ''}`);
    seen.push(...r.body.items.map((i) => i.id));
    if (!r.body.hasMore) break;
    before = r.body.items[r.body.items.length - 1].id;
  }
  assert.deepEqual(seen, all);
  // starting from a broadcast cursor
  r = await api(1, 'GET', '/?before=b:3');
  assert.deepEqual(r.body.items.map((i) => i.id), ['b:2', 'n:1']);
  // someone else's row is not a valid cursor
  r = await api(1, 'GET', '/?before=n:3');
  assert.deepEqual(r.body.items, []);
  assert.equal((await api(1, 'GET', '/?before=x:1')).status, 400);
  assert.equal((await api(1, 'GET', '/?limit=0')).status, 400);
  // limit is capped
  assert.equal((await api(1, 'GET', '/?limit=500')).status, 200);

  // user 2 only sees their own row + broadcasts since their signup
  r = await api(2, 'GET', '/');
  assert.deepEqual(r.body.items.map((i) => i.id), ['n:3', 'b:3', 'b:2']);

  // guests get empty results
  assert.deepEqual((await api(3, 'GET', '/')).body, { items: [], unread: 0, hasMore: false });
  assert.deepEqual((await api(3, 'GET', '/unread-count')).body, { unread: 0 });
  assert.equal((await api(null, 'GET', '/')).status, 401);
});

test('a broadcast created before signup is hidden; one after signup is shown', async () => {
  seedInbox();
  t.users[0].created_at = new Date('2026-10-15T00:00:00Z');
  const r = await api(1, 'GET', '/');
  assert.ok(!r.body.items.some((i) => i.id === 'b:2'));
  assert.ok(r.body.items.some((i) => i.id === 'b:3'));
});

test('read: by ids of both kinds, then all; read flags and unread counts follow', async () => {
  seedInbox();
  assert.deepEqual((await api(1, 'GET', '/unread-count')).body, { unread: 6 });
  let r = await api(1, 'POST', '/read', { ids: ['n:4', 'b:2', 'n:3', 'b:1'] }); // n:3 is not mine, b:1 predates signup
  assert.deepEqual(r.body, { success: true, unread: 4 });
  assert.equal(t.notifications.find((n) => n.id === 3).read_at, null);
  assert.ok(!t.broadcast_reads.some((x) => x.broadcast_id === 1));
  r = await api(1, 'GET', '/');
  const flags = Object.fromEntries(r.body.items.map((i) => [i.id, i.read]));
  assert.deepEqual(flags, { 'n:4': true, 'n:5': false, 'n:2': false, 'b:3': false, 'b:2': true, 'n:1': false });
  // idempotent
  assert.equal((await api(1, 'POST', '/read', { ids: ['b:2'] })).body.unread, 4);
  assert.equal(t.broadcast_reads.length, 1);

  assert.equal((await api(1, 'POST', '/read', { ids: ['nope'] })).status, 400);
  assert.equal((await api(1, 'POST', '/read', {})).status, 400);
  assert.equal((await api(1, 'POST', '/read', { ids: Array(201).fill('n:1') })).status, 400);
  assert.equal((await api(3, 'POST', '/read', { all: true })).status, 403);

  r = await api(1, 'POST', '/read', { all: true });
  assert.deepEqual(r.body, { success: true, unread: 0 });
  assert.ok((await api(1, 'GET', '/')).body.items.every((i) => i.read));
  assert.deepEqual((await api(2, 'GET', '/unread-count')).body, { unread: 3 }, 'other users are untouched');
});

// ---------------------------------------------------------------------------
// Prefs
// ---------------------------------------------------------------------------
test('prefs: defaults, partial update, validation, guests', async () => {
  const all = { buddy: true, messages: true, trips: true, rewards: true, announcements: true };
  assert.deepEqual((await api(1, 'GET', '/prefs')).body, all);
  let r = await api(1, 'PUT', '/prefs', { messages: false });
  assert.deepEqual(r.body, { ...all, messages: false });
  r = await api(1, 'PUT', '/prefs', { trips: false, unknown: 1 });
  assert.deepEqual(r.body, { ...all, messages: false, trips: false });
  assert.deepEqual((await api(1, 'GET', '/prefs')).body, { ...all, messages: false, trips: false });
  assert.equal((await api(1, 'PUT', '/prefs', { buddy: 'no' })).status, 400);
  assert.equal((await api(3, 'PUT', '/prefs', { buddy: false })).status, 403);
  assert.deepEqual((await api(3, 'GET', '/prefs')).body, all);
  assert.deepEqual((await api(2, 'GET', '/prefs')).body, all);
});

// ---------------------------------------------------------------------------
// push_service
// ---------------------------------------------------------------------------
const MSG = { type: 'buddy_request', title: 'New buddy request', body: 'Asha wants to be your friend', data: { connectionId: 7 } };

test('sendToUser stores the inbox row and pushes to every device with string data and the right channel', async () => {
  const fcm = fakeMessaging();
  push.setMessagingClient(fcm);
  t.device_tokens.push({ token: 'a', user_id: 1, platform: 'android', updated_at: tick() }, { token: 'b', user_id: 1, platform: 'ios', updated_at: tick() });
  t.device_tokens.push({ token: 'z', user_id: 2, platform: 'android', updated_at: tick() });
  const r = await push.sendToUser(1, MSG, { pref: 'buddy' });
  assert.equal(r.inboxId, 1);
  assert.equal(r.sent, 2);
  assert.equal(t.notifications.length, 1);
  assert.deepEqual(t.notifications[0].data, { connectionId: '7', type: 'buddy_request' });
  assert.equal(fcm.sent.length, 1);
  const m = fcm.sent[0];
  assert.deepEqual(m.tokens.sort(), ['a', 'b']);
  assert.deepEqual(m.notification, { title: 'New buddy request', body: 'Asha wants to be your friend' });
  assert.deepEqual(m.data, { connectionId: '7', type: 'buddy_request', notificationId: 'n:1' });
  for (const v of Object.values(m.data)) assert.equal(typeof v, 'string');
  assert.equal(m.android.priority, 'high');
  assert.equal(m.android.notification.channelId, 'buddy');

  const { channelFor, buildMessage } = push._internals;
  assert.equal(channelFor('buddy_message'), 'buddy');
  assert.equal(channelFor('trip_update'), 'rewards');
  assert.equal(channelFor('announcement'), 'announcements');
  const chat = buildMessage({ type: 'buddy_message', title: 'Asha', body: 'hi', data: { connectionId: 7, name: 'Asha', nothing: null }, collapseKey: 'buddy_chat_7' });
  assert.equal(chat.android.collapseKey, 'buddy_chat_7');
  assert.equal(chat.android.notification.tag, 'buddy_chat_7');
  assert.equal(chat.apns.headers['apns-collapse-id'], 'buddy_chat_7');
  assert.deepEqual(chat.data, { connectionId: '7', name: 'Asha', type: 'buddy_message' });
});

test('prefs gate the push but the inbox row is still stored; inbox:false stores nothing', async () => {
  const fcm = fakeMessaging();
  push.setMessagingClient(fcm);
  t.device_tokens.push({ token: 'a', user_id: 1, platform: 'android', updated_at: tick() });
  t.notification_prefs.push({ user_id: 1, buddy: false, messages: false, trips: true, rewards: true, announcements: true });
  let r = await push.sendToUser(1, MSG, { pref: 'buddy' });
  assert.equal(r.skipped, 'pref');
  assert.equal(t.notifications.length, 1, 'inbox row stored');
  assert.equal(fcm.sent.length, 0, 'no push');

  r = await push.sendToUser(1, { type: 'buddy_message', title: 'Asha', body: 'hi', data: { connectionId: 7 } }, { pref: 'messages', inbox: false });
  assert.equal(r.skipped, 'pref');
  assert.equal(t.notifications.length, 1, 'messages never go to the inbox');

  r = await push.sendToUser(1, { type: 'trip_update', title: 'Trip approved', body: 'x', data: { tripId: 3, status: 'approved' } }, { pref: 'trips' });
  assert.equal(r.sent, 1);
  assert.equal(fcm.sent[0].android.notification.channelId, 'rewards');
  assert.deepEqual(fcm.sent[0].data, { tripId: '3', status: 'approved', type: 'trip_update', notificationId: 'n:2' });

  // no devices: inbox only
  r = await push.sendToUser(2, MSG, { pref: 'buddy' });
  assert.equal(r.skipped, 'no_tokens');
  assert.equal(t.notifications.filter((n) => n.user_id === 2).length, 1);
});

test('unregistered / invalid tokens reported by FCM are deleted; other failures are kept', async () => {
  const fcm = fakeMessaging({
    dead: 'messaging/registration-token-not-registered',
    bad: 'messaging/invalid-argument',
    flaky: 'messaging/internal-error',
  });
  push.setMessagingClient(fcm);
  for (const token of ['ok', 'dead', 'bad', 'flaky']) t.device_tokens.push({ token, user_id: 1, platform: 'android', updated_at: tick() });
  const r = await push.sendToUser(1, MSG, { pref: 'buddy' });
  assert.equal(r.sent, 1);
  assert.equal(r.failed, 3);
  assert.equal(r.removed, 2);
  assert.deepEqual(t.device_tokens.map((d) => d.token).sort(), ['flaky', 'ok']);
});

test('without Firebase (unset or broken FIREBASE_SERVICE_ACCOUNT) sends are a no-op, inbox still stored, nothing throws', async () => {
  push.setMessagingClient(undefined); // lazy init from env
  t.device_tokens.push({ token: 'a', user_id: 1, platform: 'android', updated_at: tick() });
  let r = await push.sendToUser(1, MSG, { pref: 'buddy' });
  assert.equal(r.skipped, 'disabled');
  assert.equal(t.notifications.length, 1);
  assert.deepEqual(await push.sendToTopic('announcements', { type: 'announcement', title: 'x', body: 'y' }), { sent: false, skipped: 'disabled' });

  process.env.FIREBASE_SERVICE_ACCOUNT = 'not-json-and-not-base64-json';
  push.setMessagingClient(undefined);
  try {
    r = await push.sendToUser(1, MSG, { pref: 'buddy' });
    assert.equal(r.skipped, 'disabled');
    assert.equal(t.notifications.length, 2);
  } finally {
    delete process.env.FIREBASE_SERVICE_ACCOUNT;
  }

  // a failing client or db never rejects
  push.setMessagingClient({ sendEachForMulticast: async () => { throw new Error('fcm down'); }, send: async () => { throw new Error('fcm down'); } });
  r = await push.sendToUser(1, MSG, { pref: 'buddy' });
  assert.equal(r.error, 'fcm down');
  assert.deepEqual(await push.sendToTopic('announcements', { type: 'announcement', title: 'x', body: 'y' }), { sent: false, error: 'fcm down' });
  assert.deepEqual(await push.sendToUser('abc', MSG), { skipped: 'invalid' });
});

test('sendToTopic builds an announcement message for the topic', async () => {
  const fcm = fakeMessaging();
  push.setMessagingClient(fcm);
  const r = await push.sendToTopic('announcements', { type: 'announcement', title: 'Diwali', body: 'Double coins', data: { url: 'https://x.test', broadcastId: 'b:4' } });
  assert.equal(r.sent, true);
  assert.equal(fcm.sent[0].topic, 'announcements');
  assert.equal(fcm.sent[0].android.notification.channelId, 'announcements');
  assert.deepEqual(fcm.sent[0].data, { url: 'https://x.test', broadcastId: 'b:4', type: 'announcement' });
});

test('parseServiceAccount accepts raw JSON and base64, and restores escaped newlines', () => {
  const { parseServiceAccount } = push._internals;
  const sa = { project_id: 'p', client_email: 'e@p.iam.gserviceaccount.com', private_key: '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----\\n' };
  const raw = JSON.stringify(sa);
  assert.equal(parseServiceAccount(raw).private_key, '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n');
  assert.equal(parseServiceAccount(Buffer.from(raw).toString('base64')).project_id, 'p');
  assert.equal(parseServiceAccount(''), null);
  assert.throws(() => parseServiceAccount('{"project_id":"p"}'));
});
