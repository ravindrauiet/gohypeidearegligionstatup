import 'package:cosmicguide/screens/tabs/love_tab.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'forecast_test.dart' show FakeBackend;

void main() {
  testWidgets('partner details asks one question at a time', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<BackendService>.value(
      value: FakeBackend(),
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const Scaffold(body: PartnerBirthDetailsSheet()),
      ),
    ));
    await tester.pumpAndSettle();

    // Step 1: name.
    expect(find.text("What's your partner's name?"), findsOneWidget);
    expect(find.text('Partner details · Step 1 of 5'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("Please enter partner's full name"), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Asha Verma');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: gender, tapping moves on.
    expect(find.text('Asha is…'), findsOneWidget);
    await tester.tap(find.text('Male'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Step 3: date.
    expect(find.text('When was Asha born?'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("Please select partner's date of birth"), findsOneWidget);
    await tester.tap(find.text('Tap to choose a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text("Please select partner's date of birth"), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 4: time.
    expect(find.text('What time was Asha born?'), findsOneWidget);
    await tester.ensureVisible(find.text("I don't know the exact time"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I don't know the exact time"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 5: place.
    expect(find.text('Where was Asha born?'), findsOneWidget);
    expect(find.text('Save & check match'), findsOneWidget);

    // Back returns to the time step with the answer kept.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What time was Asha born?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
