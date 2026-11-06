import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../../services/meetup_service.dart';
import '../../widgets/rewards/coin_toast.dart';
import '../../widgets/ui/app_ui.dart';
import 'meetup_widgets.dart';

/// One meetup: when/where, RSVP, check-in (GPS or host code), who's going and,
/// after checking in, "People you met". Deep link: `MeetupDetailScreen(meetupId: id)`.
class MeetupDetailScreen extends StatefulWidget {
  final int meetupId;

  /// Shown straight away (e.g. the list card) while the full detail loads.
  final Meetup? initial;
  const MeetupDetailScreen({super.key, required this.meetupId, this.initial});

  static Route<void> route(int meetupId, {Meetup? initial}) =>
      MaterialPageRoute(builder: (_) => MeetupDetailScreen(meetupId: meetupId, initial: initial));

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  Meetup? _m;
  bool _detailLoaded = false;
  String? _error;
  bool _busy = false;
  final Set<int> _requested = {};
  final Set<int> _connecting = {};
  Timer? _ticker;

  MeetupService get _svc => context.read<MeetupService>();

  @override
  void initState() {
    super.initState();
    _m = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // Re-evaluate the check-in window while the screen stays open.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final m = await _svc.detail(widget.meetupId);
      if (!mounted) return;
      setState(() {
        _m = m;
        _detailLoaded = true;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 404 ? 'This meetup is no longer available.' : MeetupService.errorText(e));
    } catch (e) {
      if (mounted) setState(() => _error = MeetupService.errorText(e));
    }
  }

