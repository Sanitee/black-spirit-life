import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() async {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    if (const bool.fromEnvironment('CAPTURE_PLANNER_WEEDS')) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final family in {
        'Segoe UI': ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf'],
        'Georgia': ['georgia.ttf', 'georgiab.ttf', 'georgiai.ttf'],
      }.entries) {
        final loader = FontLoader(family.key);
        for (final font in family.value) {
          loader.addFont(
            File(
              'C:/Windows/Fonts/$font',
            ).readAsBytes().then(ByteData.sublistView),
          );
        }
        await loader.load();
      }
    }
  });

  for (final fixture in const [
    (name: 'Clear Liquid Reagent', weeds: 1.0, grass: 1.0),
    (name: 'Pure Powder Reagent', weeds: 1.0, grass: 1.0),
    (name: 'Elixir of Concentration', weeds: 8.0, grass: 2.0),
  ]) {
    testWidgets(
      '${fixture.name} Need First chooser switches exact quantities',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1500, 940);
        addTearDown(tester.view.reset);
        final controller = _controller(catalog, fixture.name);
        addTearDown(controller.dispose);
        final mode = controller.active;
        expect(mode.plan.value.missing.single.name, 'Weeds');
        expect(mode.plan.value.missing.single.need, fixture.weeds);
        final inventoryBefore = Map<String, double>.of(
          mode.state.value.inventory,
        );
        final captureKey = GlobalKey();
        var marketChecks = 0;
        final actions = PlannerExternalActions(
          openRecipeBook: (_) {},
          copyName: (_) async {},
          checkPrices: (_) async {
            marketChecks++;
            return const PlannerMarketRefresh(
              prices: {'Weeds': 100, 'Wild Grass': 200},
              stock: {'Weeds': 0, 'Wild Grass': 100},
              unlistedItemNames: {},
              fetchedAt: 1789351200000,
              summary: 'Market checked.',
            );
          },
        );
        final spec = StandardSpec.theme;
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: AppOverlayCoordinatorHost(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: spec.materialTheme(),
                home: ThemeSpecScope(
                  spec: spec,
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(18),
                      child: PlannerView(
                        controller: mode,
                        externalActions: actions,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PlannerActionKeys.p15));
        await tester.pumpAndSettle();
        expect(find.text('Stock 0'), findsOneWidget);
        expect(marketChecks, 1);

        final anchor = find.byKey(
          PlannerActionKeys.row('P12', 'missing:Weeds:Weeds'),
        );
        expect(anchor, findsOneWidget);
        await tester.ensureVisible(anchor);
        await tester.tap(anchor);
        await tester.pumpAndSettle();
        expect(
          find.byKey(PlannerActionKeys.row('P13', 'Wild Grass')),
          findsOneWidget,
        );
        if (const bool.fromEnvironment('CAPTURE_PLANNER_WEEDS')) {
          await _capture(tester, captureKey, fixture.name);
        }
        await tester.tap(
          find.byKey(PlannerActionKeys.row('P13', 'Wild Grass')),
        );
        await tester.pumpAndSettle();
        expect(mode.plan.value.missing.single.name, 'Wild Grass');
        expect(mode.plan.value.missing.single.need, fixture.grass);
        expect(mode.state.value.substituteChoices, {
          'recipe:${fixture.name}:Weeds': 'Wild Grass',
        });
        expect(find.text('Stock 100'), findsOneWidget);
        expect(find.text('Stock 0'), findsNothing);
        expect(
          marketChecks,
          1,
          reason: 'Changing a choice must not request prices.',
        );

        await tester.tap(
          find.byKey(PlannerActionKeys.row('P12', 'missing:Wild Grass:Weeds')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PlannerActionKeys.row('P13', 'Weeds')));
        await tester.pumpAndSettle();
        expect(mode.plan.value.missing.single.name, 'Weeds');
        expect(mode.plan.value.missing.single.need, fixture.weeds);
        expect(mode.state.value.inventory, inventoryBefore);
        expect(mode.state.value.want, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

PlannerApplicationController _controller(
  CatalogSnapshot catalog,
  String target,
) {
  ModeState state(CraftMode mode) => ModeState(
    target: target,
    want: 1,
    ignoreIngredientInventory: false,
    bonusTarget: '',
    bonusWant: 1,
    market: MarketState(),
    inventory: {
      for (final row in catalog.alchemy.items[target]!.ingredients)
        if (row.name != 'Weeds') row.name: 1000,
    },
    substituteChoices: {'recipe:$target:Weeds': 'Weeds'},
    appearance: AppearanceSettings.defaultsFor(mode),
  );
  return PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 14),
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
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    const directory = String.fromEnvironment('PLANNER_WEEDS_CAPTURE_DIRECTORY');
    final file = File(
      '$directory/${name.toLowerCase().replaceAll(' ', '-')}.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
