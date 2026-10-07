import 'package:flutter/material.dart';
import 'contact_screen.dart';
import 'privacy_screen.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const List<(String, List<String>)> _sections = [
    (
      'Acceptance of Terms',
      [
        'By creating an account or using CosmicGuide you agree to these Terms.',
        'If you do not agree, please do not use the app.',
        'We may update these Terms; continued use after an update means you accept the changes.',
      ],
    ),
    (
      'Our Service',
      [
        'CosmicGuide provides Vedic astrology tools: Kundli charts, horoscopes, Panchang, AI readings and live consultations with independent Pandits.',
        'Astrology offers guidance and perspective only. It is not a substitute for professional medical, legal, financial or psychological advice.',
        'AI readings are generated automatically and may contain mistakes.',
      ],
    ),
    (
      'Your Responsibilities',
      [
        'Provide accurate birth details and keep your login credentials secure.',
        'Be respectful in chats; abusive or unlawful content is not allowed.',
        'You are responsible for decisions you make based on any reading.',
      ],
    ),
    (
      'Wallet & Consultations',
      [
        'Prices are shown in Indian Rupees (INR) and live consultations are billed per minute at the rate shown for each Pandit.',
        'Wallet bonuses are promotional credits and cannot be withdrawn.',
        'If a consultation fails because of a technical problem on our side, contact support for a review of the charges.',
      ],
    ),
    (
      'Pandit Partners',
      [
        'Pandits on CosmicGuide are independent practitioners responsible for their own advice.',
        'Remedies such as gemstones or rituals are suggestions; please consult qualified professionals before purchases or health-related actions.',
      ],
    ),
    (
      'Limitation of Liability',
      [
        'CosmicGuide is provided "as is". To the extent permitted by law, we are not liable for indirect or consequential losses.',
        'Our total liability is limited to the amount you paid for the affected service.',
      ],
    ),
    (
      'Governing Law',
      [
        'These Terms are governed by the laws of India.',
        'We encourage you to contact support first so we can try to resolve any dispute quickly.',
      ],
    ),
  ];

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
        title: const Text('Terms of Service', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Please read these Terms carefully. They explain the rules for using CosmicGuide.',
              style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            for (final s in _sections) ...[
              LegalSection(title: s.$1, items: s.$2, icon: Icons.description_outlined),
              const SizedBox(height: 12),
            ],
            LegalContactCard(
              title: 'Questions about these Terms?',
              text: 'Write to us at ${CosmicGuideContact.supportEmail} and we will be happy to help.',
              buttonLabel: 'Email Support',
              onPressed: () => CosmicGuideContact.email(context, subject: '[CosmicGuide] Terms of Service question'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Last updated: ${PrivacyScreen.lastUpdated}.',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
