import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend_service.dart';

/// Named routes used across the app. Every name here is registered in
/// `AstroApp.routes` (lib/main.dart).
class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const topicSelection = '/topic-selection';
  static const birthDetails = '/birth-details';
  static const home = '/home';
  static const kundliView = '/kundli-view';
  static const chatbot = '/chatbot';
  static const about = '/about';
  static const blog = '/blog';
  static const consultationHistory = '/consultation-history';
  static const contact = '/contact';
  static const faq = '/faq';
  static const gemstoneRemedy = '/gemstone-remedy';
  static const help = '/help';
  static const panchang = '/panchang';
  static const panditDashboard = '/pandit-dashboard';
  static const panditLogin = '/pandit-login';
  static const panditRegistration = '/pandit-registration';
  static const privacy = '/privacy';
  static const profile = '/profile';
  static const terms = '/terms';
  static const wallet = '/wallet';
}

/// Helpers that decide where the user should land in the entry flow.
class AuthFlow {
  AuthFlow._();

  static const _onboardingSeenKey = 'onboarding_seen';

  /// Where a signed-in user should go: the dashboard if their Kundli exists,
  /// otherwise the topic picker that leads into birth details.
  static String routeAfterLogin(BackendService backend) =>
      backend.hasBirthDetails ? AppRoutes.home : AppRoutes.topicSelection;

  /// Where the app should start for the current persisted session.
  static Future<String> resolveStartRoute(BackendService backend) async {
    final prefs = await SharedPreferences.getInstance();
    // BackendService starts loading the stored session in its constructor
    // using the same SharedPreferences instance, so by the time the await
    // above resolves the session state has been restored. Fall back to prefs
    // directly in case the service has not finished.
    final hasToken = backend.isAuthenticated ||
        (prefs.getString('auth_token')?.isNotEmpty ?? false);
    if (hasToken) {
      final hasKundli = backend.hasBirthDetails ||
          (prefs.getString('kundli_data')?.contains('"ascendant"') ?? false);
      return hasKundli ? AppRoutes.home : AppRoutes.birthDetails;
    }
    final seenOnboarding = prefs.getBool(_onboardingSeenKey) ?? false;
    return seenOnboarding ? AppRoutes.login : AppRoutes.onboarding;
  }

  static Future<void> markOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingSeenKey, true);
    } catch (_) {
      // Non-critical: worst case the user sees onboarding again.
    }
  }
}
