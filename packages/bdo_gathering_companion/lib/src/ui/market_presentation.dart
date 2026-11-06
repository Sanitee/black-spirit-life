import 'package:flutter/widgets.dart';

typedef GatheringStockBuilder =
    Widget Function(
      BuildContext context, {
      required int? stock,
      int? preorders,
      Key? stockKey,
    });
typedef GatheringSilverBuilder =
    Widget Function(
      BuildContext context, {
      required num? value,
      required TextStyle style,
      String prefix,
      String suffix,
      Key? textKey,
    });

/// Optional host presentation only. Pricing, stock freshness and calculations
/// remain owned by Gathering. InheritedTheme also survives detail dialogs.
class GatheringMarketPresentation extends InheritedTheme {
  const GatheringMarketPresentation({
    required this.stockBuilder,
    required this.silverBuilder,
    required super.child,
    super.key,
  });
  final GatheringStockBuilder stockBuilder;
  final GatheringSilverBuilder silverBuilder;

  static GatheringMarketPresentation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GatheringMarketPresentation>();
  @override
  Widget wrap(BuildContext context, Widget child) =>
      GatheringMarketPresentation(
        stockBuilder: stockBuilder,
        silverBuilder: silverBuilder,
        child: child,
      );
  @override
  bool updateShouldNotify(GatheringMarketPresentation oldWidget) =>
      stockBuilder != oldWidget.stockBuilder ||
      silverBuilder != oldWidget.silverBuilder;
}
