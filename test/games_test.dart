import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cosmicguide/models/game.dart';
import 'package:cosmicguide/screens/games/games_hub_screen.dart';
import 'package:cosmicguide/screens/games/graha_quest_screen.dart';
import 'package:cosmicguide/screens/games/nakshatra_cards_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/widgets/game_widgets.dart';
import 'package:cosmicguide/widgets/play_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake contract payloads (public: also imported by games_board_circle_test.dart)
// ---------------------------------------------------------------------------

const gameLongText = 'This is a deliberately long sentence that keeps going so that narrow screens and large '
    'text sizes are exercised properly without any overflow appearing anywhere at all.';

const gameToday = '2026-10-11';

const _planetOrder = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];

const nakshatraNames = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra', 'Punarvasu', 'Pushya', 'Ashlesha', //
  'Magha', 'Purva Phalguni', 'Uttara Phalguni', 'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha', //
  'Mula', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha', 'Purva Bhadrapada',
  'Uttara Bhadrapada', 'Revati',
];
const _nakRulers = ['Ketu', 'Venus', 'Sun', 'Moon', 'Mars', 'Rahu', 'Jupiter', 'Saturn', 'Mercury'];
const _nakSymbols = ['🐎', '🔺', '🔥', '🛞', '🦌', '💧', '🏹', '🌸', '🐍'];

String nakId(int index) => 'nak:${nakshatraNames[index].toLowerCase().replaceAll(' ', '_')}';

Map<String, dynamic> playerPayload({
  int level = 3,
  int xpIntoLevel = 120,
  int streak = 4,
  bool streakAliveToday = false,
  String title = 'Star Seeker',
}) {
  // level n needs 100*n xp to reach n+1
  var base = 0;
  for (var l = 1; l < level; l++) {
    base += 100 * l;
  }
  return {
    'level': level,
    'xp': base + xpIntoLevel,
    'xpIntoLevel': xpIntoLevel,
    'xpForNext': 100 * level,
    'title': title,
    'streak': streak,
    'bestStreak': streak + 5,
    'streakAliveToday': streakAliveToday,
  };
}

List<Map<String, dynamic>> planetsPayload() => [
      for (var i = 0; i < _planetOrder.length; i++)
        {
          'planet': _planetOrder[i],
          'level': 1 + i % 4,
          'power': 20 + i * 9,
          'natal': i == 4
              ? 'Exalted in Cancer — a natural gift. $gameLongText'
              : '${_planetOrder[i]} in your ${i + 1}th house — steady and reliable',
          'status': ['strong', 'steady', 'needs_care'][i % 3],
          'role': ['Your inner coach', 'Your heart keeper', 'Your brave engine'][i % 3],
          'xp': i * 15,
        },
    ];

Map<String, dynamic> missionPayload(int i, {bool done = false}) => {
      'id': 'm$gameToday-${i + 1}',
      'planet': ['Saturn', 'Moon', 'Mars'][i % 3],
      'title': [
        'Finish one thing you have been putting off for days',
        'Call someone who would love to hear your voice',
        'Move your body for ten minutes',
      ][i % 3],
      'why': [
        'Saturn is slow-walking your work house today, so finishing beats starting. $gameLongText',
        'The Moon is in your friendly star today — warm words land well.',
        'Mars is fired up in your 6th — burn it off happily.',
      ][i % 3],
      'xp': [40, 30, 20][i % 3],
      'done': done,
      'category': ['action', 'kindness', 'body'][i % 3],
    };

Map<String, dynamic> missionsPayload({int done = 0, bool bonusRollGranted = false}) => {
      'date': gameToday,
      'items': [for (var i = 0; i < 3; i++) missionPayload(i, done: i < done)],
      'completedCount': done,
      'allDone': done >= 3,
      'allDoneBonusXp': 50,
      'bonusRollGranted': bonusRollGranted || done >= 3,
    };

Map<String, dynamic> nakCardPayload(int index, {bool collected = false, bool birthStar = false}) => {
      'id': nakId(index),
      'kind': 'nakshatra',
      'name': nakshatraNames[index],
      'symbol': _nakSymbols[index % 9],
      'ruler': _nakRulers[index % 9],
      'deity': index == 9 ? 'The Pitris (ancestors)' : 'Deity ${index + 1}',
      'power': index == 9 ? 'The Throne — born to lead' : 'The ${nakshatraNames[index]} spark — quick and bright',
      'keywords': ['Leadership', 'Legacy', 'Pride'],
      'rarity': 'common',
      'isBirthStar': birthStar,
      'collected': collected,
      'collectedOn': collected ? '2026-09-${(index + 1).toString().padLeft(2, '0')}' : null,
    };

Map<String, dynamic> rareCardPayload(String id, String name, {bool collected = false, String rarity = 'rare'}) => {
      'id': id,
      'kind': 'rare',
      'name': name,
      'symbol': '🌟',
      'ruler': null,
      'deity': null,
      'power': 'A once-in-a-while sky moment, saved forever',
      'keywords': ['Rare', 'Lucky'],
      'rarity': rarity,
      'isBirthStar': id == 'rare:birth_star',
      'collected': collected,
      'collectedOn': collected ? '2026-09-20' : null,
    };

Map<String, dynamic> luckPayload({bool favorable = true}) => {
      'tara': favorable ? 'Mitra' : 'Vipat',
      'favorable': favorable,
      'chandrashtama': false,
      'line': favorable ? 'Mitra Tara — the sky is on your side' : 'Vipat Tara — go gently, small steps win today',
    };

/// GET /api/game/state
Map<String, dynamic> gameStatePayload({
  int missionsDone = 0,
  bool canCollect = true,
  int collectedCount = 9,
  int rollsLeft = 2,
  int position = 14,
  int memberCount = 2,
  bool guest = false,
}) =>
    {
      'player': playerPayload(streakAliveToday: missionsDone > 0),
      'planets': planetsPayload(),
      'missions': missionsPayload(done: missionsDone),
      'card': {
        'today': nakCardPayload(9, collected: !canCollect),
        'canCollect': canCollect,
        'collectedCount': collectedCount,
        'total': 27,
        'rareCount': 1,
      },
      'moksha': {'position': position, 'rollsLeft': rollsLeft, 'wins': 1},
      'circle': {'memberCount': memberCount, 'inviteCode': guest ? null : 'STAR42'},
      'luck': luckPayload(),
    };

