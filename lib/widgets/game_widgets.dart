// Shared building blocks for the four games (hub, Graha Quest, Nakshatra
// Cards, Moksha Patam, Cosmic Match).
//
// Everything here is self-contained (no packages beyond Flutter), respects
// "reduce motion" (MediaQuery.disableAnimations) and stays overflow-free at
// 320dp / 1.3x text. One-shot effects (confetti, XP flight, pops) always end;
// only [PulseDot], [GameShimmer] and [GameSkeleton] loop.

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ============================================================================
// Palette
// ============================================================================

class GameColors {
  GameColors._();

  static const bg = Color(0xFFFCF7F1);
  static const ink = Color(0xFF17142B);
  static const accent = Color(0xFFFB9548);
  static const nightA = Color(0xFF1E1A38);
  static const nightB = Color(0xFF3A2A6B);
  static const gold = Color(0xFFF5B301);
  static const goldDeep = Color(0xFFD98200);
  static const good = Color(0xFF059669);
  static const bad = Color(0xFFE5484D);
  static const blue = Color(0xFF2F80ED);
  static const violet = Color(0xFF6C63FF);
  static const pink = Color(0xFFEC4899);
  static const flame = Color(0xFFFF6B1A);
  static const muted = Color(0xFF6B7280);

  static const List<Color> night = [nightA, nightB];
  static const List<Color> confetti = [gold, accent, pink, violet, Color(0xFF34D399), Color(0xFF38BDF8)];

  static const Map<String, String> glyphs = {
    'Sun': '☉', 'Moon': '☽', 'Mars': '♂', 'Mercury': '☿', 'Jupiter': '♃',
    'Venus': '♀', 'Saturn': '♄', 'Rahu': '☊', 'Ketu': '☋',
  };

  static const Map<String, Color> _planet = {
    'Sun': Color(0xFFF59E0B),
    'Moon': Color(0xFF6C8CF5),
    'Mars': Color(0xFFE5484D),
    'Mercury': Color(0xFF10B981),
    'Jupiter': Color(0xFFE0A100),
    'Venus': Color(0xFFEC4899),
    'Saturn': Color(0xFF4F46E5),
    'Rahu': Color(0xFF64748B),
    'Ketu': Color(0xFFB45309),
  };

  /// Signature colour of a graha (violet for anything unknown / null).
  static Color planet(String? name) => _planet[name] ?? violet;

  /// Astro glyph of a graha ("✦" for anything unknown / null).
  static String glyph(String? name) => glyphs[name] ?? '✦';

  /// Two-stop gradient in the planet's colour, for avatars and card art.
  static List<Color> planetGradient(String? name) {
    final c = planet(name);
    final hsl = HSLColor.fromColor(c);
    return [
      hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor(),
      hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).withHue((hsl.hue + 18) % 360).toColor(),
    ];
  }

  /// Planet status: 'strong' | 'steady' | 'needs_care'.
  static Color status(String s) => s == 'strong' ? good : (s == 'needs_care' ? bad : blue);

  /// Card rarity: 'common' | 'rare' | 'legendary'.
  static Color rarity(String r) => r == 'legendary' ? gold : (r == 'rare' ? violet : muted);
}

/// True when the user asked the OS to reduce motion: skip long animations.
bool gameReduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ============================================================================
// Containers
// ============================================================================

/// Rounded game surface. With [onTap] it presses in slightly and is announced
/// as a button with [semanticLabel].
class GameCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final List<Color>? gradient;
  final Color? borderColor;
  final double radius;
  final String? semanticLabel;
  final bool glow;

  const GameCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.gradient,
    this.borderColor,
    this.radius = 22,
    this.semanticLabel,
    this.glow = false,
  });

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gradient;
    final tint = g != null ? g.last : Colors.black;
    final radius = BorderRadius.circular(widget.radius);
    Widget body = Ink(
      decoration: BoxDecoration(
        color: g == null ? widget.color : null,
        gradient: g == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
        borderRadius: radius,
        border: Border.all(color: widget.borderColor ?? Colors.black.withValues(alpha: g == null ? 0.06 : 0)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: widget.glow ? 0.35 : (g == null ? 0.05 : 0.22)),
            blurRadius: widget.glow ? 22 : 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    if (widget.onTap == null) {
      return Material(type: MaterialType.transparency, child: SizedBox(width: double.infinity, child: body));
    }
    body = InkWell(
      onTap: widget.onTap,
      onHighlightChanged: _set,
      borderRadius: radius,
      child: body,
    );
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _down && !gameReduceMotion(context) ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: Material(type: MaterialType.transparency, child: SizedBox(width: double.infinity, child: body)),
      ),
    );
  }
}

