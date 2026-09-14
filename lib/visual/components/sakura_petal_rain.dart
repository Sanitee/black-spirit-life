import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A deterministic, paint-only Sakura shower for short-lived notices.
///
/// Interaction and semantics remain owned by the widget beneath this layer.
/// The supplied animation is expected to run from 0 to 1 once.
class SakuraPetalRain extends StatelessWidget {
  const SakuraPetalRain({
    required this.animation,
    required this.baseColor,
    required this.highlightColor,
    this.paintKey,
    super.key,
  });

  static const int petalCount = 12;

  final Animation<double> animation;
  final Color baseColor;
  final Color highlightColor;
  final Key? paintKey;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => CustomPaint(
            key: paintKey,
            painter: SakuraPetalRainPainter(
              progress: animation.value,
              baseColor: baseColor,
              highlightColor: highlightColor,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

class SakuraPetalRainPainter extends CustomPainter {
  const SakuraPetalRainPainter({
    required this.progress,
    required this.baseColor,
    required this.highlightColor,
  });

  final double progress;
  final Color baseColor;
  final Color highlightColor;

  static const List<_PetalSeed> _petals = <_PetalSeed>[
    _PetalSeed(.04, .014, .654, 16, .58, .72, .18),
    _PetalSeed(.12, .120, .712, -13, -.47, .90, 1.44),
    _PetalSeed(.21, .069, .596, 19, .68, .66, 2.18),
    _PetalSeed(.30, .197, .750, -18, -.64, .82, .72),
    _PetalSeed(.39, .144, .635, 11, .53, .58, 2.86),
    _PetalSeed(.48, .031, .683, -16, -.72, .88, 1.06),
    _PetalSeed(.57, .236, .740, 21, .63, .70, 2.42),
    _PetalSeed(.66, .099, .615, -12, -.51, .96, .36),
    _PetalSeed(.74, .175, .702, 14, .76, .64, 1.82),
    _PetalSeed(.82, .050, .663, -20, -.60, .84, 2.72),
    _PetalSeed(.90, .262, .731, 10, .50, .60, .94),
    _PetalSeed(.96, .131, .625, -15, -.69, .78, 2.02),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final timeline = progress.clamp(0.0, 1.0).toDouble();
    for (var index = 0; index < _petals.length; index++) {
      final seed = _petals[index];
      final local = ((timeline - seed.delay) / seed.duration).clamp(0.0, 1.0);
      if (timeline < seed.delay || local >= 1) continue;

      final eased = Curves.easeInOut.transform(local.toDouble());
      final fadeIn = (local / .08).clamp(0.0, 1.0);
      final fadeOut = ((1 - local) / .24).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut * (.56 + (index % 3) * .09);
      if (opacity <= 0) continue;

      final sway = math.sin(local * math.pi * 2.25 + seed.phase) * 7.5;
      final x = size.width * seed.startX + seed.drift * eased + sway;
      final y = -14 + (size.height + 29) * eased;
      final turn = seed.phase + seed.turns * math.pi * 2 * local;
      final petalColor = Color.lerp(
        baseColor,
        highlightColor,
        .26 + (index % 4) * .16,
      )!;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(turn);
      canvas.scale(seed.scale);
      final petal = Path()
        ..moveTo(0, -6.2)
        ..quadraticBezierTo(4.8, -2.1, 3.5, 1.2)
        ..quadraticBezierTo(2.2, 4.7, 0, 6.4)
        ..quadraticBezierTo(-3.9, 3.6, -3.5, .2)
        ..quadraticBezierTo(-3.1, -3.2, 0, -6.2)
        ..close();
      canvas.drawPath(
        petal,
        Paint()
          ..color = petalColor.withAlpha((opacity * 188).round())
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(.1, -3.8)
          ..quadraticBezierTo(-.8, -.2, .1, 3.8),
        Paint()
          ..color = highlightColor.withAlpha((opacity * 94).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = .72
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant SakuraPetalRainPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.highlightColor != highlightColor;
}

class _PetalSeed {
  const _PetalSeed(
    this.startX,
    this.delay,
    this.duration,
    this.drift,
    this.turns,
    this.scale,
    this.phase,
  );

  final double startX;
  final double delay;
  final double duration;
  final double drift;
  final double turns;
  final double scale;
  final double phase;
}
