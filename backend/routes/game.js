// Games API (/api/game): Graha Quest, Nakshatra Cards, Moksha Patam, Cosmic Match.
// Server-authoritative. Rules live in services/game_service.js; this file owns auth, persistence
// and transactions. Every mutation locks the caller's game_profiles row first, so double taps
// are serialised per account.
const express = require('express');
const crypto = require('crypto');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken, kundliFromRow } = require('./auth');
const F = require('../services/forecast_service');
const { AstrologyInputError } = require('../services/astrology_service');
const S = require('../services/game_service');
const G = require('../services/game_content');

const { GameError } = S;
const NO_KUNDLI_MSG = 'No Kundli found for this profile. Generate a Kundli first.';
const LOGIN_MSG = 'Please log in or create an account to add friends to your Cosmic Circle.';

// ---------------------------------------------------------------------------
// Request context
// ---------------------------------------------------------------------------
const KUNDLI_COLS = `bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude, bd.timezone,
       k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada, k.planetary_positions, k.houses,
       k.dasha_info, k.ai_report, k.kundli_data`;

// Loads the caller, their Kundli and today's sky facts. Throws NO_KUNDLI when there is no chart.
async function baseContext(req) {
  if (!req.user) throw new GameError(409, 'NO_KUNDLI', NO_KUNDLI_MSG);
  const r = await db.query(
    `SELECT u.id AS uid, u.role AS user_role, u.full_name AS user_name, u.invite_code, ${KUNDLI_COLS}
     FROM users u
     LEFT JOIN birth_details bd ON bd.user_id = u.id
     LEFT JOIN kundlis k ON k.user_id = u.id
     WHERE u.id = $1`,
    [req.user.userId]
  );
  const row = r.rows[0];
  if (!row) throw new GameError(401, 'LOGIN_REQUIRED', 'Your session is no longer valid. Please log in again.');
  const kundli = kundliFromRow(row);
  if (!kundli) throw new GameError(409, 'NO_KUNDLI', NO_KUNDLI_MSG);
  const name = row.full_name || row.user_name || 'You';
  const ctx = F.createContext(kundli, { profile: { name, isFamily: false, familyId: null, relationship: null } });
  const today = F.todayFor(ctx);
  const registered = row.user_role !== 'guest';
  return {
    userId: row.uid,
    registered,
    name,
    displayName: registered ? (row.user_name || name) : name,
    inviteCode: registered ? row.invite_code || null : null,
    kundli,
    ctx,
    today,
    day: F.dayLite(ctx, today),
    birthNak: ctx.natal.moonNak,
    strength: S.natalStrength(kundli, ctx.natal),
    config: S.config()
  };
}

// Invite codes are created lazily, for registered accounts only
async function ensureInviteCode(base) {
  if (!base.registered) return null;
  if (base.inviteCode) return base.inviteCode;
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = S.newInviteCode(crypto.randomInt);
    try {
      const r = await db.query('UPDATE users SET invite_code = $1 WHERE id = $2 AND invite_code IS NULL RETURNING invite_code', [code, base.userId]);
      if (r.rows[0]) {
        base.inviteCode = r.rows[0].invite_code;
        return base.inviteCode;
      }
      const cur = await db.query('SELECT invite_code FROM users WHERE id = $1', [base.userId]);
      base.inviteCode = cur.rows[0] ? cur.rows[0].invite_code : null;
      if (base.inviteCode) return base.inviteCode;
    } catch (err) {
      if (!err || err.code !== '23505') throw err; // code collision: try another
    }
  }
  throw new Error('Could not allocate an invite code');
}