/// GET /api/game/cards. The first [collected] nakshatra cards are owned; today's
/// card is Magha (index 9); with [withExtra] a rare birth-star card is on offer.
Map<String, dynamic> cardsPayload({
  int collected = 9,
  bool canCollect = true,
  bool withExtra = true,
  bool row1Claimed = false,
}) {
  bool has(int i) => i < collected || (!canCollect && i == 9);
  final cards = [for (var i = 0; i < 27; i++) nakCardPayload(i, collected: has(i), birthStar: i == 21)];
  final missing = [for (var i = 0; i < 27; i++) if (!has(i) && i != 9) i];
  Map<String, dynamic> row(String id, String name, int from, Map<String, dynamic> reward, {bool claimed = false}) {
    final ids = [for (var i = from; i < from + 9; i++) nakId(i)];
    final got = [for (var i = from; i < from + 9; i++) if (has(i)) i].length;
    return {
      'id': id,
      'name': name,
      'cardIds': ids,
      'collected': got,
      'complete': got == 9,
      'reward': reward,
      'claimed': claimed,
    };
  }

  return {
    'today': {
      'card': cards[9],
      'canCollect': canCollect,
      'extra': [
        if (withExtra) rareCardPayload('rare:birth_star', 'Birth Star Return', collected: !canCollect),
      ],
    },
    'cards': cards,
    'rare': [
      rareCardPayload('rare:lunar_eclipse_2026-03-03', 'Blood Moon Eclipse', collected: true, rarity: 'legendary'),
      rareCardPayload('rare:birth_star', 'Birth Star Return', collected: !canCollect),
      rareCardPayload('rare:moksha', 'Moksha'),
    ],
    'collectedCount': cards.where((c) => c['collected'] == true).length,
    'total': 27,
    'sets': [
      row('row1', "Ashwini's Row (1–9)", 0, {'type': 'wallet', 'amount': 51, 'label': '₹51 wallet credit'},
          claimed: row1Claimed),
      row('row2', "Magha's Row (10–18)", 9, {'type': 'xp', 'amount': 150, 'label': '+150 XP'}),
      row('row3', "Mula's Row (19–27)", 18, {'type': 'xp', 'amount': 200, 'label': '+200 XP'}),
    ],
    'upcoming': [
      for (var k = 0; k < missing.length && k < 5; k++)
        {'card': cards[missing[k]], 'date': '2026-10-${12 + k * 2}'},
    ],
  };
}

Map<String, dynamic> mokshaPlayerPayload(String key, String name,
        {String? relationship, int position = 14, int wins = 0, int rollsLeft = 2, bool favorable = true}) =>
    {
      'profileKey': key,
      'name': name,
      'relationship': relationship,
      'position': position,
      'wins': wins,
      'rollsLeft': rollsLeft,
      'isYou': key == 'self',
      'luck': luckPayload(favorable: favorable),
    };

List<Map<String, dynamic>> mokshaPlayersPayload({int position = 14, int rollsLeft = 2}) => [
      mokshaPlayerPayload('self', 'Ravindra Nath Jha', position: position, wins: 1, rollsLeft: rollsLeft),
      mokshaPlayerPayload('fam:7', 'Sunita Devi Jha', relationship: 'Mother', position: 37, rollsLeft: 1),
      mokshaPlayerPayload('fam:9', 'Aarav', relationship: 'Son', position: 3, rollsLeft: 0, favorable: false),
    ];

/// GET /api/game/moksha
Map<String, dynamic> mokshaPayload({int position = 14, int rollsLeft = 2}) => {
      'board': {
        'size': 100,
        'ladders': [
          {'from': 4, 'to': 25, 'name': 'Generosity', 'line': 'Giving lifts you higher. $gameLongText'},
          {'from': 16, 'to': 44, 'name': 'Truth', 'line': 'Honest words open doors.'},
          {'from': 21, 'to': 60, 'name': 'Devotion', 'line': 'A steady heart climbs fast.'},
          {'from': 51, 'to': 72, 'name': 'Patience', 'line': 'Waiting well is a superpower.'},
          {'from': 63, 'to': 95, 'name': 'Compassion', 'line': 'Kindness is the shortcut.'},
        ],
        'snakes': [
          {'from': 29, 'to': 8, 'name': 'Anger', 'line': 'A hot moment, a long slide. Breathe.'},
          {'from': 47, 'to': 19, 'name': 'Greed', 'line': 'Wanting more cost a little.'},
          {'from': 76, 'to': 41, 'name': 'Pride', 'line': 'Pride goes before the slide.'},
          {'from': 99, 'to': 62, 'name': 'Ego', 'line': 'So close! Humility gets you home.'},
        ],
      },
      'players': mokshaPlayersPayload(position: position, rollsLeft: rollsLeft),
      'lastMoves': [
        {'profileKey': 'self', 'name': 'Ravindra Nath Jha', 'dice': 4, 'from': 10, 'to': 14, 'event': null, 'at': '2026-10-10T08:12:00.000Z'},
        {'profileKey': 'fam:7', 'name': 'Sunita Devi Jha', 'dice': 2, 'from': 14, 'to': 44, 'event': 'Truth', 'at': '2026-10-10T07:02:00.000Z'},
      ],
    };

/// POST /api/game/moksha/roll
Map<String, dynamic> mokshaRollPayload({
  String profileKey = 'self',
  int dice = 2,
  int from = 14,
  int? landed,
  int? to,
  Map<String, dynamic>? event,
  bool overshoot = false,
  bool won = false,
  Map<String, dynamic>? reward,
  int rollsLeft = 1,
  List<Map<String, dynamic>>? players,
}) {
  final l = landed ?? (overshoot ? from : from + dice);
  final t = to ?? l;
  return {
    'profileKey': profileKey,
    'dice': dice,
    'from': from,
    'landed': l,
    'to': t,
    'event': event,
    'overshoot': overshoot,
    'won': won,
    'reward': reward,
    'rollsLeft': rollsLeft,
    'players': players ??
        [
          for (final p in mokshaPlayersPayload())
            p['profileKey'] == profileKey ? {...p, 'position': t, 'rollsLeft': rollsLeft} : p,
        ],
    'player': playerPayload(streakAliveToday: true),
  };
}

Map<String, dynamic> circleMemberPayload(String id, String name,
        {String? relationship, bool hasChart = true, double score = 28.5, String label = 'Strong', int todayScore = 74}) =>
    {
      'id': id,
      'kind': id.startsWith('fam:') ? 'family' : 'friend',
      'name': name,
      'relationship': relationship,
      'hasChart': hasChart,
      'moonSign': hasChart ? 'Cancer' : null,
      'nakshatra': hasChart ? 'Pushya' : null,
      'compatibility': hasChart
          ? {'score': score, 'max': 36, 'label': label, 'strongest': 'Friendship (Graha Maitri)', 'weakest': 'Temperament (Gana)'}
          : null,
      'todayScore': hasChart ? todayScore : null,
      'mood': hasChart ? 'good' : null,
    };

