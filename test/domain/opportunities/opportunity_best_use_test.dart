import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_best_use.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as f;

void main() {
  test(
    'values one complete craft against selling consumed material after tax',
    () {
      final result = _evaluate()!;
      expect(result.selectedQuantity, 2);
      expect(result.quote.crafts, 1);
      expect(result.otherInputCost, 60);
      expect(result.extraProfitPerUnit, 230); // (650 - 60 - 130) / 2.
      expect(
        result.quote.listingProfit,
        390,
      ); // Ordinary purchase quote intact.
      expect(result.otherIngredientsAvailable, isTrue);
      expect(result.isEstimated, isFalse);
      expect(result.ingredientChoices, {'Ore': 'Ore'});
    },
  );

  test('selected market stock and ask tiers do not value owned material', () {
    final result = _evaluate(
      source: f.marketItem('2', price: 100, stock: 0, asks: const []),
    )!;
    expect(result.quote.ingredientsAvailable, isFalse);
    expect(result.quote.hasEstimatedInputs, isTrue);
    expect(result.otherIngredientsAvailable, isTrue);
    expect(result.isEstimated, isFalse);
    expect(result.extraProfitPerUnit, 230);
    final costlyReplacement = _evaluate(
      source: f.marketItem('2', price: 100, asks: [f.level(10000, 100)]),
    )!;
    expect(costlyReplacement.quote.listingProfit, isNegative);
    expect(costlyReplacement.extraProfitPerUnit, 230);
  });

  test('tax applies equally to output and direct-sale baseline', () {
    final result = _evaluate(
      tax: MarketTax(valuePack: true, merchantRing: true, familyFameBonus: .01),
    )!;
    const netRate = .65 * 1.36;
    expect(result.extraProfitPerUnit, closeTo((800 * netRate - 60) / 2, 1e-9));
  });

  for (final quantity in [26, 27]) {
    test(
      'known ${quantity == 26 ? 'zero' : 'negative'} extra profit is not unknown',
      () {
        final result = _evaluate(
          product: f.recipe(
            'Product',
            ingredients: [
              f.ingredient('Ore', 2),
              f.ingredient('Other', quantity.toDouble()),
            ],
          ),
        )!;
        expect(result.extraProfitPerUnit, quantity == 26 ? 0 : -10);
      },
    );
  }

  for (final scenario in [
    'missing',
    'stale',
    'future',
    'unlisted',
    'other-tier',
    'wrong-id',
  ]) {
    test('$scenario selected sale price stays unknown, never free', () {
      final result = _evaluate(
        omitSource: scenario == 'missing',
        source: switch (scenario) {
          'stale' => f.marketItem(
            '2',
            quoteTime: f.now.subtract(const Duration(minutes: 6)),
          ),
          'future' => f.marketItem(
            '2',
            quoteTime: f.now.add(const Duration(seconds: 1)),
          ),
          'unlisted' => f.marketItem('2', unlisted: true),
          'other-tier' => OpportunityMarketItem(
            itemId: '2',
            subId: 1,
            basePrice: 100,
            stock: 50,
            quoteFetchedAt: f.now,
          ),
          'wrong-id' => f.marketItem('999'),
          _ => null,
        },
      )!;
      expect(result.extraProfitPerUnit, isNull);
      expect(result.otherInputCost, 60);
      expect(result.otherIngredientsAvailable, isTrue);
    });
  }

  test('missing and stale other-input prices cannot become zero costs', () {
    for (final other in <OpportunityMarketItem?>[
      null,
      f.marketItem(
        '3',
        quoteTime: f.now.subtract(const Duration(minutes: 6)),
        unknownBook: true,
      ),
    ]) {
      final result = _evaluate(other: other, omitOther: other == null)!;
      expect(result.otherInputCost, isNull);
      expect(result.extraProfitPerUnit, isNull);
      expect(result.otherIngredientsAvailable, isFalse);
    }
  });

  test('missing or stale output price cannot rank a recipe', () {
    expect(_evaluate(omitOutput: true)!.extraProfitPerUnit, isNull);
    expect(
      _evaluate(
        output: f.marketItem(
          '1',
          quoteTime: f.now.subtract(const Duration(minutes: 6)),
        ),
      )!.extraProfitPerUnit,
      isNull,
    );
    expect(
      _evaluate(output: f.marketItem('1', unlisted: true))!.extraProfitPerUnit,
      isNull,
    );
  });

  test(
    'verified NPC other inputs and actual mixed purchases remain priced',
    () {
      final npc = _evaluate(omitOther: true, npcPrice: 20)!;
      expect(npc.otherInputCost, 60);
      expect(npc.extraProfitPerUnit, 230);
      expect(npc.otherIngredientsAvailable, isTrue);
      final mixed = _evaluate(
        npcPrice: 20,
        other: f.marketItem('3', price: 20, stock: 1, asks: [f.level(10, 1)]),
      )!;
      expect(mixed.otherInputCost, 50);
      expect(mixed.extraProfitPerUnit, 235);
      expect(mixed.otherIngredientsAvailable, isTrue);
    },
  );

  test(
    'fresh summary estimates stay separate from ingredient availability',
    () {
      final available = _evaluate(
        other: f.marketItem('3', price: 20, stock: 3, unknownBook: true),
      )!;
      expect(available.extraProfitPerUnit, 230);
      expect(available.isEstimated, isTrue);
      expect(available.otherIngredientsAvailable, isTrue);
      final short = _evaluate(
        other: f.marketItem('3', price: 20, stock: 2, asks: [f.level(20, 2)]),
      )!;
      expect(short.extraProfitPerUnit, 230);
      expect(short.isEstimated, isTrue);
      expect(short.otherIngredientsAvailable, isFalse);
    },
  );

  test(
    'source aliases and duplicate rows use actual aggregated consumption',
    () {
      final result = _evaluate(
        product: f.recipe(
          'Product',
          ingredients: [
            f.ingredient('Ore', 2),
            f.ingredient('Alias Ore', 3),
            f.ingredient('Ore', 1),
          ],
        ),
        extras: {'Alias Ore': f.leaf('Alias Ore', id: '0002')},
      )!;
      expect(result.selectedQuantity, 6);
      expect(result.quote.ingredients, hasLength(1));
      expect(result.otherInputCost, 0);
      expect(result.extraProfitPerUnit, closeTo((650 - 390) / 6, 1e-9));
      expect(result.ingredientChoices, {
        'Ore': 'Ore',
        'Alias Ore': 'Alias Ore',
      });
    },
  );

  test('forces eligible substitute slots and honors their ratio', () {
    final result = _evaluate(
      product: f.recipe(
        'Product',
        ingredients: [
          f.ingredient('Cheap', 10, options: ['Ore'], ratios: {'Ore': .2}),
        ],
      ),
      extras: {'Cheap': f.leaf('Cheap', id: '4')},
      extraMarket: {'4': f.marketItem('4', price: 1)},
    )!;
    expect(result.selectedQuantity, 2);
    expect(result.ingredientChoices, {'Cheap': 'Ore'});
    expect(result.quote.ingredients.single.name, 'Ore');
  });

  test('resolved canonical ID finds a direct alias absent from this mode', () {
    final recipe = f.recipe(
      'Product',
      ingredients: [f.ingredient('Alias Ore', 2)],
    );
    OpportunityBestUseQuote? evaluate(String? selectedId) =>
        evaluateOpportunityBestUse(
          itemName: 'Canonical Ore',
          selectedItemId: selectedId,
          recipe: recipe,
          mode: CraftMode.processing,
          recipes: {
            'Product': recipe,
            'Alias Ore': f.leaf('Alias Ore', id: '2'),
          },
          state: f.state(),
          rules: PlannerRules(),
          marketTax: MarketTax(),
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: {
              '1': f.marketItem('1', price: 1000),
              '2': f.marketItem('2', price: 100),
            },
          ),
          now: f.now,
          maxMarketAge: const Duration(minutes: 5),
        );
    expect(evaluate(null), isNull);
    final result = evaluate('0002')!;
    expect(result.itemName, 'Canonical Ore');
    expect(result.selectedQuantity, 2);
    expect(result.ingredientChoices, {'Alias Ore': 'Alias Ore'});
    expect(result.extraProfitPerUnit, 260);
    expect(evaluate('3'), isNull);
    for (final invalid in ['0', '-2', '2.0', '2e0', 'not-an-id']) {
      expect(evaluate(invalid), isNull);
    }
  });

  test('higher grade is resolved and rounded by the existing calculator', () {
    final result = _evaluate(
      itemName: 'Special Herb',
      product: f.recipe(
        'Product',
        type: 'alchemy',
        ingredients: [f.ingredient('Herb', 7)],
      ),
      extras: {'Herb': f.leaf('Herb', id: '4')},
      rules: PlannerRules(qualityIngredients: {'Herb'}),
    )!;
    expect(result.selectedQuantity, 2);
    expect(result.ingredientChoices, {'Herb': 'Special Herb'});
    expect(result.quote.ingredients.single.name, 'Special Herb');
    expect(result.mode, CraftMode.alchemy);
  });

  test(
    'denominator uses consumed whole units, not a fractional raw quantity',
    () {
      final result = _evaluate(
        product: f.recipe('Product', ingredients: [f.ingredient('Ore', .25)]),
      )!;
      expect(result.selectedQuantity, 1);
      expect(result.extraProfitPerUnit, 585);
    },
  );

  test(
    'compares whole variants per material instead of output or total profit',
    () {
      final product = f.recipe(
        'Product',
        variants: [
          f.variant('bulk', [f.ingredient('Ore', 100)], output: 10, batch: 10),
          f.variant('efficient', [
            f.ingredient('Ore', 1),
            f.ingredient('Other', 25),
          ]),
        ],
      );
      final result = _evaluate(
        product: product,
        source: f.marketItem('2', price: 10),
      )!;
      expect(result.quote.selectedVariantId, 'efficient');
      expect(result.selectedQuantity, 1);
      expect(result.extraProfitPerUnit, 143.5);
      expect(result.quote.expectedOutput, 1);
      expect(result.quote.crafts, 1);
    },
  );

  test('only variants actually using selected material are eligible', () {
    final product = f.recipe(
      'Product',
      variants: [
        f.variant('unrelated', [f.ingredient('Other', 1)], output: 100),
        f.variant(
          'selected-10x',
          [f.ingredient('Ore', 20)],
          output: 10,
          batch: 10,
        ),
      ],
    );
    final result = _evaluate(product: product)!;
    expect(result.quote.selectedVariantId, 'selected-10x');
    expect(result.selectedQuantity, 20);
    expect(result.quote.expectedOutput, 10);
  });

  test(
    'available-input preference ignores selected stock and finds supplied variant',
    () {
      final product = f.recipe(
        'Product',
        variants: [
          f.variant('cheap', [
            f.ingredient('Ore', 2),
            f.ingredient('Other', 1),
          ]),
          f.variant('supplied', [
            f.ingredient('Ore', 2),
            f.ingredient('Alternative', 1),
          ]),
        ],
      );
      OpportunityBestUseQuote evaluate(bool prefer) => _evaluate(
        product: product,
        source: f.marketItem('2', price: 100, stock: 0, asks: const []),
        other: f.marketItem('3', price: 10, stock: 0, asks: const []),
        extras: {'Alternative': f.leaf('Alternative', id: '4')},
        extraMarket: {'4': f.marketItem('4', price: 20)},
        preferAvailableInputs: prefer,
      )!;
      expect(evaluate(false).quote.selectedVariantId, 'cheap');
      final available = evaluate(true);
      expect(available.quote.selectedVariantId, 'supplied');
      expect(available.otherIngredientsAvailable, isTrue);
      expect(available.quote.ingredientsAvailable, isFalse);
    },
  );

  test(
    'direct-use enumeration includes all routes but not upstream recipes',
    () {
      final child = f.recipe(
        'Intermediate',
        ingredients: [f.ingredient('Ore', 2)],
      );
      final product = f.recipe(
        'Product',
        variants: [
          f.variant('base-route', [f.ingredient('Intermediate', 1)]),
          f.variant('other-route', [f.ingredient('Other', 2)]),
        ],
      );
      final recipes = {
        product.name: product,
        child.name: child,
        'Other': f.leaf('Other', id: '3'),
      };
      final names = opportunityBestUseItems(
        product,
        recipes: recipes,
        rules: PlannerRules(),
      );
      expect(names, contains('Other'));
      expect(names, isNot(contains('Ore')));
      expect(
        _evaluate(product: product, extras: {'Intermediate': child}),
        isNull,
      );
    },
  );

  test(
    'invalid quantities, references, leaves, and self uses do not qualify',
    () {
      for (final recipe in [
        f.recipe('Product', ingredients: [f.ingredient('Ore', 0)]),
        f.recipe('Product', ingredients: [f.ingredient('Ore', double.nan)]),
        f.recipe('Product', role: RecipeRole.manualConversion),
        f.recipe('Product', role: RecipeRole.salvage),
        f.leaf('Product'),
      ]) {
        expect(_evaluate(product: recipe), isNull);
      }
      expect(_evaluate(itemName: ''), isNull);
      expect(_evaluate(itemName: 'Product'), isNull);
      expect(
        _evaluate(rules: PlannerRules(legacyUnavailableItems: {'Product'})),
        isNull,
      );
    },
  );

  test('uses supplied mastery and never changes inventory or choices', () {
    final state = f
        .state(inventory: {'Ore': 999}, choices: {'Product': 'saved'})
        .copyWith(alchemyMastery: 1700);
    final before = state.toJson();
    final result = _evaluate(
      product: f.recipe('Product', type: 'alchemy', minimum: 1, maximum: 4),
      state: state,
    )!;
    final ordinary = f.calculate(product: result.recipe, state: state);
    expect(result.quote.outputPerCraft, ordinary.outputPerCraft);
    expect(state.toJson(), before);
    expect(
      () => result.ingredientChoices['Other'] = 'Ore',
      throwsUnsupportedError,
    );
  });

  test('suggestions omit malformed whole routes without requiring prices', () {
    final recipe = f.recipe(
      'Product',
      variants: [
        f.variant('bad', [f.ingredient('Other', 0)]),
        f.variant('valid', [f.ingredient('Ore', 2)]),
      ],
    );
    final recipes = {
      'Product': recipe,
      'Ore': f.leaf('Ore', id: '2'),
      'Other': f.leaf('Other', id: '3'),
    };
    expect(
      opportunityBestUseItems(recipe, recipes: recipes, rules: PlannerRules()),
      {'Ore'},
    );
  });

  test(
    'real Trace of Nature directly selects Gem Polisher without an amount',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipes = catalog.alchemy.items;
      final recipe = recipes['Gem Polisher']!;
      final rules = const PlannerAssembly().plannerRules(
        catalog.supportingData,
      );
      const calculator = OpportunityCalculator();
      final ids = calculator.marketItemIds(
        recipe: recipe,
        recipes: recipes,
        rules: rules,
      );
      final result = evaluateOpportunityBestUse(
        itemName: 'Trace of Nature',
        recipe: recipe,
        mode: CraftMode.alchemy,
        recipes: recipes,
        rules: rules,
        state: f.state().copyWith(alchemyMastery: 1700),
        marketTax: MarketTax(valuePack: true),
        market: OpportunityMarketSnapshot(
          region: 'eu',
          items: {for (final id in ids) id: f.marketItem(id, price: 100)},
        ),
        now: f.now,
        maxMarketAge: const Duration(minutes: 5),
        catalogNpcPrices: CatalogRepository(catalog).npcPurchasePrices,
      )!;
      expect(result.selectedQuantity, 2);
      expect(result.ingredientChoices, {'Trace of Nature': 'Trace of Nature'});
      expect(result.quote.crafts, 1);
      expect(result.extraProfitPerUnit, isNotNull);
    },
  );
}

