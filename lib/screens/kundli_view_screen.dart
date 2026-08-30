import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

const List<String> _zodiacSigns = [
  'Aries', 'Taurus', 'Gemini', 'Cancer', 
  'Leo', 'Virgo', 'Libra', 'Scorpio', 
  'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
];

const Map<int, String> _houseMeanings = {
  1: 'Self, Health & Personality',
  2: 'Wealth, Family & Speech',
  3: 'Courage, Siblings & Skills',
  4: 'Home, Mother & Peace',
  5: 'Children, Intelligence & Karma',
  6: 'Health, Obstacles & Service',
  7: 'Marriage, Spouse & Partners',
  8: 'Longevity, Transformation & Mystery',
  9: 'Luck, Higher Learning & Father',
  10: 'Career, Status & Fame',
  11: 'Gains, Income & Friends',
  12: 'Losses, Foreign & Spirituality'
};

int _getNavamshaSignIndex(double long) {
  final signIdx = (long / 30).floor() % 12;
  final remDeg = long % 30;
  final navIdx = (remDeg / (30 / 9)).floor();

  int startSign = 0;
  if ([0, 4, 8].contains(signIdx)) {
    startSign = 0;
  } else if ([1, 5, 9].contains(signIdx)) {
    startSign = 9;
  } else if ([2, 6, 10].contains(signIdx)) {
    startSign = 6;
  } else if ([3, 7, 11].contains(signIdx)) {
    startSign = 3;
  }
  return (startSign + navIdx) % 12;
}

int _getDasamshaSignIndex(double long) {
  final signIdx = (long / 30).floor() % 12;
  final remDeg = long % 30;
  final dasIdx = (remDeg / (30 / 10)).floor();

  int startSign = 0;
  if (signIdx % 2 == 0) {
    startSign = signIdx;
  } else {
    startSign = (signIdx + 8) % 12;
  }
  return (startSign + dasIdx) % 12;
}

class KundliViewScreen extends StatefulWidget {
  const KundliViewScreen({super.key});

  @override
  State<KundliViewScreen> createState() => _KundliViewScreenState();
}

class _KundliViewScreenState extends State<KundliViewScreen> {
  int _selectedSubTab = 0; // 0: D1, 1: D9, 2: D10, 3: Panchang & Avakhada, 4: Planets & Nakshatras, 5: Full Life Report
  String? _cachedReport;
  bool _isLoadingReport = false;

  final List<String> _subTabs = [
    'Birth Chart (D1)',
    'Navamsha (D9)',
    'Dasamsha (D10)',
    'Panchang & Avakhada',
    'Planets & Nakshatras',
    'Full Life Report'
  ];

