// Game logic for Graha Quest, Nakshatra Cards, Moksha Patam and Cosmic Match.
// Pure functions only (no database): everything here is driven by the stored Kundli and the
// rules-only day computation of the forecast engine. routes/game.js owns persistence.
const A = require('./astrology_service');
const F = require('./forecast_service');
const G = require('./game_content');

const PLANETS = G.PLANET_ORDER;
const ALL_DONE_BONUS_XP = 50;
const MAX_CIRCLE = 30;

class GameError extends Error {
  constructor(status, code, message, extra) {
    super(message);
    this.name = 'GameError';
    this.statusCode = status;
    this.code = code;
    this.extra = extra || null;
  }
}

// ---------------------------------------------------------------------------
// Config (wallet credits are real money in this app: small, capped, switchable)
// ---------------------------------------------------------------------------
function intEnv(v, def, lo, hi) {
  if (v === undefined || v === null || String(v).trim() === '') return def;
  const x = Math.floor(Number(v));
  if (!Number.isFinite(x)) return def;
  return Math.max(lo, Math.min(hi, x));
}
function config(env = process.env) {
  return {
    walletRewards: String(env.GAME_WALLET_REWARDS || 'true').toLowerCase() !== 'false',
    setReward: intEnv(env.GAME_SET_REWARD_AMOUNT, 11, 0, 500),
    fullSetReward: intEnv(env.GAME_FULL_SET_REWARD_AMOUNT, 51, 0, 1000),
    mokshaWinXp: intEnv(env.GAME_MOKSHA_WIN_XP, 200, 0, 5000),
    mokshaWinWallet: intEnv(env.GAME_MOKSHA_WIN_WALLET, 0, 0, 500)
  };
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
// FNV-1a 32-bit: stable seeded choice per (user, date, slot)
function hash(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}
const fmtNum = (x) => (Math.abs(x - Math.round(x)) < 1e-9 ? String(Math.round(x)) : (Math.round(x * 10) / 10).toFixed(1));
const round1 = (x) => Math.round(x * 10) / 10;
const dateStr = (d) => (d ? String(d).slice(0, 10) : null);

const cache = new Map();
function cached(key, fn, max = 600) {
  if (cache.has(key)) return cache.get(key);
  const v = fn();
  if (cache.size >= max) cache.delete(cache.keys().next().value);
  cache.set(key, v);
  return v;
}

// ---------------------------------------------------------------------------
// Player level / streak
// Level n needs 100*n XP to reach n+1, so total XP to reach level L is 50*L*(L-1).
// ---------------------------------------------------------------------------
function levelInfo(xp) {
  const total = Math.max(0, Math.floor(Number(xp) || 0));
  let level = Math.floor((1 + Math.sqrt(1 + total / 12.5)) / 2);
  while (50 * level * (level + 1) <= total) level++;
  while (level > 1 && 50 * level * (level - 1) > total) level--;
  return { level, xpIntoLevel: total - 50 * level * (level - 1), xpForNext: 100 * level };
}

function normProfile(gp) {
  const g = gp || {};
  return {
    xp: Number(g.xp) || 0,
    streak: Number(g.streak) || 0,
    bestStreak: Number(g.best_streak ?? g.bestStreak) || 0,
    lastMissionDate: dateStr(g.last_mission_date ?? g.lastMissionDate),
    planetXp: (g.planet_xp ?? g.planetXp) && typeof (g.planet_xp ?? g.planetXp) === 'object' ? { ...(g.planet_xp ?? g.planetXp) } : {},
    bonusRollDate: dateStr(g.bonus_roll_date ?? g.bonusRollDate)
  };
}

// The streak shown today: still alive if the last mission was today or yesterday
function currentStreak(p, today) {
  if (!p.lastMissionDate) return 0;
  if (p.lastMissionDate === today || p.lastMissionDate === F.isoAdd(today, -1)) return p.streak;
  return 0;
}

// Streak after completing a mission on `today`
function streakAfterMission(p, today) {
  let streak = p.streak;
  if (p.lastMissionDate === today) streak = Math.max(1, streak);
  else if (p.lastMissionDate === F.isoAdd(today, -1)) streak += 1;
  else streak = 1;
  return { streak, bestStreak: Math.max(p.bestStreak, streak), lastMissionDate: today };
}

function playerView(gp, today) {
  const p = normProfile(gp);
  const lv = levelInfo(p.xp);
  return {
    level: lv.level,
    xp: p.xp,
    xpIntoLevel: lv.xpIntoLevel,
    xpForNext: lv.xpForNext,
    title: G.playerTitle(lv.level),
    streak: currentStreak(p, today),
    bestStreak: p.bestStreak,
    streakAliveToday: p.lastMissionDate === today
  };
}

// ---------------------------------------------------------------------------
// Planet strength from the birth chart
// ---------------------------------------------------------------------------
const DIGNITY_KEY = { exalted: 'exalted', 'own sign': 'own', 'friendly sign': 'friend', 'neutral sign': 'neutral', 'enemy sign': 'enemy', debilitated: 'debilitated' };
const DIGNITY_BASE = { exalted: 85, moolatrikona: 78, own: 72, friend: 58, neutral: 48, enemy: 36, debilitated: 25 };
// Moolatrikona: [sign index, from degree, to degree]. The Moon (Taurus) and Mercury (Virgo) share their
// exaltation sign, which the forecast engine already reports as "exalted".
const MOOLATRIKONA = { Sun: [4, 0, 20], Mars: [0, 0, 12], Jupiter: [8, 0, 10], Venus: [6, 0, 15], Saturn: [10, 0, 20] };
const XP_PER_POWER = 20;

/**
 * @param kundli stored kundli (for retrograde flags)
 * @param natal  forecast natal facts (F.createContext(kundli).natal)
 * @returns {{[planet]: {dignity, base, sign, retrograde, line}}}
 */
function natalStrength(kundli, natal) {
  const retro = {};
  for (const p of Array.isArray(kundli && kundli.planetaryPositions) ? kundli.planetaryPositions : []) {
    const name = String(p.name || p.planet || '').split(' ')[0];
    retro[name] = /retro/i.test(String(p.speed || '')) || p.retrograde === true;
  }
  const out = {};
  for (const planet of PLANETS) {
    const inf = natal && natal.info ? natal.info[planet] : null;
    const long = natal && natal.planets ? natal.planets[planet] : null;
    if (!inf || !Number.isFinite(long)) {
      out[planet] = { dignity: 'neutral', base: DIGNITY_BASE.neutral, sign: null, retrograde: false, line: 'Balanced in your chart: follows your effort' };
      continue;
    }
    const signIdx = Math.floor(long / 30) % 12;
    const deg = long % 30;
    let dignity = DIGNITY_KEY[inf.dignity] || 'neutral';
    const mt = MOOLATRIKONA[planet];
    if (dignity === 'own' && mt && mt[0] === signIdx && deg >= mt[1] && deg < mt[2]) dignity = 'moolatrikona';
    let base = DIGNITY_BASE[dignity];
    let line;
    if (planet === 'Rahu' || planet === 'Ketu') {
      // Shadow planets own no sign: they borrow from their host, so keep them nearer the middle
      base = Math.round(50 + (base - 50) * 0.5);
      line = G.SHADOW_LINE[planet](inf.sign, A.SIGN_LORDS[signIdx]);
    } else {
      const isRetro = !!retro[planet] && planet !== 'Sun' && planet !== 'Moon';
      line = G.DIGNITY_LINE[dignity](inf.sign) + (isRetro ? G.RETRO_NOTE : '');
      out[planet] = { dignity, base, sign: inf.sign, retrograde: isRetro, line };
      continue;
    }
    out[planet] = { dignity, base, sign: inf.sign, retrograde: true, line };
  }
  return out;
}

function planetPower(base, xp) {
  return clamp(Math.round(base + Math.floor((Number(xp) || 0) / XP_PER_POWER)), 0, 100);
}
const planetLevel = (power) => clamp(Math.ceil(power / 10), 1, 10);
const planetStatus = (power) => (power >= 66 ? 'strong' : power >= 45 ? 'steady' : 'needs_care');

function planetViews(strength, planetXp) {
  return PLANETS.map((planet) => {
    const s = strength[planet];
    const xp = Math.max(0, Math.floor(Number(planetXp && planetXp[planet]) || 0));
    const power = planetPower(s.base, xp);
    const level = planetLevel(power);
    const ch = G.PLANET_CHARACTERS[planet];
    return {
      planet, level, power, natal: s.line, status: planetStatus(power), role: ch.role, xp,
      // additive
      emoji: ch.emoji, title: G.planetTitle(planet, level), personality: ch.personality
    };
  });
}

// ---------------------------------------------------------------------------
// Daily missions: 3 different planets, deterministic per (user, local date)
// ---------------------------------------------------------------------------
const SLOW_PLANETS = ['Saturn', 'Jupiter', 'Rahu', 'Ketu', 'Mars'];
const rotate = (arr, i) => (arr.length ? arr.slice(i % arr.length).concat(arr.slice(0, i % arr.length)) : arr);

/**
 * @param o { userId, date, day: F.dayLite(ctx, date), strength: natalStrength(), recentKeys: Set<missionKey> done in the previous 7 days }
 * @returns [{ id, key, planet, title, why, xp, category, reason }]
 */
function pickMissions({ userId, date, day, strength, recentKeys }) {
  const recent = recentKeys instanceof Set ? recentKeys : new Set(recentKeys || []);
  const seed = (tag) => hash(`${userId}|${date}|${tag}`);
  const tr = {};
  for (const t of day.transits) tr[t.planet] = t;
  const used = new Set();
  const slots = [];
  const take = (cands) => {
    const c = cands.find((x) => x && PLANETS.includes(x.planet) && !used.has(x.planet));
    if (!c) return false;
    used.add(c.planet);
    slots.push(c);
    return true;
  };

  // (a) Needs care: a tough slow transit right now, or one of the two weakest planets in the birth chart
  const candA = [];
  for (const p of SLOW_PLANETS) {
    if (tr[p] && tr[p].effect === 'challenging') candA.push({ planet: p, type: 'transit_tough', simple: tr[p].simple });
  }
  const weakest = PLANETS.slice().sort((a, b) => strength[a].base - strength[b].base || PLANETS.indexOf(a) - PLANETS.indexOf(b)).slice(0, 2);
  for (const p of weakest) if (!candA.some((c) => c.planet === p)) candA.push({ planet: p, type: 'natal_weak' });
  take(rotate(candA, seed('a')));

  // (b) Today's Moon (Tara Bala / Chandrashtama) or the lord of the weekday
  const moonCand = day.chandrashtama
    ? { planet: 'Moon', type: 'chandrashtama' }
    : { planet: 'Moon', type: 'tara', tara: day.tara.name, favorable: day.tara.favorable };
  const dayCand = { planet: day.dayLord, type: 'day_lord' };
  const nakCand = { planet: A.NAKSHATRA_LORDS[day.moonNakIndex % 9], type: 'nak_lord', nakshatra: day.moonNakshatra };
  const firstTwo = day.chandrashtama || seed('b') % 2 === 0 ? [moonCand, dayCand] : [dayCand, moonCand];
  take([...firstTwo, nakCand]);

  // (c) The running dasha / antardasha lord, or today's most supportive transit
  const good = day.transits
    .filter((t) => t.effect === 'favorable')
    .sort((x, y) => (F.W_DAY[y.planet] || 0) - (F.W_DAY[x.planet] || 0))
    .map((t) => ({ planet: t.planet, type: 'transit_good', simple: t.simple }));
  const head = [{ planet: day.dasha.antardasha, type: 'antardasha' }, { planet: day.dasha.mahadasha, type: 'dasha' }];
  if (good[0]) head.push(good[0]);
  take([...rotate(head, seed('c')), ...good.slice(1)]);

  // Safety net: always three different planets
  const rest = rotate(PLANETS, seed('f')).map((p) => ({ planet: p, type: 'fallback' }));
  while (slots.length < 3 && take(rest)) { /* filled */ }

  const usedCategories = new Set();
  return slots.map((reason) => {
    const lib = G.MISSIONS[reason.planet];
    let pool = lib.filter((x) => !recent.has(x.key));
    if (!pool.length) pool = lib;
    const fresh = pool.filter((x) => !usedCategories.has(x.c));
    if (fresh.length) pool = fresh;
    const pick = pool[seed(`m|${reason.planet}`) % pool.length];
    usedCategories.add(pick.c);
    return {
      id: `${date}_${pick.key}`,
      key: pick.key,
      planet: reason.planet,
      title: pick.title,
      why: G.whyLine(reason),
      xp: pick.xp,
      category: pick.c,
      reason: reason.type
    };
  });
}

function missionsView(missions, doneIds, date, bonusRollGranted) {
  const done = doneIds instanceof Set ? doneIds : new Set(doneIds || []);
  const items = missions.map((x) => ({
    id: x.id, planet: x.planet, title: x.title, why: x.why, xp: x.xp, done: done.has(x.id), category: x.category
  }));
  const completedCount = items.filter((x) => x.done).length;
  return {
    date,
    items,
    completedCount,
    allDone: completedCount === items.length && items.length > 0,
    allDoneBonusXp: ALL_DONE_BONUS_XP,
    bonusRollGranted: !!bonusRollGranted
  };
}

// ---------------------------------------------------------------------------
// Luck (Tara Bala in plain words)
// ---------------------------------------------------------------------------
function luckView(day) {
  if (!day) return { tara: 'Steady', favorable: false, chandrashtama: false, line: 'A steady, ordinary sky today' };
  return {
    tara: day.tara.name,
    favorable: !!day.tara.favorable,
    chandrashtama: !!day.chandrashtama,
    line: day.chandrashtama ? G.CHANDRASHTAMA_LINE : (G.LUCK_LINES[day.tara.name] || `${day.tara.name} Tara`)
  };
}

// ---------------------------------------------------------------------------
// Nakshatra cards
// ---------------------------------------------------------------------------
const NAK_INDEX_BY_ID = {};
G.NAKSHATRA_CARDS.forEach((_, i) => { NAK_INDEX_BY_ID[G.nakCardId(i)] = i; });
const ECLIPSE_ID = /^rare:(solar|lunar)_eclipse_(\d{4}-\d{2}-\d{2})$/;

function cardRarity(id) {
  if (id in NAK_INDEX_BY_ID) return 'common';
  if (G.RARE_STATIC[id]) return G.RARE_STATIC[id].rarity;
  if (ECLIPSE_ID.test(id)) return 'legendary';
  return 'rare';
}
const cardXp = (id) => G.CARD_XP[cardRarity(id)];
const cardKind = (id) => (id in NAK_INDEX_BY_ID ? 'nakshatra' : 'rare');

/**
 * @param id card id
 * @param o { birthNak: 0-26, collected: Map<cardId, 'YYYY-MM-DD'> }
 */
function buildCard(id, o = {}) {
  const collected = o.collected || new Map();
  const on = collected.get(id) || null;
  const base = { id, collected: collected.has(id), collectedOn: on };
  if (id in NAK_INDEX_BY_ID) {
    const i = NAK_INDEX_BY_ID[id];
    const c = G.NAKSHATRA_CARDS[i];
    return {
      id, kind: 'nakshatra', name: c.name, symbol: c.symbol, ruler: c.ruler, deity: c.deity, power: c.power,
      keywords: c.keywords.slice(), rarity: 'common', isBirthStar: i === o.birthNak, collected: base.collected, collectedOn: on,
      number: i + 1
    };
  }
  let meta = G.RARE_STATIC[id] || G.FESTIVAL_CARD_BY_ID[id] || null;
  const ecl = ECLIPSE_ID.exec(id);
  if (ecl) meta = G.eclipseCardMeta(ecl[1], ecl[2]);
  if (!meta) meta = { name: 'Mystery Card', symbol: '✨', power: 'A rare gift from the sky', keywords: ['rare'] };
  const card = {
    id, kind: 'rare', name: meta.name, symbol: meta.symbol, ruler: null, deity: null, power: meta.power,
    keywords: (meta.keywords || []).slice(), rarity: meta.rarity || 'rare', isBirthStar: id === 'rare:birth_star',
    collected: base.collected, collectedOn: on
  };
  if (meta.how) card.how = meta.how;
  if (ecl) card.date = ecl[2];
  return card;
}

const RARE_EVENT_TYPES = new Set(['full_moon', 'solar_eclipse', 'lunar_eclipse', 'festival']);
function rareIdForEvent(e) {
  if (e.type === 'full_moon') return 'rare:purnima';
  if (e.type === 'solar_eclipse') return `rare:solar_eclipse_${e.date}`;
  if (e.type === 'lunar_eclipse') return `rare:lunar_eclipse_${e.date}`;
  if (e.type === 'festival' && G.FESTIVAL_CARDS[e.title]) return G.FESTIVAL_CARDS[e.title].id;
  return null;
}
// Sky-driven rare cards per date in [from, to] (cached per chart/location)
function rareEvents(ctx, from, to) {
  return cached(`rare|${ctx.hash}|${from}|${to}`, () => {
    const out = [];
    for (const e of F.eventsBetween(ctx, from, to, { chandrashtama: false })) {
      if (!RARE_EVENT_TYPES.has(e.type)) continue;
      const id = rareIdForEvent(e);
      if (id && !out.some((x) => x.id === id && x.date === e.date)) out.push({ id, date: e.date });
    }
    return out;
  });
}

/**
 * Cards that can be collected on `date`.
 * @returns {{ nakIndex, cardId, extraIds: string[] }}
 */
function cardsAvailable(ctx, date, o = {}) {
  const nakIndex = F.moonNakAtSunrise(ctx, date);
  const extraIds = [];
  if (nakIndex === ctx.natal.moonNak) extraIds.push('rare:birth_star');
  for (const e of rareEvents(ctx, date, date)) if (!extraIds.includes(e.id)) extraIds.push(e.id);
  for (const days of G.STREAK_MILESTONES) if ((Number(o.bestStreak) || 0) >= days) extraIds.push(`rare:streak_${days}`);
  return { nakIndex, cardId: G.nakCardId(nakIndex), extraIds };
}

function setReward(set, o = {}) {
  const cfg = o.config || config();
  const walletAmount = set.rewardKind === 'row' ? cfg.setReward : set.rewardKind === 'full' ? cfg.fullSetReward : 0;
  if (walletAmount > 0 && cfg.walletRewards && o.registered) {
    return { type: 'wallet', amount: walletAmount, label: `₹${walletAmount} wallet credit` };
  }
  return { type: 'xp', amount: set.xp, label: `${set.xp} XP` };
}

function setsView(o) {
  const collected = o.collected || new Map();
  const claimed = o.claimed instanceof Set ? o.claimed : new Set(o.claimed || []);
  return G.CARD_SETS.map((s) => {
    const cardIds = s.indices(o.birthNak).map((i) => G.nakCardId(i));
    const have = cardIds.filter((id) => collected.has(id)).length;
    return {
      id: s.id, name: s.name, cardIds, collected: have, complete: have === cardIds.length,
      reward: setReward(s, o), claimed: claimed.has(s.id)
    };
  });
}

// Next uncollected nakshatra cards (when the Moon reaches them at sunrise) + next rare sky events
function upcomingCards(ctx, today, o) {
  const collected = o.collected || new Map();
  const out = [];
  const seen = new Set();
  for (let i = 1; i <= 45 && seen.size < 5; i++) {
    const date = F.isoAdd(today, i);
    const idx = F.moonNakAtSunrise(ctx, date);
    const id = G.nakCardId(idx);
    if (collected.has(id) || seen.has(id)) continue;
    seen.add(id);
    out.push({ card: buildCard(id, o), date });
  }
  const rares = new Set();
  if (!collected.has('rare:birth_star')) {
    for (let i = 1; i <= 30; i++) {
      const date = F.isoAdd(today, i);
      if (F.moonNakAtSunrise(ctx, date) === ctx.natal.moonNak) {
        rares.add('rare:birth_star');
        out.push({ card: buildCard('rare:birth_star', o), date });
        break;
      }
    }
  }
  for (const e of rareEvents(ctx, F.isoAdd(today, 1), F.isoAdd(today, 45))) {
    if (collected.has(e.id) || rares.has(e.id) || rares.size >= 4) continue;
    rares.add(e.id);
    out.push({ card: buildCard(e.id, o), date: e.date });
  }
  return out.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

// Every rare card this user knows about: the fixed catalogue + collected / upcoming eclipse cards
function rareCatalogue(ctx, today, o) {
  const collected = o.collected || new Map();
  const ids = [...Object.keys(G.RARE_STATIC), ...Object.values(G.FESTIVAL_CARDS).map((f) => f.id)];
  for (const id of collected.keys()) if (cardKind(id) === 'rare' && !ids.includes(id)) ids.push(id);
  const eclipses = cached(`ecl|${ctx.hash}|${today}`, () => F.eclipseDays(ctx, today, F.isoAdd(today, 400)));
  for (const e of eclipses.slice(0, 3)) {
    const id = `rare:${e.kind}_eclipse_${e.date}`;
    if (!ids.includes(id)) ids.push(id);
  }
  return ids.map((id) => buildCard(id, o));
}

// ---------------------------------------------------------------------------
// Moksha Patam
// ---------------------------------------------------------------------------
const LADDER_AT = new Map(G.BOARD.ladders.map((l) => [l.from, l]));
const SNAKE_AT = new Map(G.BOARD.snakes.map((s) => [s.from, s]));

// Daily rolls: 1 base, +1 when Tara Bala is favourable (not on Chandrashtama), +1 for 'self' after all 3 missions
function rollsAllowed(day, o = {}) {
  let n = 1;
  if (day && day.tara.favorable && !day.chandrashtama) n += 1;
  if (o.isSelf && o.bonusRoll) n += 1;
  return n;
}
function rollsLeft(row, today, day, o = {}) {
  const used = row && dateStr(row.rolls_date) === today ? Number(row.rolls_used) || 0 : 0;
  return Math.max(0, rollsAllowed(day, o) - used);
}

function applyRoll(position, dice) {
  const from = clamp(Math.floor(Number(position) || 1), 1, 100);
  if (!Number.isInteger(dice) || dice < 1 || dice > 6) throw new RangeError('dice must be 1-6');
  if (from + dice > 100) {
    return { from, landed: from, to: from, event: null, overshoot: true, won: false };
  }
  const landed = from + dice;
  let to = landed;
  let event = null;
  if (LADDER_AT.has(landed)) {
    const l = LADDER_AT.get(landed);
    to = l.to;
    event = { type: 'ladder', name: l.name, line: l.line };
  } else if (SNAKE_AT.has(landed)) {
    const s = SNAKE_AT.get(landed);
    to = s.to;
    event = { type: 'snake', name: s.name, line: s.line };
  }
  return { from, landed, to, event, overshoot: false, won: to === 100 };
}

function moveLabel(r) {
  if (r.won) return 'Moksha!';
  if (r.overshoot) return 'Needs an exact roll';
  if (r.event) return `${r.event.type === 'ladder' ? 'Ladder' : 'Snake'}: ${r.event.name}`;
  return null;
}

function nextRollHint(o = {}) {
  if (o.isSelf && !o.bonusRoll) return 'No rolls left for now. Finish all 3 of today\'s missions for a bonus roll, or come back tomorrow for fresh ones.';
  return 'No rolls left today. Fresh rolls arrive tomorrow, with an extra one on your lucky-star days.';
}

// ---------------------------------------------------------------------------
// Cosmic Match
// ---------------------------------------------------------------------------
function moonProfile(kundli) {
  if (!kundli) return null;
  return { moonLongitude: kundli.moonLongitude, moonSign: kundli.moonSign, nakshatra: kundli.nakshatra };
}

/**
 * Direction-independent Ashtakoot: the classic table is written for bride/groom and is not
 * symmetric (Varna, Vashya, Gana), so every koota is averaged over both directions.
 * @returns {{score, max, label, strongest, weakest, kootas: {[name]: {score, max}}}|null}
 */
function compatibility(a, b) {
  let r1;
  let r2;
  try {
    r1 = A.calculateAshtakoot(a, b);
    r2 = A.calculateAshtakoot(b, a);
  } catch (_) {
    return null;
  }
  const kootas = {};
  let total = 0;
  r1.kootas.forEach((k, i) => {
    const score = (k.score + r2.kootas[i].score) / 2;
    kootas[k.name] = { score, max: k.max };
    total += score;
  });
  const names = Object.keys(kootas);
  const ratio = (nm) => kootas[nm].score / kootas[nm].max;
  // ties: the heavier koota matters more
  const strongest = names.slice().sort((x, y) => ratio(y) - ratio(x) || kootas[y].max - kootas[x].max)[0];
  const weakest = names.slice().sort((x, y) => ratio(x) - ratio(y) || kootas[y].max - kootas[x].max)[0];
  const score = round1(total);
  return {
    score, max: 36, label: G.compatLabel(score),
    strongest: G.KOOTA_PLAIN[strongest].strong,
    weakest: ratio(weakest) >= 1 ? 'Honestly, nothing major. You two fit well' : G.KOOTA_PLAIN[weakest].weak,
    kootas
  };
}
const publicCompat = (c) => (c ? { score: c.score, max: c.max, label: c.label, strongest: c.strongest, weakest: c.weakest } : null);

// Today's score/mood from the rules-only forecast day (no AI), cached per chart + date
function dayScore(kundli, date, opts = {}) {
  try {
    const ctx = F.createContext(kundli, opts);
    return cached(`score|${ctx.hash}|${date}`, () => {
      const d = F.dayLite(ctx, date);
      return { todayScore: d.overall, mood: d.mood };
    });
  } catch (_) {
    return { todayScore: null, mood: null };
  }
}

/**
 * @param members [{ id, name, todayScore, mood, _compat }]  (_compat = compatibility() result or null)
 */
function buildRankings(members) {
  const size = members.length;
  const withCompat = members.filter((x) => x._compat);
  return G.RANKINGS.map((r) => {
    const unlocked = size >= r.needMembers;
    let entries = [];
    if (unlocked) {
      if (r.id === 'luckiestToday') {
        entries = members.filter((x) => Number.isFinite(x.todayScore))
          .sort((x, y) => y.todayScore - x.todayScore || String(x.name).localeCompare(String(y.name)))
          .map((x) => ({ memberId: x.id, name: x.name, value: String(x.todayScore), note: G.MOOD_NOTES[x.mood] || 'A steady day' }));
      } else if (r.id === 'cosmicTwin') {
        entries = withCompat.slice()
          .sort((x, y) => y._compat.score - x._compat.score || String(x.name).localeCompare(String(y.name)))
          .map((x) => ({ memberId: x.id, name: x.name, value: `${fmtNum(x._compat.score)}/36`, note: G.COMPAT_NOTES[x._compat.label] }));
      } else {
        const max = r.kootas.reduce((s, k) => s + withCompatMax(k), 0);
        entries = withCompat.map((x) => {
          const sum = r.kootas.reduce((s, k) => s + x._compat.kootas[k].score, 0);
          const best = r.kootas.slice().sort((p, q) => x._compat.kootas[q].score / x._compat.kootas[q].max - x._compat.kootas[p].score / x._compat.kootas[p].max)[0];
          return { m: x, sum, note: sum / max >= 0.5 ? G.KOOTA_PLAIN[best].strong : r.note };
        })
          .sort((x, y) => y.sum - x.sum || y.m._compat.score - x.m._compat.score || String(x.m.name).localeCompare(String(y.m.name)))
          .map((x) => ({ memberId: x.m.id, name: x.m.name, value: `${fmtNum(x.sum)}/${max}`, note: x.note }));
      }
    }
    return { id: r.id, title: r.title, emoji: r.emoji, unlocked, needMembers: r.needMembers, entries: entries.slice(0, 3) };
  });
}
const KOOTA_MAX = { Varna: 1, Vashya: 2, Tara: 3, Yoni: 4, Maitri: 5, Gana: 6, Bhakoot: 7, Nadi: 8 };
function withCompatMax(k) { return KOOTA_MAX[k]; }

const INVITE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no I, L, O, 0, 1
function newInviteCode(randomInt, length = 6) {
  let s = '';
  for (let i = 0; i < length; i++) s += INVITE_ALPHABET[randomInt(0, INVITE_ALPHABET.length)];
  return s;
}
function normalizeInviteCode(raw) {
  if (typeof raw !== 'string') return null;
  const c = raw.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return c.length >= 4 && c.length <= 12 ? c : null;
}
function shareText(code) {
  return code
    ? `Join my Cosmic Circle on CosmicGuide! Enter my code ${code} and see how our stars match ✨`
    : 'Come play on CosmicGuide and see how our stars match ✨';
}

module.exports = {
  GameError,
  config,
  hash,
  ALL_DONE_BONUS_XP,
  MAX_CIRCLE,
  XP_PER_POWER,
  DIGNITY_BASE,
  levelInfo,
  normProfile,
  currentStreak,
  streakAfterMission,
  playerView,
  natalStrength,
  planetPower,
  planetLevel,
  planetStatus,
  planetViews,
  pickMissions,
  missionsView,
  luckView,
  cardRarity,
  cardXp,
  cardKind,
  buildCard,
  cardsAvailable,
  rareEvents,
  setReward,
  setsView,
  upcomingCards,
  rareCatalogue,
  rollsAllowed,
  rollsLeft,
  applyRoll,
  moveLabel,
  nextRollHint,
  moonProfile,
  compatibility,
  publicCompat,
  dayScore,
  buildRankings,
  KOOTA_MAX,
  INVITE_ALPHABET,
  newInviteCode,
  normalizeInviteCode,
  shareText
};
