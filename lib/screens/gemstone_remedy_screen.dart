import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../services/backend_service.dart';
import '../widgets/ui/app_ui.dart';
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

/// The natural hue of each stone, used to tint its product tile. These are
/// data (the colour of the gem itself), not UI accents.
Color _gemHue(String gemName) {
  final n = gemName.toLowerCase();
  if (n.contains('ruby') || n.contains('manik')) return const Color(0xFFB3123A);
  if (n.contains('pearl') || n.contains('moti')) return const Color(0xFF8A8FA8);
  if (n.contains('coral') || n.contains('moonga')) return const Color(0xFFD9502E);
  if (n.contains('emerald') || n.contains('panna')) return const Color(0xFF0F8A5F);
  if (n.contains('yellow') || n.contains('pukhraj')) return const Color(0xFFD69A00);
  if (n.contains('blue') || n.contains('neelam')) return const Color(0xFF2843B0);
  if (n.contains('diamond') || n.contains('heera') || n.contains('white')) return const Color(0xFF5B7FD6);
  if (n.contains('hessonite') || n.contains('gomed')) return const Color(0xFFA0522D);
  if (n.contains('cat') || n.contains('lehsunia')) return const Color(0xFF7C6F3E);
  return AppColors.cosmicLight;
}

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

  void _askAstrologer(String? ascendant) {
    Navigator.pushNamed(context, '/chatbot', arguments: {
      'name': 'Pandit Shastri',
      'specialty': 'Gemstone & Remedy Advice',
      'field': 'Remedies',
      'initialMessage': ascendant != null
          ? 'Which gemstone is safest for my $ascendant Lagna in my current dasha?'
          : 'Which gemstone should I wear according to my birth chart?',
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    final ascendant = kundli != null ? Vedic.text(kundli['ascendant']) : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Gemstones & Remedies', overflow: TextOverflow.ellipsis),
      ),
      body: kundli != null && Vedic.signIndex(kundli['ascendant']) >= 0 ? _buildPersonalised(kundli) : _buildGeneric(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
            child: AppButton(
              label: 'Confirm with an astrologer',
              icon: Icons.chat_bubble_outline_rounded,
              onPressed: () => _askAstrologer(ascendant),
            ),
          ),
        ),
      ),
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

    const headerPad = EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
      children: [
        _banner(
          'Personalised for $name',
          'Lagna $ascendant · Moon $moonSign',
          validMd.isNotEmpty ? 'Lagna lord $lagnaLord · Running $validMd Mahadasha' : 'Lagna lord $lagnaLord',
        ),
        SectionHeader(
          title: 'Your life stone',
          subtitle: 'Ruled by your Lagna lord, $lagnaLord',
          padding: headerPad,
        ),
        _productCard(
          _gems[lagnaLord]!,
          role: 'Life stone',
          why: 'Strengthens $lagnaLord, the lord of your Lagna, which governs your health, confidence and overall direction in life.',
          featured: true,
        ),
        const SectionHeader(
          title: 'Supporting stones',
          subtitle: 'Optional. Wear only after your life stone suits you.',
          padding: headerPad,
        ),
        _productCard(
          _gems[fifthLord]!,
          role: 'Punya stone · 5th lord',
          why: 'Supports $fifthLord, lord of your 5th house: intellect, creativity, children and past-life merit.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _productCard(
          _gems[ninthLord]!,
          role: 'Bhagya stone · 9th lord',
          why: 'Supports $ninthLord, lord of your 9th house: luck, dharma, teachers and your father.',
        ),
        const SectionHeader(
          title: 'Recommended mantras',
          subtitle: 'A free remedy anyone can start today. 108 times daily.',
          padding: headerPad,
        ),
        ...mantraPlanets.map((p) => _mantraCard(
              '$p beej mantra${p == validMd ? ' · current Mahadasha' : (p == lagnaLord ? ' · Lagna lord' : ' · fortune')}',
              _mantras[p]![0],
              '108 times daily · full jap ${_mantras[p]![1]}',
            )),
        const SectionHeader(title: 'Daily remedies', subtitle: 'Simple habits that support these planets.', padding: headerPad),
        _remediesCard([for (final p in remedyPlanets) ..._remedies[p]!]),
        const SizedBox(height: AppSpacing.lg),
        _caution(),
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
      return _skeleton();
    }
    if (_loading && _generic == null) return _skeleton();
    if (_error != null && _generic == null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppStateView.error(title: 'Couldn\'t load gemstones', message: _error, onAction: _loadGeneric),
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

    const headerPad = EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm);

    return RefreshIndicator(
      onRefresh: _loadGeneric,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
        children: [
          _banner(
            'General recommendations',
            'Not personalised yet',
            'Add your birth details to get stones and mantras for your own Lagna and Dasha.',
            action: AppButton(
              label: 'Add birth details',
              icon: Icons.edit_calendar_rounded,
              expand: false,
              height: 44,
              onPressed: () => Navigator.pushNamed(context, '/birth-details'),
            ),
          ),
          if (primary.isNotEmpty) ...[
            const SectionHeader(title: 'Popular gemstone', padding: headerPad),
            _productCard(fromMap(primary), role: 'Most recommended', featured: true),
          ],
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _productCard(fromMap(secondary), role: 'Complementary stone'),
          ],
          if (mantras.isNotEmpty) ...[
            const SectionHeader(title: 'Mantras', padding: headerPad),
            ...mantras.map((m) => _mantraCard(Vedic.text(m['planet'], 'Vedic mantra'), Vedic.text(m['mantra']), Vedic.text(m['recitations'], ''))),
          ],
          if (remedies.isNotEmpty) ...[
            const SectionHeader(title: 'Daily remedies', padding: headerPad),
            _remediesCard(remedies),
          ],
          if (primary.isEmpty && mantras.isEmpty && remedies.isEmpty)
            const AppStateView(
              icon: Icons.diamond_outlined,
              title: 'No recommendations right now',
              message: 'Pull down to refresh, or add your birth details for a personalised list.',
            ),
          const SizedBox(height: AppSpacing.lg),
          _caution(),
        ],
      ),
    );
  }

  Widget _skeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
      children: const [
        SkeletonBox(height: 120, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.xl),
        SkeletonBox(width: 160, height: 18, radius: 6),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 220, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.sm),
        SkeletonBox(height: 140, radius: AppRadius.lg),
      ],
    );
  }

  // ---------------------------------------------------------------- widgets
  Widget _banner(String eyebrow, String title, String sub, {Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.diamond_outlined, color: AppColors.gold, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(eyebrow,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.gold, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: AppText.title.copyWith(color: AppColors.textOnDark)),
          const SizedBox(height: AppSpacing.xxs),
          Text(sub, style: AppText.body.copyWith(color: AppColors.textOnDarkMuted, fontSize: 13)),
          if (action != null) ...[const SizedBox(height: AppSpacing.md), action],
        ],
      ),
    );
  }

  /// Product-style gemstone card: tinted stone tile, name, why, how to wear.
  Widget _productCard(_GemInfo g, {required String role, String? why, bool featured = false}) {
    final hue = _gemHue(g.gem);
    final tile = featured ? 88.0 : 64.0;
    return AppCard(
      shadow: featured,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: '${g.gem} illustration',
                child: Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [hue.withValues(alpha: 0.10), hue.withValues(alpha: 0.24)],
                    ),
                  ),
                  child: Icon(Icons.diamond_rounded, color: hue, size: tile * 0.46),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: featured ? AppColors.primarySoft : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: featured ? AppColors.primaryDark : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(g.gem, maxLines: 2, overflow: TextOverflow.ellipsis, style: featured ? AppText.title : AppText.subtitle),
                    const SizedBox(height: 2),
                    Text('For ${g.planet}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (why != null || g.benefits.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Why it’s recommended', style: AppText.bodyStrong),
            const SizedBox(height: AppSpacing.xxs),
            if (why != null) Text(why, style: AppText.body.copyWith(fontSize: 13)),
            if (g.benefits.isNotEmpty) ...[
              if (why != null) const SizedBox(height: AppSpacing.xxs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_rounded, size: 16, color: AppColors.success),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(g.benefits, style: AppText.body.copyWith(fontSize: 13, color: AppColors.textPrimary))),
                ],
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          const Text('How to wear', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            child: Column(
              children: [
                _specRow(Icons.scale_outlined, 'Weight', g.weight),
                const Divider(height: 1),
                _specRow(Icons.circle_outlined, 'Metal', g.metal),
                const Divider(height: 1),
                _specRow(Icons.back_hand_outlined, 'Finger', g.finger),
                const Divider(height: 1),
                _specRow(Icons.event_outlined, 'When', g.day),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _specRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(width: 64, child: Text(label, style: AppText.caption.copyWith(color: AppColors.textSecondary, fontSize: 13))),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: AppText.bodyStrong.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _mantraCard(String title, String mantra, String recite) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.xxs, AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.caption.copyWith(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SelectableText(mantra, style: AppText.subtitle.copyWith(height: 1.4)),
                  if (recite.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text('Recite: $recite', style: AppText.caption),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy mantra',
              icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.textSecondary),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: mantra));
                if (mounted) showAppSnack(context, 'Mantra copied');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _remediesCard(List<String> items) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: AppColors.success, size: 14),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(items[i], style: AppText.body.copyWith(color: AppColors.textPrimary))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _caution() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Before you buy', style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  'Gemstones are strong remedies. Confirm with an astrologer (dasha, planetary strength and functional malefics) before wearing one, and buy only lab-certified natural stones.',
                  style: AppText.body.copyWith(fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
