import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_best_use.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as f;

void main() {
  test(
    'compares raw material instead of ordinary purchase profit or output',
    () {
      final quote = _quote();
      final result = _compare(quote)!;
      expect(result.selectedQuantity, 2);
      expect(quote.expectedOutput, 1);
      expect(quote.listingRevenue, 650);
      expect(quote.listingProfit, 390);
      expect(result.rawIngredientSale, 130);
      expect(result.rawSalePerUnit, 65);
      expect(result.otherInputCost, 60);
      expect(result.craftingReturn, 590);
      expect(result.craftingReturnPerUnit, 295);
      expect(result.profitLoss, 460);
      expect(result.profitLossPerUnit, 230);
      expect(result.isEstimated, isFalse);
      expect(result.otherIngredientsAvailable, isTrue);
    },
  );

  test(
    'edited crafts use current ask tiers instead of scaling a cached result',
    () {
      final other = f.marketItem(
        '3',
        price: 20,
        asks: [f.level(20, 3), f.level(30, 100)],
      );
      final single = _compare(_quote(other: other))!;
      final doubled = _compare(_quote(other: other, crafts: 2))!;
      expect(single.otherInputCost, 60);
      expect(single.profitLossPerUnit, 230);
      expect(doubled.selectedQuantity, 4);
      expect(doubled.rawIngredientSale, 260);
      expect(doubled.otherInputCost, 150);
      expect(doubled.craftingReturn, 1150);
      expect(doubled.profitLoss, 890);
      expect(doubled.profitLossPerUnit, 222.5);
    },
  );

  test('edited custom sale price changes return but not raw-sale baseline', () {
    final quote = _quote(
      crafts: 2,
      customSalePrice: 2000,
      other: f.marketItem('3', asks: [f.level(20, 3), f.level(30, 100)]),
    );
    final result = _compare(quote)!;
    expect(quote.hasCustomSalePrice, isTrue);
    expect(quote.listingRevenue, 2600);
    expect(result.selectedQuantity, 4);
    expect(result.rawIngredientSale, 260);
    expect(result.rawSalePerUnit, 65);
    expect(result.otherInputCost, 150);
    expect(result.craftingReturn, 2450);
    expect(result.profitLoss, 2190);
    expect(result.profitLossPerUnit, 547.5);
  });

  test(
    'fractional expected output does not become the per-item denominator',
    () {
      final quote = _quote(
        product: f.recipe(
          'Product',
          minimum: 2,
          maximum: 3,
          ingredients: [f.ingredient('Ore', 2), f.ingredient('Other', 3)],
        ),
      );
      final result = _compare(quote)!;
      expect(quote.expectedOutput, 2.5);
      expect(result.selectedQuantity, 2);
      expect(result.rawSalePerUnit, 65);
      expect(result.profitLossPerUnit, 717.5);
    },
  );

  test('missing output keeps independently known raw sale and other cost', () {
    final result = _compare(_quote(omitOutput: true))!;
    expect(result.selectedQuantity, 2);
    expect(result.rawIngredientSale, 130);
    expect(result.rawSalePerUnit, 65);
    expect(result.otherInputCost, 60);
    expect(result.craftingReturn, isNull);
    expect(result.craftingReturnPerUnit, isNull);
    expect(result.profitLoss, isNull);
    expect(result.profitLossPerUnit, isNull);
  });

  test(
    'missing other-input price cannot hide known raw sale or become free',
    () {
      final result = _compare(_quote(omitOther: true))!;
      expect(result.rawIngredientSale, 130);
      expect(result.rawSalePerUnit, 65);
      expect(result.otherInputCost, isNull);
      expect(result.craftingReturn, isNull);
      expect(result.profitLossPerUnit, isNull);
      expect(result.otherIngredientsAvailable, isFalse);
    },
  );

  for (final scenario in [
    'missing',
    'stale',
    'future',
    'unlisted',
    'wrong-id',
    'other-tier',
  ]) {
    test(
      '$scenario selected resale stays unknown but crafting return survives',
      () {
        final input = switch (scenario) {
          'stale' => f.marketItem(
            '2',
            price: 100,
            quoteTime: f.now.subtract(const Duration(minutes: 6)),
          ),
          'future' => f.marketItem(
            '2',
            price: 100,
            quoteTime: f.now.add(const Duration(seconds: 1)),
          ),
          'unlisted' => f.marketItem('2', price: 100, unlisted: true),
          'wrong-id' => f.marketItem('999', price: 100),
          'other-tier' => OpportunityMarketItem(
            itemId: '2',
            subId: 1,
            basePrice: 100,
            stock: 50,
            quoteFetchedAt: f.now,
          ),
          _ => null,
        };
        final result = _compare(
          _quote(input: input, omitInput: scenario == 'missing'),
        )!;
        expect(result.selectedQuantity, 2);
        expect(result.rawIngredientSale, isNull);
        expect(result.rawSalePerUnit, isNull);
        expect(result.otherInputCost, 60);
        expect(result.craftingReturn, 590);
        expect(result.craftingReturnPerUnit, 295);
        expect(result.profitLoss, isNull);
        expect(result.profitLossPerUnit, isNull);
      },
    );
  }

  test('selected ask prices, stock and buyers do not value owned material', () {
    for (final input in [
      f.marketItem('2', price: 100, stock: 0, asks: [], bids: []),
      f.marketItem('2', price: 100, asks: [f.level(10000, 100)]),
    ]) {
      final quote = _quote(
        input: input,
        output: f.marketItem('1', price: 1000, stock: 0, asks: [], bids: []),
      );
      final result = _compare(quote)!;
      expect(result.rawIngredientSale, 130);
      expect(result.profitLossPerUnit, 230);
      expect(result.isEstimated, isFalse);
      expect(result.otherIngredientsAvailable, isTrue);
    }
    expect(
      _quote(
        input: f.marketItem('2', asks: [f.level(10000, 100)]),
      ).listingProfit,
      isNegative,
    );
  });

  test(
    'only other-input estimates and availability qualify the comparison',
    () {
      final result = _compare(
        _quote(
          other: f.marketItem('3', price: 20, stock: 2, unknownBook: true),
        ),
      )!;
      expect(result.rawSalePerUnit, 65);
      expect(result.otherInputCost, 60);
      expect(result.profitLossPerUnit, 230);
      expect(result.isEstimated, isTrue);
      expect(result.otherIngredientsAvailable, isFalse);
    },
  );

  test('canonical ID includes aliased duplicate input slots', () {
    final quote = _quote(
      product: f.recipe(
        'Product',
        ingredients: [
          f.ingredient('Ore', 2),
          f.ingredient('Alias Ore', 3),
          f.ingredient('Ore', 1),
        ],
      ),
      extras: {'Alias Ore': f.leaf('Alias Ore', id: '0002')},
    );
    final result = _compare(
      quote,
      itemName: 'Canonical material absent from this mode',
      selectedItemId: '0002',
    )!;
    expect(result.selectedQuantity, 6);
    expect(result.rawIngredientSale, 390);
    expect(result.rawSalePerUnit, 65);
    expect(result.otherInputCost, 0);
    expect(result.profitLoss, 260);
    expect(result.profitLossPerUnit, closeTo(260 / 6, 1e-9));
  });

  test('folded name is available when no canonical ID was supplied', () {
    final result = _compare(
      _quote(),
      itemName: '  oRE  ',
      selectedItemId: null,
    )!;
    expect(result.selectedQuantity, 2);
    expect(result.profitLossPerUnit, 230);
  });

  test(
    'consumed whole units, not fractional formula quantities, set the basis',
    () {
      final quote = _quote(
        product: f.recipe('Product', ingredients: [f.ingredient('Ore', .25)]),
      );
      final result = _compare(quote)!;
      expect(result.selectedQuantity, 1);
      expect(result.rawIngredientSale, 65);
      expect(result.profitLossPerUnit, 585);
    },
  );

  test('removed selection and zero craft quantity return no comparison', () {
    final quote = _quote(
      product: f.recipe('Product', ingredients: [f.ingredient('Other', 3)]),
    );
    expect(_compare(quote), isNull);
    expect(_compare(_quote(crafts: 0)), isNull);
    expect(_compare(_quote(), itemName: '', selectedItemId: null), isNull);
  });

  test(
    'an invalid or different explicit ID never falls back to matching name',
    () {
      for (final id in ['0', '-2', '2.0', '2e0', 'bad', '3']) {
        final result = _compare(_quote(), selectedItemId: id);
        if (id == '3') {
          // A different valid ID refers to the actual other input, not Ore.
          expect(result!.selectedQuantity, 3);
          expect(result.rawIngredientSale, 39);
        } else {
          expect(result, isNull);
        }
      }
    },
  );

  test('configured tax applies equally to raw sale and crafted output', () {
    final tax = MarketTax(
      valuePack: true,
      merchantRing: true,
      familyFameBonus: .01,
    );
    final result = _compare(_quote(tax: tax), tax: tax)!;
    expect(result.rawIngredientSale, closeTo(176.8, 1e-9));
    expect(result.craftingReturn, closeTo(824, 1e-9));
    expect(result.profitLossPerUnit, closeTo(323.6, 1e-9));
  });

  test('invalid custom output price does not erase raw-sale reference', () {
    final result = _compare(_quote(customSalePrice: 0))!;
    expect(result.rawIngredientSale, 130);
    expect(result.craftingReturn, isNull);
    expect(result.profitLossPerUnit, isNull);
  });
}

