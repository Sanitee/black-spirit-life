import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../components/retained_asset_image.dart';
import 'standard_spec.dart';

/// Noninteractive retained background for all Standard scene and plain IDs.
class StandardBackdrop extends StatelessWidget {
  const StandardBackdrop({
    required this.backgroundId,
    this.child,
    this.blurSigma = 0,
    this.imageOpacity = 0.86,
    this.atmosphere,
    super.key,
  });

  final String backgroundId;
  final Widget? child;
  final double blurSigma;
  final double imageOpacity;

  /// Optional visual-only atmosphere supplied by the owning scene controller.
  final Widget? atmosphere;

  static const Key imageKey = ValueKey<String>('standard-backdrop-image');
  static const Key plainKey = ValueKey<String>('standard-backdrop-plain');
  static const Key toneKey = ValueKey<String>('standard-backdrop-tone');
  static const Key sceneStackKey = ValueKey<String>(
    'standard-backdrop-scene-stack',
  );
  static const Key failureKey = ValueKey<String>(
    'standard-backdrop-asset-failure',
  );

  @override
  Widget build(BuildContext context) {
    final selection = StandardSpec.resolveBackdrop(backgroundId);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ClipRect(child: _buildBackground(selection)),
            ),
          ),
        ),
        if (child case final content?) Positioned.fill(child: content),
      ],
    );
  }

  Widget _buildBackground(StandardBackdropSelection selection) {
    final plain = selection.plain;
    // Avalonia uses the plain gradients only for the Appearance thumbnails.
    // The live plain treatments retain Greenhouse beneath the common dark tone
    // at a deliberately low opacity, then use the selected plain accent for
    // particles and controls.
    final scene = plain == null
        ? selection.scene!
        : StandardSpec.scenes[StandardSpec.defaultBackgroundId]!;
    final sigma = blurSigma.clamp(0.0, 12.0).toDouble();
    final opacity = plain == null
        ? imageOpacity.clamp(0.0, 1.0).toDouble()
        : 0.32;
    Widget image = RetainedAssetImage(
      assetPath: scene.assetPath,
      assetLabel: plain == null
          ? '${scene.displayName} scene'
          : '${plain.displayName} retained Greenhouse scene',
      imageKey: imageKey,
      failureKey: failureKey,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      opacity: AlwaysStoppedAnimation<double>(opacity),
    );
    if (sigma > 0) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Transform.scale(scale: 1.025, child: image),
      );
    }

    final sceneStack = Stack(
      key: sceneStackKey,
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: StandardSpec.backdropBacking),
        image,
        const DecoratedBox(
          key: toneKey,
          decoration: BoxDecoration(gradient: StandardSpec.backdropTone),
        ),
        ?atmosphere,
      ],
    );
    return plain == null
        ? sceneStack
        : KeyedSubtree(key: plainKey, child: sceneStack);
  }
}

/// A deterministic, very low-contrast material grain for plain backgrounds.
class StandardBackdropTexturePainter extends CustomPainter {
  const StandardBackdropTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final grain = Paint()
      ..color = const Color(0x0DFFF4D8)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final shade = Paint()
      ..color = const Color(0x18000000)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 72; i++) {
      final x = ((i * 149 + i * i * 11) % 997) / 997 * size.width;
      final y = ((i * 83 + i * i * 17) % 991) / 991 * size.height;
      final length = 4.0 + (i % 9) * 1.1;
      canvas.drawLine(Offset(x, y), Offset(x + length, y + (i % 3 - 1)), grain);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), grain);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), shade);
  }

  @override
  bool shouldRepaint(covariant StandardBackdropTexturePainter oldDelegate) =>
      false;
}
