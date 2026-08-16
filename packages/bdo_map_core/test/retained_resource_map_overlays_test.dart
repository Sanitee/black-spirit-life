import 'dart:convert';
import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset bundledDataset;
  late Directory cacheDirectory;
  late MockClient tileClient;
  late BdoTileSource tileSource;

  setUpAll(() async {
    bundledDataset = await BdoResourceMapLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp(
      'bdo_retained_overlay_test_',
    );
    final transparentPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4'
      'z8DwHwAFgAI/ScL2WQAAAABJRU5ErkJggg==',
    );
    tileClient = MockClient(
      (request) async => http.Response.bytes(
        transparentPng,
        HttpStatus.ok,
        headers: const <String, String>{'content-type': 'image/png'},
      ),
    );
    tileSource = BdoTileSource(
      id: 'retained-overlay-test',
      displayName: 'Retained overlay test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoTileSource.workermanCommunity.worldBounds,
      attribution: 'Test fixture',
      usageNotice: 'Test fixture',
      fileExtension: 'png',
    );
  });

  tearDownAll(() async {
    tileClient.close();
    if (cacheDirectory.existsSync()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  testWidgets('landmark child stays retained and its tap follows a pure pan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final city = bundledDataset.workerNodes.firstWhere(
      (node) => node.nodeType == 'City',
    );
    final dataset = BdoResourceMapDataset(
      manifest: bundledDataset.manifest,
      resources: const <BdoResourceDefinition>[],
      workerNodes: <BdoWorkerNode>[city],
      gatheringSpots: const <BdoGatheringSpot>[],
      gatheringPoints: const <BdoGatheringPoint>[],
      gatheringRoutes: const <BdoGatheringRoute>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cacheDirectory,
            tileSource: tileSource,
            tileHttpClient: tileClient,
            showSourceNotice: false,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              showGatewayHubs: false,
              showAllMapNodes: false,
              showAllNodeConnections: false,
              showWorkerOutputIcons: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final viewport = tester.getSize(find.byType(BdoMapCanvas));
    canvas.cameraController.setCamera(
      BdoMapCamera(center: city.location.mapPoint, zoom: 4.5),
      viewport,
    );
    await tester.pump();

    final markerFinder = find.byKey(
      ValueKey<String>('resource-map-landmark-${city.id}'),
    );
    expect(markerFinder, findsOneWidget);
    final retainedWidget = tester.widget(markerFinder);
    final centerBefore = tester.getCenter(markerFinder);

    canvas.cameraController.panBy(const Offset(64, 28), viewport);
    await tester.pump();

    expect(tester.widget(markerFinder), same(retainedWidget));
    final centerAfter = tester.getCenter(markerFinder);
    expect(centerAfter.dx - centerBefore.dx, closeTo(64, .01));
    expect(centerAfter.dy - centerBefore.dy, closeTo(28, .01));

    await tester.tap(markerFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
      findsOneWidget,
    );
    expect(find.text(city.siteName), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overscan retains an offscreen landmark until pure pan makes it tappable',
    (tester) async {
      const surfaceSize = Size(1000, 700);
      const zoom = 4.5;
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mapCenter = tileSource.worldBounds.center;
      final scale = tileSource.scaleForZoom(zoom);
      BdoWorkerNode cityAt({
        required String id,
        required String name,
        required BdoMapPoint point,
      }) => BdoWorkerNode(
        id: id,
        name: name,
        nodeType: 'City',
        region: 'Retained test',
        location: point.worldPoint,
        contributionPoints: 0,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: false,
      );

      final centeredCity = cityAt(
        id: 'retained-center-city',
        name: 'Retained Center',
        point: mapCenter,
      );
      final enteringCity = cityAt(
        id: 'retained-entering-city',
        name: 'Entering City',
        point: mapCenter.translate((surfaceSize.width / 2 + 40) / scale, 0),
      );
      final dataset = BdoResourceMapDataset(
        manifest: bundledDataset.manifest,
        resources: const <BdoResourceDefinition>[],
        workerNodes: <BdoWorkerNode>[centeredCity, enteringCity],
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringPoints: const <BdoGatheringPoint>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                showGatewayHubs: false,
                showAllMapNodes: false,
                showAllNodeConnections: false,
                showWorkerOutputIcons: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: mapCenter, zoom: zoom),
        viewport,
      );
      await tester.pump();

      final centeredFinder = find.byKey(
        const ValueKey<String>('resource-map-landmark-retained-center-city'),
      );
      final enteringFinder = find.byKey(
        const ValueKey<String>('resource-map-landmark-retained-entering-city'),
      );
      expect(centeredFinder, findsOneWidget);
      expect(enteringFinder, findsOneWidget);
      expect(enteringFinder.hitTestable(), findsNothing);
      final retainedCenteredWidget = tester.widget(centeredFinder);
      final retainedEnteringWidget = tester.widget(enteringFinder);

      canvas.cameraController.panBy(const Offset(-220, 0), viewport);
      await tester.pump();

      expect(tester.widget(centeredFinder), same(retainedCenteredWidget));
      expect(tester.widget(enteringFinder), same(retainedEnteringWidget));
      expect(enteringFinder.hitTestable(), findsOneWidget);

      final enteringTapTarget = find
          .descendant(
            of: enteringFinder,
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.tap(enteringTapTarget);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
        findsOneWidget,
      );
      expect(find.text(enteringCity.siteName), findsWidgets);

      // Disposing the retained overlay must remove both its camera listener
      // and its pending settle timer.
      canvas.cameraController.panBy(const Offset(1, 0), viewport);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dense worker outputs stay retained through repeated pure-pan frames',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var outputArtworkBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: BdoResourceMap(
              dataset: bundledDataset,
              cacheDirectory: cacheDirectory,
              tileSource: tileSource,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              nodeNetworkPreferences: BdoNodeNetworkPreferences(
                showAllMapNodes: true,
                showWorkerOutputIcons: true,
              ),
              workerOutputIconBuilder: (context, resource, size) {
                outputArtworkBuilds += 1;
                return SizedBox.square(
                  dimension: size,
                  child: ColoredBox(color: Colors.teal.shade300),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final viewport = tester.getSize(find.byType(BdoMapCanvas));
      canvas.cameraController.setCamera(
        BdoMapCamera(center: tileSource.worldBounds.center, zoom: 3.15),
        viewport,
      );
      await tester.pump();

      final outputMarkers = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is Positioned &&
            key is ValueKey<String> &&
            key.value.startsWith('resource-map-worker-output-');
      });
      expect(outputMarkers, findsWidgets);
      final firstMarker = outputMarkers.first;
      final retainedMarker = tester.widget(firstMarker);
      final orientationMarkers = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is Positioned &&
            key is ValueKey<String> &&
            key.value.startsWith('resource-map-orientation-node-');
      });
      expect(orientationMarkers, findsWidgets);
      final firstOrientationMarker = orientationMarkers.first;
      final retainedOrientationMarker = tester.widget(firstOrientationMarker);
      final initialArtworkBuilds = outputArtworkBuilds;
      expect(initialArtworkBuilds, greaterThan(0));

      for (var frame = 0; frame < 20; frame += 1) {
        canvas.cameraController.panBy(const Offset(3, 1.5), viewport);
        await tester.pump();
      }

      expect(outputArtworkBuilds, initialArtworkBuilds);
      expect(tester.widget(firstMarker), same(retainedMarker));
      expect(
        tester.widget(firstOrientationMarker),
        same(retainedOrientationMarker),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        outputArtworkBuilds,
        inInclusiveRange(initialArtworkBuilds, initialArtworkBuilds + 3),
        reason:
            'Settling may build artwork for a newly entered edge marker, but '
            'must not rebuild the full dense output layer.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
