import 'package:flutter/material.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  static const _bodyStyle = TextStyle(fontSize: 16, height: 1.6, color: AppColors.textSecondary);

  static const List<(IconData, String, String)> _offers = [
    (
      Icons.grid_view_rounded,
      'Janam Kundli',
      'Accurate birth charts with Lagna, Nakshatra, planetary positions and Vimshottari Dasha.'
    ),
    (Icons.auto_awesome_outlined, 'AI astrologer', 'Instant, chart-aware answers to your questions, available 24/7.'),
    (
      Icons.forum_outlined,
      'Live pandit consultations',
      'One-on-one guidance from experienced astrologers, with remedies saved to your profile.'
    ),
    (
      Icons.wb_sunny_outlined,
      'Daily Panchang & muhurat',
      'Tithi, Nakshatra, Yoga and auspicious timings for your day.'
    ),
  ];

  static const List<(IconData, String, String)> _values = [
    (
      Icons.verified_outlined,
      'Authenticity',
      'Calculations grounded in classical Vedic methods, presented honestly, without fear-based predictions.'
    ),
    (
      Icons.lock_outline_rounded,
      'Privacy',
      'Your birth data is personal. We use it only to serve you and never sell it.'
    ),
    (
      Icons.self_improvement_rounded,
      'Empowerment',
      'Astrology is a guide, not a verdict. We help you understand your tendencies so you can act with clarity.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('About us')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
          children: [
            // Hero
            ClipRRect(
              borderRadius: AppRadius.card,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 200),
                child: Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    const Positioned.fill(child: AppImage('assets/images/astrology-hero.jpg')),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.cosmic.withValues(alpha: 0.15),
                              AppColors.cosmic.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 72, AppSpacing.lg, AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CosmicGuide', style: AppText.display.copyWith(color: AppColors.textOnDark)),
                          const SizedBox(height: 4),
                          Text('Authentic Vedic astrology, made personal and accessible.',
                              style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _heading('Our story'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'CosmicGuide was created to bring the depth of Jyotish, the ancient Vedic science of light, to everyone, wherever they are. '
                'We combine precise astronomical calculations with the wisdom of experienced astrologers, so your birth chart becomes a practical guide for everyday decisions.',
                style: _bodyStyle,
              ),
            ),

            _heading('What we offer'),
            for (final o in _offers) _InfoItem(icon: o.$1, title: o.$2, description: o.$3),

            _heading('Our values'),
            for (final v in _values)
              _InfoItem(icon: v.$1, title: v.$2, description: v.$3, color: AppColors.cosmicLight),

            const SizedBox(height: AppSpacing.lg),
            AppCard(
              color: AppColors.surfaceMuted,
              border: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Have questions?', style: AppText.subtitle),
                  const SizedBox(height: 4),
                  const Text('We would love to hear from you: questions, suggestions or feedback.',
                      style: AppText.body),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Contact us',
                    icon: Icons.mail_outline_rounded,
                    height: 44,
                    expand: false,
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

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, AppSpacing.xl, 4, AppSpacing.sm),
        child: Semantics(header: true, child: Text(text, style: AppText.title)),
      );
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.title,
    required this.description,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.subtitle),
                const SizedBox(height: 2),
                Text(description, style: AppText.body.copyWith(fontSize: 15, height: 1.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
