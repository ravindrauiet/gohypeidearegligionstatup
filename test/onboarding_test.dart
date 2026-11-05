import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cosmicguide/screens/onboarding_screen.dart';
import 'package:cosmicguide/widgets/onboarding/onboarding_page.dart' show OnboardingPhotoVisual;
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/utils/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _slides = OnboardingScreen.slides;

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

/// Pumps the onboarding screen as the first route, with stub destinations.
Future<void> pumpOnboarding(
  WidgetTester tester, {
  Size size = const Size(360, 740),
  double textScale = 1.0,
  bool disableAnimations = false,
  String? fontFamily,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<BackendService>(
      create: (_) => BackendService(),
      child: MaterialApp(
        theme: fontFamily == null ? null : ThemeData(fontFamily: fontFamily),
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
Future<void> walkAllSlides(WidgetTester tester, {bool copyMustFit = false}) async {
  final screen = tester.getRect(find.byType(OnboardingScreen));
  for (var i = 0; i < _slides.length; i++) {
    expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
    expect(find.text(_slides[i].title), findsOneWidget, reason: 'slide ${i + 1} title');
    expect(find.text(_slides[i].subtitle), findsOneWidget, reason: 'slide ${i + 1} subtitle');
    // The headline starts on screen (on very short screens the slide scrolls).
    final title = tester.getRect(find.text(_slides[i].title));
    expect(title.left, greaterThanOrEqualTo(screen.left), reason: 'slide ${i + 1} title x');
    expect(title.right, lessThanOrEqualTo(screen.right), reason: 'slide ${i + 1} title x');
    if (copyMustFit) {
      // The whole body sits above the dots without scrolling.
      final body = tester.getRect(find.text(_slides[i].subtitle));
      final dots = tester.getRect(find.byKey(const ValueKey('onboarding-dot-0')));
      expect(body.bottom, lessThanOrEqualTo(dots.top), reason: 'slide ${i + 1} body hidden behind controls');
    }
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
  group('Onboarding story', () {
    test('six slides with short headlines and short body copy', () {
      expect(_slides.length, 6);
      for (final s in _slides) {
        expect(_words(s.title), lessThanOrEqualTo(12), reason: s.title);
        expect(_words(s.subtitle), lessThanOrEqualTo(22), reason: s.subtitle);
        expect(s.eyebrow, isNotEmpty);
        expect(s.imageLabel, isNotEmpty);
        expect(s.background, hasLength(greaterThanOrEqualTo(2)));
      }
      // One illustration per slide, in the story order.
      expect(_slides.map((s) => s.visual).toList(), OnboardingVisual.values);
    });

    test('it tells the spiritual-social story, ending on Kundli', () {
      expect(_slides[0].title, contains('buddy'));
      expect(_slides[0].subtitle, contains('50 mindset questions'));
      expect(_slides[1].subtitle, contains('18+'));
      expect(_slides[1].subtitle, contains('birth details'));
      expect(_slides[2].subtitle, allOf(contains('+10'), contains('+1'), contains('+50')));
      expect(_slides[3].title, contains('10,000 coins'));
      expect(_slides[4].subtitle, allOf(contains('bhajans'), contains('katha')));
      expect(_slides[5].title, contains('Kundli'));
      expect(_slides[5].subtitle, contains('pandit'));
    });

    test('every photo it uses ships with the app', () {
      for (final image in OnboardingScreen.images) {
        expect(File(image).existsSync(), isTrue, reason: image);
      }
    });
  });

  group('Onboarding layout', () {
    const sizes = [
      Size(320, 568),
      Size(320, 480),
      Size(360, 740),
      Size(412, 915),
      Size(800, 1280),
      Size(740, 360),
    ];
    for (final size in sizes) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('every slide fits ${size.width.toInt()}x${size.height.toInt()} at text scale $scale',
            (tester) async {
          await pumpOnboarding(tester, size: size, textScale: scale);
          await walkAllSlides(tester);
        });
      }
    }

    testWidgets('the illustration gets real space on a normal phone', (tester) async {
      await pumpOnboarding(tester, size: const Size(412, 915));
      for (var i = 0; i < _slides.length; i++) {
        final visual = tester.getRect(find.bySemanticsLabel(_slides[i].imageLabel));
        expect(visual.height, greaterThan(250), reason: 'slide ${i + 1}');
        if (i < _slides.length - 1) {
          await tester.tap(_nextButton);
          await tester.pumpAndSettle();
        }
      }
    });

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

    testWidgets('every slide shows its photo and nothing keeps animating', (tester) async {
      await pumpOnboarding(tester);
      for (var i = 0; i < _slides.length; i++) {
        expect(find.image(AssetImage(OnboardingPhotoVisual.photoFor(_slides[i].visual).$1)), findsWidgets);
        if (i < _slides.length - 1) {
          await tester.tap(_nextButton);
          await tester.pumpAndSettle();
        }
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('Onboarding copy with real font metrics', () {
    // The test font draws every glyph a full em wide, so line breaks only
    // match a phone with a real font loaded (Roboto ships with the SDK).
    const family = 'OnboardingRoboto';
    final root = Platform.environment['FLUTTER_ROOT'];
    final dir = root == null ? null : Directory('$root/bin/cache/artifacts/material_fonts');
    final available = dir != null && File('${dir.path}/roboto-regular.ttf').existsSync();

    setUpAll(() async {
      if (!available) return;
      final loader = FontLoader(family);
      for (final w in ['regular', 'medium', 'bold', 'black']) {
        final bytes = File('${dir.path}/roboto-$w.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    });

    for (final (size, scale) in const [(Size(320, 568), 1.3), (Size(360, 740), 1.3), (Size(412, 915), 1.3)]) {
      testWidgets(
          'body sits above the controls without scrolling at ${size.width.toInt()}x${size.height.toInt()} and ${scale}x',
          (tester) async {
        await pumpOnboarding(tester, size: size, textScale: scale, fontFamily: family);
        await walkAllSlides(tester, copyMustFit: true);
      }, skip: !available);
    }
  });

  group('Onboarding content', () {
    testWidgets('first slide welcomes the user and shows the brand and Skip', (tester) async {
      await pumpOnboarding(tester);
      expect(find.text(OnboardingScreen.welcome), findsOneWidget);
      expect(find.text(OnboardingScreen.brand), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text(_slides[0].title), findsOneWidget);
    });

    testWidgets('the welcome line is only on the first slide', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(_nextButton);
      await tester.pumpAndSettle();
      expect(find.text(OnboardingScreen.welcome), findsNothing);
      expect(find.text(OnboardingScreen.brand), findsOneWidget);
    });

    testWidgets('illustrations and progress are labelled for screen readers', (tester) async {
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

    testWidgets('the last slide hides Skip and shows the big Get started button', (tester) async {
      await pumpOnboarding(tester);
      for (var i = 0; i < _slides.length - 1; i++) {
        await tester.tap(_nextButton);
        await tester.pumpAndSettle();
      }
      expect(find.text(_slides.last.title), findsOneWidget);
      expect(find.descendant(of: _nextButton, matching: find.text('Get started')), findsOneWidget);
      final skip = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(const ValueKey('onboarding-skip')), matching: find.byType(AnimatedOpacity)),
      );
      expect(skip.opacity, 0);
      // The tap on the hidden Skip does nothing.
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
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

    testWidgets('Skip from a middle slide also goes to login', (tester) async {
      await pumpOnboarding(tester);
      await tester.tap(_nextButton);
      await tester.pumpAndSettle();
      await tester.tap(_nextButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN STUB'), findsOneWidget);
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
      expect(find.bySemanticsLabel('Step 2 of ${_slides.length}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Get started leaves onboarding for login and marks it seen', (tester) async {
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