// Everything the games need about one account, in a single round trip
async function loadBundle(q, base) {
  const r = await q.query(
    `SELECT
       (SELECT row_to_json(g) FROM game_profiles g WHERE g.user_id = $1) AS gp,
       (SELECT COALESCE(json_agg(json_build_object('date', l.local_date, 'id', l.mission_id, 'key', l.mission_key)), '[]'::json)
          FROM game_mission_log l WHERE l.user_id = $1 AND l.local_date >= $2::date) AS logs,
       (SELECT COALESCE(json_agg(json_build_object('id', c.card_id, 'on', c.collected_on)), '[]'::json)
          FROM game_cards c WHERE c.user_id = $1) AS cards,
       (SELECT COALESCE(json_agg(s.set_id), '[]'::json) FROM game_set_claims s WHERE s.user_id = $1) AS claims,
       (SELECT row_to_json(m) FROM moksha_players m WHERE m.user_id = $1 AND m.profile_key = 'self') AS moksha_self,
       (SELECT COUNT(*) FROM friend_links f WHERE f.user_id = $1) AS friends,
       (SELECT COUNT(*) FROM family_kundlis fk WHERE fk.user_id = $1) AS family`,
    [base.userId, F.isoAdd(base.today, -7)]
  );
  const row = r.rows[0] || {};
  const logs = Array.isArray(row.logs) ? row.logs : [];
  const collected = new Map();
  for (const c of Array.isArray(row.cards) ? row.cards : []) collected.set(c.id, String(c.on).slice(0, 10));
  const profile = S.normProfile(row.gp);
  return {
    profile,
    collected,
    claimed: new Set(Array.isArray(row.claims) ? row.claims : []),
    doneToday: new Set(logs.filter((l) => String(l.date).slice(0, 10) === base.today).map((l) => l.id)),
    recentKeys: new Set(logs.filter((l) => String(l.date).slice(0, 10) < base.today).map((l) => l.key)),
    mokshaSelf: row.moksha_self || null,
    friendCount: Number(row.friends) || 0,
    familyCount: Number(row.family) || 0
  };
}

const bonusToday = (base, b) => b.profile.bonusRollDate === base.today;
const cardOpts = (base, b) => ({ birthNak: base.birthNak, collected: b.collected, claimed: b.claimed, registered: base.registered, config: base.config });

function missionsFor(base, b) {
  return S.pickMissions({ userId: base.userId, date: base.today, day: base.day, strength: base.strength, recentKeys: b.recentKeys });
}
function missionsPayload(base, b) {
  return S.missionsView(missionsFor(base, b), b.doneToday, base.today, bonusToday(base, b));
}
function availableCards(base, b) {
  const av = S.cardsAvailable(base.ctx, base.today, { bestStreak: b.profile.bestStreak });
  const ids = [av.cardId, ...av.extraIds];
  return { ...av, ids, canCollect: ids.some((id) => !b.collected.has(id)) };
}
const playerOf = (base, b) => S.playerView(b.profile, base.today);
const planetsOf = (base, b) => S.planetViews(base.strength, b.profile.planetXp);

// Per-account mutex + fresh snapshot inside a transaction
async function lockProfile(client, base) {
  await client.query('INSERT INTO game_profiles (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING', [base.userId]);
  await client.query('SELECT user_id FROM game_profiles WHERE user_id = $1 FOR UPDATE', [base.userId]);
  return loadBundle(client, base);
}

function handle(fn) {
  return async (req, res) => {
    try {
      res.json(await fn(req));
    } catch (err) {
      if (err instanceof GameError) {
        return res.status(err.statusCode).json({ error: err.message, code: err.code, ...(err.extra || {}) });
      }
      if (err instanceof F.ForecastError) {
        const body = { error: err.message };
        if (err.code) body.code = err.code;
        return res.status(err.statusCode || 400).json(body);
      }
      if (err instanceof AstrologyInputError) return res.status(400).json({ error: err.message });
      console.error('Game error:', err);
      res.status(500).json({ error: 'Something went wrong in the game. Please try again.' });
    }
  };
}

// ---------------------------------------------------------------------------
// GET /api/game/state : hub overview
// ---------------------------------------------------------------------------
router.get('/state', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  const [b, inviteCode] = [await loadBundle(db, base), await ensureInviteCode(base)];
  const av = availableCards(base, b);
  let nakCount = 0;
  let rareCount = 0;
  for (const id of b.collected.keys()) {
    if (S.cardKind(id) === 'nakshatra') nakCount++;
    else rareCount++;
  }
  return {
    player: playerOf(base, b),
    planets: planetsOf(base, b),
    missions: missionsPayload(base, b),
    card: {
      today: S.buildCard(av.cardId, cardOpts(base, b)),
      canCollect: av.canCollect,
      collectedCount: nakCount,
      total: 27,
      rareCount
    },
    moksha: {
      position: b.mokshaSelf ? Number(b.mokshaSelf.position) || 1 : 1,
      rollsLeft: S.rollsLeft(b.mokshaSelf, base.today, base.day, { isSelf: true, bonusRoll: bonusToday(base, b) }),
      wins: b.mokshaSelf ? Number(b.mokshaSelf.wins) || 0 : 0
    },
    circle: { memberCount: b.friendCount + b.familyCount, inviteCode },
    luck: S.luckView(base.day)
  };
}));

