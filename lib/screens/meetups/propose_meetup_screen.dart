import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/meetup_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'meetup_widgets.dart';

/// Verified members propose a meetup (reviewed by our team before it is
/// public). Others see why they can't host yet ("Get verified to host").
class ProposeMeetupScreen extends StatefulWidget {
  const ProposeMeetupScreen({super.key});

  /// Opens the verification flow (owned by the trust feature). Null hides the button.
  static WidgetBuilder? verifyBuilder;

  @override
  State<ProposeMeetupScreen> createState() => _ProposeMeetupScreenState();
}

class _ProposeMeetupScreenState extends State<ProposeMeetupScreen> {
  ProposeStatus? _status;
  String? _error;
  bool _submitted = false;

  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _venue = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  String _type = MeetupType.satsang;
  bool _useTemple = true;
  List<MeetupTemple>? _temples;
  String? _templeId;
  MeetupFix? _venueFix;
  bool _locating = false;
  DateTime? _day;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 30);
  int _durationMin = 90;
  double _capacity = 20;
  bool _womenOnly = false;
  bool _saving = false;

  MeetupService get _svc => context.read<MeetupService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _venue, _address, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final s = await _svc.proposeStatus();
      if (!mounted) return;
      setState(() => _status = s);
      if (s.canPropose) {
        try {
          final t = await _svc.temples();
          if (mounted) setState(() => _temples = t);
        } catch (_) {
          if (mounted) setState(() => _temples = const []);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = MeetupService.errorText(e));
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? now.add(const Duration(days: 2)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 89)),
    );
    if (d != null && mounted) setState(() => _day = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null && mounted) setState(() => _time = t);
  }

  Future<void> _locateVenue() async {
    setState(() => _locating = true);
    try {
      final fix = await _svc.locate(ask: true, precise: true);
      if (mounted) setState(() => _venueFix = fix);
    } catch (e) {
      if (mounted) showAppSnack(context, MeetupService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_day == null) return showAppSnack(context, 'Pick a date', error: true);
    if (_useTemple && _templeId == null) return showAppSnack(context, 'Pick the temple', error: true);
    if (!_useTemple && _venueFix == null) {
      return showAppSnack(context, 'Set the venue location (stand at the venue and tap the button)', error: true);
    }
    final start = DateTime(_day!.year, _day!.month, _day!.day, _time.hour, _time.minute);
    final draft = MeetupDraft(
      title: _title.text,
      type: _type,
      description: _desc.text,
      templeId: _useTemple ? _templeId : null,
      venueName: _useTemple ? '' : _venue.text,
      address: _useTemple ? '' : _address.text,
      city: _useTemple ? '' : _city.text,
      lat: _useTemple ? null : _venueFix!.lat,
      lng: _useTemple ? null : _venueFix!.lng,
      startsAt: start,
      endsAt: start.add(Duration(minutes: _durationMin)),
      capacity: _capacity.round(),
      womenOnly: _womenOnly,
    );
    setState(() => _saving = true);
    try {
      await _svc.propose(draft);
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) showAppSnack(context, MeetupService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<BackendService>().isAuthenticated;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Host a satsang')),
      body: _body(authed),
    );
  }

  Widget _gate(IconData icon, String title, String message, {String? action, VoidCallback? onAction, Color color = AppColors.primary}) {
    return Center(
      child: SingleChildScrollView(
        child: AppStateView(icon: icon, title: title, message: message, actionLabel: action, onAction: onAction, color: color),
      ),
    );
  }

  Widget _body(bool authed) {
    if (!authed) {
      return _gate(Icons.lock_person_rounded, 'Log in to host', 'Create a free account to propose a satsang.',
          action: 'Log in', onAction: () => Navigator.pushNamed(context, '/login'));
    }
    if (_submitted) {
      return _gate(Icons.mark_email_read_rounded, 'Sent for review',
          'Our team checks every meetup before it goes live. We will notify you when it is approved.',
          action: 'Done', onAction: () => Navigator.of(context).pop(true), color: AppColors.success);
    }
    final s = _status;
    if (s == null) {
      if (_error != null) return Center(child: SingleChildScrollView(child: AppStateView.error(message: _error, onAction: _load)));
      return const Center(child: CircularProgressIndicator());
    }
    if (!s.canPropose) {
      final verify = ProposeMeetupScreen.verifyBuilder;
      return switch (s.reason) {
        'NOT_VERIFIED' => _gate(
            Icons.verified_user_rounded,
            'Get verified to host',
            'To keep meetups safe, only verified members can host. Verification takes a quick selfie check. '
                'You can still join any meetup.',
            action: verify == null ? null : 'Get verified',
            onAction: verify == null
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: verify));
                    _load();
                  },
            color: AppColors.info),
        'RATE_LIMITED' => _gate(Icons.hourglass_top_rounded, 'That is plenty for this week',
            'You can propose up to 2 meetups a week. Please try again in a few days.', color: AppColors.warning),
        'UNDER_18' => _gate(Icons.child_care_rounded, 'Meetups are for adults (18+)',
            'Hosting and joining meetups is open to people aged 18 and over.', color: AppColors.warning),
        'NO_BIRTH_DETAILS' => _gate(Icons.auto_awesome_rounded, 'Add your birth details first',
            'Meetups are for people aged 18 and over, so we need your birth date.',
            action: 'Add birth details', onAction: () => Navigator.pushNamed(context, '/birth-details')),
        'BANNED' => _gate(Icons.gpp_maybe_outlined, 'Hosting is not available',
            'Your account cannot host meetups after a safety review.', color: AppColors.danger),
        _ => _gate(Icons.lock_person_rounded, 'Log in to host', 'Create a free account to propose a satsang.',
            action: 'Log in', onAction: () => Navigator.pushNamed(context, '/login')),
      };
    }
    return _formView(s);
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint);

  String? _len(String? v, int min, int max, String what) {
    final n = (v ?? '').trim().length;
    if (n < min) return 'Add the $what';
    if (n > max) return 'At most $max characters';
    return null;
  }

  Widget _formView(ProposeStatus s) {
    final temples = _temples;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        children: [
          Text('Hold it at a temple or another public place. Our team reviews it before it goes live. '
              '${s.remainingThisWeek} of 2 proposals left this week.', style: AppText.body),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _title,
            maxLength: 80,
            decoration: _dec('Title', hint: 'e.g. Hanuman Chalisa satsang'),
            validator: (v) => _len(v, 4, 80, 'title (at least 4 characters)'),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Type', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            for (final t in MeetupType.all)
              AppFilterChip(
                label: MeetupType.label(t),
                icon: MeetupTypeStyle.icon(t),
                selected: _type == t,
                onTap: () => setState(() => _type = t),
              ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          const Text('Venue', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            AppFilterChip(label: 'Famous temple', icon: Icons.temple_hindu_rounded, selected: _useTemple, onTap: () => setState(() => _useTemple = true)),
            AppFilterChip(label: 'Other public place', icon: Icons.place_rounded, selected: !_useTemple, onTap: () => setState(() => _useTemple = false)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          if (_useTemple)
            temples == null
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    initialValue: _templeId,
                    isExpanded: true,
                    decoration: _dec('Temple'),
                    items: [
                      for (final t in temples)
                        DropdownMenuItem(value: t.id, child: Text('${t.name}, ${t.city}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _templeId = v),
                  )
          else ...[
            TextFormField(
              controller: _venue,
              maxLength: 120,
              decoration: _dec('Venue name', hint: 'e.g. Prachin Hanuman Mandir'),
              validator: (v) => _useTemple ? null : _len(v, 2, 120, 'venue name'),
            ),
            TextFormField(
              controller: _address,
              maxLength: 300,
              decoration: _dec('Public address'),
              validator: (v) => _useTemple ? null : _len(v, 5, 300, 'address'),
            ),
            TextFormField(
              controller: _city,
              maxLength: 80,
              decoration: _dec('City'),
              validator: (v) => _useTemple ? null : _len(v, 2, 80, 'city'),
            ),
            AppButton(
              label: _venueFix == null ? "I'm at the venue: set its location" : 'Venue location set',
              icon: _venueFix == null ? Icons.my_location_rounded : Icons.check_circle_rounded,
              variant: _venueFix == null ? AppButtonVariant.outline : AppButtonVariant.secondary,
              loading: _locating,
              height: 46,
              onPressed: _locateVenue,
            ),
            const SizedBox(height: 4),
            const Text('Used only to check attendees in at the venue. Never shown to anyone.', style: AppText.caption),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Text('When', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            AppButton(
              label: _day == null ? 'Pick a date' : '${_day!.day}/${_day!.month}/${_day!.year}',
              icon: Icons.calendar_month_rounded,
              variant: AppButtonVariant.outline,
              expand: false,
              height: 44,
              onPressed: _pickDay,
            ),
            AppButton(
              label: meetupTime(DateTime(2000, 1, 1, _time.hour, _time.minute)),
              icon: Icons.schedule_rounded,
              variant: AppButtonVariant.outline,
              expand: false,
              height: 44,
              onPressed: _pickTime,
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            for (final d in const [60, 90, 120, 180])
              AppFilterChip(
                label: d % 60 == 0 ? '${d ~/ 60} h' : '${d / 60} h',
                selected: _durationMin == d,
                onTap: () => setState(() => _durationMin = d),
              ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Text('Group size: up to ${_capacity.round()} people', style: AppText.bodyStrong),
          Slider(
            value: _capacity,
            min: 5,
            max: 50,
            divisions: 45,
            label: '${_capacity.round()}',
            onChanged: (v) => setState(() => _capacity = v),
          ),
          if (s.canHostWomenOnly)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Women only', style: AppText.bodyStrong),
              subtitle: const Text('Only women can see and join', style: AppText.caption),
              value: _womenOnly,
              onChanged: (v) => setState(() => _womenOnly = v),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _desc,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            decoration: _dec('What will happen?', hint: 'What to bring, dress code, where to meet inside...'),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Send for review', icon: Icons.send_rounded, loading: _saving, onPressed: _submit),
        ],
      ),
    );
  }
}
