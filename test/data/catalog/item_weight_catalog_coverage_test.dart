import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
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
              isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId) ||
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
      final reviewDirectory =
          Platform.environment['CATALOG_COVERAGE_REVIEW_DIR'];
      if (reviewDirectory != null) {
        File('$reviewDirectory/active-weight-names.json').writeAsStringSync(
          jsonEncode({
            'names': requiredNames.toList()..sort(),
            'weightIdentities': rules.itemWeightIds.length,
            'weightValues': rules.itemWeightsLtById.length,
          }),
        );
      }
      // The reviewed Cooking water route is now optional. Its two extra raw
      // alternatives leave the automatic graph but keep their exact weights.
      // The September 17 patch retires the four base Apeiron production routes.
      // Three October 29 names enter the raw graph. Confirmed removed outputs
      // and ingredients used only by those routes no longer count as active;
      // their historical weight records are retained, not deleted.
      // Restored Beast/Giant mixed routes add four exact0.2LT elixir inputs.
      // Six black crystals now feed an explicitly random manual conversion,
      // not guaranteed WON production. Their exact weights remain available.
      // Exact retired-boss/legacy availability gates also remove their exclusive
      // consumers. The complete remaining graph must still have known weights;
      // the historical weight records below must remain present.
      expect(requiredNames, hasLength(1606));
      for (final entry in const {
        'Black Magic Crystal - Harphia': '15628',
        'Black Magic Crystal - Cobelinus': '15629',
        'Black Magic Crystal - Viper': '15630',
        'Black Magic Crystal - Hystria': '15631',
        'Black Magic Crystal - Carmae': '15632',
        'Black Magic Crystal - Addis': '15650',
      }.entries) {
        expect(requiredNames, isNot(contains(entry.key)));
        expect(rules.itemWeightIdFor(entry.key), entry.value);
        expect(rules.itemWeightLtFor(entry.key), 0.1);
      }
      expect(
        requiredNames,
        containsAll([
          'Perfume of Resolve',
          'Immortal: Perfume of Resolve',
          'Tainted Khalk Fluid',
        ]),
      );
      for (final name in removedPcItemsById.values) {
        expect(requiredNames, isNot(contains(name)));
        if (rules.itemWeightIds.containsKey(name)) {
          expect(rules.itemWeightLtFor(name), greaterThan(0), reason: name);
        }
      }
      for (final slot in ['Necklace', 'Earring', 'Ring', 'Belt']) {
        expect(requiredNames, isNot(contains('Apeiron $slot')));
        expect(rules.itemWeightLtFor('Apeiron $slot'), greaterThan(0));
      }
      for (final name in ['Bag of Muddy Water', 'Cactus Sap']) {
        expect(requiredNames, isNot(contains(name)));
        expect(rules.itemWeightLtFor(name), greaterThan(0));
        expect(
          catalog.cooking.items['Purified Water']!.ingredients.single.options,
          contains(name),
        );
      }
      expect(
        catalog.cooking.items['Purified Water']!.role,
        RecipeRole.manualConversion,
      );
      expect(
        requiredNames,
        containsAll([
          'Cooking Honey',
          'Wild Beehive',
          'Purified Water',
          'Bottle of River Water',
        ]),
      );
      // Insectivore Plant Root and bound Khan's Dim Magic now have their own
      // reviewed identities rather than inferred aliases or missing weights.
      expect(rules.itemWeightIds, hasLength(1760));
      expect(rules.itemWeightsLtById, hasLength(1759));
      expect(rules.itemWeightIdFor("Khan's Dim Magic"), '45517');
      expect(rules.itemWeightLtFor("Khan's Dim Magic"), 0.1);
      for (final entry in const {
        '[Mix] EXP-Reaper Elixir': '766',
        '[Mix] Swiftness-Wind-Spell Elixir': '768',
        '[Mix] Manhunt-Rage Elixir': '769',
        '[Mix] Thorn-Defense Elixir': '770',
      }.entries) {
        expect(requiredNames, contains(entry.key));
        expect(rules.itemWeightIdFor(entry.key), entry.value);
        expect(rules.itemWeightLtFor(entry.key), 0.2);
      }
      expect(
        rules.itemWeightsLtById.values.every(
          (weight) => weight.isFinite && weight > 0,
        ),
        isTrue,
      );
    },
  );

  test('assembled production options all have exact item weights', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    const assembly = PlannerAssembly();
    final rules = assembly.plannerRules(catalog.supportingData);
    final requiredNames = <String>{};
    for (final mode in CraftMode.values) {
      final recipes = assembly.assembleRecipes(
        catalog: catalog.forMode(mode),
        state: ModeState(
          target: '',
          bonusTarget: '',
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(mode),
        ),
        supportingData: catalog.supportingData,
        sharedMetadata: catalog.alchemy.metadata,
        mode: mode,
        processingRecipes: catalog.processing.items,
      );
      for (final recipe in recipes.values) {
        if (!recipe.isCraftable ||
            recipe.name.trim().toLowerCase() == 'assorted side dishes') {
          continue;
        }
        requiredNames.add(recipe.name);
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
    const reviewedAlternatives = <String, String>{
      'Pile of Sunrise Herbs': '5421',
      'Monkey Blood': '6211',
      'Tiger Blood': '6356',
      'Worm Blood': '6209',
      'Bat Blood': '6219',
      'Kuku Bird Blood': '6217',
      'Cobra Blood': '6222',
    };
    for (final entry in reviewedAlternatives.entries) {
      expect(requiredNames, contains(entry.key));
      expect(rules.itemWeightIdFor(entry.key), entry.value);
      expect(rules.itemWeightLtFor(entry.key), 0.1);
    }
    // Metadata's capital Q must reuse the existing case-insensitive identity.
    expect(rules.itemWeightIdFor('High-Quality Sunrise Herb'), '5444');
    expect(rules.itemWeightLtFor('High-Quality Sunrise Herb'), 0.1);
    expect(
      rules.itemWeightIds.containsKey('High-Quality Sunrise Herb'),
      isFalse,
    );
  });
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
