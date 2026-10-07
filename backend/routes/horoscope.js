const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const { chatCompletion } = require('../services/openai_client');
const {
  ZODIAC_SIGNS,
  DEFAULT_TIMEZONE,
  timezoneForLocation,
  AstrologyInputError,
  calculateDailyPanchangAndMuhurats,
  calculateCurrentHora,
  calculateMoonPhase,
  calculateTransitAspects,
  calculateKundli,
  calculateAshtakoot,
  manglikStatus,
  todayISO
} = require('../services/astrology_service');

const HOROSCOPE_DATA = {
  Aries: { love: 85, career: 78, luck: 90, wealth: 82, todayFocus: 'Clear Communication' },
  Taurus: { love: 92, career: 84, luck: 88, wealth: 95, todayFocus: 'Financial Growth' },
  Gemini: { love: 80, career: 90, luck: 85, wealth: 88, todayFocus: 'Creative Expression' },
  Cancer: { love: 94, career: 76, luck: 82, wealth: 80, todayFocus: 'Emotional Harmony' },
  Leo: { love: 88, career: 95, luck: 91, wealth: 89, todayFocus: 'Leadership & Confidence' },
  Virgo: { love: 82, career: 91, luck: 84, wealth: 93, todayFocus: 'Detail & Health' },
  Libra: { love: 95, career: 83, luck: 89, wealth: 84, todayFocus: 'Balance & Relationships' },
  Scorpio: { love: 86, career: 89, luck: 93, wealth: 87, todayFocus: 'Intuition & Strategy' },
  Sagittarius: { love: 89, career: 87, luck: 96, wealth: 85, todayFocus: 'Adventure & Wisdom' },
  Capricorn: { love: 81, career: 96, luck: 83, wealth: 94, todayFocus: 'Ambition & Discipline' },
  Aquarius: { love: 87, career: 88, luck: 90, wealth: 86, todayFocus: 'Innovation & Friendship' },
  Pisces: { love: 93, career: 82, luck: 92, wealth: 85, todayFocus: 'Spiritual Connection' }
};

const BENEFICS = ['Jupiter', 'Venus', 'Moon', 'Mercury'];
const clampScore = (n) => Math.max(35, Math.min(98, Math.round(n)));

function parseJson(value, fallback) {
  if (value === null || value === undefined) return fallback;
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch (_) { return fallback; }
}

function locationFromQuery(query) {
  const lat = query.lat !== undefined ? parseFloat(query.lat) : undefined;
  const lng = query.lng !== undefined ? parseFloat(query.lng) : undefined;
  const latOk = Number.isFinite(lat) ? lat : undefined;
  const lngOk = Number.isFinite(lng) ? lng : undefined;
  const tz = timezoneForLocation(typeof query.tz === 'string' ? query.tz.trim() : undefined, latOk, lngOk);
  return { lat: latOk, lng: lngOk, tz };
}

function inputErrorOr500(res, err, message) {
  if (err instanceof AstrologyInputError) return res.status(400).json({ error: err.message });
  console.error(message, err);
  return res.status(500).json({ error: message });
}

