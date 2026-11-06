import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import '../tabs/love_tab.dart';
import '../trust/biodata_edit_screen.dart';
import '../trust/family_notes_screen.dart';
import '../trust/family_share_screen.dart';
import '../trust/verification_screen.dart';
import 'buddy_connections_view.dart';
import 'buddy_discover_view.dart';
import 'buddy_onboarding_screen.dart';

/// Sections of [BuddyHubTab].
class BuddyHubSection {
  BuddyHubSection._();
  static const discover = 0;
  static const requests = 1;
  static const buddies = 2;
  static const kundli = 3;
}

/// Bottom-nav tab 4: "Find your buddy" (Discover | Requests | Buddies |
/// Kundli match). The classic Guna Milan [LoveTab] lives in "Kundli match".
class BuddyHubTab extends StatefulWidget {
  const BuddyHubTab({super.key});

  /// Set to a [BuddyHubSection] value to switch section from elsewhere
  /// (e.g. before `HomeScreen.switchTab(context, 4)`).
  static final ValueNotifier<int> sectionNotifier = ValueNotifier(BuddyHubSection.discover);

  @override
  State<BuddyHubTab> createState() => _BuddyHubTabState();
}

class _BuddyHubTabState extends State<BuddyHubTab> {
  int _section = BuddyHubTab.sectionNotifier.value;
  final Set<int> _built = {};
  String? _authKey;

  @override
  void initState() {
    super.initState();
    BuddyHubTab.sectionNotifier.addListener(_onExternalSection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Provider.of<BackendService>(context);
    final key = '${b.isAuthenticated}:${b.user?['id']}:${b.hasBirthDetails}';
    if (key != _authKey) {
      final first = _authKey == null;
      _authKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus(force: !first));
    }
  }

  @override
  void dispose() {
    BuddyHubTab.sectionNotifier.removeListener(_onExternalSection);
    super.dispose();
  }

  void _onExternalSection() => _select(BuddyHubTab.sectionNotifier.value);

  void _select(int i) {
    if (i == _section) return;
    setState(() => _section = i);
    final s = context.read<BuddyService>();
    if ((i == BuddyHubSection.requests || i == BuddyHubSection.buddies) && s.hasActiveProfile) {
      s.loadConnections().catchError((_) => s.connections);
    }
  }

  Future<void> _loadStatus({bool force = false}) async {
    if (!mounted) return;
    final s = context.read<BuddyService>();
    try {
      final st = await s.loadStatus(force: force);
      if (st.eligible && st.isActive) await s.loadConnections();
    } catch (_) {
      // Shown via statusError.
    }
  }

