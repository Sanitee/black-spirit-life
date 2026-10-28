import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as fixtures;

void main() {
  const calculator = OpportunityCalculator();
  final product = fixtures.recipe(
    'Product',
    ingredients: [fixtures.ingredient('Ore', 10)],
    variants: [
      fixtures.variant('standard', [fixtures.ingredient('Ore', 10)]),
      fixtures.variant('alternative', [fixtures.ingredient('Ore', 12)]),
    ],
  );
  late Map<String, Recipe> recipes;
  late PlannerRules rules;
  late ModeState state;
  late OpportunityInventorySnapshot prepared;

  setUp(() {
    recipes = {'Product': product, 'Ore': fixtures.leaf('Ore', id: '2')};
    rules = PlannerRules(marketIds: {'Alias': '2'});
    state = fixtures.state(
      inventory: {
        'Ore': 5.9,
        'Alias': 7.9,
        'NaN': double.nan,
        'Infinity': double.infinity,
        'Negative': -20,
        'Zero': 0,
      },
    );
    prepared = calculator.prepareInventory(
      recipes: recipes,
      state: state,
      rules: rules,
    );
  });

  OpportunityQuote evaluate({bool cached = true, bool useInventory = true}) =>
      calculator.evaluate(
        recipe: product,
        recipes: recipes,
        rules: rules,
        state: state,
        marketTax: MarketTax(valuePack: true),
        market: OpportunityMarketSnapshot(
          region: 'eu',
          items: {
            '1': fixtures.marketItem('1', price: 1000),
            '2': fixtures.marketItem('2'),
            '3': fixtures.marketItem('3'),
          },
        ),
        now: fixtures.now,
        useInventory: useInventory,
        preparedInventory: cached ? prepared : null,
      );

  void expectParity() {
    final actual = evaluate();
    final expected = evaluate(cached: false);
    expect(
      [
        actual.selectedVariantId,
        actual.listingProfit,
        actual.ownedIngredientSales,
        for (final input in actual.ingredients)
          [
            input.name,
            input.itemId,
            input.quantity,
            input.ownedQuantity,
            input.purchaseQuantity,
            input.costForCalculation,
            input.ownedSaleAfterTax,
          ],
      ],
      [
        expected.selectedVariantId,
        expected.listingProfit,
        expected.ownedIngredientSales,
        for (final input in expected.ingredients)
          [
            input.name,
            input.itemId,
            input.quantity,
            input.ownedQuantity,
            input.purchaseQuantity,
            input.costForCalculation,
            input.ownedSaleAfterTax,
          ],
      ],
    );
  }

  test('reuse retains flooring, alias maximum and formula choices', () {
    expectParity();
    expect(evaluate().ingredients.single.ownedQuantity, 7);
    expect(evaluate().ingredients.single.purchaseQuantity, 3);
    expectParity(); // A previous evaluation must not consume the shared stock.
  });

  test('new inventory rejects the old snapshot', () {
    state = fixtures.state(inventory: {'Ore': 2});
    expectParity();
    expect(evaluate().ingredients.single.ownedQuantity, 2);
  });

  test('new alias rules reject the old snapshot', () {
    rules = PlannerRules(marketIds: {'Alias': '3'});
    expectParity();
    expect(evaluate().ingredients.single.ownedQuantity, 5);
  });

  test('in-place recipe replacement rejects the old snapshot', () {
    recipes['Ore'] = fixtures.leaf('Ore', id: '3');
    expectParity();
    expect(evaluate().ingredients.single.ownedQuantity, 5);
  });

  test('in-place recipe addition rejects the old snapshot', () {
    recipes['Alias'] = fixtures.leaf('Alias', id: '3');
    expectParity();
    expect(evaluate().ingredients.single.ownedQuantity, 5);
  });

  test('disabled inventory ignores a supplied snapshot', () {
    expect(evaluate(useInventory: false).ingredients.single.ownedQuantity, 0);
    expect(
      evaluate(useInventory: false).inputCost,
      evaluate(cached: false, useInventory: false).inputCost,
    );
  });
}
