import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/src/engine/map_camera.dart';
import 'package:bdo_map_core/src/engine/tile_cache.dart';
import 'package:bdo_map_core/src/engine/tile_manager.dart';
import 'package:bdo_map_core/src/model/map_geometry.dart';
import 'package:bdo_map_core/src/model/map_visual_style.dart';
import 'package:bdo_map_core/src/model/tile_source.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// These tests characterize terrain selection, not native presentation or the
// reported physical-monitor effect. No real provider, user cache or profile is
// accessed. Unlike the scene-retention fixture, every coordinate and LOD has
// different, asymmetric imagery, and the first stages are deliberately cold.
const _source = BdoTileSource(
  id: 'cold-pyramid-test',
  displayName: 'Generated coordinate pyramid',
  urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
  worldBounds: BdoMapBounds(left: -512, top: -512, right: 512, bottom: 512),
  attribution: 'Generated test fixture',
  usageNotice: 'Generated test fixture',
  maximumZoom: 4,
  worldUnitsAtZoomZero: 1024,
  fileExtension: 'png',
);
const _stageSize = Size(384, 192);
const _overviewSize = Size(512, 384);
const _left = BdoTileCoordinate(zoom: 2, x: -2, y: -1);
const _right = BdoTileCoordinate(zoom: 2, x: -1, y: -1);
const _parent = BdoTileCoordinate(zoom: 1, x: -1, y: -1);
const _grandparent = BdoTileCoordinate(zoom: 0, x: -1, y: -1);
final _overview = <BdoTileCoordinate>{
  const BdoTileCoordinate(zoom: 0, x: -1, y: -1),
  const BdoTileCoordinate(zoom: 0, x: 0, y: -1),
  const BdoTileCoordinate(zoom: 0, x: -1, y: 0),
  const BdoTileCoordinate(zoom: 0, x: 0, y: 0),
};
const _tileBytes = 256 * 256 * 4;
const _wholeImage = Rect.fromLTWH(0, 0, 256, 256);
const _chrome = ResourceMapChromeThemeData.sakuraCartographer;

class _EncodedMemoryCache extends BdoMapDiskCache {
  _EncodedMemoryCache()
    : super(
        rootDirectory: Directory.systemTemp,
        sourceNamespace: 'cold-pyramid-no-filesystem',
      );

  final entries = <BdoTileCoordinate, Uint8List>{};
  final reads = <BdoTileCoordinate, int>{};

  @override
  Future<Uint8List?> read(
    BdoTileCoordinate coordinate, {
    required String extension,
  }) async {
    reads.update(coordinate, (value) => value + 1, ifAbsent: () => 1);
    final value = entries[coordinate];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(
    BdoTileCoordinate coordinate,
    Uint8List bytes, {
    required String extension,
  }) async {
    entries.putIfAbsent(coordinate, () => Uint8List.fromList(bytes));
  }
}

class _Pattern {
  _Pattern(this.image, this.encoded);

  final ui.Image image;
  final Uint8List encoded;
}

class _Transport extends ChangeNotifier {
  _Transport(this.pattern) {
    client = MockClient((request) {
      expect(request.url.host, 'example.test');
      final match = RegExp(
        r'^/(\d+)/(-?\d+)_(-?\d+)\.png$',
      ).firstMatch(request.url.path)!;
      final coordinate = BdoTileCoordinate(
        zoom: int.parse(match[1]!),
        x: int.parse(match[2]!),
        y: int.parse(match[3]!),
      );
      calls.update(coordinate, (value) => value + 1, ifAbsent: () => 1);
      final completer = Completer<http.Response>();
      pending.putIfAbsent(coordinate, () => []).add(completer);
      notifyListeners();
      if (automatic) unawaited(release(coordinate));
      return completer.future;
    });
  }

  final Future<_Pattern> Function(BdoTileCoordinate) pattern;
  late final MockClient client;
  final calls = <BdoTileCoordinate, int>{};
  final pending = <BdoTileCoordinate, List<Completer<http.Response>>>{};
  bool automatic = false;

  Future<void> release(
    BdoTileCoordinate coordinate, {
    int status = HttpStatus.ok,
  }) async {
    final waiting = pending.remove(coordinate);
    if (waiting == null) return;
    final bytes = status == HttpStatus.ok
        ? (await pattern(coordinate)).encoded
        : Uint8List(0);
    for (final completer in waiting) {
      completer.complete(http.Response.bytes(bytes, status));
    }
    notifyListeners();
  }

