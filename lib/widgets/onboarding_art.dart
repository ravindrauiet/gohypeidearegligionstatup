import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'moksha_board.dart' show MokshaColors;
import 'onboarding_chrome.dart';

// ============================================================================
// Onboarding illustrations
//
// Every slide's hero is drawn in code as a rich, animated preview of the real
// feature, on top of the night sky painted by OnboardingSky. They use static
// sample data only (never the backend), are laid out on a fixed 360x380 design
// canvas and scaled as one unit, so they cannot overflow on small phones or
// with large text.
// ============================================================================

/// Size of the design canvas every illustration is laid out on.
const double onboardingArtWidth = 360;
const double onboardingArtHeight = 380;

const double _artW = onboardingArtWidth;
const double _artH = onboardingArtHeight;

const Color _gold1 = onboardingGoldLight;
const Color _gold2 = onboardingGoldDeep;
const Color _inkDark = Color(0xFF1B1538);
const Color _mint = Color(0xFF4ADE80);
const Color _rose = Color(0xFFFF7A7A);
const Color _sky = Color(0xFF7CC4FF);

Color _w(double alpha) => Colors.white.withValues(alpha: alpha);

/// The app font, for text drawn straight onto a canvas.
String? _fontOf(BuildContext context) => DefaultTextStyle.of(context).style.fontFamily;

/// Progress of the sub-interval [a, b] of the slide timeline `t` (0..1).
double _seg(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) {
  if (t <= a) return 0;
  if (t >= b) return 1;
  return curve.transform((t - a) / (b - a));
}

/// The gentle motion that continues after the entrance: [s] is seconds since
/// the slide became active and [e] an envelope (0..1) that eases the motion in
/// and back out, so the picture always comes to rest in its final state.
class _Idle {
  final double s;
  final double e;
  const _Idle(this.s, this.e);

  /// A slow sine wave in -1..1 (already multiplied by the envelope).
  double wave(double phase, {double period = 4}) => math.sin((s / period + phase) * math.pi * 2) * e;

  /// A sawtooth 0..1 that repeats every [period] seconds.
  double loop(double period, [double phase = 0]) => (s / period + phase) % 1.0;
}

Widget _tx(
  String text,
  double size, {
  FontWeight w = FontWeight.w600,
  Color c = Colors.white,
  int lines = 1,
  double h = 1.25,
  double ls = 0,
  TextAlign? align,
}) {
  return Text(
    text,
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: TextStyle(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls),
  );
}

/// Fades and scales a child in (v may overshoot 1 with a "back" curve).
Widget _pop(double v, Widget child, {Alignment alignment = Alignment.center}) {
  return Opacity(
    opacity: v.clamp(0.0, 1.0),
    child: Transform.scale(scale: 0.7 + 0.3 * v, alignment: alignment, child: child),
  );
}

/// Fades a child in while it rises a few pixels.
Widget _rise(double v, Widget child, {double dy = 14}) {
  return Opacity(
    opacity: v.clamp(0.0, 1.0),
    child: Transform.translate(offset: Offset(0, (1 - v) * dy), child: child),
  );
}

Widget _float(double dy, Widget child) => Transform.translate(offset: Offset(0, dy), child: child);

// ----------------------------------------------------------------------------
// Shared pieces
// ----------------------------------------------------------------------------

/// A frosted-glass surface: optional backdrop blur, a translucent fill, a
/// light edge that is brighter at the top-left, and a soft drop shadow.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final Color tint;
  final double fill;
  final Color? edge;
  final Color? glow;

  const _Glass({
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(14),
    this.blur = false,
    this.tint = Colors.white,
    this.fill = 0.10,
    this.edge,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget body = CustomPaint(
      foregroundPainter: _GlassEdgePainter(radius, edge),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Colors.white, tint, 0.6)!.withValues(alpha: fill + 0.07),
              tint.withValues(alpha: math.max(0.03, fill - 0.04)),
            ],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (blur) {
      body = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: body),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: const Color(0x3D0B0820),
        boxShadow: [
          const BoxShadow(color: Color(0x73050314), blurRadius: 22, offset: Offset(0, 12)),
          if (glow != null) BoxShadow(color: glow!.withValues(alpha: 0.30), blurRadius: 26, spreadRadius: -2),
        ],
      ),
      child: body,
    );
  }
}

class _GlassEdgePainter extends CustomPainter {
  final double radius;
  final Color? edge;
  const _GlassEdgePainter(this.radius, this.edge);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final c = edge ?? Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - 0.5))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.withValues(alpha: edge == null ? 0.46 : 0.95),
            c.withValues(alpha: edge == null ? 0.12 : 0.45),
            c.withValues(alpha: edge == null ? 0.20 : 0.70),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) => old.radius != radius || old.edge != edge;
}

/// A glass pill with a glowing dot or an icon.
class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool blur;
  final Color? edge;
  const _Chip(this.text, {required this.color, this.icon, this.blur = false, this.edge});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 19,
      blur: blur,
      fill: 0.16,
      edge: edge,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: color) else _GlowDot(color, size: 8),
          const SizedBox(width: 7),
          Flexible(child: _tx(text, 12.5, w: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GlowDot extends StatelessWidget {
  final Color color;
  final double size;
  final double pulse;
  const _GlowDot(this.color, {this.size = 8, this.pulse = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.85), blurRadius: size * (0.9 + pulse), spreadRadius: pulse * 2),
        ],
      ),
    );
  }
}

/// A luminous sphere: used for people and tokens.
class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  final Widget? child;
  final double glow;
  const _Orb({required this.size, required this.color, this.child, this.glow = 0.55});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.65)!,
            color,
            Color.lerp(color, const Color(0xFF140F35), 0.55)!,
          ],
          stops: const [0, 0.48, 1],
        ),
        border: Border.all(color: _w(0.55), width: size > 40 ? 1.6 : 1.1),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: glow), blurRadius: size * 0.45, spreadRadius: 1),
        ],
      ),
      child: child,
    );
  }
}

/// A small four-point sparkle.
class _Sparkle extends StatelessWidget {
  final double size;
  final double v;
  const _Sparkle({this.size = 12, this.v = 1});

  Color get color => _gold1;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _SparklePainter(color, v)));
  }
}

class _SparklePainter extends CustomPainter {
  final Color color;
  final double v;
  const _SparklePainter(this.color, this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final a = v.clamp(0.0, 1.0);
    if (a <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * (0.55 + 0.45 * a);
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final ang = -math.pi / 2 + i * math.pi / 4;
      final p = c + Offset(math.cos(ang), math.sin(ang)) * (i.isEven ? r : r * 0.26);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..color = color.withValues(alpha: 0.5 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
    canvas.drawPath(path, Paint()..color = Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: a));
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.v != v || old.color != color;
}

/// A glowing gradient progress ring.
class _RingPainter extends CustomPainter {
  final double fraction;
  final List<Color> colors;
  final double stroke;
  const _RingPainter({required this.fraction, required this.colors, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _w(0.10),
    );
    if (fraction <= 0) return;
    final sweep = math.pi * 2 * fraction;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke + 5
        ..color = colors.last.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.9),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          colors: [...colors, colors.first],
          transform: const GradientRotation(-math.pi / 2 - 0.25),
        ).createShader(rect),
    );
    // Bright bead at the tip of the arc.
    final a = -math.pi / 2 + sweep;
    final tip = rect.center + Offset(math.cos(a), math.sin(a)) * (rect.width / 2);
    canvas.drawCircle(tip, stroke * 0.28, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.stroke != stroke || old.colors != colors;
}

void _paintText(
  Canvas canvas,
  String text,
  Offset centre,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w800,
  String? font,
  double scale = 1,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: font, fontSize: size, height: 1, fontWeight: weight, color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  if (scale != 1) canvas.scale(scale, scale);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
  tp.dispose();
}

// ============================================================================
// Public widget
// ============================================================================

/// The hero illustration for onboarding slide [index] (0..5).
///
/// The entrance plays once each time [active] turns true, followed by a short
/// spell of gentle idle motion; with reduced motion
/// (`MediaQuery.disableAnimations`) the finished picture is shown immediately
/// and nothing moves.
class OnboardingArt extends StatefulWidget {
  final int index;
  final bool active;
  final Color accent;

  /// Signed distance of this slide from the centre of the pager (-1..1), used
  /// for a gentle parallax while swiping.
  final double parallax;

  const OnboardingArt({
    super.key,
    required this.index,
    required this.active,
    required this.accent,
    this.parallax = 0,
  });