// Deterministic, transit-based daily forecast used directly or as AI fallback
function buildAstroPulse(dateISO, ctx, transitInfo, personal = true) {
  const aspects = transitInfo.aspects;
  const top = aspects.slice(0, 3);

  const scores = { love: 70, career: 70, health: 70, luck: 70 };
  for (const a of aspects.slice(0, 8)) {
    const weight = Math.max(0.3, 1 - a.orb / 4);
    const benefic = BENEFICS.includes(a.transitPlanet);
    const delta = (a.nature === 'harmonious' ? 8 : a.nature === 'challenging' ? -7 : (benefic ? 5 : -3)) * weight;
    if (['Venus', 'Moon'].includes(a.transitPlanet) || ['Venus', 'Moon'].includes(a.natalPlanet)) scores.love += delta;
    if (['Sun', 'Saturn', 'Mercury'].includes(a.transitPlanet) || ['Sun', 'Saturn'].includes(a.natalPlanet)) scores.career += delta;
    if (['Mars', 'Sun'].includes(a.transitPlanet) || ['Mars', 'Sun'].includes(a.natalPlanet)) scores.health += delta;
    if (['Jupiter', 'Venus'].includes(a.transitPlanet) || ['Jupiter'].includes(a.natalPlanet)) scores.luck += delta;
  }
  Object.keys(scores).forEach((k) => { scores[k] = clampScore(scores[k]); });

  const lead = top[0];
  let headlineMain = 'Steady';
  let headlineSub = 'Progress';
  let summary = personal
    ? `No exact transit aspects are active for your ${ctx.ascendant} Lagna today. A balanced day for routine work and reflection.`
    : 'No major planetary aspects are exact today. A balanced day for routine work and reflection. Generate your Kundli for a personalised forecast.';
  if (lead) {
    if (lead.nature === 'harmonious') { headlineMain = 'Push It'; headlineSub = 'Forward'; }
    else if (lead.nature === 'challenging') { headlineMain = 'Slow'; headlineSub = 'Down'; }
    else { headlineMain = 'Focus'; headlineSub = 'Within'; }
    const verb = { Conj: 'conjoins', Sext: 'sextiles', Squa: 'squares', Trin: 'trines', Oppo: 'opposes' }[lead.type];
    summary = (personal
      ? `Transiting ${lead.transitPlanet} ${verb} your natal ${lead.natalPlanet} (orb ${lead.orb}°). `
      : `Today ${lead.transitPlanet} ${verb} ${lead.natalPlanet} in the sky (orb ${lead.orb}°). `) +
      (lead.nature === 'harmonious'
        ? 'Resistance is low today; take the step you have been planning.'
        : lead.nature === 'challenging'
          ? 'Expect some friction; patience and careful decisions will serve you best.'
          : 'Energy concentrates in this area of life; act with intention.');
  }

  return {
    date: dateISO,
    headlineMain,
    headlineSub,
    summary,
    transits: top.length > 0
      ? top.map((a) => ({ title: a.title, aspect: a.aspect, nature: a.nature, orb: a.orb }))
      : [],
    scores,
    detailedForecast: {
      career: `${personal ? `For your ${ctx.ascendant} Lagna, ` : 'Today, '}${scores.career >= 70 ? 'professional matters move with reasonable support' : 'work may need extra patience and planning'} today.`,
      love: `${personal ? `With Moon in ${ctx.moon_sign} at birth, ` : `With the Moon transiting ${ctx.moon_sign}, `}${scores.love >= 70 ? 'warmth and understanding come more easily in relationships' : 'clear and gentle communication avoids misunderstandings'}.`,
      remedies: 'Recite the Gayatri Mantra at sunrise or offer water to the rising Sun for clarity and vitality.'
    },
    currentTransits: transitInfo.currentPositions
  };
}

