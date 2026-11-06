// Muhurat finder API (works for guests; a logged-in user's Kundli adds a light personal factor).
//   GET /api/muhurat/events                       -> { events: [{ id, label, labelHi, icon, category, note }] }
//   GET /api/muhurat?event=&lat=&lng=&tz=&from=YYYY-MM-DD&days=30 (max 60)&personal=0|1
// See services/muhurat_service.js and data/muhurat_rules.json for the rules.
const express = require('express');
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const M = require('../services/muhurat_service');

const router = express.Router();

router.get('/events', (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600');
  res.json({ events: M.listEvents(), disclaimer: M.DISCLAIMER });
});

// Birth nakshatra + Moon sign of the signed-in user (only these two facts are read; nothing is returned).
async function personalFor(req) {
  if (!req.user || req.query.personal === '0') return null;
  try {
    const r = await db.query('SELECT moon_sign, nakshatra FROM kundlis WHERE user_id = $1', [req.user.userId]);
    return M.personalFromKundli(r.rows[0]);
  } catch (e) {
    console.warn('muhurat: kundli lookup failed', e.message);
    return null;
  }
}

router.get('/', optionalAuthenticateToken, async (req, res) => {
  try {
    M.normaliseQuery(req.query); // validate before touching the DB
    const personal = await personalFor(req);
    const out = M.findMuhurat(req.query, { personal });
    if (!personal) res.set('Cache-Control', 'public, max-age=1800');
    else res.set('Cache-Control', 'private, no-store');
    res.json(out);
  } catch (e) {
    if (e instanceof M.MuhuratInputError) return res.status(400).json({ error: e.message, code: e.code });
    console.error('muhurat failed', e);
    return res.status(500).json({ error: 'Could not calculate muhurat right now' });
  }
});

module.exports = router;
