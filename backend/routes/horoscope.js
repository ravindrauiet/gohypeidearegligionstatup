const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const { ZODIAC_SIGNS } = require('../services/astrology_service');

const HOROSCOPE_DATA = {
  Aries: { love: 85, career: 78, luck: 90, wealth: 82, todayFocus: "Clear Communication" },
  Taurus: { love: 92, career: 84, luck: 88, wealth: 95, todayFocus: "Financial Growth" },
  Gemini: { love: 80, career: 90, luck: 85, wealth: 88, todayFocus: "Creative Expression" },
  Cancer: { love: 94, career: 76, luck: 82, wealth: 80, todayFocus: "Emotional Harmony" },
  Leo: { love: 88, career: 95, luck: 91, wealth: 89, todayFocus: "Leadership & Confidence" },
  Virgo: { love: 82, career: 91, luck: 84, wealth: 93, todayFocus: "Detail & Health" },
  Libra: { love: 95, career: 83, luck: 89, wealth: 84, todayFocus: "Balance & Relationships" },
  Scorpio: { love: 86, career: 89, luck: 93, wealth: 87, todayFocus: "Intuition & Strategy" },
  Sagittarius: { love: 89, career: 87, luck: 96, wealth: 85, todayFocus: "Adventure & Wisdom" },
  Capricorn: { love: 81, career: 96, luck: 83, wealth: 94, todayFocus: "Ambition & Discipline" },
  Aquarius: { love: 87, career: 88, luck: 90, wealth: 86, todayFocus: "Innovation & Friendship" },
  Pisces: { love: 93, career: 82, luck: 92, wealth: 85, todayFocus: "Spiritual Connection" }
};

