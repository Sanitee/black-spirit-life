import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recipe route and batch matrix', () {
    test('keeps route and batch as independent declared axes', () {
      final recipe = _matrixRecipe();

      expect(recipe.variantRoutes.map((route) => route.id), <String>[
        'route-a',
        'route-b',
      ]);
      expect(recipe.variantRoutes.map((route) => route.label), <String>[
        'Raw Materials',
        'Prepared Stone',
      ]);
      expect(recipe.variantBatchMultipliers, <int>[1, 10, 100]);
      expect(recipe.hasRecipeRouteChoices, isTrue);
      expect(recipe.hasRecipeBatchChoices, isTrue);
      expect(recipe.variantForRouteAndBatch('route-a', 100)?.id, 'a-100x');
      expect(recipe.variantForRouteAndBatch('route-b', 100), isNull);
    });

    test('preserves the batch when the newly selected route supports it', () {
      final recipe = _matrixRecipe();

      expect(recipe.resolveRouteSelection('a-10x', 'route-b')?.id, 'b-10x');
      expect(recipe.resolveRouteSelection('B-10X', 'ROUTE-A')?.id, 'a-10x');
    });

    test('falls back deterministically without inventing a formula', () {
      final recipe = _matrixRecipe();

      expect(recipe.resolveRouteSelection('a-100x', 'route-b')?.id, 'b-1x');
      expect(recipe.resolveBatchSelection('b-1x', 100), isNull);
      expect(recipe.resolveBatchSelection('b-1x', 10)?.id, 'b-10x');
    });

    test('resolves one complete formula for planning', () {
      final recipe = _matrixRecipe();

      final selected = recipe.resolveVariant('B-10X');

      expect(selected.baseOutput, 4);
      expect(selected.outputMinimum, 10);
      expect(
        selected.ingredients.map((ingredient) => ingredient.name),
        <String>['Prepared Stone', 'Batch Catalyst'],
      );
      expect(
        selected.ingredients.map((ingredient) => ingredient.quantity),
        <double>[10, 1],
      );
    });

    test('legacy variants remain route-only one-times formulas', () {
      final recipe = _recipe(
        variants: <RecipeVariant>[
          _variant(
            id: 'route-a',
            label: 'Route A',
            ingredients: <Ingredient>[_ingredient('A', 1)],
          ),
          _variant(
            id: 'route-b',
            label: 'Route B',
            ingredients: <Ingredient>[_ingredient('B', 1)],
          ),
        ],
      );

      expect(recipe.variantRoutes.map((route) => route.id), <String>[
        'route-a',
        'route-b',
      ]);
      expect(recipe.variantBatchMultipliers, <int>[1]);
      expect(recipe.hasRecipeRouteChoices, isTrue);
      expect(recipe.hasRecipeBatchChoices, isFalse);
    });
  });
}

Recipe _matrixRecipe() => _recipe(
  variants: <RecipeVariant>[
    _variant(
      id: 'a-1x',
      label: 'Raw Materials',
      routeId: 'route-a',
      ingredients: <Ingredient>[_ingredient('Raw Material', 1)],
    ),
    _variant(
      id: 'a-10x',
      label: 'Raw Materials',
      routeId: 'route-a',
      batchMultiplier: 10,
      baseOutput: 4,
      output: 10,
      ingredients: <Ingredient>[
        _ingredient('Raw Material', 10),
        _ingredient('Batch Catalyst', 1),
      ],
    ),
    _variant(
      id: 'a-100x',
      label: 'Raw Materials',
      routeId: 'route-a',
      batchMultiplier: 100,
      baseOutput: 40,
      output: 100,
      ingredients: <Ingredient>[
        _ingredient('Raw Material', 100),
        _ingredient('Large Batch Catalyst', 1),
      ],
    ),
    _variant(
      id: 'b-1x',
      label: 'Prepared Stone',
      routeId: 'route-b',
      ingredients: <Ingredient>[_ingredient('Prepared Stone', 1)],
    ),
    _variant(
      id: 'b-10x',
      label: 'Prepared Stone',
      routeId: 'route-b',
      batchMultiplier: 10,
      baseOutput: 4,
      output: 10,
      ingredients: <Ingredient>[
        _ingredient('Prepared Stone', 10),
        _ingredient('Batch Catalyst', 1),
      ],
    ),
  ],
  defaultVariantId: 'a-1x',
);

Recipe _recipe({
  required List<RecipeVariant> variants,
  String? defaultVariantId,
}) => Recipe(
  name: 'Matrix Output',
  type: 'processing',
  baseOutput: 0.4,
  group: 'Processing - Heating',
  method: 'Heating',
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
  defaultVariantId: defaultVariantId,
);

RecipeVariant _variant({
  required String id,
  required String label,
  required List<Ingredient> ingredients,
  String? routeId,
  int batchMultiplier = 1,
  double baseOutput = 0.4,
  double output = 1,
}) => RecipeVariant(
  id: id,
  label: label,
  routeId: routeId,
  batchMultiplier: batchMultiplier,
  type: 'processing',
  baseOutput: baseOutput,
  method: 'Heating',
  ingredients: ingredients,
  outputMinimum: output,
  outputMaximum: output,
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);
