// Muhurat finder: rules table, scoring, windows, validation, performance, cache and the HTTP routes.
// The DB is a tiny in-memory stub installed in require.cache before any route loads (never the real pool).
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const Module = require('module');

const DB_PATH = path.join(__dirname, '..', 'db.js');
const kundlis = new Map(); // userId -> { moon_sign, nakshatra }
const queries = [];
const stub = {
  query: async (sql, params = []) => {
    const s = String(sql).replace(/\s+/g, ' ').trim();
    queries.push(s);
    if (s.startsWith('SELECT role FROM users WHERE id = $1')) return { rows: [{ role: 'guest' }] };
    if (s.startsWith('SELECT moon_sign, nakshatra FROM kundlis WHERE user_id = $1')) {
      const row = kundlis.get(params[0]);
      return { rows: row ? [row] : [] };
    }
    throw new Error(`Unexpected SQL in muhurat test: ${s}`);
  }
};
const m = new Module(DB_PATH, module);
m.filename = DB_PATH;
m.loaded = true;
m.exports = stub;
require.cache[DB_PATH] = m;
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-unit-tests-only-0123456789';

const { serve, call } = require('./fake_db');
const { signToken } = require('../routes/auth');
const M = require('../services/muhurat_service');
const A = require('../services/astrology_service');
const RULES = require('../data/muhurat_rules.json');

const X = M._internal;
const IST = A.resolveTimeZone('Asia/Kolkata');
const day = (iso) => X.computeDay(iso, 28.6, 77.2, IST, X.lunarContext());

test('rules table is well formed', () => {
  assert.equal(RULES.events.length, 12);
  const ids = new Set();
  for (const e of RULES.events) {
    assert.ok(!ids.has(e.id), `duplicate ${e.id}`);
    ids.add(e.id);
    assert.ok(e.label && e.labelHi && e.icon, e.id);
    for (const n of e.goodNakshatras) assert.ok(A.NAKSHATRAS.includes(n), `${e.id}: bad nakshatra ${n}`);
    for (const w of [...e.goodWeekdays, ...(e.avoidWeekdays || [])]) assert.ok(w >= 0 && w <= 6);
    assert.ok(!e.goodWeekdays.some((w) => (e.avoidWeekdays || []).includes(w)), `${e.id}: weekday both good and avoided`);
    for (const t of e.goodTithis) assert.ok(t >= 1 && t <= 30 && t !== 30);
    for (const s of e.specials || []) assert.ok(A.NAKSHATRAS.includes(s.nakshatra));
  }
  for (const y of [...RULES.common.goodYogas, ...RULES.common.badYogasSoft, ...RULES.common.badYogasHard]) {
    assert.ok(typeof y === 'string' && y.length > 2);
  }
});

test('events list has the 12 supported events with Hindi labels and safety notes', () => {
  const ev = M.listEvents();
  assert.deepEqual(ev.map((e) => e.id), [
    'griha_pravesh', 'vehicle_purchase', 'new_job_or_business', 'property_purchase', 'marriage', 'engagement',
    'naming_ceremony', 'mundan', 'travel_start', 'gold_jewellery_purchase', 'starting_education', 'surgery_or_medical'
  ]);
  for (const e of ev) assert.match(e.labelHi, /[ऀ-ॿ]/);
  assert.match(ev.find((e) => e.id === 'marriage').note, /pandit/i);
  assert.match(ev.find((e) => e.id === 'surgery_or_medical').note, /doctor/i);
});

