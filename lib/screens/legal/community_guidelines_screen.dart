import 'package:flutter/material.dart';

import '../../widgets/ui/app_ui.dart';

/// Which part of [CommunityGuidelinesScreen] to open on.
enum GuidelinesSection { buddy, coins, trip }

/// Community guidelines (buddies), coins terms and temple trip terms, written
/// in plain English. Push it with `MaterialPageRoute`; pass [initialSection]
/// to jump straight to one part (e.g. from the coins or trip screens).
class CommunityGuidelinesScreen extends StatefulWidget {
  final GuidelinesSection? initialSection;

  const CommunityGuidelinesScreen({super.key, this.initialSection});

  @override
  State<CommunityGuidelinesScreen> createState() => _CommunityGuidelinesScreenState();
}

class _Rule {
  final IconData icon;
  final String title;
  final String body;
  const _Rule(this.icon, this.title, this.body);
}

class _Section {
  final GuidelinesSection id;
  final String chip;
  final String title;
  final String intro;
  final IconData icon;
  final Color color;
  final List<_Rule> rules;
  const _Section({
    required this.id,
    required this.chip,
    required this.title,
    required this.intro,
    required this.icon,
    required this.color,
    required this.rules,
  });
}

const _sections = <_Section>[
  _Section(
    id: GuidelinesSection.buddy,
    chip: 'Buddies',
    title: 'Buddy community guidelines',
    intro: 'Find your buddy is about real, respectful connections. These simple rules keep it safe and kind '
        'for everyone.',
    icon: Icons.people_alt_rounded,
    color: AppColors.love,
    rules: [
      _Rule(Icons.favorite_border_rounded, 'Be respectful',
          'Treat every person the way you would like to be treated. Be honest about who you are and what you are '
              'looking for, and take "no" gracefully.'),
      _Rule(Icons.verified_user_outlined, '18+ only',
          'Buddies is only for adults. Your age comes from the birth date in your Kundli, so please keep it '
              'truthful. Report anyone you believe is under 18.'),
      _Rule(Icons.block_rounded, 'No harassment',
          'No abuse, threats, hate, unwanted sexual messages or repeated messages after someone has stopped '
              'replying. One report is enough for us to review an account.'),
      _Rule(Icons.money_off_rounded, 'Never ask for money',
          'Do not ask buddies for money, gifts, bank or card details, OTPs or investments, and never send any. '
              'Anyone who asks is very likely a scammer: please report them.'),
      _Rule(Icons.storefront_outlined, 'Meet in public places',
          'If you decide to meet, choose a busy public place, tell a friend or family member where you are going, '
              'and arrange your own travel. Never share your home address too early.'),
      _Rule(Icons.flag_outlined, 'Report and block',
          'You can block or report anyone from their profile or your chat. Blocking hides you from each other '
              'right away; our team reviews every report.'),
      _Rule(Icons.lock_outline_rounded, 'Your details stay private',
          'Others never see your birth details, Kundli, quiz answers, AI chats or exact location: only your match '
              'score, a few highlights and a rough distance.'),
    ],
  ),
  _Section(
    id: GuidelinesSection.coins,
    chip: 'Coins',
    title: 'Coins terms',
    intro: 'Coins are a small thank-you for spending time with CosmicGuide. They are fun to collect, but they '
        'are not money.',
    icon: Icons.toll_rounded,
    color: Color(0xFFC97A0A),
    rules: [
      _Rule(Icons.currency_rupee_rounded, 'No cash value',
          'Coins have no cash value. They cannot be bought, sold, transferred to another account or exchanged '
              'for money, gift cards or anything else outside the app.'),
      _Rule(Icons.wb_sunny_outlined, 'Daily check-in: 1 coin',
          'Check in once a day (India time) to collect 1 coin and grow your streak.'),
      _Rule(Icons.sports_esports_outlined, 'Games: 10 coins each per day',
          'Each of the four games pays 10 coins once a day when you play it.'),
      _Rule(Icons.play_circle_outline_rounded, 'Videos: 1 coin per new video',
          'Watch a devotional video you have not watched before for at least 10 seconds to collect 1 coin. Each '
              'video pays only once.'),
      _Rule(Icons.psychology_alt_outlined, 'Mindset questions: 50 coins each',
          'Your first answer to each of the 50 mindset questions pays 50 coins. Changing an answer later is free '
              'but does not pay again.'),
      _Rule(Icons.gavel_rounded, 'Fair play',
          'We may adjust or remove coins earned through bugs, automation, multiple accounts or other abuse, and '
              'we may change the earning rules with notice in the app. Coins are removed if you delete your '
              'account.'),
    ],
  ),
  _Section(
    id: GuidelinesSection.trip,
    chip: 'Temple trip',
    title: 'Temple trip terms',
    intro: 'Save 10,000 coins and you can request a temple trip with one of your buddies. Here is how it works.',
    icon: Icons.temple_hindu_rounded,
    color: AppColors.primary,
    rules: [
      _Rule(Icons.toll_outlined, '10,000 coins to request',
          'A request uses 10,000 coins, which are held while our team reviews it. You can cancel a pending '
              'request at any time and get them back.'),
      _Rule(Icons.fact_check_outlined, 'Reviewed by our team',
          'Every request is subject to review and availability. We will contact you both to confirm the temple, '
              'dates and details before anything is booked.'),
      _Rule(Icons.flight_takeoff_rounded, 'We arrange the travel',
          'When a trip is approved, CosmicGuide arranges the travel. You never need to pay anyone, and nobody '
              'from our team will ask you for money or bank details.'),
      _Rule(Icons.handshake_outlined, 'Both buddies must agree',
          'You can only request a trip with an accepted buddy, and the trip goes ahead only if both of you '
              'confirm with our team.'),
      _Rule(Icons.replay_rounded, 'Rejected requests are refunded',
          'If we cannot arrange a trip, or your buddy does not agree, the request is rejected and your 10,000 '
              'coins are returned to your balance.'),
      _Rule(Icons.health_and_safety_outlined, 'Safety first',
          'Travel only if you feel comfortable, keep family informed of your plans, and follow the temple\'s '
              'rules and local guidance. Tell us straight away if anything feels wrong.'),
    ],
  ),
];

