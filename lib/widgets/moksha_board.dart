import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game.dart' show MokshaJump;

// ============================================================================
// Geometry
// ============================================================================

/// A cell of the 10×10 grid. `row` 0 is the TOP row, `col` 0 the LEFT column.
@immutable
class MokshaCell {
  final int col;
  final int row;
  const MokshaCell(this.col, this.row);

  @override
  bool operator ==(Object other) => other is MokshaCell && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'MokshaCell($col, $row)';
}

/// Square ⇄ cell mapping for the classic board: square 1 is bottom-left, rows
/// snake left→right then right→left (boustrophedon), so 100 ends up top-left.
class MokshaGeometry {
  MokshaGeometry._();

  static const int side = 10;
  static const int goal = side * side;

  static int clampSquare(int square) => square.clamp(1, goal);

  static MokshaCell cellOf(int square) {
    final i = clampSquare(square) - 1;
    final fromBottom = i ~/ side;
    final inRow = i % side;
    return MokshaCell(fromBottom.isEven ? inRow : side - 1 - inRow, side - 1 - fromBottom);
  }

  static int squareAt(int col, int row) {
    final c = col.clamp(0, side - 1);
    final fromBottom = side - 1 - row.clamp(0, side - 1);
    return fromBottom * side + (fromBottom.isEven ? c : side - 1 - c) + 1;
  }

  /// Centre of a square in unit coordinates (0..1 on both axes).
  static Offset unitCenter(int square) {
    final c = cellOf(square);
    return Offset((c.col + 0.5) / side, (c.row + 0.5) / side);
  }

  /// The square under a point of a board drawn [boardSize] wide, or null when outside.
  static int? squareAtPoint(Offset p, double boardSize) {
    if (boardSize <= 0 || p.dx < 0 || p.dy < 0 || p.dx >= boardSize || p.dy >= boardSize) return null;
    final cell = boardSize / side;
    return squareAt((p.dx / cell).floor(), (p.dy / cell).floor());
  }

  /// A little jump from [a] to [b] (unit coordinates): straight line plus an arc.
  static Offset hop(Offset a, Offset b, double t) {
    final p = Offset.lerp(a, b, t)!;
    return Offset(p.dx, p.dy - math.sin(math.pi * t) * 0.045);
  }

  /// A point on the wavy body of a snake whose head is at [head] and tail at
  /// [tail] (any coordinate space). `t` 0 = head, 1 = tail.
  static Offset snakePoint(Offset head, Offset tail, double t, {required double cell}) {
    final d = tail - head;
    final len = d.distance;
    if (len == 0) return head;
    final normal = Offset(-d.dy / len, d.dx / len);
    final waves = math.max(2, (len / (cell * 1.5)).round());
    final sway = math.sin(math.pi * waves * t) * math.sin(math.pi * t) * cell * 0.42;
    return head + d * t + normal * sway;
  }
}

// ============================================================================
// Palette
// ============================================================================

class MokshaColors {
  MokshaColors._();
  static const maroon = Color(0xFF7A2E1D);
  static const ink = Color(0xFF4A2511);
  static const cream = Color(0xFFFFF6E0);
  static const sand = Color(0xFFFCE3B4);
  static const gold = Color(0xFFF2B705);
  static const goldDeep = Color(0xFF9A6A00);
  static const ladderTint = Color(0xFFE2F1C4);
  static const snakeTint = Color(0xFFFAD7CF);
  static const ladder = Color(0xFF15803D);
  static const snake = Color(0xFFB4532A);

  static const snakes = <Color>[
    Color(0xFF2E9E6B),
    Color(0xFF8E44AD),
    Color(0xFFD9534F),
    Color(0xFF1F8FA8),
    Color(0xFF5B5BD6),
    Color(0xFFC2710C),
  ];

  /// Token colours: index 0 is always "you".
  static const tokens = <Color>[
    Color(0xFFE4572E),
    Color(0xFF2F80ED),
    Color(0xFF059669),
    Color(0xFF8B5CF6),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFF92400E),
  ];

  static Color token(int index) => tokens[index % tokens.length];
}

