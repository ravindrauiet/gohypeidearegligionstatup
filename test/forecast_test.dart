import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pujakaro/models/forecast.dart';
import 'package:pujakaro/screens/date_explorer_screen.dart';
import 'package:pujakaro/screens/forecast_screen.dart';
import 'package:pujakaro/screens/life_timeline_screen.dart';
import 'package:pujakaro/services/backend_service.dart';
import 'package:pujakaro/widgets/your_day_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake contract payloads
// ---------------------------------------------------------------------------

const _long = 'This is a deliberately long sentence that keeps going so that narrow screens and large '
    'text sizes are exercised properly without any overflow appearing anywhere at all.';

Map<String, dynamic> _meta({bool known = false}) => {
      'profile': {'name': 'Ravindra Nath Jha', 'isFamily': false, 'familyId': null, 'relationship': null},
      'birthTimeKnown': known,
      'accuracyNote': known ? null : 'Your birth time is unknown, so Lagna-based house readings are approximate.',
      'generatedBy': 'ai',
    };

Map<String, dynamic> _summary(int score, String mood) => {
      'headline': 'A steady, productive day — trust slow progress over shortcuts today',
      'narrative': 'Ravindra, Saturn asks for patience while Jupiter quietly supports learning. $_long',
      'mood': mood,
      'overallScore': score,
    };

Map<String, dynamic> _scores() => {
      for (final k in ['career', 'love', 'money', 'health', 'mind'])
        k: {'score': 40 + k.length * 7, 'label': 'Good', 'reason': 'Saturn in your 10th from Moon drives $k matters. $_long'},
    };

Map<String, dynamic> _transit(String planet, int house, String effect, {bool retro = false}) => {
      'planet': planet,
      'sign': 'Sagittarius',
      'degree': 14.6,
      'nakshatra': 'Purva Ashadha',
      'retrograde': retro,
      'houseFromMoon': house,
      'houseFromLagna': (house + 3) % 12 + 1,
      'effect': effect,
      'title': '$planet in your ${house}th from Moon',
      'meaning': 'Classical gochara result in plain words. $_long',
      'realLife': ['You may notice delays at work', 'Seniors watch you closely', _long],
      'doList': ['Finish pending tasks', 'Be punctual'],
      'avoidList': ['Shortcuts', 'Arguing with authority'],
      'since': '2025-03-29',
      'until': '2027-06-03',
    };

const _planets = ['Saturn', 'Jupiter', 'Rahu', 'Ketu', 'Mars', 'Sun', 'Venus', 'Mercury', 'Moon'];

Map<String, dynamic> _dasha() => {
      'mahadasha': 'Saturn',
      'antardasha': 'Mercury',
      'pratyantardasha': 'Venus',
      'mahadashaEnds': '2036-04-11',
      'antardashaEnds': '2027-12-20',
      'pratyantardashaEnds': '2026-11-02',
      'theme': 'Hard work meets clever communication. $_long',
    };

Map<String, dynamic> _remedy() => {
      'title': 'Saturday Shani remedy',
      'mantra': 'Om Sham Shanaishcharaya Namah (108 times)',
      'action': 'Offer mustard oil and help an elderly person. $_long',
      'color': 'Navy blue',
      'day': 'Saturday',
    };

Map<String, dynamic> _event(String date, String type) => {
      'date': date,
      'time': '07:42 AM',
      'type': type,
      'title': type == 'festival' ? 'Sharad Purnima celebration day' : 'Mercury enters Libra',
      'description': 'What happens in the sky. $_long',
      'personalImpact': 'For your chart this lights up communication. $_long',
      'importance': 3,
    };

