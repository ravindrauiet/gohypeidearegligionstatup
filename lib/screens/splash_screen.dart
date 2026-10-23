import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthAndNavigate());
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
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.cosmic,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.cosmicGradient),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                      child: Semantics(
                        label: 'CosmicGuide, loading',
                        container: true,
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(AppRadius.xl),
                                  boxShadow: AppShadows.raised,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.xl),
                                  child: Image.asset(
                                    'assets/icons/cosmicguide_icon.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: AppColors.cosmicLight,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.explore_rounded, size: 44, color: AppColors.gold),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                'CosmicGuide',
                                textAlign: TextAlign.center,
                                style: AppText.display.copyWith(color: AppColors.textOnDark),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Vedic astrology, made simple',
                                textAlign: TextAlign.center,
                                style: AppText.body.copyWith(color: AppColors.textOnDarkMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  child: SizedBox(
                    width: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        // A still bar when the system asks for less motion.
                        value: reduceMotion ? 0.35 : null,
                        minHeight: 3,
                        color: AppColors.primary,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
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
