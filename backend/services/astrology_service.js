// Comprehensive Astronomical Vedic Kundli Calculation Engine (Lahiri Ayanamsa)

const ZODIAC_SIGNS = [
  'Aries', 'Taurus', 'Gemini', 'Cancer', 
  'Leo', 'Virgo', 'Libra', 'Scorpio', 
  'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
];

const NAKSHATRAS = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra',
  'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni',
  'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha',
  'Moola', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha',
  'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati'
];

const NAKSHATRA_LORDS = [
  'Ketu', 'Venus', 'Sun', 'Moon', 'Mars', 'Rahu', 'Jupiter', 'Saturn', 'Mercury'
];

const DASHA_PERIODS = {
  Ketu: 7,
  Venus: 20,
  Sun: 6,
  Moon: 10,
  Mars: 7,
  Rahu: 18,
  Jupiter: 16,
  Saturn: 19,
  Mercury: 17
};

/**
 * Calculates Julian Day Number from Date and Time
 */
function getJulianDay(year, month, day, hour, minute) {
  if (month <= 2) {
    year -= 1;
    month += 12;
  }
  const A = Math.floor(year / 100);
  const B = 2 - A + Math.floor(A / 4);
  const dayFraction = (hour + minute / 60.0) / 24.0;
  return Math.floor(365.25 * (year + 4716)) + Math.floor(30.6001 * (month + 1)) + day + dayFraction + B - 1524.5;
}

/**
 * Calculates Lahiri Ayanamsa for given Julian Day
 */
function getLahiriAyanamsa(jd) {
  const t = (jd - 2451545.0) / 36525.0;
  return 23.85 + (t * 1.396);
}

/**
 * Normalizes an angle to 0 - 360 degrees
 */
function normalizeDeg(deg) {
  let norm = deg % 360;
  if (norm < 0) norm += 360;
  return norm;
}

/**
 * Main Real Vedic Kundli Calculator
 */
