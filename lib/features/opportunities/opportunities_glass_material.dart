import 'package:flutter/material.dart';
import 'opportunity_glass_finish.dart';

/// A small recessed display mount. Original item artwork remains unobscured;
/// the light and contact edge are painted only in its surrounding margin.
class OpportunityItemMountPainter extends CustomPainter {
  const OpportunityItemMountPainter({required this.finish});
  final OpportunityGlassFinish finish;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide < 8) return;
    final rect = (Offset.zero & size).deflate(.5);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(finish.railLight.withAlpha(95), finish.top),
            Color.lerp(
              finish.bottom,
              Colors.black,
              finish.lightSurface ? .04 : .22,
            )!,
            Color.alphaBlend(finish.accent.withAlpha(32), finish.bottom),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            finish.railLight.withAlpha(210),
            finish.edge.withAlpha(45),
            finish.accent.withAlpha(75),
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    // Only the surrounding four-pixel mount changes; artwork stays intact.
    canvas.drawRRect(
      shape.deflate(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withAlpha(finish.lightSurface ? 65 : 180),
            Colors.black.withAlpha(25),
            finish.railLight.withAlpha(100),
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    final underline = Rect.fromLTWH(
      size.width * .25,
      size.height - 2,
      size.width * .5,
      1,
    );
    canvas.drawRect(
      underline,
      Paint()
        ..shader = LinearGradient(
          colors: [
            finish.accent.withAlpha(0),
            finish.accent.withAlpha(205),
            finish.accent.withAlpha(0),
          ],
        ).createShader(underline),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant OpportunityItemMountPainter oldDelegate) =>
      oldDelegate.finish != finish;
}

/// The existing artwork column becomes a separate material plane, without
/// allocating any space or drawing behind the figures in the reading column.
class OpportunityCraftCardRelief extends CustomPainter {
  const OpportunityCraftCardRelief({
    required this.finish,
    this.artworkWidth = 80,
  });

  final OpportunityGlassFinish finish;
  final double artworkWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= artworkWidth || size.height < 8) return;
    final rect = Offset.zero & size;
    final bay = Rect.fromLTWH(0, 0, artworkWidth, size.height);
    final lightSurface = finish.lightSurface;
    final metal = Color.lerp(
      finish.top,
      finish.railLight,
      lightSurface ? .30 : .42,
    )!;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    canvas.drawRect(
      bay,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -.45),
          end: const Alignment(1, .80),
          colors: [
            Color.lerp(metal, finish.bottom, .24)!,
            Color.lerp(metal, Colors.white, lightSurface ? .24 : .12)!,
            metal,
            Color.lerp(metal, finish.bottom, lightSurface ? .34 : .49)!,
          ],
          stops: const [0, .14, .45, 1],
        ).createShader(bay),
    );
    // One bounded path for the satin grain, confined to the artwork material.
    // Nothing is animated or painted across the names and financial values.
    final grain = Path();
    for (double y = 2; y < size.height && y < 1200; y += 3) {
      grain.moveTo(2, y);
      grain.lineTo(artworkWidth - 3, y);
    }
    canvas.drawPath(
      grain,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..shader = LinearGradient(
          colors: [
            Colors.white.withAlpha(lightSurface ? 25 : 18),
            finish.railLight.withAlpha(4),
          ],
        ).createShader(bay),
    );
    final seam = Rect.fromLTWH(artworkWidth - 3, 0, 3, size.height);
    canvas.drawRect(
      seam,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black.withAlpha(lightSurface ? 48 : 110),
          ],
        ).createShader(seam),
    );
    canvas.drawLine(
      Offset(artworkWidth - .5, 0),
      Offset(artworkWidth - .5, size.height),
      Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            finish.railLight.withAlpha(225),
            finish.railLight.withAlpha(125),
            finish.edge.withAlpha(60),
          ],
          stops: const [0, .5, 1],
        ).createShader(bay),
    );
    final ledge = Rect.fromLTWH(18, size.height - 8, artworkWidth - 36, 1);
    canvas.drawRect(
      ledge,
      Paint()
        ..shader = LinearGradient(
          colors: [
            finish.railLight.withAlpha(0),
            finish.railLight.withAlpha(210),
            finish.railLight.withAlpha(0),
          ],
        ).createShader(ledge),
    );
    canvas.restore();
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant OpportunityCraftCardRelief oldDelegate) =>
      oldDelegate.finish != finish || oldDelegate.artworkWidth != artworkWidth;
}

/// A light-catching rim, not a second frame. All strokes stay within the
/// existing boundary and the centre stays completely clear of text and input.
class OpportunityGlassBevel extends CustomPainter {
  const OpportunityGlassBevel({
    required this.light,
    this.radius = 12,
    this.strength = 1,
    this.inset = false,
    this.raisedLip = false,
    this.lightSurface = false,
  });

  final Color light;
  final double radius, strength;
  final bool inset;
  final bool raisedLip, lightSurface;

