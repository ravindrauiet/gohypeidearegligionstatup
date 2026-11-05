import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/rewards_service.dart';
import '../ui/app_ui.dart';
import 'coin_toast.dart';
import 'reward_parts.dart';

const _kPromptDayKey = 'daily_checkin_prompted_day';

/// Opens the daily check-in sheet. Returns the coins awarded (null if closed
/// without claiming).
Future<int?> showDailyCheckIn(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DailyCheckInSheet(),
  );
}

/// Wrap Home (or place anywhere under it): once per IST day, when a logged-in
/// user hasn't claimed today's coin, shows the check-in sheet.
class DailyCheckInGate extends StatefulWidget {
  final Widget child;

  /// Wait a moment after Home appears before prompting.
  final Duration delay;

  const DailyCheckInGate({super.key, required this.child, this.delay = const Duration(milliseconds: 900)});

  @override
  State<DailyCheckInGate> createState() => _DailyCheckInGateState();
}

class _DailyCheckInGateState extends State<DailyCheckInGate> {
  RewardsService? _rewards;
  bool _checking = false;
  String? _promptedDay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = context.read<RewardsService>();
    if (!identical(r, _rewards)) {
      _rewards?.removeListener(_maybePrompt);
      _rewards = r..addListener(_maybePrompt);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (r.loggedIn && !r.loaded && !r.loading) {
          r.refresh();
        } else {
          _maybePrompt();
        }
      });
    }
  }

  @override
  void dispose() {
    _rewards?.removeListener(_maybePrompt);
    super.dispose();
  }

  Future<void> _maybePrompt() async {
    final r = _rewards;
    if (!mounted || r == null || _checking || !r.dailyAvailable) return;
    final today = istDayKey();
    if (_promptedDay == today) return;
    _checking = true;
    try {
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
        if (prefs.getString(_kPromptDayKey) == today) {
          _promptedDay = today;
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(widget.delay);
      if (!mounted || !r.dailyAvailable) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return; // don't cover another screen
      _promptedDay = today;
      try {
        await prefs?.setString(_kPromptDayKey, today);
      } catch (_) {}
      if (!mounted) return;
      await showDailyCheckIn(context);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DailyCheckInSheet extends StatefulWidget {
  const _DailyCheckInSheet();

  @override
  State<_DailyCheckInSheet> createState() => _DailyCheckInSheetState();
}

class _DailyCheckInSheetState extends State<_DailyCheckInSheet> {
  bool _claiming = false;
  int? _awarded;
  String? _error;

  Future<void> _claim() async {
    final r = context.read<RewardsService>();
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      final n = await r.claimDaily();
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _awarded = n;
      });
      if (n > 0) showCoinToast(context, n, reason: 'Daily check-in');
    } on LoginRequiredException catch (e) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RewardsService>();
    final claimed = _awarded != null || r.dailyClaimed;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final streak = claimed ? r.streakDays : r.streakDays + 1;
    final done = streakDotsDone(r.streakDays, claimedToday: claimed);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      child: AnimatedSize(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _CoinMedal(celebrate: claimed, reduce: reduce),
          const SizedBox(height: AppSpacing.md),
          Text(
            claimed ? (_awarded == 0 ? 'Already checked in today' : '+1 coin added') : 'Your daily blessing',
            textAlign: TextAlign.center,
            style: AppText.headline,
          ),
          const SizedBox(height: 6),
          Text(
            claimed
                ? 'You\'re on a $streak-day streak. Come back tomorrow to keep it going.'
                : (r.streakDays > 0
                    ? 'Check in today to make it a $streak-day streak.'
                    : 'Check in every day to build your streak.'),
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: StreakWeekRow(done: done, todayPending: !claimed),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (!claimed)
            AppButton(label: 'Claim 1 coin', icon: Icons.redeem_rounded, loading: _claiming, onPressed: _claim)
          else
            AppButton(
              label: 'Done',
              variant: AppButtonVariant.dark,
              onPressed: () => Navigator.of(context).pop(_awarded ?? 0),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text('Balance: ${formatCoins(r.balance)} coins', style: AppText.caption),
        ]),
      ),
    );
  }
}

class _CoinMedal extends StatelessWidget {
  final bool celebrate;
  final bool reduce;
  const _CoinMedal({required this.celebrate, required this.reduce});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(celebrate),
      tween: Tween(begin: celebrate && !reduce ? 0.6 : 1, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFFF4CF), Color(0xFFFFF9EB)]),
          boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 2)],
        ),
        alignment: Alignment.center,
        child: Stack(alignment: Alignment.center, children: [
          const CoinIcon(size: 60),
          if (celebrate)
            const Positioned(
              right: 8,
              bottom: 8,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.success,
                child: Icon(Icons.check_rounded, size: 16, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}
