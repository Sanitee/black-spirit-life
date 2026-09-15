import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inventory_test_fixture.dart';

void main() {
  testWidgets('shows compact shared controls and grouped planner materials', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    expect(find.byKey(InventoryActionKeys.storageSelector), findsNothing);
    expect(find.byKey(InventoryActionKeys.addStorage), findsNothing);
    expect(find.byKey(InventoryActionKeys.renameStorage), findsNothing);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.byKey(InventoryActionKeys.filter('owned')), findsOneWidget);
    expect(
      find.byKey(InventoryActionKeys.filter('alchemyPlan')),
      findsOneWidget,
    );
    expect(
      find.byKey(InventoryActionKeys.filter('cookingPlan')),
      findsOneWidget,
    );
    expect(
      find.byKey(InventoryActionKeys.filter('processingPlan')),
      findsOneWidget,
    );
    expect(find.byKey(InventoryActionKeys.filter('all')), findsOneWidget);
    expect(find.byKey(InventoryActionKeys.i04), findsNothing);
    expect(find.text('Plants & farming'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'inventory-subsection:Plants & farming:Herbs & flowers',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Selected Group'), findsNothing);
    expect(find.byKey(InventoryActionKeys.emptyStorage), findsNothing);
  });

  testWidgets('edits one shared amount for every planner mode', (tester) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    final amount = find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb'));
    await tester.enterText(amount, '10.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Sunrise Herb'],
        10000,
      );
    }
  });

  testWidgets('screenshot review does not mutate until save and can undo', (
    tester,
  ) async {
    final analysis = _analysis();
    final harness = InventoryTestHarness(pasteScreenshot: () async => analysis);
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    final before = harness.controller.documentSnapshot;

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    expect(find.text('Review items'), findsOneWidget);
    expect(harness.controller.documentSnapshot, same(before));

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-close')),
    );
    await tester.pumpAndSettle();
    expect(harness.controller.documentSnapshot, same(before));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace current inventory'));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();

    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Sunrise Herb'],
        1000,
      );
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Silver Azalea'],
        isNull,
        reason:
            'Replace current inventory must remove items not in the review.',
      );
    }
    expect(harness.undoOffers, hasLength(1));

    await tester.runAsync(harness.undoOffers.single.undo);
    await tester.pumpAndSettle();
    expect(harness.controller.documentSnapshot, same(before));
  });

  testWidgets('failed screenshot save restores every prior amount', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(),
      saveState: (_) async => throw StateError('disk unavailable'),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    final before = harness.controller.documentSnapshot;

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();

    expect(harness.controller.documentSnapshot, same(before));
    expect(harness.undoOffers, isEmpty);
    expect(
      find.textContaining('Your previous amounts are unchanged'),
      findsOneWidget,
    );
  });

  testWidgets('recognition failure restores the screenshot controls', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => throw StateError('recognizer unavailable'),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    expect(find.textContaining('recognizer unavailable'), findsOneWidget);
    expect(
      find.byKey(InventoryActionKeys.pasteScreenshot).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('review removal is reversible before saving', (tester) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(includeSecondRow: true),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final firstRow = find.byKey(
      const ValueKey<String>('inventory-import-row-storage-r0c0'),
    );
    expect(firstRow, findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('inventory-import-remove-storage-r0c0'),
      ),
    );
    await tester.pumpAndSettle();
    expect(firstRow, findsNothing);
    expect(find.text('Undo removal'), findsOneWidget);

    await tester.tap(find.text('Undo removal'));
    await tester.pumpAndSettle();
    expect(firstRow, findsOneWidget);
  });

  testWidgets('a cropped grid saves into the shared Inventory', (tester) async {
    late InventoryTestHarness harness;
    harness = InventoryTestHarness(pasteScreenshot: () async => _analysis());
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saving to'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('inventory-import-location')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();
    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Sunrise Herb'],
        1003,
        reason: 'The recognized 1,000 must be added to the saved 3.',
      );
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Silver Azalea'],
        7,
        reason: 'A new screenshot must not erase unrelated owned items.',
      );
    }
  });

  testWidgets(
    'separate screenshot reviews accumulate by default and Replace stays explicit',
    (tester) async {
      var review = 0;
      final analyses = <InventoryScreenshotAnalysis>[
        _analysis(quantity: 1000, fingerprintCharacter: '1'),
        _analysis(quantity: 250, fingerprintCharacter: '2'),
        _analysis(quantity: 5, fingerprintCharacter: '3'),
      ];
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => analyses[review++],
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      Future<void> openAndSave({bool replace = false}) async {
        await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
        await tester.pumpAndSettle();
        if (replace) {
          await tester.tap(find.text('Replace current inventory'));
          await tester.pump();
        }
        await tester.tap(
          find.byKey(const ValueKey<String>('inventory-import-save')),
        );
        await tester.pumpAndSettle();
      }

      await openAndSave();
      await openAndSave();

      for (final mode in CraftMode.values) {
        final inventory = harness.controller.modes[mode]!.state.value.inventory;
        expect(
          inventory['Sunrise Herb'],
          1253,
          reason:
              'Independent review sessions must add 1,000 and 250 to the '
              'previously owned 3 instead of silently replacing it.',
        );
        expect(inventory['Silver Azalea'], 7);
      }

      await openAndSave(replace: true);

      for (final mode in CraftMode.values) {
        final inventory = harness.controller.modes[mode]!.state.value.inventory;
        expect(inventory['Sunrise Herb'], 5);
        expect(
          inventory['Silver Azalea'],
          isNull,
          reason:
              'The destructive behavior remains available only after the '
              'reviewer explicitly chooses Replace current inventory.',
        );
      }
    },
  );
}

