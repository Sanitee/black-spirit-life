import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds an action by its retained accessibility hint, not a visible popup.
Finder findActionHint(String message) {
  bool matches(Widget widget) =>
      (widget is IconButton && widget.tooltip == message) ||
      (widget is Tooltip && widget.message == message) ||
      (widget is RawTooltip && widget.semanticsTooltip == message);
  return find.byElementPredicate((element) {
    if (!matches(element.widget)) return false;
    // Shared app and standalone map/Gathering controls use different quiet
    // subclasses. A Material control may also build a nested hidden tooltip;
    // these are one action, not two separate matching buttons.
    var nested = false;
    element.visitAncestorElements((ancestor) {
      if (!matches(ancestor.widget)) return true;
      nested = true;
      return false;
    });
    return !nested;
  }, description: 'action or semantic hint "$message"');
}
