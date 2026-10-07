// Personal Vedic forecast engine (deterministic).
//
// Inputs: a stored Kundli (natal Moon, Lagna, planet longitudes, birth UTC) and a date range.
// Outputs: day / week / month / timeline payloads that follow the shared API contract
// (see forecast_contract.md in the project notes):
//   - transits of the 9 grahas with classical Gochara results counted from the natal Moon (with Vedha)
//   - Tara Bala, Chandra Bala, Chandrashtama
//   - Vimshottari Maha / Antar / Pratyantar dasha
//   - Sade Sati, Ashtama / Kantaka Shani, Jupiter and Rahu-Ketu periods
//   - events: ingresses, stations, eclipses, lunations, Ekadashi, Sankranti, festivals, dasha changes
//   - explainable 0-100 life-area scores
// All astronomy comes from Swiss Ephemeris (Moshier, Lahiri) via astrology_service helpers.
// Rahu/Ketu use the MEAN node here so sign ingress dates are clean single crossings
// (the true node oscillates and can cross a sign boundary several times).

'use strict';

const crypto = require('crypto');
const sweph = require('sweph');
const A = require('./astrology_service');
const I = require('./forecast_interpretations');
const { chatCompletion, hasOpenAIKey } = require('./openai_client');

const C = sweph.constants;
const ENGINE_VERSION = 'f1';
const DAY_MS = 86400000;
const YEAR_MS = 365.25 * DAY_MS;
const NAK_SPAN = 360 / 27;
const SIGNS = A.ZODIAC_SIGNS;
const NAKS = A.NAKSHATRAS;
const ORD = I.ORD;

const PLANETS = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];
const TRANSIT_ORDER = ['Saturn', 'Jupiter', 'Rahu', 'Ketu', 'Mars', 'Sun', 'Venus', 'Mercury', 'Moon'];
const BODY = {
  Sun: C.SE_SUN, Moon: C.SE_MOON, Mars: C.SE_MARS, Mercury: C.SE_MERCURY,
  Jupiter: C.SE_JUPITER, Venus: C.SE_VENUS, Saturn: C.SE_SATURN, Rahu: C.SE_MEAN_NODE
};
// [search step in days, max search window in days] for sign entry/exit searches
const SPAN_CFG = {
  Moon: [0.1, 4], Sun: [1, 40], Mercury: [0.5, 160], Venus: [1, 180], Mars: [1, 270],
  Jupiter: [2, 500], Saturn: [4, 1100], Rahu: [4, 700], Ketu: [4, 700]
};
const AMANTA_MONTHS = ['Chaitra', 'Vaishakha', 'Jyeshtha', 'Ashadha', 'Shravana', 'Bhadrapada',
  'Ashwin', 'Kartika', 'Margashirsha', 'Pausha', 'Magha', 'Phalguna'];
const SANKRANTI_NAMES = ['Mesha', 'Vrishabha', 'Mithuna', 'Karka', 'Simha', 'Kanya', 'Tula',
  'Vrishchika', 'Dhanu', 'Makar', 'Kumbha', 'Meena'];
const EKADASHI_NAMES = {
  // amanta month index -> [Shukla, Krishna]
  0: ['Kamada', 'Varuthini'], 1: ['Mohini', 'Apara'], 2: ['Nirjala', 'Yogini'], 3: ['Devshayani', 'Kamika'],
  4: ['Shravana Putrada', 'Aja'], 5: ['Parsva (Parivartini)', 'Indira'], 6: ['Papankusha', 'Rama'],
  7: ['Devutthana (Prabodhini)', 'Utpanna'], 8: ['Mokshada', 'Saphala'], 9: ['Pausha Putrada', 'Shattila'],
  10: ['Jaya', 'Vijaya'], 11: ['Amalaki', 'Papmochani']
};
// Festivals derived from amanta lunar month + tithi at the traditional time of day (kaal)
const FESTIVALS = [
  { name: 'Vasant Panchami', month: 10, tithi: 5, kaal: 'sunrise' },
  { name: 'Maha Shivaratri', month: 10, tithi: 29, kaal: 'nishita' },
  { name: 'Chaitra Navratri / Ugadi / Gudi Padwa', month: 0, tithi: 1, kaal: 'sunrise' },
  { name: 'Ram Navami', month: 0, tithi: 9, kaal: 'madhyahna' },
  { name: 'Hanuman Jayanti', month: 0, tithi: 15, kaal: 'sunrise' },
  { name: 'Akshaya Tritiya', month: 1, tithi: 3, kaal: 'sunrise' },
  { name: 'Guru Purnima', month: 3, tithi: 15, kaal: 'sunrise' },
  { name: 'Raksha Bandhan', month: 4, tithi: 15, kaal: 'sunrise' },
  { name: 'Krishna Janmashtami', month: 4, tithi: 23, kaal: 'sunrise' },
  { name: 'Ganesh Chaturthi', month: 5, tithi: 4, kaal: 'madhyahna' },
  { name: 'Sharad Navratri begins', month: 6, tithi: 1, kaal: 'sunrise' },
  { name: 'Dussehra (Vijayadashami)', month: 6, tithi: 10, kaal: 'aparahna' },
  { name: 'Dhanteras', month: 6, tithi: 28, kaal: 'pradosh' },
  { name: 'Diwali (Lakshmi Puja)', month: 6, tithi: 30, kaal: 'pradosh' }
];
const MAJOR_FESTIVALS = new Set(['Maha Shivaratri', 'Holi', 'Diwali (Lakshmi Puja)', 'Krishna Janmashtami',
  'Ram Navami', 'Sharad Navratri begins', 'Dussehra (Vijayadashami)', 'Ganesh Chaturthi', 'Chaitra Navratri / Ugadi / Gudi Padwa']);

const EXALT = { Sun: 0, Moon: 1, Mars: 9, Mercury: 5, Jupiter: 3, Venus: 11, Saturn: 6, Rahu: 1, Ketu: 7 };
const BENEFICS = ['Jupiter', 'Venus', 'Mercury', 'Moon'];

// Scoring model -------------------------------------------------------------
const AREAS = ['career', 'love', 'money', 'health', 'mind'];
const AREA_HOUSES = { career: [10, 6, 11, 1], love: [5, 7, 11], money: [2, 11, 9], health: [1, 6, 8, 12], mind: [4, 1] };
const AREA_KARAKAS = {
  career: ['Sun', 'Saturn', 'Jupiter', 'Mercury', 'Mars'],
  love: ['Venus', 'Moon', 'Jupiter', 'Mars'],
  money: ['Jupiter', 'Venus', 'Mercury'],
  health: ['Sun', 'Mars', 'Saturn', 'Moon'],
  mind: ['Moon', 'Mercury']
};
const AREA_WEIGHT = { career: 0.25, love: 0.2, money: 0.2, health: 0.15, mind: 0.2 };
// Per-planet weights: day forecasts are Moon-led; week/month "slow" layer is led by Saturn/Jupiter/nodes
const W_DAY = { Moon: 6, Sun: 3, Mercury: 2.5, Venus: 3, Mars: 3.5, Jupiter: 4.5, Saturn: 4.5, Rahu: 2.5, Ketu: 2 };
const W_SLOW = { Moon: 0, Sun: 2.5, Mercury: 2, Venus: 2.5, Mars: 3, Jupiter: 6, Saturn: 6, Rahu: 3.5, Ketu: 2.5 };
const G_VAL = { favorable: 1, neutral: 0.15, challenging: -0.6 };
const TARA_VAL = { 1: -0.5, 2: 1, 3: -1, 4: 0.8, 5: -0.8, 6: 1, 7: -1.3, 8: 0.8, 9: 1 };
const SCORE_K = 24;
// Health/mind houses (1, 4, 6, 8, 12) are mostly 'bad' houses in classical gochara; a small bias keeps their median near 50
const AREA_BIAS = { career: 0, love: 0, money: 0, health: 6, mind: 3 };

