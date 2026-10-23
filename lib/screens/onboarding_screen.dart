import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

/// One full-bleed onboarding slide.
class OnboardingSlide {
  final String image;

  /// Which part of the photo stays in view when it is cropped to the screen.
  final Alignment focus;

  /// Short bold headline (six words at most).
  final String title;

  /// One line that says what the feature does.
  final String subtitle;

  /// Describes the photo for screen readers.
  final String imageLabel;

  const OnboardingSlide({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.imageLabel,
    this.focus = Alignment.center,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Shown above the headline of the first slide so people know the app's name.
  static const welcome = 'Welcome to CosmicGuide';

  /// The wordmark in the top bar.
  static const brand = 'CosmicGuide';

  static const slides = <OnboardingSlide>[
    OnboardingSlide(
      image: 'assets/images/onboarding_1.jpg',
      focus: Alignment(0.15, 0),
      title: 'Your true Vedic Kundli',
      subtitle: 'Made from your exact birth time and place.',
      imageLabel: 'A woman studying a glowing birth chart',
    ),
    OnboardingSlide(
      image: 'assets/images/topic_moon_calendar.jpg',
      title: 'Your day, in plain words',
      subtitle: 'Daily guidance from your chart and the Panchang.',
      imageLabel: 'Phases of the Moon over a mountain lake',
    ),
    OnboardingSlide(
      image: 'assets/images/topic_love_compatibility.jpg',
      title: 'Match with people you love',
      subtitle: '36-point Guna Milan for partners, family and friends.',
      imageLabel: 'A couple holding hands at sunset',
    ),
    OnboardingSlide(
      image: 'assets/images/topic_transits_today.jpg',
      title: 'Ask anytime, get real answers',
      subtitle: 'An AI astrologer that knows your chart, or a live pandit.',
      imageLabel: 'Saturn with glowing rings among the stars',
    ),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode every photo up front so swiping never shows an empty frame.
    if (!_precached) {
      _precached = true;
      for (final slide in _slides) {
        precacheImage(AssetImage(slide.image), context, onError: (_, __) {});
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.xs, 0),
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
            TextButton(
              onPressed: _navigateToNextScreen,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textOnDark,
                minimumSize: const Size(56, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Skip', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    final duration = _reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return Semantics(
      label: 'Step ${_currentIndex + 1} of ${_slides.length}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _slides.length; i++)
              AnimatedContainer(
                key: ValueKey('onboarding-dot-$i'),
                duration: duration,
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _currentIndex ? 22 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _currentIndex ? AppColors.primary : Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Height kept free at the bottom of each slide for the dots and button.
  static const double _controlsHeight = 6 + AppSpacing.lg + 52 + AppSpacing.md * 2;

  Widget _slide(BuildContext context, int index) {
    final slide = _slides[index];
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          image: true,
          label: slide.imageLabel,
          child: Image.asset(
            slide.image,
            fit: BoxFit.cover,
            alignment: slide.focus,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.cosmicGradient),
            ),
          ),
        ),
        // Scrims: a light one under the top bar, a deep one under the copy.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xCC0B0820), Color(0xFA0B0820)],
                stops: [0, 0.2, 0.42, 0.7, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            padding.top + 60,
            AppSpacing.xl,
            padding.bottom + _controlsHeight,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (index == 0) ...[
                          Text(
                            OnboardingScreen.welcome,
                            style: AppText.overline.copyWith(color: AppColors.gold, fontSize: 12, letterSpacing: 0.4),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.15,
                          child: Text(
                            slide.title,
                            style: AppText.display.copyWith(color: AppColors.textOnDark, fontSize: 30, height: 1.15),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          slide.subtitle,
                          style: AppText.body.copyWith(color: AppColors.textOnDarkMuted, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.cosmic,
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
                      child: Align(
                        alignment: Alignment.centerLeft,
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
