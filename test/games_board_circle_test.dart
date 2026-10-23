import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cosmicguide/screens/games/cosmic_match_screen.dart';
import 'package:cosmicguide/screens/games/moksha_patam_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/widgets/moksha_board.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Contract-shaped payloads (local to this file)
// ---------------------------------------------------------------------------

const _longLine = 'This is a deliberately long sentence that keeps going so that narrow screens and large '
    'text sizes are exercised properly without any overflow appearing anywhere at all.';

Map<String, dynamic> _luck({bool favorable = true, bool chandrashtama = false}) => {
      'tara': favorable ? 'Mitra' : 'Vipat',
      'favorable': favorable,
      'chandrashtama': chandrashtama,
      'line': chandrashtama
          ? 'Chandrashtama today — go gently, the Moon is resting far from your star.'
          : (favorable ? 'Mitra Tara — the sky is on your side today' : 'Vipat Tara — a slow and steady kind of day'),
    };

Map<String, dynamic> _boardPlayer(String key, String name,
        {String? relationship, int position = 14, int wins = 0, int rollsLeft = 2, bool favorable = true}) =>
    {
      'profileKey': key,
      'name': name,
      'relationship': relationship,
      'position': position,
      'wins': wins,
      'rollsLeft': rollsLeft,
      'isYou': key == 'self',
      'luck': _luck(favorable: favorable, chandrashtama: key == 'fam:9'),
    };

List<Map<String, dynamic>> _boardPlayers({int position = 14, int rollsLeft = 2, int wins = 1}) => [
      _boardPlayer('self', 'Ravindra Nath Jha', position: position, wins: wins, rollsLeft: rollsLeft),
      _boardPlayer('fam:7', 'Meera', relationship: 'Mother', position: 37, rollsLeft: 1),
      _boardPlayer('fam:9', 'Aarav', relationship: 'Son', position: 14, rollsLeft: 0, favorable: false),
    ];

Map<String, dynamic> boardPayload({int position = 14, int rollsLeft = 2}) => {
      'board': {
        'size': 100,
        'ladders': [
          {'from': 4, 'to': 25, 'name': 'Generosity', 'line': 'Giving lifts you higher. $_longLine'},
          {'from': 16, 'to': 44, 'name': 'Truth', 'line': 'Honest words open doors.'},
          {'from': 51, 'to': 72, 'name': 'Patience', 'line': 'Waiting well is a superpower.'},
          {'from': 63, 'to': 95, 'name': 'Compassion', 'line': 'Kindness is the shortcut.'},
        ],
        'snakes': [
          {'from': 29, 'to': 8, 'name': 'Anger', 'line': 'A hot moment, a long slide. Breathe.'},
          {'from': 76, 'to': 41, 'name': 'Pride', 'line': 'Pride goes before the slide.'},
          {'from': 99, 'to': 62, 'name': 'Ego', 'line': 'So close! Humility gets you home.'},
        ],
      },
      'players': _boardPlayers(position: position, rollsLeft: rollsLeft),
      'lastMoves': [
        {'profileKey': 'self', 'name': 'Ravindra Nath Jha', 'dice': 4, 'from': 10, 'to': 14, 'event': null, 'at': '2026-10-10T08:12:00.000Z'},
        {'profileKey': 'fam:7', 'name': 'Meera', 'dice': 2, 'from': 14, 'to': 44, 'event': 'Ladder: Truth', 'at': '2026-10-10T07:02:00.000Z'},
      ],
    };

Map<String, dynamic> rollPayload({
  String profileKey = 'self',
  required int dice,
  required int from,
  int? landed,
  int? to,
  Map<String, dynamic>? event,
  bool overshoot = false,
  bool won = false,
  Map<String, dynamic>? reward,
  int rollsLeft = 1,
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
    'players': [
      for (final p in _boardPlayers())
        p['profileKey'] == profileKey
            ? {...p, 'position': won ? 1 : t, 'rollsLeft': rollsLeft, 'wins': (p['wins'] as int) + (won ? 1 : 0)}
            : p,
    ],
    'player': {'level': 3, 'xp': 420, 'xpIntoLevel': 120, 'xpForNext': 300, 'title': 'Star Seeker', 'streak': 4, 'bestStreak': 9, 'streakAliveToday': true},
  };
}

