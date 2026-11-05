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

/// In-app YouTube player. Pays 1 coin (once per video, server-side) after a
/// video has actually played for 10 seconds.
///
/// Two modes:
/// * list mode ([VideoPlayerScreen.new]): our own "Up next" queue of videos;
/// * playlist player mode ([VideoPlayerScreen.playlist]): the YouTube player
///   loads the whole playlist by id (used when the server can't list the
///   videos). The player's own next / previous controls move through it, and
///   the current video id comes from the player's metadata.
class VideoPlayerScreen extends StatefulWidget {
  final List<VideoItem> queue;
  final int index;
  final String? playlistTitle;

  /// Playlist player mode: the YouTube playlist to play by id.
  final String? playlistId;

  /// 9:16 player for Shorts.
  final bool vertical;

  const VideoPlayerScreen({
    super.key,
    required this.queue,
    required this.index,
    this.playlistTitle,
    this.vertical = false,
  }) : playlistId = null;

  /// Plays the whole YouTube playlist [playlistId] in the player.
  const VideoPlayerScreen.playlist({
    super.key,
    required String this.playlistId,
    this.playlistTitle,
    this.vertical = false,
  })  : queue = const [],
        index = 0;

  bool get isPlaylistMode => queue.isEmpty && (playlistId ?? '').isNotEmpty;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _controller;
  late final VideoCoinTracker _tracker;
  StreamSubscription<YoutubePlayerValue>? _valueSub;
  StreamSubscription<YoutubeVideoState>? _positionSub;
  Timer? _ticker;

  // List mode.
  late int _index;

  // Playlist player mode: position in the playlist, as the player reports it.
  int? _plIndex;
  int? _plLength;

  /// Latest playback position (null until the player reports one).
  Duration? _lastPosition;
  bool _failed = false;

  /// The player itself could not be opened (no network).
  bool _openFailed = false;
  bool _fullscreen = false;
  bool _forcedLandscape = false;
  PlayerState _lastState = PlayerState.unknown;
  Timer? _skipTimer;

  bool get _playlistMode => widget.isPlaylistMode;

  VideoItem get _current => widget.queue[_index];

  bool get _hasNext {
    if (_playlistMode) return _plIndex == null || _plLength == null || _plIndex! < _plLength! - 1;
    return _index < widget.queue.length - 1;
  }

  bool get _hasPrevious => _playlistMode ? (_plIndex ?? 0) > 0 : _index > 0;

