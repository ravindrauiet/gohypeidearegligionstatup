import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../services/backend_service.dart';
import '../widgets/forecast_widgets.dart';
import '../widgets/ui/app_ui.dart';
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
    if (parsed == null && hadData && mounted) showAppSnack(context, message, error: true);
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
            const Text('Your forecast', maxLines: 1, overflow: TextOverflow.ellipsis),
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
      body: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 4),
                  child: _Segmented(labels: const ['Day', 'Week', 'Month'], index: _tab, onChanged: _setTab),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _periodBar(),
                ),
                if (_tab == 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _DateStrip(selected: _day, today: _today, onPick: _openDay),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: FC.anim(context, 220),
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
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: _pickPeriod,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_periodLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!_isCurrent)
          Semantics(
            button: true,
            child: InkWell(
              onTap: _goToday,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(_tab == 0 ? 'Today' : (_tab == 1 ? 'This week' : 'This month'),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
              ),
            ),
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
      color: AppColors.primary,
      onRefresh: () => _loadCurrent(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
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

// ============================================================================
// Header controls
// ============================================================================

class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const _Segmented({required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
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
                    duration: FC.anim(context, 200),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                      boxShadow: i == index ? AppShadows.card : null,
                    ),
                    alignment: Alignment.center,
                    child: ExcludeSemantics(
                      child: Text(labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 14,
                            color: i == index ? AppColors.textPrimary : AppColors.textSecondary,
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

/// Horizontal strip of days around the selected one (day view only).
class _DateStrip extends StatefulWidget {
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onPick;
  const _DateStrip({required this.selected, required this.today, required this.onPick});

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  static const _span = 7; // days either side of the selected one
  static const _cell = 52.0;
  static const _pad = 12.0;
  final _ctrl = ScrollController();
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center());
  }

  @override
  void didUpdateWidget(_DateStrip old) {
    super.didUpdateWidget(old);
    if (!sameDay(old.selected, widget.selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _center() {
    if (!mounted || !_ctrl.hasClients) return;
    final target = (_pad + _span * _cell + _cell / 2 - _viewport / 2).clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = -_span; i <= _span; i++)
        DateTime(widget.selected.year, widget.selected.month, widget.selected.day + i),
    ];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, c) {
      _viewport = c.maxWidth;
      return SizedBox(
        height: 58 + 12 * scale,
        child: ListView.builder(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _pad),
          itemExtent: _cell,
          itemCount: days.length,
          itemBuilder: (context, i) {
            final d = days[i];
            final sel = sameDay(d, widget.selected);
            final isToday = sameDay(d, widget.today);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Semantics(
                button: true,
                selected: sel,
                label: '${FC.date(d, 'EEEE d MMMM')}${isToday ? ', today' : ''}',
                excludeSemantics: true,
                child: Material(
                  color: sel ? AppColors.primary : AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: sel ? null : () => widget.onPick(d),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          child: Text(DateFormat('EEE').format(d),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white.withValues(alpha: 0.85) : AppColors.textTertiary)),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          child: Text('${d.day}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: sel ? Colors.white : AppColors.textPrimary)),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isToday ? (sel ? Colors.white : AppColors.primary) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

// ============================================================================
// Shared bits
// ============================================================================

String _forWhom(ForecastProfile p) =>
    p.isFamily && p.name.isNotEmpty ? 'This is for my ${p.relationship ?? 'family member'} ${p.name}. ' : '';

String _shareText(String title, ForecastSummary s, {String extra = ''}) => [
      title,
      if (s.headline.isNotEmpty) s.headline,
      'Overall ${s.overallScore}/100 · ${Mood.label(s.mood)}',
      if (s.narrative.isNotEmpty) s.narrative,
      if (extra.isNotEmpty) extra,
      '— from my CosmicGuide forecast',
    ].join('\n\n');

/// Bottom CTA: "Ask AI about …" plus a share (copy) button.
class _AskShareBar extends StatelessWidget {
  final String askLabel;
  final String question;
  final String shareText;
  const _AskShareBar({required this.askLabel, required this.question, required this.shareText});

  Future<void> _share(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: shareText));
    if (context.mounted) showAppSnack(context, 'Forecast copied. Paste it anywhere to share.');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              label: askLabel,
              icon: Icons.auto_awesome_rounded,
              onPressed: () => askAstrologer(context, question),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Share forecast',
            child: Semantics(
              button: true,
              label: 'Share forecast',
              excludeSemantics: true,
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.button,
                  side: const BorderSide(color: AppColors.border, width: 1.2),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _share(context),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.ios_share_rounded, color: AppColors.textPrimary),
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

Widget _rowsCard(List<Widget> rows) => ForecastCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );

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
    final careful = <Widget>[
      if (d.moon.chandrashtama)
        const ForecastIconRow(
          icon: Icons.nightlight_round,
          color: AppColors.danger,
          title: 'A low-energy Moon day',
          detail: 'Keep plans simple, skip big decisions and arguments, and rest more.',
        ),
      for (final s in d.avoid) ForecastIconRow(icon: Icons.do_not_disturb_on_rounded, color: AppColors.danger, title: s),
      if (d.panchang.rahuKaal.isNotEmpty)
        ForecastIconRow(
          icon: Icons.schedule_rounded,
          color: AppColors.warning,
          title: 'Starting new things in Rahu Kaal',
          trailing: d.panchang.rahuKaal,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.meta.accuracyNote != null) AccuracyBanner(d.meta.accuracyNote!),
        ForecastHero(
          eyebrow: '${d.weekday.isEmpty ? FC.date(d.date, 'EEEE') : d.weekday}, ${FC.date(d.date, 'd MMMM')}'
              '${isToday ? ' · Today' : ''}',
          summary: d.summary,
          aiGenerated: d.meta.isAi,
        ),
        if (d.goodFor.isNotEmpty) ...[
          const SectionLabel('Good for'),
          _rowsCard([
            for (final s in d.goodFor) ForecastIconRow(icon: Icons.check_circle_rounded, color: AppColors.success, title: s),
          ]),
        ],
        if (careful.isNotEmpty) ...[
          const SectionLabel('Be careful with'),
          _rowsCard(careful),
        ],
        if (d.bestTimes.isNotEmpty) ...[
          const SectionLabel('Best time'),
          _rowsCard([
            for (final b in d.bestTimes)
              ForecastIconRow(
                icon: Icons.access_time_filled_rounded,
                color: AppColors.success,
                title: b.label,
                trailing: b.window,
                detail: b.reason,
              ),
          ]),
        ],
        const SizedBox(height: AppSpacing.xl),
        AreaBars(scores: d.scores, title: isToday ? 'Your life areas today' : 'Life areas on this day'),
        if (!d.remedy.isEmpty || d.luckyColor.isNotEmpty || d.luckyNumber != null) ...[
          const SectionLabel('Remedy & luck'),
          RemedyCard(remedy: d.remedy, luckyColor: d.luckyColor, luckyNumber: d.luckyNumber),
        ],
        const SizedBox(height: AppSpacing.xl),
        WhyExpander(
          subtitle: 'Your Moon, planets, dasha and Panchang for this day',
          builder: () => [
            const SectionLabel('Your Moon today'),
            MoonCard(moon: d.moon),
            if (d.events.isNotEmpty) ...[
              const SectionLabel('In the sky on this day'),
              ForecastCard(child: Column(children: [for (final e in d.events) EventTile(event: e)])),
            ],
            if (!d.dasha.isEmpty) ...[
              const SectionLabel('Your life chapter'),
              DashaCard(dasha: d.dasha),
            ],
            if (d.transits.isNotEmpty) ...[
              const SectionLabel('Planets in motion for you',
                  subtitle: 'Each planet is read from your birth Moon. Tap one to see what it means in real life.'),
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
          ],
        ),
        _AskShareBar(
          askLabel: isToday ? 'Ask AI about today' : 'Ask AI about this day',
          question: _question(),
          shareText: _shareText('My day · ${FC.date(d.date, 'EEE d MMM yyyy')}', d.summary,
              extra: d.goodFor.isEmpty ? '' : 'Good for: ${d.goodFor.join(', ')}'),
        ),
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
              const IconTile(Icons.nightlight_round, color: AppColors.cosmicLight, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(moon.sign.isEmpty ? 'Moon' : 'Moon in ${moon.sign}', style: AppText.subtitle),
                    if (moon.nakshatra.isNotEmpty) Text('${moon.nakshatra} nakshatra', style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                    if (moon.houseFromMoon > 0)
                      Text('${FC.ordinal(moon.houseFromMoon)} from your birth Moon', style: AppText.caption),
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
            Text(tara.meaning, style: AppText.body.copyWith(fontSize: 13.5)),
          ],
          if (moon.chandrashtama) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: 'Chandrashtama warning',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chandrashtama: the Moon is in the 8th from your birth Moon. Energy and patience run low, so '
                        'skip big decisions, risky travel and arguments; rest and keep things simple.',
                        style: AppText.caption.copyWith(fontSize: 12.5, color: AppColors.textPrimary, height: 1.45),
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
                const Icon(Icons.schedule_rounded, size: 15, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Moon moves into ${moon.nextSign ?? 'the next sign'} at ${moon.changesSignAt}',
                      style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
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
          IconTile(FC.effectIcon(aspect.effect), color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null) ...[badge!, const SizedBox(height: 4)],
                Text(aspect.title, style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
                Text('${aspect.orb.toStringAsFixed(1)}° orb · ${Effect.label(aspect.effect)}',
                    style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
                if (aspect.meaning.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(aspect.meaning, style: AppText.body.copyWith(fontSize: 13)),
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
                runSpacing: 12,
                children: [
                  for (final it in items)
                    SizedBox(
                      width: w,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it[0], style: AppText.caption.copyWith(fontSize: 11)),
                          Text(it[1],
                              style: AppText.bodyStrong.copyWith(
                                fontSize: 13,
                                color: it[0] == 'Rahu Kaal'
                                    ? FC.bad
                                    : (it[0] == 'Abhijit' ? FC.good : AppColors.textPrimary),
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
              icon: const Icon(Icons.wb_sunny_rounded, size: 16),
              label: const Text('Open full Panchang & Muhurat'),
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
        if (w.focus.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ForecastCard(
            title: 'Your focus this week',
            icon: Icons.center_focus_strong_rounded,
            child: Text(w.focus, style: AppText.body.copyWith(color: AppColors.textPrimary)),
          ),
        ],
        if (w.days.isNotEmpty) ...[
          const SectionLabel('Your 7 days', subtitle: 'Tap a day for its full forecast'),
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
        const SizedBox(height: AppSpacing.xl),
        AreaBars(scores: w.scores, title: "This week's life areas"),
        if (!w.bestDays.isEmpty) ...[
          const SectionLabel('Best days for'),
          BestDaysCard(bestDays: w.bestDays, onTap: onOpenDay),
        ],
        if (w.cautionDays.isNotEmpty) ...[
          const SectionLabel('Go gently on'),
          CautionDaysCard(days: w.cautionDays, onTap: onOpenDay),
        ],
        if (!w.remedy.isEmpty) ...[
          const SectionLabel('Remedy for the week'),
          RemedyCard(remedy: w.remedy),
        ],
        if (w.events.isNotEmpty || !w.dasha.isEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          WhyExpander(
            subtitle: 'Sky events and your dasha this week',
            builder: () => [
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
            ],
          ),
        ],
        _AskShareBar(
          askLabel: 'Ask AI about this week',
          question: '${_forWhom(w.meta.profile)}My week ${FC.range(w.weekStart, w.weekEnd)} scores ${w.summary.overallScore}/100 '
              '(${Mood.label(w.summary.mood)}): ${w.summary.headline} '
              '${w.dasha.isEmpty ? '' : 'Dasha: ${w.dasha.chain}. '}'
              '${w.cautionDays.isEmpty ? '' : 'Caution days: ${w.cautionDays.map((c) => '${FC.date(c.date, 'EEE d MMM')} (${c.reason})').join('; ')}. '}'
              'How should I plan this week?',
          shareText: _shareText('My week · ${FC.range(w.weekStart, w.weekEnd)}', w.summary, extra: w.focus),
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
                borderRadius: BorderRadius.circular(AppRadius.md),
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
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: FC.score(d.score))),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 64,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: d.score / 100),
                              duration: FC.anim(context, 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, _) => Container(
                                width: 12,
                                height: 6 + 58 * t,
                                decoration: BoxDecoration(
                                  color: FC.score(d.score).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(6),
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
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sameDay(d.date, today) ? AppColors.primary : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Text('${d.date.day}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: sameDay(d.date, today) ? Colors.white : AppColors.textPrimary)),
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
                                          decoration:
                                              const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle)))
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
    final style = AppText.caption.copyWith(fontSize: 11);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nightlight_round, size: 12, color: FC.bad),
          const SizedBox(width: 4),
          Flexible(child: Text('Low-energy Moon day', style: style)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(child: Text('Go gently', style: style)),
        ]),
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
      borderRadius: BorderRadius.circular(AppRadius.md),
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
                  Text(DateFormat('EEE').format(d.date), maxLines: 1, style: AppText.caption.copyWith(fontSize: 11)),
                  Text('${d.date.day}', maxLines: 1, style: AppText.title.copyWith(fontSize: 17)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.highlight.isNotEmpty)
                    Text(d.highlight, style: AppText.body.copyWith(fontSize: 13.5, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Pill('${d.score} · ${Mood.label(d.mood)}', color: FC.score(d.score)),
                      if (d.taraBala.isNotEmpty) Pill('${d.taraBala} Tara', color: d.taraFavorable ? FC.good : FC.bad),
                      if (d.chandrashtama) const Pill('Chandrashtama', color: FC.bad, icon: Icons.nightlight_round),
                      if (caution && !d.chandrashtama) const Pill('Caution', color: AppColors.warning),
                      if (d.moonSign.isNotEmpty) Pill('Moon ${d.moonSign}', color: FC.violet),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
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
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconTile(FC.areaIcon(k), color: FC.area(k), size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(LifeArea.label(k), style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final d in bestDays.byArea[k]!)
                                Semantics(
                                  button: true,
                                  label: 'Open ${FC.date(d, 'EEEE d MMMM')}',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                    onTap: () => onTap(d),
                                    child: ExcludeSemantics(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(AppRadius.pill),
                                          border: Border.all(color: AppColors.border),
                                        ),
                                        child: Text(FC.date(d, 'EEE d'),
                                            style: AppText.caption
                                                .copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
    return _rowsCard([
      for (final c in days)
        ForecastIconRow(
          icon: Icons.warning_amber_rounded,
          color: AppColors.danger,
          title: FC.date(c.date, 'EEEE, d MMM'),
          detail: c.reason,
          onTap: c.date == null ? null : () => onTap(c.date!),
        ),
    ]);
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
        const SectionLabel('Your month at a glance', subtitle: 'Tap any date for its forecast'),
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
          _rowsCard([
            for (final w in m.weeks)
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: w.weekStart == null ? null : () => onOpenWeek(w.weekStart!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: FC.score(w.score).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.md)),
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${w.score}',
                                style: TextStyle(fontWeight: FontWeight.w800, color: FC.score(w.score))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (w.weekStart != null && w.weekEnd != null) ? FC.range(w.weekStart!, w.weekEnd!) : 'Week',
                              style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (w.headline.isNotEmpty)
                              Text(w.headline, style: AppText.body.copyWith(fontSize: 13.5, color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      if (w.weekStart != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),
          ]),
        ],
        const SizedBox(height: AppSpacing.xl),
        AreaBars(scores: m.scores, title: "This month's life areas"),
        if (!m.bestDays.isEmpty) ...[
          const SectionLabel('Best days for'),
          BestDaysCard(bestDays: m.bestDays, onTap: onOpenDay),
        ],
        if (m.cautionDays.isNotEmpty) ...[
          const SectionLabel('Go gently on'),
          CautionDaysCard(days: m.cautionDays, onTap: onOpenDay),
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
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(FC.date(d, 'EEEE, d MMMM'),
                          style: AppText.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                    ),
                  ),
                  for (final e in grouped[d]!) EventTile(event: e),
                ],
              ],
            ),
          ),
        ],
        if (!m.remedy.isEmpty) ...[
          const SectionLabel('Remedy for the month'),
          RemedyCard(remedy: m.remedy),
        ],
        if (m.keyTransits.isNotEmpty || !m.dasha.isEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          WhyExpander(
            subtitle: 'Big planetary moves and your dasha this month',
            builder: () => [
              if (m.keyTransits.isNotEmpty) ...[
                const SectionLabel('Big planetary moves'),
                for (final t in m.keyTransits) TransitCard(transit: t, profile: m.meta.profile),
              ],
              if (!m.dasha.isEmpty) ...[
                const SectionLabel('Your life chapter'),
                DashaCard(dasha: m.dasha),
              ],
            ],
          ),
        ],
        _AskShareBar(
          askLabel: 'Ask AI about this month',
          question: '${_forWhom(m.meta.profile)}My forecast for $title is ${m.summary.overallScore}/100 '
              '(${Mood.label(m.summary.mood)}): ${m.summary.headline} '
              '${m.dasha.isEmpty ? '' : 'Dasha: ${m.dasha.chain}. '}'
              '${m.keyTransits.isEmpty ? '' : 'Key transits: ${m.keyTransits.map((t) => '${t.planet} in ${t.sign} (${FC.ordinal(t.houseFromMoon)} from Moon)').join(', ')}. '}'
              'What should I focus on this month and which dates matter most?',
          shareText: _shareText('My month · $title', m.summary),
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
                  child: Text(h, style: AppText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
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
    final color =
        md == null ? AppColors.surfaceMuted : FC.score(md.score).withValues(alpha: 0.12 + 0.38 * (md.score / 100));
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => onTap(date),
          child: ExcludeSemantics(
            child: Container(
              decoration: isToday
                  ? BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 1.8),
                      borderRadius: BorderRadius.circular(AppRadius.sm))
                  : null,
              child: Stack(
                children: [
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.6,
                      heightFactor: 0.5,
                      child: FittedBox(
                        child: Text('$dayNum',
                            style: TextStyle(
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600, color: AppColors.textPrimary)),
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
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
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
    final style = AppText.caption.copyWith(fontSize: 11, color: AppColors.textSecondary);
    Widget swatch(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Flexible(child: Text(t, style: style)),
        ]);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        swatch(FC.good.withValues(alpha: 0.45), 'Strong'),
        swatch(FC.blue.withValues(alpha: 0.38), 'Good'),
        swatch(AppColors.warning.withValues(alpha: 0.32), 'Mixed'),
        swatch(FC.bad.withValues(alpha: 0.25), 'Tough'),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(child: Text('Festival', style: style)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nightlight_round, size: 11, color: FC.bad),
          const SizedBox(width: 4),
          Flexible(child: Text('Low-energy Moon', style: style)),
        ]),
      ],
    );
  }
}