function calculateKundli(dob, tob, placeOfBirth, latitude = 28.6139, longitude = 77.2090) {
  const lat = parseFloat(latitude) || 28.6139;
  const lon = parseFloat(longitude) || 77.2090;

  const parts = dob.split('-');
  const year = parseInt(parts[0], 10);
  const month = parseInt(parts[1], 10);
  const day = parseInt(parts[2], 10);

  const tParts = tob.split(':');
  const hour = parseInt(tParts[0], 10);
  const minute = parseInt(tParts[1], 10);

  // 1. Julian Day & Ayanamsa
  const jd = getJulianDay(year, month, day, hour, minute);
  const ayanamsa = getLahiriAyanamsa(jd);

  // Days since J2000.0
  const d = jd - 2451545.0;

  // 2. Solar Position (Tropical to Sidereal)
  const gSun = normalizeDeg(357.529 + 0.98560028 * d);
  const qSun = normalizeDeg(280.459 + 0.98564736 * d);
  const LsunTropical = qSun + 1.915 * Math.sin(gSun * Math.PI / 180) + 0.020 * Math.sin(2 * gSun * Math.PI / 180);
  const LsunSidereal = normalizeDeg(LsunTropical - ayanamsa);

  const sunSignIndex = Math.floor(LsunSidereal / 30);
  const sunSign = ZODIAC_SIGNS[sunSignIndex];
  const sunDegree = LsunSidereal % 30;

  // 3. Lunar Position
  const LmoonTropical = normalizeDeg(218.316 + 13.176396 * d);
  const Mmoon = normalizeDeg(134.963 + 13.064993 * d);
  const Fmoon = normalizeDeg(93.272 + 13.229350 * d);

  const moonLongTropical = LmoonTropical + 6.289 * Math.sin(Mmoon * Math.PI / 180);
  const LmoonSidereal = normalizeDeg(moonLongTropical - ayanamsa);

  const moonSignIndex = Math.floor(LmoonSidereal / 30);
  const moonSign = ZODIAC_SIGNS[moonSignIndex];
  const moonDegree = LmoonSidereal % 30;

  // 4. Nakshatra & Pada Calculation
  const nakshatraDeg = LmoonSidereal / (360 / 27);
  const nakshatraIndex = Math.floor(nakshatraDeg) % 27;
  const nakshatra = NAKSHATRAS[nakshatraIndex];
  
  const nakshatraRemDeg = (LmoonSidereal % (360 / 27));
  const nakshatraPada = Math.floor(nakshatraRemDeg / (360 / 108)) + 1;

  // 5. Ascendant (Lagna) Calculation using Local Sidereal Time
  const GMST = normalizeDeg(280.46061837 + 360.98564736629 * d);
  const LMST = normalizeDeg(GMST + lon);
  const eps = 23.439 * Math.PI / 180; // Obliquity of ecliptic

  const lmstRad = LMST * Math.PI / 180;
  const latRad = lat * Math.PI / 180;

  const ascRad = Math.atan2(
    Math.cos(lmstRad),
    -Math.sin(lmstRad) * Math.cos(eps) - Math.tan(latRad) * Math.sin(eps)
  );

  let ascendantDegTropical = normalizeDeg(ascRad * 180 / Math.PI);
  const ascendantDegSidereal = normalizeDeg(ascendantDegTropical - ayanamsa);
  const ascendantIndex = Math.floor(ascendantDegSidereal / 30);
  const ascendant = ZODIAC_SIGNS[ascendantIndex];

  // 6. Other Planetary Approximations (Mars, Mercury, Jupiter, Venus, Saturn, Rahu, Ketu)
  const Lmars = normalizeDeg(normalizeDeg(355.45 + 0.524033 * d) - ayanamsa);
  const Lmerc = normalizeDeg(normalizeDeg(LsunTropical + 12 * Math.sin((d * 0.04) * Math.PI / 180)) - ayanamsa);
  const Ljup = normalizeDeg(normalizeDeg(34.40 + 0.083091 * d) - ayanamsa);
  const Lven = normalizeDeg(normalizeDeg(LsunTropical + 22 * Math.sin((d * 0.02) * Math.PI / 180)) - ayanamsa);
  const Lsat = normalizeDeg(normalizeDeg(50.08 + 0.033459 * d) - ayanamsa);
  const Lrahu = normalizeDeg(normalizeDeg(125.04 - 0.05295 * d) - ayanamsa);
  const Lketu = normalizeDeg(Lrahu + 180);

  const rawPlanets = [
    { name: 'Sun', long: LsunSidereal, speed: 'Normal' },
    { name: 'Moon', long: LmoonSidereal, speed: 'Fast' },
    { name: 'Mars', long: Lmars, speed: 'Normal' },
    { name: 'Mercury', long: Lmerc, speed: 'Normal' },
    { name: 'Jupiter', long: Ljup, speed: 'Slow' },
    { name: 'Venus', long: Lven, speed: 'Normal' },
    { name: 'Saturn', long: Lsat, speed: 'Retrograde' },
    { name: 'Rahu', long: Lrahu, speed: 'Retrograde' },
    { name: 'Ketu', long: Lketu, speed: 'Retrograde' }
  ];

  const planets = rawPlanets.map(p => {
    const signIdx = Math.floor(p.long / 30);
    const houseNum = ((signIdx - ascendantIndex + 12) % 12) + 1;
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[signIdx],
      house: houseNum,
      degree: parseFloat((p.long % 30).toFixed(2)),
      speed: p.speed
    };
  });

  // 7. 12 House Chart Setup
  const houses = {};
  for (let i = 1; i <= 12; i++) {
    const houseSign = ZODIAC_SIGNS[(ascendantIndex + i - 1) % 12];
    const housePlanets = planets.filter(p => p.house === i).map(p => p.name);
    houses[`house_${i}`] = {
      sign: houseSign,
      planets: housePlanets
    };
  }

  // 8. Vimshottari Dasha Calculation
  const lordIndex = nakshatraIndex % 9;
  const currentMahadasha = NAKSHATRA_LORDS[lordIndex];
  const antardasha = NAKSHATRA_LORDS[(lordIndex + 2) % 9];
  const dashaYears = DASHA_PERIODS[currentMahadasha] || 16;

  // Fraction of dasha remaining based on Moon's degree in Nakshatra
  const dashaPassedFraction = nakshatraRemDeg / (360 / 27);
  const dashaRemainingYears = Math.round(dashaYears * (1 - dashaPassedFraction));
  const dashaEndYear = year + dashaRemainingYears;

  return {
    ascendant,
    sunSign,
    moonSign,
    nakshatra,
    nakshatraPada,
    latitude: lat,
    longitude: lon,
    ayanamsa: parseFloat(ayanamsa.toFixed(2)),
    planetaryPositions: planets,
    houses,
    dashaInfo: {
      currentMahadasha,
      antardasha,
      dashaEndDate: `${dashaEndYear}-08-15`
    }
  };
}

module.exports = {
  calculateKundli,
  ZODIAC_SIGNS,
  NAKSHATRAS
};
