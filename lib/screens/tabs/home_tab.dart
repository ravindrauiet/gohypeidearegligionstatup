import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../config/home_promos.dart';
import '../../data/ai_astrologers.dart';
import '../../widgets/hindu_calendar_section.dart';
import '../../widgets/home/home_widgets.dart';
import '../../widgets/play_strip.dart';
import '../../widgets/promo_carousel.dart';
import '../../widgets/today_simple_card.dart';
import '../../widgets/ui/app_ui.dart';
import '../../widgets/your_day_card.dart';
import '../blog_detail_screen.dart';
import '../blog_screen.dart' show kCosmicGuideArticles;
import '../home_screen.dart';
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

  final ScrollController _scroll = ScrollController();

  /// True once the dark hero has scrolled away (switches the status-bar icons).
  bool _heroCollapsed = false;
  double _heroScrollable = 300;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
  static const List<String> _searchHints = [
    'when will I get married?',
    'is today good for me?',
    'how is my career this year?',
    'which gemstone suits me?',
    'what does my Dasha mean?',
  ];

  List<HomeShortcut> get _shortcuts => [
        HomeShortcut('Kundli', 'assets/images/topic_birth_chart.jpg', () => widget.onNavigateTab(_kChartTab)),
        HomeShortcut(
            'Horoscope', 'assets/images/topic_how_is_my_day.jpg', () => _route(AppRoutes.forecast, {'tab': 'day'})),
        HomeShortcut('Matching', 'assets/images/topic_love_compatibility.jpg', () => widget.onNavigateTab(_kLoveTab)),
        HomeShortcut('Panchang', 'assets/images/topic_moon_calendar.jpg', () => _route(AppRoutes.panchang)),
        HomeShortcut('Timeline', 'assets/images/topic_transits_today.jpg', () => _route(AppRoutes.lifeTimeline)),
        HomeShortcut('Why me?', 'assets/images/astrology-hero.jpg', () => _route(AppRoutes.dateExplorer)),
        HomeShortcut('Remedies', 'assets/images/Brihaspati.jpg', () => _route(AppRoutes.gemstoneRemedy)),
        HomeShortcut('Games', 'assets/images/heroBanner.jpg', () => _route(AppRoutes.games)),
      ];

  void _onScroll() {
    // Light status-bar icons over the dark hero, dark ones once it's gone.
    final collapsed = _scroll.hasClients && _scroll.offset > _heroScrollable - 8;
    if (collapsed != _heroCollapsed) setState(() => _heroCollapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final selfKundli = service.kundliData;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final scale = media.textScaler.scale(1).clamp(1.0, 1.6);

    // Hero = profile row + 2:1 promo slide + dots, with the pinned bar at its foot.
    final barHeight = HomeStickyBar.heightFor(context);
    final promoHeight = kHomePromos.isEmpty ? 0.0 : (width * 0.92 - 12) / 2 + 18;
    final heroContent = AppSpacing.xs + 52 * scale + AppSpacing.md + promoHeight + AppSpacing.md;
    _heroScrollable = heroContent;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _heroCollapsed ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: RefreshIndicator(
          color: AppColors.primary,
          edgeOffset: media.padding.top,
          onRefresh: _loadData,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 0,
                expandedHeight: heroContent + barHeight,
                backgroundColor: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.black26,
                elevation: 0,
                scrolledUnderElevation: 1,
                automaticallyImplyLeading: false,
                systemOverlayStyle: _heroCollapsed ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _hero(service, selfKundli, barHeight),
                ),
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(barHeight),
                  child: HomeStickyBar(
                    hints: _searchHints,
                    onSearch: () => _openAi(),
                    shortcuts: _shortcuts,
                  ),
                ),
              ),
              SliverList.list(
                children: [
                  // Quick asks (the filter-chip row).
                  _askSuggestions(),

                  // Your day.
                  const SectionHeader(title: 'In the spotlight', eyebrow: true),
                  Padding(padding: AppSpacing.pagePadding, child: YourDayCard(refreshTick: _refreshTick)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
                    child: PlayStrip(refreshTick: _refreshTick),
                  ),

                  // Astrologers: live pandits + AI personas.
                  SectionHeader(
                    title: 'Recommended for you',
                    eyebrow: true,
                    actionLabel: 'See all',
                    onAction: () => widget.onNavigateTab(_kChatTab),
                  ),
                  _recommended(),

                  // Today in plain words + planet weather.
                  const SectionHeader(title: 'Today for you', eyebrow: true),
                  Padding(padding: AppSpacing.pagePadding, child: TodaySimpleCard(refreshTick: _refreshTick)),

                  // Hindu calendar: today's festival / vrat and what's coming up.
                  HinduCalendarSection(refreshTick: _refreshTick),

                  // Panchang, hora and Moon.
                  SectionHeader(
                    title: "Today's sky",
                    eyebrow: true,
                    subtitle: 'Panchang for ${kDefaultPanchangLocation.name}',
                    actionLabel: 'Panchang',
                    onAction: () => _route(AppRoutes.panchang),
                  ),
                  Padding(padding: AppSpacing.pagePadding, child: _todaySkyCard()),

                  // Explore more.
                  const SectionHeader(title: 'Explore more', eyebrow: true),
                  _exploreMore(service),

                  // Calculators.
                  const SectionHeader(
                      title: 'Quick calculators', eyebrow: true, subtitle: 'Worked out from your birth details'),
                  _calculators(selfKundli),

                  // Articles feed.
                  SectionHeader(
                    title: 'Learn astrology',
                    eyebrow: true,
                    actionLabel: 'See all',
                    onAction: () => _route(AppRoutes.blog),
                  ),
                  _articlesFeed(),

                  const HomeFooter(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ hero
  Widget _hero(BackendService service, Map<String, dynamic>? selfKundli, double barHeight) {
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

    return HomeHeroHeader(
      title: firstName.isEmpty ? 'Namaste' : 'Hi, $firstName',
      subtitle: '${_greeting()} · $sub',
      avatarName: name,
      walletLabel: service.isAuthenticated ? '₹${service.walletBalance.toStringAsFixed(0)}' : null,
      onSwitchProfile: () => showKundliProfilePicker(context),
      onWallet: () => _route(AppRoutes.wallet),
      onProfile: () => _route(AppRoutes.profile),
      bottomInset: barHeight,
      banner: PromoCarousel(promos: kHomePromos, onTap: _openPromo),
    );
  }

  // ------------------------------------------------------------------ AI suggestions
  static const List<(String, IconData, String)> _suggestions = [
    ('Is today good?', Icons.wb_sunny_outlined, 'Is today a good day for me to start something new?'),
    ('Career', Icons.work_outline_rounded, 'How will my career go this year, based on my chart?'),
    ('Marriage', Icons.favorite_border_rounded, 'When is a good time for marriage in my chart?'),
    ('Money', Icons.savings_outlined, 'What does my chart say about money and savings right now?'),
    ('Health', Icons.spa_outlined, 'What should I take care of for my health, according to my chart?'),
  ];

  Widget _askSuggestions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
      child: Row(
        children: [
          for (final (label, icon, question) in _suggestions) ...[
            AppFilterChip(label: label, icon: icon, selected: false, onTap: () => _openAi(question)),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ recommended
  static double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  Widget _panditTile(Map<String, dynamic> p) {
    final name = (p['full_name'] ?? p['fullName'] ?? 'Pandit').toString();
    final avatar = (p['avatar_url'] ?? p['avatarUrl'] ?? '').toString();
    final online = p['is_online'] == true || p['isOnline'] == true;
    final busy = p['is_busy'] == true || p['isBusy'] == true;
    final rate = _num(p['rate_per_min'] ?? p['ratePerMin']);
    final rating = _num(p['rating']);
    final reviews = _num(p['total_reviews'] ?? p['totalReviews'])?.toInt() ?? 0;
    final (status, color, icon) = !online
        ? ('Offline', AppColors.textTertiary, Icons.schedule_rounded)
        : (busy
            ? ('Busy now', AppColors.warning, Icons.timelapse_rounded)
            : ('Online now', AppColors.success, Icons.bolt_rounded));
    return HomeAstroTile(
      name: name,
      // AppAvatar-style rule: the backend's old stock photo is not this person.
      imageUrl: avatar.contains('photo-1507003211169') ? null : avatar,
      tag: rate != null ? 'LIVE · ₹${rate.toStringAsFixed(0)}/min' : 'LIVE PANDIT',
      pill: rating != null && reviews > 0
          ? RatingBadge(rating.toStringAsFixed(1))
          : const AppBadge(label: 'New', color: Colors.white, background: AppColors.success),
      statusIcon: icon,
      status: status,
      statusColor: color,
      onTap: () => widget.onNavigateTab(_kChatTab),
    );
  }

  static String _shortField(String? field) {
    final f = (field ?? '').toLowerCase();
    if (f.contains('love')) return 'Love';
    if (f.contains('career')) return 'Career';
    if (f.contains('kundli')) return 'Kundli';
    return 'Guidance';
  }

  Widget _aiTile(Map<String, dynamic> a) {
    final name = a['name']?.toString() ?? 'AI Astrologer';
    return HomeAstroTile(
      name: name,
      imageUrl: a['imageUrl']?.toString(),
      tag: 'FREE · ${_shortField(a['field']?.toString())}',
      pill: const HomeAiPill(),
      statusIcon: Icons.bolt_rounded,
      status: 'Replies instantly',
      statusColor: AppColors.success,
      onTap: () => _route(AppRoutes.chatbot, a),
    );
  }

  Widget _recommended() {
    // Live pandits (online first), then the AI astrologers.
    final pandits = [..._pandits]..sort((a, b) {
        int rank(Map p) => (p['is_online'] == true || p['isOnline'] == true) ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
    final tiles = <Widget>[
      if (_panditsLoading && _pandits.isEmpty)
        for (var i = 0; i < 2; i++) const SkeletonBox(width: HomeAstroTile.width, height: 150, radius: AppRadius.lg),
      for (final p in pandits.take(4)) _panditTile(p),
      for (final a in kAiAstrologers) _aiTile(a),
    ];

    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final tileHeight = 104 + 14 + 40 * scale + 4;
    const rows = 2;
    final columns = (tiles.length / rows).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: tileHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var c = 0; c < columns; c++)
                        if (c * rows + r < tiles.length) ...[
                          if (c > 0) const SizedBox(width: AppSpacing.sm),
                          tiles[c * rows + r],
                        ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_panditsError != null && _pandits.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                const Expanded(child: Text("Couldn't load live pandits", style: AppText.caption)),
                TextButton(onPressed: _loadPandits, child: const Text('Retry')),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ explore more
  Widget _exploreMore(BackendService service) {
    final tiles = [
      HomeExploreMoreTile(
        icon: Icons.account_balance_wallet_rounded,
        label: service.isAuthenticated ? 'Add money\n₹${service.walletBalance.toStringAsFixed(0)}' : 'Wallet',
        color: AppColors.primary,
        onTap: () => _route(AppRoutes.wallet),
      ),
      HomeExploreMoreTile(
        icon: Icons.history_rounded,
        label: 'My\nconsultations',
        color: AppColors.info,
        onTap: () => _route(AppRoutes.consultationHistory),
      ),
      HomeExploreMoreTile(
        icon: Icons.groups_rounded,
        label: 'Family\nKundlis',
        color: AppColors.love,
        onTap: () => HomeScreen.switchTab(context, 2, targetSection: 'family'),
      ),
    ];
    return Padding(
      padding: AppSpacing.pagePadding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ articles
  static const List<String> _articleImages = [
    'assets/images/astrology.jpg',
    'assets/images/topic_transits_today.jpg',
    'assets/images/topic_moon_calendar.jpg',
    'assets/images/topic_how_is_my_day.jpg',
  ];

  Widget _articlesFeed() {
    final articles = kCosmicGuideArticles;
    if (articles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: AppSpacing.pagePadding,
      child: Column(
        children: [
          for (var i = 0; i < articles.length && i < 3; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            HomeFeedCard(
              image: _articleImages[i % _articleImages.length],
              tag: (articles[i].category ?? '').isEmpty ? 'Article' : articles[i].category!,
              title: articles[i].title,
              meta: (articles[i].readTime ?? '').isEmpty ? 'Read article' : articles[i].readTime!,
              onTap: () => _push(BlogDetailScreen(blogId: articles[i].id)),
            ),
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