// ---------------------------------------------------------------------------
// Graha Quest
// ---------------------------------------------------------------------------
router.post('/missions/:id/complete', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  const missionId = String(req.params.id || '');
  return db.withTransaction(async (client) => {
    const b = await lockProfile(client, base);
    const mission = missionsFor(base, b).find((x) => x.id === missionId);
    if (!mission) throw new GameError(404, 'MISSION_NOT_FOUND', "That mission isn't on today's list. Pull to refresh for today's missions.");

    const before = playerOf(base, b);
    const planetBefore = planetsOf(base, b).find((p) => p.planet === mission.planet);
    let xpGained = 0;
    let bonusXp = 0;
    let bonusRollGranted = false;

    const ins = await client.query(
      `INSERT INTO game_mission_log (user_id, local_date, mission_id, mission_key, planet, xp)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (user_id, local_date, mission_id) DO NOTHING RETURNING id`,
      [base.userId, base.today, mission.id, mission.key, mission.planet, mission.xp]
    );
    if (ins.rows.length > 0) {
      xpGained = mission.xp;
      const p = b.profile;
      const st = S.streakAfterMission(p, base.today);
      const planetXp = { ...p.planetXp, [mission.planet]: (Number(p.planetXp[mission.planet]) || 0) + mission.xp };
      let bonusDate = p.bonusRollDate;
      if (b.doneToday.size + 1 >= 3 && bonusDate !== base.today) {
        bonusXp = S.ALL_DONE_BONUS_XP;
        bonusRollGranted = true;
        bonusDate = base.today;
      }
      await client.query(
        `UPDATE game_profiles
         SET xp = xp + $2, streak = $3, best_streak = $4, last_mission_date = $5, planet_xp = $6::jsonb,
             bonus_roll_date = $7, updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $1`,
        [base.userId, xpGained + bonusXp, st.streak, st.bestStreak, st.lastMissionDate, JSON.stringify(planetXp), bonusDate]
      );
    }

    const after = await loadBundle(client, base);
    const player = playerOf(base, after);
    const planets = planetsOf(base, after);
    const planetAfter = planets.find((p) => p.planet === mission.planet);
    const missions = missionsPayload(base, after);
    return {
      mission: missions.items.find((x) => x.id === mission.id),
      xpGained,
      bonusXp,
      leveledUp: player.level > before.level,
      planetLeveledUp: planetAfter.level > planetBefore.level ? mission.planet : null,
      bonusRollGranted,
      player,
      planets,
      missions
    };
  });
}));

// ---------------------------------------------------------------------------
// Nakshatra Cards
// ---------------------------------------------------------------------------
router.get('/cards', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  const b = await loadBundle(db, base);
  const o = cardOpts(base, b);
  const av = availableCards(base, b);
  const cards = G.NAKSHATRA_CARDS.map((_, i) => S.buildCard(G.nakCardId(i), o));
  return {
    today: { card: S.buildCard(av.cardId, o), canCollect: av.canCollect, extra: av.extraIds.map((id) => S.buildCard(id, o)) },
    cards,
    rare: S.rareCatalogue(base.ctx, base.today, o),
    collectedCount: cards.filter((c) => c.collected).length,
    total: 27,
    sets: S.setsView(o),
    upcoming: S.upcomingCards(base.ctx, base.today, o)
  };
}));

