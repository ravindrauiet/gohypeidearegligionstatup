import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../services/backend_service.dart' show BackendException;
import '../../services/rewards_service.dart';
import '../../widgets/rewards/coin_toast.dart';
import '../../widgets/rewards/reward_parts.dart';
import '../../widgets/ui/app_ui.dart';
import '../legal/community_guidelines_screen.dart';
import 'coins_screen.dart' show showTempleTripInfo;

/// Temple trip reward: locked progress until 10,000 coins, then a short
/// buddy -> temple -> month flow, plus the user's trip requests.
class TempleTripScreen extends StatefulWidget {
  /// Preselects this buddy (user id) when opened from a buddy's profile.
  final int? buddyId;
  const TempleTripScreen({super.key, this.buddyId});

  @override
  State<TempleTripScreen> createState() => _TempleTripScreenState();
}

class _TempleTripScreenState extends State<TempleTripScreen> {
  bool _loading = true;
  String? _error;
  bool _needsLogin = false;
  List<TripRequest> _trips = const [];

  // Planner
  int _step = 0; // 0 buddy, 1 temple, 2 month
  List<TripBuddy>? _buddies;
  String? _buddiesError;
  TripBuddy? _buddy;
  TempleList? _temples;
  bool _templesLoading = false;
  String? _templesError;
  Temple? _temple;
  String? _month;
  bool _submitting = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Each planner step starts at the top of the page (the temple list is long).
  void _setStep(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  RewardsService get _r => context.read<RewardsService>();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _needsLogin = false;
    });
    final r = _r;
    await r.refresh();
    if (!mounted) return;
    if (!r.loggedIn) {
      setState(() {
        _loading = false;
        _needsLogin = true;
      });
      return;
    }
    String? tripsError;
    try {
      final trips = await r.myTrips();
      if (!mounted) return;
      setState(() => _trips = trips);
    } on LoginRequiredException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsLogin = true;
      });
      return;
    } catch (e) {
      tripsError = e is BackendException ? e.message : 'Couldn\'t load your trip requests.';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      // Without the wallet there is nothing sensible to show (balance 0 would
      // look like "locked"), so a wallet failure is a full-screen error.
      if (!r.loaded) _error = r.error ?? tripsError ?? 'Could not load your coins. Please try again.';
    });
    if (r.loaded && tripsError != null) showAppSnack(context, tripsError, error: true);
    if (r.loaded && r.tripUnlocked && _buddies == null) await _loadBuddies();
  }

  bool _buddiesLoading = false;

  Future<void> _loadBuddies() async {
    if (_buddiesLoading || !mounted) return;
    setState(() {
      _buddiesError = null;
      _buddiesLoading = true;
    });
    try {
      final list = await _r.loadTripBuddies();
      if (!mounted) return;
      setState(() {
        _buddiesLoading = false;
        _buddies = list;
        if (widget.buddyId != null) {
          for (final b in list) {
            if (b.userId == widget.buddyId) _buddy = b;
          }
        }
      });
      if (_buddy != null && widget.buddyId != null && _step == 0) _goTemples();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buddiesLoading = false;
        _buddiesError = e is BackendException ? e.message : 'Couldn\'t load your buddies.';
      });
    }
  }

  Future<void> _goTemples() async {
    final b = _buddy;
    if (b == null) return;
    _setStep(1);
    setState(() {
      _templesLoading = true;
      _templesError = null;
      _temple = null;
    });
    try {
      final t = await _r.loadTemples(b.userId);
      if (!mounted || _buddy?.userId != b.userId) return; // buddy changed meanwhile
      setState(() {
        _temples = t;
        _templesLoading = false;
      });
    } catch (e) {
      if (!mounted || _buddy?.userId != b.userId) return;
      setState(() {
        _templesLoading = false;
        _templesError = e is BackendException ? e.message : 'Couldn\'t load temples.';
      });
    }
  }

  List<String> get _months {
    final now = istNow();
    return [
      for (var i = 1; i <= 12; i++)
        () {
          final d = DateTime(now.year, now.month + i);
          return '${d.year}-${d.month.toString().padLeft(2, '0')}';
        }(),
    ];
  }

  static String monthLabel(String ym) {
    final p = ym.split('-');
    final y = p.isNotEmpty ? int.tryParse(p[0]) : null;
    final m = p.length > 1 ? int.tryParse(p[1]) : null;
    if (y == null || m == null) return ym;
    return DateFormat('MMMM yyyy').format(DateTime(y, m));
  }

  Future<void> _confirm() async {
    final b = _buddy, t = _temple, m = _month;
    if (b == null || t == null || m == null) return;
    final r = _r;
    final ok = await showAppSheet<bool>(
      context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Confirm your trip request', style: AppText.headline),
          const SizedBox(height: AppSpacing.lg),
          _SummaryRow(icon: Icons.temple_hindu_rounded, label: 'Temple', value: '${t.name}${t.place.isEmpty ? '' : ', ${t.place}'}'),
          _SummaryRow(icon: Icons.people_alt_rounded, label: 'With', value: b.displayName),
          _SummaryRow(icon: Icons.calendar_month_rounded, label: 'Month', value: monthLabel(m)),
          _SummaryRow(icon: Icons.toll_rounded, label: 'Coins used', value: formatCoins(r.goal)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: const Text(
              'Our team will review your request and contact you both to arrange it. If it can\'t be arranged, or you '
              'cancel while it\'s pending, your coins are refunded. Coins are not money; terms apply.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Send request', onPressed: () => Navigator.of(ctx).pop(true)),
          const SizedBox(height: AppSpacing.xs),
          AppButton(label: 'Not now', variant: AppButtonVariant.ghost, onPressed: () => Navigator.of(ctx).pop(false)),
        ]),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      final req = await r.requestTrip(buddyId: b.userId, templeId: t.id, preferredMonth: m);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _trips = [req, ..._trips.where((x) => x.id != req.id)];
        _step = 0;
        _buddy = null;
        _temple = null;
        _month = null;
      });
      showAppSnack(context, 'Request sent! Our team will be in touch.');
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppSnack(
          context, e is BackendException || e is LoginRequiredException ? e.toString() : 'Couldn\'t send the request.',
          error: true);
      // e.g. INSUFFICIENT_COINS / NOT_BUDDIES: the numbers on screen are stale.
      if (e is BackendException && e.statusCode != null) _load();
    }
  }

  final Set<String> _cancelling = {};

  Future<void> _cancel(TripRequest t) async {
    if (_cancelling.contains(t.id)) return;
    final refund = t.coinsSpent > 0 ? t.coinsSpent : _r.goal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text('Your ${formatCoins(refund)} coins will be returned to your balance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling.add(t.id));
    try {
      final updated = await _r.cancelTrip(t.id);
      if (!mounted) return;
      setState(() {
        _cancelling.remove(t.id);
        if (updated != null) _trips = [for (final x in _trips) x.id == updated.id ? updated : x];
      });
      showCoinToast(context, refund, reason: 'Trip cancelled, coins refunded');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling.remove(t.id));
      showAppSnack(context, e is BackendException || e is LoginRequiredException ? e.toString() : 'Couldn\'t cancel.',
          error: true);
      if (e is BackendException && e.statusCode == 409) _load(); // no longer pending
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RewardsService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Temple trip'),
        actions: [
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showTempleTripInfo(context),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body(r)),
    );
  }

  Widget _body(RewardsService r) {
    if (_loading && !r.loaded) return const Center(child: CircularProgressIndicator());
    if (_needsLogin) {
      return ListView(children: [
        AppStateView(
          icon: Icons.lock_outline_rounded,
          title: 'Log in to plan a temple trip',
          message: 'Coins and trips are saved to your account.',
          actionLabel: 'Log in',
          onAction: () => Navigator.of(context).pushNamed('/login'),
        ),
      ]);
    }
    if (_error != null) return ListView(children: [AppStateView.error(message: _error, onAction: _load)]);
    if (!r.loaded) return const Center(child: CircularProgressIndicator());

    // Unlocked later (e.g. after a refund) without buddies loaded yet.
    if (r.tripUnlocked && _buddies == null && !_buddiesLoading && _buddiesError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBuddies());
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
      children: [
        if (!r.tripUnlocked) _Locked(r: r) else _planner(r),
        if (_trips.isNotEmpty) ...[
          const SectionHeader(
            title: 'My trip requests',
            padding: EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
          ),
          for (final t in _trips)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TripCard(
                trip: t,
                cancelling: _cancelling.contains(t.id),
                onCancel: t.canCancel ? () => _cancel(t) : null,
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TermsLink(
            label: 'Temple trip terms',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CommunityGuidelinesScreen(initialSection: GuidelinesSection.trip),
            )),
          ),
        ),
      ],
    );
  }

  Widget _planner(RewardsService r) {
    final steps = ['Buddy', 'Temple', 'Month'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        gradient: AppColors.cosmicGradient,
        child: Row(children: [
          const CoinIcon(size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your temple trip is unlocked',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              Text('${formatCoins(r.balance)} coins available',
                  style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: 4),
              Text(steps[i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == _step ? AppColors.primaryDark : AppColors.textTertiary)),
            ]),
          ),
        ],
      ]),
      const SizedBox(height: AppSpacing.lg),
      switch (_step) {
        0 => _buddyStep(),
        1 => _templeStep(),
        _ => _monthStep(),
      },
    ]);
  }

  Widget _stepNav({required String next, VoidCallback? onNext, bool loading = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(children: [
        if (_step > 0) ...[
          AppButton(
            label: 'Back',
            expand: false,
            variant: AppButtonVariant.outline,
            onPressed: () => _setStep(_step - 1),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: AppButton(label: next, onPressed: onNext, loading: loading)),
      ]),
    );
  }

  Widget _buddyStep() {
    final list = _buddies;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Who is coming with you?', style: AppText.title),
      const SizedBox(height: 4),
      const Text('Pick one of your buddies.', style: AppText.body),
      const SizedBox(height: AppSpacing.md),
      if (_buddiesError != null)
        AppStateView.error(compact: true, message: _buddiesError, onAction: _loadBuddies)
      else if (list == null || _buddiesLoading)
        const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
      else if (list.isEmpty)
        const AppCard(
          child: AppStateView(
            compact: true,
            icon: Icons.people_outline_rounded,
            title: 'No buddies yet',
            message: 'Once someone accepts your buddy request, you can plan a trip together.',
          ),
        )
      else ...[
        for (final b in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _SelectCard(
              selected: _buddy?.userId == b.userId,
              onTap: () => setState(() => _buddy = b),
              leading: AppAvatar(imageUrl: b.photoUrl, name: b.displayName, size: 44),
              title: b.displayName,
              subtitle: [if (b.city.isNotEmpty) b.city, if (b.score != null) '${b.score}% match'].join(' · '),
            ),
          ),
        _stepNav(next: 'Choose a temple', onNext: _buddy == null ? null : _goTemples),
      ],
    ]);
  }

  Widget _templeStep() {
    final t = _temples;
    Widget card(Temple x) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _TempleCard(temple: x, selected: _temple?.id == x.id, onTap: () => setState(() => _temple = x)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Where would you like to go${_buddy == null ? '' : ' with ${_buddy!.displayName}'}?', style: AppText.title),
      const SizedBox(height: 4),
      const Text('Distances are from the midpoint between you two.', style: AppText.body),
      const SizedBox(height: AppSpacing.md),
      if (_templesLoading)
        const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
      else if (_templesError != null)
        AppStateView.error(compact: true, message: _templesError, onAction: _goTemples)
      else if (t != null) ...[
        if (t.recommendedTemples.isNotEmpty) ...[
          const Text('RECOMMENDED FOR YOU TWO', style: AppText.overline),
          const SizedBox(height: AppSpacing.xs),
          for (final x in t.recommendedTemples) card(x),
          const SizedBox(height: AppSpacing.sm),
          const Text('MORE TEMPLES', style: AppText.overline),
          const SizedBox(height: AppSpacing.xs),
        ],
        for (final x in t.others) card(x),
      ],
      _stepNav(next: 'Choose a month', onNext: _temple == null ? null : () => _setStep(2)),
    ]);
  }

  Widget _monthStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('When would you like to travel?', style: AppText.title),
      const SizedBox(height: 4),
      const Text('Pick a preferred month. We\'ll confirm exact dates with you both.', style: AppText.body),
      const SizedBox(height: AppSpacing.md),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in _months)
          AppFilterChip(
            label: monthLabel(m),
            selected: _month == m,
            onTap: () => setState(() => _month = m),
          ),
      ]),
      _stepNav(next: 'Review request', onNext: _month == null ? null : _confirm, loading: _submitting),
    ]);
  }
}

