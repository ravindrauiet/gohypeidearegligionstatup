import 'package:flutter/material.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
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
      answer: 'Go to the More tab and tap "Edit birth details". Your Kundli, daily predictions and AI readings are recalculated with the new details.',
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
      answer: 'Open "Consultations" from the More tab. The Remedies tab lists every gemstone, mantra and ritual prescribed during your consultations.',
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
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('FAQs')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const Text('Frequently asked questions', style: AppText.headline),
            const SizedBox(height: 4),
            const Text('Quick answers about Kundli, consultations and your wallet.', style: AppText.body),
            const SizedBox(height: AppSpacing.md),
            AppSearchBar(
              hint: 'Search questions',
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.md),
            if (items.isEmpty)
              AppStateView(
                compact: true,
                icon: Icons.search_off_rounded,
                title: 'No matching questions',
                message: 'Try a different word, or ask our support team.',
                actionLabel: 'Clear search',
                onAction: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(),
                      _buildFAQItem(items[i]),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Still need help?', style: AppText.subtitle),
                        SizedBox(height: 2),
                        Text('Our team usually replies within a few hours.', style: AppText.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppButton(
                    label: 'Contact',
                    expand: false,
                    height: 44,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.contact),
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // Keep expansion state stable while filtering.
        key: PageStorageKey<String>(item.question),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        title: Text(item.question, style: AppText.bodyStrong.copyWith(fontSize: 15)),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textTertiary,
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.answer, style: AppText.body.copyWith(fontSize: 15, height: 1.6)),
        ],
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
