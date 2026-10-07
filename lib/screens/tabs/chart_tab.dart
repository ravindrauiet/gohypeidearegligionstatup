import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../kundli_view_screen.dart';

/// Chart tab: the active profile's Vedic Kundli (D1, D9, D10, dashas, panchang,
/// planets and the AI life report). All chart maths & rendering live in
/// kundli_view_screen.dart so both entry points stay consistent.
class ChartTab extends StatelessWidget {
  const ChartTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    final birth = Vedic.asMap(kundli?['birthDetails']);
    final relationship = Vedic.text(birth['relationship'], '');
    final name = Vedic.displayName(kundli, service: service);
    final isFamily = service.selectedFamilyMember != null;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showKundliProfilePicker(context),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.black, fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      relationship.isNotEmpty ? '$relationship Kundli' : 'Personal Vedic Kundli',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isFamily ? const Color(0xFF6C63FF) : Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isFamily)
            TextButton(
              onPressed: () => service.selectFamilyMember(null),
              child: const Text('My Kundli', style: TextStyle(color: Color(0xFFE83D66), fontWeight: FontWeight.bold)),
            ),
          IconButton(
            tooltip: 'Open full-screen Kundli',
            icon: const Icon(Icons.open_in_full_rounded, color: Colors.black),
            onPressed: kundli == null
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KundliViewScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: kundli == null
          ? const KundliEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: Color(0xFF7C77E6), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Sidereal zodiac · Lahiri ayanamsa · Whole-sign houses',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KundliExplorer(key: ValueKey(Vedic.identity(kundli)), kundli: kundli),
                ],
              ),
            ),
    );
  }
}
