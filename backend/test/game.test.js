// Games: content sanity, rules and API contract shapes (no database). Run: npm test
const test = require('node:test');
const assert = require('node:assert/strict');
const A = require('../services/astrology_service');
const F = require('../services/forecast_service');
const G = require('../services/game_content');
const S = require('../services/game_service');

const NOW = Date.parse('2026-10-07T06:00:00Z');
const PLANETS = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];

function chart(dob, tob, lat = 28.61, lng = 77.21, name = 'Asha Rao') {
  const k = A.calculateKundli(dob, tob, 'Test', lat, lng);
  k.birthDetails = { fullName: name, latitude: lat, longitude: lng };
  return k;
}
const CHARTS = [chart('1990-05-15', '06:30'), chart('1988-11-02', '22:30', 19.07, 72.87), chart('2001-01-20', '13:05', 13.08, 80.27), chart('1975-08-09', '03:15', 40.71, -74.0)];
const ctxFor = (k) => F.createContext(k, { nowMs: NOW });

// ---------------------------------------------------------------------------
// Contract shape validators (also used by the HTTP e2e script)
// ---------------------------------------------------------------------------
const ISO = /^\d{4}-\d{2}-\d{2}$/;
const isStr = (x) => typeof x === 'string' && x.length > 0;
const isInt = (x, lo = -Infinity, hi = Infinity) => Number.isInteger(x) && x >= lo && x <= hi;
const isBool = (x) => typeof x === 'boolean';
const MOODS = ['excellent', 'good', 'mixed', 'challenging'];
const COMPAT_LABELS = ['Soul-level', 'Strong', 'Easy', 'Spicy', 'Opposites'];
const RANKING_IDS = ['cosmicTwin', 'luckiestToday', 'funPartner', 'travelBuddy', 'businessPartner', 'calmingPresence'];

