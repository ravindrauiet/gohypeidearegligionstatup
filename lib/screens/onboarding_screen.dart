import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/onboarding/onboarding_page.dart';
import '../widgets/ui/app_ui.dart';

export '../widgets/onboarding/onboarding_page.dart' show OnboardingSlide, OnboardingVisual;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Shown above the headline of the first slide so people know the app's name.
  static const welcome = 'Welcome to CosmicGuide';

  /// The wordmark in the top bar.
  static const brand = 'CosmicGuide';

  static const slides = <OnboardingSlide>[
    OnboardingSlide(
      eyebrow: 'Buddy match',
      title: 'Find your buddy, matched by your Kundli',
      subtitle:
          'Life partner, business partner, friends, travel and satsang buddies. Matched on your real Kundli and 50 mindset questions.',
      imageLabel: 'A sample match card: Ananya, 87 percent match, with Kundli, mindset and distance scores',
      visual: OnboardingVisual.buddyMatch,
      accent: Color(0xFFFF8FB1),
      background: [Color(0xFF2E1455), Color(0xFF150A2E)],
    ),
    OnboardingSlide(
      eyebrow: 'Near you',
      title: 'Buddies near you, safe and private',
      subtitle: 'See matches close to you. Chat only when both agree. 18+, report & block. No one sees your birth details.',
      imageLabel: 'People a few kilometres away, a connect request and safety badges',
      visual: OnboardingVisual.nearby,
      accent: Color(0xFF38BDF8),
      background: [Color(0xFF0E2447), Color(0xFF07122A)],
    ),
    OnboardingSlide(
      eyebrow: 'Daily rewards',
      title: 'Earn coins every single day',
      subtitle: 'Check in daily, play games for +10, watch Bhakti videos for +1, answer mindset questions for +50.',
      imageLabel: 'A coin wallet counting up, with daily tasks ticked off',
      visual: OnboardingVisual.coins,
      accent: AppColors.gold,
      background: [Color(0xFF3D2409), Color(0xFF1A0F05)],
    ),
    OnboardingSlide(
      eyebrow: 'Free temple trip',
      title: 'Reach 10,000 coins, get a free temple trip',
      subtitle: 'We sponsor a trip for you and your buddy to a famous temple near you both.',
      imageLabel: 'A Himalayan temple at sunrise with a coin goal almost reached',
      visual: OnboardingVisual.templeTrip,
      accent: Color(0xFFFF9A4D),
      background: [Color(0xFF3E1509), Color(0xFF1B0905)],
    ),
    OnboardingSlide(
      eyebrow: 'Bhakti & games',
      title: 'Bhakti videos and fun games, all in one place',
      subtitle: 'Watch devotional series, bhajans and katha anytime. Play quick games and earn coins as you go.',
      imageLabel: 'Ramayan katha, Hanuman Chalisa and a games tile',
      visual: OnboardingVisual.bhakti,
      accent: Color(0xFFFDBA74),
      background: [Color(0xFF3A1030), Color(0xFF190717)],
    ),
    OnboardingSlide(
      eyebrow: 'Kundli & AI astrologer',
      title: 'Your Kundli and an AI astrologer, always with you',
      subtitle:
          'Accurate Vedic Kundli, daily guidance, Panchang and festivals. Ask our AI anytime, or talk to a real pandit.',
      imageLabel: 'A Vedic birth chart, today\'s Panchang and a chat with the AI astrologer',
      visual: OnboardingVisual.kundli,
      accent: Color(0xFFC4B5FD),
      background: [Color(0xFF2B1E6E), Color(0xFF110C30)],
    ),
  ];

  /// Every photo the slides draw, so they can be decoded up front.
  static List<String> get images => [
        for (final s in slides)
          if (s.image != null) s.image!,
        ...OnboardingPhotoVisual.allPhotos,
      ];

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _leaving = false;
  bool _precached = false;

  List<OnboardingSlide> get _slides => OnboardingScreen.slides;
  bool get _isLast => _currentIndex == _slides.length - 1;
  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  Duration get _quick => _reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode every photo up front so swiping never shows an empty frame.
    if (!_precached) {
      _precached = true;
      for (final image in OnboardingScreen.images) {
        precacheImage(AssetImage(image), context, onError: (_, __) {});
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToNextScreen() {
    if (_leaving) return;
    _leaving = true;
    // Persist (fire-and-forget) so returning users skip onboarding next launch.
    AuthFlow.markOnboardingSeen();
    final backendService = context.read<BackendService>();
    final route = backendService.isAuthenticated ? AuthFlow.routeAfterLogin(backendService) : AppRoutes.login;
    Navigator.pushReplacementNamed(context, route);
  }

  void _goTo(int page) {
    // Reduced motion: change slide without the sliding animation.
    if (_reduceMotion) {
      _pageController.jumpToPage(page);
    } else {
      _pageController.animateToPage(page, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  void _nextPage() => _isLast ? _navigateToNextScreen() : _goTo(_currentIndex + 1);

  /// Height of the top bar below the status bar.
  static const double _topBarHeight = 52;

  /// Height kept free at the bottom of each slide for the dots and button.
  static const double _controlsHeight = 6 + AppSpacing.lg + 52 + AppSpacing.md * 2;

  Widget _topBar() {
    return SizedBox(
      height: _topBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.xs, 0),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Row(
            children: [
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.asset(
                    'assets/icons/cosmicguide_icon.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 28, height: 28),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  OnboardingScreen.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle.copyWith(color: AppColors.textOnDark, fontWeight: FontWeight.w800),
                ),
              ),
              // On the last slide the big button does the same job.
              AnimatedOpacity(
                duration: _quick,
                opacity: _isLast ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _isLast,
                  child: ExcludeSemantics(
                    excluding: _isLast,
                    child: TextButton(
                      key: const ValueKey('onboarding-skip'),
                      onPressed: _navigateToNextScreen,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textOnDark,
                        minimumSize: const Size(56, 44),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      ),
                      child: const Text('Skip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    final accent = _slides[_currentIndex].accent;
    return Semantics(
      label: 'Step ${_currentIndex + 1} of ${_slides.length}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                key: ValueKey('onboarding-dot-$i'),
                duration: _quick,
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _currentIndex ? 24 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _currentIndex
                      ? accent
                      : i < _currentIndex
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slide(BuildContext context, int index) {
    final padding = MediaQuery.paddingOf(context);
    final slide = _slides[index];
    return OnboardingPage(
      slide: slide,
      visual: OnboardingPhotoVisual(slide: slide),
      topInset: padding.top + _topBarHeight + AppSpacing.xs,
      bottomInset: padding.bottom + _controlsHeight,
      showWelcome: index == 0,
      welcome: OnboardingScreen.welcome,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _slides[_currentIndex].background.last,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        // System back walks back through the slides before leaving the app.
        canPop: _currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goTo(_currentIndex - 1);
        },
        child: Scaffold(
          backgroundColor: AppColors.cosmic,
          body: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemCount: _slides.length,
                itemBuilder: _slide,
              ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _dots(),
                              const SizedBox(height: AppSpacing.lg),
                              AppButton(
                                key: const ValueKey('onboarding-next'),
                                label: _isLast ? 'Get started' : 'Next',
                                icon: _isLast ? Icons.auto_awesome_rounded : null,
                                onPressed: _nextPage,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
