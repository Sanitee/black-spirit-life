import 'dart:math' as math;

import 'package:flutter/material.dart';

double readableSelectMenuWidth(
  BuildContext context,
  Iterable<String> labels, {
  double triggerWidth = 0,
  double horizontalChrome = 64,
  double minimumWidth = 240,
}) {
  final theme = Theme.of(context);
  final style =
      theme.popupMenuTheme.textStyle ??
      theme.textTheme.labelLarge ??
      const TextStyle(fontSize: 14);
  final textDirection = Directionality.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  var longestLabelWidth = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    longestLabelWidth = math.max(longestLabelWidth, painter.width);
  }
  final viewportMaximum = math.max(
    112.0,
    MediaQuery.sizeOf(context).width - 24,
  );
  final lowerBound = math.min(
    math.max(minimumWidth, triggerWidth),
    viewportMaximum,
  );
  return (longestLabelWidth + horizontalChrome)
      .clamp(lowerBound, viewportMaximum)
      .toDouble();
}
