import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/buddy/trust_badges.dart';
import '../../widgets/ui/app_ui.dart';
import 'buddy_links.dart';
import 'buddy_profile_screen.dart';

/// One-to-one chat with an accepted buddy. Polls every 4 s while open.
class BuddyChatScreen extends StatefulWidget {
  final BuddyConnection connection;

  /// Shared highlights for icebreakers; fetched from the profile if null.
  final List<String>? highlights;

  const BuddyChatScreen({super.key, required this.connection, this.highlights});

  /// Connection id of the chat currently open (null when none), so foreground
  /// message pushes for that chat are not shown as notifications.
  static final ValueNotifier<int?> openConnectionId = ValueNotifier<int?>(null);
  static final List<int> _openStack = [];

  static void _setOpen(int id, bool open) {
    if (open) {
      _openStack.add(id);
    } else {
      _openStack.remove(id);
    }
    openConnectionId.value = _openStack.isEmpty ? null : _openStack.last;
  }

  @override
  State<BuddyChatScreen> createState() => _BuddyChatScreenState();
}

class _BuddyChatScreenState extends State<BuddyChatScreen> with WidgetsBindingObserver {
  late final BuddyChatPoller _poller;
  late final BuddyService _service;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _showSafety = false;
  List<String> _highlights = const [];
  int _lastCount = 0;
  bool _icebreakerSent = false;

