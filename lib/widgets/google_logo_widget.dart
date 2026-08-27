import 'package:flutter/material.dart';

class GoogleLogoWidget extends StatelessWidget {
  final double size;

  const GoogleLogoWidget({super.key, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/icons/google_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return CustomPaint(
            size: Size(size, size),
            painter: GoogleLogoVectorPainter(),
          );
        },
      ),
    );
  }
}

// Crisp Vector Painter for Official 4-Color Google 'G' Logo
class GoogleLogoVectorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final double strokeWidth = size.width * 0.22;
    final Rect outerRect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final Paint redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Paint yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Paint greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Paint bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Draw 4 distinct color arcs
    canvas.drawArc(outerRect, -0.6, 1.6, false, redPaint); // Red top arc
    canvas.drawArc(outerRect, 1.0, 1.2, false, yellowPaint); // Yellow left arc
    canvas.drawArc(outerRect, 2.2, 1.3, false, greenPaint); // Green bottom arc
    canvas.drawArc(outerRect, 3.5, 0.9, false, bluePaint); // Blue right arc

    // Draw Blue Horizontal Bar extending to center
    final Paint blueFillPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final Rect barRect = Rect.fromLTWH(
      radius * 0.9,
      radius - strokeWidth / 2,
      radius * 0.95,
      strokeWidth,
    );
    canvas.drawRect(barRect, blueFillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
