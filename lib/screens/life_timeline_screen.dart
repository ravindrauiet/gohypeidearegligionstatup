import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../services/backend_service.dart';
import '../widgets/forecast_widgets.dart';
import '../widgets/ui/app_ui.dart';
import 'kundli_view_screen.dart' show KundliEmptyState, Vedic, showKundliProfilePicker;

/// Vertical timeline of the big periods of life: Sade Sati, slow transits and dashas.
/// Route arguments (optional): `{familyId: int}`.
class LifeTimelineScreen extends StatefulWidget {
  final int? familyId;
  const LifeTimelineScreen({super.key, this.familyId});

  factory LifeTimelineScreen.fromArgs(Object? args) =>
      LifeTimelineScreen(familyId: args is Map ? fIntOrNull(args['familyId']) : null);

  @override
  State<LifeTimelineScreen> createState() => _LifeTimelineScreenState();
}

class _Filter {
  final String label;
  final Set<String> kinds;
  const _Filter(this.label, this.kinds);
}

const _filters = [
  _Filter('Sade Sati', {TimelineKind.sadeSati, TimelineKind.ashtamaShani, TimelineKind.kantakaShani}),
  _Filter('Saturn', {TimelineKind.saturn}),
  _Filter('Jupiter', {TimelineKind.jupiter}),
  _Filter('Rahu–Ketu', {TimelineKind.rahuKetu}),
  _Filter('Dashas', {TimelineKind.mahadasha, TimelineKind.antardasha}),
];

/// Quiet identity colour per period kind (used for the small kind label only;
/// good / challenging is always shown with the semantic colours).
Color kindColor(String kind) {
  switch (kind) {
    case TimelineKind.sadeSati:
    case TimelineKind.ashtamaShani:
    case TimelineKind.kantakaShani:
      return AppColors.cosmic;
    case TimelineKind.saturn:
      return AppColors.cosmicLight;
    case TimelineKind.jupiter:
      return AppColors.primaryDark;
    case TimelineKind.rahuKetu:
      return AppColors.info;
    case TimelineKind.mahadasha:
      return AppColors.cosmicLight;
    default:
      return AppColors.textSecondary;
  }
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case TimelineKind.sadeSati:
    case TimelineKind.ashtamaShani:
    case TimelineKind.kantakaShani:
    case TimelineKind.saturn:
      return Icons.hourglass_bottom_rounded;
    case TimelineKind.jupiter:
      return Icons.wb_sunny_rounded;
    case TimelineKind.rahuKetu:
      return Icons.sync_alt_rounded;
    default:
      return Icons.auto_stories_rounded;
  }
}

class _LifeTimelineScreenState extends State<LifeTimelineScreen> {
  late final BackendService _service;
  final ScrollController _scroll = ScrollController();
  final GlobalKey _hereKey = GlobalKey();

  int? _familyId;
  int? _observedSelection;
  LifeTimeline? _data;
  bool _loading = false;
  String? _error;
  bool _noKundli = false;
  int _token = 0;
  _Filter? _filter;

  @override
  void initState() {
    super.initState();
    _service = Provider.of<BackendService>(context, listen: false);
    _observedSelection = activeFamilyId(_service);
    _familyId = widget.familyId ?? _observedSelection;
    _service.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    final id = activeFamilyId(_service);
    if (id == _observedSelection || !mounted) return;
    _observedSelection = id;
    setState(() {
      _familyId = id;
      _data = null;
    });
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _noKundli = false;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await _service.fetchLifeTimeline(familyId: _familyId, forceRefresh: force);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    LifeTimeline? parsed;
    if (raw != null) {
      try {
        parsed = LifeTimeline.fromJson(raw);
      } catch (_) {}
    }
    setState(() {
      _loading = false;
      if (parsed != null) {
        _data = parsed;
      } else {
        _noKundli = _service.lastErrorCode == 'NO_KUNDLI';
        _error = _service.lastError ?? 'Could not load your life timeline.';
      }
    });
    if (parsed != null) _scrollToNow();
  }

