// Family mode (v3 trust): read-only share links for parents / siblings, no login needed.
//
// Signed-in owner (registered, with a buddy profile, not banned):
//   POST   /api/family/links {kind: 'self' | 'match', matchUserId?}  -> {link}   (max 5 active)
//   GET    /api/family/links                                          -> {links, maxActive}
//   DELETE /api/family/links/:id   (revoke)                           -> {link}
//   GET    /api/family/notes                                          -> {notes}
//   DELETE /api/family/notes/:id                                      -> {ok}
// Public (anyone with the link):
//   GET    /api/family/:token          -> read-only summary (never birth date/time/place, contact,
//                                         exact location, email, selfies or notes)
//   POST   /api/family/:token/notes {name, relation, message}  (5 per link + IP per day)
//   GET    /f/:token                   -> public/family.html (mounted in server.js)
//
// A "match" link shares an ACCEPTED buddy's public summary + our compatibility score; it stops
// working as soon as that connection ends, either side blocks, or either is banned.
// SQL statements carry /*q:name*/ tags (test/family.test.js dispatches on them).
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const push = require('../services/push_service');
const T = require('../services/trust_service');
const M = require('../services/buddy_matching');
const B = require('./buddy')._internal;

const router = express.Router();

const LINK_DAYS = 30;
const MAX_ACTIVE_LINKS = 5;
const NOTES_PER_IP_PER_DAY = 5;
const NOTES_PER_LINK_PER_DAY = 30;
const RELATIONS = ['Mother', 'Father', 'Sibling', 'Other'];
const TOKEN_RE = /^[A-Za-z0-9_-]{24,64}$/;
const MAX_INT = 2147483647;

class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
const wrap = (fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (err) {
    if (err instanceof HttpError) return res.status(err.status).json({ error: err.message, code: err.code });
    console.error('Family route error:', err);
    return res.status(500).json({ error: 'Something went wrong. Please try again.' });
  }
};
const iso = (v) => {
  if (!v) return null;
  const d = v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
};
const toId = (v) => {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 && n <= MAX_INT ? n : null;
};
const asArray = (v) => (Array.isArray(v) ? v : typeof v === 'string' && v.startsWith('{')
  ? v.slice(1, -1).split(',').filter(Boolean).map((s) => s.replace(/^"|"$/g, ''))
  : []);
const newToken = () => crypto.randomBytes(24).toString('base64url'); // 32 chars, 192 bits

function noStore(res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('Referrer-Policy', 'no-referrer');
}

/** https://<backend host> (PUBLIC_BASE_URL wins). Plain http only for local / LAN hosts. */
function baseUrl(req) {
  const env = String(process.env.PUBLIC_BASE_URL || '').trim().replace(/\/+$/, '');
  if (/^https?:\/\/[^\s/]+$/i.test(env)) return env;
  const host = String(req.get('x-forwarded-host') || req.get('host') || '').split(',')[0].trim();
  const local = /^(localhost|127\.|10\.|192\.168\.|\[::1\])/i.test(host);
  return `${local ? 'http' : 'https'}://${host}`;
}

function clientIp(req) {
  const real = req.get('x-real-ip');
  if (real) return real.trim();
  const xff = req.get('x-forwarded-for');
  if (xff) return xff.split(',')[0].trim();
  return (req.socket && req.socket.remoteAddress) || 'unknown';
}
const ipHash = (ip) => crypto.createHash('sha256').update(`cosmicguide:family:${ip}`).digest('hex');

// ---------------------------------------------------------------------------
// Owner auth
// ---------------------------------------------------------------------------
function requireRegistered(req, res, next) {
  if (!req.user || req.user.role === 'guest') {
    return res.status(401).json({ error: 'Please log in to share with family', code: 'LOGIN_REQUIRED' });
  }
  return next();
}
const registered = [optionalAuthenticateToken, requireRegistered];

async function requireOwner(userId) {
  const me = await B.loadMe(userId);
  if (!me) throw new HttpError(401, 'Please log in to share with family', 'LOGIN_REQUIRED');
  const el = B.eligibility(me);
  if (!el.eligible) throw new HttpError(403, el.reason === 'UNDER_18' ? 'Buddies is for people aged 18 and over' : 'Create your Kundli first', el.reason);
  if (!me.bp_user_id) throw new HttpError(409, 'Set up your buddy profile first', 'NO_PROFILE');
  if (B.isBanned(me)) throw new HttpError(403, 'Your buddy profile has been suspended after a safety review', 'BANNED');
  return me;
}

