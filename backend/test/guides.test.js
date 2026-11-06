// Puja & vrat guides: JSON schema, bundled app copy, next-date rules and the HTTP routes. No DB involved.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const { serve, call } = require('./fake_db');
const G = require('../services/guide_service');
const DATA = require('../data/puja_guides.json');

const ROOT = path.join(__dirname, '..', '..');
const ISO = /^\d{4}-\d{2}-\d{2}$/;
const DEVANAGARI = /[ऀ-ॿ]/;
const nonEmpty = (s) => typeof s === 'string' && s.trim().length > 0;
const weekday = (iso) => new Date(`${iso}T00:00:00Z`).getUTCDay();

test('every guide has the required fields; ids are unique', () => {
  const guides = DATA.guides;
  assert.ok(guides.length >= 12);
  const ids = new Set();
  for (const g of guides) {
    const where = g.id || '(no id)';
    assert.match(g.id, /^[a-z0-9_]+$/, where);
    assert.ok(!ids.has(g.id), `duplicate id ${g.id}`);
    ids.add(g.id);
    for (const f of ['title', 'deity', 'duration', 'overview', 'katha', 'regionalNote']) assert.ok(nonEmpty(g[f]), `${where}.${f}`);
    assert.match(g.titleHi, DEVANAGARI, `${where}.titleHi`);
    assert.ok(['vrat', 'puja', 'festival'].includes(g.category), `${where}.category`);
    assert.ok(['Easy', 'Moderate', 'Elaborate'].includes(g.difficulty), `${where}.difficulty`);
    assert.match(g.regionalNote, /family/i);

    assert.ok(nonEmpty(g.when.text), `${where}.when.text`);
    assert.ok(g.when.festivalKey === null || nonEmpty(g.when.festivalKey));
    const r = g.when.rule;
    assert.ok(['lunar', 'tithi', 'weekday'].includes(r.type), `${where}.rule`);
    if (r.type === 'lunar') {
      assert.ok(Number.isInteger(r.month) && r.month >= 0 && r.month <= 11);
      assert.ok(Number.isInteger(r.tithi) && r.tithi >= 1 && r.tithi <= 30);
    }
    if (r.type === 'tithi') assert.ok(r.tithis.length && r.tithis.every((t) => t >= 1 && t <= 30));
    if (r.type === 'weekday') assert.ok(r.weekdays.length && r.weekdays.every((d) => d >= 0 && d <= 6));
    if (r.type !== 'weekday') assert.ok(['sunrise', 'madhyahna', 'aparahna', 'pradosh', 'nishita'].includes(r.kaal));

    assert.ok(Array.isArray(g.samagri) && g.samagri.length >= 4, `${where}.samagri`);
    for (const s of g.samagri) {
      assert.ok(nonEmpty(s.item), `${where} samagri item`);
      if (s.qty !== undefined) assert.ok(nonEmpty(s.qty));
    }
    assert.ok(Array.isArray(g.steps) && g.steps.length >= 4, `${where}.steps`);
    for (const st of g.steps) {
      assert.ok(nonEmpty(st.text) && st.text.length < 400, `${where} step`);
      if (st.mantra) {
        assert.match(st.mantra.devanagari, DEVANAGARI);
        assert.ok(nonEmpty(st.mantra.transliteration) && !DEVANAGARI.test(st.mantra.transliteration));
      }
    }
    if (g.vratRules !== null) {
      for (const k of ['do', 'dont', 'food']) {
        assert.ok(Array.isArray(g.vratRules[k]) && g.vratRules[k].length >= 1 && g.vratRules[k].every(nonEmpty), `${where}.vratRules.${k}`);
      }
    }
    if (g.category === 'vrat') assert.ok(g.vratRules, `${where}: a vrat needs vratRules`);
    const words = g.katha.trim().split(/\s+/).length;
    assert.ok(words >= 150 && words <= 300, `${where}.katha has ${words} words`);
    assert.ok(nonEmpty(g.aarti.title) && g.aarti.lines.length >= 1);
    for (const l of g.aarti.lines) {
      assert.match(l.devanagari, DEVANAGARI);
      assert.ok(nonEmpty(l.transliteration));
    }
    assert.ok(Array.isArray(g.tips) && g.tips.length >= 1 && g.tips.every(nonEmpty));
    if (g.image !== null) assert.ok(fs.existsSync(path.join(ROOT, 'assets', 'images', g.image)), `${where}: missing image ${g.image}`);
  }
  for (const id of ['karva_chauth', 'ekadashi_vrat', 'satyanarayan_katha', 'ganesh_chaturthi', 'navratri_kalash_sthapana',
    'diwali_lakshmi_puja', 'mahashivratri', 'janmashtami', 'somvar_vrat', 'hanuman_puja', 'purnima_puja', 'chhath_puja']) {
    assert.ok(ids.has(id), `missing guide ${id}`);
  }
});

