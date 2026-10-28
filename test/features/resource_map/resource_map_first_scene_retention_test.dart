import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/workspace/retained_workspace_viewport.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sceneKey = ValueKey('resource-first-scene');
const _viewport = Size(1500, 940);
final _expectedNodeArtworkKeys = <BdoNodeIconImageKey>{
  for (
    var sourceIconType = bdoNodeIconTypeMinimum;
    sourceIconType <= bdoNodeIconTypeMaximum;
    sourceIconType++
  )
    for (final active in const [false, true])
      for (final highlighted in const [false, true])
        (
          sourceIconType: sourceIconType,
          active: active,
          highlighted: highlighted,
        ),
};
final _expectedNodeArtworkAssets = {
  for (final key in _expectedNodeArtworkKeys)
    bdoNodeIconAssetPath(
      key.sourceIconType,
      active: key.active,
      highlighted: key.highlighted,
    ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in const [
    (
      id: 'tab-return',
      title:
          'full first-settled Atlas scene matches a retained tab return at 70%',
      prefix: '',
      reportName: 'scene-retention',
    ),
    (
      id: 'closed-pointer-pan',
      title:
          'first Atlas mouse drag preserves pixels after exact camera return',
      prefix: 'pan-',
      reportName: 'scene-first-pan',
    ),
    (
      id: 'synthetic-gesture-only',
      title: 'synthetic Atlas gesture start and end preserve an unmoved scene',
      prefix: 'gesture-only-',
      reportName: 'scene-gesture-only',
    ),
  ]) {
    testWidgets(scenario.title, (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: false);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.binding.setSurfaceSize(_viewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = (await tester.runAsync(() async {
          await _loadFonts();
          return (
            dataset: await BdoResourceMapLoader.loadBundled(),
            lodging: await LodgingDataLoader.loadBundled(),
            economics: await BdoWorkerEconomicsLoader.loadBundled(),
            terrain: await _terrainTile(),
            cache: await Directory.systemTemp.createTemp('map_first_scene_'),
          );
        }))!;
        final visible = ValueNotifier(true);
        final assets = _DelayedArtworkBundle();
        var requests = 0;
        final client = MockClient((request) async {
          expect(request.url.host, 'example.test');
          requests++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return http.Response.bytes(
            fixture.terrain,
            200,
            headers: {'content-type': 'image/png'},
          );
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          visible.dispose();
          client.close();
          await tester.runAsync(() async {
            // Windows may still be finishing a cache write after tile disposal.
            for (var attempt = 0; attempt < 30; attempt++) {
              try {
                await fixture.cache.delete(recursive: true);
                break;
              } on FileSystemException {
                if (attempt == 29) rethrow;
                await Future<void>.delayed(const Duration(milliseconds: 20));
              }
            }
          });
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: 'Segoe UI',
              platform: TargetPlatform.windows,
            ),
            home: DefaultAssetBundle(
              bundle: assets,
              child: ResourceMapThemeAdapter(
                spec: SakuraNightGardenSpec.theme,
                uiOpacity: .7,
                child: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (context, active, child) =>
                      RetainedWorkspaceViewport(
                        offstage: !active,
                        child: TickerMode(
                          enabled: active,
                          child: RepaintBoundary(key: _sceneKey, child: child!),
                        ),
                      ),
                  child: BdoResourceMap(
                    dataset: fixture.dataset,
                    lodgingDataset: fixture.lodging,
                    workerEconomics: fixture.economics,
                    cacheDirectory: fixture.cache,
                    tileHttpClient: client,
                    tileSource: BdoTileSource(
                      id: 'first-scene-test',
                      displayName: 'Generated terrain fixture',
                      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
                      worldBounds: BdoTileSource.workermanCommunity.worldBounds,
                      attribution: 'Generated test fixture',
                      usageNotice: 'Headless regression only.',
                      fileExtension: 'png',
                    ),
                    showSourceNotice: false,
                    uiOpacity: .7,
                    onUiOpacityChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );

        // Do not preseed the cache or suppress ordinary animation. Exercise the
        // real cache, HTTP, decode, image-stream and annotation registration paths.
        await _settleScene(tester, assets, () => requests);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('resource-map-field-desk')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('resource-map-home-find-material')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('resource-map-home-worker-income')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('resource-map-home-houses')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('resource-map-ui-opacity-slider')),
              )
              .value,
          .7,
        );
        expect(
          MediaQuery.disableAnimationsOf(
            tester.element(find.byType(BdoResourceMap)),
          ),
          isFalse,
        );
        expect(
          assets.loadedArtwork,
          containsAll([
            'packages/bdo_map_core/assets/images/menu_artwork/iron_ore.webp',
            'packages/bdo_map_core/assets/images/menu_artwork/silver.webp',
            'packages/bdo_map_core/assets/images/menu_artwork/house.webp',
          ]),
        );
        expect(find.byType(BackdropFilter), findsNothing);
        final mapState = tester.state(find.byType(BdoResourceMap));
        final canvasState = tester.state(find.byType(BdoMapCanvas));
        final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
        final camera = canvas.cameraController;
        final position = camera.camera;
        final manager = canvas.tileManager;
        final requestCount = requests;
        final decodedRevision = manager.decodedTileRevision;
        final firstNodeArtwork = _expectNodeArtworkReady(tester);
        final firstTiles = _visibleTileImages(manager);
        final firstArtworkWidgets = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .map((widget) => widget.image!)
            .toList();
        final firstPainter = _mapPainter(tester);
        final first = await _capture(tester, '${scenario.prefix}first-settled');
        final firstLayers = _layerStructure(tester);
        final firstIdle = _idleState(tester, manager, assets);
        final transitionEvidence = <String, Object?>{
          'kind': scenario.id,
          'initialCamera': _cameraValues(position),
          'initialVisualStyle': firstPainter.visualStyle.name,
          'visibleTileImagesBefore': firstTiles.length,
          'physicalMonitorCovered': false,
        };

        if (scenario.id == 'tab-return') {
          visible.value = false;
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(BdoResourceMap), findsNothing);
          expect(
            tester.state(find.byType(BdoResourceMap, skipOffstage: false)),
            same(mapState),
          );
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.binding.hasScheduledFrame, isFalse);

          visible.value = true;
          await tester.pump();
        } else if (scenario.id == 'closed-pointer-pan') {
          transitionEvidence.addAll(
            await _closedPointerPan(tester, camera, position),
          );
        } else {
          transitionEvidence.addAll(
            await _syntheticGestureWithoutPan(tester, camera, position),
          );
        }
        _expectNodeArtworkReady(tester);
        final returnFrame = await _capture(
          tester,
          '${scenario.prefix}first-return-frame',
        );
        if (scenario.id != 'tab-return') {
          // City-label snapshots settle 90 ms after camera movement. Keep this
          // interval explicit rather than relying on incidental frame pumping.
          await tester.pump(const Duration(milliseconds: 120));
        }
        await _settleScene(tester, assets, () => requests);
        final returnedNodeArtwork = _expectNodeArtworkReady(tester);
        expect(
          returnedNodeArtwork,
          same(firstNodeArtwork),
          reason: 'This transition must retain the decoded node artwork.',
        );
        final returned = await _capture(
          tester,
          '${scenario.prefix}returned-settled',
        );
        final returnedLayers = _layerStructure(tester);
        final returnedIdle = _idleState(tester, manager, assets);
        final afterCanvas = tester.widget<BdoMapCanvas>(
          find.byType(BdoMapCanvas),
        );
        expect(tester.state(find.byType(BdoResourceMap)), same(mapState));
        expect(tester.state(find.byType(BdoMapCanvas)), same(canvasState));
        expect(afterCanvas.cameraController, same(camera));
        expect(afterCanvas.tileManager, same(manager));
        expect(camera.camera.center.x, position.center.x);
        expect(camera.camera.center.y, position.center.y);
        expect(camera.camera.zoom, position.zoom);
        if (scenario.id == 'tab-return' ||
            scenario.id == 'synthetic-gesture-only') {
          expect(
            requests,
            requestCount,
            reason: 'A transition without camera movement needs no tiles.',
          );
          expect(manager.decodedTileRevision, decodedRevision);
        }
        final returnedTiles = _visibleTileImages(manager);
        final retainedTileImages = firstTiles.keys.every(
          (key) => identical(firstTiles[key], returnedTiles[key]),
        );
        expect(returnedTiles.keys, unorderedEquals(firstTiles.keys));
        expect(retainedTileImages, isTrue);
        for (final key in firstNodeArtwork.keys) {
          expect(returnedNodeArtwork[key], same(firstNodeArtwork[key]));
        }
        final returnedArtworkWidgets = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .map((widget) => widget.image!)
            .toList();
        expect(returnedArtworkWidgets.length, firstArtworkWidgets.length);
        final widgetArtworkIdentity = <Map<String, Object>>[];
        for (var index = 0; index < firstArtworkWidgets.length; index++) {
          final beforeImage = firstArtworkWidgets[index];
          final afterImage = returnedArtworkWidgets[index];
          final sameHandle = identical(afterImage, beforeImage);
          final sameDecodedMemory = afterImage.isCloneOf(beforeImage);
          widgetArtworkIdentity.add({
            'index': index,
            'width': afterImage.width,
            'height': afterImage.height,
            'sameDartHandle': sameHandle,
            'sameDecodedMemory': sameDecodedMemory,
          });
          // Image detaches its listener while TickerMode is disabled, keeping
          // the stream alive. On return ImageStreamCompleter supplies a clone
          // of its current image, then Image disposes the old handle. isCloneOf
          // is valid for that disposed handle and detects re-decoded memory.
          expect(
            sameDecodedMemory,
            isTrue,
            reason: 'Widget artwork $index must reuse its decoded image.',
          );
          if (scenario.id != 'tab-return') {
            expect(
              sameHandle,
              isTrue,
              reason: 'A gesture does not reattach the artwork image stream.',
            );
          }
        }
        final returnedPainter = _mapPainter(tester);
        expect(returnedPainter.visualStyle, firstPainter.visualStyle);
        expect(returnedPainter.chromeTheme, same(firstPainter.chromeTheme));
        expect(afterCanvas.visualStyle, canvas.visualStyle);
        expect(afterCanvas.chromeTheme, same(canvas.chromeTheme));
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('resource-map-ui-opacity-slider')),
              )
              .value,
          .7,
        );
        expect(find.byType(BackdropFilter), findsNothing);
        transitionEvidence.addAll({
          'finalCamera': _cameraValues(camera.camera),
          'finalVisualStyle': returnedPainter.visualStyle.name,
          'sameChromeTheme': identical(
            returnedPainter.chromeTheme,
            firstPainter.chromeTheme,
          ),
          'retainedVisibleTileImages': retainedTileImages,
          'retainedWidgetArtworkImages': firstArtworkWidgets.length,
          'widgetArtworkIdentity': widgetArtworkIdentity,
          'visibleTileImagesAfter': returnedTiles.length,
          'requestsDuringTransition': requests - requestCount,
          'decodedRevisionDelta': manager.decodedTileRevision - decodedRevision,
          'differentPixelsBeforeSnapshotSettle': _differentPixels(
            first,
            returnFrame,
          ),
        });
        expect(tester.takeException(), isNull);

        final differences = _differentPixels(first, returned);
        final report = <String, Object?>{
          'fixture':
              'Actual BdoResourceMap; bundled data, lodging, economics and artwork',
          'transition': transitionEvidence,
          'theme': 'Sakura Night Garden',
          'uiOpacity': .7,
          'normalAnimationsEnabled': true,
          'viewport': [_viewport.width, _viewport.height],
          'terrain':
              'Generated PNG via delayed mock HTTP; empty temporary cache',
          'limitations': [
            'Each case creates a fresh map widget and temporary tile cache, '
                'not a fresh Flutter engine or process; engine, shader and '
                'Flutter image caches may be shared between tests.',
            'The baseline uses RepaintBoundary.toImage before the transition; '
                'this is a headless scene replay, not native screen capture.',
            'Generated terrain does not reproduce the actual remote map '
                'pattern or native GPU image-decoding/presentation path.',
            'Comparisons start after initial tiles, all node artwork and '
                'animations settle; transient cold-loading frames and any '
                'downstream physical effect are not excluded by pixel parity.',
          ],
          'tileRequests': requests,
          'decodedTiles': manager.decodedTileCount,
          'nodeArtwork': {
            'expectedImageKeys': _expectedNodeArtworkKeys.length,
            'expectedUniqueAssets': _expectedNodeArtworkAssets.length,
            'firstSettledDecodedImages': firstNodeArtwork.length,
            'returnedSettledDecodedImages': returnedNodeArtwork.length,
            'retainedDecodedImages': identical(
              firstNodeArtwork,
              returnedNodeArtwork,
            ),
          },
          'delayedArtwork': assets.loadedArtwork.toList()..sort(),
          'firstIdle': firstIdle,
          'returnedIdle': returnedIdle,
          'firstLayers': firstLayers,
          'returnedLayers': returnedLayers,
          'firstReturnFrameDifferentPixels': _differentPixels(
            first,
            returnFrame,
          ),
          'settledDifferentPixels': differences,
          'nativePresentationOrPhysicalMonitorCovered': false,
        };
        final output = Platform.environment['RESOURCE_FIRST_SCENE_CAPTURE_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final directory = Directory(output);
            await directory.create(recursive: true);
            await File(
              '${directory.path}/${scenario.reportName}.json',
            ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
          });
        }
        expect(
          differences,
          0,
          reason: '${scenario.id} must not repair settled pixels.',
        );
        expect(
          returnedLayers,
          firstLayers,
          reason: 'Settled layer structure is stable.',
        );
        expect(returnedIdle, firstIdle);
      } finally {
        // The test binding checks paint globals before addTearDown runs.
        debugDisableShadows = previousShadows;
      }
    });
  }
}

