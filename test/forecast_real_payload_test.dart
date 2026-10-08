// Renders the forecast screens from REAL backend responses captured in
// test/fixtures/forecast (regenerate them from the backend when the API changes).
// This guards the app <-> backend contract, which forecast_test.dart only covers
// with hand-written payloads.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pujakaro/models/forecast.dart';
import 'package:pujakaro/screens/date_explorer_screen.dart';
import 'package:pujakaro/screens/forecast_screen.dart';
import 'package:pujakaro/screens/life_timeline_screen.dart';
import 'package:pujakaro/widgets/today_simple_card.dart';
import 'package:pujakaro/widgets/your_day_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'forecast_test.dart' show FakeBackend, pumpScreen, scrollThrough;

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/forecast/$name.json').readAsStringSync()) as Map<String, dynamic>;

FakeBackend realBackend({String day = 'day', String month = 'month'}) => FakeBackend()
  ..day = fixture(day)
  ..week = fixture('week')
  ..month = fixture(month)
  ..timeline = fixture('timeline');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Real backend payloads parse', () {
    test('day', () {
      final d = DayForecast.fromJson(fixture('day'));
      expect(d.summary.headline, isNotEmpty);
      expect(d.transits, hasLength(9));
      for (final area in ['career', 'love', 'money', 'health', 'mind']) {
        expect(d.scores[area].reason, isNotEmpty, reason: area);
      }
    });

    test('week, month, timeline and family day', () {
      expect(WeekForecast.fromJson(fixture('week')).days, hasLength(7));
      expect(MonthForecast.fromJson(fixture('month')).days, hasLength(31));
      expect(LifeTimeline.fromJson(fixture('timeline')).periods, isNotEmpty);
      final fam = DayForecast.fromJson(fixture('family_day'));
      expect(fam.meta.birthTimeKnown, isFalse);
      expect(fam.meta.accuracyNote, isNotNull);
    });
  });

  group('Screens render real payloads at 320x640, 1.3x text', () {
    for (final tab in [0, 1, 2]) {
      testWidgets('ForecastScreen tab $tab', (tester) async {
        await pumpScreen(tester, ForecastScreen(initialTab: tab, initialDate: DateTime(2026, 10, 7)), realBackend());
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ForecastScreen for a family member with unknown birth time', (tester) async {
      await pumpScreen(tester, ForecastScreen(initialDate: DateTime(2026, 10, 7)),
          realBackend(day: 'family_day', month: 'family_month'));
      expect(find.textContaining('Birth time is unknown'), findsWidgets);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LifeTimelineScreen', (tester) async {
      await pumpScreen(tester, const LifeTimelineScreen(), realBackend());
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DateExplorerScreen', (tester) async {
      await pumpScreen(
          tester, DateExplorerScreen.fromArgs(const {'date': '2026-10-07', 'note': 'got a promotion'}), realBackend());
      expect(find.text('Why your career was affected'), findsOneWidget);
      await scrollThrough(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home TodaySimpleCard shows plain guidance and planet weather', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: TodaySimpleCard())),
        realBackend(),
      );
      expect(find.textContaining('Today for you'), findsOneWidget);
      expect(find.text('A good day for'), findsOneWidget);
      expect(find.text('Your best time today'), findsOneWidget);
      expect(find.text('Your planet weather'), findsOneWidget);
      // Plain sentences from the backend, no jargon such as "4th from Moon".
      expect(find.textContaining('Saturn is testing your patience'), findsOneWidget);
      expect(find.textContaining('from Moon'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.textContaining('Saturn is testing your patience'));
      await tester.tap(find.textContaining('Saturn is testing your patience'));
      await tester.pumpAndSettle();
      expect(find.text('You may notice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home YourDayCard', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: YourDayCard())),
        realBackend(),
      );
      expect(find.textContaining('YOUR DAY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
