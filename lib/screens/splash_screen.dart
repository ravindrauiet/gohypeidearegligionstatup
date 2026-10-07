import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../utils/app_routes.dart';

/// Entry point of the app. Restores the persisted session and routes the user:
/// signed in + Kundli -> /home, signed in without Kundli -> /birth-details,
/// returning signed-out user -> /login, first launch -> /onboarding.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// Minimum time the splash stays visible so it does not flash.
  static const minimumDisplay = Duration(milliseconds: 900);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkAuthAndNavigate());
  }

  Future<void> _checkAuthAndNavigate() async {
    if (!mounted) return;
    final backendService = context.read<BackendService>();

    String route = AppRoutes.onboarding;
    try {
      final results = await Future.wait<Object?>([
        AuthFlow.resolveStartRoute(backendService),
        Future<void>.delayed(SplashScreen.minimumDisplay),
      ]);
      route = results.first as String;
    } catch (e) {
      debugPrint('Splash: failed to restore session: $e');
    }

    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icons/cosmicguide_icon.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.explore_rounded,
                        size: 54,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'CosmicGuide',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authentic Vedic Astrology & Guidance',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