class _Locked extends StatelessWidget {
  final RewardsService r;
  const _Locked({required this.r});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Column(children: [
          CoinProgressRing(
            progress: r.progress,
            size: 132,
            stroke: 11,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_rounded, color: AppColors.gold, size: 26),
              const SizedBox(height: 2),
              Text('${(r.progress * 100).floor()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('A temple trip with your buddy',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            '${formatCoins(r.balance)} of ${formatCoins(r.goal)} coins. ${formatCoins(r.coinsToGoal)} more to unlock.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 14, height: 1.4),
          ),
        ]),
      ),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fastest ways to get there', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.sm),
          _tip(Icons.psychology_alt_rounded, 'Answer mindset questions', '+50 each'),
          _tip(Icons.sports_esports_rounded, 'Play the 4 daily games', '+10 each'),
          _tip(Icons.wb_sunny_rounded, 'Check in every day', '+1'),
          _tip(Icons.play_circle_fill_rounded, 'Watch new videos', '+1 each'),
        ]),
      ),
    ]);
  }

  Widget _tip(IconData icon, String text, String coins) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.bodyStrong)),
          const CoinIcon(size: 14),
          const SizedBox(width: 4),
          Text(coins, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9A6400))),
        ]),
      );
}

class _SelectCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? below;

  const _SelectCard({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    this.subtitle = '',
    this.below,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              leading,
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppText.subtitle),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                  if (below != null) ...[const SizedBox(height: 6), below!],
                ]),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : AppColors.textTertiary),
            ]),
          ),
        ),
      ),
    );
  }
}

