// Coins economy (server-authoritative). Every change is a row in coin_ledger, which is unique on
// (user_id, reason, ref), so each reward can be paid at most once. Balance = SUM(amount).
// Pure helpers (istDate, streakDays, ...) are unit-tested in test/rewards.test.js.

const GOAL = 10000;
const TRIP_COST = 10000;
const DAILY_COINS = 1;
const GAME_COINS = 10;
const VIDEO_COINS = 1;
const QUESTION_COINS = 50;
// Any well-formed YouTube id is accepted for the video reward, so cap how many pay per IST day;
// without it a script could post random ids and farm a free temple trip.
const VIDEO_DAILY_CAP = 50;
const GAMES = ['quest', 'cards', 'moksha', 'circle'];
const IST = 'Asia/Kolkata';

const EARN_RULES = [
  { key: 'daily_login', title: 'Daily check-in', coins: DAILY_COINS, note: 'Open the app and check in once a day.' },
  { key: 'game', title: 'Play a game', coins: GAME_COINS, note: 'Each game (Graha Quest, Nakshatra Cards, Moksha Patam, Cosmic Circle) pays once a day.' },
  { key: 'video', title: 'Watch a devotional video', coins: VIDEO_COINS, note: `Every new video you watch pays once (up to ${VIDEO_DAILY_CAP} a day).` },
  { key: 'question', title: 'Answer a mindset question', coins: QUESTION_COINS, note: 'First answer to each of the 50 questions. Helps us find your buddy.' },
  { key: 'trip', title: 'Temple trip with a buddy', coins: -TRIP_COST, note: 'Spend 10,000 coins on a temple trip, arranged by our team.' },
];

// 'YYYY-MM-DD' in Asia/Kolkata for the given instant (Date, ms number or ISO string).
function istDate(now = new Date()) {
  const d = now instanceof Date ? now : new Date(now);
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: IST, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(d);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

// 'YYYY-MM' in IST.
function istMonth(now = new Date()) {
  return istDate(now).slice(0, 7);
}

// Shift an ISO date ('YYYY-MM-DD') by n days (calendar arithmetic, timezone free).
function addDays(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return t.toISOString().slice(0, 10);
}

// Consecutive days in `dates` ending today or yesterday (IST). Order and duplicates don't matter.
function streakDays(dates, today = istDate()) {
  const set = new Set((dates || []).map((x) => String(x).slice(0, 10)));
  let cur = set.has(today) ? today : addDays(today, -1);
  let n = 0;
  while (set.has(cur)) {
    n++;
    cur = addDays(cur, -1);
  }
  return n;
}

const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;
function isVideoId(x) {
  return typeof x === 'string' && VIDEO_ID_RE.test(x);
}

function gameRef(game, now = new Date()) {
  return `${game}:${istDate(now)}`;
}

function cleanNote(note) {
  if (note === undefined || note === null) return null;
  const s = String(note).replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, 255) : null;
}

// Inserts a ledger row once. Returns the amount actually applied (0 when already paid).
// `client` is anything with .query (pool or a transaction client).
async function awardCoins(client, userId, amount, reason, ref, note) {
  const r = await client.query(
    `INSERT INTO coin_ledger (user_id, amount, reason, ref, note)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (user_id, reason, ref) DO NOTHING
     RETURNING id`,
    [userId, amount, String(reason).slice(0, 40), String(ref).slice(0, 160), cleanNote(note)]
  );
  return r.rows.length > 0 ? amount : 0;
}

async function balanceOf(client, userId) {
  const r = await client.query('SELECT COALESCE(SUM(amount), 0) AS balance FROM coin_ledger WHERE user_id = $1', [userId]);
  return Number(r.rows[0] && r.rows[0].balance) || 0;
}

async function streakOf(client, userId, today = istDate()) {
  const r = await client.query(
    `SELECT ref FROM coin_ledger WHERE user_id = $1 AND reason = 'daily_login' ORDER BY ref DESC LIMIT 400`,
    [userId]
  );
  return streakDays(r.rows.map((x) => x.ref), today);
}

// Game hook: +10 once per game per IST day for registered users. Returns 0 or GAME_COINS.
async function awardGameCoins(client, userId, game, registered, now = new Date()) {
  if (!registered || !GAMES.includes(game)) return 0;
  return awardCoins(client, userId, GAME_COINS, 'game', gameRef(game, now), `Played ${game}`);
}

function ledgerRow(r) {
  return {
    id: r.id,
    amount: Number(r.amount),
    reason: r.reason,
    ref: r.ref,
    note: r.note || null,
    createdAt: r.created_at instanceof Date ? r.created_at.toISOString() : r.created_at,
  };
}

// Express middleware (after optionalAuthenticateToken): registered accounts only.
function requireRegistered(message = 'Please log in to earn and use coins.') {
  return (req, res, next) => {
    if (!req.user || req.user.role === 'guest') {
      return res.status(401).json({ error: message, code: 'LOGIN_REQUIRED' });
    }
    return next();
  };
}

module.exports = {
  requireRegistered,
  GOAL,
  TRIP_COST,
  DAILY_COINS,
  GAME_COINS,
  VIDEO_COINS,
  VIDEO_DAILY_CAP,
  QUESTION_COINS,
  GAMES,
  EARN_RULES,
  istDate,
  istMonth,
  addDays,
  streakDays,
  isVideoId,
  gameRef,
  cleanNote,
  awardCoins,
  balanceOf,
  streakOf,
  awardGameCoins,
  ledgerRow,
};
