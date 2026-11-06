import 'package:cosmicguide/screens/jap/jap_counter_screen.dart';
import 'package:cosmicguide/screens/jap/jap_widgets.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/jap_service.dart';
import 'package:cosmicguide/services/notification_service.dart';
import 'package:cosmicguide/services/rewards_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Simulates POST /coins/jap and GET /coins/jap/today with the server rules
/// (5 coins, 3 a day per IST day, >= 90 s apart).
class FakeJapBackend extends BackendService {
  bool authed = true;
  int userId = 1;
  bool offline = false;
  DateTime Function() clock;
  final List<String> calls = [];
  final Map<String, List<DateTime>> paid = {}; // '<user>:<ist day>' -> paid times
  int balance = 100;

  FakeJapBackend(this.clock);

  @override
  bool get isAuthenticated => authed;
  @override
  Map<String, dynamic>? get user => authed ? {'id': userId, 'fullName': 'Asha Rao'} : null;

  void signIn(bool v, {int id = 1}) {
    authed = v;
    userId = id;
    notifyListeners();
  }

  List<DateTime> get _today => paid.putIfAbsent('$userId:${istDayKey(clock())}', () => []);

  int count(String c) => calls.where((x) => x == c).length;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add('$method $path');
    if (offline) throw const BackendException('No internet connection');
    if (!authed) throw const BackendException('Please log in to earn and use coins.', statusCode: 401);
    final today = _today;
    if (method == 'GET' && path == '/coins/jap/today') {
      return {'paidToday': today.length, 'cap': 3, 'coinsPerMala': 5, 'dailyCapReached': today.length >= 3};
    }
    if (method == 'POST' && path == '/coins/jap') {
      if (today.length >= 3) return {'awarded': 0, 'balance': balance, 'paidToday': 3, 'cap': 3, 'dailyCapReached': true};
      if (today.isNotEmpty && clock().difference(today.last).inSeconds < 90) {
        throw const BackendException('Take your time with the mala.', statusCode: 429);
      }
      today.add(clock());
      balance += 5;
      return {'awarded': 5, 'balance': balance, 'paidToday': today.length, 'cap': 3, 'dailyCapReached': today.length >= 3};
    }
    if (method == 'GET' && path == '/coins') {
      return {'balance': balance, 'goal': 10000, 'todayEarned': 0, 'dailyClaimed': true, 'streakDays': 1, 'earnRules': [], 'recent': []};
    }
    throw BackendException('Not found: $method $path', statusCode: 404);
  }
}

class Clock {
  DateTime t;
  Clock(this.t);
  DateTime call() => t;
  void advance(Duration d) => t = t.add(d);
}

class FakeLocal implements LocalNotifier {
  final Map<int, PlannedNotification> scheduled = {};
  bool? granted = true;
  bool grantOnRequest = false;
  @override
  Future<void> init(void Function(Map<String, dynamic> data) onTap) async {}
  @override
  Future<Map<String, dynamic>?> launchPayload() async => null;
  @override
  Future<void> show(int id, String title, String body, String channel, Map<String, String> payload) async {}
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;
  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<bool?> permissionGranted() async => granted;
  @override
  Future<bool> requestPermission() async {
    if (grantOnRequest) granted = true;
    return grantOnRequest;
  }

  @override
  Future<void> openSettings() async {}
}

Future<void> drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Taps until the current mala completes; returns how many taps completed one.
int finishMala(JapService s) {
  var completed = 0;
  final left = JapService.malaSize - s.count;
  for (var i = 0; i < left; i++) {
    if (s.tap()) completed++;
  }
  return completed;
}

// 10:00 IST
final start = DateTime.utc(2026, 11, 5, 4, 30).toLocal();

