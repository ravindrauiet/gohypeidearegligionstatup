import 'dart:async';

import 'package:cosmicguide/screens/legal/community_guidelines_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/rewards_service.dart';
import 'package:cosmicguide/screens/rewards/coins_screen.dart';
import 'package:cosmicguide/screens/rewards/mindset_quiz_screen.dart';
import 'package:cosmicguide/screens/rewards/temple_trip_screen.dart';
import 'package:cosmicguide/widgets/rewards/coin_toast.dart';
import 'package:cosmicguide/widgets/rewards/coins_pill.dart';
import 'package:cosmicguide/widgets/rewards/daily_checkin.dart';
import 'package:cosmicguide/widgets/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRewardsBackend extends BackendService {
  bool authed = true;
  int balance = 120;
  bool dailyClaimed = false;
  int streak = 3;
  final Map<String, int> answers = {'q1': 2};
  final List<String> calls = [];
  final List<Map<String, dynamic>> trips = [];
  bool stringNumbers = false;
  Completer<void>? holdCoins;

  void ping() => notifyListeners();

  List<Map<String, dynamic>> get questions => [
        for (var i = 1; i <= 3; i++)
          {
            'id': 'q$i',
            'text': 'Question number $i: how do you usually spend a quiet Sunday morning?',
            'category': 'lifestyle',
            'options': ['Prayer and meditation', 'Long walk outdoors', 'Family breakfast', 'Catching up on work'],
          }
      ];

  @override
  bool get isAuthenticated => authed;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add('$method $path');
    if (!authed) throw const BackendException('Please log in to earn coins.', statusCode: 401);
    switch ('$method $path') {
      case 'GET /coins':
        if (holdCoins != null) await holdCoins!.future;
        if (stringNumbers) {
          return {'balance': '$balance', 'goal': '10000', 'todayEarned': '5', 'dailyClaimed': 'true', 'streakDays': '2', 'earnRules': null, 'recent': [null, {'id': 3, 'amount': '1', 'reason': 'daily_login', 'createdAt': null}]};
        }
        return {
          'balance': balance,
          'goal': 10000,
          'todayEarned': 0,
          'dailyClaimed': dailyClaimed,
          'streakDays': streak,
          'earnRules': [
            {'key': 'daily_login', 'title': 'Daily check-in', 'coins': 1, 'note': ''},
          ],
          'recent': [
            {'id': 1, 'amount': 10, 'reason': 'game', 'ref': 'quest:2026-11-04', 'createdAt': '2026-11-04T10:00:00Z'},
            {'id': 2, 'amount': 50, 'reason': 'question', 'ref': 'q1', 'createdAt': '2026-11-04T09:00:00Z'},
          ],
        };
      case 'POST /coins/daily':
        final awarded = dailyClaimed ? 0 : 1;
        if (!dailyClaimed) {
          dailyClaimed = true;
          balance += 1;
          streak += 1;
        }
        return {'awarded': awarded, 'balance': balance, 'streakDays': streak};
      case 'GET /coins/questions':
        return {'questions': questions, 'answers': answers, 'answeredCount': answers.length, 'coinsPerQuestion': 50};
      case 'GET /buddy/connections':
        return {
          'incoming': [],
          'outgoing': [],
          'buddies': [
            {'id': 5, 'intent': 'spiritual', 'status': 'accepted', 'other': {'userId': 7, 'displayName': 'Asha', 'city': 'Pune', 'score': 82}},
          ],
        };
      case 'GET /trips/temples?buddyId=7':
        return {
          'temples': [
            {'id': 'kashi', 'name': 'Kashi Vishwanath', 'deity': 'Shiva', 'city': 'Varanasi', 'state': 'UP', 'distanceKm': 640, 'why': 'A Jyotirlinga on the Ganga.'},
            {'id': 'tirupati', 'name': 'Tirumala Venkateswara', 'deity': 'Vishnu (Balaji)', 'city': 'Tirupati', 'state': 'AP', 'distanceKm': 820, 'why': ''},
          ],
          'recommended': ['kashi'],
        };
      case 'POST /trips/request':
        balance -= 10000;
        trips.add({'id': 9, 'temple': {'id': 'kashi', 'name': 'Kashi Vishwanath'}, 'buddy': {'userId': 7, 'displayName': 'Asha'}, 'preferredMonth': body?['preferredMonth'], 'status': 'pending'});
        return {'request': trips.last, 'balance': balance};
      case 'GET /trips':
        return {'requests': trips};
      case 'POST /trips/9/cancel':
      case 'POST /trips/11/cancel':
        final t = trips.firstWhere((x) => '/trips/${x['id']}/cancel' == path);
        t['status'] = 'cancelled';
        balance += 10000;
        return {'request': t, 'balance': balance};
    }
    final m = RegExp(r'^POST /coins/questions/(\w+)/answer$').firstMatch('$method $path');
    if (m != null) {
      final id = m.group(1)!;
      final first = !answers.containsKey(id);
      answers[id] = (body?['optionIndex'] as num).toInt();
      if (first) balance += 50;
      return {'awarded': first ? 50 : 0, 'balance': balance, 'answeredCount': answers.length};
    }
    throw BackendException('Not found: $method $path', statusCode: 404);
  }
}

