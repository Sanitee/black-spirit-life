import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/services/stable_v017_migration.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

GatheringSession recordedSession({
  String id = 'session-1',
  String notes = 'First visit',
  int total = 1300,
  bool approximate = false,
}) => GatheringSession(
  id: id,
  createdAt: DateTime.utc(2026, 8, 31, 10, 15),
  methodId: 'butcher',
  methodLabel: 'Butchering',
  methodIcon: 'assets/icons/tools/butcher_knife.webp',
  spotId: 'imp-cave-wolves',
  spotName: 'Imp Cave · Wolves',
  durationSeconds: 1800,
  mastery: 1000,
  notes: notes,
  loot: [
    LootEntry(
      id: '7913',
      name: 'Wolf Meat',
      icon: 'assets/icons/items/7913.webp',
      start: 100,
      remaining: 400,
      sentAway: 1000,
      overrideTotal: total == 1300 ? null : total,
      isApproximate: approximate,
    ),
  ],
  buffs: [
    {
      'id': 'buff-791',
      'name': 'Verdure Draught',
      'category': 'draughts',
      'icon': 'assets/icons/buffs/791.webp',
      'grade': 3,
      'effects': {'lifeExpPct': 20.0, 'gatheringSpeed': 3.0},
      'durationMinutes': 20.0,
    },
  ],
  pets: const [
    {
      'id': 'hedgehog',
      'name': 'Hedgehog',
      'icon': 'assets/icons/pets/hedgehog.webp',
      'summary': 'Extra materials · Life EXP',
    },
  ],
  buffTotals: {'lifeExpPct': 20.0, 'gatheringSpeed': 3.0},
  catalogDate: '2026-08-28',
);

Map<String, dynamic> profile(List<Object?> sessions) => {
  'schemaVersion': 1,
  'sessions': sessions,
  'preferences': {'methodId': 'butcher', 'spotId': 'imp-cave-wolves'},
};

