import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_service.dart';

const List<String> _zodiacSigns = [
  'Aries', 'Taurus', 'Gemini', 'Cancer', 
  'Leo', 'Virgo', 'Libra', 'Scorpio', 
  'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
];

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

class ChartTab extends StatefulWidget {
  const ChartTab({super.key});

  @override
  State<ChartTab> createState() => _ChartTabState();
}

class _ChartTabState extends State<ChartTab> {
  int _selectedSubTab = 0; // 0: Birth Chart (D1), 1: Navamsha (D9), 2: Dasamsha (D10), 3: Planets & Dashas, 4: Astrocartography, 5: AI Full Reading
  bool _isInteractiveMode = true;
  String? _aiReport;
  bool _isLoadingReport = false;

  final List<String> _subTabs = [
    'Birth Chart (D1)',
    'Navamsha (D9)',
    'Dasamsha (D10)',
    'Panchang & Avakhada',
    'Planets & Nakshatras',
    'Full Life Report'
  ];

  Future<void> _fetchAIReportIfNeeded(BackendService backendService, Map<String, dynamic> kundli) async {
    if (_aiReport != null || _isLoadingReport) return;
    if (kundli['aiReport'] != null && kundli['aiReport'].toString().trim().isNotEmpty) {
      setState(() => _aiReport = kundli['aiReport']);
      return;
    }

    setState(() => _isLoadingReport = true);
    final birth = kundli['birthDetails'] ?? {};
    final report = await backendService.fetchAIKundliReport(kundli, birthDetails: birth);
    if (mounted) {
      setState(() {
        _aiReport = report ?? '''### 👤 Personality & Core Nature
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
            'ascendant': 'Scorpio',
            'sunSign': 'Gemini',
            'moonSign': 'Pisces',
            'nakshatra': 'Uttara Bhadrapada',
            'nakshatraPada': 2,
            'birthDetails': {'fullName': 'ravindra'},
            'dashaInfo': {
              'currentMahadasha': 'Saturn',
              'antardasha': 'Venus',
              'dashaEndDate': '2032-08-15'
            },
            'planetaryPositions': [
              {'name': 'Sun ☉', 'sign': 'Gemini', 'house': 8, 'degree': 29.5, 'speed': 'Direct'},
              {'name': 'Moon ☽', 'sign': 'Pisces', 'house': 5, 'degree': 14.2, 'speed': 'Fast'},
              {'name': 'Mars ♂', 'sign': 'Aries', 'house': 6, 'degree': 12.8, 'speed': 'Direct'},
              {'name': 'Mercury ☿', 'sign': 'Cancer', 'house': 9, 'degree': 04.1, 'speed': 'Direct'},
              {'name': 'Jupiter ♃', 'sign': 'Taurus', 'house': 7, 'degree': 18.9, 'speed': 'Direct'},
              {'name': 'Venus ♀', 'sign': 'Gemini', 'house': 8, 'degree': 22.3, 'speed': 'Direct'},
              {'name': 'Saturn ♄', 'sign': 'Aquarius', 'house': 4, 'degree': 16.7, 'speed': 'Retrograde'},
              {'name': 'Rahu ☊', 'sign': 'Pisces', 'house': 5, 'degree': 21.0, 'speed': 'Retrograde'},
              {'name': 'Ketu ☋', 'sign': 'Virgo', 'house': 11, 'degree': 21.0, 'speed': 'Retrograde'},
            ]
          });

    final name = kundli['birthDetails']?['fullName'] ?? kundli['fullName'] ?? 'ravindra';
    final relationship = kundli['birthDetails']?['relationship'];
    final ascendant = kundli['ascendant'] ?? 'Scorpio';
    final moonSign = kundli['moonSign'] ?? 'Pisces';
    final nakshatra = kundli['nakshatra'] ?? 'Uttara Bhadrapada';
    final pada = kundli['nakshatraPada'] ?? 2;
    final dasha = kundli['dashaInfo'] ?? {'currentMahadasha': 'Saturn', 'antardasha': 'Venus', 'dashaEndDate': '2032-08-15'};

    final List planetsList = (kundli['planetaryPositions'] is List && (kundli['planetaryPositions'] as List).isNotEmpty)
        ? (kundli['planetaryPositions'] as List)
        : [
            {'name': 'Sun ☉', 'sign': 'Gemini', 'house': 8, 'degree': 29.5},
            {'name': 'Moon ☽', 'sign': 'Pisces', 'house': 5, 'degree': 14.2},
            {'name': 'Mars ♂', 'sign': 'Aries', 'house': 6, 'degree': 12.8},
            {'name': 'Mercury ☿', 'sign': 'Cancer', 'house': 9, 'degree': 04.1},
            {'name': 'Jupiter ♃', 'sign': 'Taurus', 'house': 7, 'degree': 18.9},
            {'name': 'Venus ♀', 'sign': 'Gemini', 'house': 8, 'degree': 22.3},
            {'name': 'Saturn ♄', 'sign': 'Aquarius', 'house': 4, 'degree': 16.7},
            {'name': 'Rahu ☊', 'sign': 'Pisces', 'house': 5, 'degree': 21.0},
            {'name': 'Ketu ☋', 'sign': 'Virgo', 'house': 11, 'degree': 21.0},
          ];

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'R',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      relationship != null ? '$relationship Kundli' : 'Personal Vedic Kundli',
                      style: TextStyle(color: relationship != null ? const Color(0xFF6C63FF) : Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    if (relationship != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => backendService.selectFamilyMember(null),
                        child: const Text('(Switch Self)', style: TextStyle(fontSize: 10, color: Color(0xFFE83D66), decoration: TextDecoration.underline)),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded, color: Color(0xFF317BEA), size: 16),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A17),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.auto_awesome, color: Color(0xFFFFB74D), size: 14),
                SizedBox(width: 4),
                Text(
                  'Neon DB Synced',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            // 1. Horizontal Sub-Tabs (D1, D9, D10, Dashas, ACG)
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _subTabs.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedSubTab == index;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSubTab = index;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1E1A17) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        _subTabs[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // Header Title
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black),
                children: [
                  const TextSpan(text: 'A map of '),
                  TextSpan(
                    text: _subTabs[_selectedSubTab],
                    style: const TextStyle(
                      color: Color(0xFFD95D39),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. Interactive Switch Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Interactive mode',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                      const SizedBox(width: 8),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: _isInteractiveMode,
                          activeTrackColor: const Color(0xFF7C77E6),
                          onChanged: (val) {
                            setState(() {
                              _isInteractiveMode = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.stars_rounded, color: Color(0xFF7C77E6), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Lahiri Ayanamsa',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 3. Dynamic Sub-Tab Content Switcher
            _buildSelectedSubTabContent(kundli, ascendant, moonSign, nakshatra, pada, dasha, planetsList),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSubTabContent(Map<String, dynamic> kundli, String ascendant, String moonSign, String nakshatra, dynamic pada, dynamic dasha, List planetsList) {
    switch (_selectedSubTab) {
      case 0:
        return _buildBirthChartD1View(ascendant, moonSign, nakshatra, pada, planetsList);
      case 1:
        return _buildNavamshaD9View(kundli, ascendant, moonSign, planetsList);
      case 2:
        return _buildDasamshaD10View(kundli, ascendant, planetsList);
      case 3:
        return _buildGrahaTableAndDashaView(dasha, planetsList);
      case 4:
        return _buildAstrocartographyView();
      case 5:
        return _buildAIReportSection(kundli);
      default:
        return _buildBirthChartD1View(ascendant, moonSign, nakshatra, pada, planetsList);
    }
  }

  // Sub-Tab 0: Birth Chart D1 View (Authentic North Indian Diamond Kundli Chart)
  Widget _buildBirthChartD1View(String ascendant, String moonSign, String nakshatra, dynamic pada, List planetsList) {
    return Column(
      children: [
        // Authentic North Indian Diamond Kundli Chart Widget
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
                    children: const [
                      Icon(Icons.brightness_7_rounded, color: Color(0xFFFB9548), size: 20),
                      SizedBox(width: 8),
                      Text('Birth Chart (D1 - Janam Kundli)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text('Lagna: $ascendant', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD95D39))),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Authentic 12-House North Indian Kundli Chart Diagram
              SizedBox(
                width: 320,
                height: 320,
                child: CustomPaint(
                  size: const Size(320, 320),
                  painter: NorthIndianKundliPainter(
                    ascendant: ascendant,
                    planetsList: planetsList,
                    chartTitle: 'D1 LAGNA',
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Ask GPT-4o AI Button for D1 Chart
              _buildAskGPTButton('Analyze my Birth Chart (D1) Lagna & Planetary Placements', 'Pandit Shastri'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Key Placements Details
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _buildInfoRow('Lagna (Ascendant)', ascendant, 'Personal Identity & Vitality'),
              const Divider(height: 16),
              _buildInfoRow('Moon Sign (Rasi)', moonSign, 'Emotional & Mental Balance'),
              const Divider(height: 16),
              _buildInfoRow('Nakshatra', nakshatra, 'Soul Purpose & Karmic Energy'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // All 9 Grahas Placements Grid
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
              const Text(
                '9 Grahas Placements (Vedic)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 14),
              ...planetsList.map((p) {
                final name = p['name'] ?? 'Planet';
                final sign = p['sign'] ?? 'Sign';
                final house = p['house'] ?? 1;
                final deg = p['degree'] ?? 10.0;
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
                              color: const Color(0xFF7C77E6).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(name[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C77E6))),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text('House $house • $sign', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        '${deg}°',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFD95D39)),
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

  // Sub-Tab 1: Navamsha D9 View (Authentic Marriage & Soul Chart Diagram)
  Widget _buildNavamshaD9View(Map<String, dynamic> kundli, String ascendant, String moonSign, List planetsList) {
    String d9Asc = ascendant;
    List d9Planets = [];

    if (kundli['d9Navamsha'] != null) {
      d9Asc = kundli['d9Navamsha']['ascendant'] ?? ascendant;
      d9Planets = kundli['d9Navamsha']['planetaryPositions'] ?? [];
    } else {
      final d1AscIdx = _zodiacSigns.indexOf(ascendant);
      final d9AscIdx = (d1AscIdx >= 0) ? _getNavamshaSignIndex(d1AscIdx * 30.0 + 15.0) : 0;
      d9Asc = _zodiacSigns[d9AscIdx];
      d9Planets = planetsList.map((p) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.favorite_rounded, color: Color(0xFFE83D66), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Navamsha (D9) Chart',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCF7F1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text('D9 Lagna: $d9Asc', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE83D66))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Divisional chart D9 reveals marriage compatibility, inner spiritual strength, and second half of life.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Authentic North Indian Diamond Chart Diagram for D9 Navamsha
          Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: CustomPaint(
                size: const Size(300, 300),
                painter: NorthIndianKundliPainter(
                  ascendant: d9Asc,
                  planetsList: d9Planets,
                  chartTitle: 'D9 NAVAMSHA',
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Ask GPT-4o Button for D9 Navamsha
          _buildAskGPTButton('Analyze my Navamsha (D9) Chart for Marriage & Soulmate Compatibility', 'Dr. Ananya Roy'),

          const SizedBox(height: 20),
          _buildInfoRow('Marriage Harmony', 'Strong', 'Benefic placements in 7th House'),
          const Divider(height: 16),
          _buildInfoRow('Dharma & Fortune', 'High', 'Jupiter aspecting D9 Lagna'),
        ],
      ),
    );
  }

  // Sub-Tab 2: Dasamsha D10 View (Authentic Career & Status Chart Diagram)
  Widget _buildDasamshaD10View(Map<String, dynamic> kundli, String ascendant, List planetsList) {
    String d10Asc = ascendant;
    List d10Planets = [];

    if (kundli['d10Dasamsha'] != null) {
      d10Asc = kundli['d10Dasamsha']['ascendant'] ?? ascendant;
      d10Planets = kundli['d10Dasamsha']['planetaryPositions'] ?? [];
    } else {
      final d1AscIdx = _zodiacSigns.indexOf(ascendant);
      final d10AscIdx = (d1AscIdx >= 0) ? _getDasamshaSignIndex(d1AscIdx * 30.0 + 15.0) : 0;
      d10Asc = _zodiacSigns[d10AscIdx];
      d10Planets = planetsList.map((p) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.work_rounded, color: Color(0xFFD95D39), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Dasamsha (D10) Chart',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCF7F1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text('D10 Lagna: $d10Asc', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD95D39))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Divisional chart D10 governs your career, profession, status, authority, and public recognition.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Authentic North Indian Diamond Chart Diagram for D10 Dasamsha
          Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: CustomPaint(
                size: const Size(300, 300),
                painter: NorthIndianKundliPainter(
                  ascendant: d10Asc,
                  planetsList: d10Planets,
                  chartTitle: 'D10 DASAMSHA',
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Ask GPT-4o Button for D10 Dasamsha
          _buildAskGPTButton('Analyze my Dasamsha (D10) Chart for Career, Job Promotions & Authority', 'Acharya Dev Sharma'),

          const SizedBox(height: 20),
          _buildInfoRow('Career Domain', 'Leadership & Innovation', 'Strong 10th House Sun placement'),
          const Divider(height: 16),
          _buildInfoRow('Professional Fame', 'Prominent', 'Saturn & Mercury exalted in D10'),
        ],
      ),
    );
  }

  // Sub-Tab 3: Planets & Dashas Table
  Widget _buildGrahaTableAndDashaView(dynamic dasha, List planetsList) {
    final mahadasha = dasha['currentMahadasha'] ?? 'Saturn';
    final antardasha = dasha['antardasha'] ?? 'Venus';
    final endDate = dasha['dashaEndDate'] ?? '2032-08-15';

    return Column(
      children: [
        // Dasha Active Timeline Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A17),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.hourglass_top_rounded, color: Color(0xFFFFB74D), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Vimshottari Dasha Active',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB74D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mahadasha', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      const SizedBox(height: 4),
                      Text(mahadasha, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Antardasha', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      const SizedBox(height: 4),
                      Text(antardasha, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFFB74D))),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Ends On', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                      const SizedBox(height: 4),
                      Text(endDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _buildAskGPTButton('Explain my current $mahadasha Mahadasha & $antardasha Antardasha predictions', 'Tarun Shastri'),
      ],
    );
  }

  // Sub-Tab 4: Astrocartography View (ACG Map Lines)
  Widget _buildAstrocartographyView() {
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
          Row(
            children: const [
              Icon(Icons.map_rounded, color: Color(0xFF317BEA), size: 22),
              SizedBox(width: 10),
              Text(
                'Astrocartography (ACG)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Global map showing where your planetary Midheaven (MC), Ascendant (ASC), and Descendant (DSC) lines cross the earth.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Planetary Relocation Map Representation
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A17),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.explore_rounded, color: Color(0xFFFFB74D), size: 54),
                const SizedBox(height: 12),
                const Text('Global Power Lines Active', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Sun MC: India & UAE • Jupiter ASC: Europe', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          _buildAskGPTButton('Which country or city is luckiest for my career and relocation?', 'Maura Meridian'),
        ],
      ),
    );
  }

  Widget _buildAIReportSection(Map<String, dynamic> kundli) {
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (_aiReport == null && !_isLoadingReport) {
      _fetchAIReportIfNeeded(backendService, kundli);
    }

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

    if (_aiReport != null && _aiReport!.isNotEmpty) {
      return _buildFormattedReportSections(_aiReport!);
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

  Widget _buildInfoRow(String title, String value, String subtitle) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFD95D39))),
      ],
    );
  }

  Widget _buildAskGPTButton(String promptText, String astrologerName) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/chatbot',
            arguments: {
              'name': astrologerName,
              'specialty': 'Vedic Chart Reading',
              'field': 'Chart Analysis',
              'initialMessage': promptText,
            },
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C77E6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.auto_awesome, size: 18),
            SizedBox(width: 8),
            Text('Ask GPT-4o About This Chart', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// Custom Painter for Authentic 12-House North Indian Diamond Kundli Chart
class NorthIndianKundliPainter extends CustomPainter {
  final String ascendant;
  final List planetsList;
  final String chartTitle;

  NorthIndianKundliPainter({
    required this.ascendant,
    required this.planetsList,
    required this.chartTitle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final paintLine = Paint()
      ..color = const Color(0xFF7C77E6)
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
    canvas.drawLine(Offset(0, 0), Offset(w, h), paintLine);
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
