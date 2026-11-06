import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backend_service.dart';
import '../../services/muhurat_service.dart';
import '../../widgets/ui/app_ui.dart';

/// Shares text (replaced in tests).
@visibleForTesting
Future<void> Function(String text)? debugMuhuratShare;

Future<void> _share(String text) async {
  final d = debugMuhuratShare;
  if (d != null) return d(text);
  await SharePlus.instance.share(ShareParams(text: text));
}

IconData muhuratIcon(String key) => switch (key) {
      'home' => Icons.home_rounded,
      'car' => Icons.directions_car_rounded,
      'work' => Icons.work_rounded,
      'property' => Icons.landscape_rounded,
      'marriage' => Icons.favorite_rounded,
      'ring' => Icons.diamond_rounded,
      'baby' => Icons.child_friendly_rounded,
      'child' => Icons.content_cut_rounded,
      'travel' => Icons.flight_takeoff_rounded,
      'gold' => Icons.workspace_premium_rounded,
      'school' => Icons.school_rounded,
      'medical' => Icons.medical_services_rounded,
      _ => Icons.auto_awesome_rounded,
    };

Color _iconColor(String key) => switch (key) {
      'home' || 'property' => const Color(0xFF0F9D7A),
      'car' || 'travel' => AppColors.info,
      'work' || 'school' => const Color(0xFF7C3AED),
      'marriage' || 'ring' => AppColors.love,
      'baby' || 'child' => const Color(0xFFF59E0B),
      'gold' => const Color(0xFFC88A04),
      'medical' => AppColors.danger,
      _ => AppColors.primary,
    };

/// Muhurat finder: pick an event, see the 3 best days in the next 30 days.
///
/// [onAskPandit] opens the Chat tab (wired by the coordinator); the button is
/// hidden when it is null. [service] is for tests.
class MuhuratFinderScreen extends StatefulWidget {
  final VoidCallback? onAskPandit;
  final String? initialEventId;
  final MuhuratService? service;

  const MuhuratFinderScreen({super.key, this.onAskPandit, this.initialEventId, this.service});

  static Future<void> open(BuildContext context, {VoidCallback? onAskPandit, String? eventId}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MuhuratFinderScreen(onAskPandit: onAskPandit, initialEventId: eventId)));

  @override
  State<MuhuratFinderScreen> createState() => _MuhuratFinderScreenState();
}

