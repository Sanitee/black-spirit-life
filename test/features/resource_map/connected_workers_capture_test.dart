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
import 'package:bdo_gathering_companion/src/domain/models.dart' as gathering;
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/application_test_harness.dart';

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
  testWidgets('real Harmony flow, artwork, compact checklist and node frames', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(440, 980));
    final loaded = (await tester.runAsync(
      () => ApplicationTestHarness.create(
        backgroundId: SakuraNightGardenSpec.theme.id,
      ),
    ))!;
    await tester.runAsync(loaded.disposeControllerOnly);
    final harness = loaded.rebindControllerInCurrentZone();
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
      catalogBuilder: () => RecipeWorkerCatalog(recipes, app.plannerRules),
      loadMap: BdoResourceMapLoader.loadBundled,
      loadEconomics: BdoWorkerEconomicsLoader.loadBundled,
      initial: BdoRecipeWorkerPreferences(
        target: 'Harmony Draught',
        budget: 550,
      ),
      onSave: (_) {},
    );
    await tester.runAsync(c.load);
    expect(c.error, isNull);
    expect(c.leaves.any((l) => l.name == 'Bottle of River Water'), isFalse);
    expect(c.leaves.any((l) => l.name == 'Purified Water' && l.vendor), isTrue);
    final spec = SakuraNightGardenSpec.theme;
    final catalog = (await tester.runAsync(gathering.Catalog.load))!;
    bool hasSpot(String name) =>
        catalog.spots.any(
          (spot) =>
              spot.mapped &&
              spot.methodIds.any(
                (method) => catalog
                    .lootForSpot(spot, method)
                    .any(
                      (item) => item.name.toLowerCase() == name.toLowerCase(),
                    ),
              ),
        ) ||
        c.pointsFor(name).isNotEmpty;
    for (final name in ['workers', 'add-items', 'nodes', 'checklist']) {
      c.showPage(switch (name) {
        'add-items' => RecipeWorkerPage.items,
        'nodes' => RecipeWorkerPage.nodes,
        _ => RecipeWorkerPage.recipe,
      });
      if (name == 'nodes') {
        for (final n in c.investmentNodes.take(2)) {
          c.toggleInvested(n.id);
        }
      }
      for (final scale in [1.0, 2.0]) {
        final checklist = name == 'checklist';
        await tester.pumpWidget(
          MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: const ValueKey('capture'),
                    child: ResourceMapThemeAdapter(
                      spec: spec,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AnimatedBuilder(
                          animation: c,
                          builder: (context, _) {
                            final panel = RecipeWorkerPanel(
                              key: ValueKey('$name-$scale'),
                              controller: c,
                              hosted: !checklist,
                              checklist: checklist,
                              onClose: checklist ? () {} : null,
                              hasSpot: hasSpot,
                              onSpot: (_) {},
                              onNode: (_) {},
                              onSetup: checklist ? null : () {},
                              artwork: (item, size) => ModeItemIcon(
                                controller: app.active,
                                name: item,
                                size: size,
                                searchAcrossModes: true,
                                catalogRepository: CatalogRepository(
                                  harness.bundle.catalog,
                                ),
                              ),
                            );
                            return checklist
                                ? AppSurface(child: panel)
                                : ResourceMapJourneySurface(
                                    title: c.pageTitle,
                                    onBack: c.back,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: panel,
                                    ),
                                  );
                          },
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
        final out = Platform.environment['BSL_RECIPE_WORKERS_CAPTURE_DIR'];
        if (out != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$out/$name-$scale.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(harness.dispose);
  });
}
