import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/migration/avalonia_v1_migration.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('synthetic migrated inventory reduces planner material demand', () {
    final migrated =
        AvaloniaV1Migration(
          defaults: AvaloniaMigrationDefaults.schemaFallback(
            applicationVersion: 'test',
          ),
          utcNow: () => DateTime.utc(2026, 7, 20),
        ).decodeUtf8(
          File(
            'test/fixtures/migration/avalonia-planner-state-synthetic.json',
          ).readAsBytesSync(),
        );
    expect(migrated.succeeded, isTrue);

    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final assembly = const PlannerAssembly();
    final withInventory = assembly.build(
      catalog: catalog,
      mode: CraftMode.alchemy,
      state: migrated.state!.alchemy.copyWith(ignoreIngredientInventory: false),
    );
    final withoutInventory = assembly.build(
      catalog: catalog,
      mode: CraftMode.alchemy,
      state: migrated.state!.alchemy.copyWith(
        inventory: const <String, double>{},
        ignoreIngredientInventory: false,
      ),
    );

    expect(withInventory.target, 'Clear Liquid Reagent');
    expect(withInventory.want, 3);
    expect(withInventory.steps, hasLength(1));
    expect(migrated.state!.alchemy.inventory['Weeds'], 7);
    expect(
      withInventory.missing.map((material) => material.name),
      containsAll(<String>['Salt', 'Sunrise Herb']),
    );
    expect(
      withInventory.missing.map((material) => material.name),
      isNot(contains('Weeds')),
    );
    expect(
      withoutInventory.missing.map((material) => material.name),
      contains('Weeds'),
    );
  });
}
