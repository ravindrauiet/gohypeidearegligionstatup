import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../services/rewards_service.dart';
import '../../widgets/rewards/coin_toast.dart';
import '../../widgets/rewards/daily_checkin.dart';
import '../../widgets/rewards/reward_parts.dart';
import '../../widgets/ui/app_ui.dart';
import '../legal/community_guidelines_screen.dart';
import 'mindset_quiz_screen.dart';
import 'temple_trip_screen.dart';

/// Coins home: balance, progress to the temple trip, ways to earn, activity.
class CoinsScreen extends StatefulWidget {
  /// Opens the devotional video library (wired by Home). Hidden when null.
  final VoidCallback? onOpenVideos;

  /// Opens the games hub; defaults to `Navigator.pushNamed('/games')`.
  final VoidCallback? onOpenGames;

  const CoinsScreen({super.key, this.onOpenVideos, this.onOpenGames});

  @override
  State<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends State<CoinsScreen> {
  bool _quizTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final r = context.read<RewardsService>();
    await r.refresh();
    if (!mounted || !r.loggedIn) return;
    // Refresh failed but older numbers are still on screen: say so.
    if (r.loaded && r.error != null) showAppSnack(context, r.error!, error: true);
    if (!r.questionsLoaded || !_quizTried) {
      _quizTried = true;
      try {
        await r.loadQuestions();
      } catch (_) {
        // The quiz card simply shows "0/50" until it loads.
      }
    }
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _openGames() {
    if (widget.onOpenGames != null) return widget.onOpenGames!();
    Navigator.of(context).pushNamed('/games');
  }

  Future<void> _claim() async {
    await showDailyCheckIn(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RewardsService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My coins'),
        actions: [
          IconButton(
            tooltip: 'How the temple trip works',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showTempleTripInfo(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _body(r),
      ),
    );
  }

  Widget _body(RewardsService r) {
    if (!r.loggedIn) {
      return ListView(padding: const EdgeInsets.all(AppSpacing.page), children: [
        _Hero(r: r, locked: true),
        const SizedBox(height: AppSpacing.lg),
        AppStateView(
          icon: Icons.lock_outline_rounded,
          title: 'Log in to start earning',
          message: 'Coins are saved to your account, so you need to log in to collect them.',
          actionLabel: 'Log in',
          onAction: () => Navigator.of(context).pushNamed('/login'),
        ),
      ]);
    }
    if (!r.loaded && r.error == null) {
      return ListView(padding: const EdgeInsets.all(AppSpacing.page), children: const [
        SkeletonBox(height: 200, radius: AppRadius.xl),
        SizedBox(height: AppSpacing.lg),
        SkeletonBox(height: 80),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 80),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 80),
      ]);
    }
    if (!r.loaded) {
      return ListView(children: [
        AppStateView.error(message: r.error, onAction: r.loading ? null : _load),
      ]);
    }

    final total = r.questionTotal;
    final perQ = _ruleCoins(r, 'question', r.coinsPerQuestion);
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
      children: [
        _Hero(r: r),
        if (!r.dailyClaimed) ...[
          const SizedBox(height: AppSpacing.md),
          _DailyBanner(onClaim: _claim, streak: r.streakDays),
        ],
        const SectionHeader(
          title: 'Ways to earn',
          subtitle: 'Small daily habits add up',
          padding: EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
        ),
        _EarnCard(
          icon: Icons.wb_sunny_rounded,
          color: AppColors.warning,
          title: 'Daily check-in',
          subtitle: r.dailyClaimed ? 'Claimed today. See you tomorrow!' : 'Open the app and claim once a day',
          coins: _ruleCoins(r, 'daily', 1),
          cta: r.dailyClaimed ? 'Done' : 'Claim',
          done: r.dailyClaimed,
          onTap: r.dailyClaimed ? null : _claim,
        ),
        _EarnCard(
          icon: Icons.sports_esports_rounded,
          color: AppColors.info,
          title: 'Play a game',
          subtitle: 'Each of the 4 games pays once a day',
          coins: _ruleCoins(r, 'game', 10),
          coinsSuffix: '/day each',
          cta: 'Play',
          onTap: _openGames,
        ),
        if (widget.onOpenVideos != null)
          _EarnCard(
            icon: Icons.play_circle_fill_rounded,
            color: AppColors.danger,
            title: 'Watch a new video',
            subtitle: 'Devotional videos, bhajans and katha',
            coins: _ruleCoins(r, 'video', 1),
            coinsSuffix: '/video',
            cta: 'Watch',
            onTap: widget.onOpenVideos,
          ),
        _EarnCard(
          icon: Icons.psychology_alt_rounded,
          color: AppColors.love,
          title: 'Mindset questions',
          subtitle: '${r.answeredCount}/$total answered',
          coins: perQ,
          coinsSuffix: ' each',
          cta: r.answeredCount >= total && r.questionsLoaded ? 'Review' : (r.answeredCount > 0 ? 'Continue' : 'Start'),
          progress: total == 0 ? 0 : r.answeredCount / total,
          onTap: () => _push(const MindsetQuizScreen()),
        ),
        _EarnCard(
          icon: Icons.temple_hindu_rounded,
          color: AppColors.primary,
          title: 'Temple trip with a buddy',
          subtitle: r.tripUnlocked
              ? 'Unlocked! Plan your trip now'
              : '${formatCoins(r.coinsToGoal)} coins to go',
          coins: r.goal,
          coinsLabel: 'Goal',
          cta: r.tripUnlocked ? 'Plan' : 'View',
          onTap: () => _push(const TempleTripScreen()),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppCard(
          padding: EdgeInsets.zero,
          child: AppListRow(
            icon: Icons.help_outline_rounded,
            color: AppColors.cosmicLight,
            title: 'How the temple trip works',
            subtitle: 'Who arranges it, and what coins are',
            onTap: () => showTempleTripInfo(context),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TermsLink(
            label: 'Coins terms',
            onTap: () => _push(const CommunityGuidelinesScreen(initialSection: GuidelinesSection.coins)),
          ),
        ),
        const SectionHeader(
          title: 'Recent activity',
          padding: EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
        ),
        if (r.recent.isEmpty)
          const AppCard(
            child: AppStateView(
              compact: true,
              icon: Icons.history_rounded,
              title: 'No coins yet',
              message: 'Claim your daily coin to get started.',
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < r.recent.length; i++) ...[
                if (i > 0) const Divider(indent: 64),
                _ActivityRow(entry: r.recent[i]),
              ],
            ]),
          ),
      ],
    );
  }

