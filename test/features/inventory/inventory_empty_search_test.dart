import 'dart:convert';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'inventory_test_fixture.dart';

void main() {
  for (final spec in RetainedThemeRegistry.themes) {
    for (final layout in [
      (const Size(1200, 752), 1.0),
      (const Size(1000, 800), 2.0),
    ]) {
      testWidgets(
        'empty search clear retains filters and data ${spec.id} $layout',
        (tester) async {
          var saves = 0;
          final harness = InventoryTestHarness(
            saveState: (state) async {
              saves++;
              return state;
            },
          );
          final session = harness.session.forMode(CraftMode.alchemy);
          session.displayFilters = {InventoryDisplayFilter.owned};
          session.selectedSmartGroup = 'All materials';
          harness.session.forMode(CraftMode.cooking).search =
              'Keep this search';
          await pumpInventory(
            tester,
            harness,
            spec: spec,
            size: layout.$1,
            textScaler: TextScaler.linear(layout.$2),
          );
          final before = jsonEncode(
            harness.controller.documentSnapshot.toJson(),
          );
          expect(find.text('No matching items'), findsNothing);
          await tester.enterText(
            find.byKey(InventoryActionKeys.i01),
            'Sunrise Herbb',
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('No matching items'), findsOneWidget);
          expect(
            find.bySemanticsLabel('No Owned items match "Sunrise Herbb".'),
            findsOneWidget,
          );
          final clear = find.byKey(InventoryActionKeys.clearSearchResults);
          await tester.ensureVisible(clear);
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(session.search, isEmpty);
          expect(session.displayFilters, {InventoryDisplayFilter.owned});
          expect(session.selectedSmartGroup, 'All materials');
          expect(
            harness.session.forMode(CraftMode.cooking).search,
            'Keep this search',
          );
          expect(find.text('No matching items'), findsNothing);
          expect(find.text('Sunrise Herb'), findsOneWidget);
          expect(
            jsonEncode(harness.controller.documentSnapshot.toJson()),
            before,
          );
          expect(saves, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('clear cancels pending query and remains keyboard operable', (
    tester,
  ) async {
    final harness = InventoryTestHarness();
    await pumpInventory(tester, harness);
    await tester.enterText(find.byKey(InventoryActionKeys.i01), 'No such item');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(InventoryActionKeys.i01),
      'Another pending query',
    );
    final clear = find.byKey(InventoryActionKeys.clearSearchResults);
    final button = tester.widget<AppButton>(clear);
    // Activate the real button through keyboard focus, not the callback directly.
    final focus = find
        .descendant(
          of: clear,
          matching: find.byWidgetPredicate(
            (widget) => widget is Focus && widget.onKeyEvent != null,
          ),
        )
        .first;
    Focus.of(
      tester.element(
        find.descendant(of: focus, matching: find.text('Clear search')),
      ),
    ).requestFocus();
    await tester.pump();
    expect(button.onPressed, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(harness.session.forMode(CraftMode.alchemy).search, isEmpty);
    expect(find.text('No matching items'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty or whitespace search does not offer a useless clear action',
    (tester) async {
      final harness = InventoryTestHarness();
      harness.session.forMode(CraftMode.alchemy).displayFilters = {
        InventoryDisplayFilter.processingPlan,
      };
      await pumpInventory(tester, harness);
      await tester.enterText(find.byKey(InventoryActionKeys.i01), '   ');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No matching items'), findsNothing);
      expect(find.byKey(InventoryActionKeys.clearSearchResults), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final spec in RetainedThemeRegistry.themes) {
    testWidgets('narrow short empty state stays reachable ${spec.id}', (
      tester,
    ) async {
      final harness = InventoryTestHarness();
      harness.session.forMode(CraftMode.alchemy).search = 'No such item';
      await pumpInventory(
        tester,
        harness,
        spec: spec,
        size: const Size(680, 460),
        textScaler: TextScaler.linear(2),
      );
      final clear = find.byKey(InventoryActionKeys.clearSearchResults);
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      expect(clear.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The existing populated headings overflow at 680/200%; keep their
      // separately reproduced baseline failure out of this empty-state check.
      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(harness.session.forMode(CraftMode.alchemy).search, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