(IconData, Color) _deityStyle(String deity) {
  final d = deity.toLowerCase();
  if (d.contains('shiv') || d.contains('mahadev') || d.contains('jyotir')) {
    return (Icons.temple_hindu_rounded, AppColors.cosmicLight);
  }
  if (d.contains('devi') || d.contains('mata') || d.contains('shakti') || d.contains('durga') || d.contains('kali')) {
    return (Icons.local_florist_rounded, AppColors.love);
  }
  if (d.contains('vishnu') || d.contains('krishna') || d.contains('balaji') || d.contains('venkate') || d.contains('jagannath') || d.contains('ram')) {
    return (Icons.spa_rounded, AppColors.info);
  }
  if (d.contains('guru') || d.contains('sikh')) return (Icons.wb_sunny_rounded, AppColors.warning);
  return (Icons.temple_hindu_rounded, AppColors.primary);
}

class _TempleCard extends StatelessWidget {
  final Temple temple;
  final bool selected;
  final VoidCallback onTap;
  const _TempleCard({required this.temple, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _deityStyle(temple.deity);
    final meta = [
      if (temple.place.isNotEmpty) temple.place,
      if (temple.distanceKm != null) '~${formatCoins(temple.distanceKm!)} km',
    ].join(' · ');
    return _SelectCard(
      selected: selected,
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: color, size: 26),
      ),
      title: temple.name,
      subtitle: [if (temple.deity.isNotEmpty) temple.deity, if (meta.isNotEmpty) meta].join(' · '),
      below: temple.why.isEmpty ? null : Text(temple.why, style: AppText.body.copyWith(fontSize: 13)),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          SizedBox(width: 84, child: Text(label, style: AppText.body)),
          Expanded(child: Text(value, style: AppText.bodyStrong)),
        ]),
      );
}

