import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

@immutable
final class AtmosphereVisualSettings {
  const AtmosphereVisualSettings({
    required this.style,
    required this.density,
    required this.opacity,
    required this.minimumSize,
    required this.maximumSize,
    required this.blur,
    required this.speed,
    required this.strength,
    required this.hue,
    this.customColor = false,
    required this.rainbow,
    required this.neon,
    required this.animated,
  });

  final String style;
  final double density;
  final double opacity;
  final double minimumSize;
  final double maximumSize;
  final double blur;
  final double speed;
  final double strength;
  final double hue;
  final bool customColor;
  final bool rainbow;
  final bool neon;
  final bool animated;
}

/// One shared-clock, paint-only atmosphere layer for retained Standard scenes.
class StandardAtmosphere extends StatefulWidget {
  const StandardAtmosphere({
    required this.settings,
    this.reduceMotion = false,
    super.key,
  });

  final AtmosphereVisualSettings settings;
  final bool reduceMotion;

  @override
  State<StandardAtmosphere> createState() => _StandardAtmosphereState();
}

class _StandardAtmosphereState extends State<StandardAtmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  bool get _moves => widget.settings.animated && !widget.reduceMotion;

  @override
  void initState() {
    super.initState();
    if (_moves) _clock.repeat();
  }

  @override
  void didUpdateWidget(StandardAtmosphere oldWidget) {
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
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) => CustomPaint(
            painter: StandardAtmospherePainter(
              settings: widget.settings,
              progress: _moves ? _clock.value : 0,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    ),
  );
}

class StandardAtmospherePainter extends CustomPainter {
  const StandardAtmospherePainter({
    required this.settings,
    required this.progress,
  });

  final AtmosphereVisualSettings settings;
  final double progress;

  static final List<_ParticleSeed> _particles = _createParticleSeeds();

