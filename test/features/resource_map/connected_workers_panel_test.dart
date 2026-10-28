import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_panel.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'recipe_worker_fixture.dart';

void main() {
  testWidgets('checklist scroll and checks survive a spot visit/remount', (
    tester,
  ) async {
    final c = RecipeWorkerController(
      catalogBuilder: () => RecipeWorkerCatalog({
        'Target': workerRecipe('Target', {
          for (var i = 0; i < 30; i++) 'Leaf $i': 1,
        }),
      }, PlannerRules()),
      loadMap: () async => workerMap(),
      loadEconomics: () async => workerEconomics(),
      initial: BdoRecipeWorkerPreferences(target: 'Target', budget: 8),
      onSave: (_) {},
    );
    await tester.runAsync(c.load);
    Widget panel() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: RecipeWorkerPanel(
            controller: c,
            checklist: true,
            hasSpot: (_) => true,
            onSpot: (_) {},
            artwork: (_, size) => SizedBox.square(dimension: size),
          ),
        ),
      ),
    );
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    c.toggle('Leaf 0');
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    final offset = c.scrollOffsets['checklist']!;
    expect(offset, greaterThan(100));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      offset,
    );
    expect(c.checkedItems, {'Leaf 0'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'inline recipe selection, same-budget item navigation, collapsed invested',
    (tester) async {
      final c = RecipeWorkerController(
        catalogBuilder: workerCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(target: 'Target', budget: 8),
        onSave: (_) {},
      );
      await tester.runAsync(c.load);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: RecipeWorkerPanel(
                controller: c,
                artwork: (_, size) => SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recipe-workers-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.byKey(const ValueKey('recipe-workers-inline-recipes')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('recipe-workers-picker')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('recipe-workers-add-items')),
      );
      await tester.tap(find.byKey(const ValueKey('recipe-workers-add-items')));
      await tester.pumpAndSettle();
      expect(find.text('Add items'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('recipe-workers-budget')),
            )
            .controller!
            .text,
        '8',
      );
      expect(find.text('400'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-workers-item-search')),
        'B',
      );
      await tester.tap(find.byKey(const ValueKey('recipe-extra-B')));
      await tester.pumpAndSettle();
      expect(c.plan!.spent, 8); // refused; no extra budget
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('recipe-workers-nodes')),
      );
      await tester.tap(find.byKey(const ValueKey('recipe-workers-nodes')));
      await tester.pumpAndSettle();
      expect(find.text('Invest nodes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recipe-invest-bridge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recipe-invest-bridge')), findsNothing);
      expect(find.text('Invested 1'), findsOneWidget);
      expect(c.plan!.spent, 8);
      await tester.ensureVisible(
        find.byKey(const ValueKey('recipe-workers-invested')),
      );
      await tester.tap(find.byKey(const ValueKey('recipe-workers-invested')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recipe-invest-bridge')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final page in RecipeWorkerPage.values) {
    testWidgets('${page.name} compact at 200 percent does not overflow', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1000);
      addTearDown(tester.view.reset);
      final c = RecipeWorkerController(
        catalogBuilder: workerCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(target: 'Target', budget: 8),
        onSave: (_) {},
      );
      await tester.runAsync(c.load);
      c.showPage(page);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 280,
                child: RecipeWorkerPanel(
                  controller: c,
                  artwork: (_, size) => SizedBox.square(dimension: size),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
