import 'package:bdo_craft_planner_flutter/domain/market/recipe_profitability.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = RecipeProfitabilityCalculator();

  test(
    'prices direct inputs, prefers vendors, and reports per-piece return',
    () {
      final product = _recipe(
        'Product',
        type: 'simple_alchemy',
        baseOutput: 2,
        ingredients: <Ingredient>[
          _ingredient('Ore', 2),
          _ingredient('Vendor Material', 1),
        ],
      );
      final recipes = <String, Recipe>{
        product.name: product,
        'Ore': _leaf('Ore'),
        'Vendor Material': _leaf('Vendor Material', npcPrice: 5),
      };
      final state = _state(
        market: MarketState(
          prices: const <String, double>{
            'Product': 100,
            'Ore': 10,
            'Vendor Material': 999,
          },
        ),
      );

      final quote = calculator.calculate(
        recipe: product,
        recipes: recipes,
        state: state,
        rules: PlannerRules(),
        marketTax: MarketTax(),
      );

      expect(quote.isAvailable, isTrue);
      expect(quote.isProfitable, isTrue);
      expect(quote.outputPerCraft, 2);
      expect(quote.ingredientCost, 25);
      expect(quote.grossRevenue, 200);
      expect(quote.netRevenue, 130);
      expect(quote.profitPerCraft, 105);
      expect(quote.profitPerPiece, 52.5);
      expect(quote.returnOnCostPercent, 420);
      expect(quote.marketNetRate, .65);
      expect(
        quote.ingredientCosts.map((cost) => cost.priceSource),
        <RecipeIngredientPriceSource>[
          RecipeIngredientPriceSource.market,
          RecipeIngredientPriceSource.vendor,
        ],
      );
      expect(quote.directMarketItemNames, <String>{'Product', 'Ore'});
    },
  );

  test('applies saved tax settings to expected-output sale proceeds', () {
    final product = _recipe(
      'Alchemy Product',
      type: 'alchemy',
      outputMinimum: 1,
      outputMaximum: 4,
      ingredients: <Ingredient>[_ingredient('Material', 1)],
    );
    final quote = calculator.calculate(
      recipe: product,
      recipes: <String, Recipe>{
        product.name: product,
        'Material': _leaf('Material'),
      },
      state: _state(
        market: MarketState(
          prices: const <String, double>{
            'Alchemy Product': 100,
            'Material': 50,
          },
        ),
      ),
      rules: PlannerRules(),
      marketTax: MarketTax(),
    );

    expect(quote.outputPerCraft, 2.5);
    expect(quote.grossRevenue, 250);
    expect(quote.netRevenue, 162.5);
    expect(quote.profitPerCraft, 112.5);
    expect(quote.profitPerPiece, 45);
    expect(quote.returnOnCostPercent, 225);
    expect(quote.marketNetRate, .65);
  });

  test('resolves the saved complete variant without scaling it again', () {
    final product = _recipe(
      'Batch Product',
      ingredients: <Ingredient>[_ingredient('One Material', 1)],
      variants: <RecipeVariant>[
        _variant(
          id: 'route-a-x1',
          label: 'A',
          baseOutput: 1,
          ingredients: <Ingredient>[_ingredient('One Material', 1)],
        ),
        _variant(
          id: 'route-a-x10',
          label: 'A',
          baseOutput: 10,
          batchMultiplier: 10,
          ingredients: <Ingredient>[
            _ingredient('Ten Material', 11),
            _ingredient('Batch Catalyst', 1),
          ],
        ),
      ],
      defaultVariantId: 'route-a-x1',
    );
    final state = _state(
      recipeVariantChoices: const <String, String>{
        'batch product': 'ROUTE-A-X10',
      },
      market: MarketState(
        prices: const <String, double>{
          'Batch Product': 100,
          'Ten Material': 50,
          'Batch Catalyst': 20,
          'One Material': 1,
        },
      ),
    );

    final quote = calculator.calculate(
      recipe: product,
      recipes: <String, Recipe>{
        product.name: product,
        'One Material': _leaf('One Material'),
        'Ten Material': _leaf('Ten Material'),
        'Batch Catalyst': _leaf('Batch Catalyst'),
      },
      state: state,
      rules: PlannerRules(),
      marketTax: MarketTax(),
    );

    expect(quote.isAvailable, isTrue);
    expect(quote.selectedVariantId, 'route-a-x10');
    expect(quote.outputPerCraft, 10);
    expect(quote.ingredientCost, 570);
    expect(quote.profitPerPiece, 8);
    expect(quote.directMarketItemNames, <String>{
      'Batch Product',
      'Ten Material',
      'Batch Catalyst',
    });
  });

  test('honors saved substitute ratios and grade ceiling conversion', () {
    final product = _recipe(
      'Quality Product',
      ingredients: <Ingredient>[
        Ingredient(
          name: 'Herb',
          quantity: 10,
          options: const <String>['Herb', 'Other Herb'],
          substituteGroup: 'Herbs',
          substituteRatios: const <String, double>{'Other Herb': 2},
        ),
      ],
    );
    final rules = PlannerRules(
      qualityConversions: const <String, QualityConversionRule>{
        'Other Herb': QualityConversionRule(
          special: QualityTierRule(name: 'Special Other Herb', ratio: 5),
        ),
      },
    );
    final state = _state(
      substituteChoices: const <String, String>{
        'recipe:quality product:herbs': 'OTHER HERB',
      },
      ingredientGrades: const <String, String>{
        'recipe:quality product:herb': 'SPECIAL',
      },
      market: MarketState(
        prices: const <String, double>{
          'Quality Product': 200,
          'Special Other Herb': 30,
        },
      ),
    );
    final recipes = <String, Recipe>{
      product.name: product,
      'Herb': _leaf('Herb'),
      'Other Herb': _leaf('Other Herb'),
      'Special Other Herb': _leaf('Special Other Herb'),
    };

    final quote = calculator.calculate(
      recipe: product,
      recipes: recipes,
      state: state,
      rules: rules,
      marketTax: MarketTax(),
    );

    expect(quote.isAvailable, isTrue);
    expect(quote.ingredientCosts, hasLength(1));
    final cost = quote.ingredientCosts.single;
    expect(cost.originalName, 'Herb');
    expect(cost.selectedName, 'Special Other Herb');
    expect(cost.grade, 'special');
    expect(cost.quantity, 4);
    expect(cost.unitPrice, 30);
    expect(cost.total, 120);
    expect(
      calculator.directMarketItemNames(
        recipe: product,
        recipes: recipes,
        state: state,
        rules: rules,
      ),
      <String>{'Quality Product', 'Special Other Herb'},
    );
  });

  test(
    'uses the Planner automatic substitute when no choice has been saved',
    () {
      final product = _recipe(
        'Automatic Product',
        ingredients: <Ingredient>[
          Ingredient(
            name: 'Original Material',
            quantity: 2,
            options: const <String>['Original Material', 'Owned Substitute'],
            substituteGroup: 'Materials',
            substituteRatios: const <String, double>{'Owned Substitute': 1.5},
          ),
        ],
      );
      final recipes = <String, Recipe>{
        product.name: product,
        'Original Material': _leaf('Original Material'),
        'Owned Substitute': _leaf('Owned Substitute'),
      };
      final state = _state(
        market: MarketState(
          prices: const <String, double>{
            'Automatic Product': 100,
            'Original Material': 40,
            'Owned Substitute': 10,
          },
          stock: const <String, double>{
            'Original Material': 100,
            'Owned Substitute': 100,
          },
        ),
      );
      final rules = PlannerRules(
        marketIds: const <String, String>{
          'Original Material': '1',
          'Owned Substitute': '2',
        },
      );

      final quote = calculator.calculate(
        recipe: product,
        recipes: recipes,
        state: state,
        rules: rules,
        marketTax: MarketTax(),
      );

      expect(quote.isAvailable, isTrue);
      expect(quote.ingredientCosts.single.selectedName, 'Owned Substitute');
      expect(quote.ingredientCosts.single.quantity, 3);
      expect(quote.ingredientCost, 30);
      expect(quote.profitPerPiece, 35);
      expect(quote.directMarketItemNames, <String>{
        'Automatic Product',
        'Owned Substitute',
      });
    },
  );

  test('processing output uses the recipe-owned recorded result range', () {
    final product = _recipe(
      'Processed Product',
      type: 'processing',
      outputMinimum: 2,
      outputMaximum: 4,
      ingredients: <Ingredient>[_ingredient('Raw Material', 1)],
    );

    final quote = calculator.calculate(
      recipe: product,
      recipes: <String, Recipe>{
        product.name: product,
        'Raw Material': _leaf('Raw Material'),
      },
      state: _state(
        processingMastery: 3000,
        ingredientGrades: const <String, String>{
          'recipe:Processed Product:Raw Material': 'special',
        },
        market: MarketState(
          prices: const <String, double>{
            'Processed Product': 100,
            'Raw Material': 40,
          },
        ),
      ),
      rules: PlannerRules(qualityIngredients: const <String>{'Raw Material'}),
      marketTax: MarketTax(),
    );

    expect(quote.isAvailable, isTrue);
    expect(quote.outputPerCraft, 3);
    expect(quote.ingredientCosts.single.grade, 'normal');
    expect(quote.ingredientCosts.single.selectedName, 'Raw Material');
    expect(quote.profitPerPiece, closeTo(155 / 3, 1e-12));
  });

  test('never treats a bundled fallback price as current market data', () {
    final product = _recipe(
      'Fallback Product',
      ingredients: <Ingredient>[_ingredient('Fallback Material', 1)],
    );
    final quote = calculator.calculate(
      recipe: product,
      recipes: <String, Recipe>{
        product.name: product,
        'Fallback Material': _leaf('Fallback Material'),
      },
      state: _state(
        market: MarketState(
          prices: const <String, double>{'Fallback Product': 100},
        ),
      ),
      rules: PlannerRules(
        fallbackMarketPrices: const <String, double>{'Fallback Material': 10},
      ),
      marketTax: MarketTax(),
    );

    expect(quote.isAvailable, isFalse);
    expect(
      quote.unavailableReason,
      RecipeProfitabilityUnavailableReason.ingredientPriceUnavailable,
    );
    expect(quote.unavailableItemName, 'Fallback Material');
    expect(quote.directMarketItemNames, <String>{
      'Fallback Product',
      'Fallback Material',
    });
  });

  test('confirmed unlisted outputs and inputs are unavailable, not free', () {
    final product = _recipe(
      'Unlisted Product',
      ingredients: <Ingredient>[_ingredient('Unlisted Material', 1)],
    );
    final recipes = <String, Recipe>{
      product.name: product,
      'Unlisted Material': _leaf('Unlisted Material'),
    };

    final outputUnlisted = calculator.calculate(
      recipe: product,
      recipes: recipes,
      state: _state(
        market: MarketState(
          prices: const <String, double>{
            'Unlisted Product': 100,
            'Unlisted Material': 10,
          },
          unlistedItemNames: const <String>{'unlisted product'},
        ),
      ),
      rules: PlannerRules(),
      marketTax: MarketTax(),
    );
    expect(
      outputUnlisted.unavailableReason,
      RecipeProfitabilityUnavailableReason.outputUnlisted,
    );
    expect(outputUnlisted.unavailableItemName, 'Unlisted Product');

    final inputUnlisted = calculator.calculate(
      recipe: product,
      recipes: recipes,
      state: _state(
        market: MarketState(
          prices: const <String, double>{
            'Unlisted Product': 100,
            'Unlisted Material': 10,
          },
          unlistedItemNames: const <String>{'UNLISTED MATERIAL'},
        ),
      ),
      rules: PlannerRules(),
      marketTax: MarketTax(),
    );
    expect(
      inputUnlisted.unavailableReason,
      RecipeProfitabilityUnavailableReason.ingredientUnlisted,
    );
    expect(inputUnlisted.unavailableItemName, 'Unlisted Material');
  });

  test('missing and nonpositive output prices remain unavailable', () {
    final product = _recipe(
      'No Price Product',
      ingredients: <Ingredient>[_ingredient('Material', 1)],
    );
    final recipes = <String, Recipe>{
      product.name: product,
      'Material': _leaf('Material'),
    };
    for (final prices in <Map<String, double>>[
      const <String, double>{'Material': 1},
      const <String, double>{'No Price Product': 0, 'Material': 1},
    ]) {
      final quote = calculator.calculate(
        recipe: product,
        recipes: recipes,
        state: _state(market: MarketState(prices: prices)),
        rules: PlannerRules(),
        marketTax: MarketTax(),
      );
      expect(
        quote.unavailableReason,
        RecipeProfitabilityUnavailableReason.outputPriceUnavailable,
      );
    }
  });
}