  static List<_ParticleSeed> _createParticleSeeds() {
    final random = _DotNetRandom(42);
    return List<_ParticleSeed>.generate(
      360,
      (_) => _ParticleSeed(
        x: random.nextDouble(),
        y: random.nextDouble(),
        depth: random.nextDouble(),
        phase: random.nextDouble() * math.pi * 2,
        hueShift: random.nextDouble() * 180,
        size: random.nextDouble(),
        spin: random.nextDouble() * math.pi * 2,
        wobble: random.nextDouble() * math.pi * 2,
      ),
      growable: false,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final density = settings.density.clamp(0.0, 1.0).toDouble();
    final opacity = settings.opacity.clamp(0.0, 1.0).toDouble();
    final count = _particleCount(settings.style, density);
    final speed = .039 + settings.speed.clamp(0.0, 1.0) * .111;
    final strength =
        math.pow(settings.strength.clamp(0.0, 1.0), 1.45).toDouble() * .58;
    final elapsedSeconds = progress * 18;
    final minimum = settings.minimumSize.clamp(.35, 2.2).toDouble();
    final maximum = math.max(
      minimum,
      settings.maximumSize.clamp(minimum, 2.2).toDouble(),
    );
    final blur = settings.blur.clamp(0.0, 1.0).toDouble();

    for (var index = 0; index < count; index++) {
      final particle = _particles[index];
      final seedX = particle.x;
      final seedY = particle.y;
      final depth = particle.depth;
      final phaseSeed = particle.phase;
      final hueShift = particle.hueShift;
      final sizeSeed = particle.size;
      final spinSeed = particle.spin;
      final wobble = particle.wobble;
      final phaseRate = speed * (.5 + depth * 1.35);
      final particlePhase = phaseSeed + elapsedSeconds * phaseRate;
      final spin = spinSeed + elapsedSeconds * (.12 + wobble * .22);
      final scale = ui.lerpDouble(minimum, maximum, sizeSeed)!;
      final radius = (1.4 + depth * 3.6) * scale;
      final motion = _particleMotion(
        size: size,
        style: settings.style,
        elapsedSeconds: elapsedSeconds,
        speed: speed,
        strength: strength,
        seedX: seedX,
        seedY: seedY,
        depth: depth,
        phaseSeed: phaseSeed,
        phaseRate: phaseRate,
        particlePhase: particlePhase,
        hueShift: hueShift,
        wobble: wobble,
      );
      final hue = settings.rainbow
          ? (settings.hue + elapsedSeconds * 32 + hueShift) % 360
          : settings.customColor
          ? settings.hue % 360
          : _particleHue(settings.style, hueShift);
      final alphaBase = switch (settings.style) {
        'fireflies' => .52 + depth * .46,
        'embers' => .26 + depth * .52,
        'snow' => .18 + depth * .34,
        'bubbles' => .16 + depth * .36,
        _ => .13 + depth * .33,
      };
      final color = _particleColor(
        settings.style,
        hue,
        (alphaBase * opacity).clamp(0.0, .92).toDouble(),
        settings.neon,
      );
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      if (blur > .005) {
        _drawRadialParticleBlur(
          canvas,
          settings.style,
          motion.center,
          radius,
          color,
          blur,
          particlePhase,
        );
        if (settings.style != 'fireflies' && settings.style != 'embers') {
          _drawParticleSoftening(
            canvas,
            style: settings.style,
            center: motion.center,
            radius: radius,
            color: color,
            blur: blur,
            particlePhase: particlePhase,
            spin: spin,
            depth: depth,
            velocity: motion.velocity,
            elapsedSeconds: elapsedSeconds,
            wobble: wobble,
            hueShift: hueShift,
          );
        }
      }
      if (settings.neon &&
          settings.style != 'embers' &&
          settings.style != 'fireflies') {
        canvas.drawCircle(
          motion.center,
          radius * 1.7,
          Paint()..color = color.withAlpha(_scaledAlpha(color, .18)),
        );
      }
      _drawParticleShape(
        canvas,
        motion.center,
        radius,
        particlePhase,
        spin,
        paint,
        settings.style,
        depth,
        motion.velocity,
        elapsedSeconds,
      );
    }
  }

  int _particleCount(String style, double density) => switch (style) {
    'fireflies' => math.min(360, (54 + density * 176).round()),
    'embers' => math.min(360, (32 + density * 142).round()),
    'snow' => math.min(360, (36 + density * 214).round()),
    'bubbles' => math.min(360, (24 + density * 150).round()),
    'stars' => math.min(360, (28 + density * 132).round()),
    'fumes' => math.min(360, (18 + density * 80).round()),
    _ => math.min(360, (26 + density * 145).round()),
  };

  _ParticleMotion _particleMotion({
    required Size size,
    required String style,
    required double elapsedSeconds,
    required double speed,
    required double strength,
    required double seedX,
    required double seedY,
    required double depth,
    required double phaseSeed,
    required double phaseRate,
    required double particlePhase,
    required double hueShift,
    required double wobble,
  }) {
    final t = elapsedSeconds;
    var x = seedX;
    var y = seedY;
    var velocityX = 0.0;
    var velocityY = 0.0;
    switch (style) {
      case 'embers':
        final factor = speed * (.75 + strength * 1.65);
        x +=
            factor *
            (.42 * _integratedSin(phaseSeed, phaseRate, t, 1.15, hueShift) +
                .28 * _integratedSin(phaseSeed, phaseRate, t, .37, wobble) +
                .12 * _integratedCos(phaseSeed, phaseRate, t, 2.1, depth * 5));
        y -= speed * t * (.11 + depth * .31);
        velocityX =
            factor *
            (.42 * math.sin(particlePhase * 1.15 + hueShift) +
                .28 * math.sin(particlePhase * .37 + wobble) +
                .12 * math.cos(particlePhase * 2.1 + depth * 5));
        velocityY = -speed * (.11 + depth * .31);
      case 'fireflies':
        final factorX = speed * (1.1 + strength * 1.45);
        final factorY = speed * (.95 + strength * 1.15);
        x +=
            factorX *
            (.32 *
                    _integratedSin(
                      phaseSeed,
                      phaseRate,
                      t,
                      .47,
                      hueShift * .017,
                    ) +
                .16 * _integratedSin(phaseSeed, phaseRate, t, 1.09, wobble) +
                .1 * _integratedCos(phaseSeed, phaseRate, t, .23, depth * 7));
        y +=
            factorY *
            (.22 * _integratedCos(phaseSeed, phaseRate, t, .39, wobble) +
                .16 *
                    _integratedSin(phaseSeed, phaseRate, t, .83, depth * 6.2));
        velocityX =
            factorX *
            (.32 * math.sin(particlePhase * .47 + hueShift * .017) +
                .16 * math.sin(particlePhase * 1.09 + wobble) +
                .1 * math.cos(particlePhase * .23 + depth * 7));
        velocityY =
            factorY *
            (.22 * math.cos(particlePhase * .39 + wobble) +
                .16 * math.sin(particlePhase * .83 + depth * 6.2));
      case 'stars':
        final sway = speed * strength;
        x += sway * .025 * _integratedSin(phaseSeed, phaseRate, t, 1, hueShift);
        y += sway * .018 * _integratedCos(phaseSeed, phaseRate, t, .7, depth);
        velocityX = sway * .025 * math.sin(particlePhase + hueShift);
        velocityY = sway * .018 * math.cos(particlePhase * .7 + depth);
      case 'snow':
        final sway = speed * strength;
        y += speed * t * (.08 + depth * .18);
        x +=
            sway *
            (.18 * _integratedSin(phaseSeed, phaseRate, t, .86, hueShift) +
                .06 * _integratedCos(phaseSeed, phaseRate, t, .32, wobble));
        velocityX =
            sway *
            (.18 * math.sin(particlePhase * .86 + hueShift) +
                .06 * math.cos(particlePhase * .32 + wobble));
        velocityY = speed * (.08 + depth * .18);
      case 'petals':
      case 'leaves':
        final sway = speed * strength;
        y += speed * t * (.055 + depth * .14);
        x +=
            sway *
            (.31 * _integratedSin(phaseSeed, phaseRate, t, 1.05, hueShift) +
                .1 * _integratedCos(phaseSeed, phaseRate, t, .39, wobble));
        velocityX =
            sway *
            (.31 * math.sin(particlePhase * 1.05 + hueShift) +
                .1 * math.cos(particlePhase * .39 + wobble));
        velocityY = speed * (.055 + depth * .14);
      case 'bubbles':
        final sway = speed * strength;
        y -= speed * t * (.075 + depth * .18);
        x +=
            sway *
            (.28 * _integratedSin(phaseSeed, phaseRate, t, .78, hueShift) +
                .09 * _integratedCos(phaseSeed, phaseRate, t, .31, wobble));
        velocityX =
            sway *
            (.28 * math.sin(particlePhase * .78 + hueShift) +
                .09 * math.cos(particlePhase * .31 + wobble));
        velocityY = -speed * (.075 + depth * .18);
      default:
        final sway = speed * strength;
        x +=
            speed * t * (.018 + depth * .035) +
            sway * .06 * _integratedSin(phaseSeed, phaseRate, t, .62, hueShift);
        y -= sway * .032 * _integratedSin(phaseSeed, phaseRate, t, .78, depth);
        velocityX =
            speed * (.018 + depth * .035) +
            sway * .06 * math.sin(particlePhase * .62 + hueShift);
        velocityY = -sway * .032 * math.sin(particlePhase * .78 + depth);
    }
    x = _wrapped(x, -.08, 1.08);
    y = _wrapped(y, -.1, 1.1);
    return _ParticleMotion(
      center: Offset(x * size.width, y * size.height),
      velocity: Offset(velocityX * size.width, velocityY * size.height),
    );
  }

  double _integratedSin(
    double phaseSeed,
    double phaseRate,
    double elapsedSeconds,
    double multiplier,
    double offset,
  ) {
    final rate = phaseRate * multiplier;
    if (rate.abs() < 1e-8) {
      return math.sin(phaseSeed * multiplier + offset) * elapsedSeconds;
    }
    return (math.cos(phaseSeed * multiplier + offset) -
            math.cos(
              (phaseSeed + phaseRate * elapsedSeconds) * multiplier + offset,
            )) /
        rate;
  }

  double _integratedCos(
    double phaseSeed,
    double phaseRate,
    double elapsedSeconds,
    double multiplier,
    double offset,
  ) {
    final rate = phaseRate * multiplier;
    if (rate.abs() < 1e-8) {
      return math.cos(phaseSeed * multiplier + offset) * elapsedSeconds;
    }
    return (math.sin(
              (phaseSeed + phaseRate * elapsedSeconds) * multiplier + offset,
            ) -
            math.sin(phaseSeed * multiplier + offset)) /
        rate;
  }

  double _wrapped(double value, double minimum, double maximum) {
    final span = maximum - minimum;
    return (value - minimum) % span + minimum;
  }

  double _particleHue(String style, double hueShift) => switch (style) {
    'embers' => 20 + hueShift * .06,
    'snow' => 202 + hueShift * .035,
    'stars' => 218 + hueShift * .08,
    'petals' || 'leaves' => 102 + hueShift * .07,
    'fireflies' => 62 + hueShift * .04,
    'bubbles' => 184 + hueShift * .05,
    _ => settings.hue + hueShift * .04,
  };

  Color _particleColor(String style, double hue, double alpha, bool neon) {
    final saturation = neon
        ? .96
        : switch (style) {
            'snow' => .24,
            'bubbles' => .44,
            'petals' || 'leaves' => .42,
            'fireflies' => .84,
            'fumes' => .36,
            _ => .72,
          };
    final lightness = neon
        ? .67
        : switch (style) {
            'embers' => .58,
            'stars' => .76,
            'snow' => .88,
            'bubbles' => .76,
            'petals' || 'leaves' => .48,
            'fireflies' => .72,
            'fumes' => .62,
            _ => .62,
          };
    return HSLColor.fromAHSL(
      alpha,
      (hue % 360 + 360) % 360,
      saturation,
      lightness,
    ).toColor();
  }

  void _drawRadialParticleBlur(
    Canvas canvas,
    String style,
    Offset center,
    double radius,
    Color color,
    double blur,
    double particlePhase,
  ) {
    final (boost, capX, capY, alphaScale) = switch (style) {
      'fireflies' => (1.25, 34.0 + blur * 32, 24.0 + blur * 24, .64),
      'embers' => (1.26, 40.0 + blur * 34, 30.0 + blur * 26, .72),
      'bubbles' => (1.08, 44.0 + blur * 28, 44.0 + blur * 28, .62),
      'snow' => (.78, 22.0 + blur * 12, 22.0 + blur * 12, .48),
      _ => (1.0, 38.0 + blur * 24, 30.0 + blur * 18, .58),
    };
    final radiusX = math.min(radius * (1.62 + blur * 4.85) * boost, capX);
    final radiusY = math.min(radius * (1.22 + blur * 3.75) * boost, capY);
    final rect = Rect.fromCenter(
      center: center,
      width: radiusX * 2,
      height: radiusY * 2,
    );
    final origin = Alignment(
      math.sin(particlePhase) * .12,
      math.cos(particlePhase * .7) * .1,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: origin,
          colors: <Color>[
            color.withAlpha(
              _scaledAlpha(color, (.075 + blur * .15) * alphaScale),
            ),
            color.withAlpha(
              _scaledAlpha(color, (.036 + blur * .075) * alphaScale),
            ),
            color.withAlpha(
              _scaledAlpha(color, (.01 + blur * .026) * alphaScale),
            ),
            color.withAlpha(0),
          ],
          stops: const <double>[0, .38, .76, 1],
        ).createShader(rect),
    );
  }