Map<String, dynamic> dayPayload([String date = '2026-10-07']) => {
      'type': 'day',
      'date': date,
      'weekday': 'Wednesday',
      ..._meta(),
      'summary': _summary(68, 'good'),
      'scores': _scores(),
      'moon': {
        'sign': 'Capricorn',
        'nakshatra': 'Shravana',
        'houseFromMoon': 8,
        'houseFromLagna': 3,
        'taraBala': {'name': 'Sampat', 'number': 2, 'favorable': true, 'meaning': 'Wealth star: gains come easily. $_long'},
        'chandraBala': false,
        'chandrashtama': true,
        'changesSignAt': '04:15 PM',
        'nextSign': 'Aquarius',
      },
      'dasha': _dasha(),
      'transits': [
        for (var i = 0; i < _planets.length; i++)
          _transit(_planets[i], i + 2, ['favorable', 'neutral', 'challenging'][i % 3], retro: i == 0),
      ],
      'aspects': [
        {'transitPlanet': 'Saturn', 'natalPlanet': 'Sun', 'aspect': 'square', 'orb': 1.2, 'effect': 'challenging', 'meaning': _long},
        {'transitPlanet': 'Jupiter', 'natalPlanet': 'Venus', 'aspect': 'trine', 'orb': 2.5, 'effect': 'favorable', 'meaning': _long},
      ],
      'events': [_event(date, 'ingress'), _event(date, 'festival')],
      'panchang': {
        'date': date,
        'vaar': 'Wednesday',
        'tithi': 'Shukla Paksha Purnima',
        'paksha': 'Shukla',
        'nakshatra': 'Uttara Bhadrapada',
        'yoga': 'Vyaghata',
        'karana': 'Vishti',
        'sunrise': '06:17 AM',
        'sunset': '05:58 PM',
        'moonrise': '05:40 PM',
        'moonset': '--',
        'rahuKaal': '12:07 PM - 01:35 PM',
        'yamaganda': '07:45 AM - 09:12 AM',
        'gulikaKaal': '10:40 AM - 12:07 PM',
        'abhijitMuhurat': '11:44 AM - 12:31 PM',
        'choghadiya': [
          {'name': 'Labh (Gain)', 'time': '06:17 AM - 07:45 AM', 'status': 'Auspicious'},
        ],
        'location': {'latitude': 28.6, 'longitude': 77.2, 'timezone': 'Asia/Kolkata'},
      },
      'goodFor': ['Paperwork', 'Learning something new', 'Quiet planning'],
      'avoid': ['Big purchases', 'Confrontations', 'Signing long contracts'],
      'bestTimes': [
        {'label': 'Abhijit Muhurat', 'start': '11:44 AM', 'end': '12:31 PM', 'reason': 'Universally auspicious midday window.'},
        {'label': 'Saturn hora', 'start': '02:10 PM', 'end': '03:05 PM', 'reason': 'Your dasha lord rules this hour.'},
      ],
      'remedy': _remedy(),
      'luckyColor': 'Navy blue',
      'luckyNumber': 8,
    };

Map<String, dynamic> weekPayload() {
  final start = DateTime(2026, 10, 5);
  return {
    'type': 'week',
    'weekStart': '2026-10-05',
    'weekEnd': '2026-10-11',
    ..._meta(),
    'summary': _summary(61, 'mixed'),
    'scores': _scores(),
    'days': [
      for (var i = 0; i < 7; i++)
        {
          'date': ymd(start.add(Duration(days: i))),
          'weekday': 'Day$i',
          'score': 35 + i * 9,
          'mood': ['challenging', 'mixed', 'good', 'excellent'][i % 4],
          'moonSign': 'Capricorn',
          'taraBala': 'Sampat',
          'taraFavorable': i.isEven,
          'chandrashtama': i == 2,
          'tithi': 'Shukla Dashami',
          'highlight': 'Good for steady work and family time. $_long',
        },
    ],
    'bestDays': {
      'career': ['2026-10-06', '2026-10-08'],
      'love': ['2026-10-09'],
      'money': [],
      'travel': ['2026-10-10'],
      'newBeginnings': ['2026-10-08', '2026-10-11'],
    },
    'cautionDays': [
      {'date': '2026-10-07', 'reason': 'Chandrashtama: the Moon transits your 8th. $_long'},
    ],
    'events': [_event('2026-10-06', 'retrograde'), _event('2026-10-10', 'festival')],
    'dasha': _dasha(),
    'focus': 'Finish what you started before taking on anything new. $_long',
    'remedy': _remedy(),
  };
}