class _DelayedArtworkBundle extends CachingAssetBundle {
  final loadedArtwork = <String>{};
  int pendingLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    pendingLoads++;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final result = await rootBundle.load(key);
      if (key.endsWith('.webp') || key.endsWith('.png')) {
        loadedArtwork.add(key);
      }
      return result;
    } finally {
      pendingLoads--;
    }
  }
}

BdoMapPainter _mapPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(BdoMapCanvas),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<BdoMapPainter>()
    .single;

Map<BdoNodeIconImageKey, ui.Image> _nodeArtwork(WidgetTester tester) =>
    _mapPainter(tester).nodeIconImages;

Map<BdoTileCoordinate, ui.Image> _visibleTileImages(BdoTileManager manager) => {
  for (final coordinate in manager.visibleCoordinates)
    coordinate: manager.tile(coordinate)!.image,
};

Map<String, double> _cameraValues(BdoMapCamera camera) => {
  'x': camera.center.x,
  'y': camera.center.y,
  'zoom': camera.zoom,
};

bool _sameCamera(BdoMapCamera left, BdoMapCamera right) =>
    left.center == right.center && left.zoom == right.zoom;

Future<Map<String, Object?>> _closedPointerPan(
  WidgetTester tester,
  BdoMapCameraController camera,
  BdoMapCamera initial,
) async {
  final canvasRect = tester.getRect(find.byType(BdoMapCanvas));
  // This is terrain well outside the left Atlas desk and right map controls.
  final down = canvasRect.topLeft + const Offset(940, 650);
  final anchor = down + const Offset(48, 0);
  final pointer = await tester.startGesture(
    down,
    kind: PointerDeviceKind.mouse,
  );
  await pointer.moveTo(anchor);
  await tester.pump(const Duration(milliseconds: 16));
  final recognizedCamera = camera.camera;
  // Close the path from the recognized drag anchor; the initial 48 px crosses
  // the recognizer's slop and is not assumed to be a camera displacement.
  await pointer.moveTo(anchor + const Offset(64, 24));
  await tester.pump(const Duration(milliseconds: 16));
  final excursion = camera.camera;
  expect(
    _sameCamera(excursion, initial),
    isFalse,
    reason: 'The real pointer must actually move the map.',
  );
  expect(excursion.zoom, initial.zoom);
  await pointer.moveTo(anchor + const Offset(96, 12));
  await tester.pump(const Duration(milliseconds: 16));
  await pointer.moveTo(anchor);
  await tester.pump(const Duration(milliseconds: 16));
  await pointer.up();
  await pointer.removePointer();
  await tester.pump();
  final afterPointer = camera.camera;
  final scale = camera.tileSource.scaleForZoom(initial.zoom);
  final residualPixels = Offset(
    (afterPointer.center.x - initial.center.x) * scale,
    (afterPointer.center.y - initial.center.y) * scale,
  );
  expect(afterPointer.zoom, initial.zoom);
  expect(
    residualPixels.distance,
    lessThanOrEqualTo(.01),
    reason: 'The pointer path itself must close to within .01 screen pixels.',
  );
  final normalized = !_sameCamera(afterPointer, initial);
  if (normalized) {
    // Only correct the bounded subpixel residual above. This extra notification
    // is recorded: if needed, the comparison includes this test-only restore,
    // not the pointer lifecycle alone. Never use it as an app-side redraw fix.
    camera.setCamera(initial, canvasRect.size);
    await tester.pump();
  }
  expect(_sameCamera(camera.camera, initial), isTrue);
  return {
    'realPointerGesture': true,
    'recognizedCamera': _cameraValues(recognizedCamera),
    'excursionCamera': _cameraValues(excursion),
    'cameraAfterPointerRelease': _cameraValues(afterPointer),
    'exactCameraNormalizationRequired': normalized,
    'residualScreenPixelsBeforeNormalization': {
      'x': residualPixels.dx,
      'y': residualPixels.dy,
      'distance': residualPixels.distance,
    },
    'cameraDriftBeforeNormalization': {
      'x': afterPointer.center.x - initial.center.x,
      'y': afterPointer.center.y - initial.center.y,
      'zoom': afterPointer.zoom - initial.zoom,
    },
  };
}

