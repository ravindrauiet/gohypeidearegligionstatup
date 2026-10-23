import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../services/backend_service.dart';
import 'ui/app_ui.dart';

// ============================================================================
// Palette & formatting
//
// `FC` predates the shared design system and is used by several screens
// (forecast, timeline, home cards, games). Its names stay, but every colour now
// maps onto the `AppColors` tokens so the forecast surfaces match the app.
// ============================================================================

class FC {
  FC._();
  static const bg = AppColors.background;
  static const accent = AppColors.primary;
  static const ink = AppColors.textPrimary;
  static const heroA = AppColors.cosmicLight;
  static const heroB = AppColors.cosmic;
  static const good = AppColors.success;
  static const blue = AppColors.info;
  static const bad = AppColors.danger;
  static const neutral = AppColors.textSecondary;
  static const violet = AppColors.cosmicLight;

  /// Score colour for light surfaces.
  static Color score(int s) {
    if (s >= 75) return good;
    if (s >= 60) return blue;
    if (s >= 42) return AppColors.warning;
    return bad;
  }

  /// Mood accent for the dark (cosmic) hero card: light tints that stay
  /// readable on deep indigo.
  static Color moodOnDark(String mood) {
    switch (mood) {
      case Mood.excellent:
        return const Color(0xFF6EE7A0);
      case Mood.good:
        return const Color(0xFFA5B4FC);
      case Mood.challenging:
        return const Color(0xFFFDA4AF);
      default:
        return AppColors.gold;
    }
  }

  static Color effect(String e) => e == Effect.favorable ? good : (e == Effect.challenging ? bad : neutral);

  static IconData effectIcon(String e) => e == Effect.favorable
      ? Icons.trending_up_rounded
      : (e == Effect.challenging ? Icons.warning_amber_rounded : Icons.remove_rounded);

  static Color area(String key) {
    switch (key) {
      case LifeArea.career:
        return AppColors.info;
      case LifeArea.love:
        return AppColors.love;
      case LifeArea.money:
        return AppColors.success;
      case LifeArea.health:
        return AppColors.primary;
      default:
        return AppColors.cosmicLight;
    }
  }

  static IconData areaIcon(String key) {
    switch (key) {
      case LifeArea.career:
        return Icons.work_rounded;
      case LifeArea.love:
        return Icons.favorite_rounded;
      case LifeArea.money:
        return Icons.savings_rounded;
      case LifeArea.health:
        return Icons.spa_rounded;
      case 'travel':
        return Icons.flight_takeoff_rounded;
      case 'newBeginnings':
        return Icons.rocket_launch_rounded;
      default:
        return Icons.self_improvement_rounded;
    }
  }

  static const Map<String, String> glyph = {
    'Sun': '☉', 'Moon': '☽', 'Mars': '♂', 'Mercury': '☿', 'Jupiter': '♃',
    'Venus': '♀', 'Saturn': '♄', 'Rahu': '☊', 'Ketu': '☋',
  };

  static String ordinal(int n) {
    if (n <= 0) return '—';
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  static String date(DateTime? d, [String pattern = 'd MMM yyyy']) => d == null ? '—' : DateFormat(pattern).format(d);
  static String dayShort(DateTime d) => DateFormat('EEE d MMM').format(d);
  static String range(DateTime a, DateTime b) {
    if (a.year == b.year && a.month == b.month) return '${a.day} – ${DateFormat('d MMM yyyy').format(b)}';
    if (a.year == b.year) return '${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM yyyy').format(b)}';
    return '${DateFormat('d MMM yyyy').format(a)} – ${DateFormat('d MMM yyyy').format(b)}';
  }

  /// Animation duration that collapses to zero when the OS asks for reduced motion.
  static Duration anim(BuildContext context, int ms) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : Duration(milliseconds: ms);
}

/// Family member id of the profile in focus (null = the user themself).
int? activeFamilyId(BackendService s) => Vedic.toInt(s.selectedFamilyMember?['id']);

