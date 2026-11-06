import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/jap_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'jap_counter_screen.dart';

/// Thin progress ring plus a ring of 108 small beads (filled as you count).
class JapBeadRing extends StatelessWidget {
  final int count;
  final int total;
  final double size;
  final Widget? child;

  const JapBeadRing({super.key, required this.count, this.total = JapService.malaSize, required this.size, this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BeadRingPainter(count.clamp(0, total), total),
        child: Center(child: child),
      ),
    );
  }
}

class _BeadRingPainter extends CustomPainter {
  final int count;
  final int total;
  const _BeadRingPainter(this.count, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    const stroke = 3.0;

    // Track + progress arc (outermost, thin).
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.border,
    );
    if (count > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * count / total,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = AppColors.primary,
      );
    }

    // Beads, just inside the ring.
    final beadR = r - 12;
    final gap = 2 * math.pi * beadR / total;
    final dot = (gap * 0.30).clamp(1.2, 3.2);
    final done = Paint()..color = AppColors.gold;
    final todo = Paint()..color = const Color(0xFFE2DCD3);
    for (var i = 0; i < total; i++) {
      final a = -math.pi / 2 + 2 * math.pi * (i + 0.5) / total;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * beadR, dot, i < count ? done : todo);
    }
    // Meru (guru) bead at the top.
    canvas.drawCircle(c + Offset(0, -beadR), dot + 1.6, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant _BeadRingPainter old) => old.count != count || old.total != total;
}

/// Seven simple bars, oldest first (today last).
class JapWeekChart extends StatelessWidget {
  final List<JapDayStat> days;
  final DateTime today;
  const JapWeekChart({super.key, required this.days, required this.today});

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final maxV = days.fold<int>(1, (m, d) => math.max(m, d.malas));
    final total = days.fold<int>(0, (s, d) => s + d.malas);
    return Semantics(
      label: 'Last 7 days: $total ${total == 1 ? 'mala' : 'malas'}',
      excludeSemantics: true,
      child: SizedBox(
        height: 120,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (d.malas > 0)
                      FittedBox(
                        child: Text('${d.malas}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: d.malas == 0 ? 0.04 : (d.malas / maxV).clamp(0.08, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: d.malas == 0 ? AppColors.border : AppColors.primary.withValues(alpha: _isToday(d.day) ? 1 : 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      child: Text(_letters[d.day.weekday - 1],
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: _isToday(d.day) ? FontWeight.w800 : FontWeight.w500,
                              color: _isToday(d.day) ? AppColors.textPrimary : AppColors.textTertiary)),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
}

/// Compact Home card: today's malas, streak and a "Start jap" button.
/// Needs a [JapService] provider above it. [onOpen] defaults to pushing
/// [JapCounterScreen].
class JapHomeCard extends StatefulWidget {
  final VoidCallback? onOpen;
  const JapHomeCard({super.key, this.onOpen});

  @override
  State<JapHomeCard> createState() => _JapHomeCardState();
}

class _JapHomeCardState extends State<JapHomeCard> {
  @override
  void initState() {
    super.initState();
    context.read<JapService>().load();
  }

  void _open() {
    final cb = widget.onOpen;
    if (cb != null) {
      cb();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JapCounterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<JapService>();
    final today = s.todayMalas;
    final streak = s.streak;
    final inProgress = s.count > 0;
    final subtitle = !s.loaded
        ? 'Chant 108 names with a calm digital mala'
        : today == 0 && streak == 0
            ? (inProgress ? '${s.count} of 108 on ${s.mantra.name}' : 'Chant 108 names with a calm digital mala')
            : [
                '$today ${today == 1 ? 'mala' : 'malas'} today',
                if (streak > 0) '$streak-day streak',
              ].join(' · ');
    return AppCard(
      onTap: _open,
      shadow: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: s.progress,
                  strokeWidth: 3,
                  backgroundColor: AppColors.border,
                  color: AppColors.primary,
                ),
              ),
              const Icon(Icons.self_improvement_rounded, color: AppColors.primary, size: 24),
            ]),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Jap mala', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: inProgress ? 'Continue jap' : 'Start jap',
          icon: Icons.play_arrow_rounded,
          height: 44,
          variant: AppButtonVariant.secondary,
          onPressed: _open,
        ),
      ]),
    );
  }
}
