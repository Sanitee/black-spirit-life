import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/services/session_import_inbox.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

const importId = '749a2f13-0ee9-4a35-8aaa-b9313624357f';
Map<String, dynamic> receiptJson({
  int revision = 1,
  int quantity = 1005,
  String activity = 'gathering',
}) => {
  'schemaVersion': 1,
  'provider': 'garmoth',
  'status': 'prepared',
  'importId': importId,
  'revision': revision,
  'importedAtUtc': '2026-09-14T12:00:00Z',
  'target': {
    'spotId': activity == 'grinding' ? '17' : '186',
    'spotName': activity == 'grinding' ? 'Orc Camp' : "Rusalka's Coral",
    'activity': activity,
    'methodIds': [
      activity == 'grinding' ? 'garmoth:grinding' : 'garmoth:stone',
    ],
    'linkedSourceIds': <String>[],
  },
  'session': {
    'durationSeconds': 3600,
    'items': <Map<String, dynamic>>[
      {
        'itemId': '4006',
        'subKey': 0,
        'name': 'Rough Stone',
        'quantity': quantity,
      },
      {'itemId': '6511', 'subKey': 0, 'name': 'Lobster', 'quantity': 38},
      {'itemId': '4477', 'subKey': 0, 'name': 'Blue Coral', 'quantity': 5},
    ],
    'agrisActive': false,
    'additionalDropRate': 0,
  },
  'preparation': {
    'matchedCount': 1,
    'notesCount': 2,
    'skippedCount': 2,
    'submitted': false,
  },
};
Catalog fixtureCatalog() => Catalog(
  methods: [
    Method({'id': 'butcher', 'label': 'Butchering', 'icon': 'butcher.webp'}),
    Method({'id': 'mining', 'label': 'Mining', 'icon': 'pickaxe.webp'}),
    Method({
      'id': 'hunting',
      'label': 'Matchlock hunting',
      'activity': 'hunting',
    }),
  ],
  spots: [],
  buffs: [],
  items: [
    GameItem({'id': '4006', 'name': 'Rough Stone', 'icon': 'stone.webp'}),
  ],
  categories: [],
  stats: [],
  presets: [],
  stackingNotes: [],
  reviewedAt: '2026-09-14',
);
GatheringSession imported({int revision = 1, int quantity = 1005}) =>
    sessionFromReceipt(
      SessionImportMetadata.fromJson(
        receiptJson(revision: revision, quantity: quantity),
      ),
      fixtureCatalog(),
    );
GatheringSession manual() => GatheringSession.fromJson({
  ...imported().toJson(),
  'id': 'manual-session',
  'sessionImport': null,
});
Future<File> writeReceipt(
  SessionImportInbox inbox,
  Map<String, dynamic> value,
) async {
  final directory = await Directory(
    inbox.directoryPath,
  ).create(recursive: true);
  final id = (value['importId'] as String).replaceAll('-', '');
  return File(
    '${directory.path}/$id-${value['revision'].toString().padLeft(10, '0')}.json',
  )..writeAsStringSync(jsonEncode(value), flush: true);
}