// POST /api/horoscope/astropulse
// Daily transit forecast. Registered users get it computed against their natal chart and cached per day.
router.post('/astropulse', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const todayDate = todayISO(DEFAULT_TIMEZONE);

    if (userId) {
      const cacheQuery = await db.query(
        'SELECT astro_pulse, panchang FROM daily_horoscopes WHERE user_id = $1 AND date = $2',
        [userId, todayDate]
      );
      if (cacheQuery.rows.length > 0 && cacheQuery.rows[0].astro_pulse) {
        return res.json({ ...cacheQuery.rows[0].astro_pulse, panchang: cacheQuery.rows[0].panchang, cached: true });
      }
    }

    let ctx = null;
    if (userId) {
      const kundliQuery = await db.query(
        `SELECT u.full_name AS user_name, k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.dasha_info, k.planetary_positions
         FROM users u
         LEFT JOIN kundlis k ON u.id = k.user_id
         WHERE u.id = $1`,
        [userId]
      );
      if (kundliQuery.rows.length > 0 && kundliQuery.rows[0].ascendant) ctx = kundliQuery.rows[0];
    }

    const hasChart = !!ctx;
    let natalPlanets = [];
    if (hasChart) {
      natalPlanets = parseJson(ctx.planetary_positions, []);
    } else {
      // No natal chart: general forecast from today's sky (fast planets vs. slow planets)
      const now = new Date();
      const k = calculateKundli(now.toISOString().split('T')[0], `${now.getUTCHours()}:${now.getUTCMinutes()}`, 'Delhi', undefined, undefined, 'UTC');
      ctx = { ascendant: k.ascendant, moon_sign: k.moonSign, sun_sign: k.sunSign, nakshatra: k.nakshatra };
      natalPlanets = k.planetaryPositions.filter((p) => /^(Jupiter|Saturn|Rahu|Ketu)/.test(p.name));
    }

    const transitInfo = calculateTransitAspects(natalPlanets);
    transitInfo.aspects = transitInfo.aspects.filter((a) => a.transitPlanet !== a.natalPlanet);
    let astroPulsePayload = buildAstroPulse(todayDate, ctx, transitInfo, hasChart);
    astroPulsePayload.personalized = hasChart;

    const aspectList = transitInfo.aspects.slice(0, 6).map((a) => `${a.title} (orb ${a.orb}°)`).join('; ') || 'none within orb';
    const ai = await chatCompletion({
      messages: [{
        role: 'system',
        content: `You are a Vedic astrologer writing a short daily forecast for ${todayDate}.
Natal chart: Lagna ${ctx.ascendant}, Moon ${ctx.moon_sign}, Sun ${ctx.sun_sign}, Nakshatra ${ctx.nakshatra}.
Actual transit-to-natal aspects today (computed, do not invent others): ${aspectList}.
Return ONLY JSON: {"headlineMain": "2 words max", "headlineSub": "1 word", "summary": "2 sentences", "detailedForecast": {"career": "...", "love": "...", "remedies": "..."}}`
      }],
      temperature: 0.4,
      maxTokens: 500,
      json: true,
      timeoutMs: 20000
    });
    if (ai && typeof ai === 'object') {
      const pick = (v, fallback) => (typeof v === 'string' && v.trim() ? v.trim() : fallback);
      astroPulsePayload = {
        ...astroPulsePayload,
        headlineMain: pick(ai.headlineMain, astroPulsePayload.headlineMain),
        headlineSub: pick(ai.headlineSub, astroPulsePayload.headlineSub),
        summary: pick(ai.summary, astroPulsePayload.summary),
        detailedForecast: {
          career: pick(ai.detailedForecast?.career, astroPulsePayload.detailedForecast.career),
          love: pick(ai.detailedForecast?.love, astroPulsePayload.detailedForecast.love),
          remedies: pick(ai.detailedForecast?.remedies, astroPulsePayload.detailedForecast.remedies)
        }
      };
    }

    const panchangPayload = calculateDailyPanchangAndMuhurats(todayDate);

    if (userId && hasChart) {
      await db.query(
        `INSERT INTO daily_horoscopes (user_id, date, astro_pulse, panchang)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, date)
         DO UPDATE SET astro_pulse = EXCLUDED.astro_pulse, panchang = EXCLUDED.panchang`,
        [userId, todayDate, JSON.stringify(astroPulsePayload), JSON.stringify(panchangPayload)]
      );
    }

    res.json({ ...astroPulsePayload, panchang: panchangPayload });
  } catch (error) {
    inputErrorOr500(res, error, 'Failed to calculate AstroPulse daily transits');
  }
});

// GET /api/horoscope/panchang?date=YYYY-MM-DD&lat=..&lng=..&tz=Asia/Kolkata
router.get('/panchang', (req, res) => {
  try {
    const { lat, lng, tz } = locationFromQuery(req.query);
    const date = typeof req.query.date === 'string' && req.query.date ? req.query.date : todayISO(tz);
    res.json(calculateDailyPanchangAndMuhurats(date, lat, lng, tz));
  } catch (error) {
    inputErrorOr500(res, error, 'Failed to calculate daily Panchang & Muhurats');
  }
});

