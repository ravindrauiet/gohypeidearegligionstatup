// Vedic Astrology Calculation Engine
// Swiss Ephemeris (sweph, Moshier analytical ephemeris - no data files required)
// with Lahiri (Chitrapaksha) ayanamsa, plus optional OpenAI narrative generation.

const sweph = require('sweph');
const tzLookup = require('@photostructure/tz-lookup');
const { chatCompletion } = require('./openai_client');

const C = sweph.constants;
const SE_GREG_CAL = C.SE_GREG_CAL;
// Moshier ephemeris is built in (accuracy ~1 arc-second for planets) and avoids
// "ephemeris file not found" fallbacks when the .se1 files are not deployed.
const EPHE_FLAG = C.SEFLG_MOSEPH;
const SIDEREAL_FLAGS = EPHE_FLAG | C.SEFLG_SIDEREAL | C.SEFLG_SPEED;
const TROPICAL_FLAGS = EPHE_FLAG | C.SEFLG_SPEED;

sweph.set_sid_mode(C.SE_SIDM_LAHIRI, 0, 0);

const DEFAULT_TIMEZONE = 'Asia/Kolkata';
const DEFAULT_LAT = 28.6139; // New Delhi
const DEFAULT_LON = 77.2090;

const ZODIAC_SIGNS = [
  'Aries', 'Taurus', 'Gemini', 'Cancer',
  'Leo', 'Virgo', 'Libra', 'Scorpio',
  'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
];

const SIGN_LORDS = [
  'Mars', 'Venus', 'Mercury', 'Moon', 'Sun', 'Mercury',
  'Venus', 'Mars', 'Jupiter', 'Saturn', 'Saturn', 'Jupiter'
];

const NAKSHATRAS = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra',
  'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni',
  'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha',
  'Moola', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha',
  'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati'
];

// Vimshottari lords in sequence starting from Ashwini (Ketu)
const NAKSHATRA_LORDS = [
  'Ketu', 'Venus', 'Sun', 'Moon', 'Mars', 'Rahu', 'Jupiter', 'Saturn', 'Mercury'
];

const DASHA_PERIODS = {
  Ketu: 7, Venus: 20, Sun: 6, Moon: 10, Mars: 7,
  Rahu: 18, Jupiter: 16, Saturn: 19, Mercury: 17
};

const NAKSHATRA_SPAN = 360 / 27; // 13°20'
const PADA_SPAN = 360 / 108; // 3°20'
const DAY_MS = 86400000;
const YEAR_DAYS = 365.25;

const GANA_LIST = [
  'Deva', 'Manushya', 'Rakshasa', 'Manushya', 'Deva', 'Manushya', 'Deva', 'Deva', 'Rakshasa',
  'Rakshasa', 'Manushya', 'Manushya', 'Deva', 'Rakshasa', 'Deva', 'Rakshasa', 'Deva', 'Rakshasa',
  'Rakshasa', 'Manushya', 'Manushya', 'Deva', 'Rakshasa', 'Rakshasa', 'Manushya', 'Manushya', 'Deva'
];
const NADI_LIST = [
  'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya',
  'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi',
  'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya'
];
const YONI_LIST = [
  'Horse', 'Elephant', 'Sheep', 'Serpent', 'Serpent', 'Dog', 'Cat', 'Sheep', 'Cat',
  'Rat', 'Rat', 'Cow', 'Buffalo', 'Tiger', 'Buffalo', 'Tiger', 'Deer', 'Deer',
  'Dog', 'Monkey', 'Mongoose', 'Monkey', 'Lion', 'Horse', 'Lion', 'Cow', 'Elephant'
];
const VARNA_BY_SIGN = [
  'Kshatriya', 'Vaishya', 'Shudra', 'Brahmin', 'Kshatriya', 'Vaishya',
  'Shudra', 'Brahmin', 'Kshatriya', 'Vaishya', 'Shudra', 'Brahmin'
];
const TATWA_BY_SIGN = [
  'Fire', 'Earth', 'Air', 'Water', 'Fire', 'Earth', 'Air', 'Water', 'Fire', 'Earth', 'Air', 'Water'
];

const TITHI_NAMES = [
  'Pratipada', 'Dwitiya', 'Tritiya', 'Chaturthi', 'Panchami', 'Shashthi', 'Saptami', 'Ashtami',
  'Navami', 'Dashami', 'Ekadashi', 'Dwadashi', 'Trayodashi', 'Chaturdashi'
];
const YOGA_NAMES = [
  'Vishkambha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda', 'Sukarma', 'Dhriti',
  'Shoola', 'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata', 'Harshana', 'Vajra', 'Siddhi', 'Vyatipata',
  'Variyan', 'Parigha', 'Shiva', 'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma', 'Indra', 'Vaidhriti'
];
const MOVABLE_KARANAS = ['Bava', 'Balava', 'Kaulava', 'Taitila', 'Garaja', 'Vanija', 'Vishti (Bhadra)'];
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const WEEKDAY_LORDS = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn'];

const PLANET_GLYPHS = {
  Sun: '☉', Moon: '☽', Mars: '♂', Mercury: '☿', Jupiter: '♃',
  Venus: '♀', Saturn: '♄', Rahu: '☊', Ketu: '☋'
};

const PLANET_CONFIG = [
  { id: C.SE_SUN, name: 'Sun ☉' },
  { id: C.SE_MOON, name: 'Moon ☽' },
  { id: C.SE_MARS, name: 'Mars ♂' },
  { id: C.SE_MERCURY, name: 'Mercury ☿' },
  { id: C.SE_JUPITER, name: 'Jupiter ♃' },
  { id: C.SE_VENUS, name: 'Venus ♀' },
  { id: C.SE_SATURN, name: 'Saturn ♄' },
  { id: C.SE_TRUE_NODE, name: 'Rahu ☊' },
];

class AstrologyInputError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AstrologyInputError';
    this.statusCode = 400;
  }
}

// ---------------------------------------------------------------------------
// Generic helpers
// ---------------------------------------------------------------------------

const norm360 = (x) => ((x % 360) + 360) % 360;
const signIndexOf = (long) => Math.floor(norm360(long) / 30) % 12;
const baseName = (name) => String(name || '').split(' ')[0];
// Degree within sign, truncated (not rounded) so 29.999 never displays as 30.00
const degInSign = (long) => Math.floor((norm360(long) % 30) * 100) / 100;
const pad2 = (n) => String(n).padStart(2, '0');

function parseDateParts(dob, label = 'dateOfBirth') {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(String(dob || '').trim());
  if (!m) throw new AstrologyInputError(`${label} must be in YYYY-MM-DD format`);
  const year = parseInt(m[1], 10);
  const month = parseInt(m[2], 10);
  const day = parseInt(m[3], 10);
  const check = new Date(Date.UTC(year, month - 1, day));
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) {
    throw new AstrologyInputError(`${label} is not a valid calendar date`);
  }
  if (year < 1800 || year > 2399) throw new AstrologyInputError(`${label} year must be between 1800 and 2399`);
  return { year, month, day };
}

function parseTimeParts(tob) {
  const m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$/.exec(String(tob || '').trim());
  if (!m) throw new AstrologyInputError('timeOfBirth must be in HH:MM (24h) or HH:MM AM/PM format');
  let hour = parseInt(m[1], 10);
  const minute = parseInt(m[2], 10);
  const second = m[3] ? parseInt(m[3], 10) : 0;
  const ampm = m[4] ? m[4].toUpperCase() : null;
  if (ampm) {
    if (hour < 1 || hour > 12) throw new AstrologyInputError('timeOfBirth hour must be 1-12 with AM/PM');
    if (ampm === 'AM' && hour === 12) hour = 0;
    if (ampm === 'PM' && hour !== 12) hour += 12;
  }
  if (hour > 23 || minute > 59 || second > 59) throw new AstrologyInputError('timeOfBirth is not a valid time');
  return { hour, minute, second };
}

