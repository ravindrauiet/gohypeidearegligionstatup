import 'dart:async';

import 'package:cosmicguide/screens/notifications/notification_inbox_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/notification_inbox_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:cosmicguide/widgets/home/home_widgets.dart';
import 'package:cosmicguide/widgets/notifications/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

DateTime get _now => DateTime.now();
DateTime get _todayEarly => DateTime(_now.year, _now.month, _now.day, 0, 1);
DateTime get _yesterday => DateTime(_now.year, _now.month, _now.day - 1, 12);
DateTime get _earlier => DateTime(_now.year, _now.month, _now.day - 5, 9);

Map<String, dynamic> item(String id,
        {String type = 'buddy_request',
        String? title,
        String body = 'Priya wants to be your Satsang buddy. Say hello and plan a temple visit together.',
        bool read = false,
        DateTime? at,
        Map<String, dynamic>? data,
        String? cursor}) =>
    {
      'id': id,
      'type': type,
      'title': title ?? 'Notification $id',
      'body': body,
      'data': data ?? {'connectionId': '12'},
      'read': read,
      'createdAt': (at ?? _todayEarly).toUtc().toIso8601String(),
      if (cursor != null) 'cursor': cursor,
    };

class FakeInboxBackend extends BackendService {
  bool loggedIn = true;
  int userId = 1;
  List<Map<String, dynamic>> page1 = [];
  List<Map<String, dynamic>> page2 = [];
  bool page1HasMore = false;
  int unreadCount = 0;
  final List<(String, String, Map<String, dynamic>?)> calls = [];
  final Map<String, BackendException> failures = {};

  /// When set, GET /notifications waits for it.
  Completer<void>? listGate;

  int count(String method, String path) =>
      calls.where((c) => c.$1 == method && c.$2.split('?').first == path).length;

  @override
  bool get isAuthenticated => loggedIn;
  @override
  String? get token => loggedIn ? 'tok$userId' : null;
  @override
  Map<String, dynamic>? get user => loggedIn ? {'id': userId, 'fullName': 'Ravi Kumar'} : null;

  void switchAccount({bool? signedIn, int? id}) {
    if (signedIn != null) loggedIn = signedIn;
    if (id != null) userId = id;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add((method, path, body));
    final p = path.split('?').first;
    final fail = failures['$method $p'];
    if (fail != null) throw fail;
    if (method == 'GET' && p == '/notifications') {
      final gate = listGate;
      if (gate != null) await gate.future;
      final q = Uri.parse(path).queryParameters;
      if (q['before'] != null) return {'items': page2, 'unread': unreadCount, 'hasMore': false};
      return {'items': page1, 'unread': unreadCount, 'hasMore': page1HasMore};
    }
    if (method == 'GET' && p == '/notifications/unread-count') return {'unread': unreadCount};
    if (method == 'POST' && p == '/notifications/read') {
      if (body?['all'] == true) {
        unreadCount = 0;
      } else {
        unreadCount = (unreadCount - (body?['ids'] as List).length).clamp(0, 1 << 30);
      }
      return {'success': true, 'unread': unreadCount};
    }
    return {};
  }
}