  void _drawParticleSoftening(
    Canvas canvas, {
    required String style,
    required Offset center,
    required double radius,
    required Color color,
    required double blur,
    required double particlePhase,
    required double spin,
    required double depth,
    required Offset velocity,
    required double elapsedSeconds,
    required double wobble,
    required double hueShift,
  }) {
    for (var index = 0; index < 6; index++) {
      final angle = wobble + particlePhase * .08 + index * math.pi / 3;
      final spread = radius * (.45 + blur * 1.9);
      _drawParticleShape(
        canvas,
        center + Offset(math.cos(angle), math.sin(angle)) * spread,
        radius * (1 + blur * .58),
        particlePhase,
        spin,
        Paint()
          ..color = color.withAlpha(_scaledAlpha(color, .032 + blur * .055)),
        style,
        depth,
        velocity,
        elapsedSeconds,
      );
    }
    if (blur < .18) return;
    for (var index = 0; index < 5; index++) {
      final angle =
          hueShift * .013 + particlePhase * .045 + index * math.pi * 2 / 5;
      final spread = radius * (1.05 + blur * 3.05);
      _drawParticleShape(
        canvas,
        center + Offset(math.cos(angle), math.sin(angle)) * spread,
        radius * (1 + blur * .95),
        particlePhase,
        spin,
        Paint()
          ..color = color.withAlpha(_scaledAlpha(color, .011 + blur * .022)),
        style,
        depth,
        velocity,
        elapsedSeconds,
      );
    }
  }