function parseCoordinate(value, fallback, min, max, label) {
  if (value === undefined || value === null || value === '') return fallback;
  const n = typeof value === 'number' ? value : parseFloat(value);
  if (!Number.isFinite(n) || n < min || n > max) {
    throw new AstrologyInputError(`${label} must be a number between ${min} and ${max}`);
  }
  return n;
}

function isValidTimeZone(tz) {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Accepts an IANA zone ("Asia/Kolkata"), a numeric offset in hours (5.5),
 * or an offset string ("+05:30", "UTC+5:30"). Returns a normalized descriptor.
 */
function resolveTimeZone(timezone) {
  if (timezone === undefined || timezone === null || timezone === '') {
    return { type: 'iana', zone: DEFAULT_TIMEZONE };
  }
  if (typeof timezone === 'number' && Number.isFinite(timezone) && Math.abs(timezone) <= 14) {
    return { type: 'offset', minutes: Math.round(timezone * 60) };
  }
  const str = String(timezone).trim();
  const off = /^(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d{2}))?$/i.exec(str);
  if (off) {
    const minutes = (parseInt(off[2], 10) * 60 + (off[3] ? parseInt(off[3], 10) : 0)) * (off[1] === '-' ? -1 : 1);
    if (Math.abs(minutes) > 14 * 60) throw new AstrologyInputError('timezone offset out of range');
    return { type: 'offset', minutes };
  }
  if (/^-?\d+(\.\d+)?$/.test(str)) return resolveTimeZone(parseFloat(str));
  if (isValidTimeZone(str)) return { type: 'iana', zone: str };
  throw new AstrologyInputError('timezone must be an IANA zone (e.g. Asia/Kolkata) or an offset like +05:30');
}

/**
 * The timezone a birth must be interpreted in. An explicit zone/offset wins;
 * otherwise it is derived from the birth place coordinates (so a 12:00 birth in
 * New York is 12:00 America/New_York, not IST). Falls back to Asia/Kolkata.
 */
function timezoneForLocation(timezone, latitude, longitude) {
  if (timezone !== undefined && timezone !== null && String(timezone).trim() !== '') return timezone;
  const lat = typeof latitude === 'number' ? latitude : parseFloat(latitude);
  const lon = typeof longitude === 'number' ? longitude : parseFloat(longitude);
  if (Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180) {
    try {
      return tzLookup(lat, lon);
    } catch (_) {
      // fall through to default
    }
  }
  return DEFAULT_TIMEZONE;
}

// Offset (minutes east of UTC) of an IANA zone at a given UTC instant
function zoneOffsetMinutes(zone, utcMs) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: zone, hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  });
  const parts = {};
  for (const p of dtf.formatToParts(new Date(utcMs))) parts[p.type] = p.value;
  const asUtc = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour % 24, +parts.minute, +parts.second);
  return Math.round((asUtc - Math.floor(utcMs / 1000) * 1000) / 60000);
}

function offsetMinutesAt(tzDesc, utcMs) {
  return tzDesc.type === 'offset' ? tzDesc.minutes : zoneOffsetMinutes(tzDesc.zone, utcMs);
}

// Convert a wall-clock local time in tzDesc into a UTC epoch (ms). Handles DST and historical offsets.
function localToUtcMs(y, mo, d, h, mi, s, tzDesc) {
  const wall = Date.UTC(y, mo - 1, d, h, mi, s);
  let utc = wall - offsetMinutesAt(tzDesc, wall) * 60000;
  const off2 = offsetMinutesAt(tzDesc, utc);
  utc = wall - off2 * 60000;
  return utc;
}

// Calendar parts of a UTC instant as seen in tzDesc
function utcToLocalParts(utcMs, tzDesc) {
  const shifted = new Date(utcMs + offsetMinutesAt(tzDesc, utcMs) * 60000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    weekday: shifted.getUTCDay(),
  };
}

function todayISO(timezone = DEFAULT_TIMEZONE, nowMs = Date.now()) {
  const p = utcToLocalParts(nowMs, resolveTimeZone(timezone));
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
}

function formatClock(utcMs, tzDesc) {
  if (!Number.isFinite(utcMs)) return '--';
  const p = utcToLocalParts(utcMs, tzDesc);
  const h12 = p.hour % 12 === 0 ? 12 : p.hour % 12;
  return `${pad2(h12)}:${pad2(p.minute)} ${p.hour < 12 ? 'AM' : 'PM'}`;
}

function isoDateFromMs(ms) {
  return new Date(ms).toISOString().split('T')[0];
}

function julianDayFromUtcMs(utcMs) {
  const d = new Date(utcMs);
  const hours = d.getUTCHours() + d.getUTCMinutes() / 60 + (d.getUTCSeconds() + d.getUTCMilliseconds() / 1000) / 3600;
  const jd = sweph.julday(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate(), hours, SE_GREG_CAL);
  return typeof jd === 'object' && jd !== null ? (jd.julianDay ?? jd.data) : jd;
}

function utcMsFromJulianDay(jd) {
  // JD 2440587.5 == 1970-01-01T00:00:00Z
  return (jd - 2440587.5) * DAY_MS;
}

function calcBody(jd, id, flags = SIDEREAL_FLAGS) {
  const res = sweph.calc_ut(jd, id, flags);
  if (!res || !Array.isArray(res.data)) {
    throw new Error(`Swiss Ephemeris failed for body ${id}: ${res && res.error}`);
  }
  if (res.flag < 0) throw new Error(`Swiss Ephemeris error for body ${id}: ${res.error}`);
  return { long: norm360(res.data[0]), speed: res.data[3] };
}

// ---------------------------------------------------------------------------
// Divisional charts
// ---------------------------------------------------------------------------

// D9 Navamsha: fiery signs start from Aries, earthy from Capricorn, airy from Libra, watery from Cancer
function getNavamshaSignIndex(long) {
  const l = norm360(long);
  const signIdx = Math.floor(l / 30) % 12;
  const navIdx = Math.min(8, Math.floor((l % 30) / (30 / 9)));
  const startSign = [0, 9, 6, 3][signIdx % 4];
  return (startSign + navIdx) % 12;
}

// D10 Dasamsha: odd signs start from the sign itself, even signs from the 9th sign
function getDasamshaSignIndex(long) {
  const l = norm360(long);
  const signIdx = Math.floor(l / 30) % 12;
  const dasIdx = Math.min(9, Math.floor((l % 30) / 3));
  const startSign = signIdx % 2 === 0 ? signIdx : (signIdx + 8) % 12;
  return (startSign + dasIdx) % 12;
}

// ---------------------------------------------------------------------------
// Vimshottari Dasha
// ---------------------------------------------------------------------------

function addYearsMs(ms, years) {
  return ms + years * YEAR_DAYS * DAY_MS;
}

/**
 * Full Vimshottari computation from the Moon's sidereal longitude at birth.
 * Returns the running Mahadasha/Antardasha as of `nowMs` plus the full sequence.
 */
