import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/meetup_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'meetup_detail_screen.dart';
import 'meetup_widgets.dart';

/// My meetups: upcoming RSVPs, events I host (incl. pending review) and past ones.
class MyMeetupsScreen extends StatefulWidget {
  const MyMeetupsScreen({super.key});

  static Route<void> route() => MaterialPageRoute(builder: (_) => const MyMeetupsScreen());

  @override
  State<MyMeetupsScreen> createState() => _MyMeetupsScreenState();
}

class _MyMeetupsScreenState extends State<MyMeetupsScreen> {
  MyMeetups? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || !context.read<BackendService>().isAuthenticated) return;
    setState(() => _error = null);
    try {
      final d = await context.read<MeetupService>().mine();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = MeetupService.errorText(e));
    }
  }

  Future<void> _open(Meetup m) async {
    await Navigator.of(context).push(MeetupDetailScreen.route(m.id, initial: m));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<BackendService>().isAuthenticated;
    final d = _data;
    Widget body;
    if (!authed) {
      body = Center(
        child: SingleChildScrollView(
          child: AppStateView(
            icon: Icons.lock_person_rounded,
            title: 'Log in to see your meetups',
            message: 'RSVP to satsangs near you and keep track of them here.',
            actionLabel: 'Log in',
            onAction: () => Navigator.pushNamed(context, '/login'),
          ),
        ),
      );
    } else if (d == null && _error != null) {
      body = Center(child: SingleChildScrollView(child: AppStateView.error(message: _error, onAction: _load)));
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (d.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
          AppStateView(
            icon: Icons.event_note_rounded,
            title: 'No meetups yet',
            message: 'When you RSVP to a satsang it shows up here, with a reminder the day before.',
          ),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            ..._section('Upcoming', d.upcoming),
            ..._section('Hosting', d.hosting),
            ..._section('Past', d.past),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My meetups')),
      body: body,
    );
  }

  List<Widget> _section(String title, List<Meetup> items) {
    if (items.isEmpty) return const [];
    return [
      SectionHeader(title: title, padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.sm)),
      for (final m in items)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
          child: MeetupCard(meetup: m, onTap: () => _open(m)),
        ),
    ];
  }
}
