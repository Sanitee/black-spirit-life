import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_panel.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/application_test_harness.dart';
import 'recipe_worker_fixture.dart';

void main() {
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
        'C:/Windows/Fonts/segoeuib.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'Roboto': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  testWidgets(
    'budget edits disable additions immediately; zero CP disables all plus buttons',
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
              width: 420,
              child: RecipeWorkerPanel(
                controller: c,
                artwork: (_, size) => SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.error, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-workers-budget')),
        '0',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('recipe-workers-plus-A')),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 100 && c.busy; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(c.busy, isFalse);
      await tester.pumpAndSettle();
      expect(c.plan!.spent, 0);
      expect(c.plan!.remaining, 0);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('recipe-workers-plus-B')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'checklist marks only its own state and exposes only real spot actions',
    (tester) async {
      BdoRecipeWorkerPreferences? saved;
      final c = RecipeWorkerController(
        catalogBuilder: workerCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(target: 'Target', budget: 8),
        onSave: (v) => saved = v,
      );
      await tester.runAsync(c.load);
      String? shown;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: RecipeWorkerPanel(
                controller: c,
                checklist: true,
                hasSpot: (name) => name == 'Milk',
                onSpot: (name) => shown = name,
                artwork: (_, size) => SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('A'), findsNothing);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(saved!.checkedItems, {'Milk'});
      await tester.tap(find.byTooltip('Show gathering spot'));
      expect(shown, 'Milk');
      expect(c.plan!.spent, 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final spec in [
    StandardSpec.theme,
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final width in [280.0, 440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('actual artwork ${spec.id} panel $width at $scale', (
          tester,
        ) async {
          configureApplicationTestSurface(tester, const Size(950, 1000));
          final harness = (await tester.runAsync(
            () => ApplicationTestHarness.create(backgroundId: spec.id),
          ))!;
          final app = harness.bundle.controller;
          final recipes = <String, Recipe>{};
          for (final mode in app.modes.values) {
            for (final r in mode.recipes.values) {
              if (r.isCraftable || recipes[r.name]?.isCraftable != true) {
                recipes[r.name] = r;
              }
            }
          }
          final c = RecipeWorkerController(
            catalogBuilder: () =>
                RecipeWorkerCatalog(recipes, app.plannerRules),
            loadMap: BdoResourceMapLoader.loadBundled,
            loadEconomics: BdoWorkerEconomicsLoader.loadBundled,
            initial: BdoRecipeWorkerPreferences(target: 'Milk Tea', budget: 78),
            onSave: (_) {},
          );
          await tester.runAsync(c.load);
          expect(c.error, isNull);
          const key = ValueKey('worker-capture');
          await tester.pumpWidget(
            MaterialApp(
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        height: 960,
                        child: RepaintBoundary(
                          key: key,
                          child: ResourceMapThemeAdapter(
                            spec: spec,
                            child: AppSurface(
                              padding: const EdgeInsets.all(10),
                              child: RecipeWorkerPanel(
                                controller: c,
                                onGathering: () {},
                                artwork: (name, size) => ModeItemIcon(
                                  controller: app.active,
                                  catalogRepository: CatalogRepository(
                                    harness.bundle.catalog,
                                  ),
                                  name: name,
                                  size: size,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await Future.wait([
              for (final e in find.byType(Image).evaluate())
                precacheImage((e.widget as Image).image, e),
            ]);
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final budget = tester.getRect(
            find.byKey(const ValueKey('recipe-workers-cp-field-CP budget')),
          );
          final remaining = tester.getRect(
            find.byKey(const ValueKey('recipe-workers-cp-field-CP left')),
          );
          expect(budget.size, remaining.size);
          expect(budget.top, remaining.top);
          expect(find.byType(Image), findsWidgets);
          expect(find.textContaining('per hour'), findsNothing);
          final output = Platform.environment['BSL_RECIPE_WORKERS_CAPTURE_DIR'];
          if (output != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(key),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('$output/workers-${spec.id}-$width-$scale.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          await tester.runAsync(harness.dispose);
        });
      }
    }
  }
}
