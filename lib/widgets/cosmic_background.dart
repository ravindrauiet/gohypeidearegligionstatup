import 'dart:math' as math;

import 'package:flutter/material.dart';

// ============================================================================
// The shared "night sky" visual language used by onboarding and sign-in: the
// animated background, the brand mark, the zodiac ring, the gold primary
// button, the glass secondary button and dark form fields. Everything is
// drawn in code.
// ============================================================================

/// Gold used for highlights.
const Color cosmicGoldLight = Color(0xFFFFD98A);
const Color cosmicGoldDeep = Color(0xFFFB9548);
const LinearGradient cosmicGoldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [cosmicGoldLight, cosmicGoldDeep],
);

/// The darkest sky colour (bottom of the screen).
const Color cosmicNight = Color(0xFF0A0818);

/// How long the gentle idle motion keeps running after a slide appears. It is
/// bounded on purpose: nothing keeps the device awake if the user walks away.
const Duration cosmicIdleDuration = Duration(seconds: 14);

// ----------------------------------------------------------------------------
// Sky
// ----------------------------------------------------------------------------

/// Full-screen night sky: a deep indigo gradient, soft glows tinted with
/// [accent], faint orbit rings and a deterministic star field of which a few
/// stars twinkle for a while each time [epoch] changes.
class CosmicBackground extends StatefulWidget {
  final Color accent;
  final int epoch;
  const CosmicBackground({super.key, required this.accent, required this.epoch});

  @override
  State<CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<CosmicBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: cosmicIdleDuration);
  bool? _reduce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce == _reduce) return;
    _reduce = reduce;
    if (reduce) {
      _c.stop();
      _c.value = 0;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(CosmicBackground old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch && _reduce != true) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _SkyPainter(widget.accent)),
        const RepaintBoundary(child: CustomPaint(painter: _StarPainter())),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(painter: _TwinklePainter(_c.value)),
          ),
        ),
      ],
    );
  }
}

class _SkyPainter extends CustomPainter {
  final Color accent;
  const _SkyPainter(this.accent);

  void _glow(Canvas canvas, Offset c, double r, Color color, double alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.45),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF211858), Color(0xFF1A1440), Color(0xFF100C2A), cosmicNight],
          stops: [0, 0.30, 0.60, 1],
        ).createShader(rect),
    );
    final w = size.width, h = size.height;
    final unit = math.min(w, h * 0.7);
    const violet = Color(0xFF6C4DF2);
    _glow(canvas, Offset(w * 0.5, h * 0.27), unit * 0.95, accent, 0.30);
    _glow(canvas, Offset(w * 0.95, h * 0.04), unit * 0.85, Color.lerp(accent, violet, 0.35)!, 0.34);
    _glow(canvas, Offset(w * 0.02, h * 0.46), unit * 0.75, Color.lerp(accent, violet, 0.7)!, 0.26);

    // Faint concentric orbits around the hero.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final centre = Offset(w * 0.5, h * 0.29);
    for (var i = 0; i < 3; i++) {
      ring.color = Colors.white.withValues(alpha: 0.055 - i * 0.012);
      canvas.drawCircle(centre, unit * (0.62 + i * 0.26), ring);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.accent != accent;
}

class _Star {
  final double x, y, r, a;
  const _Star(this.x, this.y, this.r, this.a);
}

final List<_Star> _stars = () {
  final rnd = math.Random(20240611);
  return [
    for (var i = 0; i < 90; i++)
      _Star(
        rnd.nextDouble(),
        math.pow(rnd.nextDouble(), 1.4).toDouble() * 0.62,
        0.45 + math.pow(rnd.nextDouble(), 3).toDouble() * 1.35,
        0.16 + rnd.nextDouble() * 0.5,
      ),
  ];
}();

/// Every seventh star twinkles; those are painted by [_TwinklePainter].
bool _twinkles(int i) => i % 7 == 0;

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (var i = 0; i < _stars.length; i++) {
      if (_twinkles(i)) continue;
      final s = _stars[i];
      p.color = Colors.white.withValues(alpha: s.a * (1 - s.y * 0.6));
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, p);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

class _TwinklePainter extends CustomPainter {
  /// 0..1 over [cosmicIdleDuration]; at 0 and 1 the stars sit at rest.
  final double v;
  const _TwinklePainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = v * cosmicIdleDuration.inMilliseconds / 1000;
    final env = math.sin(v * math.pi).clamp(0.0, 1.0);
    final p = Paint();
    final halo = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (var i = 0; i < _stars.length; i++) {
      if (!_twinkles(i)) continue;
      final s = _stars[i];
      final wave = math.sin(seconds * (1.1 + (i % 5) * 0.23) + i) * env;
      final a = (0.62 + 0.36 * wave).clamp(0.0, 1.0);
      final at = Offset(s.x * size.width, s.y * size.height);
      final r = s.r + 0.7;
      halo.color = Colors.white.withValues(alpha: 0.30 * a);
      canvas.drawCircle(at, r * 2.4, halo);
      p.color = Colors.white.withValues(alpha: a);
      canvas.drawCircle(at, r, p);
    }
  }

  @override
  bool shouldRepaint(_TwinklePainter old) => old.v != v;
}