router.post('/cards/collect', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  return db.withTransaction(async (client) => {
    const b = await lockProfile(client, base);
    const before = playerOf(base, b);
    const completeBefore = new Set(S.setsView(cardOpts(base, b)).filter((s) => s.complete).map((s) => s.id));
    const av = availableCards(base, b);
    const got = [];
    let xpGained = 0;
    for (const id of av.ids) {
      if (b.collected.has(id)) continue;
      const ins = await client.query(
        `INSERT INTO game_cards (user_id, card_id, kind, collected_on) VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, card_id) DO NOTHING RETURNING id`,
        [base.userId, id, S.cardKind(id), base.today]
      );
      if (ins.rows.length > 0) {
        got.push(id);
        xpGained += S.cardXp(id);
      }
    }
    if (xpGained > 0) {
      await client.query('UPDATE game_profiles SET xp = xp + $2, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1', [base.userId, xpGained]);
    }
    const after = await loadBundle(client, base);
    const o = cardOpts(base, after);
    const player = playerOf(base, after);
    return {
      collected: got.map((id) => S.buildCard(id, o)),
      xpGained,
      completedSets: S.setsView(o).filter((s) => s.complete && !completeBefore.has(s.id)).map((s) => s.id),
      player,
      leveledUp: player.level > before.level
    };
  });
}));

router.post('/cards/sets/:id/claim', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  const setId = String(req.params.id || '');
  return db.withTransaction(async (client) => {
    const b = await lockProfile(client, base);
    const set = S.setsView(cardOpts(base, b)).find((s) => s.id === setId);
    if (!set) throw new GameError(404, 'SET_NOT_FOUND', 'That card set does not exist.');
    if (set.claimed) throw new GameError(409, 'ALREADY_CLAIMED', 'You have already claimed this reward.');
    if (!set.complete) {
      throw new GameError(409, 'SET_INCOMPLETE', `Collect all ${set.cardIds.length} cards in this set first (${set.collected}/${set.cardIds.length} so far).`);
    }
    const reward = set.reward;
    const ins = await client.query(
      `INSERT INTO game_set_claims (user_id, set_id, reward_type, amount) VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, set_id) DO NOTHING RETURNING id`,
      [base.userId, set.id, reward.type, reward.amount]
    );
    if (ins.rows.length === 0) throw new GameError(409, 'ALREADY_CLAIMED', 'You have already claimed this reward.');

    let walletBalance = null;
    if (reward.type === 'wallet') {
      const w = await client.query(
        'UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + $1 WHERE id = $2 RETURNING wallet_balance',
        [reward.amount, base.userId]
      );
      await client.query(
        `INSERT INTO wallet_transactions (user_id, type, amount, description) VALUES ($1, 'recharge', $2, $3)`,
        [base.userId, reward.amount, `Game reward: ${set.name} card set`]
      );
      walletBalance = Number(w.rows[0].wallet_balance);
    } else {
      await client.query('UPDATE game_profiles SET xp = xp + $2, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1', [base.userId, reward.amount]);
    }
    const after = await loadBundle(client, base);
    return { reward, walletBalance, player: playerOf(base, after) };
  });
}));

// ---------------------------------------------------------------------------
// Moksha Patam
// ---------------------------------------------------------------------------
async function familyRows(q, userId) {
  const r = await q.query('SELECT * FROM family_kundlis WHERE user_id = $1 ORDER BY id LIMIT 60', [userId]);
  return r.rows;
}

// Keeps moksha_players in step with the family list (adds new profiles, drops deleted ones)
async function syncMokshaPlayers(q, base, family) {
  const want = ['self', ...family.map((f) => `fam:${f.id}`)];
  let rows = (await q.query('SELECT * FROM moksha_players WHERE user_id = $1', [base.userId])).rows;
  const have = new Set(rows.map((r) => r.profile_key));
  const missing = want.filter((k) => !have.has(k));
  const stale = rows.filter((r) => !want.includes(r.profile_key)).map((r) => r.profile_key);
  if (missing.length) {
    await q.query(
      `INSERT INTO moksha_players (user_id, profile_key)
       SELECT $1, k FROM unnest($2::text[]) AS k
       ON CONFLICT (user_id, profile_key) DO NOTHING`,
      [base.userId, missing]
    );
  }
  if (stale.length) {
    await q.query('DELETE FROM moksha_players WHERE user_id = $1 AND profile_key = ANY($2::text[])', [base.userId, stale]);
  }
  if (missing.length || stale.length) {
    rows = (await q.query('SELECT * FROM moksha_players WHERE user_id = $1', [base.userId])).rows;
  }
  const byKey = new Map(rows.map((r) => [r.profile_key, r]));
  return want.map((k) => byKey.get(k)).filter(Boolean);
}

