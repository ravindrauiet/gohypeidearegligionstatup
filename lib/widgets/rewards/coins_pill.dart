import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/rewards/coins_screen.dart';
import '../../services/rewards_service.dart';
import '../ui/app_ui.dart';
import 'coin_toast.dart';
import 'reward_parts.dart';

/// Gold "coin + balance" pill for the Home header. Opens [CoinsScreen]; shows a
/// small dot while today's check-in coin is waiting.
class CoinsPill extends StatefulWidget {
  /// Use a translucent style on dark (cosmic) headers.
  final bool onDark;

  /// Passed through to [CoinsScreen] so its "Watch a video" card can open videos.
  final VoidCallback? onOpenVideos;

  /// Overrides the default tap (push [CoinsScreen]).
  final VoidCallback? onTap;

  const CoinsPill({super.key, this.onDark = false, this.onOpenVideos, this.onTap});

  @override
  State<CoinsPill> createState() => _CoinsPillState();
}

class _CoinsPillState extends State<CoinsPill> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = context.read<RewardsService>();
      if (r.loggedIn && !r.loaded && !r.loading) r.refresh();
    });
  }

  void _open() {
    if (widget.onTap != null) return widget.onTap!();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CoinsScreen(onOpenVideos: widget.onOpenVideos)));
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RewardsService>();
    final showBalance = r.loggedIn && r.loaded;
    final text = showBalance ? formatCoins(r.balance) : 'Earn';
    final dot = r.dailyAvailable;

    return Semantics(
      button: true,
      label: showBalance
          ? '${formatCoins(r.balance)} coins${dot ? ', daily reward waiting' : ''}'
          : 'Earn coins',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.fromLTRB(5, 4, 12, 4),
              decoration: BoxDecoration(
                color: widget.onDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFFFF6DE),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: widget.onDark ? AppColors.gold.withValues(alpha: 0.5) : const Color(0xFFF7D98A)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const CoinIcon(size: 24),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: widget.onDark ? const Color(0xFFFFD66B) : const Color(0xFF8A5A00),
                    ),
                  ),
                ),
              ]),
            ),
            if (dot)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.onDark ? AppColors.cosmic : Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
