import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/editor/editor_projection.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_projection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inventory_test_fixture.dart';

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  PlannerApplicationController controllerFor(PlannerState state) {
    final controller = PlannerApplicationController(
      catalog: catalog,
      initialState: state,
      saveState: (value) async => value,
      saveDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('only the eight archived items leave ordinary inventory lists', () {
    final controller = controllerFor(inventoryDocument(showDeleteTools: false));
    final names = InventoryProjection.assemble(
      controller.active,
    ).items.map((item) => item.name).toSet();
    expect(names.where(isTemporarilyArchivedItem), isEmpty);
    expect(
      names,
      containsAll(<String>[
        'Fox Blood',
        'Weasel Blood',
        'Dinosaur Blood',
        'Lizard Hide',
        'Worm Hide',
        'Yak Hide',
        'Weasel Hide',
        'Raccoon Hide',
        'Sealed Black Magic Crystal',
        'Black Magic Crystal - Precision',
        'Black Magic Crystal - Armor',
      ]),
    );
  });

  test('owned archived items and old choices survive assembly and saving', () {
    final original = inventoryDocument(showDeleteTools: false);
    final owned = <String, double>{
      for (final name in temporarilyArchivedItemsById.values) name: 7,
    };
    final state = original.copyWith(
      alchemy: original.alchemy.copyWith(
        inventory: owned,
        substituteChoices: const {
          "recipe:Wise Man's Blood:Blood Group 3": 'Monkey Blood',
        },
      ),
      processing: original.processing.copyWith(
        substituteChoices: const {
          'recipe:Hard Hide:BDO Group 3516': 'Dinosaur Hide',
        },
      ),
    );
    final controller = controllerFor(state);
    final projected = InventoryProjection.assemble(controller.active).items;
    for (final entry in owned.entries) {
      expect(projected.singleWhere((item) => item.name == entry.key).owned, 7);
    }
    const codec = PlannerStateJsonCodec();
    final roundTrip = codec.decode(codec.encode(controller.documentSnapshot));
    expect(roundTrip.alchemy.inventory, owned);
    expect(
      roundTrip.alchemy.substituteChoices,
      state.alchemy.substituteChoices,
    );
    expect(
      roundTrip.processing.substituteChoices,
      state.processing.substituteChoices,
    );
  });

  test('editor keeps historical identities but does not suggest them', () {
    final controller = controllerFor(inventoryDocument(showDeleteTools: false));
    final historicalNames = <String>{};
    for (final mode in CraftMode.values) {
      final projection = RecipeEditorProjection.fromController(
        controller.modes[mode]!,
      );
      expect(
        projection.suggestedItemNames.where(isTemporarilyArchivedItem),
        isEmpty,
      );
      expect(
        projection
            .filtered('')
            .where((record) => isTemporarilyArchivedItem(record.name)),
        isEmpty,
      );
      for (final name in temporarilyArchivedItemsById.values) {
        if (projection.canonicalItemName(name) != null) {
          historicalNames.add(name);
          expect(projection.filtered(name), isEmpty);
        }
      }
    }
    expect(historicalNames, containsAll(temporarilyArchivedItemsById.values));
  });
}
