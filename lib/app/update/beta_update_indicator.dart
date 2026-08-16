import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'beta_update.dart';

/// Compact, always-in-app status strip for Black Spirit Life updates.
///
/// The strip deliberately avoids release-note dialogs and browser hand-offs:
/// one activation downloads the selected update and restarts when it is ready.
class BetaUpdateIndicator extends StatefulWidget {
  const BetaUpdateIndicator({
    required this.controller,
    required this.onUpdateNow,
    super.key,
  });

  static const double height = 44;
  static const Key buttonKey = ValueKey<String>('beta-update-strip');
  static const Key iconKey = ValueKey<String>('beta-update-strip-icon');
  static const Key sweepKey = ValueKey<String>('beta-update-strip-sweep');
  static const Key arrowKey = ValueKey<String>('beta-update-strip-arrow');
  static const Key progressKey = ValueKey<String>('beta-update-strip-progress');

  final BetaUpdateController controller;
  final Future<void> Function() onUpdateNow;

  @override
  State<BetaUpdateIndicator> createState() => _BetaUpdateIndicatorState();
}

class _BetaUpdateIndicatorState extends State<BetaUpdateIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _attention = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  );
  bool _activationPending = false;

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

  bool get _shouldAnimateAttention =>
      widget.controller.snapshot.phase == BetaUpdatePhase.available &&
      !_activationPending &&
      !widget.controller.operationPending;

  void _syncAnimation() {
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_shouldAnimateAttention && !reduceMotion) {
      if (!_attention.isAnimating) _attention.repeat();
    } else {
      _attention
        ..stop()
        ..value = 0;
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
    final presentation = _presentation(snapshot);
    final toneColor = spec.palette.forTone(presentation.tone);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animateAttention = _shouldAnimateAttention && !reduceMotion;
    final semanticsLabel = presentation.actionHint.isEmpty
        ? presentation.label
        : '${presentation.label}. ${presentation.actionHint}';

    return SizedBox(
      height: BetaUpdateIndicator.height,
      width: double.infinity,
      child: AppSurface(
        role: AppSurfaceRole.commandBand,
        tone: presentation.tone,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        child: Semantics(
          liveRegion: true,
          button: actionable,
          enabled: actionable,
          label: semanticsLabel,
          onTap: actionable ? () => unawaited(_activate()) : null,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: BetaUpdateIndicator.buttonKey,
              onTap: actionable ? _activate : null,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (animateAttention)
                    _UpdateAttentionLayer(
                      color: toneColor,
                      animation: _attention,
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: <Widget>[
                        _UpdateStatusGlyph(
                          key: BetaUpdateIndicator.iconKey,
                          snapshot: snapshot,
                          color: toneColor,
                          attention: _attention,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            presentation.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: spec.typography.label.copyWith(
                              color: spec.palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (presentation.actionHint.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 16),
                          Text(
                            presentation.actionHint,
                            style: spec.typography.meta.copyWith(
                              color: actionable
                                  ? spec.palette.primaryBright
                                  : spec.palette.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (actionable) ...<Widget>[
                            const SizedBox(width: 5),
                            _AnimatedActionArrow(
                              color: spec.palette.primaryBright,
                              animation: animateAttention
                                  ? _attention
                                  : kAlwaysDismissedAnimation,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateAttentionLayer extends StatelessWidget {
  const _UpdateAttentionLayer({required this.color, required this.animation});

  final Color color;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final pulse = _attentionPulse(animation.value);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: color.withAlpha(34 + (pulse * 58).round()),
                    width: 1.15,
                  ),
                ),
              ),
              Align(
                key: BetaUpdateIndicator.sweepKey,
                alignment: Alignment(-1.4 + animation.value * 2.8, 0),
                child: Transform.rotate(
                  angle: -.16,
                  child: FractionallySizedBox(
                    widthFactor: .15,
                    heightFactor: 1.7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.transparent,
                            color.withAlpha(18),
                            color.withAlpha(58),
                            color.withAlpha(18),
                            Colors.transparent,
                          ],
                          stops: const <double>[0, .28, .5, .72, 1],
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
  );
}

class _AnimatedActionArrow extends StatelessWidget {
  const _AnimatedActionArrow({required this.color, required this.animation});

  final Color color;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 21,
    child: Align(
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.translate(
          key: BetaUpdateIndicator.arrowKey,
          offset: Offset(_attentionPulse(animation.value) * 4, 0),
          child: child,
        ),
        child: Icon(Icons.arrow_forward_rounded, size: 17, color: color),
      ),
    ),
  );
}

class _UpdateStatusGlyph extends StatelessWidget {
  const _UpdateStatusGlyph({
    required this.snapshot,
    required this.color,
    required this.attention,
    super.key,
  });

  final BetaUpdateSnapshot snapshot;
  final Color color;
  final Animation<double> attention;

  @override
  Widget build(BuildContext context) {
    if (snapshot.phase == BetaUpdatePhase.downloading) {
      return SizedBox.square(
        key: BetaUpdateIndicator.progressKey,
        dimension: 22,
        child: CircularProgressIndicator(
          value: snapshot.progress > 0 ? snapshot.progress : null,
          strokeWidth: 2.4,
          color: color,
          backgroundColor: color.withAlpha(42),
        ),
      );
    }

    final icon = switch (snapshot.phase) {
      BetaUpdatePhase.ready => Icons.restart_alt_rounded,
      BetaUpdatePhase.offline => Icons.cloud_off_outlined,
      BetaUpdatePhase.error => Icons.error_outline_rounded,
      _ => Icons.system_update_alt_rounded,
    };
    return AnimatedBuilder(
      animation: attention,
      builder: (context, child) {
        final pulse = _attentionPulse(attention.value);
        return Transform.scale(
          scale: 1 + pulse * .11,
          child: Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(30 + (pulse * 38).round()),
              border: Border.all(
                color: color.withAlpha(50 + (pulse * 82).round()),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withAlpha(48 + (pulse * 112).round()),
                  blurRadius: 5 + pulse * 6,
                  spreadRadius: .5 + pulse * 1.5,
                ),
              ],
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        );
      },
    );
  }
}

double _attentionPulse(double progress) =>
    (1 - math.cos(progress * math.pi * 2)) / 2;

_UpdatePresentation _presentation(BetaUpdateSnapshot snapshot) {
  switch (snapshot.phase) {
    case BetaUpdatePhase.available:
      final version = snapshot.targetVersion.trim();
      final size = snapshot.sizeBytes > 0
          ? _formatBytes(snapshot.sizeBytes)
          : '';
      final kind = snapshot.usesDelta ? 'patch' : 'update';
      return _UpdatePresentation(
        label: <String>[
          snapshot.testOnly ? 'Update available (test)' : 'Update available',
          if (version.isNotEmpty) version,
          if (size.isNotEmpty) '$size $kind',
        ].join('  ·  '),
        actionHint: 'Update now',
        tone: AppSurfaceTone.info,
      );
    case BetaUpdatePhase.downloading:
      final percent = (snapshot.progress.clamp(0, 1) * 100).round();
      return _UpdatePresentation(
        label: snapshot.testOnly
            ? 'Testing update download  ·  $percent%'
            : 'Downloading update  ·  $percent%',
        actionHint: '',
        tone: AppSurfaceTone.info,
      );
    case BetaUpdatePhase.ready:
      return _UpdatePresentation(
        label: snapshot.testOnly ? 'Update test complete' : 'Update ready',
        actionHint: snapshot.testOnly ? '' : 'Restart to install',
        tone: AppSurfaceTone.success,
      );
    case BetaUpdatePhase.applying:
      return const _UpdatePresentation(
        label: 'Applying update',
        actionHint: 'Restarting',
        tone: AppSurfaceTone.info,
      );
    case BetaUpdatePhase.offline:
      return const _UpdatePresentation(
        label: 'Update check is offline',
        actionHint: 'Try again',
        tone: AppSurfaceTone.warning,
      );
    case BetaUpdatePhase.error:
      return const _UpdatePresentation(
        label: 'Update could not be checked',
        actionHint: 'Try again',
        tone: AppSurfaceTone.danger,
      );
    default:
      return const _UpdatePresentation(
        label: '',
        actionHint: '',
        tone: AppSurfaceTone.neutral,
      );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = -1;
  do {
    value /= 1024;
    unit += 1;
  } while (value >= 1024 && unit < units.length - 1);
  final decimals = value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

class _UpdatePresentation {
  const _UpdatePresentation({
    required this.label,
    required this.actionHint,
    required this.tone,
  });

  final String label;
  final String actionHint;
  final AppSurfaceTone tone;
}