void main() {
  group('Inventory ledger', () {
    test(
      'exact overrides retain approximate observation provenance through JSON',
      () {
        final entry = LootEntry(id: '7913', name: 'Wolf Meat');
        entry.setStart(100);
        entry.setSnapshot(1000, approximate: true);
        entry.overrideTotal = 937;
        entry.isApproximate = false;
        expect(entry.isApproximate, isFalse);
        expect(entry.observationsApproximate, isTrue);
        final loaded = LootEntry.fromJson(
          jsonDecode(jsonEncode(entry.toJson())),
        );
        expect(loaded.isApproximate, isFalse);
        expect(loaded.overrideTotal, 937);
        loaded.overrideTotal = null;
        expect(loaded.total, 900);
        expect(loaded.isApproximate, isTrue);
        loaded.overrideTotal = 950;
        loaded.isApproximate = false;
        loaded.setStart(150);
        expect(loaded.isApproximate, isTrue);
        expect(loaded.total, 850);
      },
    );

    test(
      'abbreviated deposits remain approximate beneath an exact override',
      () {
        final entry = LootEntry(
          id: '7913',
          name: 'Wolf Meat',
          overrideTotal: 2500,
        );
        entry.recordMaidDeposit(1000, approximate: true);
        expect(entry.isApproximate, isFalse);
        final loaded = LootEntry.fromJson(entry.toJson());
        expect(loaded.observationsApproximate, isTrue);
        expect(loaded.isApproximate, isFalse);
        loaded.setSnapshot(400);
        expect(loaded.total, 1400);
        expect(loaded.isApproximate, isTrue);
      },
    );

    test(
      'older rows load safely without claiming lost override provenance is exact',
      () {
        final legacy = LootEntry(
          id: '7913',
          name: 'Wolf Meat',
          remaining: 1000,
          overrideTotal: 1050,
          hasInventorySnapshot: true,
        ).toJson()..remove('observationsApproximate');
        final loaded = LootEntry.fromJson(legacy);
        expect(
          loaded.isApproximate,
          isFalse,
          reason: 'The explicitly entered whole total remains authoritative.',
        );
        loaded.overrideTotal = null;
        expect(
          loaded.isApproximate,
          isTrue,
          reason:
              'The old format lost the accuracy of observations under this override.',
        );
        legacy['overrideTotal'] = null;
        expect(LootEntry.fromJson(legacy).isApproximate, isFalse);
        legacy['isApproximate'] = true;
        expect(LootEntry.fromJson(legacy).observationsApproximate, isTrue);
        final pureManual = LootEntry(
          id: 'manual',
          name: 'Manual item',
          overrideTotal: 80,
        ).toJson()..remove('observationsApproximate');
        expect(LootEntry.fromJson(pureManual).observationsApproximate, isFalse);
      },
    );

    test(
      'new exact observations remain exact when an override is cleared after loading',
      () {
        final entry = LootEntry(id: '7913', name: 'Wolf Meat');
        entry.setSnapshot(1000);
        entry.overrideTotal = 1050;
        entry.isApproximate = false;
        final loaded = LootEntry.fromJson(entry.toJson())..overrideTotal = null;
        expect(loaded.observationsApproximate, isFalse);
        expect(loaded.isApproximate, isFalse);
      },
    );

    test('starting stock, current snapshot, and maid batches count once', () {
      final meat = LootEntry(id: '7913', name: 'Wolf Meat');
      meat.setStart(100);
      expect(meat.total, 0);
      meat.addBatch(600);
      meat.addBatch(400);
      meat.setSnapshot(400);
      expect(meat.rawTotal, 1300);
      expect(meat.sentAway, 1000);
      meat.setSnapshot(400);
      expect(
        meat.rawTotal,
        1300,
        reason: 'Repeating an inventory picture must not add another batch.',
      );
      meat.setSnapshot(450);
      expect(meat.rawTotal, 1350);
    });

    test(
      'final total overrides the observations and later batches add to it',
      () {
        final meat = recordedSession().loot.single;
        meat.overrideTotal = 2300;
        expect(meat.total, 2300);
        meat.addBatch(200);
        expect(meat.total, 2500);
        expect(
          meat.sentAway,
          1000,
          reason: 'Do not also add a post-override batch to the old ledger.',
        );
        meat.setSnapshot(600);
        expect(meat.overrideTotal, isNull);
        expect(
          meat.total,
          1500,
          reason: 'Switching back to inventory mode uses its own observations.',
        );
      },
    );

    test('a later starting-stock correction preserves the final inventory', () {
      final meat = LootEntry(id: '7913', name: 'Wolf Meat');
      meat.setSnapshot(400);
      meat.addBatch(1000);
      meat.setStart(100);
      expect(meat.remaining, 400);
      expect(meat.rawTotal, 1300);
      meat.setStart(150);
      expect(meat.rawTotal, 1250);
      final restored = LootEntry.fromJson(meat.toJson());
      restored.setStart(200);
      expect(
        restored.remaining,
        400,
        reason: 'The observed-snapshot state must survive persistence.',
      );
      expect(restored.rawTotal, 1200);
    });

    test(
      'negative ledger values remain detectable before UI clamps display',
      () {
        final meat = LootEntry(id: '7913', name: 'Wolf Meat', start: 500);
        meat.setSnapshot(100);
        expect(meat.rawTotal, -400);
        expect(meat.total, 0);
        meat.addBatch(600);
        expect(meat.rawTotal, 200);
      },
    );

    test(
      'roundtrip preserves approximate observations and explicit overrides',
      () {
        final original = recordedSession(
          total: 1200,
          approximate: true,
        ).loot.single;
        final restored = LootEntry.fromJson(original.toJson());
        expect(restored.start, 100);
        expect(restored.remaining, 400);
        expect(restored.sentAway, 1000);
        expect(restored.overrideTotal, 1200);
        expect(restored.total, 1200);
        expect(restored.isApproximate, isTrue);
        restored.overrideTotal = 1237;
        restored.isApproximate = false;
        final exact = LootEntry.fromJson(restored.toJson());
        expect(exact.total, 1237);
        expect(exact.isApproximate, isFalse);
      },
    );
  });

  group('Standalone persistence', () {
    late Directory directory;
    late SessionStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'bdo-gathering-store-test-',
      );
      store = SessionStore(directory: directory);
    });

    tearDown(() async {
      if (!await directory.exists()) return;
      final target = await directory.resolveSymbolicLinks();
      final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
      if (!target.toLowerCase().startsWith(
            '${temporaryRoot.toLowerCase()}${Platform.pathSeparator}',
          ) ||
          !directory.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('bdo-gathering-store-test-')) {
        throw StateError('Refusing to clean an unexpected test directory.');
      }
      await directory.delete(recursive: true);
    });

    test(
      'missing profile loads empty without creating storage files',
      () async {
        await store.load();
        expect(store.sessions, isEmpty);
        expect(await directory.list().toList(), isEmpty);
      },
    );

    test(
      'saving an exact override preserves observation accuracy for later history edits',
      () async {
        final session = recordedSession(approximate: true);
        session.loot.single.overrideTotal = 1337;
        session.loot.single.isApproximate = false;
        await store.upsert(session);
        final loaded = SessionStore(directory: directory);
        await loaded.load();
        final entry = loaded.sessions.single.loot.single;
        expect(entry.isApproximate, isFalse);
        expect(entry.observationsApproximate, isTrue);
        entry.overrideTotal = null;
        expect(entry.isApproximate, isTrue);
        await loaded.save();
        final reloaded = SessionStore(directory: directory);
        await reloaded.load();
        expect(reloaded.sessions.single.loot.single.isApproximate, isTrue);
        expect(reloaded.sessions.single.loot.single.total, 1300);
      },
    );

    test(
      'save and reload retain ledger, approximation, date, and preferences',
      () async {
        store.preferences = {
          'methodId': 'butcher',
          'spotId': 'imp-cave-wolves',
          'glassOpacityPercent': 37,
          'gatheringEstimateSetup': {
            'mastery': 1850,
            'gatheringDropRatePercent': 72,
            'includeAfuaru': true,
          },
        };
        await store.upsert(recordedSession(approximate: true));
        final restored = SessionStore(directory: directory);
        await restored.load();
        expect(restored.sessions, hasLength(1));
        final session = restored.sessions.single;
        expect(session.createdAt, DateTime.utc(2026, 8, 31, 10, 15));
        expect(session.durationSeconds, 1800);
        expect(session.totalItems, 1300);
        expect(session.loot.single.isApproximate, isTrue);
        expect(session.loot.single.start, 100);
        expect(session.loot.single.sentAway, 1000);
        expect(session.buffs.single['grade'], 3);
        expect(session.pets.single['id'], 'hedgehog');
        expect(restored.preferences['methodId'], 'butcher');
        expect(restored.preferences['glassOpacityPercent'], 37);
        expect(restored.preferences['gatheringEstimateSetup'], {
          'mastery': 1850,
          'gatheringDropRatePercent': 72,
          'includeAfuaru': true,
        });
        expect(await File('${store.file.path}.tmp').exists(), isFalse);
      },
    );

    test('older sessions without pets remain valid', () {
      final legacy = recordedSession().toJson()..remove('pets');
      expect(GatheringSession.fromJson(legacy).pets, isEmpty);
    });

    test(
      'preparation preference and frozen session snapshot survive save and reload',
      () async {
        final preparation = GatheringPreparation(
          baseSettings: const BairogCalculatorSettings(
            mastery: 1350,
            gatheringDropRatePercent: 27,
          ),
          buffIds: {'buff-890'},
          petIds: {'hedgehog'},
          statsConfirmed: true,
        );
        final frozen = {
          'profile': preparation.toJson(),
          'effectiveSettings': {'mastery': 1400},
          'statsConfirmed': true,
          'methodId': 'butcher',
        };
        store.preferences = {
          gatheringPreparationPreferenceKey: preparation.toJson(),
          'glassOpacityPercent': 60,
        };
        await store.upsert(
          GatheringSession.fromJson({
            ...recordedSession().toJson(),
            'preparationSnapshot': frozen,
          }),
        );
        final saved = await store.file.readAsString();
        final restored = SessionStore(directory: directory);
        await restored.load();
        expect(
          await store.file.readAsString(),
          saved,
          reason: 'Reading preferences and history never rewrites them.',
        );
        expect(
          GatheringPreparation.fromPreferences(
            restored.preferences,
          ).hasSameValuesAs(preparation),
          isTrue,
        );
        expect(restored.sessions.single.preparationSnapshot, frozen);
        restored.preferences[gatheringPreparationPreferenceKey] = preparation
            .copyWith(
              baseSettings: const BairogCalculatorSettings(mastery: 200),
            )
            .toJson();
        await restored.save();
        final again = SessionStore(directory: directory);
        await again.load();
        expect(
          GatheringPreparation.fromPreferences(
            again.preferences,
          ).baseSettings.mastery,
          200,
        );
        expect(
          again.sessions.single.preparationSnapshot,
          frozen,
          reason:
              'Later global preparation edits cannot revise recorded setup or totals.',
        );
      },
    );

    test(
      'stable migration marker and loadout notes survive saves and backup recovery',
      () async {
        const sourceSha256 =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        final marker = <String, dynamic>{
          'schemaVersion': 1,
          'migrationVersion': stableV017GatheringMigrationVersion,
          'sourceSha256': sourceSha256,
          'archiveRelativePath':
              'migration-archive/v0.1.7/gathering-state.$sourceSha256.json',
          'sessionCount': 1,
          'migratedAtUtc': '2026-09-15T18:30:00.000Z',
        };
        store.preferences = <String, dynamic>{
          stableV017GatheringMigrationPreferenceKey: marker,
          stableV017GatheringLoadoutNotesPreferenceKey:
              'Synthetic Manos gathering loadout',
        };
        await store.upsert(recordedSession());

        final restored = SessionStore(directory: directory);
        await restored.load();
        expect(
          restored.preferences[stableV017GatheringMigrationPreferenceKey],
          marker,
        );
        expect(
          restored.preferences[stableV017GatheringLoadoutNotesPreferenceKey],
          'Synthetic Manos gathering loadout',
        );
        restored.preferences['glassOpacityPercent'] = 42;
        await restored.save();

        final again = SessionStore(directory: directory);
        await again.load();
        expect(
          again.preferences[stableV017GatheringMigrationPreferenceKey],
          marker,
        );
        expect(
          again.preferences[stableV017GatheringLoadoutNotesPreferenceKey],
          'Synthetic Manos gathering loadout',
        );

        await again.file.writeAsString('damaged primary', flush: true);
        final recovered = SessionStore(directory: directory);
        await recovered.load();
        expect(recovered.recoveredBackup, isTrue);
        expect(
          recovered.preferences[stableV017GatheringMigrationPreferenceKey],
          marker,
        );
        expect(
          recovered.preferences[stableV017GatheringLoadoutNotesPreferenceKey],
          'Synthetic Manos gathering loadout',
        );
      },
    );

    test(
      'editing an existing ID replaces it without duplicating history',
      () async {
        await store.upsert(recordedSession());
        await store.upsert(recordedSession(id: 'session-2', total: 900));
        await store.upsert(
          recordedSession(notes: 'Corrected amount', total: 1400),
        );
        expect(store.sessions, hasLength(2));
        expect(store.sessions.first.id, 'session-1');
        expect(store.sessions.first.totalItems, 1400);
        expect(store.sessions.first.notes, 'Corrected amount');
        final restored = SessionStore(directory: directory);
        await restored.load();
        expect(restored.sessions.map((s) => s.id).toSet(), {
          'session-1',
          'session-2',
        });
        expect(restored.sessions.first.totalItems, 1400);
        await restored.remove('session-2');
        final afterDelete = SessionStore(directory: directory);
        await afterDelete.load();
        expect(afterDelete.sessions.single.id, 'session-1');
      },
    );

    test(
      'historical buff values survive a catalog change and unrelated edit',
      () async {
        await store.upsert(recordedSession());
        final currentCatalogBuff = Buff({
          'id': 'buff-791',
          'name': 'A future renamed draught',
          'effects': {'lifeExpPct': 35},
          'durationMinutes': 30,
        });
        expect(currentCatalogBuff.effects['lifeExpPct'], 35);
        final restored = SessionStore(directory: directory);
        await restored.load();
        final saved = restored.sessions.single.toJson();
        saved['notes'] = 'Only the note was edited';
        await restored.upsert(GatheringSession.fromJson(saved));
        final reloaded = SessionStore(directory: directory);
        await reloaded.load();
        final history = reloaded.sessions.single;
        expect(history.catalogDate, '2026-08-28');
        expect(history.buffTotals['lifeExpPct'], 20);
        expect(history.buffs.single['name'], 'Verdure Draught');
        expect(objectMap(history.buffs.single['effects'])['lifeExpPct'], 20);
        expect(history.buffs.single['durationMinutes'], 20);
      },
    );

    test(
      'persistence strips non-schema screenshot fields and source paths',
      () async {
        final raw = recordedSession().toJson();
        raw['screenshotPath'] = r'C:\screenshots\private-inventory.png';
        raw['imageBytes'] = [1, 2, 3, 4];
        final loot = (raw['loot'] as List).single as Map<String, dynamic>;
        loot['cropPath'] = r'C:\temporary\loot-crop.png';
        loot['dataBase64'] = 'PRIVATE_IMAGE_SENTINEL';
        final buff = (raw['buffs'] as List).single as Map<String, dynamic>;
        buff['screenshotPath'] = r'C:\screenshots\buffs.png';
        buff['imageBytes'] = [1, 2, 3];
        final pet = (raw['pets'] as List).single as Map<String, dynamic>;
        pet['screenshotPath'] = r'C:\screenshots\pet.png';
        await store.upsert(GatheringSession.fromJson(raw));
        await store.upsert(recordedSession(id: 'session-2'));
        final files = await directory.list().where((f) => f is File).toList();
        expect(
          files.map((f) => f.path.split(Platform.pathSeparator).last).toSet(),
          {'sessions.json', 'sessions.json.bak'},
        );
        for (final file in files.cast<File>()) {
          final text = await file.readAsString();
          for (final forbidden in [
            'screenshotPath',
            'imageBytes',
            'cropPath',
            'dataBase64',
            'private-inventory',
            'PRIVATE_IMAGE_SENTINEL',
          ]) {
            expect(text, isNot(contains(forbidden)), reason: file.path);
          }
          expect(
            text,
            contains('assets/icons/'),
            reason: 'Bundled item artwork references are safe to preserve.',
          );
        }
      },
    );

    test(
      'one rolling backup keeps the previous valid save, without archives',
      () async {
        await store.upsert(recordedSession(total: 1000));
        await store.upsert(recordedSession(total: 1100));
        await store.upsert(recordedSession(total: 1200));
        final backup = objectMap(
          jsonDecode(await File('${store.file.path}.bak').readAsString()),
        );
        final previous = GatheringSession.fromJson(
          objectList(backup['sessions']).single,
        );
        expect(previous.totalItems, 1100);
        expect(store.sessions.single.totalItems, 1200);
        expect(await directory.list().length, 2);
      },
    );

    test(
      'corrupt primary recovers backup without writing during load',
      () async {
        await store.upsert(recordedSession(total: 1000));
        await store.upsert(recordedSession(total: 1100));
        final backupFile = File('${store.file.path}.bak');
        final validBackup = await backupFile.readAsString();
        const damaged = '{"schemaVersion":1,"sessions":[';
        await store.file.writeAsString(damaged);
        final recovered = SessionStore(directory: directory);
        await recovered.load();
        expect(recovered.recoveredBackup, isTrue);
        expect(recovered.sessions.single.totalItems, 1000);
        expect(await store.file.readAsString(), damaged);
        expect(await backupFile.readAsString(), validBackup);
        await recovered.upsert(recordedSession(total: 1250));
        expect(recovered.recoveredBackup, isFalse);
        expect(
          await backupFile.readAsString(),
          validBackup,
          reason: 'Do not replace the valid backup with the corrupt primary.',
        );
        final fresh = SessionStore(directory: directory);
        await fresh.load();
        expect(fresh.sessions.single.totalItems, 1250);
      },
    );

    test(
      'partially malformed session lists trigger recovery, not silent loss',
      () async {
        final backupFile = File('${store.file.path}.bak');
        await backupFile.writeAsString(
          jsonEncode(
            profile([
              recordedSession(total: 1000).toJson(),
              recordedSession(id: 'session-2', total: 900).toJson(),
            ]),
          ),
        );
        final damaged = jsonEncode(profile([recordedSession().toJson(), null]));
        await store.file.writeAsString(damaged);
        await store.load();
        expect(store.recoveredBackup, isTrue);
        expect(
          store.sessions,
          hasLength(2),
          reason: 'A malformed row must not silently remove a saved session.',
        );
        expect(await store.file.readAsString(), damaged);
      },
    );

    test(
      'invalid nested loot is rejected if no recovery backup exists',
      () async {
        final bad = recordedSession().toJson();
        bad['loot'] = <Object?>[...(bad['loot'] as List), 'not a loot record'];
        final contents = jsonEncode(profile([bad]));
        await store.file.writeAsString(contents);
        await expectLater(store.load(), throwsA(isA<FormatException>()));
        expect(store.sessions, isEmpty);
        expect(await store.file.readAsString(), contents);
      },
    );

    test('unsupported or unrecoverable data remains untouched', () async {
      final incompatible = jsonEncode({'schemaVersion': 999, 'sessions': []});
      await store.file.writeAsString(incompatible);
      await expectLater(store.load(), throwsA(isA<FormatException>()));
      expect(await store.file.readAsString(), incompatible);
      await store.file.writeAsString('not json');
      await File('${store.file.path}.bak').writeAsString('also not json');
      await expectLater(store.load(), throwsA(isA<FormatException>()));
      expect(store.sessions, isEmpty);
      expect(await store.file.readAsString(), 'not json');
    });

    test('failed writes roll back edits and deletions in memory', () async {
      await store.upsert(recordedSession(total: 1000));
      final previousFile = await store.file.readAsString();
      // A directory occupying the temporary-file name causes a real write
      // failure without touching permissions or the user's real profile.
      await Directory('${store.file.path}.tmp').create();
      await expectLater(
        store.upsert(recordedSession(total: 1500)),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.sessions.single.totalItems, 1000);
      expect(await store.file.readAsString(), previousFile);
      await expectLater(
        store.remove('session-1'),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.sessions.single.id, 'session-1');
      expect(await store.file.readAsString(), previousFile);
    });
  });
}
