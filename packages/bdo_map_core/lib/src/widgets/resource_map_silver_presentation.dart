import 'package:flutter/widgets.dart';

typedef ResourceMapSilverBuilder =
    Widget Function(
      BuildContext context, {
      required num? value,
      required TextStyle style,
      String suffix,
      Key? textKey,
    });

/// The host can share its amount presentation without coupling map calculations
/// or editable fields to the application. Captured by nested dialog routes.
class ResourceMapSilverPresentation extends InheritedTheme {
  const ResourceMapSilverPresentation({
    required this.builder,
    required super.child,
    super.key,
  });
  final ResourceMapSilverBuilder builder;
  static ResourceMapSilverPresentation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ResourceMapSilverPresentation>();
  @override
  Widget wrap(BuildContext context, Widget child) =>
      ResourceMapSilverPresentation(builder: builder, child: child);
  @override
  bool updateShouldNotify(ResourceMapSilverPresentation oldWidget) =>
      builder != oldWidget.builder;
}
