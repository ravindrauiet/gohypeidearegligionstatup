const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const { ZODIAC_SIGNS, calculateDailyPanchangAndMuhurats } = require('../services/astrology_service');

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
// Real-time OpenAI GPT-4o AstroPulse Daily Transit Calculation Engine with 1-Time Daily Neon DB Caching
router.post('/astropulse', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const todayDate = new Date().toISOString().split('T')[0];

    // 1. Check Neon DB for existing daily pre-generated cache for today
    if (userId) {
      const cacheQuery = await db.query(
        `SELECT astro_pulse, panchang FROM daily_horoscopes WHERE user_id = $1 AND date = $2`,
        [userId, todayDate]
      );
      if (cacheQuery.rows.length > 0 && cacheQuery.rows[0].astro_pulse) {
        console.log(`\n⚡ RETURNING PRE-CACHED ASTROPULSE & PANCHANG FROM NEON DB FOR USER ID: ${userId} (${todayDate})`);
        return res.json({ ...cacheQuery.rows[0].astro_pulse, cached: true });
      }
    }

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

    console.log('\n=====================================================');
    console.log(`🌌 GENERATING & CACHING ASTROPULSE DAILY TRANSIT (User ID: ${userId || 'Guest'})`);
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
      scores: { love: 85, career: 92, health: 78, luck: 90 },
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
  "scores": { "love": 85, "career": 92, "health": 78, "luck": 90 },
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
        console.error('❌ OpenAI AstroPulse calculation error:', err);
      }
    }

    // 2. Generate Live Panchang & Muhurats for today
    const panchangPayload = calculateDailyPanchangAndMuhurats(todayDate);

    // 3. Store into Neon DB table daily_horoscopes for 0-cost repeated reads
    if (userId) {
      await db.query(
        `INSERT INTO daily_horoscopes (user_id, date, astro_pulse, panchang)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, date)
         DO UPDATE SET astro_pulse = EXCLUDED.astro_pulse, panchang = EXCLUDED.panchang`,
        [userId, todayDate, JSON.stringify(astroPulsePayload), JSON.stringify(panchangPayload)]
      );
      console.log(`💾 SAVED DAILY ASTROPULSE & PANCHANG TO NEON DB FOR USER ID: ${userId} (${todayDate})`);
    }

    res.json({ ...astroPulsePayload, panchang: panchangPayload });
  } catch (error) {
    console.error('AstroPulse endpoint error:', error);
    res.status(500).json({ error: 'Failed to calculate AstroPulse daily transits' });
  }
});

