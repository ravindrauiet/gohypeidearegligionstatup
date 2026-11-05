import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_service.dart' show BackendException;
import '../../services/video_service.dart';
import '../../widgets/ui/app_ui.dart';
import '../../widgets/videos/video_cards.dart';
import 'video_player_screen.dart';

/// One playlist: hero artwork, "Play all" and the list of videos with their
/// coin status (green check = already paid, "+1" = still pays a coin).
class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  final String title;

  const PlaylistScreen({super.key, required this.playlistId, required this.title});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  PlaylistDetail? _detail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final service = context.read<VideoService>();
    _detail = service.cachedDetail(widget.playlistId);
    _loading = _detail == null;
    if (_detail == null) _load(initial: true);
    // Make sure the catalogue (for the category) is there too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) service.loadPlaylists();
    });
  }

  Future<void> _load({bool force = false, bool initial = false}) async {
    if (!initial) {
      setState(() {
        _loading = _detail == null;
        _error = null;
      });
    }
    try {
      final d = await context.read<VideoService>().playlistDetail(widget.playlistId, force: force);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      // Pull-to-refresh failed but the list is still on screen: say so.
      if (_detail != null) {
        showAppSnack(context, e is BackendException ? e.message : 'Could not refresh this playlist.', error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _youtubeUrl => 'https://www.youtube.com/playlist?list=${widget.playlistId}';

  Future<void> _openOnYouTube() async {
    final ok = await launchUrl(Uri.parse(_youtubeUrl), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppSnack(context, 'Could not open YouTube', error: true);
  }

  void _play(int index) {
    final d = _detail;
    if (d == null) return;
    final playlist = context.read<VideoService>().playlistById(widget.playlistId);
    if (d.usePlayerMode) {
      _playWholePlaylist();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(
        queue: d.videos,
        index: index,
        playlistTitle: widget.title,
        vertical: playlist?.isShorts ?? false,
      ),
    ));
  }

  /// Player mode: the YouTube player loads the whole playlist by id.
  void _playWholePlaylist() {
    final playlist = context.read<VideoService>().playlistById(widget.playlistId);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen.playlist(
        playlistId: widget.playlistId,
        playlistTitle: widget.title,
        vertical: playlist?.isShorts ?? false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VideoService>();
    final playlist = service.playlistById(widget.playlistId);
    final category = playlist?.category ?? '';
    final d = _detail;

    final List<Widget> slivers;
    if (d == null && _loading) {
      slivers = [SliverToBoxAdapter(child: _skeleton())];
    } else if (d == null) {
      // Only when the server can't be reached at all: the player couldn't
      // open either (with a server answer we fall back to player mode).
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: AppStateView.error(
              title: 'You seem to be offline',
              message: _error is BackendException
                  ? _error.toString()
                  : 'Connect to the internet to watch this playlist.',
              onAction: () => _load(force: true),
            ),
          ),
        ),
      ];
    } else if (d.usePlayerMode) {
      slivers = [SliverToBoxAdapter(child: _playerHero(playlist, category, service))];
    } else {
      final newCount = d.videos.where((v) => !service.isWatched(v.videoId)).length;
      slivers = [
        SliverToBoxAdapter(child: _hero(d, category, newCount, service.canEarn)),
        if (!d.complete) SliverToBoxAdapter(child: _partialNote(d)),
        SliverList.separated(
            itemCount: d.videos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (_, i) => _VideoRow(
              video: d.videos[i],
              index: i,
              category: category,
              watched: service.isWatched(d.videos[i].videoId),
              onTap: () => _play(i),
            ),
          ),
      ];
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Open on YouTube',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: _openOnYouTube,
              ),
            ],
          ),
          ...slivers,
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ]),
      ),
    );
  }

  Widget _hero(PlaylistDetail d, String category, int newCount, bool canEarn) {
    final style = VideoCategories.style(category);
    final count = d.videos.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ClipRRect(
              borderRadius: AppRadius.card,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Material(
                  color: Colors.black,
                  child: InkWell(
                    onTap: count == 0 ? null : () => _play(0),
                    child: Stack(fit: StackFit.expand, children: [
                      VideoThumbImage(url: d.firstThumbnail, category: category, iconSize: 44),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x22000000), Color(0x88000000)],
                          ),
                        ),
                      ),
                      if (count > 0)
                        Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded, size: 38, color: AppColors.primary),
                          ),
                        ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.playlist_play_rounded, size: 16, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('$count video${count == 1 ? '' : 's'}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(widget.title, style: AppText.headline),
        const SizedBox(height: AppSpacing.xs),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (category.isNotEmpty) AppBadge(label: style.label, icon: style.icon, color: style.colors.last),
          if (count > 0)
            Text(
              newCount == 0
                  ? 'All watched'
                  : !canEarn
                      ? '$newCount new · log in to earn coins'
                      : context.read<VideoService>().dailyCapReached
                          ? '$newCount new · today\'s video coins collected'
                          : '$newCount new · earn $newCount coin${newCount == 1 ? '' : 's'}',
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
        ]),
        if (count > 0) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Play all', icon: Icons.play_arrow_rounded, onPressed: () => _play(0)),
        ],
      ]),
    );
  }

  /// Player mode (the server can't list the videos): big artwork and a
  /// "Play all videos" button that plays the playlist by id in the player.
  Widget _playerHero(VideoPlaylist? playlist, String category, VideoService service) {
    final style = VideoCategories.style(category);
    final shorts = playlist?.isShorts ?? false;
    final String coinLine = !service.canEarn
        ? 'Log in to earn 1 coin for each new video you watch'
        : service.dailyCapReached
            ? 'Today\'s video coins are collected · come back tomorrow for more'
            : 'Earn 1 coin for each new video you watch for 10 seconds';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ClipRRect(
              borderRadius: AppRadius.card,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Material(
                  color: Colors.black,
                  child: InkWell(
                    onTap: _playWholePlaylist,
                    child: Stack(fit: StackFit.expand, children: [
                      VideoThumbImage(url: playlist?.thumbnail, category: category, iconSize: 48),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x11000000), Color(0x99000000)],
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6))],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, size: 50, color: AppColors.primary),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(shorts ? Icons.bolt_rounded : Icons.playlist_play_rounded,
                                size: 16, color: Colors.white),
                            const SizedBox(width: 4),
                            const Text('Full playlist',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(widget.title, style: AppText.headline),
        if (category.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          AppBadge(label: style.label, icon: style.icon, color: style.colors.last),
        ],
        const SizedBox(height: AppSpacing.sm),
        const Text('Sit back and enjoy the whole playlist, one video after another.', style: AppText.body),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Play all videos',
          icon: Icons.play_circle_fill_rounded,
          height: 56,
          onPressed: _playWholePlaylist,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Icon(
            service.canEarn ? Icons.monetization_on_rounded : Icons.lock_outline_rounded,
            size: 18,
            color: service.canEarn ? const Color(0xFFC97A0A) : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(coinLine,
                style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: TextButton.icon(
            onPressed: _openOnYouTube,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open on YouTube'),
          ),
        ),
      ]),
    );
  }

  /// The server only knows part of the playlist: the RSS feed's latest ~15
  /// videos, or the first 300 from the YouTube API.
  Widget _partialNote(PlaylistDetail d) {
    final n = d.videos.length;
    final what = d.source == 'rss' ? 'Showing the latest $n videos.' : 'Showing $n videos; some couldn\'t be loaded.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              Text(what, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              InkWell(
                onTap: _openOnYouTube,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text('Open full playlist on YouTube',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _skeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(radius: AppRadius.lg)),
        const SizedBox(height: AppSpacing.md),
        const SkeletonBox(width: 220, height: 22),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(height: 50),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < 4; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(children: [
              SkeletonBox(width: 128, height: 72),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(height: 12, radius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(width: 100, height: 12, radius: 4),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _VideoRow extends StatelessWidget {
  final VideoItem video;
  final int index;
  final String category;
  final bool watched;
  final VoidCallback onTap;

  const _VideoRow({
    required this.video,
    required this.index,
    required this.category,
    required this.watched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = video.publishedAt == null ? null : DateFormat('d MMM yyyy').format(video.publishedAt!.toLocal());
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 128,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  VideoThumbImage(url: video.thumbnail, category: category, iconSize: 22),
                  if (watched) Container(color: Colors.black.withValues(alpha: 0.25)),
                  Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                video.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                date ?? 'Video ${index + 1}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ]),
          ),
          const SizedBox(width: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: watched ? const WatchedChip(compact: true) : const CoinChip(),
          ),
        ]),
      ),
    );
  }
}
