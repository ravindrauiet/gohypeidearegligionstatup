import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/home_promos.dart';
import 'ui/app_ui.dart';

/// Home ad / promo slot: 2:1 slides (image or video) with a peek of the next
/// slide, auto-advance and page dots.
///
/// Images stay for 6 seconds; a video stays until it ends. Videos are muted,
/// only play while their slide is showing and Home is visible, and fall back
/// to their poster if they cannot load (e.g. offline).
class PromoCarousel extends StatefulWidget {
  final List<HomePromo> promos;
  final ValueChanged<HomePromo> onTap;

  const PromoCarousel({super.key, required this.promos, required this.onTap});

  static const imageDuration = Duration(seconds: 6);

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _index = 0;
  bool _reduceMotion = false;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // False while Home is a hidden tab or covered by another screen.
    _visible = TickerMode.valuesOf(context).enabled;
    _scheduleNext();
  }

  bool get _currentIsVideo =>
      widget.promos.isNotEmpty && widget.promos[_index].type == PromoMediaType.video;

  void _scheduleNext({bool videoFailed = false}) {
    _timer?.cancel();
    if (_reduceMotion || !_visible || widget.promos.length < 2) return;
    // A playing video advances itself when it ends (see _onVideoEnded).
    if (_currentIsVideo && !videoFailed) return;
    _timer = Timer(PromoCarousel.imageDuration, _next);
  }

  void _next() {
    if (!mounted || !_controller.hasClients || widget.promos.length < 2) return;
    final next = (_index + 1) % widget.promos.length;
    _controller.animateToPage(next, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
  }

  void _onVideoEnded(int i) {
    if (i == _index && !_reduceMotion) _next();
  }

  void _onVideoFailed(int i) {
    if (i == _index) _scheduleNext(videoFailed: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.promos.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final height = (width * 0.92 - 12) / 2; // 2:1 slides
    final single = widget.promos.length == 1;

    return Column(
      children: [
        SizedBox(
          height: height,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (n) {
              // The user is swiping: hold auto-advance until the next page settles.
              if (n.dragDetails != null) _timer?.cancel();
              return false;
            },
            child: PageView.builder(
              controller: single ? PageController() : _controller,
              itemCount: widget.promos.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _scheduleNext();
              },
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: single ? AppSpacing.page : 6),
                child: _PromoSlide(
                  promo: widget.promos[i],
                  active: i == _index && _visible,
                  loop: single,
                  onTap: () => widget.onTap(widget.promos[i]),
                  onEnded: () => _onVideoEnded(i),
                  onFailed: () => _onVideoFailed(i),
                ),
              ),
            ),
          ),
        ),
        if (!single) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.promos.length, (i) {
              final selected = i == _index;
              return AnimatedContainer(
                duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: selected ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _PromoSlide extends StatefulWidget {
  final HomePromo promo;
  final bool active;
  final bool loop;
  final VoidCallback onTap;
  final VoidCallback onEnded;
  final VoidCallback onFailed;

  const _PromoSlide({
    required this.promo,
    required this.active,
    required this.loop,
    required this.onTap,
    required this.onEnded,
    required this.onFailed,
  });

  @override
  State<_PromoSlide> createState() => _PromoSlideState();
}

class _PromoSlideState extends State<_PromoSlide> {
  // Owned here (not in the video) so the mute button can sit above the
  // slide-wide tap target.
  final ValueNotifier<bool> _muted = ValueNotifier(true);
  final ValueNotifier<bool> _videoPlaying = ValueNotifier(false);

  HomePromo get promo => widget.promo;
  bool get _hasText => promo.title != null || promo.subtitle != null || promo.cta != null;

  @override
  void dispose() {
    _muted.dispose();
    _videoPlaying.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final label = [promo.title, promo.subtitle, promo.cta].whereType<String>().join('. ');
    return Semantics(
      button: true,
      label: label.isEmpty ? (promo.sponsored ? 'Advertisement' : 'Promotion') : label,
      onTap: onTap,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Material(
          color: AppColors.cosmic,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (promo.type == PromoMediaType.video)
                _PromoVideo(
                  source: promo.source,
                  poster: promo.poster,
                  active: widget.active,
                  loop: widget.loop,
                  muted: _muted,
                  ready: _videoPlaying,
                  onEnded: widget.onEnded,
                  onFailed: widget.onFailed,
                )
              else
                _media(promo.source),
              if (_hasText)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0, 0.55, 1],
                      colors: [Color(0xE6110C30), Color(0x80110C30), Color(0x00110C30)],
                    ),
                  ),
                ),
              // Ink on top of the media so the whole slide is tappable.
              Positioned.fill(child: InkWell(onTap: onTap)),
              if (_hasText)
                Positioned(
                  left: AppSpacing.md,
                  right: 96,
                  top: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: IgnorePointer(child: _text()),
                ),
              if (promo.sponsored)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: AppBadge(label: 'Ad', color: Colors.white, background: Color(0x66000000)),
                ),
              ValueListenableBuilder<bool>(
                valueListenable: _videoPlaying,
                builder: (context, ready, _) => !ready
                    ? const SizedBox.shrink()
                    : Positioned(
                        right: 4,
                        bottom: 4,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _muted,
                          builder: (context, muted, _) => IconButton(
                            tooltip: muted ? 'Unmute' : 'Mute',
                            style: IconButton.styleFrom(backgroundColor: const Color(0x66000000)),
                            icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: Colors.white, size: 18),
                            onPressed: () => _muted.value = !muted,
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

  Widget _text() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (promo.title != null)
          Text(promo.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.title.copyWith(color: AppColors.textOnDark, fontSize: 17)),
        if (promo.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(promo.subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted, fontSize: 12.5)),
        ],
        if (promo.cta != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(promo.cta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
            ]),
          ),
        ],
      ],
    );
  }
}

