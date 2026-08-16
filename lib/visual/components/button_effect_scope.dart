import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

@immutable
final class ButtonEffectVisualSettings {
  const ButtonEffectVisualSettings({
    required this.effect,
    required this.intensity,
    required this.speed,
    required this.blur,
    required this.activeOnly,
    required this.hue,
    required this.rainbow,
    required this.neon,
  });

  final String effect;
  final double intensity;
  final double speed;
  final double blur;
  final bool activeOnly;
  final double hue;
  final bool rainbow;
  final bool neon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonEffectVisualSettings &&
          other.effect == effect &&
          other.intensity == intensity &&
          other.speed == speed &&
          other.blur == blur &&
          other.activeOnly == activeOnly &&
          other.hue == hue &&
          other.rainbow == rainbow &&
          other.neon == neon;

  @override
  int get hashCode => Object.hash(
    effect,
    intensity,
    speed,
    blur,
    activeOnly,
    hue,
    rainbow,
    neon,
  );
}

/// Provides one animation clock to every button in the current workspace.
class ButtonEffectHost extends StatefulWidget {
  const ButtonEffectHost({
    required this.settings,
    required this.child,
    this.reduceMotion = false,
    super.key,
  });

  final ButtonEffectVisualSettings settings;
  final bool reduceMotion;
  final Widget child;

  @override
  State<ButtonEffectHost> createState() => _ButtonEffectHostState();
}

class _ButtonEffectHostState extends State<ButtonEffectHost>
    with SingleTickerProviderStateMixin {
  static const int _clockSeconds = 1000;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _clockSeconds),
  );

  bool get _moves => !widget.reduceMotion && widget.settings.effect != 'quiet';

  @override
  void initState() {
    super.initState();
    if (_moves) _clock.repeat();
  }

  @override
  void didUpdateWidget(ButtonEffectHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_moves && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!_moves && _clock.isAnimating) {
      _clock.stop();
      _clock.value = 0;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ButtonEffectScope(
    settings: widget.settings,
    clock: _clock,
    child: widget.child,
  );
}

class ButtonEffectScope extends InheritedTheme {
  const ButtonEffectScope({
    required this.settings,
    required this.clock,
    required super.child,
    super.key,
  });

  final ButtonEffectVisualSettings settings;
  final Animation<double> clock;

  static ButtonEffectScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ButtonEffectScope>();

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ButtonEffectScope(settings: settings, clock: clock, child: child);

  @override
  bool updateShouldNotify(ButtonEffectScope oldWidget) =>
      oldWidget.settings != settings || oldWidget.clock != clock;
}

class ButtonEffectPainter extends CustomPainter {
  const ButtonEffectPainter({
    required this.settings,
    required this.progress,
    required this.active,
  }) : _clock = null;

  ButtonEffectPainter.animated({
    required this.settings,
    required Animation<double> clock,
    required this.active,
  }) : progress = 0,
       _clock = clock,
       super(repaint: clock);

  final ButtonEffectVisualSettings settings;
  final double progress;
  final bool active;
  final Animation<double>? _clock;

  double get _effectiveSeconds {
    final clock = _clock;
    return clock == null
        ? progress
        : clock.value * _ButtonEffectHostState._clockSeconds;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || settings.effect == 'quiet') return;
    if (settings.activeOnly && !active) return;
    final intensity = settings.intensity.clamp(0.0, 1.0);
    if (intensity <= 0) return;
    final speed = .154 + settings.speed.clamp(0.0, 1.0) * .436;
    final seconds = _effectiveSeconds;
    final hue = settings.rainbow
        ? (settings.hue + seconds * (12 + settings.speed * 38)) % 360
        : settings.hue % 360;
    final color = HSLColor.fromAHSL(
      settings.neon ? .28 + intensity * .28 : .16 + intensity * .2,
      hue,
      settings.neon ? .98 : .7,
      settings.neon ? .68 : .58,
    ).toColor();
    final rect = Offset.zero & size;
    final blur = settings.blur.clamp(0.0, 1.0);

    if (blur > .005) {
      _drawSoftBloom(canvas, rect, color, blur, intensity);
    }

