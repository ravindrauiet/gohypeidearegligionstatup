// Personal forecast engine: astronomy sanity checks + API contract shapes. Run: npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const A = require('../services/astrology_service');
const F = require('../services/forecast_service');
const I = require('../services/forecast_interpretations');

const NOW = Date.parse('2026-10-07T06:00:00Z');
const DELHI = { lat: 28.61, lng: 77.21 };

function chart(dob, tob, lat = DELHI.lat, lng = DELHI.lng, opts = {}) {
  const k = A.calculateKundli(dob, tob, 'Test', lat, lng, undefined, opts);
  k.birthDetails = { fullName: 'Asha Rao', latitude: lat, longitude: lng };
  return k;
}
// Synthetic chart with a chosen natal Moon longitude (everything else from a real chart)
function chartWithMoon(moonLong) {
  const k = chart('1990-05-15', '06:30');
  k.moonLongitude = moonLong;
  k.planetaryPositions = k.planetaryPositions.map((p) => (p.name.startsWith('Moon') ? { ...p, longitude: moonLong } : p));
  return k;
}
const ctxFor = (k, extra = {}) => F.createContext(k, { nowMs: NOW, ...extra });

// ---------------------------------------------------------------------------
// Contract shape helpers
// ---------------------------------------------------------------------------
const ISO = /^\d{4}-\d{2}-\d{2}$/;
const CLOCK = /^\d{2}:\d{2} (AM|PM)$/;
const MOODS = ['excellent', 'good', 'mixed', 'challenging'];
const EFFECTS = ['favorable', 'neutral', 'challenging'];
const LABELS = ['Strong', 'Good', 'Steady', 'Careful', 'Difficult'];
const EVENT_TYPES = ['ingress', 'retrograde', 'direct', 'solar_eclipse', 'lunar_eclipse', 'full_moon', 'new_moon',
  'ekadashi', 'sankranti', 'dasha_change', 'chandrashtama', 'festival'];
const PLANETS = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];
const isStr = (x) => typeof x === 'string' && x.length > 0;
const isInt = (x, lo, hi) => Number.isInteger(x) && x >= lo && x <= hi;

