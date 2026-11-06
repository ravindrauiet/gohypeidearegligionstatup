import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/guide_service.dart';
import '../../widgets/ui/app_ui.dart';
import 'guide_detail_screen.dart';

const _categories = <(String?, String)>[(null, 'All'), ('vrat', 'Vrat'), ('puja', 'Puja'), ('festival', 'Festival')];

/// Gradient per category for cards without a deity image.
LinearGradient guideGradient(String category) => switch (category) {
      'vrat' => const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
      'festival' => const LinearGradient(colors: [Color(0xFFFF8A2B), Color(0xFFE11D48)]),
      _ => const LinearGradient(colors: [Color(0xFFF5B83D), Color(0xFFFF6A13)]),
    };

String guideCategoryLabel(String c) => switch (c) { 'vrat' => 'Vrat', 'festival' => 'Festival', _ => 'Puja' };

/// Puja & vrat guides: search + category chips + cards.
class GuidesScreen extends StatefulWidget {
  final GuideService? service;
  const GuidesScreen({super.key, this.service});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GuidesScreen()));

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  late final GuideService _service =
      widget.service ?? GuideService(Provider.of<BackendService>(context, listen: false));
  final _search = TextEditingController();
  List<PujaGuide>? _guides;
  String? _category;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Bundle first (instant, offline), then server dates.
    final local = await _service.bundled();
    if (!mounted) return;
    setState(() {
      _guides = local;
      _failed = local.isEmpty;
    });
    final all = await _service.all();
    if (!mounted) return;
    setState(() {
      _guides = all;
      _failed = all.isEmpty;
    });
  }

  List<PujaGuide> get _visible {
    final q = _search.text.trim().toLowerCase();
    return (_guides ?? const <PujaGuide>[]).where((g) {
      if (_category != null && g.category != _category) return false;
      if (q.isEmpty) return true;
      return '${g.title} ${g.titleHi} ${g.deity} ${g.whenText}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final guides = _guides;
    final visible = _visible;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Puja & Vrat Guides')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
          children: [
            const Text('Step-by-step, with samagri lists, mantras and katha. Made for doing it yourself, wherever you live.',
                style: AppText.body),
            const SizedBox(height: AppSpacing.sm),
            AppSearchBar(hint: 'Search Ekadashi, Shiva, Diwali...', controller: _search, onChanged: (_) => setState(() {})),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _categories)
                AppFilterChip(label: c.$2, selected: _category == c.$1, onTap: () => setState(() => _category = c.$1)),
            ]),
            const SizedBox(height: AppSpacing.md),
            if (guides == null)
              for (var i = 0; i < 4; i++)
                const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm), child: SkeletonBox(height: 110, radius: AppRadius.lg))
            else if (_failed)
              AppStateView.error(message: 'Guides could not be loaded.', onAction: _load)
            else if (visible.isEmpty)
              const AppStateView(
                  icon: Icons.search_off_rounded, title: 'No guide found', message: 'Try another word or category.', compact: true)
            else
              for (final g in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: GuideCard(guide: g, onTap: () => GuideDetailScreen.open(context, g.id, service: _service)),
                ),
          ],
        ),
      ),
    );
  }
}

/// Image (or gradient) thumbnail for a guide.
class GuideThumb extends StatelessWidget {
  final PujaGuide guide;
  final double width;
  final double height;
  const GuideThumb({super.key, required this.guide, this.width = 84, this.height = 84});

  @override
  Widget build(BuildContext context) {
    final asset = guide.imageAsset;
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(gradient: guideGradient(guide.category)),
      alignment: Alignment.center,
      child: Text(guide.titleHi.isEmpty ? '🪔' : guide.titleHi.characters.first,
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: asset == null
          ? fallback
          : Image.asset(asset, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
    );
  }
}

class GuideCard extends StatelessWidget {
  final PujaGuide guide;
  final VoidCallback onTap;
  const GuideCard({super.key, required this.guide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final next = guide.nextDate ?? guide.localNextDate(DateTime.now());
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GuideThumb(guide: guide),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(guide.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
            Text(guide.titleHi, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
            const SizedBox(height: 4),
            Text(guide.overview, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              AppBadge(label: guideCategoryLabel(guide.category), color: AppColors.info, background: AppColors.infoSoft),
              if (next != null)
                AppBadge(
                    label: 'Next: ${DateFormat('d MMM').format(next)}',
                    icon: Icons.event_rounded,
                    color: AppColors.primaryDark,
                    background: AppColors.primarySoft),
            ]),
          ]),
        ),
      ]),
    );
  }
}