const SYNASTRY_PLANETS = [
  { key: 'Sun', label: 'Sun ☉ (Willpower)' },
  { key: 'Moon', label: 'Moon ☽ (Emotions)' },
  { key: 'Venus', label: 'Venus ♀ (Romance)' },
  { key: 'Mars', label: 'Mars ♂ (Passion)' }
];

function signRelation(s1, s2) {
  const i1 = ZODIAC_SIGNS.indexOf(s1);
  const i2 = ZODIAC_SIGNS.indexOf(s2);
  if (i1 < 0 || i2 < 0) return { alignment: 'Unknown', verdict: 'Insufficient data' };
  const d = Math.min((i1 - i2 + 12) % 12, (i2 - i1 + 12) % 12);
  switch (d) {
    case 0: return { alignment: 'Conjunction (0°)', verdict: 'Shared Focus' };
    case 2: return { alignment: 'Sextile (60°)', verdict: 'Supportive Harmony' };
    case 3: return { alignment: 'Square (90°)', verdict: 'Dynamic Tension' };
    case 4: return { alignment: 'Trine (120°)', verdict: 'Natural Flow' };
    case 6: return { alignment: 'Opposition (180°)', verdict: 'Attraction of Opposites' };
    default: return { alignment: `${d * 30}° apart`, verdict: 'Requires Adjustment' };
  }
}

function verdictForGunas(total) {
  if (total < 18) return 'Low Compatibility (Not Recommended)';
  if (total <= 24) return 'Average Compatibility (Madhyam Milan)';
  if (total <= 32) return 'Very Good Compatibility (Uttam Milan)';
  return 'Excellent Compatibility (Sarvottam Milan)';
}

