import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Build-only comparison; no preferences, runtime toggles or default changes.
/// Use only for the isolated Resource Map cold-start display investigation.
const diagnosticEarlierResourcePillPaint = bool.fromEnvironment(
  'BSL_DIAGNOSTIC_EARLIER_RESOURCE_PILL_PAINT',
);

// Painters from the 2026-10-18 09:44 Pill checkpoint. Geometry and children
// remain owned by today's ResourceMapPill. This is not a confirmed display fix.
/// A narrow upper lens and lower contact lip make the option feel raised.
/// Both sit behind content and follow material opacity, never child opacity.
class EarlierResourcePillLens extends CustomPainter {
  const EarlierResourcePillLens({
    required this.light,
    required this.shade,
    required this.strength,
    required this.pressed,
  });

  final Color light;
  final Color shade;
  final double strength;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final lens = Rect.fromLTWH(
      1,
      1,
      size.width - 2,
      math.min(17, size.height / 3),
    );
    canvas.drawRect(
      lens,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(
              light,
              Colors.white,
              .58,
            )!.withValues(alpha: (pressed ? .045 : .14) * strength),
            light.withValues(alpha: 0),
          ],
        ).createShader(lens),
    );
    final lip = Rect.fromLTWH(1, size.height - 5, size.width - 2, 4);
    canvas.drawRect(
      lip,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            shade.withValues(alpha: 0),
            Color.lerp(
              shade,
              Colors.black,
              .65,
            )!.withValues(alpha: (pressed ? .09 : .26) * strength),
          ],
        ).createShader(lip),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant EarlierResourcePillLens oldDelegate) =>
      light != oldDelegate.light ||
      shade != oldDelegate.shade ||
      strength != oldDelegate.strength ||
      pressed != oldDelegate.pressed;
}

/// The edge distinguishes selection from hover without another filled plane.
/// Painting never adds a hit target or a continuously running animation.
class EarlierResourcePillEdge extends CustomPainter {
  const EarlierResourcePillEdge({
    required this.color,
    required this.strength,
    required this.selected,
    required this.focused,
    required this.hovered,
    required this.pressed,
  });

  final Color color;
  final double strength;
  final bool selected;
  final bool focused;
  final bool hovered;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final bounds = (Offset.zero & size).deflate(1.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              color,
              Colors.white,
              .7,
            )!.withValues(alpha: (pressed ? .10 : .46) * strength),
            color.withValues(alpha: .05 * strength),
            Colors.black.withValues(alpha: .34 * strength),
          ],
          stops: const [0, .46, 1],
        ).createShader(bounds),
    );
    if (selected) {
      final height = math.min(26.0, size.height - 18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1.5, (size.height - height) / 2, 2.5, height),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
    }
    if (selected || hovered || focused) {
      final rect = Rect.fromLTWH(10, 1.5, size.width - 20, 1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: .65 * strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    if (focused || pressed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(3),
          const Radius.circular(7),
        ),
        Paint()
          ..color = color.withValues(alpha: focused ? 1 : .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant EarlierResourcePillEdge oldDelegate) =>
      color != oldDelegate.color ||
      strength != oldDelegate.strength ||
      selected != oldDelegate.selected ||
      focused != oldDelegate.focused ||
      hovered != oldDelegate.hovered ||
      pressed != oldDelegate.pressed;
}