class _CommunityGuidelinesScreenState extends State<CommunityGuidelinesScreen> {
  final _keys = {for (final s in _sections) s.id: GlobalKey()};
  late GuidelinesSection _active = widget.initialSection ?? GuidelinesSection.buddy;

  @override
  void initState() {
    super.initState();
    if (widget.initialSection != null && widget.initialSection != GuidelinesSection.buddy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(widget.initialSection!, animate: false));
    }
  }

  void _jump(GuidelinesSection id, {bool animate = true}) {
    if (!mounted) return;
    setState(() => _active = id);
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Scrollable.ensureVisible(
      ctx,
      duration: animate && !reduce ? const Duration(milliseconds: 350) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Guidelines & terms')),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.pagePadding,
            child: Row(children: [
              for (var i = 0; i < _sections.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                AppFilterChip(
                  label: _sections[i].chip,
                  icon: _sections[i].icon,
                  selected: _active == _sections[i].id,
                  onTap: () => _jump(_sections[i].id),
                ),
              ],
            ]),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // A Column inside a scroll view (not a lazy list) so every section
          // exists and can be scrolled to.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final s in _sections) ...[
                _SectionView(key: _keys[s.id], section: s),
                const SizedBox(height: AppSpacing.xl),
              ],
              const Text(
                'Questions or something to report? Contact us from Help & support in the My account tab. '
                'These guidelines sit alongside our Terms of service and Privacy policy.',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SectionView extends StatelessWidget {
  final _Section section;
  const _SectionView({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final s = section;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: s.color.withValues(alpha: 0.08),
          borderRadius: AppRadius.card,
          border: Border.all(color: s.color.withValues(alpha: 0.18)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: s.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(s.icon, color: s.color, size: 24),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(s.title, style: AppText.title)),
              const SizedBox(height: 4),
              Text(s.intro, style: AppText.body),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < s.rules.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 60),
            _RuleRow(rule: s.rules[i], color: s.color),
          ],
        ]),
      ),
    ]);
  }
}

class _RuleRow extends StatelessWidget {
  final _Rule rule;
  final Color color;
  const _RuleRow({required this.rule, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 14, AppSpacing.md, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(rule.icon, size: 22, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rule.title, style: AppText.bodyStrong),
            const SizedBox(height: 2),
            Text(rule.body, style: AppText.body),
          ]),
        ),
      ]),
    );
  }
}

/// Small "Terms" text link used under the coins and temple trip screens.
class TermsLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const TermsLink({super.key, this.label = 'Terms', required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
      ),
      icon: const Icon(Icons.description_outlined, size: 16),
      label: Text(label),
    );
  }
}
