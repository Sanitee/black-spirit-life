import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final oracle =
      jsonDecode(
            File(
              'test/fixtures/planner/avalonia-oracle.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final scenarios = (oracle['scenarios']! as List).cast<Map<String, Object?>>();
  final expectedByName = <String, Map<String, Object?>>{
    for (final scenario in scenarios)
      scenario['name']! as String: scenario['result']! as Map<String, Object?>,
  };
  const engine = PlannerEngine();

  test('matches protected Avalonia nested inventory oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _chainItems,
      state: PlannerState(
        target: 'Final Elixir',
        want: 10,
        ignoreIngredientInventory: false,
        inventory: const {'Silver Azalea': 10, 'Rough Stone': 5},
      ),
    );
    expect(result.toJson(), expectedByName['nested_inventory']);
  });

  test('matches protected Avalonia substitute-ratio oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _substitutionItems,
      state: PlannerState(
        target: 'Choice Tonic',
        want: 4,
        substituteChoices: const {
          'recipe:Choice Tonic:Herb group': 'Sunrise Herb',
        },
      ),
    );
    expect(result.toJson(), expectedByName['substitute_ratio']);
  });

  test('matches protected Avalonia ingredient-quality oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.cooking,
      recipes: _qualityItems,
      state: PlannerState(
        target: 'Meal',
        want: 8,
        ingredientGrades: const {'recipe:Meal:Wheat': 'high'},
      ),
      rules: PlannerRules(
        qualityIngredients: const {'Wheat'},
        qualityConversions: const {
          'Wheat': QualityConversionRule(
            high: QualityTierRule(name: 'High-Quality Wheat', ratio: 3),
            special: QualityTierRule(name: 'Special Wheat', ratio: 5),
          ),
        },
      ),
    );
    expect(result.toJson(), expectedByName['quality_high']);
  });

  test('matches protected Avalonia processing mass oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.processing,
      recipes: _processingItems,
      state: PlannerState(
        target: 'Wheat Flour',
        want: 1000,
        processingMastery: 680,
        useMassProcessing: true,
      ),
    );
    expect(result.toJson(), expectedByName['processing_mass']);
  });

  test('matches protected Avalonia completed dependency oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _chainItems,
      state: PlannerState(
        target: 'Final Elixir',
        want: 10,
        completedSteps: const {'Reagent'},
      ),
    );
    expect(result.toJson(), expectedByName['completed_dependency']);
  });

  test('matches protected Avalonia cycle-guard oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _cycleItems,
      state: PlannerState(target: 'A', want: 1),
    );
    expect(result.toJson(), expectedByName['cycle_guard']);
  });

  test('matches protected Avalonia market-material oracle', () {
    final result = engine.buildPlan(
      mode: CraftMode.alchemy,
      recipes: _chainItems,
      state: PlannerState(
        target: 'Final Elixir',
        want: 3,
        marketPrices: const {'Silver Azalea': 1200},
        marketStock: const {'Silver Azalea': 5},
      ),
      rules: PlannerRules(
        marketIds: const {'Silver Azalea': '1001'},
        fallbackMarketPrices: const {'Rough Stone': 250},
      ),
    );
    expect(result.toJson(), expectedByName['market_materials']);
  });

  test('matches protected Avalonia mass-processing scalar boundaries', () {
    final scalarChecks = oracle['scalarChecks']! as Map<String, Object?>;
    final expected = scalarChecks['massProcessing']! as Map<String, Object?>;
    expect({
      for (final mastery in [0, 2, 679, 680, 3000, 9000])
        '$mastery': massProcessingBatchSize(mastery),
    }, expected);
  });
}

Recipe _recipe(
  String name,
  String type,
  double baseOutput,
  List<Ingredient> ingredients, {
  String? method,
  double outputMinimum = 1,
  double outputMaximum = 1,
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

Ingredient _ingredient(
  String name,
  double quantity, {
  List<String> options = const [],
  String? group,
  Map<String, double> ratios = const {},
}) => Ingredient(
  name: name,
  quantity: quantity,
  options: options,
  substituteGroup: group,
  substituteRatios: ratios,
);

final Map<String, Recipe> _chainItems = {
  'Final Elixir': _recipe('Final Elixir', 'alchemy', 1, [
    _ingredient('Reagent', 2),
    _ingredient('Silver Azalea', 3),
  ]),
  'Reagent': _recipe('Reagent', 'alchemy', 1, [_ingredient('Rough Stone', 4)]),
  'Silver Azalea': _recipe('Silver Azalea', 'gathered', 1, []),
  'Rough Stone': _recipe('Rough Stone', 'gathered', 1, []),
};

final Map<String, Recipe> _substitutionItems = {
  'Choice Tonic': _recipe('Choice Tonic', 'alchemy', 1, [
    _ingredient(
      'Wild Plant',
      5,
      options: ['Wild Plant', 'Sunrise Herb'],
      group: 'Herb group',
      ratios: const {'Sunrise Herb': 2},
    ),
  ]),
  'Wild Plant': _recipe('Wild Plant', 'gathered', 1, []),
  'Sunrise Herb': _recipe('Sunrise Herb', 'gathered', 1, []),
};

final Map<String, Recipe> _qualityItems = {
  'Meal': _recipe('Meal', 'cooking', 1, [_ingredient('Wheat', 6)]),
  'Wheat': _recipe('Wheat', 'gathered', 1, []),
  'High-Quality Wheat': _recipe('High-Quality Wheat', 'gathered', 1, []),
  'Special Wheat': _recipe('Special Wheat', 'gathered', 1, []),
};

final Map<String, Recipe> _processingItems = {
  'Wheat Flour': _recipe(
    'Wheat Flour',
    'processing',
    1,
    [_ingredient('Wheat', 1)],
    method: 'Grinding',
    outputMinimum: 1,
    outputMaximum: 4,
  ),
  'Wheat': _recipe('Wheat', 'gathered', 1, []),
};

final Map<String, Recipe> _cycleItems = {
  'A': _recipe('A', 'alchemy', 1, [_ingredient('B', 1)]),
  'B': _recipe('B', 'alchemy', 1, [_ingredient('A', 1)]),
};
