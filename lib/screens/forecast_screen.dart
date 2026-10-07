import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../services/backend_service.dart';
import '../widgets/forecast_widgets.dart';
import 'kundli_view_screen.dart' show KundliEmptyState, Vedic, showKundliProfilePicker;
import 'panchang_screen.dart';

/// Personal Day / Week / Month forecast built from the user's own Kundli.
///
/// Route arguments (all optional): `{tab: 'day'|'week'|'month'|0..2,
/// date: DateTime|'YYYY-MM-DD', familyId: int}`.
class ForecastScreen extends StatefulWidget {
  static const tabNames = ['day', 'week', 'month'];

  final int initialTab;
  final DateTime? initialDate;
  final int? familyId;

  const ForecastScreen({super.key, this.initialTab = 0, this.initialDate, this.familyId});

  factory ForecastScreen.fromArgs(Object? args) {
    if (args is! Map) return const ForecastScreen();
    final rawTab = args['tab'];
    var tab = 0;
    if (rawTab is int) {
      tab = rawTab.clamp(0, 2);
    } else if (rawTab != null) {
      final i = tabNames.indexOf(rawTab.toString().toLowerCase());
      tab = i < 0 ? 0 : i;
    }
    final rawDate = args['date'];
    final date = rawDate is DateTime ? dateOnly(rawDate) : fDate(rawDate);
    return ForecastScreen(initialTab: tab, initialDate: date, familyId: fIntOrNull(args['familyId']));
  }

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _Slot<T> {
  T? data;
  bool loading = false;
  String? error;
  bool noKundli = false;
  String? key;
  int token = 0;

  void reset() {
    data = null;
    loading = false;
    error = null;
    noKundli = false;
    key = null;
    token++;
  }
}

class _ForecastScreenState extends State<ForecastScreen> {
  late final BackendService _service;
  late int _tab;
  late DateTime _day;
  late DateTime _weekStart;
  late DateTime _month;
  int? _familyId;
  int? _observedSelection;

  final _daySlot = _Slot<DayForecast>();
  final _weekSlot = _Slot<WeekForecast>();
  final _monthSlot = _Slot<MonthForecast>();

  DateTime get _today => dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _service = Provider.of<BackendService>(context, listen: false);
    _tab = widget.initialTab.clamp(0, 2);
    final d = widget.initialDate ?? _today;
    _day = dateOnly(d);
    _weekStart = mondayOf(d);
    _month = DateTime(d.year, d.month, 1);
    _observedSelection = activeFamilyId(_service);
    _familyId = widget.familyId ?? _observedSelection;
    _service.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCurrent();
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    final id = activeFamilyId(_service);
    if (id == _observedSelection || !mounted) return;
    _observedSelection = id;
    setState(() {
      _familyId = id;
      _daySlot.reset();
      _weekSlot.reset();
      _monthSlot.reset();
    });
    _loadCurrent();
  }

  // ------------------------------------------------------------------ loading
  Future<void> _loadCurrent({bool force = false}) {
    switch (_tab) {
      case 1:
        return _run<WeekForecast>(
          _weekSlot,
          'w|${ymd(_weekStart)}|$_familyId',
          (s) => s.fetchWeekForecast(weekStart: _weekStart, familyId: _familyId, forceRefresh: force),
          (j) => WeekForecast.fromJson(j, fallbackStart: _weekStart),
          force: force,
        );
      case 2:
        return _run<MonthForecast>(
          _monthSlot,
          'm|${ym(_month)}|$_familyId',
          (s) => s.fetchMonthForecast(month: _month, familyId: _familyId, forceRefresh: force),
          (j) => MonthForecast.fromJson(j, fallbackMonth: _month),
          force: force,
        );
      default:
        return _run<DayForecast>(
          _daySlot,
          'd|${ymd(_day)}|$_familyId',
          (s) => s.fetchDayForecast(date: _day, familyId: _familyId, forceRefresh: force),
          (j) => DayForecast.fromJson(j, fallbackDate: _day),
          force: force,
        );
    }
  }

