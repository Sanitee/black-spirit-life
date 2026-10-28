import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/workspace/retained_workspace_viewport.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sceneKey = ValueKey('resource-cold-frame-sequence');
const _viewport = Size(1500, 940);
final _nodeKeys = <BdoNodeIconImageKey>{
  for (
    var type = bdoNodeIconTypeMinimum;
    type <= bdoNodeIconTypeMaximum;
    type++
  )
    for (final active in const [false, true])
      for (final highlighted in const [false, true])
        (sourceIconType: type, active: active, highlighted: highlighted),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold Atlas paints and completes without a corrective gesture', (
    tester,
  ) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    _FrameCollector? collector;
    final visible = ValueNotifier(true);
    final responses = _ControlledTiles();
    Directory? cache;
    try {
      await tester.binding.setSurfaceSize(_viewport);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      final fixture = (await tester.runAsync(() async {
        await _loadFonts();
        return (
          dataset: await BdoResourceMapLoader.loadBundled(),
          lodging: await LodgingDataLoader.loadBundled(),
          economics: await BdoWorkerEconomicsLoader.loadBundled(),
          cache: await Directory.systemTemp.createTemp('map_cold_frames_'),
        );
      }))!;
      cache = fixture.cache;

      // The framework registered drawFrame when the binding initialized. This
      // later persistent callback runs after its paint, BEFORE post-frame fit
      // and annotation callbacks. Copy state now: the painter holds a mutable
      // camera controller, so reading it after pump would miss the first paint.
      collector = _FrameCollector(tester);
      tester.binding.addPersistentFrameCallback((_) {
        collector?.afterFrameworkPaint();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Segoe UI',
            platform: TargetPlatform.windows,
          ),
          home: ResourceMapThemeAdapter(
            spec: SakuraNightGardenSpec.theme,
            uiOpacity: .7,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, active, child) => RetainedWorkspaceViewport(
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
                tileHttpClient: responses.client,
                tileSource: BdoTileSource(
                  id: 'cold-frame-sequence-test',
                  displayName: 'Coordinate and level terrain fixture',
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
      );

      final frames = collector;
      expect(frames.errors, isEmpty);
      final first = frames.byName('first-paint');
      expect(first.phase, SchedulerPhase.persistentCallbacks.name);
      expect(first.camera['zoom'], .85);
      expect(first.nodeImages, 0);
      expect(first.decodedTiles, 0);
      expect(first.visibleTiles, 0);
      final mapState = tester.state(find.byType(BdoResourceMap));
      final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
      final manager = canvas.tileManager;
      final fittedCamera = _camera(canvas.cameraController.camera);
      expect(fittedCamera, isNot(first.camera));
      expect(tester.binding.hasScheduledFrame, isTrue);

      // pump() consumes scheduled work; it does not call scheduleFrame. No
      // gesture, camera mutation, setState, cache retry, or forced repaint is
      // used during the complete first-load sequence.
      await tester.pump();
      final fitted = frames.byName('first-fitted');
      expect(fitted.frame, first.frame + 1);
      expect(fitted.camera, fittedCamera);
      expect(fitted.visibleTiles, greaterThan(0));
      expect(fitted.decodedTiles, 0);

      // HTTP remains blocked while the production canvas loads all bundled
      // node PNGs through rootBundle + ui.Codec. DefaultAssetBundle cannot gate
      // those direct loads. Their actual zero-to-complete paint is observed.
      await _until(tester, () => frames.has('art-ready'));
      final artwork = frames.byName('art-ready');
      expect(artwork.nodeImages, _nodeKeys.length);
      expect(artwork.nodeKeys, unorderedEquals(_nodeKeys.map(_nodeKey)));
      expect(artwork.camera, fittedCamera);
      expect(artwork.decodedTiles, 0);
      expect(responses.pending, isNotEmpty);
      await _until(tester, () => _idle(tester, allowHeldTiles: true));
      expect(tester.binding.hasScheduledFrame, isFalse);
      frames.capture('before-first-tile');

      // Release exactly one real HTTP response, with coordinate-specific PNG
      // bytes. Its decode must itself schedule and reach the next paint.
      final firstRequest = responses.pending.first;
      expect(manager.visibleCoordinates, contains(firstRequest));
      responses.release(firstRequest);
      await _until(tester, () => frames.has('first-tile'));
      final firstTile = frames.byName('first-tile');
      expect(firstTile.camera, fittedCamera);
      expect(firstTile.decodedTiles, 1);
      expect(firstTile.nodeImages, _nodeKeys.length);
      expect(manager.tile(firstRequest), isNotNull);

      responses.releaseAll();
      await _until(tester, () => _idle(tester));
      expect(frames.has('visible-complete'), isTrue);
      expect(manager.visibleCoordinates, isNotEmpty);
      expect(
        manager.visibleCoordinates.every((tile) => manager.tile(tile) != null),
        isTrue,
      );
      expect(manager.failedVisibleTileCount, 0);
      expect(responses.encoded.length, greaterThan(1));
      expect(
        responses.encoded.values.map(base64Encode).toSet().length,
        responses.encoded.length,
        reason: 'Different coordinates/levels must not reuse one flat tile.',
      );
      expect(_painter(tester).nodeIconImages.keys, unorderedEquals(_nodeKeys));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
      frames.capture('first-settled');
      final settled = frames.byName('first-settled');
      final requestsBefore = responses.requestCount;
      final revisionBefore = manager.decodedTileRevision;

      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BdoResourceMap), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      visible.value = true;
      await tester.pump();
      await _until(tester, () => _idle(tester));
      expect(tester.state(find.byType(BdoResourceMap)), same(mapState));
      expect(
        tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas)).tileManager,
        same(manager),
      );
      expect(_camera(canvas.cameraController.camera), fittedCamera);
      expect(manager.decodedTileRevision, revisionBefore);
      expect(responses.requestCount, requestsBefore);
      frames.capture('retained-return');
      final returned = frames.byName('retained-return');
      expect(returned.layers, settled.layers);
      expect(returned.nodeKeys, settled.nodeKeys);
      expect(frames.errors, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.runAsync(() async {
        final pixels = <String, Uint8List>{};
        for (final frame in frames.records) {
          final data = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          pixels[frame.name] = Uint8List.fromList(Uint8List.sublistView(data));
        }
        final finalDifference = _differences(
          pixels['first-settled']!,
          pixels['retained-return']!,
        );
        final firstTileDifference = _differences(
          pixels['before-first-tile']!,
          pixels['first-tile']!,
        );
        expect(firstTileDifference, greaterThan(0));
        expect(finalDifference, 0);
        final output = Platform.environment['RESOURCE_COLD_FRAME_CAPTURE_DIR'];
        if (output != null) {
          final directory = Directory(output);
          await directory.create(recursive: true);
          for (final frame in frames.records) {
            final png = (await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '${directory.path}/${frame.name}.png',
            ).writeAsBytes(Uint8List.sublistView(png));
          }
          await File(
            '${directory.path}/cold-frame-sequence.json',
          ).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'schema': 1,
              'firstPaintObservedBeforePostFrameCallbacks': true,
              'initialLoadGesturesOrForcedRepaints': 0,
              'bundledNodeArtworkExpected': _nodeKeys.length,
              'firstTileChangedPixels': firstTileDifference,
              'retainedReturnChangedPixels': finalDifference,
              'requests': responses.requestCount,
              'frames': frames.records.map((frame) => frame.toJson()).toList(),
              'limits': [
                'Fresh widget and temporary disk cache, not a fresh engine/GPU.',
                'Distinct synthetic coordinate/LOD terrain, not remote WebP.',
                'Full bundled map data and real node/menu artwork.',
                'Actual Sakura map adapter at 70%; shared title is not mounted.',
                'toImageSync replays a headless layer tree, not Windows scanout.',
                'No physical monitor conclusion; capture can perturb raster work.',
              ],
            }),
          );
        }
      });
    } finally {
      // Restore globals even if teardown itself reports a filesystem failure.
      debugDisableShadows = previousShadows;
      // Persistent callbacks cannot be removed. Disable the callback and clear
      // its sole reference before unmount; later tests retain no test objects.
      final completedCollector = collector;
      collector = null;
      completedCollector?.dispose();
      responses.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      visible.dispose();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.binding.setSurfaceSize(null);
      if (cache != null) {
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 30; attempt++) {
            try {
              await cache!.delete(recursive: true);
              break;
            } on FileSystemException {
              if (attempt == 29) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          }
        });
      }
    }
  });
}