function computeVimshottari(moonLong, birthUtcMs, nowMs = Date.now()) {
  const l = norm360(moonLong);
  const nakIdx = Math.floor(l / NAKSHATRA_SPAN) % 27;
  const startLordIdx = nakIdx % 9;
  const elapsedFraction = (l % NAKSHATRA_SPAN) / NAKSHATRA_SPAN;
  const firstLord = NAKSHATRA_LORDS[startLordIdx];
  const balanceYears = DASHA_PERIODS[firstLord] * (1 - elapsedFraction);

  // Theoretical start of the first (partially elapsed) Mahadasha
  let cursor = addYearsMs(birthUtcMs, -DASHA_PERIODS[firstLord] * elapsedFraction);
  const sequence = [];
  // Two full 120-year cycles is more than enough to cover any lifetime
  for (let i = 0; i < 18; i++) {
    const lord = NAKSHATRA_LORDS[(startLordIdx + i) % 9];
    const end = addYearsMs(cursor, DASHA_PERIODS[lord]);
    sequence.push({ lord, startMs: cursor, endMs: end });
    cursor = end;
  }

  const refMs = Math.max(nowMs, birthUtcMs);
  const md = sequence.find((s) => refMs >= s.startMs && refMs < s.endMs) || sequence[0];
  const mdYears = DASHA_PERIODS[md.lord];
  const mdLordIdx = NAKSHATRA_LORDS.indexOf(md.lord);

  let adCursor = md.startMs;
  let ad = null;
  for (let j = 0; j < 9; j++) {
    const adLord = NAKSHATRA_LORDS[(mdLordIdx + j) % 9];
    const adEnd = addYearsMs(adCursor, (mdYears * DASHA_PERIODS[adLord]) / 120);
    if (refMs >= adCursor && refMs < adEnd) {
      ad = { lord: adLord, startMs: adCursor, endMs: adEnd };
      break;
    }
    adCursor = adEnd;
  }
  if (!ad) ad = { lord: md.lord, startMs: md.startMs, endMs: md.endMs };

  return {
    currentMahadasha: md.lord,
    antardasha: ad.lord,
    mahadashaStartDate: isoDateFromMs(Math.max(md.startMs, birthUtcMs)),
    dashaEndDate: isoDateFromMs(md.endMs),
    antardashaStartDate: isoDateFromMs(Math.max(ad.startMs, birthUtcMs)),
    antardashaEndDate: isoDateFromMs(ad.endMs),
    balanceAtBirth: {
      planet: firstLord,
      years: parseFloat(balanceYears.toFixed(2))
    },
    mahadashaSequence: sequence
      .filter((s) => s.endMs > birthUtcMs)
      .slice(0, 9)
      .map((s) => ({
        planet: s.lord,
        startDate: isoDateFromMs(Math.max(s.startMs, birthUtcMs)),
        endDate: isoDateFromMs(s.endMs)
      }))
  };
}

/**
 * Recompute time-dependent dasha info for a stored kundli (stored dasha goes stale).
 * Requires moonLongitude + birthUtc, which are stored for charts generated by this engine.
 */
function refreshDashaInfo(kundli, nowMs = Date.now()) {
  if (!kundli || typeof kundli !== 'object') return kundli;
  const moonLong = Number(kundli.moonLongitude);
  const birthMs = kundli.birthUtc ? Date.parse(kundli.birthUtc) : NaN;
  if (!Number.isFinite(moonLong) || !Number.isFinite(birthMs)) return kundli;
  try {
    return { ...kundli, dashaInfo: computeVimshottari(moonLong, birthMs, nowMs) };
  } catch (_) {
    return kundli;
  }
}

// ---------------------------------------------------------------------------
// Panchang elements
// ---------------------------------------------------------------------------

function panchangElements(sunLong, moonLong) {
  const elong = norm360(moonLong - sunLong);
  const tithiNum = Math.floor(elong / 12) + 1; // 1..30
  const paksha = tithiNum <= 15 ? 'Shukla' : 'Krishna';
  let tithiName;
  if (tithiNum === 15) tithiName = 'Purnima';
  else if (tithiNum === 30) tithiName = 'Amavasya';
  else tithiName = TITHI_NAMES[(tithiNum - 1) % 15];

  const yogaIdx = Math.floor(norm360(sunLong + moonLong) / NAKSHATRA_SPAN) % 27;

  const karanaNum = Math.floor(elong / 6); // 0..59
  let karana;
  if (karanaNum === 0) karana = 'Kimstughna';
  else if (karanaNum === 57) karana = 'Shakuni';
  else if (karanaNum === 58) karana = 'Chatushpada';
  else if (karanaNum === 59) karana = 'Naga';
  else karana = MOVABLE_KARANAS[(karanaNum - 1) % 7];

  const nakIdx = Math.floor(norm360(moonLong) / NAKSHATRA_SPAN) % 27;

  return {
    tithi: `${paksha} Paksha ${tithiName}`,
    tithiNumber: tithiNum,
    paksha,
    yoga: YOGA_NAMES[yogaIdx],
    karana,
    nakshatra: NAKSHATRAS[nakIdx],
    nakshatraIndex: nakIdx,
    elongation: elong
  };
}

function vashyaForLongitude(long) {
  const l = norm360(long);
  const s = signIndexOf(l);
  const firstHalf = (l % 30) < 15;
  switch (s) {
    case 0: case 1: return 'Chatushpada';
    case 2: case 5: case 6: case 10: return 'Manav';
    case 3: case 11: return 'Jalchar';
    case 4: return 'Vanchar';
    case 7: return 'Keet';
    case 8: return firstHalf ? 'Manav' : 'Chatushpada';
    case 9: return firstHalf ? 'Chatushpada' : 'Jalchar';
    default: return 'Manav';
  }
}

// Paya (by Moon's house from Lagna): 1,6,11 Gold; 2,5,9 Silver; 3,7,10 Copper; 4,8,12 Iron
function payaForMoonHouse(house) {
  if ([1, 6, 11].includes(house)) return 'Gold';
  if ([2, 5, 9].includes(house)) return 'Silver';
  if ([3, 7, 10].includes(house)) return 'Copper';
  return 'Iron';
}

// ---------------------------------------------------------------------------
// Birth chart
// ---------------------------------------------------------------------------

/**
 * @param {string} dob YYYY-MM-DD (local civil date at place of birth)
 * @param {string} tob HH:MM[:SS] or HH:MM AM/PM (local civil time)
 * @param {string} placeOfBirth informational only
 * @param {number} latitude north positive
 * @param {number} longitude east positive
 * @param {string|number} timezone IANA zone or UTC offset (default Asia/Kolkata)
 */
