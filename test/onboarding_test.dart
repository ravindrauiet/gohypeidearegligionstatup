import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cosmicguide/screens/onboarding_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/utils/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _slides = OnboardingScreen.slides;

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

Finder get _nextButton => find.byKey(const ValueKey('onboarding-next'));

/// Walks every slide with the bottom button, failing on any exception
/// (layout overflows surface as exceptions in widget tests).
Future<void> walkAllSlides(WidgetTester tester) async {
  for (var i = 0; i < _slides.length; i++) {
    expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
    expect(find.text(_slides[i].title), findsOneWidget, reason: 'slide ${i + 1} title');
    expect(find.text(_slides[i].subtitle), findsOneWidget, reason: 'slide ${i + 1} subtitle');
    final last = i == _slides.length - 1;
    expect(find.descendant(of: _nextButton, matching: find.text(last ? 'Get started' : 'Next')), findsOneWidget);
    if (!last) {
      await tester.tap(_nextButton);
      // Mid-animation frames must lay out cleanly too.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull, reason: 'leaving slide ${i + 1}');
      await tester.pumpAndSettle();
    }
  }
  expect(tester.takeException(), isNull);
}

void main() {
  test('onboarding is short, with short headlines and real photos', () {
    expect(_slides.length, inInclusiveRange(3, 4));
    for (final s in _slides) {
      expect(s.title.split(' ').length, lessThanOrEqualTo(6), reason: s.title);
      expect(s.image, startsWith('assets/images/'));
      expect(s.imageLabel, isNotEmpty);
    }
    expect(_slides.map((s) => s.image).toSet().length, _slides.length);
  });

  group('Onboarding layout', () {
    for (final size in const [Size(320, 568), Size(360, 740), Size(800, 1280), Size(740, 360)]) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('every slide fits ${size.width.toInt()}x${size.height.toInt()} at text scale $scale',
            (tester) async {
          await pumpOnboarding(tester, size: size, textScale: scale);
          await walkAllSlides(tester);
        });
      }
    }

    testWidgets('reduced motion changes slides at once and leaves nothing animating', (tester) async {
      await pumpOnboarding(tester, size: const Size(320, 568), textScale: 1.3, disableAnimations: true);
      expect(tester.binding.hasScheduledFrame, isFalse);
      for (var i = 0; i < _slides.length - 1; i++) {
        await tester.tap(_nextButton);
        await tester.pump();
        expect(find.text(_slides[i + 1].title), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
    });
  });

  group('Onboarding content', () {
    testWidgets('first slide welcomes the user and shows a full-bleed photo', (tester) async {
      await pumpOnboarding(tester);
      expect(find.text(OnboardingScreen.welcome), findsOneWidget);
      expect(find.text(OnboardingScreen.brand), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      final photo = tester.widget<Image>(
        find.byWidgetPredicate((w) =>
            w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.startsWith('assets/images/')),
      );
      expect((photo.image as AssetImage).assetName, _slides[0].image);
      // The photo fills the whole screen.
      final rect = tester.getRect(find.byWidget(photo));
      expect(rect.size, const Size(360, 740));
    });

    testWidgets('the welcome line is only on the first slide', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(_nextButton);
      await tester.pumpAndSettle();
      expect(find.text(OnboardingScreen.welcome), findsNothing);
      expect(find.text(OnboardingScreen.brand), findsOneWidget);
    });

    testWidgets('photos and progress are labelled for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOnboarding(tester);
      expect(find.bySemanticsLabel(_slides[0].imageLabel), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of ${_slides.length}'), findsOneWidget);
      expect(find.bySemanticsLabel('Skip'), findsOneWidget);
      expect(find.bySemanticsLabel('Next'), findsOneWidget);

      await tester.tap(_nextButton);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(_slides[1].imageLabel), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2 of ${_slides.length}'), findsOneWidget);
      handle.dispose();
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
      await tester.tap(_nextButton);
      await tester.pumpAndSettle();
      expect(find.text(_slides[1].title), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_slides[0].title), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('swiping moves between slides', (tester) async {
      await pumpOnboarding(tester);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text(_slides[1].title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('last button leaves onboarding and marks it seen', (tester) async {
      await pumpOnboarding(tester);
      for (var i = 0; i < _slides.length - 1; i++) {
        await tester.tap(_nextButton);
        await tester.pumpAndSettle();
      }
      expect(find.text('Get started'), findsOneWidget);

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
