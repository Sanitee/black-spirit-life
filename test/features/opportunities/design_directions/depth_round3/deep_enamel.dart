import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Native depth study; the shared preview supplies all text and game artwork.
class DeepEnamelPaint extends CustomPainter {
  const DeepEnamelPaint({required this.part, this.selected = false})
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

  static RRect _round(Rect rect, double radius) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

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
        const [Color(0xFF373A3C), Color(0xFF24272A), Color(0xFF111517)],
        stops: const [0, .36, 1],
      ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.8, -1),
          radius: 1.1,
          colors: [Color(0x246B6558), Color(0x006B6558)],
        ).createShader(rect),
    );
  }

  void _card(Canvas canvas, Size size) {
    // This is an assembly: a metal chassis, a ceramic insert and a sunk display.
    final frontRect = Rect.fromLTWH(0, 0, size.width - 8, size.height - 8);
    final front = _round(frontRect, 13);
    _extrudedChassis(canvas, front, depth: 8);
    canvas.drawRRect(
      front,
      _gradient(
        frontRect,
        const [
          Color(0xFFE2D9C4),
          Color(0xFFA79F8C),
          Color(0xFFC6BDA7),
          Color(0xFF746F62),
          Color(0xFFAAA28D),
        ],
        stops: const [0, .14, .35, .68, 1],
      ),
    );
    _metalEdge(canvas, front, bright: true);

    final enamelRect = Rect.fromLTRB(6, 6, size.width - 14, 90);
    _enamelInsert(canvas, enamelRect);
    final well = Rect.fromLTRB(
      12,
      94,
      size.width - 12,
      math.min(161, size.height - 9),
    );
    _instrumentWindow(canvas, well);
  }

  void _extrudedChassis(Canvas canvas, RRect front, {required double depth}) {
    final path = Path()..addRRect(front);
    canvas.drawShadow(
      path.shift(Offset(depth * .55, depth * .75)),
      const Color(0xE0000000),
      12,
      false,
    );
    canvas.drawShadow(
      path.shift(const Offset(2, 3)),
      const Color(0xFF000000),
      3,
      false,
    );
    final side = front.shift(Offset(depth, depth));
    canvas.drawRRect(
      side,
      _gradient(
        side.outerRect,
        const [
          Color(0xFF706D62),
          Color(0xFF393A36),
          Color(0xFF777365),
          Color(0xFF282C2C),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .5, .91, 1],
      ),
    );
    canvas.drawRRect(
      side,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF101516),
    );
    // Narrow reflected bands make the vertical lower edge physically readable.
    canvas.drawLine(
      Offset(front.left + 15 + depth, front.bottom + depth - 2),
      Offset(front.right - 11 + depth, front.bottom + depth - 2),
      _gradient(side.outerRect, const [
        Color(0x909C9788),
        Color(0x70645F53),
        Color(0x30504E45),
      ])..strokeWidth = 1,
    );
  }

  void _metalEdge(Canvas canvas, RRect shape, {required bool bright}) {
    canvas.drawRRect(
      shape,
      _gradient(
          shape.outerRect,
          bright
              ? const [Color(0xFFF8F0D9), Color(0xFF7A7768), Color(0xFF484C47)]
              : const [Color(0xFF99998F), Color(0xFF444A4A), Color(0xFF101719)],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final inner = shape.deflate(2);
    canvas.drawRRect(
      inner,
      _gradient(shape.outerRect, const [
          Color(0x50958F7C),
          Color(0x209A988A),
          Color(0x70E0D7BF),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7,
    );
  }

  void _enamelInsert(Canvas canvas, Rect rect) {
    final ceramic = _round(rect, 10);
    // A dark joint and a ceramic sidewall sit beneath the rounded glazed lip.
    canvas.drawRRect(
      ceramic.shift(const Offset(1, 2.5)),
      Paint()..color = const Color(0xFF635E50),
    );
    canvas.drawRRect(
      ceramic.inflate(.6),
      Paint()..color = const Color(0xCC605B4D),
    );
    canvas.drawRRect(
      ceramic,
      _gradient(
        rect,
        const [
          Color(0xFFFFFEF3),
          Color(0xFFE3DFD1),
          Color(0xFFBDB6A1),
          Color(0xFF938C78),
        ],
        stops: const [0, .33, .88, 1],
      ),
    );
    final face = ceramic.deflate(4);
    canvas.drawRRect(
      face,
      _gradient(
        face.outerRect,
        const [Color(0xFFF2EFE4), Color(0xFFEAE6D9), Color(0xFFE5E0D1)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    canvas.save();
    canvas.clipRRect(ceramic);
    // A rolled edge changes brightness over only a few pixels, like real glaze.
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 7),
      _gradient(
        Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + 7),
        const [
          Color(0xFFE5DFCC),
          Color(0xFFFFFEF7),
          Color(0xAFFFFEF7),
          Color(0x00FFFEF7),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .23, .49, 1],
      ),
    );
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, rect.left + 7, rect.bottom),
      _gradient(
        Rect.fromLTRB(rect.left, rect.top, rect.left + 7, rect.bottom),
        const [Color(0xBFB6B09C), Color(0xFFFFFEF0), Color(0x00FFFEF0)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: const [0, .38, 1],
      ),
    );
    canvas.drawRect(
      Rect.fromLTRB(rect.right - 5, rect.top, rect.right, rect.bottom),
      _gradient(
        Rect.fromLTRB(rect.right - 5, rect.top, rect.right, rect.bottom),
        const [Color(0x00625B46), Color(0x80625B46)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.bottom - 5, rect.right, rect.bottom),
      _gradient(
        Rect.fromLTRB(rect.left, rect.bottom - 5, rect.right, rect.bottom),
        const [Color(0x00635C46), Color(0x70635C46)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    canvas.restore();
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + 1.5, rect.top + 11)
        ..quadraticBezierTo(
          rect.left + 1.5,
          rect.top + 1.5,
          rect.left + 11,
          rect.top + 1.5,
        )
        ..lineTo(rect.left + rect.width * .62, rect.top + 1.5),
      _gradient(rect, const [
          Color(0xEFFFFFFF),
          Color(0x70FFFFFF),
          Color(0x00FFFFFF),
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _instrumentWindow(Canvas canvas, Rect rect) {
    final rim = _round(rect, 6);
    canvas.drawRRect(rim.inflate(.7), Paint()..color = const Color(0xFF534F42));
    // Bright lower/right metal and a black upper edge signal a recess, not a card.
    canvas.drawRRect(
      rim,
      _gradient(
        rect,
        const [Color(0xFF050708), Color(0xFF111719), Color(0xFF8D8C7C)],
        stops: const [0, .57, 1],
      ),
    );
    final glass = rim.deflate(2.4);
    final bounds = glass.outerRect;
    canvas.drawRRect(
      glass,
      _gradient(bounds, const [
        Color(0xFF151C1E),
        Color(0xFF1C2526),
        Color(0xFF141C1E),
      ]),
    );
    canvas.save();
    canvas.clipRRect(glass);
    final topShadow = Rect.fromLTWH(bounds.left, bounds.top, bounds.width, 9);
    canvas.drawRect(
      topShadow,
      _gradient(
        topShadow,
        const [Color(0xE6000000), Color(0x66000000), Color(0x00000000)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .4, 1],
      ),
    );
    final sideShadow = Rect.fromLTWH(bounds.left, bounds.top, 7, bounds.height);
    canvas.drawRect(
      sideShadow,
      _gradient(
        sideShadow,
        const [Color(0xA3000000), Color(0x00000000)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
    );
    canvas.restore();
    canvas.drawLine(
      Offset(rect.left + 7, rect.bottom - 1),
      Offset(rect.right - 7, rect.bottom - 1),
      Paint()
        ..color = const Color(0xFFA9A894)
        ..strokeWidth = .8,
    );
  }

  void _rail(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 7, size.height - 7);
    final shell = _round(rect, 12);
    _extrudedChassis(canvas, shell, depth: 7);
    canvas.drawRRect(
      shell,
      _gradient(rect, const [
        Color(0xFF62625B),
        Color(0xFF333A3A),
        Color(0xFF151F22),
      ]),
    );
    final face = shell.deflate(6);
    canvas.drawRRect(
      face,
      _gradient(face.outerRect, const [
        Color(0xFF2B3234),
        Color(0xFF1C2528),
        Color(0xFF161F22),
      ]),
    );
    _metalEdge(canvas, shell, bright: false);
    canvas.drawRRect(
      face,
      Paint()
        ..color = const Color(0xA0081114)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _button(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 3, size.height - 4);
    final shell = _round(rect, 7);
    _extrudedChassis(canvas, shell, depth: 3);
    canvas.drawRRect(
      shell,
      _gradient(
        rect,
        selected
            ? const [Color(0xFFFFF2CE), Color(0xFFA79A76), Color(0xFF736C53)]
            : const [Color(0xFF939993), Color(0xFF424C4C), Color(0xFF222C30)],
      ),
    );
    final face = shell.deflate(2.5);
    canvas.drawRRect(
      face,
      _gradient(
        face.outerRect,
        selected
            ? const [Color(0xFFE9DCB9), Color(0xFFDBC99D), Color(0xFFBEAB7E)]
            : const [Color(0xFF495253), Color(0xFF323E41), Color(0xFF253338)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    );
    _metalEdge(canvas, shell, bright: selected);
    canvas.drawPath(
      Path()
        ..moveTo(2, 11)
        ..quadraticBezierTo(2, 2, 10, 2)
        ..lineTo(rect.right - 9, 2),
      Paint()
        ..color = selected ? const Color(0xEFFFF7DB) : const Color(0xAFBAC4BE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant DeepEnamelPaint oldDelegate) =>
      part != oldDelegate.part || selected != oldDelegate.selected;
}