// ============================================================================
// Board painter
// ============================================================================

class MokshaBoardPainter extends CustomPainter {
  final List<MokshaJump> ladders;
  final List<MokshaJump> snakes;
  final int? highlight;

  MokshaBoardPainter({required this.ladders, required this.snakes, this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final cell = s / MokshaGeometry.side;
    final board = RRect.fromRectAndRadius(Offset.zero & Size(s, s), Radius.circular(cell * 0.45));

    canvas.save();
    canvas.clipRRect(board);

    final ladderFeet = {for (final l in ladders) l.from};
    final snakeHeads = {for (final l in snakes) l.from};

    for (var sq = 1; sq <= MokshaGeometry.goal; sq++) {
      final c = MokshaGeometry.cellOf(sq);
      final rect = Rect.fromLTWH(c.col * cell, c.row * cell, cell, cell);
      Color fill = (c.col + c.row).isEven ? MokshaColors.cream : MokshaColors.sand;
      if (ladderFeet.contains(sq)) fill = MokshaColors.ladderTint;
      if (snakeHeads.contains(sq)) fill = MokshaColors.snakeTint;
      canvas.drawRect(rect, Paint()..color = fill);

      if (sq == MokshaGeometry.goal) {
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const RadialGradient(colors: [Color(0xFFFFF1A8), Color(0xFFF2B705), Color(0xFFE08A00)])
                .createShader(rect),
        );
        _text(canvas, '🕉', rect.center, cell * 0.56, MokshaColors.maroon, center: true);
      } else {
        _text(canvas, '$sq', rect.topLeft + Offset(cell * 0.09, cell * 0.05), cell * 0.3,
            MokshaColors.ink.withValues(alpha: 0.62));
      }
    }

    final grid = Paint()
      ..color = MokshaColors.maroon.withValues(alpha: 0.16)
      ..strokeWidth = 0.6;
    for (var i = 1; i < MokshaGeometry.side; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, s), grid);
      canvas.drawLine(Offset(0, i * cell), Offset(s, i * cell), grid);
    }

    for (final l in ladders) {
      _ladder(canvas, l, s, cell);
    }
    for (var i = 0; i < snakes.length; i++) {
      _snake(canvas, snakes[i], s, cell, MokshaColors.snakes[i % MokshaColors.snakes.length]);
    }

    final hl = highlight;
    if (hl != null) {
      final c = MokshaGeometry.cellOf(hl);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(c.col * cell, c.row * cell, cell, cell).deflate(1.2), Radius.circular(cell * 0.18)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = MokshaColors.maroon,
      );
    }
    canvas.restore();

    canvas.drawRRect(
      board.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = MokshaColors.maroon,
    );
  }

  void _text(Canvas canvas, String text, Offset at, double fontSize, Color color, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(fontSize: fontSize, height: 1, fontWeight: FontWeight.w800, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
    tp.dispose();
  }

  void _ladder(Canvas canvas, MokshaJump l, double s, double cell) {
    final a = MokshaGeometry.unitCenter(l.from) * s;
    final b = MokshaGeometry.unitCenter(l.to) * s;
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    final n = Offset(-dir.dy, dir.dx) * (cell * 0.17);
    final start = a + dir * (cell * 0.12);
    final end = b - dir * (cell * 0.12);

    final outline = Paint()
      ..color = MokshaColors.goldDeep
      ..strokeWidth = cell * 0.13
      ..strokeCap = StrokeCap.round;
    final gold = Paint()
      ..color = MokshaColors.gold
      ..strokeWidth = cell * 0.075
      ..strokeCap = StrokeCap.round;

    final span = (end - start).distance;
    final rungs = math.max(2, (span / (cell * 0.42)).floor());
    for (final paint in [outline, gold]) {
      canvas.drawLine(start + n, end + n, paint);
      canvas.drawLine(start - n, end - n, paint);
      for (var i = 1; i < rungs; i++) {
        final p = Offset.lerp(start, end, i / rungs)!;
        canvas.drawLine(p + n, p - n, paint);
      }
    }
  }

  void _snake(Canvas canvas, MokshaJump l, double s, double cell, Color color) {
    final head = MokshaGeometry.unitCenter(l.from) * s;
    final tail = MokshaGeometry.unitCenter(l.to) * s;
    if ((tail - head).distance == 0) return;
    const steps = 44;
    final pts = [for (var i = 0; i <= steps; i++) MokshaGeometry.snakePoint(head, tail, i / steps, cell: cell)];
    final dark = Color.lerp(color, Colors.black, 0.35)!;
    final light = Color.lerp(color, Colors.white, 0.55)!;
    final width = cell * 0.27;

    for (final pass in [0, 1]) {
      final paint = Paint()
        ..color = pass == 0 ? dark : color
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < steps; i++) {
        final t = i / steps;
        final w = width * (1 - 0.68 * t);
        paint.strokeWidth = pass == 0 ? w + 1.6 : w;
        canvas.drawLine(pts[i], pts[i + 1], paint);
      }
    }
    final dot = Paint()..color = light;
    for (var i = 4; i < steps - 3; i += 4) {
      canvas.drawCircle(pts[i], width * 0.16 * (1 - 0.6 * i / steps), dot);
    }

    // Head with eyes and a friendly little tongue.
    final look = pts[0] - pts[2];
    final ld = look.distance == 0 ? const Offset(0, -1) : look / look.distance;
    final side = Offset(-ld.dy, ld.dx);
    final r = width * 0.78;
    final tongue = Paint()
      ..color = const Color(0xFFE11D48)
      ..strokeWidth = math.max(1, cell * 0.045)
      ..strokeCap = StrokeCap.round;
    final tip = head + ld * (r + cell * 0.2);
    canvas.drawLine(head + ld * r * 0.8, tip, tongue);
    canvas.drawLine(tip, tip + (ld + side) * (cell * 0.07), tongue);
    canvas.drawLine(tip, tip + (ld - side) * (cell * 0.07), tongue);
    canvas.drawCircle(head, r + 0.8, Paint()..color = dark);
    canvas.drawCircle(head, r, Paint()..color = color);
    for (final sgn in [-1.0, 1.0]) {
      final eye = head + ld * (r * 0.25) + side * (r * 0.48 * sgn);
      canvas.drawCircle(eye, r * 0.3, Paint()..color = Colors.white);
      canvas.drawCircle(eye + ld * (r * 0.08), r * 0.15, Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(MokshaBoardPainter old) =>
      old.highlight != highlight || !identical(old.ladders, ladders) || !identical(old.snakes, snakes);
}

// ============================================================================
// Board widget (board + tokens + sparkle)
// ============================================================================

class MokshaToken {
  final String id;
  final String label;
  final Color color;

  /// Centre in unit coordinates (0..1).
  final Offset center;
  final bool active;

  const MokshaToken({
    required this.id,
    required this.label,
    required this.color,
    required this.center,
    this.active = false,
  });
}

class MokshaBoardView extends StatelessWidget {
  final List<MokshaJump> ladders;
  final List<MokshaJump> snakes;
  final List<MokshaToken> tokens;
  final int? highlightSquare;

  /// Golden sparkle around this unit-coordinate point (ladder climbs); [sparkleT] 0..1.
  final Offset? sparkleAt;
  final double sparkleT;
  final ValueChanged<int>? onSquareTap;
  final String semanticLabel;

  const MokshaBoardView({
    super.key,
    required this.ladders,
    required this.snakes,
    required this.tokens,
    this.highlightSquare,
    this.sparkleAt,
    this.sparkleT = 0,
    this.onSquareTap,
    this.semanticLabel = 'Moksha Patam board',
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final s = math.min(box.maxWidth, box.maxHeight);
          final cell = s / MokshaGeometry.side;
          final d = cell * 0.74;
          final ordered = [...tokens.where((t) => !t.active), ...tokens.where((t) => t.active)];
          return Semantics(
            container: true,
            image: true,
            label: semanticLabel,
            hint: onSquareTap == null ? null : 'Tap a ladder or a snake to read its story',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: onSquareTap == null
                  ? null
                  : (d) {
                      final sq = MokshaGeometry.squareAtPoint(d.localPosition, s);
                      if (sq != null) onSquareTap!(sq);
                    },
              child: ExcludeSemantics(
                child: SizedBox(
                  width: s,
                  height: s,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter:
                                MokshaBoardPainter(ladders: ladders, snakes: snakes, highlight: highlightSquare),
                          ),
                        ),
                      ),
                      for (final t in ordered)
                        Positioned(
                          left: t.center.dx * s - d / 2,
                          top: t.center.dy * s - d / 2,
                          width: d,
                          height: d,
                          child: MokshaTokenDot(label: t.label, color: t.color, size: d, active: t.active),
                        ),
                      if (sparkleAt != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _SparklePainter(sparkleAt! * s, sparkleT, cell)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A round player token with an initial.
class MokshaTokenDot extends StatelessWidget {
  final String label;
  final Color color;
  final double size;
  final bool active;
  const MokshaTokenDot({super.key, required this.label, required this.color, this.size = 28, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(color, Colors.white, 0.45)!, color],
        ),
        border: Border.all(color: active ? MokshaColors.gold : Colors.white, width: active ? size * 0.11 : size * 0.07),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: size * 0.16, offset: Offset(0, size * 0.07)),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: size * 0.46, height: 1, fontWeight: FontWeight.w900, color: Colors.white),
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  final Offset at;
  final double t;
  final double cell;
  _SparklePainter(this.at, this.t, this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      at,
      cell * 0.75,
      Paint()
        ..color = MokshaColors.gold.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.3),
    );
    const n = 7;
    for (var i = 0; i < n; i++) {
      final phase = (t * 3 + i / n) % 1.0;
      final angle = i * 2 * math.pi / n + t * math.pi * 2;
      final p = at + Offset(math.cos(angle), math.sin(angle)) * (cell * (0.45 + 0.6 * phase));
      final r = cell * 0.17 * (1 - phase);
      final paint = Paint()..color = Color.lerp(Colors.white, MokshaColors.gold, phase)!.withValues(alpha: 1 - phase);
      final star = Path()
        ..moveTo(p.dx, p.dy - r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r)
        ..close();
      canvas.drawPath(star, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t || old.at != at;
}

// ============================================================================
// Dice
// ============================================================================

class MokshaDice extends StatelessWidget {
  final int value;
  final double size;

  /// Rotation in radians (the tumble).
  final double angle;
  const MokshaDice({super.key, required this.value, this.size = 56, this.angle = 0});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _DicePainter(value.clamp(1, 6))),
      ),
    );
  }
}

class _DicePainter extends CustomPainter {
  final int value;
  _DicePainter(this.value);

  static const _pips = <int, List<Offset>>{
    1: [Offset(0.5, 0.5)],
    2: [Offset(0.28, 0.28), Offset(0.72, 0.72)],
    3: [Offset(0.26, 0.26), Offset(0.5, 0.5), Offset(0.74, 0.74)],
    4: [Offset(0.28, 0.28), Offset(0.72, 0.28), Offset(0.28, 0.72), Offset(0.72, 0.72)],
    5: [Offset(0.27, 0.27), Offset(0.73, 0.27), Offset(0.5, 0.5), Offset(0.27, 0.73), Offset(0.73, 0.73)],
    6: [
      Offset(0.28, 0.25),
      Offset(0.72, 0.25),
      Offset(0.28, 0.5),
      Offset(0.72, 0.5),
      Offset(0.28, 0.75),
      Offset(0.72, 0.75),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final body = RRect.fromRectAndRadius(Offset.zero & Size(s, s), Radius.circular(s * 0.22));
    canvas.drawRRect(body.shift(Offset(0, s * 0.05)), Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFFFE9C2)],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = MokshaColors.goldDeep.withValues(alpha: 0.6),
    );
    final pip = Paint()..color = value == 1 ? const Color(0xFFD62828) : MokshaColors.maroon;
    for (final p in _pips[value]!) {
      canvas.drawCircle(Offset(p.dx * s, p.dy * s), s * (value == 1 ? 0.13 : 0.09), pip);
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) => old.value != value;
}
