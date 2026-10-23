import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../screens/panchang_screen.dart';
import '../services/backend_service.dart';
import 'forecast_widgets.dart' show activeFamilyId, askAstrologer;
import 'ui/app_ui.dart';

/// Home "Hindu Panchang" section: today's festival / vrat (if any) as a
/// highlighted card, then a rail of what's coming up (festivals, Ekadashi,
/// Purnima, Amavasya, Sankranti, eclipses).
///
/// Dates and descriptions come from the backend month forecast (this month
/// and next), which works them out with the proper tithi and timing rules.
/// Bump [refreshTick] to re-fetch (pull-to-refresh).
class HinduCalendarSection extends StatefulWidget {
  final int refreshTick;
  const HinduCalendarSection({super.key, this.refreshTick = 0});

  /// Event types that belong to the Hindu calendar (astro-only events such as
  /// retrogrades and Chandrashtama are left to the forecast screens).
  static const types = {'festival', 'ekadashi', 'sankranti', 'full_moon', 'new_moon', 'solar_eclipse', 'lunar_eclipse'};

  static const _lookahead = Duration(days: 60);
  static const _maxUpcoming = 10;

  @override
  State<HinduCalendarSection> createState() => _HinduCalendarSectionState();
}

class _HinduCalendarSectionState extends State<HinduCalendarSection> {
  List<ForecastEvent>? _events;
  bool _loading = false;
  bool _failed = false;
  String? _profileKey;
  int _token = 0;

  @override
  void didUpdateWidget(HinduCalendarSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick && _profileKey != null) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final now = DateTime.now();
    final familyId = activeFamilyId(service);
    List<Map<String, dynamic>?> months;
    try {
      months = await Future.wait([
        service.fetchMonthForecast(familyId: familyId, forceRefresh: force),
        service.fetchMonthForecast(month: DateTime(now.year, now.month + 1, 1), familyId: familyId),
      ]);
    } catch (_) {
      months = const [null, null];
    }
    if (!mounted || token != _token) return;

    final today = DateTime(now.year, now.month, now.day);
    final seen = <String>{};
    final events = <ForecastEvent>[];
    for (final m in months) {
      final raw = m?['events'];
      if (raw is! List) continue;
      for (final item in raw) {
        final e = ForecastEvent.fromJson(item);
        final d = e.date;
        if (d == null || !HinduCalendarSection.types.contains(e.type)) continue;
        final day = DateTime(d.year, d.month, d.day);
        if (day.isBefore(today) || day.difference(today) > HinduCalendarSection._lookahead) continue;
        if (seen.add('${day.toIso8601String()}|${e.title}')) events.add(e);
      }
    }
    events.sort((a, b) {
      final byDate = a.date!.compareTo(b.date!);
      return byDate != 0 ? byDate : b.importance.compareTo(a.importance);
    });

    setState(() {
      _loading = false;
      // Only a total failure is an error; one missing month still shows the other.
      _failed = months.every((m) => m == null);
      _events = events;
    });
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    // The forecast needs a Kundli; without one Home already shows the create prompt.
    if (kundli == null) return const SizedBox.shrink();