OpportunityBestUseQuote? _evaluate({
  Recipe? product,
  String itemName = 'Ore',
  OpportunityMarketItem? source,
  OpportunityMarketItem? other,
  OpportunityMarketItem? output,
  bool omitSource = false,
  bool omitOther = false,
  bool omitOutput = false,
  double npcPrice = 0,
  Map<String, Recipe> extras = const {},
  Map<String, OpportunityMarketItem> extraMarket = const {},
  PlannerRules? rules,
  ModeState? state,
  MarketTax? tax,
  bool preferAvailableInputs = false,
}) {
  final recipe =
      product ??
      f.recipe(
        'Product',
        ingredients: [f.ingredient('Ore', 2), f.ingredient('Other', 3)],
      );
  final mode =
      CraftMode.values.where((m) => m.key == recipe.type).firstOrNull ??
      CraftMode.processing;
  return evaluateOpportunityBestUse(
    itemName: itemName,
    recipe: recipe,
    mode: mode,
    recipes: {
      recipe.name: recipe,
      itemName: f.leaf(itemName, id: '2'),
      'Other': f.leaf('Other', id: '3', npc: npcPrice),
      ...extras,
    },
    state: state ?? f.state(),
    rules: rules ?? PlannerRules(),
    marketTax: tax ?? MarketTax(),
    market: OpportunityMarketSnapshot(
      region: 'eu',
      items: {
        if (!omitOutput) '1': output ?? f.marketItem('1', price: 1000),
        if (!omitSource) '2': source ?? f.marketItem('2', price: 100),
        if (!omitOther) '3': other ?? f.marketItem('3', price: 20),
        ...extraMarket,
      },
    ),
    now: f.now,
    maxMarketAge: const Duration(minutes: 5),
    preferAvailableInputs: preferAvailableInputs,
  );
}