  /// One-sentence descriptions read by screen readers.
  static const List<String> labels = [
    'Illustration: a North Indian Kundli chart with planets in their houses, Scorpio Lagna and Moon in Anuradha.',
    'Illustration: today\'s guidance card with a score of 74 out of 100, what the day is good for, what to be careful with and the best time.',
    'Illustration: a planet weather list showing how Saturn, Jupiter and the Sun affect you, beside a life timeline marked "You are here".',
    'Illustration: a daily mission being ticked for 30 XP, a Chitra star card, and a Snakes and Ladders board with a dice.',
    'Illustration: two people joined by a compatibility score of 31 out of 36, and a podium of who is luckiest today.',
    'Illustration: a chat where the AI astrologer answers a question about your week, with a pandit shown online.',
  ];

  @override
  State<OnboardingArt> createState() => _OnboardingArtState();
}

class _OnboardingArtState extends State<OnboardingArt> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _idle = AnimationController(vsync: this, duration: onboardingIdleDuration);
  late final Listenable _both = Listenable.merge([_enter, _idle]);
  bool? _reduce;

  void _play() {
    _enter.forward(from: 0);
    _idle.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce == _reduce) return;
    _reduce = reduce;
    if (reduce) {
      _enter.value = 1;
      _idle.stop();
      _idle.value = 0;
    } else if (widget.active) {
      _play();
    }
  }

  @override
  void didUpdateWidget(OnboardingArt old) {
    super.didUpdateWidget(old);
    if (_reduce == true) return;
    if (widget.active && !old.active) {
      _play();
    } else if (!widget.active && old.active) {
      _idle.stop();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _idle.dispose();
    super.dispose();
  }

  _Idle _idleNow() {
    final total = onboardingIdleDuration.inMilliseconds / 1000;
    final s = _idle.value * total;
    final rampIn = Curves.easeInOut.transform(((s - 1.4) / 1.6).clamp(0.0, 1.0));
    final rampOut = Curves.easeInOut.transform(((total - s) / 1.6).clamp(0.0, 1.0));
    return _Idle(s, rampIn * rampOut);
  }

  Widget _scene(double t, _Idle idle) {
    switch (widget.index) {
      case 0:
        return _KundliArt(t: t, idle: idle, accent: widget.accent);
      case 1:
        return _DayArt(t: t, idle: idle, accent: widget.accent);
      case 2:
        return _WhyArt(t: t, idle: idle, accent: widget.accent);
      case 3:
        return _GamesArt(t: t, idle: idle, accent: widget.accent);
      case 4:
        return _PeopleArt(t: t, idle: idle, accent: widget.accent);
      default:
        return _AskArt(t: t, idle: idle, accent: widget.accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shift = _reduce == true ? 0.0 : widget.parallax.clamp(-1.0, 1.0) * 44;
    return Semantics(
      image: true,
      label: OnboardingArt.labels[widget.index.clamp(0, OnboardingArt.labels.length - 1)],
      child: ExcludeSemantics(
        child: Transform.translate(
          offset: Offset(shift, 0),
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: SizedBox(
              width: _artW,
              height: _artH,
              child: MediaQuery.withNoTextScaling(
                child: AnimatedBuilder(
                  animation: _both,
                  builder: (context, _) => _scene(_enter.value, _idleNow()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 1. Vedic Kundli
// ============================================================================

class _KundliArt extends StatelessWidget {
  final double t;
  final _Idle idle;
  final Color accent;
  const _KundliArt({required this.t, required this.idle, required this.accent});

  static const double _chart = 256;
  static const Offset _c = Offset(_artW / 2, 186);

  @override
  Widget build(BuildContext context) {
    final ring = _seg(t, 0.0, 0.34);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Slowly turning zodiac ring behind the chart.
        Positioned(
          left: _c.dx - 176,
          top: _c.dy - 176,
          width: 352,
          height: 352,
          child: Opacity(
            opacity: ring,
            child: Transform.rotate(
              angle: idle.s * 0.014 - (1 - ring) * 0.5,
              child: const RepaintBoundary(child: CustomPaint(painter: CosmicZodiacRingPainter())),
            ),
          ),
        ),
        Positioned(
          left: _c.dx - _chart / 2,
          top: _c.dy - _chart / 2,
          width: _chart,
          height: _chart,
          child: Transform.scale(
            scale: 0.9 + 0.1 * _seg(t, 0.0, 0.26),
            child: RepaintBoundary(child: CustomPaint(painter: _ChartPainter(t, _fontOf(context)))),
          ),
        ),
        Positioned(left: 30, top: 18, child: _Sparkle(size: 16, v: _seg(t, 0.5, 0.7) * (0.75 + 0.25 * idle.wave(0.1)))),
        Positioned(right: 26, top: 44, child: _Sparkle(size: 11, v: _seg(t, 0.6, 0.8) * (0.7 + 0.3 * idle.wave(0.6)))),
        Positioned(left: 22, top: 300, child: _Sparkle(size: 10, v: _seg(t, 0.7, 0.9) * (0.7 + 0.3 * idle.wave(0.35)))),
        Positioned(
          left: 12,
          top: 40,
          child: _float(
            idle.wave(0) * 3,
            _pop(
              _seg(t, 0.60, 0.78, Curves.easeOutBack),
              _Chip('Lagna · Scorpio', color: accent, blur: true),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 284,
          child: _float(
            idle.wave(0.5) * 3,
            _pop(
              _seg(t, 0.70, 0.88, Curves.easeOutBack),
              const _Chip('Moon · Anuradha', color: Color(0xFFB7C4FF), blur: true),
              alignment: Alignment.centerRight,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 334,
          child: Center(
            child: _rise(
              _seg(t, 0.82, 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xCC14102E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gold1.withValues(alpha: 0.85), width: 1.2),
                  boxShadow: [BoxShadow(color: _gold2.withValues(alpha: 0.35), blurRadius: 16)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded, size: 15, color: _gold1),
                    const SizedBox(width: 7),
                    Flexible(
                      child: _tx('Lahiri · Swiss Ephemeris', 12, w: FontWeight.w700, c: _gold1, ls: 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartPlanet {
  final int house;
  final String label;
  final Color color;
  const _ChartPlanet(this.house, this.label, this.color);
}

/// A glowing North Indian (diamond) chart that draws itself: frame, diagonals
/// and the inner diamond are traced in gold, then sign numbers fade in and the
/// planets pop into their houses as luminous orbs. Sample chart: Scorpio Lagna
/// with the Moon in Anuradha.
class _ChartPainter extends CustomPainter {
  final double t;
  final String? font;
  const _ChartPainter(this.t, this.font);

  static const _ascSign = 8; // Scorpio

  // Planet centre and sign-number centre for houses 1..12 (the same layout
  // the real Kundli chart uses).
  static const List<List<double>> _layout = [
    [0.50, 0.225, 0.50, 0.42],
    [0.25, 0.095, 0.25, 0.205],
    [0.095, 0.25, 0.205, 0.25],
    [0.25, 0.50, 0.42, 0.50],
    [0.095, 0.75, 0.205, 0.75],
    [0.25, 0.905, 0.25, 0.795],
    [0.50, 0.775, 0.50, 0.58],
    [0.75, 0.905, 0.75, 0.795],
    [0.905, 0.75, 0.795, 0.75],
    [0.75, 0.50, 0.58, 0.50],
    [0.905, 0.25, 0.795, 0.25],
    [0.75, 0.095, 0.75, 0.205],
  ];

  static const List<_ChartPlanet> _planets = [
    _ChartPlanet(1, 'As', _gold1),
    _ChartPlanet(1, 'Mo', Color(0xFFDCE4FF)),
    _ChartPlanet(10, 'Su', Color(0xFFFFC44D)),
    _ChartPlanet(10, 'Me', Color(0xFF5EEAD4)),
    _ChartPlanet(4, 'Ma', Color(0xFFFF7A6B)),
    _ChartPlanet(5, 'Ju', Color(0xFFFFE08A)),
    _ChartPlanet(7, 'Sa', Color(0xFF9DB2FF)),
    _ChartPlanet(11, 'Ve', Color(0xFFF9A8D4)),
    _ChartPlanet(3, 'Ra', Color(0xFFC4B5FD)),
    _ChartPlanet(9, 'Ke', Color(0xFFE0A872)),
  ];

  void _partial(Canvas canvas, Path path, double f, Paint paint) {
    if (f <= 0) return;
    if (f >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * f), paint);
    }
  }

  void _orb(Canvas canvas, Offset at, double r, Color color, String label, double v) {
    if (v <= 0) return;
    final a = v.clamp(0.0, 1.0);
    final rr = r * (0.5 + 0.5 * v);
    canvas.drawCircle(
      at,
      rr + 4,
      Paint()
        ..color = color.withValues(alpha: 0.60 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      at,
      rr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: [
            Color.lerp(color, Colors.white, 0.75)!.withValues(alpha: a),
            color.withValues(alpha: a),
            Color.lerp(color, const Color(0xFF1A1440), 0.5)!.withValues(alpha: a),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: at, radius: rr)),
    );
    _paintText(canvas, label, at, r * 0.86, _inkDark.withValues(alpha: a), weight: FontWeight.w900, font: font, scale: 0.6 + 0.4 * v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final frame = RRect.fromRectAndRadius(rect.deflate(1.2), const Radius.circular(18));
    final appear = _seg(t, 0.0, 0.26);

    // Aura and the dark glass plate the chart sits on.
    canvas.drawRRect(
      frame.inflate(4),
      Paint()
        ..color = _gold2.withValues(alpha: 0.42 * appear)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF34277A).withValues(alpha: 0.94 * appear),
            const Color(0xFF150F38).withValues(alpha: 0.96 * appear),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = RadialGradient(
          colors: [_gold1.withValues(alpha: 0.20 * appear), _gold1.withValues(alpha: 0)],
        ).createShader(rect),
    );

    final ghost = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _w(0.07 * appear);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = _gold2.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = onboardingGoldGradient.createShader(rect);

    final border = Path()..addRRect(frame);
    final diagonals = Path()
      ..moveTo(0, 0)
      ..lineTo(w, h)
      ..moveTo(w, 0)
      ..lineTo(0, h);
    final diamond = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w / 2, h)
      ..lineTo(0, h / 2)
      ..close();

    final fDiag = _seg(t, 0.10, 0.40, Curves.easeInOut);
    final fDiamond = _seg(t, 0.22, 0.54, Curves.easeInOut);
    final fBorder = _seg(t, 0.0, 0.32, Curves.easeInOut);
    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawPath(diagonals, ghost);
    canvas.drawPath(diamond, ghost);
    for (final paint in [glow, line]) {
      _partial(canvas, diagonals, fDiag, paint);
      _partial(canvas, diamond, fDiamond, paint);
    }
    canvas.restore();
    _partial(canvas, border, fBorder, glow);
    _partial(canvas, border, fBorder, line..strokeWidth = 2.8);

    final signs = _seg(t, 0.38, 0.56);
    for (var i = 0; i < 12; i++) {
      final cfg = _layout[i];
      _paintText(canvas, '${(_ascSign - 1 + i) % 12 + 1}', Offset(w * cfg[2], h * cfg[3]), 10.5,
          _gold1.withValues(alpha: 0.72 * signs),
          weight: FontWeight.w700, font: font);
    }

    final perHouse = <int, int>{};
    for (final p in _planets) {
      perHouse[p.house] = (perHouse[p.house] ?? 0) + 1;
    }
    final seen = <int, int>{};
    for (var i = 0; i < _planets.length; i++) {
      final p = _planets[i];
      final cfg = _layout[p.house - 1];
      final n = perHouse[p.house]!;
      final k = seen[p.house] ?? 0;
      seen[p.house] = k + 1;
      final dx = n == 1 ? 0.0 : (k - (n - 1) / 2) * 30;
      final start = 0.44 + i * 0.035;
      _orb(canvas, Offset(w * cfg[0] + dx, h * cfg[1]), 12.5, p.color, p.label,
          _seg(t, start, start + 0.14, Curves.easeOutBack));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.t != t || old.font != font;
}

// ============================================================================
// 2. Your day
// ============================================================================

/// The sun's path across the sky behind the day card.
class _SunArcPainter extends CustomPainter {
  final double v;
  final double pulse;
  const _SunArcPainter(this.v, this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, 118);
    const rx = 168.0, ry = 104.0;
    Offset at(double f) {
      final a = math.pi + f * math.pi;
      return c + Offset(math.cos(a) * rx, math.sin(a) * ry);
    }

    final dash = Paint()
      ..color = _w(0.26)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i += 2) {
      canvas.drawLine(at(i / 60), at((i + 0.9) / 60), dash);
    }
    final sunF = 0.06 + 0.56 * v;
    final travelled = Path()..moveTo(at(0.04).dx, at(0.04).dy);
    for (var f = 0.04; f <= sunF; f += 0.01) {
      final p = at(f);
      travelled.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      travelled,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..shader = onboardingGoldGradient.createShader(Offset.zero & size),
    );
    // Sun.
    final sun = at(sunF);
    canvas.drawCircle(
      sun,
      24 + 3 * pulse,
      Paint()
        ..color = _gold2.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final ray = Paint()
      ..color = _gold1.withValues(alpha: 0.8)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + pulse * 0.2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(sun + d * 16, sun + d * 21, ray);
    }
    canvas.drawCircle(
      sun,
      12,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFFFF6D6), _gold1, _gold2],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: sun, radius: 12)),
    );
    // Moon waiting at the end of the day.
    final moon = at(0.79);
    canvas.drawCircle(
      moon,
      11,
      Paint()
        ..color = const Color(0xFFB7C4FF).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: moon, radius: 8)),
      Path()..addOval(Rect.fromCircle(center: moon + const Offset(4.5, -3), radius: 7)),
    );
    canvas.drawPath(crescent, Paint()..color = const Color(0xFFE6EBFF));
  }

  @override
  bool shouldRepaint(_SunArcPainter old) => old.v != v || old.pulse != pulse;
}

class _DayArt extends StatelessWidget {
  final double t;
  final _Idle idle;
  final Color accent;
  const _DayArt({required this.t, required this.idle, required this.accent});

  Widget _row(int i, IconData icon, String label, String text, Color color) {
    final v = _seg(t, 0.42 + i * 0.13, 0.66 + i * 0.13);
    return Positioned(
      left: 20,
      right: 20,
      top: 226.0 + i * 50,
      child: _rise(
        v,
        _Glass(
          radius: 16,
          fill: 0.09,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color.withValues(alpha: 0.20),
                  border: Border.all(color: color.withValues(alpha: 0.55)),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 10)],
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tx(label, 10.5, w: FontWeight.w800, c: color, ls: 0.3),
                    _tx(text, 12.5, w: FontWeight.w600, c: _w(0.94)),
                  ],
                ),
              ),
            ],
          ),
        ),
        dy: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ring = _seg(t, 0.10, 0.62);
    final card = _seg(t, 0.0, 0.26);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: _seg(t, 0.0, 0.2),
            child: CustomPaint(painter: _SunArcPainter(_seg(t, 0.05, 0.6, Curves.easeInOut), idle.wave(0, period: 3))),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 70,
          height: 146,
          child: _rise(
            card,
            _Glass(
              radius: 26,
              blur: true,
              fill: 0.13,
              tint: Color.lerp(accent, Colors.white, 0.5)!,
              glow: accent,
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _tx('TODAY FOR YOU', 10.5, w: FontWeight.w800, c: _gold1, ls: 1.6),
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: _mint.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _mint.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wb_sunny_rounded, size: 11, color: _mint),
                              const SizedBox(width: 5),
                              Flexible(child: _tx('Good day', 10.5, w: FontWeight.w800, c: _mint)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _tx('A bright day for steady progress', 18, w: FontWeight.w800, lines: 2, h: 1.2),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 108,
                    height: 108,
                    child: CustomPaint(
                      painter: _RingPainter(
                        fraction: 0.74 * ring,
                        colors: const [_gold1, _gold2],
                        stroke: 10,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _tx('${(74 * ring).round()}', 36, w: FontWeight.w900, h: 1),
                            const SizedBox(height: 2),
                            _tx('of 100', 10.5, w: FontWeight.w700, c: _w(0.7)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            dy: 20,
          ),
        ),
        _row(0, Icons.sentiment_satisfied_alt_rounded, 'A good day for', 'Important talks · learning · family', _mint),
        _row(1, Icons.warning_amber_rounded, 'Be careful with', 'Rushed spending · late nights', _rose),
        _row(2, Icons.schedule_rounded, 'Best time', '11:40 am – 12:28 pm · lucky window', _sky),
      ],
    );
  }
}

// ============================================================================
// 3. Why things happen
// ============================================================================

enum _PlanetKind { saturn, jupiter, sun }

/// Small painted planets: Saturn with its ring, banded Jupiter, a rayed Sun.
class _PlanetPainter extends CustomPainter {
  final _PlanetKind kind;
  const _PlanetPainter(this.kind);

  void _sphere(Canvas canvas, Offset c, double r, List<Color> colors) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: colors,
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final u = size.shortestSide / 48;
    Paint halo(Color color) => Paint()
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 9 * u);
    switch (kind) {
      case _PlanetKind.saturn:
        canvas.drawCircle(c, 15 * u, halo(const Color(0xFFE8B86B)));
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.38);
        final ringRect = Rect.fromCenter(center: Offset.zero, width: 46 * u, height: 14 * u);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 * u
          ..color = const Color(0xFFF3DDAE);
        canvas.drawArc(ringRect, math.pi, math.pi, false, ring);
        canvas.rotate(0.38);
        _sphere(canvas, Offset.zero, 13 * u, const [Color(0xFFFFF0CC), Color(0xFFE0AE62), Color(0xFF7A5220)]);
        canvas.rotate(-0.38);
        canvas.drawArc(ringRect, 0, math.pi, false, ring);
        canvas.drawArc(
          ringRect.inflate(-3.4 * u),
          0.1,
          math.pi - 0.2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * u
            ..color = const Color(0x99A9783A),
        );
        canvas.restore();
      case _PlanetKind.jupiter:
        final r = 17 * u;
        canvas.drawCircle(c, r, halo(const Color(0xFFF2A65A)));
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
        canvas.drawRect(Rect.fromCircle(center: c, radius: r), Paint()..color = const Color(0xFFF1CFA0));
        const bands = [
          [-0.72, 0.16, 0xFFD9A066],
          [-0.42, 0.20, 0xFFB86F3C],
          [-0.08, 0.14, 0xFFE8B985],
          [0.18, 0.24, 0xFFC2814A],
          [0.56, 0.16, 0xFFDBA570],
          [0.80, 0.20, 0xFFA8643A],
        ];
        for (final b in bands) {
          canvas.drawRect(
            Rect.fromLTWH(c.dx - r, c.dy + r * (b[0] as double), r * 2, r * (b[1] as double)),
            Paint()..color = Color(b[2] as int),
          );
        }
        canvas.drawOval(
          Rect.fromCenter(center: c + Offset(r * 0.32, r * 0.30), width: r * 0.5, height: r * 0.28),
          Paint()..color = const Color(0xFFC2512F),
        );
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.45, -0.55),
              radius: 1.15,
              colors: [_w(0.55), _w(0), const Color(0xB3301505)],
              stops: const [0, 0.42, 1],
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        );
        canvas.restore();
      case _PlanetKind.sun:
        canvas.drawCircle(c, 17 * u, halo(_gold2));
        final ray = Paint()
          ..color = _gold1
          ..strokeWidth = 2 * u
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 10; i++) {
          final a = i * math.pi / 5;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c + d * 16.5 * u, c + d * (i.isEven ? 21.5 : 19.5) * u, ray);
        }
        _sphere(canvas, c, 13.5 * u, const [Color(0xFFFFF8DC), _gold1, _gold2]);
    }
  }

  @override
  bool shouldRepaint(_PlanetPainter old) => old.kind != kind;
}

/// The orbit the three planets sit on, plus two fainter neighbours.
class _OrbitPainter extends CustomPainter {
  final double v;
  const _OrbitPainter(this.v);

  static const centre = Offset(-232.2, 161);
  static const radius = 274.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final spec in const [
      [radius - 30, 0.14, 1.0],
      [radius, 0.55, 1.8],
      [radius + 34, 0.16, 1.0],
    ]) {
      p
        ..strokeWidth = spec[2]
        ..color = _gold1.withValues(alpha: spec[1] * v);
      canvas.drawArc(Rect.fromCircle(center: centre, radius: spec[0]), -0.62, 1.24 * v, false, p);
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.v != v;
}

class _WhyArt extends StatelessWidget {
  final double t;
  final _Idle idle;
  final Color accent;
  const _WhyArt({required this.t, required this.idle, required this.accent});

  static const double _rowH = 70;
  static const double _orb = 58;

  double _cx(int i) => i == 1 ? 54 : 42;
  double _top(int i) => 44.0 + i * 82;

  Widget _row(int i, bool good, String text, String until) {
    final v = _seg(t, 0.12 + i * 0.14, 0.38 + i * 0.14);
    final left = _cx(i) + 2;
    final dot = good ? _mint : _rose;
    return Positioned(
      left: left,
      top: _top(i),
      width: 230 - left,
      height: _rowH,
      child: _float(
        idle.wave(i * 0.33) * 2.5,
        Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(24 * (1 - v), 0),
            child: _Glass(
              radius: 22,
              blur: true,
              fill: 0.11,
              padding: const EdgeInsets.fromLTRB(36, 0, 8, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tx(text, 12.5, w: FontWeight.w700, lines: 2, h: 1.22),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _GlowDot(dot, size: 7, pulse: 0.3 + 0.3 * idle.wave(i * 0.3, period: 2)),
                      const SizedBox(width: 6),
                      Flexible(child: _tx(until, 10.5, w: FontWeight.w600, c: _w(0.7))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The planet itself, sitting on the orbit and overlapping its card.
  Widget _planet(int i, _PlanetKind kind) {
    final v = _seg(t, 0.06 + i * 0.14, 0.30 + i * 0.14, Curves.easeOutBack);
    return Positioned(
      left: _cx(i) - _orb / 2,
      top: _top(i) + _rowH / 2 - _orb / 2 + idle.wave(i * 0.33) * 2.5,
      width: _orb,
      height: _orb,
      child: _pop(v, RepaintBoundary(child: CustomPaint(painter: _PlanetPainter(kind)))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _OrbitPainter(_seg(t, 0.0, 0.4, Curves.easeInOut)))),
        Positioned(
          left: 22,
          top: 14,
          child: _rise(
            _seg(t, 0.0, 0.2),
            _tx('Your planet weather', 14.5, w: FontWeight.w800, ls: 0.1),
            dy: 6,
          ),
        ),
        _row(0, false, 'Saturn is testing your patience at home', 'until Jun 2027'),
        _row(1, true, 'Jupiter is opening doors for learning', 'until May 2027'),
        _row(2, true, 'Sun supports your career', 'until 17 Nov'),
        _planet(0, _PlanetKind.saturn),
        _planet(1, _PlanetKind.jupiter),
        _planet(2, _PlanetKind.sun),
        Positioned(
          left: 20,
          top: 304,
          child: _float(
            idle.wave(0.7) * 2.5,
            _pop(
              _seg(t, 0.80, 0.96, Curves.easeOutBack),
              const _Chip('Why did this happen?', color: _gold1, icon: Icons.history_rounded, edge: _gold1),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        Positioned(
          left: 240,
          top: 12,
          width: 118,
          height: 352,
          child: CustomPaint(painter: _TimelinePainter(t, accent, idle.loop(2.2), idle.e, _fontOf(context))),
        ),
      ],
    );
  }
}

/// Luminous vertical life timeline: the past is a glowing line, the future is
/// dashed, with a pulsing "You are here" beacon.
class _TimelinePainter extends CustomPainter {
  final double t;
  final Color accent;
  final double pulse;
  final double pulseOn;
  final String? font;
  const _TimelinePainter(this.t, this.accent, this.pulse, this.pulseOn, this.font);

  static const _nodes = <List<String>>[
    ['2016', 'Rahu chapter'],
    ['NOW', 'You are here'],
    ['2027', 'Saturn eases'],
    ['2034', 'Jupiter rises'],
  ];
  static const _ys = [0.20, 0.42, 0.68, 0.93];
  static const _nowIndex = 1;

  TextPainter _tp(String text, double size, FontWeight w, Color color, double maxWidth, {double ls = 0}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: font, fontSize: size, height: 1.15, fontWeight: w, color: color, letterSpacing: ls),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const x = 12.0;
    const top = 30.0;
    final bottom = size.height * _ys.last;
    final nowY = size.height * _ys[_nowIndex];
    final light = Color.lerp(accent, Colors.white, 0.45)!;
    final head = _seg(t, 0.0, 0.2);

    final title = _tp('LIFE TIMELINE', 10, FontWeight.w800, _gold1.withValues(alpha: head), size.width, ls: 1.4);
    title.paint(canvas, const Offset(0, 4));
    title.dispose();

    // The future: dashed, not fixed yet.
    final track = Paint()
      ..color = _w(0.30)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = nowY + 12; y < bottom; y += 8) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3.5, bottom)), track);
    }

    // The lived part glows in from the top down to "now".
    final lived = _seg(t, 0.08, 0.52, Curves.easeInOut);
    if (lived > 0) {
      final end = Offset(x, top + (nowY - top) * lived);
      canvas.drawLine(
        const Offset(x, top),
        end,
        Paint()
          ..color = accent.withValues(alpha: 0.8)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawLine(
        const Offset(x, top),
        end,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [light.withValues(alpha: 0.15), light, _gold1],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromLTRB(x - 2, top, x + 2, nowY)),
      );
    }

    final labelWidth = size.width - x - 14;
    for (var i = 0; i < _nodes.length; i++) {
      final y = size.height * _ys[i];
      final isNow = i == _nowIndex;
      final v = _seg(t, 0.10 + i * 0.15, 0.30 + i * 0.15, Curves.easeOutBack);
      final a = v.clamp(0.0, 1.0);
      if (a <= 0) continue;

      if (isNow) {
        final here = _seg(t, 0.46, 0.62);
        // Expanding beacon rings.
        for (final phase in [0.0, 0.5]) {
          final p = (pulse + phase) % 1.0;
          canvas.drawCircle(
            Offset(x, y),
            9 + 15 * p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = _gold1.withValues(alpha: 0.55 * (1 - p) * pulseOn * here),
          );
        }
        canvas.drawCircle(
          Offset(x, y),
          15,
          Paint()
            ..color = _gold2.withValues(alpha: 0.75 * here)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawCircle(Offset(x, y), 8.5 * (0.6 + 0.4 * v), Paint()..color = Colors.white.withValues(alpha: a));
        canvas.drawCircle(
          Offset(x, y),
          5.5 * (0.6 + 0.4 * v),
          Paint()
            ..shader = onboardingGoldGradient.createShader(Rect.fromCircle(center: Offset(x, y), radius: 5.5)),
        );

        final label = _tp(_nodes[i][1], 11, FontWeight.w800, _inkDark.withValues(alpha: a), labelWidth - 14);
        final pill = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 15, y - label.height / 2 - 6, label.width + 16, label.height + 12),
          const Radius.circular(13),
        );
        canvas.drawRRect(
          pill,
          Paint()
            ..color = _gold2.withValues(alpha: 0.5 * a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        canvas.drawRRect(
          pill,
          Paint()
            ..shader = LinearGradient(
              colors: [_gold1.withValues(alpha: a), _gold2.withValues(alpha: a)],
            ).createShader(pill.outerRect),
        );
        label.paint(canvas, Offset(x + 23, y - label.height / 2));
        label.dispose();
        continue;
      }

      final past = i < _nowIndex;
      final r = 5.5 * (0.6 + 0.4 * v);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = const Color(0xFF1A1440).withValues(alpha: a));
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = (past ? light : Colors.white).withValues(alpha: (past ? 1.0 : 0.7) * a),
      );
      final year = _tp(_nodes[i][0], 10, FontWeight.w800, _w(0.62 * a), labelWidth, ls: 0.6);
      final text = _tp(_nodes[i][1], 12, FontWeight.w700, _w(0.95 * a), labelWidth);
      final block = year.height + text.height + 1;
      year.paint(canvas, Offset(x + 16, y - block / 2));
      text.paint(canvas, Offset(x + 16, y - block / 2 + year.height + 1));
      year.dispose();
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.t != t || old.accent != accent || old.pulse != pulse || old.pulseOn != pulseOn || old.font != font;
}

// ============================================================================
// 4. Cosmic games
// ============================================================================

class _GamesArt extends StatelessWidget {
  final double t;
  final _Idle idle;
  final Color accent;
  const _GamesArt({required this.t, required this.idle, required this.accent});

  static const double _board = 208;
  static const double _cell = _board / 4;

  /// Centre of square 1..16 on the 4x4 corner of the board (row 0 at the
  /// bottom, numbering snakes back and forth like the real board).
  static Offset _centre(int square) {
    final i = square - 1;
    final row = i ~/ 4;
    final inRow = i % 4;
    final col = row.isEven ? inRow : 3 - inRow;
    return Offset((col + 0.5) * _cell, (3 - row + 0.5) * _cell);
  }

  Offset _tokenAt() {
    final hop = _seg(t, 0.66, 0.82, Curves.linear) * 2; // 1 -> 2 -> 3
    final climb = _seg(t, 0.84, 0.97, Curves.easeInOut); // ladder 3 -> 10
    if (climb > 0) return Offset.lerp(_centre(3), _centre(10), climb)!;
    final from = hop < 1 ? 1 : 2;
    final f = hop < 1 ? hop : hop - 1;
    final base = Offset.lerp(_centre(from), _centre(from + 1), hop >= 2 ? 1 : f)!;
    return base - Offset(0, math.sin((hop >= 2 ? 1 : f) * math.pi) * _cell * 0.32);
  }

  Widget _starCard() {
    final flip = _seg(t, 0.30, 0.70, Curves.easeInOutCubic);
    final angle = math.pi + (0.26 - math.pi) * flip + idle.wave(0.2, period: 5) * 0.06;
    final front = angle < math.pi / 2;
    // Foil shine: once after the flip, then every few seconds while idle.
    final enterSweep = _seg(t, 0.70, 0.92, Curves.easeInOut);
    final idleSweep = idle.e > 0 ? (idle.loop(4.5) / 0.28).clamp(0.0, 1.0) : 0.0;
    final sweep = enterSweep > 0 && enterSweep < 1 ? enterSweep : idleSweep;
    const radius = BorderRadius.all(Radius.circular(16));
    final face = front
        ? ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4B2FBF), Color(0xFF8B3FE0), Color(0xFFE8559A), Color(0xFFFFA24D)],
                      stops: [0, 0.4, 0.78, 1],
                    ),
                  ),
                ),
                const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _CardPatternPainter()))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _tx('14', 11, w: FontWeight.w900, c: _gold1),
                          const Spacer(),
                          const Icon(Icons.auto_awesome, size: 11, color: _gold1),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(
                        width: 62,
                        height: 56,
                        child: RepaintBoundary(child: CustomPaint(painter: _GemPainter())),
                      ),
                      const Spacer(),
                      _tx('Chitra', 19, w: FontWeight.w900, h: 1.1, ls: 0.2),
                      const SizedBox(height: 3),
                      _tx('Star card 14 of 27', 9.5, w: FontWeight.w700, c: _w(0.85)),
                    ],
                  ),
                ),
                // Static gloss.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_w(0.30), _w(0.0), _w(0.0)],
                      stops: const [0, 0.38, 1],
                    ),
                  ),
                ),
                if (sweep > 0 && sweep < 1)
                  FractionalTranslation(
                    translation: Offset(-1.2 + 2.4 * sweep, 0),
                    child: Transform.rotate(
                      angle: 0.35,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_w(0), _w(0.55), _w(0)],
                            stops: const [0.3, 0.5, 0.7],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF241A5C), Color(0xFF4A2F99)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: radius,
            ),
            child: Center(child: Icon(Icons.auto_awesome, color: _gold1, size: 40)),
          );
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0014)
        ..rotateZ(-0.10)
        ..rotateY(angle),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            const BoxShadow(color: Color(0x99050314), blurRadius: 22, offset: Offset(0, 14)),
            BoxShadow(color: const Color(0xFFE8559A).withValues(alpha: 0.45), blurRadius: 26),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: _gold1, width: 2.2),
        ),
        child: face,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tick = _seg(t, 0.16, 0.32, Curves.easeOutBack);
    final ticked = tick.clamp(0.0, 1.0);
    final xp = _seg(t, 0.26, 0.48, Curves.easeOutBack);
    final burst = math.sin(_seg(t, 0.26, 0.56, Curves.linear) * math.pi);
    final dice = _seg(t, 0.46, 0.66);
    final token = _tokenAt();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Corner of the Moksha Patam board.
        Positioned(
          right: 14,
          top: 134,
          width: _board,
          height: _board,
          child: _rise(
            _seg(t, 0.0, 0.24),
            Transform.rotate(
              angle: 0.035,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _MiniBoardPainter(_fontOf(context))))),
                  Positioned(
                    left: token.dx - 15,
                    top: token.dy - 15 - idle.wave(0.4, period: 2).abs() * 3,
                    child: _Orb(
                      size: 30,
                      color: const Color(0xFF7C6CFF),
                      glow: 0.9,
                      child: _tx('Y', 13, w: FontWeight.w900, h: 1),
                    ),
                  ),
                ],
              ),
            ),
            dy: 22,
          ),
        ),
        // Nakshatra star card.
        Positioned(
          left: 18,
          top: 112,
          width: 132,
          height: 178,
          child: _float(idle.wave(0.25) * 3, _rise(_seg(t, 0.06, 0.3), _starCard(), dy: 22)),
        ),
        // Dice.
        Positioned(
          left: 104,
          top: 292,
          width: 58,
          height: 62,
          child: _pop(
            _seg(t, 0.44, 0.58, Curves.easeOutBack),
            Transform.rotate(
              angle: 0.16 + (1 - dice) * math.pi * 2,
              child: const RepaintBoundary(child: CustomPaint(painter: _DicePainter())),
            ),
          ),
        ),
        // Mission card being ticked.
        Positioned(
          left: 18,
          top: 26,
          width: 238,
          child: _rise(
            _seg(t, 0.0, 0.22),
            _Glass(
              radius: 20,
              blur: true,
              fill: 0.12,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(_w(0.08), const Color(0xFF6EE7A0), ticked)!,
                          Color.lerp(_w(0.08), const Color(0xFF16A34A), ticked)!,
                        ],
                      ),
                      border: Border.all(color: Color.lerp(_w(0.45), _w(0.9), ticked)!, width: 1.6),
                      boxShadow: [BoxShadow(color: _mint.withValues(alpha: 0.6 * ticked), blurRadius: 14)],
                    ),
                    child: Transform.scale(
                      scale: tick,
                      child: const Icon(Icons.check_rounded, size: 22, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tx('Call someone you love', 13.5, w: FontWeight.w800),
                        const SizedBox(height: 2),
                        _tx('Moon mission · 2 of 3 today', 11, w: FontWeight.w600, c: _w(0.68)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            dy: 16,
          ),
        ),
        // "+30 XP" bursts out of the tick and settles on the card's corner.
        Positioned(
          left: 172,
          top: 40 - 32 * xp.clamp(0.0, 1.2),
          child: Opacity(
            opacity: xp.clamp(0.0, 1.0),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: -16,
                  right: -16,
                  top: -16,
                  bottom: -16,
                  child: CustomPaint(painter: _BurstPainter(burst)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: onboardingGoldGradient,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFF1CC), width: 1),
                    boxShadow: [
                      BoxShadow(color: _gold2.withValues(alpha: 0.7), blurRadius: 16, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: _tx('+30 XP', 13, w: FontWeight.w900, c: const Color(0xFF3A1C02)),
                ),
              ],
            ),
          ),
        ),
        // Streak flame.
        Positioned(
          right: 14,
          top: 36,
          child: _pop(
            _seg(t, 0.10, 0.28, Curves.easeOutBack),
            _Glass(
              radius: 19,
              fill: 0.14,
              padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 1 +
                        0.3 * math.sin(_seg(t, 0.30, 0.60, Curves.linear) * math.pi) +
                        0.08 * idle.wave(0, period: 1.4),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFFFF6A00).withValues(alpha: 0.8), blurRadius: 12)],
                      ),
                      child: const Icon(Icons.local_fire_department_rounded, size: 18, color: Color(0xFFFFA63D)),
                    ),
                  ),
                  const SizedBox(width: 5),
                  _tx('7 days', 12.5, w: FontWeight.w800),
                ],
              ),
            ),
            alignment: Alignment.centerRight,
          ),
        ),
        Positioned(left: 152, top: 100, child: _Sparkle(size: 12, v: _seg(t, 0.7, 0.9) * (0.7 + 0.3 * idle.wave(0.3)))),
        Positioned(left: 30, top: 306, child: _Sparkle(size: 14, v: _seg(t, 0.6, 0.8) * (0.7 + 0.3 * idle.wave(0.8)))),
      ],
    );
  }
}

