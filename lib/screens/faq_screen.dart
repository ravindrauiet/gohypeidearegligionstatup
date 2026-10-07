import 'package:flutter/material.dart';
import 'contact_screen.dart';

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  static const Color _accent = Color(0xFFFB9548);

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  static const List<FAQItem> _faqItems = [
    FAQItem(
      question: 'What details do I need to generate my Kundli?',
      answer: 'Your full name, date of birth, exact time of birth and place of birth. The time of birth decides your Lagna (Ascendant), so the more precise it is, the more accurate your chart and predictions will be.',
    ),
    FAQItem(
      question: 'I don\'t know my exact birth time. What should I do?',
      answer: 'Enter the closest time you know (for example from a birth certificate or family records). Your Moon sign and Nakshatra are usually still reliable, but Lagna and house positions may shift. A live Pandit can help with birth-time rectification.',
    ),
    FAQItem(
      question: 'How do I update my birth details?',
      answer: 'Open Profile & Settings and tap "Update Birth Details". Your Kundli, daily predictions and AI readings are recalculated with the new details.',
    ),
    FAQItem(
      question: 'What is the difference between the AI Astrologer and a live Pandit?',
      answer: 'The AI Astrologer answers instantly using your birth chart and is available 24/7. Live Pandits are experienced human astrologers who consult with you one-on-one and are billed per minute from your wallet.',
    ),
    FAQItem(
      question: 'How does billing for live consultations work?',
      answer: 'Each Pandit shows a per-minute rate before you connect. Consultation charges are paid from your CosmicGuide wallet, so keep enough balance for the time you need. You can recharge any time from My Wallet.',
    ),
    FAQItem(
      question: 'Why am I in a waiting queue?',
      answer: 'When a Pandit is already consulting someone, you are placed in their queue. The lobby shows your position and an estimated wait, and you are connected automatically when it is your turn. You can leave the queue at any time.',
    ),
    FAQItem(
      question: 'Do wallet recharges include a bonus?',
      answer: 'Yes. Recharges of ₹500 or more get a 10% bonus, and recharges of ₹1000 or more get a 15% bonus, credited instantly to your wallet.',
    ),
    FAQItem(
      question: 'Where can I see remedies a Pandit prescribed?',
      answer: 'Open "Consultations & Remedies" from your profile. The Remedies tab lists every gemstone, mantra and ritual prescribed during your consultations.',
    ),
    FAQItem(
      question: 'Can I add Kundlis for my family members?',
      answer: 'Yes. You can save birth charts for family members and select one before a consultation so the Pandit reviews the right chart.',
    ),
    FAQItem(
      question: 'Is my birth data private?',
      answer: 'Your birth details are used only to calculate your charts and personalise readings. They are shared with a Pandit only during a consultation you start. See our Privacy Policy for details.',
    ),
    FAQItem(
      question: 'Are astrological predictions guaranteed?',
      answer: 'No. Vedic astrology offers guidance and perspective; it is not a substitute for professional medical, legal or financial advice. Please use your own judgement for important decisions.',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? _faqItems
        : _faqItems.where((f) => f.question.toLowerCase().contains(q) || f.answer.toLowerCase().contains(q)).toList();

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
        title: const Text('FAQs', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search questions',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No questions match your search.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              )
            else
              ...items.map(_buildFAQItem),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Still need help?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Our support team usually replies within a few hours.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactScreen())),
                      style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
                      child: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(FAQItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            item.question,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black),
          ),
          iconColor: _accent,
          collapsedIconColor: _accent,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.answer, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class FAQItem {
  final String question;
  final String answer;

  const FAQItem({
    required this.question,
    required this.answer,
  });
}
