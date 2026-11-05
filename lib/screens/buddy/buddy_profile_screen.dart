import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import 'buddy_chat_screen.dart';
import 'buddy_connect_sheet.dart';

/// Full view of another person: score, breakdown, highlights, bio and an
/// honest note on how the score works.
class BuddyProfileScreen extends StatefulWidget {
  final int userId;

  /// Shown immediately while the fresh copy loads.
  final BuddyCandidate? initial;

  const BuddyProfileScreen({super.key, required this.userId, this.initial});

  @override
  State<BuddyProfileScreen> createState() => _BuddyProfileScreenState();
}

class _BuddyProfileScreenState extends State<BuddyProfileScreen> {
  BuddyCandidate? _c;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  /// Server said 404 (blocked, paused or gone) even though we had a copy.
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _c = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await context.read<BuddyService>().user(widget.userId);
      if (!mounted) return;
      setState(() {
        _c = c ?? _c;
        _loading = false;
        _unavailable = c == null;
        if (c == null && _c == null) _error = 'This profile is no longer available.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e is BuddyBannedException) {
          _unavailable = true;
          if (_c == null) _error = BuddyService.bannedMessage;
        } else if (e is BackendException && e.statusCode == 404) {
          _unavailable = true;
          if (_c == null) _error = 'This profile is no longer available.';
        } else if (_c == null) {
          _error = BuddyService.errorText(e);
        }
      });
    }
  }

  Future<void> _connect() async {
    final c = _c;
    if (c == null) return;
    final ref = await showBuddyConnectSheet(context, c);
    if (ref != null && mounted) _load();
  }

  Future<void> _act(Future<void> Function(BuddyService s, int id) fn, String done) async {
    final conn = _c?.connection;
    if (conn == null) return;
    setState(() => _busy = true);
    try {
      await fn(context.read<BuddyService>(), conn.id);
      if (mounted) showAppSnack(context, done);
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, BuddyService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChat() async {
    final c = _c;
    final conn = c?.connection;
    if (c == null || conn == null) return;
    // Use the real connection (right intent, unread) when we have it.
    final known = context.read<BuddyService>().connections.buddies.where((b) => b.id == conn.id).firstOrNull;
    final intent = known?.intent ?? (c.intents.isNotEmpty ? c.intents.first : BuddyIntent.friend);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BuddyChatScreen(
        connection:
            BuddyConnection(id: conn.id, intent: intent, status: conn.status, other: c, unread: known?.unread ?? 0),
        highlights: c.highlights,
      ),
    ));
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: AppText.subtitle),
            const SizedBox(height: AppSpacing.sm),
            child,
          ]),
        ),
      );

  Widget _hero(BuddyCandidate c) {
    return AppCard(
      gradient: AppColors.cosmicGradient,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      child: Column(children: [
        BuddyAvatar(name: c.displayName, imageUrl: c.photoUrl, size: 104, seed: c.userId, ring: true),
        const SizedBox(height: AppSpacing.md),
        Text(c.age != null ? '${c.displayName}, ${c.age}' : c.displayName,
            textAlign: TextAlign.center, style: AppText.headline.copyWith(color: Colors.white)),
        const SizedBox(height: 4),
        Text(
          [if (c.city != null) c.city!, if (c.distanceLabel != null) c.distanceLabel!].join('  ·  '),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        if (c.intents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (final i in c.intents)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(BuddyIntentStyle.icon(i), size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(BuddyIntent.label(i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _howItWorks(BuddyCandidate c) {
    final life = c.intents.contains(BuddyIntent.lifePartner) &&
        (context.read<BuddyService>().profile?.intents.contains(BuddyIntent.lifePartner) ?? false);
    final weights = life
        ? '50% Kundli (Ashtakoot Guna Milan), 40% mindset, 10% distance'
        : '30% Kundli harmony, 55% mindset, 15% distance';
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Text('How this score works', style: AppText.bodyStrong),
        ]),
        const SizedBox(height: 6),
        Text(
          'The score mixes $weights. Kundli compares both Moon signs, nakshatras and lagnas; mindset compares '
          'your answers to the 50 questions you have both answered. With few shared answers it stays close to 50%.\n\n'
          'It is a thoughtful starting point, not a verdict: no score can promise a relationship. '
          'Their birth details, chart and answers are never shown to you, and yours are never shown to them.',
          style: AppText.body.copyWith(fontSize: 13),
        ),
      ]),
    );
  }

  Widget _bottomBar(BuddyCandidate c) {
    final conn = c.connection;
    Widget child;
    if (_unavailable && !(conn?.isAccepted ?? false)) {
      child =
          const Text('This person is not available right now.', textAlign: TextAlign.center, style: AppText.bodyStrong);
    } else if (conn != null && conn.status == 'declined' && !conn.isIncoming) {
      child = Text("${c.firstName} didn't accept your request this time.",
          textAlign: TextAlign.center, style: AppText.bodyStrong);
    } else if (conn == null || (!conn.isPending && !conn.isAccepted)) {
      child = AppButton(label: 'Connect with ${c.firstName}', icon: Icons.favorite_border_rounded, onPressed: _connect);
    } else if (conn.isAccepted) {
      child = AppButton(label: 'Message ${c.firstName}', icon: Icons.chat_bubble_outline_rounded, onPressed: _openChat);
    } else if (conn.isIncoming) {
      child = Row(children: [
        Expanded(
          child: AppButton(
            label: 'Decline',
            variant: AppButtonVariant.outline,
            onPressed: _busy ? null : () => _act((s, id) => s.decline(id), 'Request declined'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: AppButton(
            label: 'Accept',
            icon: Icons.check_rounded,
            loading: _busy,
            onPressed: _busy ? null : () => _act((s, id) => s.accept(id), 'You are now buddies'),
          ),
        ),
      ]);
    } else {
      child = Row(children: [
        const Expanded(
          child: Text('Request sent. Waiting for a reply.', style: AppText.bodyStrong),
        ),
        AppButton(
          label: 'Cancel',
          expand: false,
          height: 44,
          variant: AppButtonVariant.outline,
          loading: _busy,
          onPressed: () => _act((s, id) => s.cancel(id), 'Request cancelled'),
        ),
      ]);
    }
    return DecoratedBox(
      decoration:
          const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.divider))),
      child: SafeArea(
        top: false,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
            child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Blocked / reported elsewhere (e.g. from the chat): never show them again.
    final hidden = context.watch<BuddyService>().isHidden(widget.userId);
    final c = hidden ? null : _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.firstName ?? 'Profile'),
        actions: [
          if (c != null)
            BuddyPersonMenu(
              userId: c.userId,
              name: c.firstName,
              onRemoved: () {
                if (mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      bottomNavigationBar: c == null ? null : _bottomBar(c),
      body: c == null
          ? (hidden
              ? const Center(
                  child: AppStateView(
                    icon: Icons.block_rounded,
                    title: 'Blocked',
                    message: "You won't see this person again.",
                  ),
                )
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Center(child: AppStateView.error(message: _error, onAction: _load)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
                children: [
                  _hero(c),
                  _section(
                    'Your match',
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BuddyScoreRing(score: c.score, size: 96),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: BuddyBreakdownBars(candidate: c, showNotes: true)),
                    ]),
                  ),
                  if (c.highlights.isNotEmpty)
                    _section('Why you might click', BuddyHighlights(highlights: c.highlights)),
                  if (c.bio.isNotEmpty)
                    _section('About ${c.firstName}',
                        Text(c.bio, style: AppText.body.copyWith(color: AppColors.textPrimary))),
                  if (c.languages.isNotEmpty)
                    _section(
                      'Speaks',
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final l in c.languages) AppBadge(label: l, color: AppColors.textSecondary),
                      ]),
                    ),
                  _howItWorks(c),
                  const SizedBox(height: AppSpacing.md),
                  const BuddyNote(
                    icon: Icons.shield_outlined,
                    color: AppColors.success,
                    text: 'Stay safe: chat inside the app first, meet in public places, and never share money or OTPs.',
                  ),
                ],
              ),
            ),
    );
  }
}
