import 'package:cosmicguide/screens/buddy/buddy_chat_screen.dart';
import 'package:cosmicguide/screens/notifications/notification_settings_screen.dart';
import 'package:cosmicguide/services/notification_router.dart';
import 'package:cosmicguide/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class FakeLocalNotifier implements LocalNotifier {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancelled = [];
  final List<(int, String, String, String, Map<String, String>)> shown = [];
  bool? granted = true;
  bool grantOnRequest = false;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<void> init(void Function(Map<String, dynamic> data) onTap) async {}
  @override
  Future<Map<String, dynamic>?> launchPayload() async => null;
  @override
  Future<void> show(int id, String title, String body, String channel, Map<String, String> payload) async =>
      shown.add((id, title, body, channel, payload));
  @override
  Future<void> schedule(PlannedNotification n) async => scheduled[n.id] = n;
  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<bool?> permissionGranted() async => granted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnRequest) granted = true;
    return grantOnRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

late tz.Location ist;
tz.TZDateTime at(int y, int m, int d, [int h = 0, int min = 0]) => tz.TZDateTime(ist, y, m, d, h, min);

ScheduleInput input(tz.TZDateTime now,
        {NotificationPrefs prefs = const NotificationPrefs(),
        bool registered = true,
        bool checkedIn = false,
        int streak = 0,
        List<FestivalItem> festivals = const [],
        int? mindsetRemaining}) =>
    ScheduleInput(
      now: now,
      prefs: prefs,
      registered: registered,
      checkedInToday: checkedIn,
      streakDays: streak,
      festivals: festivals,
      mindsetRemaining: mindsetRemaining,
    );

