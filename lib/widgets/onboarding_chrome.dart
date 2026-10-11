import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cosmic_background.dart';

export 'cosmic_background.dart';

// ============================================================================
// Onboarding chrome. The night sky, brand mark and gold button are shared with
// sign-in and live in cosmic_background.dart; this file keeps the onboarding
// names for them and adds the segmented progress bar.
// ============================================================================

const Color onboardingGoldLight = cosmicGoldLight;
const Color onboardingGoldDeep = cosmicGoldDeep;
const LinearGradient onboardingGoldGradient = cosmicGoldGradient;
const Color onboardingNight = cosmicNight;
const Duration onboardingIdleDuration = cosmicIdleDuration;

typedef OnboardingSky = CosmicBackground;
typedef OnboardingMark = CosmicMark;
typedef OnboardingPrimaryButton = CosmicPrimaryButton;

// ----------------------------------------------------------------------------
// Progress
// ----------------------------------------------------------------------------

/// Slim segmented progress bar (like stories). [page] is the pager's
/// fractional page, so the next segment fills while the user swipes.
class OnboardingProgress extends StatelessWidget {
  final double page;
  final int count;
  const OnboardingProgress({super.key, required this.page, required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      width: double.infinity,
      child: CustomPaint(painter: _ProgressPainter(page, count)),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double page;
  final int count;
  const _ProgressPainter(this.page, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 6.0;
    final w = (size.width - gap * (count - 1)) / count;
    final radius = Radius.circular(size.height / 2);
    final track = Paint()..color = Colors.white.withValues(alpha: 0.16);
    final fill = Paint()..shader = onboardingGoldGradient.createShader(Offset.zero & size);
    final glow = Paint()
      ..color = onboardingGoldDeep.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (var i = 0; i < count; i++) {
      final left = i * (w + gap);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, w, size.height), radius), track);
      final f = (page - i + 1).clamp(0.0, 1.0);
      if (f <= 0) continue;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(left, 0, math.max(size.height, w * f), size.height), radius);
      if (f < 1 || i == page.round()) canvas.drawRRect(r, glow);
      canvas.drawRRect(r, fill);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => old.page != page || old.count != count;
}

