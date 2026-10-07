import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import 'kundli_view_screen.dart';

class _GemInfo {
  final String gem;
  final String planet;
  final String weight;
  final String metal;
  final String finger;
  final String day;
  final String benefits;

  const _GemInfo(this.gem, this.planet, this.weight, this.metal, this.finger, this.day, this.benefits);
}

const Map<String, _GemInfo> _gems = {
  'Sun': _GemInfo('Ruby (Manikya)', 'Sun (Surya)', '3 – 6 Ratti', 'Gold or copper', 'Ring finger, right hand', 'Sunday morning at sunrise',
      'Boosts confidence, leadership, vitality and favour from authority figures.'),
  'Moon': _GemInfo('Pearl (Moti)', 'Moon (Chandra)', '4 – 7 Ratti', 'Silver', 'Little finger, right hand', 'Monday morning (Shukla Paksha)',
      'Calms the mind, steadies emotions and supports sleep and nurturing relationships.'),
  'Mars': _GemInfo('Red Coral (Moonga)', 'Mars (Mangal)', '6 – 9 Ratti', 'Gold or copper', 'Ring finger, right hand', 'Tuesday morning',
      'Adds courage, drive and stamina; supports property matters and sibling bonds.'),
  'Mercury': _GemInfo('Emerald (Panna)', 'Mercury (Budh)', '3 – 6 Ratti', 'Gold', 'Little finger, right hand', 'Wednesday morning',
      'Sharpens intellect, speech and analytical ability; good for commerce and studies.'),
  'Jupiter': _GemInfo('Yellow Sapphire (Pukhraj)', 'Jupiter (Guru)', '3 – 6 Ratti', 'Gold', 'Index finger, right hand', 'Thursday morning (Shukla Paksha)',
      'Brings wisdom, fortune, children\'s happiness, wealth and spiritual protection.'),
  'Venus': _GemInfo('Diamond (Heera) / White Sapphire', 'Venus (Shukra)', '0.5 – 1 ct diamond or 3 – 6 Ratti sapphire', 'Platinum or silver',
      'Middle finger, right hand', 'Friday morning', 'Enhances love, harmony, creativity, comforts and refinement.'),
  'Saturn': _GemInfo('Blue Sapphire (Neelam)', 'Saturn (Shani)', '3 – 5 Ratti', 'Silver or panchdhatu', 'Middle finger, right hand', 'Saturday evening',
      'Gives discipline, endurance and steady career growth. Always trial-wear for 3 days first.'),
};

const Map<String, List<String>> _mantras = {
  'Sun': ['Om Hraam Hreem Hraum Sah Suryaya Namah', '7,000'],
  'Moon': ['Om Shraam Shreem Shraum Sah Chandraya Namah', '11,000'],
  'Mars': ['Om Kraam Kreem Kraum Sah Bhaumaya Namah', '10,000'],
  'Mercury': ['Om Braam Breem Braum Sah Budhaya Namah', '9,000'],
  'Jupiter': ['Om Graam Greem Graum Sah Gurave Namah', '19,000'],
  'Venus': ['Om Draam Dreem Draum Sah Shukraya Namah', '16,000'],
  'Saturn': ['Om Praam Preem Praum Sah Shanaischaraya Namah', '23,000'],
  'Rahu': ['Om Bhraam Bhreem Bhraum Sah Rahave Namah', '18,000'],
  'Ketu': ['Om Sraam Sreem Sraum Sah Ketave Namah', '17,000'],
};

const Map<String, List<String>> _remedies = {
  'Sun': ['Offer water (Arghya) to the rising Sun from a copper vessel.', 'Recite Aditya Hridayam on Sundays and respect your father and elders.'],
  'Moon': ['Offer water or milk to Lord Shiva on Mondays.', 'Donate rice or white clothes on Monday and keep a regular sleep routine.'],
  'Mars': ['Recite Hanuman Chalisa on Tuesdays.', 'Donate red lentils (masoor dal) on Tuesday and channel energy into exercise.'],
  'Mercury': ['Feed green fodder to cows on Wednesdays.', 'Worship Lord Ganesha and donate green moong dal.'],
  'Jupiter': ['Offer yellow flowers and chana dal to Lord Vishnu on Thursdays.', 'Respect teachers and gurus; wear yellow on Thursdays.'],
  'Venus': ['Worship Goddess Lakshmi on Fridays.', 'Donate white sweets or rice on Friday; keep your surroundings clean and fragrant.'],
  'Saturn': ['Light a sesame-oil lamp under a Peepal tree on Saturday evening.', 'Donate black sesame or mustard oil and serve the elderly and workers.'],
  'Rahu': ['Recite Durga Chalisa and donate a blanket on Saturdays.', 'Avoid intoxicants and keep commitments honest.'],
  'Ketu': ['Feed stray dogs and worship Lord Ganesha.', 'Donate a multi-coloured blanket on Tuesdays or Saturdays.'],
};