function checkCommon(p) {
  assert.equal(typeof p.profile, 'object');
  assert.ok(isStr(p.profile.name));
  assert.equal(typeof p.profile.isFamily, 'boolean');
  assert.ok(p.profile.familyId === null || Number.isInteger(p.profile.familyId));
  assert.ok(p.profile.relationship === null || typeof p.profile.relationship === 'string');
  assert.equal(typeof p.birthTimeKnown, 'boolean');
  assert.ok(p.accuracyNote === null || isStr(p.accuracyNote));
  assert.ok(['ai', 'rules'].includes(p.generatedBy));
}
function checkSummary(s) {
  assert.ok(isStr(s.headline) && s.headline.length <= 90, `headline: ${s.headline}`);
  assert.ok(isStr(s.narrative));
  assert.ok(MOODS.includes(s.mood));
  assert.ok(isInt(s.overallScore, 0, 100));
}
function checkScores(sc) {
  for (const a of ['career', 'love', 'money', 'health', 'mind']) {
    assert.ok(isInt(sc[a].score, 0, 100), a);
    assert.ok(LABELS.includes(sc[a].label));
    assert.ok(isStr(sc[a].reason));
  }
}
function checkTransit(t) {
  assert.ok(PLANETS.includes(t.planet));
  assert.ok(A.ZODIAC_SIGNS.includes(t.sign));
  assert.ok(typeof t.degree === 'number' && t.degree >= 0 && t.degree < 30);
  assert.ok(A.NAKSHATRAS.includes(t.nakshatra));
  assert.equal(typeof t.retrograde, 'boolean');
  assert.ok(isInt(t.houseFromMoon, 1, 12) && isInt(t.houseFromLagna, 1, 12));
  assert.ok(EFFECTS.includes(t.effect));
  assert.ok(isStr(t.title) && isStr(t.meaning));
  assert.ok(Array.isArray(t.realLife) && t.realLife.length >= 3 && t.realLife.length <= 5);
  assert.ok(Array.isArray(t.doList) && Array.isArray(t.avoidList));
  assert.ok(t.since === null || ISO.test(t.since));
  assert.ok(t.until === null || ISO.test(t.until));
}
function checkEvent(e) {
  assert.ok(ISO.test(e.date));
  assert.ok(e.time === null || CLOCK.test(e.time), e.time);
  assert.ok(EVENT_TYPES.includes(e.type), e.type);
  assert.ok(isStr(e.title) && isStr(e.description) && isStr(e.personalImpact));
  assert.ok([1, 2, 3].includes(e.importance));
}
function checkDasha(d) {
  for (const k of ['mahadasha', 'antardasha', 'pratyantardasha']) assert.ok(PLANETS.includes(d[k]));
  for (const k of ['mahadashaEnds', 'antardashaEnds', 'pratyantardashaEnds']) assert.ok(ISO.test(d[k]));
  assert.ok(isStr(d.theme));
}
function checkRemedy(r) {
  for (const k of ['title', 'mantra', 'action', 'color']) assert.ok(isStr(r[k]));
  assert.ok(r.day === null || isStr(r.day));
}
function checkBestDays(b) {
  for (const k of ['career', 'love', 'money', 'travel', 'newBeginnings']) {
    assert.ok(Array.isArray(b[k]));
    b[k].forEach((d) => assert.ok(ISO.test(d)));
  }
}
function checkDayPayload(p) {
  assert.equal(p.type, 'day');
  assert.ok(ISO.test(p.date) && isStr(p.weekday));
  checkCommon(p); checkSummary(p.summary); checkScores(p.scores);
  const m = p.moon;
  assert.ok(A.ZODIAC_SIGNS.includes(m.sign) && A.NAKSHATRAS.includes(m.nakshatra));
  assert.ok(isInt(m.houseFromMoon, 1, 12) && isInt(m.houseFromLagna, 1, 12));
  assert.ok(isStr(m.taraBala.name) && isInt(m.taraBala.number, 1, 9) && typeof m.taraBala.favorable === 'boolean' && isStr(m.taraBala.meaning));
  assert.equal(typeof m.chandraBala, 'boolean');
  assert.equal(typeof m.chandrashtama, 'boolean');
  assert.ok(m.changesSignAt === null || CLOCK.test(m.changesSignAt));
  assert.ok(m.nextSign === null || A.ZODIAC_SIGNS.includes(m.nextSign));
  checkDasha(p.dasha);
  assert.deepEqual(p.transits.map((t) => t.planet), ['Saturn', 'Jupiter', 'Rahu', 'Ketu', 'Mars', 'Sun', 'Venus', 'Mercury', 'Moon']);
  p.transits.forEach(checkTransit);
  assert.ok(p.aspects.length <= 6);
  p.aspects.forEach((a) => {
    assert.ok(PLANETS.includes(a.transitPlanet) && PLANETS.includes(a.natalPlanet));
    assert.ok(['conjunction', 'opposition', 'trine', 'square', 'sextile'].includes(a.aspect));
    assert.ok(a.orb >= 0 && a.orb <= 3);
    assert.ok(EFFECTS.includes(a.effect) && isStr(a.meaning));
  });
  p.events.forEach(checkEvent);
  p.events.forEach((e) => assert.equal(e.date, p.date));
  assert.ok(p.panchang && isStr(p.panchang.tithi) && Array.isArray(p.panchang.choghadiya));
  assert.ok(p.goodFor.length >= 3 && p.goodFor.length <= 5);
  assert.ok(p.avoid.length >= 3 && p.avoid.length <= 5);
  assert.ok(p.bestTimes.length >= 1 && p.bestTimes.length <= 4);
  p.bestTimes.forEach((b) => assert.ok(isStr(b.label) && CLOCK.test(b.start) && CLOCK.test(b.end) && isStr(b.reason)));
  checkRemedy(p.remedy);
  assert.ok(isStr(p.luckyColor) && isInt(p.luckyNumber, 1, 9));
}
function checkWeekPayload(p) {
  assert.equal(p.type, 'week');
  assert.ok(ISO.test(p.weekStart) && ISO.test(p.weekEnd));
  assert.equal(new Date(`${p.weekStart}T00:00:00Z`).getUTCDay(), 1, 'week starts Monday');
  checkCommon(p); checkSummary(p.summary); checkScores(p.scores);
  assert.equal(p.days.length, 7);
  p.days.forEach((d) => {
    assert.ok(ISO.test(d.date) && isStr(d.weekday) && isInt(d.score, 0, 100) && MOODS.includes(d.mood));
    assert.ok(A.ZODIAC_SIGNS.includes(d.moonSign) && typeof d.taraBala === 'string' && typeof d.taraFavorable === 'boolean');
    assert.equal(typeof d.chandrashtama, 'boolean');
    assert.ok(isStr(d.tithi) && isStr(d.highlight));
  });
  checkBestDays(p.bestDays);
  p.cautionDays.forEach((c) => assert.ok(ISO.test(c.date) && isStr(c.reason)));
  p.events.forEach(checkEvent);
  checkDasha(p.dasha);
  assert.ok(isStr(p.focus));
  checkRemedy(p.remedy);
}
function checkMonthPayload(p) {
  assert.equal(p.type, 'month');
  assert.ok(/^\d{4}-\d{2}$/.test(p.month) && isStr(p.monthName));
  checkCommon(p); checkSummary(p.summary); checkScores(p.scores);
  assert.ok(p.days.length >= 28 && p.days.length <= 31);
  p.days.forEach((d) => {
    assert.ok(ISO.test(d.date) && isInt(d.score, 0, 100) && MOODS.includes(d.mood) && isStr(d.tithi));
    assert.ok(A.ZODIAC_SIGNS.includes(d.moonSign) && typeof d.chandrashtama === 'boolean');
    assert.ok(d.festival === null || isStr(d.festival));
    assert.ok(isStr(d.highlight));
  });
  assert.ok(p.weeks.length >= 4 && p.weeks.length <= 6);
  p.weeks.forEach((w) => assert.ok(ISO.test(w.weekStart) && ISO.test(w.weekEnd) && isInt(w.score, 0, 100) && isStr(w.headline)));
  assert.ok(p.keyTransits.length >= 4);
  p.keyTransits.forEach(checkTransit);
  p.events.forEach(checkEvent);
  p.events.forEach((e) => assert.ok(e.date.startsWith(p.month)));
  checkBestDays(p.bestDays);
  p.cautionDays.forEach((c) => assert.ok(ISO.test(c.date) && isStr(c.reason)));
  checkDasha(p.dasha);
  checkRemedy(p.remedy);
}
function checkTimelinePayload(p) {
  assert.equal(p.type, 'timeline');
  checkCommon(p);
  assert.ok(ISO.test(p.now));
  assert.ok(p.periods.length > 5);
  const kinds = ['sade_sati', 'ashtama_shani', 'kantaka_shani', 'saturn_transit', 'jupiter_transit', 'rahu_ketu', 'mahadasha', 'antardasha'];
  let prev = '';
  for (const x of p.periods) {
    assert.ok(isStr(x.id) && kinds.includes(x.kind) && isStr(x.title));
    assert.ok(ISO.test(x.start) && ISO.test(x.end) && x.start < x.end);
    assert.ok(x.start >= prev, 'sorted by start');
    prev = x.start;
    if (x.kind === 'sade_sati') assert.ok(['Rising', 'Peak', 'Setting'].includes(x.phase));
    else assert.equal(x.phase, null);
    assert.ok(EFFECTS.includes(x.effect) && [1, 2, 3].includes(x.intensity) && typeof x.current === 'boolean');
    assert.ok(isStr(x.summary) && Array.isArray(x.realLife) && Array.isArray(x.advice));
  }
}
module.exports = { checkDayPayload, checkWeekPayload, checkMonthPayload, checkTimelinePayload };

