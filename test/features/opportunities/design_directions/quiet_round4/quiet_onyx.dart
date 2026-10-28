import 'package:flutter/material.dart';

/// A quieter enamel study: one continuous body, no nested panel frames.
class QuietOnyxPaint extends CustomPainter {
  const QuietOnyxPaint({required this.part, this.selected = false})
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

  static Paint _wash(
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

  static RRect _shape(Rect rect, double radius) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      _wash(
        rect,
        const [Color(0xFF323739), Color(0xFF242B2E), Color(0xFF171F23)],
        stops: const [0, .45, 1],
      ),
    );
  }

  void _body(Canvas canvas, RRect shape, {required double depth}) {
    final path = Path()..addRRect(shape);
    canvas.drawShadow(
      path.shift(Offset(1.5, depth)),
      const Color(0xC0000000),
      9,
      false,
    );
    canvas.drawShadow(
      path.shift(const Offset(1, 1.5)),
      const Color(0xDD000000),
      2,
      false,
    );
    canvas.drawRRect(
      shape.shift(Offset(depth, depth)),
      _wash(
        shape.outerRect,
        const [Color(0xFF293235), Color(0xFF121C20)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
  }

  void _card(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 3.5, size.height - 3.5);
    final body = _shape(rect, 12);
    _body(canvas, body, depth: 3.5);
    canvas.drawRRect(
      body,
      _wash(rect, const [Color(0xFF2B3436), Color(0xFF1D282C)]),
    );
    canvas.save();
    canvas.clipRRect(body);

    // The enamel meets the dark base along one softly rolled edge.
    final enamel = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, 88)
      ..quadraticBezierTo(rect.width * .72, 92, rect.width * .48, 91)
      ..quadraticBezierTo(rect.width * .22, 92, rect.left, 89)
      ..close();
    final castShadow = enamel.shift(const Offset(0, 3));
    canvas.drawPath(
      castShadow,
      Paint()
        ..color = const Color(0x88080F11)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      enamel,
      _wash(
        Rect.fromLTRB(0, 0, rect.right, 92),
        const [Color(0xFFF1EEE4), Color(0xFFE8E4D8), Color(0xFFD4CEBE)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .82, 1],
      ),
    );

    // Curved highlights occupy the outer few pixels, never the item or its name.
    final upperLip = Rect.fromLTWH(0, 0, rect.width, 6);
    canvas.drawRect(
      upperLip,
      _wash(
        upperLip,
        const [Color(0xFFE2DED1), Color(0xEFFFFFF7), Color(0x00FFFFF7)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .36, 1],
      ),
    );
    final leftLip = Rect.fromLTWH(0, 0, 5, 86);
    canvas.drawRect(
      leftLip,
      _wash(
        leftLip,
        const [Color(0xFFC5BFAF), Color(0xBFFFFCF0), Color(0x00FFFCF0)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: const [0, .45, 1],
      ),
    );
    // A slight curved rolloff on the ivory side supplies depth without a seam.
    canvas.save();
    canvas.clipPath(enamel);
    final lowerLip = Rect.fromLTWH(0, 85, rect.width, 8);
    canvas.drawRect(
      lowerLip,
      _wash(
        lowerLip,
        const [Color(0x005C594C), Color(0x165C594C), Color(0x705C594C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .55, 1],
      ),
    );
    canvas.restore();
    canvas.restore();

    // The only outline belongs to the outer silhouette; there is no bottom trim.
    canvas.drawRRect(
      body,
      _wash(rect, const [
          Color(0xCFFFFBE9),
          Color(0x353B4444),
          Color(0x30202B2F),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }

  void _rail(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 3, size.height - 3);
    final shape = _shape(rect, 12);
    _body(canvas, shape, depth: 3);
    canvas.drawRRect(
      shape,
      _wash(rect, const [
        Color(0xFF303A3D),
        Color(0xFF222E33),
        Color(0xFF1B272D),
      ]),
    );
    canvas.drawRRect(
      shape,
      _wash(rect, const [
          Color(0x706E7774),
          Color(0x302B383D),
          Color(0x40202D34),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  void _button(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 2, size.height - 2.5);
    final shape = _shape(rect, 7);
    _body(canvas, shape, depth: 2.5);
    canvas.drawRRect(
      shape,
      _wash(
        rect,
        selected
            ? const [Color(0xFFDED2B5), Color(0xFFCABB98), Color(0xFFB3A784)]
            : const [Color(0xFF3E4A4D), Color(0xFF303E43), Color(0xFF27363D)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .52, 1],
      ),
    );
    canvas.drawRRect(
      shape,
      _wash(
          rect,
          selected
              ? const [Color(0xBFF4EBD0), Color(0x55726C54)]
              : const [Color(0x70838E8B), Color(0x45212D34)],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant QuietOnyxPaint oldDelegate) =>
      part != oldDelegate.part || selected != oldDelegate.selected;
}