  Future<void> _openOnboarding({BuddyProfile? initial}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BuddyOnboardingScreen(initial: initial)),
    );
    if (saved == true && mounted) {
      setState(() => _built.clear());
      _loadStatus();
    }
  }

  Future<void> _togglePause(BuddyProfile p) async {
    final s = context.read<BuddyService>();
    try {
      if (p.isActive) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pause your buddy profile?'),
            content: const Text('You will be hidden from Discover and Nearby. Your buddies and chats stay safe.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep visible')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pause')),
            ],
          ),
        );
        if (ok != true) return;
        await s.pauseProfile();
        if (mounted) showAppSnack(context, 'Profile paused');
      } else {
        await s.resumeProfile();
        if (mounted) {
          setState(() => _built.clear());
          showAppSnack(context, 'Welcome back! Your profile is visible again');
        }
      }
    } catch (e) {
      if (mounted) showAppSnack(context, BuddyService.errorText(e), error: true);
    }
  }

  void _showSafetyTips() {
    showAppSheet<void>(context, builder: (_) => const _SafetyTipsSheet());
  }

  // ------------------------------------------------------------------ UI

  Widget _segmented(BuddyService s) {
    final labels = [
      ('Discover', Icons.explore_rounded, 0),
      ('Requests', Icons.mark_email_unread_rounded, s.incomingCount),
      ('Buddies', Icons.forum_rounded, s.unreadCount),
      ('Kundli match', Icons.favorite_rounded, 0),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: _section == i,
                label: labels[i].$3 > 0 ? '${labels[i].$1}, ${labels[i].$3} new' : labels[i].$1,
                excludeSemantics: true,
                onTap: () => _select(i),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _select(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: _section == i ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                      boxShadow: _section == i ? AppShadows.card : null,
                    ),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            labels[i].$1,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _section == i ? FontWeight.w800 : FontWeight.w600,
                              color: _section == i ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                          if (labels[i].$3 > 0) ...[const SizedBox(width: 4), BuddyCountBadge(labels[i].$3)],
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// Gate / hero / paused card for sections 0-2, or null if ready.
  Widget? _gate(BuddyService s, BackendService b) {
    final st = s.status;
    if (!b.isAuthenticated || st?.gate == BuddyGate.loginRequired) {
      return _GateView(
        icon: Icons.lock_person_rounded,
        title: 'Log in to find your buddy',
        message: 'Buddies are real, verified members. Log in or create a free account to start.',
        actionLabel: 'Log in',
        onAction: () => Navigator.pushNamed(context, '/login'),
      );
    }
    if (st == null) {
      if (s.statusError != null) {
        return Center(child: AppStateView.error(message: s.statusError, onAction: () => _loadStatus(force: true)));
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (st.gate == BuddyGate.banned) {
      return const _GateView(
        icon: Icons.gpp_maybe_outlined,
        title: 'Buddy profile suspended',
        message: BuddyService.bannedMessage,
      );
    }
    if (st.gate == BuddyGate.under18) {
      return const _GateView(
        icon: Icons.child_care_rounded,
        title: 'Buddies is for adults (18+)',
        message: 'Based on your Kundli birth date you are under 18, so this space is not open for you yet. '
            'You can still enjoy Kundli match, games and your daily guidance.',
      );
    }
    if (!st.eligible || st.gate == BuddyGate.noKundli) {
      return _GateView(
        icon: Icons.auto_awesome_rounded,
        title: 'First, create your Kundli',
        message: 'We match buddies with your birth chart, so we need your birth details first. It takes a minute.',
        actionLabel: 'Create my Kundli',
        onAction: () async {
          await Navigator.pushNamed(context, '/birth-details');
          _loadStatus(force: true);
        },
      );
    }
    final p = st.profile;
    if (p == null) return _BuddyHero(onCreate: () => _openOnboarding());
    if (!p.isActive) {
      return _GateView(
        icon: Icons.pause_circle_outline_rounded,
        title: 'Your buddy profile is paused',
        message: "You're hidden from everyone right now. Resume whenever you're ready.",
        actionLabel: 'Resume my profile',
        onAction: () => _togglePause(p),
      );
    }
    return null;
  }

  Widget _sectionBody(int i) {
    switch (i) {
      case BuddyHubSection.discover:
        return const BuddyDiscoverView();
      case BuddyHubSection.requests:
        return const BuddyRequestsView();
      case BuddyHubSection.buddies:
        return const BuddyListView();
      default:
        // LoveTab brings its own app bar; we are already below the status bar.
        return MediaQuery.removePadding(context: context, removeTop: true, child: const LoveTab());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BuddyService>();
    final b = context.watch<BackendService>();
    final gate = _gate(s, b);
    final p = s.profile;
    _built.add(_section);

    Widget body;
    if (gate != null && _section != BuddyHubSection.kundli) {
      body = KeyedSubtree(key: const ValueKey('gate'), child: gate);
    } else {
      body = IndexedStack(
        index: _section,
        children: [
          for (var i = 0; i < 4; i++)
            if (_built.contains(i) && (i == BuddyHubSection.kundli || gate == null))
              _sectionBody(i)
            else
              const SizedBox.shrink(),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Find your buddy'),
        actions: [
          IconButton(
            tooltip: 'Safety tips',
            icon: const Icon(Icons.shield_outlined),
            onPressed: _showSafetyTips,
          ),
          if (p != null && !(s.status?.isBanned ?? false))
            PopupMenuButton<String>(
              tooltip: 'Profile options',
              icon: const Icon(Icons.manage_accounts_outlined),
              onSelected: (v) {
                if (v == 'edit') _openOnboarding(initial: p);
                if (v == 'pause') _togglePause(p);
                final screen = switch (v) {
                  'verify' => const VerificationScreen(),
                  'biodata' => const BiodataEditScreen(),
                  'family' => const FamilyShareScreen(),
                  'notes' => const FamilyNotesScreen(),
                  _ => null,
                };
                if (screen != null) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit my profile')),
                ),
                PopupMenuItem(
                  value: 'verify',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_outlined, color: Color(0xFF1D6FE0)),
                    title: Text(p.verified ? 'Verified' : 'Get verified'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'biodata',
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined),
                      title: Text('Biodata details')),
                ),
                const PopupMenuItem(
                  value: 'family',
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.family_restroom_rounded),
                      title: Text('Share with family')),
                ),
                const PopupMenuItem(
                  value: 'notes',
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.mark_chat_read_outlined),
                      title: Text('Family notes')),
                ),
                PopupMenuItem(
                  value: 'pause',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
                    title: Text(p.isActive ? 'Pause my profile' : 'Resume my profile'),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        _segmented(s),
        Expanded(child: body),
      ]),
    );
  }
}

// ------------------------------------------------------------------ pieces

class _GateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GateView({required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: AppText.title),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: AppText.body),
            if (onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: actionLabel ?? 'Continue', onPressed: onAction),
            ],
          ]),
        ),
      ],
    );
  }
}

