import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'disk cache round-trips encoded bytes in its provider namespace',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_map_cache_test_',
      );
      addTearDown(() async {
        final resolved = temporary.absolute.path;
        expect(
          resolved.contains('bdo_map_cache_test_'),
          isTrue,
          reason: 'Only the test-created temporary directory may be removed.',
        );
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      });
      final cache = BdoMapDiskCache(
        rootDirectory: temporary,
        sourceNamespace: 'provider:test',
        maximumBytes: 1024,
      );
      const coordinate = BdoTileCoordinate(zoom: 4, x: -7, y: 12);
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

      await cache.write(coordinate, bytes, extension: 'webp');

      expect(await cache.read(coordinate, extension: 'webp'), bytes);
      expect(await cache.byteSize(), bytes.length);
      expect(cache.directory.path, contains('provider_test'));

      expect(await cache.clear(), bytes.length);
      expect(await cache.byteSize(), 0);
      expect(await cache.directory.exists(), isTrue);
    },
  );

  test('an unavailable cache directory degrades to no-op storage', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdo_map_cache_unavailable_test_',
    );
    addTearDown(() async {
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_map_cache_unavailable_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
    final obstruction = File(
      '${temporary.path}${Platform.pathSeparator}not-a-directory',
    );
    await obstruction.writeAsString('cache path obstruction');
    final cache = BdoMapDiskCache(
      rootDirectory: Directory(obstruction.path),
      sourceNamespace: 'provider',
    );
    const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);

    expect(await cache.read(coordinate, extension: 'webp'), isNull);
    await cache.write(
      coordinate,
      Uint8List.fromList(<int>[1, 2, 3]),
      extension: 'webp',
    );
    expect(await cache.byteSize(), 0);
    expect(await cache.clear(), 0);
  });

  test('dot-only and empty provider namespaces are rejected', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdo_map_cache_namespace_test_',
    );
    addTearDown(() async {
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_map_cache_namespace_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    for (final namespace in <String>['', '   ', '.', '..', '...']) {
      expect(
        () => BdoMapDiskCache(
          rootDirectory: temporary,
          sourceNamespace: namespace,
        ),
        throwsArgumentError,
        reason: '"$namespace" must not resolve to the root or its parent.',
      );
    }
  });

  test('unsafe namespace characters remain inside one cache child', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdo_map_cache_containment_test_',
    );
    addTearDown(() async {
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_map_cache_containment_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
    final cache = BdoMapDiskCache(
      rootDirectory: temporary,
      sourceNamespace: '../provider\\tiles:revision',
    );

    expect(cache.directory.parent.absolute.path, temporary.absolute.path);
    expect(cache.directory.path, endsWith('.._provider_tiles_revision'));
    await cache.initialize();
    expect(await cache.directory.exists(), isTrue);
  });

  test('tile extensions cannot escape the provider directory', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdo_map_cache_extension_test_',
    );
    addTearDown(() async {
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_map_cache_extension_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
    final cache = BdoMapDiskCache(
      rootDirectory: temporary,
      sourceNamespace: 'provider',
    );
    const coordinate = BdoTileCoordinate(zoom: 0, x: 0, y: 0);
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    for (final extension in <String>[
      '',
      '.',
      '../webp',
      r'..\webp',
      'webp/../../outside',
      r'webp\..\..\outside',
      'webp.tmp',
    ]) {
      await expectLater(
        cache.read(coordinate, extension: extension),
        throwsArgumentError,
        reason: '"$extension" must not reach a path outside the cache.',
      );
      await expectLater(
        cache.write(coordinate, bytes, extension: extension),
        throwsArgumentError,
        reason: '"$extension" must not create a path outside the cache.',
      );
      await expectLater(
        cache.remove(coordinate, extension: extension),
        throwsArgumentError,
        reason: '"$extension" must not delete a path outside the cache.',
      );
    }

    expect(await cache.directory.exists(), isFalse);
  });

  test('every completed write leaves the disk cache within its cap', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdo_map_cache_cap_test_',
    );
    addTearDown(() async {
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_map_cache_cap_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
    final cache = BdoMapDiskCache(
      rootDirectory: temporary,
      sourceNamespace: 'strict-cap',
      maximumBytes: 10,
    );
    const first = BdoTileCoordinate(zoom: 1, x: 0, y: 0);
    const second = BdoTileCoordinate(zoom: 1, x: 1, y: 0);
    final firstBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
    final secondBytes = Uint8List.fromList(<int>[7, 8, 9, 10, 11, 12]);

    await cache.write(first, firstBytes, extension: 'webp');
    expect(await cache.byteSize(), lessThanOrEqualTo(cache.maximumBytes));

    await cache.write(second, secondBytes, extension: 'webp');

    expect(await cache.byteSize(), lessThanOrEqualTo(cache.maximumBytes));
    expect(await cache.read(first, extension: 'webp'), isNull);
    expect(await cache.read(second, extension: 'webp'), secondBytes);
  });

  test('an oversized item is skipped without evicting useful tiles', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdo_map_cache_oversize_test_',
    );
    addTearDown(() async {
      final resolved = temporary.absolute.path;
      expect(
        resolved.contains('bdo_map_cache_oversize_test_'),
        isTrue,
        reason: 'Only the test-created temporary directory may be removed.',
      );
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
    final cache = BdoMapDiskCache(
      rootDirectory: temporary,
      sourceNamespace: 'oversize',
      maximumBytes: 5,
    );
    const retained = BdoTileCoordinate(zoom: 1, x: 0, y: 0);
    const oversized = BdoTileCoordinate(zoom: 1, x: 1, y: 0);
    final retainedBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    await cache.write(retained, retainedBytes, extension: 'webp');
    await cache.write(
      oversized,
      Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]),
      extension: 'webp',
    );

    expect(await cache.read(retained, extension: 'webp'), retainedBytes);
    expect(await cache.read(oversized, extension: 'webp'), isNull);
    expect(await cache.byteSize(), retainedBytes.length);
  });

  test(
    'a file that survives clear remains counted against the cap',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'bdo_map_cache_locked_clear_test_',
      );
      File? retainedFile;
      addTearDown(() async {
        if (retainedFile != null && await retainedFile.exists()) {
          await Process.run('attrib', <String>['-R', retainedFile.path]);
        }
        final resolved = temporary.absolute.path;
        expect(
          resolved.contains('bdo_map_cache_locked_clear_test_'),
          isTrue,
          reason: 'Only the test-created temporary directory may be removed.',
        );
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      });
      final cache = BdoMapDiskCache(
        rootDirectory: temporary,
        sourceNamespace: 'locked-clear',
        maximumBytes: 10,
      );
      const retained = BdoTileCoordinate(zoom: 1, x: 0, y: 0);
      const rejected = BdoTileCoordinate(zoom: 1, x: 1, y: 0);
      final retainedBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      await cache.write(retained, retainedBytes, extension: 'webp');
      retainedFile = File(
        '${cache.directory.path}${Platform.pathSeparator}1_0_0.webp',
      );
      final attributeResult = await Process.run('attrib', <String>[
        '+R',
        retainedFile.path,
      ]);
      expect(attributeResult.exitCode, 0);

      expect(await cache.clear(), 0);
      await cache.write(
        rejected,
        Uint8List.fromList(<int>[5, 6, 7, 8, 9, 10, 11, 12]),
        extension: 'webp',
      );

      expect(await cache.read(retained, extension: 'webp'), retainedBytes);
      expect(await cache.read(rejected, extension: 'webp'), isNull);
      expect(await cache.byteSize(), retainedBytes.length);
    },
    skip: !Platform.isWindows,
  );
}
