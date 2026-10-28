import 'package:flutter/material.dart';

/// Translucent material for a host-provided, clipped sigma-24 backdrop blur.
/// Paint after the blur and outside its clip so the contact shadow stays sharp.
class SmokedGlassPaint extends CustomPainter {
  const SmokedGlassPaint({required this.part, this.selected = false})
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
    if (part == 'background') {
      _background(canvas, size);
      return;
    }
    _glass(canvas, size);
  }

  static Paint _gradient(
    Rect rect,
    List<Color> colors, {
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
    List<double>? stops,
  }) => Paint()
    ..shader = LinearGradient(
      begin: begin,
      end: end,
      colors: colors,
      stops: stops,
    ).createShader(rect);

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      _gradient(
        rect,
        const [Color(0xFF102D3D), Color(0xFF0B1C30), Color(0xFF080E23)],
        stops: const [0, .47, 1],
      ),
    );

    // Large diffused lights show through the glass without adding decoration.
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .28, size.height * .15),
        width: size.width * .95,
        height: size.height * 1.15,
      ),
      const Color(0xC22B9EA7),
      const Color(0x58295B94),
    );
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .91, size.height * .43),
        width: size.width * .80,
        height: size.height * 1.35,
      ),
      const Color(0xB97952B0),
      const Color(0x50453D87),
    );
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .54, size.height * 1.01),
        width: size.width * .76,
        height: size.height * 1.05,
      ),
      const Color(0xA4238994),
      const Color(0x44234675),
    );
    // A single light fold gives the blur something to soften through the panes.
    // It belongs to the backdrop, never to the item or numeric content.
    final fold = Path()
      ..moveTo(-size.width * .08, size.height * 1.15)
      ..cubicTo(
        -size.width * .03,
        size.height * .55,
        size.width * .42,
        size.height * .57,
        size.width * .58,
        -size.height * .25,
      )
      ..lineTo(size.width * .72, -size.height * .25)
      ..cubicTo(
        size.width * .34,
        size.height * .59,
        size.width * .07,
        size.height * .57,
        size.width * .05,
        size.height * 1.15,
      )
      ..close();
    canvas.drawPath(
      fold,
      _gradient(
        rect,
        const [Color(0x185CCDBF), Color(0x602C9FBC), Color(0x103E55BC)],
        stops: const [0, .47, 1],
      )..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Keep the outer corners grounded while the illuminated middle has colour.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.1),
          radius: 1.05,
          colors: [Color(0x00030B19), Color(0x00030B19), Color(0x60030B19)],
          stops: [0, .58, 1],
        ).createShader(rect),
    );
  }

  void _light(Canvas canvas, Rect rect, Color center, Color shoulder) {
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [center, shoulder, center.withAlpha(0)],
          stops: const [0, .43, 1],
        ).createShader(rect),
    );
  }

  void _glass(Canvas canvas, Size size) {
    final button = part == 'button';
    final rail = part == 'rail';
    final active = button && selected;
    final depth = button ? 2.0 : 3.0;
    final rect = Rect.fromLTWH(0, 0, size.width - depth, size.height - depth);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(button ? 8 : 16),
    );
    final path = Path()..addRRect(shape);

    // Shadow and sidewall must never darken the transparent reading surface.
    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(60)),
        path,
      ),
    );
    canvas.drawShadow(
      path.shift(Offset(1, depth + 1)),
      const Color(0xBB010616),
      button ? 5 : 10,
      false,
    );
    canvas.drawShadow(
      path.shift(const Offset(1, 1.5)),
      const Color(0xA0010711),
      2,
      false,
    );
    canvas.restore();

    final side = Path.combine(
      PathOperation.difference,
      Path()..addRRect(shape.shift(Offset(depth * .8, depth))),
      path,
    );
    canvas.drawPath(
      side,
      _gradient(
        rect,
        active
            ? const [Color(0xAF74BFC8), Color(0xA92B536D)]
            : const [Color(0x8A467A90), Color(0xA109182E)],
      ),
    );

    canvas.drawRRect(
      shape,
      _gradient(
        rect,
        active
            ? const [Color(0xC2357384), Color(0xBF245870), Color(0xD5203E63)]
            : rail
            ? const [Color(0xA0183447), Color(0xB20B1C32)]
            : button
            ? const [Color(0x912F586D), Color(0xA11A304F)]
            : const [Color(0x8025475A), Color(0x96172F48), Color(0xA910203B)],
      ),
    );

    canvas.save();
    canvas.clipRRect(shape);
    final reflection = Path()
      ..moveTo(rect.left - 16, rect.top - 15)
      ..lineTo(rect.width * .82, rect.top - 15)
      ..cubicTo(
        rect.width * .66,
        rect.height * .10,
        rect.width * .39,
        rect.height * .40,
        rect.width * .10,
        rect.height * .29,
      )
      ..lineTo(rect.left - 16, rect.height * .40)
      ..close();
    canvas.drawPath(
      reflection,
      _gradient(
        rect,
        active
            ? const [Color(0x18FFFFFF), Color(0x06FFFFFF), Color(0x00FFFFFF)]
            : const [Color(0x26D6F4FF), Color(0x0ED6F4FF), Color(0x00D6F4FF)],
        stops: const [0, .34, .7],
      )..maskFilter = MaskFilter.blur(BlurStyle.normal, button ? 6 : 16),
    );
    canvas.restore();

    // One edge explains the glass silhouette; there is no inner frame.
    canvas.drawRRect(
      shape,
      _gradient(
          rect,
          active
              ? const [Color(0xCECFFEF5), Color(0x7063AFC4), Color(0x7C3D6D99)]
              : const [Color(0x8CC3E7F6), Color(0x445D9BB7), Color(0x5359619A)],
          stops: const [0, .42, 1],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );
    if (!button && !rail) {
      final glint = Path()
        ..moveTo(1, 28)
        ..lineTo(1, 16)
        ..quadraticBezierTo(1, 1, 16, 1)
        ..lineTo(rect.width * .34, 1);
      canvas.drawPath(
        glint,
        _gradient(
            Rect.fromLTWH(0, 0, rect.width * .34, 30),
            const [Color(0x85D7FAFF), Color(0x28C5E3FF), Color(0x00C5E3FF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0, .30, 1],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SmokedGlassPaint oldDelegate) =>
      part != oldDelegate.part || selected != oldDelegate.selected;
}
