import 'package:flutter/widgets.dart';

import '../../data/icons/custom_icon_store.dart';

/// Makes the app-owned icon store available to item renderers without adding
/// persistence concerns to feature controllers or domain state.
class CustomIconStoreScope extends InheritedWidget {
  const CustomIconStoreScope({
    required this.store,
    required super.child,
    super.key,
  });

  final CustomIconStore store;

  static CustomIconStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomIconStoreScope>()?.store;

  @override
  bool updateShouldNotify(CustomIconStoreScope oldWidget) =>
      !identical(store, oldWidget.store);
}
