import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../widgets/ui/app_ui.dart';
import '../kundli_view_screen.dart';

/// Kundli tab: the active profile's Vedic Kundli (cosmic hero with Lagna /
/// Moon / Nakshatra, then sticky sections for D1, D9, D10, dashas, panchang,
/// planets and the AI life report). All chart maths & rendering live in
/// kundli_view_screen.dart so both entry points stay consistent.
class ChartTab extends StatelessWidget {
  const ChartTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);

    if (kundli == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: AppSpacing.page,
          title: const Text('Kundli'),
          actions: [
            IconButton(
              tooltip: 'Switch profile',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => showKundliProfilePicker(context),
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
        ),
        body: const KundliEmptyState(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: KundliExplorer(
        key: ValueKey(Vedic.identity(kundli)),
        kundli: kundli,
        onOpenFullScreen: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KundliViewScreen())),
      ),
    );
  }
}
