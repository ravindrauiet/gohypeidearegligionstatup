import 'package:flutter/material.dart';

import '../utils/session_messages.dart';
import 'ui/app_ui.dart';

/// Highlighted "Remedy prescription" card shown in live consultation chats.
class SessionPrescriptionCard extends StatelessWidget {
  final SessionMessage message;
  final String? fromName;

  const SessionPrescriptionCard({super.key, required this.message, this.fromName});

  static const Map<String, IconData> _icons = {
    'Gemstone': Icons.diamond_outlined,
    'Mantra': Icons.self_improvement_rounded,
    'Remedy': Icons.spa_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final parts = message.prescriptionParts;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        container: true,
        label: fromName != null ? 'Remedy from $fromName' : 'Remedy prescription',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            gradient: AppColors.cosmicGradient,
            borderRadius: AppRadius.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Remedy prescription',
                            style: TextStyle(color: AppColors.textOnDark, fontSize: 15, fontWeight: FontWeight.w700)),
                        if (fromName != null)
                          Text(
                            'From $fromName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final entry in parts.entries)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(_icons[entry.key] ?? Icons.spa_outlined, size: 16, color: AppColors.gold),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '${entry.key}  ',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold),
                            ),
                            TextSpan(text: entry.value),
                          ]),
                          style: const TextStyle(color: AppColors.textOnDark, fontSize: 14, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  formatSessionClock(message.time),
                  style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
