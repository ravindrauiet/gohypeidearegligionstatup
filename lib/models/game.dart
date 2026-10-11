// Typed models for the games API (`/api/game/*`): Graha Quest, Nakshatra
// Cards, Moksha Patam and Cosmic Match.
//
// Parsing is deliberately forgiving (same helpers as the forecast models):
// numbers may arrive as strings, any field may be null or missing, and lists
// may contain junk. Every `fromJson` returns a usable object, never throws.

import 'forecast.dart';

export 'forecast.dart' show fMap, fList, fMapList, fStr, fStrOrNull, fInt, fIntOrNull, fDouble, fBool, fStrList, fDate;

// ---------------------------------------------------------------------------
// Shared objects
// ---------------------------------------------------------------------------

/// The nine grahas, in the order the game shows them.
const List<String> kGamePlanets = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];

String _planetName(dynamic v) {
  final s = fStr(v);
  if (s.isEmpty) return '';
  final norm = s[0].toUpperCase() + s.substring(1).toLowerCase();
  return kGamePlanets.contains(norm) ? norm : s;
}

class GamePlayer {
  final int level;
  final int xp;
  final int xpIntoLevel;
  final int xpForNext;
  final String title;
  final int streak;
  final int bestStreak;
  final bool streakAliveToday;

  const GamePlayer({
    this.level = 1,
    this.xp = 0,
    this.xpIntoLevel = 0,
    this.xpForNext = 100,
    this.title = 'Star Seeker',
    this.streak = 0,
    this.bestStreak = 0,
    this.streakAliveToday = false,
  });

  factory GamePlayer.fromJson(dynamic json) {
    final j = fMap(json);
    final level = fInt(j['level'], 1).clamp(1, 9999);
    final forNext = fInt(j['xpForNext']);
    final streak = fInt(j['streak']).clamp(0, 100000);
    return GamePlayer(
      level: level,
      xp: fInt(j['xp']).clamp(0, 1 << 31),
      xpIntoLevel: fInt(j['xpIntoLevel']).clamp(0, 1 << 31),
      xpForNext: forNext > 0 ? forNext : 100 * level,
      title: fStr(j['title'], 'Star Seeker'),
      streak: streak,
      bestStreak: fInt(j['bestStreak'], streak).clamp(streak, 100000),
      streakAliveToday: fBool(j['streakAliveToday']),
    );
  }

  /// 0..1 progress through the current level.
  double get progress => xpForNext <= 0 ? 0 : (xpIntoLevel / xpForNext).clamp(0.0, 1.0);

  int get xpToNext => (xpForNext - xpIntoLevel).clamp(0, xpForNext);

  /// Local, optimistic copy after gaining [gain] XP (the server stays the truth).
  GamePlayer withXpGain(int gain, {bool streakAlive = true}) {
    var lvl = level, into = xpIntoLevel + gain, need = xpForNext;
    while (need > 0 && into >= need) {
      into -= need;
      lvl++;
      need = 100 * lvl;
    }
    final newStreak = (streakAlive && !streakAliveToday) ? streak + 1 : streak;
    return GamePlayer(
      level: lvl,
      xp: xp + gain,
      xpIntoLevel: into,
      xpForNext: need,
      title: title,
      streak: newStreak,
      bestStreak: newStreak > bestStreak ? newStreak : bestStreak,
      streakAliveToday: streakAliveToday || streakAlive,
    );
  }
}

class PlanetStatus {
  PlanetStatus._();
  static const strong = 'strong';
  static const steady = 'steady';
  static const needsCare = 'needs_care';

  static String parse(dynamic v) {
    final s = fStr(v).toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (s == strong) return strong;
    if (s == needsCare || s == 'needscare' || s == 'weak') return needsCare;
    return steady;
  }

  static String label(String s) => s == strong ? 'Strong' : (s == needsCare ? 'Needs you' : 'Steady');
}

class GamePlanet {
  final String planet;
  final int level;
  final int power;
  final String natal;
  final String status;
  final String role;
  final int xp;

  /// Optional character extras from the server.
  final String? emoji;
  final String? title;
  final String? personality;

  const GamePlanet({
    required this.planet,
    this.level = 1,
    this.power = 0,
    this.natal = '',
    this.status = PlanetStatus.steady,
    this.role = '',
    this.xp = 0,
    this.emoji,
    this.title,
    this.personality,
  });