// ---------------------------------------------------------------------------
// Tara Bala / Chandrashtama
// ---------------------------------------------------------------------------
test('Tara Bala counts from the birth nakshatra (mod 9)', () => {
  const t = F._internal.taraNumber;
  assert.equal(t(0, 0), 1); // same star: Janma
  assert.equal(t(0, 1), 2); // Sampat
  assert.equal(t(0, 2), 3); // Vipat
  assert.equal(t(0, 6), 7); // Vadha
  assert.equal(t(0, 8), 9); // Param Mitra
  assert.equal(t(0, 9), 1); // 10th star: Janma again (Anujanma)
  assert.equal(t(20, 2), 1); // wraps around 27: (2-20+27)=9 -> 10th star
  assert.equal(t(26, 0), 2); // Revati -> Ashwini is the next star
  assert.equal(I.TARA[7].name, 'Vadha');
  assert.equal(I.TARA[7].favorable, false);
  assert.equal(I.TARA[9].favorable, true);
});

test('Chandrashtama is flagged exactly when transit Moon is in the 8th sign from natal Moon', () => {
  const date = '2026-10-07';
  const probe = F._internal.dayInfo(ctxFor(chart('1990-05-15', '06:30')), date);
  const moonSign = probe.tr.Moon.sign;
  // natal Moon placed 7 signs before the transit Moon -> transit Moon is 8th from it
  const natalSign = (moonSign + 12 - 7) % 12;
  const ctx = ctxFor(chartWithMoon(natalSign * 30 + 10));
  const day = F.buildDay(ctx, date);
  assert.equal(day.moon.houseFromMoon, 8);
  assert.equal(day.moon.chandrashtama, true);
  assert.equal(day.moon.chandraBala, false);
  assert.equal(day.scores.mind.reason.length > 0, true);
  // the 9th sign is not Chandrashtama but the 7th gives Chandra Bala
  const day2 = F.buildDay(ctxFor(chartWithMoon(((moonSign + 12 - 6) % 12) * 30 + 10)), date);
  assert.equal(day2.moon.houseFromMoon, 7);
  assert.equal(day2.moon.chandrashtama, false);
  assert.equal(day2.moon.chandraBala, true);
  // Tara from the synthetic natal nakshatra
  const nat = Math.floor((natalSign * 30 + 10) / (360 / 27));
  assert.equal(day.moon.taraBala.number, F._internal.taraNumber(nat, A.NAKSHATRAS.indexOf(day.moon.nakshatra)));
});