class _FrameCollector {
  _FrameCollector(this.tester);
  final WidgetTester tester;
  final records = <_PaintedFrame>[];
  final errors = <String>[];
  var frameNumber = 0;

  bool has(String name) => records.any((frame) => frame.name == name);
  _PaintedFrame byName(String name) =>
      records.singleWhere((frame) => frame.name == name);

  void afterFrameworkPaint() {
    if (find.byType(BdoMapCanvas).evaluate().isEmpty) return;
    frameNumber++;
    try {
      final painter = _painter(tester);
      final manager = painter.tileManager;
      if (!has('first-paint')) {
        capture('first-paint');
      } else if (!has('first-fitted') &&
          _camera(painter.cameraController.camera)['zoom'] !=
              byName('first-paint').camera['zoom']) {
        capture('first-fitted');
      }
      if (!has('art-ready') &&
          painter.nodeIconImages.length == _nodeKeys.length) {
        capture('art-ready');
      }
      if (!has('first-tile') && manager.decodedTileCount > 0) {
        capture('first-tile');
      }
      if (!has('visible-complete') &&
          manager.visibleCoordinates.isNotEmpty &&
          manager.visibleCoordinates.every(
            (tile) => manager.tile(tile) != null,
          )) {
        capture('visible-complete');
      }
    } on Object catch (error, stack) {
      errors.add('$error\n$stack');
    }
  }

