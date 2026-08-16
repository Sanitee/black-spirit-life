import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_identity.dart';
import '../../visual/components/retained_asset_image.dart';
import '../../visual/sakura_night_garden/sakura_spec.dart';

/// A short, non-blocking identity cue shown only while application data loads.
///
/// After the entrance, the World-root keeps a restrained breathing glow while
/// data loads. There is no minimum display time: the entire subtree can be
/// removed as soon as bootstrap completes.
class WorldRootStartupAnimation extends StatefulWidget {
  const WorldRootStartupAnimation({
    this.assetPath = AppIdentity.appIconAssetPath,
    this.dimension = 184,
    super.key,
  });

  final String assetPath;
  final double dimension;

  static const Duration duration = Duration(milliseconds: 1100);
  static const Duration breathingDuration = Duration(milliseconds: 2200);
  static const Key artworkKey = ValueKey<String>('world-root-startup-artwork');
  static const Key artworkFailureKey = ValueKey<String>(
    'world-root-startup-artwork-failure',
  );
  static const Key glowKey = ValueKey<String>('world-root-startup-glow');
  static const Key sheenKey = ValueKey<String>('world-root-startup-sheen');
  static const Key breathingKey = ValueKey<String>(
    'world-root-startup-breathing',
  );

  @override
  State<WorldRootStartupAnimation> createState() =>
      WorldRootStartupAnimationState();
}

class WorldRootStartupAnimationState extends State<WorldRootStartupAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: WorldRootStartupAnimation.duration,
  );
  late final AnimationController _breathing = AnimationController(
    vsync: this,
    duration: WorldRootStartupAnimation.breathingDuration,
  );
  bool _motionPreferenceApplied = false;
  bool _reducedMotionLatched = false;

  @visibleForTesting
  double get debugProgress => _entrance.value;

  @visibleForTesting
  double get debugBreathingProgress => _breathing.value;

  @visibleForTesting
  bool get debugIsAnimating => _entrance.isAnimating || _breathing.isAnimating;

  @visibleForTesting
  bool get debugIsBreathing => _breathing.isAnimating;

  @override
  void initState() {
    super.initState();
    _entrance.addStatusListener(_entranceStatusChanged);
  }

  void _entranceStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        _reducedMotionLatched ||
        _breathing.isAnimating) {
      return;
    }
    _breathing.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_motionPreferenceApplied) {
      _motionPreferenceApplied = true;
      if (reduceMotion) {
        _reducedMotionLatched = true;
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
      return;
    }
    if (reduceMotion && !_reducedMotionLatched) {
      _reducedMotionLatched = true;
      _entrance
        ..stop()
        ..value = 1;
      _breathing
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _entrance
      ..removeStatusListener(_entranceStatusChanged)
      ..dispose();
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.dimension,
    child: RepaintBoundary(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_entrance, _breathing]),
            builder: (context, _) {
              final progress = _entrance.value;
              final breath = Curves.easeInOut.transform(_breathing.value);
              final entrance = Curves.easeOutCubic.transform(
                (progress / .66).clamp(0.0, 1.0),
              );
              final fade = Curves.easeOut.transform(
                (progress / .36).clamp(0.0, 1.0),
              );
              final aura = (_auraOpacity(progress) + breath * .1).clamp(
                0.0,
                1.0,
              );
              final sheen = _sheenOpacity(progress);
              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: widget.dimension * .11,
                    right: widget.dimension * .11,
                    bottom: widget.dimension * .02,
                    height: widget.dimension * .72,
                    child: Transform.scale(
                      scale: (.88 + entrance * .12) * (1 + breath * .045),
                      child: Opacity(
                        key: WorldRootStartupAnimation.glowKey,
                        opacity: aura,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: Alignment(0, .42),
                              radius: .7,
                              colors: <Color>[
                                Color(0xCFA66C69),
                                Color(0x8066765F),
                                Color(0x000D0B0F),
                              ],
                              stops: <double>[0, .42, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, -breath * widget.dimension * .008),
                      child: Opacity(
                        opacity: fade,
                        child: Transform.scale(
                          key: WorldRootStartupAnimation.breathingKey,
                          scale: .92 + entrance * .08 + breath * .025,
                          child: SizedBox.square(
                            dimension: widget.dimension * .88,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                widget.dimension * .12,
                              ),
                              child: RetainedAssetImage(
                                assetPath: widget.assetPath,
                                assetLabel: 'Black Spirit Life World-root',
                                fit: BoxFit.contain,
                                imageKey: WorldRootStartupAnimation.artworkKey,
                                failureKey:
                                    WorldRootStartupAnimation.artworkFailureKey,
                                background: SakuraNightGardenSpec.canvasDeep,
                                foreground: SakuraNightGardenSpec.warmIvory,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(widget.dimension * .06),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          widget.dimension * .13,
                        ),
                        child: Opacity(
                          key: WorldRootStartupAnimation.sheenKey,
                          opacity: sheen,
                          child: CustomPaint(
                            painter: _WorldRootSheenPainter(
                              progress: _sheenProgress(progress),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

double _auraOpacity(double progress) {
  if (progress <= .58) {
    return Curves.easeOut.transform((progress / .58).clamp(0.0, 1.0)) * .42;
  }
  final settle = Curves.easeInOut.transform(
    ((progress - .58) / .42).clamp(0.0, 1.0),
  );
  return .42 + (.18 - .42) * settle;
}

double _sheenProgress(double progress) =>
    ((progress - .18) / .62).clamp(0.0, 1.0);

double _sheenOpacity(double progress) {
  final value = _sheenProgress(progress);
  if (value <= 0 || value >= 1) return 0;
  return math.sin(value * math.pi) * .34;
}

class _WorldRootSheenPainter extends CustomPainter {
  const _WorldRootSheenPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centerY = size.height * (.86 - .72 * progress);
    final band = Rect.fromLTWH(
      0,
      centerY - size.height * .11,
      size.width,
      size.height * .22,
    );
    canvas.drawRect(
      band,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x00A66C69),
            Color(0x8FCF9B83),
            Color(0xCFE8B0BF),
            Color(0x0066765F),
          ],
          stops: <double>[0, .42, .54, 1],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(covariant _WorldRootSheenPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
