import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/custom_icon_test_support.dart';
import 'inventory_test_fixture.dart';

void main() {
  testWidgets('searches real metadata and filters by smart material family', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    expect(
      find.byKey(InventoryActionKeys.smartGroup('Alchemy materials')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(InventoryActionKeys.smartGroup('Alchemy materials')),
    );
    await tester.pump();
    expect(
      find.byKey(InventoryActionKeys.row('I14', 'Clear Liquid Reagent')),
      findsOneWidget,
    );
    expect(
      find.byKey(InventoryActionKeys.row('I14', 'Pure Powder Reagent')),
      findsOneWidget,
    );
    expect(find.byKey(InventoryActionKeys.row('I14', 'Salt')), findsNothing);

    await tester.tap(
      find.byKey(InventoryActionKeys.smartGroup('All materials')),
    );
    await tester.pump();

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
      find.bySemanticsLabel('No All materials items match "Calpheon".'),
      findsOneWidget,
    );

    final clearSearch = find.byTooltip('Clear inventory search');
    expect(clearSearch, findsOneWidget);
    await tester.tap(clearSearch);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Sunrise Herb'), findsOneWidget);
  });

  testWidgets('Materials hides equipment-like clutter until All items', (
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
    expect(find.text("Crystal of Void - Ah'krad"), findsOneWidget);
  });

  testWidgets('Current plan filter follows live target changes', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.filter('currentPlan')));
    await tester.pump();
    expect(find.text('Sunrise Herb'), findsOneWidget);
    expect(find.text('Salt'), findsOneWidget);
    expect(find.text('Silver Azalea'), findsNothing);

    expect(
      harness.controller.active.selectTarget('Pure Powder Reagent'),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('Silver Azalea'), findsOneWidget);
    expect(find.text('Sunrise Herb'), findsNothing);
  });

  testWidgets('adds and renames a selected storage through compact dialogs', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.addStorage));
    await tester.pumpAndSettle();
    await tester.enterText(
      _editableAppTextField('Storage or character name'),
      'Calpheon City Storage',
    );
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(InventoryActionKeys.storage('calpheon-city-storage')),
      findsOneWidget,
    );
    expect(
      harness.controller.active.inventoryStorage.selectedLocation.name,
      'Calpheon City Storage',
    );

    await tester.tap(find.byKey(InventoryActionKeys.i04));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Rename Calpheon City Storage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _editableAppTextField('Storage name'),
      'Calpheon Workshop',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(
      harness.controller.active.inventoryStorage.selectedLocation.name,
      'Calpheon Workshop',
    );
    expect(find.text('Calpheon Workshop'), findsWidgets);
  });

  testWidgets(
    'edits one storage amount with grouped formatting and validation',
    (tester) async {
      final harness = InventoryTestHarness();
      final locationId = harness.controller.active
          .ensureInventoryStorageLocation('Calpheon City Storage');
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      final amount = find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb'));
      await tester.tap(
        find.byKey(InventoryActionKeys.row('I09', 'Sunrise Herb')),
      );
      expect(harness.copiedNames, <String>['Sunrise Herb']);

      await tester.enterText(amount, '10000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        harness.controller.active.inventoryStorage.quantityAt(
          locationId,
          'Sunrise Herb',
        ),
        10000,
      );
      expect(
        harness.controller.active.state.value.inventory['Sunrise Herb'],
        10003,
        reason: 'The original Unassigned amount must remain part of the total.',
      );
      final editable = tester.widget<EditableText>(
        find.descendant(of: amount, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, '10.000');
      expect(find.text('Total 10.003'), findsOneWidget);

      await tester.enterText(amount, '-5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        harness.controller.active.inventoryStorage.quantityAt(
          locationId,
          'Sunrise Herb',
        ),
        10000,
        reason: 'Invalid drafts must not overwrite the last valid amount.',
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.enterText(amount, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        harness.controller.active.inventoryStorage.quantityAt(
          locationId,
          'Sunrise Herb',
        ),
        0,
      );
      expect(
        harness.controller.active.state.value.inventory['Sunrise Herb'],
        3,
      );
    },
  );

  testWidgets('same aggregate still refreshes the selected storage amount', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    final locationId = harness.controller.active.ensureInventoryStorageLocation(
      'Calpheon City Storage',
    );
    harness.controller.active.setInventoryStorageQuantity(
      locationId: locationId,
      itemName: 'Sunrise Herb',
      text: '3',
    );
    harness.controller.active.setInventoryStorageQuantity(
      locationId: inventoryUnassignedLocationId,
      itemName: 'Sunrise Herb',
      text: '0',
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    Finder amountField() => find.descendant(
      of: find.byKey(InventoryActionKeys.row('I10', 'Sunrise Herb')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(amountField()).controller.text, '3');

    harness.controller.active.setInventoryStorageQuantity(
      locationId: inventoryUnassignedLocationId,
      itemName: 'Sunrise Herb',
      text: '3',
    );
    harness.controller.active.setInventoryStorageQuantity(
      locationId: locationId,
      itemName: 'Sunrise Herb',
      text: '0',
    );
    await tester.pumpAndSettle();

    expect(harness.controller.active.state.value.inventory['Sunrise Herb'], 3);
    expect(tester.widget<EditableText>(amountField()).controller.text, '0');
  });

  testWidgets(
    'clear is editor-only and clears all locations without a prompt',
    (tester) async {
      final harness = InventoryTestHarness()..clearApprovals.add(false);
      harness.controller.active.ensureInventoryStorageLocation(
        'Calpheon City Storage',
      );
      harness.controller.active.setInventoryStorageQuantity(
        locationId: 'calpheon-city-storage',
        itemName: 'Salt',
        text: '25',
      );
      await pumpInventory(tester, harness, size: const Size(1500, 940));

      expect(find.byKey(InventoryActionKeys.i03), findsNothing);
      await tester.tap(find.byKey(InventoryActionKeys.i04));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(InventoryActionKeys.i03));
      await tester.pumpAndSettle();

      expect(harness.controller.active.state.value.inventory, isEmpty);
      expect(
        harness.controller.active.inventoryStorage.locations.every(
          (location) => location.quantities.isEmpty,
        ),
        isTrue,
      );
      expect(harness.clearRequests, isEmpty);
      expect(harness.transactionNotices, isEmpty);
      expect(harness.undoOffers, isEmpty);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets('clear write failure rolls back every storage amount', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      saveState: (_) async =>
          throw const FileSystemException('injected inventory disk failure'),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(InventoryActionKeys.i04));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InventoryActionKeys.i03));
    await tester.pumpAndSettle();

    expect(harness.controller.active.state.value.inventory, hasLength(2));
    expect(find.textContaining('Inventory was not cleared'), findsOneWidget);
    expect(harness.undoOffers, isEmpty);
  });

  testWidgets('editor group tools add, regroup, rename, and reset metadata', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    await tester.tap(find.byKey(InventoryActionKeys.i04));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.bySemanticsLabel('New inventory group name'),
      '  Daily   Alchemy  ',
    );
    await tester.tap(find.byKey(InventoryActionKeys.i05));
    await tester.pumpAndSettle();
    expect(
      harness.controller.active.state.value.customCategories,
      contains('Daily Alchemy'),
    );
    expect(
      harness.session.forMode(CraftMode.alchemy).selectedCategory,
      'Daily Alchemy',
    );

    final selector = find.byKey(InventoryActionKeys.i08Selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: selector, matching: find.byType(EditableText)),
      'silver',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Silver Azalea'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(InventoryActionKeys.i08));
    await tester.pumpAndSettle();
    expect(
      harness
          .controller
          .active
          .state
          .value
          .ingredientMeta['Silver Azalea']
          ?.category,
      'Daily Alchemy',
    );

    await tester.enterText(
      find.bySemanticsLabel('Rename selected inventory group'),
      '  Lab   Supplies ',
    );
    await tester.tap(find.byKey(InventoryActionKeys.i06));
    await tester.pumpAndSettle();
    expect(
      harness.controller.active.state.value.customCategories,
      contains('Lab Supplies'),
    );
    expect(
      harness
          .controller
          .active
          .state
          .value
          .ingredientMeta['Silver Azalea']
          ?.category,
      'Lab Supplies',
    );

    await tester.tap(find.byKey(InventoryActionKeys.i07));
    await tester.pumpAndSettle();
    expect(
      harness
          .controller
          .active
          .state
          .value
          .ingredientMeta['Silver Azalea']
          ?.category,
      isNull,
    );
  });

  testWidgets('item settings dialog saves category and source together', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'sunrise');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(InventoryActionKeys.i04));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(InventoryActionKeys.row('I11', 'Sunrise Herb')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item settings'), findsOneWidget);
    await tester.tap(_appSelect('Group for Sunrise Herb'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Field Kit').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      _editableAppTextField('Source note for Sunrise Herb'),
      'Gather near Behr before dawn',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    final metadata =
        harness.controller.active.state.value.ingredientMeta['Sunrise Herb'];
    expect(metadata?.category, 'Field Kit');
    expect(metadata?.sourceNote, 'Gather near Behr before dawn');
    expect(find.textContaining('settings saved'), findsOneWidget);
  });

  testWidgets('item settings write failure leaves prior metadata intact', (
    tester,
  ) async {
    final harness = InventoryTestHarness(
      saveState: (_) async =>
          throw const FileSystemException('injected item settings failure'),
    );
    await pumpInventory(tester, harness, size: const Size(1500, 940));
    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'sunrise');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(InventoryActionKeys.i04));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(InventoryActionKeys.row('I11', 'Sunrise Herb')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      _editableAppTextField('Source note for Sunrise Herb'),
      'This must not persist',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(
      harness
          .controller
          .active
          .state
          .value
          .ingredientMeta['Sunrise Herb']
          ?.sourceNote,
      'Gathered near Heidel roads.',
    );
    expect(find.textContaining('settings were not saved'), findsOneWidget);
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

  testWidgets('lazy list keeps scroll, arrow focus, and useful semantics', (
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
    expect(semantics.properties.label, contains('in Unassigned'));
    expect(semantics.properties.label, contains('total'));

    final firstFocus = tester.widget<Focus>(firstRow).focusNode!;
    firstFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      harness.session.forMode(CraftMode.alchemy).selectedItem,
      'Silver Azalea Reserve 01',
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
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.semanticLabel == 'Inventory storage locations',
        ),
        findsOneWidget,
      );
      expect(find.byKey(InventoryActionKeys.i01), findsOneWidget);
      expect(find.byKey(InventoryActionKeys.i14), findsOneWidget);
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

Finder _editableAppTextField(String semanticLabel) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is AppTextField && widget.semanticLabel == semanticLabel,
  ),
  matching: find.byType(EditableText),
);

Finder _appSelect(String semanticLabel) => find.byWidgetPredicate(
  (widget) =>
      widget is AppSelect<String> && widget.semanticLabel == semanticLabel,
);
