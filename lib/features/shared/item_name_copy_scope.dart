import 'package:flutter/material.dart';

/// Keeps the shell's clipboard feedback available in nested item windows.
/// InheritedTheme is captured by dialog routes; popovers retain it directly.
class ItemNameCopyScope extends InheritedTheme {
  const ItemNameCopyScope({
    required this.copyName,
    this.copyText,
    required super.child,
    super.key,
  });

  final Future<void> Function(String) copyName;
  final Future<void> Function(String text, String confirmation)? copyText;

  static Future<void> Function(String)? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ItemNameCopyScope>()?.copyName;

  static Future<void> Function(String, String)? textActionOf(
    BuildContext context,
  ) => context.getInheritedWidgetOfExactType<ItemNameCopyScope>()?.copyText;

  @override
  bool updateShouldNotify(ItemNameCopyScope oldWidget) =>
      copyName != oldWidget.copyName || copyText != oldWidget.copyText;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ItemNameCopyScope(copyName: copyName, copyText: copyText, child: child);
}