  factory GamePlanet.fromJson(dynamic json) {
    final j = fMap(json);
    return GamePlanet(
      planet: _planetName(j['planet'] ?? j['name']),
      level: fInt(j['level'], 1).clamp(1, 10),
      power: fInt(j['power']).clamp(0, 100),
      natal: fStr(j['natal']),
      status: PlanetStatus.parse(j['status']),
      role: fStr(j['role']),
      xp: fInt(j['xp']).clamp(0, 1 << 31),
      emoji: fStrOrNull(j['emoji']),
      title: fStrOrNull(j['title']),
      personality: fStrOrNull(j['personality']),
    );
  }

  bool get needsCare => status == PlanetStatus.needsCare;

  static List<GamePlanet> listFrom(dynamic v) =>
      fMapList(v).map(GamePlanet.fromJson).where((p) => p.planet.isNotEmpty).toList();
}

class GameMission {
  final String id;
  final String planet;
  final String title;
  final String why;
  final int xp;
  final bool done;
  final String category;

  const GameMission({
    required this.id,
    this.planet = '',
    this.title = '',
    this.why = '',
    this.xp = 0,
    this.done = false,
    this.category = 'action',
  });

  factory GameMission.fromJson(dynamic json) {
    final j = fMap(json);
    const cats = ['action', 'kindness', 'mind', 'body', 'learn'];
    final cat = fStr(j['category']).toLowerCase();
    return GameMission(
      id: fStr(j['id']),
      planet: _planetName(j['planet']),
      title: fStr(j['title'], 'Mission'),
      why: fStr(j['why']),
      xp: fInt(j['xp']).clamp(0, 100000),
      done: fBool(j['done']),
      category: cats.contains(cat) ? cat : 'action',
    );
  }

  GameMission copyWith({bool? done}) => GameMission(
      id: id, planet: planet, title: title, why: why, xp: xp, done: done ?? this.done, category: category);
}

class MissionsDay {
  final DateTime? date;
  final List<GameMission> items;
  final int completedCount;
  final bool allDone;
  final int allDoneBonusXp;
  final bool bonusRollGranted;

  const MissionsDay({
    this.date,
    this.items = const [],
    this.completedCount = 0,
    this.allDone = false,
    this.allDoneBonusXp = 0,
    this.bonusRollGranted = false,
  });

  factory MissionsDay.fromJson(dynamic json) {
    final j = fMap(json);
    final items = fMapList(j['items']).map(GameMission.fromJson).where((m) => m.id.isNotEmpty).toList();
    final doneCount = items.where((m) => m.done).length;
    final completed = fIntOrNull(j['completedCount']) ?? doneCount;
    return MissionsDay(
      date: fDate(j['date']),
      items: items,
      completedCount: completed.clamp(0, items.isEmpty ? completed.clamp(0, 99) : items.length),
      allDone: j['allDone'] == null ? (items.isNotEmpty && doneCount == items.length) : fBool(j['allDone']),
      allDoneBonusXp: fInt(j['allDoneBonusXp']).clamp(0, 100000),
      bonusRollGranted: fBool(j['bonusRollGranted']),
    );
  }

  int get total => items.length;
  int get xpAvailable => items.where((m) => !m.done).fold(0, (a, m) => a + m.xp);

  /// Local copy with mission [id] marked done / not done (optimistic UI).
  MissionsDay withDone(String id, bool done) {
    final next = [for (final m in items) m.id == id ? m.copyWith(done: done) : m];
    final count = next.where((m) => m.done).length;
    return MissionsDay(
      date: date,
      items: next,
      completedCount: count,
      allDone: next.isNotEmpty && count == next.length,
      allDoneBonusXp: allDoneBonusXp,
      bonusRollGranted: bonusRollGranted,
    );
  }
}

class CardRarity {
  CardRarity._();
  static const common = 'common';
  static const rare = 'rare';
  static const legendary = 'legendary';

  static String parse(dynamic v) {
    final s = fStr(v).toLowerCase();
    return s == rare || s == legendary ? s : common;
  }

  static String label(String r) => r == legendary ? 'Legendary' : (r == rare ? 'Rare' : 'Common');
}

/// A collectible card (one of the 27 nakshatras, or a rare event card).
class CosmicCard {
  final String id;
  final String kind; // 'nakshatra' | 'rare'
  final String name;
  final String symbol;
  final String? ruler;
  final String? deity;
  final String power;
  final List<String> keywords;
  final String rarity;
  final bool isBirthStar;
  final bool collected;
  final DateTime? collectedOn;

  /// Nakshatra number 1-27 (nakshatra cards), when sent.
  final int? number;

  /// Rare cards: how to get it.
  final String? how;

  /// Rare event cards (e.g. an eclipse): the day it happens.
  final DateTime? date;