/// Small rounded label ("+40 XP", "Needs you").
class GamePill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  final double fontSize;
  const GamePill(this.text, {super.key, this.color = GameColors.accent, this.icon, this.solid = false, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: fontSize + 1, color: fg), const SizedBox(width: 3)],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Section heading used inside the game screens.
class GameSectionTitle extends StatelessWidget {
  final String text;
  final String? emoji;
  final Widget? trailing;
  const GameSectionTitle(this.text, {super.key, this.emoji, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          if (emoji != null) ...[
            ExcludeSemantics(child: Text(emoji!, style: const TextStyle(fontSize: 18))),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: GameColors.ink)),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

// ============================================================================
// Player: level, XP, streak
// ============================================================================

/// Number that counts up/down to [value].
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final Duration duration;
  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  Widget build(BuildContext context) {
    if (gameReduceMotion(context)) return Text('$prefix$value$suffix', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$prefix${v.round()}$suffix', style: style),
    );
  }
}

/// Animated experience bar. [progress] is 0..1; [label] sits under the bar.
class XpBar extends StatelessWidget {
  final double progress;
  final String? label;
  final String? trailingLabel;
  final Color color;
  final Color? trackColor;
  final double height;
  final bool onDark;
  final String? semanticLabel;

  const XpBar({
    super.key,
    required this.progress,
    this.label,
    this.trailingLabel,
    this.color = GameColors.gold,
    this.trackColor,
    this.height = 12,
    this.onDark = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final target = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final track = trackColor ?? (onDark ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.08));
    final textColor = onDark ? Colors.white.withValues(alpha: 0.85) : Colors.grey.shade700;
    Widget bar(double v) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: track),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v <= 0 ? 0.0 : v.clamp(0.03, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height),
                      gradient: LinearGradient(colors: [Color.lerp(color, Colors.white, 0.35)!, color]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Semantics(
      label: semanticLabel ?? label ?? 'Progress',
      value: '${(target * 100).round()} percent',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (gameReduceMotion(context))
              bar(target)
            else
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: target),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => bar(v),
              ),
            if (label != null || trailingLabel != null) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(label ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
                  ),
                  if (trailingLabel != null)
                    Text(trailingLabel!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gold medallion with the player's level. Pops when the level changes.
class LevelBadge extends StatelessWidget {
  final int level;
  final double size;
  const LevelBadge({super.key, required this.level, this.size = 54});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE082), GameColors.gold, GameColors.goldDeep],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: size * 0.05),
        boxShadow: [BoxShadow(color: GameColors.gold.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('LV',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: size * 0.17, height: 1, fontWeight: FontWeight.w900, color: const Color(0xFF6B3F00))),
              Text('$level',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: size * 0.38, height: 1.05, fontWeight: FontWeight.w900, color: const Color(0xFF3D2400))),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      label: 'Level $level',
      child: ExcludeSemantics(
        child: gameReduceMotion(context)
            ? badge
            : TweenAnimationBuilder<double>(
                key: ValueKey<int>(level),
                tween: Tween<double>(begin: 0.7, end: 1),
                duration: const Duration(milliseconds: 520),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: badge,
              ),
      ),
    );
  }
}

/// Streak flame with the day count. Bright when the streak is [alive] today,
/// grey embers when today's mission is still waiting. Pops when the count grows.
class StreakFlame extends StatelessWidget {
  final int streak;
  final bool alive;
  final double size;
  final bool onDark;
  final bool showLabel;

  const StreakFlame({
    super.key,
    required this.streak,
    this.alive = false,
    this.size = 26,
    this.onDark = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final lit = alive && streak > 0;
    final idle = onDark ? Colors.white.withValues(alpha: 0.45) : Colors.grey.shade400;
    final flameColor = lit ? GameColors.flame : idle;
    final textColor = lit ? (onDark ? Colors.white : GameColors.ink) : (onDark ? Colors.white70 : Colors.grey.shade600);
    final flame = Stack(
      alignment: Alignment.center,
      children: [
        if (lit)
          Container(
            width: size * 1.15,
            height: size * 1.15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: GameColors.flame.withValues(alpha: 0.45), blurRadius: size * 0.6)],
            ),
          ),
        Icon(Icons.local_fire_department_rounded, size: size, color: flameColor),
      ],
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        gameReduceMotion(context)
            ? flame
            : TweenAnimationBuilder<double>(
                key: ValueKey<String>('$streak$lit'),
                tween: Tween<double>(begin: lit ? 0.5 : 1, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: flame,
              ),
        if (showLabel) ...[
          const SizedBox(width: 3),
          Text('$streak',
              style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w900, color: textColor, height: 1)),
        ],
      ],
    );
    final days = streak == 1 ? '1 day' : '$streak days';
    return Semantics(
      label: lit
          ? 'Streak $days, alive today'
          : (streak > 0 ? 'Streak $days, complete a mission today to keep it' : 'No streak yet'),
      child: ExcludeSemantics(child: row),
    );
  }
}