/** The accepted, unblocked, unbanned connection between a and b, or null. */
async function acceptedConnection(a, b) {
  if (a === b) return null;
  const [blocked, conns] = await Promise.all([B.blockedPair(a, b), B.connectionsBetween(a, b)]);
  if (blocked) return null;
  return conns.find((c) => c.status === 'accepted') || null;
}

const linkActive = (l, now = Date.now()) => !l.revoked_at && new Date(l.expires_at).getTime() > now;

function linkView(l, req) {
  return {
    id: Number(l.id),
    kind: l.kind === 'match' ? 'match' : 'self',
    token: l.token,
    url: `${baseUrl(req)}/f/${l.token}`,
    match: l.kind === 'match' && l.match_user_id
      ? { userId: Number(l.match_user_id), displayName: l.match_display_name || B.firstName(l.match_full_name) || 'Buddy' }
      : null,
    createdAt: iso(l.created_at),
    expiresAt: iso(l.expires_at),
    revokedAt: iso(l.revoked_at),
    active: linkActive(l),
    notesCount: Number(l.notes_count) || 0,
  };
}

const LINK_SELECT = `SELECT fl.id, fl.token, fl.user_id, fl.kind, fl.match_user_id, fl.created_at, fl.expires_at, fl.revoked_at,
       mbp.display_name AS match_display_name, mu.full_name AS match_full_name,
       (SELECT COUNT(*) FROM family_notes fn WHERE fn.link_id = fl.id) AS notes_count
     FROM family_links fl
     LEFT JOIN users mu ON mu.id = fl.match_user_id
     LEFT JOIN buddy_profiles mbp ON mbp.user_id = fl.match_user_id`;

// POST /api/family/links
router.post('/links', registered, wrap(async (req, res) => {
  const body = req.body || {};
  const kind = body.kind === undefined || body.kind === null ? 'self' : body.kind;
  if (!['self', 'match'].includes(kind)) throw new HttpError(400, 'kind must be self or match', 'INVALID_INPUT');
  let matchId = null;
  if (kind === 'match') {
    matchId = toId(body.matchUserId);
    if (!matchId) throw new HttpError(400, 'Choose which buddy to share', 'INVALID_INPUT');
  }
  const me = await requireOwner(req.user.userId);
  const meId = Number(me.user_id);
  if (kind === 'match') {
    // Only an accepted buddy (never a stranger from Discover) can be shared with family.
    const conn = await acceptedConnection(meId, matchId);
    const other = conn ? await B.loadPerson(matchId) : null;
    if (!conn || !other || B.isBanned(other) || !B.eligibility(other).eligible) {
      throw new HttpError(403, 'You can share a match with family once you are buddies', 'NOT_BUDDIES');
    }
  }
  const active = await db.query(
    '/*q:familyActiveCount*/ SELECT COUNT(*) AS n FROM family_links WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW()',
    [meId]
  );
  if ((Number(active.rows[0] && active.rows[0].n) || 0) >= MAX_ACTIVE_LINKS) {
    throw new HttpError(409, `You can have ${MAX_ACTIVE_LINKS} active family links. Turn one off to create another.`, 'LINK_LIMIT');
  }
  const ins = await db.query(
    `/*q:familyInsertLink*/ INSERT INTO family_links (token, user_id, kind, match_user_id, expires_at)
     VALUES ($1, $2, $3, $4, NOW() + ($5::int * INTERVAL '1 day')) RETURNING id`,
    [newToken(), meId, kind, matchId, LINK_DAYS]
  );
  const row = (await db.query(`/*q:familyLinkById*/ ${LINK_SELECT} WHERE fl.id = $1`, [ins.rows[0].id])).rows[0];
  res.json({ link: linkView(row, req) });
}));

// GET /api/family/links
router.get('/links', registered, wrap(async (req, res) => {
  const r = await db.query(
    `/*q:familyListLinks*/ ${LINK_SELECT} WHERE fl.user_id = $1 AND (fl.revoked_at IS NULL OR fl.revoked_at > NOW() - INTERVAL '30 days')
     ORDER BY fl.id DESC LIMIT 30`,
    [req.user.userId]
  );
  res.json({ links: r.rows.map((l) => linkView(l, req)), maxActive: MAX_ACTIVE_LINKS });
}));