  const CosmicCard({
    required this.id,
    this.kind = 'nakshatra',
    this.name = '',
    this.symbol = '✨',
    this.ruler,
    this.deity,
    this.power = '',
    this.keywords = const [],
    this.rarity = CardRarity.common,
    this.isBirthStar = false,
    this.collected = false,
    this.collectedOn,
    this.number,
    this.how,
    this.date,
  });

  factory CosmicCard.fromJson(dynamic json) {
    final j = fMap(json);
    final id = fStr(j['id']);
    final kindRaw = fStr(j['kind']).toLowerCase();
    final kind = kindRaw == 'rare' || kindRaw == 'nakshatra' ? kindRaw : (id.startsWith('rare:') ? 'rare' : 'nakshatra');
    final ruler = fStrOrNull(j['ruler']);
    final on = fDate(j['collectedOn']);
    return CosmicCard(
      id: id,
      kind: kind,
      name: fStr(j['name'], 'Mystery card'),
      symbol: fStr(j['symbol'], '✨'),
      ruler: ruler == null ? null : _planetName(ruler),
      deity: fStrOrNull(j['deity']),
      power: fStr(j['power']),
      keywords: fStrList(j['keywords']),
      rarity: j['rarity'] == null && kind == 'rare' ? CardRarity.rare : CardRarity.parse(j['rarity']),
      isBirthStar: fBool(j['isBirthStar']),
      collected: j['collected'] == null ? on != null : fBool(j['collected']),
      collectedOn: on,
      number: fIntOrNull(j['number']),
      how: fStrOrNull(j['how']),
      date: fDate(j['date']),
    );
  }

  bool get isRare => kind == 'rare';
  bool get isEmpty => id.isEmpty;

  CosmicCard asCollected([DateTime? on]) => CosmicCard(
        id: id,
        kind: kind,
        name: name,
        symbol: symbol,
        ruler: ruler,
        deity: deity,
        power: power,
        keywords: keywords,
        rarity: rarity,
        isBirthStar: isBirthStar,
        collected: true,
        collectedOn: collectedOn ?? on,
        number: number,
        how: how,
        date: date,
      );

  static List<CosmicCard> listFrom(dynamic v) =>
      fMapList(v).map(CosmicCard.fromJson).where((c) => c.id.isNotEmpty).toList();
}

class GameLuck {
  final String tara;
  final bool favorable;
  final bool chandrashtama;
  final String line;

  const GameLuck({this.tara = '', this.favorable = false, this.chandrashtama = false, this.line = ''});

  factory GameLuck.fromJson(dynamic json) {
    final j = fMap(json);
    return GameLuck(
      tara: fStr(j['tara']),
      favorable: fBool(j['favorable']),
      chandrashtama: fBool(j['chandrashtama']),
      line: fStr(j['line']),
    );
  }

  bool get isEmpty => tara.isEmpty && line.isEmpty;
}

// ---------------------------------------------------------------------------
// GET /game/state
// ---------------------------------------------------------------------------

class CardSummary {
  final CosmicCard today;
  final bool canCollect;
  final int collectedCount;
  final int total;
  final int rareCount;

  const CardSummary({
    this.today = const CosmicCard(id: ''),
    this.canCollect = false,
    this.collectedCount = 0,
    this.total = 27,
    this.rareCount = 0,
  });

  factory CardSummary.fromJson(dynamic json) {
    final j = fMap(json);
    final total = fInt(j['total'], 27);
    return CardSummary(
      today: CosmicCard.fromJson(j['today']),
      canCollect: fBool(j['canCollect']),
      collectedCount: fInt(j['collectedCount']).clamp(0, 9999),
      total: total > 0 ? total : 27,
      rareCount: fInt(j['rareCount']).clamp(0, 9999),
    );
  }
}

class MokshaSummary {
  final int position;
  final int rollsLeft;
  final int wins;
  const MokshaSummary({this.position = 1, this.rollsLeft = 0, this.wins = 0});

  factory MokshaSummary.fromJson(dynamic json) {
    final j = fMap(json);
    return MokshaSummary(
      position: fInt(j['position'], 1).clamp(1, 100),
      rollsLeft: fInt(j['rollsLeft']).clamp(0, 99),
      wins: fInt(j['wins']).clamp(0, 100000),
    );
  }
}

class CircleSummary {
  final int memberCount;
  final String? inviteCode;
  const CircleSummary({this.memberCount = 0, this.inviteCode});

  factory CircleSummary.fromJson(dynamic json) {
    final j = fMap(json);
    return CircleSummary(memberCount: fInt(j['memberCount']).clamp(0, 100000), inviteCode: fStrOrNull(j['inviteCode']));
  }
}