/// Short gold rays that flash around the XP badge.
class _BurstPainter extends CustomPainter {
  final double v;
  const _BurstPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0.01) return;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = _gold1.withValues(alpha: v.clamp(0.0, 1.0))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5 + 0.2;
      final d = Offset(math.cos(a) * 1.5, math.sin(a));
      canvas.drawLine(c + d * (22 + 6 * v), c + d * (27 + 12 * v), p);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.v != v;
}

/// Faint star pattern printed on the nakshatra card.
class _CardPatternPainter extends CustomPainter {
  const _CardPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.42);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _w(0.20);
    canvas.drawCircle(c, 40, p);
    canvas.drawCircle(c, 50, p..color = _w(0.10));
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * 42, c + d * (i.isEven ? 49 : 46), p..color = _w(0.22));
    }
    canvas.drawCircle(
      c,
      30,
      Paint()
        ..color = const Color(0xFFBDEBFF).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  @override
  bool shouldRepaint(_CardPatternPainter old) => false;
}

/// A faceted gem (Chitra means "the bright jewel").
class _GemPainter extends CustomPainter {
  const _GemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);
    final tl = p(0.22, 0.04), tr = p(0.78, 0.04), l = p(0.0, 0.36), r = p(1.0, 0.36), b = p(0.5, 1.0);
    final ml = p(0.30, 0.36), mr = p(0.70, 0.36), tm = p(0.5, 0.04);
    void tri(Offset a, Offset b2, Offset c, Color color) {
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b2.dx, b2.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        Paint()..color = color,
      );
    }

    // Crown.
    tri(tl, l, ml, const Color(0xFF9BE4FF));
    tri(tl, tm, ml, const Color(0xFFE9FAFF));
    tri(tm, ml, mr, const Color(0xFFBFF0FF));
    tri(tm, tr, mr, const Color(0xFFFFFFFF));
    tri(tr, r, mr, const Color(0xFF7FD4FF));
    // Pavilion.
    tri(l, ml, b, const Color(0xFF5BB8F5));
    tri(ml, mr, b, const Color(0xFF8FDBFF));
    tri(mr, r, b, const Color(0xFF3D8FE0));
    final outline = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(r.dx, r.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(l.dx, l.dy)
      ..close();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.drawLine(l, r, Paint()..color = _w(0.8));
  }

  @override
  bool shouldRepaint(_GemPainter old) => false;
}

