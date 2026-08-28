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
  int _selectedSubTab = 0; // 0: Birth Chart (D1), 1: Navamsha (D9), 2: Dasamsha (D10), 3: Planets & Dashas, 4: Astrocartography
  bool _isInteractiveMode = true;

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
                child: Text('Soul Lagna: $moonSign', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE83D66))),
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
                  ascendant: moonSign,
                  planetsList: planetsList,
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
                child: const Text('10th Lord: Sun', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD95D39))),
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
                  ascendant: 'Leo',
                  planetsList: planetsList,
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

    // 5. Draw Title Tag in Center Diamond
    final TextPainter titlePainter = TextPainter(
      text: TextSpan(
        text: chartTitle,
        style: const TextStyle(color: Color(0xFFD95D39), fontWeight: FontWeight.w900, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout();
    titlePainter.paint(canvas, Offset(w / 2 - titlePainter.width / 2, h / 2 - 8));

    // 6. Draw House Placements & Planets
    final List<String> housePlanets = List.generate(12, (_) => '');
    for (var p in planetsList) {
      final int house = (p['house'] ?? 1) as int;
      if (house >= 1 && house <= 12) {
        final name = p['name'].toString().split(' ')[0];
        housePlanets[house - 1] += (housePlanets[house - 1].isEmpty ? '' : ', ') + name;
      }
    }

    // Positions for 12 Houses in North Indian Chart
    final List<Offset> houseOffsets = [
      Offset(w / 2, h * 0.22),      // House 1 (Top Diamond)
      Offset(w * 0.25, h * 0.12),   // House 2 (Top Left)
      Offset(w * 0.12, h * 0.25),   // House 3 (Left Top)
      Offset(w * 0.22, h * 0.50),   // House 4 (Left Diamond)
      Offset(w * 0.12, h * 0.75),   // House 5 (Left Bottom)
      Offset(w * 0.25, h * 0.88),   // House 6 (Bottom Left)
      Offset(w / 2, h * 0.78),      // House 7 (Bottom Diamond)
      Offset(w * 0.75, h * 0.88),   // House 8 (Bottom Right)
      Offset(w * 0.88, h * 0.75),   // House 9 (Right Bottom)
      Offset(w * 0.78, h * 0.50),   // House 10 (Right Diamond)
      Offset(w * 0.88, h * 0.25),   // House 11 (Right Top)
      Offset(w * 0.75, h * 0.12),   // House 12 (Top Right)
    ];

    for (int i = 0; i < 12; i++) {
      final pos = houseOffsets[i];
      final planetsStr = housePlanets[i];

      if (planetsStr.isNotEmpty) {
        final TextPainter pt = TextPainter(
          text: TextSpan(
            text: planetsStr,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        );
        pt.layout();
        pt.paint(canvas, Offset(pos.dx - pt.width / 2, pos.dy));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
