import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart' show BackendException;
import '../../services/rewards_service.dart';
import '../../widgets/rewards/coin_toast.dart';
import '../../widgets/ui/app_ui.dart';

/// The 50 mindset questions, one per screen. Resumes at the first unanswered
/// question and pays 50 coins for each first answer.
class MindsetQuizScreen extends StatefulWidget {
  const MindsetQuizScreen({super.key});

  @override
  State<MindsetQuizScreen> createState() => _MindsetQuizScreenState();
}

class _MindsetQuizScreenState extends State<MindsetQuizScreen> {
  bool _loading = true;
  String? _error;
  bool _needsLogin = false;
  int _index = 0;
  bool _finished = false;
  bool _reviewing = false;
  bool _submitting = false;
  int? _picked;
  int _burstKey = 0;
  int? _burst;
  int _earnedThisSession = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final r = context.read<RewardsService>();
    setState(() {
      _loading = true;
      _error = null;
      _needsLogin = false;
    });
    try {
      await r.loadQuestions();
      if (!mounted) return;
      final first = r.firstUnanswered;
      setState(() {
        _loading = false;
        _index = first >= r.questions.length ? 0 : first;
        _finished = r.questions.isNotEmpty && first >= r.questions.length;
      });
    } on LoginRequiredException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needsLogin = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is BackendException ? e.message : 'Could not load the questions. Please try again.';
      });
    }
  }

  bool get _reduce => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  int? _nextUnanswered(RewardsService r, int from) {
    final n = r.questions.length;
    for (var k = 1; k <= n; k++) {
      final j = (from + k) % n;
      if (!r.answers.containsKey(r.questions[j].id)) return j;
    }
    return null;
  }

  void _advance({bool skipping = false}) {
    final r = context.read<RewardsService>();
    final n = r.questions.length;
    if (n == 0) return;
    int? next;
    if (_reviewing) {
      next = _index + 1 < n ? _index + 1 : null;
    } else {
      next = _nextUnanswered(r, _index);
      if (next == _index && !skipping) next = null;
      // Skipping the last open question just moves forward.
      if (next == _index && skipping) next = _index + 1 < n ? _index + 1 : null;
    }
    setState(() {
      _picked = null;
      _burst = null;
      if (next == null) {
        _finished = r.firstUnanswered >= n;
        if (!_finished) _index = r.firstUnanswered;
      } else {
        _index = next;
      }
    });
  }

  Future<void> _answer(MindsetQuestion q, int option) async {
    if (_submitting) return;
    final r = context.read<RewardsService>();
    HapticFeedback.selectionClick();
    setState(() {
      _submitting = true;
      _picked = option;
    });
    try {
      final awarded = await r.answerQuestion(q.id, option);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (awarded > 0) {
          _burst = awarded;
          _burstKey++;
          _earnedThisSession += awarded;
        }
      });
      if (awarded > 0) HapticFeedback.mediumImpact();
      final wait = awarded > 0
          ? (_reduce ? const Duration(milliseconds: 700) : const Duration(milliseconds: 1100))
          : const Duration(milliseconds: 350);
      await Future<void>.delayed(wait);
      if (!mounted) return;
      if (r.questions.isNotEmpty && r.questions[_index].id == q.id) _advance();
    } on LoginRequiredException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _picked = null;
      });
      showAppSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _picked = null;
      });
      showAppSnack(context, 'Couldn\'t save your answer. Check your connection and try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RewardsService>();
    // "+50" only while the question on screen still pays (first answer).
    final onScreen = r.questions.isEmpty ? null : r.questions[_index.clamp(0, r.questions.length - 1)];
    final pays = onScreen != null && !r.answers.containsKey(onScreen.id);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Mindset questions'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (!_loading && !_finished && !_needsLogin && _error == null && pays)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CoinIcon(size: 18),
                  const SizedBox(width: 4),
                  Text('+${r.coinsPerQuestion}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9A6400))),
                ]),
              ),
            ),
        ],
      ),
      body: SafeArea(top: false, child: _body(r)),
    );
  }

  Widget _body(RewardsService r) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_needsLogin) {
      return Center(
        child: AppStateView(
          icon: Icons.lock_outline_rounded,
          title: 'Log in to answer',
          message: 'Your answers and coins are saved to your account.',
          actionLabel: 'Log in',
          onAction: () => Navigator.of(context).pushNamed('/login'),
        ),
      );
    }
    if (_error != null) {
      return Center(child: AppStateView.error(message: _error, onAction: _load));
    }
    if (r.questions.isEmpty) {
      return Center(
        child: AppStateView(
          icon: Icons.psychology_alt_rounded,
          title: 'Questions are on their way',
          message: 'Please check back in a little while.',
          actionLabel: 'Try again',
          onAction: _load,
        ),
      );
    }
    if (_finished) return _finish(r);

    final q = r.questions[_index.clamp(0, r.questions.length - 1)];
    final total = r.questions.length;
    final current = r.answers[q.id];
    final reduce = _reduce;

    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('${_index + 1} of $total', style: AppText.bodyStrong),
              const Spacer(),
              Text('${r.answeredCount} answered', style: AppText.caption),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (_index + 1) / total),
                duration: reduce ? Duration.zero : const Duration(milliseconds: 350),
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceMuted,
                  color: AppColors.primary,
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: ListView(
              key: ValueKey(q.id),
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.lg),
              children: [
                if (q.category.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppBadge(label: q.category.toUpperCase(), color: AppColors.cosmicLight),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Text(q.text, style: AppText.headline),
                const SizedBox(height: AppSpacing.xl),
                for (var i = 0; i < q.options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _OptionCard(
                      letter: String.fromCharCode(65 + i),
                      text: q.options[i],
                      selected: (_picked ?? current) == i,
                      busy: _submitting && _picked == i,
                      onTap: _submitting ? null : () => _answer(q, i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
          child: Row(children: [
            TextButton.icon(
              onPressed: _index > 0 && !_submitting
                  ? () => setState(() {
                        _index--;
                        _picked = null;
                        _burst = null;
                      })
                  : null,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _submitting ? null : () => _advance(skipping: true),
              child: Text(current != null ? 'Next' : 'Skip'),
            ),
          ]),
        ),
      ]),
      if (_burst != null)
        Positioned.fill(
          child: IgnorePointer(child: _CoinBurst(key: ValueKey(_burstKey), amount: _burst!, reduce: reduce)),
        ),
    ]);
  }

  Widget _finish(RewardsService r) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xl),
      children: [
        Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.successSoft,
              boxShadow: AppShadows.glow(AppColors.success),
            ),
            child: const Icon(Icons.verified_rounded, size: 56, color: AppColors.success),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const Text('Your mindset profile is ready', textAlign: TextAlign.center, style: AppText.headline),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'It helps us find buddies who think like you. Your answers stay private: others only see how well you match.',
          textAlign: TextAlign.center,
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          color: const Color(0xFFFFF8E6),
          child: Row(children: [
            const CoinIcon(size: 36),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _earnedThisSession > 0
                    ? 'You earned $_earnedThisSession coins just now'
                    : '${r.answeredCount} of ${r.questions.length} questions answered',
                style: AppText.subtitle,
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(label: 'Done', onPressed: () => Navigator.of(context).maybePop()),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Review my answers',
          variant: AppButtonVariant.outline,
          onPressed: () => setState(() {
            _reviewing = true;
            _finished = false;
            _index = 0;
          }),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String letter;
  final String text;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  const _OptionCard({required this.letter, required this.text, required this.selected, required this.busy, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.primary : AppColors.surfaceMuted,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : (selected
                          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                          : Text(letter,
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary))),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      )),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinBurst extends StatelessWidget {
  final int amount;
  final bool reduce;
  const _CoinBurst({super.key, required this.amount, required this.reduce});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '+$amount coins',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduce ? const Duration(milliseconds: 1) : const Duration(milliseconds: 900),
        builder: (context, t, _) {
          final pop = reduce ? 1.0 : Curves.elasticOut.transform((t / 0.6).clamp(0.0, 1.0));
          final rise = reduce ? 0.0 : -40 * Curves.easeOut.transform(t);
          final fade = t < 0.75 || reduce ? 1.0 : 1 - (t - 0.75) / 0.25;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, rise),
                child: Transform.scale(
                  scale: 0.5 + 0.5 * pop,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 22, 12),
                    decoration: BoxDecoration(
                      gradient: AppColors.cosmicGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: AppShadows.glow(AppColors.gold),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const CoinIcon(size: 40),
                      const SizedBox(width: 10),
                      Text('+$amount',
                          style: const TextStyle(
                              color: Color(0xFFFFD66B), fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
