import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_candidate_card.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import 'buddy_connect_sheet.dart';
import 'buddy_links.dart';
import 'buddy_profile_screen.dart';

const _distanceSteps = [5, 10, 25, 50, 100, 250, 500, 0]; // 0 = anywhere

/// Intent chips + distance slider + candidate cards.
class BuddyDiscoverView extends StatefulWidget {
  const BuddyDiscoverView({super.key});

  @override
  State<BuddyDiscoverView> createState() => _BuddyDiscoverViewState();
}

class _BuddyDiscoverViewState extends State<BuddyDiscoverView> {
  String _intent = 'all';
  int _distanceIdx = 4; // 100 km
  List<BuddyCandidate>? _items;
  bool _loading = true;
  String? _error;
  final Set<int> _skipped = {};
  int _req = 0;
  bool _locating = false;

  int? get _maxKm => _distanceSteps[_distanceIdx] == 0 ? null : _distanceSteps[_distanceIdx];

  String get _distanceLabel => _maxKm == null ? 'Anywhere' : 'Within $_maxKm km';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // "Anywhere" omits maxKm: the server then doesn't filter by distance.
      final list = await context.read<BuddyService>().discover(intent: _intent, maxKm: _maxKm);
      if (!mounted || req != _req) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _loading = false;
        _error = BuddyService.errorText(e);
      });
      // With cards still on screen the error view is hidden: say so briefly.
      if (_items?.isNotEmpty ?? false) showAppSnack(context, _error!, error: true);
    }
  }

  void _remove(int userId) => setState(() => _items = _items?.where((c) => c.userId != userId).toList());

  Future<void> _connect(BuddyCandidate c) async {
    final ref = await showBuddyConnectSheet(context, c, preferredIntent: _intent == 'all' ? null : _intent);
    if (ref != null && mounted) _remove(c.userId);
  }

  Future<void> _open(BuddyCandidate c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BuddyProfileScreen(userId: c.userId, initial: c),
    ));
    if (!mounted) return;
    final s = context.read<BuddyService>();
    if (s.isHidden(c.userId)) _remove(c.userId);
  }

  Future<void> _shareLocation() async {
    final s = context.read<BuddyService>();
    setState(() => _locating = true);
    final r = await s.updateLocation(city: s.profile?.city);
    if (!mounted) return;
    setState(() => _locating = false);
    if (r == BuddyLocationResult.updated) {
      showAppSnack(context, 'Location updated (approximate only)');
      _load();
    } else {
      showAppSnack(
        context,
        switch (r) {
          BuddyLocationResult.serviceDisabled => 'Location is turned off on this device. We\'ll keep matching by city.',
          BuddyLocationResult.deniedForever =>
            'Location permission is blocked in your phone settings. We\'ll keep matching by city.',
          BuddyLocationResult.denied => "No problem. We'll keep matching by city.",
          _ => "Couldn't get your location. We'll keep matching by city.",
        },
        error: r == BuddyLocationResult.failed,
      );
    }
  }

  Widget _filters() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 8),
          children: [
            for (final i in ['all', ...BuddyIntent.all])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppFilterChip(
                  label: i == 'all' ? 'All' : BuddyIntent.label(i),
                  icon: i == 'all' ? Icons.auto_awesome_rounded : BuddyIntentStyle.icon(i),
                  selected: _intent == i,
                  onTap: () {
                    if (_intent == i) return;
                    setState(() => _intent = i);
                    _load();
                  },
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.xs, 0),
        child: Row(children: [
          const Icon(Icons.near_me_outlined, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          SizedBox(
            width: 100,
            child: Text(_distanceLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
          ),
          Expanded(
            child: Slider(
              value: _distanceIdx.toDouble(),
              min: 0,
              max: (_distanceSteps.length - 1).toDouble(),
              divisions: _distanceSteps.length - 1,
              label: _distanceLabel,
              semanticFormatterCallback: (_) => _distanceLabel,
              onChanged: (v) => setState(() => _distanceIdx = v.round()),
              onChangeEnd: (_) => _load(),
            ),
          ),
        ]),
      ),
    ]);
  }

  List<Widget> _nudges(BuddyService s) {
    final st = s.status;
    final out = <Widget>[];
    if (st != null && !st.quizComplete) {
      final left = st.quizTotal - st.quizAnswered;
      out.add(AppCard(
        gradient: AppColors.cosmicGradient,
        onTap: BuddyLinks.hasMindsetQuiz ? () => BuddyLinks.openMindsetQuiz(context).then((_) => _load()) : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          const Icon(Icons.psychology_rounded, color: AppColors.gold, size: 30),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                st.quizAnswered == 0 ? 'Get much better matches' : '${st.quizAnswered}/${st.quizTotal} mindset answers',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                'Answer $left more mindset questions and earn up to ${left * 50} coins',
                style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12.5, height: 1.3),
              ),
            ]),
          ),
          if (BuddyLinks.hasMindsetQuiz) const Icon(Icons.chevron_right_rounded, color: Colors.white),
        ]),
      ));
    }
    final p = s.profile;
    if (p != null && p.showNearby && !p.hasLocation) {
      out.add(BuddyNote(
        icon: Icons.near_me_rounded,
        color: const Color(0xFF0E9F8A),
        text: 'Share your approximate location to see how far buddies are (we only ever show "~3 km").',
        trailing: TextButton(
          onPressed: _locating ? null : _shareLocation,
          child: Text(_locating ? '…' : 'Share'),
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BuddyService>();
    final items = (_items ?? const <BuddyCandidate>[])
        .where((c) => !_skipped.contains(c.userId) && !s.isHidden(c.userId))
        .toList();
    final nudges = _nudges(s);

    final children = <Widget>[
      _filters(),
      for (final n in nudges)
        Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
            child: n),
    ];

    if (_loading && _items == null) {
      for (var i = 0; i < 2; i++) {
        children.add(const Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
          child: SkeletonBox(height: 300, radius: AppRadius.lg),
        ));
      }
    } else if (_error != null && items.isEmpty) {
      children.add(AppStateView.error(message: _error, onAction: _load));
    } else if (items.isEmpty) {
      children.add(AppStateView(
        icon: Icons.travel_explore_rounded,
        title: _skipped.isNotEmpty ? "You've seen everyone for now" : 'No buddies here yet',
        message: 'Try another intent or a bigger distance. New people join every day.',
        actionLabel: _skipped.isNotEmpty ? 'Show skipped again' : 'Refresh',
        onAction: () {
          setState(() => _skipped.clear());
          _load();
        },
      ));
    } else {
      if (_loading) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: LinearProgressIndicator(minHeight: 2),
        ));
      }
      for (final c in items) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xs),
          child: BuddyCandidateCard(
            key: ValueKey('buddy-card-${c.userId}'),
            candidate: c,
            onOpen: () => _open(c),
            onSkip: () => setState(() => _skipped.add(c.userId)),
            onConnect: () => _connect(c),
            onRemoved: () => _remove(c.userId),
          ),
        ));
      }
    }
    children.add(const SizedBox(height: AppSpacing.xxl));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
    );
  }
}
