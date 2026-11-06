// Muhurat finder (deterministic, no DB).
//
// For an event (griha pravesh, vehicle purchase, vivah, ...) and a date range, scores every day with the
// data-driven rules in data/muhurat_rules.json and returns the best 3 days with a clean daytime window.
//
// Day facts follow the app's daily Panchang (astrology_service.calculateDailyPanchangAndMuhurats):
//   - tithi / nakshatra / yoga / karana at local sunrise (udaya convention), Lahiri sidereal
//   - Rahu Kaal / Yamaganda / Gulika / choghadiya as the same eighths of daylight
//   - Abhijit = the 8th of 15 daytime muhurtas around local noon
// They are computed here with the same low-level helpers (instead of parsing the formatted strings the
// panchang endpoint returns) so windows are exact instants and moonrise/moonset (not needed) are skipped.
// Extra facts the finder needs: sidereal Sun sign (Kharmas), amanta lunar month + adhika (Chaturmas,
// Mala maas) via forecast_service's new-moon table, and the Moon sign (Chandrabala).
//
// Performance: one day costs 2 rise/set searches + a handful of body positions (~1 ms). Days are cached
// per (date, rounded location, tz) and shared across events; full results are cached for 6 h.

'use strict';

const sweph = require('sweph');
const A = require('./astrology_service');
const F = require('./forecast_service');
const RULES = require('../data/muhurat_rules.json');

const C = sweph.constants;
const DAY_MS = 86400000;
const HOUR_MS = 3600000;
const RESULT_TTL_MS = 6 * HOUR_MS;
const MAX_DAYS = 60;
const DEFAULT_DAYS = 30;
const DEFAULT_LAT = 28.6139;
const DEFAULT_LNG = 77.209;
const TOP_N = 3;

const W = RULES.weights;
const COMMON = RULES.common;
const EVENTS = RULES.events;
const EVENT_BY_ID = new Map(EVENTS.map((e) => [e.id, e]));

const NAKS = A.NAKSHATRAS;
const WEEKDAYS = A.WEEKDAYS;
const WEEKDAY_LORDS = A.WEEKDAY_LORDS;
const SAGITTARIUS = 8;
const PISCES = 11;

// Same eighth-of-day tables as calculateDailyPanchangAndMuhurats (Sunday first, 1-based segment)
const RAHU_SEG = [8, 2, 7, 5, 6, 4, 3];
const YAMA_SEG = [5, 4, 3, 2, 1, 7, 6];
const GULIKA_SEG = [7, 6, 5, 4, 3, 2, 1];
const CHOGHADIYA_CYCLE = [
  { name: 'Udveg', status: 'Avoid' },
  { name: 'Char', status: 'Neutral' },
  { name: 'Labh', status: 'Auspicious' },
  { name: 'Amrit', status: 'Best' },
  { name: 'Kaal', status: 'Avoid' },
  { name: 'Shubh', status: 'Auspicious' },
  { name: 'Rog', status: 'Avoid' }
];
const CHOGHADIYA_START = [0, 3, 6, 2, 5, 1, 4];

const TARA_NAMES = ['', 'Janma', 'Sampat', 'Vipat', 'Kshema', 'Pratyak', 'Sadhana', 'Naidhana', 'Mitra', 'Param Mitra'];
const TARA_GOOD = new Set([2, 4, 6, 8, 9]);
const TARA_BAD = new Set([3, 5, 7]);
const CHANDRA_GOOD = new Set([1, 3, 6, 7, 10, 11]);

const DISCLAIMER = 'Muhurat suggestions follow widely published Vedic panchang rules (tithi, nakshatra, weekday, yoga, '
  + 'Bhadra, Rahu Kaal) for your area. They are general guidance, not a guarantee, and do not replace your family '
  + 'tradition or a pandit who can also check the exact lagna and your Kundli. Customs vary by region.';