function calculateKundli(dob, tob, placeOfBirth, latitude, longitude, timezone, options = {}) {
  const lat = parseCoordinate(latitude, DEFAULT_LAT, -89.9, 89.9, 'latitude');
  const lon = parseCoordinate(longitude, DEFAULT_LON, -180, 180, 'longitude');
  const { year, month, day } = parseDateParts(dob);
  const { hour, minute, second } = parseTimeParts(tob);
  const tzDesc = resolveTimeZone(timezoneForLocation(timezone, lat, lon));

  const birthUtcMs = localToUtcMs(year, month, day, hour, minute, second, tzDesc);
  const utcOffsetMinutes = offsetMinutesAt(tzDesc, birthUtcMs);
  const julday = julianDayFromUtcMs(birthUtcMs);
  const ayanamsa = sweph.get_ayanamsa_ut(julday);

  // Sidereal ascendant (Lagna)
  const housesRes = sweph.houses_ex(julday, C.SEFLG_SIDEREAL, lat, lon, 'E');
  if (!housesRes || !housesRes.data) throw new Error('Swiss Ephemeris house calculation failed');
  const ascendantDeg = norm360(housesRes.data.points ? housesRes.data.points[0] : housesRes.data.houses[0]);
  const ascendantIndex = signIndexOf(ascendantDeg);
  const ascendant = ZODIAC_SIGNS[ascendantIndex];

  const d9AscendantIndex = getNavamshaSignIndex(ascendantDeg);
  const d10AscendantIndex = getDasamshaSignIndex(ascendantDeg);

  // Sidereal planetary longitudes
  const raw = PLANET_CONFIG.map((p) => ({ name: p.name, ...calcBody(julday, p.id) }));
  const rahu = raw.find((p) => p.name.startsWith('Rahu'));
  raw.push({ name: 'Ketu ☋', long: norm360(rahu.long + 180), speed: rahu.speed });

  const rawSunLong = raw.find((p) => p.name.startsWith('Sun')).long;
  const rawMoonLong = raw.find((p) => p.name.startsWith('Moon')).long;

  const houseFrom = (sIdx, ascIdx) => ((sIdx - ascIdx + 12) % 12) + 1;
  const motion = (p) => {
    const n = baseName(p.name);
    if (n === 'Sun' || n === 'Moon') return 'Direct';
    return p.speed < 0 ? 'Retrograde' : 'Direct';
  };

  const planets = raw.map((p) => {
    const signIdx = signIndexOf(p.long);
    const nakIdx = Math.floor(p.long / NAKSHATRA_SPAN) % 27;
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[signIdx],
      house: houseFrom(signIdx, ascendantIndex),
      degree: degInSign(p.long),
      longitude: parseFloat(p.long.toFixed(4)),
      speed: motion(p),
      nakshatra: NAKSHATRAS[nakIdx],
      nakshatraPada: Math.floor((p.long % NAKSHATRA_SPAN) / PADA_SPAN) + 1,
      planetLord: NAKSHATRA_LORDS[nakIdx % 9]
    };
  });

  const d9Planets = raw.map((p) => {
    const sIdx = getNavamshaSignIndex(p.long);
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[sIdx],
      house: houseFrom(sIdx, d9AscendantIndex),
      degree: degInSign(p.long * 9),
      speed: motion(p)
    };
  });

  const d10Planets = raw.map((p) => {
    const sIdx = getDasamshaSignIndex(p.long);
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[sIdx],
      house: houseFrom(sIdx, d10AscendantIndex),
      degree: degInSign(p.long * 10),
      speed: motion(p)
    };
  });

  // Moon nakshatra & pada
  const nakshatraIndex = Math.floor(rawMoonLong / NAKSHATRA_SPAN) % 27;
  const nakshatra = NAKSHATRAS[nakshatraIndex];
  const nakshatraPada = Math.floor((rawMoonLong % NAKSHATRA_SPAN) / PADA_SPAN) + 1;

  // Whole-sign houses from Lagna
  const houses = {};
  for (let i = 1; i <= 12; i++) {
    houses[`house_${i}`] = {
      sign: ZODIAC_SIGNS[(ascendantIndex + i - 1) % 12],
      planets: planets.filter((p) => p.house === i).map((p) => p.name)
    };
  }

  const dashaInfo = computeVimshottari(rawMoonLong, birthUtcMs);

  // Birth Panchang (vaar is the civil weekday of the local birth date)
  const pe = panchangElements(rawSunLong, rawMoonLong);
  const vaar = WEEKDAYS[new Date(Date.UTC(year, month - 1, day)).getUTCDay()];

  const moonSignIdx = signIndexOf(rawMoonLong);
  const moonHouse = houseFrom(moonSignIdx, ascendantIndex);

  // When the birth time is unknown the Lagna, houses and D9/D10 are only a noon
  // estimate, and the Moon may change sign/nakshatra during that day.
  let birthTime = { known: true };
  if (options.birthTimeKnown === false) {
    const moonSigns = new Set();
    const moonNakshatras = new Set();
    for (let h = 0; h <= 24; h++) {
      const ms = localToUtcMs(year, month, day, Math.min(h, 23), h === 24 ? 59 : 0, h === 24 ? 59 : 0, tzDesc);
      const moon = calcBody(julianDayFromUtcMs(ms), C.SE_MOON).long;
      moonSigns.add(ZODIAC_SIGNS[signIndexOf(moon)]);
      moonNakshatras.add(NAKSHATRAS[Math.floor(moon / NAKSHATRA_SPAN) % 27]);
    }
    birthTime = {
      known: false,
      assumedTime: `${pad2(hour)}:${pad2(minute)}`,
      lagnaReliable: false,
      moonSignCertain: moonSigns.size === 1,
      nakshatraCertain: moonNakshatras.size === 1,
      possibleMoonSigns: [...moonSigns],
      possibleNakshatras: [...moonNakshatras]
    };
  }

  return {
    ascendant,
    ascendantDegree: degInSign(ascendantDeg),
    birthTime,
    sunSign: ZODIAC_SIGNS[signIndexOf(rawSunLong)],
    moonSign: ZODIAC_SIGNS[moonSignIdx],
    nakshatra,
    nakshatraPada,
    latitude: lat,
    longitude: lon,
    timezone: tzDesc.type === 'iana' ? tzDesc.zone : `UTC${utcOffsetMinutes >= 0 ? '+' : '-'}${pad2(Math.floor(Math.abs(utcOffsetMinutes) / 60))}:${pad2(Math.abs(utcOffsetMinutes) % 60)}`,
    utcOffsetMinutes,
    birthUtc: new Date(birthUtcMs).toISOString(),
    moonLongitude: parseFloat(rawMoonLong.toFixed(6)),
    ayanamsa: parseFloat(ayanamsa.toFixed(4)),
    planetaryPositions: planets,
    panchang: {
      tithi: pe.tithi,
      paksha: pe.paksha,
      vaar,
      nakshatra,
      yoga: pe.yoga,
      karana: pe.karana
    },
    avakhada: {
      varna: VARNA_BY_SIGN[moonSignIdx],
      vashya: vashyaForLongitude(rawMoonLong),
      yoni: YONI_LIST[nakshatraIndex],
      gana: GANA_LIST[nakshatraIndex],
      nadi: NADI_LIST[nakshatraIndex],
      paya: payaForMoonHouse(moonHouse),
      tatwa: TATWA_BY_SIGN[moonSignIdx]
    },
    d9Navamsha: {
      ascendant: ZODIAC_SIGNS[d9AscendantIndex],
      planetaryPositions: d9Planets
    },
    d10Dasamsha: {
      ascendant: ZODIAC_SIGNS[d10AscendantIndex],
      planetaryPositions: d10Planets
    },
    houses,
    dashaInfo
  };
}

async function calculateKundliWithAI(dob, tob, placeOfBirth, latitude, longitude, birthDetails = {}, timezone) {
  const kundli = calculateKundli(dob, tob, placeOfBirth, latitude, longitude, timezone, {
    birthTimeKnown: birthDetails.birthTimeKnown
  });
  try {
    kundli.aiReport = await generateAIKundliReport(kundli, birthDetails);
  } catch (e) {
    console.error('AI report pre-generation error:', e && e.message ? e.message : e);
    kundli.aiReport = buildFallbackKundliReport(kundli);
  }
  return kundli;
}

