import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_desktop_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;
  late LodgingDataset lodgingDataset;
  late Directory cacheDirectory;
  late BdoTileSource tileSource;
  late MockClient tileClient;
  late List<int> tilePng;

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    lodgingDataset = await LodgingDataLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp(
      'bdo_resource_map_widget_test_',
    );
    tilePng = await _makeTileFixture();
    tileClient = MockClient(
      (request) async => http.Response.bytes(
        tilePng,
        HttpStatus.ok,
        headers: <String, String>{'content-type': 'image/png'},
      ),
    );
    tileSource = BdoTileSource(
      id: 'widget-test-tiles',
      displayName: 'Widget test tiles',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoTileSource.workermanCommunity.worldBounds,
      attribution: 'Generated test fixture',
      usageNotice: 'Only used by automated tests.',
      fileExtension: 'png',
    );
  });

  testWidgets('worker setup hides the deferred screenshot importer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            setupScreenshotPicker: () async => null,
            setupScreenshotClipboardReader: () async => null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>(
          'resource-map-worker-import-screenshot-shortcut',
        ),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(find.text('Scan screenshots', skipOffstage: false), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Your nodes',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Royal Workshop stays hidden from the worker map', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              royalWorkshopPlan: BdoRoyalWorkshopPlan(accessInvested: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.byKey(
        const ValueKey<String>('resource-map-shortcut-royal-workshop'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('resource-map-worker-royal-workshop-action'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-royal-workshop-manager')),
      findsNothing,
    );
    expect(find.textContaining('Royal Workshop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'house directory records owned uses without moving the map on town click',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calpheon = lodgingDataset.towns.singleWhere(
        (town) => town.name == 'Calpheon City',
      );
      final existingHouse = calpheon.housesById['house:2666']!;
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                currentOwnedHouseIds: <String>{existingHouse.id},
                currentHouseUsageTypeIds: <String, int>{existingHouse.id: 2},
              ),
              onNodeNetworkPreferencesChanged: updates.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-worker-houses-action')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('resource-map-sidebar-housing-directory'),
        ),
        findsOneWidget,
      );
      await _settleVisibleGoldenImages(
        tester,
        root: find.byType(BdoResourceMap),
      );
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_housing_directory.png'),
      );
      final canvasBefore = tester.widget<BdoMapCanvas>(
        find.byType(BdoMapCanvas),
      );
      final cameraBefore = canvasBefore.cameraController.camera;
      final calpheonTown = find.byKey(
        ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
      );
      await tester.tap(calpheonTown);
      await tester.pumpAndSettle();

      final cameraAfter = tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .cameraController
          .camera;
      expect(cameraAfter.center, cameraBefore.center);
      expect(cameraAfter.zoom, cameraBefore.zoom);
      expect(
        find.byKey(
          ValueKey<String>('resource-map-town-housing-${calpheon.townNodeId}'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 invested'), findsOneWidget);
      expect(find.text('Hired: not entered / Beds ready: 1'), findsOneWidget);
      expect(find.text('CP lodging ceiling: 95'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>('resource-map-house-filter-${calpheon.townNodeId}'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-fit-houses-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_housing.png'),
      );
      _expectHousingOverlayDeclutteredAndConnected(tester, calpheon);

      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-all-houses-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();
      final houseRow = find.byKey(
        ValueKey<String>('resource-map-house-row-${existingHouse.id}'),
      );
      final detailScrollable = find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('resource-map-sidebar-details'),
            ),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        houseRow,
        180,
        scrollable: detailScrollable,
      );
      await tester.tap(houseRow);
      await tester.pumpAndSettle();
      _expectHousingOverlayDeclutteredAndConnected(tester, calpheon);

      expect(
        find.byKey(
          ValueKey<String>('resource-map-house-flyout-${existingHouse.id}'),
        ),
        findsOneWidget,
      );
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_house_flyout.png'),
      );
      final houseFlyout = find.byKey(
        ValueKey<String>('resource-map-house-flyout-${existingHouse.id}'),
      );
      final houseFlyoutBefore = tester.getTopLeft(houseFlyout);
      await tester.drag(
        find.byKey(
          ValueKey<String>(
            'resource-map-house-drag-handle-${existingHouse.id}',
          ),
        ),
        const Offset(70, 35),
      );
      await tester.pump();
      expect(tester.getTopLeft(houseFlyout), isNot(houseFlyoutBefore));
      final storageChoice = find.byKey(
        ValueKey<String>('resource-map-house-usage-${existingHouse.id}-2'),
      );
      expect(storageChoice, findsOneWidget);
      await tester.scrollUntilVisible(
        storageChoice,
        -120,
        scrollable: detailScrollable,
      );
      expect(
        tester.getSemantics(storageChoice).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );

      final ownedCheckbox = find.byKey(
        ValueKey<String>('resource-map-house-row-owned-${existingHouse.id}'),
      );
      await tester.scrollUntilVisible(
        ownedCheckbox,
        180,
        scrollable: detailScrollable,
      );
      await tester.tap(ownedCheckbox);
      await tester.pump();
      expect(updates, isNotEmpty);
      expect(
        updates.last.currentOwnedHouseIds,
        isNot(contains(existingHouse.id)),
      );
      expect(
        updates.last.currentHouseUsageTypeIds,
        isNot(contains(existingHouse.id)),
      );

      final chainedHouse = calpheon.housesById['house:2333']!;
      final chainedHouseRow = find.byKey(
        ValueKey<String>('resource-map-house-row-${chainedHouse.id}'),
      );
      await tester.scrollUntilVisible(
        chainedHouseRow,
        180,
        scrollable: detailScrollable,
      );
      await tester.tap(chainedHouseRow);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-house-usage-${chainedHouse.id}-2'),
        ),
      );
      await tester.pump();
      expect(
        updates.last.currentOwnedHouseIds,
        containsAll(<String>{'house:2331', 'house:2332', chainedHouse.id}),
        reason: 'Choosing a use invests the complete prerequisite path.',
      );
      expect(updates.last.currentHouseUsageTypeIds[chainedHouse.id], 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary town and house selection preserve the camera', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calpheon = lodgingDataset.towns.singleWhere(
      (town) => town.name == 'Calpheon City',
    );
    final house = calpheon.housesById['house:2666']!;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();
    final housesAction = find.byKey(
      const ValueKey<String>('resource-map-worker-houses-action'),
    );
    final workerHubScrollable = find
        .descendant(
          of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      housesAction,
      220,
      scrollable: workerHubScrollable,
    );
    await tester.tap(housesAction);
    await tester.pumpAndSettle();

    final beforeTown = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;
    await tester.tap(
      find.byKey(
        ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
      ),
    );
    await tester.pumpAndSettle();
    final afterTown = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;
    expect(afterTown.center, beforeTown.center);
    expect(afterTown.zoom, beforeTown.zoom);

    await tester.tap(
      find.byKey(
        ValueKey<String>('resource-map-all-houses-${calpheon.townNodeId}'),
      ),
    );
    await tester.pumpAndSettle();
    final houseRow = find.byKey(
      ValueKey<String>('resource-map-house-row-${house.id}'),
    );
    final detailScrollable = find
        .descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-sidebar-details'),
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      houseRow,
      180,
      scrollable: detailScrollable,
    );
    final beforeHouse = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;

    await tester.tap(houseRow);
    await tester.pumpAndSettle();

    final afterHouse = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;
    expect(afterHouse.center, beforeHouse.center);
    expect(afterHouse.zoom, beforeHouse.zoom);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected house retains its detail snapshot across repeated pure pans',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calpheon = lodgingDataset.towns.singleWhere(
        (town) => town.name == 'Calpheon City',
      );
      final house = calpheon.housesById['house:2666']!;
      var selectedHouseSnapshotBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              debugOnSelectedHouseSnapshotBuilt: () {
                selectedHouseSnapshotBuilds += 1;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      final housesAction = find.byKey(
        const ValueKey<String>('resource-map-worker-houses-action'),
      );
      await tester.scrollUntilVisible(
        housesAction,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(housesAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-fit-houses-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-all-houses-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();
      final houseRow = find.byKey(
        ValueKey<String>('resource-map-house-row-${house.id}'),
      );
      await tester.scrollUntilVisible(
        houseRow,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('resource-map-sidebar-details'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(houseRow);
      await tester.pumpAndSettle();

      final selectedHouse = find.byKey(
        ValueKey<String>('resource-map-selected-house-${house.id}'),
      );
      expect(selectedHouse, findsOneWidget);
      expect(selectedHouseSnapshotBuilds, 1);
      final detailsWidgetBefore = tester.widget<Material>(selectedHouse);
      final detailsElementBefore = tester.element(selectedHouse);
      final controller = tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .cameraController;

      for (var index = 0; index < 24; index += 1) {
        controller.panBy(const Offset(1, .5), const Size(1200, 752));
        await tester.pump();
      }

      expect(
        selectedHouseSnapshotBuilds,
        1,
        reason:
            'Pure camera pans must not solve lodging or rebuild house details.',
      );
      expect(tester.widget<Material>(selectedHouse), same(detailsWidgetBefore));
      expect(tester.element(selectedHouse), same(detailsElementBefore));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Calpheon housing distinguishes current and theoretical capacity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calpheon = lodgingDataset.towns.singleWhere(
        (town) => town.name == 'Calpheon City',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      final housesAction = find.byKey(
        const ValueKey<String>('resource-map-worker-houses-action'),
      );
      await tester.scrollUntilVisible(
        housesAction,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(housesAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hired: not entered / Beds ready: 1'), findsOneWidget);
      expect(find.text('CP lodging ceiling: 95'), findsOneWidget);
      final plusControl = find.byKey(
        ValueKey<String>(
          'resource-map-lodging-target-plus-${calpheon.townNodeId}',
        ),
      );
      final minusControl = find.byKey(
        ValueKey<String>(
          'resource-map-lodging-target-minus-${calpheon.townNodeId}',
        ),
      );
      IconButton housingButton(Finder control) => tester.widget<IconButton>(
        find.descendant(of: control, matching: find.byType(IconButton)),
      );

      housingButton(plusControl).onPressed!.call();
      await tester.pump();
      expect(
        find.textContaining('Cheapest setup for 2 workers:'),
        findsOneWidget,
      );
      final twoWorkerPlan = LodgingOptimizer.solve(
        town: calpheon,
        requiredCapacity: 2,
        existingCapacity: 1,
      );
      for (final houseId in twoWorkerPlan.newlyRequiredHouseIds) {
        expect(
          find.byKey(
            ValueKey<String>('resource-map-recommended-house-$houseId'),
          ),
          findsOneWidget,
        );
      }

      housingButton(plusControl).onPressed!.call();
      await tester.pump();
      expect(
        find.textContaining('Cheapest setup for 3 workers:'),
        findsOneWidget,
      );

      housingButton(minusControl).onPressed!.call();
      await tester.pump();
      expect(
        find.textContaining('Cheapest setup for 2 workers:'),
        findsOneWidget,
      );
      for (final houseId in twoWorkerPlan.newlyRequiredHouseIds) {
        expect(
          find.byKey(
            ValueKey<String>('resource-map-recommended-house-$houseId'),
          ),
          findsOneWidget,
          reason:
              'Returning to the same target must reproduce the same exact '
              'cheapest housing recommendation.',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Calpheon housing plus stops at mapped and explicit bonus limits',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calpheon = lodgingDataset.towns.singleWhere(
        (town) => town.name == 'Calpheon City',
      );
      final ownedHouseIds = calpheon.housesById.keys.toSet();
      final activeLodgingUsages = <String, int>{
        for (final house in calpheon.lodgingHouses) house.id: 1,
      };
      final updates = <BdoNodeNetworkPreferences>[];

      BdoNodeNetworkPreferences preferences({required int bonus}) =>
          BdoNodeNetworkPreferences(
            currentOwnedHouseIds: ownedHouseIds,
            currentHouseUsageTypeIds: activeLodgingUsages,
            townWorkerCapacitiesByNodeId: <String, BdoTownWorkerCapacity>{
              calpheon.townNodeId: BdoTownWorkerCapacity(
                availableWorkerCount: 0,
                freeLodgingSlotCount: 0,
                hiredWorkerCount: 95,
                bonusLodgingSlotCount: bonus,
              ),
            },
          );

      Widget mapFor(BdoNodeNetworkPreferences networkPreferences) {
        return MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: networkPreferences,
              onNodeNetworkPreferencesChanged: updates.add,
            ),
          ),
        );
      }

      await tester.pumpWidget(mapFor(preferences(bonus: 0)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      final housesAction = find.byKey(
        const ValueKey<String>('resource-map-worker-houses-action'),
      );
      await tester.scrollUntilVisible(
        housesAction,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(housesAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hired: 95 / Beds ready: 95'), findsOneWidget);
      expect(find.text('CP lodging ceiling: 95'), findsOneWidget);
      final plusControl = find.byKey(
        ValueKey<String>(
          'resource-map-lodging-target-plus-${calpheon.townNodeId}',
        ),
      );
      IconButton plusButton() => tester.widget<IconButton>(
        find.descendant(of: plusControl, matching: find.byType(IconButton)),
      );
      expect(plusButton().onPressed, isNull);
      await tester.tap(plusControl, warnIfMissed: false);
      await tester.pump();
      expect(updates, isEmpty);

      await tester.pumpWidget(mapFor(preferences(bonus: 5)));
      await tester.pump();
      expect(find.text('Hired: 95 / Beds ready: 100'), findsOneWidget);
      expect(find.text('Housing limit including 5 bonus: 100'), findsOneWidget);
      expect(plusButton().onPressed, isNull);
      await tester.tap(plusControl, warnIfMissed: false);
      await tester.pump();
      expect(updates, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy worker capacity stays authoritative in the housing planner',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calpheon = lodgingDataset.towns.singleWhere(
        (town) => town.name == 'Calpheon City',
      );
      const availableWorkers = 3;
      const vacantLegacySlots = 5;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                townWorkerCapacitiesByNodeId: <String, BdoTownWorkerCapacity>{
                  calpheon.townNodeId: const BdoTownWorkerCapacity(
                    availableWorkerCount: availableWorkers,
                    freeLodgingSlotCount: vacantLegacySlots,
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _openNodePlanner(tester);
      final housesAction = find.byKey(
        const ValueKey<String>('resource-map-worker-houses-action'),
      );
      await tester.scrollUntilVisible(
        housesAction,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(housesAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Hired: not entered / Beds ready: '
          '${availableWorkers + vacantLegacySlots}',
        ),
        findsOneWidget,
        reason:
            'Older saves already describe usable workers plus vacant beds; '
            'the housing screen must not replace them with only mapped beds.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Shop lodging migrates legacy vacant slots without losing capacity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calpheon = lodgingDataset.towns.singleWhere(
        (town) => town.name == 'Calpheon City',
      );
      const availableWorkers = 3;
      const vacantLegacySlots = 5;
      const legacyTotal = availableWorkers + vacantLegacySlots;
      final legacyUnmappedSlots = math.max(
        legacyTotal - calpheon.baseWorkerSlots,
        0,
      );
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                townWorkerCapacitiesByNodeId: <String, BdoTownWorkerCapacity>{
                  calpheon.townNodeId: const BdoTownWorkerCapacity(
                    availableWorkerCount: availableWorkers,
                    freeLodgingSlotCount: vacantLegacySlots,
                  ),
                },
              ),
              onNodeNetworkPreferencesChanged: updates.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _openNodePlanner(tester);
      final housesAction = find.byKey(
        const ValueKey<String>('resource-map-worker-houses-action'),
      );
      await tester.scrollUntilVisible(
        housesAction,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(housesAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-shop-lodging-${calpheon.townNodeId}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                const ValueKey<String>('resource-map-shop-lodging-other'),
              ),
            )
            .controller!
            .text,
        '$legacyUnmappedSlots',
        reason:
            'Vacant capacity not represented by mapped houses must be '
            'carried into the migration instead of silently reset to zero.',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-shop-lodging-save')),
      );
      await tester.pumpAndSettle();

      final saved =
          updates.last.townWorkerCapacitiesByNodeId[calpheon.townNodeId]!;
      expect(saved.hiredWorkerCount, availableWorkers);
      expect(saved.availableWorkerCount, availableWorkers);
      expect(saved.freeLodgingSlotCount, vacantLegacySlots);
      expect(saved.otherBonusLodgingSlotCount, legacyUnmappedSlots);
      expect(
        saved.availableWorkerCount + saved.freeLodgingSlotCount,
        legacyTotal,
      );
      expect(
        find.text('Hired: $availableWorkers / Beds ready: $legacyTotal'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('town Shop lodging saves Pearl Loyalty and Other bonus sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calpheon = lodgingDataset.towns.singleWhere(
      (town) => town.name == 'Calpheon City',
    );
    final updates = <BdoNodeNetworkPreferences>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();
    final housesAction = find.byKey(
      const ValueKey<String>('resource-map-worker-houses-action'),
    );
    await tester.scrollUntilVisible(
      housesAction,
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(housesAction);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>('resource-map-housing-town-${calpheon.townNodeId}'),
      ),
    );
    await tester.pumpAndSettle();

    final shopAction = find.byKey(
      ValueKey<String>('resource-map-shop-lodging-${calpheon.townNodeId}'),
    );
    expect(shopAction, findsOneWidget);
    await tester.tap(shopAction);
    await tester.pumpAndSettle();
    expect(find.text('Shop lodging · Calpheon City'), findsOneWidget);

    final pearlPlus = find.byKey(
      const ValueKey<String>('resource-map-shop-lodging-pearl-plus'),
    );
    for (var count = 0; count < 3; count += 1) {
      await tester.tap(pearlPlus);
      await tester.pump();
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-loyalty')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-other')),
      '4',
    );
    await tester.pump();
    expect(find.text('Adds 8 bonus beds'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-shop-lodging-save')),
    );
    await tester.pumpAndSettle();

    expect(updates, isNotEmpty);
    final saved =
        updates.last.townWorkerCapacitiesByNodeId[calpheon.townNodeId]!;
    expect(saved.bonusLodgingSlotCount, 8);
    expect(saved.pearlLodgingPurchasedCount, 3);
    expect(saved.loyaltyLodgingPurchasedCount, 1);
    expect(saved.otherBonusLodgingSlotCount, 4);
    expect(saved.effectiveBonusLodgingSlotCount, 8);
    expect(find.text('Hired: 0 / Beds ready: 9'), findsOneWidget);
    expect(find.text('Housing limit including 8 bonus: 103'), findsOneWidget);
    expect(find.text('Shop lodging · +8 beds'), findsOneWidget);

    await tester.tap(shopAction);
    await tester.pumpAndSettle();
    expect(find.text('3 of 5 purchased'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(
              const ValueKey<String>('resource-map-shop-lodging-loyalty'),
            ),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(
              const ValueKey<String>('resource-map-shop-lodging-other'),
            ),
          )
          .controller!
          .text,
      '4',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('housing setup stays readable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final town =
        (lodgingDataset.towns.toList()
              ..sort((left, right) => left.name.compareTo(right.name)))
            .first;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();
    final scaledHousesAction = find.byKey(
      const ValueKey<String>('resource-map-worker-houses-action'),
    );
    final scaledWorkerHubScrollable = find
        .descendant(
          of: find.byKey(const ValueKey<String>('resource-map-worker-hub')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      scaledHousesAction,
      220,
      scrollable: scaledWorkerHubScrollable,
    );
    await tester.tap(scaledHousesAction);
    await tester.pumpAndSettle();

    expect(find.text('Your house network'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'The scalable town directory must not overflow.',
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('resource-map-housing-town-list')),
      const Offset(0, -380),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Scaled town rows must not overflow.',
    );
    final townRow = find.byKey(
      ValueKey<String>('resource-map-housing-town-${town.townNodeId}'),
    );
    expect(townRow, findsOneWidget);
    expect(
      tester.getSemantics(townRow).label,
      contains('Open connected house network'),
    );

    await tester.tap(townRow);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey<String>('resource-map-town-housing-${town.townNodeId}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('resource-map-house-filter-${town.townNodeId}'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  tearDownAll(() async {
    tileClient.close();
    final resolved = cacheDirectory.absolute.path;
    expect(
      resolved.contains('bdo_resource_map_widget_test_'),
      isTrue,
      reason: 'Only the test-created temporary directory may be removed.',
    );
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  testWidgets('Illuminated Atlas overview uses the Ledger map skin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.illuminatedAtlas,
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .chromeTheme
          .variant,
      ResourceMapChromeThemeVariant.illuminatedAtlas,
    );
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_overview_illuminated_atlas.png'),
    );
  });

  testWidgets('compact floating desktop home opens exact source details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
      'Find an item, source, node or town',
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-command-gather')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
      findsOneWidget,
    );
    final closedContextPanel = find.byKey(
      const ValueKey<String>('resource-map-desktop-sidebar-hidden'),
    );
    expect(
      closedContextPanel,
      findsOneWidget,
      reason: 'The map starts without a contextual panel covering it.',
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-gather-hub')),
      findsNothing,
      reason: 'The map starts without a source strip until Gather is chosen.',
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-hub')),
      findsNothing,
    );
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    expect(canvas.gatheringSpots, isEmpty);
    expect(canvas.gatheringPoints, isEmpty);
    expect(
      canvas.cameraController.camera.zoom,
      greaterThan(1.5),
      reason:
          'the first viewport should be fitted instead of using a fixed zoom',
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_overview.png'),
    );

    await tester.enterText(find.byType(TextField), 'Snake Meat');
    await tester.pumpAndSettle();
    final snakeResult = find.descendant(
      of: find.byType(ListTile),
      matching: find.text('Snake Meat'),
    );
    expect(snakeResult, findsOneWidget);

    await tester.tap(snakeResult);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Snake'), findsWidgets);
    expect(find.text('Products & methods'), findsNothing);
    expect(find.text('Exact locations'), findsNothing);
    expect(
      find.text('No matching material, node or gathering area.'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-details-card')),
      findsNothing,
      reason: 'Desktop details belong to the floating side sheet.',
    );
    final selectedCanvas = tester.widget<BdoMapCanvas>(
      find.byType(BdoMapCanvas),
    );
    final selectedViewport = tester.getSize(find.byType(BdoMapCanvas));
    final selectedBounds = selectedCanvas.cameraController.visibleWorldBounds(
      selectedViewport,
    );
    final tshiraPoints = selectedCanvas.gatheringPoints
        .where(
          (point) => point.areaId == 'gathering:tshira-snake-scorpion-rotation',
        )
        .toList(growable: false);
    expect(tshiraPoints, hasLength(21));
    expect(
      tshiraPoints.every(
        (point) => selectedBounds.contains(point.location.mapPoint),
      ),
      isTrue,
      reason: 'Snake Meat should open on the compact Tshira rotation.',
    );
    final desktopZoomRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-zoom-controls')),
    );
    final desktopSidebarRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-desktop-sidebar')),
    );
    expect(desktopZoomRect.overlaps(desktopSidebarRect), isFalse);
    expect(desktopSidebarRect.left, 0);
    expect(desktopSidebarRect.width, lessThan(460));
    expect(desktopSidebarRect.right, lessThan(desktopZoomRect.left));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_snake_meat.png'),
    );
  });

  testWidgets('node click opens an actionable map-anchored route summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final updates = <BdoNodeNetworkPreferences>[];
    BdoWorkerNode? candidate;
    BdoProductionNodePath? candidatePath;
    for (final node in dataset.workerNodes.where(
      (entry) =>
          entry.isProductionNode &&
          entry.nodeType != 'Excavation' &&
          entry.outputs.isNotEmpty,
    )) {
      final pathResult = const BdoProductionNodePathCostService().calculate(
        data: dataset,
        request: BdoProductionNodePathRequest(targetNodeId: node.id),
      );
      final path =
          pathResult.minimumIncrementalPath ?? pathResult.minimumTotalPath;
      if (path != null && path.connectNodeIds.isNotEmpty) {
        candidate = node;
        candidatePath = path;
        break;
      }
    }
    expect(candidate, isNotNull);
    expect(candidatePath, isNotNull);
    final selectedNode = candidate!;
    final expectedPath = candidatePath!;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final viewport = tester.getSize(find.byType(BdoMapCanvas));
    canvas.cameraController.setCamera(
      BdoMapCamera(center: selectedNode.location.mapPoint, zoom: 4.5),
      viewport,
    );
    await tester.pump();
    final cameraBefore = canvas.cameraController.camera;

    canvas.onHit(
      BdoMapHit(kind: BdoMapHitKind.workerNode, id: selectedNode.id),
    );
    await tester.pumpAndSettle();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.cameraController.camera.center, cameraBefore.center);
    expect(canvas.cameraController.camera.zoom, cameraBefore.zoom);
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );
    expect(find.text(selectedNode.siteName), findsWidgets);
    for (final output in selectedNode.outputs) {
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-node-quick-panel'),
          ),
          matching: find.text(output.name),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-add-route')),
      findsOneWidget,
    );
    expect(canvas.nodeNetworkEdgeChanges, isNotEmpty);

    await expectLater(
      find.byKey(const ValueKey<String>('resource-map-node-quick-boundary')),
      matchesGoldenFile('goldens/resource_map_node_quick_flyout.png'),
    );

    final nodeFlyout = find.byKey(
      ValueKey<String>('resource-map-node-quick-flyout-${selectedNode.id}'),
    );
    final nodeFlyoutBefore = tester.getTopLeft(nodeFlyout);
    await tester.drag(
      find.byKey(const ValueKey<String>('resource-map-node-quick-drag-handle')),
      const Offset(-80, 42),
    );
    await tester.pump();
    expect(tester.getTopLeft(nodeFlyout), isNot(nodeFlyoutBefore));
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel-tail')),
      findsNothing,
      reason: 'A manually positioned panel no longer points at the old node.',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-add-route')),
    );
    await tester.pumpAndSettle();

    expect(updates, isNotEmpty);
    expect(
      updates.last.currentNodeIds,
      containsAll(expectedPath.connectNodeIds),
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-add-route')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-toggle-invested')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .cameraController
          .camera,
      cameraBefore,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'excavation node keeps the planner and camera while showing unlock help',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final glishExcavation = dataset.workerNodesById['480']!;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await _openNodeMaterialTargets(tester);

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: glishExcavation.location.mapPoint, zoom: 5.2),
        viewport,
      );
      await tester.pump();
      final cameraBeforeNodeClick = canvas.cameraController.camera;

      canvas.onHit(
        BdoMapHit(kind: BdoMapHitKind.workerNode, id: glishExcavation.id),
      );
      await tester.pumpAndSettle();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.cameraController.camera, cameraBeforeNodeClick);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-sidebar-planned-network'),
        ),
        findsOneWidget,
        reason: 'The planner must remain available behind the node popup.',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-network-workbench-node-details'),
        ),
        findsNothing,
      );
      expect(find.text('EXCAVATION ACCESS'), findsOneWidget);
      expect(find.text('Mark Karu on map'), findsOneWidget);
      for (final output in glishExcavation.outputs) {
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('resource-map-node-quick-panel'),
            ),
            matching: find.text(output.name),
          ),
          findsOneWidget,
        );
      }

      final managerMarkerAction = find.byKey(
        const ValueKey<String>('resource-map-node-toggle-manager-marker'),
      );
      await tester.ensureVisible(managerMarkerAction);
      await tester.pump();
      await tester.tap(managerMarkerAction);
      await tester.pump();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-manager-marker-excavation:41086',
          ),
        ),
        findsOneWidget,
      );
      expect(canvas.cameraController.camera, cameraBeforeNodeClick);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Seoul click stays anchored and exposes only useful town actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seoul = dataset.workerNodesById['1852']!;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: seoul.location.mapPoint, zoom: 5.2),
        viewport,
      );
      await tester.pump();
      final cameraBeforeTownClick = canvas.cameraController.camera;

      canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: seoul.id));
      await tester.pumpAndSettle();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.cameraController.camera, cameraBeforeTownClick);
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      expect(find.text('Seoul'), findsWidgets);
      expect(find.text('Open Royal Workshops'), findsNothing);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-town-open-royal-workshops'),
        ),
        findsNothing,
      );
      expect(find.text('Yukjo workers & storage'), findsNothing);
      expect(find.text('Houses'), findsOneWidget);

      final openHouses = find.byKey(
        const ValueKey<String>('resource-map-town-open-houses'),
      );
      await tester.ensureVisible(openHouses);
      await tester.pump();
      await tester.tap(openHouses);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);

      expect(
        find.byKey(const ValueKey<String>('resource-map-town-housing-1853')),
        findsOneWidget,
      );
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.cameraController.camera, cameraBeforeTownClick);

      expect(find.textContaining('Royal Workshop'), findsNothing);
    },
  );

  testWidgets('Workers opens a direct task strip over the map', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();

    final workerHub = find.byKey(
      const ValueKey<String>('resource-map-worker-hub'),
    );
    expect(workerHub, findsOneWidget);
    expect(find.text('Cooking & Alchemy'), findsNothing);
    expect(find.text('Planned network'), findsOneWidget);
    expect(find.text('Best income'), findsOneWidget);
    expect(find.text('Find nodes'), findsOneWidget);
    expect(find.text('Plan a node network'), findsNothing);
    expect(find.text('What should your workers collect?'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-current-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-houses-action')),
      findsOneWidget,
    );
    expect(find.text('MAP DISPLAY'), findsNothing);
    expect(
      find
          .byKey(const ValueKey<String>('resource-map-desktop-edge-surface'))
          .hitTestable(),
      findsNothing,
      reason: 'Worker goals sit directly on the map without a side drawer.',
    );
    expect(
      tester.getSize(workerHub).height,
      lessThanOrEqualTo(48),
      reason: 'The direct task strip must leave the map visually open.',
    );

    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_worker_hub.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop map home and Worker Network hub do not expose the task workbench',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final workbench = find.byKey(
        const ValueKey<String>('resource-map-network-workbench'),
      );
      expect(workbench.hitTestable(), findsNothing);
      expect(
        find
            .byKey(
              const ValueKey<String>(
                'resource-map-network-workbench-mode-targets',
              ),
            )
            .hitTestable(),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-hub')),
        findsOneWidget,
      );
      expect(workbench.hitTestable(), findsNothing);
      expect(
        find
            .byKey(const ValueKey<String>('resource-map-mode-action-strip'))
            .hitTestable(),
        findsOneWidget,
        reason: 'Worker goals stay in the direct task strip.',
      );
      expect(
        find
            .byKey(const ValueKey<String>('resource-map-desktop-edge-surface'))
            .hitTestable(),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'planned network panel collapses left and restores its selected state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: _rerouteNetworkDataset(),
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 20,
                desiredResourceNodeCounts: const <String, int>{'x': 1},
                rootNodeIds: const <String>{'root'},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodeMaterialTargets(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-node-target-search')),
        'X Material',
      );
      await tester.pump();

      final sidebar = find.byKey(
        const ValueKey<String>('resource-map-desktop-sidebar'),
      );
      final target = find.byKey(
        const ValueKey<String>('resource-map-node-target-x'),
      );
      expect(sidebar.hitTestable(), findsOneWidget);
      expect(target.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-target-remove-x')),
        findsOneWidget,
      );
      tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .onHit(
            const BdoMapHit(kind: BdoMapHitKind.workerNode, id: 'x-shared'),
          );
      await tester.pump();
      final nodeFlyout = find.byKey(
        const ValueKey<String>('resource-map-node-quick-flyout-x-shared'),
      );
      expect(nodeFlyout, findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-desktop-sidebar-collapse'),
        ),
      );
      await tester.pump();

      expect(sidebar, findsOneWidget, reason: 'The panel stays mounted.');
      expect(sidebar.hitTestable(), findsNothing);
      expect(target, findsOneWidget, reason: 'Its selected row is preserved.');
      expect(target.hitTestable(), findsNothing);
      expect(
        nodeFlyout,
        findsNothing,
        reason: 'Full-map mode also hides an open node flyout.',
      );
      final restore = find.byKey(
        const ValueKey<String>('resource-map-desktop-task-surface-restore'),
      );
      expect(restore.hitTestable(), findsOneWidget);
      expect(find.byType(BdoMapCanvas), findsOneWidget);

      await tester.tap(restore);
      await tester.pump();

      expect(sidebar.hitTestable(), findsOneWidget);
      expect(target.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-target-remove-x')),
        findsOneWidget,
      );
      expect(
        nodeFlyout,
        findsOneWidget,
        reason: 'The selected node flyout returns with the panel state.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'planned materials use the sidebar and current-node editing uses workbench',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              lodgingDataset: lodgingDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await _openNodeMaterialTargets(tester);

      final workbench = find.byKey(
        const ValueKey<String>('resource-map-network-workbench'),
      );
      final desktopEdge = find.byKey(
        const ValueKey<String>('resource-map-desktop-edge-surface'),
      );
      expect(workbench.hitTestable(), findsNothing);
      expect(
        find
            .byKey(
              const ValueKey<String>(
                'resource-map-network-workbench-mode-targets',
              ),
            )
            .hitTestable(),
        findsNothing,
      );
      expect(desktopEdge.hitTestable(), findsOneWidget);
      expect(
        find.descendant(
          of: desktopEdge,
          matching: find.byKey(
            const ValueKey<String>('resource-map-node-planner-targets'),
          ),
        ),
        findsOneWidget,
        reason: 'Planned materials belong in the compact left workspace.',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pumpAndSettle();
      expect(workbench.hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-hub')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-worker-current-action'),
        ),
      );
      await tester.pumpAndSettle();

      expect(workbench.hitTestable(), findsOneWidget);
      expect(
        find
            .byKey(
              const ValueKey<String>(
                'resource-map-network-workbench-mode-editCurrent',
              ),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(desktopEdge.hitTestable(), findsNothing);
      expect(
        find.descendant(
          of: desktopEdge,
          matching: find.byKey(
            const ValueKey<String>(
              'resource-map-node-planner-header-editCurrent',
            ),
          ),
        ),
        findsNothing,
        reason:
            'Current-node editing uses the workbench header, not the old one.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'active plan keeps its complete route while node details open in workbench',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final routeDataset = _rerouteNetworkDataset();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: routeDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 50,
                desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodeMaterialTargets(tester);

      await tester.tap(
        find
            .byKey(const ValueKey<String>('resource-map-build-node-network'))
            .hitTestable(),
      );
      await _settleNodeNetworkCalculation(tester);

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final completeRouteKeys = canvas.nodeNetworkEdgeChanges
          .map((edge) => edge.key)
          .toSet();
      expect(
        completeRouteKeys.length,
        greaterThan(2),
        reason: 'The fixture should produce a multi-branch complete route.',
      );
      final selectedProductionNode = routeDataset.workerNodes.firstWhere(
        (node) =>
            node.isProductionNode &&
            canvas.nodeNetworkChangeKinds.containsKey(node.id),
      );

      canvas.onHit(
        BdoMapHit(
          kind: BdoMapHitKind.workerNode,
          id: selectedProductionNode.id,
        ),
      );
      await tester.pump();

      expect(
        find
            .byKey(
              const ValueKey<String>(
                'resource-map-network-workbench-node-details',
              ),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey<String>(
            'resource-map-node-quick-flyout-${selectedProductionNode.id}',
          ),
        ),
        findsNothing,
      );
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkEdgeChanges.map((edge) => edge.key).toSet(),
        completeRouteKeys,
        reason:
            'Selecting one planned node must not replace the full plan with '
            'that node\'s shorter path.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop workbench stays scrollable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1000, 700),
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await _openNodeMaterialTargets(tester);

    final plannedMaterials = find.byKey(
      const ValueKey<String>('resource-map-node-planner-targets'),
    );
    expect(plannedMaterials, findsOneWidget);
    final plannedMaterialScrollables = find.descendant(
      of: plannedMaterials,
      matching: find.byType(Scrollable),
    );
    expect(
      plannedMaterialScrollables,
      findsWidgets,
      reason: 'Large text must keep task content reachable by scrolling.',
    );
    await tester.drag(plannedMaterialScrollables.first, const Offset(0, -90));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gather opens a direct source strip over the map', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-gather')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('resource-map-gather-hub')),
      findsOneWidget,
    );
    final taskRail = find.byKey(
      const ValueKey<String>('resource-map-command-action-rail'),
    );
    expect(taskRail, findsOneWidget);
    for (final label in <String>['Gather', 'Workers']) {
      expect(
        find.descendant(of: taskRail, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('resource-map-shortcut-checklist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-shortcut-favorites')),
      findsOneWidget,
    );
    const gatheringSections = <(String, String)>[
      ('plantsWood', 'Plants & wood'),
      ('oresMinerals', 'Ores & minerals'),
      ('meat', 'Meat'),
      ('bloodHides', 'Blood & hides'),
      ('mushrooms', 'Mushrooms'),
      ('seafoodMarine', 'Coastal gathering'),
    ];
    for (final entry in gatheringSections) {
      final action = find.byKey(
        ValueKey<String>('resource-map-section-${entry.$1}'),
      );
      expect(action, findsOneWidget);
      expect(
        find.descendant(of: action, matching: find.text(entry.$2)),
        findsOneWidget,
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(
        action.hitTestable(),
        findsOneWidget,
        reason: '${entry.$2} must be reachable instead of silently clipped.',
      );
      final label = find.descendant(of: action, matching: find.text(entry.$2));
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
    }
    expect(find.text('Sea & marine'), findsNothing);
    expect(find.text('Fish & marine'), findsNothing);
    expect(find.text('Browse sources'), findsNothing);
    expect(find.textContaining('Search also understands'), findsNothing);
    expect(
      find
          .byKey(const ValueKey<String>('resource-map-desktop-edge-surface'))
          .hitTestable(),
      findsNothing,
      reason: 'Gather categories stay directly on the map without a drawer.',
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-gather-hub')),
          )
          .height,
      lessThanOrEqualTo(48),
    );

    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_gather_hub.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('node planner builds, previews, and saves a CP-aware network', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final updates = <BdoNodeNetworkPreferences>[];
    final ash = dataset.resources.singleWhere(
      (resource) => resource.name == 'Ash Timber',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
          nodeNetworkPreferences: BdoNodeNetworkPreferences(
            contributionPointBudget: 250,
          ),
          onNodeNetworkPreferencesChanged: updates.add,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    await _openNodeMaterialTargets(tester);
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-sidebar-planned-network'),
      ),
      findsOneWidget,
    );
    expect(find.text('What should your workers collect?'), findsNothing);
    expect(find.text('CP available'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-target-settings-toggle'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-node-target-settings-toggle'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('CP available'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-target-cp-update')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-node-target-settings-toggle'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final plannerCanvas = tester.widget<BdoMapCanvas>(
      find.byType(BdoMapCanvas),
    );
    expect(
      plannerCanvas.showAllNetworkConnections,
      isTrue,
      reason:
          'material targeting must retain the user\'s default-on connection '
          'layer instead of silently changing a saved display preference',
    );
    expect(
      find
          .byKey(const ValueKey<String>('resource-map-desktop-sidebar'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-planner-targets')),
      findsOneWidget,
    );
    expect(find.text('Search worker materials'), findsOneWidget);
    final targetPanelRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-node-planner-targets')),
    );
    expect(
      targetPanelRect.width,
      inInclusiveRange(400, 500),
      reason:
          'The material palette needs enough width for artwork, names, '
          'availability and count controls without becoming a broad drawer.',
    );
    for (final view in <String>['all', 'selected', 'current', 'favorites']) {
      final filter = find.byKey(
        ValueKey<String>('resource-map-node-target-view-$view'),
      );
      expect(filter, findsOneWidget);
      final rect = tester.getRect(filter);
      expect(rect.left, greaterThanOrEqualTo(targetPanelRect.left));
      expect(rect.right, lessThanOrEqualTo(targetPanelRect.right));
    }

    await tester.enterText(
      find.byKey(const ValueKey<String>('resource-map-node-target-search')),
      'Ash Timber',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey<String>('resource-map-node-target-${ash.id}')),
    );
    await tester.pump();

    expect(updates, isNotEmpty);
    expect(updates.last.desiredResourceNodeCounts[ash.id], 1);
    final ashPlus = find.byKey(
      ValueKey<String>('resource-map-node-target-plus-${ash.id}'),
    );
    final ashMinus = find.byKey(
      ValueKey<String>('resource-map-node-target-minus-${ash.id}'),
    );
    final ashRemove = find.byKey(
      ValueKey<String>('resource-map-node-target-remove-${ash.id}'),
    );
    IconButton buttonInside(Finder control) => tester.widget<IconButton>(
      find.descendant(of: control, matching: find.byType(IconButton)),
    );
    expect(buttonInside(ashMinus).onPressed, isNull);
    expect(buttonInside(ashPlus).onPressed, isNotNull);
    expect(buttonInside(ashRemove).onPressed, isNotNull);

    await tester.tap(ashPlus);
    await tester.pump();
    expect(updates.last.desiredResourceNodeCounts[ash.id], 2);
    expect(buttonInside(ashMinus).onPressed, isNotNull);

    await tester.tap(ashMinus);
    await tester.pump();
    expect(updates.last.desiredResourceNodeCounts[ash.id], 1);
    await _settleNodeTargetPreview(tester);
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-target-preview')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_planned_network.png'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-build-node-network')),
    );
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-network-calculating'),
      ),
      findsOneWidget,
    );
    await _settleNodeNetworkCalculation(tester);

    expect(find.text('Recommended complete network'), findsOneWidget);
    expect(find.textContaining('/ 250 CP'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(find.text('Use setup'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-network-workbench-leading'),
      ),
      findsNothing,
      reason:
          'The review should not reserve an empty route-context pane when no '
          'map node is selected.',
    );
    final reviewBody = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-body'),
    );
    expect(reviewBody, findsOneWidget);
    expect(
      tester.getSize(reviewBody).width,
      greaterThanOrEqualTo(700),
      reason:
          'Material names and their remove/minus/count/plus controls should '
          'own the main share of the review workbench.',
    );
    final reviewMaterial = find.byKey(
      ValueKey<String>('resource-map-review-material-${ash.id}'),
    );
    final reviewPlus = find.byKey(
      ValueKey<String>('resource-map-node-target-plus-review-${ash.id}'),
    );
    expect(reviewMaterial, findsOneWidget);
    expect(reviewPlus, findsOneWidget);
    final reviewBodyRect = tester.getRect(reviewBody);
    final reviewMaterialRect = tester.getRect(reviewMaterial);
    final reviewPlusRect = tester.getRect(reviewPlus);
    expect(reviewMaterialRect.left, greaterThanOrEqualTo(reviewBodyRect.left));
    expect(reviewMaterialRect.right, lessThanOrEqualTo(reviewBodyRect.right));
    expect(reviewPlusRect.left, greaterThanOrEqualTo(reviewMaterialRect.left));
    expect(reviewPlusRect.right, lessThanOrEqualTo(reviewMaterialRect.right));
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.nodeNetworkEdgeChanges, isNotEmpty);
    expect(
      canvas.nodeNetworkChangeKinds.values,
      contains(BdoNodeNetworkChangeKind.connect),
    );
    await _settleVisibleGoldenImages(tester, root: find.byType(BdoResourceMap));
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_node_network.png'),
    );

    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-route-visible-status'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-save-current-node-network'),
      ),
    );
    await _settleNodeNetworkCalculation(tester);
    expect(updates.last.currentNodeIds, isNotEmpty);
    expect(
      find.text(
        'Saved as your in-game network in the planner. '
        'Nothing was changed in BDO.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'planned materials show live CP shortage and current setup summary',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final routeDataset = _rerouteNetworkDataset();

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: routeDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 1,
              desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
              currentNodeIds: const <String>{'shared', 'x-shared'},
              rootNodeIds: const <String>{'root'},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodeMaterialTargets(tester);
      await _settleNodeTargetPreview(tester);

      expect(
        find.byKey(const ValueKey<String>('resource-map-node-target-preview')),
        findsOneWidget,
      );
      expect(find.textContaining('CP short'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-current-production-summary'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-node-target-settings-toggle'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-current-production-summary'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-current-production-summary'),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-target-x')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-target-y')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'node planner records the current in-game network from map clicks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final updates = <BdoNodeNetworkPreferences>[];
      final root = dataset.workerNodes.firstWhere(
        (node) =>
            node.contributionPoints == 0 &&
            (node.nodeType == 'City' || node.nodeType == 'Town'),
      );
      final node = dataset.workerNodes.firstWhere(
        (node) =>
            node.contributionPoints > 0 &&
            node.nodeType != 'City' &&
            node.nodeType != 'Town',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 250,
            ),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-worker-current-action'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-node-planner-header-editCurrent',
          ),
        ),
        findsOneWidget,
      );

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: root.id));
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.nodeNetworkChangeKinds, isNot(contains(root.id)));
      expect(find.textContaining('free worker-town root'), findsOneWidget);

      canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: node.id));
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkChangeKinds[node.id],
        BdoNodeNetworkChangeKind.retained,
      );
      expect(
        find.textContaining('1 marked · ${node.contributionPoints} CP'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-save-current-node-draft'),
        ),
      );
      await tester.pumpAndSettle();

      expect(updates.last.currentNodeIds, contains(node.id));
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-hub')),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing was changed in BDO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy setup map clicks add a production endpoint with its whole route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final updates = <BdoNodeNetworkPreferences>[];
      final paths = const BdoProductionNodePathCostService().calculateAll(
        data: dataset,
      );
      final endpoint = dataset.workerNodes.firstWhere((node) {
        final path = paths[node.id]?.minimumIncrementalPath;
        return node.isProductionNode &&
            path != null &&
            path.connectNodeIds.length > 1;
      });
      final expectedPath = paths[endpoint.id]!.minimumIncrementalPath!;

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 250,
            ),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openCurrentNodeEditor(tester);

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: endpoint.id));
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      for (final nodeId in expectedPath.connectNodeIds) {
        final node = dataset.workerNodesById[nodeId]!;
        if (!node.isNaturalWorkerRoot) {
          expect(
            canvas.nodeNetworkChangeKinds[nodeId],
            BdoNodeNetworkChangeKind.retained,
          );
        }
      }
      expect(find.textContaining('complete path'), findsWidgets);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-save-current-node-draft'),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates, isNotEmpty);
      expect(updates.last.currentNodeIds, contains(endpoint.id));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current setup search adds a staffed destination with its complete path',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final paths = const BdoProductionNodePathCostService().calculateAll(
        data: dataset,
      );
      final uniqueNames = <String, int>{};
      for (final node in dataset.workerNodes.where(
        (node) => node.isProductionNode,
      )) {
        uniqueNames.update(
          node.siteName,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final node = dataset.workerNodes.firstWhere((candidate) {
        final path = paths[candidate.id]?.minimumIncrementalPath;
        return candidate.isProductionNode &&
            uniqueNames[candidate.siteName] == 1 &&
            path != null &&
            path.connectNodeIds.length > 1;
      });
      final expectedPath = paths[node.id]!.minimumIncrementalPath!;
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-worker-current-action'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(
          const ValueKey<String>('resource-map-current-node-search-field'),
        ),
        node.siteName,
      );
      await tester.pumpAndSettle();
      final optionSurface = find.byKey(
        const ValueKey<String>('resource-map-current-node-options'),
      );
      expect(optionSurface, findsOneWidget);
      expect(tester.getSize(optionSurface).width, lessThanOrEqualTo(1176));
      final optionTitle = tester.widget<Text>(
        find.descendant(of: optionSurface, matching: find.text(node.siteName)),
      );
      expect(optionTitle.maxLines, isNull);
      expect(optionTitle.overflow, TextOverflow.visible);
      await tester.tap(find.widgetWithText(ListTile, node.siteName));
      await tester.pumpAndSettle();

      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      for (final id in expectedPath.connectNodeIds) {
        expect(
          canvas.nodeNetworkChangeKinds[id],
          BdoNodeNetworkChangeKind.retained,
        );
      }
      expect(
        find.textContaining('Added ${node.siteName} and its complete path'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-save-current-node-draft'),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates, isNotEmpty);
      expect(
        updates.last.currentNodeIds,
        containsAll(expectedPath.connectNodeIds),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current recipe recommendation fills one mapped node per shortage and '
    'solves them together',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ash = dataset.resources.singleWhere(
        (resource) => resource.name == 'Ash Timber',
      );
      final iron = dataset.resources.singleWhere(
        (resource) => resource.name == 'Iron Ore',
      );
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            plannerContextLabel: 'Alchemy · Test recipe',
            plannerNeeds: const <BdoPlannerMaterialNeed>[
              BdoPlannerMaterialNeed(
                name: 'Ash Timber',
                missingQuantity: 120,
                marketable: true,
                stockKnown: true,
                stock: 0,
                marketRegion: 'eu',
                marketFetchedAt: null,
              ),
              BdoPlannerMaterialNeed(
                name: 'Iron Ore',
                missingQuantity: 600,
                marketable: true,
                stockKnown: true,
                stock: 0,
                marketRegion: 'eu',
                marketFetchedAt: null,
              ),
            ],
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 250,
            ),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-recommend-current-recipe'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('complete network'), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('resource-map-review-material-${ash.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('resource-map-review-material-${iron.id}')),
        findsOneWidget,
      );
      expect(updates, isNotEmpty);
      expect(updates.last.desiredResourceNodeCounts, <String, int>{
        ash.id: 1,
        iron.id: 1,
      });
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.nodeNetworkChangeKinds, isNotEmpty);
      expect(
        canvas.nodeNetworkChangeKinds.values,
        contains(BdoNodeNetworkChangeKind.connect),
      );
      expect(
        canvas.nodeNetworkEdgeChanges,
        isNotEmpty,
        reason: 'Recipe plans must always draw their full connection route.',
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-network-workbench-back'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-hub')),
        findsOneWidget,
        reason:
            'Recipe review should return to the worker goals that opened it.',
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-recommend-current-recipe'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cooking and Alchemy groups select individual materials and optimize '
    'one shared route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ash = dataset.resources.singleWhere(
        (resource) => resource.name == 'Ash Timber',
      );
      final iron = dataset.resources.singleWhere(
        (resource) => resource.name == 'Iron Ore',
      );
      final ashAvailable = dataset.workerNodesForResource(ash.id).length;
      final ironAvailable = dataset.workerNodesForResource(iron.id).length;
      final updates = <BdoNodeNetworkPreferences>[];
      final groups = <BdoPlannerNeedGroup>[
        BdoPlannerNeedGroup(
          id: 'cooking',
          label: 'Cooking',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'ash-timber',
              selectedByDefault: false,
              need: const BdoPlannerMaterialNeed(
                name: 'Ash Timber',
                missingQuantity: 120,
                marketable: true,
                stockKnown: true,
                stock: 0,
                marketRegion: 'eu',
                marketFetchedAt: null,
              ),
            ),
          ],
        ),
        BdoPlannerNeedGroup(
          id: 'alchemy',
          label: 'Alchemy',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'iron-ore',
              need: const BdoPlannerMaterialNeed(
                name: 'Iron Ore',
                missingQuantity: 600,
                marketable: true,
                stockKnown: true,
                stock: 0,
                marketRegion: 'eu',
                marketFetchedAt: null,
              ),
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              plannerNeedGroups: groups,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 250,
              ),
              resourceIconBuilder: (context, resource, size) => ColoredBox(
                key: ValueKey<String>('recipe-material-artwork-${resource.id}'),
                color: const Color(0xFF67B89D),
              ),
              onNodeNetworkPreferencesChanged: updates.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);

      expect(find.text('Cooking & Alchemy'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-recommend-current-recipe'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose recipe materials'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-hub')),
        findsOneWidget,
        reason: 'Cancel returns to the direct Worker tasks, not the old panel.',
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-desktop-sidebar-hidden'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-recommend-current-recipe'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose recipe materials'), findsOneWidget);
      expect(find.text('Cooking'), findsOneWidget);
      expect(find.text('Alchemy'), findsOneWidget);
      expect(find.text('0/1 worker items'), findsOneWidget);
      expect(find.text('1/1 worker items'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-recipe-live-cp-preview'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-recipe-material-cooking-ash-timber',
          ),
        ),
        findsNothing,
        reason: 'Material rows stay hidden until their group is expanded.',
      );

      await tester.tap(find.text('Cooking'));
      await tester.pumpAndSettle();
      final ashMaterial = find.byKey(
        const ValueKey<String>(
          'resource-map-recipe-material-cooking-ash-timber',
        ),
      );
      expect(ashMaterial, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(ashMaterial).value, isFalse);
      await tester.tap(ashMaterial);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(ashMaterial).value, isTrue);
      expect(find.text('Use 2 materials'), findsOneWidget);
      expect(
        find.descendant(
          of: ashMaterial,
          matching: find.byKey(
            ValueKey<String>('recipe-material-artwork-${ash.id}'),
          ),
        ),
        findsOneWidget,
        reason: 'Recipe materials should use their exact item artwork.',
      );
      expect(ashAvailable, greaterThan(1));
      final ashCountControl = find.byKey(
        const ValueKey<String>(
          'resource-map-recipe-node-count-cooking-ash-timber',
        ),
      );
      expect(
        find.descendant(
          of: ashCountControl,
          matching: find.text('$ashAvailable'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(
                const ValueKey<String>(
                  'resource-map-recipe-node-plus-cooking-ash-timber',
                ),
              ),
            )
            .onPressed,
        isNull,
        reason: 'Plus must disable at the real reachable-node maximum.',
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-recipe-node-remove-cooking-ash-timber',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-recipe-node-minus-cooking-ash-timber',
          ),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: ashCountControl,
          matching: find.text('${ashAvailable - 1}'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Alchemy'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-recipe-material-alchemy-iron-ore',
          ),
        ),
        findsOneWidget,
      );
      final applyRecipe = find.byKey(
        const ValueKey<String>(
          'resource-map-optimize-selected-recipe-materials',
        ),
      );
      expect(tester.widget<FilledButton>(applyRecipe).onPressed, isNotNull);
      await tester.tap(applyRecipe);
      await tester.pumpAndSettle();

      expect(find.text('Choose recipe materials'), findsNothing);
      expect(find.textContaining('complete network'), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('resource-map-review-material-${ash.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('resource-map-review-material-${iron.id}')),
        findsOneWidget,
      );
      expect(updates, isNotEmpty);
      expect(updates.last.desiredResourceNodeCounts, <String, int>{
        ash.id: ashAvailable - 1,
        iron.id: ironAvailable,
      });
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.nodeNetworkEdgeChanges, isNotEmpty);
      expect(
        canvas.nodeNetworkChangeKinds.values,
        contains(BdoNodeNetworkChangeKind.connect),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recipe review adjusts exact material counts and recomputes route, '
    'workers, lodging, and saved targets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mapDataset = _rerouteNetworkDataset();
      final updates = <BdoNodeNetworkPreferences>[];
      final groups = <BdoPlannerNeedGroup>[
        BdoPlannerNeedGroup(
          id: 'cooking',
          label: 'Cooking',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'x-material',
              need: const BdoPlannerMaterialNeed(
                gameItemId: 1001,
                name: 'X Material',
                missingQuantity: 40,
                marketable: true,
                stockKnown: true,
                stock: 0,
                marketRegion: 'eu',
                marketFetchedAt: null,
              ),
            ),
          ],
        ),
        BdoPlannerNeedGroup(
          id: 'alchemy',
          label: 'Alchemy',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'y-material',
              need: const BdoPlannerMaterialNeed(
                gameItemId: 1002,
                name: 'Y Material',
                missingQuantity: 25,
                marketable: true,
                stockKnown: true,
                stock: 0,
                marketRegion: 'eu',
                marketFetchedAt: null,
              ),
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
            ),
            child: BdoResourceMap(
              dataset: mapDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              workerEconomics: _rerouteWorkerEconomics(),
              lodgingDataset: _rerouteLodgingDataset(),
              plannerNeedGroups: groups,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 20,
                desiredResourceNodeCounts: const <String, int>{'x': 2, 'y': 1},
                townWorkerCapacitiesByNodeId:
                    const <String, BdoTownWorkerCapacity>{
                      'root': BdoTownWorkerCapacity(
                        availableWorkerCount: 0,
                        freeLodgingSlotCount: 0,
                      ),
                    },
              ),
              resourceIconBuilder: (context, resource, size) => ColoredBox(
                key: ValueKey<String>('review-material-artwork-${resource.id}'),
                color: const Color(0xFF67B89D),
              ),
              onNodeNetworkPreferencesChanged: updates.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-recommend-current-recipe'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-optimize-selected-recipe-materials',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final reviewScrollable = find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('resource-map-network-workbench-scroll'),
            ),
            matching: find.byType(Scrollable),
          )
          .hitTestable()
          .first;
      final workerCapacityAction = find.byKey(
        const ValueKey<String>('resource-map-node-review-worker-capacity'),
      );
      expect(
        find.textContaining('10 / 20 CP'),
        findsOneWidget,
        reason:
            'The route total must include the 1 CP lodging house required '
            'for its three worker jobs.',
      );
      await tester.scrollUntilVisible(
        workerCapacityAction,
        120,
        scrollable: reviewScrollable,
      );
      expect(find.textContaining('Workers: 0/3 covered'), findsOneWidget);
      final xRow = find.byKey(
        const ValueKey<String>('resource-map-review-material-x'),
      );
      await tester.scrollUntilVisible(xRow, 180, scrollable: reviewScrollable);
      expect(xRow, findsOneWidget);
      expect(
        find.descendant(
          of: xRow,
          matching: find.byKey(
            const ValueKey<String>('review-material-artwork-x'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>(
                    'resource-map-node-target-plus-review-x',
                  ),
                ),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
        reason: 'Review plus must stop at the reachable two-node maximum.',
      );

      final reviewMinus = find.byKey(
        const ValueKey<String>('resource-map-node-target-minus-review-x'),
      );
      await tester.ensureVisible(reviewMinus);
      await tester.pumpAndSettle();
      await tester.tap(reviewMinus.hitTestable());
      await _settleNodeNetworkCalculation(tester);

      expect(updates.last.desiredResourceNodeCounts, const <String, int>{
        'x': 1,
        'y': 1,
      });
      await tester.drag(reviewScrollable, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('6 / 20 CP'),
        findsOneWidget,
        reason: 'Recomputed totals must continue to include lodging CP.',
      );
      await tester.scrollUntilVisible(
        workerCapacityAction,
        120,
        scrollable: reviewScrollable,
      );
      expect(find.textContaining('Workers: 0/2 covered'), findsOneWidget);
      expect(xRow, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-review-material-y')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(xRow, 180, scrollable: reviewScrollable);
      final reviewRemove = find.byKey(
        const ValueKey<String>('resource-map-node-target-remove-review-x'),
      );
      await tester.ensureVisible(reviewRemove);
      await tester.pumpAndSettle();
      await tester.tap(reviewRemove.hitTestable());
      await _settleNodeNetworkCalculation(tester);

      expect(updates.last.desiredResourceNodeCounts, const <String, int>{
        'y': 1,
      });
      await tester.drag(reviewScrollable, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('3 / 20 CP', skipOffstage: false),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        workerCapacityAction,
        120,
        scrollable: reviewScrollable,
      );
      expect(
        find.textContaining('Workers: 0/1 covered', skipOffstage: false),
        findsOneWidget,
      );
      expect(xRow, findsNothing);
      expect(
        find.textContaining('1 production node', skipOffstage: false),
        findsWidgets,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-network-workbench-back'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-recommend-current-recipe'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cooking'));
      await tester.pumpAndSettle();
      final reopenedX = find.byKey(
        const ValueKey<String>(
          'resource-map-recipe-material-cooking-x-material',
        ),
      );
      expect(reopenedX, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(reopenedX).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'income route uses mapped base lodging and exposes exact new house path',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
            ),
            child: BdoResourceMap(
              dataset: _rerouteNetworkDataset(),
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              workerEconomics: _rerouteWorkerEconomics(),
              lodgingDataset: _rerouteChainedLodgingDataset(),
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 20,
                rootNodeIds: <String>{'root'},
                onlineHoursPerDay: 8,
                resourceAvailabilityPercent: 100,
              ),
              marketOutputEvidenceByResourceId:
                  const <String, MarketValueOutputInput>{
                    'x': MarketValueOutputInput(
                      outputId: 'x',
                      outputName: 'X Material',
                      isMarketable: true,
                      currentUnitPrice: 100,
                      listedStock: 0,
                    ),
                    'y': MarketValueOutputInput(
                      outputId: 'y',
                      outputName: 'Y Material',
                      isMarketable: true,
                      currentUnitPrice: 90,
                      listedStock: 0,
                    ),
                  },
              marketNetRate: 0.845,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('14 of 20'),
        findsOneWidget,
        reason:
            'The displayed total must be the 11 CP node route plus the exact '
            '3 CP prerequisite-and-lodging house closure.',
      );
      expect(find.text('2 houses'), findsWidgets);
      final badge = find.byKey(
        const ValueKey<String>('resource-map-lodging-town-badge-root'),
      );
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('2')),
        findsOneWidget,
        reason: 'The round town badge counts both houses the route must buy.',
      );

      await tester.tap(badge);
      await tester.pumpAndSettle();

      final summary = find.byKey(
        const ValueKey<String>('resource-map-planned-lodging-summary-root'),
      );
      expect(summary, findsOneWidget);
      expect(find.text('Root lodging'), findsOneWidget);
      expect(find.text('2 to buy'), findsOneWidget);
      expect(find.text('+4 beds'), findsOneWidget);
      expect(find.text('+3 CP'), findsOneWidget);
      expect(find.text('BUY FOR LODGING (1)'), findsOneWidget);
      expect(find.text('BUY FIRST (1)'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-planned-lodging-house-house:9000',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-planned-lodging-house-house:9001',
          ),
        ),
        findsOneWidget,
      );

      final cameraController = tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .cameraController;
      final cameraBeforeHouseSelection = cameraController.camera;
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-planned-lodging-house-house:9001',
          ),
        ),
      );
      await tester.pump();
      expect(cameraController.camera, cameraBeforeHouseSelection);
      final selectedHousePulse = find.byKey(
        const ValueKey<String>('resource-map-house-selection-pulse-house:9001'),
      );
      expect(
        selectedHousePulse,
        findsOneWidget,
        reason:
            'Selecting a house in the lodging summary should reveal the '
            'matching map marker without moving the map.',
      );
      expect(
        find.descendant(
          of: selectedHousePulse,
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
        reason: 'Reduced-motion mode should retain the static selected state.',
      );

      final housingPainter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CustomPainter>()
          .singleWhere(
            (painter) => painter.runtimeType.toString().contains(
              'HousePrerequisitePainter',
            ),
          );
      // ignore: avoid_dynamic_calls
      final graph = Map<String, Object>.from(
        // ignore: avoid_dynamic_calls
        (housingPainter as dynamic).debugVisualGraph as Map,
      );
      expect(
        graph['recommendedNewHouseIds'],
        containsAll(<String>{'house:9000', 'house:9001'}),
        reason:
            'The on-map house layer must retain the exact prerequisite and '
            'lodging closure even when nearby houses are decluttered into one '
            'visual marker.',
      );

      final beforeDrag = tester.getTopLeft(summary);
      await tester.drag(
        find.byKey(
          const ValueKey<String>(
            'resource-map-planned-lodging-summary-handle-root',
          ),
        ),
        const Offset(55, 30),
      );
      await tester.pump();
      expect(tester.getTopLeft(summary), isNot(beforeDrag));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker economics shows after-tax online income and complete route tools',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final marketDataset = _rerouteNetworkDataset();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
            ),
            child: BdoResourceMap(
              dataset: marketDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              workerEconomics: _rerouteWorkerEconomics(),
              lodgingDataset: _rerouteLodgingDataset(),
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 20,
                onlineHoursPerDay: 8,
                resourceAvailabilityPercent: 100,
                townWorkerCapacitiesByNodeId:
                    const <String, BdoTownWorkerCapacity>{
                      'root': BdoTownWorkerCapacity(
                        availableWorkerCount: 0,
                        freeLodgingSlotCount: 0,
                      ),
                    },
              ),
              marketOutputEvidenceByResourceId:
                  const <String, MarketValueOutputInput>{
                    'x': MarketValueOutputInput(
                      outputId: 'x',
                      outputName: 'X Material',
                      isMarketable: true,
                      currentUnitPrice: 100,
                      listedStock: 0,
                    ),
                    'y': MarketValueOutputInput(
                      outputId: 'y',
                      outputName: 'Y Material',
                      isMarketable: true,
                      currentUnitPrice: 90,
                      listedStock: 1000,
                    ),
                  },
              marketNetRate: 0.845,
              marketRegion: 'eu',
              marketFetchedAt: DateTime.utc(2026, 7, 29, 12),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      final openIncome = find.byKey(
        const ValueKey<String>(
          'resource-map-open-market-value-recommendations',
        ),
      );
      await tester.ensureVisible(openIncome);
      await tester.pumpAndSettle();
      await tester.tap(openIncome);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>(
              'resource-map-node-planner-header-marketValue',
            ),
          ),
          matching: find.text('Best worker income'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('market tax'), findsOneWidget);
      final incomeSummary = tester.widget<Text>(find.textContaining('/ hour'));
      expect(incomeSummary.data, isNot(startsWith('0 silver / hour')));
      expect(find.textContaining('online hours'), findsOneWidget);
      expect(find.textContaining('in one week'), findsOneWidget);
      expect(find.text('Recommended route'), findsOneWidget);
      expect(
        find.textContaining('Your workers pause when you log out'),
        findsOneWidget,
      );
      expect(find.text('Show route on map'), findsOneWidget);
      expect(find.text('Save as my setup'), findsOneWidget);
      expect(find.text('Tell us what you already own'), findsOneWidget);
      expect(find.textContaining('connection line'), findsNothing);
      final incomeSurface = find.byKey(
        const ValueKey<String>('resource-map-network-workbench'),
      );
      expect(incomeSurface, findsOneWidget);
      final incomeSurfaceRect = tester.getRect(incomeSurface);
      expect(
        tester.getSize(incomeSurface).width,
        inInclusiveRange(480, 680),
        reason:
            'A compact income summary should stay anchored over the map, not '
            'stretch across nearly the entire desktop window.',
      );
      expect(tester.getRect(incomeSurface).top, greaterThan(400));
      expect(tester.getRect(incomeSurface).bottom, lessThanOrEqualTo(900));
      expect(
        tester.getSize(incomeSurface).height,
        lessThan(400),
        reason:
            'The income result should stay in a finite bottom workbench '
            'instead of becoming a full-height sheet.',
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-network-workbench-mode-marketValue',
          ),
        ),
        findsOneWidget,
        reason:
            'Worker-income results should use the dedicated market-value '
            'workbench mode.',
      );
      expect(
        find.descendant(of: incomeSurface, matching: find.byType(Card)),
        findsNothing,
        reason: 'The result should not regress to an elevated card.',
      );
      final canvasBeforeCollapse = tester.widget<BdoMapCanvas>(
        find.byType(BdoMapCanvas),
      );
      final routeLinesBeforeCollapse =
          canvasBeforeCollapse.nodeNetworkEdgeChanges.length;
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-network-workbench-collapse'),
        ),
      );
      await tester.pump();
      expect(incomeSurface, findsOneWidget);
      expect(incomeSurface.hitTestable(), findsNothing);
      final restorePanel = find.byKey(
        const ValueKey<String>('resource-map-desktop-task-surface-restore'),
      );
      expect(restorePanel.hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
            .nodeNetworkEdgeChanges,
        hasLength(routeLinesBeforeCollapse),
        reason: 'Hiding the UI must not change the planned network on-map.',
      );
      await tester.tap(restorePanel);
      await tester.pump();
      expect(incomeSurface.hitTestable(), findsOneWidget);
      expect(tester.getRect(incomeSurface), incomeSurfaceRect);
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_worker_income.png'),
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-income-lodging-town-root'),
        ),
        findsNothing,
        reason: 'Exact lodging details should stay folded until requested.',
      );
      final lodgingDetailsButton = find.byKey(
        const ValueKey<String>('resource-map-toggle-worker-lodging-details'),
      );
      await tester.ensureVisible(lodgingDetailsButton);
      await tester.pumpAndSettle();
      await tester.tap(lodgingDetailsButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-income-lodging-town-root'),
        ),
        findsOneWidget,
        reason:
            'The existing exact lodging town and house path remains available '
            'through progressive disclosure.',
      );
      await tester.ensureVisible(lodgingDetailsButton);
      await tester.tap(lodgingDetailsButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-worker-income-settings'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-worker-capacity-settings'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('not silver per hour'), findsNothing);

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkEdgeChanges,
        isNotEmpty,
        reason: 'The recommended income plan must paint its connection lines.',
      );
      expect(
        canvas.nodeNetworkChangeKinds.values,
        contains(BdoNodeNetworkChangeKind.connect),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-worker-income-settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Adjust the estimate'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                const ValueKey<String>('resource-map-online-hours-input'),
              ),
            )
            .controller!
            .text,
        '8',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                const ValueKey<String>('resource-map-availability-input'),
              ),
            )
            .controller!
            .text,
        '100',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final workerCapacityButton = find.byKey(
        const ValueKey<String>('resource-map-worker-capacity-settings'),
      );
      await tester.ensureVisible(workerCapacityButton);
      await tester.pumpAndSettle();
      await tester.tap(workerCapacityButton);
      await tester.pumpAndSettle();
      expect(find.text('Your workers by town'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-town-add')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-worker-town-add-action'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('bonus lodging'), findsWidgets);
      expect(find.text('Hired workers'), findsOneWidget);
      expect(find.text('Bonus lodging slots'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.nodeNetworkEdgeChanges, isNotEmpty);
      expect(find.textContaining('not silver per hour'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden Royal Workshop state does not reserve CP or change income',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
            ),
            child: BdoResourceMap(
              dataset: _rerouteNetworkDataset(),
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              workerEconomics: _rerouteWorkerEconomics(),
              lodgingDataset: _rerouteLodgingDataset(),
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 5,
                rootNodeIds: const <String>{'root'},
                onlineHoursPerDay: 8,
                royalWorkshopPlan: BdoRoyalWorkshopPlan(
                  accessInvested: true,
                  areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
                    'infirmary': BdoRoyalWorkshopAreaPlan(
                      workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
                        0: BdoRoyalWorkshopSlotPlan(
                          recordedGoodName: 'Current ordinary roll',
                          workerName: 'Worker A',
                          taskHours: 1,
                          netSilverPerCycle: 100000000,
                          isRunning: true,
                        ),
                      },
                    ),
                  },
                ),
              ),
              marketOutputEvidenceByResourceId:
                  const <String, MarketValueOutputInput>{
                    'x': MarketValueOutputInput(
                      outputId: 'x',
                      outputName: 'X Material',
                      isMarketable: true,
                      currentUnitPrice: 100,
                      listedStock: 0,
                    ),
                    'y': MarketValueOutputInput(
                      outputId: 'y',
                      outputName: 'Y Material',
                      isMarketable: true,
                      currentUnitPrice: 90,
                      listedStock: 0,
                    ),
                  },
              marketNetRate: 0.845,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final total = tester.widget<Text>(
        find.byKey(
          const ValueKey<String>('resource-map-worker-income-total-hourly'),
        ),
      );
      expect(total.data, isNot('100.00m / hour'));
      expect(find.textContaining('Royal Workshop'), findsNothing);
      expect(
        tester
            .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
            .nodeNetworkEdgeChanges,
        isNotEmpty,
        reason:
            'Hidden Royal Workshop preferences must not reserve CP or alter '
            'the ordinary worker-node route.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving income settings closes, paints progress, and yields to UI work',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final marketDataset = _rerouteNetworkDataset();
      final preferenceUpdates = <BdoNodeNetworkPreferences>[];
      final heartbeat = ValueNotifier<int>(0);
      final navigatorObserver = _PopCountingNavigatorObserver();
      addTearDown(heartbeat.dispose);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: <NavigatorObserver>[navigatorObserver],
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                BdoResourceMap(
                  dataset: marketDataset,
                  cacheDirectory: cacheDirectory,
                  tileSource: tileSource,
                  showSourceNotice: false,
                  tileHttpClient: tileClient,
                  workerEconomics: _rerouteWorkerEconomics(),
                  lodgingDataset: _rerouteLodgingDataset(),
                  nodeNetworkPreferences: BdoNodeNetworkPreferences(
                    contributionPointBudget: 20,
                    rootNodeIds: const <String>{'root'},
                    townWorkerCapacitiesByNodeId:
                        const <String, BdoTownWorkerCapacity>{
                          'root': BdoTownWorkerCapacity(
                            availableWorkerCount: 0,
                            freeLodgingSlotCount: 0,
                          ),
                        },
                  ),
                  onNodeNetworkPreferencesChanged: preferenceUpdates.add,
                  marketOutputEvidenceByResourceId:
                      const <String, MarketValueOutputInput>{
                        'x': MarketValueOutputInput(
                          outputId: 'x',
                          outputName: 'X Material',
                          isMarketable: true,
                          currentUnitPrice: 100,
                          listedStock: 0,
                        ),
                        'y': MarketValueOutputInput(
                          outputId: 'y',
                          outputName: 'Y Material',
                          isMarketable: true,
                          currentUnitPrice: 90,
                          listedStock: 1000,
                        ),
                      },
                  marketNetRate: 0.845,
                  marketRegion: 'eu',
                  marketFetchedAt: DateTime.utc(2026, 7, 29, 12),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: IgnorePointer(
                    child: ValueListenableBuilder<int>(
                      valueListenable: heartbeat,
                      builder: (context, value, child) => Text(
                        'UI heartbeat $value',
                        key: const ValueKey<String>(
                          'resource-map-test-ui-heartbeat',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final settings = find.byKey(
        const ValueKey<String>('resource-map-worker-income-settings'),
      );
      await tester.tap(settings);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      final onlineHours = find.byKey(
        const ValueKey<String>('resource-map-online-hours-input'),
      );
      final availability = find.byKey(
        const ValueKey<String>('resource-map-availability-input'),
      );
      final partialPrices = find.descendant(
        of: dialog,
        matching: find.widgetWithText(
          SwitchListTile,
          'Keep incomplete market results',
        ),
      );
      expect(tester.widget<TextField>(onlineHours).controller!.text, '8');
      expect(tester.widget<TextField>(availability).controller!.text, '100');
      expect(tester.widget<SwitchListTile>(partialPrices).value, isFalse);

      // Leave every persisted income preference untouched. The partial-price
      // switch is local to this page and must independently trigger a refresh.
      await tester.tap(partialPrices);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(partialPrices).value, isTrue);
      expect(preferenceUpdates, isEmpty);

      final apply = find.byKey(
        const ValueKey<String>('resource-map-save-income-settings'),
      );
      final popCountBeforeApply = navigatorObserver.popCount;
      await tester.tap(apply);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        heartbeat.value += 1;
      });
      await tester.pump();

      final progress = find.byKey(
        const ValueKey<String>('resource-map-worker-income-calculating'),
      );
      expect(progress, findsOneWidget);
      final liveRegion = tester.widget<Semantics>(progress);
      expect(liveRegion.properties.liveRegion, isTrue);
      expect(
        liveRegion.properties.label,
        'Updating worker income recommendation',
      );
      expect(
        find.descendant(
          of: progress,
          matching: find.byType(LinearProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(navigatorObserver.popCount, popCountBeforeApply + 1);
      expect(heartbeat.value, 1);

      // Rebuild the scheduled heartbeat without advancing zero-delay planner
      // timers. It must render while the recommendation is still in progress.
      await tester.pump();
      expect(find.text('UI heartbeat 1'), findsOneWidget);
      expect(progress, findsOneWidget);
      expect(preferenceUpdates, isEmpty);

      await tester.pumpAndSettle();
      expect(find.text('Adjust the estimate'), findsNothing);
      expect(progress, findsNothing);

      final workerCapacity = find.byKey(
        const ValueKey<String>('resource-map-worker-capacity-settings'),
      );
      await tester.ensureVisible(workerCapacity);
      await tester.tap(workerCapacity);
      await tester.pumpAndSettle();

      expect(find.text('Your workers by town'), findsOneWidget);
      expect(find.text('Hired workers'), findsOneWidget);
      expect(find.text('Bonus lodging slots'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-hired-workers-root')),
        '4',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-bonus-lodging-root')),
        '8',
      );
      await tester.pump();
      expect(find.textContaining('9 known slots'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      final savedCapacity =
          preferenceUpdates.last.townWorkerCapacitiesByNodeId['root']!;
      expect(savedCapacity.hiredWorkerCount, 4);
      expect(savedCapacity.bonusLodgingSlotCount, 8);
      expect(savedCapacity.availableWorkerCount, 4);
      expect(savedCapacity.freeLodgingSlotCount, 5);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker income result stays readable and actionable at 200 percent text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: BdoResourceMap(
              dataset: _rerouteNetworkDataset(),
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              workerEconomics: _rerouteWorkerEconomics(),
              lodgingDataset: _rerouteLodgingDataset(),
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 20,
                onlineHoursPerDay: 8,
                resourceAvailabilityPercent: 100,
                townWorkerCapacitiesByNodeId:
                    const <String, BdoTownWorkerCapacity>{
                      'root': BdoTownWorkerCapacity(
                        availableWorkerCount: 0,
                        freeLodgingSlotCount: 0,
                      ),
                    },
              ),
              marketOutputEvidenceByResourceId:
                  const <String, MarketValueOutputInput>{
                    'x': MarketValueOutputInput(
                      outputId: 'x',
                      outputName: 'X Material',
                      isMarketable: true,
                      currentUnitPrice: 100,
                      listedStock: 0,
                    ),
                    'y': MarketValueOutputInput(
                      outputId: 'y',
                      outputName: 'Y Material',
                      isMarketable: true,
                      currentUnitPrice: 90,
                      listedStock: 1000,
                    ),
                  },
              marketNetRate: 0.845,
              marketRegion: 'eu',
              marketFetchedAt: DateTime.utc(2026, 7, 29, 12),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      final openIncome = find.byKey(
        const ValueKey<String>(
          'resource-map-open-market-value-recommendations',
        ),
      );
      await tester.ensureVisible(openIncome);
      await tester.pumpAndSettle();
      await tester.tap(openIncome);
      await tester.pumpAndSettle();

      final surface = find.byKey(
        const ValueKey<String>('resource-map-network-workbench'),
      );
      expect(surface, findsOneWidget);
      expect(tester.getRect(surface).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(surface).bottom, lessThanOrEqualTo(900));
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>(
              'resource-map-node-planner-header-marketValue',
            ),
          ),
          matching: find.text('Best worker income'),
        ),
        findsOneWidget,
      );
      expect(find.text('CP available'), findsOneWidget);
      expect(find.text('Recommended route'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);

      final update = find.byKey(
        const ValueKey<String>('resource-map-market-value-apply-cp'),
      );
      final adjust = find.descendant(
        of: find.byKey(
          const ValueKey<String>(
            'resource-map-node-planner-header-marketValue',
          ),
        ),
        matching: find.byKey(
          const ValueKey<String>('resource-map-worker-income-settings'),
        ),
      );
      final owned = find.byKey(
        const ValueKey<String>('resource-map-worker-capacity-settings'),
      );
      expect(update, findsOneWidget);
      expect(adjust, findsOneWidget);
      expect(owned, findsOneWidget);
      expect(tester.getSemantics(update).label, contains('Update'));
      expect(
        tester.widget<IconButton>(adjust).tooltip,
        'Adjust income estimate',
      );
      expect(
        tester.getSemantics(owned).label,
        contains('Tell us what you already own'),
      );

      final detailsToggle = find.byKey(
        const ValueKey<String>('resource-map-toggle-market-node-details'),
      );
      await tester.ensureVisible(detailsToggle);
      await tester.tap(detailsToggle);
      await tester.pumpAndSettle();
      final ranking = find.byKey(
        const ValueKey<String>('resource-map-market-value-ranking-basis'),
      );
      await tester.ensureVisible(ranking);
      final rankingWidget = tester.widget<PopupMenuButton>(ranking);
      expect(rankingWidget.position, PopupMenuPosition.under);
      expect(
        rankingWidget.constraints!.maxWidth,
        greaterThan(380),
        reason: 'The 200% menu width must be measured from its full labels.',
      );
      final rankingLabel = tester.widget<Text>(
        find.descendant(
          of: ranking,
          matching: find.text('Ranking: Net silver / added CP-hour'),
        ),
      );
      expect(rankingLabel.maxLines, isNull);
      expect(rankingLabel.overflow, isNot(TextOverflow.ellipsis));

      await tester.tap(ranking);
      await tester.pumpAndSettle();
      final longestRankingOption = find.text('Most silver per online hour');
      expect(longestRankingOption, findsOneWidget);
      final optionRect = tester.getRect(longestRankingOption);
      expect(optionRect.left, greaterThanOrEqualTo(0));
      expect(optionRect.right, lessThanOrEqualTo(1200));
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.ensureVisible(owned);
      await tester.tap(owned);
      await tester.pumpAndSettle();
      final townSelector = find.byKey(
        const ValueKey<String>('resource-map-worker-town-add'),
      );
      final addTown = find.byKey(
        const ValueKey<String>('resource-map-worker-town-add-action'),
      );
      expect(townSelector, findsOneWidget);
      expect(addTown, findsOneWidget);
      final townDropdown = tester.widget<DropdownButton<String>>(townSelector);
      expect(townDropdown.menuWidth, isNotNull);
      expect(townDropdown.menuWidth!, greaterThan(240));
      expect(townDropdown.menuWidth!, lessThanOrEqualTo(1176));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'market recommendations rank exact paths and optionally penalize stock',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final marketDataset = _rerouteNetworkDataset();
      final preferenceUpdates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: marketDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 20,
              rootNodeIds: const <String>{'root'},
            ),
            onNodeNetworkPreferencesChanged: preferenceUpdates.add,
            marketOutputEvidenceByResourceId:
                const <String, MarketValueOutputInput>{
                  'x': MarketValueOutputInput(
                    outputId: 'x',
                    outputName: 'X Material',
                    isMarketable: true,
                    currentUnitPrice: 100,
                    listedStock: 0,
                  ),
                  'y': MarketValueOutputInput(
                    outputId: 'y',
                    outputName: 'Y Material',
                    isMarketable: true,
                    currentUnitPrice: 90,
                    listedStock: 100000,
                  ),
                },
            marketNetRate: 1,
            marketRegion: 'eu',
            marketFetchedAt: DateTime.utc(2026, 7, 29, 12),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('resource-map-add-recommended-value-network'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                const ValueKey<String>('resource-map-market-value-cp-budget'),
              ),
            )
            .controller!
            .text,
        '20',
      );
      expect(find.textContaining('not silver per hour'), findsWidgets);
      expect(find.text('Recommended value network'), findsOneWidget);
      expect(
        find.textContaining('11 of 20 CP · 0 already invested · +11 new'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_market_value.png'),
      );
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkEdgeChanges,
        hasLength(5),
        reason: 'The primary result should paint the complete union network.',
      );
      expect(
        canvas.workerNodes.map((node) => node.id),
        containsAll(<String>[
          'root',
          'shared',
          'x-shared',
          'y-shared',
          'x-direct',
          'y-direct',
        ]),
      );
      expect(find.textContaining('Route shown'), findsNothing);

      final detailsToggle = find.byKey(
        const ValueKey<String>('resource-map-toggle-market-node-details'),
      );
      await tester.ensureVisible(detailsToggle);
      await tester.pumpAndSettle();
      await tester.tap(detailsToggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-ranking-basis'),
        ),
        findsOneWidget,
      );
      expect(find.text('Value / added CP'), findsOneWidget);
      final yDirect = find.byKey(
        const ValueKey<String>('resource-map-market-value-node-y-direct'),
      );
      expect(yDirect, findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-ranking-basis'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-basis-total-cp'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Value / total CP'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-ranking-basis'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-basis-added-cp'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Value / added CP'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-ranking-basis'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-stock-toggle'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recommended value network'), findsOneWidget);

      final xShared = find.byKey(
        const ValueKey<String>('resource-map-market-value-node-x-shared'),
      );
      await tester.scrollUntilVisible(
        xShared,
        80,
        scrollable: find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-market-value-results'),
          ),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(xShared);
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.nodeNetworkEdgeChanges, hasLength(5));
      expect(
        canvas.nodeNetworkEdgeChanges.map((edge) => edge.key),
        containsAll(<String>[
          'root\u0000shared',
          'shared\u0000x-shared',
          'shared\u0000y-shared',
          'root\u0000x-direct',
          'root\u0000y-direct',
        ]),
        reason:
            'Inspecting one ranked node must not replace the complete '
            'recommended network drawn on the map.',
      );
      expect(
        canvas.nodeNetworkChangeKinds['x-shared'],
        BdoNodeNetworkChangeKind.connect,
      );
      expect(
        canvas.workerNodes.map((node) => node.id),
        containsAll(<String>['root', 'shared', 'x-shared']),
      );

      final budgetField = find.byKey(
        const ValueKey<String>('resource-map-market-value-cp-budget'),
      );
      await tester.ensureVisible(budgetField);
      await tester.enterText(budgetField, '2');
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-market-value-apply-cp'),
        ),
      );
      await tester.pumpAndSettle();
      expect(preferenceUpdates.last.contributionPointBudget, 2);
      expect(yDirect, findsOneWidget);
      expect(
        find.textContaining('3 routes need more than 2 free CP'),
        findsOneWidget,
      );
      expect(find.textContaining('1 ranked'), findsOneWidget);
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkChangeKinds['y-direct'],
        BdoNodeNetworkChangeKind.connect,
      );
      expect(canvas.nodeNetworkEdgeChanges, hasLength(1));
      expect(find.textContaining('Available worker nodes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recommended raw-sale network adds its union without replacing saved nodes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: _rerouteNetworkDataset(),
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 8,
              currentNodeIds: const <String>{'x-direct'},
              rootNodeIds: const <String>{'root'},
            ),
            onNodeNetworkPreferencesChanged: updates.add,
            marketOutputEvidenceByResourceId:
                const <String, MarketValueOutputInput>{
                  'x': MarketValueOutputInput(
                    outputId: 'x',
                    outputName: 'X Material',
                    isMarketable: true,
                    currentUnitPrice: 100,
                    listedStock: 0,
                  ),
                  'y': MarketValueOutputInput(
                    outputId: 'y',
                    outputName: 'Y Material',
                    isMarketable: true,
                    currentUnitPrice: 90,
                    listedStock: 0,
                  ),
                },
            marketNetRate: 1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recommended value network'), findsOneWidget);
      final useRecommendedNetwork = find.byKey(
        const ValueKey<String>('resource-map-add-recommended-value-network'),
      );
      await tester.ensureVisible(useRecommendedNetwork);
      await tester.pumpAndSettle();
      await tester.tap(useRecommendedNetwork);
      await tester.pumpAndSettle();

      expect(updates, isNotEmpty);
      expect(updates.last.currentNodeIds, contains('x-direct'));
      expect(updates.last.currentNodeIds.length, greaterThan(1));
      expect(
        updates.last.currentNodeIds,
        isNot(contains('root')),
        reason: 'Free worker-town roots are not invested nodes.',
      );
      expect(find.textContaining('Nothing was changed in BDO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'price-only market recommendations stay usable at 200 percent text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1200, 900),
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: BdoResourceMap(
              dataset: _rerouteNetworkDataset(),
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                contributionPointBudget: 20,
                rootNodeIds: const <String>{'root'},
              ),
              marketOutputEvidenceByResourceId:
                  const <String, MarketValueOutputInput>{
                    'x': MarketValueOutputInput(
                      outputId: 'x',
                      outputName: 'X Material',
                      isMarketable: true,
                      currentUnitPrice: 100,
                      listedStock: 0,
                    ),
                    'y': MarketValueOutputInput(
                      outputId: 'y',
                      outputName: 'Y Material',
                      isMarketable: true,
                      currentUnitPrice: 90,
                      listedStock: 100000,
                    ),
                  },
              marketNetRate: 1,
              marketRegion: 'eu',
              marketFetchedAt: DateTime.utc(2026, 7, 29, 12),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _openNodePlanner(tester);

      final openRecommendations = find.byKey(
        const ValueKey<String>(
          'resource-map-open-market-value-recommendations',
        ),
      );
      await tester.ensureVisible(openRecommendations);
      await tester.pumpAndSettle();
      await tester.tap(openRecommendations);
      await tester.pumpAndSettle();

      final page = find.byKey(
        const ValueKey<String>('resource-map-market-value-page'),
      );
      expect(page, findsOneWidget);
      expect(find.text('Recommended value network'), findsOneWidget);
      final explicitFontSizes = tester
          .widgetList<Text>(
            find.descendant(of: page, matching: find.byType(Text)),
          )
          .map((text) => text.style?.fontSize)
          .whereType<double>()
          .toList(growable: false);
      expect(explicitFontSizes, isNotEmpty);
      expect(
        explicitFontSizes.every((fontSize) => fontSize >= 11.5),
        isTrue,
        reason:
            'The Atlas market page should not fall back to legacy microtype.',
      );

      final detailsToggle = find.byKey(
        const ValueKey<String>('resource-map-toggle-market-node-details'),
      );
      await tester.ensureVisible(detailsToggle);
      await tester.pumpAndSettle();
      await tester.tap(detailsToggle);
      await tester.pumpAndSettle();

      final finalNode = find.byKey(
        const ValueKey<String>('resource-map-market-value-node-y-direct'),
      );
      expect(finalNode, findsOneWidget);
      await tester.ensureVisible(finalNode);
      await tester.pumpAndSettle();
      final finalNodeRect = tester.getRect(finalNode);
      expect(finalNodeRect.top, greaterThanOrEqualTo(0));
      expect(finalNodeRect.bottom, lessThanOrEqualTo(900));

      await tester.tap(finalNode);
      await tester.pumpAndSettle();
      expect(find.textContaining('Route shown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing targets re-solves the whole network instead of retaining a '
    'former shared route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final rerouteDataset = _rerouteNetworkDataset();

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: rerouteDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 20,
              desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
              rootNodeIds: const <String>{'root'},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await _openNodeMaterialTargets(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-build-node-network')),
      );
      await _settleNodeNetworkCalculation(tester);
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkChangeKinds,
        containsPair('x-shared', BdoNodeNetworkChangeKind.connect),
      );
      expect(
        canvas.nodeNetworkChangeKinds,
        containsPair('y-shared', BdoNodeNetworkChangeKind.connect),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-save-current-node-network'),
        ),
      );
      await _settleNodeNetworkCalculation(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-node-planner-back-targets'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _settleNodeTargetPreview(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-node-target-search')),
        'X Material',
      );
      await tester.pump();
      final xTarget = find.byKey(
        const ValueKey<String>('resource-map-node-target-x'),
      );
      expect(tester.widget<InkWell>(xTarget).onTap, isNull);
      final removeX = find.descendant(
        of: find.byKey(
          const ValueKey<String>('resource-map-node-target-remove-x'),
        ),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(removeX).onPressed!.call();
      await tester.pump();
      await _settleNodeTargetPreview(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-build-node-network')),
      );
      await _settleNodeNetworkCalculation(tester);
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.nodeNetworkChangeKinds,
        containsPair('y-direct', BdoNodeNetworkChangeKind.connect),
      );
      for (final nodeId in <String>['shared', 'x-shared', 'y-shared']) {
        expect(
          canvas.nodeNetworkChangeKinds,
          containsPair(nodeId, BdoNodeNetworkChangeKind.disconnect),
        );
      }
      expect(find.textContaining('2 / 20 CP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected worker material has separate remove minus and capped plus',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final targetDataset = _rerouteNetworkDataset();
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: targetDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              desiredResourceNodeCounts: const <String, int>{'x': 1},
              rootNodeIds: const <String>{'root'},
            ),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await _openNodeMaterialTargets(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-node-target-search')),
        'X Material',
      );
      await tester.pump();

      final row = find.byKey(
        const ValueKey<String>('resource-map-node-target-x'),
      );
      final removeControl = find.byKey(
        const ValueKey<String>('resource-map-node-target-remove-x'),
      );
      final minusControl = find.byKey(
        const ValueKey<String>('resource-map-node-target-minus-x'),
      );
      final plusControl = find.byKey(
        const ValueKey<String>('resource-map-node-target-plus-x'),
      );
      IconButton buttonInside(Finder control) => tester.widget<IconButton>(
        find.descendant(of: control, matching: find.byType(IconButton)),
      );

      expect(
        tester.getSize(row).height,
        greaterThanOrEqualTo(56),
        reason: 'Planned materials must not regress to a tiny list row.',
      );
      final buildRoute = find.byKey(
        const ValueKey<String>('resource-map-build-node-network'),
      );
      final allView = find.byKey(
        const ValueKey<String>('resource-map-node-target-view-all'),
      );
      expect(
        tester.getRect(buildRoute).bottom,
        lessThan(tester.getRect(allView).top),
      );
      expect(tester.widget<InkWell>(row).onTap, isNull);
      expect(buttonInside(removeControl).onPressed, isNotNull);
      expect(buttonInside(minusControl).onPressed, isNull);
      expect(buttonInside(plusControl).onPressed, isNotNull);

      buttonInside(plusControl).onPressed!.call();
      await tester.pump();
      expect(updates.last.desiredResourceNodeCounts, const <String, int>{
        'x': 2,
      });
      expect(buttonInside(minusControl).onPressed, isNotNull);
      expect(buttonInside(plusControl).onPressed, isNull);

      await tester.pump();
      expect(
        updates.last.desiredResourceNodeCounts,
        const <String, int>{'x': 2},
        reason: 'Plus is a no-op at the two reachable-node maximum.',
      );

      buttonInside(minusControl).onPressed!.call();
      await tester.pump();
      expect(updates.last.desiredResourceNodeCounts, const <String, int>{
        'x': 1,
      });

      buttonInside(removeControl).onPressed!.call();
      await tester.pump();
      expect(updates.last.desiredResourceNodeCounts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'node targets use selected-town reachability and retain invalid choices '
    'only for removal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scopedDataset = _rootScopedNetworkDataset();
      final updates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: scopedDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              desiredResourceNodeCounts: const <String, int>{'wood': 1},
              rootNodeIds: const <String>{'root-a'},
            ),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await _openNodeMaterialTargets(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('resource-map-node-target-search')),
        'Ash Timber',
      );
      await tester.pump();

      final availability = find.byKey(
        const ValueKey<String>('resource-map-node-target-availability-wood'),
      );
      final targetRow = find.byKey(
        const ValueKey<String>('resource-map-node-target-wood'),
      );
      final incrementButton = find.descendant(
        of: targetRow,
        matching: find.widgetWithIcon(IconButton, Icons.add_rounded),
      );
      final decrementButton = find.byKey(
        const ValueKey<String>('resource-map-node-target-minus-wood'),
      );
      final removeButton = find.byKey(
        const ValueKey<String>('resource-map-node-target-remove-wood'),
      );
      IconButton buttonInside(Finder control) => tester.widget<IconButton>(
        find.descendant(of: control, matching: find.byType(IconButton)),
      );
      expect(find.text('1 available worker node'), findsOneWidget);
      expect(tester.widget<Text>(availability).data, '1 available worker node');
      expect(tester.widget<IconButton>(incrementButton).onPressed, isNull);
      expect(buttonInside(decrementButton).onPressed, isNull);
      expect(buttonInside(removeButton).onPressed, isNotNull);

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-node-target-settings-toggle'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-node-starting-towns-targets'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Root A'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Isolated'));
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-save-starting-towns')),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await _settleNodeTargetPreview(tester);

      expect(updates.last.rootNodeIds, const <String>{'isolated'});
      expect(updates.last.desiredResourceNodeCounts, const <String, int>{
        'wood': 1,
      });
      expect(
        tester.widget<Text>(availability).data,
        'No reachable nodes from your chosen towns',
      );
      expect(tester.widget<IconButton>(incrementButton).onPressed, isNull);

      await tester.tap(targetRow);
      await tester.pump();
      expect(
        updates.last.desiredResourceNodeCounts,
        const <String, int>{'wood': 1},
        reason:
            'A selected row is informational; only its explicit X removes it.',
      );
      await tester.tap(incrementButton, warnIfMissed: false);
      await tester.pump();
      expect(
        updates.last.desiredResourceNodeCounts,
        const <String, int>{'wood': 1},
        reason: 'The disabled plus button must be a no-op at the real maximum.',
      );
      await tester.tap(removeButton);
      await tester.pump();
      expect(updates.last.desiredResourceNodeCounts, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-target-wood')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing the saved node baseline requires confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scopedDataset = _rootScopedNetworkDataset();
    final updates = <BdoNodeNetworkPreferences>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: BdoResourceMap(
          dataset: scopedDataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
          nodeNetworkPreferences: BdoNodeNetworkPreferences(
            desiredResourceNodeCounts: const <String, int>{'wood': 1},
            currentNodeIds: const <String>{'root-a', 'wood-a'},
            rootNodeIds: const <String>{'root-a'},
          ),
          onNodeNetworkPreferencesChanged: updates.add,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _openNodeMaterialTargets(tester);
    await _settleNodeTargetPreview(tester);

    expect(find.byTooltip('Clear saved setup'), findsNothing);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-node-target-settings-toggle'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Clear saved setup'), findsOneWidget);

    final clearSaved = find
        .byKey(const ValueKey<String>('resource-map-clear-saved-node-network'))
        .hitTestable();
    await tester.tap(clearSaved);
    await tester.pumpAndSettle();
    expect(find.text('Clear saved network?'), findsOneWidget);
    final dialogTheme = Theme.of(tester.element(find.byType(AlertDialog)));
    expect(dialogTheme.brightness, Brightness.dark);
    expect(dialogTheme.colorScheme.primary, ResourceMapAtlasColors.primary);
    expect(
      dialogTheme.dialogTheme.backgroundColor,
      ResourceMapAtlasColors.paperRaised,
      reason:
          'Map dialogs must keep the Atlas surface even when the outer app '
          'uses a dark or themed appearance.',
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-cancel-clear-node-network'),
      ),
    );
    await tester.pumpAndSettle();
    expect(updates, isEmpty);
    expect(find.text('Show my setup'), findsOneWidget);

    await tester.tap(clearSaved);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-confirm-clear-node-network'),
      ),
    );
    await tester.pumpAndSettle();
    expect(updates, hasLength(1));
    expect(updates.single.currentNodeIds, isEmpty);
    expect(find.text('Show my setup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large requests return a complete scalable network', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final largeDataset = _largeNetworkDataset(productionNodeCount: 11);

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: largeDataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
          nodeNetworkPreferences: BdoNodeNetworkPreferences(
            desiredResourceNodeCounts: const <String, int>{'wood': 11},
            rootNodeIds: const <String>{'root'},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _openNodeMaterialTargets(tester);

    final buildRoute = find.byKey(
      const ValueKey<String>('resource-map-build-node-network'),
    );
    expect(buildRoute, findsOneWidget);
    expect(tester.widget<FilledButton>(buildRoute).onPressed, isNotNull);
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-build-node-network')),
    );
    await _settleNodeNetworkCalculation(tester);

    expect(find.text('Recommended complete network'), findsOneWidget);
    expect(
      find.textContaining(
        'This request is too large for an exact cheapest calculation.',
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-review-material-wood')),
      findsOneWidget,
    );
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.nodeNetworkEdgeChanges,
      hasLength(11),
      reason: 'Every requested production node must remain connected on-map.',
    );
    expect(
      canvas.nodeNetworkChangeKinds.values,
      contains(BdoNodeNetworkChangeKind.connect),
    );
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-save-current-node-network'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact node planner opens without losing its Back action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(680, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-compact-node-planner')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-planner-header-home'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-compact-node-planner-sheet'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-planner-close')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-mode-materials')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-compact-node-planner-sheet'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-planner-targets')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact worker income uses the Atlas reading surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(680, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: _rerouteNetworkDataset(),
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            workerEconomics: _rerouteWorkerEconomics(),
            lodgingDataset: _rerouteLodgingDataset(),
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              contributionPointBudget: 20,
              onlineHoursPerDay: 8,
              resourceAvailabilityPercent: 100,
              townWorkerCapacitiesByNodeId:
                  const <String, BdoTownWorkerCapacity>{
                    'root': BdoTownWorkerCapacity(
                      availableWorkerCount: 0,
                      freeLodgingSlotCount: 0,
                    ),
                  },
            ),
            marketOutputEvidenceByResourceId:
                const <String, MarketValueOutputInput>{
                  'x': MarketValueOutputInput(
                    outputId: 'x',
                    outputName: 'X Material',
                    isMarketable: true,
                    currentUnitPrice: 100,
                    listedStock: 0,
                  ),
                  'y': MarketValueOutputInput(
                    outputId: 'y',
                    outputName: 'Y Material',
                    isMarketable: true,
                    currentUnitPrice: 90,
                    listedStock: 1000,
                  ),
                },
            marketNetRate: 0.845,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await _openNodePlanner(tester);

    final openIncome = find.byKey(
      const ValueKey<String>('resource-map-open-market-value-recommendations'),
    );
    await tester.ensureVisible(openIncome);
    await tester.pumpAndSettle();
    await tester.tap(openIncome);
    await tester.pumpAndSettle();

    final incomePage = find.byKey(
      const ValueKey<String>('resource-map-market-value-page'),
    );
    expect(incomePage, findsOneWidget);
    final eyebrow = tester.widget<Text>(find.text('ESTIMATED INCOME'));
    expect(eyebrow.style?.color, ResourceMapAtlasColors.accent);
    expect(eyebrow.style?.fontSize, greaterThanOrEqualTo(12));
    final hourly = tester.widget<Text>(find.textContaining('/ hour'));
    expect(hourly.style?.color, ResourceMapAtlasColors.ink);
    expect(hourly.style?.fontSize, greaterThanOrEqualTo(24));
    expect(find.text('Recommended route'), findsOneWidget);
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_worker_income_compact.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('node planner stays readable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 900),
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await _openNodePlanner(tester);

    expect(find.text('Plan your workers'), findsNothing);
    expect(find.text('Planned network'), findsOneWidget);
    expect(find.text('Best income'), findsOneWidget);
    expect(find.text('Find nodes'), findsOneWidget);
    expect(find.text('What should your workers collect?'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-mode-materials')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('external map focus opens the applicable source directly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = BdoResourceMapController()
      ..focus(
        const BdoResourceMapFocusRequest(
          materialName: 'Snake Meat',
          source: BdoResourceMapFocusSource.manualGathering,
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringPoints, isNotEmpty);
    expect(canvas.workerNodes, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Snake Meat',
    );

    controller.focus(
      const BdoResourceMapFocusRequest(
        materialName: 'Ash Timber',
        source: BdoResourceMapFocusSource.workerNodes,
      ),
    );
    await tester.pumpAndSettle();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isNotEmpty);
    expect(canvas.gatheringPoints, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external NPC vendor focus shows a real Salt seller and details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const davidId = 'npc:40013:1:location:0';
      final david = dataset.vendorNpcsById[davidId]!;
      final davidSalt = dataset
          .vendorListingsForItem('Salt')
          .singleWhere((listing) => listing.vendorId == davidId);
      final vendorDataset = BdoResourceMapDataset(
        manifest: dataset.manifest,
        resources: dataset.resources,
        workerNodes: dataset.workerNodes,
        gatheringSpots: dataset.gatheringSpots,
        gatheringPoints: dataset.gatheringPoints,
        gatheringRoutes: dataset.gatheringRoutes,
        fieldSources: dataset.fieldSources,
        vendorNpcs: <BdoVendorNpc>[david],
        vendorListings: <BdoVendorListing>[davidSalt],
      );
      final controller = BdoResourceMapController()
        ..focus(
          const BdoResourceMapFocusRequest(
            materialName: 'Salt',
            source: BdoResourceMapFocusSource.npcVendors,
          ),
        );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: vendorDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              controller: controller,
              vendorItemIconBuilder: (context, itemName, size) => SizedBox(
                key: const ValueKey<String>('test-vendor-item-art'),
                width: size,
                height: size,
                child: const Icon(Icons.water_drop_rounded),
              ),
              vendorPortraitBuilder: (context, vendor, size) => SizedBox.square(
                key: ValueKey<String>('test-vendor-portrait-${vendor.id}'),
                dimension: size,
                child: const Icon(Icons.face_rounded),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('resource-map-vendor-lookup-banner')),
        findsOneWidget,
      );
      expect(
        find.text('1 mapped NPC location · click a pin for details'),
        findsOneWidget,
      );
      final vendorMarkers = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('resource-map-vendor-marker-');
      });
      expect(vendorMarkers, findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-vendor-marker-$davidId'),
          ),
          matching: find.byType(InkResponse),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey<String>('resource-map-vendor-details-$davidId'),
        ),
        findsOneWidget,
      );
      expect(find.text('David Finto'), findsOneWidget);
      expect(find.text('<Chef>'), findsOneWidget);
      expect(find.text('20 silver'), findsOneWidget);
      expect(find.textContaining('Source-recorded map location'), findsNothing);
      final details = find.byKey(
        const ValueKey<String>('resource-map-vendor-details-$davidId'),
      );
      final portrait = find.byKey(
        const ValueKey<String>('test-vendor-portrait-$davidId'),
      );
      expect(portrait, findsOneWidget);
      expect(tester.getSize(portrait), const Size.square(80));
      expect(
        find.descendant(
          of: details,
          matching: find.byIcon(Icons.person_rounded),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('test-vendor-item-art')),
        findsNWidgets(2),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-close-vendor-details-$davidId'),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-vendor-details-$davidId'),
        ),
        findsNothing,
      );
      expect(vendorMarkers, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('repeated vendor focus keeps one Back step and restores camera', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const davidId = 'npc:40013:1:location:0';
    final david = dataset.vendorNpcsById[davidId]!;
    final davidSalt = dataset
        .vendorListingsForItem('Salt')
        .singleWhere((listing) => listing.vendorId == davidId);
    final vendorDataset = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: dataset.resources,
      workerNodes: dataset.workerNodes,
      gatheringSpots: dataset.gatheringSpots,
      gatheringPoints: dataset.gatheringPoints,
      gatheringRoutes: dataset.gatheringRoutes,
      fieldSources: dataset.fieldSources,
      vendorNpcs: <BdoVendorNpc>[david],
      vendorListings: <BdoVendorListing>[davidSalt],
    );
    final controller = BdoResourceMapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: vendorDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialCamera = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;

    const request = BdoResourceMapFocusRequest(
      materialName: 'Salt',
      source: BdoResourceMapFocusSource.npcVendors,
    );
    controller.focus(request);
    await tester.pumpAndSettle();
    controller.focus(request);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-vendor-lookup-back')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('resource-map-vendor-lookup-banner')),
      findsNothing,
    );
    final restoredCamera = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;
    expect(restoredCamera.zoom, closeTo(initialCamera.zoom, 0.000001));
    expect(restoredCamera.center.x, closeTo(initialCamera.center.x, 0.001));
    expect(restoredCamera.center.y, closeTo(initialCamera.center.y, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate navigation refreshes the camera and layers restored by Back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = BdoResourceMapController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const request = BdoResourceMapFocusRequest(
        materialName: 'Thuja Sap',
        resourceId: 'item:5020',
        source: BdoResourceMapFocusSource.manualGathering,
      );
      controller.focus(request);
      await tester.pumpAndSettle();
      controller.focus(request);
      await tester.pumpAndSettle();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      final cameraBeforeAdjustment = canvas.cameraController.camera;
      canvas.cameraController.panBy(const Offset(96, -54), viewport);
      await tester.pump();
      final latestCamera = canvas.cameraController.camera;
      expect(latestCamera, isNot(cameraBeforeAdjustment));
      final latestWorkerNodeIds = canvas.workerNodes
          .map((node) => node.id)
          .toSet();
      final latestGatheringSpotIds = canvas.gatheringSpots
          .map((spot) => spot.id)
          .toSet();
      final latestGatheringPointIds = canvas.gatheringPoints
          .map((point) => point.id)
          .toSet();
      final latestGatheringRouteIds = canvas.gatheringRoutes
          .map((route) => route.id)
          .toSet();
      expect(latestWorkerNodeIds, isEmpty);
      expect(
        latestGatheringSpotIds.isNotEmpty ||
            latestGatheringPointIds.isNotEmpty ||
            latestGatheringRouteIds.isNotEmpty,
        isTrue,
      );
      expect(canvas.showConnections, isFalse);

      controller.focus(request);
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final refocusedCamera = canvas.cameraController.camera;
      expect(
        refocusedCamera.center.x,
        isNot(closeTo(latestCamera.center.x, 1)),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pumpAndSettle();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final restoredCamera = canvas.cameraController.camera;
      expect(restoredCamera.zoom, closeTo(latestCamera.zoom, 0.000001));
      expect(restoredCamera.center.x, closeTo(latestCamera.center.x, 0.001));
      expect(restoredCamera.center.y, closeTo(latestCamera.center.y, 0.001));
      expect(
        canvas.workerNodes.map((node) => node.id).toSet(),
        latestWorkerNodeIds,
      );
      expect(
        canvas.gatheringSpots.map((spot) => spot.id).toSet(),
        latestGatheringSpotIds,
      );
      expect(
        canvas.gatheringPoints.map((point) => point.id).toSet(),
        latestGatheringPointIds,
      );
      expect(
        canvas.gatheringRoutes.map((route) => route.id).toSet(),
        latestGatheringRouteIds,
      );
      expect(canvas.showConnections, isFalse);
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('coincident vendor records remain individually selectable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const waleId = 'npc:40605:1:location:0';
    const secondId = 'test:coincident-wale';
    final wale = dataset.vendorNpcsById[waleId]!;
    final second = BdoVendorNpc(
      id: secondId,
      sourceVendorId: 'test:coincident-wale-source',
      gameNpcId: wale.gameNpcId,
      spawnId: 99,
      name: 'Wale Annex',
      role: wale.role,
      location: wale.location,
      sourceUrl: wale.sourceUrl,
      reviewedAt: wale.reviewedAt,
      verification: wale.verification,
      provenanceId: wale.provenanceId,
    );
    final waleListing = dataset
        .vendorListingsForItem('Blue Reagent')
        .singleWhere((listing) => listing.vendorId == waleId);
    final listings = <BdoVendorListing>[
      waleListing,
      BdoVendorListing(
        itemId: waleListing.itemId,
        itemName: waleListing.itemName,
        vendorId: secondId,
        priceSilver: waleListing.priceSilver,
        provenanceId: waleListing.provenanceId,
      ),
    ];
    final vendorDataset = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: dataset.resources,
      workerNodes: dataset.workerNodes,
      gatheringSpots: dataset.gatheringSpots,
      gatheringPoints: dataset.gatheringPoints,
      gatheringRoutes: dataset.gatheringRoutes,
      fieldSources: dataset.fieldSources,
      vendorNpcs: <BdoVendorNpc>[wale, second],
      vendorListings: listings,
    );
    final controller = BdoResourceMapController()
      ..focus(
        const BdoResourceMapFocusRequest(
          materialName: 'Blue Reagent',
          source: BdoResourceMapFocusSource.npcVendors,
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: vendorDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            controller: controller,
            vendorPortraitBuilder: (context, vendor, size) => SizedBox.square(
              key: ValueKey<String>('test-vendor-portrait-${vendor.id}'),
              dimension: size,
              child: const Icon(Icons.face_rounded),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cluster = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('resource-map-vendor-cluster-');
    });
    expect(cluster, findsOneWidget);
    await tester.tap(
      find.descendant(of: cluster, matching: find.byType(InkResponse)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('resource-map-vendor-cluster-picker')),
      findsOneWidget,
    );
    expect(find.text('2 NPC sellers nearby'), findsOneWidget);
    expect(find.text('Wale'), findsOneWidget);
    expect(find.text('Wale Annex'), findsOneWidget);
    expect(find.text('50.000 silver'), findsNWidgets(2));
    final picker = find.byKey(
      const ValueKey<String>('resource-map-vendor-cluster-picker'),
    );
    for (final vendorId in <String>[waleId, secondId]) {
      final portrait = find.byKey(
        ValueKey<String>('test-vendor-portrait-$vendorId'),
      );
      expect(portrait, findsOneWidget);
      expect(tester.getSize(portrait), const Size.square(40));
    }
    expect(
      find.descendant(of: picker, matching: find.byIcon(Icons.person_rounded)),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-vendor-cluster-choice-$secondId'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('resource-map-vendor-cluster-picker')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-vendor-details-$secondId'),
      ),
      findsOneWidget,
    );
    final selectedPortrait = find.byKey(
      const ValueKey<String>('test-vendor-portrait-$secondId'),
    );
    expect(selectedPortrait, findsOneWidget);
    expect(tester.getSize(selectedPortrait), const Size.square(80));
    expect(find.text('<Material Vendor>'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vendor pin and details stay usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const davidId = 'npc:40013:1:location:0';
    final david = dataset.vendorNpcsById[davidId]!;
    final davidSalt = dataset
        .vendorListingsForItem('Salt')
        .singleWhere((listing) => listing.vendorId == davidId);
    final controller = BdoResourceMapController()
      ..focus(
        const BdoResourceMapFocusRequest(
          materialName: 'Salt',
          source: BdoResourceMapFocusSource.npcVendors,
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: BdoResourceMapDataset(
              manifest: dataset.manifest,
              resources: dataset.resources,
              workerNodes: dataset.workerNodes,
              gatheringSpots: dataset.gatheringSpots,
              gatheringPoints: dataset.gatheringPoints,
              gatheringRoutes: dataset.gatheringRoutes,
              fieldSources: dataset.fieldSources,
              vendorNpcs: <BdoVendorNpc>[david],
              vendorListings: <BdoVendorListing>[davidSalt],
            ),
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final marker = find.byKey(
      const ValueKey<String>('resource-map-vendor-marker-$davidId'),
    );
    expect(tester.getSize(marker), const Size(48, 48));
    await tester.tap(
      find.descendant(of: marker, matching: find.byType(InkResponse)),
    );
    await tester.pump();

    final card = find.byKey(
      const ValueKey<String>('resource-map-vendor-details-$davidId'),
    );
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    final mapRect = tester.getRect(find.byType(BdoResourceMap));
    expect(cardRect.top, greaterThanOrEqualTo(mapRect.top));
    expect(cardRect.bottom, lessThanOrEqualTo(mapRect.bottom));
    expect(
      find.descendant(of: card, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.person_rounded)),
      findsOneWidget,
    );
    expect(find.textContaining('not yet independently'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external focus opens field-source details without inventing exact dots',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = BdoResourceMapController()
        ..focus(
          const BdoResourceMapFocusRequest(
            materialName: 'Insectivore Plant Flower',
            resourceId: 'item:5440',
            source: BdoResourceMapFocusSource.manualGathering,
          ),
        );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.gatheringPoints,
        isEmpty,
        reason:
            'Poisonous Swamp Plant has source guidance but no trustworthy '
            'exact spawn coordinates.',
      );
      expect(canvas.gatheringSpots, isEmpty);
      expect(canvas.gatheringRoutes, isEmpty);
      expect(canvas.workerNodes, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Insectivore Plant Flower',
      );
      final details = find.byKey(
        const ValueKey<String>('resource-map-sidebar-details'),
      );
      expect(details, findsOneWidget);
      expect(
        find.descendant(
          of: details,
          matching: find.text('Poisonous Swamp Plant'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: details,
          matching: find.text('Insectivore Plant Flower'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'external worker-plan focus merges a material and opens its count controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ash = dataset.resources.singleWhere(
        (resource) => resource.name == 'Ash Timber',
      );
      final iron = dataset.resources.singleWhere(
        (resource) => resource.name == 'Iron Ore',
      );
      final updates = <BdoNodeNetworkPreferences>[];
      final controller = BdoResourceMapController()
        ..focus(
          const BdoResourceMapFocusRequest(
            materialName: 'Ash Timber',
            source: BdoResourceMapFocusSource.workerNodePlanner,
          ),
        );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            controller: controller,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              desiredResourceNodeCounts: <String, int>{iron.id: 1},
            ),
            onNodeNetworkPreferencesChanged: updates.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('resource-map-node-planner-targets')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('resource-map-node-target-${ash.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('resource-map-node-target-remove-${ash.id}'),
        ),
        findsOneWidget,
      );
      expect(updates, isNotEmpty);
      expect(updates.last.desiredResourceNodeCounts[ash.id], 1);
      expect(updates.last.desiredResourceNodeCounts[iron.id], 1);

      final plus = find.byKey(
        ValueKey<String>('resource-map-node-target-plus-${ash.id}'),
      );
      expect(plus, findsOneWidget);
      await tester.tap(plus);
      await tester.pump();
      expect(updates.last.desiredResourceNodeCounts[ash.id], 2);
      expect(updates.last.desiredResourceNodeCounts[iron.id], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gather checklist reorders, completes, and advances to mapped sources',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final snake = dataset.resources.singleWhere(
        (resource) => resource.name == 'Snake Meat',
      );
      final ash = dataset.resources.singleWhere(
        (resource) => resource.name == 'Ash Timber',
      );
      final updates = <BdoGatherChecklist>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            gatherChecklist: BdoGatherChecklist(
              entries: <BdoGatherChecklistEntry>[
                BdoGatherChecklistEntry(
                  resourceId: snake.id,
                  displayName: snake.name,
                  sourceKind: BdoGatherChecklistSourceKind.manualGathering,
                ),
                BdoGatherChecklistEntry(
                  resourceId: ash.id,
                  displayName: ash.name,
                  sourceKind: BdoGatherChecklistSourceKind.workerNode,
                ),
              ],
            ),
            onGatherChecklistChanged: updates.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await _openGatherHub(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-shortcut-checklist')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 remaining · 0 complete'), findsOneWidget);
      expect(find.text('Snake Meat'), findsOneWidget);
      expect(find.text('Ash Timber'), findsOneWidget);

      final reorderable = tester.widget<ReorderableListView>(
        find.byKey(
          const ValueKey<String>('resource-map-gather-checklist-list'),
        ),
      );
      reorderable.onReorderItem!(0, 1);
      await tester.pump();
      expect(updates.last.entries.map((entry) => entry.resourceId), <String>[
        ash.id,
        snake.id,
      ]);

      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-gather-checklist-locate-${snake.id}'),
        ),
      );
      await tester.pumpAndSettle();
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, isNotEmpty);
      expect(canvas.workerNodes, isEmpty);
      expect(
        find.byKey(
          ValueKey<String>('resource-map-detail-checklist-next-${snake.id}'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          ValueKey<String>('resource-map-detail-checklist-next-${snake.id}'),
        ),
      );
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.workerNodes, isNotEmpty);
      expect(canvas.gatheringPoints, isEmpty);
      expect(updates.last.selectedResourceId, ash.id);
      expect(
        updates.last.entries
            .singleWhere((entry) => entry.resourceId == snake.id)
            .isCompleted,
        isTrue,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-detail-open-checklist'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 remaining · 1 complete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fit all restores every Snake Meat dot after extreme zoom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Snake Meat');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Snake Meat'),
      ),
    );
    await tester.pump();

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final snakeResource = dataset.resources.singleWhere(
      (resource) => resource.name == 'Snake Meat',
    );
    final snakePoints = dataset
        .gatheringPointsForResource(snakeResource.id)
        .toList(growable: false);
    final viewport = tester.getSize(find.byType(BdoMapCanvas));
    expect(snakePoints.length, greaterThan(300));
    expect(canvas.gatheringPoints, hasLength(snakePoints.length));

    canvas.cameraController.setCamera(
      BdoMapCamera(
        center: tileSource.worldBounds.center.translate(900000, -700000),
        zoom: canvas.cameraController.maximumZoom,
      ),
      viewport,
    );
    await tester.pump();
    expect(
      canvas.cameraController.camera.zoom,
      canvas.cameraController.maximumZoom,
    );

    final fitAll = find.byKey(
      const ValueKey<String>(
        'resource-map-fit-field-source-field-source:snake',
      ),
    );
    await tester.scrollUntilVisible(
      fitAll,
      180,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(fitAll);
    await tester.pump();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final fittedBounds = canvas.cameraController.visibleWorldBounds(viewport);
    expect(
      snakePoints.every(
        (point) => fittedBounds.contains(point.location.mapPoint),
      ),
      isTrue,
      reason: 'Fit all must put every exact Snake Meat dot in the viewport.',
    );
    final paddedViewport = Rect.fromLTWH(
      52,
      52,
      viewport.width - 104,
      viewport.height - 104,
    );
    expect(
      snakePoints.every(
        (point) => paddedViewport.contains(
          canvas.cameraController.worldToScreen(
            point.location.mapPoint,
            viewport,
          ),
        ),
      ),
      isTrue,
      reason: 'Exact dots should remain inside the intended fit padding.',
    );
    expect(canvas.cameraController.camera.zoom, lessThan(4.15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity search opens its full worker overview on Enter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Mining');
    await tester.pumpAndSettle();
    final miningCount = dataset.workerNodes
        .where(
          (node) =>
              node.isResourceNode && node.activity == BdoWorkerActivity.mining,
        )
        .length;
    expect(
      find.byKey(const ValueKey<String>('resource-map-search-activity-mining')),
      findsOneWidget,
    );
    expect(find.text('ACTIVITIES'), findsOneWidget);
    expect(find.textContaining('$miningCount worker nodes'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, hasLength(miningCount));
    expect(
      canvas.workerNodes.every(
        (node) => node.activity == BdoWorkerActivity.mining,
      ),
      isTrue,
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(
              const ValueKey<String>('resource-map-worker-activity-mining'),
            ),
          )
          .color,
      ResourceMapAtlasColors.primary,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-explorer')),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop commands open focused worker tasks with padded targets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final contextPanel = find.byKey(
        const ValueKey<String>('resource-map-desktop-sidebar'),
      );
      expect(
        contextPanel,
        findsNothing,
        reason: 'Desktop starts map-first, without a permanent sidebar.',
      );
      final workersButton = find.byKey(
        const ValueKey<String>('resource-map-command-workers'),
      );
      expect(tester.getSize(workersButton).height, greaterThanOrEqualTo(40));
      expect(
        tester.getSize(find.byTooltip('Zoom in')).shortestSide,
        greaterThanOrEqualTo(44),
      );
      final statusToggle = find.byKey(
        const ValueKey<String>('resource-map-status-toggle'),
      );
      expect(
        tester.getSize(statusToggle).shortestSide,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(statusToggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byTooltip('Map source and fan-content notice'))
            .shortestSide,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(statusToggle);
      await tester.pumpAndSettle();

      await tester.tap(workersButton);
      await tester.pumpAndSettle();
      expect(
        contextPanel,
        findsNothing,
        reason: 'Worker goals stay on the map instead of opening a drawer.',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-hub')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-browse-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-mode-materials')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-worker-current-action'),
        ),
        findsOneWidget,
      );
      expect(find.text('Find nodes'), findsOneWidget);
      expect(find.text('Planned network'), findsOneWidget);
      expect(find.text('Best income'), findsOneWidget);
      expect(find.text('Plan a node network'), findsNothing);
      expect(find.text('YOUR GAME SETUP'), findsNothing);
      expect(find.text('What would you like to do?'), findsNothing);
      expect(find.text('MAP DISPLAY'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-all-nodes')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-connections')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-output-icons')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-worker-browse-action')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('resource-map-worker-explorer')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop contextual surface keeps permanent landmarks and vivid colors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferenceUpdates = <BdoNodeNetworkPreferences>[];

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                showCitiesAndTowns: false,
                showGatewayHubs: false,
                mapVisualStyle: BdoMapVisualStyle.standard,
              ),
              onNodeNetworkPreferencesChanged: preferenceUpdates.add,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final hiddenSidebar = find.byKey(
        const ValueKey<String>('resource-map-desktop-sidebar-hidden'),
      );
      expect(hiddenSidebar, findsOneWidget);
      expect(
        tester
            .widget<ExcludeFocus>(
              find.byKey(
                const ValueKey<String>('resource-map-desktop-sheet-focus'),
              ),
            )
            .excluding,
        isTrue,
      );
      expect(
        tester
            .widget<ExcludeSemantics>(
              find.byKey(
                const ValueKey<String>('resource-map-desktop-sheet-semantics'),
              ),
            )
            .excluding,
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-gather')),
      );
      await tester.pumpAndSettle();
      expect(hiddenSidebar, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-hub')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ExcludeFocus>(
              find.byKey(
                const ValueKey<String>('resource-map-desktop-sheet-focus'),
              ),
            )
            .excluding,
        isTrue,
      );
      expect(
        tester
            .widget<ExcludeSemantics>(
              find.byKey(
                const ValueKey<String>('resource-map-desktop-sheet-semantics'),
              ),
            )
            .excluding,
        isTrue,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-gather')),
      );
      await tester.pumpAndSettle();
      expect(hiddenSidebar, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-hub')),
        findsNothing,
        reason: 'Closing Gather removes its source strip from the map.',
      );
      expect(
        tester
            .widget<ExcludeFocus>(
              find.byKey(
                const ValueKey<String>('resource-map-desktop-sheet-focus'),
              ),
            )
            .excluding,
        isTrue,
      );

      final searchField = find.byType(TextField);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(searchField).focusNode!.hasFocus, isTrue);

      final orientationNodes = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            ((widget.key! as ValueKey<String>).value).startsWith(
              'resource-map-orientation-node-',
            ),
      );
      expect(orientationNodes, findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('resource-map-layer-menu')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-layer-menu-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('resource-map-layer-menu')),
        findsOneWidget,
      );

      final towns = find.byKey(
        const ValueKey<String>('resource-map-layer-towns'),
      );
      final hubs = find.byKey(
        const ValueKey<String>('resource-map-layer-hubs'),
      );
      final allNodes = find.byKey(
        const ValueKey<String>('resource-map-layer-all-nodes'),
      );
      final allConnections = find.byKey(
        const ValueKey<String>('resource-map-layer-all-connections'),
      );
      final outputs = find.byKey(
        const ValueKey<String>('resource-map-layer-worker-outputs'),
      );
      final vividColors = find.byKey(
        const ValueKey<String>('resource-map-layer-vivid-colors'),
      );
      Semantics layerSemantics(Finder control) => tester.widget<Semantics>(
        find.descendant(of: control, matching: find.byType(Semantics)).first,
      );
      expect(towns, findsNothing);
      expect(hubs, findsNothing);
      expect(vividColors, findsNothing);
      expect(layerSemantics(allNodes).properties.toggled, isTrue);
      expect(layerSemantics(allConnections).properties.toggled, isTrue);
      expect(layerSemantics(outputs).properties.toggled, isTrue);
      expect(
        tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas)).visualStyle,
        BdoMapVisualStyle.vivid,
      );
      expect(
        tester
            .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
            .showAllNetworkConnections,
        isTrue,
      );

      await tester.tap(allNodes);
      await tester.pumpAndSettle();

      expect(layerSemantics(allNodes).properties.toggled, isFalse);
      expect(allConnections, findsNothing);
      expect(outputs, findsNothing);
      expect(preferenceUpdates, hasLength(1));
      expect(preferenceUpdates.last.showCitiesAndTowns, isTrue);
      expect(preferenceUpdates.last.showGatewayHubs, isTrue);
      expect(preferenceUpdates.last.showAllMapNodes, isFalse);
      expect(preferenceUpdates.last.showAllNodeConnections, isTrue);
      expect(preferenceUpdates.last.showWorkerOutputIcons, isTrue);
      expect(preferenceUpdates.last.mapVisualStyle, BdoMapVisualStyle.vivid);
      expect(
        tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas)).visualStyle,
        BdoMapVisualStyle.vivid,
      );
      expect(
        tester
            .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
            .showAllNetworkConnections,
        isFalse,
      );
      expect(orientationNodes, findsNothing);

      await tester.tap(allNodes);
      await tester.pumpAndSettle();
      expect(layerSemantics(allNodes).properties.toggled, isTrue);
      expect(allConnections, findsOneWidget);
      expect(outputs, findsOneWidget);
      expect(layerSemantics(allConnections).properties.toggled, isTrue);
      expect(orientationNodes, findsWidgets);
      expect(
        tester
            .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
            .showAllNetworkConnections,
        isTrue,
      );

      await tester.tap(allConnections);
      await tester.tap(outputs);
      await tester.pumpAndSettle();
      expect(layerSemantics(allConnections).properties.toggled, isFalse);
      expect(layerSemantics(outputs).properties.toggled, isFalse);
      expect(preferenceUpdates, hasLength(4));
      expect(preferenceUpdates.last.showCitiesAndTowns, isTrue);
      expect(preferenceUpdates.last.showGatewayHubs, isTrue);
      expect(preferenceUpdates.last.showAllMapNodes, isTrue);
      expect(preferenceUpdates.last.showAllNodeConnections, isFalse);
      expect(preferenceUpdates.last.showWorkerOutputIcons, isFalse);
      expect(preferenceUpdates.last.mapVisualStyle, BdoMapVisualStyle.vivid);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-layer-menu-toggle')),
      );
      await tester.pumpAndSettle();
      expect(towns, findsNothing);
      expect(hubs, findsNothing);
      expect(vividColors, findsNothing);
      expect(layerSemantics(allNodes).properties.toggled, isTrue);
      expect(layerSemantics(allConnections).properties.toggled, isFalse);
      expect(layerSemantics(outputs).properties.toggled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('worker hub stays flat and usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: dataset,
            lodgingDataset: lodgingDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();

    final hub = find.byKey(const ValueKey<String>('resource-map-worker-hub'));
    expect(hub, findsOneWidget);
    expect(find.descendant(of: hub, matching: find.byType(Card)), findsNothing);
    final hubScrollable = find.descendant(
      of: hub,
      matching: find.byType(Scrollable),
    );
    expect(hubScrollable, findsOneWidget);
    for (final entry in <(String, String)>[
      ('resource-map-node-mode-materials', 'Planned network'),
      ('resource-map-open-market-value-recommendations', 'Best income'),
      ('resource-map-worker-browse-action', 'Find nodes'),
    ]) {
      final action = find.byKey(ValueKey<String>(entry.$1));
      await tester.scrollUntilVisible(action, 120, scrollable: hubScrollable);
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      final titleFinder = find.descendant(
        of: action,
        matching: find.text(entry.$2),
      );
      final titleWidget = tester.widget<Text>(titleFinder);
      final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
      expect(titleWidget.maxLines, 1);
      expect(
        titleParagraph.didExceedMaxLines,
        isFalse,
        reason:
            '${entry.$2} should remain complete at 200% text '
            '(laid out at ${titleParagraph.size}).',
      );
      final actionRect = tester.getRect(action);
      expect(actionRect.top, greaterThanOrEqualTo(0));
      expect(actionRect.bottom, lessThanOrEqualTo(700));
    }
    for (final key in <String>[
      'resource-map-worker-current-action',
      'resource-map-worker-houses-action',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
    }
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-worker-royal-workshop-action'),
      ),
      findsNothing,
    );
    expect(find.text('Seoul Royal Workshop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gather hub stays one-line and usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _openGatherHub(tester);

    final hub = find.byKey(const ValueKey<String>('resource-map-gather-hub'));
    expect(hub, findsOneWidget);
    expect(find.descendant(of: hub, matching: find.byType(Card)), findsNothing);
    expect(
      find.descendant(of: hub, matching: find.byType(Scrollable)),
      findsOneWidget,
    );
    for (final key in <String>[
      'resource-map-shortcut-checklist',
      'resource-map-shortcut-favorites',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
    }
    const gatheringSections = <(String, String)>[
      ('plantsWood', 'Plants & wood'),
      ('oresMinerals', 'Ores & minerals'),
      ('meat', 'Meat'),
      ('bloodHides', 'Blood & hides'),
      ('mushrooms', 'Mushrooms'),
      ('seafoodMarine', 'Coastal gathering'),
    ];
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-mode-actions-scroll-right'),
      ),
      findsOneWidget,
      reason: 'Overflow must be visibly navigable at large text.',
    );
    for (final entry in gatheringSections) {
      final action = find.byKey(
        ValueKey<String>('resource-map-section-${entry.$1}'),
      );
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget);
      final label = find.descendant(of: action, matching: find.text(entry.$2));
      expect(label, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
        reason: '${entry.$2} must stay complete at 200% text.',
      );
    }
    await tester.tap(
      find
          .byKey(const ValueKey<String>('resource-map-section-seafoodMarine'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coastal gathering'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact overlays stay inside a short landscape viewport', (
    tester,
  ) async {
    const viewport = Size(680, 300);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Thuja Sap');
    await tester.pumpAndSettle();
    final sourceResult = find.byWidgetPredicate(
      (widget) =>
          widget is ListTile &&
          widget.title is Text &&
          (widget.title! as Text).data == 'Thuja Tree',
    );
    expect(sourceResult, findsOneWidget);
    expect(
      tester.getRect(sourceResult).bottom,
      lessThanOrEqualTo(viewport.height),
    );

    await tester.tap(sourceResult);
    await tester.pump();
    final details = find.byKey(
      const ValueKey<String>('resource-map-details-card'),
    );
    expect(details, findsOneWidget);
    final detailsRect = tester.getRect(details);
    expect(detailsRect.top, greaterThanOrEqualTo(0));
    expect(
      detailsRect.bottom,
      lessThanOrEqualTo(viewport.height - 46),
      reason: 'The status band must remain reachable below compact details.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            key: UniqueKey(),
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _openNodePlanner(tester);

    final plannerSheet = find.byKey(
      const ValueKey<String>('resource-map-compact-node-planner-sheet'),
    );
    final plannerHeader = find.byKey(
      const ValueKey<String>('resource-map-node-planner-header-home'),
    );
    expect(plannerSheet, findsOneWidget);
    expect(
      find.descendant(of: plannerSheet, matching: plannerHeader),
      findsOneWidget,
      reason:
          'A short landscape window keeps Back and CP controls inside the '
          'scrollable planner instead of painting a sheet over them.',
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-planner-close')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-apply-cp')),
      findsOneWidget,
    );

    final zoomControls = find.byKey(
      const ValueKey<String>('resource-map-zoom-controls'),
    );
    final layerToggle = find.byKey(
      const ValueKey<String>('resource-map-layer-menu-toggle'),
    );
    expect(
      tester.getRect(zoomControls).bottom,
      lessThanOrEqualTo(viewport.height),
    );
    expect(
      tester.getRect(layerToggle).bottom,
      lessThanOrEqualTo(viewport.height),
    );
    expect(
      tester.getRect(plannerSheet).right,
      lessThanOrEqualTo(tester.getRect(layerToggle).left),
      reason: 'The compact planner leaves a usable map-control gutter.',
    );

    await tester.tap(layerToggle);
    await tester.pumpAndSettle();
    final layerControls = find.byKey(
      const ValueKey<String>('resource-map-layer-controls'),
    );
    expect(
      tester.getRect(layerControls).bottom,
      lessThanOrEqualTo(viewport.height),
      reason: 'The short-window layer menu scrolls instead of leaving view.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-node thinning keeps the highest-value node in each cell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final resource = dataset.resources.first;
    final location = dataset.workerNodes.first.location;
    final city = BdoWorkerNode(
      id: 'test-city',
      name: 'Test City',
      nodeType: 'City',
      region: 'Test',
      location: location,
      contributionPoints: 0,
      linkIds: const <String>['test-connection'],
      outputs: const <BdoNodeOutput>[],
      isResourceNode: false,
    );
    final connection = BdoWorkerNode(
      id: 'test-connection',
      name: 'Test Connection',
      nodeType: 'Connection',
      region: 'Test',
      location: location,
      contributionPoints: 1,
      linkIds: const <String>['test-city', 'test-production'],
      outputs: const <BdoNodeOutput>[],
      isResourceNode: false,
    );
    final production = BdoWorkerNode(
      id: 'test-production',
      name: 'Test Connection - Mining',
      nodeType: 'Mining',
      region: 'Test',
      location: location,
      contributionPoints: 1,
      linkIds: const <String>['test-connection'],
      outputs: <BdoNodeOutput>[
        BdoNodeOutput(
          resourceId: resource.id,
          gameItemId: resource.gameItemId,
          name: resource.name,
          isPrimary: true,
        ),
      ],
      isResourceNode: true,
      parentId: connection.id,
    );
    final priorityDataset = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: <BdoResourceDefinition>[resource],
      workerNodes: <BdoWorkerNode>[city, connection, production],
      gatheringSpots: const <BdoGatheringSpot>[],
      gatheringPoints: const <BdoGatheringPoint>[],
      gatheringRoutes: const <BdoGatheringRoute>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: priorityDataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(
        const ValueKey<String>('resource-map-orientation-node-test-production'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-orientation-node-test-connection'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all-node markers open complete details without moving the camera',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final resources = dataset.resources.take(2).toList(growable: false);
      final location = dataset.workerNodes.first.location;
      final parent = BdoWorkerNode(
        id: 'test-click-parent',
        name: 'Test Click Parent',
        nodeType: 'Connection',
        region: 'Test',
        location: location,
        contributionPoints: 2,
        linkIds: const <String>['test-click-farm', 'test-click-mine'],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: false,
      );
      final farm = BdoWorkerNode(
        id: 'test-click-farm',
        name: 'Test Click Parent - Farming',
        nodeType: 'Farm',
        region: 'Test',
        location: BdoWorldPoint(location.x + 200000, location.z),
        contributionPoints: 1,
        linkIds: const <String>['test-click-parent'],
        outputs: <BdoNodeOutput>[
          BdoNodeOutput(
            resourceId: resources.first.id,
            gameItemId: resources.first.gameItemId,
            name: resources.first.name,
            isPrimary: true,
          ),
        ],
        isResourceNode: true,
        parentId: parent.id,
      );
      final mine = BdoWorkerNode(
        id: 'test-click-mine',
        name: 'Test Click Parent - Mining',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(location.x + 400000, location.z),
        contributionPoints: 1,
        linkIds: const <String>['test-click-parent'],
        outputs: <BdoNodeOutput>[
          BdoNodeOutput(
            resourceId: resources.last.id,
            gameItemId: resources.last.gameItemId,
            name: resources.last.name,
            isPrimary: true,
          ),
        ],
        isResourceNode: true,
        parentId: parent.id,
      );
      final clickableDataset = BdoResourceMapDataset(
        manifest: dataset.manifest,
        resources: resources,
        workerNodes: <BdoWorkerNode>[parent, farm, mine],
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringPoints: const <BdoGatheringPoint>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: clickableDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: parent.location.mapPoint, zoom: 4.5),
        tester.getSize(find.byType(BdoMapCanvas)),
      );
      await tester.pump();
      final cameraBeforeDirectMarkerTap = canvas.cameraController.camera;

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'resource-map-orientation-node-test-click-parent',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        canvas.cameraController.camera.center,
        cameraBeforeDirectMarkerTap.center,
      );
      expect(
        canvas.cameraController.camera.zoom,
        cameraBeforeDirectMarkerTap.zoom,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      expect(find.text('Test Click Parent'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-node-quick-panel'),
          ),
          matching: find.text('2 CP'),
        ),
        findsOneWidget,
      );
      expect(find.text('2 worker sites'), findsOneWidget);
      final quickPanel = find.byKey(
        const ValueKey<String>('resource-map-node-quick-panel'),
      );
      expect(
        find.descendant(
          of: quickPanel,
          matching: find.text('AVAILABLE WORKER NODES · 2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quickPanel, matching: find.text(farm.name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quickPanel, matching: find.text(mine.name)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-more-details')),
        findsNothing,
      );

      final farmLink = find.byKey(
        ValueKey<String>('resource-map-node-worker-site-${farm.id}'),
      );
      await tester.ensureVisible(farmLink);
      await tester.pumpAndSettle();
      await tester.tap(farmLink);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: quickPanel, matching: find.text('PRODUCES')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quickPanel, matching: find.text('CONNECTED FROM')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all-node layer fills landmark gaps below dedicated zoom thresholds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final location = dataset.workerNodes.first.location;
      final town = BdoWorkerNode(
        id: 'test-threshold-town',
        name: 'Test Threshold Town',
        nodeType: 'Town',
        region: 'Test',
        location: location,
        contributionPoints: 0,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: false,
      );
      final gateway = BdoWorkerNode(
        id: 'test-threshold-gateway',
        name: 'Test Threshold Gateway',
        nodeType: 'Gateway',
        region: 'Test',
        location: BdoWorldPoint(location.x + 250000, location.z),
        contributionPoints: 0,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: false,
      );
      final thresholdDataset = BdoResourceMapDataset(
        manifest: dataset.manifest,
        resources: const <BdoResourceDefinition>[],
        workerNodes: <BdoWorkerNode>[town, gateway],
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringPoints: const <BdoGatheringPoint>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: thresholdDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-layer-menu-toggle')),
      );
      await tester.pump();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: town.location.mapPoint, zoom: 2.8),
        viewport,
      );
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>('resource-map-landmark-${town.id}')),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey<String>('resource-map-orientation-node-${town.id}'),
        ),
        findsOneWidget,
      );

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: gateway.location.mapPoint, zoom: 2.8),
        viewport,
      );
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>('resource-map-landmark-${gateway.id}')),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey<String>('resource-map-orientation-node-${gateway.id}'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Enter selects the first visible search group', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'fish');
    await tester.pumpAndSettle();
    expect(find.text('MATERIALS'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
      findsOneWidget,
      reason:
          'Materials render ahead of Activities, so Enter must open the '
          'first material instead of the Fishing activity overview.',
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-explorer')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('category filtering and favorites stay compact and stateful', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final favoriteChanges = <Set<String>>[];
    final manualSources = dataset.fieldSources
        .where(
          (source) => source.products.any(
            (product) =>
                dataset.resourcesById[product.resourceId]?.section ==
                BdoResourceSection.plantsWood,
          ),
        )
        .toList(growable: false);
    expect(manualSources, isNotEmpty);
    final source = dataset.fieldSourcesById['field-source:thuja-tree']!;
    final resource = dataset.resources.singleWhere(
      (resource) => resource.name == 'Thuja Sap',
    );
    expect(
      source.products.map((product) => product.resourceId),
      contains(resource.id),
    );
    expect(dataset.hasWorkerSource(resource.id), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
          onFavoriteResourceIdsChanged: (favorites) {
            favoriteChanges.add(Set<String>.of(favorites));
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await _openGatherHub(tester);
    expect(find.text('Browse sources'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('resource-map-mode-action-strip')),
      findsOneWidget,
    );
    final gatherTask = find.byKey(
      const ValueKey<String>('resource-map-command-gather'),
    );
    final checklistTask = find.byKey(
      const ValueKey<String>('resource-map-shortcut-checklist'),
    );
    final favoritesTask = find.byKey(
      const ValueKey<String>('resource-map-shortcut-favorites'),
    );
    expect(
      tester.getCenter(gatherTask).dy,
      lessThan(tester.getCenter(checklistTask).dy),
      reason:
          'Gather stays in the permanent command bar while its optional '
          'Checklist and Favorites tools appear only inside the gather hub.',
    );
    expect(
      tester.getCenter(checklistTask).dy,
      lessThan(tester.getCenter(favoritesTask).dy),
      reason: 'The two optional gather tools stay in a compact vertical rail.',
    );
    expect(
      find.textContaining('Search also understands'),
      findsNothing,
      reason: 'the source browser should not need an instructional paragraph',
    );
    expect(
      tester.getSemantics(gatherTask).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-section-plantsWood')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resource-map-resource-browser')),
      findsOneWidget,
    );
    expect(find.text('Plants & wood'), findsWidgets);
    expect(
      find.textContaining('Products from the same tree'),
      findsNothing,
      reason:
          'The category list should start with its sources, not helper copy.',
    );
    expect(find.textContaining('mapped sources'), findsNothing);

    final favoriteButton = find.byKey(
      ValueKey<String>('resource-map-favorite-source-${source.id}'),
    );
    final browserScrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('resource-map-resource-browser')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      favoriteButton,
      140,
      scrollable: browserScrollable,
    );
    await tester.pump();
    expect(favoriteButton, findsOneWidget);
    await tester.tap(favoriteButton);
    await tester.pump();
    expect(favoriteChanges, isNotEmpty);
    expect(favoriteChanges.last, <String>{resource.id});

    await tester.tap(
      find.byKey(ValueKey<String>('resource-map-browser-source-${source.id}')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
      findsOneWidget,
    );
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    expect(
      canvas.gatheringPoints.isNotEmpty ||
          canvas.gatheringSpots.isNotEmpty ||
          canvas.gatheringRoutes.isNotEmpty,
      isTrue,
    );

    await tester.tap(gatherTask);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resource-map-gather-hub')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-shortcut-favorites')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Favorites'), findsWidgets);
    expect(find.text(source.name), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-resource-browser')),
      findsOneWidget,
    );

    await tester.tap(favoriteButton);
    await tester.pump();
    expect(favoriteChanges.last, isEmpty);
    expect(find.text(source.name), findsNothing);
    expect(find.text('Star a material to keep it here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no-result clear search preserves the current browser and Back history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _openGatherHub(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-section-plantsWood')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-resource-browser')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'not-a-real-map-item');
      await tester.pumpAndSettle();
      expect(find.textContaining('No results for'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Clear search'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-resource-browser')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.tap(find.widgetWithText(TextButton, 'All categories'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('resource-map-resource-browser')),
        findsNothing,
      );
      expect(find.text('Browse sources'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('resource-map-mode-action-strip')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual browse keeps Sheep meat blood and hide in one source row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sheep = dataset.fieldSourcesById['field-source:sheep']!;
      expect(sheep.products, hasLength(3));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await _openGatherHub(tester);
      final meatSection = find.byKey(
        const ValueKey<String>('resource-map-section-meat'),
      );
      await tester.ensureVisible(meatSection);
      await tester.pumpAndSettle();
      await tester.tap(meatSection.hitTestable());
      await tester.pumpAndSettle();

      final taskStrip = find.byKey(
        const ValueKey<String>('resource-map-desktop-task-strip'),
      );
      final allCategories = find.byKey(
        const ValueKey<String>('resource-map-browser-all-categories'),
      );
      final gatheringSourcesHeading = find.byKey(
        const ValueKey<String>(
          'resource-map-browser-gathering-sources-heading',
        ),
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-browser-all-categories-surface'),
        ),
        findsOneWidget,
      );
      expect(gatheringSourcesHeading, findsOneWidget);
      expect(find.text('GATHERING SOURCES'), findsOneWidget);
      expect(
        find.descendant(
          of: gatheringSourcesHeading,
          matching: find.byType(ResourceMapSurfaceIsland),
        ),
        findsOneWidget,
        reason: 'The section label needs its own compact contrast surface.',
      );
      expect(
        tester.getRect(allCategories).top - tester.getRect(taskStrip).bottom,
        lessThanOrEqualTo(12),
      );
      expect(
        tester.getRect(gatheringSourcesHeading).top -
            tester.getRect(allCategories).bottom,
        lessThanOrEqualTo(8),
      );
      expect(find.textContaining('mapped sources'), findsNothing);
      expect(find.textContaining('Products from the same tree'), findsNothing);
      await expectLater(
        find.byKey(const ValueKey<String>('resource-map-resource-browser')),
        matchesGoldenFile('goldens/resource_map_meat_browser.png'),
      );

      final sheepRow = find.byKey(
        const ValueKey<String>(
          'resource-map-browser-source-field-source:sheep',
        ),
      );
      await tester.scrollUntilVisible(
        sheepRow,
        140,
        scrollable: find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-resource-browser'),
          ),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      expect(sheepRow, findsOneWidget);
      expect(
        find.descendant(of: sheepRow, matching: find.text('Sheep')),
        findsOneWidget,
      );
      for (final productName in const <String>[
        'Lamb Meat',
        'Sheep Blood',
        'Sheep Hide',
      ]) {
        expect(
          find.descendant(
            of: sheepRow,
            matching: find.textContaining(productName),
          ),
          findsOneWidget,
        );
      }
      for (final product in sheep.products) {
        expect(
          find.byKey(
            ValueKey<String>(
              'resource-map-browser-resource-${product.resourceId}',
            ),
          ),
          findsNothing,
          reason: 'Sheep products should not become duplicate browse rows.',
        );
      }

      await tester.tap(sheepRow);
      await tester.pump();
      expect(find.text('Products & methods'), findsNothing);
      expect(find.text('Lamb Meat'), findsOneWidget);
      expect(find.text('Sheep Blood'), findsOneWidget);
      expect(find.text('Sheep Hide'), findsOneWidget);
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_gathering_product_cards.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Marni sniper hunting is an acquisition option inside animal materials',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await _openGatherHub(tester);
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-marni-sniper')),
        findsNothing,
        reason: 'A gathering method must not become a top-level category.',
      );

      final meatSection = find.byKey(
        const ValueKey<String>('resource-map-section-meat'),
      );
      await tester.ensureVisible(meatSection);
      await tester.pumpAndSettle();
      await tester.tap(meatSection.hitTestable());
      await tester.pumpAndSettle();

      final marniSource = find.byKey(
        const ValueKey<String>(
          'resource-map-browser-source-'
          'field-source:marni-sniper-hunting',
        ),
      );
      Future<void> revealMarniSource() async {
        final browserScroll = find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-resource-browser'),
          ),
          matching: find.byType(Scrollable),
        );
        final browserPosition = tester
            .state<ScrollableState>(browserScroll)
            .position;
        for (
          var offset = browserPosition.minScrollExtent;
          offset <= browserPosition.maxScrollExtent;
          offset += 120
        ) {
          browserPosition.jumpTo(
            offset.clamp(
              browserPosition.minScrollExtent,
              browserPosition.maxScrollExtent,
            ),
          );
          await tester.pump();
          if (marniSource.evaluate().isNotEmpty) {
            break;
          }
        }
        await Scrollable.ensureVisible(
          tester.element(marniSource),
          alignment: .4,
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
      }

      await revealMarniSource();
      expect(marniSource, findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'All categories'));
      await tester.pumpAndSettle();
      final bloodAndHidesSection = find.byKey(
        const ValueKey<String>('resource-map-section-bloodHides'),
      );
      await tester.ensureVisible(bloodAndHidesSection);
      await tester.pumpAndSettle();
      await tester.tap(bloodAndHidesSection.hitTestable());
      await tester.pumpAndSettle();
      await revealMarniSource();
      expect(
        marniSource,
        findsOneWidget,
        reason: 'Sniper hunting is also a method for blood and hide items.',
      );

      await tester.tap(marniSource.hitTestable());
      await tester.pumpAndSettle();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, isEmpty);
      expect(canvas.gatheringSpots.map((spot) => spot.id), <String>[
        'gathering:beombawi-marni-sniper-preserve',
      ]);
      expect(find.text('Marni Sniper Hunting'), findsWidgets);
      expect(find.text('Products & methods'), findsNothing);
      expect(find.text('Pork'), findsWidgets);
      expect(find.text('Bear Hide'), findsOneWidget);
      expect(find.text('Crystal of Decimation'), findsOneWidget);
      expect(find.text('Crystal of Bitterness'), findsOneWidget);
      expect(find.text('Crystal of Darkness'), findsOneWidget);
      expect(find.text('Forest Crystal'), findsOneWidget);
      expect(find.text('Live Meat'), findsOneWidget);
      expect(find.byType(BdoGatheringToolIcon), findsNWidgets(11));
      expect(
        find.textContaining('Pork, Pig Blood, and Pig Hide together'),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField), 'Pig');
      await tester.pumpAndSettle();
      final pigResult = find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title! as Text).data == 'Pig',
      );
      expect(pigResult, findsOneWidget);
      await tester.tap(pigResult);
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringSpots, isEmpty);
      expect(canvas.gatheringPoints, hasLength(719));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'coastal gathering keeps shore crabs and nearby shellfish distinct',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _openGatherHub(tester);

      final coastalSection = find.byKey(
        const ValueKey<String>('resource-map-section-seafoodMarine'),
      );
      await tester.ensureVisible(coastalSection);
      await tester.pumpAndSettle();
      await tester.tap(coastalSection.hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('Coastal gathering'), findsWidgets);
      expect(find.text('Sea & marine'), findsNothing);
      expect(find.text('Fish & marine'), findsNothing);
      final crabSource = find.byKey(
        const ValueKey<String>(
          'resource-map-browser-source-field-source:coral-stoneback-crab',
        ),
      );
      final shellfishSource = find.byKey(
        const ValueKey<String>(
          'resource-map-browser-source-'
          'field-source:stillcoral-coastal-gathering',
        ),
      );
      expect(crabSource, findsOneWidget);
      expect(shellfishSource, findsOneWidget);

      await tester.tap(shellfishSource);
      await tester.pumpAndSettle();
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, hasLength(198));
      expect(canvas.gatheringRoutes, isEmpty);
      expect(find.text('Products & methods'), findsNothing);
      expect(find.text('Oyster'), findsWidgets);
      expect(find.text('Giant Pearl Clam'), findsOneWidget);
      expect(find.text('Lobster'), findsOneWidget);
      expect(
        find.textContaining('no line, path order, broad circle'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Insectivore gathering dots stay separate from Flower combat drops',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gatherable =
          dataset.fieldSourcesById['field-source:insectivore-plant']!;
      final combat =
          dataset.fieldSourcesById['field-source:poisonous-swamp-plant']!;
      final powder = dataset.resources.singleWhere(
        (resource) => resource.name == 'Insectivore Plant Powder',
      );
      final flower = dataset.resources.singleWhere(
        (resource) => resource.name == 'Insectivore Plant Flower',
      );
      final gatherablePoints = dataset
          .gatheringPointsForFieldSource(gatherable.id)
          .toList(growable: false);
      expect(gatherablePoints, isNotEmpty);
      expect(
        gatherable.products.map((product) => product.resourceId),
        contains(powder.id),
      );
      expect(
        gatherable.products.map((product) => product.resourceId),
        isNot(contains(flower.id)),
      );
      expect(dataset.gatheringPointsForFieldSource(combat.id), isEmpty);
      expect(dataset.gatheringPointsForResource(flower.id), isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      Future<void> selectMaterial(String name) async {
        await tester.enterText(find.byType(TextField), name);
        await tester.pumpAndSettle();
        final result = find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.title is Text &&
              (widget.title! as Text).data == name,
        );
        expect(result, findsOneWidget);
        await tester.tap(result);
        await tester.pump();
      }

      await selectMaterial(powder.name);
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final details = find.byKey(
        const ValueKey<String>('resource-map-sidebar-details'),
      );
      expect(canvas.gatheringPoints, hasLength(gatherablePoints.length));
      expect(find.text('Insectivore Plant'), findsWidgets);
      expect(
        find.textContaining('Requires Gathering Beginner 10'),
        findsNothing,
      );
      expect(
        find.descendant(
          of: details,
          matching: find.text('Insectivore Plant Powder'),
        ),
        findsOneWidget,
      );
      expect(find.text('Gather / Bare Hands or Hoe'), findsNothing);
      expect(find.text('Insectivore Plant Sap'), findsOneWidget);
      expect(find.text('Fluid collect / Fluid Collector'), findsNothing);
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-source-gameplay-note-field-source:insectivore-plant',
          ),
        ),
        findsOneWidget,
      );

      await selectMaterial(flower.name);
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, isEmpty);
      expect(find.text('Poisonous Swamp Plant'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey<String>(
            'resource-map-source-gameplay-note-'
            'field-source:poisonous-swamp-plant',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'characters far above the plant level may receive no '
          'Insectivore Plant Flower',
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: details,
          matching: find.text('Insectivore Plant Flower'),
        ),
        findsOneWidget,
      );
      expect(find.text('Defeat / Combat'), findsNothing);
      expect(
        find.textContaining('no reliable exact map positions'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('source filter constrains search and survives navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final workerOnly = dataset.resources.firstWhere(
      (resource) =>
          dataset.hasWorkerSource(resource.id) &&
          !dataset.hasMappedManualSource(resource.id),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    Finder resultFor(BdoResourceDefinition resource) => find.byWidgetPredicate(
      (widget) =>
          widget is ListTile &&
          widget.title is Text &&
          (widget.title! as Text).data == resource.name,
    );
    Semantics commandSemantics(String mode) => tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(ValueKey<String>('resource-map-command-$mode')),
            matching: find.byType(Semantics),
          )
          .first,
    );

    await _openGatherHub(tester);
    await tester.enterText(find.byType(TextField), workerOnly.name);
    await tester.pumpAndSettle();
    expect(resultFor(workerOnly), findsNothing);
    expect(commandSemantics('gather').properties.selected, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), workerOnly.name);
    await tester.pumpAndSettle();
    expect(resultFor(workerOnly), findsOneWidget);
    expect(commandSemantics('workers').properties.selected, isTrue);

    await tester.tap(resultFor(workerOnly));
    await tester.pump();
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isNotEmpty);
    expect(canvas.gatheringPoints, isEmpty);
    expect(canvas.gatheringSpots, isEmpty);
    expect(canvas.gatheringRoutes, isEmpty);
    expect(commandSemantics('workers').properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker output artwork appears only above its zoom threshold', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final resource = dataset.resources.firstWhere((candidate) {
      final nodes = dataset.workerNodesForResource(candidate.id);
      return nodes.length == 1 && nodes.single.isResourceNode;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
          nodeNetworkPreferences: BdoNodeNetworkPreferences(
            showAllMapNodes: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), resource.name);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title! as Text).data == resource.name,
      ),
    );
    await tester.pump();

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, hasLength(1));
    final node = canvas.workerNodes.single;
    final marker = find.byKey(
      ValueKey<String>('resource-map-worker-output-${node.id}'),
    );
    final viewport = tester.getSize(find.byType(BdoMapCanvas));

    canvas.cameraController.setCamera(
      BdoMapCamera(center: node.location.mapPoint, zoom: 2.15),
      viewport,
    );
    await tester.pump();
    expect(marker, findsNothing);

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    canvas.cameraController.setCamera(
      BdoMapCamera(center: node.location.mapPoint, zoom: 2.25),
      viewport,
    );
    await tester.pump();
    expect(marker, findsOneWidget);
    final retainedMarker = tester.widget(marker);
    final markerTopLeftBeforePan = tester.getTopLeft(marker);
    canvas.cameraController.panBy(const Offset(36, 18), viewport);
    await tester.pump();
    expect(
      tester.widget(marker),
      same(retainedMarker),
      reason:
          'A pure pan must translate retained output artwork, not rebuild it.',
    );
    final markerTopLeftAfterPan = tester.getTopLeft(marker);
    expect(
      markerTopLeftAfterPan.dx - markerTopLeftBeforePan.dx,
      closeTo(36, .01),
    );
    expect(
      markerTopLeftAfterPan.dy - markerTopLeftBeforePan.dy,
      closeTo(18, .01),
    );
    expect(
      find.descendant(
        of: marker,
        matching: find.byKey(
          const ValueKey<String>('resource-map-missing-worker-output-artwork'),
        ),
      ),
      findsOneWidget,
      reason:
          'A missing exact item-artwork builder must use a neutral indicator, '
          'not the node activity or resource category.',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-layer-menu-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-layer-worker-outputs')),
    );
    await tester.pumpAndSettle();
    expect(marker, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'worker output bars use their exact-artwork builder instead of category art',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final resource = dataset.resources.firstWhere((candidate) {
        final nodes = dataset.workerNodesForResource(candidate.id);
        return nodes.length == 1 && nodes.single.isResourceNode;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              showAllMapNodes: true,
            ),
            resourceIconBuilder: (context, resource, size) => ColoredBox(
              key: ValueKey<String>('generic-category-${resource.id}'),
              color: const Color(0xFFCC8844),
            ),
            workerOutputIconBuilder: (context, resource, size) => ColoredBox(
              key: ValueKey<String>('exact-output-${resource.id}'),
              color: const Color(0xFF4488CC),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), resource.name);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.title is Text &&
              (widget.title! as Text).data == resource.name,
        ),
      );
      await tester.pump();

      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final node = canvas.workerNodes.single;
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: node.location.mapPoint, zoom: 3),
        viewport,
      );
      await tester.pump();

      final marker = find.byKey(
        ValueKey<String>('resource-map-worker-output-${node.id}'),
      );
      expect(marker, findsOneWidget);
      expect(
        find.descendant(
          of: marker,
          matching: find.byKey(ValueKey<String>('exact-output-${resource.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: marker,
          matching: find.byKey(
            ValueKey<String>('generic-category-${resource.id}'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: marker,
          matching: find.byWidgetPredicate((widget) {
            if (widget case DecoratedBox(:final decoration)) {
              return decoration is BoxDecoration && decoration.border != null;
            }
            return false;
          }),
        ),
        findsNothing,
        reason:
            'Exact item art already owns its frame; the map must not draw '
            'another border around it.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker output artwork is deterministically culled before markers overlap',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _openWorkerNetwork(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-worker-activity-all')),
      );
      await tester.pumpAndSettle();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final resourceNodes = canvas.workerNodes
          .where((node) => node.outputs.isNotEmpty)
          .toList(growable: false);
      final anchor = resourceNodes.reduce((best, candidate) {
        int nearbyCount(BdoWorkerNode node) => resourceNodes
            .where(
              (other) =>
                  math.sqrt(
                    math.pow(
                          other.location.mapPoint.x - node.location.mapPoint.x,
                          2,
                        ) +
                        math.pow(
                          other.location.mapPoint.y - node.location.mapPoint.y,
                          2,
                        ),
                  ) <
                  125000,
            )
            .length;
        final bestCount = nearbyCount(best);
        final candidateCount = nearbyCount(candidate);
        return candidateCount > bestCount ||
                (candidateCount == bestCount &&
                    candidate.id.compareTo(best.id) < 0)
            ? candidate
            : best;
      });
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: anchor.location.mapPoint, zoom: 4.9),
        viewport,
      );
      await tester.pump();

      final outputMarkers = find.byWidgetPredicate(
        (widget) =>
            widget is Positioned &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'resource-map-worker-output-',
            ),
      );
      expect(outputMarkers, findsAtLeastNWidgets(3));
      final markerKeys = outputMarkers
          .evaluate()
          .map((element) => element.widget.key! as ValueKey<String>)
          .toList(growable: false);
      final firstRects = <Rect>[
        for (final key in markerKeys) tester.getRect(find.byKey(key)),
      ];
      for (var index = 0; index < firstRects.length; index += 1) {
        for (var other = index + 1; other < firstRects.length; other += 1) {
          expect(
            firstRects[index].inflate(3).overlaps(firstRects[other]),
            isFalse,
            reason:
                '${markerKeys[index].value} overlaps '
                '${markerKeys[other].value}',
          );
        }
      }

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: anchor.location.mapPoint, zoom: 4.9),
        viewport,
      );
      await tester.pump();
      final repeatedKeys = outputMarkers
          .evaluate()
          .map((element) => element.widget.key! as ValueKey<String>)
          .toList(growable: false);
      final repeatedRects = <Rect>[
        for (final key in repeatedKeys) tester.getRect(find.byKey(key)),
      ];
      expect(repeatedKeys, markerKeys);
      expect(repeatedRects, firstRects);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail links keep a one-step worker navigation history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _openWorkerNetwork(tester);
    final miningActivity = find.byKey(
      const ValueKey<String>('resource-map-worker-activity-mining'),
    );
    await tester.scrollUntilVisible(
      miningActivity,
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-worker-explorer')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(miningActivity);
    await tester.pumpAndSettle();

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final viewport = tester.getSize(find.byType(BdoMapCanvas));
    final node = canvas.workerNodes.firstWhere(
      (entry) => entry.outputs.isNotEmpty && entry.parentId != null,
    );
    final originalCamera = canvas.cameraController.camera;
    canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: node.id));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        matching: find.byType(Scrollbar),
      ),
      findsNothing,
    );
    final connectedFrom = find.byKey(
      ValueKey<String>('resource-map-node-connected-from-${node.parentId}'),
    );
    expect(connectedFrom, findsOneWidget);
    await tester.ensureVisible(connectedFrom);
    await tester.pump();
    await tester.tap(connectedFrom);
    await tester.pumpAndSettle();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedNodeId, node.parentId);
    expect(canvas.cameraController.camera, originalCamera);

    canvas.cameraController.panBy(const Offset(-64, 36), viewport);
    await tester.pump();
    final userAdjustedCamera = canvas.cameraController.camera;
    expect(userAdjustedCamera, isNot(originalCamera));

    final quickBack = find.byKey(
      const ValueKey<String>('resource-map-node-quick-back'),
    );
    expect(quickBack, findsOneWidget);
    await tester.tap(quickBack);
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedNodeId, node.id);
    final restoredCamera = canvas.cameraController.camera;
    expect(restoredCamera.zoom, closeTo(originalCamera.zoom, 0.000001));
    expect(restoredCamera.center.x, closeTo(originalCamera.center.x, 0.001));
    expect(restoredCamera.center.y, closeTo(originalCamera.center.y, 0.001));
    expect(quickBack, findsOneWidget);

    await tester.tap(quickBack);
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedNodeId, isNull);
    expect(
      canvas.workerNodes.every(
        (entry) => entry.activity == BdoWorkerActivity.mining,
      ),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-navigation-path')),
      findsNothing,
    );

    canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: node.id));
    await tester.pumpAndSettle();
    await tester.tap(connectedFrom);
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedNodeId, node.parentId);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-panel-close')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedNodeId, isNull);
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsNothing,
    );
    expect(quickBack, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('material search and no-result recovery use the real map flows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Snake Meat');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Snake Meat'),
      ),
    );
    await tester.pump();
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Snake Meat',
    );
    expect(canvas.gatheringPoints, hasLength(657));
    expect(canvas.gatheringSpots, hasLength(1));
    expect(find.text('Exact locations'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'not-a-real-bdo-resource');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No results for "not-a-real-bdo-resource"'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Worker nodes'));
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    expect(find.textContaining('map stays clear'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-picker')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-all')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.workerNodes,
      hasLength(
        dataset.workerNodes.where((node) => node.isResourceNode).length,
      ),
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(
              const ValueKey<String>('resource-map-worker-activity-all'),
            ),
          )
          .color,
      ResourceMapAtlasColors.primary,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'worker material search stays open while matching nodes breathe and compare',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final rice = dataset.resources.singleWhere(
        (resource) => resource.name == 'Rice',
      );
      final riceNodes = dataset.workerNodesForResource(rice.id).toList();
      expect(riceNodes.length, greaterThanOrEqualTo(2));

      await tester.enterText(find.byType(TextField), 'Rice');
      await tester.pump();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final riceNodeIds = riceNodes.map((node) => node.id).toSet();
      expect(canvas.emphasizedNodeIds, riceNodeIds);
      expect(
        canvas.workerNodes.map((node) => node.id),
        containsAll(riceNodeIds),
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsOneWidget,
      );

      canvas.cameraController.setCamera(
        const BdoMapCamera(center: BdoMapPoint(913000, 618000), zoom: 3.75),
        tester.getSize(find.byType(BdoMapCanvas)),
      );
      final comparisonCamera = canvas.cameraController.camera;

      BdoMapSearchEmphasisPainter currentEmphasisPainter() => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(BdoMapCanvas),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<BdoMapSearchEmphasisPainter>()
          .single;

      final initialPulse = currentEmphasisPainter().pulse;
      await tester.pump(const Duration(milliseconds: 450));
      expect(currentEmphasisPainter().pulse, isNot(initialPulse));
      expect(
        find.byKey(const ValueKey<String>('bdo-map-search-emphasis-boundary')),
        findsOneWidget,
        reason: 'The breathing rings must have their own repaint boundary.',
      );

      final firstNode = riceNodes.first;
      final firstResult = find.byKey(
        ValueKey<String>(
          'resource-map-search-result-workerNode-${firstNode.id}',
        ),
      );
      expect(firstResult, findsOneWidget);
      await tester.tap(firstResult);
      await tester.pump();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedNodeId, firstNode.id);
      expect(canvas.cameraController.camera, comparisonCamera);
      expect(canvas.emphasizedNodeIds, riceNodeIds);
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-node-quick-panel-tail'),
        ),
        findsNothing,
      );
      expect(tester.widget<ListTile>(firstResult).selected, isTrue);

      final secondNode = riceNodes[1];
      final secondResult = find.byKey(
        ValueKey<String>(
          'resource-map-search-result-workerNode-${secondNode.id}',
        ),
      );
      expect(secondResult, findsOneWidget);
      await tester.ensureVisible(secondResult);
      await tester.tap(secondResult);
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedNodeId, secondNode.id);
      expect(canvas.cameraController.camera, comparisonCamera);
      expect(canvas.emphasizedNodeIds, riceNodeIds);
      expect(tester.widget<ListTile>(secondResult).selected, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-node-panel-close')),
      );
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedNodeId, isNull);
      expect(canvas.emphasizedNodeIds, riceNodeIds);
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsOneWidget,
      );

      canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: firstNode.id));
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedNodeId, firstNode.id);
      expect(canvas.emphasizedNodeIds, containsAll(riceNodeIds));
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsOneWidget,
        reason: 'Selecting the pulsing marker must keep its result list open.',
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('worker search pulse becomes a static halo for reduced motion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'Rice');
    await tester.pump();

    BdoMapSearchEmphasisPainter currentPainter() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(BdoMapCanvas),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<BdoMapSearchEmphasisPainter>()
        .single;

    final staticPulse = currentPainter().pulse;
    expect(staticPulse, greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
    expect(currentPainter().pulse, staticPulse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker search highlights only the matching source product', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final pineSap = dataset.resources.singleWhere(
      (resource) => resource.name == 'Pine Sap',
    );
    final pineTimber = dataset.resources.singleWhere(
      (resource) => resource.name == 'Pine Timber',
    );
    final sapNodeIds = dataset
        .workerNodesForResource(pineSap.id)
        .map((node) => node.id)
        .toSet();
    final timberOnlyNodeIds = dataset
        .workerNodesForResource(pineTimber.id)
        .map((node) => node.id)
        .where((nodeId) => !sapNodeIds.contains(nodeId))
        .toSet();
    expect(sapNodeIds, isNotEmpty);
    expect(timberOnlyNodeIds, isNotEmpty);

    await tester.enterText(find.byType(TextField), 'Pine Sap');
    await tester.pump();
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.emphasizedNodeIds, sapNodeIds);
    expect(canvas.emphasizedNodeIds, isNot(containsAll(timberOnlyNodeIds)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a worker search closes details that no longer match', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'Rice');
    await tester.pump();

    final rice = dataset.resources.singleWhere(
      (resource) => resource.name == 'Rice',
    );
    final riceNode = dataset.workerNodesForResource(rice.id).first;
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'resource-map-search-result-workerNode-${riceNode.id}',
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Pine Sap');
    await tester.pump();
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedNodeId, isNull);
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'worker material comparison uses fragmented results and anchored details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Rice');
      await tester.pump();

      final rice = dataset.resources.singleWhere(
        (resource) => resource.name == 'Rice',
      );
      final firstNode = dataset.workerNodesForResource(rice.id).first;
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'resource-map-search-result-workerNode-${firstNode.id}',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      await _settleVisibleGoldenImages(
        tester,
        root: find.byType(BdoResourceMap),
      );
      await expectLater(
        find.byType(BdoResourceMap),
        matchesGoldenFile('goldens/resource_map_worker_search_compare.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker activity filtering and details preserve the worker context',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await _openWorkerNetwork(tester);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-worker-activity-picker'),
        ),
        findsOneWidget,
      );
      final miningActivity = find.byKey(
        const ValueKey<String>('resource-map-worker-activity-mining'),
      );
      await tester.scrollUntilVisible(
        miningActivity,
        120,
        scrollable: find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-worker-explorer'),
          ),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(miningActivity);
      await tester.pumpAndSettle();
      final miningCount = dataset.workerNodes
          .where(
            (node) =>
                node.isResourceNode &&
                node.activity == BdoWorkerActivity.mining,
          )
          .length;
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.workerNodes, hasLength(miningCount));
      expect(
        canvas.workerNodes.every(
          (node) => node.activity == BdoWorkerActivity.mining,
        ),
        isTrue,
      );
      expect(
        tester
            .widget<Material>(
              find.byKey(
                const ValueKey<String>('resource-map-worker-activity-mining'),
              ),
            )
            .color,
        ResourceMapAtlasColors.primary,
      );
      expect(
        tester
            .widget<Material>(
              find.byKey(
                const ValueKey<String>('resource-map-worker-activity-all'),
              ),
            )
            .color,
        isNot(ResourceMapAtlasColors.primary),
      );

      final primalGiant = canvas.workerNodes.singleWhere(
        (node) => node.name == 'Primal Giant Post - Mining',
      );
      final cameraBeforeDetails = canvas.cameraController.camera;
      canvas.onHit(
        BdoMapHit(kind: BdoMapHitKind.workerNode, id: primalGiant.id),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('resource-map-node-quick-panel'),
          ),
          matching: find.textContaining('Mining'),
        ),
        findsWidgets,
      );
      expect(find.text('Primal Giant Post'), findsWidgets);
      expect(find.text('Primal Giant Post - Mining'), findsNothing);
      expect(find.text('Mine'), findsNothing);
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedNodeId, primalGiant.id);
      expect(canvas.workerNodes, hasLength(miningCount));
      expect(canvas.cameraController.camera.center, cameraBeforeDetails.center);
      expect(canvas.cameraController.camera.zoom, cameraBeforeDetails.zoom);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-node-panel-close')),
      );
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedNodeId, isNull);
      expect(canvas.workerNodes, hasLength(miningCount));
      expect(
        canvas.workerNodes.every(
          (node) => node.activity == BdoWorkerActivity.mining,
        ),
        isTrue,
      );
      expect(canvas.cameraController.camera.center, cameraBeforeDetails.center);
      expect(canvas.cameraController.camera.zoom, cameraBeforeDetails.zoom);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map status stays compact and reveals accessible controls on demand',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              showSourceNotice: false,
              tileHttpClient: tileClient,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final toggle = find.byKey(
        const ValueKey<String>('resource-map-status-toggle'),
      );
      final animation = find.byKey(
        const ValueKey<String>('resource-map-status-animation'),
      );
      expect(toggle, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-status-details')),
        findsNothing,
      );
      expect(find.byTooltip('Map source and fan-content notice'), findsNothing);
      expect(
        find.descendant(of: animation, matching: find.byType(AnimatedSize)),
        findsNothing,
        reason: 'Reduced motion swaps status states without a size animation.',
      );
      expect(tester.widget<Semantics>(toggle).properties.toggled, isFalse);
      expect(
        tester.widget<Semantics>(toggle).properties.label,
        startsWith('Map status:'),
      );
      final collapsedWidth = tester.getSize(toggle).width;
      expect(collapsedWidth, 48);

      await tester.tap(toggle);
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('resource-map-status-details')),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Map source and fan-content notice'),
        findsOneWidget,
      );
      expect(find.byTooltip('Use cached tiles only'), findsOneWidget);
      expect(tester.widget<Semantics>(toggle).properties.toggled, isTrue);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey<String>('resource-map-status-details')),
            )
            .width,
        greaterThan(collapsedWidth),
      );

      await tester.tap(toggle);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-status-details')),
        findsNothing,
      );
      expect(tester.widget<Semantics>(toggle).properties.toggled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact map remains usable at 200 percent text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(680, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(760, 620),
            textScaler: TextScaler.linear(2),
          ),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.byType(BdoResourceMap), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
      'Find a material or place',
    );
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringSpots, isEmpty);
    expect(canvas.gatheringPoints, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-compact-worker-network')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-compact-worker-explorer'),
      ),
      findsOneWidget,
    );
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-all')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.workerNodes,
      hasLength(
        dataset.workerNodes.where((node) => node.isResourceNode).length,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-compact-worker-back')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.workerNodes,
      isEmpty,
      reason: 'One-step Back returns from All nodes to the activity picker.',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-compact-worker-back')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sheep Hide');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title! as Text).data == 'Sheep Hide',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Historical exact locations'), findsNothing);
    expect(find.textContaining('historical recorded dots'), findsNothing);
    final compactZoomRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-zoom-controls')),
    );
    final compactDetailsRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-details-card')),
    );
    expect(compactZoomRect.overlaps(compactDetailsRect), isFalse);
    expect(compactZoomRect.bottom, lessThan(compactDetailsRect.top));
    expect(tester.takeException(), isNull);

    expect(find.byTooltip('Map source and fan-content notice'), findsNothing);
    final statusAnimatedSize = find.descendant(
      of: find.byKey(const ValueKey<String>('resource-map-status-animation')),
      matching: find.byType(AnimatedSize),
    );
    expect(statusAnimatedSize, findsOneWidget);
    expect(
      tester.widget<AnimatedSize>(statusAnimatedSize).duration,
      const Duration(milliseconds: 180),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-status-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Map source and fan-content notice'));
    await tester.pump();
    expect(find.text('Map source and usage'), findsOneWidget);
    expect(find.textContaining('Downloaded map tiles:'), findsOneWidget);
    final sourceTitle = find.text('Map source and usage');
    final sourceTitleBefore = tester.getCenter(sourceTitle);
    await tester.drag(
      find.byKey(
        const ValueKey<String>('resource-map-source-notice-drag-handle'),
      ),
      const Offset(90, 40),
    );
    await tester.pump();
    expect(tester.getCenter(sourceTitle), isNot(sourceTitleBefore));
    expect(tester.takeException(), isNull);

    final clearCache = find.byKey(
      const ValueKey<String>('resource-map-clear-cache'),
    );
    await tester.ensureVisible(clearCache);
    await tester.tap(clearCache);
    await tester.pump();
    expect(find.textContaining('Clearing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact Tshira fit keeps the selected species readable beside details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(680, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), 'Snake Meat');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.title is Text &&
              (widget.title! as Text).data == 'Snake Meat',
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final canvasFinder = find.byType(BdoMapCanvas);
      final canvas = tester.widget<BdoMapCanvas>(canvasFinder);
      final viewport = tester.getSize(canvasFinder);
      expect(viewport, const Size(680, 620));
      final tshiraSnakePoints = canvas.gatheringPoints
          .where(
            (point) =>
                point.areaId == 'gathering:tshira-snake-scorpion-rotation' &&
                point.resourceIds.contains('item:7922'),
          )
          .toList(growable: false);
      expect(tshiraSnakePoints, hasLength(21));
      final screenYs = tshiraSnakePoints
          .map(
            (point) => canvas.cameraController
                .worldToScreen(point.location.mapPoint, viewport)
                .dy,
          )
          .toList(growable: false);
      final verticalSpread =
          screenYs.reduce(math.max) - screenYs.reduce(math.min);
      expect(canvas.cameraController.camera.zoom, greaterThan(7));
      expect(
        verticalSpread,
        greaterThanOrEqualTo(108),
        reason:
            'The compact details card must not collapse the selected Tshira '
            'species into a tiny or effectively one-pixel fit band.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'child detail dismissal returns to its material until explicitly cleared',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Snake Meat');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Snake Meat'),
        ),
      );
      await tester.pump();

      void openFirstPoint() {
        final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
        final point = canvas.gatheringPoints.first;
        canvas.onHit(
          BdoMapHit(kind: BdoMapHitKind.gatheringPoint, id: point.id),
        );
      }

      void expectParentMaterial() {
        final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
        expect(canvas.selectedPointId, isNull);
        expect(canvas.selectedSpotId, isNull);
        expect(canvas.gatheringPoints, hasLength(657));
        expect(canvas.gatheringSpots, hasLength(1));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Snake Meat',
        );
        expect(
          find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
          findsOneWidget,
        );
        expect(find.text('Exact locations'), findsNothing);
      }

      openFirstPoint();
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
        findsOneWidget,
      );
      expect(find.text('Back to Snake'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pump();
      expectParentMaterial();

      openFirstPoint();
      await tester.pump();
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      canvas.onEmptyTap!.call();
      await tester.pump();
      expectParentMaterial();

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, hasLength(657));
      expect(canvas.gatheringSpots, hasLength(1));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-close')),
      );
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, isEmpty);
      expect(canvas.gatheringSpots, isEmpty);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-desktop-sidebar-hidden'),
        ),
        findsOneWidget,
        reason: 'Clearing the final selection should restore the full map.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual gathering dots open honest details without moving the map',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), 'Snake Meat');
      await tester.pumpAndSettle();
      final snakeResult = find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Snake Meat'),
      );
      await tester.tap(snakeResult);
      await tester.pump();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, isNotEmpty);
      expect(
        canvas.gatheringPoints.every(
          (point) => point.resourceIds.contains('item:7922'),
        ),
        isTrue,
      );
      final point = canvas.gatheringPoints.first;
      final cameraBeforeClick = canvas.cameraController.camera;

      canvas.onHit(BdoMapHit(kind: BdoMapHitKind.gatheringPoint, id: point.id));
      await tester.pump();

      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedPointId, point.id);
      expect(canvas.gatheringPoints, hasLength(657));
      expect(
        canvas.gatheringPoints.map((entry) => entry.id),
        contains(point.id),
      );
      expect(canvas.cameraController.camera.center, cameraBeforeClick.center);
      expect(canvas.cameraController.camera.zoom, cameraBeforeClick.zoom);
      expect(find.text('EXACT GATHERING LOCATION'), findsOneWidget);
      expect(find.text(point.label), findsOneWidget);
      expect(find.text('Needs re-verification'), findsOneWidget);

      canvas.onEmptyTap!.call();
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedPointId, isNull);
      expect(canvas.gatheringPoints, hasLength(657));
      expect(find.byType(TextField).evaluate().single.widget, isA<TextField>());
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Snake Meat',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a visible historical cluster zooms through real hit testing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Sheep Hide');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.title is Text &&
              (widget.title! as Text).data == 'Sheep Hide',
        ),
      ),
    );
    await tester.pump();

    final canvasFinder = find.byType(BdoMapCanvas);
    var canvas = tester.widget<BdoMapCanvas>(canvasFinder);
    expect(canvas.cameraController.camera.zoom, lessThan(4.15));
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: canvasFinder,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter is BdoMapPainter,
                    ),
                  ),
                )
                .painter!
            as BdoMapPainter;
    final layout = painter.overlayLayout!;
    expect(layout.cameraController.camera, canvas.cameraController.camera);
    final unobscuredClusters = layout.gatheringPointClusters.where(
      (cluster) =>
          cluster.position.dx > 460 &&
          cluster.position.dx < 800 &&
          cluster.position.dy > 90 &&
          cluster.position.dy < 650,
    );
    expect(unobscuredClusters, isNotEmpty);
    final cluster = unobscuredClusters.first;
    expect(
      layout.hitTest(cluster.position)!.hit.kind,
      BdoMapHitKind.gatheringPointCluster,
    );
    final cameraBeforeTap = canvas.cameraController.camera;

    await tester.tapAt(tester.getTopLeft(canvasFinder) + cluster.position);
    await tester.pump(const Duration(milliseconds: 400));

    canvas = tester.widget<BdoMapCanvas>(canvasFinder);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Sheep Hide',
      reason: 'the painted overview mark must resolve to a map hit',
    );
    expect(canvas.gatheringPoints, isNotEmpty);
    expect(canvas.selectedSpotId, isNull);
    expect(
      canvas.cameraController.camera.zoom,
      greaterThan(cameraBeforeTap.zoom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Edania keeps worker data without a fabricated Golden Leaf circle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), 'Purified Water');
      await tester.pumpAndSettle();
      final waterResult = find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Purified Water'),
      );
      expect(waterResult, findsOneWidget);
      await tester.tap(waterResult);
      await tester.pump();

      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.workerNodes.map((node) => node.id), contains('2054'));

      await tester.enterText(find.byType(TextField), 'Golden Leaf Snake');
      await tester.pumpAndSettle();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        find.text('Zephyros Golden Leaf Snake Zone (Approx.)'),
        findsNothing,
      );
      expect(dataset.gatheringSpots, hasLength(3));
      expect(
        dataset.gatheringSpots.every((spot) => spot.radiusWorld == null),
        isTrue,
      );
      expect(canvas.gatheringSpots, isEmpty);
      expect(find.text('Caphras Essence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('material source filters include routes contextually', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const resourceId = 'item:4616';
    final thujaPoints = dataset
        .gatheringPointsForResource(resourceId)
        .take(2)
        .toList(growable: false);
    final route = BdoGatheringRoute(
      id: 'test:thuja-route',
      spotId: 'test:thuja-area',
      name: 'Test Thuja Route',
      region: 'Kamasylvia',
      resourceIds: const <String>[resourceId],
      tool: 'Fluid Collector',
      loop: false,
      summary: 'A test-only route used to exercise display state.',
      waypoints: <BdoGatheringWaypoint>[
        BdoGatheringWaypoint(
          order: 1,
          location: thujaPoints.first.location,
          kind: 'gathering',
          label: 'Start',
          targets: const <String>['Thuja Tree'],
        ),
        BdoGatheringWaypoint(
          order: 2,
          location: thujaPoints.last.location,
          kind: 'gathering',
          label: 'Finish',
          targets: const <String>['Thuja Tree'],
        ),
      ],
      verification: BdoGatheringVerification.stale,
      provenanceId: thujaPoints.first.provenanceId,
    );
    final routeDataset = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: dataset.resources,
      workerNodes: dataset.workerNodes,
      gatheringSpots: dataset.gatheringSpots,
      gatheringPoints: dataset.gatheringPoints,
      gatheringRoutes: <BdoGatheringRoute>[route],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: routeDataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> selectThujaTimber() async {
      await tester.enterText(find.byType(TextField), 'Thuja Timber');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
          matching: find.descendant(
            of: find.byType(ListTile),
            matching: find.text('Thuja Timber'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await selectThujaTimber();

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringRoutes, <BdoGatheringRoute>[route]);
    expect(
      find.byKey(const ValueKey<String>('resource-map-material-source-filter')),
      findsNothing,
      reason: 'Desktop source mode is selected by the top-level task buttons.',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-workers')),
    );
    await tester.pumpAndSettle();
    await selectThujaTimber();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringRoutes, isEmpty);
    expect(canvas.workerNodes, isNotEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-command-gather')),
    );
    await tester.pumpAndSettle();
    await selectThujaTimber();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringRoutes, <BdoGatheringRoute>[route]);
    expect(canvas.workerNodes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing tile providers immediately primes the new engine', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient(
      (request) async => http.Response.bytes(tilePng, HttpStatus.ok),
    );
    addTearDown(client.close);
    BdoTileSource source(String id, String host) => BdoTileSource(
      id: id,
      displayName: id,
      urlTemplate: 'https://$host/{z}/{x}_{y}.png',
      worldBounds: BdoTileSource.workermanCommunity.worldBounds,
      attribution: 'Generated test fixture',
      usageNotice: 'Only used by automated tests.',
      minimumZoom: 0,
      maximumZoom: 7,
      fileExtension: 'png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: source('provider-a', 'a.example.test'),
          tileHttpClient: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final firstManager = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .tileManager;
    expect(firstManager.source.id, 'provider-a');
    expect(firstManager.visibleCoordinates, isNotEmpty);
    expect(
      tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .cameraController
          .camera
          .zoom,
      greaterThanOrEqualTo(0),
    );

    await tester.enterText(find.byType(TextField), 'Snake Meat');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Snake Meat'),
      ),
    );
    await tester.pump();
    final resourceCamera = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .cameraController
        .camera;

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: source('provider-b', 'b.example.test'),
          tileHttpClient: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final secondManager = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .tileManager;
    expect(secondManager, isNot(same(firstManager)));
    expect(secondManager.source.id, 'provider-b');
    expect(secondManager.visibleCoordinates, isNotEmpty);
    final replacementCanvas = tester.widget<BdoMapCanvas>(
      find.byType(BdoMapCanvas),
    );
    expect(replacementCanvas.gatheringPoints, isNotEmpty);
    expect(
      replacementCanvas.cameraController.camera.center.x,
      closeTo(resourceCamera.center.x, 0.001),
    );
    expect(
      replacementCanvas.cameraController.camera.center.y,
      closeTo(resourceCamera.center.y, 0.001),
    );
    expect(
      replacementCanvas.cameraController.camera.zoom,
      closeTo(resourceCamera.zoom, 0.001),
      reason: 'A replacement engine should refit the existing viewport.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('source notice traps focus and closes with Escape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.focusNode!.hasFocus, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-status-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Map source and fan-content notice'));
    await tester.pump();

    expect(find.text('Map source and usage'), findsOneWidget);
    expect(searchField.focusNode!.hasFocus, isFalse);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('Map source and usage'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Snake Meat uses exact dots and a radius-free Tshira focus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    const resourceName = 'Snake Meat';
    await tester.enterText(find.byType(TextField), resourceName);
    await tester.pumpAndSettle();
    final resourceResult = find.descendant(
      of: find.byType(ListTile),
      matching: find.text(resourceName),
    );
    expect(resourceResult, findsOneWidget);
    await tester.tap(resourceResult);
    await tester.pump();

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringPoints, hasLength(657));
    expect(canvas.gatheringSpots, hasLength(1));
    expect(canvas.gatheringSpots.single.radiusWorld, isNull);
    final point = canvas.gatheringPoints.first;
    canvas.onHit(BdoMapHit(kind: BdoMapHitKind.gatheringPoint, id: point.id));
    await tester.pump();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.selectedPointId, point.id);
    expect(
      canvas.gatheringPoints,
      hasLength(657),
      reason: 'Selecting one exact dot must keep sibling locations visible.',
    );
    expect(canvas.gatheringSpots, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape and an empty map tap dismiss search results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Snake Meat');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Snake Meat',
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
      findsOneWidget,
    );

    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    canvas.onEmptyTap!.call();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
      findsNothing,
    );
    expect(canvas.onEmptyTap, isNotNull);

    await tester.tap(find.byTooltip('Show the full world'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Snake Meat',
      reason: 'The world-view control changes only the camera, not navigation.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search results collapse left without losing the query', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Snake Meat');
    await tester.pump();
    final results = find.byKey(
      const ValueKey<String>('resource-map-sidebar-search'),
    );
    expect(results.hitTestable(), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-desktop-search-collapse'),
      ),
    );
    await tester.pump();

    expect(results, findsOneWidget, reason: 'Search state stays mounted.');
    expect(results.hitTestable(), findsNothing);
    expect(
      tester.widget<TextField>(searchField).controller!.text,
      'Snake Meat',
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-desktop-task-surface-restore'),
      ),
    );
    await tester.pump();

    expect(results.hitTestable(), findsOneWidget);
    expect(
      tester.widget<TextField>(searchField).controller!.text,
      'Snake Meat',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker paths add parents without replacing the activity view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await _openWorkerNetwork(tester);
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-all')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final resourceNodeCount = dataset.workerNodes
        .where((node) => node.isResourceNode)
        .length;
    expect(canvas.workerNodes, hasLength(resourceNodeCount));
    expect(canvas.showConnections, isFalse);

    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-picker')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(
              const ValueKey<String>('resource-map-worker-activity-all'),
            ),
          )
          .color,
      ResourceMapAtlasColors.primary,
    );

    final firstNode = canvas.workerNodes.firstWhere(
      (node) => node.parentId != null,
    );
    canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: firstNode.id));
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.workerNodes,
      hasLength(resourceNodeCount),
      reason: 'inspecting one node must preserve the browse overview',
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );

    final quickPanel = find.byKey(
      const ValueKey<String>('resource-map-node-quick-panel'),
    );
    final pathToggle = find.descendant(
      of: quickPanel,
      matching: find.byKey(
        const ValueKey<String>('resource-map-worker-path-toggle'),
      ),
    );
    await tester.scrollUntilVisible(
      pathToggle,
      150,
      scrollable: find
          .descendant(of: quickPanel, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(pathToggle);
    await tester.pump();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.showConnections, isTrue);
    expect(canvas.workerNodes.length, greaterThan(resourceNodeCount));
    expect(canvas.workerNodes.any((node) => !node.isResourceNode), isTrue);

    await tester.tap(pathToggle);
    await tester.pump();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.showConnections, isFalse);
    expect(canvas.workerNodes, hasLength(resourceNodeCount));
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-picker')),
      findsNothing,
    );

    await tester.enterText(find.byType(TextField), 'Potato');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title! as Text).data == 'Potato',
      ),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.workerNodes.map((node) => node.id).toSet(),
      dataset
          .workerNodesForResource('item:7003')
          .map((node) => node.id)
          .toSet(),
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-picker')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a material chip exits worker browse and narrows the map', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await _openWorkerNetwork(tester);
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-all')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final node = canvas.workerNodes.firstWhere(
      (entry) => entry.outputs.isNotEmpty,
    );
    final output = node.outputs.first;

    canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: node.id));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );
    final materialRow = find.byKey(
      ValueKey<String>('resource-map-node-output-${output.resourceId}'),
    );
    expect(materialRow, findsOneWidget);

    await tester.tap(materialRow);
    await tester.pumpAndSettle();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(
      canvas.workerNodes.map((entry) => entry.id).toSet(),
      dataset
          .workerNodesForResource(output.resourceId)
          .map((entry) => entry.id)
          .toSet(),
    );
    expect(canvas.gatheringSpots, isEmpty);
    expect(canvas.gatheringPoints, isEmpty);
    expect(canvas.gatheringRoutes, isEmpty);
    final workerSourceSemantics = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('resource-map-command-workers'),
            ),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(workerSourceSemantics.properties.selected, isTrue);
    expect(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-picker')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
      findsOneWidget,
    );
    expect(find.text(output.name), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker cluster fitting uses the full map behind quick details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await _openWorkerNetwork(tester);
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.workerNodes, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-activity-all')),
    );
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final worldCenter = tileSource.worldBounds.center;
    final centralNodes = canvas.workerNodes.toList()
      ..sort(
        (a, b) => a.location.mapPoint
            .distanceTo(worldCenter)
            .compareTo(b.location.mapPoint.distanceTo(worldCenter)),
      );
    final clusterNodes = centralNodes.take(3).toList(growable: false);

    canvas.onHit(
      BdoMapHit(kind: BdoMapHitKind.workerNode, id: clusterNodes.first.id),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    canvas.onHit(
      BdoMapHit(
        kind: BdoMapHitKind.workerCluster,
        id: 'test-cluster',
        clusterNodeIds: clusterNodes.map((node) => node.id).toList(),
      ),
    );
    await tester.pump();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final viewport = tester.getSize(find.byType(BdoMapCanvas));
    final clusterPoints = clusterNodes
        .map((node) => node.location.mapPoint)
        .toList(growable: false);
    final left = clusterPoints.map((point) => point.x).reduce(math.min);
    final right = clusterPoints.map((point) => point.x).reduce(math.max);
    final top = clusterPoints.map((point) => point.y).reduce(math.min);
    final bottom = clusterPoints.map((point) => point.y).reduce(math.max);
    final clusterCenter = BdoMapPoint((left + right) / 2, (top + bottom) / 2);
    final fittedPosition = canvas.cameraController.worldToScreen(
      clusterCenter,
      viewport,
    );
    final expectedPosition = Offset(viewport.width / 2, viewport.height / 2);

    expect(fittedPosition.dx, closeTo(expectedPosition.dx, 1.5));
    expect(fittedPosition.dy, closeTo(expectedPosition.dy, 1.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas selection keeps the user camera in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final viewport = tester.getSize(find.byType(BdoMapCanvas));
    final easternNode = dataset.workerNodes
        .where((node) => node.isResourceNode)
        .reduce(
          (current, candidate) =>
              candidate.location.x > current.location.x ? candidate : current,
        );
    final before = canvas.cameraController.worldToScreen(
      easternNode.location.mapPoint,
      viewport,
    );
    final beforeCamera = canvas.cameraController.camera;
    expect(before.dx, greaterThan(viewport.width * 0.6));

    canvas.onHit(BdoMapHit(kind: BdoMapHitKind.workerNode, id: easternNode.id));
    await tester.pump();

    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final after = canvas.cameraController.worldToScreen(
      easternNode.location.mapPoint,
      viewport,
    );
    expect(canvas.selectedNodeId, easternNode.id);
    expect(canvas.workerNodes.map((node) => node.id), <String>[easternNode.id]);
    expect(canvas.cameraController.camera.center, beforeCamera.center);
    expect(canvas.cameraController.camera.zoom, beforeCamera.zoom);
    expect(after, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct landmark selection keeps the user camera in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final city = dataset.workerNodes.firstWhere(
      (node) => node.nodeType == 'City',
    );
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    canvas.cameraController.setCamera(
      BdoMapCamera(center: city.location.mapPoint, zoom: 4.5),
      tester.getSize(find.byType(BdoMapCanvas)),
    );
    await tester.pump();
    final marker = find.byKey(
      ValueKey<String>('resource-map-landmark-${city.id}'),
    );
    expect(marker, findsOneWidget);
    final beforeCamera = canvas.cameraController.camera;

    await tester.tap(
      find.descendant(of: marker, matching: find.byType(GestureDetector)).first,
      // The all-node layer can intentionally paint the same city above its
      // landmark label. Either surface opens the identical node details; the
      // retained-overlay test separately verifies the landmark hit transform.
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(canvas.cameraController.camera.center, beforeCamera.center);
    expect(canvas.cameraController.camera.zoom, beforeCamera.zoom);
    expect(find.text(city.siteName), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse wheel zoom passes through town landmarks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
          tileSource: tileSource,
          showSourceNotice: false,
          tileHttpClient: tileClient,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final city = dataset.workerNodes.firstWhere(
      (node) => node.nodeType == 'City',
    );
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    canvas.cameraController.setCamera(
      BdoMapCamera(center: city.location.mapPoint, zoom: 4.5),
      tester.getSize(find.byType(BdoMapCanvas)),
    );
    await tester.pump();
    final marker = find.byKey(
      ValueKey<String>('resource-map-landmark-${city.id}'),
    );
    expect(marker, findsOneWidget);
    final beforeZoom = canvas.cameraController.camera.zoom;

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(marker),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pump();

    expect(canvas.cameraController.camera.zoom, greaterThan(beforeZoom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Thuja Sap search resolves to one source with every product and method',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final resourceArtworkSizes = <({String name, double size})>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            resourceIconBuilder: (context, resource, size) {
              resourceArtworkSizes.add((name: resource.name, size: size));
              return const ColoredBox(color: Colors.teal);
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(
          const ValueKey<String>('resource-map-desktop-sidebar-hidden'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-command-gather')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
        'Find an item, source, node or town',
      );

      final thujaSource = dataset.fieldSourcesById['field-source:thuja-tree']!;
      final thujaSap = dataset.resources.singleWhere(
        (resource) => resource.name == 'Thuja Sap',
      );
      final workerCount = dataset.workerNodesForResource(thujaSap.id).length;
      expect(workerCount, greaterThan(0));

      Future<void> selectThujaSap() async {
        await tester.enterText(find.byType(TextField), 'Thuja Sap');
        await tester.pumpAndSettle();
        final result = find.descendant(
          of: find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ListTile &&
                widget.title is Text &&
                (widget.title! as Text).data == 'Thuja Sap',
          ),
        );
        expect(result, findsOneWidget);
        await tester.tap(result);
        await tester.pumpAndSettle();
      }

      await selectThujaSap();

      final details = find.byKey(
        const ValueKey<String>('resource-map-sidebar-details'),
      );
      expect(find.text('Thuja Tree'), findsWidgets);
      expect(find.text('Products & methods'), findsNothing);
      expect(
        find.descendant(of: details, matching: find.text('Thuja Sap')),
        findsOneWidget,
      );
      expect(find.text('Fluid collect / Fluid Collector'), findsNothing);
      expect(find.text('Thuja Timber'), findsOneWidget);
      expect(find.text('Lumber / Lumbering Axe'), findsNothing);
      expect(
        resourceArtworkSizes.any(
          (entry) => entry.name == 'Thuja Sap' && entry.size == 46,
        ),
        isTrue,
        reason: 'Gathering product artwork should use the available card room.',
      );
      final gatheringTools = find.descendant(
        of: details,
        matching: find.byType(BdoGatheringToolIcon),
      );
      expect(gatheringTools, findsWidgets);
      expect(tester.getSize(gatheringTools.first).height, 32);
      expect(
        find.byKey(
          ValueKey<String>(
            'resource-map-source-product-worker-nodes-${thujaSap.id}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-material-source-filter'),
        ),
        findsNothing,
        reason:
            'Desktop uses the always-visible Gather and Workers commands '
            'instead of another chooser inside details.',
      );
      var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final exactPointCount = canvas.gatheringPoints.length;
      expect(
        exactPointCount,
        dataset.gatheringPointsForFieldSource(thujaSource.id).length,
      );
      expect(canvas.workerNodes, isNotEmpty);
      expect(exactPointCount, greaterThan(1));

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-gather')),
      );
      await tester.pumpAndSettle();
      await selectThujaSap();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.workerNodes, isEmpty);
      expect(canvas.gatheringPoints, hasLength(exactPointCount));

      final selectedPoint = canvas.gatheringPoints.first;
      canvas.onHit(
        BdoMapHit(kind: BdoMapHitKind.gatheringPoint, id: selectedPoint.id),
      );
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.selectedPointId, selectedPoint.id);
      expect(canvas.gatheringPoints, hasLength(exactPointCount));

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pump();
      final workerAlternativesLink = find.byKey(
        ValueKey<String>(
          'resource-map-source-product-worker-nodes-${thujaSap.id}',
        ),
      );
      expect(workerAlternativesLink, findsOneWidget);
      await tester.ensureVisible(workerAlternativesLink);
      await tester.tap(workerAlternativesLink);
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.workerNodes.map((node) => node.id).toSet(),
        dataset
            .workerNodesForResource(thujaSap.id)
            .map((node) => node.id)
            .toSet(),
      );
      expect(canvas.emphasizedNodeIds, isNotEmpty);
      expect(canvas.gatheringPoints, hasLength(exactPointCount));
      final firstEmphasisRevision = canvas.emphasisRevision;
      await tester.tap(workerAlternativesLink);
      await tester.pump();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.emphasisRevision, firstEmphasisRevision + 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-gather')),
      );
      await tester.pumpAndSettle();
      await selectThujaSap();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(
        canvas.gatheringPoints,
        hasLength(exactPointCount),
        reason:
            'The Gather command must restore the exact manual source layer.',
      );
      expect(canvas.workerNodes, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      await selectThujaSap();
      canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.workerNodes, isNotEmpty);
      expect(canvas.gatheringPoints, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'planner shortlist keeps exact manual shortages and omits easy routes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final builtResourceIcons = <String>[];
      final needs = <BdoPlannerMaterialNeed>[
        BdoPlannerMaterialNeed(
          gameItemId: 7922,
          name: 'Legacy snake catalog name',
          missingQuantity: 24,
          marketable: true,
          stockKnown: true,
          stock: 0,
          marketRegion: 'eu',
          marketFetchedAt: DateTime.utc(2026, 7, 28),
        ),
        BdoPlannerMaterialNeed(
          name: 'Truffle Mushroom',
          missingQuantity: 10,
          marketable: true,
          stockKnown: true,
          stock: 5,
          marketRegion: 'na',
          marketFetchedAt: DateTime.utc(2026, 7, 27),
        ),
        BdoPlannerMaterialNeed(
          name: 'soft hide',
          missingQuantity: 40,
          marketable: false,
          stockKnown: false,
          stock: 0,
          marketRegion: 'asia',
          marketFetchedAt: DateTime.utc(2026, 7, 26),
        ),
        BdoPlannerMaterialNeed(
          name: "Monk's Branch",
          missingQuantity: 200,
          marketable: true,
          stockKnown: true,
          stock: 0,
          marketRegion: 'eu',
          marketFetchedAt: DateTime.utc(2026, 7, 28),
        ),
        BdoPlannerMaterialNeed(
          name: 'Thuja Sap',
          missingQuantity: 50,
          marketable: true,
          stockKnown: true,
          stock: 0,
          marketRegion: 'eu',
          marketFetchedAt: DateTime.utc(2026, 7, 28),
        ),
        BdoPlannerMaterialNeed(
          name: 'Silver Azalea',
          missingQuantity: 500,
          marketable: false,
          stockKnown: true,
          stock: 0,
          marketRegion: 'eu',
          marketFetchedAt: DateTime.utc(2026, 7, 28),
          vendorPurchaseAvailable: true,
        ),
        BdoPlannerMaterialNeed(
          name: "Rusalka's Coral",
          missingQuantity: 1,
          marketable: true,
          stockKnown: true,
          stock: 1,
          marketRegion: 'eu',
          marketFetchedAt: DateTime.utc(2026, 7, 28),
        ),
        const BdoPlannerMaterialNeed(
          name: 'Unmapped test material',
          missingQuantity: 1,
          marketable: true,
          stockKnown: false,
          stock: 0,
          marketRegion: '',
          marketFetchedAt: null,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
            plannerNeeds: needs,
            plannerContextLabel: 'Test craft plan',
            resourceIconBuilder: (context, resource, size) {
              builtResourceIcons.add(resource.id);
              return ColoredBox(
                key: ValueKey<String>('test-resource-icon-${resource.id}'),
                color: const Color(0xFF7BC79F),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _openGatherHub(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-gather-plan-shortlist'),
        ),
      );
      await tester.pumpAndSettle();

      final snakeRow = find.byKey(
        const ValueKey<String>('resource-map-plan-need-item:7922'),
      );
      final truffleRow = find.byKey(
        const ValueKey<String>('resource-map-plan-need-item:5420'),
      );
      final sheepRow = find.byKey(
        const ValueKey<String>('resource-map-plan-need-item:6002'),
      );
      final gatherScrollable = find
          .descendant(
            of: find.byKey(const ValueKey<String>('resource-map-gather-hub')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('NEEDED FOR YOUR PLAN'),
        140,
        scrollable: gatherScrollable,
      );
      await tester.pump();
      expect(find.text('NEEDED FOR YOUR PLAN'), findsOneWidget);
      expect(find.text('Test craft plan'), findsOneWidget);
      expect(
        find.textContaining('shortages have exact map dots'),
        findsNothing,
        reason: 'the shortlist is self-explanatory without a summary paragraph',
      );
      await tester.scrollUntilVisible(
        snakeRow,
        100,
        scrollable: gatherScrollable,
      );
      await tester.pump();
      expect(snakeRow, findsOneWidget, reason: 'matched by game item ID');
      expect(truffleRow, findsOneWidget, reason: 'matched by exact name');
      expect(sheepRow, findsOneWidget, reason: 'matched by resource alias');
      expect(
        tester.getSize(snakeRow).height,
        lessThanOrEqualTo(54),
        reason: 'plan targets should stay readable and flat, not card-heavy',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-plan-need-item:5007')),
        findsNothing,
        reason: "Monk's Branch has concrete worker-node coverage",
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-plan-need-item:5020')),
        findsNothing,
        reason: 'Thuja Sap has a worker alternative despite its exact dots',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-plan-need-item:5402')),
        findsNothing,
        reason:
            'vendor-direct materials do not belong in a gathering shortlist',
      );
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-plan-need-item:821255'),
        ),
        findsNothing,
        reason: 'market stock already covers the requested quantity',
      );
      expect(
        tester.getTopLeft(snakeRow).dy,
        lessThan(tester.getTopLeft(truffleRow).dy),
      );
      expect(
        tester.getTopLeft(truffleRow).dy,
        lessThan(tester.getTopLeft(sheepRow).dy),
      );
      expect(find.text('0 STOCK'), findsOneWidget);
      expect(find.text('LOW STOCK'), findsOneWidget);
      expect(find.text('GATHER'), findsOneWidget);

      final zeroStockStatus = tester.widget<Tooltip>(
        find.descendant(of: snakeRow, matching: find.byType(Tooltip)),
      );
      expect(zeroStockStatus.message, contains('0 stock at last EU check'));
      expect(zeroStockStatus.message, contains('2026-07-28'));
      final partialStockStatus = tester.widget<Tooltip>(
        find.descendant(of: truffleRow, matching: find.byType(Tooltip)),
      );
      expect(
        partialStockStatus.message,
        contains('Stock below needed quantity'),
      );
      expect(partialStockStatus.message, contains('5 available'));
      expect(partialStockStatus.message, contains('NA'));
      expect(partialStockStatus.message, contains('2026-07-27'));
      final unmarketableStatus = tester.widget<Tooltip>(
        find.descendant(of: sheepRow, matching: find.byType(Tooltip)),
      );
      expect(
        unmarketableStatus.message,
        contains('Not registered on Central Market'),
      );
      expect(unmarketableStatus.message, contains('ASIA'));
      expect(unmarketableStatus.message, contains('2026-07-26'));

      for (final resourceId in const <String>[
        'item:7922',
        'item:5420',
        'item:6002',
      ]) {
        expect(builtResourceIcons, contains(resourceId));
        expect(
          find.byKey(ValueKey<String>('test-resource-icon-$resourceId')),
          findsWidgets,
        );
      }

      await tester.tap(snakeRow);
      await tester.pump();
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      expect(canvas.gatheringPoints, hasLength(657));
      expect(canvas.gatheringSpots, hasLength(1));
      expect(find.text('Exact locations'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-workers')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), "Monk's Branch");
      await tester.pumpAndSettle();
      expect(find.text("Monk's Branch"), findsWidgets);
      final monkBranchWorkerNodeCount = dataset
          .workerNodesForResource('item:5007')
          .length;
      expect(monkBranchWorkerNodeCount, greaterThan(0));
      expect(
        find.textContaining('$monkBranchWorkerNodeCount worker nodes'),
        findsWidgets,
        reason: 'filtering the home shortlist must not remove worker search',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('community-reported Rusalka points use current point wording', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 752));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            showSourceNotice: false,
            tileHttpClient: tileClient,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), "Rusalka's Coral");
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        matching: find.descendant(
          of: find.byType(ListTile),
          matching: find.text("Rusalka's Coral"),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Exact locations'), findsNothing);
    expect(find.text('Historical exact locations'), findsNothing);
    var canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.gatheringPoints, hasLength(34));
    expect(canvas.gatheringSpots, isEmpty);
    await expectLater(
      find.byType(BdoResourceMap),
      matchesGoldenFile('goldens/resource_map_rusalka_coral.png'),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(680, 700));
    await tester.pumpAndSettle();
    canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    canvas.onHit(
      BdoMapHit(
        kind: BdoMapHitKind.gatheringPoint,
        id: canvas.gatheringPoints.first.id,
      ),
    );
    await tester.pump();

    expect(find.text('Community-reported location'), findsOneWidget);
    expect(find.text('Community-reported area'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _expectHousingOverlayDeclutteredAndConnected(
  WidgetTester tester,
  LodgingTown town,
) {
  final markerFinder = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        (key.value.startsWith('resource-map-house-map-cluster-') ||
            key.value.startsWith('resource-map-house-marker-'));
  });
  final markerKeys = tester
      .widgetList<Widget>(markerFinder)
      .map((widget) => widget.key)
      .whereType<ValueKey<String>>()
      .toList(growable: false);
  expect(markerKeys, isNotEmpty);
  final markerRects = <ValueKey<String>, Rect>{
    for (final key in markerKeys) key: tester.getRect(find.byKey(key)),
  };
  for (var firstIndex = 0; firstIndex < markerKeys.length; firstIndex += 1) {
    for (
      var secondIndex = firstIndex + 1;
      secondIndex < markerKeys.length;
      secondIndex += 1
    ) {
      final firstKey = markerKeys[firstIndex];
      final secondKey = markerKeys[secondIndex];
      expect(
        markerRects[firstKey]!
            .inflate(1.5)
            .overlaps(markerRects[secondKey]!.inflate(1.5)),
        isFalse,
        reason:
            '${firstKey.value} and ${secondKey.value} need visible breathing '
            'room at the fitted-town zoom.',
      );
    }
  }

  final housingPaints = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .where(
        (paint) =>
            paint.painter?.runtimeType.toString().contains(
              'HousePrerequisitePainter',
            ) ??
            false,
      )
      .toList(growable: false);
  expect(housingPaints, hasLength(1));
  final housingPainter = housingPaints.single.painter!;
  // ignore: avoid_dynamic_calls
  final rawGraph = (housingPainter as dynamic).debugVisualGraph;
  final graph = Map<String, Object>.from(rawGraph as Map);
  final anchorIds = Map<String, String>.from(graph['anchorIds']! as Map);
  final anchorPositions = Map<String, Offset>.from(
    graph['anchorPositions']! as Map,
  );
  final ownedHouseIds = graph['ownedHouseIds']! as Set<String>;
  final recommendedNewHouseIds =
      graph['recommendedNewHouseIds']! as Set<String>;
  final selectedHouseId = graph['selectedHouseId']! as String;
  final visibleHouseIds = graph['visibleHouseIds']! as Set<String>;
  final edges = graph['edges']! as List<Map<String, Object>>;
  final collapsedAnchorIds = <String>{
    for (final entry in anchorIds.entries)
      if (entry.key != entry.value) entry.value,
  };
  expect(
    collapsedAnchorIds,
    isNotEmpty,
    reason: 'The fitted Calpheon view should collapse dense house groups.',
  );
  expect(
    edges,
    isNotEmpty,
    reason: 'Collapsed house markers still need a visible prerequisite graph.',
  );

  const strengthRanks = <String, int>{
    'neutral': 0,
    'owned': 1,
    'recommended': 2,
    'selected': 3,
  };
  String pairKey(String first, String second) => first.compareTo(second) <= 0
      ? '$first\u0000$second'
      : '$second\u0000$first';

  final expectedStrengthByPair = <String, int>{};
  for (final house in town.houses) {
    final prerequisiteId = house.prerequisiteHouseId;
    if (prerequisiteId == null ||
        !visibleHouseIds.contains(prerequisiteId) ||
        !visibleHouseIds.contains(house.id)) {
      continue;
    }
    final firstAnchorId = anchorIds[prerequisiteId] ?? prerequisiteId;
    final secondAnchorId = anchorIds[house.id] ?? house.id;
    if (firstAnchorId == secondAnchorId) {
      continue;
    }
    final strength =
        selectedHouseId == prerequisiteId || selectedHouseId == house.id
        ? strengthRanks['selected']!
        : recommendedNewHouseIds.contains(prerequisiteId) ||
              recommendedNewHouseIds.contains(house.id)
        ? strengthRanks['recommended']!
        : ownedHouseIds.contains(prerequisiteId) &&
              ownedHouseIds.contains(house.id)
        ? strengthRanks['owned']!
        : strengthRanks['neutral']!;
    final key = pairKey(firstAnchorId, secondAnchorId);
    final previous = expectedStrengthByPair[key];
    if (previous == null || strength > previous) {
      expectedStrengthByPair[key] = strength;
    }
  }

  final actualStrengthByPair = <String, int>{};
  var previousStrength = -1;
  for (final edge in edges) {
    final firstAnchorId = edge['firstAnchorId']! as String;
    final secondAnchorId = edge['secondAnchorId']! as String;
    final start = edge['start']! as Offset;
    final end = edge['end']! as Offset;
    final strengthName = edge['strength']! as String;
    final strength = strengthRanks[strengthName]!;
    final key = pairKey(firstAnchorId, secondAnchorId);
    expect(firstAnchorId, isNot(secondAnchorId));
    expect(
      actualStrengthByPair.containsKey(key),
      isFalse,
      reason: 'Collapsed house edges must be drawn only once.',
    );
    expect(start, anchorPositions[firstAnchorId]);
    expect(end, anchorPositions[secondAnchorId]);
    expect(
      strength,
      greaterThanOrEqualTo(previousStrength),
      reason: 'Neutral rails should paint before highlighted house paths.',
    );
    actualStrengthByPair[key] = strength;
    previousStrength = strength;
  }
  expect(actualStrengthByPair, expectedStrengthByPair);
  expect(
    edges.any(
      (edge) =>
          collapsedAnchorIds.contains(edge['firstAnchorId']) ||
          collapsedAnchorIds.contains(edge['secondAnchorId']),
    ),
    isTrue,
    reason:
        'At least one prerequisite rail should terminate on a visible '
        'cluster anchor instead of a hidden house coordinate.',
  );
}

Future<void> _openNodePlanner(WidgetTester tester) async {
  final desktopCommand = find.byKey(
    const ValueKey<String>('resource-map-command-workers'),
  );
  if (desktopCommand.evaluate().isNotEmpty) {
    await tester.tap(desktopCommand);
  } else {
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-compact-node-planner')),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _openGatherHub(WidgetTester tester) async {
  final desktopCommand = find.byKey(
    const ValueKey<String>('resource-map-command-gather'),
  );
  if (desktopCommand.evaluate().isNotEmpty) {
    await tester.tap(desktopCommand);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resource-map-gather-hub')),
      findsOneWidget,
    );
    return;
  }
  fail('This helper is only used by desktop resource-map tests.');
}

Future<void> _openNodeMaterialTargets(WidgetTester tester) async {
  await _openNodePlanner(tester);
  final materialsAction = find
      .byKey(const ValueKey<String>('resource-map-node-mode-materials'))
      .hitTestable();
  expect(materialsAction, findsOneWidget);
  await tester.tap(materialsAction);
  await tester.pump(const Duration(milliseconds: 250));
  if (find
      .byKey(const ValueKey<String>('resource-map-node-target-preview-loading'))
      .evaluate()
      .isNotEmpty) {
    await _settleNodeTargetPreview(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _openCurrentNodeEditor(WidgetTester tester) async {
  await _openNodePlanner(tester);
  final currentSetup = find
      .byKey(const ValueKey<String>('resource-map-worker-current-action'))
      .hitTestable();
  expect(currentSetup, findsOneWidget);
  await tester.tap(currentSetup);
  await tester.pumpAndSettle();
}

Future<void> _settleNodeNetworkCalculation(WidgetTester tester) async {
  final progress = find.byKey(
    const ValueKey<String>('resource-map-node-network-calculating'),
  );
  for (var attempt = 0; attempt < 200; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (progress.evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('The background node-network calculation did not finish in time.');
}

Future<void> _settleNodeTargetPreview(WidgetTester tester) async {
  final progress = find.byKey(
    const ValueKey<String>('resource-map-node-target-preview-loading'),
  );
  await tester.pump(const Duration(milliseconds: 200));
  for (var attempt = 0; attempt < 200; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (progress.evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('The planned-material CP preview did not finish in time.');
}

Future<void> _settleVisibleGoldenImages(
  WidgetTester tester, {
  required Finder root,
}) async {
  final precached = <ImageProvider<Object>>{};
  for (var pass = 0; pass < 2; pass += 1) {
    await tester.pump();
    final imageElements = find
        .descendant(of: root, matching: find.byType(Image))
        .evaluate()
        .toList(growable: false);
    for (final element in imageElements) {
      final provider = (element.widget as Image).image;
      if (!precached.add(provider)) {
        continue;
      }
      await tester.runAsync(() => precacheImage(provider, element));
    }
    await tester.pumpAndSettle();
  }
}

Future<void> _openWorkerNetwork(WidgetTester tester) async {
  final desktopCommand = find.byKey(
    const ValueKey<String>('resource-map-command-workers'),
  );
  if (desktopCommand.evaluate().isNotEmpty) {
    await tester.tap(desktopCommand);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-browse-action')),
    );
  } else {
    final button = find.byKey(
      const ValueKey<String>('resource-map-open-worker-network'),
    );
    await tester.scrollUntilVisible(
      button,
      240,
      scrollable: find.descendant(
        of: find.byKey(
          const ValueKey<String>('resource-map-sidebar-home-page'),
        ),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(button);
  }
  await tester.pumpAndSettle();
}

BdoResourceMapDataset _rootScopedNetworkDataset() {
  const resource = BdoResourceDefinition(
    id: 'wood',
    name: 'Ash Timber',
    category: 'Timber & sap',
    section: BdoResourceSection.plantsWood,
    aliases: <String>['Ash Wood'],
    acquisitionModes: <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
  );
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'widget-root-scope',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'widget test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[resource],
    workerNodes: <BdoWorkerNode>[
      _networkNode(
        id: 'root-a',
        name: 'Root A',
        type: 'City',
        x: -1200,
        links: const <String>['wood-a'],
      ),
      _networkNode(
        id: 'root-b',
        name: 'Root B',
        type: 'Town',
        x: 1200,
        links: const <String>['wood-b'],
      ),
      _networkNode(id: 'isolated', name: 'Isolated', type: 'City', x: 0),
      _networkProductionNode(id: 'wood-a', parentId: 'root-a', x: -600),
      _networkProductionNode(id: 'wood-b', parentId: 'root-b', x: 600),
    ],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

BdoResourceMapDataset _largeNetworkDataset({required int productionNodeCount}) {
  const resource = BdoResourceDefinition(
    id: 'wood',
    name: 'Ash Timber',
    category: 'Timber & sap',
    section: BdoResourceSection.plantsWood,
    aliases: <String>[],
    acquisitionModes: <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
  );
  final productionIds = <String>[
    for (var index = 0; index < productionNodeCount; index += 1) 'wood-$index',
  ];
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'widget-exact-limit',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'widget test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[resource],
    workerNodes: <BdoWorkerNode>[
      _networkNode(
        id: 'root',
        name: 'Root',
        type: 'City',
        x: 0,
        links: productionIds,
      ),
      for (var index = 0; index < productionNodeCount; index += 1)
        _networkProductionNode(
          id: productionIds[index],
          parentId: 'root',
          x: (index - productionNodeCount / 2) * 180,
        ),
    ],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

BdoResourceMapDataset _rerouteNetworkDataset() {
  const x = BdoResourceDefinition(
    id: 'x',
    gameItemId: 1001,
    name: 'X Material',
    category: 'Test material',
    section: BdoResourceSection.other,
    aliases: <String>[],
    acquisitionModes: <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
  );
  const y = BdoResourceDefinition(
    id: 'y',
    gameItemId: 1002,
    name: 'Y Material',
    category: 'Test material',
    section: BdoResourceSection.other,
    aliases: <String>[],
    acquisitionModes: <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
  );
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'widget-global-reroute',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'widget test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[x, y],
    workerNodes: <BdoWorkerNode>[
      _networkNode(
        id: 'root',
        name: 'Root',
        type: 'City',
        x: 0,
        links: const <String>['shared', 'x-direct', 'y-direct'],
      ),
      _networkNode(
        id: 'shared',
        name: 'Shared route',
        type: 'Connection',
        x: 300,
        cp: 3,
        links: const <String>['root', 'x-shared', 'y-shared'],
      ),
      _networkProductionNode(
        id: 'x-shared',
        parentId: 'shared',
        x: 550,
        resourceId: 'x',
        resourceName: 'X Material',
      ),
      _networkProductionNode(
        id: 'y-shared',
        parentId: 'shared',
        x: 650,
        resourceId: 'y',
        resourceName: 'Y Material',
      ),
      _networkProductionNode(
        id: 'x-direct',
        parentId: 'root',
        x: -500,
        cp: 4,
        resourceId: 'x',
        resourceName: 'X Material',
      ),
      _networkProductionNode(
        id: 'y-direct',
        parentId: 'root',
        x: -300,
        cp: 2,
        resourceId: 'y',
        resourceName: 'Y Material',
      ),
    ],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

BdoWorkerEconomicsDataset _rerouteWorkerEconomics() {
  const worker = BdoWorkerProfileEstimate(
    id: 'test-human',
    label: 'Test Human',
    workerType: 0,
    characterKey: 1,
    isGiant: false,
    workSpeed: 100,
    movementSpeed: 10,
    luck: 20,
  );
  BdoWorkerProductionEconomics production(String nodeId, int gameItemId) {
    return BdoWorkerProductionEconomics(
      nodeId: nodeId,
      baseWorkload: 100,
      workerTypes: const <int>{0},
      standardYields: <int, double>{gameItemId: 10},
      giantYields: <int, double>{gameItemId: 12},
      luckyBonusYields: <int, double>{gameItemId: 2},
      townDistances: const <String, double>{'root': 600},
    );
  }

  return BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: BdoWorkerEconomicsManifest(
      datasetVersion: 'widget-worker-income',
      generatedAt: DateTime.utc(2026, 7, 29),
      sourceRepository: Uri.parse('https://example.invalid/widget-test'),
      sourceCommit: 'widget-test',
      sourcePackageVersion: 'widget-test',
      sourceLicenseExpression: 'test-only',
      upstreamWorkermanCommit: 'widget-test',
      permittedUse: 'Automated test fixture',
      sourceSha256: const <String, String>{'fixture': 'test'},
      assumptions: const <String>['Automated test fixture'],
    ),
    townsByNodeId: <String, BdoWorkerTownEconomics>{
      'root': BdoWorkerTownEconomics(
        nodeId: 'root',
        regionId: 1,
        baseWorkerSlots: 1,
        profiles: const <BdoWorkerProfileEstimate>[worker],
      ),
    },
    productionNodesById: <String, BdoWorkerProductionEconomics>{
      'x-shared': production('x-shared', 1001),
      'y-shared': production('y-shared', 1002),
      'x-direct': production('x-direct', 1001),
      'y-direct': production('y-direct', 1002),
    },
  );
}

LodgingDataset _rerouteLodgingDataset() {
  final lodgingHouse = LodgingHouse(
    id: 'house:9001',
    sourceKey: 9001,
    name: 'Root 1-1',
    regionId: 1,
    townNodeId: 'root',
    parentNodeId: 'root',
    contributionPoints: 1,
    lodgingSpaces: 4,
    isLodging: true,
    usages: const <HouseUsage>[
      HouseUsage(typeId: 1, label: 'Lodging', level: 1),
    ],
    prerequisiteHouseId: null,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
  return LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'widget-lodging',
      generatedAt: DateTime.utc(2026, 7, 30),
      sourceRepository: Uri.parse('https://example.invalid/widget-test'),
      sourceCommit: 'widget-test',
      sourceLicenseExpression: 'test-only',
      permittedUse: 'Automated test fixture',
      sourceSha256: const <String, String>{'fixture': 'test'},
      townCount: 1,
      workerTownCount: 1,
      lodgingHouseCount: 1,
      nonLodgingHouseCount: 0,
      houseCount: 1,
      assumptions: const <String>['Automated test fixture'],
    ),
    towns: <LodgingTown>[
      LodgingTown(
        regionId: 1,
        townNodeId: 'root',
        name: 'Root',
        baseWorkerSlots: 1,
        position: const LodgingPosition(x: 0, y: 0, z: 0),
        houses: <LodgingHouse>[lodgingHouse],
      ),
    ],
  );
}

LodgingDataset _rerouteChainedLodgingDataset() {
  final prerequisite = LodgingHouse(
    id: 'house:9000',
    sourceKey: 9000,
    name: 'Root 1-1',
    regionId: 1,
    townNodeId: 'root',
    parentNodeId: 'root',
    contributionPoints: 1,
    lodgingSpaces: 0,
    isLodging: false,
    usages: <HouseUsage>[HouseUsage(typeId: 2, label: 'Storage', level: 1)],
    prerequisiteHouseId: null,
    position: LodgingPosition(x: -400, y: 0, z: 0),
  );
  final lodgingHouse = LodgingHouse(
    id: 'house:9001',
    sourceKey: 9001,
    name: 'Root 1-2',
    regionId: 1,
    townNodeId: 'root',
    parentNodeId: 'root',
    contributionPoints: 2,
    lodgingSpaces: 4,
    isLodging: true,
    usages: <HouseUsage>[HouseUsage(typeId: 1, label: 'Lodging', level: 1)],
    prerequisiteHouseId: 'house:9000',
    position: LodgingPosition(x: 400, y: 0, z: 0),
  );
  return LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'widget-chained-lodging',
      generatedAt: DateTime.utc(2026, 8, 3),
      sourceRepository: Uri.parse('https://example.invalid/widget-test'),
      sourceCommit: 'widget-test',
      sourceLicenseExpression: 'test-only',
      permittedUse: 'Automated test fixture',
      sourceSha256: const <String, String>{'fixture': 'test'},
      townCount: 1,
      workerTownCount: 1,
      lodgingHouseCount: 1,
      nonLodgingHouseCount: 1,
      houseCount: 2,
      assumptions: const <String>['Automated test fixture'],
    ),
    towns: <LodgingTown>[
      LodgingTown(
        regionId: 1,
        townNodeId: 'root',
        name: 'Root',
        baseWorkerSlots: 1,
        position: LodgingPosition(x: 0, y: 0, z: 0),
        houses: <LodgingHouse>[prerequisite, lodgingHouse],
      ),
    ],
  );
}

BdoWorkerNode _networkNode({
  required String id,
  required String name,
  required String type,
  required double x,
  int cp = 0,
  List<String> links = const <String>[],
}) {
  return BdoWorkerNode(
    id: id,
    name: name,
    nodeType: type,
    region: 'Test',
    location: BdoWorldPoint(x, 0),
    contributionPoints: cp,
    linkIds: links,
    outputs: const <BdoNodeOutput>[],
    isResourceNode: false,
  );
}

BdoWorkerNode _networkProductionNode({
  required String id,
  required String parentId,
  required double x,
  int cp = 1,
  String resourceId = 'wood',
  String resourceName = 'Ash Timber',
}) {
  return BdoWorkerNode(
    id: id,
    name: 'Ash Site - Lumbering',
    nodeType: 'Lumbering',
    region: 'Test',
    location: BdoWorldPoint(x, 0),
    contributionPoints: cp,
    linkIds: <String>[parentId],
    outputs: <BdoNodeOutput>[
      BdoNodeOutput(
        resourceId: resourceId,
        name: resourceName,
        isPrimary: true,
      ),
    ],
    isResourceNode: true,
    isProductionNode: true,
    parentId: parentId,
  );
}

class _PopCountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }
}

Future<List<int>> _makeTileFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size.square(256);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF20383D));
  final land = Path()
    ..moveTo(0, 198)
    ..cubicTo(28, 158, 44, 182, 76, 129)
    ..cubicTo(109, 74, 151, 118, 180, 55)
    ..cubicTo(205, 15, 233, 42, 256, 24)
    ..lineTo(256, 256)
    ..lineTo(0, 256)
    ..close();
  canvas.drawPath(land, Paint()..color = const Color(0xFF4F674F));
  canvas.drawPath(
    land,
    Paint()
      ..color = const Color(0xFF83906D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  for (var offset = 32.0; offset < 256; offset += 48) {
    canvas
      ..drawLine(
        Offset(offset, 0),
        Offset(offset, 256),
        Paint()..color = const Color(0x1439D6C0),
      )
      ..drawLine(
        Offset(0, offset),
        Offset(256, offset),
        Paint()..color = const Color(0x1439D6C0),
      );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
