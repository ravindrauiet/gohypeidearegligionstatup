const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const { calculateKundliWithAI, generateAIKundliReport } = require('../services/astrology_service');

// POST /api/kundli/ai-report
// Generates a comprehensive ChatGPT (GPT-4o) Kundli Analysis Report based on Swiss Ephemeris data
router.post('/ai-report', optionalAuthenticateToken, async (req, res) => {
  try {
    const { kundli, birthDetails } = req.body;
    if (!kundli) {
      return res.status(400).json({ error: 'Kundli payload is required' });
    }

    const reportMarkdown = await generateAIKundliReport(kundli, birthDetails || {});
    res.json({ aiReport: reportMarkdown });
  } catch (error) {
    console.error('AI Kundli Report error:', error);
    res.status(500).json({ error: 'Failed to generate AI Kundli Report' });
  }
});

// POST /api/kundli/generate
// Saves birth details and calculates/stores Kundli chart into Neon DB
router.post('/generate', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude } = req.body;

    if (!fullName || !dateOfBirth || !timeOfBirth || !placeOfBirth) {
      return res.status(400).json({ error: 'Full name, date of birth, time of birth, and place of birth are required' });
    }

    console.log('\n=====================================================');
    console.log(`📜 KUNDLI GENERATION REQUEST (User ID: ${userId || 'Guest'})`);
    console.log('-----------------------------------------------------');
    console.log(`👤 FULL NAME: ${fullName} (${gender || 'Not Specified'})`);
    console.log(`📅 BIRTH DATE & TIME: ${dateOfBirth} at ${timeOfBirth}`);
    console.log('-----------------------------------------------------');

    const kundliData = await calculateKundliWithAI(
      dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude,
      { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth }
    );

    console.log('✨ KUNDLI CALCULATION SUMMARY:');
    console.log(`• Ascendant (Lagna): ${kundliData.ascendant}`);
    console.log(`• Sun Sign (Rasi): ${kundliData.sunSign}`);
    console.log(`• Moon Sign (Rasi): ${kundliData.moonSign}`);
    console.log(`• Nakshatra: ${kundliData.nakshatra} (Pada ${kundliData.nakshatraPada})`);

    if (userId) {
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

      await db.query(
        `INSERT INTO kundlis (user_id, ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada, planetary_positions, houses, dasha_info, ai_report)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (user_id) DO UPDATE SET
           ascendant = EXCLUDED.ascendant,
           sun_sign = EXCLUDED.sun_sign,
           moon_sign = EXCLUDED.moon_sign,
           nakshatra = EXCLUDED.nakshatra,
           nakshatra_pada = EXCLUDED.nakshatra_pada,
           planetary_positions = EXCLUDED.planetary_positions,
           houses = EXCLUDED.houses,
           dasha_info = EXCLUDED.dasha_info,
           ai_report = EXCLUDED.ai_report`,
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
          kundliData.aiReport || ''
        ]
      );
      console.log(`💾 NEON DB STORAGE: Successfully saved Kundli & AI Report for User #${userId} (${fullName}) to Neon PostgreSQL!`);
    }

    console.log('=====================================================\n');

    res.json({
      message: 'Kundli generated and saved successfully to Neon DB',
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
router.get('/', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const result = await db.query(
      `SELECT bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info, k.ai_report
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
        dashaInfo: typeof row.dasha_info === 'string' ? JSON.parse(row.dasha_info) : row.dasha_info,
        aiReport: row.ai_report
      }
    });
  } catch (error) {
    console.error('Fetch Kundli error:', error);
    res.status(500).json({ error: 'Failed to fetch Kundli chart' });
  }
});

// =====================================================
// FAMILY KUNDLIS API (Multiple Profiles per Account)
// =====================================================

// POST /api/kundli/family/add
router.post('/family/add', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized: Please log in to add family member Kundlis' });
    }

    const { relationship, fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude } = req.body;

    if (!relationship || !fullName || !dateOfBirth || !timeOfBirth || !placeOfBirth) {
      return res.status(400).json({ error: 'Relationship, full name, date of birth, time of birth, and place of birth are required' });
    }

    console.log('\n=====================================================');
    console.log(`👨‍👩‍👧‍👦 FAMILY KUNDLI GENERATION REQUEST (User ID: ${userId})`);
    console.log('-----------------------------------------------------');
    console.log(`👥 RELATIONSHIP: ${relationship}`);
    console.log(`👤 NAME: ${fullName} (${gender || 'Not Specified'})`);
    console.log(`📅 BIRTH DATE & TIME: ${dateOfBirth} at ${timeOfBirth}`);
    console.log(`📍 PLACE: ${placeOfBirth}`);
    console.log('-----------------------------------------------------');

    // 1. Compute Kundli & pre-generate AI report ONCE
    const kundliData = await calculateKundliWithAI(
      dateOfBirth, timeOfBirth, placeOfBirth, latitude, longitude,
      { fullName, gender, dateOfBirth, timeOfBirth, placeOfBirth }
    );

    // Clean up any old duplicate profile for this family member before inserting
    await db.query(
      `DELETE FROM family_kundlis WHERE user_id = $1 AND LOWER(full_name) = LOWER($2)`,
      [userId, fullName]
    );

    // 2. Insert into family_kundlis table in Neon DB with ai_report
    const insertQuery = await db.query(
      `INSERT INTO family_kundlis 
        (user_id, relationship, full_name, gender, date_of_birth, time_of_birth, place_of_birth, latitude, longitude, ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada, planetary_positions, houses, dasha_info, ai_report)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
       RETURNING id, created_at`,
      [
        userId,
        relationship,
        fullName,
        gender || 'Not Specified',
        dateOfBirth,
        timeOfBirth,
        placeOfBirth,
        latitude || 28.6139,
        longitude || 77.2090,
        kundliData.ascendant,
        kundliData.sunSign,
        kundliData.moonSign,
        kundliData.nakshatra,
        kundliData.nakshatraPada,
        JSON.stringify(kundliData.planetaryPositions),
        JSON.stringify(kundliData.houses),
        JSON.stringify(kundliData.dashaInfo),
        kundliData.aiReport || ''
      ]
    );

    const familyRecordId = insertQuery.rows[0].id;
    console.log(`💾 NEON DB STORAGE: Successfully saved Family Kundli #${familyRecordId} (${fullName} - ${relationship}) under User #${userId}`);
    console.log('=====================================================\n');

    res.json({
      message: 'Family member Kundli created and saved successfully',
      familyMember: {
        id: familyRecordId,
        relationship,
        fullName,
        gender,
        dateOfBirth,
        timeOfBirth,
        placeOfBirth,
        kundli: kundliData
      }
    });

  } catch (error) {
    console.error('Family Kundli creation error:', error);
    res.status(500).json({ error: 'Failed to add family member Kundli' });
  }
});

// GET /api/kundli/family/list
router.get('/family/list', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const result = await db.query(
      `SELECT id, relationship, full_name, gender, date_of_birth, time_of_birth, place_of_birth,
              ascendant, sun_sign, moon_sign, nakshatra, nakshatra_pada,
              planetary_positions, houses, dasha_info, ai_report, created_at
       FROM family_kundlis
       WHERE user_id = $1
       ORDER BY created_at DESC`,
      [userId]
    );

    const familyMembers = result.rows.map(row => ({
      id: row.id,
      relationship: row.relationship,
      fullName: row.full_name,
      gender: row.gender,
      dateOfBirth: row.date_of_birth,
      timeOfBirth: row.time_of_birth,
      placeOfBirth: row.place_of_birth,
      createdAt: row.created_at,
      kundli: {
        ascendant: row.ascendant,
        sunSign: row.sun_sign,
        moonSign: row.moon_sign,
        nakshatra: row.nakshatra,
        nakshatra_pada: row.nakshatra_pada,
        planetaryPositions: typeof row.planetary_positions === 'string' ? JSON.parse(row.planetary_positions) : row.planetary_positions,
        houses: typeof row.houses === 'string' ? JSON.parse(row.houses) : row.houses,
        dashaInfo: typeof row.dasha_info === 'string' ? JSON.parse(row.dasha_info) : row.dasha_info,
        aiReport: row.ai_report
      }
    }));

    res.json({ familyMembers });
  } catch (error) {
    console.error('Fetch family Kundlis error:', error);
    res.status(500).json({ error: 'Failed to fetch family Kundlis' });
  }
});

// DELETE /api/kundli/family/:id
router.delete('/family/:id', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const familyId = req.params.id;

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    await db.query(
      `DELETE FROM family_kundlis WHERE id = $1 AND user_id = $2`,
      [familyId, userId]
    );

    res.json({ message: 'Family Kundli deleted successfully' });
  } catch (error) {
    console.error('Delete family Kundli error:', error);
    res.status(500).json({ error: 'Failed to delete family Kundli' });
  }
});

module.exports = router;