  @override
  void initState() {
    super.initState();
    _index = widget.index.clamp(0, math.max(0, widget.queue.length - 1));
    _tracker = VideoCoinTracker(
      context.read<VideoService>(),
      onClaimed: _onClaimed,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
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
    if (_playlistMode) {
      unawaited(_open(() => _controller.loadPlaylist(list: [widget.playlistId!], listType: ListType.playlist)));
    } else if (widget.queue.isNotEmpty) {
      _resetForCurrent();
      unawaited(_open(() => _controller.loadVideoById(videoId: _current.videoId)));
    }
  }

  /// Runs a player command; the player never getting ready (no network)
  /// shows the "could not open the player" state instead of failing silently.
  Future<void> _open(Future<void> Function() command) async {
    try {
      await command();
    } catch (e) {
      debugPrint('VideoPlayerScreen: player failed to open: $e');
      if (mounted) setState(() => _openFailed = true);
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

  /// List mode: start counting the queue's current video from zero.
  void _resetForCurrent() {
    _lastPosition = null;
    _failed = false;
    _skipTimer?.cancel();
    _tracker.setVideo(_current.videoId, title: _current.title, restart: true);
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
    unawaited(_open(() => _controller.loadVideoById(videoId: _current.videoId)));
  }

  void _next() {
    if (_playlistMode) {
      _clearErrorForSkip();
      unawaited(_open(_controller.nextVideo));
    } else {
      _goTo(_index + 1);
    }
  }

  void _previous() {
    if (_playlistMode) {
      _clearErrorForSkip();
      unawaited(_open(_controller.previousVideo));
    } else {
      _goTo(_index - 1);
    }
  }

  void _clearErrorForSkip() {
    _skipTimer?.cancel();
    if (_failed) {
      _controller.update(error: YoutubeError.none);
      setState(() => _failed = false);
    }
  }

  void _onValue(YoutubePlayerValue v) {
    if (!mounted) return;
    final fs = v.fullScreenOption.enabled;
    if (fs != _fullscreen) {
      setState(() => _fullscreen = fs);
      _applyFullscreenUi(fs, locked: v.fullScreenOption.locked);
    }

    if (_playlistMode) _onPlaylistMetadata(v.metaData);

    if (v.hasError && !_failed) {
      setState(() => _failed = true);
      if (_hasNext) {
        showAppSnack(context, 'This video can\'t play here. Playing the next one.', error: true);
        final from = _index;
        _skipTimer?.cancel();
        _skipTimer = Timer(const Duration(milliseconds: 1800), () {
          if (!mounted || !_failed) return;
          if (_playlistMode) {
            _next();
          } else if (_index == from) {
            _goTo(from + 1);
          }
        });
      }
      return;
    }
    final justEnded = v.playerState == PlayerState.ended && _lastState != PlayerState.ended;
    _lastState = v.playerState;
    // Playlist mode: the YouTube player moves on by itself.
    if (justEnded && !_playlistMode && _hasNext) _goTo(_index + 1);
  }

  /// Playlist mode: the player reports the video it is playing (id + title)
  /// whenever it changes; coins are counted per that id.
  void _onPlaylistMetadata(YoutubeMetaData meta) {
    if (meta.videoId.isEmpty) return;
    if (meta.videoId == _tracker.videoId) {
      if (meta.title.isNotEmpty && meta.title != _tracker.title) {
        setState(() => _tracker.setVideo(meta.videoId, title: meta.title));
      }
      return;
    }
    _lastPosition = null;
    _skipTimer?.cancel();
    setState(() {
      _failed = false;
      _tracker.setVideo(meta.videoId, title: meta.title);
    });
    unawaited(_refreshPlaylistPosition());
  }

  Future<void> _refreshPlaylistPosition() async {
    try {
      final (ids, index) = await (_controller.playlist, _controller.playlistIndex).wait;
      if (!mounted) return;
      setState(() {
        _plLength = ids.isEmpty ? null : ids.length;
        _plIndex = index < 0 ? null : index;
      });
    } catch (_) {
      // Position in the playlist is a nicety; ignore.
    }
  }

  /// Called every second: feeds real playback time to the coin tracker.
  void _tick() {
    if (!mounted) return;
    final playing = !_failed && _controller.value.playerState == PlayerState.playing;
    if (_tracker.tick(playing: playing, position: _lastPosition)) setState(() {});
  }

  void _onClaimed(String videoId, int amount) {
    if (!mounted) return;
    final service = context.read<VideoService>();
    if (amount > 0) {
      try {
        context
            .read<RewardsService>()
            .applyAward(amount, reason: 'video', ref: videoId, balance: service.lastBalance);
      } on ProviderNotFoundException {
        // Shown without the rewards provider: the toast is enough.
      }
      showCoinToast(context, amount, reason: 'New video watched');
    } else if (service.takeDailyCapNotice()) {
      showAppSnack(context, 'Daily video coin limit reached. Come back tomorrow for more.');
    }
    setState(() {});
  }

  String get _youtubeUrl {
    if (!_playlistMode) return _current.youtubeUrl;
    final list = Uri.encodeQueryComponent(widget.playlistId!);
    final id = _tracker.videoId;
    return id.isEmpty
        ? 'https://www.youtube.com/playlist?list=$list'
        : 'https://www.youtube.com/watch?v=$id&list=$list';
  }

  Future<void> _openOnYouTube() async {
    final ok = await launchUrl(Uri.parse(_youtubeUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppSnack(context, 'Could not open YouTube', error: true);
  }

  void _retryOpen() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => _playlistMode
          ? VideoPlayerScreen.playlist(
              playlistId: widget.playlistId!,
              playlistTitle: widget.playlistTitle,
              vertical: widget.vertical,
            )
          : VideoPlayerScreen(
              queue: widget.queue,
              index: _index,
              playlistTitle: widget.playlistTitle,
              vertical: widget.vertical,
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.queue.isEmpty && !_playlistMode) {
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
                if (_openFailed)
                  SliverToBoxAdapter(
                    child: AppStateView.error(
                      compact: true,
                      title: 'Could not open the player',
                      message: 'Check your internet connection and try again.',
                      onAction: _retryOpen,
                    ),
                  ),
                SliverToBoxAdapter(child: _info(service)),
                if (_playlistMode) SliverToBoxAdapter(child: _playlistTip()) else ..._upNext(service),
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

  String get _title {
    if (!_playlistMode) return _current.displayTitle;
    final t = _tracker.title;
    return t.isNotEmpty ? VideoCategories.cleanTitle(t) : (widget.playlistTitle ?? 'Playlist');
  }

  String get _positionLabel {
    if (!_playlistMode) return '${_index + 1} of ${widget.queue.length}';
    if (_plIndex == null) return _tracker.videoId.isEmpty ? 'Starting the playlist...' : 'Playing the playlist';
    return _plLength == null ? 'Video ${_plIndex! + 1}' : 'Video ${_plIndex! + 1} of $_plLength';
  }

  Widget _info(VideoService service) {
    final id = _tracker.videoId;
    final watched = id.isNotEmpty && service.isWatched(id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title, style: AppText.title),
        const SizedBox(height: 4),
        Text(_positionLabel, style: AppText.caption),
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
              onPressed: _hasPrevious ? _previous : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AppButton(
              label: 'Next',
              icon: Icons.skip_next_rounded,
              variant: AppButtonVariant.secondary,
              height: 46,
              onPressed: _hasNext ? _next : null,
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
    final played = _tracker.playedSeconds;
    if (_tracker.earned) {
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
      text = played == 0
          ? 'Watch 10 seconds of each new video to earn 1 coin'
          : 'Earn 1 coin in ${_tracker.secondsLeft} s...';
    }
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600))),
    ]);
  }

  /// Playlist mode: there is no list to show; explain the controls instead.
  Widget _playlistTip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Playing the whole playlist', style: AppText.bodyStrong),
              const SizedBox(height: 4),
              Text(
                'Videos play one after another. Use Next and Previous, or the player\'s own controls, '
                'to move through the playlist.',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: _openOnYouTube,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Open on YouTube',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
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
