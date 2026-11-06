import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/meetup_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'meetup_detail_screen.dart';
import 'meetup_widgets.dart';
import 'my_meetups_screen.dart';
import 'propose_meetup_screen.dart';

/// "Satsang near you": upcoming group events (aarti, kirtan, seva...) sorted
/// by start time and distance, with type filters. Guests can browse.
class MeetupsScreen extends StatefulWidget {
  /// Pre-selected type filter (a [MeetupType] key), e.g. from a deep link.
  final String? initialType;
  const MeetupsScreen({super.key, this.initialType});

  static Route<void> route({String? type}) => MaterialPageRoute(builder: (_) => MeetupsScreen(initialType: type));

  @override
  State<MeetupsScreen> createState() => _MeetupsScreenState();
}

class _MeetupsScreenState extends State<MeetupsScreen> {
  late String _type = MeetupType.all.contains(widget.initialType) ? widget.initialType! : 'all';
  MeetupList? _list;
  String? _error;
  bool _loading = true;
  bool _locating = false;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool askLocation = false}) async {
    if (!mounted) return;
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
      if (askLocation) _locating = true;
    });
    final svc = context.read<MeetupService>();
    try {
      MeetupList out;
      try {
        out = await svc.loadNearby(type: _type == 'all' ? null : _type, askLocation: askLocation, force: true);
      } on MeetupLocationException catch (e) {
        if (mounted) showAppSnack(context, e.message, error: true);
        out = await svc.loadNearby(type: _type == 'all' ? null : _type, force: true);
      }
      if (!mounted || req != _req) return;
      setState(() => _list = out);
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() => _error = MeetupService.errorText(e));
    } finally {
      if (mounted && req == _req) {
        setState(() {
          _loading = false;
          _locating = false;
        });
      }
    }
  }

  void _selectType(String t) {
    if (t == _type) return;
    setState(() => _type = t);
    _load();
  }

  Future<void> _open(Meetup m) async {
    await Navigator.of(context).push(MeetupDetailScreen.route(m.id, initial: m));
    if (mounted) _load();
  }

  Future<void> _propose() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ProposeMeetupScreen()));
    if (created == true && mounted) _load();
  }

  void _openMine() {
    if (!context.read<BackendService>().isAuthenticated) {
      Navigator.pushNamed(context, '/login');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyMeetupsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final items = list?.meetups ?? const <Meetup>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Satsang meetups'),
        actions: [
          IconButton(tooltip: 'My meetups', icon: const Icon(Icons.event_note_rounded), onPressed: _openMine),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
              child: _Hero(list: list, locating: _locating, onUseLocation: () => _load(askLocation: true)),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: AppSpacing.pagePadding,
                children: [
                  for (final t in ['all', ...MeetupType.all])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Center(
                        child: AppFilterChip(
                          label: t == 'all' ? 'All' : MeetupType.label(t),
                          icon: t == 'all' ? Icons.apps_rounded : MeetupTypeStyle.icon(t),
                          selected: _type == t,
                          onTap: () => _selectType(t),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loading && list == null)
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
                  child: SkeletonBox(height: 116),
                )
            else if (_error != null && list == null)
              AppStateView.error(message: _error, onAction: _load)
            else if (items.isEmpty)
              AppStateView(
                icon: Icons.groups_rounded,
                title: _type == 'all' ? 'No meetups near you yet' : 'No ${MeetupType.label(_type).toLowerCase()} meetups yet',
                message: 'Small group aarti, kirtan and seva at temples are the safest way to meet fellow seekers. '
                    'Host the first one!',
                actionLabel: 'Propose a meetup',
                onAction: _propose,
              )
            else ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
                  child: Text(_error!, style: AppText.caption.copyWith(color: AppColors.danger)),
                ),
              for (final m in items)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
                  child: MeetupCard(meetup: m, onTap: () => _open(m)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
                child: _HostCard(onTap: _propose),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final MeetupList? list;
  final bool locating;
  final VoidCallback onUseLocation;
  const _Hero({required this.list, required this.locating, required this.onUseLocation});

  @override
  Widget build(BuildContext context) {
    final byLocation = list?.byLocation ?? false;
    return AppCard(
      gradient: AppColors.cosmicGradient,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.temple_hindu_rounded, color: AppColors.gold, size: 22),
          SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text('Satsang near you',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Small group aarti, kirtan and seva at temples. Meeting in a group at a public place is the '
          'safest, most natural way to meet fellow seekers.',
          style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpacing.xs, runSpacing: 4, children: [
          Icon(byLocation ? Icons.near_me_rounded : Icons.public_rounded, size: 16, color: AppColors.gold),
          Text(
            byLocation ? 'Within ${list?.radiusKm ?? 25} km of you' : 'Showing all upcoming meetups',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (!byLocation)
            TextButton(
              onPressed: locating ? null : onUseLocation,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: Text(locating ? 'Finding you…' : 'Use my location'),
            ),
        ]),
      ]),
    );
  }
}

class _HostCard extends StatelessWidget {
  final VoidCallback onTap;
  const _HostCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: const Icon(Icons.add_location_alt_rounded, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Host a satsang', style: AppText.bodyStrong),
            SizedBox(height: 2),
            Text('Verified members can propose an event at a temple or public place.', style: AppText.caption),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
      ]),
    );
  }
}