function buildFallbackKundliReport(k) {
  const d = k.dashaInfo || {};
  return `### Personality & Core Nature
Born with **${k.ascendant} Ascendant**, **Moon in ${k.moonSign}** and **${k.nakshatra} Nakshatra (Pada ${k.nakshatraPada})**. The Lagna lord is **${SIGN_LORDS[ZODIAC_SIGNS.indexOf(k.ascendant)] || 'N/A'}** and the Moon sign lord is **${SIGN_LORDS[ZODIAC_SIGNS.indexOf(k.moonSign)] || 'N/A'}**; their placements describe your temperament and emotional nature.

### Physical Traits & Vitality
Your **${k.ascendant} Lagna** shapes physical constitution and outward demeanour, while the **${k.avakhada?.tatwa || 'N/A'} Tatwa** of the Moon sign indicates your dominant element.

### Health & Wellness Outlook
With **${k.avakhada?.gana || 'N/A'} Gana** and **${k.avakhada?.nadi || 'N/A'} Nadi**, regular routines, adequate rest and steady discipline support well-being.

### Career, Wealth & Professional Success
Your **D10 Dasamsha Lagna is ${k.d10Dasamsha?.ascendant || 'N/A'}**. Study the 10th house and its lord in both D1 and D10 for career direction.

### Marriage, Relationships & Life Partner
Your **D9 Navamsha Lagna is ${k.d9Navamsha?.ascendant || 'N/A'}**. The 7th house of D1 and the Navamsha together describe partnership themes.

### Understanding of Active Dasha Period
You are running **${d.currentMahadasha || 'N/A'} Mahadasha** (until ${d.dashaEndDate || 'N/A'}) with **${d.antardasha || 'N/A'} Antardasha** (until ${d.antardashaEndDate || 'N/A'}). Results depend on the placement and strength of these lords in your chart.

### Final Summary & Guidance
Consistent effort, ethical conduct and patience allow the supportive factors in your chart to manifest. For a detailed personal reading, consult an experienced astrologer.`;
}

async function generateAIKundliReport(kundliData, birthDetails = {}) {
  const k = kundliData || {};
  const fullName = birthDetails.fullName || 'Seeker';

  const planetsSummary = (Array.isArray(k.planetaryPositions) ? k.planetaryPositions : [])
    .map((p) => `- ${p.name}: ${p.sign} (House ${p.house}, ${p.degree}°, ${p.speed || 'Direct'}) | Nakshatra: ${p.nakshatra || 'N/A'} (Pada ${p.nakshatraPada || 'N/A'})`)
    .join('\n');

  const prompt = `Generate a structured Vedic astrology (Jyotish) Kundli interpretation for ${fullName} using ONLY the computed data below (sidereal, Lahiri ayanamsa).

CHART DATA:
${k.birthTime && k.birthTime.known === false ? `- IMPORTANT: Birth time is UNKNOWN (noon assumed). Do NOT interpret the Ascendant, house placements, D9/D10 Lagna or house-based yogas; base the reading on the Moon sign (Chandra Lagna), planet signs, nakshatras and dasha only, and say so briefly.${k.birthTime.moonSignCertain ? '' : ` The Moon may be in ${k.birthTime.possibleMoonSigns.join(' or ')} depending on the exact time.`}
` : ''}- Ascendant (D1 Lagna): ${k.ascendant}
- Sun Sign: ${k.sunSign}
- Moon Sign: ${k.moonSign}
- Nakshatra: ${k.nakshatra} (Pada ${k.nakshatraPada})
- Birth Panchang: Tithi ${k.panchang?.tithi}, Vaar ${k.panchang?.vaar}, Yoga ${k.panchang?.yoga}, Karana ${k.panchang?.karana}
- Avakhada: Gana ${k.avakhada?.gana}, Nadi ${k.avakhada?.nadi}, Yoni ${k.avakhada?.yoni}, Varna ${k.avakhada?.varna}, Tatwa ${k.avakhada?.tatwa}, Paya ${k.avakhada?.paya}

D1 PLANETS:
${planetsSummary || '- not available'}

D9 Navamsha Lagna: ${k.d9Navamsha?.ascendant}
D10 Dasamsha Lagna: ${k.d10Dasamsha?.ascendant}

VIMSHOTTARI DASHA:
- Mahadasha: ${k.dashaInfo?.currentMahadasha} (ends ${k.dashaInfo?.dashaEndDate})
- Antardasha: ${k.dashaInfo?.antardasha} (ends ${k.dashaInfo?.antardashaEndDate || 'N/A'})

Write in Markdown with these "###" sections: Personality & Core Nature; Physical Traits & Vitality; Health & Wellness Outlook; Career, Wealth & Professional Success; Marriage, Relationships & Life Partner; Understanding of Active Dasha Period; Final Summary & Guidance.
Ground every statement in the placements above, be balanced and realistic, avoid fear-mongering, medical or financial guarantees.`;

  const ai = await chatCompletion({
    messages: [
      { role: 'system', content: 'You are an experienced, ethical Vedic astrologer producing clear Kundli interpretations.' },
      { role: 'user', content: prompt }
    ],
    temperature: 0.6,
    maxTokens: 1400,
    timeoutMs: 30000
  });

  return ai || buildFallbackKundliReport(k);
}

// ---------------------------------------------------------------------------
// Sun/Moon rise & set, daily Panchang, Hora, Moon phase
// ---------------------------------------------------------------------------

function riseSet(jdStartUt, body, kind, lat, lon) {
  const rsmi = kind === 'rise' ? C.SE_CALC_RISE : C.SE_CALC_SET;
  try {
    const res = sweph.rise_trans(jdStartUt, body, null, EPHE_FLAG, rsmi, [lon, lat, 0], 1013.25, 15);
    if (!res || res.flag < 0 || typeof res.data !== 'number') return NaN;
    return res.data;
  } catch (_) {
    return NaN;
  }
}

function sunMoonAt(jd) {
  return { sun: calcBody(jd, C.SE_SUN).long, moon: calcBody(jd, C.SE_MOON).long };
}

function muhuratWindow(startMs, endMs, tzDesc) {
  return `${formatClock(startMs, tzDesc)} - ${formatClock(endMs, tzDesc)}`;
}

/**
 * Real daily Panchang for a local date at a location (defaults: New Delhi, IST).
 * Tithi/Nakshatra/Yoga/Karana are evaluated at local sunrise (traditional convention).
 */
