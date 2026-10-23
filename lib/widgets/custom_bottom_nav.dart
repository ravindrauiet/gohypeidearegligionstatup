import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class _NavSpec {
  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavSpec(this.index, this.label, this.icon, this.activeIcon);
}

/// Bottom navigation. Tab indices are fixed by [HomeScreen] (0 Home, 1 Chart,
/// 2 More, 3 Chat, 4 Love); this bar only changes the order they are shown in,
/// with Chat ("Ask Astro") raised in the centre as the primary action.
class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _left = [
    _NavSpec(0, 'Home', Icons.home_outlined, Icons.home_rounded),
    _NavSpec(1, 'Kundli', Icons.auto_awesome_mosaic_outlined, Icons.auto_awesome_mosaic_rounded),
  ];
  static const _right = [
    _NavSpec(4, 'Love', Icons.favorite_border_rounded, Icons.favorite_rounded),
    _NavSpec(2, 'More', Icons.grid_view_outlined, Icons.grid_view_rounded),
  ];
  static const _chatIndex = 3;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border, width: 0.8)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF14142B).withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (final s in _left) _item(s),
                _centerItem(),
                for (final s in _right) _item(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(_NavSpec s) {
    final selected = currentIndex == s.index;
    final color = selected ? AppColors.primary : AppColors.textTertiary;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '${s.label} tab',
        excludeSemantics: true,
        onTap: () => onTap(s.index),
        child: InkResponse(
          onTap: () => onTap(s.index),
          radius: 32,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primarySoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(selected ? s.activeIcon : s.icon, size: 22, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                s.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centerItem() {
    final selected = currentIndex == _chatIndex;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Chat tab',
        excludeSemantics: true,
        onTap: () => onTap(_chatIndex),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(_chatIndex),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 34,
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.primaryGradient : AppColors.cosmicGradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.glow(selected ? AppColors.primary : AppColors.cosmic),
                ),
                child: const Icon(Icons.forum_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                'Ask Astro',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
