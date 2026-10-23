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
        const SizedBox(height: AppSpacing.sm),
        _weatherCard(day),
      ],
    );
  }

  // ---------------------------------------------------------------- today
  Widget _todayCard(DayForecast day) {
    // Rahu Kaal gets its own "avoid" time line, so drop it from the list.
    final avoid = day.avoid.where((a) => !a.contains('Rahu Kaal')).take(3).toList();
    final best = day.bestTimes.isNotEmpty ? day.bestTimes.first : null;
    final rahu = day.panchang.rahuKaal.trim();

    final hasRahu = rahu.isNotEmpty && rahu != '--';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Today for you', style: AppText.title)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(DateFormat('EEE, d MMM').format(day.date),
                    style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _moodNote(day),
          if (day.goodFor.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _chipGroup(Icons.check_circle_rounded, 'A good day for', day.goodFor.take(3).toList(), AppColors.success),
          ],
          if (avoid.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _chipGroup(Icons.do_not_disturb_on_rounded, 'Be careful with', avoid, AppColors.danger),
          ],
          if (best != null || hasRahu) ...[
            const SizedBox(height: AppSpacing.md),
            _bestTime(best, hasRahu ? rahu : null),
          ],
          _moreLink('See full day'),
        ],
      ),
    );
  }

  /// The day's "why" as one soft line at the top: the Moon sets the mood.
  Widget _moodNote(DayForecast day) {
    final friendly = !day.moon.chandrashtama && day.moon.taraBala.favorable;
    final color = friendly ? AppColors.success : AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.nightlight_round, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(_why(day),
                style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// A small heading followed by short tinted chips, one per item.
  Widget _chipGroup(IconData icon, String label, List<String> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Text(item,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
              ),
          ],
        ),
      ],
    );
  }

  /// Highlighted best-time window, with Rahu Kaal as a quiet "avoid" line.
  Widget _bestTime(BestTime? best, String? rahu) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.warningSoft, AppColors.primarySoft]),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (best != null)
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.wb_sunny_rounded, size: 20, color: AppColors.warning),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Your best time today',
                              style:
                                  AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                          AppBadge(label: _plainTimeLabel(best.label), color: AppColors.success),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${best.start} – ${best.end}', style: AppText.subtitle.copyWith(fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
          if (best == null)
            Text('Your best time today',
                style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          if (rahu != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.block_rounded, size: 14, color: AppColors.danger),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Avoid $rahu for new starts (Rahu Kaal)',
                      style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
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

  /// Rows shown before "Show more", so the card stays light.
  static const _weatherPreview = 3;
  bool _allWeather = false;

  Widget _weatherCard(DayForecast day) {
    final items = _weatherTransits(day);
    if (items.isEmpty) return const SizedBox.shrink();
    final hidden = items.length - _weatherPreview;
    final visible = _allWeather || hidden <= 0 ? items : items.take(_weatherPreview).toList();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your planet weather', style: AppText.title),
          const SizedBox(height: 2),
          Text('How the planets are touching your life right now',
              style: AppText.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const Divider(indent: 52),
            _weatherRow(visible[i]),
          ],
          if (hidden > 0)
            InkWell(
              onTap: () => setState(() => _allWeather = !_allWeather),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_allWeather ? 'Show less' : 'Show $hidden more',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    Icon(_allWeather ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          _moreLink('What does this mean?'),
        ],
      ),
    );
  }

  Widget _weatherRow(Transit t) {
    final color = _effectColor(t.effect);
    final until = _until(t);
    final meta = [t.planet, if (until.isNotEmpty) until].join(' · ');
    return Semantics(
      button: true,
      label: '${t.simple}. ${_effectLabel(t.effect)}. $meta',
      onTap: () => _showTransit(t),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _showTransit(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Text(_planetAbbr[t.planet] ?? t.planet.characters.take(2).toString(),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.simple, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AppBadge(label: _effectLabel(t.effect), color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
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