  int _ruleCoins(RewardsService r, String keyPart, int fallback) {
    for (final rule in r.earnRules) {
      if (rule.key.toLowerCase().contains(keyPart) && rule.coins != 0) return rule.coins.abs();
    }
    return fallback;
  }
}

class _Hero extends StatelessWidget {
  final RewardsService r;
  final bool locked;
  const _Hero({required this.r, this.locked = false});

  @override
  Widget build(BuildContext context) {
    final pct = (r.progress * 100).floor();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.cosmicGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.raised,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('YOUR BALANCE',
                  style: TextStyle(
                      color: AppColors.textOnDarkMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
              const SizedBox(height: 6),
              Row(children: [
                const CoinIcon(size: 34),
                const SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: CountUpText(
                      locked ? 0 : r.balance,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text('of ${formatCoins(r.goal)} coins',
                  style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: AppSpacing.sm),
          CoinProgressRing(
            progress: locked ? 0 : r.progress,
            size: 88,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${locked ? 0 : pct}%',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const Icon(Icons.temple_hindu_rounded, color: AppColors.gold, size: 16),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(children: [
            const Icon(Icons.temple_hindu_rounded, size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                r.tripUnlocked && !locked
                    ? 'Temple trip unlocked! Plan it with a buddy.'
                    : 'Temple trip unlocks at ${formatCoins(r.goal)}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        if (!locked) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _HeroStat(icon: Icons.local_fire_department_rounded, text: '${r.streakDays}-day streak'),
            _HeroStat(icon: Icons.add_circle_outline_rounded, text: '+${formatCoins(r.todayEarned)} today'),
          ]),
        ],
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeroStat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: AppColors.gold),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Color(0xFFFFE6A6), fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _DailyBanner extends StatelessWidget {
  final VoidCallback onClaim;
  final int streak;
  const _DailyBanner({required this.onClaim, required this.streak});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: const Color(0xFFFFF8E6),
      onTap: onClaim,
      child: Row(children: [
        const CoinIcon(size: 40),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Today\'s coin is waiting', style: AppText.subtitle),
            const SizedBox(height: 2),
            Text(streak > 0 ? 'Keep your $streak-day streak alive' : 'Start your streak today', style: AppText.caption),
          ]),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(label: 'Claim', onPressed: onClaim, expand: false, height: 40),
      ]),
    );
  }
}

