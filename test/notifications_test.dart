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
    List<PlannedNotification> dayOf(List<PlannedNotification> plan, int y, int m, int d) =>
        plan.where((p) => p.when.year == y && p.when.month == m && p.when.day == d).toList();

    test('five a day, all between 10:00 and 22:00 IST, for ten days', () {
      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 6, 0)));
      expect(plan.length, NotificationIds.planDays * NotificationIds.slotsPerDay);
      for (final p in plan) {
        final t = tz.TZDateTime.from(p.when, ist);
        final mins = t.hour * 60 + t.minute;
        expect(mins >= 10 * 60 && mins < 22 * 60, isTrue, reason: '${p.title} at $t');
        expect(p.repeat, NotificationRepeat.none);
      }
      final today = dayOf(plan, 2026, 11, 5);
      expect([for (final p in today) (p.when.hour, p.when.minute)], [(10, 0), (13, 0), (16, 30), (19, 30), (21, 15)]);
      expect(today.first.payload['type'], 'daily_horoscope');
      expect(plan.map((p) => p.id).toSet().length, plan.length, reason: 'ids are unique');
      expect(plan.every((p) => NotificationIds.managed.contains(p.id)), isTrue);
    });

    test('slots already passed today are skipped; copy rotates day to day', () {
      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 17, 0)));
      expect([for (final p in dayOf(plan, 2026, 11, 5)) p.when.hour], [19, 21]);
      final afternoons = [
        for (var d = 6; d < 10; d++) dayOf(plan, 2026, 11, d).firstWhere((p) => p.when.hour == 13).payload['type']
      ];
      expect(afternoons.toSet().length, greaterThan(1));
    });

    test('device in another time zone still gets India-time slots', () {
      final ny = tz.getLocation('America/New_York');
      final plan = NotificationSchedule.plan(input(tz.TZDateTime(ny, 2026, 11, 5, 12)));
      expect(plan, isNotEmpty);
      for (final p in plan) {
        final t = tz.TZDateTime.from(p.when, ist);
        expect(t.hour >= 10 && t.hour < 22, isTrue);
      }
    });

    test('horoscope time is kept between 10:00 and 12:00 and personalised', () {
      final early = NotificationSchedule.plan(ScheduleInput(
        now: at(2026, 11, 5, 6, 0),
        prefs: const NotificationPrefs(horoscopeHour: 5, horoscopeMinute: 45),
        moonSign: 'Leo',
      ));
      final h = early.firstWhere((p) => p.payload['type'] == 'daily_horoscope');
      expect(h.when, at(2026, 11, 5, 10, 0));
      expect(h.body, contains('Leo'));
      final late = NotificationSchedule.plan(
          ScheduleInput(now: at(2026, 11, 5, 6, 0), prefs: const NotificationPrefs(horoscopeHour: 18)));
      expect(late.first.when, at(2026, 11, 5, 12, 0));
      final off = NotificationSchedule.plan(
          ScheduleInput(now: at(2026, 11, 5, 6, 0), prefs: const NotificationPrefs(horoscope: false)));
      expect(dayOf(off, 2026, 11, 5).any((p) => p.when.hour == 10), isFalse);
    });

    test('check-in reminder helper: today 19:30 unless already checked in', () {
      final notYet = NotificationSchedule.checkinTimes(at(2026, 11, 5, 10, 0), checkedInToday: false);
      expect(notYet, [at(2026, 11, 5, 19, 30), at(2026, 11, 6, 19, 30), at(2026, 11, 7, 19, 30)]);
      final done = NotificationSchedule.checkinTimes(at(2026, 11, 5, 10, 0), checkedInToday: true);
      expect(done.first, at(2026, 11, 6, 19, 30), reason: 'skipped today after a check-in');
    });

    test('evening slot: streak check-in, aarti once checked in, nothing coin-related for guests', () {
      final notYet = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 30), streak: 5));
      final eve = dayOf(notYet, 2026, 11, 5).firstWhere((p) => p.when.hour == 19);
      expect(eve.title, contains('5-day streak'));
      expect(eve.payload['type'], 'checkin');
      expect(dayOf(notYet, 2026, 11, 6).firstWhere((p) => p.when.hour == 19).title, isNot(contains('streak')));

      final done = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 30), checkedIn: true, streak: 5));
      expect(dayOf(done, 2026, 11, 5).firstWhere((p) => p.when.hour == 19).payload['type'], 'videos');
      expect(dayOf(done, 2026, 11, 6).firstWhere((p) => p.when.hour == 19).payload['type'], 'checkin');

      final guest = NotificationSchedule.plan(input(at(2026, 11, 5, 10, 30), registered: false));
      expect(guest.any((p) => const {'checkin', 'mindset', 'trip_update'}.contains(p.payload['type'])), isFalse);
      expect(guest, isNotEmpty, reason: 'guests keep local reminders');
    });

    test('festival eve and day replace the night and morning slots', () {
      final plan = NotificationSchedule.plan(input(at(2026, 11, 5, 9, 0), festivals: [
        FestivalItem(DateTime(2026, 11, 8), 'Diwali'),
        FestivalItem(DateTime(2026, 11, 8), 'Lakshmi Puja'),
      ]));
      final eve = dayOf(plan, 2026, 11, 7).firstWhere((p) => p.when.hour == 21);
      expect(eve.title, 'Tomorrow: Diwali & Lakshmi Puja');
      expect(eve.payload, {'type': 'festival', 'name': 'Diwali & Lakshmi Puja'});
      final morning = dayOf(plan, 2026, 11, 8).firstWhere((p) => p.when.hour == 10);
      expect(morning.title, 'Today: Diwali & Lakshmi Puja');
      expect(morning.channel, NotificationChannels.festivals);

      final off = NotificationSchedule.plan(input(at(2026, 11, 5, 9, 0),
          prefs: const NotificationPrefs(festivals: false), festivals: [FestivalItem(DateTime(2026, 11, 8), 'Diwali')]));
      expect(off.any((p) => p.payload['type'] == 'festival'), isFalse);
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

    test('nudges off keeps only horoscope, check-in and festivals', () {
      final plan =
          NotificationSchedule.plan(input(at(2026, 11, 5, 9, 0), prefs: const NotificationPrefs(nudges: false)));
      expect(plan.map((p) => p.payload['type']).toSet(), {'daily_horoscope', 'checkin'});
    });

    test('mindset only while questions remain; every nudge routes to a real screen', () {
      final none = NotificationSchedule.plan(input(at(2026, 11, 5, 9, 0), mindsetRemaining: 0));
      expect(none.any((p) => p.payload['type'] == 'mindset'), isFalse);
      final some = NotificationSchedule.plan(input(at(2026, 11, 5, 9, 0), mindsetRemaining: 10));
      for (final p in some) {
        final type = p.payload['type'];
        if (type == 'checkin' || type == 'festival') continue;
        expect(NotificationRouter.resolve(p.payload).destination, isNot(NotificationDestination.home), reason: type);
      }
    });

    test('one-off reminders are pulled earlier into the window', () {
      expect(NotificationSchedule.clampEarlierIntoWindow(at(2026, 11, 8, 6, 30)), at(2026, 11, 7, 21, 30));
      expect(NotificationSchedule.clampEarlierIntoWindow(at(2026, 11, 8, 23, 0)), at(2026, 11, 8, 21, 30));
      expect(NotificationSchedule.clampEarlierIntoWindow(at(2026, 11, 8, 18, 0)), at(2026, 11, 8, 18, 0));
    });

    test('master off schedules nothing', () {
      expect(NotificationSchedule.plan(input(at(2026, 11, 5, 10, 0), prefs: const NotificationPrefs(master: false))),
          isEmpty);
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
      // 10:00 has just passed, so day 0 starts at 13:00; day 1 has all five.
      final morning1 = NotificationIds.planId(1, 0), evening1 = NotificationIds.planId(1, 3);
      expect(first, containsAll([NotificationIds.planId(0, 1), morning1, evening1]));
      expect(first.contains(NotificationIds.dailyHoroscope), isFalse, reason: 'old repeating id is retired');
      await s.rescheduleAll();
      expect(local.scheduled.keys.toSet(), first);

      await s.updatePrefs(s.prefs.copyWith(horoscope: false, checkin: false, nudges: false));
      expect(local.scheduled.containsKey(morning1), isFalse);
      expect(local.scheduled.containsKey(evening1), isFalse);
      expect(local.cancelled, contains(morning1));

      await s.updatePrefs(s.prefs.copyWith(master: false));
      expect(local.scheduled, isEmpty);
      s.dispose();
    });

    test('a check-in moves the reminder to tomorrow', () async {
      final local = FakeLocalNotifier();
      final s = NotificationService(local: local, clock: () => at(2026, 11, 5, 10, 0))..debugRegistered = true;
      await s.load();
      await s.rescheduleAll();
      final today = NotificationIds.planId(0, 3), tomorrow = NotificationIds.planId(1, 3);
      expect(local.scheduled[today]!.when, at(2026, 11, 5, 19, 30));
      expect(local.scheduled[today]!.payload['type'], 'checkin');
      s.markCheckedIn(6);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(local.scheduled[today]!.payload['type'], isNot('checkin'), reason: 'already checked in today');
      expect(local.scheduled[tomorrow]!.when, at(2026, 11, 6, 19, 30));
      expect(local.scheduled[tomorrow]!.title, contains('6-day streak'));
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
      expect(find.text('10:00 AM'), findsOneWidget);

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
