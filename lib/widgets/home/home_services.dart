import 'package:flutter/material.dart';

import '../ui/app_ui.dart';

// ============================================================================
// The super-app "services" layer of Home: one list of things the app does,
// drawn as a 4 x 2 icon grid, as compact chips in the pinned bar, and matched
// by keyword in the search sheet.
// ============================================================================

/// One thing the app can do (a tile in "Everything in one app").
class HomeService {
  /// Stable id, used for widget keys (`home-service-<id>`) and tests.
  final String id;
  final String label;
  final IconData icon;

  /// Two-stop gradient for the icon chip (top-left to bottom-right).
  final List<Color> colors;

  /// Tiny corner badge, e.g. "NEW" or "+10".
  final String? badge;

  /// One-line description in the search sheet.
  final String description;

  /// Extra words the search sheet matches on (lower case).
  final List<String> keywords;

  final VoidCallback onTap;

  const HomeService({
    required this.id,
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.badge,
    this.description = '',
    this.keywords = const [],
  });

  Color get color => colors.last;

  /// Score for [query] (0 = no match). Label prefix beats a keyword hit.
  int matchScore(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 1;
    final label = this.label.toLowerCase();
    if (label.startsWith(q)) return 4;
    if (label.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 3;
    final words = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    bool hit(String w) =>
        label.contains(w) ||
        keywords.any((k) => k.startsWith(w) || w.startsWith(k)) ||
        description.toLowerCase().contains(w);
    if (words.isEmpty) return label.contains(q) ? 2 : 0;
    final hits = words.where(hit).length;
    return hits == 0 ? 0 : (hits == words.length ? 2 : 1);
  }
}

/// Services matching [query], best first. Empty query returns all of them.
List<HomeService> matchHomeServices(String query, List<HomeService> services) {
  final scored = <(int, int, HomeService)>[];
  for (var i = 0; i < services.length; i++) {
    final s = services[i].matchScore(query);
    if (s > 0) scored.add((s, i, services[i]));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
  return [for (final e in scored) e.$3];
}

/// Rounded gradient chip with a white glyph and a soft gloss (the one icon
/// style for services).
class HomeServiceIcon extends StatelessWidget {
  final IconData icon;
  final List<Color> colors;
  final double size;

  const HomeServiceIcon({super.key, required this.icon, required this.colors, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.32);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        boxShadow: [
          BoxShadow(color: colors.last.withValues(alpha: 0.28), blurRadius: size * 0.22, offset: Offset(0, size * 0.08)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gloss in the top-left corner.
            Positioned(
              left: -size * 0.25,
              top: -size * 0.35,
              child: Container(
                width: size * 0.9,
                height: size * 0.75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
            ),
            Center(child: Icon(icon, color: Colors.white, size: size * 0.5)),
          ],
        ),
      ),
    );
  }
}

/// "Everything in one app": 8 services in two rows of four.
class HomeServicesGrid extends StatelessWidget {
  final List<HomeService> services;
  final String title;
  final int columns;

  const HomeServicesGrid({
    super.key,
    required this.services,
    this.title = 'Everything in one app',
    this.columns = 4,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <List<HomeService>>[
      for (var i = 0; i < services.length; i += columns)
        services.sublist(i, (i + columns).clamp(0, services.length)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(child: c < rows[r].length ? _ServiceTile(service: rows[r][c]) : const SizedBox()),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final HomeService service;
  const _ServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final badge = service.badge;
    return Semantics(
      button: true,
      label: badge == null ? service.label : '${service.label}, $badge',
      excludeSemantics: true,
      onTap: service.onTap,
      child: InkWell(
        key: ValueKey('home-service-${service.id}'),
        onTap: service.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  HomeServiceIcon(icon: service.icon, colors: service.colors),
                  if (badge != null)
                    Positioned(
                      top: -7,
                      right: -12,
                      child: _TinyBadge(label: badge, color: badge.startsWith('+') ? AppColors.success : AppColors.danger),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Tiny labels stay legible but never push the grid apart.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Text(
                  service.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TinyBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.surface, width: 1.5),
      ),
      child: Text(
        label,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
            color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.3, height: 1.2),
      ),
    );
  }
}

/// Compact chip ("[icon] Find buddy") used for the pinned bar's shortcut row.
class HomeServiceChip extends StatelessWidget {
  final HomeService service;
  const HomeServiceChip({super.key, required this.service});

  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return (14 * scale + 22).clamp(38.0, 60.0);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: service.label,
      excludeSemantics: true,
      onTap: service.onTap,
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          key: ValueKey('home-chip-${service.id}'),
          onTap: service.onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HomeServiceIcon(icon: service.icon, colors: service.colors, size: 28),
                const SizedBox(width: 7),
                Text(
                  service.label,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Search sheet
// ----------------------------------------------------------------------------

/// Opens the Home search: services matched by keyword, with "Ask AI" last.
/// Tapping a result closes the sheet first, then runs its action.
Future<void> showHomeSearch(
  BuildContext context, {
  required List<HomeService> services,
  required ValueChanged<String?> onAskAi,
}) {
  return showAppSheet<void>(
    context,
    builder: (sheetContext) => HomeSearchSheet(services: services, onAskAi: onAskAi),
  );
}

class HomeSearchSheet extends StatefulWidget {
  final List<HomeService> services;
  final ValueChanged<String?> onAskAi;

  const HomeSearchSheet({super.key, required this.services, required this.onAskAi});

  @override
  State<HomeSearchSheet> createState() => _HomeSearchSheetState();
}

class _HomeSearchSheetState extends State<HomeSearchSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  void _askAi() {
    final q = _query.trim();
    _run(() => widget.onAskAi(q.isEmpty ? null : q));
  }

  @override
  Widget build(BuildContext context) {
    final results = matchHomeServices(_query, widget.services);
    final q = _query.trim();
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.xs, 0),
            child: Row(children: [
              const Expanded(child: Text('Search CosmicGuide', style: AppText.title)),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.sm),
            child: TextField(
              key: const ValueKey('home-search-field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (_) {
                if (results.isNotEmpty && q.isNotEmpty && results.first.matchScore(q) >= 3) {
                  _run(results.first.onTap);
                } else {
                  _askAi();
                }
              },
              decoration: InputDecoration(
                hintText: 'Buddies, bhajans, games, kundli…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.cancel_rounded, color: AppColors.textTertiary),
                        onPressed: () => setState(() {
                          _controller.clear();
                          _query = '';
                        }),
                      ),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              children: [
                if (q.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
                    child: Text('Popular', style: AppText.caption),
                  ),
                for (final s in results) _resultRow(s),
                if (q.isNotEmpty && results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
                    child: Text('No matching feature. The AI can still help:', style: AppText.caption),
                  ),
                _askAiRow(q),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(HomeService s) {
    return ListTile(
      key: ValueKey('home-search-${s.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      leading: HomeServiceIcon(icon: s.icon, colors: s.colors, size: 40),
      title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
      subtitle: s.description.isEmpty
          ? null
          : Text(s.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
      onTap: () => _run(s.onTap),
    );
  }

  Widget _askAiRow(String q) {
    return ListTile(
      key: const ValueKey('home-search-ask-ai'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      leading: const HomeServiceIcon(
          icon: Icons.auto_awesome_rounded, colors: [Color(0xFF8B7CFF), Color(0xFF4F46E5)], size: 40),
      title: Text(q.isEmpty ? 'Ask the AI astrologer' : 'Ask AI: "$q"',
          maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
      subtitle: const Text('Free answers from your Kundli, 24/7', style: AppText.caption),
      trailing: const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
      onTap: _askAi,
    );
  }
}