function calculateDailyPanchangAndMuhurats(dateStr, lat = DEFAULT_LAT, lng = DEFAULT_LON, timezone = DEFAULT_TIMEZONE) {
  const tzDesc = resolveTimeZone(timezone);
  const latN = parseCoordinate(lat, DEFAULT_LAT, -66, 66, 'lat');
  const lonN = parseCoordinate(lng, DEFAULT_LON, -180, 180, 'lng');
  const dateISO = dateStr || todayISO(timezone);
  const { year, month, day } = parseDateParts(dateISO, 'date');
  const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay();

  const midnightUtc = localToUtcMs(year, month, day, 0, 0, 0, tzDesc);
  const jdMidnight = julianDayFromUtcMs(midnightUtc);

  const jdSunrise = riseSet(jdMidnight, C.SE_SUN, 'rise', latN, lonN);
  const jdSunset = riseSet(Number.isFinite(jdSunrise) ? jdSunrise : jdMidnight, C.SE_SUN, 'set', latN, lonN);
  const jdMoonrise = riseSet(jdMidnight, C.SE_MOON, 'rise', latN, lonN);
  const jdMoonset = riseSet(jdMidnight, C.SE_MOON, 'set', latN, lonN);

  const sunriseMs = Number.isFinite(jdSunrise) ? utcMsFromJulianDay(jdSunrise) : midnightUtc + 6 * 3600000;
  const sunsetMs = Number.isFinite(jdSunset) ? utcMsFromJulianDay(jdSunset) : midnightUtc + 18 * 3600000;
  const dayLen = sunsetMs - sunriseMs;
  const part = dayLen / 8;

  const pos = sunMoonAt(Number.isFinite(jdSunrise) ? jdSunrise : jdMidnight + 0.25);
  const pe = panchangElements(pos.sun, pos.moon);

  // 1-based eighth-of-day segment for each weekday (Sunday first)
  const RAHU_SEG = [8, 2, 7, 5, 6, 4, 3];
  const YAMA_SEG = [5, 4, 3, 2, 1, 7, 6];
  const GULIKA_SEG = [7, 6, 5, 4, 3, 2, 1];
  const seg = (n) => [sunriseMs + (n - 1) * part, sunriseMs + n * part];

  const rahu = seg(RAHU_SEG[weekday]);
  const yama = seg(YAMA_SEG[weekday]);
  const gulika = seg(GULIKA_SEG[weekday]);

  const midday = (sunriseMs + sunsetMs) / 2;
  const muhurta = dayLen / 15;

  const CHOGHADIYA_CYCLE = [
    { name: 'Udveg (Anxiety)', status: 'Avoid' },
    { name: 'Char (Neutral)', status: 'Neutral' },
    { name: 'Labh (Gain)', status: 'Auspicious' },
    { name: 'Amrit (Best)', status: 'Best' },
    { name: 'Kaal (Loss)', status: 'Avoid' },
    { name: 'Shubh (Auspicious)', status: 'Auspicious' },
    { name: 'Rog (Sickness)', status: 'Avoid' }
  ];
  const CHOGHADIYA_START = [0, 3, 6, 2, 5, 1, 4]; // Sun..Sat
  const choghadiya = [];
  for (let i = 0; i < 8; i++) {
    const c = CHOGHADIYA_CYCLE[(CHOGHADIYA_START[weekday] + i) % 7];
    const [s, e] = seg(i + 1);
    choghadiya.push({ name: c.name, time: muhuratWindow(s, e, tzDesc), status: c.status });
  }

  return {
    date: dateISO,
    vaar: WEEKDAYS[weekday],
    tithi: pe.tithi,
    paksha: pe.paksha,
    nakshatra: pe.nakshatra,
    yoga: pe.yoga,
    karana: pe.karana,
    sunrise: formatClock(sunriseMs, tzDesc),
    sunset: formatClock(sunsetMs, tzDesc),
    moonrise: Number.isFinite(jdMoonrise) ? formatClock(utcMsFromJulianDay(jdMoonrise), tzDesc) : '--',
    moonset: Number.isFinite(jdMoonset) ? formatClock(utcMsFromJulianDay(jdMoonset), tzDesc) : '--',
    rahuKaal: muhuratWindow(rahu[0], rahu[1], tzDesc),
    yamaganda: muhuratWindow(yama[0], yama[1], tzDesc),
    gulikaKaal: muhuratWindow(gulika[0], gulika[1], tzDesc),
    abhijitMuhurat: muhuratWindow(midday - muhurta / 2, midday + muhurta / 2, tzDesc),
    choghadiya,
    location: { latitude: latN, longitude: lonN, timezone: tzDesc.type === 'iana' ? tzDesc.zone : tzDesc.minutes }
  };
}

const HORA_MEANINGS = {
  Sun: 'Vitality, leadership, authority, and dealings with government or seniors.',
  Moon: 'Emotions, travel, public dealings, and nurturing activities.',
  Mars: 'Courage, physical effort, competition, property and technical work.',
  Mercury: 'Intellectual work, writing, trade, and strategic communication.',
  Jupiter: 'Expansion, wealth, learning, spiritual practice, and auspicious beginnings.',
  Venus: 'Beauty, harmony, relationships, arts, and luxury purchases.',
  Saturn: 'Discipline, hard work, long-term tasks, and service; avoid new ventures.'
};
const CHALDEAN = ['Sun', 'Venus', 'Mercury', 'Moon', 'Saturn', 'Jupiter', 'Mars'];

function calculateCurrentHora(nowMs = Date.now(), lat = DEFAULT_LAT, lng = DEFAULT_LON, timezone = DEFAULT_TIMEZONE) {
  const tzDesc = resolveTimeZone(timezone);
  const local = utcToLocalParts(nowMs, tzDesc);
  const sunriseOn = (y, m, d) => {
    const mid = localToUtcMs(y, m, d, 0, 0, 0, tzDesc);
    const jd = riseSet(julianDayFromUtcMs(mid), C.SE_SUN, 'rise', lat, lng);
    return Number.isFinite(jd) ? utcMsFromJulianDay(jd) : mid + 6 * 3600000;
  };
  const shiftDay = (y, m, d, delta) => {
    const dt = new Date(Date.UTC(y, m - 1, d + delta));
    return [dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate()];
  };

  let [y, m, d] = [local.year, local.month, local.day];
  let sunrise = sunriseOn(y, m, d);
  if (nowMs < sunrise) {
    [y, m, d] = shiftDay(y, m, d, -1);
    sunrise = sunriseOn(y, m, d);
  }
  const [ny, nm, nd] = shiftDay(y, m, d, 1);
  const nextSunrise = sunriseOn(ny, nm, nd);
  const jdSet = riseSet(julianDayFromUtcMs(sunrise), C.SE_SUN, 'set', lat, lng);
  const sunset = Number.isFinite(jdSet) ? utcMsFromJulianDay(jdSet) : sunrise + 12 * 3600000;

  const weekday = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  let index;
  let start;
  let end;
  if (nowMs < sunset) {
    const len = (sunset - sunrise) / 12;
    index = Math.min(11, Math.floor((nowMs - sunrise) / len));
    start = sunrise + index * len;
    end = start + len;
  } else {
    const len = (nextSunrise - sunset) / 12;
    const n = Math.min(11, Math.floor((nowMs - sunset) / len));
    index = 12 + n;
    start = sunset + n * len;
    end = start + len;
  }
  const startIdx = CHALDEAN.indexOf(WEEKDAY_LORDS[weekday]);
  const planet = CHALDEAN[(startIdx + index) % 7];

  return {
    planet,
    symbol: PLANET_GLYPHS[planet],
    meaning: HORA_MEANINGS[planet],
    startTime: formatClock(start, tzDesc),
    endTime: formatClock(end, tzDesc),
    isDayHora: index < 12
  };
}

function moonElongationAt(jd) {
  const sun = calcBody(jd, C.SE_SUN, TROPICAL_FLAGS).long;
  const moon = calcBody(jd, C.SE_MOON, TROPICAL_FLAGS).long;
  return norm360(moon - sun);
}

function calculateMoonPhase(nowMs = Date.now(), timezone = DEFAULT_TIMEZONE) {
  const tzDesc = resolveTimeZone(timezone);
  const jd = julianDayFromUtcMs(nowMs);
  const elong = moonElongationAt(jd);
  const illumination = Math.round(((1 - Math.cos((elong * Math.PI) / 180)) / 2) * 100);
  const SYNODIC = 29.530588;
  const ageDays = (elong / 360) * SYNODIC;

  const PHASES = ['New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
    'Full Moon', 'Waning Gibbous', 'Third Quarter', 'Waning Crescent'];
  const phase = PHASES[Math.floor(norm360(elong + 22.5) / 45) % 8];

  // Next full moon: iterate on elongation reaching 180°
  let jdFull = jd + (norm360(180 - elong) / 360) * SYNODIC;
  for (let i = 0; i < 6; i++) {
    let diff = moonElongationAt(jdFull) - 180;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    jdFull -= diff / 12.19; // mean relative daily motion of Moon vs Sun
  }
  const fullParts = utcToLocalParts(utcMsFromJulianDay(jdFull), tzDesc);
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  const moonSid = calcBody(jd, C.SE_MOON).long;
  const nakIdx = Math.floor(moonSid / NAKSHATRA_SPAN) % 27;

  return {
    phase,
    illumination,
    ageDays,
    moonSign: ZODIAC_SIGNS[signIndexOf(moonSid)],
    nakshatra: NAKSHATRAS[nakIdx],
    fullMoonDate: `${fullParts.day} ${MONTHS[fullParts.month - 1]}`,
    fullMoonISO: `${fullParts.year}-${pad2(fullParts.month)}-${pad2(fullParts.day)}`
  };
}

