// Shared building blocks for the games section (hub, Graha Quest, Nakshatra
// Cards, Moksha Patam, Cosmic Match).
//
// Built on the app design system (`AppColors`, `AppText`, `AppRadius`...): white
// cards with hairline borders, one saffron accent, deep-indigo "cosmic" hero
// areas, thin strokes and calm motion. Everything respects "reduce motion"
// (MediaQuery.disableAnimations) and stays overflow-free at 320dp / 1.3x text.
// One-shot effects (confetti, XP flight) always end; only [PulseDot],
// [GameShimmer] and [GameSkeleton] loop, and they stop under reduce motion.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app_ui.dart';

// ============================================================================
// Palette (mapped onto the app tokens)
// ============================================================================

class GameColors {
  GameColors._();

  static const bg = AppColors.background;
  static const ink = AppColors.textPrimary;
  static const accent = AppColors.primary;
  static const nightA = AppColors.cosmicLight;
  static const nightB = AppColors.cosmic;
  static const gold = AppColors.gold;
  static const goldDeep = Color(0xFFB7791F);
  static const good = AppColors.success;
  static const bad = AppColors.danger;
  static const blue = AppColors.info;
  static const violet = AppColors.cosmicLight;
  static const pink = AppColors.love;
  static const flame = AppColors.primary;
  static const muted = AppColors.textSecondary;

  static const List<Color> night = [nightA, nightB];
  static const List<Color> confetti = [gold, accent, Colors.white, Color(0xFFB9B3F5)];

  static const Map<String, String> glyphs = {
    'Sun': '☉',
    'Moon': '☽',
    'Mars': '♂',
    'Mercury': '☿',
    'Jupiter': '♃',
    'Venus': '♀',
    'Saturn': '♄',
    'Rahu': '☊',
    'Ketu': '☋',
  };

  // Restrained, slightly desaturated planet hues: distinct, never neon.
  static const Map<String, Color> _planet = {
    'Sun': Color(0xFFD98E1F),
    'Moon': Color(0xFF6F82B0),
    'Mars': Color(0xFFC84B3A),
    'Mercury': Color(0xFF2B8F6E),
    'Jupiter': Color(0xFFB8901C),
    'Venus': Color(0xFFB8537F),
    'Saturn': Color(0xFF4A4EA3),
    'Rahu': Color(0xFF5F6B7D),
    'Ketu': Color(0xFF8C6146),
  };

  /// Signature colour of a graha (indigo for anything unknown / null).
  static Color planet(String? name) => _planet[name] ?? violet;

  /// Astro glyph of a graha ("✦" for anything unknown / null).
  static String glyph(String? name) => glyphs[name] ?? '✦';

  /// Two-stop gradient in the planet's colour, deepened towards indigo, for
  /// card art.
  static List<Color> planetGradient(String? name) {
    final c = planet(name);
    return [Color.lerp(c, AppColors.cosmic, 0.25)!, Color.lerp(c, AppColors.cosmic, 0.7)!];
  }

  /// Planet status: 'strong' | 'steady' | 'needs_care'.
  static Color status(String s) => s == 'strong' ? good : (s == 'needs_care' ? bad : blue);

  /// Card rarity: 'common' | 'rare' | 'legendary'.
  static Color rarity(String r) => r == 'legendary' ? goldDeep : (r == 'rare' ? violet : muted);
}

/// True when the user asked the OS to reduce motion: skip long animations.
bool gameReduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Consistent white app bar for every game screen: bold title, optional muted
/// subtitle, optional actions.
PreferredSizeWidget gameAppBar({required String title, String? subtitle, List<Widget>? actions}) {
  return AppBar(
    titleSpacing: 0,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    title: Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (subtitle != null)
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    ),
    actions: actions,
    bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
  );
}

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

  /// Lifts the card with a soft shadow (used for "this needs you" states).
  final bool glow;

  const GameCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color = AppColors.surface,
    this.gradient,
    this.borderColor,
    this.radius = AppRadius.lg,
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
    final radius = BorderRadius.circular(widget.radius);
    Widget body = Ink(
      decoration: BoxDecoration(
        color: g == null ? widget.color : null,
        gradient: g == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
        borderRadius: radius,
        border: Border.all(color: widget.borderColor ?? (g == null ? AppColors.border : Colors.transparent)),
        boxShadow: widget.glow ? AppShadows.card : null,
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
        scale: _down && !gameReduceMotion(context) ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
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
  const GamePill(this.text,
      {super.key, this.color = GameColors.accent, this.icon, this.solid = false, this.fontSize = 11.5});

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: fontSize + 1, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize, height: 1.25, fontWeight: FontWeight.w700, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Section heading used inside the game screens: one bold title, optional
/// trailing widget (a count pill, a hint).
class GameSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const GameSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(text, style: AppText.title)),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), trailing!],
        ],
      ),
    );
  }
}