Future<Map<String, Object?>> _syntheticGestureWithoutPan(
  WidgetTester tester,
  BdoMapCameraController camera,
  BdoMapCamera initial,
) async {
  final detector = tester.widget<GestureDetector>(
    find.descendant(
      of: find.byType(BdoMapCanvas),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onScaleStart != null &&
            widget.onScaleEnd != null,
      ),
    ),
  );
  final beforePainter = _mapPainter(tester);
  detector.onScaleStart!(
    ScaleStartDetails(
      focalPoint: const Offset(940, 650),
      localFocalPoint: const Offset(940, 650),
    ),
  );
  await tester.pump();
  final afterStart = _mapPainter(tester);
  expect(_sameCamera(camera.camera, initial), isTrue);
  detector.onScaleEnd!(ScaleEndDetails());
  await tester.pump();
  expect(_sameCamera(camera.camera, initial), isTrue);
  final afterEnd = _mapPainter(tester);
  expect(afterStart, isNot(same(beforePainter)));
  expect(afterEnd, isNot(same(afterStart)));
  return {
    'realPointerGesture': false,
    'syntheticCallbacksOnly': true,
    'cameraUnchangedThroughout': true,
    'painterRecreatedAtStart': !identical(beforePainter, afterStart),
    'painterRecreatedAtEnd': !identical(afterStart, afterEnd),
    'exactCameraNormalizationRequired': false,
  };
}

