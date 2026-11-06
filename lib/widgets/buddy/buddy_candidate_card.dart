import 'package:flutter/material.dart';

import '../../services/buddy_service.dart';
import '../ui/app_ui.dart';
import 'buddy_ui.dart';
import 'trust_badges.dart';

/// The Discover card: who they are, how well you fit, and why.
class BuddyCandidateCard extends StatelessWidget {
  final BuddyCandidate candidate;
  final VoidCallback onOpen;
  final VoidCallback onSkip;
  final VoidCallback onConnect;
  final VoidCallback? onRemoved;

  const BuddyCandidateCard({
    super.key,
    required this.candidate,
    required this.onOpen,
    required this.onSkip,
    required this.onConnect,
    this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final conn = c.connection;
    final metaStyle = AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 13);
    return AppCard(
      shadow: true,
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: avatar, name, meta, menu.
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, 4, AppSpacing.sm),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primarySoft, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BuddyAvatar(name: c.displayName, imageUrl: c.photoUrl, size: 60, seed: c.userId, ring: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    BuddyNameWithBadge(
                      text: c.age != null ? '${c.displayName}, ${c.age}' : c.displayName,
                      verified: c.verified,
                      badgeSize: 18,
                      style: AppText.title,
                    ),
                    const SizedBox(height: 3),
                    Wrap(spacing: 10, runSpacing: 2, children: [
                      if (c.city != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.location_city_rounded, size: 14, color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Flexible(
                              child: Text(c.city!, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle)),
                        ]),
                      if (c.distanceLabel != null)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.near_me_rounded, size: 14, color: AppColors.textTertiary),
                          const SizedBox(width: 3),
                          Text(c.distanceLabel!, style: metaStyle),
                        ]),
                    ]),
                    if (c.careerLine != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.school_outlined, size: 14, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                            child:
                                Text(c.careerLine!, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle)),
                      ]),
                    ],
                    if (c.phoneVerified) ...[const SizedBox(height: 4), const PhoneVerifiedChip()],
                  ]),
                ),
              ),
              BuddyPersonMenu(userId: c.userId, name: c.firstName, onViewProfile: onOpen, onRemoved: onRemoved),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              BuddyScoreRing(score: c.score, size: 86),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: BuddyBreakdownBars(candidate: c)),
            ]),
          ),
          if (c.highlights.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: BuddyHighlights(highlights: c.highlights),
            ),
          if (c.intents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final i in c.intents) BuddyIntentChip(intent: i, dense: true),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: conn != null && conn.isPending && !conn.isIncoming
                ? const BuddyNote(
                    icon: Icons.schedule_rounded, text: 'Request sent. We will let you know when they reply.')
                : Row(children: [
                    Expanded(
                      child: AppButton(
                        label: 'Skip',
                        icon: Icons.close_rounded,
                        variant: AppButtonVariant.outline,
                        height: 48,
                        onPressed: onSkip,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: conn != null && conn.isIncoming ? 'Accept' : 'Connect',
                        icon: Icons.favorite_border_rounded,
                        height: 48,
                        onPressed: onConnect,
                      ),
                    ),
                  ]),
          ),
        ],
      ),
    );
  }
}

/// Compact tile for rails (Home, nearby popup).
class BuddyMiniTile extends StatelessWidget {
  static const double width = 128;

  final BuddyCandidate candidate;
  final VoidCallback onTap;

  const BuddyMiniTile({super.key, required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final color = buddyScoreColor(c.score);
    final sub = c.distanceLabel ?? c.city ?? (c.intents.isNotEmpty ? BuddyIntent.label(c.intents.first) : '');
    return Semantics(
      button: true,
      label: '${c.displayName}${c.verified ? ', verified' : ''}, ${c.score} percent match. $sub',
      onTap: onTap,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: SizedBox(
          width: width - 20,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
              BuddyAvatar(name: c.displayName, imageUrl: c.photoUrl, size: 64, seed: c.userId),
              Positioned(
                bottom: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text('${c.score}%',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            BuddyNameWithBadge(
              text: c.age != null ? '${c.firstName}, ${c.age}' : c.firstName,
              verified: c.verified,
              badgeSize: 14,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.textSecondary)),
            if (c.intents.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final i in c.intents.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(BuddyIntentStyle.icon(i), size: 14, color: BuddyIntentStyle.color(i)),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
