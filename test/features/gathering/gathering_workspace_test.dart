import 'dart:io';

import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy Gathering journal is copied once without touching the source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'black-spirit-gathering-migration-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final legacy = Directory('${root.path}${Platform.pathSeparator}legacy');
      final destination = Directory(
        '${root.path}${Platform.pathSeparator}personal${Platform.pathSeparator}gathering',
      );
      await legacy.create(recursive: true);
      final source = File(
        '${legacy.path}${Platform.pathSeparator}sessions.json',
      );
      final sourceBackup = File('${source.path}.bak');
      const original = '{"schemaVersion":1,"sessions":[{"id":"kept"}]}';
      const backup = '{"schemaVersion":1,"sessions":[]}';
      await source.writeAsString(original, flush: true);
      await sourceBackup.writeAsString(backup, flush: true);

      await migrateLegacyGatheringSessions(
        destinationDirectory: destination,
        legacyDirectory: legacy,
      );

      final migrated = File(
        '${destination.path}${Platform.pathSeparator}sessions.json',
      );
      expect(await migrated.readAsString(), original);
      expect(await File('${migrated.path}.bak').readAsString(), backup);
      expect(await source.readAsString(), original);
      expect(await sourceBackup.readAsString(), backup);

      await migrated.writeAsString('new integrated journal', flush: true);
      await source.writeAsString('new standalone journal', flush: true);
      await migrateLegacyGatheringSessions(
        destinationDirectory: destination,
        legacyDirectory: legacy,
      );
      expect(await migrated.readAsString(), 'new integrated journal');
      expect(await source.readAsString(), 'new standalone journal');
    },
  );
}
