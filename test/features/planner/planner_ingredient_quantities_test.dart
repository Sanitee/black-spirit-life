import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

Finder _quantity(String recipe, String ingredient, {bool perCraft = false}) =>
    find.byKey(
      ValueKey<String>(
        'planner-ingredient-${perCraft ? 'per-craft' : 'batch'}-quantity:'
        '$recipe:$ingredient',
      ),
    );

void main() {
  for (final mode in CraftMode.values) {
    testWidgets('${mode.name} shows formula and live plan totals together', (
      tester,
    ) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(activeMode: mode);
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      final recipe = switch (mode) {
        CraftMode.alchemy => 'Intermediate Reagent',
        CraftMode.cooking => 'Beer',
        CraftMode.processing => 'Wheat Flour',
      };
      final name = mode == CraftMode.alchemy ? 'Sunrise Herb' : 'Wheat';
      final formula = switch (mode) {
        CraftMode.alchemy => 'x2',
        CraftMode.cooking => 'x5',
        CraftMode.processing => 'x1',
      };
      for (final want in [10, 13709]) {
        harness.controller.active.updateState(
          (state) => state.copyWith(want: want),
          immediate: true,
        );
        await tester.pumpAndSettle();
        final step = harness.controller.active.plan.value.steps.firstWhere(
          (step) => step.name == recipe,
        );
        expect(
          tester.widget<Text>(_quantity(recipe, name, perCraft: true)).data,
          formula,
        );
        expect(
          tester.widget<Text>(_quantity(recipe, name)).data,
          formatQuantity(step.ingredients.single.need),
        );
        expect(
          tester.getRect(_quantity(recipe, name, perCraft: true)).right,
          lessThan(tester.getRect(_quantity(recipe, name)).left),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'real reagent formula and grouped totals at text scale $scale',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        if (const bool.fromEnvironment('CAPTURE_INGREDIENT_QUANTITIES')) {
          await tester.runAsync(_loadCaptureFonts);
        }
        final catalog = const BundledCatalogParser().parse(
          File('assets/data/app-data.json').readAsStringSync(),
        );
        ModeState state(CraftMode mode) => ModeState(
          target: 'Clear Liquid Reagent',
          bonusTarget: '',
          want: 34272,
          ignoreIngredientInventory: false,
          inventory: const {
            'Salt': 100000,
            'Sunrise Herb': 100000,
            'Purified Water': 100000,
            'Weeds': 100000,
          },
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(mode),
        );
        final controller = PlannerApplicationController(
          catalog: catalog,
          initialState: PlannerState(
            applicationVersion: 'test',
            lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 16),
            activeMode: CraftMode.alchemy,
            alchemy: state(CraftMode.alchemy),
            cooking: state(CraftMode.cooking),
            processing: state(CraftMode.processing),
            processingYields: const {},
            marketTax: MarketTax(),
            showDeleteTools: false,
          ),
          saveState: (state) async => state,
          saveDebounce: Duration.zero,
        );
        addTearDown(controller.dispose);
        final spec = SakuraNightGardenSpec.theme;
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: AppOverlayCoordinatorHost(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: spec.materialTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ThemeSpecScope(
                  spec: spec,
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(18),
                      child: PlannerView(
                        controller: controller.active,
                        externalActions: PlannerExternalActions(
                          openRecipeBook: (_) {},
                          copyName: (_) async {},
                          checkPrices: (_) async => const PlannerMarketRefresh(
                            prices: {},
                            stock: {},
                            unlistedItemNames: {},
                            fetchedAt: 0,
                            summary: '',
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
        final step = controller.active.plan.value.steps.firstWhere(
          (step) => step.name == 'Clear Liquid Reagent',
        );
        expect(step.count, 13709);
        for (final name in ['Salt', 'Sunrise Herb']) {
          final perCraft = _quantity(step.name, name, perCraft: true);
          final total = _quantity(step.name, name);
          expect(tester.widget<Text>(perCraft).data, 'x1');
          expect(tester.widget<Text>(total).data, '13.709');
          expect(
            tester.getRect(perCraft).right,
            lessThan(tester.getRect(total).left),
          );
        }
        expect(step.ingredients.firstWhere((i) => i.name == 'Salt').missing, 0);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_INGREDIENT_QUANTITIES')) {
          for (final element in find.byType(Image).evaluate()) {
            await tester.runAsync(
              () => precacheImage((element.widget as Image).image, element),
            );
          }
          await tester.pumpAndSettle();
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            const root = String.fromEnvironment(
              'INGREDIENT_CAPTURE_DIRECTORY',
              defaultValue: 'build/ingredient-quantity-review',
            );
            final file = File('$root/reagent-${(scale * 100).round()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
    );
  }
}

Future<void> _loadCaptureFonts() async {
  final root = Platform.environment['WINDIR'] ?? r'C:\Windows';
  for (final entry in {
    'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
    'Georgia': ['georgia.ttf', 'georgiab.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      loader.addFont(
        File(
          '$root/Fonts/$name',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final file = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/'
      'materialicons-regular.otf',
    );
    if (await file.exists()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(file.readAsBytes().then(ByteData.sublistView));
      await loader.load();
      break;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Could not locate Flutter material fonts.');
    }
    directory = directory.parent;
  }
}