function checkPlayer(p) {
  assert.ok(isInt(p.level, 1), 'player.level');
  assert.ok(isInt(p.xp, 0), 'player.xp');
  assert.ok(isInt(p.xpIntoLevel, 0), 'player.xpIntoLevel');
  assert.equal(p.xpForNext, 100 * p.level);
  assert.ok(p.xpIntoLevel < p.xpForNext);
  assert.ok(isStr(p.title));
  assert.ok(isInt(p.streak, 0) && isInt(p.bestStreak, 0) && p.bestStreak >= p.streak);
  assert.ok(isBool(p.streakAliveToday));
}
function checkPlanet(p) {
  assert.ok(PLANETS.includes(p.planet));
  assert.ok(isInt(p.level, 1, 10), 'planet.level');
  assert.ok(isInt(p.power, 0, 100), 'planet.power');
  assert.ok(isStr(p.natal));
  assert.ok(['strong', 'steady', 'needs_care'].includes(p.status));
  assert.ok(isStr(p.role));
  assert.ok(isInt(p.xp, 0));
}
function checkPlanets(list) {
  assert.equal(list.length, 9);
  assert.deepEqual(list.map((p) => p.planet), PLANETS);
  list.forEach(checkPlanet);
}
function checkMission(m) {
  assert.ok(isStr(m.id));
  assert.ok(PLANETS.includes(m.planet));
  assert.ok(isStr(m.title) && m.title.length <= 70, `title too long: ${m.title}`);
  assert.ok(isStr(m.why) && m.why.length <= 200, `why: ${m.why}`);
  assert.ok([20, 30, 40].includes(m.xp));
  assert.ok(isBool(m.done));
  assert.ok(G.CATEGORIES.includes(m.category));
}
function checkMissions(ms) {
  assert.match(ms.date, ISO);
  assert.equal(ms.items.length, 3);
  ms.items.forEach(checkMission);
  assert.equal(new Set(ms.items.map((x) => x.planet)).size, 3, 'three different planets');
  assert.equal(new Set(ms.items.map((x) => x.id)).size, 3);
  assert.equal(ms.completedCount, ms.items.filter((x) => x.done).length);
  assert.equal(ms.allDone, ms.completedCount === 3);
  assert.ok(isInt(ms.allDoneBonusXp, 0));
  assert.ok(isBool(ms.bonusRollGranted));
}
function checkCard(c) {
  assert.ok(isStr(c.id) && /^(nak|rare):[a-z0-9_-]+$/.test(c.id), `card id ${c.id}`);
  assert.ok(['nakshatra', 'rare'].includes(c.kind));
  assert.equal(c.kind, c.id.startsWith('nak:') ? 'nakshatra' : 'rare');
  assert.ok(isStr(c.name) && isStr(c.symbol) && isStr(c.power));
  assert.ok(c.ruler === null || PLANETS.includes(c.ruler));
  assert.ok(c.deity === null || isStr(c.deity));
  assert.ok(Array.isArray(c.keywords) && c.keywords.every(isStr));
  assert.ok(['common', 'rare', 'legendary'].includes(c.rarity));
  assert.ok(isBool(c.isBirthStar) && isBool(c.collected));
  assert.ok(c.collectedOn === null || ISO.test(c.collectedOn));
  assert.equal(c.collected, c.collectedOn !== null);
}
function checkLuck(l) {
  assert.ok(isStr(l.tara) && isStr(l.line));
  assert.ok(isBool(l.favorable) && isBool(l.chandrashtama));
}
function checkState(s) {
  checkPlayer(s.player);
  checkPlanets(s.planets);
  checkMissions(s.missions);
  checkCard(s.card.today);
  assert.equal(s.card.today.kind, 'nakshatra');
  assert.ok(isBool(s.card.canCollect));
  assert.ok(isInt(s.card.collectedCount, 0, 27));
  assert.equal(s.card.total, 27);
  assert.ok(isInt(s.card.rareCount, 0));
  assert.ok(isInt(s.moksha.position, 1, 100) && isInt(s.moksha.rollsLeft, 0, 3) && isInt(s.moksha.wins, 0));
  assert.ok(isInt(s.circle.memberCount, 0));
  assert.ok(s.circle.inviteCode === null || /^[A-Z2-9]{6}$/.test(s.circle.inviteCode));
  checkLuck(s.luck);
}
function checkMissionComplete(r) {
  checkMission(r.mission);
  assert.equal(r.mission.done, true);
  assert.ok(isInt(r.xpGained, 0) && isInt(r.bonusXp, 0));
  assert.ok(isBool(r.leveledUp) && isBool(r.bonusRollGranted));
  assert.ok(r.planetLeveledUp === null || PLANETS.includes(r.planetLeveledUp));
  checkPlayer(r.player);
  checkPlanets(r.planets);
  checkMissions(r.missions);
}
function checkReward(r) {
  assert.ok(['wallet', 'xp'].includes(r.type));
  assert.ok(isInt(r.amount, 1));
  assert.ok(isStr(r.label));
}
function checkCardsPayload(p) {
  checkCard(p.today.card);
  assert.ok(isBool(p.today.canCollect));
  assert.ok(Array.isArray(p.today.extra));
  p.today.extra.forEach((c) => { checkCard(c); assert.equal(c.kind, 'rare'); });
  assert.equal(p.cards.length, 27);
  p.cards.forEach((c, i) => { checkCard(c); assert.equal(c.name, A.NAKSHATRAS[i]); });
  assert.equal(p.cards.filter((c) => c.isBirthStar).length, 1);
  assert.ok(Array.isArray(p.rare) && p.rare.length >= 6);
  p.rare.forEach(checkCard);
  assert.equal(p.collectedCount, p.cards.filter((c) => c.collected).length);
  assert.equal(p.total, 27);
  assert.ok(p.sets.length >= 4);
  for (const s of p.sets) {
    assert.ok(isStr(s.id) && isStr(s.name));
    assert.ok(s.cardIds.length > 0 && s.cardIds.every((id) => p.cards.some((c) => c.id === id)));
    assert.equal(s.collected, s.cardIds.filter((id) => p.cards.find((c) => c.id === id).collected).length);
    assert.equal(s.complete, s.collected === s.cardIds.length);
    checkReward(s.reward);
    assert.ok(isBool(s.claimed));
  }
  assert.ok(Array.isArray(p.upcoming));
  assert.ok(p.upcoming.filter((u) => u.card.kind === 'nakshatra').length <= 5);
  for (const u of p.upcoming) { checkCard(u.card); assert.match(u.date, ISO); assert.equal(u.card.collected, false); }
}
function checkCollect(r) {
  assert.ok(Array.isArray(r.collected));
  r.collected.forEach((c) => { checkCard(c); assert.equal(c.collected, true); });
  assert.ok(isInt(r.xpGained, 0));
  assert.ok(Array.isArray(r.completedSets) && r.completedSets.every(isStr));
  checkPlayer(r.player);
}
function checkClaim(r) {
  checkReward(r.reward);
  assert.ok(r.walletBalance === null || typeof r.walletBalance === 'number');
  assert.equal(r.reward.type === 'wallet', r.walletBalance !== null);
  checkPlayer(r.player);
}
function checkBoard(b) {
  assert.equal(b.size, 100);
  for (const l of b.ladders) assert.ok(isInt(l.from, 2, 99) && isInt(l.to, 2, 99) && l.to > l.from && isStr(l.name) && isStr(l.line));
  for (const s of b.snakes) assert.ok(isInt(s.from, 2, 99) && isInt(s.to, 1, 99) && s.to < s.from && isStr(s.name) && isStr(s.line));
}
function checkMokshaPlayers(players) {
  assert.ok(players.length >= 1);
  assert.equal(players[0].profileKey, 'self');
  assert.equal(players.filter((p) => p.isYou).length, 1);
  for (const p of players) {
    assert.match(p.profileKey, /^(self|fam:\d+)$/);
    assert.ok(isStr(p.name));
    assert.ok(p.relationship === null || isStr(p.relationship));
    assert.ok(isInt(p.position, 1, 100) && isInt(p.wins, 0) && isInt(p.rollsLeft, 0, 3));
    assert.equal(p.isYou, p.profileKey === 'self');
    checkLuck(p.luck);
  }
}
function checkMoksha(p) {
  checkBoard(p.board);
  checkMokshaPlayers(p.players);
  assert.ok(Array.isArray(p.lastMoves) && p.lastMoves.length <= 10);
  for (const m of p.lastMoves) {
    assert.match(m.profileKey, /^(self|fam:\d+)$/);
    assert.ok(isStr(m.name));
    assert.ok(isInt(m.dice, 1, 6) && isInt(m.from, 1, 100) && isInt(m.to, 1, 100));
    assert.ok(m.event === null || isStr(m.event));
    assert.ok(!Number.isNaN(Date.parse(m.at)));
  }
}
function checkRoll(r) {
  assert.match(r.profileKey, /^(self|fam:\d+)$/);
  assert.ok(isInt(r.dice, 1, 6) && isInt(r.from, 1, 100) && isInt(r.landed, 1, 100) && isInt(r.to, 1, 100));
  assert.ok(isBool(r.overshoot) && isBool(r.won));
  if (r.overshoot) { assert.equal(r.landed, r.from); assert.equal(r.to, r.from); } else assert.equal(r.landed, r.from + r.dice);
  if (r.event === null) assert.equal(r.to, r.landed);
  else {
    assert.ok(['ladder', 'snake'].includes(r.event.type) && isStr(r.event.name) && isStr(r.event.line));
    assert.ok(r.event.type === 'ladder' ? r.to > r.landed : r.to < r.landed);
  }
  assert.equal(r.won, r.to === 100);
  if (r.won) { assert.ok(isInt(r.reward.xp, 0)); if (r.reward.card !== null) checkCard(r.reward.card); } else assert.equal(r.reward, null);
  assert.ok(isInt(r.rollsLeft, 0, 3));
  checkMokshaPlayers(r.players);
  checkPlayer(r.player);
}
function checkMember(m) {
  assert.match(m.id, /^(fam|friend):\d+$/);
  assert.equal(m.kind, m.id.startsWith('fam:') ? 'family' : 'friend');
  assert.ok(isStr(m.name));
  assert.ok(m.relationship === null || isStr(m.relationship));
  assert.ok(isBool(m.hasChart));
  if (m.hasChart) {
    assert.ok(A.ZODIAC_SIGNS.includes(m.moonSign) && A.NAKSHATRAS.includes(m.nakshatra));
    assert.ok(typeof m.compatibility.score === 'number' && m.compatibility.score >= 0 && m.compatibility.score <= 36);
    assert.equal(Math.round(m.compatibility.score * 10) / 10, m.compatibility.score);
    assert.equal(m.compatibility.max, 36);
    assert.ok(COMPAT_LABELS.includes(m.compatibility.label));
    assert.ok(isStr(m.compatibility.strongest) && isStr(m.compatibility.weakest));
    assert.ok(isInt(m.todayScore, 0, 100) && MOODS.includes(m.mood));
  } else {
    assert.equal(m.moonSign, null); assert.equal(m.nakshatra, null); assert.equal(m.compatibility, null);
    assert.equal(m.todayScore, null); assert.equal(m.mood, null);
  }
  // privacy: never birth details
  const allowed = ['id', 'kind', 'name', 'relationship', 'hasChart', 'moonSign', 'nakshatra', 'compatibility', 'todayScore', 'mood'];
  for (const k of Object.keys(m)) assert.ok(allowed.includes(k), `member exposes unexpected field ${k}`);
}
function checkCircle(c) {
  assert.ok(c.inviteCode === null || /^[A-Z2-9]{6}$/.test(c.inviteCode));
  assert.ok(isStr(c.shareText));
  if (c.inviteCode) assert.ok(c.shareText.includes(c.inviteCode));
  assert.ok(Array.isArray(c.members) && c.members.length <= 30);
  c.members.forEach(checkMember);
  assert.ok(isStr(c.you.name) && A.ZODIAC_SIGNS.includes(c.you.moonSign) && A.NAKSHATRAS.includes(c.you.nakshatra));
  assert.ok(isInt(c.you.todayScore, 0, 100) && MOODS.includes(c.you.mood));
  assert.deepEqual(c.rankings.map((r) => r.id).sort(), RANKING_IDS.slice().sort());
  for (const r of c.rankings) {
    assert.ok(isStr(r.title) && isStr(r.emoji) && isBool(r.unlocked) && isInt(r.needMembers, 1));
    assert.equal(r.unlocked, c.members.length >= r.needMembers);
    assert.ok(Array.isArray(r.entries) && r.entries.length <= 3);
    if (!r.unlocked) assert.equal(r.entries.length, 0);
    for (const e of r.entries) {
      assert.ok(c.members.some((m) => m.id === e.memberId));
      assert.ok(isStr(e.name) && isStr(e.value) && isStr(e.note));
    }
  }
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------
test('Moksha Patam board is valid', () => {
  const b = G.BOARD;
  checkBoard(b);
  assert.ok(b.ladders.length >= 8 && b.snakes.length >= 9);
  const ends = [...b.ladders, ...b.snakes].flatMap((x) => [x.from, x.to]);
  assert.equal(new Set(ends).size, ends.length, 'no square is used by two ladders/snakes (so no chains or cycles)');
  assert.ok(!ends.includes(1) && !ends.includes(100), 'start and finish are free');
  assert.equal(new Set(b.ladders.map((l) => l.name)).size, b.ladders.length);
  assert.equal(new Set(b.snakes.map((s) => s.name)).size, b.snakes.length);
  for (const v of ['Generosity', 'Truth', 'Devotion', 'Patience', 'Service', 'Courage', 'Knowledge', 'Gratitude', 'Self-control']) {
    assert.ok(b.ladders.some((l) => l.name === v), v);
  }
  for (const v of ['Anger', 'Greed', 'Ego', 'Envy', 'Laziness', 'Lust for power', 'Lies', 'Attachment', 'Pride', 'Gossip']) {
    assert.ok(b.snakes.some((s) => s.name === v), v);
  }
  // a long snake near the top, like the traditional board
  assert.ok(b.snakes.some((s) => s.from >= 95 && s.from - s.to >= 50));
  // no run of six snake heads (which would make a wall)
  const heads = new Set(b.snakes.map((s) => s.from));
  for (let sq = 1; sq <= 94; sq++) assert.ok([1, 2, 3, 4, 5, 6].some((d) => !heads.has(sq + d)));

  // every square 1..100 resolves to a legal square, and 100 is reachable from 1 and from everywhere reachable
  const next = (sq) => [1, 2, 3, 4, 5, 6].map((d) => S.applyRoll(sq, d).to);
  const seen = new Set([1]);
  const queue = [1];
  while (queue.length) for (const t of next(queue.shift())) if (!seen.has(t)) { seen.add(t); queue.push(t); }
  assert.ok(seen.has(100), 'square 100 is reachable');
  for (const sq of seen) {
    if (sq === 100) continue;
    const reach = new Set([sq]);
    const q = [sq];
    while (q.length) for (const t of next(q.shift())) if (!reach.has(t)) { reach.add(t); q.push(t); }
    assert.ok(reach.has(100), `100 reachable from ${sq}`);
  }
  for (let sq = 1; sq <= 100; sq++) for (const t of sq === 100 ? [] : next(sq)) assert.ok(isInt(t, 1, 100));
});

test('Moksha Patam roll rules', () => {
  assert.deepEqual(S.applyRoll(1, 2), { from: 1, landed: 3, to: 21, event: { type: 'ladder', name: 'Generosity', line: G.BOARD.ladders[0].line }, overshoot: false, won: false });
  const snake = S.applyRoll(97, 1);
  assert.equal(snake.to, 12);
  assert.equal(snake.event.type, 'snake');
  assert.deepEqual(S.applyRoll(97, 3), { from: 97, landed: 100, to: 100, event: null, overshoot: false, won: true });
  assert.deepEqual(S.applyRoll(97, 4), { from: 97, landed: 97, to: 97, event: null, overshoot: true, won: false });
  assert.equal(S.applyRoll(10, 1).event, null);
  assert.throws(() => S.applyRoll(5, 7));

  const good = { tara: { favorable: true }, chandrashtama: false };
  const bad = { tara: { favorable: false }, chandrashtama: false };
  const ch = { tara: { favorable: true }, chandrashtama: true };
  assert.equal(S.rollsAllowed(bad), 1);
  assert.equal(S.rollsAllowed(good), 2);
  assert.equal(S.rollsAllowed(ch), 1, 'no Tara bonus on Chandrashtama');
  assert.equal(S.rollsAllowed(good, { isSelf: true, bonusRoll: true }), 3);
  assert.equal(S.rollsAllowed(good, { isSelf: false, bonusRoll: true }), 2, 'mission bonus is for self only');
  assert.equal(S.rollsAllowed(null), 1);
  assert.equal(S.rollsLeft({ rolls_date: '2026-10-07', rolls_used: 1 }, '2026-10-07', good), 1);
  assert.equal(S.rollsLeft({ rolls_date: '2026-10-06', rolls_used: 2 }, '2026-10-07', good), 2, 'rolls reset on a new local day');
  assert.equal(S.rollsLeft({ rolls_date: '2026-10-07', rolls_used: 5 }, '2026-10-07', bad), 0);
  assert.equal(S.rollsLeft(null, '2026-10-07', bad), 1);
});

// Whole-word checks: nothing medical, financial, costly or risky in the mission library
const UNSAFE = /\b(medicine|medicines|medication|pill|pills|cure|cures|heal|diagnos\w*|doctor|treatment|therapy|fast|fasting|diet|detox|weight|invest\w*|loan|lend|borrow|bet|gambl\w*|lottery|stock|stocks|crypto|buy|purchase|spend|pay|donate|money|rupees|gold|gemstone|alcohol|drink alcohol|smok\w*|drive|swim|climb|fire|knife|fight|run a|marathon|quit your|resign|confront|stranger's|alone at night)\b/i;

test('mission library: size, wording and safety', () => {
  const keys = new Set();
  const cats = new Set();
  for (const p of PLANETS) {
    const list = G.MISSIONS[p];
    assert.ok(list.length >= 10, `${p} has ${list.length} missions`);
    assert.ok(new Set(list.map((x) => x.c)).size >= 4, `${p} covers at least 4 categories`);
    for (const x of list) {
      assert.ok(!keys.has(x.key), `duplicate key ${x.key}`);
      keys.add(x.key);
      cats.add(x.c);
      assert.ok(/^[a-z]+\d\d$/.test(x.key));
      assert.ok(G.CATEGORIES.includes(x.c), x.key);
      assert.ok([20, 30, 40].includes(x.xp), x.key);
      assert.ok(x.title.length >= 12 && x.title.length <= 70, `${x.key} title length ${x.title.length}`);
      assert.ok(!UNSAFE.test(x.title), `${x.key} uses an unsafe word: ${x.title}`);
      assert.ok(!/[—–]/.test(x.title));
      assert.equal(G.MISSION_BY_KEY[x.key].planet, p);
    }
  }
  assert.deepEqual([...cats].sort(), G.CATEGORIES.slice().sort());
  for (const p of PLANETS) {
    const ch = G.PLANET_CHARACTERS[p];
    assert.ok(isStr(ch.role) && isStr(ch.personality) && isStr(ch.emoji));
    assert.equal(ch.titles.length, 5);
    assert.equal(G.planetTitle(p, 1), ch.titles[0]);
    assert.equal(G.planetTitle(p, 10), ch.titles[4]);
  }
});

test('27 nakshatra cards match the tradition tables', () => {
  assert.equal(G.NAKSHATRA_CARDS.length, 27);
  const ids = new Set();
  G.NAKSHATRA_CARDS.forEach((c, i) => {
    assert.equal(c.name, A.NAKSHATRAS[i]);
    assert.equal(c.ruler, A.NAKSHATRA_LORDS[i % 9], `${c.name} ruler`);
    assert.ok(isStr(c.symbol) && isStr(c.deity) && isStr(c.power));
    assert.ok(c.power.length <= 70, c.power);
    assert.equal(c.keywords.length, 3);
    ids.add(G.nakCardId(i));
    checkCard(S.buildCard(G.nakCardId(i), { birthNak: 3 }));
  });
  assert.equal(ids.size, 27);
  assert.equal(G.nakCardId(9), 'nak:magha');
  assert.equal(G.nakCardId(10), 'nak:purva_phalguni');
  for (const id of [...Object.keys(G.RARE_STATIC), ...Object.values(G.FESTIVAL_CARDS).map((f) => f.id), 'rare:lunar_eclipse_2026-03-03', 'rare:solar_eclipse_2027-08-02']) {
    const c = S.buildCard(id, {});
    checkCard(c);
    assert.equal(c.kind, 'rare');
    assert.notEqual(c.rarity, 'common');
  }
  assert.equal(S.buildCard('rare:lunar_eclipse_2026-03-03', {}).rarity, 'legendary');
  assert.ok(S.cardXp('rare:moksha') > S.cardXp('rare:purnima') && S.cardXp('rare:purnima') > S.cardXp('nak:magha'));
});

// ---------------------------------------------------------------------------
// Player level, streak, planets
// ---------------------------------------------------------------------------
test('level math: level n needs 100*n XP to reach n+1', () => {
  assert.deepEqual(S.levelInfo(0), { level: 1, xpIntoLevel: 0, xpForNext: 100 });
  assert.deepEqual(S.levelInfo(99), { level: 1, xpIntoLevel: 99, xpForNext: 100 });
  assert.deepEqual(S.levelInfo(100), { level: 2, xpIntoLevel: 0, xpForNext: 200 });
  assert.deepEqual(S.levelInfo(299), { level: 2, xpIntoLevel: 199, xpForNext: 200 });
  assert.deepEqual(S.levelInfo(300), { level: 3, xpIntoLevel: 0, xpForNext: 300 });
  assert.deepEqual(S.levelInfo(-5), { level: 1, xpIntoLevel: 0, xpForNext: 100 });
  let prev = 1;
  for (let xp = 0; xp <= 60000; xp += 7) {
    const l = S.levelInfo(xp);
    assert.ok(l.level >= prev && l.xpIntoLevel >= 0 && l.xpIntoLevel < l.xpForNext);
    assert.equal(50 * l.level * (l.level - 1) + l.xpIntoLevel, xp);
    prev = l.level;
  }
  assert.equal(G.playerTitle(1), 'Star Seeker');
  assert.equal(G.playerTitle(3), 'Sky Walker');
  assert.equal(G.playerTitle(99), 'Moksha Master');
  checkPlayer(S.playerView(null, '2026-10-07'));
  checkPlayer(S.playerView({ xp: 1234, streak: 4, best_streak: 9, last_mission_date: '2026-10-07' }, '2026-10-07'));
});

test('streak logic across local dates', () => {
  let p = S.normProfile(null);
  const play = (date) => { p = { ...p, ...S.streakAfterMission(p, date) }; return p; };
  assert.equal(S.playerView(p, '2026-10-01').streak, 0);
  play('2026-10-01');
  assert.deepEqual([p.streak, p.bestStreak], [1, 1]);
  play('2026-10-01'); // second mission, same day
  assert.equal(p.streak, 1);
  play('2026-10-02');
  play('2026-10-03');
  assert.deepEqual([p.streak, p.bestStreak], [3, 3]);
  // next morning, nothing done yet: streak still shown, not yet alive today
  let v = S.playerView(p, '2026-10-04');
  assert.deepEqual([v.streak, v.streakAliveToday, v.bestStreak], [3, false, 3]);
  v = S.playerView(p, '2026-10-03');
  assert.deepEqual([v.streak, v.streakAliveToday], [3, true]);
  // a missed day breaks it
  v = S.playerView(p, '2026-10-05');
  assert.deepEqual([v.streak, v.streakAliveToday, v.bestStreak], [0, false, 3]);
  play('2026-10-05');
  assert.deepEqual([p.streak, p.bestStreak], [1, 3]);
  // month / year boundaries
  p = { ...p, streak: 5, bestStreak: 5, lastMissionDate: '2026-12-31' };
  play('2027-01-01');
  assert.deepEqual([p.streak, p.bestStreak], [6, 6]);
  p = { ...p, lastMissionDate: '2028-02-28' };
  play('2028-02-29');
  assert.equal(p.streak, 7);
});

test('planet strength comes from the birth chart and grows with XP', () => {
  for (const k of CHARTS) {
    const ctx = ctxFor(k);
    const st = S.natalStrength(k, ctx.natal);
    const views = S.planetViews(st, {});
    checkPlanets(views);
    for (const v of views) {
      assert.equal(v.power, st[v.planet].base);
      assert.equal(v.level, Math.max(1, Math.ceil(v.power / 10)));
      assert.ok(!/debilitat|enemy|malefic|bad|weak|afflict/i.test(v.natal), `natal line should be gentle: ${v.natal}`);
    }
    // Rahu / Ketu are shadow planets: kept near the middle
    assert.ok(st.Rahu.base >= 35 && st.Rahu.base <= 70 && /Shadow planet/.test(st.Rahu.line));
    const boosted = S.planetViews(st, { Saturn: 400 }).find((p) => p.planet === 'Saturn');
    assert.equal(boosted.power, Math.min(100, st.Saturn.base + 20));
    assert.equal(S.planetViews(st, { Saturn: 1e6 }).find((p) => p.planet === 'Saturn').power, 100);
  }
  // Known dignities for 1990-05-15 06:30 Delhi: Venus exalted in Pisces, Saturn in own sign Capricorn (retrograde)
  const st = S.natalStrength(CHARTS[0], ctxFor(CHARTS[0]).natal);
  assert.equal(st.Venus.dignity, 'exalted');
  assert.match(st.Venus.line, /^Exalted in Pisces/);
  assert.equal(st.Saturn.dignity, 'own');
  assert.ok(st.Saturn.retrograde && /retrograde/.test(st.Saturn.line));
  assert.equal(S.planetStatus(85), 'strong');
  assert.equal(S.planetStatus(50), 'steady');
  assert.equal(S.planetStatus(30), 'needs_care');
  // Moolatrikona: Sun at 10 deg Leo
  const k = JSON.parse(JSON.stringify(CHARTS[0]));
  const natal = ctxFor(k).natal;
  natal.planets.Sun = 130;
  natal.info.Sun = { ...natal.info.Sun, sign: 'Leo', dignity: 'own sign' };
  assert.equal(S.natalStrength(k, natal).Sun.dignity, 'moolatrikona');
});

// ---------------------------------------------------------------------------
// Missions
// ---------------------------------------------------------------------------
test('daily missions: deterministic, three different planets, tied to the real sky', () => {
  const planetsSeen = new Set();
  const reasons = new Set();
  for (const [ci, k] of CHARTS.entries()) {
    const ctx = ctxFor(k);
    const strength = S.natalStrength(k, ctx.natal);
    for (let i = 0; i < 60; i++) {
      const date = F.isoAdd('2026-09-01', i);
      const day = F.dayLite(ctx, date);
      const args = { userId: 40 + ci, date, day, strength, recentKeys: new Set() };
      const a = S.pickMissions(args);
      const b = S.pickMissions({ ...args, day: F.dayLite(ctxFor(k), date) });
      assert.deepEqual(a, b, 'same user + date gives the same missions');
      const view = S.missionsView(a, new Set(), date, false);
      checkMissions(view);
      for (const x of a) {
        planetsSeen.add(x.planet);
        reasons.add(x.reason);
        assert.ok(x.id.startsWith(`${date}_`));
        assert.equal(G.MISSION_BY_KEY[x.key].planet, x.planet);
        assert.ok(!/undefined|null|NaN/.test(x.why), x.why);
        assert.ok(x.why.includes(x.planet) || x.planet === 'Moon', `why names the planet: ${x.why}`);
      }
      // slot (a) is a tough slow transit or one of the two weakest natal planets
      const weakest = PLANETS.slice().sort((p, q) => strength[p].base - strength[q].base || PLANETS.indexOf(p) - PLANETS.indexOf(q)).slice(0, 2);
      const tough = day.transits.filter((t) => t.effect === 'challenging').map((t) => t.planet);
      assert.ok(tough.includes(a[0].planet) || weakest.includes(a[0].planet), `slot a: ${a[0].planet}`);
      if (a[0].reason === 'transit_tough') assert.ok(a[0].why.startsWith(day.transits.find((t) => t.planet === a[0].planet).simple));
      // slot (b) is the Moon, the weekday lord or today's star lord
      assert.ok(['Moon', day.dayLord, A.NAKSHATRA_LORDS[day.moonNakIndex % 9]].includes(a[1].planet) || a[1].reason === 'fallback');
      if (a[1].reason === 'tara') assert.ok(a[1].why.includes(`${day.tara.name} Tara`));
      // a different user gets their own picks on at least some days (checked below)
    }
  }
  assert.equal(planetsSeen.size, 9, 'every planet shows up over time');
  for (const r of ['transit_tough', 'tara', 'day_lord']) assert.ok(reasons.has(r), `reason ${r} occurs`);
  assert.ok(reasons.has('dasha') || reasons.has('antardasha'));

  // different users with the same chart do not all get identical missions every day
  const k = CHARTS[0];
  const ctx = ctxFor(k);
  const strength = S.natalStrength(k, ctx.natal);
  let differ = 0;
  for (let i = 0; i < 30; i++) {
    const date = F.isoAdd('2026-09-01', i);
    const day = F.dayLite(ctx, date);
    const x = S.pickMissions({ userId: 1, date, day, strength }).map((q) => q.key).join();
    const y = S.pickMissions({ userId: 2, date, day, strength }).map((q) => q.key).join();
    if (x !== y) differ++;
  }
  assert.ok(differ > 10);
});

test('daily missions avoid what the player did in the last 7 days', () => {
  const k = CHARTS[0];
  const ctx = ctxFor(k);
  const strength = S.natalStrength(k, ctx.natal);
  const date = '2026-10-07';
  const day = F.dayLite(ctx, date);
  const first = S.pickMissions({ userId: 7, date, day, strength, recentKeys: new Set() });
  const again = S.pickMissions({ userId: 7, date, day, strength, recentKeys: new Set(first.map((x) => x.key)) });
  assert.deepEqual(again.map((x) => x.planet), first.map((x) => x.planet), 'planets come from the sky, not from history');
  for (const x of again) assert.ok(!first.some((f) => f.key === x.key), `${x.key} was repeated`);
  // if everything was done recently we still return three missions
  const all = new Set(Object.keys(G.MISSION_BY_KEY));
  assert.equal(S.pickMissions({ userId: 7, date, day, strength, recentKeys: all }).length, 3);
  // completion view
  const v = S.missionsView(first, new Set(first.map((x) => x.id)), date, true);
  assert.deepEqual([v.completedCount, v.allDone, v.bonusRollGranted, v.allDoneBonusXp], [3, true, true, 50]);
});

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------
test("card of the day is the forecast's Moon nakshatra; rare cards follow the real sky", () => {
  const k = CHARTS[0];
  const ctx = ctxFor(k);
  let birthReturns = 0;
  for (let i = 0; i < 40; i++) {
    const date = F.isoAdd('2026-10-01', i);
    const av = S.cardsAvailable(ctx, date, { bestStreak: 0 });
    const card = S.buildCard(av.cardId, { birthNak: ctx.natal.moonNak });
    if (i % 4 === 0) assert.equal(card.name, F.buildDay(ctx, date).moon.nakshatra, date);
    assert.equal(card.name, F.dayLite(ctx, date).moonNakshatra, date);
    const isReturn = card.name === k.nakshatra;
    assert.equal(av.extraIds.includes('rare:birth_star'), isReturn);
    assert.equal(card.isBirthStar, isReturn);
    if (isReturn) birthReturns++;
  }
  assert.ok(birthReturns >= 1 && birthReturns <= 3);

  // Full moon, festival and eclipse days from the forecast events become rare cards on exactly those dates
  const events = F.eventsBetween(ctx, '2026-01-01', '2026-12-31', { chandrashtama: false });
  const fm = events.find((e) => e.type === 'full_moon');
  assert.ok(S.cardsAvailable(ctx, fm.date).extraIds.includes('rare:purnima'));
  assert.ok(!S.cardsAvailable(ctx, F.isoAdd(fm.date, 5)).extraIds.includes('rare:purnima'));
  const diwali = events.find((e) => e.title === 'Diwali (Lakshmi Puja)');
  assert.ok(S.cardsAvailable(ctx, diwali.date).extraIds.includes('rare:festival_diwali'));
  const ecl = events.find((e) => e.type === 'lunar_eclipse' || e.type === 'solar_eclipse');
  assert.ok(ecl, 'there is an eclipse in 2026');
  const eclId = `rare:${ecl.type}_${ecl.date}`;
  assert.ok(S.cardsAvailable(ctx, ecl.date).extraIds.includes(eclId), eclId);
  assert.equal(S.cardRarity(eclId), 'legendary');
  // every major festival title the forecast can emit has a card
  for (const e of events.filter((x) => x.type === 'festival' && x.importance >= 2)) assert.ok(G.FESTIVAL_CARDS[e.title], e.title);

  // streak milestones
  assert.deepEqual(S.cardsAvailable(ctx, '2026-10-08', { bestStreak: 6 }).extraIds.filter((x) => x.startsWith('rare:streak')), []);
  assert.deepEqual(S.cardsAvailable(ctx, '2026-10-08', { bestStreak: 31 }).extraIds.filter((x) => x.startsWith('rare:streak')), ['rare:streak_7', 'rare:streak_30']);

  // upcoming: next uncollected cards with the date the Moon reaches them
  const collected = new Map([[S.cardsAvailable(ctx, '2026-10-08').cardId, '2026-10-07']]);
  const up = S.upcomingCards(ctx, '2026-10-07', { birthNak: ctx.natal.moonNak, collected });
  const naks = up.filter((u) => u.card.kind === 'nakshatra');
  assert.equal(naks.length, 5);
  for (const u of up) {
    assert.ok(u.date > '2026-10-07' && !collected.has(u.card.id));
    if (u.card.kind === 'nakshatra') assert.equal(S.cardsAvailable(ctx, u.date).cardId, u.card.id);
    else assert.ok(S.cardsAvailable(ctx, u.date).extraIds.includes(u.card.id), `${u.card.id} on ${u.date}`);
  }
  assert.deepEqual(up.map((u) => u.date), up.map((u) => u.date).slice().sort());
  const rare = S.rareCatalogue(ctx, '2026-10-07', { collected: new Map([['rare:moksha', '2026-10-01']]) });
  assert.ok(rare.find((c) => c.id === 'rare:moksha').collected);
  assert.ok(rare.some((c) => /eclipse/.test(c.id)), 'next eclipse is listed');
});

test('card sets: completion, rewards and config', () => {
  const birthNak = 20; // Uttara Ashadha
  const on = { walletRewards: true, setReward: 11, fullSetReward: 51 };
  const none = S.setsView({ birthNak, collected: new Map(), claimed: new Set(), registered: true, config: on });
  assert.deepEqual(none.map((s) => s.id), ['row1', 'row2', 'row3', 'janma_trio', 'navatara', 'full_sky']);
  assert.ok(none.every((s) => !s.complete && s.collected === 0 && !s.claimed));
  assert.deepEqual(none.map((s) => s.cardIds.length), [9, 9, 9, 3, 9, 27]);
  assert.equal(none[0].cardIds[0], 'nak:ashwini');
  assert.equal(none[1].cardIds[0], 'nak:magha');
  assert.equal(none[2].cardIds[0], 'nak:moola');
  // Janma / Anujanma / Trijanma share the birth star's ruler
  const trio = none[3].cardIds.map((id) => S.buildCard(id, {}).ruler);
  assert.equal(new Set(trio).size, 1);
  assert.equal(none[4].cardIds[0], G.nakCardId(birthNak));
  assert.equal(none[4].cardIds[8], G.nakCardId((birthNak + 8) % 27), 'wraps around the zodiac');

  const collected = new Map(none[0].cardIds.map((id) => [id, '2026-10-01']));
  const one = S.setsView({ birthNak, collected, claimed: new Set(['row1']), registered: true, config: on });
  assert.deepEqual([one[0].complete, one[0].collected, one[0].claimed], [true, 9, true]);
  assert.ok(!one[1].complete && !one[5].complete && one[5].collected === 9);
  const all = new Map(none[5].cardIds.map((id) => [id, '2026-10-01']));
  assert.ok(S.setsView({ birthNak, collected: all, claimed: new Set(), registered: true, config: on }).every((s) => s.complete));

  // rewards: wallet for registered users only, small, switchable
  assert.deepEqual(one[0].reward, { type: 'wallet', amount: 11, label: '₹11 wallet credit' });
  assert.equal(one[5].reward.type, 'wallet');
  assert.equal(one[3].reward.type, 'xp');
  assert.equal(one[4].reward.type, 'xp');
  const guest = S.setsView({ birthNak, collected, claimed: new Set(), registered: false, config: on });
  assert.ok(guest.every((s) => s.reward.type === 'xp' && s.reward.amount > 0));
  const off = S.setsView({ birthNak, collected, claimed: new Set(), registered: true, config: { ...on, walletRewards: false } });
  assert.ok(off.every((s) => s.reward.type === 'xp'));
  const zero = S.setsView({ birthNak, collected, claimed: new Set(), registered: true, config: { ...on, setReward: 0 } });
  assert.equal(zero[0].reward.type, 'xp');

  // env parsing: safe defaults and caps
  assert.deepEqual(S.config({}), { walletRewards: true, setReward: 11, fullSetReward: 51, mokshaWinXp: 200, mokshaWinWallet: 0 });
  assert.equal(S.config({ GAME_WALLET_REWARDS: 'false' }).walletRewards, false);
  assert.equal(S.config({ GAME_SET_REWARD_AMOUNT: '999999' }).setReward, 500);
  assert.equal(S.config({ GAME_SET_REWARD_AMOUNT: '-5' }).setReward, 0);
  assert.equal(S.config({ GAME_SET_REWARD_AMOUNT: 'abc' }).setReward, 11);
});

// ---------------------------------------------------------------------------
// Cosmic Match
// ---------------------------------------------------------------------------
test('circle compatibility is symmetric, bounded and uses Ashtakoot', () => {
  const moons = [];
  for (let l = 3; l < 360; l += 7.3) {
    moons.push({ moonLongitude: l, moonSign: A.ZODIAC_SIGNS[Math.floor(l / 30)], nakshatra: A.NAKSHATRAS[Math.floor(l / (360 / 27))] });
  }
  const labels = new Set();
  let asymmetricRaw = 0;
  for (const a of moons) {
    for (const b of moons) {
      const ab = S.compatibility(a, b);
      const ba = S.compatibility(b, a);
      assert.deepEqual(S.publicCompat(ab), S.publicCompat(ba), 'A-B equals B-A');
      assert.ok(ab.score >= 0 && ab.score <= 36);
      const r1 = A.calculateAshtakoot(a, b).total;
      const r2 = A.calculateAshtakoot(b, a).total;
      if (r1 !== r2) asymmetricRaw++;
      assert.equal(ab.score, Math.round(((r1 + r2) / 2) * 10) / 10);
      assert.equal(Object.keys(ab.kootas).length, 8);
      assert.ok(isStr(ab.strongest) && isStr(ab.weakest) && ab.strongest !== ab.weakest);
      labels.add(ab.label);
    }
  }
  assert.ok(asymmetricRaw > 0, 'the raw table is direction-dependent, which is why we average');
  assert.equal(labels.size, 5, 'all five labels occur');
  assert.equal(G.compatLabel(36), 'Soul-level');
  assert.equal(G.compatLabel(0), 'Opposites');
  assert.equal(S.compatibility({ moonSign: 'Nope', nakshatra: 'Nope' }, moons[0]), null);
  const total = Object.values(S.KOOTA_MAX).reduce((s, x) => s + x, 0);
  assert.equal(total, 36);
  for (const r of G.RANKINGS) for (const k of r.kootas || []) assert.ok(S.KOOTA_MAX[k], k);
});

test('circle rankings unlock by circle size and rank by the right kootas', () => {
  const me = S.moonProfile(CHARTS[0]);
  const mk = (i, k) => {
    const c = S.compatibility(me, S.moonProfile(k));
    const sc = S.dayScore(k, '2026-10-07');
    return { id: `fam:${i}`, name: `P${i}`, todayScore: sc.todayScore, mood: sc.mood, _compat: c };
  };
  const pool = [chart('1988-11-02', '22:30'), chart('1992-03-11', '09:10'), chart('1979-07-23', '18:45'), chart('2003-12-01', '05:55'), chart('1995-06-17', '12:00')];
  const need = { cosmicTwin: 1, luckiestToday: 1, funPartner: 2, travelBuddy: 3, businessPartner: 4, calmingPresence: 5 };
  for (let n = 0; n <= 5; n++) {
    const members = pool.slice(0, n).map((k, i) => mk(i + 1, k));
    const rk = S.buildRankings(members);
    assert.equal(rk.length, 6);
    for (const r of rk) {
      assert.equal(r.needMembers, need[r.id]);
      assert.equal(r.unlocked, n >= need[r.id], `${r.id} with ${n}`);
      assert.equal(r.entries.length, r.unlocked ? Math.min(3, n) : 0);
    }
    if (n === 5) {
      const twin = rk.find((r) => r.id === 'cosmicTwin').entries;
      const best = members.slice().sort((a, b) => b._compat.score - a._compat.score)[0];
      assert.equal(twin[0].memberId, best.id);
      assert.match(twin[0].value, /^\d+(\.\d)?\/36$/);
      const lucky = rk.find((r) => r.id === 'luckiestToday').entries;
      assert.equal(Number(lucky[0].value), Math.max(...members.map((m) => m.todayScore)));
      const fun = rk.find((r) => r.id === 'funPartner').entries;
      assert.match(fun[0].value, /^\d+(\.\d)?\/12$/);
      const funScore = (m) => m._compat.kootas.Yoni.score + m._compat.kootas.Gana.score + m._compat.kootas.Vashya.score;
      assert.equal(funScore(members.find((m) => m.id === fun[0].memberId)), Math.max(...members.map(funScore)));
      assert.match(rk.find((r) => r.id === 'travelBuddy').entries[0].value, /\/10$/);
      assert.match(rk.find((r) => r.id === 'businessPartner').entries[0].value, /\/16$/);
      assert.match(rk.find((r) => r.id === 'calmingPresence').entries[0].value, /\/19$/);
    }
  }
  // a member without a chart still counts towards the circle size but never appears in entries
  const rk = S.buildRankings([{ id: 'friend:9', name: 'No Chart', todayScore: null, mood: null, _compat: null }]);
  assert.ok(rk.find((r) => r.id === 'cosmicTwin').unlocked);
  assert.equal(rk.find((r) => r.id === 'cosmicTwin').entries.length, 0);
});

test('today score for circle members equals the forecast day score (rules only)', () => {
  for (const k of CHARTS) {
    const ctx = F.createContext(k);
    const day = F.buildDay(ctx, '2026-10-07');
    const s = S.dayScore(k, '2026-10-07');
    assert.equal(s.todayScore, day.summary.overallScore);
    assert.equal(s.mood, day.summary.mood);
    assert.equal(day.generatedBy, 'rules');
  }
  assert.deepEqual(S.dayScore({}, '2026-10-07'), { todayScore: null, mood: null });
});

test('invite codes are short, uppercase and unambiguous', () => {
  const crypto = require('crypto');
  const seen = new Set();
  for (let i = 0; i < 500; i++) {
    const c = S.newInviteCode(crypto.randomInt);
    assert.match(c, /^[A-HJKMNP-Z2-9]{6}$/);
    assert.ok(!/[ILO01]/.test(c));
    seen.add(c);
  }
  assert.ok(seen.size > 490);
  assert.equal(S.normalizeInviteCode(' ab-c2 3d '), 'ABC23D');
  assert.equal(S.normalizeInviteCode(''), null);
  assert.equal(S.normalizeInviteCode(12345), null);
  assert.ok(S.shareText('ABC23D').includes('ABC23D'));
});

test('luck lines are friendly and cover every Tara', () => {
  const ctx = ctxFor(CHARTS[0]);
  const names = new Set();
  for (let i = 0; i < 30; i++) {
    const day = F.dayLite(ctx, F.isoAdd('2026-10-01', i));
    const l = S.luckView(day);
    checkLuck(l);
    names.add(l.tara);
    assert.equal(l.favorable, day.tara.favorable);
    assert.ok(!/danger|death|bad luck|inauspicious|obstacle/i.test(l.line), l.line);
    if (!l.chandrashtama) assert.ok(l.line.startsWith(`${l.tara} Tara`));
  }
  assert.equal(names.size, 9);
  for (const n of names) assert.ok(G.LUCK_LINES[n] && G.TARA_PLAIN[n], n);
  checkLuck(S.luckView(null));
});

module.exports = {
  checkPlayer, checkPlanets, checkMissions, checkCard, checkLuck, checkState, checkMissionComplete,
  checkCardsPayload, checkCollect, checkClaim, checkMoksha, checkRoll, checkCircle, checkMember
};