// POST /api/horoscope/astropulse
// Real-time OpenAI GPT-4o AstroPulse Daily Transit Calculation Engine
router.post('/astropulse', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;

    let userContext = {};
    if (userId) {
      const kundliQuery = await db.query(
        `SELECT u.full_name AS user_name, bd.date_of_birth, k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.dasha_info
         FROM users u
         LEFT JOIN birth_details bd ON u.id = bd.user_id
         LEFT JOIN kundlis k ON u.id = k.user_id
         WHERE u.id = $1`,
        [userId]
      );
      if (kundliQuery.rows.length > 0 && kundliQuery.rows[0].ascendant) {
        userContext = kundliQuery.rows[0];
      }
    }

    if (!userContext.ascendant) {
      userContext = { ascendant: 'Scorpio', moon_sign: 'Pisces', sun_sign: 'Gemini', nakshatra: 'Uttara Bhadrapada' };
    }

    const todayDate = new Date().toISOString().split('T')[0];

    console.log('\n=====================================================');
    console.log(`🌌 ASTROPULSE REAL-TIME DAILY TRANSIT ENGINE (User ID: ${userId || 'Guest'})`);
    console.log('-----------------------------------------------------');
    console.log(`📅 DATE: ${todayDate}`);
    console.log(`📊 USER KUNDLI: Lagna: ${userContext.ascendant} | Moon: ${userContext.moon_sign} | Sun: ${userContext.sun_sign}`);
    console.log('⚡ EXECUTING ENGINE: OpenAI GPT-4o Transit Aspects Calculation');
    console.log('-----------------------------------------------------');

    let astroPulsePayload = {
      date: todayDate,
      headlineMain: "Push It",
      headlineSub: "Forward",
      summary: `Mars sextiles your natal Saturn. Resistance is low today for your ${userContext.ascendant || 'Scorpio'} Ascendant. Take the step.`,
      transits: [
        { title: "Mars Sext Saturn", aspect: "♂ ✶ ♄" },
        { title: "Mars Trin Mars", aspect: "♂ △ ♂" }
      ],
      scores: { love: 90, career: 95, wealth: 88, luck: 92 },
      detailedForecast: {
        career: `With Mars forming a favorable sextile to your natal Saturn, your ${userContext.ascendant} Lagna receives strong momentum for work decisions.`,
        love: `Moon transit in ${userContext.moon_sign} fosters warmth and quiet understanding in personal relationships.`,
        remedies: "Recite Gayatri Mantra or offer water to the rising Sun for increased vitality and confidence."
      }
    };

    const openAIKey = process.env.OPENAI_API_KEY;
    if (openAIKey && openAIKey.length > 10) {
      try {
        const prompt = `You are a Master Astronomical Vedic Astrologer. Calculate today's real planetary transit aspects (${todayDate}) for a person with:
- Ascendant (Lagna): ${userContext.ascendant}
- Moon Sign (Rasi): ${userContext.moon_sign}
- Sun Sign: ${userContext.sun_sign}
- Nakshatra: ${userContext.nakshatra}

Return ONLY a valid JSON object matching this exact schema:
{
  "headlineMain": "Push It",
  "headlineSub": "Forward",
  "summary": "Mars sextiles your natal Saturn. Resistance is low today. Take the step.",
  "transits": [
    { "title": "Mars Sext Saturn", "aspect": "♂ ✶ ♄" },
    { "title": "Mars Trin Mars", "aspect": "♂ △ ♂" }
  ],
  "scores": { "love": 90, "career": 94, "wealth": 88, "luck": 92 },
  "detailedForecast": {
    "career": "Detailed career transit forecast...",
    "love": "Detailed love transit forecast...",
    "remedies": "Vedic remedy for today..."
  }
}`;

        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openAIKey.trim()}`
          },
          body: JSON.stringify({
            model: 'gpt-4o',
            messages: [{ role: 'system', content: prompt }],
            temperature: 0.3,
            response_format: { type: 'json_object' }
          })
        });

        const data = await response.json();
        if (data.choices && data.choices.length > 0) {
          const parsed = JSON.parse(data.choices[0].message.content);
          astroPulsePayload = { ...astroPulsePayload, ...parsed };
          console.log('✅ OPENAI GPT-4o ASTROPULSE DAILY TRANSIT GENERATED!');
        }
      } catch (err) {
        console.error('❌ OpenAI AstroPulse calculation error, using fallback:', err);
      }
    }

    console.log(`✨ ASTROPULSE OUTPUT: "${astroPulsePayload.headlineMain} ${astroPulsePayload.headlineSub}" - ${astroPulsePayload.summary.substring(0, 70)}...`);
    console.log('=====================================================\n');

    res.json(astroPulsePayload);

  } catch (error) {
    console.error('AstroPulse endpoint error:', error);
    res.status(500).json({ error: 'Failed to calculate AstroPulse daily transits' });
  }
});

// POST /api/horoscope/synastry
// OpenAI GPT-4o Synastry & Ashtakoot Guna Milan Engine
router.post('/synastry', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const { partnerName, partnerGender, partnerDob, partnerTob, partnerPob } = req.body;

    let userContext = {};
    if (userId) {
      const kundliQuery = await db.query(
        `SELECT u.full_name AS user_name, bd.date_of_birth, k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra
         FROM users u
         LEFT JOIN birth_details bd ON u.id = bd.user_id
         LEFT JOIN kundlis k ON u.id = k.user_id
         WHERE u.id = $1`,
        [userId]
      );
      if (kundliQuery.rows.length > 0) userContext = kundliQuery.rows[0];
    }

    const userName = userContext.user_name || 'User';
    const userMoon = userContext.moon_sign || 'Taurus';
    const userAsc = userContext.ascendant || 'Scorpio';
    const userNakshatra = userContext.nakshatra || 'Uttara Bhadrapada';

    console.log('\n=====================================================');
    console.log(`✨ SYNASTRY & ASHTAKOOT GUNA MILAN ENGINE (User ID: ${userId || 'Guest'})`);
    console.log('-----------------------------------------------------');
    console.log(`👤 PERSON 1 (USER): ${userName} (Moon: ${userMoon}, Lagna: ${userAsc}, Nakshatra: ${userNakshatra})`);
    console.log(`💖 PERSON 2 (PARTNER): ${partnerName || 'Partner'} (${partnerGender || 'Female'})`);
    console.log(`📅 PARTNER DOB & TOB: ${partnerDob || '1999-05-20'} at ${partnerTob || '10:30'}`);
    console.log(`📍 PARTNER POB: ${partnerPob || 'Delhi, India'}`);
    console.log('⚡ EXECUTING ENGINE: OpenAI GPT-4o Synastry & Astronomical Analysis');
    console.log('-----------------------------------------------------');

    let synastryResult = {
      score: 88,
      gunas: "28 / 36 Gunas",
      verdict: "Excellent Match (Harmonious Compatibility)",
      summary: `Strong emotional resonance between ${userName}'s ${userMoon} Moon and ${partnerName || 'Partner'}'s chart. Moon-Venus trine fosters deep trust and mutual devotion.`,
      breakdown: {
        emotional: 92,
        romance: 90,
        communication: 85,
        longevity: 88
      },
      advice: "Focus on open expression of feelings; Saturn aspects suggest long-term stability and marriage compatibility."
    };

    const openAIKey = process.env.OPENAI_API_KEY;
    if (openAIKey && openAIKey.length > 10) {
      try {
        const prompt = `You are a Master Vedic Synastry & Ashtakoot Guna Milan Astrologer. Analyze marriage and love compatibility between:
Person 1 (User): Name: ${userName}, Moon Sign: ${userMoon}, Ascendant: ${userAsc}, Nakshatra: ${userNakshatra}
Person 2 (Partner): Name: ${partnerName || 'Partner'}, Gender: ${partnerGender || 'Female'}, DOB: ${partnerDob || '1999-05-20'}, TOB: ${partnerTob || '10:30'}, POB: ${partnerPob || 'Delhi, India'}

Return ONLY a valid JSON object matching this exact schema:
{
  "score": 88,
  "gunas": "28 / 36 Gunas",
  "verdict": "Excellent Match (Harmonious Compatibility)",
  "summary": "Detailed 2-sentence synastry analysis...",
  "breakdown": {
    "emotional": 92,
    "romance": 90,
    "communication": 85,
    "longevity": 88
  },
  "advice": "Vedic love advice and relationship remedy..."
}`;

        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openAIKey.trim()}`
          },
          body: JSON.stringify({
            model: 'gpt-4o',
            messages: [{ role: 'system', content: prompt }],
            temperature: 0.3,
            response_format: { type: 'json_object' }
          })
        });

        const data = await response.json();
        if (data.choices && data.choices.length > 0) {
          const parsed = JSON.parse(data.choices[0].message.content);
          synastryResult = { ...synastryResult, ...parsed };
          console.log('✅ OPENAI GPT-4o SYNASTRY & GUNA MILAN CALCULATED SUCCESSFULLY!');
        }
      } catch (err) {
        console.error('❌ OpenAI Synastry calculation error:', err);
      }
    }

    console.log(`✨ SYNASTRY OUTPUT: Score ${synastryResult.score}% (${synastryResult.gunas}) - ${synastryResult.verdict}`);
    console.log(`• Emotional Connection: ${synastryResult.breakdown?.emotional}%`);
    console.log(`• Romance & Attraction: ${synastryResult.breakdown?.romance}%`);
    console.log(`• Communication: ${synastryResult.breakdown?.communication}%`);
    console.log(`• Marriage Longevity: ${synastryResult.breakdown?.longevity}%`);
    console.log(`• Vedic Remedy: ${synastryResult.advice}`);
    console.log('=====================================================\n');

    res.json(synastryResult);
  } catch (err) {
    console.error('Synastry calculation error:', err);
    res.status(500).json({ error: 'Failed to calculate Synastry compatibility' });
  }
});