class ForecastError extends Error {
  constructor(message, status = 400, code) {
    super(message);
    this.name = 'ForecastError';
    this.statusCode = status;
    if (code) this.code = code;
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
const norm360 = (x) => ((x % 360) + 360) % 360;
const signOf = (l) => Math.floor(norm360(l) / 30) % 12;
const nakOf = (l) => Math.floor(norm360(l) / NAK_SPAN) % 27;
const houseFrom = (s, ref) => ((s - ref + 12) % 12) + 1;
const pad2 = (n) => String(n).padStart(2, '0');
const msToJd = (ms) => ms / DAY_MS + 2440587.5;
const jdToMs = (jd) => (jd - 2440587.5) * DAY_MS;
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const baseName = (n) => String(n || '').split(' ')[0];
const lc = (s) => (s ? s.charAt(0).toLowerCase() + s.slice(1) : s);
const uc = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function isoAdd(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
function isoWeekday(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}
function isoDiffDays(a, b) {
  const pa = a.split('-').map(Number);
  const pb = b.split('-').map(Number);
  return Math.round((Date.UTC(pb[0], pb[1] - 1, pb[2]) - Date.UTC(pa[0], pa[1] - 1, pa[2])) / DAY_MS);
}
function isValidIso(iso) {
  if (typeof iso !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false;
  const [y, m, d] = iso.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}
function localIso(ms, tz) {
  const p = A.utcToLocalParts(ms, tz);
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
}
function localMidnightMs(iso, tz) {
  const [y, m, d] = iso.split('-').map(Number);
  return A.localToUtcMs(y, m, d, 0, 0, 0, tz);
}
function clock(ms, tz) {
  return A.formatClock(ms, tz);
}

function pos(planet, jd) {
  if (planet === 'Ketu') {
    const r = A.calcBody(jd, BODY.Rahu);
    return { long: norm360(r.long + 180), speed: r.speed };
  }
  return A.calcBody(jd, BODY[planet]);
}
const signAt = (planet, jd) => signOf(pos(planet, jd).long);
function elongAt(jd) {
  return norm360(A.calcBody(jd, C.SE_MOON).long - A.calcBody(jd, C.SE_SUN).long);
}

// Bisection: f(lo) !== f(hi); returns the first instant (approx) where the value differs from f(lo)
function bisect(f, lo, hi, iters = 26) {
  const k0 = f(lo);
  for (let i = 0; i < iters; i++) {
    const mid = (lo + hi) / 2;
    if (f(mid) === k0) lo = mid; else hi = mid;
  }
  return hi;
}

// Sign entry (dir=-1) or exit (dir=+1) instant of `planet` around jd; null if beyond the search cap
function findSignBoundary(planet, jd, dir) {
  const [step, cap] = SPAN_CFG[planet];
  const s0 = signAt(planet, jd);
  let prev = jd;
  for (let d = step; d <= cap + step; d += step) {
    const t = jd + dir * d;
    if (signAt(planet, t) !== s0) {
      const f = (x) => signAt(planet, x) === s0;
      if (dir > 0) return bisect(f, prev, t);
      // backward: find the last instant outside the sign, entry is just after it
      return bisect(f, t, prev);
    }
    prev = t;
  }
  return null;
}

// Contiguous sign segments of `planet` covering [jdA, jdB] (first/last are extended to true entry/exit)
const segmentCache = new Map();
function signSegments(planet, jdA, jdB) {
  const key = `${planet}|${jdA.toFixed(3)}|${jdB.toFixed(3)}`;
  if (segmentCache.has(key)) return segmentCache.get(key);
  const step = SPAN_CFG[planet][0];
  const segs = [];
  let cur = signAt(planet, jdA);
  let curStart = findSignBoundary(planet, jdA, -1);
  let prev = jdA;
  for (let t = jdA + step; ; t += step) {
    const tt = Math.min(t, jdB);
    const s = signAt(planet, tt);
    if (s !== cur) {
      const c0 = cur;
      const b = bisect((x) => signAt(planet, x) === c0, prev, tt);
      segs.push({ sign: cur, start: curStart, end: b });
      cur = signAt(planet, b + 1e-6);
      curStart = b;
      // a second change inside the same step is not possible with the configured steps
    }
    prev = tt;
    if (tt >= jdB) break;
  }
  segs.push({ sign: cur, start: curStart, end: findSignBoundary(planet, jdB, 1) });
  if (segmentCache.size > 200) segmentCache.clear();
  segmentCache.set(key, segs);
  return segs;
}

// Sign changes strictly inside [jdA, jdB)
function ingressesBetween(planet, jdA, jdB) {
  const step = SPAN_CFG[planet][0];
  const out = [];
  let prev = jdA;
  let cur = signAt(planet, jdA);
  for (let t = jdA + step; ; t += step) {
    const tt = Math.min(t, jdB);
    const s = signAt(planet, tt);
    if (s !== cur) {
      const c0 = cur;
      const b = bisect((x) => signAt(planet, x) === c0, prev, tt);
      const to = signAt(planet, b + 1e-6);
      out.push({ jd: b, from: cur, to });
      cur = to;
    }
    prev = tt;
    if (tt >= jdB) break;
  }
  return out;
}

function stationsBetween(planet, jdA, jdB) {
  const step = planet === 'Mercury' ? 0.5 : 1;
  const out = [];
  const retroAt = (x) => pos(planet, x).speed < 0;
  let prev = jdA;
  let cur = retroAt(jdA);
  for (let t = jdA + step; ; t += step) {
    const tt = Math.min(t, jdB);
    const r = retroAt(tt);
    if (r !== cur) {
      const b = bisect(retroAt, prev, tt, 22);
      out.push({ jd: b, kind: r ? 'retrograde' : 'direct' });
      cur = r;
    }
    prev = tt;
    if (tt >= jdB) break;
  }
  return out;
}

// Tithi changes inside [jdA, jdB): [{ jd, tithi (1..30) that begins }]
function tithiChanges(jdA, jdB) {
  const step = 0.25;
  const tithiAt = (x) => Math.floor(elongAt(x) / 12);
  const out = [];
  let prev = jdA;
  let cur = tithiAt(jdA);
  for (let t = jdA + step; ; t += step) {
    const tt = Math.min(t, jdB);
    const k = tithiAt(tt);
    if (k !== cur) {
      const b = bisect(tithiAt, prev, tt, 24);
      const nk = tithiAt(b + 1e-6);
      out.push({ jd: b, tithi: nk + 1 });
      cur = nk;
    }
    prev = tt;
    if (tt >= jdB) break;
  }
  return out;
}

// New moons (conjunctions) in [jdA, jdB]
function newMoonsBetween(jdA, jdB) {
  const out = [];
  let prevJd = jdA;
  let prevE = elongAt(jdA);
  for (let t = jdA + 1; t <= jdB + 1; t += 1) {
    const e = elongAt(t);
    if (prevE > 270 && e < 90) {
      const b = bisect((x) => elongAt(x) > 180, prevJd, t, 26);
      out.push({ jd: b, sunSign: signOf(A.calcBody(b, C.SE_SUN).long) });
    }
    prevJd = t;
    prevE = e;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Natal facts
// ---------------------------------------------------------------------------
function dignityOf(planet, s) {
  if (EXALT[planet] === s) return 'exalted';
  if ((EXALT[planet] + 6) % 12 === s) return 'debilitated';
  if (A.SIGN_LORDS[s] === planet) return 'own sign';
  const rel = I.planetRelation(planet, A.SIGN_LORDS[s]);
  return rel === 'friend' ? 'friendly sign' : rel === 'enemy' ? 'enemy sign' : 'neutral sign';
}
const DIGNITY_VAL = { exalted: 1, 'own sign': 0.8, 'friendly sign': 0.35, 'neutral sign': 0, 'enemy sign': -0.35, debilitated: -1 };

function natalFromKundli(kundli) {
  if (!kundli || typeof kundli !== 'object') return null;
  let k = kundli;
  let moonLong = Number(k.moonLongitude);
  let birthMs = k.birthUtc ? Date.parse(k.birthUtc) : NaN;
  if (!Number.isFinite(moonLong) || !Number.isFinite(birthMs)) {
    const bd = k.birthDetails || {};
    const re = A.recomputeLegacyKundli({
      date_of_birth: bd.dateOfBirth, time_of_birth: bd.timeOfBirth, place_of_birth: bd.placeOfBirth,
      latitude: bd.latitude, longitude: bd.longitude, timezone: bd.timezone
    });
    if (!re) return null;
    k = { ...re, ...k, moonLongitude: re.moonLongitude, birthUtc: re.birthUtc, birthTime: k.birthTime || re.birthTime };
    moonLong = Number(re.moonLongitude);
    birthMs = Date.parse(re.birthUtc);
  }
  if (!Number.isFinite(moonLong) || !Number.isFinite(birthMs)) return null;
  const lagna = SIGNS.indexOf(k.ascendant);
  if (lagna < 0) return null;

  const planets = {};
  for (const p of Array.isArray(k.planetaryPositions) ? k.planetaryPositions : []) {
    const name = baseName(p.name || p.planet);
    const l = A.natalLongitude(p);
    if (PLANETS.includes(name) && Number.isFinite(l)) planets[name] = norm360(l);
  }
  planets.Moon = norm360(moonLong);
  if (Number.isFinite(planets.Rahu) && !Number.isFinite(planets.Ketu)) planets.Ketu = norm360(planets.Rahu + 180);

  const birthTimeKnown = !(k.birthTime && k.birthTime.known === false);
  const moonSign = signOf(moonLong);
  const info = {};
  for (const [p, l] of Object.entries(planets)) {
    const s = signOf(l);
    const house = houseFrom(s, birthTimeKnown ? lagna : moonSign);
    const dignity = dignityOf(p, s);
    let strength = DIGNITY_VAL[dignity] || 0;
    if ([1, 4, 5, 7, 9, 10].includes(house)) strength += 0.3;
    else if ([6, 8, 12].includes(house)) strength -= 0.4;
    else if ([2, 3, 11].includes(house)) strength += 0.1;
    info[p] = { sign: SIGNS[s], house, dignity, strength: clamp(strength, -1, 1) };
  }
  const bd = kundli.birthDetails || {};
  const lat = Number.isFinite(Number(k.latitude)) ? Number(k.latitude) : Number(bd.latitude);
  const lng = Number.isFinite(Number(k.longitude)) ? Number(k.longitude) : Number(bd.longitude);
  return {
    moonLong: norm360(moonLong),
    moonSign,
    moonNak: nakOf(moonLong),
    lagna,
    planets,
    info,
    birthMs,
    birthTimeKnown,
    houseBasis: birthTimeKnown ? 'Lagna' : 'Moon',
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null
  };
}

function kundliHash(natal, ctx) {
  const raw = JSON.stringify([ENGINE_VERSION, natal.moonLong.toFixed(4), natal.birthMs, natal.lagna,
    natal.birthTimeKnown, Number(ctx.lat).toFixed(2), Number(ctx.lng).toFixed(2)]);
  return crypto.createHash('sha1').update(raw).digest('hex').slice(0, 20);
}

/**
 * @param {object} kundli stored kundli (kundliFromRow output)
 * @param {object} opts { lat, lng, nowMs, profile: {name,isFamily,familyId,relationship} }
 */
function createContext(kundli, opts = {}) {
  const natal = natalFromKundli(kundli);
  if (!natal) throw new ForecastError('No Kundli found for this profile. Generate a Kundli first.', 409, 'NO_KUNDLI');
  const lat = Number.isFinite(opts.lat) ? opts.lat : (natal.lat ?? 28.6139);
  const lng = Number.isFinite(opts.lng) ? opts.lng : (natal.lng ?? 77.209);
  const tzName = A.timezoneForLocation(undefined, lat, lng);
  const tz = A.resolveTimeZone(tzName);
  const ctx = {
    natal, lat, lng, latRS: clamp(lat, -65.5, 65.5), tzName, tz,
    nowMs: Number.isFinite(opts.nowMs) ? opts.nowMs : Date.now(),
    profile: opts.profile || { name: (kundli.birthDetails && kundli.birthDetails.fullName) || 'You', isFamily: false, familyId: null, relationship: null },
    anchors: new Map(), days: new Map(), kaal: new Map(), newMoons: null, mdList: null
  };
  ctx.firstName = String(ctx.profile.name || '').trim().split(/\s+/)[0] || 'Friend';
  ctx.hash = kundliHash(natal, ctx);
  return ctx;
}

function todayFor(ctx) {
  return localIso(ctx.nowMs, ctx.tz);
}

// ---------------------------------------------------------------------------
// Day anchors (sunrise / sunset) and kaal times
// ---------------------------------------------------------------------------
function getAnchor(ctx, iso) {
  let a = ctx.anchors.get(iso);
  if (a) return a;
  const midnight = localMidnightMs(iso, ctx.tz);
  const jd0 = msToJd(midnight);
  let rise = A.riseSet(jd0, C.SE_SUN, 'rise', ctx.latRS, ctx.lng);
  if (!Number.isFinite(rise) || rise > jd0 + 1) rise = jd0 + 0.25;
  let set = A.riseSet(rise, C.SE_SUN, 'set', ctx.latRS, ctx.lng);
  if (!Number.isFinite(set) || set > rise + 1) set = rise + 0.5;
  a = { iso, midnightMs: midnight, sunriseJd: rise, sunsetJd: set, nextMidnightMs: localMidnightMs(isoAdd(iso, 1), ctx.tz) };
  ctx.anchors.set(iso, a);
  return a;
}

function kaalJd(ctx, iso, kaal) {
  const a = getAnchor(ctx, iso);
  switch (kaal) {
    case 'madhyahna': return (a.sunriseJd + a.sunsetJd) / 2;
    case 'aparahna': return a.sunriseJd + 0.7 * (a.sunsetJd - a.sunriseJd);
    case 'pradosh': return a.sunsetJd + 48 / 1440;
    case 'nishita': return (a.sunsetJd + getAnchor(ctx, isoAdd(iso, 1)).sunriseJd) / 2;
    default: return a.sunriseJd;
  }
}

function ensureNewMoons(ctx, jdA, jdB) {
  const nm = ctx.newMoons;
  if (nm && nm.from <= jdA - 35 && nm.to >= jdB + 35) return nm.list;
  const from = Math.min(jdA, nm ? nm.from + 35 : jdA) - 40;
  const to = Math.max(jdB, nm ? nm.to - 35 : jdB) + 40;
  ctx.newMoons = { from, to, list: newMoonsBetween(from, to) };
  return ctx.newMoons.list;
}

// Amanta lunar month for an instant: named from the Sun's sign at the preceding new moon
function lunarMonthAt(ctx, jd) {
  const list = ensureNewMoons(ctx, jd, jd);
  let i = -1;
  for (let j = 0; j < list.length; j++) if (list[j].jd <= jd) i = j;
  if (i < 0) return { month: null, adhika: false, name: null };
  const s = list[i].sunSign;
  const month = (s + 1) % 12;
  const adhika = !!(list[i + 1] && list[i + 1].sunSign === s);
  return { month, adhika, name: `${adhika ? 'Adhika ' : ''}${AMANTA_MONTHS[month]}` };
}

function kaalInfo(ctx, iso, kaal) {
  const key = `${iso}|${kaal}`;
  let v = ctx.kaal.get(key);
  if (v) return v;
  const jd = kaalJd(ctx, iso, kaal);
  const tithi = Math.floor(elongAt(jd) / 12) + 1;
  v = { jd, tithi, ...lunarMonthAt(ctx, jd) };
  ctx.kaal.set(key, v);
  return v;
}

// Days in isoList (sorted, contiguous) on which tithi T (in amanta month `month`, or any month when null)
// is observed at `kaal`; handles vriddhi (keep first day) and kshaya (tithi skipped at kaal).
function observanceDays(ctx, isoList, T, kaal, month) {
  const out = [];
  const ok = (inf) => month === null || (inf.month === month && !inf.adhika);
  const prevT = T === 1 ? 30 : T - 1;
  const nextT = T === 30 ? 1 : T + 1;
  for (let i = 0; i < isoList.length; i++) {
    const inf = kaalInfo(ctx, isoList[i], kaal);
    if (inf.tithi === T && ok(inf)) {
      if (i > 0) {
        const p = kaalInfo(ctx, isoList[i - 1], kaal);
        if (p.tithi === T && ok(p)) continue;
      }
      out.push({ iso: isoList[i], info: inf });
    } else if (inf.tithi === prevT && i + 1 < isoList.length) {
      const n = kaalInfo(ctx, isoList[i + 1], kaal);
      if (n.tithi === nextT && ok(T === 1 ? n : inf)) out.push({ iso: isoList[i], info: T === 1 ? n : inf });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Dasha (3 levels)
// ---------------------------------------------------------------------------
function mahadashaList(ctx) {
  if (ctx.mdList) return ctx.mdList;
  const { moonLong, birthMs } = ctx.natal;
  const nak = Math.floor(moonLong / NAK_SPAN) % 27;
  const startIdx = nak % 9;
  const frac = (moonLong % NAK_SPAN) / NAK_SPAN;
  const first = A.NAKSHATRA_LORDS[startIdx];
  let cursor = birthMs - A.DASHA_PERIODS[first] * frac * YEAR_MS;
  const list = [];
  for (let i = 0; i < 18; i++) {
    const lord = A.NAKSHATRA_LORDS[(startIdx + i) % 9];
    const end = cursor + A.DASHA_PERIODS[lord] * YEAR_MS;
    list.push({ lord, start: cursor, end });
    cursor = end;
  }
  ctx.mdList = list;
  return list;
}
function subPeriods(parent) {
  const idx = A.NAKSHATRA_LORDS.indexOf(parent.lord);
  const len = parent.end - parent.start;
  const out = [];
  let c = parent.start;
  for (let j = 0; j < 9; j++) {
    const lord = A.NAKSHATRA_LORDS[(idx + j) % 9];
    const end = j === 8 ? parent.end : c + (len * A.DASHA_PERIODS[lord]) / 120;
    out.push({ lord, start: c, end });
    c = end;
  }
  return out;
}
function dashaAt(ctx, ms) {
  const list = mahadashaList(ctx);
  const t = Math.max(ms, ctx.natal.birthMs);
  const md = list.find((p) => t >= p.start && t < p.end) || list[list.length - 1];
  const ads = subPeriods(md);
  const ad = ads.find((p) => t >= p.start && t < p.end) || ads[ads.length - 1];
  const pds = subPeriods(ad);
  const pd = pds.find((p) => t >= p.start && t < p.end) || pds[pds.length - 1];
  return { md, ad, pd };
}
function dashaNow(ctx, ms) {
  const d = dashaAt(ctx, ms);
  return {
    mahadasha: d.md.lord,
    antardasha: d.ad.lord,
    pratyantardasha: d.pd.lord,
    mahadashaEnds: localIso(d.md.end, ctx.tz),
    antardashaEnds: localIso(d.ad.end, ctx.tz),
    pratyantardashaEnds: localIso(d.pd.end, ctx.tz),
    theme: I.dashaTheme(d.md.lord, d.ad.lord, ctx.natal.info, ctx.natal.houseBasis)
  };
}

// ---------------------------------------------------------------------------
// Transits, Gochara, aspects
// ---------------------------------------------------------------------------
function transitsAt(ctx, jd) {
  const tr = {};
  for (const p of PLANETS) {
    const { long, speed } = pos(p, jd);
    const s = signOf(long);
    tr[p] = {
      planet: p, long, speed, sign: s, nak: nakOf(long),
      retro: p === 'Rahu' || p === 'Ketu' ? true : (p === 'Sun' || p === 'Moon' ? false : speed < 0),
      hMoon: houseFrom(s, ctx.natal.moonSign),
      hLagna: houseFrom(s, ctx.natal.lagna)
    };
  }
  applyGochara(tr);
  return tr;
}

function applyGochara(tr) {
  for (const p of PLANETS) {
    const t = tr[p];
    const good = I.GOCHARA_GOOD[p].includes(t.hMoon);
    let vedhaBy = null;
    if (good) {
      const vh = I.VEDHA[p][t.hMoon];
      for (const q of PLANETS) {
        if (q === p || q === I.VEDHA_EXEMPT[p]) continue;
        if ((p === 'Rahu' && q === 'Ketu') || (p === 'Ketu' && q === 'Rahu')) continue;
        // The fast Moon only obstructs its own daily result, not slower transits
        if (q === 'Moon' && p !== 'Moon') continue;
        if (tr[q].hMoon === vh) { vedhaBy = q; break; }
      }
      t.vedhaHouse = vedhaBy ? vh : null;
    }
    t.good = good;
    t.vedhaBy = vedhaBy;
    t.effect = good ? (vedhaBy ? 'neutral' : 'favorable') : 'challenging';
  }
}

const ASPECT_ANGLES = [['conjunction', 0], ['sextile', 60], ['square', 90], ['trine', 120], ['opposition', 180]];
function aspectsFor(ctx, tr, { includeMoon = true, maxOrb = 3 } = {}) {
  const found = [];
  for (const t of PLANETS) {
    if (t === 'Moon' && !includeMoon) continue;
    for (const [n, nl] of Object.entries(ctx.natal.planets)) {
      const diff = Math.abs(norm360(tr[t].long - nl));
      const sep = diff > 180 ? 360 - diff : diff;
      for (const [aspect, angle] of ASPECT_ANGLES) {
        if ((t === 'Rahu' || t === 'Ketu') && aspect !== 'conjunction') continue;
        const orb = Math.abs(sep - angle);
        if (orb > maxOrb) continue;
        const benefic = BENEFICS.includes(t);
        let effect;
        if (benefic) effect = ['conjunction', 'trine', 'sextile'].includes(aspect) ? 'favorable' : 'neutral';
        else effect = ['trine', 'sextile'].includes(aspect) ? 'neutral' : 'challenging';
        if (t === 'Jupiter' && aspect === 'opposition') effect = 'favorable';
        const strength = (W_SLOW[t] || 1.5) * (1 - orb / (maxOrb + 0.5));
        found.push({
          transitPlanet: t, natalPlanet: n, aspect, orb: Math.round(orb * 100) / 100, effect,
          meaning: I.aspectMeaning(t, n, aspect, effect), _strength: strength
        });
      }
    }
  }
  found.sort((a, b) => b._strength - a._strength);
  return found;
}
const publicAspect = (a) => ({ transitPlanet: a.transitPlanet, natalPlanet: a.natalPlanet, aspect: a.aspect, orb: a.orb, effect: a.effect, meaning: a.meaning });

function spanDates(ctx, planet, jd) {
  const since = findSignBoundary(planet, jd, -1);
  const until = findSignBoundary(planet, jd, 1);
  return {
    since: since === null ? null : localIso(jdToMs(since), ctx.tz),
    until: until === null ? null : localIso(jdToMs(until), ctx.tz)
  };
}

function transitObject(ctx, t, jd, withSpan = true) {
  const entry = I.GOCHARA[t.planet][t.hMoon];
  let meaning = `${entry.theme}. ${entry.meaning}`;
  if (t.vedhaBy) meaning += ` Its good results are partly blocked (Vedha) by ${t.vedhaBy} in your ${ORD(t.vedhaHouse)} from Moon, so the effect is milder.`;
  const span = withSpan ? spanDates(ctx, t.planet, jd) : { since: null, until: null };
  return {
    planet: t.planet,
    sign: SIGNS[t.sign],
    degree: Math.floor((norm360(t.long) % 30) * 100) / 100,
    nakshatra: NAKS[t.nak],
    retrograde: t.retro,
    houseFromMoon: t.hMoon,
    houseFromLagna: t.hLagna,
    effect: t.effect,
    title: `${t.planet} in your ${ORD(t.hMoon)} from Moon`,
    meaning,
    realLife: entry.realLife.slice(0, 5),
    doList: entry.doList.slice(),
    avoidList: entry.avoidList.slice(),
    since: span.since,
    until: span.until
  };
}

// ---------------------------------------------------------------------------
// Scores
// ---------------------------------------------------------------------------
function lagnaNature(p, h) {
  if (BENEFICS.includes(p)) return [6, 8, 12].includes(h) ? -0.6 : (h === 3 ? 0 : 1);
  if ([3, 6, 10, 11].includes(h)) return 1;
  return [8, 12].includes(h) ? -1 : -0.6;
}

function gocharaReason(p, t, area, mode) {
  const lead = p === 'Moon' && mode === 'day'
    ? `Today's Moon in your ${ORD(t.hMoon)} from natal Moon`
    : `${p} transiting your ${ORD(t.hMoon)} from Moon`;
  if (t.effect === 'favorable') return `${lead} (${I.HOUSE_TOPICS[t.hMoon]}) supports your ${I.AREA_LABEL[area]}.`;
  if (t.effect === 'neutral') return `${lead} would help your ${I.AREA_LABEL[area]}, but ${t.vedhaBy} in your ${ORD(t.vedhaHouse)} blocks it (Vedha), keeping things steady.`;
  return `${lead} (${I.HOUSE_TOPICS[t.hMoon]}) asks for care in ${I.AREA_LABEL[area]}.`;
}

function strengthWord(s) {
  if (s >= 0.6) return 'strong';
  if (s >= 0.2) return 'well placed';
  if (s > -0.2) return 'moderately placed';
  if (s > -0.6) return 'under some strain';
  return 'weak';
}

/**
 * Explainable contributions to each life area.
 * mode 'day': all planets at sunrise + Tara Bala + Chandrashtama + 3 dasha levels
 * mode 'slow': no Moon/Tara; Saturn/Jupiter/nodes dominate (used for week/month)
 */
function buildDrivers(ctx, tr, o) {
  const W = o.mode === 'day' ? W_DAY : W_SLOW;
  const known = ctx.natal.birthTimeKnown;
  const dashaLords = new Set([o.dasha.md.lord, o.dasha.ad.lord]);
  const out = [];
  for (const p of PLANETS) {
    if (!W[p]) continue;
    const t = tr[p];
    const mult = dashaLords.has(p) ? 1.35 : 1;
    for (const area of AREAS) {
      const inHouse = AREA_HOUSES[area].includes(t.hMoon);
      const karaka = AREA_KARAKAS[area].includes(p);
      const rel = (inHouse ? 1 : 0) + (karaka ? 0.5 : 0) + 0.1;
      out.push({ area, planet: p, kind: 'gochara', value: G_VAL[t.effect] * W[p] * rel * mult, text: gocharaReason(p, t, area, o.mode) });
      if (AREA_HOUSES[area].includes(t.hLagna)) {
        const nat = lagnaNature(p, t.hLagna);
        if (nat !== 0) {
          out.push({
            area, planet: p, kind: 'lagna', value: nat * W[p] * 0.45 * (known ? 1 : 0.4),
            text: `${p} in your ${ORD(t.hLagna)} house from Lagna ${nat > 0 ? 'strengthens' : 'adds pressure to'} your ${I.AREA_LABEL[area]}.`
          });
        }
      }
    }
  }
  if (o.mode === 'day') {
    const tara = I.TARA[o.taraNum];
    for (const area of AREAS) {
      const f = area === 'mind' ? 1.3 : area === 'health' ? 1.1 : 1;
      out.push({ area, planet: null, kind: 'tara', value: TARA_VAL[o.taraNum] * 5 * f,
        text: `Today's ${tara.name} Tara (${o.taraNum}) from your birth star ${tara.favorable ? 'supports' : 'weighs on'} your ${I.AREA_LABEL[area]}.` });
      if (o.chandrashtama) {
        out.push({ area, planet: 'Moon', kind: 'chandrashtama', value: ['mind', 'health'].includes(area) ? -11 : -8,
          text: 'The Moon is in the 8th from your natal Moon (Chandrashtama), lowering energy and judgement today.' });
      }
    }
  }
  const levels = [['Mahadasha', o.dasha.md.lord, 5], ['Antardasha', o.dasha.ad.lord, 3.5]];
  if (o.mode === 'day') levels.push(['Pratyantardasha', o.dasha.pd.lord, 2]);
  for (const [level, lord, w] of levels) {
    const inf = ctx.natal.info[lord];
    if (!inf) continue;
    for (const area of AREAS) {
      const rel = I.DASHA_LORD[lord].areas.includes(area) ? 1 : 0.35;
      out.push({ area, planet: lord, kind: 'dasha', value: inf.strength * w * rel,
        text: `Your ${level} lord ${lord} is ${strengthWord(inf.strength)} in your birth chart (${inf.dignity}, ${ORD(inf.house)} house from ${ctx.natal.houseBasis}).` });
    }
  }
  for (const a of o.aspects || []) {
    if (o.mode !== 'day' && a.transitPlanet === 'Moon') continue;
    const sgn = a.effect === 'favorable' ? 1 : a.effect === 'challenging' ? -1 : 0;
    if (!sgn) continue;
    const areas = (I.DASHA_LORD[a.natalPlanet] || { areas: [] }).areas;
    for (const area of areas) {
      out.push({ area, planet: a.transitPlanet, kind: 'aspect', value: sgn * 2.5 * (1 - a.orb / 3.5),
        text: `Transit ${a.transitPlanet} ${a.aspect === 'conjunction' ? 'conjunct' : a.aspect} your natal ${a.natalPlanet} (orb ${a.orb.toFixed(1)}°) ${sgn > 0 ? 'lifts' : 'tests'} your ${I.AREA_LABEL[area]}.` });
    }
  }
  return out;
}

function labelFor(score) {
  if (score >= 80) return 'Strong';
  if (score >= 65) return 'Good';
  if (score >= 50) return 'Steady';
  if (score >= 35) return 'Careful';
  return 'Difficult';
}
function moodFor(score) {
  if (score >= 72) return 'excellent';
  if (score >= 58) return 'good';
  if (score >= 44) return 'mixed';
  return 'challenging';
}
function rawToScore(sum) {
  return clamp(Math.round(52 + 44 * Math.tanh(sum / SCORE_K)), 5, 97);
}
function pickReason(drivers, area, positive) {
  const ds = drivers.filter((d) => d.area === area && d.value !== 0);
  if (!ds.length) return null;
  const dir = ds.filter((d) => (positive ? d.value > 0 : d.value < 0));
  const pool = dir.length ? dir : ds;
  return pool.reduce((best, d) => (Math.abs(d.value) > Math.abs(best.value) ? d : best), pool[0]);
}
function scoresFromDrivers(drivers) {
  const scores = {};
  for (const area of AREAS) {
    const sum = AREA_BIAS[area] + drivers.filter((d) => d.area === area).reduce((s, d) => s + d.value, 0);
    const score = rawToScore(sum);
    const r = pickReason(drivers, area, score >= 50);
    scores[area] = { score, label: labelFor(score), reason: r ? r.text : 'No strong planetary influence on this area right now.' };
  }
  return scores;
}
function overallOf(scores) {
  return Math.round(AREAS.reduce((s, a) => s + scores[a].score * AREA_WEIGHT[a], 0));
}
function blendScores(daily, slow, slowDrivers, wDaily) {
  const out = {};
  for (const area of AREAS) {
    const avg = daily.reduce((s, d) => s + d.scores[area].score, 0) / daily.length;
    const score = clamp(Math.round(wDaily * avg + (1 - wDaily) * slow[area].score), 0, 100);
    const r = pickReason(slowDrivers, area, score >= 50);
    out[area] = { score, label: labelFor(score), reason: r ? r.text : slow[area].reason };
  }
  return out;
}

// ---------------------------------------------------------------------------
// Day computation (cheap: no panchang strings, no span searches)
// ---------------------------------------------------------------------------
function taraNumber(birthNak, nak) {
  return (((nak - birthNak + 27) % 27) % 9) + 1;
}

function dayInfo(ctx, iso) {
  let d = ctx.days.get(iso);
  if (d) return d;
  const anchor = getAnchor(ctx, iso);
  const jd = anchor.sunriseJd;
  const tr = transitsAt(ctx, jd);
  const moon = tr.Moon;
  const taraNum = taraNumber(ctx.natal.moonNak, moon.nak);
  const pe = A.panchangElements(tr.Sun.long, tr.Moon.long);
  const chandrashtama = moon.hMoon === 8;
  const dasha = dashaAt(ctx, jdToMs(jd));
  const aspects = aspectsFor(ctx, tr);
  const drivers = buildDrivers(ctx, tr, { mode: 'day', taraNum, chandrashtama, dasha, aspects });
  const scores = scoresFromDrivers(drivers);
  const overall = overallOf(scores);
  d = {
    iso, jd, anchor, tr, taraNum, tara: I.TARA[taraNum], pe, chandrashtama,
    chandraBala: [1, 3, 6, 7, 10, 11].includes(moon.hMoon),
    dasha, aspects, drivers, scores, overall, mood: moodFor(overall),
    weekday: A.WEEKDAYS[isoWeekday(iso)]
  };
  ctx.days.set(iso, d);
  return d;
}

function slowLayer(ctx, jd) {
  const tr = transitsAt(ctx, jd);
  const dasha = dashaAt(ctx, jdToMs(jd));
  const aspects = aspectsFor(ctx, tr, { includeMoon: false });
  const drivers = buildDrivers(ctx, tr, { mode: 'slow', dasha, aspects });
  return { tr, dasha, drivers, scores: scoresFromDrivers(drivers) };
}

// Moon sign change within [sunrise, end of local day]
function moonSignChange(ctx, d) {
  const endJd = msToJd(d.anchor.nextMidnightMs);
  const ch = ingressesBetween('Moon', d.jd, endJd);
  if (!ch.length) return { changesSignAt: null, nextSign: null };
  return { changesSignAt: clock(jdToMs(ch[0].jd), ctx.tz), nextSign: SIGNS[ch[0].to] };
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------
function mkEvent(ctx, ms, type, title, description, personalImpact, importance, withTime = true) {
  return { date: localIso(ms, ctx.tz), time: withTime ? clock(ms, ctx.tz) : null, type, title, description, personalImpact, importance, _ms: ms };
}

function eclipsesBetween(jdA, jdB) {
  const out = [];
  const typeName = (flag) => {
    if (flag & C.SE_ECL_TOTAL) return 'total';
    if (flag & C.SE_ECL_ANNULAR_TOTAL) return 'hybrid';
    if (flag & C.SE_ECL_ANNULAR) return 'annular';
    if (flag & C.SE_ECL_PARTIAL) return 'partial';
    if (flag & C.SE_ECL_PENUMBRAL) return 'penumbral';
    return 'partial';
  };
  try {
    let t = jdA;
    for (let i = 0; i < 40; i++) {
      const r = sweph.sol_eclipse_when_glob(t, A.EPHE_FLAG, 0, false);
      if (!r || r.flag < 0 || !Array.isArray(r.data)) break;
      const jd = r.data[0];
      if (jd >= jdB) break;
      if (jd >= jdA) out.push({ kind: 'solar', subtype: typeName(r.flag), jd });
      t = jd + 20;
    }
    t = jdA;
    for (let i = 0; i < 40; i++) {
      const r = sweph.lun_eclipse_when(t, A.EPHE_FLAG, 0, false);
      if (!r || r.flag < 0 || !Array.isArray(r.data)) break;
      const jd = r.data[0];
      if (jd >= jdB) break;
      const sub = typeName(r.flag);
      if (jd >= jdA && sub !== 'penumbral') out.push({ kind: 'lunar', subtype: sub, jd });
      t = jd + 20;
    }
  } catch (err) {
    console.warn('Eclipse search failed:', err && err.message);
  }
  return out.sort((a, b) => a.jd - b.jd);
}

/**
 * All events whose (local) date is within [startIso, endIso].
 * opts.chandrashtama (default true), opts.minImportance
 */
function eventsBetween(ctx, startIso, endIso, opts = {}) {
  const msA = localMidnightMs(startIso, ctx.tz);
  const msB = localMidnightMs(isoAdd(endIso, 1), ctx.tz);
  const jdA = msToJd(msA);
  const jdB = msToJd(msB);
  const nm = ctx.natal.moonSign;
  const ev = [];

  // Ingresses (Sun ingress = Sankranti)
  for (const p of ['Sun', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Rahu']) {
    for (const ing of ingressesBetween(p, jdA, jdB)) {
      const ms = jdToMs(ing.jd);
      const h = houseFrom(ing.to, nm);
      if (p === 'Sun') {
        const name = `${SANKRANTI_NAMES[ing.to]} Sankranti`;
        const desc = ing.to === 9 ? I.FESTIVAL_DESC['Makar Sankranti'] : `The Sun enters ${SIGNS[ing.to]}, beginning a new solar month; a traditional day for charity and holy baths.`;
        ev.push(mkEvent(ctx, ms, 'sankranti', ing.to === 9 ? 'Makar Sankranti' : name, desc, I.ingressImpact('Sun', h), ing.to === 9 ? 3 : 2));
      } else if (p === 'Rahu') {
        const k = (ing.to + 6) % 12;
        const hk = houseFrom(k, nm);
        ev.push(mkEvent(ctx, ms, 'ingress', `Rahu enters ${SIGNS[ing.to]}, Ketu enters ${SIGNS[k]}`,
          `${I.INGRESS_DESC.Rahu} ${I.INGRESS_DESC.Ketu}`,
          `${I.RAHU_KETU_AXIS[h]} (Rahu in your ${ORD(h)}, Ketu in your ${ORD(hk)} from Moon.)`, 3));
      } else {
        ev.push(mkEvent(ctx, ms, 'ingress', `${p} enters ${SIGNS[ing.to]}`, I.INGRESS_DESC[p], I.ingressImpact(p, h),
          ['Jupiter', 'Saturn'].includes(p) ? 3 : p === 'Mars' ? 2 : 1));
      }
    }
  }
  // Stations
  for (const p of ['Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn']) {
    for (const st of stationsBetween(p, jdA, jdB)) {
      const ms = jdToMs(st.jd);
      const h = houseFrom(signAt(p, st.jd), nm);
      const tx = I.stationText(p, st.kind, h);
      ev.push(mkEvent(ctx, ms, st.kind, `${p} turns ${st.kind === 'retrograde' ? 'retrograde' : 'direct'} in ${SIGNS[signAt(p, st.jd)]}`,
        tx.description, tx.personalImpact, 2));
    }
  }
  // Eclipses
  for (const ec of eclipsesBetween(jdA, jdB)) {
    const ms = jdToMs(ec.jd);
    const pointLong = ec.kind === 'solar' ? A.calcBody(ec.jd, C.SE_SUN).long : A.calcBody(ec.jd, C.SE_MOON).long;
    const s = signOf(pointLong);
    const tx = I.eclipseText(ec.kind, ec.subtype, houseFrom(s, nm));
    ev.push(mkEvent(ctx, ms, ec.kind === 'solar' ? 'solar_eclipse' : 'lunar_eclipse',
      `${uc(ec.subtype)} ${ec.kind} eclipse in ${SIGNS[s]}`, tx.description, tx.personalImpact, 3));
  }
  // Full / new moons
  for (const tc of tithiChanges(jdA, jdB)) {
    if (tc.tithi !== 16 && tc.tithi !== 1) continue;
    const kind = tc.tithi === 16 ? 'full_moon' : 'new_moon';
    const s = signOf(A.calcBody(tc.jd, C.SE_MOON).long);
    const tx = I.lunationText(kind, houseFrom(s, nm), SIGNS[s]);
    ev.push(mkEvent(ctx, jdToMs(tc.jd), kind, kind === 'full_moon' ? `Purnima (Full Moon) in ${SIGNS[s]}` : `Amavasya (New Moon) in ${SIGNS[s]}`,
      tx.description, tx.personalImpact, 1));
  }
  // Ekadashi and festivals (observance days in the profile's location)
  const isoList = [];
  for (let iso = isoAdd(startIso, -2); iso <= isoAdd(endIso, 2); iso = isoAdd(iso, 1)) isoList.push(iso);
  ensureNewMoons(ctx, jdA - 3, jdB + 3);
  const inRange = (iso) => iso >= startIso && iso <= endIso;
  for (const T of [11, 26]) {
    for (const o of observanceDays(ctx, isoList, T, 'sunrise', null)) {
      if (!inRange(o.iso)) continue;
      const paksha = T === 11 ? 'Shukla' : 'Krishna';
      const named = o.info.adhika ? (T === 11 ? 'Padmini' : 'Parama') : (o.info.month !== null ? EKADASHI_NAMES[o.info.month][T === 11 ? 0 : 1] : null);
      const d = dayInfo(ctx, o.iso);
      ev.push({
        date: o.iso, time: null, type: 'ekadashi',
        title: named ? `${named} Ekadashi` : `${paksha} Ekadashi`,
        description: `${paksha} Ekadashi${o.info.name ? ` of ${o.info.name}` : ''}: a day for fasting or light sattvic food, Vishnu worship and mental cleansing.`,
        personalImpact: `With the Moon in your ${ORD(d.tr.Moon.hMoon)} from natal Moon and ${d.tara.name} Tara, it is a good day to fast or simplify food and focus on ${d.tara.favorable ? 'intentions you want to grow' : 'letting go of stress'}.`,
        importance: 1, _ms: getAnchor(ctx, o.iso).midnightMs
      });
    }
  }
  // Holika Dahan: Phalguna Purnima at pradosh, after Bhadra (Vishti karana, elongation 168-174 deg).
  // If Bhadra covers that whole night, it moves to the next evening. Holi (colours) is the following day.
  for (const o of observanceDays(ctx, isoList, 15, 'pradosh', 11)) {
    let dahan = o.iso;
    const next = getAnchor(ctx, isoAdd(o.iso, 1));
    const pr = kaalJd(ctx, o.iso, 'pradosh');
    const bhadraEnd = elongAt(pr) < 174 ? bisect((x) => elongAt(x) < 174, pr, pr + 1.2, 24) : pr;
    const purnimaEnd = bisect((x) => elongAt(x) < 180, pr, pr + 1.5, 24);
    const threePrahars = next.sunriseJd + 0.75 * (next.sunsetJd - next.sunriseJd);
    // Dharmasindhu: Bhadra over pradosh + Purnima lasting 3 prahars into the next day -> next evening
    if (bhadraEnd > pr && purnimaEnd > threePrahars) dahan = isoAdd(o.iso, 1);
    const holi = isoAdd(dahan, 1);
    for (const [iso, name] of [[dahan, 'Holika Dahan'], [holi, 'Holi']]) {
      if (!inRange(iso)) continue;
      const d = dayInfo(ctx, iso);
      ev.push({
        date: iso, time: null, type: 'festival', title: name, description: I.FESTIVAL_DESC[name],
        personalImpact: `For you the Moon is in your ${ORD(d.tr.Moon.hMoon)} from natal Moon (${I.HOUSE_TOPICS[d.tr.Moon.hMoon]}) with ${d.tara.name} Tara${d.chandrashtama ? ' and Chandrashtama, so keep celebrations calm and simple' : ', a good day to let old grudges burn away and celebrate'}.`,
        importance: name === 'Holi' ? 2 : 1, _ms: getAnchor(ctx, iso).midnightMs
      });
    }
  }
  for (const f of FESTIVALS) {
    for (const o of observanceDays(ctx, isoList, f.tithi, f.kaal, f.month)) {
      if (!inRange(o.iso)) continue;
      const d = dayInfo(ctx, o.iso);
      ev.push({
        date: o.iso, time: null, type: 'festival', title: f.name,
        description: I.FESTIVAL_DESC[f.name] || `${f.name}.`,
        personalImpact: `For you the Moon is in your ${ORD(d.tr.Moon.hMoon)} from natal Moon (${I.HOUSE_TOPICS[d.tr.Moon.hMoon]}) with ${d.tara.name} Tara${d.chandrashtama ? ' and Chandrashtama, so keep celebrations calm and simple' : ', so the day’s blessings flow naturally into these areas'}.`,
        importance: MAJOR_FESTIVALS.has(f.name) ? 2 : 1, _ms: getAnchor(ctx, o.iso).midnightMs
      });
    }
  }
  // Dasha changes
  for (const md of mahadashaList(ctx)) {
    if (md.end <= msA || md.start >= msB) continue;
    for (const ad of subPeriods(md)) {
      if (ad.end <= msA || ad.start >= msB) continue;
      for (const pd of subPeriods(ad)) {
        if (pd.start < msA || pd.start >= msB || pd.start <= ctx.natal.birthMs) continue;
        const isMd = pd.start === md.start;
        const isAd = pd.start === ad.start;
        const inf = ctx.natal.info[isMd ? md.lord : isAd ? ad.lord : pd.lord];
        const where = inf ? ` In your chart this lord sits in your ${ORD(inf.house)} house from ${ctx.natal.houseBasis} (${I.HOUSE_TOPICS[inf.house]}).` : '';
        if (isMd) {
          ev.push(mkEvent(ctx, pd.start, 'dasha_change', `${md.lord} Mahadasha begins`, I.dashaPeriodText('mahadasha', md.lord, ctx.natal.info, ctx.natal.houseBasis).summary,
            `${I.dashaTheme(md.lord, ad.lord, ctx.natal.info, ctx.natal.houseBasis)}${where}`, 3, false));
        } else if (isAd) {
          ev.push(mkEvent(ctx, pd.start, 'dasha_change', `${md.lord}-${ad.lord} Antardasha begins`, `A new sub-period of ${ad.lord} within your ${md.lord} Mahadasha.`,
            I.dashaTheme(md.lord, ad.lord, ctx.natal.info, ctx.natal.houseBasis), 2, false));
        } else {
          ev.push(mkEvent(ctx, pd.start, 'dasha_change', `${ad.lord}-${pd.lord} Pratyantardasha begins`,
            `A short sub-sub-period of ${pd.lord} (${I.DASHA_LORD[pd.lord].keywords}) within ${md.lord}-${ad.lord}.`,
            `For the next few weeks ${pd.lord}'s themes colour your days.${where}`, 1, false));
        }
      }
    }
  }
  // Chandrashtama periods overlapping the window
  if (opts.chandrashtama !== false) {
    const ch = (nm + 7) % 12;
    for (const seg of signSegments('Moon', jdA, jdB)) {
      if (seg.sign !== ch || seg.start === null || seg.end === null) continue;
      if (seg.end <= jdA || seg.start >= jdB) continue;
      const startMs = jdToMs(seg.start);
      const endMs = jdToMs(seg.end);
      const startsInside = seg.start >= jdA;
      const e = mkEvent(ctx, startsInside ? startMs : msA, 'chandrashtama', `Chandrashtama: Moon in ${SIGNS[ch]}`,
        `The Moon transits the 8th sign from your natal Moon until ${localIso(endMs, ctx.tz)} ${clock(endMs, ctx.tz)}. Traditionally a time to avoid major decisions, launches and arguments.`,
        'Keep plans simple, rest well and double-check important work; energy and judgement can dip for these two to three days.', 2, startsInside);
      ev.push(e);
    }
  }

  const minImp = opts.minImportance || 1;
  return ev
    .filter((e) => e.date >= startIso && e.date <= endIso && e.importance >= minImp)
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : (a._ms - b._ms) || (b.importance - a.importance)))
    .map(({ _ms, ...rest }) => rest);
}

// ---------------------------------------------------------------------------
// Day extras: goodFor / avoid / bestTimes / remedy / lucky
// ---------------------------------------------------------------------------
const RIKTA = new Set([4, 9, 14, 19, 24, 29]);

function uniq(arr) {
  const seen = new Set();
  return arr.filter((x) => {
    const k = String(x).toLowerCase();
    if (!x || seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

function goodAndAvoid(ctx, d, panchang) {
  const mh = d.tr.Moon.hMoon;
  const moonEntry = I.GOCHARA.Moon[mh];
  const nature = I.nakshatraNature(NAKS[d.tr.Moon.nak]);
  let good = [];
  let avoid = [];
  if (d.chandrashtama) {
    good.push('Routine work and finishing pending tasks', 'Rest, meditation and prayer');
    avoid.push('Major decisions, launches or signing big contracts', 'Arguments and risky activities');
  }
  good = good.concat(d.tara.goodFor, moonEntry.doList, nature.goodFor);
  avoid = avoid.concat(d.tara.avoid, moonEntry.avoidList, nature.avoid);
  if (RIKTA.has(d.pe.tithiNumber)) avoid.push('Starting new ventures (Rikta tithi)');
  if (d.pe.tithiNumber === 30) avoid.push('New beginnings on Amavasya');
  if (panchang && panchang.rahuKaal) avoid.push(`Starting important work during Rahu Kaal (${panchang.rahuKaal})`);
  good = uniq(good).slice(0, 5);
  avoid = uniq(avoid).slice(0, 5);
  while (good.length < 3) good.push(['Prayer or meditation', 'Helping someone in need', 'Planning the week ahead'][good.length]);
  while (avoid.length < 3) avoid.push(['Overcommitting your time', 'Skipping meals or sleep', 'Gossip'][avoid.length]);
  return { goodFor: good, avoid };
}

const HORA_MEANING = {
  Sun: 'leadership, government and authority work', Moon: 'travel, public dealings and nurturing',
  Mars: 'courage, physical effort and property', Mercury: 'writing, trade and communication',
  Jupiter: 'learning, finance and auspicious beginnings', Venus: 'relationships, art and purchases',
  Saturn: 'disciplined, long-term work'
};
const CHOG_START = [0, 3, 6, 2, 5, 1, 4];
const CHOG_CYCLE = [['Udveg', false], ['Char', false], ['Labh', true], ['Amrit', true], ['Kaal', false], ['Shubh', true], ['Rog', false]];
const RAHU_SEG = [8, 2, 7, 5, 6, 4, 3];

function bestTimes(ctx, d) {
  const wd = isoWeekday(d.iso);
  const rise = jdToMs(d.anchor.sunriseJd);
  const set = jdToMs(d.anchor.sunsetJd);
  const dayLen = set - rise;
  const part = dayLen / 8;
  const rahu = [rise + (RAHU_SEG[wd] - 1) * part, rise + RAHU_SEG[wd] * part];
  const overlapsRahu = (s, e) => s < rahu[1] && e > rahu[0];
  const out = [];
  const add = (label, s, e, reason) => out.push({ label, start: clock(s, ctx.tz), end: clock(e, ctx.tz), reason, _s: s });

  // Abhijit muhurat (traditionally skipped on Wednesdays)
  const mid = (rise + set) / 2;
  const muh = dayLen / 15;
  if (wd !== 3 && !overlapsRahu(mid - muh / 2, mid + muh / 2)) add('Abhijit Muhurat', mid - muh / 2, mid + muh / 2, 'The most auspicious midday window for important starts and decisions.');

  // Favourable day choghadiya (Amrit first, then Shubh/Labh), avoiding Rahu Kaal
  const chogs = [];
  for (let i = 0; i < 8; i++) {
    const [name, good] = CHOG_CYCLE[(CHOG_START[wd] + i) % 7];
    const s = rise + i * part;
    const e = s + part;
    if (good && !overlapsRahu(s, e)) chogs.push({ name, s, e, rank: name === 'Amrit' ? 0 : name === 'Shubh' ? 1 : 2 });
  }
  chogs.sort((a, b) => a.rank - b.rank || a.s - b.s);
  for (const c of chogs.slice(0, 2)) {
    add(`${c.name} Choghadiya`, c.s, c.e, c.name === 'Amrit' ? 'Amrit (nectar) period: best for anything important.' : c.name === 'Shubh' ? 'Shubh (auspicious) period: good for ceremonies, learning and meetings.' : 'Labh (gain) period: good for business, money and trade.');
  }

  // Hora of the running dasha lord (or Jupiter when the lord is a node)
  const lords = [d.dasha.ad.lord, d.dasha.md.lord].filter((l) => A.CHALDEAN.includes(l));
  const horaLen = dayLen / 12;
  const startIdx = A.CHALDEAN.indexOf(A.WEEKDAY_LORDS[wd]);
  const candidates = uniq([...lords, 'Jupiter', 'Venus']);
  let added = false;
  for (const lord of candidates) {
    if (added) break;
    for (let i = 0; i < 12; i++) {
      if (A.CHALDEAN[(startIdx + i) % 7] !== lord) continue;
      const s = rise + i * horaLen;
      const e = s + horaLen;
      if (overlapsRahu(s, e)) continue;
      const why = lords.includes(lord)
        ? `Hora of your ${lord === d.dasha.ad.lord ? 'Antardasha' : 'Mahadasha'} lord ${lord}`
        : `${lord} hora (a natural benefic, used because your dasha lord's hora is not free today)`;
      add(`${lord} Hora`, s, e, `${why}: good for ${HORA_MEANING[lord]}.`);
      added = true;
      break;
    }
  }
  out.sort((a, b) => a._s - b._s);
  return out.slice(0, 4).map(({ _s, ...r }) => r);
}

function remedyFor(scores, drivers, dasha) {
  const weakest = AREAS.reduce((w, a) => (scores[a].score < scores[w].score ? a : w), AREAS[0]);
  const neg = drivers.filter((x) => x.area === weakest && x.value < 0 && x.planet);
  let planet = neg.length ? neg.reduce((m, x) => (x.value < m.value ? x : m), neg[0]).planet : dasha.md.lord;
  if (!I.REMEDIES[planet]) planet = 'Jupiter';
  const r = I.REMEDIES[planet];
  return { title: `For your ${I.AREA_LABEL[weakest]}: steady ${planet}'s influence`, mantra: r.mantra, action: r.action, color: r.color, day: r.day };
}

function lucky(d) {
  const wl = A.WEEKDAY_LORDS[isoWeekday(d.iso)];
  const cands = [wl, d.dasha.ad.lord, d.dasha.md.lord];
  const p = cands.find((c) => d.tr[c] && d.tr[c].effect === 'favorable') || (d.tara.favorable ? wl : 'Jupiter');
  return { luckyColor: I.LUCKY_COLOR[p], luckyNumber: I.LUCKY_NUMBER[p] };
}

// ---------------------------------------------------------------------------
// Narrative (rules)
// ---------------------------------------------------------------------------
function bestWorst(scores) {
  const sorted = AREAS.slice().sort((a, b) => scores[b].score - scores[a].score);
  return { best: sorted[0], worst: sorted[sorted.length - 1] };
}
function clip(s, n) {
  if (s.length <= n) return s;
  return `${s.slice(0, n - 1).replace(/[\s,;:.-]+\S*$/, '')}…`;
}
function strongestSlow(tr) {
  const order = ['Saturn', 'Jupiter', 'Rahu'];
  return order.map((p) => tr[p]).find((t) => t.effect !== 'neutral') || tr.Saturn;
}

function dayNarrative(ctx, d, events) {
  const { best, worst } = bestWorst(d.scores);
  const mh = d.tr.Moon.hMoon;
  const fest = events.find((e) => e.type === 'festival' || e.type === 'solar_eclipse' || e.type === 'lunar_eclipse');
  let headline;
  if (d.chandrashtama) headline = 'Chandrashtama day: keep it simple and steady';
  else if (d.mood === 'excellent') headline = `A strong ${d.tara.name} Tara day for your ${I.AREA_LABEL[best]}`;
  else if (d.mood === 'good') headline = `Good momentum for your ${I.AREA_LABEL[best]} today`;
  else if (d.mood === 'mixed') headline = `A mixed day: lean into ${I.AREA_LABEL[best]}, go easy on ${I.AREA_LABEL[worst]}`;
  else headline = `A slower day: protect your ${I.AREA_LABEL[worst]} and pace yourself`;
  if (fest) headline = `${fest.title}: ${lc(headline)}`;
  const slow = strongestSlow(d.tr);
  const sEntry = I.GOCHARA[slow.planet][slow.hMoon];
  const moonEntry = I.GOCHARA.Moon[mh];
  const sentences = [
    `${ctx.firstName}, today the Moon is in your ${ORD(mh)} house from your natal Moon, a "${moonEntry.theme}" kind of day, and ${d.tara.name} Tara is ${d.tara.favorable ? 'on your side' : 'asking for patience'}.`,
    `In the background, ${slow.planet} in your ${ORD(slow.hMoon)} from Moon ("${sEntry.theme}") sets the longer-term tone.`,
    `Your ${d.dasha.md.lord}-${d.dasha.ad.lord} dasha keeps ${I.DASHA_LORD[d.dasha.ad.lord].keywords} in focus.`,
    d.chandrashtama
      ? 'Keep big decisions for another day and favour rest and routine.'
      : `Your ${I.AREA_LABEL[best]} looks strongest (${d.scores[best].score}/100), while ${I.AREA_LABEL[worst]} needs a gentler touch.`
  ];
  return { headline: clip(headline, 90), narrative: sentences.join(' '), mood: d.mood, overallScore: d.overall };
}

// ---------------------------------------------------------------------------
// Public builders
// ---------------------------------------------------------------------------
function baseFields(ctx) {
  const known = ctx.natal.birthTimeKnown;
  return {
    profile: ctx.profile,
    birthTimeKnown: known,
    accuracyNote: known ? null : 'Birth time is unknown, so Lagna-based parts (houses from Lagna, dasha lord houses) are approximate; Moon-based results are reliable.',
    generatedBy: 'rules'
  };
}

function buildDay(ctx, iso) {
  const date = iso || todayFor(ctx);
  const d = dayInfo(ctx, date);
  const panchang = A.calculateDailyPanchangAndMuhurats(date, ctx.latRS, ctx.lng, ctx.tzName);
  const events = eventsBetween(ctx, date, date);
  const transits = TRANSIT_ORDER.map((p) => transitObject(ctx, d.tr[p], d.jd, true));
  const msc = moonSignChange(ctx, d);
  const ga = goodAndAvoid(ctx, d, panchang);
  const summary = dayNarrative(ctx, d, events);
  return {
    type: 'day',
    date,
    weekday: d.weekday,
    ...baseFields(ctx),
    summary,
    scores: d.scores,
    moon: {
      sign: SIGNS[d.tr.Moon.sign],
      nakshatra: NAKS[d.tr.Moon.nak],
      houseFromMoon: d.tr.Moon.hMoon,
      houseFromLagna: d.tr.Moon.hLagna,
      taraBala: { name: d.tara.name, number: d.taraNum, favorable: d.tara.favorable, meaning: d.tara.meaning },
      chandraBala: d.chandraBala,
      chandrashtama: d.chandrashtama,
      changesSignAt: msc.changesSignAt,
      nextSign: msc.nextSign
    },
    dasha: dashaNow(ctx, jdToMs(d.jd)),
    transits,
    aspects: d.aspects.slice(0, 6).map(publicAspect),
    events,
    panchang,
    goodFor: ga.goodFor,
    avoid: ga.avoid,
    bestTimes: bestTimes(ctx, d),
    remedy: remedyFor(d.scores, d.drivers, d.dasha),
    ...lucky(d)
  };
}

function dayHighlight(d, festival, eclipse) {
  if (festival) return `${festival} · ${d.tara.name} Tara`;
  if (eclipse) return `${eclipse} · rest and reflect`;
  if (d.chandrashtama) return 'Chandrashtama: go slow, avoid big decisions';
  return `${I.GOCHARA.Moon[d.tr.Moon.hMoon].theme} · ${d.tara.name} Tara`;
}

function pickBestDays(days, n) {
  const usable = days.filter((d) => !d.chandrashtama);
  const top = (fn, cond) => usable.filter(cond || (() => true)).map((d) => ({ d, v: fn(d) }))
    .sort((a, b) => b.v - a.v).slice(0, n).filter((x) => x.v >= 55).map((x) => x.d.iso).sort();
  const travelNature = new Set(['Chara', 'Kshipra', 'Mridu']);
  const startNature = new Set(['Dhruva', 'Kshipra', 'Mridu', 'Chara']);
  return {
    career: top((d) => d.scores.career.score),
    love: top((d) => d.scores.love.score),
    money: top((d) => d.scores.money.score),
    travel: top((d) => d.overall + (travelNature.has(I.nakshatraNature(NAKS[d.tr.Moon.nak]).key) ? 8 : 0),
      (d) => d.tara.favorable && ![8, 12].includes(d.tr.Moon.hMoon)),
    newBeginnings: top((d) => d.overall + (startNature.has(I.nakshatraNature(NAKS[d.tr.Moon.nak]).key) ? 6 : 0),
      (d) => d.tara.favorable && !RIKTA.has(d.pe.tithiNumber) && d.pe.tithiNumber !== 30 && ![8, 12].includes(d.tr.Moon.hMoon))
  };
}

function cautionDays(days, events, limit) {
  const out = [];
  for (const d of days) {
    const reasons = [];
    if (d.chandrashtama) reasons.push('Chandrashtama (Moon in the 8th from your natal Moon)');
    if (!d.tara.favorable && d.taraNum !== 1 && d.overall < 50) reasons.push(`${d.tara.name} Tara`);
    const ecl = events.find((e) => e.date === d.iso && (e.type === 'solar_eclipse' || e.type === 'lunar_eclipse'));
    if (ecl) reasons.push(ecl.title);
    if (!reasons.length && d.overall < 40) reasons.push('Low overall planetary support');
    if (reasons.length) out.push({ date: d.iso, reason: `${reasons.join('; ')}: keep plans simple.` });
  }
  return out.slice(0, limit);
}

function festivalByDate(events) {
  const m = {};
  for (const e of events) if (e.type === 'festival' && !m[e.date]) m[e.date] = e.title;
  return m;
}

function mondayOf(iso) {
  const wd = isoWeekday(iso);
  return isoAdd(iso, -((wd + 6) % 7));
}

function buildWeek(ctx, startIso) {
  const weekStart = mondayOf(startIso || todayFor(ctx));
  const weekEnd = isoAdd(weekStart, 6);
  const isoList = Array.from({ length: 7 }, (_, i) => isoAdd(weekStart, i));
  const days = isoList.map((iso) => dayInfo(ctx, iso));
  const slow = slowLayer(ctx, days[3].jd);
  const scores = blendScores(days, slow.scores, slow.drivers, 0.55);
  const overall = overallOf(scores);
  const events = eventsBetween(ctx, weekStart, weekEnd);
  const fest = festivalByDate(events);
  const eclByDate = {};
  for (const e of events) if (e.type.endsWith('eclipse')) eclByDate[e.date] = e.title;
  const today = todayFor(ctx);
  const dashaMs = today >= weekStart && today <= weekEnd ? ctx.nowMs : jdToMs(days[3].jd);
  const bestDays = pickBestDays(days, 2);
  const caution = cautionDays(days, events, 7);
  const { best, worst } = bestWorst(scores);
  const bestDay = days.reduce((b, d) => (d.overall > b.overall ? d : b), days[0]);
  const worstDay = days.reduce((b, d) => (d.overall < b.overall ? d : b), days[0]);
  const keyEv = events.filter((e) => e.importance >= 2 && e.type !== 'chandrashtama');
  const s = strongestSlow(slow.tr);
  const focus = `Put your energy into ${I.AREA_LABEL[best]} this week; ${bestDay.weekday} looks strongest, while ${worstDay.weekday} calls for a slower pace.`;
  const headline = clip(keyEv.length
    ? `${moodHeadline(moodFor(overall))} week · ${keyEv[0].title}`
    : `${moodHeadline(moodFor(overall))} week for your ${I.AREA_LABEL[best]}`, 90);
  const narrative = [
    `${ctx.firstName}, your strongest area this week is ${I.AREA_LABEL[best]}. ${scores[best].reason}`,
    `${s.planet} in your ${ORD(s.hMoon)} from Moon ("${I.GOCHARA[s.planet][s.hMoon].theme}") sets the background tone.`,
    caution.length ? `Go gently on ${caution.map((c) => A.WEEKDAYS[isoWeekday(c.date)]).slice(0, 3).join(', ')}.` : 'No major caution days stand out this week.',
    keyEv.length ? `Key moment: ${keyEv[0].title} on ${A.WEEKDAYS[isoWeekday(keyEv[0].date)]}.` : `Give ${I.AREA_LABEL[worst]} a little extra care.`
  ].join(' ');
  return {
    type: 'week',
    weekStart,
    weekEnd,
    ...baseFields(ctx),
    summary: { headline, narrative, mood: moodFor(overall), overallScore: overall },
    scores,
    days: days.map((d) => ({
      date: d.iso, weekday: d.weekday, score: d.overall, mood: d.mood, moonSign: SIGNS[d.tr.Moon.sign],
      taraBala: d.tara.name, taraFavorable: d.tara.favorable, chandrashtama: d.chandrashtama,
      tithi: d.pe.tithi, highlight: dayHighlight(d, fest[d.iso], eclByDate[d.iso])
    })),
    bestDays,
    cautionDays: caution,
    events,
    dasha: dashaNow(ctx, dashaMs),
    focus,
    remedy: remedyFor(scores, slow.drivers, slow.dasha)
  };
}

function moodHeadline(mood) {
  return { excellent: 'An excellent', good: 'A good', mixed: 'A mixed', challenging: 'A demanding' }[mood];
}

function buildMonth(ctx, monthStr) {
  const month = monthStr || todayFor(ctx).slice(0, 7);
  const [y, m] = month.split('-').map(Number);
  const first = `${month}-01`;
  const nDays = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const last = `${month}-${pad2(nDays)}`;
  const isoList = Array.from({ length: nDays }, (_, i) => isoAdd(first, i));
  const days = isoList.map((iso) => dayInfo(ctx, iso));
  const midJd = days[Math.floor(nDays / 2)].jd;
  const slow = slowLayer(ctx, midJd);
  const scores = blendScores(days, slow.scores, slow.drivers, 0.35);
  const overall = overallOf(scores);
  const events = eventsBetween(ctx, first, last);
  const fest = festivalByDate(events);
  const eclByDate = {};
  for (const e of events) if (e.type.endsWith('eclipse')) eclByDate[e.date] = e.title;

  // Weeks: Monday-Sunday blocks clipped to the month
  const weeks = [];
  let cur = [];
  for (const d of days) {
    if (cur.length && isoWeekday(d.iso) === 1) { weeks.push(cur); cur = []; }
    cur.push(d);
  }
  if (cur.length) weeks.push(cur);
  const weekRows = weeks.map((w) => {
    const sc = Math.round(w.reduce((s, d) => s + d.overall, 0) / w.length);
    const bd = w.reduce((b, d) => (d.overall > b.overall ? d : b), w[0]);
    const ch = w.filter((d) => d.chandrashtama);
    const f = w.find((d) => fest[d.iso]);
    let headline = `${moodHeadline(moodFor(sc))} stretch; best day ${A.WEEKDAYS[isoWeekday(bd.iso)].slice(0, 3)} ${Number(bd.iso.slice(8))}`;
    if (f) headline += ` · ${fest[f.iso]}`;
    else if (ch.length) headline += ` · Chandrashtama ${Number(ch[0].iso.slice(8))}${ch.length > 1 ? `-${Number(ch[ch.length - 1].iso.slice(8))}` : ''}`;
    return { weekStart: w[0].iso, weekEnd: w[w.length - 1].iso, score: sc, headline: clip(headline, 90) };
  });

  // Key transits: slow planets + any planet that changes sign this month (shown after the change)
  const key = {};
  for (const p of ['Saturn', 'Jupiter', 'Rahu', 'Ketu']) key[p] = { tr: slow.tr[p], jd: midJd };
  const ingressEvents = events.filter((e) => e.type === 'ingress' || e.type === 'sankranti');
  for (const p of ['Mars', 'Sun', 'Venus', 'Mercury', 'Saturn', 'Jupiter', 'Rahu']) {
    const ing = ingressesBetween(p, days[0].jd, days[nDays - 1].jd + 1);
    if (!ing.length) continue;
    const jd = ing[ing.length - 1].jd + 0.01;
    const tr = transitsAt(ctx, jd);
    key[p] = { tr: tr[p], jd };
    if (p === 'Rahu') key.Ketu = { tr: tr.Ketu, jd };
  }
  const keyTransits = TRANSIT_ORDER.filter((p) => key[p]).map((p) => transitObject(ctx, key[p].tr, key[p].jd, true));

  const today = todayFor(ctx);
  const dashaMs = today >= first && today <= last ? ctx.nowMs : jdToMs(midJd);
  const caution = cautionDays(days, events, 10);
  const { best, worst } = bestWorst(scores);
  const s = strongestSlow(slow.tr);
  const bigEv = events.filter((e) => e.importance >= 2 && e.type !== 'chandrashtama');
  const headline = clip(bigEv.length
    ? `${moodHeadline(moodFor(overall))} month for ${I.AREA_LABEL[best]} · ${bigEv[0].title}`
    : `${moodHeadline(moodFor(overall))} month for your ${I.AREA_LABEL[best]}`, 90);
  const narrative = [
    `${ctx.firstName}, ${MONTH_NAMES[m - 1]} is shaped most by ${s.planet} in your ${ORD(s.hMoon)} from Moon ("${I.GOCHARA[s.planet][s.hMoon].theme}").`,
    `Your strongest area is ${I.AREA_LABEL[best]}. ${scores[best].reason}`,
    ingressEvents.length ? `Watch for ${ingressEvents.slice(0, 2).map((e) => `${e.title} (${Number(e.date.slice(8))} ${MONTH_NAMES[m - 1].slice(0, 3)})`).join(' and ')}.` : `${I.AREA_LABEL[worst].charAt(0).toUpperCase() + I.AREA_LABEL[worst].slice(1)} needs steady attention.`,
    `Your ${slow.dasha.md.lord}-${slow.dasha.ad.lord} dasha keeps ${I.DASHA_LORD[slow.dasha.ad.lord].keywords} in focus.`
  ].join(' ');
  return {
    type: 'month',
    month,
    monthName: `${MONTH_NAMES[m - 1]} ${y}`,
    ...baseFields(ctx),
    summary: { headline, narrative, mood: moodFor(overall), overallScore: overall },
    scores,
    days: days.map((d) => ({
      date: d.iso, score: d.overall, mood: d.mood, tithi: d.pe.tithi, moonSign: SIGNS[d.tr.Moon.sign],
      chandrashtama: d.chandrashtama, festival: fest[d.iso] || null, highlight: dayHighlight(d, fest[d.iso], eclByDate[d.iso])
    })),
    weeks: weekRows,
    keyTransits,
    events,
    bestDays: pickBestDays(days, 4),
    cautionDays: caution,
    dasha: dashaNow(ctx, dashaMs),
    remedy: remedyFor(scores, slow.drivers, slow.dasha)
  };
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------
// Merge segments: a short stint sandwiched between two stints of the same sign is absorbed
function cleanStints(segs, shortDays) {
  const s = segs.filter((x) => x.start !== null && x.end !== null).map((x) => ({ ...x, previews: [] }));
  let changed = true;
  while (changed) {
    changed = false;
    for (let i = 1; i < s.length - 1; i++) {
      if (s[i].end - s[i].start < shortDays && s[i - 1].sign === s[i + 1].sign) {
        const merged = {
          sign: s[i - 1].sign, start: s[i - 1].start, end: s[i + 1].end,
          previews: [...s[i - 1].previews, { sign: s[i].sign, start: s[i].start, end: s[i].end }, ...s[i + 1].previews]
        };
        s.splice(i - 1, 3, merged);
        changed = true;
        break;
      }
    }
  }
  return s;
}

function buildTimeline(ctx, fromIso, years, opts = {}) {
  const from = fromIso || isoAdd(todayFor(ctx), -730);
  const nYears = years || 6;
  const [fy, fm, fd] = from.split('-').map(Number);
  const to = new Date(Date.UTC(fy + nYears, fm - 1, fd)).toISOString().slice(0, 10);
  const msA = localMidnightMs(from, ctx.tz);
  const msB = localMidnightMs(to, ctx.tz);
  const jdA = msToJd(msA);
  const jdB = msToJd(msB);
  const now = todayFor(ctx);
  const nm = ctx.natal.moonSign;
  const iso = (jd) => localIso(jdToMs(jd), ctx.tz);
  const periods = [];
  const overlaps = (s, e) => e > jdA && s < jdB;
  const previewNote = (st) => (st.previews.length
    ? ` (Includes a brief preview of ${st.previews.map((p) => `${SIGNS[p.sign]} from ${iso(p.start)} to ${iso(p.end)}`).join(' and ')}.)`
    : '');
  const push = (p) => {
    p.current = p.start <= now && now < p.end;
    periods.push(p);
  };

  // Saturn: Sade Sati / Ashtama / Kantaka / other houses
  const sat = cleanStints(signSegments('Saturn', jdA - 3 * 365, jdB + 3 * 365), 200);
  for (let i = 0; i < sat.length; i++) {
    const st = sat[i];
    if (!overlaps(st.start, st.end)) continue;
    const h = houseFrom(st.sign, nm);
    const start = iso(st.start);
    const end = iso(st.end);
    const sign = SIGNS[st.sign];
    if ([12, 1, 2].includes(h)) {
      const phase = h === 12 ? 'Rising' : h === 1 ? 'Peak' : 'Setting';
      const t = I.SADE_SATI[phase];
      push({ id: `sade_sati-${start}`, kind: 'sade_sati', title: `Sade Sati — ${phase} phase (Saturn in ${sign})`, start, end, phase,
        effect: 'challenging', intensity: phase === 'Peak' ? 3 : 2, summary: t.summary + previewNote(st), realLife: t.realLife, advice: t.advice });
    } else if (h === 8) {
      const t = I.ASHTAMA_SHANI;
      push({ id: `ashtama_shani-${start}`, kind: 'ashtama_shani', title: `Ashtama Shani (Saturn in ${sign}, 8th from Moon)`, start, end, phase: null,
        effect: 'challenging', intensity: 3, summary: t.summary + previewNote(st), realLife: t.realLife, advice: t.advice });
    } else if ([4, 7, 10].includes(h)) {
      const t = I.KANTAKA_SHANI[h];
      push({ id: `kantaka_shani-${start}`, kind: 'kantaka_shani', title: `Kantaka Shani (Saturn in ${sign}, ${ORD(h)} from Moon)`, start, end, phase: null,
        effect: 'challenging', intensity: 2, summary: t.summary + previewNote(st), realLife: t.realLife, advice: t.advice });
    } else {
      const g = I.GOCHARA.Saturn[h];
      const good = I.GOCHARA_GOOD.Saturn.includes(h);
      push({ id: `saturn_transit-${start}`, kind: 'saturn_transit', title: `Saturn in ${sign} (${ORD(h)} from Moon)`, start, end, phase: null,
        effect: good ? 'favorable' : 'challenging', intensity: good ? 2 : 1, summary: `${g.theme}. ${g.meaning}${previewNote(st)}`, realLife: g.realLife, advice: g.doList });
    }
  }
  if (opts.saturnOnly) return { periods };
  // Jupiter
  for (const st of cleanStints(signSegments('Jupiter', jdA - 400, jdB + 400), 100)) {
    if (!overlaps(st.start, st.end)) continue;
    const h = houseFrom(st.sign, nm);
    const g = I.GOCHARA.Jupiter[h];
    const good = I.GOCHARA_GOOD.Jupiter.includes(h);
    const start = iso(st.start);
    push({ id: `jupiter_transit-${start}`, kind: 'jupiter_transit', title: `Jupiter in ${SIGNS[st.sign]} (${ORD(h)} from Moon)`, start, end: iso(st.end), phase: null,
      effect: good ? 'favorable' : 'challenging', intensity: good ? 2 : 1, summary: `${g.theme}. ${g.meaning}${previewNote(st)}`, realLife: g.realLife, advice: g.doList });
  }
  // Rahu / Ketu axis (mean node)
  for (const st of cleanStints(signSegments('Rahu', jdA - 600, jdB + 600), 60)) {
    if (!overlaps(st.start, st.end)) continue;
    const h = houseFrom(st.sign, nm);
    const k = (st.sign + 6) % 12;
    const hk = houseFrom(k, nm);
    const rGood = I.GOCHARA_GOOD.Rahu.includes(h);
    const kGood = I.GOCHARA_GOOD.Ketu.includes(hk);
    const start = iso(st.start);
    push({ id: `rahu_ketu-${start}`, kind: 'rahu_ketu', title: `Rahu in ${SIGNS[st.sign]} / Ketu in ${SIGNS[k]} (${ORD(h)}/${ORD(hk)} from Moon)`,
      start, end: iso(st.end), phase: null, effect: rGood ? 'favorable' : kGood ? 'neutral' : 'challenging', intensity: 2,
      summary: I.RAHU_KETU_AXIS[h],
      realLife: [...I.GOCHARA.Rahu[h].realLife.slice(0, 2), ...I.GOCHARA.Ketu[hk].realLife.slice(0, 2)],
      advice: uniq([...I.GOCHARA.Rahu[h].doList.slice(0, 2), ...I.GOCHARA.Ketu[hk].doList.slice(0, 2)]) });
  }
  // Dashas
  const effectOf = (lord) => {
    const s = (ctx.natal.info[lord] || { strength: 0 }).strength;
    return s > 0.3 ? 'favorable' : s < -0.3 ? 'challenging' : 'neutral';
  };
  for (const md of mahadashaList(ctx)) {
    if (md.end <= msA || md.start >= msB) continue;
    const t = I.dashaPeriodText('mahadasha', md.lord, ctx.natal.info, ctx.natal.houseBasis);
    const start = localIso(Math.max(md.start, ctx.natal.birthMs), ctx.tz);
    push({ id: `mahadasha-${start}`, kind: 'mahadasha', title: `${md.lord} Mahadasha`, start, end: localIso(md.end, ctx.tz), phase: null,
      effect: effectOf(md.lord), intensity: 3, summary: t.summary, realLife: t.realLife, advice: t.advice });
    for (const ad of subPeriods(md)) {
      if (ad.end <= msA || ad.start >= msB || ad.end <= ctx.natal.birthMs) continue;
      const ta = I.dashaPeriodText('antardasha', ad.lord, ctx.natal.info, ctx.natal.houseBasis);
      const s2 = localIso(Math.max(ad.start, ctx.natal.birthMs), ctx.tz);
      push({ id: `antardasha-${s2}`, kind: 'antardasha', title: `${md.lord}-${ad.lord} Antardasha`, start: s2, end: localIso(ad.end, ctx.tz), phase: null,
        effect: effectOf(ad.lord), intensity: 2, summary: I.dashaTheme(md.lord, ad.lord, ctx.natal.info, ctx.natal.houseBasis), realLife: ta.realLife, advice: ta.advice });
    }
  }
  const KIND_ORDER = ['mahadasha', 'antardasha', 'sade_sati', 'ashtama_shani', 'kantaka_shani', 'saturn_transit', 'jupiter_transit', 'rahu_ketu'];
  periods.sort((a, b) => (a.start < b.start ? -1 : a.start > b.start ? 1 : KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind)));
  return { type: 'timeline', ...baseFields(ctx), now, from, to, periods };
}

// Sade Sati status at an instant (for chat context)
function sadeSatiStatus(ctx, jd) {
  const tl = buildTimeline({ ...ctx, nowMs: jdToMs(jd) }, localIso(jdToMs(jd) - 4 * 365 * DAY_MS, ctx.tz), 8, { saturnOnly: true });
  const now = localIso(jdToMs(jd), ctx.tz);
  const cur = tl.periods.find((p) => ['sade_sati', 'ashtama_shani', 'kantaka_shani'].includes(p.kind) && p.start <= now && now < p.end);
  const nextSade = tl.periods.find((p) => p.kind === 'sade_sati' && p.start > now);
  return { current: cur || null, next: nextSade || null };
}

// ---------------------------------------------------------------------------
// Chat context (compact, cheap)
// ---------------------------------------------------------------------------
function chatContext(kundli, opts = {}) {
  const ctx = createContext(kundli, opts);
  const today = todayFor(ctx);
  const d = dayInfo(ctx, today);
  const dn = dashaNow(ctx, ctx.nowMs);
  const slowTxt = ['Saturn', 'Jupiter', 'Rahu', 'Ketu'].map((p) => {
    const t = d.tr[p];
    const span = spanDates(ctx, p, d.jd);
    return `${p} in ${SIGNS[t.sign]} = ${ORD(t.hMoon)} from Moon (${t.effect}: ${I.GOCHARA[p][t.hMoon].theme}${span.until ? `, until ${span.until}` : ''})`;
  }).join('; ');
  const ss = sadeSatiStatus(ctx, d.jd);
  const ssTxt = ss.current
    ? `${ss.current.title}, ${ss.current.start} to ${ss.current.end}`
    : `not active${ss.next ? `; next Sade Sati phase starts ${ss.next.start}` : ''}`;
  const ev = eventsBetween(ctx, today, isoAdd(today, 7), { minImportance: 2 })
    .slice(0, 8).map((e) => `${e.date} ${e.title}`).join('; ');
  const week = Array.from({ length: 7 }, (_, i) => dayInfo(ctx, isoAdd(today, i)));
  const best = week.reduce((b, x) => (x.overall > b.overall ? x : b), week[0]);
  const lines = [
    `=== TODAY FOR THIS USER (computed ${today}, ${ctx.tzName}; transits from natal Moon in ${SIGNS[ctx.natal.moonSign]}) ===`,
    `Dasha: ${dn.mahadasha} Mahadasha (to ${dn.mahadashaEnds}) / ${dn.antardasha} Antardasha (to ${dn.antardashaEnds}) / ${dn.pratyantardasha} Pratyantardasha (to ${dn.pratyantardashaEnds})`,
    `Moon today: ${SIGNS[d.tr.Moon.sign]}, ${NAKS[d.tr.Moon.nak]}, ${ORD(d.tr.Moon.hMoon)} from natal Moon; ${d.tara.name} Tara (${d.tara.favorable ? 'favourable' : 'unfavourable'}); Chandrashtama: ${d.chandrashtama ? 'YES' : 'no'}`,
    `Slow transits: ${slowTxt}`,
    `Saturn cycle: ${ssTxt}`,
    `Today's scores (0-100): overall ${d.overall}, career ${d.scores.career.score}, love ${d.scores.love.score}, money ${d.scores.money.score}, health ${d.scores.health.score}, mind ${d.scores.mind.score}`,
    `Next 7 days: best day ${best.iso}; chandrashtama days: ${week.filter((x) => x.chandrashtama).map((x) => x.iso).join(', ') || 'none'}`,
    `Events next 7 days: ${ev || 'none major'}`,
    'Use these computed facts when the user asks about today, this week or this month; do not invent other transits.'
  ];
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// AI narrative (optional rewrite of headline/narrative/focus only)
// ---------------------------------------------------------------------------
function narrativeFacts(payload) {
  const f = {
    period: payload.type,
    date: payload.date || payload.weekStart || payload.month,
    name: payload.profile && payload.profile.name,
    mood: payload.summary.mood,
    overallScore: payload.summary.overallScore,
    scores: Object.fromEntries(AREAS.map((a) => [a, { score: payload.scores[a].score, reason: payload.scores[a].reason }])),
    dasha: payload.dasha ? { mahadasha: payload.dasha.mahadasha, antardasha: payload.dasha.antardasha, pratyantardasha: payload.dasha.pratyantardasha } : null,
    rulesHeadline: payload.summary.headline,
    rulesNarrative: payload.summary.narrative
  };
  if (payload.moon) f.moon = { sign: payload.moon.sign, nakshatra: payload.moon.nakshatra, houseFromMoon: payload.moon.houseFromMoon, tara: payload.moon.taraBala.name, chandrashtama: payload.moon.chandrashtama };
  const tr = payload.transits || payload.keyTransits;
  if (tr) f.transits = tr.filter((t) => t.planet !== 'Moon').map((t) => `${t.title} (${t.effect})`);
  if (payload.events) f.events = payload.events.filter((e) => e.importance >= 2).slice(0, 8).map((e) => `${e.date}: ${e.title}`);
  if (payload.cautionDays) f.cautionDays = payload.cautionDays.slice(0, 5);
  if (payload.focus) f.rulesFocus = payload.focus;
  return f;
}

async function aiNarrative(payload, { timeoutMs = 9000 } = {}) {
  if (!hasOpenAIKey()) return null;
  const facts = narrativeFacts(payload);
  const wantsFocus = payload.type === 'week';
  const res = await chatCompletion({
    models: ['gpt-4o-mini', 'gpt-4o'],
    json: true,
    temperature: 0.6,
    maxTokens: 400,
    timeoutMs,
    messages: [
      { role: 'system', content: 'You are a warm, grounded Vedic astrologer writing a short personal forecast. Rewrite ONLY the headline and narrative' + (wantsFocus ? ' and focus' : '') + ' using strictly the facts in the JSON. Do not add planets, dates, events or predictions that are not in the facts. No fear-mongering, no medical, legal or financial guarantees, no emojis. Return JSON: {"headline": string (max 90 chars), "narrative": string (2-5 sentences, second person, use the first name exactly once)' + (wantsFocus ? ', "focus": string (one sentence)' : '') + '}.' },
      { role: 'user', content: JSON.stringify(facts) }
    ]
  });
  if (!res || typeof res !== 'object') return null;
  const headline = typeof res.headline === 'string' ? res.headline.trim() : '';
  const narrative = typeof res.narrative === 'string' ? res.narrative.trim() : '';
  if (!headline || !narrative || narrative.length > 1200) return null;
  const out = { headline: clip(headline, 90), narrative };
  if (wantsFocus && typeof res.focus === 'string' && res.focus.trim()) out.focus = res.focus.trim().slice(0, 300);
  return out;
}

function applyNarrative(payload, n) {
  if (!n) return payload;
  payload.summary = { ...payload.summary, headline: n.headline, narrative: n.narrative };
  if (n.focus && payload.type === 'week') payload.focus = n.focus;
  payload.generatedBy = 'ai';
  return payload;
}

module.exports = {
  ForecastError,
  createContext,
  natalFromKundli,
  buildDay,
  buildWeek,
  buildMonth,
  buildTimeline,
  chatContext,
  aiNarrative,
  applyNarrative,
  isValidIso,
  isoAdd,
  mondayOf,
  todayFor,
  // exposed for tests
  _internal: {
    taraNumber, dashaAt, mahadashaList, subPeriods, signSegments, ingressesBetween, stationsBetween,
    eclipsesBetween, eventsBetween, dayInfo, transitsAt, sadeSatiStatus, lunarMonthAt, observanceDays,
    msToJd, jdToMs, localMidnightMs, AREAS
  }
};
