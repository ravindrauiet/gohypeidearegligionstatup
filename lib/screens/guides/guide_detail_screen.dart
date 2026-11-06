import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backend_service.dart';
import '../../services/guide_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'guides_screen.dart' show GuideThumb, guideCategoryLabel, guideGradient;

/// Shares text (replaced in tests).
@visibleForTesting
Future<void> Function(String text)? debugGuideShare;

Future<void> _share(String text) async {
  final d = debugGuideShare;
  if (d != null) return d(text);
  await SharePlus.instance.share(ShareParams(text: text));
}

/// Full guide: overview, when (+ next date), samagri checklist, steps with
/// mantras, vrat do/don't, katha, aarti, tips and "Remind me".
class GuideDetailScreen extends StatefulWidget {
  final String guideId;
  final GuideService? service;
  const GuideDetailScreen({super.key, required this.guideId, this.service});

  /// Deep-link entry point (e.g. from a festival notification: payload {type: 'guide', guideId}).
  static Future<void> open(BuildContext context, String guideId, {GuideService? service}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GuideDetailScreen(guideId: guideId, service: service)));

  @override
  State<GuideDetailScreen> createState() => _GuideDetailScreenState();
}

class _GuideDetailScreenState extends State<GuideDetailScreen> {
  late final GuideService _service =
      widget.service ?? GuideService(Provider.of<BackendService>(context, listen: false));
  PujaGuide? _guide;
  Set<int> _checked = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(GuideDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.guideId != widget.guideId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Show the bundled guide straight away, then refresh from the server.
    final local = (await _service.bundled()).where((g) => g.id == widget.guideId).firstOrNull;
    final checked = await _service.checked(widget.guideId);
    if (!mounted) return;
    setState(() {
      _guide = local;
      _checked = checked;
    });
    try {
      final g = await _service.detail(widget.guideId);
      if (!mounted) return;
      setState(() {
        _guide = g ?? local;
        _loading = false;
        if (_guide == null) _error = 'This guide is not available.';
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_guide == null) _error = e.statusCode == 404 ? 'This guide is not available.' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_guide == null) _error = 'Could not load this guide. Check your connection.';
      });
    }
  }

  Future<void> _toggle(int i, bool on) async {
    setState(() {
      _checked = {..._checked};
      on ? _checked.add(i) : _checked.remove(i);
    });
    await _service.saveChecked(widget.guideId, _checked);
  }

  DateTime? get _next {
    final g = _guide;
    if (g == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final server = g.nextDates.where((d) => !d.isBefore(today)).firstOrNull;
    return server ?? g.localNextDate(today);
  }

  Future<void> _remind() async {
    final g = _guide;
    final next = _next;
    if (g == null || next == null) return;
    final n = await _service.remind(g, next);
    if (!mounted) return;
    showAppSnack(
      context,
      n == 0
          ? 'Could not set a reminder. Turn on notifications in settings (or the day is too close).'
          : 'We will remind you on ${DateFormat('EEE d MMM').format(next.subtract(const Duration(days: 1)))} evening'
              '${n == 2 ? ' and that morning' : ''}.',
      error: n == 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _guide;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(g?.title ?? 'Guide', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: g == null
          ? (_loading
              ? const Center(child: CircularProgressIndicator())
              : AppStateView.error(message: _error, onAction: _load))
          : _body(g),
    );
  }

  Widget _body(PujaGuide g) {
    final next = _next;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
      children: [
        _header(g),
        const SizedBox(height: AppSpacing.md),
        Text(g.overview, style: AppText.body.copyWith(fontSize: 15, color: AppColors.textPrimary)),
        _section('When', Icons.event_rounded),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.whenText, style: AppText.body.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if (next != null)
              Row(children: [
                const Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Next: ${DateFormat('EEEE, d MMMM y').format(next)}',
                      key: const ValueKey('guide_next_date'), style: AppText.bodyStrong),
                ),
              ])
            else
              const Text('Check your local panchang for the exact date this year.', style: AppText.caption),
            const SizedBox(height: 4),
            Text('Duration: ${g.duration}', style: AppText.caption),
            if (next != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                  label: 'Remind me',
                  icon: Icons.notifications_active_outlined,
                  onPressed: _remind,
                  height: 44,
                  variant: AppButtonVariant.secondary),
            ],
          ]),
        ),
        if (g.samagri.isNotEmpty) ...[
          _section('Samagri checklist', Icons.checklist_rounded,
              trailing: TextButton.icon(
                onPressed: () => _share(GuideService.samagriShareText(g, _checked)),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share list'),
              )),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (var i = 0; i < g.samagri.length; i++)
                CheckboxListTile(
                  key: ValueKey('samagri_$i'),
                  value: _checked.contains(i),
                  onChanged: (v) => _toggle(i, v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  activeColor: AppColors.success,
                  title: Text(g.samagri[i].label,
                      style: TextStyle(
                          fontSize: 15,
                          color: _checked.contains(i) ? AppColors.textTertiary : AppColors.textPrimary,
                          decoration: _checked.contains(i) ? TextDecoration.lineThrough : null)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${_checked.length} of ${g.samagri.length} ready', style: AppText.caption),
          ),
        ],
        if (g.steps.isNotEmpty) ...[
          _section('Steps', Icons.format_list_numbered_rounded),
          for (var i = 0; i < g.steps.length; i++) _StepTile(index: i + 1, step: g.steps[i]),
        ],
        if (g.vratRules != null) ...[
          _section('Vrat rules', Icons.rule_rounded),
          _RulesCard(rules: g.vratRules!),
        ],
        if (g.katha.isNotEmpty) ...[
          _section('Katha', Icons.menu_book_rounded),
          AppCard(child: Text(g.katha, style: const TextStyle(fontSize: 16, height: 1.6, color: AppColors.textPrimary))),
        ],
        if (g.aartiLines.isNotEmpty) ...[
          _section(g.aartiTitle.isEmpty ? 'Aarti' : g.aartiTitle, Icons.light_mode_rounded),
          _MantraCard(lines: g.aartiLines),
        ],
        if (g.tips.isNotEmpty) ...[
          _section('Tips', Icons.lightbulb_outline_rounded),
          for (final t in g.tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ', style: TextStyle(fontSize: 16, color: AppColors.primary)),
                Expanded(child: Text(t, style: AppText.body.copyWith(fontSize: 15))),
              ]),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.diversity_3_rounded, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Expanded(child: Text(g.regionalNote, style: AppText.caption)),
        ]),
      ],
    );
  }

  Widget _header(PujaGuide g) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(gradient: guideGradient(g.category), borderRadius: AppRadius.card),
      child: Row(children: [
        GuideThumb(guide: g, width: 72, height: 72),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.titleHi, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(g.deity, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.3)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              AppBadge(label: guideCategoryLabel(g.category), color: Colors.white, background: Colors.white24),
              if (g.difficulty.isNotEmpty) AppBadge(label: g.difficulty, color: Colors.white, background: Colors.white24),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _section(String title, IconData icon, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: AppText.title)),
          if (trailing != null) trailing,
        ]),
      );
}

