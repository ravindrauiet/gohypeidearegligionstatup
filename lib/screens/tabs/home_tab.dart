import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../blog_screen.dart';
import '../gemstone_remedy_screen.dart';
import '../kundli_view_screen.dart';
import '../panchang_screen.dart';
import '../wallet_screen.dart';
import '../../widgets/your_day_card.dart';

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
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;

  Map<String, dynamic>? _astroPulseData;
  List<Map<String, dynamic>> _starTalkPosts = [];
  bool _loading = false;
  bool _astroPulseFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_loading) return;
    final service = Provider.of<BackendService>(context, listen: false);
    setState(() {
      _loading = true;
      _astroPulseFailed = false;
    });

    Future<T?> safe<T>(Future<T> f) async {
      try {
        return await f;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait<dynamic>([
      safe(service.fetchAstroPulseToday()),
      safe(service.fetchStarTalkPosts()),
      if (service.isAuthenticated) safe(service.fetchWalletBalance()),
    ]);
    if (!mounted) return;

    final pulse = results[0];
    final posts = results[1];
    setState(() {
      _loading = false;
      if (pulse is Map) {
        _astroPulseData = Map<String, dynamic>.from(pulse);
      } else {
        _astroPulseFailed = _astroPulseData == null;
      }
      if (posts is List && posts.isNotEmpty) _starTalkPosts = Vedic.asMapList(posts);
    });
  }

  // ------------------------------------------------------------------ helpers
  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good Morning';
    if (h >= 12 && h < 17) return 'Good Afternoon';
    if (h >= 17 && h < 21) return 'Good Evening';
    return 'Good Night';
  }

  Map<String, int> _scores() {
    final raw = Vedic.asMap(_astroPulseData?['scores']);
    int v(String k, int d) => (Vedic.toInt(raw[k]) ?? d).clamp(0, 100);
    return {
      'love': v('love', 0),
      'career': v('career', 0),
      'health': v('health', v('wealth', 0)),
      'luck': v('luck', 0),
    };
  }

  List<Map<String, String>> _transits() {
    return Vedic.asMapList(_astroPulseData?['transits'])
        .map((t) => {'title': Vedic.text(t['title'], 'Transit'), 'aspect': Vedic.text(t['aspect'], '')})
        .toList();
  }

  void _openChat(String name, String specialty, String field, String message) {
    Navigator.pushNamed(context, '/chatbot', arguments: {
      'name': name,
      'specialty': specialty,
      'field': field,
      'initialMessage': message,
    });
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final selfKundli = service.kundliData;
    final name = Vedic.displayName(selfKundli, service: service);
    final moonSign = Vedic.text(selfKundli?['moonSign'], '');

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showKundliProfilePicker(context),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.black, fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Hi, ${_greeting()}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Material(
            color: const Color(0xFF6B1A3A),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _push(const WalletScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '₹${service.walletBalance.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Birth details',
            icon: const Icon(Icons.manage_accounts_outlined, color: Colors.black),
            onPressed: () => Navigator.pushNamed(context, '/birth-details'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0. Personal forecast: Your Day (+ Life Timeline / Why did this happen?)
              const YourDayCard(),
              const SizedBox(height: 24),

              // 1. Promo banners
              SizedBox(
                height: 150,
                child: PageView(
                  controller: _bannerController,
                  onPageChanged: (index) => setState(() => _currentBannerIndex = index),
                  children: [
                    _buildPromoBannerCard(
                      title: 'Chat with an AI\nVedic astrologer',
                      buttonText: 'Start chatting',
                      icon: Icons.forum_rounded,
                      gradientColors: const [Color(0xFF0F0826), Color(0xFF27134A)],
                      onTap: () => widget.onNavigateTab(_kChatTab),
                    ),
                    _buildPromoBannerCard(
                      title: 'Unlock your\ndaily chart insight',
                      buttonText: 'View transits',
                      icon: Icons.auto_graph_rounded,
                      gradientColors: const [Color(0xFF1E0E3D), Color(0xFF4A1F78)],
                      onTap: () => _showAstroPulseDetailModal(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (index) {
                  final isSelected = _currentBannerIndex == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isSelected ? 14 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF6B6B) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 24),

              // 2. AstroPulse
              _buildAstroPulseSection(),

              const SizedBox(height: 18),

              // 3. Today's Panchang
              _buildTodayPanchangCard(),

              const SizedBox(height: 28),

              // 4. Chat with astrologers
              _sectionHeader('Chat with Astrologers', actionLabel: 'See All', onAction: () => widget.onNavigateTab(_kChatTab)),
              const SizedBox(height: 16),
              SizedBox(
                height: 284,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  children: [
                    _buildAstrologerCard(
                      name: 'Mira Solis',
                      specialty: 'Western Astrologer',
                      rating: '4.8 (982)',
                      originalPrice: '₹98',
                      discountPrice: '₹49',
                      showOffer: true,
                      imageUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=300&q=80',
                      avatarBg: const Color(0xFFFFF3E0),
                    ),
                    const SizedBox(width: 14),
                    _buildAstrologerCard(
                      name: 'Pt. Rishiraj Tiwari',
                      specialty: 'Vedic Astrologer',
                      rating: '4.8 (769)',
                      imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
                      avatarBg: const Color(0xFFFFE0B2),
                    ),
                    const SizedBox(width: 14),
                    _buildAstrologerCard(
                      name: 'Elena Meridian',
                      specialty: 'Relationship Astrologer',
                      rating: '4.9 (540)',
                      imageUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=300&q=80',
                      avatarBg: const Color(0xFFF3E5F5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 5. Charts grid
              _sectionHeader('Charts & Tools'),
              const SizedBox(height: 18),
              _iconGrid([
                _GridItem(
                    'Natal\nChart', Icons.pie_chart_outline_rounded, const [Color(0xFF6C63FF), Color(0xFF9A94FF)], () => widget.onNavigateTab(_kChartTab)),
                _GridItem('Synastry', Icons.favorite_rounded, const [Color(0xFFFF4766), Color(0xFFFF8597)], () => widget.onNavigateTab(_kLoveTab)),
                _GridItem('Panchang', Icons.wb_sunny_rounded, const [Color(0xFFFB8C00), Color(0xFFFFB74D)], () => _push(const PanchangScreen())),
                _GridItem('Vedic\nKundli', Icons.menu_book_rounded, const [Color(0xFFD95D39), Color(0xFFFF8A65)], () => _push(const KundliViewScreen()),
                    sparkle: true),
                _GridItem('Gemstones', Icons.diamond_rounded, const [Color(0xFF2563EB), Color(0xFF60A5FA)], () => _push(const GemstoneRemedyScreen())),
                _GridItem('Dasha\nTimeline', Icons.hourglass_bottom_rounded, const [Color(0xFF8E24AA), Color(0xFFCE93D8)],
                    () => _push(const KundliViewScreen(initialTab: 3))),
                _GridItem('Horoscope', Icons.stars_rounded, const [Color(0xFFF59E0B), Color(0xFFFCD34D)], () => _showAstroPulseDetailModal(context),
                    sparkle: true),
                _GridItem('Moon\nCalendar', Icons.nightlight_round, const [Color(0xFF512DA8), Color(0xFF9575CD)], () => _showMoonCalendarModal(context)),
              ]),

              const SizedBox(height: 32),

              // 6. Star Talk
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('COMMUNITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                        SizedBox(height: 2),
                        Text('Star Talk', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.black)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _showStarTalkInfo,
                    child: const Text('What is it?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildStarTalkList(),

              const SizedBox(height: 32),

              // 7. Moon Shine
              _sectionHeader("Today's Moon Shine", actionLabel: 'View', onAction: () => _showMoonCalendarModal(context)),
              const SizedBox(height: 16),
              _buildMoonShineCard(),

              const SizedBox(height: 24),

              // 8. Planetary hour
              const _LiveHoraCard(),

              const SizedBox(height: 28),

              // 9. Couples promo
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF27094B), Color(0xFF67145F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, height: 1.25),
                        children: [
                          TextSpan(text: 'Someone keeping you up '),
                          TextSpan(text: 'lately?', style: TextStyle(color: Color(0xFFFF6B81))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Find out why. Compare your charts and read it together.', style: TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => widget.onNavigateTab(_kLoveTab),
                      icon: const Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
                      label: const Text('Try Coupled', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE83D66),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 10. Compatibility
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    const Text(
                      '💕 Cosmic Compatibility',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'See how your charts align – emotional, physical and karmic connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildMatchAvatar(name.isNotEmpty ? name[0].toUpperCase() : '?', 'You'),
                        const SizedBox(width: 16),
                        const Icon(Icons.favorite_rounded, color: Color(0xFFE83D66), size: 28),
                        const SizedBox(width: 16),
                        _buildMatchAvatar('?', 'Partner'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => widget.onNavigateTab(_kLoveTab),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF8BBD0),
                          foregroundColor: const Color(0xFFC2185B),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('See Your Match', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 11. Community mood
              _sectionHeader('${moonSign.isNotEmpty ? moonSign : 'Community'} Moons · Today'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildCommunityMetric(Icons.bolt_rounded, const Color(0xFF00B074), '60%', 'Intense')),
                    Expanded(child: _buildCommunityMetric(Icons.emoji_objects_rounded, const Color(0xFF7032D9), '61%', 'Reflective')),
                    Expanded(child: _buildCommunityMetric(Icons.local_fire_department_rounded, const Color(0xFFE83D66), '68%', 'Motivated')),
                    Expanded(child: _buildCommunityMetric(Icons.battery_charging_full_rounded, const Color(0xFFE53935), '67%', 'Energy')),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Community mood check-in from ${moonSign.isNotEmpty ? '$moonSign Moon' : 'CosmicGuide'} members today',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: Color(0xFFD95D39)),
              ),

              const SizedBox(height: 32),

              // 12. Calculators
              _sectionHeader('Astrological Calculators'),
              const SizedBox(height: 18),
              _iconGrid([
                _GridItem('Big 3', Icons.format_size_rounded, const [Color(0xFF1976D2), Color(0xFF64B5F6)], () => _showBigThree(selfKundli)),
                _GridItem('Know Your\nNodes', Icons.hub_rounded, const [Color(0xFF7B1FA2), Color(0xFFE1BEE7)], () => _showNodes(selfKundli)),
                _GridItem('Lo Shu\nGrid', Icons.grid_on_rounded, const [Color(0xFF6A1B9A), Color(0xFFE1BEE7)], () => _showLoShu(selfKundli)),
                _GridItem('Know Your\nNumbers', Icons.casino_rounded, const [Color(0xFF1E88E5), Color(0xFF90CAF9)], () => _showNumbers(selfKundli)),
                _GridItem('Chinese\nZodiac', Icons.calculate_rounded, const [Color(0xFFE64A19), Color(0xFFFFAB91)], () => _showChinese(selfKundli)),
                const _GridItem('Black Moon\nLilith', Icons.bedtime_rounded, [Color(0xFF512DA8), Color(0xFFB39DDB)], null),
                const _GridItem('Juno', Icons.auto_awesome_rounded, [Color(0xFFF57C00), Color(0xFFFFCC80)], null),
                const _GridItem("Where's\nChiron", Icons.vpn_key_rounded, [Color(0xFFF57F17), Color(0xFFFFE082)], null),
              ]),

              const SizedBox(height: 32),

              // 13. Reports
              _sectionHeader('Reports'),
              const SizedBox(height: 16),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _push(const KundliViewScreen(initialTab: KundliExplorer.reportTab)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 84,
                          height: 112,
                          decoration: BoxDecoration(color: const Color(0xFF1A1A3A), borderRadius: BorderRadius.circular(12)),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 26),
                              SizedBox(height: 6),
                              Text(
                                'BIRTH CHART\nREPORT',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Full Life Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                              const SizedBox(height: 4),
                              Text(
                                'Personality, health, career, marriage and your running dasha – from your exact birth chart.',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
                              ),
                              const SizedBox(height: 8),
                              const Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '₹1999  ',
                                      style: TextStyle(fontSize: 13, color: Colors.grey, decoration: TextDecoration.lineThrough),
                                    ),
                                    TextSpan(
                                      text: 'FREE (Included)',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF00B074)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 14. Blogs
              _sectionHeader('Blogs', actionLabel: 'See All', onAction: () => _push(const BlogScreen())),
              const SizedBox(height: 16),
              _buildBlogCard(
                category: 'Birth Chart',
                title: "Why ChatGPT Can't Actually Read Your Birth Chart",
                meta: '5 min read',
                imageUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=300&q=80',
                bgColor: const Color(0xFF6B124B),
              ),
              const SizedBox(height: 14),
              _buildBlogCard(
                category: 'Transit',
                title: 'Jupiter Transits: A Rising Sign Guide for All 12 Ascendants',
                meta: '4 min read',
                imageUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=300&q=80',
                bgColor: const Color(0xFF1E3A8A),
              ),
              const SizedBox(height: 14),
              _buildBlogCard(
                category: 'Transit',
                title: 'What A Retrograde Really Means In Astrology (And How to Survive It)',
                meta: '6 min read',
                imageUrl: 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=300&q=80',
                bgColor: const Color(0xFF7C3AED),
              ),

              const SizedBox(height: 40),

              // 15. Footer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8F0FE), Color(0xFFEADCF8), Color(0xFFD8C2F8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.black, height: 1.15),
                        children: [
                          TextSpan(text: 'Follow\nyour '),
                          TextSpan(text: 'stars!', style: TextStyle(color: Color(0xFFE83D66))),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CosmicGuide',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1.0,
                          shadows: [Shadow(color: Colors.black26, blurRadius: 10)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ sections
  Widget _sectionHeader(String title, {String? actionLabel, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.black),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
          ),
      ],
    );
  }

  Widget _buildAstroPulseSection() {
    final data = _astroPulseData;
    if (data == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.grey.shade200)),
        child: _astroPulseFailed && !_loading
            ? Column(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Colors.grey, size: 36),
                  const SizedBox(height: 8),
                  const Text("Couldn't load today's AstroPulse.", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                ],
              )
            : const Column(
                children: [
                  SizedBox(height: 8),
                  CircularProgressIndicator(color: Color(0xFFE83D66)),
                  SizedBox(height: 12),
                  Text('Reading today\'s planetary transits…', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  SizedBox(height: 8),
                ],
              ),
      );
    }

    final transits = _transits();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AstroPulse · Today', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 32, height: 1.1),
            children: [
              TextSpan(
                text: '${Vedic.text(data['headlineMain'], 'Your Day')}\n',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
              ),
              TextSpan(
                text: Vedic.text(data['headlineSub'], 'Ahead'),
                style: const TextStyle(color: Color(0xFFD95D39), fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          Vedic.text(data['summary'], ''),
          style: TextStyle(fontSize: 15, color: Colors.grey.shade700, height: 1.4),
        ),
        if (transits.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...transits.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildTransitRow(t['title']!, t['aspect']!),
              )),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: () => _showAstroPulseDetailModal(context),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Explore AstroPulse'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE83D66),
              foregroundColor: Colors.white,
              elevation: 0,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildDailyAstroPulseProgressMeters(_scores()),
      ],
    );
  }

  Widget _buildTransitRow(String name, String symbols) {
    return Row(
      children: [
        Flexible(
          child: Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey.shade800)),
        ),
        if (symbols.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(symbols, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ],
    );
  }

  void _showAstroPulseDetailModal(BuildContext context) {
    if (_astroPulseData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loading ? 'Still loading today\'s AstroPulse…' : 'AstroPulse is unavailable. Pull down to retry.'),
          action: _loading ? null : SnackBarAction(label: 'Retry', onPressed: _loadData),
        ),
      );
      return;
    }
    final scores = _scores();
    final forecast = Vedic.asMap(_astroPulseData?['detailedForecast']);
    final transits = _transits();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.88),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFFE83D66), size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('AstroPulse · Today', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetContext)),
                    ],
                  ),
                  Text(
                    'Daily transit analysis for your birth chart.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _buildScorePill('Love', scores['love']!, Colors.pink)),
                      Expanded(child: _buildScorePill('Career', scores['career']!, Colors.orange)),
                      Expanded(child: _buildScorePill('Health', scores['health']!, Colors.green)),
                      Expanded(child: _buildScorePill('Luck', scores['luck']!, Colors.purple)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _forecastBlock('💼 Career', Vedic.text(forecast['career'], 'No career insight for today.')),
                  _forecastBlock('💖 Love & Relationships', Vedic.text(forecast['love'], 'No relationship insight for today.')),
                  _forecastBlock('🕉️ Today\'s Vedic Remedy', Vedic.text(forecast['remedies'], 'Recite the Gayatri Mantra at sunrise.')),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _openChat(
                          'AstroPulse Today Advisor',
                          'Daily Transit Guidance',
                          'Daily Horoscope',
                          transits.isNotEmpty
                              ? 'Explain today\'s ${transits.first['title']} transit and how it affects my birth chart.'
                              : 'Explain today\'s planetary transits and how they affect my birth chart.',
                        );
                      },
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Ask AI about today\'s transits', overflow: TextOverflow.ellipsis),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C77E6),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _forecastBlock(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: Colors.grey.shade800, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildScorePill(String label, int val, Color color) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Text('$val%', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildDailyAstroPulseProgressMeters(Map<String, int> scores) {
    String note(int v) => v >= 85 ? 'Excellent' : (v >= 70 ? 'Favourable' : (v >= 50 ? 'Mixed' : 'Go slow'));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text('DAILY ASTRO PULSE METRICS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0)),
              ),
              Icon(Icons.auto_graph_rounded, color: Color(0xFFE83D66), size: 18),
            ],
          ),
          const SizedBox(height: 16),
          _buildMetricBar('❤️ Love', scores['love']!, note(scores['love']!), const Color(0xFFE83D66)),
          const SizedBox(height: 12),
          _buildMetricBar('💼 Career', scores['career']!, note(scores['career']!), const Color(0xFFFF9800)),
          const SizedBox(height: 12),
          _buildMetricBar('🩺 Health', scores['health']!, note(scores['health']!), const Color(0xFF059669)),
          const SizedBox(height: 12),
          _buildMetricBar('🌟 Luck', scores['luck']!, note(scores['luck']!), const Color(0xFF9C27B0)),
        ],
      ),
    );
  }

  Widget _buildMetricBar(String label, int pct, String note, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
            ),
            Text('$pct% · $note', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.grey.shade200,
            color: color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildTodayPanchangCard() {
    DailyPanchang? p;
    try {
      p = PanchangCalculator.cached(PanchangCalculator.todayAt(kDefaultPanchangLocation));
    } catch (_) {
      p = null;
    }
    const loc = kDefaultPanchangLocation;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _push(const PanchangScreen()),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFD700), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "TODAY'S PANCHANG & MUHURAT",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                ],
              ),
              const SizedBox(height: 10),
              if (p == null)
                const Text('Tap to open the Panchang', style: TextStyle(color: Colors.white))
              else ...[
                Text(
                  '${p.paksha} ${p.tithi.name} · ${p.nakshatra.name}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _panchangStat('Rahu Kaal', PanchangCalculator.formatWindow(p.rahuKaal, loc), Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(child: _panchangStat('Abhijit Muhurat', PanchangCalculator.formatWindow(p.abhijit, loc), const Color(0xFFFFD700))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _panchangStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildPromoBannerCard({
    required String title,
    required String buttonText,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.25),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFB085FF), Color(0xFF804BFF)]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(buttonText, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: const Color(0xFFFFD700), size: 44),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAstrologerCard({
    required String name,
    required String specialty,
    required String rating,
    required String imageUrl,
    required Color avatarBg,
    String? originalPrice,
    String? discountPrice,
    bool showOffer = false,
  }) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 26,
            child: showOffer ? const _OfferCountdown(initialSeconds: 1731) : null,
          ),
          ClipOval(
            child: Container(
              width: 70,
              height: 70,
              color: avatarBg,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: discountPrice != null
                ? Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'From ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        TextSpan(
                          text: '${originalPrice ?? ''} ',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough),
                        ),
                        TextSpan(text: discountPrice, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                    maxLines: 1,
                  )
                : null,
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(specialty,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(rating, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: () => _openChat(
                name,
                specialty,
                'Vedic Consultation',
                'Namaste! I am $name. How can I guide you with your birth chart today?',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE83D66),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Chat Now', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconGrid(List<_GridItem> items) {
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 10.0;
      final itemW = (constraints.maxWidth - spacing * 3) / 4;
      final iconSize = itemW.clamp(44.0, 62.0);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: spacing,
          mainAxisSpacing: 16,
          mainAxisExtent: iconSize + 44,
        ),
        itemBuilder: (context, i) => _build3DChartItem(items[i], iconSize),
      );
    });
  }

  Widget _build3DChartItem(_GridItem item, double size) {
    final enabled = item.onTap != null;
    final mainColor = item.colors.first;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled
            ? item.onTap
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${item.label.replaceAll('\n', ' ')} is coming soon.')),
                ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: item.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(size * 0.35),
                    boxShadow: [
                      BoxShadow(color: mainColor.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 1, offset: const Offset(0, 5)),
                    ],
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Center(child: Icon(item.icon, color: Colors.white, size: size * 0.45)),
                ),
                if (item.sparkle && enabled)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Color(0xFFFFD700), shape: BoxShape.circle),
                      child: const Icon(Icons.auto_awesome, color: Colors.black, size: 10),
                    ),
                  ),
                if (!enabled)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: const Text('Soon', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ star talk
  Widget _buildStarTalkList() {
    if (_starTalkPosts.isEmpty) {
      return Container(
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(12),
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
        child: _loading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('No community posts right now.', style: TextStyle(color: Colors.grey.shade600)),
                  TextButton(onPressed: _loadData, child: const Text('Refresh')),
                ],
              ),
      );
    }
    const bgs = [Color(0xFFDCEDC8), Color(0xFFE1BEE7), Color(0xFFFFECB3)];
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _starTalkPosts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final post = _starTalkPosts[index];
          return _buildStarTalkPost(
            handle: Vedic.text(post['handle'], 'stargazer'),
            glyphs: Vedic.text(post['glyphs'], ''),
            text: Vedic.text(post['text'], ''),
            likes: Vedic.toInt(post['likes']) ?? 0,
            comments: Vedic.toInt(post['comments']) ?? 0,
            avatarBg: bgs[index % bgs.length],
          );
        },
      ),
    );
  }

  Widget _buildStarTalkPost({
    required String handle,
    required String glyphs,
    required String text,
    required int likes,
    required int comments,
    required Color avatarBg,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: avatarBg,
                child: Text(handle.isNotEmpty ? handle[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(handle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    if (glyphs.isNotEmpty)
                      Text(glyphs, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.favorite_border_rounded, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('$likes', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 14),
              const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('$comments', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  void _showStarTalkInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What is Star Talk?'),
        content: const Text(
          'Star Talk is where CosmicGuide members share how today\'s transits are showing up in their lives. '
          'The glyphs show each member\'s Sun ☉, Moon ☽ and Rising ↑ signs.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
      ),
    );
  }

  // ------------------------------------------------------------------ moon
  _MoonInfo _moonNow() => _MoonInfo.compute(DateTime.now().toUtc());

  Widget _buildMoonShineCard() {
    final m = _moonNow();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2C2C2E),
                  boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.4), blurRadius: 12)],
                ),
                child: Center(child: Icon(m.icon, color: const Color(0xFFFFF7ED), size: 46)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.phase, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.black)),
                    const SizedBox(height: 2),
                    Text(
                      'Moon in ${m.rashi}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: Color(0xFFD95D39)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildMoonStat('${m.illumination}%', 'LIT')),
                        Expanded(child: _buildMoonStat(DateFormat('d MMM').format(m.nextFullMoon.toLocal()), 'FULL')),
                        Expanded(child: _buildMoonStat('${m.ageDays}d', 'AGE')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(width: 3, height: 32, color: const Color(0xFFD95D39)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The Moon is ${m.phase.toLowerCase()} (${m.illumination}% lit) in ${m.nakshatra} Nakshatra, ${m.rashi}.',
                  style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoonStat(String val, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(val, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _showMoonCalendarModal(BuildContext context) {
    final now = DateTime.now().toUtc();
    final m = _MoonInfo.compute(now);
    final fmt = DateFormat('EEE, d MMM');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.nightlight_round, color: Color(0xFF673AB7), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(child: Text("Today's Moon Calendar", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetContext)),
                  ],
                ),
                Text('${m.phase} in ${m.rashi}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD95D39))),
                const SizedBox(height: 6),
                Text(
                  '${m.illumination}% illuminated · ${m.nakshatra} Nakshatra · ${m.ageDays} days since New Moon',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                _moonRow(Icons.brightness_1_rounded, 'Next Full Moon (Purnima)', fmt.format(m.nextFullMoon.toLocal())),
                _moonRow(Icons.brightness_1_outlined, 'Next New Moon (Amavasya)', fmt.format(m.nextNewMoon.toLocal())),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _push(const PanchangScreen());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF673AB7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Open Panchang Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _moonRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF673AB7)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ misc widgets
  Widget _buildCommunityMetric(IconData icon, Color color, String val, String label) {
    return Column(
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 8),
        Text(val, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildBlogCard({
    required String category,
    required String title,
    required String meta,
    required String imageUrl,
    required Color bgColor,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _push(const BlogScreen()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 76,
                  height: 76,
                  color: bgColor,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.article_rounded, color: Colors.white, size: 34)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black, height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(meta, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchAvatar(String label, String sub) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFFCF7F1), shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300)),
          child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
        ),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  // ------------------------------------------------------------------ calculators
  DateTime? _birthDate(Map<String, dynamic>? kundli) {
    if (kundli == null) return null;
    final utc = Vedic.birthUtc(kundli);
    if (utc == null) return null;
    final ist = utc.add(const Duration(hours: 5, minutes: 30));
    return DateTime(ist.year, ist.month, ist.day);
  }

  void _needBirthDetails() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Add your birth details first.'),
        action: SnackBarAction(label: 'Add', onPressed: () => Navigator.pushNamed(context, '/birth-details')),
      ),
    );
  }

  void _showInfoSheet(String title, IconData icon, List<Widget> children) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: const Color(0xFF6C63FF)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetContext)),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _factRow(String label, String value, {String? sub}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFCF7F1), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFD95D39))),
        ],
      ),
    );
  }

  void _showBigThree(Map<String, dynamic>? kundli) {
    if (kundli == null || Vedic.signIndex(kundli['ascendant']) < 0) return _needBirthDetails();
    _showInfoSheet('Your Big 3 (Vedic)', Icons.format_size_rounded, [
      _factRow('Sun sign ☉', Vedic.text(kundli['sunSign']), sub: 'Soul, ego and vitality'),
      _factRow('Moon sign ☽', Vedic.text(kundli['moonSign']), sub: 'Mind, emotions – the key sign in Vedic astrology'),
      _factRow('Ascendant ↑', Vedic.text(kundli['ascendant']), sub: 'Body, personality and life direction'),
      Text('Sidereal (Lahiri) signs – these can differ from Western tropical signs by about one sign.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
    _showInfoSheet('Your Lunar Nodes', Icons.hub_rounded, [
      _factRow('Rahu ☊ (North Node)', '${Vedic.text(rahu['sign'])} · H${Vedic.text(rahu['house'])}',
          sub: 'Worldly desires and growth: ${kHouseMeanings[Vedic.toInt(rahu['house'])] ?? ''}'),
      _factRow('Ketu ☋ (South Node)', '${Vedic.text(ketu['sign'])} · H${Vedic.text(ketu['house'])}',
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

    _showInfoSheet('Lo Shu Grid', Icons.grid_on_rounded, [
      Text('Born ${DateFormat('d MMM yyyy').format(dob)} · Driver $driver · Conductor $conductor', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
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
                  color: c > 0 ? const Color(0xFF6C63FF).withValues(alpha: 0.12) : const Color(0xFFFCF7F1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c > 0 ? const Color(0xFF6C63FF) : Colors.grey.shade300),
                ),
                child: Text(
                  c > 0 ? List.filled(c, '$n').join() : '–',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c > 0 ? const Color(0xFF4A44A8) : Colors.grey),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        missing.isEmpty ? 'No missing numbers – a well-balanced grid.' : 'Missing numbers: ${missing.join(', ')}',
        style: const TextStyle(fontWeight: FontWeight.bold),
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
    _showInfoSheet('Know Your Numbers', Icons.casino_rounded, [
      _factRow('Mulank (Psychic number)', '$mulank', sub: 'From your birth day – how you see yourself'),
      _factRow('Bhagyank (Destiny number)', '$bhagyank', sub: 'From your full date of birth – your life path'),
      if (nameSum > 0) _factRow('Name number (Chaldean)', '${_reduce(nameSum)}', sub: 'Compound $nameSum · from "${Vedic.displayName(kundli)}"'),
    ]);
  }

  void _showChinese(Map<String, dynamic>? kundli) {
    final dob = _birthDate(kundli);
    if (dob == null) return _needBirthDetails();
    const animals = ['Rat', 'Ox', 'Tiger', 'Rabbit', 'Dragon', 'Snake', 'Horse', 'Goat', 'Monkey', 'Rooster', 'Dog', 'Pig'];
    const elements = ['Metal', 'Metal', 'Water', 'Water', 'Wood', 'Wood', 'Fire', 'Fire', 'Earth', 'Earth'];
    String sign(int year) => '${elements[year % 10]} ${animals[((year - 4) % 12 + 12) % 12]}';
    final early = dob.month == 1 || (dob.month == 2 && dob.day < 20);
    _showInfoSheet('Chinese Zodiac', Icons.calculate_rounded, [
      _factRow('Your sign', sign(dob.year), sub: 'Based on birth year ${dob.year}'),
      if (early)
        Text(
          'You were born before late February. If your birthday falls before Chinese New Year of ${dob.year}, your sign is ${sign(dob.year - 1)}.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
    ]);
  }
}

// ============================================================================
// Helper types & small stateful widgets
// ============================================================================

class _GridItem {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  final bool sparkle;

  const _GridItem(this.label, this.icon, this.colors, this.onTap, {this.sparkle = false});
}

/// Self-contained countdown so the whole home tab doesn't rebuild every second.
class _OfferCountdown extends StatefulWidget {
  final int initialSeconds;
  const _OfferCountdown({required this.initialSeconds});

  @override
  State<_OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<_OfferCountdown> {
  late int _seconds = widget.initialSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds <= 0) {
        t.cancel();
        return;
      }
      setState(() => _seconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ended = _seconds <= 0;
    final h = _seconds ~/ 3600, m = (_seconds % 3600) ~/ 60, s = _seconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ended ? Colors.grey : const Color(0xFF00B074),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          ended ? 'Offer ended' : 'Offer ends in ${two(h)}:${two(m)}:${two(s)}',
          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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

  const _MoonInfo(this.phase, this.icon, this.illumination, this.ageDays, this.rashi, this.nakshatra, this.nextFullMoon, this.nextNewMoon);

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
class _LiveHoraCard extends StatefulWidget {
  const _LiveHoraCard();

  @override
  State<_LiveHoraCard> createState() => _LiveHoraCardState();
}

class _LiveHoraCardState extends State<_LiveHoraCard> {
  Timer? _timer;

  static const List<String> _chaldean = ['Sun', 'Venus', 'Mercury', 'Moon', 'Saturn', 'Jupiter', 'Mars'];
  static const List<String> _dayLord = ['Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Sun']; // Mon..Sun
  static const Map<String, List<String>> _info = {
    'Sun': ['☉', 'Authority, government work, health and leadership.'],
    'Moon': ['☽', 'Travel, public dealings, emotions and nurturing.'],
    'Mars': ['♂', 'Courage, sports, property and decisive action.'],
    'Mercury': ['☿', 'Study, writing, communication and trade.'],
    'Jupiter': ['♃', 'Learning, finance, blessings and spiritual work.'],
    'Venus': ['♀', 'Love, art, beauty, luxury and harmony.'],
    'Saturn': ['♄', 'Hard work, discipline and long-term tasks.'],
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
  }

  @override
  Widget build(BuildContext context) {
    final hora = _currentHora();
    if (hora == null) return const SizedBox.shrink();
    final (lord, end) = hora;
    final info = _info[lord]!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(info[0], style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('$lord Hora',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B074).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF00B074))),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(info[1], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(
                  'Planetary hour until ${PanchangCalculator.formatTime(end, kDefaultPanchangLocation)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