  Future<void> _run<T>(
    _Slot<T> slot,
    String key,
    Future<Map<String, dynamic>?> Function(BackendService s) fetch,
    T Function(Map<String, dynamic> json) parse, {
    bool force = false,
  }) async {
    if (!force && slot.key == key && (slot.data != null || slot.loading)) return;
    final token = ++slot.token;
    setState(() {
      if (slot.key != key) slot.data = null;
      slot.key = key;
      slot.loading = true;
      slot.error = null;
      slot.noKundli = false;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await fetch(_service);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != slot.token) return;
    T? parsed;
    if (raw != null) {
      try {
        parsed = parse(raw);
      } catch (_) {
        parsed = null;
      }
    }
    final hadData = slot.data != null;
    final message = _service.lastError ?? 'Could not load your forecast. Please try again.';
    setState(() {
      slot.loading = false;
      if (parsed != null) {
        slot.data = parsed;
      } else {
        slot.noKundli = _service.lastErrorCode == 'NO_KUNDLI';
        slot.error = message;
      }
    });
    if (parsed == null && hadData) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ------------------------------------------------------------------ navigation
  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    _loadCurrent();
  }

  void _openDay(DateTime d) {
    setState(() {
      _day = dateOnly(d);
      _tab = 0;
    });
    _loadCurrent();
  }

  void _openWeek(DateTime d) {
    setState(() {
      _weekStart = mondayOf(d);
      _tab = 1;
    });
    _loadCurrent();
  }

  void _shift(int dir) {
    setState(() {
      switch (_tab) {
        case 1:
          _weekStart = _weekStart.add(Duration(days: 7 * dir));
          break;
        case 2:
          _month = DateTime(_month.year, _month.month + dir, 1);
          break;
        default:
          _day = DateTime(_day.year, _day.month, _day.day + dir);
      }
    });
    _loadCurrent();
  }

  void _goToday() {
    final t = _today;
    setState(() {
      switch (_tab) {
        case 1:
          _weekStart = mondayOf(t);
          break;
        case 2:
          _month = DateTime(t.year, t.month, 1);
          break;
        default:
          _day = t;
      }
    });
    _loadCurrent();
  }

  bool get _isCurrent {
    final t = _today;
    switch (_tab) {
      case 1:
        return sameDay(_weekStart, mondayOf(t));
      case 2:
        return _month.year == t.year && _month.month == t.month;
      default:
        return sameDay(_day, t);
    }
  }

  String get _periodLabel {
    switch (_tab) {
      case 1:
        return FC.range(_weekStart, _weekStart.add(const Duration(days: 6)));
      case 2:
        return DateFormat('MMMM yyyy').format(_month);
      default:
        return DateFormat('EEE, d MMM yyyy').format(_day);
    }
  }

  Future<void> _pickPeriod() async {
    final initial = _tab == 1 ? _weekStart : (_tab == 2 ? _month : _day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDatePickerMode: _tab == 2 ? DatePickerMode.year : DatePickerMode.day,
      helpText: _tab == 1 ? 'Pick any day in the week' : (_tab == 2 ? 'Pick any day in the month' : 'Pick a day'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      switch (_tab) {
        case 1:
          _weekStart = mondayOf(picked);
          break;
        case 2:
          _month = DateTime(picked.year, picked.month, 1);
          break;
        default:
          _day = dateOnly(picked);
      }
    });
    _loadCurrent();
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final loadedProfile = _daySlot.data?.meta.profile ?? _weekSlot.data?.meta.profile ?? _monthSlot.data?.meta.profile;
    final kundli = Vedic.activeKundli(service);
    var name = loadedProfile?.name ?? '';
    if (name.isEmpty) name = Vedic.displayName(kundli, service: service);

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
            const Text('Your Forecast',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _Segmented(
              labels: const ['Day', 'Week', 'Month'],
              index: _tab,
              onChanged: _setTab,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: _periodBar(),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(key: ValueKey(_tab), child: _tabBody()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodBar() {
    final unit = _tab == 1 ? 'week' : (_tab == 2 ? 'month' : 'day');
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous $unit',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _shift(-1),
        ),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Selected $unit: $_periodLabel. Tap to pick a date',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickPeriod,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 16, color: FC.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_periodLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!_isCurrent)
          ActionChip(
            label: Text(_tab == 0 ? 'Today' : (_tab == 1 ? 'This week' : 'This month')),
            onPressed: _goToday,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: Colors.black,
            labelStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        IconButton(
          tooltip: 'Next $unit',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => _shift(1),
        ),
      ],
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case 1:
        return _body<WeekForecast>(_weekSlot, (w) => WeekView(week: w, today: _today, onOpenDay: _openDay));
      case 2:
        return _body<MonthForecast>(
            _monthSlot, (m) => MonthView(month: m, today: _today, onOpenDay: _openDay, onOpenWeek: _openWeek));
      default:
        return _body<DayForecast>(_daySlot, (d) => DayView(day: d, isToday: sameDay(d.date, _today)));
    }
  }

  Widget _body<T>(_Slot<T> slot, Widget Function(T data) builder) {
    if (slot.noKundli && slot.data == null) return const KundliEmptyState();
    final data = slot.data;
    Widget content;
    if (data != null) {
      content = builder(data);
    } else if (slot.error != null && !slot.loading) {
      content = ForecastError(message: slot.error!, onRetry: () => _loadCurrent(force: true));
    } else {
      content = const ForecastSkeleton();
    }
    return RefreshIndicator(
      color: Colors.black,
      onRefresh: () => _loadCurrent(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (slot.loading && data != null)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2)),
            content,
          ],
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const _Segmented({required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                label: '${labels[i]} forecast',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: i == index ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    alignment: Alignment.center,
                    child: ExcludeSemantics(
                      child: Text(labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: i == index ? Colors.white : Colors.black87,
                          )),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _askButton(BuildContext context, String label, String message) {
  return SizedBox(
    height: 50,
    child: ElevatedButton.icon(
      onPressed: () => askAstrologer(context, message),
      icon: const Icon(Icons.forum_rounded, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

String _forWhom(ForecastProfile p) =>
    p.isFamily && p.name.isNotEmpty ? 'This is for my ${p.relationship ?? 'family member'} ${p.name}. ' : '';

// ============================================================================
// Day
// ============================================================================

class DayView extends StatelessWidget {
  final DayForecast day;
  final bool isToday;
  const DayView({super.key, required this.day, this.isToday = false});

  String _question() {
    final m = day.moon;
    final slow = day.transits
        .where((t) => t.isSlow && t.houseFromMoon > 0)
        .map((t) => '${t.planet} ${FC.ordinal(t.houseFromMoon)} from Moon${t.retrograde ? ' (R)' : ''}')
        .join(', ');
    return '${_forWhom(day.meta.profile)}My forecast for ${FC.date(day.date, 'EEEE d MMMM yyyy')}: '
        'overall ${day.summary.overallScore}/100 (${Mood.label(day.summary.mood)}). '
        '${day.dasha.isEmpty ? '' : 'Dasha: ${day.dasha.chain}. '}'
        'Moon in ${m.sign}${m.nakshatra.isNotEmpty ? ' (${m.nakshatra})' : ''}'
        '${m.taraBala.name.isNotEmpty ? ', ${m.taraBala.name} Tara' : ''}'
        '${m.chandrashtama ? ', Chandrashtama day' : ''}. '
        '${slow.isNotEmpty ? 'Slow transits: $slow. ' : ''}'
        'How will this day go for me and what should I focus on?';
  }

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.meta.accuracyNote != null) AccuracyBanner(d.meta.accuracyNote!),
        ForecastHero(
          eyebrow: '${d.weekday}, ${FC.date(d.date, 'd MMMM')}${isToday ? ' · Today' : ''}',
          summary: d.summary,
          aiGenerated: d.meta.isAi,
        ),
        const SizedBox(height: 14),
        AreaBars(scores: d.scores, title: isToday ? 'Your life areas today' : 'Life areas on this day'),
        if (d.goodFor.isNotEmpty || d.avoid.isNotEmpty) ...[
          const SizedBox(height: 14),
          ForecastCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.goodFor.isNotEmpty)
                  ChipGroup(title: 'Good for', items: d.goodFor, color: FC.good, icon: Icons.thumb_up_alt_rounded),
                if (d.goodFor.isNotEmpty && d.avoid.isNotEmpty) const SizedBox(height: 14),
                if (d.avoid.isNotEmpty)
                  ChipGroup(title: 'Better to avoid', items: d.avoid, color: FC.bad, icon: Icons.do_not_disturb_on_rounded),
              ],
            ),
          ),
        ],
        const SectionLabel('Your Moon today'),
        MoonCard(moon: d.moon),
        if (d.bestTimes.isNotEmpty) ...[
          const SectionLabel('Best times'),
          ForecastCard(child: Column(children: [for (final b in d.bestTimes) _BestTimeRow(b)])),
        ],
        if (d.events.isNotEmpty) ...[
          const SectionLabel('In the sky on this day'),
          ForecastCard(child: Column(children: [for (final e in d.events) EventTile(event: e)])),
        ],
        if (!d.dasha.isEmpty) ...[
          const SectionLabel('Your life chapter'),
          DashaCard(dasha: d.dasha),
        ],
        if (d.transits.isNotEmpty) ...[
          const SectionLabel('Planets in motion for you'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
            child: Text(
              'Each planet is read from your birth Moon. Tap one to see what it means in real life.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.35),
            ),
          ),
          for (final t in d.transits) TransitCard(transit: t, profile: d.meta.profile),
        ],
        if (d.aspects.isNotEmpty) ...[
          const SectionLabel('Touching your birth chart'),
          ForecastCard(child: Column(children: [for (final a in d.aspects) AspectRow(aspect: a)])),
        ],
        if (!d.panchang.isEmpty) ...[
          const SectionLabel('Panchang'),
          PanchangMini(panchang: d.panchang, date: d.date),
        ],
        if (!d.remedy.isEmpty || d.luckyColor.isNotEmpty || d.luckyNumber != null) ...[
          const SectionLabel('Remedy & luck'),
          RemedyCard(remedy: d.remedy, luckyColor: d.luckyColor, luckyNumber: d.luckyNumber),
        ],
        const SizedBox(height: 20),
        _askButton(context, isToday ? 'Ask an astrologer about my day' : 'Ask an astrologer about this day', _question()),
      ],
    );
  }
}

class MoonCard extends StatelessWidget {
  final MoonToday moon;
  const MoonCard({super.key, required this.moon});

  @override
  Widget build(BuildContext context) {
    final tara = moon.taraBala;
    final taraColor = tara.favorable ? FC.good : FC.bad;
    return ForecastCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0xFFEDE9FE), shape: BoxShape.circle),
                child: const Icon(Icons.nightlight_round, color: FC.violet),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(moon.sign.isEmpty ? 'Moon' : 'Moon in ${moon.sign}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (moon.nakshatra.isNotEmpty)
                      Text('${moon.nakshatra} nakshatra', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                    if (moon.houseFromMoon > 0)
                      Text('${FC.ordinal(moon.houseFromMoon)} from your birth Moon',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (tara.name.isNotEmpty)
                Pill('${tara.name} Tara${tara.number > 0 ? ' · ${tara.number}/9' : ''}',
                    color: taraColor, icon: tara.favorable ? Icons.check_circle_rounded : Icons.error_outline_rounded),
              Pill(tara.favorable ? 'Favourable star' : 'Unfavourable star', color: taraColor, solid: true),
              Pill(moon.chandraBala ? 'Chandra Bala strong' : 'Chandra Bala weak',
                  color: moon.chandraBala ? FC.blue : FC.neutral),
            ],
          ),
          if (tara.meaning.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(tara.meaning, style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey.shade800)),
          ],
          if (moon.chandrashtama) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: 'Chandrashtama warning',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FC.bad.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: FC.bad.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: FC.bad, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chandrashtama: the Moon is in the 8th from your birth Moon. Energy and patience run low, so '
                        'skip big decisions, risky travel and arguments; rest and keep things simple.',
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF7F1D1D)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (moon.changesSignAt != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 15, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Moon moves into ${moon.nextSign ?? 'the next sign'} at ${moon.changesSignAt}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BestTimeRow extends StatelessWidget {
  final BestTime b;
  const _BestTimeRow(this.b);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: FC.good.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.access_time_filled_rounded, size: 16, color: FC.good),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                if (b.window.isNotEmpty)
                  Text(b.window, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: FC.good)),
                if (b.reason.isNotEmpty)
                  Text(b.reason, style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AspectRow extends StatelessWidget {
  final Aspect aspect;
  final Widget? badge;
  const AspectRow({super.key, required this.aspect, this.badge});

  @override
  Widget build(BuildContext context) {
    final color = FC.effect(aspect.effect);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FC.effectIcon(aspect.effect), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null) ...[badge!, const SizedBox(height: 4)],
                Text(aspect.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                Text('${aspect.orb.toStringAsFixed(1)}° orb · ${Effect.label(aspect.effect)}',
                    style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
                if (aspect.meaning.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(aspect.meaning, style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade800)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PanchangMini extends StatelessWidget {
  final PanchangLite panchang;
  final DateTime date;
  const PanchangMini({super.key, required this.panchang, required this.date});

  @override
  Widget build(BuildContext context) {
    final p = panchang;
    final items = <List<String>>[
      if (p.tithi.isNotEmpty) ['Tithi', p.tithi],
      if (p.nakshatra.isNotEmpty) ['Nakshatra', p.nakshatra],
      if (p.yoga.isNotEmpty) ['Yoga', p.yoga],
      if (p.karana.isNotEmpty) ['Karana', p.karana],
      if (p.sunrise.isNotEmpty) ['Sunrise', p.sunrise],
      if (p.sunset.isNotEmpty) ['Sunset', p.sunset],
      if (p.rahuKaal.isNotEmpty) ['Rahu Kaal', p.rahuKaal],
      if (p.abhijit.isNotEmpty) ['Abhijit', p.abhijit],
    ];
    return ForecastCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final it in items)
                    SizedBox(
                      width: w,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it[0], style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          Text(it[1],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: it[0] == 'Rahu Kaal' ? FC.bad : (it[0] == 'Abhijit' ? FC.good : Colors.black),
                              )),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PanchangScreen(initialDate: date)),
              ),
              icon: const Icon(Icons.wb_sunny_rounded, size: 16, color: FC.accent),
              label: const Text('Open full Panchang & Muhurat', style: TextStyle(color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Week
// ============================================================================

class WeekView extends StatelessWidget {
  final WeekForecast week;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;
  const WeekView({super.key, required this.week, required this.today, required this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    final w = week;
    final cautionDates = w.cautionDays.map((c) => c.date).whereType<DateTime>().toList();
    bool isCaution(DateTime d) => cautionDates.any((c) => sameDay(c, d));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (w.meta.accuracyNote != null) AccuracyBanner(w.meta.accuracyNote!),
        ForecastHero(
          eyebrow: 'Week of ${FC.range(w.weekStart, w.weekEnd)}',
          summary: w.summary,
          aiGenerated: w.meta.isAi,
        ),
        if (w.days.isNotEmpty) ...[
          const SectionLabel('Your 7 days'),
          ForecastCard(
            child: Column(
              children: [
                ScoreStrip(days: w.days, today: today, isCaution: isCaution, onTap: onOpenDay),
                const SizedBox(height: 10),
                const _StripLegend(),
                const Divider(height: 24),
                for (final d in w.days) _WeekDayRow(day: d, caution: isCaution(d.date), onTap: () => onOpenDay(d.date)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        AreaBars(scores: w.scores, title: "This week's life areas"),
        if (w.focus.isNotEmpty) ...[
          const SizedBox(height: 14),
          ForecastCard(
            title: 'Your focus this week',
            icon: Icons.center_focus_strong_rounded,
            child: Text(w.focus, style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.grey.shade900)),
          ),
        ],
        if (!w.bestDays.isEmpty) ...[
          const SectionLabel('Best days for'),
          BestDaysCard(bestDays: w.bestDays, onTap: onOpenDay),
        ],
        if (w.cautionDays.isNotEmpty) ...[
          const SectionLabel('Go gently on'),
          CautionDaysCard(days: w.cautionDays, onTap: onOpenDay),
        ],
        if (w.events.isNotEmpty) ...[
          const SectionLabel('Sky events this week'),
          ForecastCard(
            child: Column(children: [
              for (final e in w.events)
                EventTile(event: e, showDate: true, onTap: e.date == null ? null : () => onOpenDay(e.date!)),
            ]),
          ),
        ],
        if (!w.dasha.isEmpty) ...[
          const SectionLabel('Your life chapter'),
          DashaCard(dasha: w.dasha),
        ],
        if (!w.remedy.isEmpty) ...[
          const SectionLabel('Remedy for the week'),
          RemedyCard(remedy: w.remedy),
        ],
        const SizedBox(height: 20),
        _askButton(
          context,
          'Ask an astrologer about my week',
          '${_forWhom(w.meta.profile)}My week ${FC.range(w.weekStart, w.weekEnd)} scores ${w.summary.overallScore}/100 '
              '(${Mood.label(w.summary.mood)}): ${w.summary.headline} '
              '${w.dasha.isEmpty ? '' : 'Dasha: ${w.dasha.chain}. '}'
              '${w.cautionDays.isEmpty ? '' : 'Caution days: ${w.cautionDays.map((c) => '${FC.date(c.date, 'EEE d MMM')} (${c.reason})').join('; ')}. '}'
              'How should I plan this week?',
        ),
      ],
    );
  }
}

/// Seven vertical score bars; tap a day to open it.
class ScoreStrip extends StatelessWidget {
  final List<WeekDay> days;
  final DateTime today;
  final bool Function(DateTime) isCaution;
  final ValueChanged<DateTime> onTap;
  const ScoreStrip({super.key, required this.days, required this.today, required this.isCaution, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              button: true,
              label: '${FC.date(d.date, 'EEEE d MMMM')}, score ${d.score}'
                  '${d.chandrashtama ? ', Chandrashtama' : ''}${isCaution(d.date) ? ', caution day' : ''}',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTap(d.date),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 16,
                          child: FittedBox(
                            child: Text('${d.score}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: FC.score(d.score))),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 64,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: d.score / 100),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, _) => Container(
                                width: 14,
                                height: 6 + 58 * t,
                                decoration: BoxDecoration(
                                  color: FC.score(d.score),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 14,
                          child: FittedBox(
                            child: Text(DateFormat('EEE').format(d.date),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sameDay(d.date, today) ? Colors.black : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Text('${d.date.day}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: sameDay(d.date, today) ? Colors.white : Colors.black)),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 14,
                          child: d.chandrashtama
                              ? const Icon(Icons.nightlight_round, size: 12, color: FC.bad)
                              : (isCaution(d.date)
                                  ? Center(
                                      child: Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: FC.accent, shape: BoxShape.circle)))
                                  : null),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StripLegend extends StatelessWidget {
  const _StripLegend();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: Colors.grey.shade600);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nightlight_round, size: 12, color: FC.bad),
          const SizedBox(width: 4),
          Text('Chandrashtama', style: style),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: FC.accent, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('Caution', style: style),
        ]),
        Text('Tap a day for details', style: style),
      ],
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  final WeekDay day;
  final bool caution;
  final VoidCallback onTap;
  const _WeekDayRow({required this.day, required this.caution, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = day;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(DateFormat('EEE').format(d.date),
                      maxLines: 1, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  Text('${d.date.day}', maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.highlight.isNotEmpty)
                    Text(d.highlight, style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Pill('${d.score} · ${Mood.label(d.mood)}', color: FC.score(d.score)),
                      if (d.taraBala.isNotEmpty)
                        Pill('${d.taraBala} Tara', color: d.taraFavorable ? FC.good : FC.bad),
                      if (d.chandrashtama) const Pill('Chandrashtama', color: FC.bad, icon: Icons.nightlight_round),
                      if (caution && !d.chandrashtama) const Pill('Caution', color: FC.accent),
                      if (d.moonSign.isNotEmpty) Pill('Moon ${d.moonSign}', color: FC.violet),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class BestDaysCard extends StatelessWidget {
  final BestDays bestDays;
  final ValueChanged<DateTime> onTap;
  const BestDaysCard({super.key, required this.bestDays, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ForecastCard(
      child: Column(
        children: [
          for (final k in BestDays.keys)
            if ((bestDays.byArea[k] ?? const []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(FC.areaIcon(k), size: 18, color: FC.area(k)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: Text(LifeArea.label(k), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final d in bestDays.byArea[k]!)
                            Semantics(
                              button: true,
                              label: 'Open ${FC.date(d, 'EEEE d MMMM')}',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => onTap(d),
                                child: ExcludeSemantics(child: Pill(FC.date(d, 'EEE d'), color: FC.area(k))),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class CautionDaysCard extends StatelessWidget {
  final List<CautionDay> days;
  final ValueChanged<DateTime> onTap;
  const CautionDaysCard({super.key, required this.days, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ForecastCard(
      borderColor: FC.bad.withValues(alpha: 0.2),
      child: Column(
        children: [
          for (final c in days)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: c.date == null ? null : () => onTap(c.date!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: FC.bad),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(FC.date(c.date, 'EEEE, d MMM'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          if (c.reason.isNotEmpty)
                            Text(c.reason, style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey.shade800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Month
// ============================================================================

class MonthView extends StatelessWidget {
  final MonthForecast month;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;
  final ValueChanged<DateTime> onOpenWeek;
  const MonthView({super.key, required this.month, required this.today, required this.onOpenDay, required this.onOpenWeek});

  @override
  Widget build(BuildContext context) {
    final m = month;
    final grouped = <DateTime, List<ForecastEvent>>{};
    for (final e in m.events) {
      if (e.date == null) continue;
      grouped.putIfAbsent(e.date!, () => []).add(e);
    }
    final eventDates = grouped.keys.toList()..sort();
    final title = m.monthName.isNotEmpty ? m.monthName : DateFormat('MMMM yyyy').format(m.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.meta.accuracyNote != null) AccuracyBanner(m.meta.accuracyNote!),
        ForecastHero(eyebrow: title, summary: m.summary, aiGenerated: m.meta.isAi),
        const SectionLabel('Your month at a glance'),
        ForecastCard(
          child: Column(
            children: [
              MonthHeatmap(month: m, today: today, onTap: onOpenDay),
              const SizedBox(height: 12),
              const _HeatmapLegend(),
            ],
          ),
        ),
        if (m.weeks.isNotEmpty) ...[
          const SectionLabel('Week by week'),
          ForecastCard(
            child: Column(children: [
              for (final w in m.weeks)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: w.weekStart == null ? null : () => onOpenWeek(w.weekStart!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: FC.score(w.score).withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text('${w.score}',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: FC.score(w.score))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (w.weekStart != null && w.weekEnd != null) ? FC.range(w.weekStart!, w.weekEnd!) : 'Week',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                              ),
                              if (w.headline.isNotEmpty)
                                Text(w.headline, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.35)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        AreaBars(scores: m.scores, title: "This month's life areas"),
        if (!m.bestDays.isEmpty) ...[
          const SectionLabel('Best days for'),
          BestDaysCard(bestDays: m.bestDays, onTap: onOpenDay),
        ],
        if (m.cautionDays.isNotEmpty) ...[
          const SectionLabel('Go gently on'),
          CautionDaysCard(days: m.cautionDays, onTap: onOpenDay),
        ],
        if (m.keyTransits.isNotEmpty) ...[
          const SectionLabel('Big planetary moves'),
          for (final t in m.keyTransits) TransitCard(transit: t, profile: m.meta.profile),
        ],
        if (eventDates.isNotEmpty) ...[
          const SectionLabel('Festivals & sky events'),
          ForecastCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in eventDates) ...[
                  InkWell(
                    onTap: () => onOpenDay(d),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 2),
                      child: Text(FC.date(d, 'EEEE, d MMMM'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: FC.accent)),
                    ),
                  ),
                  for (final e in grouped[d]!) EventTile(event: e),
                ],
              ],
            ),
          ),
        ],
        if (!m.dasha.isEmpty) ...[
          const SectionLabel('Your life chapter'),
          DashaCard(dasha: m.dasha),
        ],
        if (!m.remedy.isEmpty) ...[
          const SectionLabel('Remedy for the month'),
          RemedyCard(remedy: m.remedy),
        ],
        const SizedBox(height: 20),
        _askButton(
          context,
          'Ask an astrologer about my month',
          '${_forWhom(m.meta.profile)}My forecast for $title is ${m.summary.overallScore}/100 '
              '(${Mood.label(m.summary.mood)}): ${m.summary.headline} '
              '${m.dasha.isEmpty ? '' : 'Dasha: ${m.dasha.chain}. '}'
              '${m.keyTransits.isEmpty ? '' : 'Key transits: ${m.keyTransits.map((t) => '${t.planet} in ${t.sign} (${FC.ordinal(t.houseFromMoon)} from Moon)').join(', ')}. '}'
              'What should I focus on this month and which dates matter most?',
        ),
      ],
    );
  }
}

class MonthHeatmap extends StatelessWidget {
  final MonthForecast month;
  final DateTime today;
  final ValueChanged<DateTime> onTap;
  const MonthHeatmap({super.key, required this.month, required this.today, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final first = month.month;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1;
    final rows = ((lead + daysInMonth) / 7).ceil();
    const heads = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Row(
          children: [
            for (final h in heads)
              Expanded(
                child: Center(
                  child: Text(h, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade500)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: AspectRatio(aspectRatio: 1, child: _cell(r * 7 + c - lead + 1, daysInMonth)),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(int dayNum, int daysInMonth) {
    if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();
    final date = DateTime(month.month.year, month.month.month, dayNum);
    final md = month.dayFor(date);
    final isToday = sameDay(date, today);
    final color = md == null ? Colors.grey.shade100 : FC.score(md.score).withValues(alpha: 0.15 + 0.45 * (md.score / 100));
    final label = [
      FC.date(date, 'EEEE d MMMM'),
      if (md != null) 'score ${md.score}',
      if (md?.festival != null) md!.festival!,
      if (md?.chandrashtama ?? false) 'Chandrashtama',
    ].join(', ');

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(date),
          child: ExcludeSemantics(
            child: Container(
              decoration: isToday
                  ? BoxDecoration(border: Border.all(color: Colors.black, width: 1.6), borderRadius: BorderRadius.circular(8))
                  : null,
              child: Stack(
                children: [
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.6,
                      heightFactor: 0.5,
                      child: FittedBox(
                        child: Text('$dayNum',
                            style: TextStyle(fontWeight: isToday ? FontWeight.w900 : FontWeight.w700, color: Colors.black87)),
                      ),
                    ),
                  ),
                  if (md?.festival != null)
                    Positioned(
                      bottom: 3,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(color: Color(0xFF9333EA), shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  if (md?.chandrashtama ?? false)
                    const Positioned(top: 2, right: 2, child: Icon(Icons.nightlight_round, size: 9, color: FC.bad)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: Colors.grey.shade700);
    Widget swatch(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(t, style: style),
        ]);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        swatch(FC.good.withValues(alpha: 0.55), 'Strong'),
        swatch(FC.blue.withValues(alpha: 0.45), 'Good'),
        swatch(FC.accent.withValues(alpha: 0.4), 'Mixed'),
        swatch(FC.bad.withValues(alpha: 0.3), 'Tough'),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF9333EA), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('Festival', style: style),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nightlight_round, size: 11, color: FC.bad),
          const SizedBox(width: 4),
          Text('Chandrashtama', style: style),
        ]),
      ],
    );
  }
}
