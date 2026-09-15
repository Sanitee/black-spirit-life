import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/recipe_route_economics.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = 'Brimming Essence of Aether';
const _sharp = 'Sharp Black Crystal Shard';
const _npc = 'Oquilla Piece of the Old Moon';
const _common = 'Faint Essence of Aether';

void main() {
  test('20 Sharps and 2 NPC pieces use their full exchange ratio', () {
    final expensiveSharps = _resolve(price: 3_000_000);
    expect(expensiveSharps.selectedVariantId, 'npc');
    expect(expensiveSharps.isAutomatic, isTrue);
    expect(expensiveSharps.selectedOption!.purchaseCost, 50_000_000);
    expect(expensiveSharps.options.first.purchaseCost, 60_000_000);
    expect(expensiveSharps.hasCompleteComparison, isTrue);
    expect(_resolve(price: 2_000_000).selectedVariantId, 'sharp');
    expect(_resolve(price: 2_500_000).selectedVariantId, 'sharp');
  });

  test('NPC source is independent of phantom market price and stock', () {
    final result = _resolve(
      price: 3_000_000,
      additionalPrices: const {_npc: 1},
      additionalStock: const {_npc: 0},
    );
    expect(result.selectedOption!.unitPrice, 25_000_000);
    expect(result.selectedOption!.canCoverNeed, isTrue);
    expect(result.selectedOption!.stockKnown, isTrue);
  });

  test('unknown alternative price never becomes free or a proven saving', () {
    final result = _resolve();
    expect(result.selectedVariantId, 'npc');
    expect(result.options.first.purchaseCost, isNull);
    expect(result.hasCompleteComparison, isFalse);
    expect(result.selectedOption!.purchaseCost, 50_000_000);
  });

  test('required stock takes priority over a nominally cheaper route', () {
    expect(_resolve(price: 1_000_000, stock: 19).selectedVariantId, 'npc');
    expect(_resolve(price: 1_000_000, stock: 20).selectedVariantId, 'sharp');
    expect(_resolve(price: 1_000_000, stock: null).selectedVariantId, 'npc');
  });

  test(
    'manual route remains chosen while cheaper recommendation stays visible',
    () {
      final result = _resolve(price: 3_000_000, choice: 'SHARP');
      expect(result.selectedVariantId, 'sharp');
      expect(result.isAutomatic, isFalse);
      expect(result.automaticVariantId, 'npc');
      expect(result.selectedOption!.purchaseCost, 60_000_000);
      expect(result.recommendedOption!.purchaseCost, 50_000_000);
    },
  );

  test(
    'Auto and manual 10x keep the recorded batch and round required crafts',
    () {
      final result = _resolve(
        price: 3_000_000,
        choice: autoRecipeRouteChoice(10),
        output: 11,
      );
      expect(result.selectedVariantId, 'npc-10x');
      expect(result.selectedOption!.neededQuantity, 40);
      expect(result.selectedOption!.purchaseCost, 1_000_000_000);
      expect(result.selectedOption!.costPerOutput, 50_000_000);
      expect(result.options.first.neededQuantity, 400);
      final manual = _resolve(
        price: 3_000_000,
        choice: 'sharp-10x',
        output: 11,
      );
      expect(manual.selectedVariantId, 'sharp-10x');
      expect(manual.automaticVariantId, 'npc-10x');
    },
  );

  test('owned materials reduce buying cost and Ignore owned disables that', () {
    final inventory = <String, double>{_sharp: 19};
    final result = _resolve(price: 3_000_000, inventory: inventory, stock: 1);
    expect(result.selectedVariantId, 'sharp');
    expect(result.selectedOption!.ownedQuantity, 19);
    expect(result.selectedOption!.missingQuantity, 1);
    expect(result.selectedOption!.purchaseCost, 3_000_000);
    expect(
      _resolve(
        price: 3_000_000,
        inventory: inventory,
        ignoreOwned: true,
        stock: 1,
      ).selectedVariantId,
      'npc',
    );
    expect(
      _resolve(
        inventory: const {_sharp: 20},
        stock: 0,
      ).selectedOption!.purchaseCost,
      0,
    );
  });

  test('invalid old choices fall back to automatic comparison', () {
    final result = _resolve(price: 3_000_000, choice: 'removed-route');
    expect(result.selectedVariantId, 'npc');
    expect(result.isAutomatic, isTrue);
  });

  test(
    'different common quantity and probabilistic outputs are not comparable',
    () {
      for (final recipe in <Recipe>[
        _recipe(npcCommonQuantity: 2),
        _recipe(npcMaximum: 2),
      ]) {
        final result = _resolve(price: 3_000_000, recipe: recipe);
        expect(result.hasComparison, isFalse);
        expect(result.selectedVariantId, 'sharp');
      }
    },
  );

  test(
    'craftable exchanged inputs and routes without NPCs remain unchanged',
    () {
      final result = resolveRecipeRoute(
        recipe: _recipe(),
        recipes: {
          ..._recipes(),
          _npc: _leaf(_npc, ingredients: [_ingredient('Raw', 1)]),
        },
        state: PlannerState(target: _target, want: 1),
        rules: _rules(),
      );
      expect(result.hasComparison, isFalse);
      expect(
        _resolve(price: 3_000_000, rules: PlannerRules()).hasComparison,
        isFalse,
      );
    },
  );

  test(
    'engine compares net target demand and includes selected alternative leaf',
    () {
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.processing,
        recipes: _recipes(),
        state: PlannerState(
          target: _target,
          want: 10,
          ignoreTargetInventory: false,
          ignoreIngredientInventory: false,
          inventory: const {_target: 9, _sharp: 19},
          marketPrices: const {_sharp: 3_000_000},
          marketStock: const {_sharp: 1},
        ),
        rules: _rules(),
      );
      final route = result.routeSelections[_target]!;
      expect(route.selectedVariantId, 'sharp');
      expect(route.selectedOption!.missingQuantity, 1);
      expect(result.steps.single.count, 1);
      expect(
        result.missing.where((row) => row.name == _sharp).single.missing,
        1,
      );
      expect(result.missing.any((row) => row.name == _npc), isFalse);
    },
  );

  test(
    'reference-only input conversions still behave as noncraftable leaves',
    () {
      final recipes = _recipes();
      recipes[_sharp] = _leaf(
        _sharp,
        role: RecipeRole.manualConversion,
        ingredients: [_ingredient('Accessory', 1)],
      );
      final result = resolveRecipeRoute(
        recipe: recipes[_target]!,
        recipes: recipes,
        state: PlannerState(
          target: _target,
          want: 1,
          marketPrices: const {_sharp: 3_000_000},
          marketStock: const {_sharp: 100},
        ),
        rules: _rules(),
      );
      expect(result.hasComparison, isTrue);
      expect(result.selectedVariantId, 'npc');
    },
  );

  test(
    'engine reevaluates an intermediate route at its actual step demand',
    () {
      final recipes = _recipes();
      recipes['Final'] = _leaf('Final', ingredients: [_ingredient(_target, 5)]);
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.processing,
        recipes: recipes,
        state: PlannerState(
          target: 'Final',
          want: 1,
          marketPrices: const {_sharp: 1_000_000},
          marketStock: const {_sharp: 99},
        ),
        rules: _rules(),
      );
      expect(result.routeSelections[_target]!.selectedVariantId, 'npc');
      expect(
        result.routeSelections[_target]!.selectedOption!.neededQuantity,
        10,
      );
      expect(
        result.missing.where((row) => row.name == _npc).single.missing,
        10,
      );
      expect(result.missing.any((row) => row.name == _sharp), isFalse);
      expect(
        result.steps.where((step) => step.name == _target).single.count,
        5,
      );
    },
  );

  test(
    'recorded 10x formula retains its extra catalyst after automatic selection',
    () {
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.processing,
        recipes: _recipes(),
        state: PlannerState(
          target: _target,
          want: 10,
          recipeVariantChoices: {_target: autoRecipeRouteChoice(10)},
          marketPrices: const {_sharp: 3_000_000},
          marketStock: const {_sharp: 1000},
        ),
        rules: _rules(),
      );
      expect(result.steps.single.count, 1);
      expect(result.steps.single.produced, 10);
      expect(
        result.steps.single.ingredients.map((row) => '${row.name}:${row.need}'),
        containsAll(['$_npc:20.0', '$_common:10.0', 'Black Stone Powder:1.0']),
      );
    },
  );
}

