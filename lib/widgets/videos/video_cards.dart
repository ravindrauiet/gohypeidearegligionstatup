import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/video_service.dart';
import '../rewards/coin_toast.dart' show CoinIcon;
import '../ui/app_ui.dart';

// ============================================================================
// Building blocks shared by the video library, playlist page and Home rail.
// ============================================================================

/// Height of the text under a playlist card (2-line title + category tag),
/// scaled with the user's text size so cards never overflow.
double playlistCardTextHeight(BuildContext context, {bool showTag = true}) {
  final s = MediaQuery.textScalerOf(context);
  final title = s.scale(13) * 1.3 * 2;
  final tag = showTag ? s.scale(11) * 1.2 + 6 + 6 : 0.0;
  return 8 + title + tag + 4;
}

/// Total height of a playlist card of [width].
double playlistCardHeight(BuildContext context, double width, {bool shorts = false, bool showTag = true}) =>
    width * (shorts ? 16 / 9 : 9 / 16) + playlistCardTextHeight(context, showTag: showTag);

/// Gradient + category icon shown when there is no thumbnail (yet).
class VideoFallbackArt extends StatelessWidget {
  final String category;
  final double iconSize;
  const VideoFallbackArt({super.key, required this.category, this.iconSize = 34});

  @override
  Widget build(BuildContext context) {
    final style = VideoCategories.style(category);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: style.gradient),
      child: Stack(fit: StackFit.expand, children: [
        Positioned(
          right: -iconSize * 0.4,
          bottom: -iconSize * 0.4,
          child: Icon(style.icon, size: iconSize * 2.6, color: Colors.white.withValues(alpha: 0.10)),
        ),
        Center(child: Icon(style.icon, size: iconSize, color: Colors.white.withValues(alpha: 0.92))),
      ]),
    );
  }
}

/// Network thumbnail with the category gradient as placeholder / error state.
class VideoThumbImage extends StatelessWidget {
  final String? url;
  final String category;
  final double iconSize;
  const VideoThumbImage({super.key, required this.url, required this.category, this.iconSize = 30});

  @override
  Widget build(BuildContext context) {
    final fallback = VideoFallbackArt(category: category, iconSize: iconSize);
    final u = url ?? '';
    if (u.isEmpty) return fallback;
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    }
    return CachedNetworkImage(
      imageUrl: u,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// Playlist artwork that lazily loads the first video's thumbnail.
class PlaylistArtwork extends StatefulWidget {
  final VideoPlaylist playlist;
  final double iconSize;
  const PlaylistArtwork({super.key, required this.playlist, this.iconSize = 30});

  @override
  State<PlaylistArtwork> createState() => _PlaylistArtworkState();
}

class _PlaylistArtworkState extends State<PlaylistArtwork> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PlaylistArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.playlistId != widget.playlist.playlistId) _resolve();
  }

  void _resolve() {
    final service = context.read<VideoService>();
    final id = widget.playlist.playlistId;
    _url = widget.playlist.thumbnail ?? service.thumbnailFor(id);
    if (_url == null) {
      service.loadThumbnail(id).then((u) {
        if (mounted && widget.playlist.playlistId == id) setState(() => _url = u);
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      VideoThumbImage(url: _url, category: widget.playlist.category, iconSize: widget.iconSize);
}

/// Netflix-style playlist card: artwork, 2-line title and category tag.
/// Uses a 9:16 poster for Shorts.
class PlaylistCard extends StatelessWidget {
  final VideoPlaylist playlist;
  final double width;
  final bool showTag;
  final VoidCallback onTap;

  /// Force a 9:16 (true) or 16:9 (false) poster; defaults to 9:16 for Shorts.
  final bool? portrait;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.width,
    required this.onTap,
    this.showTag = true,
    this.portrait,
  });

  @override
  Widget build(BuildContext context) {
    final shorts = portrait ?? playlist.isShorts;
    final style = VideoCategories.style(playlist.category);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '${playlist.displayTitle}, ${style.label} playlist',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: shorts ? 9 / 16 : 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  PlaylistArtwork(playlist: playlist),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.55, 1],
                        colors: [Colors.transparent, Color(0x99000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(shorts ? Icons.bolt_rounded : Icons.playlist_play_rounded,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            if (showTag) ...[
              const SizedBox(height: 6),
              AppBadge(label: style.label, icon: style.icon, color: style.colors.last),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Horizontal rail of skeleton cards while playlists load.
class PlaylistRailSkeleton extends StatelessWidget {
  final double cardWidth;
  final int count;
  const PlaylistRailSkeleton({super.key, this.cardWidth = 168, this.count = 4});

  @override
  Widget build(BuildContext context) {
    final h = playlistCardHeight(context, cardWidth);
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: AppSpacing.pagePadding,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, __) => SizedBox(
          width: cardWidth,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: cardWidth, height: cardWidth * 9 / 16),
            const SizedBox(height: 10),
            SkeletonBox(width: cardWidth * 0.9, height: 12, radius: 4),
            const SizedBox(height: 6),
            SkeletonBox(width: cardWidth * 0.55, height: 12, radius: 4),
          ]),
        ),
      ),
    );
  }
}

/// Small gold "+1" coin chip for videos that still pay a coin.
class CoinChip extends StatelessWidget {
  final int amount;
  const CoinChip({super.key, this.amount = 1});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const CoinIcon(size: 13),
        const SizedBox(width: 3),
        Text('+$amount',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF9A5B00), height: 1.2)),
      ]),
    );
  }
}

/// Green "Watched" check for videos that have already paid their coin.
class WatchedChip extends StatelessWidget {
  final bool compact;
  const WatchedChip({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success, semanticLabel: 'Watched');
    }
    return const AppBadge(label: 'Watched', icon: Icons.check_rounded, color: AppColors.success);
  }
}
