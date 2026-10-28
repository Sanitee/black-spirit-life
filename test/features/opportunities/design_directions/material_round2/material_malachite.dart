import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Native material study. The host owns every label, icon and interaction.
class MalachitePaint extends CustomPainter {
  const MalachitePaint({required this.part, this.selected = false})
    : assert(
        part == 'background' ||
            part == 'rail' ||
            part == 'card' ||
            part == 'button',
      );

  final String part;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    switch (part) {
      case 'background':
        _background(canvas, size);
      case 'rail':
        _slab(canvas, size, rail: true);
      case 'card':
        _slab(canvas, size, rail: false);
      case 'button':
        _button(canvas, size);
    }
  }

  static Path _cut(Rect rect, double corner) => Path()
    ..moveTo(rect.left + corner, rect.top)
    ..lineTo(rect.right - corner, rect.top)
    ..lineTo(rect.right, rect.top + corner)
    ..lineTo(rect.right, rect.bottom - corner)
    ..lineTo(rect.right - corner, rect.bottom)
    ..lineTo(rect.left + corner, rect.bottom)
    ..lineTo(rect.left, rect.bottom - corner)
    ..lineTo(rect.left, rect.top + corner)
    ..close();

  static Paint _wash(Rect rect, List<Color> colors, {List<double>? stops}) =>
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: stops,
        ).createShader(rect);

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      _wash(rect, const [
        Color(0xFF16372B),
        Color(0xFF0C211B),
        Color(0xFF06120F),
      ]),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.9, -1),
          radius: 1.1,
          colors: [Color(0x30517855), Color(0x00517855)],
        ).createShader(rect),
    );
    // The mineral is exposed at the frame; text and controls sit on calm ground.
    final margin = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRect(rect.deflate(24)),
    );
    canvas.save();
    canvas.clipPath(margin);
    _veins(canvas, rect, opacity: .32);
    canvas.restore();
    canvas.drawLine(
      const Offset(28, 1),
      Offset(size.width - 28, 1),
      _wash(rect, const [
        Color(0x20C4B885),
        Color(0xB9D6C792),
        Color(0x00C4B885),
      ])..strokeWidth = 2,
    );
  }

  void _slab(Canvas canvas, Size size, {required bool rail}) {
    final rect = Offset.zero & size;
    final corner = rail ? 15.0 : 13.0;
    final edge = _cut(rect, corner);
    final faceRect = rect.deflate(8);
    final face = _cut(faceRect, math.max(3, corner - 7));

    canvas.drawShadow(
      edge.shift(const Offset(0, 4)),
      const Color(0xFF000805),
      13,
      false,
    );
    canvas.drawPath(
      edge.shift(const Offset(0, 6)),
      _wash(rect, const [Color(0xFF11231A), Color(0xFF010A06)]),
    );
    canvas.drawPath(
      edge,
      _wash(
        rect,
        const [
          Color(0xFF7C7851),
          Color(0xFF2D5D40),
          Color(0xFF14291D),
          Color(0xFF4D583B),
        ],
        stops: const [0, .24, .75, 1],
      ),
    );

    final mineral = _cut(rect.deflate(1.3), corner - 1);
    canvas.drawPath(
      mineral,
      _wash(
        rect,
        const [
          Color(0xFF39825B),
          Color(0xFF184E35),
          Color(0xFF2D7250),
          Color(0xFF113D29),
        ],
        stops: const [0, .3, .64, 1],
      ),
    );
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, mineral, face));
    _veins(canvas, rect, opacity: .85);
    // A broad, reflected light runs across the polished rim, not over the text.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-1, -.7),
          end: Alignment(1, .6),
          colors: [
            Color(0x006ECE9A),
            Color(0x009DE6B3),
            Color(0x5DBFE9BD),
            Color(0x009DE6B3),
            Color(0x006ECE9A),
          ],
          stops: [0, .18, .24, .33, 1],
        ).createShader(rect),
    );
    canvas.restore();

    canvas.drawPath(
      face,
      _wash(
        faceRect,
        rail
            ? const [Color(0xFF15352A), Color(0xFF10281F), Color(0xFF0B1E17)]
            : const [Color(0xFF183C2F), Color(0xFF102C22), Color(0xFF0B2119)],
      ),
    );
    canvas.drawPath(
      face,
      _wash(rect, const [
          Color(0xFFC9C293),
          Color(0xFF6E7951),
          Color(0xFF374C31),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawPath(
      edge,
      _wash(rect, const [
          Color(0xDDE6D9A7),
          Color(0x60646A43),
          Color(0x803D4E33),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );

    // Fine champagne inlay follows the two clipped upper corners.
    final seam = Paint()
      ..color = const Color(0xC8D9CA94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(
      Path()
        ..moveTo(1.4, corner + 9)
        ..lineTo(1.4, corner)
        ..lineTo(corner, 1.4)
        ..lineTo(corner + 26, 1.4),
      seam,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width - corner - 18, 1.4)
        ..lineTo(size.width - corner, 1.4)
        ..lineTo(size.width - 1.4, corner)
        ..lineTo(size.width - 1.4, corner + 5),
      seam..color = const Color(0x777F9666),
    );
    canvas.drawLine(
      Offset(corner + 3, size.height + 3),
      Offset(size.width - corner - 3, size.height + 3),
      Paint()
        ..color = const Color(0x70345031)
        ..strokeWidth = 1,
    );
  }

  void _button(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = _cut(rect, 6);
    final faceRect = rect.deflate(2);
    final face = _cut(faceRect, 4);
    canvas.drawShadow(edge, const Color(0xFF000704), 6, false);
    canvas.drawPath(
      edge.shift(const Offset(0, 3)),
      Paint()
        ..color = selected ? const Color(0xFF40351E) : const Color(0xFF020D07),
    );
    canvas.drawPath(
      edge,
      _wash(
        rect,
        selected
            ? const [Color(0xFFF6E9BB), Color(0xFFAE9561), Color(0xFF67572F)]
            : const [Color(0xFF728468), Color(0xFF38553D), Color(0xFF1B3325)],
      ),
    );
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: selected
              ? const [Color(0xFFE7D7A6), Color(0xFFD5BF89), Color(0xFFB9A16B)]
              : const [Color(0xFF244C39), Color(0xFF193C2C), Color(0xFF102B1D)],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(face);
    if (selected) {
      final brush = math.Random(37);
      for (var y = 3.0; y < size.height - 2; y += 2) {
        canvas.drawLine(
          Offset(2 + brush.nextDouble() * 8, y),
          Offset(size.width - 2 - brush.nextDouble() * 12, y),
          Paint()
            ..color = const Color(0x12FFFFD3)
            ..strokeWidth = .6,
        );
      }
    } else {
      // Only the outer few pixels of dark buttons carry mineral banding.
      canvas.clipPath(
        Path.combine(PathOperation.difference, face, _cut(rect.deflate(5), 2)),
      );
      _veins(canvas, rect, opacity: .3);
    }
    canvas.restore();
    canvas.drawLine(
      const Offset(7, 1),
      Offset(size.width - 7, 1),
      Paint()
        ..color = selected ? const Color(0xFFEDE4B5) : const Color(0xA899B58A)
        ..strokeWidth = 1,
    );
  }

  void _veins(Canvas canvas, Rect rect, {required double opacity}) {
    // Malachite's nested bands flow in parallel; no random marks cross a label.
    final sx = math.max(100.0, rect.width);
    final sy = math.max(90.0, rect.height);
    final count = (sy / 4).ceil() + 40;
    for (var band = -20; band < count; band++) {
      final path = Path();
      for (var step = 0; step <= 70; step++) {
        final x = rect.left - 25 + (sx + 50) * step / 70;
        final phase = x / sx * math.pi * 2.4;
        final y =
            rect.top +
            band * 4.2 +
            math.sin(phase + band * .032) * 20 +
            math.sin(phase * 2.1 + .7) * 8;
        if (step == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final light = band % 5 == 0;
      final color = light ? const Color(0xFFA2D39E) : const Color(0xFF032C1A);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = light ? 1.1 : (band.isEven ? 2.2 : .7)
          ..color = color.withValues(alpha: (light ? .65 : .6) * opacity),
      );
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant MalachitePaint oldDelegate) =>
      part != oldDelegate.part || selected != oldDelegate.selected;
}