Future<(JapService, FakeJapBackend, Clock)> make({bool authed = true, Clock? clock, FakeJapBackend? backend}) async {
  final c = clock ?? Clock(start);
  final b = backend ?? (FakeJapBackend(c.call)..authed = authed);
  final s = JapService(b, clock: c.call, retryDelay: const Duration(seconds: 45));
  await s.load();
  await drain();
  return (s, b, c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('counting', () {
    test('taps count up per mantra, undo and reset', () async {
      final (s, b, _) = await make(authed: false);
      addTearDown(s.dispose);
      expect(s.count, 0);
      expect(s.tap(), isFalse);
      s.tap();
      s.tap();
      expect(s.count, 3);
      expect(s.undo(), isTrue);
      expect(s.count, 2);
      s.select('gayatri');
      expect(s.count, 0, reason: 'each mantra keeps its own count');
      s.tap();
      expect(s.undo(), isTrue);
      expect(s.undo(), isFalse, reason: 'undo at zero is a no-op');
      s.select('shiva');
      expect(s.count, 2);
      s.reset();
      expect(s.count, 0);
      expect(b.calls, isEmpty, reason: 'guests never call the server');
    });

    test('108 taps complete a mala, count restarts and stats update', () async {
      final (s, _, _) = await make(authed: false);
      addTearDown(s.dispose);
      expect(finishMala(s), 1);
      expect(s.count, 0);
      expect(s.todayMalas, 1);
      expect(s.totalMalas, 1);
      expect(s.streak, 1);
      expect(s.lastCoinStatus, JapCoinStatus.signInToEarn);
    });

    test('in-progress counts, mantra, custom text and settings persist', () async {
      final (s, _, c) = await make(authed: false);
      for (var i = 0; i < 40; i++) {
        s.tap();
      }
      s.select('hanuman');
      s.tap();
      s.setCustomText('  Radhe   Radhe ');
      s.tap();
      s.tap();
      s.setSound(true);
      finishMala(s); // custom mala done
      await drain();
      s.dispose();

      final (s2, _, _) = await make(authed: false, clock: c);
      addTearDown(s2.dispose);
      expect(s2.selectedId, JapService.customId);
      expect(s2.customText, 'Radhe Radhe');
      expect(s2.mantra.transliteration, 'Radhe Radhe');
      expect(s2.count, 0);
      expect(s2.countFor('shiva'), 40);
      expect(s2.countFor('hanuman'), 1);
      expect(s2.soundOn, isTrue);
      expect(s2.totalMalas, 1);
      expect(s2.todayMalas, 1);
    });

    test('corrupt saved state starts fresh', () async {
      SharedPreferences.setMockInitialValues({JapService.prefsKey: '{not json'});
      final (s, _, _) = await make(authed: false);
      addTearDown(s.dispose);
      expect(s.loaded, isTrue);
      expect(s.count, 0);
    });
  });

  group('streak and history', () {
    test('japStreak counts consecutive days ending today or yesterday', () {
      final today = DateTime(2026, 11, 5);
      expect(japStreak({}, today), 0);
      expect(japStreak({'2026-11-05': 1}, today), 1);
      expect(japStreak({'2026-11-05': 2, '2026-11-04': 1, '2026-11-03': 1, '2026-11-01': 4}, today), 3);
      expect(japStreak({'2026-11-04': 1, '2026-11-03': 1}, today), 2, reason: 'yesterday still counts');
      expect(japStreak({'2026-11-03': 1}, today), 0, reason: 'a missed day breaks it');
      expect(japStreak({'2026-10-31': 1, '2026-11-01': 1}, DateTime(2026, 11, 1)), 2, reason: 'across months');
      expect(japStreak({'2026-11-05': 0, '2026-11-04': 1}, today), 1, reason: 'zero days do not count');
    });

    test('streak and last 7 days follow the injected clock across days', () async {
      final c = Clock(DateTime(2026, 11, 2, 7));
      final (s, _, _) = await make(authed: false, clock: c);
      addTearDown(s.dispose);
      finishMala(s);
      c.advance(const Duration(days: 1));
      finishMala(s);
      finishMala(s);
      expect(s.streak, 2);
      expect(s.todayMalas, 2);
      c.advance(const Duration(days: 1));
      expect(s.todayMalas, 0);
      expect(s.streak, 2, reason: 'still alive until today ends');
      c.advance(const Duration(days: 1));
      expect(s.streak, 0);
      final week = s.last7Days;
      expect(week.length, 7);
      expect(week.last.day, DateTime(2026, 11, 5));
      expect(week.map((d) => d.malas).toList(), [0, 0, 0, 1, 2, 0, 0]);
      expect(s.totalMalas, 3);
    });
  });

  group('coins', () {
    test('completing a mala claims once and reports the award', () async {
      final (s, b, c) = await make();
      addTearDown(s.dispose);
      expect(b.count('GET /coins/jap/today'), 1);
      final awards = <JapAward>[];
      final sub = s.awards.listen(awards.add);
      addTearDown(sub.cancel);
      for (var i = 0; i < 107; i++) {
        s.tap();
      }
      expect(b.count('POST /coins/jap'), 0);
      expect(s.tap(), isTrue);
      await drain();
      expect(b.count('POST /coins/jap'), 1);
      expect(s.lastCoinStatus, JapCoinStatus.awarded);
      expect(s.lastAwarded, 5);
      expect(s.paidToday, 1);
      expect(awards.single.amount, 5);
      expect(awards.single.balance, 105);
      // more beads of the next mala do not claim again
      c.advance(const Duration(seconds: 30));
      s.tap();
      s.undo();
      await drain();
      expect(b.count('POST /coins/jap'), 1);
    });

    test('updates the RewardsService wallet with the server balance', () async {
      final c = Clock(start);
      final b = FakeJapBackend(c.call);
      final rewards = RewardsService(b);
      addTearDown(rewards.dispose);
      await rewards.refresh();
      expect(rewards.balance, 100);
      final s = JapService(b, rewards: rewards, clock: c.call);
      addTearDown(s.dispose);
      await s.load();
      await drain();
      finishMala(s);
      await drain();
      expect(rewards.balance, 105);
      expect(rewards.recent.first.reason, 'jap_mala');
    });

    test('stops claiming at the daily cap of 3', () async {
      final (s, b, c) = await make();
      addTearDown(s.dispose);
      for (var i = 0; i < 3; i++) {
        finishMala(s);
        await drain();
        c.advance(const Duration(minutes: 2));
      }
      expect(s.paidToday, 3);
      expect(s.dailyCapReached, isTrue);
      expect(b.count('POST /coins/jap'), 3);
      finishMala(s);
      await drain();
      expect(b.count('POST /coins/jap'), 3, reason: 'no request once capped');
      expect(s.lastCoinStatus, JapCoinStatus.capReached);
      expect(s.todayMalas, 4, reason: 'counting continues unpaid');
    });

    test('server cap from another device is respected', () async {
      final c = Clock(start);
      final b = FakeJapBackend(c.call);
      b.paid['1:${istDayKey(start)}'] = [start, start, start];
      final (s, _, _) = await make(clock: c, backend: b);
      addTearDown(s.dispose);
      expect(s.paidToday, 3);
      finishMala(s);
      await drain();
      expect(b.count('POST /coins/jap'), 0);
      expect(s.lastCoinStatus, JapCoinStatus.capReached);
    });

    test('a second mala within 90 s is retried after the gap', () async {
      final (s, b, c) = await make();
      addTearDown(s.dispose);
      finishMala(s);
      await drain();
      c.advance(const Duration(seconds: 40));
      finishMala(s);
      await drain();
      expect(b.count('POST /coins/jap'), 2);
      expect(s.paidToday, 1);
      expect(s.pendingClaims, 1);
      expect(s.retryScheduled, isTrue);
      c.advance(const Duration(seconds: 55));
      await s.flush();
      expect(s.paidToday, 2);
      expect(s.pendingClaims, 0);
    });

    test('offline claims are queued, survive restarts and are sent later', () async {
      final (s, b, c) = await make();
      b.offline = true;
      finishMala(s);
      await drain();
      expect(s.pendingClaims, 1);
      expect(s.offline, isTrue);
      expect(s.lastCoinStatus, JapCoinStatus.queuedOffline);
      expect(s.retryScheduled, isTrue);
      c.advance(const Duration(minutes: 2));
      finishMala(s);
      c.advance(const Duration(minutes: 2));
      finishMala(s);
      c.advance(const Duration(minutes: 2));
      finishMala(s);
      await drain();
      expect(s.pendingClaims, 3, reason: 'never more than the daily cap queued');
      s.dispose();

      b.offline = false;
      final (s2, _, _) = await make(clock: c, backend: b);
      addTearDown(s2.dispose);
      // Sent after load; the server's 90 s rule paces the burst, the rest retry later.
      expect(s2.paidToday, 1);
      expect(s2.pendingClaims, 2);
      expect(s2.retryScheduled, isTrue);
      c.advance(const Duration(seconds: 91));
      await s2.flush();
      c.advance(const Duration(seconds: 91));
      await s2.flush();
      expect(s2.pendingClaims, 0);
      expect(s2.paidToday, 3);
      expect(b.balance, 115);
    });

    test('queued claims from an earlier IST day are dropped', () async {
      final (s, b, c) = await make();
      addTearDown(s.dispose);
      b.offline = true;
      finishMala(s);
      await drain();
      expect(s.pendingClaims, 1);
      c.advance(const Duration(days: 1));
      b.offline = false;
      final before = b.count('POST /coins/jap');
      await s.flush();
      expect(b.count('POST /coins/jap'), before);
      expect(s.pendingClaims, 0);
      expect(s.paidToday, 0);
    });

    test('signing out drops queued claims and paid count', () async {
      final (s, b, _) = await make();
      addTearDown(s.dispose);
      finishMala(s);
      await drain();
      expect(s.paidToday, 1);
      b.offline = true;
      finishMala(s);
      await drain();
      expect(s.pendingClaims, 1);
      final posts = b.count('POST /coins/jap');
      b.signIn(false);
      expect(s.paidToday, 0);
      expect(s.pendingClaims, 0);
      b.offline = false;
      b.signIn(true, id: 2);
      await drain();
      expect(s.paidToday, 0, reason: 'the second account has its own count');
      expect(b.count('POST /coins/jap'), posts, reason: 'nothing sent for the new account');
      expect(b.balance, 105);
      expect(s.todayMalas, 2, reason: 'device practice stats stay');
    });

    test('guest completion never calls the server', () async {
      final (s, b, _) = await make(authed: false);
      addTearDown(s.dispose);
      finishMala(s);
      await drain();
      expect(b.calls, isEmpty);
      expect(s.lastCoinStatus, JapCoinStatus.signInToEarn);
      expect(s.paidToday, 0);
    });
  });

  group('reminder', () {
    test('setReminder stores the time and reports denial', () async {
      final calls = <(bool, int, int)>[];
      var allow = true;
      final b = FakeJapBackend(() => start)..authed = false;
      final s = JapService(b, reminderScheduler: ({required enabled, required hour, required minute}) async {
        calls.add((enabled, hour, minute));
        return allow;
      });
      addTearDown(s.dispose);
      await s.load();
      expect(await s.setReminder(true, hour: 5, minute: 45), isTrue);
      expect(s.reminderOn, isTrue);
      expect((s.reminderHour, s.reminderMinute), (10, 45), reason: 'kept inside 10:00-22:00');
      allow = false;
      expect(await s.setReminder(true, hour: 7, minute: 0), isFalse);
      expect(s.reminderOn, isFalse);
      allow = true;
      await s.setReminder(false);
      expect(calls.last, (false, 10, 0));
    });

    test('NotificationService.setJapReminder schedules a daily jap reminder', () async {
      tz_data.initializeTimeZones();
      final ist = tz.getLocation('Asia/Kolkata');
      final local = FakeLocal();
      final n = NotificationService(local: local, clock: () => tz.TZDateTime(ist, 2026, 11, 5, 10, 0));
      addTearDown(n.dispose);
      expect(await n.setJapReminder(enabled: true, hour: 6, minute: 30), isTrue);
      final p = local.scheduled[NotificationService.japReminderId]!;
      expect(p.payload['type'], 'jap');
      expect(p.repeat, NotificationRepeat.daily);
      expect(p.when, tz.TZDateTime(ist, 2026, 11, 5, 10, 30), reason: '06:30 is moved into the 10:00-22:00 window');
      expect(NotificationIds.managed.contains(NotificationService.japReminderId), isFalse);
      expect(await n.setJapReminder(enabled: true, hour: 19, minute: 0), isTrue);
      expect(local.scheduled[NotificationService.japReminderId]!.when, tz.TZDateTime(ist, 2026, 11, 5, 19, 0));
      expect(await n.setJapReminder(enabled: false, hour: 19, minute: 0), isTrue);
      expect(local.scheduled, isEmpty);
      local.granted = false;
      expect(await n.setJapReminder(enabled: true, hour: 6, minute: 0), isFalse);
      expect(local.scheduled, isEmpty);
    });
  });

  group('widgets', () {
    Future<JapService> pumpJap(WidgetTester tester, Widget child,
        {required FakeJapBackend backend, Size size = const Size(320, 568), Clock? clock}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final c = clock ?? Clock(start);
      final s = JapService(backend, clock: c.call);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<BackendService>.value(value: backend),
          ChangeNotifierProvider<JapService>.value(value: s),
        ],
        child: MaterialApp(
          builder: (context, w) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: w!,
          ),
          routes: {'/login': (_) => const Scaffold(body: Text('ROUTE:/login'))},
          home: child,
        ),
      ));
      await tester.pump();
      await tester.pump();
      return s;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('counter at 320px / 1.3x: tap, undo, complete', (tester) async {
      final b = FakeJapBackend(() => start);
      final s = await pumpJap(tester, const JapCounterScreen(), backend: b);
      addTearDown(s.dispose);
      await settle(tester);
      expect(find.text('ॐ नमः शिवाय'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      final area = find.byKey(const ValueKey('jap-tap-area'));
      await tester.tap(area);
      await tester.tap(area);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Undo last'));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(s.count, 1);
      for (var i = 0; i < 106; i++) {
        s.tap();
      }
      await tester.pump();
      expect(find.text('107'), findsOneWidget);
      await tester.tap(area);
      await settle(tester);
      expect(find.text('Mala complete'), findsOneWidget);
      expect(find.textContaining('+5 coins'), findsWidgets);
      expect(b.count('POST /coins/jap'), 1);
      expect(find.text('Coins 1/3 today'), findsOneWidget);
      // the next tap only dismisses the card
      await tester.tap(area);
      await settle(tester);
      expect(find.text('Mala complete'), findsNothing);
      expect(s.count, 0);
      await tester.pump(const Duration(seconds: 3)); // coin toast finishes
      expect(tester.takeException(), isNull);
    });

    testWidgets('guest sees "Sign in to earn coins" and can still count', (tester) async {
      final b = FakeJapBackend(() => start)..authed = false;
      final s = await pumpJap(tester, const JapCounterScreen(), backend: b);
      addTearDown(s.dispose);
      await settle(tester);
      expect(find.text('Sign in to earn coins'), findsOneWidget);
      for (var i = 0; i < 107; i++) {
        s.tap();
      }
      await tester.tap(find.byKey(const ValueKey('jap-tap-area')));
      await settle(tester);
      expect(find.text('Mala complete'), findsOneWidget);
      expect(find.textContaining('Sign in to earn coins for every mala'), findsOneWidget);
      expect(b.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('jap-sign-in')));
      await settle(tester);
      expect(find.text('ROUTE:/login'), findsOneWidget);
    });

    testWidgets('mantra picker and practice sheet at 320px', (tester) async {
      final b = FakeJapBackend(() => start)..authed = false;
      final s = await pumpJap(tester, const JapCounterScreen(), backend: b, size: const Size(320, 640));
      addTearDown(s.dispose);
      await settle(tester);
      await tester.tap(find.text('ॐ नमः शिवाय'));
      await settle(tester);
      expect(find.text('Choose a mantra'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Om Hanumate Namah'), 200,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
      await tester.tap(find.text('Om Hanumate Namah'));
      await settle(tester);
      expect(s.selectedId, 'hanuman');
      expect(find.text('ॐ हनुमते नमः'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.insights_rounded));
      await settle(tester);
      expect(find.text('Your practice'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.byType(JapWeekChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('counter at 412px renders without overflow', (tester) async {
      final b = FakeJapBackend(() => start);
      final s = await pumpJap(tester, const JapCounterScreen(), backend: b, size: const Size(412, 892));
      addTearDown(s.dispose);
      await settle(tester);
      s.select('gayatri');
      await tester.pump();
      expect(find.byType(JapBeadRing), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('home card shows progress and opens via onOpen', (tester) async {
      final b = FakeJapBackend(() => start)..authed = false;
      var opened = 0;
      final s = await pumpJap(
        tester,
        Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: JapHomeCard(onOpen: () => opened++))),
        backend: b,
      );
      addTearDown(s.dispose);
      await settle(tester);
      expect(find.text('Start jap'), findsOneWidget);
      s.tap();
      await tester.pump();
      expect(find.text('Continue jap'), findsOneWidget);
      finishMala(s);
      await tester.pump();
      expect(find.textContaining('1 mala today'), findsOneWidget);
      expect(find.textContaining('1-day streak'), findsOneWidget);
      await tester.tap(find.text('Start jap'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
