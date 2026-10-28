import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_panel.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'grouped_plan_test.dart' show groupedCatalog;
import 'recipe_worker_fixture.dart';

Future<void> settlePlan(WidgetTester tester, RecipeWorkerController c) async {
  for (var i = 0; i < 100 && c.busy; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(c.busy, isFalse);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shelf adds inline, groups collapse, overlaps move once and disappear',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(500, 1100);
      addTearDown(tester.view.reset);
      final c = RecipeWorkerController(
        catalogBuilder: groupedCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(
          targets: ['First', 'Second'],
          budget: 8,
        ),
        onSave: (_) {},
      );
      await tester.runAsync(c.load);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: RecipeWorkerPanel(
                controller: c,
                artwork: (_, size) => SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recipe-group-shared')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('recipe-workers-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-workers-recipe-search')),
        'Third',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Third'));
      await settlePlan(tester, c);
      expect(c.targets, ['First', 'Second', 'Third']);
      expect(find.byKey(const ValueKey('recipe-group-shared')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recipe-group-recipe:First')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('recipe-workers-plus-A')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('recipe-group-shared')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recipe-workers-plus-A')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('recipe-group-shared')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recipe-workers-plus-A')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('recipe-workers-summary')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('recipe-remove-Third')),
      );
      await tester.tap(find.byKey(const ValueKey('recipe-remove-Third')));
      await settlePlan(tester, c);
      expect(find.byKey(const ValueKey('recipe-group-shared')), findsNothing);
      expect(
        find.byKey(const ValueKey('recipe-group-recipe:First')),
        findsOneWidget,
      );
      final budget = tester.getSize(
        find.byKey(const ValueKey('recipe-workers-cp-field-CP budget')),
      );
      final left = tester.getSize(
        find.byKey(const ValueKey('recipe-workers-cp-field-CP left')),
      );
      expect(budget, left);
      expect(budget.width, lessThanOrEqualTo(100));
      expect(budget.height, lessThanOrEqualTo(42));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('node status tabs stay reachable while the long list scrolls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 430);
    addTearDown(tester.view.reset);
    final c = RecipeWorkerController(
      catalogBuilder: groupedCatalog,
      loadMap: () async => workerMap(),
      loadEconomics: () async => workerEconomics(),
      initial: BdoRecipeWorkerPreferences(
        targets: ['First', 'Second'],
        budget: 20,
      ),
      onSave: (_) {},
    );
    await tester.runAsync(c.load);
    c.showPage(RecipeWorkerPage.nodes);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RecipeWorkerPanel(
              controller: c,
              artwork: (_, size) => SizedBox.square(dimension: size),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final switcher = find.byKey(const ValueKey('recipe-workers-invested'));
    final position = tester.getTopLeft(switcher);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(switcher), position);
    expect(switcher.hitTestable(), findsOneWidget);
    c.toggleInvested('bridge');
    await tester.pumpAndSettle();
    await tester.tap(switcher);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recipe-invest-bridge')), findsOneWidget);
    expect(find.byKey(const ValueKey('recipe-invest-A0')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