  void _drawParticleShape(
    Canvas canvas,
    Offset center,
    double radius,
    double particlePhase,
    double spin,
    Paint paint,
    String style,
    double depth,
    Offset velocity,
    double elapsedSeconds,
  ) {
    switch (style) {
      case 'embers':
        _drawEmber(canvas, center, radius * .82, spin, velocity, paint);
      case 'snow':
        _drawSnow(canvas, center, radius * .72, spin, paint);
      case 'stars':
        _drawStar(
          canvas,
          center,
          radius * .86,
          spin + elapsedSeconds * .04,
          paint,
        );
      case 'bubbles':
        _drawBubble(canvas, center, radius * 1.08, paint);
      case 'fireflies':
        _drawFirefly(
          canvas,
          center,
          radius * 1.08,
          particlePhase,
          spin,
          depth,
          velocity,
          paint,
        );
      case 'leaves':
        _drawLeaf(
          canvas,
          center,
          radius * 1.15,
          spin + particlePhase * .16,
          paint,
          petal: true,
        );
      case 'petals':
        _drawLeaf(
          canvas,
          center,
          radius * 1.15,
          spin + particlePhase * .16,
          paint,
          petal: false,
        );
      case 'fumes':
        _drawFume(canvas, center, radius * 1.35, particlePhase, paint);
      default:
        _drawFume(canvas, center, radius * 1.35, particlePhase, paint);
    }
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Paint source,
  ) {
    final paint = Paint()
      ..color = source.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(.65, radius * .18);
    for (var ray = 0; ray < 2; ray++) {
      final angle = phase + ray * math.pi / 2;
      final vector = Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawLine(center - vector, center + vector, paint);
    }
    canvas.drawCircle(
      center,
      radius * .18,
      Paint()..color = source.color.withAlpha(_scaledAlpha(source.color, .62)),
    );
  }