InventoryScreenshotAnalysis _analysis({
  bool includeSecondRow = false,
  int quantity = 1000,
  String fingerprintCharacter = 'a',
}) {
  final png = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
  return InventoryScreenshotAnalysis(
    fileName: 'storage.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: const <String>['Sunrise Herb', 'Silver Azalea'],
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, fingerprintCharacter).join(),
      sourceWidth: 1,
      sourceHeight: 1,
      gridColumns: includeSecondRow ? 2 : 1,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        InventoryScreenshotRow(
          id: 'storage-r0c0',
          slotId: 'r0c0',
          row: 0,
          column: 0,
          crop: const InventoryScreenshotRect(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
          ),
          quantityText: quantity.toString(),
          quantity: quantity,
          quantitySuggested: null,
          quantityApproximate: false,
          quantityAssumedOne: false,
          quantityConfidence: 1,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Sunrise Herb',
              confidence: 1,
              sharedArtwork: false,
              grade: null,
            ),
          ],
          selectedName: 'Sunrise Herb',
          relevance: InventoryOcrMaterialRelevance.relevant,
          reviewRequired: false,
          reviewReasons: const <String>[],
          previewPng: png,
        ),
        if (includeSecondRow)
          InventoryScreenshotRow(
            id: 'storage-r0c1',
            slotId: 'r0c1',
            row: 0,
            column: 1,
            crop: const InventoryScreenshotRect(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
            ),
            quantityText: '2K',
            quantity: 2000,
            quantitySuggested: null,
            quantityApproximate: false,
            quantityAssumedOne: false,
            quantityConfidence: 1,
            matches: const <InventoryItemMatch>[
              InventoryItemMatch(
                name: 'Silver Azalea',
                confidence: .9,
                sharedArtwork: false,
                grade: null,
              ),
            ],
            selectedName: null,
            relevance: InventoryOcrMaterialRelevance.relevant,
            reviewRequired: true,
            reviewReasons: const <String>['Confirm the suggested item.'],
            previewPng: png,
          ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}
