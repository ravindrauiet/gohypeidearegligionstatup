import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import 'forecast_widgets.dart';
import 'ui/app_ui.dart';

/// Home "Today for you" card: plain-language guidance (good for / be careful /
/// best time) plus "Your planet weather", one simple sentence per planet.
/// Uses the same day forecast as [YourDayCard], so it costs no extra request.
/// Bump [refreshTick] to force a re-fetch (pull-to-refresh).
class TodaySimpleCard extends StatefulWidget {
  final int refreshTick;
  const TodaySimpleCard({super.key, this.refreshTick = 0});

  @override
  State<TodaySimpleCard> createState() => _TodaySimpleCardState();
}

class _TodaySimpleCardState extends State<TodaySimpleCard> {
  DayForecast? _day;
  bool _loading = false;
  String? _error;
  String? _profileKey;
  int _token = 0;

  // Slow planets first (they set the tone for weeks or months), then any fast
  // planet doing something clearly good or difficult.
  static const _weatherOrder = ['Saturn', 'Jupiter', 'Rahu', 'Ketu', 'Sun', 'Venus', 'Mars', 'Mercury'];
  static const _maxWeather = 5;

  @override
  void didUpdateWidget(TodaySimpleCard old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick && _profileKey != null) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    if (Vedic.activeKundli(service) == null) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await service.fetchDayForecast(familyId: activeFamilyId(service), forceRefresh: force);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    DayForecast? parsed;
    if (raw != null) {
      try {
        parsed = DayForecast.fromJson(raw);
      } catch (_) {}
    }
    setState(() {
      _loading = false;
      if (parsed != null) {
        _day = parsed;
      } else {
        _error = service.lastError ?? "Couldn't load today's guidance.";
      }
    });
  }

  void _openDay() => Navigator.pushNamed(context, AppRoutes.forecast, arguments: {'tab': 'day'});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    // Without a Kundli, YourDayCard already shows the create-Kundli prompt.
    if (kundli == null) return const SizedBox.shrink();

    final key = '${activeFamilyId(service)}|${Vedic.identity(kundli)}';
    if (key != _profileKey) {
      _profileKey = key;
      _day = null;
      _error = null;
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final day = _day;
    if (day == null) {
      if (_error != null && !_loading) {
        return AppCard(
          padding: EdgeInsets.zero,
          child: AppStateView.error(
            compact: true,
            title: "Couldn't load today's guidance",
            message: _error,
            onAction: () => _load(force: true),
          ),
        );
      }
      return Semantics(
        label: "Loading today's guidance",
        child: const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 160, height: 16),
              SizedBox(height: AppSpacing.md),
              SkeletonBox(height: 40),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(height: 40),
              SizedBox(height: AppSpacing.sm),
              SkeletonBox(height: 40),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _todayCard(day),
        const SizedBox(height: AppSpacing.lg),
        _weatherSection(day),
      ],
    );
  }

  // ---------------------------------------------------------------- today
  bool _friendly(DayForecast d) => !d.moon.chandrashtama && d.moon.taraBala.favorable;

  String _moodTitle(DayForecast d) {
    if (d.moon.chandrashtama) return 'A sensitive day, go gently';
    return _friendly(d) ? 'A friendly day for you' : 'Go slow today';
  }

  Widget _todayCard(DayForecast day) {
    // Rahu Kaal gets its own place on the timeline, so drop it from the list.
    final avoid = day.avoid.where((a) => !a.contains('Rahu Kaal')).take(3).toList();
    final best = day.bestTimes.isNotEmpty ? day.bestTimes.first : null;
    final rahu = day.panchang.rahuKaal.trim();
    final hasRahu = rahu.isNotEmpty && rahu != '--';
    final friendly = _friendly(day);
    final tone = friendly ? AppColors.success : AppColors.info;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: mood headline, date and the Moon's reason, on a soft tint.
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tone.withValues(alpha: 0.12), tone.withValues(alpha: 0.02)],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('EEEE, d MMM').format(day.date),
                          style: AppText.caption.copyWith(color: tone, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(_moodTitle(day), style: AppText.title),
                      const SizedBox(height: 6),
                      Text(_why(day),
                          style: AppText.body.copyWith(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _MoonDisc(color: tone),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (day.goodFor.isNotEmpty || avoid.isNotEmpty)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (day.goodFor.isNotEmpty)
                          Expanded(
                            child: _listPanel(Icons.check_circle_rounded, 'A good day for',
                                day.goodFor.take(3).toList(), AppColors.success),
                          ),
                        if (day.goodFor.isNotEmpty && avoid.isNotEmpty) const SizedBox(width: AppSpacing.sm),
                        if (avoid.isNotEmpty)
                          Expanded(child: _listPanel(Icons.cancel_rounded, 'Be careful with', avoid, AppColors.danger)),
                      ],
                    ),
                  ),
                if (best != null || hasRahu) ...[
                  const SizedBox(height: AppSpacing.md),
                  _DayTimeline(
                    bestLabel: best != null ? _plainTimeLabel(best.label) : null,
                    bestStart: best?.start,
                    bestEnd: best?.end,
                    rahu: hasRahu ? rahu : null,
                    date: day.date,
                  ),
                ],
                _moreLink('See full day'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tinted panel with a heading and up to three short lines.
  Widget _listPanel(IconData icon, String label, List<String> items, Color color) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  maxLines: 2,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color, height: 1.2)),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                        width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 13, height: 1.35, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // A link whose text can wrap on narrow screens with large text.
  Widget _moreLink(String text) {
    return InkWell(
      onTap: _openDay,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Flexible(
              child: Text(text,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  String _plainTimeLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('amrit')) return 'Very lucky';
    if (l.contains('abhijit')) return 'Lucky midday';
    if (l.contains('shubh')) return 'Auspicious';
    if (l.contains('labh')) return 'Good for gains';
    if (l.contains('hora')) return 'Good hour';
    return 'Good time';
  }

  String _why(DayForecast day) {
    final m = day.moon;
    if (m.chandrashtama) {
      return 'The Moon is in a sensitive spot for you today, so feelings run high. Keep plans simple and rest well.';
    }
    if (m.taraBala.favorable) {
      return 'The Moon is in a friendly star (${m.taraBala.name}) for you today, so things tend to go your way.';
    }
    return 'The Moon is in a testing star (${m.taraBala.name}) for you today. Go slowly and double-check important things.';
  }

  // -------------------------------------------------------------- weather
  List<Transit> _weatherTransits(DayForecast day) {
    final byPlanet = {for (final t in day.transits) t.planet: t};
    final picked = <Transit>[];
    for (final p in _weatherOrder) {
      final t = byPlanet[p];
      if (t == null) continue;
      final slow = Transit.slowPlanets.contains(p);
      if (slow || t.effect != Effect.neutral) picked.add(t);
      if (picked.length == _maxWeather) break;
    }
    return picked;
  }

  String _until(Transit t) {
    final u = t.until;
    if (u == null) return '';
    final sameYear = u.year == DateTime.now().year;
    return 'until ${DateFormat(sameYear ? 'd MMM' : 'MMM yyyy').format(u)}';
  }

  Color _effectColor(String e) =>
      e == Effect.favorable ? AppColors.success : (e == Effect.challenging ? AppColors.danger : AppColors.cosmicLight);

  String _effectLabel(String e) =>
      e == Effect.favorable ? 'Supportive' : (e == Effect.challenging ? 'Testing' : 'Mixed');

  static const _planetAbbr = {
    'Sun': 'Su',
    'Moon': 'Mo',
    'Mars': 'Ma',
    'Mercury': 'Me',
    'Jupiter': 'Ju',
    'Venus': 'Ve',
    'Saturn': 'Sa',
    'Rahu': 'Ra',
    'Ketu': 'Ke',
  };

  /// "Your planet weather": a heading, then one swipeable card per planet.
  Widget _weatherSection(DayForecast day) {
    final items = _weatherTransits(day);
    if (items.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final screen = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Your planet weather', style: AppText.title),
        const SizedBox(height: 2),
        Text('Swipe to see how each planet touches your life',
            style: AppText.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        // Full-bleed rail: break out of the page padding to the screen edges.
        SizedBox(
          height: 172 + 46 * (scale - 1) * 2,
          child: OverflowBox(
            maxWidth: screen,
            minWidth: screen,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: AppSpacing.pagePadding,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => _weatherCard(items[i]),
            ),
          ),
        ),
        _moreLink('What does this mean?'),
      ],
    );
  }

  Widget _weatherCard(Transit t) {
    final color = _effectColor(t.effect);
    final until = _until(t);
    return SizedBox(
      width: 232,
      child: Semantics(
        button: true,
        label: '${t.planet}. ${_effectLabel(t.effect)}. ${t.simple}. $until',
        onTap: () => _showTransit(t),
        excludeSemantics: true,
        child: AppCard(
          onTap: () => _showTransit(t),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                              border: Border.all(color: color.withValues(alpha: 0.25)),
                            ),
                            child: Text(_planetAbbr[t.planet] ?? t.planet.characters.take(2).toString(),
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.planet, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                                if (until.isNotEmpty)
                                  Text(until, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                              ],
                            ),
                          ),
                          AppBadge(label: _effectLabel(t.effect), color: color),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          t.simple,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      const Row(
                        children: [
                          Text('Read more',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransit(Transit t) {
    showAppSheet<void>(
      context,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.simple, style: AppText.title),
              if (_until(t).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_until(t), style: AppText.caption),
              ],
              if (t.realLife.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                const Text('You may notice', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.xs),
                BulletList(t.realLife, color: AppColors.primary),
              ],
              if (t.doList.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('What helps', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.xs),
                BulletList(t.doList, color: AppColors.success),
              ],
              if (t.avoidList.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('Better to avoid', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.xs),
                BulletList(t.avoidList, color: AppColors.danger),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Ask an astrologer about this',
                icon: Icons.auto_awesome_rounded,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  askAstrologer(context, transitQuestion(t));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glowing moon disc in the card header.
class _MoonDisc extends StatelessWidget {
  final Color color;
  const _MoonDisc({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFFF8E1), Color(0xFFFFE08A), Color(0xFFF5B83D)],
        ),
        boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1)],
      ),
      child: Icon(Icons.nightlight_round, color: color.withValues(alpha: 0.75), size: 24),
    );
  }
}

/// The day from 6 AM to 10 PM as a bar: the best window in green, Rahu Kaal
/// in red and a "Now" marker, with the times spelled out underneath.
class _DayTimeline extends StatelessWidget {
  final String? bestLabel;
  final String? bestStart;
  final String? bestEnd;
  final String? rahu;
  final DateTime date;

  const _DayTimeline({
    required this.bestLabel,
    required this.bestStart,
    required this.bestEnd,
    required this.rahu,
    required this.date,
  });

  static const _dayStart = 6 * 60;
  static const _dayEnd = 22 * 60;

  /// Minutes since midnight for "07:45 AM"; null if it can't be read.
  static int? _minutes(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').firstMatch(s);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final ap = m.group(3)?.toLowerCase();
    if (ap == 'pm' && h != 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    return h * 60 + min;
  }

  static (int, int)? _range(String? s) {
    if (s == null) return null;
    final parts = s.split(RegExp(r'\s*[-–]\s*'));
    if (parts.length < 2) return null;
    final a = _minutes(parts[0]);
    final b = _minutes(parts[1]);
    return a == null || b == null || b <= a ? null : (a, b);
  }

  double _pos(int minutes) => ((minutes - _dayStart) / (_dayEnd - _dayStart)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final best = (bestStart != null && bestEnd != null) ? _range('$bestStart - $bestEnd') : null;
    final rahuRange = _range(rahu);
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    final nowMin = now.hour * 60 + now.minute;
    final showNow = isToday && nowMin >= _dayStart && nowMin <= _dayEnd;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.warningSoft, AppColors.primarySoft]),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.wb_sunny_rounded, size: 16, color: AppColors.warning),
              Text('Your best time today',
                  style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
              if (bestLabel != null) AppBadge(label: bestLabel!, color: AppColors.success),
            ],
          ),
          if (bestStart != null && bestEnd != null) ...[
            const SizedBox(height: 2),
            Text('$bestStart – $bestEnd', style: AppText.subtitle.copyWith(fontSize: 17)),
          ],
          if (best != null || rahuRange != null) ...[
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              Widget seg((int, int) r, Color color) => Positioned(
                    left: w * _pos(r.$1),
                    width: (w * (_pos(r.$2) - _pos(r.$1))).clamp(6.0, w),
                    top: 8,
                    height: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    ),
                  );
              return SizedBox(
                height: 26,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 8,
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                    if (best != null) seg(best, AppColors.success),
                    if (rahuRange != null) seg(rahuRange, AppColors.danger),
                    if (showNow)
                      Positioned(
                        left: w * _pos(nowMin) - 1.5,
                        top: 2,
                        width: 3,
                        height: 22,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            // Hour marks at their real places on the bar.
            LayoutBuilder(builder: (context, c) {
              const style = TextStyle(fontSize: 10.5, color: AppColors.textTertiary, fontWeight: FontWeight.w500);
              Widget mark(String t, int minutes) => Align(
                    alignment: Alignment(_pos(minutes) * 2 - 1, 0),
                    child: Text(t, maxLines: 1, textScaler: TextScaler.noScaling, style: style),
                  );
              return SizedBox(
                height: 14,
                child: Stack(children: [
                  mark('6 AM', 6 * 60),
                  mark('12 PM', 12 * 60),
                  mark('6 PM', 18 * 60),
                  mark('10 PM', 22 * 60),
                ]),
              );
            }),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              if (best != null) const _Legend(color: AppColors.success, label: 'Best time'),
              if (rahu != null) _Legend(color: AppColors.danger, label: 'Rahu Kaal $rahu · avoid new starts'),
              if (showNow) const _Legend(color: AppColors.textPrimary, label: 'Now'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: AppText.caption.copyWith(color: AppColors.textSecondary))),
      ],
    );
  }
}