/// GET /api/game/circle
Map<String, dynamic> circlePayload({bool withFriends = true}) {
  final members = [
    circleMemberPayload('fam:7', 'Sunita Devi Jha', relationship: 'Mother', score: 31, label: 'Soul-level', todayScore: 86),
    circleMemberPayload('fam:9', 'Aarav', relationship: 'Son', score: 18.5, label: 'Spicy', todayScore: 52),
    if (withFriends) circleMemberPayload('friend:42', 'Priya Sharma', score: 24, label: 'Easy', todayScore: 67),
    if (withFriends) circleMemberPayload('friend:43', 'Chartless Charlie', hasChart: false),
  ];
  final unlockedCount = members.length;
  Map<String, dynamic> ranking(String id, String title, String emoji, int need) => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'unlocked': unlockedCount >= need,
        'needMembers': need,
        'entries': unlockedCount >= need
            ? [
                for (final m in members.where((m) => m['hasChart'] == true).take(3))
                  {'memberId': m['id'], 'name': m['name'], 'value': '31/36', 'note': 'You two just get each other. $gameLongText'},
              ]
            : [],
      };

  return {
    'inviteCode': 'STAR42',
    'shareText': 'Join my Cosmic Circle on CosmicGuide! Use my code STAR42 and see how our stars match.',
    'members': members,
    'you': {'name': 'Ravindra Nath Jha', 'moonSign': 'Capricorn', 'nakshatra': 'Shravana', 'todayScore': 68, 'mood': 'good'},
    'rankings': [
      ranking('cosmicTwin', 'Cosmic Twin', '👯', 1),
      ranking('luckiestToday', 'Luckiest Today', '🍀', 2),
      ranking('travelBuddy', 'Travel Buddy', '🧳', 3),
      ranking('businessPartner', 'Business Partner', '💼', 4),
      ranking('funPartner', 'Fun Partner', '🎉', 5),
      ranking('calmingPresence', 'Calming Presence', '🧘', 6),
    ],
  };
}

// ---------------------------------------------------------------------------
// Fake backend (stateful, contract-shaped)
// ---------------------------------------------------------------------------

/// A [BackendService] whose game methods answer from in-memory contract payloads.
///
/// * Set a payload to null (with [errorCode]/[errorMessage]) to simulate a failed load.
/// * `fail*` flags make the matching mutation return null.
/// * `*Response` overrides replace the computed mutation result.
/// * Counters / request lists record every call.
class FakeGameBackend extends BackendService {
  Map<String, dynamic>? state = gameStatePayload();
  Map<String, dynamic>? cards = cardsPayload();
  Map<String, dynamic>? moksha = mokshaPayload();
  Map<String, dynamic>? circle = circlePayload();

  String? errorCode;
  String? errorMessage;

  Map<String, dynamic>? kundli = {
    'ascendant': 'Leo',
    'moonSign': 'Capricorn',
    'birthDetails': {'fullName': 'Ravindra Nath Jha', 'dateOfBirth': '1990-01-01', 'timeOfBirth': '10:00'},
  };

  // Gates: when set, the call waits for the completer (loading-state tests).
  Completer<void>? stateGate;
  Completer<void>? completeGate;
  Completer<void>? collectGate;
  Completer<void>? rollGate;

  // Failure switches for mutations.
  bool failComplete = false;
  bool failCollect = false;
  bool failClaim = false;
  bool failRoll = false;
  bool failJoin = false;
  bool failRemove = false;

  // Optional canned mutation responses.
  Map<String, dynamic>? completeResponse;
  Map<String, dynamic>? collectResponse;
  Map<String, dynamic>? claimResponse;
  Map<String, dynamic>? rollResponse;
  Map<String, dynamic>? joinResponse;

  /// Forces `leveledUp` / `planetLeveledUp` on the next computed mission result.
  bool nextLeveledUp = false;
  String? nextPlanetLeveledUp;

  double fakeWallet = 100;

  // Call records.
  int stateCalls = 0;
  int forcedStateCalls = 0;
  int cardsCalls = 0;
  int collectCalls = 0;
  int mokshaCalls = 0;
  int circleCalls = 0;
  final List<String> completeCalls = [];
  final List<String> claimCalls = [];
  final List<String> rollCalls = [];
  final List<String> joinCalls = [];
  final List<int> removeCalls = [];

  @override
  Map<String, dynamic>? get kundliData => kundli;
  @override
  bool get hasBirthDetails => kundli != null;
  @override
  String? get lastError => errorMessage;
  @override
  String? get lastErrorCode => errorCode;
  @override
  double get walletBalance => fakeWallet;

  void fail(String message, {String? code}) {
    errorMessage = message;
    errorCode = code;
  }

  void _ok() {
    errorMessage = null;
    errorCode = null;
  }

  Map<String, dynamic>? _fail(String message, [String? code]) {
    errorMessage ??= message;
    errorCode ??= code;
    return null;
  }

  static Map<String, dynamic> _copy(Map v) => Map<String, dynamic>.from(v);

  void _addXp(int gain) {
    final s = state;
    if (s == null) return;
    final p = GamePlayer.fromJson(s['player']).withXpGain(gain, streakAlive: false);
    s['player'] = {..._copy(s['player'] as Map), 'level': p.level, 'xp': p.xp, 'xpIntoLevel': p.xpIntoLevel, 'xpForNext': p.xpForNext};
  }

  @override
  Future<Map<String, dynamic>?> fetchGameState({bool forceRefresh = false}) async {
    stateCalls++;
    if (forceRefresh) forcedStateCalls++;
    if (stateGate != null) await stateGate!.future;
    if (state == null) return _fail('Could not load the game. Please try again.');
    _ok();
    return state;
  }

  @override
  Future<Map<String, dynamic>?> completeMission(String missionId) async {
    completeCalls.add(missionId);
    if (completeGate != null) await completeGate!.future;
    if (failComplete || state == null) return _fail('Could not complete the mission. Please try again.');
    _ok();
    if (completeResponse != null) return completeResponse;
    final s = state!;
    final missions = _copy(s['missions'] as Map);
    final items = [for (final m in missions['items'] as List) _copy(m as Map)];
    final idx = items.indexWhere((m) => m['id'] == missionId);
    if (idx < 0) return _fail('Mission not found', 'MISSION_NOT_FOUND');
    final already = items[idx]['done'] == true;
    items[idx]['done'] = true;
    final count = items.where((m) => m['done'] == true).length;
    final allDone = count == items.length;
    final gained = already ? 0 : items[idx]['xp'] as int;
    final bonus = (!already && allDone) ? missions['allDoneBonusXp'] as int : 0;
    missions
      ..['items'] = items
      ..['completedCount'] = count
      ..['allDone'] = allDone
      ..['bonusRollGranted'] = allDone;
    s['missions'] = missions;
    final before = GamePlayer.fromJson(s['player']);
    _addXp(gained + bonus);
    final player = _copy(s['player'] as Map);
    if (!already && before.streakAliveToday == false) {
      player['streak'] = before.streak + 1;
      player['streakAliveToday'] = true;
    }
    s['player'] = player;
    if (!already && allDone) {
      s['moksha'] = {..._copy(s['moksha'] as Map), 'rollsLeft': ((s['moksha'] as Map)['rollsLeft'] as int) + 1};
    }
    final leveled = nextLeveledUp || GamePlayer.fromJson(player).level > before.level;
    final planetUp = nextPlanetLeveledUp;
    nextLeveledUp = false;
    nextPlanetLeveledUp = null;
    return {
      'mission': items[idx],
      'xpGained': gained,
      'bonusXp': bonus,
      'leveledUp': leveled,
      'planetLeveledUp': planetUp,
      'bonusRollGranted': !already && allDone,
      'player': player,
      'planets': s['planets'],
      'missions': missions,
    };
  }

