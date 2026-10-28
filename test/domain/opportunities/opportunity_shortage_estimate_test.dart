import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as fixture;

void main() {
  test('sold out uses highest active preorder rather than summary price', () {
    final quote = fixture.calculate(
      crafts: 3,
      input: fixture.marketItem(
        '2',
        price: 20,
        stock: 0,
        asks: [],
        bids: [
          fixture.level(22, 10),
          fixture.level(30, 5),
          fixture.level(99, 0),
        ],
      ),
    );
    final input = quote.ingredients.single;
    expect(input.costForCalculation, 90);
    expect(input.estimatedUnitPrice, 30);
    expect(input.marketUnitPrice, 30);
    expect(input.estimatedFromPreorder, isTrue);
    expect(input.estimatedMarketQuantity, 3);
    expect(input.filledQuantity, 0);
    expect(quote.marketReady, isFalse);
    expect(quote.inputCraftCapacity, 0);
    expect(quote.listingProfit, closeTo(163.5, .000001));
  });

  test('partial stock combines actual asks with preorder-priced shortfall', () {
    final quote = fixture.calculate(
      crafts: 5,
      input: fixture.marketItem(
        '2',
        price: 10,
        stock: 2,
        asks: [fixture.level(30, 2)],
        bids: [fixture.level(25, 100)],
      ),
    );
    expect(quote.totalCost, 135); // 2 x 30 + 3 x 25.
    expect(quote.ingredients.single.filledQuantity, 2);
    expect(quote.ingredients.single.estimatedMarketQuantity, 3);
    expect(quote.ingredients.single.estimatedFromPreorder, isTrue);
  });

  test('fresh preorders can estimate without a usable summary quote', () {
    final quote = fixture.calculate(
      input: fixture.marketItem(
        '2',
        price: 0,
        stock: 0,
        asks: [],
        bids: [fixture.level(25, 100)],
      ),
    );
    expect(quote.totalCost, 25);
    expect(quote.ingredients.single.estimatedFromPreorder, isTrue);
  });

  test(
    'stale future or malformed preorders cannot replace a valid base price',
    () {
      for (final item in [
        fixture.marketItem(
          '2',
          price: 20,
          asks: [],
          bids: [fixture.level(30, 10)],
          bookTime: fixture.now.subtract(const Duration(minutes: 6)),
        ),
        fixture.marketItem(
          '2',
          price: 20,
          asks: [],
          bids: [fixture.level(30, 10)],
          bookTime: fixture.now.add(const Duration(seconds: 1)),
        ),
        fixture.marketItem(
          '2',
          price: 20,
          asks: [],
          bids: [fixture.level(30, -1)],
        ),
        fixture.marketItem(
          '2',
          price: 20,
          asks: [],
          bids: [fixture.level(0, 10)],
        ),
      ]) {
        final quote = fixture.calculate(input: item);
        expect(quote.totalCost, 20);
        expect(quote.ingredients.single.estimatedFromPreorder, isFalse);
      }
    },
  );

  test(
    'NPC supply keeps its verified price instead of a preorder estimate',
    () {
      final quote = fixture.calculate(
        npcPrice: 12,
        input: fixture.marketItem(
          '2',
          price: 20,
          stock: 0,
          asks: [],
          bids: [fixture.level(30, 100)],
        ),
      );
      expect(quote.totalCost, 12);
      expect(quote.ingredients.single.npcQuantity, 1);
      expect(quote.ingredients.single.estimatedFromPreorder, isFalse);
      expect(quote.hasEstimatedInputs, isFalse);
    },
  );

  test('zero stock uses fresh base price without inventing availability', () {
    final quote = fixture.calculate(
      crafts: 3,
      input: fixture.marketItem('2', price: 20, stock: 0, asks: []),
    );
    final input = quote.ingredients.single;
    expect(input.buyCost, isNull);
    expect(input.estimatedMarketQuantity, 3);
    expect(input.estimatedUnitPrice, 20);
    expect(input.estimatedCost, 60);
    expect(input.costForCalculation, 60);
    expect(input.marketQuantity, 0);
    expect(input.filledQuantity, 0);
    expect(input.coversRequest, isFalse);
    expect(quote.inputCost, isNull);
    expect(quote.estimatedInputCost, 60);
    expect(quote.calculationInputCost, 60);
    expect(quote.hasEstimatedInputs, isTrue);
    expect(quote.marketReady, isFalse);
    expect(quote.inputCraftCapacity, 0);
    expect(quote.issues, contains(OpportunityIssue.insufficientInputs));
    expect(quote.listingProfit, closeTo(193.5, .000001));
    expect(quote.buyerProfit, closeTo(168.15, .000001));
  });

  test('partial stock retains actual asks; only shortfall uses base', () {
    final quote = fixture.calculate(
      crafts: 5,
      input: fixture.marketItem('2', price: 10, asks: [fixture.level(15, 2)]),
    );
    final input = quote.ingredients.single;
    expect(input.estimatedCost, 60); // 2 actual x15 + 3 estimated x10.
    expect(input.preliminaryCost, 50);
    expect(input.estimatedMarketQuantity, 3);
    expect(input.marketQuantity, 2);
    expect(input.filledQuantity, 2);
    expect(input.availableQuantity, 2);
    expect(quote.totalCost, 60);
    expect(quote.marketReady, isFalse);
    expect(quote.inputCraftCapacity, 2);
  });

  test('estimated input costs are not taxed; fees are deducted once', () {
    final quote = fixture.calculate(
      crafts: 2,
      tax: MarketTax(valuePack: true, merchantRing: true),
      input: fixture.marketItem('2', price: 20, asks: []),
      extraCostPerRun: 7,
      extraCostPerCraft: 3,
    );
    expect(quote.estimatedInputCost, 40);
    expect(quote.totalCost, 53);
    expect(quote.listingRevenue, closeTo(175.5, .000001));
    expect(quote.listingProfit, closeTo(122.5, .000001));
    expect(quote.buyerProfit, closeTo(104.95, .000001));
  });

  test(
    'missing, stale, future, invalid and unlisted base prices never estimate',
    () {
      final old = fixture.now.subtract(const Duration(minutes: 6));
      final future = fixture.now.add(const Duration(seconds: 1));
      for (final input in [
        fixture.marketItem('2', asks: [], quoteTime: old),
        fixture.marketItem('2', asks: [], quoteTime: future),
        fixture.marketItem('2', price: 0, asks: []),
        fixture.marketItem('2', price: -1, asks: []),
        fixture.marketItem('2', asks: [], unlisted: true),
        fixture.marketItem('99', asks: []),
      ]) {
        final quote = fixture.calculate(input: input);
        expect(quote.estimatedInputCost, isNull);
        expect(quote.listingProfit, isNull);
        expect(quote.buyerProfit, isNull);
        expect(quote.hasEstimatedInputs, isFalse);
      }
    },
  );

  test(
    'unusable books do not invalidate a separate fresh base-price estimate',
    () {
      for (final input in [
        fixture.marketItem('2', unknownBook: true),
        fixture.marketItem(
          '2',
          asks: [],
          bookTime: fixture.now.subtract(const Duration(minutes: 6)),
        ),
        fixture.marketItem(
          '2',
          asks: [],
          bookTime: fixture.now.add(const Duration(seconds: 1)),
        ),
        fixture.marketItem('2', asks: [fixture.level(0, 10)]),
        fixture.marketItem('2', asks: [fixture.level(10, -1)]),
      ]) {
        final quote = fixture.calculate(input: input);
        expect(quote.inputCost, isNull);
        expect(quote.estimatedInputCost, 10);
        expect(
          quote.ingredients.single.estimateKind,
          OpportunityInputEstimateKind.uncheckedDepth,
        );
        expect(quote.ingredients.single.filledQuantity, 0);
        expect(quote.inputCapacityKnown, isFalse);
        expect(quote.marketReady, isFalse);
      }
    },
  );

  test('a missing quote and missing output buyer depth stay unknown', () {
    final missing = fixture.calculate(omitInput: true);
    expect(missing.estimatedInputCost, isNull);
    final noBuyers = fixture.calculate(
      input: fixture.marketItem('2', asks: []),
      output: fixture.marketItem('1', price: 100, bids: []),
    );
    expect(noBuyers.listingProfit, closeTo(74.5, .000001));
    expect(noBuyers.buyerProfit, isNull);
    expect(noBuyers.buyersCoverOutput, isFalse);
    expect(noBuyers.buyerFilledQuantity, 0);
  });

  test('one unknown ingredient prevents an incomplete full-run estimate', () {
    final quote = fixture.calculate(
      product: fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', 1),
          fixture.ingredient('Other', 1),
        ],
      ),
      input: fixture.marketItem('2', asks: []),
      extras: {'Other': fixture.leaf('Other', id: '3')},
    );
    expect(quote.hasEstimatedInputs, isTrue);
    expect(quote.estimatedInputCost, isNull);
    expect(quote.totalCost, isNull);
    expect(quote.listingProfit, isNull);
  });

  test('NPC remainder stays real cost and never needs an estimate', () {
    final quote = fixture.calculate(
      crafts: 5,
      npcPrice: 20,
      input: fixture.marketItem('2', price: 5, asks: [fixture.level(10, 2)]),
    );
    expect(quote.inputCost, 80);
    expect(quote.estimatedInputCost, isNull);
    expect(quote.hasEstimatedInputs, isFalse);
    expect(quote.ingredients.single.npcQuantity, 3);
    expect(quote.ingredients.single.estimatedMarketQuantity, 0);
    expect(quote.marketReady, isTrue);
  });

  test('full asks stay real when base quote is stale', () {
    final quote = fixture.calculate(
      input: fixture.marketItem(
        '2',
        quoteTime: fixture.now.subtract(const Duration(hours: 1)),
      ),
    );
    expect(quote.inputCost, 10);
    expect(quote.estimatedInputCost, isNull);
    expect(quote.hasEstimatedInputs, isFalse);
    expect(quote.marketReady, isTrue);
  });

  test(
    'duplicate aliases share stock and estimate their combined shortage once',
    () {
      final quote = fixture.calculate(
        product: fixture.recipe(
          'Product',
          ingredients: [
            fixture.ingredient('Ore', 2),
            fixture.ingredient('Alias Ore', 3),
          ],
        ),
        extras: {'Alias Ore': fixture.leaf('Alias Ore', id: '0002')},
        input: fixture.marketItem('2', price: 10, asks: [fixture.level(20, 4)]),
      );
      expect(quote.ingredients, hasLength(1));
      expect(quote.ingredients.single.estimatedMarketQuantity, 1);
      expect(quote.estimatedInputCost, 90);
    },
  );

  test(
    'buyable complete formula wins even if unavailable estimate is cheaper',
    () {
      final product = fixture.recipe(
        'Product',
        variants: [
          fixture.variant('estimate', [fixture.ingredient('Ore', 1)]),
          fixture.variant('buyable', [fixture.ingredient('NPC', 1)]),
        ],
      );
      final extras = {'NPC': fixture.leaf('NPC', npc: 100)};
      final input = fixture.marketItem('2', price: 1, asks: []);
      final automatic = fixture.calculate(
        product: product,
        extras: extras,
        input: input,
      );
      expect(automatic.selectedVariantId, 'buyable');
      expect(automatic.hasEstimatedInputs, isFalse);
      expect(automatic.listingProfit, lessThan(0));
      final manual = fixture.calculate(
        product: product,
        extras: extras,
        input: input,
        selectedVariantId: 'estimate',
      );
      expect(manual.estimatedInputCost, 1);
      expect(manual.marketReady, isFalse);
      expect(manual.listingProfit, greaterThan(0));
    },
  );

  test('buyable substitute also wins over cheaper missing-stock estimate', () {
    final quote = fixture.calculate(
      product: fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', 1, options: ['Ore', 'Other']),
        ],
      ),
      input: fixture.marketItem('2', price: 1, asks: []),
      extras: {'Other': fixture.leaf('Other', id: '3')},
      additionalMarket: {'3': fixture.marketItem('3', price: 20)},
    );
    expect(quote.ingredients.single.name, 'Other');
    expect(quote.marketReady, isTrue);
    expect(quote.inputCost, 20);
  });

  test('known estimated substitutes rank by actual plus missing cost', () {
    final quote = fixture.calculate(
      product: fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', 2, options: ['Ore', 'Other']),
        ],
      ),
      input: fixture.marketItem('2', price: 1, asks: [fixture.level(100, 1)]),
      extras: {'Other': fixture.leaf('Other', id: '3')},
      additionalMarket: {'3': fixture.marketItem('3', price: 10, asks: [])},
    );
    expect(quote.ingredients.single.name, 'Other');
    expect(quote.estimatedInputCost, 20);
  });
}