test('returns top 3 days sorted by score with reasons, panchang facts and a disclaimer', () => {
  const r = M.findMuhurat({ event: 'vehicle_purchase', from: '2026-11-05', days: 30 });
  assert.equal(r.results.length, 3);
  assert.equal(r.from, '2026-11-05');
  assert.equal(r.to, '2026-12-04');
  assert.ok(r.disclaimer.length > 50);
  for (let i = 1; i < r.results.length; i++) assert.ok(r.results[i - 1].score >= r.results[i].score);
  for (const x of r.results) {
    assert.ok(x.score >= 0 && x.score <= 100);
    assert.match(x.date, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(A.WEEKDAYS.includes(x.weekday));
    assert.ok(x.tithi && x.nakshatra && x.yoga && x.paksha);
    assert.ok(x.reasons.length >= 2 && x.reasons.length <= 4, JSON.stringify(x.reasons));
    for (const s of x.reasons) assert.ok(typeof s === 'string' && s.length < 140);
    assert.ok(Array.isArray(x.cautions));
    assert.match(x.bestWindow.start, /^\d{2}:\d{2} (AM|PM)$/);
    assert.ok(Date.parse(x.bestWindow.endUtc) > Date.parse(x.bestWindow.startUtc));
  }
  // Results are a subset of the scored, eligible days
  assert.ok(r.eligibleDays >= 3 && r.eligibleDays <= 30);
  assert.equal(r.consideredDays, 30);
});

test('avoids Amavasya and Rikta tithis (and reports them) per the rules', () => {
  const r = M.findMuhurat({ event: 'griha_pravesh', from: '2027-01-20', days: 45 });
  for (const x of r.results) {
    const d = day(x.date);
    assert.notEqual(d.tithiNumber, 30);
    assert.ok(![4, 9, 14, 19, 24, 29].includes(d.tithiNumber), `${x.date} is rikta`);
    assert.ok(!/^Vishti/.test(d.karana));
  }
  const ama = r.avoided.find((a) => a.reason === 'Amavasya');
  const rikta = r.avoided.find((a) => a.reason === 'Rikta tithi');
  assert.ok(ama && ama.count >= 1 && ama.text);
  assert.ok(rikta && rikta.count >= 4);
  for (const iso of ama.dates) assert.equal(day(iso).tithiNumber, 30);
  for (const iso of rikta.dates) assert.ok([4, 9, 14, 19, 24, 29].includes(day(iso).tithiNumber));
  // Surgery keeps Rikta days eligible (tradition: fit for removing illness) but still avoids Amavasya
  const s = M.findMuhurat({ event: 'surgery_or_medical', from: '2027-01-20', days: 45 });
  assert.ok(!s.avoided.some((a) => a.reason === 'Rikta tithi'));
  assert.ok(s.avoided.some((a) => a.reason === 'Amavasya'));
});

test('Kharmas and Chaturmas block vivah but not a vehicle purchase', () => {
  const k = M.findMuhurat({ event: 'marriage', from: '2026-12-20', days: 20 }); // Sun in Sagittarius
  assert.equal(k.results.length, 0);
  assert.ok(k.message);
  assert.ok(k.avoided.find((a) => a.reason === 'Kharmas').count >= 15);
  const c = M.findMuhurat({ event: 'marriage', from: '2026-08-01', days: 30 }); // Shravan / Bhadrapada
  assert.equal(c.results.length, 0);
  assert.ok(c.avoided.some((a) => a.reason === 'Chaturmas'));
  const v = M.findMuhurat({ event: 'vehicle_purchase', from: '2026-12-20', days: 20 });
  assert.equal(v.results.length, 3);
  assert.ok(!v.avoided.some((a) => a.reason === 'Kharmas'));
  assert.equal(X.inChaturmas({ lunarMonth: 3, tithiNumber: 10 }), false);
  assert.equal(X.inChaturmas({ lunarMonth: 3, tithiNumber: 11 }), true);
  assert.equal(X.inChaturmas({ lunarMonth: 7, tithiNumber: 11 }), false);
});

test('best window lies in daylight and avoids Rahu Kaal, Yamaganda and Gulika; no Abhijit on Wednesday', () => {
  let checked = 0;
  for (const event of ['vehicle_purchase', 'griha_pravesh', 'gold_jewellery_purchase', 'travel_start']) {
    const r = M.findMuhurat({ event, from: '2027-02-01', days: 60 });
    for (const x of r.results) {
      const d = day(x.date);
      const s = Date.parse(x.bestWindow.startUtc);
      const e = Date.parse(x.bestWindow.endUtc);
      assert.ok(s >= d.sunriseMs - 1000 && e <= d.sunsetMs + 1000, 'daytime');
      for (const b of [d.rahu, d.yama, d.gulika]) assert.ok(!(s < b.end - 1000 && b.start < e - 1000), `${event} ${x.date} overlaps`);
      if (x.weekday === 'Wednesday') assert.notEqual(x.bestWindow.label, 'Abhijit Muhurat');
      checked++;
    }
  }
  assert.ok(checked >= 10);
  // Direct check over many days: Abhijit is used only when clean
  for (let i = 0; i < 14; i++) {
    const iso = new Date(Date.UTC(2027, 1, 1 + i)).toISOString().slice(0, 10);
    const d = day(iso);
    const w = X.bestWindow(RULES.events[1], d, IST);
    assert.ok(w);
    for (const b of [d.rahu, d.yama, d.gulika]) assert.ok(!(w._start < b.end && b.start < w._end));
  }
});

test('panchang facts match the app daily panchang function', () => {
  for (const iso of ['2026-11-11', '2027-03-03']) {
    const p = A.calculateDailyPanchangAndMuhurats(iso, 28.6, 77.2, 'Asia/Kolkata');
    const d = day(iso);
    assert.equal(d.tithi, p.tithi);
    assert.equal(d.nakshatra, p.nakshatra);
    assert.equal(d.yoga, p.yoga);
    assert.equal(A.formatClock(d.rahu.start, IST) + ' - ' + A.formatClock(d.rahu.end, IST), p.rahuKaal);
  }
});

test('personal factor: Tarabala / Chandrabala reasons and Chandrashtama caution', () => {
  const rule = RULES.events.find((e) => e.id === 'vehicle_purchase');
  const d = day('2026-11-11');
  const good = X.scoreDay(rule, d, { birthNakIndex: (d.nakshatraIndex + 26) % 27, moonSignIndex: d.moonSign });
  // tara = 2 (Sampat), Moon in 1st from natal Moon
  assert.ok(good.reasons.some((r) => /Sampat Tara/.test(r.text)));
  assert.ok(good.reasons.some((r) => /Moon sign/.test(r.text)));
  const base = X.scoreDay(rule, d, null);
  const bad = X.scoreDay(rule, d, { birthNakIndex: (d.nakshatraIndex + 25) % 27, moonSignIndex: (d.moonSign + 5) % 12 });
  // tara = 3 (Vipat), Moon 8th from natal Moon
  assert.ok(bad.score < base.score && base.score <= good.score);
  assert.ok(bad.cautions.some((c) => /Chandrashtama/.test(c)));
  assert.deepEqual(M.personalFromKundli({ moon_sign: 'Taurus', nakshatra: 'Rohini' }), { birthNakIndex: 3, moonSignIndex: 1 });
  assert.equal(M.personalFromKundli({ moon_sign: '', nakshatra: '' }), null);
  assert.equal(M.personalFromKundli(null), null);
});

test('performance: 30 days well under 1.5 s cold; all 12 events x 60 days reuse day facts', () => {
  X._resetCaches();
  let t = Date.now();
  M.findMuhurat({ event: 'marriage', from: '2027-05-01', days: 30, lat: 19.07, lng: 72.88 });
  const cold = Date.now() - t;
  assert.ok(cold < 1500, `cold 30 days took ${cold} ms`);
  t = Date.now();
  for (const e of M.listEvents()) M.findMuhurat({ event: e.id, from: '2027-05-01', days: 60, lat: 19.07, lng: 72.88 });
  const all = Date.now() - t;
  assert.ok(all < 2500, `12 events x 60 days took ${all} ms`);
  assert.ok(X.dayCache.size >= 60 && X.dayCache.size <= 61);
});

test('results are cached per event, range and rounded location', () => {
  X._resetCaches();
  const a = M.findMuhurat({ event: 'travel_start', from: '2027-04-01', days: 30, lat: 12.97, lng: 77.59 });
  assert.equal(a.cached, false);
  const b = M.findMuhurat({ event: 'travel_start', from: '2027-04-01', days: 30, lat: 12.99, lng: 77.61 });
  assert.equal(b.cached, true); // same 0.1 deg cell
  assert.deepEqual(b.results, a.results);
  assert.deepEqual(b.location, { lat: 13, lng: 77.6, timezone: 'Asia/Kolkata' });
  const c = M.findMuhurat({ event: 'travel_start', from: '2027-04-01', days: 31, lat: 12.97, lng: 77.59 });
  assert.equal(c.cached, false);
  // Expiry after 6 h
  const now = Date.now();
  const d = M.findMuhurat({ event: 'travel_start', from: '2027-04-01', days: 30, lat: 12.97, lng: 77.59 }, { nowMs: now + 7 * 3600000 });
  assert.equal(d.cached, false);
});

test('input validation', () => {
  const bad = [
    {}, { event: 'nope' }, { event: 'marriage', days: '0' }, { event: 'marriage', days: 'abc' },
    { event: 'marriage', days: '2.5' }, { event: 'marriage', from: '2026-02-30' }, { event: 'marriage', from: '05-11-2026' },
    { event: 'marriage', lat: '20' }, { event: 'marriage', lat: '100', lng: '10' }, { event: 'marriage', lat: 'x', lng: '10' },
    { event: 'marriage', tz: 'Mars/Olympus' }
  ];
  for (const q of bad) assert.throws(() => M.normaliseQuery(q), M.MuhuratInputError, JSON.stringify(q));
  assert.equal(M.normaliseQuery({ event: 'marriage', days: '500' }).days, 60);
  const n = M.normaliseQuery({ event: 'marriage', lat: '40.71', lng: '-74.01' });
  assert.equal(n.tzName, 'America/New_York');
  assert.equal(M.normaliseQuery({ event: 'marriage' }).lat, 28.6);
});

test('HTTP: /events, guest search, logged-in personal factor and 400s', async () => {
  const router = require('../routes/muhurat');
  const srv = await serve(router, '/api/muhurat');
  try {
    const ev = await call(srv.url, 'GET', '/events');
    assert.equal(ev.status, 200);
    assert.equal(ev.body.events.length, 12);

    const g = await call(srv.url, 'GET', '?event=gold_jewellery_purchase&from=2027-01-15&days=30&lat=28.61&lng=77.21&tz=Asia/Kolkata');
    assert.equal(g.status, 200);
    assert.equal(g.body.personal, false);
    assert.equal(g.body.results.length, 3);
    assert.equal(g.body.event.id, 'gold_jewellery_purchase');
    assert.ok(!queries.some((q) => q.includes('kundlis')), 'guests never hit the DB');

    kundlis.set(41, { moon_sign: 'Cancer', nakshatra: 'Pushya' });
    const token = signToken({ userId: 41, role: 'user' });
    const p = await call(srv.url, 'GET', '?event=gold_jewellery_purchase&from=2027-01-15&days=30&lat=28.61&lng=77.21', { token });
    assert.equal(p.status, 200);
    assert.equal(p.body.personal, true);
    assert.equal(p.body.results.length, 3);
    const off = await call(srv.url, 'GET', '?event=gold_jewellery_purchase&from=2027-01-15&days=30&personal=0', { token });
    assert.equal(off.body.personal, false);
    const noK = await call(srv.url, 'GET', '?event=gold_jewellery_purchase&from=2027-01-15&days=30', { token: signToken({ userId: 42, role: 'user' }) });
    assert.equal(noK.status, 200);
    assert.equal(noK.body.personal, false);

    for (const qs of ['', '?event=xyz', '?event=marriage&days=0', '?event=marriage&from=2027-13-01', '?event=marriage&lat=1']) {
      const r = await call(srv.url, 'GET', qs);
      assert.equal(r.status, 400, qs);
      assert.ok(r.body.error);
    }
    const inv = await call(srv.url, 'GET', '?event=marriage', { token: 'garbage' });
    assert.equal(inv.status, 401);
  } finally {
    await srv.close();
  }
});
