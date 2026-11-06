import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/shared_profile_guard.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../domain/state/state_test_fixture.dart';

Matcher samePath(String expected) => predicate<String>(
  (actual) =>
      actual.replaceAll('\\', '/').toLowerCase() ==
      expected.replaceAll('\\', '/').toLowerCase(),
  'the same Windows path as $expected',
);

void main() {
  late Directory fixture;
  late Map<String, String> environment;
  late PersonalDataLocationService legacy;
  late PersonalDataLocationService shared;
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp(
      'bsl-stable-shared-upgrade-',
    );
    environment = {
      'APPDATA': '${fixture.path}/roaming',
      'LOCALAPPDATA': '${fixture.path}/local',
      'BSL_DOCUMENTS_DIR': '${fixture.path}/documents',
    };
    legacy = PersonalDataLocationService.fromEnvironment(
      environment,
      resolvedExecutable: '${fixture.path}/old/current/app.exe',
    );
    shared = PersonalDataLocationService.fromEnvironment(
      environment,
      shared: true,
      resolvedExecutable: '${fixture.path}/new/current/app.exe',
    );
  });
  tearDown(() async {
    await shared.sharedProfileGuard!.release();
    await fixture.delete(recursive: true);
  });
  Future<File> save(Directory root) async {
    await root.create(recursive: true);
    final file = File('${root.path}/planner-state.json');
    await file.writeAsString(
      const PlannerStateJsonCodec().encode(buildStateFixture()),
    );
    return file;
  }

  test('fresh installs retain the Documents default', () async {
    expect(
      (await shared.resolveApplicationDirectory()).path,
      samePath(shared.defaultDirectory.path),
    );
    expect(await shared.locatorFile.exists(), isFalse);
  });
  test(
    'default Stable save and every companion file stay in the same folder',
    () async {
      final old = await legacy.resolveApplicationDirectory();
      final state = await save(old);
      final before = await state.readAsBytes();
      final files = <String, List<int>>{
        'fishing/fish-journal.sqlite3': [1, 2, 3],
        'fishing/fish-journal.sqlite3-wal': [4, 5],
        'fishing/fish-journal.sqlite3-shm': [6, 7],
        'gathering/sessions.json': [123, 125],
        'planner-state.json.bak': [9, 8],
        'icons/custom.png': [2, 4],
      };
      for (final entry in files.entries) {
        final f = File('${old.path}/${entry.key}');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(entry.value);
      }
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(old.path),
      );
      expect(shared.requiresExistingProfile, isTrue);
      expect(await state.readAsBytes(), before);
      for (final entry in files.entries) {
        expect(
          await File('${old.path}/${entry.key}').readAsBytes(),
          entry.value,
        );
      }
      expect(
        await File('${old.path}/${SharedProfileGuard.markerName}').exists(),
        isTrue,
      );
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(old.path),
      );
    },
  );
  test(
    'keeps the existing custom folder and locators recover on reopen',
    () async {
      await save(await legacy.resolveApplicationDirectory());
      final selected = Directory('${fixture.path}/chosen-profile');
      await legacy.moveTo(selected.path);
      final oldLocator = await legacy.locatorFile.readAsBytes();
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(selected.path),
      );
      expect(await legacy.locatorFile.readAsBytes(), oldLocator);
      await shared.locatorFile.delete();
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(selected.path),
      );
      expect(await shared.locatorFile.exists(), isTrue);
    },
  );
  test(
    'existing shared profile wins without touching the old Stable save',
    () async {
      final oldState = await save(await legacy.resolveApplicationDirectory());
      final before = await oldState.readAsBytes();
      final fresh = await shared.resolveApplicationDirectory();
      // First adoption is established; replacing old state must not trigger a merge.
      await oldState.writeAsString('invalid now');
      await expectLater(
        shared.resolveApplicationDirectory(),
        throwsA(isA<FormatException>()),
      );
      expect(await oldState.readAsString(), 'invalid now');
      expect(fresh.path, samePath(legacy.defaultDirectory.path));
      expect(before, isNotEmpty);
    },
  );
  test(
    'pre-existing Documents shared profile is preferred over Stable',
    () async {
      final old = await legacy.resolveApplicationDirectory();
      await save(old);
      final documents = shared.defaultDirectory;
      await documents.create(recursive: true);
      await shared.sharedProfileGuard!.verify(documents);
      await save(documents);
      await shared.sharedProfileGuard!.markInitialized(documents);
      final oldBefore = await Directory(
        old.path,
      ).list().map((f) => f.path).toList();
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(documents.path),
      );
      expect(
        await Directory(old.path).list().map((f) => f.path).toList(),
        oldBefore,
      );
      expect(await shared.locatorFile.exists(), isFalse);
    },
  );
  test(
    'invalid old save fails closed without new locator or shared marker',
    () async {
      final old = await legacy.resolveApplicationDirectory();
      await old.create(recursive: true);
      await File(
        '${old.path}/planner-state.json',
      ).writeAsString('{"schemaVersion":2}');
      await expectLater(
        shared.resolveApplicationDirectory(),
        throwsA(anything),
      );
      expect(await shared.locatorFile.exists(), isFalse);
      expect(
        await File('${old.path}/${SharedProfileGuard.markerName}').exists(),
        isFalse,
      );
      expect(await shared.defaultDirectory.exists(), isFalse);
    },
  );
  test(
    'foreign or unmarked nonempty Documents folder is never replaced',
    () async {
      await save(await legacy.resolveApplicationDirectory());
      await shared.defaultDirectory.create(recursive: true);
      final sentinel = File('${shared.defaultDirectory.path}/do-not-touch.txt');
      await sentinel.writeAsString('keep');
      await expectLater(
        shared.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsString(), 'keep');
      expect(await shared.locatorFile.exists(), isFalse);
    },
  );
  test(
    'interrupted marker-first adoption resumes without replacing saved bytes',
    () async {
      final old = await legacy.resolveApplicationDirectory();
      final state = await save(old);
      await shared.sharedProfileGuard!.adoptExistingProfile(old);
      final before = await state.readAsBytes();
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(old.path),
      );
      expect(await state.readAsBytes(), before);
    },
  );
  test(
    'invalid existing shared marker is not overwritten during adoption',
    () async {
      final old = await legacy.resolveApplicationDirectory();
      await save(old);
      final marker = File('${old.path}/${SharedProfileGuard.markerName}');
      await marker.writeAsString(jsonEncode({'formatVersion': 999}));
      await expectLater(
        shared.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );
      final savedMarker =
          jsonDecode(await marker.readAsString()) as Map<String, Object?>;
      expect(savedMarker['formatVersion'], 999);
      expect(await shared.locatorFile.exists(), isFalse);
    },
  );
  test(
    'an intentional old reset without a save does not revive old contents',
    () async {
      final old = await legacy.resolveApplicationDirectory();
      await old.create(recursive: true);
      await File(
        '${old.path}/${AppIdentity.intentionalResetMarkerFileName}',
      ).writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'packageId': AppIdentity.installerPackageId,
          'releaseChannel': AppIdentity.releaseChannel,
          'intentionalReset': true,
          'transactionId': 'synthetic-reset',
        }),
      );
      expect(
        (await shared.resolveApplicationDirectory()).path,
        samePath(shared.defaultDirectory.path),
      );
      expect(await shared.locatorFile.exists(), isFalse);
    },
  );
}
