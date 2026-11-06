import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ordinary quiet wrappers keep action names without creating hover popups.
/// Flutter's exact-runtime-type tooltip finder misses their subclasses.
Finder findActionHint(String message) {
  bool matches(Widget widget) =>
      (widget is IconButton && widget.tooltip == message) ||
      (widget is Tooltip && widget.message == message);
  return find.byElementPredicate((element) {
    if (!matches(element.widget)) return false;
    // IconButton may also build its own hidden Tooltip. Count one action, not
    // both the wrapper and its internal implementation node.
    var nested = false;
    element.visitAncestorElements((ancestor) {
      if (!matches(ancestor.widget)) return true;
      nested = true;
      return false;
    });
    return !nested;
  }, description: 'action or semantic hint "$message"');
}
