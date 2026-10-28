import 'package:flutter/material.dart';

import 'content_size_popover.dart';

/// Preserves the Planner's public control and keys over shared sizing visuals.
class PlannerAppearancePopover extends ContentSizePopover {
  const PlannerAppearancePopover({
    required super.value,
    required super.maximum,
    required super.onChanged,
    required super.onChangeEnd,
    required super.onReset,
    required super.onClose,
    super.key,
  }) : super(
         label: 'Planner size',
         keys: const ContentSizePopoverKeys('planner-appearance'),
       );

  static const surfaceKey = ValueKey<String>('planner-appearance-popover');
  static const backingKey = ValueKey<String>('planner-appearance-backing');
  static const sliderKey = ValueKey<String>('planner-appearance-zoom-slider');
  static const valueKey = ValueKey<String>('planner-appearance-zoom-value');
  static const resetKey = ValueKey<String>('planner-appearance-zoom-reset');
  static const closeKey = ValueKey<String>('planner-appearance-close');
}