  void _drawSnow(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Paint source,
  ) {
    if (radius < 2.6) {
      canvas.drawCircle(center, radius * .45, source);
      return;
    }
    final paint = Paint()
      ..color = source.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(.5, radius * .11);
    for (var ray = 0; ray < 6; ray++) {
      final angle = phase * .18 + ray * math.pi / 3;
      final vector = Offset(math.cos(angle), math.sin(angle)) * radius * .58;
      canvas.drawLine(center - vector, center + vector, paint);
      if (ray.isEven) {
        final branch = center + vector * .55;
        final side = angle + math.pi / 6;
        canvas.drawLine(
          branch,
          branch - Offset(math.cos(side), math.sin(side)) * radius * .18,
          paint,
        );
      }
    }
  }

  void _drawLeaf(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Paint source, {
    required bool petal,
  }) {
    final angle = phase * .62;
    final forward = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-forward.dy, forward.dx);
    final tip = center + forward * radius;
    final base = center - forward * radius * (petal ? .42 : .58);
    final breadth = radius * (petal ? .52 : .34);
    final left = center + normal * breadth - forward * radius * .06;
    final right = center - normal * breadth - forward * radius * .06;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(left.dx, left.dy, base.dx, base.dy)
      ..quadraticBezierTo(right.dx, right.dy, tip.dx, tip.dy)
      ..close();
    canvas.drawPath(path, source);
    final vein = Paint()
      ..color = Color.fromARGB(
        _scaledAlpha(source.color, .55),
        petal ? 255 : 210,
        petal ? 218 : 238,
        petal ? 185 : 166,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.5, radius * .09)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(base, tip, vein);
  }

  void _drawEmber(
    Canvas canvas,
    Offset center,
    double radius,
    double spin,
    Offset velocity,
    Paint source,
  ) {
    radius = math.max(2.2, radius);
    final unscaled = velocity.distance > .04
        ? velocity
        : Offset(math.sin(spin) * .18, -1);
    final forward = unscaled / unscaled.distance;
    final normal = Offset(-forward.dy, forward.dx);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 2.7,
        height: radius * 2.16,
      ),
      Paint()
        ..color = const Color(
          0xFFFF9A38,
        ).withAlpha(_scaledAlpha(source.color, .11)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + normal * math.sin(spin) * radius * .22,
        width: radius * 1.76,
        height: radius * 1.44,
      ),
      Paint()..color = source.color.withAlpha(_scaledAlpha(source.color, .42)),
    );
    canvas.drawLine(
      center -
          forward * radius * 2.15 +
          normal * math.sin(spin * .7) * radius * .42,
      center - forward * radius * .36,
      Paint()
        ..color = const Color(
          0xFFFF8024,
        ).withAlpha(_scaledAlpha(source.color, .16))
        ..strokeWidth = math.max(.7, radius * .24)
        ..strokeCap = StrokeCap.round,
    );
    final tip = center + forward * radius * .88;
    final base = center - forward * radius * .9;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        center.dx -
            forward.dx * radius * .58 +
            normal.dx * radius * (.36 + math.sin(spin) * .08),
        center.dy -
            forward.dy * radius * .58 +
            normal.dy * radius * (.36 + math.sin(spin) * .08),
        base.dx,
        base.dy,
      )
      ..quadraticBezierTo(
        center.dx -
            forward.dx * radius * .58 -
            normal.dx * radius * (.42 + math.cos(spin) * .07),
        center.dy -
            forward.dy * radius * .58 -
            normal.dy * radius * (.42 + math.cos(spin) * .07),
        tip.dx,
        tip.dy,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = source.color.withAlpha(_scaledAlpha(source.color, .78)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + forward * radius * .06,
        width: radius * .42,
        height: radius * .64,
      ),
      Paint()
        ..color = const Color(
          0xFFFFE07D,
        ).withAlpha(_scaledAlpha(source.color, 1.18)),
    );
  }

  void _drawBubble(Canvas canvas, Offset center, double radius, Paint source) {
    final outline = Paint()
      ..color = source.color.withAlpha(_scaledAlpha(source.color, .82))
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.55, radius * .13);
    canvas.drawCircle(center, radius, outline);
    canvas.drawCircle(
      center.translate(-radius * .34, -radius * .34),
      radius * .16,
      Paint()
        ..color = const Color(
          0xFFE8FFFA,
        ).withAlpha(_scaledAlpha(source.color, .52)),
    );
  }

  void _drawFirefly(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    double spin,
    double depth,
    Offset velocity,
    Paint source,
  ) {
    radius = math.max(5.2, radius * .92);
    final pulse =
        (.58 +
                math.sin(phase * 2.2 + depth * 4.2) * .28 +
                math.sin(phase * 5.1) * .16)
            .clamp(.18, 1.0);
    final angle = velocity.distance > .01
        ? math.atan2(velocity.dy, velocity.dx)
        : spin * .18 + math.sin(phase * .42 + depth * 2.4) * .46;
    final forward = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-forward.dy, forward.dx);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 3.7,
        height: radius * 2.72,
      ),
      Paint()
        ..color = source.color.withAlpha(
          _scaledAlpha(source.color, .16 * pulse),
        ),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center - forward * radius * .35,
        width: radius * 2.04,
        height: radius * 1.48,
      ),
      Paint()
        ..color = source.color.withAlpha(
          _scaledAlpha(source.color, .3 * pulse),
        ),
    );
    final wingColor = const Color(
      0xFFF7FFD6,
    ).withAlpha(_scaledAlpha(source.color, .68));
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
    final wingRoot = center - forward * radius * .08;
    final wingPaint = Paint()
      ..color = wingColor
      ..strokeWidth = math.max(.7, radius * .12);
    canvas.drawLine(
      wingRoot,
      center + normal * radius * .84 - forward * radius * .32,
      wingPaint,
    );
    canvas.drawLine(
      wingRoot,
      center - normal * radius * .84 - forward * radius * .32,
      wingPaint,
    );
    final bodyPaint = Paint()
      ..color = const Color(
        0xFF1F1D12,
      ).withAlpha(_scaledAlpha(source.color, .84))
      ..strokeWidth = math.max(.75, radius * .2)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center - forward * radius * .52,
      center + forward * radius * .46,
      bodyPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + forward * radius * .54,
        width: radius * .4,
        height: radius * .34,
      ),
      bodyPaint,
    );
    final abdomen = center - forward * radius * .55;
    canvas.drawOval(
      Rect.fromCenter(
        center: abdomen,
        width: radius * .96,
        height: radius * .72,
      ),
      Paint()
        ..color = source.color.withAlpha(
          _scaledAlpha(source.color, (1.08 + depth * .2) * pulse),
        ),
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
        ).withAlpha(_scaledAlpha(source.color, .9 * pulse)),
    );
  }

  void _drawFume(
    Canvas canvas,
    Offset center,
    double radius,
    double phase,
    Paint source,
  ) {
    final path = Path()
      ..moveTo(center.dx - radius, center.dy + math.sin(phase) * radius * .2)
      ..cubicTo(
        center.dx - radius * .35,
        center.dy - radius * .55,
        center.dx + radius * .25,
        center.dy + radius * .58,
        center.dx + radius,
        center.dy - math.cos(phase) * radius * .22,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = source.color.withAlpha(_scaledAlpha(source.color, .34))
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.65, radius * .12)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 1.84,
        height: radius * .76,
      ),
      Paint()..color = source.color.withAlpha(_scaledAlpha(source.color, .13)),
    );
  }

  static int _scaledAlpha(Color color, double factor) =>
      (color.a * 255 * factor).round().clamp(0, 255);

  @override
  bool shouldRepaint(covariant StandardAtmospherePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.settings != settings;
}

