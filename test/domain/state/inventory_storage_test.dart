import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lazily preserves the legacy flat inventory as Unassigned', () {
    final mode = _mode(inventory: const <String, double>{'Wolf Blood': 1200});

    final storage = InventoryStorageState.fromModeState(mode);

    expect(storage.hadPersistedLedger, isFalse);
    expect(storage.locations, hasLength(1));
    expect(storage.selectedLocation.name, 'Unassigned');
    expect(storage.totalFor('wolf blood'), 1200);
    expect(storage.applyTo(mode).inventory, mode.inventory);
  });

  test('named locations aggregate without losing the manual balance', () {
    final mode = _mode(inventory: const <String, double>{'Wolf Blood': 200});
    final ensured = InventoryStorageState.fromModeState(
      mode,
    ).ensureLocation('Calpheon City Storage');
    final next = ensured.state
        .setQuantity(
          locationId: ensured.location.id,
          itemName: 'Wolf Blood',
          quantity: 1300,
        )
        .setQuantity(
          locationId: ensured.location.id,
          itemName: 'Fir Timber',
          quantity: 500,
        );

    final updated = next.applyTo(mode);

    expect(updated.inventory, <String, double>{
      'Wolf Blood': 1500,
      'Fir Timber': 500,
    });
    final restored = InventoryStorageState.fromModeState(updated);
    expect(restored.selectedLocation.name, 'Calpheon City Storage');
    expect(restored.quantityAt('calpheon-city-storage', 'Wolf Blood'), 1300);
  });

  test(
    'a reviewed partial screenshot replaces only visible location items',
    () {
      final mode = _mode(
        inventory: const <String, double>{'Wolf Blood': 200, 'Fir Timber': 90},
      );
      final ensured = InventoryStorageState.fromModeState(
        mode,
      ).ensureLocation('Calpheon City Storage');
      final first = ensured.state.applyReviewedScreenshot(
        locationId: ensured.location.id,
        quantities: const <String, double>{
          'Wolf Blood': 1000,
          'Fir Timber': 400,
        },
        replaceMatchingUnassigned: true,
      );
      final second = first.applyReviewedScreenshot(
        locationId: ensured.location.id,
        quantities: const <String, double>{'Wolf Blood': 1200},
      );

      expect(second.totalFor('Wolf Blood'), 1200);
      expect(second.totalFor('Fir Timber'), 400);
      expect(second.quantityAt(inventoryUnassignedLocationId, 'Wolf Blood'), 0);
    },
  );

  test('removing a named storage moves its quantities to Unassigned', () {
    final mode = _mode();
    final ensured = InventoryStorageState.fromModeState(
      mode,
    ).ensureLocation('Velia Storage');
    final withStock = ensured.state.setQuantity(
      locationId: ensured.location.id,
      itemName: 'Salt',
      quantity: 5000,
    );

    final removed = withStock.removeLocation(ensured.location.id);

    expect(removed.locations, hasLength(1));
    expect(removed.totalFor('Salt'), 5000);
    expect(removed.quantityAt(inventoryUnassignedLocationId, 'Salt'), 5000);
  });

  test('clearing one location preserves every other storage', () {
    final mode = _mode(inventory: const <String, double>{'Wolf Blood': 200});
    final ensured = InventoryStorageState.fromModeState(
      mode,
    ).ensureLocation('Velia Storage');
    final withStock = ensured.state
        .setQuantity(
          locationId: ensured.location.id,
          itemName: 'Salt',
          quantity: 5000,
        )
        .setQuantity(
          locationId: ensured.location.id,
          itemName: 'Wolf Blood',
          quantity: 800,
        );

    final cleared = withStock.clearLocation(ensured.location.id);

    expect(cleared.selectedLocationId, ensured.location.id);
    expect(cleared.locationById(ensured.location.id)!.quantities, isEmpty);
    expect(
      cleared.quantityAt(inventoryUnassignedLocationId, 'Wolf Blood'),
      200,
    );
    expect(cleared.totalFor('Wolf Blood'), 200);
    expect(cleared.totalFor('Salt'), 0);
  });

  test(
    'an invalid or drifting ledger fails back to the flat planner total',
    () {
      final mode = _mode(
        inventory: const <String, double>{'Salt': 50},
        extensions: <String, Object?>{
          inventoryStorageExtensionKey: <String, Object?>{
            'schemaVersion': 1,
            'selectedLocationId': 'unassigned',
            'locations': <Object?>[
              <String, Object?>{
                'id': 'unassigned',
                'name': 'Unassigned',
                'quantities': <String, double>{'Salt': 999},
              },
            ],
          },
        },
      );

      final storage = InventoryStorageState.fromModeState(mode);

      expect(storage.recoveredFromMismatch, isTrue);
      expect(storage.totalFor('Salt'), 50);
    },
  );

  test('location names are case-insensitively unique', () {
    final mode = _mode();
    final first = InventoryStorageState.fromModeState(
      mode,
    ).ensureLocation('Calpheon City Storage');

    final repeated = first.state.ensureLocation('  calpheon city storage ');

    expect(repeated.state.locations, hasLength(2));
    expect(repeated.location.id, first.location.id);
  });

  test('named storages migrate once into one shared inventory', () {
    final alchemyBase = _mode(
      inventory: const <String, double>{'Wolf Blood': 200, 'Fir Timber': 25},
    );
    final calpheon = InventoryStorageState.fromModeState(
      alchemyBase,
    ).ensureLocation('Calpheon City Storage');
    final alchemy = calpheon.state
        .setQuantity(
          locationId: calpheon.location.id,
          itemName: 'Wolf Blood',
          quantity: 800,
        )
        .applyTo(alchemyBase);
    final source = _document(
      alchemy: alchemy,
      cooking: _mode(
        inventory: const <String, double>{'wolf blood': 900, 'Salt': 40},
      ),
      processing: _mode(inventory: const <String, double>{'Copper Ore': 55}),
    );

    final migrated = migrateToSharedInventory(source);

    const expected = <String, double>{
      'Wolf Blood': 1000,
      'Fir Timber': 25,
      'Salt': 40,
      'Copper Ore': 55,
    };
    expect(migrated.alchemy.inventory, expected);
    expect(migrated.cooking.inventory, expected);
    expect(migrated.processing.inventory, expected);
    expect(
      migrated.alchemy.extensions,
      isNot(contains(inventoryStorageExtensionKey)),
    );
    expect(
      migrated.cooking.extensions,
      isNot(contains(inventoryStorageExtensionKey)),
    );
    expect(
      migrated.processing.extensions,
      isNot(contains(inventoryStorageExtensionKey)),
    );
    final archive = migrated.extensions[inventoryStorageArchiveExtensionKey];
    expect(archive, isA<Map>());
    expect(
      (archive! as Map)['alchemy'],
      isA<Map>().having(
        (value) => value['namedStorage'],
        'named storage ledger',
        isNotNull,
      ),
    );
    expect(migrateToSharedInventory(migrated), same(migrated));
  });

  test('shared set, add, and clear mirror every planner mode', () {
    final source = _document(
      alchemy: _mode(inventory: const <String, double>{'Salt': 10}),
      cooking: _mode(),
      processing: _mode(),
    );

    final set = setSharedInventoryAmounts(source, const <String, double>{
      'Salt': 25,
      'Wheat': 8,
    });
    final added = setSharedInventoryAmounts(set, const <String, double>{
      'salt': 5,
    }, add: true);

    for (final mode in CraftMode.values) {
      expect(added.forMode(mode).inventory['Salt'], 30);
      expect(added.forMode(mode).inventory['Wheat'], 8);
    }
    final cleared = clearSharedInventory(added);
    for (final mode in CraftMode.values) {
      expect(cleared.forMode(mode).inventory, isEmpty);
    }
  });

  test('shared deltas add output, consume inputs, and clamp at zero', () {
    final source = _document(
      alchemy: _mode(inventory: const <String, double>{'Base': 12, 'Salt': 2}),
      cooking: _mode(),
      processing: _mode(),
    );

    final adjusted = applySharedInventoryDeltas(source, const <String, double>{
      'base': -5,
      'Salt': -20,
      'Finished Meal': 3,
    });

    for (final mode in CraftMode.values) {
      expect(adjusted.forMode(mode).inventory, <String, double>{
        'Base': 7,
        'Finished Meal': 3,
      });
    }
  });
}

ModeState _mode({
  Map<String, double> inventory = const <String, double>{},
  Map<String, Object?> extensions = const <String, Object?>{},
}) => ModeState(
  target: 'Test Target',
  bonusTarget: 'Test Target',
  inventory: inventory,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
  extensions: extensions,
);

PlannerState _document({
  required ModeState alchemy,
  required ModeState cooking,
  required ModeState processing,
}) => PlannerState(
  applicationVersion: 'inventory-migration-test',
  lastSuccessfulWriteUtc: DateTime.utc(2026, 8, 23),
  activeMode: CraftMode.alchemy,
  alchemy: alchemy,
  cooking: cooking,
  processing: processing,
  processingYields: const <String, double>{'defaultYield': 2.5},
  marketTax: MarketTax(),
);
