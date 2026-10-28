import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Optical glass and a metal housing; isolated to the native preview study.
class DeepGlassPaint extends CustomPainter {
  const DeepGlassPaint({required this.part, this.selected = false})
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
    final bounds = Offset.zero & size;
    if (part == 'background') {
      _studioPlane(canvas, bounds);
      return;
    }
    final button = part == 'button';
    final pearl = button && selected;
    final radius = math.min(17.0, size.shortestSide * .27);
    final depth = button ? 4.5 : 9.0;
    final bevel = button ? 4.0 : 6.0;
    final front = RRect.fromRectAndRadius(
      bounds.deflate(.8),
      Radius.circular(radius),
    );

    _housing(canvas, bounds, front, depth: depth, button: button);

    // This entire ring is glass thickness, not a thin decorative outline.
    canvas.drawRRect(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pearl
              ? const [
                  Color(0xFFFFFFFF),
                  Color(0xFFEDF1F6),
                  Color(0xFF849BB5),
                  Color(0xFFB9CEE0),
                ]
              : const [
                  Color(0xFFC6E0EC),
                  Color(0xFF648FA8),
                  Color(0xFF203C56),
                  Color(0xFF10253D),
                  Color(0xFF385D7B),
                ],
          stops: pearl ? const [0, .17, .8, 1] : const [0, .2, .48, .81, 1],
        ).createShader(bounds),
    );
    final readingFace = front.deflate(bevel);
    canvas.drawRRect(
      readingFace,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pearl
              ? const [Color(0xFFF0F2F7), Color(0xFFD7E0EB)]
              : part == 'rail'
              ? const [Color(0xFF25374C), Color(0xFF142236)]
              : const [Color(0xFF2D4158), Color(0xFF1B2D44)],
        ).createShader(bounds),
    );

    // A black internal seam and silver front rim explain the stacked layers.
    canvas.drawRRect(
      readingFace,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pearl
              ? const [Color(0xFFFFFFFF), Color(0x777288A2)]
              : const [Color(0xB007192A), Color(0x665A829E)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE5EDF8FF), Color(0x777CA7BF), Color(0xAB263D54)],
          stops: [0, .37, 1],
        ).createShader(bounds),
    );
    _edgeReflection(canvas, bounds, front, pearl: pearl);
    if (part == 'card') _numericRecess(canvas, bounds);
  }

  void _housing(
    Canvas canvas,
    Rect bounds,
    RRect front, {
    required double depth,
    required bool button,
  }) {
    final contact = front.shift(Offset(depth * .65, depth + 2));
    canvas.drawRRect(
      contact,
      Paint()
        ..color = const Color(0xA9030A13)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, button ? 5 : 17),
    );
    canvas.drawRRect(
      contact,
      Paint()
        ..color = const Color(0xE3050B12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, button ? 1.5 : 3),
    );
    final casing = front.shift(Offset(depth * .83, depth));
    final casingBounds = casing.outerRect;
    canvas.drawRRect(
      casing,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFC7D5DF),
            Color(0xFF5C7387),
            Color(0xFF1D3045),
            Color(0xFF566F83),
            Color(0xFF9CB3C4),
            Color(0xFF344B60),
          ],
          stops: [0, .15, .57, .87, .95, 1],
        ).createShader(casingBounds),
    );
    canvas.drawRRect(
      casing.deflate(.7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x81E8F1F5), Color(0x5C0C1A28), Color(0xB1A2B8C9)],
        ).createShader(casingBounds),
    );
    // A short dark seam separates the polished housing from the glass plate.
    canvas.drawRRect(
      front.shift(const Offset(2, 2)),
      Paint()..color = const Color(0xFF081624),
    );
    final bottom = Rect.fromLTWH(
      bounds.width * .09,
      bounds.height + depth - 2.2,
      bounds.width * .81,
      1,
    );
    canvas.drawLine(
      bottom.topLeft,
      bottom.topRight,
      Paint()
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          colors: [Color(0x048EAAC1), Color(0xB8B4C9D9), Color(0x19314C66)],
        ).createShader(bottom),
    );
  }

  void _numericRecess(Canvas canvas, Rect bounds) {
    final scale = bounds.height / 170;
    final wellBounds = Rect.fromLTRB(
      18,
      94 * scale,
      bounds.width - 18,
      161 * scale,
    );
    if (wellBounds.width <= 0 || wellBounds.height <= 0) return;
    final well = RRect.fromRectAndRadius(wellBounds, const Radius.circular(10));
    canvas.drawRRect(
      well,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF030B15), Color(0xFF1C3044), Color(0xFF7192A9)],
          stops: [0, .62, 1],
        ).createShader(wellBounds),
    );
    final window = well.deflate(2.4);
    canvas.drawRRect(window, Paint()..color = const Color(0xFF0A1423));
    canvas.save();
    canvas.clipRRect(window);
    final inner = window.outerRect;
    final topShade = Rect.fromLTWH(inner.left, inner.top, inner.width, 12);
    canvas.drawRect(
      topShade,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xED01050A), Color(0x0001050A)],
        ).createShader(topShade),
    );
    final leftShade = Rect.fromLTWH(inner.left, inner.top, 11, inner.height);
    canvas.drawRect(
      leftShade,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xAF01050A), Color(0x0001050A)],
        ).createShader(leftShade),
    );
    canvas.restore();
    canvas.drawLine(
      Offset(wellBounds.left + 10, wellBounds.bottom - .8),
      Offset(wellBounds.right - 10, wellBounds.bottom - .8),
      Paint()
        ..strokeWidth = 1
        ..color = const Color(0x916F90A9),
    );
  }

  void _edgeReflection(
    Canvas canvas,
    Rect bounds,
    RRect front, {
    required bool pearl,
  }) {
    canvas.save();
    canvas.clipRRect(front);
    // The studio window stays above the y15 reading zone and left of x19.
    canvas.clipPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, bounds.width, 13.5))
        ..addRect(Rect.fromLTWH(0, 0, 13.5, bounds.height)),
    );
    final window = Path()
      ..moveTo(-25, -40)
      ..lineTo(math.min(185, bounds.width * .55), -40)
      ..lineTo(math.min(157, bounds.width * .48), 15)
      ..lineTo(-25, 15)
      ..close();
    canvas.drawPath(
      window,
      Paint()
        ..color = Color(pearl ? 0x6FFFFFFF : 0x53D9F1FA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  void _studioPlane(Canvas canvas, Rect bounds) {
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF354658), Color(0xFF202F42), Color(0xFF111D30)],
          stops: [0, .45, 1],
        ).createShader(bounds),
    );
    final bounce = Rect.fromLTWH(
      -bounds.width * .3,
      -100,
      bounds.width * 1.05,
      bounds.height * .65,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topLeft,
          radius: 1.3,
          colors: [Color(0x356F8499), Color(0x006F8499)],
        ).createShader(bounce),
    );
  }

  @override
  bool shouldRepaint(DeepGlassPaint oldDelegate) =>
      oldDelegate.part != part || oldDelegate.selected != selected;

  @override
  bool? hitTest(Offset position) => false;
}