  Color _light(int alpha) => light.withAlpha((alpha * strength).round());
  Color _dark(int alpha) => Colors.black.withAlpha((alpha * strength).round());

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide < 4) return;
    final rect = (Offset.zero & size).deflate(.5);
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // Lit top, quiet sides, dark lower contact edge. Reversing the lighting
    // makes fields feel recessed without an expensive inner-shadow filter.
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: inset
              ? [_dark(220), _dark(60), _light(95)]
              : [_light(245), _light(90), _dark(210)],
          stops: inset ? const [0, .20, 1] : const [0, .12, 1],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(rounded.deflate(1));
    final band = Rect.fromLTWH(1.5, 1.5, size.width - 3, inset ? 6 : 4);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [inset ? _dark(95) : _light(38), Colors.transparent],
        ).createShader(band),
    );
    canvas.restore();
    if (!inset && size.width > radius * 2 + 2) {
      // The concentrated upper glint tapers away rather than tracing a neon
      // box around the card. Paint at the same edge, not around its content.
      canvas.drawLine(
        Offset(radius, .7),
        Offset(size.width - radius, .7),
        Paint()
          ..strokeWidth = 1
          ..shader = LinearGradient(
            colors: [
              _light(255),
              Colors.white.withAlpha((150 * strength).round()),
              _light(35),
            ],
            stops: const [0, .33, 1],
          ).createShader(rect),
      );
      canvas.drawRRect(
        rounded.deflate(raisedLip ? 1.25 : 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = raisedLip ? 1.5 : .7
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: raisedLip
                ? [
                    Colors.white.withAlpha(lightSurface ? 160 : 72),
                    _light(lightSurface ? 100 : 90),
                    Colors.black.withAlpha(lightSurface ? 52 : 150),
                  ]
                : [_light(42), _light(0), _light(25)],
            stops: raisedLip ? const [0, .32, 1] : const [0, .15, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant OpportunityGlassBevel oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.radius != radius ||
      oldDelegate.strength != strength ||
      oldDelegate.inset != inset ||
      oldDelegate.raisedLip != raisedLip ||
      oldDelegate.lightSurface != lightSurface;
}

/// Fine brushed metal on Bronze, reflected window light on Moon. No grain
/// behind labels, image decoding, timers, blur, or off-screen layers.
class OpportunityArtworkLustre extends CustomPainter {
  const OpportunityArtworkLustre({required this.finish});
  final OpportunityGlassFinish finish;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final moon = finish.key == 'moon';
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            finish.accent.withAlpha(moon ? 52 : 24),
            finish.accent.withAlpha(0),
            finish.accent.withAlpha(moon ? 28 : 0),
            Colors.black.withAlpha(35),
          ],
          stops: const [0, .34, .72, 1],
        ).createShader(rect),
    );
    if (!moon) {
      final grain = Paint()
        ..strokeWidth = .65
        ..shader = LinearGradient(
          colors: [
            finish.accent.withAlpha(11),
            finish.accent.withAlpha(5),
            finish.accent.withAlpha(1),
          ],
        ).createShader(rect);
      // Batched into one path, bounded by the visible artwork bay height.
      final lines = Path();
      for (double y = 2; y < size.height; y += 3) {
        lines.moveTo(1, y);
        lines.lineTo(size.width - 2, y);
      }
      canvas.drawPath(lines, grain..style = PaintingStyle.stroke);
    }
    canvas.drawLine(
      const Offset(1, 0),
      Offset(1, size.height),
      Paint()..color = finish.accent.withAlpha(45),
    );
    canvas.drawLine(
      Offset(size.width - 1.5, 0),
      Offset(size.width - 1.5, size.height),
      Paint()..color = const Color(0x85000000),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant OpportunityArtworkLustre oldDelegate) =>
      oldDelegate.finish != finish;
}

/// The two broad, static light pools provide depth without live blur.
class OpportunityGlassBackdrop extends CustomPainter {
  const OpportunityGlassBackdrop({this.finish = OpportunityGlassFinish.bronze});
  final OpportunityGlassFinish finish;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            finish.canvas,
            finish.canvas,
            Color.lerp(
              finish.canvas,
              finish.lightSurface ? Colors.white : Colors.black,
              finish.lightSurface ? .12 : .4,
            )!,
          ],
          stops: const [0, .47, 1],
        ).createShader(rect),
    );
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .20, size.height * .12),
        width: size.width * 1.05,
        height: size.height * 1.35,
      ),
      finish.light,
      finish.light.withAlpha(24),
    );
    _light(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * .90, size.height * .72),
        width: size.width * .85,
        height: size.height * 1.10,
      ),
      finish.coolLight,
      finish.coolLight.withAlpha(18),
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
  bool shouldRepaint(covariant OpportunityGlassBackdrop oldDelegate) =>
      oldDelegate.finish != finish;
}