class _MuhuratFinderScreenState extends State<MuhuratFinderScreen> {
  late final MuhuratService _service =
      widget.service ?? MuhuratService(Provider.of<BackendService>(context, listen: false));
  List<MuhuratEvent> _events = MuhuratEvent.fallback;
  MuhuratEvent? _selected;
  MuhuratPlace _place = MuhuratPlace.delhi;
  MuhuratResponse? _result;
  bool _loading = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final place = await _service.savedPlace();
    final events = await _service.events();
    if (!mounted) return;
    setState(() {
      _place = place;
      _events = events;
    });
    final initial = widget.initialEventId;
    if (initial != null) {
      final e = events.where((x) => x.id == initial).firstOrNull;
      if (e != null) _select(e);
    }
  }

  void _select(MuhuratEvent e) {
    setState(() => _selected = e);
    _search();
  }

  Future<void> _search() async {
    final e = _selected;
    if (e == null) return;
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.find(e, _place);
      if (!mounted || token != _token) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } on BackendException catch (err) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = err.message;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  Future<void> _changePlace() async {
    final birth = _service.birthPlace();
    final picked = await showAppSheet<MuhuratPlace>(
      context,
      builder: (ctx) => _PlaceSheet(current: _place, birth: birth),
    );
    if (picked == null || !mounted) return;
    setState(() => _place = picked);
    await _service.savePlace(picked);
    _search();
  }

  Future<void> _remind(MuhuratDay d) async {
    final e = _selected;
    if (e == null) return;
    final n = await _service.addReminders(e, d);
    if (!mounted) return;
    showAppSnack(
      context,
      n == 0
          ? 'Could not set a reminder. Turn on notifications in settings (or the date is too close).'
          : n == 2
              ? 'Reminders set for the evening before (6 PM) and the morning (7 AM)'
              : 'Reminder set',
      error: n == 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Muhurat Finder')),
      body: RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
          children: [
            _hero(),
            const SizedBox(height: AppSpacing.lg),
            const Text('What are you planning?', style: AppText.title),
            const SizedBox(height: AppSpacing.sm),
            _EventGrid(events: _events, selected: _selected?.id, onTap: _select),
            const SizedBox(height: AppSpacing.md),
            _placeRow(),
            const SizedBox(height: AppSpacing.md),
            ..._resultsSection(),
          ],
        ),
      ),
    );
  }

  Widget _hero() => AppCard(
        gradient: AppColors.cosmicGradient,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.event_available_rounded, color: AppColors.gold, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('शुभ मुहूर्त', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
              SizedBox(height: 2),
              Text('Find an auspicious day',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Top 3 days in the next 30, from tithi, nakshatra, weekday and Rahu Kaal for your city.',
                  style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.35)),
            ]),
          ),
        ]),
      );

  Widget _placeRow() => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        onTap: _changePlace,
        child: Row(children: [
          const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Timings for ${_place.name}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
          ),
          TextButton(onPressed: _changePlace, child: const Text('Change')),
        ]),
      );

  List<Widget> _resultsSection() {
    final e = _selected;
    if (e == null) {
      return const [
        AppStateView(
          icon: Icons.touch_app_rounded,
          title: 'Pick an occasion above',
          message: 'We will check the next 30 days and show the three best days with a clean time window.',
          compact: true,
        ),
      ];
    }
    final out = <Widget>[];
    final note = _result?.event.id == e.id ? (_result?.event.note ?? e.note) : e.note;
    if (note != null) out.addAll([_NoteBanner(text: note, strong: e.id == 'surgery_or_medical'), const SizedBox(height: 12)]);

    if (_loading) {
      out.addAll(List.generate(
          3,
          (_) => const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: SkeletonBox(height: 190, radius: AppRadius.lg),
              )));
      return out;
    }
    if (_error != null) {
      out.add(AppStateView.error(message: _error, onAction: _search, compact: true));
      return out;
    }
    final r = _result;
    if (r == null) return out;
    out.add(Text('Best days for ${e.shortLabel}', style: AppText.title));
    out.add(const SizedBox(height: 4));
    out.add(Text(
        r.personal ? 'Includes your Moon sign and birth star (Tarabala / Chandrabala).' : 'General panchang days for your city.',
        style: AppText.caption));
    out.add(const SizedBox(height: AppSpacing.sm));
    if (r.results.isEmpty) {
      out.add(AppStateView(
        icon: Icons.event_busy_rounded,
        title: 'No clearly auspicious day soon',
        message: r.message ?? 'Try again later or ask a pandit for a personal muhurat.',
        actionLabel: widget.onAskPandit == null ? null : 'Ask a pandit',
        onAction: widget.onAskPandit,
        compact: true,
      ));
    }
    for (var i = 0; i < r.results.length; i++) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: MuhuratDayCard(
          day: r.results[i],
          rank: i + 1,
          onRemind: () => _remind(r.results[i]),
          onShare: () => _share(MuhuratService.shareText(r.event, r.results[i], _place.name)),
          onAskPandit: widget.onAskPandit,
        ),
      ));
    }
    if (r.avoided.isNotEmpty) out.add(_AvoidedCard(avoided: r.avoided));
    out.add(const SizedBox(height: AppSpacing.md));
    out.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textTertiary),
      const SizedBox(width: 6),
      Expanded(child: Text(r.disclaimer, style: AppText.caption)),
    ]));
    return out;
  }
}

class _EventGrid extends StatelessWidget {
  final List<MuhuratEvent> events;
  final String? selected;
  final ValueChanged<MuhuratEvent> onTap;
  const _EventGrid({required this.events, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 340 ? 2 : (c.maxWidth < 600 ? 3 : 4);
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final e in events)
            SizedBox(
              width: w,
              child: _EventChip(event: e, selected: e.id == selected, onTap: () => onTap(e)),
            ),
        ],
      );
    });
  }
}

class _EventChip extends StatelessWidget {
  final MuhuratEvent event;
  final bool selected;
  final VoidCallback onTap;
  const _EventChip({required this.event, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _iconColor(event.icon);
    return Semantics(
      button: true,
      selected: selected,
      label: event.shortLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? color.withValues(alpha: 0.10) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: selected ? color : AppColors.border, width: selected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('muhurat_event_${event.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(muhuratIcon(event.icon), color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(event.shortLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(event.labelHi,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NoteBanner extends StatelessWidget {
  final String text;
  final bool strong;
  const _NoteBanner({required this.text, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final color = strong ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: strong ? AppColors.dangerSoft : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(strong ? Icons.local_hospital_rounded : Icons.info_rounded, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13.5, height: 1.4, color: AppColors.textPrimary, fontWeight: strong ? FontWeight.w700 : FontWeight.w500)),
        ),
      ]),
    );
  }
}

