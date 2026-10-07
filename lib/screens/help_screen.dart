import 'package:flutter/material.dart';
import 'contact_screen.dart';
import 'faq_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const Color _accent = Color(0xFFFB9548);

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
        title: const Text('Help & Support', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(
              icon: Icons.auto_awesome_rounded,
              title: 'Getting Started',
              items: const [
                'Add your birth details (date, exact time and place) from your profile.',
                'Your Kundli, Moon sign, Nakshatra and Dasha are calculated automatically.',
                'Check the Home tab daily for your horoscope, Panchang and Muhurat.',
              ],
            ),
            const SizedBox(height: 14),
            _buildSection(
              icon: Icons.forum_rounded,
              title: 'Live Pandit Consultations',
              items: const [
                'Pick an online Pandit in the Chat tab and tap to connect.',
                'If the Pandit is busy, you join a queue and are connected automatically.',
                'Remedies prescribed by your Pandit are saved under Consultations & Remedies.',
              ],
            ),
            const SizedBox(height: 14),
            _buildSection(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Wallet & Payments',
              items: const [
                'Recharge your wallet from My Wallet before a paid consultation.',
                'Recharges of ₹500+ get a 10% bonus, ₹1000+ get a 15% bonus.',
                'For any billing issue, contact us with the date and amount.',
              ],
            ),
            const SizedBox(height: 14),
            _buildSection(
              icon: Icons.lock_outline_rounded,
              title: 'Account & Privacy',
              items: const [
                'Your birth data is used only to calculate your charts and readings.',
                'You can update your birth details at any time from your profile.',
                'To delete your account and data, email our support team.',
              ],
            ),
            const SizedBox(height: 14),
            _buildLinkCard(
              context,
              icon: Icons.quiz_outlined,
              title: 'Browse FAQs',
              subtitle: 'Quick answers to common questions',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FAQScreen())),
            ),
            const SizedBox(height: 14),
            _buildContactSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required IconData icon, required String title, required List<String> items}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle, color: Color(0xFF059669), size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildLinkCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Icon(icon, color: _accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact Support', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 4),
          const Text(
            'Hours: ${CosmicGuideContact.supportHours}',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _contactButton(Icons.email_rounded, 'Email', () => CosmicGuideContact.email(context, subject: '[CosmicGuide] Help request')),
              _contactButton(Icons.phone_rounded, 'Call', () => CosmicGuideContact.call(context)),
              _contactButton(Icons.chat_rounded, 'WhatsApp', () => CosmicGuideContact.whatsapp(context)),
              _contactButton(
                Icons.edit_note_rounded,
                'Write to us',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: _accent),
      label: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: BorderSide(color: _accent.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
