// Puja & vrat guides: content (data/puja_guides.json) + next observance date.
//
// Each guide's `when.rule` says how to find its next date:
//   { type: 'lunar',   month, tithi, kaal }  amanta month (0 = Chaitra .. 11 = Phalguna) + tithi (1..30)
//                                            observed at kaal (sunrise | madhyahna | aparahna | pradosh | nishita)
//   { type: 'tithi',   tithis: [..], kaal }  any month (Ekadashi, Purnima)
//   { type: 'weekday', weekdays: [..] }      0 = Sunday .. 6 = Saturday (Somvar vrat, Hanuman puja)
// Lunar rules reuse forecast_service's observance logic (vriddhi / kshaya tithi handling, adhika months
// skipped) with a kundli-free context, so dates match the festival dates the app shows elsewhere.

'use strict';

const A = require('./astrology_service');
const F = require('./forecast_service');
const GUIDES = require('../data/puja_guides.json');

const DAY_MS = 86400000;
const CACHE_TTL_MS = 12 * 3600000;
const SCAN_DAYS = 400;
const LIST_FIELDS = ['id', 'title', 'titleHi', 'deity', 'category', 'image', 'duration', 'difficulty', 'overview'];

const BY_ID = new Map(GUIDES.guides.map((g) => [g.id, g]));

const pad2 = (n) => String(n).padStart(2, '0');
function isoAdd(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
function isoWeekday(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

/** Minimal context accepted by forecast_service's anchor / kaal / observance helpers (no Kundli needed). */
function calendarContext(lat, lng, tzName) {
  const tz = A.resolveTimeZone(tzName);
  return {
    lat, lng, latRS: Math.max(-65.5, Math.min(65.5, lat)), tz, tzName,
    anchors: new Map(), kaal: new Map(), newMoons: null
  };
}

function todayIn(tzName, nowMs) {
  const p = A.utcToLocalParts(nowMs, A.resolveTimeZone(tzName));
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
}

function localIso(ms, tz) {
  const p = A.utcToLocalParts(ms, tz);
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
}

// Day lists covering each (non-adhika) amanta month `month` from today on. Uses the context's new-moon
// table built by forecast_service.lunarMonthAt (entries { jd, sunSign }; month = sunSign + 1, adhika when
// two consecutive new moons share the Sun sign - the same rule lunarMonthAt applies).
function monthSpans(ctx, today, month) {
  const jdToday = F._internal.msToJd(Date.parse(`${today}T00:00:00Z`));
  // Two calls so the table is built once for the whole scan range (each call only extends it).
  F._internal.lunarMonthAt(ctx, jdToday);
  F._internal.lunarMonthAt(ctx, jdToday + SCAN_DAYS);
  const list = (ctx.newMoons && ctx.newMoons.list) || [];
  const spans = [];
  for (let i = 0; i + 1 < list.length; i++) {
    const s = list[i].sunSign;
    if ((s + 1) % 12 !== month || list[i + 1].sunSign === s) continue;
    const startIso = localIso(F._internal.jdToMs(list[i].jd), ctx.tz);
    const endIso = localIso(F._internal.jdToMs(list[i + 1].jd), ctx.tz);
    if (endIso < today) continue;
    const days = [];
    for (let iso = isoAdd(startIso, -1); iso <= isoAdd(endIso, 1); iso = isoAdd(iso, 1)) days.push(iso);
    spans.push(days);
  }
  return spans;
}

function nextDatesFor(guide, ctx, today, count = 2) {
  const rule = guide.when && guide.when.rule;
  if (!rule) return [];
  if (rule.type === 'weekday') {
    const out = [];
    for (let i = 0; i < 14 && out.length < count; i++) {
      const iso = isoAdd(today, i);
      if (rule.weekdays.includes(isoWeekday(iso))) out.push(iso);
    }
    return out;
  }
  const tithis = rule.type === 'lunar' ? [rule.tithi] : rule.tithis;
  const month = rule.type === 'lunar' ? rule.month : null;
  const kaal = rule.kaal || 'sunrise';
  const found = new Set();
  if (month !== null) {
    // Month-specific festival: only scan the days of that amanta month (from the new-moon table), so a
    // festival 10 months away costs ~35 sunrise/sunset searches instead of ~300.
    for (const span of monthSpans(ctx, today, month)) {
      if (found.size >= count) break;
      for (const o of F._internal.observanceDays(ctx, span, tithis[0], kaal, month)) {
        if (o.iso >= today) found.add(o.iso);
      }
    }
    return [...found].sort().slice(0, count);
  }
  // Any-month tithi: scan in 40-day chunks (2 days of overlap for vriddhi/kshaya) until enough dates are found.
  for (let start = 0; start < SCAN_DAYS && found.size < count; start += 38) {
    const isoList = [];
    for (let i = Math.max(-1, start - 1); i < start + 40; i++) isoList.push(isoAdd(today, i));
    for (const T of tithis) {
      for (const o of F._internal.observanceDays(ctx, isoList, T, kaal, month)) {
        if (o.iso >= today) found.add(o.iso);
      }
    }
  }
  return [...found].sort().slice(0, count);
}

const cache = new Map();

/**
 * Next observance dates for every guide (cached 12 h per day + rounded location).
 * @returns {Map<string, string[]>} guideId -> ['YYYY-MM-DD', ...]
 */
function upcomingDates({ lat = 28.6139, lng = 77.209, tz, nowMs = Date.now() } = {}) {
  const latR = Math.round(lat * 10) / 10;
  const lngR = Math.round(lng * 10) / 10;
  const tzName = tz || A.timezoneForLocation(undefined, latR, lngR);
  const today = todayIn(tzName, nowMs);
  const key = `${today}|${latR}|${lngR}|${tzName}`;
  const hit = cache.get(key);
  if (hit && nowMs - hit.at < CACHE_TTL_MS) return hit.value;
  const ctx = calendarContext(latR, lngR, tzName);
  const value = new Map();
  for (const g of GUIDES.guides) value.set(g.id, nextDatesFor(g, ctx, today));
  if (cache.size > 200) cache.clear();
  cache.set(key, { at: nowMs, value });
  return value;
}

function listGuides(dates) {
  return GUIDES.guides.map((g) => {
    const o = {};
    for (const f of LIST_FIELDS) o[f] = g[f] === undefined ? null : g[f];
    o.when = { text: g.when.text, festivalKey: g.when.festivalKey || null };
    o.isVrat = !!g.vratRules;
    o.nextDate = dates ? (dates.get(g.id) || [])[0] || null : null;
    return o;
  });
}

function getGuide(id, dates) {
  const g = BY_ID.get(id);
  if (!g) return null;
  const next = dates ? dates.get(id) || [] : [];
  return { ...g, nextDate: next[0] || null, nextDates: next };
}

module.exports = {
  GUIDES,
  listGuides,
  getGuide,
  upcomingDates,
  _internal: { nextDatesFor, calendarContext, cache, DAY_MS }
};