// ----------------------------------------------------------------------------
// Brand mark
// ----------------------------------------------------------------------------

/// A small gold "orbit and star" mark used beside the wordmark.
class CosmicMark extends StatelessWidget {
  final double size;
  const CosmicMark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: const CustomPaint(painter: _MarkPainter()));
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Offset.zero & size;
    final gold = Paint()..shader = cosmicGoldGradient.createShader(rect);
    canvas.drawCircle(
      c,
      r * 0.9,
      Paint()
        ..color = cosmicGoldDeep.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = cosmicGoldGradient.createShader(rect),
    );
    // Four-point star.
    final star = Path();
    final long = r * 0.62, short = r * 0.17;
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final d = i.isEven ? long : short;
      final p = c + Offset(math.cos(a), math.sin(a)) * d;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, gold);
    canvas.drawCircle(c + Offset(r * 0.68, -r * 0.68), r * 0.13, gold);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}


// ----------------------------------------------------------------------------
// Zodiac ring
// ----------------------------------------------------------------------------

/// A faint zodiac / mandala ring: two circles, twelve divisions with a mark in
/// each, and fine tick marks on the inner edge.
class CosmicZodiacRingPainter extends CustomPainter {
  const CosmicZodiacRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final band = r * 0.125;
    final inner = r - band;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = cosmicGoldLight.withValues(alpha: 0.42);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = cosmicGoldLight.withValues(alpha: 0.20);
    canvas.drawCircle(c, r, line);
    canvas.drawCircle(c, inner, line);
    canvas.drawCircle(c, inner - band * 0.4, faint);
    Offset at(double angle, double radius) => c + Offset(math.cos(angle), math.sin(angle)) * radius;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(at(a, inner), at(a, r), line);
      final mid = a + math.pi / 12;
      final m = at(mid, (r + inner) / 2);
      if (i.isEven) {
        final p = Path();
        for (var k = 0; k < 4; k++) {
          final q = m +
              Offset(math.cos(mid + k * math.pi / 2), math.sin(mid + k * math.pi / 2)) *
                  (k.isEven ? band * 0.23 : band * 0.14);
          k == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
        }
        p.close();
        canvas.drawPath(p, Paint()..color = cosmicGoldLight.withValues(alpha: 0.6));
      } else {
        canvas.drawCircle(m, band * 0.12, Paint()..color = cosmicGoldDeep.withValues(alpha: 0.7));
        canvas.drawCircle(m, band * 0.25, faint);
      }
    }
    for (var i = 0; i < 72; i++) {
      final a = i * math.pi / 36;
      canvas.drawLine(at(a, inner - band * 0.4), at(a, inner - band * (i % 6 == 0 ? 0.78 : 0.6)), faint);
    }
  }

  @override
  bool shouldRepaint(CosmicZodiacRingPainter old) => false;
}

// ----------------------------------------------------------------------------
// Buttons
// ----------------------------------------------------------------------------

/// Full-width gold pill with a soft glow and a gentle press scale. Pass a null
/// [onPressed] to disable it, or [loading] to show a spinner instead of the
/// label.
class CosmicPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? leading;
  final bool loading;
  const CosmicPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.leading,
    this.loading = false,
  });

  @override
  State<CosmicPrimaryButton> createState() => _CosmicPrimaryButtonState();
}

class _CosmicPrimaryButtonState extends State<CosmicPrimaryButton> {
  bool _down = false;

  static const _ink = Color(0xFF2B1403);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final radius = BorderRadius.circular(28);
    final enabled = widget.onPressed != null && !widget.loading;
    return Semantics(
      button: true,
      container: true,
      enabled: enabled,
      child: AnimatedScale(
        scale: _down && !reduce ? 0.97 : 1,
        duration: Duration(milliseconds: reduce ? 0 : 110),
        curve: Curves.easeOut,
        child: Opacity(
          opacity: enabled || widget.loading ? 1 : 0.55,
          child: Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE3A3), cosmicGoldLight, cosmicGoldDeep],
                stops: [0, 0.35, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: cosmicGoldDeep.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(color: cosmicGoldLight.withValues(alpha: 0.25), blurRadius: 6),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: enabled ? widget.onPressed : null,
                onHighlightChanged: (v) => setState(() => _down = v),
                splashColor: Colors.white.withValues(alpha: 0.25),
                highlightColor: Colors.white.withValues(alpha: 0.12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Glossy top edge.
                    Positioned(
                      left: 1,
                      right: 1,
                      top: 1,
                      height: 26,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white.withValues(alpha: 0.38), Colors.white.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.loading)
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: _ink, strokeWidth: 2.4),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.leading != null) ...[
                                ExcludeSemantics(child: widget.leading!),
                                const SizedBox(width: 10),
                              ],
                              Text(
                                widget.label,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                  color: _ink,
                                ),
                              ),
                              if (widget.icon != null) ...[
                                const SizedBox(width: 10),
                                ExcludeSemantics(
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: _ink.withValues(alpha: 0.14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(widget.icon, size: 18, color: _ink),
                                  ),
                                ),
                              ],
                            ],
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
    );
  }
}

