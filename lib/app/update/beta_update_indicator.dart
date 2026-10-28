import 'dart:async';

import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'beta_update.dart';

/// Compact, global title-bar offer for Black Spirit Life updates.
///
/// One activation keeps the existing download, prepare, save, restart and
/// durability flow. This widget only changes its presentation.
class BetaUpdateIndicator extends StatefulWidget {
  const BetaUpdateIndicator({
    required this.controller,
    required this.onUpdateNow,
    super.key,
  });

  static const double height = 40;
  static const double expandedWidth = 128;
  static const double compactWidth = 42;
  static const Key buttonKey = ValueKey<String>('beta-update-title-button');
  static const Key iconKey = ValueKey<String>('beta-update-title-icon');
  static const Key availableContentKey = ValueKey<String>(
    'beta-update-title-available-content',
  );
  static const Key actionPanelKey = ValueKey<String>(
    'beta-update-title-action-panel',
  );
  static const Key progressKey = ValueKey<String>('beta-update-title-progress');

  // Retained as public test keys so older callers compile while the approved
  // compact design deliberately omits the former petals, savings row and arrow.
  static const Key petalRainKey = ValueKey<String>(
    'beta-update-strip-petal-rain',
  );
  static const Key savingsKey = ValueKey<String>('beta-update-strip-savings');
  static const Key arrowKey = ValueKey<String>('beta-update-strip-arrow');

  final BetaUpdateController controller;
  final Future<void> Function() onUpdateNow;

  @override
  State<BetaUpdateIndicator> createState() => _BetaUpdateIndicatorState();
}

