import 'package:cosmicguide/screens/meetups/meetup_detail_screen.dart';
import 'package:cosmicguide/screens/meetups/meetup_widgets.dart';
import 'package:cosmicguide/screens/meetups/meetups_screen.dart';
import 'package:cosmicguide/screens/meetups/propose_meetup_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/meetup_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
final _now = DateTime.now();

Map<String, dynamic> meetupJson({
  int id = 1,
  String title = 'Sandhya aarti together',
  String type = 'aarti',
  Duration startsIn = const Duration(days: 2),
  int capacity = 20,
  int going = 6,
  bool womenOnly = false,
  Map<String, dynamic>? host,
  String? myStatus,
  String status = 'approved',
  List<Map<String, dynamic>>? attendees,
  List<Map<String, dynamic>>? peopleYouMet,
  String? checkinCode,
  bool isHost = false,
}) {
  final start = _now.add(startsIn);
  return {
    'id': id,
    'title': title,
    'type': type,
    'status': status,
    'phase': startsIn.isNegative ? 'live' : 'upcoming',
    'venueName': 'ISKCON Temple',
    'city': 'Delhi',
    'address': 'Hare Krishna Hill, East of Kailash',
    'startsAt': start.toUtc().toIso8601String(),
    'endsAt': start.add(const Duration(hours: 2)).toUtc().toIso8601String(),
    'distanceKm': 7,
    'capacity': capacity,
    'goingCount': going,
    'spotsLeft': capacity - going,
    'womenOnly': womenOnly,
    'official': host == null,
    'host': host,
    'isHost': isHost,
    'myStatus': myStatus,
    'attendees': attendees,
    'description': 'We sing the aarti together and share prasad.',
    'mapsUrl': 'https://www.google.com/maps/search/?api=1&query=ISKCON',
    'checkinOpensAt': start.subtract(const Duration(minutes: 30)).toUtc().toIso8601String(),
    'coinsForCheckin': 100,
    if (checkinCode != null) 'checkinCode': checkinCode,
    if (peopleYouMet != null) 'peopleYouMet': peopleYouMet,
  };
}

class FakeMeetupBackend extends BackendService {
  bool loggedIn = true;
  List<Map<String, dynamic>> list = [meetupJson()];
  Map<String, dynamic> detail = meetupJson();
  Map<String, dynamic> proposeStatus = {'canPropose': false, 'reason': 'NOT_VERIFIED', 'remainingThisWeek': 2};
  final calls = <(String, String, Map<String, dynamic>?)>[];

  /// "METHOD /path" -> (message, status, code) failure.
  final failures = <String, (String, int, String)>{};
  String? _code;
  @override
  String? get lastErrorCode => _code;

  /// Responds to POST /meetups/:id/checkin.
  Map<String, dynamic> Function(Map<String, dynamic>? body)? onCheckin;

  @override
  bool get isAuthenticated => loggedIn;
  @override
  Map<String, dynamic>? get user => loggedIn ? {'id': 2, 'fullName': 'Ravi Kumar'} : null;

  int count(String method, String path) => calls.where((c) => c.$1 == method && c.$2.split('?').first == path).length;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add((method, path, body));
    final p = path.split('?').first;
    final f = failures.remove('$method $p');
    _code = f?.$3;
    if (f != null) throw BackendException(f.$1, statusCode: f.$2);
    if (method == 'GET' && p == '/meetups') {
      return {'origin': path.contains('lat=') ? 'location' : 'none', 'radiusKm': path.contains('lat=') ? 25 : null, 'meetups': list};
    }
    if (method == 'GET' && p == '/meetups/can-propose') return proposeStatus;
    if (method == 'GET' && p.startsWith('/meetups/')) return {'meetup': detail};
    if (method == 'POST' && p.endsWith('/rsvp')) {
      detail = {...detail, 'myStatus': 'going', 'goingCount': (detail['goingCount'] as int) + 1, 'spotsLeft': (detail['spotsLeft'] as int) - 1};
      return {'meetup': detail, 'changed': true};
    }
    if (method == 'POST' && p.endsWith('/cancel')) {
      detail = {...detail, 'myStatus': 'cancelled'};
      return {'meetup': detail};
    }
    if (method == 'POST' && p.endsWith('/checkin')) return onCheckin!(body);
    if (method == 'POST' && p == '/buddy/connect') return {'connection': {'id': 9, 'status': 'pending'}};
    throw BackendException('unexpected $method $path', statusCode: 500);
  }
}

