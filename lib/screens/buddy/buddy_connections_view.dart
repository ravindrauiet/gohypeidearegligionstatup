import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import 'buddy_chat_screen.dart';
import 'buddy_profile_screen.dart';

void _openProfile(BuildContext context, BuddyCandidate c) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => BuddyProfileScreen(userId: c.userId, initial: c),
  ));
}

Future<void> _refresh(BuildContext context) async {
  try {
    await context.read<BuddyService>().loadConnections();
  } catch (e) {
    if (context.mounted) showAppSnack(context, BuddyService.errorText(e), error: true);
  }
}

/// Shared loading / error wrapper for the two connection lists.
class _ConnectionsScaffold extends StatefulWidget {
  final Widget Function(BuildContext context, BuddyConnections c) builder;
  const _ConnectionsScaffold({required this.builder});

  @override
  State<_ConnectionsScaffold> createState() => _ConnectionsScaffoldState();
}

class _ConnectionsScaffoldState extends State<_ConnectionsScaffold> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await context.read<BuddyService>().loadConnections();
    } catch (e) {
      if (mounted) setState(() => _error = BuddyService.errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<BuddyService>();
    if (!s.connectionsLoaded) {
      if (_error != null) return Center(child: AppStateView.error(message: _error, onAction: _load));
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          for (var i = 0; i < 4; i++) ...[
            const SkeletonBox(height: 84, radius: AppRadius.lg),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }
    return RefreshIndicator(onRefresh: () => _refresh(context), child: widget.builder(context, s.connections));
  }
}

// ---------------------------------------------------------------- requests

class BuddyRequestsView extends StatelessWidget {
  const BuddyRequestsView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ConnectionsScaffold(builder: (context, c) {
      if (c.incoming.isEmpty && c.outgoing.isEmpty) {
        return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
          AppStateView(
            icon: Icons.mark_email_unread_outlined,
            title: 'No requests yet',
            message: 'When someone wants to connect, you will see them here. You can also send requests from Discover.',
          ),
        ]);
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          if (c.incoming.isNotEmpty) ...[
            SectionHeader(title: 'Wants to connect', subtitle: '${c.incoming.length} waiting for you'),
            for (final x in c.incoming) _RequestCard(conn: x, incoming: true),
          ],
          if (c.outgoing.isNotEmpty) ...[
            const SectionHeader(title: 'Sent by you', subtitle: 'Waiting for their reply'),
            for (final x in c.outgoing) _RequestCard(conn: x, incoming: false),
          ],
        ],
      );
    });
  }
}

class _RequestCard extends StatefulWidget {
  final BuddyConnection conn;
  final bool incoming;
  const _RequestCard({required this.conn, required this.incoming});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  String? _busy;

  Future<void> _do(String action) async {
    final s = context.read<BuddyService>();
    final name = widget.conn.other.firstName;
    setState(() => _busy = action);
    try {
      switch (action) {
        case 'accept':
          await s.accept(widget.conn.id);
          if (mounted) showAppSnack(context, 'You and $name are now buddies');
        case 'decline':
          await s.decline(widget.conn.id);
        default:
          await s.cancel(widget.conn.id);
          if (mounted) showAppSnack(context, 'Request cancelled');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, BuddyService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.conn;
    final o = x.other;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
      child: AppCard(
        onTap: () => _openProfile(context, o),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, 4, AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            BuddyAvatar(name: o.displayName, imageUrl: o.photoUrl, size: 52, seed: o.userId),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.age != null ? '${o.displayName}, ${o.age}' : o.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  BuddyIntentChip(intent: x.intent, dense: true),
                  if (o.score > 0) AppBadge(label: '${o.score}% match', color: buddyScoreColor(o.score)),
                  if (o.city != null) Text(o.city!, style: AppText.caption),
                ]),
              ]),
            ),
            BuddyPersonMenu(userId: o.userId, name: o.firstName, onViewProfile: () => _openProfile(context, o)),
          ]),
          if (x.message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration:
                    BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Text('"${x.message}"',
                    style: AppText.body.copyWith(fontStyle: FontStyle.italic, color: AppColors.textPrimary)),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: widget.incoming
                ? Row(children: [
                    Expanded(
                      child: AppButton(
                        label: 'Decline',
                        height: 44,
                        variant: AppButtonVariant.outline,
                        loading: _busy == 'decline',
                        onPressed: _busy != null ? null : () => _do('decline'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        label: 'Accept',
                        icon: Icons.check_rounded,
                        height: 44,
                        loading: _busy == 'accept',
                        onPressed: _busy != null ? null : () => _do('accept'),
                      ),
                    ),
                  ])
                : Row(children: [
                    const Icon(Icons.schedule_rounded, size: 16, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        x.createdAt != null ? 'Sent ${DateFormat('d MMM').format(x.createdAt!)}' : 'Sent',
                        style: AppText.caption,
                      ),
                    ),
                    AppButton(
                      label: 'Cancel',
                      expand: false,
                      height: 40,
                      variant: AppButtonVariant.ghost,
                      loading: _busy == 'cancel',
                      onPressed: _busy != null ? null : () => _do('cancel'),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------- buddies

class BuddyListView extends StatelessWidget {
  const BuddyListView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ConnectionsScaffold(builder: (context, c) {
      if (c.buddies.isEmpty) {
        return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
          AppStateView(
            icon: Icons.diversity_1_rounded,
            title: 'Your buddies will live here',
            message: 'Once someone accepts your request (or you accept theirs), you can chat here.',
          ),
        ]);
      }
      final sorted = [...c.buddies]..sort((a, b) {
          final ta = a.lastMessage?.createdAt ?? a.createdAt ?? DateTime(2000);
          final tb = b.lastMessage?.createdAt ?? b.createdAt ?? DateTime(2000);
          return tb.compareTo(ta);
        });
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const Divider(indent: 80),
        itemBuilder: (_, i) => _BuddyRow(conn: sorted[i]),
      );
    });
  }
}

class _BuddyRow extends StatelessWidget {
  final BuddyConnection conn;
  const _BuddyRow({required this.conn});

  String _time(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return DateFormat('h:mm a').format(d);
    if (now.difference(d).inDays < 7) return DateFormat('EEE').format(d);
    return DateFormat('d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final o = conn.other;
    final last = conn.lastMessage;
    final unread = conn.unread > 0;
    final preview = last == null ? 'Say namaste to ${o.firstName}' : '${last.mine ? 'You: ' : ''}${last.body}';
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BuddyChatScreen(connection: conn),
      )),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, 4, AppSpacing.sm),
        child: Row(children: [
          BuddyAvatar(name: o.displayName, imageUrl: o.photoUrl, size: 52, seed: o.userId),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(o.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.subtitle.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                ),
                if (last != null)
                  Text(_time(last.createdAt),
                      style: AppText.caption.copyWith(color: unread ? AppColors.primary : AppColors.textTertiary)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(BuddyIntentStyle.icon(conn.intent), size: 13, color: BuddyIntentStyle.color(conn.intent)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      fontSize: 13,
                      color: unread ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      fontStyle: last == null ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 6),
                  Semantics(label: '${conn.unread} unread', child: BuddyCountBadge(conn.unread)),
                ],
              ]),
            ]),
          ),
          BuddyPersonMenu(userId: o.userId, name: o.firstName, onViewProfile: () => _openProfile(context, o)),
        ]),
      ),
    );
  }
}
