import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/shared_profile_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late Directory personal;
  late SharedProfileGuard guard;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('bsl-shared-profile-');
    personal = Directory('${fixture.path}/Documents/Black Spirit Life');
    guard = SharedProfileGuard(Directory('${fixture.path}/control'));
  });
  tearDown(() async {
    await guard.release();
    await fixture.delete(recursive: true);
  });

  test(
    'empty shared profile gets a contract; missing initialized save fails',
    () async {
      await guard.acquire();
      await guard.verify(personal);
      final marker = File('${personal.path}/${SharedProfileGuard.markerName}');
      expect(
        (jsonDecode(await marker.readAsString())
            as Map)['requiresExistingState'],
        false,
      );
      final state = File('${personal.path}/planner-state.json');
      await state.writeAsString('{"schemaVersion":1}');
      await guard.markInitialized(personal);
      expect(
        (jsonDecode(await marker.readAsString())
            as Map)['requiresExistingState'],
        true,
      );
      await state.delete();
      final before = await marker.readAsString();
      await expectLater(
        guard.verify(personal),
        throwsA(isA<FileSystemException>()),
      );
      expect(await state.exists(), false);
      expect(await marker.readAsString(), before);
    },
  );

  test('existing unmarked folder is not adopted or overwritten', () async {
    await personal.create(recursive: true);
    final file = File('${personal.path}/planner-state.json');
    await file.writeAsString('{"schemaVersion":1,"inventory":"keep"}');
    await expectLater(
      guard.verify(personal),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), '{"schemaVersion":1,"inventory":"keep"}');
    expect(
      await File('${personal.path}/${SharedProfileGuard.markerName}').exists(),
      false,
    );
  });

  test(
    'newer contract and planner schema fail without recovery or rewriting',
    () async {
      await guard.verify(personal);
      final marker = File('${personal.path}/${SharedProfileGuard.markerName}');
      final contract =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      for (final field in [
        'formatVersion',
        'minimumReaderVersion',
        'minimumWriterVersion',
      ]) {
        await marker.writeAsString(jsonEncode({...contract, field: 2}));
        final before = await marker.readAsString();
        await expectLater(
          guard.verify(personal),
          throwsA(isA<FileSystemException>()),
        );
        expect(await marker.readAsString(), before);
      }
      await marker.writeAsString(jsonEncode(contract));
      final state = File('${personal.path}/planner-state.json');
      await state.writeAsString('{"schemaVersion":2}');
      await expectLater(
        guard.verify(personal),
        throwsA(isA<FileSystemException>()),
      );
      expect(await state.readAsString(), '{"schemaVersion":2}');
      expect(await personal.list().length, 2);
    },
  );

  test(
    'Windows known Documents and shared control root are independent of executable',
    () async {
      final env = {
        'APPDATA': '${fixture.path}/roaming',
        'LOCALAPPDATA': '${fixture.path}/local',
        'BSL_DOCUMENTS_DIR': '${fixture.path}/redirected-documents',
      };
      final first = PersonalDataLocationService.fromEnvironment(
        env,
        shared: true,
        resolvedExecutable: '${fixture.path}/version-one/app.exe',
      );
      final second = PersonalDataLocationService.fromEnvironment(
        env,
        shared: true,
        resolvedExecutable: '${fixture.path}/version-two/app.exe',
      );
      addTearDown(first.sharedProfileGuard!.release);
      addTearDown(second.sharedProfileGuard!.release);
      final firstPath = await first.resolveApplicationDirectory();
      expect(
        firstPath.path.replaceAll('\\', '/'),
        '${fixture.path}/redirected-documents/Black Spirit Life'.replaceAll(
          '\\',
          '/',
        ),
      );
      expect(first.controlDirectory.path, second.controlDirectory.path);
      expect(
        first.runtimeDirectory!.path.contains('redirected-documents'),
        false,
      );
      if (Platform.isWindows) {
        await expectLater(
          second.resolveApplicationDirectory(),
          throwsA(isA<FileSystemException>()),
        );
      }
      await first.sharedProfileGuard!.release();
      expect((await second.resolveApplicationDirectory()).path, firstPath.path);
    },
  );

  test(
    'missing known Documents path never falls back to an empty legacy profile',
    () {
      expect(
        () => PersonalDataLocationService.fromEnvironment({
          'APPDATA': '${fixture.path}/roaming',
          'LOCALAPPDATA': '${fixture.path}/local',
        }, shared: true),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  final dart = Platform.environment['BSL_DART_EXECUTABLE'];
  test(
    'a different process cannot take the lease; crash releases it',
    () async {
      await guard.acquire();
      final blocked = await Process.run(dart!, [
        'tool/shared_profile_lease_probe.dart',
        guard.controlDirectory.path,
      ]);
      expect(
        blocked.exitCode,
        42,
        reason: '${blocked.stdout}\n${blocked.stderr}',
      );
      await guard.release();
      final process = await Process.start(dart, [
        'tool/shared_profile_lease_probe.dart',
        guard.controlDirectory.path,
        'hold',
      ]);
      expect(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'held',
      );
      await expectLater(guard.acquire(), throwsA(isA<FileSystemException>()));
      expect(process.kill(), isTrue);
      await process.exitCode;
      // Windows can signal process exit just before closing its file handles.
      // Confirm bounded eventual release, not same-tick kernel cleanup.
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (true) {
        try {
          await guard.acquire();
          break;
        } on FileSystemException {
          if (DateTime.now().isAfter(deadline)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    },
    skip: dart == null
        ? 'Set BSL_DART_EXECUTABLE for the real multiprocess gate.'
        : false,
  );
}
