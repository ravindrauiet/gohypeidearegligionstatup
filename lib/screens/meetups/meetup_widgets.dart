import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/meetup_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'meetup_detail_screen.dart';

/// Icon + accent colour per meetup type.
class MeetupTypeStyle {
  MeetupTypeStyle._();

  static IconData icon(String type) => switch (type) {
        MeetupType.aarti => Icons.local_fire_department_rounded,
        MeetupType.bhajanSandhya => Icons.music_note_rounded,
        MeetupType.seva => Icons.volunteer_activism_rounded,
        MeetupType.yoga => Icons.self_improvement_rounded,
        MeetupType.satsang => Icons.groups_rounded,
        MeetupType.kirtan => Icons.queue_music_rounded,
        _ => Icons.temple_hindu_rounded,
      };

  static Color color(String type) => switch (type) {
        MeetupType.aarti => AppColors.primary,
        MeetupType.bhajanSandhya => AppColors.info,
        MeetupType.seva => AppColors.success,
        MeetupType.yoga => const Color(0xFF0E9F9A),
        MeetupType.satsang => AppColors.cosmicLight,
        MeetupType.kirtan => AppColors.love,
        _ => AppColors.warning,
      };
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "6:30 PM"
String meetupTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// "Sat, 8 Nov · 6:30 – 8:00 PM"
String meetupWhen(Meetup m) {
  final s = m.startsAt;
  final sameDay = s.year == m.endsAt.year && s.month == m.endsAt.month && s.day == m.endsAt.day;
  final day = '${_weekdays[s.weekday - 1]}, ${s.day} ${_months[s.month - 1]}';
  return '$day · ${meetupTime(s)} – ${sameDay ? meetupTime(m.endsAt) : '${m.endsAt.day} ${_months[m.endsAt.month - 1]} ${meetupTime(m.endsAt)}'}';
}

/// Calendar-style date block: "NOV / 8 / SAT".
class MeetupDateBlock extends StatelessWidget {
  final DateTime date;
  final Color color;
  final double width;
  const MeetupDateBlock({super.key, required this.date, this.color = AppColors.primary, this.width = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_months[date.month - 1].toUpperCase(),
            maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: color)),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('${date.day}',
              style: const TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
        Text(_weekdays[date.weekday - 1],
            maxLines: 1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ]),
    );
  }
}

/// Small "verified" tick used next to host / attendee names.
class MeetupVerifiedTick extends StatelessWidget {
  final double size;
  const MeetupVerifiedTick({super.key, this.size = 14});
  @override
  Widget build(BuildContext context) =>
      Semantics(label: 'verified', child: Icon(Icons.verified_rounded, size: size, color: AppColors.info));
}

/// Initials avatar for attendees (no photos: the server never sends them).
class MeetupInitials extends StatelessWidget {
  final MeetupPerson person;
  final double size;
  const MeetupInitials({super.key, required this.person, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final palette = [AppColors.primary, AppColors.info, AppColors.success, AppColors.love, AppColors.cosmicLight];
    final c = palette[person.displayName.hashCode.abs() % palette.length];
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        child: Text(person.initials,
            maxLines: 1,
            style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: c)),
      ),
      if (person.verified)
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: MeetupVerifiedTick(size: size * 0.38),
          ),
        ),
    ]);
  }
}

/// "Hosted by Asha ✓" / "Official CosmicGuide event".
class MeetupHostLine extends StatelessWidget {
  final Meetup meetup;
  const MeetupHostLine({super.key, required this.meetup});