  Future<void> open() async {
    automatic = true;
    await Future.wait(pending.keys.toList().map(release));
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}

class _Pyramid {
  _Pyramid({int decodedTileCapacity = 64}) {
    transport = _Transport(pattern);
    manager = BdoTileManager(
      source: _source,
      diskCache: cache,
      client: transport.client,
      maximumDecodedBytes: decodedTileCapacity * _tileBytes,
    );
  }

  final cache = _EncodedMemoryCache();
  final patterns = <BdoTileCoordinate, Future<_Pattern>>{};
  final camera = BdoMapCameraController(
    tileSource: _source,
    initialCamera: const BdoMapCamera(
      center: BdoMapPoint(-256, -128),
      zoom: 2.35,
    ),
  );
  late final _Transport transport;
  late final BdoTileManager manager;

  Future<_Pattern> pattern(BdoTileCoordinate coordinate) =>
      patterns.putIfAbsent(coordinate, () => _makePattern(coordinate));

  void update(Size viewport) {
    manager.updateViewport(
      visibleBounds: camera.visibleWorldBounds(viewport),
      zoom: _source.tileZoomFor(camera.camera.zoom),
      prefetchRing: 0,
    );
  }

  Future<void> until(bool Function() ready, String reason) async {
    if (ready()) return;
    final completer = Completer<void>();
    void changed() {
      if (!completer.isCompleted && ready()) completer.complete();
    }

    manager.addListener(changed);
    transport.addListener(changed);
    try {
      changed();
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('Timed out: $reason'),
      );
    } finally {
      manager.removeListener(changed);
      transport.removeListener(changed);
    }
  }

  Future<void> idle() => until(
    () => manager.activeRequestCount == 0 && manager.queuedRequestCount == 0,
    'all fixture requests finish',
  );

  BdoMapPainter painter(BdoMapVisualStyle style) => BdoMapPainter(
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
    chromeTheme: _chrome,
    visualStyle: style,
  );

  Future<void> dispose() async {
    // Finish only this fixture's in-memory requests before disposing images.
    await transport.open();
    await idle();
    manager.dispose();
    transport.dispose();
    camera.dispose();
    for (final value in patterns.values) {
      (await value).image.dispose();
    }
  }
}

Future<_Pattern> _makePattern(BdoTileCoordinate coordinate) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final seed =
      (coordinate.zoom + 1) * 47 +
      (coordinate.x + 16) * 23 +
      (coordinate.y + 16) * 61;
  for (var quadrant = 0; quadrant < 4; quadrant++) {
    final color = Color.fromARGB(
      255,
      32 + (seed + quadrant * 37) % 192,
      32 + (seed * 3 + quadrant * 71) % 192,
      32 + (seed * 7 + quadrant * 19) % 192,
    );
    canvas.drawRect(
      Rect.fromLTWH((quadrant % 2) * 128.0, (quadrant ~/ 2) * 128.0, 128, 128),
      Paint()..color = color,
    );
  }
  // Asymmetry catches wrong source halves, mirroring and pixel offsets.
  canvas.drawRect(
    const Rect.fromLTWH(23, 41, 9, 161),
    Paint()..color = const Color(0xFFF5E6B2),
  );
  canvas.drawRect(
    const Rect.fromLTWH(71, 207, 149, 7),
    Paint()..color = const Color(0xFF183445),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(256, 256);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return _Pattern(
      image,
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _rgba(ui.Image image) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return Uint8List.fromList(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}

Future<Uint8List> _raster(
  Size size,
  void Function(Canvas) paint, {
  String? capture,
}) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final pixels = await _rgba(image);
    final directory = Platform.environment['RESOURCE_STARTUP_CAPTURE_DIR'];
    if (capture != null && directory != null && directory.isNotEmpty) {
      final destination = Directory(directory);
      await destination.create(recursive: true);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('${destination.path}/pyramid-$capture.png').writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    }
    return pixels;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _actual(
  _Pyramid fixture,
  Size size,
  BdoMapVisualStyle style,
  String capture,
) => _raster(
  size,
  (canvas) => fixture.painter(style).paint(canvas, size),
  capture: capture,
);

typedef _ExpectedTile = ({
  ui.Image image,
  Rect source,
  Rect world,
  bool ancestor,
});

// An independent, explicit image/crop oracle. It does not ask the manager to
// select a tile or reuse the production ancestor/destination calculation.
Future<Uint8List> _expected(
  BdoMapCamera camera,
  Size size,
  BdoMapVisualStyle style,
  List<_ExpectedTile> tiles,
) => _raster(size, (canvas) {
  canvas.drawRect(Offset.zero & size, Paint()..color = _chrome.canvas);
  final scale = _source.scaleForZoom(camera.zoom);
  for (final tile in tiles) {
    final destination = Rect.fromLTWH(
      size.width / 2 + (tile.world.left - camera.center.x) * scale,
      size.height / 2 + (tile.world.top - camera.center.y) * scale,
      tile.world.width * scale,
      tile.world.height * scale,
    );
    canvas.drawImageRect(
      tile.image,
      tile.source,
      destination.inflate(tile.ancestor ? .5 : .35),
      Paint()
        ..filterQuality = FilterQuality.low
        ..colorFilter = style == BdoMapVisualStyle.vivid
            ? const ColorFilter.matrix([
                1.10,
                -.08,
                -.01,
                0,
                -4,
                -.04,
                1.11,
                -.03,
                0,
                -2,
                -.03,
                -.08,
                1.16,
                0,
                -1,
                0,
                0,
                0,
                1,
                0,
              ])
            : null,
    );
  }
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x0C071112), Color(0x19050C0D)],
      ).createShader(Offset.zero & size),
  );
});

