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
  static const double expandedWidth = 134;
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
    if (!_canBreathe || reduceMotion) {
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
                              left: 3,
                              right: compact ? 3 : 9,
                            ),
                            child: Row(
                              children: <Widget>[
                                _UpdateBadge(
                                  snapshot: snapshot,
                                  spec: spec,
                                  glow: glow,
                                ),
                                if (!compact) ...<Widget>[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      label,
                                      key: BetaUpdateIndicator.actionPanelKey,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: spec.typography.button.copyWith(
                                        color: actionable
                                            ? spec.palette.text
                                            : spec.palette.textMuted,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .15,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Transform.rotate(
                                    angle: .785398,
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: spec.palette.primaryBright
                                            .withAlpha(actionable ? 190 : 86),
                                        border: Border.all(
                                          color: spec.palette.text.withAlpha(
                                            actionable ? 116 : 54,
                                          ),
                                          width: .7,
                                        ),
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
    final face = Rect.fromLTRB(compact ? 1 : 15, 4, size.width - 1, 32);
    final path = _octagon(face, 5);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = spec.palette.primaryBright.withAlpha(
            (glow * .9 * 86).round(),
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + glow * 3),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.alphaBlend(
              spec.palette.primary.withAlpha(enabled ? 42 : 20),
              spec.palette.surface,
            ),
            spec.palette.surfaceInset,
          ],
        ).createShader(face),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = spec.palette.primaryBright.withAlpha(
          enabled ? 126 + (glow * 92).round() : 56,
        ),
    );
    canvas.drawPath(
      _octagon(face.deflate(2), 4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = spec.palette.text.withAlpha(
          enabled ? 28 + (glow * 42).round() : 14,
        ),
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
    final rect = Offset.zero & size;
    final path = _octagon(rect.deflate(.7), 7);
    if (glow > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = spec.palette.primaryBright.withAlpha(
            (glow * .72 * 108).round(),
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + glow * 2),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.alphaBlend(
              spec.palette.primaryBright.withAlpha(52),
              spec.palette.surface,
            ),
            spec.palette.surfaceInset,
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = spec.palette.primaryBright.withAlpha(
          152 + (glow * 82).round(),
        ),
    );
  }

  @override
  bool shouldRepaint(_TightGlowBadgePainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.glow != glow;
}

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