class GameState {
  final GamePlayer player;
  final List<GamePlanet> planets;
  final MissionsDay missions;
  final CardSummary card;
  final MokshaSummary moksha;
  final CircleSummary circle;
  final GameLuck luck;

  const GameState({
    this.player = const GamePlayer(),
    this.planets = const [],
    this.missions = const MissionsDay(),
    this.card = const CardSummary(),
    this.moksha = const MokshaSummary(),
    this.circle = const CircleSummary(),
    this.luck = const GameLuck(),
  });

  factory GameState.fromJson(dynamic json) {
    final j = fMap(json);
    return GameState(
      player: GamePlayer.fromJson(j['player']),
      planets: GamePlanet.listFrom(j['planets']),
      missions: MissionsDay.fromJson(j['missions']),
      card: CardSummary.fromJson(j['card']),
      moksha: MokshaSummary.fromJson(j['moksha']),
      circle: CircleSummary.fromJson(j['circle']),
      luck: GameLuck.fromJson(j['luck']),
    );
  }

  GameState copyWith({GamePlayer? player, List<GamePlanet>? planets, MissionsDay? missions}) => GameState(
        player: player ?? this.player,
        planets: planets ?? this.planets,
        missions: missions ?? this.missions,
        card: card,
        moksha: moksha,
        circle: circle,
        luck: luck,
      );
}

// ---------------------------------------------------------------------------
// Graha Quest
// ---------------------------------------------------------------------------

class MissionCompleteResult {
  final GameMission mission;
  final int xpGained;
  final int bonusXp;
  final bool leveledUp;
  final String? planetLeveledUp;
  final bool bonusRollGranted;
  final GamePlayer player;
  final List<GamePlanet> planets;
  final MissionsDay missions;

  const MissionCompleteResult({
    required this.mission,
    this.xpGained = 0,
    this.bonusXp = 0,
    this.leveledUp = false,
    this.planetLeveledUp,
    this.bonusRollGranted = false,
    this.player = const GamePlayer(),
    this.planets = const [],
    this.missions = const MissionsDay(),
  });

  factory MissionCompleteResult.fromJson(dynamic json) {
    final j = fMap(json);
    final planet = fStrOrNull(j['planetLeveledUp']);
    return MissionCompleteResult(
      mission: GameMission.fromJson(j['mission']),
      xpGained: fInt(j['xpGained']).clamp(0, 1000000),
      bonusXp: fInt(j['bonusXp']).clamp(0, 1000000),
      leveledUp: fBool(j['leveledUp']),
      planetLeveledUp: planet == null ? null : _planetName(planet),
      bonusRollGranted: fBool(j['bonusRollGranted']),
      player: GamePlayer.fromJson(j['player']),
      planets: GamePlanet.listFrom(j['planets']),
      missions: MissionsDay.fromJson(j['missions']),
    );
  }
}

// ---------------------------------------------------------------------------
// Nakshatra Cards
// ---------------------------------------------------------------------------

class SetReward {
  final String type; // 'wallet' | 'xp'
  final int amount;
  final String label;
  const SetReward({this.type = 'xp', this.amount = 0, this.label = ''});

  factory SetReward.fromJson(dynamic json) {
    final j = fMap(json);
    final type = fStr(j['type']).toLowerCase() == 'wallet' ? 'wallet' : 'xp';
    final amount = fInt(j['amount']).clamp(0, 10000000);
    return SetReward(
      type: type,
      amount: amount,
      label: fStr(j['label'], type == 'wallet' ? '₹$amount wallet credit' : '+$amount XP'),
    );
  }

  bool get isWallet => type == 'wallet';
}

class CardSet {
  final String id;
  final String name;
  final List<String> cardIds;
  final int collected;
  final bool complete;
  final SetReward reward;
  final bool claimed;

  const CardSet({
    required this.id,
    this.name = '',
    this.cardIds = const [],
    this.collected = 0,
    this.complete = false,
    this.reward = const SetReward(),
    this.claimed = false,
  });

  factory CardSet.fromJson(dynamic json) {
    final j = fMap(json);
    final ids = fStrList(j['cardIds']);
    final collected = fInt(j['collected']).clamp(0, ids.isEmpty ? 999 : ids.length);
    return CardSet(
      id: fStr(j['id']),
      name: fStr(j['name'], 'Card set'),
      cardIds: ids,
      collected: collected,
      complete: j['complete'] == null ? (ids.isNotEmpty && collected >= ids.length) : fBool(j['complete']),
      reward: SetReward.fromJson(j['reward']),
      claimed: fBool(j['claimed']),
    );
  }

