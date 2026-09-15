import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/services/stable_v017_migration.dart';
import 'package:bdo_gathering_companion/src/ui/stable_v017_loadout_notes_card.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _session({
  String id = 'synthetic-gathering-session-1',
  String recordedAtUtc = '2026-09-14T10:30:00.000Z',
  String method = 'Butchering',
  String location = 'Behr',
  Object durationMinutes = 60,
  Object mastery = 2111,
  String notes = 'Synthetic lifecycle preservation record',
}) => <String, dynamic>{
  'id': id,
  'recordedAtUtc': recordedAtUtc,
  'method': method,
  'location': location,
  'durationMinutes': durationMinutes,
  'mastery': mastery,
  'notes': notes,
};

Map<String, dynamic> _profile({
  Object mastery = 2111,
  String loadoutNotes = 'Synthetic Manos gathering loadout',
  List<Object?>? sessions,
}) => <String, dynamic>{
  'version': 1,
  'profile': <String, dynamic>{
    'mastery': mastery,
    'loadoutNotes': loadoutNotes,
  },
  'sessions': sessions ?? <Object?>[_session()],
};

Future<Directory> _temporaryGatheringDirectory(String label) async {
  final root = await Directory.systemTemp.createTemp(
    'bdo-gathering-stable-v017-$label-',
  );
  addTearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  return Directory('${root.path}${Platform.pathSeparator}gathering');
}

File _sourceFile(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}gathering-state.json');

File _destinationFile(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}sessions.json');