Map<String, dynamic> _member(String id, String name,
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
          ? {
              'score': score,
              'max': 36,
              'label': label,
              'strongest': 'You make each other laugh easily. $_longLine',
              'weakest': 'Your tempers run at different speeds.',
            }
          : null,
      'todayScore': hasChart ? todayScore : null,
      'mood': hasChart ? 'good' : null,
    };

List<Map<String, dynamic>> _defaultMembers() => [
      _member('fam:7', 'Meera', relationship: 'Mother', score: 31, label: 'Soul-level', todayScore: 86),
      _member('friend:42', 'Priya Sharma', score: 24, label: 'Easy', todayScore: 67),
      _member('friend:43', 'Chartless Charlie With A Very Long Name Indeed', hasChart: false),
    ];

Map<String, dynamic> circleData({List<Map<String, dynamic>>? members, String? inviteCode = 'STAR42'}) {
  final list = members ?? _defaultMembers();
  Map<String, dynamic> ranking(String id, String title, String emoji, int need) => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'unlocked': list.length >= need,
        'needMembers': need,
        'entries': list.length >= need
            ? [
                for (final m in list.where((m) => m['hasChart'] == true).take(3))
                  {'memberId': m['id'], 'name': m['name'], 'value': '31/36', 'note': 'You two just get each other. $_longLine'},
              ]
            : [],
      };
  return {
    'inviteCode': inviteCode,
    'shareText': 'Join my Cosmic Circle on CosmicGuide! Use my code STAR42 and see how our stars match.',
    'members': list,
    'you': {'name': 'Ravindra Nath Jha', 'moonSign': 'Capricorn', 'nakshatra': 'Shravana', 'todayScore': 68, 'mood': 'good'},
    'rankings': [
      ranking('cosmicTwin', 'Cosmic Twin', '👯', 1),
      ranking('luckiestToday', 'Luckiest Today', '🍀', 2),
      ranking('travelBuddy', 'Travel Buddy', '🧳', 5),
    ],
  };
}

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

class BoardCircleBackend extends BackendService {
  Map<String, dynamic>? board = boardPayload();
  Map<String, dynamic>? circle = circleData();
  Map<String, dynamic>? rollResponse;
  Map<String, dynamic>? joinResponse;
  Map<String, dynamic>? removeResponse;
  Completer<void>? boardGate;
  String? errorCode;
  String? errorMessage;

  int boardCalls = 0;
  int circleCalls = 0;
  final List<String> rollCalls = [];
  final List<String> joinCalls = [];
  final List<int> removeCalls = [];

  @override
  String? get lastError => errorMessage;
  @override
  String? get lastErrorCode => errorCode;

  void fail(String message, [String? code]) {
    errorMessage = message;
    errorCode = code;
  }

  @override
  Future<Map<String, dynamic>?> fetchMokshaBoard() async {
    boardCalls++;
    if (boardGate != null) await boardGate!.future;
    return board;
  }

  @override
  Future<Map<String, dynamic>?> rollMokshaDice({String profileKey = 'self'}) async {
    rollCalls.add(profileKey);
    return rollResponse;
  }

  @override
  Future<Map<String, dynamic>?> fetchCircle() async {
    circleCalls++;
    return circle;
  }

  @override
  Future<Map<String, dynamic>?> joinCircle(String code) async {
    joinCalls.add(code);
    return joinResponse;
  }

