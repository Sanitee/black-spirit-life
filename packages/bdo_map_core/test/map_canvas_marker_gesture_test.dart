import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/src/engine/map_camera.dart';
import 'package:bdo_map_core/src/engine/tile_cache.dart';
import 'package:bdo_map_core/src/engine/tile_manager.dart';
import 'package:bdo_map_core/src/model/map_geometry.dart';
import 'package:bdo_map_core/src/model/resource_map_data.dart';
import 'package:bdo_map_core/src/model/tile_source.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _markerKey = ValueKey<String>('gesture-test-marker');
const _markerLabel = 'Open overlaid node';
const _viewport = Size(800, 600);

void main() {
  for (final kind in <PointerDeviceKind>[
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
  ]) {
    testWidgets(
      '${kind.name} drag beginning on a marker pans without selecting',
      (tester) async {
        final fixture = await _mountCanvas(tester);
        final before = fixture.camera.camera;
        final start = tester.getCenter(find.byKey(_markerKey));
        final gesture = await tester.startGesture(start, kind: kind);

        await gesture.moveBy(const Offset(35, 12));
        await tester.pump();
        await gesture.moveBy(const Offset(110, 45));
        await tester.pump();
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 350));

        expect(fixture.camera.camera.center.x, lessThan(before.center.x));
        expect(fixture.camera.camera.center.y, lessThan(before.center.y));
        expect(fixture.camera.camera.zoom, before.zoom);
        fixture.expectNoSelection();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${kind.name} marker tap calls only its own action immediately',
      (tester) async {
        final fixture = await _mountCanvas(tester);
        final before = fixture.camera.camera;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_markerKey)),
          kind: kind,
        );
        await gesture.up();
        // Do not advance the double-tap timeout: a marker's single action must
        // not inherit the background canvas's double-click recognizer.
        await tester.pump();

        expect(fixture.markerTaps, 1);
        expect(fixture.hits, isEmpty);
        expect(fixture.emptyTaps, 0);
        expect(fixture.camera.camera.center, before.center);
        expect(fixture.camera.camera.zoom, before.zoom);
      },
    );
  }

  testWidgets('blank canvas drag still pans with overlaid markers present', (
    tester,
  ) async {
    final fixture = await _mountCanvas(tester);
    final before = fixture.camera.camera;
    final gesture = await tester.startGesture(
      const Offset(80, 440),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(100, -40));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(fixture.camera.camera.center.x, lessThan(before.center.x));
    expect(fixture.camera.camera.center.y, greaterThan(before.center.y));
    expect(fixture.camera.camera.zoom, before.zoom);
    fixture.expectNoSelection();
  });

  testWidgets(
    'wheel over a marker zooms around the pointer without selecting',
    (tester) async {
      final fixture = await _mountCanvas(tester);
      final pointer =
          tester.getCenter(find.byKey(_markerKey)) + const Offset(30, 8);
      final anchor = fixture.camera.screenToWorld(pointer, _viewport);
      final beforeZoom = fixture.camera.camera.zoom;

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: pointer,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();

      expect(fixture.camera.camera.zoom, closeTo(beforeZoom + .5, .001));
      final afterAnchor = fixture.camera.screenToWorld(pointer, _viewport);
      expect(afterAnchor.x, closeTo(anchor.x, .001));
      expect(afterAnchor.y, closeTo(anchor.y, .001));
      fixture.expectNoSelection();
    },
  );

  testWidgets('pinch beginning on a marker zooms without firing its tap', (
    tester,
  ) async {
    final fixture = await _mountCanvas(tester);
    final center = tester.getCenter(find.byKey(_markerKey));
    final beforeZoom = fixture.camera.camera.zoom;
    final first = await tester.startGesture(
      center - const Offset(24, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(24, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(50, 0));
    await second.moveTo(center + const Offset(50, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(90, 0));
    await second.moveTo(center + const Offset(90, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 350));

    expect(fixture.camera.camera.zoom, greaterThan(beforeZoom + .5));
    fixture.expectNoSelection();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated marker clicks do not trigger background double-click zoom',
    (tester) async {
      final fixture = await _mountCanvas(tester);
      final beforeZoom = fixture.camera.camera.zoom;
      final center = tester.getCenter(find.byKey(_markerKey));

      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 75));
      expect(fixture.markerTaps, 1);
      await tester.tapAt(center);
      await tester.pump();

      expect(fixture.markerTaps, 2);
      expect(fixture.camera.camera.zoom, beforeZoom);
      expect(fixture.hits, isEmpty);
      expect(fixture.emptyTaps, 0);
    },
  );

  testWidgets('background double-click still zooms without empty selection', (
    tester,
  ) async {
    final fixture = await _mountCanvas(tester);
    final beforeZoom = fixture.camera.camera.zoom;

    await tester.tapAt(const Offset(100, 420));
    await tester.pump(const Duration(milliseconds: 75));
    await tester.tapAt(const Offset(100, 420));
    await tester.pump(const Duration(milliseconds: 350));

    expect(fixture.camera.camera.zoom, closeTo(beforeZoom + 1, .001));
    fixture.expectNoSelection();
  });

  testWidgets(
    'background tap retains painted-node and empty-map hit handling',
    (tester) async {
      final fixture = await _mountCanvas(tester, includeMarker: false);
      expect(
        tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas)).markerOverlays,
        isEmpty,
      );

      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 350));
      expect(fixture.hits, hasLength(1));
      expect(fixture.hits.single.id, _node.id);
      expect(fixture.emptyTaps, 0);

      await tester.tapAt(const Offset(100, 420));
      await tester.pump(const Duration(milliseconds: 350));
      expect(fixture.hits, hasLength(1));
      expect(fixture.emptyTaps, 1);
      expect(fixture.markerTaps, 0);
    },
  );

  testWidgets('marker and map retain separate accessible actions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      final fixture = await _mountCanvas(tester);

      final marker = tester.getSemantics(find.bySemanticsLabel(_markerLabel));
      expect(marker.flagsCollection.isButton, isTrue);
      expect(
        marker.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue,
      );

      final map = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Interactive Black Desert resource map')),
      );
      expect(map.id, isNot(marker.id));
      expect(
        map.getSemanticsData().hasAction(ui.SemanticsAction.increase),
        isTrue,
      );
      expect(
        map.getSemanticsData().hasAction(ui.SemanticsAction.decrease),
        isTrue,
      );

      tester.binding.platformDispatcher.onSemanticsActionEvent!(
        ui.SemanticsActionEvent(
          type: ui.SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: marker.id,
        ),
      );
      await tester.pump();
      expect(fixture.markerTaps, 1);
      expect(fixture.hits, isEmpty);
      expect(fixture.emptyTaps, 0);

      final beforeZoom = fixture.camera.camera.zoom;
      tester.binding.platformDispatcher.onSemanticsActionEvent!(
        ui.SemanticsActionEvent(
          type: ui.SemanticsAction.increase,
          viewId: tester.view.viewId,
          nodeId: map.id,
        ),
      );
      await tester.pump();
      expect(fixture.camera.camera.zoom, closeTo(beforeZoom + .7, .001));
      expect(fixture.markerTaps, 1);
    } finally {
      semanticsHandle.dispose();
    }
  });
}

