// Coins API (/api/coins): balance, daily check-in, video rewards and the 50 mindset questions.
// All amounts are decided here; the client only asks. See services/coins_service.js.
const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const C = require('../services/coins_service');
const QUESTIONS = require('../data/mindset_questions.json');

const QUESTION_BY_ID = new Map(QUESTIONS.map((q) => [q.id, q]));
const PUBLIC_QUESTIONS = QUESTIONS.map((q) => ({ id: q.id, text: q.text, category: q.category, options: q.options.slice() }));

const auth = [optionalAuthenticateToken, C.requireRegistered('Please log in to earn and use coins.')];

function handle(fn) {
  return async (req, res) => {
    try {
      res.json(await fn(req, res));
    } catch (err) {
      if (err && err.statusCode && err.publicMessage) {
        return res.status(err.statusCode).json({ error: err.publicMessage, ...(err.code ? { code: err.code } : {}) });
      }
      console.error('Coins error:', err);
      res.status(500).json({ error: 'Something went wrong with your coins. Please try again.' });
    }
  };
}

function badRequest(message, code = 'BAD_REQUEST', statusCode = 400) {
  const e = new Error(message);
  e.statusCode = statusCode;
  e.publicMessage = message;
  e.code = code;
  return e;
}

// GET /api/coins
router.get('/', auth, handle(async (req) => {
  const userId = req.user.userId;
  const today = C.istDate();
  const [balance, todayRow, dailyRow, streak, recent] = await Promise.all([
    C.balanceOf(db, userId),
    db.query(
      `SELECT COALESCE(SUM(amount), 0) AS earned FROM coin_ledger
       WHERE user_id = $1 AND amount > 0 AND reason <> 'trip_refund'
         AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = $2::date`,
      [userId, today]
    ),
    db.query(`SELECT 1 FROM coin_ledger WHERE user_id = $1 AND reason = 'daily_login' AND ref = $2`, [userId, today]),
    C.streakOf(db, userId, today),
    db.query(
      `SELECT id, amount, reason, ref, note, created_at FROM coin_ledger WHERE user_id = $1 ORDER BY id DESC LIMIT 30`,
      [userId]
    ),
  ]);
  return {
    balance,
    goal: C.GOAL,
    todayEarned: Number(todayRow.rows[0] && todayRow.rows[0].earned) || 0,
    dailyClaimed: dailyRow.rows.length > 0,
    streakDays: streak,
    earnRules: C.EARN_RULES.map((r) => ({ ...r })),
    recent: recent.rows.map(C.ledgerRow),
  };
}));

// POST /api/coins/daily
router.post('/daily', auth, handle(async (req) => {
  const userId = req.user.userId;
  const today = C.istDate();
  const awarded = await C.awardCoins(db, userId, C.DAILY_COINS, 'daily_login', today, 'Daily check-in');
  const [balance, streak] = await Promise.all([C.balanceOf(db, userId), C.streakOf(db, userId, today)]);
  return { awarded, balance, streakDays: streak };
}));

// POST /api/coins/video {videoId, title?}
router.post('/video', auth, handle(async (req) => {
  const body = req.body || {};
  const videoId = typeof body.videoId === 'string' ? body.videoId.trim() : '';
  if (!C.isVideoId(videoId)) throw badRequest('That does not look like a valid video.', 'BAD_VIDEO_ID');
  const title = typeof body.title === 'string' ? body.title : null;
  const userId = req.user.userId;
  const today = C.istDate();
  return db.withTransaction(async (client) => {
    // Serialise this account's video rewards so parallel requests cannot overshoot the daily cap.
    await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [userId]);
    const paid = await client.query(
      `SELECT COUNT(*) AS n FROM coin_ledger
       WHERE user_id = $1 AND reason = 'video' AND (created_at AT TIME ZONE 'Asia/Kolkata')::date = $2::date`,
      [userId, today]
    );
    if ((Number(paid.rows[0] && paid.rows[0].n) || 0) >= C.VIDEO_DAILY_CAP) {
      return { awarded: 0, balance: await C.balanceOf(client, userId), dailyCapReached: true };
    }
    const awarded = await C.awardCoins(client, userId, C.VIDEO_COINS, 'video', videoId, title ? `Watched: ${title}` : 'Watched a video');
    return { awarded, balance: await C.balanceOf(client, userId) };
  });
}));

// GET /api/coins/questions
router.get('/questions', auth, handle(async (req) => {
  const r = await db.query('SELECT question_id, option_index FROM mindset_answers WHERE user_id = $1', [req.user.userId]);
  const answers = {};
  for (const row of r.rows) {
    const q = QUESTION_BY_ID.get(row.question_id);
    const idx = Number(row.option_index);
    if (q && Number.isInteger(idx) && idx >= 0 && idx < q.options.length) answers[row.question_id] = idx;
  }
  return {
    questions: PUBLIC_QUESTIONS,
    answers,
    answeredCount: Object.keys(answers).length,
    coinsPerQuestion: C.QUESTION_COINS,
  };
}));

// POST /api/coins/questions/:id/answer {optionIndex}
router.post('/questions/:id/answer', auth, handle(async (req) => {
  const q = QUESTION_BY_ID.get(String(req.params.id || ''));
  if (!q) throw badRequest('That question does not exist.', 'QUESTION_NOT_FOUND', 404);
  const raw = req.body ? req.body.optionIndex : undefined;
  const optionIndex = typeof raw === 'string' && /^\d+$/.test(raw) ? Number(raw) : raw;
  if (!Number.isInteger(optionIndex) || optionIndex < 0 || optionIndex >= q.options.length) {
    throw badRequest('Please pick one of the options.', 'BAD_OPTION');
  }
  const userId = req.user.userId;
  return db.withTransaction(async (client) => {
    await client.query(
      `INSERT INTO mindset_answers (user_id, question_id, option_index) VALUES ($1, $2, $3)
       ON CONFLICT (user_id, question_id) DO UPDATE SET option_index = EXCLUDED.option_index, answered_at = CURRENT_TIMESTAMP`,
      [userId, q.id, optionIndex]
    );
    const awarded = await C.awardCoins(client, userId, C.QUESTION_COINS, 'question', q.id, `Answered: ${q.text}`);
    const count = await client.query(
      'SELECT COUNT(*) AS n FROM mindset_answers WHERE user_id = $1 AND question_id = ANY($2::text[])',
      [userId, QUESTIONS.map((x) => x.id)]
    );
    return {
      awarded,
      balance: await C.balanceOf(client, userId),
      answeredCount: Number(count.rows[0] && count.rows[0].n) || 0,
    };
  });
}));

module.exports = router;