/// A chunky ivory dice showing five, with a visible side for depth.
class _DicePainter extends CustomPainter {
  const _DicePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width - 6;
    final top = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.24));
    canvas.drawRRect(
      top.shift(const Offset(6, 12)),
      Paint()
        ..color = const Color(0xB3050314)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawRRect(top.shift(const Offset(4, 7)), Paint()..color = const Color(0xFFB98A4A));
    canvas.drawRRect(top.shift(const Offset(2, 3.5)), Paint()..color = const Color(0xFFDDB877));
    canvas.drawRRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFFFF3D6), Color(0xFFF6D9A0)],
        ).createShader(top.outerRect),
    );
    canvas.drawRRect(
      top.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _w(0.9),
    );
    final pip = Paint()..color = MokshaColors.maroon;
    final shine = Paint()..color = _w(0.55);
    for (final o in const [Offset(0.27, 0.27), Offset(0.73, 0.27), Offset(0.5, 0.5), Offset(0.27, 0.73), Offset(0.73, 0.73)]) {
      final c = Offset(o.dx * s, o.dy * s);
      canvas.drawCircle(c, s * 0.085, pip);
      canvas.drawCircle(c - Offset(s * 0.025, s * 0.03), s * 0.025, shine);
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) => false;
}

/// A 4x4 corner of the Moksha Patam board with a golden ladder and a snake,
/// in the warm traditional colours of the real game board.
class _MiniBoardPainter extends CustomPainter {
  final String? font;
  const _MiniBoardPainter(this.font);