/// Image from the bundle or the network, decoded at display size.
Widget _media(String source) {
  return LayoutBuilder(builder: (context, c) {
    final px = (c.maxWidth * MediaQuery.devicePixelRatioOf(context)).round();
    if (source.startsWith('assets/')) {
      return Image.asset(
        source,
        fit: BoxFit.cover,
        cacheWidth: px > 0 ? px : null,
        errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.cosmic),
      );
    }
    return AppImage(source);
  });
}

class _PromoVideo extends StatefulWidget {
  final String source;
  final String? poster;
  final bool active;
  final bool loop;
  final ValueNotifier<bool> muted;
  final ValueNotifier<bool> ready;
  final VoidCallback onEnded;
  final VoidCallback onFailed;

  const _PromoVideo({
    required this.source,
    required this.poster,
    required this.active,
    required this.loop,
    required this.muted,
    required this.ready,
    required this.onEnded,
    required this.onFailed,
  });

  @override
  State<_PromoVideo> createState() => _PromoVideoState();
}

class _PromoVideoState extends State<_PromoVideo> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _ready = false;
  bool _failed = false;
  bool _endedReported = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.muted.addListener(_applyVolume);
    _init();
  }

  Future<void> _init() async {
    final c = widget.source.startsWith('assets/')
        ? VideoPlayerController.asset(widget.source)
        : VideoPlayerController.networkUrl(Uri.parse(widget.source));
    _video = c;
    try {
      await c.initialize();
      await c.setVolume(widget.muted.value ? 0 : 1);
      await c.setLooping(widget.loop);
      c.addListener(_onTick);
      if (!mounted) return;
      setState(() => _ready = true);
      widget.ready.value = true;
      _sync();
    } catch (e) {
      debugPrint('Promo video failed to load (${widget.source}): $e');
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onFailed();
    }
  }

  void _onTick() {
    final v = _video!.value;
    if (v.hasError && !_failed) {
      setState(() => _failed = true);
      widget.ready.value = false;
      widget.onFailed();
      return;
    }
    final ended = !widget.loop && v.duration > Duration.zero && v.position >= v.duration;
    if (ended && !_endedReported) {
      _endedReported = true;
      widget.onEnded();
    }
  }

  void _applyVolume() {
    if (_ready && !_failed) _video?.setVolume(widget.muted.value ? 0 : 1);
  }

  void _sync() {
    final c = _video;
    if (c == null || !_ready || _failed) return;
    if (widget.active && _appActive) {
      if (_endedReported) {
        _endedReported = false;
        c.seekTo(Duration.zero);
      }
      c.play();
    } else {
      c.pause();
    }
  }

  @override
  void didUpdateWidget(_PromoVideo old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.muted.removeListener(_applyVolume);
    _video?.removeListener(_onTick);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poster = widget.poster != null ? _media(widget.poster!) : const ColoredBox(color: AppColors.cosmic);
    if (!_ready || _failed) {
      return Stack(fit: StackFit.expand, children: [
        poster,
        if (!_failed)
          const Center(
            child: SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
          ),
      ]);
    }
    final size = _video!.value.size;
    return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(_video!)),
      );
  }
}
