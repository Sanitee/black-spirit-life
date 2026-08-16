import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inventory_test_fixture.dart';

void main() {
  testWidgets(
    'shows storage navigation, smart filters, and editor disclosure',
    (tester) async {
      final harness = InventoryTestHarness();
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      expect(
        find.byKey(InventoryActionKeys.storage('unassigned')),
        findsOneWidget,
      );
      expect(
        find.byKey(InventoryActionKeys.smartGroup('All materials')),
        findsOneWidget,
      );
      expect(
        find.byKey(InventoryActionKeys.filter('materials')),
        findsOneWidget,
      );
      expect(find.byKey(InventoryActionKeys.i04), findsOneWidget);
      expect(find.text('Selected Group'), findsNothing);

      await tester.tap(find.byKey(InventoryActionKeys.i04));
      await tester.pumpAndSettle();
      expect(find.text('Selected Group'), findsOneWidget);
      expect(find.byKey(InventoryActionKeys.i03), findsOneWidget);
    },
  );

  testWidgets('edits one named storage while retaining the combined total', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    harness.controller.active.ensureInventoryStorageLocation(
      'Calpheon City Storage',
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(
      find.byKey(InventoryActionKeys.storage('calpheon-city-storage')),
    );
    await tester.pump();
    final amount = find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb'));
    await tester.enterText(amount, '10.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final storage = harness.controller.active.inventoryStorage;
    expect(storage.quantityAt('calpheon-city-storage', 'Sunrise Herb'), 10000);
    expect(storage.quantityAt('unassigned', 'Sunrise Herb'), 3);
    expect(storage.totalFor('Sunrise Herb'), 10003);
    expect(
      harness.controller.active.state.value.inventory['Sunrise Herb'],
      10003,
    );
  });

  testWidgets('screenshot review does not mutate until save and can undo', (
    tester,
  ) async {
    final analysis = _analysis();
    final harness = InventoryTestHarness(pasteScreenshot: () async => analysis);
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    final before = harness.controller.active.state.value;

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    expect(find.text('Review storage screenshot'), findsOneWidget);
    expect(harness.controller.active.state.value, same(before));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.controller.active.state.value, same(before));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();

    final saved = harness.controller.active.inventoryStorage;
    expect(saved.selectedLocation.name, 'Calpheon City Storage');
    expect(saved.quantityAt('calpheon-city-storage', 'Sunrise Herb'), 1000);
    expect(saved.quantityAt('unassigned', 'Sunrise Herb'), 0);
    expect(harness.undoOffers, hasLength(1));

    await tester.runAsync(harness.undoOffers.single.undo);
    await tester.pumpAndSettle();
    expect(harness.controller.active.state.value.inventory, before.inventory);
    expect(
      InventoryStorageState.fromModeState(
        harness.controller.active.state.value,
      ).locations,
      hasLength(1),
    );
  });

  testWidgets('failed screenshot save restores every prior amount', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(),
      saveState: (_) async => throw StateError('disk unavailable'),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    final before = harness.controller.active.state.value;

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();

    expect(harness.controller.active.state.value, same(before));
    expect(harness.controller.active.state.value.inventory, before.inventory);
    expect(harness.undoOffers, isEmpty);
    expect(
      find.textContaining('Your previous amounts are unchanged'),
      findsOneWidget,
    );
  });

  testWidgets('a cropped grid uses the currently selected storage', (
    tester,
  ) async {
    late InventoryTestHarness harness;
    harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(suggestedLocationName: null),
    );
    harness.controller.active.ensureInventoryStorageLocation(
      'Calpheon City Storage',
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    final locationField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('inventory-import-location')),
        matching: find.byType(EditableText),
      ),
    );
    expect(locationField.controller.text, 'Calpheon City Storage');

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();
    expect(
      harness.controller.active.inventoryStorage.quantityAt(
        'calpheon-city-storage',
        'Sunrise Herb',
      ),
      1000,
    );
  });
}

InventoryScreenshotAnalysis _analysis({
  String? suggestedLocationName = 'Calpheon City Storage',
}) {
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
  return InventoryScreenshotAnalysis(
    screenshotPng: png,
    draft: InventoryScreenshotDraft(
      suggestedLocationName: suggestedLocationName,
      sourceWidth: 1,
      sourceHeight: 1,
      rows: <InventoryScreenshotRow>[
        InventoryScreenshotRow(
          slot: 1,
          crop: const InventoryScreenshotRect(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
          ),
          quantityText: '1K',
          quantity: 1000,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Sunrise Herb',
              confidence: 1,
              sharedArtwork: false,
            ),
          ],
          previewPng: png,
        ),
      ],
    ),
  );
}
