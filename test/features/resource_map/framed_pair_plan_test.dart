import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_panel.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'grouped_plan_panel_test.dart' show settlePlan;
import 'grouped_plan_test.dart' show groupedCatalog;
import 'recipe_worker_fixture.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));

Widget panel(
  RecipeWorkerController c, {
  double width = 300,
  double scale = 1,
}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Segoe UI'),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: RecipeWorkerPanel(
            hosted: true,
            controller: c,
            artwork: (name, size) => SizedBox.square(
              key: ValueKey('art-$name-$size'),
              dimension: size,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() async {
    final font = FontLoader('Segoe UI');
    for (final path in [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/seguisb.ttf',
    ]) {
      font.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await font.load();
  });
  testWidgets('budget first, folded pair, actions fixed; opening is UI only', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 500);
    addTearDown(tester.view.reset);
    var saves = 0;
    final c = RecipeWorkerController(
      catalogBuilder: groupedCatalog,
      loadMap: () async => workerMap(),
      loadEconomics: () async => workerEconomics(),
      initial: BdoRecipeWorkerPreferences(
        targets: ['First', 'Second'],
        budget: 8,
      ),
      onSave: (_) => saves++,
    );
    await tester.runAsync(c.load);
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    final currentPlan = c.plan, initialSaves = saves;
    expect(find.text('Recipes'), findsNothing);
    expect(keyed('recipe-workers-expanded'), findsNothing);
    expect(keyed('recipe-workers-summary'), findsOneWidget);
    expect(keyed('recipe-workers-picker').hitTestable(), findsOneWidget);
    expect(tester.getSize(keyed('recipe-workers-framed-pair')).width, 76);
    expect(
      tester.getSize(keyed('recipe-workers-cp-field-CP budget')),
      const Size(86, 38), // 88px field minus the existing 1px material rim.
    );
    expect(
      tester.getSize(keyed('recipe-workers-cp-field-CP left')),
      const Size(86, 38),
    );
    final fields = tester.getRect(keyed('recipe-workers-cp-field-CP left'));
    final pair = tester.getRect(keyed('recipe-workers-framed-pair'));
    expect(pair.left, greaterThan(fields.right));
    expect(pair.bottom, closeTo(fields.bottom, 1));
    final actionPositions = [
      'nodes',
      'auto',
      'add-items',
    ].map((a) => tester.getRect(keyed('recipe-workers-$a'))).toList();
    expect(actionPositions.map((r) => r.center.dy).toSet().length, 1);
    expect(actionPositions.first.top, greaterThan(pair.bottom));
    await tester.tap(keyed('recipe-workers-summary'));
    await tester.pumpAndSettle();
    expect(keyed('recipe-workers-expanded'), findsOneWidget);
    expect(keyed('recipe-shelf-First'), findsOneWidget);
    expect(c.plan, same(currentPlan));
    expect(saves, initialSaves);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    for (var i = 0; i < actionPositions.length; i++) {
      final key = 'recipe-workers-${['nodes', 'auto', 'add-items'][i]}';
      expect(tester.getRect(keyed(key)), actionPositions[i]);
      expect(keyed(key).hitTestable(), findsOneWidget);
    }
    await tester.tap(keyed('recipe-workers-nodes'));
    await tester.pumpAndSettle();
    c.back();
    await tester.pumpAndSettle();
    expect(keyed('recipe-workers-expanded'), findsOneWidget);
    await tester.tap(keyed('recipe-workers-summary'));
    await tester.pumpAndSettle();
    expect(keyed('recipe-workers-expanded'), findsNothing);
    expect(c.targets, ['First', 'Second']);
    expect(c.plan, same(currentPlan));
    expect(saves, initialSaves);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('plus adds inline and row crosses remove only their recipe', (
    tester,
  ) async {
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
    await tester.pumpWidget(panel(c));
    await tester.pumpAndSettle();
    await tester.tap(keyed('recipe-workers-picker'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Third'));
    await settlePlan(tester, c);
    expect(c.targets, ['First', 'Second', 'Third']);
    expect(find.text('+1'), findsOneWidget);
    expect(keyed('recipe-workers-expanded'), findsNothing);
    await tester.tap(keyed('recipe-workers-summary'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('recipe-shelf-Third'));
    await tester.pumpAndSettle();
    expect(keyed('recipe-workers-recipe-search'), findsNothing);
    expect(c.targets, ['First', 'Second', 'Third']);
    expect(
      find.descendant(
        of: keyed('recipe-shelf-Third'),
        matching: find.byIcon(Icons.expand_more),
      ),
      findsNothing,
    );
    expect(
      tester.widget<IconButton>(keyed('recipe-remove-Third')).icon,
      isA<Icon>().having((i) => i.icon, 'remove glyph', Icons.close),
    );
    await tester.ensureVisible(keyed('recipe-remove-Third'));
    await tester.tap(keyed('recipe-remove-Third'));
    await settlePlan(tester, c);
    expect(c.targets, ['First', 'Second']);
    expect(find.text('+1'), findsNothing);
    expect(keyed('recipe-workers-recipe-search'), findsNothing);
    await tester.tap(keyed('recipe-workers-picker'));
    await tester.pumpAndSettle();
    await tester.enterText(keyed('recipe-workers-recipe-search'), 'Third');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Third'));
    await tester.tap(find.widgetWithText(ListTile, 'Third'));
    await settlePlan(tester, c);
    expect(c.targets, ['First', 'Second', 'Third']);
    // Removing every selection leaves the plus usable and never deletes
    // catalog recipes. The empty summary is no longer a second search action.
    for (final name in ['Second', 'Third', 'First']) {
      await tester.ensureVisible(keyed('recipe-remove-$name'));
      await tester.tap(keyed('recipe-remove-$name'));
      await settlePlan(tester, c);
    }
    expect(c.targets, isEmpty);
    expect(keyed('recipe-workers-expanded'), findsNothing);
    expect(
      tester.widget<TextButton>(keyed('recipe-workers-summary')).onPressed,
      isNull,
    );
    expect(c.catalog!.targets, containsAll(['First', 'Second', 'Third']));
    await tester.tap(keyed('recipe-workers-picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'First'));
    await settlePlan(tester, c);
    expect(c.targets, ['First']);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  for (final width in [280.0, 300.0, 380.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final count in [0, 1, 4]) {
        testWidgets('$count long recipes at $width and text $scale fit', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(500, 700);
          addTearDown(tester.view.reset);
          final names = List.generate(
            4,
            (i) => 'A very long Harmony Draught recipe name $i',
          );
          final c = RecipeWorkerController(
            catalogBuilder: () => RecipeWorkerCatalog({
              for (final name in names) name: workerRecipe(name, {'A': 1}),
            }, PlannerRules()),
            loadMap: () async => workerMap(),
            loadEconomics: () async => workerEconomics(),
            initial: BdoRecipeWorkerPreferences(
              targets: names.take(count).toList(),
              budget: 8,
            ),
            onSave: (_) {},
          );
          await tester.runAsync(c.load);
          await tester.pumpWidget(panel(c, width: width, scale: scale));
          await tester.pumpAndSettle();
          expect(keyed('recipe-workers-picker').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          final left = tester.getRect(keyed('recipe-workers-cp-field-CP left'));
          final budget = tester.getRect(
            keyed('recipe-workers-cp-field-CP budget'),
          );
          expect(left.size, budget.size);
          expect(left.top, budget.top);
          if (count > 0) {
            await tester.tap(keyed('recipe-workers-summary'));
            await tester.pumpAndSettle();
            expect(keyed('recipe-shelf-${names.first}'), findsOneWidget);
            await tester.ensureVisible(
              keyed('recipe-shelf-${names[count - 1]}'),
            );
            await tester.pumpAndSettle();
            final remove = keyed('recipe-remove-${names[count - 1]}');
            expect(remove.hitTestable(), findsOneWidget);
            final rowBounds = tester.getRect(
              keyed('recipe-shelf-${names[count - 1]}'),
            );
            final removeBounds = tester.getRect(remove);
            expect(removeBounds.right, lessThanOrEqualTo(rowBounds.right));
            expect(removeBounds.bottom, lessThanOrEqualTo(rowBounds.bottom));
            expect(
              keyed('recipe-workers-picker').hitTestable(),
              findsOneWidget,
            );
            expect(keyed('recipe-workers-nodes').hitTestable(), findsOneWidget);
          }
          // The fixed + must reveal the inline search even after scrolling
          // through many expanded recipe rows at enlarged text sizes.
          await tester.tap(keyed('recipe-workers-picker'));
          await tester.pumpAndSettle();
          expect(
            keyed('recipe-workers-recipe-search').hitTestable(),
            findsOneWidget,
          );
          expect(keyed('recipe-workers-nodes').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        });
      }
    }
  }
}
