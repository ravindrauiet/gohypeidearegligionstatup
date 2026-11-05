// Buddy matching: pure scoring, highlights and small helpers (no database, no I/O).
// score = round(w.kundli*kundli + w.mindset*mindset + w.distance*distance), each part 0-100.
const { ZODIAC_SIGNS, NAKSHATRAS, SIGN_LORDS, NAKSHATRA_SPAN, GANA_LIST } = require('./astrology_service');
const { calculateAshtakoot, relation } = require('./guna_milan');

const INTENTS = ['life_partner', 'business', 'friend', 'travel', 'spiritual'];
const WEIGHTS = {
  life_partner: { kundli: 0.5, mindset: 0.4, distance: 0.1 },
  other: { kundli: 0.3, mindset: 0.55, distance: 0.15 }
};
const DEFAULT_MAX_KM = 100;
const SHRINK_BELOW = 10; // shared answers needed before the mindset score is fully trusted

// Mindset category weights per intent (1 = neutral).
const CATEGORY_WEIGHTS = {
  base: { values: 1.3, lifestyle: 1, spiritual: 1, career_money: 1, relationships: 1, social: 1, travel: 1 },
  life_partner: { relationships: 1.6, values: 1.5, lifestyle: 1.2, spiritual: 1.1 },
  business: { career_money: 1.8, values: 1.3, social: 1.1, relationships: 0.7, travel: 0.6 },
  friend: { social: 1.5, lifestyle: 1.3, travel: 1.1 },
  travel: { travel: 1.8, lifestyle: 1.3, social: 1.1 },
  spiritual: { spiritual: 1.8, values: 1.4 }
};
const CATEGORY_LABELS = {
  values: 'what matters in life',
  lifestyle: 'daily lifestyle',
  spiritual: 'faith and spirituality',
  career_money: 'work and money',
  relationships: 'relationships',
  social: 'people and social life',
  travel: 'travel'
};

const clamp = (n, lo = 0, hi = 100) => Math.max(lo, Math.min(hi, n));

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/** Whole years between dob ('YYYY-MM-DD') and today ('YYYY-MM-DD'); null if dob is invalid. */
function ageOn(dob, todayIso) {
  const d = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dob || ''));
  const t = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(todayIso || ''));
  if (!d || !t) return null;
  const [dy, dm, dd] = d.slice(1).map(Number);
  const [ty, tm, td] = t.slice(1).map(Number);
  let age = ty - dy;
  if (tm < dm || (tm === dm && td < dd)) age -= 1;
  return age >= 0 ? age : null;
}

/** Coordinates are stored rounded to 2 decimals (~1 km). */
function roundCoord(x) {
  const n = Number(x);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100) / 100;
}

