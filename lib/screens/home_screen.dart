import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData ?? {
      'ascendant': 'Aries',
      'sunSign': 'Leo',
      'moonSign': 'Taurus',
      'nakshatra': 'Rohini',
      'birthDetails': {'fullName': 'Astro Seeker'}
    };

    final name = kundli['birthDetails']?['fullName'] ?? 'Astro Seeker';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.black,
              radius: 18,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'A',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hi, Good Morning',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                Text(
                  name,
                  style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar_rounded, color: Colors.black),
            onPressed: () {
              Navigator.pushNamed(context, '/birth-details');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner 1: Kundli Card Summary
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'YOUR VEDIC KUNDLI',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFB9548)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/kundli-view'),
                        child: const Text('View Full Chart >', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickStat('Ascendant', kundli['ascendant'] ?? 'Aries'),
                      _buildQuickStat('Moon Sign', kundli['moonSign'] ?? 'Taurus'),
                      _buildQuickStat('Nakshatra', kundli['nakshatra'] ?? 'Rohini'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Daily Horoscope Preview Card (Matching reference slide 6/6)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.brightness_7_rounded, color: Color(0xFF4CAF50), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Daily Horoscope & Insights',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          Text(
                            "${kundli['moonSign'] ?? 'Aries'} for Today",
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildProgressScore('Love', 0.85, const Color(0xFFFF6B81))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildProgressScore('Career', 0.90, const Color(0xFF317BEA))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildProgressScore('Luck', 0.94, const Color(0xFF4CAF50))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'A conversation with a trusted friend set a harmonious tone today. Cosmic alignment brings clarity in decisions.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Astro Features',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 14),

            // Feature Grid (Matching user reference screenshots)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.15,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              children: [
                _buildFeatureCard(
                  context,
                  title: 'Synastry',
                  subtitle: 'Relationship Insights',
                  icon: Icons.favorite_rounded,
                  color: const Color(0xFFFF6B81),
                  badge: 'Match',
                  onTap: () => _showFeatureModal(context, 'Synastry Insights', 'Discover love chemistry and compatibility charts between you and your partner.'),
                ),
                _buildFeatureCard(
                  context,
                  title: 'Astrocartography',
                  subtitle: 'Personal Astro Map',
                  icon: Icons.public_rounded,
                  color: const Color(0xFF317BEA),
                  badge: 'Astro Map',
                  onTap: () => _showFeatureModal(context, 'Astrocartography Map', 'Find your best locations across the globe for love, career, luck, and wealth.'),
                ),
                _buildFeatureCard(
                  context,
                  title: 'Moon Calendar',
                  subtitle: 'Moon Phases & You',
                  icon: Icons.nightlight_round,
                  color: const Color(0xFF9C27B0),
                  badge: 'Full Moon',
                  onTap: () => _showFeatureModal(context, 'Moon Phases', 'Track illumination, lunar age, and Nakshatra positions for daily energy shifts.'),
                ),
                _buildFeatureCard(
                  context,
                  title: 'Solar Return',
                  subtitle: 'Birthday Forecast',
                  icon: Icons.wb_sunny_rounded,
                  color: const Color(0xFFFF9800),
                  badge: 'Annual Focus',
                  onTap: () => _showFeatureModal(context, 'Solar Return Chart', 'Explore planets, houses, and theme of your upcoming year.'),
                ),
              ],
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),

      // Floating AI Kundli Assistant Chat Button
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FloatingActionButton.extended(
            onPressed: () {
              Navigator.pushNamed(context, '/chatbot');
            },
            backgroundColor: Colors.black,
            elevation: 8,
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            label: const Text(
              'Chat with AI Kundli Assistant',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
      ],
    );
  }

  Widget _buildProgressScore(String label, double val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Text("${(val * 100).toInt()}%", style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: val,
            color: color,
            backgroundColor: color.withOpacity(0.15),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String badge,
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
            Row(
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
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

  void _showFeatureModal(BuildContext context, String title, String description) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFCF7F1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 12),
              Text(description, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/chatbot');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25))),
                  child: const Text('Ask AI About This Feature', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}