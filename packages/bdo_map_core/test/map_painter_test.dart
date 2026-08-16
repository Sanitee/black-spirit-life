import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_map_core/src/engine/map_camera.dart';
import 'package:bdo_map_core/src/engine/tile_cache.dart';
import 'package:bdo_map_core/src/engine/tile_manager.dart';
import 'package:bdo_map_core/src/model/map_geometry.dart';
import 'package:bdo_map_core/src/model/map_visual_style.dart';
import 'package:bdo_map_core/src/model/resource_map_data.dart';
import 'package:bdo_map_core/src/model/tile_source.dart';
import 'package:bdo_map_core/src/network/node_network_models.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/foundation.dart'
    show FlutterMemoryAllocations, ObjectCreated, ObjectDisposed, ObjectEvent;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the painter renders decoded tile pixels into the viewport', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'painter-test',
        displayName: 'Painter test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFFE34B2B));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = BdoMapPainter(
        cameraController: camera,
        tileManager: manager,
        workerNodes: const <BdoWorkerNode>[],
        workerNodesById: const <String, BdoWorkerNode>{},
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
        showConnections: false,
        selectedNodeId: null,
        selectedSpotId: null,
        selectedRouteId: null,
        colorScheme: const ColorScheme.dark(),
      );

      painter.paint(canvas, const Size.square(256));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(256, 256);
      final bytes = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final center = (128 * 256 + 128) * 4;
      final red = bytes!.getUint8(center);
      final green = bytes.getUint8(center + 1);
      final blue = bytes.getUint8(center + 2);

      expect(red, greaterThan(150));
      expect(red, greaterThan(green * 2));
      expect(red, greaterThan(blue * 3));

      rendered.dispose();
      picture.dispose();
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets(
    'vivid treatment changes only the basemap palette and deepens greens and blues',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'vivid-painter-test',
          displayName: 'Vivid painter test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 0,
          worldUnitsAtZoomZero: 256,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF376F62));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(128, 128),
            zoom: 0,
          ),
        );
        BdoMapPainter painter(BdoMapVisualStyle style) => BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          workerNodes: const <BdoWorkerNode>[],
          workerNodesById: const <String, BdoWorkerNode>{},
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringRoutes: const <BdoGatheringRoute>[],
          showConnections: false,
          selectedNodeId: null,
          selectedSpotId: null,
          selectedRouteId: null,
          colorScheme: const ColorScheme.dark(),
          visualStyle: style,
        );

        final standard = await _renderPainter(
          painter(BdoMapVisualStyle.standard),
        );
        final vivid = await _renderPainter(painter(BdoMapVisualStyle.vivid));
        final center = (128 * 256 + 128) * 4;
        final standardGreenLead =
            standard[center + 1].toInt() - standard[center].toInt();
        final standardBlueLead =
            standard[center + 2].toInt() - standard[center].toInt();
        final vividGreenLead =
            vivid[center + 1].toInt() - vivid[center].toInt();
        final vividBlueLead = vivid[center + 2].toInt() - vivid[center].toInt();

        expect(
          vivid.sublist(center, center + 3),
          isNot(standard.sublist(center, center + 3)),
        );
        expect(vividGreenLead, greaterThan(standardGreenLead));
        expect(vividBlueLead, greaterThan(standardBlueLead));

        final transparentTileImage = await _solidImage(Colors.transparent);
        final transparentManager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: transparentTileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        BdoMapPainter backgroundPainter(BdoMapVisualStyle style) =>
            BdoMapPainter(
              cameraController: camera,
              tileManager: transparentManager,
              workerNodes: const <BdoWorkerNode>[],
              workerNodesById: const <String, BdoWorkerNode>{},
              gatheringSpots: const <BdoGatheringSpot>[],
              gatheringRoutes: const <BdoGatheringRoute>[],
              showConnections: false,
              selectedNodeId: null,
              selectedSpotId: null,
              selectedRouteId: null,
              colorScheme: const ColorScheme.dark(),
              visualStyle: style,
            );
        final standardBackground = await _renderPainter(
          backgroundPainter(BdoMapVisualStyle.standard),
        );
        final vividBackground = await _renderPainter(
          backgroundPainter(BdoMapVisualStyle.vivid),
        );
        expect(
          vividBackground,
          orderedEquals(standardBackground),
          reason:
              'The optional treatment must not recolor the viewport, shade, '
              'markers, labels, or routes outside decoded tile pixels.',
        );
        final illuminatedBackground = await _renderPainter(
          BdoMapPainter(
            cameraController: camera,
            tileManager: transparentManager,
            workerNodes: const <BdoWorkerNode>[],
            workerNodesById: const <String, BdoWorkerNode>{},
            gatheringSpots: const <BdoGatheringSpot>[],
            gatheringRoutes: const <BdoGatheringRoute>[],
            showConnections: false,
            selectedNodeId: null,
            selectedSpotId: null,
            selectedRouteId: null,
            colorScheme: const ColorScheme.dark(),
            chromeTheme: ResourceMapChromeThemeData.illuminatedAtlas,
          ),
        );
        expect(
          illuminatedBackground,
          isNot(orderedEquals(standardBackground)),
          reason:
              'The empty canvas belongs to map chrome and must follow the '
              'paired Planner theme.',
        );

        camera.dispose();
        transparentManager.dispose();
        transparentTileImage.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );

  testWidgets('the painter never draws tiles outside its viewport', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'painter-clip-test',
        displayName: 'Painter clip test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 512, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF2ECC71));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(256, 128),
          zoom: 0,
        ),
      );
      final painter = BdoMapPainter(
        cameraController: camera,
        tileManager: manager,
        workerNodes: const <BdoWorkerNode>[],
        workerNodesById: const <String, BdoWorkerNode>{},
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
        showConnections: false,
        selectedNodeId: null,
        selectedSpotId: null,
        selectedRouteId: null,
        colorScheme: const ColorScheme.dark(),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 400, 200),
        Paint()..color = const Color(0xFFB51F32),
      );
      canvas
        ..save()
        ..translate(200, 0);
      painter.paint(canvas, const Size(200, 200));
      canvas.restore();
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(400, 200);
      final bytes = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      int channelAt(int x, int y, int channel) {
        return bytes!.getUint8((y * 400 + x) * 4 + channel);
      }

      expect(channelAt(100, 100, 0), greaterThan(140));
      expect(channelAt(100, 100, 1), lessThan(80));
      expect(channelAt(250, 100, 1), greaterThan(120));
      expect(channelAt(250, 100, 1), greaterThan(channelAt(250, 100, 0)));

      rendered.dispose();
      picture.dispose();
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets('exact gathering dots remain painted below cluster zoom', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'exact-dot-low-zoom-test',
        displayName: 'Exact dot low zoom test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now(),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      const point = BdoGatheringPoint(
        id: 'center-point',
        location: BdoWorldPoint(128, -128),
        resourceIds: <String>['test-resource'],
        target: 'Test target',
        kind: 'gathering',
        label: 'Center point',
        verification: BdoGatheringVerification.communityReported,
        provenanceId: 'test',
      );
      final recorder = ui.PictureRecorder();
      final painter = BdoMapPainter(
        cameraController: camera,
        tileManager: manager,
        workerNodes: const <BdoWorkerNode>[],
        workerNodesById: const <String, BdoWorkerNode>{},
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringPoints: const <BdoGatheringPoint>[point],
        gatheringRoutes: const <BdoGatheringRoute>[],
        showConnections: false,
        selectedNodeId: null,
        selectedSpotId: null,
        selectedRouteId: null,
        colorScheme: const ColorScheme.dark(),
      );

      painter.paint(Canvas(recorder), const Size.square(256));
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(256, 256);
      final bytes = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final center = (128 * 256 + 128) * 4;
      final background = (16 * 256 + 16) * 4;

      expect(bytes!.getUint8(center + 1), greaterThan(100));
      expect(
        bytes.getUint8(center + 1),
        greaterThan(bytes.getUint8(background + 1) + 45),
      );

      rendered.dispose();
      picture.dispose();
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets(
    'route waypoint labels dispose every TextPainter after repeated paints',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'route-label-disposal-test',
          displayName: 'Route label disposal test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 0,
          worldUnitsAtZoomZero: 256,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF22302E));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now(),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(128, 128),
            zoom: 0,
          ),
        );
        const route = BdoGatheringRoute(
          id: 'visible-route',
          spotId: 'visible-spot',
          name: 'Visible route',
          region: 'Test',
          resourceIds: <String>['test-resource'],
          tool: 'Butcher Knife',
          loop: false,
          summary: 'Visible route fixture',
          waypoints: <BdoGatheringWaypoint>[
            BdoGatheringWaypoint(
              order: 1,
              location: BdoWorldPoint(96, -96),
              kind: 'target',
              label: 'First',
              targets: <String>['Test target'],
            ),
            BdoGatheringWaypoint(
              order: 2,
              location: BdoWorldPoint(128, -128),
              kind: 'target',
              label: 'Second',
              targets: <String>['Test target'],
            ),
            BdoGatheringWaypoint(
              order: 3,
              location: BdoWorldPoint(160, -160),
              kind: 'target',
              label: 'Third',
              targets: <String>['Test target'],
            ),
          ],
          verification: BdoGatheringVerification.crossChecked,
          provenanceId: 'test',
        );
        final painter = BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          workerNodes: const <BdoWorkerNode>[],
          workerNodesById: const <String, BdoWorkerNode>{},
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringRoutes: const <BdoGatheringRoute>[route],
          showConnections: false,
          selectedNodeId: null,
          selectedSpotId: null,
          selectedRouteId: null,
          colorScheme: const ColorScheme.dark(),
        );
        final created = <Object>[];
        final disposed = <Object>[];
        var routePaintInProgress = false;

        void recordTextPainterLifecycle(ObjectEvent event) {
          if (!routePaintInProgress) {
            return;
          }
          if (event is ObjectCreated && event.className == 'TextPainter') {
            created.add(event.object);
          } else if (event is ObjectDisposed &&
              created.any((object) => identical(object, event.object))) {
            disposed.add(event.object);
          }
        }

        FlutterMemoryAllocations.instance.addListener(
          recordTextPainterLifecycle,
        );
        try {
          for (var paintCount = 0; paintCount < 2; paintCount++) {
            final recorder = ui.PictureRecorder();
            routePaintInProgress = true;
            try {
              painter.paint(Canvas(recorder), const Size.square(256));
            } finally {
              routePaintInProgress = false;
            }
            recorder.endRecording().dispose();
          }

          expect(created, hasLength(route.waypoints.length * 2));
          expect(disposed, hasLength(created.length));
          for (final painter in created) {
            expect(
              disposed.any((object) => identical(object, painter)),
              isTrue,
            );
          }
        } finally {
          FlutterMemoryAllocations.instance.removeListener(
            recordTextPainterLifecycle,
          );
          camera.dispose();
          manager.dispose();
          tileImage.dispose();
        }
      });
    },
  );

  test('gathering areas do not expose region-sized offscreen hit targets', () {
    const source = BdoTileSource(
      id: 'area-hit-test',
      displayName: 'Area hit test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoMapBounds(
        left: -2000,
        top: -2000,
        right: 2000,
        bottom: 2000,
      ),
      attribution: 'Generated test fixture',
      usageNotice: 'Generated test fixture',
      minimumZoom: 0,
      maximumZoom: 0,
      worldUnitsAtZoomZero: 1000,
      fileExtension: 'png',
    );
    final camera = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 0),
    );
    addTearDown(camera.dispose);
    const spot = BdoGatheringSpot(
      id: 'edge-area',
      name: 'Edge area',
      region: 'Test',
      nearestNode: '',
      location: BdoWorldPoint(-1171.875, 0),
      resourceIds: <String>['test-resource'],
      targets: <BdoGatheringTarget>[],
      quality: 'alternative',
      summary: 'Test fixture',
      verification: BdoGatheringVerification.independentSurvey,
      provenanceId: 'test',
      radiusWorld: 800,
    );
    final layout = BdoMapOverlayLayout(
      cameraController: camera,
      viewport: const Size(400, 400),
      workerNodes: const <BdoWorkerNode>[],
      gatheringSpots: const <BdoGatheringSpot>[spot],
      gatheringRoutes: const <BdoGatheringRoute>[],
    );

    expect(layout.hitTargets, isEmpty);
    expect(layout.hitTest(const Offset(100, 200)), isNull);
  });

  test('gathering-point overview keeps cluster hit targets world anchored', () {
    const source = BdoTileSource(
      id: 'point-zoom-test',
      displayName: 'Point zoom test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoMapBounds(
        left: -2000,
        top: -2000,
        right: 2000,
        bottom: 2000,
      ),
      attribution: 'Generated test fixture',
      usageNotice: 'Generated test fixture',
      minimumZoom: 0,
      maximumZoom: 7,
      worldUnitsAtZoomZero: 4000,
      fileExtension: 'png',
    );
    const viewport = Size(500, 400);
    final camera = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 3),
    );
    addTearDown(camera.dispose);
    const point = BdoGatheringPoint(
      id: 'exact-point',
      location: BdoWorldPoint(0, 0),
      resourceIds: <String>['test-resource'],
      target: 'Test target',
      kind: 'butchering',
      label: 'Exact test point',
      verification: BdoGatheringVerification.stale,
      provenanceId: 'test',
    );

    BdoMapOverlayLayout layout() => BdoMapOverlayLayout(
      cameraController: camera,
      viewport: viewport,
      workerNodes: const <BdoWorkerNode>[],
      gatheringSpots: const <BdoGatheringSpot>[],
      gatheringPoints: const <BdoGatheringPoint>[point],
      gatheringRoutes: const <BdoGatheringRoute>[],
    );

    final overview = layout();
    final overviewTarget = overview.hitTargets.single;
    final overviewCluster = overview.gatheringPointClusters.single;

    expect(identical(overview.hitTargets, overview.hitTargets), isTrue);
    expect(overviewTarget.hit.kind, BdoMapHitKind.gatheringPointCluster);
    expect(overviewTarget.hit.clusterPointIds, <String>[point.id]);
    expect(overviewTarget.hit.clusterBounds, overviewCluster.bounds);
    expect(overviewTarget.position, overviewCluster.position);
    expect(overviewTarget.hitRadius, greaterThan(4.2));
    expect(overview.hitTest(overviewCluster.position), same(overviewTarget));
    expect(
      overviewTarget.hit.clusterBounds!.contains(point.location.mapPoint),
      isTrue,
    );

    camera.setCamera(
      const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 5),
      viewport,
    );
    final target = layout().hitTargets.single;

    expect(target.hit.kind, BdoMapHitKind.gatheringPoint);
    expect(target.hit.id, point.id);
    expect(target.label, point.label);
  });

  test('gathering-point overview clusters remain world anchored after pan', () {
    const source = BdoTileSource(
      id: 'point-cluster-stability-test',
      displayName: 'Point cluster stability test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoMapBounds(
        left: -2000,
        top: -2000,
        right: 2000,
        bottom: 2000,
      ),
      attribution: 'Generated test fixture',
      usageNotice: 'Generated test fixture',
      minimumZoom: 0,
      maximumZoom: 7,
      worldUnitsAtZoomZero: 4000,
      fileExtension: 'png',
    );
    const viewport = Size(500, 400);
    final camera = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 3),
    );
    addTearDown(camera.dispose);
    final points = List<BdoGatheringPoint>.generate(12, (index) {
      return BdoGatheringPoint(
        id: 'point-$index',
        location: BdoWorldPoint(index * 8, index.isEven ? 5 : 12),
        resourceIds: const <String>['test-resource'],
        target: 'Test target',
        kind: 'butchering',
        label: 'Point $index',
        verification: BdoGatheringVerification.stale,
        provenanceId: 'test',
      );
    });

    Set<String> memberships() {
      final layout = BdoMapOverlayLayout(
        cameraController: camera,
        viewport: viewport,
        workerNodes: const <BdoWorkerNode>[],
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringPoints: points,
        gatheringRoutes: const <BdoGatheringRoute>[],
      );
      return layout.gatheringPointClusters.map((cluster) {
        final ids = cluster.points.map((point) => point.id).toList()..sort();
        return ids.join('|');
      }).toSet();
    }

    final before = memberships();
    camera.panBy(const Offset(5, 3), viewport);

    expect(memberships(), before);
  });

  testWidgets('painter skips repaint when only the hover overlay rebuilds', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'selective-repaint-test',
        displayName: 'Selective repaint test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      const nodes = <BdoWorkerNode>[];
      const nodesById = <String, BdoWorkerNode>{};
      const spots = <BdoGatheringSpot>[];
      const points = <BdoGatheringPoint>[];
      const routes = <BdoGatheringRoute>[];
      const colors = ColorScheme.dark();
      BdoMapPainter painter({
        String? selectedPointId,
        double tileFadeProgress = 1,
        BdoMapVisualStyle visualStyle = BdoMapVisualStyle.standard,
        ResourceMapChromeThemeData chromeTheme =
            ResourceMapChromeThemeData.sakuraCartographer,
      }) {
        return BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          workerNodes: nodes,
          workerNodesById: nodesById,
          gatheringSpots: spots,
          gatheringPoints: points,
          gatheringRoutes: routes,
          showConnections: false,
          selectedNodeId: null,
          selectedSpotId: null,
          selectedPointId: selectedPointId,
          selectedRouteId: null,
          colorScheme: colors,
          tileFadeProgress: tileFadeProgress,
          visualStyle: visualStyle,
          chromeTheme: chromeTheme,
        );
      }

      final original = painter();

      expect(painter().shouldRepaint(original), isFalse);
      expect(painter(selectedPointId: 'point').shouldRepaint(original), isTrue);
      expect(painter(tileFadeProgress: 0.5).shouldRepaint(original), isTrue);
      expect(
        painter(visualStyle: BdoMapVisualStyle.vivid).shouldRepaint(original),
        isTrue,
      );
      expect(
        painter(
          chromeTheme: ResourceMapChromeThemeData.illuminatedAtlas,
        ).shouldRepaint(original),
        isTrue,
      );

      final overlayLayout = BdoMapOverlayLayout(
        cameraController: camera,
        viewport: const Size.square(256),
        workerNodes: nodes,
        workerNodesById: nodesById,
        gatheringSpots: spots,
        gatheringPoints: points,
        gatheringRoutes: routes,
      );
      final sakuraEmphasis = BdoMapSearchEmphasisPainter(
        overlayLayout: overlayLayout,
        emphasizedNodeIds: const <String>{'node'},
        selectedNodeId: null,
        pulse: .5,
      );
      final ledgerEmphasis = BdoMapSearchEmphasisPainter(
        overlayLayout: overlayLayout,
        emphasizedNodeIds: const <String>{'node'},
        selectedNodeId: null,
        pulse: .5,
        chromeTheme: ResourceMapChromeThemeData.illuminatedAtlas,
      );
      expect(ledgerEmphasis.shouldRepaint(sakuraEmphasis), isTrue);

      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets('hovering within one target does not rebuild its tooltip', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'hover-state-test',
        displayName: 'Hover state test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      const node = BdoWorkerNode(
        id: 'hover-node',
        name: 'Hover node',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(128, -128),
        contributionPoints: 1,
        linkIds: <String>[],
        outputs: <BdoNodeOutput>[],
        isResourceNode: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: BdoMapCanvas(
              cameraController: camera,
              tileManager: manager,
              workerNodes: const <BdoWorkerNode>[node],
              workerNodesById: const <String, BdoWorkerNode>{
                'hover-node': node,
              },
              gatheringSpots: const <BdoGatheringSpot>[],
              gatheringRoutes: const <BdoGatheringRoute>[],
              showConnections: false,
              onHit: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(BdoMapCanvas));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: center);
      await mouse.moveTo(center);
      await tester.pump();
      final tooltip = find.text('Hover node \u00B7 Mining');
      expect(tooltip, findsOneWidget);
      final firstPosition = tester.getTopLeft(tooltip);

      await mouse.moveTo(center + const Offset(3, 2));
      await tester.pump();

      expect(tester.getTopLeft(tooltip), firstPosition);

      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets('map canvas exposes concise content and navigation semantics', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'map-semantics-test',
        displayName: 'Map semantics test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(
          left: -2000,
          top: -2000,
          right: 2000,
          bottom: 2000,
        ),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 7,
        worldUnitsAtZoomZero: 4000,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 0),
      );
      final nodes = List<BdoWorkerNode>.generate(2, (index) {
        return BdoWorkerNode(
          id: 'node-$index',
          name: 'Node $index',
          nodeType: 'Mining',
          region: 'Test',
          location: BdoWorldPoint(index * 50, 0),
          contributionPoints: 1,
          linkIds: const <String>[],
          outputs: const <BdoNodeOutput>[],
          isResourceNode: true,
        );
      });
      final spots = List<BdoGatheringSpot>.generate(3, (index) {
        return BdoGatheringSpot(
          id: 'zone-$index',
          name: 'Zone $index',
          region: 'Test',
          nearestNode: 'Test',
          location: BdoWorldPoint(index * 70, 120),
          resourceIds: const <String>['test-resource'],
          targets: const <BdoGatheringTarget>[],
          quality: 'alternative',
          summary: 'Test fixture',
          verification: BdoGatheringVerification.crossChecked,
          provenanceId: 'test',
          radiusWorld: 80,
        );
      });
      final points = List<BdoGatheringPoint>.generate(4, (index) {
        return BdoGatheringPoint(
          id: 'point-$index',
          location: BdoWorldPoint(index * 35, -100),
          resourceIds: const <String>['test-resource'],
          target: 'Test target',
          kind: 'butchering',
          label: 'Point $index',
          verification: BdoGatheringVerification.crossChecked,
          provenanceId: 'test',
        );
      });
      const route = BdoGatheringRoute(
        id: 'route',
        spotId: 'zone-0',
        name: 'Route',
        region: 'Test',
        resourceIds: <String>['test-resource'],
        tool: 'Butcher Knife',
        loop: false,
        summary: 'Test fixture',
        waypoints: <BdoGatheringWaypoint>[],
        verification: BdoGatheringVerification.crossChecked,
        provenanceId: 'test',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 500,
            height: 400,
            child: BdoMapCanvas(
              cameraController: camera,
              tileManager: manager,
              workerNodes: nodes,
              workerNodesById: <String, BdoWorkerNode>{
                for (final node in nodes) node.id: node,
              },
              gatheringSpots: spots,
              gatheringPoints: points,
              gatheringRoutes: const <BdoGatheringRoute>[route],
              showConnections: false,
              onHit: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final semanticsFinder = find.byWidgetPredicate((widget) {
        return widget is Semantics &&
            (widget.properties.label ?? '').startsWith(
              'Interactive Black Desert resource map.',
            );
      });
      expect(semanticsFinder, findsOneWidget);
      final semantics = tester.widget<Semantics>(semanticsFinder);
      expect(
        semantics.properties.label,
        contains(
          '2 worker nodes, 3 gathering zones, '
          '4 historical gathering points, and 1 gathering route',
        ),
      );
      expect(semantics.properties.value, 'Zoom 0.0');
      expect(semantics.properties.hint, contains('Click or tap a marker'));
      expect(semantics.properties.hint, contains('arrow keys'));
      expect(semantics.properties.hint, contains('mouse wheel'));
      expect(semantics.properties.hint, contains('Home resets'));
      expect(semantics.properties.onIncrease, isNotNull);
      expect(semantics.properties.onDecrease, isNotNull);
      final viewportClip = tester.widget<ClipRect>(
        find.byKey(const ValueKey<String>('bdo-map-canvas-viewport-clip')),
      );
      expect(viewportClip.clipBehavior, Clip.hardEdge);

      semantics.properties.onIncrease!();
      await tester.pump();
      expect(camera.camera.zoom, closeTo(0.7, 0.001));
      tester.widget<Semantics>(semanticsFinder).properties.onDecrease!.call();
      await tester.pump();
      expect(camera.camera.zoom, closeTo(0, 0.001));

      final center = tester.getCenter(find.byType(BdoMapCanvas));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -2400),
        ),
      );
      await tester.pump();
      expect(
        camera.camera.zoom,
        closeTo(0.75, 0.001),
        reason: 'One high-resolution wheel event must not jump many levels.',
      );

      camera.setCamera(
        camera.camera.copyWith(zoom: camera.maximumZoom - 0.2),
        const Size(500, 400),
      );
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, -2400),
        ),
      );
      await tester.pump();
      expect(camera.camera.zoom, camera.maximumZoom);
      expect(
        tester.widget<Semantics>(semanticsFinder).properties.increasedValue,
        'Zoom 9.0',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets('dense exact points label only the selected point', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'point-label-test',
        displayName: 'Point label test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(
          left: -2000,
          top: -2000,
          right: 2000,
          bottom: 2000,
        ),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 7,
        worldUnitsAtZoomZero: 4000,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 6.5),
      );

      BdoGatheringPoint point(String label) {
        return BdoGatheringPoint(
          id: 'same-point',
          location: const BdoWorldPoint(0, 0),
          resourceIds: const <String>['test-resource'],
          target: 'Test target',
          kind: 'butchering',
          label: label,
          verification: BdoGatheringVerification.stale,
          provenanceId: 'test',
        );
      }

      BdoMapPainter painter(String label, {bool selected = false}) {
        return BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          workerNodes: const <BdoWorkerNode>[],
          workerNodesById: const <String, BdoWorkerNode>{},
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringPoints: <BdoGatheringPoint>[point(label)],
          gatheringRoutes: const <BdoGatheringRoute>[],
          showConnections: false,
          selectedNodeId: null,
          selectedSpotId: null,
          selectedPointId: selected ? 'same-point' : null,
          selectedRouteId: null,
          colorScheme: const ColorScheme.dark(),
        );
      }

      final unselectedShort = await _renderPainter(painter('A'));
      final unselectedLong = await _renderPainter(
        painter('A deliberately much longer label'),
      );
      final selectedShort = await _renderPainter(painter('A', selected: true));
      final selectedLong = await _renderPainter(
        painter('A deliberately much longer label', selected: true),
      );

      expect(unselectedShort, unselectedLong);
      expect(selectedShort, isNot(selectedLong));

      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets(
    'browse overview labels every broad gathering zone without labeling dense states',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'gathering-overview-label-test',
          displayName: 'Gathering overview label test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(
            left: -1200,
            top: -900,
            right: 1200,
            bottom: 900,
          ),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 7,
          worldUnitsAtZoomZero: 1024,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF22302E));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 0),
        );
        const positions = <BdoWorldPoint>[
          BdoWorldPoint(-850, 500),
          BdoWorldPoint(100, 500),
          BdoWorldPoint(700, 450),
          BdoWorldPoint(150, -420),
          BdoWorldPoint(720, -300),
        ];
        const baseNames = <String>[
          '1 Tshira Snake Zone',
          '2 Hakinza Elephant Zone',
          '3 Nymphamare Crab Zone',
          '4 Orbita Sheep Zone',
          '5 Zephyros Snake Zone',
        ];

        List<BdoGatheringSpot> spots(List<String> names) {
          return List<BdoGatheringSpot>.generate(names.length, (index) {
            return BdoGatheringSpot(
              id: 'zone-$index',
              name: names[index],
              region: 'Test',
              nearestNode: 'Test',
              location: positions[index],
              resourceIds: const <String>['test-resource'],
              targets: const <BdoGatheringTarget>[],
              quality: 'alternative',
              summary: 'Test fixture',
              verification: BdoGatheringVerification.crossChecked,
              provenanceId: 'test',
              radiusWorld: 120,
            );
          });
        }

        BdoMapPainter painter(
          List<String> names, {
          bool focused = false,
          bool dense = false,
        }) {
          final visibleSpots = spots(names);
          return BdoMapPainter(
            cameraController: camera,
            tileManager: manager,
            workerNodes: const <BdoWorkerNode>[],
            workerNodesById: const <String, BdoWorkerNode>{},
            gatheringSpots: focused
                ? visibleSpots.take(1).toList(growable: false)
                : visibleSpots,
            gatheringPoints: dense
                ? const <BdoGatheringPoint>[
                    BdoGatheringPoint(
                      id: 'dense-point',
                      location: BdoWorldPoint(0, 0),
                      resourceIds: <String>['test-resource'],
                      target: 'Test target',
                      kind: 'butchering',
                      label: 'Dense point',
                      verification: BdoGatheringVerification.crossChecked,
                      provenanceId: 'test',
                    ),
                  ]
                : const <BdoGatheringPoint>[],
            gatheringRoutes: const <BdoGatheringRoute>[],
            showConnections: false,
            selectedNodeId: null,
            selectedSpotId: null,
            selectedPointId: null,
            selectedRouteId: null,
            colorScheme: const ColorScheme.dark(),
          );
        }

        const viewport = Size(640, 420);
        final overview = await _renderPainter(
          painter(baseNames),
          size: viewport,
        );
        for (var index = 0; index < baseNames.length; index++) {
          final changedNames = baseNames.toList(growable: false);
          changedNames[index] = 'Changed ${changedNames[index]}';
          final changed = await _renderPainter(
            painter(changedNames),
            size: viewport,
          );
          expect(
            changed,
            isNot(overview),
            reason: 'Zone ${index + 1} should have a visible overview label.',
          );
        }

        final allNamesChanged = baseNames
            .map((name) => name.replaceFirst('Zone', 'Region'))
            .toList(growable: false);
        final changedOverview = await _renderPainter(
          painter(allNamesChanged),
          size: viewport,
        );
        final focusedShort = await _renderPainter(
          painter(baseNames, focused: true),
          size: viewport,
        );
        final focusedLong = await _renderPainter(
          painter(allNamesChanged, focused: true),
          size: viewport,
        );
        final denseShort = await _renderPainter(
          painter(baseNames, dense: true),
          size: viewport,
        );
        final denseLong = await _renderPainter(
          painter(allNamesChanged, dense: true),
          size: viewport,
        );

        expect(changedOverview, isNot(overview));
        expect(focusedShort, focusedLong);
        expect(denseShort, denseLong);

        camera.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );

  testWidgets('worker activity changes icon marker artwork', (tester) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'worker-activity-marker-test',
        displayName: 'Worker activity marker test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );

      BdoWorkerNode node({required String name, required String nodeType}) {
        return BdoWorkerNode(
          id: 'activity-node',
          name: name,
          nodeType: nodeType,
          region: 'Test',
          location: const BdoWorldPoint(128, -128),
          contributionPoints: 1,
          linkIds: const <String>[],
          outputs: const <BdoNodeOutput>[],
          isResourceNode: true,
        );
      }

      BdoMapPainter painter(BdoWorkerNode node) {
        return BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          workerNodes: <BdoWorkerNode>[node],
          workerNodesById: <String, BdoWorkerNode>{node.id: node},
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringRoutes: const <BdoGatheringRoute>[],
          showConnections: false,
          selectedNodeId: null,
          selectedSpotId: null,
          selectedRouteId: null,
          colorScheme: const ColorScheme.dark(),
        );
      }

      final mining = await _renderPainter(
        painter(node(name: 'Activity Site - Mining', nodeType: 'Mine')),
      );
      final farming = await _renderPainter(
        painter(node(name: 'Activity Site - Farming', nodeType: 'Farm')),
      );

      expect(mining, isNot(farming));

      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  test(
    'worker hit labels lead with primary output and use the parent site',
    () {
      const source = BdoTileSource(
        id: 'worker-activity-label-test',
        displayName: 'Worker activity label test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(
          left: -2000,
          top: -2000,
          right: 2000,
          bottom: 2000,
        ),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 7,
        worldUnitsAtZoomZero: 4000,
        fileExtension: 'png',
      );
      const parent = BdoWorkerNode(
        id: 'island',
        name: 'Pujara Island',
        nodeType: 'Connection',
        region: 'Balenos',
        location: BdoWorldPoint(20, 0),
        contributionPoints: 1,
        linkIds: <String>[],
        outputs: <BdoNodeOutput>[],
        isResourceNode: false,
      );
      const mining = BdoWorkerNode(
        id: 'mining',
        name: 'Primal Giant Post - Mining',
        nodeType: 'Mine',
        region: 'Calpheon',
        location: BdoWorldPoint(-20, 0),
        contributionPoints: 1,
        linkIds: <String>[],
        outputs: <BdoNodeOutput>[
          BdoNodeOutput(
            resourceId: 'lead-ore',
            name: 'Lead Ore',
            isPrimary: true,
          ),
        ],
        isResourceNode: true,
      );
      const fishing = BdoWorkerNode(
        id: 'fishing',
        name: 'Fish Drying Yard 1',
        nodeType: 'Fishing',
        region: '',
        location: BdoWorldPoint(20, 0),
        contributionPoints: 1,
        linkIds: <String>[],
        outputs: <BdoNodeOutput>[
          BdoNodeOutput(
            resourceId: 'dried-fish',
            name: 'Dried Fish',
            isPrimary: true,
          ),
        ],
        isResourceNode: true,
        parentId: 'island',
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 6.5),
      );
      addTearDown(camera.dispose);
      final layout = BdoMapOverlayLayout(
        cameraController: camera,
        viewport: const Size(500, 400),
        workerNodes: const <BdoWorkerNode>[mining, fishing],
        workerNodesById: const <String, BdoWorkerNode>{
          'island': parent,
          'mining': mining,
          'fishing': fishing,
        },
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
      );
      final labelsById = <String, String>{
        for (final target in layout.hitTargets) target.hit.id: target.label,
      };

      expect(labelsById['mining'], 'Lead Ore \u00B7 Primal Giant Post');
      expect(labelsById['fishing'], 'Dried Fish \u00B7 Pujara Island');
    },
  );

  testWidgets(
    'browse-all workers suppress labels while focused results retain context',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'worker-label-density-test',
          displayName: 'Worker label density test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(
            left: -2000,
            top: -2000,
            right: 2000,
            bottom: 2000,
          ),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 7,
          worldUnitsAtZoomZero: 4000,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF22302E));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(0, 0),
            zoom: 6.5,
          ),
        );

        List<BdoWorkerNode> nodes(String nameSuffix) {
          return List<BdoWorkerNode>.generate(60, (index) {
            final column = index % 10;
            final row = index ~/ 10;
            return BdoWorkerNode(
              id: 'node-$index',
              name: 'Node $index $nameSuffix',
              nodeType: 'Mining',
              region: 'Test',
              location: BdoWorldPoint((column - 4.5) * 7, -(row - 2.5) * 7),
              contributionPoints: 1,
              linkIds: const <String>[],
              outputs: const <BdoNodeOutput>[],
              isResourceNode: true,
            );
          });
        }

        BdoMapPainter painter(
          List<BdoWorkerNode> visibleNodes, {
          String? selectedNodeId,
          bool declutterForOutputArtwork = false,
        }) {
          return BdoMapPainter(
            cameraController: camera,
            tileManager: manager,
            workerNodes: visibleNodes,
            workerNodesById: <String, BdoWorkerNode>{
              for (final node in visibleNodes) node.id: node,
            },
            gatheringSpots: const <BdoGatheringSpot>[],
            gatheringRoutes: const <BdoGatheringRoute>[],
            showConnections: false,
            declutterWorkerLabelsForOutputArtwork: declutterForOutputArtwork,
            workerOutputArtworkMinimumZoom: 2.2,
            selectedNodeId: selectedNodeId,
            selectedSpotId: null,
            selectedRouteId: null,
            colorScheme: const ColorScheme.dark(),
          );
        }

        final shortNames = nodes('A');
        final longNames = nodes('A deliberately much longer label');
        final browseShort = await _renderPainter(painter(shortNames));
        final browseLong = await _renderPainter(painter(longNames));
        final focusedShort = await _renderPainter(
          painter(shortNames.take(6).toList(growable: false)),
        );
        final focusedLong = await _renderPainter(
          painter(longNames.take(6).toList(growable: false)),
        );
        final selectedShort = await _renderPainter(
          painter(shortNames, selectedNodeId: 'node-24'),
        );
        final selectedLong = await _renderPainter(
          painter(longNames, selectedNodeId: 'node-24'),
        );
        final declutteredShort = await _renderPainter(
          painter(
            shortNames.take(6).toList(growable: false),
            declutterForOutputArtwork: true,
          ),
        );
        final declutteredLong = await _renderPainter(
          painter(
            longNames.take(6).toList(growable: false),
            declutterForOutputArtwork: true,
          ),
        );
        final declutteredSelectedShort = await _renderPainter(
          painter(
            shortNames.take(6).toList(growable: false),
            selectedNodeId: 'node-2',
            declutterForOutputArtwork: true,
          ),
        );
        final declutteredSelectedLong = await _renderPainter(
          painter(
            longNames.take(6).toList(growable: false),
            selectedNodeId: 'node-2',
            declutterForOutputArtwork: true,
          ),
        );

        expect(browseShort, browseLong);
        expect(focusedShort, isNot(focusedLong));
        expect(selectedShort, isNot(selectedLong));
        expect(
          declutteredShort,
          declutteredLong,
          reason: 'Output artwork owns the unselected label space.',
        );
        expect(
          declutteredSelectedShort,
          isNot(declutteredSelectedLong),
          reason: 'A selected node keeps one contextual label below its icon.',
        );

        camera.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );

  test('worker clustering is world anchored at every result count', () {
    const source = BdoTileSource(
      id: 'stable-cluster-test',
      displayName: 'Stable cluster test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoMapBounds(
        left: 0,
        top: -100000,
        right: 100000,
        bottom: 0,
      ),
      attribution: 'Generated test fixture',
      usageNotice: 'Generated test fixture',
      minimumZoom: 0,
      maximumZoom: 7,
      worldUnitsAtZoomZero: 100000,
      fileExtension: 'png',
    );
    const viewport = Size(800, 600);
    final camera = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(
        center: BdoMapPoint(25000, -38000),
        zoom: 2.2,
      ),
    );
    addTearDown(camera.dispose);
    final nodes = List<BdoWorkerNode>.generate(60, (index) {
      final column = index % 10;
      final row = index ~/ 10;
      return BdoWorkerNode(
        id: 'node-$index',
        name: 'Node $index',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(10000 + column * 3000, 30000 + row * 3000),
        contributionPoints: 1,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: true,
      );
    });

    BdoMapOverlayLayout layoutFor(List<BdoWorkerNode> visibleNodes) {
      return BdoMapOverlayLayout(
        cameraController: camera,
        viewport: viewport,
        workerNodes: visibleNodes,
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
      );
    }

    Set<String> memberships(BdoMapOverlayLayout layout) {
      return layout.nodeClusters.map((cluster) {
        final ids = cluster.nodes.map((node) => node.id).toList()..sort();
        return ids.join('|');
      }).toSet();
    }

    final before = layoutFor(nodes);
    expect(
      before.nodeClusters.any((cluster) => cluster.nodes.length > 1),
      isTrue,
    );
    final beforeMemberships = memberships(before);

    camera.panBy(const Offset(5, 3), viewport);
    final afterMemberships = memberships(layoutFor(nodes));
    expect(afterMemberships, beforeMemberships);

    final focused = layoutFor(nodes.take(40).toList(growable: false));
    expect(focused.nodeClusters.length, lessThan(40));
    expect(
      focused.nodeClusters.any((cluster) => cluster.nodes.length > 1),
      isTrue,
    );

    final withSelection = BdoMapOverlayLayout(
      cameraController: camera,
      viewport: viewport,
      workerNodes: nodes.take(40).toList(growable: false),
      gatheringSpots: const <BdoGatheringSpot>[],
      gatheringRoutes: const <BdoGatheringRoute>[],
      selectedNodeId: 'node-0',
    );
    expect(
      withSelection.nodeClusters
          .singleWhere(
            (cluster) => cluster.nodes.any((node) => node.id == 'node-0'),
          )
          .nodes,
      hasLength(1),
    );
  });

  test('close zoom clusters only worker markers that would collide', () {
    const source = BdoTileSource(
      id: 'close-zoom-cluster-test',
      displayName: 'Close zoom cluster test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoMapBounds(
        left: 0,
        top: -100000,
        right: 100000,
        bottom: 0,
      ),
      attribution: 'Generated test fixture',
      usageNotice: 'Generated test fixture',
      minimumZoom: 0,
      maximumZoom: 7,
      worldUnitsAtZoomZero: 100000,
      fileExtension: 'png',
    );
    const viewport = Size(800, 600);
    final camera = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(
        center: BdoMapPoint(25000, -38000),
        zoom: 9,
      ),
    );
    addTearDown(camera.dispose);
    final scale = source.scaleForZoom(camera.maximumZoom);
    final nearWorldDelta = 20 / scale;
    final clearWorldDelta = 90 / scale;
    final nodes = <BdoWorkerNode>[
      const BdoWorkerNode(
        id: 'close-a',
        name: 'Close A',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(25000, 38000),
        contributionPoints: 1,
        linkIds: <String>[],
        outputs: <BdoNodeOutput>[],
        isResourceNode: true,
      ),
      BdoWorkerNode(
        id: 'close-b',
        name: 'Close B',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(25000 + nearWorldDelta, 38000),
        contributionPoints: 1,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: true,
      ),
      BdoWorkerNode(
        id: 'clear-c',
        name: 'Clear C',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(25000 + clearWorldDelta, 38000),
        contributionPoints: 1,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: true,
      ),
    ];

    BdoMapOverlayLayout layout() => BdoMapOverlayLayout(
      cameraController: camera,
      viewport: viewport,
      workerNodes: nodes,
      gatheringSpots: const <BdoGatheringSpot>[],
      gatheringRoutes: const <BdoGatheringRoute>[],
    );

    Set<String> memberships(BdoMapOverlayLayout value) {
      return value.nodeClusters.map((cluster) {
        final ids = cluster.nodes.map((node) => node.id).toList()..sort();
        return ids.join('|');
      }).toSet();
    }

    final before = layout();
    expect(camera.camera.zoom, camera.maximumZoom);
    expect(memberships(before), <String>{'close-a|close-b', 'clear-c'});
    final centers = before.nodeClusters
        .map((cluster) => cluster.position)
        .toList(growable: false);
    expect((centers.first - centers.last).distance, greaterThanOrEqualTo(40));

    camera.panBy(const Offset(11, -7), viewport);
    expect(memberships(layout()), memberships(before));
  });

  testWidgets('status-only tile notifications do not repaint map overlays', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'status-repaint-test',
        displayName: 'Status repaint test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: -256, right: 256, bottom: 0),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF24312F));
      final manager = _NotifyingPainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now(),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, -128),
          zoom: 0,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.square(
            dimension: 400,
            child: BdoMapCanvas(
              cameraController: camera,
              tileManager: manager,
              workerNodes: const <BdoWorkerNode>[],
              workerNodesById: const <String, BdoWorkerNode>{},
              gatheringSpots: const <BdoGatheringSpot>[],
              gatheringRoutes: const <BdoGatheringRoute>[],
              showConnections: false,
              onHit: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      BdoMapPainter currentPainter() {
        final customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(BdoMapCanvas),
            matching: find.byType(CustomPaint),
          ),
        );
        return customPaint.painter! as BdoMapPainter;
      }

      final beforeStatus = currentPainter();
      manager.notifyStatusOnly();
      await tester.pump();
      expect(currentPainter(), same(beforeStatus));
      expect(currentPainter().tilePaintRevision, 0);

      manager.publishDecodedTile();
      await tester.pump();
      expect(currentPainter(), same(beforeStatus));
      expect(currentPainter().tilePaintRevisionListenable?.value, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets('node-network additions paint a legible green route', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'network-change-painter-test',
        displayName: 'Network change painter test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF22302E));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      const first = BdoWorkerNode(
        id: 'first',
        name: 'First',
        nodeType: 'Town',
        region: 'Test',
        location: BdoWorldPoint(64, -128),
        contributionPoints: 0,
        linkIds: <String>['second'],
        outputs: <BdoNodeOutput>[],
        isResourceNode: false,
      );
      const second = BdoWorkerNode(
        id: 'second',
        name: 'Second - Mining',
        nodeType: 'Mining',
        region: 'Test',
        location: BdoWorldPoint(192, -128),
        contributionPoints: 1,
        linkIds: <String>['first'],
        outputs: <BdoNodeOutput>[],
        isResourceNode: true,
        isProductionNode: true,
      );
      final painter = BdoMapPainter(
        cameraController: camera,
        tileManager: manager,
        workerNodes: const <BdoWorkerNode>[first, second],
        workerNodesById: const <String, BdoWorkerNode>{
          'first': first,
          'second': second,
        },
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
        showConnections: false,
        nodeNetworkEdgeChanges: const <BdoNodeNetworkEdgeChange>[
          BdoNodeNetworkEdgeChange(
            firstNodeId: 'first',
            secondNodeId: 'second',
            kind: BdoNodeNetworkChangeKind.connect,
          ),
        ],
        nodeNetworkChangeKinds: const <String, BdoNodeNetworkChangeKind>{
          'second': BdoNodeNetworkChangeKind.connect,
        },
        selectedNodeId: null,
        selectedSpotId: null,
        selectedRouteId: null,
        colorScheme: const ColorScheme.dark(),
      );

      final bytes = await _renderPainter(painter);
      final center = (128 * 256 + 128) * 4;
      expect(bytes[center + 1], greaterThan(bytes[center]));
      expect(bytes[center + 1], greaterThan(bytes[center + 2]));
      expect(bytes[center + 1], greaterThan(150));

      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets(
    'planned-route paths are retained and translated across center-only pans',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'retained-network-path-test',
          displayName: 'Retained network path test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 1,
          worldUnitsAtZoomZero: 256,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF22302E));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(64, 128),
            zoom: 0,
          ),
        );
        const first = BdoWorkerNode(
          id: 'first',
          name: 'First',
          nodeType: 'Connection',
          region: 'Test',
          location: BdoWorldPoint(30, -128),
          contributionPoints: 1,
          linkIds: <String>['second'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const second = BdoWorkerNode(
          id: 'second',
          name: 'Second',
          nodeType: 'Connection',
          region: 'Test',
          location: BdoWorldPoint(90, -128),
          contributionPoints: 1,
          linkIds: <String>['first'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const offscreenFirst = BdoWorkerNode(
          id: 'offscreen-first',
          name: 'Offscreen first',
          nodeType: 'Connection',
          region: 'Test',
          location: BdoWorldPoint(180, -128),
          contributionPoints: 1,
          linkIds: <String>['offscreen-second'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const offscreenSecond = BdoWorkerNode(
          id: 'offscreen-second',
          name: 'Offscreen second',
          nodeType: 'Connection',
          region: 'Test',
          location: BdoWorldPoint(220, -128),
          contributionPoints: 1,
          linkIds: <String>['offscreen-first'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        final painter = BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          // Route endpoints intentionally stay out of the node layer so the
          // sampled green span below contains only the planned edge itself.
          workerNodes: const <BdoWorkerNode>[],
          workerNodesById: const <String, BdoWorkerNode>{
            'first': first,
            'second': second,
            'offscreen-first': offscreenFirst,
            'offscreen-second': offscreenSecond,
          },
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringRoutes: const <BdoGatheringRoute>[],
          showConnections: false,
          nodeNetworkEdgeChanges: const <BdoNodeNetworkEdgeChange>[
            BdoNodeNetworkEdgeChange(
              firstNodeId: 'first',
              secondNodeId: 'second',
              kind: BdoNodeNetworkChangeKind.connect,
            ),
            BdoNodeNetworkEdgeChange(
              firstNodeId: 'offscreen-first',
              secondNodeId: 'offscreen-second',
              kind: BdoNodeNetworkChangeKind.connect,
            ),
          ],
          nodeNetworkChangeKinds: const <String, BdoNodeNetworkChangeKind>{
            'first': BdoNodeNetworkChangeKind.connect,
            'second': BdoNodeNetworkChangeKind.connect,
            'offscreen-first': BdoNodeNetworkChangeKind.connect,
            'offscreen-second': BdoNodeNetworkChangeKind.connect,
          },
          // A selected route endpoint exercises the retained planned-node
          // ring geometry without adding node-marker artwork to this fixture.
          selectedNodeId: 'first',
          selectedSpotId: null,
          selectedRouteId: null,
          colorScheme: const ColorScheme.dark(),
        );

        final before = await _renderPainter(
          painter,
          size: const Size.square(128),
        );
        final beforeSpan = _greenRouteSpan(before, width: 128, row: 64);
        expect(beforeSpan, isNotNull);
        expect(painter.debugNodeNetworkGeometryBuildCount, 1);
        expect(painter.debugNodeNetworkRingGeometryBuildCount, 1);

        camera.panBy(const Offset(10, 0), const Size.square(128));
        final after = await _renderPainter(
          painter,
          size: const Size.square(128),
        );
        final afterSpan = _greenRouteSpan(after, width: 128, row: 64);
        expect(afterSpan, isNotNull);
        expect(
          afterSpan!.$1 - beforeSpan!.$1,
          10,
          reason:
              'before=$beforeSpan after=$afterSpan camera=${camera.camera.center}',
        );
        expect(afterSpan.$2 - beforeSpan.$2, 10);
        expect(painter.debugNodeNetworkGeometryBuildCount, 1);
        expect(painter.debugNodeNetworkRingGeometryBuildCount, 1);

        // The second route was outside the original viewport (and outside the
        // old culling allowance). It still appears after a center-only pan,
        // proving the retained geometry contains every valid planned edge.
        camera.panBy(const Offset(-138, 0), const Size.square(128));
        final revealed = await _renderPainter(
          painter,
          size: const Size.square(128),
        );
        expect(_greenRouteSpan(revealed, width: 128, row: 64), isNotNull);
        expect(painter.debugNodeNetworkGeometryBuildCount, 1);
        expect(painter.debugNodeNetworkRingGeometryBuildCount, 1);

        await _renderPainter(painter, size: const Size.square(160));
        expect(painter.debugNodeNetworkGeometryBuildCount, 2);
        expect(painter.debugNodeNetworkRingGeometryBuildCount, 2);

        camera.zoomAround(
          zoom: 1,
          anchor: const Offset(80, 80),
          viewport: const Size.square(160),
        );
        await _renderPainter(painter, size: const Size.square(160));
        expect(painter.debugNodeNetworkGeometryBuildCount, 3);
        expect(painter.debugNodeNetworkRingGeometryBuildCount, 3);

        camera.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );

  testWidgets(
    'large planned-node marker artwork records once across repeated pans',
    (tester) async {
      await tester.runAsync(() async {
        const viewport = Size.square(256);
        const source = BdoTileSource(
          id: 'retained-planned-marker-test',
          displayName: 'Retained planned marker test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 7,
          worldUnitsAtZoomZero: 256,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF22302E));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(128, 128),
            zoom: 6.3,
          ),
        );
        final nodes = <BdoWorkerNode>[
          for (var index = 0; index < 96; index += 1)
            BdoWorkerNode(
              id: 'production-$index',
              name: 'Production $index',
              nodeType: 'Farm',
              region: 'Test',
              location: BdoWorldPoint(
                123.6 + (index % 12) * .8,
                -(125.2 + (index ~/ 12) * .8),
              ),
              contributionPoints: 1,
              linkIds: <String>[
                if (index > 0) 'production-${index - 1}',
                if (index < 95) 'production-${index + 1}',
              ],
              outputs: const <BdoNodeOutput>[],
              isResourceNode: true,
              isProductionNode: true,
            ),
        ];
        final nodesById = <String, BdoWorkerNode>{
          for (final node in nodes) node.id: node,
        };
        final edges = <BdoNodeNetworkEdgeChange>[
          for (var index = 1; index < nodes.length; index += 1)
            BdoNodeNetworkEdgeChange(
              firstNodeId: nodes[index - 1].id,
              secondNodeId: nodes[index].id,
              kind: BdoNodeNetworkChangeKind.connect,
            ),
        ];
        final changeKinds = <String, BdoNodeNetworkChangeKind>{
          for (final node in nodes) node.id: BdoNodeNetworkChangeKind.connect,
        };
        final layout = BdoMapOverlayLayout(
          cameraController: camera,
          viewport: viewport,
          workerNodes: nodes,
          workerNodesById: nodesById,
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringRoutes: const <BdoGatheringRoute>[],
          retainAllWorkerNodes: true,
        );
        final painter = BdoMapPainter(
          cameraController: camera,
          tileManager: manager,
          workerNodes: nodes,
          workerNodesById: nodesById,
          gatheringSpots: const <BdoGatheringSpot>[],
          gatheringRoutes: const <BdoGatheringRoute>[],
          showConnections: false,
          nodeNetworkEdgeChanges: edges,
          nodeNetworkChangeKinds: changeKinds,
          selectedNodeId: null,
          selectedSpotId: null,
          selectedRouteId: null,
          colorScheme: const ColorScheme.dark(),
          overlayLayout: layout,
        );

        await _renderPainter(painter, size: viewport);
        expect(layout.nodeClusters.length, 96);
        expect(painter.debugPlannedNodeMarkerPictureBuildCount, 1);
        expect(painter.debugPlannedNodeMarkerPictureReplayCount, 1);

        for (var frame = 0; frame < 8; frame += 1) {
          camera.panBy(const Offset(14, 7), viewport);
          await _renderPainter(painter, size: viewport);
        }
        expect(
          painter.debugPlannedNodeMarkerPictureBuildCount,
          1,
          reason:
              'A 96-node planned network should replay one recorded marker '
              'picture during ordinary fixed-zoom panning.',
        );
        expect(painter.debugPlannedNodeMarkerPictureReplayCount, 9);
        expect(painter.debugNodeNetworkGeometryBuildCount, 1);
        expect(painter.debugNodeNetworkRingGeometryBuildCount, 1);

        // Crossing the generous overscan boundary records a fresh complete
        // neighborhood instead of letting newly revealed markers disappear.
        camera.panBy(const Offset(-1400, 0), viewport);
        await _renderPainter(painter, size: viewport);
        expect(painter.debugPlannedNodeMarkerPictureBuildCount, 2);
        expect(painter.debugPlannedNodeMarkerPictureReplayCount, 10);

        camera.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );

  testWidgets('inactive network routes paint a dark halo and light core', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'inactive-route-painter-test',
        displayName: 'Inactive route painter test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF52615D));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      const first = BdoWorkerNode(
        id: 'first',
        name: 'First',
        nodeType: 'Town',
        region: 'Test',
        location: BdoWorldPoint(64, -128),
        contributionPoints: 0,
        linkIds: <String>['second'],
        outputs: <BdoNodeOutput>[],
        isResourceNode: false,
      );
      const second = BdoWorkerNode(
        id: 'second',
        name: 'Second',
        nodeType: 'Connection',
        region: 'Test',
        location: BdoWorldPoint(192, -128),
        contributionPoints: 1,
        linkIds: <String>['first'],
        outputs: <BdoNodeOutput>[],
        isResourceNode: false,
      );
      final painter = BdoMapPainter(
        cameraController: camera,
        tileManager: manager,
        workerNodes: const <BdoWorkerNode>[first, second],
        workerNodesById: const <String, BdoWorkerNode>{
          'first': first,
          'second': second,
        },
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
        showConnections: false,
        showAllNetworkConnections: true,
        selectedNodeId: null,
        selectedSpotId: null,
        selectedRouteId: null,
        colorScheme: const ColorScheme.dark(),
      );

      final bytes = await _renderPainter(painter);
      int channel(int x, int y, int channel) =>
          bytes[(y * 256 + x) * 4 + channel];
      expect(channel(128, 128, 0), greaterThan(90));
      expect(channel(128, 128, 1), greaterThan(90));
      expect(channel(128, 128, 2), greaterThan(90));
      expect(
        channel(128, 126, 1),
        lessThan(channel(128, 124, 1)),
        reason: 'The dark route halo separates the pale core from map art.',
      );

      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets('neutral routes stay legible on light and dark basemaps', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final fixture in <({Color tile, bool light})>[
        (tile: const Color(0xFF172321), light: false),
        (tile: const Color(0xFFE4E0D2), light: true),
      ]) {
        final bytes = await _renderNetworkEdge(
          tileColor: fixture.tile,
          showAllNetworkConnections: true,
        );
        double luminanceAt(int x, int y) {
          final offset = (y * 256 + x) * 4;
          return bytes[offset] * .2126 +
              bytes[offset + 1] * .7152 +
              bytes[offset + 2] * .0722;
        }

        final background = luminanceAt(128, 120);
        final halo = luminanceAt(128, 126);
        final core = luminanceAt(128, 128);
        expect(
          core - halo,
          greaterThan(28),
          reason:
              'The dual-tone route must remain distinct on ${fixture.tile}: '
              'background=$background, halo=$halo, core=$core.',
        );
        if (fixture.light) {
          expect(
            background - halo,
            greaterThan(45),
            reason: 'A dark casing must separate the route from light terrain.',
          );
        } else {
          expect(
            core - background,
            greaterThan(45),
            reason: 'The route core must separate from dark terrain.',
          );
        }
      }
    });
  });

  testWidgets('all-network mode does not overdraw a relevant route', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final relevantOnly = await _renderNetworkEdge(
        tileColor: const Color(0xFF52615D),
        showConnections: true,
      );
      final relevantWithAll = await _renderNetworkEdge(
        tileColor: const Color(0xFF52615D),
        showConnections: true,
        showAllNetworkConnections: true,
      );

      expect(
        relevantWithAll,
        relevantOnly,
        reason:
            'An edge promoted to the relevant tier must not retain a second '
            'neutral stroke underneath it.',
      );
    });
  });

  testWidgets('ordinary routes use a calm pale gray-green core', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await _renderNetworkEdge(
        tileColor: const Color(0xFF52615D),
        showConnections: true,
      );
      final offset = (128 * 256 + 128) * 4;
      final red = bytes[offset];
      final green = bytes[offset + 1];
      final blue = bytes[offset + 2];

      expect(green, greaterThan(red));
      expect(green, greaterThan(blue));
      expect(
        (red - blue).abs(),
        lessThan(35),
        reason:
            'Ordinary links should read as a neutral gray-green guide, not '
            'compete with the gold retained-route state.',
      );
    });
  });

  testWidgets(
    'retained, connect, and disconnect routes dominate neutral links',
    (tester) async {
      await tester.runAsync(() async {
        final rendered = <BdoNodeNetworkChangeKind, Uint8List>{};
        for (final kind in BdoNodeNetworkChangeKind.values) {
          rendered[kind] = await _renderNetworkEdge(
            tileColor: const Color(0xFF52615D),
            showAllNetworkConnections: true,
            edgeChanges: <BdoNodeNetworkEdgeChange>[
              BdoNodeNetworkEdgeChange(
                firstNodeId: 'first',
                secondNodeId: 'second',
                kind: kind,
              ),
            ],
          );
        }

        ({int red, int green, int blue}) colorAt(
          BdoNodeNetworkChangeKind kind,
        ) {
          final bytes = rendered[kind]!;
          final offset = (128 * 256 + 128) * 4;
          return (
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
          );
        }

        final retained = colorAt(BdoNodeNetworkChangeKind.retained);
        expect(retained.red - retained.blue, greaterThan(35));
        expect(retained.green - retained.blue, greaterThan(25));

        final connect = colorAt(BdoNodeNetworkChangeKind.connect);
        expect(connect.green - connect.red, greaterThan(45));
        expect(connect.green - connect.blue, greaterThan(20));

        final disconnect = colorAt(BdoNodeNetworkChangeKind.disconnect);
        expect(disconnect.red - disconnect.green, greaterThan(55));
        expect(disconnect.red - disconnect.blue, greaterThan(45));
      });
    },
  );

  testWidgets(
    'planned-network focus removes the neutral mesh without weakening the route',
    (tester) async {
      await tester.runAsync(() async {
        final focused = await _renderPlannedNetworkFocus(
          prioritizePlannedNetwork: true,
        );
        final ordinary = await _renderPlannedNetworkFocus(
          prioritizePlannedNetwork: false,
        );

        ({int red, int green, int blue}) colorAt(
          Uint8List bytes,
          int x,
          int y,
        ) {
          final offset = (y * 256 + x) * 4;
          return (
            red: bytes[offset],
            green: bytes[offset + 1],
            blue: bytes[offset + 2],
          );
        }

        int colorDistance(
          ({int red, int green, int blue}) first,
          ({int red, int green, int blue}) second,
        ) {
          return (first.red - second.red).abs() +
              (first.green - second.green).abs() +
              (first.blue - second.blue).abs();
        }

        final focusedNeutral = colorAt(focused, 128, 64);
        final ordinaryNeutral = colorAt(ordinary, 128, 64);
        expect(
          colorDistance(focusedNeutral, ordinaryNeutral),
          greaterThan(80),
          reason:
              'The ordinary cross-map connection must disappear behind an '
              'active recommendation instead of becoming a second web.',
        );

        final focusedRoute = colorAt(focused, 96, 160);
        expect(focusedRoute.green, greaterThan(150));
        expect(focusedRoute.green - focusedRoute.red, greaterThan(45));
        expect(focusedRoute.green - focusedRoute.blue, greaterThan(20));
      });
    },
  );

  testWidgets(
    'planned-network focus exposes towns and production sites instead of every junction',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'planned-node-priority-test',
          displayName: 'Planned node priority test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 0,
          worldUnitsAtZoomZero: 256,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF52615D));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(128, 128),
            zoom: 0,
          ),
        );
        const town = BdoWorkerNode(
          id: 'town',
          name: 'Worker town',
          nodeType: 'Town',
          region: 'Test',
          location: BdoWorldPoint(48, -128),
          contributionPoints: 0,
          linkIds: <String>['junction'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const junction = BdoWorkerNode(
          id: 'junction',
          name: 'Route junction',
          nodeType: 'Connection',
          region: 'Test',
          location: BdoWorldPoint(128, -128),
          contributionPoints: 1,
          linkIds: <String>['town', 'production'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const production = BdoWorkerNode(
          id: 'production',
          name: 'Useful mine',
          nodeType: 'Mining',
          region: 'Test',
          location: BdoWorldPoint(208, -128),
          contributionPoints: 1,
          linkIds: <String>['junction'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: true,
          isProductionNode: true,
        );
        const unrelated = BdoWorkerNode(
          id: 'unrelated',
          name: 'Unrelated node',
          nodeType: 'Connection',
          region: 'Test',
          location: BdoWorldPoint(128, -64),
          contributionPoints: 1,
          linkIds: <String>[],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const workerNodes = <BdoWorkerNode>[
          town,
          junction,
          production,
          unrelated,
        ];
        const workerNodesById = <String, BdoWorkerNode>{
          'town': town,
          'junction': junction,
          'production': production,
          'unrelated': unrelated,
        };
        const edges = <BdoNodeNetworkEdgeChange>[
          BdoNodeNetworkEdgeChange(
            firstNodeId: 'town',
            secondNodeId: 'junction',
            kind: BdoNodeNetworkChangeKind.connect,
          ),
          BdoNodeNetworkEdgeChange(
            firstNodeId: 'junction',
            secondNodeId: 'production',
            kind: BdoNodeNetworkChangeKind.connect,
          ),
        ];
        const kinds = <String, BdoNodeNetworkChangeKind>{
          'town': BdoNodeNetworkChangeKind.connect,
          'junction': BdoNodeNetworkChangeKind.connect,
          'production': BdoNodeNetworkChangeKind.connect,
        };

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.square(
              dimension: 256,
              child: BdoMapCanvas(
                cameraController: camera,
                tileManager: manager,
                workerNodes: workerNodes,
                workerNodesById: workerNodesById,
                gatheringSpots: const <BdoGatheringSpot>[],
                gatheringRoutes: const <BdoGatheringRoute>[],
                showConnections: true,
                showAllNetworkConnections: true,
                nodeNetworkEdgeChanges: edges,
                nodeNetworkChangeKinds: kinds,
                onHit: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        final customPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(BdoMapCanvas),
            matching: find.byType(CustomPaint),
          ),
        );
        final painter = customPaint.painter! as BdoMapPainter;
        final hitIds = painter.overlayLayout!.hitTargets
            .where((target) => target.hit.kind == BdoMapHitKind.workerNode)
            .map((target) => target.hit.id)
            .toSet();

        expect(hitIds, <String>{'town', 'production'});
        final mapSemantics = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').startsWith(
                'Interactive Black Desert resource map.',
              ),
        );
        expect(
          tester.widget<Semantics>(mapSemantics).properties.label,
          contains('2 worker nodes'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        camera.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );

  testWidgets('ordinary node selection never changes the map camera', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const source = BdoTileSource(
        id: 'selection-camera-test',
        displayName: 'Selection camera test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
        attribution: 'Generated test fixture',
        usageNotice: 'Generated test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      final tileImage = await _solidImage(const Color(0xFF52615D));
      final manager = _PainterTileManager(
        source: source,
        coordinate: coordinate,
        decodedTile: BdoDecodedTile(
          coordinate: coordinate,
          image: tileImage,
          decodedBytes: 256 * 256 * 4,
          loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          fromDisk: true,
        ),
      );
      final camera = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(
          center: BdoMapPoint(128, 128),
          zoom: 0,
        ),
      );
      const node = BdoWorkerNode(
        id: 'selectable-node',
        name: 'Selectable node',
        nodeType: 'Connection',
        region: 'Test',
        location: BdoWorldPoint(128, -128),
        contributionPoints: 1,
        linkIds: <String>[],
        outputs: <BdoNodeOutput>[],
        isResourceNode: false,
      );
      String? selectedNodeId;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox.square(
                dimension: 256,
                child: BdoMapCanvas(
                  cameraController: camera,
                  tileManager: manager,
                  workerNodes: const <BdoWorkerNode>[node],
                  workerNodesById: const <String, BdoWorkerNode>{
                    'selectable-node': node,
                  },
                  gatheringSpots: const <BdoGatheringSpot>[],
                  gatheringRoutes: const <BdoGatheringRoute>[],
                  showConnections: false,
                  selectedNodeId: selectedNodeId,
                  onHit: (hit) {
                    setState(() => selectedNodeId = hit.id);
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      final before = camera.camera;

      tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .onHit(
            const BdoMapHit(
              kind: BdoMapHitKind.workerNode,
              id: 'selectable-node',
            ),
          );
      await tester.pump();

      expect(selectedNodeId, node.id);
      expect(camera.camera.center, before.center);
      expect(camera.camera.zoom, before.zoom);

      await tester.pumpWidget(const SizedBox.shrink());
      camera.dispose();
      manager.dispose();
      tileImage.dispose();
    });
  });

  testWidgets(
    'pure pan with search emphasis does not rebuild its dense painter',
    (tester) async {
      await tester.runAsync(() async {
        const source = BdoTileSource(
          id: 'pan-repaint-test',
          displayName: 'Pan repaint test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
          attribution: 'Generated test fixture',
          usageNotice: 'Generated test fixture',
          minimumZoom: 0,
          maximumZoom: 0,
          worldUnitsAtZoomZero: 256,
          fileExtension: 'png',
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        final tileImage = await _solidImage(const Color(0xFF52615D));
        final manager = _PainterTileManager(
          source: source,
          coordinate: coordinate,
          decodedTile: BdoDecodedTile(
            coordinate: coordinate,
            image: tileImage,
            decodedBytes: 256 * 256 * 4,
            loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            fromDisk: true,
          ),
        );
        final camera = BdoMapCameraController(
          tileSource: source,
          initialCamera: const BdoMapCamera(
            center: BdoMapPoint(128, 128),
            zoom: 0,
          ),
        );
        const node = BdoWorkerNode(
          id: 'pan-target',
          name: 'Pan target',
          nodeType: 'Town',
          region: 'Test',
          location: BdoWorldPoint(128, -128),
          contributionPoints: 0,
          linkIds: <String>['pan-production'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: false,
        );
        const production = BdoWorkerNode(
          id: 'pan-production',
          name: 'Pan production',
          nodeType: 'Mining',
          region: 'Test',
          location: BdoWorldPoint(220, -128),
          contributionPoints: 1,
          linkIds: <String>['pan-target'],
          outputs: <BdoNodeOutput>[],
          isResourceNode: true,
          isProductionNode: true,
        );
        BdoMapHit? hit;

        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.square(
                dimension: 256,
                child: BdoMapCanvas(
                  cameraController: camera,
                  tileManager: manager,
                  workerNodes: const <BdoWorkerNode>[node, production],
                  workerNodesById: const <String, BdoWorkerNode>{
                    'pan-target': node,
                    'pan-production': production,
                  },
                  gatheringSpots: const <BdoGatheringSpot>[],
                  gatheringRoutes: const <BdoGatheringRoute>[],
                  emphasizedNodeIds: const <String>{'pan-target'},
                  nodeNetworkEdgeChanges: const <BdoNodeNetworkEdgeChange>[
                    BdoNodeNetworkEdgeChange(
                      firstNodeId: 'pan-target',
                      secondNodeId: 'pan-production',
                      kind: BdoNodeNetworkChangeKind.connect,
                    ),
                  ],
                  nodeNetworkChangeKinds:
                      const <String, BdoNodeNetworkChangeKind>{
                        'pan-target': BdoNodeNetworkChangeKind.connect,
                        'pan-production': BdoNodeNetworkChangeKind.connect,
                      },
                  showConnections: false,
                  onHit: (value) => hit = value,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        BdoMapPainter currentPainter() {
          return tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(BdoMapCanvas),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is CustomPaint &&
                            widget.painter is BdoMapPainter,
                      ),
                    ),
                  )
                  .painter!
              as BdoMapPainter;
        }

        final painterBeforePan = currentPainter();
        final layoutBeforePan = painterBeforePan.overlayLayoutProvider!.call();
        expect(layoutBeforePan.nodeClusters, hasLength(2));
        camera.panBy(const Offset(32, 0), const Size.square(256));
        await tester.pump();

        expect(currentPainter(), same(painterBeforePan));
        expect(
          currentPainter().overlayLayoutProvider!.call(),
          same(layoutBeforePan),
          reason: 'A fixed-zoom planned route must not recluster on pure pan.',
        );
        final localTarget = camera.worldToScreen(
          node.location.mapPoint,
          const Size.square(256),
        );
        final movedTarget = currentPainter().overlayLayoutProvider!
            .call()
            .hitTest(localTarget);
        expect(movedTarget?.hit.id, node.id);
        expect(hit, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        camera.dispose();
        manager.dispose();
        tileImage.dispose();
      });
    },
  );
}

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  picture.dispose();
  return image;
}

Future<Uint8List> _renderPainter(
  BdoMapPainter painter, {
  Size size = const Size.square(256),
}) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return Uint8List.fromList(bytes);
}

(int, int)? _greenRouteSpan(
  Uint8List bytes, {
  required int width,
  required int row,
}) {
  int? first;
  int? last;
  for (var x = 0; x < width; x += 1) {
    final offset = (row * width + x) * 4;
    final red = bytes[offset];
    final green = bytes[offset + 1];
    final blue = bytes[offset + 2];
    if (green > 170 && green > red + 45 && green > blue + 25) {
      first ??= x;
      last = x;
    }
  }
  if (first == null || last == null) {
    return null;
  }
  return (first, last);
}

Future<Uint8List> _renderNetworkEdge({
  required Color tileColor,
  bool showConnections = false,
  bool showAllNetworkConnections = false,
  List<BdoNodeNetworkEdgeChange> edgeChanges =
      const <BdoNodeNetworkEdgeChange>[],
}) async {
  const source = BdoTileSource(
    id: 'network-edge-test',
    displayName: 'Network edge test',
    urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
    worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
    attribution: 'Generated test fixture',
    usageNotice: 'Generated test fixture',
    minimumZoom: 0,
    maximumZoom: 0,
    worldUnitsAtZoomZero: 256,
    fileExtension: 'png',
  );
  const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
  final tileImage = await _solidImage(tileColor);
  final manager = _PainterTileManager(
    source: source,
    coordinate: coordinate,
    decodedTile: BdoDecodedTile(
      coordinate: coordinate,
      image: tileImage,
      decodedBytes: 256 * 256 * 4,
      loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
      fromDisk: true,
    ),
  );
  final camera = BdoMapCameraController(
    tileSource: source,
    initialCamera: const BdoMapCamera(center: BdoMapPoint(128, 128), zoom: 0),
  );
  const first = BdoWorkerNode(
    id: 'first',
    name: 'First',
    nodeType: 'Town',
    region: 'Test',
    location: BdoWorldPoint(64, -128),
    contributionPoints: 0,
    linkIds: <String>['second'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: false,
  );
  const second = BdoWorkerNode(
    id: 'second',
    name: 'Second',
    nodeType: 'Connection',
    region: 'Test',
    location: BdoWorldPoint(192, -128),
    contributionPoints: 1,
    linkIds: <String>['first'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: false,
  );
  final painter = BdoMapPainter(
    cameraController: camera,
    tileManager: manager,
    workerNodes: const <BdoWorkerNode>[first, second],
    workerNodesById: const <String, BdoWorkerNode>{
      'first': first,
      'second': second,
    },
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
    showConnections: showConnections,
    showAllNetworkConnections: showAllNetworkConnections,
    nodeNetworkEdgeChanges: edgeChanges,
    selectedNodeId: null,
    selectedSpotId: null,
    selectedRouteId: null,
    colorScheme: const ColorScheme.dark(),
  );

  final bytes = await _renderPainter(painter);
  camera.dispose();
  manager.dispose();
  tileImage.dispose();
  return bytes;
}

Future<Uint8List> _renderPlannedNetworkFocus({
  required bool prioritizePlannedNetwork,
}) async {
  const source = BdoTileSource(
    id: 'planned-network-focus-test',
    displayName: 'Planned network focus test',
    urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
    worldBounds: BdoMapBounds(left: 0, top: 0, right: 256, bottom: 256),
    attribution: 'Generated test fixture',
    usageNotice: 'Generated test fixture',
    minimumZoom: 0,
    maximumZoom: 0,
    worldUnitsAtZoomZero: 256,
    fileExtension: 'png',
  );
  const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
  final tileImage = await _solidImage(const Color(0xFF52615D));
  final manager = _PainterTileManager(
    source: source,
    coordinate: coordinate,
    decodedTile: BdoDecodedTile(
      coordinate: coordinate,
      image: tileImage,
      decodedBytes: 256 * 256 * 4,
      loadedAt: DateTime.now().subtract(const Duration(seconds: 1)),
      fromDisk: true,
    ),
  );
  final camera = BdoMapCameraController(
    tileSource: source,
    initialCamera: const BdoMapCamera(center: BdoMapPoint(128, 128), zoom: 0),
  );
  const town = BdoWorkerNode(
    id: 'town',
    name: 'Worker town',
    nodeType: 'Town',
    region: 'Test',
    location: BdoWorldPoint(48, -160),
    contributionPoints: 0,
    linkIds: <String>['junction'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: false,
  );
  const junction = BdoWorkerNode(
    id: 'junction',
    name: 'Route junction',
    nodeType: 'Connection',
    region: 'Test',
    location: BdoWorldPoint(128, -160),
    contributionPoints: 1,
    linkIds: <String>['town', 'production'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: false,
  );
  const production = BdoWorkerNode(
    id: 'production',
    name: 'Useful mine',
    nodeType: 'Mining',
    region: 'Test',
    location: BdoWorldPoint(208, -160),
    contributionPoints: 1,
    linkIds: <String>['junction'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: true,
    isProductionNode: true,
  );
  const unrelatedFirst = BdoWorkerNode(
    id: 'unrelated-first',
    name: 'Unrelated first',
    nodeType: 'Connection',
    region: 'Test',
    location: BdoWorldPoint(48, -64),
    contributionPoints: 1,
    linkIds: <String>['unrelated-second'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: false,
  );
  const unrelatedSecond = BdoWorkerNode(
    id: 'unrelated-second',
    name: 'Unrelated second',
    nodeType: 'Connection',
    region: 'Test',
    location: BdoWorldPoint(208, -64),
    contributionPoints: 1,
    linkIds: <String>['unrelated-first'],
    outputs: <BdoNodeOutput>[],
    isResourceNode: false,
  );
  const workerNodes = <BdoWorkerNode>[
    town,
    junction,
    production,
    unrelatedFirst,
    unrelatedSecond,
  ];
  const workerNodesById = <String, BdoWorkerNode>{
    'town': town,
    'junction': junction,
    'production': production,
    'unrelated-first': unrelatedFirst,
    'unrelated-second': unrelatedSecond,
  };
  const edges = <BdoNodeNetworkEdgeChange>[
    BdoNodeNetworkEdgeChange(
      firstNodeId: 'town',
      secondNodeId: 'junction',
      kind: BdoNodeNetworkChangeKind.connect,
    ),
    BdoNodeNetworkEdgeChange(
      firstNodeId: 'junction',
      secondNodeId: 'production',
      kind: BdoNodeNetworkChangeKind.connect,
    ),
  ];
  const kinds = <String, BdoNodeNetworkChangeKind>{
    'town': BdoNodeNetworkChangeKind.connect,
    'junction': BdoNodeNetworkChangeKind.connect,
    'production': BdoNodeNetworkChangeKind.connect,
  };
  final painter = BdoMapPainter(
    cameraController: camera,
    tileManager: manager,
    workerNodes: workerNodes,
    workerNodesById: workerNodesById,
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
    showConnections: true,
    showAllNetworkConnections: true,
    nodeNetworkEdgeChanges: edges,
    nodeNetworkChangeKinds: kinds,
    prioritizePlannedNetwork: prioritizePlannedNetwork,
    selectedNodeId: null,
    selectedSpotId: null,
    selectedRouteId: null,
    colorScheme: const ColorScheme.dark(),
  );

  final bytes = await _renderPainter(painter);
  camera.dispose();
  manager.dispose();
  tileImage.dispose();
  return bytes;
}

class _PainterTileManager extends BdoTileManager {
  _PainterTileManager({
    required super.source,
    required this.coordinate,
    required this.decodedTile,
  }) : super(
         diskCache: BdoMapDiskCache(
           rootDirectory: Directory.systemTemp,
           sourceNamespace: 'bdo-map-painter-test-unused',
         ),
       );

  final BdoTileCoordinate coordinate;
  final BdoDecodedTile decodedTile;

  @override
  void updateViewport({
    required BdoMapBounds visibleBounds,
    required int zoom,
    int prefetchRing = 1,
  }) {}

  @override
  Set<BdoTileCoordinate> get visibleCoordinates => <BdoTileCoordinate>{
    coordinate,
  };

  @override
  BdoDecodedTile? tile(BdoTileCoordinate requested) {
    return requested == coordinate ? decodedTile : null;
  }

  @override
  BdoDecodedTile? nearestAncestor(BdoTileCoordinate requested) => null;
}

class _NotifyingPainterTileManager extends _PainterTileManager {
  _NotifyingPainterTileManager({
    required super.source,
    required super.coordinate,
    required super.decodedTile,
  });

  int _decodedCount = 0;
  int _decodedRevision = 0;

  @override
  int get decodedTileCount => _decodedCount;

  @override
  int get decodedTileRevision => _decodedRevision;

  void notifyStatusOnly() {
    notifyListeners();
  }

  void publishDecodedTile() {
    _decodedCount = 1;
    _decodedRevision += 1;
    notifyListeners();
  }
}