void _samePixels(Uint8List actual, Uint8List expected, String reason) {
  expect(actual.length, expected.length, reason: reason);
  final mismatch = actual.indexed.where(
    (entry) => entry.$2 != expected[entry.$1],
  );
  expect(mismatch.take(8).toList(), isEmpty, reason: reason);
}

Future<List<_ExpectedTile>> _overviewOracle(_Pyramid fixture) async => [
  for (final coordinate in _overview)
    (
      image: (await fixture.pattern(coordinate)).image,
      source: _wholeImage,
      world: Rect.fromLTWH(
        coordinate.x * 1024.0,
        coordinate.y * 1024.0,
        1024,
        1024,
      ),
      ancestor: false,
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final style in BdoMapVisualStyle.values) {
    testWidgets(
      'cold signed pyramid selects missing, parent and exact ${style.name}',
      (tester) async {
        await tester.runAsync(() async {
          final fixture = _Pyramid();
          try {
            fixture.update(_stageSize);
            await fixture.until(
              () => {
                _left,
                _right,
                _parent,
                _grandparent,
              }.every(fixture.transport.pending.containsKey),
              'the four gated cold requests are visible',
            );
            expect(fixture.manager.visibleCoordinates, {_left, _right});
            expect(fixture.manager.decodedTileCount, 0);
            final missing = await _actual(
              fixture,
              _stageSize,
              style,
              '${style.name}-missing',
            );
            _samePixels(
              missing,
              await _expected(fixture.camera.camera, _stageSize, style, []),
              'No hidden fallback before any image arrives.',
            );

            await fixture.transport.release(_parent);
            await fixture.until(
              () => fixture.manager.tile(_parent) != null,
              'parent decodes',
            );
            final parentTile = fixture.manager.tile(_parent)!;
            expect(fixture.manager.nearestAncestor(_left), same(parentTile));
            expect(fixture.manager.nearestAncestor(_right), same(parentTile));
            final parent = (await fixture.pattern(_parent)).image;
            const leftWorld = Rect.fromLTWH(-512, -256, 256, 256);
            const rightWorld = Rect.fromLTWH(-256, -256, 256, 256);
            final parentDraws = <_ExpectedTile>[
              (
                image: parent,
                source: const Rect.fromLTWH(0, 128, 128, 128),
                world: leftWorld,
                ancestor: true,
              ),
              (
                image: parent,
                source: const Rect.fromLTWH(128, 128, 128, 128),
                world: rightWorld,
                ancestor: true,
              ),
            ];
            final fallback = await _actual(
              fixture,
              _stageSize,
              style,
              '${style.name}-ancestor',
            );
            _samePixels(
              fallback,
              await _expected(
                fixture.camera.camera,
                _stageSize,
                style,
                parentDraws,
              ),
              'Negative child coordinates use the correct bottom parent quadrants.',
            );
            expect(listEquals(missing, fallback), isFalse);

            final revision = fixture.manager.decodedTileRevision;
            await fixture.transport.release(_left);
            await fixture.until(
              () => fixture.manager.tile(_left) != null,
              'left exact tile decodes',
            );
            expect(fixture.manager.tile(_right), isNull);
            expect(fixture.manager.decodedTileRevision, greaterThan(revision));
            final leftTile = fixture.manager.tile(_left)!;
            _samePixels(
              await _rgba(leftTile.image),
              await _rgba((await fixture.pattern(_left)).image),
              'The left exact decoded image has its own coordinate identity.',
            );
            final mixedDraws = <_ExpectedTile>[
              (
                image: (await fixture.pattern(_left)).image,
                source: _wholeImage,
                world: leftWorld,
                ancestor: false,
              ),
              parentDraws[1],
            ];
            final mixed = await _actual(
              fixture,
              _stageSize,
              style,
              '${style.name}-mixed',
            );
            _samePixels(
              mixed,
              await _expected(
                fixture.camera.camera,
                _stageSize,
                style,
                mixedDraws,
              ),
              'Only the completed child replaces its parent.',
            );
            expect(listEquals(fallback, mixed), isFalse);

            await fixture.transport.release(_right);
            await fixture.until(
              () => fixture.manager.tile(_right) != null,
              'right exact tile decodes',
            );
            final rightTile = fixture.manager.tile(_right)!;
            expect(identical(leftTile.image, rightTile.image), isFalse);
            expect(
              listEquals(
                await _rgba(leftTile.image),
                await _rgba(rightTile.image),
              ),
              isFalse,
            );
            final exactDraws = <_ExpectedTile>[
              mixedDraws[0],
              (
                image: (await fixture.pattern(_right)).image,
                source: _wholeImage,
                world: rightWorld,
                ancestor: false,
              ),
            ];
            final exact = await _actual(
              fixture,
              _stageSize,
              style,
              '${style.name}-exact',
            );
            _samePixels(
              exact,
              await _expected(
                fixture.camera.camera,
                _stageSize,
                style,
                exactDraws,
              ),
              'Every exact coordinate has its own pixels and crop.',
            );
            expect(listEquals(mixed, exact), isFalse);

            await fixture.transport.release(_grandparent);
            await fixture.idle();
            expect(fixture.manager.tile(_left), same(leftTile));
            expect(fixture.manager.tile(_right), same(rightTile));
            _samePixels(
              await _actual(
                fixture,
                _stageSize,
                style,
                '${style.name}-late-ancestor',
              ),
              exact,
              'A later ancestor cannot replace an already exact image.',
            );
          } finally {
            await fixture.dispose();
          }
        });
      },
    );

    for (final evict in [false, true]) {
      testWidgets(
        'deep zoom then globe preserves ${evict ? 'redecoded' : 'retained'} overview ${style.name}',
        (tester) async {
          await tester.runAsync(() async {
            final fixture = _Pyramid(decodedTileCapacity: evict ? 6 : 64);
            try {
              fixture.camera.reset(_overviewSize);
              final home = fixture.camera.camera;
              fixture.update(_overviewSize);
              await fixture.transport.open();
              await fixture.idle();
              expect(fixture.manager.visibleCoordinates, _overview);
              expect(fixture.manager.failedVisibleTileCount, 0);
              final original = <BdoTileCoordinate, BdoDecodedTile>{
                for (final coordinate in _overview)
                  coordinate: fixture.manager.tile(coordinate)!,
              };
              final originalPixels = <BdoTileCoordinate, Uint8List>{
                for (final entry in original.entries)
                  entry.key: await _rgba(entry.value.image),
              };
              final requestsBefore = Map<BdoTileCoordinate, int>.of(
                fixture.transport.calls,
              );
              final before = await _actual(
                fixture,
                _overviewSize,
                style,
                '${style.name}-${evict ? 'evicted' : 'retained'}-overview-before',
              );
              _samePixels(
                before,
                await _expected(
                  home,
                  _overviewSize,
                  style,
                  await _overviewOracle(fixture),
                ),
                'The initial overview uses four distinct exact coordinates.',
              );

              fixture.camera.zoomAround(
                zoom: 3.35,
                anchor: _overviewSize.center(Offset.zero),
                viewport: _overviewSize,
              );
              fixture.update(_overviewSize);
              await fixture.idle();
              expect(fixture.camera.camera.zoom, 3.35);
              expect(
                fixture.manager.visibleCoordinates.every(
                  (coordinate) => coordinate.zoom == 3,
                ),
                isTrue,
              );
              expect(
                fixture.manager.visibleCoordinates.every(
                  (coordinate) => fixture.manager.tile(coordinate) != null,
                ),
                isTrue,
              );
              final deep = await _actual(
                fixture,
                _overviewSize,
                style,
                '${style.name}-${evict ? 'evicted' : 'retained'}-deep',
              );
              expect(
                listEquals(before, deep),
                isFalse,
                reason:
                    'The intervening LOD must actually change visible pixels.',
              );
              final lost = _overview
                  .where(
                    (coordinate) => fixture.manager.tile(coordinate) == null,
                  )
                  .toSet();
              expect(
                lost.isNotEmpty,
                evict,
                reason:
                    'Exercise actual manager LRU eviction, not a substituted fixture map.',
              );

              // This is the production globe callback, not an exact-camera
              // normalization that could conceal drift in the reset calculation.
              fixture.camera.reset(_overviewSize);
              expect(fixture.camera.camera.center, home.center);
              expect(fixture.camera.camera.zoom, home.zoom);
              fixture.update(_overviewSize);
              expect(fixture.manager.visibleCoordinates, _overview);
              if (evict) {
                // Higher-detail descendants must not stand in for missing
                // overview tiles, even though they remain decoded in the cache.
                for (final coordinate in lost) {
                  expect(fixture.manager.tile(coordinate), isNull);
                  expect(fixture.manager.nearestAncestor(coordinate), isNull);
                }
                final returning = await _actual(
                  fixture,
                  _overviewSize,
                  style,
                  '${style.name}-evicted-return-before-decode',
                );
                expect(listEquals(before, returning), isFalse);
              }
              await fixture.idle();
              for (final coordinate in _overview) {
                final tile = fixture.manager.tile(coordinate)!;
                expect(
                  identical(tile, original[coordinate]),
                  !lost.contains(coordinate),
                );
                if (lost.contains(coordinate)) expect(tile.fromDisk, isTrue);
                _samePixels(
                  await _rgba(tile.image),
                  originalPixels[coordinate]!,
                  'Re-decoding preserves exact bytes for $coordinate.',
                );
                expect(
                  fixture.transport.calls[coordinate],
                  requestsBefore[coordinate],
                  reason:
                      'Overview restoration reads the fixture cache, not a changed upstream image.',
                );
              }
              _samePixels(
                await _actual(
                  fixture,
                  _overviewSize,
                  style,
                  '${style.name}-${evict ? 'evicted' : 'retained'}-overview-after',
                ),
                before,
                'Deep zoom plus the real reset leaves the completed overview unchanged.',
              );
            } finally {
              await fixture.dispose();
            }
          });
        },
      );
    }
  }

  testWidgets(
    'current retry behavior: failed exact tile stays a fallback until explicit retry',
    (tester) async {
      await tester.runAsync(() async {
        final fixture = _Pyramid();
        try {
          fixture.update(_stageSize);
          await fixture.until(
            () => fixture.transport.pending.length == 4,
            'initial gated requests',
          );
          await fixture.transport.release(
            _left,
            status: HttpStatus.serviceUnavailable,
          );
          await fixture.transport.open();
          await fixture.idle();
          expect(fixture.manager.failedVisibleTileCount, 1);
          expect(fixture.manager.serviceState, BdoTileServiceState.degraded);
          expect(fixture.manager.tile(_left), isNull);
          expect(fixture.manager.nearestAncestor(_left)!.coordinate, _parent);
          final exactRight = fixture.manager.tile(_right)!;
          final calls = fixture.transport.calls[_left];
          final builds = fixture.manager.debugViewportBuildCount;
          final fallback = await _actual(
            fixture,
            _stageSize,
            BdoMapVisualStyle.vivid,
            'retry-failed-fallback',
          );

          fixture.update(_stageSize);
          expect(fixture.manager.debugViewportBuildCount, builds);
          expect(fixture.manager.activeRequestCount, 0);
          expect(fixture.manager.queuedRequestCount, 0);
          expect(fixture.transport.calls[_left], calls);
          _samePixels(
            await _actual(
              fixture,
              _stageSize,
              BdoMapVisualStyle.vivid,
              'retry-unchanged-viewport',
            ),
            fallback,
            'A repaint or same viewport does not repair a failed exact tile.',
          );

          // Characterization only: this does not advance real DateTime past the
          // backoff or imply that a missing tile caused the monitor symptom.
          fixture.manager.retryVisible();
          await fixture.idle();
          expect(fixture.transport.calls[_left], calls! + 1);
          expect(fixture.manager.failedVisibleTileCount, 0);
          expect(fixture.manager.serviceState, BdoTileServiceState.online);
          expect(fixture.manager.tile(_right), same(exactRight));
          expect(fixture.manager.tile(_left), isNotNull);
          final repaired = await _actual(
            fixture,
            _stageSize,
            BdoMapVisualStyle.vivid,
            'retry-exact-repaired',
          );
          expect(listEquals(fallback, repaired), isFalse);
          _samePixels(
            await _rgba(fixture.manager.tile(_left)!.image),
            await _rgba((await fixture.pattern(_left)).image),
            'Retry restores the correct exact image, not an ancestor or adjacent tile.',
          );
        } finally {
          await fixture.dispose();
        }
      });
    },
  );
}