void main() {
  late Directory temporary;
  late SessionStore store;
  late SessionImportInbox inbox;
  var notifications = 0;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bsl-import-inbox-test-');
    store = SessionStore(directory: temporary);
    notifications = 0;
    inbox = SessionImportInbox(
      store: store,
      catalog: fixtureCatalog(),
      onChanged: () => notifications++,
    );
  });
  tearDown(() async {
    inbox.dispose();
    await temporary.delete(recursive: true);
  });

  test(
    'typed metadata preserves original rows, false, zero and independent Notes counts',
    () {
      final data = SessionImportMetadata.fromJson(receiptJson());
      expect(data.items.map((item) => item.quantity), [1005, 38, 5]);
      expect(data.agrisActive, false);
      expect(data.additionalDropRate, 0);
      expect(data.additionalDropAmount, isNull);
      expect(data.agrisUsed, isNull);
      expect(data.matchedCount, 1);
      expect(data.notesCount, 2);
      expect(data.toJson()['preparation'], containsPair('submitted', false));
      expect(() => data.items.clear(), throwsUnsupportedError);
      expect(
        SessionImportMetadata.fromJson(data.toJson()).toJson(),
        data.toJson(),
      );
    },
  );
  test('malformed receipt, false successes and browser fields fail closed', () {
    for (final alter in <void Function(Map<String, dynamic>)>[
      (j) => j['schemaVersion'] = 2,
      (j) => j['provider'] = 'other',
      (j) => j['importId'] = '../../sessions',
      (j) => j['revision'] = 0,
      (j) => j['target']['activity'] = 'unknown',
      (j) => j['session']['durationSeconds'] = 0,
      (j) => j['session']['agrisActive'] = 1,
      (j) => j['session']['additionalDropRate'] = 1.001,
      (j) => j['session']['additionalDropAmount'] = double.infinity,
      (j) => j['session']['agrisUsed'] = -1,
      (j) => j['session']['items'][0]['quantity'] = 0,
      (j) => j['session']['items'][0]['subKey'] = -1,
      (j) => j['preparation']['matchedCount'] = 0,
      (j) => j['preparation']['notesCount'] = 3,
      (j) => j['preparation']['submitted'] = true,
      (j) => j['cookies'] = 'not allowed',
      (j) => j['target']['url'] = 'https://example.test/private',
      (j) => j['session']['items'][1] = j['session']['items'][0],
    ]) {
      final value = receiptJson();
      alter(value);
      expect(
        () => SessionImportMetadata.fromJson(value),
        throwsFormatException,
      );
    }
  });
  test(
    'projection uses original quantities, known method and icon without invented buffs',
    () {
      final session = imported();
      expect(session.id, 'session-import:$importId');
      expect(session.methodId, 'mining');
      expect(session.methodIcon, 'pickaxe.webp');
      expect(session.loot.map((item) => item.total), [1005, 38, 5]);
      expect(session.loot.first.icon, 'stone.webp');
      expect(session.loot.last.icon, '');
      expect(session.buffs, isEmpty);
      expect(session.buffTotals, isEmpty);
      expect(session.preparationSnapshot, isNull);
      expect(
        GatheringSession.fromJson(session.toJson()).toJson(),
        session.toJson(),
      );
      expect(manual().toJson().containsKey('sessionImport'), false);
    },
  );
  test(
    'grinding is never relabelled as gathering or first available method',
    () {
      final session = sessionFromReceipt(
        SessionImportMetadata.fromJson(receiptJson(activity: 'grinding')),
        fixtureCatalog(),
      );
      expect(session.methodId, 'grinding');
      expect(session.methodLabel, 'Grinding');
      expect(session.methodIcon, '');
      expect(session.spotId, 'garmoth:17');
    },
  );
  test('name-only and enhanced items remain distinct from base market IDs', () {
    final json = receiptJson();
    json['session']['items'][1] = {
      'itemId': '4006',
      'subKey': 1,
      'name': 'Enhanced test',
      'quantity': 3,
    };
    json['session']['items'][2] = {
      'itemId': null,
      'subKey': 0,
      'name': 'Unmapped reviewed item',
      'quantity': 5,
    };
    final session = sessionFromReceipt(
      SessionImportMetadata.fromJson(json),
      fixtureCatalog(),
    );
    expect(session.loot.map((item) => item.id).toSet(), hasLength(3));
    expect(session.loot[1].id, '4006:1');
    expect(session.loot[2].id, startsWith('session-import-item:'));
    expect(session.sessionImport!.items.last.itemId, isNull);
  });
  test(
    'durable ingest keeps every reviewed row then acknowledges only its receipt',
    () async {
      store.preferences = {
        'methodId': 'butcher',
        'spotId': 'untouched',
        'glassOpacityPercent': 17,
      };
      final file = await writeReceipt(inbox, receiptJson());
      await inbox.drain();
      expect(store.sessions.single.loot.map((item) => item.total), [
        1005,
        38,
        5,
      ]);
      expect(store.preferences['spotId'], 'untouched');
      expect(await file.exists(), false);
      expect(notifications, 1);
      final reloaded = SessionStore(directory: temporary);
      await reloaded.load();
      expect(reloaded.sessions.single.sessionImport!.notesCount, 2);
      expect(reloaded.preferences, store.preferences);
    },
  );
  test(
    'retry/restart and older receipts do not duplicate or downgrade history',
    () async {
      await writeReceipt(inbox, receiptJson(revision: 2, quantity: 2000));
      await writeReceipt(inbox, receiptJson());
      await inbox.drain();
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.loot.first.total, 2000);
      expect(store.sessions.single.createdAt, DateTime.utc(2026, 9, 14, 12));
      await writeReceipt(inbox, receiptJson(revision: 2, quantity: 2000));
      await inbox.drain();
      expect(store.sessions, hasLength(1));
      expect(notifications, 1);
      expect(await Directory(inbox.directoryPath).list().length, 0);
    },
  );
  test(
    'failed save rolls memory back and retains the exact receipt for retry',
    () async {
      await store.upsert(manual());
      final originalBytes = await store.file.readAsBytes();
      final blocker = await Directory('${store.file.path}.tmp').create();
      final file = await writeReceipt(inbox, receiptJson());
      await inbox.drain();
      expect(store.sessions.single.id, 'manual-session');
      expect(await store.file.readAsBytes(), originalBytes);
      expect(await file.exists(), true);
      expect(inbox.lastError, isNotNull);
      await blocker.delete();
      await inbox.drain();
      expect(store.sessions, hasLength(2));
      expect(await file.exists(), false);
      expect(inbox.lastError, isNull);
    },
  );
  test(
    'conflicting equal revision stays pending rather than replacing saved history',
    () async {
      await store.upsertImported(imported());
      final file = await writeReceipt(inbox, receiptJson(quantity: 999));
      await inbox.drain();
      expect(store.sessions.single.loot.first.total, 1005);
      expect(await file.exists(), true);
      expect(inbox.lastError, isNotNull);
    },
  );
  test(
    'temporary files, malformed receipts and filename mismatches cannot become history',
    () async {
      await Directory(inbox.directoryPath).create();
      await File(
        '${inbox.directoryPath}/.pending-fixture.tmp',
      ).writeAsString(jsonEncode(receiptJson()));
      final file = await writeReceipt(inbox, receiptJson());
      await file.writeAsString('{partial');
      await inbox.drain();
      expect(store.sessions, isEmpty);
      expect(await file.exists(), true);
      await file.writeAsString(jsonEncode(receiptJson(revision: 2)));
      await inbox.drain();
      expect(store.sessions, isEmpty);
      expect(await file.exists(), true);
    },
  );
  test('dispose never starts an import or creates an inbox', () async {
    inbox.dispose();
    inbox.start();
    await inbox.drain();
    expect(store.sessions, isEmpty);
    expect(await Directory(inbox.directoryPath).exists(), false);
  });
  test(
    'concurrent manual/import writes are serialized and a failed turn does not roll back its successor',
    () async {
      final held = HoldingStore(directory: temporary);
      final manualSave = held.upsert(manual());
      await held.entered.future;
      final importSave = held.upsertImported(imported());
      expect(held.sessions.map((row) => row.id), ['manual-session']);
      final failed = expectLater(manualSave, throwsStateError);
      held.release.complete();
      await failed;
      expect(await importSave, true);
      expect(held.sessions.single.id, 'session-import:$importId');
      final reloaded = SessionStore(directory: temporary);
      await reloaded.load();
      expect(reloaded.sessions.single.id, 'session-import:$importId');
    },
  );
  test(
    'stale imported editor cannot overwrite a newer acknowledged native revision',
    () async {
      final oldEditor = imported();
      await store.upsertImported(oldEditor);
      await writeReceipt(inbox, receiptJson(revision: 2, quantity: 2000));
      await inbox.drain();
      await expectLater(store.upsert(oldEditor), throwsStateError);
      expect(store.sessions.single.sessionImport!.revision, 2);
      expect(store.sessions.single.loot.first.total, 2000);
      final withoutMetadata = GatheringSession.fromJson({
        ...oldEditor.toJson(),
        'sessionImport': null,
      });
      await expectLater(store.upsert(withoutMetadata), throwsStateError);
      final currentEdit = GatheringSession.fromJson({
        ...store.sessions.single.toJson(),
        'notes': 'My local note',
        'createdAt': '2026-09-13T10:00:00Z',
        'mastery': 1700,
        'buffs': [
          {
            'id': 'local-buff',
            'name': 'Recorded buff',
            'category': 'food',
            'icon': '',
            'effects': {'lifeExpPct': 10},
            'durationMinutes': 30,
          },
        ],
        'pets': [
          {
            'id': 'local-pet',
            'name': 'Recorded pet',
            'icon': '',
            'summary': '',
          },
        ],
        'buffTotals': {'lifeExpPct': 10},
        'preparationSnapshot': {'recorded': true},
        'catalogDate': '2026-08-01',
      });
      await store.upsert(currentEdit);
      expect(store.sessions.single.notes, 'My local note');
      await store.upsertImported(imported(revision: 3, quantity: 3000));
      expect(store.sessions.single.notes, 'My local note');
      expect(store.sessions.single.loot.first.total, 3000);
      final updated = store.sessions.single;
      expect(updated.createdAt, DateTime.utc(2026, 9, 13, 10));
      expect(updated.mastery, 1700);
      expect(updated.buffs.single['name'], 'Recorded buff');
      expect(updated.pets.single['name'], 'Recorded pet');
      expect(updated.buffTotals, {'lifeExpPct': 10});
      expect(updated.preparationSnapshot, {'recorded': true});
      expect(updated.catalogDate, '2026-08-01');
    },
  );
}

class HoldingStore extends SessionStore {
  HoldingStore({required super.directory});
  final entered = Completer<void>();
  final release = Completer<void>();
  var calls = 0;
  @override
  Future<void> save() async {
    if (++calls == 1) {
      entered.complete();
      await release.future;
      throw StateError('isolated injected write failure');
    }
    await super.save();
  }
}