  @override
  Future<Map<String, dynamic>?> fetchGameCards() async {
    cardsCalls++;
    if (cards == null) return _fail('Could not load your cards. Please try again.');
    _ok();
    return cards;
  }

  @override
  Future<Map<String, dynamic>?> collectTodayCards() async {
    collectCalls++;
    if (collectGate != null) await collectGate!.future;
    if (failCollect || cards == null) return _fail('Could not collect the card. Please try again.');
    _ok();
    if (collectResponse != null) return collectResponse;
    final c = cards!;
    final today = _copy(c['today'] as Map);
    final can = today['canCollect'] == true;
    final got = <Map<String, dynamic>>[];
    if (can) {
      final main = {..._copy(today['card'] as Map), 'collected': true, 'collectedOn': gameToday};
      final extra = [
        for (final e in today['extra'] as List) {..._copy(e as Map), 'collected': true, 'collectedOn': gameToday},
      ];
      got
        ..add(main)
        ..addAll(extra);
      final ids = got.map((g) => g['id']).toSet();
      Map<String, dynamic> mark(dynamic x) {
        final m = _copy(x as Map);
        return ids.contains(m['id']) ? {...m, 'collected': true, 'collectedOn': gameToday} : m;
      }

      c['today'] = {'card': main, 'canCollect': false, 'extra': extra};
      c['cards'] = [for (final x in c['cards'] as List) mark(x)];
      c['rare'] = [for (final x in c['rare'] as List) mark(x)];
      c['collectedCount'] = (c['cards'] as List).where((x) => (x as Map)['collected'] == true).length;
      c['sets'] = [
        for (final raw in c['sets'] as List)
          () {
            final set = _copy(raw as Map);
            final n = (set['cardIds'] as List)
                .where((id) => (c['cards'] as List).any((x) => (x as Map)['id'] == id && x['collected'] == true))
                .length;
            return {...set, 'collected': n, 'complete': n == (set['cardIds'] as List).length};
          }(),
      ];
      c['upcoming'] = [
        for (final u in c['upcoming'] as List)
          if (!ids.contains(((u as Map)['card'] as Map)['id'])) u,
      ];
      final s = state;
      if (s != null) {
        s['card'] = {
          ..._copy(s['card'] as Map),
          'today': main,
          'canCollect': false,
          'collectedCount': c['collectedCount'],
        };
      }
    }
    final xp = got.fold<int>(0, (a, g) => a + (g['kind'] == 'rare' ? 50 : 25));
    _addXp(xp);
    return {
      'collected': got,
      'xpGained': xp,
      'completedSets': <String>[],
      'player': state?['player'] ?? playerPayload(),
    };
  }

  @override
  Future<Map<String, dynamic>?> claimCardSet(String setId) async {
    claimCalls.add(setId);
    if (failClaim || cards == null) return _fail('Could not claim the reward. Please try again.');
    if (claimResponse != null) {
      _ok();
      return claimResponse;
    }
    final c = cards!;
    final sets = [for (final s in c['sets'] as List) _copy(s as Map)];
    final idx = sets.indexWhere((s) => s['id'] == setId);
    if (idx < 0 || sets[idx]['complete'] != true) {
      errorMessage = 'Collect every card in this row first.';
      errorCode = 'SET_INCOMPLETE';
      return null;
    }
    if (sets[idx]['claimed'] == true) {
      errorMessage = 'You already claimed this reward.';
      errorCode = 'ALREADY_CLAIMED';
      return null;
    }
    _ok();
    sets[idx]['claimed'] = true;
    c['sets'] = sets;
    final reward = _copy(sets[idx]['reward'] as Map);
    final isWallet = reward['type'] == 'wallet';
    if (isWallet) {
      fakeWallet += (reward['amount'] as num).toDouble();
    } else {
      _addXp(reward['amount'] as int);
    }
    return {
      'reward': reward,
      'walletBalance': isWallet ? fakeWallet : null,
      'player': state?['player'] ?? playerPayload(),
    };
  }

  @override
  Future<Map<String, dynamic>?> fetchMokshaBoard() async {
    mokshaCalls++;
    if (moksha == null) return _fail('Could not load the board. Please try again.');
    _ok();
    return moksha;
  }

  @override
  Future<Map<String, dynamic>?> rollMokshaDice({String profileKey = 'self'}) async {
    rollCalls.add(profileKey);
    if (rollGate != null) await rollGate!.future;
    if (failRoll || moksha == null) return _fail('Could not roll the dice. Please try again.');
    _ok();
    final m = moksha!;
    final players = [for (final p in m['players'] as List) _copy(p as Map)];
    final idx = players.indexWhere((p) => p['profileKey'] == profileKey);
    Map<String, dynamic> result;
    if (rollResponse != null) {
      result = rollResponse!;
    } else {
      if (idx < 0) {
        errorMessage = 'That player is not on this board.';
        errorCode = 'PLAYER_NOT_FOUND';
        return null;
      }
      final left = players[idx]['rollsLeft'] as int;
      if (left <= 0) {
        errorMessage = 'No rolls left today. Finish your 3 missions for a bonus roll!';
        errorCode = 'NO_ROLLS_LEFT';
        return null;
      }
      final from = players[idx]['position'] as int;
      players[idx]
        ..['position'] = from + 2 > 100 ? from : from + 2
        ..['rollsLeft'] = left - 1;
      result = mokshaRollPayload(
        profileKey: profileKey,
        dice: 2,
        from: from,
        overshoot: from + 2 > 100,
        rollsLeft: left - 1,
        players: players,
      );
    }
    final after = result['players'];
    if (after is List && after.isNotEmpty) m['players'] = after;
    return result;
  }

  @override
  Future<Map<String, dynamic>?> fetchCircle() async {
    circleCalls++;
    if (circle == null) return _fail('Could not load your circle. Please try again.');
    _ok();
    return circle;
  }

