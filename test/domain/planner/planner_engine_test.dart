import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = PlannerEngine();

  test('simple ceiling produces exact craft and missing quantities', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _simpleCatalog(),
      state: PlannerState(target: 'Target', want: 5),
    );

    expect(result.empty, isFalse);
    expect(result.steps, hasLength(1));
    expect(result.steps.single.name, 'Target');
    expect(result.steps.single.count, 3);
    expect(result.steps.single.produced, 6);
    expect(result.steps.single.demand, 5);
    expect(result.missing, hasLength(1));
    expect(result.missing.single.name, 'Raw');
    expect(result.missing.single.need, 9);
    expect(result.missing.single.missing, 9);
  });

  test('both inventory layers and both ignore switches remain independent', () {
    PlanResult build({
      required bool ignoreTarget,
      required bool ignoreIngredient,
    }) {
      return engine.buildPlan(
        mode: CraftMode.alchemy,
        recipes: _simpleCatalog(),
        state: PlannerState(
          target: 'Target',
          want: 5,
          inventory: const <String, double>{'Target': 1, 'Raw': 2},
          ignoreTargetInventory: ignoreTarget,
          ignoreIngredientInventory: ignoreIngredient,
        ),
      );
    }

    var result = build(ignoreTarget: false, ignoreIngredient: false);
    expect(result.steps.single.count, 2);
    expect(result.missing.single.missing, 4);

    result = build(ignoreTarget: true, ignoreIngredient: false);
    expect(result.steps.single.count, 3);
    expect(result.missing.single.missing, 7);

    result = build(ignoreTarget: false, ignoreIngredient: true);
    expect(result.steps.single.count, 2);
    expect(result.missing.single.missing, 6);

    result = build(ignoreTarget: true, ignoreIngredient: true);
    expect(result.steps.single.count, 3);
    expect(result.missing.single.missing, 9);
  });

  test('completed target and intermediate steps remove downstream work', () {
    final targetDone = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _simpleCatalog(),
      state: PlannerState(
        target: 'Target',
        want: 5,
        completedSteps: const <String>{'target'},
      ),
    );
    expect(targetDone.steps, isEmpty);
    expect(targetDone.missing, isEmpty);

    final intermediateDone = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[_ingredient('Middle', 2)]),
        'Middle': _recipe('Middle', <Ingredient>[_ingredient('Raw', 3)]),
        'Raw': _leaf('Raw'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        completedSteps: const <String>{'Middle'},
      ),
    );
    expect(intermediateDone.steps.map((step) => step.name), <String>['Target']);
    expect(intermediateDone.missing, isEmpty);
  });

  test(
    'recursive graph aggregates repeated demand and orders deepest first',
    () {
      final result = engine.buildPlan(
        mode: CraftMode.alchemy,
        recipes: <String, Recipe>{
          'Target': _recipe('Target', <Ingredient>[
            _ingredient('A', 1),
            _ingredient('B', 1),
          ]),
          'A': _recipe('A', <Ingredient>[_ingredient('C', 2)]),
          'B': _recipe('B', <Ingredient>[_ingredient('C', 3)]),
          'C': _recipe('C', <Ingredient>[_ingredient('Raw', 4)]),
          'Raw': _leaf('Raw'),
        },
        state: PlannerState(target: 'Target', want: 2),
      );

      expect(result.steps.map((step) => step.name), <String>[
        'C',
        'A',
        'B',
        'Target',
      ]);
      expect(result.firstWhereStep('C').count, 10);
      expect(result.missing.single.need, 40);
    },
  );

  test(
    'cycle guard terminates deterministically with current recompute semantics',
    () {
      final recipes = <String, Recipe>{
        'A': _recipe('A', <Ingredient>[_ingredient('B', 1)]),
        'B': _recipe('B', <Ingredient>[_ingredient('A', 1)]),
      };
      final state = PlannerState(target: 'A', want: 1);
      final first = engine.buildPlan(
        mode: CraftMode.alchemy,
        recipes: recipes,
        state: state,
      );
      final second = engine.buildPlan(
        mode: CraftMode.alchemy,
        recipes: recipes,
        state: state,
      );

      expect(first.toJson(), second.toJson());
      expect(first.steps.map((step) => step.name), <String>['A', 'B']);
      expect(first.firstWhereStep('A').count, 2);
      expect(first.firstWhereStep('B').count, 1);
      expect(first.missing, isEmpty);
    },
  );

  test(
    'processing mass batches are reported without changing craft demand',
    () {
      final result = engine.buildPlan(
        mode: CraftMode.processing,
        recipes: <String, Recipe>{
          'Flour': _recipe(
            'Flour',
            <Ingredient>[_ingredient('Wheat', 1)],
            type: 'processing',
            method: 'Grinding',
            outputMinimum: 1,
            outputMaximum: 1,
          ),
          'Wheat': _leaf('Wheat'),
        },
        state: PlannerState(
          target: 'Flour',
          want: 100,
          processingMastery: 2,
          useMassProcessing: true,
        ),
      );

      expect(result.steps.single.count, 100);
      expect(result.steps.single.batchSize, 10);
      expect(result.steps.single.batchCount, 10);
      expect(result.missing.single.need, 100);
    },
  );

  test('recorded processing output determines the plan', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Fixed Result': _recipe(
          'Fixed Result',
          <Ingredient>[_ingredient('Raw', 1)],
          type: 'processing',
          outputMinimum: 2,
          outputMaximum: 2,
        ),
        'Raw': _leaf('Raw'),
      },
      state: PlannerState(target: 'Fixed Result', want: 10),
    );

    expect(result.steps.single.count, 5);
    expect(result.missing.single.need, 5);
  });

  test('blue quality converts demand and accepts legacy mixed-case grades', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[_ingredient('Base', 10)]),
        'Base': _leaf('Base'),
        'Blue Base': _leaf('Blue Base'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        ingredientGrades: const <String, String>{'BASE': ' BLUE '},
      ),
      rules: PlannerRules(
        blueElixirMap: const <String, String>{'base': 'Blue Base'},
      ),
    );

    expect(result.steps.single.ingredients.single.grade, 'blue');
    expect(result.steps.single.ingredients.single.name, 'Blue Base');
    expect(result.missing.single.name, 'Blue Base');
    expect(result.missing.single.need, 4);
  });

  test('processing suppresses quality conversion in the calculation', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[
          _ingredient('Base', 10),
        ], type: 'processing'),
        'Base': _leaf('Base'),
        'Blue Base': _leaf('Blue Base'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        ingredientGrades: const <String, String>{'recipe:Target:Base': 'blue'},
      ),
      rules: PlannerRules(
        blueElixirMap: const <String, String>{'Base': 'Blue Base'},
      ),
    );

    expect(result.steps.single.ingredients.single.grade, 'normal');
    expect(result.steps.single.ingredients.single.name, 'Base');
    expect(result.missing.single.name, 'Base');
    expect(result.missing.single.need, 10);
  });

  test('substitute pricing prefers an option that covers the full demand', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[
          _substituteIngredient('Cheap but scarce', 10, const <String>[
            'Cheap but scarce',
            'Fully stocked',
          ]),
        ], type: 'processing'),
        'Cheap but scarce': _leaf('Cheap but scarce'),
        'Fully stocked': _leaf('Fully stocked'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        marketPrices: const <String, double>{
          'Cheap but scarce': 1,
          'Fully stocked': 3,
        },
        marketStock: const <String, double>{
          'Cheap but scarce': 2,
          'Fully stocked': 10,
        },
      ),
      rules: PlannerRules(
        marketIds: const <String, String>{
          'Cheap but scarce': '1',
          'Fully stocked': '2',
        },
      ),
    );

    expect(
      result.firstWhereStep('Target').ingredients.single.name,
      'Fully stocked',
    );
  });

  test(
    'substitute pricing still chooses the cheapest fully stocked option',
    () {
      final result = engine.buildPlan(
        mode: CraftMode.processing,
        recipes: <String, Recipe>{
          'Target': _recipe('Target', <Ingredient>[
            _substituteIngredient('Cheapest', 10, const <String>[
              'Cheapest',
              'Costlier',
            ]),
          ], type: 'processing'),
          'Cheapest': _leaf('Cheapest'),
          'Costlier': _leaf('Costlier'),
        },
        state: PlannerState(
          target: 'Target',
          want: 1,
          marketPrices: const <String, double>{'Cheapest': 2, 'Costlier': 3},
          marketStock: const <String, double>{'Cheapest': 10, 'Costlier': 100},
        ),
        rules: PlannerRules(
          marketIds: const <String, String>{'Cheapest': '1', 'Costlier': '2'},
        ),
      );

      expect(
        result.firstWhereStep('Target').ingredients.single.name,
        'Cheapest',
      );
    },
  );

  test('substitute stock coverage uses the quantity still missing', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[
          _substituteIngredient('Mostly owned', 10, const <String>[
            'Mostly owned',
            'Fully stocked',
          ]),
        ], type: 'processing'),
        'Mostly owned': _leaf('Mostly owned'),
        'Fully stocked': _leaf('Fully stocked'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        ignoreIngredientInventory: false,
        inventory: const <String, double>{'Mostly owned': 8},
        marketPrices: const <String, double>{
          'Mostly owned': 1,
          'Fully stocked': 2,
        },
        marketStock: const <String, double>{
          'Mostly owned': 2,
          'Fully stocked': 10,
        },
      ),
      rules: PlannerRules(
        marketIds: const <String, String>{
          'Mostly owned': '1',
          'Fully stocked': '2',
        },
      ),
    );

    expect(
      result.firstWhereStep('Target').ingredients.single.name,
      'Mostly owned',
    );
  });

  test('ignored inventory does not make an understocked substitute look '
      'covered', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[
          _substituteIngredient('Ignored inventory', 10, const <String>[
            'Ignored inventory',
            'Fully stocked',
          ]),
        ], type: 'processing'),
        'Ignored inventory': _leaf('Ignored inventory'),
        'Fully stocked': _leaf('Fully stocked'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        ignoreIngredientInventory: true,
        inventory: const <String, double>{'Ignored inventory': 8},
        marketPrices: const <String, double>{
          'Ignored inventory': 1,
          'Fully stocked': 2,
        },
        marketStock: const <String, double>{
          'Ignored inventory': 2,
          'Fully stocked': 10,
        },
      ),
      rules: PlannerRules(
        marketIds: const <String, String>{
          'Ignored inventory': '1',
          'Fully stocked': '2',
        },
      ),
    );

    expect(
      result.firstWhereStep('Target').ingredients.single.name,
      'Fully stocked',
    );
  });

  test('substitute pricing chooses the greatest coverage when all stock is '
      'partial', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[
          _substituteIngredient('Cheaper partial', 10, const <String>[
            'Cheaper partial',
            'Better supplied',
          ]),
        ], type: 'processing'),
        'Cheaper partial': _leaf('Cheaper partial'),
        'Better supplied': _leaf('Better supplied'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        marketPrices: const <String, double>{
          'Cheaper partial': 1,
          'Better supplied': 3,
        },
        marketStock: const <String, double>{
          'Cheaper partial': 4,
          'Better supplied': 8,
        },
      ),
      rules: PlannerRules(
        marketIds: const <String, String>{
          'Cheaper partial': '1',
          'Better supplied': '2',
        },
      ),
    );

    expect(
      result.firstWhereStep('Target').ingredients.single.name,
      'Better supplied',
    );
  });

  test('an explicit saved substitute still wins over market automation', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: <String, Recipe>{
        'Target': _recipe('Target', <Ingredient>[
          _substituteIngredient('Automatic choice', 1, const <String>[
            'Automatic choice',
            'Saved choice',
          ]),
        ], type: 'processing'),
        'Automatic choice': _leaf('Automatic choice'),
        'Saved choice': _leaf('Saved choice'),
      },
      state: PlannerState(
        target: 'Target',
        want: 1,
        substituteChoices: const <String, String>{
          'recipe:Target:test:Automatic choice': 'Saved choice',
        },
        marketPrices: const <String, double>{
          'Automatic choice': 1,
          'Saved choice': 100,
        },
        marketStock: const <String, double>{
          'Automatic choice': 100,
          'Saved choice': 100,
        },
      ),
      rules: PlannerRules(
        marketIds: const <String, String>{
          'Automatic choice': '1',
          'Saved choice': '2',
        },
      ),
    );

    expect(
      result.firstWhereStep('Target').ingredients.single.name,
      'Saved choice',
    );
  });

  test('saved recipe variant switches the complete correlated formula', () {
    final target = Recipe(
      name: 'Target',
      type: 'simple_alchemy',
      baseOutput: 1,
      group: null,
      method: 'Simple Alchemy',
      ingredients: <Ingredient>[_ingredient('Route A Raw', 2)],
      marketId: null,
      sourceNote: null,
      vendor: null,
      location: null,
      npcPrice: 0,
      qualityBase: null,
      qualityGrade: null,
      outputMinimum: 1,
      outputMaximum: 1,
      variants: <RecipeVariant>[
        RecipeVariant(
          id: 'route-a',
          label: 'Route A',
          type: 'simple_alchemy',
          baseOutput: 1,
          method: 'Simple Alchemy',
          ingredients: <Ingredient>[_ingredient('Route A Raw', 2)],
          outputMinimum: 1,
          outputMaximum: 1,
        ),
        RecipeVariant(
          id: 'route-b',
          label: 'Route B',
          type: 'simple_alchemy',
          baseOutput: 1,
          method: 'Simple Alchemy',
          ingredients: <Ingredient>[
            _ingredient('Route B Raw', 3),
            _ingredient('Route B Catalyst', 1),
          ],
          outputMinimum: 1,
          outputMaximum: 1,
        ),
      ],
      defaultVariantId: 'route-a',
    );
    final recipes = <String, Recipe>{
      'Target': target,
      'Route A Raw': _leaf('Route A Raw'),
      'Route B Raw': _leaf('Route B Raw'),
      'Route B Catalyst': _leaf('Route B Catalyst'),
    };

    final selected = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: recipes,
      state: PlannerState(
        target: 'Target',
        want: 2,
        recipeVariantChoices: const <String, String>{'target': 'ROUTE-B'},
      ),
    );
    expect(
      selected.steps.single.ingredients.map((ingredient) => ingredient.name),
      <String>['Route B Raw', 'Route B Catalyst'],
    );
    expect(
      selected.missing.map((material) => '${material.name}:${material.need}'),
      containsAll(<String>['Route B Raw:6.0', 'Route B Catalyst:2.0']),
    );

    final invalidFallsBack = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: recipes,
      state: PlannerState(
        target: 'Target',
        want: 2,
        recipeVariantChoices: const <String, String>{'Target': 'removed-route'},
      ),
    );
    expect(
      invalidFallsBack.steps.single.ingredients.single.name,
      'Route A Raw',
    );
  });

  test(
    'fixed processing batch formula is not multiplied by mastery batching',
    () {
      final target = Recipe(
        name: 'Batch Target',
        type: 'processing',
        baseOutput: 0.4,
        group: null,
        method: 'Simple Alchemy',
        ingredients: <Ingredient>[_ingredient('Raw Material', 10)],
        marketId: null,
        sourceNote: null,
        vendor: null,
        location: null,
        npcPrice: 0,
        qualityBase: null,
        qualityGrade: null,
        outputMinimum: 1,
        outputMaximum: 1,
        variants: <RecipeVariant>[
          RecipeVariant(
            id: 'standard',
            label: 'Standard',
            routeId: 'standard',
            type: 'processing',
            baseOutput: 0.4,
            method: 'Simple Alchemy',
            ingredients: <Ingredient>[_ingredient('Raw Material', 10)],
            outputMinimum: 1,
            outputMaximum: 1,
          ),
          RecipeVariant(
            id: 'standard-10x',
            label: 'Standard',
            routeId: 'standard',
            batchMultiplier: 10,
            type: 'processing',
            baseOutput: 4,
            method: 'Simple Alchemy',
            ingredients: <Ingredient>[
              _ingredient('Raw Material', 100),
              _ingredient('Batch Catalyst', 1),
            ],
            outputMinimum: 10,
            outputMaximum: 10,
          ),
        ],
        defaultVariantId: 'standard',
      );
      final result = engine.buildPlan(
        mode: CraftMode.processing,
        recipes: <String, Recipe>{
          'Batch Target': target,
          'Raw Material': _leaf('Raw Material'),
          'Batch Catalyst': _leaf('Batch Catalyst'),
        },
        state: PlannerState(
          target: 'Batch Target',
          want: 10,
          processingMastery: 2000,
          useMassProcessing: true,
          recipeVariantChoices: const <String, String>{
            'Batch Target': 'standard-10x',
          },
        ),
      );

      final step = result.firstWhereStep('Batch Target');
      expect(step.count, 1);
      expect(
        step.ingredients.map(
          (ingredient) => '${ingredient.name}:${ingredient.need}',
        ),
        <String>['Raw Material:100.0', 'Batch Catalyst:1.0'],
      );
      expect(
        result.missing.map((material) => '${material.name}:${material.need}'),
        containsAll(<String>['Raw Material:100.0', 'Batch Catalyst:1.0']),
      );
    },
  );

  test('zero request remains a valid nonempty plan result with no rows', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _simpleCatalog(),
      state: PlannerState(target: 'Target', want: 0),
    );
    expect(result.empty, isFalse);
    expect(result.steps, isEmpty);
    expect(result.missing, isEmpty);
  });

  test('vendorInfo NPC fallback wins over market pricing for missing rows', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _simpleCatalog(),
      state: PlannerState(
        target: 'Target',
        want: 5,
        marketPrices: const <String, double>{'Raw': 9999},
        marketStock: const <String, double>{'Raw': 1},
      ),
      rules: PlannerRules(
        marketIds: const <String, String>{'Raw': '101'},
        vendorInfo: const <String, VendorSourceRule>{
          'Raw': VendorSourceRule(
            vendor: 'Material Vendor',
            role: 'Material Vendor',
            location: 'Calpheon',
            price: 700,
          ),
        },
      ),
    );

    final market = result.missing.single.market;
    expect(market.status, 'vendor');
    expect(market.marketable, isFalse);
    expect(market.price, 700);
    expect(market.buyable, 9);
    expect(market.total, 6300);
    expect(market.hasSourceInfo, isTrue);
  });

  test('unknown market stock estimates the full missing quantity', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _simpleCatalog(),
      state: PlannerState(
        target: 'Target',
        want: 5,
        marketPrices: const <String, double>{'Raw': 100},
      ),
      rules: PlannerRules(marketIds: const <String, String>{'Raw': '101'}),
    );

    final market = result.missing.single.market;
    expect(market.status, 'priced');
    expect(market.stockKnown, isFalse);
    expect(market.buyable, 0);
    expect(market.total, 900);
  });
}

extension on PlanResult {
  PlanStep firstWhereStep(String name) =>
      steps.firstWhere((step) => step.name == name);
}

Map<String, Recipe> _simpleCatalog() => <String, Recipe>{
  'Target': _recipe('Target', <Ingredient>[
    _ingredient('Raw', 3),
  ], baseOutput: 2),
  'Raw': _leaf('Raw'),
};

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

Ingredient _substituteIngredient(
  String name,
  double quantity,
  List<String> options,
) => Ingredient(
  name: name,
  quantity: quantity,
  options: options,
  substituteGroup: 'test:$name',
  substituteRatios: <String, double>{for (final option in options) option: 1},
);

Recipe _leaf(String name) => _recipe(name, const <Ingredient>[]);

Recipe _recipe(
  String name,
  List<Ingredient> ingredients, {
  String type = 'simple_alchemy',
  double baseOutput = 1,
  String? method,
  double? outputMinimum,
  double? outputMaximum,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: baseOutput,
  group: null,
  method: method,
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
);