  void _snack(String text, {bool error = false}) {
    if (mounted) showAppSnack(context, text, error: error);
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } on MeetupLocationException catch (e) {
      _snack(e.message, error: true);
    } on BackendException catch (e) {
      final code = _svc.lastErrorCode;
      _snack(MeetupService.errorText(e), error: true);
      if (code == 'FULL' || code == 'STARTED' || e.statusCode == 404) unawaited(_load());
    } catch (e) {
      _snack(MeetupService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rsvp() => _run(() async {
        final m = await _svc.rsvp(widget.meetupId);
        if (!mounted) return;
        setState(() => _m = m);
        _snack("You're going! We'll remind you before it starts.");
      });

  Future<void> _cancelRsvp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel your RSVP?'),
        content: const Text('Your spot will go to someone else.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my spot')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel RSVP')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final m = await _svc.cancelRsvp(widget.meetupId);
      if (!mounted) return;
      if (m != null) setState(() => _m = m);
      _snack('RSVP cancelled');
    });
  }

  Future<void> _cancelEvent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this meetup?'),
        content: const Text('Everyone who RSVPed will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel meetup')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final m = await _svc.cancelEvent(widget.meetupId);
      if (mounted) setState(() => _m = m);
    });
  }

  void _afterCheckin(MeetupCheckin r) {
    if (!mounted) return;
    if (r.meetup != null) setState(() => _m = r.meetup);
    final shown = showCoinsFromResponse(context, r.raw,
        reason: 'Satsang check-in', rewardReason: 'meetup_checkin', ref: 'event:${widget.meetupId}');
    if (shown == 0) _snack("You're checked in. Enjoy the satsang!");
  }

  Future<void> _checkInHere() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? fallbackReason;
    try {
      _afterCheckin(await _svc.checkInHere(widget.meetupId));
    } on MeetupLocationException catch (e) {
      fallbackReason = e.message;
    } on BackendException catch (e) {
      final code = _svc.lastErrorCode;
      if (code == 'TOO_FAR') {
        fallbackReason = '${e.message}. Indoors? Ask the host for the check-in code.';
      } else {
        _snack(MeetupService.errorText(e), error: true);
      }
    } catch (e) {
      _snack(MeetupService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (fallbackReason != null && mounted) await _enterCode(reason: fallbackReason);
  }

  Future<void> _enterCode({String? reason}) async {
    final code = await showDialog<String>(context: context, builder: (_) => _CodeDialog(reason: reason));
    if (code == null || !mounted) return;
    await _run(() async => _afterCheckin(await _svc.checkInWithCode(widget.meetupId, code)));
  }

  Future<void> _openMaps(Meetup m) async {
    final url = m.mapsUrl ??
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([m.venueName, m.address, m.city].whereType<String>().join(', '))}';
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) _snack('Could not open maps. The address is: ${m.address}', error: true);
  }

  Future<void> _connect(MeetupPerson p) async {
    final id = p.userId;
    if (id == null || _connecting.contains(id)) return;
    setState(() => _connecting.add(id));
    try {
      await _svc.connect(id);
      if (!mounted) return;
      setState(() => _requested.add(id));
      _snack('Request sent to ${p.displayName}');
      try {
        final buddy = context.read<BuddyService>();
        unawaited(buddy.loadConnections(fresh: true).then((_) {}, onError: (_) {}));
      } on ProviderNotFoundException {
        // Buddy feature not mounted (tests): nothing to refresh.
      }
    } on BackendException catch (e) {
      final code = _svc.lastErrorCode;
      _snack(
          switch (code) {
            'NO_PROFILE' || 'NO_KUNDLI' => 'Set up your buddy profile first to connect with people.',
            'PROFILE_PAUSED' => 'Your buddy profile is paused. Resume it to connect.',
            'INTENT_MISMATCH' => '${p.displayName} is not looking for buddies right now.',
            _ => MeetupService.errorText(e),
          },
          error: true);
    } catch (e) {
      _snack(MeetupService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _connecting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Meetup')),
      body: m == null
          ? (_error != null
              ? Center(child: SingleChildScrollView(child: AppStateView.error(message: _error, onAction: _load)))
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _content(m)),
      bottomNavigationBar: m == null ? null : _actionBar(m),
    );
  }

  Widget _content(Meetup m) {
    final color = MeetupTypeStyle.color(m.type);
    final status = meetupStatusBadge(m);
    final authed = context.watch<BackendService>().isAuthenticated;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
      children: [
        if (_error != null && _detailLoaded == false)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _Note(icon: Icons.wifi_off_rounded, color: AppColors.danger, text: _error!),
          ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppBadge(label: MeetupType.label(m.type), color: color, icon: MeetupTypeStyle.icon(m.type)),
          if (m.womenOnly) const AppBadge(label: 'Women only', color: AppColors.love, icon: Icons.female_rounded),
          if (status != null) status,
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(m.title, style: AppText.headline),
        const SizedBox(height: 6),
        MeetupHostLine(meetup: m),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _InfoRow(icon: Icons.calendar_month_rounded, color: color, title: meetupWhen(m), subtitle: _timingNote(m)),
            const Divider(height: 1),
            _InfoRow(
              icon: Icons.place_rounded,
              color: color,
              title: m.venueName,
              subtitle: [m.address, if (m.city != null && !m.address.contains(m.city!)) m.city!].where((s) => s.isNotEmpty).join(', '),
              trailing: TextButton.icon(
                onPressed: () => _openMaps(m),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open in Maps'),
              ),
            ),
            const Divider(height: 1),
            _CapacityRow(meetup: m, color: color),
          ]),
        ),
        if (m.isHost && m.checkinCode != null) ...[
          const SizedBox(height: AppSpacing.md),
          _HostPanel(meetup: m, onCancel: m.isCancelled || m.isEnded ? null : _cancelEvent),
        ],
        if (m.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text('About', style: AppText.title),
          const SizedBox(height: 6),
          Text(m.description, style: AppText.body),
        ],
        const SizedBox(height: AppSpacing.lg),
        const Text("Who's going", style: AppText.title),
        const SizedBox(height: AppSpacing.xs),
        _attendees(m, authed),
        if (m.peopleYouMet != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text('People you met', style: AppText.title),
          const SizedBox(height: 2),
          const Text('Everyone here checked in at the venue. Send a buddy request to stay in touch.', style: AppText.caption),
          const SizedBox(height: AppSpacing.xs),
          _peopleYouMet(m.peopleYouMet!),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _Note(
          icon: Icons.shield_outlined,
          color: AppColors.info,
          text: 'Meet at the venue and stay with the group. Keep your phone number and home address private until '
              'you trust someone, and report anyone who makes you uncomfortable.',
        ),
      ],
    );
  }

  String? _timingNote(Meetup m) {
    if (m.isCancelled) return 'This meetup was cancelled';
    if (m.isEnded) return 'This meetup has ended';
    if (m.phase == 'live') return 'Happening now';
    if (m.isGoing && !m.isCheckedIn) return 'Check-in opens 30 min before the start';
    return null;
  }

  Widget _attendees(Meetup m, bool authed) {
    final list = m.attendees;
    if (list == null) {
      return Text(
        !authed
            ? 'Log in and RSVP to see who is going.'
            : m.goingCount == 0
                ? 'Be the first to RSVP.'
                : 'RSVP to see who is going. Only first names and verified badges are shown.',
        style: AppText.body,
      );
    }
    final others = m.goingCount - (m.isGoing ? 1 : 0) - list.length;
    if (list.isEmpty) return Text(m.isGoing ? "You're the first one going. Invite a friend!" : 'No one yet.', style: AppText.body);
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
      for (final p in list)
        SizedBox(
          width: 64,
          child: Column(children: [
            MeetupInitials(person: p, size: 44),
            const SizedBox(height: 4),
            Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppText.caption),
          ]),
        ),
      if (others > 0)
        SizedBox(
          width: 64,
          child: Column(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
              child: Text('+$others', style: AppText.bodyStrong),
            ),
            const SizedBox(height: 4),
            const Text('more', style: AppText.caption),
          ]),
        ),
    ]);
  }

  Widget _peopleYouMet(List<MeetupPerson> people) {
    if (people.isEmpty) {
      return const Text('No one else has checked in yet. Pull down to refresh.', style: AppText.body);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < people.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
            child: Row(children: [
              MeetupInitials(person: people[i]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Row(children: [
                  Flexible(child: Text(people[i].displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong)),
                  if (people[i].verified) ...[const SizedBox(width: 4), const MeetupVerifiedTick()],
                ]),
              ),
              if (people[i].canConnect && people[i].userId != null)
                _requested.contains(people[i].userId)
                    ? const AppBadge(label: 'Requested', color: AppColors.success, icon: Icons.check_rounded)
                    : AppButton(
                        label: 'Connect',
                        expand: false,
                        height: 36,
                        variant: AppButtonVariant.secondary,
                        loading: _connecting.contains(people[i].userId),
                        onPressed: () => _connect(people[i]),
                      ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget? _actionBar(Meetup m) {
    final authed = context.watch<BackendService>().isAuthenticated;
    final now = _svc.clock();
    Widget child;
    if (!authed) {
      child = AppButton(label: 'Log in to RSVP', icon: Icons.login_rounded, onPressed: () => Navigator.pushNamed(context, '/login'));
    } else if (m.isCancelled) {
      child = const _BarNote(icon: Icons.event_busy_rounded, color: AppColors.danger, text: 'This meetup was cancelled');
    } else if (m.isPending) {
      child = const _BarNote(
          icon: Icons.hourglass_top_rounded, color: AppColors.warning, text: 'Waiting for our team to approve this meetup');
    } else if (m.status == 'rejected') {
      child = const _BarNote(icon: Icons.block_rounded, color: AppColors.danger, text: 'This meetup was not approved');
    } else if (m.isCheckedIn) {
      child = _BarNote(
          icon: Icons.verified_rounded,
          color: AppColors.success,
          text: m.isEnded ? 'You attended this meetup' : "You're checked in · +${m.coinsForCheckin} coins");
    } else if (m.isEnded) {
      child = const _BarNote(icon: Icons.history_rounded, color: AppColors.textSecondary, text: 'This meetup has ended');
    } else if (m.isGoing && m.checkinWindowOpen(now)) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        AppButton(
          label: 'Check in at venue · +${m.coinsForCheckin} coins',
          icon: Icons.where_to_vote_rounded,
          loading: _busy,
          onPressed: _checkInHere,
        ),
        TextButton(onPressed: _busy ? null : () => _enterCode(), child: const Text('Enter host code instead')),
      ]);
    } else if (m.isGoing) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        const _BarNote(icon: Icons.event_available_rounded, color: AppColors.success, text: "You're going"),
        TextButton(onPressed: _busy ? null : _cancelRsvp, child: const Text('Cancel RSVP')),
      ]);
    } else if (m.hasStarted) {
      child = const _BarNote(icon: Icons.schedule_rounded, color: AppColors.textSecondary, text: 'RSVPs closed: it has started');
    } else if (m.isFull) {
      child = const _BarNote(icon: Icons.groups_rounded, color: AppColors.textSecondary, text: 'This meetup is full');
    } else {
      child = AppButton(
        label: "RSVP · I'm going",
        icon: Icons.event_available_rounded,
        loading: _busy,
        onPressed: _rsvp,
      );
    }
    return Material(
      color: AppColors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _InfoRow({required this.icon, required this.color, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.bodyStrong),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ]),
          ),
        ]),
        if (trailing != null) Padding(padding: const EdgeInsets.only(left: 40), child: trailing!),
      ]),
    );
  }
}

