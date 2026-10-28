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
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(384, 192);
const _boundaryKey = ValueKey('startup-map-boundary');
const _canvasKey = ValueKey('startup-map-canvas');
const _left = BdoTileCoordinate(zoom: 1, x: 0, y: 0);
const _right = BdoTileCoordinate(zoom: 1, x: 1, y: 0);
const _parent = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
const _prefetch = BdoTileCoordinate(zoom: 2, x: 3, y: 3);
const _source = BdoTileSource(
  id: 'startup-render-test',
  displayName: 'Generated startup tiles',
  urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
  worldBounds: BdoMapBounds(left: 0, top: 0, right: 512, bottom: 512),
  attribution: 'Generated test fixture',
  usageNotice: 'Generated test fixture',
  minimumZoom: 0,
  maximumZoom: 2,
  worldUnitsAtZoomZero: 512,
  fileExtension: 'png',
);

class _MemoryTiles extends BdoTileManager {
  _MemoryTiles()
    : super(
        source: _source,
        diskCache: BdoMapDiskCache(
          rootDirectory: Directory.systemTemp,
          sourceNamespace: 'startup-test-no-io',
        ),
      );

  final images = <BdoTileCoordinate, BdoDecodedTile>{};
  int revision = 0;
  int viewportCalls = 0;
  bool disposed = false;

  @override
  Set<BdoTileCoordinate> get visibleCoordinates => {_left, _right};

  @override
  int get decodedTileCount => images.length;

  @override
  int get decodedTileRevision => revision;

  @override
  BdoDecodedTile? tile(BdoTileCoordinate coordinate) => images[coordinate];

  @override
  void updateViewport({
    required BdoMapBounds visibleBounds,
    required int zoom,
    int prefetchRing = 1,
  }) {
    viewportCalls++;
  }

  void put(
    BdoTileCoordinate coordinate,
    ui.Image image, {
    required DateTime loadedAt,
    bool fromDisk = true,
    bool notify = false,
  }) {
    images[coordinate] = BdoDecodedTile(
      coordinate: coordinate,
      image: image,
      decodedBytes: image.width * image.height * 4,
      loadedAt: loadedAt,
      fromDisk: fromDisk,
    );
    revision++;
    if (notify) notifyListeners();
  }

  void statusChanged() => notifyListeners();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Fixture {
  _Fixture(this.exactImage, this.ancestorImage, double zoom)
    : camera = BdoMapCameraController(
        tileSource: _source,
        initialCamera: BdoMapCamera(
          // Put the shared tile edge through a pixel centre, including at
          // fractional zoom, so the overlap seam is actually exercised.
          center: BdoMapPoint(256 + .5 / _source.scaleForZoom(zoom), 128),
          zoom: zoom,
        ),
      );

  final ui.Image exactImage;
  final ui.Image ancestorImage;
  final BdoMapCameraController camera;
  final manager = _MemoryTiles();

  void exactTiles(DateTime loadedAt, {bool notify = false}) {
    manager.put(_left, exactImage, loadedAt: loadedAt, notify: notify);
    manager.put(
      _right,
      exactImage,
      loadedAt: loadedAt,
      fromDisk: false,
      notify: notify,
    );
  }

  BdoMapPainter painter({
    BdoMapVisualStyle style = BdoMapVisualStyle.vivid,
    ResourceMapChromeThemeData chrome =
        ResourceMapChromeThemeData.sakuraCartographer,
  }) => BdoMapPainter(
    cameraController: camera,
    tileManager: manager,
    workerNodes: const [],
    workerNodesById: const {},
    gatheringSpots: const [],
    gatheringRoutes: const [],
    showConnections: false,
    selectedNodeId: null,
    selectedSpotId: null,
    selectedRouteId: null,
    colorScheme: const ColorScheme.dark(),
    visualStyle: style,
    chromeTheme: chrome,
  );

  void dispose() {
    camera.dispose();
    manager.dispose();
    exactImage.dispose();
    ancestorImage.dispose();
  }
}

Future<ui.Image> _solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = color);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(256, 256);
  } finally {
    picture.dispose();
  }
}

Future<_Fixture> _fixture({double zoom = 1.35}) async => _Fixture(
  await _solid(const Color(0xFF467E69)),
  await _solid(const Color(0xFFD95525)),
  zoom,
);

