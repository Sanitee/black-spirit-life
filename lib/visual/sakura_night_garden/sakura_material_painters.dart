import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';
import 'sakura_spec.dart';

/// Deterministic blackened-cedar grain for the Sakura backdrop and sidebar.
///
/// No random source or animation clock is used, so captures remain stable.
class SakuraCedarGrainPainter extends CustomPainter {
  const SakuraCedarGrainPainter({
    this.sidebar = false,
    this.highlight = const Color(0x167F625C),
    this.shadow = const Color(0x26000000),
    this.density = 1,
  });

  final bool sidebar;
  final Color highlight;
  final Color shadow;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    final resolvedDensity = density.clamp(0.25, 2).toDouble();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _paintStainedBands(canvas, size, resolvedDensity);
    _paintBrokenGrain(canvas, size, resolvedDensity);
    _paintKnots(canvas, size, resolvedDensity);
    _paintPores(canvas, size, resolvedDensity);
    _paintVignette(canvas, size);
    canvas.restore();
  }

  double _axisLength(Size size) => sidebar ? size.height : size.width;

  double _crossLength(Size size) => sidebar ? size.width : size.height;

  Offset _point(double along, double across) =>
      sidebar ? Offset(across, along) : Offset(along, across);

  Offset get _highlightShift =>
      sidebar ? const Offset(-0.8, 0) : const Offset(0, -0.8);

  Color _scaledAlpha(Color color, double scale) =>
      color.withAlpha((color.a * 255 * scale).round().clamp(0, 255));

  void _paintStainedBands(Canvas canvas, Size size, double resolvedDensity) {
    final axis = _axisLength(size);
    final cross = _crossLength(size);
    final count = ((cross / 43) * resolvedDensity).round().clamp(4, 18);
    for (var index = 0; index < count; index++) {
      final phase = index * 1.37 + (index % 3) * 0.41;
      final spacing = cross / count;
      final center = (index + 0.48 + math.sin(index * 2.11) * 0.14) * spacing;
      final wander = 2.8 + (index % 5) * 1.15;
      final path = Path();
      var previousAlong = -24.0;
      var previousCross = center + math.sin(phase) * wander;
      final first = _point(previousAlong, previousCross);
      path.moveTo(first.dx, first.dy);
      const segments = 7;
      for (var segment = 1; segment <= segments; segment++) {
        final along = -24 + (axis + 48) * segment / segments;
        final across =
            center +
            math.sin(phase + segment * 0.91) * wander +
            math.sin(phase * 0.63 + segment * 1.79) * wander * 0.28;
        final control = _point(
          (previousAlong + along) / 2,
          (previousCross + across) / 2 +
              math.cos(phase + segment * 0.74) * wander * 0.34,
        );
        final target = _point(along, across);
        path.quadraticBezierTo(control.dx, control.dy, target.dx, target.dy);
        previousAlong = along;
        previousCross = across;
      }

      final bandWidth = math
          .max(5.5, spacing * (0.25 + (index % 4) * 0.035))
          .toDouble();
      canvas.drawPath(
        path,
        Paint()
          ..color = _scaledAlpha(shadow, 0.62 + (index % 3) * 0.11)
          ..style = PaintingStyle.stroke
          ..strokeWidth = bandWidth
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path.shift(_highlightShift),
        Paint()
          ..color = _scaledAlpha(highlight, 0.48 + (index % 2) * 0.13)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, bandWidth * 0.22)
          ..strokeCap = StrokeCap.round,
      );
      if (index % 3 == 1) {
        canvas.drawPath(
          path.shift(
            sidebar ? Offset(bandWidth * 0.24, 0) : Offset(0, bandWidth * 0.24),
          ),
          Paint()
            ..color = _scaledAlpha(shadow, 0.72)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.55
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  void _paintBrokenGrain(Canvas canvas, Size size, double resolvedDensity) {
    final axis = _axisLength(size);
    final cross = _crossLength(size);
    final count = ((cross / 15) * resolvedDensity).round().clamp(10, 58);
    final dark = Paint()
      ..color = _scaledAlpha(shadow, 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.72
      ..strokeCap = StrokeCap.round;
    final light = Paint()
      ..color = _scaledAlpha(highlight, 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.46
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < count; index++) {
      final seedA = (index * 151 + index * index * 17) % 997;
      final seedB = (index * 83 + index * index * 29) % 991;
      final startAlong = seedA / 997 * math.max(1, axis - 14) - 5;
      final across = seedB / 991 * cross;
      final length = math.min(
        axis * 0.24,
        24 + (index % 8) * 9.5 + (seedB % 17),
      );
      final bend = (index % 5 - 2) * 0.58;
      final start = _point(startAlong, across);
      final control = _point(
        startAlong + length * 0.46,
        across + bend + math.sin(index * 1.71) * 1.4,
      );
      final end = _point(
        startAlong + length,
        across + math.sin(index * 0.87) * 2.2,
      );
      final grain = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      canvas.drawPath(grain, index % 4 == 0 ? light : dark);

      if (index % 3 == 0) {
        final splitStart = _point(
          startAlong + length * 0.58,
          across + math.sin(index * 0.87) * 1.2,
        );
        final splitControl = _point(
          startAlong + length * 0.78,
          across + (index.isEven ? -3.2 : 3.2),
        );
        final splitEnd = _point(
          startAlong + length * 0.96,
          across + (index.isEven ? -4.8 : 4.8),
        );
        final split = Path()
          ..moveTo(splitStart.dx, splitStart.dy)
          ..quadraticBezierTo(
            splitControl.dx,
            splitControl.dy,
            splitEnd.dx,
            splitEnd.dy,
          );
        canvas.drawPath(split, dark..strokeWidth = 0.56);
        dark.strokeWidth = 0.72;
      }
    }
  }

  void _paintKnots(Canvas canvas, Size size, double resolvedDensity) {
    final axis = _axisLength(size);
    final cross = _crossLength(size);
    final area = size.width * size.height;
    final count = ((area / 70000) * resolvedDensity).round().clamp(1, 8);
    for (var index = 0; index < count; index++) {
      final along =
          (0.12 + ((index * 347 + index * index * 31) % 997) / 997 * 0.76) *
          axis;
      final across = (0.1 + ((index * 191 + 73) % 983) / 983 * 0.8) * cross;
      final center = _point(along, across);
      final alongDiameter = 8.5 + (index % 4) * 2.4;
      final crossDiameter = 3.8 + (index % 3) * 1.25;
      final outer = Rect.fromCenter(
        center: center,
        width: sidebar ? crossDiameter : alongDiameter,
        height: sidebar ? alongDiameter : crossDiameter,
      );
      final knotShadow = Paint()
        ..color = _scaledAlpha(shadow, 1.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15;
      final knotLight = Paint()
        ..color = _scaledAlpha(highlight, 1.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55;
      canvas.drawOval(outer, knotShadow);
      canvas.drawOval(
        outer.deflate(1.35).shift(_highlightShift * 0.5),
        knotLight,
      );
      final slitStart = _point(along - alongDiameter * 0.27, across);
      final slitEnd = _point(
        along + alongDiameter * 0.27,
        across + (index.isEven ? 0.7 : -0.7),
      );
      canvas.drawLine(
        slitStart,
        slitEnd,
        knotShadow
          ..strokeWidth = 0.62
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintPores(Canvas canvas, Size size, double resolvedDensity) {
    final area = size.width * size.height;
    final poreCount = ((area / 12500) * resolvedDensity).round().clamp(7, 42);
    final light = Paint()
      ..color = _scaledAlpha(highlight, 0.68)
      ..strokeWidth = 0.48
      ..strokeCap = StrokeCap.round;
    final dark = Paint()
      ..color = _scaledAlpha(shadow, 0.76)
      ..strokeWidth = 0.58
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < poreCount; index++) {
      final x = ((index * 149 + index * index * 11) % 997) / 997 * size.width;
      final y = ((index * 83 + index * index * 17) % 991) / 991 * size.height;
      final longAxis = 0.9 + (index % 5) * 0.46;
      final delta = sidebar
          ? Offset((index % 3 - 1) * 0.16, longAxis)
          : Offset(longAxis, (index % 3 - 1) * 0.16);
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y) + delta,
        index.isEven ? dark : light,
      );
    }
  }

  void _paintVignette(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.22, -0.3),
          radius: 1.28,
          colors: <Color>[Colors.transparent, Color(0x27000000)],
          stops: <double>[0.44, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: sidebar ? Alignment.centerLeft : Alignment.topCenter,
          end: sidebar ? Alignment.centerRight : Alignment.bottomCenter,
          colors: const <Color>[
            Color(0x24000000),
            Colors.transparent,
            Colors.transparent,
            Color(0x1C000000),
          ],
          stops: const <double>[0, 0.08, 0.82, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SakuraCedarGrainPainter oldDelegate) =>
      oldDelegate.sidebar != sidebar ||
      oldDelegate.highlight != highlight ||
      oldDelegate.shadow != shadow ||
      oldDelegate.density != density;
}

/// Restrained deterministic weave and inset line for plum-lacquer surfaces.
class SakuraPlumMaterialPainter extends CustomPainter {
  const SakuraPlumMaterialPainter({
    this.radius = 6,
    this.strength = 1,
    this.drawInnerRule = true,
    this.depressed = false,
    this.accented = false,
  });

  final double radius;
  final double strength;
  final bool drawInnerRule;
  final bool depressed;
  final bool accented;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) return;
    final resolvedStrength = strength.clamp(0, 2).toDouble();
    final bounds = Offset.zero & size;
    final clip = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(radius.clamp(0, math.min(size.width, size.height) / 2)),
    );
    canvas.save();
    canvas.clipRRect(clip);

    _paintFaceLighting(canvas, bounds, resolvedStrength);
    _paintMicrograin(canvas, size, resolvedStrength);
    _paintEdgeDepth(canvas, bounds, resolvedStrength);
    canvas.restore();
  }

  void _paintFaceLighting(Canvas canvas, Rect bounds, double resolvedStrength) {
    final topAlpha =
        ((depressed
                    ? 10
                    : accented
                    ? 32
                    : 22) *
                resolvedStrength)
            .round()
            .clamp(0, 255);
    final bottomAlpha = ((depressed ? 58 : 42) * resolvedStrength)
        .round()
        .clamp(0, 255);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.fromARGB(topAlpha, 245, 202, 211),
            const Color(0x00000000),
            const Color(0x00000000),
            Color.fromARGB(bottomAlpha, 0, 0, 0),
          ],
          stops: const <double>[0, 0.17, 0.57, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.42),
          radius: 1.18,
          colors: <Color>[
            Color.fromARGB(
              (11 * resolvedStrength).round().clamp(0, 255),
              239,
              188,
              202,
            ),
            const Color(0x00000000),
            Color.fromARGB(
              (24 * resolvedStrength).round().clamp(0, 255),
              0,
              0,
              0,
            ),
          ],
          stops: const <double>[0, 0.56, 1],
        ).createShader(bounds),
    );
  }

  void _paintMicrograin(Canvas canvas, Size size, double resolvedStrength) {
    final area = size.width * size.height;
    final count = (area / 520).round().clamp(7, 38);
    final light = Paint()
      ..color = Color.fromARGB(
        (16 * resolvedStrength).round().clamp(0, 255),
        246,
        219,
        218,
      )
      ..strokeWidth = 0.46
      ..strokeCap = StrokeCap.round;
    final dark = Paint()
      ..color = Color.fromARGB(
        (32 * resolvedStrength).round().clamp(0, 255),
        0,
        0,
        0,
      )
      ..strokeWidth = 0.54
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < count; index++) {
      final x =
          2 +
          ((index * 67 + index * index * 23) % 983) /
              983 *
              math.max(1, size.width - 4);
      final y =
          2 +
          ((index * 131 + index * index * 7) % 977) /
              977 *
              math.max(1, size.height - 4);
      final length = 2.2 + (index % 5) * 1.35;
      final rise = (index % 4 - 1.5) * 0.27;
      final grain = Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + length * 0.48,
          y + rise + math.sin(index * 1.3) * 0.42,
          x + length,
          y + rise,
        );
      canvas.drawPath(grain, index % 4 == 0 ? light : dark);
      if (index % 6 == 2) {
        canvas.drawCircle(Offset(x + length * 0.3, y + 1.25), 0.38, dark);
      }
    }
  }

  void _paintEdgeDepth(Canvas canvas, Rect bounds, double resolvedStrength) {
    RRect rim(double inset) => RRect.fromRectAndRadius(
      bounds.deflate(inset),
      Radius.circular(math.max(0, radius - inset)),
    );

    canvas.drawRRect(
      rim(0.55),
      Paint()
        ..color = Color.fromARGB(
          (72 * resolvedStrength).round().clamp(0, 255),
          0,
          0,
          0,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45,
    );
    canvas.drawRRect(
      rim(1.35),
      Paint()
        ..color = Color.fromARGB(
          ((drawInnerRule ? 40 : 24) * resolvedStrength).round().clamp(0, 255),
          accented ? 239 : 207,
          accented ? 172 : 128,
          accented ? 191 : 148,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = drawInnerRule ? 0.72 : 0.52,
    );

    final inset = drawInnerRule ? 2.25 : 1.85;
    final left = bounds.left + inset;
    final right = bounds.right - inset;
    final top = bounds.top + inset;
    final bottom = bounds.bottom - inset;
    final lineRadius = math.min(radius, math.max(0, (right - left) / 3));
    final topRule = Path()
      ..moveTo(left + lineRadius, top)
      ..lineTo(right - lineRadius, top);
    final lowerRule = Path()
      ..moveTo(left + lineRadius, bottom)
      ..lineTo(right - lineRadius, bottom);
    canvas.drawPath(
      topRule,
      Paint()
        ..color = Color.fromARGB(
          ((depressed ? 11 : 50) * resolvedStrength).round().clamp(0, 255),
          247,
          206,
          210,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.62
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      lowerRule,
      Paint()
        ..color = Color.fromARGB(
          ((depressed ? 82 : 66) * resolvedStrength).round().clamp(0, 255),
          0,
          0,
          0,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = depressed ? 1.15 : 0.82
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SakuraPlumMaterialPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.strength != strength ||
      oldDelegate.drawInnerRule != drawInnerRule ||
      oldDelegate.depressed != depressed ||
      oldDelegate.accented != accented;
}

/// Fine left status stem and incised corner tooling for Sakura cards and rows.
class SakuraSurfaceToolingPainter extends CustomPainter {
  const SakuraSurfaceToolingPainter({
    this.tone = AppSurfaceTone.neutral,
    this.statusRail = true,
    this.cornerTooling = true,
  });

  final AppSurfaceTone tone;
  final bool statusRail;
  final bool cornerTooling;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 12 || size.height < 16) return;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
    );
    if (statusRail) _drawStatusRail(canvas, size);
    if (cornerTooling) _drawCornerTooling(canvas, size);
    canvas.restore();
  }

  void _drawStatusRail(Canvas canvas, Size size) {
    final top = math.min(7.0, size.height * 0.18);
    final bottom = math.max(top + 5, size.height - 7);
    final rail = Path()
      ..moveTo(2.35, top)
      ..cubicTo(2.1, size.height * 0.34, 2.8, size.height * 0.66, 2.4, bottom);
    canvas.drawPath(
      rail,
      Paint()
        ..color = const Color(0x8F070509)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.15
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      rail,
      Paint()
        ..color = SakuraNightGardenSpec.dustySakura.withAlpha(224)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.55
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      rail.shift(const Offset(-0.28, -0.08)),
      Paint()
        ..color = SakuraNightGardenSpec.paleBlossom.withAlpha(154)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..strokeCap = StrokeCap.round,
    );

    if (size.height < 28) return;
    final nodeY = (size.height * 0.31).clamp(top + 5, bottom - 5).toDouble();
    final twig = Path()
      ..moveTo(2.55, nodeY)
      ..quadraticBezierTo(5.0, nodeY - 2.4, 7.0, nodeY - 4.8);
    canvas.drawPath(
      twig,
      Paint()
        ..color = SakuraNightGardenSpec.barkCopper.withAlpha(212)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85
        ..strokeCap = StrokeCap.round,
    );
    _drawBud(canvas, Offset(7.35, nodeY - 5.1), _budColor);
  }

  Color get _budColor => switch (tone) {
    AppSurfaceTone.success => SakuraNightGardenSpec.mutedMoss,
    AppSurfaceTone.warning => SakuraNightGardenSpec.barkCopper,
    AppSurfaceTone.danger => SakuraNightGardenSpec.emberBerry,
    AppSurfaceTone.info => SakuraNightGardenSpec.paleBlossom,
    AppSurfaceTone.neutral => SakuraNightGardenSpec.dustySakura,
  };

  void _drawBud(Canvas canvas, Offset center, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - 2.25)
      ..cubicTo(
        center.dx + 1.65,
        center.dy - 1.45,
        center.dx + 1.3,
        center.dy + 0.8,
        center.dx,
        center.dy + 1.35,
      )
      ..cubicTo(
        center.dx - 1.3,
        center.dy + 0.8,
        center.dx - 1.65,
        center.dy - 1.45,
        center.dx,
        center.dy - 2.25,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color.withAlpha(222));
    canvas.drawPath(
      path,
      Paint()
        ..color = SakuraNightGardenSpec.paleBlossom.withAlpha(116)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45,
    );
  }

  void _drawCornerTooling(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SakuraNightGardenSpec.copperHighlight.withAlpha(94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    final topRight = Offset(size.width - 3, 3);
    canvas.drawLine(topRight.translate(-6, 0), topRight, paint);
    canvas.drawLine(topRight, topRight.translate(0, 6), paint);
    final bottomRight = Offset(size.width - 3, size.height - 3);
    canvas.drawLine(bottomRight.translate(-5, 0), bottomRight, paint);
    canvas.drawLine(bottomRight, bottomRight.translate(0, -5), paint);
    canvas.drawCircle(
      topRight.translate(-1.7, 1.7),
      0.75,
      Paint()..color = SakuraNightGardenSpec.dustySakura.withAlpha(116),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SakuraSurfaceToolingPainter oldDelegate) =>
      oldDelegate.tone != tone ||
      oldDelegate.statusRail != statusRail ||
      oldDelegate.cornerTooling != cornerTooling;
}

/// Paint-only pointed continuation for the active sidebar navigation plate.
///
/// The host follows the retained Ledger tab bounds, while the material and
/// tooling remain entirely Sakura-specific.
class SakuraNavigationTabPainter extends CustomPainter {
  const SakuraNavigationTabPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 24 || size.height < 22) return;
    final pointX = size.width - 2.5;
    final shoulderX = size.width - math.min(17.0, size.height * .4);
    final tab = Path()
      ..moveTo(shoulderX, 1.5)
      ..lineTo(pointX, size.height / 2)
      ..lineTo(shoulderX, size.height - 1.5)
      ..close();
    canvas.drawPath(
      tab,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF6B3C48),
            Color(0xFF4A2B36),
            Color(0xFF261A21),
          ],
          stops: <double>[0, .55, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      tab,
      Paint()
        ..color = SakuraNightGardenSpec.dustySakura.withAlpha(216)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9,
    );

    final centerY = size.height / 2;
    final twig = Path()
      ..moveTo(shoulderX - 1, centerY + 7)
      ..quadraticBezierTo(shoulderX + 5, centerY + 4, pointX - 5, centerY - 1);
    canvas.drawPath(
      twig,
      Paint()
        ..color = SakuraNightGardenSpec.copperHighlight.withAlpha(176)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(pointX - 5, centerY - 1.4),
        width: 2.8,
        height: 4.2,
      ),
      Paint()..color = SakuraNightGardenSpec.paleBlossom.withAlpha(212),
    );
    canvas.drawCircle(
      Offset(shoulderX + 3.5, centerY + 4.4),
      .8,
      Paint()..color = SakuraNightGardenSpec.dustySakura.withAlpha(214),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SakuraNavigationTabPainter oldDelegate) => false;
}
