import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inventory_test_fixture.dart';

void main() {
  test('production quality alternatives match Avalonia inventory groups', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final state = PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.fromMillisecondsSinceEpoch(0),
      activeMode: CraftMode.alchemy,
      alchemy: ModeState(
        target: 'Harmony Draught - Edania',
        bonusTarget: 'Clear Liquid Reagent',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
      ),
      cooking: ModeState(
        target: 'Beer',
        bonusTarget: 'Beer',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.cooking),
      ),
      processing: ModeState(
        target: 'Wheat Flour',
        bonusTarget: 'Wheat Flour',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      ),
      processingYields: const <String, double>{},
      marketTax: MarketTax(),
    );
    final controller = PlannerApplicationController(
      catalog: catalog,
      initialState: state,
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    final projection = InventoryProjection.assemble(controller.active);
    final expectedInventoryNames = <String>{};
    for (final mode in CraftMode.values) {
      for (final recipe in catalog.forMode(mode).items.values) {
        final referenceOnly =
            mode == CraftMode.processing &&
            (recipe.group ?? '').toLowerCase().startsWith('reference -');
        if (referenceOnly) continue;
        expectedInventoryNames.add(recipe.name.toLowerCase());
        for (final ingredients in <Iterable<Ingredient>>[
          recipe.ingredients,
          for (final variant in recipe.variants) variant.ingredients,
        ]) {
          for (final ingredient in ingredients) {
            expectedInventoryNames
              ..add(ingredient.name.toLowerCase())
              ..addAll(ingredient.options.map((name) => name.toLowerCase()));
          }
        }
      }
    }
    final projectedInventoryNames = projection.items
        .map((item) => item.name.toLowerCase())
        .toSet();
    expectedInventoryNames.removeWhere(isTemporarilyArchivedItem);
    expect(
      expectedInventoryNames.difference(projectedInventoryNames),
      isEmpty,
      reason:
          'All Items must expose every real life-skill ingredient, substitute, '
          'intermediate, meal, elixir, draught, and recipe result.',
    );
    final counts = <String, int>{
      for (final group in projection.groups) group.name: group.itemCount,
    };
    expect(counts['Elixirs'], greaterThanOrEqualTo(95));
    expect(counts['Mushrooms'], greaterThanOrEqualTo(47));

    final elixirs = projection.visibleItems(category: 'Elixirs', search: '');
    expect(
      elixirs.map((item) => item.name),
      isNot(contains('High-Quality Elixir of Assassination')),
    );

    final mushrooms = projection
        .visibleItems(category: 'Mushrooms', search: '')
        .map((item) => item.name)
        .toList(growable: false);
    expect(
      mushrooms,
      containsAll(<String>[
        'High-Quality Blue Umbrella Mushroom',
        'High-Quality Volcanic Umbrella Mushroom',
        'Special Blue Umbrella Mushroom',
        'Special Volcanic Umbrella Mushroom',
      ]),
    );
    expect(
      mushrooms,
      orderedEquals(<String>[...mushrooms]..sort(_compareNames)),
    );
  });

  test('production blood and meat families use human BDO group labels', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    PlannerState stateFor(CraftMode mode) => PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.fromMillisecondsSinceEpoch(0),
      activeMode: mode,
      alchemy: ModeState(
        target: 'Clown\'s Blood',
        bonusTarget: 'Clown\'s Blood',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
      ),
      cooking: ModeState(
        target: 'Balenos Meal',
        bonusTarget: 'Balenos Meal',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.cooking),
      ),
      processing: ModeState(
        target: 'Wheat Flour',
        bonusTarget: 'Wheat Flour',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      ),
      processingYields: const <String, double>{},
      marketTax: MarketTax(),
    );

    final alchemyController = PlannerApplicationController(
      catalog: catalog,
      initialState: stateFor(CraftMode.alchemy),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    addTearDown(alchemyController.dispose);
    final alchemy = InventoryProjection.assemble(alchemyController.active);
    final wolfBlood = alchemy.items.singleWhere(
      (item) => item.name == 'Wolf Blood',
    );
    expect(wolfBlood.section, 'Animal materials');
    expect(wolfBlood.subsection, 'Blood Group 1');

    final cookingController = PlannerApplicationController(
      catalog: catalog,
      initialState: stateFor(CraftMode.cooking),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    addTearDown(cookingController.dispose);
    final cooking = InventoryProjection.assemble(cookingController.active);
    expect(
      cooking.items.singleWhere((item) => item.name == 'Beef').subsection,
      'Red meat',
    );
    expect(
      cooking.items
          .singleWhere((item) => item.name == 'Chicken Meat')
          .subsection,
      'Bird meat',
    );
    expect(
      cooking.items.singleWhere((item) => item.name == 'Bird Meat').subsection,
      'Bird meat',
    );
    final steaming = cooking.items.singleWhere(
      (item) => item.name == 'Steaming Hot Grilled Bird Meat',
    );
    expect(steaming.section, 'Cooking');
    expect(steaming.subsection, 'Prepared food');
    expect(
      cooking.items
          .singleWhere((item) => item.name == 'Lizard Meat')
          .subsection,
      'Reptile meat',
    );
  });

  test('production taxonomy uses an item identity from every craft mode', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    PlannerState stateFor(CraftMode mode) => PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.fromMillisecondsSinceEpoch(0),
      activeMode: mode,
      alchemy: ModeState(
        target: 'Harmony Draught - Edania',
        bonusTarget: 'Clear Liquid Reagent',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
      ),
      cooking: ModeState(
        target: 'Beer',
        bonusTarget: 'Beer',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.cooking),
      ),
      processing: ModeState(
        target: 'Wheat Flour',
        bonusTarget: 'Wheat Flour',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      ),
      processingYields: const <String, double>{},
      marketTax: MarketTax(),
    );

    for (final mode in CraftMode.values) {
      final controller = PlannerApplicationController(
        catalog: catalog,
        initialState: stateFor(mode),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      final items = InventoryProjection.assemble(controller.active).items;
      void expectHome(String name, String section, String subsection) {
        final item = items.singleWhere((candidate) => candidate.name == name);
        expect(item.section, section, reason: '$name/${mode.key}');
        expect(item.subsection, subsection, reason: '$name/${mode.key}');
      }

      final leatherGlaze = items.singleWhere(
        (item) => item.name == 'Leather Glaze',
      );
      expect(leatherGlaze.section, 'Alchemy materials', reason: mode.key);
      expect(
        leatherGlaze.subsection,
        'Reagents & crafting additives',
        reason: mode.key,
      );

      final steelDefense = items.singleWhere(
        (item) => item.name == 'Elixir of Steel Defense',
      );
      expect(steelDefense.section, 'Elixirs & buffs', reason: mode.key);
      expect(steelDefense.subsection, 'Elixirs', reason: mode.key);

      final fallingMoon = items.singleWhere(
        (item) => item.name == 'Tears of the Falling Moon',
      );
      expect(fallingMoon.section, 'Alchemy materials', reason: mode.key);
      expect(fallingMoon.subsection, 'Special ingredients', reason: mode.key);

      final blackStonePowder = items.singleWhere(
        (item) => item.name == 'Black Stone Powder',
      );
      expect(blackStonePowder.section, 'Miscellaneous', reason: mode.key);
      expect(
        blackStonePowder.subsection,
        'Processed & other',
        reason: mode.key,
      );

      for (final name in <String>[
        'Coral Crystal',
        'Imperfect Lightstone of Earth',
        'Imperfect Lightstone of Fire',
        'Imperfect Lightstone of Flora',
        'Imperfect Lightstone of Wind',
        'Purified Lightstone of Earth',
        'Purified Lightstone of Fire',
        'Purified Lightstone of Flora',
        'Purified Lightstone of Wind',
      ]) {
        final material = items.singleWhere((item) => item.name == name);
        expect(
          material.section,
          'Alchemy materials',
          reason: '$name/${mode.key}',
        );
        expect(
          material.subsection,
          'Special ingredients',
          reason: '$name/${mode.key}',
        );
        expect(material.equipmentLike, isFalse, reason: '$name/${mode.key}');
      }

      for (final name in <String>[
        'Elixir of Armor',
        'Armor Draught',
        'Immortal: Armor Draught',
      ]) {
        final buff = items.singleWhere((item) => item.name == name);
        expect(buff.equipmentLike, isFalse, reason: '$name/${mode.key}');
        expect(buff.section, 'Elixirs & buffs', reason: '$name/${mode.key}');
        expect(
          buff.subsection,
          name.contains('Draught') ? 'Draughts' : 'Elixirs',
          reason: '$name/${mode.key}',
        );
      }

      for (final name in <String>[
        'Hard Black Crystal Shard',
        'Sharp Black Crystal Shard',
        'Pure Iron Crystal',
        'Ultimate Armor Reform Stone',
      ]) {
        expect(
          items.singleWhere((item) => item.name == name).equipmentLike,
          isFalse,
          reason: '$name/${mode.key}',
        );
      }

      for (final name in <String>[
        'Cold Draft Beer',
        'Blood Red Delotia Pudding',
      ]) {
        final food = items.singleWhere((item) => item.name == name);
        expect(food.section, 'Cooking', reason: '$name/${mode.key}');
        expect(food.subsection, 'Prepared food', reason: '$name/${mode.key}');
      }

      final enhancedCookingNames = catalog.cooking.items.entries
          .where(
            (entry) =>
                entry.value.group == 'Cooking' &&
                !const <String>{
                  'Essence of Liquor',
                  'Vinegar',
                  'Dressing',
                  'Red Sauce',
                  'White Sauce',
                }.contains(entry.key),
          )
          .map((entry) => entry.key)
          .toSet();
      expect(enhancedCookingNames, isNotEmpty);
      expect(
        items.where(
          (item) =>
              enhancedCookingNames.contains(item.name) &&
              (item.section != 'Cooking' || item.subsection != 'Prepared food'),
        ),
        isEmpty,
        reason: mode.key,
      );
      final simpleCookingNames = catalog.processing.items.entries
          .where(
            (entry) =>
                entry.value.group == 'Processing - Simple Cooking' &&
                !entry.key.startsWith('Spirit Essence of '),
          )
          .map((entry) => entry.key)
          .toSet();
      expect(simpleCookingNames, isNotEmpty);
      expect(
        items.where(
          (item) =>
              simpleCookingNames.contains(item.name) &&
              (item.section != 'Cooking' || item.subsection != 'Prepared food'),
        ),
        isEmpty,
        reason: 'Processing Simple Cooking foods/${mode.key}',
      );
      final driedFishNames = <String>{
        for (final entry in catalog.cooking.items.entries)
          if (entry.value.group == 'Dried Fish') entry.key,
      };
      for (final recipe in catalog.cooking.items.values) {
        final formulas = <Iterable<Ingredient>>[
          recipe.ingredients,
          for (final variant in recipe.variants) variant.ingredients,
        ];
        for (final ingredient in formulas.expand((value) => value)) {
          if (ingredient.substituteGroup == 'BDO group 6') {
            driedFishNames.addAll(<String>[
              ingredient.name,
              ...ingredient.options,
            ]);
          }
        }
      }
      expect(driedFishNames.length, greaterThan(130));
      expect(
        items.where(
          (item) =>
              driedFishNames.contains(item.name) &&
              (item.section != 'Cooking' ||
                  item.subsection != 'Fish & seafood'),
        ),
        isEmpty,
        reason: 'Dried-fish substitute family/${mode.key}',
      );

      expectHome('Bronze Ingot', 'Ores & minerals', 'Metals');
      expectHome('Black Gem', 'Ores & minerals', 'Gems & crystals');
      expectHome('Blood Ruby', 'Ores & minerals', 'Gems & crystals');
      expectHome('Thick Turo Blood', 'Animal materials', 'Other blood');
      expectHome('Corn Oil', 'Cooking', 'Cooking basics');
      expectHome('Perilla Oil', 'Cooking', 'Cooking basics');
      for (final name in <String>[
        'Dried Tuna',
        'Dried Golden-thread',
        'Dried Maomao',
        'Dried Stone Moroko',
      ]) {
        expectHome(name, 'Cooking', 'Fish & seafood');
      }
      for (final name in <String>[
        'Ferocious Leather',
        'Damaged Hide',
        'Usable Hide',
        'Naturewoven Hide',
      ]) {
        expectHome(name, 'Animal materials', 'Other animal materials');
      }
      for (final name in <String>[
        'Caphras Stone',
        'Concentrated Magical Black Stone',
        'Concentrated Magical Black Stone (Armor)',
        "Krogdalo's Origin Stone",
        'Ultimate Armor Reform Stone',
        'Ultimate Weapon Reform Stone',
      ]) {
        expectHome(name, 'Miscellaneous', 'Processed & other');
      }
      for (final name in <String>[
        'Essence of Liquor',
        'Vinegar',
        'Dressing',
        'Red Sauce',
        'White Sauce',
        'Red Pepper Powder',
      ]) {
        expectHome(name, 'Cooking', 'Cooking basics');
      }
      expectHome('Rough Stone', 'Ores & minerals', 'Ore & raw minerals');
      expectHome('Melted Iron Shard', 'Ores & minerals', 'Metals');
      expectHome("Monk's Branch", 'Trees & wood', 'Branches & bark');
      expectHome(
        'Insectivore Plant Sap',
        'Alchemy materials',
        'Special ingredients',
      );
      expectHome('Delotia Powder', 'Alchemy materials', 'Traces & powders');
      for (final name in <String>[
        'Black Stone',
        'Black Stone Powder',
        'Black Gem Fragment',
        'Earth Spirit Stone Fragment',
        'Water Spirit Stone Fragment',
        'Wind Spirit Stone Fragment',
      ]) {
        expectHome(name, 'Miscellaneous', 'Processed & other');
      }
      for (final name in <String>[
        'Bottle of River Water',
        'Bottle of Turbid Water',
        'Bag of Muddy Water',
        'Distilled Water',
        'Mineral Water',
        'Purified Water',
      ]) {
        expectHome(name, 'Cooking', 'Water & liquids');
      }
      for (final name in <String>['Citron Tea', 'Exquisite Cron Meal']) {
        expectHome(name, 'Cooking', 'Prepared food');
      }
      for (final name in <String>[
        'Ancient Spirit Dust',
        'Essence of Dawn',
        'Spirit Essence of Water',
        'Mutant Loah Flower Neutralizer',
        'Concentrated Herbal Juice',
        'Highly Concentrated Herbal Juice',
        'Flower of Madness',
      ]) {
        expectHome(name, 'Miscellaneous', 'Processed & other');
      }
      for (final name in <String>["Ah'krad", "Basilisk's Belt"]) {
        final item = items.singleWhere((candidate) => candidate.name == name);
        expect(
          item.section,
          isNot('Alchemy materials'),
          reason: '$name/${mode.key}',
        );
      }

      final buffNames = items.where(
        (item) => RegExp(
          r'\b(elixir|draught|perfume)\b',
          caseSensitive: false,
        ).hasMatch(item.name),
      );
      expect(
        buffNames.where((item) => item.section != 'Elixirs & buffs'),
        isEmpty,
        reason: mode.key,
      );
    }
  });

  test(
    'projection keeps editor groups while assigning deterministic human homes',
    () {
      final controller = PlannerApplicationController(
        catalog: inventoryCatalog(),
        initialState: inventoryDocument(showDeleteTools: false),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      final projection = InventoryProjection.assemble(controller.active);
      expect(
        projection.groups.map((group) => group.name),
        containsAll(<String>[
          'Alchemy Reagents',
          'Cooking',
          'Crops',
          'Creature Blood',
          'Field Kit',
          'Grinding',
          'Herbs',
          'Vendor Materials',
          'Wild Herbs',
        ]),
      );
      expect(
        projection.groups
            .singleWhere((group) => group.name == 'Herbs')
            .itemCount,
        1,
      );
      final homes = projection.items
          .map((item) => '${item.section}/${item.subsection}')
          .toList(growable: false);
      expect(homes.first, 'Animal materials/Other blood');
      expect(homes, contains('Plants & farming/Herbs & flowers'));
      expect(homes, contains('Cooking/Cooking basics'));
      expect(
        homes,
        contains('Alchemy materials/Reagents & crafting additives'),
      );
      expect(
        projection.items
            .singleWhere((item) => item.name == 'Silver Azalea')
            .owned,
        7,
      );
      expect(
        projection.items.where((item) => item.name == 'Wheat'),
        hasLength(1),
      );
      expect(
        projection.items.map((item) => item.name),
        containsAll(<String>['Beer', 'Wheat Flour']),
      );
    },
  );

  test('saved catalog-less quantities remain visible as saved items', () {
    final source = inventoryDocument(showDeleteTools: false);
    final alchemy = source.alchemy.copyWith(
      inventory: <String, double>{
        ...source.alchemy.inventory,
        'Retired Saved Material': 42,
      },
    );
    final controller = PlannerApplicationController(
      catalog: inventoryCatalog(),
      initialState: source.copyWith(alchemy: alchemy),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    final item = InventoryProjection.assemble(
      controller.active,
    ).items.singleWhere((row) => row.name == 'Retired Saved Material');

    expect(item.savedOnly, isTrue);
    expect(item.section, 'Miscellaneous');
    expect(item.subsection, 'Saved items');
    expect(item.owned, 42);
  });

  test(
    'search covers name, category, source, vendor, location, and keywords',
    () {
      final controller = PlannerApplicationController(
        catalog: inventoryCatalog(),
        initialState: inventoryDocument(showDeleteTools: false),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      final projection = InventoryProjection.assemble(controller.active);
      final sunrise = projection.items.singleWhere(
        (item) => item.name == 'Sunrise Herb',
      );
      for (final query in <String>[
        'sunrise',
        'herbs',
        'gathered near',
        'lara',
        'heidel',
        'serendia',
        'morning herb',
      ]) {
        expect(sunrise.matches(query), isTrue, reason: query);
      }
      expect(sunrise.matches('Calpheon timber'), isFalse);
      expect(
        projection.visibleItems(category: 'Herbs', search: 'Heidel'),
        hasLength(1),
      );
      expect(
        projection.visibleItems(category: 'Wild Herbs', search: 'Heidel'),
        isEmpty,
      );
      expect(controller.active.mode, CraftMode.alchemy);
    },
  );

  test('category normalization collapses whitespace without changing case', () {
    expect(
      normalizeInventoryCategory('  Daily   Alchemy\tRuns  '),
      'Daily Alchemy Runs',
    );
  });
}

int _compareNames(String left, String right) {
  final folded = left.toLowerCase().compareTo(right.toLowerCase());
  return folded != 0 ? folded : left.compareTo(right);
}
