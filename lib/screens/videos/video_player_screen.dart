import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../services/rewards_service.dart';
import '../../services/video_service.dart';
import '../../widgets/rewards/coin_toast.dart';
import '../../widgets/ui/app_ui.dart';
import '../../widgets/videos/video_cards.dart';

/// In-app YouTube player with an "Up next" queue. Pays 1 coin (once per
/// video, server-side) after the video has actually played for 10 seconds.
class VideoPlayerScreen extends StatefulWidget {
  final List<VideoItem> queue;
  final int index;
  final String? playlistTitle;

  /// 9:16 player for Shorts.
  final bool vertical;

  const VideoPlayerScreen({
    super.key,
    required this.queue,
    required this.index,
    this.playlistTitle,
    this.vertical = false,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  static const _secondsForCoin = 10;
  static const _maxClaimAttempts = 3;

  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _positionSub;
  Timer? _ticker;

  late int _index;

  /// Real playback time of the current video, in ms (position advancing
  /// while the state is "playing"; seeking ahead does not count).
  int _watchedMs = 0;
  Duration? _lastPosition;
  Duration? _positionAtLastTick;
  bool _rewardHandled = false;
  int _claimAttempts = 0;
  bool _earnedThisVideo = false;
  bool _failed = false;
  bool _fullscreen = false;
  bool _forcedLandscape = false;
  PlayerState _lastState = PlayerState.unknown;
  Timer? _skipTimer;

  int get _playedSeconds => _watchedMs ~/ 1000;

  VideoItem get _current => widget.queue[_index];
  bool get _hasNext => _index < widget.queue.length - 1;
  bool get _hasPrevious => _index > 0;

  @override
  void initState() {
    super.initState();
    _index = widget.index.clamp(0, math.max(0, widget.queue.length - 1));
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        playsInline: true,
        enableCaption: false,
      ),
    );
    _valueSub = _controller.stream.listen(_onValue);
    _positionSub = _controller.videoStateStream.listen((s) => _lastPosition = s.position);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (widget.queue.isNotEmpty) {
      _resetForCurrent();
      _controller.loadVideoById(videoId: _current.videoId);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _skipTimer?.cancel();
    _valueSub?.cancel();
    _positionSub?.cancel();
    _restoreSystemUi();
    _controller.close();
    super.dispose();
  }

  /// Fullscreen from the player button: landscape + immersive for 16:9
  /// videos. Fullscreen from rotating the phone (unlocked) leaves the
  /// orientation alone so rotating back exits it.
  void _applyFullscreenUi(bool fullscreen, {required bool locked}) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (locked && !widget.vertical) {
        _forcedLandscape = true;
        SystemChrome.setPreferredOrientations(
            const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      }
    } else {
      _restoreSystemUi();
    }
  }