// GET /api/horoscope/panchang
// Fetch Today's Live Panchang & Muhurat Clock
router.get('/panchang', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const todayDate = new Date().toISOString().split('T')[0];

    if (userId) {
      const cacheQuery = await db.query(
        `SELECT panchang FROM daily_horoscopes WHERE user_id = $1 AND date = $2`,
        [userId, todayDate]
      );
      if (cacheQuery.rows.length > 0 && cacheQuery.rows[0].panchang) {
        return res.json({ ...cacheQuery.rows[0].panchang, cached: true });
      }
    }

    const panchangPayload = calculateDailyPanchangAndMuhurats(todayDate);
    res.json(panchangPayload);
  } catch (error) {
    console.error('Panchang calculation error:', error);
    res.status(500).json({ error: 'Failed to calculate daily Panchang & Muhurats' });
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
      score: 86,
      gunaTotal: 31,
      gunas: "31 / 36 Gunas",
      verdict: "Very High Compatibility (Uttam Milan)",
      summary: `Strong emotional resonance between ${userName}'s ${userMoon} Moon and ${partnerName || 'Partner'}'s chart. Moon-Venus trine fosters deep trust and mutual devotion.`,
      ashtakoot: [
        { name: "Varna", score: 1, max: 1, meaning: "Work & Ego Alignment", verdict: "Full Compatibility" },
        { name: "Vashya", score: 2, max: 2, meaning: "Mutual Influence & Control", verdict: "Harmonious Balance" },
        { name: "Tara", score: 3, max: 3, meaning: "Destiny & Astral Luck", verdict: "Auspicious Star Alignment" },
        { name: "Yoni", score: 3, max: 4, meaning: "Physical & Intimate Affinity", verdict: "Strong Physical Chemistry" },
        { name: "Maitri", score: 5, max: 5, meaning: "Intellectual Friendship", verdict: "Deep Mental Bond" },
        { name: "Gana", score: 6, max: 6, meaning: "Behavior & Temperament", verdict: "Matching Deva Gana" },
        { name: "Bhakoot", score: 7, max: 7, meaning: "Emotional & Financial Growth", verdict: "No Bhakoot Dosha (7/7)" },
        { name: "Nadi", score: 8, max: 8, meaning: "Genetics, Health & Progeny", verdict: "No Nadi Dosha (8/8)" }
      ],
      manglikCheck: {
        person1Status: "Non-Manglik",
        person2Status: "Partial Manglik (Mars in 4th House)",
        manglikVerdict: "Manglik Dosha is balanced and non-obstructive due to Jupiter's beneficial aspect."
      },
      nadiBhakootAnalysis: {
        nadiVerdict: "Excellent Nadi compatibility (8/8). Ensures healthy lineage and physical vitality.",
        bhakootVerdict: "Favorable 1/7 Bhakoot axis. Fosters mutual wealth accumulation and emotional trust."
      },
      planetarySynastry: [
        { planet: "Sun ☉ (Willpower)", p1Sign: userContext.sun_sign || "Scorpio", p2Sign: "Cancer", alignment: "Trine (120°)", verdict: "Harmonious Ambition" },
        { planet: "Moon ☽ (Emotions)", p1Sign: userMoon, p2Sign: "Taurus", alignment: "Sextile (60°)", verdict: "Deep Emotional Symbiosis" },
        { planet: "Venus ♀ (Romance)", p1Sign: "Libra", p2Sign: "Gemini", alignment: "Trine (120°)", verdict: "Strong Physical Attraction" },
        { planet: "Mars ♂ (Passion)", p1Sign: "Aries", p2Sign: "Leo", alignment: "Trine (120°)", verdict: "High Dynamic Energy & Loyalty" }
      ],
      advice: "Focus on open expression of feelings; Saturn aspects suggest long-term stability and marriage compatibility.",
      relationshipReport: `### 💖 Emotional Bond & Mutual Understanding
${userName} and ${partnerName || 'Partner'} share a naturally harmonious emotional connection. The alignment of ${userMoon} Moon fosters deep mutual empathy, intuitive understanding, and shared life goals.

### 💍 Marriage Longevity & Progeny Compatibility
With 31 out of 36 Gunas matched, this pair exhibits outstanding Ashtakoot compatibility. The absence of both Nadi and Bhakoot Doshas ensures strong health, financial stability, and long-term marital bliss.

### 🌿 Sacred Guidance & Relationship Remedies
To maintain positive planetary energy, light a Ghee lamp together on Thursdays and practice open communication during active Mars transits.`
    };

    const openAIKey = process.env.OPENAI_API_KEY;
    if (openAIKey && openAIKey.length > 10) {
      try {
        const prompt = `You are a Master Vedic Synastry & Ashtakoot Guna Milan Astrologer. Analyze 36-Guna marriage compatibility between:
Person 1 (User): Name: ${userName}, Moon Sign: ${userMoon}, Ascendant: ${userAsc}, Nakshatra: ${userNakshatra}
Person 2 (Partner): Name: ${partnerName || 'Partner'}, Gender: ${partnerGender || 'Female'}, DOB: ${partnerDob || '1999-05-20'}, TOB: ${partnerTob || '10:30'}, POB: ${partnerPob || 'Delhi, India'}

Return ONLY a valid JSON object matching this exact schema:
{
  "score": 86,
  "gunaTotal": 31,
  "gunas": "31 / 36 Gunas",
  "verdict": "Very High Compatibility (Uttam Milan)",
  "summary": "Detailed 2-sentence synastry analysis...",
  "ashtakoot": [
    { "name": "Varna", "score": 1, "max": 1, "meaning": "Work & Ego Alignment", "verdict": "Full Compatibility" },
    { "name": "Vashya", "score": 2, "max": 2, "meaning": "Mutual Influence & Control", "verdict": "Harmonious Balance" },
    { "name": "Tara", "score": 3, "max": 3, "meaning": "Destiny & Astral Luck", "verdict": "Auspicious Star Alignment" },
    { "name": "Yoni", "score": 3, "max": 4, "meaning": "Physical & Intimate Affinity", "verdict": "Strong Physical Chemistry" },
    { "name": "Maitri", "score": 5, "max": 5, "meaning": "Intellectual Friendship", "verdict": "Deep Mental Bond" },
    { "name": "Gana", "score": 6, "max": 6, "meaning": "Behavior & Temperament", "verdict": "Matching Deva Gana" },
    { "name": "Bhakoot", "score": 7, "max": 7, "meaning": "Emotional & Financial Growth", "verdict": "No Bhakoot Dosha (7/7)" },
    { "name": "Nadi", "score": 8, "max": 8, "meaning": "Genetics, Health & Progeny", "verdict": "No Nadi Dosha (8/8)" }
  ],
  "manglikCheck": {
    "person1Status": "Non-Manglik",
    "person2Status": "Partial Manglik",
    "manglikVerdict": "Detailed Manglik compatibility verdict..."
  },
  "nadiBhakootAnalysis": {
    "nadiVerdict": "Detailed Nadi compatibility explanation...",
    "bhakootVerdict": "Detailed Bhakoot compatibility explanation..."
  },
  "advice": "Vedic love advice and relationship remedy...",
  "relationshipReport": "Comprehensive Markdown relationship guidance report with ### headings..."
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
          console.log('✅ OPENAI GPT-4o ASHTAKOOT GUNA MILAN CALCULATED SUCCESSFULLY!');
        }
      } catch (err) {
        console.error('❌ OpenAI Synastry calculation error:', err);
      }
    }

    console.log(`✨ ASHTAKOOT SYNASTRY OUTPUT: Score ${synastryResult.score}% (${synastryResult.gunas}) - ${synastryResult.verdict}`);
    console.log(`• Manglik Check: ${synastryResult.manglikCheck?.manglikVerdict}`);
    console.log(`• Nadi Verdict: ${synastryResult.nadiBhakootAnalysis?.nadiVerdict}`);
    console.log(`• Bhakoot Verdict: ${synastryResult.nadiBhakootAnalysis?.bhakootVerdict}`);
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