  @override
  Future<Map<String, dynamic>?> joinCircle(String code) async {
    joinCalls.add(code);
    if (failJoin) return _fail('That code does not match anyone. Check it and try again.', 'INVALID_CODE');
    _ok();
    if (joinResponse != null) return joinResponse;
    final c = circle ??= circlePayload(withFriends: false);
    final member = circleMemberPayload('friend:77', 'Meera Iyer', score: 33, label: 'Soul-level', todayScore: 91);
    c['members'] = [...c['members'] as List, member];
    return {'member': member, 'circle': c};
  }

  @override
  Future<Map<String, dynamic>?> removeCircleFriend(int userId) async {
    removeCalls.add(userId);
    if (failRemove || circle == null) return _fail('Could not remove this friend. Please try again.');
    _ok();
    final c = circle!;
    c['members'] = [
      for (final m in c['members'] as List)
        if ((m as Map)['id'] != 'friend:$userId') m,
    ];
    return {'success': true, 'circle': c};
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps [screen] at a small phone size with large text. Game routes that are
/// not under test resolve to `ROUTE:<name>` marker pages.
Future<void> pumpGameScreen(
  WidgetTester tester,
  Widget screen,
  BackendService fake, {
  Size size = const Size(320, 640),
  double textScale = 1.3,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Widget marker(String name) => Scaffold(appBar: AppBar(), body: Text('ROUTE:$name'));
  await tester.pumpWidget(
    ChangeNotifierProvider<BackendService>.value(
      value: fake,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: disableAnimations),
          child: child!,
        ),
        routes: {
          for (final r in const [
            '/birth-details',
            '/login',
            '/wallet',
            '/games',
            '/games/quest',
            '/games/cards',
            '/games/moksha',
            '/games/circle',
          ])
            r: (_) => marker(r),
        },
        home: screen,
      ),
    ),
  );
  await tester.pump();
  if (settle) await settleGame(tester);
}

/// Like pumpAndSettle, but tolerant of the endless idle loops (shimmer, pulse)
/// the game screens run: advances time in steps instead of waiting for quiet.
Future<void> settleGame(WidgetTester tester, [Duration total = const Duration(seconds: 4)]) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<void> scrollGameThrough(WidgetTester tester, {int steps = 30}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < steps; i++) {
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settleGame(tester, const Duration(seconds: 1));
}

