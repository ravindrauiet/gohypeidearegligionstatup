// Reference charts with widely published Vedic (Lahiri) placements.
// If any of these fail, the Kundli engine has regressed. Run: npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  calculateKundli,
  timezoneForLocation,
  getNavamshaSignIndex,
  getDasamshaSignIndex,
} = require('../services/astrology_service');

const signOf = (k, planet) => k.planetaryPositions.find((p) => p.name.startsWith(planet)).sign;

test('Narendra Modi — Scorpio lagna, Moon in Anuradha, Mars in lagna', () => {
  const k = calculateKundli('1950-09-17', '11:00', 'Vadnagar', 23.785, 72.639);
  assert.equal(k.ascendant, 'Scorpio');
  assert.equal(k.moonSign, 'Scorpio');
  assert.equal(k.nakshatra, 'Anuradha');
  assert.equal(signOf(k, 'Mars'), 'Scorpio');
  assert.equal(signOf(k, 'Saturn'), 'Leo');
  assert.equal(signOf(k, 'Venus'), 'Leo');
  assert.equal(signOf(k, 'Jupiter'), 'Aquarius');
});

test('Amitabh Bachchan — Aquarius lagna, Moon in Swati (1942 war-time IST +6:30)', () => {
  const k = calculateKundli('1942-10-11', '16:00', 'Allahabad', 25.435, 81.846);
  assert.equal(k.birthUtc, '1942-10-11T09:30:00.000Z');
  assert.equal(k.ascendant, 'Aquarius');
  assert.equal(k.moonSign, 'Libra');
  assert.equal(k.nakshatra, 'Swati');
  assert.equal(signOf(k, 'Jupiter'), 'Cancer');
  assert.equal(signOf(k, 'Saturn'), 'Taurus');
});

test('M. K. Gandhi — Libra lagna, Moon in Ashlesha (Porbandar LMT)', () => {
  const k = calculateKundli('1869-10-02', '07:12', 'Porbandar', 21.64, 69.6, '+04:39');
  assert.equal(k.ascendant, 'Libra');
  assert.equal(k.moonSign, 'Cancer');
  assert.equal(k.nakshatra, 'Ashlesha');
  assert.equal(signOf(k, 'Saturn'), 'Scorpio');
});

test('Births outside India use the birth place timezone, not IST', () => {
  const jobs = calculateKundli('1955-02-24', '19:15', 'San Francisco', 37.77, -122.42);
  assert.equal(jobs.timezone, 'America/Los_Angeles');
  assert.equal(jobs.birthUtc, '1955-02-25T03:15:00.000Z');
  assert.equal(jobs.ascendant, 'Leo');
  assert.equal(jobs.moonSign, 'Pisces');
  assert.equal(jobs.nakshatra, 'Uttara Bhadrapada');

  const london = calculateKundli('1990-07-15', '09:00', 'London', 51.5, -0.12);
  assert.equal(london.birthUtc, '1990-07-15T08:00:00.000Z'); // BST

  const kathmandu = calculateKundli('2000-01-01', '12:00', 'Kathmandu', 27.7, 85.3);
  assert.equal(kathmandu.birthUtc, '2000-01-01T06:15:00.000Z'); // +05:45
});

test('An explicit timezone overrides the coordinate lookup', () => {
  assert.equal(timezoneForLocation('+05:30', 40.71, -74.0), '+05:30');
  assert.equal(timezoneForLocation(undefined, 40.71, -74.0), 'America/New_York');
  assert.equal(timezoneForLocation(undefined, undefined, undefined), 'Asia/Kolkata');
});

test('Navamsha (D9) and Dasamsha (D10) sign rules', () => {
  // Aries 0° → D9 Aries; Taurus 0° → D9 Capricorn; Gemini 0° → Libra; Cancer 0° → Cancer
  assert.deepEqual([0, 30, 60, 90].map(getNavamshaSignIndex), [0, 9, 6, 3]);
  // Last navamsha of Aries (29°) → Sagittarius
  assert.equal(getNavamshaSignIndex(29), 8);
  // D10: odd sign counts from itself, even sign from the 9th
  assert.equal(getDasamshaSignIndex(0), 0); // Aries → Aries
  assert.equal(getDasamshaSignIndex(30), 9); // Taurus → Capricorn
  assert.equal(getDasamshaSignIndex(59), 6); // Taurus 29° → Libra
});

test('Nakshatra pada and degree never overflow', () => {
  const k = calculateKundli('2000-01-01', '00:00', 'Delhi', 28.61, 77.21);
  for (const p of k.planetaryPositions) {
    assert.ok(p.degree >= 0 && p.degree < 30, `${p.name} degree ${p.degree}`);
    assert.ok(p.nakshatraPada >= 1 && p.nakshatraPada <= 4, `${p.name} pada ${p.nakshatraPada}`);
    assert.ok(p.house >= 1 && p.house <= 12);
  }
  assert.ok(k.ayanamsa > 23.8 && k.ayanamsa < 23.9); // Lahiri ≈ 23.85° in 2000
});

test('Unknown birth time flags the Lagna as unreliable and lists possible Moon signs', () => {
  const known = calculateKundli('1990-06-01', '12:00', 'Delhi', 28.61, 77.21);
  assert.deepEqual(known.birthTime, { known: true });

  const k = calculateKundli('1990-06-01', '12:00', 'Delhi', 28.61, 77.21, undefined, { birthTimeKnown: false });
  assert.equal(k.birthTime.known, false);
  assert.equal(k.birthTime.lagnaReliable, false);
  assert.ok(k.birthTime.possibleMoonSigns.includes(k.moonSign));
  assert.ok(k.birthTime.possibleNakshatras.includes(k.nakshatra));
  assert.equal(k.birthTime.moonSignCertain, k.birthTime.possibleMoonSigns.length === 1);
});
