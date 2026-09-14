import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'beta_update.dart';

/// In-app status notice for Black Spirit Life updates.
///
/// The strip deliberately avoids release-note dialogs and browser hand-offs:
/// one activation downloads the selected update and restarts when it is ready.
class BetaUpdateIndicator extends StatefulWidget {
  const BetaUpdateIndicator({
    required this.controller,
    required this.onUpdateNow,
    super.key,
  });

  static const double height = 84;
  static const Key buttonKey = ValueKey<String>('beta-update-strip');
  static const Key iconKey = ValueKey<String>('beta-update-strip-icon');
  static const Key availableContentKey = ValueKey<String>(
    'beta-update-strip-available-content',
  );
  static const Key petalRainKey = ValueKey<String>(
    'beta-update-strip-petal-rain',
  );
  static const Key savingsKey = ValueKey<String>('beta-update-strip-savings');
  static const Key actionPanelKey = ValueKey<String>(
    'beta-update-strip-action-panel',
  );
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
    duration: const Duration(milliseconds: 10400),
  );
  bool _activationPending = false;
  String? _playedAvailableOffer;

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

  String get _availableOfferKey {
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
    final phase = widget.controller.snapshot.phase;
    if (phase != BetaUpdatePhase.available) {
      _playedAvailableOffer = null;
      _attention
        ..stop()
        ..value = 0;
      return;
    }
    if (reduceMotion) {
      _playedAvailableOffer = _availableOfferKey;
      _attention
        ..stop()
        ..value = 1;
      return;
    }
    if (!_shouldAnimateAttention) {
      _attention
        ..stop()
        ..value = 0;
      return;
    }
    final offer = _availableOfferKey;
    if (_playedAvailableOffer != offer) {
      _playedAvailableOffer = offer;
      unawaited(_attention.forward(from: 0));
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
    final petalBase = Color.lerp(
      spec.palette.primary,
      const Color(0xFFCF7F98),
      .48,
    )!;
    final petalHighlight = Color.lerp(
      spec.palette.primaryBright,
      const Color(0xFFE8B0BF),
      .58,
    )!;
    final semanticsLabel = snapshot.phase == BetaUpdatePhase.available
        ? _availableSemanticsLabel(snapshot)
        : presentation.actionHint.isEmpty
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
                  ExcludeSemantics(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              toneColor.withAlpha(18),
                              Colors.transparent,
                              spec.palette.primary.withAlpha(13),
                            ],
                            stops: const <double>[0, .56, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (animateAttention)
                    SakuraPetalRain(
                      paintKey: BetaUpdateIndicator.petalRainKey,
                      animation: _attention,
                      baseColor: petalBase,
                      highlightColor: petalHighlight,
                    ),
                  if (snapshot.phase == BetaUpdatePhase.available)
                    _AvailableUpdateContent(
                      snapshot: snapshot,
                      actionable: actionable,
                      attention: animateAttention
                          ? _attention
                          : kAlwaysDismissedAnimation,
                      toneColor: toneColor,
                    )
                  else
                    _UpdateStatusContent(
                      snapshot: snapshot,
                      presentation: presentation,
                      actionable: actionable,
                      toneColor: toneColor,
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

class _AvailableUpdateContent extends StatelessWidget {
  const _AvailableUpdateContent({
    required this.snapshot,
    required this.actionable,
    required this.attention,
    required this.toneColor,
  });

  final BetaUpdateSnapshot snapshot;
  final bool actionable;
  final Animation<double> attention;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final version = snapshot.targetVersion.trim();
    final kind = snapshot.usesDelta ? 'patch' : 'update';
    final size = snapshot.sizeBytes > 0
        ? '${_formatBytes(snapshot.sizeBytes)} $kind'
        : '';
    final savingsBytes = snapshot.usesDelta
        ? snapshot.fullSizeBytes - snapshot.sizeBytes
        : 0;
    final savings = savingsBytes > 0
        ? '${_formatBytes(savingsBytes)} smaller than the full download'
        : '';
    final eyebrow = snapshot.testOnly
        ? 'TEST UPDATE'
        : snapshot.usesDelta
        ? 'DELTA UPDATE'
        : 'APP UPDATE';
    final heading = version.isEmpty
        ? 'A new version is ready'
        : 'Version $version is ready';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final simplified = MediaQuery.textScalerOf(context).scale(1) > 1.35;
        final behavior = snapshot.testOnly
            ? compact
                  ? 'simulates install flow'
                  : 'simulates the automatic install flow'
            : compact
            ? 'installs automatically'
            : 'installs and restarts automatically';
        final meta = <String>[
          if (size.isNotEmpty) size,
          behavior,
        ].join('  ·  ');
        final accessibleMeta = snapshot.testOnly
            ? <String>['TEST', if (size.isNotEmpty) size].join('  ·  ')
            : snapshot.usesDelta
            ? <String>[
                if (size.isNotEmpty) size,
                if (savingsBytes > 0) 'saves ${_formatBytes(savingsBytes)}',
              ].join('  ·  ')
            : size;
        return Padding(
          key: BetaUpdateIndicator.availableContentKey,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 18,
            vertical: 8,
          ),
          child: Row(
            children: <Widget>[
              _UpdateStatusGlyph(
                key: BetaUpdateIndicator.iconKey,
                snapshot: snapshot,
                color: toneColor,
                attention: attention,
              ),
              SizedBox(width: compact ? 9 : 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!simplified) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: toneColor,
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: toneColor.withAlpha(118),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              eyebrow,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: spec.typography.label.copyWith(
                                color: toneColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .78,
                                height: 1.05,
                              ),
                            ),
                          ),
                          if (!compact && savings.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                savings,
                                key: BetaUpdateIndicator.savingsKey,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: spec.typography.meta.copyWith(
                                  color: spec.palette.textMuted,
                                  fontSize: 10.5,
                                  height: 1.05,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: spec.typography.button.copyWith(
                        color: spec.palette.text,
                        fontSize: compact ? 13 : 14,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                      ),
                    ),
                    if (!simplified) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: spec.typography.meta.copyWith(
                          color: spec.palette.textMuted,
                          fontSize: compact ? 10 : 11,
                          height: 1.05,
                        ),
                      ),
                    ] else if (accessibleMeta.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        accessibleMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: spec.typography.meta.copyWith(
                          color: spec.palette.textMuted,
                          fontSize: compact ? 10 : 11,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 18),
              AnimatedBuilder(
                animation: attention,
                builder: (context, child) {
                  final pulse = _arrivalPulse(attention.value);
                  final actionColor = actionable
                      ? spec.palette.primaryBright
                      : spec.palette.textMuted;
                  return Container(
                    key: BetaUpdateIndicator.actionPanelKey,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          spec.palette.primary.withAlpha(
                            actionable ? 48 + (pulse * 20).round() : 20,
                          ),
                          spec.palette.surfaceInset.withAlpha(148),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        spec.geometry.buttonRadius + 2,
                      ),
                      border: Border.all(
                        color: actionColor.withAlpha(
                          actionable ? 128 + (pulse * 55).round() : 54,
                        ),
                      ),
                      boxShadow: pulse <= 0
                          ? const <BoxShadow>[]
                          : <BoxShadow>[
                              BoxShadow(
                                color: actionColor.withAlpha(
                                  (pulse * 70).round(),
                                ),
                                blurRadius: 8 + pulse * 8,
                              ),
                            ],
                    ),
                    child: child,
                  );
                },
                child: compact
                    ? SizedBox(
                        width: 92,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Update',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: spec.typography.button.copyWith(
                                  color: actionable
                                      ? spec.palette.primaryBright
                                      : spec.palette.textMuted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            _AnimatedActionArrow(
                              color: actionable
                                  ? spec.palette.primaryBright
                                  : spec.palette.textMuted,
                              animation: attention,
                            ),
                          ],
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'Update now',
                            style: spec.typography.button.copyWith(
                              color: actionable
                                  ? spec.palette.primaryBright
                                  : spec.palette.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          _AnimatedActionArrow(
                            color: actionable
                                ? spec.palette.primaryBright
                                : spec.palette.textMuted,
                            animation: attention,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateStatusContent extends StatelessWidget {
  const _UpdateStatusContent({
    required this.snapshot,
    required this.presentation,
    required this.actionable,
    required this.toneColor,
  });

  final BetaUpdateSnapshot snapshot;
  final _UpdatePresentation presentation;
  final bool actionable;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: <Widget>[
          _UpdateStatusGlyph(
            key: BetaUpdateIndicator.iconKey,
            snapshot: snapshot,
            color: toneColor,
            attention: kAlwaysDismissedAnimation,
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
                animation: kAlwaysDismissedAnimation,
              ),
            ],
          ],
        ],
      ),
    );
  }
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
          offset: Offset(_arrivalPulse(animation.value) * 4, 0),
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
        final pulse = _arrivalPulse(attention.value);
        return Transform.scale(
          scale: 1 + pulse * .07,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withAlpha(24 + (pulse * 28).round()),
              border: Border.all(
                color: color.withAlpha(76 + (pulse * 76).round()),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withAlpha(32 + (pulse * 82).round()),
                  blurRadius: 4 + pulse * 7,
                  spreadRadius: pulse * 1.2,
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

double _arrivalPulse(double progress) {
  if (progress <= 0 || progress >= .30) return 0;
  return math.sin(progress / .30 * math.pi);
}

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

String _availableSemanticsLabel(BetaUpdateSnapshot snapshot) {
  final version = snapshot.targetVersion.trim();
  final size = snapshot.sizeBytes > 0 ? _formatBytes(snapshot.sizeBytes) : '';
  final savingsBytes = snapshot.usesDelta
      ? snapshot.fullSizeBytes - snapshot.sizeBytes
      : 0;
  return <String>[
    snapshot.testOnly ? 'Test update available' : 'Update available',
    if (version.isNotEmpty) 'Version $version',
    if (size.isNotEmpty)
      snapshot.usesDelta ? '$size delta patch' : '$size full update',
    if (savingsBytes > 0)
      'Saves ${_formatBytes(savingsBytes)} compared with the full download',
    snapshot.testOnly
        ? 'Runs a local simulation and does not install a package'
        : 'Installs and restarts automatically',
    snapshot.testOnly ? 'Run update test' : 'Update now',
  ].join('. ');
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
