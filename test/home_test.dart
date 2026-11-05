import 'package:cosmicguide/config/home_promos.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/screens/home_screen.dart';
import 'package:cosmicguide/screens/tabs/home_tab.dart';
import 'package:cosmicguide/screens/videos/videos_screen.dart';
import 'package:cosmicguide/services/buddy_service.dart';
import 'package:cosmicguide/services/rewards_service.dart';
import 'package:cosmicguide/services/video_service.dart';
import 'package:cosmicguide/widgets/custom_bottom_nav.dart';
import 'package:cosmicguide/widgets/home/home_earnings_card.dart';
import 'package:cosmicguide/widgets/home/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wallet backend for the Home earnings card.
class FakeHomeBackend extends BackendService {
  bool authed = true;
  int balance = 1240;
  bool dailyClaimed = false;
  int streak = 3;
  List<Map<String, dynamic>> recent = [];
  bool fail = false;

  @override
  bool get isAuthenticated => authed;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    if (!authed) throw const BackendException('Please log in.', statusCode: 401);
    if (fail) throw const BackendException('Server down', statusCode: 500);
    if ('$method $path' == 'GET /coins') {
      return {
        'balance': balance,
        'goal': 10000,
        'todayEarned': 11,
        'dailyClaimed': dailyClaimed,
        'streakDays': streak,
        'earnRules': [
          {'key': 'daily_login', 'title': 'Daily check-in', 'coins': 1},
          {'key': 'game', 'title': 'Play a game', 'coins': 10},
        ],
        'recent': recent,
      };
    }
    throw BackendException('Not found: $method $path', statusCode: 404);
  }
}

Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  double width = 412,
  double textScale = 1.0,
  BackendService? backend,
  RewardsService? rewards,
}) async {
  tester.view.physicalSize = Size(width, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Widget app = MaterialApp(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: child,
  );
  if (backend != null && rewards != null) {
    app = MultiProvider(providers: [
      ChangeNotifierProvider<BackendService>.value(value: backend),
      ChangeNotifierProvider<RewardsService>.value(value: rewards),
    ], child: app);
  }
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<HomeService> sampleServices(List<String> taps) {
  HomeService s(String id, String label, {String? badge, List<String> keywords = const []}) => HomeService(
        id: id,
        label: label,
        icon: Icons.star_rounded,
        colors: const [Colors.orange, Colors.deepOrange],
        badge: badge,
        keywords: keywords,
        onTap: () => taps.add(id),
      );
  return [
    s('buddy', 'Find buddy', badge: 'NEW', keywords: ['friend', 'partner', 'satsang']),
    s('coins', 'Earn coins', badge: '+1', keywords: ['reward', 'temple']),
    s('videos', 'Videos', badge: 'NEW', keywords: ['bhajan', 'aarti', 'katha']),
    s('games', 'Games', badge: '+10', keywords: ['play']),
    s('ai', 'Ask AI', badge: 'FREE', keywords: ['chat']),
    s('kundli', 'Kundli', keywords: ['chart', 'birth']),
    s('panchang', 'Panchang', keywords: ['tithi', 'festival']),
    s('pandit', 'Talk to pandit', badge: 'LIVE', keywords: ['live', 'expert']),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---------------------------------------------------------------- promos
  test('promo carousel leads with buddy, temple trip, videos and rewards', () {
    expect(kHomePromos.length, greaterThanOrEqualTo(4));
    expect(kHomePromos[0].action, isA<PromoTab>());
    expect((kHomePromos[0].action as PromoTab).index, 4);
    expect(kHomePromos[1].action, isA<PromoTempleTrip>());
    expect(kHomePromos[2].action, isA<PromoVideos>());
    expect(kHomePromos[3].action, isA<PromoCoins>());
    // Astrology slides are still there, after the super-app ones.
    expect(kHomePromos.skip(4).map((p) => p.action.runtimeType),
        containsAll([PromoAiChat, PromoKundliReport, PromoKundliMatch]));
  });

  // ---------------------------------------------------------------- search matching
  group('service search', () {
    test('matches by label and keyword, best first', () {
      final services = sampleServices([]);
      expect(matchHomeServices('bhajan', services).first.id, 'videos');
      expect(matchHomeServices('kun', services).first.id, 'kundli');
      expect(matchHomeServices('pandit', services).first.id, 'pandit');
      expect(matchHomeServices('satsang friend', services).first.id, 'buddy');
      expect(matchHomeServices('zzqx', services), isEmpty);
      expect(matchHomeServices('', services).length, services.length);
    });

    testWidgets('sheet opens a matching service, and asks AI with the query', (tester) async {
      final taps = <String>[];
      final asked = <String?>[];
      final services = sampleServices(taps);
      await pumpAt(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHomeSearch(context, services: services, onAskAi: asked.add),
              child: const Text('open'),
            ),
          ),
        ),
        width: 320,
        textScale: 1.3,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeSearchSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('home-search-ask-ai')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('home-search-field')), 'bhajan');
      await tester.pump();
      expect(find.byKey(const ValueKey('home-search-videos')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-search-kundli')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-search-videos')));
      await tester.pumpAndSettle();
      expect(taps, ['videos']);
      expect(find.byType(HomeSearchSheet), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('home-search-field')), 'will I marry soon');
      await tester.pump();
      expect(find.text('Ask AI: "will I marry soon"'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-search-ask-ai')));
      await tester.pumpAndSettle();
      expect(asked, ['will I marry soon']);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------- services grid
  group('services grid', () {
    for (final (width, scale) in [(320.0, 1.3), (412.0, 1.0)]) {
      testWidgets('8 tiles route correctly at ${width.toInt()}px / ${scale}x', (tester) async {
        final taps = <String>[];
        final services = sampleServices(taps);
        await pumpAt(
          tester,
          Scaffold(body: ListView(children: [HomeServicesGrid(services: services)])),
          width: width,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('EVERYTHING IN ONE APP'), findsOneWidget);
        for (final s in services) {
          expect(find.byKey(ValueKey('home-service-${s.id}')), findsOneWidget);
        }
        expect(find.text('NEW'), findsNWidgets(2));
        expect(find.text('+10'), findsOneWidget);

        // Two rows of four.
        final y0 = tester.getTopLeft(find.byKey(const ValueKey('home-service-buddy'))).dy;
        final y3 = tester.getTopLeft(find.byKey(const ValueKey('home-service-games'))).dy;
        final y4 = tester.getTopLeft(find.byKey(const ValueKey('home-service-ai'))).dy;
        expect(y3, y0);
        expect(y4, greaterThan(y0));

        for (final s in services) {
          await tester.tap(find.byKey(ValueKey('home-service-${s.id}')));
        }
        expect(taps, services.map((s) => s.id).toList());
      });
    }

    testWidgets('pinned bar fits its search + chips at 320px / 1.3x', (tester) async {
      final taps = <String>[];
      var searched = 0;
      var ai = 0;
      await pumpAt(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Column(children: [
              SizedBox(
                height: HomeStickyBar.heightFor(context),
                child: HomeStickyBar(
                  hints: const ['buddies, bhajans, games, kundli…'],
                  onSearch: () => searched++,
                  onAi: () => ai++,
                  shortcuts: sampleServices(taps),
                ),
              ),
            ]),
          ),
        ),
        width: 320,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Search '), findsOneWidget);
      expect(find.text('buddies, bhajans, games, kundli…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.tap(find.bySemanticsLabel('Chat with AI astrologer'));
      await tester.tap(find.byKey(const ValueKey('home-chip-buddy')));
      expect(searched, 1);
      expect(ai, 1);
      expect(taps, ['buddy']);
    });
  });

  // ---------------------------------------------------------------- earnings card
  group('daily earnings card', () {
    late List<String> actions;
    Widget card() => Scaffold(
          body: ListView(children: [
            HomeEarningsCard(
              onCheckIn: () => actions.add('checkin'),
              onPlayGame: () => actions.add('game'),
              onWatchVideo: () => actions.add('video'),
              onAnswerQuestion: () => actions.add('question'),
              onOpenCoins: () => actions.add('coins'),
              onOpenTrip: () => actions.add('trip'),
            ),
          ]),
        );
    setUp(() => actions = []);

    for (final (width, scale) in [(320.0, 1.3), (412.0, 1.0)]) {
      testWidgets('balance, trip progress and checklist at ${width.toInt()}px / ${scale}x', (tester) async {
        final now = DateTime.now().toUtc();
        final b = FakeHomeBackend()
          ..recent = [
            {'id': 1, 'amount': 10, 'reason': 'game', 'ref': 'quest', 'createdAt': now.toIso8601String()},
            // Yesterday's answer doesn't tick today's row.
            {
              'id': 2,
              'amount': 50,
              'reason': 'question',
              'ref': 'q1',
              'createdAt': now.subtract(const Duration(days: 2)).toIso8601String()
            },
          ];
        final r = RewardsService(b);
        await pumpAt(tester, card(), width: width, textScale: scale, backend: b, rewards: r);
        await settle(tester);
        expect(tester.takeException(), isNull);

        expect(find.byKey(const ValueKey('home-earnings')), findsOneWidget);
        expect(find.text('8,760 more for a free temple trip'), findsOneWidget);
        expect(find.text('12%'), findsOneWidget);
        expect(find.text('🔥 3-day'), findsOneWidget);
        expect(find.bySemanticsLabel('Daily check-in, earn 1 coins'), findsOneWidget);
        expect(find.bySemanticsLabel('Play a game, done today'), findsOneWidget);
        expect(find.bySemanticsLabel('Watch a new video, earn 1 coins'), findsOneWidget);
        expect(find.bySemanticsLabel('Answer a mindset question, earn 50 coins'), findsOneWidget);

        for (final id in ['checkin', 'game', 'video', 'question']) {
          await tester.ensureVisible(find.byKey(ValueKey('earn-task-$id')));
          await tester.tap(find.byKey(ValueKey('earn-task-$id')));
        }
        await tester.tap(find.byKey(const ValueKey('home-earnings-trip')));
        await tester.tap(find.byKey(const ValueKey('home-earnings-balance')));
        expect(actions, ['checkin', 'game', 'video', 'question', 'trip', 'coins']);
      });
    }

    testWidgets('claimed check-in shows as done and opens the wallet', (tester) async {
      final b = FakeHomeBackend()..dailyClaimed = true;
      final r = RewardsService(b);
      await pumpAt(tester, card(), width: 320, textScale: 1.3, backend: b, rewards: r);
      await settle(tester);
      expect(find.bySemanticsLabel('Checked in today, done today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('earn-task-checkin')));
      expect(actions, ['coins']);
    });

    testWidgets('guests see the invitation, which opens coins', (tester) async {
      final b = FakeHomeBackend()..authed = false;
      final r = RewardsService(b);
      await pumpAt(tester, card(), width: 320, textScale: 1.3, backend: b, rewards: r);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-earnings-guest')), findsOneWidget);
      expect(find.text('Earn coins every day'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-earnings-guest')));
      expect(actions, ['coins']);
    });

    testWidgets('a wallet error offers retry', (tester) async {
      final b = FakeHomeBackend()..fail = true;
      final r = RewardsService(b);
      await pumpAt(tester, card(), backend: b, rewards: r);
      await settle(tester);
      expect(find.text("Couldn't load your coins"), findsOneWidget);
      b.fail = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-earnings')), findsOneWidget);
    });

    test('earnedToday uses the IST day', () {
      final b = FakeHomeBackend();
      final r = RewardsService(b)
        ..recent = [
          CoinEntry(id: '1', amount: 1, reason: 'video', createdAt: DateTime.utc(2026, 11, 4, 19, 0)), // 00:30 IST 5th
        ];
      expect(HomeEarningsCard.earnedToday(r, 'video', DateTime.utc(2026, 11, 5, 6)), isTrue);
      expect(HomeEarningsCard.earnedToday(r, 'video', DateTime.utc(2026, 11, 6, 6)), isFalse);
      expect(HomeEarningsCard.earnedToday(r, 'game', DateTime.utc(2026, 11, 5, 6)), isFalse);
    });
  });

  // ---------------------------------------------------------------- home screen tabs
  testWidgets('Videos is tab 5 with no back button; back returns Home; Kundli tab 1 still opens',
      (tester) async {
    final b = FakeHomeBackend()..dailyClaimed = true;
    final r = RewardsService(b);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<BackendService>.value(value: b),
        ChangeNotifierProvider<RewardsService>.value(value: r),
        ChangeNotifierProvider<VideoService>(create: (_) => VideoService(b)),
        ChangeNotifierProvider<BuddyService>(create: (_) => BuddyService(b)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await settle(tester);
    expect(find.byType(HomeTab), findsOneWidget);

    await tester.tap(find.text('Videos').last);
    await settle(tester);
    expect(find.byType(VideosScreen), findsOneWidget);
    expect(find.text('Bhakti videos'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(tester.takeException(), isNull);

    // System back from a tab goes Home first.
    await tester.binding.handlePopRoute();
    await settle(tester);
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack).first);
    expect(stack.index, 0);

    // Kundli (tab 1) is reachable by index even without a nav slot.
    HomeScreen.switchTab(tester.element(find.byType(HomeTab)), 1);
    await settle(tester);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack).first).index, 1);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  // ---------------------------------------------------------------- whole Home tab
  group('home tab', () {
    for (final (width, scale) in [(320.0, 1.3), (412.0, 1.0)]) {
      testWidgets('renders the new feed order and routes the grid at ${width.toInt()}px / ${scale}x',
          (tester) async {
        final b = FakeHomeBackend()..dailyClaimed = true;
        final r = RewardsService(b);
        final tabs = <int>[];
        tester.view.physicalSize = Size(width, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<BackendService>.value(value: b),
            ChangeNotifierProvider<RewardsService>.value(value: r),
            ChangeNotifierProvider<VideoService>(create: (_) => VideoService(b)),
            ChangeNotifierProvider<BuddyService>(create: (_) => BuddyService(b)),
          ],
          child: MaterialApp(
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: c!,
            ),
            routes: {
              '/games': (_) => const Scaffold(body: Text('ROUTE:/games')),
              '/panchang': (_) => const Scaffold(body: Text('ROUTE:/panchang')),
              '/chatbot': (_) => const Scaffold(body: Text('ROUTE:/chatbot')),
            },
            home: HomeTab(onNavigateTab: tabs.add),
          ),
        ));
        await settle(tester);
        expect(tester.takeException(), isNull);

        // Grid sits right below the header, before buddies and earnings.
        final grid = find.byType(HomeServicesGrid);
        expect(grid, findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('home-service-kundli')));
        await tester.tap(find.byKey(const ValueKey('home-service-videos')));
        await tester.tap(find.byKey(const ValueKey('home-service-buddy')));
        await tester.tap(find.byKey(const ValueKey('home-service-pandit')));
        expect(tabs, [1, 5, 4, 3]);

        // Scroll the whole feed: no overflow anywhere, sections in order.
        final scrollable = find.byType(Scrollable).first;
        double? yOf(Finder f) => f.evaluate().isEmpty ? null : tester.getTopLeft(f.first).dy;
        final seen = <String, double>{};
        const titles = ['DAILY EARNINGS', 'PLAY & EARN', 'YOUR DAY', 'ASK AI ANYTHING', "TODAY'S SKY", 'EXPLORE MORE'];
        var offset = 0.0;
        for (var i = 0; i < 60 && seen.length < titles.length; i++) {
          for (final t in titles) {
            final y = yOf(find.text(t));
            if (y != null) seen.putIfAbsent(t, () => y + offset);
          }
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 50));
          offset += 300;
          expect(tester.takeException(), isNull);
        }
        expect(seen.keys.toSet(), titles.toSet());
        for (var i = 1; i < titles.length; i++) {
          expect(seen[titles[i]]!, greaterThan(seen[titles[i - 1]]!), reason: '${titles[i]} after ${titles[i - 1]}');
        }
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      });
    }
  });

  // ---------------------------------------------------------------- bottom nav
  group('bottom nav', () {
    for (final (width, scale) in [(320.0, 1.3), (412.0, 1.0)]) {
      testWidgets('Home · Buddy · Ask AI · Videos · More at ${width.toInt()}px / ${scale}x', (tester) async {
        final taps = <int>[];
        await pumpAt(
          tester,
          Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: CustomBottomNav(currentIndex: 0, onTap: taps.add, badges: const {4: 2}),
          ),
          width: width,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        final labels = ['Home', 'Buddy', 'Ask AI', 'Videos', 'More'];
        final xs = [for (final l in labels) tester.getCenter(find.text(l)).dx];
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i], greaterThan(xs[i - 1]), reason: '${labels[i]} should be right of ${labels[i - 1]}');
        }
        expect(find.text('Kundli'), findsNothing);
        for (final l in labels) {
          await tester.tap(find.text(l));
        }
        expect(taps, [0, 4, 3, 5, 2]);
        expect(find.bySemanticsLabel('Buddy tab, 2 new'), findsOneWidget);
        expect(find.bySemanticsLabel('Videos tab'), findsOneWidget);
        expect(find.bySemanticsLabel('Ask AI tab'), findsOneWidget);
      });
    }

    testWidgets('Videos tab is highlighted at index 5; Kundli (1) highlights nothing', (tester) async {
      var index = 5;
      late StateSetter set;
      await pumpAt(
        tester,
        StatefulBuilder(builder: (context, setState) {
          set = setState;
          return Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: CustomBottomNav(currentIndex: index, onTap: (_) {}),
          );
        }),
      );
      FontWeight weight(String label) => tester.widget<Text>(find.text(label)).style!.fontWeight!;
      expect(weight('Videos'), FontWeight.w700);
      expect(weight('Home'), FontWeight.w500);

      set(() => index = 1);
      await tester.pump();
      for (final l in ['Home', 'Buddy', 'Videos', 'More']) {
        expect(weight(l), FontWeight.w500);
      }
    });
  });
}