  /// Back to the app defaults (all orientations, normal system bars).
  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    if (_forcedLandscape) {
      _forcedLandscape = false;
      SystemChrome.setPreferredOrientations(const []);
    }
  }

  void _resetForCurrent() {
    _watchedMs = 0;
    _claimAttempts = 0;
    _lastPosition = null;
    _positionAtLastTick = null;
    _failed = false;
    _earnedThisVideo = false;
    _skipTimer?.cancel();
    // Already paid for (or a guest): no need to count.
    final service = context.read<VideoService>();
    _rewardHandled = service.isWatched(_current.videoId) || !service.canEarn || service.dailyCapReached;
  }

  void _goTo(int i) {
    if (i < 0 || i >= widget.queue.length || i == _index) return;
    setState(() {
      _index = i;
      _resetForCurrent();
    });
    // The package only clears an error once a video plays; clear it now so
    // the next video starts clean.
    _controller.update(error: YoutubeError.none);
    _controller.loadVideoById(videoId: _current.videoId);
  }

  void _onValue(YoutubePlayerValue v) {
    if (!mounted) return;
    final fs = v.fullScreenOption.enabled;
    if (fs != _fullscreen) {
      setState(() => _fullscreen = fs);
      _applyFullscreenUi(fs, locked: v.fullScreenOption.locked);
    }

    if (v.hasError && !_failed) {
      setState(() => _failed = true);
      if (_hasNext) {
        showAppSnack(context, 'This video can\'t play here. Playing the next one.', error: true);
        final from = _index;
        _skipTimer?.cancel();
        _skipTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted && _index == from && _failed) _goTo(from + 1);
        });
      }
      return;
    }
    final justEnded = v.playerState == PlayerState.ended && _lastState != PlayerState.ended;
    _lastState = v.playerState;
    if (justEnded && _hasNext) _goTo(_index + 1);
  }

  /// Called every second: adds real playback time (state playing and the
  /// position advanced; a jump from seeking counts as at most 1.5 s).
  void _tick() {
    if (!mounted || _rewardHandled || _failed) return;
    if (_controller.value.playerState != PlayerState.playing) {
      _positionAtLastTick = null; // re-baseline after pause / buffering / seek
      return;
    }
    final pos = _lastPosition;
    final prev = _positionAtLastTick;
    _positionAtLastTick = pos;
    final int gained;
    if (pos == null) {
      gained = 1000; // no position updates on this platform: trust the state
    } else if (prev == null) {
      return; // first sample: just set the baseline
    } else {
      gained = (pos - prev).inMilliseconds.clamp(0, 1500);
    }
    if (gained == 0) return;
    _watchedMs += gained;
    if (_playedSeconds >= _secondsForCoin) {
      _rewardHandled = true;
      _reward(_current);
    } else {
      setState(() {});
    }
  }

  Future<void> _reward(VideoItem video) async {
    _claimAttempts++;
    final service = context.read<VideoService>();
    final amount = await service.claimVideoReward(video.videoId, video.title);
    if (!mounted) return;
    final stillCurrent = _current.videoId == video.videoId;
    if (amount == null) {
      // Offline / server hiccup: try again after a little more watching,
      // a few times at most (never spam the endpoint).
      if (stillCurrent && _claimAttempts < _maxClaimAttempts) {
        setState(() {
          _rewardHandled = false;
          _watchedMs = (_secondsForCoin - 5) * 1000;
        });
      }
      return;
    }
    if (amount > 0) {
      try {
        context
            .read<RewardsService>()
            .applyAward(amount, reason: 'video', ref: video.videoId, balance: service.lastBalance);
      } on ProviderNotFoundException {
        // Shown without the rewards provider: the toast is enough.
      }
      showCoinToast(context, amount, reason: 'New video watched');
    } else if (service.takeDailyCapNotice()) {
      showAppSnack(context, 'Daily video coin limit reached. Come back tomorrow for more.');
    }
    if (stillCurrent) setState(() => _earnedThisVideo = amount > 0);
  }

  Future<void> _openOnYouTube() async {
    final ok = await launchUrl(Uri.parse(_current.youtubeUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppSnack(context, 'Could not open YouTube', error: true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: AppStateView(icon: Icons.videocam_off_rounded, title: 'Nothing to play')),
      );
    }
    final service = context.watch<VideoService>();
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _controller.exitFullScreen();
      },
      child: YoutubePlayerControllerProvider(
        controller: _controller,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(widget.playlistTitle ?? 'Now playing',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
            actions: [
              IconButton(
                tooltip: 'Open on YouTube',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: _openOnYouTube,
              ),
            ],
          ),
          body: Column(children: [
            _player(),
            Expanded(
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(child: _info(service)),
                ..._upNext(service),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _player() {
    final player = YoutubePlayer(
      controller: _controller,
      aspectRatio: widget.vertical ? 9 / 16 : 16 / 9,
      backgroundColor: Colors.black,
    );
    if (!widget.vertical) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: player),
        ),
      );
    }
    final size = MediaQuery.sizeOf(context);
    final maxH = size.height * 0.58;
    final w = math.min(size.width, maxH * 9 / 16);
    return ColoredBox(
      color: Colors.black,
      child: Center(child: SizedBox(width: w, child: player)),
    );
  }

  Widget _info(VideoService service) {
    final watched = service.isWatched(_current.videoId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_current.displayTitle, style: AppText.title),
        const SizedBox(height: 4),
        Text('${_index + 1} of ${widget.queue.length}', style: AppText.caption),
        const SizedBox(height: AppSpacing.sm),
        _coinStatus(service, watched),
        if (_failed) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hasNext
                      ? 'This video is unavailable in the app. Skipping to the next one...'
                      : 'This video is unavailable in the app.',
                  style: AppText.caption.copyWith(color: AppColors.textPrimary),
                ),
              ),
              TextButton(onPressed: _openOnYouTube, child: const Text('YouTube')),
            ]),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(
            child: AppButton(
              label: 'Previous',
              icon: Icons.skip_previous_rounded,
              variant: AppButtonVariant.outline,
              height: 46,
              onPressed: _hasPrevious ? () => _goTo(_index - 1) : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              label: 'Next',
              icon: Icons.skip_next_rounded,
              variant: AppButtonVariant.secondary,
              height: 46,
              onPressed: _hasNext ? () => _goTo(_index + 1) : null,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _coinStatus(VideoService service, bool watched) {
    final IconData icon;
    final Color color;
    final String text;
    if (_earnedThisVideo) {
      icon = Icons.monetization_on_rounded;
      color = AppColors.success;
      text = '+1 coin earned for this video';
    } else if (watched) {
      icon = Icons.check_circle_rounded;
      color = AppColors.success;
      text = 'Watched · coin already collected';
    } else if (!service.canEarn) {
      icon = Icons.lock_outline_rounded;
      color = AppColors.textSecondary;
      text = 'Log in to earn 1 coin for each new video';
    } else if (service.dailyCapReached) {
      icon = Icons.bedtime_outlined;
      color = AppColors.textSecondary;
      text = 'Daily video coin limit reached · come back tomorrow';
    } else {
      icon = Icons.monetization_on_rounded;
      color = const Color(0xFFC97A0A);
      final left = math.max(0, _secondsForCoin - _playedSeconds);
      text = _playedSeconds == 0 ? 'Watch 10 seconds to earn 1 coin' : 'Earn 1 coin in $left s...';
    }
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600))),
    ]);
  }

  List<Widget> _upNext(VideoService service) {
    final next = [for (var i = _index + 1; i < widget.queue.length; i++) i];
    if (next.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, 0),
            child: Column(children: [
              const Text('You\'ve reached the end of this list', style: AppText.caption),
              if (widget.queue.length > 1)
                TextButton.icon(
                  onPressed: () => _goTo(0),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Play from the start'),
                ),
            ]),
          ),
        ),
      ];
    }
    return [
      const SliverToBoxAdapter(
        child: SectionHeader(
          title: 'Up next',
          padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xs),
        ),
      ),
      SliverList.builder(
        itemCount: next.length,
        itemBuilder: (_, j) {
          final i = next[j];
          final v = widget.queue[i];
          final watched = service.isWatched(v.videoId);
          return InkWell(
            onTap: () => _goTo(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: VideoThumbImage(url: v.thumbnail, category: '', iconSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(v.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: AppSpacing.xs),
                watched ? const WatchedChip(compact: true) : const CoinChip(),
              ]),
            ),
          );
        },
      ),
    ];
  }
}
