import 'package:flutter/material.dart';

import '../../visual/visual.dart';

enum ProfileArtwork { alchemy, cooking, processing, weight, featherySteps }

/// Compact cream profile symbols matching the user's in-game reference.
///
/// The four monochrome symbols are native vector recreations, not extracted
/// client artwork. Feathery Steps alone uses the original bundled skill image.
class ProfileIcon extends StatelessWidget {
  const ProfileIcon({required this.artwork, this.size = 24, super.key});

  final ProfileArtwork artwork;
  final double size;

  static const featheryAssetPath = 'assets/app/profile_feathery_steps.webp';

  @override
  Widget build(BuildContext context) {
    if (artwork == ProfileArtwork.featherySteps) {
      return Image.asset(
        featheryAssetPath,
        key: const ValueKey('profile-original-icon:featherySteps'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
        gaplessPlayback: true,
      );
    }
    final image = CustomPaint(
      key: ValueKey('profile-vector-icon:${artwork.name}'),
      size: Size.square(size),
      painter: _ProfileSymbolPainter(artwork),
    );
    final palette = context.visualTheme.palette;
    // Cream symbols need a dark reading well on pale Appearance themes.
    if (palette.surfaceRaised.computeLuminance() < .5) {
      return image;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(4),
      ),
      child: image,
    );
  }
}

class _ProfileSymbolPainter extends CustomPainter {
  const _ProfileSymbolPainter(this.artwork);

  final ProfileArtwork artwork;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = const Color(0xFFEAD9B5);
    switch (artwork) {
      case ProfileArtwork.alchemy:
        final flask = Path()
          ..moveTo(9, 5)
          ..lineTo(15, 5)
          ..lineTo(15, 10)
          ..lineTo(21, 20.5)
          ..quadraticBezierTo(22, 22, 20, 22)
          ..lineTo(4, 22)
          ..quadraticBezierTo(2, 22, 3, 20.5)
          ..lineTo(9, 10)
          ..close();
        final bubbles = Path()
          ..addOval(
            Rect.fromCircle(center: const Offset(12.5, 13), radius: 1.6),
          )
          ..addOval(Rect.fromCircle(center: const Offset(9, 17.5), radius: 1.5))
          ..addOval(Rect.fromCircle(center: const Offset(15, 19), radius: 1.1));
        canvas.drawPath(
          Path.combine(PathOperation.difference, flask, bubbles),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(7.5, 4, 9, 1.6),
            const Radius.circular(.6),
          ),
          paint,
        );
        canvas.drawCircle(const Offset(10, 1.6), 1, paint);
        canvas.drawCircle(const Offset(14, 2.3), .6, paint);
      case ProfileArtwork.cooking:
        final roast = Path()
          ..moveTo(1.5, 17.5)
          ..cubicTo(2, 12, 8, 7.2, 13, 8)
          ..cubicTo(18, 8.3, 21.5, 13.3, 19, 17)
          ..cubicTo(16, 21.5, 8, 22.5, 2.5, 20)
          ..quadraticBezierTo(1, 19.3, 1.5, 17.5)
          ..close();
        final thighOutline = Path.combine(
          PathOperation.difference,
          Path()..addOval(const Rect.fromLTWH(8.5, 10, 9.5, 9)),
          Path()..addOval(const Rect.fromLTWH(9.6, 11.1, 7.3, 6.8)),
        );
        canvas.drawPath(
          Path.combine(PathOperation.difference, roast, thighOutline),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(13, 10)
            ..lineTo(17.5, 6.3)
            ..lineTo(17.1, 4.6)
            ..cubicTo(16.6, 2.5, 19.2, 1.6, 20, 3.6)
            ..cubicTo(21.8, 2.1, 23.2, 4.6, 21.1, 5.8)
            ..lineTo(19.2, 6.6)
            ..lineTo(17.3, 11.9)
            ..close(),
          paint,
        );
      case ProfileArtwork.processing:
        // The reference uses a single diagonal hammer, not crossed tools.
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-.7);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-1.55, -4, 3.1, 17),
            const Radius.circular(.7),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-6.2, -8, 12.4, 5.3),
            const Radius.circular(.45),
          ),
          paint,
        );
        canvas.restore();
      case ProfileArtwork.weight:
        final body = Path()
          ..moveTo(6, 8)
          ..lineTo(18, 8)
          ..lineTo(22, 21)
          ..quadraticBezierTo(22.3, 22, 21, 22)
          ..lineTo(3, 22)
          ..quadraticBezierTo(1.7, 22, 2, 21)
          ..close();
        final ring = Path.combine(
          PathOperation.difference,
          Path()..addOval(const Rect.fromLTWH(8, 1, 8, 9)),
          Path()..addOval(const Rect.fromLTWH(10, 3, 4, 4.8)),
        );
        canvas.drawPath(body, paint);
        canvas.drawPath(ring, paint);
      case ProfileArtwork.featherySteps:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProfileSymbolPainter oldDelegate) =>
      oldDelegate.artwork != artwork;
}