// ---------------------------------------------------------------------------
// Transits (AstroPulse)
// ---------------------------------------------------------------------------

const ASPECTS = [
  { angle: 0, short: 'Conj', name: 'conjunct', glyph: '☌', nature: 'neutral' },
  { angle: 60, short: 'Sext', name: 'sextile', glyph: '✶', nature: 'harmonious' },
  { angle: 90, short: 'Squa', name: 'square', glyph: '□', nature: 'challenging' },
  { angle: 120, short: 'Trin', name: 'trine', glyph: '△', nature: 'harmonious' },
  { angle: 180, short: 'Oppo', name: 'opposite', glyph: '☍', nature: 'challenging' }
];

function natalLongitude(p) {
  if (Number.isFinite(Number(p.longitude))) return Number(p.longitude);
  const sIdx = ZODIAC_SIGNS.indexOf(p.sign);
  const deg = Number(p.degree);
  if (sIdx < 0 || !Number.isFinite(deg)) return NaN;
  return sIdx * 30 + deg;
}

/** Real transit-to-natal aspects for today, tightest first. */
function calculateTransitAspects(natalPlanets, nowMs = Date.now(), maxOrb = 3) {
  const jd = julianDayFromUtcMs(nowMs);
  const transitBodies = PLANET_CONFIG.filter((p) => !p.name.startsWith('Rahu'));
  const transits = transitBodies.map((p) => ({ name: baseName(p.name), ...calcBody(jd, p.id) }));
  const natal = (Array.isArray(natalPlanets) ? natalPlanets : [])
    .map((p) => ({ name: baseName(p.name || p.planet), long: natalLongitude(p) }))
    .filter((p) => p.name && Number.isFinite(p.long));

  const found = [];
  for (const t of transits) {
    for (const n of natal) {
      const diff = Math.abs(norm360(t.long - n.long));
      const sep = diff > 180 ? 360 - diff : diff;
      for (const a of ASPECTS) {
        const orb = Math.abs(sep - a.angle);
        const allowed = t.name === 'Moon' ? maxOrb + 2 : maxOrb;
        if (orb <= allowed) {
          found.push({
            title: `${t.name} ${a.name} ${n.name}`,
            aspect: `${PLANET_GLYPHS[t.name] || ''} ${a.glyph} ${PLANET_GLYPHS[n.name] || ''}`.trim(),
            transitPlanet: t.name,
            natalPlanet: n.name,
            type: a.short,
            nature: a.nature,
            orb: parseFloat(orb.toFixed(2))
          });
        }
      }
    }
  }
  found.sort((a, b) => a.orb - b.orb);
  const currentPositions = transits.map((t) => ({ name: t.name, sign: ZODIAC_SIGNS[signIndexOf(t.long)], degree: degInSign(t.long) }));
  return { aspects: found, currentPositions };
}

// ---------------------------------------------------------------------------
// Ashtakoot Guna Milan
// ---------------------------------------------------------------------------

const PLANET_FRIENDS = {
  Sun: { friends: ['Moon', 'Mars', 'Jupiter'], enemies: ['Venus', 'Saturn'] },
  Moon: { friends: ['Sun', 'Mercury'], enemies: [] },
  Mars: { friends: ['Sun', 'Moon', 'Jupiter'], enemies: ['Mercury'] },
  Mercury: { friends: ['Sun', 'Venus'], enemies: ['Moon'] },
  Jupiter: { friends: ['Sun', 'Moon', 'Mars'], enemies: ['Mercury', 'Venus'] },
  Venus: { friends: ['Mercury', 'Saturn'], enemies: ['Sun', 'Moon'] },
  Saturn: { friends: ['Mercury', 'Venus'], enemies: ['Sun', 'Moon', 'Mars'] }
};

function relation(a, b) {
  if (a === b) return 'F';
  const r = PLANET_FRIENDS[a];
  if (r.friends.includes(b)) return 'F';
  if (r.enemies.includes(b)) return 'E';
  return 'N';
}

const YONI_ORDER = ['Horse', 'Elephant', 'Sheep', 'Serpent', 'Dog', 'Cat', 'Rat', 'Cow', 'Buffalo', 'Tiger', 'Deer', 'Monkey', 'Mongoose', 'Lion'];
const YONI_MATRIX = [
  [4, 2, 2, 3, 2, 2, 2, 1, 0, 1, 3, 3, 2, 1],
  [2, 4, 3, 3, 2, 2, 2, 2, 3, 1, 2, 3, 2, 0],
  [2, 3, 4, 2, 1, 2, 1, 3, 3, 1, 2, 0, 3, 1],
  [3, 3, 2, 4, 2, 1, 1, 1, 1, 2, 2, 2, 0, 2],
  [2, 2, 1, 2, 4, 2, 1, 2, 2, 1, 0, 2, 1, 1],
  [2, 2, 2, 1, 2, 4, 0, 2, 2, 1, 3, 3, 2, 1],
  [2, 2, 1, 1, 1, 0, 4, 2, 2, 2, 2, 2, 1, 2],
  [1, 2, 3, 1, 2, 2, 2, 4, 3, 0, 3, 2, 2, 1],
  [0, 3, 3, 1, 2, 2, 2, 3, 4, 1, 2, 2, 2, 1],
  [1, 1, 1, 2, 1, 1, 2, 0, 1, 4, 1, 1, 2, 1],
  [3, 2, 2, 2, 0, 3, 2, 3, 2, 1, 4, 2, 2, 1],
  [3, 3, 0, 2, 2, 3, 2, 2, 2, 1, 2, 4, 3, 2],
  [2, 2, 3, 0, 1, 2, 1, 2, 2, 2, 2, 3, 4, 2],
  [1, 0, 1, 2, 1, 1, 2, 1, 1, 1, 1, 2, 2, 4]
];
const VASHYA_ORDER = ['Chatushpada', 'Manav', 'Jalchar', 'Vanchar', 'Keet'];
// rows: boy, cols: girl
const VASHYA_MATRIX = [
  [2, 1, 1, 0.5, 1],
  [1, 2, 0.5, 0, 1],
  [1, 0.5, 2, 1, 1],
  [0.5, 0, 1, 2, 0],
  [1, 1, 1, 0, 2]
];
const VARNA_RANK = { Brahmin: 4, Kshatriya: 3, Vaishya: 2, Shudra: 1 };
const GANA_ORDER = ['Deva', 'Manushya', 'Rakshasa'];
const GANA_MATRIX = [ // rows boy, cols girl
  [6, 6, 0],
  [5, 6, 0],
  [1, 0, 6]
];

/**
 * @param {{moonLongitude?:number, moonSign:string, nakshatra:string}} boy
 * @param {{moonLongitude?:number, moonSign:string, nakshatra:string}} girl
 */