class _TripCard extends StatelessWidget {
  final TripRequest trip;
  final VoidCallback? onCancel;
  final bool cancelling;
  const _TripCard({required this.trip, this.onCancel, this.cancelling = false});

  @override
  Widget build(BuildContext context) {
    // Refunds go to whoever paid, so only say "refunded" on my own requests.
    final refunded = trip.mine ? ' · refunded' : '';
    final (String label, Color color) = switch (trip.status) {
      'pending' => ('Under review', AppColors.warning),
      'approved' || 'confirmed' || 'arranged' => ('Confirmed', AppColors.success),
      'completed' => ('Completed', AppColors.success),
      'rejected' || 'declined' => ('Not arranged$refunded', AppColors.danger),
      'cancelled' || 'canceled' => ('Cancelled$refunded', AppColors.textTertiary),
      _ => (trip.status.isEmpty ? 'Pending' : trip.status[0].toUpperCase() + trip.status.substring(1), AppColors.info),
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The badge may take at most half the row, so long statuses
        // ("Cancelled · refunded") ellipsize at 320px / large text.
        LayoutBuilder(
          builder: (context, c) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(trip.temple.name, style: AppText.subtitle)),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth / 2),
              child: AppBadge(label: label, color: color),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        Text(
          [
            trip.mine ? 'With ${trip.buddy.displayName}' : 'Invited by ${trip.buddy.displayName}',
            if (trip.preferredMonth.isNotEmpty) _TempleTripScreenState.monthLabel(trip.preferredMonth),
          ].join(' · '),
          style: AppText.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (onCancel != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: cancelling ? null : onCancel,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger, padding: EdgeInsets.zero),
              child: Text(cancelling ? 'Cancelling...' : 'Cancel request'),
            ),
          ),
        ],
      ]),
    );
  }
}
