import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Material-only native preview. All content and interaction belong to its host.
class OnyxIvoryPaint extends CustomPainter {
  const OnyxIvoryPaint({required this.part, this.selected = false})
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
        _rail(canvas, size);
      case 'card':
        _card(canvas, size);
      case 'button':
        _button(canvas, size);
    }
  }

  void _background(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      _linear(
        bounds,
        const [Color(0xFFF3EEE2), Color(0xFFE5DED1), Color(0xFFC4B9A8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .53, 1],
      ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.45, -.72),
          radius: 1.15,
          colors: [Color(0x68FFFFF6), Color(0x00FFF8E8)],
        ).createShader(bounds),
    );
    // Very low-contrast mineral clouds are broad enough to read as stone,
    // not marks competing with text or repeated decorative objects.
    for (final cloud in const [
      (Offset(.12, .37), .44, Color(0x11908365)),
      (Offset(.82, .15), .35, Color(0x13FFFFFF)),
      (Offset(.61, .91), .48, Color(0x10756E58)),
    ]) {
      final center = Offset(
        size.width * cloud.$1.dx,
        size.height * cloud.$1.dy,
      );
      final radius = size.width * cloud.$2;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [cloud.$3, cloud.$3.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
    _grain(canvas, bounds, seed: 419, dark: false, density: 105);
    canvas.save();
    canvas.clipPath(_edgeBand(bounds, 22));
    _vein(canvas, bounds, const Color(0x397B7661), seed: 72, amplitude: 12);
    _vein(
      canvas,
      bounds.deflate(8),
      const Color(0x27908A72),
      seed: 209,
      amplitude: 10,
    );
    canvas.restore();
  }

  void _rail(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final face = RRect.fromRectAndRadius(
      bounds.deflate(1),
      const Radius.circular(13),
    );
    canvas.drawShadow(
      Path()..addRRect(face),
      const Color(0xB5000806),
      8,
      false,
    );
    canvas.drawRRect(
      face,
      _linear(
        bounds,
        const [Color(0xFF34483F), Color(0xFF10241E), Color(0xFF07110F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .20, 1],
      ),
    );
    canvas.save();
    canvas.clipRRect(face);
    // A thin angled reflection, kept low enough for ivory navigation labels.
    canvas.drawRect(
      bounds,
      _linear(
        bounds,
        const [Color(0x225C7C69), Color(0x005C7C69), Color(0x0046594D)],
        begin: const Alignment(-1, -.85),
        end: const Alignment(.8, 1),
        stops: const [0, .42, 1],
      ),
    );
    _grain(canvas, bounds, seed: 621, dark: true, density: 90);
    canvas.save();
    canvas.clipPath(_edgeBand(bounds, 11));
    _vein(
      canvas,
      bounds.deflate(3),
      const Color(0x427B927D),
      seed: 18,
      amplitude: 9,
    );
    canvas.restore();
    canvas.restore();
    _rim(canvas, face, const Color(0xFFAC9967), const Color(0xFF24392D));
    final inlay = RRect.fromRectAndRadius(
      bounds.deflate(5),
      const Radius.circular(9),
    );
    canvas.drawRRect(
      inlay,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xBBE9DCA9), Color(0x34897745), Color(0x55978C61)],
        ).createShader(bounds),
    );
  }

  void _card(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final body = RRect.fromRectAndRadius(
      bounds.deflate(.5),
      const Radius.circular(10),
    );
    final faceBounds = Rect.fromLTRB(0, 0, size.width - 2, size.height - 4);
    final face = RRect.fromRectAndRadius(faceBounds, const Radius.circular(9));
    canvas.drawShadow(
      Path()..addRRect(body),
      const Color(0x887E7254),
      5,
      false,
    );
    // The visible lower edge is the cut side of the limestone slab.
    canvas.drawRRect(
      body,
      _linear(
        bounds,
        const [Color(0xFFC9BA91), Color(0xFF716346), Color(0xFF9F916F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .65, 1],
      ),
    );
    canvas.drawRRect(
      face,
      _linear(
        faceBounds,
        const [Color(0xFFFFFBEF), Color(0xFFF1EBD9), Color(0xFFDAD0B7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .57, 1],
      ),
    );
    canvas.save();
    canvas.clipRRect(face);
    _grain(canvas, faceBounds, seed: 820, dark: false, density: 46);
    // The content inset starts at 16px. Veins live strictly in the outer 12px.
    canvas.save();
    canvas.clipPath(_edgeBand(faceBounds, 12));
    _vein(
      canvas,
      faceBounds.deflate(2),
      const Color(0x498F8667),
      seed: 131,
      amplitude: 7,
    );
    _vein(
      canvas,
      faceBounds.deflate(4),
      const Color(0x26827052),
      seed: 72,
      amplitude: 5,
    );
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 8),
      _linear(Rect.fromLTWH(0, 0, size.width, 8), const [
        Color(0x75FFFFFF),
        Color(0x00FFFFFF),
      ]),
    );
    canvas.restore();
    _rim(
      canvas,
      face,
      const Color(0xFFFFFEF1),
      selected ? const Color(0xFFA4853D) : const Color(0xFFA99A73),
    );
    final inlay = RRect.fromRectAndRadius(
      faceBounds.deflate(5),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      inlay,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1 : .55
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            selected ? const Color(0xF0B69848) : const Color(0x8EB49F67),
            const Color(0x269E8C54),
            const Color(0x70947E45),
          ],
        ).createShader(faceBounds),
    );
  }

  void _button(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final base = RRect.fromRectAndRadius(
      bounds.deflate(.5),
      const Radius.circular(7),
    );
    final faceBounds = Rect.fromLTRB(
      .5,
      .5,
      size.width - .5,
      size.height - 2.5,
    );
    final face = RRect.fromRectAndRadius(faceBounds, const Radius.circular(6));
    canvas.drawShadow(
      Path()..addRRect(base),
      const Color(0x85040D08),
      3,
      false,
    );
    canvas.drawRRect(
      base,
      Paint()
        ..color = selected ? const Color(0xFF71551C) : const Color(0xFF08120F),
    );
    canvas.drawRRect(
      face,
      _linear(
        faceBounds,
        selected
            ? const [Color(0xFFF1DDA0), Color(0xFFC7A253), Color(0xFFB28B3D)]
            : const [Color(0xFF344D40), Color(0xFF1B2F25), Color(0xFF10231B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, .47, 1],
      ),
    );
    canvas.save();
    canvas.clipRRect(face);
    if (selected) {
      // Fine horizontal machining traces read as satin brass, not a glow.
      final brush = Paint()
        ..color = const Color(0x28FFF8CA)
        ..strokeWidth = .35;
      for (double y = 3; y < size.height - 3; y += 2.7) {
        canvas.drawLine(Offset(2, y), Offset(size.width - 2, y + .35), brush);
      }
    } else {
      _grain(canvas, faceBounds, seed: 901, dark: true, density: 52);
    }
    canvas.restore();
    _rim(
      canvas,
      face,
      selected ? const Color(0xFFFFF0B3) : const Color(0xFF738673),
      selected ? const Color(0xFF947335) : const Color(0xFF162B20),
    );
  }

  Paint _linear(
    Rect bounds,
    List<Color> colors, {
    Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter,
    List<double>? stops,
  }) => Paint()
    ..shader = LinearGradient(
      begin: begin,
      end: end,
      colors: colors,
      stops: stops,
    ).createShader(bounds);

  void _rim(Canvas canvas, RRect face, Color light, Color dark) {
    canvas.drawRRect(
      face.deflate(.65),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, light.withValues(alpha: .55), dark],
          stops: const [0, .28, 1],
        ).createShader(face.outerRect),
    );
  }

  Path _edgeBand(Rect bounds, double width) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(bounds)
    ..addRect(bounds.deflate(width));

  void _grain(
    Canvas canvas,
    Rect bounds, {
    required int seed,
    required bool dark,
    required double density,
  }) {
    final random = math.Random(seed);
    final paint = Paint()
      ..color = dark ? const Color(0x145F8B73) : const Color(0x176B6146);
    final count = (bounds.width * bounds.height / density).round();
    for (var i = 0; i < count; i++) {
      final point = Offset(
        bounds.left + random.nextDouble() * bounds.width,
        bounds.top + random.nextDouble() * bounds.height,
      );
      canvas.drawCircle(point, .25 + random.nextDouble() * .28, paint);
    }
  }

  void _vein(
    Canvas canvas,
    Rect bounds,
    Color color, {
    required int seed,
    required double amplitude,
  }) {
    final random = math.Random(seed);
    final path = Path();
    var point = Offset(bounds.left, bounds.top + amplitude * .7);
    path.moveTo(point.dx, point.dy);
    for (var i = 1; i <= 20; i++) {
      final next = Offset(
        bounds.left + bounds.width * i / 20,
        bounds.top + random.nextDouble() * amplitude,
      );
      path.quadraticBezierTo(
        (point.dx + next.dx) / 2,
        point.dy + (random.nextDouble() - .5) * amplitude,
        next.dx,
        next.dy,
      );
      point = next;
    }
    path.moveTo(
      bounds.left + bounds.width * .38,
      bounds.bottom - amplitude * .35,
    );
    for (var i = 0; i < 16; i++) {
      path.lineTo(
        bounds.left + bounds.width * (.38 + .62 * i / 15),
        bounds.bottom - random.nextDouble() * amplitude,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65,
    );
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant OnyxIvoryPaint oldDelegate) =>
      part != oldDelegate.part || selected != oldDelegate.selected;
}
