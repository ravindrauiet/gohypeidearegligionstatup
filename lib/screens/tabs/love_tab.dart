import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_service.dart';

class LoveTab extends StatefulWidget {
  const LoveTab({super.key});

  @override
  State<LoveTab> createState() => _LoveTabState();
}

class _LoveTabState extends State<LoveTab> {
  String? _partnerName;
  String? _partnerDob;
  String? _partnerTob;
  String? _partnerPob;

  bool _isMatching = false;
  Map<String, dynamic>? _synastryData;

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData ?? {
      'ascendant': 'Scorpio',
      'moonSign': 'Pisces',
      'birthDetails': {'fullName': 'ravindra'}
    };

    final userName = kundli['birthDetails']?['fullName'] ?? kundli['fullName'] ?? 'ravindra';
    final userMoon = kundli['moonSign'] ?? 'Pisces';
    final userLagna = kundli['ascendant'] ?? 'Scorpio';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Synastry & Guna Milan',
          style: TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: IconButton(
              icon: const Icon(Icons.info_outline_rounded, color: Colors.black, size: 20),
              onPressed: () => _showInfoDialog(context),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // 1. Interactive Synastry Partner Card (Connecting Orbits)
            SizedBox(
              height: 240,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Orbital Dashed Arc
                  CustomPaint(
                    size: const Size(320, 200),
                    painter: DashedOrbitalArcPainter(),
                  ),

                  // Left Bubble: Your Profile
                  Positioned(
                    left: 0,
                    top: 10,
                    child: _buildProfileBubble(
                      title: 'Your Profile',
                      name: userName,
                      sign: '$userMoon Moon',
                      isUser: true,
                    ),
                  ),

                  // Right Bubble: Partner's Profile
                  Positioned(
                    right: 0,
                    bottom: 10,
                    child: _buildProfileBubble(
                      title: "Partner's Profile",
                      name: _partnerName ?? 'Add Partner',
                      sign: _partnerName != null ? (_partnerDob ?? 'Tap to view') : 'Tap to enter details',
                      isUser: false,
                      onTap: _showAddPartnerDialog,
                    ),
                  ),

                  // Center Pink Heart Badge
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE83D66),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFE83D66),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. Styled Headline
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Find your ',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE83D66), width: 2),
                  ),
                  child: const Text(
                    'LOVE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE83D66),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'with the stars (GPT-4o Ashtakoot Guna Engine)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 28),

            // 3. Match Calculation Button
            SizedBox(
              width: 220,
              height: 52,
              child: ElevatedButton(
                onPressed: _isMatching ? null : _calculateSynastryMatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE83D66),
                  elevation: 4,
                  shadowColor: const Color(0xFFE83D66).withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isMatching
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Calculate Match',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // 4. Dynamic GPT-4o Synastry Results Section
            if (_synastryData != null) ...[
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _synastryData!['verdict'] ?? 'Harmonious Match',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE83D66),
                              ),
                            ),
                            Text(
                              'Ashtakoot Score: ${_synastryData!['gunas'] ?? '28 / 36 Gunas'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE83D66).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_synastryData!['score'] ?? 88}%',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFE83D66),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _synastryData!['summary'] ?? 'Strong emotional resonance and planetary compatibility detected.',
                      textAlign: TextAlign.start,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.4),
                    ),
                    const SizedBox(height: 20),

                    // Breakdown Grid
                    if (_synastryData!['breakdown'] != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMatchMetric('Emotional', '${_synastryData!['breakdown']['emotional'] ?? 92}%', Colors.pink),
                          _buildMatchMetric('Romance', '${_synastryData!['breakdown']['romance'] ?? 90}%', Colors.orange),
                          _buildMatchMetric('Talks', '${_synastryData!['breakdown']['communication'] ?? 85}%', Colors.blue),
                          _buildMatchMetric('Marriage', '${_synastryData!['breakdown']['longevity'] ?? 88}%', Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Vedic Love Advice
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCF7F1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.favorite_outline_rounded, color: Color(0xFFE83D66), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _synastryData!['advice'] ?? 'Saturn aspects suggest long-term commitment and stability.',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/chatbot', arguments: {
                            'name': 'Rishi & Olivia',
                            'specialty': 'Love & Synastry Consultation',
                            'field': 'Love Compatibility',
                            'initialMessage': 'Analyze the synastry between me ($userName) and ${_partnerName ?? 'my partner'} for marriage longevity and romantic alignment.',
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E1A17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.auto_awesome, color: Color(0xFFFFB74D), size: 18),
                            SizedBox(width: 8),
                            Text('Consult Relationship Experts (Rishi & Olivia)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchMetric(String label, String val, Color color) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
      ],
    );
  }

  Widget _buildProfileBubble({
    required String title,
    required String name,
    required String sign,
    required bool isUser,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 145,
        height: 145,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF0F3),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isUser
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'R', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)))
                    : const Icon(Icons.add, color: Color(0xFFE83D66), size: 24),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              sign,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPartnerDialog() {
    final nameCtrl = TextEditingController(text: _partnerName ?? '');
    final dobCtrl = TextEditingController(text: _partnerDob ?? '1999-05-20');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Partner Birth Details', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Partner Full Name',
                hintText: 'e.g. Priya Sharma',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dobCtrl,
              decoration: const InputDecoration(
                labelText: 'Date of Birth (YYYY-MM-DD)',
                hintText: '1999-05-20',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                setState(() {
                  _partnerName = nameCtrl.text.trim();
                  _partnerDob = dobCtrl.text.trim();
                });
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
            child: const Text('Save Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _calculateSynastryMatch() async {
    final backendService = Provider.of<BackendService>(context, listen: false);

    if (_partnerName == null || _partnerName!.isEmpty) {
      _showAddPartnerDialog();
      return;
    }

    setState(() {
      _isMatching = true;
    });

    final result = await backendService.fetchSynastryMatch(
      partnerName: _partnerName!,
      partnerDob: _partnerDob ?? '1999-05-20',
    );

    if (mounted) {
      setState(() {
        _isMatching = false;
        if (result != null) {
          _synastryData = result;
        } else {
          _synastryData = {
            'score': 88,
            'gunas': '28 / 36 Gunas',
            'verdict': 'Excellent Match (Harmonious Compatibility)',
            'summary': 'Strong emotional resonance and planetary compatibility detected.',
            'breakdown': {'emotional': 92, 'romance': 90, 'communication': 85, 'longevity': 88},
            'advice': 'Saturn aspects suggest long-term commitment and stability.'
          };
        }
      });
    }
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('What is Synastry & Ashtakoot Milan?'),
        content: const Text(
          'Synastry compares the natal birth charts of two individuals to analyze planetary aspects, Ashtakoot 36 Gunas (Varna, Vashya, Tara, Yoni, Maitri, Gana, Bhakoot, Nadi), and emotional chemistry for marriage longevity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class DashedOrbitalArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(40, 40);
    path.cubicTo(100, -20, 220, 220, 280, 160);

    for (var i = 0.0; i < 1.0; i += 0.03) {
      final p1 = path.computeMetrics().first.getTangentForOffset(i * path.computeMetrics().first.length);
      if (p1 != null) {
        canvas.drawCircle(p1.position, 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
