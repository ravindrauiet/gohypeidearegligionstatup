import 'dart:async';

import 'package:cosmicguide/screens/buddy/buddy_chat_screen.dart';
import 'package:cosmicguide/screens/buddy/buddy_hub_tab.dart';
import 'package:cosmicguide/screens/buddy/buddy_profile_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/buddy_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:cosmicguide/widgets/buddy/buddy_badge_scope.dart';
import 'package:cosmicguide/widgets/buddy/buddy_home_section.dart';
import 'package:cosmicguide/widgets/buddy/nearby_buddy_watcher.dart';
import 'package:cosmicguide/widgets/custom_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> candidateJson({int id = 7, String name = 'Priya Sharma', int score = 82}) => {
      'userId': id,
      'displayName': name,
      'age': 27,
      'city': 'Varanasi',
      'distanceKm': 4,
      'photoUrl': null,
      'intents': ['friend', 'spiritual'],
      'bio': 'I love early morning aarti and long walks by the ghats.',
      'languages': ['Hindi', 'English'],
      'score': score,
      'breakdown': {'kundli': 74, 'mindset': 88, 'distance': 96},
      'highlights': [
        'Both Moons in water signs: easy emotional understanding',
        'You agree on 31 of 38 shared questions',
      ],
      'sharedAnswers': 38,
      'agreeAnswers': 31,
      'connection': null,
    };

Map<String, dynamic> profileJson({List<String> intents = const ['friend'], bool showNearby = true}) => {
      'displayName': 'Ravi',
      'bio': 'Seeker, chai lover and weekend trekker.',
      'intents': intents,
      'gender': 'male',
      'interestedIn': 'any',
      'city': 'Patna',
      'languages': ['Hindi'],
      'showNearby': showNearby,
      'isActive': true,
      'hasLocation': true,
    };

class FakeBuddyBackend extends BackendService {
  bool loggedIn = true;
  Map<String, dynamic> status = {'profile': null, 'eligible': true, 'age': 30, 'quizAnswered': 0, 'quizTotal': 50};
  List<Map<String, dynamic>> candidates = [candidateJson()];
  List<Map<String, dynamic>> nearbyList = [];
  List<Map<String, dynamic>> messages = [];
  Map<String, dynamic> connections = {'incoming': [], 'outgoing': [], 'buddies': []};
  final List<(String, String, Map<String, dynamic>?)> calls = [];

  /// "METHOD /path" (no query) -> error thrown for that call.
  final Map<String, BackendException> failures = {};

  /// "METHOD /path" -> code of the error body (what BackendService.lastErrorCode reports).
  final Map<String, String> failureCodes = {};
  String? _lastCode;
  @override
  String? get lastErrorCode => _lastCode;

  /// Each GET /buddy/connections takes the next gate (if any) and waits for it.
  final List<Completer<void>> connectionGates = [];

  /// Overrides GET /buddy/user/:id.
  Map<String, dynamic>? userCandidate;
  int _msgId = 100;

  int count(String method, String path) => calls.where((c) => c.$1 == method && c.$2.split('?').first == path).length;

  @override
  bool get isAuthenticated => loggedIn;
  @override
  Map<String, dynamic>? get user => loggedIn ? {'id': 1, 'fullName': 'Ravi Kumar', 'gender': 'Male'} : null;
  @override
  bool get hasBirthDetails => true;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add((method, path, body));
    final p = path.split('?').first;
    final fail = failures['$method $p'];
    _lastCode = fail == null ? null : failureCodes['$method $p'];
    if (fail != null) throw fail;
    if (method == 'GET' && p == '/buddy/profile') return status;
    if (method == 'PUT' && p == '/buddy/profile') {
      status = {
        ...status,
        'profile': {...body!, 'hasLocation': false}
      };
      return {'profile': status['profile']};
    }
    if (method == 'GET' && p == '/buddy/discover') return {'candidates': candidates};
    if (method == 'GET' && p == '/buddy/nearby') return {'candidates': nearbyList};
    if (method == 'GET' && p.startsWith('/buddy/user/')) return {'candidate': userCandidate ?? candidateJson()};
    if (method == 'GET' && p == '/buddy/connections') {
      final snapshot = connections;
      final gate = connectionGates.isNotEmpty ? connectionGates.removeAt(0) : null;
      if (gate != null) await gate.future;
      return snapshot;
    }
    if (method == 'GET' && p.startsWith('/buddy/chat/')) return {'messages': messages};
    if (method == 'POST' && p.startsWith('/buddy/chat/')) {
      final m = {'id': ++_msgId, 'body': body!['body'], 'createdAt': DateTime.now().toIso8601String(), 'mine': true};
      messages = [...messages, m];
      return {'message': m};
    }
    if (method == 'POST' && p == '/buddy/connect') {
      return {
        'connection': {'id': 55, 'status': 'pending', 'direction': 'outgoing'}
      };
    }
    return {'ok': true};
  }
}

