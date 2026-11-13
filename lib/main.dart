import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/meetups/propose_meetup_screen.dart';
import 'screens/trust/verification_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/topic_selection_screen.dart';
import 'screens/birth_details_screen.dart';
import 'screens/home_screen.dart';
import 'screens/kundli_view_screen.dart';
import 'screens/chatbot_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/about_us_screen.dart';
import 'screens/blog_screen.dart';
import 'screens/consultation_history_screen.dart';
import 'screens/contact_screen.dart';
import 'screens/date_explorer_screen.dart';
import 'screens/forecast_screen.dart';
import 'screens/life_timeline_screen.dart';
import 'screens/faq_screen.dart';
import 'screens/games/cosmic_match_screen.dart';
import 'screens/games/games_hub_screen.dart';
import 'screens/games/graha_quest_screen.dart';
import 'screens/games/moksha_patam_screen.dart';
import 'screens/games/nakshatra_cards_screen.dart';
import 'screens/gemstone_remedy_screen.dart';
import 'screens/help_screen.dart';
import 'screens/panchang_screen.dart';
import 'screens/pandit_dashboard_screen.dart';
import 'screens/pandit_login_screen.dart';
import 'screens/pandit_registration_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/analytics_service.dart';
import 'services/clarity/clarity.dart';
import 'services/backend_service.dart';
import 'services/buddy_service.dart';
import 'services/jap_service.dart';
import 'services/meetup_service.dart';
import 'services/notification_inbox_service.dart';
import 'services/notification_router.dart';
import 'services/notification_service.dart';
import 'services/rewards_service.dart';
import 'services/video_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Time zones + optional Firebase (push is disabled when it is not configured).
  await NotificationService.bootstrap();
  ProposeMeetupScreen.verifyBuilder = (_) => const VerificationScreen();
  runApp(wrapWithClarity(const AstroApp()));
}

class AstroApp extends StatelessWidget {
  const AstroApp({super.key});

  /// Screens with no personal data. Everything else (chats, birth details, kundli, forecasts,
  /// profile, wallet, login, buddy/family screens...) stays masked in Clarity recordings.
  static const Set<String> _publicScreens = {
    AppRoutes.onboarding, AppRoutes.topicSelection, AppRoutes.home, AppRoutes.about,
    AppRoutes.blog, AppRoutes.faq, AppRoutes.help, AppRoutes.panchang, AppRoutes.privacy,
    AppRoutes.terms, AppRoutes.gemstoneRemedy, AppRoutes.games, AppRoutes.gamesQuest,
    AppRoutes.gamesCards, AppRoutes.gamesMoksha, AppRoutes.gamesCircle,
  };

  static final Map<String, WidgetBuilder> routes = _routes.map((name, builder) => MapEntry(
        name,
        _publicScreens.contains(name) ? (context) => clarityPublic(builder(context)) : builder,
      ));

  static final Map<String, WidgetBuilder> _routes = {
    AppRoutes.splash: (context) => const SplashScreen(),
    AppRoutes.onboarding: (context) => const OnboardingScreen(),
    AppRoutes.login: (context) => const LoginScreen(),
    AppRoutes.register: (context) => const RegisterScreen(),
    AppRoutes.topicSelection: (context) => const TopicSelectionScreen(),
    AppRoutes.birthDetails: (context) => const BirthDetailsScreen(),
    AppRoutes.home: (context) => const HomeScreen(),
    AppRoutes.kundliView: (context) => const KundliViewScreen(),
    AppRoutes.chatbot: (context) => const ChatbotScreen(),
    AppRoutes.about: (context) => const AboutUsScreen(),
    AppRoutes.blog: (context) => const BlogScreen(),
    AppRoutes.consultationHistory: (context) =>
        const ConsultationHistoryScreen(),
    AppRoutes.contact: (context) => const ContactScreen(),
    AppRoutes.faq: (context) => const FAQScreen(),
    AppRoutes.gemstoneRemedy: (context) => const GemstoneRemedyScreen(),
    AppRoutes.help: (context) => const HelpScreen(),
    AppRoutes.panchang: (context) => const PanchangScreen(),
    AppRoutes.panditDashboard: (context) => const PanditDashboardScreen(),
    AppRoutes.panditLogin: (context) => const PanditLoginScreen(),
    AppRoutes.panditRegistration: (context) => const PanditRegistrationScreen(),
    AppRoutes.privacy: (context) => const PrivacyScreen(),
    AppRoutes.profile: (context) => const ProfileScreen(),
    AppRoutes.terms: (context) => const TermsScreen(),
    AppRoutes.wallet: (context) => const WalletScreen(),
    AppRoutes.forecast: (context) => ForecastScreen.fromArgs(ModalRoute.of(context)?.settings.arguments),
    AppRoutes.lifeTimeline: (context) => LifeTimelineScreen.fromArgs(ModalRoute.of(context)?.settings.arguments),
    AppRoutes.dateExplorer: (context) => DateExplorerScreen.fromArgs(ModalRoute.of(context)?.settings.arguments),
    AppRoutes.games: (context) => const GamesHubScreen(),
    AppRoutes.gamesQuest: (context) => const GrahaQuestScreen(),
    AppRoutes.gamesCards: (context) => const NakshatraCardsScreen(),
    AppRoutes.gamesMoksha: (context) => const MokshaPatamScreen(),
    AppRoutes.gamesCircle: (context) => const CosmicMatchScreen(),
  };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Created eagerly so the persisted session starts loading immediately.
        ChangeNotifierProvider(create: (_) => BackendService(), lazy: false),
        ChangeNotifierProvider(create: (c) => RewardsService(c.read<BackendService>())),
        ChangeNotifierProvider(create: (c) => VideoService(c.read<BackendService>())),
        ChangeNotifierProvider(create: (c) => BuddyService(c.read<BackendService>())),
        ChangeNotifierProvider(create: (c) => JapService(c.read<BackendService>(), rewards: c.read<RewardsService>())),
        ChangeNotifierProvider(create: (c) => NotificationInboxService(c.read<BackendService>())),
        ChangeNotifierProvider(create: (c) => MeetupService(c.read<BackendService>())), // v3 meetups
        ChangeNotifierProvider(
          lazy: false,
          create: (c) => NotificationService(
            backend: c.read<BackendService>(),
            rewards: c.read<RewardsService>(),
            push: NotificationService.firebaseReady ? FirebasePushClient() : null,
            onPush: (_) => c.read<NotificationInboxService>().onPushReceived(),
          )..start(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: NotificationRouter.navigatorKey,
        navigatorObservers: [AnalyticsService.observer(), ScreenNameObserver()],
        // Mask the whole app in Clarity recordings by default; public screens unmask themselves.
        builder: (context, child) => clarityPrivate(child ?? const SizedBox.shrink()),
        title: 'CosmicGuide - Vedic Kundli & Guidance',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.splash,
        routes: routes,
        // Never crash on an unknown route name: fall back to the splash router,
        // which sends the user to the right place for their session state.
        onUnknownRoute: (settings) => MaterialPageRoute(
          builder: (context) => const SplashScreen(),
          settings: settings,
        ),
      ),
    );
  }
}
