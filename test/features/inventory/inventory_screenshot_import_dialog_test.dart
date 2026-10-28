import 'dart:async';
import 'dart:convert';

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inventory_test_fixture.dart';

void main() {
  testWidgets(
    'review is compact and orders likely alternatives without duplicates',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _analysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saving to'), findsNothing);
      expect(find.text('Replace current inventory'), findsOneWidget);
      expect(find.text('Add to inventory'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('inventory-import-add-mode')),
            )
            .selected,
        isTrue,
        reason: 'A new storage screenshot must add by default.',
      );
      expect(find.text('Add screenshot'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Choose another'), findsNothing);
      final frame = tester.getSize(
        find.byKey(const ValueKey<String>('inventory-import-dialog-frame')),
      );
      expect(frame.width, lessThanOrEqualTo(980));
      expect(frame.height, lessThanOrEqualTo(860));
      final actions = tester.getRect(
        find.byKey(const ValueKey<String>('inventory-import-actions')),
      );
      final firstScreenshot = tester.getRect(
        find.byKey(
          const ValueKey<String>('inventory-import-screenshot-section-0'),
        ),
      );
      expect(firstScreenshot.top - actions.bottom, inInclusiveRange(10, 24));
      expect(
        tester.getSize(
          find.byKey(
            const ValueKey<String>('inventory-import-preview-quality-row'),
          ),
        ),
        const Size(60, 48),
      );

      expect(find.text('Screenshot'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('inventory-import-screenshot-bookmarks'),
        ),
        findsNothing,
      );
      final grid = tester.widget<SliverGrid>(
        find.byKey(const ValueKey<String>('inventory-import-grid-0')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      expect(delegate.mainAxisExtent, 72);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('inventory-import-dialog-frame'),
          ),
          matching: find.textContaining('% match'),
        ),
        findsNothing,
      );

      final qualityChooser = tester.widget<AppSearchSelect<String>>(
        find.byKey(const ValueKey<String>('inventory-import-item-quality-row')),
      );
      expect(qualityChooser.value, 'Special Sunflower');
      expect(qualityChooser.items, <String>['Special Sunflower', 'Sunflower']);
      expect(qualityChooser.searchItems, contains('Banana'));
      expect(qualityChooser.items, isNot(contains('Milk')));
      final qualityEditable = find.descendant(
        of: find.byKey(
          const ValueKey<String>('inventory-import-item-quality-row'),
        ),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(qualityEditable).controller.text,
        'Special Sunflower',
      );
      expect(tester.getSize(qualityEditable).width, greaterThan(120));

      final milkChooser = tester.widget<AppSearchSelect<String>>(
        find.byKey(const ValueKey<String>('inventory-import-item-milk-row')),
      );
      expect(milkChooser.value, 'Milk');
      expect(milkChooser.items.first, 'Milk');
      expect(milkChooser.items, isNot(contains('Special Sunflower')));
      final milkEditable = find.descendant(
        of: find.byKey(
          const ValueKey<String>('inventory-import-item-milk-row'),
        ),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(milkEditable).controller.text, 'Milk');
      expect(tester.getSize(milkEditable).width, greaterThan(120));
    },
  );

  testWidgets('review switches to one readable column on a narrow window', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(),
    );
    await pumpInventory(tester, harness, size: const Size(700, 820));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(
      find.byKey(const ValueKey<String>('inventory-import-grid-0')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous rows auto-fill in descending BDO item-ID order', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _orderedAnalysis(),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    AppSearchSelect<String> chooser(String id) =>
        tester.widget<AppSearchSelect<String>>(
          find.byKey(ValueKey<String>('inventory-import-item-$id')),
        );

    expect(chooser('ordered-0').value, 'Candidate 900');
    expect(chooser('ordered-1').value, 'Candidate 880');
    expect(
      chooser('ordered-2').value,
      'Candidate 700',
      reason: 'Candidate 890 would break the descending row-major order.',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-item-ordered-0')),
    );
    await tester.pumpAndSettle();
    final candidate850 = find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text('Candidate 850'),
    );
    await tester.tap(candidate850.last);
    await tester.pumpAndSettle();

    expect(chooser('ordered-0').value, 'Candidate 850');
    expect(chooser('ordered-1').value, 'Candidate 800');
    expect(
      chooser('ordered-1').items,
      contains('Candidate 880'),
      reason:
          'A same-artwork automatic alternative must remain mouse-selectable; '
          'the item-ID bounds constrain automatic reflow, not manual review.',
    );
    expect(chooser('ordered-2').value, 'Candidate 700');
  });

  testWidgets(
    'Dried Fish item-ID order spans alternating authoritative artwork families',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _driedFishAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('fish-clownfish').value, 'Dried Clownfish');
      expect(chooser('fish-grouper').value, 'Dried Grouper');
      expect(chooser('fish-maomao').value, 'Dried Maomao');
      expect(
        chooser('fish-grouper').items,
        containsAll(<String>[
          'Dried Grouper',
          'Dried Maomao',
          'Dried Surfperch',
          'Dried Siganid',
        ]),
      );
      expect(
        chooser('fish-grouper').items,
        isNot(contains('Dried Bluefish')),
        reason:
            'The unopened dropdown must show the matching artwork family, '
            'not every item in the broad Dried Fish catalogue group.',
      );
      expect(
        chooser('fish-grouper').searchItems,
        contains('Dried Bluefish'),
        reason:
            'Typing must still search the complete planner catalogue when '
            'the visual family is not the intended item.',
      );
      expect(chooser('fish-surfperch').value, 'Dried Surfperch');
      expect(
        chooser('fish-bluefish').value,
        'Dried Bluefish',
        reason:
            'Spotted Barbel 8639 cannot follow Clownfish 8602 in the '
            'authoritative Dried Fish order.',
      );
      expect(chooser('fish-siganid').value, 'Dried Siganid');
      expect(
        chooser('fish-nibbler').value,
        'Dried Nibbler',
        reason:
            'Amur Minnow 8642 cannot appear after Siganid 8572 even though '
            'it shares Nibbler artwork.',
      );
      expect(chooser('fish-golden-thread').value, 'Dried Golden-thread');
    },
  );

  testWidgets(
    'Dried Fish reflow keeps correct candidates when the native top artwork is wrong',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async =>
            _driedFishAnalysis(confusedArtworkCandidates: true),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('fish-bluefish').value, 'Dried Bluefish');
      expect(chooser('fish-bluefish').items, contains('Dried Bluefish'));
      expect(chooser('fish-siganid').value, 'Dried Siganid');
      expect(chooser('fish-nibbler').value, 'Dried Nibbler');
      expect(chooser('fish-nibbler').items, contains('Dried Nibbler'));
      expect(chooser('fish-golden-thread').value, 'Dried Golden-thread');
      expect(
        chooser('fish-bluefish').items.first,
        'Dried Bluefish',
        reason:
            'Once the preceding Auto Arrange rows establish the descending '
            'item-ID run, a wrong small-icon family must not hide the next '
            'valid fish from the mouse dropdown.',
      );
    },
  );

  testWidgets(
    'observed fish order puts valid lower IDs before impossible lookalikes',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _realisticFishDropdownAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(
        chooser('fish-bluefish-dropdown').value,
        'Dried Silver Stripe Round Herring',
      );
      expect(
        chooser('fish-bluefish-dropdown').items.take(2),
        <String>['Dried Silver Stripe Round Herring', 'Dried Bluefish'],
        reason:
            'The current automatic value remains visible first, but the next '
            'mouse choice must honor Surfperch 8574 -> Bluefish 8573 instead '
            'of listing visually similar higher IDs that are impossible here.',
      );
      expect(chooser('fish-nibbler-dropdown').value, 'Dried Notch Jaw');
      expect(chooser('fish-nibbler-dropdown').items.take(2), <String>[
        'Dried Notch Jaw',
        'Dried Nibbler',
      ]);
    },
  );

  testWidgets('a selected yellow row survives dialog reconciliation', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _singleReviewAnalysis(
        _row(
          id: 'napa-cabbage',
          column: 0,
          selectedName: 'Napa Cabbage',
          quantity: 20636,
          itemSuggestionUncertain: true,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Napa Cabbage',
              confidence: .927,
              sharedArtwork: true,
              grade: 0,
              itemId: 820120,
              artworkKey: 'app:napa-cabbage',
            ),
            InventoryItemMatch(
              name: 'Special Napa Cabbage',
              confidence: .92,
              sharedArtwork: true,
              grade: 0,
              itemId: 820121,
              artworkKey: 'app:napa-cabbage',
            ),
          ],
          previewPng: _pixelPng(),
        ),
        plannerItemNames: const <String>[
          'Napa Cabbage',
          'Special Napa Cabbage',
        ],
      ),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final chooser = tester.widget<AppSearchSelect<String>>(
      find.byKey(const ValueKey<String>('inventory-import-item-napa-cabbage')),
    );
    expect(chooser.value, 'Napa Cabbage');
    expect(
      _fieldFrameAlpha(tester, 'item-napa-cabbage'),
      greaterThan(.5),
      reason: 'A filled but genuinely uncertain answer must be visibly yellow.',
    );
    final paintedFrame = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>(
                'inventory-import-error-item-napa-cabbage-frame',
              ),
            ),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      paintedFrame.position,
      DecorationPosition.foreground,
      reason: 'The opaque search field must not paint over its amber frame.',
    );
  });

  testWidgets(
    'manual correction immediately clears an uncertain yellow frame',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _singleReviewAnalysis(
          _row(
            id: 'manual-shared-fish',
            column: 0,
            selectedName: 'Dried Maomao',
            quantity: 8104,
            itemSuggestionUncertain: true,
            matches: const <InventoryItemMatch>[
              InventoryItemMatch(
                name: 'Dried Maomao',
                confidence: .89,
                sharedArtwork: true,
                grade: 0,
                itemId: 8577,
                artworkKey: 'helper:shared-fish',
                orderGroupKey: 'catalog:dried-fish',
              ),
              InventoryItemMatch(
                name: 'Dried Surfperch',
                confidence: .89,
                sharedArtwork: true,
                grade: 0,
                itemId: 8574,
                artworkKey: 'helper:shared-fish',
                orderGroupKey: 'catalog:dried-fish',
              ),
            ],
            previewPng: _pixelPng(),
          ),
          plannerItemNames: const <String>['Dried Maomao', 'Dried Surfperch'],
        ),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      expect(
        _fieldFrameAlpha(tester, 'item-manual-shared-fish'),
        greaterThan(.5),
      );

      await _chooseReviewItem(tester, 'manual-shared-fish', 'Dried Surfperch');

      expect(
        _fieldFrameAlpha(tester, 'item-manual-shared-fish'),
        closeTo(0, .001),
        reason: 'The user-confirmed answer must stop looking uncertain.',
      );
    },
  );

  testWidgets('decisive pixels stay neutral even with dropdown alternatives', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _singleReviewAnalysis(
        _row(
          id: 'decisive-with-alternatives',
          column: 0,
          selectedName: 'Milk',
          quantity: 500,
          itemSuggestionUncertain: true,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Milk',
              confidence: .84,
              sourceVisualConfidence: .96,
              sharedArtwork: false,
              grade: 0,
              itemId: 9003,
            ),
            InventoryItemMatch(
              name: 'Cream',
              confidence: .83,
              sourceVisualConfidence: .78,
              sharedArtwork: false,
              grade: 0,
              itemId: 9004,
            ),
          ],
          previewPng: _pixelPng(),
        ),
        plannerItemNames: const <String>['Milk', 'Cream'],
      ),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final chooser = tester.widget<AppSearchSelect<String>>(
      find.byKey(
        const ValueKey<String>(
          'inventory-import-item-decisive-with-alternatives',
        ),
      ),
    );
    expect(chooser.value, 'Milk');
    expect(chooser.items, contains('Cream'));
    expect(
      _fieldFrameAlpha(tester, 'item-decisive-with-alternatives'),
      closeTo(0, .001),
      reason:
          'Alternatives in the dropdown do not imply uncertainty when the '
          'selected artwork is decisive.',
    );
  });

  testWidgets('Big mushroom gaps preserve the stronger visual selection', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _bigMushroomAnalysis(),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    AppSearchSelect<String> chooser(String id) =>
        tester.widget<AppSearchSelect<String>>(
          find.byKey(ValueKey<String>('inventory-import-item-$id')),
        );

    expect(
      chooser('big-emperor').value,
      'Big Emperor Mushroom',
      reason:
          'A weaker, higher-ID Big Ancient fallback is absent from the '
          'screenshot and must not replace the stronger Big Emperor visual '
          'selection merely to close an item-ID gap.',
    );
    expect(chooser('big-tiger').value, 'Big Tiger Mushroom');
    expect(chooser('big-sky').value, 'Big Sky Mushroom');
    expect(chooser('big-cloud').value, 'Big Cloud Mushroom');
  });

  testWidgets(
    'earlier manual fish choice releases confident source selections and '
    'reflows every later non-fixed row',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async =>
            _driedFishAnalysis(confidentLaterSelections: true),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('fish-grouper').value, 'Dried Grouper');
      expect(chooser('fish-maomao').value, 'Dried Maomao');
      expect(
        chooser('fish-grouper').items,
        contains('Dried Maomao'),
        reason:
            'A name held only by a later non-fixed source selection must '
            'remain available to an earlier row.',
      );

      await _chooseReviewItem(tester, 'fish-golden-thread', 'Dried Saurel');
      expect(chooser('fish-golden-thread').value, 'Dried Saurel');

      await _chooseReviewItem(tester, 'fish-grouper', 'Dried Maomao');

      expect(chooser('fish-grouper').value, 'Dried Maomao');
      expect(chooser('fish-maomao').value, 'Dried Surfperch');
      expect(chooser('fish-surfperch').value, 'Dried Siganid');
      expect(chooser('fish-bluefish').value, 'Dried Golden-thread');
      expect(
        chooser('fish-siganid').value,
        isNull,
        reason:
            'A row with no candidate left inside both manual ID bounds must '
            'be cleared instead of keeping its stale inference.',
      );
      expect(chooser('fish-nibbler').value, 'Dried Filefish');
      expect(
        chooser('fish-golden-thread').value,
        'Dried Saurel',
        reason:
            'A manually fixed later row must survive every inferred reflow.',
      );
    },
  );

  testWidgets(
    'an earlier automatic fish owner stays mouse-selectable and reflows',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _herringAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('herring-earlier').value, 'Dried Round Herring');
      expect(
        chooser('herring-target').items,
        containsAll(<String>[
          'Dried Round Herring',
          'Dried Silver Stripe Round Herring',
        ]),
        reason:
            'An automatic owner must never remove the other identical-icon '
            'herring from a mouse-accessible dropdown.',
      );

      await _chooseReviewItem(tester, 'herring-target', 'Dried Round Herring');

      expect(chooser('herring-earlier').value, 'Dried Whiting');
      expect(chooser('herring-target').value, 'Dried Round Herring');
      expect(chooser('herring-later').value, 'Dried Grunt');
    },
  );

  testWidgets('one ambiguous salt slot prefers the structured ingredient', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _saltAnalysis(slotCount: 1),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final chooser = tester.widget<AppSearchSelect<String>>(
      find.byKey(const ValueKey<String>('inventory-import-item-salt-0')),
    );
    expect(chooser.value, 'Salt');
    expect(chooser.items, containsAll(<String>['Salt', 'Sun-Dried Salt']));
  });

  testWidgets(
    'correct Barley Flour match survives lower salt fallback candidates',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _barleyFlourWithSaltFallbackAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      final chooser = tester.widget<AppSearchSelect<String>>(
        find.byKey(
          const ValueKey<String>('inventory-import-item-barley-flour'),
        ),
      );
      expect(chooser.value, 'Barley Flour');
      expect(chooser.items.first, 'Barley Flour');
      expect(
        chooser.searchItems,
        containsAll(<String>['Salt', 'Sun-Dried Salt']),
        reason:
            'The fallback candidates remain searchable for correction, but '
            'must not activate the singleton-salt default.',
      );
    },
  );

  testWidgets('two ambiguous salt slots keep both distinct items', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _saltAnalysis(slotCount: 2),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    AppSearchSelect<String> chooser(String id) =>
        tester.widget<AppSearchSelect<String>>(
          find.byKey(ValueKey<String>('inventory-import-item-$id')),
        );
    expect(chooser('salt-0').value, 'Sun-Dried Salt');
    expect(chooser('salt-1').value, 'Salt');
  });

  testWidgets(
    'singleton shared bottles prefer the exact structured recipe ingredient',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _sharedBottleAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('storms-bottle').value, 'Oil of Storms');
      expect(
        chooser('storms-bottle').items,
        containsAll(<String>['Oil of Storms', 'Bottle of Turbid Water']),
        reason:
            'The identical bottle remains mouse-selectable even though the '
            'real recipe ingredient is the safer singleton default.',
      );
      expect(chooser('regeneration-bottle').value, 'Oil of Regeneration');
      expect(
        chooser('regeneration-bottle').items,
        containsAll(<String>['Oil of Regeneration', 'Bottle of Clean Water']),
      );
    },
  );

  testWidgets(
    'automatic water suggestions prefer oils but manual water choices survive',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async =>
            _sharedBottleAnalysis(preselectWater: true),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));
      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();
      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );
      expect(chooser('storms-bottle').value, 'Oil of Storms');
      expect(chooser('regeneration-bottle').value, 'Oil of Regeneration');
      await _chooseReviewItem(
        tester,
        'storms-bottle',
        'Bottle of Turbid Water',
      );
      await _chooseReviewItem(
        tester,
        'regeneration-bottle',
        'Bottle of Clean Water',
      );
      expect(chooser('storms-bottle').value, 'Bottle of Turbid Water');
      expect(chooser('regeneration-bottle').value, 'Bottle of Clean Water');
    },
  );

  testWidgets('two shared bottle stacks retain both water and oil identities', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async =>
          _sharedBottleAnalysis(preselectWater: true, duplicateStorms: true),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    String? selected(String id) => tester
        .widget<AppSearchSelect<String>>(
          find.byKey(ValueKey<String>('inventory-import-item-$id')),
        )
        .value;
    expect(
      {selected('storms-bottle'), selected('storms-second')},
      {'Bottle of Turbid Water', 'Oil of Storms'},
    );
    expect(selected('regeneration-bottle'), 'Oil of Regeneration');
  });

  testWidgets(
    'long selected item wraps to two lines without moving amount or delete',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _longSelectedNameAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      Finder item(String id) =>
          find.byKey(ValueKey<String>('inventory-import-item-$id'));
      Finder amount(String id) =>
          find.byKey(ValueKey<String>('inventory-import-amount-$id'));
      Finder remove(String id) =>
          find.byKey(ValueKey<String>('inventory-import-remove-$id'));
      Finder row(String id) =>
          find.byKey(ValueKey<String>('inventory-import-row-$id'));

      final longEditable = find.descendant(
        of: item('long-result'),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(longEditable).controller.text,
        'Steaming Hot Grilled Bird Meat',
      );
      expect(tester.widget<EditableText>(longEditable).maxLines, 2);
      expect(tester.getSize(item('long-result')).height, 44);
      expect(tester.getSize(item('short-result')).height, 44);

      final longRow = tester.getRect(row('long-result'));
      final shortRow = tester.getRect(row('short-result'));
      final longAmount = tester.getRect(amount('long-result'));
      final shortAmount = tester.getRect(amount('short-result'));
      final longRemove = tester.getRect(remove('long-result'));
      final shortRemove = tester.getRect(remove('short-result'));
      expect(longRow.height, 72);
      expect(shortRow.height, 72);
      expect(longAmount.size, shortAmount.size);
      expect(longRemove.size, shortRemove.size);
      expect(
        longRow.right - longAmount.right,
        closeTo(shortRow.right - shortAmount.right, .01),
      );
      expect(
        longRow.right - longRemove.right,
        closeTo(shortRow.right - shortRemove.right, .01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared-artwork fallback orders blood and meat independently', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _sharedArtworkFallbackAnalysis(),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    AppSearchSelect<String> chooser(String id) =>
        tester.widget<AppSearchSelect<String>>(
          find.byKey(ValueKey<String>('inventory-import-item-$id')),
        );

    expect(chooser('blood-0').value, 'Blood 900');
    expect(chooser('blood-1').value, 'Blood 880');
    expect(
      chooser('meat-0').value,
      'Meat 1200',
      reason: 'A new artwork family must not inherit the blood ID ceiling.',
    );
    expect(chooser('meat-1').value, 'Meat 1150');
  });

  testWidgets(
    'blood:all reflows across artwork families without widening a dropdown',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _globalBloodOrderAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('group-two-first').value, 'Goat Blood');
      expect(chooser('group-two-second').value, 'Llama Blood');
      expect(
        chooser('marmot-family').value,
        'Marmot Blood',
        reason:
            'The descending blood:all ceiling must continue when the exact '
            'visual bottle family changes.',
      );
      expect(
        chooser('marmot-family').items,
        containsAll(<String>['Marmot Blood', 'Weasel Blood', 'Fox Blood']),
      );
      expect(
        chooser('marmot-family').items,
        isNot(contains('Goat Blood')),
        reason:
            'The unopened dropdown must remain restricted to this exact '
            'shared artwork family.',
      );
      expect(chooser('marmot-family').searchItems, contains('Goat Blood'));

      await _chooseReviewItem(tester, 'group-two-first', 'Llama Blood');

      expect(chooser('group-two-first').value, 'Llama Blood');
      expect(chooser('group-two-second').value, 'Ox Blood');
      expect(
        chooser('marmot-family').value,
        'Fox Blood',
        reason:
            'A manual earlier choice must immediately recalculate every '
            'later provisional blood row, including a different icon family.',
      );
    },
  );

  testWidgets(
    'real blood run restores Waragon and exposes indistinguishable Raccoon',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _realBloodGapAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('blood-goat').value, 'Goat Blood');
      expect(chooser('blood-llama').value, 'Llama Blood');
      expect(chooser('blood-waragon').value, 'Waragon Blood');
      expect(chooser('blood-wolf').value, 'Wolf Blood');
      expect(chooser('blood-bear').value, 'Bear Blood');
      expect(
        chooser('blood-raccoon').value,
        'Weasel Blood',
        reason:
            'The current-client artwork is pixel-identical here, so the '
            'automatic value is only an order-based best guess.',
      );
      expect(chooser('blood-worm').value, 'Worm Blood');
      expect(chooser('blood-fox').value, 'Fox Blood');
      expect(chooser('blood-sheep').value, 'Sheep Blood');
      expect(chooser('blood-deer').value, 'Deer Blood');
      expect(chooser('blood-waragon').items, contains('Waragon Blood'));
      expect(chooser('blood-raccoon').items, contains('Raccoon Blood'));
      expect(
        tester
            .widget<AppSurface>(
              find.byKey(
                const ValueKey<String>('inventory-import-row-blood-raccoon'),
              ),
            )
            .tone,
        AppSurfaceTone.warning,
      );

      await _chooseReviewItem(tester, 'blood-raccoon', 'Raccoon Blood');
      expect(chooser('blood-raccoon').value, 'Raccoon Blood');
      expect(
        tester
            .widget<AppSurface>(
              find.byKey(
                const ValueKey<String>('inventory-import-row-blood-raccoon'),
              ),
            )
            .tone,
        AppSurfaceTone.neutral,
      );
    },
  );

  testWidgets(
    'visual hide and sap families use pixels before canonical item order',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _visualMaterialSequenceAnalysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      AppSearchSelect<String> chooser(String id) =>
          tester.widget<AppSearchSelect<String>>(
            find.byKey(ValueKey<String>('inventory-import-item-$id')),
          );

      expect(chooser('hide-fox').value, 'Fox Hide');
      expect(
        chooser('hide-fox').items.take(2),
        containsAll(<String>['Fox Hide', 'Weasel Hide']),
      );
      expect(chooser('sap-elder').value, 'Elder Tree Sap');
      expect(chooser('sap-acacia').value, 'Acacia Sap');
      expect(chooser('sap-pine').value, 'Pine Sap');
      expect(chooser('sap-maple').value, 'Maple Sap');
      expect(chooser('sap-ash').value, 'Ash Sap');
    },
  );

  testWidgets('review close control stays pinned to the modal top-right', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(),
    );
    await pumpInventory(
      tester,
      harness,
      size: const Size(1500, 940),
      textScaler: const TextScaler.linear(2),
    );

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final frame = tester.getRect(
      find.byKey(const ValueKey<String>('inventory-import-dialog-frame')),
    );
    final close = tester.getRect(
      find.byKey(const ValueKey<String>('inventory-import-close')),
    );

    expect(close.top - frame.top, inInclusiveRange(10, 20));
    expect(frame.right - close.right, inInclusiveRange(10, 20));
  });

  testWidgets('review header moves the native application window', (
    tester,
  ) async {
    const channel = MethodChannel('com.bdocraftplanner.flutter/window');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    final frameFinder = find.byKey(
      const ValueKey<String>('inventory-import-dialog-frame'),
    );
    final before = tester.getTopLeft(frameFinder);
    await tester.drag(
      find.byKey(const ValueKey<String>('inventory-import-drag-region')),
      const Offset(-90, -45),
    );
    await tester.pump();
    final after = tester.getTopLeft(frameFinder);

    expect(calls, contains('beginDrag'));
    expect(after, before);
    expect(
      find.byKey(const ValueKey<String>('inventory-import-close')),
      findsOneWidget,
    );
  });

  testWidgets('item-ID ordering never replaces confident unrelated OCR items', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _unrelatedIdAnalysis(),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();

    AppSearchSelect<String> chooser(String id) =>
        tester.widget<AppSearchSelect<String>>(
          find.byKey(ValueKey<String>('inventory-import-item-$id')),
        );

    expect(chooser('fire-flower').value, 'Special Fire Flake Flower');
    expect(chooser('mineral-water').value, 'Mineral Water');
    expect(chooser('olive').value, 'Olive');
    expect(chooser('muddy-water').value, 'Bag of Muddy Water');
    expect(chooser('muddy-water').items.take(2), <String>[
      'Bag of Muddy Water',
      'Thuja Plank',
    ]);
    final muddyRow = tester.widget<AppSurface>(
      find.byKey(const ValueKey<String>('inventory-import-row-muddy-water')),
    );
    expect(muddyRow.tone, AppSurfaceTone.warning);
  });

  testWidgets(
    'typing keeps focus and the enlarged crop shows the full amount',
    (tester) async {
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => _analysis(),
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();

      final itemField = find.descendant(
        of: find.byKey(
          const ValueKey<String>('inventory-import-item-quality-row'),
        ),
        matching: find.byType(EditableText),
      );
      await tester.tap(itemField);
      await tester.enterText(itemField, 'S');
      await tester.pump();
      expect(tester.widget<EditableText>(itemField).focusNode.hasFocus, isTrue);
      await tester.enterText(itemField, 'Sp');
      await tester.pump();
      expect(tester.widget<EditableText>(itemField).controller.text, 'Sp');
      expect(tester.widget<EditableText>(itemField).focusNode.hasFocus, isTrue);

      final amountField = find.descendant(
        of: find.byKey(
          const ValueKey<String>('inventory-import-amount-milk-row'),
        ),
        matching: find.byType(EditableText),
      );
      await tester.tap(amountField);
      await tester.enterText(amountField, '6');
      await tester.pump();
      expect(
        tester.widget<EditableText>(amountField).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(amountField, '65');
      await tester.pump();
      await tester.enterText(amountField, '656400');
      await tester.pump();
      expect(
        tester.widget<EditableText>(amountField).controller.text,
        '656.400',
      );
      expect(
        tester.widget<EditableText>(amountField).focusNode.hasFocus,
        isTrue,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('inventory-import-preview-button-quality-row'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Visible in screenshot'), findsOneWidget);
      expect(find.text('656.4K'), findsOneWidget);
      expect(find.text('Full amount'), findsOneWidget);
      expect(find.text('656.400'), findsWidgets);
      final enlarged = tester.widget<Image>(
        find.byKey(
          const ValueKey<String>('inventory-import-preview-large-quality-row'),
        ),
      );
      expect(enlarged.fit, BoxFit.contain);
    },
  );

  testWidgets('save reveals and focuses the first incomplete slot', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _incompleteAnalysis(),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('inventory-import-save')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose the item and enter its amount.'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('inventory-import-error-item-empty-row-');
      }),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('inventory-import-error-amount-empty-row-');
      }),
      findsOneWidget,
    );
    final itemEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('inventory-import-item-empty-row'),
        ),
        matching: find.byType(EditableText),
      ),
    );
    expect(itemEditable.focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'Add screenshot shows progress until the next recognition finishes',
    (tester) async {
      final pending = Completer<InventoryScreenshotAnalysis?>();
      var screenshot = 0;
      final harness = InventoryTestHarness(
        pasteScreenshot: () {
          if (screenshot++ == 0) {
            return Future<InventoryScreenshotAnalysis?>.value(_analysis());
          }
          return pending.future;
        },
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();
      final addButton = find.byKey(
        const ValueKey<String>('inventory-import-add-screenshot'),
      );
      await tester.tap(addButton);
      await tester.pump();

      expect(
        find.descendant(
          of: addButton,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      pending.complete(
        _analysis(fingerprintCharacter: 'd', idSuffix: '-second'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screenshot'), findsNWidgets(2));
      expect(
        find.descendant(
          of: addButton,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('numbered screenshot bookmarks jump through a long review', (
    tester,
  ) async {
    var screenshot = 0;
    final harness = InventoryTestHarness(
      pasteScreenshot: () async => _analysis(
        fingerprintCharacter: String.fromCharCode(
          'a'.codeUnitAt(0) + screenshot,
        ),
        idSuffix: '-$screenshot',
      ),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pumpAndSettle();
    screenshot += 1;
    for (var index = 1; index < 8; index += 1) {
      await tester.tap(
        find.byKey(const ValueKey<String>('inventory-import-add-screenshot')),
      );
      await tester.pumpAndSettle();
      screenshot += 1;
    }

    expect(
      find.byKey(
        const ValueKey<String>('inventory-import-screenshot-bookmarks'),
      ),
      findsOneWidget,
    );
    for (var index = 0; index < 8; index += 1) {
      expect(
        find.byKey(
          ValueKey<String>('inventory-import-screenshot-bookmark-$index'),
        ),
        findsOneWidget,
      );
    }
    final rows = tester.widget<CustomScrollView>(
      find.byKey(const ValueKey<String>('inventory-import-rows')),
    );
    expect(rows.controller!.offset, 0);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('inventory-import-screenshot-bookmark-7'),
      ),
    );
    await tester.pumpAndSettle();

    expect(rows.controller!.offset, greaterThan(0));
    final viewport = tester.getRect(
      find.byKey(const ValueKey<String>('inventory-import-rows')),
    );
    final lastSection = tester.getRect(
      find.byKey(
        const ValueKey<String>('inventory-import-screenshot-section-7'),
      ),
    );
    expect(viewport.overlaps(lastSection), isTrue);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('inventory-import-screenshot-bookmark-0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(rows.controller!.offset, closeTo(0, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'separate screenshot sections keep duplicate items reviewable and total them',
    (tester) async {
      final second = _analysis(
        fingerprintCharacter: 'd',
        idSuffix: '-second',
        qualityQuantity: 400,
        milkQuantity: 500,
      );
      var screenshot = 0;
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => screenshot++ == 0 ? _analysis() : second,
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('inventory-import-add-screenshot')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Screenshot'), findsNWidgets(2));
      expect(
        find.byKey(
          const ValueKey<String>('inventory-import-item-s1-quality-row-second'),
        ),
        findsOneWidget,
      );
      expect(find.text('Special Sunflower'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey<String>('inventory-import-save')),
      );
      await tester.pumpAndSettle();

      for (final mode in CraftMode.values) {
        final inventory = harness.controller.modes[mode]!.state.value.inventory;
        expect(inventory['Special Sunflower'], 656800);
        expect(inventory['Milk'], 175000);
      }
    },
  );
}

InventoryScreenshotAnalysis _analysis({
  String fingerprintCharacter = 'a',
  String idSuffix = '',
  int qualityQuantity = 656400,
  int milkQuantity = 174500,
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
    plannerItemNames: const <String>[
      'Special Sunflower',
      'Sunflower',
      'Milk',
      'Banana',
    ],
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, fingerprintCharacter).join(),
      sourceWidth: 1,
      sourceHeight: 1,
      gridColumns: 2,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'quality-row$idSuffix',
          column: 0,
          selectedName: 'Special Sunflower',
          quantity: qualityQuantity,
          quantityText: qualityQuantity == 656400
              ? '656.4K'
              : '$qualityQuantity',
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Special Sunflower',
              confidence: .98,
              sharedArtwork: false,
              grade: 2,
            ),
            InventoryItemMatch(
              name: 'Sunflower',
              confidence: .88,
              sharedArtwork: false,
              grade: 0,
            ),
          ],
          previewPng: png,
        ),
        _row(
          id: 'milk-row$idSuffix',
          column: 1,
          selectedName: 'Milk',
          quantity: milkQuantity,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Milk',
              confidence: .99,
              sharedArtwork: false,
              grade: 0,
            ),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _orderedAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Candidate 900': 900,
    'Candidate 880': 880,
    'Candidate 850': 850,
    'Candidate 800': 800,
    'Candidate 700': 700,
    'Candidate 890': 890,
  };
  InventoryItemMatch match(String name, double confidence) =>
      InventoryItemMatch(
        name: name,
        confidence: confidence,
        sharedArtwork: true,
        grade: 0,
        itemId: ids[name],
        artworkKey: 'icons/items/fish-family.webp',
      );
  return InventoryScreenshotAnalysis(
    fileName: 'ordered.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'b').join(),
      sourceWidth: 1,
      sourceHeight: 1,
      gridColumns: 3,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'ordered-0',
          column: 0,
          selectedName: null,
          quantity: 1,
          matches: <InventoryItemMatch>[
            match('Candidate 900', .96),
            match('Candidate 850', .95),
          ],
          previewPng: png,
        ),
        _row(
          id: 'ordered-1',
          column: 1,
          selectedName: null,
          quantity: 2,
          matches: <InventoryItemMatch>[
            match('Candidate 880', .97),
            match('Candidate 800', .95),
          ],
          previewPng: png,
        ),
        _row(
          id: 'ordered-2',
          column: 2,
          selectedName: null,
          quantity: 3,
          matches: <InventoryItemMatch>[
            match('Candidate 890', .99),
            match('Candidate 700', .94),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _driedFishAnalysis({
  bool confidentLaterSelections = false,
  bool confusedArtworkCandidates = false,
}) {
  final png = _pixelPng();
  const ids = <String, int>{
    'Dried Common Minnow': 8643,
    'Dried Amur Minnow': 8642,
    'Dried Spotted Barbel': 8639,
    'Dried Mackerel Pike': 8635,
    'Dried Clownfish': 8602,
    'Dried Grouper': 8584,
    'Dried Maomao': 8577,
    'Dried Surfperch': 8574,
    'Dried Bluefish': 8573,
    'Dried Siganid': 8572,
    'Dried Nibbler': 8571,
    'Dried Golden-thread': 8570,
    'Dried Filefish': 8534,
    'Dried Saurel': 8509,
  };
  const clownfishArtwork =
      'icons/items/eb0498bb277302587fc449335e55dc2ccfb43caa41c868fa6d88272cb57a605e.webp';
  const genericFishArtwork =
      'icons/items/149a63971399c8d9a3b45cec715266de7389fc18401f791054e2fae0ab58018d.webp';
  const redFishArtwork =
      'icons/items/ff47e9b1b62138e92c5141db1ecc37a7505668f5fc0ee608d42a436856499206.webp';
  const paleFishArtwork =
      'icons/items/c45c23e66db2e04b013e6f3e3778f74b089b3db62166b02e2037b83a0d6bfe40.webp';

  InventoryItemMatch match(
    String name,
    String artwork, [
    double confidence = .96,
  ]) => InventoryItemMatch(
    name: name,
    confidence: confidence,
    sharedArtwork: true,
    grade: 0,
    itemId: ids[name],
    artworkKey: artwork,
    orderGroupKey: 'dried-fish',
  );

  List<InventoryItemMatch> genericFish() => <InventoryItemMatch>[
    match('Dried Common Minnow', genericFishArtwork, .99),
    match('Dried Grouper', genericFishArtwork, .98),
    match('Dried Maomao', genericFishArtwork, .97),
    match('Dried Surfperch', genericFishArtwork, .96),
    match('Dried Siganid', genericFishArtwork, .95),
  ];

  List<InventoryItemMatch> redFish() => <InventoryItemMatch>[
    match(
      'Dried Spotted Barbel',
      confusedArtworkCandidates ? genericFishArtwork : redFishArtwork,
      .99,
    ),
    match('Dried Bluefish', redFishArtwork, .98),
    match('Dried Golden-thread', redFishArtwork, .97),
    match('Dried Saurel', redFishArtwork, .96),
  ];

  List<InventoryItemMatch> paleFish() => <InventoryItemMatch>[
    match(
      'Dried Amur Minnow',
      confusedArtworkCandidates ? genericFishArtwork : paleFishArtwork,
      .99,
    ),
    match('Dried Nibbler', paleFishArtwork, .98),
    match('Dried Filefish', paleFishArtwork, .97),
  ];

  return InventoryScreenshotAnalysis(
    fileName: 'dried-fish-order.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'e').join(),
      sourceWidth: 8,
      sourceHeight: 1,
      gridColumns: 8,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'fish-clownfish',
          column: 0,
          selectedName: 'Dried Clownfish',
          quantity: 1,
          matches: <InventoryItemMatch>[
            match('Dried Mackerel Pike', clownfishArtwork, .99),
            match('Dried Clownfish', clownfishArtwork, .98),
          ],
          previewPng: png,
        ),
        _row(
          id: 'fish-grouper',
          column: 1,
          selectedName: confidentLaterSelections ? 'Dried Grouper' : null,
          quantity: 2,
          matches: genericFish(),
          previewPng: png,
        ),
        _row(
          id: 'fish-maomao',
          column: 2,
          selectedName: confidentLaterSelections ? 'Dried Maomao' : null,
          quantity: 3,
          matches: genericFish(),
          previewPng: png,
        ),
        _row(
          id: 'fish-surfperch',
          column: 3,
          selectedName: confidentLaterSelections ? 'Dried Surfperch' : null,
          quantity: 4,
          matches: genericFish(),
          previewPng: png,
        ),
        _row(
          id: 'fish-bluefish',
          column: 4,
          selectedName: confidentLaterSelections ? 'Dried Bluefish' : null,
          quantity: 5,
          matches: redFish(),
          previewPng: png,
        ),
        _row(
          id: 'fish-siganid',
          column: 5,
          selectedName: confidentLaterSelections ? 'Dried Siganid' : null,
          quantity: 6,
          matches: genericFish(),
          previewPng: png,
        ),
        _row(
          id: 'fish-nibbler',
          column: 6,
          selectedName: confidentLaterSelections ? 'Dried Nibbler' : null,
          quantity: 7,
          matches: paleFish(),
          previewPng: png,
        ),
        _row(
          id: 'fish-golden-thread',
          column: 7,
          selectedName: confidentLaterSelections ? 'Dried Golden-thread' : null,
          quantity: 8,
          matches: redFish(),
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _realisticFishDropdownAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Dried Spotted Barbel': 8639,
    'Dried Surfperch': 8574,
    'Dried Bluefish': 8573,
    'Dried Siganid': 8572,
    'Dried Nibbler': 8571,
    'Dried Silver Stripe Round Herring': 8565,
    'Dried Round Herring': 8564,
    'Dried Notch Jaw': 8550,
    'Dried Filefish': 8534,
    'Dried Saurel': 8509,
    'Milk': 9003,
  };
  const wrongArtwork = 'app:wrong-fish-family';
  const redArtwork = 'app:red-fish-family';
  const paleArtwork = 'app:pale-fish-family';

  InventoryItemMatch fish(
    String name,
    String artwork,
    double confidence,
    double sourceScore,
  ) => InventoryItemMatch(
    name: name,
    confidence: confidence,
    sourceVisualConfidence: sourceScore,
    sharedArtwork: true,
    grade: 0,
    itemId: ids[name],
    artworkKey: artwork,
    orderGroupKey: 'dried-fish',
  );

  return InventoryScreenshotAnalysis(
    fileName: 'realistic-fish-dropdown.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    plannerItemOrderGroups: <String, String>{
      for (final name in ids.keys)
        if (name != 'Milk') name.toLowerCase(): 'dried-fish',
    },
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '4').join(),
      sourceWidth: 5,
      sourceHeight: 1,
      gridColumns: 5,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'fish-surfperch-anchor',
          column: 0,
          selectedName: 'Dried Surfperch',
          quantity: 107000,
          matches: <InventoryItemMatch>[
            fish('Dried Surfperch', wrongArtwork, .90, .93),
          ],
          previewPng: png,
        ),
        _row(
          id: 'fish-bluefish-dropdown',
          column: 1,
          selectedName: 'Dried Silver Stripe Round Herring',
          quantity: 24268,
          matches: <InventoryItemMatch>[
            fish('Dried Spotted Barbel', wrongArtwork, .8204, .91),
            fish('Dried Silver Stripe Round Herring', wrongArtwork, .8204, .91),
            fish('Dried Bluefish', redArtwork, .8204, .876),
            fish('Dried Round Herring', redArtwork, .8204, .876),
            fish('Dried Saurel', redArtwork, .8204, .876),
          ],
          previewPng: png,
        ),
        _row(
          id: 'fish-sequence-break',
          column: 2,
          selectedName: 'Milk',
          quantity: 1,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Milk',
              confidence: .99,
              sharedArtwork: false,
              grade: 0,
              itemId: 9003,
            ),
          ],
          previewPng: png,
        ),
        _row(
          id: 'fish-siganid-anchor',
          column: 3,
          selectedName: 'Dried Siganid',
          quantity: 6753,
          matches: <InventoryItemMatch>[
            fish('Dried Siganid', wrongArtwork, .90, .93),
          ],
          previewPng: png,
        ),
        _row(
          id: 'fish-nibbler-dropdown',
          column: 4,
          selectedName: 'Dried Notch Jaw',
          quantity: 1220,
          matches: <InventoryItemMatch>[
            fish('Dried Spotted Barbel', wrongArtwork, .8796, .925),
            fish('Dried Nibbler', paleArtwork, .8796, .925),
            fish('Dried Notch Jaw', wrongArtwork, .8796, .925),
            fish('Dried Filefish', paleArtwork, .8796, .925),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _herringAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Dried Whiting': 8566,
    'Dried Silver Stripe Round Herring': 8565,
    'Dried Round Herring': 8564,
    'Dried Grunt': 8561,
  };
  const artwork =
      'icons/items/ff47e9b1b62138e92c5141db1ecc37a7505668f5fc0ee608d42a436856499206.webp';
  InventoryItemMatch match(String name) => InventoryItemMatch(
    name: name,
    confidence: .96,
    sharedArtwork: true,
    grade: 0,
    itemId: ids[name],
    artworkKey: artwork,
    orderGroupKey: 'dried-fish',
  );
  final family = <InventoryItemMatch>[
    match('Dried Whiting'),
    match('Dried Silver Stripe Round Herring'),
    match('Dried Round Herring'),
    match('Dried Grunt'),
  ];
  return InventoryScreenshotAnalysis(
    fileName: 'herring-order.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    plannerItemOrderGroups: <String, String>{
      for (final name in ids.keys) name.toLowerCase(): 'dried-fish',
    },
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '7').join(),
      sourceWidth: 3,
      sourceHeight: 1,
      gridColumns: 3,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'herring-earlier',
          column: 0,
          selectedName: 'Dried Round Herring',
          quantity: 50919,
          matches: family,
          previewPng: png,
        ),
        _row(
          id: 'herring-target',
          column: 1,
          selectedName: 'Dried Silver Stripe Round Herring',
          quantity: 15202,
          matches: family,
          previewPng: png,
        ),
        _row(
          id: 'herring-later',
          column: 2,
          selectedName: 'Dried Grunt',
          quantity: 350,
          matches: family,
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _saltAnalysis({required int slotCount}) {
  final png = _pixelPng();
  const ids = <String, int>{'Salt': 9001, 'Sun-Dried Salt': 9008};
  const artwork =
      'icons/items/718d537b1f62806b4f9f7d6abbbb8629b402192533890b9a701e9664a4aa999f.webp';
  InventoryItemMatch match(String name) => InventoryItemMatch(
    name: name,
    confidence: .96,
    sharedArtwork: true,
    grade: 0,
    itemId: ids[name],
    artworkKey: artwork,
    primaryIngredientUseCount: name == 'Salt' ? 24 : 0,
  );
  final matches = <InventoryItemMatch>[match('Sun-Dried Salt'), match('Salt')];
  return InventoryScreenshotAnalysis(
    fileName: 'salt.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '8').join(),
      sourceWidth: slotCount,
      sourceHeight: 1,
      gridColumns: slotCount,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        for (var index = 0; index < slotCount; index += 1)
          _row(
            id: 'salt-$index',
            column: index,
            selectedName: 'Sun-Dried Salt',
            quantity: 45065 + index,
            matches: matches,
            previewPng: png,
          ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _barleyFlourWithSaltFallbackAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Barley Flour': 7102,
    'Wheat Flour': 7101,
    'Salt': 9001,
    'Sun-Dried Salt': 9008,
  };
  const flourArtwork = 'app:barley-flour';
  const saltArtwork = 'helper:shared-salt';
  InventoryItemMatch match(
    String name,
    double confidence, {
    required String artworkKey,
    String? orderGroupKey,
  }) => InventoryItemMatch(
    name: name,
    confidence: confidence,
    sharedArtwork: artworkKey == saltArtwork,
    grade: 0,
    itemId: ids[name],
    artworkKey: artworkKey,
    orderGroupKey: orderGroupKey,
  );

  return InventoryScreenshotAnalysis(
    fileName: 'barley-flour-with-salt-fallbacks.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '6').join(),
      sourceWidth: 1,
      sourceHeight: 1,
      gridColumns: 1,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'barley-flour',
          column: 0,
          selectedName: 'Barley Flour',
          quantity: 19996,
          matches: <InventoryItemMatch>[
            match(
              'Barley Flour',
              .8818,
              artworkKey: flourArtwork,
              orderGroupKey: 'grain:flour',
            ),
            match(
              'Wheat Flour',
              .7854,
              artworkKey: 'app:wheat-flour',
              orderGroupKey: 'grain:flour',
            ),
            match('Salt', .71, artworkKey: saltArtwork),
            match('Sun-Dried Salt', .69, artworkKey: saltArtwork),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _sharedBottleAnalysis({
  bool preselectWater = false,
  bool duplicateStorms = false,
}) {
  final png = _pixelPng();
  const ids = <String, int>{
    'Bottle of Turbid Water': 6654,
    'Oil of Storms': 6602,
    'Bottle of Clean Water': 6655,
    'Oil of Regeneration': 6601,
  };

  InventoryItemMatch match(
    String name, {
    required String artworkKey,
    required int primaryIngredientUseCount,
  }) => InventoryItemMatch(
    name: name,
    confidence: .96,
    sharedArtwork: true,
    grade: 0,
    itemId: ids[name],
    artworkKey: artworkKey,
    primaryIngredientUseCount: primaryIngredientUseCount,
  );

  List<InventoryItemMatch> family(
    String bottle,
    String oil,
    String artworkKey,
  ) => <InventoryItemMatch>[
    match(bottle, artworkKey: artworkKey, primaryIngredientUseCount: 0),
    match(oil, artworkKey: artworkKey, primaryIngredientUseCount: 1),
  ];

  return InventoryScreenshotAnalysis(
    fileName: 'shared-bottles.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '4').join(),
      sourceWidth: 2,
      sourceHeight: 1,
      gridColumns: 2,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'storms-bottle',
          column: 0,
          selectedName: preselectWater ? 'Bottle of Turbid Water' : null,
          itemSuggestionUncertain: true,
          quantity: 9418,
          matches: family(
            'Bottle of Turbid Water',
            'Oil of Storms',
            'helper:storms-bottle',
          ),
          previewPng: png,
        ),
        _row(
          id: 'regeneration-bottle',
          column: 1,
          selectedName: preselectWater ? 'Bottle of Clean Water' : null,
          itemSuggestionUncertain: true,
          quantity: 8991,
          matches: family(
            'Bottle of Clean Water',
            'Oil of Regeneration',
            'helper:regeneration-bottle',
          ),
          previewPng: png,
        ),
        if (duplicateStorms)
          _row(
            id: 'storms-second',
            column: 2,
            selectedName: preselectWater ? 'Bottle of Turbid Water' : null,
            itemSuggestionUncertain: true,
            quantity: 42,
            matches: family(
              'Bottle of Turbid Water',
              'Oil of Storms',
              'helper:storms-bottle',
            ),
            previewPng: png,
          ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _longSelectedNameAnalysis() {
  final png = _pixelPng();
  return InventoryScreenshotAnalysis(
    fileName: 'long-selected-name.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: const <String>['Steaming Hot Grilled Bird Meat', 'Milk'],
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '1').join(),
      sourceWidth: 2,
      sourceHeight: 1,
      gridColumns: 2,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'long-result',
          column: 0,
          selectedName: 'Steaming Hot Grilled Bird Meat',
          quantity: 596,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Steaming Hot Grilled Bird Meat',
              confidence: .99,
              sharedArtwork: false,
              grade: 2,
              itemId: 9493,
            ),
          ],
          previewPng: png,
        ),
        _row(
          id: 'short-result',
          column: 1,
          selectedName: 'Milk',
          quantity: 174500,
          matches: const <InventoryItemMatch>[
            InventoryItemMatch(
              name: 'Milk',
              confidence: .99,
              sharedArtwork: false,
              grade: 0,
              itemId: 7,
            ),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _bigMushroomAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Big Ancient Mushroom': 5437,
    'Big Emperor Mushroom': 5432,
    'Big Tiger Mushroom': 5431,
    'Big Sky Mushroom': 5430,
    'Big Cloud Mushroom': 5429,
    'Big Dwarf Mushroom': 5428,
    'Big Fortune Mushroom': 5426,
  };

  InventoryItemMatch match(String name, double confidence) =>
      InventoryItemMatch(
        name: name,
        confidence: confidence,
        sharedArtwork: false,
        grade: null,
        itemId: ids[name],
        artworkKey: 'app:$name',
        orderGroupKey: 'mushroom:big',
      );

  InventoryScreenshotRow row(
    String id,
    int column,
    String selectedName,
    List<InventoryItemMatch> matches,
  ) => _row(
    id: id,
    column: column,
    selectedName: selectedName,
    quantity: column + 1,
    matches: matches,
    previewPng: png,
    itemSuggestionUncertain: true,
  );

  return InventoryScreenshotAnalysis(
    fileName: 'big-mushrooms.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'f').join(),
      sourceWidth: 4,
      sourceHeight: 1,
      gridColumns: 4,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        row('big-emperor', 0, 'Big Emperor Mushroom', <InventoryItemMatch>[
          match('Big Emperor Mushroom', .78565),
          match('Big Ancient Mushroom', .75254),
        ]),
        row('big-tiger', 1, 'Big Tiger Mushroom', <InventoryItemMatch>[
          match('Big Tiger Mushroom', .819),
          match('Big Fortune Mushroom', .765),
        ]),
        row('big-sky', 2, 'Big Sky Mushroom', <InventoryItemMatch>[
          match('Big Sky Mushroom', .837),
          match('Big Cloud Mushroom', .638),
        ]),
        row('big-cloud', 3, 'Big Cloud Mushroom', <InventoryItemMatch>[
          match('Big Cloud Mushroom', .804),
          match('Big Dwarf Mushroom', .754),
        ]),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _sharedArtworkFallbackAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Blood 900': 900,
    'Blood 880': 880,
    'Blood 850': 850,
    'Blood 800': 800,
    'Meat 1200': 1200,
    'Meat 1150': 1150,
    'Meat 1100': 1100,
    'Meat 1000': 1000,
  };
  InventoryItemMatch match(String name, String artwork, double confidence) =>
      InventoryItemMatch(
        name: name,
        confidence: confidence,
        sharedArtwork: true,
        grade: 0,
        itemId: ids[name],
        artworkKey: artwork,
      );
  return InventoryScreenshotAnalysis(
    fileName: 'shared-artwork-fallback.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'f').join(),
      sourceWidth: 4,
      sourceHeight: 1,
      gridColumns: 4,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'blood-0',
          column: 0,
          selectedName: null,
          quantity: 1,
          matches: <InventoryItemMatch>[
            match('Blood 900', 'icons/items/blood.webp', .98),
            match('Blood 850', 'icons/items/blood.webp', .97),
          ],
          previewPng: png,
        ),
        _row(
          id: 'blood-1',
          column: 1,
          selectedName: null,
          quantity: 2,
          matches: <InventoryItemMatch>[
            match('Blood 880', 'icons/items/blood.webp', .98),
            match('Blood 800', 'icons/items/blood.webp', .97),
          ],
          previewPng: png,
        ),
        _row(
          id: 'meat-0',
          column: 2,
          selectedName: null,
          quantity: 3,
          matches: <InventoryItemMatch>[
            match('Meat 1200', 'icons/items/meat.webp', .98),
            match('Meat 1100', 'icons/items/meat.webp', .97),
          ],
          previewPng: png,
        ),
        _row(
          id: 'meat-1',
          column: 3,
          selectedName: null,
          quantity: 4,
          matches: <InventoryItemMatch>[
            match('Meat 1150', 'icons/items/meat.webp', .98),
            match('Meat 1000', 'icons/items/meat.webp', .97),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _globalBloodOrderAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Goat Blood': 6228,
    'Llama Blood': 6227,
    'Marmot Blood': 6226,
    'Weasel Blood': 6212,
    'Ox Blood': 6206,
    'Fox Blood': 6203,
  };

  InventoryItemMatch match(String name, String artworkKey) =>
      InventoryItemMatch(
        name: name,
        confidence: .80,
        sharedArtwork: true,
        grade: 0,
        itemId: ids[name],
        artworkKey: artworkKey,
        orderGroupKey: 'blood:all',
      );

  List<InventoryItemMatch> groupTwo() => <InventoryItemMatch>[
    match('Goat Blood', 'helper:blood-group-two'),
    match('Llama Blood', 'helper:blood-group-two'),
    match('Ox Blood', 'helper:blood-group-two'),
  ];
  List<InventoryItemMatch> marmotFamily() => <InventoryItemMatch>[
    match('Marmot Blood', 'helper:marmot-blood'),
    match('Weasel Blood', 'helper:marmot-blood'),
    match('Fox Blood', 'helper:marmot-blood'),
  ];

  return InventoryScreenshotAnalysis(
    fileName: 'global-blood-order.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    plannerItemOrderGroups: <String, String>{
      for (final name in ids.keys) name.toLowerCase(): 'blood:all',
    },
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '3').join(),
      sourceWidth: 3,
      sourceHeight: 1,
      gridColumns: 3,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'group-two-first',
          column: 0,
          selectedName: null,
          quantity: 563,
          matches: groupTwo(),
          previewPng: png,
        ),
        _row(
          id: 'group-two-second',
          column: 1,
          selectedName: null,
          quantity: 2903,
          matches: groupTwo(),
          previewPng: png,
        ),
        _row(
          id: 'marmot-family',
          column: 2,
          selectedName: null,
          quantity: 184,
          matches: marmotFamily(),
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _realBloodGapAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Goat Blood': 6228,
    'Llama Blood': 6227,
    'Marmot Blood': 6226,
    'Scorpion Blood': 6224,
    'Lion Blood': 6223,
    'Cobra Blood': 6222,
    'Ogre Blood': 6221,
    'Troll Blood': 6220,
    'Flamingo Blood': 6218,
    'Kuku Bird Blood': 6217,
    'Cheetah Dragon Blood': 6216,
    'Waragon Blood': 6215,
    'Wolf Blood': 6214,
    'Bear Blood': 6213,
    'Weasel Blood': 6212,
    'Raccoon Blood': 6210,
    'Worm Blood': 6209,
    'Lizard Blood': 6208,
    'Dinosaur Blood': 6207,
    'Ox Blood': 6206,
    'Pig Blood': 6205,
    'Rhino Blood': 6204,
    'Fox Blood': 6203,
    'Sheep Blood': 6202,
    'Deer Blood': 6201,
  };

  InventoryItemMatch native(String name, String artwork, double confidence) =>
      InventoryItemMatch(
        name: name,
        confidence: confidence,
        sharedArtwork: true,
        grade: 0,
        itemId: ids[name],
        artworkKey: artwork,
        orderGroupKey: 'blood:all',
        nativeMaterialEligible: true,
      );
  InventoryItemMatch fallback(String name, {double? sourceVisualConfidence}) =>
      InventoryItemMatch(
        name: name,
        confidence: .70,
        sharedArtwork: false,
        grade: 0,
        itemId: ids[name],
        artworkKey: 'app:${ids[name]}',
        orderGroupKey: 'blood:all',
        sourceVisualConfidence: sourceVisualConfidence,
      );
  List<InventoryItemMatch> withFallbacks(
    List<InventoryItemMatch> leading, {
    String? visuallySupportedFallback,
    double visuallySupportedScore = .94,
  }) => <InventoryItemMatch>[
    ...leading,
    for (final name in ids.keys)
      if (!leading.any((match) => match.name == name))
        fallback(
          name,
          sourceVisualConfidence: name == visuallySupportedFallback
              ? visuallySupportedScore
              : .30,
        ),
  ];
  List<InventoryItemMatch> groupTwo({
    String? visualFallback,
    double visualFallbackScore = .94,
  }) => withFallbacks(
    <InventoryItemMatch>[
      native('Goat Blood', 'helper:group-two', .7882),
      native('Llama Blood', 'helper:group-two', .7882),
      native('Ox Blood', 'helper:group-two', .7882),
      native('Pig Blood', 'helper:group-two', .7882),
      native('Sheep Blood', 'helper:group-two', .7882),
      native('Deer Blood', 'helper:group-two', .7882),
    ],
    visuallySupportedFallback: visualFallback,
    visuallySupportedScore: visualFallbackScore,
  );
  List<InventoryItemMatch> wolfFamily() => withFallbacks(<InventoryItemMatch>[
    native('Flamingo Blood', 'helper:wolf-family', .8085),
    native('Cheetah Dragon Blood', 'helper:wolf-family', .8085),
    native('Wolf Blood', 'helper:wolf-family', .8085),
    native('Rhino Blood', 'helper:wolf-family', .8085),
  ]);
  List<InventoryItemMatch> bearFamily() => withFallbacks(<InventoryItemMatch>[
    native('Lion Blood', 'helper:bear-family', .7461),
    native('Ogre Blood', 'helper:bear-family', .7461),
    native('Troll Blood', 'helper:bear-family', .7461),
    native('Bear Blood', 'helper:bear-family', .7461),
    native('Dinosaur Blood', 'helper:bear-family', .7461),
  ]);
  List<InventoryItemMatch> foxFamily({
    String? visualFallback,
    double visualFallbackScore = .94,
  }) => withFallbacks(
    <InventoryItemMatch>[
      native('Marmot Blood', 'helper:fox-family', .7483),
      native('Scorpion Blood', 'helper:fox-family', .7483),
      native('Weasel Blood', 'helper:fox-family', .7483),
      native('Fox Blood', 'helper:fox-family', .7483),
    ],
    visuallySupportedFallback: visualFallback,
    visuallySupportedScore: visualFallbackScore,
  );
  List<InventoryItemMatch> wormFamily() => withFallbacks(<InventoryItemMatch>[
    native('Cobra Blood', 'helper:worm-family', .8445),
    native('Kuku Bird Blood', 'helper:worm-family', .8445),
    native('Worm Blood', 'helper:worm-family', .8445),
    native('Lizard Blood', 'helper:worm-family', .8445),
  ]);

  final rows = <({String id, int amount, List<InventoryItemMatch> matches})>[
    (id: 'blood-goat', amount: 563, matches: groupTwo()),
    (id: 'blood-llama', amount: 2903, matches: groupTwo()),
    (
      id: 'blood-waragon',
      amount: 179,
      matches: groupTwo(
        visualFallback: 'Waragon Blood',
        visualFallbackScore: .6754426187445228,
      ),
    ),
    (id: 'blood-wolf', amount: 2425, matches: wolfFamily()),
    (id: 'blood-bear', amount: 4390, matches: bearFamily()),
    (
      id: 'blood-raccoon',
      amount: 22,
      matches: foxFamily(
        visualFallback: 'Raccoon Blood',
        visualFallbackScore: .6863159338856243,
      ),
    ),
    (id: 'blood-worm', amount: 2641, matches: wormFamily()),
    (id: 'blood-fox', amount: 11930, matches: foxFamily()),
    (id: 'blood-sheep', amount: 1, matches: groupTwo()),
    (id: 'blood-deer', amount: 5495, matches: groupTwo()),
  ];
  return InventoryScreenshotAnalysis(
    fileName: 'real-blood-gap.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    plannerItemOrderGroups: <String, String>{
      for (final name in ids.keys) name.toLowerCase(): 'blood:all',
    },
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'b').join(),
      sourceWidth: rows.length,
      sourceHeight: 1,
      gridColumns: rows.length,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        for (var index = 0; index < rows.length; index += 1)
          _row(
            id: rows[index].id,
            column: index,
            selectedName: null,
            quantity: rows[index].amount,
            matches: rows[index].matches,
            previewPng: png,
          ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _visualMaterialSequenceAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Ox Hide': 6006,
    'Rhino Hide': 6004,
    'Fox Hide': 6003,
    'Deer Hide': 6001,
    'Weasel Hide': 6012,
    'Raccoon Hide': 6010,
    'Elder Tree Sap': 5014,
    'Acacia Sap': 5013,
    'Pine Sap': 5003,
    'Maple Sap': 5002,
    'Ash Sap': 5001,
    'Milk': 9003,
  };
  InventoryItemMatch match(
    String name,
    double confidence,
    String artwork,
    String? group,
  ) => InventoryItemMatch(
    name: name,
    confidence: confidence,
    sharedArtwork: artwork == 'helper:fox-weasel',
    grade: 0,
    itemId: ids[name],
    artworkKey: artwork,
    orderGroupKey: group,
    nativeMaterialEligible: true,
  );
  InventoryScreenshotRow row(
    String id,
    int column,
    String? selected,
    List<InventoryItemMatch> matches,
  ) => _row(
    id: id,
    column: column,
    selectedName: selected,
    quantity: column + 1,
    matches: matches,
    previewPng: png,
  );
  return InventoryScreenshotAnalysis(
    fileName: 'visual-material-order.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    plannerItemOrderGroups: <String, String>{
      for (final name in <String>[
        'Ox Hide',
        'Rhino Hide',
        'Fox Hide',
        'Deer Hide',
        'Weasel Hide',
        'Raccoon Hide',
      ])
        name.toLowerCase(): 'hide:raw',
      for (final name in <String>[
        'Elder Tree Sap',
        'Acacia Sap',
        'Pine Sap',
        'Maple Sap',
        'Ash Sap',
      ])
        name.toLowerCase(): 'sap:tree',
    },
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, '6').join(),
      sourceWidth: 11,
      sourceHeight: 1,
      gridColumns: 11,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        row('hide-ox', 0, 'Ox Hide', <InventoryItemMatch>[
          match('Ox Hide', .96, 'helper:ox', 'hide:raw'),
        ]),
        row('hide-rhino', 1, 'Rhino Hide', <InventoryItemMatch>[
          match('Rhino Hide', .96, 'helper:rhino', 'hide:raw'),
        ]),
        row('hide-fox', 2, null, <InventoryItemMatch>[
          match('Weasel Hide', .9093, 'helper:fox-weasel', 'hide:raw'),
          match('Fox Hide', .9093, 'helper:fox-weasel', 'hide:raw'),
          match('Raccoon Hide', .9078, 'helper:raccoon', 'hide:raw'),
        ]),
        row('hide-deer', 3, 'Deer Hide', <InventoryItemMatch>[
          match('Deer Hide', .96, 'helper:deer', 'hide:raw'),
        ]),
        row('sap-elder', 4, 'Elder Tree Sap', <InventoryItemMatch>[
          match('Elder Tree Sap', .8434, 'helper:elder', 'sap:tree'),
          match('Acacia Sap', .8281, 'helper:acacia', 'sap:tree'),
        ]),
        row('sap-acacia', 5, 'Elder Tree Sap', <InventoryItemMatch>[
          match('Acacia Sap', .8428, 'helper:acacia', 'sap:tree'),
          match('Elder Tree Sap', .8325, 'helper:elder', 'sap:tree'),
        ]),
        row('family-break', 6, 'Milk', <InventoryItemMatch>[
          match('Milk', .99, 'helper:milk', null),
        ]),
        row('sap-pine', 7, 'Pine Sap', <InventoryItemMatch>[
          match('Pine Sap', .8588, 'helper:pine', 'sap:tree'),
          match('Maple Sap', .8569, 'helper:maple', 'sap:tree'),
        ]),
        row('sap-maple', 8, 'Maple Sap', <InventoryItemMatch>[
          match('Maple Sap', .8460, 'helper:maple', 'sap:tree'),
          match('Ash Sap', .8414, 'helper:ash', 'sap:tree'),
        ]),
        row('sap-ash', 9, 'Maple Sap', <InventoryItemMatch>[
          match('Maple Sap', .8650, 'helper:maple', 'sap:tree'),
          match('Ash Sap', .8650, 'helper:ash', 'sap:tree'),
        ]),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

Future<void> _chooseReviewItem(
  WidgetTester tester,
  String rowId,
  String name,
) async {
  await tester.tap(
    find.byKey(ValueKey<String>('inventory-import-item-$rowId')),
  );
  await tester.pumpAndSettle();
  final option = find.descendant(
    of: find.byType(MenuItemButton),
    matching: find.text(name),
  );
  expect(option, findsWidgets);
  await tester.tap(option.last);
  await tester.pumpAndSettle();
}

double _fieldFrameAlpha(WidgetTester tester, String fieldKey) {
  final frame = find.byKey(
    ValueKey<String>('inventory-import-error-$fieldKey-frame'),
  );
  final decorationFinder = find.descendant(
    of: frame,
    matching: find.byType(DecoratedBox),
  );
  final decoration =
      tester.widget<DecoratedBox>(decorationFinder.first).decoration
          as BoxDecoration;
  final border = decoration.border! as Border;
  return border.top.color.a;
}

InventoryScreenshotAnalysis _unrelatedIdAnalysis() {
  final png = _pixelPng();
  const ids = <String, int>{
    'Special Fire Flake Flower': 5466,
    'Mineral Water': 9059,
    'Olive': 7309,
    'Bag of Muddy Water': 6657,
    'Thuja Plank': 4701,
  };
  InventoryItemMatch match(
    String name,
    double confidence, {
    bool sharedArtwork = false,
  }) => InventoryItemMatch(
    name: name,
    confidence: confidence,
    sharedArtwork: sharedArtwork,
    grade: 0,
    itemId: ids[name],
  );
  return InventoryScreenshotAnalysis(
    fileName: 'unrelated-ids.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: ids.keys.toList(growable: false),
    plannerItemIds: ids,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'd').join(),
      sourceWidth: 2,
      sourceHeight: 2,
      gridColumns: 2,
      gridRows: 2,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'fire-flower',
          column: 0,
          selectedName: 'Special Fire Flake Flower',
          quantity: 1,
          matches: <InventoryItemMatch>[
            match('Special Fire Flake Flower', .98),
          ],
          previewPng: png,
        ),
        _row(
          id: 'mineral-water',
          column: 1,
          selectedName: 'Mineral Water',
          quantity: 2,
          matches: <InventoryItemMatch>[match('Mineral Water', .99)],
          previewPng: png,
        ),
        _row(
          id: 'olive',
          column: 0,
          selectedName: 'Olive',
          quantity: 3,
          matches: <InventoryItemMatch>[match('Olive', .97)],
          previewPng: png,
        ),
        _row(
          id: 'muddy-water',
          column: 1,
          selectedName: 'Bag of Muddy Water',
          itemSuggestionUncertain: true,
          quantity: 4,
          matches: <InventoryItemMatch>[
            match('Bag of Muddy Water', .79),
            match('Thuja Plank', .78),
          ],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _incompleteAnalysis() {
  final png = _pixelPng();
  return InventoryScreenshotAnalysis(
    fileName: 'incomplete.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: const <String>['Fallback item'],
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'c').join(),
      sourceWidth: 1,
      sourceHeight: 1,
      gridColumns: 1,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[
        _row(
          id: 'empty-row',
          column: 0,
          selectedName: null,
          quantity: null,
          matches: const <InventoryItemMatch>[],
          previewPng: png,
        ),
      ],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

InventoryScreenshotAnalysis _singleReviewAnalysis(
  InventoryScreenshotRow row, {
  required List<String> plannerItemNames,
}) {
  final png = _pixelPng();
  return InventoryScreenshotAnalysis(
    fileName: 'single-review.png',
    mimeType: 'image/png',
    sourceByteCount: png.length,
    screenshotBytes: png,
    plannerItemNames: plannerItemNames,
    draft: InventoryScreenshotDraft(
      imageFingerprint: List<String>.filled(64, 'a').join(),
      sourceWidth: 1,
      sourceHeight: 1,
      gridColumns: 1,
      gridRows: 1,
      gridConfidence: 1,
      rows: <InventoryScreenshotRow>[row],
      hiddenRows: const <InventoryScreenshotRow>[],
      warnings: const <String>[],
    ),
  );
}

Uint8List _pixelPng() => Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

InventoryScreenshotRow _row({
  required String id,
  required int column,
  required String? selectedName,
  required int? quantity,
  String? quantityText,
  required List<InventoryItemMatch> matches,
  required Uint8List previewPng,
  bool itemSuggestionUncertain = false,
}) => InventoryScreenshotRow(
  id: id,
  slotId: id,
  row: 0,
  column: column,
  crop: const InventoryScreenshotRect(left: 0, top: 0, width: 1, height: 1),
  quantityText: quantityText ?? quantity?.toString() ?? '',
  quantity: quantity,
  quantitySuggested: null,
  quantityApproximate: false,
  quantityAssumedOne: false,
  quantityConfidence: 1,
  matches: matches,
  selectedName: selectedName,
  relevance: InventoryOcrMaterialRelevance.relevant,
  reviewRequired: false,
  itemSuggestionUncertain: itemSuggestionUncertain,
  reviewReasons: const <String>[],
  previewPng: previewPng,
);
