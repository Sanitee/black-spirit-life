import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/features/gathering/gathering_personal_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'black-spirit-life-gathering-store-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('starts empty and reads only the selected personal-data root', () async {
    final unrelatedLegacy = Directory(
      _join(temporaryDirectory.path, 'BDO Gathering Companion'),
    );
    await unrelatedLegacy.create(recursive: true);
    await File(
      _join(unrelatedLegacy.path, 'sessions.json'),
    ).writeAsString('{"personal":"must not import"}');
    final selectedRoot = Directory(_join(temporaryDirectory.path, 'selected'));
    final store = GatheringPersonalStore(selectedRoot);

    final loaded = await store.load();

    expect(loaded.profile.mastery, 0);
    expect(loaded.profile.loadoutNotes, isEmpty);
    expect(loaded.sessions, isEmpty);
    expect(await File(store.path).exists(), isFalse);
    expect(await unrelatedLegacy.list().length, 1);
  });

  test('stores profile and sessions below the central selected root', () async {
    final store = GatheringPersonalStore(temporaryDirectory);
    final session = GatheringSession(
      id: 'session-1',
      recordedAtUtc: DateTime.utc(2026, 9, 15, 12, 30),
      method: 'Butchering',
      location: 'Balenos',
      durationMinutes: 45,
      mastery: 1850,
      notes: 'Personal notes',
    );
    final data = GatheringPersonalData(
      profile: const GatheringProfile(
        mastery: 1850,
        loadoutNotes: 'Personal loadout',
      ),
      sessions: [session],
    );

    await store.save(data);
    final loaded = await GatheringPersonalStore(temporaryDirectory).load();

    expect(
      File(store.path).parent.absolute.path,
      Directory(
        _join(temporaryDirectory.path, GatheringPersonalStore.directoryName),
      ).absolute.path,
    );
    expect(loaded.profile.mastery, 1850);
    expect(loaded.profile.loadoutNotes, 'Personal loadout');
    expect(loaded.sessions, hasLength(1));
    expect(loaded.sessions.single.location, 'Balenos');
    expect(loaded.sessions.single.notes, 'Personal notes');
  });

  test('rejects malformed personal data without rewriting it', () async {
    final store = GatheringPersonalStore(temporaryDirectory);
    await store.directory.create(recursive: true);
    final file = File(store.path);
    const malformed = '{"version":1,"profile":{"mastery":9000}}';
    await file.writeAsString(malformed);

    await expectLater(store.load(), throwsFormatException);

    expect(await file.readAsString(), malformed);
  });

  test(
    'serialized state contains no machine path or external import source',
    () {
      final json = jsonEncode(
        GatheringPersonalData(
          profile: const GatheringProfile(
            mastery: 1200,
            loadoutNotes: 'My gathering clothes',
          ),
          sessions: [
            GatheringSession(
              id: 'safe',
              recordedAtUtc: DateTime.utc(2026, 9, 15),
              method: 'Mining',
              location: '',
              durationMinutes: 30,
              mastery: 1200,
              notes: '',
            ),
          ],
        ).toJson(),
      ).toLowerCase();

      expect(json, isNot(contains('appdata')));
      expect(json, isNot(contains('beta')));
      expect(json, isNot(contains('legacy')));
      expect(json, isNot(contains('garmoth')));
    },
  );
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';