test('Week marks Chandrashtama days and lists a chandrashtama event', () => {
  const probe = F._internal.dayInfo(ctxFor(chart('1990-05-15', '06:30')), '2026-10-07');
  const natalSign = (probe.tr.Moon.sign + 12 - 7) % 12;
  const w = F.buildWeek(ctxFor(chartWithMoon(natalSign * 30 + 5)), '2026-10-07');
  assert.ok(w.days.find((d) => d.date === '2026-10-07').chandrashtama);
  assert.ok(w.events.some((e) => e.type === 'chandrashtama'));
  assert.ok(w.cautionDays.some((c) => c.date === '2026-10-07'));
});

// ---------------------------------------------------------------------------
// Saturn cycles
// ---------------------------------------------------------------------------
function saturnPeriodOn(k, date) {
  const tl = F.buildTimeline(ctxFor(k), '2020-01-01', 12);
  return tl.periods.find((p) => ['sade_sati', 'ashtama_shani', 'kantaka_shani', 'saturn_transit'].includes(p.kind) && p.start <= date && date < p.end);
}

test('Sade Sati: Moon in Aquarius is in the Setting phase after Saturn enters Pisces (2025-03-29)', () => {
  const p = saturnPeriodOn(chartWithMoon(315), '2025-06-01');
  assert.equal(p.kind, 'sade_sati');
  assert.equal(p.phase, 'Setting');
  assert.ok(p.start >= '2025-03-28' && p.start <= '2025-03-30', p.start);
  const before = saturnPeriodOn(chartWithMoon(315), '2024-06-01');
  assert.equal(before.phase, 'Peak');
});

