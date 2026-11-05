import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';

/// Asks how you'd like to connect (intent + optional note) and sends the
/// request. Returns the connection (status `accepted` if they had already
/// asked you), or null if dismissed.
Future<BuddyConnectionRef?> showBuddyConnectSheet(BuildContext context, BuddyCandidate candidate,
    {String? preferredIntent}) async {
  final service = context.read<BuddyService>();
  final ref = await showAppSheet<BuddyConnectionRef>(
    context,
    builder: (_) => _ConnectSheet(service: service, candidate: candidate, preferredIntent: preferredIntent),
  );
  if (ref != null && context.mounted) {
    showAppSnack(
      context,
      ref.isAccepted
          ? 'You and ${candidate.firstName} are now buddies. Say namaste!'
          : 'Request sent to ${candidate.firstName}',
    );
  }
  return ref;
}

class _ConnectSheet extends StatefulWidget {
  final BuddyService service;
  final BuddyCandidate candidate;
  final String? preferredIntent;
  const _ConnectSheet({required this.service, required this.candidate, this.preferredIntent});

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  late final List<String> _options;
  late String _intent;
  final _message = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final mine = widget.service.profile?.intents ?? const <String>[];
    final theirs = widget.candidate.intents;
    final shared = theirs.where(mine.contains).toList();
    _options = shared.isNotEmpty ? shared : (theirs.isNotEmpty ? theirs : (mine.isNotEmpty ? mine : BuddyIntent.all));
    final p = widget.preferredIntent;
    _intent = p != null && _options.contains(p) ? p : _options.first;
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _suggestion => switch (_intent) {
        BuddyIntent.lifePartner =>
          'Namaste ${widget.candidate.firstName}, our charts seem to get along. Would love to know you better.',
        BuddyIntent.business =>
          'Hi ${widget.candidate.firstName}, I think we could build something good together. Open to a chat?',
        BuddyIntent.travel => 'Hi ${widget.candidate.firstName}, fancy planning a trip or yatra together sometime?',
        BuddyIntent.spiritual =>
          'Jai Shri Krishna ${widget.candidate.firstName}! Would you like to be satsang buddies?',
        _ => 'Hi ${widget.candidate.firstName}, looks like we think alike. Say hello?',
      };

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ref = await widget.service.connect(widget.candidate.userId, _intent, message: _message.text);
      if (!mounted) return;
      Navigator.pop(context, ref ?? const BuddyConnectionRef(id: 0, status: 'pending', direction: 'outgoing'));
    } catch (e) {
      if (!mounted) return;
      final limited = e is BuddyRateLimitedException;
      setState(() {
        _sending = false;
        // The note they wrote stays in the box.
        _error = limited
            ? "Slow down a little. You've sent a lot of requests today, please try again tomorrow."
            : BuddyService.errorText(e);
      });
      if (limited) showAppSnack(context, 'Slow down a little. Try again later.');
      if (e is BuddyBannedException && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            BuddyAvatar(name: c.displayName, imageUrl: c.photoUrl, size: 48, seed: c.userId),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Connect with ${c.firstName}', style: AppText.title),
                Text('${c.score}% · ${buddyScoreLabel(c.score)}', style: AppText.caption),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          const Text('Connect as', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final i in _options)
              AppFilterChip(
                label: BuddyIntent.label(i),
                icon: BuddyIntentStyle.icon(i),
                selected: _intent == i,
                onTap: () => setState(() => _intent = i),
              ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          const Text('Add a note (optional)', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _message,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: _suggestion, hintMaxLines: 3),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _message.text = _suggestion),
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Use this note'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const BuddyNote(
            icon: Icons.lock_outline_rounded,
            text: 'They see your name, score and highlights. Your birth details, chart and answers stay private. '
                'Chat opens only if they accept.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: AppText.body.copyWith(color: AppColors.danger)),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            label: 'Send request',
            icon: Icons.send_rounded,
            loading: _sending,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
