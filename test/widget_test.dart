import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cosmicguide/main.dart';
import 'package:cosmicguide/screens/auth/login_screen.dart';
import 'package:cosmicguide/screens/birth_details_screen.dart';
import 'package:cosmicguide/screens/topic_selection_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:cosmicguide/utils/app_routes.dart';
import 'package:cosmicguide/utils/validators.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps the app and lets the splash screen resolve its start route.
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const AstroApp());
  await tester.pump(); // post-frame callback kicks off session restore
  await tester.pump(const Duration(seconds: 1)); // splash minimum display
  await tester.pumpAndSettle();
}

final _realGoogleIdToken = LoginScreen.googleIdToken;

void main() {
  group('App entry flow', () {
    testWidgets('first launch shows onboarding', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpApp(tester);

      expect(find.text('Welcome to CosmicGuide'), findsOneWidget);
      expect(find.text('Your true Vedic Kundli'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('skipping onboarding lands on login and is remembered',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpApp(tester);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Continue with Email'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_seen'), isTrue);
    });

    testWidgets('returning signed-out user goes straight to login',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await pumpApp(tester);

      expect(find.text('Continue with Email'), findsOneWidget);
      expect(find.text('Welcome to CosmicGuide'), findsNothing);
    });

    testWidgets('email login sheet validates input before calling backend',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await pumpApp(tester);

      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome Back'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your email address'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('login offers every way to continue', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Continue with Email'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.textContaining('Create an account', findRichText: true),
          findsOneWidget);
    });

    testWidgets('cancelling Google sign-in stays on login quietly',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      LoginScreen.googleIdToken = () async => null;
      addTearDown(() => LoginScreen.googleIdToken = _realGoogleIdToken);
      await pumpApp(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Email'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Google sign-in failure explains and offers email',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      LoginScreen.googleIdToken = () async => throw Exception('no plugin');
      addTearDown(() => LoginScreen.googleIdToken = _realGoogleIdToken);
      await pumpApp(tester);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Google sign-in is unavailable'), findsOneWidget);
      expect(find.text('Continue with Email'), findsOneWidget);
    });

    testWidgets('create account opens the sign-up form and can switch back',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await pumpApp(tester);

      await tester
          .tap(find.textContaining('Create an account', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Create New Account'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your email address'), findsOneWidget);

      await tester.tap(
          find.textContaining('Already have an account', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Full Name'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('legal links on login open Terms and Privacy', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_seen': true});
      await pumpApp(tester);

      await tester.ensureVisible(find.text('Terms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Email'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Privacy Policy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Email'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-in user without a Kundli resumes at birth details',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'test-token',
        'user_data': jsonEncode({'fullName': 'Test User'}),
      });
      await pumpApp(tester);

      expect(find.text('Enter your Name'), findsOneWidget);
      // Name is pre-filled from the stored account.
      expect(find.widgetWithText(TextField, 'Test User'), findsOneWidget);

      // Clearing the name blocks progress with a helpful message.
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Please enter your name'), findsOneWidget);
    });
  });

  group('First-run screens fit small phones with large text', () {
    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<BackendService>(
          create: (_) => BackendService(),
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('login', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpScreen(tester, const LoginScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Continue with Google'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue with Email'));
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('topic selection toggles cards and needs one pick',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpScreen(tester, const TopicSelectionScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('My Vedic Kundli'));
      await tester.pump();
      expect(find.text('Select at least one'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('My planet weather'), 200);
      await tester.tap(find.text('My planet weather'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('birth details steps', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpScreen(tester, const BirthDetailsScreen());
      expect(find.text('Step 1 of 4'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Asha');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Who You Are'), findsOneWidget);
      await tester.tap(find.text('Female'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Date and time are required, shown inline.
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Please select your date of birth'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Routing table', () {
    test('every named route is registered', () {
      const names = [
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.topicSelection,
        AppRoutes.birthDetails,
        AppRoutes.home,
        AppRoutes.kundliView,
        AppRoutes.chatbot,
        AppRoutes.about,
        AppRoutes.blog,
        AppRoutes.consultationHistory,
        AppRoutes.contact,
        AppRoutes.faq,
        AppRoutes.gemstoneRemedy,
        AppRoutes.help,
        AppRoutes.panchang,
        AppRoutes.panditDashboard,
        AppRoutes.panditLogin,
        AppRoutes.panditRegistration,
        AppRoutes.privacy,
        AppRoutes.profile,
        AppRoutes.terms,
        AppRoutes.wallet,
        AppRoutes.forecast,
        AppRoutes.lifeTimeline,
        AppRoutes.dateExplorer,
        AppRoutes.games,
        AppRoutes.gamesQuest,
        AppRoutes.gamesCards,
        AppRoutes.gamesMoksha,
        AppRoutes.gamesCircle,
      ];
      for (final name in names) {
        expect(AstroApp.routes.containsKey(name), isTrue,
            reason: '$name missing');
      }
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email(' user@example.com '), isNull);
    });

    test('password length only enforced for new passwords', () {
      expect(Validators.password('abc'), isNull);
      expect(Validators.password('abc', isNew: true), isNotNull);
      expect(Validators.password('abcdef', isNew: true), isNull);
    });
  });
}