test('Sade Sati: Moon in Pisces is at its Peak through 2025-26', () => {
  for (const d of ['2025-06-01', '2026-01-15', '2026-10-07']) {
    const p = saturnPeriodOn(chartWithMoon(345), d);
    assert.equal(p.kind, 'sade_sati', d);
    assert.equal(p.phase, 'Peak', d);
  }
  const rising = saturnPeriodOn(chartWithMoon(345), '2024-01-01');
  assert.equal(rising.phase, 'Rising');
});

test('Ashtama and Kantaka Shani are detected from the natal Moon', () => {
  // Saturn in Pisces 2025-27: 8th from Leo, 4th from Sagittarius, 7th from Virgo, 10th from Gemini
  assert.equal(saturnPeriodOn(chartWithMoon(135), '2026-01-01').kind, 'ashtama_shani');
  assert.equal(saturnPeriodOn(chartWithMoon(255), '2026-01-01').kind, 'kantaka_shani');
  assert.equal(saturnPeriodOn(chartWithMoon(165), '2026-01-01').kind, 'kantaka_shani');
  assert.equal(saturnPeriodOn(chartWithMoon(75), '2026-01-01').kind, 'kantaka_shani');
  assert.equal(saturnPeriodOn(chartWithMoon(225), '2026-01-01').kind, 'saturn_transit'); // 5th from Scorpio
});

// ---------------------------------------------------------------------------
// Ingresses, eclipses, festivals
// ---------------------------------------------------------------------------
function eventsIn(start, end) {
  return F._internal.eventsBetween(ctxFor(chart('1990-05-15', '06:30')), start, end, { chandrashtama: false });
}

test('Sidereal ingress dates: Saturn -> Pisces 2025-03-29, Jupiter -> Gemini 2025-05-14, Rahu -> Aquarius 2025-05-18', () => {
  const ev = eventsIn('2025-03-01', '2025-06-01');
  const find = (t) => ev.find((e) => e.type === 'ingress' && e.title.startsWith(t));
  assert.equal(find('Saturn enters Pisces').date, '2025-03-29');
  assert.ok(['2025-05-14', '2025-05-15'].includes(find('Jupiter enters Gemini').date));
  assert.equal(find('Rahu enters Aquarius').date, '2025-05-18');
});

test('Eclipses: total lunar 2025-09-07, annular solar 2026-02-17, total solar 2026-08-12', () => {
  const ec = F._internal.eclipsesBetween(F._internal.msToJd(Date.parse('2025-01-01')), F._internal.msToJd(Date.parse('2027-01-01')));
  const dates = ec.map((e) => `${e.kind}:${new Date(F._internal.jdToMs(e.jd)).toISOString().slice(0, 10)}`);
  assert.ok(dates.includes('lunar:2025-09-07'), dates.join(','));
  assert.ok(dates.includes('solar:2026-02-17'));
  assert.ok(dates.includes('solar:2026-08-12'));
  assert.ok(dates.includes('lunar:2026-03-03'));
  assert.equal(ec.find((e) => e.kind === 'lunar' && e.subtype === 'total' && dates.includes('lunar:2025-09-07')).subtype, 'total');
  const ev = eventsIn('2025-09-01', '2025-09-30');
  assert.ok(ev.some((e) => e.type === 'lunar_eclipse' && e.date === '2025-09-07' && /house from Moon/.test(e.personalImpact)));
});

