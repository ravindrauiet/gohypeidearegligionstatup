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
  int _selectedSubTab = 0; // 0: Birth Chart, 1: Solar Return, 2: Astrocartography
  bool _isInteractiveMode = true;
  String _selectedView = 'Default';

  final List<String> _subTabs = ['Birth Chart', 'Solar Return', 'Astrocartography'];

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData ?? {
      'ascendant': 'Aries',
      'sunSign': 'Leo',
      'moonSign': 'Taurus',
      'nakshatra': 'Rohini',
      'birthDetails': {'fullName': 'ravindra'}
    };

    final name = kundli['birthDetails']?['fullName'] ?? 'ravindra';

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
                  'Hi, Good Night',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w400),
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
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black, size: 20),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Wallet badge ₹0
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6B1A3A),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  '₹0',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // 2. Title Header (Matching Image 2)
            RichText(
              text: const TextSpan(
                style: TextStyle(fontFamily: 'Roboto', fontSize: 32, height: 1.15),
                children: [
                  TextSpan(
                    text: 'A map of ',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: 'who you are',
                    style: TextStyle(
                      color: Color(0xFFD95D39),
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. Mode Controls Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Interactive mode switch pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Interactive mode',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      const SizedBox(width: 8),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: _isInteractiveMode,
                          activeColor: Colors.grey.shade700,
                          activeTrackColor: Colors.grey.shade400,
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

                // View Selector Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedView,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black, size: 18),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 4. Interactive Zodiac Birth Chart Wheel (Matching Image 2)
            Center(
              child: GestureDetector(
                onTapUp: (details) {
                  if (_isInteractiveMode) {
                    _showPlanetDetailsSheet(context);
                  }
                },
                child: SizedBox(
                  width: 340,
                  height: 340,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(340, 340),
                        painter: ZodiacChartWheelPainter(),
                      ),
                      // Center Logo Circle
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.brightness_3, color: Color(0xFFE83D66), size: 16),
                                  Icon(Icons.flare_rounded, color: Color(0xFFFB9548), size: 16),
                                ],
                              ),
                              Icon(Icons.blur_on_rounded, color: Color(0xFF7C77E6), size: 16),
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

            // Kundli Chart Breakdown Summary
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
                    'Planetary Placements Summary',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  _buildPlacementRow('Sun ☉', 'Leo (5th House)', 'Creative Leadership & Vitality'),
                  const Divider(height: 16),
                  _buildPlacementRow('Moon ☽', 'Taurus (2nd House)', 'Emotional Balance & Stability'),
                  const Divider(height: 16),
                  _buildPlacementRow('Mars ♂', 'Pisces (12th House)', 'Intuitive Energy & Drive'),
                  const Divider(height: 16),
                  _buildPlacementRow('Saturn ♄', 'Taurus (2nd House)', 'Disciplined Financial Growth'),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildPlacementRow(String planet, String placement, String effect) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(planet, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(placement, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        Flexible(
          child: Text(
            effect,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7C77E6)),
          ),
        ),
      ],
    );
  }

  void _showPlanetDetailsSheet(BuildContext context) {
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
                    child: const Text('♂', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Mars in Pisces', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                      Text('12th House • 14° 22\'', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Mars sextiles natal Saturn today, reducing resistance and granting focused determination for creative & spiritual pursuits.',
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
                  child: const Text('Ask AI About Mars Transit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Zodiac Wheel Custom Painter matching image 2
class ZodiacChartWheelPainter extends CustomPainter {
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
      ..color = const Color(0xFF7C77E6).withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.45, centerHousePaint);

    // 4. House Radial Lines & Zodiac Signs
    final linePaint = Paint()
      ..color = const Color(0xFF7C77E6).withOpacity(0.5)
      ..strokeWidth = 1.2;

    final signs = [
      'ARIES', 'PISCES', 'AQUARIUS', 'CAPRICORN',
      'SAGITTARIUS', 'SCORPIO', 'LIBRA', 'VIRGO',
      'LEO', 'CANCER', 'GEMINI', 'TAURUS'
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
          fontSize: 8.5,
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
        text: '${((i + 9) % 12) + 1}',
        style: const TextStyle(
          color: Color(0xFF7C77E6),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(houseX - textPainter.width / 2, houseY - textPainter.height / 2),
      );

      // Draw Planet Glyphs in middle ring
      if (i % 2 == 0 || i == 3 || i == 7) {
        final planetRadius = radius * 0.62;
        final planetX = center.dx + planetRadius * cos(labelAngle + 0.1);
        final planetY = center.dy + planetRadius * sin(labelAngle + 0.1);

        textPainter.text = TextSpan(
          text: planetGlyphs[i % planetGlyphs.length],
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