  int get size => cardIds.isEmpty ? (collected > 0 ? collected : 1) : cardIds.length;
  double get progress => (collected / size).clamp(0.0, 1.0);
  bool get canClaim => complete && !claimed;

  CardSet asClaimed() => CardSet(
      id: id, name: name, cardIds: cardIds, collected: collected, complete: complete, reward: reward, claimed: true);
}

class UpcomingCard {
  final CosmicCard card;
  final DateTime? date;
  const UpcomingCard({required this.card, this.date});

  factory UpcomingCard.fromJson(dynamic json) {
    final j = fMap(json);
    return UpcomingCard(card: CosmicCard.fromJson(j['card']), date: fDate(j['date']));
  }
}

class TodayCards {
  final CosmicCard card;
  final bool canCollect;
  final List<CosmicCard> extra;
  const TodayCards({this.card = const CosmicCard(id: ''), this.canCollect = false, this.extra = const []});

  factory TodayCards.fromJson(dynamic json) {
    final j = fMap(json);
    return TodayCards(
      card: CosmicCard.fromJson(j['card']),
      canCollect: fBool(j['canCollect']),
      extra: CosmicCard.listFrom(j['extra']),
    );
  }
}

class CardAlbum {
  final TodayCards today;
  final List<CosmicCard> cards;
  final List<CosmicCard> rare;
  final int collectedCount;
  final int total;
  final List<CardSet> sets;
  final List<UpcomingCard> upcoming;

  const CardAlbum({
    this.today = const TodayCards(),
    this.cards = const [],
    this.rare = const [],
    this.collectedCount = 0,
    this.total = 27,
    this.sets = const [],
    this.upcoming = const [],
  });

  factory CardAlbum.fromJson(dynamic json) {
    final j = fMap(json);
    final cards = CosmicCard.listFrom(j['cards']);
    final total = fInt(j['total'], cards.isEmpty ? 27 : cards.length);
    return CardAlbum(
      today: TodayCards.fromJson(j['today']),
      cards: cards,
      rare: CosmicCard.listFrom(j['rare']),
      collectedCount: fIntOrNull(j['collectedCount']) ?? cards.where((c) => c.collected).length,
      total: total > 0 ? total : 27,
      sets: fMapList(j['sets']).map(CardSet.fromJson).where((s) => s.id.isNotEmpty).toList(),
      upcoming: fMapList(j['upcoming']).map(UpcomingCard.fromJson).where((u) => u.card.id.isNotEmpty).toList(),
    );
  }

  /// When the Moon (or a rare event) next brings card [id], if known.
  DateTime? arrivalOf(String id) {
    for (final u in upcoming) {
      if (u.card.id == id) return u.date;
    }
    return null;
  }

  CosmicCard? cardById(String id) {
    for (final c in [...cards, ...rare, today.card, ...today.extra]) {
      if (c.id == id) return c;
    }
    return null;
  }
}

class CollectResult {
  final List<CosmicCard> collected;
  final int xpGained;
  final List<String> completedSets;
  final GamePlayer player;
  final bool leveledUp;

  const CollectResult({
    this.collected = const [],
    this.xpGained = 0,
    this.completedSets = const [],
    this.player = const GamePlayer(),
    this.leveledUp = false,
  });

  factory CollectResult.fromJson(dynamic json) {
    final j = fMap(json);
    return CollectResult(
      collected: CosmicCard.listFrom(j['collected']),
      xpGained: fInt(j['xpGained']).clamp(0, 1000000),
      completedSets: fStrList(j['completedSets']),
      player: GamePlayer.fromJson(j['player']),
      leveledUp: fBool(j['leveledUp']),
    );
  }
}

class ClaimResult {
  final SetReward reward;
  final double? walletBalance;
  final GamePlayer player;

  const ClaimResult({this.reward = const SetReward(), this.walletBalance, this.player = const GamePlayer()});

  factory ClaimResult.fromJson(dynamic json) {
    final j = fMap(json);
    final hasBalance = j['walletBalance'] is num ||
        (j['walletBalance'] is String && double.tryParse((j['walletBalance'] as String).trim()) != null);
    return ClaimResult(
      reward: SetReward.fromJson(j['reward']),
      walletBalance: hasBalance ? fDouble(j['walletBalance']) : null,
      player: GamePlayer.fromJson(j['player']),
    );
  }
}

// ---------------------------------------------------------------------------
// Moksha Patam
// ---------------------------------------------------------------------------