// DELETE /api/family/links/:id (revoke; idempotent)
router.delete('/links/:id', registered, wrap(async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw new HttpError(404, 'Link not found', 'NOT_FOUND');
  const r = await db.query(
    `/*q:familyRevoke*/ UPDATE family_links SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP)
     WHERE id = $1 AND user_id = $2 RETURNING id`,
    [id, req.user.userId]
  );
  if (!r.rows.length) throw new HttpError(404, 'Link not found', 'NOT_FOUND');
  const row = (await db.query(`/*q:familyLinkById*/ ${LINK_SELECT} WHERE fl.id = $1`, [id])).rows[0];
  res.json({ link: linkView(row, req) });
}));

// GET /api/family/notes
router.get('/notes', registered, wrap(async (req, res) => {
  const r = await db.query(
    `/*q:familyListNotes*/ SELECT fn.id, fn.link_id, fn.name, fn.relation, fn.message, fn.created_at,
            fl.kind, fl.match_user_id, mbp.display_name AS match_display_name
     FROM family_notes fn
     JOIN family_links fl ON fl.id = fn.link_id
     LEFT JOIN buddy_profiles mbp ON mbp.user_id = fl.match_user_id
     WHERE fn.user_id = $1
     ORDER BY fn.id DESC LIMIT 100`,
    [req.user.userId]
  );
  res.json({
    notes: r.rows.map((n) => ({
      id: Number(n.id),
      linkId: Number(n.link_id),
      name: n.name,
      relation: n.relation,
      message: n.message,
      about: n.kind === 'match' ? (n.match_display_name || 'a match') : null,
      createdAt: iso(n.created_at),
    })),
  });
}));

// DELETE /api/family/notes/:id
router.delete('/notes/:id', registered, wrap(async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw new HttpError(404, 'Note not found', 'NOT_FOUND');
  const r = await db.query('/*q:familyDeleteNote*/ DELETE FROM family_notes WHERE id = $1 AND user_id = $2 RETURNING id', [id, req.user.userId]);
  if (!r.rows.length) throw new HttpError(404, 'Note not found', 'NOT_FOUND');
  res.json({ ok: true });
}));

// ---------------------------------------------------------------------------
// Public side
// ---------------------------------------------------------------------------

/** Public summary of a person: no birth date/time/place, coordinates, email, phone or photos. */
async function publicPerson(row) {
  const r = await db.query('/*q:familyPlanets*/ SELECT planetary_positions FROM kundlis WHERE user_id = $1', [row.user_id]);
  const planets = r.rows[0] ? r.rows[0].planetary_positions : null;
  const intents = asArray(row.intents);
  return {
    displayName: row.display_name || B.firstName(row.full_name) || 'Buddy',
    age: M.ageOn(B.isoDate(row.date_of_birth), B.todayIST()),
    city: row.city || null,
    bio: row.bio || '',
    intents: intents.map((key) => ({ key, label: B.intentLabel(key) })),
    languages: asArray(row.languages),
    verified: B.isVerified(row),
    phoneVerified: B.isPhoneVerified(row),
    kundli: { moonSign: row.moon_sign || null, nakshatra: row.nakshatra || null, manglik: T.manglikFrom(planets) },
    biodata: T.biodataView(row.biodata),
  };
}

/** Resolves a token to a live link + the people it shows, or throws 404. */
async function resolveLink(token) {
  if (typeof token !== 'string' || !TOKEN_RE.test(token)) throw new HttpError(404, 'This link is not valid', 'NOT_FOUND');
  const r = await db.query(
    '/*q:familyLinkByToken*/ SELECT id, token, user_id, kind, match_user_id, created_at, expires_at, revoked_at FROM family_links WHERE token = $1',
    [token]
  );
  const link = r.rows[0];
  if (!link) throw new HttpError(404, 'This link is not valid', 'NOT_FOUND');
  if (!linkActive(link)) throw new HttpError(404, 'This link has expired or was turned off', 'LINK_EXPIRED');
  const ownerId = Number(link.user_id);
  const owner = await B.loadPerson(ownerId);
  const unavailable = () => new HttpError(404, 'This profile is not available right now', 'UNAVAILABLE');
  if (!owner || B.isBanned(owner) || !B.eligibility(owner).eligible) throw unavailable();
  if (link.kind !== 'match') return { link, owner };
  const matchId = Number(link.match_user_id);
  const conn = await acceptedConnection(ownerId, matchId);
  const match = conn ? await B.loadPerson(matchId) : null;
  if (!conn || !match || B.isBanned(match) || !B.eligibility(match).eligible) throw unavailable();
  return { link, owner, match, conn };
}