  void _scrollToNow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _hereKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.25, duration: FC.anim(context, 450), curve: Curves.easeOutCubic);
    });
  }

  bool _isCurrent(TimelinePeriod p, DateTime now) => p.current || p.contains(now);

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    var name = _data?.meta.profile.name ?? '';
    if (name.isEmpty) name = Vedic.displayName(Vedic.activeKundli(service), service: service);

    Widget body;
    if (_noKundli && _data == null) {
      body = const KundliEmptyState();
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(force: true),
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
          child: _data != null
              ? _content(_data!)
              : (_error != null && !_loading
                  ? ForecastError(message: _error!, onRetry: () => _load(force: true))
                  : const ForecastSkeleton()),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Life timeline', maxLines: 1, overflow: TextOverflow.ellipsis),
            if (name.isNotEmpty)
              Text('for $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch profile',
            icon: const Icon(Icons.people_alt_outlined),
            onPressed: () => showKundliProfilePicker(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }

  Widget _content(LifeTimeline data) {
    final now = data.now;
    final available = _filters.where((f) => data.periods.any((p) => f.kinds.contains(p.kind))).toList();
    final filter = (_filter != null && available.contains(_filter)) ? _filter : null;
    final periods = filter == null ? data.periods : data.periods.where((p) => filter.kinds.contains(p.kind)).toList();
    final current = data.periods.where((p) => _isCurrent(p, now)).toList();

    // "You are here" goes after the last period that has already started.
    var hereIndex = 0;
    for (var i = 0; i < periods.length; i++) {
      final s = periods[i].start;
      if (s != null && !s.isAfter(now)) hereIndex = i + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.meta.accuracyNote != null) AccuracyBanner(data.meta.accuracyNote!),
        _nowHero(current, data),
        if (available.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('All', filter == null, () => setState(() => _filter = null)),
              for (final f in available) _chip(f.label, filter == f, () => setState(() => _filter = f)),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        const _EffectLegend(),
        const SizedBox(height: AppSpacing.md),
        if (periods.isEmpty)
          const AppStateView(
            icon: Icons.filter_alt_off_rounded,
            title: 'Nothing to show here',
            message: 'No periods match this filter. Try "All".',
            compact: true,
          ),
        for (var i = 0; i <= periods.length; i++) ...[
          if (i == hereIndex && periods.isNotEmpty) _hereMarker(now),
          if (i < periods.length) _periodTile(periods[i], data, _isCurrent(periods[i], now), i == periods.length - 1),
        ],
      ],
    );
  }

  Widget _nowHero(List<TimelinePeriod> current, LifeTimeline data) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where you are now',
              style: AppText.caption.copyWith(color: AppColors.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            current.isEmpty
                ? 'A quieter stretch with no major Saturn, Jupiter or node pressure.'
                : 'You are moving through ${current.length} major ${current.length == 1 ? 'period' : 'periods'} right now.',
            style: AppText.title.copyWith(color: Colors.white, height: 1.3),
          ),
          if (current.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in current)
                  Semantics(
                    button: true,
                    label: 'Open ${p.title}',
                    excludeSemantics: true,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _openDetails(p, data),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: _effectOnDark(p.effect), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(p.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Slow planets and dashas set the background of your life. Knowing which chapter you are in explains a lot.',
            style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted, height: 1.45),
          ),
        ],
      ),
    );
  }

  static Color _effectOnDark(String effect) => effect == Effect.favorable
      ? FC.moodOnDark(Mood.excellent)
      : (effect == Effect.challenging ? FC.moodOnDark(Mood.challenging) : FC.moodOnDark(Mood.mixed));

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.primarySoft,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        color: selected ? AppColors.primaryDark : AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 13,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.4 : 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
    );
  }

  Widget _hereMarker(DateTime now) {
    return Padding(
      key: _hereKey,
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        label: 'You are here, ${FC.date(now)}',
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: AppShadows.glow(AppColors.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('You are here · ${FC.date(now, 'd MMM yyyy')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: AppColors.primary.withValues(alpha: 0.3))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodTile(TimelinePeriod p, LifeTimeline data, bool isCurrent, bool isLast) {
    final kc = kindColor(p.kind);
    final ec = FC.effect(p.effect);
    final range = (p.start != null && p.end != null)
        ? '${FC.date(p.start, 'MMM yyyy')} – ${FC.date(p.end, 'MMM yyyy')}'
        : (p.start != null ? 'From ${FC.date(p.start, 'MMM yyyy')}' : '');
    final past = p.end != null && p.end!.isBefore(data.now);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  bottom: isLast ? null : 0,
                  height: isLast ? 22 : null,
                  child: Container(width: 2, color: AppColors.border),
                ),
                Positioned(
                  top: 18,
                  child: Container(
                    width: isCurrent ? 14 : 10,
                    height: isCurrent ? 14 : 10,
                    decoration: BoxDecoration(
                      color: isCurrent ? ec : AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: ec, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Semantics(
                button: true,
                label: '${p.title}, ${TimelineKind.label(p.kind)}, $range, ${Effect.label(p.effect)}'
                    '${isCurrent ? ', happening now' : ''}',
                child: Opacity(
                  opacity: past && !isCurrent ? 0.78 : 1,
                  child: Material(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.card,
                      side: BorderSide(
                          color: isCurrent ? AppColors.primary : AppColors.border, width: isCurrent ? 1.5 : 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openDetails(p, data),
                      child: ExcludeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Semantic stripe: green supportive, red challenging, grey mixed.
                            Container(width: 4, color: ec),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(_kindIcon(p.kind), size: 14, color: kc),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            [TimelineKind.label(p.kind), if (p.phase != null) '${p.phase} phase'].join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.caption.copyWith(color: kc, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 6),
                                          const AppBadge(label: 'Now', color: Colors.white, background: AppColors.primary),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(p.title, style: AppText.subtitle),
                                    if (range.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(range, style: AppText.caption),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Pill(Effect.label(p.effect), color: ec, icon: FC.effectIcon(p.effect)),
                                        ),
                                        const SizedBox(width: 10),
                                        Text('Intensity', style: AppText.caption.copyWith(fontSize: 11)),
                                        const SizedBox(width: 6),
                                        for (var i = 1; i <= 3; i++)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.only(right: 3),
                                            decoration: BoxDecoration(
                                              color: i <= p.intensity ? ec : ec.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (p.summary.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(p.summary,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.body.copyWith(fontSize: 13)),
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
            ),
          ),
        ],
      ),
    );
  }

  void _openDetails(TimelinePeriod p, LifeTimeline data) {
    showAppSheet<void>(
      context,
      builder: (ctx) => TimelinePeriodSheet(period: p, profile: data.meta.profile, isCurrent: _isCurrent(p, data.now)),
    );
  }
}

class _EffectLegend extends StatelessWidget {
  const _EffectLegend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Flexible(child: Text(t, style: AppText.caption.copyWith(color: AppColors.textSecondary))),
        ]);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(FC.effect(Effect.favorable), 'Supportive'),
        item(FC.effect(Effect.challenging), 'Challenging'),
        item(FC.effect(Effect.neutral), 'Mixed'),
      ],
    );
  }
}

