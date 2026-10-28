import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_recipe_routes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as fixture;

void main() {
  test('real Tenacity formulas separate coral from perfume and batch', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final routes = opportunityRecipeRoutes([
      catalog.processing.items['Perfume of Tenacity']!,
      catalog.alchemy.items['Perfume of Tenacity']!,
    ]);
    expect(routes, hasLength(2));
    expect(routes.first.formulas.map((f) => f.batchMultiplier), [1, 10]);
    expect(routes.last.formulas.map((f) => f.batchMultiplier), [1]);
    expect(
      routes.first
          .selectBatch(10)
          .resolved
          .ingredients
          .map((i) => (i.name, i.quantity)),
      contains(("Ibellab's Essence", 1.0)),
    );
    final coral = routes.last.selectBatch(10);
    expect(coral.batchMultiplier, 1);
    expect(coral.resolved.type, 'alchemy');
    expect(
      coral.resolved.ingredients.map((i) => (i.name, i.quantity)),
      contains(("Rusalka's Coral", 30.0)),
    );
    expect(
      coral.resolved.ingredients.any((i) => i.name == 'Perfume of Deep Sea'),
      isFalse,
    );
  });

  test(
    'identical copies collapse but outputs and substitution ratios do not',
    () {
      final base = fixture.recipe('Product');
      final duplicate = fixture.recipe('Product');
      final output = fixture.recipe('Product', maximum: 2);
      final alternatives = fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient(
            'Ore',
            1,
            options: ['Other Ore'],
            ratios: {'Other Ore': 2},
          ),
        ],
      );
      final routes = opportunityRecipeRoutes([
        base,
        duplicate,
        output,
        alternatives,
      ]);
      expect(routes, hasLength(3));
      expect(routes.first.contains(duplicate, null), isTrue);
      expect(routes.first.contains(output, null), isFalse);
    },
  );

  test(
    'route selection preserves supported batches and falls back without multiplication',
    () {
      RecipeVariant variant(String id, String route, int batch, String input) =>
          RecipeVariant(
            id: id,
            label: route,
            type: 'processing',
            baseOutput: 1,
            method: 'Heating',
            routeId: route,
            batchMultiplier: batch,
            ingredients: [fixture.ingredient(input, batch.toDouble())],
            outputMinimum: batch.toDouble(),
            outputMaximum: batch.toDouble(),
          );
      final recipe = fixture.recipe(
        'Product',
        variants: [
          variant('a1', 'a', 1, 'Ore'),
          variant('a10', 'a', 10, 'Ore'),
          variant('b1', 'b', 1, 'Other Ore'),
          variant('b10', 'b', 10, 'Other Ore'),
          variant('c1', 'c', 1, 'Third Ore'),
        ],
      );
      final routes = opportunityRecipeRoutes([recipe]);
      expect(routes, hasLength(3));
      expect(routes[1].selectBatch(10).variantId, 'b10');
      expect(routes[2].selectBatch(10).variantId, 'c1');
      expect(routes[2].forBatch(10), isNull);
      expect(routes[1].contains(recipe, 'b10'), isTrue);
      expect(routes[1].contains(recipe, 'a10'), isFalse);
    },
  );

  test('reference-only conversions never become selectable recipes', () {
    expect(
      opportunityRecipeRoutes([
        fixture.recipe('Product', role: RecipeRole.manualConversion),
        fixture.recipe('Product', role: RecipeRole.salvage),
        fixture.leaf('Product'),
      ]),
      isEmpty,
    );
  });

  test('route letters stay readable beyond Z', () {
    expect([0, 1, 25, 26, 27].map(opportunityRecipeLetter), [
      'A',
      'B',
      'Z',
      'AA',
      'AB',
    ]);
  });
}
