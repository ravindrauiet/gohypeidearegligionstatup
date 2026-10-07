import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../services/backend_service.dart';
import '../widgets/forecast_widgets.dart';
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

Color kindColor(String kind) {
  switch (kind) {
    case TimelineKind.sadeSati:
    case TimelineKind.ashtamaShani:
    case TimelineKind.kantakaShani:
      return const Color(0xFF334155);
    case TimelineKind.saturn:
      return const Color(0xFF475569);
    case TimelineKind.jupiter:
      return const Color(0xFFD97706);
    case TimelineKind.rahuKetu:
      return const Color(0xFF7C3AED);
    case TimelineKind.mahadasha:
      return FC.violet;
    default:
      return const Color(0xFF0891B2);
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
          alignment: 0.25, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
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
        color: Colors.black,
        onRefresh: () => _load(force: true),
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: _data != null
              ? _content(_data!)
              : (_error != null && !_loading
                  ? ForecastError(message: _error!, onRetry: () => _load(force: true))
                  : const ForecastSkeleton()),
        ),
      );
    }

    return Scaffold(
      backgroundColor: FC.bg,
      appBar: AppBar(
        backgroundColor: FC.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Life Timeline',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
            Text('for $name',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch profile',
            icon: const Icon(Icons.people_alt_outlined, color: Colors.black),
            onPressed: () => showKundliProfilePicker(context),
          ),
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
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [FC.heroA, FC.heroB], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('WHERE YOU ARE NOW',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Text(
                current.isEmpty
                    ? 'A quieter stretch with no major Saturn, Jupiter or node pressure.'
                    : 'You are moving through ${current.length} major ${current.length == 1 ? 'period' : 'periods'} right now.',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.3),
              ),
              if (current.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in current)
                      ActionChip(
                        label: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => _openDetails(p, data),
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        side: BorderSide(color: FC.effect(p.effect).withValues(alpha: 0.6)),
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Slow planets and dashas set the background of your life. Knowing which chapter you are in explains a lot.',
                style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('All', filter == null, () => setState(() => _filter = null)),
              for (final f in available) _chip(f.label, filter == f, () => setState(() => _filter = f)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (periods.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No periods to show for this filter.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ),
        for (var i = 0; i <= periods.length; i++) ...[
          if (i == hereIndex && periods.isNotEmpty) _hereMarker(now),
          if (i < periods.length) _periodTile(periods[i], data, _isCurrent(periods[i], now), i == periods.length - 1),
        ],
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: Colors.black,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black, fontWeight: FontWeight.w700, fontSize: 12),
      side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _hereMarker(DateTime now) {
    return Padding(
      key: _hereKey,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        label: 'You are here, ${FC.date(now)}',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Container(
                width: 28,
                alignment: Alignment.center,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: FC.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: FC.accent.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: FC.accent, borderRadius: BorderRadius.circular(20)),
                  child: Text('You are here · ${FC.date(now, 'd MMM yyyy')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
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
                  child: Container(width: 2, color: Colors.black.withValues(alpha: 0.1)),
                ),
                Positioned(
                  top: 18,
                  child: Container(
                    width: isCurrent ? 14 : 10,
                    height: isCurrent ? 14 : 10,
                    decoration: BoxDecoration(
                      color: isCurrent ? ec : Colors.white,
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
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                button: true,
                label: '${p.title}, ${TimelineKind.label(p.kind)}, $range${isCurrent ? ', happening now' : ''}',
                child: Material(
                  color: isCurrent ? const Color(0xFFFFF4E8) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _openDetails(p, data),
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: isCurrent ? FC.accent.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.06),
                              width: isCurrent ? 1.5 : 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Pill(TimelineKind.label(p.kind), color: kc),
                                if (p.phase != null) Pill(p.phase!, color: const Color(0xFF0F766E)),
                                if (isCurrent) const Pill('Now', color: FC.accent, solid: true),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            if (range.isNotEmpty)
                              Text(range, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(FC.effectIcon(p.effect), size: 14, color: ec),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(Effect.label(p.effect),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ec)),
                                ),
                                const SizedBox(width: 10),
                                for (var i = 1; i <= 3; i++)
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(right: 3),
                                    decoration: BoxDecoration(
                                      color: i <= p.intensity ? kc : kc.withValues(alpha: 0.15),
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
                                  style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade800)),
                            ],
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => TimelinePeriodSheet(period: p, profile: data.meta.profile, isCurrent: _isCurrent(p, data.now)),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(p.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(TimelineKind.label(p.kind), color: kindColor(p.kind)),
                  if (p.phase != null) Pill('${p.phase} phase', color: const Color(0xFF0F766E)),
                  Pill(Effect.label(p.effect), color: ec, icon: FC.effectIcon(p.effect)),
                  Pill('Intensity ${p.intensity}/3', color: FC.neutral),
                  if (isCurrent) const Pill('Happening now', color: FC.accent, solid: true),
                ],
              ),
              if (p.start != null) ...[
                const SizedBox(height: 10),
                Text(
                  p.end != null ? '${FC.date(p.start)} – ${FC.date(p.end)}' : 'From ${FC.date(p.start)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
              ],
              if (p.summary.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(p.summary, style: TextStyle(fontSize: 14, height: 1.5, color: Colors.grey.shade900)),
              ],
              if (p.realLife.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('What this looks like in real life',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 8),
                BulletList(p.realLife, color: FC.violet),
              ],
              if (p.advice.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('What helps', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: FC.good)),
                const SizedBox(height: 8),
                BulletList(p.advice, color: FC.good, icon: Icons.check_circle_rounded),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => askAstrologer(context, _question(), field: 'Life Timeline', closeSheet: true),
                  icon: const Icon(Icons.forum_rounded, size: 18),
                  label: const Text('Ask an astrologer about this', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
