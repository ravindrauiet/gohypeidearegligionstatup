import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../ui/app_ui.dart';

// ============================================================================
// Home building blocks in the Zomato / Swiggy style: a full-bleed hero header,
// a pinned search + shortcut bar, compact recommendation tiles, big feed
// cards and a quiet footer.
// ============================================================================

/// Full-bleed cosmic header drawn behind the status bar: greeting / profile
/// switcher on the left, gold wallet pill and avatar on the right, then the
/// ad / promo slot ([banner]).
class HomeHeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String avatarName;
  final String? walletLabel;
  final VoidCallback onSwitchProfile;
  final VoidCallback onWallet;
  final VoidCallback onProfile;
  final Widget banner;

  /// Space left at the bottom for the pinned bar that overlays the header.
  final double bottomInset;

  const HomeHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.avatarName,
    required this.walletLabel,
    required this.onSwitchProfile,
    required this.onWallet,
    required this.onProfile,
    required this.banner,
    required this.bottomInset,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/topic_moon_calendar.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.cosmicGradient)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.55, 1],
              colors: [Color(0x99110C30), Color(0x33110C30), Color(0xE6110C30)],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: top + AppSpacing.xs, bottom: bottomInset + AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.sm, 0),
                child: Row(
                  children: [
                    Expanded(child: _profileSwitcher()),
                    if (walletLabel != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _GoldWalletPill(label: walletLabel!, onTap: onWallet),
                    ],
                    const SizedBox(width: AppSpacing.xs),
                    _avatarButton(),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              banner,
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileSwitcher() {
    return Semantics(
      button: true,
      label: '$title. $subtitle. Switch profile',
      onTap: onSwitchProfile,
      excludeSemantics: true,
      child: InkWell(
        onTap: onSwitchProfile,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Colors.white),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                ],
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textOnDarkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarButton() {
    final initial = avatarName.trim().isEmpty ? '?' : avatarName.trim()[0].toUpperCase();
    return Semantics(
      button: true,
      label: 'Profile',
      onTap: onProfile,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onProfile,
        radius: 26,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
          ),
          child: Text(initial,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.cosmicLight)),
        ),
      ),
    );
  }
}

/// Gold gradient wallet pill (like Zomato's GOLD badge).
class _GoldWalletPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GoldWalletPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Wallet balance $label',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFE7A3), Color(0xFFF5B83D)]),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: const Color(0xFFFFF3CF), width: 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 16, color: Color(0xFF5A3A00)),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF5A3A00))),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Pinned search + shortcuts
// ----------------------------------------------------------------------------

class HomeShortcut {
  final String label;
  final String image;
  final VoidCallback onTap;
  const HomeShortcut(this.label, this.image, this.onTap);
}

/// White bar that sits at the bottom of the hero and stays pinned under the
/// status bar while scrolling: AI search + round photo shortcuts.
class HomeStickyBar extends StatelessWidget {
  final List<String> hints;
  final VoidCallback onSearch;
  final List<HomeShortcut> shortcuts;