class _CapacityRow extends StatelessWidget {
  final Meetup meetup;
  final Color color;
  const _CapacityRow({required this.meetup, required this.color});

  @override
  Widget build(BuildContext context) {
    final m = meetup;
    final frac = m.capacity <= 0 ? 0.0 : (m.goingCount / m.capacity).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.groups_rounded, size: 20, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${m.goingCount} going · ${m.isFull ? 'Full' : '${m.spotsLeft} of ${m.capacity} spots left'}',
                style: AppText.bodyStrong),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: AppColors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation(m.isFull ? AppColors.textTertiary : color),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HostPanel extends StatelessWidget {
  final Meetup meetup;
  final VoidCallback? onCancel;
  const _HostPanel({required this.meetup, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final code = meetup.checkinCode!;
    final pretty = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
    return AppCard(
      gradient: AppColors.cosmicGradient,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("You're hosting", style: TextStyle(color: AppColors.textOnDarkMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(pretty,
                  semanticsLabel: 'Check-in code $code',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 4)),
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              showAppSnack(context, 'Code copied');
            },
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
          ),
        ]),
        Text(
          meetup.isPending
              ? 'Check-in code. Your meetup is waiting for approval; we will notify you.'
              : 'Check-in code. Share it at the venue with attendees whose GPS does not work indoors. '
                  '${meetup.checkedInCount} checked in so far.',
          style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.4),
        ),
        if (onCancel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Cancel this meetup'),
          ),
        ],
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Note({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppText.caption.copyWith(color: AppColors.textSecondary))),
      ]),
    );
  }
}

class _BarNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _BarNote({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppText.bodyStrong.copyWith(color: color))),
      ]),
    );
  }
}

class _CodeDialog extends StatefulWidget {
  final String? reason;
  const _CodeDialog({this.reason});

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^\d{6}$').hasMatch(_c.text);
    return AlertDialog(
      title: const Text('Enter host code'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.reason != null) ...[
            Text(widget.reason!, style: AppText.body),
            const SizedBox(height: AppSpacing.sm),
          ],
          const Text('Ask the host for the 6-digit check-in code.', style: AppText.caption),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            key: const Key('meetup-code-field'),
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => valid ? Navigator.pop(context, _c.text) : null,
            decoration: const InputDecoration(hintText: '6-digit code', counterText: ''),
            style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: valid ? () => Navigator.pop(context, _c.text) : null, child: const Text('Check in')),
      ],
    );
  }
}
