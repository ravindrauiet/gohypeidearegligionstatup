import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:cosmicguide/widgets/hindu_calendar_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'forecast_test.dart' show FakeBackend;

String _d(int days) {
  final d = DateTime.now().add(Duration(days: days));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('Home Hindu Panchang shows today and upcoming festivals only', (tester) async {
    tester.view.physicalSize = const Size(360 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final fake = FakeBackend()
      ..month = {
        'events': [
          {'date': _d(-2), 'type': 'festival', 'title': 'Past festival', 'importance': 2},
          {'date': _d(0), 'type': 'festival', 'title': 'Sharad Navratri begins',
           'description': 'Nine nights of the Divine Mother (Durga), a powerful time for spiritual practice.',
           'personalImpact': 'The day’s blessings flow into career and status for you.', 'importance': 2},
          {'date': _d(0), 'type': 'retrograde', 'title': 'Venus turns retrograde', 'importance': 2},
          {'date': _d(1), 'type': 'ekadashi', 'title': 'Papankusha Ekadashi', 'importance': 1},
          {'date': _d(5), 'type': 'full_moon', 'time': '09:20 PM', 'title': 'Sharad Purnima', 'importance': 1},
          {'date': _d(14), 'type': 'festival', 'title': 'Dhanteras', 'importance': 2},
          {'date': _d(16), 'type': 'festival', 'title': 'Diwali (Lakshmi Puja)', 'importance': 3},
          {'date': _d(16), 'type': 'new_moon', 'title': 'Amavasya (New Moon) in Libra', 'importance': 1},
        ],
      };
    await tester.pumpWidget(ChangeNotifierProvider<BackendService>.value(
      value: fake,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(body: SingleChildScrollView(child: HinduCalendarSection())),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Past festival'), findsNothing);
    expect(find.text('Venus turns retrograde'), findsNothing);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Sharad Navratri begins'), findsOneWidget);
    expect(find.text('Papankusha Ekadashi'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);

    // The detail sheet.
    await tester.tap(find.text('Sharad Navratri begins'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Ask AI about this day'), findsOneWidget);
    expect(find.text('For you'), findsOneWidget);
    expect(find.text('See Panchang for this day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
