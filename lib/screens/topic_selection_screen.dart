import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

/// One interest. Shows [image] when set, otherwise [icon] on a gradient tile.
class _Topic {
  final String id;
  final String title;
  final String subtitle;
  final String? image;
  final IconData icon;
  final List<Color> colors;

  const _Topic(
    this.id,
    this.title,
    this.subtitle, {
    this.image,
    this.icon = Icons.auto_awesome_rounded,
    this.colors = const [Color(0xFFFF8A2B), AppColors.primary],
  });
}

class _Section {
  final String title;
  final List<_Topic> topics;
  const _Section(this.title, this.topics);
}

class TopicSelectionScreen extends StatefulWidget {
  const TopicSelectionScreen({super.key});

  /// SharedPreferences key holding the ids of the topics the user picked.
  static const prefsKey = 'interest_topics';

  /// Interest ids in display order (the order they are saved in).
  static List<String> get topicIds => [for (final s in _sections) ...s.topics.map((t) => t.id)];

  /// Picked when the screen opens.
  static const defaultSelection = {'kundli'};

  static const List<_Section> _sections = [
    _Section('Find your people', [
      _Topic(
        'life_partner',
        'Find a life partner',
        'Matches from your real Kundli and 50 mindset questions, not just photos.',
        image: 'assets/images/onboarding_2.jpg',
      ),
      _Topic(
        'business_partner',
        'Business partner',
        'Meet people with the same goals, values and work style to build with.',
        icon: Icons.handshake_rounded,
        colors: [Color(0xFF4F46E5), Color(0xFF1B1446)],
      ),
      _Topic(
        'friends',
        'Friends & community',
        'Friends with the same mindset, close to where you live.',
        icon: Icons.diversity_3_rounded,
        colors: [Color(0xFF22C55E), Color(0xFF15803D)],
      ),
      _Topic(
        'travel',
        'Travel buddy',
        'Find a buddy for yatras and temple trips, and earn a free trip together.',
        image: 'assets/images/heroBanner.jpg',
      ),
      _Topic(
        'satsang',
        'Satsang',
        'Join people near you for satsang, kirtan and seva.',
        image: 'assets/images/featuredPuja.jpg',
      ),
    ]),
    _Section('Bhakti & rewards', [
      _Topic(
        'bhajans',
        'Bhajans & videos',
        'Devotional series, bhajans and katha, all inside the app.',
        image: 'assets/images/hanuman_chalisa.jpg',
      ),
      _Topic(
        'games',
        'Games & rewards',
        'Play quick games, earn coins every day and unlock a free temple trip.',
        icon: Icons.sports_esports_rounded,
        colors: [Color(0xFFF5B83D), Color(0xFFE5760A)],
      ),
    ]),
    _Section('Kundli & daily guidance', [
      _Topic(
        'kundli',
        'My Vedic Kundli',
        'Your birth chart from your exact birth time and place, with your planets, Lagna and Dasha.',
        image: 'assets/images/topic_birth_chart.jpg',
      ),
      _Topic(
        'love',
        'Love & marriage matching',
        'See how well you match with a partner using 36-point Guna Milan.',
        image: 'assets/images/topic_love_compatibility.jpg',
      ),
      _Topic(
        'day',
        "How's my day today",
        "What today is good for, what to be careful with and your best time, with the day's Panchang.",
        image: 'assets/images/topic_how_is_my_day.jpg',
      ),
      _Topic(
        'panchang',
        "Today's Panchang & Moon",
        "The day's tithi (lunar day), nakshatra (star), good and bad times, and the Moon's phase.",
        image: 'assets/images/topic_moon_calendar.jpg',
      ),
      _Topic(
        'transits',
        'My planet weather',
        'How Saturn, Jupiter and your Dasha are touching your life right now.',
        image: 'assets/images/topic_transits_today.jpg',
      ),
    ]),
  ];

  @override
  State<TopicSelectionScreen> createState() => _TopicSelectionScreenState();
}

class _TopicSelectionScreenState extends State<TopicSelectionScreen> {
  static const _sections = TopicSelectionScreen._sections;

  final Set<String> _selected = {...TopicSelectionScreen.defaultSelection};
  bool _precached = false;

  /// Flat list of rows: the intro, section headers and topic cards.
  late final List<Object> _rows = [
    'intro',
    for (final s in _sections) ...[s, ...s.topics],
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final s in _sections) {
      for (final t in s.topics) {
        if (t.image != null) precacheImage(AssetImage(t.image!), context, onError: (_, __) {});
      }
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _saveSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = TopicSelectionScreen.topicIds.where(_selected.contains).toList();
      await prefs.setStringList(TopicSelectionScreen.prefsKey, ids);
    } catch (e) {
      debugPrint('Could not save topics: $e');
    }
  }

  void _proceed() {
    _saveSelection();
    // Push (not replace) so back from birth details returns to the topics.
    Navigator.pushNamed(context, AppRoutes.birthDetails);
  }

  void _skipToDashboard() {
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
  }

  Widget _row(BuildContext context, int index) {
    final row = _rows[index];
    if (row is _Section) {
      return Padding(
        padding: EdgeInsets.only(top: index == 1 ? 0 : AppSpacing.sm, bottom: AppSpacing.xxs),
        child: Semantics(
          header: true,
          child: Text(row.title.toUpperCase(), style: AppText.overline.copyWith(color: AppColors.textSecondary)),
        ),
      );
    }
    if (row is _Topic) {
      return _TopicCard(
        topic: row,
        selected: _selected.contains(row.id),
        onTap: () => _toggleSelection(row.id),
      );
    }
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What would you like to explore first?', style: AppText.display),
        SizedBox(height: 6),
        Text('Pick as many as you like. Next we make your Kundli, which powers your matches too.',
            style: AppText.body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.xs, 0),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _skipToDashboard,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size(56, 44),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
                itemCount: _rows.length,
                separatorBuilder: (_, i) => SizedBox(height: i == 0 ? AppSpacing.lg : AppSpacing.sm),
                itemBuilder: _row,
              ),
            ),
            // Sticky bottom CTA.
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          count == 0 ? 'Select at least one' : '$count selected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppButton(
                        label: 'Proceed',
                        expand: false,
                        onPressed: count == 0 ? null : _proceed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photo (or icon) card with a check in the corner when selected.
class _TopicCard extends StatelessWidget {
  final _Topic topic;
  final bool selected;
  final VoidCallback onTap;

  const _TopicCard({required this.topic, required this.selected, required this.onTap});

  static const double _thumb = 84;

  @override
  Widget build(BuildContext context) {
    final duration =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 160);
    final radius = BorderRadius.circular(AppRadius.md);
    final thumb = topic.image != null
        ? AppImage(topic.image!, width: _thumb, height: _thumb, radius: radius)
        : Container(
            width: _thumb,
            height: _thumb,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(colors: topic.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Icon(topic.icon, size: 36, color: Colors.white),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: topic.title,
      hint: topic.subtitle,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: AppRadius.card,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  thumb,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                        const SizedBox(height: 4),
                        Text(
                          topic.subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedContainer(
                    duration: duration,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.primary : AppColors.surface,
                      border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1.6),
                    ),
                    child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