PlannedNotification? byId(List<PlannedNotification> plan, int id) {
  for (final p in plan) {
    if (p.id == id) return p;
  }
  return null;
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    ist = tz.getLocation('Asia/Kolkata');
    tz.setLocalLocation(ist);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationRouter.debugReset();
    BuddyChatScreen.openConnectionId.value = null;
  });

  // 2026-11-05 is a Thursday.
  group('scheduling computations', () {
    test('daily horoscope: next 07:30', () {
      expect(NotificationSchedule.nextAt(at(2026, 11, 5, 6, 0), 7, 30), at(2026, 11, 5, 7, 30));
      expect(NotificationSchedule.nextAt(at(2026, 11, 5, 7, 30), 7, 30), at(2026, 11, 6, 7, 30));
      expect(NotificationSchedule.nextAt(at(2026, 11, 5, 20, 0), 7, 30), at(2026, 11, 6, 7, 30));
      // Month / year rollover.
      expect(NotificationSchedule.nextAt(at(2026, 12, 31, 9, 0), 7, 30), at(2027, 1, 1, 7, 30));

      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 6, 0)));
      final h = byId(plan, NotificationIds.dailyHoroscope)!;
      expect(h.when, at(2026, 11, 5, 7, 30));
      expect(h.repeat, NotificationRepeat.daily);
      expect(h.payload['type'], 'daily_horoscope');
    });

    test('custom horoscope time and moon sign personalisation', () {
      final plan = NotificationSchedule.plan(ScheduleInput(
        now: at(2026, 11, 5, 6, 0),
        prefs: const NotificationPrefs(horoscopeHour: 5, horoscopeMinute: 45),
        moonSign: 'Leo',
      ));
      final h = byId(plan, NotificationIds.dailyHoroscope)!;
      expect(h.when, at(2026, 11, 6, 5, 45));
      expect(h.body, contains('Leo'));
    });

    test('check-in reminder: today 19:30 unless already checked in', () {
      final notYet = NotificationSchedule.checkinTimes(at(2026, 11, 5, 10, 0), checkedInToday: false);
      expect(notYet, [at(2026, 11, 5, 19, 30), at(2026, 11, 6, 19, 30), at(2026, 11, 7, 19, 30)]);

      final done = NotificationSchedule.checkinTimes(at(2026, 11, 5, 10, 0), checkedInToday: true);
      expect(done.first, at(2026, 11, 6, 19, 30), reason: 'skipped today after a check-in');

      final late = NotificationSchedule.checkinTimes(at(2026, 11, 5, 20, 0), checkedInToday: false);
      expect(late.first, at(2026, 11, 6, 19, 30));
    });

    test('check-in plan mentions the streak and is skipped for guests', () {
      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), checkedIn: true, streak: 5));
      final first = byId(plan, NotificationIds.checkinBase)!;
      expect(first.when, at(2026, 11, 6, 19, 30));
      expect(first.title, contains('5-day streak'));
      expect(byId(plan, NotificationIds.checkinBase + 1)!.title, isNot(contains('streak')));
      expect(first.payload['type'], 'checkin');

      final guest = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), registered: false));
      expect(byId(guest, NotificationIds.checkinBase), isNull);
      expect(byId(guest, NotificationIds.mindsetWeekly), isNull);
      expect(byId(guest, NotificationIds.dailyHoroscope), isNotNull, reason: 'guests keep local reminders');
    });

    test('festival eve 18:00 and morning 07:00', () {
      final now = at(2026, 11, 5, 10, 0);
      expect(NotificationSchedule.festivalTimes(now, DateTime(2026, 11, 8)),
          [at(2026, 11, 7, 18, 0), at(2026, 11, 8, 7, 0)]);
      expect(NotificationSchedule.festivalTimes(now, DateTime(2026, 11, 5)), isEmpty, reason: 'both already passed');
      expect(
          NotificationSchedule.festivalTimes(at(2026, 11, 5, 19, 0), DateTime(2026, 11, 6)), [at(2026, 11, 6, 7, 0)]);
      // Month boundary.
      expect(NotificationSchedule.festivalTimes(now, DateTime(2026, 12, 1)).first, at(2026, 11, 30, 18, 0));
    });

    test('festival plan: grouped per day, 30-day window, ids and payload', () {
      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), festivals: [
        FestivalItem(DateTime(2026, 11, 8), 'Diwali'),
        FestivalItem(DateTime(2026, 11, 8), 'Lakshmi Puja'),
        FestivalItem(DateTime(2026, 11, 20), 'Chhath Puja'),
        FestivalItem(DateTime(2027, 1, 14), 'Makar Sankranti'), // > 30 days away
      ]));
      final fest = plan.where((p) => p.channel == NotificationChannels.festivals).toList();
      expect(fest.length, 4);
      final eve = byId(plan, NotificationIds.festivalBase)!;
      expect(eve.when, at(2026, 11, 7, 18, 0));
      expect(eve.title, 'Tomorrow: Diwali & Lakshmi Puja');
      expect(eve.payload, {'type': 'festival', 'name': 'Diwali & Lakshmi Puja', 'date': '2026-11-08'});
      expect(byId(plan, NotificationIds.festivalBase + 1)!.when, at(2026, 11, 8, 7, 0));
      expect(byId(plan, NotificationIds.festivalBase + 2)!.title, 'Tomorrow: Chhath Puja');
      expect(fest.any((p) => p.title.contains('Sankranti')), isFalse);

      final off = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0),
          prefs: const NotificationPrefs(festivals: false),
          festivals: [FestivalItem(DateTime(2026, 11, 8), 'Diwali')]));
      expect(off.where((p) => p.channel == NotificationChannels.festivals), isEmpty);
    });

    test('festivals are read from month forecast events', () {
      final items = NotificationService.festivalsFromForecast([
        {
          'events': [
            {'date': '2026-11-08', 'type': 'festival', 'title': 'Diwali'},
            {'date': '2026-11-08', 'type': 'festival', 'title': 'Diwali'},
            {'date': '2026-11-11', 'type': 'ekadashi', 'title': 'Dev Uthani Ekadashi'},
            {'date': '2026-11-24', 'type': 'full_moon', 'title': 'Purnima'},
            {'date': '2026-11-12', 'type': 'retrograde', 'title': 'Mercury retrograde'},
          ]
        },
        null,
      ]);
      expect(items.map((f) => f.name), ['Diwali', 'Dev Uthani Ekadashi']);
    });

    test('re-engagement: 3 and 7 days out, out of the night, pushed forward on each open', () {
      expect(NotificationSchedule.reengageTime(at(2026, 11, 5, 14, 15), 3), at(2026, 11, 8, 14, 15));
      expect(NotificationSchedule.reengageTime(at(2026, 11, 5, 22, 30), 3), at(2026, 11, 9, 10, 0));
      expect(NotificationSchedule.reengageTime(at(2026, 11, 5, 2, 0), 3), at(2026, 11, 8, 10, 0));

      final first = NotificationSchedule.plan(input(at(2026, 11, 5, 12, 0)));
      final later = NotificationSchedule.plan(input(at(2026, 11, 6, 15, 0)));
      expect(byId(first, NotificationIds.reengage3)!.when, at(2026, 11, 8, 12, 0));
      expect(byId(first, NotificationIds.reengage7)!.when, at(2026, 11, 12, 12, 0));
      expect(byId(later, NotificationIds.reengage3)!.when, at(2026, 11, 9, 15, 0));
      expect(
          byId(later, NotificationIds.reengage3)!.when.isAfter(byId(first, NotificationIds.reengage3)!.when), isTrue);
      expect(
          ['daily_horoscope', 'mindset', 'videos'], contains(byId(first, NotificationIds.reengage3)!.payload['type']));
    });

    test('mindset nudge: Sunday 11:00 only while questions remain', () {
      expect(NotificationSchedule.nextWeekday(at(2026, 11, 5, 10, 0), DateTime.sunday, 11), at(2026, 11, 8, 11, 0));
      expect(NotificationSchedule.nextWeekday(at(2026, 11, 8, 12, 0), DateTime.sunday, 11), at(2026, 11, 15, 11, 0));
      expect(NotificationSchedule.nextWeekday(at(2026, 11, 8, 10, 0), DateTime.sunday, 11), at(2026, 11, 8, 11, 0));

      final some = byId(NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), mindsetRemaining: 10)),
          NotificationIds.mindsetWeekly)!;
      expect(some.title, 'Answer 3 questions, earn 150 coins');
      expect(some.repeat, NotificationRepeat.weekly);
      expect(
          byId(NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), mindsetRemaining: 0)),
              NotificationIds.mindsetWeekly),
          isNull);
    });

    test('master off schedules nothing; every planned id is managed', () {
      expect(NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), prefs: const NotificationPrefs(master: false))),
          isEmpty);
      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0),
          festivals: [for (var d = 6; d < 20; d++) FestivalItem(DateTime(2026, 11, d), 'Fest $d')]));
      expect(plan.every((p) => NotificationIds.managed.contains(p.id)), isTrue);
      expect(plan.map((p) => p.id).toSet().length, plan.length, reason: 'ids are unique');
    });

    test('prefs round-trip and server mapping', () {
      const p = NotificationPrefs(checkin: false, horoscopeHour: 6, messages: false);
      expect(NotificationPrefs.fromJson(p.toJson()).toJson(), p.toJson());
      expect(p.toServer(), {'buddy': true, 'messages': false, 'trips': true, 'rewards': false, 'announcements': true});
      final merged = const NotificationPrefs().mergeServer({'trips': false, 'rewards': false});
      expect(merged.trips, isFalse);
      expect(merged.checkin, isFalse);
      expect(merged.buddy, isTrue);
    });
  });

  group('router', () {
    test('maps every payload type', () {
      NotificationDestination d(Map<String, dynamic> data) => NotificationRouter.resolve(data).destination;
      expect(d({'type': 'buddy_request', 'connectionId': '4'}), NotificationDestination.buddyRequests);
      final accepted = NotificationRouter.resolve({'type': 'buddy_accepted', 'connectionId': '12', 'name': 'Asha'});
      expect(accepted.destination, NotificationDestination.buddyChat);
      expect(accepted.connectionId, 12);
      expect(accepted.title, 'Asha');
      expect(NotificationRouter.resolve({'type': 'buddy_message', 'connectionId': 9}).connectionId, 9);
      expect(d({'type': 'buddy_message'}), NotificationDestination.buddyRequests, reason: 'missing id');
      expect(d({'type': 'nearby_buddy'}), NotificationDestination.buddyDiscover);
      expect(d({'type': 'trip_update', 'tripId': '3', 'status': 'approved'}), NotificationDestination.templeTrip);
      expect(d({'type': 'coins'}), NotificationDestination.coins);
      expect(d({'type': 'checkin'}), NotificationDestination.home);
      expect(d({'type': 'daily_horoscope'}), NotificationDestination.forecast);
      expect(d({'type': 'festival', 'name': 'Diwali', 'date': '2026-11-08'}), NotificationDestination.home);
      expect(d({'type': 'videos'}), NotificationDestination.videos);
      final pl = NotificationRouter.resolve({'type': 'videos', 'playlistId': 'PL1'});
      expect(pl.destination, NotificationDestination.playlist);
      expect(pl.playlistId, 'PL1');
      expect(d({'type': 'mindset'}), NotificationDestination.mindset);
      expect(d({'type': 'announcement', 'url': 'https://x'}), NotificationDestination.inbox);
      expect(d({'type': 'inbox'}), NotificationDestination.inbox);
      expect(d({'type': 'something_new'}), NotificationDestination.home);
      expect(d({}), NotificationDestination.home);
    });

    testWidgets('queues until Home is ready, then opens', (tester) async {
      final opened = <NotificationTarget>[];
      NotificationRouter.debugHandler = opened.add;
      await NotificationRouter.open({'type': 'coins'});
      expect(opened, isEmpty);
      expect(NotificationRouter.pending, {'type': 'coins'});

      NotificationRouter.onHomeReady();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(opened.single.destination, NotificationDestination.coins);
      expect(NotificationRouter.pending, isNull);

      await NotificationRouter.open({'type': 'mindset'});
      expect(opened.last.destination, NotificationDestination.mindset);
      NotificationRouter.onHomeGone();
      await NotificationRouter.open({'type': 'inbox'});
      expect(opened.length, 2);
      expect(NotificationRouter.pending, {'type': 'inbox'});
    });
  });

  group('foreground push', () {
    test('suppressed only for the open chat and respects toggles', () {
      const prefs = NotificationPrefs();
      final msg = {'type': 'buddy_message', 'connectionId': '7', 'name': 'Asha'};
      expect(NotificationService.shouldPresentForeground(msg, prefs), isTrue);
      expect(NotificationService.shouldPresentForeground(msg, prefs, openConnectionId: 7), isFalse);
      expect(NotificationService.shouldPresentForeground(msg, prefs, openConnectionId: 8), isTrue);
      expect(
          NotificationService.shouldPresentForeground({'type': 'buddy_request', 'connectionId': '7'}, prefs,
              openConnectionId: 7),
          isTrue);
      expect(NotificationService.shouldPresentForeground(msg, const NotificationPrefs(messages: false)), isFalse);
      expect(
          NotificationService.shouldPresentForeground({'type': 'trip_update'}, const NotificationPrefs(master: false)),
          isFalse);
      expect(NotificationService.channelForType('buddy_message'), NotificationChannels.buddy);
      expect(NotificationService.channelForType('announcement'), NotificationChannels.announcements);
    });

    test('service hides the open chat, shows others and always pings the inbox', () async {
      final local = FakeLocalNotifier();
      var pings = 0;
      final s = NotificationService(local: local, onPush: (_) => pings++);
      BuddyChatScreen.openConnectionId.value = 7;
      await s.handleForegroundMessage(
          const PushMessage(title: 'Asha', body: 'Hi!', data: {'type': 'buddy_message', 'connectionId': '7'}));
      expect(local.shown, isEmpty);
      await s.handleForegroundMessage(
          const PushMessage(title: 'Ravi', body: 'Namaste', data: {'type': 'buddy_message', 'connectionId': '8'}));
      expect(local.shown.single.$1, NotificationIds.chatBase + 8);
      expect(local.shown.single.$4, NotificationChannels.buddy);
      expect(local.shown.single.$5['connectionId'], '8');
      BuddyChatScreen.openConnectionId.value = null;
      await s.handleForegroundMessage(
          const PushMessage(title: 'Asha', body: 'Again', data: {'type': 'buddy_message', 'connectionId': '7'}));
      expect(local.shown.length, 2);
      expect(pings, 3);
      s.dispose();
    });
  });

  group('service scheduling', () {
    test('reschedule is idempotent and cancels categories turned off', () async {
      final local = FakeLocalNotifier();
      final s = NotificationService(local: local, clock: () => at(2026, 11, 5, 10, 0))..debugRegistered = true;
      await s.load();
      await s.rescheduleAll();
      final first = local.scheduled.keys.toSet();
      expect(
          first, containsAll([NotificationIds.dailyHoroscope, NotificationIds.checkinBase, NotificationIds.reengage3]));
      await s.rescheduleAll();
      expect(local.scheduled.keys.toSet(), first);

      await s.updatePrefs(s.prefs.copyWith(horoscope: false, checkin: false));
      expect(local.scheduled.containsKey(NotificationIds.dailyHoroscope), isFalse);
      expect(local.scheduled.containsKey(NotificationIds.checkinBase), isFalse);
      expect(local.cancelled, contains(NotificationIds.dailyHoroscope));

      await s.updatePrefs(s.prefs.copyWith(master: false));
      expect(local.scheduled, isEmpty);
      s.dispose();
    });

    test('a check-in moves the reminder to tomorrow', () async {
      final local = FakeLocalNotifier();
      final s = NotificationService(local: local, clock: () => at(2026, 11, 5, 10, 0))..debugRegistered = true;
      await s.load();
      await s.rescheduleAll();
      expect(local.scheduled[NotificationIds.checkinBase]!.when, at(2026, 11, 5, 19, 30));
      s.markCheckedIn(6);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(local.scheduled[NotificationIds.checkinBase]!.when, at(2026, 11, 6, 19, 30));
      expect(local.scheduled[NotificationIds.checkinBase]!.title, contains('6-day streak'));
      s.dispose();
    });

    test('pre-prompt: only when permission is off, at most once per 14 days', () async {
      final local = FakeLocalNotifier()..granted = false;
      final s = NotificationService(local: local);
      await s.load();
      await s.refreshPermission();
      expect(await s.shouldShowPrePrompt(), isTrue);
      SharedPreferences.setMockInitialValues(
          {'notif_preprompt_at': DateTime.now().subtract(const Duration(days: 3)).toIso8601String()});
      expect(await s.shouldShowPrePrompt(), isFalse);
      SharedPreferences.setMockInitialValues(
          {'notif_preprompt_at': DateTime.now().subtract(const Duration(days: 15)).toIso8601String()});
      expect(await s.shouldShowPrePrompt(), isTrue);
      local.granted = true;
      await s.refreshPermission();
      expect(await s.shouldShowPrePrompt(), isFalse);
      s.dispose();
    });
  });

  group('settings screen', () {
    Future<NotificationService> pump(WidgetTester tester, FakeLocalNotifier local, {bool registered = true}) async {
      tester.view.physicalSize = const Size(320 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = NotificationService(local: local, clock: () => at(2026, 11, 5, 10, 0))..debugRegistered = registered;
      await s.load();
      await tester.pumpWidget(ChangeNotifierProvider<NotificationService>.value(
        value: s,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const NotificationSettingsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      return s;
    }

    bool switchValue(WidgetTester tester, String key) => tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

    testWidgets('renders at 320px / 1.3x and toggles categories', (tester) async {
      final local = FakeLocalNotifier();
      final s = await pump(tester, local);
      expect(tester.takeException(), isNull);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byKey(const Key('notif_permission_banner')), findsNothing);
      for (final k in [
        'notif_master',
        'notif_horoscope',
        'notif_checkin',
        'notif_festivals',
        'notif_nudges',
        'notif_buddy',
        'notif_messages',
        'notif_trips',
        'notif_announcements'
      ]) {
        expect(switchValue(tester, k), isTrue, reason: k);
      }
      expect(find.text('7:30 AM'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notif_festivals')));
      await tester.pumpAndSettle();
      expect(s.prefs.festivals, isFalse);
      expect(switchValue(tester, 'notif_festivals'), isFalse);

      await tester.tap(find.byKey(const Key('notif_messages')));
      await tester.pump(const Duration(seconds: 1)); // server sync debounce
      expect(s.prefs.messages, isFalse);

      // Master off disables (and visually clears) every category.
      await tester.tap(find.byKey(const Key('notif_master')));
      await tester.pumpAndSettle();
      expect(s.prefs.master, isFalse);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('notif_horoscope'))).onChanged, isNull);
      expect(switchValue(tester, 'notif_horoscope'), isFalse);
      expect(s.prefs.horoscope, isTrue, reason: 'category choice is kept');
      expect(local.scheduled, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('guests: account toggles disabled with a hint', (tester) async {
      await pump(tester, FakeLocalNotifier(), registered: false);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('notif_buddy'))).onChanged, isNull);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('notif_festivals'))).onChanged, isNotNull);
      expect(find.textContaining('Log in to get buddy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the "Notifications are off" banner and opens settings', (tester) async {
      final local = FakeLocalNotifier()..granted = false;
      SharedPreferences.setMockInitialValues({'notif_perm_asked': true});
      await pump(tester, local);
      expect(find.byKey(const Key('notif_permission_banner')), findsOneWidget);
      expect(find.text('Notifications are off'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(local.settingsOpened, 1, reason: 'already asked once: go to system settings');
      expect(tester.takeException(), isNull);
    });

    testWidgets('banner asks the OS first when never asked', (tester) async {
      final local = FakeLocalNotifier()
        ..granted = false
        ..grantOnRequest = true;
      final s = await pump(tester, local);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(local.requests, 1);
      expect(local.settingsOpened, 0);
      expect(s.permissionGranted, isTrue);
      expect(find.byKey(const Key('notif_permission_banner')), findsNothing);
    });
  });
}
