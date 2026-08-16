import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory roaming;
  late Directory local;
  late Map<String, String> environment;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bsl-former-profile-test-');
    roaming = await Directory(_join(root.path, 'Roaming')).create();
    local = await Directory(_join(root.path, 'Local')).create();
    environment = <String, String>{
      'APPDATA': roaming.path,
      'LOCALAPPDATA': local.path,
    };
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'uses the untouched former default profile when no locator exists',
    () async {
      final resolved = await const FormerPersonalDataProfileResolver().resolve(
        environment,
      );

      expect(resolved.path, _join(roaming.path, 'Black Spirit Life Beta'));
    },
  );

  test(
    'uses the committed former custom location with exact ownership',
    () async {
      final custom = await Directory(
        _join(root.path, 'Former custom'),
      ).create();
      await File(_join(custom.path, 'planner-state.json')).writeAsString('{}');
      await File(
        _join(custom.path, PersonalDataLocationService.profileMarkerFileName),
      ).writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'packageId': 'BlackSpiritLife.App.Beta',
          'releaseChannel': 'win-x64-beta',
          'profile': true,
          'profileId': 'profile-1-${List<String>.filled(32, 'a').join()}',
          'transactionId': 'move-2-${List<String>.filled(32, 'b').join()}',
        }),
      );
      final control = await _controlDirectory(local).create(recursive: true);
      await File(
        _join(control.path, PersonalDataLocationService.locatorMirrorFileName),
      ).writeAsString(_formerIdentity(custom.path));

      final resolved = await const FormerPersonalDataProfileResolver().resolve(
        environment,
      );

      expect(resolved.path, custom.path);
    },
  );

  test(
    'unfinished former move fails closed instead of selecting stale data',
    () async {
      final control = await _controlDirectory(local).create(recursive: true);
      await File(
        _join(control.path, PersonalDataLocationService.journalFileName),
      ).writeAsString('{}');

      await expectLater(
        const FormerPersonalDataProfileResolver().resolve(environment),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'an unreadable committed mirror is not bypassed by the primary copy',
    () async {
      final custom = await Directory(
        _join(root.path, 'Former custom'),
      ).create();
      final control = await _controlDirectory(local).create(recursive: true);
      await File(
        _join(control.path, PersonalDataLocationService.locatorFileName),
      ).writeAsString(_formerIdentity(custom.path));
      await File(
        _join(control.path, PersonalDataLocationService.locatorMirrorFileName),
      ).writeAsString('{broken');

      await expectLater(
        const FormerPersonalDataProfileResolver().resolve(environment),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'Stable relocation protects the former profile but not its own source',
    () {
      final executable = _join(_join(root.path, 'app'), 'BlackSpiritLife.exe');
      final service = PersonalDataLocationService.fromEnvironment(
        environment,
        resolvedExecutable: executable,
      );

      final protected = service.protectedDirectories
          .map((directory) => directory.path.toLowerCase())
          .toSet();
      expect(
        protected,
        contains(_join(roaming.path, 'Black Spirit Life Beta').toLowerCase()),
      );
      expect(
        protected,
        isNot(
          contains(
            _join(roaming.path, AppIdentity.stateDirectoryName).toLowerCase(),
          ),
        ),
      );
    },
  );
}

Directory _controlDirectory(Directory local) => Directory(
  _join(
    _join(local.path, 'Black Spirit Life Beta'),
    PersonalDataLocationService.bootstrapDirectoryName,
  ),
);

String _formerIdentity(String applicationDirectory) =>
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'packageId': 'BlackSpiritLife.App.Beta',
      'releaseChannel': 'win-x64-beta',
      'applicationDirectory': applicationDirectory,
    });

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}$right';
