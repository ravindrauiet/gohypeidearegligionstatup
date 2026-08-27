import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

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
      'category': 'ASTRO AI COSMIC GUIDE',
      'title': 'Welcome to AstroAI',
      'subtitle': 'Discover cosmic clarity, personalized birth chart insights, and real-time AI astrological guidance crafted for your soul.',
      'buttonText': 'Begin Journey',
      'imagePath': 'assets/images/onboarding_1.jpg',
      'accentColor': const Color(0xFFFB9548),
    },
    {
      'step': '2/6',
      'category': 'SYNASTRY RELATIONSHIPS',
      'title': 'Your Relationship Insights',
      'subtitle': 'Explore the dynamics of your relationships with a detailed Synastry report. Understand how you connect with others on a deeper level.',
      'buttonText': "I'm Curious",
      'imagePath': 'assets/images/onboarding_2.jpg',
      'accentColor': const Color(0xFFFF6B81),
    },
    {
      'step': '3/6',
      'category': 'ASTROCARTOGRAPHY',
      'title': 'Explore Your Astro-Map',
      'subtitle': 'Discover the best locations across the globe for success, love, career, and fortune based on your natal planetary lines.',
      'buttonText': 'Tell Me More',
      'imagePath': 'assets/images/onboarding_3.jpg',
      'accentColor': const Color(0xFF317BEA),
    },
    {
      'step': '4/6',
      'category': 'LUNAR CYCLES',
      'title': 'Moon Phases & You',
      'subtitle': "Stay in tune with lunar energy shifts using our moon phase calendar. Learn how each phase impacts your emotions & intuition.",
      'buttonText': 'Interesting',
      'imagePath': 'assets/images/onboarding_4.jpg',
      'accentColor': const Color(0xFF9C27B0),
    },
    {
      'step': '5/6',
      'category': 'SOLAR RETURN',
      'title': 'Your Birthday Forecast',
      'subtitle': 'Get detailed annual predictions for your upcoming year. Understand key themes and monthly forecasts for your personal new year.',
      'buttonText': "Let's Continue",
      'imagePath': 'assets/images/onboarding_5.jpg',
      'accentColor': const Color(0xFFFF9800),
    },
    {
      'step': '6/6',
      'category': 'DAILY ASTROLOGY',
      'title': 'Daily Horoscopes & Insights',
      'subtitle': 'Get your personalized daily horoscope with actionable advice for your day. Clear, accurate guidance aligned with your stars.',
      'buttonText': 'Get Started',
      'imagePath': 'assets/images/onboarding_6.jpg',
      'accentColor': const Color(0xFF4CAF50),
    },
  ];

  void _navigateToNextScreen() {
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (backendService.isAuthenticated && backendService.hasBirthDetails) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _nextPage() {
    if (_currentIndex < _onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _navigateToNextScreen();
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _navigateToNextScreen,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                    ),
                    child: Text(
                      _onboardingData[_currentIndex]['step'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main PageView Content
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
                  final accentColor = data['accentColor'] as Color;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        // Sleek Category Tag Pill (Above Image)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            data['category'],
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // PRISTINE HERO IMAGE CARD
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                data['imagePath'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(
                                      Icons.auto_awesome,
                                      size: 60,
                                      color: accentColor,
                                    ),
                                  );
                                },
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
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            height: 1.2,
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
                            height: 1.45,
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Page Indicator Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_onboardingData.length, (index) {
                final isSelected = _currentIndex == index;
                final accentColor = _onboardingData[_currentIndex]['accentColor'] as Color;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected ? accentColor : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 16),

            // Bottom Action Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    _onboardingData[_currentIndex]['buttonText'],
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
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
