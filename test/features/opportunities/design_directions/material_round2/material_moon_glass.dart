import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Static smoked-glass materials for the native design comparison only.
class MoonGlassPaint extends CustomPainter {
  const MoonGlassPaint({required this.part, this.selected = false})
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
      _background(canvas, bounds);
      return;
    }

    final button = part == 'button';
    final pearl = button && selected;
    final rail = part == 'rail';
    final radius = math.min(16.0, size.shortestSide / 3);
    final faceBounds = bounds.deflate(1.2);
    final face = RRect.fromRectAndRadius(faceBounds, Radius.circular(radius));
    final depth = button ? 3.2 : 5.5;

    // The lowest layer casts contact darkness; a little transmitted blue light
    // sits beyond it on the underlying plane rather than on the reading face.
    canvas.drawRRect(
      face.shift(Offset(0, button ? 3 : 9)),
      Paint()
        ..color = Color(button ? 0x9803020A : 0xBC03030B)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, button ? 4 : 12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .13,
          size.height - 3,
          size.width * .62,
          button ? 5 : 9,
        ),
        const Radius.circular(7),
      ),
      Paint()
        ..color = Color(pearl ? 0x49BEB9DE : 0x2C8686CC)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, button ? 7 : 13),
    );
    canvas.drawRRect(
      face.shift(Offset(0, depth)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pearl
              ? const [Color(0xFF777790), Color(0xFF303147)]
              : const [Color(0xFF36354A), Color(0xFF0B0C17)],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pearl
              ? const [
                  Color(0xFFF5F1F5),
                  Color(0xFFE1E1EE),
                  Color(0xFFD0CDDF),
                  Color(0xFFE1E4ED),
                ]
              : rail
              ? const [
                  Color(0xF52D304A),
                  Color(0xF51C2035),
                  Color(0xF217192B),
                  Color(0xF7212136),
                ]
              : const [
                  Color(0xF530344C),
                  Color(0xF51D2034),
                  Color(0xF417192C),
                  Color(0xF2222035),
                ],
          stops: const [0, .28, .73, 1],
        ).createShader(bounds),
    );

    canvas.save();
    canvas.clipRRect(face);
    _reflections(canvas, bounds, pearl: pearl, rail: rail, button: button);
    canvas.restore();

    // Both rims are kept at the edge; iridescence never crosses item text.
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pearl ? 1.6 : 1.35
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pearl
              ? const [
                  Color(0xF7FFFFFF),
                  Color(0xA9F1EAF8),
                  Color(0xC7B7BCDA),
                  Color(0xDBEEF2FC),
                ]
              : const [
                  Color(0xCDDADCEA),
                  Color(0x887E83B2),
                  Color(0x49605886),
                  Color(0x897A80A8),
                ],
          stops: const [0, .3, .7, 1],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      face.deflate(3.0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pearl
              ? const [Color(0x9AFFFFFF), Color(0x06323658), Color(0x5AFFFFFF)]
              : const [Color(0x337477A5), Color(0x04131729), Color(0x53060711)],
          stops: const [0, .45, 1],
        ).createShader(bounds),
    );

    final rimBounds = Rect.fromLTWH(
      radius + 3,
      1.5,
      math.max(0, size.width - radius * 2 - 6),
      2,
    );
    canvas.drawLine(
      rimBounds.topLeft,
      rimBounds.topRight,
      Paint()
        ..strokeWidth = pearl ? 1.6 : 1.1
        ..shader = LinearGradient(
          colors: pearl
              ? const [Color(0x24FFFFFF), Color(0xF0FFFFFF), Color(0x20EEE4FC)]
              : const [Color(0x15D8E5FA), Color(0xB9D5DEF2), Color(0x16D7C4EF)],
          stops: const [0, .3, 1],
        ).createShader(rimBounds),
    );
    canvas.drawLine(
      Offset(radius + 3, size.height + depth - 2),
      Offset(size.width - radius - 3, size.height + depth - 2),
      Paint()
        ..strokeWidth = .7
        ..color = Color(pearl ? 0x697B799A : 0x38545A86),
    );
  }

  void _reflections(
    Canvas canvas,
    Rect bounds, {
    required bool pearl,
    required bool rail,
    required bool button,
  }) {
    final cap = Rect.fromLTWH(
      bounds.left - bounds.width * .12,
      bounds.top - 10,
      bounds.width * .75,
      button ? 20 : 36,
    );
    canvas.drawRect(
      cap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pearl
              ? const [Color(0x7AFFFFFF), Color(0x00FFFFFF)]
              : const [Color(0x237B87B3), Color(0x007B87B3)],
        ).createShader(cap),
    );
    if (rail) {
      final strip = Rect.fromLTWH(
        -12,
        bounds.height * .06,
        25,
        bounds.height * .72,
      );
      canvas.drawRect(
        strip,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x216D7FAE), Color(0x006D7FAE)],
          ).createShader(strip)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    final lowerEdge = Rect.fromLTWH(
      bounds.width * .5,
      bounds.height - 10,
      bounds.width * .45,
      12,
    );
    canvas.drawRect(
      lowerEdge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pearl
              ? const [Color(0x00D6DDF4), Color(0x43D6DDF4)]
              : const [Color(0x00978ABD), Color(0x17978ABD)],
        ).createShader(lowerEdge),
    );
  }

  void _background(Canvas canvas, Rect bounds) {
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2036), Color(0xFF0D1020), Color(0xFF121322)],
          stops: [.02, .55, 1],
        ).createShader(bounds),
    );
    final reflectedPlane = Path()
      ..moveTo(bounds.width * .1, -80)
      ..lineTo(bounds.width * .64, -80)
      ..lineTo(bounds.width * .36, bounds.height + 100)
      ..lineTo(-bounds.width * .16, bounds.height + 100)
      ..close();
    canvas.drawPath(
      reflectedPlane,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x163C4D76), Color(0x08363A66), Color(0x00363A66)],
        ).createShader(bounds)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 52),
    );
    final rightReflection = Rect.fromLTWH(
      bounds.width * .86,
      0,
      bounds.width * .14,
      bounds.height,
    );
    canvas.drawRect(
      rightReflection,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00483966), Color(0x17483966)],
        ).createShader(rightReflection)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
  }

  @override
  bool shouldRepaint(MoonGlassPaint oldDelegate) =>
      oldDelegate.part != part || oldDelegate.selected != selected;

  @override
  bool? hitTest(Offset position) => false;
}