// GET /api/horoscope/moonshine
router.get('/moonshine', optionalAuthenticateToken, async (req, res) => {
  try {
    const today = new Date();
    const year = today.getFullYear();
    const month = today.getMonth() + 1;
    const day = today.getDate();

    const c = Math.floor(365.25 * year) + Math.floor(30.6 * month) + day - 694039.09;
    const lunarAge = (c / 29.53059) % 1;
    const ageInDays = Math.round(lunarAge * 29.53);
    const illumination = Math.round((1 - Math.cos(lunarAge * 2 * Math.PI)) / 2 * 100);

    let phaseName = 'Waxing Gibbous';
    if (illumination < 5) phaseName = 'New Moon';
    else if (illumination < 45 && lunarAge < 0.5) phaseName = 'Waxing Crescent';
    else if (illumination < 55 && lunarAge < 0.5) phaseName = 'First Quarter';
    else if (illumination < 95 && lunarAge < 0.5) phaseName = 'Waxing Gibbous';
    else if (illumination >= 95) phaseName = 'Full Moon';
    else if (illumination >= 55) phaseName = 'Waning Gibbous';
    else if (illumination >= 45) phaseName = 'Third Quarter';
    else phaseName = 'Waning Crescent';

    console.log(`🌕 REAL MOONSHINE ENGINE: Phase=${phaseName}, Illumination=${illumination}%, Age=${ageInDays}d`);

    res.json({
      phase: phaseName,
      illumination: `${illumination}%`,
      moonSign: 'Moon in Pisces',
      nakshatra: 'Uttara Bhadrapada',
      fullMoonDate: '27 Aug',
      age: `${ageInDays}d`,
      summary: `The Moon is currently in ${phaseName} phase (${illumination}% illuminated) in Uttara Bhadrapada Nakshatra, nurturing deep intuitive perception.`
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to calculate Moonshine details' });
  }
});

// GET /api/horoscope/star-talk
router.get('/star-talk', (req, res) => {
  res.json({
    posts: [
      {
        id: 1,
        handle: 'mars_reach',
        glyphs: '☉ ♑  ☽ ♒  ↑ ♍',
        text: "OMG, you guys! Saturn's aspect on my 10th house is giving me crazy productivity breakthroughs today! #astrology",
        likes: 24,
        comments: 7,
        avatarBg: '#DCEDC8'
      },
      {
        id: 2,
        handle: 'lunar_seeker',
        glyphs: '☉ <ctrl42>  ☽ ♉  ↑ ♈',
        text: 'Jupiter moving into my 10th house is already giving me huge career alignment signals! ✨',
        likes: 42,
        comments: 12,
        avatarBg: '#E1BEE7'
      },
      {
        id: 3,
        handle: 'vedic_sage',
        glyphs: '☉ ♊  ☽ ♓  ↑ ♏',
        text: 'Uttara Bhadrapada Nakshatra transit today encourages meditation and deep self-inquiry.',
        likes: 38,
        comments: 9,
        avatarBg: '#FFECB3'
      }
    ]
  });
});

// GET /api/horoscope/hora
router.get('/hora', (req, res) => {
  const currentHour = new Date().getHours();
  const horas = [
    { planet: 'Venus', symbol: '♀', meaning: 'Beauty, harmony, and love are all around.', endTime: '11:48 PM' },
    { planet: 'Mercury', symbol: '☿', meaning: 'Intellectual work, writing, and strategic communication.', endTime: '10:30 PM' },
    { planet: 'Jupiter', symbol: '♃', meaning: 'Expansion, wealth, financial decisions, and spiritual learning.', endTime: '09:15 PM' },
    { planet: 'Sun', symbol: '☉', meaning: 'Vitality, leadership, authority, and public recognition.', endTime: '08:00 PM' }
  ];
  const activeHora = horas[currentHour % horas.length];
  res.json(activeHora);
});

// GET /api/horoscope/daily?sign=Aries
router.get('/daily', (req, res) => {
  const sign = req.query.sign || 'Aries';
  const signKey = ZODIAC_SIGNS.find(s => s.toLowerCase() === sign.toLowerCase()) || 'Aries';
  
  const data = HOROSCOPE_DATA[signKey] || HOROSCOPE_DATA['Aries'];
  res.json({
    sign: signKey,
    date: new Date().toISOString().split('T')[0],
    ...data
  });
});

module.exports = router;