/// A ladder (virtue, goes up) or a snake (vice, goes down).
class MokshaJump {
  final int from;
  final int to;
  final String name;
  final String line;
  const MokshaJump({required this.from, required this.to, this.name = '', this.line = ''});

  factory MokshaJump.fromJson(dynamic json) {
    final j = fMap(json);
    return MokshaJump(
      from: fInt(j['from']).clamp(0, 100),
      to: fInt(j['to']).clamp(0, 100),
      name: fStr(j['name']),
      line: fStr(j['line']),
    );
  }

  bool get isLadder => to > from;
  bool get isValid => from >= 1 && to >= 1 && from != to;

  static List<MokshaJump> listFrom(dynamic v) =>
      fMapList(v).map(MokshaJump.fromJson).where((e) => e.isValid).toList();
}

class MokshaPlayer {
  final String profileKey;
  final String name;
  final String? relationship;
  final int position;
  final int wins;
  final int rollsLeft;
  final bool isYou;
  final GameLuck luck;

  const MokshaPlayer({
    required this.profileKey,
    this.name = '',
    this.relationship,
    this.position = 1,
    this.wins = 0,
    this.rollsLeft = 0,
    this.isYou = false,
    this.luck = const GameLuck(),
  });

  factory MokshaPlayer.fromJson(dynamic json) {
    final j = fMap(json);
    final key = fStr(j['profileKey'], 'self');
    return MokshaPlayer(
      profileKey: key,
      name: fStr(j['name'], key == 'self' ? 'You' : 'Player'),
      relationship: fStrOrNull(j['relationship']),
      position: fInt(j['position'], 1).clamp(1, 100),
      wins: fInt(j['wins']).clamp(0, 100000),
      rollsLeft: fInt(j['rollsLeft']).clamp(0, 99),
      isYou: j['isYou'] == null ? key == 'self' : fBool(j['isYou']),
      luck: GameLuck.fromJson(j['luck']),
    );
  }

  static List<MokshaPlayer> listFrom(dynamic v) => fMapList(v).map(MokshaPlayer.fromJson).toList();
}

class MokshaMove {
  final String profileKey;
  final String name;
  final int dice;
  final int from;
  final int to;
  final String? event;
  final DateTime? at;

  const MokshaMove({
    this.profileKey = 'self',
    this.name = '',
    this.dice = 0,
    this.from = 1,
    this.to = 1,
    this.event,
    this.at,
  });

  factory MokshaMove.fromJson(dynamic json) {
    final j = fMap(json);
    final ev = j['event'];
    return MokshaMove(
      profileKey: fStr(j['profileKey'], 'self'),
      name: fStr(j['name']),
      dice: fInt(j['dice']).clamp(0, 6),
      from: fInt(j['from'], 1).clamp(1, 100),
      to: fInt(j['to'], 1).clamp(1, 100),
      event: ev is Map ? fStrOrNull(ev['name'] ?? ev['type']) : fStrOrNull(ev),
      at: DateTime.tryParse(fStr(j['at']))?.toLocal(),
    );
  }
}

class MokshaBoard {
  final int size;
  final List<MokshaJump> ladders;
  final List<MokshaJump> snakes;
  final List<MokshaPlayer> players;
  final List<MokshaMove> lastMoves;

  const MokshaBoard({
    this.size = 100,
    this.ladders = const [],
    this.snakes = const [],
    this.players = const [],
    this.lastMoves = const [],
  });

  factory MokshaBoard.fromJson(dynamic json) {
    final j = fMap(json);
    final b = fMap(j['board']);
    final size = fInt(b['size'], 100);
    return MokshaBoard(
      size: size > 0 ? size : 100,
      ladders: MokshaJump.listFrom(b['ladders']),
      snakes: MokshaJump.listFrom(b['snakes']),
      players: MokshaPlayer.listFrom(j['players']),
      lastMoves: fMapList(j['lastMoves']).map(MokshaMove.fromJson).toList(),
    );
  }

  MokshaPlayer? get you {
    for (final p in players) {
      if (p.isYou) return p;
    }
    return players.isEmpty ? null : players.first;
  }

  MokshaPlayer? playerByKey(String key) {
    for (final p in players) {
      if (p.profileKey == key) return p;
    }
    return null;
  }

  MokshaBoard withPlayers(List<MokshaPlayer> next) =>
      MokshaBoard(size: size, ladders: ladders, snakes: snakes, players: next, lastMoves: lastMoves);
}

class MokshaEvent {
  final String type; // 'ladder' | 'snake'
  final String name;
  final String line;
  const MokshaEvent({required this.type, this.name = '', this.line = ''});

  bool get isLadder => type == 'ladder';
  bool get isSnake => type == 'snake';