/// Scrolls the screen's main (lazy) list until [f] is built and fully on screen.
Future<void> reveal(WidgetTester tester, Finder f, {double delta = 150}) async {
  await tester.scrollUntilVisible(f, delta, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(f.first);
  await settleGame(tester, const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Game models', () {
    test('state payload parses fully', () {
      final s = GameState.fromJson(gameStatePayload());
      expect(s.player.level, 3);
      expect(s.player.xpForNext, 300);
      expect(s.player.progress, closeTo(0.4, 0.001));
      expect(s.planets, hasLength(9));
      expect(s.planets[2].needsCare, isTrue);
      expect(s.missions.items, hasLength(3));
      expect(s.missions.xpAvailable, 90);
      expect(s.missions.date, DateTime(2026, 10, 11));
      expect(s.card.today.name, 'Magha');
      expect(s.card.canCollect, isTrue);
      expect(s.moksha.position, 14);
      expect(s.circle.inviteCode, 'STAR42');
      expect(s.luck.favorable, isTrue);
    });

    test('messy JSON: strings for numbers, nulls, junk and missing fields', () {
      final s = GameState.fromJson({
        'player': {'level': '4', 'xp': '710.4', 'xpIntoLevel': null, 'xpForNext': 0, 'streak': '6', 'streakAliveToday': 'yes'},
        'planets': [
          {'planet': 'saturn', 'level': '99', 'power': 250, 'status': 'Needs Care'},
          {'planet': 'Moon', 'power': '-4', 'status': null},
          'junk',
          null,
          {'level': 3},
        ],
        'missions': {
          'date': '2026-10-11T00:00:00.000Z',
          'items': [
            {'id': 7, 'xp': '30', 'done': 1, 'category': 'DANCE'},
            {'title': 'no id'},
            42,
          ],
        },
        'card': {'today': 'nope', 'canCollect': 'true', 'total': '0'},
        'moksha': {'position': '140', 'rollsLeft': -2},
        'circle': null,
        'luck': 'lucky',
      });
      expect(s.player.level, 4);
      expect(s.player.xp, 710);
      expect(s.player.xpForNext, 400);
      expect(s.player.streak, 6);
      expect(s.player.bestStreak, 6);
      expect(s.player.streakAliveToday, isTrue);
      expect(s.planets, hasLength(2));
      expect(s.planets[0].planet, 'Saturn');
      expect(s.planets[0].level, 10);
      expect(s.planets[0].power, 100);
      expect(s.planets[0].needsCare, isTrue);
      expect(s.planets[1].power, 0);
      expect(s.planets[1].status, PlanetStatus.steady);
      expect(s.missions.items, hasLength(1));
      expect(s.missions.items.first.id, '7');
      expect(s.missions.items.first.done, isTrue);
      expect(s.missions.items.first.category, 'action');
      expect(s.missions.completedCount, 1);
      expect(s.missions.allDone, isTrue);
      expect(s.card.today.isEmpty, isTrue);
      expect(s.card.canCollect, isTrue);
      expect(s.card.total, 27);
      expect(s.moksha.position, 100);
      expect(s.moksha.rollsLeft, 0);
      expect(s.circle.inviteCode, isNull);
      expect(s.luck.isEmpty, isTrue);

      // Nothing at all still gives usable objects.
      expect(GameState.fromJson(null).player.level, 1);
      expect(CardAlbum.fromJson('x').total, 27);
      expect(MokshaBoard.fromJson(null).size, 100);
      expect(CosmicCircle.fromJson(const []).members, isEmpty);
      expect(MissionCompleteResult.fromJson(null).mission.id, '');
      expect(MokshaRollResult.fromJson({'dice': '9', 'from': 'x'}).dice, 6);
    });

    test('cards, board and circle payloads parse', () {
      final a = CardAlbum.fromJson(cardsPayload());
      expect(a.cards, hasLength(27));
      expect(a.collectedCount, 9);
      expect(a.today.card.id, 'nak:magha');
      expect(a.today.card.ruler, 'Ketu');
      expect(a.today.extra.single.isRare, isTrue);
      expect(a.rare, hasLength(3));
      expect(a.rare.first.rarity, CardRarity.legendary);
      expect(a.sets, hasLength(3));
      expect(a.sets.first.canClaim, isTrue);
      expect(a.sets.first.reward.isWallet, isTrue);
      expect(a.sets[1].progress, 0);
      expect(a.upcoming, hasLength(5));
      expect(a.arrivalOf(a.upcoming[1].card.id), DateTime(2026, 10, 14));
      expect(a.cards[21].isBirthStar, isTrue);

      final claim = ClaimResult.fromJson({'reward': {'type': 'wallet', 'amount': '51'}, 'walletBalance': '151.5', 'player': null});
      expect(claim.walletBalance, 151.5);
      expect(claim.reward.label, contains('51'));
      expect(ClaimResult.fromJson({'walletBalance': null}).walletBalance, isNull);

      final b = MokshaBoard.fromJson(mokshaPayload());
      expect(b.ladders, hasLength(5));
      expect(b.snakes.first.isLadder, isFalse);
      expect(b.players, hasLength(3));
      expect(b.you!.profileKey, 'self');
      expect(b.playerByKey('fam:7')!.relationship, 'Mother');
      expect(b.lastMoves.last.event, 'Truth');
      final roll = MokshaRollResult.fromJson(mokshaRollPayload(
        dice: 2,
        from: 14,
        to: 44,
        event: {'type': 'ladder', 'name': 'Truth', 'line': 'Up you go'},
        won: false,
        reward: {'xp': 15, 'card': null},
      ));
      expect(roll.landed, 16);
      expect(roll.to, 44);
      expect(roll.event!.isLadder, isTrue);
      expect(roll.reward!.xp, 15);
      expect(roll.reward!.card, isNull);

      final c = CosmicCircle.fromJson(circlePayload());
      expect(c.members, hasLength(4));
      expect(c.friends, hasLength(2));
      expect(c.members.first.compatibility!.display, '31/36');
      expect(c.members[1].compatibility!.display, '18.5/36');
      expect(c.friends.first.friendUserId, 42);
      expect(c.members.last.compatibility, isNull);
      expect(c.rankings, hasLength(6));
      expect(c.rankings.last.unlocked, isFalse);
      expect(c.rankings.last.entries, isEmpty);
      expect(c.you.moonSign, 'Capricorn');
    });

    test('optional backend extras parse', () {
      final p = GamePlanet.fromJson({'planet': 'Venus', 'emoji': '💖', 'title': 'The Charmer', 'personality': 'Loves beauty.'});
      expect(p.personality, 'Loves beauty.');
      expect(p.emoji, '💖');
      final c = CosmicCard.fromJson({'id': 'rare:lunar_eclipse_2026-03-03', 'how': 'Open the app on eclipse day', 'date': '2026-03-03'});
      expect(c.isRare, isTrue);
      expect(c.how, contains('eclipse'));
      expect(c.date, DateTime(2026, 3, 3));
      expect(CosmicCard.fromJson({'id': 'nak:magha', 'number': '10'}).number, 10);
      expect(CollectResult.fromJson({'leveledUp': true}).leveledUp, isTrue);
      expect(MokshaReward.fromJson({'xp': 100, 'wallet': 11})!.wallet, 11);
      expect(MokshaReward.fromJson({'xp': 100})!.wallet, isNull);
      expect(GameMission.fromJson({'id': '2026-10-11_saturn_finish'}).id, '2026-10-11_saturn_finish');
      expect(CosmicCircle.fromJson({'inviteCode': null}).inviteCode, '');
      expect(MokshaMove.fromJson({'event': 'Ladder: Truth'}).event, 'Ladder: Truth');
    });

    test('optimistic helpers', () {
      const p = GamePlayer(level: 1, xp: 90, xpIntoLevel: 90, xpForNext: 100, streak: 2, bestStreak: 2);
      final q = p.withXpGain(40);
      expect(q.level, 2);
      expect(q.xpIntoLevel, 30);
      expect(q.xpForNext, 200);
      expect(q.streak, 3);
      expect(q.streakAliveToday, isTrue);
      final m = MissionsDay.fromJson(missionsPayload(done: 2));
      final all = m.withDone(m.items.last.id, true);
      expect(all.allDone, isTrue);
      expect(all.withDone(m.items.first.id, false).completedCount, 2);
    });
  });

  // -------------------------------------------------------------------------
  group('Games hub', () {
    testWidgets('renders player, luck and four live tiles at 320x640 / 1.3x', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const GamesHubScreen(), fake);

      expect(find.text('Star Seeker'), findsOneWidget);
      expect(find.text('120 / 300 XP'), findsOneWidget);
      expect(find.text('Mitra Tara — the sky is on your side'), findsOneWidget);
      expect(find.text('Graha Quest'), findsOneWidget);
      expect(find.text('0/3 missions'), findsOneWidget);
      expect(find.text('+90 XP waiting'), findsOneWidget);

      await reveal(tester, find.text('Today: Magha'));
      expect(find.text('Tap to collect ✨'), findsOneWidget);
      await reveal(tester, find.text('Square 14'));
      expect(find.text('2 rolls left'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Moksha Patam. Square 14')), findsOneWidget);
      await reveal(tester, find.text('2 in your circle'));
      await scrollGameThrough(tester, steps: 6);
    });

    testWidgets('reduced motion and a wide screen also render', (tester) async {
      final fake = FakeGameBackend()..state = gameStatePayload(missionsDone: 3, canCollect: false, rollsLeft: 0, memberCount: 0);
      await pumpGameScreen(tester, const GamesHubScreen(), fake, size: const Size(900, 700), textScale: 1, disableAnimations: true);
      expect(find.text('All done! 🎉'), findsOneWidget);
      expect(find.text('Collected ✓'), findsOneWidget);
      expect(find.text('0 rolls left'), findsOneWidget);
      expect(find.text('Invite a friend 💌'), findsOneWidget);
    });

    testWidgets('a tile opens its game and the hub refreshes on return', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const GamesHubScreen(), fake);
      await tester.tap(find.text('Graha Quest'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('ROUTE:/games/quest'), findsOneWidget);

      fake.state = gameStatePayload(missionsDone: 2);
      await tester.pageBack();
      await settleGame(tester, const Duration(seconds: 1));
      expect(fake.forcedStateCalls, 1);
      expect(find.text('2/3 missions'), findsOneWidget);
    });

    testWidgets('shows a skeleton while loading', (tester) async {
      final fake = FakeGameBackend()..stateGate = Completer<void>();
      await pumpGameScreen(tester, const GamesHubScreen(), fake, settle: false);
      expect(find.byType(GameSkeleton), findsOneWidget);
      fake.stateGate!.complete();
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.byType(GameSkeleton), findsNothing);
      expect(find.text('Graha Quest'), findsOneWidget);
    });

    testWidgets('NO_KUNDLI shows the create-Kundli CTA', (tester) async {
      final fake = FakeGameBackend()
        ..state = null
        ..fail('Please create your Kundli first.', code: 'NO_KUNDLI');
      await pumpGameScreen(tester, const GamesHubScreen(), fake);
      expect(find.byType(GameNoKundli), findsOneWidget);
      await reveal(tester, find.text('Create my Kundli'));
      await tester.tap(find.text('Create my Kundli'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('ROUTE:/birth-details'), findsOneWidget);
    });

    testWidgets('error state retries', (tester) async {
      final fake = FakeGameBackend()
        ..state = null
        ..fail('The server ran into a problem. Please try again shortly.');
      await pumpGameScreen(tester, const GamesHubScreen(), fake);
      expect(find.byType(GameError), findsOneWidget);
      expect(find.textContaining('server ran into a problem'), findsOneWidget);

      fake
        ..state = gameStatePayload()
        ..errorMessage = null;
      await tester.tap(find.text('Try again'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.byType(GameError), findsNothing);
      expect(find.text('Graha Quest'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Graha Quest', () {
    const first = 'Finish one thing you have been putting off for days';
    const third = 'Move your body for ten minutes';

    testWidgets('renders missions and the planet team at 320x640 / 1.3x', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);
      expect(find.text("Today's missions"), findsOneWidget);
      expect(find.text('0/3'), findsOneWidget);
      expect(find.text(first), findsOneWidget);
      expect(find.textContaining('Do one mission today to keep your 4-day streak'), findsOneWidget);

      await scrollGameThrough(tester, steps: 10);
      expect(find.text('Your team'), findsOneWidget);
      expect(find.byType(PlanetAvatar), findsWidgets);
      expect(find.text('Needs you'), findsWidgets);

      // Planets that need care lead the team; open the first one.
      await reveal(tester, find.text('Mars'));
      await tester.tap(find.text('Mars'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('In your chart'), findsOneWidget);
      expect(find.text('It needs you — power it up'), findsOneWidget);
    });

    testWidgets('planet sheet with long natal text fits', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);
      // Jupiter sits off to the right inside the horizontal team strip.
      await reveal(tester, find.text('Jupiter'));
      await tester.tap(find.text('Jupiter'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.textContaining('Exalted in Cancer'), findsOneWidget);
      expect(find.text('What powers it up'), findsOneWidget);
    });

    testWidgets('completing a mission updates progress and calls the service once', (tester) async {
      final fake = FakeGameBackend()..completeGate = Completer<void>();
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);

      await tester.tap(find.text(first));
      await tester.pump();
      // Optimistic: counted and checked before the server answers.
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('+40 XP earned'), findsOneWidget);
      expect(find.text('160 / 300 XP'), findsOneWidget);

      // Extra taps while in flight (or once done) do nothing.
      await tester.tap(find.text(first));
      await tester.pump();
      fake.completeGate!.complete();
      await settleGame(tester);
      await tester.tap(find.text(first));
      await settleGame(tester, const Duration(milliseconds: 500));

      expect(fake.completeCalls, ['m$gameToday-1']);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('160 / 300 XP'), findsOneWidget);
      expect(find.textContaining('Streak safe for today'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a failed completion rolls back', (tester) async {
      final fake = FakeGameBackend()..failComplete = true;
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);
      await tester.tap(find.text(first));
      await settleGame(tester, const Duration(seconds: 1));
      expect(fake.completeCalls, hasLength(1));
      expect(find.text('0/3'), findsOneWidget);
      expect(find.text('+40 XP'), findsOneWidget);
      expect(find.text('120 / 300 XP'), findsOneWidget);
      expect(find.text('Could not complete the mission. Please try again.'), findsOneWidget);
    });

    testWidgets('finishing all three celebrates and offers the bonus roll', (tester) async {
      final fake = FakeGameBackend()..state = gameStatePayload(missionsDone: 2);
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);
      expect(find.text('2/3'), findsOneWidget);

      await reveal(tester, find.text(third));
      await tester.tap(find.text(third));
      await settleGame(tester);

      expect(find.text('All 3 missions done!'), findsOneWidget);
      expect(find.textContaining('Bonus roll unlocked in Moksha Patam'), findsOneWidget);
      expect(find.textContaining('+50 bonus XP'), findsOneWidget);
      expect(find.text('+20 XP earned'), findsOneWidget);

      await tester.tap(find.text('Roll the dice 🎲'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('ROUTE:/games/moksha'), findsOneWidget);
      expect(fake.completeCalls, hasLength(1));
    });

    testWidgets('all-done state on open shows the Moksha Patam shortcut, no dialog', (tester) async {
      final fake = FakeGameBackend()..state = gameStatePayload(missionsDone: 3);
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake, disableAnimations: true);
      expect(find.byType(Dialog), findsNothing);
      await reveal(tester, find.text('Play Moksha Patam'));
      expect(find.text('All done for today! 🎉'), findsOneWidget);
    });

    testWidgets('level-up dialog and planet level-up banner', (tester) async {
      final fake = FakeGameBackend()
        ..nextLeveledUp = true
        ..nextPlanetLeveledUp = 'Saturn';
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);
      await tester.tap(find.text(first));
      await settleGame(tester);
      expect(find.text('Level 3!'), findsOneWidget);
      await tester.tap(find.text('Yay!'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.byType(Dialog), findsNothing);
      expect(find.textContaining('Saturn levelled up'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await settleGame(tester, const Duration(milliseconds: 300));
      expect(find.textContaining('Saturn levelled up'), findsNothing);
    });

    testWidgets('NO_KUNDLI and error/retry states', (tester) async {
      final fake = FakeGameBackend()
        ..state = null
        ..fail('Please create your Kundli first.', code: 'NO_KUNDLI');
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake);
      expect(find.text('Meet your planet team'), findsOneWidget);
      expect(find.text('Create my Kundli'), findsOneWidget);

      final broken = FakeGameBackend()
        ..state = null
        ..fail('Unable to connect to the server. Please check your internet connection.');
      await pumpGameScreen(tester, const GrahaQuestScreen(key: ValueKey('b')), broken);
      expect(find.byType(GameError), findsOneWidget);
      broken
        ..state = gameStatePayload()
        ..errorMessage = null;
      await tester.tap(find.text('Try again'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text("Today's missions"), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Nakshatra Cards', () {
    testWidgets('renders hero, album, rare shelf and sets at 320x640 / 1.3x', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      expect(find.text("Today's card is waiting"), findsOneWidget);
      expect(find.text('Tap to reveal'), findsOneWidget);
      expect(find.text('Magha'), findsNothing); // still face down

      await reveal(tester, find.text('Arriving soon'));
      expect(find.textContaining('Moon arrives 12 Oct'), findsOneWidget);
      await reveal(tester, find.text('Your collection'));
      expect(find.text('9/27'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('not collected. Moon arrives')), findsWidgets);
      await reveal(tester, find.text('Rare cards'));
      await reveal(tester, find.text('Sets & rewards'));
      await reveal(tester, find.text("Ashwini's Row (1–9)"));
      await scrollGameThrough(tester, steps: 12);
    });

    testWidgets('birth-star badge and silhouettes with arrival dates', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake, size: const Size(420, 900), textScale: 1);
      await reveal(tester, find.text('Your birth star'));
      expect(find.textContaining('Shravana'), findsWidgets);
      await reveal(tester, find.text('🌙 12 Oct'));
      await tester.tap(find.text('🌙 12 Oct'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.textContaining('Moon arrives 12 Oct — open the app that day'), findsOneWidget);
    });

    testWidgets('tapping the card flips, collects once and shows it', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);

      await tester.tap(find.text('Tap to reveal'));
      await tester.pump(const Duration(milliseconds: 100)); // mid-flip
      await settleGame(tester);

      expect(fake.collectCalls, 1);
      expect(find.text('Magha is yours!'), findsOneWidget);
      expect(find.text('Magha'), findsOneWidget);
      expect(find.text('The Throne — born to lead'), findsOneWidget);
      expect(find.textContaining('Ruler: ☋ Ketu'), findsOneWidget);
      expect(find.text('Tap to reveal'), findsNothing);

      await reveal(tester, find.text('+75 XP'));
      // The extra rare card is revealed with its own tap.
      await reveal(tester, find.text('Bonus rare card!'));
      expect(find.text('Birth Star Return'), findsNothing);
      await tester.tap(find.text('Bonus rare card!'));
      await settleGame(tester);
      expect(find.text('Birth Star Return'), findsOneWidget);

      await reveal(tester, find.text('10/27'));
      expect(fake.collectCalls, 1);
      expect(fake.cardsCalls, 2); // album refreshed after collecting
    });

    testWidgets('reduced motion skips the flip but still collects', (tester) async {
      final fake = FakeGameBackend()..cards = cardsPayload(withExtra: false);
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake, disableAnimations: true);
      await tester.tap(find.text('Tap to reveal'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('Magha is yours!'), findsOneWidget);
      expect(find.text('Bonus rare card!'), findsNothing);
    });

    testWidgets('a failed collect turns the card face-down again', (tester) async {
      final fake = FakeGameBackend()..failCollect = true;
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      await tester.tap(find.text('Tap to reveal'));
      await settleGame(tester);
      expect(fake.collectCalls, 1);
      expect(find.text('Tap to reveal'), findsOneWidget);
      expect(find.text('Magha is yours!'), findsNothing);
      expect(find.text('Could not collect the card. Please try again.'), findsOneWidget);
    });

    testWidgets('already collected today shows the card face-up', (tester) async {
      final fake = FakeGameBackend()..cards = cardsPayload(canCollect: false);
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      expect(find.text("You already collected today's card"), findsOneWidget);
      expect(find.text('Tap to reveal'), findsNothing);
      expect(find.text('The Throne — born to lead'), findsOneWidget);
      expect(find.textContaining('Come back for'), findsOneWidget);
      expect(fake.collectCalls, 0);
    });

    testWidgets('claiming a completed set pays out and shows the new balance', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      await reveal(tester, find.text('Claim 🎁'));
      expect(find.text('Reward: ₹51 wallet credit'), findsOneWidget);

      await tester.tap(find.text('Claim 🎁'));
      await settleGame(tester, const Duration(seconds: 2));
      expect(fake.claimCalls, ['row1']);
      expect(find.text('₹51 wallet credit claimed! Wallet balance: ₹151'), findsOneWidget);
      expect(find.text('Claimed ✓'), findsOneWidget);
      expect(find.text('Claim 🎁'), findsNothing);
    });

    testWidgets('a failed claim keeps the button and explains', (tester) async {
      final fake = FakeGameBackend()..failClaim = true;
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      await reveal(tester, find.text('Claim 🎁'));
      await tester.tap(find.text('Claim 🎁'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('Could not claim the reward. Please try again.'), findsOneWidget);
      expect(find.text('Claim 🎁'), findsOneWidget);
    });

    testWidgets('tapping a collected card opens its detail sheet', (tester) async {
      final fake = FakeGameBackend();
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      await reveal(tester, find.text('Ashwini'));
      await tester.tap(find.text('Ashwini'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('Collected on 1 Sep 2026'), findsOneWidget);
      expect(find.text('The Ashwini spark — quick and bright'), findsOneWidget);
    });

    testWidgets('NO_KUNDLI and error/retry states', (tester) async {
      final fake = FakeGameBackend()
        ..cards = null
        ..fail('Please create your Kundli first.', code: 'NO_KUNDLI');
      await pumpGameScreen(tester, const NakshatraCardsScreen(), fake);
      expect(find.text('Your card album is waiting'), findsOneWidget);
      await tester.tap(find.text('Create my Kundli'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('ROUTE:/birth-details'), findsOneWidget);
    });

    testWidgets('error state retries', (tester) async {
      final broken = FakeGameBackend()
        ..cards = null
        ..fail('The server is taking too long to respond. Please try again.');
      await pumpGameScreen(tester, const NakshatraCardsScreen(), broken);
      expect(find.byType(GameError), findsOneWidget);
      broken
        ..cards = cardsPayload()
        ..errorMessage = null;
      await tester.tap(find.text('Try again'));
      await settleGame(tester, const Duration(seconds: 1));
      expect(find.text('Tap to reveal'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Home Play strip', () {
    Widget host(int tick) => Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: PlayStrip(refreshTick: tick)));

    testWidgets('shows streak, level, missions, card dot and rolls; opens the hub', (tester) async {
      final fake = FakeGameBackend()..state = gameStatePayload(missionsDone: 1);
      await pumpGameScreen(tester, host(0), fake);
      expect(find.text("Play today's games"), findsOneWidget);
      expect(find.text('🎯 1/3'), findsOneWidget);
      expect(find.text('🃏 Card waiting'), findsOneWidget);
      expect(find.text('🎲 2'), findsOneWidget);
      expect(find.byType(StreakFlame), findsOneWidget);
      expect(find.byType(LevelBadge), findsOneWidget);
      // Home stays calm: nothing on the strip animates forever.
      await tester.pumpAndSettle();

      await tester.tap(find.text("Play today's games"));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE:/games'), findsOneWidget);
    });

    testWidgets('hidden without a Kundli, quiet on errors', (tester) async {
      final none = FakeGameBackend()..kundli = null;
      await pumpGameScreen(tester, host(0), none);
      expect(find.text("Play today's games"), findsNothing);
      expect(none.stateCalls, 0);

      final noChart = FakeGameBackend()
        ..state = null
        ..fail('Please create your Kundli first.', code: 'NO_KUNDLI');
      await pumpGameScreen(tester, const Scaffold(key: ValueKey("n"), body: PlayStrip()), noChart);
      expect(find.text("Play today's games"), findsNothing);

      final broken = FakeGameBackend()
        ..state = null
        ..fail('Unable to connect to the server.');
      await pumpGameScreen(tester, const Scaffold(key: ValueKey("e"), body: PlayStrip()), broken);
      expect(find.text("Play today's games"), findsOneWidget);
      expect(find.text('Missions, cards and a dice roll are waiting'), findsOneWidget);
      expect(find.textContaining('Unable to connect'), findsNothing);
    });
  });
}