  Future<void> _fetchReportIfNeeded(BackendService backendService, Map<String, dynamic> kundli, Map<String, dynamic> birth) async {
    if (_cachedReport != null || _isLoadingReport) return;
    if (kundli['aiReport'] != null && kundli['aiReport'].toString().trim().isNotEmpty) {
      setState(() => _cachedReport = kundli['aiReport']);
      return;
    }

    setState(() => _isLoadingReport = true);
    final report = await backendService.fetchAIKundliReport(kundli, birthDetails: birth);
    if (mounted) {
      setState(() {
        _cachedReport = report ?? '''### 👤 Personality & Core Nature
Born under **${kundli['ascendant'] ?? 'Vedic'} Ascendant** with **Moon in ${kundli['moonSign']}** and **${kundli['nakshatra']} Nakshatra**, you possess an analytical, morally grounded character with strong intuition and creative vision.

### 🏋️ Physical Traits & Vitality
Your **${kundli['ascendant']} Lagna** endows you with an impressive presence, quick reflexes, and clear expressive eyes.

### 🩺 Health & Wellness Outlook
Your health profile is supported by balanced planetary placements. Practice regular daily routines and mindfulness meditation.

### 💼 Career, Wealth & Professional Success
Your **D10 Dasamsha Chart (Lagna: ${kundli['d10Dasamsha']?['ascendant'] ?? kundli['ascendant']})** indicates strong leadership potential and steady financial growth.

### ❤️ Marriage, Relationships & Life Partner
Your **D9 Navamsha Chart (Lagna: ${kundli['d9Navamsha']?['ascendant'] ?? kundli['ascendant']})** reveals deep emotional maturity and lasting marital harmony.

### ⏳ Understanding of Active Dasha Period
Active Mahadasha: **${kundli['dashaInfo']?['currentMahadasha'] ?? 'Mars'}** | Antardasha: **${kundli['dashaInfo']?['antardasha'] ?? 'Jupiter'}**. This period favors strategic career decisions.

### 🏁 Final Executive Summary & Sacred Guidance
Embrace discipline and purposeful action to maximize the positive fruits of your birth chart.''';
        _isLoadingReport = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final selectedFamily = backendService.selectedFamilyMember;

    final Map<String, dynamic> kundli = (selectedFamily != null && selectedFamily['kundli'] != null)
        ? {
            ...selectedFamily['kundli'],
            'birthDetails': {
              'fullName': selectedFamily['fullName'],
              'relationship': selectedFamily['relationship'],
              'dateOfBirth': selectedFamily['dateOfBirth'],
              'timeOfBirth': selectedFamily['timeOfBirth'],
              'placeOfBirth': selectedFamily['placeOfBirth'],
            }
          }
        : (backendService.kundliData ?? {
            'ascendant': 'Gemini',
            'sunSign': 'Capricorn',
            'moonSign': 'Taurus',
            'nakshatra': 'Mrigashira',
            'nakshatraPada': 1,
            'birthDetails': {'fullName': 'Main Profile', 'placeOfBirth': 'Delhi'},
            'dashaInfo': {
              'currentMahadasha': 'Mars',
              'antardasha': 'Jupiter',
              'dashaEndDate': '2030-08-15'
            },
            'planetaryPositions': [
              {'name': 'Sun ☉', 'sign': 'Capricorn', 'house': 8, 'degree': 4.2, 'speed': 'Direct', 'nakshatra': 'Uttara Ashadha', 'nakshatraPada': 3, 'planetLord': 'Sun'},
              {'name': 'Moon ☽', 'sign': 'Taurus', 'house': 12, 'degree': 24.5, 'speed': 'Fast', 'nakshatra': 'Mrigashira', 'nakshatraPada': 1, 'planetLord': 'Mars'},
              {'name': 'Mars ♂', 'sign': 'Scorpio', 'house': 6, 'degree': 18.1, 'speed': 'Direct', 'nakshatra': 'Jyeshtha', 'nakshatraPada': 1, 'planetLord': 'Mercury'},
              {'name': 'Mercury ☿', 'sign': 'Sagittarius', 'house': 7, 'degree': 19.4, 'speed': 'Direct', 'nakshatra': 'Purva Ashadha', 'nakshatraPada': 2, 'planetLord': 'Venus'},
              {'name': 'Jupiter ♃', 'sign': 'Aries', 'house': 11, 'degree': 12.8, 'speed': 'Direct', 'nakshatra': 'Ashwini', 'nakshatraPada': 4, 'planetLord': 'Ketu'},
              {'name': 'Venus ♀', 'sign': 'Aquarius', 'house': 9, 'degree': 14.6, 'speed': 'Direct', 'nakshatra': 'Shatabhisha', 'nakshatraPada': 3, 'planetLord': 'Rahu'},
              {'name': 'Saturn ♄', 'sign': 'Pisces', 'house': 10, 'degree': 8.9, 'speed': 'Retrograde', 'nakshatra': 'Uttara Bhadrapada', 'nakshatraPada': 2, 'planetLord': 'Saturn'},
              {'name': 'Rahu ☊', 'sign': 'Cancer', 'house': 2, 'degree': 15.3, 'speed': 'Retrograde', 'nakshatra': 'Pushya', 'nakshatraPada': 4, 'planetLord': 'Saturn'},
              {'name': 'Ketu ☋', 'sign': 'Capricorn', 'house': 8, 'degree': 15.3, 'speed': 'Retrograde', 'nakshatra': 'Shravana', 'nakshatraPada': 2, 'planetLord': 'Moon'},
            ]
          });

    final birth = kundli['birthDetails'] ?? {};
    final fullName = birth['fullName'] ?? kundli['fullName'] ?? 'Vedic Profile';
    final relationship = birth['relationship'];
    final d1Ascendant = kundli['ascendant'] ?? 'Gemini';
    final sunSign = kundli['sunSign'] ?? 'Capricorn';
    final moonSign = kundli['moonSign'] ?? 'Taurus';
    final nakshatra = kundli['nakshatra'] ?? 'Mrigashira';
    final pada = kundli['nakshatraPada'] ?? 1;
    final dasha = kundli['dashaInfo'] ?? {'currentMahadasha': 'Mars', 'antardasha': 'Jupiter', 'dashaEndDate': '2030-08-15'};
    
    final List d1Planets = (kundli['planetaryPositions'] is List && (kundli['planetaryPositions'] as List).isNotEmpty)
        ? (kundli['planetaryPositions'] as List)
        : [];

    // Derive D9 Navamsha Chart Data
    String d9Ascendant = d1Ascendant;
    List d9Planets = [];
    if (kundli['d9Navamsha'] != null) {
      d9Ascendant = kundli['d9Navamsha']['ascendant'] ?? d1Ascendant;
      d9Planets = kundli['d9Navamsha']['planetaryPositions'] ?? [];
    } else {
      final d1AscIdx = _zodiacSigns.indexOf(d1Ascendant);
      final d9AscIdx = (d1AscIdx >= 0) ? _getNavamshaSignIndex(d1AscIdx * 30.0 + 15.0) : 0;
      d9Ascendant = _zodiacSigns[d9AscIdx];
      d9Planets = d1Planets.map((p) {
        final sign = p['sign'] ?? 'Aries';
        final deg = double.tryParse(p['degree']?.toString() ?? '15.0') ?? 15.0;
        final sIdx = _zodiacSigns.indexOf(sign);
        final absLong = (sIdx >= 0 ? sIdx : 0) * 30.0 + deg;
        final pD9SignIdx = _getNavamshaSignIndex(absLong);
        final house = ((pD9SignIdx - d9AscIdx + 12) % 12) + 1;
        return {
          ...p,
          'sign': _zodiacSigns[pD9SignIdx],
          'house': house,
        };
      }).toList();
    }

    // Derive D10 Dasamsha Chart Data
    String d10Ascendant = d1Ascendant;
    List d10Planets = [];
    if (kundli['d10Dasamsha'] != null) {
      d10Ascendant = kundli['d10Dasamsha']['ascendant'] ?? d1Ascendant;
      d10Planets = kundli['d10Dasamsha']['planetaryPositions'] ?? [];
    } else {
      final d1AscIdx = _zodiacSigns.indexOf(d1Ascendant);
      final d10AscIdx = (d1AscIdx >= 0) ? _getDasamshaSignIndex(d1AscIdx * 30.0 + 15.0) : 0;
      d10Ascendant = _zodiacSigns[d10AscIdx];
      d10Planets = d1Planets.map((p) {
        final sign = p['sign'] ?? 'Aries';
        final deg = double.tryParse(p['degree']?.toString() ?? '15.0') ?? 15.0;
        final sIdx = _zodiacSigns.indexOf(sign);
        final absLong = (sIdx >= 0 ? sIdx : 0) * 30.0 + deg;
        final pD10SignIdx = _getDasamshaSignIndex(absLong);
        final house = ((pD10SignIdx - d10AscIdx + 12) % 12) + 1;
        return {
          ...p,
          'sign': _zodiacSigns[pD10SignIdx],
          'house': house,
        };
      }).toList();
    }

    if (_selectedSubTab == 5 && _cachedReport == null && !_isLoadingReport) {
      _fetchReportIfNeeded(backendService, kundli, birth);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          relationship != null ? '$relationship\'s Vedic Kundli' : 'Your Vedic Kundli',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            if (relationship != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  relationship,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Born: ${birth['dateOfBirth'] ?? 'N/A'} • ${birth['placeOfBirth'] ?? 'N/A'}",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sub-Tab Navigation Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_subTabs.length, (index) {
                  final isSelected = _selectedSubTab == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(_subTabs[index]),
                      selected: isSelected,
                      selectedColor: const Color(0xFF6C63FF),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade300,
                        ),
                      ),
                      onSelected: (val) {
                        setState(() => _selectedSubTab = index);
                        if (index == 5) {
                          _fetchReportIfNeeded(backendService, kundli, birth);
                        }
                      },
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),

            // Sub-Tab Visual Content Switcher
            if (_selectedSubTab == 0)
              _buildVisualNorthIndianChart(d1Ascendant, d1Planets, 'D1 LAGNA CHART')
            else if (_selectedSubTab == 1)
              _buildVisualNorthIndianChart(d9Ascendant, d9Planets, 'D9 NAVAMSHA CHART')
            else if (_selectedSubTab == 2)
              _buildVisualNorthIndianChart(d10Ascendant, d10Planets, 'D10 DASAMSHA CHART')
            else if (_selectedSubTab == 3)
              _buildPanchangAndAvakhadaView(kundli)
            else if (_selectedSubTab == 4)
              _buildPlanetsAndDashaSection(dasha, d1Planets)
            else
              _buildFullReportView(fullName),

            const SizedBox(height: 20),

            // Key Highlights Cards
            const Text(
              'Chart Highlights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildInfoCard('Ascendant (Lagna)', d1Ascendant, Icons.flare_rounded, const Color(0xFFFF6B81)),
                _buildInfoCard('Moon Sign (Rasi)', moonSign, Icons.brightness_3_rounded, const Color(0xFF317BEA)),
                _buildInfoCard('Sun Sign', sunSign, Icons.wb_sunny_rounded, const Color(0xFFFF9800)),
                _buildInfoCard('Nakshatra', "$nakshatra (P$pada)", Icons.star_rounded, const Color(0xFF9C27B0)),
              ],
            ),
            const SizedBox(height: 20),

            // Vimshottari Dasha Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B0000), Color(0xFFB22222)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.hourglass_bottom_rounded, color: Colors.white70, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Vimshottari Dasha Timeline',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Current Mahadasha: ${dasha['currentMahadasha'] ?? 'Mars'}",
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Antardasha: ${dasha['antardasha'] ?? 'Jupiter'}",
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🌅 Panchang & Avakhada Chakra View
  Widget _buildPanchangAndAvakhadaView(Map<String, dynamic> kundli) {
    final panchang = kundli['panchang'] ?? {
      'tithi': 'Pratipada',
      'vaar': 'Tuesday',
      'nakshatra': kundli['nakshatra'] ?? 'Swati',
      'yoga': 'Priti',
      'karana': 'Bava'
    };

    final avakhada = kundli['avakhada'] ?? {
      'varna': 'Shudra',
      'vashya': 'Manav',
      'yoni': 'Buffalo',
      'gana': 'Deva',
      'nadi': 'Antya',
      'paya': 'Silver',
      'tatwa': 'Air'
    };

    return Column(
      children: [
        // Panchang Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.wb_sunny_rounded, color: Color(0xFFFF9800), size: 22),
                  SizedBox(width: 10),
                  Text('Birth Panchang Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ],
              ),
              const SizedBox(height: 14),
              _buildKeyValuePair('Tithi (Lunar Day)', panchang['tithi'] ?? 'Pratipada'),
              const Divider(height: 16),
              _buildKeyValuePair('Vaar (Weekday)', panchang['vaar'] ?? 'Tuesday'),
              const Divider(height: 16),
              _buildKeyValuePair('Nakshatra', panchang['nakshatra'] ?? 'Swati'),
              const Divider(height: 16),
              _buildKeyValuePair('Yoga', panchang['yoga'] ?? 'Priti'),
              const Divider(height: 16),
              _buildKeyValuePair('Karana', panchang['karana'] ?? 'Bava'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Avakhada Chakra Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 22),
                  SizedBox(width: 10),
                  Text('Avakhada Chakra Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ],
              ),
              const SizedBox(height: 14),
              _buildKeyValuePair('Varna', avakhada['varna'] ?? 'Shudra'),
              const Divider(height: 16),
              _buildKeyValuePair('Vashya', avakhada['vashya'] ?? 'Manav'),
              const Divider(height: 16),
              _buildKeyValuePair('Yoni (Animal Motif)', avakhada['yoni'] ?? 'Buffalo'),
              const Divider(height: 16),
              _buildKeyValuePair('Gana (Temperament)', avakhada['gana'] ?? 'Deva'),
              const Divider(height: 16),
              _buildKeyValuePair('Nadi (Pulse)', avakhada['nadi'] ?? 'Antya'),
              const Divider(height: 16),
              _buildKeyValuePair('Paya (Metal Element)', avakhada['paya'] ?? 'Silver'),
              const Divider(height: 16),
              _buildKeyValuePair('Tatwa (Element)', avakhada['tatwa'] ?? 'Air'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeyValuePair(String label, String val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
        Text(val, style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // Complete Vedic Janam Kundli Life Reading Report Widget
  Widget _buildFullReportView(String fullName) {
    if (_isLoadingReport) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            children: const [
              CircularProgressIndicator(color: Color(0xFF6C63FF)),
              SizedBox(height: 16),
              Text(
                'Loading Complete Life Report...',
                style: TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (_cachedReport != null && _cachedReport!.isNotEmpty) {
      return _buildFormattedReportSections(_cachedReport!);
    }

    return const Center(child: Text('Loading your complete Vedic Kundli Report...'));
  }

  Widget _buildFormattedReportSections(String rawReport) {
    final List<String> blocks = rawReport.split('###').where((b) => b.trim().isNotEmpty).toList();

    if (blocks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: SelectableText.rich(
          TextSpan(children: _parseFormattedSpans(rawReport)),
        ),
      );
    }

    return Column(
      children: blocks.map((block) {
        final lines = block.trim().split('\n');
        final titleLine = lines.first.trim();
        final bodyText = lines.sublist(1).join('\n').trim();

        Color cardColor = const Color(0xFF6C63FF);
        IconData icon = Icons.stars_rounded;

        if (titleLine.contains('Personality')) {
          cardColor = const Color(0xFF317BEA);
          icon = Icons.person_rounded;
        } else if (titleLine.contains('Physical')) {
          cardColor = const Color(0xFF00B894);
          icon = Icons.fitness_center_rounded;
        } else if (titleLine.contains('Health')) {
          cardColor = const Color(0xFFE17055);
          icon = Icons.health_and_safety_rounded;
        } else if (titleLine.contains('Career')) {
          cardColor = const Color(0xFFFF9800);
          icon = Icons.work_rounded;
        } else if (titleLine.contains('Marriage')) {
          cardColor = const Color(0xFFE84393);
          icon = Icons.favorite_rounded;
        } else if (titleLine.contains('Dasha')) {
          cardColor = const Color(0xFF9C27B0);
          icon = Icons.hourglass_bottom_rounded;
        } else if (titleLine.contains('Final') || titleLine.contains('Summary')) {
          cardColor = const Color(0xFFD95D39);
          icon = Icons.workspace_premium_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardColor.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: cardColor.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: cardColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titleLine,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              SelectableText.rich(
                TextSpan(children: _parseFormattedSpans(bodyText)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<TextSpan> _parseFormattedSpans(String text) {
    final List<TextSpan> spans = [];
    final RegExp exp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in exp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: const TextStyle(color: Color(0xFF2D3748), fontSize: 14, height: 1.6),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 14, height: 1.6),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: const TextStyle(color: Color(0xFF2D3748), fontSize: 14, height: 1.6),
      ));
    }

    return spans;
  }

  // Visual North Indian Diamond Kundli Chart Widget & House-by-House Breakdown
  Widget _buildVisualNorthIndianChart(String ascendant, List planetsList, String chartTitle) {
    final ascIdx = _zodiacSigns.indexOf(ascendant);
    final ascSignNum = (ascIdx >= 0) ? ascIdx + 1 : 1;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 20),
                      const SizedBox(width: 8),
                      Text(chartTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text('Lagna: $ascendant (#$ascSignNum)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD95D39))),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // How-to-Read Guide Pill
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, color: Color(0xFF6C63FF), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Top Center = 1st House (Lagna). Small numbers (1–12) in corners show Zodiac Signs.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF4A44A8), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Authentic 12-House North Indian Kundli Chart Diagram
              SizedBox(
                width: 320,
                height: 320,
                child: CustomPaint(
                  size: const Size(320, 320),
                  painter: VisualNorthIndianKundliPainter(
                    ascendant: ascendant,
                    planetsList: planetsList,
                    chartTitle: chartTitle,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Easy-to-Understand House-by-House Breakdown Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.grid_view_rounded, color: Color(0xFF6C63FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'House-by-House Breakdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Explore what planets occupy each of your 12 Life Houses:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              ...List.generate(12, (i) {
                final houseNum = i + 1;
                final signNum = ((ascSignNum - 1 + i) % 12) + 1;
                final signName = _zodiacSigns[signNum - 1];
                final meaning = _houseMeanings[houseNum] ?? '';

                final housePlanets = planetsList.where((p) => (p['house'] ?? 1) == houseNum).toList();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: housePlanets.isNotEmpty
                        ? const Color(0xFF6C63FF).withValues(alpha: 0.06)
                        : const Color(0xFFFCF7F1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: housePlanets.isNotEmpty
                          ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: housePlanets.isNotEmpty ? const Color(0xFF6C63FF) : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$houseNum',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'House $houseNum • $signName (#$signNum)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                                ),
                                if (houseNum == 1) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD95D39),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('LAGNA', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              meaning,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (housePlanets.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: housePlanets.map((p) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C63FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p['name'].toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                        )
                      else
                        Text(
                          'Empty',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // Planets & Nakshatras List View
  Widget _buildPlanetsAndDashaSection(dynamic dasha, List planetsList) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '9 Grahas & Nakshatra Placements',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          const SizedBox(height: 14),
          ...planetsList.map((p) {
            final name = p['name'] ?? 'Planet';
            final sign = p['sign'] ?? 'Sign';
            final house = p['house'] ?? 1;
            final deg = p['degree'] ?? 10.0;
            final nak = p['nakshatra'] ?? 'Nakshatra';
            final pada = p['nakshatraPada'] ?? 1;
            final lord = p['planetLord'] ?? 'Lord';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text(name.toString()[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6C63FF))),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('House $house • $sign (${deg}°)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          Text('$nak (Pada $pada) • Lord: $lord', style: const TextStyle(fontSize: 11, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${deg}°',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFD95D39)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Authentic 12-House North Indian Diamond Kundli Chart
class VisualNorthIndianKundliPainter extends CustomPainter {
  final String ascendant;
  final List planetsList;
  final String chartTitle;

  VisualNorthIndianKundliPainter({
    required this.ascendant,
    required this.planetsList,
    required this.chartTitle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final paintLine = Paint()
      ..color = const Color(0xFF6C63FF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..color = const Color(0xFFFCF7F1)
      ..style = PaintingStyle.fill;

    // 1. Outer Square Background
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paintFill);

    // 2. Outer Border Line
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paintLine);

    // 3. Inner Diagonals (X shape)
    canvas.drawLine(const Offset(0, 0), Offset(w, h), paintLine);
    canvas.drawLine(Offset(w, 0), Offset(0, h), paintLine);

    // 4. Inner Diamond (Kite shape linking midpoints)
    final Path diamondPath = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w / 2, h)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawPath(diamondPath, paintLine);

    // 5. Outer Title Tag is already in header, keep center clean & clear

    // 6. Draw Zodiac Sign Numbers (1 to 12) at House Inner Vertices
    final ascIdx = _zodiacSigns.indexOf(ascendant);
    final ascSignNum = (ascIdx >= 0) ? ascIdx + 1 : 1;

    final List<Offset> signNumberOffsets = [
      Offset(w * 0.50, h * 0.36),  // H1 (bottom inner vertex of top diamond)
      Offset(w * 0.25, h * 0.20),  // H2 (inner vertex of top-left triangle)
      Offset(w * 0.20, h * 0.25),  // H3 (inner vertex of left-top triangle)
      Offset(w * 0.36, h * 0.50),  // H4 (right inner vertex of left diamond)
      Offset(w * 0.20, h * 0.75),  // H5 (inner vertex of left-bottom triangle)
      Offset(w * 0.25, h * 0.80),  // H6 (inner vertex of bottom-left triangle)
      Offset(w * 0.50, h * 0.64),  // H7 (top inner vertex of bottom diamond)
      Offset(w * 0.75, h * 0.80),  // H8 (inner vertex of bottom-right triangle)
      Offset(w * 0.80, h * 0.75),  // H9 (inner vertex of right-bottom triangle)
      Offset(w * 0.64, h * 0.50),  // H10 (left inner vertex of right diamond)
      Offset(w * 0.80, h * 0.25),  // H11 (inner vertex of right-top triangle)
      Offset(w * 0.75, h * 0.20),  // H12 (inner vertex of top-right triangle)
    ];

    for (int i = 0; i < 12; i++) {
      final signNum = ((ascSignNum - 1 + i) % 12) + 1;
      final pos = signNumberOffsets[i];

      final TextPainter st = TextPainter(
        text: TextSpan(
          text: '$signNum',
          style: const TextStyle(
            color: Color(0xFFD95D39),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      st.layout();
      st.paint(canvas, Offset(pos.dx - st.width / 2, pos.dy - st.height / 2));
    }

    // 7. Draw House Placements & Planets
    final List<List<String>> housePlanets = List.generate(12, (_) => []);
    for (var p in planetsList) {
      final int house = (p['house'] ?? 1) as int;
      if (house >= 1 && house <= 12) {
        final name = p['name'].toString().split(' ')[0];
        housePlanets[house - 1].add(name);
      }
    }

    // Centered Positions for Planets in 12 Houses
    final List<Offset> houseOffsets = [
      Offset(w * 0.50, h * 0.18),  // House 1 (Top Diamond center)
      Offset(w * 0.25, h * 0.08),  // House 2 (Top-Left triangle center)
      Offset(w * 0.08, h * 0.25),  // House 3 (Left-Top triangle center)
      Offset(w * 0.18, h * 0.50),  // House 4 (Left Diamond center)
      Offset(w * 0.08, h * 0.75),  // House 5 (Left-Bottom triangle center)
      Offset(w * 0.25, h * 0.92),  // House 6 (Bottom-Left triangle center)
      Offset(w * 0.50, h * 0.82),  // House 7 (Bottom Diamond center)
      Offset(w * 0.75, h * 0.92),  // House 8 (Bottom-Right triangle center)
      Offset(w * 0.92, h * 0.75),  // House 9 (Right-Bottom triangle center)
      Offset(w * 0.82, h * 0.50),  // House 10 (Right Diamond center)
      Offset(w * 0.92, h * 0.25),  // House 11 (Right-Top triangle center)
      Offset(w * 0.75, h * 0.08),  // House 12 (Top-Right triangle center)
    ];

    for (int i = 0; i < 12; i++) {
      final pos = houseOffsets[i];
      final planets = housePlanets[i];

      if (planets.isNotEmpty) {
        final String formattedText = planets.join('\n');
        final TextPainter pt = TextPainter(
          text: TextSpan(
            text: formattedText,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              height: 1.1,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        pt.layout();
        pt.paint(canvas, Offset(pos.dx - pt.width / 2, pos.dy - pt.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