  static const _ladderFrom = 3, _ladderTo = 10, _snakeFrom = 13, _snakeTo = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cell = s / 4;
    Offset centre(int sq) => _GamesArt._centre(sq) * (cell / _GamesArt._cell);
    final board = RRect.fromRectAndRadius(Offset.zero & Size(s, s), Radius.circular(cell * 0.34));

    canvas.drawRRect(
      board.shift(const Offset(0, 14)),
      Paint()
        ..color = const Color(0xB3050314)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawRRect(
      board.inflate(2),
      Paint()
        ..color = MokshaColors.gold.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.save();
    canvas.clipRRect(board);
    for (var sq = 1; sq <= 16; sq++) {
      final c = centre(sq);
      final rect = Rect.fromCenter(center: c, width: cell, height: cell);
      final col = (c.dx / cell).floor(), row = (c.dy / cell).floor();
      var fill = (col + row).isEven ? MokshaColors.cream : MokshaColors.sand;
      if (sq == _ladderFrom) fill = MokshaColors.ladderTint;
      if (sq == _snakeFrom) fill = MokshaColors.snakeTint;
      canvas.drawRect(rect, Paint()..color = fill);
      final tp = TextPainter(
        text: TextSpan(
          text: '$sq',
          style: TextStyle(
            fontFamily: font,
            fontSize: cell * 0.24,
            height: 1,
            fontWeight: FontWeight.w800,
            color: MokshaColors.ink.withValues(alpha: 0.62),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, rect.topLeft + Offset(cell * 0.12, cell * 0.10));
      tp.dispose();
    }
    final grid = Paint()
      ..color = MokshaColors.maroon.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, s), grid);
      canvas.drawLine(Offset(0, i * cell), Offset(s, i * cell), grid);
    }

    // Golden ladder.
    final a = centre(_ladderFrom), b = centre(_ladderTo);
    final dir = (b - a) / (b - a).distance;
    final n = Offset(-dir.dy, dir.dx) * (cell * 0.17);
    final start = a + dir * (cell * 0.1), end = b - dir * (cell * 0.1);
    final rungs = math.max(2, ((end - start).distance / (cell * 0.34)).floor());
    for (final paint in [
      Paint()
        ..color = MokshaColors.goldDeep
        ..strokeWidth = cell * 0.13
        ..strokeCap = StrokeCap.round,
      Paint()
        ..color = MokshaColors.gold
        ..strokeWidth = cell * 0.075
        ..strokeCap = StrokeCap.round,
      Paint()
        ..color = const Color(0xFFFFF0B3)
        ..strokeWidth = cell * 0.022
        ..strokeCap = StrokeCap.round,
    ]) {
      canvas.drawLine(start + n, end + n, paint);
      canvas.drawLine(start - n, end - n, paint);
      for (var i = 1; i < rungs; i++) {
        final p = Offset.lerp(start, end, i / rungs)!;
        canvas.drawLine(p + n, p - n, paint);
      }
    }

    // Snake: a tapering wavy body from head to tail, with a spotted back.
    const colour = Color(0xFF1FA971);
    final head = centre(_snakeFrom), tail = centre(_snakeTo);
    final sd = (tail - head) / (tail - head).distance;
    final sn = Offset(-sd.dy, sd.dx);
    const steps = 40;
    final pts = [
      for (var i = 0; i <= steps; i++)
        Offset.lerp(head, tail, i / steps)! +
            sn * (math.sin(i / steps * math.pi * 2.5) * cell * 0.26 * math.sin(i / steps * math.pi)),
    ];
    final dark = Color.lerp(colour, Colors.black, 0.4)!;
    final width = cell * 0.26;
    for (final pass in [0, 1]) {
      final paint = Paint()
        ..color = pass == 0 ? dark : colour
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < steps; i++) {
        final w = width * (1 - 0.66 * i / steps);
        paint.strokeWidth = pass == 0 ? w + 2.2 : w;
        canvas.drawLine(pts[i], pts[i + 1], paint);
      }
    }
    final spot = Paint()..color = const Color(0xFFFDE68A);
    for (var i = 4; i < steps - 3; i += 4) {
      canvas.drawCircle(pts[i], width * (1 - 0.66 * i / steps) * 0.22, spot);
    }
    final look = pts[0] - pts[2];
    final ld = look / look.distance;
    final side = Offset(-ld.dy, ld.dx);
    final r = width * 0.82;
    final tongue = Paint()
      ..color = const Color(0xFFE11D48)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final tip = head + ld * (r + cell * 0.18);
    canvas.drawLine(head + ld * r * 0.8, tip, tongue);
    canvas.drawLine(tip, tip + (ld + side) * (cell * 0.07), tongue);
    canvas.drawLine(tip, tip + (ld - side) * (cell * 0.07), tongue);
    canvas.drawCircle(head, r + 1.1, Paint()..color = dark);
    canvas.drawCircle(head, r, Paint()..color = colour);
    for (final sign in [-1.0, 1.0]) {
      final eye = head + ld * (r * 0.25) + side * (r * 0.48 * sign);
      canvas.drawCircle(eye, r * 0.3, Paint()..color = Colors.white);
      canvas.drawCircle(eye + ld * (r * 0.08), r * 0.15, Paint()..color = Colors.black);
    }
    canvas.restore();

