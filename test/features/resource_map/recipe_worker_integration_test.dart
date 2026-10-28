import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_panel.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/recipe_checklist.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_map.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/town_shop_lodging_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'recipe_worker_fixture.dart';

class _MemoryStore extends SessionStore {
  _MemoryStore(Directory directory) : super(directory: directory);
  int writes = 0;
  @override
  Future<void> save() async {
    writes++;
  }
}

void main() {
  testWidgets(
    'Plan uses supplied artwork, hides hosted status and draws its shared CP network',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 950);
      addTearDown(tester.view.reset);
      final cache = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('recipe-map-test-'),
      ))!;
      final c = RecipeWorkerController(
        catalogBuilder: workerCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(target: 'Target', budget: 8),
        onSave: (_) {},
      );
      await tester.runAsync(c.load);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xff182b30), BlendMode.src);
      final picture = recorder.endRecording();
      final tile = await tester.runAsync(() async {
        final image = await picture.toImage(256, 256);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return bytes!.buffer.asUint8List();
      });
      picture.dispose();
      final client = MockClient(
        (_) async => http.Response.bytes(
          tile!,
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: c,
            builder: (context, _) => BdoResourceMap(
              dataset: c.data!,
              cacheDirectory: cache,
              tileHttpClient: client,
              showSourceNotice: false,
              recipeWorkerPlan: c.plan?.network,
              recipePlanArtwork: const SizedBox(
                key: ValueKey('test-harmony-artwork'),
                width: 30,
                height: 30,
              ),
              recipeWorkerTitle: c.pageTitle,
              onRecipeWorkerBack: c.back,
              recipeWorkerBuilder: (_, setup, node) => RecipeWorkerPanel(
                controller: c,
                hosted: true,
                onSetup: setup,
                onNode: node,
                artwork: (_, size) => SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Workers'), findsNothing);
      expect(
        find.byKey(const ValueKey('test-harmony-artwork')),
        findsOneWidget,
      );
      expect(find.byTooltip('Show map status details'), findsNothing);
      expect(
        find.byKey(const ValueKey('resource-map-status-toggle')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resource-map-status-animation')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('resource-map-home-worker-income')),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find.byKey(const ValueKey('recipe-workers-budget')),
        findsOneWidget,
      );
      expect(find.text('Worker income').hitTestable(), findsNothing);
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.nodeNetworkChangeKinds.keys.toSet(), c.plan!.nodeIds);
      expect(canvas.nodeNetworkEdgeChanges, isNotEmpty);
      expect(find.text('Nodes'), findsOneWidget);
      expect(find.byTooltip('Worker settings'), findsOneWidget);
      expect(find.text('Specific items'), findsNothing);
      await tester.tap(find.byTooltip('Worker settings'));
      await tester.pumpAndSettle();
      expect(find.byType(TownShopLodgingDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(TownShopLodgingDialog))).pop();
      await tester.pumpAndSettle();
      expect(c.budget, 8);
      expect(
        find.byKey(const ValueKey('resource-map-home-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('resource-map-atlas-workspace-minimize')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('recipe-workers-add-items')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Add items'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-workers-item-search')),
        'A',
      );
      await tester.tap(find.byKey(const ValueKey('resource-map-task-back')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find.byKey(const ValueKey('recipe-workers-budget')),
        findsOneWidget,
      );
      expect(c.budget, 8);
      await tester.tap(find.byKey(const ValueKey('recipe-workers-nodes')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Invest nodes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('resource-map-task-back')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('recipe-workers-minus-A')));
      for (var i = 0; i < 100 && c.busy; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(c.busy, isFalse);
      expect(c.plan!.remaining, 1);
      final after = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(after.nodeNetworkChangeKinds.keys.toSet(), c.plan!.nodeIds);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      client.close();
      await tester.runAsync(() => cache.delete(recursive: true));
    },
  );

  testWidgets(
    'Gathering checklist opens from Workers and navigates only to recorded loot spots',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 950);
      addTearDown(tester.view.reset);
      const channel = MethodChannel('bdo_gathering/native');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final catalog = (await tester.runAsync(Catalog.load))!;
      final spot = catalog.spots.firstWhere(
        (s) => s.mapped && catalog.lootForSpot(s, s.methodIds.first).isNotEmpty,
      );
      final item = catalog.lootForSpot(spot, spot.methodIds.first).first.name;
      final map = (await tester.runAsync(BdoResourceMapLoader.loadBundled))!;
      final recorded = map.gatheringPoints.first;
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('recipe-gather-test-'),
      ))!;
      final store = _MemoryStore(directory)
        ..preferences = {
          'methodId': 'butcher',
          'spotId': 'imp-cave-wolves',
          'sentinel': 'keep',
        };
      final controller = GatheringRecipeChecklistController()..open();
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(
            visualPalette: CompanionVisualPalette.fieldDesk,
          ),
          builder: companionBackdropBuilder,
          home: CompanionHome(
            catalog: catalog,
            store: store,
            glassOpacityPercent: 70,
            onGlassOpacityChanged: (_) {},
            recipeChecklistController: controller,
            recipeChecklistBuilder: (context, hasSpot, showSpot, close, locations) {
              expect(hasSpot(item), isTrue);
              expect(hasSpot('not an actual item'), isFalse);
              return Column(
                children: [
                  IconButton(
                    tooltip: 'Close checklist',
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                  TextButton(
                    key: const ValueKey('test-show-spot'),
                    onPressed: () => showSpot(item),
                    child: Text(item),
                  ),
                  TextButton(
                    key: const ValueKey('test-show-locations'),
                    onPressed: () => locations(
                      GatheringRecipeLocations(
                        item: 'Recorded test location',
                        sourceNote:
                            'Historical source; not a current spawn guarantee.',
                        points: [
                          GatheringRecipePoint(
                            id: recorded.id,
                            x: recorded.location.x,
                            z: recorded.location.z,
                            label: recorded.label,
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Recorded locations'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close checklist'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('test-show-spot')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close checklist'), findsNothing);
      final guide = tester.widget<FieldGuide>(find.byType(FieldGuide));
      expect(guide.initialSpot, isNotNull);
      expect(guide.initialSpot!.mapped, isTrue);
      expect(
        guide.initialSpot!.methodIds.any(
          (m) => catalog
              .lootForSpot(guide.initialSpot!, m)
              .any((i) => i.name == item),
        ),
        isTrue,
      );
      expect(guide.navigationRequest, greaterThan(0));
      expect(guide.onReturnToChecklist, isNotNull);
      await tester.tap(find.byKey(const ValueKey('guide-change-spot')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-show-spot')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('test-show-locations')));
      await tester.pumpAndSettle();
      final points = tester
          .widget<SpotMap>(
            find.byKey(
              const ValueKey('recipe-locations-Recorded test location'),
            ),
          )
          .locationPoints;
      expect(points.single.x, recorded.location.x);
      expect(points.single.z, recorded.location.z);
      expect(
        find.byKey(ValueKey('recipe-location-${recorded.id}')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back to checklist'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-show-spot')), findsOneWidget);
      expect(store.preferences['sentinel'], 'keep');
      expect(store.sessions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}
