import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../services/backend_service.dart';

// ============================================================================
// Palette & formatting
// ============================================================================

class FC {
  FC._();
  static const bg = Color(0xFFFCF7F1);
  static const accent = Color(0xFFFB9548);
  static const ink = Colors.black;
  static const heroA = Color(0xFF1E1A38);
  static const heroB = Color(0xFF2E2452);
  static const good = Color(0xFF059669);
  static const blue = Color(0xFF2F80ED);
  static const bad = Color(0xFFE5484D);
  static const neutral = Color(0xFF6B7280);
  static const violet = Color(0xFF6C63FF);

  /// Score colour for light surfaces.
  static Color score(int s) {
    if (s >= 75) return good;
    if (s >= 60) return blue;
    if (s >= 42) return accent;
    return bad;
  }

  /// Mood accent for the dark hero card.
  static Color moodOnDark(String mood) {
    switch (mood) {
      case Mood.excellent:
        return const Color(0xFF34D399);
      case Mood.good:
        return const Color(0xFF7DD3FC);
      case Mood.challenging:
        return const Color(0xFFFCA5A5);
      default:
        return const Color(0xFFFDBA74);
    }
  }

  static Color effect(String e) => e == Effect.favorable ? good : (e == Effect.challenging ? bad : neutral);

  static IconData effectIcon(String e) => e == Effect.favorable
      ? Icons.trending_up_rounded
      : (e == Effect.challenging ? Icons.warning_amber_rounded : Icons.remove_rounded);