Future<void> pumpBuddy(WidgetTester tester, FakeBuddyBackend backend, Widget child,
    {double width = 360, double textScale = 1.3}) async {
  tester.view.physicalSize = Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: backend),
      ChangeNotifierProvider(create: (c) => BuddyService(c.read<BackendService>())),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      routes: {
        '/login': (_) => const Scaffold(body: Text('LOGIN SCREEN')),
        '/birth-details': (_) => const Scaffold(body: Text('BIRTH SCREEN')),
      },
      home: child,
    ),
  ));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('models', () {
    test('candidate parses messy JSON safely', () {
      final c = BuddyCandidate.tryParse({
        'userId': '12',
        'displayName': '',
        'age': '29',
        'distanceKm': 3.6,
        'intents': ['friend', 'bogus'],
        'score': '140',
        'breakdown': {'kundli': null, 'mindset': '55.4'},
        'highlights': ['a', '', 'b', 'c', 'd', 'e'],
        'connection': {'id': 3, 'status': 'pending', 'direction': 'incoming'},
      })!;
      expect(c.userId, 12);
      expect(c.displayName, 'Buddy');
      expect(c.age, 29);
      expect(c.distanceLabel, '~4 km');
      expect(c.intents, ['friend']);
      expect(c.score, 100);
      expect(c.kundliScore, 0);
      expect(c.mindsetScore, 55);
      expect(c.highlights, ['a', 'b', 'c', 'd']);
      expect(c.connection!.isIncoming, isTrue);
      expect(BuddyCandidate.tryParse({'displayName': 'x'}), isNull);
    });

    test('status maps reasons to gates', () {
      expect(BuddyStatus.fromJson({'eligible': false, 'reason': 'UNDER_18'}).gate, BuddyGate.under18);
      expect(BuddyStatus.fromJson({'eligible': false, 'reason': 'NO_KUNDLI'}).gate, BuddyGate.noKundli);
      final ok = BuddyStatus.fromJson({'eligible': true, 'profile': profileJson(), 'quizAnswered': '12'});
      expect(ok.eligible, isTrue);
      expect(ok.profile!.intents, ['friend']);
      expect(ok.quizAnswered, 12);
    });

    test('connections parse and count unread', () {
      final c = BuddyConnections.fromJson({
        'incoming': [
          {'id': 1, 'intent': 'friend', 'status': 'pending', 'other': candidateJson(id: 2)}
        ],
        'buddies': [
          {'id': 2, 'intent': 'travel', 'status': 'accepted', 'other': candidateJson(id: 3), 'unread': '2'},
          {'id': 3, 'intent': 'travel', 'status': 'accepted', 'other': null},
        ],
      });
      expect(c.incoming, hasLength(1));
      expect(c.buddies, hasLength(1));
      expect(c.unread, 2);
    });
  });

  group('hub gate', () {
    testWidgets('logged out asks to log in', (tester) async {
      final b = FakeBuddyBackend()..loggedIn = false;
      await pumpBuddy(tester, b, const BuddyHubTab());
      expect(find.text('Log in to find your buddy'), findsOneWidget);
      await tapText(tester, 'Log in');
      expect(find.text('LOGIN SCREEN'), findsOneWidget);
    });

    testWidgets('no kundli sends to birth details', (tester) async {
      final b = FakeBuddyBackend()..status = {'eligible': false, 'reason': 'NO_KUNDLI'};
      await pumpBuddy(tester, b, const BuddyHubTab());
      expect(find.text('First, create your Kundli'), findsOneWidget);
      await tapText(tester, 'Create my Kundli');
      expect(find.text('BIRTH SCREEN'), findsOneWidget);
    });

    testWidgets('under 18 sees a friendly message', (tester) async {
      final b = FakeBuddyBackend()..status = {'eligible': false, 'reason': 'UNDER_18', 'age': 16};
      await pumpBuddy(tester, b, const BuddyHubTab());
      expect(find.text('Buddies is for adults (18+)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('eligible without profile shows the hero', (tester) async {
      await pumpBuddy(tester, FakeBuddyBackend(), const BuddyHubTab());
      expect(find.text('People who truly fit you'), findsOneWidget);
      expect(find.text('Create my buddy profile'), findsOneWidget);
      expect(find.text('Kundli match'), findsOneWidget);
    });
  });

  testWidgets('onboarding: one question per screen, saves profile, suggests quiz', (tester) async {
    final b = FakeBuddyBackend();
    await pumpBuddy(tester, b, const BuddyHubTab());
    await tapText(tester, 'Create my buddy profile');

    expect(find.text('What are you looking for?'), findsOneWidget);
    await tapText(tester, 'Next');
    expect(find.text('Pick at least one'), findsOneWidget);
    await tapText(tester, 'Life partner');
    await tapText(tester, 'Satsang buddy');
    await tapText(tester, 'Next');

    expect(find.text('A little about you'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Ravi'), findsOneWidget); // prefilled first name
    await tapText(tester, 'Next'); // gender prefilled from the account
    expect(find.text('For a life partner, you would like to meet…'), findsOneWidget);
    await tapText(tester, 'Women'); // auto-advances

    expect(find.text('Say something real'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'I love kirtan, chai and long walks by the river.');
    await tapText(tester, 'Next');

    expect(find.text('Which languages do you speak?'), findsOneWidget);
    await tapText(tester, 'Next');

    expect(find.text('Where are you based?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Patna');
    await tapText(tester, 'Next');

    expect(find.text('Our safety promise'), findsOneWidget);
    await tapText(tester, 'I am 18 or older');
    await tapText(tester, 'I will be kind and respectful');
    await tapText(tester, 'I will report anything that feels wrong');
    await tapText(tester, 'Create my profile');

    final put = b.calls.firstWhere((c) => c.$1 == 'PUT' && c.$2 == '/buddy/profile');
    expect(put.$3!['intents'], ['life_partner', 'spiritual']);
    expect(put.$3!['interestedIn'], 'female');
    expect(put.$3!['gender'], 'male');
    expect(put.$3!['city'], 'Patna');
    expect(find.text('Your buddy profile is live'), findsOneWidget);
    expect(find.textContaining('earn up to 2,500 coins'), findsOneWidget);
    expect(find.text('Start the questions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discover card renders at 360px / 1.3x and connects', (tester) async {
    final b = FakeBuddyBackend()
      ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 10, 'quizTotal': 50};
    await pumpBuddy(tester, b, const BuddyHubTab());
    expect(tester.takeException(), isNull);
    expect(find.text('Priya Sharma, 27'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Great match'), findsOneWidget);
    expect(find.text('~4 km'), findsOneWidget);
    expect(find.text('You agree on 31 of 38 shared questions'), findsOneWidget);
    expect(find.text('Kundli'), findsOneWidget);
    expect(find.text('Mindset'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.textContaining('Answer 40 more mindset questions'), findsOneWidget);

    await tapText(tester, 'Connect');
    expect(find.text('Connect with Priya'), findsOneWidget);
    await tapText(tester, 'Send request');
    expect(b.calls.any((c) => c.$2 == '/buddy/connect' && c.$3!['userId'] == 7), isTrue);
    expect(find.text('Priya Sharma, 27'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skip hides a card; report menu is available', (tester) async {
    final b = FakeBuddyBackend()..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50};
    await pumpBuddy(tester, b, const BuddyHubTab(), width: 320);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('More options for Priya'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tapText(tester, 'Skip');
    expect(find.text("You've seen everyone for now"), findsOneWidget);
  });

  testWidgets('chat sends a message and shows safety banner once', (tester) async {
    final b = FakeBuddyBackend();
    final conn = BuddyConnection.tryParse({
      'id': 9,
      'intent': 'spiritual',
      'status': 'accepted',
      'other': candidateJson(),
    })!;
    await pumpBuddy(
        tester, b, BuddyChatScreen(connection: conn, highlights: const ['You agree on 31 of 38 shared questions']));
    expect(find.textContaining('never share money or OTPs'), findsOneWidget);
    expect(find.text('You and Priya are buddies'), findsOneWidget);
    expect(find.byTooltip('Plan a temple trip'), findsOneWidget);
    expect(find.textContaining('Which question mattered most'), findsOneWidget); // icebreaker from highlights

    await tester.enterText(find.byType(TextField), 'Namaste Priya!');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(b.calls.any((c) => c.$1 == 'POST' && c.$2 == '/buddy/chat/9' && c.$3!['body'] == 'Namaste Priya!'), isTrue);
    expect(find.text('Namaste Priya!'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Polling picks up the other person's reply.
    b.messages = [
      ...b.messages,
      {'id': 500, 'body': 'Jai Shri Krishna!', 'createdAt': DateTime.now().toIso8601String(), 'mine': false},
    ];
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Jai Shri Krishna!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose the poller
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('buddy_chat_safety_seen_9'), isTrue);
  });

  testWidgets('home section invites, nearby watcher pops up once', (tester) async {
    final b = FakeBuddyBackend()
      ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50}
      ..nearbyList = [candidateJson(id: 7), candidateJson(id: 8, name: 'Meera Joshi', score: 77)];
    await pumpBuddy(
      tester,
      b,
      const Scaffold(
        body: NearbyBuddyWatcher(
          initialDelay: Duration(milliseconds: 10),
          child: SingleChildScrollView(child: BuddyHomeSection()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('2 buddies near you'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapText(tester, 'Later');
    expect(find.text('FIND YOUR BUDDY'), findsOneWidget); // home rail header (uppercase eyebrow)
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(NearbyBuddyWatcher.prefsSeenIds), containsAll(['7', '8']));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home section shows invitation without a profile', (tester) async {
    await pumpBuddy(tester, FakeBuddyBackend(), const Scaffold(body: SingleChildScrollView(child: BuddyHomeSection())));
    expect(find.text('Someone who truly fits you'), findsOneWidget);
    expect(find.text('Create my buddy profile'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // QA fixes + nav badge
  // -------------------------------------------------------------------------

  group('nav badge', () {
    testWidgets('bottom nav shows a red count on Buddy, caps at 99+, hides at zero', (tester) async {
      var count = 3;
      late StateSetter set;
      await pumpBuddy(
        tester,
        FakeBuddyBackend(),
        StatefulBuilder(builder: (context, setState) {
          set = setState;
          return Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: CustomBottomNav(currentIndex: 0, onTap: (_) {}, badges: {4: count}),
          );
        }),
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('nav-badge-4')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('nav-badge-4')), matching: find.text('3')), findsOneWidget);
      expect(find.bySemanticsLabel('Buddy tab, 3 new'), findsOneWidget);

      set(() => count = 150);
      await tester.pump();
      expect(find.text('99+'), findsOneWidget);
      expect(tester.takeException(), isNull);

      set(() => count = 0);
      await tester.pump();
      expect(find.byKey(const ValueKey('nav-badge-4')), findsNothing);
      expect(find.bySemanticsLabel('Buddy tab'), findsOneWidget);
    });

    Widget badgeHarness() => BuddyBadgeScope(
          interval: const Duration(minutes: 3),
          child: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: Selector<BuddyService, int>(
              selector: (_, s) => s.badgeCount,
              builder: (_, n, __) => CustomBottomNav(currentIndex: 0, onTap: (_) {}, badges: {4: n}),
            ),
          ),
        );

    testWidgets('badge = incoming requests + unread; refreshes on start, resume and timer only', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50}
        ..connections = {
          'incoming': [connJson(id: 1, otherId: 11)],
          'outgoing': [connJson(id: 3, otherId: 13)],
          'buddies': [connJson(id: 2, otherId: 12, status: 'accepted', unread: '3')],
        };
      await pumpBuddy(tester, b, badgeHarness());
      final s = tester.element(find.byType(CustomBottomNav)).read<BuddyService>();
      expect(b.count('GET', '/buddy/connections'), 1);
      expect(find.descendant(of: find.byKey(const ValueKey('nav-badge-4')), matching: find.text('4')), findsOneWidget);
      expect(s.badgeUpdatesRunning, isTrue);

      // Background: timer stops.
      for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      expect(s.badgeUpdatesRunning, isFalse);
      await tester.pump(const Duration(minutes: 10));
      expect(b.count('GET', '/buddy/connections'), 1);

      // Resume (after the throttle window): refreshes once.
      s.clock = () => DateTime.now().add(const Duration(hours: 1));
      b.connections = {
        ...b.connections,
        'incoming': [connJson(id: 1, otherId: 11), connJson(id: 4, otherId: 14)]
      };
      for (final st in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/connections'), 2);
      expect(find.text('5'), findsOneWidget);

      // A burst of refresh requests is throttled.
      s.clock = () => DateTime.now().add(const Duration(hours: 1, seconds: 5));
      await s.refreshBadge();
      await s.refreshBadge();
      expect(b.count('GET', '/buddy/connections'), 2);

      // Periodic refresh while foregrounded.
      s.clock = () => DateTime.now().add(const Duration(hours: 2));
      await tester.pump(const Duration(minutes: 3));
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/connections'), 3);

      await tester.pumpWidget(const SizedBox());
      expect(s.badgeUpdatesRunning, isFalse);
    });

    testWidgets('guests and people without a buddy profile never call /connections', (tester) async {
      final guest = FakeBuddyBackend()..loggedIn = false;
      await pumpBuddy(tester, guest, badgeHarness());
      expect(guest.calls, isEmpty);
      expect(find.byKey(const ValueKey('nav-badge-4')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      final noProfile = FakeBuddyBackend();
      await pumpBuddy(tester, noProfile, badgeHarness());
      expect(noProfile.count('GET', '/buddy/profile'), 1);
      expect(noProfile.count('GET', '/buddy/connections'), 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('logging out clears the badge immediately', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..connections = {
          'incoming': [connJson(id: 1, otherId: 11)],
          'outgoing': [],
          'buddies': [],
        };
      await pumpBuddy(tester, b, badgeHarness());
      expect(find.byKey(const ValueKey('nav-badge-4')), findsOneWidget);
      b.loggedIn = false;
      b.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-badge-4')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('connections', () {
    testWidgets('accept clears the badge at once; an older in-flight response cannot undo it', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..connections = {
          'incoming': [connJson(id: 1, otherId: 11)],
          'outgoing': [],
          'buddies': [],
        };
      final s = BuddyService(b);
      addTearDown(s.dispose);
      await s.loadStatus();
      await s.loadConnections();
      expect(s.badgeCount, 1);

      final stale = Completer<void>(), fresh = Completer<void>();
      b.connectionGates.addAll([stale, fresh]);
      final staleLoad = s.loadConnections(); // snapshot still has the request
      b.connections = {
        'incoming': [],
        'outgoing': [],
        'buddies': [connJson(id: 1, otherId: 11, status: 'accepted')],
      };
      await s.accept(1);
      expect(s.badgeCount, 0); // optimistic
      expect(s.connections.buddies.single.id, 1);

      fresh.complete();
      await tester.pump();
      stale.complete(); // the old response arrives last
      await staleLoad;
      await tester.pump();
      expect(s.incomingCount, 0);
      expect(s.connections.buddies, hasLength(1));
    });

    testWidgets('accepting a request that was already withdrawn refreshes the list', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50}
        ..connections = {
          'incoming': [connJson(id: 1, otherId: 11)],
          'outgoing': [],
          'buddies': [],
        };
      BuddyHubTab.sectionNotifier.value = BuddyHubSection.requests;
      addTearDown(() => BuddyHubTab.sectionNotifier.value = BuddyHubSection.discover);
      await pumpBuddy(tester, b, const BuddyHubTab(), width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('Asha, 26'), findsOneWidget);

      b.failures['POST /buddy/connections/1/accept'] =
          const BackendException('This request is no longer pending', statusCode: 409);
      b.connections = {'incoming': [], 'outgoing': [], 'buddies': []};
      await tapText(tester, 'Accept');
      expect(find.text('This request is no longer pending'), findsOneWidget);
      expect(find.text('Asha, 26'), findsNothing);
      expect(find.text('No requests yet'), findsOneWidget);
    });

    testWidgets('blocking someone from Requests removes them immediately', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50}
        ..connections = {
          'incoming': [connJson(id: 1, otherId: 11)],
          'outgoing': [connJson(id: 2, otherId: 12, name: 'Kiran')],
          'buddies': [],
        };
      BuddyHubTab.sectionNotifier.value = BuddyHubSection.requests;
      addTearDown(() => BuddyHubTab.sectionNotifier.value = BuddyHubSection.discover);
      await pumpBuddy(tester, b, const BuddyHubTab());
      await tester.tap(find.byTooltip('More options for Asha'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Block');
      expect(find.text('Block Asha?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Block'));
      await tester.pumpAndSettle();
      expect(b.calls.any((c) => c.$2 == '/buddy/block' && c.$3!['userId'] == 11), isTrue);
      expect(find.text('Asha, 26'), findsNothing);
      expect(find.text('Kiran, 26'), findsOneWidget);
    });

    test('connections JSON tolerates nulls and numbers as strings', () {
      final c = BuddyConnections.fromJson({
        'incoming': null,
        'outgoing': 'nope',
        'buddies': [
          {
            'id': '8',
            'intent': null,
            'status': 'accepted',
            'other': {'userId': '5', 'displayName': null, 'score': null, 'age': '31'},
            'lastMessage': {'body': 'hi', 'createdAt': null, 'mine': 'true'},
            'unread': null,
          }
        ],
      });
      expect(c.incoming, isEmpty);
      expect(c.outgoing, isEmpty);
      final x = c.buddies.single;
      expect(x.id, 8);
      expect(x.intent, BuddyIntent.friend);
      expect(x.other.userId, 5);
      expect(x.other.displayName, 'Buddy');
      expect(x.other.age, 31);
      expect(x.other.score, 0);
      expect(x.lastMessage!.mine, isTrue);
      expect(x.unread, 0);
    });
  });

  group('chat', () {
    BuddyConnection conn() => BuddyConnection.tryParse({
          'id': 9,
          'intent': 'spiritual',
          'status': 'accepted',
          'other': candidateJson(),
        })!;

    testWidgets('ended chat stops polling and hides the composer', (tester) async {
      final b = FakeBuddyBackend()
        ..messages = [
          {'id': 100, 'body': 'Namaste!', 'createdAt': DateTime.now().toIso8601String(), 'mine': false},
        ];
      await pumpBuddy(tester, b, BuddyChatScreen(connection: conn(), highlights: const []));
      expect(find.byType(TextField), findsOneWidget);

      b.failures['GET /buddy/chat/9'] =
          const BackendException('You can chat once the request is accepted', statusCode: 403);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('This chat is no longer available.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final polls = b.count('GET', '/buddy/chat/9');
      await tester.pump(const Duration(seconds: 20));
      expect(b.count('GET', '/buddy/chat/9'), polls);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('chat that is gone on open shows a calm message, no retry loop', (tester) async {
      final b = FakeBuddyBackend()
        ..failures['GET /buddy/chat/9'] = const BackendException('This chat is not available', statusCode: 403);
      await pumpBuddy(tester, b, BuddyChatScreen(connection: conn(), highlights: const []));
      expect(find.text('Chat unavailable'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(b.count('GET', '/buddy/chat/9'), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('double tap on an icebreaker sends it once', (tester) async {
      final b = FakeBuddyBackend();
      await pumpBuddy(tester, b, BuddyChatScreen(connection: conn(), highlights: const []));
      final chip = find.byType(ActionChip).first;
      await tester.tap(chip);
      await tester.tap(chip, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(b.count('POST', '/buddy/chat/9'), 1);
      expect(find.byType(ActionChip), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('double tap on "retry" re-sends once', (tester) async {
      final b = FakeBuddyBackend()
        ..failures['POST /buddy/chat/9'] = const BackendException('Request failed', statusCode: 500);
      await pumpBuddy(tester, b, BuddyChatScreen(connection: conn(), highlights: const []));
      await tester.enterText(find.byType(TextField), 'Hello there');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Not sent · tap to retry'), findsOneWidget);

      b.failures.clear();
      await tester.tap(find.text('Hello there'));
      await tester.tap(find.text('Hello there'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(b.count('POST', '/buddy/chat/9'), 2); // 1 failed + 1 retry
      expect(find.text('Hello there'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('own sends do not move the poll cursor (no skipped replies)', (tester) async {
      final b = FakeBuddyBackend()
        ..messages = [
          {'id': 100, 'body': 'Namaste!', 'createdAt': DateTime.now().toIso8601String(), 'mine': false},
        ];
      await pumpBuddy(tester, b, BuddyChatScreen(connection: conn(), highlights: const []));
      await tester.enterText(find.byType(TextField), 'Hi!');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      final lastPoll = b.calls.lastWhere((c) => c.$1 == 'GET' && c.$2.startsWith('/buddy/chat/9'));
      expect(lastPoll.$2, '/buddy/chat/9?after=100');
      expect(find.text('Hi!'), findsOneWidget); // not duplicated by the poll
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('profile', () {
    testWidgets('a profile that is gone (404) cannot be connected to', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..failures['GET /buddy/user/7'] = const BackendException('This person is not available', statusCode: 404);
      await pumpBuddy(tester, b, BuddyProfileScreen(userId: 7, initial: BuddyCandidate.tryParse(candidateJson())),
          width: 320);
      expect(find.text('This person is not available right now.'), findsOneWidget);
      expect(find.text('Connect with Priya'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a declined request is shown honestly (no dead Connect button)', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..userCandidate = {
          ...candidateJson(),
          'connection': {'id': 5, 'status': 'declined', 'direction': 'outgoing'},
        };
      await pumpBuddy(tester, b, const BuddyProfileScreen(userId: 7));
      expect(find.text("Priya didn't accept your request this time."), findsOneWidget);
      expect(find.text('Connect with Priya'), findsNothing);
    });

    testWidgets('pending incoming request: accept / decline', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..userCandidate = {
          ...candidateJson(),
          'connection': {'id': 5, 'status': 'pending', 'direction': 'incoming'},
        };
      await pumpBuddy(tester, b, const BuddyProfileScreen(userId: 7), width: 320);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(tester.takeException(), isNull);
      b.userCandidate = {
        ...candidateJson(),
        'connection': {'id': 5, 'status': 'accepted', 'direction': 'incoming'},
      };
      await tapText(tester, 'Accept');
      expect(b.count('POST', '/buddy/connections/5/accept'), 1);
      expect(find.text('Message Priya'), findsOneWidget);
    });
  });

  group('nearby watcher', () {
    Widget watcher() => const Scaffold(
          body: NearbyBuddyWatcher(initialDelay: Duration(milliseconds: 10), child: SizedBox.expand()),
        );

    testWidgets('does not check again within 6 hours', (tester) async {
      SharedPreferences.setMockInitialValues({
        NearbyBuddyWatcher.prefsLastCheck: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..nearbyList = [candidateJson()];
      await pumpBuddy(tester, b, watcher());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/nearby'), 0);
      expect(find.textContaining('near you'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only shows people not shown before', (tester) async {
      SharedPreferences.setMockInitialValues({
        NearbyBuddyWatcher.prefsLastCheck: DateTime.now().subtract(const Duration(hours: 7)).millisecondsSinceEpoch,
        NearbyBuddyWatcher.prefsSeenIds: ['7'],
      });
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..nearbyList = [candidateJson(id: 7), candidateJson(id: 8, name: 'Meera Joshi')];
      await pumpBuddy(tester, b, watcher());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('1 buddy near you'), findsOneWidget);
      await tapText(tester, 'Later');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(NearbyBuddyWatcher.prefsSeenIds), ['7', '8']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failing server is not retried on every resume', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..failures['GET /buddy/nearby'] = const BackendException('Request failed', statusCode: 500);
      await pumpBuddy(tester, b, watcher());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/nearby'), 1);
      for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      for (final st in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/nearby'), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('guests: no network calls at all', (tester) async {
      final b = FakeBuddyBackend()..loggedIn = false;
      await pumpBuddy(tester, b, watcher());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(b.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    test('seen ids keep the newest 200 in order', () {
      final existing = [for (var i = 1; i <= 200; i++) '$i'];
      final out = NearbyBuddyWatcher.mergeSeenIds(existing, ['201']);
      expect(out, hasLength(200));
      expect(out.first, '2');
      expect(out.last, '201');
      final again = NearbyBuddyWatcher.mergeSeenIds(['1', '2', '3'], ['2']);
      expect(again, ['1', '3', '2']);
    });
  });

  group('banned', () {
    test('status: BANNED reason / banned flags map to the banned gate', () {
      expect(BuddyStatus.fromJson({'eligible': false, 'reason': 'BANNED', 'banned': true}).gate, BuddyGate.banned);
      final viaProfile = BuddyStatus.fromJson({
        'eligible': true,
        'banned': false,
        'profile': {...profileJson(), 'banned': true},
      });
      expect(viaProfile.gate, BuddyGate.banned);
      expect(viaProfile.eligible, isFalse);
      expect(BuddyStatus.fromJson({'eligible': true, 'banned': false, 'profile': profileJson()}).gate, BuddyGate.none);
    });

    testWidgets('hub shows a calm suspended state, no discover / onboarding / connections', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {
          'profile': {...profileJson(), 'banned': true},
          'eligible': false,
          'reason': 'BANNED',
          'banned': true,
        };
      await pumpBuddy(tester, b, const BuddyHubTab(), width: 320);
      expect(find.text('Buddy profile suspended'), findsOneWidget);
      expect(find.text(BuddyService.bannedMessage), findsOneWidget);
      expect(find.text('Create my buddy profile'), findsNothing);
      expect(find.byTooltip('Profile options'), findsNothing);
      expect(b.count('GET', '/buddy/discover'), 0);
      expect(b.count('GET', '/buddy/connections'), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('403 BANNED from discover flips the hub to the suspended state', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50}
        ..failures['GET /buddy/discover'] = const BackendException('Suspended', statusCode: 403)
        ..failureCodes['GET /buddy/discover'] = 'BANNED';
      await pumpBuddy(tester, b, const BuddyHubTab());
      expect(find.text('Buddy profile suspended'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nearby watcher stops silently when banned', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true}
        ..failures['GET /buddy/nearby'] = const BackendException('Suspended', statusCode: 403)
        ..failureCodes['GET /buddy/nearby'] = 'BANNED';
      await pumpBuddy(
        tester,
        b,
        const Scaffold(
          body: NearbyBuddyWatcher(
            initialDelay: Duration(milliseconds: 10),
            interval: Duration(milliseconds: 100),
            child: SingleChildScrollView(child: BuddyHomeSection()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/nearby'), 1);
      // Even with a tiny interval it never asks again, shows nothing, and Home hides the section.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(b.count('GET', '/buddy/nearby'), 1);
      expect(find.textContaining('near you'), findsNothing);
      expect(find.text('Someone who truly fits you'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('rate limits', () {
    BuddyConnection conn() => BuddyConnection.tryParse({
          'id': 9,
          'intent': 'spiritual',
          'status': 'accepted',
          'other': candidateJson(),
        })!;

    testWidgets('chat 429: friendly snack, text goes back into the input, no failed bubble', (tester) async {
      final b = FakeBuddyBackend()
        ..failures['POST /buddy/chat/9'] = const BackendException('Too many messages', statusCode: 429)
        ..failureCodes['POST /buddy/chat/9'] = 'RATE_LIMITED';
      await pumpBuddy(tester, b, BuddyChatScreen(connection: conn(), highlights: const []));
      await tester.enterText(find.byType(TextField), 'Are you coming to the aarti?');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slow down a little'), findsOneWidget);
      expect(find.text('Not sent · tap to retry'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Are you coming to the aarti?');

      // Later it goes through (once the snack bar has gone).
      b.failures.clear();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(b.count('POST', '/buddy/chat/9'), 2);
      expect(find.text('Are you coming to the aarti?'), findsOneWidget); // the bubble
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('connect 429: friendly message, note is kept, sheet stays open', (tester) async {
      final b = FakeBuddyBackend()
        ..status = {'profile': profileJson(), 'eligible': true, 'quizAnswered': 50}
        ..failures['POST /buddy/connect'] = const BackendException('Too many requests', statusCode: 429)
        ..failureCodes['POST /buddy/connect'] = 'RATE_LIMITED';
      await pumpBuddy(tester, b, const BuddyHubTab());
      await tapText(tester, 'Connect');
      await tester.enterText(find.byType(TextField), 'Namaste, satsang buddies?');
      await tapText(tester, 'Send request');
      expect(find.textContaining("You've sent a lot of requests today"), findsOneWidget);
      expect(find.text('Slow down a little. Try again later.'), findsOneWidget);
      expect(find.text('Connect with Priya'), findsOneWidget); // still open
      expect(find.text('Namaste, satsang buddies?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('under-18: Home does not advertise buddies', (tester) async {
    final b = FakeBuddyBackend()..status = {'eligible': false, 'reason': 'UNDER_18', 'age': 16};
    await pumpBuddy(tester, b, const Scaffold(body: SingleChildScrollView(child: BuddyHomeSection())));
    expect(find.text('Someone who truly fits you'), findsNothing);
    expect(b.count('GET', '/buddy/discover'), 0);
  });
}

Map<String, dynamic> connJson({
  required int id,
  required int otherId,
  String status = 'pending',
  String name = 'Asha',
  Object unread = 0,
}) =>
    {
      'id': id,
      'intent': 'friend',
      'status': status,
      'message': null,
      'createdAt': DateTime.now().toIso8601String(),
      'other': {'userId': otherId, 'displayName': name, 'age': 26, 'city': 'Pune', 'photoUrl': null, 'score': null},
      'unread': unread,
    };
