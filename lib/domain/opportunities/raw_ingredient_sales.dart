import '../market/market_calculations.dart';
import '../state/planner_state.dart';
import 'opportunity_calculator.dart';

/// Listing proceeds for the exact consumed inputs, not profit or an instant
/// sale. Supplier purchase costs never change this value.
final class RawIngredientSales {
  const RawIngredientSales({
    required this.afterTax,
    required this.excludedNames,
    required this.unpricedNames,
  });

  final double? afterTax;
  final List<String> excludedNames;
  final List<String> unpricedNames;
}

RawIngredientSales calculateRawIngredientSales({
  required Iterable<OpportunityIngredientQuote> ingredients,
  required MarketTax tax,
  required DateTime now,
  required Duration maxAge,
  required bool Function(String itemId) isMarketable,
  bool ownedOnly = false,
}) {
  var gross = 0.0;
  var count = 0;
  final excluded = <String>[];
  final unpriced = <String>[];
  for (final input in ingredients) {
    count++;
    final quantity = ownedOnly ? input.ownedQuantity : input.quantity;
    if (ownedOnly && quantity == 0) continue;
    final id = input.itemId;
    if (id != null && !isMarketable(id)) {
      excluded.add(input.name);
      continue;
    }
    final market = input.market;
    if (id == null ||
        quantity <= 0 ||
        market == null ||
        market.itemId != id ||
        market.subId != 0 ||
        market.unlisted ||
        !market.quoteIsFresh(now, maxAge)) {
      unpriced.add(input.name);
      continue;
    }
    // Use the same fresh listing-price basis as crafted output. Empty stock
    // or no buyers does not invalidate a hypothetical listing value.
    gross += quantity * market.basePrice!;
  }
  final net = marketNetProceeds(gross, tax);
  return RawIngredientSales(
    afterTax:
        count == 0 || unpriced.isNotEmpty || !gross.isFinite || !net.isFinite
        ? null
        : net,
    excludedNames: List.unmodifiable(excluded),
    unpricedNames: List.unmodifiable(unpriced),
  );
}
