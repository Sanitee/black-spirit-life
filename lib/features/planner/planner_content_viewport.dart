import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../visual/visual.dart';
import 'planner_content_fit.dart';

/// A display-only zoom of the Planner body. The shell and its navigation stay
/// outside this viewport, and the same feature subtree is retained at 100%.
class PlannerContentViewport extends StatefulWidget {
  const PlannerContentViewport({
    required this.scale,
    required this.child,
    this.controller,
    this.onMaximumChanged,
    super.key,
  });

  final ValueListenable<double> scale;
  final Widget child;
  final ModeFeatureController? controller;
  final ValueChanged<double>? onMaximumChanged;

  @override
  State<PlannerContentViewport> createState() => _PlannerContentViewportState();
}

class _PlannerContentViewportState extends State<PlannerContentViewport> {
  double? _reportedMaximum;
  double _pendingMaximum = 1;
  bool _reportScheduled = false;

  void _reportMaximum(double maximum) {
    _pendingMaximum = maximum;
    if (_reportedMaximum == maximum || _reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted || _reportedMaximum == _pendingMaximum) return;
      _reportedMaximum = _pendingMaximum;
      widget.onMaximumChanged?.call(_pendingMaximum);
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = RepaintBoundary(child: widget.child);
    final controller = widget.controller;
    if (controller == null) return _viewport(context, child, const []);
    return ListenableBuilder(
      listenable: controller.plan,
      child: child,
      builder: (context, child) => _viewport(
        context,
        child!,
        plannerQueueFitBreakpoints(context, controller),
      ),
    );
  }

  Widget _viewport(
    BuildContext context,
    Widget content,
    List<double> queueBreakpoints,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final maximum = plannerContentMaximumScale(
        size: constraints.biggest,
        denseLayout: context.visualTheme.usesDenseSplitLayout,
        textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
        queueBreakpoints: queueBreakpoints,
      );
      _reportMaximum(maximum);
      return ValueListenableBuilder<double>(
        valueListenable: widget.scale,
        child: content,
        builder: (context, requested, child) {
          final scale = requested.isFinite
              ? requested.clamp(1.0, maximum)
              : 1.0;
          final logicalSize = constraints.biggest / scale;
          return ClipRect(
            key: const ValueKey('planner-content-viewport'),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: logicalSize.width,
              maxWidth: logicalSize.width,
              minHeight: logicalSize.height,
              maxHeight: logicalSize.height,
              child: Transform.scale(
                key: const ValueKey('planner-content-transform'),
                alignment: Alignment.topLeft,
                scale: scale,
                child: child,
              ),
            ),
          );
        },
      );
    },
  );
}

/// Stay on the current command/column/Need-row layout branch. These are the
/// existing Planner layout thresholds, expressed in body-viewport coordinates.
/// Round down to a whole percentage so the slider never crosses a fit boundary.
@visibleForTesting
double plannerContentMaximumScale({
  required Size size,
  required bool denseLayout,
  required double textScale,
  Iterable<double> queueBreakpoints = const [],
}) {
  if (!size.isFinite || size.width < 760 || size.height <= 0) return 1;
  final width = size.width;
  var minimumWidth = 760.0;
  void preserveBreakpoint(double threshold, {double? activateAt}) {
    if (width >= (activateAt ?? threshold)) {
      minimumWidth = math.max(minimumWidth, threshold);
    }
  }

  // The command band has 12 logical pixels of padding on each side.
  if (denseLayout && textScale <= 1.25 && width >= 844) {
    preserveBreakpoint(844);
  } else if (!denseLayout && textScale <= 1.25 && width >= 1134) {
    preserveBreakpoint(1134);
  } else if (textScale <= 1.5) {
    preserveBreakpoint(1124);
  }

  final needFraction = denseLayout ? .52 : .46;
  final needHeaderInset = denseLayout ? 44.0 : 24.0;
  preserveBreakpoint(12 + (400 + needHeaderInset) / needFraction);
  // Account for column/list insets, panel padding and the row's border.
  final needRowInset = denseLayout ? 74.0 : 54.0;
  final needRowBoundary =
      12 + (60 + 350 * textScale + needRowInset) / needFraction;
  preserveBreakpoint(needRowBoundary + 1, activateAt: needRowBoundary);
  for (final threshold in queueBreakpoints) {
    // Do not skip a currently-inline row in the small safety margin. At that
    // boundary 100% is preferable to moving one of its controls onto a new line.
    preserveBreakpoint(threshold + 1, activateAt: threshold);
  }

  final fit = math.min(1.25, width / minimumWidth);
  return ((fit * 100 + .000001).floor() / 100).clamp(1.0, 1.25);
}
