import 'dart:convert';
import 'dart:io';

import 'package:cosmicguide/screens/guides/guide_detail_screen.dart';
import 'package:cosmicguide/screens/guides/guides_home_rail.dart';
import 'package:cosmicguide/screens/guides/guides_screen.dart';
import 'package:cosmicguide/screens/muhurat/muhurat_finder_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/guide_service.dart';
import 'package:cosmicguide/services/muhurat_service.dart';
import 'package:cosmicguide/services/notification_service.dart';
import 'package:cosmicguide/widgets/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeLocalNotifier implements LocalNotifier {
  final Map<int, PlannedNotification> scheduled = {};
  bool? granted = true;

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
  Future<bool> requestPermission() async => false;
  @override
  Future<void> openSettings() async {}
}

Map<String, dynamic> _fixture(String name) =>
    Map<String, dynamic>.from(jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map);

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class FakeBackend extends BackendService {
  bool failMuhurat = false;
  bool guidesOffline = false;
  final List<String> calls = [];
  final DateTime guideDate = DateTime.now().add(const Duration(days: 10));

  @override
  bool get isAuthenticated => false;

  @override
  Map<String, dynamic>? get kundliData => null;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add('$method $path');
    if (path == '/muhurat/events') {
      return {
        'events': MuhuratEvent.fallback
            .map((e) => {'id': e.id, 'label': e.label, 'labelHi': e.labelHi, 'icon': e.icon, 'note': e.note})
            .toList()
      };
    }
    if (path.startsWith('/muhurat?')) {
      if (failMuhurat) throw const BackendException('Server is busy', statusCode: 500);
      final event = Uri.parse(path).queryParameters['event'];
      if (event == 'marriage') return _fixture('muhurat_marriage_kharmas.json');
      return _fixture('muhurat_vehicle.json');
    }
    if (path == '/guides') {
      if (guidesOffline) throw const BackendException('offline');
      final raw = jsonDecode(File('assets/data/puja_guides.json').readAsStringSync()) as Map;
      return {
        'guides': [
          for (final g in raw['guides'] as List)
            {...Map<String, dynamic>.from(g as Map), 'steps': null, 'nextDate': _iso(guideDate)},
        ]
      };
    }
    if (path.startsWith('/guides/')) {
      if (guidesOffline) throw const BackendException('offline');
      final id = path.substring('/guides/'.length);
      final raw = jsonDecode(File('assets/data/puja_guides.json').readAsStringSync()) as Map;
      final g = (raw['guides'] as List).cast<Map>().firstWhere((g) => g['id'] == id);
      return {
        'guide': {...Map<String, dynamic>.from(g), 'nextDate': _iso(guideDate), 'nextDates': [_iso(guideDate)]}
      };
    }
    throw BackendException('unexpected $path');
  }
}

late tz.Location ist;

GuideService guideService(FakeBackend b, NotificationService? ns) => GuideService(b,
    loadAsset: () async => File('assets/data/puja_guides.json').readAsStringSync(), notifications: () => ns);

Widget host(Widget child, FakeBackend backend, {double width = 412, double scale = 1.0}) {
  return ChangeNotifierProvider<BackendService>.value(
    value: backend,
    child: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
}

Future<void> setSize(WidgetTester t, double width) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pump();
}

/// Scrolls until [f] is built and visible ([up] scrolls back towards the top).
Future<void> seek(WidgetTester t, Finder f, {bool up = false}) async {
  await t.scrollUntilVisible(f, up ? -250 : 250, scrollable: find.byType(Scrollable).first, maxScrolls: 80);
  await t.pumpAndSettle();
  expect(f, findsWidgets);
}

