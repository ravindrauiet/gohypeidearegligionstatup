// Ashtakoot Guna Milan (36-point Vedic compatibility), shared by the horoscope synastry
// route, the games and Buddy matching. Moved out of astrology_service.js unchanged;
// astrology_service still re-exports `calculateAshtakoot` for existing callers.
const A = require('./astrology_service');

const {
  AstrologyInputError,
  ZODIAC_SIGNS,
  NAKSHATRAS,
  SIGN_LORDS,
  NAKSHATRA_SPAN,
  GANA_LIST,
  NADI_LIST,
  YONI_LIST,
  VARNA_BY_SIGN,
  vashyaForLongitude,
  norm360,
  signIndexOf
} = A;

const PLANET_FRIENDS = {
  Sun: { friends: ['Moon', 'Mars', 'Jupiter'], enemies: ['Venus', 'Saturn'] },
  Moon: { friends: ['Sun', 'Mercury'], enemies: [] },
  Mars: { friends: ['Sun', 'Moon', 'Jupiter'], enemies: ['Mercury'] },
  Mercury: { friends: ['Sun', 'Venus'], enemies: ['Moon'] },
  Jupiter: { friends: ['Sun', 'Moon', 'Mars'], enemies: ['Mercury', 'Venus'] },
  Venus: { friends: ['Mercury', 'Saturn'], enemies: ['Sun', 'Moon'] },
  Saturn: { friends: ['Mercury', 'Venus'], enemies: ['Sun', 'Moon', 'Mars'] }
};

/** Natural relationship of planet a towards planet b: 'F' friend, 'N' neutral, 'E' enemy. */
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
// Moon longitude as a number, or null when unknown. null / '' must not become 0° (Number(null) === 0),
// which would silently treat every chart without a stored longitude as Ashwini / Aries.
function moonLongitudeOf(p) {
  const v = p && p.moonLongitude;
  if (v === null || v === undefined || (typeof v === 'string' && v.trim() === '')) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function calculateAshtakoot(boy, girl) {
  const prep = (p) => {
    const moonLong = moonLongitudeOf(p);
    const nakIdx = moonLong !== null
      ? Math.floor(norm360(moonLong) / NAKSHATRA_SPAN) % 27
      : NAKSHATRAS.indexOf(p.nakshatra);
    const signIdx = moonLong !== null
      ? signIndexOf(moonLong)
      : ZODIAC_SIGNS.indexOf(p.moonSign);
    if (nakIdx < 0 || signIdx < 0) throw new AstrologyInputError('Moon sign / nakshatra unavailable for Guna Milan');
    const long = moonLong !== null ? moonLong : signIdx * 30 + 7.5;
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

module.exports = {
  calculateAshtakoot,
  relation,
  PLANET_FRIENDS,
  GANA_ORDER
};