class TimelinePeriodSheet extends StatelessWidget {
  final TimelinePeriod period;
  final ForecastProfile profile;
  final bool isCurrent;
  const TimelinePeriodSheet({super.key, required this.period, required this.profile, this.isCurrent = false});

  String _question() {
    final p = period;
    final who = profile.isFamily && profile.name.isNotEmpty ? 'For my ${profile.relationship ?? 'family member'} ${profile.name}: ' : '';
    final when = (p.start != null && p.end != null) ? ' from ${FC.date(p.start)} to ${FC.date(p.end)}' : '';
    return '$who${isCurrent ? 'I am currently in' : 'My chart shows'} ${p.title} (${TimelineKind.label(p.kind)}'
        '${p.phase != null ? ', ${p.phase} phase' : ''})$when. ${p.summary} '
        'How does this period affect me personally and what should I do during it?';
  }

  @override
  Widget build(BuildContext context) {
    final p = period;
    final ec = FC.effect(p.effect);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconTile(_kindIcon(p.kind), color: ec, size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.title, style: AppText.headline.copyWith(fontSize: 20))),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(TimelineKind.label(p.kind), color: kindColor(p.kind)),
                  if (p.phase != null) Pill('${p.phase} phase', color: AppColors.cosmicLight),
                  Pill(Effect.label(p.effect), color: ec, icon: FC.effectIcon(p.effect)),
                  Pill('Intensity ${p.intensity}/3', color: FC.neutral),
                  if (isCurrent) const Pill('Happening now', color: AppColors.primary, solid: true),
                ],
              ),
              if (p.start != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(Icons.date_range_rounded, size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.end != null ? '${FC.date(p.start)} – ${FC.date(p.end)}' : 'From ${FC.date(p.start)}',
                        style: AppText.bodyStrong.copyWith(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
              if (p.summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(p.summary, style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 14.5, height: 1.55)),
              ],
              if (p.realLife.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const Text('What this looks like in real life', style: AppText.subtitle),
                const SizedBox(height: 8),
                BulletList(p.realLife, color: AppColors.cosmicLight),
              ],
              if (p.advice.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text('What helps', style: AppText.subtitle.copyWith(color: FC.good)),
                const SizedBox(height: 8),
                BulletList(p.advice, color: FC.good, icon: Icons.check_circle_rounded),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Ask an astrologer about this',
                icon: Icons.auto_awesome_rounded,
                onPressed: () => askAstrologer(context, _question(), field: 'Life Timeline', closeSheet: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
