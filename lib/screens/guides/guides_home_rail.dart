import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/guide_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'guide_detail_screen.dart';
import 'guides_screen.dart';

/// Home rail: "Puja & vrat guides", upcoming ones first. [onSeeAll] defaults
/// to pushing [GuidesScreen].
class GuidesHomeRail extends StatefulWidget {
  final VoidCallback? onSeeAll;
  final GuideService? service;
  const GuidesHomeRail({super.key, this.onSeeAll, this.service});

  @override
  State<GuidesHomeRail> createState() => _GuidesHomeRailState();
}

class _GuidesHomeRailState extends State<GuidesHomeRail> {
  late final GuideService _service =
      widget.service ?? GuideService(Provider.of<BackendService>(context, listen: false));
  List<PujaGuide>? _guides;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final local = await _service.bundled();
    if (mounted) setState(() => _guides = _sorted(local));
    final all = await _service.all();
    if (mounted) setState(() => _guides = _sorted(all));
  }

  static List<PujaGuide> _sorted(List<PujaGuide> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime key(PujaGuide g) => g.nextDate ?? g.localNextDate(today) ?? DateTime(9999);
    return [...list]..sort((a, b) => key(a).compareTo(key(b)));
  }

  @override
  Widget build(BuildContext context) {
    final guides = _guides;
    if (guides != null && guides.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      SectionHeader(
        title: 'Puja & vrat guides',
        subtitle: 'Step-by-step, with samagri and mantras',
        onAction: widget.onSeeAll ?? () => GuidesScreen.open(context),
      ),
      SizedBox(
        height: 196,
        child: guides == null
            ? ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: AppSpacing.pagePadding,
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, __) => const SkeletonBox(width: 150, height: 196, radius: AppRadius.lg),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: AppSpacing.pagePadding,
                itemCount: guides.length.clamp(0, 8),
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) => _RailCard(
                  guide: guides[i],
                  onTap: () => GuideDetailScreen.open(context, guides[i].id, service: _service),
                ),
              ),
      ),
    ]);
  }
}

class _RailCard extends StatelessWidget {
  final PujaGuide guide;
  final VoidCallback onTap;
  const _RailCard({required this.guide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final next = guide.nextDate ?? guide.localNextDate(DateTime.now());
    return SizedBox(
      width: 150,
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GuideThumb(guide: guide, width: 150, height: 96),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(guide.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong.copyWith(height: 1.25)),
              const SizedBox(height: 2),
              Text(next == null ? guide.titleHi : 'Next: ${DateFormat('d MMM').format(next)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
            ]),
          ),
        ]),
      ),
    );
  }
}
