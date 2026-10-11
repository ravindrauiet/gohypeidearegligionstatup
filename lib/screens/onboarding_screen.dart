import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/onboarding_art.dart';
import '../widgets/onboarding_chrome.dart';

class _Slide {
  final String category;

  /// The title is split in three so one key phrase can be shown in gold.
  final String titleBefore;
  final String titleGold;
  final String titleAfter;
  final String subtitle;
  final String button;
  final Color accent;
  const _Slide(
    this.category,
    this.titleBefore,
    this.titleGold,
    this.titleAfter,
    this.subtitle,
    this.button,
    this.accent,
  );

  String get title => '$titleBefore$titleGold$titleAfter';
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Shown beside the brand mark on the first slide so people know the app's
  /// name.
  static const welcome = 'Welcome to CosmicGuide';

  /// The wordmark on the other slides.
  static const brand = 'CosmicGuide';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // One slide per thing this app really does. The pictures are drawn in code
  // (lib/widgets/onboarding_art.dart) as previews of the real screens. The
  // accents are the bright-on-dark versions of each feature's colour.
  static const List<_Slide> _slides = [
    _Slide(
      'VEDIC KUNDLI',
      'Your true ',
      'Vedic Kundli',
      '',
      'Made from your exact birth time and place, anywhere in the world. See your Lagna (rising sign), '
          'nakshatra (birth star), D9 and D10 charts and Dasha timeline.',
      'Begin',
      Color(0xFFFFA45C),
    ),
    _Slide(
      'YOUR DAY',
      'Your day, in ',
      'simple words',
      '',
      'Each morning: what today is good for, what to be careful with and your best time, from your '
          "own chart and the day's Panchang (Hindu calendar). Weekly and monthly too.",
      'Sounds good',
      Color(0xFF9B8CFF),
    ),
    _Slide(
      'WHY THINGS HAPPEN',
      'Know ',
      'why',
      ' things happen',
      'See how Saturn, Jupiter and your Dasha (life chapter) shape your life right now, look ahead '
          'on your Life Timeline, or pick a past date and ask why it happened.',
      'Show me',
      Color(0xFF5AA9FF),
    ),
    _Slide(
      'COSMIC GAMES',
      '',
      'Play',
      ' with your planets',
      'Your nine planets are your team. Finish three small real-life missions a day, collect the '
          "Moon's star cards and play Moksha Patam, the original Snakes & Ladders.",
      "Let's play",
      Color(0xFFFFB534),
    ),
    _Slide(
      'PEOPLE YOU LOVE',
      'Match with the ',
      'people you love',
      '',
      'Real 36-point Guna Milan with a partner, charts for your whole family, and a Cosmic Circle '
          "with friends: find your cosmic twin and see who's luckiest today.",
      'Nice',
      Color(0xFFFF6FB5),
    ),
    _Slide(
      'ASK ANYTIME',
      'Ask anytime, get ',
      'real answers',
      '',
      "Chat with an AI astrologer that already knows your chart and today's planets, or talk to a "
          'real pandit live when it matters.',
      'Get started',
      Color(0xFF3DDC97),
    ),
  ];

