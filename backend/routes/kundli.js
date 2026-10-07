const express = require('express');
const router = express.Router();
const db = require('../db');
const {
  authenticateToken,
  optionalAuthenticateToken,
  guestOrAuthenticateToken,
  kundliFromRow
} = require('./auth');
const {
  calculateKundliWithAI,
  generateAIKundliReport,
  refreshDashaInfo,
  recomputeLegacyKundli,
  resolveTimeZone,
  timezoneForLocation,
  AstrologyInputError
} = require('../services/astrology_service');

const MAX_TEXT = 255;

function str(value, max = MAX_TEXT) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function timezoneLabel(timezone) {
  // Normalised representation that is stored and echoed back
  const tz = resolveTimeZone(timezone);
  if (tz.type === 'iana') return tz.zone;
  const m = Math.abs(tz.minutes);
  return `${tz.minutes >= 0 ? '+' : '-'}${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

function handleError(res, error, fallbackMessage) {
  if (error instanceof AstrologyInputError) {
    return res.status(400).json({ error: error.message });
  }
  console.error(fallbackMessage, error);
  return res.status(500).json({ error: fallbackMessage });
}

// POST /api/kundli/ai-report
// Generates an AI interpretation for an already-computed Kundli payload.
router.post('/ai-report', optionalAuthenticateToken, async (req, res) => {
  try {
    const { kundli, birthDetails } = req.body || {};
    if (!kundli || typeof kundli !== 'object' || Array.isArray(kundli) || !kundli.ascendant) {
      return res.status(400).json({ error: 'A Kundli payload with at least an ascendant is required' });
    }
    const details = birthDetails && typeof birthDetails === 'object' ? birthDetails : (kundli.birthDetails || {});
    const reportMarkdown = await generateAIKundliReport(refreshDashaInfo(kundli), details);
    res.json({ aiReport: reportMarkdown });
  } catch (error) {
    handleError(res, error, 'Failed to generate AI Kundli Report');
  }
});

// POST /api/kundli/generate
// Calculates the chart and stores birth details + Kundli for the (guest or registered) user.
router.post('/generate', guestOrAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const body = req.body || {};
    const fullName = str(body.fullName);
    const gender = str(body.gender, 50) || 'Not Specified';
    const dateOfBirth = str(body.dateOfBirth, 20);
    const timeOfBirth = str(body.timeOfBirth, 20);
    const placeOfBirth = str(body.placeOfBirth);
    const { latitude, longitude } = body;

    if (!fullName || !dateOfBirth || !timeOfBirth || !placeOfBirth) {
      return res.status(400).json({ error: 'Full name, date of birth, time of birth, and place of birth are required' });
    }
    const timezone = timezoneLabel(timezoneForLocation(body.timezone, latitude, longitude));

    const birthTimeKnown = body.birthTimeKnown !== false;
    const birthDetails = { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth, birthTimeKnown };
    const kundliData = await calculateKundliWithAI(
      dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude, birthDetails, timezone
    );

    const fullBirthDetails = {
      ...birthDetails,
      latitude: kundliData.latitude,
      longitude: kundliData.longitude,
      timezone
    };

    await db.withTransaction(async (client) => {
      await client.query(
        `INSERT INTO birth_details (user_id, full_name, gender, date_of_birth, time_of_birth, place_of_birth, latitude, longitude, timezone)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (user_id) DO UPDATE SET
           full_name = EXCLUDED.full_name,
           gender = EXCLUDED.gender,
           date_of_birth = EXCLUDED.date_of_birth,
           time_of_birth = EXCLUDED.time_of_birth,
           place_of_birth = EXCLUDED.place_of_birth,
           latitude = EXCLUDED.latitude,
           longitude = EXCLUDED.longitude,
           timezone = EXCLUDED.timezone,
           updated_at = CURRENT_TIMESTAMP`,
        [userId, fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth, kundliData.latitude, kundliData.longitude, timezone]
      );

      await client.query(
        `INSERT INTO kundlis (user_id, ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada, planetary_positions, houses, dasha_info, ai_report, kundli_data)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (user_id) DO UPDATE SET
           ascendant = EXCLUDED.ascendant,
           sun_sign = EXCLUDED.sun_sign,
           moon_sign = EXCLUDED.moon_sign,
           nakshatra = EXCLUDED.nakshatra,
           nakshatra_pada = EXCLUDED.nakshatra_pada,
           planetary_positions = EXCLUDED.planetary_positions,
           houses = EXCLUDED.houses,
           dasha_info = EXCLUDED.dasha_info,
           ai_report = EXCLUDED.ai_report,
           kundli_data = EXCLUDED.kundli_data,
           updated_at = CURRENT_TIMESTAMP`,
        [
          userId,
          kundliData.ascendant,
          kundliData.sunSign,
          kundliData.moonSign,
          kundliData.nakshatra,
          kundliData.nakshatraPada,
          JSON.stringify(kundliData.planetaryPositions),
          JSON.stringify(kundliData.houses),
          JSON.stringify(kundliData.dashaInfo),
          kundliData.aiReport || '',
          JSON.stringify(kundliData)
        ]
      );

      // Daily transit cache was computed against the old chart
      await client.query('DELETE FROM daily_horoscopes WHERE user_id = $1', [userId]);
    });

    res.json({
      message: 'Kundli generated and saved successfully',
      kundli: {
        ...kundliData,
        birthDetails: fullBirthDetails
      }
    });
  } catch (error) {
    handleError(res, error, 'Failed to generate Kundli chart');
  }
});

// GET /api/kundli
router.get('/', authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      `SELECT bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude, bd.timezone,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info, k.ai_report, k.kundli_data
       FROM birth_details bd
       LEFT JOIN kundlis k ON bd.user_id = k.user_id
       WHERE bd.user_id = $1`,
      [req.user.userId]
    );

    const kundli = kundliFromRow(result.rows[0]);
    if (!kundli) {
      return res.status(404).json({ error: 'Birth details or Kundli not found for user' });
    }

    res.json({ birthDetails: kundli.birthDetails, kundli });
  } catch (error) {
    handleError(res, error, 'Failed to fetch Kundli chart');
  }
});

// =====================================================
// FAMILY KUNDLIS (multiple profiles per account)
// =====================================================

function familyMemberFromRow(row) {
  const stored = row.kundli_data && typeof row.kundli_data === 'object' ? row.kundli_data : null;
  const legacy = stored ? null : recomputeLegacyKundli(row);
  const full = stored || {};
  const kundli = refreshDashaInfo({
    ...full,
    ascendant: row.ascendant,
    sunSign: row.sun_sign,
    moonSign: row.moon_sign,
    nakshatra: row.nakshatra,
    nakshatraPada: row.nakshatra_pada,
    planetaryPositions: row.planetary_positions,
    houses: row.houses,
    dashaInfo: row.dasha_info,
    ...(legacy || {}),
    aiReport: row.ai_report || full.aiReport || null
  });
  const birthDetails = {
    fullName: row.full_name,
    gender: row.gender,
    dateOfBirth: row.date_of_birth,
    timeOfBirth: row.time_of_birth,
    placeOfBirth: row.place_of_birth,
    latitude: row.latitude,
    longitude: row.longitude,
    timezone: row.timezone
  };
  kundli.birthDetails = birthDetails;
  // Backwards-compatible snake_case alias
  kundli.nakshatra_pada = row.nakshatra_pada;
  return {
    id: row.id,
    relationship: row.relationship,
    fullName: row.full_name,
    gender: row.gender,
    dateOfBirth: row.date_of_birth,
    timeOfBirth: row.time_of_birth,
    placeOfBirth: row.place_of_birth,
    latitude: row.latitude,
    longitude: row.longitude,
    timezone: row.timezone,
    createdAt: row.created_at,
    kundli
  };
}

// POST /api/kundli/family/add
router.post('/family/add', guestOrAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const body = req.body || {};
    const relationship = str(body.relationship, 100);
    const fullName = str(body.fullName);
    const gender = str(body.gender, 50) || 'Not Specified';
    const dateOfBirth = str(body.dateOfBirth, 20);
    const timeOfBirth = str(body.timeOfBirth, 20);
    const placeOfBirth = str(body.placeOfBirth);
    const { latitude, longitude } = body;

    if (!relationship || !fullName || !dateOfBirth || !timeOfBirth || !placeOfBirth) {
      return res.status(400).json({ error: 'Relationship, full name, date of birth, time of birth, and place of birth are required' });
    }
    const timezone = timezoneLabel(timezoneForLocation(body.timezone, latitude, longitude));

    const kundliData = await calculateKundliWithAI(
      dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude,
      { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth, birthTimeKnown: body.birthTimeKnown !== false },
      timezone
    );

    const inserted = await db.withTransaction(async (client) => {
      // Replace an existing profile for the same family member
      await client.query(
        'DELETE FROM family_kundlis WHERE user_id = $1 AND LOWER(full_name) = LOWER($2)',
        [userId, fullName]
      );
      const insertQuery = await client.query(
        `INSERT INTO family_kundlis
          (user_id, relationship, full_name, gender, date_of_birth, time_of_birth, place_of_birth, latitude, longitude, timezone,
           ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada, planetary_positions, houses, dasha_info, ai_report, kundli_data)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20)
         RETURNING *`,
        [
          userId, relationship, fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth,
          kundliData.latitude, kundliData.longitude, timezone,
          kundliData.ascendant, kundliData.sunSign, kundliData.moonSign, kundliData.nakshatra, kundliData.nakshatraPada,
          JSON.stringify(kundliData.planetaryPositions),
          JSON.stringify(kundliData.houses),
          JSON.stringify(kundliData.dashaInfo),
          kundliData.aiReport || '',
          JSON.stringify(kundliData)
        ]
      );
      return insertQuery.rows[0];
    });

    res.status(201).json({
      message: 'Family member Kundli created and saved successfully',
      familyMember: familyMemberFromRow(inserted)
    });
  } catch (error) {
    handleError(res, error, 'Failed to add family member Kundli');
  }
});

// GET /api/kundli/family/list
router.get('/family/list', optionalAuthenticateToken, async (req, res) => {
  try {
    if (!req.user) return res.json({ familyMembers: [] });

    const result = await db.query(
      `SELECT * FROM family_kundlis WHERE user_id = $1 ORDER BY created_at DESC, id DESC`,
      [req.user.userId]
    );
    res.json({ familyMembers: result.rows.map(familyMemberFromRow) });
  } catch (error) {
    handleError(res, error, 'Failed to fetch family Kundlis');
  }
});

// PUT /api/kundli/family/:id
// Partial update; any omitted field keeps its stored value. The chart is recalculated.
router.put('/family/:id', authenticateToken, async (req, res) => {
  try {
    const familyId = Number(req.params.id);
    if (!Number.isInteger(familyId) || familyId <= 0) {
      return res.status(400).json({ error: 'Invalid family member id' });
    }
    const userId = req.user.userId;
    const existingRes = await db.query('SELECT * FROM family_kundlis WHERE id = $1 AND user_id = $2', [familyId, userId]);
    const existing = existingRes.rows[0];
    if (!existing) return res.status(404).json({ error: 'Family member not found' });

    const body = req.body || {};
    const pick = (key, max, current) => (body[key] !== undefined ? str(body[key], max) : current);
    const relationship = pick('relationship', 100, existing.relationship);
    const fullName = pick('fullName', MAX_TEXT, existing.full_name);
    const gender = pick('gender', 50, existing.gender) || 'Not Specified';
    const dateOfBirth = pick('dateOfBirth', 20, existing.date_of_birth);
    const timeOfBirth = pick('timeOfBirth', 20, existing.time_of_birth);
    const placeOfBirth = pick('placeOfBirth', MAX_TEXT, existing.place_of_birth);
    const latitude = body.latitude !== undefined ? body.latitude : existing.latitude;
    const longitude = body.longitude !== undefined ? body.longitude : existing.longitude;
    // Keep the stored zone unless the place moved; a new place gets a fresh lookup
    const placeMoved = body.latitude !== undefined || body.longitude !== undefined;
    const timezone = timezoneLabel(timezoneForLocation(
      body.timezone !== undefined ? body.timezone : (placeMoved ? undefined : existing.timezone),
      latitude, longitude
    ));

    if (!relationship || !fullName || !dateOfBirth || !timeOfBirth || !placeOfBirth) {
      return res.status(400).json({ error: 'Relationship, full name, date of birth, time of birth, and place of birth cannot be empty' });
    }

    const kundliData = await calculateKundliWithAI(
      dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude,
      {
        fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth,
        // Keep the stored flag unless the caller sends a new time or flag
        birthTimeKnown: body.birthTimeKnown !== undefined || body.timeOfBirth !== undefined
          ? body.birthTimeKnown !== false
          : !(existing.kundli_data && existing.kundli_data.birthTime && existing.kundli_data.birthTime.known === false)
      },
      timezone
    );

    const updated = await db.query(
      `UPDATE family_kundlis SET
         relationship = $3, full_name = $4, gender = $5, date_of_birth = $6, time_of_birth = $7, place_of_birth = $8,
         latitude = $9, longitude = $10, timezone = $11,
         ascendant = $12, sun_sign = $13, moon_sign = $14, nakshatra = $15, nakshatra_pada = $16,
         planetary_positions = $17, houses = $18, dasha_info = $19, ai_report = $20, kundli_data = $21
       WHERE id = $1 AND user_id = $2
       RETURNING *`,
      [
        familyId, userId, relationship, fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth,
        kundliData.latitude, kundliData.longitude, timezone,
        kundliData.ascendant, kundliData.sunSign, kundliData.moonSign, kundliData.nakshatra, kundliData.nakshatraPada,
        JSON.stringify(kundliData.planetaryPositions),
        JSON.stringify(kundliData.houses),
        JSON.stringify(kundliData.dashaInfo),
        kundliData.aiReport || '',
        JSON.stringify(kundliData)
      ]
    );
    if (updated.rows.length === 0) return res.status(404).json({ error: 'Family member not found' });

    res.json({ message: 'Family member updated successfully', familyMember: familyMemberFromRow(updated.rows[0]) });
  } catch (error) {
    handleError(res, error, 'Failed to update family member Kundli');
  }
});

// DELETE /api/kundli/family/:id
router.delete('/family/:id', authenticateToken, async (req, res) => {
  try {
    const familyId = Number(req.params.id);
    if (!Number.isInteger(familyId) || familyId <= 0) {
      return res.status(400).json({ error: 'Invalid family member id' });
    }

    const result = await db.query(
      'DELETE FROM family_kundlis WHERE id = $1 AND user_id = $2 RETURNING id',
      [familyId, req.user.userId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Family member not found' });
    }

    res.json({ message: 'Family Kundli deleted successfully', id: familyId });
  } catch (error) {
    handleError(res, error, 'Failed to delete family Kundli');
  }
});

module.exports = router;