Future<NotificationInboxService> pumpInbox(
  WidgetTester tester,
  FakeInboxBackend backend, {
  double width = 360,
  double textScale = 1.0,
  NotificationOpener? onOpen,
  Widget? child,
}) async {
  tester.view.physicalSize = Size(width * 3, 760 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late NotificationInboxService svc;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: backend),
      ChangeNotifierProvider(create: (c) => svc = NotificationInboxService(c.read<BackendService>()), lazy: false),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      routes: {'/login': (_) => const Scaffold(body: Text('LOGIN SCREEN'))},
      home: child ?? NotificationInboxScreen(onOpen: onOpen ?? (_) async {}),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return svc;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('helpers', () {
    final now = DateTime(2026, 11, 5, 15, 30);

    test('grouping into Today / Yesterday / Earlier', () {
      expect(inboxGroupFor(DateTime(2026, 11, 5, 0, 5), now), InboxGroup.today);
      expect(inboxGroupFor(DateTime(2026, 11, 4, 23, 59), now), InboxGroup.yesterday);
      expect(inboxGroupFor(DateTime(2026, 11, 3, 10), now), InboxGroup.earlier);
      expect(inboxGroupFor(null, now), InboxGroup.earlier);
      // Slightly in the future (clock skew) still counts as today.
      expect(inboxGroupFor(DateTime(2026, 11, 5, 15, 31), now), InboxGroup.today);
    });

    test('relative time', () {
      expect(inboxRelativeTime(now.subtract(const Duration(seconds: 20)), now), 'Just now');
      expect(inboxRelativeTime(now.subtract(const Duration(minutes: 5)), now), '5m ago');
      expect(inboxRelativeTime(now.subtract(const Duration(hours: 3)), now), '3h ago');
      expect(inboxRelativeTime(DateTime(2026, 11, 4, 9), now), 'Yesterday');
      expect(inboxRelativeTime(DateTime(2026, 11, 2, 9), now), 'Mon');
      expect(inboxRelativeTime(DateTime(2026, 10, 12, 9), now), '12 Oct');
      expect(inboxRelativeTime(DateTime(2025, 10, 12, 9), now), '12 Oct 2025');
      expect(inboxRelativeTime(null, now), '');
    });

    test('badge text caps at 99+', () {
      expect(inboxBadgeText(7), '7');
      expect(inboxBadgeText(99), '99');
      expect(inboxBadgeText(100), '99+');
      expect(inboxBadgeText(4200), '99+');
    });

    test('every contract type has its own icon', () {
      const types = [
        'buddy_request', 'buddy_accepted', 'buddy_message', 'nearby_buddy', 'trip_update', 'coins', 'checkin',
        'daily_horoscope', 'festival', 'videos', 'mindset', 'announcement',
      ];
      final icons = types.map((t) => inboxTypeStyle(t).$1).toSet();
      expect(icons.length, types.length);
      expect(inboxTypeStyle('something_new').$1, Icons.notifications_rounded);
    });

    test('parsing is defensive', () {
      final n = InboxNotification.tryParse({
        'id': 34,
        'type': 'trip_update',
        'title': 'Trip confirmed',
        'data': {'tripId': 9, 'status': 'confirmed', 'skip': null},
        'read': 1,
        'createdAt': 'not a date',
      })!;
      expect(n.id, '34');
      expect(n.data, {'tripId': '9', 'status': 'confirmed'});
      expect(n.read, isTrue);
      expect(n.createdAt, isNull);
      expect(n.cursor, '34');
      expect(n.routeData['type'], 'trip_update');
      expect(InboxNotification.tryParse({'title': 'no id'}), isNull);
      expect(InboxNotification.tryParse('junk'), isNull);
      expect(InboxNotification.tryParse({'id': 'b:1'})!.type, 'inbox');
    });
  });

  group('service', () {
    test('guests get nothing and make no calls', () async {
      final b = FakeInboxBackend()..loggedIn = false;
      final s = NotificationInboxService(b);
      await s.refresh();
      await s.refreshUnread(force: true);
      await s.loadMore();
      expect(await s.markAllRead(), isFalse);
      expect(b.calls, isEmpty);
      expect(s.items, isEmpty);
      expect(s.unread, 0);
      s.dispose();
    });

    test('pagination passes the cursor (or id) and stops when hasMore is false', () async {
      final b = FakeInboxBackend()
        ..page1 = [item('n:3'), item('b:2', cursor: 'c-2')]
        ..page1HasMore = true
        ..page2 = [item('n:1'), item('b:2')] // duplicate dropped
        ..unreadCount = 3;
      final s = NotificationInboxService(b);
      await s.refresh();
      expect(s.items.map((n) => n.id), ['n:3', 'b:2']);
      expect(s.hasMore, isTrue);
      expect(s.unread, 3);
      await s.loadMore();
      expect(b.calls.last.$2, '/notifications?before=c-2&limit=30');
      expect(s.items.map((n) => n.id), ['n:3', 'b:2', 'n:1']);
      expect(s.hasMore, isFalse);
      await s.loadMore();
      expect(b.count('GET', '/notifications'), 2);

      // Without a cursor the id is used (url-encoded).
      final b2 = FakeInboxBackend()
        ..page1 = [item('n:9')]
        ..page1HasMore = true;
      final s2 = NotificationInboxService(b2);
      await s2.refresh();
      await s2.loadMore();
      expect(b2.calls.last.$2, '/notifications?before=n%3A9&limit=30');
      s.dispose();
      s2.dispose();
    });

    test('mark read / mark all read update the count; failures revert', () async {
      final b = FakeInboxBackend()
        ..page1 = [item('n:1'), item('n:2'), item('n:3', read: true)]
        ..unreadCount = 2;
      final s = NotificationInboxService(b);
      await s.refresh();
      expect(await s.markRead('n:1'), isTrue);
      expect(s.items.first.read, isTrue);
      expect(s.unread, 1);
      expect(b.calls.last.$3, {
        'ids': ['n:1']
      });
      // Already read: no call.
      final before = b.calls.length;
      await s.markRead('n:3');
      expect(b.calls.length, before);

      b.failures['POST /notifications/read'] = const BackendException('nope', statusCode: 500);
      expect(await s.markAllRead(), isFalse);
      expect(s.unread, 1);
      expect(s.items[1].read, isFalse);

      b.failures.clear();
      expect(await s.markAllRead(), isTrue);
      expect(b.calls.last.$3, {'all': true});
      expect(s.unread, 0);
      expect(s.items.every((n) => n.read), isTrue);
      s.dispose();
    });

    test('refreshUnread is throttled unless forced', () async {
      final b = FakeInboxBackend()..unreadCount = 4;
      final s = NotificationInboxService(b);
      var t = DateTime(2026, 1, 1, 10);
      s.clock = () => t;
      await s.refreshUnread();
      await s.refreshUnread();
      expect(b.count('GET', '/notifications/unread-count'), 1);
      expect(s.unread, 4);
      await s.refreshUnread(force: true);
      expect(b.count('GET', '/notifications/unread-count'), 2);
      t = t.add(NotificationInboxService.unreadMinGap);
      await s.refreshUnread();
      expect(b.count('GET', '/notifications/unread-count'), 3);
      s.dispose();
    });

    test('account change drops cached items and ignores late responses', () async {
      final b = FakeInboxBackend()
        ..page1 = [item('n:1')]
        ..unreadCount = 1;
      final s = NotificationInboxService(b);
      await s.refresh();
      expect(s.items, hasLength(1));

      b.switchAccount(id: 2);
      b.unreadCount = 0;
      await Future<void>.delayed(Duration.zero);
      expect(s.items, isEmpty);
      expect(s.loaded, isFalse);

      // A request in flight for the old account must not land on the new one.
      b.listGate = Completer<void>();
      final pending = s.refresh();
      b.switchAccount(signedIn: false);
      await Future<void>.delayed(Duration.zero);
      b.listGate!.complete();
      await pending;
      expect(s.items, isEmpty);
      expect(s.signedIn, isFalse);
      s.dispose();
    });
  });

  group('screen', () {
    testWidgets('groups items, highlights unread and opens via the router', (tester) async {
      final opened = <Map<String, dynamic>>[];
      final b = FakeInboxBackend()
        ..page1 = [
          item('n:5', title: 'Priya wants to connect', at: _todayEarly),
          item('n:4', type: 'trip_update', title: 'Trip confirmed', read: true, at: _yesterday,
              data: {'tripId': '3', 'status': 'confirmed'}),
          item('n:3', type: 'coins', title: '50 coins added', read: true, at: _earlier, data: {}),
        ]
        ..unreadCount = 1;
      final s = await pumpInbox(tester, b, onOpen: (d) async => opened.add(d));
      await tester.pumpAndSettle();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('EARLIER'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-unread-dot')), findsOneWidget);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
      expect(find.byIcon(Icons.temple_hindu_rounded), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);

      await tester.tap(find.text('Priya wants to connect'));
      await tester.pumpAndSettle();
      expect(opened, [
        {'connectionId': '12', 'type': 'buddy_request'}
      ]);
      expect(b.calls.any((c) => c.$1 == 'POST' && c.$2 == '/notifications/read'), isTrue);
      expect(s.unread, 0);
      expect(find.byKey(const ValueKey('inbox-unread-dot')), findsNothing);
      expect(find.text('Mark all read'), findsNothing);

      await tester.tap(find.text('Trip confirmed'));
      await tester.pumpAndSettle();
      expect(opened.last, {'tripId': '3', 'status': 'confirmed', 'type': 'trip_update'});
    });

    testWidgets('announcement without a link opens in place', (tester) async {
      final opened = <Map<String, dynamic>>[];
      final b = FakeInboxBackend()
        ..page1 = [item('b:1', type: 'announcement', title: 'Diwali offers', body: 'Full text here', data: {})];
      await pumpInbox(tester, b, onOpen: (d) async => opened.add(d));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diwali offers'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('Diwali offers'), findsNWidgets(2)); // tile + sheet
    });

    testWidgets('mark all read clears every highlight', (tester) async {
      final b = FakeInboxBackend()
        ..page1 = [item('n:2'), item('n:1')]
        ..unreadCount = 2;
      final s = await pumpInbox(tester, b);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-unread-dot')), findsNWidgets(2));
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-unread-dot')), findsNothing);
      expect(s.unread, 0);
      expect(b.calls.last.$3, {'all': true});
    });

    testWidgets('infinite scroll loads the next page', (tester) async {
      final b = FakeInboxBackend()
        ..page1 = [for (var i = 40; i > 10; i--) item('n:$i', title: 'Item $i', read: true)]
        ..page1HasMore = true
        ..page2 = [item('n:10', title: 'Item 10', read: true, at: _earlier)];
      await pumpInbox(tester, b);
      await tester.pumpAndSettle();
      expect(b.count('GET', '/notifications'), 1);
      await tester.scrollUntilVisible(find.text('Item 10'), 600, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(b.calls.any((c) => c.$2.contains('before=n%3A11')), isTrue);
      expect(find.text('Item 10'), findsOneWidget);
      await tester.scrollUntilVisible(find.text("That's everything"), 300, scrollable: find.byType(Scrollable).first);
      expect(b.count('GET', '/notifications'), 2);
    });

    testWidgets('skeleton while loading, then empty state', (tester) async {
      final b = FakeInboxBackend()..listGate = Completer<void>();
      await pumpInbox(tester, b);
      expect(find.byKey(const ValueKey('inbox-skeleton')), findsOneWidget);
      b.listGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-skeleton')), findsNothing);
      expect(find.text("You're all caught up"), findsOneWidget);
    });

    testWidgets('error state with retry', (tester) async {
      final b = FakeInboxBackend()
        ..failures['GET /notifications'] = const BackendException('Server down', statusCode: 503);
      await pumpInbox(tester, b);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load notifications"), findsOneWidget);
      b.failures.clear();
      b.page1 = [item('n:1', title: 'Back online')];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Back online'), findsOneWidget);
    });

    testWidgets('guests are asked to sign in and nothing is fetched', (tester) async {
      final b = FakeInboxBackend()..loggedIn = false;
      await pumpInbox(tester, b);
      await tester.pumpAndSettle();
      expect(find.text('Sign in to see your notifications'), findsOneWidget);
      expect(b.calls, isEmpty);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN SCREEN'), findsOneWidget);
    });

    testWidgets('no overflow at 320px with 1.3x text', (tester) async {
      final b = FakeInboxBackend()
        ..page1 = [
          item('n:3',
              title: 'A very long notification title that keeps going and going past two lines for sure',
              body: 'And an equally long body text that will need to be truncated after the second line ' * 3),
          item('n:2', type: 'festival', read: true, at: _yesterday),
          item('n:1', type: 'mindset', at: _earlier),
        ]
        ..unreadCount = 2;
      await pumpInbox(tester, b, width: 320, textScale: 1.3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('screen works without a provided service', (tester) async {
      final b = FakeInboxBackend()..page1 = [item('n:1', title: 'Standalone')];
      tester.view.physicalSize = const Size(360 * 3, 760 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<BackendService>.value(
        value: b,
        child: MaterialApp(home: NotificationInboxScreen(onOpen: (_) async {})),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Standalone'), findsOneWidget);
    });
  });

  group('bell', () {
    testWidgets('shows unread badge, caps at 99+, opens inbox and refreshes on return', (tester) async {
      final b = FakeInboxBackend()..unreadCount = 7;
      final s = await pumpInbox(tester, b,
          child: const Scaffold(backgroundColor: AppColors.cosmic, body: Center(child: NotificationBell())));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-badge')), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      b.unreadCount = 250;
      await s.refreshUnread(force: true);
      await tester.pump();
      expect(find.text('99+'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, 250 unread'), findsOneWidget);

      final before = b.count('GET', '/notifications/unread-count');
      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(b.count('GET', '/notifications/unread-count'), greaterThan(before));
    });

    testWidgets('no badge for guests or zero unread; refresh on app resume', (tester) async {
      final b = FakeInboxBackend()..unreadCount = 0;
      final s = await pumpInbox(tester, b, child: const Scaffold(body: Center(child: NotificationBell())));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-badge')), findsNothing);

      var t = DateTime(2026, 1, 1, 10);
      s.clock = () => t;
      t = t.add(const Duration(minutes: 5));
      final before = b.count('GET', '/notifications/unread-count');
      b.unreadCount = 2;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(b.count('GET', '/notifications/unread-count'), before + 1);
      expect(find.text('2'), findsOneWidget);

      b.switchAccount(signedIn: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-badge')), findsNothing);
    });

    testWidgets('renders nothing without the provider', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NotificationBell())));
      expect(find.byType(NotificationBellButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hero header fits coins pill + bell at 320px / 1.3x', (tester) async {
      final b = FakeInboxBackend()..unreadCount = 120;
      await pumpInbox(tester, b,
          width: 320,
          textScale: 1.3,
          child: Scaffold(
            body: SizedBox(
              height: 320,
              child: HomeHeroHeader(
                title: 'Hi, Ravindranath',
                subtitle: 'Good evening · Scorpio Lagna · Cancer Moon',
                avatarName: 'Ravi',
                walletLabel: null,
                pill: Container(width: 92, height: 34, color: Colors.amber),
                bell: const NotificationBell(),
                onSwitchProfile: () {},
                onWallet: () {},
                onProfile: () {},
                banner: const SizedBox(height: 120),
                bottomInset: 0,
              ),
            ),
          ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('99+'), findsOneWidget);
    });
  });
}
