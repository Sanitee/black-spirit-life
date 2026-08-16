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
}

class _FailingCommitter implements AtomicFileCommitter {
  const _FailingCommitter();

  @override
  Future<void> replace(File stagedFile, File targetFile) {
    throw const FileSystemException('Injected commit failure.');
  }
}
