import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  const assembly = PlannerAssembly();
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  for (final recipe in const [
    (name: 'Clear Liquid Reagent', weeds: 1.0, grass: 1.0),
    (name: 'Pure Powder Reagent', weeds: 1.0, grass: 1.0),
    (name: 'Elixir of Concentration', weeds: 8.0, grass: 2.0),
  ]) {
    test('${recipe.name} has only its verified recipe-local grass ratio', () {
      final ingredient = catalog.alchemy.items[recipe.name]!.ingredients
          .singleWhere((row) => row.name == 'Weeds');
      expect(ingredient.quantity, recipe.weeds);
      expect(ingredient.options, ['Weeds', 'Wild Grass']);
      expect(ingredient.substituteGroup, 'Weeds');
      expect(ingredient.substituteRatios['Weeds'], 1);
      expect(
        ingredient.quantity * ingredient.substituteRatios['Wild Grass']!,
        recipe.grass,
      );

      final state = ModeState(
        target: recipe.name,
        want: 1,
        ignoreIngredientInventory: false,
        bonusTarget: '',
        bonusWant: 1,
        market: MarketState(),
        inventory: {
          for (final row in catalog.alchemy.items[recipe.name]!.ingredients)
            if (row.name != 'Weeds') row.name: 1000,
        },
        appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
      );
      for (final selected in ['Weeds', 'Wild Grass']) {
        final plan = assembly.build(
          catalog: catalog,
          mode: CraftMode.alchemy,
          state: state.copyWith(
            substituteChoices: {'recipe:${recipe.name}:Weeds': selected},
          ),
        );
        expect(plan.missing.single.name, selected);
        expect(
          plan.missing.single.choice!.parentName,
          recipe.name,
          reason: 'An owned zero-craft dependency must not claim this choice.',
        );
        expect(
          plan.missing.single.need,
          selected == 'Weeds' ? recipe.weeds : recipe.grass,
        );
      }
      final defaultPlan = assembly.build(
        catalog: catalog,
        mode: CraftMode.alchemy,
        state: state,
      );
      expect(defaultPlan.missing.single.name, 'Weeds');
      expect(defaultPlan.missing.single.need, recipe.weeds);
    });
  }

  test(
    'grass is not made globally interchangeable and unknown ratios stay out',
    () {
      for (final name in ['Elixir of Burn Removal', 'Antidote Elixir']) {
        final grass = catalog.alchemy.items[name]!.ingredients.singleWhere(
          (row) => row.name == 'Wild Grass',
        );
        expect(grass.options, isEmpty);
        expect(grass.substituteRatios, isEmpty);
      }
      expect(catalog.alchemy.items['Weeds']!.ingredients, isEmpty);
      expect(catalog.alchemy.items['Wild Grass']!.ingredients, isEmpty);
      expect(
        catalog.supportingData['qualityConversions'].toString(),
        isNot(contains('Weeds')),
      );
    },
  );
}
