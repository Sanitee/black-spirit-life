import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Native Flutter rendering of the 24x24 vector glyphs used by the Avalonia
/// baseline. Keeping these paths in one painter preserves icon silhouettes
/// without introducing an external rendering surface.
class AppVectorGlyph extends StatelessWidget {
  const AppVectorGlyph(
    this.name, {
    this.size = 16,
    this.color,
    this.tightBounds = false,
    super.key,
  });

  final String name;
  final double size;
  final Color? color;
  final bool tightBounds;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _AppVectorGlyphPainter(
        name: name,
        color: color ?? IconTheme.of(context).color ?? Colors.white,
        tightBounds: tightBounds,
      ),
    ),
  );
}

class _AppVectorGlyphPainter extends CustomPainter {
  const _AppVectorGlyphPainter({
    required this.name,
    required this.color,
    required this.tightBounds,
  });

  final String name;
  final Color color;
  final bool tightBounds;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = _glyphPath(name);
    final filled = name == 'spark' || name == 'star';
    final strokeWidth = filled ? 1.0 : 2.0;
    final sourceBounds = tightBounds
        ? (filled
              ? path.getBounds()
              : path.getBounds().inflate(strokeWidth / 2))
        : const Rect.fromLTWH(0, 0, 24, 24);
    final scale = math.min(
      size.width / sourceBounds.width,
      size.height / sourceBounds.height,
    );
    canvas
      ..save()
      ..translate(
        (size.width - sourceBounds.width * scale) / 2 -
            sourceBounds.left * scale,
        (size.height - sourceBounds.height * scale) / 2 -
            sourceBounds.top * scale,
      )
      ..scale(scale, scale);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppVectorGlyphPainter oldDelegate) =>
      oldDelegate.name != name ||
      oldDelegate.color != color ||
      oldDelegate.tightBounds != tightBounds;
}

Path _glyphPath(String name) => switch (name) {
  'target' => _target(),
  'compass' => _compass(),
  'rosette' => _rosette(),
  'spark' => _polygon(const <Offset>[
    Offset(12, 2),
    Offset(14.8, 9.2),
    Offset(22, 12),
    Offset(14.8, 14.8),
    Offset(12, 22),
    Offset(9.2, 14.8),
    Offset(2, 12),
    Offset(9.2, 9.2),
  ]),
  'vault' => _vault(),
  'edit' => _edit(),
  'quill' => _quill(),
  'data' => _data(),
  'profile' => _profile(),
  'flask' => _flask(),
  'pot' => _pot(),
  'processing' => _processing(),
  'book' => _book(),
  'branch' => _branch(),
  'image' => _image(),
  'trash' => _trash(),
  'info' => _info(),
  'error' => _error(),
  'calc' => _calc(),
  'check' => _check(),
  'minimize' =>
    Path()
      ..moveTo(5, 11)
      ..lineTo(19, 11)
      ..lineTo(19, 13)
      ..lineTo(5, 13)
      ..close(),
  'maximize' => Path()..addRect(const Rect.fromLTRB(6, 6, 18, 18)),
  'restore' =>
    Path()
      ..moveTo(8, 6)
      ..lineTo(18, 6)
      ..lineTo(18, 16)
      ..lineTo(16, 16)
      ..addRect(const Rect.fromLTRB(6, 8, 16, 18)),
  'close' =>
    Path()
      ..moveTo(6, 6)
      ..lineTo(18, 18)
      ..moveTo(18, 6)
      ..lineTo(6, 18),
  'add' =>
    Path()
      ..moveTo(12, 5)
      ..lineTo(12, 19)
      ..moveTo(5, 12)
      ..lineTo(19, 12),
  'reset' => _reset(),
  'star' => _polygon(const <Offset>[
    Offset(12, 3),
    Offset(14.7, 8.5),
    Offset(20.8, 9.4),
    Offset(16.4, 13.7),
    Offset(17.5, 19.8),
    Offset(12, 16.9),
    Offset(6.5, 19.8),
    Offset(7.6, 13.7),
    Offset(3.2, 9.4),
    Offset(9.3, 8.5),
  ]),
  'chevron-down' =>
    Path()
      ..moveTo(6, 9)
      ..lineTo(12, 15)
      ..lineTo(18, 9),
  'chevron-up' =>
    Path()
      ..moveTo(6, 15)
      ..lineTo(12, 9)
      ..lineTo(18, 15),
  'blur' => _blur(),
  'swap' => _swap(),
  _ =>
    Path()
      ..moveTo(12, 5)
      ..lineTo(12, 19)
      ..moveTo(5, 12)
      ..lineTo(19, 12),
};