class MuhuratInputError extends Error {
  constructor(message, code = 'BAD_INPUT') {
    super(message);
    this.name = 'MuhuratInputError';
    this.statusCode = 400;
    this.code = code;
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
const pad2 = (n) => String(n).padStart(2, '0');
const msToJd = (ms) => ms / DAY_MS + 2440587.5;
const jdToMs = (jd) => (jd - 2440587.5) * DAY_MS;
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const round1 = (x) => Math.round(x * 10) / 10;

function isoAdd(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
function isValidIso(iso) {
  if (typeof iso !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false;
  const [y, m, d] = iso.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return y >= 1900 && y <= 2100 && t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}
function tzKey(tzDesc) {
  return tzDesc.type === 'iana' ? tzDesc.zone : `off${tzDesc.minutes}`;
}
function tithiLabel(n) {
  return A.panchangElements(0, (n - 1) * 12 + 0.5).tithi;
}
function tithiShort(n) {
  // "Shukla Paksha Panchami" -> "Panchami"
  return tithiLabel(n).replace(/^(Shukla|Krishna) Paksha /, '');
}

// ---------------------------------------------------------------------------
// Day facts (cached, shared across events)
// ---------------------------------------------------------------------------
const dayCache = new Map();
const DAY_CACHE_MAX = 20000;

function lunarContext() {
  return { newMoons: null };
}

function computeDay(iso, lat, lng, tzDesc, lunarCtx) {
  const key = `${iso}|${lat}|${lng}|${tzKey(tzDesc)}`;
  const hit = dayCache.get(key);
  if (hit) return hit;

  const [y, m, d] = iso.split('-').map(Number);
  const weekday = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  const midnight = A.localToUtcMs(y, m, d, 0, 0, 0, tzDesc);
  const jd0 = msToJd(midnight);
  let rise = A.riseSet(jd0, C.SE_SUN, 'rise', lat, lng);
  if (!Number.isFinite(rise) || rise > jd0 + 1) rise = jd0 + 0.25;
  let set = A.riseSet(rise, C.SE_SUN, 'set', lat, lng);
  if (!Number.isFinite(set) || set > rise + 1) set = rise + 0.5;
  const sunriseMs = jdToMs(rise);
  const sunsetMs = jdToMs(set);

  const sun = A.calcBody(rise, C.SE_SUN).long;
  const moon = A.calcBody(rise, C.SE_MOON).long;
  const pe = A.panchangElements(sun, moon);
  const lunar = F._internal.lunarMonthAt(lunarCtx, rise);

  const part = (sunsetMs - sunriseMs) / 8;
  const seg = (n) => ({ start: sunriseMs + (n - 1) * part, end: sunriseMs + n * part, n });
  const midday = (sunriseMs + sunsetMs) / 2;
  const muhurta = (sunsetMs - sunriseMs) / 15;
  const choghadiya = [];
  for (let i = 0; i < 8; i++) {
    const c = CHOGHADIYA_CYCLE[(CHOGHADIYA_START[weekday] + i) % 7];
    choghadiya.push({ ...seg(i + 1), name: c.name, status: c.status });
  }

  const day = {
    iso,
    weekday,
    sunriseMs,
    sunsetMs,
    tithiNumber: pe.tithiNumber,
    tithi: pe.tithi,
    paksha: pe.paksha,
    nakshatra: pe.nakshatra,
    nakshatraIndex: pe.nakshatraIndex,
    yoga: pe.yoga,
    karana: pe.karana,
    sunSign: A.signIndexOf(sun),
    moonSign: A.signIndexOf(moon),
    lunarMonth: lunar.month,
    lunarMonthName: lunar.name,
    adhika: !!lunar.adhika,
    rahu: seg(RAHU_SEG[weekday]),
    yama: seg(YAMA_SEG[weekday]),
    gulika: seg(GULIKA_SEG[weekday]),
    abhijit: { start: midday - muhurta / 2, end: midday + muhurta / 2 },
    choghadiya
  };
  if (dayCache.size >= DAY_CACHE_MAX) dayCache.delete(dayCache.keys().next().value);
  dayCache.set(key, day);
  return day;
}

// Moon/Sun derived elements at an instant (used to check the chosen window)
function elementsAt(ms) {
  const jd = msToJd(ms);
  return A.panchangElements(A.calcBody(jd, C.SE_SUN).long, A.calcBody(jd, C.SE_MOON).long);
}

// Amanta months: 3 = Ashadha, 7 = Kartika. Chaturmas runs Ashadha Shukla 11 -> Kartika Shukla 11 (exclusive).
function inChaturmas(day) {
  const m = day.lunarMonth;
  if (m === null || m === undefined) return false;
  if (m === 3) return day.tithiNumber >= 11;
  if (m === 4 || m === 5 || m === 6) return true;
  if (m === 7) return day.tithiNumber < 11;
  return false;
}

// ---------------------------------------------------------------------------
// Rules and scoring
// ---------------------------------------------------------------------------

/** Reasons that remove a day for this event entirely (empty = allowed). */
function hardAvoidReasons(rule, day) {
  const out = [];
  if (day.tithiNumber === COMMON.amavasya) out.push('Amavasya');
  if (rule.avoidRikta && COMMON.riktaTithis.includes(day.tithiNumber)) out.push('Rikta tithi');
  if (rule.avoidBhadra && /^Vishti/.test(day.karana)) out.push('Bhadra (Vishti karana)');
  if (COMMON.badYogasHard.includes(day.yoga)) out.push(`${day.yoga} yoga`);
  if (rule.avoidKharmas && (day.sunSign === SAGITTARIUS || day.sunSign === PISCES)) out.push('Kharmas');
  if (rule.avoidChaturmas && inChaturmas(day)) out.push('Chaturmas');
  if (rule.avoidAdhika && day.adhika) out.push('Adhika (Mala) maas');
  return out;
}

const AVOID_TEXT = {
  Amavasya: 'Amavasya (new Moon) is avoided for auspicious starts',
  'Rikta tithi': 'Rikta tithis (Chaturthi, Navami, Chaturdashi) are traditionally "empty" for new beginnings',
  'Bhadra (Vishti karana)': 'Bhadra (Vishti karana) at sunrise is avoided for auspicious work',
  Kharmas: 'Kharmas: the Sun is in Sagittarius or Pisces, a pause for ceremonies',
  Chaturmas: 'Chaturmas (Devshayani to Devutthana Ekadashi): no vivah, griha pravesh or mundan',
  'Adhika (Mala) maas': 'Adhika (Mala) maas is avoided for samskaras'
};

/**
 * Scores one day. Returns { score, reasons:[{w,text}], cautions:[] } (personal factor optional).
 * personal: { birthNakIndex, moonSignIndex } or null.
 */
function scoreDay(rule, day, personal) {
  let score = W.base;
  const reasons = [];
  const cautions = [];
  const add = (w, text) => {
    score += w;
    if (text) reasons.push({ w, text });
  };

  // Nakshatra (most important)
  if (rule.goodNakshatras.includes(day.nakshatra)) {
    add(W.nakshatraGood, (rule.nakReasons || '{n} nakshatra is favourable').replace('{n}', day.nakshatra));
  } else if (COMMON.ugraTikshnaNakshatras.includes(day.nakshatra)) {
    score += W.nakshatraBad;
    cautions.push(`${day.nakshatra} is a fierce/sharp nakshatra, usually not chosen for this`);
  }

  // Tithi
  const t = day.tithiNumber;
  const goodTithis = rule.goodTithis || COMMON.goodTithis;
  if (goodTithis.includes(t)) add(W.tithiGood, `${tithiShort(t)} is a favourable tithi`);
  else if (t === 30 || COMMON.riktaTithis.includes(t) || [6, 8, 12, 21, 23, 27].includes(t)) score += W.tithiBad;

  // Paksha
  if (day.paksha === 'Shukla') add(W.shuklaPaksha, 'Shukla paksha: the Moon is growing');
  else if (t >= 26) {
    score += W.krishnaLate;
    cautions.push('Late Krishna paksha: the Moon is waning');
  } else if (t <= 20) score += W.krishnaEarly;

  // Weekday
  if (rule.goodWeekdays.includes(day.weekday)) {
    add(W.weekdayGood, `${WEEKDAYS[day.weekday]} (ruled by ${WEEKDAY_LORDS[day.weekday]}) suits this`);
  } else if ((rule.avoidWeekdays || []).includes(day.weekday)) {
    score += W.weekdayBad;
    cautions.push(`${WEEKDAYS[day.weekday]} is not a preferred weekday for this`);
  }

  // Yoga
  if (COMMON.goodYogas.includes(day.yoga)) add(W.yogaGood, `${day.yoga} yoga adds auspiciousness`);
  else if (COMMON.badYogasSoft.includes(day.yoga)) {
    score += W.yogaBad;
    cautions.push(`${day.yoga} yoga is considered inauspicious; keep the start within the suggested window`);
  }

  // Special combinations (e.g. Guru Pushya)
  for (const s of rule.specials || []) {
    if (s.nakshatra === day.nakshatra && s.weekdays.includes(day.weekday)) {
      add(W.special, s.reason.replace('{w}', WEEKDAYS[day.weekday]));
    }
  }

  // Personal factor: Tarabala (from birth nakshatra) + Chandrabala (from natal Moon sign)
  if (personal) {
    if (Number.isInteger(personal.birthNakIndex)) {
      const tara = (((day.nakshatraIndex - personal.birthNakIndex + 27) % 27) % 9) + 1;
      if (TARA_GOOD.has(tara)) add(W.taraGood, `${TARA_NAMES[tara]} Tara from your birth star is supportive`);
      else if (TARA_BAD.has(tara)) {
        score += W.taraBad;
        cautions.push(`${TARA_NAMES[tara]} Tara from your birth star: not ideal for you personally`);
      }
    }
    if (Number.isInteger(personal.moonSignIndex)) {
      const house = ((day.moonSign - personal.moonSignIndex + 12) % 12) + 1;
      if (house === 8) {
        score += W.chandrashtama;
        cautions.push('Chandrashtama: the Moon is 8th from your Moon sign today');
      } else if (CHANDRA_GOOD.has(house)) add(W.chandraGood, 'Good day for your Moon sign (Chandrabala)');
    }
  }

  return { score: Math.round(clamp(score, 0, 100)), reasons, cautions };
}

// ---------------------------------------------------------------------------
// Best window: Abhijit when clean (not Wednesday, by tradition), else the best daytime choghadiya
// that is not Rahu Kaal / Yamaganda / Gulika and not under Bhadra.
// ---------------------------------------------------------------------------
const overlaps = (a, b) => a.start < b.end && b.start < a.end;

function bestWindow(rule, day, tzDesc) {
  const blocked = [day.rahu, day.yama, day.gulika];
  const free = (w) => !blocked.some((b) => overlaps(w, b));
  const cands = [];
  if (day.weekday !== 3 && free(day.abhijit)) cands.push({ ...day.abhijit, label: 'Abhijit Muhurat', p: 0 });
  const rank = { Best: 1, Auspicious: 2, Neutral: rule.allowChar ? 3 : 9 };
  for (const c of day.choghadiya) {
    const p = rank[c.status];
    if (p === undefined || p > 3) continue;
    if (!free(c)) continue;
    cands.push({ start: c.start, end: c.end, label: `${c.name} choghadiya`, p });
  }
  cands.sort((a, b) => a.p - b.p || a.start - b.start);
  let chosen = null;
  for (const w of cands) {
    if (rule.avoidBhadra) {
      const mid = elementsAt((w.start + w.end) / 2);
      if (/^Vishti/.test(mid.karana)) continue;
    }
    chosen = w;
    break;
  }
  if (!chosen) return null;
  return {
    start: A.formatClock(chosen.start, tzDesc),
    end: A.formatClock(chosen.end, tzDesc),
    label: chosen.label,
    startUtc: new Date(chosen.start).toISOString(),
    endUtc: new Date(chosen.end).toISOString(),
    _start: chosen.start,
    _end: chosen.end
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
function listEvents() {
  return EVENTS.map((e) => ({
    id: e.id,
    label: e.label,
    labelHi: e.labelHi,
    icon: e.icon,
    category: e.category,
    note: e.note || null
  }));
}

function parseNum(v, label, min, max) {
  if (v === undefined || v === null || v === '') return null;
  const n = typeof v === 'number' ? v : Number(String(v).trim());
  if (!Number.isFinite(n) || n < min || n > max) throw new MuhuratInputError(`${label} must be a number between ${min} and ${max}`);
  return n;
}

/** Validates/normalises query input. Location is rounded to 0.1 deg (~11 km) for caching and privacy. */
function normaliseQuery(q = {}) {
  const eventId = typeof q.event === 'string' ? q.event.trim() : '';
  if (!eventId) throw new MuhuratInputError('event is required', 'EVENT_REQUIRED');
  const rule = EVENT_BY_ID.get(eventId);
  if (!rule) throw new MuhuratInputError(`Unknown event "${eventId.slice(0, 40)}"`, 'UNKNOWN_EVENT');

  const latIn = parseNum(q.lat, 'lat', -66, 66);
  const lngIn = parseNum(q.lng, 'lng', -180, 180);
  if ((latIn === null) !== (lngIn === null)) throw new MuhuratInputError('lat and lng must be given together');
  const lat = round1(latIn === null ? DEFAULT_LAT : latIn);
  const lng = round1(lngIn === null ? DEFAULT_LNG : lngIn);

  let tzDesc;
  const tzRaw = typeof q.tz === 'string' && q.tz.trim() ? q.tz.trim() : A.timezoneForLocation(undefined, lat, lng);
  try {
    tzDesc = A.resolveTimeZone(tzRaw);
  } catch (e) {
    throw new MuhuratInputError(e.message);
  }

  let days = DEFAULT_DAYS;
  if (q.days !== undefined && q.days !== null && q.days !== '') {
    const n = Number(q.days);
    if (!Number.isInteger(n) || n < 1) throw new MuhuratInputError('days must be a whole number from 1 to 60');
    days = Math.min(n, MAX_DAYS);
  }

  const nowMs = Number.isFinite(q.nowMs) ? q.nowMs : Date.now();
  let from = typeof q.from === 'string' && q.from.trim() ? q.from.trim() : null;
  if (from === null) {
    const p = A.utcToLocalParts(nowMs, tzDesc);
    from = `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
  } else if (!isValidIso(from)) {
    throw new MuhuratInputError('from must be a date in YYYY-MM-DD format');
  }
  return { rule, lat, lng, tzDesc, tzName: tzDesc.type === 'iana' ? tzDesc.zone : tzRaw, from, days };
}

const resultCache = new Map();
const RESULT_CACHE_MAX = 500;

/** All days scored without the personal factor (cached 6 h). */
function scoredRange(n, nowMs = Date.now()) {
  const key = `${n.rule.id}|${n.from}|${n.days}|${n.lat}|${n.lng}|${tzKey(n.tzDesc)}`;
  const hit = resultCache.get(key);
  if (hit && nowMs - hit.at < RESULT_TTL_MS) return { ...hit.value, cached: true };

  const lunarCtx = lunarContext();
  const days = [];
  for (let i = 0; i < n.days; i++) {
    const iso = isoAdd(n.from, i);
    days.push(computeDay(iso, n.lat, n.lng, n.tzDesc, lunarCtx));
  }
  const value = { key, days };
  if (resultCache.size >= RESULT_CACHE_MAX) resultCache.delete(resultCache.keys().next().value);
  resultCache.set(key, { at: nowMs, value });
  return { ...value, cached: false };
}

function personalFromKundli(row) {
  if (!row) return null;
  const nakName = String(row.nakshatra || '').trim();
  const birthNakIndex = NAKS.findIndex((x) => x.toLowerCase() === nakName.toLowerCase());
  const moonName = String(row.moon_sign || row.moonSign || '').split(' ')[0];
  const moonSignIndex = A.ZODIAC_SIGNS.findIndex((x) => x.toLowerCase() === moonName.toLowerCase());
  if (birthNakIndex < 0 && moonSignIndex < 0) return null;
  return {
    birthNakIndex: birthNakIndex >= 0 ? birthNakIndex : null,
    moonSignIndex: moonSignIndex >= 0 ? moonSignIndex : null
  };
}

/**
 * Finds the best days.
 * @param {object} query { event, lat, lng, tz, from, days }
 * @param {object} [opts] { personal: {birthNakIndex, moonSignIndex} | null, nowMs }
 */
function findMuhurat(query, opts = {}) {
  const n = normaliseQuery({ ...query, nowMs: opts.nowMs });
  const { rule, tzDesc } = n;
  const range = scoredRange(n, opts.nowMs);
  const personal = opts.personal || null;

  const avoidedMap = new Map();
  const candidates = [];
  for (const day of range.days) {
    const hard = hardAvoidReasons(rule, day);
    if (hard.length) {
      for (const r of hard) {
        const a = avoidedMap.get(r) || { reason: r, text: AVOID_TEXT[r] || `${r} is avoided`, count: 0, dates: [] };
        a.count += 1;
        a.dates.push(day.iso);
        avoidedMap.set(r, a);
      }
      continue;
    }
    const s = scoreDay(rule, day, personal);
    candidates.push({ day, ...s });
  }
  // Highest score first; ties -> earlier date
  candidates.sort((a, b) => b.score - a.score || (a.day.iso < b.day.iso ? -1 : 1));

  const results = [];
  for (const c of candidates) {
    if (results.length >= TOP_N) break;
    const win = bestWindow(rule, c.day, tzDesc);
    if (!win) continue;
    const cautions = [...c.cautions];
    // Udaya-tithi convention: the nakshatra may change before the suggested window
    const at = elementsAt((win._start + win._end) / 2);
    if (at.nakshatra !== c.day.nakshatra) {
      cautions.push(`The Moon moves into ${at.nakshatra} before this window; confirm the exact time locally`);
    }
    const reasons = c.reasons.sort((a, b) => b.w - a.w).slice(0, 4).map((r) => r.text);
    if (reasons.length < 2) reasons.push('No major dosha (Amavasya, Bhadra, Rikta) on this day');
    delete win._start;
    delete win._end;
    results.push({
      date: c.day.iso,
      weekday: WEEKDAYS[c.day.weekday],
      score: c.score,
      tithi: c.day.tithi,
      paksha: c.day.paksha,
      nakshatra: c.day.nakshatra,
      yoga: c.day.yoga,
      karana: c.day.karana,
      lunarMonth: c.day.lunarMonthName,
      sunrise: A.formatClock(c.day.sunriseMs, tzDesc),
      sunset: A.formatClock(c.day.sunsetMs, tzDesc),
      rahuKaal: `${A.formatClock(c.day.rahu.start, tzDesc)} - ${A.formatClock(c.day.rahu.end, tzDesc)}`,
      bestWindow: win,
      reasons,
      cautions
    });
  }

  const avoided = [...avoidedMap.values()].sort((a, b) => b.count - a.count);
  return {
    event: { id: rule.id, label: rule.label, labelHi: rule.labelHi, icon: rule.icon, note: rule.note || null },
    from: n.from,
    to: isoAdd(n.from, n.days - 1),
    days: n.days,
    location: { lat: n.lat, lng: n.lng, timezone: n.tzName },
    personal: !!personal,
    results,
    avoided,
    consideredDays: range.days.length,
    eligibleDays: candidates.length,
    message: results.length ? null : 'No clearly auspicious day in this range for this event. Try a longer range or ask a pandit.',
    disclaimer: DISCLAIMER,
    cached: range.cached
  };
}

function _resetCaches() {
  dayCache.clear();
  resultCache.clear();
}

module.exports = {
  MuhuratInputError,
  listEvents,
  findMuhurat,
  personalFromKundli,
  normaliseQuery,
  DISCLAIMER,
  MAX_DAYS,
  RULES,
  _internal: { computeDay, scoreDay, hardAvoidReasons, bestWindow, inChaturmas, lunarContext, tithiLabel, _resetCaches, dayCache, resultCache }
};