Future<List<int>> _writeSource(
  Directory directory,
  Map<String, dynamic> contents,
) async {
  await directory.create(recursive: true);
  final bytes = utf8.encode(jsonEncode(contents));
  await _sourceFile(directory).writeAsBytes(bytes, flush: true);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'migrates the exact lifecycle fixture, profile, archive, and marker once',
    () async {
      final directory = await _temporaryGatheringDirectory('fixture');
      final sourceBytes = await _writeSource(directory, _profile());
      final migratedAt = DateTime.utc(2026, 9, 15, 18, 30);

      expect(
        await migrateStableV017GatheringData(
          directory: directory,
          nowUtc: () => migratedAt,
        ),
        isTrue,
      );
      expect(await _sourceFile(directory).readAsBytes(), sourceBytes);

      final store = SessionStore(directory: directory);
      await store.load();
      expect(store.sessions, hasLength(1));
      final session = store.sessions.single;
      expect(session.id, 'synthetic-gathering-session-1');
      expect(session.createdAt, DateTime.utc(2026, 9, 14, 10, 30));
      expect(session.methodId, 'butcher');
      expect(session.methodLabel, 'Butchering');
      expect(session.spotId, 'custom');
      expect(session.spotName, 'Behr');
      expect(session.stableV017Location, 'Behr');
      expect(session.durationSeconds, 3600);
      expect(session.mastery, 2111);
      expect(session.notes, 'Synthetic lifecycle preservation record');
      expect(session.loot, isEmpty);
      expect(session.buffs, isEmpty);
      expect(session.pets, isEmpty);
      expect(session.buffTotals, isEmpty);
      expect(session.preparationSnapshot, isNull);
      expect(session.sessionImport, isNull);

      final preparation = GatheringPreparation.fromPreferences(
        store.preferences,
      );
      expect(preparation.statsConfirmed, isTrue);
      expect(preparation.buffIds, isEmpty);
      expect(preparation.petIds, isEmpty);
      final expectedSettings = <String, dynamic>{
        'schemaVersion': 2,
        'mastery': 2111,
        'additionalDroprateBonus': 0.0,
        'minigameMode': 'none',
        'hedgehogTier': 0,
        'agrisEnabled': false,
        'expensesEnabled': <String, bool>{
          '589': false,
          '820150': false,
          '821144': false,
          '821145': false,
        },
        'displayMode': 'silver_hr',
        'yourEnergy': 0.0,
        'energyRecovery': 0.0,
        'includeAfuaru': false,
        'includeChest': false,
        'includeChestX10': false,
        'includeFeverTime': false,
        'includeEvergreenShard': false,
        'showTaxed': false,
        'marketNetRate': 1.0,
        'dropTaxed': <String, bool>{},
        'hiddenDropIds': <String, bool>{},
        'customGathersPerHour': <String, String>{},
        'customItemPrices': <String, dynamic>{},
      };
      expect(preparation.baseSettings.toJson(), expectedSettings);
      final catalog = await Catalog.load();
      final effectiveSettings = preparation.effectiveSettings(catalog);
      expect(effectiveSettings.toJson(), expectedSettings);
      final projection = BairogCalculator(catalog.bairogCalculatorData!)
          .projectRoute(
            routeId: catalog.bairogCalculatorData!.rotations.first.id,
            settings: effectiveSettings,
          );
      expect(projection.hedgehogSilverPerHour, 0);
      expect(projection.afuaruSilverPerHour, 0);
      expect(projection.chestSilverPerHour, 0);
      expect(projection.chestX10SilverPerHour, 0);
      expect(projection.feverTimeSilverPerHour, 0);
      expect(projection.agrisSilverBonusPerHour, 0);
      expect(projection.agrisPointsPerHour, 0);
      expect(projection.energy.selectedRecoveryPerHour, 0);
      expect(projection.energy.naturalRecoveryPerHour, 0);
      expect(projection.energy.startingEnergy, 0);
      expect(projection.energy.energyBoost, 0);
      expect(projection.energy.hourlyExpenseSilver, 0);
      expect(projection.energyDumpSilver, 0);
      expect(
        store.preferences[stableV017GatheringLoadoutNotesPreferenceKey],
        'Synthetic Manos gathering loadout',
      );

      final sourceSha256 = sha256.convert(sourceBytes).toString();
      final marker = readStableV017GatheringMigrationMarker(
        store.preferences[stableV017GatheringMigrationPreferenceKey],
      );
      expect(marker['sourceSha256'], sourceSha256);
      expect(marker['sessionCount'], 1);
      expect(marker['migratedAtUtc'], migratedAt.toIso8601String());
      final archive = File(
        '${directory.parent.path}${Platform.pathSeparator}migration-archive'
        '${Platform.pathSeparator}v0.1.7${Platform.pathSeparator}'
        'gathering-state.$sourceSha256.json',
      );
      expect(await archive.readAsBytes(), sourceBytes);

      final destinationBefore = await _destinationFile(directory).readAsBytes();
      expect(
        await migrateStableV017GatheringData(directory: directory),
        isFalse,
      );
      expect(
        await _destinationFile(directory).readAsBytes(),
        destinationBefore,
      );
      expect(await archive.readAsBytes(), sourceBytes);
    },
  );

  test('maps every stable method without inventing catalog locations', () async {
    final directory = await _temporaryGatheringDirectory('methods');
    const methods = <String>[
      'Butchering',
      'Fluid collecting',
      'Harvesting',
      'Hoe gathering',
      'Lumbering',
      'Mining',
      'Tanning',
      'Hunting',
      'Other',
    ];
    await _writeSource(
      directory,
      _profile(
        sessions: <Object?>[
          for (var index = 0; index < methods.length; index++)
            _session(
              id: 'session-$index',
              method: methods[index],
              location: index == 2
                  ? 'Behr'
                  : (index == 8 ? '' : 'Place $index'),
            ),
        ],
      ),
    );

    await migrateStableV017GatheringData(directory: directory);
    final store = SessionStore(directory: directory);
    await store.load();
    expect(store.sessions.map((entry) => entry.methodLabel), methods);
    expect(store.sessions[0].methodId, 'butcher');
    expect(store.sessions[1].methodId, 'fluid');
    expect(
      store.sessions[2].methodId,
      'legacy-v017-${sha256.convert(utf8.encode('Harvesting')).toString().substring(0, 16)}',
    );
    expect(store.sessions[3].methodId, 'hoe');
    expect(store.sessions[4].methodId, 'lumbering');
    expect(store.sessions[5].methodId, 'mining');
    expect(store.sessions[6].methodId, 'tanning');
    expect(store.sessions[7].methodId, 'hunting');
    expect(store.sessions[8].methodId, startsWith('legacy-v017-'));
    expect(store.sessions[2].spotId, 'custom');
    expect(store.sessions[2].spotName, 'Behr');
    expect(store.sessions[8].spotId, 'custom');
    expect(store.sessions[8].spotName, 'Unspecified location');
    expect(store.sessions[8].stableV017Location, isEmpty);
    expect(store.sessions[2].methodId, isNot(store.sessions[8].methodId));

    await store.save();
    final roundTripped = SessionStore(directory: directory);
    await roundTripped.load();
    expect(roundTripped.sessions.map((entry) => entry.methodLabel), methods);
    expect(roundTripped.sessions[2].stableV017Location, 'Behr');
    expect(roundTripped.sessions[8].stableV017Location, isEmpty);
  });

  test('accepts every stable boundary without changing values', () async {
    final directory = await _temporaryGatheringDirectory('boundaries');
    final longId = 'i' * 160;
    final longMethod = 'm' * 80;
    final longLocation = 'l' * 160;
    final longNotes = 'n' * 12000;
    final longLoadout = 'o' * 4000;
    await _writeSource(
      directory,
      _profile(
        mastery: 0,
        loadoutNotes: longLoadout,
        sessions: <Object?>[
          _session(
            id: longId,
            method: longMethod,
            location: longLocation,
            durationMinutes: 10080,
            mastery: 3000,
            notes: longNotes,
          ),
          _session(
            id: 'minimum',
            durationMinutes: 1,
            mastery: 0,
            notes: '',
            location: '',
          ),
        ],
      ),
    );

    await migrateStableV017GatheringData(directory: directory);
    final store = SessionStore(directory: directory);
    await store.load();
    expect(store.sessions.first.id, longId);
    expect(store.sessions.first.methodLabel, longMethod);
    expect(store.sessions.first.spotName, longLocation);
    expect(store.sessions.first.stableV017Location, longLocation);
    expect(store.sessions.first.durationSeconds, 604800);
    expect(store.sessions.first.mastery, 3000);
    expect(store.sessions.first.notes, longNotes);
    expect(store.sessions.last.durationSeconds, 60);
    expect(store.sessions.last.mastery, 0);
    expect(store.sessions.last.stableV017Location, isEmpty);
    expect(
      GatheringPreparation.fromPreferences(
        store.preferences,
      ).baseSettings.mastery,
      0,
    );
    expect(
      store.preferences[stableV017GatheringLoadoutNotesPreferenceKey],
      longLoadout,
    );
  });

  test(
    'rejects damaged stable data before creating archive or destination',
    () async {
      final base = _profile();
      final invalidDocuments = <Map<String, dynamic>>[
        <String, dynamic>{...base, 'version': 2},
        _profile(mastery: 1.5),
        _profile(mastery: -1),
        _profile(mastery: 3001),
        _profile(loadoutNotes: 'x' * 4001),
        <String, dynamic>{...base, 'sessions': 'not a list'},
        <String, dynamic>{
          ...base,
          'sessions': List<Object?>.filled(10001, null),
        },
        _profile(sessions: <Object?>[_session(), _session()]),
        _profile(sessions: <Object?>[_session(id: '')]),
        _profile(sessions: <Object?>[_session(id: 'x' * 161)]),
        _profile(
          sessions: <Object?>[_session(recordedAtUtc: '2026-09-14T10:30:00')],
        ),
        _profile(sessions: <Object?>[_session(method: '')]),
        _profile(sessions: <Object?>[_session(method: 'x' * 81)]),
        _profile(sessions: <Object?>[_session(location: 'x' * 161)]),
        _profile(sessions: <Object?>[_session(durationMinutes: 0)]),
        _profile(sessions: <Object?>[_session(durationMinutes: 10081)]),
        _profile(sessions: <Object?>[_session(durationMinutes: 1.5)]),
        _profile(sessions: <Object?>[_session(mastery: -1)]),
        _profile(sessions: <Object?>[_session(mastery: 3001)]),
        _profile(sessions: <Object?>[_session(notes: 'x' * 12001)]),
      ];

      for (var index = 0; index < invalidDocuments.length; index++) {
        final directory = await _temporaryGatheringDirectory('invalid-$index');
        final sourceBytes = await _writeSource(
          directory,
          invalidDocuments[index],
        );
        await expectLater(
          migrateStableV017GatheringData(directory: directory),
          throwsA(isA<FormatException>()),
        );
        expect(await _sourceFile(directory).readAsBytes(), sourceBytes);
        expect(await _destinationFile(directory).exists(), isFalse);
        expect(
          await Directory(
            '${directory.parent.path}${Platform.pathSeparator}migration-archive',
          ).exists(),
          isFalse,
        );
      }
    },
  );

  test(
    'never parses, merges, or overwrites an existing current store',
    () async {
      final directory = await _temporaryGatheringDirectory('existing');
      final sourceBytes = await _writeSource(directory, _profile());
      final destination = _destinationFile(directory);
      const currentBytes = <int>[0, 1, 2, 3, 255];
      await destination.writeAsBytes(currentBytes, flush: true);

      expect(
        await migrateStableV017GatheringData(directory: directory),
        isFalse,
      );
      expect(await destination.readAsBytes(), currentBytes);
      expect(await _sourceFile(directory).readAsBytes(), sourceBytes);
      expect(
        await Directory(
          '${directory.parent.path}${Platform.pathSeparator}migration-archive',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'fails closed on an archive collision and preserves every file',
    () async {
      final directory = await _temporaryGatheringDirectory('collision');
      final sourceBytes = await _writeSource(directory, _profile());
      final digest = sha256.convert(sourceBytes).toString();
      final archive = File(
        '${directory.parent.path}${Platform.pathSeparator}migration-archive'
        '${Platform.pathSeparator}v0.1.7${Platform.pathSeparator}'
        'gathering-state.$digest.json',
      );
      await archive.parent.create(recursive: true);
      const collisionBytes = <int>[9, 8, 7];
      await archive.writeAsBytes(collisionBytes, flush: true);

      await expectLater(
        migrateStableV017GatheringData(directory: directory),
        throwsA(isA<FileSystemException>()),
      );
      expect(await archive.readAsBytes(), collisionBytes);
      expect(await _sourceFile(directory).readAsBytes(), sourceBytes);
      expect(await _destinationFile(directory).exists(), isFalse);
    },
  );

  test(
    'recovers owned stale temporary files without duplicate records',
    () async {
      final directory = await _temporaryGatheringDirectory('stale-temp');
      final sourceBytes = await _writeSource(directory, _profile());
      final digest = sha256.convert(sourceBytes).toString();
      final archive = File(
        '${directory.parent.path}${Platform.pathSeparator}migration-archive'
        '${Platform.pathSeparator}v0.1.7${Platform.pathSeparator}'
        'gathering-state.$digest.json',
      );
      final archiveTemporary = File('${archive.path}.stable-v017.tmp');
      final destinationTemporary = File(
        '${_destinationFile(directory).path}.stable-v017.tmp',
      );
      await archiveTemporary.parent.create(recursive: true);
      await archiveTemporary.writeAsString('stale archive temp', flush: true);
      await destinationTemporary.writeAsString(
        'stale destination temp',
        flush: true,
      );

      expect(
        await migrateStableV017GatheringData(directory: directory),
        isTrue,
      );
      expect(await archiveTemporary.exists(), isFalse);
      expect(await destinationTemporary.exists(), isFalse);
      final store = SessionStore(directory: directory);
      await store.load();
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.id, 'synthetic-gathering-session-1');
    },
  );

  test(
    'resumes safely from a matching archive without a destination',
    () async {
      final directory = await _temporaryGatheringDirectory('resume');
      final sourceBytes = await _writeSource(directory, _profile());
      final digest = sha256.convert(sourceBytes).toString();
      final archive = File(
        '${directory.parent.path}${Platform.pathSeparator}migration-archive'
        '${Platform.pathSeparator}v0.1.7${Platform.pathSeparator}'
        'gathering-state.$digest.json',
      );
      await archive.parent.create(recursive: true);
      await archive.writeAsBytes(sourceBytes, flush: true);

      expect(
        await migrateStableV017GatheringData(directory: directory),
        isTrue,
      );
      expect(await archive.readAsBytes(), sourceBytes);
      final store = SessionStore(directory: directory);
      await store.load();
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.id, 'synthetic-gathering-session-1');
    },
  );

  test('a genuinely fresh root remains untouched', () async {
    final directory = await _temporaryGatheringDirectory('fresh');
    await directory.create(recursive: true);
    expect(await migrateStableV017GatheringData(directory: directory), isFalse);
    expect(await directory.list().toList(), isEmpty);
    final siblings = await directory.parent.list().toList();
    expect(siblings, hasLength(1));
    expect(siblings.single.path, directory.path);
  });

  testWidgets('the imported loadout note card is read-only and conditional', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: companionBackdropBuilder,
        home: const Scaffold(
          body: StableV017GatheringLoadoutNotesCard(
            notes: 'Synthetic Manos gathering loadout',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('stable-v017-gathering-loadout-notes')),
      findsOneWidget,
    );
    expect(find.text('Synthetic Manos gathering loadout'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: companionBackdropBuilder,
        home: const Scaffold(
          body: StableV017GatheringLoadoutNotesCard(notes: ''),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('stable-v017-gathering-loadout-notes')),
      findsNothing,
    );
  });
}