bool _nodeArtworkReady(Map<BdoNodeIconImageKey, ui.Image> images) =>
    images.length == _expectedNodeArtworkKeys.length &&
    _expectedNodeArtworkKeys.every(images.containsKey) &&
    images.values.every((image) => image.width > 0 && image.height > 0);

Map<BdoNodeIconImageKey, ui.Image> _expectNodeArtworkReady(
  WidgetTester tester,
) {
  final images = _nodeArtwork(tester);
  expect(images.keys, unorderedEquals(_expectedNodeArtworkKeys));
  expect(_nodeArtworkReady(images), isTrue);
  return images;
}

Future<void> _settleScene(
  WidgetTester tester,
  _DelayedArtworkBundle assets,
  int Function() requestCount,
) async {
  final timeout = Stopwatch()..start();
  var stable = 0;
  var previousRequests = -1;
  BdoTileManager? manager;
  Map<BdoNodeIconImageKey, ui.Image> nodeArtwork = const {};
  while (timeout.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 32));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    manager = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .tileManager;
    // The canvas decodes node PNGs directly through rootBundle and ui.Codec.
    // Those loads bypass both DefaultAssetBundle and Flutter's image cache.
    nodeArtwork = _nodeArtwork(tester);
    final images = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    final ready =
        requestCount() > 0 &&
        manager.visibleCoordinates.isNotEmpty &&
        manager.visibleCoordinates.every(
          (tile) => manager!.tile(tile) != null,
        ) &&
        manager.activeRequestCount == 0 &&
        manager.queuedRequestCount == 0 &&
        _nodeArtworkReady(nodeArtwork) &&
        assets.pendingLoads == 0 &&
        images.length >= 3 &&
        images.every((image) => image.image != null) &&
        PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
        tester.binding.transientCallbackCount == 0 &&
        !tester.binding.hasScheduledFrame;
    stable = ready && previousRequests == requestCount() ? stable + 1 : 0;
    previousRequests = requestCount();
    if (stable == 3) return;
  }
  throw TestFailure(
    'Full Atlas scene did not become idle: ${requestCount()} requests, '
    '${manager?.activeRequestCount} active, ${manager?.queuedRequestCount} queued, '
    '${manager?.decodedTileCount} decoded, ${assets.pendingLoads} pending assets, '
    '${nodeArtwork.length}/${_expectedNodeArtworkKeys.length} node images, '
    '${tester.binding.transientCallbackCount} tickers, '
    '${tester.binding.hasScheduledFrame} scheduled frame.',
  );
}