RecipeRouteSelection _resolve({
  double? price,
  double? stock = 1000,
  String? choice,
  double? output,
  Map<String, double> inventory = const {},
  bool ignoreOwned = false,
  Recipe? recipe,
  PlannerRules? rules,
  Map<String, double> additionalPrices = const {},
  Map<String, double> additionalStock = const {},
}) {
  final recipes = _recipes(recipe: recipe);
  return resolveRecipeRoute(
    recipe: recipes[_target]!,
    recipes: recipes,
    state: PlannerState(
      target: _target,
      want: 1,
      ignoreIngredientInventory: ignoreOwned,
      inventory: inventory,
      recipeVariantChoices: {_target: ?choice},
      marketPrices: {_sharp: ?price, ...additionalPrices},
      marketStock: {_sharp: ?stock, ...additionalStock},
    ),
    rules: rules ?? _rules(),
    requestedOutput: output,
  );
}

PlannerRules _rules() => PlannerRules(
  vendorInfo: const {
    _npc: VendorSourceRule(vendor: 'Old Moon Manager', price: 25_000_000),
  },
);

Map<String, Recipe> _recipes({Recipe? recipe}) => {
  _target: recipe ?? _recipe(),
  _sharp: _leaf(_sharp),
  _npc: _leaf(_npc),
  _common: _leaf(_common),
  'Black Stone Powder': _leaf('Black Stone Powder'),
};