// POST /api/horoscope/synastry
// Ashtakoot Guna Milan between the logged-in user's chart and the partner's birth details.
router.post('/synastry', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : null;
    const body = req.body || {};
    const partnerName = typeof body.partnerName === 'string' && body.partnerName.trim() ? body.partnerName.trim().slice(0, 100) : 'Partner';
    const partnerGender = typeof body.partnerGender === 'string' ? body.partnerGender.trim() : '';
    const { partnerDob, partnerTob, partnerPob, partnerLatitude, partnerLongitude, partnerTimezone } = body;

    if (!partnerDob || !partnerTob) {
      return res.status(400).json({ error: "Partner's date and time of birth are required" });
    }

    let user = null;
    if (userId) {
      const q = await db.query(
        `SELECT u.full_name AS user_name, COALESCE(bd.gender, u.gender) AS gender,
                k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.planetary_positions, k.kundli_data
         FROM users u
         LEFT JOIN birth_details bd ON u.id = bd.user_id
         LEFT JOIN kundlis k ON u.id = k.user_id
         WHERE u.id = $1`,
        [userId]
      );
      if (q.rows.length > 0 && q.rows[0].moon_sign && q.rows[0].nakshatra) user = q.rows[0];
    }
    if (!user) {
      return res.status(409).json({ error: 'Please generate your own Kundli first so compatibility can be calculated.' });
    }

    const partner = calculateKundli(partnerDob, partnerTob, partnerPob || '', partnerLatitude, partnerLongitude, partnerTimezone || undefined);
    const userPlanets = parseJson(user.planetary_positions, []);
    const userFull = parseJson(user.kundli_data, {}) || {};
    const userMoon = {
      moonLongitude: userFull.moonLongitude,
      moonSign: user.moon_sign,
      nakshatra: user.nakshatra
    };
    const partnerMoon = { moonLongitude: partner.moonLongitude, moonSign: partner.moonSign, nakshatra: partner.nakshatra };

    // Traditional Guna Milan is directional (boy / girl). Partner gender decides the roles;
    // if unspecified, the user is treated as the boy.
    const isMale = (g) => /^m(ale)?$/i.test(String(g || '').trim());
    const isFemale = (g) => /^f(emale)?$/i.test(String(g || '').trim());
    let userIsBoy = true;
    if (isMale(partnerGender)) userIsBoy = false;
    else if (isFemale(partnerGender)) userIsBoy = true;
    else if (isFemale(user.gender)) userIsBoy = false;
    const result = userIsBoy ? calculateAshtakoot(userMoon, partnerMoon) : calculateAshtakoot(partnerMoon, userMoon);

    const userName = user.user_name || 'User';
    const total = result.total;
    const userManglik = manglikStatus(userPlanets);
    const partnerManglik = manglikStatus(partner.planetaryPositions);
    const manglikFmt = (m) => (m.house ? `${m.status} (Mars in house ${m.house})` : m.status);
    let manglikVerdict;
    if (userManglik.status === 'Unknown') manglikVerdict = 'Manglik status could not be determined for both charts.';
    else if (userManglik.status === partnerManglik.status) manglikVerdict = userManglik.status === 'Manglik'
      ? 'Both partners are Manglik, which traditionally cancels the dosha.'
      : 'Neither partner is Manglik. No Mangal Dosha concerns.';
    else manglikVerdict = 'Only one partner is Manglik. Traditional texts recommend checking cancellation factors with an astrologer.';

    const planetFor = (list, key) => (Array.isArray(list) ? list : []).find((p) => String(p.name || p.planet || '').startsWith(key));
    const planetarySynastry = SYNASTRY_PLANETS.map(({ key, label }) => {
      const p1 = planetFor(userPlanets, key);
      const p2 = planetFor(partner.planetaryPositions, key);
      const p1Sign = p1 ? p1.sign : (key === 'Sun' ? user.sun_sign : key === 'Moon' ? user.moon_sign : 'Unknown');
      const p2Sign = p2 ? p2.sign : 'Unknown';
      return { planet: label, p1Sign, p2Sign, ...signRelation(p1Sign, p2Sign) };
    });

    const percent = Math.round((total / 36) * 100);
    let synastryResult = {
      score: percent,
      gunaTotal: total,
      gunas: `${total} / 36 Gunas`,
      verdict: verdictForGunas(total),
      summary: `${userName} (Moon in ${user.moon_sign}, ${user.nakshatra}) and ${partnerName} (Moon in ${partner.moonSign}, ${partner.nakshatra}) score ${total} of 36 Gunas.`,
      ashtakoot: result.kootas,
      manglikCheck: {
        person1Status: manglikFmt(userManglik),
        person2Status: manglikFmt(partnerManglik),
        manglikVerdict
      },
      nadiBhakootAnalysis: {
        nadiVerdict: result.nadiDosha
          ? `Nadi Dosha present: both belong to ${result.bNadi} Nadi (0/8). Traditionally considered significant; remedies and cancellation factors should be reviewed.`
          : `No Nadi Dosha (${result.bNadi} / ${result.gNadi}), 8/8.`,
        bhakootVerdict: result.bhakootDosha
          ? `Bhakoot Dosha present (${result.axis} axis), 0/7.`
          : `No Bhakoot Dosha (${result.axis} axis), 7/7.`
      },
      planetarySynastry,
      partnerChart: {
        ascendant: partner.ascendant,
        moonSign: partner.moonSign,
        sunSign: partner.sunSign,
        nakshatra: partner.nakshatra,
        nakshatraPada: partner.nakshatraPada
      },
      advice: total >= 18
        ? 'The Guna score supports this match. Nurture open communication and shared goals.'
        : 'The Guna score is below the traditional threshold of 18. Consider a detailed consultation before major decisions.',
      relationshipReport: `### Emotional Bond
${userName}'s Moon in ${user.moon_sign} and ${partnerName}'s Moon in ${partner.moonSign} describe the emotional rapport between you.

### Guna Milan Summary
Total ${total}/36 Gunas: ${verdictForGunas(total)}.

### Guidance
Compatibility scores are one traditional input among many; mutual respect, values and communication matter most.`
    };

    const kootaText = result.kootas.map((k) => `${k.name} ${k.score}/${k.max} (${k.verdict})`).join(', ');
    const ai = await chatCompletion({
      messages: [{
        role: 'system',
        content: `You are a Vedic astrologer. Write a relationship compatibility narrative based ONLY on these computed results (do not change any numbers).
Person 1: ${userName}, Lagna ${user.ascendant}, Moon ${user.moon_sign}, Nakshatra ${user.nakshatra}, ${manglikFmt(userManglik)}.
Person 2: ${partnerName}, Lagna ${partner.ascendant}, Moon ${partner.moonSign}, Nakshatra ${partner.nakshatra}, ${manglikFmt(partnerManglik)}.
Ashtakoot: ${kootaText}. Total ${total}/36.
Return ONLY JSON: {"summary": "2 sentences", "advice": "1-2 sentences", "relationshipReport": "Markdown with ### headings, 150-250 words"}`
      }],
      temperature: 0.4,
      maxTokens: 700,
      json: true,
      timeoutMs: 20000
    });
    if (ai && typeof ai === 'object') {
      for (const key of ['summary', 'advice', 'relationshipReport']) {
        if (typeof ai[key] === 'string' && ai[key].trim()) synastryResult[key] = ai[key].trim();
      }
    }

    res.json(synastryResult);
  } catch (err) {
    inputErrorOr500(res, err, 'Failed to calculate Synastry compatibility');
  }
});

