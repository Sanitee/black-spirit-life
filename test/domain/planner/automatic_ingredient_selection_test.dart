import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart'
    as stored;
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlanResult fruit({
    Map<String, double> stock = const {},
    Map<String, double> prices = const {},
    Map<String, double> owned = const {},
    bool ignoreOwned = false,
    Map<String, String> grades = const {},
    String type = 'simple_alchemy',
  }) => const PlannerEngine().buildPlan(
    mode: CraftMode.cooking,
    recipes: {
      'Target': _recipe('Target', [_ingredient('Fruit', 5)], type: type),
      for (final name in ['Fruit', 'High-Quality Fruit', 'Special Fruit'])
        name: _recipe(name, []),
    },
    state: PlannerState(
      target: 'Target',
      want: 10,
      inventory: owned,
      ignoreIngredientInventory: ignoreOwned,
      marketPrices: prices,
      marketStock: stock,
      ingredientGrades: grades,
    ),
    rules: PlannerRules(
      qualityIngredients: {'Fruit'},
      marketIds: {
        'Fruit': '1',
        'High-Quality Fruit': '2',
        'Special Fruit': '3',
      },
    ),
  );

  test(
    'available higher quality beats zero stock, even with partial supply',
    () {
      final result = fruit(
        stock: {'Fruit': 0, 'High-Quality Fruit': 0, 'Special Fruit': 1},
        prices: {'Fruit': 1, 'High-Quality Fruit': 2, 'Special Fruit': 30},
      );
      final row = result.steps.single.ingredients.single;
      expect(row.name, 'Special Fruit');
      expect(row.grade, 'special');
      expect(row.need, 10);
      expect(result.missing.single.name, row.name);
      expect(result.missing.single.need, row.need);
      expect(result.missing.single.market.status, 'partial');
    },
  );

  test('quality price comparison uses required amount, not unit price', () {
    final result = fruit(
      stock: {'Fruit': 100, 'Special Fruit': 100},
      prices: {'Fruit': 10, 'Special Fruit': 30},
    );
    expect(result.missing.single.name, 'Special Fruit');
    expect(result.missing.single.market.total, 300);
  });

  test('fully owned wins and partial ownership reduces the investment', () {
    const stock = {'Fruit': 100.0, 'Special Fruit': 100.0};
    const prices = {'Fruit': 10.0, 'Special Fruit': 30.0};
    final covered = fruit(
      stock: stock,
      prices: prices,
      owned: {'Special Fruit': 10},
    );
    expect(covered.steps.single.ingredients.single.name, 'Special Fruit');
    expect(covered.missing, isEmpty);
    final partial = fruit(stock: stock, prices: prices, owned: {'Fruit': 49});
    expect(partial.missing.single.name, 'Fruit');
    expect(partial.missing.single.market.total, 10);
    expect(
      fruit(
        stock: stock,
        prices: prices,
        owned: {'Fruit': 49},
        ignoreOwned: true,
      ).missing.single.name,
      'Special Fruit',
    );
  });

  test(
    'unknown prices are not free and unknown stock does not beat confirmed stock',
    () {
      expect(
        fruit(
          stock: {'Fruit': 0, 'Special Fruit': 1},
          prices: {'Fruit': 1, 'High-Quality Fruit': 1, 'Special Fruit': 30},
        ).missing.single.name,
        'Special Fruit',
      );
      expect(
        fruit(
          stock: {'Fruit': 1, 'Special Fruit': 100},
          prices: {'Fruit': 10},
        ).missing.single.name,
        'Fruit',
      );
    },
  );

  test('all unavailable stays deterministic and honestly out of stock', () {
    final result = fruit(
      stock: {'Fruit': 0, 'High-Quality Fruit': 0, 'Special Fruit': 0},
      prices: {'Fruit': 10, 'High-Quality Fruit': 100, 'Special Fruit': 200},
    );
    expect(result.missing.single.name, 'Fruit');
    expect(result.missing.single.market.stock, 0);
    expect(result.missing.single.market.status, 'none');
  });

  test('manual quality stays even when confirmed empty', () {
    const grades = {'recipe:Target:Fruit': 'normal'};
    const prices = {'Fruit': 10.0, 'Special Fruit': 1.0};
    expect(
      fruit(
        stock: {'Fruit': 1, 'Special Fruit': 100},
        prices: prices,
        grades: grades,
      ).steps.single.ingredients.single.name,
      'Fruit',
    );
    expect(
      fruit(
        stock: {'Fruit': 0, 'Special Fruit': 100},
        prices: prices,
        grades: grades,
      ).steps.single.ingredients.single.name,
      'Fruit',
    );
    expect(
      fruit(
        stock: {'Fruit': 0, 'Special Fruit': 100},
        prices: prices,
        grades: grades,
        owned: {'Fruit': 50},
      ).steps.single.ingredients.single.name,
      'Fruit',
    );
    expect(
      fruit(
        stock: {'Special Fruit': 100},
        prices: prices,
        grades: grades,
      ).steps.single.ingredients.single.name,
      'Fruit',
      reason: 'Unknown stock is not confirmed unavailable.',
    );
  });

  test('Processing does not inherit residence quality substitutions', () {
    final result = fruit(
      type: 'processing',
      stock: {'Fruit': 0, 'Special Fruit': 100},
      prices: {'Fruit': 10, 'Special Fruit': 1},
    );
    expect(result.missing.single.name, 'Fruit');
  });

  test(
    'explicit Auto resumes availability selection and masks legacy grade',
    () {
      expect(
        fruit(
          stock: {'Fruit': 0, 'Special Fruit': 20},
          prices: {'Fruit': 1, 'Special Fruit': 10},
          grades: {'Fruit': 'normal', 'recipe:Target:Fruit': 'auto'},
        ).missing.single.name,
        'Special Fruit',
      );
    },
  );

  test(
    'batch choice includes dependencies absent from the one-craft choice',
    () {
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.cooking,
        recipes: {
          'Target': _recipe('Target', [
            _ingredient('A', 1, ['A', 'B']),
          ]),
          'A': _recipe('A', [_ingredient('Raw A', 2)]),
          'B': _recipe('B', [_ingredient('Raw B', 2)]),
          'Raw A': _recipe('Raw A', []),
          'Raw B': _recipe('Raw B', []),
        },
        state: PlannerState(
          target: 'Target',
          want: 10,
          ignoreIngredientInventory: false,
          inventory: {'A': 1},
          marketPrices: {'A': 10, 'B': 1},
          marketStock: {'A': 100, 'B': 100},
        ),
        rules: PlannerRules(marketIds: {'A': '1', 'B': '2'}),
      );
      expect(result.steps.map((s) => s.name), contains('B'));
      expect(result.steps.map((s) => s.name), isNot(contains('A')));
      expect(result.missing.single.name, 'Raw B');
      expect(result.missing.single.need, 20);
    },
  );

  test(
    'shared owned amounts are not promised independently to two recipes',
    () {
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.cooking,
        recipes: {
          'Target': _recipe('Target', [
            _ingredient('A', 1),
            _ingredient('B', 1),
          ]),
          for (final name in ['A', 'B'])
            name: _recipe(name, [
              _ingredient('Raw A', 10, ['Raw A', 'Raw B']),
            ]),
          'Raw A': _recipe('Raw A', []),
          'Raw B': _recipe('Raw B', []),
        },
        state: PlannerState(
          target: 'Target',
          want: 1,
          ignoreIngredientInventory: false,
          inventory: {'Raw A': 10},
          marketPrices: {'Raw A': 10, 'Raw B': 8},
          marketStock: {'Raw A': 100, 'Raw B': 100},
        ),
        rules: PlannerRules(marketIds: {'Raw A': '1', 'Raw B': '2'}),
      );
      expect(result.missing.single.name, 'Raw B');
      expect(result.missing.single.need, 10);
      final selected = result.steps
          .where((s) => s.name != 'Target')
          .expand((s) => s.ingredients)
          .map((i) => i.name)
          .toList();
      expect(selected, containsAll(['Raw A', 'Raw B']));
    },
  );

  test(
    'real Balacs Lunchbox checks all Citron tiers and selects stocked Special',
    () async {
      final catalog = const BundledCatalogParser().parse(
        await File('assets/data/app-data.json').readAsString(),
      );
      final controller = PlannerApplicationController(
        catalog: catalog,
        initialState: stored.PlannerState(
          applicationVersion: 'test',
          lastSuccessfulWriteUtc: DateTime.utc(2026),
          activeMode: CraftMode.cooking,
          processingYields: const {},
          marketTax: stored.MarketTax(),
          alchemy: _mode(),
          processing: _mode(),
          cooking: stored.ModeState(
            bonusTarget: '',
            appearance: stored.AppearanceSettings.defaultsFor(
              CraftMode.cooking,
            ),
            target: 'Balacs Lunchbox',
            want: 100,
            ignoreIngredientInventory: false,
            market: stored.MarketState(
              prices: {
                'Citron': 3170,
                'High-Quality Citron': 10000,
                'Special Citron': 20000,
              },
              stock: {
                'Citron': 0,
                'High-Quality Citron': 0,
                'Special Citron': 100,
              },
            ),
          ),
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      final plan = controller.active.plan.value;
      final citrons = plan.steps
          .expand((s) => s.ingredients)
          .where((i) => i.original == 'Citron')
          .toList();
      expect(citrons.length, greaterThanOrEqualTo(2));
      expect(citrons.every((i) => i.name == 'Special Citron'), isTrue);
      expect(plan.missing.any((i) => i.name == 'Citron'), isFalse);
      expect(
        plan.missing.singleWhere((i) => i.name == 'Special Citron').need,
        citrons.fold<double>(0, (sum, i) => sum + i.need),
      );
      for (final step in plan.steps) {
        for (final ingredient in step.ingredients.where(
          (i) => i.original == 'Citron',
        )) {
          // Each of these formulas needs at least one Special Citron per craft,
          // not a fraction pooled across the complete batch.
          expect(ingredient.need, step.count);
        }
      }
      final checked = controller.active.recipeRouteMarketNamesForPlan(plan);
      expect(
        checked,
        containsAll(['Citron', 'High-Quality Citron', 'Special Citron']),
      );
      expect(
        controller.active.state.value.ingredientGrades,
        isEmpty,
        reason: 'Automatic choices must not become saved manual overrides.',
      );
      final citronInputs = plan.steps
          .expand((s) => s.ingredients)
          .where((i) => i.name == 'Special Citron')
          .toList();
      expect(citronInputs.length, greaterThan(1));
      controller.active.selectNeededIngredientGrade(citronInputs, 'normal');
      expect(
        controller.active.plan.value.steps
            .expand((s) => s.ingredients)
            .where((i) => i.original == 'Citron')
            .every((i) => i.name == 'Citron'),
        isTrue,
      );
      expect(
        controller.active.plan.value.missing
            .singleWhere((i) => i.name == 'Citron')
            .market
            .stock,
        0,
      );
      controller.active.selectNeededIngredientGrade(
        controller.active.plan.value.steps
            .expand((s) => s.ingredients)
            .where((i) => i.original == 'Citron'),
        'auto',
      );
      expect(
        controller.active.plan.value.steps
            .expand((s) => s.ingredients)
            .where((i) => i.original == 'Citron')
            .every((i) => i.name == 'Special Citron'),
        isTrue,
      );
      controller.active.updateState(
        (s) => s.copyWith(
          market: s.market.copyWith(
            stock: {
              'Citron': 10000,
              'High-Quality Citron': 0,
              'Special Citron': 0,
            },
          ),
        ),
      );
      expect(
        controller.active.plan.value.steps
            .expand((s) => s.ingredients)
            .where((i) => i.original == 'Citron')
            .every((i) => i.name == 'Citron'),
        isTrue,
      );
    },
  );
}

stored.ModeState _mode() => stored.ModeState(
  target: '',
  bonusTarget: '',
  market: stored.MarketState(),
  appearance: stored.AppearanceSettings.defaultsFor(CraftMode.cooking),
);

Ingredient _ingredient(
  String name,
  double quantity, [
  List<String> options = const [],
]) => Ingredient(
  name: name,
  quantity: quantity,
  options: options,
  substituteGroup: null,
  substituteRatios: const {},
);

Recipe _recipe(
  String name,
  List<Ingredient> ingredients, {
  String type = 'simple_alchemy',
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
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
  outputMinimum: 1,
  outputMaximum: 1,
);