ModeState _state({
  MarketState? market,
  Map<String, String> substituteChoices = const <String, String>{},
  Map<String, String> ingredientGrades = const <String, String>{},
  Map<String, String> recipeVariantChoices = const <String, String>{},
  int processingMastery = 0,
}) => ModeState(
  target: 'Product',
  bonusTarget: 'Product',
  substituteChoices: substituteChoices,
  ingredientGrades: ingredientGrades,
  recipeVariantChoices: recipeVariantChoices,
  processingMastery: processingMastery,
  market: market ?? MarketState(),
  appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
);

Recipe _recipe(
  String name, {
  String type = 'simple_alchemy',
  double baseOutput = 1,
  required List<Ingredient> ingredients,
  double? outputMinimum,
  double? outputMaximum,
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: baseOutput,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: outputMinimum,
  outputMaximum: outputMaximum,
  variants: variants,
  defaultVariantId: defaultVariantId,
);

Recipe _leaf(String name, {double npcPrice = 0}) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const <Ingredient>[],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: npcPrice,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

RecipeVariant _variant({
  required String id,
  required String label,
  required double baseOutput,
  required List<Ingredient> ingredients,
  int batchMultiplier = 1,
}) => RecipeVariant(
  id: id,
  label: label,
  routeId: 'route-a',
  batchMultiplier: batchMultiplier,
  type: 'simple_alchemy',
  baseOutput: baseOutput,
  method: null,
  ingredients: ingredients,
  outputMinimum: null,
  outputMaximum: null,
);