Future<RewardsService> pump(WidgetTester tester, Widget child, FakeRewardsBackend fake) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final rewards = RewardsService(fake);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: fake),
      ChangeNotifierProvider<RewardsService>.value(value: rewards),
    ],
    child: MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: c!,
      ),
      routes: {
        '/login': (_) => const Scaffold(body: Text('ROUTE:/login')),
        '/games': (_) => const Scaffold(body: Text('ROUTE:/games')),
      },
      home: child,
    ),
  ));
  await tester.pump();
  return rewards;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('istDayKey uses India time', () {
    expect(istDayKey(DateTime.utc(2026, 11, 4, 19, 0)), '2026-11-05'); // 00:30 IST
    expect(istDayKey(DateTime.utc(2026, 11, 4, 18, 0)), '2026-11-04'); // 23:30 IST
  });

  testWidgets('coins screen shows balance, ways to earn and activity', (tester) async {
    final fake = FakeRewardsBackend();
    await pump(tester, CoinsScreen(onOpenVideos: () {}), fake);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('My coins'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Temple trip unlocks at 10,000'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ways to earn'), 200);
    await tester.scrollUntilVisible(find.text('1/3 answered'), 200);
    expect(find.text('Watch a new video'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Played Graha Quest'), 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('coins screen asks guests to log in', (tester) async {
    final fake = FakeRewardsBackend()..authed = false;
    await pump(tester, const CoinsScreen(), fake);
    await settle(tester);
    expect(find.text('Log in to start earning'), findsOneWidget);
    expect(fake.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily check-in gate prompts once and claims', (tester) async {
    final fake = FakeRewardsBackend();
    final rewards = await pump(
        tester,
        const DailyCheckInGate(
          delay: Duration(milliseconds: 10),
          child: Scaffold(body: Center(child: CoinsPill())),
        ),
        fake);
    await settle(tester);
    expect(find.text('Claim 1 coin'), findsOneWidget);
    expect(find.text('Your daily blessing'), findsOneWidget);
    await tester.tap(find.text('Claim 1 coin'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('+1 coin added'), findsOneWidget);
    expect(find.text('+1 coin'), findsOneWidget); // toast
    expect(rewards.balance, 121);
    expect(rewards.dailyClaimed, isTrue);
    expect(rewards.streakDays, 4);
    await settle(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Claim 1 coin'), findsNothing);
    expect(find.text('121'), findsOneWidget); // pill
    expect(tester.takeException(), isNull);
    expect(fake.calls.where((c) => c == 'POST /coins/daily').length, 1);
  });

  testWidgets('quiz resumes at first unanswered, pays and finishes', (tester) async {
    final fake = FakeRewardsBackend();
    final rewards = await pump(tester, const MindsetQuizScreen(), fake);
    await settle(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.text('Long walk outdoors'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('+50'), findsWidgets);
    expect(rewards.balance, 170);
    await settle(tester);
    expect(find.text('3 of 3'), findsOneWidget);
    await tester.tap(find.text('Family breakfast'));
    await settle(tester);
    expect(find.text('Your mindset profile is ready'), findsOneWidget);
    expect(find.text('You earned 100 coins just now'), findsOneWidget);
    expect(rewards.answeredCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temple trip is locked below the goal', (tester) async {
    final fake = FakeRewardsBackend();
    await pump(tester, const TempleTripScreen(), fake);
    await settle(tester);
    expect(find.text('A temple trip with your buddy'), findsOneWidget);
    expect(find.textContaining('9,880 more to unlock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temple trip: buddy, temple, month, confirm, then listed', (tester) async {
    final fake = FakeRewardsBackend()..balance = 10050;
    final rewards = await pump(tester, const TempleTripScreen(), fake);
    await settle(tester);
    expect(find.text('Your temple trip is unlocked'), findsOneWidget);
    await tester.tap(find.text('Asha'));
    await tester.pump();
    await tester.tap(find.text('Choose a temple'));
    await settle(tester);
    expect(find.text('RECOMMENDED FOR YOU TWO'), findsOneWidget);
    expect(find.textContaining('~640 km'), findsOneWidget);
    await tester.tap(find.text('Kashi Vishwanath'));
    await tester.pump();
    await tester.ensureVisible(find.text('Choose a month'));
    await tester.pump();
    await tester.tap(find.text('Choose a month'));
    await settle(tester);
    await tester.tap(find.byType(AppFilterChip).first);
    await tester.pump();
    await tester.ensureVisible(find.text('Review request'));
    await tester.pump();
    await tester.tap(find.text('Review request'));
    await settle(tester);
    expect(find.text('Confirm your trip request'), findsOneWidget);
    await tester.ensureVisible(find.text('Send request'));
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await settle(tester);
    expect(fake.calls, contains('POST /trips/request'));
    expect(rewards.balance, 50);
    expect(find.text('Under review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game responses with coinsAwarded toast and add to balance', (tester) async {
    final fake = FakeRewardsBackend();
    late BuildContext ctx;
    final rewards = await pump(tester, Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    }), fake);
    await rewards.refresh();
    expect(showCoinsFromResponse(ctx, {'ok': true}), 0);
    expect(showCoinsFromResponse(ctx, {'coinsAwarded': 10}, reason: 'Graha Quest mission'), 10);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('+10 coins'), findsOneWidget);
    expect(find.text('Graha Quest mission'), findsOneWidget);
    expect(rewards.balance, 130);
    await settle(tester);
    expect(find.text('+10 coins'), findsNothing);
  });

  test('wallet JSON with numbers as strings and nulls is parsed', () async {
    final fake = FakeRewardsBackend()..stringNumbers = true;
    final r = RewardsService(fake);
    await r.refresh();
    expect(r.loaded, isTrue);
    expect(r.error, isNull);
    expect(r.balance, 120);
    expect(r.goal, 10000);
    expect(r.todayEarned, 5);
    expect(r.dailyClaimed, isTrue);
    expect(r.streakDays, 2);
    expect(r.earnRules, isEmpty);
    expect(r.recent.single.amount, 1);
  });

  test('trip requests: mine / invited, coinsSpent, canCancel', () {
    final mine = TripRequest.fromJson({
      'id': 4,
      'temple': {'id': 'kashi', 'name': 'Kashi Vishwanath'},
      'buddy': {'userId': '7', 'displayName': 'Asha'},
      'preferredMonth': '2027-01',
      'status': 'PENDING',
      'coinsSpent': '10000',
      'mine': true,
    });
    expect(mine.canCancel, isTrue);
    expect(mine.coinsSpent, 10000);
    expect(mine.buddy.userId, 7);
    final invited = TripRequest.fromJson({'id': 5, 'temple': null, 'buddy': null, 'status': 'pending', 'mine': false});
    expect(invited.canCancel, isFalse);
    expect(invited.temple.name, 'Temple');
    expect(invited.buddy.displayName, 'Buddy');
  });

  test('applyAward uses the server balance, and fetches when not loaded', () async {
    final fake = FakeRewardsBackend();
    final r = RewardsService(fake);
    r.applyAward(1, reason: 'video', balance: 500); // not loaded: refresh instead of guessing
    await Future<void>.delayed(Duration.zero);
    expect(fake.calls, contains('GET /coins'));
    await r.refresh();
    expect(r.balance, 120);
    r.applyAward(1, reason: 'video', ref: 'abc', balance: 121);
    expect(r.balance, 121);
    expect(r.recent.first.reason, 'video');
    r.applyAward(10, reason: 'game', ref: 'quest');
    expect(r.balance, 131);
    expect(r.todayEarned, 11);
  });

  test('a refresh that finishes after logout is dropped', () async {
    final fake = FakeRewardsBackend()..holdCoins = Completer<void>();
    final r = RewardsService(fake);
    final pending = r.refresh();
    fake.authed = false;
    fake.ping(); // logout
    fake.holdCoins!.complete();
    await pending;
    expect(r.loaded, isFalse);
    expect(r.balance, 0);
    expect(r.loggedIn, isFalse);
    expect(r.loading, isFalse);
  });

  testWidgets('quiz: changing an answer pays nothing and hides +50', (tester) async {
    final fake = FakeRewardsBackend();
    final rewards = await pump(tester, const MindsetQuizScreen(), fake);
    await settle(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget); // header: this one still pays
    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('+50'), findsNothing); // q1 already answered
    await tester.tap(find.text('Prayer and meditation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('+50'), findsNothing); // no burst for a changed answer
    await settle(tester);
    expect(rewards.balance, 120);
    expect(rewards.answers['q1'], 0);
    expect(find.text('2 of 3'), findsOneWidget); // back to the open question
    expect(tester.takeException(), isNull);
  });

  testWidgets('coins screen at 320px links to the coins terms', (tester) async {
    final fake = FakeRewardsBackend();
    await pump(tester, CoinsScreen(onOpenVideos: () {}), fake);
    tester.view.physicalSize = const Size(320, 700);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Coins terms'), 200);
    await tester.tap(find.text('Coins terms'));
    await settle(tester);
    expect(find.byType(CommunityGuidelinesScreen), findsOneWidget);
    expect(find.text('Coins terms'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temple trip: invited requests have no cancel; mine cancels with refund', (tester) async {
    final fake = FakeRewardsBackend()
      ..trips.addAll([
        {'id': 9, 'temple': {'id': 'kashi', 'name': 'Kashi Vishwanath'}, 'buddy': {'userId': 7, 'displayName': 'Asha'}, 'preferredMonth': '2027-02', 'status': 'pending', 'coinsSpent': 10000, 'mine': true},
        {'id': 10, 'temple': {'id': 'tirupati', 'name': 'Tirumala Venkateswara'}, 'buddy': {'userId': 8, 'displayName': 'Ravi'}, 'preferredMonth': '2027-03', 'status': 'pending', 'coinsSpent': 10000, 'mine': false},
      ]);
    final rewards = await pump(tester, const TempleTripScreen(), fake);
    tester.view.physicalSize = const Size(320, 1400);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Invited by Ravi · March 2027'), 200);
    expect(find.text('Cancel request'), findsOneWidget); // only on my own request
    await tester.ensureVisible(find.text('Cancel request'));
    await tester.tap(find.text('Cancel request'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel request').last);
    await settle(tester);
    expect(fake.calls, contains('POST /trips/9/cancel'));
    expect(rewards.balance, 10120);
    expect(find.text('Cancelled · refunded'), findsOneWidget);
    expect(find.text('Temple trip terms'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('temple trip shows an error (not "locked") when the wallet fails', (tester) async {
    final fake = _FailingCoinsBackend();
    await pump(tester, const TempleTripScreen(), fake);
    await settle(tester);
    expect(find.text('A temple trip with your buddy'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Unable to connect to the server.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FailingCoinsBackend extends FakeRewardsBackend {
  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    if (path == '/coins') throw const BackendException('Unable to connect to the server.');
    return super.api(method, path, body: body, timeout: timeout);
  }
}