Map<String, Object> _idleState(
  WidgetTester tester,
  BdoTileManager manager,
  _DelayedArtworkBundle assets,
) => {
  'transientCallbacks': tester.binding.transientCallbackCount,
  'scheduledFrame': tester.binding.hasScheduledFrame,
  'activeTileRequests': manager.activeRequestCount,
  'queuedTileRequests': manager.queuedRequestCount,
  'pendingAssets': assets.pendingLoads,
  'pendingImages': PaintingBinding.instance.imageCache.pendingImageCount,
};

List<String> _layerStructure(WidgetTester tester) {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_sceneKey),
  );
  expect(boundary.debugNeedsPaint, isFalse);
  final result = <String>[];
  void visit(Layer layer, int depth) {
    final geometry = switch (layer) {
      ClipRectLayer() => '${layer.clipRect}',
      ClipRRectLayer() => '${layer.clipRRect}',
      ClipPathLayer() => '${layer.clipPath?.getBounds()}',
      TransformLayer() => '${layer.transform}',
      OpacityLayer() => '${layer.alpha} ${layer.offset}',
      ColorFilterLayer() => '${layer.colorFilter}',
      ImageFilterLayer() => '${layer.imageFilter} ${layer.offset}',
      BackdropFilterLayer() => '${layer.filter}',
      OffsetLayer() => '${layer.offset}',
      PictureLayer() => '${layer.canvasBounds}',
      _ => '',
    };
    result.add('$depth ${layer.runtimeType} $geometry');
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        visit(child, depth + 1);
      }
    }
  }

  visit(boundary.debugLayer!, 0);
  return result;
}

