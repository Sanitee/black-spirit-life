import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared by Crafting's grid and zoom limits so zoom cannot drop a column.
abstract final class OpportunityCraftCardLayout {
  static const minimumWidth = 300.0;
  static const maximumWidth = 332.0;
  static const maximumColumns = 6;
}

/// Width of the longest existing run, used to retain compact toolbar rows.
double opportunitiesWrapMinimumWidth(
  List<double> widths, {
  required double available,
  required double spacing,
}) {
  var run = 0.0;
  var maximum = 0.0;
  for (final rawWidth in widths) {
    final width = math.min(rawWidth, available);
    if (run > 0 && run + spacing + width > available) {
      maximum = math.max(maximum, run);
      run = width;
    } else {
      run += (run == 0 ? 0 : spacing) + width;
    }
  }
  return math.max(maximum, run);
}

/// Presentation-only zoom. The retained child is not rebuilt by slider ticks.
class OpportunitiesContentViewport extends StatefulWidget {
  const OpportunitiesContentViewport({
    required this.scale,
    required this.child,
    required this.maximumFor,
    this.onMaximumChanged,
    super.key,
  });
  final ValueListenable<double> scale;
  final Widget child;
  final double Function(Size size) maximumFor;
  final ValueChanged<double>? onMaximumChanged;
  @override
  State<OpportunitiesContentViewport> createState() =>
      _OpportunitiesContentViewportState();
}

class _OpportunitiesContentViewportState
    extends State<OpportunitiesContentViewport> {
  double? _reportedMaximum;
  double _pendingMaximum = 1;
  bool _reportScheduled = false;
  void _reportMaximum(double value) {
    _pendingMaximum = value;
    if (_reportedMaximum == value || _reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted || _reportedMaximum == _pendingMaximum) return;
      _reportedMaximum = _pendingMaximum;
      widget.onMaximumChanged?.call(_pendingMaximum);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maximum = widget.maximumFor(constraints.biggest);
      _reportMaximum(maximum);
      return ValueListenableBuilder<double>(
        valueListenable: widget.scale,
        child: RepaintBoundary(child: widget.child),
        builder: (context, requested, child) {
          final scale = requested.isFinite
              ? requested.clamp(1.0, maximum)
              : 1.0;
          final logicalSize = constraints.biggest / scale;
          return ClipRect(
            key: const ValueKey('opportunities-content-viewport'),
            clipBehavior: scale == 1 ? Clip.none : Clip.hardEdge,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: logicalSize.width,
              maxWidth: logicalSize.width,
              minHeight: logicalSize.height,
              maxHeight: logicalSize.height,
              child: Transform.scale(
                key: const ValueKey('opportunities-content-transform'),
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

/// Keep the current grid and content branches. Breakpoints are supplied in
/// unscaled overview coordinates, never recalculated from the slider preview.
double opportunitiesContentMaximumScale({
  required Size size,
  required String section,
  required double textScale,
  Iterable<double> cardBreakpoints = const [],
  Iterable<double> paneBreakpoints = const [],
}) {
  if (!size.isFinite || size.width <= 0 || size.height <= 0) return 1;
  final width = size.width;
  // Match the actual grid even with smaller system text. Only Exchange's
  // explicit grid rule clamps its text factor separately below.
  final text = textScale.isFinite && textScale > 0 ? textScale : 1.0;
  var minimum = math.min(width, 360.0);
  void preserve(double threshold) {
    if (width >= threshold) minimum = math.max(minimum, threshold);
  }

  if (section == 'exchanges') {
    final gridText = text.clamp(1.0, 2.0);
    final columns = (width / (420 * gridText)).floor().clamp(1, 3);
    if (columns > 1) preserve(columns * 420 * gridText);
    // The identity panel's content has fourteen pixels on each side.
    preserve(680 * text + 28);
    for (final inner in cardBreakpoints) {
      if (inner <= 560 * gridText - 28) {
        preserve(columns * (inner + 28) + (columns - 1) * 12);
      }
    }
  } else {
    final crafting = section != 'best-use';
    final minimumWidth = crafting
        ? OpportunityCraftCardLayout.minimumWidth
        : 380.0;
    final maximumWidth = crafting
        ? OpportunityCraftCardLayout.maximumWidth
        : 640.0;
    final maximumColumns = crafting
        ? OpportunityCraftCardLayout.maximumColumns
        : 3;
    final columns = ((width + 16) / (minimumWidth * text + 16)).floor().clamp(
      1,
      maximumColumns,
    );
    if (columns > 1) preserve(columns * (minimumWidth * text + 16) - 16);
    for (final inner in cardBreakpoints) {
      if (inner <= maximumWidth * text - 28) {
        preserve(columns * (inner + 28) + 5 + (columns - 1) * 16);
      }
    }
  }
  for (final threshold in paneBreakpoints) {
    preserve(threshold);
  }
  final scale =
      ((math.min(1.25, width / minimum) * 100 + .000001).floor() / 100).clamp(
        1.0,
        1.25,
      );
  // Division can land just below an exact breakpoint in binary floating point.
  // Use the actual viewport width rather than reducing safe exact fits.
  if (scale > 1 && width / scale < minimum) {
    return ((scale * 100).round() - 1) / 100;
  }
  return scale;
}
