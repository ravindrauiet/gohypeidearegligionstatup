import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/rewards_service.dart';
import '../rewards/coin_toast.dart' show CoinIcon;
import '../rewards/reward_parts.dart' show formatCoins;
import '../ui/app_ui.dart';

/// One row of today's earning checklist.
class EarnTask {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final int coins;

  /// Done today (null = we can't tell, so the row is just an action).
  final bool? done;
  final String? doneLabel;
  final VoidCallback onTap;

  const EarnTask({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.coins,
    required this.done,
    required this.onTap,
    this.doneLabel,
  });
}

/// Home "Daily earnings": coin balance, progress to the 10,000-coin temple
/// trip and today's checklist (check in, play, watch, answer).
///
/// Everything comes from [RewardsService]: the check-in tick is the server's
/// `dailyClaimed`; game / video / question ticks are derived from today's
/// (IST) entries in `recent`. When nothing shows a task was done, the row is
/// simply an action.
class HomeEarningsCard extends StatefulWidget {
  final VoidCallback onCheckIn;
  final VoidCallback onPlayGame;
  final VoidCallback onWatchVideo;
  final VoidCallback onAnswerQuestion;
  final VoidCallback onOpenCoins;
  final VoidCallback onOpenTrip;

  const HomeEarningsCard({
    super.key,
    required this.onCheckIn,
    required this.onPlayGame,
    required this.onWatchVideo,
    required this.onAnswerQuestion,
    required this.onOpenCoins,
    required this.onOpenTrip,
  });

  /// True when [r.recent] holds an entry for [reason] earned today (IST).
  static bool earnedToday(RewardsService r, String reason, [DateTime? now]) {
    final today = istDayKey(now);
    return r.recent.any((e) =>
        e.reason == reason && e.amount > 0 && e.createdAt != null && istDayKey(e.createdAt) == today);
  }

  /// Coins a task pays, from the server's earn rules when present.
  static int ruleCoins(RewardsService r, String keyPart, int fallback) {
    for (final rule in r.earnRules) {
      if (rule.key.toLowerCase().contains(keyPart) && rule.coins != 0) return rule.coins.abs();
    }
    return fallback;
  }

  @override
  State<HomeEarningsCard> createState() => _HomeEarningsCardState();
}

