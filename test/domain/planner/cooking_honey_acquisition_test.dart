import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  const assembly = PlannerAssembly();
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  test('Oatmeal buys Honey rather than automatically grinding beehives', () {
    final state = _state(CraftMode.cooking, target: 'Oatmeal');
    final plan = assembly.build(
      catalog: catalog,
      mode: CraftMode.cooking,
      state: state,
    );
    final honey = plan.missing.singleWhere(
      (item) => item.name == 'Cooking Honey',
    );
    expect(honey.need, greaterThan(0));
    expect(honey.market.marketable, isTrue);
    expect(
      plan.steps.map((step) => step.name),
      isNot(contains('Cooking Honey')),
    );
    expect(
      plan.missing.map((item) => item.name),
      isNot(contains('Wild Beehive')),
    );
    final reference = catalog.cooking.items['Cooking Honey']!;
    expect(reference.role, RecipeRole.manualConversion);
    expect(reference.ingredients.single.name, 'Wild Beehive');
    expect(reference.ingredients.single.quantity, 3);
  });

  test(
    'owned Honey reduces shopping without consuming owned beehives or choices',
    () {
      final blank = assembly.build(
        catalog: catalog,
        mode: CraftMode.cooking,
        state: _state(CraftMode.cooking, target: 'Oatmeal'),
      );
      final needed = blank.missing
          .singleWhere((item) => item.name == 'Cooking Honey')
          .need;
      final state = _state(
        CraftMode.cooking,
        target: 'Oatmeal',
        inventory: {'Cooking Honey': 2, 'Wild Beehive': 500},
        choices: const {'Unrelated saved recipe': 'keep-this-choice'},
      );
      final before = jsonEncode(state.toJson());
      final plan = assembly.build(
        catalog: catalog,
        mode: CraftMode.cooking,
        state: state,
      );
      final honey = plan.missing.singleWhere(
        (item) => item.name == 'Cooking Honey',
      );
      expect(honey.need, needed);
      expect(honey.have, 2);
      expect(honey.missing, needed - 2);
      expect(
        plan.missing.map((item) => item.name),
        isNot(contains('Wild Beehive')),
      );
      expect(jsonEncode(state.toJson()), before);
    },
  );

  test(
    'explicit Processing Honey keeps the recorded one-to-two output recipe',
    () {
      final honey = catalog.processing.items['Cooking Honey']!;
      expect(honey.role, RecipeRole.production);
      expect(honey.isCraftable, isTrue);
      expect(honey.outputMinimum, 1);
      expect(honey.outputMaximum, 2);
      final plan = assembly.build(
        catalog: catalog,
        mode: CraftMode.processing,
        state: _state(CraftMode.processing, target: 'Cooking Honey', want: 3),
      );
      expect(plan.steps.single.name, 'Cooking Honey');
      expect(plan.steps.single.count, 2);
      expect(plan.steps.single.produced, 3);
      expect(plan.missing.single.name, 'Wild Beehive');
      expect(plan.missing.single.need, 6);
    },
  );

  test(
    'Cooking item details can still resolve the explicit Grinding recipe',
    () {
      final resolved = resolveAcquisitionRecipe(
        name: 'Cooking Honey',
        currentMode: CraftMode.cooking,
        recipesByMode: {
          for (final mode in CraftMode.values)
            mode: catalog.forMode(mode).items,
        },
      );
      expect(resolved?.mode, CraftMode.processing);
      expect(resolved?.recipe.method, 'Grinding');
      expect(resolved?.recipe.ingredients.single.quantity, 3);
    },
  );

  test(
    'reviewed acquisition keeps worker Honey separate from optional hunting',
    () {
      final source =
          jsonDecode(File('assets/data/app-data.json').readAsStringSync())
              as Map;
      final info = source['acquisitionInfo'] as Map;
      final honey = info['Cooking Honey'] as Map;
      final notes = jsonEncode(honey);
      expect(notes, contains('Alejandro Farm or Zvier Highlands'));
      expect(
        notes,
        contains('Optional: shoot beehives from trees in Balenos Forest'),
      );
      expect(notes, contains('https://bdocodex.com/us/quest/9042/5/'));
      expect(
        jsonEncode(info['Wild Beehive']),
        contains('Grind 3 Wild Beehives'),
      );
    },
  );

  for (final entry in const {
    CraftMode.alchemy: 'Clear Liquid Reagent',
    CraftMode.cooking: 'Delotia Juice',
  }.entries) {
    test(
      '${entry.key.name} buys Purified Water without scheduling bottles',
      () {
        final state = _state(entry.key, target: entry.value);
        final plan = assembly.build(
          catalog: catalog,
          mode: entry.key,
          state: state,
        );
        expect(
          catalog.forMode(entry.key).items['Purified Water']!.role,
          RecipeRole.manualConversion,
        );
        final water = plan.missing.singleWhere(
          (item) => item.name == 'Purified Water',
        );
        expect(water.missing, greaterThan(0));
        expect(water.market.price, 5000);
        expect(
          plan.steps.map((step) => step.name),
          isNot(contains('Purified Water')),
        );
        expect(
          plan.missing.map((item) => item.name),
          isNot(contains('Bottle of River Water')),
        );
      },
    );
  }

  test(
    'explicit water Filtering preserves its recorded output and ingredients',
    () {
      final recipe = catalog.processing.items['Purified Water']!;
      expect(recipe.role, RecipeRole.production);
      expect(recipe.outputMinimum, 1);
      expect(recipe.outputMaximum, 4);
      final plan = assembly.build(
        catalog: catalog,
        mode: CraftMode.processing,
        state: _state(CraftMode.processing, target: 'Purified Water', want: 5),
      );
      expect(plan.steps.single.count, 2);
      expect(plan.steps.single.produced, 5);
      expect(plan.missing.single.name, 'Bottle of River Water');
      expect(plan.missing.single.need, 2);
    },
  );

  test('ordinary flour dough dairy and herb processing remains automatic', () {
    for (final name in [
      'Wheat Flour',
      'Wheat Dough',
      'Cream',
      'Butter',
      'Cheese',
    ]) {
      expect(catalog.cooking.items[name]!.isCraftable, isTrue, reason: name);
    }
    for (final name in [
      'Melted Iron Shard',
      'Insectivore Plant Powder',
      'Insectivore Plant Sap',
      'Delotia Powder',
    ]) {
      expect(catalog.alchemy.items[name]!.isCraftable, isTrue, reason: name);
    }
  });
}

ModeState _state(
  CraftMode mode, {
  required String target,
  int want = 100,
  Map<String, double> inventory = const {},
  Map<String, String> choices = const {},
}) => ModeState(
  target: target,
  want: want,
  bonusTarget: '',
  inventory: inventory,
  recipeVariantChoices: choices,
  ignoreIngredientInventory: false,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
