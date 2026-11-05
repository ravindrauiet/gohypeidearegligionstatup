import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/video_service.dart';
import '../../widgets/rewards/coin_toast.dart' show CoinIcon;
import '../../widgets/ui/app_ui.dart';
import '../../widgets/videos/video_cards.dart';
import 'playlist_screen.dart';

/// The devotional video library: category chips, Netflix-style rails and
/// title search over the curated Tilak playlists.
class VideosScreen extends StatefulWidget {
  /// Optional category to open on (one of the API category strings).
  final String? initialCategory;

  const VideosScreen({super.key, this.initialCategory});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  final _search = TextEditingController();
  String? _category;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VideoService>().loadPlaylists();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openPlaylist(VideoPlaylist p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaylistScreen(playlistId: p.playlistId, title: p.displayTitle),
    ));
  }

  void _selectCategory(String? c) {
    setState(() => _category = c);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VideoService>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Bhakti videos')),
      body: RefreshIndicator(
        onRefresh: () => service.loadPlaylists(force: true),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: _header(service)),
            ..._body(service),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  Widget _header(VideoService service) {
    final cats = service.categories;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxs, AppSpacing.page, AppSpacing.sm),
          child: Row(children: [
            const CoinIcon(size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                service.canEarn
                    ? 'Watch new videos, earn 1 coin each'
                    : 'Watch new videos, earn 1 coin each (log in to collect)',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ]),
        ),
        Padding(
          padding: AppSpacing.pagePadding,
          child: AppSearchBar(
            hint: 'Search bhajans, katha, darshan...',
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 20 + math.max(18.0, MediaQuery.textScalerOf(context).scale(13) * 1.4),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.pagePadding,
            children: [
              AppFilterChip(
                label: 'All',
                icon: Icons.apps_rounded,
                selected: _category == null,
                onTap: () => _selectCategory(null),
              ),
              for (final c in cats) ...[
                const SizedBox(width: AppSpacing.xs),
                AppFilterChip(
                  label: VideoCategories.label(c),
                  icon: VideoCategories.style(c).icon,
                  selected: _category == c,
                  onTap: () => _selectCategory(_category == c ? null : c),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  List<Widget> _body(VideoService service) {
    if (!service.loaded) {
      if (service.error != null && !service.loading) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: AppStateView.error(
                title: 'Could not load videos',
                message: service.error,
                onAction: () => service.loadPlaylists(force: true),
              ),
            ),
          ),
        ];
      }
      return [
        SliverList.list(children: [
          for (var i = 0; i < 3; i++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.sm),
              child: Align(alignment: Alignment.centerLeft, child: SkeletonBox(width: 140 + i * 20.0, height: 18)),
            ),
            const PlaylistRailSkeleton(),
          ],
        ]),
      ];
    }

    final searching = _query.trim().isNotEmpty;
    if (searching || _category != null) {
      final items = service.search(_query, category: _category);
      if (items.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: AppStateView(
                icon: Icons.search_off_rounded,
                title: 'No playlists found',
                message: searching ? 'Try another word, like "Ramayan" or "Krishna".' : null,
                actionLabel: 'Clear search',
                onAction: () {
                  _search.clear();
                  setState(() {
                    _query = '';
                    _category = null;
                  });
                },
              ),
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: searching
                ? 'Results'
                : VideoCategories.label(_category!),
            subtitle: '${items.length} playlist${items.length == 1 ? '' : 's'}',
          ),
        ),
        _PlaylistGrid(items: items, onTap: _openPlaylist),
      ];
    }

    return [
      for (final c in service.categories)
        SliverToBoxAdapter(
          child: _CategoryRail(
            category: c,
            items: service.playlistsIn(c),
            onTap: _openPlaylist,
            onSeeAll: () => _selectCategory(c),
          ),
        ),
    ];
  }
}

class _CategoryRail extends StatelessWidget {
  final String category;
  final List<VideoPlaylist> items;
  final ValueChanged<VideoPlaylist> onTap;
  final VoidCallback onSeeAll;

  const _CategoryRail({required this.category, required this.items, required this.onTap, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final shorts = VideoCategories.isShorts(category);
    final width = shorts ? 120.0 : 172.0;
    final height = playlistCardHeight(context, width, shorts: shorts, showTag: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        title: VideoCategories.label(category),
        subtitle: '${items.length} playlist${items.length == 1 ? '' : 's'}',
        onAction: onSeeAll,
      ),
      SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.pagePadding,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, i) => PlaylistCard(
            playlist: items[i],
            width: width,
            showTag: false,
            onTap: () => onTap(items[i]),
          ),
        ),
      ),
    ]);
  }
}

class _PlaylistGrid extends StatelessWidget {
  final List<VideoPlaylist> items;
  final ValueChanged<VideoPlaylist> onTap;
  const _PlaylistGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final allShorts = items.every((p) => p.isShorts);
    final screenW = MediaQuery.sizeOf(context).width;
    const gap = AppSpacing.sm;
    final available = screenW - AppSpacing.page * 2;
    final minCard = allShorts ? 104.0 : 150.0;
    final columns = math.max(2, ((available + gap) / (minCard + gap)).floor()).clamp(2, allShorts ? 6 : 5);
    final cardW = (available - gap * (columns - 1)) / columns;
    // Mixed results (search) use 16:9 posters for everything so rows line up.
    final extent = playlistCardHeight(context, cardW, shorts: allShorts);

    return SliverPadding(
      padding: AppSpacing.pagePadding,
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: gap,
          mainAxisExtent: extent,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => Align(
          alignment: Alignment.topCenter,
          child: PlaylistCard(
            playlist: items[i],
            width: cardW,
            portrait: allShorts,
            onTap: () => onTap(items[i]),
          ),
        ),
      ),
    );
  }
}
