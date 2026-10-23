import 'package:flutter/material.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';
import 'contact_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<(IconData, String, List<String>)> _guides = [
    (
      Icons.auto_awesome_outlined,
      'Getting started',
      [
        'Add your birth details (date, exact time and place) from the More tab.',
        'Your Kundli, Moon sign, Nakshatra and Dasha are calculated automatically.',
        'Check the Home tab daily for your horoscope, Panchang and Muhurat.',
      ],
    ),
    (
      Icons.forum_outlined,
      'Live pandit consultations',
      [
        'Pick an online Pandit in the Chat tab and tap to connect.',
        'If the Pandit is busy, you join a queue and are connected automatically.',
        'Remedies prescribed by your Pandit are saved under Consultations.',
      ],
    ),
    (
      Icons.account_balance_wallet_outlined,
      'Wallet & payments',
      [
        'Recharge your wallet before a paid consultation.',
        'Recharges of ₹500+ get a 10% bonus, ₹1000+ get a 15% bonus.',
        'For any billing issue, contact us with the date and amount.',
      ],
    ),
    (
      Icons.lock_outline_rounded,
      'Account & privacy',
      [
        'Your birth data is used only to calculate your charts and readings.',
        'You can update your birth details at any time from the More tab.',
        'To delete your account and data, email our support team.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Help & support')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
          children: [
            const Text('How can we help?', style: AppText.headline),
            const SizedBox(height: 4),
            const Text('Search the FAQs or reach our team directly.', style: AppText.body),
            const SizedBox(height: AppSpacing.md),
            AppSearchBar(
              hint: 'Search help articles & FAQs',
              onTap: () => Navigator.pushNamed(context, AppRoutes.faq),
            ),
            const SizedBox(height: AppSpacing.md),

            // Contact options
            Row(
              children: [
                Expanded(
                  child: _ContactTile(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email us',
                    color: AppColors.primary,
                    onTap: () => CosmicGuideContact.email(context, subject: '[CosmicGuide] Help request'),
                  ),
                ),
                if (CosmicGuideContact.phoneSupportEnabled) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _ContactTile(
                      icon: Icons.chat_outlined,
                      label: 'WhatsApp',
                      color: AppColors.success,
                      onTap: () => CosmicGuideContact.whatsapp(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _ContactTile(
                      icon: Icons.phone_outlined,
                      label: 'Call',
                      color: AppColors.info,
                      onTap: () => CosmicGuideContact.call(context),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _ContactTile(
                    icon: Icons.edit_note_rounded,
                    label: 'Write to us',
                    color: AppColors.cosmicLight,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.contact),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('Support hours: ${CosmicGuideContact.supportHours}',
                textAlign: TextAlign.center, style: AppText.caption),

            const Padding(
              padding: EdgeInsets.fromLTRB(4, AppSpacing.xl, 4, AppSpacing.xs),
              child: Text('Guides', style: AppText.title),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _guides.length; i++) ...[
                    if (i > 0) const Divider(),
                    _GuideTile(icon: _guides[i].$1, title: _guides[i].$2, items: _guides[i].$3),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: EdgeInsets.zero,
              child: AppListRow(
                icon: Icons.quiz_outlined,
                color: AppColors.primary,
                title: 'Browse all FAQs',
                subtitle: 'Quick answers to common questions',
                onTap: () => Navigator.pushNamed(context, AppRoutes.faq),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ContactTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppText.bodyStrong.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _GuideTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> items;

  const _GuideTile({required this.icon, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.textSecondary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
        title: Text(title, style: AppText.bodyStrong.copyWith(fontSize: 15)),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.textTertiary,
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 9, right: AppSpacing.sm, left: 4),
                    child: CircleAvatar(radius: 2.5, backgroundColor: AppColors.textTertiary),
                  ),
                  Expanded(child: Text(item, style: AppText.body.copyWith(fontSize: 15, height: 1.6))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
