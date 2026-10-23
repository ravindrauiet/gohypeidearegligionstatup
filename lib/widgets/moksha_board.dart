import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game.dart' show MokshaJump;
import '../theme/app_theme.dart';

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

/// Restrained board palette built on the app tokens: white and pale-grey
/// squares, hairline grid, deep-indigo ink, gold ladders, muted snakes.
class MokshaColors {
  MokshaColors._();

  /// Primary board ink (strokes, roll button). Kept as `maroon` for callers.
  static const maroon = AppColors.cosmic;
  static const ink = AppColors.textSecondary;
  static const cream = AppColors.surface;
  static const sand = Color(0xFFF6F5FA);
  static const gold = AppColors.gold;
  static const goldDeep = Color(0xFFB7791F);
  static const ladderTint = Color(0xFFEFF8F2);
  static const snakeTint = Color(0xFFFDF0F2);
  static const ladder = AppColors.success;
  static const snake = AppColors.danger;

  static const snakes = <Color>[
    Color(0xFF2B8F6E),
    Color(0xFF4A4EA3),
    Color(0xFFB8537F),
    Color(0xFF5F6B7D),
    Color(0xFFC84B3A),
    Color(0xFF8C6146),
  ];

  /// Token colours: index 0 is always "you".
  static const tokens = <Color>[
    AppColors.primary,
    Color(0xFF4F46E5),
    Color(0xFF16A34A),
    Color(0xFFB8537F),
    Color(0xFF0E7490),
    Color(0xFF8C6146),
    Color(0xFF5F6B7D),
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
    final board = RRect.fromRectAndRadius(Offset.zero & Size(s, s), const Radius.circular(AppRadius.lg));

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
        canvas.drawRect(rect, Paint()..color = MokshaColors.gold.withValues(alpha: 0.22));
        _text(canvas, 'ॐ', rect.center, cell * 0.5, MokshaColors.goldDeep, center: true);
      } else {
        _text(canvas, '$sq', rect.topLeft + Offset(cell * 0.08, cell * 0.06), cell * 0.24, AppColors.textTertiary);
      }
    }

    final grid = Paint()
      ..color = AppColors.border
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
          ..strokeWidth = 1.6
          ..color = MokshaColors.maroon,
      );
    }
    canvas.restore();

    canvas.drawRRect(
      board.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );
  }

  void _text(Canvas canvas, String text, Offset at, double fontSize, Color color, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(fontSize: fontSize, height: 1, fontWeight: FontWeight.w600, color: color)),
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
    final n = Offset(-dir.dy, dir.dx) * (cell * 0.16);
    final start = a + dir * (cell * 0.12);
    final end = b - dir * (cell * 0.12);

    final rail = Paint()
      ..color = MokshaColors.goldDeep
      ..strokeWidth = math.max(1.4, cell * 0.06)
      ..strokeCap = StrokeCap.round;
    final rung = Paint()
      ..color = MokshaColors.goldDeep.withValues(alpha: 0.8)
      ..strokeWidth = math.max(1.0, cell * 0.04)
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start + n, end + n, rail);
    canvas.drawLine(start - n, end - n, rail);
    final span = (end - start).distance;
    final rungs = math.max(2, (span / (cell * 0.42)).floor());
    for (var i = 1; i < rungs; i++) {
      final p = Offset.lerp(start, end, i / rungs)!;
      canvas.drawLine(p + n, p - n, rung);
    }
  }

  void _snake(Canvas canvas, MokshaJump l, double s, double cell, Color color) {
    final head = MokshaGeometry.unitCenter(l.from) * s;
    final tail = MokshaGeometry.unitCenter(l.to) * s;
    if ((tail - head).distance == 0) return;
    const steps = 44;
    final pts = [for (var i = 0; i <= steps; i++) MokshaGeometry.snakePoint(head, tail, i / steps, cell: cell)];
    final width = cell * 0.2;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < steps; i++) {
      final t = i / steps;
      paint.strokeWidth = math.max(1.2, width * (1 - 0.75 * t));
      canvas.drawLine(pts[i], pts[i + 1], paint);
    }

    // Head: a simple disc with two small eyes.
    final look = pts[0] - pts[2];
    final ld = look.distance == 0 ? const Offset(0, -1) : look / look.distance;
    final side = Offset(-ld.dy, ld.dx);
    final r = width * 0.75;
    canvas.drawCircle(head, r, Paint()..color = color);
    for (final sgn in [-1.0, 1.0]) {
      final eye = head + ld * (r * 0.25) + side * (r * 0.45 * sgn);
      canvas.drawCircle(eye, r * 0.18, Paint()..color = Colors.white);
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
                            painter: MokshaBoardPainter(ladders: ladders, snakes: snakes, highlight: highlightSquare),
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
        color: color,
        border: Border.all(color: Colors.white, width: math.max(1.5, size * (active ? 0.1 : 0.07))),
        boxShadow: [
          if (active) BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.9), spreadRadius: 1.2),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18), blurRadius: size * 0.14, offset: Offset(0, size * 0.05)),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: size * 0.44, height: 1, fontWeight: FontWeight.w700, color: Colors.white),
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
    canvas.drawRRect(body.shift(Offset(0, s * 0.04)), Paint()..color = Colors.black.withValues(alpha: 0.12));
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );
    final pip = Paint()..color = value == 1 ? AppColors.primary : AppColors.textPrimary;
    for (final p in _pips[value]!) {
      canvas.drawCircle(Offset(p.dx * s, p.dy * s), s * (value == 1 ? 0.12 : 0.08), pip);
    }
  }

  @override
  bool shouldRepaint(_DicePainter old) => old.value != value;
}