  const HomeStickyBar({super.key, required this.hints, required this.onSearch, required this.shortcuts});

  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return 12 + 50 + 12 + 56 + 6 + 16 * scale + 12;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, AppSpacing.page, 12),
            child: Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: AppSpacing.sm),
                _aiButton(),
              ],
            ),
          ),
          SizedBox(
            height: 56 + 6 + 16 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6) + 12,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: AppSpacing.pagePadding,
              itemCount: shortcuts.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, i) => _ShortcutBubble(shortcut: shortcuts[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Semantics(
      button: true,
      label: 'Ask the AI astrologer',
      onTap: onSearch,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onSearch,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(child: RotatingHint(prefix: 'Ask ', hints: hints)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiButton() {
    return Semantics(
      button: true,
      label: 'Chat with AI astrologer',
      onTap: onSearch,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onSearch,
        radius: 30,
        child: Container(
          width: 50,
          height: 50,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: [AppColors.primary, AppColors.love, AppColors.info, AppColors.primary]),
          ),
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ShortcutBubble extends StatelessWidget {
  final HomeShortcut shortcut;
  const _ShortcutBubble({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final px = (56 * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      button: true,
      label: shortcut.label,
      onTap: shortcut.onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: shortcut.onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.card,
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipOval(
                  child: Image.asset(
                    shortcut.image,
                    fit: BoxFit.cover,
                    cacheWidth: px,
                    errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surfaceMuted),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                shortcut.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search hint that cycles through examples ("Ask 'when will I marry?'").
class RotatingHint extends StatefulWidget {
  final String prefix;
  final List<String> hints;
  const RotatingHint({super.key, required this.prefix, required this.hints});

  @override
  State<RotatingHint> createState() => _RotatingHintState();
}

class _RotatingHintState extends State<RotatingHint> {
  Timer? _timer;
  int _i = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final visible = TickerMode.valuesOf(context).enabled;
    _timer?.cancel();
    if (!reduce && visible && widget.hints.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
        if (mounted) setState(() => _i = (_i + 1) % widget.hints.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 15, color: AppColors.textTertiary);
    return Row(
      children: [
        Text(widget.prefix, style: style),
        Expanded(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.8), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: Text(
                '"${widget.hints[_i]}"',
                key: ValueKey(_i),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Recommendation tile (astrologers)
// ----------------------------------------------------------------------------

/// Compact photo tile: image with a dark tag on top and a pill overlapping
/// its bottom edge, then the name and a status line (Zomato restaurant tile).
class HomeAstroTile extends StatelessWidget {
  static const double width = 112;

  final String name;
  final String? imageUrl;
  final String tag;
  final Widget pill;
  final IconData statusIcon;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;

  const HomeAstroTile({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.tag,
    required this.pill,
    required this.statusIcon,
    required this.status,
    required this.statusColor,
    required this.onTap,
  });

  /// Shown when there is no photo (or it fails to load).
  Widget _initials() => ColoredBox(
        color: AppColors.infoSoft,
        child: Center(child: AppAvatar(name: name, size: 56, color: AppColors.info)),
      );

  @override
  Widget build(BuildContext context) {
    final url = imageUrl ?? '';
    return Semantics(
      button: true,
      label: '$name. $tag. $status',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: SizedBox(
                      width: width,
                      height: 104,
                      child: url.isEmpty
                          ? _initials()
                          : url.startsWith('assets/')
                              ? Image.asset(url,
                                  fit: BoxFit.cover,
                                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
                                  errorBuilder: (_, __, ___) => _initials())
                              : CachedNetworkImage(
                                  imageUrl: url,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const SkeletonBox(),
                                  errorWidget: (_, __, ___) => _initials()),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                      decoration: const BoxDecoration(
                        color: Color(0xB3000000),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                      ),
                      child: Text(tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: -9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: pill,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small purple "AI" pill used on AI astrologer tiles.
class HomeAiPill extends StatelessWidget {
  const HomeAiPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.info, borderRadius: BorderRadius.circular(6)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 11),
        SizedBox(width: 2),
        Text('AI', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ----------------------------------------------------------------------------
// Explore more + feed cards + footer
// ----------------------------------------------------------------------------

/// Square tile with a big soft icon and a two-line label ("Explore more").
class HomeExploreMoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const HomeExploreMoreTile(
      {super.key, required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.md),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.06)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// Big image feed card (article), like Zomato's restaurant feed.
class HomeFeedCard extends StatelessWidget {
  final String image;
  final String tag;
  final String title;
  final String meta;
  final VoidCallback onTap;

  const HomeFeedCard(
      {super.key, required this.image, required this.tag, required this.title, required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $meta',
      onTap: onTap,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        radius: BorderRadius.circular(AppRadius.xl),
        shadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppImage(image),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(6)),
                      child: Text(tag,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.menu_book_rounded, size: 15, color: AppColors.success),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet sign-off at the bottom of Home.
class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your stars,\nsimplified.',
            style: TextStyle(
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: AppColors.textTertiary.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Icon(Icons.favorite_rounded, size: 14, color: AppColors.love.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            const Text('Made with care in India · CosmicGuide', style: AppText.caption),
          ]),
        ],
      ),
    );
  }
}
