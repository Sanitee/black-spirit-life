import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets(
    'Recipe Book map lookup restores its search, scroll, filter, and preview',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);

      await tester.tap(find.byKey(PlannerActionKeys.p03));
      await _pumpWorkspace(tester);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);

      final search = find.descendant(
        of: find.byKey(RecipeBookKeys.r03Search),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'e');
      await tester.tap(find.byKey(RecipeBookKeys.r05SearchByIngredient));
      await tester.pump(const Duration(milliseconds: 120));

      final details = find.byKey(
        RecipeBookKeys.r13Details('Insectivore Plant Powder'),
      );
      final cardScroll = find.descendant(
        of: find.byKey(RecipeBookKeys.r10CardScroll),
        matching: find.byType(Scrollable),
      );
      expect(cardScroll, findsOneWidget);
      await tester.scrollUntilVisible(details, 260, scrollable: cardScroll);
      await tester.pump();
      expect(details, findsOneWidget);

      final scrollPosition = tester.state<ScrollableState>(cardScroll).position;
      expect(scrollPosition.pixels, greaterThan(0));
      final savedScrollOffset = scrollPosition.pixels;

      await tester.tap(details);
      await tester.pump(const Duration(milliseconds: 180));
      final preview = find.byKey(RecipeBookKeys.previewPanel);
      expect(preview, findsOneWidget);

      final bookWidget = tester.widget<RecipeBookModal>(
        find.byType(RecipeBookModal),
      );
      final bookController = bookWidget.controller;
      final bookElement = tester.element(find.byKey(RecipeBookKeys.modal));
      final previewElement = tester.element(preview);
      expect(bookController.search, 'e');
      expect(bookController.searchByIngredient, isTrue);
      expect(bookController.previewName, 'Insectivore Plant Powder');
      expect(bookController.scrollOffset, closeTo(savedScrollOffset, 0.1));

      final ingredientRegion = find.byKey(
        RecipeBookKeys.mapLookupRegion(
          'Insectivore Plant Powder',
          0,
          'Insectivore Plant Flower',
        ),
      );
      expect(ingredientRegion, findsOneWidget);
      await tester.tap(
        ingredientRegion,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      const stableId =
          'recipe-preview:Insectivore Plant Powder:0:'
          'Insectivore Plant Flower';
      final showGathering = find.byKey(
        PlannerActionKeys.mapLookupAction(
          stableId,
          PlannerMapLookupSource.manualGathering.name,
        ),
      );
      expect(showGathering, findsOneWidget);
      expect(find.text('Show source on map'), findsOneWidget);
      await tester.tap(showGathering);
      await tester.pump();
      await _pumpUntilMapIsReady(tester);
      await tester.pump(const Duration(milliseconds: 220));

      expect(_isSelected(tester, _workspaceTab('Craft Planner')), isFalse);
      expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
      expect(find.byType(BdoResourceMap), findsOneWidget);
      final mapCanvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        mapCanvas.gatheringPoints,
        isEmpty,
        reason: 'the Flower source has guidance but no trustworthy exact dots',
      );
      expect(mapCanvas.gatheringSpots, isEmpty);
      expect(mapCanvas.gatheringRoutes, isEmpty);
      expect(mapCanvas.workerNodes, isEmpty);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(
                TextField,
                'Find an item, source, node or town',
              ),
            )
            .controller
            ?.text,
        'Insectivore Plant Flower',
      );
      final mapDetails = find.byKey(
        const ValueKey<String>('resource-map-sidebar-details'),
      );
      expect(mapDetails, findsOneWidget);
      expect(
        find.descendant(
          of: mapDetails,
          matching: find.text('Poisonous Swamp Plant'),
        ),
        findsWidgets,
      );
      expect(
        find.byKey(RecipeBookKeys.modal, skipOffstage: false),
        findsOneWidget,
        reason: 'the open Recipe Book stays mounted behind the map',
      );
      expect(
        find.byKey(RecipeBookKeys.previewPanel, skipOffstage: false),
        findsOneWidget,
      );

      await tester.tap(_workspaceTab('Craft Planner'));
      await tester.pump(const Duration(milliseconds: 180));

      expect(_isSelected(tester, _workspaceTab('Craft Planner')), isTrue);
      expect(_isSelected(tester, _workspaceTab('Resource Map')), isFalse);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      expect(find.byKey(RecipeBookKeys.previewPanel), findsOneWidget);
      expect(
        tester.element(find.byKey(RecipeBookKeys.modal)),
        same(bookElement),
      );
      expect(
        tester.element(find.byKey(RecipeBookKeys.previewPanel)),
        same(previewElement),
      );
      expect(
        tester.widget<RecipeBookModal>(find.byType(RecipeBookModal)).controller,
        same(bookController),
      );
      expect(tester.widget<TextField>(search).controller?.text, 'e');
      expect(bookController.searchByIngredient, isTrue);
      expect(bookController.previewName, 'Insectivore Plant Powder');
      expect(
        tester.state<ScrollableState>(cardScroll).position.pixels,
        closeTo(savedScrollOffset, 0.1),
      );
      expect(bookController.scrollOffset, closeTo(savedScrollOffset, 0.1));
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );
}

Finder _workspaceTab(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == label,
  description: '$label top-level workspace tab',
);

bool? _isSelected(WidgetTester tester, Finder tab) =>
    tester.widget<Semantics>(tab).properties.selected;

MockClient _localFailureTileClient() {
  return MockClient(
    (request) async => http.Response(
      'Tile networking is disabled by the integration-test fixture.',
      HttpStatus.serviceUnavailable,
    ),
  );
}

ResourceMapWorkspaceConfiguration _testMapConfiguration(
  ApplicationTestHarness harness,
  http.Client tileClient,
) {
  return ResourceMapWorkspaceConfiguration(
    cacheDirectory: Directory(
      '${harness.temporaryDirectory.path}${Platform.pathSeparator}map-cache',
    ),
    tileHttpClient: tileClient,
    showSourceNotice: false,
  );
}

Future<ApplicationTestHarness> _createHarness(WidgetTester tester) async {
  var harness = (await tester.runAsync(() => ApplicationTestHarness.create()))!;
  await tester.runAsync(harness.disposeControllerOnly);
  await tester.runAsync(BdoResourceMapLoader.loadBundled);
  await tester.runAsync(BdoWorkerEconomicsLoader.loadBundled);
  await tester.runAsync(LodgingDataLoader.loadBundled);
  harness = harness.rebindControllerInCurrentZone();
  return harness;
}

Future<void> _pumpWorkspace(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pumpUntilMapIsReady(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(BdoResourceMap).evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    find.byType(BdoResourceMap),
    findsOneWidget,
    reason: 'the bundled resource-map dataset should load without networking',
  );
}

Future<void> _disposeWidgetHarness(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var disposed = false;
  final disposeFuture = harness.bundle.controller.dispose().whenComplete(
    () => disposed = true,
  );
  for (var attempt = 0; attempt < 20 && !disposed; attempt++) {
    await tester.pump();
  }
  expect(disposed, isTrue, reason: 'controller disposal must drain in-zone');
  await disposeFuture;
  await tester.runAsync(() async {
    if (await harness.temporaryDirectory.exists()) {
      await harness.temporaryDirectory.delete(recursive: true);
    }
  });
}