    canvas.drawRRect(
      board.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = MokshaColors.maroon,
    );
    canvas.drawRRect(
      board.deflate(4.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = MokshaColors.gold,
    );
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) => old.font != font;
}

// ============================================================================
// 5. People you love
// ============================================================================

class _PeopleArt extends StatelessWidget {
  final double t;
  final _Idle idle;
  final Color accent;
  const _PeopleArt({required this.t, required this.idle, required this.accent});

  static const Offset _c = Offset(_artW / 2, 150);
  static const Offset _you = Offset(50, 62);
  static const Offset _partner = Offset(310, 62);
  static const double _orbit = 114;

  Widget _person(Offset at, String initial, String name, Color color, double v, double bob) {
    return Positioned(
      left: at.dx - 40,
      top: at.dy - 34 + bob,
      width: 80,
      child: _pop(
        v,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Orb(size: 66, color: color, glow: 0.7, child: _tx(initial, 26, w: FontWeight.w900, h: 1)),
            const SizedBox(height: 6),
            _tx(name, 12, w: FontWeight.w700, c: _w(0.9)),
          ],
        ),
      ),
    );
  }

  Widget _friend(double angle, String initial, Color color, double v) {
    final a = angle + idle.s * 0.018;
    final at = _c + Offset(math.cos(a), math.sin(a)) * _orbit;
    return Positioned(
      left: at.dx - 14,
      top: at.dy - 14,
      child: _pop(v, _Orb(size: 28, color: color, glow: 0.6, child: _tx(initial, 11.5, w: FontWeight.w900, h: 1))),
    );
  }

  Widget _podium(int place, String name, double height, List<Color> colors, double v) {
    return SizedBox(
      width: 46,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pop(
            v,
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                border: Border.all(color: _w(0.8), width: 1),
                boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.7), blurRadius: 10)],
              ),
              child: _tx('$place', 11.5, w: FontWeight.w900, c: _inkDark, h: 1),
            ),
          ),
          const SizedBox(height: 2),
          _tx(name, 10.5, w: FontWeight.w700, h: 1.2),
          const SizedBox(height: 3),
          Container(
            width: 36,
            height: 3 + height * v.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.first, colors.last.withValues(alpha: 0.35)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _seg(t, 0.18, 0.68);
    final link = _seg(t, 0.04, 0.34, Curves.easeInOut);
    final disc = _seg(t, 0.0, 0.24);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _ConstellationPainter(link, accent))),
        _friend(-1.57, 'M', const Color(0xFF8B7CFF), _seg(t, 0.40, 0.56, Curves.easeOutBack)),
        _friend(0.10, 'R', const Color(0xFF4FD1C5), _seg(t, 0.48, 0.64, Curves.easeOutBack)),
        _friend(2.95, 'D', const Color(0xFFFFB454), _seg(t, 0.56, 0.72, Curves.easeOutBack)),
        _person(_you, 'Y', 'You', _gold2, _seg(t, 0.0, 0.2, Curves.easeOutBack), idle.wave(0) * 3),
        _person(_partner, 'A', 'Aarav', const Color(0xFF8B7CFF), _seg(t, 0.06, 0.26, Curves.easeOutBack),
            idle.wave(0.5) * 3),
        // The compatibility ring.
        Positioned(
          left: _c.dx - 86,
          top: _c.dy - 86,
          width: 172,
          height: 172,
          child: Transform.scale(
            scale: 0.85 + 0.15 * disc,
            child: Opacity(
              opacity: disc,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [const Color(0xFF3A1F5E).withValues(alpha: 0.96), const Color(0xFF160F36).withValues(alpha: 0.96)],
                  ),
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 44, spreadRadius: 2),
                    const BoxShadow(color: Color(0x80050314), blurRadius: 20, offset: Offset(0, 12)),
                  ],
                ),
                padding: const EdgeInsets.all(9),
                child: CustomPaint(
                  painter: _RingPainter(
                    fraction: 31 / 36 * count,
                    colors: [_gold1, accent],
                    stroke: 13,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _tx('${(31 * count).round()}', 56, w: FontWeight.w900, h: 1),
                        const SizedBox(height: 2),
                        _tx('of 36', 13, w: FontWeight.w700, c: _w(0.72)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 224,
          child: Center(
            child: _pop(
              _seg(t, 0.64, 0.82, Curves.easeOutBack),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color.lerp(accent, Colors.white, 0.25)!, const Color(0xFFDB2777)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _w(0.55)),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 18, offset: const Offset(0, 5))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 1 + 0.14 * idle.wave(0, period: 1.2),
                      child: const Icon(Icons.favorite_rounded, size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    _tx('Soul-level match', 13, w: FontWeight.w800),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Luckiest today podium (Cosmic Circle).
        Positioned(
          left: 20,
          right: 20,
          top: 276,
          height: 92,
          child: _rise(
            _seg(t, 0.46, 0.7),
            _Glass(
              radius: 22,
              blur: true,
              fill: 0.11,
              padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tx('Luckiest today', 15, w: FontWeight.w800),
                        _tx('Your Cosmic Circle', 11, w: FontWeight.w600, c: _w(0.66)),
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B7CFF).withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFB7ADFF).withValues(alpha: 0.6)),
                          ),
                          child: _tx('Cosmic twin · Meera', 10.5, w: FontWeight.w800, c: const Color(0xFFD9D4FF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _podium(2, 'Riya', 18, const [Color(0xFFF1F5F9), Color(0xFF94A3B8)],
                      _seg(t, 0.66, 0.84, Curves.easeOutBack)),
                  _podium(1, 'You', 32, const [_gold1, _gold2], _seg(t, 0.74, 0.94, Curves.easeOutBack)),
                  _podium(3, 'Dev', 10, const [Color(0xFFF2C29B), Color(0xFFB8733F)],
                      _seg(t, 0.58, 0.76, Curves.easeOutBack)),
                ],
              ),
            ),
            dy: 20,
          ),
        ),
      ],
    );
  }
}