  static MokshaEvent? fromJson(dynamic json) {
    if (json is! Map) return null;
    final type = fStr(json['type']).toLowerCase();
    if (type != 'ladder' && type != 'snake') return null;
    return MokshaEvent(type: type, name: fStr(json['name']), line: fStr(json['line']));
  }
}

class MokshaReward {
  final int xp;
  final CosmicCard? card;

  /// Wallet credit (rupees) a win may include.
  final double? wallet;
  const MokshaReward({this.xp = 0, this.card, this.wallet});

  static MokshaReward? fromJson(dynamic json) {
    if (json is! Map) return null;
    final card = json['card'] is Map ? CosmicCard.fromJson(json['card']) : null;
    return MokshaReward(xp: fInt(json['xp']).clamp(0, 1000000), card: (card == null || card.isEmpty) ? null : card,
        wallet: _walletAmount(json['wallet']));
  }
}

class MokshaRollResult {
  final String profileKey;
  final int dice;
  final int from;
  final int landed;
  final int to;
  final MokshaEvent? event;
  final bool overshoot;
  final bool won;
  final MokshaReward? reward;
  final int rollsLeft;
  final List<MokshaPlayer> players;
  final GamePlayer player;

  const MokshaRollResult({
    this.profileKey = 'self',
    this.dice = 1,
    this.from = 1,
    this.landed = 1,
    this.to = 1,
    this.event,
    this.overshoot = false,
    this.won = false,
    this.reward,
    this.rollsLeft = 0,
    this.players = const [],
    this.player = const GamePlayer(),
  });

  factory MokshaRollResult.fromJson(dynamic json) {
    final j = fMap(json);
    final from = fInt(j['from'], 1).clamp(1, 100);
    final to = fInt(j['to'], from).clamp(1, 100);
    return MokshaRollResult(
      profileKey: fStr(j['profileKey'], 'self'),
      dice: fInt(j['dice'], 1).clamp(1, 6),
      from: from,
      landed: fInt(j['landed'], to).clamp(1, 100),
      to: to,
      event: MokshaEvent.fromJson(j['event']),
      overshoot: fBool(j['overshoot']),
      won: fBool(j['won']),
      reward: MokshaReward.fromJson(j['reward']),
      rollsLeft: fInt(j['rollsLeft']).clamp(0, 99),
      players: MokshaPlayer.listFrom(j['players']),
      player: GamePlayer.fromJson(j['player']),
    );
  }
}

// ---------------------------------------------------------------------------
// Cosmic Match
// ---------------------------------------------------------------------------

class Compatibility {
  final double score;
  final double max;
  final String label;
  final String strongest;
  final String weakest;

  const Compatibility({this.score = 0, this.max = 36, this.label = '', this.strongest = '', this.weakest = ''});

  static Compatibility? fromJson(dynamic json) {
    if (json is! Map) return null;
    final max = fDouble(json['max'], 36);
    final m = max > 0 ? max : 36.0;
    return Compatibility(
      score: fDouble(json['score']).clamp(0, m).toDouble(),
      max: m,
      label: fStr(json['label']),
      strongest: fStr(json['strongest']),
      weakest: fStr(json['weakest']),
    );
  }

  double get fraction => (score / max).clamp(0.0, 1.0);

  /// "31/36" or "24.5/36".
  String get display {
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${n(score)}/${n(max)}';
  }
}

class CircleMember {
  final String id;
  final String kind; // 'family' | 'friend'
  final String name;
  final String? relationship;
  final bool hasChart;
  final String? moonSign;
  final String? nakshatra;
  final Compatibility? compatibility;
  final int? todayScore;
  final String? mood;

  const CircleMember({
    required this.id,
    this.kind = 'friend',
    this.name = '',
    this.relationship,
    this.hasChart = false,
    this.moonSign,
    this.nakshatra,
    this.compatibility,
    this.todayScore,
    this.mood,
  });

  factory CircleMember.fromJson(dynamic json) {
    final j = fMap(json);
    final id = fStr(j['id']);
    final kindRaw = fStr(j['kind']).toLowerCase();
    final kind = kindRaw == 'family' || kindRaw == 'friend' ? kindRaw : (id.startsWith('fam:') ? 'family' : 'friend');
    final moon = fStrOrNull(j['moonSign']);
    final score = fIntOrNull(j['todayScore']);
    return CircleMember(
      id: id,
      kind: kind,
      name: fStr(j['name'], 'Friend'),
      relationship: fStrOrNull(j['relationship']),
      hasChart: j['hasChart'] == null ? moon != null : fBool(j['hasChart']),
      moonSign: moon,
      nakshatra: fStrOrNull(j['nakshatra']),
      compatibility: Compatibility.fromJson(j['compatibility']),
      todayScore: score?.clamp(0, 100),
      mood: fStrOrNull(j['mood']),
    );
  }

