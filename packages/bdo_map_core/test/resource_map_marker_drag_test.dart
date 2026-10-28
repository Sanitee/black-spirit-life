import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BdoResourceMapDataset dataset;
  late Directory cacheDirectory;
  late MockClient tileClient;
  final preferenceChanges = <BdoNodeNetworkPreferences>[];

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp('bdo_marker_drag_');
    tileClient = MockClient(
      (_) async => http.Response('', HttpStatus.notFound),
    );
  });
  setUp(preferenceChanges.clear);
  tearDownAll(() async {
    tileClient.close();
    await cacheDirectory.delete(recursive: true);
  });

  Future<void> openMap(
    WidgetTester tester, {
    ResourceMapInterfaceStyle style = ResourceMapInterfaceStyle.glassDock,
    BdoNodeNetworkPreferences? preferences,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: ResourceMapChromeTheme(
            data: style == ResourceMapInterfaceStyle.glassDock
                ? ResourceMapChromeThemeData.glassDock
                : ResourceMapChromeThemeData.ghostLedger,
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              interfaceStyle: style,
              nodeNetworkPreferences: preferences,
              onNodeNetworkPreferencesChanged: preferenceChanges.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final style in ResourceMapInterfaceStyle.values) {
    testWidgets('${style.id}: a clean map shows task markers only and Invest '
        'temporarily reveals the graph', (tester) async {
      await openMap(tester, style: style);
      final orientationMarkers = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'resource-map-orientation-node-',
            ),
      );
      expect(_canvas(tester).workerNodes, isEmpty);
      expect(_canvas(tester).showAllNetworkConnections, isFalse);
      expect(orientationMarkers, findsNothing);
      expect(preferenceChanges, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('resource-map-home-more-tools')),
      );
      await tester.pumpAndSettle();
      final setup = find.byKey(const ValueKey('resource-map-home-setup'));
      await tester.ensureVisible(setup);
      await tester.tap(setup);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('resource-map-invest-node-mode')),
      );
      await tester.pumpAndSettle();
      expect(_canvas(tester).showAllNetworkConnections, isTrue);
      expect(orientationMarkers, findsWidgets);
      expect(
        preferenceChanges,
        isEmpty,
        reason: 'Entering Invest must not save an all-world Layers choice.',
      );

      await tester.tap(find.byTooltip('Close task'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resource-map-home-find-material')),
        findsOneWidget,
      );
      expect(_canvas(tester).showAllNetworkConnections, isFalse);
      expect(orientationMarkers, findsNothing);
      expect(preferenceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.id}: mouse drag beginning on a real town label moves '
        'the map and clicking still opens the town', (tester) async {
      await openMap(tester, style: style);
      final town = dataset.workerNodes.firstWhere(
        (node) => node.nodeType == 'City',
      );
      await _centerOn(tester, town);
      final marker = find.byKey(ValueKey('resource-map-landmark-${town.id}'));
      final label = find.descendant(
        of: marker,
        matching: find.text(town.siteName),
      );
      expect(marker, findsOneWidget);
      expect(label, findsOneWidget);
      final before = _canvas(tester).cameraController.camera;
      await _dragFrom(tester, tester.getCenter(label));
      _expectPannedWithoutSelection(tester, before);
      expect(
        find.byKey(const ValueKey('resource-map-home-find-material')),
        findsOneWidget,
      );
      expect(preferenceChanges, isEmpty);

      // A label remains clickable after dragging. Zoom in to separate Velia's
      // label from the neighboring real production markers used by the dense
      // overview; the drag itself is exercised at overview zoom above.
      await _centerOn(tester, town, zoom: 7);
      final clickStart = _pointOn(tester, marker, content: label);
      final beforeClick = _canvas(tester).cameraController.camera;
      await _mouseClick(tester, clickStart, jitter: const Offset(.25, .25));
      expect(_canvas(tester).selectedNodeId, town.id);
      expect(
        find.byKey(const ValueKey('resource-map-home-find-material')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('resource-map-sidebar-details')),
        findsOneWidget,
      );
      expect(
        _canvas(tester).cameraController.camera.center,
        beforeClick.center,
      );
      expect(_canvas(tester).cameraController.camera.zoom, beforeClick.zoom);
      expect(preferenceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.id}: dense worker-node targets pan without selecting '
        'and retain their click action', (tester) async {
      await openMap(
        tester,
        style: style,
        preferences: BdoNodeNetworkPreferences(showAllMapNodes: true),
      );
      final town = dataset.workerNodes.firstWhere(
        (node) => node.nodeType == 'City',
      );
      await _centerOn(tester, town);
      final marker = _visibleOrientationMarker(tester, dataset);
      final nodeId = _orientationNodeId(tester, marker);
      final before = _canvas(tester).cameraController.camera;
      await _dragFrom(tester, _pointOn(tester, marker));
      _expectPannedWithoutSelection(tester, before);
      expect(preferenceChanges, isEmpty);
      await _mouseClick(tester, _pointOn(tester, marker));
      expect(_canvas(tester).selectedNodeId, nodeId);
      expect(preferenceChanges, isEmpty);
      final selectedCanvas = _canvas(tester);
      final selectedBefore = selectedCanvas.cameraController.camera;
      final selectedPosition =
          tester.getTopLeft(find.byType(BdoMapCanvas)) +
          selectedCanvas.cameraController.worldToScreen(
            dataset.workerNodesById[nodeId]!.location.mapPoint,
            tester.getSize(find.byType(BdoMapCanvas)),
          );
      await _dragFrom(tester, selectedPosition);
      expect(
        _canvas(tester).cameraController.camera.center,
        isNot(selectedBefore.center),
      );
      expect(_canvas(tester).cameraController.camera.zoom, selectedBefore.zoom);
      expect(_canvas(tester).selectedNodeId, nodeId);
      expect(preferenceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.id}: worker-output artwork remains a pass-through '
        'drag surface', (tester) async {
      await openMap(
        tester,
        style: style,
        preferences: BdoNodeNetworkPreferences(
          showAllMapNodes: true,
          showWorkerOutputIcons: true,
        ),
      );
      final town = dataset.workerNodes.firstWhere(
        (node) => node.nodeType == 'City',
      );
      await _centerOn(tester, town, zoom: 2.8);
      final outputs = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'resource-map-worker-output-',
            ),
      );
      final visibleOutputs = outputs.evaluate().where((element) {
        final rect = tester.getRect(find.byWidget(element.widget));
        return rect.center.dx > 430 &&
            rect.center.dx < 1000 &&
            rect.center.dy > 180 &&
            rect.center.dy < 650;
      }).toList();
      expect(visibleOutputs, isNotEmpty);
      final output = find.byWidget(visibleOutputs.first.widget);
      final before = _canvas(tester).cameraController.camera;
      await _dragFrom(tester, tester.getCenter(output));
      _expectPannedWithoutSelection(tester, before);
      expect(preferenceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.id}: dragging an investment marker never invests '
        'but a following click toggles exactly once', (tester) async {
      await openMap(tester, style: style);
      await tester.tap(
        find.byKey(const ValueKey('resource-map-home-more-tools')),
      );
      await tester.pumpAndSettle();
      final setupAction = find.byKey(const ValueKey('resource-map-home-setup'));
      await tester.ensureVisible(setupAction);
      await tester.tap(setupAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('resource-map-invest-node-mode')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resource-map-invest-mode-banner')),
        findsOneWidget,
      );
      final town = dataset.workerNodes.firstWhere(
        (node) => node.nodeType == 'City',
      );
      await _centerOn(tester, town);
      final marker = _visibleOrientationMarker(tester, dataset);
      final nodeId = _orientationNodeId(tester, marker);
      expect(
        dataset.workerNodesById[nodeId]!.contributionPoints,
        greaterThan(0),
      );
      final before = _canvas(tester).cameraController.camera;
      final beforeChanges = preferenceChanges.length;
      final canceled = await tester.startGesture(
        _pointOn(tester, marker),
        kind: ui.PointerDeviceKind.mouse,
      );
      await canceled.moveBy(const Offset(18, 12));
      await tester.pump();
      await canceled.moveBy(const Offset(18, 12));
      await tester.pump();
      await canceled.cancel();
      await tester.pumpAndSettle();
      _expectPannedWithoutSelection(tester, before);
      expect(preferenceChanges, hasLength(beforeChanges));
      expect(_canvas(tester).activeNodeIds, isNot(contains(nodeId)));
      await _dragFrom(tester, _pointOn(tester, marker));
      _expectPannedWithoutSelection(tester, before);
      expect(preferenceChanges, hasLength(beforeChanges));
      expect(_canvas(tester).activeNodeIds, isNot(contains(nodeId)));
      await _mouseClick(tester, _pointOn(tester, marker));
      expect(preferenceChanges, hasLength(beforeChanges + 1));
      expect(preferenceChanges.last.currentNodeIds, contains(nodeId));
      await _mouseClick(tester, _pointOn(tester, marker));
      expect(preferenceChanges, hasLength(beforeChanges + 2));
      expect(preferenceChanges.last.currentNodeIds, isNot(contains(nodeId)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.id}: touch drags across town labels pan without '
        'opening their details', (tester) async {
      await openMap(tester, style: style);
      final town = dataset.workerNodes.firstWhere(
        (node) => node.nodeType == 'City',
      );
      await _centerOn(tester, town);
      final marker = find.byKey(ValueKey('resource-map-landmark-${town.id}'));
      final label = find.descendant(
        of: marker,
        matching: find.text(town.siteName),
      );
      final before = _canvas(tester).cameraController.camera;
      await _dragFrom(
        tester,
        tester.getCenter(label),
        kind: ui.PointerDeviceKind.touch,
      );
      _expectPannedWithoutSelection(tester, before);
      expect(preferenceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.id}: trackpad pan/pinch and wheel zoom work over '
        'town labels without duplicate zoom or selection', (tester) async {
      await openMap(tester, style: style);
      final town = dataset.workerNodes.firstWhere(
        (node) => node.nodeType == 'City',
      );
      await _centerOn(tester, town);
      final marker = find.byKey(ValueKey('resource-map-landmark-${town.id}'));
      final start = tester.getCenter(marker);
      final before = _canvas(tester).cameraController.camera;
      final gesture = await tester.startGesture(
        start,
        kind: ui.PointerDeviceKind.trackpad,
      );
      await gesture.panZoomUpdate(start, pan: const Offset(12, 8), scale: 1.02);
      await tester.pump();
      await gesture.panZoomUpdate(
        start,
        pan: const Offset(80, 50),
        scale: 1.25,
      );
      await tester.pump();
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(
        _canvas(tester).cameraController.camera.center,
        isNot(before.center),
      );
      expect(
        _canvas(tester).cameraController.camera.zoom,
        greaterThan(before.zoom),
      );
      expect(_canvas(tester).selectedNodeId, isNull);
      expect(preferenceChanges, isEmpty);

      await _centerOn(tester, town);
      final beforeWheel = _canvas(tester).cameraController.camera;
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: tester.getCenter(marker),
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _canvas(tester).cameraController.camera.zoom,
        closeTo(beforeWheel.zoom + .5, .000001),
        reason: 'A scroll event must reach exactly one zoom handler.',
      );
      expect(_canvas(tester).selectedNodeId, isNull);
      expect(preferenceChanges, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

BdoMapCanvas _canvas(WidgetTester tester) =>
    tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));

Future<void> _centerOn(
  WidgetTester tester,
  BdoWorkerNode node, {
  double zoom = 2.6,
}) async {
  _canvas(tester).cameraController.setCamera(
    BdoMapCamera(center: node.location.mapPoint, zoom: zoom),
    tester.getSize(find.byType(BdoMapCanvas)),
  );
  await tester.pumpAndSettle();
}

Future<void> _dragFrom(
  WidgetTester tester,
  Offset start, {
  ui.PointerDeviceKind kind = ui.PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(start, kind: kind);
  for (var step = 0; step < 12; step++) {
    await gesture.moveBy(const Offset(8, 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void _expectPannedWithoutSelection(WidgetTester tester, BdoMapCamera before) {
  final canvas = _canvas(tester);
  expect(
    canvas.cameraController.camera.center,
    isNot(before.center),
    reason: 'Geographic markers must not shield the shared map pan recognizer.',
  );
  expect(canvas.cameraController.camera.zoom, before.zoom);
  final viewport = tester.getSize(find.byType(BdoMapCanvas));
  final translatedAnchor = canvas.cameraController.worldToScreen(
    before.center,
    viewport,
  );
  expect(translatedAnchor.dx, greaterThan(viewport.width / 2));
  expect(translatedAnchor.dy, greaterThan(viewport.height / 2));
  expect(canvas.selectedNodeId, isNull);
  expect(canvas.selectedSpotId, isNull);
  expect(canvas.selectedPointId, isNull);
}

Future<void> _mouseClick(
  WidgetTester tester,
  Offset position, {
  Offset jitter = Offset.zero,
}) async {
  final gesture = await tester.startGesture(
    position,
    kind: ui.PointerDeviceKind.mouse,
  );
  if (jitter != Offset.zero) {
    await gesture.moveBy(jitter);
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

String _orientationNodeId(WidgetTester tester, Finder marker) =>
    (tester.widget(marker).key! as ValueKey<String>).value.replaceFirst(
      'resource-map-orientation-node-',
      '',
    );

Finder _visibleOrientationMarker(
  WidgetTester tester,
  BdoResourceMapDataset dataset,
) {
  final markers = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'resource-map-orientation-node-',
        ),
  );
  for (final element in markers.hitTestable().evaluate()) {
    final marker = find.byKey(element.widget.key!);
    final node = dataset.workerNodesById[_orientationNodeId(tester, marker)]!;
    final center = tester.getCenter(marker);
    if (node.contributionPoints > 0 &&
        center.dx > 430 &&
        center.dx < 760 &&
        center.dy > 180 &&
        center.dy < 520) {
      return marker;
    }
  }
  fail('The real overview must contain a visible interactive paid node.');
}

Offset _pointOn(WidgetTester tester, Finder marker, {Finder? content}) {
  final bounds = tester.getRect(content ?? marker);
  final target = tester.renderObject<RenderBox>(marker);
  for (final x in <double>[.5, .15, .85]) {
    for (final y in <double>[.5, .25, .75]) {
      final point = Offset(
        bounds.left + bounds.width * x,
        bounds.top + bounds.height * y,
      );
      if (tester
          .hitTestOnBinding(point)
          .path
          .any((entry) => identical(entry.target, target))) {
        return point;
      }
    }
  }
  fail('The intended marker must expose a real pointer hit target.');
}
