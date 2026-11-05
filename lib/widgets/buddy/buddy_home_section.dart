import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/buddy/buddy_onboarding_screen.dart';
import '../../screens/buddy/buddy_profile_screen.dart';
import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../ui/app_ui.dart';
import 'buddy_candidate_card.dart';
import 'buddy_ui.dart';

/// Home feed section "Find your buddy": an invitation when there's no
/// profile yet, otherwise a rail of the top 6 matches + "See all".
class BuddyHomeSection extends StatefulWidget {
  /// Opens the Buddy tab (e.g. `() => HomeScreen.switchTab(context, 4)`).
  final VoidCallback? onOpenBuddies;

  const BuddyHomeSection({super.key, this.onOpenBuddies});

  @override
  State<BuddyHomeSection> createState() => _BuddyHomeSectionState();
}

class _BuddyHomeSectionState extends State<BuddyHomeSection> {
  bool _loadingMatches = false;
  String? _authKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Provider.of<BackendService>(context);
    final key = '${b.isAuthenticated}:${b.user?['id']}';
    if (key != _authKey) {
      _authKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final s = context.read<BuddyService>();
    if (!context.read<BackendService>().isAuthenticated) return;
    try {
      final st = await s.loadStatus();
      if (st.eligible && st.isActive && s.topMatches == null && mounted) {
        setState(() => _loadingMatches = true);
        await s.loadTopMatches();
      }
    } catch (_) {
      // Quietly fall back to the invitation card.
    } finally {
      if (mounted && _loadingMatches) setState(() => _loadingMatches = false);
    }
  }

  void _open() {
    if (widget.onOpenBuddies != null) {
      widget.onOpenBuddies!();
      return;
    }
    final s = context.read<BuddyService>();
    if (s.status?.eligible == true && s.profile == null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BuddyOnboardingScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BuddyService>();
    final st = s.status;
    // Under 18: don't advertise a space they can't use.
    // Suspended: nothing to offer here either (the Buddy tab explains).
    if (st?.gate == BuddyGate.under18 || st?.gate == BuddyGate.banned) return const SizedBox.shrink();
    final ready = st != null && st.eligible && st.isActive;
    if (!ready) return _Invitation(onTap: _open, hasProfile: st?.profile != null);

    final matches = s.topMatches ?? const <BuddyCandidate>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SectionHeader(
        title: 'Find your buddy',
        eyebrow: true,
        subtitle: 'Your strongest matches today',
        onAction: widget.onOpenBuddies,
        actionLabel: 'See all',
      ),
      SizedBox(
        height: 196,
        child: _loadingMatches && matches.isEmpty
            ? ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, __) =>
                    const SkeletonBox(width: BuddyMiniTile.width, height: 180, radius: AppRadius.lg),
              )
            : matches.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                    child: AppCard(
                      onTap: widget.onOpenBuddies,
                      child: const Center(
                        child: AppStateView(
                          compact: true,
                          icon: Icons.travel_explore_rounded,
                          title: 'New matches are on their way',
                          message: 'Answer more mindset questions to find people faster.',
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (_, i) => BuddyMiniTile(
                      candidate: matches[i],
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => BuddyProfileScreen(userId: matches[i].userId, initial: matches[i]),
                      )),
                    ),
                  ),
      ),
    ]);
  }
}

class _Invitation extends StatelessWidget {
  final VoidCallback onTap;
  final bool hasProfile;
  const _Invitation({required this.onTap, required this.hasProfile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
      child: Semantics(
        button: true,
        label: 'Find your buddy. Life partner, business partner, friend, travel or satsang buddy.',
        excludeSemantics: true,
        onTap: onTap,
        child: AppCard(
          gradient: AppColors.cosmicGradient,
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('NEW · FIND YOUR BUDDY',
                    style: TextStyle(
                        color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
              ),
              Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.5), size: 18),
            ]),
            const SizedBox(height: AppSpacing.xs),
            const Text('Someone who truly fits you',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 4),
            const Text('Matched by your Kundli, how you think and how near you are.',
                style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              for (final i in BuddyIntent.all)
                Expanded(
                  child: Column(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(BuddyIntentStyle.icon(i), color: Colors.white, size: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      BuddyIntent.label(i).split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
            ]),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: hasProfile ? 'Open buddies' : 'Create my buddy profile',
              icon: Icons.arrow_forward_rounded,
              height: 46,
              onPressed: onTap,
            ),
          ]),
        ),
      ),
    );
  }
}