Path _polygon(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

Path _branch() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(6, 5), radius: 2))
  ..addOval(Rect.fromCircle(center: const Offset(18, 8), radius: 2))
  ..addOval(Rect.fromCircle(center: const Offset(18, 18), radius: 2))
  ..moveTo(6, 7)
  ..lineTo(6, 16)
  ..quadraticBezierTo(6, 18, 8, 18)
  ..lineTo(16, 18)
  ..moveTo(6, 11)
  ..quadraticBezierTo(6, 8, 10, 8)
  ..lineTo(16, 8);

Path _target() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
  ..moveTo(12, 7)
  ..lineTo(12, 17)
  ..moveTo(7, 12)
  ..lineTo(17, 12);

Path _compass() => Path()
  ..moveTo(12, 2)
  ..lineTo(14.5, 9.5)
  ..lineTo(22, 12)
  ..lineTo(14.5, 14.5)
  ..lineTo(12, 22)
  ..lineTo(9.5, 14.5)
  ..lineTo(2, 12)
  ..lineTo(9.5, 9.5)
  ..close()
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 5))
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 2));

Path _rosette() => Path()
  ..moveTo(12, 12)
  ..cubicTo(9, 10, 9, 6, 12, 3)
  ..cubicTo(15, 6, 15, 10, 12, 12)
  ..cubicTo(14, 9, 18, 9, 21, 12)
  ..cubicTo(18, 15, 14, 15, 12, 12)
  ..cubicTo(15, 14, 15, 18, 12, 21)
  ..cubicTo(9, 18, 9, 14, 12, 12)
  ..cubicTo(10, 15, 6, 15, 3, 12)
  ..cubicTo(6, 9, 10, 9, 12, 12)
  ..cubicTo(12, 8, 15, 5, 18, 6)
  ..cubicTo(19, 9, 16, 12, 12, 12)
  ..cubicTo(16, 12, 19, 15, 18, 18)
  ..cubicTo(15, 19, 12, 16, 12, 12)
  ..cubicTo(12, 16, 9, 19, 6, 18)
  ..cubicTo(5, 15, 8, 12, 12, 12)
  ..cubicTo(8, 12, 5, 9, 6, 6)
  ..cubicTo(9, 5, 12, 8, 12, 12)
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 3));

Path _vault() => Path()
  ..addRect(const Rect.fromLTRB(4, 5, 20, 19))
  ..moveTo(8, 9)
  ..lineTo(16, 9)
  ..moveTo(8, 13)
  ..lineTo(16, 13)
  ..moveTo(12, 5)
  ..lineTo(12, 19);

Path _edit() => Path()
  ..moveTo(5, 18)
  ..lineTo(6.2, 13.6)
  ..lineTo(15.8, 4)
  ..lineTo(20, 8.2)
  ..lineTo(10.4, 17.8)
  ..close()
  ..moveTo(14.5, 5.3)
  ..lineTo(18.7, 9.5);

Path _quill() => Path()
  ..moveTo(4, 21)
  ..cubicTo(7, 15, 11, 8, 20, 3)
  ..cubicTo(20, 9, 17, 16, 9, 19)
  ..moveTo(5, 20)
  ..lineTo(3, 22)
  ..moveTo(8, 17)
  ..lineTo(17, 7)
  ..moveTo(9, 14)
  ..lineTo(14, 14)
  ..moveTo(11, 11)
  ..lineTo(16, 11)
  ..moveTo(13, 8)
  ..lineTo(18, 8);

Path _data() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 5))
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 1));

Path _profile() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(12, 8), radius: 4))
  ..moveTo(4.5, 21)
  ..cubicTo(4.8, 16.5, 7.7, 14, 12, 14)
  ..cubicTo(16.3, 14, 19.2, 16.5, 19.5, 21);

Path _flask() => Path()
  ..moveTo(9, 3)
  ..lineTo(15, 3)
  ..moveTo(10, 3)
  ..lineTo(10, 8.8)
  ..lineTo(5.4, 17.3)
  ..cubicTo(4.3, 19.4, 5.7, 21, 8.1, 21)
  ..lineTo(15.9, 21)
  ..cubicTo(18.3, 21, 19.7, 19.4, 18.6, 17.3)
  ..lineTo(14, 8.8)
  ..lineTo(14, 3)
  ..moveTo(8, 15.5)
  ..lineTo(16, 15.5);

Path _pot() => Path()
  ..moveTo(6, 10)
  ..lineTo(18, 10)
  ..lineTo(18, 15.5)
  ..cubicTo(18, 19, 15.8, 21, 12, 21)
  ..cubicTo(8.2, 21, 6, 19, 6, 15.5)
  ..close()
  ..moveTo(8, 10)
  ..cubicTo(8.5, 7.6, 15.5, 7.6, 16, 10)
  ..moveTo(4, 12)
  ..lineTo(6, 12)
  ..moveTo(18, 12)
  ..lineTo(20, 12);

