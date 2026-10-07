import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import 'services/backend_service.dart';
import 'utils/app_routes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AstroApp());
}

class AstroApp extends StatelessWidget {
  const AstroApp({super.key});

  static final Map<String, WidgetBuilder> routes = {
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
  };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Created eagerly so the persisted session starts loading immediately.
        ChangeNotifierProvider(create: (_) => BackendService(), lazy: false),
      ],
      child: MaterialApp(
        title: 'CosmicGuide - Vedic Kundli & Guidance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          primaryColor: Colors.black,
          scaffoldBackgroundColor: const Color(0xFFFCF7F1),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFB9548),
            primary: Colors.black,
            secondary: const Color(0xFFFB9548),
            surface: const Color(0xFFFCF7F1),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
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
