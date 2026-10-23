import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import 'forecast_widgets.dart';
import 'ui/app_ui.dart';

/// Personal "Your day" summary shown near the top of Home: today's score,
/// headline and life-area bars from the day forecast, with links into the
/// full forecast. Bump [refreshTick] to force a re-fetch (pull-to-refresh).
class YourDayCard extends StatefulWidget {
  final int refreshTick;
  const YourDayCard({super.key, this.refreshTick = 0});

  @override
  State<YourDayCard> createState() => _YourDayCardState();
}

class _YourDayCardState extends State<YourDayCard> {
  DayForecast? _day;
  bool _loading = false;
  String? _error;
  bool _noKundli = false;
  String? _profileKey;
  int _token = 0;

  @override
  void didUpdateWidget(YourDayCard old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick && _profileKey != null && !_noKundli) {
      _load(force: true);
    }
  }

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    if (Vedic.activeKundli(service) == null) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _noKundli = false;
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
        _noKundli = service.lastErrorCode == 'NO_KUNDLI';
        _error = service.lastError ?? "Couldn't load your day.";
      }
    });
  }

  void _openForecast(String tab) => Navigator.pushNamed(context, AppRoutes.forecast, arguments: {'tab': tab});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    final key = '${activeFamilyId(service)}|${kundli == null ? '' : Vedic.identity(kundli)}';
    if (key != _profileKey) {
      _profileKey = key;
      _day = null;
      _error = null;
      _noKundli = false;
      if (kundli != null) {
        _loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      } else {
        _token++;
        _loading = false;
      }
    }

    if (kundli == null || (_noKundli && _day == null)) return _createKundliCta();
    if (_day != null) return _dayCard(_day!);
    if (_error != null && !_loading) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: AppStateView.error(
          compact: true,
          title: "Couldn't load your day",
          message: _error,
          onAction: () => _load(force: true),
        ),
      );
    }
    return _skeleton();
  }

  Widget _skeleton() => Semantics(
        label: 'Loading your day',
        child: const AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 110, height: 12),
                    SizedBox(height: AppSpacing.sm),
                    SkeletonBox(height: 18),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(width: 180, height: 18),
                    SizedBox(height: AppSpacing.md),
                    SkeletonBox(height: 36),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.md),
              SkeletonBox(width: 72, height: 72, radius: 36),
            ],
          ),
        ),
      );

  Widget _createKundliCta() {
    return AppCard(
      gradient: AppColors.cosmicGradient,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your day, decoded', style: AppText.caption.copyWith(color: AppColors.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Text('See how today, this week and this month unfold for you',
              style: AppText.title.copyWith(color: AppColors.textOnDark)),
          const SizedBox(height: 6),
          Text(
            'Add your birth details and we will read your own Kundli, dasha and planetary transits every day.',
            style: AppText.body.copyWith(color: AppColors.textOnDarkMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Create my Kundli',
            icon: Icons.auto_awesome_rounded,
            expand: false,
            height: 46,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.birthDetails),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(DayForecast d) {
    final moodColor = FC.moodOnDark(d.summary.mood);
    final tara = d.moon.taraBala;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final hint = d.moon.chandrashtama
        ? 'Chandrashtama today: go gently, avoid big decisions.'
        : (tara.name.isNotEmpty
            ? '${tara.name} Tara: ${tara.favorable ? 'a supportive star for you today.' : 'a testing star, so be patient.'}'
            : '');

    return Semantics(
      container: true,
      label: 'Your day: ${d.summary.headline}. Score ${d.summary.overallScore} out of 100',
      child: AppCard(
        gradient: AppColors.cosmicGradient,
        image: const DecorationImage(
          image: ResizeImage(AssetImage('assets/images/astrology-hero.jpg'), width: 900),
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
          opacity: 0.45,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => _openForecast('day'),
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
                      Text(
                        'YOUR DAY · ${FC.date(d.date, 'EEE d MMM').toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.overline.copyWith(color: AppColors.gold),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        d.summary.headline.isEmpty ? 'Your personal guidance is ready' : d.summary.headline,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(color: AppColors.textOnDark, fontSize: 17, height: 1.3),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Pill(Mood.label(d.summary.mood), color: moodColor),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ScoreRing(score: d.summary.overallScore, color: moodColor, size: 72),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (final k in LifeArea.all)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Semantics(
                        label: '${LifeArea.label(k)} ${d.scores[k].score}',
                        child: ExcludeSemantics(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 14,
                                child: FittedBox(
                                  child: Text(LifeArea.label(k),
                                      style: const TextStyle(
                                          color: AppColors.textOnDarkMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(height: 5),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: d.scores[k].score / 100),
                                duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 700),
                                builder: (context, v, _) => ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: v,
                                    minHeight: 5,
                                    color: FC.area(k),
                                    backgroundColor: Colors.white12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    d.moon.chandrashtama ? Icons.warning_amber_rounded : Icons.nightlight_round,
                    size: 16,
                    color: d.moon.chandrashtama ? AppColors.warning : AppColors.textOnDarkMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(hint, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted, fontSize: 12.5)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _action('Read full forecast', 'day', primary: true),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _action('Week', 'week')),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _action('Month', 'month')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String label, String tab, {bool primary = false}) {
    return Semantics(
      button: true,
      label: primary ? 'Read full forecast for today' : 'Open $label forecast',
      onTap: () => _openForecast(tab),
      excludeSemantics: true,
      child: Material(
        color: primary ? AppColors.primary : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => _openForecast(tab),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Center(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
