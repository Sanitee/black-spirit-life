import 'package:flutter/material.dart';

/// A static navy field with a restrained teal atmosphere. No per-card blur,
/// ornament or animated lighting is needed beneath the opaque reading planes.
class OpportunityGlassBackdrop extends CustomPainter {
  const OpportunityGlassBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10232E), Color(0xFF0D1926), Color(0xFF0A1420)],
          stops: [0, .47, 1],
        ).createShader(rect),
    );
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .20, size.height * .12),
        width: size.width * 1.05,
        height: size.height * 1.35,
      ),
      const Color(0x282B6F70),
      const Color(0x102B5462),
    );
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .53, size.height * 1.03),
        width: size.width * .85,
        height: size.height * 1.10,
      ),
      const Color(0x122C6269),
      const Color(0x082B475B),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.15),
          radius: 1.1,
          colors: [Color(0x00030A18), Color(0x00030A18), Color(0x20030A18)],
          stops: [0, .52, 1],
        ).createShader(rect),
    );
  }

  void _light(Canvas canvas, Rect rect, Color center, Color shoulder) {
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [center, shoulder, center.withAlpha(0)],
          stops: const [0, .44, 1],
        ).createShader(rect),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant OpportunityGlassBackdrop oldDelegate) => false;
}
