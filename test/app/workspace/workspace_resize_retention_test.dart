import 'dart:convert';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets('resizing leaves hidden features and planner state alone', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final original = (await tester.runAsync(
      () => ApplicationTestHarness.create(backgroundId: 'sakura-night-garden'),
    ))!;
    final harness = original.rebindControllerInCurrentZone();
    await tester.runAsync(original.disposeControllerOnly);
    final controller = harness.bundle.controller;
    controller.active.selectTarget('Adaptation Draught');
    controller.active.commitAmount('100');
    try {
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          enableBetaUpdates: false,
          enableOpportunityAutoCheck: false,
        ),
      );
      await tester.pumpAndSettle();
      for (final mode in [
        CraftMode.cooking,
        CraftMode.processing,
        CraftMode.alchemy,
      ]) {
        controller.switchMode(mode);
        await tester.pumpAndSettle();
      }
      controller.active.navigate('inventory');
      await tester.pumpAndSettle();
      final inventoryState = tester.state(find.byType(InventoryView));
      final search = find.descendant(
        of: find.byKey(InventoryActionKeys.i01),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'Sunrise');
      await tester.pumpAndSettle();
      controller.active.navigate('plan');
      await tester.pumpAndSettle();
      final planBefore = jsonEncode(controller.active.plan.value.toJson());
      var hiddenBuilds = 0;
      var plannerBuilds = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is PlannerView) plannerBuilds++;
        // The tiny viewport gate may update its MediaQuery wrapper, but the
        // hidden feature subtree must not rebuild just because size changed.
        if (element.widget is MediaQuery) return;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget case Offstage(offstage: true)) {
            hiddenBuilds++;
            return false;
          }
          return true;
        });
      };
      for (var i = 0; i < 12; i++) {
        final width = 1500.0 - i * 25;
        tester.view.physicalSize = Size(width, width * 47 / 75);
        await tester.pump();
      }
      debugOnRebuildDirtyWidget = null;
      expect(hiddenBuilds, 0);
      expect(plannerBuilds, 0);
      expect(jsonEncode(controller.active.plan.value.toJson()), planBefore);
      controller.active.navigate('inventory');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(InventoryView)), same(inventoryState));
      expect(tester.widget<TextField>(search).controller!.text, 'Sunrise');
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.disposeControllerOnly();
      await tester.runAsync(
        () => harness.temporaryDirectory.delete(recursive: true),
      );
    }
  });
}