/// One recommended day: big date, score ring, best window, reasons, cautions, actions.
class MuhuratDayCard extends StatelessWidget {
  final MuhuratDay day;
  final int rank;
  final VoidCallback onRemind;
  final VoidCallback onShare;
  final VoidCallback? onAskPandit;

  const MuhuratDayCard({
    super.key,
    required this.day,
    required this.rank,
    required this.onRemind,
    required this.onShare,
    this.onAskPandit,
  });

  @override
  Widget build(BuildContext context) {
    final w = day.bestWindow;
    return AppCard(
      shadow: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: rank == 1 ? AppColors.primaryGradient : null,
              color: rank == 1 ? null : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(children: [
              Text(DateFormat('MMM').format(day.date).toUpperCase(),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: rank == 1 ? Colors.white : AppColors.primaryDark)),
              Text('${day.date.day}',
                  style: TextStyle(
                      fontSize: 26, height: 1.1, fontWeight: FontWeight.w800, color: rank == 1 ? Colors.white : AppColors.primaryDark)),
            ]),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(day.weekday, style: AppText.title),
                if (rank == 1) const AppBadge(label: 'Best day', color: AppColors.success),
              ]),
              const SizedBox(height: 2),
              Text('${day.tithi} · ${day.nakshatra} nakshatra', style: AppText.body),
              Text('${day.yoga} yoga', style: AppText.caption),
            ]),
          ),
          const SizedBox(width: 8),
          _ScoreRing(score: day.score),
        ]),
        if (w != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: w.text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  TextSpan(text: '  ${w.label}', style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ])),
              ),
            ]),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        for (final r in day.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(r, style: AppText.body.copyWith(color: AppColors.textPrimary))),
            ]),
          ),
        for (final c in day.cautions)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(c, style: AppText.body)),
            ]),
          ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppButton(
              label: 'Add reminder',
              icon: Icons.notifications_active_outlined,
              onPressed: onRemind,
              expand: false,
              height: 40,
              variant: AppButtonVariant.secondary),
          AppButton(
              label: 'Share', icon: Icons.share_rounded, onPressed: onShare, expand: false, height: 40, variant: AppButtonVariant.outline),
          if (onAskPandit != null)
            AppButton(
                label: 'Ask a pandit to confirm',
                icon: Icons.chat_bubble_outline_rounded,
                onPressed: onAskPandit,
                expand: false,
                height: 40,
                variant: AppButtonVariant.ghost),
        ]),
      ]),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;
  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80 ? AppColors.success : (score >= 65 ? AppColors.primary : AppColors.warning);
    return Semantics(
      label: 'Score $score out of 100',
      excludeSemantics: true,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 5,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          FittedBox(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('$score', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AvoidedCard extends StatelessWidget {
  final List<MuhuratAvoided> avoided;
  const _AvoidedCard({required this.avoided});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.surfaceMuted,
      border: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Why other days were skipped', style: AppText.subtitle),
        const SizedBox(height: 6),
        for (final a in avoided.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.remove_circle_outline_rounded, size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${a.text} (${a.count} ${a.count == 1 ? 'day' : 'days'})', style: AppText.body),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _PlaceSheet extends StatelessWidget {
  final MuhuratPlace current;
  final MuhuratPlace? birth;
  const _PlaceSheet({required this.current, this.birth});

  @override
  Widget build(BuildContext context) {
    final places = [if (birth != null) birth!, ...MuhuratPlace.cities];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 4),
            child: Text('Choose your city', style: AppText.title),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text('Sunrise and Rahu Kaal depend on where the event happens.', style: AppText.caption),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in places)
                ListTile(
                  leading: Icon(p == birth ? Icons.cake_outlined : Icons.location_city_rounded, color: AppColors.primary),
                  title: Text(p.name),
                  trailing: p.name == current.name ? const Icon(Icons.check_rounded, color: AppColors.success) : null,
                  onTap: () => Navigator.of(context).pop(p),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
