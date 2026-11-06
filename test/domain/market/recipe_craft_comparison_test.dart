import 'package:bdo_craft_planner_flutter/domain/market/recipe_craft_comparison.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 5, 12);
  const age = Duration(minutes: 5);
  OpportunityMarketItem item({
    int stock = 0,
    int? base = 100,
    List<OpportunityMarketLevel> bids = const [
      OpportunityMarketLevel(price: 120, quantity: 5),
    ],
    List<OpportunityMarketLevel> asks = const [],
    bool stale = false,
    bool unlisted = false,
  }) => OpportunityMarketItem(
    itemId: '1',
    basePrice: base,
    stock: stock,
    quoteFetchedAt: stale ? now.subtract(const Duration(minutes: 6)) : now,
    bookFetchedAt: stale ? now.subtract(const Duration(minutes: 6)) : now,
    asks: asks,
    bids: bids,
    unlisted: unlisted,
  );

  test(
    'empty stock uses highest occupied preorder, not base or empty level',
    () {
      expect(
        recipeMarketUnitPrice(
          item(
            bids: const [
              OpportunityMarketLevel(price: 500, quantity: 0),
              OpportunityMarketLevel(price: 90, quantity: 8),
              OpportunityMarketLevel(price: 120, quantity: 1),
            ],
          ),
          now,
          age,
        ),
        120,
      );
    },
  );
  test('positive stock keeps the quoted market price', () {
    expect(recipeMarketUnitPrice(item(stock: 9), now, age), 100);
  });
  test('empty preorder book falls back to fresh base price', () {
    expect(recipeMarketUnitPrice(item(bids: const []), now, age), 100);
  });
  test('fresh order book can value an item without a base quote', () {
    expect(recipeMarketUnitPrice(item(base: null), now, age), 120);
    expect(
      recipeMarketUnitPrice(
        item(
          base: null,
          asks: const [
            OpportunityMarketLevel(price: 130, quantity: 3),
            OpportunityMarketLevel(price: 125, quantity: 4),
          ],
        ),
        now,
        age,
      ),
      125,
    );
  });
  test('stale, unlisted and wholly unknown prices are not zero', () {
    expect(recipeMarketUnitPrice(item(stale: true), now, age), isNull);
    expect(recipeMarketUnitPrice(item(unlisted: true), now, age), isNull);
    expect(
      recipeMarketUnitPrice(item(base: null, bids: const []), now, age),
      isNull,
    );
    expect(recipeMarketUnitPrice(null, now, age), isNull);
  });

  RecipeCraftValueInput input({
    String name = 'Wheat',
    double quantity = 5,
    double owned = 3,
    double? buy = 100,
    double? sell = 120,
    bool market = true,
  }) => RecipeCraftValueInput(
    name: name,
    quantity: quantity,
    owned: owned,
    buyPrice: buy,
    sellPrice: sell,
    marketable: market,
  );
  RecipeCraftComparison compare(
    List<RecipeCraftValueInput> rows, {
    double? output = 1000,
    double tax = .65,
  }) => RecipeCraftComparison.calculate(
    inputs: rows,
    outputNetRevenue: output,
    netRate: tax,
  );

  test('three comparable estimates use one craft and after-tax sales', () {
    final result = compare([input()]);
    expect(result.buyAllProfit, 500);
    expect(result.buyMissingReturn, 800);
    expect(result.sellOwnedProceeds, 234);
  });
  test('extra inventory never inflates one-craft sale value', () {
    final result = compare([input(owned: 1500000)]);
    expect(result.buyAllProfit, 500);
    expect(result.buyMissingReturn, 1000);
    expect(result.sellOwnedProceeds, 390);
  });
  test(
    'duplicate case variants share inventory rather than spending it twice',
    () {
      final result = compare([
        input(quantity: 3, owned: 4),
        input(name: 'wheat', quantity: 2, owned: 4),
      ]);
      expect(result.buyAllProfit, 500);
      expect(result.buyMissingReturn, 900);
      expect(result.sellOwnedProceeds, 312);
    },
  );
  test(
    'unknown owned input price does not block a cash return with no purchases',
    () {
      final result = compare([input(owned: 5, buy: null, sell: null)]);
      expect(result.buyAllProfit, isNull);
      expect(result.buyMissingReturn, 1000);
      expect(result.sellOwnedProceeds, isNull);
    },
  );
  test(
    'unknown missing input blocks both purchase estimates, not empty owned sale',
    () {
      final result = compare([input(owned: 0, buy: null, sell: null)]);
      expect(result.buyAllProfit, isNull);
      expect(result.buyMissingReturn, isNull);
      expect(result.sellOwnedProceeds, 0);
      expect(result.missingBuyPrices, {'Wheat'});
    },
  );
  test(
    'unknown output does not hide the independently known owned sale value',
    () {
      final result = compare([input()], output: null);
      expect(result.buyAllProfit, isNull);
      expect(result.buyMissingReturn, isNull);
      expect(result.sellOwnedProceeds, 234);
    },
  );
  test('NPC-only items have purchase costs but no invented market buyback', () {
    final result = compare([input(market: false, sell: null)]);
    expect(result.buyAllProfit, 500);
    expect(result.buyMissingReturn, 800);
    expect(result.sellOwnedProceeds, 0);
  });
  test('NPC plus market input retains separate buying and selling prices', () {
    final result = compare([input(buy: 20, sell: 120)], tax: .845);
    expect(result.buyAllProfit, 900);
    expect(result.buyMissingReturn, 960);
    expect(result.sellOwnedProceeds, closeTo(304.2, .001));
  });
  test(
    'missing and negative owned quantities never create extra sale proceeds',
    () {
      final result = compare([input(owned: -5)]);
      expect(result.buyMissingReturn, 500);
      expect(result.sellOwnedProceeds, 0);
    },
  );
  test(
    'negative profit is retained and invalid quantities cannot become free',
    () {
      expect(compare([input(buy: 500)]).buyAllProfit, -1500);
      expect(compare([input(quantity: double.nan)]).buyMissingReturn, isNull);
      expect(compare([input()], tax: double.nan).sellOwnedProceeds, isNull);
    },
  );
}
