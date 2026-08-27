import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_service.dart';

class HomeTab extends StatefulWidget {
  final Function(int) onNavigateTab;
  const HomeTab({super.key, required this.onNavigateTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final PageController _bannerController = PageController();
  int _currentBannerIndex = 0;

  // Countdown timer for offer badge
  late Timer _timer;
  int _offerSeconds = 1731; // 00:28:51

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_offerSeconds > 0) {
            _offerSeconds--;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  String _formatTimer(int totalSeconds) {
    int m = totalSeconds ~/ 60;
    int s = totalSeconds % 60;
    return "00:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData ?? {
      'ascendant': 'Aries',
      'sunSign': 'Leo',
      'moonSign': 'Taurus',
      'nakshatra': 'Rohini',
      'birthDetails': {'fullName': 'ravindra'}
    };

    final name = kundli['birthDetails']?['fullName'] ?? 'ravindra';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'R',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hi, Good Night',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w400),
                ),
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black, size: 20),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Wallet badge ₹0
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wallet Balance: ₹0. Tap to top up!')),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6B1A3A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: const [
                  Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    '₹0',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Settings gear button
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.black, size: 20),
              onPressed: () {
                Navigator.pushNamed(context, '/birth-details');
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Promo Cosmic Banner Carousel
            SizedBox(
              height: 155,
              child: PageView(
                controller: _bannerController,
                onPageChanged: (index) {
                  setState(() {
                    _currentBannerIndex = index;
                  });
                },
                children: [
                  _buildPromoBannerCard(
                    title: 'Claim your\nfree chat bonus',
                    buttonText: '+ Refer and Earn',
                    gradientColors: [const Color(0xFF0F0826), const Color(0xFF27134A)],
                  ),
                  _buildPromoBannerCard(
                    title: 'Unlock Your\nDaily Chart Insight',
                    buttonText: 'View Transits',
                    gradientColors: [const Color(0xFF1E0E3D), const Color(0xFF4A1F78)],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Banner Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(2, (index) {
                final isSelected = _currentBannerIndex == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 12 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFF6B6B) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            // 2. AstroPulse · Today Section
            const Text(
              'AstroPulse · Today',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            RichText(
              text: const TextSpan(
                style: TextStyle(fontFamily: 'Roboto', fontSize: 32, height: 1.1),
                children: [
                  TextSpan(
                    text: 'Push It\n',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: 'Forward',
                    style: TextStyle(
                      color: Color(0xFFD95D39),
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            Text(
              'Mars sextiles your natal Saturn. Resistance is low today. Take the step.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 18),

            _buildTransitRow('Mars Sext Saturn', '♂ ✶ ♄'),
            const SizedBox(height: 8),
            _buildTransitRow('Mars Trin Mars', '♂ △ ♂'),

            const SizedBox(height: 20),

            SizedBox(
              width: 200,
              height: 46,
              child: ElevatedButton(
                onPressed: () => widget.onNavigateTab(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE83D66),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Explore AstroPulse',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // 3. Talk to an Astrologer Banner
            GestureDetector(
              onTap: () => widget.onNavigateTab(3),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE83D66),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Talk to an Astrologer',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Personal guidance from expert astrologers.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'Start',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFE83D66)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // 4. Chat with Astrologers Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chat with Astrologers',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                GestureDetector(
                  onTap: () => widget.onNavigateTab(3),
                  child: const Text(
                    'See All',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              height: 275,
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
                    offerTimer: _formatTimer(_offerSeconds),
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
                    specialty: 'Astrocartography Expert',
                    rating: '4.9 (540)',
                    imageUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=300&q=80',
                    avatarBg: const Color(0xFFF3E5F5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 5. Charts 3D Icons Grid Section
            const Text(
              'Charts',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
            ),

            const SizedBox(height: 18),

            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.85,
              crossAxisSpacing: 10,
              mainAxisSpacing: 18,
              children: [
                _build3DChartItem('Natal\nChart', Icons.pie_chart_outline_rounded, const Color(0xFF7C77E6), () => widget.onNavigateTab(1)),
                _build3DChartItem('Synastry', Icons.favorite_rounded, const Color(0xFFFF6B81), () => widget.onNavigateTab(4)),
                _build3DChartItem('Solar\nChart', Icons.wb_sunny_rounded, const Color(0xFFFF9800), () => widget.onNavigateTab(1)),
                _build3DChartItem('Vedic\nChart', Icons.menu_book_rounded, const Color(0xFFD95D39), () => widget.onNavigateTab(1)),
                _build3DChartItem('ACG Chart', Icons.public_rounded, const Color(0xFF317BEA), () => widget.onNavigateTab(1)),
                _build3DChartItem('Transit\nChart', Icons.blur_on_rounded, const Color(0xFF9C27B0), () => widget.onNavigateTab(1)),
                _build3DChartItem('Horoscope', Icons.stars_rounded, const Color(0xFFFFC107), () => widget.onNavigateTab(1)),
                _build3DChartItem('Moon\nCalendar', Icons.nightlight_round, const Color(0xFF673AB7), () => widget.onNavigateTab(1)),
              ],
            ),

            const SizedBox(height: 32),

            // 6. Community: Star Talk Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('COMMUNITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                    SizedBox(height: 2),
                    Text('Star Talk', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Colors.black)),
                  ],
                ),
                const Text('What is?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),

            const SizedBox(height: 14),

            SizedBox(
              height: 140,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildStarTalkPost(
                    handle: 'mars_reach',
                    glyphs: '☉ ♑  ☽ ♒  ↑ ♍',
                    text: "OMG, you guys! I'm so behind on the #call sheet! We're rolling in 20 and I sti...",
                    likes: 8,
                    comments: 3,
                    avatarBg: const Color(0xFFDCEDC8),
                  ),
                  const SizedBox(width: 14),
                  _buildStarTalkPost(
                    handle: 'lunar_seeker',
                    glyphs: '☉ ♌  ☽ ♉  ↑ ♈',
                    text: 'Jupiter moving into my 10th house is already giving me huge career alignment signals! ✨',
                    likes: 14,
                    comments: 5,
                    avatarBg: const Color(0xFFE1BEE7),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 7. Today's Moon Shine Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  "Today's Moon Shine",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                Text('View', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2C2C2E),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.brightness_3, color: Color(0xFFFFF7ED), size: 54),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Waxing Gibbous',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Moon in Aquarius',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: Color(0xFFD95D39)),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _buildMoonStat('99%', 'LIT'),
                                const SizedBox(width: 16),
                                _buildMoonStat('27 Aug', 'FULL'),
                                const SizedBox(width: 16),
                                _buildMoonStat('14d', 'AGE'),
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
                      const Expanded(
                        child: Text(
                          'The Moon is in Aquarius during a Waxing Gibbous phase.',
                          style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 8. Planetary Hour Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Text('♀', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Venus Hour',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Beauty, harmony, and love are all around.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text(
                        '00:16:40',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                      Text(
                        'Ends at 11:48 PM',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // 9. Promo Banner: Someone keeping you up Lately?
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontFamily: 'Roboto', fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, height: 1.25),
                      children: [
                        TextSpan(text: 'Someone keeping you\nup '),
                        TextSpan(text: 'Lately?', style: TextStyle(color: Color(0xFFFF6B81))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Find out why. Send them a link and read it together.',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => widget.onNavigateTab(4),
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

            // 10. Cosmic Compatibility Card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('💕 ', style: TextStyle(fontSize: 20)),
                      Text(
                        'Cosmic Compatibility',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'See how your charts align emotional, physical, and karmic connection',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMatchAvatar('R', 'You'),
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
                      onPressed: () => widget.onNavigateTab(4),
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

            // 11. Capricorn Community · Today (Matching New Image 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  'Capricorn Community · Today',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black),
                ),
                Text('See All', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCommunityMetric(Icons.bolt_rounded, const Color(0xFF00B074), '60%', 'Intense'),
                  _buildCommunityMetric(Icons.emoji_objects_rounded, const Color(0xFF7032D9), '61%', 'Reflective'),
                  _buildCommunityMetric(Icons.local_fire_department_rounded, const Color(0xFFE83D66), '68%', 'Motivated'),
                  _buildCommunityMetric(Icons.battery_charging_full_rounded, const Color(0xFFE53935), '67%', 'Energy'),
                ],
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              '83% of Capricorn report feeling energized today',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: Color(0xFFD95D39),
              ),
            ),

            const SizedBox(height: 32),

            // 12. Astrological Calculators Section (Matching New Image 1)
            const Text(
              'Astrological Calculators',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
            ),

            const SizedBox(height: 18),

            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.82,
              crossAxisSpacing: 10,
              mainAxisSpacing: 18,
              children: [
                _build3DChartItem('Big 3', Icons.format_size_rounded, const Color(0xFF1E88E5), () {}),
                _build3DChartItem('Black\nMoon Lilith', Icons.bedtime_rounded, const Color(0xFF7E57C2), () {}),
                _build3DChartItem('Juno\nCalculator', Icons.auto_awesome_rounded, const Color(0xFFFFA726), () {}),
                _build3DChartItem('Lo Shu\nGrid', Icons.grid_on_rounded, const Color(0xFF8E24AA), () {}),
                _build3DChartItem('Know Your\nNumbers', Icons.casino_rounded, const Color(0xFF42A5F5), () {}),
                _build3DChartItem('Chinese\nCalculator', Icons.calculate_rounded, const Color(0xFFFF7043), () {}),
                _build3DChartItem('Know Your\nNodes', Icons.hub_rounded, const Color(0xFFAB47BC), () {}),
                _build3DChartItem("Where's\nYour Chir...", Icons.vpn_key_rounded, const Color(0xFFFFCA28), () {}),
              ],
            ),

            const SizedBox(height: 32),

            // 13. Reports Section (Matching New Image 2)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black)),
                Text('See All', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Book Cover Artwork Thumbnail
                  Container(
                    width: 90,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A3A),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(2, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 28),
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
                        const Text(
                          'Birth Chart Report',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Understand your nature, strengths and life partners.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
                            SizedBox(width: 4),
                            Text('4.2 (500)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            children: const [
                              TextSpan(
                                text: '₹1999.00  ',
                                style: TextStyle(fontSize: 13, color: Colors.grey, decoration: TextDecoration.lineThrough),
                              ),
                              TextSpan(
                                text: '₹599.00',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),
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

            const SizedBox(height: 32),

            // 14. Blogs Section (Matching New Images 2 & 3)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Blogs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black)),
                Text('See All', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),

            const SizedBox(height: 16),

            _buildBlogCard(
              category: 'Birth Chart',
              title: "Why ChatGPT Can't Actually Read Your Birth Chart",
              meta: '5 min read · Jul 2',
              imageUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?auto=format&fit=crop&w=300&q=80',
              bgColor: const Color(0xFF6B124B),
            ),
            const SizedBox(height: 14),
            _buildBlogCard(
              category: 'Transit',
              title: 'Jupiter in Leo 2026: A Rising Sign Guide for All 12 Ascendants',
              meta: '4 min read · Jun 30',
              imageUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=300&q=80',
              bgColor: const Color(0xFF1E3A8A),
            ),
            const SizedBox(height: 14),
            _buildBlogCard(
              category: 'Transit',
              title: 'What A Retrograde Really Means In Astrology (And How to Survive It)',
              meta: '6 min read · Jun 26',
              imageUrl: 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=300&q=80',
              bgColor: const Color(0xFF7C3AED),
            ),

            const SizedBox(height: 40),

            // 15. Footer Branding Banner (Matching New Image 3)
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontFamily: 'Roboto', fontSize: 36, fontWeight: FontWeight.w900, color: Colors.black, height: 1.15),
                      children: [
                        TextSpan(text: 'Follow\nyour '),
                        TextSpan(text: 'stars!', style: TextStyle(color: Color(0xFFE83D66))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // White Glowing upastrology Logo Emblem
                  Row(
                    children: const [
                      Text(
                        'upastrology',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1.0,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoBannerCard({
    required String title,
    required String buttonText,
    required List<Color> gradientColors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB085FF), Color(0xFF804BFF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.card_giftcard_rounded, color: Color(0xFFFFD700), size: 48),
        ],
      ),
    );
  }

  Widget _buildTransitRow(String name, String symbols) {
    return Row(
      children: [
        Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey.shade800)),
        const SizedBox(width: 10),
        Text(symbols, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
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
    String? offerTimer,
  }) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (offerTimer != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00B074),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Offer ends in $offerTimer',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(35),
            child: Container(
              width: 70,
              height: 70,
              color: avatarBg,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(child: Text(name[0], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (discountPrice != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'From ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  TextSpan(text: '$originalPrice ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
                  TextSpan(text: discountPrice, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(specialty, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 14),
              const SizedBox(width: 4),
              Text(rating, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/chatbot'),
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

  Widget _build3DChartItem(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(icon, color: color, size: 28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black, height: 1.15),
          ),
        ],
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: avatarBg,
                child: Text(handle[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(handle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                  Text(glyphs, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
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

  Widget _buildCommunityMetric(IconData icon, Color color, String val, String label) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 80,
              height: 80,
              color: bgColor,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.article_rounded, color: Colors.white, size: 36)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black, height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoonStat(String val, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildMatchAvatar(String label, String sub) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFFFCF7F1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
          ),
        ),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }
}