  bool get isFriend => kind == 'friend';
  bool get isFamily => kind == 'family';

  /// Numeric user id for `removeCircleFriend` (friends only).
  int? get friendUserId => isFriend && id.contains(':') ? int.tryParse(id.split(':').last) : null;

  static List<CircleMember> listFrom(dynamic v) =>
      fMapList(v).map(CircleMember.fromJson).where((m) => m.id.isNotEmpty).toList();
}

class CircleYou {
  final String name;
  final String? moonSign;
  final String? nakshatra;
  final int? todayScore;
  final String? mood;
  const CircleYou({this.name = 'You', this.moonSign, this.nakshatra, this.todayScore, this.mood});

  factory CircleYou.fromJson(dynamic json) {
    final j = fMap(json);
    return CircleYou(
      name: fStr(j['name'], 'You'),
      moonSign: fStrOrNull(j['moonSign']),
      nakshatra: fStrOrNull(j['nakshatra']),
      todayScore: fIntOrNull(j['todayScore'])?.clamp(0, 100),
      mood: fStrOrNull(j['mood']),
    );
  }
}

class RankingEntry {
  final String memberId;
  final String name;
  final String value;
  final String note;
  const RankingEntry({this.memberId = '', this.name = '', this.value = '', this.note = ''});

  factory RankingEntry.fromJson(dynamic json) {
    final j = fMap(json);
    return RankingEntry(
      memberId: fStr(j['memberId']),
      name: fStr(j['name']),
      value: fStr(j['value']),
      note: fStr(j['note']),
    );
  }
}

class CircleRanking {
  final String id;
  final String title;
  final String emoji;
  final bool unlocked;
  final int needMembers;
  final List<RankingEntry> entries;

  const CircleRanking({
    required this.id,
    this.title = '',
    this.emoji = '⭐',
    this.unlocked = false,
    this.needMembers = 0,
    this.entries = const [],
  });

  factory CircleRanking.fromJson(dynamic json) {
    final j = fMap(json);
    final unlocked = fBool(j['unlocked']);
    return CircleRanking(
      id: fStr(j['id']),
      title: fStr(j['title'], 'Ranking'),
      emoji: fStr(j['emoji'], '⭐'),
      unlocked: unlocked,
      needMembers: fInt(j['needMembers']).clamp(0, 1000),
      entries: unlocked
          ? fMapList(j['entries']).map(RankingEntry.fromJson).where((e) => e.name.isNotEmpty).toList()
          : const [],
    );
  }
}

class CosmicCircle {
  final String inviteCode;
  final String shareText;
  final List<CircleMember> members;
  final CircleYou you;
  final List<CircleRanking> rankings;

  const CosmicCircle({
    this.inviteCode = '',
    this.shareText = '',
    this.members = const [],
    this.you = const CircleYou(),
    this.rankings = const [],
  });

  factory CosmicCircle.fromJson(dynamic json) {
    final j = fMap(json);
    return CosmicCircle(
      inviteCode: fStr(j['inviteCode']),
      shareText: fStr(j['shareText']),
      members: CircleMember.listFrom(j['members']),
      you: CircleYou.fromJson(j['you']),
      rankings: fMapList(j['rankings']).map(CircleRanking.fromJson).where((r) => r.id.isNotEmpty).toList(),
    );
  }

  List<CircleMember> get friends => members.where((m) => m.isFriend).toList();
  List<CircleMember> get family => members.where((m) => m.isFamily).toList();
}

class JoinCircleResult {
  final CircleMember? member;
  final CosmicCircle circle;
  const JoinCircleResult({this.member, this.circle = const CosmicCircle()});

  factory JoinCircleResult.fromJson(dynamic json) {
    final j = fMap(json);
    final m = j['member'] is Map ? CircleMember.fromJson(j['member']) : null;
    return JoinCircleResult(member: (m == null || m.id.isEmpty) ? null : m, circle: CosmicCircle.fromJson(j['circle']));
  }
}

/// Wallet credit that may arrive as a number, a numeric string or `{amount}`.
double? _walletAmount(dynamic v) {
  if (v is Map) v = v['amount'];
  if (v is num && v.isFinite && v > 0) return v.toDouble();
  if (v is String) {
    final d = double.tryParse(v.trim());
    return (d != null && d > 0) ? d : null;
  }
  return null;
}