/// Scrolls the first scrollable down to the end, checking for layout errors on the way.
Future<void> scrollThrough(WidgetTester t) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 40; i++) {
    await t.drag(list, const Offset(0, -500));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull);
  }
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    ist = tz.getLocation('Asia/Kolkata');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugMuhuratShare = null;
    debugGuideShare = null;
  });

  group('Muhurat finder', () {
    testWidgets('event grid -> 3 result cards with reasons; reminder + share; no overflow at 320px x1.3',
        (t) async {
      await setSize(t, 320);
      final b = FakeBackend();
      final local = FakeLocalNotifier();
      final ns = NotificationService(local: local, clock: () => tz.TZDateTime(ist, 2026, 11, 5, 10));
      final shared = <String>[];
      debugMuhuratShare = (s) async => shared.add(s);
      var asked = 0;
      final svc = MuhuratService(b, notifications: () => ns);
      await t.pumpWidget(host(MuhuratFinderScreen(service: svc, onAskPandit: () => asked++), b, width: 320, scale: 1.3));
      await t.pumpAndSettle();
      await seek(t, find.text('Pick an occasion above'));
      await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('muhurat_event_vehicle_purchase')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(b.calls.any((c) => c.startsWith('GET /muhurat?event=vehicle_purchase&lat=28.61&lng=77.21&tz=Asia%2FKolkata')),
          isTrue);
      await seek(t, find.text('Best day'));

      // First card: reasons as ticks + actions
      await t.scrollUntilVisible(find.text('Best day'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Anuradha nakshatra is traditionally good for buying a vehicle'), findsOneWidget);
      await tapVisible(t, find.text('Add reminder').first);
      await t.pumpAndSettle();
      expect(local.scheduled.length, 2);
      final times = local.scheduled.values.map((n) => n.when.toUtc()).toList()..sort();
      expect(times[0], DateTime(2026, 11, 10, 18).toUtc());
      expect(times[1], DateTime(2026, 11, 11, 10).toUtc());
      for (final n in local.scheduled.values) {
        expect(n.id, greaterThanOrEqualTo(MuhuratService.reminderIdBase));
        expect(n.payload['type'], 'muhurat');
        expect(n.payload['date'], '2026-11-11');
      }
      expect(find.textContaining('Reminders set'), findsOneWidget);

      await tapVisible(t, find.text('Share').first);
      await t.pump();
      expect(shared.single, contains('2026-11-11'));
      expect(shared.single, contains('Best time'));
      await tapVisible(t, find.text('Ask a pandit to confirm').first);
      expect(asked, 1);

      await scrollThrough(t);
      expect(find.textContaining('Why other days were skipped'), findsOneWidget);
      expect(find.textContaining('general guidance'), findsOneWidget);
      ns.dispose();
    });

    testWidgets('marriage in Kharmas: pandit note, empty state; surgery shows the doctor note', (t) async {
      await setSize(t, 412);
      final b = FakeBackend();
      await t.pumpWidget(host(MuhuratFinderScreen(service: MuhuratService(b), onAskPandit: () {}), b));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('muhurat_event_marriage')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('No clearly auspicious day soon'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('confirmed by a pandit'), findsOneWidget);
      expect(find.text('Ask a pandit'), findsOneWidget);
      await t.scrollUntilVisible(find.textContaining('Kharmas'), 300, scrollable: find.byType(Scrollable).first);

      await t.scrollUntilVisible(find.byKey(const ValueKey('muhurat_event_surgery_or_medical')), -300,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const ValueKey('muhurat_event_surgery_or_medical')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.textContaining('Always follow your doctor'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byIcon(Icons.local_hospital_rounded), findsOneWidget);
    });

    testWidgets('server error shows a retry; city change re-runs the search and is remembered', (t) async {
      await setSize(t, 412);
      final b = FakeBackend()..failMuhurat = true;
      final svc = MuhuratService(b);
      await t.pumpWidget(host(MuhuratFinderScreen(service: svc), b));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('muhurat_event_travel_start')));
      await t.pumpAndSettle();
      await seek(t, find.text('Server is busy'));
      b.failMuhurat = false;
      await seek(t, find.text('Try again'));
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      await seek(t, find.text('Best day'));
      expect(find.text('Ask a pandit to confirm'), findsNothing); // no callback wired
      await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await t.pumpAndSettle();
      await seek(t, find.text('Change'));

      await t.tap(find.text('Change'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mumbai'));
      await t.pumpAndSettle();
      expect(find.text('Timings for Mumbai'), findsOneWidget);
      expect(b.calls.last, contains('lat=19.08&lng=72.88'));
      expect((await svc.savedPlace()).name, 'Mumbai');
    });

    test('reminder times and ids', () {
      expect(MuhuratService.reminderTimes(DateTime(2026, 12, 1)), [DateTime(2026, 11, 30, 18), DateTime(2026, 12, 1, 10)]);
      final a = MuhuratService.reminderId('marriage', DateTime(2026, 12, 1), 0);
      expect(MuhuratService.reminderId('marriage', DateTime(2026, 12, 1), 1), a + 1);
      expect(a, inInclusiveRange(MuhuratService.reminderIdBase, MuhuratService.reminderIdBase + 20000));
      final r = MuhuratResponse.fromJson(_fixture('muhurat_vehicle.json'), MuhuratEvent.fallback[1]);
      expect(r.results.length, 3);
      expect(r.results.first.bestWindow, isNotNull);
      expect(r.avoided, isNotEmpty);
    });
  });

  group('Puja & vrat guides', () {
    test('bundled JSON parses into 12 complete guides', () {
      final guides = GuideService.parse(File('assets/data/puja_guides.json').readAsStringSync());
      expect(guides.length, greaterThanOrEqualTo(12));
      for (final g in guides) {
        expect(g.hasDetail, isTrue, reason: g.id);
        expect(g.samagri, isNotEmpty);
        expect(g.katha, isNotEmpty);
        expect(g.aartiLines, isNotEmpty);
      }
      final somvar = guides.firstWhere((g) => g.id == 'somvar_vrat');
      expect(somvar.localNextDate(DateTime(2026, 11, 6))!.weekday, DateTime.monday);
      expect(guides.firstWhere((g) => g.id == 'ganesh_chaturthi').imageAsset, 'assets/images/ganesh.jpg');
      expect(guides.firstWhere((g) => g.id == 'karva_chauth').imageAsset, isNull);
    });

    for (final (width, scale) in [(320.0, 1.3), (412.0, 1.0)]) {
      testWidgets('list: search, category chips, cards at ${width.toInt()}px x$scale', (t) async {
        await setSize(t, width);
        final b = FakeBackend();
        await t.pumpWidget(host(GuidesScreen(service: guideService(b, null)), b, width: width, scale: scale));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(GuideCard), findsWidgets);
        await t.enterText(find.byType(TextField), 'mahashiv');
        await t.pumpAndSettle();
        expect(find.text('Mahashivratri'), findsOneWidget);
        expect(find.text('Karva Chauth'), findsNothing);
        await t.enterText(find.byType(TextField), '');
        await t.tap(find.text('Vrat'));
        await t.pumpAndSettle();
        expect(find.text('Ekadashi Vrat'), findsOneWidget);
        expect(find.text('Diwali Lakshmi Puja'), findsNothing);
        await t.enterText(find.byType(TextField), 'zzzz');
        await t.pumpAndSettle();
        expect(find.text('No guide found'), findsOneWidget);
      });

      testWidgets('detail renders every section without overflow at ${width.toInt()}px x$scale', (t) async {
        await setSize(t, width);
        final b = FakeBackend();
        for (final id in ['chhath_puja', 'navratri_kalash_sthapana', 'satyanarayan_katha']) {
          await t.pumpWidget(host(GuideDetailScreen(key: ValueKey(id), guideId: id, service: guideService(b, null)), b, width: width, scale: scale));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await seek(t, find.byKey(const ValueKey('guide_next_date')));
          await scrollThrough(t);
          expect(find.textContaining('follow your family tradition'), findsOneWidget);
        }
      });
    }

    testWidgets('samagri checklist persists per guide; share list', (t) async {
      await setSize(t, 412);
      final b = FakeBackend()..guidesOffline = true; // works offline from the bundle
      final shared = <String>[];
      debugGuideShare = (s) async => shared.add(s);
      final svc = guideService(b, null);
      await t.pumpWidget(host(GuideDetailScreen(guideId: 'diwali_lakshmi_puja', service: svc), b));
      await t.pumpAndSettle();
      expect(find.text('Diwali Lakshmi Puja'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('samagri_1')), 300, scrollable: find.byType(Scrollable).first);
      await tapVisible(t, find.byKey(const ValueKey('samagri_0')));
      await tapVisible(t, find.byKey(const ValueKey('samagri_1')));
      await t.pumpAndSettle();
      await seek(t, find.text('2 of 10 ready'));
      expect(await svc.checked('diwali_lakshmi_puja'), {0, 1});
      expect(await svc.checked('karva_chauth'), isEmpty);

      await seek(t, find.text('Share list'), up: true);
      await tapVisible(t, find.text('Share list'));
      await t.pump();
      expect(shared.single, contains('☑ Lakshmi and Ganesha idols or picture'));
      expect(shared.single, contains('☐ Clay diyas'));

      // Re-open: ticks restored
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(host(GuideDetailScreen(guideId: 'diwali_lakshmi_puja', service: svc), b));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const ValueKey('samagri_1')), 300, scrollable: find.byType(Scrollable).first);
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('samagri_0'))).value, isTrue);
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('samagri_2'))).value, isFalse);
      // Offline, a lunar festival has no date -> no Remind button
      await seek(t, find.textContaining('Check your local panchang'), up: true);
      expect(find.text('Remind me'), findsNothing);
    });

    testWidgets('Remind me schedules eve 18:00 and morning 10:00 for the next date', (t) async {
      await setSize(t, 412);
      final b = FakeBackend();
      final local = FakeLocalNotifier();
      final ns = NotificationService(local: local, clock: () => tz.TZDateTime.now(ist));
      await t.pumpWidget(host(GuideDetailScreen(guideId: 'karva_chauth', service: guideService(b, ns)), b));
      await t.pumpAndSettle();
      await t.tap(find.text('Remind me'));
      await t.pumpAndSettle();
      final d = b.guideDate;
      final times = local.scheduled.values.map((n) => n.when.toUtc()).toList()..sort();
      expect(times, [DateTime(d.year, d.month, d.day - 1, 18).toUtc(), DateTime(d.year, d.month, d.day, 10).toUtc()]);
      for (final n in local.scheduled.values) {
        expect(n.payload, {'type': 'guide', 'guideId': 'karva_chauth'});
        expect(n.id, greaterThanOrEqualTo(GuideService.reminderIdBase));
      }
      expect(find.textContaining('We will remind you'), findsOneWidget);

      // Permission denied -> nothing scheduled, friendly error
      local.scheduled.clear();
      local.granted = false;
      await ns.refreshPermission();
      ScaffoldMessenger.of(t.element(find.byType(GuideDetailScreen))).hideCurrentSnackBar();
      await t.pumpAndSettle();
      await t.tap(find.text('Remind me'));
      await t.pumpAndSettle();
      expect(local.scheduled, isEmpty);
      expect(find.textContaining('Could not set a reminder'), findsOneWidget);
      ns.dispose();
    });

    testWidgets('home rail: cards, See all, open detail; 320px x1.3', (t) async {
      await setSize(t, 320);
      final b = FakeBackend();
      var seeAll = 0;
      await t.pumpWidget(host(
          Scaffold(body: ListView(children: [GuidesHomeRail(onSeeAll: () => seeAll++, service: guideService(b, null))])), b,
          width: 320, scale: 1.3));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Puja & vrat guides'), findsOneWidget);
      await t.tap(find.text('See all'));
      expect(seeAll, 1);
      await t.tap(find.byType(AppCard).first);
      await t.pumpAndSettle();
      expect(find.byType(GuideDetailScreen), findsOneWidget);
    });
  });
}
