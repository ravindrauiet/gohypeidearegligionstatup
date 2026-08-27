const express = require('express');
const router = express.Router();
const db = require('../db');
const { authenticateToken } = require('./auth');
const { calculateKundli } = require('../services/astrology_service');

// POST /api/kundli/generate
// Saves birth details and calculates/stores Kundli chart
router.post('/generate', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude } = req.body;

    if (!fullName || !dateOfBirth || !timeOfBirth || !placeOfBirth) {
      return res.status(400).json({ error: 'Full name, date of birth, time of birth, and place of birth are required' });
    }

    // 1. Calculate Kundli Chart
    const kundliData = calculateKundli(dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude);

    // 2. Save / Update Birth Details in Neon DB
    await db.query(
      `INSERT INTO birth_details (user_id, full_name, gender, date_of_birth, time_of_birth, place_of_birth, latitude, longitude)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (user_id) DO UPDATE SET
         full_name = EXCLUDED.full_name,
         gender = EXCLUDED.gender,
         date_of_birth = EXCLUDED.date_of_birth,
         time_of_birth = EXCLUDED.time_of_birth,
         place_of_birth = EXCLUDED.place_of_birth,
         latitude = EXCLUDED.latitude,
         longitude = EXCLUDED.longitude,
         updated_at = CURRENT_TIMESTAMP`,
      [userId, fullName, gender || 'Not Specified', dateOfBirth, timeOfBirth, placeOfBirth, latitude || 28.6139, longitude || 77.2090]
    );

    // 3. Save / Update Kundli in Neon DB
    const kundliResult = await db.query(
      `INSERT INTO kundlis (user_id, ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada, planetary_positions, houses, dasha_info)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       ON CONFLICT (user_id) DO UPDATE SET
         ascendant = EXCLUDED.ascendant,
         sun_sign = EXCLUDED.sun_sign,
         moon_sign = EXCLUDED.moon_sign,
         nakshatra = EXCLUDED.nakshatra,
         nakshatra_pada = EXCLUDED.nakshatra_pada,
         planetary_positions = EXCLUDED.planetary_positions,
         houses = EXCLUDED.houses,
         dasha_info = EXCLUDED.dasha_info
       RETURNING *`,
      [
        userId,
        kundliData.ascendant,
        kundliData.sunSign,
        kundliData.moonSign,
        kundliData.nakshatra,
        kundliData.nakshatraPada,
        JSON.stringify(kundliData.planetaryPositions),
        JSON.stringify(kundliData.houses),
        JSON.stringify(kundliData.dashaInfo)
      ]
    );

    res.json({
      message: 'Kundli generated and saved successfully',
      kundli: {
        ...kundliData,
        birthDetails: { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth }
      }
    });

  } catch (error) {
    console.error('Kundli generation error:', error);
    res.status(500).json({ error: 'Failed to generate Kundli chart' });
  }
});

// GET /api/kundli
// Fetch current user's Kundli and birth details
router.get('/', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await db.query(
      `SELECT bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info
       FROM birth_details bd
       LEFT JOIN kundlis k ON bd.user_id = k.user_id
       WHERE bd.user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Birth details or Kundli not found for user' });
    }

    const row = result.rows[0];
    res.json({
      birthDetails: {
        fullName: row.full_name,
        gender: row.gender,
        dateOfBirth: row.date_of_birth,
        timeOfBirth: row.time_of_birth,
        placeOfBirth: row.place_of_birth
      },
      kundli: {
        ascendant: row.ascendant,
        sunSign: row.sun_sign,
        moonSign: row.moon_sign,
        nakshatra: row.nakshatra,
        nakshatraPada: row.nakshatra_pada,
        planetaryPositions: typeof row.planetary_positions === 'string' ? JSON.parse(row.planetary_positions) : row.planetary_positions,
        houses: typeof row.houses === 'string' ? JSON.parse(row.houses) : row.houses,
        dashaInfo: typeof row.dasha_info === 'string' ? JSON.parse(row.dasha_info) : row.dasha_info
      }
    });
  } catch (error) {
    console.error('Fetch Kundli error:', error);
    res.status(500).json({ error: 'Failed to fetch Kundli chart' });
  }
});

module.exports = router;