class GemstoneRemedyScreen extends StatefulWidget {
  const GemstoneRemedyScreen({super.key});

  @override
  State<GemstoneRemedyScreen> createState() => _GemstoneRemedyScreenState();
}

class _GemstoneRemedyScreenState extends State<GemstoneRemedyScreen> {
  // Generic (non-personalised) recommendations from the backend, used when no Kundli exists.
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _generic;

  Future<void> _loadGeneric() async {
    final service = Provider.of<BackendService>(context, listen: false);
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic>? data;
    try {
      data = await service.fetchGemstoneRecommendations();
    } catch (_) {
      data = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _generic = data;
      if (data == null) _error = 'Could not load recommendations. Check your connection and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Gemstones & Remedies',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: kundli != null ? _buildPersonalised(kundli) : _buildGeneric(),
    );
  }

  // ---------------------------------------------------------------- personalised
  Widget _buildPersonalised(Map<String, dynamic> kundli) {
    final ascIdx = Vedic.signIndex(kundli['ascendant']);
    final ascendant = Vedic.text(kundli['ascendant']);
    final moonSign = Vedic.text(kundli['moonSign']);
    final name = Vedic.displayName(kundli);

    final lagnaLord = Vedic.signLords[ascIdx];
    final fifthLord = Vedic.signLords[(ascIdx + 4) % 12];
    final ninthLord = Vedic.signLords[(ascIdx + 8) % 12];

    final dasha = Vedic.vimshottari(kundli);
    final mdLord = dasha?.currentMaha?.lord ?? Vedic.text(Vedic.asMap(kundli['dashaInfo'])['currentMahadasha'], '');
    final validMd = _mantras.containsKey(mdLord) ? mdLord : '';

    final mantraPlanets = <String>{lagnaLord, if (validMd.isNotEmpty) validMd, ninthLord}.toList();
    final remedyPlanets = <String>{lagnaLord, if (validMd.isNotEmpty) validMd}.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _banner(
          'PERSONALISED FROM ${name.toUpperCase()}\'S KUNDLI',
          'Lagna: $ascendant · Moon: $moonSign',
          validMd.isNotEmpty
              ? 'Lagna lord $lagnaLord · Running $validMd Mahadasha'
              : 'Lagna lord $lagnaLord',
        ),
        const SizedBox(height: 22),
        _label('💎 LIFE STONE (LAGNA LORD · $lagnaLord)'.toUpperCase()),
        const SizedBox(height: 10),
        _primaryGemCard(_gems[lagnaLord]!),
        const SizedBox(height: 22),
        _label('SUPPORTING STONES'),
        const SizedBox(height: 10),
        _secondaryGemCard(_gems[fifthLord]!, 'Punya stone · 5th lord $fifthLord', const Color(0xFF059669)),
        const SizedBox(height: 10),
        _secondaryGemCard(_gems[ninthLord]!, 'Bhagya stone · 9th lord $ninthLord', const Color(0xFF317BEA)),
        const SizedBox(height: 22),
        _label('🕉️ RECOMMENDED MANTRAS'),
        const SizedBox(height: 10),
        ...mantraPlanets.map((p) => _mantraCard(
              '$p Beej Mantra${p == validMd ? ' · current Mahadasha' : (p == lagnaLord ? ' · Lagna lord' : ' · fortune')}',
              _mantras[p]![0],
              '108 times daily · full jap ${_mantras[p]![1]}',
            )),
        const SizedBox(height: 22),
        _label('🌿 DAILY REMEDIES'),
        const SizedBox(height: 10),
        _remediesCard([for (final p in remedyPlanets) ..._remedies[p]!]),
        const SizedBox(height: 18),
        _disclaimerAndCta(ascendant),
      ],
    );
  }

  // ---------------------------------------------------------------- generic
  Widget _buildGeneric() {
    if (!_loading && _generic == null && _error == null) {
      // e.g. the active profile changed to one without a Kundli after initState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading && _generic == null && _error == null) _loadGeneric();
      });
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)));
    }
    if (_loading && _generic == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)));
    }
    if (_error != null && _generic == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton.icon(onPressed: _loadGeneric, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/birth-details'),
                child: const Text('Add birth details for personalised remedies'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _generic ?? const <String, dynamic>{};
    final primary = Vedic.asMap(data['primaryGemstone']);
    final secondary = Vedic.asMap(data['secondaryGemstone']);
    final mantras = Vedic.asMapList(data['vedicMantras']);
    final remedies = (data['dailyRemedies'] is List) ? (data['dailyRemedies'] as List).map((e) => e.toString()).toList() : <String>[];

    _GemInfo fromMap(Map<String, dynamic> m) => _GemInfo(
          Vedic.text(m['name'], 'Gemstone'),
          Vedic.text(m['planet']),
          Vedic.text(m['ratti']),
          Vedic.text(m['metal']),
          Vedic.text(m['finger']),
          Vedic.text(m['day']),
          Vedic.text(m['benefits'], ''),
        );

    return RefreshIndicator(
      onRefresh: _loadGeneric,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _banner('GENERAL RECOMMENDATIONS', 'Not personalised yet', 'Add your birth details to get stones and mantras for your own Lagna and Dasha.'),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/birth-details'),
              icon: const Icon(Icons.edit_calendar_rounded, size: 18),
              label: const Text('Add birth details'),
            ),
          ),
          const SizedBox(height: 18),
          if (primary.isNotEmpty) ...[
            _label('💎 POPULAR GEMSTONE'),
            const SizedBox(height: 10),
            _primaryGemCard(fromMap(primary)),
            const SizedBox(height: 18),
          ],
          if (secondary.isNotEmpty) ...[
            _secondaryGemCard(fromMap(secondary), 'Complementary stone', const Color(0xFF059669)),
            const SizedBox(height: 18),
          ],
          if (mantras.isNotEmpty) ...[
            _label('🕉️ MANTRAS'),
            const SizedBox(height: 10),
            ...mantras.map((m) => _mantraCard(Vedic.text(m['planet'], 'Vedic Mantra'), Vedic.text(m['mantra']), Vedic.text(m['recitations'], ''))),
            const SizedBox(height: 18),
          ],
          if (remedies.isNotEmpty) ...[
            _label('🌿 DAILY REMEDIES'),
            const SizedBox(height: 10),
            _remediesCard(remedies),
            const SizedBox(height: 18),
          ],
          if (primary.isEmpty && mantras.isEmpty && remedies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No recommendations available right now.')),
            ),
          _disclaimerAndCta(null),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- widgets
  Widget _banner(String eyebrow, String title, String sub) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
      );

  Widget _primaryGemCard(_GemInfo g) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Color(0xFFFFF8E1), shape: BoxShape.circle),
                child: const Icon(Icons.diamond_rounded, color: Color(0xFFD97706), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.gem, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
                    const SizedBox(height: 2),
                    Text('Planet: ${g.planet}', style: const TextStyle(fontSize: 13, color: Color(0xFFD95D39), fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _detailRow('Weight', g.weight),
          _detailRow('Metal', g.metal),
          _detailRow('Finger', g.finger),
          _detailRow('When to wear', g.day),
          if (g.benefits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFCF7F1), borderRadius: BorderRadius.circular(14)),
              child: Text('✨ ${g.benefits}', style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _secondaryGemCard(_GemInfo g, String role, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.diamond_outlined, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(g.gem, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text('${g.planet} · ${g.weight} · ${g.finger}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (g.benefits.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(g.benefits, style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mantraCard(String title, String mantra, String recite) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9C27B0))),
          const SizedBox(height: 6),
          SelectableText('"$mantra"', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black, height: 1.3)),
          if (recite.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Recite: $recite', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _remediesCard(List<String> items) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: items
            .map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3))),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _detailRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(val, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _disclaimerAndCta(String? ascendant) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gemstones are strong remedies. Confirm with an astrologer (dasha, planetary strength and functional malefics) before wearing one, and buy only lab-certified natural stones.',
                  style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/chatbot', arguments: {
              'name': 'Pandit Shastri',
              'specialty': 'Gemstone & Remedy Advice',
              'field': 'Remedies',
              'initialMessage': ascendant != null
                  ? 'Which gemstone is safest for my $ascendant Lagna in my current dasha?'
                  : 'Which gemstone should I wear according to my birth chart?',
            }),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Confirm with an astrologer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE83D66),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}