test('festival keys match the forecast engine festival titles where one exists', () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'services', 'forecast_service.js'), 'utf8');
  for (const key of ['Ganesh Chaturthi', 'Sharad Navratri begins', 'Diwali (Lakshmi Puja)', 'Maha Shivaratri', 'Krishna Janmashtami', 'Hanuman Jayanti']) {
    assert.ok(src.includes(`'${key}'`), key);
    assert.ok(DATA.guides.some((g) => g.when.festivalKey === key), key);
  }
});

test('the app bundles an identical copy of the guides', () => {
  const app = fs.readFileSync(path.join(ROOT, 'assets', 'data', 'puja_guides.json'), 'utf8');
  assert.deepEqual(JSON.parse(app), DATA);
  const pubspec = fs.readFileSync(path.join(ROOT, 'pubspec.yaml'), 'utf8');
  assert.match(pubspec, /- assets\/data\//);
});

test('next dates follow the panchang (known observance days, New Delhi)', () => {
  G._internal.cache.clear();
  const d25 = G.upcomingDates({ nowMs: Date.parse('2025-01-02T06:00:00Z') });
  assert.equal(d25.get('mahashivratri')[0], '2025-02-26');
  assert.equal(d25.get('karva_chauth')[0], '2025-10-10');
  assert.equal(d25.get('diwali_lakshmi_puja')[0], '2025-10-20');
  assert.equal(d25.get('chhath_puja')[0], '2025-10-27');
  assert.equal(d25.get('ganesh_chaturthi')[0], '2025-08-27');
  assert.equal(d25.get('navratri_kalash_sthapana')[0], '2025-09-22');
  const d24 = G.upcomingDates({ nowMs: Date.parse('2024-01-02T06:00:00Z') });
  assert.equal(d24.get('karva_chauth')[0], '2024-10-20');
  assert.equal(d24.get('chhath_puja')[0], '2024-11-07');
  assert.equal(d24.get('mahashivratri')[0], '2024-03-08');
  // Weekday rules
  for (const iso of d25.get('somvar_vrat')) assert.equal(weekday(iso), 1);
  for (const iso of d25.get('hanuman_puja')) assert.ok([2, 6].includes(weekday(iso)));
  // Monthly ones are close
  const ek = d25.get('ekadashi_vrat');
  assert.equal(ek.length, 2);
  assert.ok(ek[0] >= '2025-01-02' && ek[0] <= '2025-01-18');
  for (const [, v] of d25) for (const iso of v) assert.match(iso, ISO);
});

test('performance: next dates for all guides < 1.5 s cold, cached afterwards', () => {
  G._internal.cache.clear();
  let t = Date.now();
  G.upcomingDates({ lat: 22.57, lng: 88.36, nowMs: Date.parse('2026-11-05T06:00:00Z') });
  const cold = Date.now() - t;
  assert.ok(cold < 1500, `cold took ${cold} ms`);
  t = Date.now();
  G.upcomingDates({ lat: 22.57, lng: 88.36, nowMs: Date.parse('2026-11-05T07:00:00Z') });
  assert.ok(Date.now() - t < 20);
});

test('HTTP: list, detail, 404s', async () => {
  const srv = await serve(require('../routes/guides'), '/api/guides');
  try {
    const list = await call(srv.url, 'GET', '');
    assert.equal(list.status, 200);
    assert.equal(list.body.guides.length, DATA.guides.length);
    const today = new Date().toISOString().slice(0, 10);
    for (const g of list.body.guides) {
      assert.ok(g.id && g.title && g.titleHi && g.category && g.when.text);
      assert.equal(g.steps, undefined, 'list is a summary');
      assert.match(g.nextDate, ISO);
      assert.ok(g.nextDate >= isoAddDays(today, -1));
    }
    const d = await call(srv.url, 'GET', '/karva_chauth?lat=19.07&lng=72.88&tz=Asia/Kolkata');
    assert.equal(d.status, 200);
    assert.equal(d.body.guide.id, 'karva_chauth');
    assert.ok(d.body.guide.steps.length >= 4);
    assert.match(d.body.guide.nextDate, ISO);
    // Bad tz: content still served, just without dates
    const bad = await call(srv.url, 'GET', '/somvar_vrat?tz=Nowhere/Land');
    assert.equal(bad.status, 200);
    assert.equal(bad.body.guide.nextDate, null);
    assert.equal((await call(srv.url, 'GET', '/nope')).status, 404);
    assert.equal((await call(srv.url, 'GET', '/..%2Fsecrets')).status, 404);
  } finally {
    await srv.close();
  }
});

function isoAddDays(iso, n) {
  const t = new Date(`${iso}T00:00:00Z`);
  t.setUTCDate(t.getUTCDate() + n);
  return t.toISOString().slice(0, 10);
}