// GET /api/family/:token
router.get('/:token', wrap(async (req, res) => {
  noStore(res);
  const { link, owner, match, conn } = await resolveLink(req.params.token);
  const out = { kind: link.kind === 'match' ? 'match' : 'self', expiresAt: iso(link.expires_at), relations: RELATIONS };
  if (!match) {
    out.person = await publicPerson(owner);
  } else {
    const me = await B.loadMe(Number(owner.user_id));
    const intent = M.INTENTS.includes(conn.intent) ? conn.intent : 'all';
    const [scored] = await B.scoreRows(me, [match], { intent, maxKm: M.DEFAULT_MAX_KM, fallbackIntent: 'friend' });
    out.sharedBy = { displayName: owner.display_name || B.firstName(owner.full_name) || 'Your family member' };
    out.person = await publicPerson(match);
    out.compatibility = scored
      ? { score: scored.match.score, breakdown: scored.match.breakdown, highlights: scored.match.highlights, intent: conn.intent, intentLabel: B.intentLabel(conn.intent) }
      : null;
  }
  res.json(out);
}));

// POST /api/family/:token/notes {name, relation, message}
router.post('/:token/notes', wrap(async (req, res) => {
  noStore(res);
  const body = req.body || {};
  const name = typeof body.name === 'string' ? body.name.replace(/\s+/g, ' ').trim() : '';
  const relation = typeof body.relation === 'string' ? body.relation.trim() : '';
  const message = typeof body.message === 'string' ? body.message.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim() : '';
  if (!name || name.length > 40) throw new HttpError(400, 'Please write your name (up to 40 letters)', 'INVALID_INPUT');
  if (!RELATIONS.includes(relation)) throw new HttpError(400, 'Choose how you are related', 'INVALID_INPUT');
  if (!message || message.length > 500) throw new HttpError(400, 'Your note can be 1 to 500 characters', 'INVALID_INPUT');
  const { link } = await resolveLink(req.params.token);
  const ip = ipHash(clientIp(req));
  const counts = await db.query(
    `/*q:familyNoteCounts*/ SELECT
       COUNT(*) FILTER (WHERE ip_hash = $2) AS by_ip,
       COUNT(*) AS by_link
     FROM family_notes WHERE link_id = $1 AND created_at > NOW() - INTERVAL '1 day'`,
    [link.id, ip]
  );
  const c = counts.rows[0] || {};
  if ((Number(c.by_ip) || 0) >= NOTES_PER_IP_PER_DAY || (Number(c.by_link) || 0) >= NOTES_PER_LINK_PER_DAY) {
    throw new HttpError(429, 'Thank you! You have sent several notes today. Please try again tomorrow.', 'RATE_LIMITED');
  }
  const ins = await db.query(
    `/*q:familyInsertNote*/ INSERT INTO family_notes (link_id, user_id, name, relation, message, ip_hash)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, created_at`,
    [link.id, link.user_id, name, relation, message, ip]
  );
  const noteId = Number(ins.rows[0].id);
  const preview = message.length > 80 ? `${message.slice(0, 79)}…` : message;
  await push.sendToUser(Number(link.user_id), {
    type: 'family_note',
    title: `A note from ${name} (${relation})`,
    body: preview,
    data: { noteId, linkId: Number(link.id) },
  }, { pref: 'buddy' });
  res.json({ ok: true });
}));

// GET /f/:token -> the family page (no login). Read with fs at a fixed path so Vercel bundles it.
const PAGE_PATH = path.join(__dirname, '..', 'public', 'family.html');
let pageCache = null;
function page(req, res) {
  try {
    if (!pageCache) pageCache = fs.readFileSync(PAGE_PATH, 'utf8');
  } catch (err) {
    console.error('Family page missing:', err.message);
    return res.status(404).json({ error: 'Page not found' });
  }
  noStore(res);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Security-Policy',
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
  res.send(pageCache);
}

router.page = page;
router._internals = { LINK_DAYS, MAX_ACTIVE_LINKS, NOTES_PER_IP_PER_DAY, NOTES_PER_LINK_PER_DAY, RELATIONS, TOKEN_RE, baseUrl, newToken, ipHash };
module.exports = router;