/// Opens the AI astrologer with a pre-filled question. Set [closeSheet] when
/// called from inside a bottom sheet so it is dismissed first.
void askAstrologer(BuildContext context, String message, {String field = 'Personal Forecast', bool closeSheet = false}) {
  final nav = Navigator.of(context);
  if (closeSheet) nav.pop();
  nav.pushNamed('/chatbot', arguments: {
    'name': 'Vedic Forecast Guide',
    'specialty': 'Transits, Dasha & Panchang',
    'field': field,
    'initialMessage': message,
  });
}

/// Plain-text description of a transit for the AI astrologer.
String transitQuestion(Transit t, {ForecastProfile? profile}) {
  final who = (profile != null && profile.isFamily && profile.name.isNotEmpty)
      ? 'For my ${profile.relationship ?? 'family member'} ${profile.name}: '
      : '';
  final parts = <String>[
    '${t.planet} is transiting ${t.sign}${t.nakshatra.isNotEmpty ? ' (${t.nakshatra} nakshatra)' : ''}${t.retrograde ? ', retrograde' : ''}',
    if (t.houseFromMoon > 0) 'in the ${FC.ordinal(t.houseFromMoon)} house from my Moon',
    if (t.houseFromLagna > 0) 'and the ${FC.ordinal(t.houseFromLagna)} from my Lagna',
  ];
  final dates = [
    if (t.since != null) 'since ${FC.date(t.since)}',
    if (t.until != null) 'until ${FC.date(t.until)}',
  ].join(' ');
  return '$who${parts.join(' ')}${dates.isNotEmpty ? ', $dates' : ''}. '
      'The app rates it ${Effect.label(t.effect).toLowerCase()}: ${t.meaning} '
      'What does this transit mean for me personally, and how should I handle it?';
}

// ============================================================================
// Building blocks
// ============================================================================

/// Tinted rounded-square icon used across forecast rows.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconTile(this.icon, {super.key, required this.color, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

class ForecastCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color? borderColor;

  const ForecastCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.iconColor,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color = AppColors.surface,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.card,
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  IconTile(icon!, color: iconColor ?? AppColors.primary, size: 30),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// Section heading in sentence case (no shouting ALL-CAPS).
class SectionLabel extends StatelessWidget {
  final String text;
  final String? subtitle;
  const SectionLabel(this.text, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, AppSpacing.xl, 2, AppSpacing.sm),
        child: Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: AppText.title.copyWith(fontSize: 17)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill(this.text, {super.key, required this.color, this.icon, this.solid = false});

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
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg, height: 1.25)),
          ),
        ],
      ),
    );
  }
}

class BulletList extends StatelessWidget {
  final List<String> items;
  final Color color;
  final IconData? icon;
  final TextStyle? style;
  const BulletList(this.items, {super.key, this.color = FC.accent, this.icon, this.style});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: icon != null
                      ? Icon(icon, size: 14, color: color)
                      : Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 3, right: 4, left: 2),
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(s, style: style ?? AppText.body.copyWith(fontSize: 13.5))),
              ],
            ),
          ),
      ],
    );
  }
}

class AccuracyBanner extends StatelessWidget {
  final String note;
  const AccuracyBanner(this.note, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Accuracy note',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.warningSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(note, style: AppText.caption.copyWith(color: AppColors.textPrimary, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One clean icon row: tinted icon, bold title, optional muted detail.
class ForecastIconRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final String? trailing;
  final VoidCallback? onTap;
  const ForecastIconRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                if (trailing != null && trailing!.isNotEmpty)
                  Text(trailing!, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail!, style: AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(AppRadius.md), onTap: onTap, child: row);
  }
}

/// Collapsible "Why? See the astrology" style section. Children are built only
/// when open so the default view stays light.
class WhyExpander extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool initiallyExpanded;
  final List<Widget> Function() builder;
  const WhyExpander({
    super.key,
    this.title = 'Why? See the astrology',
    this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    this.initiallyExpanded = false,
    required this.builder,
  });

  @override
  State<WhyExpander> createState() => _WhyExpanderState();
}

class _WhyExpanderState extends State<WhyExpander> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.title,
          excludeSemantics: true,
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: _open ? AppColors.cosmicLight.withValues(alpha: 0.35) : AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      IconTile(widget.icon, color: AppColors.cosmicLight, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: AppText.subtitle),
                            if (widget.subtitle != null)
                              Text(widget.subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: FC.anim(context, 200),
                        child: const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: FC.anim(context, 220),
          alignment: Alignment.topCenter,
          child: _open
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.builder())
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ============================================================================
// Score ring
// ============================================================================

class ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  final Color color;
  final Color trackColor;
  final Color textColor;
  final String? caption;

  const ScoreRing({
    super.key,
    required this.score,
    this.size = 96,
    required this.color,
    this.trackColor = const Color(0x2EFFFFFF),
    this.textColor = Colors.white,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final v = score.clamp(0, 100);
    return Semantics(
      label: 'Overall score $v out of 100',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v / 100),
          duration: FC.anim(context, 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RingPainter(t, color, trackColor, stroke: size * 0.085),
              child: Padding(
                padding: EdgeInsets.all(size * 0.2),
                child: FittedBox(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(t * 100).round()}',
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800, color: textColor, height: 1, letterSpacing: -0.5)),
                      if (caption != null)
                        Text(caption!,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7))),
                    ],
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

class _RingPainter extends CustomPainter {
  final double t;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter(this.t, this.color, this.track, {required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (t <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color || old.track != track;
}

// ============================================================================
// Hero summary
// ============================================================================

class ForecastHero extends StatelessWidget {
  final String eyebrow;
  final ForecastSummary summary;
  final bool aiGenerated;
  final Widget? footer;

  const ForecastHero({super.key, required this.eyebrow, required this.summary, this.aiGenerated = false, this.footer});

  @override
  Widget build(BuildContext context) {
    final moodColor = FC.moodOnDark(summary.mood);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ScoreRing(score: summary.overallScore, color: moodColor, size: 76, caption: 'of 100'),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Pill(Mood.label(summary.mood), color: moodColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            summary.headline.isEmpty ? 'Your guidance is ready' : summary.headline,
            style: AppText.title.copyWith(color: Colors.white, height: 1.3),
          ),
          if (summary.narrative.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(summary.narrative, style: AppText.body.copyWith(color: AppColors.textOnDarkMuted, height: 1.55)),
          ],
          if (footer != null) ...[const SizedBox(height: 14), footer!],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(aiGenerated ? Icons.auto_awesome_rounded : Icons.menu_book_rounded,
                  size: 12, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  aiGenerated ? 'Written for your chart by AI from classical rules' : 'Based on classical Vedic rules for your chart',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Life areas: compact cards with a small meter each
// ============================================================================

class AreaBars extends StatefulWidget {
  final ForecastScores scores;
  final String title;
  const AreaBars({super.key, required this.scores, this.title = 'Life areas'});

  @override
  State<AreaBars> createState() => _AreaBarsState();
}

class _AreaBarsState extends State<AreaBars> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    const keys = LifeArea.all;
    final open = _open;
    final openScore = open == null ? null : widget.scores[open];
    return ForecastCard(
      title: widget.title,
      icon: Icons.insights_rounded,
      iconColor: AppColors.cosmicLight,
      trailing: const Text('Tap for why', style: AppText.caption),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            const gap = 10.0;
            final half = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < keys.length; i++)
                  SizedBox(
                    width: (keys.length.isOdd && i == keys.length - 1) ? c.maxWidth : half,
                    child: _tile(keys[i], widget.scores[keys[i]]),
                  ),
              ],
            );
          }),
          AnimatedSize(
            duration: FC.anim(context, 200),
            alignment: Alignment.topCenter,
            child: (open != null && openScore != null && openScore.reason.isNotEmpty)
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: FC.area(open).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Why ${LifeArea.label(open).toLowerCase()} looks this way',
                            style: AppText.caption.copyWith(color: FC.area(open), fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(openScore.reason, style: AppText.body.copyWith(fontSize: 13.5, color: AppColors.textPrimary)),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _tile(String key, AreaScore a) {
    final selected = _open == key;
    final color = FC.area(key);
    final sc = FC.score(a.score);
    return Semantics(
      button: a.reason.isNotEmpty,
      expanded: a.reason.isNotEmpty ? selected : null,
      label: '${LifeArea.label(key)} ${a.score} out of 100, ${a.label}',
      child: Material(
        color: selected ? color.withValues(alpha: 0.06) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: selected ? color.withValues(alpha: 0.5) : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: a.reason.isEmpty ? null : () => setState(() => _open = selected ? null : key),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconTile(FC.areaIcon(key), color: color, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(LifeArea.label(key),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${a.score}',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: sc, height: 1.1)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(a.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedBar(value: a.score / 100, color: sc, height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const AnimatedBar({super.key, required this.value, required this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: FC.anim(context, 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: v, minHeight: height, color: color, backgroundColor: AppColors.surfaceMuted),
      ),
    );
  }
}

// ============================================================================
// Transit card (expandable)
// ============================================================================

class TransitCard extends StatefulWidget {
  final Transit transit;
  final ForecastProfile? profile;
  final bool initiallyExpanded;
  const TransitCard({super.key, required this.transit, this.profile, this.initiallyExpanded = false});

  @override
  State<TransitCard> createState() => _TransitCardState();
}

class _TransitCardState extends State<TransitCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final t = widget.transit;
    final color = FC.effect(t.effect);
    final dates = [
      if (t.since != null) 'since ${FC.date(t.since, 'd MMM yy')}',
      if (t.until != null) 'until ${FC.date(t.until, 'd MMM yy')}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: _open ? color.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              expanded: _open,
              label: '${t.title}. ${Effect.label(t.effect)}${t.retrograde ? ', retrograde' : ''}',
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.md)),
                          child: Text(FC.glyph[t.planet] ?? t.planet.characters.first,
                              style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (t.sign.isNotEmpty) '${t.sign} ${t.degree > 0 ? '${t.degree.toStringAsFixed(0)}°' : ''}'.trim(),
                                  if (t.nakshatra.isNotEmpty) t.nakshatra,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Pill(Effect.label(t.effect), color: color, icon: FC.effectIcon(t.effect)),
                                  if (t.houseFromMoon > 0) Pill('${FC.ordinal(t.houseFromMoon)} from Moon', color: FC.violet),
                                  if (t.retrograde) const Pill('Retrograde ℞', color: AppColors.warning),
                                ],
                              ),
                              if (dates.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(dates, style: AppText.caption.copyWith(fontSize: 11)),
                              ],
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: FC.anim(context, 200),
                          child: const Icon(Icons.expand_more_rounded, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: FC.anim(context, 220),
              alignment: Alignment.topCenter,
              child: _open ? _details(t) : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(Transit t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          if (t.meaning.isNotEmpty) Text(t.meaning, style: AppText.body.copyWith(color: AppColors.textPrimary)),
          if (t.realLife.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('In real life you may notice…', style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
            const SizedBox(height: 6),
            BulletList(t.realLife, color: FC.violet),
          ],
          if (t.doList.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Do', style: AppText.bodyStrong.copyWith(fontSize: 13.5, color: FC.good)),
            const SizedBox(height: 4),
            BulletList(t.doList, color: FC.good, icon: Icons.check_circle_rounded),
          ],
          if (t.avoidList.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Avoid', style: AppText.bodyStrong.copyWith(fontSize: 13.5, color: FC.bad)),
            const SizedBox(height: 4),
            BulletList(t.avoidList, color: FC.bad, icon: Icons.cancel_rounded),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Ask an astrologer about this',
            icon: Icons.forum_rounded,
            variant: AppButtonVariant.secondary,
            height: 44,
            expand: false,
            onPressed: () => askAstrologer(context, transitQuestion(t, profile: widget.profile), field: 'Transits'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Dasha, remedy, events
// ============================================================================

class DashaCard extends StatelessWidget {
  final DashaNow dasha;
  const DashaCard({super.key, required this.dasha});

  @override
  Widget build(BuildContext context) {
    Widget level(String label, String lord, DateTime? ends, double weight) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: FC.violet.withValues(alpha: 0.06 + 0.04 * weight), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Text(FC.glyph[lord] ?? (lord.isEmpty ? '?' : lord[0]),
                  style: const TextStyle(fontSize: 16, color: FC.violet, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.caption),
                  Text(lord.isEmpty ? '—' : lord, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                ],
              ),
            ),
            if (ends != null)
              Flexible(
                child: Text('until ${FC.date(ends, 'd MMM yyyy')}',
                    textAlign: TextAlign.end, maxLines: 2, style: AppText.caption.copyWith(fontSize: 11)),
              ),
          ],
        ),
      );
    }

    return ForecastCard(
      title: 'Your dasha right now',
      icon: Icons.hourglass_bottom_rounded,
      iconColor: FC.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          level('Mahadasha · the chapter of life', dasha.mahadasha, dasha.mahadashaEnds, 3),
          level('Antardasha · the current sub-chapter', dasha.antardasha, dasha.antardashaEnds, 2),
          if (dasha.pratyantardasha.isNotEmpty)
            level('Pratyantar · this few weeks', dasha.pratyantardasha, dasha.pratyantardashaEnds, 1),
          if (dasha.theme.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Text(dasha.theme, style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 13.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class RemedyCard extends StatelessWidget {
  final Remedy remedy;
  final String? luckyColor;
  final int? luckyNumber;
  const RemedyCard({super.key, required this.remedy, this.luckyColor, this.luckyNumber});

  @override
  Widget build(BuildContext context) {
    final hasLucky = (luckyColor ?? '').isNotEmpty || luckyNumber != null;
    return ForecastCard(
      title: remedy.title.isEmpty ? 'Your remedy' : remedy.title,
      icon: Icons.spa_rounded,
      iconColor: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (remedy.mantra.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Text(remedy.mantra,
                  style: AppText.bodyStrong.copyWith(fontStyle: FontStyle.italic, color: AppColors.textPrimary)),
            ),
          if (remedy.action.isNotEmpty) Text(remedy.action, style: AppText.body.copyWith(fontSize: 13.5)),
          if (remedy.color.isNotEmpty || (remedy.day ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (remedy.color.isNotEmpty) Pill('Wear ${remedy.color}', color: AppColors.primaryDark, icon: Icons.palette_rounded),
              if ((remedy.day ?? '').isNotEmpty) Pill('Best on ${remedy.day}', color: FC.violet, icon: Icons.event_rounded),
            ]),
          ],
          if (hasLucky) ...[
            const Divider(height: 24),
            Row(
              children: [
                if ((luckyColor ?? '').isNotEmpty)
                  Expanded(child: _lucky(Icons.palette_outlined, 'Lucky colour', luckyColor!)),
                if (luckyNumber != null) Expanded(child: _lucky(Icons.tag_rounded, 'Lucky number', '$luckyNumber')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _lucky(IconData icon, String label, String value) => Row(
        children: [
          IconTile(icon, color: AppColors.primary, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
              ],
            ),
          ),
        ],
      );
}

IconData eventIcon(String type) {
  switch (type) {
    case 'ingress':
      return Icons.swap_horiz_rounded;
    case 'retrograde':
      return Icons.u_turn_left_rounded;
    case 'direct':
      return Icons.arrow_forward_rounded;
    case 'solar_eclipse':
      return Icons.wb_sunny_outlined;
    case 'lunar_eclipse':
      return Icons.dark_mode_outlined;
    case 'full_moon':
      return Icons.circle;
    case 'new_moon':
      return Icons.circle_outlined;
    case 'ekadashi':
      return Icons.self_improvement_rounded;
    case 'sankranti':
      return Icons.wb_twilight_rounded;
    case 'dasha_change':
      return Icons.hourglass_bottom_rounded;
    case 'chandrashtama':
      return Icons.nightlight_round;
    default:
      return Icons.celebration_rounded;
  }
}

Color eventColor(ForecastEvent e) {
  if (e.type == 'chandrashtama' || e.isEclipse) return FC.bad;
  if (e.isFestival) return AppColors.primary;
  if (e.type == 'dasha_change') return FC.violet;
  if (e.type == 'retrograde') return AppColors.warning;
  return FC.blue;
}

class EventTile extends StatelessWidget {
  final ForecastEvent event;
  final bool showDate;
  final VoidCallback? onTap;
  const EventTile({super.key, required this.event, this.showDate = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = eventColor(event);
    final when = [
      if (showDate && event.date != null) FC.date(event.date, 'EEE d MMM'),
      if (event.time != null) event.time!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(eventIcon(event.type), color: color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(event.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
                      ),
                      if (event.importance >= 3)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.star_rounded, size: 16, color: AppColors.gold, semanticLabel: 'Important'),
                        ),
                    ],
                  ),
                  if (when.isNotEmpty) Text(when, style: AppText.caption.copyWith(fontSize: 11)),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(event.description, style: AppText.body.copyWith(fontSize: 13)),
                  ],
                  if (event.personalImpact.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'For you: ', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                        TextSpan(text: event.personalImpact),
                      ]),
                      style: AppText.body.copyWith(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChipGroup extends StatelessWidget {
  final String title;
  final List<String> items;
  final Color color;
  final IconData icon;
  const ChipGroup({super.key, required this.title, required this.items, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: AppText.bodyStrong.copyWith(fontSize: 13.5, color: color))),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Text(s, style: AppText.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Loading / error states (Blinkit / Zepto style animated shimmer loader with
// rotating "what we're doing" tips)
// ============================================================================

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2.2 - 1.1), 0.0, 0.0);
  }
}

class ForecastSkeleton extends StatefulWidget {
  const ForecastSkeleton({super.key});

  @override
  State<ForecastSkeleton> createState() => _ForecastSkeletonState();
}

class _ForecastSkeletonState extends State<ForecastSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  static const List<String> _loadingTips = [
    'Calculating planetary transits & Moon nakshatra…',
    'Reading Dasha periods & cosmic energies…',
    'Analyzing daily planetary alignments…',
  ];
  int _tipIndex = 0;
  double _last = 0;
  int _cycles = 0;

  @override
  void initState() {
    super.initState();
    // `repeat()` never reports `completed`, so detect each wrap-around of the
    // sweep and move to the next tip every second pass.
    _c.addListener(() {
      final v = _c.value;
      if (v < _last) {
        _cycles++;
        if (_cycles.isEven && mounted) setState(() => _tipIndex = (_tipIndex + 1) % _loadingTips.length);
      }
      _last = v;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _block({required double height, double? width, double radius = AppRadius.sm}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(radius)),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading your forecast',
      liveRegion: true,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rotating "what we're doing" pill.
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RotationTransition(
                      turns: _c,
                      child: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: FC.anim(context, 250),
                        child: Text(
                          _loadingTips[_tipIndex],
                          key: ValueKey(_tipIndex),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Shimmer sweep over the placeholder cards.
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) => ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => LinearGradient(
                  begin: const Alignment(-1.0, 0),
                  end: const Alignment(1.0, 0),
                  transform: _SlidingGradientTransform(slidePercent: _c.value),
                  colors: const [AppColors.surfaceMuted, AppColors.background, AppColors.surfaceMuted],
                  stops: const [0.1, 0.5, 0.9],
                ).createShader(bounds),
                child: child,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero: ring + headline.
                  _card(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _block(height: 64, width: 64, radius: 32),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _block(height: 12, width: 110),
                                const SizedBox(height: 10),
                                _block(height: 20, width: 80, radius: AppRadius.pill),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _block(height: 18),
                      const SizedBox(height: 10),
                      _block(height: 12),
                      const SizedBox(height: 8),
                      FractionallySizedBox(widthFactor: 0.7, child: _block(height: 12)),
                    ],
                  )),
                  // Icon rows.
                  _card(Column(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
                          child: Row(
                            children: [
                              _block(height: 34, width: 34, radius: 10),
                              const SizedBox(width: 12),
                              Expanded(child: _block(height: 14)),
                            ],
                          ),
                        ),
                    ],
                  )),
                  // Life-area tiles.
                  Row(
                    children: [
                      Expanded(child: _card(_block(height: 64))),
                      const SizedBox(width: 10),
                      Expanded(child: _card(_block(height: 64))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForecastError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool compact;
  const ForecastError({super.key, required this.message, required this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        children: [
          const IconTile(Icons.cloud_off_rounded, color: AppColors.danger, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(fontSize: 13)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
    return AppStateView(
      icon: Icons.cloud_off_rounded,
      color: AppColors.danger,
      title: "We couldn't read the stars just now",
      message: message,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