test('Festival dates (New Delhi) match published calendars', () => {
  const ev = eventsIn('2025-01-01', '2026-12-31').filter((e) => e.type === 'festival');
  const on = (name) => ev.filter((e) => e.title === name).map((e) => e.date);
  assert.ok(on('Diwali (Lakshmi Puja)').includes('2025-10-20'));
  assert.ok(on('Diwali (Lakshmi Puja)').includes('2026-11-08'));
  assert.ok(on('Holi').includes('2025-03-14'));
  assert.ok(on('Holi').includes('2026-03-04'));
  assert.ok(on('Maha Shivaratri').includes('2025-02-26'));
  assert.ok(on('Maha Shivaratri').includes('2026-02-15'));
  assert.ok(on('Sharad Navratri begins').includes('2025-09-22'));
  assert.ok(on('Dussehra (Vijayadashami)').includes('2025-10-02'));
  assert.ok(on('Raksha Bandhan').includes('2025-08-09'));
  assert.ok(on('Ram Navami').includes('2025-04-06'));
  assert.ok(on('Ganesh Chaturthi').includes('2025-08-27'));
  assert.ok(on('Guru Purnima').includes('2025-07-10'));
  // each festival once per year
  assert.equal(on('Diwali (Lakshmi Puja)').length, 2);
  const sank = eventsIn('2026-01-01', '2026-01-31').find((e) => e.title === 'Makar Sankranti');
  assert.equal(sank.date, '2026-01-14');
});

test('Ekadashi falls on tithi 11/26 at sunrise, about twice a month', () => {
  const ev = eventsIn('2025-01-01', '2025-12-31').filter((e) => e.type === 'ekadashi');
  assert.ok(ev.length >= 23 && ev.length <= 26, String(ev.length));
  assert.ok(ev.some((e) => e.title === 'Nirjala Ekadashi' && e.date === '2025-06-06'));
});

// ---------------------------------------------------------------------------
// Dasha
// ---------------------------------------------------------------------------
test('Pratyantardasha boundaries are contiguous and nest exactly inside antardashas', () => {
  const ctx = ctxFor(chart('1990-05-15', '06:30'));
  const mds = F._internal.mahadashaList(ctx);
  for (let i = 1; i < mds.length; i++) assert.equal(mds[i].start, mds[i - 1].end);
  for (const md of mds.slice(0, 3)) {
    const ads = F._internal.subPeriods(md);
    assert.equal(ads[0].start, md.start);
    assert.equal(ads[8].end, md.end);
    assert.equal(ads[0].lord, md.lord);
    for (let i = 1; i < 9; i++) assert.equal(ads[i].start, ads[i - 1].end);
    for (const ad of ads) {
      const pds = F._internal.subPeriods(ad);
      assert.equal(pds[0].start, ad.start);
      assert.equal(pds[8].end, ad.end);
      assert.equal(pds[0].lord, ad.lord);
      for (let i = 1; i < 9; i++) assert.equal(pds[i].start, pds[i - 1].end);
    }
  }
});

test('Dasha now agrees with the stored Vimshottari computation', () => {
  const k = chart('1990-05-15', '06:30');
  const ref = A.computeVimshottari(k.moonLongitude, Date.parse(k.birthUtc), NOW);
  const d = F.buildDay(ctxFor(k), '2026-10-07').dasha;
  assert.equal(d.mahadasha, ref.currentMahadasha);
  assert.equal(d.antardasha, ref.antardasha);
  assert.ok(Math.abs(Date.parse(d.antardashaEnds) - Date.parse(ref.antardashaEndDate)) <= 86400000);
  assert.ok(d.pratyantardashaEnds <= d.antardashaEnds);
});