Future<Uint8List> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_sceneKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final result = Uint8List.fromList(Uint8List.sublistView(data));
      final output = Platform.environment['RESOURCE_FIRST_SCENE_CAPTURE_DIR'];
      if (output != null) {
        final directory = Directory(output);
        await directory.create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(Uint8List.sublistView(png));
      }
      return result;
    } finally {
      image.dispose();
    }
  }))!;
}

int _differentPixels(Uint8List left, Uint8List right) {
  expect(left.length, right.length);
  var count = 0;
  for (var offset = 0; offset < left.length; offset += 4) {
    if (left[offset] != right[offset] ||
        left[offset + 1] != right[offset + 1] ||
        left[offset + 2] != right[offset + 2] ||
        left[offset + 3] != right[offset + 3]) {
      count++;
    }
  }
  return count;
}

Future<void> _loadFonts() async {
  if (Platform.isWindows) {
    final windows = Platform.environment['WINDIR'] ?? 'C:/Windows';
    for (final entry in {
      'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
      'Georgia': ['georgia.ttf', 'georgiab.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final name in entry.value) {
        loader.addFont(
          File('$windows/Fonts/$name').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  }
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found.');
    }
    sdk = sdk.parent;
  }
  for (final entry in {
    'Roboto': ['roboto-regular.ttf', 'roboto-bold.ttf'],
    'MaterialIcons': ['materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      loader.addFont(
        File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/$name',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}

Future<Uint8List> _terrainTile() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()..color = const Color(0xFF385051),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 110)
      ..cubicTo(76, 70, 103, 164, 174, 77)
      ..cubicTo(211, 22, 251, 82, 256, 58)
      ..lineTo(256, 256)
      ..lineTo(0, 256)
      ..close(),
    Paint()..color = const Color(0xFF7E806A),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 213)
      ..cubicTo(71, 109, 164, 245, 256, 123),
    Paint()
      ..color = const Color(0xFFE2CA9A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return Uint8List.fromList(Uint8List.sublistView(data));
  } finally {
    image.dispose();
    picture.dispose();
  }
}
