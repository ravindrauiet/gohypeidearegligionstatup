import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/buddy_service.dart';
import '../ui/app_ui.dart';

// ============================================================================
// Shared building blocks for the buddy feature: intent styling, avatar, score
// ring, breakdown bars, highlights and the report / block menu.
// ============================================================================

class BuddyIntentStyle {
  BuddyIntentStyle._();

  static IconData icon(String key) => switch (key) {
        BuddyIntent.lifePartner => Icons.favorite_rounded,
        BuddyIntent.business => Icons.handshake_rounded,
        BuddyIntent.friend => Icons.people_alt_rounded,
        BuddyIntent.travel => Icons.luggage_rounded,
        BuddyIntent.spiritual => Icons.self_improvement_rounded,
        _ => Icons.person_rounded,
      };

  static Color color(String key) => switch (key) {
        BuddyIntent.lifePartner => AppColors.love,
        BuddyIntent.business => AppColors.info,
        BuddyIntent.friend => const Color(0xFF0E9F8A),
        BuddyIntent.travel => const Color(0xFF0284C7),
        BuddyIntent.spiritual => AppColors.primary,
        _ => AppColors.textSecondary,
      };
}

const _avatarGradients = [
  [Color(0xFFFF9A5A), Color(0xFFE5560A)], // saffron
  [Color(0xFF6D5BD0), Color(0xFF2E2275)], // indigo night
  [Color(0xFFFF7A9C), Color(0xFFC2185B)], // lotus
  [Color(0xFF34C3A8), Color(0xFF0E7C6B)], // tulsi
  [Color(0xFFF5B83D), Color(0xFFD97706)], // marigold
  [Color(0xFF5AA9F5), Color(0xFF1D4ED8)], // sky
];

/// Photo, or elegant initials on a warm gradient with a faint star motif.
class BuddyAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final int seed;
  final bool ring;

  const BuddyAvatar({super.key, required this.name, this.imageUrl, this.size = 56, this.seed = 0, this.ring = false});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final g = _avatarGradients[seed.abs() % _avatarGradients.length];
    final fallback = DecoratedBox(
      decoration:
          BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Stack(fit: StackFit.expand, children: [
        Positioned(
          right: size * 0.08,
          top: size * 0.08,
          child: Icon(Icons.auto_awesome, size: size * 0.22, color: Colors.white.withValues(alpha: 0.35)),
        ),
        Center(
          child: Text(_initials,
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36, letterSpacing: 0.5)),
        ),
      ]),
    );
    final url = imageUrl?.trim() ?? '';
    final img = url.isEmpty
        ? fallback
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          );
    final avatar = ExcludeSemantics(
      child: SizedBox(width: size, height: size, child: ClipOval(child: img)),
    );
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.primaryGradient),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        child: avatar,
      ),
    );
  }
}

Color buddyScoreColor(int score) {
  if (score >= 70) return AppColors.success;
  if (score >= 55) return AppColors.primary;
  if (score >= 40) return AppColors.warning;
  return AppColors.textTertiary;
}

/// Animated ring with the overall score and an optional label below.
class BuddyScoreRing extends StatelessWidget {
  final int score;
  final double size;
  final bool showLabel;

  const BuddyScoreRing({super.key, required this.score, this.size = 84, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = buddyScoreColor(score);
    final ring = SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0, end: score / 100),
        builder: (context, v, _) => Stack(fit: StackFit.expand, children: [
          CircularProgressIndicator(
            value: v,
            strokeWidth: size * 0.09,
            strokeCap: StrokeCap.round,
            backgroundColor: color.withValues(alpha: 0.12),
            color: color,
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$score%', style: AppText.headline.copyWith(fontSize: 22)),
                const Text('match', style: AppText.caption),
              ]),
            ),
          ),
        ]),
      ),
    );
    return Semantics(
      label: '$score percent, ${buddyScoreLabel(score)}',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ring,
        if (showLabel) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: size + 24,
            child: Text(buddyScoreLabel(score),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, height: 1.2)),
          ),
        ],
      ]),
    );
  }
}

/// Kundli / Mindset / Distance bars.
class BuddyBreakdownBars extends StatelessWidget {
  final BuddyCandidate candidate;
  final bool showNotes;

  const BuddyBreakdownBars({super.key, required this.candidate, this.showNotes = false});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final mindsetNote = c.sharedAnswers > 0
        ? 'You agree on ${c.agreeAnswers} of ${c.sharedAnswers} shared questions'
        : 'Answer the mindset questions to sharpen this';
    final rows = [
      ('Kundli', c.kundliScore, Icons.brightness_3_rounded, AppColors.info, 'Moon, nakshatra and lagna harmony'),
      ('Mindset', c.mindsetScore, Icons.psychology_rounded, AppColors.primary, mindsetNote),
      (
        'Distance',
        c.distanceScore,
        Icons.place_rounded,
        const Color(0xFF0E9F8A),
        c.distanceLabel != null ? '${c.distanceLabel} away (approximate)' : 'Distance not shared'
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value, icon, color, note) in rows)
          Padding(
            padding: EdgeInsets.only(bottom: showNotes ? AppSpacing.sm : 8),
            child: Semantics(
              label: '$label $value percent',
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                  Text('$value%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: value / 100,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.12),
                    color: color,
                  ),
                ),
                if (showNotes) ...[
                  const SizedBox(height: 4),
                  Text(note, style: AppText.caption),
                ],
              ]),
            ),
          ),
      ],
    );
  }
}

