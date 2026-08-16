import 'dart:ui';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Size(1200, 800);

  test('screen/world conversion round-trips', () {
    final controller = BdoMapCameraController(
      tileSource: BdoTileSource.workermanCommunity,
      initialCamera: const BdoMapCamera(
        center: BdoMapPoint(12000, -35000),
        zoom: 4.3,
      ),
    );
    const world = BdoMapPoint(-87500, 214000);

    final screen = controller.worldToScreen(world, viewport);
    final roundTrip = controller.screenToWorld(screen, viewport);

    expect(roundTrip.x, closeTo(world.x, 0.0001));
    expect(roundTrip.y, closeTo(world.y, 0.0001));
  });

  test('pointer-anchored zoom preserves the world point under the pointer', () {
    final controller = BdoMapCameraController(
      tileSource: BdoTileSource.workermanCommunity,
      initialCamera: const BdoMapCamera(center: BdoMapPoint.zero, zoom: 2),
    );
    const pointer = Offset(233, 617);
    final before = controller.screenToWorld(pointer, viewport);

    controller.zoomAround(zoom: 5.25, anchor: pointer, viewport: viewport);
    final after = controller.screenToWorld(pointer, viewport);

    expect(after.x, closeTo(before.x, 0.0001));
    expect(after.y, closeTo(before.y, 0.0001));
  });

  test('interactive zoom supports two close-inspection overzoom levels', () {
    final controller = BdoMapCameraController(
      tileSource: BdoTileSource.workermanCommunity,
      initialCamera: const BdoMapCamera(center: BdoMapPoint.zero, zoom: 7),
    );
    addTearDown(controller.dispose);
    const pointer = Offset(233, 617);
    final before = controller.screenToWorld(pointer, viewport);

    controller.zoomAround(zoom: 99, anchor: pointer, viewport: viewport);

    expect(controller.maximumZoom, 9);
    expect(controller.camera.zoom, controller.maximumZoom);
    final after = controller.screenToWorld(pointer, viewport);
    expect(after.x, closeTo(before.x, 0.0001));
    expect(after.y, closeTo(before.y, 0.0001));
  });

  test('fit bounds centers content inside asymmetric viewport insets', () {
    const source = BdoTileSource(
      id: 'inset-test',
      displayName: 'Inset test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoMapBounds(
        left: -10000,
        top: -10000,
        right: 10000,
        bottom: 10000,
      ),
      attribution: 'Test fixture',
      usageNotice: 'Test fixture',
      maximumZoom: 8,
      worldUnitsAtZoomZero: 1000,
      fileExtension: 'png',
    );
    final controller = BdoMapCameraController(tileSource: source);
    const content = BdoMapBounds(
      left: -500,
      top: -300,
      right: 500,
      bottom: 300,
    );

    controller.fitBounds(
      content,
      viewport: viewport,
      padding: 50,
      insetRight: 400,
    );

    final contentCenter = controller.worldToScreen(content.center, viewport);
    expect(contentCenter.dx, closeTo(400, 0.001));
    expect(contentCenter.dy, closeTo(400, 0.001));
  });

  test(
    'fit bounds respects a provider minimum above its requested maximum',
    () {
      const source = BdoTileSource(
        id: 'minimum-zoom-test',
        displayName: 'Minimum zoom test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 1000, bottom: 1000),
        attribution: 'Test fixture',
        usageNotice: 'Test fixture',
        minimumZoom: 3,
        maximumZoom: 6,
        worldUnitsAtZoomZero: 1000,
        fileExtension: 'png',
      );
      final controller = BdoMapCameraController(tileSource: source);

      controller.fitBounds(
        source.worldBounds,
        viewport: viewport,
        maximumZoom: 1,
      );

      expect(controller.camera.zoom, 3);
    },
  );
}