@immutable
final class _ParticleMotion {
  const _ParticleMotion({required this.center, required this.velocity});

  final Offset center;
  final Offset velocity;
}

@immutable
final class _ParticleSeed {
  const _ParticleSeed({
    required this.x,
    required this.y,
    required this.depth,
    required this.phase,
    required this.hueShift,
    required this.size,
    required this.spin,
    required this.wobble,
  });

  final double x;
  final double y;
  final double depth;
  final double phase;
  final double hueShift;
  final double size;
  final double spin;
  final double wobble;
}

/// Compatibility implementation for the seeded `System.Random` sequence used
/// by Avalonia's `AtmosphereControl` (`new Random(42)`).
final class _DotNetRandom {
  _DotNetRandom(int seed) {
    const seedConstant = 161803398;
    final subtraction = seed == -2147483648 ? 2147483647 : seed.abs();
    var mj = seedConstant - subtraction;
    var mk = 1;
    _seedArray[55] = mj;
    for (var index = 1; index < 55; index++) {
      final slot = (21 * index) % 55;
      _seedArray[slot] = mk;
      mk = mj - mk;
      if (mk < 0) mk += _maximum;
      mj = _seedArray[slot];
    }
    for (var pass = 1; pass < 5; pass++) {
      for (var index = 1; index < 56; index++) {
        _seedArray[index] -= _seedArray[1 + (index + 30) % 55];
        if (_seedArray[index] < 0) _seedArray[index] += _maximum;
      }
    }
    _next = 0;
    _nextPair = 21;
  }

  static const int _maximum = 2147483647;
  static const double _scale = 1 / _maximum;

  final List<int> _seedArray = List<int>.filled(56, 0);
  late int _next;
  late int _nextPair;

  double nextDouble() {
    var next = _next + 1;
    if (next >= 56) next = 1;
    var nextPair = _nextPair + 1;
    if (nextPair >= 56) nextPair = 1;
    var result = _seedArray[next] - _seedArray[nextPair];
    if (result == _maximum) result--;
    if (result < 0) result += _maximum;
    _seedArray[next] = result;
    _next = next;
    _nextPair = nextPair;
    return result * _scale;
  }
}
