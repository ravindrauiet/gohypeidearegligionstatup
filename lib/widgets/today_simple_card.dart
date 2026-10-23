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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today for you · ${DateFormat('EEE, d MMM').format(day.date)}', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.md),
          if (day.goodFor.isNotEmpty)
            _line(Icons.thumb_up_alt_outlined, 'A good day for', day.goodFor.take(3).join(' · '), AppColors.success),
          if (avoid.isNotEmpty) _line(Icons.error_outline_rounded, 'Be careful with', avoid.join(' · '), AppColors.danger),
          if (best != null || rahu.isNotEmpty)
            _line(
              Icons.schedule_rounded,
              'Your best time today',
              [
                if (best != null) '${best.start} – ${best.end} (${_plainTimeLabel(best.label)})',
                if (rahu.isNotEmpty && rahu != '--') 'Avoid $rahu for new starts (Rahu Kaal)',
              ].join('\n'),
              AppColors.info,
            ),
          _line(Icons.lightbulb_outline_rounded, 'Why', _why(day), AppColors.primary),
          _moreLink('See full day'),
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

  Widget _line(IconData icon, String label, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(text, style: AppText.body.copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _plainTimeLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('amrit')) return 'very lucky';
    if (l.contains('abhijit')) return 'lucky midday window';
    if (l.contains('shubh')) return 'auspicious';
    if (l.contains('labh')) return 'good for gains';
    if (l.contains('hora')) return 'good planetary hour';
    return 'good time';
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
      e == Effect.favorable ? AppColors.success : (e == Effect.challenging ? AppColors.danger : AppColors.textTertiary);

  Widget _weatherCard(DayForecast day) {
    final items = _weatherTransits(day);
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your planet weather', style: AppText.subtitle),
          const SizedBox(height: 2),
          Text('How the planets are touching your life right now',
              style: AppText.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          for (final t in items) _weatherRow(t),
          _moreLink('What does this mean?'),
        ],
      ),
    );
  }

  Widget _weatherRow(Transit t) {
    final color = _effectColor(t.effect);
    final until = _until(t);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => _showTransit(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.simple, style: AppText.bodyStrong),
                  if (until.isNotEmpty) Text(until, style: AppText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
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