  @override
  Widget build(BuildContext context) {
    final h = meetup.host;
    if (h == null || meetup.official) {
      return Row(children: [
        const Icon(Icons.workspace_premium_rounded, size: 14, color: AppColors.gold),
        const SizedBox(width: 4),
        Flexible(
          child: Text('Official CosmicGuide event',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
        ),
      ]);
    }
    return Row(children: [
      const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textTertiary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(meetup.isHost ? 'Hosted by you' : 'Hosted by ${h.displayName}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
      ),
      if (h.verified) ...[const SizedBox(width: 3), const MeetupVerifiedTick(size: 13)],
    ]);
  }
}

/// Status pill: Going / Checked in / Full / Cancelled / Pending review / Live.
Widget? meetupStatusBadge(Meetup m) {
  if (m.isCancelled) return const AppBadge(label: 'Cancelled', color: AppColors.danger);
  if (m.isPending) return const AppBadge(label: 'Pending review', color: AppColors.warning, icon: Icons.hourglass_top_rounded);
  if (m.status == 'rejected') return const AppBadge(label: 'Not approved', color: AppColors.danger);
  if (m.isCheckedIn) return const AppBadge(label: 'Checked in', color: AppColors.success, icon: Icons.check_circle_rounded);
  if (m.isGoing) return const AppBadge(label: 'Going', color: AppColors.success, icon: Icons.event_available_rounded);
  if (m.phase == 'live') return const AppBadge(label: 'Happening now', color: AppColors.love);
  if (m.isFull) return const AppBadge(label: 'Full', color: AppColors.textSecondary);
  return null;
}

/// List card: date block, type, title, venue, distance, spots left, badges.
class MeetupCard extends StatelessWidget {
  final Meetup meetup;
  final VoidCallback? onTap;
  const MeetupCard({super.key, required this.meetup, this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = meetup;
    final color = MeetupTypeStyle.color(m.type);
    final status = meetupStatusBadge(m);
    final place = [m.venueName, if (m.city != null) m.city!].join(', ');
    final facts = <String>[
      meetupTime(m.startsAt),
      if (m.distanceKm != null) '${m.distanceKm} km',
      if (!m.isCancelled && !m.isEnded) m.isFull ? 'Full' : '${m.spotsLeft} ${m.spotsLeft == 1 ? 'spot' : 'spots'} left',
    ];
    return Semantics(
      button: onTap != null,
      label: '${MeetupType.label(m.type)}: ${m.title}',
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MeetupDateBlock(date: m.startsAt, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                AppBadge(label: MeetupType.label(m.type), color: color, icon: MeetupTypeStyle.icon(m.type)),
                if (m.womenOnly) const AppBadge(label: 'Women only', color: AppColors.love, icon: Icons.female_rounded),
                if (status != null) status,
              ]),
              const SizedBox(height: 6),
              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_outlined, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(place,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(facts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                      color: m.isFull ? AppColors.textTertiary : AppColors.textPrimary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              MeetupHostLine(meetup: m),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Compact Home rail: "Satsang near you" + horizontally scrolling cards.
/// Loads quietly (never asks for location); hidden on errors.
class MeetupsHomeRail extends StatefulWidget {
  final VoidCallback? onSeeAll;

  /// Opens a meetup; defaults to pushing [MeetupDetailScreen].
  final void Function(Meetup meetup)? onOpen;
  const MeetupsHomeRail({super.key, this.onSeeAll, this.onOpen});

  @override
  State<MeetupsHomeRail> createState() => _MeetupsHomeRailState();
}

class _MeetupsHomeRailState extends State<MeetupsHomeRail> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      await context.read<MeetupService>().loadNearby();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _open(Meetup m) {
    final cb = widget.onOpen;
    if (cb != null) return cb(m);
    Navigator.of(context).push(MeetupDetailScreen.route(m.id, initial: m));
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<MeetupService>().nearby;
    if (_failed && list == null) return const SizedBox.shrink();
    final items = list?.meetups.take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SectionHeader(
        title: 'Satsang near you',
        subtitle: 'Small group events at temples',
        onAction: widget.onSeeAll,
      ),
      if (items == null)
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.pagePadding,
            itemCount: 2,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, __) => const SkeletonBox(width: 260, height: 128),
          ),
        )
      else if (items.isEmpty)
        Padding(
          padding: AppSpacing.pagePadding,
          child: AppCard(
            onTap: widget.onSeeAll,
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: const Icon(Icons.groups_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('No meetups near you yet', style: AppText.bodyStrong),
                  Text('Aarti, kirtan and seva in small groups. Be the first to host one.', style: AppText.caption),
                ]),
              ),
            ]),
          ),
        )
      else
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.pagePadding,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) => _RailCard(meetup: items[i], onTap: () => _open(items[i])),
          ),
        ),
    ]);
  }
}

class _RailCard extends StatelessWidget {
  final Meetup meetup;
  final VoidCallback onTap;
  const _RailCard({required this.meetup, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = meetup;
    final color = MeetupTypeStyle.color(m.type);
    final width = (MediaQuery.sizeOf(context).width * 0.78).clamp(220.0, 280.0);
    return SizedBox(
      width: width,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MeetupDateBlock(date: m.startsAt, color: color, width: 50),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(m.venueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
              const Spacer(),
              Text(
                [meetupTime(m.startsAt), if (m.distanceKm != null) '${m.distanceKm} km', if (m.isGoing) 'Going'].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: m.isGoing ? AppColors.success : color, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
