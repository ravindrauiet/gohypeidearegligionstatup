import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<Map<String, dynamic>> _onboardingData = [
    {
      'step': '1/6',
      'title': 'Welcome to AstroAI',
      'subtitle': 'Discover cosmic clarity, personalized birth chart insights, and real-time AI astrological guidance crafted for your soul.',
      'buttonText': 'Begin Journey',
      'cardTitle': 'Astro AI Cosmic Guide',
      'icon': Icons.auto_awesome,
      'accentColor': const Color(0xFFFB9548),
      'badges': ['Personal Kundli', 'AI Astrologer', '24/7 Guidance']
    },
    {
      'step': '2/6',
      'title': 'Your Relationship Insights',
      'subtitle': 'Explore the dynamics of your relationships with a detailed Synastry report. Understand how you connect with others on a deeper level.',
      'buttonText': "I'm Curious",
      'cardTitle': 'Synastry',
      'icon': Icons.favorite_rounded,
      'accentColor': const Color(0xFFFF6B81),
      'badges': ['Rishi ❤️ Olivia', 'Compatibility 94%', 'Soul Chemistry']
    },
    {
      'step': '3/6',
      'title': 'Explore your personal astro-map!',
      'subtitle': 'Discover the best locations for success, love, and well-being based on your stars with Astrocartography.',
      'buttonText': 'Tell Me More',
      'cardTitle': 'Astrocartography',
      'icon': Icons.public_rounded,
      'accentColor': const Color(0xFF317BEA),
      'badges': ['Location for LOVE?', 'Location for CAREER?', 'Location for LUCK?', 'Location for WEALTH?']
    },
    {
      'step': '4/6',
      'title': 'Moon Phases & You',
      'subtitle': "Stay in tune with the moon's cycles using our moon phase calendar. Learn how each phase impacts your emotions and daily activities.",
      'buttonText': 'Interesting',
      'cardTitle': 'Moon Calendar',
      'icon': Icons.nightlight_round,
      'accentColor': const Color(0xFF9C27B0),
      'badges': ['Full Moon (96%)', 'Uttara Ashadha', 'Illumination 96%', 'Aquarius']
    },
    {
      'step': '5/6',
      'title': 'Your Birthday Forecast',
      'subtitle': 'Get detailed predictions for your upcoming year. Understand key themes and insights for each month ahead with Solar Return.',
      'buttonText': "Let's Continue",
      'cardTitle': 'Solar Return Chart',
      'icon': Icons.wb_sunny_rounded,
      'accentColor': const Color(0xFFFF9800),
      'badges': ['Year Theme', 'Solar Return', 'Annual Focus']
    },
    {
      'step': '6/6',
      'title': 'Daily Horoscopes & Insights',
      'subtitle': 'Get your personalized daily horoscopes with practical advice for your day. Clear guidance based on your zodiac sign.',
      'buttonText': 'Get Started',
      'cardTitle': 'Daily Horoscope',
      'icon': Icons.brightness_7_rounded,
      'accentColor': const Color(0xFF4CAF50),
      'badges': ['Aries (Mar 21 - Apr 19)', 'Love 85%', 'Career 90%', 'Today Focus']
    },
  ];

  void _nextPage() {
    if (_currentIndex < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushReplacementNamed(context, '/birth-details');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Progress Counter & Skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/birth-details'),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black.withOpacity(0.1)),
                    ),
                    child: Text(
                      _onboardingData[_currentIndex]['step'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Onboarding Page Slider
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) {
                  final data = _onboardingData[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Decorative Card Container Mockup (Matching reference UI)
                        Expanded(
                          child: Center(
                            child: Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 380),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: (data['accentColor'] as Color).withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      data['icon'] as IconData,
                                      size: 56,
                                      color: data['accentColor'] as Color,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    data['cardTitle'],
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: data['accentColor'] as Color,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: (data['badges'] as List<String>).map((badge) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF7ED),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: (data['accentColor'] as Color).withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          badge,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: data['accentColor'] as Color,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Title
                        Text(
                          data['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            height: 1.25,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Subtitle
                        Text(
                          data['subtitle'],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Next / Action Button (Matching black rounded button in screenshots)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    _onboardingData[_currentIndex]['buttonText'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
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
