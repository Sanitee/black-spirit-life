import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ledger_spec.dart';

/// Fine, non-interactive corner tooling used over raised vellum cards.
/// Geometry and paint values match the retained LedgerOrnamentFrameControl.
class LedgerOrnamentFramePainter extends CustomPainter {
  const LedgerOrnamentFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 28 || size.height < 24) return;
    final innerRule = Paint()
      ..color = const Color(0x699a7438)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    canvas.drawRect(
      Rect.fromLTWH(3.5, 3.5, size.width - 7, size.height - 7),
      innerRule,
    );

    final cornerPen = Paint()
      ..color = const Color(0xb5a77e2e)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final stud = Paint()
      ..color = const Color(0xc2b9903e)
      ..style = PaintingStyle.fill;
    void drawCorner(Offset origin, double dx, double dy) {
      canvas.drawLine(origin.translate(0, dy * 15), origin, cornerPen);
      canvas.drawLine(origin, origin.translate(dx * 15, 0), cornerPen);
      canvas.drawLine(
        origin.translate(dx * 4, dy * 10),
        origin.translate(dx * 10, dy * 4),
        cornerPen,
      );
      canvas.drawCircle(origin.translate(dx * 3.2, dy * 3.2), 1.45, stud);
    }

    drawCorner(const Offset(1.5, 1.5), 1, 1);
    drawCorner(Offset(size.width - 1.5, 1.5), -1, 1);
    drawCorner(Offset(1.5, size.height - 1.5), 1, -1);
    drawCorner(Offset(size.width - 1.5, size.height - 1.5), -1, -1);
  }

  @override
  bool shouldRepaint(covariant LedgerOrnamentFramePainter oldDelegate) => false;
}

/// Corner and inner-rule tooling for vellum surfaces.
class LedgerSurfaceToolingPainter extends CustomPainter {
  const LedgerSurfaceToolingPainter({required this.trim, this.inset = 4});

  final Color trim;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 12 || size.height < 12) return;
    final paint = Paint()
      ..color = trim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    canvas.drawRect(rect, paint);

    const arm = 8.0;
    final corners = <(Offset, double, double)>[
      (rect.topLeft, 1, 1),
      (rect.topRight, -1, 1),
      (rect.bottomLeft, 1, -1),
      (rect.bottomRight, -1, -1),
    ];
    for (final corner in corners) {
      final point = corner.$1;
      final sx = corner.$2;
      final sy = corner.$3;
      canvas.drawLine(point, point.translate(sx * arm, 0), paint);
      canvas.drawLine(point, point.translate(0, sy * arm), paint);
      canvas.drawCircle(point.translate(sx * 2.5, sy * 2.5), 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LedgerSurfaceToolingPainter oldDelegate) =>
      oldDelegate.trim != trim || oldDelegate.inset != inset;
}

/// Restrained inner line and diamond terminals used on manuscript controls.
class LedgerButtonToolingPainter extends CustomPainter {
  const LedgerButtonToolingPainter({required this.trim});

  final Color trim;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 16) return;
    final paint = Paint()
      ..color = trim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final y = size.height - 4.5;
    canvas.drawLine(
      const Offset(8, 0).translate(0, y),
      Offset(size.width - 8, y),
      paint,
    );
    for (final x in <double>[7, size.width - 7]) {
      final path = Path()
        ..moveTo(x, y - 2.2)
        ..lineTo(x + 2.2, y)
        ..lineTo(x, y + 2.2)
        ..lineTo(x - 2.2, y)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LedgerButtonToolingPainter oldDelegate) =>
      oldDelegate.trim != trim;
}

/// Pointed right marker and gold edge for the active lapis navigation slab.
class LedgerNavigationRibbonPainter extends CustomPainter {
  const LedgerNavigationRibbonPainter({
    required this.trim,
    required this.lapisLight,
    required this.lapisDeep,
  });

