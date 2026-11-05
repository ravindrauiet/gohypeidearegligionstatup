import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_service.dart';
import '../../services/notification_inbox_service.dart';
import '../../services/notification_router.dart';
import '../../utils/app_routes.dart';
import '../../widgets/ui/app_ui.dart';

/// Opens a notification payload (defaults to [NotificationRouter.open]).
typedef NotificationOpener = Future<void> Function(Map<String, dynamic> data);

// ============================================================================
// Pure helpers (unit-tested)
// ============================================================================

enum InboxGroup { today, yesterday, earlier }

extension InboxGroupLabel on InboxGroup {
  String get label => switch (this) {
        InboxGroup.today => 'Today',
        InboxGroup.yesterday => 'Yesterday',
        InboxGroup.earlier => 'Earlier',
      };
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Which section a notification created at [at] belongs to, seen from [now].
InboxGroup inboxGroupFor(DateTime? at, DateTime now) {
  if (at == null) return InboxGroup.earlier;
  final days = _day(now).difference(_day(at)).inDays;
  if (days <= 0) return InboxGroup.today;
  if (days == 1) return InboxGroup.yesterday;
  return InboxGroup.earlier;
}

/// Short relative time: "Just now", "5m ago", "3h ago", "Yesterday", "Mon", "12 Oct", "12 Oct 2025".
String inboxRelativeTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final diff = now.difference(at);
  final days = _day(now).difference(_day(at)).inDays;
  if (diff.inMinutes < 1) return 'Just now';
  if (days <= 0) {
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(at);
  if (at.year == now.year) return DateFormat('d MMM').format(at);
  return DateFormat('d MMM y').format(at);
}

/// "99+" cap for badges.
String inboxBadgeText(int count) => count > 99 ? '99+' : '$count';

/// Icon + tint per notification `type` (see the notification contract).
(IconData, Color) inboxTypeStyle(String type) => switch (type) {
      'buddy_request' => (Icons.person_add_alt_1_rounded, AppColors.love),
      'buddy_accepted' => (Icons.handshake_rounded, AppColors.success),
      'buddy_message' => (Icons.chat_bubble_rounded, AppColors.info),
      'nearby_buddy' => (Icons.near_me_rounded, AppColors.love),
      'trip_update' => (Icons.temple_hindu_rounded, AppColors.warning),
      'coins' => (Icons.monetization_on_rounded, const Color(0xFFD99A1E)),
      'checkin' => (Icons.event_available_rounded, AppColors.success),
      'daily_horoscope' => (Icons.auto_awesome_rounded, AppColors.cosmicLight),
      'festival' => (Icons.celebration_rounded, AppColors.primary),
      'videos' => (Icons.play_circle_fill_rounded, AppColors.danger),
      'mindset' => (Icons.psychology_rounded, AppColors.info),
      'announcement' => (Icons.campaign_rounded, AppColors.primary),
      _ => (Icons.notifications_rounded, AppColors.textSecondary),
    };

/// Announcements and plain `inbox` rows are read in place (the router would
/// just reopen this screen); an announcement's `url` opens from the sheet.
bool _opensInPlace(InboxNotification n) => n.type == 'inbox' || n.type == 'announcement';

// ============================================================================
// Screen
// ============================================================================

class NotificationInboxScreen extends StatefulWidget {
  /// Overrides how a tapped notification is opened (tests).
  final NotificationOpener? onOpen;

  /// Overrides the provided [NotificationInboxService] (tests).
  final NotificationInboxService? service;

  const NotificationInboxScreen({super.key, this.onOpen, this.service});

  @override
  State<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

sealed class _Entry {}

class _HeaderEntry extends _Entry {
  final String label;
  _HeaderEntry(this.label);
}

class _ItemEntry extends _Entry {
  final InboxNotification n;
  final bool lastInGroup;
  _ItemEntry(this.n, this.lastInGroup);
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  NotificationInboxService? _svc;
  bool _ownsService = false;
  final ScrollController _scroll = ScrollController();