Recipe _recipe({double npcCommonQuantity = 1, double npcMaximum = 1}) {
  final variants = <RecipeVariant>[
    for (final npc in [false, true])
      for (final batch in [1, 10])
        RecipeVariant(
          id: '${npc ? 'npc' : 'sharp'}${batch == 10 ? '-10x' : ''}',
          label: npc ? 'Oquilla Pieces' : 'Sharp Shards',
          routeId: npc ? 'npc' : 'sharp',
          batchMultiplier: batch,
          type: 'processing',
          baseOutput: batch * 0.4,
          method: 'Simple Alchemy',
          ingredients: [
            _ingredient(npc ? _npc : _sharp, (npc ? 2 : 20) * batch.toDouble()),
            _ingredient(_common, (npc ? npcCommonQuantity : 1.0) * batch),
            if (batch == 10) _ingredient('Black Stone Powder', 1),
          ],
          outputMinimum: batch.toDouble(),
          outputMaximum: (npc ? npcMaximum : 1.0) * batch,
        ),
  ];
  return Recipe(
    name: _target,
    type: 'processing',
    baseOutput: 0.4,
    group: null,
    method: 'Simple Alchemy',
    ingredients: variants.first.ingredients,
    marketId: null,
    sourceNote: null,
    vendor: null,
    location: null,
    npcPrice: 0,
    qualityBase: null,
    qualityGrade: null,
    outputMinimum: 1,
    outputMaximum: 1,
    variants: variants,
    defaultVariantId: 'sharp',
  );
}

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const [],
  substituteGroup: null,
  substituteRatios: const {},
);

Recipe _leaf(
  String name, {
  List<Ingredient> ingredients = const [],
  RecipeRole role = RecipeRole.production,
}) => Recipe(
  name: name,
  type: ingredients.isEmpty ? 'gathered' : 'processing',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: name == _sharp ? '4997' : null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  role: role,
);
