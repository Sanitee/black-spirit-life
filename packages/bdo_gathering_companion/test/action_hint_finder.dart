import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Targets the retained accessible action, not a removed ordinary hover popup.
Finder findActionHint(String message) => find.byWidgetPredicate((widget) {
  if (widget is GatheringQuietIconButton) return widget.tooltip == message;
  if (widget is GatheringQuietTooltip) return widget.message == message;
  if (widget is RawTooltip) return widget.semanticsTooltip == message;
  return false;
});
