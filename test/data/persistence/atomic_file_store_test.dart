import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bdo-state-store-test-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  void validateJson(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> || value['revision'] is! int) {
      throw const FormatException('Invalid synthetic state.');
    }
  }

  test(
    'flushes, validates, replaces, and retains the prior valid bytes',
    () async {
      var tick = 0;
      final store = AtomicFileStore(
        directory: directory,
        fileName: 'planner-state.json',
        utcNow: () => DateTime.fromMicrosecondsSinceEpoch(++tick, isUtc: true),
      );

      final first = await store.writeJson({
        'revision': 1,
      }, validate: validateJson);
      final second = await store.writeJson({
        'revision': 2,
      }, validate: validateJson);

      expect(first.backupPath, isNull);
      expect(second.backupPath, isNotNull);
      expect(jsonDecode(await File(store.targetPath).readAsString()), {
        'revision': 2,
      });
      expect(jsonDecode(await File(second.backupPath!).readAsString()), {
        'revision': 1,
      });
      expect(second.byteCount, greaterThan(0));
      expect(second.sha256, hasLength(64));
    },
  );

  test('validation failure leaves the last valid target untouched', () async {
    final store = AtomicFileStore(
      directory: directory,
      fileName: 'planner-state.json',
    );
    await store.writeJson({'revision': 1}, validate: validateJson);

    await expectLater(
      store.writeBytes(
        Uint8List.fromList(utf8.encode('{"wrong":true}')),
        validate: validateJson,
      ),
      throwsFormatException,
    );

    expect(jsonDecode(await File(store.targetPath).readAsString()), {
      'revision': 1,
    });
    final temporaryFiles = await directory
        .list()
        .where((entity) => entity.path.endsWith('.tmp'))
        .toList();
    expect(temporaryFiles, isEmpty);
  });

  test('serializes concurrent writes so the newer request wins', () async {
    final store = AtomicFileStore(
      directory: directory,
      fileName: 'planner-state.json',
    );

    final first = store.writeJson({'revision': 1}, validate: validateJson);
    final second = store.writeJson({'revision': 2}, validate: validateJson);
    await Future.wait([first, second]);

    expect(jsonDecode(await File(store.targetPath).readAsString()), {
      'revision': 2,
    });
  });

  test('commit failure leaves the target and backup recoverable', () async {
    final initialStore = AtomicFileStore(
      directory: directory,
      fileName: 'planner-state.json',
    );
    await initialStore.writeJson({'revision': 1}, validate: validateJson);
    final failingStore = AtomicFileStore(
      directory: directory,
      fileName: 'planner-state.json',
      committer: const _FailingCommitter(),
    );

    await expectLater(
      failingStore.writeJson({'revision': 2}, validate: validateJson),
      throwsA(isA<FileSystemException>()),
    );

    expect(jsonDecode(await File(failingStore.targetPath).readAsString()), {
      'revision': 1,
    });
    expect(
      await directory
          .list()
          .where((entity) => entity.path.contains('.backup-'))
          .length,
      1,
    );
  });

  test('rejects paths instead of accepting an arbitrary target', () {
    expect(
      () => AtomicFileStore(directory: directory, fileName: '..\\state.json'),
      throwsArgumentError,
    );
  });

  test('strict default never replaces an invalid existing state', () async {
    final store = AtomicFileStore(
      directory: directory,
      fileName: 'planner-state.json',
    );
    await File(store.targetPath).writeAsString('{broken');
    await expectLater(
      store.writeJson({'revision': 1}, validate: validateJson),
      throwsFormatException,
    );
    expect(await File(store.targetPath).readAsString(), '{broken');
    expect(await directory.list().length, 1);
  });

  test(
    'cache opt-in preserves each invalid original without name collisions',
    () async {
      final now = DateTime.utc(2026, 9, 11);
      for (var revision = 1; revision <= 2; revision++) {
        // A replacement store with the same clock starts its sequence at zero.
        final store = AtomicFileStore(
          directory: directory,
          fileName: 'cache.json',
          utcNow: () => now,
          preserveMalformedTarget: true,
        );
        await File(store.targetPath).writeAsString('broken-$revision');
        await store.writeJson({'revision': revision}, validate: validateJson);
        expect(jsonDecode(await File(store.targetPath).readAsString()), {
          'revision': revision,
        });
      }
      final originals = await directory
          .list()
          .where((entry) => entry.path.contains('.corrupt-'))
          .cast<File>()
          .toList();
      expect(originals, hasLength(2));
      expect(
        await Future.wait(originals.map((file) => file.readAsString())),
        unorderedEquals(['broken-1', 'broken-2']),
      );
    },
  );

  test(
    'cache opt-in still rejects invalid replacement before preservation',
    () async {
      final store = AtomicFileStore(
        directory: directory,
        fileName: 'cache.json',
        preserveMalformedTarget: true,
      );
      await File(store.targetPath).writeAsString('broken-original');
      await expectLater(
        store.writeJson({'wrong': true}, validate: validateJson),
        throwsFormatException,
      );
      expect(await File(store.targetPath).readAsString(), 'broken-original');
      expect(await directory.list().length, 1);
    },
  );

  test(
    'failed cache recovery commit never removes the active target',
    () async {
      final store = AtomicFileStore(
        directory: directory,
        fileName: 'cache.json',
        preserveMalformedTarget: true,
        committer: const _FailingCommitter(),
      );
      await File(store.targetPath).writeAsString('broken-original');
      await expectLater(
        store.writeJson({'revision': 1}, validate: validateJson),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(store.targetPath).readAsString(), 'broken-original');
      final original = await directory
          .list()
          .where((entry) => entry.path.contains('.corrupt-'))
          .cast<File>()
          .single;
      expect(await original.readAsString(), 'broken-original');
      expect(await directory.list().length, 2);
    },
  );
}

class _FailingCommitter implements AtomicFileCommitter {
  const _FailingCommitter();

  @override
  Future<void> replace(File stagedFile, File targetFile) {
    throw const FileSystemException('Injected commit failure.');
  }
}