// ---------------------------------------------------------------------------
// Payload shapes and performance
// ---------------------------------------------------------------------------
test('Day payload matches the contract', () => {
  const p = F.buildDay(ctxFor(chart('1990-05-15', '06:30')), '2026-10-07');
  checkDayPayload(p);
  assert.equal(p.generatedBy, 'rules');
  assert.equal(p.accuracyNote, null);
  assert.ok(p.summary.narrative.includes('Asha'));
  // transits carry real sign entry/exit dates
  const sat = p.transits.find((t) => t.planet === 'Saturn');
  assert.equal(sat.sign, 'Pisces');
  assert.equal(sat.since, '2025-03-29');
});

test('Day scores vary day to day while staying in range', () => {
  const ctx = ctxFor(chart('1990-05-15', '06:30'));
  const scores = Array.from({ length: 30 }, (_, i) => F._internal.dayInfo(ctx, F.isoAdd('2026-10-01', i)).overall);
  const distinct = new Set(scores).size;
  assert.ok(distinct >= 10, `only ${distinct} distinct scores`);
  assert.ok(Math.max(...scores) - Math.min(...scores) >= 20);
});

test('Week payload matches the contract and snaps to Monday', () => {
  const p = F.buildWeek(ctxFor(chart('1990-05-15', '06:30')), '2026-10-08');
  checkWeekPayload(p);
  assert.equal(p.weekStart, '2026-10-05');
  assert.equal(p.weekEnd, '2026-10-11');
});

test('Month payload matches the contract (family member profile) and is fast', () => {
  const k = chart('1988-11-02', '22:30', 19.07, 72.87);
  const t0 = Date.now();
  const p = F.buildMonth(ctxFor(k, { profile: { name: 'Bob Rao', isFamily: true, familyId: 7, relationship: 'Spouse' } }), '2026-10');
  const ms = Date.now() - t0;
  checkMonthPayload(p);
  assert.equal(p.monthName, 'October 2026');
  assert.equal(p.days.length, 31);
  assert.equal(p.profile.isFamily, true);
  assert.equal(p.profile.familyId, 7);
  assert.ok(p.events.some((e) => e.title === 'Dussehra (Vijayadashami)' && e.date === '2026-10-20'));
  assert.ok(ms < 1500, `month took ${ms}ms`);
});

test('Timeline payload matches the contract', () => {
  const p = F.buildTimeline(ctxFor(chart('1990-05-15', '06:30')), '2024-10-07', 6);
  checkTimelinePayload(p);
  assert.ok(p.periods.some((x) => x.kind === 'mahadasha' && x.current));
  assert.ok(p.periods.some((x) => x.kind === 'jupiter_transit'));
  assert.ok(p.periods.some((x) => x.kind === 'rahu_ketu'));
});

test('Unknown birth time sets an accuracy note and still forecasts', () => {
  const k = chart('1995-03-10', '12:00', 26.85, 80.95, { birthTimeKnown: false });
  const p = F.buildDay(ctxFor(k), '2026-10-07');
  assert.equal(p.birthTimeKnown, false);
  assert.ok(isStr(p.accuracyNote));
  checkDayPayload(p);
});

test('Missing kundli data raises NO_KUNDLI', () => {
  assert.throws(() => F.createContext({ ascendant: null }), (e) => e.code === 'NO_KUNDLI' && e.statusCode === 409);
});

test('Interpretation library covers 9 planets x 12 houses', () => {
  for (const p of PLANETS) {
    for (let h = 1; h <= 12; h++) {
      const e = I.GOCHARA[p][h];
      assert.ok(e && isStr(e.theme) && isStr(e.meaning), `${p} ${h}`);
      assert.ok(e.realLife.length >= 3 && e.realLife.length <= 5, `${p} ${h}`);
      assert.ok(e.doList.length >= 1 && e.avoidList.length >= 1);
    }
  }
});

test('Chat context block is compact and grounded', () => {
  const txt = F.chatContext(chart('1990-05-15', '06:30'), { nowMs: NOW });
  assert.ok(txt.includes('Dasha:') && txt.includes('Moon today:') && txt.includes('Saturn cycle:'));
  assert.ok(txt.length < 2000);
});
