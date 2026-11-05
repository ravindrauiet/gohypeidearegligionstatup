import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/buddy/buddy_profile_screen.dart';
import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../ui/app_ui.dart';
import 'buddy_candidate_card.dart';

/// Wrap the Home tab with this. When Home is on screen (no other route on top),
/// at most once every 6 hours it checks /buddy/nearby and gently offers
/// candidates the user hasn't been shown before.
class NearbyBuddyWatcher extends StatefulWidget {
  final Widget child;

  /// Optional "See all" target (e.g. switch to the Buddy tab).
  final VoidCallback? onOpenBuddies;

  /// Overridable for tests.
  final Duration interval;
  final Duration initialDelay;

  const NearbyBuddyWatcher({
    super.key,
    required this.child,
    this.onOpenBuddies,
    this.interval = const Duration(hours: 6),
    this.initialDelay = const Duration(seconds: 3),
  });

  static const prefsLastCheck = 'buddy_nearby_last_check';
  static const prefsSeenIds = 'buddy_nearby_seen_ids';
  static const maxSeenIds = 200;

  /// Oldest first; keeps the newest [maxSeenIds] (so people shown recently
  /// are never forgotten and shown again).
  @visibleForTesting
  static List<String> mergeSeenIds(List<String> existing, Iterable<String> added) {
    final out = <String>[...existing.where((id) => !added.contains(id)), ...added];
    final deduped = <String>{...out}.toList();
    return deduped.length <= maxSeenIds ? deduped : deduped.sublist(deduped.length - maxSeenIds);
  }

  @override
  State<NearbyBuddyWatcher> createState() => _NearbyBuddyWatcherState();
}

class _NearbyBuddyWatcherState extends State<NearbyBuddyWatcher> with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule(widget.initialDelay);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule(widget.initialDelay);
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _check);
  }

  /// True only when this widget is what the user is looking at.
  bool get _onScreen {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    // Hidden IndexedStack children (other bottom tabs) have tickers disabled.
    return TickerMode.valuesOf(context).enabled;
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    final backend = context.read<BackendService>();
    if (!backend.isAuthenticated) {
      // Guests: nothing to do now; look again later (no network call).
      _schedule(const Duration(minutes: 5));
      return;
    }
    if (!_onScreen) {
      // Try again a bit later rather than interrupting.
      _schedule(const Duration(minutes: 1));
      return;
    }
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(NearbyBuddyWatcher.prefsLastCheck) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final since = Duration(milliseconds: now - last);
      if (last > 0 && since < widget.interval) {
        _schedule(widget.interval - since);
        return;
      }
      if (!mounted) return;
      final service = context.read<BuddyService>();
      final st = await service.loadStatus();
      final p = st.profile;
      if (!st.eligible || p == null || !p.isActive || !p.showNearby) return;

      // Record the attempt first, so a failing server is also asked at most
      // once per interval (resumes don't retry it).
      await prefs.setInt(NearbyBuddyWatcher.prefsLastCheck, now);
      final list = await service.nearby();
      final seenList = prefs.getStringList(NearbyBuddyWatcher.prefsSeenIds) ?? const <String>[];
      final seen = seenList.toSet();
      final fresh = list.where((c) => !seen.contains('${c.userId}') && c.connection == null).take(5).toList();
      if (fresh.isEmpty || !_onScreen) return;

      await prefs.setStringList(
          NearbyBuddyWatcher.prefsSeenIds, NearbyBuddyWatcher.mergeSeenIds(seenList, fresh.map((c) => '${c.userId}')));
      if (!mounted) return;
      await showAppSheet<void>(
        context,
        builder: (_) => _NearbySheet(candidates: fresh, onOpenBuddies: widget.onOpenBuddies),
      );
    } catch (_) {
      // Never bother the user with errors from a background check.
    } finally {
      _checking = false;
      if (mounted && (_timer == null || !_timer!.isActive)) _schedule(widget.interval);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NearbySheet extends StatelessWidget {
  final List<BuddyCandidate> candidates;
  final VoidCallback? onOpenBuddies;
  const _NearbySheet({required this.candidates, this.onOpenBuddies});

  void _view(BuildContext context, BuddyCandidate c) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute<void>(builder: (_) => BuddyProfileScreen(userId: c.userId, initial: c)));
  }

  @override
  Widget build(BuildContext context) {
    final n = candidates.length;
    final title = n == 1 ? '1 buddy near you' : '$n buddies near you';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.near_me_rounded, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.title),
                const Text('Strong matches within about 10 km', style: AppText.caption),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            itemCount: n,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) => BuddyMiniTile(candidate: candidates[i], onTap: () => _view(context, candidates[i])),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Text('Distances are approximate. Your exact location is never shared.',
              textAlign: TextAlign.center, style: AppText.caption),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Row(children: [
            Expanded(
              child: AppButton(
                label: 'Later',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'View',
                icon: Icons.arrow_forward_rounded,
                onPressed: () {
                  if (n == 1 || onOpenBuddies == null) {
                    _view(context, candidates.first);
                  } else {
                    Navigator.pop(context);
                    onOpenBuddies!();
                  }
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
