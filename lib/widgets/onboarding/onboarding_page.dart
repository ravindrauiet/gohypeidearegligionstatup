import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../ui/app_ui.dart';

/// Which illustrated card a slide shows above its copy.
enum OnboardingVisual { buddyMatch, nearby, coins, templeTrip, bhakti, kundli }

/// One onboarding slide: an illustrated card built from widgets, a short
/// headline and one or two lines of body copy.
class OnboardingSlide {
  /// Small label above the headline.
  final String eyebrow;

  /// Bold headline (twelve words at most).
  final String title;

  /// Body copy (about twenty words at most).
  final String subtitle;

  /// Describes the illustration for screen readers.
  final String imageLabel;

  /// Optional photo shown, dimmed, behind the whole slide.
  final String? image;

  /// Which part of [image] stays in view when it is cropped to the screen.
  final Alignment focus;

  final OnboardingVisual visual;

  /// Accent for the eyebrow, active dot and glows.
  final Color accent;

  /// Full-bleed background gradient colours (top to bottom).
  final List<Color> background;

  const OnboardingSlide({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.imageLabel,
    required this.visual,
    required this.accent,
    required this.background,
    this.image,
    this.focus = Alignment.center,
  });
}

/// The single, still photo a slide shows in a rounded card. No animation on
/// purpose; onboarding stays simple. Photos: see assets/PHOTO_CREDITS.md.
class OnboardingPhotoVisual extends StatelessWidget {
  final OnboardingSlide slide;
  const OnboardingPhotoVisual({super.key, required this.slide});

  /// The photo for each slide and which part stays in view when cropped.
  static (String, Alignment) photoFor(OnboardingVisual visual) => switch (visual) {
        OnboardingVisual.buddyMatch => ('assets/images/ob_buddy.jpg', const Alignment(0, -0.45)),
        OnboardingVisual.nearby => ('assets/images/ob_nearby.jpg', const Alignment(-0.1, -0.2)),
        OnboardingVisual.coins => ('assets/images/ob_coins.jpg', const Alignment(0, 0.1)),
        OnboardingVisual.templeTrip => ('assets/images/ob_temple.jpg', const Alignment(-0.15, 0)),
        OnboardingVisual.bhakti => ('assets/images/ob_bhakti.jpg', const Alignment(-0.3, -0.3)),
        OnboardingVisual.kundli => ('assets/images/topic_birth_chart.jpg', Alignment.center),
      };

  static List<String> get allPhotos => [for (final v in OnboardingVisual.values) photoFor(v).$1];

  @override
  Widget build(BuildContext context) {
    final (path, focus) = photoFor(slide.visual);
    return Center(
      child: Container(
        width: 300,
        height: 360,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 6))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          path,
          fit: BoxFit.cover,
          alignment: focus,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => ColoredBox(color: slide.accent.withValues(alpha: 0.2)),
        ),
      ),
    );
  }
}

/// Lays out one slide: full-bleed background, the illustration filling the
/// free space (scaled to fit) and the copy underneath. On short screens the
/// illustration keeps a minimum height and the slide scrolls instead.
class OnboardingPage extends StatelessWidget {
  final OnboardingSlide slide;
  final Widget visual;
  final bool showWelcome;
  final String welcome;

  /// Space kept free at the top (top bar) and bottom (dots and button).
  final double topInset;
  final double bottomInset;

  const OnboardingPage({
    super.key,
    required this.slide,
    required this.visual,
    required this.topInset,
    required this.bottomInset,
    this.showWelcome = false,
    this.welcome = '',
  });

  /// The illustrations are drawn on a canvas this wide and scaled to fit.
  static const double canvasWidth = 320;

  /// Smallest height the illustration gets before the slide starts scrolling.
  static const double minVisualHeight = 150;

  /// Below this content height the copy tightens up so it fits without scrolling.
  static const double compactHeight = 460;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Background(slide: slide),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.xl, topInset, AppSpacing.xl, bottomInset),
          child: LayoutBuilder(
            builder: (context, constraints) => _content(constraints, constraints.maxHeight < compactHeight),
          ),
        ),
      ],
    );
  }

  Widget _content(BoxConstraints constraints, bool compact) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _FixedIntrinsicHeight(
                      height: compact ? 110 : minVisualHeight,
                      child: Semantics(
                        image: true,
                        label: slide.imageLabel,
                        child: ExcludeSemantics(
                          child: Align(
                            alignment: const Alignment(0, 0.4),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: MediaQuery.withNoTextScaling(
                                  child: SizedBox(
                                    width: canvasWidth,
                                    child: visual,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
                  _Copy(slide: slide, welcome: showWelcome ? welcome : null, compact: compact),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Copy extends StatelessWidget {
  final OnboardingSlide slide;
  final String? welcome;
  final bool compact;

  const _Copy({required this.slide, this.welcome, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (welcome != null) ...[
          Text(
            welcome!,
            style: AppText.overline.copyWith(color: AppColors.gold, fontSize: 12, letterSpacing: 0.4),
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        // On short screens the welcome line stands in for the eyebrow.
        if (welcome == null || !compact)
          Text(
            slide.eyebrow.toUpperCase(),
            style: AppText.overline.copyWith(color: slide.accent, fontSize: 11.5, letterSpacing: 1.1),
          ),
        SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.xs),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: Text(
            slide.title,
            style: AppText.display.copyWith(
              color: AppColors.textOnDark,
              fontSize: compact ? 23 : 27,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text(
            slide.subtitle,
            style: AppText.body.copyWith(
              color: AppColors.textOnDarkMuted,
              fontSize: compact ? 14 : 15,
              height: compact ? 1.4 : 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _Background extends StatelessWidget {
  final OnboardingSlide slide;
  const _Background({required this.slide});

  @override
  Widget build(BuildContext context) {
    final colors = slide.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
          ),
        ),
        if (slide.image != null)
          Opacity(
            opacity: 0.32,
            child: Image.asset(
              slide.image!,
              fit: BoxFit.cover,
              alignment: slide.focus,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        // Soft accent glow behind the illustration.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.35),
                radius: 0.8,
                colors: [slide.accent.withValues(alpha: 0.28), slide.accent.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        // Deep scrim under the copy so the text always reads.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.transparent,
                  colors.last.withValues(alpha: 0.85),
                  colors.last,
                ],
                stops: const [0, 0.18, 0.45, 0.72, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports a fixed intrinsic height so [IntrinsicHeight] reserves exactly
/// [height] for the illustration on short screens, while the real layout
/// still lets it grow into whatever space is free.
class _FixedIntrinsicHeight extends SingleChildRenderObjectWidget {
  final double height;
  const _FixedIntrinsicHeight({required this.height, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFixedIntrinsicHeight(height);

  @override
  void updateRenderObject(BuildContext context, _RenderFixedIntrinsicHeight renderObject) {
    renderObject.height = height;
  }
}

class _RenderFixedIntrinsicHeight extends RenderProxyBox {
  _RenderFixedIntrinsicHeight(this._height);

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;
}
