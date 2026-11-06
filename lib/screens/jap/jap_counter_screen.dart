import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/jap_service.dart';
import '../../widgets/rewards/coin_toast.dart';
import '../../widgets/ui/app_ui.dart';
import 'jap_widgets.dart';

/// Digital jap mala: pick a mantra, tap anywhere in the lower area to count,
/// 108 beads make a mala. Needs a [JapService] provider above it.
class JapCounterScreen extends StatefulWidget {
  const JapCounterScreen({super.key});

  @override
  State<JapCounterScreen> createState() => _JapCounterScreenState();
}

class _JapCounterScreenState extends State<JapCounterScreen> {
  late final JapService _jap = context.read<JapService>();
  StreamSubscription<JapAward>? _awardSub;
  bool _showComplete = false;

  @override
  void initState() {
    super.initState();
    _awardSub = _jap.awards.listen((a) {
      if (mounted) showCoinToast(context, a.amount, reason: 'Jap mala complete');
    });
    _jap.load().then((_) {
      if (mounted && _jap.registered) _jap.syncToday();
    });
  }

  @override
  void dispose() {
    _awardSub?.cancel();
    super.dispose();
  }

  void _tap() {
    if (_showComplete) {
      setState(() => _showComplete = false);
      return;
    }
    final completed = _jap.tap();
    if (completed) {
      HapticFeedback.heavyImpact();
      setState(() => _showComplete = true);
    } else {
      HapticFeedback.selectionClick();
    }
    if (_jap.soundOn) SystemSound.play(SystemSoundType.click);
  }

  void _undo() {
    if (_jap.undo()) HapticFeedback.selectionClick();
  }

  Future<void> _reset() async {
    if (_jap.count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset this mala?'),
        content: Text('Your count of ${_jap.count} for ${_jap.mantra.name} will be cleared. Completed malas stay in your stats.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true && mounted) _jap.reset();
  }

  void _login() => Navigator.of(context).pushNamed('/login');

  Future<void> _pickMantra() async {
    await showAppSheet<void>(context, builder: (_) => ChangeNotifierProvider.value(value: _jap, child: const _MantraPicker()));
  }

  Future<void> _openPractice() async {
    await showAppSheet<void>(context, builder: (_) => ChangeNotifierProvider.value(value: _jap, child: const _PracticeSheet()));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<JapService>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Jap mala'),
        actions: [
          IconButton(
            tooltip: 'Your practice and reminders',
            icon: const Icon(Icons.insights_rounded),
            onPressed: s.loaded ? _openPractice : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !s.loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
                  child: _MantraCard(mantra: s.mantra, onTap: _pickMantra),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
                  child: _StatStrip(service: s, onLogin: _login),
                ),
                Expanded(child: _tapArea(s)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
                  child: Row(children: [
                    Expanded(
                      child: _ControlButton(
                          icon: Icons.undo_rounded, label: 'Undo last', onPressed: s.count > 0 && !_showComplete ? _undo : null),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _ControlButton(icon: Icons.restart_alt_rounded, label: 'Reset', onPressed: s.count > 0 ? _reset : null),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _ControlButton(
                        icon: s.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        label: s.soundOn ? 'Sound on' : 'Sound off',
                        onPressed: () => _jap.setSound(!s.soundOn),
                      ),
                    ),
                  ]),
                ),
              ]),
      ),
    );
  }

  Widget _tapArea(JapService s) {
    final label = _showComplete ? 'Mala complete. Tap to begin the next mala' : 'Count one bead. ${s.count} of 108';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: _tap,
      child: GestureDetector(
        key: const ValueKey('jap-tap-area'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _tap(),
        child: LayoutBuilder(builder: (context, c) {
          final size = (c.biggest.shortestSide - 24).clamp(120.0, 340.0);
          return Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _showComplete
                  ? _CompletionCard(key: const ValueKey('done'), service: s, maxHeight: c.maxHeight, onLogin: _login)
                  : JapBeadRing(
                      key: const ValueKey('ring'),
                      count: s.count,
                      size: size,
                      child: Padding(
                        padding: EdgeInsets.all(size * 0.2),
                        child: FittedBox(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('${s.count}',
                                style: const TextStyle(
                                    fontSize: 64,
                                    height: 1.0,
                                    fontWeight: FontWeight.w300,
                                    letterSpacing: -1.5,
                                    color: AppColors.textPrimary,
                                    fontFeatures: [FontFeature.tabularFigures()])),
                            const SizedBox(height: 4),
                            const Text('of 108', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            const Text('Tap anywhere', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                          ]),
                        ),
                      ),
                    ),
            ),
          );
        }),
      ),
    );
  }
}