  @override
  Future<Map<String, dynamic>?> removeCircleFriend(int userId) async {
    removeCalls.add(userId);
    return removeResponse;
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> pumpGame(WidgetTester tester, Widget screen, BoardCircleBackend fake,
    {bool reduceMotion = true, bool settle = true}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<BackendService>.value(
      value: fake,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3), disableAnimations: reduceMotion),
          child: child!,
        ),
        routes: {
          '/chatbot': (context) => Scaffold(
                body: Text('CHAT:${(ModalRoute.of(context)?.settings.arguments as Map?)?['initialMessage'] ?? ''}'),
              ),
          '/birth-details': (_) => const Scaffold(body: Text('BIRTH DETAILS')),
          '/login': (_) => const Scaffold(body: Text('LOGIN')),
          '/games/quest': (_) => const Scaffold(body: Text('QUEST')),
        },
        home: screen,
      ),
    ),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<void> scrollAll(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

final _roll = find.byKey(const Key('moksha-roll'));
Finder _playerTile(String key) => find.byKey(ValueKey('moksha-player-$key'));
Finder _inTile(String key, String text) => find.descendant(of: _playerTile(key), matching: find.textContaining(text));

List<String> captureClipboard(WidgetTester tester) {
  final clips = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clips.add((call.arguments as Map)['text'] as String);
    return null;
  });
  // No app can open whatsapp:// here: every url_launcher flavour answers "no".
  const legacy = MethodChannel('plugins.flutter.io/url_launcher');
  const pigeons = [
    'dev.flutter.pigeon.url_launcher_windows.UrlLauncherApi.launchUrl',
    'dev.flutter.pigeon.url_launcher_windows.UrlLauncherApi.canLaunchUrl',
  ];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(legacy, (call) async => false);
  for (final name in pigeons) {
    messenger.setMockMessageHandler(name, (message) async => null);
  }
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(legacy, null);
    for (final name in pigeons) {
      messenger.setMockMessageHandler(name, null);
    }
  });
  return clips;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  group('Moksha board geometry', () {
    test('square → cell mapping is boustrophedon from the bottom-left', () {
      expect(MokshaGeometry.cellOf(1), const MokshaCell(0, 9));
      expect(MokshaGeometry.cellOf(10), const MokshaCell(9, 9));
      expect(MokshaGeometry.cellOf(11), const MokshaCell(9, 8));
      expect(MokshaGeometry.cellOf(20), const MokshaCell(0, 8));
      expect(MokshaGeometry.cellOf(91), const MokshaCell(9, 0));
      expect(MokshaGeometry.cellOf(100), const MokshaCell(0, 0));
    });

    test('cell → square is the exact inverse for all 100 squares', () {
      final seen = <MokshaCell>{};
      for (var sq = 1; sq <= 100; sq++) {
        final c = MokshaGeometry.cellOf(sq);
        expect(c.col, inInclusiveRange(0, 9));
        expect(c.row, inInclusiveRange(0, 9));
        expect(MokshaGeometry.squareAt(c.col, c.row), sq);
        seen.add(c);
      }
      expect(seen, hasLength(100));
      // Neighbouring squares always touch (no jumps at the row turns).
      for (var sq = 1; sq < 100; sq++) {
        final a = MokshaGeometry.cellOf(sq);
        final b = MokshaGeometry.cellOf(sq + 1);
        expect((a.col - b.col).abs() + (a.row - b.row).abs(), 1, reason: '$sq → ${sq + 1}');
      }
    });

    test('out-of-range squares clamp, points map back to squares', () {
      expect(MokshaGeometry.cellOf(0), MokshaGeometry.cellOf(1));
      expect(MokshaGeometry.cellOf(140), MokshaGeometry.cellOf(100));
      expect(MokshaGeometry.unitCenter(1), const Offset(0.05, 0.95));
      expect(MokshaGeometry.unitCenter(100), const Offset(0.05, 0.05));
      expect(MokshaGeometry.squareAtPoint(const Offset(5, 283), 288), 1);
      expect(MokshaGeometry.squareAtPoint(const Offset(5, 5), 288), 100);
      expect(MokshaGeometry.squareAtPoint(const Offset(283, 5), 288), 91);
      expect(MokshaGeometry.squareAtPoint(const Offset(300, 5), 288), isNull);
      expect(MokshaGeometry.squareAtPoint(const Offset(-1, 5), 288), isNull);
    });

    test('hops and snake slides start and end exactly on their squares', () {
      final a = MokshaGeometry.unitCenter(29);
      final b = MokshaGeometry.unitCenter(8);
      Offset snake(double t) => MokshaGeometry.snakePoint(a, b, t, cell: 0.1);
      expect((snake(0) - a).distance, lessThan(1e-9));
      expect((snake(1) - b).distance, lessThan(1e-9));
      expect((snake(0.3) - Offset.lerp(a, b, 0.3)!).distance, greaterThan(0)); // it wiggles
      expect(MokshaGeometry.hop(a, b, 0), a);
      expect((MokshaGeometry.hop(a, b, 1) - b).distance, lessThan(1e-9));
      expect(MokshaGeometry.hop(a, a, 0.5).dy, lessThan(a.dy)); // jumps up
    });
  });

  // -------------------------------------------------------------------------
  group('MokshaPatamScreen at 320x640, 1.3x text', () {
    testWidgets('renders board, players, hints and moves without overflow', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const MokshaPatamScreen(), fake);

      expect(find.text('Moksha Patam'), findsOneWidget);
      expect(tester.getSize(find.byType(MokshaBoardView)), const Size(288, 288));
      expect(find.textContaining('Mitra Tara'), findsOneWidget);
      expect(find.text('Lucky star day · +1 roll'), findsOneWidget);
      expect(find.text('Roll the dice'), findsOneWidget);
      expect(find.text('2 rolls left today'), findsOneWidget);
      expect(_inTile('self', 'Square 14 · 2 rolls left'), findsOneWidget);
      expect(_inTile('fam:7', 'Mother · Square 37 · 1 roll left'), findsOneWidget);
      expect(_inTile('fam:9', 'No rolls left'), findsOneWidget);
      expect(find.text('Want more rolls?'), findsOneWidget);
      expect(find.textContaining('14 → 44'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await scrollAll(tester);
      expect(tester.takeException(), isNull);
      expect(fake.boardCalls, 1);
    });

    testWidgets('also lays out with animations on and at normal text size', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const MokshaPatamScreen(), fake, reduceMotion: false);
      await scrollAll(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a ladder square tells its story; How to play lists them all', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const MokshaPatamScreen(), fake);

      final board = find.byType(MokshaBoardView);
      final origin = tester.getTopLeft(board);
      final c = MokshaGeometry.unitCenter(16) * 288;
      await tester.tapAt(origin + c);
      await tester.pumpAndSettle();
      expect(find.text('Square 16'), findsOneWidget);
      expect(find.text('Truth'), findsOneWidget);
      expect(find.text('Honest words open doors.'), findsOneWidget);
      expect(find.textContaining('climbs from 16 to 44'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(160, 20));
      await tester.pumpAndSettle();

      // A plain square does nothing.
      await tester.tapAt(origin + MokshaGeometry.unitCenter(2) * 288);
      await tester.pumpAndSettle();
      expect(find.text('Square 2'), findsNothing);

      await tester.tap(find.byTooltip('How to play'));
      await tester.pumpAndSettle();
      expect(find.text('How to play'), findsOneWidget);
      expect(find.textContaining('ancient Indian game of karma'), findsOneWidget);
      await tester.drag(find.text('How to play'), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Anger'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ladder roll climbs and shows the virtue line', (tester) async {
      final fake = BoardCircleBackend()
        ..rollResponse = rollPayload(
            dice: 2, from: 14, landed: 16, to: 44, event: {'type': 'ladder', 'name': 'Truth', 'line': 'Honest words open doors.'});
      await pumpGame(tester, const MokshaPatamScreen(), fake);

      await tapVisible(tester, _roll);
      expect(fake.rollCalls, ['self']);
      expect(find.text('Ladder! Truth'), findsOneWidget);
      expect(find.text('Honest words open doors.'), findsOneWidget);
      expect(find.textContaining('climbed from 16 to 44'), findsOneWidget);
      expect(_inTile('self', 'Square 44 · 1 roll left'), findsOneWidget);
      expect(find.text('1 roll left today'), findsOneWidget);
      expect(find.textContaining('14 → 44 · Ladder: Truth'), findsNWidgets(2)); // new move on top of the old one
      expect(tester.takeException(), isNull);
    });

    testWidgets('snake roll (animated) slides down kindly; double taps roll once', (tester) async {
      final fake = BoardCircleBackend()
        ..board = boardPayload(position: 27)
        ..rollResponse = rollPayload(
            dice: 2,
            from: 27,
            landed: 29,
            to: 8,
            event: {'type': 'snake', 'name': 'Anger', 'line': 'A hot moment, a long slide. Breathe.'});
      await pumpGame(tester, const MokshaPatamScreen(), fake, reduceMotion: false);

      await tester.ensureVisible(_roll);
      await tester.pumpAndSettle();
      await tester.tap(_roll);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Rolling…'), findsOneWidget);
      await tester.tap(_roll, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      // Mid-animation the other players cannot be selected either.
      await tester.tap(_playerTile('fam:7'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(fake.rollCalls, ['self']);
      expect(find.text('A little slip: Anger'), findsOneWidget);
      expect(find.text('A hot moment, a long slide. Breathe.'), findsOneWidget);
      expect(find.textContaining('slid from 29 to 8'), findsOneWidget);
      expect(_inTile('self', 'Square 8 · 1 roll left'), findsOneWidget);
      expect(find.text('Roll the dice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overshoot keeps the token and explains the exact roll needed', (tester) async {
      final fake = BoardCircleBackend()
        ..board = boardPayload(position: 97)
        ..rollResponse = rollPayload(dice: 5, from: 97, overshoot: true);
      await pumpGame(tester, const MokshaPatamScreen(), fake);

      await tapVisible(tester, _roll);
      expect(find.text('So close!'), findsOneWidget);
      expect(find.textContaining('Moksha needs exactly 3'), findsOneWidget);
      expect(_inTile('self', 'Square 97 · 1 roll left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('win (animated) celebrates with rewards, then resets to square 1', (tester) async {
      final fake = BoardCircleBackend()
        ..board = boardPayload(position: 97)
        ..rollResponse = rollPayload(dice: 3, from: 97, landed: 100, to: 100, won: true, rollsLeft: 0, reward: {
          'xp': 150,
          'card': {
            'id': 'rare:moksha',
            'kind': 'rare',
            'name': 'Moksha',
            'symbol': '🕉',
            'ruler': null,
            'deity': null,
            'power': 'Liberation — you finished the journey. $_longLine',
            'keywords': ['freedom'],
            'rarity': 'legendary',
            'isBirthStar': false,
            'collected': true,
            'collectedOn': '2026-10-11',
          },
        });
      await pumpGame(tester, const MokshaPatamScreen(), fake, reduceMotion: false);

      await tapVisible(tester, _roll);
      expect(find.text('Moksha!'), findsWidgets);
      expect(find.text('+150 XP'), findsOneWidget);
      expect(find.text('Rare card unlocked'), findsOneWidget);
      expect(find.text('Moksha × 2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Begin a new journey'));
      await tester.pumpAndSettle();
      expect(find.text('Begin a new journey'), findsNothing);
      expect(_inTile('self', 'Square 1 · No rolls left'), findsOneWidget);
      expect(find.textContaining('97 → 100 · Moksha!'), findsOneWidget);
      expect(find.text('The dice are resting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no rolls left: friendly rest card, countdown and a way to keep playing', (tester) async {
      final fake = BoardCircleBackend()..board = boardPayload(rollsLeft: 0);
      await pumpGame(tester, const MokshaPatamScreen(), fake);

      expect(_roll, findsNothing);
      expect(find.text('The dice are resting'), findsOneWidget);
      expect(find.textContaining('Come back tomorrow'), findsOneWidget);
      expect(find.textContaining('New rolls in '), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.text('Roll for Meera'));
      expect(_roll, findsOneWidget);
      expect(find.text('Roll for Meera'), findsOneWidget); // now the dice button itself
      expect(find.text('The dice are resting'), findsNothing);
    });

    testWidgets('server NO_ROLLS_LEFT shows its hint instead of an error', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const MokshaPatamScreen(), fake);
      fake.fail('You have used today\'s rolls. Finish your 3 missions for a bonus roll!', 'NO_ROLLS_LEFT');

      await tapVisible(tester, _roll);
      expect(fake.rollCalls, ['self']);
      expect(find.text('The dice are resting'), findsOneWidget);
      expect(find.textContaining('Finish your 3 missions for a bonus roll'), findsOneWidget);
      expect(find.textContaining('New rolls in '), findsOneWidget);
      expect(_inTile('self', 'Square 14 · No rolls left'), findsOneWidget);
      expect(_roll, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed roll keeps the state and can be retried', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const MokshaPatamScreen(), fake);
      fake.fail('Unable to connect to the server.');

      await tapVisible(tester, _roll);
      expect(find.text('Unable to connect to the server.'), findsOneWidget);
      expect(_inTile('self', 'Square 14 · 2 rolls left'), findsOneWidget);

      fake
        ..errorMessage = null
        ..rollResponse = rollPayload(dice: 3, from: 14);
      await tapVisible(tester, _roll);
      expect(fake.rollCalls, ['self', 'self']);
      expect(find.textContaining('Hopped from 14 to 17'), findsOneWidget);
      expect(_inTile('self', 'Square 17'), findsOneWidget);
    });

    testWidgets('rolling for a family member sends their profileKey', (tester) async {
      final fake = BoardCircleBackend()..rollResponse = rollPayload(profileKey: 'fam:7', dice: 4, from: 37, rollsLeft: 0);
      await pumpGame(tester, const MokshaPatamScreen(), fake);

      await tapVisible(tester, _playerTile('fam:7'));
      expect(find.text('Roll for Meera'), findsOneWidget);
      await tapVisible(tester, _roll);
      expect(fake.rollCalls, ['fam:7']);
      expect(find.text('Meera rolled a 4'), findsOneWidget);
      expect(_inTile('fam:7', 'Square 41 · No rolls left'), findsOneWidget);
      expect(_inTile('self', 'Square 14 · 2 rolls left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missions hint links to Graha Quest', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const MokshaPatamScreen(), fake);
      await tapVisible(tester, find.text('Go to today\'s missions'));
      expect(find.text('QUEST'), findsOneWidget);
    });

    testWidgets('NO_KUNDLI leads to birth details', (tester) async {
      final fake = BoardCircleBackend()
        ..board = null
        ..fail('No Kundli found', 'NO_KUNDLI');
      await pumpGame(tester, const MokshaPatamScreen(), fake);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Create my Kundli'));
      expect(find.text('BIRTH DETAILS'), findsOneWidget);
    });

    testWidgets('load error shows retry, which reloads', (tester) async {
      final fake = BoardCircleBackend()
        ..board = null
        ..fail('The server is taking too long to respond.');
      await pumpGame(tester, const MokshaPatamScreen(), fake);
      expect(find.text('The server is taking too long to respond.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      fake
        ..board = boardPayload()
        ..errorMessage = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(MokshaBoardView), findsOneWidget);
      expect(fake.boardCalls, 2);
    });

    testWidgets('shows a skeleton while the board loads', (tester) async {
      final fake = BoardCircleBackend()..boardGate = Completer<void>();
      await pumpGame(tester, const MokshaPatamScreen(), fake, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Setting up the board'), findsOneWidget);
      fake.boardGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MokshaBoardView), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('CosmicMatchScreen at 320x640, 1.3x text', () {
    Finder member(String id) => find.byKey(ValueKey('member-$id'));
    Finder ranking(String id) => find.byKey(ValueKey('ranking-$id'));
    final codeInput = find.byKey(const Key('circle-code-input'));

    testWidgets('renders you, invite, rankings (locked + unlocked) and members', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      expect(find.text('You'), findsOneWidget);
      expect(find.text('Moon in Capricorn · Shravana'), findsOneWidget);
      expect(find.text('Today: Good'), findsOneWidget);
      expect(find.text('STAR42'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Have a code?'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(ranking('cosmicTwin'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: ranking('cosmicTwin'), matching: find.text('Meera')), findsOneWidget);
      expect(find.descendant(of: ranking('cosmicTwin'), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: ranking('cosmicTwin'), matching: find.text('31/36')), findsNWidgets(2));
      expect(find.descendant(of: ranking('cosmicTwin'), matching: find.byIcon(Icons.lock_rounded)), findsNothing);
      expect(find.descendant(of: ranking('travelBuddy'), matching: find.byIcon(Icons.lock_rounded)), findsOneWidget);
      expect(find.descendant(of: ranking('travelBuddy'), matching: find.text('Add 2 more people to unlock')),
          findsOneWidget);
      // Swipe the podium row sideways.
      await tester.drag(find.byKey(const Key('circle-rankings')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(member('fam:7'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: member('fam:7'), matching: find.text('Family')), findsOneWidget);
      expect(find.descendant(of: member('fam:7'), matching: find.text('Soul-level')), findsOneWidget);
      expect(find.descendant(of: member('fam:7'), matching: find.text('31')), findsOneWidget);
      expect(find.descendant(of: member('fam:7'), matching: find.text('Today 86')), findsOneWidget);
      expect(find.descendant(of: member('friend:42'), matching: find.text('Friend')), findsOneWidget);
      expect(find.descendant(of: member('friend:43'), matching: find.text('Hasn\'t added birth details')), findsOneWidget);
      expect(find.text('Your circle is waiting'), findsNothing);

      await scrollAll(tester);
      expect(tester.takeException(), isNull);
      expect(fake.circleCalls, 1);
    });

    testWidgets('Copy copies the code', (tester) async {
      final clips = captureClipboard(tester);
      final fake = BoardCircleBackend();
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      await tapVisible(tester, find.text('Copy'));
      expect(clips, ['STAR42']);
      expect(find.textContaining('Code copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Share falls back to copying the invite text when WhatsApp is missing', (tester) async {
      final clips = captureClipboard(tester);
      final fake = BoardCircleBackend();
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      await tapVisible(tester, find.text('Share'));
      expect(clips.single, contains('Use my code STAR42'));
      expect(find.textContaining('Invite copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('joining with a code adds the friend', (tester) async {
      final kabir = _member('friend:77', 'Kabir', score: 27, label: 'Strong');
      final fake = BoardCircleBackend()
        ..joinResponse = {
          'member': kabir,
          'circle': circleData(members: [..._defaultMembers(), kabir]),
        };
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      // Empty input is caught locally.
      await tapVisible(tester, find.text('Join'));
      expect(find.text('Type the code your friend sent you.'), findsOneWidget);
      expect(fake.joinCalls, isEmpty);

      await tester.enterText(codeInput, ' MOON77 ');
      await tapVisible(tester, find.text('Join'));
      expect(fake.joinCalls, ['MOON77']);
      expect(find.textContaining('Kabir is in your circle now'), findsOneWidget);
      expect(tester.widget<TextField>(codeInput).controller!.text, isEmpty);
      await tester.ensureVisible(member('friend:77'));
      expect(member('friend:77'), findsOneWidget);
      expect(find.text('Your circle · 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    const joinErrors = {
      'INVALID_CODE': 'that code doesn\'t match anyone',
      'OWN_CODE': 'That\'s your own code',
      'BAD_CODE': 'look like a code',
      'CIRCLE_FULL': 'circle is full',
      'ALREADY_FRIENDS': 'already in each other\'s circle',
    };
    for (final e in joinErrors.entries) {
      testWidgets('join error ${e.key} is shown inline', (tester) async {
        final fake = BoardCircleBackend();
        await pumpGame(tester, const CosmicMatchScreen(), fake);
        fake.fail('Server says no', e.key);

        await tester.enterText(codeInput, 'NOPE00');
        await tapVisible(tester, find.text('Join'));
        expect(fake.joinCalls, ['NOPE00']);
        expect(find.textContaining(e.value), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.widget<TextField>(codeInput).controller!.text, 'NOPE00');
        expect(tester.takeException(), isNull);

        // Typing again clears the error.
        await tester.enterText(codeInput, 'NOPE01');
        await tester.pumpAndSettle();
        expect(find.textContaining(e.value), findsNothing);
      });
    }

    testWidgets('join as a guest asks to log in', (tester) async {
      final fake = BoardCircleBackend()..circle = circleData(inviteCode: null);
      await pumpGame(tester, const CosmicMatchScreen(), fake);
      expect(find.text('Log in to invite friends'), findsOneWidget);
      expect(find.text('STAR42'), findsNothing);
      fake.fail('Please log in', 'LOGIN_REQUIRED');

      await tester.enterText(codeInput, 'STAR99');
      await tapVisible(tester, find.text('Join'));
      expect(find.text('Log in to add friends to your circle.'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(TextButton, 'Log in'));
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('member sheet explains the match and asks the astrologer', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      await tapVisible(tester, member('fam:7'));
      expect(find.text('Soul-level match'), findsOneWidget);
      expect(find.text('Where you two click'), findsOneWidget);
      expect(find.text('Where to go gently'), findsOneWidget);
      expect(find.text('Your tempers run at different speeds.'), findsOneWidget);
      expect(find.text('Meera\'s day today'), findsOneWidget);
      expect(find.text('Remove from circle'), findsNothing); // family can't be removed here
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.text('Ask an astrologer about us'));
      expect(find.textContaining('CHAT:Tell me about my compatibility with my Mother Meera.'), findsOneWidget);
      expect(find.textContaining('31/36 (Soul-level)'), findsOneWidget);
    });

    testWidgets('a member without a chart shows a gentle nudge, no ring', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const CosmicMatchScreen(), fake);
      await tapVisible(tester, member('friend:43'));
      expect(find.text('No match yet'), findsOneWidget);
      expect(find.text('Ask an astrologer about us'), findsNothing);
      expect(find.text('Remove from circle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing a friend asks first, then updates the circle', (tester) async {
      final fake = BoardCircleBackend()
        ..removeResponse = {
          'success': true,
          'circle': circleData(members: _defaultMembers().where((m) => m['id'] != 'friend:42').toList()),
        };
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      // Cancel first: nothing is sent.
      await tapVisible(tester, member('friend:42'));
      expect(find.text('Easy match'), findsOneWidget);
      await tapVisible(tester, find.text('Remove from circle'));
      expect(find.text('Remove Priya Sharma?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(fake.removeCalls, isEmpty);
      expect(member('friend:42'), findsOneWidget);

      await tapVisible(tester, member('friend:42'));
      await tapVisible(tester, find.text('Remove from circle'));
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(fake.removeCalls, [42]);
      expect(member('friend:42'), findsNothing);
      expect(find.text('Priya Sharma was removed from your circle.'), findsOneWidget);
      expect(find.text('Your circle · 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed remove keeps the friend and says why', (tester) async {
      final fake = BoardCircleBackend();
      await pumpGame(tester, const CosmicMatchScreen(), fake);
      fake.fail('Could not remove this friend. Please try again.');
      await tapVisible(tester, member('friend:42'));
      await tapVisible(tester, find.text('Remove from circle'));
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(fake.removeCalls, [42]);
      expect(member('friend:42'), findsOneWidget);
      expect(find.text('Could not remove this friend. Please try again.'), findsOneWidget);
    });

    testWidgets('guest LOGIN_REQUIRED shows the log-in state', (tester) async {
      final fake = BoardCircleBackend()
        ..circle = null
        ..fail('Please log in to use Cosmic Match', 'LOGIN_REQUIRED');
      await pumpGame(tester, const CosmicMatchScreen(), fake);
      expect(find.text('Log in to build your circle'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Log in'));
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('empty circle makes inviting the main event', (tester) async {
      final clips = captureClipboard(tester);
      final fake = BoardCircleBackend()..circle = circleData(members: []);
      await pumpGame(tester, const CosmicMatchScreen(), fake);

      expect(find.byKey(const Key('circle-empty')), findsOneWidget);
      expect(find.text('Your circle is waiting'), findsOneWidget);
      expect(find.textContaining('Your circle ·'), findsNothing);
      await tester.ensureVisible(ranking('cosmicTwin'));
      expect(find.descendant(of: ranking('cosmicTwin'), matching: find.text('Add 1 more person to unlock')),
          findsOneWidget);
      expect(find.descendant(of: ranking('travelBuddy'), matching: find.text('Add 5 more people to unlock')),
          findsOneWidget);
      await scrollAll(tester);
      expect(tester.takeException(), isNull);

      await tapVisible(tester, find.text('Invite your first person'));
      expect(clips.single, contains('STAR42'));
    });

    testWidgets('NO_KUNDLI leads to birth details', (tester) async {
      final fake = BoardCircleBackend()
        ..circle = null
        ..fail('No Kundli found', 'NO_KUNDLI');
      await pumpGame(tester, const CosmicMatchScreen(), fake);
      await tapVisible(tester, find.text('Create my Kundli'));
      expect(find.text('BIRTH DETAILS'), findsOneWidget);
    });

    testWidgets('load error shows retry, which reloads', (tester) async {
      final fake = BoardCircleBackend()
        ..circle = null
        ..fail('Unable to connect to the server.');
      await pumpGame(tester, const CosmicMatchScreen(), fake);
      expect(find.text('Unable to connect to the server.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      fake
        ..circle = circleData()
        ..errorMessage = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('STAR42'), findsOneWidget);
      expect(fake.circleCalls, 2);
    });
  });
}