class _EarnCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int coins;
  final String coinsSuffix;
  final String? coinsLabel;
  final String cta;
  final bool done;
  final double? progress;
  final VoidCallback? onTap;

  const _EarnCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.coins,
    required this.cta,
    this.coinsSuffix = '',
    this.coinsLabel,
    this.done = false,
    this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.subtitle),
              const SizedBox(height: 3),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
                const CoinIcon(size: 14),
                Text(
                  '${coinsLabel != null ? '$coinsLabel ' : '+'}${formatCoins(coins)}$coinsSuffix',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF9A6400)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(subtitle, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    minHeight: 5,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(width: AppSpacing.xs),
          done
              ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(cta,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                ),
        ]),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final CoinEntry entry;
  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (entry.reason) {
      'daily_login' => (Icons.wb_sunny_rounded, AppColors.warning),
      'game' => (Icons.sports_esports_rounded, AppColors.info),
      'video' => (Icons.play_circle_fill_rounded, AppColors.danger),
      'question' => (Icons.psychology_alt_rounded, AppColors.love),
      'trip' || 'trip_refund' => (Icons.temple_hindu_rounded, AppColors.primary),
      _ => (Icons.toll_rounded, AppColors.gold),
    };
    final positive = entry.amount >= 0;
    final when = entry.createdAt == null ? '' : DateFormat('d MMM, h:mm a').format(entry.createdAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.title, style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (when.isNotEmpty) Text(when, style: AppText.caption),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          '${positive ? '+' : '-'}${formatCoins(entry.amount.abs())}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: positive ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ]),
    );
  }
}

/// Short, honest explainer of the temple trip reward.
Future<void> showTempleTripInfo(BuildContext context) {
  Widget point(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(body, style: AppText.body),
            ]),
          ),
        ]),
      );

  return showAppSheet<void>(
    context,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('How the temple trip works', style: AppText.headline),
        const SizedBox(height: AppSpacing.lg),
        point(Icons.toll_rounded, 'Collect 10,000 coins',
            'Earn them by checking in, playing, watching videos and answering mindset questions.'),
        point(Icons.people_alt_rounded, 'Pick a buddy and a temple',
            'Choose one of your accepted buddies, a temple and a month that suits you both.'),
        point(Icons.support_agent_rounded, 'Our team reviews and arranges it',
            'We contact you both to confirm details. If we can\'t arrange it, or you cancel while it\'s pending, your coins come back.'),
        point(Icons.info_outline_rounded, 'Coins are not money',
            'Coins can\'t be bought, sold, transferred or exchanged for cash. Trips depend on availability and terms apply.'),
        const SizedBox(height: AppSpacing.xs),
        AppButton(label: 'Got it', onPressed: () => Navigator.of(ctx).pop()),
      ]),
    ),
  );
}
