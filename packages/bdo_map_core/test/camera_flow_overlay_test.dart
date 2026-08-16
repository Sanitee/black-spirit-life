import 'package:bdo_map_core/src/engine/map_camera.dart';
import 'package:bdo_map_core/src/model/map_geometry.dart';
import 'package:bdo_map_core/src/model/tile_source.dart';
import 'package:bdo_map_core/src/widgets/camera_flow_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewport = Size(300, 200);

void main() {
  const worldPoint = BdoMapPoint(20, 0);
  const source = BdoTileSource(
    id: 'camera-flow-test',
    displayName: 'Camera flow test',
    urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
    worldBounds: BdoMapBounds(
      left: -1000,
      top: -1000,
      right: 1000,
      bottom: 1000,
    ),
    attribution: 'Test fixture',
    usageNotice: 'Test fixture',
    maximumZoom: 4,
    worldUnitsAtZoomZero: 256,
    fileExtension: 'png',
  );

  testWidgets('lays children out loosely at their requested size', (
    tester,
  ) async {
    final cameraController = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(center: BdoMapPoint.zero, zoom: 0),
    );
    addTearDown(cameraController.dispose);

    await tester.pumpWidget(
      _TestOverlay(
        cameraController: cameraController,
        point: worldPoint,
        onTap: () {},
      ),
    );

    expect(tester.getSize(find.byKey(_markerKey)), const Size(40, 30));
    expect(
      tester.getCenter(find.byKey(_markerKey)),
      tester.getTopLeft(find.byKey(_flowKey)) + const Offset(170, 100),
    );
  });

  testWidgets('repainted camera transforms remain hit-testable after pan', (
    tester,
  ) async {
    var tapCount = 0;
    final cameraController = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(center: BdoMapPoint.zero, zoom: 0),
    );
    addTearDown(cameraController.dispose);

    await tester.pumpWidget(
      _TestOverlay(
        cameraController: cameraController,
        point: worldPoint,
        onTap: () => tapCount += 1,
      ),
    );
    final flowTopLeft = tester.getTopLeft(find.byKey(_flowKey));
    final oldCenter = flowTopLeft + const Offset(170, 100);

    await tester.tapAt(oldCenter);
    expect(tapCount, 1);

    cameraController.panBy(const Offset(50, 0), _viewport);
    await tester.pump();

    await tester.tapAt(oldCenter);
    expect(tapCount, 1);

    await tester.tapAt(flowTopLeft + const Offset(220, 100));
    expect(tapCount, 2);
  });

  testWidgets(
    'pure camera changes reposition a retained child without rebuilding it',
    (tester) async {
      var markerBuildCount = 0;
      final cameraController = BdoMapCameraController(
        tileSource: source,
        initialCamera: const BdoMapCamera(center: BdoMapPoint.zero, zoom: 0),
      );
      addTearDown(cameraController.dispose);

      await tester.pumpWidget(
        _TestOverlay(
          cameraController: cameraController,
          point: worldPoint,
          onTap: () {},
          onMarkerBuild: () => markerBuildCount += 1,
        ),
      );
      expect(markerBuildCount, 1);
      expect(
        tester.getCenter(find.byKey(_markerKey)),
        tester.getTopLeft(find.byKey(_flowKey)) + const Offset(170, 100),
      );

      cameraController.panBy(const Offset(50, 0), _viewport);
      await tester.pump();

      expect(markerBuildCount, 1);
      expect(
        tester.getCenter(find.byKey(_markerKey)),
        tester.getTopLeft(find.byKey(_flowKey)) + const Offset(220, 100),
      );

      cameraController.setCamera(
        const BdoMapCamera(center: BdoMapPoint.zero, zoom: 1),
        _viewport,
      );
      await tester.pump();

      expect(markerBuildCount, 1);
      expect(
        tester.getCenter(find.byKey(_markerKey)),
        tester.getTopLeft(find.byKey(_flowKey)) + const Offset(190, 100),
        reason:
            'Zoom must invalidate the camera transform without rebuilding '
            'the retained marker subtree.',
      );
    },
  );

  testWidgets('changed overlay data invalidates the retained projection', (
    tester,
  ) async {
    var markerBuildCount = 0;
    final cameraController = BdoMapCameraController(
      tileSource: source,
      initialCamera: const BdoMapCamera(center: BdoMapPoint.zero, zoom: 1),
    );
    addTearDown(cameraController.dispose);

    Widget overlayAt(BdoMapPoint point) => _TestOverlay(
      cameraController: cameraController,
      point: point,
      onTap: () {},
      onMarkerBuild: () => markerBuildCount += 1,
    );

    await tester.pumpWidget(overlayAt(worldPoint));
    expect(markerBuildCount, 1);
    expect(
      tester.getCenter(find.byKey(_markerKey)),
      tester.getTopLeft(find.byKey(_flowKey)) + const Offset(190, 100),
    );

    await tester.pumpWidget(overlayAt(const BdoMapPoint(40, 0)));

    expect(markerBuildCount, 2);
    expect(
      tester.getCenter(find.byKey(_markerKey)),
      tester.getTopLeft(find.byKey(_flowKey)) + const Offset(230, 100),
      reason:
          'Replacing overlay data must repaint the retained child at the new '
          'world point.',
    );
  });
}

const _flowKey = ValueKey<String>('camera-flow');
const _markerKey = ValueKey<String>('camera-flow-marker');

class _TestOverlay extends StatelessWidget {
  const _TestOverlay({
    required this.cameraController,
    required this.point,
    required this.onTap,
    this.onMarkerBuild,
  });

  final BdoMapCameraController cameraController;
  final BdoMapPoint point;
  final VoidCallback onTap;
  final VoidCallback? onMarkerBuild;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            key: _flowKey,
            width: _viewport.width,
            height: _viewport.height,
            child: Flow(
              delegate: _TestCameraFlowDelegate(
                cameraController: cameraController,
                point: point,
              ),
              children: <Widget>[
                _CountingMarker(onBuild: onMarkerBuild, onTap: onTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountingMarker extends StatelessWidget {
  const _CountingMarker({required this.onTap, this.onBuild});

  final VoidCallback onTap;
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild?.call();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(key: _markerKey, width: 40, height: 30),
    );
  }
}

class _TestCameraFlowDelegate extends BdoMapCameraFlowDelegate {
  _TestCameraFlowDelegate({
    required super.cameraController,
    required this.point,
  });

  final BdoMapPoint point;

  @override
  void paintChildren(FlowPaintingContext context) {
    final size = childSize(context, 0);
    final center = worldToScreen(context, point);
    paintChildAt(
      context,
      0,
      topLeft: center - Offset(size.width / 2, size.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TestCameraFlowDelegate oldDelegate) =>
      super.shouldRepaint(oldDelegate) || oldDelegate.point != point;
}
