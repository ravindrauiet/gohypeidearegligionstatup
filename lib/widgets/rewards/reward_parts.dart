import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../ui/app_ui.dart';

final _fmt = NumberFormat.decimalPattern('en_IN');

/// "10,000" / "1,25,000" (Indian grouping).
String formatCoins(int n) => _fmt.format(n);

/// Gold progress ring with an optional centre child.
class CoinProgressRing extends StatelessWidget {
  final double progress;
  final double size;
  final double stroke;
  final Color track;
  final Widget? child;

  const CoinProgressRing({
    super.key,
    required this.progress,
    this.size = 96,
    this.stroke = 9,
    this.track = const Color(0x33FFFFFF),
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, track),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final double stroke;
  final Color track;
  _RingPainter(this.v, this.stroke, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
        r,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * math.max(v, 0.015),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [Color(0xFFFFE08A), AppColors.gold, Color(0xFFFF9A3C)],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.stroke != stroke || old.track != track;
}

/// Animated number count-up (snaps when reduced motion is on).
class CountUpText extends StatelessWidget {
  final int value;
  final TextStyle style;
  const CountUpText(this.value, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formatCoins(v.round()), style: style, maxLines: 1),
    );
  }
}

/// 7 small day circles: done days ticked, today ringed.
class StreakWeekRow extends StatelessWidget {
  /// Days already checked in within the current 7-day cycle (0..7).
  final int done;

  /// Whether today's slot is the next one (i.e. today is not claimed yet).
  final bool todayPending;
  final bool onDark;

  const StreakWeekRow({super.key, required this.done, this.todayPending = true, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final todayIndex = todayPending ? done.clamp(0, 6) : (done - 1).clamp(0, 6);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _Dot(filled: i < done, today: i == todayIndex, onDark: onDark),
              const SizedBox(height: 6),
              Text(i == todayIndex ? 'Today' : 'Day ${i + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: i == todayIndex ? FontWeight.w800 : FontWeight.w600,
                    color: i == todayIndex
                        ? (onDark ? AppColors.gold : AppColors.primaryDark)
                        : (onDark ? AppColors.textOnDarkMuted : AppColors.textTertiary),
                  )),
            ]),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool filled;
  final bool today;
  final bool onDark;
  const _Dot({required this.filled, required this.today, required this.onDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled
            ? const LinearGradient(colors: [Color(0xFFFFD66B), Color(0xFFF0A422)], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        color: filled ? null : (onDark ? Colors.white.withValues(alpha: 0.08) : AppColors.surfaceMuted),
        border: today
            ? Border.all(color: onDark ? AppColors.gold : AppColors.primary, width: 2)
            : Border.all(color: filled ? Colors.transparent : (onDark ? Colors.white24 : AppColors.border)),
      ),
      child: filled
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : (today
              ? Icon(Icons.add_rounded, size: 18, color: onDark ? AppColors.gold : AppColors.primary)
              : null),
    );
  }
}

/// How many dots to fill for a streak of [streakDays].
int streakDotsDone(int streakDays, {required bool claimedToday}) {
  if (streakDays <= 0) return 0;
  if (claimedToday) return ((streakDays - 1) % 7) + 1;
  return streakDays % 7;
}
