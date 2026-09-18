import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/services/stable_v017_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disposable stable-v0.1.7 Gathering first-open migration', () async {
    final directoryPath = Platform.environment['BSL_GATHERING_GATE_ROOT'];
    final resultPath = Platform.environment['BSL_GATHERING_GATE_RESULT'];
    expect(directoryPath, isNotNull);
    expect(resultPath, isNotNull);
    final directory = Directory(directoryPath!).absolute;
    final migrated = await migrateStableV017GatheringData(
      directory: directory,
      nowUtc: () => DateTime.utc(2026, 9, 16),
    );
    final store = SessionStore(directory: directory);
    await store.load();
    await store.flush();
    expect(migrated, isTrue);
    expect(store.sessions, hasLength(1));
    await File(resultPath!).writeAsString(
      jsonEncode(<String, Object?>{
        'migrated': migrated,
        'sessions': store.sessions.length,
        'preferences': store.preferences.keys.toList()..sort(),
        'destination': store.file.path,
      }),
      flush: true,
    );
  });
}