// Each family player's own sky today (their chart, the account's local date)
function familyDay(base, famRow) {
  try {
    const kundli = kundliFromRow(famRow);
    if (!kundli) return null;
    return F.dayLite(F.createContext(kundli), base.today);
  } catch (_) {
    return null;
  }
}

function mokshaPlayers(base, rows, family, bonusRoll) {
  const famById = new Map(family.map((f) => [`fam:${f.id}`, f]));
  return rows.map((row) => {
    const isSelf = row.profile_key === 'self';
    const fam = famById.get(row.profile_key);
    const day = isSelf ? base.day : familyDay(base, fam);
    return {
      profileKey: row.profile_key,
      name: isSelf ? base.name : fam.full_name,
      relationship: isSelf ? null : fam.relationship || null,
      position: Number(row.position) || 1,
      wins: Number(row.wins) || 0,
      rollsLeft: S.rollsLeft(row, base.today, day, { isSelf, bonusRoll }),
      isYou: isSelf,
      luck: S.luckView(day),
      _day: day
    };
  });
}
const publicPlayers = (players) => players.map(({ _day, ...rest }) => rest);

router.get('/moksha', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  const family = await familyRows(db, base.userId);
  const rows = await syncMokshaPlayers(db, base, family);
  const b = await loadBundle(db, base);
  const players = mokshaPlayers(base, rows, family, bonusToday(base, b));
  const nameOf = new Map(players.map((p) => [p.profileKey, p.name]));
  const moves = await db.query(
    `SELECT profile_key, player_name, dice, from_square, to_square, event, created_at
     FROM moksha_moves WHERE user_id = $1 ORDER BY id DESC LIMIT 10`,
    [base.userId]
  );
  return {
    board: G.BOARD,
    players: publicPlayers(players),
    lastMoves: moves.rows.map((m) => ({
      profileKey: m.profile_key,
      name: nameOf.get(m.profile_key) || m.player_name || 'Player',
      dice: m.dice,
      from: m.from_square,
      to: m.to_square,
      event: m.event || null,
      at: new Date(m.created_at).toISOString()
    }))
  };
}));