const _source = BdoTileSource(
  id: 'marker-gesture-test',
  displayName: 'Isolated marker gesture fixture',
  urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
  worldBounds: BdoMapBounds(left: -2000, top: -2000, right: 2000, bottom: 2000),
  attribution: 'Test fixture',
  usageNotice: 'Test fixture',
  worldUnitsAtZoomZero: 4000,
);

const _node = BdoWorkerNode(
  id: 'underlying-node',
  name: 'Underlying node',
  nodeType: 'Mining',
  region: 'Test',
  location: BdoWorldPoint(0, 0),
  contributionPoints: 1,
  linkIds: <String>[],
  outputs: <BdoNodeOutput>[],
  isResourceNode: true,
);

Future<_CanvasFixture> _mountCanvas(
  WidgetTester tester, {
  bool includeMarker = true,
}) async {
  await tester.binding.setSurfaceSize(_viewport);
  final fixture = _CanvasFixture();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.camera.dispose();
    fixture.tiles.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: BdoMapCanvas(
        cameraController: fixture.camera,
        tileManager: fixture.tiles,
        workerNodes: const <BdoWorkerNode>[_node],
        workerNodesById: const <String, BdoWorkerNode>{
          'underlying-node': _node,
        },
        gatheringSpots: const <BdoGatheringSpot>[],
        gatheringRoutes: const <BdoGatheringRoute>[],
        showConnections: false,
        onHit: fixture.hits.add,
        onEmptyTap: () => fixture.emptyTaps += 1,
        markerOverlays: <Widget>[
          if (includeMarker)
            Positioned(
              left: 320,
              top: 270,
              width: 160,
              height: 60,
              child: Semantics(
                button: true,
                label: _markerLabel,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: _markerKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => fixture.markerTaps += 1,
                    child: const ColoredBox(
                      color: Color(0xAA102829),
                      child: Center(
                        child: ExcludeSemantics(child: Text('Overlay node')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  await tester.pump();
  return fixture;
}

class _CanvasFixture {
  final camera = BdoMapCameraController(
    tileSource: _source,
    initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 3),
  );
  final tiles = _InertTileManager();
  final hits = <BdoMapHit>[];
  int emptyTaps = 0;
  int markerTaps = 0;

  void expectNoSelection() {
    expect(
      markerTaps,
      0,
      reason: 'Dragging/zooming must not select the overlay.',
    );
    expect(
      hits,
      isEmpty,
      reason: 'The painted node below must not be selected.',
    );
    expect(emptyTaps, 0, reason: 'Dragging/zooming must not clear selection.');
  }
}

// Gesture tests do not need decoded map tiles. Keeping viewport requests inert
// also prevents disk or HTTP activity from obscuring gesture timing assertions.
class _InertTileManager extends BdoTileManager {
  _InertTileManager()
    : super(
        source: _source,
        diskCache: BdoMapDiskCache(
          rootDirectory: Directory.systemTemp,
          sourceNamespace: 'marker-gesture-test-unused',
        ),
      );

  @override
  void updateViewport({
    required BdoMapBounds visibleBounds,
    required int zoom,
    int prefetchRing = 1,
  }) {}
}
