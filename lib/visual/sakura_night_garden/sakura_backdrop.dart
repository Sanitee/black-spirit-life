import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sakura_material_painters.dart';
import 'sakura_spec.dart';

/// Noninteractive blackened-cedar and charcoal-plum Sakura workspace.
class SakuraNightGardenBackdrop extends StatelessWidget {
  const SakuraNightGardenBackdrop({
    this.child,
    this.sidebarRegionWidth = 260,
    super.key,
  });

  final Widget? child;

  /// Includes the shell's left workspace inset, 226 px rail, and 14 px gap.
  final double sidebarRegionWidth;

  static const Key materialKey = ValueKey<String>(
    'sakura-night-garden-backdrop-material',
  );
  static const Key detailKey = ValueKey<String>(
    'sakura-night-garden-backdrop-detail',
  );
  static const Key textureKey = ValueKey<String>(
    'sakura-night-garden-backdrop-texture',
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.hardEdge,
    children: <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const DecoratedBox(
                    key: materialKey,
                    decoration: BoxDecoration(
                      gradient: SakuraNightGardenSpec.canvasGradient,
                    ),
                  ),
                  const DecoratedBox(
                    key: textureKey,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(
                          'assets/sakura/materials/'
                          'charcoal-plum-lacquer.png',
                        ),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        opacity: .18,
                      ),
                    ),
                  ),
                  CustomPaint(
                    key: detailKey,
                    isComplex: true,
                    willChange: false,
                    painter: SakuraBackdropDetailPainter(
                      sidebarRegionWidth: sidebarRegionWidth,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (child case final content?) Positioned.fill(child: content),
    ],
  );
}

/// Short alias for visual composition sites.
class SakuraBackdrop extends SakuraNightGardenBackdrop {
  const SakuraBackdrop({super.child, super.sidebarRegionWidth, super.key});
}

/// Static grain, mineral wash, vignette, and rail joinery for the backdrop.
class SakuraBackdropDetailPainter extends CustomPainter {
  const SakuraBackdropDetailPainter({this.sidebarRegionWidth = 260});

  final double sidebarRegionWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    final sidebarWidth = sidebarRegionWidth
        .clamp(0.0, math.max(0.0, size.width - 80))
        .toDouble();

    const SakuraCedarGrainPainter(
      density: 1.1,
      highlight: Color(0x117A5A55),
      shadow: Color(0x24000000),
    ).paint(canvas, size);

    if (sidebarWidth > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, sidebarWidth, size.height));
      const SakuraCedarGrainPainter(
        sidebar: true,
        density: 1.2,
        highlight: Color(0x1C8E665F),
        shadow: Color(0x30000000),
      ).paint(canvas, Size(sidebarWidth, size.height));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, sidebarWidth, size.height),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              Color(0x12000000),
              Color(0x083F232C),
              Color(0x2A08070A),
            ],
            stops: <double>[0, 0.72, 1],
          ).createShader(Rect.fromLTWH(0, 0, sidebarWidth, size.height)),
      );
      canvas.restore();
    }

    final glowRect = Rect.fromCenter(
      center: Offset(size.width * 0.61, size.height * 0.34),
      width: size.width * 1.22,
      height: size.height * 1.12,
    );
    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[
            Color(0x122E202A),
            Color(0x071D171D),
            Color(0x000D0B0F),
          ],
          stops: <double>[0, 0.58, 1],
        ).createShader(glowRect),
    );

    final vignetteRect = Offset.zero & size;
    canvas.drawRect(
      vignetteRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.06, -0.08),
          radius: 1.12,
          colors: <Color>[
            Color(0x00100E12),
            Color(0x16000000),
            Color(0x59000000),
          ],
          stops: <double>[0, 0.7, 1],
        ).createShader(vignetteRect),
    );

    if (sidebarWidth > 0) {
      canvas.drawLine(
        Offset(sidebarWidth - 1.5, 0),
        Offset(sidebarWidth - 1.5, size.height),
        Paint()
          ..color = const Color(0xB242282D)
          ..strokeWidth = 2.5,
      );
      canvas.drawLine(
        Offset(sidebarWidth + 0.5, 0),
        Offset(sidebarWidth + 0.5, size.height),
        Paint()
          ..color = SakuraNightGardenSpec.copperHighlight.withAlpha(74)
          ..strokeWidth = 0.75,
      );
    }

    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..color = SakuraNightGardenSpec.rosewood.withAlpha(112)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = const Color(0x87000000)
        ..strokeWidth = 1,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SakuraBackdropDetailPainter oldDelegate) =>
      oldDelegate.sidebarRegionWidth != sidebarRegionWidth;
}