// GET /api/horoscope/moonshine
router.get('/moonshine', (req, res) => {
  try {
    const { tz } = locationFromQuery(req.query);
    const m = calculateMoonPhase(Date.now(), tz);
    res.json({
      phase: m.phase,
      illumination: `${m.illumination}%`,
      moonSign: `Moon in ${m.moonSign}`,
      nakshatra: m.nakshatra,
      fullMoonDate: m.fullMoonDate,
      fullMoonISO: m.fullMoonISO,
      age: `${Math.round(m.ageDays)}d`,
      summary: `The Moon is in its ${m.phase} phase (${m.illumination}% illuminated), transiting ${m.moonSign} in ${m.nakshatra} Nakshatra.`
    });
  } catch (err) {
    inputErrorOr500(res, err, 'Failed to calculate Moonshine details');
  }
});

// GET /api/horoscope/star-talk (static community feed)
router.get('/star-talk', (req, res) => {
  res.json({
    posts: [
      {
        id: 1,
        handle: 'mars_reach',
        glyphs: '☉ ♑  ☽ ♒  ↑ ♍',
        text: "Saturn's aspect on my 10th house is bringing real productivity breakthroughs today! #astrology",
        likes: 24,
        comments: 7,
        avatarBg: '#DCEDC8'
      },
      {
        id: 2,
        handle: 'lunar_seeker',
        glyphs: '☉ ♋  ☽ ♉  ↑ ♈',
        text: 'Jupiter moving into my 10th house is already giving me career alignment signals!',
        likes: 42,
        comments: 12,
        avatarBg: '#E1BEE7'
      },
      {
        id: 3,
        handle: 'vedic_sage',
        glyphs: '☉ ♊  ☽ ♓  ↑ ♏',
        text: 'Uttara Bhadrapada Nakshatra transit encourages meditation and deep self-inquiry.',
        likes: 38,
        comments: 9,
        avatarBg: '#FFECB3'
      }
    ]
  });
});

// GET /api/horoscope/hora?lat=..&lng=..&tz=..
router.get('/hora', (req, res) => {
  try {
    const { lat, lng, tz } = locationFromQuery(req.query);
    res.json(calculateCurrentHora(Date.now(), lat, lng, tz));
  } catch (err) {
    inputErrorOr500(res, err, 'Failed to calculate current Hora');
  }
});

// GET /api/horoscope/daily?sign=Aries
router.get('/daily', (req, res) => {
  const sign = typeof req.query.sign === 'string' ? req.query.sign : 'Aries';
  const signKey = ZODIAC_SIGNS.find((s) => s.toLowerCase() === sign.toLowerCase().trim()) || 'Aries';
  res.json({
    sign: signKey,
    date: todayISO(DEFAULT_TIMEZONE),
    ...HOROSCOPE_DATA[signKey]
  });
});

module.exports = router;