function calculateAshtakoot(boy, girl) {
  const prep = (p) => {
    const nakIdx = Number.isFinite(Number(p.moonLongitude))
      ? Math.floor(norm360(Number(p.moonLongitude)) / NAKSHATRA_SPAN) % 27
      : NAKSHATRAS.indexOf(p.nakshatra);
    const signIdx = Number.isFinite(Number(p.moonLongitude))
      ? signIndexOf(Number(p.moonLongitude))
      : ZODIAC_SIGNS.indexOf(p.moonSign);
    if (nakIdx < 0 || signIdx < 0) throw new AstrologyInputError('Moon sign / nakshatra unavailable for Guna Milan');
    const long = Number.isFinite(Number(p.moonLongitude)) ? Number(p.moonLongitude) : signIdx * 30 + 7.5;
    return { nakIdx, signIdx, vashya: vashyaForLongitude(long) };
  };
  const b = prep(boy);
  const g = prep(girl);

  const kootas = [];

  // 1. Varna
  const bVarna = VARNA_BY_SIGN[b.signIdx];
  const gVarna = VARNA_BY_SIGN[g.signIdx];
  const varna = VARNA_RANK[bVarna] >= VARNA_RANK[gVarna] ? 1 : 0;
  kootas.push({ name: 'Varna', score: varna, max: 1, meaning: 'Work & Ego Alignment', verdict: `${bVarna} / ${gVarna}` });

  // 2. Vashya
  const vashya = VASHYA_MATRIX[VASHYA_ORDER.indexOf(b.vashya)][VASHYA_ORDER.indexOf(g.vashya)];
  kootas.push({ name: 'Vashya', score: vashya, max: 2, meaning: 'Mutual Influence & Control', verdict: `${b.vashya} / ${g.vashya}` });

  // 3. Tara
  const taraOk = (from, to) => {
    const rem = (((to - from + 27) % 27) + 1) % 9;
    return ![3, 5, 7].includes(rem);
  };
  const t1 = taraOk(g.nakIdx, b.nakIdx);
  const t2 = taraOk(b.nakIdx, g.nakIdx);
  const tara = (t1 ? 1.5 : 0) + (t2 ? 1.5 : 0);
  kootas.push({ name: 'Tara', score: tara, max: 3, meaning: 'Destiny & Astral Luck', verdict: tara === 3 ? 'Auspicious Tara both ways' : tara === 0 ? 'Inauspicious Tara' : 'Partially auspicious Tara' });

  // 4. Yoni
  const bYoni = YONI_LIST[b.nakIdx];
  const gYoni = YONI_LIST[g.nakIdx];
  const yoni = YONI_MATRIX[YONI_ORDER.indexOf(bYoni)][YONI_ORDER.indexOf(gYoni)];
  kootas.push({ name: 'Yoni', score: yoni, max: 4, meaning: 'Physical & Intimate Affinity', verdict: `${bYoni} / ${gYoni}` });

  // 5. Graha Maitri
  const bLord = SIGN_LORDS[b.signIdx];
  const gLord = SIGN_LORDS[g.signIdx];
  const r1 = relation(bLord, gLord);
  const r2 = relation(gLord, bLord);
  const pair = [r1, r2].sort().join('');
  const maitriTable = { FF: 5, FN: 4, NN: 3, EF: 1, EN: 0.5, EE: 0 };
  const maitri = bLord === gLord ? 5 : maitriTable[pair];
  kootas.push({ name: 'Maitri', score: maitri, max: 5, meaning: 'Intellectual Friendship', verdict: `${bLord} / ${gLord}` });

  // 6. Gana
  const bGana = GANA_LIST[b.nakIdx];
  const gGana = GANA_LIST[g.nakIdx];
  const gana = GANA_MATRIX[GANA_ORDER.indexOf(bGana)][GANA_ORDER.indexOf(gGana)];
  kootas.push({ name: 'Gana', score: gana, max: 6, meaning: 'Behavior & Temperament', verdict: `${bGana} / ${gGana}` });

  // 7. Bhakoot
  const dist = ((b.signIdx - g.signIdx + 12) % 12) + 1;
  const bhakootDosha = [2, 12, 5, 9, 6, 8].includes(dist);
  const bhakoot = bhakootDosha ? 0 : 7;
  const axis = `${dist}/${((g.signIdx - b.signIdx + 12) % 12) + 1}`;
  kootas.push({ name: 'Bhakoot', score: bhakoot, max: 7, meaning: 'Emotional & Financial Growth', verdict: bhakootDosha ? `Bhakoot Dosha (${axis})` : `No Bhakoot Dosha (${axis})` });

  // 8. Nadi
  const bNadi = NADI_LIST[b.nakIdx];
  const gNadi = NADI_LIST[g.nakIdx];
  const nadiDosha = bNadi === gNadi;
  const nadi = nadiDosha ? 0 : 8;
  kootas.push({ name: 'Nadi', score: nadi, max: 8, meaning: 'Genetics, Health & Progeny', verdict: nadiDosha ? `Nadi Dosha (both ${bNadi})` : `No Nadi Dosha (${bNadi} / ${gNadi})` });

  const total = kootas.reduce((s, k) => s + k.score, 0);
  return { kootas, total, bhakootDosha, nadiDosha, axis, bNadi, gNadi };
}

function manglikStatus(planets) {
  const mars = (Array.isArray(planets) ? planets : []).find((p) => baseName(p.name || p.planet) === 'Mars');
  if (!mars || !mars.house) return { status: 'Unknown', house: null };
  const h = Number(mars.house);
  return { status: [1, 2, 4, 7, 8, 12].includes(h) ? 'Manglik' : 'Non-Manglik', house: h };
}

/**
 * Charts stored before the full payload was persisted lack D9/D10, panchang, avakhada etc.
 * Recompute them from the stored birth details (timezone from the row, else from the coordinates).
 * Returns null when not possible.
 */
function recomputeLegacyKundli(row) {
  if (!row || !row.date_of_birth || !row.time_of_birth) return null;
  try {
    return calculateKundli(String(row.date_of_birth), String(row.time_of_birth), row.place_of_birth || '',
      row.latitude, row.longitude, row.timezone || undefined);
  } catch (_) {
    return null;
  }
}

module.exports = {
  AstrologyInputError,
  recomputeLegacyKundli,
  calculateKundli,
  calculateKundliWithAI,
  generateAIKundliReport,
  buildFallbackKundliReport,
  calculateDailyPanchangAndMuhurats,
  calculateCurrentHora,
  calculateMoonPhase,
  calculateTransitAspects,
  calculateAshtakoot,
  manglikStatus,
  computeVimshottari,
  refreshDashaInfo,
  resolveTimeZone,
  timezoneForLocation,
  getNavamshaSignIndex,
  getDasamshaSignIndex,
  todayISO,
  parseDateParts,
  parseTimeParts,
  ZODIAC_SIGNS,
  NAKSHATRAS,
  DEFAULT_TIMEZONE,
  // Low-level helpers reused by the personal forecast engine (services/forecast_service.js)
  calcBody,
  riseSet,
  localToUtcMs,
  utcToLocalParts,
  offsetMinutesAt,
  julianDayFromUtcMs,
  utcMsFromJulianDay,
  formatClock,
  panchangElements,
  natalLongitude,
  SIGN_LORDS,
  NAKSHATRA_LORDS,
  DASHA_PERIODS,
  WEEKDAYS,
  WEEKDAY_LORDS,
  CHALDEAN,
  NAKSHATRA_SPAN,
  SIDEREAL_FLAGS,
  EPHE_FLAG
};
