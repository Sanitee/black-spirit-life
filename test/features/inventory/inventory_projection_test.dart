import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
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
    final counts = <String, int>{
      for (final group in projection.groups) group.name: group.itemCount,
    };
    expect(counts['Elixirs'], 95);
    expect(counts['Mushrooms'], 47);

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

  test(
    'projection assembles deterministic groups, counts, and alphabetical rows',
    () {
      final controller = PlannerApplicationController(
        catalog: inventoryCatalog(),
        initialState: inventoryDocument(showDeleteTools: false),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      final projection = InventoryProjection.assemble(controller.active);
      expect(projection.groups.map((group) => group.name), <String>[
        'Alchemy Reagents',
        'Creature Blood',
        'Field Kit',
        'Herbs',
        'Vendor Materials',
        'Wild Herbs',
      ]);
      expect(
        projection.groups
            .singleWhere((group) => group.name == 'Herbs')
            .itemCount,
        1,
      );
      final names = projection.items.map((item) => item.name).toList();
      expect(names, orderedEquals(<String>[...names]..sort(_compareNames)));
      expect(
        projection.items
            .singleWhere((item) => item.name == 'Silver Azalea')
            .owned,
        7,
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
    expect(item.smartGroup, 'Miscellaneous');
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
