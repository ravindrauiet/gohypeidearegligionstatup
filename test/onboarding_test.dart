import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cosmicguide/screens/onboarding_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/utils/app_routes.dart';
import 'package:cosmicguide/widgets/onboarding_art.dart';
import 'package:cosmicguide/widgets/onboarding_chrome.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _titles = [
  'Your true Vedic Kundli',
  'Your day, in simple words',
  'Know why things happen',
  'Play with your planets',
  'Match with the people you love',
  'Ask anytime, get real answers',
];

const _buttons = ['Begin', 'Sounds good', 'Show me', "Let's play", 'Nice', 'Get started'];

/// Pumps the onboarding screen as the first route, with stub destinations.
Future<void> pumpOnboarding(
  WidgetTester tester, {
  Size size = const Size(360, 740),
  double textScale = 1.0,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<BackendService>(
      create: (_) => BackendService(),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        routes: {
          '/': (_) => const OnboardingScreen(),
          AppRoutes.login: (_) => const Scaffold(body: Text('LOGIN STUB')),
          AppRoutes.topicSelection: (_) => const Scaffold(body: Text('TOPICS STUB')),
          AppRoutes.home: (_) => const Scaffold(body: Text('HOME STUB')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Walks all six slides with the bottom button, failing on any exception
/// (layout overflows surface as exceptions in widget tests).
Future<void> walkAllSlides(WidgetTester tester) async {
  for (var i = 0; i < _titles.length; i++) {
    expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
    expect(find.text(_titles[i]), findsOneWidget, reason: 'slide ${i + 1} title');
    expect(find.text('${i + 1}/6'), findsOneWidget);
    expect(find.bySemanticsLabel(OnboardingArt.labels[i]), findsOneWidget,
        reason: 'slide ${i + 1} illustration label');
    expect(find.widgetWithText(OnboardingPrimaryButton, _buttons[i]), findsOneWidget);
    if (i < _titles.length - 1) {
      await tester.tap(find.widgetWithText(OnboardingPrimaryButton, _buttons[i]));
      // Mid-animation frames must lay out cleanly too.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'leaving slide ${i + 1}');
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull, reason: 'animating slide ${i + 2}');
      await tester.pumpAndSettle();
    }
  }
  expect(tester.takeException(), isNull);
}

void main() {
  group('Onboarding layout', () {
    for (final size in const [Size(320, 568), Size(360, 740), Size(800, 1280), Size(740, 360)]) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('all six slides fit ${size.width.toInt()}x${size.height.toInt()} at text scale $scale',
            (tester) async {
          await pumpOnboarding(tester, size: size, textScale: scale);
          await walkAllSlides(tester);
        });
      }
    }

    testWidgets('reduced motion shows every finished picture with no running animation', (tester) async {
      await pumpOnboarding(tester, size: const Size(320, 568), textScale: 1.3, disableAnimations: true);
      expect(tester.binding.hasScheduledFrame, isFalse);
      for (var i = 0; i < _titles.length; i++) {
        expect(find.text(_titles[i]), findsOneWidget);
        expect(find.bySemanticsLabel(OnboardingArt.labels[i]), findsOneWidget);
        if (i < _titles.length - 1) {
          await tester.tap(find.widgetWithText(OnboardingPrimaryButton, _buttons[i]));
          // The slide changes at once and the art is already in its final state.
          await tester.pump();
          expect(find.text(_titles[i + 1]), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
        }
      }
      // Final state of the last picture is on screen.
      expect(find.text('Pandit online'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Onboarding content', () {
    testWidgets('first slide names the app and shows the Kundli preview', (tester) async {
      await pumpOnboarding(tester);
      expect(find.text('Welcome to CosmicGuide'), findsOneWidget);
      expect(find.text('VEDIC KUNDLI'), findsOneWidget);
      expect(find.text('Lagna · Scorpio'), findsOneWidget);
      expect(find.text('Moon · Anuradha'), findsOneWidget);
      expect(find.text('Lahiri · Swiss Ephemeris'), findsOneWidget);
      // No leftovers from the old, copied onboarding.
      expect(find.textContaining('Astro-Map'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('illustrations preview the real features', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      expect(find.text('74'), findsOneWidget);
      expect(find.text('A good day for'), findsOneWidget);
      expect(find.text('Be careful with'), findsOneWidget);
      expect(find.text('Best time'), findsOneWidget);

      await tester.tap(find.text('Sounds good'));
      await tester.pumpAndSettle();
      expect(find.text('Your planet weather'), findsOneWidget);
      expect(find.text('Sun supports your career'), findsOneWidget);

      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
      expect(find.text('+30 XP'), findsOneWidget);
      expect(find.text('Chitra'), findsOneWidget);

      await tester.tap(find.text("Let's play"));
      await tester.pumpAndSettle();
      expect(find.text('31'), findsOneWidget);
      expect(find.text('Luckiest today'), findsOneWidget);

      await tester.tap(find.text('Nice'));
      await tester.pumpAndSettle();
      expect(find.text('How will my week go?'), findsOneWidget);
      expect(find.text('Pandit online'), findsOneWidget);
    });

    testWidgets('each illustration is one labelled image for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOnboarding(tester);
      expect(find.bySemanticsLabel(OnboardingArt.labels[0]), findsOneWidget);
      // Decorative internals are hidden from assistive technology.
      expect(find.bySemanticsLabel('Lagna · Scorpio'), findsNothing);
      expect(find.bySemanticsLabel('Step 1 of 6'), findsOneWidget);
      expect(find.bySemanticsLabel('Skip'), findsOneWidget);
      expect(find.bySemanticsLabel('Begin'), findsOneWidget);
      expect(OnboardingArt.labels.length, 6);
      expect(OnboardingArt.labels.toSet().length, 6);
      handle.dispose();
    });

    testWidgets('revisiting a slide replays its animation', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      expect(find.text('74'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // The score ring is counting up again rather than sitting at 74.
      expect(find.text('74'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('74'), findsOneWidget);
    });
  });

  group('Onboarding motion', () {
    testWidgets('idle motion is bounded and ends on the same finished picture', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(find.text('Begin'));
      // Past the entrance, in the middle of the gentle idle motion.
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(find.text('74'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // It comes to rest by itself (nothing keeps animating forever).
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('74'), findsOneWidget);
    });

    testWidgets('progress bar and wordmark follow the slides', (tester) async {
      await pumpOnboarding(tester);
      expect(find.byType(OnboardingProgress), findsOneWidget);
      expect(tester.widget<OnboardingProgress>(find.byType(OnboardingProgress)).page, 0);
      expect(find.text('Welcome to CosmicGuide'), findsOneWidget);

      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      expect(tester.widget<OnboardingProgress>(find.byType(OnboardingProgress)).page, 1);
      // The greeting is only for the first slide; the brand stays.
      expect(find.text('Welcome to CosmicGuide'), findsNothing);
      expect(find.text('CosmicGuide'), findsOneWidget);
    });

    testWidgets('small screens with large text can scroll the copy', (tester) async {
      await pumpOnboarding(tester, size: const Size(320, 568), textScale: 1.3);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      await tester.drag(find.text(_titles[0]), const Offset(0, -400));
      await tester.pumpAndSettle();
      // At the end of the text the "more below" hint goes away.
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Onboarding navigation', () {
    testWidgets('Skip goes to login and marks onboarding seen', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN STUB'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_seen'), isTrue);
    });

    testWidgets('system back on slide 2 returns to slide 1', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      expect(find.text('2/6'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('1/6'), findsOneWidget);
      expect(find.text(_titles[0]), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('swiping moves between slides', (tester) async {
      await pumpOnboarding(tester);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2/6'), findsOneWidget);
      expect(find.text('Sounds good'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('last button leaves onboarding and marks it seen', (tester) async {
      await pumpOnboarding(tester);
      for (var i = 0; i < _buttons.length - 1; i++) {
        await tester.tap(find.widgetWithText(OnboardingPrimaryButton, _buttons[i]));
        await tester.pumpAndSettle();
      }
      expect(find.text('6/6'), findsOneWidget);

      // A double tap must not navigate twice.
      await tester.tap(find.text('Get started'));
      await tester.tap(find.text('Get started'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('LOGIN STUB'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_seen'), isTrue);
    });
  });
}