// ============================================================================
// Planets
// ============================================================================

/// Round planet character: gradient in the planet's colour with its glyph.
/// Optional [power] (0..100) draws a progress ring; [level] adds a small pip.
class PlanetAvatar extends StatelessWidget {
  final String planet;
  final double size;
  final int? level;
  final int? power;
  final bool highlight;
  final bool dimmed;

  const PlanetAvatar({
    super.key,
    required this.planet,
    this.size = 48,
    this.level,
    this.power,
    this.highlight = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = GameColors.planet(planet);
    final colors = dimmed ? [Colors.grey.shade400, Colors.grey.shade600] : GameColors.planetGradient(planet);
    final ring = power != null;
    final inner = ring ? size * 0.82 : size;
    return Semantics(
      label: [
        planet,
        if (level != null) 'level $level',
        if (power != null) 'power $power percent',
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (ring)
                SizedBox(
                  width: size,
                  height: size,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: (power! / 100).clamp(0.0, 1.0),
                      color: highlight ? GameColors.bad : color,
                      track: color.withValues(alpha: 0.18),
                      stroke: math.max(2.5, size * 0.065),
                    ),
                  ),
                ),
              Container(
                width: inner,
                height: inner,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  boxShadow: [
                    BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: size * 0.2, offset: Offset(0, size * 0.06)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  GameColors.glyph(planet),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: inner * 0.52, height: 1.1, color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              if (level != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    constraints: BoxConstraints(minWidth: size * 0.38),
                    padding: EdgeInsets.symmetric(horizontal: size * 0.07, vertical: size * 0.03),
                    decoration: BoxDecoration(
                      color: GameColors.ink,
                      borderRadius: BorderRadius.circular(size),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text('$level',
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: size * 0.22, height: 1.1, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double stroke;
  const _RingPainter({required this.progress, required this.color, required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (progress > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

// ============================================================================
// Celebration effects
// ============================================================================

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final bool star;
  const _Particle(this.angle, this.speed, this.size, this.spin, this.color, this.star);
}

/// One-shot confetti / sparkle burst that fills its parent (put it in a
/// `Positioned.fill` above your content, or call [ConfettiBurst.show] to play
/// it over the whole screen). Never blocks touches; does nothing when the
/// user prefers reduced motion.
class ConfettiBurst extends StatefulWidget {
  final int particleCount;
  final Duration duration;
  final List<Color> colors;

  /// Burst origin within the widget (-1..1 like [Alignment]).
  final Alignment origin;
  final bool autoPlay;
  final VoidCallback? onDone;

  const ConfettiBurst({
    super.key,
    this.particleCount = 70,
    this.duration = const Duration(milliseconds: 1600),
    this.colors = GameColors.confetti,
    this.origin = const Alignment(0, -0.2),
    this.autoPlay = true,
    this.onDone,
  });

  /// Plays a burst over the whole screen and removes itself when finished.
  static void show(BuildContext context, {Alignment origin = const Alignment(0, -0.2), int particleCount = 80}) {
    if (gameReduceMotion(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: ConfettiBurst(
          origin: origin,
          particleCount: particleCount,
          onDone: () {
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<ConfettiBurst> createState() => ConfettiBurstState();
}

class ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });
  List<_Particle> _particles = const [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && widget.autoPlay) {
      _started = true;
      play();
    }
  }

  /// (Re)plays the burst.
  void play() {
    if (!mounted) return;
    if (gameReduceMotion(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
      return;
    }
    final rnd = math.Random();
    _particles = [
      for (var i = 0; i < widget.particleCount; i++)
        _Particle(
          -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.5,
          0.35 + rnd.nextDouble() * 0.75,
          5 + rnd.nextDouble() * 7,
          (rnd.nextDouble() - 0.5) * 14,
          widget.colors[i % widget.colors.length],
          i % 5 == 0,
        ),
    ];
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: _c.isAnimating || (_c.value > 0 && _c.value < 1)
                  ? ConfettiPainter(_particles, _c.value, widget.origin)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the confetti particles at time [t] (0..1).
class ConfettiPainter extends CustomPainter {
  final List<Object> _particles;
  final double t;
  final Alignment origin;
  const ConfettiPainter(this._particles, this.t, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final o = origin.alongSize(size);
    final reach = size.shortestSide * 0.95;
    final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
    final paint = Paint();
    for (final raw in _particles) {
      final p = raw as _Particle;
      final travel = Curves.easeOutCubic.transform(t) * reach * p.speed;
      final x = o.dx + math.cos(p.angle) * travel;
      final y = o.dy + math.sin(p.angle) * travel + t * t * size.height * 0.45;
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      if (p.star) {
        canvas.drawPath(_star(p.size * 0.9), paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), const Radius.circular(1.5)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  static Path _star(double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.4;
      final a = -math.pi / 2 + i * math.pi / 4;
      final pt = Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.t != t;
}

/// "+40 XP" chip that flies from one widget to another (e.g. from a mission
/// card into the XP bar). No-op when either end is not laid out or the user
/// prefers reduced motion.
class XpFlight {
  XpFlight._();

  static void fly(BuildContext context, {required GlobalKey from, required GlobalKey to, required String text}) {
    if (gameReduceMotion(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final a = from.currentContext?.findRenderObject();
    final b = to.currentContext?.findRenderObject();
    if (overlay == null || a is! RenderBox || b is! RenderBox || !a.attached || !b.attached) return;
    if (!a.hasSize || !b.hasSize) return;
    final start = a.localToGlobal(a.size.center(Offset.zero));
    final end = b.localToGlobal(b.size.center(Offset.zero));
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _XpFlightChip(
        start: start,
        end: end,
        text: text,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _XpFlightChip extends StatefulWidget {
  final Offset start;
  final Offset end;
  final String text;
  final VoidCallback onDone;
  const _XpFlightChip({required this.start, required this.end, required this.text, required this.onDone});

  @override
  State<_XpFlightChip> createState() => _XpFlightChipState();
}

class _XpFlightChipState extends State<_XpFlightChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 850))
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
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = Curves.easeInOutCubic.transform(_c.value);
            final lift = math.sin(_c.value * math.pi) * 46;
            final pos = Offset.lerp(widget.start, widget.end, t)! - Offset(0, lift);
            final scale = 1.25 - 0.45 * t;
            final opacity = _c.value > 0.85 ? (1 - (_c.value - 0.85) / 0.15).clamp(0.0, 1.0) : 1.0;
            return Stack(
              children: [
                Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: Opacity(opacity: opacity, child: Transform.scale(scale: scale, child: child)),
                  ),
                ),
              ],
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: GameColors.gold,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: GameColors.gold.withValues(alpha: 0.6), blurRadius: 12)],
              ),
              child: Text(widget.text,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF3D2400))),
            ),
          ),
        ),
      ),
    );
  }
}

/// Softly breathing dot / wrapper that says "tap me". Loops forever, so use it
/// sparingly; it is static when the user prefers reduced motion.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final Widget? child;
  const PulseDot({super.key, this.color = GameColors.bad, this.size = 10, this.child});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (gameReduceMotion(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child != null) {
      return ScaleTransition(scale: Tween<double>(begin: 1, end: 1.06).animate(_c), child: child);
    }
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(color: widget.color.withValues(alpha: 0.55 * (1 - _c.value)), blurRadius: 2, spreadRadius: 5 * _c.value),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diagonal light sweep over [child] (face-down card, "collect me" states).
/// Static when the user prefers reduced motion.
class GameShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;
  const GameShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  State<GameShimmer> createState() => _GameShimmerState();
}

class _GameShimmerState extends State<GameShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  void _sync() {
    final run = widget.enabled && !gameReduceMotion(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GameShimmer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: widget.borderRadius,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final x = -1.6 + _c.value * 3.2;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(x - 0.5, -1),
                          end: Alignment(x + 0.5, 1),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// Loading / error / empty states
// ============================================================================

class GameSkeleton extends StatefulWidget {
  /// Heights of the placeholder blocks, top to bottom.
  final List<double> blocks;
  final String label;
  const GameSkeleton({super.key, this.blocks = const [150, 64, 120, 120, 120], this.label = 'Loading your game'});

  @override
  State<GameSkeleton> createState() => _GameSkeletonState();
}

class _GameSkeletonState extends State<GameSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (gameReduceMotion(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final h in widget.blocks)
              Container(
                height: h,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GameError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool compact;
  final String title;
  const GameError({
    super.key,
    required this.message,
    required this.onRetry,
    this.compact = false,
    this.title = 'The stars dropped the dice',
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(child: Text('🎲', style: TextStyle(fontSize: 44))),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
        ],
      ),
    );
  }
}

/// Shown when the player has no Kundli yet (`NO_KUNDLI`): every game is driven
/// by the user's own chart, so this leads to the birth-details form.
class GameNoKundli extends StatelessWidget {
  final VoidCallback onCreate;
  final String title;
  final String message;
  const GameNoKundli({
    super.key,
    required this.onCreate,
    this.title = 'Your stars are the game board',
    this.message = 'Add your birth details once and the games come alive with your own planets, your own '
        'lucky days and your own cards.',
  });

  @override
  Widget build(BuildContext context) {
    return GameCard(
      gradient: GameColors.night,
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(child: Text('🪐', style: TextStyle(fontSize: 48))),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCreate,
              style: ElevatedButton.styleFrom(
                backgroundColor: GameColors.gold,
                foregroundColor: const Color(0xFF3D2400),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Create my Kundli', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}
