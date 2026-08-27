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
  final PageController _pageController = PageController();
  int _currentBannerIndex = 0;

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
                controller: _pageController,
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
                    buttonText: 'View Transit',
                    gradientColors: [const Color(0xFF1E0E3D), const Color(0xFF4A1F78)],
                  ),
                  _buildPromoBannerCard(
                    title: 'Talk to AI Astrologer\n24/7 Unlimited',
                    buttonText: 'Start Chat',
                    gradientColors: [const Color(0xFF2B0C36), const Color(0xFF6B1B54)],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Banner Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
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

            // 2. AstroPulse · Today Section (Matching Image 1)
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

            // Planetary Transits List
            _buildTransitRow('Mars Sext Saturn', '♂ ✶ ♄'),
            const SizedBox(height: 8),
            _buildTransitRow('Mars Trin Mars', '♂ △ ♂'),

            const SizedBox(height: 20),

            // Pink Explore AstroPulse Button
            SizedBox(
              width: 200,
              height: 46,
              child: ElevatedButton(
                onPressed: () {
                  widget.onNavigateTab(1); // Navigate to Chart tab
                },
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

            const SizedBox(height: 30),

            // 3. Quick Feature Cards
            const Text(
              'Astrology Hub',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 14),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.15,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              children: [
                _buildQuickCard(
                  title: 'Zodiac Chart',
                  subtitle: 'Interactive Birth Wheel',
                  icon: Icons.pie_chart_outline_rounded,
                  color: const Color(0xFF7C77E6),
                  onTap: () => widget.onNavigateTab(1),
                ),
                _buildQuickCard(
                  title: 'Synastry Love',
                  subtitle: 'Partner Compatibility',
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFE83D66),
                  onTap: () => widget.onNavigateTab(4),
                ),
                _buildQuickCard(
                  title: 'AI Astrologer',
                  subtitle: 'Ask Unlimited Questions',
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFFFB9548),
                  onTap: () => widget.onNavigateTab(3),
                ),
                _buildQuickCard(
                  title: 'Solar Return',
                  subtitle: 'Annual Forecast',
                  icon: Icons.wb_sunny_rounded,
                  color: const Color(0xFFFF9800),
                  onTap: () => widget.onNavigateTab(1),
                ),
              ],
            ),

            const SizedBox(height: 30),
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
        border: Border.all(color: Colors.purple.withOpacity(0.3), width: 1),
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
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF804BFF).withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Cosmic Graphic Representation
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.purple.withOpacity(0.2),
                ),
              ),
              const Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFFFD700),
                size: 44,
              ),
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.nightlight_round, color: Colors.amberAccent, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransitRow(String name, String symbols) {
    return Row(
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          symbols,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