class BuddyIntentChip extends StatelessWidget {
  final String intent;
  final bool dense;
  const BuddyIntentChip({super.key, required this.intent, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final color = BuddyIntentStyle.color(intent);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(BuddyIntentStyle.icon(intent), size: dense ? 12 : 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(BuddyIntent.label(intent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

/// 2-4 short "why you fit" lines.
class BuddyHighlights extends StatelessWidget {
  final List<String> highlights;
  final int max;
  const BuddyHighlights({super.key, required this.highlights, this.max = 4});

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in highlights.take(max))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.gold),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(h, style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 13))),
            ]),
          ),
      ],
    );
  }
}

/// Small count badge (e.g. new requests).
class BuddyCountBadge extends StatelessWidget {
  final int count;
  const BuddyCountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1.3)),
    );
  }
}

// ---------------------------------------------------------------- safety

enum _PersonAction { profile, report, block }

/// The ⋮ menu shown wherever a person appears: (view profile), report, block.
/// [onRemoved] runs after a successful block/report (e.g. pop the screen).
class BuddyPersonMenu extends StatelessWidget {
  final int userId;
  final String name;
  final VoidCallback? onViewProfile;
  final VoidCallback? onRemoved;
  final Color? color;

  const BuddyPersonMenu({
    super.key,
    required this.userId,
    required this.name,
    this.onViewProfile,
    this.onRemoved,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PersonAction>(
      tooltip: 'More options for $name',
      icon: Icon(Icons.more_vert_rounded, color: color ?? AppColors.textSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      onSelected: (a) async {
        switch (a) {
          case _PersonAction.profile:
            onViewProfile?.call();
          case _PersonAction.report:
            if (await showBuddyReportSheet(context, userId: userId, name: name)) onRemoved?.call();
          case _PersonAction.block:
            if (await confirmBuddyBlock(context, userId: userId, name: name)) onRemoved?.call();
        }
      },
      itemBuilder: (_) => [
        if (onViewProfile != null)
          const PopupMenuItem(
            value: _PersonAction.profile,
            child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_outline_rounded),
                title: Text('View profile')),
          ),
        const PopupMenuItem(
          value: _PersonAction.report,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.flag_outlined), title: Text('Report')),
        ),
        const PopupMenuItem(
          value: _PersonAction.block,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block_rounded, color: AppColors.danger),
            title: Text('Block', style: TextStyle(color: AppColors.danger)),
          ),
        ),
      ],
    );
  }
}

/// Returns true if the person was blocked.
Future<bool> confirmBuddyBlock(BuildContext context, {required int userId, required String name}) async {
  final service = context.read<BuddyService>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block $name?'),
      content: const Text(
          "They won't be able to see you, send requests or message you. They won't be told that you blocked them."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await service.block(userId);
    if (context.mounted) showAppSnack(context, '$name is blocked');
    return true;
  } catch (e) {
    if (context.mounted) showAppSnack(context, BuddyService.errorText(e), error: true);
    return false;
  }
}

/// Returns true if the person was reported (which also blocks them).
Future<bool> showBuddyReportSheet(BuildContext context, {required int userId, required String name}) async {
  final service = context.read<BuddyService>();
  final result =
      await showAppSheet<bool>(context, builder: (ctx) => _ReportSheet(service: service, userId: userId, name: name));
  if (result == true && context.mounted) {
    showAppSnack(context, 'Thank you. Our team will review this. $name is blocked for you.');
  }
  return result == true;
}

class _ReportSheet extends StatefulWidget {
  final BuddyService service;
  final int userId;
  final String name;
  const _ReportSheet({required this.service, required this.userId, required this.name});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.service.report(widget.userId, _reason!, details: _details.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = BuddyService.errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Report ${widget.name}', style: AppText.title),
          const SizedBox(height: 4),
          const Text('Your report is private. We will also block this person for you.', style: AppText.body),
          const SizedBox(height: AppSpacing.md),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final e in buddyReportReasons.entries)
                RadioListTile<String>(
                  value: e.key,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(e.value, style: AppText.bodyStrong),
                ),
            ]),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _details,
            maxLength: 500,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(hintText: 'Anything else we should know? (optional)'),
          ),
          if (_error != null) ...[
            Text(_error!, style: AppText.body.copyWith(color: AppColors.danger)),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            label: 'Report and block',
            icon: Icons.flag_rounded,
            variant: AppButtonVariant.dark,
            loading: _sending,
            onPressed: _reason == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// Soft tinted info strip (privacy / safety notes).
class BuddyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Widget? trailing;

  const BuddyNote({super.key, required this.icon, required this.text, this.color = AppColors.info, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 13))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