    switch (settings.effect) {
      case 'glow':
        _drawGlow(canvas, rect, seconds, speed, color);
      case 'orbit':
        _drawOrbit(canvas, rect, seconds, speed, intensity, color);
      case 'sweep':
        _drawSweep(canvas, rect, seconds, speed, intensity, blur, color);
      case 'sigil':
        _drawSigil(canvas, rect, seconds, speed, color);
      case 'embers':
        _drawEmbers(canvas, rect, seconds, speed, intensity, blur, color);
      case 'frost':
        _drawFrost(canvas, rect, seconds, speed, intensity, color);
      case 'fireflies':
        _drawFireflies(canvas, rect, seconds, speed, intensity, blur, color);
    }
  }

  void _drawSoftBloom(
    Canvas canvas,
    Rect rect,
    Color color,
    double blur,
    double intensity,
  ) {
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(2.2),
      const Radius.circular(10),
    );
    final alphaFactor = .2 + blur * .42 + intensity * .08;
    for (final ring in <(double, double)>[
      (5.5 + blur * 12, alphaFactor * .46),
      (2.8 + blur * 5.5, alphaFactor * .64),
    ]) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withAlpha(_scaledAlpha(color, ring.$2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.$1,
      );
    }
  }

  void _drawGlow(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    Color color,
  ) {
    final pulse = .5 + math.sin(seconds * speed * 2.4) * .5;
    final alphaFactor = .78 + pulse * .72;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(2.1),
      const Radius.circular(9),
    );
    for (final ring in <(double, double)>[
      (5.4, alphaFactor * .38),
      (3.7, alphaFactor * .28),
      (2.15, alphaFactor),
    ]) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withAlpha(_scaledAlpha(color, ring.$2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring.$1,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          <Color>[
            color.withAlpha(_scaledAlpha(color, alphaFactor * .22)),
            color.withAlpha(_scaledAlpha(color, alphaFactor * .08)),
            color.withAlpha(0),
          ],
          const <double>[0, .55, 1],
        ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center.translate(-rect.width * .02, -rect.height * .04),
          math.max(rect.width, rect.height) * .82,
          <Color>[
            color.withAlpha(
              _scaledAlpha(color, alphaFactor * (.11 + pulse * .11)),
            ),
            color.withAlpha(
              _scaledAlpha(color, alphaFactor * (.06 + pulse * .05)),
            ),
            color.withAlpha(0),
          ],
          const <double>[0, .64, 1],
        ),
    );
  }

  void _drawOrbit(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    double intensity,
    Color color,
  ) {
    final border = rect.deflate(2.2);
    final thickness =
        (math.min(rect.width, rect.height) * .045 + intensity * .9)
            .clamp(1.4, 3.4)
            .toDouble();
    canvas.drawRRect(
      RRect.fromRectAndRadius(border, const Radius.circular(10)),
      Paint()
        ..color = color.withAlpha(_scaledAlpha(color, .46 + intensity * .38))
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * .54,
    );
    final start = (seconds * (.18 + speed * .16)) % 1;
    final highlightAlpha = 1.25 + intensity * .4;
    _drawPerimeterSegment(
      canvas,
      border,
      start,
      .26 + intensity * .12,
      Paint()
        ..color = color.withAlpha(_scaledAlpha(color, highlightAlpha))
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = thickness,
    );
    final second = Color.fromARGB(
      _scaledAlpha(color, highlightAlpha * .62),
      (color.r * 255 + 28).round().clamp(0, 255),
      (color.g * 255 + 48).round().clamp(0, 255),
      (color.b * 255 + 22).round().clamp(0, 255),
    );
    _drawPerimeterSegment(
      canvas,
      border,
      (start + .48) % 1,
      (.26 + intensity * .12) * .58,
      Paint()
        ..color = second
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.1, thickness * .72),
    );
  }

  void _drawPerimeterSegment(
    Canvas canvas,
    Rect rect,
    double start,
    double length,
    Paint paint,
  ) {
    const samples = 26;
    var previous = _pointOnRect(rect, start * _perimeter(rect));
    for (var index = 1; index <= samples; index++) {
      final point = _pointOnRect(
        rect,
        ((start + length * index / samples) % 1) * _perimeter(rect),
      );
      canvas.drawLine(previous, point, paint);
      previous = point;
    }
  }

  void _drawSweep(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    double intensity,
    double blur,
    Color color,
  ) {
    final height = rect.height;
    final t = (seconds * speed * .34) % 1;
    final x = -height * 1.6 + t * (rect.width + height * 3.2);
    final soft = _sweepRibbon(
      x - height * .15,
      height,
      height * (1.22 + blur * 2.2),
      height * 1.34,
    );
    canvas.drawPath(
      soft,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - height * 1.4, 0),
          Offset(x + height * 1.4, 0),
          <Color>[
            color.withAlpha(0),
            color.withAlpha(_scaledAlpha(color, .04 + blur * .12)),
            const Color(
              0xFFFFFAD2,
            ).withAlpha(_scaledAlpha(color, .18 + blur * .34)),
            color.withAlpha(_scaledAlpha(color, .05 + blur * .13)),
            color.withAlpha(0),
          ],
          const <double>[0, .18, .5, .82, 1],
        ),
    );
    final broad = _sweepRibbon(
      x,
      height,
      height * (1 + intensity * .34),
      height * 1.22,
    );
    canvas.drawPath(
      broad,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - height, 0),
          Offset(x + height, 0),
          <Color>[
            color.withAlpha(0),
            color.withAlpha(_scaledAlpha(color, .12 + intensity * .08)),
            const Color(
              0xFFFFFCD8,
            ).withAlpha(_scaledAlpha(color, .58 + intensity * .22)),
            color.withAlpha(_scaledAlpha(color, .18 + intensity * .08)),
            color.withAlpha(0),
          ],
          const <double>[0, .18, .5, .82, 1],
        ),
    );
    canvas.drawLine(
      Offset(x + height * .34, height + 10),
      Offset(x + height * 1.24, -10),
      Paint()
        ..color = const Color(
          0xFFFFFCD8,
        ).withAlpha(_scaledAlpha(color, .62 + intensity * .28))
        ..strokeWidth = math.max(1.9, height * (.07 + blur * .04)),
    );
    canvas.drawLine(
      Offset(x - height * .12, height + 14),
      Offset(x + height * .8, -14),
      Paint()
        ..color = color.withAlpha(_scaledAlpha(color, .2 + blur * .24))
        ..strokeWidth = math.max(3.6, height * (.18 + blur * .24)),
    );
  }

  Path _sweepRibbon(double x, double height, double halfWidth, double slant) =>
      Path()
        ..moveTo(x - halfWidth, height + 16)
        ..lineTo(x + halfWidth, height + 16)
        ..lineTo(x + slant + halfWidth, -16)
        ..lineTo(x + slant - halfWidth, -16)
        ..close();

  void _drawSigil(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    Color color,
  ) {
    final pulse = .72 + math.sin(seconds * speed * 1.8) * .22;
    final paint = Paint()
      ..color = color.withAlpha(_scaledAlpha(color, pulse))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final tick = math.min(14.0, math.min(rect.width, rect.height) * .28);
    const pad = 5.0;
    for (final corner in <(Offset, double, double)>[
      (const Offset(pad, pad), 1, 1),
      (Offset(rect.width - pad, pad), -1, 1),
      (Offset(pad, rect.height - pad), 1, -1),
      (Offset(rect.width - pad, rect.height - pad), -1, -1),
    ]) {
      _drawSigilCorner(canvas, corner.$1, corner.$2, corner.$3, tick, paint);
    }
  }

  void _drawSigilCorner(
    Canvas canvas,
    Offset origin,
    double sx,
    double sy,
    double tick,
    Paint paint,
  ) {
    canvas.drawLine(origin, origin.translate(sx * tick, 0), paint);
    canvas.drawLine(origin, origin.translate(0, sy * tick), paint);
    canvas.drawCircle(
      origin.translate(sx * tick * .62, sy * tick * .62),
      2.4,
      paint,
    );
  }

  void _drawEmbers(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    double intensity,
    double blur,
    Color color,
  ) {
    for (var index = 0; index < 14; index++) {
      final seed = _unit(index * 97 + 11);
      final t = (seconds * (.14 + speed * .28) + seed) % 1;
      final x =
          8 +
          ((seed * 997) % 1) * math.max(1, rect.width - 16) +
          math.sin(seconds * (1.1 + seed) + seed * 10) *
              (2.2 + intensity * 4.2);
      final y = rect.height + 4 - t * (rect.height + 14);
      final radius = 1.5 + ((seed * 17) % 1) * (2.4 + intensity * 1.6);
      final ember = color.withAlpha(
        _scaledAlpha(color, math.sin(t * math.pi) * (.5 + intensity * .7)),
      );
      _drawButtonEmber(
        canvas,
        Offset(x, y),
        radius,
        ember,
        seed,
        seconds,
        blur,
      );
    }
  }

  void _drawButtonEmber(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double seed,
    double seconds,
    double blur,
  ) {
    if (color.a <= .01) return;
    final lean = math.sin(seconds * (1.3 + seed) + seed * 8) * radius * .45;
    if (blur > .005) {
      _drawGlowAura(canvas, center, radius * 1.05, color, blur);
    }
    canvas.drawLine(
      center.translate(lean * .3, radius * 2.1),
      center.translate(0, radius * .2),
      Paint()
        ..color = color.withAlpha(_scaledAlpha(color, .28))
        ..strokeWidth = math.max(.75, radius * .34)
        ..strokeCap = StrokeCap.round,
    );
    final path = Path()
      ..moveTo(center.dx + lean * .18, center.dy - radius * 1.08)
      ..quadraticBezierTo(
        center.dx + radius * .62,
        center.dy - radius * .12,
        center.dx + lean * .34,
        center.dy + radius * .92,
      )
      ..quadraticBezierTo(
        center.dx - radius * .58,
        center.dy + radius * .08,
        center.dx + lean * .18,
        center.dy - radius * 1.08,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, -radius * .08),
        width: radius * .4,
        height: radius * .64,
      ),
      Paint()
        ..color = const Color(0xFFFFE28C).withAlpha(_scaledAlpha(color, .72)),
    );
  }

  void _drawFrost(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    double intensity,
    Color color,
  ) {
    final shimmer = .6 + math.sin(seconds * speed * 2.1) * .25;
    final frost = color.withAlpha(_scaledAlpha(color, shimmer));
    final border = rect.deflate(2.2);
    final rrect = RRect.fromRectAndRadius(border, const Radius.circular(9));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withAlpha(_scaledAlpha(color, shimmer * .22))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.8 + intensity * 1.6,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = frost
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + intensity * .65,
    );
    final branchPaint = Paint()
      ..color = frost
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1 + intensity * .6;
    final length = math
        .min(18.0, math.min(rect.width, rect.height) * .34)
        .toDouble();
    for (final corner in <(Offset, double, double)>[
      (const Offset(5, 5), 1, 1),
      (Offset(rect.width - 5, 5), -1, 1),
      (Offset(5, rect.height - 5), 1, -1),
      (Offset(rect.width - 5, rect.height - 5), -1, -1),
    ]) {
      _drawFrostCorner(
        canvas,
        corner.$1,
        length,
        corner.$2,
        corner.$3,
        branchPaint,
      );
    }
    for (var index = 0; index < 7; index++) {
      final point = _pointOnRect(
        border,
        ((seconds * (.11 + speed * .12) + index * .173) % 1) *
            _perimeter(border),
      );
      final pulse =
          .45 +
          math.sin(seconds * speed * (2.4 + index * .19) + index * 1.7) * .35;
      _drawGlint(
        canvas,
        point,
        2.4 + intensity * 3.2 + index % 3,
        seconds * .4 + index,
        const Color(0xFFF6FFF6).withAlpha(_scaledAlpha(color, .38 + pulse)),
      );
    }
  }

  void _drawFrostCorner(
    Canvas canvas,
    Offset origin,
    double length,
    double sx,
    double sy,
    Paint paint,
  ) {
    canvas.drawLine(origin, origin.translate(sx * length, 0), paint);
    canvas.drawLine(origin, origin.translate(0, sy * length), paint);
    canvas.drawLine(
      origin.translate(sx * length * .55, 0),
      origin.translate(sx * length * .75, sy * length * .25),
      paint,
    );
    canvas.drawLine(
      origin.translate(0, sy * length * .55),
      origin.translate(sx * length * .25, sy * length * .75),
      paint,
    );
  }

  void _drawFireflies(
    Canvas canvas,
    Rect rect,
    double seconds,
    double speed,
    double intensity,
    double blur,
    Color color,
  ) {
    for (var index = 0; index < 10; index++) {
      final seed = _unit(index * 83 + 17);
      final t = (seconds * (.055 + speed * .085) + seed) % 1;
      final reverse = (seed * 1000).floor().isEven;
      final lane = .2 + ((seed * 431) % 1) * .6;
      final x = reverse
          ? rect.width + 10 - t * (rect.width + 20)
          : -10 + t * (rect.width + 20);
      final y =
          rect.height * lane +
          math.sin(seconds * (.74 + seed * .24) + seed * 11) *
              rect.height *
              (.035 + intensity * .055);
      final previousT = math.max(0.0, t - .018);
      final previousX = reverse
          ? rect.width + 10 - previousT * (rect.width + 20)
          : -10 + previousT * (rect.width + 20);
      final previousY =
          rect.height * lane +
          math.sin((seconds - .13) * (.74 + seed * .24) + seed * 11) *
              rect.height *
              (.035 + intensity * .055);
      final pulse =
          .58 + math.sin(seconds * speed * (2.2 + seed) + seed * 12) * .42;
      final flyColor = color.withAlpha(_scaledAlpha(color, pulse * 1.45));
      _drawButtonFirefly(
        canvas,
        Offset(x, y),
        Offset(x - previousX, y - previousY),
        3.7 + intensity * 2.6 + ((seed * 19) % 1) * 1.8,
        flyColor,
        seconds * speed + seed * 7,
        blur,
      );
    }
  }

  void _drawButtonFirefly(
    Canvas canvas,
    Offset center,
    Offset direction,
    double radius,
    Color color,
    double phase,
    double blur,
  ) {
    if (color.a <= .01) return;
    if (blur > .005) _drawGlowAura(canvas, center, radius, color, blur);
    final safeDirection = direction.distance <= .0001
        ? const Offset(1, 0)
        : direction;
    final forward = safeDirection / safeDirection.distance;
    final normal = Offset(-forward.dy, forward.dx);
    final wingColor = const Color(
      0xFFF7FFD6,
    ).withAlpha(_scaledAlpha(color, .68));
    for (final side in const <double>[-1, 1]) {
      final root =
          center - forward * radius * .06 + normal * side * radius * .12;
      final tip =
          center - forward * radius * .36 + normal * side * radius * .82;
      final top =
          center - forward * radius * .62 + normal * side * radius * .34;
      final lower =
          center + forward * radius * .08 + normal * side * radius * .46;
      final wing = Path()
        ..moveTo(root.dx, root.dy)
        ..quadraticBezierTo(top.dx, top.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(lower.dx, lower.dy, root.dx, root.dy)
        ..close();
      canvas.drawPath(wing, Paint()..color = wingColor);
    }
    canvas.drawLine(
      center - forward * radius * .52,
      center + forward * radius * .46,
      Paint()
        ..color = const Color(0xFF1F1D12).withAlpha(_scaledAlpha(color, .84))
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(.75, radius * .2),
    );
    final abdomen = center - forward * radius * .55;
    canvas.drawOval(
      Rect.fromCenter(
        center: abdomen,
        width: radius * .96,
        height: radius * .72,
      ),
      Paint()..color = color,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: abdomen - forward * radius * .1,
        width: radius * .5,
        height: radius * .36,
      ),
      Paint()
        ..color = const Color(
          0xFFFFFCB2,
        ).withAlpha(_scaledAlpha(color, .9 * (.65 + math.sin(phase) * .25))),
    );
  }

  void _drawGlowAura(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double blur,
  ) {
    final bounds = Rect.fromCenter(
      center: center,
      width: radius * (5.2 + blur * 10.4),
      height: radius * (4 + blur * 8.4),
    );
    canvas.drawOval(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          center.translate(-bounds.width * .02, -bounds.height * .02),
          math.max(bounds.width, bounds.height) * .5,
          <Color>[
            color.withAlpha(_scaledAlpha(color, .16 + blur * .22)),
            color.withAlpha(_scaledAlpha(color, .07 + blur * .12)),
            color.withAlpha(_scaledAlpha(color, .018 + blur * .04)),
            color.withAlpha(0),
          ],
          const <double>[0, .42, .72, 1],
        ),
    );
  }

  void _drawGlint(
    Canvas canvas,
    Offset center,
    double radius,
    double spin,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(.55, radius * .18);
    for (var ray = 0; ray < 2; ray++) {
      final angle = spin + ray * math.pi / 2;
      final vector = Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawLine(center - vector, center + vector, paint);
    }
    canvas.drawCircle(
      center,
      radius * .62,
      Paint()..color = color.withAlpha(_scaledAlpha(color, .28)),
    );
  }

  Offset _pointOnRect(Rect rect, double distance) {
    final width = rect.width;
    final height = rect.height;
    final perimeter = 2 * (width + height);
    var value = distance % perimeter;
    if (value <= width) return Offset(rect.left + value, rect.top);
    value -= width;
    if (value <= height) return Offset(rect.right, rect.top + value);
    value -= height;
    if (value <= width) return Offset(rect.right - value, rect.bottom);
    value -= width;
    return Offset(rect.left, rect.bottom - value);
  }

  double _perimeter(Rect rect) => math.max(1, 2 * (rect.width + rect.height));

  int _scaledAlpha(Color color, double factor) =>
      (color.a * 255 * factor).round().clamp(0, 255);

  double _unit(int seed) =>
      ((seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;

  @override
  bool shouldRepaint(covariant ButtonEffectPainter oldDelegate) =>
      oldDelegate._clock != _clock ||
      oldDelegate._effectiveSeconds != _effectiveSeconds ||
      oldDelegate.active != active ||
      oldDelegate.settings != settings;
}
