import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/custom_icon_test_support.dart';
import 'inventory_test_fixture.dart';

void main() {
  testWidgets('screenshot analysis shows a clear loading state', (
    tester,
  ) async {
    final pending = Completer<InventoryScreenshotAnalysis?>();
    final harness = InventoryTestHarness(pasteScreenshot: () => pending.future);
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
    await tester.pump();

    expect(find.text('Reading screenshot…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Reading screenshot' &&
            widget.properties.liveRegion == true,
      ),
      findsOneWidget,
    );

    pending.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('searches real metadata inside human material sections', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'reagent');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Alchemy materials'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'inventory-subsection:Alchemy materials:Reagents & crafting additives',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(InventoryActionKeys.row('I14', 'Clear Liquid Reagent')),
      findsOneWidget,
    );
    expect(
      find.byKey(InventoryActionKeys.row('I14', 'Pure Powder Reagent')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'salt');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(InventoryActionKeys.row('I14', 'Salt')), findsOneWidget);

    await tester.enterText(
      find.byKey(InventoryActionKeys.i01),
      'Material Vendor Lara',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sunrise Herb'), findsOneWidget);
    expect(find.text('Silver Azalea'), findsNothing);

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'Calpheon');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.bySemanticsLabel('No Inventory items match "Calpheon".'),
      findsOneWidget,
    );

    final clearSearch = find.byTooltip('Clear inventory search');
    expect(clearSearch, findsOneWidget);
    await tester.tap(clearSearch);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sunrise Herb'), findsOneWidget);
  });

  testWidgets('planner Inventory excludes equipment-like clutter', (
    tester,
  ) async {
    final base = inventoryDocument(showDeleteTools: false);
    final harness = InventoryTestHarness(
      initialState: base.copyWith(
        alchemy: base.alchemy.copyWith(
          recipeEdits: <String, RecipeState?>{
            "Crystal of Void - Ah'krad": RecipeState(
              type: 'alchemy',
              group: 'Gear crystal',
            ),
          },
        ),
      ),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    expect(find.text("Crystal of Void - Ah'krad"), findsNothing);
    await tester.tap(find.byKey(InventoryActionKeys.filter('all')));
    await tester.pump();
    expect(find.text("Crystal of Void - Ah'krad"), findsNothing);
  });

  testWidgets('Alchemy, Cooking, and Processing plans combine independently', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    expect(find.text('Owned'), findsOneWidget);
    expect(find.text('Alchemy plan'), findsOneWidget);
    expect(find.text('Cooking plan'), findsOneWidget);
    expect(find.text('Processing plan'), findsOneWidget);
    expect(find.text('All items'), findsOneWidget);
    expect(find.byKey(InventoryActionKeys.storageSelector), findsNothing);
    expect(find.byKey(InventoryActionKeys.addStorage), findsNothing);
    expect(find.byKey(InventoryActionKeys.renameStorage), findsNothing);
    final filterRects = <Rect>[
      for (final name in <String>[
        'owned',
        'alchemyPlan',
        'cookingPlan',
        'processingPlan',
        'all',
      ])
        tester.getRect(find.byKey(InventoryActionKeys.filter(name))),
    ];
    expect(filterRects.map((rect) => rect.top).toSet(), hasLength(1));
    expect(
      filterRects.every((rect) => rect.width < 160),
      isTrue,
      reason: 'Inventory filters should remain compact at desktop width.',
    );

    await tester.tap(find.byKey(InventoryActionKeys.filter('alchemyPlan')));
    await tester.pump();
    expect(find.text('Sunrise Herb'), findsOneWidget);
    expect(find.text('Salt'), findsOneWidget);
    expect(find.text('Silver Azalea'), findsNothing);
    expect(find.text('Wheat'), findsNothing);

    await tester.tap(find.byKey(InventoryActionKeys.filter('cookingPlan')));
    await tester.pump();
    expect(find.text('Sunrise Herb'), findsOneWidget);
    expect(find.text('Wheat'), findsOneWidget);
    expect(find.text('Wheat Flour'), findsNothing);

    await tester.tap(find.byKey(InventoryActionKeys.filter('processingPlan')));
    await tester.pump();
    expect(find.text('Sunrise Herb'), findsOneWidget);
    expect(find.text('Wheat'), findsOneWidget);
    expect(find.text('Wheat Flour'), findsOneWidget);

    await tester.tap(find.byKey(InventoryActionKeys.filter('alchemyPlan')));
    await tester.pump();
    expect(find.text('Sunrise Herb'), findsNothing);
    expect(find.text('Wheat'), findsOneWidget);
    expect(find.text('Wheat Flour'), findsOneWidget);

    await tester.tap(find.byKey(InventoryActionKeys.filter('alchemyPlan')));
    expect(
      harness.controller.modes[CraftMode.alchemy]!.selectTarget(
        'Pure Powder Reagent',
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('Silver Azalea'), findsOneWidget);
    expect(find.text('Sunrise Herb'), findsNothing);
    expect(find.text('Wheat'), findsOneWidget);
  });

  testWidgets('amount edits are shared by every planner mode', (tester) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'Sunrise Herb');
    await tester.pump(const Duration(milliseconds: 200));

    final amount = find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb'));
    await tester.enterText(amount, '10000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Sunrise Herb'],
        10000,
      );
    }
    final editable = tester.widget<EditableText>(
      find.descendant(of: amount, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, '10.000');
    final rowSemantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byKey(InventoryActionKeys.row('I14', 'Sunrise Herb')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').startsWith('Sunrise Herb,'),
        ),
      ),
    );
    expect(rowSemantics.properties.label, 'Sunrise Herb, 10.000 owned');

    await tester.enterText(amount, '-5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      harness.controller.active.state.value.inventory['Sunrise Herb'],
      10000,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('search and quantity replace the redundant Add item dialog', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    expect(find.byKey(InventoryActionKeys.addItem), findsNothing);
    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'Salt');
    await tester.pump(const Duration(milliseconds: 200));
    final amount = find.byKey(InventoryActionKeys.row('I10', 'Salt'));
    await tester.enterText(amount, '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Salt'],
        250,
      );
    }
    await tester.tap(find.byKey(InventoryActionKeys.row('I15', 'Salt')));
    await tester.pumpAndSettle();
    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory['Salt'],
        isNull,
      );
    }
    expect(harness.undoOffers, hasLength(1));
  });

  testWidgets('long item can be found and entered at 200 percent text', (
    tester,
  ) async {
    final harness = InventoryTestHarness(includeLongItems: true);
    await pumpInventory(
      tester,
      harness,
      size: const Size(1500, 940),
      textScaler: const TextScaler.linear(2),
    );
    expect(find.byKey(InventoryActionKeys.addItem), findsNothing);
    await tester.enterText(
      find.byKey(InventoryActionKeys.i01),
      'Special Volcanic',
    );
    await tester.pump(const Duration(milliseconds: 200));
    final amount = find.byKey(
      InventoryActionKeys.row('I10', 'Special Volcanic Umbrella Mushroom'),
    );
    await tester.enterText(amount, '25000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      harness
          .controller
          .active
          .state
          .value
          .inventory['Special Volcanic Umbrella Mushroom'],
      25000,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty inventory confirms, mirrors, and offers whole-state undo',
    (tester) async {
      final harness = InventoryTestHarness();
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      await tester.tap(find.byKey(InventoryActionKeys.filter('owned')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(InventoryActionKeys.emptyInventory),
      );
      await tester.tap(find.byKey(InventoryActionKeys.emptyInventory));
      await tester.pumpAndSettle();
      expect(find.text('Empty inventory?'), findsOneWidget);
      await tester.tap(find.byKey(InventoryActionKeys.confirmEmptyInventory));
      await tester.pumpAndSettle();

      for (final mode in CraftMode.values) {
        expect(harness.controller.modes[mode]!.state.value.inventory, isEmpty);
      }
      expect(harness.undoOffers, hasLength(1));
      final result = await harness.undoOffers.single.undo();
      await tester.pumpAndSettle();
      expect(result.restored, isTrue);
      for (final mode in CraftMode.values) {
        expect(
          harness.controller.modes[mode]!.state.value.inventory['Sunrise Herb'],
          3,
        );
      }
    },
  );

  testWidgets('failed empty inventory keeps every amount', (tester) async {
    final harness = InventoryTestHarness(
      saveState: (_) async =>
          throw const FileSystemException('injected inventory disk failure'),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.filter('owned')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(InventoryActionKeys.emptyInventory));
    await tester.tap(find.byKey(InventoryActionKeys.emptyInventory));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InventoryActionKeys.confirmEmptyInventory));
    await tester.pumpAndSettle();

    expect(harness.controller.active.state.value.inventory, hasLength(2));
    expect(find.textContaining('was not emptied'), findsOneWidget);
    expect(harness.undoOffers, isEmpty);
  });

  testWidgets('pending amount commits on focus loss before reconstruction', (
    tester,
  ) async {
    final savedStates = <PlannerState>[];
    final harness = InventoryTestHarness(
      saveState: (state) async {
        savedStates.add(state);
        return state;
      },
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'Sunrise Herb');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb')),
      '5000',
    );
    await tester.pump();
    expect(
      harness.controller.active.state.value.inventory['Sunrise Herb'],
      3,
      reason: 'The focused field still owns the uncommitted draft.',
    );

    await tester.tap(find.byKey(InventoryActionKeys.i01));
    await tester.pumpAndSettle();
    expect(
      harness.controller.active.state.value.inventory['Sunrise Herb'],
      5000,
    );
    expect(savedStates, isNotEmpty);
    expect(savedStates.last.alchemy.inventory['Sunrise Herb'], 5000);

    tester.view.physicalSize = const Size(1200, 752);
    await tester.pumpWidget(
      KeyedSubtree(
        key: const ValueKey<String>('resized-inventory-host'),
        child: harness.host(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      harness.controller.active.state.value.inventory['Sunrise Herb'],
      5000,
    );
    final rebuilt = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb')),
        matching: find.byType(EditableText),
      ),
    );
    expect(rebuilt.controller.text, '5.000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('lazy grid keeps scroll, arrow focus, and useful semantics', (
    tester,
  ) async {
    final harness = InventoryTestHarness(additionalHerbs: 60);
    await pumpInventory(tester, harness, size: const Size(1200, 752));
    await tester.enterText(
      find.byKey(InventoryActionKeys.i01),
      'Silver Azalea',
    );
    await tester.pump(const Duration(milliseconds: 200));

    const lastName = 'Silver Azalea Reserve 60';
    expect(find.text(lastName), findsNothing);
    final session = harness.session.forMode(CraftMode.alchemy);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    await tester.drag(
      find.byKey(InventoryActionKeys.i14),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(session.itemScrollController.offset, greaterThan(0));

    session.itemScrollController.jumpTo(0);
    await tester.pump();
    final firstRow = find.byKey(
      InventoryActionKeys.row('I14', 'Silver Azalea'),
    );
    final rowSemantics = find.descendant(
      of: firstRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label ?? '').startsWith('Silver Azalea,'),
      ),
    );
    final semantics = tester.widget<Semantics>(rowSemantics);
    expect(semantics.properties.label, contains('Silver Azalea'));
    expect(semantics.properties.label, contains('owned'));

    final firstFocus = tester.widget<Focus>(firstRow).focusNode!;
    firstFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      harness.session.forMode(CraftMode.alchemy).selectedItem,
      'Silver Azalea Reserve 02',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventory composes in both themes and at 200% text', (
    tester,
  ) async {
    for (final spec in <ThemeSpec>[
      StandardSpec.theme,
      IlluminatedLedgerSpec.theme,
    ]) {
      final harness = InventoryTestHarness();
      await pumpInventory(
        tester,
        harness,
        size: const Size(1200, 752),
        spec: spec,
      );
      expect(find.byKey(InventoryActionKeys.storageSelector), findsNothing);
      expect(find.byKey(InventoryActionKeys.i01), findsOneWidget);
      expect(find.byKey(InventoryActionKeys.i14), findsOneWidget);
      expect(
        find.byKey(InventoryActionKeys.filter('cookingPlan')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: spec.id);
    }

    final largeText = InventoryTestHarness();
    await pumpInventory(
      tester,
      largeText,
      size: const Size(1500, 940),
      textScaler: TextScaler.linear(2),
    );
    expect(find.byKey(InventoryActionKeys.i01), findsOneWidget);
    expect(find.byKey(InventoryActionKeys.i14), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Inventory uses three readable columns', (tester) async {
    final harness = InventoryTestHarness(
      additionalHerbs: 3,
      includeLongItems: true,
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.enterText(
      find.byKey(InventoryActionKeys.i01),
      'Silver Azalea Reserve',
    );
    await tester.pump(const Duration(milliseconds: 200));

    final first = tester.getRect(
      find.byKey(InventoryActionKeys.row('I14', 'Silver Azalea Reserve 01')),
    );
    final second = tester.getRect(
      find.byKey(InventoryActionKeys.row('I14', 'Silver Azalea Reserve 02')),
    );
    final third = tester.getRect(
      find.byKey(InventoryActionKeys.row('I14', 'Silver Azalea Reserve 03')),
    );
    expect((first.top - second.top).abs(), lessThan(1));
    expect((second.top - third.top).abs(), lessThan(1));
    expect(second.left, greaterThan(first.right));
    expect(third.left, greaterThan(second.right));
    expect(first.width, greaterThan(360));
    expect(first.width, lessThan(500));

    await tester.enterText(
      find.byKey(InventoryActionKeys.i01),
      'Special Volcanic Umbrella Mushroom',
    );
    await tester.pump(const Duration(milliseconds: 200));
    final longName = find.descendant(
      of: find.byKey(
        InventoryActionKeys.row('I14', 'Special Volcanic Umbrella Mushroom'),
      ),
      matching: find.text('Special Volcanic Umbrella Mushroom'),
    );
    expect(longName, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(longName).didExceedMaxLines,
      isFalse,
    );
    final longRow = tester.getRect(
      find.byKey(
        InventoryActionKeys.row('I14', 'Special Volcanic Umbrella Mushroom'),
      ),
    );
    final amount = tester.getRect(
      find.byKey(
        InventoryActionKeys.row('I10', 'Special Volcanic Umbrella Mushroom'),
      ),
    );
    final remove = tester.getRect(
      find.byKey(
        InventoryActionKeys.row('I15', 'Special Volcanic Umbrella Mushroom'),
      ),
    );
    final nameBounds = tester.getRect(longName);
    final icon = tester.getRect(
      find.descendant(
        of: find.byKey(
          InventoryActionKeys.row('I14', 'Special Volcanic Umbrella Mushroom'),
        ),
        matching: find.byType(ModeItemIcon),
      ),
    );
    expect(longRow.height, lessThan(104));
    expect(amount.top, greaterThanOrEqualTo(nameBounds.bottom + 6));
    expect(remove.left - amount.right, greaterThanOrEqualTo(8));
    expect((icon.center.dy - longRow.center.dy).abs(), lessThan(1));
    expect((amount.center.dy - remove.center.dy).abs(), lessThan(4));
    expect(longRow.contains(amount.center), isTrue);
    expect(longRow.contains(remove.center), isTrue);

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'Sunrise Herb');
    await tester.pump(const Duration(milliseconds: 200));
    final shortRowFinder = find.byKey(
      InventoryActionKeys.row('I14', 'Sunrise Herb'),
    );
    final shortName = find.descendant(
      of: shortRowFinder,
      matching: find.text('Sunrise Herb'),
    );
    final shortRow = tester.getRect(shortRowFinder);
    final shortNameBounds = tester.getRect(shortName);
    final shortAmount = tester.getRect(
      find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb')),
    );
    final shortRemove = tester.getRect(
      find.byKey(InventoryActionKeys.row('I15', 'Sunrise Herb')),
    );
    final shortIcon = tester.getRect(
      find.descendant(of: shortRowFinder, matching: find.byType(ModeItemIcon)),
    );
    expect(shortRow.height, lessThan(80));
    expect(shortAmount.left - shortNameBounds.right, greaterThanOrEqualTo(12));
    expect(shortRemove.left - shortAmount.right, greaterThanOrEqualTo(8));
    expect((shortIcon.center.dy - shortRow.center.dy).abs(), lessThan(1));
    expect((shortAmount.center.dy - shortRemove.center.dy).abs(), lessThan(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inventory rows render saved custom icons and saved aliases', (
    tester,
  ) async {
    final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
    addTearDown(() => tester.runAsync(stored.dispose));
    final harness = InventoryTestHarness(additionalHerbs: 1);
    harness.controller.active.updateState(
      (state) => state.copyWith(
        customIcons: <String, CustomIconReference>{
          'Sunrise Herb': stored.reference,
        },
        iconAliases: const <String, String>{
          'Silver Azalea Reserve 01': 'Silver Azalea',
        },
      ),
      immediate: true,
    );
    await pumpInventory(tester, harness, iconStore: stored.store);

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'sunrise');
    await tester.pump(const Duration(milliseconds: 200));
    final customRow = find.byKey(
      InventoryActionKeys.row('I14', 'Sunrise Herb'),
    );
    final customImage = find.descendant(
      of: customRow,
      matching: find.byKey(ModeItemIconKeys.image('Sunrise Herb')),
    );
    final customTerminal = find.byWidgetPredicate(
      (widget) =>
          widget.key == ModeItemIconKeys.image('Sunrise Herb') ||
          widget.key == ModeItemIconKeys.failure('Sunrise Herb'),
    );
    await pumpUntilIconState(tester, customTerminal);
    expect(customImage, findsOneWidget);
    expect(
      (tester.widget<Image>(customImage).image as MemoryImage).bytes,
      orderedEquals(stored.bytes),
    );

    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'reserve 01');
    await tester.pump(const Duration(milliseconds: 200));
    const aliasName = 'Silver Azalea Reserve 01';
    final aliasRow = find.byKey(InventoryActionKeys.row('I14', aliasName));
    expect(aliasRow, findsOneWidget);
    expect(
      find.descendant(
        of: aliasRow,
        matching: find.byKey(ModeItemIconKeys.image(aliasName)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: aliasRow,
        matching: find.byKey(ModeItemIconKeys.failure(aliasName)),
      ),
      findsNothing,
    );
  });
}
