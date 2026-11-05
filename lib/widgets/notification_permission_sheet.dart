import 'package:flutter/material.dart';

import 'ui/app_ui.dart';

/// Friendly pre-prompt shown before the OS notification permission dialog.
/// Returns true when the user taps "Turn on notifications".
class NotificationPermissionSheet extends StatelessWidget {
  const NotificationPermissionSheet({super.key});

  static Future<bool?> show(BuildContext context) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        builder: (_) => const NotificationPermissionSheet(),
      );

  static const _benefits = <(IconData, String, String)>[
    (Icons.wb_sunny_rounded, 'Daily horoscope', 'Your personal guidance every morning.'),
    (Icons.celebration_rounded, 'Festival alerts', 'A reminder the evening before and on the day.'),
    (Icons.people_alt_rounded, 'Buddy messages', 'Know when a buddy writes or accepts your request.'),
    (Icons.monetization_on_rounded, 'Coins & streaks', "Never miss your daily check-in coins."),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Stay in tune with your stars', textAlign: TextAlign.center, style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Turn on notifications and we will only send what matters to you. You can change this any time in Settings.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final b in _benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(b.$1, size: 20, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.$2, style: AppText.bodyStrong),
                    Text(b.$3, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Turn on notifications',
            icon: Icons.notifications_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Not now',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