class _BetaUpdateIndicatorState extends State<BetaUpdateIndicator>
    with SingleTickerProviderStateMixin {
  static const _attentionDuration = Duration(milliseconds: 5200);

  late final AnimationController _attention = AnimationController(
    vsync: this,
    duration: _attentionDuration,
  );
  bool _activationPending = false;
  String? _activeOffer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(BetaUpdateIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    _syncAnimation();
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(_syncAnimation);
  }

  bool get _canBreathe =>
      widget.controller.snapshot.phase == BetaUpdatePhase.available &&
      !_activationPending &&
      !widget.controller.operationPending;

  String get _offerKey {
    final snapshot = widget.controller.snapshot;
    return <Object>[
      snapshot.currentVersion,
      snapshot.targetVersion,
      snapshot.sizeBytes,
      snapshot.fullSizeBytes,
      snapshot.deltaCount,
      snapshot.testOnly,
    ].join('|');
  }

  void _syncAnimation() {
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_canBreathe || reduceMotion || !TickerMode.valuesOf(context).enabled) {
      _attention
        ..stop()
        ..value = 0;
      if (widget.controller.snapshot.phase != BetaUpdatePhase.available) {
        _activeOffer = null;
      }
      return;
    }
    final offer = _offerKey;
    if (_activeOffer != offer || !_attention.isAnimating) {
      _activeOffer = offer;
      _attention.value = 0;
      unawaited(_attention.repeat());
    }
  }

  Future<void> _activate() async {
    final phase = widget.controller.snapshot.phase;
    if (_activationPending || widget.controller.operationPending) return;
    if (phase != BetaUpdatePhase.available && phase != BetaUpdatePhase.ready) {
      return;
    }
    setState(() {
      _activationPending = true;
      _syncAnimation();
    });
    try {
      await widget.onUpdateNow();
    } finally {
      if (mounted) {
        setState(() {
          _activationPending = false;
          _syncAnimation();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _attention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    if (!snapshot.showsIndicator) return const SizedBox.shrink();

    final spec = context.visualTheme;
    final actionable =
        !_activationPending &&
        !widget.controller.operationPending &&
        (snapshot.phase == BetaUpdatePhase.available ||
            snapshot.phase == BetaUpdatePhase.ready);
    final narrow = MediaQuery.sizeOf(context).width < 680;
    final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    final compact = narrow || enlarged;
    final width = compact
        ? BetaUpdateIndicator.compactWidth
        : BetaUpdateIndicator.expandedWidth;
    final label = _label(snapshot);
    final tooltip = _tooltip(snapshot);

    return SizedBox(
      width: width,
      height: BetaUpdateIndicator.height,
      child: Center(
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: Semantics(
            liveRegion: true,
            button: actionable,
            enabled: actionable,
            label: tooltip,
            onTap: actionable ? () => unawaited(_activate()) : null,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: BetaUpdateIndicator.buttonKey,
                onTap: actionable ? _activate : null,
                customBorder: const _TightGlowBorder(),
                hoverColor: spec.palette.primaryBright.withAlpha(18),
                focusColor: spec.palette.primaryBright.withAlpha(28),
                splashColor: spec.palette.primaryBright.withAlpha(32),
                child: AnimatedBuilder(
                  animation: _attention,
                  builder: (context, _) {
                    final glow = _canBreathe
                        ? _tightGlow(_attention.value)
                        : 0.0;
                    return RepaintBoundary(
                      child: SizedBox(
                        key: BetaUpdateIndicator.availableContentKey,
                        width: width,
                        height: 36,
                        child: CustomPaint(
                          painter: _TightGlowFramePainter(
                            spec: spec,
                            glow: glow,
                            compact: compact,
                            enabled: actionable,
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: compact ? 4 : 0,
                              right: compact ? 4 : 14,
                            ),
                            child: Row(
                              children: <Widget>[
                                _UpdateBadge(
                                  snapshot: snapshot,
                                  spec: spec,
                                  glow: glow,
                                ),
                                if (!compact) ...<Widget>[
                                  const SizedBox(width: 16),
                                  Flexible(
                                    child: Text(
                                      label,
                                      key: BetaUpdateIndicator.actionPanelKey,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: spec.typography.button.copyWith(
                                        color: actionable
                                            ? spec.palette.text
                                            : spec.palette.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: .15,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Transform.rotate(
                                    angle: .785398,
                                    child: Container(
                                      width: 3,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: spec.palette.primaryBright
                                            .withAlpha(actionable ? 190 : 86),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({
    required this.snapshot,
    required this.spec,
    required this.glow,
  });

  final BetaUpdateSnapshot snapshot;
  final ThemeSpec spec;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final downloading = snapshot.phase == BetaUpdatePhase.downloading;
    return SizedBox.square(
      key: BetaUpdateIndicator.iconKey,
      dimension: 34,
      child: CustomPaint(
        painter: _TightGlowBadgePainter(spec: spec, glow: glow),
        child: Center(
          child: downloading
              ? SizedBox.square(
                  key: BetaUpdateIndicator.progressKey,
                  dimension: 20,
                  child: CircularProgressIndicator(
                    value: snapshot.progress > 0 ? snapshot.progress : null,
                    strokeWidth: 1.8,
                    color: spec.palette.primaryBright,
                    backgroundColor: spec.palette.text.withAlpha(28),
                  ),
                )
              : snapshot.phase == BetaUpdatePhase.available
              ? SizedBox.square(
                  dimension: 16,
                  child: CustomPaint(
                    painter: _DownloadGlyphPainter(spec: spec, glow: glow),
                  ),
                )
              : Icon(
                  snapshot.phase == BetaUpdatePhase.ready
                      ? Icons.restart_alt_rounded
                      : snapshot.phase == BetaUpdatePhase.applying
                      ? Icons.autorenew_rounded
                      : Icons.system_update_alt_rounded,
                  size: 18,
                  color: spec.palette.text,
                  shadows: glow <= 0
                      ? null
                      : <Shadow>[
                          Shadow(
                            color: spec.palette.primaryBright.withAlpha(
                              (glow * 150).round(),
                            ),
                            blurRadius: 2,
                          ),
                        ],
                ),
        ),
      ),
    );
  }
}

class _TightGlowFramePainter extends CustomPainter {
  const _TightGlowFramePainter({
    required this.spec,
    required this.glow,
    required this.compact,
    required this.enabled,
  });

  final ThemeSpec spec;
  final double glow;
  final bool compact;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    // Compact mode is the crest alone, not a second frame behind the crest.
    if (compact) return;
    final material = _UpdateMetal(spec);
    final face = Rect.fromLTRB(18, 4, size.width, 32);
    final path = _taperedFace(face);
    final edge = material.edge(1 + glow * 1.8);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = material.light.withValues(alpha: glow * .9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
    // The breathing rim is a separate layer; the opaque face cannot cover it.
    canvas.drawPath(path, Paint()..shader = edge.createShader(face));
    final inner = _taperedFace(face.deflate(1));
    canvas.drawPath(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [material.faceTop, material.faceBottom, material.faceBounce],
          stops: const [0, .75, 1],
        ).createShader(face),
    );
    // Restrained lower copper reflection, as in the approved Copper light face.
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawRect(
      face,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomLeft,
          radius: 1.1,
          colors: [material.copper.withAlpha(56), material.copper.withAlpha(0)],
        ).createShader(face),
    );
    canvas.restore();
    canvas.drawPath(
      Path()
        ..moveTo(38, 7)
        ..lineTo(size.width - 15, 7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = material.light.withAlpha(enabled ? 78 : 35),
    );
    canvas.drawLine(
      const Offset(36, 29),
      Offset(size.width - 13, 29),
      Paint()
        ..strokeWidth = .7
        ..color = material.copper.withAlpha(124),
    );
  }

  @override
  bool shouldRepaint(_TightGlowFramePainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.glow != glow ||
      oldDelegate.compact != compact ||
      oldDelegate.enabled != enabled;
}

class _TightGlowBadgePainter extends CustomPainter {
  const _TightGlowBadgePainter({required this.spec, required this.glow});

  final ThemeSpec spec;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final material = _UpdateMetal(spec);
    final rect = Offset.zero & size;
    final path = _octagon(rect.deflate(.5), 8);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = material.light.withValues(alpha: glow * .72)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
    final brightness = 1 + glow * .48;
    canvas.drawPath(
      path,
      Paint()..shader = material.edge(brightness).createShader(rect),
    );
    canvas.drawPath(
      _octagon(rect.deflate(1.5), 7.3),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _brighten(material.crestTop, brightness),
            _brighten(material.crestBottom, brightness),
          ],
        ).createShader(rect),
    );
    // Inset diamond makes the arrow badge distinct from the app's box buttons.
    final center = rect.center;
    final diamond = Path()
      ..moveTo(center.dx, 3.7)
      ..lineTo(size.width - 3.7, center.dy)
      ..lineTo(center.dx, size.height - 3.7)
      ..lineTo(3.7, center.dy)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = .8
        ..color = _brighten(material.copper, brightness).withAlpha(100),
    );
  }

  @override
  bool shouldRepaint(_TightGlowBadgePainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.glow != glow;
}

class _DownloadGlyphPainter extends CustomPainter {
  const _DownloadGlyphPainter({required this.spec, required this.glow});
  final ThemeSpec spec;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    // Same open tray and downward arrow as the approved preview, not the
    // generic system-update window glyph. Scale a 16px vector without a font.
    canvas.save();
    canvas.scale(size.width / 16, size.height / 16);
    final arrow = Path()
      ..moveTo(8, 1.5)
      ..lineTo(8, 10)
      ..moveTo(4.5, 6.5)
      ..lineTo(8, 10)
      ..lineTo(11.5, 6.5)
      ..moveTo(2, 10.5)
      ..lineTo(2, 13.2)
      ..quadraticBezierTo(2, 14, 3, 14)
      ..lineTo(13, 14)
      ..quadraticBezierTo(14, 14, 14, 13.2)
      ..lineTo(14, 10.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.35;
    if (glow > 0) {
      canvas.drawPath(
        arrow,
        paint
          ..color = _UpdateMetal(spec).light.withValues(alpha: glow * .8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
    canvas.drawPath(
      arrow,
      paint
        ..color = spec.palette.text
        ..maskFilter = null,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DownloadGlyphPainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.glow != glow;
}

// Material tokens derive from the active theme, including Appearance changes.
// Dark faces retain the preview's copper/plum relationships; light themes keep
// their own paper/surface contrast rather than inheriting a dark badge.
class _UpdateMetal {
  _UpdateMetal(this.spec);
  final ThemeSpec spec;
  ThemePalette get palette => spec.palette;
  bool get dark => spec.brightness == Brightness.dark;
  Color get copper => Color.lerp(palette.trimBright, palette.warning, .55)!;
  Color get light => Color.lerp(copper, palette.text, .72)!;
  Color get faceTop =>
      Color.lerp(palette.surfaceRaised, palette.primary, dark ? .13 : .04)!;
  Color get faceBottom => palette.surface;
  Color get faceBounce => Color.lerp(palette.surface, palette.trimBright, .18)!;
  Color get crestTop => Color.lerp(faceTop, copper, .2)!;
  Color get crestBottom => Color.lerp(palette.surface, palette.primary, .12)!;

  LinearGradient edge(double brightness) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0, .19, .4, .69, .87, 1],
    colors:
        [
              light,
              copper,
              palette.trim,
              Color.lerp(copper, palette.text, .38)!,
              palette.trim,
              copper,
            ]
            .map(
              (color) => _brighten(
                color,
                dark ? brightness : 1 + (brightness - 1) * .18,
              ),
            )
            .toList(),
  );
}

Color _brighten(Color color, double amount) => Color.from(
  alpha: color.a,
  red: (color.r * amount).clamp(0, 1),
  green: (color.g * amount).clamp(0, 1),
  blue: (color.b * amount).clamp(0, 1),
);

Path _taperedFace(Rect rect) => Path()
  ..moveTo(rect.left, rect.top)
  ..lineTo(rect.right - 8, rect.top)
  ..lineTo(rect.right, rect.center.dy)
  ..lineTo(rect.right - 8, rect.bottom)
  ..lineTo(rect.left, rect.bottom)
  ..close();

class _TightGlowBorder extends ShapeBorder {
  const _TightGlowBorder();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _octagon(rect.deflate(2), 5);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _octagon(rect, 6);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

Path _octagon(Rect rect, double cut) => Path()
  ..moveTo(rect.left + cut, rect.top)
  ..lineTo(rect.right - cut, rect.top)
  ..lineTo(rect.right, rect.top + cut)
  ..lineTo(rect.right, rect.bottom - cut)
  ..lineTo(rect.right - cut, rect.bottom)
  ..lineTo(rect.left + cut, rect.bottom)
  ..lineTo(rect.left, rect.bottom - cut)
  ..lineTo(rect.left, rect.top + cut)
  ..close();

double _tightGlow(double value) {
  const curve = Cubic(.45, 0, .55, 1);
  if (value <= .44) {
    return curve.transform((value / .44).clamp(0, 1).toDouble());
  }
  if (value <= .88) {
    return curve.transform((1 - (value - .44) / .44).clamp(0, 1).toDouble());
  }
  return 0;
}

String _label(BetaUpdateSnapshot snapshot) => switch (snapshot.phase) {
  BetaUpdatePhase.available => 'Update',
  BetaUpdatePhase.downloading => '${(snapshot.progress * 100).round()}%',
  BetaUpdatePhase.ready => 'Restart',
  BetaUpdatePhase.applying => 'Updating',
  _ => 'Update',
};

String _tooltip(BetaUpdateSnapshot snapshot) {
  final version = snapshot.targetVersion.trim();
  final target = version.isEmpty ? 'the latest version' : 'version $version';
  return switch (snapshot.phase) {
    BetaUpdatePhase.available => <String>[
      snapshot.testOnly ? 'Test update available' : 'Update to $target',
      if (snapshot.sizeBytes > 0)
        '${_formatBytes(snapshot.sizeBytes)} ${snapshot.usesDelta ? 'patch' : 'download'}',
      snapshot.testOnly
          ? 'Runs the safe update demonstration'
          : 'Installs and restarts automatically',
    ].join(' · '),
    BetaUpdatePhase.downloading =>
      'Downloading $target · ${(snapshot.progress * 100).round()}%',
    BetaUpdatePhase.ready => '$target is ready · restart and apply',
    BetaUpdatePhase.applying => 'Applying $target',
    _ => 'Black Spirit Life update',
  };
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
