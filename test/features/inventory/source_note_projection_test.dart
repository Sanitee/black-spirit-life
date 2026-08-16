import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_projection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inventory_test_fixture.dart';

void main() {
  test('Inventory shows user notes but not bundled catalog notes', () {
    final controller = PlannerApplicationController(
      catalog: inventoryCatalog(),
      initialState: inventoryDocument(showDeleteTools: false),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    final projection = InventoryProjection.assemble(controller.active);
    expect(
      projection.items
          .singleWhere((item) => item.name == 'Sunrise Herb')
          .sourceNote,
      'Gathered near Heidel roads.',
    );
    expect(
      projection.items
          .singleWhere((item) => item.name == 'Blood Wolf Blood')
          .sourceNote,
      isNull,
      reason: 'the bundled catalog note is not a user-owned Inventory note',
    );
    expect(
      projection.items.singleWhere((item) => item.name == 'Salt').sourceNote,
      isNull,
      reason: 'vendor/location metadata must not populate the note field',
    );
  });
}
