import 'package:flutter/material.dart';

import 'ui/app_ui.dart';

/// Full-screen CosmicGuide loader (same look as the splash screen) shown while something
/// slow happens on the user's behalf, e.g. building their Kundli from birth details typed
/// in the AI chat. Put it on top of the screen in a Stack while [visible].
class CosmicGuideLoader extends StatelessWidget {
  const CosmicGuideLoader({
    super.key,
    required this.title,
    this.message,
  });

  /// Main line, e.g. "Preparing your Kundli".
  final String title;

  /// Current step, e.g. "Finding Namakkal on the map…".
  final String? message;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Positioned.fill(
      child: Semantics(
        label: '$title. ${message ?? ''}',
        liveRegion: true,
        container: true,
        child: AbsorbPointer(
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppColors.cosmicGradient),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppText.body.copyWith(color: AppColors.textOnDark, fontWeight: FontWeight.w600),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 6),
                          AnimatedSwitcher(
                            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
                            child: Text(
                              message!,
                              key: ValueKey(message),
                              textAlign: TextAlign.center,
                              style: AppText.body.copyWith(color: AppColors.textOnDarkMuted),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: 120,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: LinearProgressIndicator(
                              value: reduceMotion ? 0.35 : null,
                              minHeight: 3,
                              color: AppColors.primary,
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
