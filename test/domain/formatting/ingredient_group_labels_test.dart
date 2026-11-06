import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/ingredient_group_labels.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:flutter_test/flutter_test.dart';

Ingredient input(String group) => Ingredient(
  name: 'Paprika',
  quantity: 2,
  options: const ['Paprika', 'Olive'],
  substituteGroup: group,
  substituteRatios: const {},
);

void main() {
  test('friendly labels never alter stored groups, members or ratios', () {
    for (final entry in {
      'BDO group 13': 'Vegetables',
      'BDO group 1': 'Grain',
      'BDO group 2': 'Dough',
      'BDO group 3': 'Fruit',
      'BDO group 5': 'Flour',
      'BDO group 6': 'Dried fish',
      'BDO group 16': 'Blood Group 1',
      'BDO group 15': 'Blood Group 4',
      'BDO group 50': 'Pepper',
      'Fruit Group 6007': 'Fruit',
      'Sunrise Herb Group 3001': 'Sunrise Herb',
      'Future recipe:processing:1': 'Ingredient',
      'BDO group 999999': 'Ingredient',
      'Custom family': 'Custom family',
    }.entries) {
      final ingredient = input(entry.key);
      expect(ingredientGroupLabel(ingredient), entry.value);
      expect(ingredient.substituteGroup, entry.key);
      expect(ingredient.options, ['Paprika', 'Olive']);
      expect(ingredient.quantity, 2);
    }
  });
  test('all bundled raw group IDs have meaningful non-ID labels', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final groups = <String>{};
    for (final mode in CraftMode.values) {
      for (final recipe in catalog.forMode(mode).items.values) {
        for (final ingredient in [
          ...recipe.ingredients,
          for (final variant in recipe.variants) ...variant.ingredients,
        ]) {
          final raw = ingredient.substituteGroup ?? '';
          if (!raw.toLowerCase().startsWith('bdo group ')) continue;
          groups.add(raw);
          final label = ingredientGroupLabel(ingredient);
          expect(label, isNot('Ingredient'), reason: raw);
          expect(label.toLowerCase(), isNot(contains('bdo group')));
        }
      }
    }
    // The reviewed Rice Flour duplicate was removed. Its obsolete
    // BDO group 82011700 is no longer referenced; real grade routes remain.
    expect(groups, hasLength(39));
    expect(groups, isNot(contains('BDO group 82011700')));
  });
}