Map<String, dynamic> monthPayload() => {
      'type': 'month',
      'month': '2026-10',
      'monthName': 'October 2026',
      ..._meta(known: true),
      'summary': _summary(72, 'good'),
      'scores': _scores(),
      'days': [
        for (var d = 1; d <= 31; d++)
          {
            'date': ymd(DateTime(2026, 10, d)),
            'score': (d * 17) % 100,
            'mood': 'mixed',
            'tithi': 'Tithi $d',
            'moonSign': 'Leo',
            'chandrashtama': d % 9 == 0,
            'festival': d % 10 == 0 ? 'Festival $d' : null,
            'highlight': 'Highlight $d',
          },
      ],
      'weeks': [
        {'weekStart': '2026-09-28', 'weekEnd': '2026-10-04', 'score': 55, 'headline': 'A slow start to the month. $_long'},
        {'weekStart': '2026-10-05', 'weekEnd': '2026-10-11', 'score': 70, 'headline': 'Momentum builds'},
      ],
      'keyTransits': [_transit('Saturn', 10, 'challenging'), _transit('Venus', 7, 'favorable')],
      'events': [_event('2026-10-06', 'ingress'), _event('2026-10-06', 'festival'), _event('2026-10-20', 'full_moon')],
      'bestDays': {'career': ['2026-10-06'], 'love': ['2026-10-14'], 'money': ['2026-10-21'], 'travel': [], 'newBeginnings': []},
      'cautionDays': [
        {'date': '2026-10-09', 'reason': 'Chandrashtama'},
      ],
      'dasha': _dasha(),
      'remedy': _remedy(),
    };

Map<String, dynamic> timelinePayload() => {
      'type': 'timeline',
      ..._meta(),
      'now': '2026-10-07',
      'periods': [
        {
          'id': 'md-saturn',
          'kind': 'mahadasha',
          'title': 'Saturn Mahadasha',
          'start': '2017-04-11',
          'end': '2036-04-11',
          'phase': null,
          'effect': 'neutral',
          'intensity': 3,
          'current': true,
          'summary': 'A long chapter of discipline. $_long',
          'realLife': ['Responsibilities grow', _long],
          'advice': ['Be patient', 'Serve elders'],
        },
        {
          'id': 'ss-rising',
          'kind': 'sade_sati',
          'title': 'Sade Sati — Rising phase',
          'start': '2023-01-17',
          'end': '2025-03-29',
          'phase': 'Rising',
          'effect': 'challenging',
          'intensity': 2,
          'current': false,
          'summary': 'Saturn in the 12th from your Moon.',
          'realLife': ['Expenses rise'],
          'advice': ['Save money'],
        },
        {
          'id': 'ju-7',
          'kind': 'jupiter_transit',
          'title': 'Jupiter through your 7th from Moon',
          'start': '2026-06-02',
          'end': '2027-06-20',
          'phase': null,
          'effect': 'favorable',
          'intensity': 2,
          'current': true,
          'summary': 'Partnerships bloom.',
          'realLife': ['Marriage talks'],
          'advice': ['Say yes to good offers'],
        },
        {
          'id': 'rk',
          'kind': 'rahu_ketu',
          'title': 'Rahu in your 4th, Ketu in your 10th',
          'start': '2027-11-01',
          'end': '2029-05-20',
          'phase': null,
          'effect': 'challenging',
          'intensity': 1,
          'current': false,
          'summary': 'Home vs career tug of war.',
          'realLife': [],
          'advice': [],
        },
      ],
    };

// ---------------------------------------------------------------------------
// Fake backend
// ---------------------------------------------------------------------------

class FakeBackend extends BackendService {
  Map<String, dynamic>? day = dayPayload();
  Map<String, dynamic>? week = weekPayload();
  Map<String, dynamic>? month = monthPayload();
  Map<String, dynamic>? timeline = timelinePayload();
  String? errorCode;
  String? errorMessage;
  Completer<Map<String, dynamic>?>? dayGate;
  Map<String, dynamic>? kundli = {
    'ascendant': 'Leo',
    'moonSign': 'Capricorn',
    'birthDetails': {'fullName': 'Ravindra Nath Jha', 'dateOfBirth': '1990-01-01', 'timeOfBirth': '10:00'},
  };

  final List<DateTime?> dayRequests = [];
  final List<DateTime?> weekRequests = [];
  int timelineCalls = 0;