  NotificationInboxService get svc => _svc!;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_svc != null) return;
    var s = widget.service;
    if (s == null) {
      try {
        s = Provider.of<NotificationInboxService>(context, listen: false);
      } on ProviderNotFoundException {
        s = NotificationInboxService(Provider.of<BackendService>(context, listen: false));
        _ownsService = true;
      }
    }
    _svc = s;
    s.addListener(_onServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(svc.refresh());
    });
  }

  @override
  void dispose() {
    _svc?.removeListener(_onServiceChanged);
    if (_ownsService) _svc?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
    // A short first page may not fill the screen: keep loading.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  void _onScroll() => _maybeLoadMore();

  void _maybeLoadMore() {
    if (!mounted || !_scroll.hasClients) return;
    final s = svc;
    if (!s.hasMore || s.loadingMore || s.loading || s.loadMoreError != null) return;
    if (_scroll.position.extentAfter < 500) unawaited(s.loadMore());
  }

  NotificationOpener get _opener => widget.onOpen ?? NotificationRouter.open;

  Future<void> _onTap(InboxNotification n) async {
    if (!n.read) unawaited(svc.markRead(n.id));
    if (_opensInPlace(n)) {
      await _showDetail(n);
      return;
    }
    await _opener(n.routeData);
  }

  Future<void> _markAll() async {
    final ok = await svc.markAllRead();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text("Couldn't mark all as read. Please try again.")));
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && uri.hasScheme && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text("Couldn't open the link.")));
    }
  }

  Future<void> _showDetail(InboxNotification n) {
    final (icon, color) = inboxTypeStyle(n.type);
    final url = (n.data['url'] ?? '').toString().trim();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TypeIcon(icon: icon, color: color, size: 48),
                const SizedBox(height: AppSpacing.sm),
                Text(n.title.isEmpty ? 'Update' : n.title, style: AppText.title),
                const SizedBox(height: AppSpacing.xxs),
                Text(inboxRelativeTime(n.createdAt, DateTime.now()), style: AppText.caption),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(n.body, style: AppText.body.copyWith(color: AppColors.textPrimary)),
                ],
                if (url.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Open',
                    icon: Icons.open_in_new_rounded,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      unawaited(_openUrl(url));
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_Entry> _entries(List<InboxNotification> items) {
    final now = DateTime.now();
    final out = <_Entry>[];
    InboxGroup? current;
    for (var i = 0; i < items.length; i++) {
      final g = inboxGroupFor(items[i].createdAt, now);
      if (g != current) {
        out.add(_HeaderEntry(g.label));
        current = g;
      }
      final nextGroup = i + 1 < items.length ? inboxGroupFor(items[i + 1].createdAt, now) : null;
      out.add(_ItemEntry(items[i], nextGroup != g));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = svc;
    final showMarkAll = s.signedIn && (s.unread > 0 || s.items.any((n) => !n.read));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (showMarkAll)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: TextButton.icon(
                onPressed: _markAll,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Mark all read', maxLines: 1),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                ),
              ),
            ),
        ],
      ),
      body: _body(s),
    );
  }

  Widget _body(NotificationInboxService s) {
    if (!s.signedIn) {
      return _scrollableCenter(AppStateView(
        icon: Icons.notifications_none_rounded,
        title: 'Sign in to see your notifications',
        message: 'Buddy requests, trip updates and rewards will show up here.',
        actionLabel: 'Sign in',
        onAction: () => Navigator.of(context).pushNamed(AppRoutes.login),
      ));
    }
    if (s.items.isEmpty && (s.loading || !s.loaded) && s.error == null) {
      return const _InboxSkeleton();
    }
    if (s.items.isEmpty && s.error != null) {
      return RefreshIndicator(
        onRefresh: s.refresh,
        child: _scrollableCenter(AppStateView.error(
          title: "Couldn't load notifications",
          message: s.error,
          onAction: s.refresh,
        )),
      );
    }
    if (s.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: s.refresh,
        child: _scrollableCenter(const AppStateView(
          icon: Icons.notifications_active_outlined,
          title: "You're all caught up",
          message: "We'll let you know when something new happens.",
          color: AppColors.success,
        )),
      );
    }

    final entries = _entries(s.items);
    final footer = s.loadingMore || s.loadMoreError != null || (!s.hasMore && s.items.length > 6);
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        itemCount: entries.length + (footer ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= entries.length) return _footer(s);
          final e = entries[i];
          return switch (e) {
            _HeaderEntry(:final label) => _GroupHeader(label: label),
            _ItemEntry(:final n, :final lastInGroup) => _NotificationTile(
                key: ValueKey('inbox-${n.id}'),
                n: n,
                showDivider: !lastInGroup,
                onTap: () => _onTap(n),
              ),
          };
        },
      ),
    );
  }

  Widget _footer(NotificationInboxService s) {
    if (s.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    }
    if (s.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const Text("Couldn't load more", style: AppText.caption, textAlign: TextAlign.center),
            TextButton(onPressed: s.loadMore, child: const Text('Retry')),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Text("That's everything", textAlign: TextAlign.center, style: AppText.caption),
    );
  }

  /// Centered content that still supports pull-to-refresh and small screens.
  Widget _scrollableCenter(Widget child) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(child: child),
          ),
        ),
      );
}

// ============================================================================
// Pieces
// ============================================================================

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xs),
        child: Text(label.toUpperCase(), style: AppText.overline),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _TypeIcon({required this.icon, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final InboxNotification n;
  final bool showDivider;
  final VoidCallback onTap;

  const _NotificationTile({super.key, required this.n, required this.showDivider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = inboxTypeStyle(n.type);
    final unread = !n.read;
    final time = inboxRelativeTime(n.createdAt, DateTime.now());
    final title = n.title.isEmpty ? 'Update' : n.title;

    return Semantics(
      button: true,
      label: [if (unread) 'Unread.', title, if (n.body.isNotEmpty) n.body, if (time.isNotEmpty) time].join(' '),
      excludeSemantics: true,
      child: Material(
        color: unread ? const Color(0xFFFFF8F2) : AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TypeIcon(icon: icon, color: color),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.bodyStrong.copyWith(
                                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                                      color: unread ? AppColors.textPrimary : AppColors.textSecondary),
                                ),
                              ),
                              if (time.isNotEmpty) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(time,
                                      maxLines: 1,
                                      style: AppText.caption.copyWith(
                                          color: unread ? AppColors.primaryDark : AppColors.textTertiary,
                                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                                ),
                              ],
                            ],
                          ),
                          if (n.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(n.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body.copyWith(fontSize: 13)),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 18,
                      child: unread
                          ? Padding(
                              padding: const EdgeInsets.only(top: 6, left: 8),
                              child: Container(
                                key: const ValueKey('inbox-unread-dot'),
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              if (showDivider)
                const Divider(height: 1, thickness: 1, indent: AppSpacing.page + 44 + AppSpacing.sm, color: AppColors.divider),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('inbox-skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      itemCount: 7,
      itemBuilder: (_, i) => Container(
        color: AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 44, height: 44, radius: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.55, child: const SkeletonBox(height: 14)),
                  const SizedBox(height: 8),
                  const SkeletonBox(height: 11),
                  const SizedBox(height: 6),
                  const FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