class _BuddyHero extends StatelessWidget {
  final VoidCallback onCreate;
  const _BuddyHero({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.brightness_3_rounded, 'Kundli harmony', 'Moon, nakshatra and lagna, plus Guna Milan for life partners'),
      (Icons.psychology_rounded, 'How you think', '50 short mindset questions about values, money, family and faith'),
      (Icons.near_me_rounded, 'How near you are', 'Approximate distance only, never your exact location'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
      children: [
        AppCard(
          gradient: AppColors.cosmicGradient,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('NEW · FIND YOUR BUDDY',
                style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            const SizedBox(height: AppSpacing.sm),
            const Text('People who truly fit you',
                style: TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
            const SizedBox(height: 6),
            const Text(
              'A life partner, a business partner, a friend, a travel or satsang buddy. Matched by your stars, your mind and your city.',
              style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final i in BuddyIntent.all)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(BuddyIntentStyle.icon(i), size: 15, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(BuddyIntent.label(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Create my buddy profile', icon: Icons.arrow_forward_rounded, onPressed: onCreate),
          ]),
        ),
        const SectionHeader(
            title: 'How matching works', padding: EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm)),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const Divider(indent: 68),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                  child: Icon(steps[i].$1, color: AppColors.primary, size: 22),
                ),
                title: Text(steps[i].$2),
                subtitle: Text(steps[i].$3),
              ),
            ],
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
        const BuddyNote(
          icon: Icons.lock_outline_rounded,
          color: AppColors.success,
          text: 'Private by design: others only see your name, age, city, bio and the match score. '
              'Your birth details, chart, answers and AI chats are never shared. Chat opens only when both say yes.',
        ),
      ],
    );
  }
}

class _SafetyTipsSheet extends StatelessWidget {
  const _SafetyTipsSheet();

  @override
  Widget build(BuildContext context) {
    const tips = [
      (Icons.chat_outlined, 'Chat here first', 'Get to know someone inside the app before sharing your number.'),
      (
        Icons.storefront_outlined,
        'Meet in public',
        'First meetings in busy public places or temples. Tell family where you are.'
      ),
      (Icons.currency_rupee_rounded, 'Never send money', 'No one genuine asks for money, gifts, OTPs or bank details.'),
      (
        Icons.flag_outlined,
        'Report and block',
        'Use the ⋮ menu on any person. Reports are private and reviewed by our team.'
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Stay safe with buddies', style: AppText.title),
        const SizedBox(height: AppSpacing.sm),
        for (final t in tips)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(t.$1, color: AppColors.success),
            title: Text(t.$2),
            subtitle: Text(t.$3),
          ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(label: 'Got it', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(context)),
      ]),
    );
  }
}
