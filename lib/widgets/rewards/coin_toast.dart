import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/rewards_service.dart';
import '../ui/app_ui.dart';

/// Gold coin drawn in code: radial gold face, darker rim, embossed star.
class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'coin',
      child: SizedBox(width: size, height: size, child: const CustomPaint(painter: _CoinPainter())),
    );
  }
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Rim
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD66B), Color(0xFFD9901A), Color(0xFFB9720C)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Face
    final face = r * 0.80;
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [Color(0xFFFFF0B3), Color(0xFFFFCB45), Color(0xFFF0A422)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: face)),
    );
    // Inner ring
    canvas.drawCircle(
      c,
      face * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, r * 0.06)
        ..color = const Color(0xFFD48A12).withValues(alpha: 0.55),
    );
    // Four-point star (embossed: dark shadow + light face)
    Path star(Offset o, double s) {
      final p = Path();
      for (var i = 0; i < 8; i++) {
        final a = -math.pi / 2 + i * math.pi / 4;
        final len = i.isEven ? s : s * 0.36;
        final pt = o + Offset(math.cos(a), math.sin(a)) * len;
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      return p..close();
    }

    final s = face * 0.52;
    canvas.drawPath(star(c + Offset(r * 0.04, r * 0.05), s), Paint()..color = const Color(0xFFB8700A).withValues(alpha: 0.6));
    canvas.drawPath(star(c, s), Paint()..color = const Color(0xFFFFF6D6));
    // Shine
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: face * 0.92),
      math.pi * 1.05,
      math.pi * 0.45,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.8, r * 0.09)
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

OverlayEntry? _current;

/// Floating "+10 coins" toast near the top of the screen. It slides in, rests,
/// then fades away; it never blocks taps. With reduced motion it only fades.
void showCoinToast(BuildContext context, int amount, {String? reason}) {
  if (amount == 0) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.remove();
  _current = null;
  HapticFeedback.lightImpact();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoinToast(
      amount: amount,
      reason: reason,
      onDone: () {
        if (_current == entry) _current = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

/// Reads `coinsAwarded` from a game / API response; when positive, shows the
/// toast and adds the coins to [RewardsService] (if one is provided above).
int showCoinsFromResponse(BuildContext context, Map<String, dynamic>? response,
    {String? reason, String rewardReason = 'game', String ref = ''}) {
  final raw = response?['coinsAwarded'];
  final amount = raw is num ? raw.round() : (raw is String ? int.tryParse(raw) ?? 0 : 0);
  if (amount <= 0 || !context.mounted) return 0;
  try {
    Provider.of<RewardsService>(context, listen: false).applyAward(amount, reason: rewardReason, ref: ref);
  } on ProviderNotFoundException {
    // Screens shown without the rewards provider (tests, previews) still toast.
  }
  showCoinToast(context, amount, reason: reason);
  return amount;
}

class _CoinToast extends StatefulWidget {
  final int amount;
  final String? reason;
  final VoidCallback onDone;
  const _CoinToast({required this.amount, this.reason, required this.onDone});

  @override
  State<_CoinToast> createState() => _CoinToastState();
}

class _CoinToastState extends State<_CoinToast> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 2600);
  late final AnimationController _c = AnimationController(vsync: this, duration: _total)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final top = MediaQuery.paddingOf(context).top + 12;
    final positive = widget.amount > 0;
    final label = '${positive ? '+' : ''}${widget.amount} ${widget.amount.abs() == 1 ? 'coin' : 'coins'}';

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: widget.reason == null ? label : '$label. ${widget.reason}',
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = _c.value;
              // 0..0.14 in, rest, 0.86..1 out
              final inT = Curves.easeOutCubic.transform((t / 0.14).clamp(0.0, 1.0));
              final outT = Curves.easeInCubic.transform(((t - 0.86) / 0.14).clamp(0.0, 1.0));
              final opacity = (inT * (1 - outT)).clamp(0.0, 1.0);
              final dy = reduce ? 0.0 : (-28 * (1 - inT)) + (-14 * outT);
              final pop = reduce ? 1.0 : Curves.elasticOut.transform((t / 0.32).clamp(0.0, 1.0));
              final spin = reduce ? 0.0 : (1 - Curves.easeOut.transform((t / 0.4).clamp(0.0, 1.0))) * math.pi;
              return Opacity(
                opacity: opacity,
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _ToastBody(
                      label: label,
                      reason: widget.reason,
                      coin: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scaleByDouble(0.6 + 0.4 * pop, 0.6 + 0.4 * pop, 1, 1)
                          ..rotateY(spin),
                        child: const CoinIcon(size: 34),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToastBody extends StatelessWidget {
  final String label;
  final String? reason;
  final Widget coin;
  const _ToastBody({required this.label, this.reason, required this.coin});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2B1E6E), AppColors.cosmic],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(color: AppColors.gold.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 6)),
            ...AppShadows.raised,
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          coin,
          const SizedBox(width: 10),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFFFFD66B), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              if (reason != null && reason!.isNotEmpty)
                Text(reason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ),
    );
  }
}