router.post('/moksha/roll', optionalAuthenticateToken, handle(async (req) => {
  const base = await baseContext(req);
  const raw = req.body && req.body.profileKey !== undefined && req.body.profileKey !== null ? req.body.profileKey : 'self';
  const profileKey = typeof raw === 'string' ? raw.trim() : '';
  if (!/^(self|fam:\d{1,9})$/.test(profileKey)) throw new GameError(404, 'PLAYER_NOT_FOUND', 'That player is not on your board.');

  return db.withTransaction(async (client) => {
    const b = await lockProfile(client, base);
    const family = await familyRows(client, base.userId);
    await syncMokshaPlayers(client, base, family);
    const locked = await client.query(
      'SELECT * FROM moksha_players WHERE user_id = $1 AND profile_key = $2 FOR UPDATE',
      [base.userId, profileKey]
    );
    const row = locked.rows[0];
    if (!row) throw new GameError(404, 'PLAYER_NOT_FOUND', 'That player is not on your board.');

    const isSelf = profileKey === 'self';
    const bonusRoll = bonusToday(base, b);
    const me = mokshaPlayers(base, [row], family, bonusRoll)[0];
    if (me.rollsLeft <= 0) {
      throw new GameError(409, 'NO_ROLLS_LEFT', `${isSelf ? 'You have' : `${me.name} has`} no rolls left today.`, {
        nextRollHint: S.nextRollHint({ isSelf, bonusRoll })
      });
    }

    const dice = crypto.randomInt(1, 7);
    const r = S.applyRoll(row.position, dice);
    const used = (String(row.rolls_date || '').slice(0, 10) === base.today ? Number(row.rolls_used) || 0 : 0) + 1;
    await client.query(
      `UPDATE moksha_players SET position = $3, wins = wins + $4, rolls_date = $5, rolls_used = $6, updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1 AND profile_key = $2`,
      [base.userId, profileKey, r.won ? 1 : r.to, r.won ? 1 : 0, base.today, used]
    );
    await client.query(
      `INSERT INTO moksha_moves (user_id, profile_key, player_name, dice, from_square, landed_square, to_square, event, won, local_date)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [base.userId, profileKey, me.name, dice, r.from, r.landed, r.to, S.moveLabel(r), r.won, base.today]
    );

    let reward = null;
    if (r.won) {
      const xp = isSelf ? base.config.mokshaWinXp : Math.round(base.config.mokshaWinXp / 2);
      reward = { xp, card: null };
      if (xp > 0) await client.query('UPDATE game_profiles SET xp = xp + $2, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1', [base.userId, xp]);
      if (isSelf) {
        const ins = await client.query(
          `INSERT INTO game_cards (user_id, card_id, kind, collected_on) VALUES ($1, 'rare:moksha', 'rare', $2)
           ON CONFLICT (user_id, card_id) DO NOTHING RETURNING id`,
          [base.userId, base.today]
        );
        const firstWin = ins.rows.length > 0;
        if (firstWin) {
          const col = new Map(b.collected);
          col.set('rare:moksha', base.today);
          reward.card = S.buildCard('rare:moksha', { birthNak: base.birthNak, collected: col });
        }
        // Optional one-time wallet credit for the very first Moksha (off by default)
        if (firstWin && base.registered && base.config.walletRewards && base.config.mokshaWinWallet > 0) {
          const amount = base.config.mokshaWinWallet;
          await client.query('UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + $1 WHERE id = $2', [amount, base.userId]);
          await client.query(
            `INSERT INTO wallet_transactions (user_id, type, amount, description) VALUES ($1, 'recharge', $2, $3)`,
            [base.userId, amount, 'Game reward: first Moksha in Moksha Patam']
          );
          reward.wallet = amount;
        }
      }
    }

    const after = await loadBundle(client, base);
    const rows = await syncMokshaPlayers(client, base, family);
    const players = mokshaPlayers(base, rows, family, bonusToday(base, after));
    const mine = players.find((p) => p.profileKey === profileKey);
    return {
      profileKey,
      dice,
      from: r.from,
      landed: r.landed,
      to: r.to,
      event: r.event,
      overshoot: r.overshoot,
      won: r.won,
      reward,
      rollsLeft: mine ? mine.rollsLeft : 0,
      players: publicPlayers(players),
      player: playerOf(base, after)
    };
  });
}));

// ---------------------------------------------------------------------------
// Cosmic Match
// ---------------------------------------------------------------------------
async function friendRows(q, userId) {
  const r = await q.query(
    `SELECT u.id AS friend_id, u.full_name AS user_name, ${KUNDLI_COLS}
     FROM friend_links f
     JOIN users u ON u.id = f.friend_user_id
     LEFT JOIN birth_details bd ON bd.user_id = u.id
     LEFT JOIN kundlis k ON k.user_id = u.id
     WHERE f.user_id = $1
     ORDER BY f.id
     LIMIT $2`,
    [userId, S.MAX_CIRCLE]
  );
  return r.rows;
}

function memberFrom(base, id, kind, name, relationship, kundli) {
  const myMoon = S.moonProfile(base.kundli);
  let compat = null;
  let score = { todayScore: null, mood: null };
  if (kundli) {
    compat = S.compatibility(myMoon, S.moonProfile(kundli));
    score = S.dayScore(kundli, base.today);
  }
  return {
    id, kind, name, relationship,
    hasChart: !!kundli,
    moonSign: kundli ? kundli.moonSign || null : null,
    nakshatra: kundli ? kundli.nakshatra || null : null,
    compatibility: S.publicCompat(compat),
    todayScore: score.todayScore,
    mood: score.mood,
    _compat: compat
  };
}

async function circlePayload(base) {
  const inviteCode = await ensureInviteCode(base);
  const [family, friends] = [await familyRows(db, base.userId), await friendRows(db, base.userId)];
  const members = [];
  for (const f of family) {
    let kundli = null;
    try { kundli = kundliFromRow(f); } catch (_) { kundli = null; }
    members.push(memberFrom(base, `fam:${f.id}`, 'family', f.full_name, f.relationship || null, kundli));
  }
  for (const f of friends) {
    let kundli = null;
    try { kundli = kundliFromRow(f); } catch (_) { kundli = null; }
    // Friends only ever expose: display name, Moon sign, nakshatra, compatibility and today's score
    members.push(memberFrom(base, `friend:${f.friend_id}`, 'friend', f.user_name || 'Friend', null, kundli));
  }
  const capped = members.slice(0, S.MAX_CIRCLE);
  return {
    inviteCode,
    shareText: S.shareText(inviteCode),
    canInvite: base.registered,
    members: capped.map(({ _compat, ...rest }) => rest),
    you: {
      name: base.displayName,
      moonSign: base.kundli.moonSign || null,
      nakshatra: base.kundli.nakshatra || null,
      todayScore: base.day.overall,
      mood: base.day.mood
    },
    rankings: S.buildRankings(capped)
  };
}

function requireLogin(req) {
  if (!req.user || req.user.role === 'guest') throw new GameError(401, 'LOGIN_REQUIRED', LOGIN_MSG);
}

router.get('/circle', optionalAuthenticateToken, handle(async (req) => circlePayload(await baseContext(req))));

router.post('/circle/join', optionalAuthenticateToken, handle(async (req) => {
  requireLogin(req);
  const base = await baseContext(req);
  if (!base.registered) throw new GameError(401, 'LOGIN_REQUIRED', LOGIN_MSG);
  const code = S.normalizeInviteCode(req.body && req.body.code);
  if (!code) throw new GameError(400, 'BAD_CODE', "Enter your friend's invite code.");

  const friendId = await db.withTransaction(async (client) => {
    const f = await client.query(`SELECT id, role FROM users WHERE invite_code = $1`, [code]);
    const friend = f.rows[0];
    if (!friend || friend.role === 'guest') throw new GameError(404, 'INVALID_CODE', "We couldn't find that code. Check it with your friend and try again.");
    if (friend.id === base.userId) throw new GameError(400, 'OWN_CODE', "That's your own code. Share it with a friend instead!");
    // Lock both accounts in a stable order so two simultaneous joins cannot deadlock
    const pair = [base.userId, friend.id].sort((x, y) => x - y);
    await client.query('SELECT id FROM users WHERE id = ANY($1::int[]) ORDER BY id FOR UPDATE', [pair]);
    const existing = await client.query('SELECT 1 FROM friend_links WHERE user_id = $1 AND friend_user_id = $2', [base.userId, friend.id]);
    if (existing.rows.length > 0) throw new GameError(409, 'ALREADY_FRIENDS', 'You two are already in each other\'s circle.');
    const sizes = await client.query(
      `SELECT u.id,
              (SELECT COUNT(*) FROM friend_links f WHERE f.user_id = u.id) + (SELECT COUNT(*) FROM family_kundlis k WHERE k.user_id = u.id) AS size
       FROM users u WHERE u.id = ANY($1::int[])`,
      [pair]
    );
    for (const s of sizes.rows) {
      if (Number(s.size) >= S.MAX_CIRCLE) {
        throw new GameError(409, 'CIRCLE_FULL', s.id === base.userId
          ? `Your circle is full (${S.MAX_CIRCLE} people). Remove someone to add a new friend.`
          : "Your friend's circle is full right now.");
      }
    }
    await client.query(
      `INSERT INTO friend_links (user_id, friend_user_id) VALUES ($1, $2), ($2, $1)
       ON CONFLICT (user_id, friend_user_id) DO NOTHING`,
      [base.userId, friend.id]
    );
    return friend.id;
  });

  const circle = await circlePayload(base);
  return { member: circle.members.find((x) => x.id === `friend:${friendId}`) || null, circle };
}));

router.delete('/circle/friends/:userId', optionalAuthenticateToken, handle(async (req) => {
  requireLogin(req);
  const friendId = Number(req.params.userId);
  if (!Number.isInteger(friendId) || friendId <= 0) throw new GameError(400, 'BAD_REQUEST', 'Invalid friend id.');
  const base = await baseContext(req);
  await db.query(
    `DELETE FROM friend_links
     WHERE (user_id = $1 AND friend_user_id = $2) OR (user_id = $2 AND friend_user_id = $1)`,
    [base.userId, friendId]
  );
  return { success: true, circle: await circlePayload(base) };
}));

module.exports = router;
