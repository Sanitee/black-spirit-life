import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/raw_ingredient_sales.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as f;

void main() {
  const listing = OpportunitySaleMode.listing;

  test('off still buys everything; on values only batch-owned inputs', () {
    final state = f.state(inventory: {'oRe': 2});
    final off = f.calculate(crafts: 5, state: state);
    final on = f.calculate(crafts: 5, state: state, useInventory: true);
    expect(off.inputCost, 50);
    expect(off.ingredients.single.ownedQuantity, 0);
    expect(on.inputCost, 30);
    expect(on.ingredients.single.quantity, 5);
    expect(on.ingredients.single.ownedQuantity, 2);
    expect(on.ingredients.single.purchaseQuantity, 3);
    expect(on.ownedIngredientSales, closeTo(20 * .845, 1e-8));
    expect(on.cashProfitFor(listing), closeTo(500 * .845 - 30, 1e-8));
    expect(on.profitFor(listing), closeTo((500 - 20) * .845 - 30, 1e-8));
    expect(state.inventory, {'oRe': 2});
  });

  test('owned stock avoids only missing ask tiers, not average full cost', () {
    final on = f.calculate(
      crafts: 5,
      useInventory: true,
      state: f.state(inventory: {'Ore': 2}),
      input: f.marketItem('2', asks: [f.level(10, 2), f.level(20, 4)]),
    );
    expect(on.inputCost, 40);
    expect(on.ingredients.single.marketQuantity, 3);
    expect(on.ingredients.single.filledQuantity, 5);
    expect(on.ingredients.single.coversRequest, isTrue);
  });

  test('fully owned zero-stock item is available without invented stock', () {
    final on = f.calculate(
      crafts: 5,
      useInventory: true,
      state: f.state(inventory: {'Ore': 1000000}),
      input: f.marketItem('2', stock: 0, asks: []),
    );
    expect(on.inputCost, 0);
    expect(on.ingredientsAvailable, isTrue);
    expect(on.ingredients.single.ownedQuantity, 5);
    expect(on.ingredients.single.market!.stock, 0);
    expect(on.ownedIngredientSales, closeTo(50 * .845, 1e-8));
    expect(on.profitFor(listing), closeTo(450 * .845, 1e-8));
  });

  test('missing purchase and resale prices remain independently unknown', () {
    final partlyOwned = f.calculate(
      crafts: 5,
      useInventory: true,
      state: f.state(inventory: {'Ore': 2}),
      omitInput: true,
    );
    expect(partlyOwned.totalCost, isNull);
    expect(partlyOwned.profitFor(listing), isNull);
    final allOwned = f.calculate(
      crafts: 5,
      useInventory: true,
      state: f.state(inventory: {'Ore': 5}),
      omitInput: true,
    );
    expect(allOwned.totalCost, 0);
    expect(allOwned.cashProfitFor(listing), isNotNull);
    expect(allOwned.ownedIngredientSales, isNull);
    expect(allOwned.profitFor(listing), isNull);
    expect(allOwned.preliminaryComparisonProfit, isNull);
    final stale = f.calculate(
      useInventory: true,
      state: f.state(inventory: {'Ore': 5}),
      input: f.marketItem(
        '2',
        quoteTime: f.now.subtract(const Duration(days: 1)),
      ),
    );
    expect(stale.ownedIngredientSales, isNull);
    expect(stale.profitFor(listing), isNull);
  });

  test('confirmed nonmarket materials count as owned, never market resale', () {
    final on = f.calculate(
      useInventory: true,
      state: f.state(inventory: {'Ore': 2}),
      omitInput: true,
      nonMarketableIds: {'2'},
    );
    expect(on.inputCost, 0);
    expect(on.ownedIngredientSales, 0);
    expect(on.ingredientsAvailable, isTrue);
    expect(on.profitFor(listing), on.cashProfitFor(listing));
    final missing = f.calculate(
      useInventory: true,
      omitInput: true,
      nonMarketableIds: {'2'},
    );
    expect(missing.inputCost, isNull);
    expect(missing.ingredientsAvailable, isFalse);
  });

  test('NPC supply charges only missing units and does not tax purchases', () {
    final on = f.calculate(
      crafts: 5,
      useInventory: true,
      npcPrice: 4,
      omitInput: true,
      nonMarketableIds: {'2'},
      state: f.state(inventory: {'Ore': 2}),
      tax: MarketTax(
        valuePack: true,
        merchantRing: true,
        familyFameBonus: .005,
      ),
      extraCostPerRun: 10,
      extraCostPerCraft: 2,
    );
    expect(on.inputCost, 12);
    expect(on.totalCost, 32);
    expect(on.ownedIngredientSales, 0);
    expect(on.profitFor(listing), closeTo(500 * .65 * 1.355 - 32, 1e-8));
  });

  test('merged repeated inputs and aliases never reuse owned stock twice', () {
    final on = f.calculate(
      useInventory: true,
      product: f.recipe(
        'Product',
        ingredients: [f.ingredient('Ore', 3), f.ingredient('Ore alias', 4)],
      ),
      extras: {'Ore alias': f.leaf('Ore alias', id: '2')},
      state: f.state(inventory: {'Ore': 4, 'ore alias': 4}),
    );
    expect(on.ingredients, hasLength(1));
    expect(on.ingredients.single.quantity, 7);
    expect(on.ingredients.single.ownedQuantity, 4);
    expect(on.inputCost, 30);
    expect(on.ownedIngredientSales, closeTo(40 * .845, 1e-8));
  });

  test(
    'substitute selection counts forgone resale, not free expensive stock',
    () {
      final on = f.calculate(
        useInventory: true,
        product: f.recipe(
          'Product',
          ingredients: [
            f.ingredient('Ore', 1, options: ['Ore', 'Fine Ore']),
          ],
        ),
        state: f.state(inventory: {'Fine Ore': 1}),
        extras: {'Fine Ore': f.leaf('Fine Ore', id: '3')},
        additionalMarket: {'3': f.marketItem('3', price: 100)},
      );
      expect(on.ingredients.single.name, 'Ore');
      final available = f.calculate(
        useInventory: true,
        preferAvailableInputs: true,
        product: f.recipe(
          'Product',
          variants: [
            f.variant('a', [f.ingredient('Ore', 1)]),
            f.variant('b', [f.ingredient('Fine Ore', 1)]),
          ],
        ),
        state: f.state(inventory: {'Fine Ore': 1}),
        input: f.marketItem('2', stock: 0, asks: []),
        extras: {'Fine Ore': f.leaf('Fine Ore', id: '3')},
        additionalMarket: {
          '3': f.marketItem('3', price: 100, stock: 0, asks: []),
        },
      );
      expect(available.selectedVariantId, 'b');
      expect(available.ingredientsAvailable, isTrue);
    },
  );

  test('custom sale price and negative comparison retain exact signs', () {
    final on = f.calculate(
      useInventory: true,
      customSalePrice: 5,
      state: f.state(inventory: {'Ore': 1}),
    );
    expect(on.cashProfitFor(listing), closeTo(5 * .845, 1e-8));
    expect(on.profitFor(listing), closeTo(-5 * .845, 1e-8));
    expect(on.preliminaryComparisonProfit, closeTo(-5 * .845, 1e-8));
    expect(
      on.profitFor(OpportunitySaleMode.currentBuyers),
      on.profitFor(listing),
    );
  });

  test('invalid craft quantities retain the active comparison mode', () {
    final quote = f.calculate(crafts: 0, useInventory: true);
    expect(quote.usesInventory, isTrue);
    expect(quote.profitFor(listing), isNull);
  });

  test(
    'raw-sales display and profit use identical owned quantities and tax',
    () {
      for (final owned in [0.0, 2.0, 1000000.0]) {
        final on = f.calculate(
          crafts: 5,
          useInventory: true,
          state: f.state(inventory: {'Ore': owned}),
        );
        final sales = calculateRawIngredientSales(
          ingredients: on.ingredients,
          tax: MarketTax(valuePack: true),
          now: f.now,
          maxAge: const Duration(minutes: 5),
          isMarketable: (_) => true,
          ownedOnly: true,
        );
        expect(sales.afterTax, on.ownedIngredientSales);
        expect(sales.unpricedNames, isEmpty);
      }
    },
  );
}