/// Tinted rounded square holding an icon (the app's standard icon tile).
class GameIconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool onDark;
  const GameIconTile(
      {super.key, required this.icon, this.color = AppColors.primary, this.size = 40, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.10) : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
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
    if (gameReduceMotion(context)) {
      return Text('$prefix$value$suffix', maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) =>
          Text('$prefix${v.round()}$suffix', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
    );
  }
}

/// Animated progress bar. [progress] is 0..1; [label] sits under the bar.
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
    this.height = 6,
    this.onDark = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final target = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final track = trackColor ?? (onDark ? Colors.white.withValues(alpha: 0.14) : AppColors.surfaceMuted);
    final textColor = onDark ? AppColors.textOnDarkMuted : AppColors.textSecondary;
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
                  widthFactor: v <= 0 ? 0.0 : v.clamp(0.02, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
                  ),
                ),
              ],
            ),
          ),
        );
    final labelStyle = TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: textColor);
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
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => bar(v),
              ),
            if (label != null || trailingLabel != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(label ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
                  ),
                  if (trailingLabel != null) Text(trailingLabel!, maxLines: 1, style: labelStyle),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Level medallion: a thin gold ring with "Lv" and the number. Eases in when
/// the level changes.
class LevelBadge extends StatelessWidget {
  final int level;
  final double size;

  /// Text colour for dark (default) or light surfaces.
  final bool onDark;
  const LevelBadge({super.key, required this.level, this.size = 54, this.onDark = true});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GameColors.gold.withValues(alpha: onDark ? 0.14 : 0.12),
        border: Border.all(color: GameColors.gold, width: math.max(1.5, size * 0.035)),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lv',
                  textScaler: TextScaler.noScaling,
                  style:
                      TextStyle(fontSize: size * 0.18, height: 1, fontWeight: FontWeight.w600, color: GameColors.gold)),
              Text('$level',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: size * 0.36,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: onDark ? Colors.white : AppColors.textPrimary,
                  )),
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
                tween: Tween<double>(begin: 0.85, end: 1),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => Opacity(
                    opacity: ((v - 0.85) / 0.15).clamp(0.0, 1.0), child: Transform.scale(scale: v, child: child)),
                child: badge,
              ),
      ),
    );
  }
}

/// Streak flame with the day count. Saffron when the streak is [alive] today,
/// muted while today's mission is still waiting.
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
    final idle = onDark ? Colors.white.withValues(alpha: 0.4) : AppColors.textTertiary;
    final flameColor = lit ? GameColors.flame : idle;
    final textColor =
        onDark ? (lit ? Colors.white : AppColors.textOnDarkMuted) : (lit ? GameColors.ink : AppColors.textSecondary);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_fire_department_rounded, size: size, color: flameColor),
        if (showLabel) ...[
          const SizedBox(width: 2),
          Text('$streak',
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w700, color: textColor, height: 1)),
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

/// Round planet mark: soft tint of the planet's colour with its glyph.
/// Optional [power] (0..100) draws a thin progress ring; [level] adds a pip.
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
    final color = dimmed ? AppColors.textTertiary : GameColors.planet(planet);
    final ring = power != null;
    final inner = ring ? size * 0.78 : size;
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
                      track: color.withValues(alpha: 0.14),
                      stroke: math.max(2.0, size * 0.045),
                    ),
                  ),
                ),
              Container(
                width: inner,
                height: inner,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.10),
                  border: Border.all(color: color.withValues(alpha: 0.28)),
                ),
                alignment: Alignment.center,
                child: Text(
                  GameColors.glyph(planet),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: inner * 0.46, height: 1.1, color: color, fontWeight: FontWeight.w600),
                ),
              ),
              if (level != null)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    constraints: BoxConstraints(minWidth: size * 0.36),
                    padding: EdgeInsets.symmetric(horizontal: size * 0.06, vertical: size * 0.025),
                    decoration: BoxDecoration(
                      color: GameColors.ink,
                      borderRadius: BorderRadius.circular(size),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text('$level',
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                            fontSize: size * 0.2, height: 1.1, fontWeight: FontWeight.w700, color: Colors.white)),
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