  final Color trim;
  final Color lapisLight;
  final Color lapisDeep;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 30 || size.height < 22) return;
    final pointX = size.width - 3;
    final shoulderX = size.width - math.min(18.0, size.height * .42);
    final path = Path()
      ..moveTo(shoulderX, 2.5)
      ..lineTo(pointX, size.height / 2)
      ..lineTo(shoulderX, size.height - 2.5)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[lapisLight, lapisDeep],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = trim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawLine(
      Offset(5, 3.5),
      Offset(shoulderX - 2, 3.5),
      Paint()
        ..color = trim.withAlpha(112)
        ..strokeWidth = .8,
    );
    canvas.drawLine(
      Offset(5, size.height - 3.5),
      Offset(shoulderX - 2, size.height - 3.5),
      Paint()
        ..color = trim.withAlpha(86)
        ..strokeWidth = .8,
    );
    for (final point in <Offset>[
      const Offset(6, 6),
      Offset(6, size.height - 6),
    ]) {
      canvas.drawCircle(point, 1.3, Paint()..color = trim);
    }
  }

  @override
  bool shouldRepaint(covariant LedgerNavigationRibbonPainter oldDelegate) =>
      oldDelegate.trim != trim ||
      oldDelegate.lapisLight != lapisLight ||
      oldDelegate.lapisDeep != lapisDeep;
}

/// Scalloped, pressed olive-wax medallion used for P08 completion.
class LedgerWaxSealPainter extends CustomPainter {
  const LedgerWaxSealPainter({
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
  });

  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 10 || size.height < 10) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .43;
    final scale = pressed ? .94 : 1.0;
    final sealPath = Path();
    const lobes = 18;
    for (var index = 0; index < lobes * 2; index++) {
      final angle = -math.pi / 2 + index * math.pi / lobes;
      final irregular = index.isEven ? 1.0 : .86 + (index % 6) * .012;
      final point =
          center +
          Offset(math.cos(angle), math.sin(angle)) * radius * irregular * scale;
      if (index == 0) {
        sealPath.moveTo(point.dx, point.dy);
      } else {
        sealPath.lineTo(point.dx, point.dy);
      }
    }
    sealPath.close();

    canvas.drawPath(
      sealPath.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x66352516)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    final sealRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawPath(
      sealPath,
      Paint()
        ..shader =
            (enabled
                    ? IlluminatedLedgerSpec.waxGradient
                    : const RadialGradient(
                        colors: <Color>[
                          Color(0xFFB3A982),
                          Color(0xFF776E51),
                          Color(0xFF49442F),
                        ],
                      ))
                .createShader(sealRect),
    );
    final gold = focused
        ? IlluminatedLedgerSpec.palette.trimBright
        : IlluminatedLedgerSpec.palette.trim;
    canvas.drawPath(
      sealPath,
      Paint()
        ..color = gold.withAlpha(enabled ? 230 : 112)
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 2 : 1.15,
    );
    for (final ring in <(double, double)>[(.66, 1.15), (.49, .72)]) {
      canvas.drawCircle(
        center,
        radius * ring.$1,
        Paint()
          ..color = const Color(
            0xFFD6B45A,
          ).withAlpha(enabled ? (hovered ? 210 : 148) : 72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.$2,
      );
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * .76),
      math.pi * 1.08,
      math.pi * .45,
      false,
      Paint()
        ..color = const Color(0xAAFFF0C9)
        ..strokeWidth = hovered ? 2.4 : 1.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    for (var index = 0; index < 8; index++) {
      final angle = index * math.pi / 4 + .18;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius * .74,
        .7 + (index % 2) * .25,
        Paint()..color = const Color(0x5034491F),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LedgerWaxSealPainter oldDelegate) =>
      oldDelegate.enabled != enabled ||
      oldDelegate.hovered != hovered ||
      oldDelegate.pressed != pressed ||
      oldDelegate.focused != focused;
}

class LedgerSectionRulePainter extends CustomPainter {
  const LedgerSectionRulePainter({required this.trim});

  final Color trim;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final y = size.height / 2;
    final paint = Paint()
      ..color = trim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset.zero.translate(9, y),
      Offset(size.width - 9, y),
      paint,
    );
    for (final x in <double>[4.5, size.width - 4.5]) {
      final path = Path()
        ..moveTo(x, y - 3)
        ..lineTo(x + 3, y)
        ..lineTo(x, y + 3)
        ..lineTo(x - 3, y)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LedgerSectionRulePainter oldDelegate) =>
      oldDelegate.trim != trim;
}
