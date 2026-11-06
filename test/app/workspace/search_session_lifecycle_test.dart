import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/editor/editor_session.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Inventory and Editor searches last for the session, not the next one',
    () {
      final inventory = InventorySessionController();
      final editor = RecipeEditorSessionController();
      for (final mode in CraftMode.values) {
        inventory.forMode(mode)
          ..search = 'Milk'
          ..groupItemQuery = 'Honey';
        editor.forMode(mode).search = 'Reagent';
      }
      for (final mode in CraftMode.values) {
        expect(inventory.forMode(mode).search, 'Milk');
        expect(inventory.forMode(mode).groupItemQuery, 'Honey');
        expect(editor.forMode(mode).search, 'Reagent');
      }
      inventory.dispose();
      editor.dispose();
      final freshInventory = InventorySessionController();
      final freshEditor = RecipeEditorSessionController();
      addTearDown(freshInventory.dispose);
      addTearDown(freshEditor.dispose);
      for (final mode in CraftMode.values) {
        expect(freshInventory.forMode(mode).search, isEmpty);
        expect(freshInventory.forMode(mode).groupItemQuery, isEmpty);
        expect(freshEditor.forMode(mode).search, isEmpty);
      }
    },
  );

  test(
    'Planner search and selected recipe still survive a disk reload',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final before = harness.bundle.controller.documentSnapshot;
      final saved = before.copyWith(
        cooking: before.cooking.copyWith(
          target: 'Beer',
          market: before.cooking.market.copyWith(search: 'Milk'),
        ),
      );
      await harness.bundle.stateRepository.save(saved);
      final reloaded = await harness.bundle.stateRepository.load(
        harness.bundle.catalog,
      );
      expect(reloaded.state.cooking.market.search, 'Milk');
      expect(reloaded.state.cooking.target, 'Beer');
      expect(reloaded.state.alchemy.toJson(), before.alchemy.toJson());
      expect(reloaded.state.processing.toJson(), before.processing.toJson());
    },
  );
}