OpportunityQuote _quote({
  Recipe? product,
  OpportunityMarketItem? input,
  OpportunityMarketItem? other,
  OpportunityMarketItem? output,
  int crafts = 1,
  int? customSalePrice,
  bool omitInput = false,
  bool omitOther = false,
  bool omitOutput = false,
  MarketTax? tax,
  Map<String, Recipe> extras = const {},
}) => f.calculate(
  product:
      product ??
      f.recipe(
        'Product',
        ingredients: [f.ingredient('Ore', 2), f.ingredient('Other', 3)],
      ),
  input: input ?? f.marketItem('2', price: 100),
  output: output ?? f.marketItem('1', price: 1000),
  crafts: crafts,
  customSalePrice: customSalePrice,
  omitInput: omitInput,
  omitOutput: omitOutput,
  tax: tax ?? MarketTax(),
  extras: {
    'Other': f.leaf('Other', id: '3'),
    ...extras,
  },
  additionalMarket: {
    if (!omitOther) '3': other ?? f.marketItem('3', price: 20),
  },
);

OpportunityBestUseComparison? _compare(
  OpportunityQuote quote, {
  String itemName = 'Ore',
  String? selectedItemId = '2',
  MarketTax? tax,
}) => calculateOpportunityBestUseComparison(
  quote: quote,
  itemName: itemName,
  selectedItemId: selectedItemId,
  marketTax: tax ?? MarketTax(),
  now: f.now,
  maxMarketAge: const Duration(minutes: 5),
);
