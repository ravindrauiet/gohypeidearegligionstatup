import 'package:flutter/material.dart';

class LoveTab extends StatefulWidget {
  const LoveTab({super.key});

  @override
  State<LoveTab> createState() => _LoveTabState();
}

class _LoveTabState extends State<LoveTab> {
  String? partnerName;
  bool _isMatching = false;
  int? _compatibilityScore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Synastry',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // 1. Interactive Synastry Partner Card (Matching Image 3)
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
                      name: 'ravindra',
                      sign: 'Taurus Moon',
                      isUser: true,
                    ),
                  ),

                  // Right Bubble: Partner's Profile
                  Positioned(
                    right: 0,
                    bottom: 10,
                    child: _buildProfileBubble(
                      title: "Partner's profile",
                      name: partnerName ?? 'Add Partner',
                      sign: partnerName != null ? 'Scorpio Sun' : 'Tap to select',
                      isUser: false,
                      onTap: _showAddPartnerDialog,
                    ),
                  ),

                  // Center Pink Heart Badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE83D66),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFE83D66),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 2. Styled Headline (Matching Image 3)
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
            const SizedBox(height: 6),
            const Text(
              'with the stars',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 36),

            // 3. Pink Match Button (Matching Image 3)
            SizedBox(
              width: 180,
              height: 52,
              child: ElevatedButton(
                onPressed: _isMatching ? null : _calculateMatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE83D66),
                  elevation: 4,
                  shadowColor: const Color(0xFFE83D66).withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isMatching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Match',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            if (_compatibilityScore != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Synastry Compatibility: $_compatibilityScore%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE83D66),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Harmonious Moon-Venus sextile! Deep emotional understanding and mutual spark detected in your natal transits.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/chatbot'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text('Ask AI Love Assistant', style: TextStyle(color: Colors.white)),
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
              color: Colors.black.withOpacity(0.05),
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
                    ? const Text('R', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)))
                    : const Icon(Icons.add, color: Color(0xFFE83D66), size: 24),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 2),
            Text(
              sign,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPartnerDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter Partner Name'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Partner Full Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                setState(() {
                  partnerName = textController.text.trim();
                });
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
            child: const Text('Save Partner', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _calculateMatch() {
    setState(() {
      _isMatching = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _isMatching = false;
        _compatibilityScore = 88;
      });
    });
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('What is Synastry?'),
        content: const Text(
          'Synastry compares the natal birth charts of two individuals to analyze planetary aspects, emotional chemistry, long-term marriage potential, and relationship harmony.',
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

// Dashed Arc Painter for connecting profiles
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

    // Render dashed line effect
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