/// Full-width glass pill with a light outline, for the secondary action.
class CosmicGlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? leading;
  const CosmicGlassButton({super.key, required this.label, required this.onPressed, this.leading});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return Semantics(
      button: true,
      container: true,
      enabled: onPressed != null,
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Colors.white.withValues(alpha: 0.09),
          border: Border.all(color: Colors.white.withValues(alpha: 0.34), width: 1.2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            splashColor: Colors.white.withValues(alpha: 0.16),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[ExcludeSemantics(child: leading!), const SizedBox(width: 12)],
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Forms on the dark sky
// ----------------------------------------------------------------------------

/// Error colour that stays readable on the dark sky.
const Color cosmicError = Color(0xFFFF9B9B);

/// Solid colour of sheets and panels that sit on the sky.
const Color cosmicSheet = Color(0xFF171233);

/// Wraps a form so its text fields, cursor and selection suit the dark sky.
class CosmicFormTheme extends StatelessWidget {
  final Widget child;
  const CosmicFormTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        brightness: Brightness.dark,
        colorScheme: base.colorScheme.copyWith(
          brightness: Brightness.dark,
          primary: cosmicGoldLight,
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white.withValues(alpha: 0.74),
          error: cosmicError,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: cosmicGoldLight,
          selectionColor: cosmicGoldLight.withValues(alpha: 0.35),
          selectionHandleColor: cosmicGoldLight,
        ),
        textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      child: child,
    );
  }
}

/// A frosted, rounded text-field decoration for the dark sky.
InputDecoration cosmicInputDecoration(String label, IconData icon, {Widget? suffix}) {
  OutlineInputBorder border(Color color, [double width = 1.2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: color, width: width),
      );
  final muted = Colors.white.withValues(alpha: 0.74);
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.error) ? cosmicError : cosmicGoldLight,
        fontWeight: FontWeight.w700,
      ),
    ),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.08),
    prefixIcon: Icon(icon, color: muted, size: 22),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    errorStyle: const TextStyle(color: cosmicError, fontSize: 12.5, fontWeight: FontWeight.w600),
    errorMaxLines: 3,
    border: border(Colors.white.withValues(alpha: 0.24)),
    enabledBorder: border(Colors.white.withValues(alpha: 0.24)),
    disabledBorder: border(Colors.white.withValues(alpha: 0.12)),
    focusedBorder: border(cosmicGoldLight, 1.6),
    errorBorder: border(cosmicError),
    focusedErrorBorder: border(cosmicError, 1.6),
  );
}

/// The title style used on sign-in surfaces, with one phrase in gold.
class CosmicGoldText extends StatelessWidget {
  final String before;
  final String gold;
  final String after;
  final double fontSize;
  final TextAlign textAlign;
  const CosmicGoldText({
    super.key,
    this.before = '',
    required this.gold,
    this.after = '',
    this.fontSize = 28,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    // Already large, so it grows only a little with the system text size.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: LayoutBuilder(
        builder: (context, c) {
          // The same light-to-deep gold on every line.
          final line = MediaQuery.textScalerOf(context).scale(fontSize) * 1.14;
          final paint = Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFE9B8), cosmicGoldLight, cosmicGoldDeep],
              stops: [0.1, 0.45, 0.95],
              tileMode: TileMode.repeated,
            ).createShader(Rect.fromLTWH(0, 0, c.maxWidth.isFinite ? c.maxWidth : 400, line));
          // Own layer: a text shader is positioned in layer coordinates, so
          // this keeps the gradient aligned with the lines of the text.
          return RepaintBoundary(
            child: Text.rich(
              TextSpan(
                children: [
                  if (before.isNotEmpty) TextSpan(text: before),
                  TextSpan(text: gold, style: TextStyle(foreground: paint)),
                  if (after.isNotEmpty) TextSpan(text: after),
                ],
              ),
              textAlign: textAlign,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.14,
                letterSpacing: -0.4,
              ),
            ),
          );
        },
      ),
    );
  }
}
