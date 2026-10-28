import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_preview_routes.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeBookFormula formula(
  CraftMode mode, {
  String method = 'Simple Alchemy',
  double quantity = 30,
  double output = 10,
  int batch = 10,
  List<String> options = const [],
  Map<String, double> ratios = const {},
}) => RecipeBookFormula(
  outputName: 'Draught',
  mode: mode,
  type: mode == CraftMode.processing ? 'processing' : 'simple_alchemy',
  method: method,
  baseOutput: mode == CraftMode.processing ? output / 2.5 : output,
  outputMinimum: output,
  outputMaximum: output,
  batchMultiplier: batch,
  ingredients: [
    Ingredient(
      name: 'Elixir',
      quantity: quantity,
      options: options,
      substituteGroup: null,
      substituteRatios: ratios,
    ),
  ],
);

void main() {
  test('identical recipes across catalogues expose one actual method', () {
    final routes = recipeBookPreviewRoutes([
      formula(CraftMode.processing),
      formula(CraftMode.alchemy),
    ]);
    expect(routes, hasLength(1));
    expect(routes.single.label, 'Simple Alchemy');
    expect(routes.single.mode, CraftMode.alchemy);
    expect(routes.single.equivalentModes, {
      CraftMode.alchemy,
      CraftMode.processing,
    });
  });

  test('distinct methods retain human workstation labels', () {
    final routes = recipeBookPreviewRoutes([
      formula(CraftMode.alchemy, method: 'Alchemy'),
      formula(CraftMode.processing),
    ]);
    expect(routes.map((route) => route.label), [
      'Residence Alchemy',
      'Simple Alchemy',
    ]);
  });

  test(
    'different quantity, output, batch, substitutes or ratios never collapse',
    () {
      for (final alternative in [
        formula(CraftMode.processing, quantity: 60),
        formula(CraftMode.processing, output: 20),
        formula(CraftMode.processing, batch: 100),
        formula(CraftMode.processing, options: ['Blue Elixir']),
        formula(CraftMode.processing, ratios: {'Blue Elixir': .333}),
      ]) {
        final routes = recipeBookPreviewRoutes([
          formula(CraftMode.alchemy),
          alternative,
        ]);
        expect(routes, hasLength(2));
        expect(routes.map((route) => route.label).toSet(), hasLength(2));
      }
    },
  );

  test('an additional recipe batch remains reachable', () {
    expect(
      recipeBookPreviewRoutes([
        formula(CraftMode.alchemy),
        formula(CraftMode.processing),
        formula(CraftMode.processing, batch: 100, quantity: 300, output: 100),
      ]),
      hasLength(2),
    );
  });
}
