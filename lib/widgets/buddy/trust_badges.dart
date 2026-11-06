import 'package:flutter/material.dart';

import '../ui/app_ui.dart';

/// The blue "Verified" check (selfie verified by the team).
const verifiedBlue = Color(0xFF1D6FE0);

/// Blue check badge. [compact] shows only the icon (for tight rows), with a
/// tooltip / semantics label so it is still announced.
class VerifiedBadge extends StatelessWidget {
  final bool compact;
  final double size;
  final bool onDark;

  const VerifiedBadge({super.key, this.compact = false, this.size = 16, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.verified_rounded, size: size, color: onDark ? const Color(0xFF8CC0FF) : verifiedBlue);
    if (compact) {
      return Tooltip(message: 'Verified', child: Semantics(label: 'Verified', child: icon));
    }
    return Semantics(
      label: 'Verified',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.14) : verifiedBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(width: 4),
          Flexible(
            child: Text('Verified',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: onDark ? Colors.white : verifiedBlue)),
          ),
        ]),
      ),
    );
  }
}

/// Green "Phone verified" chip.
class PhoneVerifiedChip extends StatelessWidget {
  final bool onDark;
  const PhoneVerifiedChip({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : AppColors.success;
    return Semantics(
      label: 'Phone verified',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.14) : AppColors.successSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.phone_iphone_rounded, size: 13, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text('Phone verified',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
      ),
    );
  }
}

/// A name followed by the compact blue check (single line, ellipsis).
class BuddyNameWithBadge extends StatelessWidget {
  final String text;
  final bool verified;
  final TextStyle? style;
  final double badgeSize;

  const BuddyNameWithBadge(
      {super.key, required this.text, required this.verified, this.style, this.badgeSize = 16});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
      if (verified) ...[
        const SizedBox(width: 4),
        VerifiedBadge(compact: true, size: badgeSize),
      ],
    ]);
  }
}
