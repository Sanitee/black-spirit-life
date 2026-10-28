import 'package:flutter/material.dart';

/// Native, preview-only material: a continuous satin face, not a split card.
class TonalOnyxPaint extends CustomPainter {
  const TonalOnyxPaint({required this.part, this.selected = false});
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

  static Paint _gradient(
    Rect rect,
    List<Color> colors, {
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
    List<double>? stops,
  }) => Paint()
    ..shader = LinearGradient(
      colors: colors,
      begin: begin,
      end: end,
      stops: stops,
    ).createShader(rect);

  static RRect _shape(Rect rect, double radius) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      _gradient(
        rect,
        const [Color(0xFF303534), Color(0xFF292F2E), Color(0xFF252B2C)],
        stops: const [0, .55, 1],
      ),
    );
  }

  void _body(Canvas canvas, RRect shape, double depth) {
    final path = Path()..addRRect(shape);
    canvas.drawShadow(
      path.shift(Offset(1, depth)),
      const Color(0x90000000),
      7,
      false,
    );
    canvas.drawShadow(
      path.shift(const Offset(0, 1)),
      const Color(0x88000000),
      1.5,
      false,
    );
    canvas.drawRRect(
      shape.shift(Offset(depth, depth)),
      _gradient(shape.outerRect, const [Color(0xFF303735), Color(0xFF202A29)]),
    );
  }

  void _card(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 3, size.height - 3);
    final shape = _shape(rect, 12);
    _body(canvas, shape, 3);

    // A broad, soft falloff joins the item and its numbers without a hard seam.
    canvas.drawRRect(
      shape,
      _gradient(
        rect,
        const [
          Color(0xFF4C504F),
          Color(0xFF444A48),
          Color(0xFF3A4240),
          Color(0xFF333C3B),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .44, .66, 1],
      ),
    );
    canvas.save();
    canvas.clipRRect(shape);

    // The light rolls over the surface edge; it does not frame another panel.
    final reflectedLight = Rect.fromLTWH(0, 0, rect.width, 30);
    canvas.drawRect(
      reflectedLight,
      _gradient(
        reflectedLight,
        const [Color(0x177D8479), Color(0x007D8479)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    final lip = Rect.fromLTWH(0, 0, rect.width, 4);
    canvas.drawRect(
      lip,
      _gradient(
        lip,
        const [Color(0x55777E75), Color(0x258E9488), Color(0x008E9488)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .42, 1],
      ),
    );
    canvas.restore();

    canvas.drawRRect(
      shape,
      _gradient(rect, const [
          Color(0x808B9185),
          Color(0x35424D47),
          Color(0x30333C38),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }

  void _rail(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 3, size.height - 3);
    final shape = _shape(rect, 12);
    _body(canvas, shape, 3);
    canvas.drawRRect(
      shape,
      _gradient(rect, const [
        Color(0xFF343D3A),
        Color(0xFF2E3735),
        Color(0xFF283331),
      ]),
    );
    canvas.drawRRect(
      shape,
      _gradient(rect, const [Color(0x606D7569), Color(0x20313D37)])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  void _button(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 2, size.height - 2.5);
    final shape = _shape(rect, 7);
    _body(canvas, shape, 2.5);
    canvas.drawRRect(
      shape,
      _gradient(
        rect,
        selected
            ? const [Color(0xFF69604E), Color(0xFF5C5547), Color(0xFF504C41)]
            : const [Color(0xFF424B46), Color(0xFF39433E), Color(0xFF343D39)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .52, 1],
      ),
    );
    canvas.drawRRect(
      shape,
      _gradient(
          rect,
          selected
              ? const [Color(0xBFB8A786), Color(0x606B6452)]
              : const [Color(0x706C796B), Color(0x35384136)],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  @override
  bool? hitTest(Offset position) => false;
  @override
  bool shouldRepaint(covariant TonalOnyxPaint oldDelegate) =>
      part != oldDelegate.part || selected != oldDelegate.selected;
}
