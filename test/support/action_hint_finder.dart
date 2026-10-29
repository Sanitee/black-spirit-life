import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds an action by its retained accessibility hint, not a visible popup.
Finder findActionHint(String message) => find.byWidgetPredicate((widget) {
  if (widget is QuietIconButton) return widget.tooltip == message;
  if (widget is AppTooltip) return widget.message == message;
  // Standalone package surfaces still use the standard Material control.
  if (widget is RawTooltip) return widget.semanticsTooltip == message;
  return false;
});