  void capture(String name) {
    final painter = _painter(tester);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_sceneKey),
    );
    if (boundary.debugNeedsPaint) {
      throw StateError('Attempted to record $name before framework paint.');
    }
    records.add(
      _PaintedFrame(
        name: name,
        frame: frameNumber,
        phase: SchedulerBinding.instance.schedulerPhase.name,
        camera: _camera(painter.cameraController.camera),
        decodedTiles: painter.tileManager.decodedTileCount,
        visibleTiles: painter.tileManager.visibleCoordinates.length,
        nodeImages: painter.nodeIconImages.length,
        nodeKeys: painter.nodeIconImages.keys.map(_nodeKey).toList()..sort(),
        layers: _layers(boundary.debugLayer!),
        image: boundary.toImageSync(pixelRatio: 1),
      ),
    );
  }

  void dispose() {
    for (final record in records) {
      record.image.dispose();
    }
    records.clear();
  }
}

class _PaintedFrame {
  const _PaintedFrame({
    required this.name,
    required this.frame,
    required this.phase,
    required this.camera,
    required this.decodedTiles,
    required this.visibleTiles,
    required this.nodeImages,
    required this.nodeKeys,
    required this.layers,
    required this.image,
  });
  final String name;
  final int frame;
  final String phase;
  final Map<String, double> camera;
  final int decodedTiles;
  final int visibleTiles;
  final int nodeImages;
  final List<String> nodeKeys;
  final List<String> layers;
  final ui.Image image;

  Map<String, Object> toJson() => {
    'name': name,
    'frame': frame,
    'schedulerPhase': phase,
    'camera': camera,
    'decodedTiles': decodedTiles,
    'visibleTiles': visibleTiles,
    'nodeImages': nodeImages,
    'nodeKeys': nodeKeys,
    'layers': layers,
  };
}

class _ControlledTiles {
  _ControlledTiles() {
    client = MockClient((request) async {
      expect(request.url.host, 'example.test');
      final coordinate = _coordinate(request.url);
      requestCount++;
      final gate = Completer<void>();
      _gates[coordinate] = gate;
      if (_allReleased || _closed) gate.complete();
      await gate.future;
      if (_closed) return http.Response('', 503);
      final bytes = await _terrainTile(coordinate);
      encoded[coordinate] = bytes;
      return http.Response.bytes(
        bytes,
        200,
        headers: {'content-type': 'image/png'},
      );
    });
  }
  late final MockClient client;
  final _gates = <BdoTileCoordinate, Completer<void>>{};
  final encoded = <BdoTileCoordinate, Uint8List>{};
  var requestCount = 0;
  var _allReleased = false;
  var _closed = false;

  List<BdoTileCoordinate> get pending => [
    for (final entry in _gates.entries)
      if (!entry.value.isCompleted) entry.key,
  ];

  void release(BdoTileCoordinate coordinate) => _gates[coordinate]!.complete();

  void releaseAll() {
    _allReleased = true;
    for (final coordinate in pending) {
      release(coordinate);
    }
  }

  void close() {
    _closed = true;
    releaseAll();
    client.close();
  }
}

BdoTileCoordinate _coordinate(Uri uri) {
  final xy = uri.pathSegments[1].replaceFirst('.png', '').split('_');
  return BdoTileCoordinate(
    zoom: int.parse(uri.pathSegments[0]),
    x: int.parse(xy[0]),
    y: int.parse(xy[1]),
  );
}

Future<Uint8List> _terrainTile(BdoTileCoordinate coordinate) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final z = coordinate.zoom;
  final x = coordinate.x;
  final y = coordinate.y;
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()
      ..color = Color.fromARGB(
        255,
        45 + z * 18,
        70 + (x + 12) % 80,
        50 + (y + 12) % 100,
      ),
  );
  canvas.drawCircle(
    Offset(48.0 + (x + 16) % 8 * 20, 48.0 + (y + 16) % 8 * 20),
    18.0 + z * 4,
    Paint()..color = const Color(0xFFD6BF8A),
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

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 20)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 32));
    if (ready()) return;
  }
  throw TestFailure('Cold-frame milestone did not arrive within 20 seconds.');
}

bool _idle(WidgetTester tester, {bool allowHeldTiles = false}) {
  final painter = _painter(tester);
  final manager = painter.tileManager;
  final images = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
  return painter.nodeIconImages.length == _nodeKeys.length &&
      images.length >= 3 &&
      images.every((image) => image.image != null) &&
      PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
      tester.binding.transientCallbackCount == 0 &&
      !tester.binding.hasScheduledFrame &&
      (allowHeldTiles ||
          (manager.activeRequestCount == 0 && manager.queuedRequestCount == 0));
}

BdoMapPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(BdoMapCanvas),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<BdoMapPainter>()
    .single;

Map<String, double> _camera(BdoMapCamera camera) => {
  'x': camera.center.x,
  'y': camera.center.y,
  'zoom': camera.zoom,
};

String _nodeKey(BdoNodeIconImageKey key) =>
    '${key.sourceIconType}/${key.active}/${key.highlighted}';

List<String> _layers(Layer root) {
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

  visit(root, 0);
  return result;
}

int _differences(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
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