  bool _leaving = false;

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

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _goTo(int page) {
    // Reduced motion: change slide without the sliding animation.
    if (_reduceMotion) {
      _pageController.jumpToPage(page);
    } else {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _nextPage() {
    if (_currentIndex < _slides.length - 1) {
      _goTo(_currentIndex + 1);
    } else {
      _navigateToNextScreen();
    }
  }

  /// The pager's fractional page (falls back to the current index before the
  /// first layout).
  double get _page {
    if (!_pageController.hasClients || !_pageController.position.haveDimensions) {
      return _currentIndex.toDouble();
    }
    return _pageController.page ?? _currentIndex.toDouble();
  }

  /// Signed distance of slide [index] from the pager's centre, for parallax.
  double _offsetOf(int index) => (_page - index).clamp(-1.0, 1.0);

  /// The accent between two slides while swiping, so the sky cross-fades.
  Color _accentAt(double page) {
    final p = page.clamp(0.0, _slides.length - 1.0);
    final a = p.floor();
    final b = math.min(a + 1, _slides.length - 1);
    return Color.lerp(_slides[a].accent, _slides[b].accent, p - a)!;
  }

  Widget _hero(int index) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) => OnboardingArt(
        index: index,
        active: index == _currentIndex,
        accent: _slides[index].accent,
        parallax: _offsetOf(index),
      ),
    );
  }

  /// Eyebrow, title and subtitle. They slide a little against the hero while
  /// swiping and scroll (with a fade hint) if there is not enough room.
  Widget _text(int index, {required bool compact}) {
    final slide = _slides[index];
    final accent = slide.accent;
    final titleSize = compact ? 26.0 : 30.0;
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        final off = _reduceMotion ? 0.0 : _offsetOf(index);
        return Transform.translate(
          offset: Offset(-off * 26, 0),
          child: Opacity(opacity: (1 - off.abs() * 0.7).clamp(0.0, 1.0), child: child),
        );
      },
      child: _ScrollWithHint(
        padding: EdgeInsets.fromLTRB(compact ? 20 : 24, 4, compact ? 20 : 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 18,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.8), blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    slide.category,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Already large, so it grows only a little with the system text size.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: LayoutBuilder(
                builder: (context, c) {
                  // The same light-to-deep gold on every line of the title.
                  final line = MediaQuery.textScalerOf(context).scale(titleSize) * 1.14;
                  final gold = Paint()
                    ..shader = const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFFE9B8), onboardingGoldLight, onboardingGoldDeep],
                      stops: [0.1, 0.45, 0.95],
                      tileMode: TileMode.repeated,
                    ).createShader(Rect.fromLTWH(0, 0, c.maxWidth, line));
                  // Own layer: a text shader is positioned in layer coordinates, so
                  // this keeps the gradient aligned with the lines of the title.
                  return RepaintBoundary(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (slide.titleBefore.isNotEmpty) TextSpan(text: slide.titleBefore),
                          TextSpan(text: slide.titleGold, style: TextStyle(foreground: gold)),
                          if (slide.titleAfter.isNotEmpty) TextSpan(text: slide.titleAfter),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.14,
                        letterSpacing: -0.4,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              slide.subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.74),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(BuildContext context, int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final w = math.min(constraints.maxWidth, 520.0);
        final compact = constraints.maxWidth < 340;

        // Short and wide (phone in landscape): hero and text side by side.
        if (h < 430 && constraints.maxWidth > h * 1.25) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Row(
                children: [
                  Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _hero(index))),
                  Expanded(child: Center(child: _text(index, compact: true))),
                ],
              ),
            ),
          );
        }

        // Portrait: the hero takes the top of the page edge to edge; the text
        // may use what is left and scrolls only if it still does not fit.
        final heroFull = w * onboardingArtHeight / onboardingArtWidth;
        final heroMin = math.min(heroFull, h * 0.54);
        return Column(
          // Phones: hero right under the top bar, so the text starts at the same
          // height on every slide. Roomy screens: centre the whole composition.
          mainAxisAlignment: h > heroFull + 340 ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Flexible(
              child: SizedBox(width: w, height: heroFull, child: _hero(index)),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w, maxHeight: math.max(0, h - heroMin)),
              child: _text(index, compact: compact),
            ),
          ],
        );
      },
    );
  }

  Widget _topBar() {
    final first = _currentIndex == 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, _) => OnboardingProgress(page: _page, count: _slides.length),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 8),
            child: SizedBox(
              height: 46,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: Row(
                  children: [
                    const ExcludeSemantics(child: OnboardingMark(size: 22)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (first)
                                  TextSpan(
                                    text: OnboardingScreen.welcome
                                        .substring(0, OnboardingScreen.welcome.length - OnboardingScreen.brand.length),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.72),
                                    ),
                                  ),
                                const TextSpan(text: OnboardingScreen.brand),
                              ],
                            ),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_currentIndex + 1}/${_slides.length}',
                      semanticsLabel: 'Step ${_currentIndex + 1} of ${_slides.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        letterSpacing: 1.2,
                        color: Colors.white.withValues(alpha: 0.6),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextButton(
                      onPressed: _navigateToNextScreen,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(56, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentIndex];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: onboardingNight,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        // System back walks back through the slides before leaving the app.
        canPop: _currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goTo(_currentIndex - 1);
        },
        child: Scaffold(
          backgroundColor: onboardingNight,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Night sky; its glow takes on the colour of the slide in view.
              ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, _) => OnboardingSky(accent: _accentAt(_page), epoch: _currentIndex),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _currentIndex = index;
                          });
                        },
                        itemCount: _slides.length,
                        itemBuilder: _buildSlide,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 472),
                        child: OnboardingPrimaryButton(
                          label: slide.button,
                          onPressed: _nextPage,
                          icon: _currentIndex == _slides.length - 1 ? Icons.auto_awesome : Icons.arrow_forward_rounded,
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

/// A scroll view that only scrolls when its child does not fit, and then
/// fades its bottom edge and shows a small arrow so it is obvious there is
/// more to read.
class _ScrollWithHint extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;
  const _ScrollWithHint({required this.child, required this.padding});

  @override
  State<_ScrollWithHint> createState() => _ScrollWithHintState();
}

class _ScrollWithHintState extends State<_ScrollWithHint> {
  final ScrollController _controller = ScrollController();
  // Keeps the scroll position when the fade is added or removed around it.
  final GlobalKey _scrollKey = GlobalKey();
  bool _more = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients || !_controller.position.hasContentDimensions) return;
    final more = _controller.position.extentAfter > 6;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    Widget scroll = SingleChildScrollView(
      key: _scrollKey,
      controller: _controller,
      padding: widget.padding,
      child: widget.child,
    );
    if (_more) {
      scroll = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.72, 1],
        ).createShader(rect),
        child: scroll,
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _update();
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (_) {
          _update();
          return false;
        },
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            scroll,
            if (_more)
              IgnorePointer(
                child: ExcludeSemantics(
                  child: Container(
                    width: 30,
                    height: 20,
                    margin: const EdgeInsets.only(bottom: 0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
