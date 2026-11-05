import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/videos/playlist_screen.dart';
import '../../screens/videos/videos_screen.dart';
import '../../services/video_service.dart';
import '../ui/app_ui.dart';
import 'video_cards.dart';

/// Compact Home rail: "Bhakti videos · earn coins" with ~8 featured playlists
/// (Ramayan, Shree Krishna, Gayatri Mantra, Darshan...). "See all" opens the
/// full library ([VideosScreen]) unless [onSeeAll] is given.
class VideoHomeRail extends StatefulWidget {
  final VoidCallback? onSeeAll;

  const VideoHomeRail({super.key, this.onSeeAll});

  @override
  State<VideoHomeRail> createState() => _VideoHomeRailState();
}

class _VideoHomeRailState extends State<VideoHomeRail> {
  static const _cardWidth = 160.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VideoService>().loadPlaylists();
    });
  }

  void _seeAll() {
    if (widget.onSeeAll != null) {
      widget.onSeeAll!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VideosScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VideoService>();
    final items = service.featured();

    final Widget body;
    if (!service.loaded && service.error != null && !service.loading) {
      body = Padding(
        padding: AppSpacing.pagePadding,
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textTertiary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(child: Text('Could not load videos', style: AppText.body)),
            TextButton(onPressed: () => service.loadPlaylists(force: true), child: const Text('Retry')),
          ]),
        ),
      );
    } else if (!service.loaded) {
      body = const PlaylistRailSkeleton(cardWidth: _cardWidth);
    } else if (items.isEmpty) {
      return const SizedBox.shrink();
    } else {
      body = SizedBox(
        height: playlistCardHeight(context, _cardWidth),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.pagePadding,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, i) {
            final p = items[i];
            return PlaylistCard(
              playlist: p,
              width: _cardWidth,
              portrait: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaylistScreen(playlistId: p.playlistId, title: p.displayTitle),
              )),
            );
          },
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SectionHeader(
        title: 'Bhakti videos · earn coins',
        subtitle: 'Watch new videos, earn 1 coin each',
        onAction: _seeAll,
      ),
      body,
    ]);
  }
}