function validLatLng(lat, lng) {
  const a = Number(lat);
  const b = Number(lng);
  return Number.isFinite(a) && Number.isFinite(b) && a >= -90 && a <= 90 && b >= -180 && b <= 180;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  if (![lat1, lng1, lat2, lng2].every((v) => v !== null && v !== undefined && Number.isFinite(Number(v)))) return null;
  const R = 6371;
  const rad = (x) => (Number(x) * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Distance as shown to people: integer km, at least 1; null when unknown. */
function displayKm(km) {
  if (km === null || km === undefined || !Number.isFinite(km)) return null;
  return Math.max(1, Math.round(km));
}

/** Lat/lng box that contains every point within `km` of (lat, lng); used as a SQL prefilter. */
function boundingBox(lat, lng, km) {
  const dLat = km / 111.32;
  const cos = Math.cos((Number(lat) * Math.PI) / 180);
  const dLng = cos < 0.01 ? 180 : Math.min(180, km / (111.32 * cos));
  return { minLat: lat - dLat, maxLat: lat + dLat, minLng: lng - dLng, maxLng: lng + dLng };
}

function normalizeGender(g) {
  const s = String(g || '').trim().toLowerCase();
  if (s === 'm' || s === 'male' || s === 'man') return 'male';
  if (s === 'f' || s === 'female' || s === 'woman') return 'female';
  if (s === 'other' || s === 'non-binary' || s === 'nonbinary') return 'other';
  return null;
}

/** life_partner only: each person's interestedIn must accept the other's gender. */
function lifePartnerCompatible(a, b) {
  const accepts = (interestedIn, gender) => {
    const want = String(interestedIn || 'any').toLowerCase();
    if (want === 'any') return true;
    return normalizeGender(gender) === want;
  };
  return accepts(a.interestedIn, b.gender) && accepts(b.interestedIn, a.gender);
}

/** Intents both people listed, in canonical order; life_partner only when genders fit both ways. */
function sharedIntents(a, b) {
  const mine = new Set(a.intents || []);
  return INTENTS.filter((i) => mine.has(i) && (b.intents || []).includes(i) && (i !== 'life_partner' || lifePartnerCompatible(a, b)));
}

/** Users hidden from me: blocks either direction plus users I have a live/declined request with. */
function excludedUserIds(meId, blocks = [], connections = [], statuses = ['pending', 'accepted', 'declined']) {
  const out = new Set();
  for (const b of blocks) {
    if (Number(b.user_id) === meId) out.add(Number(b.blocked_user_id));
    else if (Number(b.blocked_user_id) === meId) out.add(Number(b.user_id));
  }
  for (const c of connections) {
    if (!statuses.includes(c.status)) continue;
    if (Number(c.from_user_id) === meId) out.add(Number(c.to_user_id));
    else if (Number(c.to_user_id) === meId) out.add(Number(c.from_user_id));
  }
  out.delete(meId);
  return [...out];
}

// ---------------------------------------------------------------------------
// Kundli part
// ---------------------------------------------------------------------------

const ELEMENTS = ['fire', 'earth', 'air', 'water'];

function signIndex(name) {
  const s = String(name || '').trim().split(/\s+/)[0].toLowerCase();
  return ZODIAC_SIGNS.findIndex((z) => z.toLowerCase() === s);
}

function moonSignIndex(k) {
  if (!k) return -1;
  const long = Number(k.moonLongitude);
  if (k.moonLongitude !== null && k.moonLongitude !== undefined && k.moonLongitude !== '' && Number.isFinite(long)) {
    return Math.floor((((long % 360) + 360) % 360) / 30) % 12;
  }
  return signIndex(k.moonSign);
}

function nakshatraIndex(k) {
  if (!k) return -1;
  const long = Number(k.moonLongitude);
  if (k.moonLongitude !== null && k.moonLongitude !== undefined && k.moonLongitude !== '' && Number.isFinite(long)) {
    return Math.floor((((long % 360) + 360) % 360) / NAKSHATRA_SPAN) % 27;
  }
  return NAKSHATRAS.findIndex((n) => n.toLowerCase() === String(k.nakshatra || '').trim().toLowerCase());
}

function elementOf(signIdx) {
  return signIdx >= 0 ? ELEMENTS[signIdx % 4] : null;
}

function elementHarmony(e1, e2) {
  if (!e1 || !e2) return null;
  if (e1 === e2) return 100;
  const pair = [e1, e2].sort().join('-');
  return { 'air-fire': 85, 'earth-water': 85, 'earth-fire': 45, 'air-water': 45, 'fire-water': 35, 'air-earth': 40 }[pair];
}

function ganaHarmony(g1, g2) {
  if (!g1 || !g2) return null;
  if (g1 === g2) return 100;
  const pair = [g1, g2].sort().join('-');
  return { 'Deva-Manushya': 75, 'Manushya-Rakshasa': 40, 'Deva-Rakshasa': 25 }[pair];
}

const FRIENDSHIP_SCORE = { FF: 100, FN: 80, NN: 60, EF: 40, EN: 25, EE: 10 };
function lordFriendship(l1, l2) {
  if (!l1 || !l2) return null;
  if (l1 === l2) return 100;
  return FRIENDSHIP_SCORE[[relation(l1, l2), relation(l2, l1)].sort().join('')];
}

/**
 * Non-marriage intents: Moon-sign element harmony (40%) + nakshatra gana (30%) + Lagna lord friendship (30%).
 * Missing parts are left out and the rest re-weighted; nothing known -> 50.
 */
function harmonyKundliScore(a, b) {
  const m1 = moonSignIndex(a);
  const m2 = moonSignIndex(b);
  const n1 = nakshatraIndex(a);
  const n2 = nakshatraIndex(b);
  const l1 = signIndex(a && a.ascendant);
  const l2 = signIndex(b && b.ascendant);
  const parts = {
    element: elementHarmony(elementOf(m1), elementOf(m2)),
    gana: ganaHarmony(n1 >= 0 ? GANA_LIST[n1] : null, n2 >= 0 ? GANA_LIST[n2] : null),
    lagna: lordFriendship(l1 >= 0 ? SIGN_LORDS[l1] : null, l2 >= 0 ? SIGN_LORDS[l2] : null)
  };
  const w = { element: 0.4, gana: 0.3, lagna: 0.3 };
  let sum = 0;
  let wsum = 0;
  for (const key of Object.keys(w)) {
    if (parts[key] === null || parts[key] === undefined) continue;
    sum += w[key] * parts[key];
    wsum += w[key];
  }
  return { score: wsum ? Math.round(sum / wsum) : 50, parts };
}

/**
 * life_partner: Ashtakoot Guna Milan as a percentage of 36. The classic table is directional
 * (boy/girl): a male/female pair uses that direction, any other pair averages both directions.
 */
function gunaKundliScore(a, b, genderA, genderB) {
  const moon = (k) => ({ moonLongitude: k && k.moonLongitude, moonSign: k && k.moonSign, nakshatra: k && k.nakshatra });
  try {
    const ga = normalizeGender(genderA);
    const gb = normalizeGender(genderB);
    let total;
    let result;
    if (ga === 'male' && gb === 'female') { result = calculateAshtakoot(moon(a), moon(b)); total = result.total; }
    else if (ga === 'female' && gb === 'male') { result = calculateAshtakoot(moon(b), moon(a)); total = result.total; }
    else {
      result = calculateAshtakoot(moon(a), moon(b));
      const r2 = calculateAshtakoot(moon(b), moon(a));
      total = (result.total + r2.total) / 2;
    }
    return { score: Math.round((total / 36) * 100), gunaTotal: Math.round(total * 2) / 2, nadiDosha: result.nadiDosha, bhakootDosha: result.bhakootDosha };
  } catch (_) {
    return { score: 50, gunaTotal: null, nadiDosha: null, bhakootDosha: null };
  }
}

// ---------------------------------------------------------------------------
// Mindset part
// ---------------------------------------------------------------------------

function categoryWeight(intent, category) {
  const specific = CATEGORY_WEIGHTS[intent] || {};
  if (specific[category] !== undefined) return specific[category];
  const base = CATEGORY_WEIGHTS.base[category];
  return base !== undefined ? base : 1;
}

/**
 * Agreement over questions both answered (same option = agree), weighted by category for the intent,
 * shrunk toward 50 when fewer than 10 answers are shared.
 * @param {{[questionId]: number}} a
 * @param {{[questionId]: number}} b
 * @param {(qid:string)=>string|undefined} categoryOf
 */
function mindsetScore(a, b, categoryOf = () => undefined, intent = 'friend') {
  const byCategory = {};
  let shared = 0;
  let agree = 0;
  let wAgree = 0;
  let wTotal = 0;
  for (const qid of Object.keys(a || {})) {
    if (!b || b[qid] === undefined || b[qid] === null || a[qid] === null) continue;
    const same = Number(a[qid]) === Number(b[qid]);
    const cat = categoryOf(qid) || 'other';
    const w = categoryWeight(intent, cat);
    shared += 1;
    wTotal += w;
    if (same) { agree += 1; wAgree += w; }
    byCategory[cat] = byCategory[cat] || { shared: 0, agree: 0 };
    byCategory[cat].shared += 1;
    if (same) byCategory[cat].agree += 1;
  }
  if (!shared) return { score: 50, raw: null, shared: 0, agree: 0, byCategory };
  const raw = (100 * wAgree) / wTotal;
  const trust = Math.min(1, shared / SHRINK_BELOW);
  return { score: Math.round(50 + (raw - 50) * trust), raw: Math.round(raw), shared, agree, byCategory };
}

// ---------------------------------------------------------------------------
// Distance part and total
// ---------------------------------------------------------------------------

function distanceScore(km, maxKm = DEFAULT_MAX_KM) {
  if (km === null || km === undefined || !Number.isFinite(km)) return 50;
  const max = Number(maxKm) > 0 ? Number(maxKm) : DEFAULT_MAX_KM;
  return Math.round(clamp(100 * (1 - km / max)));
}

function weightsFor(intent) {
  return intent === 'life_partner' ? WEIGHTS.life_partner : WEIGHTS.other;
}

function totalScore(intent, breakdown) {
  const w = weightsFor(intent);
  return Math.round(clamp(w.kundli * breakdown.kundli + w.mindset * breakdown.mindset + w.distance * breakdown.distance));
}

// ---------------------------------------------------------------------------
// Highlights: 2-4 short, warm lines from the strongest factors. Never mention the other
// person's sign names, birth details or individual answers.
// ---------------------------------------------------------------------------

const SAME_ELEMENT_LINE = {
  water: 'Both Moons in water signs: easy emotional understanding',
  fire: 'Both Moons in fire signs: shared energy and enthusiasm',
  earth: 'Both Moons in earth signs: a grounded, practical bond',
  air: 'Both Moons in air signs: conversations flow easily'
};

function buildHighlights(f) {
  const lines = [];
  const add = (strength, text) => { if (text && !lines.some((l) => l.text === text)) lines.push({ strength, text }); };

  if (f.intent === 'life_partner' && f.guna && f.guna.gunaTotal !== null) {
    const g = f.guna.gunaTotal;
    if (g >= 27) add(95, `Strong Kundli match: ${g} of 36 Gunas`);
    else if (g >= 18) add(70, `Good Kundli match: ${g} of 36 Gunas`);
    if (f.guna.nadiDosha === false && f.guna.bhakootDosha === false && g >= 18) add(60, 'No major doshas between your charts');
  }

  const e1 = f.elements && f.elements[0];
  const e2 = f.elements && f.elements[1];
  if (e1 && e2) {
    if (e1 === e2) add(85, SAME_ELEMENT_LINE[e1]);
    else if ([e1, e2].sort().join('-') === 'air-fire') add(72, 'Your Moon signs (fire and air) lift each other up');
    else if ([e1, e2].sort().join('-') === 'earth-water') add(72, 'Your Moon signs (earth and water) nurture each other');
  }
  if (f.parts) {
    if (f.parts.gana === 100) add(68, 'Similar natural temperament');
    else if (f.parts.gana === 75) add(55, 'Temperaments that balance each other');
    if (f.parts.lagna === 100) add(66, 'Your rising signs are natural friends');
  }

  const m = f.mindset;
  if (m && m.shared >= 5) {
    const pct = (100 * m.agree) / m.shared;
    if (pct >= 50) add(50 + pct / 2, `You agree on ${m.agree} of ${m.shared} shared questions`);
    let best = null;
    for (const [cat, c] of Object.entries(m.byCategory || {})) {
      if (!CATEGORY_LABELS[cat] || c.shared < 3) continue;
      const r = c.agree / c.shared;
      if (r >= 0.75 && (!best || r > best.r || (r === best.r && c.shared > best.shared))) best = { cat, r, shared: c.shared };
    }
    if (best) add(60 + best.r * 30, `You think alike about ${CATEGORY_LABELS[best.cat]}`);
  }

  if (f.distanceKm !== null && f.distanceKm !== undefined) {
    if (f.distanceKm <= 10) add(65, `Close by: about ${f.distanceKm} km away`);
    else if (f.distanceKm <= 50) add(45, `About ${f.distanceKm} km away: easy to meet up`);
  }
  if (f.sharedLanguages && f.sharedLanguages.length) {
    add(48, `You both speak ${f.sharedLanguages.slice(0, 2).join(' and ')}`);
  }

  lines.sort((x, y) => y.strength - x.strength);
  const out = lines.slice(0, 4).map((l) => l.text);

  // Always at least two lines.
  const fallbacks = [
    f.kundliScore >= 60 ? 'Your Kundlis sit well together' : null,
    m && m.shared > 0 && m.shared < 5 ? `You agree on ${m.agree} of ${m.shared} shared questions` : null,
    !m || m.shared < SHRINK_BELOW ? 'Answer more mindset questions to sharpen this match' : null,
    'A fresh match worth saying hello to'
  ];
  for (const fb of fallbacks) {
    if (out.length >= 2) break;
    if (fb && !out.includes(fb)) out.push(fb);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Whole match
// ---------------------------------------------------------------------------

/**
 * @param {object} me    {kundli:{moonSign,nakshatra,ascendant,moonLongitude}, gender, answers, lat, lng, languages}
 * @param {object} other same shape
 * @param {{intent:string, maxKm?:number, categoryOf?:(qid)=>string}} opts
 */
function scoreMatch(me, other, opts = {}) {
  const intent = INTENTS.includes(opts.intent) ? opts.intent : 'friend';
  const harmony = harmonyKundliScore(me.kundli, other.kundli);
  const guna = intent === 'life_partner' ? gunaKundliScore(me.kundli, other.kundli, me.gender, other.gender) : null;
  const kundli = guna ? guna.score : harmony.score;
  const mindset = mindsetScore(me.answers, other.answers, opts.categoryOf, intent);
  const km = haversineKm(me.lat, me.lng, other.lat, other.lng);
  const distanceKm = displayKm(km);
  const breakdown = { kundli, mindset: mindset.score, distance: distanceScore(km, opts.maxKm) };
  const mineLang = new Set((me.languages || []).map((l) => String(l).toLowerCase()));
  const sharedLanguages = (other.languages || []).filter((l) => mineLang.has(String(l).toLowerCase()));
  const highlights = buildHighlights({
    intent,
    guna,
    parts: harmony.parts,
    elements: [elementOf(moonSignIndex(me.kundli)), elementOf(moonSignIndex(other.kundli))],
    mindset,
    distanceKm,
    sharedLanguages,
    kundliScore: kundli
  });
  return {
    intent,
    score: totalScore(intent, breakdown),
    breakdown,
    highlights,
    sharedAnswers: mindset.shared,
    agreeAnswers: mindset.agree,
    distanceKm,
    km
  };
}

/** Best-scoring intent among the shared ones (falls back to `fallback` when none are shared). */
function bestMatch(me, other, opts = {}, fallback = null) {
  const intents = opts.intent && opts.intent !== 'all' ? [opts.intent] : sharedIntents(me, other);
  const list = intents.length ? intents : (fallback ? [fallback] : []);
  let best = null;
  for (const intent of list) {
    const r = scoreMatch(me, other, { ...opts, intent });
    if (!best || r.score > best.score) best = r;
  }
  return best;
}

module.exports = {
  INTENTS,
  WEIGHTS,
  DEFAULT_MAX_KM,
  CATEGORY_LABELS,
  ageOn,
  roundCoord,
  validLatLng,
  haversineKm,
  displayKm,
  boundingBox,
  normalizeGender,
  lifePartnerCompatible,
  sharedIntents,
  excludedUserIds,
  elementOf,
  moonSignIndex,
  nakshatraIndex,
  elementHarmony,
  ganaHarmony,
  lordFriendship,
  harmonyKundliScore,
  gunaKundliScore,
  mindsetScore,
  distanceScore,
  totalScore,
  buildHighlights,
  scoreMatch,
  bestMatch
};
