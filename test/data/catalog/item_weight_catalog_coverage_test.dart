import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every active production input and output has an exact positive weight',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final rules = const PlannerAssembly().plannerRules(
        catalog.supportingData,
      );
      final requiredNames = <String>{};

      for (final mode in CraftMode.values) {
        for (final recipe in catalog.forMode(mode).items.values) {
          if (!recipe.isCraftable ||
              recipe.name.trim().toLowerCase() == 'assorted side dishes') {
            continue;
          }
          requiredNames.add(recipe.name.trim());
          _addIngredientNames(requiredNames, recipe.ingredients);
          for (final variant in recipe.variants) {
            _addIngredientNames(requiredNames, variant.ingredients);
          }
        }
      }

      final missing =
          requiredNames
              .where((name) => rules.itemWeightLtFor(name) == null)
              .toList()
            ..sort();
      expect(missing, isEmpty);
      expect(requiredNames, hasLength(1662));
      expect(rules.itemWeightIds, hasLength(1686));
      expect(rules.itemWeightsLtById, hasLength(1685));
      expect(
        rules.itemWeightsLtById.values.every(
          (weight) => weight.isFinite && weight > 0,
        ),
        isTrue,
      );
    },
  );
}

void _addIngredientNames(Set<String> names, Iterable<Ingredient> ingredients) {
  for (final ingredient in ingredients) {
    names.add(ingredient.name.trim());
    names.addAll(
      ingredient.options
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty),
    );
  }
}
