import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

export '../../theme/app_theme.dart';

// ============================================================================
// Shared building blocks. Every screen composes these so spacing, corners,
// states (loading / empty / error) and buttons behave the same everywhere.
// ============================================================================

enum AppButtonVariant { primary, secondary, outline, ghost, dark }

/// Full-width (by default) button with a loading state.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expand;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final (Color bg, Color fg, BorderSide? side) = switch (variant) {
      AppButtonVariant.primary => (AppColors.primary, Colors.white, null),
      AppButtonVariant.secondary => (AppColors.primarySoft, AppColors.primaryDark, null),
      AppButtonVariant.outline => (AppColors.surface, AppColors.textPrimary, const BorderSide(color: AppColors.border, width: 1.2)),
      AppButtonVariant.ghost => (Colors.transparent, AppColors.primary, null),
      AppButtonVariant.dark => (AppColors.textPrimary, Colors.white, null),
    };

    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.button.copyWith(color: fg)),
              ),
            ],
          );

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled || loading ? 1 : 0.5,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button, side: side ?? BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// White rounded card with a hairline border; tappable when [onTap] is set.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final DecorationImage? image;
  final bool shadow;
  final BorderRadius? radius;
  final bool border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.color,
    this.gradient,
    this.image,
    this.shadow = false,
    this.radius,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? AppRadius.card;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.surface) : null,
        gradient: gradient,
        image: image,
        borderRadius: r,
        border: border && gradient == null ? Border.all(color: AppColors.border) : null,
        boxShadow: shadow ? AppShadows.card : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// "Title ....... See all >" row used above every horizontal rail / section.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.title),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(actionLabel ?? 'See all',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small rounded label, e.g. "LIVE", "4.9 ★", "Free".
class AppBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;

  const AppBadge({super.key, required this.label, this.color = AppColors.primary, this.background, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 3)],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, height: 1.2)),
        ),
      ]),
    );
  }
}

/// Green "4.8 ★" rating pill (Swiggy / Zomato style).
class RatingBadge extends StatelessWidget {
  final String rating;
  const RatingBadge(this.rating, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(rating, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 2),
        const Icon(Icons.star_rounded, color: Colors.white, size: 12),
      ]),
    );
  }
}

/// Selectable filter pill used in horizontal filter rows.
class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const AppFilterChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.4 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primaryDark : AppColors.textPrimary)),
            ),
          ]),
        ),
      ),
    );
  }
}

const _kStockPanditPhoto = 'photo-1507003211169-0a1dd7228f2d';

/// Round avatar: network photo with initials fallback.
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final bool online;
  final Color? color;

  const AppAvatar({super.key, this.imageUrl, required this.name, this.size = 48, this.online = false, this.color});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.cosmicLight;
    final fallback = Container(
      color: bg.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: Text(_initials, style: TextStyle(color: bg, fontWeight: FontWeight.w800, fontSize: size * 0.34)),
    );
    var url = imageUrl?.trim() ?? '';
    // The backend's old default pandit photo is a stock picture of a stranger;
    // show the person's initials until they upload their own photo.
    if (url.contains(_kStockPanditPhoto)) url = '';
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        ClipOval(
          child: SizedBox.expand(
            child: url.isEmpty
                ? fallback
                : (url.startsWith('assets/')
                    ? Image.asset(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => fallback,
                        errorWidget: (_, __, ___) => fallback,
                      )),
          ),
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Network or asset image with a neutral placeholder and graceful failure.
class AppImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? radius;

  const AppImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.radius});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppColors.textTertiary),
    );
    final Widget img = url.startsWith('assets/')
        ? Image.asset(url, width: width, height: height, fit: fit, errorBuilder: (_, __, ___) => placeholder)
        : CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: fit,
            placeholder: (_, __) => const SkeletonBox(),
            errorWidget: (_, __, ___) => placeholder,
          );
    return radius == null ? img : ClipRRect(borderRadius: radius!, child: img);
  }
}

/// Shimmering grey block for loading skeletons (no extra package needed).
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height, this.radius = AppRadius.md});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 0.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: const [Color(0xFFEDEDF2), Color(0xFFF7F7FA), Color(0xFFEDEDF2)],
            ),
          ),
        );
      },
    );
  }
}

/// Friendly empty / error / info state with an optional action.
class AppStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;
  final bool compact;

  const AppStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.primary,
    this.compact = false,
  });

  const AppStateView.error({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.actionLabel = 'Try again',
    this.onAction,
    this.compact = false,
  })  : icon = Icons.wifi_off_rounded,
        color = AppColors.danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: compact ? AppSpacing.md : AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 52 : 72,
            height: compact ? 52 : 72,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: compact ? 26 : 34),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, textAlign: TextAlign.center, style: AppText.subtitle),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: AppText.body),
          ],
          if (onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
                label: actionLabel ?? 'Continue', onPressed: onAction, expand: false, height: 44,
                variant: AppButtonVariant.secondary),
          ],
        ],
      ),
    );
  }
}

/// Square-ish icon tile used in quick-action grids (Swiggy category style).
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              if (badge != null)
                Positioned(
                  top: -6,
                  right: -10,
                  child: AppBadge(label: badge!, color: Colors.white, background: AppColors.danger),
                ),
            ]),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

/// Settings-style row: leading icon tile, title, subtitle, chevron.
class AppListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color color;
  final Widget? trailing;

  const AppListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.color = AppColors.textSecondary,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ]),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ]),
      ),
    );
  }
}

/// Tappable search field look-alike (opens a real search on tap) or a real
/// field when [controller] is provided.
class AppSearchBar extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const AppSearchBar({super.key, required this.hint, this.onTap, this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border),
      boxShadow: AppShadows.card,
    );
    if (controller != null) {
      return Container(
        decoration: decoration,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: hint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: decoration,
          child: Row(children: [
            const Icon(Icons.search_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
                child: Text(hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 14))),
          ]),
        ),
      ),
    );
  }
}

/// Opens a consistent modal bottom sheet.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollable,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// Consistent toast-like snackbar.
void showAppSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: error ? const Color(0xFFFF8FA3) : const Color(0xFF7CE0A3), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
}