class _MantraCard extends StatelessWidget {
  final JapMantra mantra;
  final VoidCallback onTap;
  const _MantraCard({required this.mantra, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (mantra.devanagari.isNotEmpty)
              Text(mantra.devanagari,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text(mantra.transliteration,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: mantra.devanagari.isEmpty
                    ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)
                    : AppText.bodyStrong.copyWith(color: AppColors.primaryDark)),
            const SizedBox(height: 2),
            Text(mantra.meaning, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption),
          ]),
        ),
        const SizedBox(width: 4),
        const Tooltip(
          message: 'Change mantra',
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.swap_horiz_rounded, color: AppColors.textSecondary),
          ),
        ),
      ]),
    );
  }
}

class _StatStrip extends StatelessWidget {
  final JapService service;
  final VoidCallback onLogin;
  const _StatStrip({required this.service, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final s = service;
    final coin = !s.registered
        ? InkWell(
            key: const ValueKey('jap-sign-in'),
            onTap: onLogin,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: const _Pill(
              leading: CoinIcon(size: 16),
              text: 'Sign in to earn coins',
              color: AppColors.primaryDark,
              background: AppColors.primarySoft,
            ),
          )
        : _Pill(
            leading: const CoinIcon(size: 16),
            text: s.dailyCapReached ? 'Coins done today' : 'Coins ${s.paidToday}/${s.cap} today',
            color: AppColors.textPrimary,
            background: AppColors.surface,
          );
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pill(
          leading: const Icon(Icons.brightness_5_rounded, size: 16, color: AppColors.primary),
          text: '${s.todayMalas} today',
          color: AppColors.textPrimary,
          background: AppColors.surface,
        ),
        _Pill(
          leading: const Icon(Icons.local_fire_department_rounded, size: 16, color: AppColors.warning),
          text: '${s.streak}-day streak',
          color: AppColors.textPrimary,
          background: AppColors.surface,
        ),
        coin,
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget leading;
  final String text;
  final Color color;
  final Color background;
  const _Pill({required this.leading, required this.text, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        leading,
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _ControlButton({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button, side: const BorderSide(color: AppColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 20, color: AppColors.textPrimary),
                  const SizedBox(height: 2),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  final JapService service;
  final double maxHeight;
  final VoidCallback onLogin;
  const _CompletionCard({super.key, required this.service, required this.maxHeight, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final s = service;
    final (String coinText, bool showCoin) = switch (s.lastCoinStatus) {
      JapCoinStatus.awarded => ('+${s.lastAwarded} coins added', true),
      JapCoinStatus.pending => ('Adding your coins...', true),
      JapCoinStatus.queuedOffline => ('You are offline. Your coins will be added when you reconnect.', true),
      JapCoinStatus.capReached => ('You have earned coins for ${s.cap} malas today. Keep chanting for peace.', false),
      JapCoinStatus.signInToEarn => ('Sign in to earn coins for every mala.', true),
      null => ('', false),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: AppCard(
          shadow: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: const Icon(Icons.self_improvement_rounded, color: AppColors.primary, size: 28),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Mala complete', textAlign: TextAlign.center, style: AppText.title),
              const SizedBox(height: 4),
              Text(
                '108 chants offered. ${s.todayMalas} ${s.todayMalas == 1 ? 'mala' : 'malas'} today.',
                textAlign: TextAlign.center,
                style: AppText.body,
              ),
              if (coinText.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (showCoin) ...[const CoinIcon(size: 18), const SizedBox(width: 6)],
                  Flexible(child: Text(coinText, textAlign: TextAlign.center, style: AppText.bodyStrong)),
                ]),
              ],
              if (s.lastCoinStatus == JapCoinStatus.signInToEarn) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton(label: 'Sign in', height: 44, expand: false, variant: AppButtonVariant.secondary, onPressed: onLogin),
              ],
              const SizedBox(height: AppSpacing.sm),
              const Text('Tap to begin the next mala', textAlign: TextAlign.center, style: AppText.caption),
            ]),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sheets
// -----------------------------------------------------------------------------

class _MantraPicker extends StatelessWidget {
  const _MantraPicker();

  Future<void> _custom(BuildContext context, JapService s) async {
    final ctrl = TextEditingController(text: s.customText);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your mantra'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Radhe Radhe'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Use')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null) return;
    s.setCustomText(text);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<JapService>();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
        children: [
          const Text('Choose a mantra', style: AppText.title),
          const SizedBox(height: 4),
          const Text('Each mantra keeps its own count.', style: AppText.body),
          const SizedBox(height: AppSpacing.sm),
          for (final m in japMantras)
            _MantraTile(
              mantra: m,
              selected: s.selectedId == m.id,
              count: s.countFor(m.id),
              onTap: () {
                s.select(m.id);
                Navigator.of(context).pop();
              },
            ),
          _MantraTile(
            mantra: JapMantra(
              id: JapService.customId,
              name: 'Custom',
              devanagari: '',
              transliteration: s.customText.isEmpty ? 'Custom mantra' : 'Custom: ${s.customText}',
              meaning: 'Chant any name or mantra that is dear to you.',
            ),
            selected: s.selectedId == JapService.customId,
            count: s.countFor(JapService.customId),
            onTap: () => _custom(context, s),
          ),
        ],
      ),
    );
  }
}

class _MantraTile extends StatelessWidget {
  final JapMantra mantra;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  const _MantraTile({required this.mantra, required this.selected, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: selected ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (mantra.devanagari.isNotEmpty)
                    Text(mantra.devanagari,
                        style: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(mantra.transliteration,
                      style: mantra.devanagari.isEmpty ? AppText.subtitle : AppText.bodyStrong.copyWith(color: AppColors.primaryDark)),
                  const SizedBox(height: 2),
                  Text(mantra.meaning, style: AppText.caption),
                ]),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(children: [
                if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                if (count > 0) ...[
                  const SizedBox(height: 4),
                  AppBadge(label: '$count/108'),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PracticeSheet extends StatelessWidget {
  const _PracticeSheet();

  Future<void> _toggleReminder(BuildContext context, JapService s, bool on) async {
    if (!on) {
      await s.setReminder(false);
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
      helpText: 'Remind me to chant at',
    );
    if (t == null) return;
    final ok = await s.setReminder(true, hour: t.hour, minute: t.minute);
    if (!ok && context.mounted) {
      showAppSnack(context, 'Please allow notifications in Settings to get your chanting reminder.', error: true);
    }
  }

  Future<void> _changeTime(BuildContext context, JapService s) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute),
      helpText: 'Remind me to chant at',
    );
    if (t == null) return;
    await s.setReminder(true, hour: t.hour, minute: t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<JapService>();
    final time = TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute).format(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('Your practice', style: AppText.title),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(child: _Stat(value: '${s.todayMalas}', label: 'Malas today')),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: _Stat(value: '${s.streak}', label: 'Day streak')),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: _Stat(value: '${s.totalMalas}', label: 'Total malas')),
        ]),
        const SizedBox(height: AppSpacing.md),
        const Text('Last 7 days', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xs),
        JapWeekChart(days: s.last7Days, today: s.now),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              key: const ValueKey('jap-reminder-switch'),
              value: s.reminderOn,
              onChanged: (v) => _toggleReminder(context, s, v),
              title: const Text('Remind me to chant'),
              subtitle: Text(s.reminderOn ? 'Every day at $time' : 'A gentle daily reminder'),
              secondary: const Icon(Icons.notifications_active_outlined),
            ),
            if (s.reminderOn)
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Reminder time'),
                trailing: Text(time, style: AppText.bodyStrong),
                onTap: () => _changeTime(context, s),
              ),
            const Divider(height: 1),
            SwitchListTile(
              value: s.soundOn,
              onChanged: s.setSound,
              title: const Text('Tap sound'),
              subtitle: const Text('A soft click on every bead'),
              secondary: const Icon(Icons.volume_up_outlined),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          s.registered
              ? 'Earn ${JapService.coinsPerMala} coins for each completed mala, up to ${s.cap} malas a day.'
              : 'Sign in to earn ${JapService.coinsPerMala} coins for each completed mala (up to ${s.cap} a day).',
          style: AppText.caption,
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(children: [
        FittedBox(child: Text(value, style: AppText.headline)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppText.caption),
      ]),
    );
  }
}