  @override
  Map<String, dynamic>? get kundliData => kundli;
  @override
  bool get hasBirthDetails => kundli != null;
  @override
  String? get lastError => errorMessage;
  @override
  String? get lastErrorCode => errorCode;

  @override
  Future<Map<String, dynamic>?> fetchDayForecast({DateTime? date, int? familyId, bool forceRefresh = false}) {
    dayRequests.add(date);
    if (dayGate != null) return dayGate!.future;
    final d = day;
    return Future.value(d == null ? null : {...d, if (date != null) 'date': ymd(date)});
  }

  @override
  Future<Map<String, dynamic>?> fetchWeekForecast({DateTime? weekStart, int? familyId, bool forceRefresh = false}) {
    weekRequests.add(weekStart);
    return Future.value(week);
  }

  @override
  Future<Map<String, dynamic>?> fetchMonthForecast({DateTime? month, int? familyId, bool forceRefresh = false}) =>
      Future.value(this.month);

  @override
  Future<Map<String, dynamic>?> fetchLifeTimeline({int? familyId, DateTime? from, int? years, bool forceRefresh = false}) {
    timelineCalls++;
    return Future.value(timeline);
  }
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> pumpScreen(WidgetTester tester, Widget screen, FakeBackend fake,
    {Size size = const Size(320, 640), double textScale = 1.3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<BackendService>.value(
      value: fake,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        routes: {
          '/chatbot': (context) => Scaffold(
                body: Text('CHAT:${(ModalRoute.of(context)?.settings.arguments as Map?)?['initialMessage'] ?? ''}'),
              ),
          '/birth-details': (_) => const Scaffold(body: Text('BIRTH DETAILS')),
          '/forecast': (context) => ForecastScreen.fromArgs(ModalRoute.of(context)?.settings.arguments),
          '/life-timeline': (_) => const LifeTimelineScreen(),
          '/date-explorer': (_) => const DateExplorerScreen(),
        },
        home: screen,
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 40; i++) {
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -------------------------------------------------------------------------
  group('Forecast models', () {
    test('day payload parses fully', () {
      final d = DayForecast.fromJson(dayPayload());
      expect(d.date, DateTime(2026, 10, 7));
      expect(d.summary.overallScore, 68);
      expect(d.summary.mood, Mood.good);
      expect(d.scores['career'].reason, contains('Saturn'));
      expect(d.transits, hasLength(9));
      expect(d.transits.first.retrograde, isTrue);
      expect(d.transits.first.since, DateTime(2025, 3, 29));
      expect(d.moon.chandrashtama, isTrue);
      expect(d.moon.taraBala.number, 2);
      expect(d.dasha.chain, 'Saturn – Mercury – Venus');
      expect(d.panchang.abhijit, '11:44 AM - 12:31 PM');
      expect(d.panchang.gulika, '10:40 AM - 12:07 PM');
      expect(d.bestTimes.first.window, '11:44 AM – 12:31 PM');
      expect(d.luckyNumber, 8);
      expect(d.meta.isAi, isTrue);
      expect(d.meta.accuracyNote, isNotNull);
    });

    test('messy JSON: strings for numbers, nulls and missing fields', () {
      final d = DayForecast.fromJson({
        'date': '2026-10-07T00:00:00.000Z',
        'summary': {'overallScore': '82', 'mood': null},
        'scores': {
          'career': {'score': '71.6'},
          'love': 55,
          'money': null,
          'health': {'score': 'abc', 'label': ''},
        },
        'moon': {'taraBala': 'Vipat', 'chandrashtama': 'true', 'houseFromMoon': '8'},
        'dasha': null,
        'transits': [
          {'planet': 'Saturn', 'houseFromMoon': '14', 'degree': '12.5', 'retrograde': 1, 'effect': 'Favourable', 'since': 'garbage'},
          'junk',
          null,
        ],
        'aspects': 'not a list',
        'events': [
          {'importance': '9'},
        ],
        'panchang': {'tithi': {'name': 'Dashami'}},
        'goodFor': ['ok', null, '', 3],
        'luckyNumber': '7',
        'birthTimeKnown': 'false',
        'generatedBy': 'GPT',
      });
      expect(d.date, DateTime(2026, 10, 7));
      expect(d.summary.overallScore, 82);
      expect(d.summary.mood, Mood.excellent); // derived from score
      expect(d.scores['career'].score, 72);
      expect(d.scores['career'].label, 'Good');
      expect(d.scores['love'].score, 55);
      expect(d.scores['money'].score, 50);
      expect(d.scores['health'].label, 'Steady');
      expect(d.moon.taraBala.name, 'Vipat');
      expect(d.moon.chandrashtama, isTrue);
      expect(d.moon.houseFromMoon, 8);
      expect(d.dasha.isEmpty, isTrue);
      expect(d.transits, hasLength(1));
      expect(d.transits.first.houseFromMoon, 0); // out of range → unknown
      expect(d.transits.first.degree, 12.5);
      expect(d.transits.first.retrograde, isTrue);
      expect(d.transits.first.effect, Effect.favorable);
      expect(d.transits.first.since, isNull);
      expect(d.transits.first.title, 'Saturn');
      expect(d.aspects, isEmpty);
      expect(d.events.single.importance, 3);
      expect(d.panchang.tithi, 'Dashami');
      expect(d.goodFor, ['ok', '3']);
      expect(d.luckyNumber, 7);
      expect(d.meta.birthTimeKnown, isFalse);
      expect(d.meta.generatedBy, 'rules');
      expect(d.remedy.isEmpty, isTrue);
    });

    test('completely empty / wrong-typed payloads never throw', () {
      expect(() => DayForecast.fromJson(null), returnsNormally);
      expect(() => WeekForecast.fromJson('nope'), returnsNormally);
      expect(() => MonthForecast.fromJson(42), returnsNormally);
      expect(() => LifeTimeline.fromJson([]), returnsNormally);
      final w = WeekForecast.fromJson({}, fallbackStart: DateTime(2026, 10, 8));
      expect(w.weekStart, DateTime(2026, 10, 5));
      expect(w.weekEnd, DateTime(2026, 10, 11));
      final m = MonthForecast.fromJson({'month': '2026-2'});
      expect(m.month, DateTime(2026, 2, 1));
    });

    test('week / month / timeline parse and sort', () {
      final w = WeekForecast.fromJson(weekPayload());
      expect(w.days, hasLength(7));
      expect(w.days[2].chandrashtama, isTrue);
      expect(w.bestDays.byArea['career'], [DateTime(2026, 10, 6), DateTime(2026, 10, 8)]);
      expect(w.bestDays.byArea['money'], isEmpty);
      expect(w.cautionDays.single.date, DateTime(2026, 10, 7));

      final m = MonthForecast.fromJson(monthPayload());
      expect(m.days, hasLength(31));
      expect(m.dayFor(DateTime(2026, 10, 10))?.festival, 'Festival 10');
      expect(m.keyTransits, hasLength(2));

      final t = LifeTimeline.fromJson(timelinePayload());
      expect(t.periods.first.id, 'md-saturn'); // sorted by start
      expect(t.periods[1].phase, 'Rising');
      expect(t.now, DateTime(2026, 10, 7));
      expect(t.periods.first.contains(DateTime(2026, 10, 7)), isTrue);
    });

    test('date helpers', () {
      expect(mondayOf(DateTime(2026, 10, 11)), DateTime(2026, 10, 5));
      expect(mondayOf(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
      expect(ymd(DateTime(2026, 1, 3)), '2026-01-03');
      expect(ym(DateTime(2026, 1, 3)), '2026-01');
    });

    test('route args parsing', () {
      final s = ForecastScreen.fromArgs(const {'tab': 'month', 'date': '2026-10-20', 'familyId': '7'});
      expect(s.initialTab, 2);
      expect(s.initialDate, DateTime(2026, 10, 20));
      expect(s.familyId, 7);
      expect(ForecastScreen.fromArgs(null).initialTab, 0);
      expect(ForecastScreen.fromArgs(const {'tab': 1}).initialTab, 1);
      expect(ForecastScreen.fromArgs(const {'tab': 'bogus'}).initialTab, 0);
    });

    test('life-area keyword detection', () {
      expect(detectLifeAreas('Got a new job and a promotion!'), {LifeArea.career});
      expect(detectLifeAreas('Painful breakup with my partner'), containsAll([LifeArea.love]));
      expect(detectLifeAreas('lost money in stocks'), {LifeArea.money});
      expect(detectLifeAreas('I fell ill'), {LifeArea.health});
      expect(detectLifeAreas('so much stress and anxiety'), {LifeArea.mind});
      expect(detectLifeAreas('I will still go'), isEmpty); // "ill" must not match "will"/"still"
      expect(detectLifeAreas(''), isEmpty);
    });

    test('planet relevance', () {
      const score = AreaScore(score: 40, reason: 'Saturn in your 10th weighs on career');
      expect(planetRelevance('Saturn', 10, Effect.challenging, LifeArea.career, score), hasLength(3));
      expect(planetRelevance('Venus', 3, Effect.neutral, LifeArea.career, score), isEmpty);
      expect(dashaRelevant('Venus', LifeArea.love), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('ForecastScreen at 320x640, 1.3x text', () {
    testWidgets('Day view renders every section without overflow', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, const ForecastScreen(), fake);

      expect(find.textContaining('A steady, productive day'), findsOneWidget);
      expect(find.textContaining('Your birth time is unknown'), findsOneWidget);
      expect(find.textContaining('Chandrashtama: the Moon'), findsOneWidget);
      expect(find.text('Saturn in your 2th from Moon'), findsOneWidget);
      expect(find.text('Open full Panchang & Muhurat'), findsOneWidget);
      expect(fake.dayRequests, isNotEmpty);

      // Expand a life-area reason and a transit card.
      await tester.ensureVisible(find.text('Career').first);
      await tester.tap(find.text('Career').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('drives career matters'), findsOneWidget);

      await tester.ensureVisible(find.text('Saturn in your 2th from Moon'));
      await tester.tap(find.text('Saturn in your 2th from Moon'));
      await tester.pumpAndSettle();
      expect(find.text('In real life you may notice…'), findsOneWidget);
      expect(find.text('Ask an astrologer about this'), findsOneWidget);

      await scrollThrough(tester);
      expect(tester.takeException(), isNull);

      // Ask-astrologer passes the transit facts to the chatbot.
      await tester.ensureVisible(find.text('Ask an astrologer about this'));
      await tester.tap(find.text('Ask an astrologer about this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CHAT:Saturn is transiting Sagittarius'), findsOneWidget);
    });

    testWidgets('Week view renders and a day tap opens the Day tab', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, const ForecastScreen(initialTab: 1), fake);

      expect(find.textContaining('WEEK OF'), findsOneWidget);
      expect(find.text('Your focus this week'), findsOneWidget);
      expect(find.text('GO GENTLY ON'), findsOneWidget);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000));
      await tester.pumpAndSettle();
      final strip = find.byType(ScoreStrip);
      await tester.ensureVisible(strip);
      await tester.tap(find.descendant(of: strip, matching: find.byType(InkWell)).at(3));
      await tester.pumpAndSettle();
      expect(fake.dayRequests.last, DateTime(2026, 10, 8));
      expect(find.byType(DayView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Month view renders heatmap, weeks, transits and events', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, ForecastScreen(initialTab: 2, initialDate: DateTime(2026, 10, 1)), fake);

      expect(find.byType(MonthHeatmap), findsOneWidget);
      expect(find.text('WEEK BY WEEK'), findsOneWidget);
      expect(find.text('BIG PLANETARY MOVES'), findsOneWidget);
      expect(find.text('FESTIVALS & SKY EVENTS'), findsOneWidget);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);

      // Tap a heatmap cell (the 15th) → Day tab for that date.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(MonthHeatmap));
      await tester.tap(find.descendant(of: find.byType(MonthHeatmap), matching: find.text('15')));
      await tester.pumpAndSettle();
      expect(fake.dayRequests.last, DateTime(2026, 10, 15));
    });

    testWidgets('NO_KUNDLI shows the create-Kundli state', (tester) async {
      final fake = FakeBackend()
        ..day = null
        ..errorCode = 'NO_KUNDLI'
        ..errorMessage = 'No Kundli found';
      await pumpScreen(tester, const ForecastScreen(), fake);
      expect(find.text('Create your Vedic Kundli'), findsOneWidget);
      await tester.ensureVisible(find.text('Add birth details'));
      await tester.tap(find.text('Add birth details'));
      await tester.pumpAndSettle();
      expect(find.text('BIRTH DETAILS'), findsOneWidget);
    });

    testWidgets('errors show Retry, which reloads', (tester) async {
      final fake = FakeBackend()
        ..day = null
        ..errorMessage = 'The server is taking too long to respond.';
      await pumpScreen(tester, const ForecastScreen(), fake);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);

      fake
        ..day = dayPayload()
        ..errorMessage = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A steady, productive day'), findsOneWidget);
    });

    testWidgets('shows a skeleton while loading', (tester) async {
      final fake = FakeBackend()..dayGate = Completer();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<BackendService>.value(
        value: fake,
        child: const MaterialApp(home: ForecastScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Loading your forecast'), findsOneWidget);
      fake.dayGate!.complete(dayPayload());
      await tester.pumpAndSettle();
      expect(find.byType(DayView), findsOneWidget);
    });

    testWidgets('period navigation requests the next day', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, ForecastScreen(initialDate: DateTime(2026, 3, 10)), fake);
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(fake.dayRequests.last, DateTime(2026, 3, 11));
      expect(find.text('Today'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('LifeTimelineScreen', () {
    testWidgets('renders periods, "You are here", filters and detail sheet', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, const LifeTimelineScreen(), fake);

      expect(find.textContaining('You are here'), findsOneWidget);
      expect(find.text('Saturn Mahadasha'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Jupiter'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Jupiter'));
      await tester.pumpAndSettle();
      expect(find.text('Rahu in your 4th, Ketu in your 10th'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'All'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Sade Sati — Rising phase'));
      await tester.tap(find.text('Sade Sati — Rising phase'));
      await tester.pumpAndSettle();
      expect(find.text('What helps'), findsOneWidget);
      expect(find.text('Save money'), findsOneWidget);
      await tester.ensureVisible(find.text('Ask an astrologer about this'));
      await tester.tap(find.text('Ask an astrologer about this'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CHAT:My chart shows Sade Sati'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('DateExplorerScreen', () {
    testWidgets('explains a date and highlights the related life area', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, const DateExplorerScreen(), fake);

      await tester.enterText(find.byType(TextField), 'got a new job');
      await tester.ensureVisible(find.text('Explain this date'));
      await tester.tap(find.text('Explain this date'));
      await tester.pumpAndSettle();

      expect(find.text('Why your career was affected'), findsOneWidget);
      expect(find.textContaining('Likely related'), findsWidgets);
      expect(find.text('SLOW PLANETS SHAPING THAT TIME'), findsOneWidget);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Ask the AI astrologer why'));
      await tester.tap(find.text('Ask the AI astrologer why'));
      await tester.pumpAndSettle();
      expect(find.textContaining('this happened: "got a new job"'), findsOneWidget);
    });

    testWidgets('route args auto-run the explorer', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, DateExplorerScreen.fromArgs(const {'date': '2020-03-22', 'note': 'stress'}), fake);
      expect(fake.dayRequests.single, DateTime(2020, 3, 22));
      expect(find.text('Why your mind was affected'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('Home YourDayCard', () {
    Widget host() => const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: YourDayCard()));

    testWidgets('shows score, areas and quick buttons; opens Week', (tester) async {
      final fake = FakeBackend();
      await pumpScreen(tester, host(), fake);
      expect(find.textContaining('YOUR DAY'), findsOneWidget);
      expect(find.text('Life Timeline'), findsOneWidget);
      expect(find.text('Why did this happen?'), findsOneWidget);
      expect(find.textContaining('Chandrashtama today'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.byType(WeekView), findsOneWidget);
    });

    testWidgets('without a Kundli shows the create CTA and makes no request', (tester) async {
      final fake = FakeBackend()..kundli = null;
      await pumpScreen(tester, host(), fake);
      expect(find.text('Create my Kundli'), findsOneWidget);
      expect(fake.dayRequests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure shows a compact retry', (tester) async {
      final fake = FakeBackend()
        ..day = null
        ..errorMessage = 'Offline';
      await pumpScreen(tester, host(), fake);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
