import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

class _Topic {
  final String id;
  final String title;
  final String subtitle;
  final String image;
  const _Topic(this.id, this.title, this.subtitle, this.image);
}

class TopicSelectionScreen extends StatefulWidget {
  const TopicSelectionScreen({super.key});

  /// SharedPreferences key holding the ids of the topics the user picked.
  static const prefsKey = 'interest_topics';

  @override
  State<TopicSelectionScreen> createState() => _TopicSelectionScreenState();
}

class _TopicSelectionScreenState extends State<TopicSelectionScreen> {
  static const List<_Topic> _topics = [
    _Topic(
      'kundli',
      'My Vedic Kundli',
      'Your birth chart from your exact birth time and place, with your planets, Lagna and Dasha.',
      'assets/images/topic_birth_chart.jpg',
    ),
    _Topic(
      'love',
      'Love & marriage matching',
      'See how well you match with a partner using 36-point Guna Milan.',
      'assets/images/topic_love_compatibility.jpg',
    ),
    _Topic(
      'day',
      "How's my day today",
      "What today is good for, what to be careful with and your best time, with the day's Panchang.",
      'assets/images/topic_how_is_my_day.jpg',
    ),
    _Topic(
      'panchang',
      "Today's Panchang & Moon",
      "The day's tithi (lunar day), nakshatra (star), good and bad times, and the Moon's phase.",
      'assets/images/topic_moon_calendar.jpg',
    ),
    _Topic(
      'transits',
      'My planet weather',
      'How Saturn, Jupiter and your Dasha are touching your life right now.',
      'assets/images/topic_transits_today.jpg',
    ),
  ];

  final Set<int> _selectedIndices = {0};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final t in _topics) {
      precacheImage(AssetImage(t.image), context, onError: (_, __) {});
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (!_selectedIndices.remove(index)) _selectedIndices.add(index);
    });
  }

  Future<void> _saveSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (_selectedIndices.toList()..sort()).map((i) => _topics[i].id).toList();
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

  @override
  Widget build(BuildContext context) {
    final count = _selectedIndices.length;
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
                itemCount: _topics.length + 1,
                separatorBuilder: (_, i) => SizedBox(height: i == 0 ? AppSpacing.lg : AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What would you like to explore first?', style: AppText.display),
                        SizedBox(height: 6),
                        Text('Pick one or more. We will set up your Kundli next.', style: AppText.body),
                      ],
                    );
                  }
                  final i = index - 1;
                  return _TopicCard(
                    topic: _topics[i],
                    selected: _selectedIndices.contains(i),
                    onTap: () => _toggleSelection(i),
                  );
                },
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

/// Photo card with a check in the corner when selected.
class _TopicCard extends StatelessWidget {
  final _Topic topic;
  final bool selected;
  final VoidCallback onTap;

  const _TopicCard({required this.topic, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final duration =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 160);
    return Semantics(
      button: true,
      selected: selected,
      label: topic.title,
      hint: topic.subtitle,
      excludeSemantics: true,
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
                  AppImage(topic.image, width: 84, height: 84, radius: BorderRadius.circular(AppRadius.md)),
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