/// The friends' orbit and the constellation lines joining the two people to
/// the ring.
class _ConstellationPainter extends CustomPainter {
  final double v;
  final Color accent;
  const _ConstellationPainter(this.v, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0) return;
    const c = _PeopleArt._c;
    // Dashed orbit.
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = _w(0.26 * v);
    final rect = Rect.fromCircle(center: c, radius: _PeopleArt._orbit);
    for (var i = 0; i < 60; i++) {
      canvas.drawArc(rect, i * math.pi / 30, math.pi / 60, false, orbit);
    }
    final glow = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final line = Paint()
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final star = Paint()..color = Colors.white;
    for (final from in const [_PeopleArt._you, _PeopleArt._partner]) {
      final sign = from.dx < c.dx ? -1.0 : 1.0;
      // A small bent path through two star nodes, like a constellation.
      final pts = [
        from + Offset(-sign * 26, 22),
        Offset(c.dx + sign * 112, c.dy - 30),
        Offset(c.dx + sign * 85, c.dy - 16),
      ];
      line.shader = LinearGradient(colors: sign < 0 ? [_gold1, accent] : [accent, const Color(0xFFB7ADFF)])
          .createShader(Rect.fromPoints(pts.first, pts.last));
      final total = (pts[1] - pts[0]).distance + (pts[2] - pts[1]).distance;
      var left = total * v;
      for (var i = 0; i < pts.length - 1; i++) {
        final len = (pts[i + 1] - pts[i]).distance;
        final f = (left / len).clamp(0.0, 1.0);
        if (f <= 0) break;
        final end = Offset.lerp(pts[i], pts[i + 1], f)!;
        canvas.drawLine(pts[i], end, glow);
        canvas.drawLine(pts[i], end, line);
        left -= len;
        if (f >= 1) {
          canvas.drawCircle(pts[i + 1], 5.5, Paint()..color = _w(0.25));
          canvas.drawCircle(pts[i + 1], 2.8, star);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) => old.v != v || old.accent != accent;
}

// ============================================================================
// 6. Ask anytime
// ============================================================================

class _AskArt extends StatelessWidget {
  final double t;
  final _Idle idle;
  final Color accent;
  const _AskArt({required this.t, required this.idle, required this.accent});

  static const _bubbleIn = BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
    bottomRight: Radius.circular(20),
    bottomLeft: Radius.circular(6),
  );

  Widget _dots(double Function(int i) lift) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
            child: Transform.translate(
              offset: Offset(0, -4 * lift(i)),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color.lerp(accent, Colors.white, 0.35 + 0.4 * lift(i)),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.7), blurRadius: 6)],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _typingBubble(Widget dots) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: _w(0.12),
        borderRadius: _bubbleIn,
        border: Border.all(color: _w(0.22)),
      ),
      child: dots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = _seg(t, 0.80, 0.96, Curves.easeOutBack);
    final firstTyping = _seg(t, 0.24, 0.31) * (1 - _seg(t, 0.54, 0.60));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Chat header.
        Positioned(
          left: 18,
          right: 18,
          top: 22,
          height: 68,
          child: _rise(
            _seg(t, 0.0, 0.2),
            _Glass(
              radius: 24,
              blur: true,
              fill: 0.12,
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4B2FBF), Color(0xFF1A1440)],
                      ),
                      border: Border.all(color: _gold1, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: _gold2.withValues(alpha: 0.55 + 0.2 * idle.wave(0, period: 2.4)),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome, size: 22, color: _gold1),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tx('AI Astrologer', 15, w: FontWeight.w800),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 12, color: accent),
                            const SizedBox(width: 4),
                            Flexible(child: _tx('Knows your chart', 11.5, w: FontWeight.w600, c: _w(0.74))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _pop(
                    online,
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _mint.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _mint.withValues(alpha: 0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GlowDot(_mint, size: 7, pulse: 0.4 + 0.5 * idle.wave(0, period: 1.6)),
                          const SizedBox(width: 6),
                          _tx('Pandit online', 11, w: FontWeight.w800, c: const Color(0xFFB9F6CF)),
                        ],
                      ),
                    ),
                    alignment: Alignment.centerRight,
                  ),
                ],
              ),
            ),
            dy: 14,
          ),
        ),
        // The question.
        Positioned(
          right: 18,
          top: 108,
          child: _pop(
            _seg(t, 0.06, 0.22, Curves.easeOutBack),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(accent, Colors.white, 0.45)!, accent, Color.lerp(accent, const Color(0xFF0B5E46), 0.45)!],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: _tx('How will my week go?', 14.5, w: FontWeight.w700, c: const Color(0xFF052E22)),
            ),
            alignment: Alignment.bottomRight,
          ),
        ),
        // Typing, before the answer arrives.
        Positioned(
          left: 18,
          top: 166,
          child: Opacity(
            opacity: firstTyping.clamp(0.0, 1.0),
            child: _typingBubble(_dots((i) => math.max(0, math.sin(t * 46 - i * 0.9)))),
          ),
        ),
        // The astrologer's reply.
        Positioned(
          left: 18,
          top: 164,
          width: 286,
          child: _float(
            idle.wave(0.3) * 2,
            _rise(
              _seg(t, 0.58, 0.78),
              ClipRRect(
                borderRadius: _bubbleIn,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_w(0.20), _w(0.09)],
                      ),
                      borderRadius: _bubbleIn,
                      border: Border.all(color: _w(0.26)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          const TextSpan(
                            children: [
                              TextSpan(text: 'A steady, social week. Your '),
                              TextSpan(
                                text: 'Rahu–Venus dasha',
                                style: TextStyle(fontWeight: FontWeight.w800, color: _gold1),
                              ),
                              TextSpan(text: ' favours new connections. Thursday looks best.'),
                            ],
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, height: 1.42, fontWeight: FontWeight.w500, color: _w(0.96)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 11, color: _gold1),
                            const SizedBox(width: 5),
                            Flexible(
                              child: _tx('From your chart and today\'s planets', 10.5, w: FontWeight.w600, c: _w(0.66)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Still typing: more is on its way.
        Positioned(
          left: 18,
          top: 280,
          child: _pop(
            _seg(t, 0.84, 0.98, Curves.easeOutBack),
            _typingBubble(_dots((i) => math.max(0.0, idle.wave(-i * 0.16, period: 1.1)))),
            alignment: Alignment.bottomLeft,
          ),
        ),
        // Message box.
        Positioned(
          left: 18,
          right: 18,
          top: 326,
          child: _rise(
            _seg(t, 0.10, 0.3),
            Container(
              height: 48,
              padding: const EdgeInsets.only(left: 18, right: 6),
              decoration: BoxDecoration(
                color: _w(0.08),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _w(0.20)),
              ),
              child: Row(
                children: [
                  Expanded(child: _tx('Ask anything…', 13.5, w: FontWeight.w500, c: _w(0.62))),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: onboardingGoldGradient,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _gold2.withValues(alpha: 0.6), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, size: 20, color: Color(0xFF2B1403)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