    final key = '${activeFamilyId(service)}|${Vedic.identity(kundli)}';
    if (key != _profileKey) {
      _profileKey = key;
      _events = null;
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final events = _events;
    final Widget body;
    if (events == null || (_loading && events.isEmpty)) {
      body = _skeleton();
    } else if (_failed) {
      body = Padding(
        padding: AppSpacing.pagePadding,
        child: AppCard(
          padding: EdgeInsets.zero,
          child: AppStateView.error(
            compact: true,
            title: "Couldn't load festival dates",
            onAction: () => _load(force: true),
          ),
        ),
      );
    } else if (events.isEmpty) {
      return const SizedBox.shrink();
    } else {
      final today = _dayOf(DateTime.now());
      final todays = events.where((e) => _dayOf(e.date!) == today).take(2).toList();
      final upcoming =
          events.where((e) => _dayOf(e.date!).isAfter(today)).take(HinduCalendarSection._maxUpcoming).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in todays)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
              child: _TodayEventCard(event: e, onTap: () => _showEvent(e)),
            ),
          if (upcoming.isNotEmpty) _rail(upcoming),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Hindu Panchang',
          eyebrow: true,
          subtitle: 'Festivals and vrat days ahead',
          actionLabel: 'Calendar',
          onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PanchangScreen())),
        ),
        body,
      ],
    );
  }

  double _railHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return 108 + 96 * scale;
  }

  Widget _rail(List<ForecastEvent> events) {
    return SizedBox(
      height: _railHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.pagePadding,
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => _UpcomingEventCard(event: events[i], onTap: () => _showEvent(events[i])),
      ),
    );
  }

  Widget _skeleton() {
    return SizedBox(
      height: _railHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: AppSpacing.pagePadding,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, __) => const SkeletonBox(width: 156, radius: AppRadius.lg),
      ),
    );
  }

  void _showEvent(ForecastEvent e) {
    final style = _EventStyle.of(e);
    final date = e.date!;
    final when = [
      DateFormat('EEEE, d MMMM').format(date),
      if (e.time != null && e.time!.isNotEmpty) e.time!,
    ].join(' · ');

    showAppSheet<void>(
      context,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SizedBox(height: 168, child: _EventArt(style: style)),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                AppBadge(label: style.label, color: style.color, icon: style.icon),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(_countdown(date),
                      style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Text(e.title, style: AppText.headline),
              const SizedBox(height: 4),
              Text(when, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              if (e.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(e.description, style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 15, height: 1.5)),
              ],
              if (e.personalImpact.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.infoSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.info),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('For you',
                                style: AppText.caption.copyWith(color: AppColors.info, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(e.personalImpact, style: AppText.body.copyWith(color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Ask AI about this day',
                icon: Icons.auto_awesome_rounded,
                onPressed: () => askAstrologer(
                  context,
                  'Tell me about ${e.title} on ${DateFormat('d MMMM yyyy').format(date)}. '
                  'What should I do on this day, and what does it mean for me?',
                  field: 'Panchang',
                  closeSheet: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'See Panchang for this day',
                icon: Icons.calendar_month_rounded,
                variant: AppButtonVariant.outline,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PanchangScreen(initialDate: date)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _countdown(DateTime date) {
  final now = DateTime.now();
  final days = DateTime(date.year, date.month, date.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 7) return 'In $days days · ${DateFormat('EEE').format(date)}';
  return 'In $days days';
}

// -----------------------------------------------------------------------------
// Look per event: label, colour, icon and picture.
// -----------------------------------------------------------------------------

/// Deity illustrations sit on this cream (it matches the pictures' own
/// background), shown whole; photos fill the frame.
const _kArtCream = Color(0xFFFAF3E2);

class _EventStyle {
  final String label;
  final Color color;
  final IconData icon;
  final String image;

  /// True for a deity illustration (shown whole on cream), false for a photo.
  final bool illustration;

  const _EventStyle(this.label, this.color, this.icon, this.image, {this.illustration = true});

  static _EventStyle of(ForecastEvent e) {
    final t = e.title.toLowerCase();
    switch (e.type) {
      case 'ekadashi':
        return const _EventStyle('Ekadashi', AppColors.info, Icons.spa_rounded, 'assets/images/satyanarayan.jpg');
      case 'full_moon':
        return const _EventStyle('Purnima', AppColors.cosmicLight, Icons.brightness_1_outlined,
            'assets/images/topic_how_is_my_day.jpg',
            illustration: false);
      case 'new_moon':
        return const _EventStyle('Amavasya', AppColors.cosmic, Icons.brightness_2_rounded,
            'assets/images/astrology-hero.jpg',
            illustration: false);
      case 'sankranti':
        return const _EventStyle('Sankranti', AppColors.warning, Icons.wb_sunny_rounded,
            'assets/images/featuredPuja.jpg',
            illustration: false);
      case 'solar_eclipse':
      case 'lunar_eclipse':
        return const _EventStyle('Grahan', AppColors.danger, Icons.contrast_rounded,
            'assets/images/topic_transits_today.jpg',
            illustration: false);
    }
    // Festivals: pick the deity the day is for.
    const festival = 'Festival';
    if (t.contains('dhanteras')) {
      return const _EventStyle(festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/dhanteras.jpg');
    }
    if (t.contains('diwali') || t.contains('lakshmi') || t.contains('deepavali')) {
      return const _EventStyle(
          festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/diwali_lakshmi_puja.jpg');
    }
    if (t.contains('navratri') || t.contains('durga')) {
      return const _EventStyle(festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/durga-ma.jpg');
    }
    if (t.contains('dussehra') || t.contains('dasara') || t.contains('vijaya') || t.contains('ram navami')) {
      return const _EventStyle(
          festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/dusshera_pujan.jpg');
    }
    if (t.contains('ganesh') || t.contains('chaturthi')) {
      return const _EventStyle(festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/ganeshaa.jpg');
    }
    if (t.contains('hanuman')) {
      return const _EventStyle(festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/hanumanji.jpg');
    }
    if (t.contains('shiv') || t.contains('pradosh') || t.contains('mahadev')) {
      return const _EventStyle(
          festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/anniversary_puja.jpg');
    }
    if (t.contains('krishna') || t.contains('janmashtami') || t.contains('vishnu') || t.contains('satyanarayan')) {
      return const _EventStyle(festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/satyanarayan.jpg');
    }
    return const _EventStyle(festival, AppColors.primary, Icons.celebration_rounded, 'assets/images/featuredPuja.jpg',
        illustration: false);
  }
}

class _EventArt extends StatelessWidget {
  final _EventStyle style;
  const _EventArt({required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final px = (c.maxWidth.isFinite ? c.maxWidth : 200) * MediaQuery.devicePixelRatioOf(context);
      final image = Image.asset(
        style.image,
        fit: style.illustration ? BoxFit.contain : BoxFit.cover,
        cacheWidth: style.illustration ? null : px.round(),
        cacheHeight: style.illustration
            ? ((c.maxHeight.isFinite ? c.maxHeight : 120) * MediaQuery.devicePixelRatioOf(context)).round()
            : null,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
      return ColoredBox(
        color: style.illustration ? _kArtCream : AppColors.cosmic,
        child: style.illustration
            // The illustrations have wide cream margins; zoom in a little.
            ? ClipRect(child: Transform.scale(scale: 1.18, child: Center(child: image)))
            : image,
      );
    });
  }
}

/// Wide highlighted card for an event happening today.
class _TodayEventCard extends StatelessWidget {
  final ForecastEvent event;
  final VoidCallback onTap;
  const _TodayEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = _EventStyle.of(event);
    return Semantics(
      button: true,
      label: 'Today: ${event.title}. ${event.description}',
      onTap: onTap,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        gradient: const LinearGradient(colors: [AppColors.primarySoft, AppColors.warningSoft]),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppRadius.lg)),
              child: SizedBox(width: 104, height: 128, child: _EventArt(style: style)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppBadge(label: 'TODAY', color: Colors.white, background: AppColors.primary),
                    const SizedBox(height: 6),
                    Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(event.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card in the upcoming rail: picture with a date chip, title, countdown.
class _UpcomingEventCard extends StatelessWidget {
  final ForecastEvent event;
  final VoidCallback onTap;
  const _UpcomingEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = _EventStyle.of(event);
    final date = event.date!;
    return Semantics(
      button: true,
      label: '${event.title}, ${DateFormat('EEEE d MMMM').format(date)}. ${_countdown(date)}',
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: 156,
        child: AppCard(
          onTap: onTap,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 104,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _EventArt(style: style),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: AppShadows.card,
                        ),
                        child: Column(
                          children: [
                            Text(DateFormat('d').format(date),
                                style: const TextStyle(
                                    fontSize: 16, height: 1.1, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                            Text(DateFormat('MMM').format(date).toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong.copyWith(fontSize: 13.5, height: 1.3)),
                      const Spacer(),
                      Row(children: [
                        Icon(style.icon, size: 13, color: style.color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(_countdown(date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