Future<Uint8List> _pixels(ui.Image image, {String? capture}) async {
  final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = Uint8List.fromList(
    raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
  );
  final directory = Platform.environment['RESOURCE_STARTUP_CAPTURE_DIR'];
  if (capture != null && directory != null && directory.isNotEmpty) {
    await Directory(directory).create(recursive: true);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$directory/startup-$capture.png').writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  }
  return result;
}

Future<Uint8List> _render(BdoMapPainter painter, {String? capture}) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  try {
    return await _pixels(image, capture: capture);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

List<int> _pixel(Uint8List bytes, int x, int y) {
  final start = (y * _size.width.toInt() + x) * 4;
  return bytes.sublist(start, start + 4);
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  ValueNotifier<bool> visible, {
  bool reduceMotion = false,
}) async {
  final canvas = BdoMapCanvas(
    key: _canvasKey,
    cameraController: fixture.camera,
    tileManager: fixture.manager,
    workerNodes: const <BdoWorkerNode>[],
    workerNodesById: const <String, BdoWorkerNode>{},
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
    showConnections: false,
    visualStyle: BdoMapVisualStyle.vivid,
    onHit: (_) {},
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: _size, disableAnimations: reduceMotion),
        child: Theme(
          data: ThemeData.dark(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: _size,
              child: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (context, active, child) => Offstage(
                  offstage: !active,
                  child: TickerMode(
                    enabled: active,
                    child: RepaintBoundary(key: _boundaryKey, child: child!),
                  ),
                ),
                child: canvas,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<Uint8List> _visiblePixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      return await _pixels(image);
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectNoTileTicker(WidgetTester tester) {
  expect(
    tester.binding.transientCallbackCount,
    0,
    reason: 'Decoded map images need one repaint, not a fade ticker.',
  );
}

Future<void> _unmount(
  WidgetTester tester,
  _Fixture fixture,
  ValueNotifier<bool> visible,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  fixture.dispose();
  visible.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final chrome in {
    'dark': ResourceMapChromeThemeData.sakuraCartographer,
    'light': ResourceMapChromeThemeData.illuminatedAtlas,
  }.entries) {
    for (final style in BdoMapVisualStyle.values) {
      for (final zoom in [1.0, 1.35]) {
        final name = '${chrome.key}-${style.name}-zoom${(zoom * 100).round()}';
        testWidgets('$name first tile paint equals settled pixels', (
          tester,
        ) async {
          await tester.runAsync(() async {
            final fixture = await _fixture(zoom: zoom);
            try {
              fixture.exactTiles(DateTime.now());
              final fresh = await _render(
                fixture.painter(style: style, chrome: chrome.value),
                capture: '$name-fresh',
              );
              fixture.exactTiles(DateTime(2000));
              final settled = await _render(
                fixture.painter(style: style, chrome: chrome.value),
                capture: '$name-settled',
              );
              fixture.exactTiles(DateTime.now().add(const Duration(days: 1)));
              final clockShifted = await _render(
                fixture.painter(style: style, chrome: chrome.value),
              );

              expect(
                fresh,
                orderedEquals(settled),
                reason:
                    'Cold disk/network tile arrivals must not start darker.',
              );
              expect(
                clockShifted,
                orderedEquals(settled),
                reason: 'Rendered opacity must not depend on the wall clock.',
              );
              final interior = _pixel(fresh, 140, 96);
              final settledInterior = _pixel(settled, 140, 96);
              expect(interior[1], greaterThan(80));
              expect(interior[1], greaterThan(interior[0] + 20));
              for (var x = 189; x <= 194; x++) {
                final seam = _pixel(fresh, x, 96);
                final settledSeam = _pixel(settled, x, 96);
                for (var channel = 0; channel < 4; channel++) {
                  expect(
                    seam[channel] - interior[channel],
                    settledSeam[channel] - settledInterior[channel],
                    reason:
                        'Tile arrival must not add contrast to the settled '
                        'filtering at overlapping tile edges.',
                  );
                }
              }
            } finally {
              fixture.dispose();
            }
          });
        });
      }
    }
  }

  testWidgets(
    'ancestor remains until exact tile arrives, then swaps immediately',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = await _fixture();
        try {
          fixture.manager.put(
            _parent,
            fixture.ancestorImage,
            loadedAt: DateTime(2000),
          );
          final fallback = await _render(fixture.painter());
          expect(_pixel(fallback, 96, 96)[0], greaterThan(150));
          fixture.manager.put(
            _left,
            fixture.exactImage,
            loadedAt: DateTime.now(),
          );
          final partial = await _render(fixture.painter());
          expect(_pixel(partial, 96, 96)[1], greaterThan(80));
          expect(
            _pixel(partial, 96, 96)[1],
            greaterThan(_pixel(partial, 96, 96)[0]),
          );
          expect(_pixel(partial, 288, 96), _pixel(fallback, 288, 96));
          fixture.manager.put(
            _right,
            fixture.exactImage,
            loadedAt: DateTime.now(),
          );
          final replacement = await _render(fixture.painter());
          fixture.exactTiles(DateTime(2000));
          final settled = await _render(fixture.painter());
          expect(replacement, orderedEquals(settled));
        } finally {
          fixture.dispose();
        }
      });
    },
  );

  testWidgets('late ancestor cannot recolor already visible exact tiles', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final fixture = await _fixture();
      try {
        fixture.exactTiles(DateTime.now().add(const Duration(days: 1)));
        final before = await _render(fixture.painter());
        fixture.manager.put(
          _parent,
          fixture.ancestorImage,
          loadedAt: DateTime.now(),
        );
        final after = await _render(fixture.painter());
        expect(after, orderedEquals(before));
        expect(_pixel(after, 96, 96)[1], greaterThan(80));
      } finally {
        fixture.dispose();
      }
    });
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'tile burst settles without ticker; reduced motion $reduceMotion',
      (tester) async {
        final fixture = (await tester.runAsync(_fixture))!;
        final visible = ValueNotifier(true);
        try {
          await _mount(tester, fixture, visible, reduceMotion: reduceMotion);
          final state = tester.state(find.byKey(_canvasKey));
          _expectNoTileTicker(tester);
          fixture.exactTiles(DateTime.now(), notify: true);
          _expectNoTileTicker(tester);
          await tester.pump();
          final first = await _visiblePixels(tester);
          expect(_pixel(first, 96, 96)[1], greaterThan(80));
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
            _expectNoTileTicker(tester);
          }
          final settled = await _visiblePixels(tester);
          expect(first, orderedEquals(settled));
          expect(tester.state(find.byKey(_canvasKey)), same(state));
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester, fixture, visible);
        }
      },
    );
  }

  testWidgets('prefetch and service-status updates do not start animation', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_fixture))!;
    final visible = ValueNotifier(true);
    try {
      fixture.exactTiles(DateTime(2000));
      await _mount(tester, fixture, visible);
      // A preloaded canvas must not replay an arrival fade either.
      _expectNoTileTicker(tester);
      final before = await _visiblePixels(tester);
      fixture.manager.statusChanged();
      _expectNoTileTicker(tester);
      await tester.pump();
      expect(await _visiblePixels(tester), orderedEquals(before));
      fixture.manager.put(
        _prefetch,
        fixture.ancestorImage,
        loadedAt: DateTime.now(),
        notify: true,
      );
      _expectNoTileTicker(tester);
      await tester.pump();
      expect(await _visiblePixels(tester), orderedEquals(before));
      await tester.pump(const Duration(milliseconds: 250));
      _expectNoTileTicker(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, fixture, visible);
    }
  });

  testWidgets(
    'hidden arrival returns fully painted without recreating map state',
    (tester) async {
      final fixture = (await tester.runAsync(_fixture))!;
      final visible = ValueNotifier(true);
      try {
        await _mount(tester, fixture, visible);
        final state = tester.state(find.byKey(_canvasKey));
        final originalCamera = fixture.camera.camera;
        visible.value = false;
        await tester.pump();
        fixture.exactTiles(DateTime.now(), notify: true);
        _expectNoTileTicker(tester);
        await tester.pump(const Duration(milliseconds: 40));
        expect(fixture.manager.disposed, isFalse);
        visible.value = true;
        await tester.pump();
        _expectNoTileTicker(tester);
        expect(tester.state(find.byKey(_canvasKey)), same(state));
        final canvas = tester.widget<BdoMapCanvas>(find.byKey(_canvasKey));
        expect(canvas.tileManager, same(fixture.manager));
        expect(canvas.cameraController, same(fixture.camera));
        expect(fixture.camera.camera, same(originalCamera));
        final returned = await _visiblePixels(tester);
        expect(_pixel(returned, 96, 96)[1], greaterThan(80));
        await tester.pump(const Duration(milliseconds: 300));
        expect(await _visiblePixels(tester), orderedEquals(returned));
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture, visible);
      }
    },
  );
}
