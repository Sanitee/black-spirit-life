import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as fixture;

void main() {
  test('fresh summary prices cover every input without inventing depth', () {
    final quote = fixture.calculate(
      crafts: 4,
      input: fixture.marketItem('2', unknownBook: true, stock: 900),
      output: fixture.marketItem('1', price: 100, unknownBook: true),
    );
    expect(quote.estimatedInputCost, 40);
    expect(quote.listingProfit, closeTo(298, .000001));
    expect(quote.inputCost, isNull);
    expect(quote.hasUncheckedInputDepth, isTrue);
    expect(quote.hasEstimatedStockShortfall, isFalse);
    expect(quote.marketReady, isFalse);
    expect(quote.inputCapacityKnown, isFalse);
    expect(quote.inputCraftCapacity, isNull);
    expect(quote.buyerRevenue, isNull);
    expect(quote.buyerCraftCapacity, isNull);
    expect(quote.buyersCoverOutput, isFalse);
    final input = quote.ingredients.single;
    expect(input.quantity, 4);
    expect(input.filledQuantity, 0);
    expect(input.marketQuantity, 0);
    expect(input.estimatedMarketQuantity, 4);
    expect(input.estimatedUnitPrice, 10);
  });

  test(
    'mixed estimates retain checked ask costs and NPC costs, plus extras',
    () {
      final quote = fixture.calculate(
        product: fixture.recipe(
          'Product',
          ingredients: [
            fixture.ingredient('Ore', 2),
            fixture.ingredient('Cloth', 3),
            fixture.ingredient('Salt', 1),
          ],
        ),
        input: fixture.marketItem('2', price: 5, asks: [fixture.level(12, 99)]),
        extras: {
          'Cloth': fixture.leaf('Cloth', id: '3'),
          'Salt': fixture.leaf('Salt', npc: 7),
        },
        additionalMarket: {
          '3': fixture.marketItem('3', price: 20, unknownBook: true),
        },
        extraCostPerCraft: 2,
        extraCostPerRun: 3,
      );
      expect(quote.inputCost, isNull);
      expect(quote.estimatedInputCost, 24 + 60 + 7);
      expect(quote.preliminaryInputCost, 10 + 60 + 7);
      expect(quote.totalCost, 96);
      expect(quote.listingProfit, closeTo(84.5 - 96, .000001));
      expect(quote.ingredients.first.buyCost, 24);
      expect(quote.ingredients.last.npcQuantity, 1);
      expect(quote.ingredients.last.estimateKind, isNull);
    },
  );

  test('duplicate aliases round their combined quantity only once', () {
    final quote = fixture.calculate(
      product: fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', .6),
          fixture.ingredient('Alias Ore', .6),
        ],
      ),
      extras: {'Alias Ore': fixture.leaf('Alias Ore', id: '0002')},
      input: fixture.marketItem('2', unknownBook: true),
    );
    expect(quote.ingredients, hasLength(1));
    expect(quote.ingredients.single.quantity, 2);
    expect(quote.ingredients.single.estimatedMarketQuantity, 2);
    expect(quote.estimatedInputCost, 20);
  });

  test('missing stale invalid or unlisted prices never become free inputs', () {
    for (final input in [
      fixture.marketItem('2', price: 0, unknownBook: true),
      fixture.marketItem('2', price: -1, unknownBook: true),
      fixture.marketItem('2', unknownBook: true, unlisted: true),
      fixture.marketItem('99', unknownBook: true),
      fixture.marketItem(
        '2',
        unknownBook: true,
        quoteTime: fixture.now.subtract(const Duration(hours: 1)),
      ),
      fixture.marketItem(
        '2',
        unknownBook: true,
        quoteTime: fixture.now.add(const Duration(seconds: 1)),
      ),
    ]) {
      final quote = fixture.calculate(input: input, extraCostPerRun: 3);
      expect(quote.totalCost, isNull);
      expect(quote.listingProfit, isNull);
      expect(quote.hasEstimatedInputs, isFalse);
    }
    expect(fixture.calculate(omitInput: true).listingProfit, isNull);
  });

  test('one missing input prevents a partly priced profit', () {
    final quote = fixture.calculate(
      product: fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', 2),
          fixture.ingredient('Cloth', 1),
        ],
      ),
      input: fixture.marketItem('2', unknownBook: true),
      extras: {'Cloth': fixture.leaf('Cloth', id: '3')},
    );
    expect(quote.ingredients.first.estimatedCost, 20);
    expect(quote.hasEstimatedInputs, isTrue);
    expect(quote.estimatedInputCost, isNull);
    expect(quote.totalCost, isNull);
    expect(quote.listingProfit, isNull);
  });

  test('archived ingredients cannot gain an estimate from cached prices', () {
    final quote = fixture.calculate(
      product: fixture.recipe(
        'Product',
        ingredients: [fixture.ingredient('Monkey Blood', 1)],
      ),
      extras: {'Monkey Blood': fixture.leaf('Monkey Blood', id: '6211')},
      additionalMarket: {'6211': fixture.marketItem('6211', unknownBook: true)},
    );
    expect(quote.listingProfit, isNull);
    expect(quote.hasEstimatedInputs, isFalse);
  });

  test(
    'known shortage retains actual asks and is distinct from unchecked depth',
    () {
      final quote = fixture.calculate(
        crafts: 4,
        input: fixture.marketItem('2', price: 10, asks: [fixture.level(12, 2)]),
      );
      expect(quote.estimatedInputCost, 44);
      expect(quote.hasEstimatedStockShortfall, isTrue);
      expect(quote.hasUncheckedInputDepth, isFalse);
      expect(quote.ingredients.single.filledQuantity, 2);
      expect(quote.ingredients.single.estimatedMarketQuantity, 2);
      expect(quote.inputCraftCapacity, 2);
      expect(quote.marketReady, isFalse);
    },
  );

  test(
    'fresh books replace the estimate with exact cost without changing units',
    () {
      final estimated = fixture.calculate(
        crafts: 3,
        input: fixture.marketItem('2', price: 10, unknownBook: true),
      );
      final checked = fixture.calculate(
        crafts: 3,
        input: fixture.marketItem('2', price: 10, asks: [fixture.level(12, 3)]),
      );
      expect(estimated.totalCost, 30);
      expect(checked.totalCost, 36);
      expect(checked.inputCost, 36);
      expect(checked.estimatedInputCost, isNull);
      expect(checked.hasEstimatedInputs, isFalse);
      expect(checked.ingredients.single.estimateKind, isNull);
      expect(checked.marketReady, isTrue);
      expect(checked.expectedOutput, estimated.expectedOutput);
    },
  );

  test(
    'variant-scoped requests exclude other formulas and reject invalid IDs',
    () {
      final recipe = fixture.recipe(
        'Product',
        variants: [
          fixture.variant('ore', [fixture.ingredient('Ore', 1)]),
          fixture.variant('cloth', [fixture.ingredient('Cloth', 1)]),
        ],
      );
      final recipes = {
        'Product': recipe,
        'Ore': fixture.leaf('Ore', id: '2'),
        'Cloth': fixture.leaf('Cloth', id: '3'),
      };
      final rules = PlannerRules();
      Set<String> ids(String? variant) => fixture.calculator.marketItemIds(
        recipe: recipe,
        recipes: recipes,
        rules: rules,
        selectedVariantId: variant,
      );
      expect(ids(null), {'1', '2', '3'});
      expect(ids('ore'), {'1', '2'});
      expect(ids('cloth'), {'1', '3'});
      expect(ids('missing'), isEmpty);
      expect(
        fixture.calculator.marketInputIds(
          recipe: recipe,
          recipes: recipes,
          rules: rules,
          selectedVariantId: 'cloth',
        ),
        {'3'},
      );
      expect(
        fixture.calculator.marketInputIds(
          recipe: recipe,
          recipes: recipes,
          rules: rules,
          selectedVariantId: 'missing',
        ),
        isEmpty,
      );
    },
  );

  test('input-only IDs preserve the output when the formula consumes it', () {
    final recipe = fixture.recipe(
      'Product',
      ingredients: [fixture.ingredient('Product', 1)],
    );
    expect(
      fixture.calculator.marketInputIds(
        recipe: recipe,
        recipes: {'Product': recipe},
        rules: PlannerRules(),
      ),
      {'1'},
    );
  });
}
