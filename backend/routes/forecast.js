// Personal forecast API: GET /api/forecast/day | /week | /month | /timeline
// Profile: the caller's own Kundli, or a family member's (familyId, must belong to the caller).
const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken, kundliFromRow } = require('./auth');
const F = require('../services/forecast_service');
const { AstrologyInputError } = require('../services/astrology_service');

class BadRequest extends Error {
  constructor(message) {
    super(message);
    this.statusCode = 400;
  }
}

function parseIsoParam(value, label) {
  if (value === undefined || value === '') return null;
  const v = String(value).trim();
  if (!F.isValidIso(v)) throw new BadRequest(`${label} must be a valid date in YYYY-MM-DD format`);
  const y = Number(v.slice(0, 4));
  if (y < 1900 || y > 2100) throw new BadRequest(`${label} year must be between 1900 and 2100`);
  return v;
}

function parseCoord(value, min, max, label) {
  if (value === undefined || value === '') return undefined;
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) throw new BadRequest(`${label} must be a number between ${min} and ${max}`);
  return n;
}

function parseFamilyId(value) {
  if (value === undefined || value === '') return null;
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) throw new BadRequest('familyId must be a positive integer');
  return n;
}

const noKundli = (res) => res.status(409).json({ error: 'No Kundli found for this profile. Generate a Kundli first.', code: 'NO_KUNDLI' });

// Resolves { kundli, profile, profileKey } or sends the error response and returns null
async function resolveProfile(req, res) {
  const familyId = parseFamilyId(req.query.familyId);
  if (familyId !== null) {
    if (!req.user) {
      res.status(404).json({ error: 'Family member not found' });
      return null;
    }
    const r = await db.query('SELECT * FROM family_kundlis WHERE id = $1 AND user_id = $2', [familyId, req.user.userId]);
    const row = r.rows[0];
    if (!row) {
      res.status(404).json({ error: 'Family member not found' });
      return null;
    }
    const kundli = kundliFromRow(row);
    if (!kundli) {
      noKundli(res);
      return null;
    }
    return {
      kundli,
      profileKey: `family:${familyId}`,
      profile: { name: row.full_name, isFamily: true, familyId, relationship: row.relationship || null }
    };
  }
  if (!req.user) {
    noKundli(res);
    return null;
  }
  const r = await db.query(
    `SELECT bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude, bd.timezone,
            k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada, k.planetary_positions, k.houses,
            k.dasha_info, k.ai_report, k.kundli_data
     FROM birth_details bd
     JOIN kundlis k ON bd.user_id = k.user_id
     WHERE bd.user_id = $1`,
    [req.user.userId]
  );
  const row = r.rows[0];
  const kundli = kundliFromRow(row);
  if (!kundli) {
    noKundli(res);
    return null;
  }
  return {
    kundli,
    profileKey: 'self',
    profile: { name: row.full_name || 'You', isFamily: false, familyId: null, relationship: null }
  };
}

// AI narrative with a per-profile, per-period cache. Never changes scores/facts; any failure keeps rules text.
async function withNarrative(req, ctx, resolved, payload, periodType, periodKey) {
  try {
    if (!req.user) return payload;
    const params = [req.user.userId, resolved.profileKey, periodType, periodKey, ctx.hash];
    const cached = await db.query(
      `SELECT payload FROM forecast_cache
       WHERE user_id = $1 AND profile_key = $2 AND period_type = $3 AND period_key = $4 AND kundli_hash = $5`,
      params
    );
    if (cached.rows[0] && cached.rows[0].payload && cached.rows[0].payload.headline) {
      return F.applyNarrative(payload, cached.rows[0].payload);
    }
    const n = await F.aiNarrative(payload);
    if (!n) return payload;
    await db.query(
      `INSERT INTO forecast_cache (user_id, profile_key, period_type, period_key, kundli_hash, payload)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (user_id, profile_key, period_type, period_key, kundli_hash) DO UPDATE SET payload = EXCLUDED.payload`,
      [...params, JSON.stringify(n)]
    );
    return F.applyNarrative(payload, n);
  } catch (err) {
    console.warn('Forecast narrative skipped:', err && err.message ? err.message : err);
    return payload;
  }
}

function handle(builder) {
  return async (req, res) => {
    try {
      const lat = parseCoord(req.query.lat, -90, 90, 'lat');
      const lng = parseCoord(req.query.lng, -180, 180, 'lng');
      const args = builder.parse(req.query);
      const resolved = await resolveProfile(req, res);
      if (!resolved) return;
      const ctx = F.createContext(resolved.kundli, { lat, lng, profile: resolved.profile });
      let payload = builder.build(ctx, args);
      if (builder.period) {
        const [type, key] = builder.period(payload);
        payload = await withNarrative(req, ctx, resolved, payload, type, key);
      }
      res.json(payload);
    } catch (err) {
      if (err instanceof BadRequest || err instanceof AstrologyInputError) return res.status(400).json({ error: err.message });
      if (err instanceof F.ForecastError) {
        const body = { error: err.message };
        if (err.code) body.code = err.code;
        return res.status(err.statusCode || 400).json(body);
      }
      console.error('Forecast error:', err);
      res.status(500).json({ error: 'Failed to compute forecast' });
    }
  };
}

// GET /api/forecast/day?date=YYYY-MM-DD
router.get('/day', optionalAuthenticateToken, handle({
  parse: (q) => ({ date: parseIsoParam(q.date, 'date') }),
  build: (ctx, a) => F.buildDay(ctx, a.date),
  period: (p) => ['day', p.date]
}));

// GET /api/forecast/week?start=YYYY-MM-DD (snapped to Monday)
router.get('/week', optionalAuthenticateToken, handle({
  parse: (q) => ({ start: parseIsoParam(q.start, 'start') }),
  build: (ctx, a) => F.buildWeek(ctx, a.start),
  period: (p) => ['week', p.weekStart]
}));

// GET /api/forecast/month?month=YYYY-MM
router.get('/month', optionalAuthenticateToken, handle({
  parse: (q) => {
    if (q.month === undefined || q.month === '') return { month: null };
    const m = String(q.month).trim();
    if (!/^\d{4}-\d{2}$/.test(m) || !F.isValidIso(`${m}-01`)) throw new BadRequest('month must be in YYYY-MM format');
    const y = Number(m.slice(0, 4));
    if (y < 1900 || y > 2100) throw new BadRequest('month year must be between 1900 and 2100');
    return { month: m };
  },
  build: (ctx, a) => F.buildMonth(ctx, a.month),
  period: (p) => ['month', p.month]
}));

// GET /api/forecast/timeline?from=YYYY-MM-DD&years=N (default from = today - 2y, years = 6, max 30)
router.get('/timeline', optionalAuthenticateToken, handle({
  parse: (q) => {
    const from = parseIsoParam(q.from, 'from');
    let years = 6;
    if (q.years !== undefined && q.years !== '') {
      years = Number(q.years);
      if (!Number.isInteger(years) || years < 1 || years > 30) throw new BadRequest('years must be an integer between 1 and 30');
    }
    return { from, years };
  },
  build: (ctx, a) => F.buildTimeline(ctx, a.from, a.years)
}));

module.exports = router;