  BuddyConnection get _conn => widget.connection;
  BuddyCandidate get _other => _conn.other;
  String get _safetyKey => 'buddy_chat_safety_seen_${_conn.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BuddyChatScreen._setOpen(_conn.id, true);
    final service = _service = context.read<BuddyService>();
    _poller = service.chatPoller(_conn.id)..addListener(_onMessages);
    _poller.start();
    service.markRead(_conn.id);
    _highlights = widget.highlights ?? const [];
    if (widget.highlights == null) _loadHighlights(service);
    _initSafety();
    _input.addListener(() => setState(() {}));
  }

  Future<void> _initSafety() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_safetyKey) == true) return;
      await prefs.setBool(_safetyKey, true);
      if (mounted) setState(() => _showSafety = true);
    } catch (_) {
      if (mounted) setState(() => _showSafety = true);
    }
  }

  Future<void> _loadHighlights(BuddyService service) async {
    try {
      final c = await service.user(_other.userId);
      if (mounted && c != null) setState(() => _highlights = c.highlights);
    } catch (_) {}
  }

  void _onMessages() {
    final n = _poller.messages.length;
    if (n != _lastCount) {
      _lastCount = n;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
    if (mounted) setState(() {});
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poller.start();
      _poller.refresh();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _poller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BuddyChatScreen._setOpen(_conn.id, false);
    _poller.removeListener(_onMessages);
    final sentSomething = _poller.messages.any((m) => m.mine && !m.failed);
    _poller.dispose();
    // Update the list preview ("You: ...") and the unread badge.
    if (sentSomething || _poller.closed) {
      _service.loadConnections(fresh: true).catchError((_) => _service.connections);
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty || _poller.closed) return;
    if (text != null) {
      // Icebreaker chips: one tap sends once, even if tapped again before the
      // row disappears.
      if (_icebreakerSent) return;
      _icebreakerSent = true;
    } else {
      _input.clear();
    }
    final result = await _poller.send(body);
    if (!mounted) return;
    switch (result) {
      case BuddySendResult.sent:
        break;
      case BuddySendResult.rateLimited:
        // Nothing is lost: typed text goes back into the box (unless they've
        // already started typing something else), icebreakers can be tapped again.
        if (text == null) {
          if (_input.text.trim().isEmpty) {
            _input.text = body;
            _input.selection = TextSelection.collapsed(offset: body.length);
          }
        } else {
          setState(() => _icebreakerSent = false);
        }
        showAppSnack(context, 'Slow down a little. You can send this again in a minute.');
      case BuddySendResult.failed:
        if (!_poller.closed) showAppSnack(context, 'Message not sent. Tap it to retry.', error: true);
    }
  }

  Future<void> _retry(BuddyMessage m) async {
    final result = await _poller.retry(m);
    if (!mounted) return;
    if (result == BuddySendResult.rateLimited) {
      showAppSnack(context, 'Slow down a little. You can send this again in a minute.');
    }
  }

  List<String> get _icebreakers {
    final name = _other.firstName;
    final out = <String>[];
    final hs = _highlights.join(' ').toLowerCase();
    if (hs.contains('agree')) out.add('We seem to agree on a lot. Which question mattered most to you?');
    if (hs.contains('moon') || hs.contains('nakshatra') || hs.contains('gana')) {
      out.add('Apparently our Moons get along. Do you follow your horoscope?');
    }
    out.addAll(switch (_conn.intent) {
      BuddyIntent.lifePartner => [
          'Namaste $name! What does a happy Sunday look like for you?',
          'What matters most to you in a family?'
        ],
      BuddyIntent.business => [
          'Hi $name! What are you building right now?',
          'What kind of partner are you looking for?'
        ],
      BuddyIntent.travel => ["Hi $name! What's the next place on your travel list?", 'Mountains or beaches?'],
      BuddyIntent.spiritual => [
          'Jai Shri Krishna $name! Which temple is closest to your heart?',
          'Do you have a favourite bhajan?'
        ],
      _ => ['Hi $name! How is your week going?', 'What do you love doing on weekends?'],
    });
    return out.take(4).toList();
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }

  void _openProfile() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BuddyProfileScreen(userId: _other.userId, initial: _other),
    ));
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: _openProfile,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            BuddyAvatar(name: _other.displayName, imageUrl: _other.photoUrl, size: 38, seed: _other.userId),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                BuddyNameWithBadge(text: _other.displayName, verified: _other.verified, style: AppText.subtitle),
                Text(
                  [
                    BuddyIntent.label(_conn.intent),
                    if (_other.score > 0) '${_other.score}% match',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        if (BuddyLinks.hasTempleTrip)
          IconButton(
            tooltip: 'Plan a temple trip',
            icon: const Icon(Icons.temple_hindu_rounded, color: AppColors.primary),
            onPressed: () => BuddyLinks.openTempleTrip(context, _other.userId),
          ),
        BuddyPersonMenu(
          userId: _other.userId,
          name: _other.firstName,
          onViewProfile: _openProfile,
          onRemoved: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _safetyBanner() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
        child: BuddyNote(
          icon: Icons.shield_rounded,
          color: AppColors.success,
          text: 'Meet in public places, never share money or OTPs. If anything feels off, use ⋮ to report.',
          trailing: InkWell(
            onTap: () => setState(() => _showSafety = false),
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary, semanticLabel: 'Dismiss'),
            ),
          ),
        ),
      );

  Widget _bubble(BuddyMessage m, {required bool showTime}) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    final time = DateFormat('h:mm a').format(m.createdAt);
    if (m.mine) {
      final bubble = Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
        decoration: BoxDecoration(
          color: m.failed ? AppColors.danger : AppColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(m.body, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (m.failed)
              const Flexible(
                child: Text('Not sent · tap to retry', style: TextStyle(color: Colors.white, fontSize: 11)),
              )
            else ...[
              if (showTime) Text(time, style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11)),
              const SizedBox(width: 4),
              Icon(m.pending ? Icons.schedule_rounded : Icons.done_rounded, size: 14, color: AppColors.textOnDarkMuted),
            ],
          ]),
        ]),
      );
      return Align(
        alignment: Alignment.centerRight,
        child: m.failed ? GestureDetector(onTap: () => _retry(m), child: bubble) : bubble,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(m.body, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.4)),
          if (showTime) ...[
            const SizedBox(height: 3),
            Text(time, style: AppText.caption.copyWith(fontSize: 11)),
          ],
        ]),
      ),
    );
  }

  Widget _icebreakerRow() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        itemCount: _icebreakers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = _icebreakers[i];
          return ActionChip(
            avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            onPressed: () => _send(t),
          );
        },
      ),
    );
  }

  Widget _emptyState() => ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.lg),
          Center(
              child: BuddyAvatar(
                  name: _other.displayName, imageUrl: _other.photoUrl, size: 84, seed: _other.userId, ring: true)),
          const SizedBox(height: AppSpacing.md),
          Text('You and ${_other.firstName} are buddies', textAlign: TextAlign.center, style: AppText.title),
          const SizedBox(height: 6),
          const Text('Break the ice with a kind hello. Pick an idea below or write your own.',
              textAlign: TextAlign.center, style: AppText.body),
          if (_highlights.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(child: BuddyHighlights(highlights: _highlights)),
          ],
        ],
      );

  Widget _closedBanner() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.sm),
          child: BuddyNote(
            icon: Icons.info_outline_rounded,
            color: AppColors.warning,
            text: _poller.error ?? 'This chat is no longer available.',
          ),
        ),
      );

  Widget _composer() {
    final canSend = _input.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration:
          const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.divider))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Message ${_other.firstName}…',
                  counterText: '',
                  fillColor: AppColors.surfaceMuted,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      borderSide: const BorderSide(color: AppColors.primary)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: 'Send',
              child: IconButton.filled(
                tooltip: 'Send',
                onPressed: canSend ? () => _send() : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.border,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _poller.messages;
    final iHaveSpoken = msgs.any((m) => m.mine);
    Widget body;
    if (_poller.loading && msgs.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_poller.closed && msgs.isEmpty) {
      body = Center(
        child: AppStateView(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Chat unavailable',
          message: _poller.error,
          actionLabel: 'Back',
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    } else if (_poller.error != null && msgs.isEmpty) {
      body = Center(child: AppStateView.error(message: _poller.error, onAction: _poller.refresh));
    } else if (msgs.isEmpty) {
      body = _emptyState();
    } else {
      // Reversed list: index 0 is the newest message at the bottom.
      body = ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
        itemCount: msgs.length,
        itemBuilder: (context, i) {
          final idx = msgs.length - 1 - i;
          final m = msgs[idx];
          final prev = idx > 0 ? msgs[idx - 1] : null;
          final next = idx < msgs.length - 1 ? msgs[idx + 1] : null;
          final showDate = prev == null || _dayLabel(prev.createdAt) != _dayLabel(m.createdAt);
          final lastOfGroup =
              next == null || next.mine != m.mine || next.createdAt.difference(m.createdAt).inMinutes > 5;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showDate)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child:
                        Text(_dayLabel(m.createdAt), style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(top: 2, bottom: lastOfGroup ? 8 : 2),
              child: _bubble(m, showTime: lastOfGroup),
            ),
          ]);
        },
      );
    }

    return Scaffold(
      appBar: _appBar(),
      body: Column(children: [
        if (_showSafety) _safetyBanner(),
        Expanded(child: body),
        if (_poller.closed && msgs.isNotEmpty) _closedBanner(),
        if (!iHaveSpoken && !_icebreakerSent && !_poller.loading && !_poller.closed) ...[
          _icebreakerRow(),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (!_poller.closed) _composer(),
      ]),
    );
  }
}
