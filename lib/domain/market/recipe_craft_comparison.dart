import 'dart:math' as math;
import '../opportunities/opportunity_market_models.dart';

/// Price is independent of availability. An empty market can still be valued
/// at its highest occupied preorder; that is not a promise of immediate supply.
double? recipeMarketUnitPrice(
  OpportunityMarketItem? item,
  DateTime now,
  Duration maxAge,
) {
  if (item == null || item.unlisted) return null;
  final bookFresh = item.bookIsFresh(now, maxAge);
  double? bid;
  double? ask;
  if (bookFresh) {
    for (final level in item.bids!) {
      if (level.quantity > 0 && level.price > 0) {
        bid = math.max(bid ?? 0, level.price.toDouble());
      }
    }
    for (final level in item.asks!) {
      if (level.quantity > 0 && level.price > 0) {
        ask = math.min(ask ?? double.infinity, level.price.toDouble());
      }
    }
  }
  if (item.stockFor(now, maxAge) == 0 && bid != null) return bid;
  if (item.quoteIsFresh(now, maxAge)) return item.basePrice!.toDouble();
  return ask ?? bid;
}

class RecipeCraftValueInput {
  const RecipeCraftValueInput({
    required this.name,
    required this.quantity,
    required this.owned,
    required this.buyPrice,
    required this.sellPrice,
    required this.marketable,
  });
  final String name;
  final double quantity, owned;
  final double? buyPrice, sellPrice;
  final bool marketable;
}

/// Three independent, comparable one-attempt estimates. Owned units are capped
/// at the recipe's requirement, and repeated rows share a single inventory pool.
class RecipeCraftComparison {
  const RecipeCraftComparison({
    required this.buyAllProfit,
    required this.buyMissingReturn,
    required this.sellOwnedProceeds,
    required this.missingBuyPrices,
    required this.missingSalePrices,
  });
  factory RecipeCraftComparison.calculate({
    required Iterable<RecipeCraftValueInput> inputs,
    required double? outputNetRevenue,
    required double netRate,
  }) {
    double? all = 0, missing = 0, sales = 0;
    final used = <String, double>{};
    final missingBuy = <String>{}, missingSale = <String>{};
    for (final row in inputs) {
      if (!row.quantity.isFinite || row.quantity <= 0 || !row.owned.isFinite) {
        all = missing = sales = null;
        continue;
      }
      final id = row.name.trim().toLowerCase();
      final have = math.min(
        row.quantity,
        math.max(0.0, row.owned - (used[id] ?? 0)),
      );
      used[id] = (used[id] ?? 0) + have;
      final need = row.quantity - have;
      final buy = row.buyPrice;
      if (buy == null || !buy.isFinite || buy <= 0) {
        all = null;
        if (need > 0) {
          missing = null;
          missingBuy.add(row.name);
        }
      } else {
        if (all != null) all += row.quantity * buy;
        if (missing != null) missing += need * buy;
      }
      // No invented NPC buyback price, and no value for units the user lacks.
      if (have > 0 && row.marketable) {
        final sell = row.sellPrice;
        if (sell == null || !sell.isFinite || sell <= 0) {
          sales = null;
          missingSale.add(row.name);
        } else if (sales != null) {
          sales += have * sell * netRate;
        }
      }
    }
    final revenue = outputNetRevenue;
    final validRevenue = revenue != null && revenue.isFinite && revenue > 0;
    double? finite(double? value) =>
        value != null && value.isFinite ? value : null;
    return RecipeCraftComparison(
      buyAllProfit: validRevenue && all != null ? finite(revenue - all) : null,
      buyMissingReturn: validRevenue && missing != null
          ? finite(revenue - missing)
          : null,
      sellOwnedProceeds: netRate.isFinite && netRate > 0 ? finite(sales) : null,
      missingBuyPrices: Set.unmodifiable(missingBuy),
      missingSalePrices: Set.unmodifiable(missingSale),
    );
  }
  final double? buyAllProfit, buyMissingReturn, sellOwnedProceeds;
  final Set<String> missingBuyPrices, missingSalePrices;
}
