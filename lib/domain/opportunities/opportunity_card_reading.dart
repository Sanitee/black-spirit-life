import 'opportunity_calculator.dart';
import 'opportunity_market_models.dart';

/// A presentation projection of the existing run, not a second yield model.
final class OpportunityPerItemQuote {
  OpportunityPerItemQuote(OpportunityQuote quote, OpportunitySaleMode mode)
    : profit = _perItem(quote.profitFor(mode), quote.expectedOutput),
      cost = _perItem(
        quote.usesInventory
            ? _sum(quote.totalCost, quote.ownedIngredientSales)
            : quote.totalCost,
        quote.expectedOutput,
      ),
      saleAfterTax = _perItem(
        quote.hasCustomSalePrice || mode == OpportunitySaleMode.listing
            ? quote.listingRevenue
            : quote.buyerRevenue,
        quote.expectedOutput,
      );

  final double? profit, cost, saleAfterTax;

  static double? _sum(double? a, double? b) =>
      a == null || b == null ? null : a + b;

  static double? _perItem(double? amount, double? output) {
    if (amount == null ||
        !amount.isFinite ||
        output == null ||
        !output.isFinite ||
        output <= 0) {
      return null;
    }
    final value = amount / output;
    return value.isFinite ? value : null;
  }
}

enum OpportunityStockTone { unknown, available, outOfStock, mixed }

enum OpportunityCraftDecision { unknown, equal, craft, sell }

/// Both scenarios project the same selected formula and expected main output.
/// All-owned is hypothetical: it never reruns substitute/variant selection or
/// modifies inventory, stock filtering, profit sorting or price freshness.
final class OpportunityCraftComparison {
  OpportunityCraftComparison(OpportunityQuote quote, OpportunitySaleMode mode)
    : sale = OpportunityPerItemQuote(quote, mode).saleAfterTax,
      purchases = OpportunityPerItemQuote._perItem(
        quote.calculationInputCost,
        quote.expectedOutput,
      ),
      extraCosts = OpportunityPerItemQuote._perItem(
        quote.extraCost,
        quote.expectedOutput,
      ),
      ownedSales = OpportunityPerItemQuote._perItem(
        quote.ownedIngredientSales,
        quote.expectedOutput,
      ),
      allSales = OpportunityPerItemQuote._perItem(
        quote.allIngredientSales,
        quote.expectedOutput,
      );

  final double? sale, purchases, extraCosts, ownedSales, allSales;
  double? get afterPurchases =>
      _subtract(_subtract(sale, purchases), extraCosts);
  double? get inventoryProfit => _subtract(afterPurchases, ownedSales);
  double? get allOwnedReturn => _subtract(sale, extraCosts);
  double? get allOwnedProfit => _subtract(allOwnedReturn, allSales);

  static double? _subtract(double? a, double? b) =>
      a == null || b == null || !(a - b).isFinite ? null : a - b;

  /// Verdict and headline agree at the visible whole-silver precision.
  static OpportunityCraftDecision decision(double? difference) =>
      difference == null || !difference.isFinite
      ? OpportunityCraftDecision.unknown
      : difference.round() == 0
      ? OpportunityCraftDecision.equal
      : difference > 0
      ? OpportunityCraftDecision.craft
      : OpportunityCraftDecision.sell;
}

/// Stock and preorders have separate freshness and may coexist at other prices.
final class OpportunityCardStock {
  OpportunityCardStock(OpportunityMarketItem? item, DateTime now, Duration age)
    : stock = item?.stockFor(now, age),
      preorders = item?.bookIsFresh(now, age) == true
          ? item?.preorderCount
          : null;

  final int? stock, preorders;
  OpportunityStockTone get tone => stock == null
      ? OpportunityStockTone.unknown
      : stock == 0
      ? OpportunityStockTone.outOfStock
      : (preorders ?? 0) > 0
      ? OpportunityStockTone.mixed
      : OpportunityStockTone.available;
}