class _StepTile extends StatelessWidget {
  final int index;
  final GuideStep step;
  const _StepTile({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
          child: Text('$index', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.text, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.textPrimary)),
            if (step.mantra != null) ...[const SizedBox(height: 8), _MantraCard(lines: [step.mantra!])],
          ]),
        ),
      ]),
    );
  }
}

class _MantraCard extends StatelessWidget {
  final List<GuideMantra> lines;
  const _MantraCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          if (lines[i].devanagari.isNotEmpty)
            SelectableText(lines[i].devanagari,
                style: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w700, color: Color(0xFF7A3E00))),
          if (lines[i].transliteration.isNotEmpty)
            SelectableText(lines[i].transliteration,
                style: const TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }
}

class _RulesCard extends StatelessWidget {
  final VratRules rules;
  const _RulesCard({required this.rules});

  Widget _group(String title, List<String> items, IconData icon, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppText.subtitle.copyWith(color: color)),
        const SizedBox(height: 4),
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(s, style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary))),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _group('Do', rules.doList, Icons.check_circle_rounded, AppColors.success),
        _group("Don't", rules.dontList, Icons.cancel_rounded, AppColors.danger),
        _group('Food', rules.food, Icons.restaurant_rounded, AppColors.primaryDark),
      ]),
    );
  }
}
