import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_service.dart';

class ChartTab extends StatefulWidget {
  const ChartTab({super.key});

  @override
  State<ChartTab> createState() => _ChartTabState();
}

class _ChartTabState extends State<ChartTab> {
  int _selectedSubTab = 0; // 0: Birth Chart (D1), 1: Navamsha (D9), 2: Dasamsha (D10), 3: Graha Table & Dashas, 4: Astrocartography
  bool _isInteractiveMode = true;
  String _selectedView = 'Vedic Sidereal';

  final List<String> _subTabs = [
    'Birth Chart (D1)',
    'Navamsha (D9)',
    'Dasamsha (D10)',
    'Planets & Dashas',
    'Astrocartography'
  ];

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData ?? {
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
    };

    final name = kundli['birthDetails']?['fullName'] ?? kundli['fullName'] ?? 'ravindra';
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
                const Text(
                  'Personal Vedic Kundli',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
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
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, color: Color(0xFF7C77E6), size: 18),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A17),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFB74D), size: 14),
                SizedBox(width: 6),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Horizontal Subtabs Pills
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
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1E1A17) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _subTabs[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // 2. Title Header
            RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 28, height: 1.15),
                children: [
                  const TextSpan(
                    text: 'A map of ',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: _subTabs[_selectedSubTab],
                    style: const TextStyle(
                      color: Color(0xFFD95D39),
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Mode Controls Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Interactive mode switch pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Interactive mode',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          value: _isInteractiveMode,
                          activeColor: const Color(0xFF7C77E6),
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

                // System View Badge
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

            // 3. Dynamic Chart Content Switcher
            _buildSelectedSubTabContent(ascendant, moonSign, nakshatra, pada, dasha, planetsList),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSubTabContent(String ascendant, String moonSign, String nakshatra, dynamic pada, dynamic dasha, List planetsList) {
    switch (_selectedSubTab) {
      case 0:
        return _buildBirthChartD1View(ascendant, moonSign, nakshatra, pada, planetsList);
      case 1:
        return _buildNavamshaD9View(ascendant, moonSign, planetsList);
      case 2:
        return _buildDasamshaD10View(ascendant, planetsList);
      case 3:
        return _buildGrahaTableAndDashaView(dasha, planetsList);
      case 4:
        return _buildAstrocartographyView();
      default:
        return _buildBirthChartD1View(ascendant, moonSign, nakshatra, pada, planetsList);
    }
  }

  // Sub-Tab 0: Birth Chart D1 View
  Widget _buildBirthChartD1View(String ascendant, String moonSign, String nakshatra, dynamic pada, List planetsList) {
    return Column(
      children: [
        // Interactive Zodiac Birth Chart Wheel
        Center(
          child: GestureDetector(
            onTapUp: (details) {
              if (_isInteractiveMode) {
                _showPlanetDetailsSheet(context, planetsList.isNotEmpty ? planetsList[0] : null);
              }
            },
            child: SizedBox(
              width: 320,
              height: 320,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(320, 320),
                    painter: ZodiacChartWheelPainter(ascendant: ascendant),
                  ),
                  // Center Lagna Badge
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'LAGNA',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          Text(
                            ascendant,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF7C77E6)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Birth Placements Summary Card
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Birth Chart Placements',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Pada $pada',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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

  // Sub-Tab 1: Navamsha D9 View
  Widget _buildNavamshaD9View(String ascendant, String moonSign, List planetsList) {
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
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Color(0xFFE83D66), size: 22),
              SizedBox(width: 10),
              Text(
                'Navamsha (D9) Chart',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Divisional chart D9 reveals marriage compatibility, inner spiritual strength, and second half of life.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: const Color(0xFFFCF7F1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF7C77E6), width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF7C77E6), size: 120),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('D9 NAVAMSHA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
                      const SizedBox(height: 4),
                      Text('Soul Lagna: $moonSign', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFD95D39))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow('Marriage Harmony', 'Strong', 'Benefic placements in 7th House'),
          const Divider(height: 16),
          _buildInfoRow('Dharma & Fortune', 'High', 'Jupiter aspecting D9 Lagna'),
        ],
      ),
    );
  }

  // Sub-Tab 2: Dasamsha D10 View
  Widget _buildDasamshaD10View(String ascendant, List planetsList) {
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
          const Row(
            children: [
              Icon(Icons.work_rounded, color: Color(0xFFFFB74D), size: 22),
              SizedBox(width: 10),
              Text(
                'Dasamsha (D10) Chart',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Divisional chart D10 governs your career, profession, status, authority, and public recognition.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: const Color(0xFFFCF7F1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFB74D), width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.workspace_premium, color: Color(0xFFFFB74D), size: 120),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('D10 DASAMSHA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
                      const SizedBox(height: 4),
                      Text('10th House Lord: $ascendant', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF7C77E6))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow('Career Domain', 'Leadership & Innovation', 'Strong 10th House Sun placement'),
          const Divider(height: 16),
          _buildInfoRow('Professional Fame', 'Prominent', 'Saturn & Mercury exalted in D10'),
        ],
      ),
    );
  }

  // Sub-Tab 3: Graha Table & Dashas View
  Widget _buildGrahaTableAndDashaView(dynamic dasha, List planetsList) {
    final mahadasha = dasha['currentMahadasha'] ?? 'Saturn';
    final antardasha = dasha['antardasha'] ?? 'Venus';
    final dashaEnd = dasha['dashaEndDate'] ?? '2032-08-15';

    return Column(
      children: [
        // Active Vimshottari Dasha Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A17),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vimshottari Dasha Timeline',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Icon(Icons.hourglass_bottom_rounded, color: Color(0xFFFFB74D), size: 20),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MAHADASHA', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(mahadasha.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFFFB74D))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ANTARDASHA', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(antardasha.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF7C77E6))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Active period valid until: $dashaEnd',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Graha Table
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
                'Vedic Planetary Positions Table',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('Planet', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Sign', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('House', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Degree', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: planetsList.map<DataRow>((p) {
                    return DataRow(cells: [
                      DataCell(Text(p['name']?.toString() ?? 'Planet', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(p['sign']?.toString() ?? 'Sign')),
                      DataCell(Text('H${p['house']}')),
                      DataCell(Text('${p['degree']}°')),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Sub-Tab 4: Astrocartography View
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
          const Row(
            children: [
              Icon(Icons.map_rounded, color: Color(0xFF7C77E6), size: 22),
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
          Center(
            child: Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1A17),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.public, color: Colors.white24, size: 160),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.explore_rounded, color: Color(0xFFFFB74D), size: 36),
                      SizedBox(height: 8),
                      Text(
                        'Global Power Lines Active',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Sun MC: India & UAE • Jupiter ASC: Europe',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, String description) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF7C77E6), fontWeight: FontWeight.w700)),
          ],
        ),
        Flexible(
          child: Text(
            description,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  void _showPlanetDetailsSheet(BuildContext context, dynamic planet) {
    final planetName = planet != null ? planet['name'] : 'Sun ☉';
    final sign = planet != null ? planet['sign'] : 'Gemini';
    final house = planet != null ? planet['house'] : 8;
    final degree = planet != null ? planet['degree'] : 29.5;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFCF7F1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF7C77E6),
                      shape: BoxShape.circle,
                    ),
                    child: Text(planetName.toString()[0], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$planetName in $sign', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                      Text('House $house • $degree°', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '$planetName in $sign in House $house grants enhanced intuition, personal empowerment, and deep cosmic insight.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/chatbot');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: Text('Ask AI About $planetName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Zodiac Wheel Custom Painter with dynamic Ascendant
class ZodiacChartWheelPainter extends CustomPainter {
  final String ascendant;

  ZodiacChartWheelPainter({required this.ascendant});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Outer Zodiac Ring (Purple #7C77E6)
    final outerRingPaint = Paint()
      ..color = const Color(0xFF7C77E6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerRingPaint);

    // 2. Inner White Circle
    final innerWhitePaint = Paint()
      ..color = const Color(0xFFFCF7F1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.78, innerWhitePaint);

    // 3. Center House Circle
    final centerHousePaint = Paint()
      ..color = const Color(0xFF7C77E6).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.45, centerHousePaint);

    // 4. House Radial Lines & Zodiac Signs
    final linePaint = Paint()
      ..color = const Color(0xFF7C77E6).withValues(alpha: 0.5)
      ..strokeWidth = 1.2;

    final signs = [
      'ARIES', 'TAURUS', 'GEMINI', 'CANCER',
      'LEO', 'VIRGO', 'LIBRA', 'SCORPIO',
      'SAGITTARIUS', 'CAPRICORN', 'AQUARIUS', 'PISCES'
    ];

    final planetGlyphs = ['☉', '☽', '♂', '☿', '♃', '♀', '♄', '☊', '☋'];

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * pi / 180;
      final outerX = center.dx + radius * cos(angle);
      final outerY = center.dy + radius * sin(angle);

      canvas.drawLine(center, Offset(outerX, outerY), linePaint);

      // Draw Zodiac Sign Text in Outer Purple Ring
      final labelAngle = ((i * 30 - 75) * pi / 180);
      final textRadius = radius * 0.88;
      final textX = center.dx + textRadius * cos(labelAngle);
      final textY = center.dy + textRadius * sin(labelAngle);

      textPainter.text = TextSpan(
        text: signs[i],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(textX - textPainter.width / 2, textY - textPainter.height / 2),
      );

      // Draw House Numbers (1 to 12)
      final houseTextRadius = radius * 0.38;
      final houseX = center.dx + houseTextRadius * cos(labelAngle);
      final houseY = center.dy + houseTextRadius * sin(labelAngle);

      textPainter.text = TextSpan(
        text: 'H${i + 1}',
        style: const TextStyle(
          color: Color(0xFF7C77E6),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(houseX - textPainter.width / 2, houseY - textPainter.height / 2),
      );

      // Draw Planet Glyphs in middle ring
      if (i < planetGlyphs.length) {
        final planetRadius = radius * 0.62;
        final planetX = center.dx + planetRadius * cos(labelAngle + 0.1);
        final planetY = center.dy + planetRadius * sin(labelAngle + 0.1);

        textPainter.text = TextSpan(
          text: planetGlyphs[i],
          style: TextStyle(
            color: _getPlanetColor(i),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(planetX - textPainter.width / 2, planetY - textPainter.height / 2),
        );
      }
    }
  }

  Color _getPlanetColor(int index) {
    final colors = [
      const Color(0xFFD95D39),
      const Color(0xFF7C77E6),
      const Color(0xFFE83D66),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
    ];
    return colors[index % colors.length];
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