  static Color area(String key) {
    switch (key) {
      case LifeArea.career:
        return const Color(0xFFFF9800);
      case LifeArea.love:
        return const Color(0xFFE83D66);
      case LifeArea.money:
        return const Color(0xFF059669);
      case LifeArea.health:
        return const Color(0xFF0EA5E9);
      default:
        return const Color(0xFF8B5CF6);
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
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? Colors.black.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: iconColor ?? FC.accent),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Semantics(
          header: true,
          child: Text(text.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
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
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
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
                Expanded(
                  child: Text(s, style: style ?? TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade800)),
                ),
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
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FC.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(note, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF7C2D12))),
            ),
          ],
        ),
      ),
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
    this.trackColor = const Color(0x33FFFFFF),
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
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _RingPainter(t, color, trackColor, stroke: size * 0.09),
              child: Padding(
                padding: EdgeInsets.all(size * 0.2),
                child: FittedBox(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(t * 100).round()}',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: textColor, height: 1)),
                      if (caption != null)
                        Text(caption!,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor.withValues(alpha: 0.7))),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [FC.heroA, FC.heroB], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: FC.heroA.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    Pill(Mood.label(summary.mood), color: moodColor, icon: Icons.brightness_5_rounded),
                    const SizedBox(height: 10),
                    Text(
                      summary.headline.isEmpty ? 'Your guidance is ready' : summary.headline,
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ScoreRing(score: summary.overallScore, color: moodColor, size: 84, caption: '/100'),
            ],
          ),
          if (summary.narrative.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(summary.narrative, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
          ],
          if (footer != null) ...[const SizedBox(height: 14), footer!],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(aiGenerated ? Icons.auto_awesome : Icons.menu_book_rounded, size: 12, color: Colors.white38),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  aiGenerated ? 'Written for your chart by AI from classical rules' : 'Based on classical Vedic rules for your chart',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
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
// Life-area bars
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
    return ForecastCard(
      title: widget.title,
      icon: Icons.insights_rounded,
      trailing: Text('Tap for why', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      child: Column(
        children: [
          for (final k in LifeArea.all) _row(k, widget.scores[k]),
        ],
      ),
    );
  }

  Widget _row(String key, AreaScore a) {
    final open = _open == key;
    final color = FC.area(key);
    return Semantics(
      button: a.reason.isNotEmpty,
      expanded: a.reason.isNotEmpty ? open : null,
      label: '${LifeArea.label(key)} ${a.score} out of 100, ${a.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: a.reason.isEmpty ? null : () => setState(() => _open = open ? null : key),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    Icon(FC.areaIcon(key), size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(LifeArea.label(key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    Flexible(
                      child: Text('${a.score} · ${a.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: FC.score(a.score))),
                    ),
                    if (a.reason.isNotEmpty)
                      Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              AnimatedBar(value: a.score / 100, color: color),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: open
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(a.reason, style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade800)),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
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
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: v, minHeight: height, color: color, backgroundColor: Colors.grey.shade200),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: _open ? 0.45 : 0.18)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
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
                  padding: const EdgeInsets.all(12),
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: Text(FC.glyph[t.planet] ?? t.planet.characters.first,
                              style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (t.sign.isNotEmpty) '${t.sign} ${t.degree > 0 ? '${t.degree.toStringAsFixed(0)}°' : ''}'.trim(),
                                  if (t.nakshatra.isNotEmpty) t.nakshatra,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Pill(Effect.label(t.effect), color: color, icon: FC.effectIcon(t.effect)),
                                  if (t.houseFromMoon > 0) Pill('${FC.ordinal(t.houseFromMoon)} from Moon', color: FC.violet),
                                  if (t.retrograde) const Pill('Retrograde ℞', color: Color(0xFFB45309)),
                                ],
                              ),
                              if (dates.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(dates, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ],
                          ),
                        ),
                        Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          if (t.meaning.isNotEmpty)
            Text(t.meaning, style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.grey.shade900)),
          if (t.realLife.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('In real life you may notice…', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 6),
            BulletList(t.realLife, color: FC.violet),
          ],
          if (t.doList.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Do', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: FC.good)),
            const SizedBox(height: 4),
            BulletList(t.doList, color: FC.good, icon: Icons.check_circle_rounded),
          ],
          if (t.avoidList.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Avoid', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: FC.bad)),
            const SizedBox(height: 4),
            BulletList(t.avoidList, color: FC.bad, icon: Icons.cancel_rounded),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => askAstrologer(context, transitQuestion(t, profile: widget.profile), field: 'Transits'),
              icon: const Icon(Icons.forum_rounded, size: 16),
              label: const Text('Ask an astrologer about this'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black26),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
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
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: FC.violet.withValues(alpha: 0.08 + 0.06 * weight), shape: BoxShape.circle),
              child: Text(FC.glyph[lord] ?? (lord.isEmpty ? '?' : lord[0]),
                  style: const TextStyle(fontSize: 16, color: FC.violet, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  Text(lord.isEmpty ? '—' : lord,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
            ),
            if (ends != null)
              Flexible(
                child: Text('until ${FC.date(ends, 'd MMM yyyy')}',
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: FC.violet.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
              child: Text(dasha.theme, style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey.shade900)),
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
      iconColor: const Color(0xFFB45309),
      color: const Color(0xFFFFFBF5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (remedy.mantra.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: FC.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(remedy.mantra,
                  style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, height: 1.4)),
            ),
          if (remedy.action.isNotEmpty)
            Text(remedy.action, style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey.shade800)),
          if (remedy.color.isNotEmpty || (remedy.day ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (remedy.color.isNotEmpty) Pill('Wear ${remedy.color}', color: const Color(0xFFB45309), icon: Icons.palette_rounded),
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
          Icon(icon, size: 18, color: FC.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(value,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
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
  if (e.isFestival) return const Color(0xFF9333EA);
  if (e.type == 'dasha_change') return FC.violet;
  if (e.type == 'retrograde') return const Color(0xFFB45309);
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
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(eventIcon(event.type), size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      ),
                      if (event.importance >= 3)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.star_rounded, size: 16, color: FC.accent, semanticLabel: 'Important'),
                        ),
                    ],
                  ),
                  if (when.isNotEmpty) Text(when, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(event.description, style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade800)),
                  ],
                  if (event.personalImpact.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'For you: ', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                        TextSpan(text: event.personalImpact),
                      ]),
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade900),
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
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color))),
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
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade900)),
              ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Loading / error states
// ============================================================================

class ForecastSkeleton extends StatefulWidget {
  const ForecastSkeleton({super.key});

  @override
  State<ForecastSkeleton> createState() => _ForecastSkeletonState();
}

class _ForecastSkeletonState extends State<ForecastSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double radius = 20}) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(radius)),
        );
    return Semantics(
      label: 'Loading your forecast',
      liveRegion: true,
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            box(190, radius: 24),
            box(210),
            box(120),
            box(90),
            box(90),
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
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 44),
          const SizedBox(height: 12),
          const Text("We couldn't read the stars just now",
              textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ],
      ),
    );
  }
}
