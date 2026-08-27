import 'package:flutter/material.dart';

class TopicSelectionScreen extends StatefulWidget {
  const TopicSelectionScreen({super.key});

  @override
  State<TopicSelectionScreen> createState() => _TopicSelectionScreenState();
}

class _TopicSelectionScreenState extends State<TopicSelectionScreen> {
  final Set<int> _selectedIndices = {0}; // Default 1st topic selected matching image 2

  final List<Map<String, String>> _topics = [
    {
      'title': 'Explore my birth chart',
      'subtitle': 'Learn your unique qualities from planetary positions at birth.',
      'imagePath': 'assets/images/topic_birth_chart.jpg',
    },
    {
      'title': 'Love compatibility',
      'subtitle': 'See how your synastry charts work in your romantic relationship.',
      'imagePath': 'assets/images/topic_love_compatibility.jpg',
    },
    {
      'title': "How's my day today",
      'subtitle': "Find out how planetary movements impact your day's energies.",
      'imagePath': 'assets/images/topic_how_is_my_day.jpg',
    },
    {
      'title': "Today's moon calendar",
      'subtitle': 'See the current moon phase and its effects on your life.',
      'imagePath': 'assets/images/topic_moon_calendar.jpg',
    },
    {
      'title': 'My transits today',
      'subtitle': 'Know how current planetary movements influence your life path.',
      'imagePath': 'assets/images/topic_transits_today.jpg',
    },
  ];

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _proceed() {
    Navigator.pushReplacementNamed(context, '/birth-details');
  }

  void _skipToDashboard() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Header Title (Matching Image 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose a topic to explore\nyour astrological insights',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    height: 1.25,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Selectable Topic Cards List (Matching Image 2 & 3)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _topics.length + 1, // +1 for "Skip to dashboard" link
                itemBuilder: (context, index) {
                  if (index == _topics.length) {
                    // Skip to dashboard link at bottom of list
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _skipToDashboard,
                            child: const Text(
                              'Skip to dashboard',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(width: 80, height: 1.5, color: Colors.black87),
                        ],
                      ),
                    );
                  }

                  final topic = _topics[index];
                  final isSelected = _selectedIndices.contains(index);

                  return GestureDetector(
                    onTap: () => _toggleSelection(index),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.grey.shade400 : Colors.grey.shade200,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Thumbnail Image Square
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              topic['imagePath']!,
                              width: 85,
                              height: 85,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 85,
                                  height: 85,
                                  color: const Color(0xFFFB9548).withValues(alpha: 0.2),
                                  child: const Icon(Icons.auto_awesome, color: Color(0xFFFB9548)),
                                );
                              },
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Text Content & Checkmark
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        topic['title']!,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF00B074), // Emerald green checkmark matching image 2
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  topic['subtitle']!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Fixed Black Bottom Bar with Proceed > (Matching Image 2 & 3)
            Container(
              width: double.infinity,
              height: 64,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _proceed,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: const [
                        Text(
                          'Proceed',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
                      ],
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
}