Path _processing() => Path()
  ..moveTo(12, 3)
  ..lineTo(19, 7)
  ..lineTo(19, 15)
  ..lineTo(12, 19)
  ..lineTo(5, 15)
  ..lineTo(5, 7)
  ..close()
  ..moveTo(12, 3)
  ..lineTo(12, 11)
  ..moveTo(19, 7)
  ..lineTo(12, 11)
  ..lineTo(5, 7)
  ..moveTo(8.2, 13.4)
  ..lineTo(12, 15.6)
  ..lineTo(15.8, 13.4);

Path _book() => Path()
  ..addRect(const Rect.fromLTRB(4, 6, 6, 8))
  ..moveTo(8, 7)
  ..lineTo(20, 7)
  ..addRect(const Rect.fromLTRB(4, 11, 6, 13))
  ..moveTo(8, 12)
  ..lineTo(20, 12)
  ..addRect(const Rect.fromLTRB(4, 16, 6, 18))
  ..moveTo(8, 17)
  ..lineTo(20, 17);

Path _image() => Path()
  ..addRect(const Rect.fromLTRB(4, 5, 20, 19))
  ..moveTo(7.5, 15)
  ..lineTo(10.2, 12.2)
  ..lineTo(12.6, 14.7)
  ..lineTo(15.4, 10.8)
  ..lineTo(19, 15)
  ..addOval(Rect.fromCircle(center: const Offset(8, 10), radius: 1.5));

Path _trash() => Path()
  ..moveTo(5, 7)
  ..lineTo(19, 7)
  ..moveTo(9, 7)
  ..lineTo(9, 5)
  ..lineTo(15, 5)
  ..lineTo(15, 7)
  ..moveTo(8, 10)
  ..lineTo(8, 18)
  ..moveTo(12, 10)
  ..lineTo(12, 18)
  ..moveTo(16, 10)
  ..lineTo(16, 18)
  ..moveTo(7, 7)
  ..lineTo(8, 21)
  ..lineTo(16, 21)
  ..lineTo(17, 7);

Path _info() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
  ..moveTo(12, 10)
  ..lineTo(12, 17)
  ..moveTo(12, 7)
  ..lineTo(12, 8);

Path _error() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
  ..moveTo(12, 7)
  ..lineTo(12, 14)
  ..moveTo(12, 16)
  ..lineTo(12, 17);

Path _calc() => Path()
  ..addRect(const Rect.fromLTRB(6, 3, 18, 21))
  ..addRect(const Rect.fromLTRB(8.5, 6, 15.5, 9))
  ..moveTo(8.5, 12)
  ..lineTo(10.5, 12)
  ..moveTo(13, 12)
  ..lineTo(15, 12)
  ..moveTo(8.5, 15)
  ..lineTo(10.5, 15)
  ..moveTo(13, 15)
  ..lineTo(15, 15)
  ..moveTo(8.5, 18)
  ..lineTo(10.5, 18)
  ..moveTo(13, 18)
  ..lineTo(15, 18);

Path _check() => Path()
  ..moveTo(5, 12.5)
  ..lineTo(10, 17.5)
  ..lineTo(19, 7);

Path _reset() => Path()
  ..moveTo(7, 7)
  ..cubicTo(10, 4, 16, 4, 19, 8)
  ..moveTo(19, 8)
  ..lineTo(19, 4)
  ..moveTo(19, 8)
  ..lineTo(15, 8)
  ..moveTo(17, 17)
  ..cubicTo(14, 20, 8, 20, 5, 16)
  ..moveTo(5, 16)
  ..lineTo(5, 20)
  ..moveTo(5, 16)
  ..lineTo(9, 16);

Path _blur() => Path()
  ..moveTo(7, 7)
  ..cubicTo(10, 4, 14, 4, 17, 7)
  ..moveTo(5, 12)
  ..cubicTo(9, 9, 15, 9, 19, 12)
  ..moveTo(7, 17)
  ..cubicTo(10, 20, 14, 20, 17, 17);

Path _swap() => Path()
  ..moveTo(7, 7)
  ..lineTo(17, 7)
  ..moveTo(14, 4)
  ..lineTo(17, 7)
  ..lineTo(14, 10)
  ..moveTo(17, 17)
  ..lineTo(7, 17)
  ..moveTo(10, 14)
  ..lineTo(7, 17)
  ..lineTo(10, 20);
