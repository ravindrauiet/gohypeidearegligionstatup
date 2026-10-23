import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/ui/app_ui.dart';
import '../consultation_lobby_screen.dart';
import '../seeker_session_chat_screen.dart';
import '../wallet_screen.dart';

/// "Ask Astro" marketplace: free AI astrologer personas plus real, paid live
/// pandits from `/pandit/list`.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  int _selectedFilterIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// (chip label, persona `field`, icon). Index 0 is "All".
  static const List<(String, String, IconData)> _categories = [
    ('Love', 'Love & Relationships', Icons.favorite_border_rounded),
    ('Career', 'Career & Wealth', Icons.work_outline_rounded),
    ('Kundli', 'Vedic Kundli', Icons.auto_awesome_outlined),
    ('Life guidance', '24/7 Guidance', Icons.self_improvement_rounded),
  ];

  /// Persona used by the "Ask our AI Astrologer" hero card.
  static const String _featuredAiId = '8';

  // Live human pandits (from /pandit/list) — separate from the free AI personas below.
  List<Map<String, dynamic>> _livePandits = [];
  bool _isLoadingPandits = true;
  bool _panditsLoadFailed = false;
  String? _panditsError;
  String? _requestingPanditId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLivePandits();
      _refreshWallet();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasWallet(BackendService s) => s.isAuthenticated || s.isGuestSession;

  /// Best-effort refresh of the wallet chip; failures keep the cached value.
  Future<void> _refreshWallet() async {
    if (!mounted) return;
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (!_hasWallet(backendService)) return;
    try {
      await backendService.fetchWalletBalance();
    } catch (_) {}
  }

  Future<void> _refreshAll() => Future.wait([_loadLivePandits(), _refreshWallet()]);

  Future<void> _loadLivePandits() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPandits = true;
      _panditsLoadFailed = false;
    });
    final backendService = Provider.of<BackendService>(context, listen: false);
    List<Map<String, dynamic>> list = const [];
    String? error;
    try {
      // Throws BackendException on failure; an empty list is a valid result.
      list = await backendService.fetchPanditsList();
    } on BackendException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load live pandits.';
    }
    if (!mounted) return;
    setState(() {
      if (error == null) _livePandits = list;
      _isLoadingPandits = false;
      _panditsLoadFailed = error != null;
      _panditsError = error;
    });
  }

  static double _toDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  // AI astrologer personas. All of them are served by the AI backend (/chat);
  // the UI labels them as AI so users are never misled into thinking they are
  // human. The map is passed as-is to /chatbot.
  final List<Map<String, dynamic>> _astrologers = [
    {
      'id': '1',
      'name': 'Priya Malhotra',
      'specialty': 'Love & Relationship Compatibility',
      'field': 'Love & Relationships',
      'rating': '4.9',
      'reviews': '1,840',
      'experience': '15 yrs exp',
      'avatarBg': AppColors.love,
      'imageUrl': 'assets/images/astrologers/priya_malhotra.jpg',
      'bio': 'Specialist in Kundli matching, soulmate connections & love transits.',
      'isOnline': true,
    },
    {
      'id': '2',
      'name': 'Acharya Dev Sharma',
      'specialty': 'Career & Financial Wealth',
      'field': 'Career & Wealth',
      'rating': '4.9',
      'reviews': '2,150',
      'experience': '18 yrs exp',
      'avatarBg': AppColors.primary,
      'imageUrl': 'assets/images/astrologers/dev_sharma.jpg',
      'bio': '10th House & D10 Dasamsha expert for job promotions, business & investments.',
      'isOnline': true,
    },
    {
      'id': '3',
      'name': 'Dr. Ananya Roy',
      'specialty': 'Love & Marriage Remedies',
      'field': 'Love & Relationships',
      'rating': '4.8',
      'reviews': '1,290',
      'experience': '12 yrs exp',
      'avatarBg': AppColors.info,
      'imageUrl': 'assets/images/astrologers/ananya_roy.jpg',
      'bio': 'Specialist in D9 Navamsha chart readings and romantic relationship alignment.',
      'isOnline': true,
    },
    {
      'id': '4',
      'name': 'Pandit Shastri',
      'specialty': 'Vedic Birth Chart & Kundli',
      'field': 'Vedic Kundli',
      'rating': '5.0',
      'reviews': '3,420',
      'experience': '22 yrs exp',
      'avatarBg': AppColors.gold,
      'imageUrl': 'assets/images/astrologers/pandit_shastri.jpg',
      'bio': 'Master in Janam Kundli, Lagna calculations, and Guna Milan analysis.',
      'isOnline': true,
    },
    {
      'id': '5',
      'name': 'Astro Maya',
      'specialty': '24/7 Life & Spiritual Guidance',
      'field': '24/7 Guidance',
      'rating': '4.9',
      'reviews': '1,950',
      'experience': '10 yrs exp',
      'avatarBg': AppColors.success,
      'imageUrl': 'assets/images/astrologers/astro_maya.jpg',
      'bio': 'Intuitive Tarot & Vedic astrologer for daily decision making & peace of mind.',
      'isOnline': true,
    },
    {
      'id': '6',
      'name': 'Guru Varma',
      'specialty': 'Career, Job Switch & Overseas Visas',
      'field': 'Career & Wealth',
      'rating': '4.8',
      'reviews': '1,480',
      'experience': '16 yrs exp',
      'avatarBg': AppColors.cosmicLight,
      'imageUrl': 'assets/images/astrologers/guru_varma.jpg',
      'bio': 'Guidance for job switches, foreign relocation, visas & promotions.',
      'isOnline': true,
    },
    {
      'id': '7',
      'name': 'Tarun Shastri',
      'specialty': 'Vimshottari Dasha & Remedies',
      'field': 'Vedic Kundli',
      'rating': '4.9',
      'reviews': '1,620',
      'experience': '14 yrs exp',
      'avatarBg': AppColors.cosmic,
      'imageUrl': 'assets/images/astrologers/tarun_shastri.jpg',
      'bio': 'Specialist in Rahu-Ketu remedies, gemstone selection & Sade Sati relief.',
      'isOnline': true,
    },
    {
      'id': '8',
      'name': 'Rishi Anand',
      'specialty': 'Instant 24/7 AI Astrologer Assistant',
      'field': '24/7 Guidance',
      'rating': '5.0',
      'reviews': '4,900',
      'experience': 'Instant AI',
      'avatarBg': AppColors.primary,
      'imageUrl': 'assets/images/astrologers/rishi_anand.jpg',
      'bio': 'Instant 24/7 personalized answers using your saved birth chart.',
      'isOnline': true,
    },
    {
      'id': '9',
      'name': 'Kavya Iyer',
      'specialty': 'Astrocartography & Relocation',
      'field': '24/7 Guidance',
      'rating': '4.8',
      'reviews': '890',
      'experience': '11 yrs exp',
      'avatarBg': AppColors.info,
      'imageUrl': 'assets/images/astrologers/kavya_iyer.jpg',
      'bio': 'Global relocation lines, planet MC/ASC aspects, and travel astrology.',
      'isOnline': true,
    },
    {
      'id': '10',
      'name': 'Siddharth Vedic Master',
      'specialty': 'Manglik & Kaal Sarp Dosha',
      'field': 'Vedic Kundli',
      'rating': '4.9',
      'reviews': '2,730',
      'experience': '20 yrs exp',
      'avatarBg': AppColors.primaryDark,
      'imageUrl': 'assets/images/astrologers/siddharth.jpg',
      'bio': 'Expert in resolving Manglik dosha, family harmony, and planetary pujas.',
      'isOnline': true,
    },
  ];

  bool _matchesQuery(Iterable<dynamic> fields) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return fields.any((f) => (f?.toString().toLowerCase() ?? '').contains(q));
  }

  List<Map<String, dynamic>> get _filteredAstrologers {
    final field = _selectedFilterIndex == 0 ? null : _categories[_selectedFilterIndex - 1].$2;
    return _astrologers
        .where((a) => field == null || a['field'] == field)
        .where((a) => _matchesQuery([a['name'], a['specialty'], a['field'], a['bio']]))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredPandits => _livePandits
      .where((p) => _matchesQuery([p['full_name'] ?? p['fullName'], p['specialty']]))
      .toList();

  /// Live pandit cards grow with the user's text size so nothing clips.
  double get _panditCardHeight => 120 + 56 * MediaQuery.textScalerOf(context).scale(1);

  void _openAi(Map<String, dynamic> astro) {
    Navigator.pushNamed(context, AppRoutes.chatbot, arguments: astro);
  }

  @override
  Widget build(BuildContext context) {
    final astrologers = _filteredAstrologers;
    final pandits = _filteredPandits;
    final searching = _query.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildTopBar()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
                  child: AppSearchBar(
                    hint: 'Search astrologers, love, career…',
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
              ),
              if (!searching) SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildFilterChips()),
              SliverToBoxAdapter(child: _buildLivePanditsSection(pandits)),
              const SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'AI astrologers',
                  subtitle: 'Free · instant replies · based on your Kundli',
                ),
              ),
              if (astrologers.isEmpty)
                SliverToBoxAdapter(
                  child: AppStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No astrologers match',
                    message: 'Try a different word or category.',
                    actionLabel: 'Clear filters',
                    compact: true,
                    onAction: () {
                      _searchController.clear();
                      setState(() {
                        _query = '';
                        _selectedFilterIndex = 0;
                      });
                    },
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  sliver: SliverList.separated(
                    itemCount: astrologers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _buildAstrologerCard(astrologers[i]),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final backend = Provider.of<BackendService>(context);
    final hasWallet = _hasWallet(backend);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xs),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ask Astro', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline),
                SizedBox(height: 2),
                Text(
                  'AI answers in seconds, or talk to a live pandit',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          if (hasWallet) ...[
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              button: true,
              label: 'Wallet balance ₹${backend.walletBalance.toStringAsFixed(0)}. Open wallet',
              excludeSemantics: true,
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () async {
                    await Navigator.pushNamed(context, AppRoutes.wallet);
                    if (mounted) _refreshWallet();
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        '₹${backend.walletBalance.toStringAsFixed(0)}',
                        style: AppText.bodyStrong,
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.add_rounded, size: 16, color: AppColors.textTertiary),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHero() {
    final featured = _astrologers.firstWhere((a) => a['id'] == _featuredAiId, orElse: () => _astrologers.first);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
      child: AppCard(
        gradient: AppColors.cosmicGradient,
        padding: EdgeInsets.zero,
        onTap: () => _openAi(featured),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Icon(Icons.auto_awesome_rounded, size: 140, color: Colors.white.withValues(alpha: 0.06)),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AppBadge(
                      label: 'AI · Free',
                      icon: Icons.auto_awesome_rounded,
                      color: AppColors.gold,
                      background: Colors.white.withValues(alpha: 0.12),
                    ),
                    const Spacer(),
                    AppAvatar(
                      imageUrl: featured['imageUrl']?.toString(),
                      name: featured['name']?.toString() ?? 'AI',
                      size: 40,
                      online: true,
                      color: Colors.white,
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Ask our AI Astrologer',
                    style: AppText.title.copyWith(color: AppColors.textOnDark, fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Free, instant answers from your Kundli. Career, marriage, money, health: just ask.',
                    style: AppText.body.copyWith(color: AppColors.textOnDarkMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Start free chat',
                    icon: Icons.chat_bubble_outline_rounded,
                    expand: false,
                    height: 44,
                    onPressed: () => _openAi(featured),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.pagePadding,
          itemCount: _categories.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            final label = index == 0 ? 'All' : _categories[index - 1].$1;
            final icon = index == 0 ? Icons.apps_rounded : _categories[index - 1].$3;
            return Center(
              child: AppFilterChip(
                label: label,
                icon: icon,
                selected: _selectedFilterIndex == index,
                onTap: () => setState(() => _selectedFilterIndex = index),
              ),
            );
          },
        ),
      ),
    );
  }

  // Live human Pandit consultations (paid, queue based)
  Widget _buildLivePanditsSection(List<Map<String, dynamic>> pandits) {
    Widget body;
    if (_isLoadingPandits && _livePandits.isEmpty) {
      body = SizedBox(
        height: _panditCardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: AppSpacing.pagePadding,
          itemCount: 2,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, __) => SkeletonBox(width: 264, height: _panditCardHeight, radius: AppRadius.lg),
        ),
      );
    } else if (_panditsLoadFailed && _livePandits.isEmpty) {
      body = Padding(
        padding: AppSpacing.pagePadding,
        child: AppCard(
          padding: EdgeInsets.zero,
          child: AppStateView.error(
            title: 'Could not load live pandits',
            message: _panditsError,
            compact: true,
            onAction: _loadLivePandits,
          ),
        ),
      );
    } else if (pandits.isEmpty) {
      body = Padding(
        padding: AppSpacing.pagePadding,
        child: AppCard(
          padding: EdgeInsets.zero,
          child: AppStateView(
            icon: Icons.person_search_rounded,
            title: _query.isNotEmpty ? 'No live pandit matches your search' : 'No live pandits right now',
            message: _query.isNotEmpty
                ? null
                : 'Our AI astrologers below are free and available any time.',
            actionLabel: 'Refresh',
            onAction: _loadLivePandits,
            compact: true,
          ),
        ),
      );
    } else {
      body = SizedBox(
        height: _panditCardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.pagePadding,
          itemCount: pandits.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) => _buildLivePanditCard(pandits[index]),
        ),
      );
    }

    final onlineCount = _livePandits
        .where((p) => p['is_online'] == true || p['isOnline'] == true)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Live pandits',
          subtitle: _isLoadingPandits && _livePandits.isEmpty
              ? 'Real human astrologers · paid per minute'
              : 'Real human astrologers · $onlineCount online now',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, AppRoutes.consultationHistory),
        ),
        body,
      ],
    );
  }

  Widget _buildLivePanditCard(Map<String, dynamic> pandit) {
    final id = pandit['id']?.toString() ?? '';
    final name = pandit['full_name']?.toString() ?? pandit['fullName']?.toString() ?? 'Pandit';
    final specialty = pandit['specialty']?.toString() ?? 'Vedic Astrology';
    final rate = _toDouble(pandit['rate_per_min'] ?? pandit['ratePerMin'], 21);
    final isOnline = pandit['is_online'] == true || pandit['isOnline'] == true;
    final isBusy = pandit['is_busy'] == true || pandit['isBusy'] == true;
    final waiting = int.tryParse(pandit['waiting_count']?.toString() ?? '') ?? 0;
    final avatarUrl = pandit['avatar_url']?.toString() ?? pandit['avatarUrl']?.toString() ?? '';
    final isRequesting = _requestingPanditId == id;

    final String statusText = !isOnline ? 'Offline' : (isBusy ? 'Busy · $waiting waiting' : 'Available now');
    final Color statusColor = !isOnline ? AppColors.textTertiary : (isBusy ? AppColors.warning : AppColors.success);
    final canRequest = isOnline && _requestingPanditId == null;
    final onTap = canRequest ? () => _startLiveConsultation(pandit) : null;

    return SizedBox(
      width: 264,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(imageUrl: avatarUrl, name: name, size: 48, online: isOnline && !isBusy),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                      const SizedBox(height: 2),
                      Text(specialty, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AppBadge(
                            label: 'Human · Live', icon: Icons.verified_user_outlined, color: AppColors.success),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Text('₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}/min', maxLines: 1, style: AppText.bodyStrong),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: !isOnline ? 'Offline' : (isBusy ? 'Join queue' : 'Chat now'),
              variant: isOnline ? AppButtonVariant.primary : AppButtonVariant.outline,
              height: 40,
              loading: isRequesting,
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAstrologerCard(Map<String, dynamic> astro) {
    final dynamic rawBg = astro['avatarBg'];
    final Color avatarColor = rawBg is Color ? rawBg : AppColors.cosmicLight;
    final String name = astro['name']?.toString() ?? 'Astrologer';
    final String rating = astro['rating']?.toString() ?? '';

    return Semantics(
      container: true,
      label: '$name, AI astrologer, ${astro['specialty'] ?? ''}',
      child: AppCard(
        onTap: () => _openAi(astro),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppAvatar(
              imageUrl: astro['imageUrl']?.toString(),
              name: name,
              size: 56,
              online: astro['isOnline'] == true,
              color: avatarColor,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                      ),
                      const SizedBox(width: 6),
                      const AppBadge(label: 'AI', icon: Icons.auto_awesome_rounded, color: AppColors.info),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    astro['specialty']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    astro['bio']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (rating.isNotEmpty) ...[RatingBadge(rating), const SizedBox(width: AppSpacing.xs)],
                      const Flexible(
                        child: Text(
                          'Free · replies instantly',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AppButton(
                label: 'Chat',
                variant: AppButtonVariant.secondary,
                expand: false,
                height: 40,
                onPressed: () => _openAi(astro),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Requests a live consultation with a real registered pandit: either starts an
  /// active session immediately or places the seeker in the waiting-queue lobby.
  Future<void> _startLiveConsultation(Map<String, dynamic> pandit) async {
    if (_requestingPanditId != null) return;
    final id = pandit['id'];
    final idStr = id?.toString() ?? '';
    final name = pandit['full_name']?.toString() ?? pandit['fullName']?.toString() ?? 'Pandit';
    final specialty = pandit['specialty']?.toString() ?? 'Vedic Advisor';
    final avatarUrl = pandit['avatar_url']?.toString() ?? '';
    final rate = _toDouble(pandit['rate_per_min'] ?? pandit['ratePerMin'], 21);

    setState(() => _requestingPanditId = idStr);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? result;
    try {
      result = await backendService.requestConsultation(panditId: id);
    } catch (e) {
      result = null;
    }
    if (!mounted) return;
    setState(() => _requestingPanditId = null);

    final error = result?['error']?.toString();
    final status = result?['status'];

    if (result == null || error != null) {
      if (error == 'INSUFFICIENT_BALANCE') {
        await _showInsufficientBalanceDialog(result!, name);
        return;
      }
      final message = (result?['message'] ?? backendService.lastError ?? 'Could not connect to $name. Please try again.').toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: error == 'PANDIT_OFFLINE' || error == 'SELF_CONSULTATION'
                ? null
                : SnackBarAction(label: 'Retry', onPressed: () => _startLiveConsultation(pandit)),
          ),
        );
      if (error == 'PANDIT_OFFLINE') _loadLivePandits();
      return;
    }

    if (status == 'active' && result['aiAstrologer'] == true) {
      // Not a registered human Pandit: served by the AI astrologer (free).
      Navigator.pushNamed(context, AppRoutes.chatbot, arguments: <String, dynamic>{
        'id': id,
        'name': name,
        'specialty': specialty,
        'field': pandit['field'],
        'imageUrl': avatarUrl,
        'ratePerMin': rate,
      });
    } else if (status == 'active') {
      final session = result['session'];
      showAppSnack(context, 'Connected to $name');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SeekerSessionChatScreen(
            session: session is Map ? Map<String, dynamic>.from(session) : const <String, dynamic>{},
            panditName: name,
            specialty: specialty,
            avatarUrl: avatarUrl,
            ratePerMin: rate,
          ),
        ),
      );
      if (mounted) _refreshAll();
    } else if (status == 'waiting') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConsultationLobbyScreen(
            initialQueueData: {
              ...?result,
              'panditName': name,
              'specialty': specialty,
              'avatarUrl': avatarUrl,
              'ratePerMin': rate,
            },
          ),
        ),
      );
      if (mounted) _refreshAll();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not connect to $name. Please try again.'),
            action: SnackBarAction(label: 'Retry', onPressed: () => _startLiveConsultation(pandit)),
          ),
        );
    }
  }

  Future<void> _showInsufficientBalanceDialog(Map<String, dynamic> result, String panditName) async {
    final balance = _toDouble(result['walletBalance'], 0);
    final rate = _toDouble(result['ratePerMin'], 0);
    final openWallet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 32),
        title: const Text('Low wallet balance'),
        content: Text(
          (result['message'] ??
                  'Your wallet balance (₹${balance.toStringAsFixed(2)}) is below $panditName\'s rate '
                      '(₹${rate.toStringAsFixed(2)}/min). Please recharge to start the consultation.')
              .toString(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Recharge wallet'),
          ),
        ],
      ),
    );
    if (openWallet != true || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
    if (mounted) _refreshWallet();
  }
}
