import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../config/home_promos.dart';
import '../../widgets/play_strip.dart';
import '../../widgets/promo_carousel.dart';
import '../../widgets/today_simple_card.dart';
import '../../widgets/ui/app_ui.dart';
import '../../widgets/your_day_card.dart';
import '../blog_detail_screen.dart';
import '../blog_screen.dart' show kCosmicGuideArticles;
import '../kundli_view_screen.dart';
import '../panchang_screen.dart';

// Bottom-nav tab indices (see HomeScreen).
const int _kChartTab = 1;
const int _kChatTab = 3;
const int _kLoveTab = 4;

class HomeTab extends StatefulWidget {
  final void Function(int) onNavigateTab;
  const HomeTab({super.key, required this.onNavigateTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Live human pandits (/pandit/list).
  List<Map<String, dynamic>> _pandits = [];
  bool _panditsLoading = true;
  String? _panditsError;

  bool _loading = false;
  bool _loadedOnce = false;

  /// Bumped on pull-to-refresh so the forecast cards and the Play strip re-fetch.
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  Future<void> _loadData() async {
    if (_loading) return;
    final service = Provider.of<BackendService>(context, listen: false);
    setState(() {
      _loading = true;
      if (_loadedOnce) _refreshTick++;
      _loadedOnce = true;
    });
    await Future.wait<void>([
      _loadPandits(),
      if (service.isAuthenticated) service.fetchWalletBalance().then((_) {}, onError: (_) {}),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPandits() async {
    if (!mounted) return;
    final service = Provider.of<BackendService>(context, listen: false);
    setState(() {
      _panditsLoading = true;
      _panditsError = null;
    });
    List<Map<String, dynamic>> list = const [];
    String? error;
    try {
      list = await service.fetchPanditsList();
    } on BackendException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load astrologers.';
    }
    if (!mounted) return;
    setState(() {
      _panditsLoading = false;
      _panditsError = error;
      if (error == null) _pandits = list;
    });
  }

  // ------------------------------------------------------------------ helpers
  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openAi([String? question]) {
    Navigator.pushNamed(context, AppRoutes.chatbot, arguments: <String, dynamic>{
      'name': 'AI Astrologer',
      'specialty': 'Vedic AI astrologer · available 24/7',
      'field': 'General Guidance',
      if (question != null) 'initialMessage': question,
    });
  }

  void _route(String name, [Object? args]) => Navigator.pushNamed(context, name, arguments: args);

  Future<void> _openPromo(HomePromo promo) async {
    switch (promo.action) {
      case PromoRoute(:final name, :final arguments):
        _route(name, arguments);
      case PromoTab(:final index):
        widget.onNavigateTab(index);
      case PromoAiChat():
        _openAi();
      case PromoKundliReport():
        _push(const KundliViewScreen(initialTab: KundliExplorer.reportTab));
      case PromoLink(:final url):
        final uri = Uri.tryParse(url);
        final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) showAppSnack(context, 'Could not open the link', error: true);
    }
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final selfKundli = service.kundliData;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(service, selfKundli),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    // Hero: the AI astrologer.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
                      child: AppSearchBar(hint: 'Ask anything about your chart…', onTap: _openAi),
                    ),
                    _askSuggestions(),

                    // Ad / promo slot (images or videos, see lib/config/home_promos.dart).
                    const SizedBox(height: AppSpacing.md),
                    PromoCarousel(promos: kHomePromos, onTap: _openPromo),

                    // Your day (score + summary from the forecast).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
                      child: YourDayCard(refreshTick: _refreshTick),
                    ),

                    // Quick actions.
                    const SectionHeader(title: 'Explore', subtitle: 'Everything your stars can tell you'),
                    _explore(),

                    // Games: streak / missions (hidden without a Kundli).
                    Padding(
                      padding: AppSpacing.pagePadding,
                      child: PlayStrip(refreshTick: _refreshTick),
                    ),

                    // Live astrologers.
                    SectionHeader(
                      title: 'Talk to astrologers',
                      subtitle: 'AI astrologer and live Vedic experts',
                      actionLabel: 'See all',
                      onAction: () => widget.onNavigateTab(_kChatTab),
                    ),
                    _astrologerRail(),

                    // Today in plain words + planet weather.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, 0),
                      child: TodaySimpleCard(refreshTick: _refreshTick),
                    ),

                    // Panchang, hora and Moon.
                    SectionHeader(
                      title: "Today's sky",
                      subtitle: 'Panchang for ${kDefaultPanchangLocation.name}',
                      actionLabel: 'Panchang',
                      onAction: () => _route(AppRoutes.panchang),
                    ),
                    Padding(padding: AppSpacing.pagePadding, child: _todaySkyCard()),

                    // Calculators.
                    const SectionHeader(title: 'Quick calculators', subtitle: 'Worked out from your birth details'),
                    _calculators(selfKundli),

                    // Articles.
                    SectionHeader(
                      title: 'Learn astrology',
                      actionLabel: 'See all',
                      onAction: () => _route(AppRoutes.blog),
                    ),
                    _articlesRail(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ top bar
  Widget _topBar(BackendService service, Map<String, dynamic>? selfKundli) {
    final name = Vedic.displayName(selfKundli, service: service);
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    final active = Vedic.activeKundli(service);
    final family = service.selectedFamilyMember;

    String sub;
    if (family != null && active != null) {
      sub = "Viewing ${Vedic.displayName(active)}'s chart";
    } else if (active != null) {
      final asc = Vedic.text(active['ascendant'], '');
      final moon = Vedic.text(active['moonSign'], '');
      sub = [if (asc.isNotEmpty) '$asc Lagna', if (moon.isNotEmpty) '$moon Moon'].join(' · ');
      if (sub.isEmpty) sub = 'Your Kundli';
    } else {
      sub = 'Add birth details to see your chart';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${_greeting()}, $firstName. $sub. Switch profile',
              onTap: () => showKundliProfilePicker(context),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => showKundliProfilePicker(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      AppAvatar(name: name, size: 42, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${_greeting()}, $firstName',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(sub,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                                ),
                                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSecondary),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (service.isAuthenticated) ...[
            const SizedBox(width: AppSpacing.xs),
            Semantics(
              button: true,
              label: 'Wallet balance ${service.walletBalance.toStringAsFixed(0)} rupees',
              onTap: () => _route(AppRoutes.wallet),
              excludeSemantics: true,
              child: Material(
                color: AppColors.surface,
                shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _route(AppRoutes.wallet),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 18),
                          const SizedBox(width: 4),
                          Text('₹${service.walletBalance.toStringAsFixed(0)}', style: AppText.bodyStrong),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline_rounded, color: AppColors.textPrimary),
            onPressed: () => _route(AppRoutes.profile),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ AI suggestions
  static const List<(String, String)> _suggestions = [
    ('Career this year', 'How will my career go this year, based on my chart?'),
    ('Marriage timing', 'When is a good time for marriage in my chart?'),
    ('Is today good?', 'Is today a good day for me to start something new?'),
    ('Money & savings', 'What does my chart say about money and savings right now?'),
  ];

  Widget _askSuggestions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
      child: Row(
        children: [
          for (final (label, question) in _suggestions) ...[
            AppFilterChip(
              label: label,
              icon: Icons.auto_awesome_rounded,
              selected: false,
              onTap: () => _openAi(question),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ explore
  Widget _explore() {
    return Padding(
      padding: AppSpacing.pagePadding,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ExploreCard(
                  image: 'assets/images/topic_birth_chart.jpg',
                  title: 'My Kundli',
                  subtitle: 'Your birth chart, read for you',
                  icon: Icons.auto_awesome_mosaic_rounded,
                  large: true,
                  onTap: () => widget.onNavigateTab(_kChartTab),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ExploreCard(
                  image: 'assets/images/topic_how_is_my_day.jpg',
                  title: 'Horoscope',
                  subtitle: 'Today, this week, this month',
                  icon: Icons.wb_twilight_rounded,
                  large: true,
                  onTap: () => _route(AppRoutes.forecast, {'tab': 'day'}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.92,
            children: [
              _ExploreCard(
                image: 'assets/images/topic_love_compatibility.jpg',
                title: 'Kundli matching',
                icon: Icons.favorite_rounded,
                onTap: () => widget.onNavigateTab(_kLoveTab),
              ),
              _ExploreCard(
                image: 'assets/images/topic_moon_calendar.jpg',
                title: 'Panchang',
                icon: Icons.calendar_month_rounded,
                onTap: () => _route(AppRoutes.panchang),
              ),
              _ExploreCard(
                image: 'assets/images/topic_transits_today.jpg',
                title: 'Life timeline',
                icon: Icons.timeline_rounded,
                onTap: () => _route(AppRoutes.lifeTimeline),
              ),
              _ExploreCard(
                image: 'assets/images/astrology-hero.jpg',
                title: 'Why did it happen?',
                icon: Icons.manage_search_rounded,
                alignment: Alignment.centerRight,
                onTap: () => _route(AppRoutes.dateExplorer),
              ),
              _ExploreCard(
                image: 'assets/images/Brihaspati.jpg',
                title: 'Remedies & gems',
                icon: Icons.diamond_outlined,
                onTap: () => _route(AppRoutes.gemstoneRemedy),
              ),
              _ExploreCard(
                image: 'assets/images/heroBanner.jpg',
                title: 'Games',
                icon: Icons.sports_esports_rounded,
                onTap: () => _route(AppRoutes.games),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ astrologers
  Widget _astrologerRail() {
    Widget rail(List<Widget> cards) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.pagePadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in cards) ...[c, const SizedBox(width: AppSpacing.sm)],
            ],
          ),
        );

    final aiCard = _AiAstrologerCard(onTap: _openAi);

    if (_panditsLoading && _pandits.isEmpty) {
      return rail([
        aiCard,
        for (int i = 0; i < 2; i++) const SkeletonBox(width: _PanditCard.width, height: 200, radius: AppRadius.lg),
      ]);
    }
    if (_panditsError != null && _pandits.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rail([aiCard]),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: AppStateView.error(
                compact: true,
                title: "Couldn't load live astrologers",
                message: _panditsError,
                onAction: _loadPandits,
              ),
            ),
          ),
        ],
      );
    }
    return rail([
      aiCard,
      for (final p in _pandits.take(8)) _PanditCard(pandit: p, onTap: () => widget.onNavigateTab(_kChatTab)),
    ]);
  }

  // ------------------------------------------------------------------ articles
  static const List<String> _articleImages = [
    'assets/images/astrology.jpg',
    'assets/images/topic_transits_today.jpg',
    'assets/images/topic_moon_calendar.jpg',
    'assets/images/topic_how_is_my_day.jpg',
  ];

  Widget _articlesRail() {
    final articles = kCosmicGuideArticles;
    if (articles.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: AppSpacing.pagePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < articles.length; i++) ...[
            SizedBox(
              width: 240,
              child: AppCard(
                padding: EdgeInsets.zero,
                onTap: () => _push(BlogDetailScreen(blogId: articles[i].id)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppImage(_articleImages[i % _articleImages.length], height: 120, width: double.infinity),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((articles[i].category ?? '').isNotEmpty)
                            Text(articles[i].category!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(articles[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                          if ((articles[i].readTime ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(articles[i].readTime!, style: AppText.caption),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ today's sky
  Widget _todaySkyCard() {
    DailyPanchang? p;
    try {
      p = PanchangCalculator.cached(PanchangCalculator.todayAt(kDefaultPanchangLocation));
    } catch (_) {
      p = null;
    }
    const loc = kDefaultPanchangLocation;
    final m = _moonNow();

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _route(AppRoutes.panchang),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: p == null
                  ? const Row(children: [
                      _TintIcon(Icons.calendar_month_rounded),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text('Open the Panchang', style: AppText.bodyStrong)),
                      Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _TintIcon(Icons.wb_sunny_rounded),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text('${p.paksha} ${p.tithi.name} · ${p.nakshatra.name}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _skyStat('Rahu Kaal (avoid)', PanchangCalculator.formatWindow(p.rahuKaal, loc),
                                  AppColors.danger),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _skyStat('Abhijit Muhurat (good)', PanchangCalculator.formatWindow(p.abhijit, loc),
                                  AppColors.success),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          const _LiveHoraRow(),
          const Divider(height: 1, color: AppColors.divider),
          InkWell(
            onTap: () => _showMoonCalendarModal(context),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  _TintIcon(m.icon),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.phase} in ${m.rashi}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                        Text(
                          '${m.illumination}% lit · ${m.nakshatra} · Full Moon ${DateFormat('d MMM').format(m.nextFullMoon.toLocal())}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skyStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ moon
  _MoonInfo _moonNow() => _MoonInfo.compute(DateTime.now().toUtc());

  void _showMoonCalendarModal(BuildContext context) {
    final now = DateTime.now().toUtc();
    final m = _MoonInfo.compute(now);
    final fmt = DateFormat('EEE, d MMM');
    showAppSheet<void>(
      context,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text("Today's Moon", style: AppText.title)),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
            Text('${m.phase} in ${m.rashi}', style: AppText.subtitle.copyWith(color: AppColors.primary)),
            const SizedBox(height: 6),
            Text('${m.illumination}% illuminated · ${m.nakshatra} Nakshatra · ${m.ageDays} days since New Moon',
                style: AppText.body),
            const SizedBox(height: AppSpacing.md),
            _moonRow(Icons.brightness_1_rounded, 'Next Full Moon (Purnima)', fmt.format(m.nextFullMoon.toLocal())),
            _moonRow(Icons.brightness_1_outlined, 'Next New Moon (Amavasya)', fmt.format(m.nextNewMoon.toLocal())),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Open Panchang calendar',
              onPressed: () {
                Navigator.pop(sheetContext);
                _route(AppRoutes.panchang);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _moonRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.cosmicLight),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.body)),
          const SizedBox(width: AppSpacing.xs),
          Text(value, style: AppText.bodyStrong),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ calculators
  Widget _calculators(Map<String, dynamic>? kundli) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.format_size_rounded, 'Big 3', () => _showBigThree(kundli)),
      (Icons.hub_rounded, 'Rahu & Ketu', () => _showNodes(kundli)),
      (Icons.grid_on_rounded, 'Lo Shu grid', () => _showLoShu(kundli)),
      (Icons.pin_outlined, 'My numbers', () => _showNumbers(kundli)),
      (Icons.calculate_rounded, 'Chinese zodiac', () => _showChinese(kundli)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: AppSpacing.pagePadding,
      child: Row(
        children: [
          for (final (icon, label, onTap) in items) ...[
            AppFilterChip(label: label, icon: icon, selected: false, onTap: onTap),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  DateTime? _birthDate(Map<String, dynamic>? kundli) {
    if (kundli == null) return null;
    final utc = Vedic.birthUtc(kundli);
    if (utc == null) return null;
    final ist = utc.add(const Duration(hours: 5, minutes: 30));
    return DateTime(ist.year, ist.month, ist.day);
  }

  void _needBirthDetails() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Add your birth details first.'),
          action: SnackBarAction(label: 'Add', onPressed: () => _route(AppRoutes.birthDetails)),
        ),
      );
  }

  void _showInfoSheet(String title, IconData icon, List<Widget> children) {
    showAppSheet<void>(
      context,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TintIcon(icon),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(title, style: AppText.title)),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _factRow(String label, String value, {String? sub}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.bodyStrong),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showBigThree(Map<String, dynamic>? kundli) {
    if (kundli == null || Vedic.signIndex(kundli['ascendant']) < 0) return _needBirthDetails();
    _showInfoSheet('Your Big 3 (Vedic)', Icons.format_size_rounded, [
      _factRow('Sun sign', Vedic.text(kundli['sunSign']), sub: 'Soul, ego and vitality'),
      _factRow('Moon sign', Vedic.text(kundli['moonSign']), sub: 'Mind and emotions, the key sign in Vedic astrology'),
      _factRow('Ascendant (Lagna)', Vedic.text(kundli['ascendant']), sub: 'Body, personality and life direction'),
      const Text('Sidereal (Lahiri) signs. These can differ from Western tropical signs by about one sign.',
          style: AppText.caption),
    ]);
  }

  void _showNodes(Map<String, dynamic>? kundli) {
    if (kundli == null) return _needBirthDetails();
    final planets = Vedic.d1Planets(kundli);
    Map<String, dynamic>? find(String k) {
      for (final p in planets) {
        if (Vedic.planetKey(p['name']) == k) return p;
      }
      return null;
    }

    final rahu = find('Rahu'), ketu = find('Ketu');
    if (rahu == null || ketu == null) return _needBirthDetails();
    _showInfoSheet('Your lunar nodes', Icons.hub_rounded, [
      _factRow('Rahu (North Node)', '${Vedic.text(rahu['sign'])} · H${Vedic.text(rahu['house'])}',
          sub: 'Worldly desires and growth: ${kHouseMeanings[Vedic.toInt(rahu['house'])] ?? ''}'),
      _factRow('Ketu (South Node)', '${Vedic.text(ketu['sign'])} · H${Vedic.text(ketu['house'])}',
          sub: 'Past mastery and detachment: ${kHouseMeanings[Vedic.toInt(ketu['house'])] ?? ''}'),
    ]);
  }

  static int _reduce(int n, {bool keepMaster = false}) {
    while (n > 9) {
      if (keepMaster && (n == 11 || n == 22 || n == 33)) return n;
      n = n.toString().split('').map(int.parse).fold(0, (a, b) => a + b);
    }
    return n;
  }

  void _showLoShu(Map<String, dynamic>? kundli) {
    final dob = _birthDate(kundli);
    if (dob == null) return _needBirthDetails();
    final digits = DateFormat('ddMMyyyy').format(dob).split('').map(int.parse).where((d) => d != 0).toList();
    final driver = _reduce(dob.day);
    final conductor = _reduce(DateFormat('ddMMyyyy').format(dob).split('').map(int.parse).fold(0, (a, b) => a + b));
    final all = [...digits, driver, conductor];
    final counts = List.filled(10, 0);
    for (final d in all) {
      if (d > 0 && d < 10) counts[d]++;
    }
    const layout = [4, 9, 2, 3, 5, 7, 8, 1, 6];
    final missing = [
      for (int i = 1; i <= 9; i++)
        if (counts[i] == 0) i
    ];

    _showInfoSheet('Lo Shu grid', Icons.grid_on_rounded, [
      Text('Born ${DateFormat('d MMM yyyy').format(dob)} · Driver $driver · Conductor $conductor', style: AppText.body),
      const SizedBox(height: 14),
      Center(
        child: SizedBox(
          width: 240,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: layout.map((n) {
              final c = counts[n];
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c > 0 ? AppColors.primarySoft : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: c > 0 ? AppColors.primary : AppColors.border),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    c > 0 ? List.filled(c, '$n').join() : '–',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c > 0 ? AppColors.primaryDark : AppColors.textTertiary),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        missing.isEmpty ? 'No missing numbers: a well-balanced grid.' : 'Missing numbers: ${missing.join(', ')}',
        style: AppText.bodyStrong,
      ),
    ]);
  }

  void _showNumbers(Map<String, dynamic>? kundli) {
    final dob = _birthDate(kundli);
    if (dob == null) return _needBirthDetails();
    final allDigits = DateFormat('ddMMyyyy').format(dob).split('').map(int.parse).fold(0, (a, b) => a + b);
    final mulank = _reduce(dob.day);
    final bhagyank = _reduce(allDigits, keepMaster: true);
    const chaldean = {
      'A': 1,
      'I': 1,
      'J': 1,
      'Q': 1,
      'Y': 1,
      'B': 2,
      'K': 2,
      'R': 2,
      'C': 3,
      'G': 3,
      'L': 3,
      'S': 3,
      'D': 4,
      'M': 4,
      'T': 4,
      'E': 5,
      'H': 5,
      'N': 5,
      'X': 5,
      'U': 6,
      'V': 6,
      'W': 6,
      'O': 7,
      'Z': 7,
      'F': 8,
      'P': 8,
    };
    final name = Vedic.displayName(kundli).toUpperCase();
    final nameSum = name.split('').fold<int>(0, (a, ch) => a + (chaldean[ch] ?? 0));
    _showInfoSheet('Know your numbers', Icons.pin_outlined, [
      _factRow('Mulank (psychic number)', '$mulank', sub: 'From your birth day: how you see yourself'),
      _factRow('Bhagyank (destiny number)', '$bhagyank', sub: 'From your full date of birth: your life path'),
      if (nameSum > 0)
        _factRow('Name number (Chaldean)', '${_reduce(nameSum)}',
            sub: 'Compound $nameSum · from "${Vedic.displayName(kundli)}"'),
    ]);
  }

  void _showChinese(Map<String, dynamic>? kundli) {
    final dob = _birthDate(kundli);
    if (dob == null) return _needBirthDetails();
    const animals = ['Rat', 'Ox', 'Tiger', 'Rabbit', 'Dragon', 'Snake', 'Horse', 'Goat', 'Monkey', 'Rooster', 'Dog', 'Pig'];
    const elements = ['Metal', 'Metal', 'Water', 'Water', 'Wood', 'Wood', 'Fire', 'Fire', 'Earth', 'Earth'];
    String sign(int year) => '${elements[year % 10]} ${animals[((year - 4) % 12 + 12) % 12]}';
    final early = dob.month == 1 || (dob.month == 2 && dob.day < 20);
    _showInfoSheet('Chinese zodiac', Icons.calculate_rounded, [
      _factRow('Your sign', sign(dob.year), sub: 'Based on birth year ${dob.year}'),
      if (early)
        Text(
          'You were born before late February. If your birthday falls before Chinese New Year of ${dob.year}, '
          'your sign is ${sign(dob.year - 1)}.',
          style: AppText.body,
        ),
    ]);
  }
}

// ============================================================================
// Private widgets
// ============================================================================

/// Soft tinted square with a rounded Material icon (the one icon style on Home).
class _TintIcon extends StatelessWidget {
  final IconData icon;
  const _TintIcon(this.icon);

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Icon(icon, color: AppColors.primary, size: 22),
      );
}

/// First card in the astrologer rail: the always-available AI astrologer.
class _AiAstrologerCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AiAstrologerCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _PanditCard.width,
      child: AppCard(
        gradient: AppColors.cosmicGradient,
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Semantics(
          button: true,
          label: 'AI astrologer, available 24/7. Ask now',
          onTap: onTap,
          excludeSemantics: true,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 30),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('AI Astrologer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong.copyWith(color: AppColors.textOnDark)),
              Text('Reads your Kundli',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
              const SizedBox(height: 6),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: AppBadge(label: 'Online 24/7', color: Colors.white, background: AppColors.success),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(label: 'Ask now', onPressed: onTap, height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// A live human pandit from /pandit/list. Opens the Chat tab, where the
/// consultation flow (wallet, queue) lives.
class _PanditCard extends StatelessWidget {
  static const double width = 156;
  final Map<String, dynamic> pandit;
  final VoidCallback onTap;
  const _PanditCard({required this.pandit, required this.onTap});

  static double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final p = pandit;
    final name = (p['full_name'] ?? p['fullName'] ?? 'Pandit').toString();
    final specialty = (p['specialty'] ?? 'Vedic Astrology').toString();
    final avatar = (p['avatar_url'] ?? p['avatarUrl'] ?? '').toString();
    final online = p['is_online'] == true || p['isOnline'] == true;
    final busy = p['is_busy'] == true || p['isBusy'] == true;
    final rate = _num(p['rate_per_min'] ?? p['ratePerMin']);
    final rating = _num(p['rating']);
    final reviews = _num(p['total_reviews'] ?? p['totalReviews'])?.toInt() ?? 0;
    final years = _num(p['experience_years'] ?? p['experienceYears'])?.toInt();

    final (statusLabel, statusColor) = !online
        ? ('Offline', AppColors.textTertiary)
        : (busy ? ('Busy', AppColors.warning) : ('Online', AppColors.success));

    return SizedBox(
      width: width,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Semantics(
          button: true,
          label: '$name, $specialty, $statusLabel'
              '${rating != null && reviews > 0 ? ', rated ${rating.toStringAsFixed(1)}' : ''}. Open chat',
          onTap: onTap,
          excludeSemantics: true,
          child: Column(
            children: [
              const SizedBox(height: 4),
              AppAvatar(imageUrl: avatar, name: name, size: 64, online: online && !busy),
              const SizedBox(height: AppSpacing.xs),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
              Text(specialty, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (rating != null && reviews > 0)
                    RatingBadge(rating.toStringAsFixed(1))
                  else
                    const AppBadge(label: 'New', color: AppColors.info),
                  AppBadge(label: statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (years != null && years > 0) '$years yrs',
                  if (rate != null) '₹${rate.toStringAsFixed(0)}/min',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              AppButton(label: 'Chat', onPressed: onTap, height: 40, variant: AppButtonVariant.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoonInfo {
  final String phase;
  final IconData icon;
  final int illumination;
  final int ageDays;
  final String rashi;
  final String nakshatra;
  final DateTime nextFullMoon;
  final DateTime nextNewMoon;

  const _MoonInfo(this.phase, this.icon, this.illumination, this.ageDays, this.rashi, this.nakshatra, this.nextFullMoon,
      this.nextNewMoon);

  static double _elong(DateTime utc) {
    final jd = PanchangCalculator.julianDay(utc);
    final e = (PanchangCalculator.moonTropical(jd) - PanchangCalculator.sunTropical(jd)) % 360;
    return e < 0 ? e + 360 : e;
  }

  /// Next instant after [from] where the Sun-Moon elongation equals [target].
  static DateTime _nextElongation(DateTime from, double target) {
    const rate = 12.19; // mean degrees per day
    final e0 = _elong(from);
    var ahead = (target - e0) % 360;
    if (ahead < 0) ahead += 360;
    if (ahead < 0.5) ahead += 360; // already at it – take the next one
    var t = from.add(Duration(minutes: (ahead / rate * 1440).round()));
    for (int i = 0; i < 4; i++) {
      var diff = (target - _elong(t)) % 360;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      t = t.add(Duration(minutes: (diff / rate * 1440).round()));
    }
    return t;
  }

  static _MoonInfo compute(DateTime nowUtc) {
    final e = _elong(nowUtc);
    final illum = ((1 - math.cos(e * math.pi / 180)) / 2 * 100).round();
    String phase;
    IconData icon;
    if (e < 6 || e >= 354) {
      phase = 'New Moon';
      icon = Icons.brightness_1_outlined;
    } else if (e < 84) {
      phase = 'Waxing Crescent';
      icon = Icons.brightness_3;
    } else if (e < 96) {
      phase = 'First Quarter';
      icon = Icons.brightness_2;
    } else if (e < 174) {
      phase = 'Waxing Gibbous';
      icon = Icons.brightness_2;
    } else if (e < 186) {
      phase = 'Full Moon';
      icon = Icons.brightness_1;
    } else if (e < 264) {
      phase = 'Waning Gibbous';
      icon = Icons.brightness_2;
    } else if (e < 276) {
      phase = 'Last Quarter';
      icon = Icons.brightness_2;
    } else {
      phase = 'Waning Crescent';
      icon = Icons.brightness_3;
    }
    final moonSid = PanchangCalculator.siderealMoon(nowUtc);
    return _MoonInfo(
      phase,
      icon,
      illum,
      (e / 360 * 29.53).floor(),
      kRashiNames[(moonSid / 30).floor() % 12],
      kNakshatraNames[(moonSid / (360 / 27)).floor() % 27],
      _nextElongation(nowUtc, 180),
      _nextElongation(nowUtc, 0),
    );
  }
}

/// Current planetary hour (Hora), computed from today's sunrise/sunset and refreshed every minute.
class _LiveHoraRow extends StatefulWidget {
  const _LiveHoraRow();

  @override
  State<_LiveHoraRow> createState() => _LiveHoraRowState();
}

class _LiveHoraRowState extends State<_LiveHoraRow> {
  Timer? _timer;

  static const List<String> _chaldean = ['Sun', 'Venus', 'Mercury', 'Moon', 'Saturn', 'Jupiter', 'Mars'];
  static const List<String> _dayLord = ['Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Sun']; // Mon..Sun
  static const Map<String, String> _info = {
    'Sun': 'Good for authority, government work, health and leadership.',
    'Moon': 'Good for travel, public dealings, emotions and nurturing.',
    'Mars': 'Good for courage, sports, property and decisive action.',
    'Mercury': 'Good for study, writing, communication and trade.',
    'Jupiter': 'Good for learning, finance, blessings and spiritual work.',
    'Venus': 'Good for love, art, beauty, luxury and harmony.',
    'Saturn': 'Good for hard work, discipline and long-term tasks.',
  };

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  (String, DateTime)? _currentHora() {
    try {
      const loc = kDefaultPanchangLocation;
      final now = DateTime.now().toUtc();
      var day = PanchangCalculator.todayAt(loc);
      var (rise, set) = PanchangCalculator.sunriseSunset(day, loc.latitude, loc.longitude);
      if (now.isBefore(rise)) {
        day = day.subtract(const Duration(days: 1));
        (rise, set) = PanchangCalculator.sunriseSunset(day, loc.latitude, loc.longitude);
      }
      final (nextRise, _) = PanchangCalculator.sunriseSunset(day.add(const Duration(days: 1)), loc.latitude, loc.longitude);

      final startIdx = _chaldean.indexOf(_dayLord[day.weekday - 1]);
      final isDay = now.isBefore(set);
      final segStart = isDay ? rise : set;
      final segEnd = isDay ? set : nextRise;
      final len = segEnd.difference(segStart).inMilliseconds / 12;
      if (len <= 0) return null;
      final idx = (now.difference(segStart).inMilliseconds / len).floor().clamp(0, 11);
      final horaNo = (isDay ? 0 : 12) + idx;
      final lord = _chaldean[(startIdx + horaNo) % 7];
      final end = segStart.add(Duration(milliseconds: (len * (idx + 1)).round()));
      return (lord, end);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hora = _currentHora();
    if (hora == null) return const SizedBox.shrink();
    final (lord, end) = hora;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TintIcon(Icons.schedule_rounded),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$lord Hora', style: AppText.bodyStrong),
                    const AppBadge(label: 'Live now', color: AppColors.success, icon: Icons.circle),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_info[lord] ?? '', style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                Text('Until ${PanchangCalculator.formatTime(end, kDefaultPanchangLocation)}', style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo tile in the Explore section: full-bleed picture, dark fade at the
/// bottom, a small frosted icon and the label. Shrinks slightly while pressed.
class _ExploreCard extends StatefulWidget {
  final String image;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool large;
  final Alignment alignment;
  final VoidCallback onTap;

  const _ExploreCard({
    required this.image,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.large = false,
    this.alignment = Alignment.center,
  });

  @override
  State<_ExploreCard> createState() => _ExploreCardState();
}

class _ExploreCardState extends State<_ExploreCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Material(
        color: AppColors.cosmic,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              widget.image,
              fit: BoxFit.cover,
              alignment: widget.alignment,
              cacheWidth: ((widget.large ? 220 : 140) * dpr).round(),
              errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.cosmic),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.45, 1],
                  colors: [Color(0x40110C30), Color(0x1A110C30), Color(0xE6110C30)],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Icon(widget.icon, size: 16, color: Colors.white),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.large ? 16 : 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted),
                    ),
                  ],
                ],
              ),
            ),
            Positioned.fill(
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (v) => setState(() => _pressed = v),
                splashColor: Colors.white.withValues(alpha: 0.12),
                highlightColor: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      label: widget.subtitle == null ? widget.title : '${widget.title}. ${widget.subtitle}',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.large ? SizedBox(height: 132 + (scale > 1 ? (scale - 1) * 60 : 0), child: card) : card,
      ),
    );
  }
}
