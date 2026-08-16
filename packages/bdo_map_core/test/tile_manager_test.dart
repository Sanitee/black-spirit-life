import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pure pan inside one tile range skips viewport rebuilding', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_tile_signature_test_',
      );
      final client = MockClient(
        (request) async => http.Response('', HttpStatus.notFound),
      );
      const source = BdoTileSource(
        id: 'signature-test',
        displayName: 'Signature test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 1024, bottom: 1024),
        attribution: 'Test fixture',
        usageNotice: 'Test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 256,
        fileExtension: 'png',
      );
      final manager = BdoTileManager(
        source: source,
        diskCache: BdoMapDiskCache(
          rootDirectory: temporary,
          sourceNamespace: source.id,
        ),
        client: client,
      );
      try {
        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: 20,
            top: 20,
            right: 180,
            bottom: 180,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        expect(manager.debugViewportBuildCount, 1);

        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: 35,
            top: 28,
            right: 195,
            bottom: 188,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        expect(
          manager.debugViewportBuildCount,
          1,
          reason: 'Sub-tile panning must not rebuild coordinate sets.',
        );

        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: 110,
            top: 28,
            right: 270,
            bottom: 188,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        expect(manager.debugViewportBuildCount, 2);
      } finally {
        manager.dispose();
        client.close();
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      }
    });
  });

  testWidgets('loads, decodes, and memory-caches a visible tile set', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_tile_manager_test_',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
        'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final client = MockClient(
        (request) async => http.Response.bytes(
          png,
          HttpStatus.ok,
          headers: const <String, String>{'content-type': 'image/png'},
        ),
      );
      const source = BdoTileSource(
        id: 'manager-test',
        displayName: 'Manager test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(
          left: -100000,
          top: -100000,
          right: 100000,
          bottom: 100000,
        ),
        attribution: 'Test fixture',
        usageNotice: 'Test fixture',
        fileExtension: 'png',
      );
      final manager = BdoTileManager(
        source: source,
        diskCache: BdoMapDiskCache(
          rootDirectory: temporary,
          sourceNamespace: source.id,
        ),
        client: client,
      );
      try {
        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: -90000,
            top: -90000,
            right: 90000,
            bottom: 90000,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while ((manager.activeRequestCount > 0 ||
                manager.queuedRequestCount > 0) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(manager.activeRequestCount, 0);
        expect(manager.queuedRequestCount, 0);
        expect(manager.decodedTileCount, 4);
        expect(manager.failedVisibleTileCount, 0);
        expect(manager.serviceState, BdoTileServiceState.online);

        expect(await manager.clearCache(), greaterThan(0));
        expect(manager.decodedTileCount, 0);
        expect(manager.decodedBytes, 0);
        expect(manager.networkEnabled, isFalse);
        expect(manager.serviceState, BdoTileServiceState.offlineMissing);
        expect(manager.offlineMissingVisibleTileCount, greaterThan(0));
        expect(await manager.diskCache.byteSize(), 0);
      } finally {
        manager.dispose();
        client.close();
      }
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_tile_manager_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
  });

  testWidgets(
    'decoded revision advances when the LRU replaces a tile at constant count',
    (tester) async {
      await tester.runAsync(() async {
        final temporary = await Directory.systemTemp.createTemp(
          'bdo_tile_revision_test_',
        );
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
          'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final client = MockClient(
          (request) async => http.Response.bytes(png, HttpStatus.ok),
        );
        const source = BdoTileSource(
          id: 'revision-test',
          displayName: 'Revision test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(
            left: -100000,
            top: -100000,
            right: 100000,
            bottom: 100000,
          ),
          attribution: 'Test fixture',
          usageNotice: 'Test fixture',
          fileExtension: 'png',
        );
        final manager = BdoTileManager(
          source: source,
          diskCache: BdoMapDiskCache(
            rootDirectory: temporary,
            sourceNamespace: source.id,
          ),
          client: client,
          maximumDecodedBytes: 256 * 256 * 4,
        );
        try {
          manager.updateViewport(
            visibleBounds: const BdoMapBounds(
              left: -90000,
              top: -90000,
              right: 90000,
              bottom: 90000,
            ),
            zoom: 0,
            prefetchRing: 0,
          );
          await _waitUntilIdle(manager);

          expect(manager.decodedTileCount, 1);
          expect(manager.decodedTileRevision, 4);
        } finally {
          manager.dispose();
          client.close();
          await _removeTestDirectory(temporary, 'bdo_tile_revision_test_');
        }
      });
    },
  );

  testWidgets('invalid cached bytes are removed and recovered from network', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_tile_poison_test_',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
        'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount += 1;
        return http.Response.bytes(png, HttpStatus.ok);
      });
      const source = BdoTileSource(
        id: 'poison-test',
        displayName: 'Poison recovery test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 1000, bottom: 1000),
        attribution: 'Test fixture',
        usageNotice: 'Test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 1000,
        fileExtension: 'png',
      );
      final cache = BdoMapDiskCache(
        rootDirectory: temporary,
        sourceNamespace: source.id,
      );
      const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
      await cache.write(
        coordinate,
        Uint8List.fromList(utf8.encode('<html>not an image</html>')),
        extension: 'png',
      );
      final manager = BdoTileManager(
        source: source,
        diskCache: cache,
        client: client,
      );
      try {
        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: 1,
            top: 1,
            right: 999,
            bottom: 999,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while ((manager.activeRequestCount > 0 ||
                manager.queuedRequestCount > 0) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(requestCount, 1);
        expect(manager.decodedTileCount, 1);
        expect(manager.failedVisibleTileCount, 0);
        expect(await cache.read(coordinate, extension: 'png'), png);
      } finally {
        manager.dispose();
        client.close();
      }
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_tile_poison_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
  });

  testWidgets('cached-only state overrides an earlier network success', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_tile_mode_test_',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
        'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final client = MockClient(
        (request) async => http.Response.bytes(png, HttpStatus.ok),
      );
      const source = BdoTileSource(
        id: 'mode-test',
        displayName: 'Mode transition test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 1000, bottom: 1000),
        attribution: 'Test fixture',
        usageNotice: 'Test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 1000,
        fileExtension: 'png',
      );
      final manager = BdoTileManager(
        source: source,
        diskCache: BdoMapDiskCache(
          rootDirectory: temporary,
          sourceNamespace: source.id,
        ),
        client: client,
      );
      try {
        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: 1,
            top: 1,
            right: 999,
            bottom: 999,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        await _waitUntilIdle(manager);
        expect(manager.serviceState, BdoTileServiceState.online);

        manager.networkEnabled = false;

        expect(manager.serviceState, BdoTileServiceState.cachedOnly);
        expect(manager.offlineMissingVisibleTileCount, 0);
      } finally {
        manager.dispose();
        client.close();
        await _removeTestDirectory(temporary, 'bdo_tile_mode_test_');
      }
    });
  });

  testWidgets('late network response is ignored after cached-only is chosen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_tile_late_response_test_',
      );
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
        'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final requestStarted = Completer<void>();
      final response = Completer<http.Response>();
      final client = MockClient((request) {
        if (!requestStarted.isCompleted) {
          requestStarted.complete();
        }
        return response.future;
      });
      const source = BdoTileSource(
        id: 'late-response-test',
        displayName: 'Late response test',
        urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
        worldBounds: BdoMapBounds(left: 0, top: 0, right: 1000, bottom: 1000),
        attribution: 'Test fixture',
        usageNotice: 'Test fixture',
        minimumZoom: 0,
        maximumZoom: 0,
        worldUnitsAtZoomZero: 1000,
        fileExtension: 'png',
      );
      final cache = BdoMapDiskCache(
        rootDirectory: temporary,
        sourceNamespace: source.id,
      );
      final manager = BdoTileManager(
        source: source,
        diskCache: cache,
        client: client,
      );
      try {
        manager.updateViewport(
          visibleBounds: const BdoMapBounds(
            left: 1,
            top: 1,
            right: 999,
            bottom: 999,
          ),
          zoom: 0,
          prefetchRing: 0,
        );
        await requestStarted.future.timeout(const Duration(seconds: 2));
        manager.networkEnabled = false;
        response.complete(http.Response.bytes(png, HttpStatus.ok));
        await _waitUntilIdle(manager);

        expect(manager.decodedTileCount, 0);
        expect(manager.offlineMissingVisibleTileCount, 1);
        expect(manager.serviceState, BdoTileServiceState.offlineMissing);
        expect(await cache.byteSize(), 0);
      } finally {
        manager.dispose();
        client.close();
        await _removeTestDirectory(temporary, 'bdo_tile_late_response_test_');
      }
    });
  });

  testWidgets(
    'late poison-recovery response cannot refill cache in cached-only mode',
    (tester) async {
      await tester.runAsync(() async {
        final temporary = await Directory.systemTemp.createTemp(
          'bdo_tile_poison_race_test_',
        );
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
          'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        );
        final requestStarted = Completer<void>();
        final response = Completer<http.Response>();
        final client = MockClient((request) {
          if (!requestStarted.isCompleted) {
            requestStarted.complete();
          }
          return response.future;
        });
        const source = BdoTileSource(
          id: 'poison-race-test',
          displayName: 'Poison race test',
          urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
          worldBounds: BdoMapBounds(left: 0, top: 0, right: 1000, bottom: 1000),
          attribution: 'Test fixture',
          usageNotice: 'Test fixture',
          minimumZoom: 0,
          maximumZoom: 0,
          worldUnitsAtZoomZero: 1000,
          fileExtension: 'png',
        );
        final cache = BdoMapDiskCache(
          rootDirectory: temporary,
          sourceNamespace: source.id,
        );
        const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
        await cache.write(
          coordinate,
          Uint8List.fromList(utf8.encode('not an image')),
          extension: 'png',
        );
        final manager = BdoTileManager(
          source: source,
          diskCache: cache,
          client: client,
        );
        try {
          manager.updateViewport(
            visibleBounds: const BdoMapBounds(
              left: 1,
              top: 1,
              right: 999,
              bottom: 999,
            ),
            zoom: 0,
            prefetchRing: 0,
          );
          await requestStarted.future.timeout(const Duration(seconds: 2));
          manager.networkEnabled = false;
          response.complete(http.Response.bytes(png, HttpStatus.ok));
          await _waitUntilIdle(manager);

          expect(manager.decodedTileCount, 0);
          expect(manager.offlineMissingVisibleTileCount, 1);
          expect(manager.serviceState, BdoTileServiceState.offlineMissing);
          expect(await cache.read(coordinate, extension: 'png'), isNull);
        } finally {
          manager.dispose();
          client.close();
          await _removeTestDirectory(temporary, 'bdo_tile_poison_race_test_');
        }
      });
    },
  );
}

Future<void> _waitUntilIdle(BdoTileManager manager) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while ((manager.activeRequestCount > 0 || manager.queuedRequestCount > 0) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(manager.activeRequestCount, 0);
  expect(manager.queuedRequestCount, 0);
}

Future<void> _removeTestDirectory(Directory directory, String marker) async {
  final resolved = directory.absolute.path;
  expect(
    resolved.contains(marker),
    isTrue,
    reason: 'Only the test-created temporary directory may be removed.',
  );
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