/// One-shot, restrained sparkle burst that fills its parent (put it in a
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
    this.particleCount = 36,
    this.duration = const Duration(milliseconds: 1400),
    this.colors = GameColors.confetti,
    this.origin = const Alignment(0, -0.2),
    this.autoPlay = true,
    this.onDone,
  });

  /// Plays a burst over the whole screen and removes itself when finished.
  static void show(BuildContext context, {Alignment origin = const Alignment(0, -0.2), int particleCount = 40}) {
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
          -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.4,
          0.3 + rnd.nextDouble() * 0.6,
          3 + rnd.nextDouble() * 4,
          (rnd.nextDouble() - 0.5) * 6,
          widget.colors[i % widget.colors.length],
          i % 3 == 0,
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

/// Paints the particles at time [t] (0..1).
class ConfettiPainter extends CustomPainter {
  final List<Object> _particles;
  final double t;
  final Alignment origin;
  const ConfettiPainter(this._particles, this.t, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final o = origin.alongSize(size);
    final reach = size.shortestSide * 0.8;
    final fade = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
    final paint = Paint();
    for (final raw in _particles) {
      final p = raw as _Particle;
      final travel = Curves.easeOutCubic.transform(t) * reach * p.speed;
      final x = o.dx + math.cos(p.angle) * travel;
      final y = o.dy + math.sin(p.angle) * travel + t * t * size.height * 0.3;
      paint.color = p.color.withValues(alpha: fade * 0.9);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      if (p.star) {
        canvas.drawPath(_star(p.size), paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
      }
      canvas.restore();
    }
  }

  static Path _star(double r) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.35;
      final a = -math.pi / 2 + i * math.pi / 4;
      final pt = Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.t != t;
}

/// "+40 XP" chip that glides from one widget to another (e.g. from a mission
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
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
            final lift = math.sin(_c.value * math.pi) * 28;
            final pos = Offset.lerp(widget.start, widget.end, t)! - Offset(0, lift);
            final opacity = _c.value > 0.8 ? (1 - (_c.value - 0.8) / 0.2).clamp(0.0, 1.0) : 1.0;
            return Stack(
              children: [
                Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: Opacity(opacity: opacity, child: Transform.scale(scale: 1.05 - 0.2 * t, child: child)),
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
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(widget.text,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GameColors.gold)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Softly breathing dot / wrapper that says "this is ready". Loops, so use it
/// sparingly; it is static when the user prefers reduced motion.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final Widget? child;
  const PulseDot({super.key, this.color = GameColors.accent, this.size = 10, this.child});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

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
      return FadeTransition(opacity: Tween<double>(begin: 1, end: 0.75).animate(_c), child: child);
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
              BoxShadow(color: widget.color.withValues(alpha: 0.4 * (1 - _c.value)), spreadRadius: 4 * _c.value),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slow diagonal light sweep over [child] (face-down card, "reveal me"
/// states). Static when the user prefers reduced motion.
class GameShimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;
  const GameShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.lg)),
  });

  @override
  State<GameShimmer> createState() => _GameShimmerState();
}

class _GameShimmerState extends State<GameShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

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
                            Colors.white.withValues(alpha: 0.10),
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

/// Skeleton placeholder blocks while a game loads.
class GameSkeleton extends StatelessWidget {
  /// Heights of the placeholder blocks, top to bottom.
  final List<double> blocks;
  final String label;
  const GameSkeleton({super.key, this.blocks = const [150, 64, 120, 120, 120], this.label = 'Loading your game'});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final h in blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SkeletonBox(height: h, radius: AppRadius.lg),
              ),
          ],
        ),
      ),
    );
  }
}

/// Friendly error with a retry (full) or a one-line inline variant (compact).
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
    this.title = 'Couldn\'t load this game',
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.textTertiary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.body),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: AppStateView.error(title: title, message: message, onAction: onRetry),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GameIconTile(icon: Icons.auto_awesome_rounded, color: GameColors.gold, size: 48, onDark: true),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppText.headline.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
          const SizedBox(height: AppSpacing.xl),
          AppButton(label: 'Create my Kundli', icon: Icons.arrow_forward_rounded, onPressed: onCreate),
        ],
      ),
    );
  }
}
