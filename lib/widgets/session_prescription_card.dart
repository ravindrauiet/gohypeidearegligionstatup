import 'package:flutter/material.dart';

import '../utils/session_messages.dart';

/// Highlighted "Vedic Remedy Prescription" card shown in live consultation chats.
class SessionPrescriptionCard extends StatelessWidget {
  final SessionMessage message;
  final String? fromName;

  const SessionPrescriptionCard({super.key, required this.message, this.fromName});

  static const Map<String, IconData> _icons = {
    'Gemstone': Icons.diamond_rounded,
    'Mantra': Icons.self_improvement_rounded,
    'Remedy': Icons.spa_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final parts = message.prescriptionParts;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fromName != null ? 'REMEDY FROM ${fromName!.toUpperCase()}' : 'VEDIC REMEDY PRESCRIPTION',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final entry in parts.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icons[entry.key] ?? Icons.spa_rounded, size: 14, color: const Color(0xFFFFD700)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(formatSessionClock(message.time), style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
