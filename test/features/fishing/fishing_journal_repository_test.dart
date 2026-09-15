import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/features/fishing/fishing_journal_repository.dart';
import 'package:bdo_craft_planner_flutter/features/fishing/fishing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'black-spirit-life-fishing-repository-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'fresh selected root stays empty and does not import elsewhere',
    () async {
      final unrelated = Directory(_join(temporaryDirectory.path, 'old-app'));
      await unrelated.create(recursive: true);
      await File(
        _join(unrelated.path, 'fishing-journal.json'),
      ).writeAsString('{"personal":"do not import"}');
      final selectedRoot = Directory(
        _join(temporaryDirectory.path, 'selected'),
      );
      final repository = FishingJournalRepository(selectedRoot);

      final journal = await repository.load();

      expect(journal.loadouts, isEmpty);
      expect(journal.sessions, isEmpty);
      expect(await repository.directory.exists(), isFalse);
      expect(await File(repository.path).exists(), isFalse);
      expect(await unrelated.list().length, 1);
    },
  );

  test(
    'round-trips loadouts and immutable session snapshots below root',
    () async {
      final repository = FishingJournalRepository(temporaryDirectory);
      final created = DateTime.utc(2026, 9, 15, 11);
      final loadout = FishingLoadout(
        id: 'loadout-1',
        name: 'Harpoon setup',
        method: FishingMethod.harpooning,
        mastery: 1675,
        tool: 'Steel harpoon',
        notes: 'My local notes',
        createdAtUtc: created,
        updatedAtUtc: created,
      );
      final session = FishingSession(
        id: 'session-1',
        startedAtUtc: DateTime.utc(2026, 9, 15, 12),
        durationMinutes: 75,
        location: 'Margoria',
        method: FishingMethod.harpooning,
        loadoutId: loadout.id,
        loadoutName: loadout.name,
        mastery: loadout.mastery,
        tool: loadout.tool,
        retainedFishCount: 18,
        silverReceived: 125000000,
        notes: 'Kept prize catches',
        createdAtUtc: created,
        updatedAtUtc: created,
      );

      await repository.save(
        FishingJournal(
          loadouts: <FishingLoadout>[loadout],
          sessions: <FishingSession>[session],
        ),
      );
      await repository.flush();
      final loaded = await FishingJournalRepository(temporaryDirectory).load();

      expect(
        repository.directory.parent.absolute.path,
        temporaryDirectory.absolute.path,
      );
      expect(
        repository.directory.uri.pathSegments
            .where((part) => part.isNotEmpty)
            .last,
        'fishing',
      );
      expect(loaded.loadouts.single.name, 'Harpoon setup');
      expect(loaded.sessions.single.loadoutName, 'Harpoon setup');
      expect(loaded.sessions.single.mastery, 1675);
      expect(loaded.sessions.single.tool, 'Steel harpoon');
      expect(loaded.sessions.single.silverReceived, 125000000);
    },
  );

  test(
    'serialized writes are ordered and flush observes the newest one',
    () async {
      final repository = FishingJournalRepository(temporaryDirectory);
      final timestamp = DateTime.utc(2026, 9, 15);
      FishingJournal journal(String id, String name) => FishingJournal(
        loadouts: <FishingLoadout>[
          FishingLoadout(
            id: id,
            name: name,
            method: FishingMethod.fishing,
            mastery: 1000,
            tool: '',
            notes: '',
            createdAtUtc: timestamp,
            updatedAtUtc: timestamp,
          ),
        ],
      );

      final first = repository.save(journal('first', 'First'));
      final second = repository.save(journal('second', 'Second'));
      await repository.flush();
      await Future.wait<void>(<Future<void>>[first, second]);

      expect((await repository.load()).loadouts.single.name, 'Second');
      expect(
        await repository.directory
            .list()
            .where((entity) => entity.path.contains('.backup-'))
            .length,
        1,
      );
    },
  );

  test('malformed existing data is rejected and never overwritten', () async {
    final repository = FishingJournalRepository(temporaryDirectory);
    await repository.directory.create(recursive: true);
    final target = File(repository.path);
    const malformed = '{"version":1,"loadouts":"private","sessions":[]}';
    await target.writeAsString(malformed);

    await expectLater(repository.load(), throwsFormatException);
    await expectLater(repository.save(FishingJournal()), throwsFormatException);

    expect(await target.readAsString(), malformed);
  });

  test(
    'deleting a loadout does not rewrite historical session details',
    () async {
      final repository = FishingJournalRepository(temporaryDirectory);
      final timestamp = DateTime.utc(2026, 9, 15);
      final loadout = FishingLoadout(
        id: 'loadout-to-delete',
        name: 'Fishing snapshot',
        method: FishingMethod.fishing,
        mastery: 2200,
        tool: 'Triple-Float Fishing Rod',
        notes: '',
        createdAtUtc: timestamp,
        updatedAtUtc: timestamp,
      );
      final historical = FishingSession(
        id: 'historical-session',
        startedAtUtc: timestamp,
        durationMinutes: 90,
        location: '',
        method: FishingMethod.fishing,
        loadoutId: loadout.id,
        loadoutName: loadout.name,
        mastery: loadout.mastery,
        tool: loadout.tool,
        retainedFishCount: 0,
        silverReceived: 0,
        notes: '',
        createdAtUtc: timestamp,
        updatedAtUtc: timestamp,
      );
      await repository.save(
        FishingJournal(
          loadouts: <FishingLoadout>[loadout],
          sessions: <FishingSession>[historical],
        ),
      );

      final beforeDelete = await repository.load();
      await repository.save(
        beforeDelete.copyWith(loadouts: const <FishingLoadout>[]),
      );
      final afterDelete = await repository.load();

      expect(afterDelete.loadouts, isEmpty);
      expect(afterDelete.sessions.single.loadoutId, 'loadout-to-delete');
      expect(afterDelete.sessions.single.loadoutName, 'Fishing snapshot');
      expect(afterDelete.sessions.single.mastery, 2200);
      expect(afterDelete.sessions.single.tool, 'Triple-Float Fishing Rod');
    },
  );

  test('JSON contains only the journal schema and entered values', () {
    final encoded = jsonEncode(FishingJournal().toJson()).toLowerCase();

    expect(encoded, '{"version":1,"loadouts":[],"sessions":[]}');
    expect(encoded, isNot(contains('appdata')));
    expect(encoded, isNot(contains('beta')));
    expect(encoded, isNot(contains('legacy')));
    expect(encoded, isNot(contains('fishystuff')));
  });
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';