late MeetupService service;
final reminders = <(int, DateTime?)>[];

Future<void> pumpMeetups(WidgetTester tester, FakeMeetupBackend backend, Widget child,
    {double width = 320, double textScale = 1.3, bool locationGranted = false}) async {
  tester.view.physicalSize = Size(width * 3, 2000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  service = MeetupService(backend)
    ..debugPermission = (({required bool ask}) async => locationGranted || ask ? null : MeetupLocationIssue.denied)
    ..debugLocator = (({required bool precise}) async => (lat: 28.5535, lng: 77.2588))
    ..debugReminder = ((m, when) => reminders.add((m.id, when)));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: backend),
      ChangeNotifierProvider<MeetupService>.value(value: service),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      routes: {'/login': (_) => const Scaffold(body: Text('LOGIN SCREEN'))},
      home: child,
    ),
  ));
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Unmounts (cancels the detail screen's minute ticker).
Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reminders.clear();
  });

  group('MeetupsScreen', () {
    testWidgets('lists cards with date, venue, distance, spots, women-only and verified host at 320px / 1.3x', (tester) async {
      final b = FakeMeetupBackend()
        ..list = [
          meetupJson(),
          meetupJson(id: 2, title: 'Mahila kirtan', type: 'kirtan', womenOnly: true, host: {'displayName': 'Asha', 'verified': true}),
          meetupJson(id: 3, title: 'Full seva', type: 'seva', capacity: 5, going: 5),
        ];
      await pumpMeetups(tester, b, const MeetupsScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Satsang near you'), findsOneWidget);
      expect(find.text('Showing all upcoming meetups'), findsOneWidget);
      expect(find.text('Sandhya aarti together'), findsOneWidget);
      expect(find.textContaining('7 km'), findsWidgets);
      expect(find.textContaining('14 spots left'), findsWidgets);
      expect(find.text('Women only'), findsOneWidget);
      expect(find.text('Hosted by Asha'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.textContaining('Official CosmicGuide event'), findsWidgets);
      expect(find.text('Full seva'), findsOneWidget);
      expect(find.text('Full'), findsWidgets);
      // No location permission: listed without coordinates.
      expect(b.calls.first.$2, '/meetups');
    });

    testWidgets('uses the location when granted, filters by type', (tester) async {
      final b = FakeMeetupBackend();
      await pumpMeetups(tester, b, const MeetupsScreen(), locationGranted: true, width: 412, textScale: 1.0);
      expect(b.calls.last.$2, contains('lat=28.55'));
      expect(b.calls.last.$2, contains('lng=77.26'));
      expect(find.text('Within 25 km of you'), findsOneWidget);
      await tapText(tester, 'Bhajan sandhya');
      expect(b.calls.last.$2, contains('type=bhajan_sandhya'));
    });

    testWidgets('"Use my location" asks and reloads', (tester) async {
      final b = FakeMeetupBackend();
      await pumpMeetups(tester, b, const MeetupsScreen());
      await tapText(tester, 'Use my location');
      expect(b.calls.last.$2, contains('lat='));
      expect(find.text('Within 25 km of you'), findsOneWidget);
    });

    testWidgets('empty state invites to propose; propose gate explains verification', (tester) async {
      final b = FakeMeetupBackend()..list = [];
      await pumpMeetups(tester, b, const MeetupsScreen());
      expect(find.text('No meetups near you yet'), findsOneWidget);
      await tapText(tester, 'Propose a meetup');
      expect(find.byType(ProposeMeetupScreen), findsOneWidget);
      expect(find.text('Get verified to host'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('error state retries', (tester) async {
      final b = FakeMeetupBackend()..failures['GET /meetups'] = ('Server down', 500, 'X');
      await pumpMeetups(tester, b, const MeetupsScreen());
      expect(find.text('Server down'), findsOneWidget);
      await tapText(tester, 'Try again');
      expect(find.text('Sandhya aarti together'), findsOneWidget);
    });
  });

  group('MeetupDetailScreen', () {
    testWidgets('guest sees details and a log-in action', (tester) async {
      final b = FakeMeetupBackend()..loggedIn = false;
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 1));
      expect(find.text('Sandhya aarti together'), findsOneWidget);
      expect(find.text('Open in Maps'), findsOneWidget);
      expect(find.text('Log in to RSVP'), findsOneWidget);
      await tapText(tester, 'Log in to RSVP');
      expect(find.text('LOGIN SCREEN'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('RSVP then cancel; reminder is scheduled; full meetup cannot be joined', (tester) async {
      final b = FakeMeetupBackend();
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 1));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('RSVP to see who is going'), findsOneWidget);
      await tapText(tester, "RSVP · I'm going");
      expect(b.count('POST', '/meetups/1/rsvp'), 1);
      expect(find.text("You're going"), findsOneWidget);
      expect(reminders.single.$1, 1);
      expect(reminders.single.$2, isNotNull);
      await tapText(tester, 'Cancel RSVP');
      await tester.tap(find.text('Cancel RSVP').last); // dialog confirm
      await tester.pumpAndSettle();
      expect(b.count('POST', '/meetups/1/cancel'), 1);
      expect(find.text("RSVP · I'm going"), findsOneWidget);
      await unmount(tester);

      final full = FakeMeetupBackend()..detail = meetupJson(capacity: 5, going: 5);
      await pumpMeetups(tester, full, const MeetupDetailScreen(meetupId: 1));
      expect(find.text('This meetup is full'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('RSVP error (FULL) shows a message and reloads', (tester) async {
      final b = FakeMeetupBackend()..failures['POST /meetups/1/rsvp'] = ('This meetup is full', 409, 'FULL');
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 1));
      await tapText(tester, "RSVP · I'm going");
      expect(find.text('This meetup is full'), findsOneWidget);
      expect(b.count('GET', '/meetups/1'), 2);
      await unmount(tester);
    });

    testWidgets('check-in with location shows coins, then "People you met" with Connect', (tester) async {
      final b = FakeMeetupBackend()
        ..detail = meetupJson(startsIn: const Duration(minutes: 10), myStatus: 'going', attendees: [
          {'displayName': 'Meera', 'initials': 'M', 'verified': true},
        ]);
      b.onCheckin = (body) {
        b.detail = {
          ...b.detail,
          'myStatus': 'checked_in',
          'peopleYouMet': [
            {'userId': 5, 'displayName': 'Meera', 'initials': 'M', 'verified': true, 'canConnect': true},
          ],
        };
        return {'checkedIn': true, 'coinsAwarded': 100, 'balance': 100, 'meetup': b.detail};
      };
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('Meera'), findsOneWidget);
      await tapText(tester, 'Check in at venue · +100 coins');
      final call = b.calls.lastWhere((c) => c.$2 == '/meetups/1/checkin');
      expect(call.$3, {'lat': 28.5535, 'lng': 77.2588});
      expect(find.textContaining("You're checked in"), findsOneWidget);
      expect(find.text('People you met'), findsOneWidget);
      await tapText(tester, 'Connect');
      final c = b.calls.lastWhere((c) => c.$2 == '/buddy/connect');
      expect(c.$3, {'userId': 5, 'intent': 'spiritual'});
      expect(find.text('Requested'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('too far from the venue falls back to the host code', (tester) async {
      final b = FakeMeetupBackend()..detail = meetupJson(startsIn: const Duration(minutes: -20), myStatus: 'going');
      b.failures['POST /meetups/1/checkin'] = ('You need to be at the venue to check in (within 300 m)', 409, 'TOO_FAR');
      b.onCheckin = (body) {
        b.detail = {...b.detail, 'myStatus': 'checked_in'};
        return {'checkedIn': true, 'coinsAwarded': 100, 'balance': 300, 'meetup': b.detail};
      };
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 1), width: 412, textScale: 1.0);
      await tapText(tester, 'Check in at venue · +100 coins');
      expect(find.text('Enter host code'), findsOneWidget);
      expect(find.textContaining('Indoors?'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('meetup-code-field')), '482913');
      await tester.pump();
      await tapText(tester, 'Check in');
      final call = b.calls.lastWhere((c) => c.$2 == '/meetups/1/checkin');
      expect(call.$3, {'code': '482913'});
      expect(find.textContaining("You're checked in"), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('not yet open: going without a check-in button; host sees the code', (tester) async {
      final b = FakeMeetupBackend()..detail = meetupJson(myStatus: 'going', isHost: true, checkinCode: '482913', host: {'displayName': 'Ravi', 'verified': true});
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 1));
      expect(find.textContaining('Check in at venue'), findsNothing);
      expect(find.text("You're going"), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);
      expect(find.text('Hosted by you'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('404 shows a not-available state', (tester) async {
      final b = FakeMeetupBackend()..failures['GET /meetups/7'] = ('gone', 404, 'NOT_FOUND');
      await pumpMeetups(tester, b, const MeetupDetailScreen(meetupId: 7));
      expect(find.text('This meetup is no longer available.'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('ProposeMeetupScreen', () {
    testWidgets('verified host sees the form; guests are asked to log in', (tester) async {
      final b = FakeMeetupBackend()..proposeStatus = {'canPropose': true, 'remainingThisWeek': 1, 'canHostWomenOnly': true};
      await pumpMeetups(tester, b, const ProposeMeetupScreen());
      // temples call fails in the fake -> empty list, form still renders
      expect(find.text('Send for review'), findsOneWidget);
      expect(find.textContaining('1 of 2 proposals left'), findsOneWidget);
      expect(find.text('Women only'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);

      final guest = FakeMeetupBackend()..loggedIn = false;
      await pumpMeetups(tester, guest, const ProposeMeetupScreen());
      expect(find.text('Log in to host'), findsOneWidget);
    });
  });

  group('MeetupsHomeRail', () {
    testWidgets('shows compact cards and See all', (tester) async {
      var seeAll = 0;
      final b = FakeMeetupBackend()..list = [meetupJson(), meetupJson(id: 2, title: 'Bhajan sandhya at ghat', type: 'bhajan_sandhya')];
      await pumpMeetups(tester, b, Scaffold(body: ListView(children: [MeetupsHomeRail(onSeeAll: () => seeAll++)])));
      expect(find.text('Satsang near you'), findsOneWidget);
      expect(find.text('Sandhya aarti together'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'See all');
      expect(seeAll, 1);
      await tapText(tester, 'Sandhya aarti together');
      expect(find.byType(MeetupDetailScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('empty list shows an invite card; errors hide the rail', (tester) async {
      final b = FakeMeetupBackend()..list = [];
      await pumpMeetups(tester, b, const Scaffold(body: MeetupsHomeRail()));
      expect(find.text('No meetups near you yet'), findsOneWidget);
      await unmount(tester);
      final e =FakeMeetupBackend()..failures['GET /meetups'] = ('down', 500, 'X');
      await pumpMeetups(tester, e, const Scaffold(body: MeetupsHomeRail()));
      expect(find.text('Satsang near you'), findsNothing);
    });
  });

  test('reminder time: 6 pm the day before, else 2 h before, else none', () {
    final now = DateTime(2026, 11, 5, 10);
    Meetup at(DateTime s) => Meetup(id: 1, title: 't', venueName: 'v', startsAt: s, endsAt: s.add(const Duration(hours: 1)));
    expect(MeetupService.reminderTime(at(DateTime(2026, 11, 8, 7)), now), DateTime(2026, 11, 7, 18));
    expect(MeetupService.reminderTime(at(DateTime(2026, 11, 5, 19)), now), DateTime(2026, 11, 5, 17));
    expect(MeetupService.reminderTime(at(DateTime(2026, 11, 5, 11)), now), isNull);
  });

  test('Meetup.tryParse is defensive', () {
    expect(Meetup.tryParse(null), isNull);
    expect(Meetup.tryParse({'id': 1}), isNull);
    final m = Meetup.tryParse({...meetupJson(), 'capacity': '20', 'goingCount': '6', 'spotsLeft': null})!;
    expect(m.capacity, 20);
    expect(m.spotsLeft, 14);
    expect(m.official, isTrue);
  });
}
