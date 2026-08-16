import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/state/state_test_fixture.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory source;
  late Directory control;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'black-spirit-life-personal-data-',
    );
    source = Directory(_join(temporaryDirectory.path, 'source-profile'));
    control = Directory(_join(temporaryDirectory.path, 'bootstrap'));
    await _writeProfile(source);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('uses the default profile when no custom locator exists', () async {
    final service = _service(source: source, control: control);

    final resolved = await service.resolveApplicationDirectory();

    expect(_samePath(resolved.path, source.path), isTrue);
    expect(await service.locatorFile.exists(), isFalse);
  });

  test('moves, verifies, switches, and removes the old profile', () async {
    final destination = Directory(
      _join(temporaryDirectory.path, 'Møved profile'),
    );
    final service = _service(source: source, control: control);

    final result = await service.moveTo(destination.path);

    expect(result.cleanupPending, isFalse);
    expect(await source.exists(), isFalse);
    expect(await destination.exists(), isTrue);
    expect(
      await File(_join(destination.path, 'planner-state.json')).exists(),
      isTrue,
    );
    expect(
      await File(
        _join(destination.path, 'icons/custom icon.png'),
      ).readAsString(),
      'icon bytes',
    );
    expect(
      await File(
        _join(
          destination.path,
          PersonalDataLocationService.profileMarkerFileName,
        ),
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        _join(
          destination.path,
          PersonalDataLocationService.moveManifestFileName,
        ),
      ).exists(),
      isFalse,
    );
    expect(await service.locatorFile.exists(), isTrue);
    expect(await service.locatorMirrorFile.exists(), isTrue);
    expect(await service.journalFile.exists(), isFalse);

    final restarted = _service(source: source, control: control);
    expect(
      _samePath(
        (await restarted.resolveApplicationDirectory()).path,
        destination.path,
      ),
      isTrue,
    );
  });

  test(
    'a nonempty destination is rejected without changing either folder',
    () async {
      final destination = Directory(
        _join(temporaryDirectory.path, 'existing-data'),
      );
      await destination.create(recursive: true);
      final unrelated = File(_join(destination.path, 'unrelated.txt'));
      await unrelated.writeAsString('keep me', flush: true);
      final service = _service(source: source, control: control);

      await expectLater(
        service.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>().having(
            (error) => error.locationSwitched,
            'locationSwitched',
            isFalse,
          ),
        ),
      );

      expect(await source.exists(), isTrue);
      expect(await unrelated.readAsString(), 'keep me');
      expect(await service.locatorFile.exists(), isFalse);
    },
  );

  test(
    'failure before locator switch rolls back the verified staging copy',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final service = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) {
          if (checkpoint == PersonalDataMoveCheckpoint.copiedAndVerified) {
            throw StateError('simulated interruption');
          }
        },
      );

      await expectLater(
        service.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>().having(
            (error) => error.locationSwitched,
            'locationSwitched',
            isFalse,
          ),
        ),
      );

      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isFalse);
      expect(await service.locatorFile.exists(), isFalse);
      expect(await service.journalFile.exists(), isFalse);
    },
  );

  test(
    'pre-switch recovery preserves the verified copy when the source vanished',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) async {
          if (checkpoint == PersonalDataMoveCheckpoint.destinationPromoted) {
            await source.delete(recursive: true);
            throw StateError('simulated source drive loss');
          }
        },
      );

      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>().having(
            (error) => error.locationSwitched,
            'locationSwitched',
            isFalse,
          ),
        ),
      );
      expect(await source.exists(), isFalse);
      expect(await destination.exists(), isTrue);
      expect(await interrupted.journalFile.exists(), isTrue);
      expect(await interrupted.locatorFile.exists(), isFalse);

      final restarted = _service(source: source, control: control);
      await expectLater(
        restarted.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.exists(), isTrue);
      expect(await restarted.journalFile.exists(), isTrue);
    },
  );

  test(
    'pre-switch recovery preserves the verified copy without source ownership proof',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) async {
          if (checkpoint == PersonalDataMoveCheckpoint.destinationPromoted) {
            await File(
              _join(
                source.path,
                PersonalDataLocationService.moveSourceSentinelFileName,
              ),
            ).delete();
            throw StateError('simulated lost ownership marker');
          }
        },
      );

      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(isA<PersonalDataMoveException>()),
      );
      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isTrue);
      expect(await interrupted.journalFile.exists(), isTrue);
      expect(await interrupted.locatorFile.exists(), isFalse);

      final restarted = _service(source: source, control: control);
      await expectLater(
        restarted.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isTrue);
      expect(await restarted.journalFile.exists(), isTrue);
    },
  );

  test(
    'startup finishes cleanup after a crash just after locator switch',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) {
          if (checkpoint == PersonalDataMoveCheckpoint.locatorSwitched) {
            throw StateError('simulated process exit');
          }
        },
      );

      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>().having(
            (error) => error.locationSwitched,
            'locationSwitched',
            isTrue,
          ),
        ),
      );
      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isTrue);
      expect(await interrupted.journalFile.exists(), isTrue);

      final restarted = _service(source: source, control: control);
      final resolved = await restarted.resolveApplicationDirectory();

      expect(_samePath(resolved.path, destination.path), isTrue);
      expect(await source.exists(), isFalse);
      expect(await restarted.journalFile.exists(), isFalse);
    },
  );

  test(
    'startup visibly retains a cleanup notice while the old copy is locked',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) {
          if (checkpoint == PersonalDataMoveCheckpoint.locatorSwitched) {
            throw StateError('simulated process exit');
          }
        },
      );
      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(isA<PersonalDataMoveException>()),
      );

      final restarted = _service(
        source: source,
        control: control,
        sourceCleanup: (_) =>
            throw const FileSystemException('simulated locked source'),
      );
      final resolved = await restarted.resolveApplicationDirectory();

      expect(_samePath(resolved.path, destination.path), isTrue);
      expect(await source.exists(), isTrue);
      expect(await restarted.journalFile.exists(), isTrue);
      expect(restarted.startupNotices, hasLength(1));
      expect(restarted.startupNotices.single, contains(source.path));
      expect(restarted.startupNotices.single, contains('retry next start'));
    },
  );

  test(
    'startup refuses cleanup when the verified destination was changed',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) {
          if (checkpoint == PersonalDataMoveCheckpoint.locatorSwitched) {
            throw StateError('simulated process exit');
          }
        },
      );
      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>().having(
            (error) => error.locationSwitched,
            'locationSwitched',
            isTrue,
          ),
        ),
      );
      await File(
        _join(destination.path, 'icons/custom icon.png'),
      ).writeAsString('changed after verification', flush: true);

      final restarted = _service(source: source, control: control);
      await expectLater(
        restarted.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );

      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isTrue);
      expect(await restarted.journalFile.exists(), isTrue);
    },
  );

  test(
    'startup completes after source removal but before journal cleanup',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) {
          if (checkpoint ==
              PersonalDataMoveCheckpoint.sourceRemovedBeforeJournalCleanup) {
            throw StateError('simulated process exit');
          }
        },
      );

      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>().having(
            (error) => error.locationSwitched,
            'locationSwitched',
            isTrue,
          ),
        ),
      );
      expect(await source.exists(), isFalse);
      expect(await interrupted.journalFile.exists(), isTrue);
      expect(
        await File(
          _join(
            destination.path,
            PersonalDataLocationService.moveManifestFileName,
          ),
        ).exists(),
        isTrue,
      );

      final restarted = _service(source: source, control: control);
      final resolved = await restarted.resolveApplicationDirectory();

      expect(_samePath(resolved.path, destination.path), isTrue);
      expect(await restarted.journalFile.exists(), isFalse);
    },
  );

  test(
    'a confirmed locator commit is never rolled back after a late error',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final service = _service(
        source: source,
        control: control,
        locatorCommitter: _CommitThenThrow(),
      );

      final result = await service.moveTo(destination.path);

      expect(result.cleanupPending, isFalse);
      expect(await source.exists(), isFalse);
      expect(await destination.exists(), isTrue);
      expect(
        _samePath(
          (await _service(
            source: source,
            control: control,
          ).resolveApplicationDirectory()).path,
          destination.path,
        ),
        isTrue,
      );
    },
  );

  test(
    'a missing configured folder fails instead of creating empty defaults',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final service = _service(source: source, control: control);
      await service.moveTo(destination.path);
      await destination.delete(recursive: true);

      final restarted = _service(source: source, control: control);

      await expectLater(
        restarted.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await source.exists(), isFalse);
    },
  );

  test(
    'the committed locator mirror restores a deleted first-move locator',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final moved = _service(source: source, control: control);
      await moved.moveTo(destination.path);
      await moved.locatorFile.delete();

      final restarted = _service(source: source, control: control);
      final resolved = await restarted.resolveApplicationDirectory();

      expect(_samePath(resolved.path, destination.path), isTrue);
      expect(restarted.requiresExistingProfile, isTrue);
      expect(await source.exists(), isFalse);
      expect(await restarted.locatorFile.exists(), isTrue);
      expect(await restarted.locatorMirrorFile.exists(), isTrue);
    },
  );

  test(
    'the committed locator mirror repairs a corrupt primary locator',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final moved = _service(source: source, control: control);
      await moved.moveTo(destination.path);
      await moved.locatorFile.writeAsString('not a locator', flush: true);

      final restarted = _service(source: source, control: control);
      final resolved = await restarted.resolveApplicationDirectory();

      expect(_samePath(resolved.path, destination.path), isTrue);
      expect(restarted.requiresExistingProfile, isTrue);
      expect(await source.exists(), isFalse);
      final repaired = await restarted.locatorFile.readAsString();
      final decoded = jsonDecode(repaired) as Map<String, Object?>;
      expect(
        _samePath(decoded['applicationDirectory']! as String, destination.path),
        isTrue,
      );
    },
  );

  test('source descendants and protected folders are rejected', () async {
    final service = _service(
      source: source,
      control: control,
      protected: <Directory>[
        Directory(_join(temporaryDirectory.path, 'protected')),
      ],
    );

    await expectLater(
      service.moveTo(_join(source.path, 'nested')),
      throwsA(isA<PersonalDataMoveException>()),
    );
    await expectLater(
      service.moveTo(_join(temporaryDirectory.path, 'protected/nested')),
      throwsA(isA<PersonalDataMoveException>()),
    );
    await expectLater(
      service.moveTo(control.path),
      throwsA(isA<PersonalDataMoveException>()),
    );
    expect(await source.exists(), isTrue);
  });

  test('physical path aliases cannot enter a protected install tree', () async {
    final protectedRoot = Directory(
      _join(temporaryDirectory.path, 'physical-install-root'),
    );
    await protectedRoot.create(recursive: true);
    final aliasRoot = Directory(_join(temporaryDirectory.path, 'alias-root'));
    final requested = _join(aliasRoot.path, 'Personal Data');
    final service = _service(
      source: source,
      control: control,
      protected: <Directory>[protectedRoot],
      physicalPathResolver: (path) async {
        final normalized = Directory(path).absolute.path;
        final aliasPrefix = Directory(aliasRoot.path).absolute.path;
        if (normalized.toLowerCase() == aliasPrefix.toLowerCase() ||
            normalized.toLowerCase().startsWith(
              '${aliasPrefix.toLowerCase()}${Platform.pathSeparator}',
            )) {
          return '${protectedRoot.path}${normalized.substring(aliasPrefix.length)}';
        }
        return normalized;
      },
    );

    await expectLater(
      service.moveTo(requested),
      throwsA(isA<PersonalDataMoveException>()),
    );

    expect(await source.exists(), isTrue);
    expect(await service.locatorFile.exists(), isFalse);
    expect(await service.journalFile.exists(), isFalse);
  });

  test(
    'a current source inside a protected install tree is never copied or cleaned',
    () async {
      final installRoot = Directory(
        _join(temporaryDirectory.path, 'protected-install'),
      );
      final installedSource = Directory(
        _join(installRoot.path, 'current/Personal Data'),
      );
      await _writeProfile(installedSource);
      final destination = Directory(
        _join(temporaryDirectory.path, 'safe-destination'),
      );
      var cleanupCalled = false;
      final service = _service(
        source: installedSource,
        control: control,
        protected: <Directory>[installRoot],
        sourceCleanup: (directory) async {
          cleanupCalled = true;
          await directory.delete(recursive: true);
        },
      );

      await expectLater(
        service.moveTo(destination.path),
        throwsA(
          isA<PersonalDataMoveException>()
              .having(
                (error) => error.locationSwitched,
                'locationSwitched',
                isFalse,
              )
              .having(
                (error) => error.message,
                'message',
                contains('current personal-data folder overlaps'),
              ),
        ),
      );

      expect(cleanupCalled, isFalse);
      expect(await installedSource.exists(), isTrue);
      expect(await destination.exists(), isFalse);
      expect(await service.locatorFile.exists(), isFalse);
      expect(await service.journalFile.exists(), isFalse);
    },
  );

  test(
    'a current source containing the bootstrap folder is never relocated',
    () async {
      final overlappingControl = Directory(_join(source.path, 'Bootstrap'));
      final destination = Directory(
        _join(temporaryDirectory.path, 'safe-destination'),
      );
      final service = _service(source: source, control: overlappingControl);

      await expectLater(
        service.moveTo(destination.path),
        throwsA(isA<PersonalDataMoveException>()),
      );

      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isFalse);
      expect(await service.journalFile.exists(), isFalse);
    },
  );

  test(
    'recovery refuses source cleanup after that source becomes protected',
    () async {
      final destination = Directory(_join(temporaryDirectory.path, 'new-data'));
      final interrupted = _service(
        source: source,
        control: control,
        checkpointHook: (checkpoint) {
          if (checkpoint == PersonalDataMoveCheckpoint.locatorSwitched) {
            throw StateError('simulated process exit');
          }
        },
      );
      await expectLater(
        interrupted.moveTo(destination.path),
        throwsA(isA<PersonalDataMoveException>()),
      );
      expect(await source.exists(), isTrue);
      expect(await interrupted.journalFile.exists(), isTrue);

      final restarted = _service(
        source: source,
        control: control,
        protected: <Directory>[source.parent],
      );
      await expectLater(
        restarted.resolveApplicationDirectory(),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('current personal-data folder overlaps'),
          ),
        ),
      );

      expect(await source.exists(), isTrue);
      expect(await destination.exists(), isTrue);
      expect(await restarted.journalFile.exists(), isTrue);
    },
  );

  test(
    'the Velopack-owned install root is never a personal-data destination',
    () async {
      final roaming = Directory(_join(temporaryDirectory.path, 'roaming'));
      final local = Directory(_join(temporaryDirectory.path, 'local'));
      final environmentSource = Directory(
        _join(roaming.path, AppIdentity.stateDirectoryName),
      );
      await _writeProfile(environmentSource);
      final service = PersonalDataLocationService.fromEnvironment(
        <String, String>{'APPDATA': roaming.path, 'LOCALAPPDATA': local.path},
      );
      final destination = _join(
        _join(local.path, AppIdentity.installerPackageId),
        'Personal Data',
      );

      await expectLater(
        service.moveTo(destination),
        throwsA(isA<PersonalDataMoveException>()),
      );

      expect(await environmentSource.exists(), isTrue);
      expect(await Directory(destination).exists(), isFalse);
    },
  );

  test(
    'a current executable protects its complete custom Velopack install root',
    () async {
      final roaming = Directory(_join(temporaryDirectory.path, 'roaming'));
      final local = Directory(_join(temporaryDirectory.path, 'local'));
      final environmentSource = Directory(
        _join(roaming.path, AppIdentity.stateDirectoryName),
      );
      await _writeProfile(environmentSource);
      final installRoot = Directory(
        _join(temporaryDirectory.path, 'Custom Beta Installation'),
      );
      final current = Directory(_join(installRoot.path, 'current'));
      await current.create(recursive: true);
      final executable = File(_join(current.path, 'BlackSpiritLife.exe'));
      await executable.writeAsBytes(const <int>[77, 90], flush: true);
      final service = PersonalDataLocationService.fromEnvironment(
        <String, String>{'APPDATA': roaming.path, 'LOCALAPPDATA': local.path},
        resolvedExecutable: executable.path,
      );
      final destination = _join(installRoot.path, 'Personal Data');

      await expectLater(
        service.moveTo(destination),
        throwsA(isA<PersonalDataMoveException>()),
      );

      expect(await environmentSource.exists(), isTrue);
      expect(await Directory(destination).exists(), isFalse);
    },
  );

  test('a non-current executable protects only its executable directory', () {
    final roaming = Directory(_join(temporaryDirectory.path, 'roaming'));
    final local = Directory(_join(temporaryDirectory.path, 'local'));
    final executableDirectory = Directory(
      _join(temporaryDirectory.path, 'Standalone/bin'),
    );
    final executable = File(
      _join(executableDirectory.path, 'BlackSpiritLife.exe'),
    );
    final service = PersonalDataLocationService.fromEnvironment(
      <String, String>{'APPDATA': roaming.path, 'LOCALAPPDATA': local.path},
      resolvedExecutable: executable.path,
    );

    expect(
      service.protectedDirectories.any(
        (directory) => _samePath(directory.path, executableDirectory.path),
      ),
      isTrue,
    );
    expect(
      service.protectedDirectories.any(
        (directory) =>
            _samePath(directory.path, executableDirectory.parent.path),
      ),
      isFalse,
    );
  });

  test(
    'moving back to the default still requires an existing recoverable profile',
    () async {
      final custom = Directory(
        _join(temporaryDirectory.path, 'custom-profile'),
      );
      final first = _service(source: source, control: control);
      await first.moveTo(custom.path);
      final second = _service(source: source, control: control);
      await second.resolveApplicationDirectory();
      await second.moveTo(source.path);

      final restarted = _service(source: source, control: control);
      final resolved = await restarted.resolveApplicationDirectory();
      expect(_samePath(resolved.path, source.path), isTrue);
      expect(restarted.requiresExistingProfile, isTrue);

      final main = File(
        _join(source.path, PlannerStateRepository.stateFileName),
      );
      await main.delete();
      final repository = PlannerStateRepository(
        paths: PlannerStatePathPolicy(
          applicationDirectory: resolved,
          legacyStateFile: File(_join(temporaryDirectory.path, 'legacy.json')),
        ),
        applicationVersion: 'test',
      );
      final recovered = await repository.load(
        _emptyCatalog(),
        requireExistingProfile: restarted.requiresExistingProfile,
      );
      expect(recovered.origin, PlannerStateLoadOrigin.recoveredBackup);

      await repository.nativeStateFile.delete();
      for (final backup
          in source
              .listSync(followLinks: false)
              .whereType<File>()
              .where(
                (file) => file.uri.pathSegments.last.startsWith(
                  '${PlannerStateRepository.stateFileName}.backup-',
                ),
              )) {
        await backup.delete();
      }
      await expectLater(
        PlannerStateRepository(
          paths: repository.paths,
          applicationVersion: 'test',
        ).load(
          _emptyCatalog(),
          requireExistingProfile: restarted.requiresExistingProfile,
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}

PersonalDataLocationService _service({
  required Directory source,
  required Directory control,
  Iterable<Directory> protected = const <Directory>[],
  PersonalDataMoveCheckpointHook? checkpointHook,
  AtomicFileCommitter locatorCommitter = const RenameAtomicFileCommitter(),
  PersonalDataSourceCleanup? sourceCleanup,
  PersonalDataPhysicalPathResolver? physicalPathResolver,
}) => PersonalDataLocationService(
  defaultDirectory: source,
  controlDirectory: control,
  protectedDirectories: protected,
  checkpointHook: checkpointHook,
  locatorCommitter: locatorCommitter,
  sourceCleanup: sourceCleanup,
  physicalPathResolver: physicalPathResolver,
);

Future<void> _writeProfile(Directory directory) async {
  await directory.create(recursive: true);
  await File(_join(directory.path, 'planner-state.json')).writeAsString(
    const PlannerStateJsonCodec().encode(buildStateFixture()),
    flush: true,
  );
  final icon = File(_join(directory.path, 'icons/custom icon.png'));
  await icon.parent.create(recursive: true);
  await icon.writeAsString('icon bytes', flush: true);
  await File(
    _join(directory.path, 'planner-state.json.backup-1'),
  ).writeAsString(
    const PlannerStateJsonCodec().encode(buildStateFixture()),
    flush: true,
  );
}

final class _CommitThenThrow implements AtomicFileCommitter {
  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    await stagedFile.rename(targetFile.path);
    throw const FileSystemException('simulated post-commit failure');
  }
}

CatalogSnapshot _emptyCatalog() {
  ModeCatalog mode(CraftMode value) => ModeCatalog(
    mode: value,
    items: const <String, Recipe>{},
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  );
  return CatalogSnapshot(
    sourceSha256: 'test',
    sourceByteCount: 0,
    alchemy: mode(CraftMode.alchemy),
    cooking: mode(CraftMode.cooking),
    processing: mode(CraftMode.processing),
    supportingData: const <String, Object?>{},
    collisions: const <CaseCollision>[],
  );
}

bool _samePath(String left, String right) =>
    Directory(left).absolute.path.toLowerCase() ==
    Directory(right).absolute.path.toLowerCase();

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}${child.replaceAll('/', Platform.pathSeparator)}';
