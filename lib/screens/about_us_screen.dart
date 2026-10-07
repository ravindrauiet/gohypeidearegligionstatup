import 'package:flutter/material.dart';
import 'contact_screen.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  static const Color _accent = Color(0xFFFB9548);
  static const Color _text = Color(0xFF5F4B32);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('About Us', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hero banner
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 36),
                  SizedBox(height: 12),
                  Text(
                    'CosmicGuide',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Authentic Vedic astrology, made personal and accessible.',
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _heading('Our Story'),
            const SizedBox(height: 12),
            const Text(
              'CosmicGuide was created to bring the depth of Jyotish – the ancient Vedic science of light – to everyone, wherever they are. '
              'We combine precise astronomical calculations with the wisdom of experienced astrologers, so your birth chart becomes a practical guide for everyday decisions.',
              style: TextStyle(fontSize: 15, height: 1.6, color: _text),
            ),

            const SizedBox(height: 24),
            _heading('What We Offer'),
            const SizedBox(height: 12),
            _buildItem(Icons.grid_view_rounded, 'Janam Kundli', 'Accurate birth charts with Lagna, Nakshatra, planetary positions and Vimshottari Dasha.'),
            _buildItem(Icons.smart_toy_outlined, 'AI Astrologer', 'Instant, chart-aware answers to your questions, available 24/7.'),
            _buildItem(Icons.forum_outlined, 'Live Pandit Consultations', 'One-on-one guidance from experienced astrologers, with remedies saved to your profile.'),
            _buildItem(Icons.wb_sunny_outlined, 'Daily Panchang & Muhurat', 'Tithi, Nakshatra, Yoga and auspicious timings for your day.'),

            const SizedBox(height: 24),
            _heading('Our Values'),
            const SizedBox(height: 12),
            _buildValueCard(
              icon: Icons.verified_outlined,
              title: 'Authenticity',
              description: 'Calculations grounded in classical Vedic methods, presented honestly – without fear-based predictions.',
              color: _accent,
            ),
            _buildValueCard(
              icon: Icons.lock_outline_rounded,
              title: 'Privacy',
              description: 'Your birth data is personal. We use it only to serve you and never sell it.',
              color: const Color(0xFF8B0000),
            ),
            _buildValueCard(
              icon: Icons.self_improvement_rounded,
              title: 'Empowerment',
              description: 'Astrology is a guide, not a verdict. We help you understand your tendencies so you can act with clarity.',
              color: const Color(0xFF317BEA),
            ),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Have Questions?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 8),
                  const Text(
                    'We would love to hear from you – questions, suggestions or feedback.',
                    style: TextStyle(fontSize: 15, color: _text, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactScreen())),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Contact Us', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Text(
        text,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
      );

  Widget _buildItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _accent, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 14, color: _text, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 13.5, color: _text, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