class _HomeEarningsCardState extends State<HomeEarningsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = context.read<RewardsService>();
      if (r.loggedIn && !r.loaded && !r.loading) r.refresh();
    });
  }

  List<EarnTask> _tasks(RewardsService r) {
    final allAnswered = r.questionsLoaded && r.answeredCount >= r.questionTotal;
    return [
      EarnTask(
        id: 'checkin',
        title: r.dailyClaimed ? 'Checked in today' : 'Daily check-in',
        icon: Icons.wb_sunny_rounded,
        color: AppColors.warning,
        coins: HomeEarningsCard.ruleCoins(r, 'daily', 1),
        done: r.dailyClaimed,
        onTap: r.dailyClaimed ? widget.onOpenCoins : widget.onCheckIn,
      ),
      EarnTask(
        id: 'game',
        title: 'Play a game',
        icon: Icons.sports_esports_rounded,
        color: AppColors.info,
        coins: HomeEarningsCard.ruleCoins(r, 'game', 10),
        done: HomeEarningsCard.earnedToday(r, 'game') ? true : null,
        onTap: widget.onPlayGame,
      ),
      EarnTask(
        id: 'video',
        title: 'Watch a new video',
        icon: Icons.play_circle_fill_rounded,
        color: AppColors.danger,
        coins: HomeEarningsCard.ruleCoins(r, 'video', 1),
        done: HomeEarningsCard.earnedToday(r, 'video') ? true : null,
        onTap: widget.onWatchVideo,
      ),
      EarnTask(
        id: 'question',
        title: allAnswered ? 'All questions answered' : 'Answer a mindset question',
        icon: Icons.psychology_alt_rounded,
        color: AppColors.love,
        coins: HomeEarningsCard.ruleCoins(r, 'question', r.coinsPerQuestion),
        done: allAnswered || HomeEarningsCard.earnedToday(r, 'question') ? true : null,
        onTap: widget.onAnswerQuestion,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RewardsService>();
    if (!r.loggedIn) return _guest(r);
    if (!r.loaded) {
      if (r.error != null && !r.loading) return _error(r);
      return const Padding(
        padding: AppSpacing.pagePadding,
        child: SkeletonBox(height: 260, radius: AppRadius.xl),
      );
    }
    final tasks = _tasks(r);
    return Padding(
      padding: AppSpacing.pagePadding,
      child: DecoratedBox(
        key: const ValueKey('home-earnings'),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _wallet(r),
              for (var i = 0; i < tasks.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 64, color: AppColors.divider),
                _taskRow(tasks[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ wallet header
  Widget _wallet(RewardsService r) {
    final pct = (r.progress * 100).floor();
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF6DE), Color(0xFFFFE7B8)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('home-earnings-balance'),
              onTap: widget.onOpenCoins,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
                child: Row(
                  children: [
                    const CoinIcon(size: 40),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: formatCoins(r.balance),
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    color: Color(0xFF5A3A00)),
                              ),
                              const TextSpan(
                                text: ' coins',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00)),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            r.todayEarned > 0 ? '+${formatCoins(r.todayEarned)} earned today' : 'Earn your first coins today',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF8A5A00)),
                          ),
                        ],
                      ),
                    ),
                    if (r.streakDays > 0) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _StreakChip(days: r.streakDays),
                    ],
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A5A00)),
                  ],
                ),
              ),
            ),
            InkWell(
              key: const ValueKey('home-earnings-trip'),
              onTap: widget.onOpenTrip,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.temple_hindu_rounded, size: 18, color: AppColors.primaryDark),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r.tripUnlocked
                              ? 'Temple trip unlocked! Plan it with your buddy'
                              : '${formatCoins(r.coinsToGoal)} more for a free temple trip',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text('$pct%',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                    ]),
                    const SizedBox(height: AppSpacing.xs),
                    _ProgressBar(progress: r.progress),
                    const SizedBox(height: 4),
                    Text(
                      '${formatCoins(r.balance)} / ${formatCoins(r.goal)} · sponsored trip with your buddy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: const Color(0xFF8A5A00)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ checklist row
  Widget _taskRow(EarnTask t) {
    final done = t.done == true;
    return Semantics(
      button: true,
      label: '${t.title}, ${done ? 'done today' : 'earn ${t.coins} coins'}',
      excludeSemantics: true,
      onTap: t.onTap,
      child: InkWell(
        key: ValueKey('earn-task-${t.id}'),
        onTap: t.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          child: Row(
            children: [
              _TickCircle(done: done, color: t.color, icon: t.icon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: done ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (done)
                const AppBadge(label: 'Done', color: AppColors.success, icon: Icons.check_rounded)
              else
                _CoinReward(coins: t.coins),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ guest / error
  Widget _guest(RewardsService r) {
    return Padding(
      padding: AppSpacing.pagePadding,
      child: AppCard(
        key: const ValueKey('home-earnings-guest'),
        onTap: widget.onOpenCoins,
        radius: BorderRadius.circular(AppRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6DE), Color(0xFFFFE2A8)],
        ),
        shadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              CoinIcon(size: 40),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Earn coins every day',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF5A3A00))),
              ),
            ]),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Check in, play games, watch bhajans and answer questions. '
              'Save 10,000 coins for a sponsored temple trip with your buddy.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF6B4A0A)),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Wrap(spacing: 6, runSpacing: 6, children: [
              _RuleChip('Check-in +1'),
              _RuleChip('Game +10'),
              _RuleChip('Video +1'),
              _RuleChip('Question +50'),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Flexible(
                child: Text('Log in to start earning',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong.copyWith(color: AppColors.primaryDark)),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark, size: 20),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _error(RewardsService r) {
    return Padding(
      padding: AppSpacing.pagePadding,
      child: AppCard(
        child: Row(children: [
          const CoinIcon(size: 28),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: Text("Couldn't load your coins", style: AppText.bodyStrong)),
          TextButton(onPressed: r.refresh, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          // Always show a sliver so a fresh wallet still reads as "started".
          widthFactor: v == 0 ? 0.02 : v.clamp(0.02, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFF5B83D), AppColors.primary]),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int days;
  const _StreakChip({required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '🔥 $days-day',
        maxLines: 1,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
      ),
    );
  }
}

class _TickCircle extends StatelessWidget {
  final bool done;
  final Color color;
  final IconData icon;
  const _TickCircle({required this.done, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.success : color.withValues(alpha: 0.12),
      ),
      child: Icon(done ? Icons.check_rounded : icon, size: 20, color: done ? Colors.white : color),
    );
  }
}

class _CoinReward extends StatelessWidget {
  final int coins;
  const _CoinReward({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DE),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: const Color(0xFFF7D98A)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const CoinIcon(size: 16),
        const SizedBox(width: 4),
        Text('+$coins',
            maxLines: 1,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
      ]),
    );
  }
}

class _RuleChip extends StatelessWidget {
  final String label;
  const _RuleChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
    );
  }
}
