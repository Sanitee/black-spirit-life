import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/stable_v017_migration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'feature migrates stable v0.1.7 before load while current data stays authoritative',
    (tester) async {
      {
        final fixture = await _featureFixture(tester, 'source-only');
        final sourceBytes = utf8.encode(
          jsonEncode(
            _stableV017Document(
              sessionId: 'legacy-history-session',
              method: 'Harvesting',
              location: 'Legacy <Meadow> & Grove',
              notes: 'Exact legacy <notes> & "quoted" text',
            ),
          ),
        );
        await tester.runAsync(() async {
          await fixture.directory.create(recursive: true);
          await fixture.source.writeAsBytes(sourceBytes, flush: true);
        });

        Map<String, dynamic>? destinationSeenByPreparation;
        await tester.pumpWidget(
          GatheringCompanionFeature(
            dataDirectory: fixture.directory,
            prepareDataDirectory: (directory) async {
              destinationSeenByPreparation = Map<String, dynamic>.from(
                jsonDecode(await fixture.destination.readAsString()) as Map,
              );
            },
            sharedMarketLoader: _noNetworkMarket,
          ),
        );
        await _untilHomeLoads(tester);

        expect(destinationSeenByPreparation, isNotNull);
        final preparationPreferences = Map<String, dynamic>.from(
          destinationSeenByPreparation!['preferences'] as Map,
        );
        expect(
          preparationPreferences,
          contains(stableV017GatheringMigrationPreferenceKey),
        );
        final home = tester.widget<CompanionHome>(find.byType(CompanionHome));
        expect(home.store.sessions, hasLength(1));
        expect(home.store.sessions.single.id, 'legacy-history-session');
        expect(home.store.sessions.single.mastery, 2111);
        expect(
          home.store.sessions.single.notes,
          'Exact legacy <notes> & "quoted" text',
        );
        expect(
          home.store.preferences,
          contains(stableV017GatheringMigrationPreferenceKey),
        );
        final preservedSourceBytes = (await tester.runAsync(
          fixture.source.readAsBytes,
        ))!;
        expect(preservedSourceBytes, sourceBytes);
        await _verifyReadOnlyMixedHistory(tester, home);
        expect(find.text('Gathering data could not be opened'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }

      {
        final fixture = await _featureFixture(tester, 'current-wins');
        final sourceBytes = utf8.encode(jsonEncode(_stableV017Document()));
        final destinationBytes = utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'sessions': [_currentSession()],
            'preferences': {'glassOpacityPercent': 77},
          }),
        );
        await tester.runAsync(() async {
          await fixture.directory.create(recursive: true);
          await fixture.source.writeAsBytes(sourceBytes, flush: true);
          await fixture.destination.writeAsBytes(destinationBytes, flush: true);
        });

        List<int>? destinationSeenByPreparation;
        await tester.pumpWidget(
          GatheringCompanionFeature(
            dataDirectory: fixture.directory,
            prepareDataDirectory: (directory) async {
              destinationSeenByPreparation = await fixture.destination
                  .readAsBytes();
            },
            sharedMarketLoader: _noNetworkMarket,
          ),
        );
        await _untilHomeLoads(tester);

        expect(destinationSeenByPreparation, destinationBytes);
        final home = tester.widget<CompanionHome>(find.byType(CompanionHome));
        expect(home.store.sessions, hasLength(1));
        expect(home.store.sessions.single.id, 'current-feature-session');
        expect(home.store.sessions.single.spotName, 'Current destination');
        expect(home.store.sessions.single.notes, 'Keep current data');
        expect(home.store.preferences['glassOpacityPercent'], 77);
        expect(
          home.store.preferences,
          isNot(contains(stableV017GatheringMigrationPreferenceKey)),
        );
        final preservedFiles = (await tester.runAsync(() async {
          return (
            destination: await fixture.destination.readAsBytes(),
            source: await fixture.source.readAsBytes(),
            archiveExists: await fixture.archiveRoot.exists(),
          );
        }))!;
        expect(preservedFiles.destination, destinationBytes);
        expect(preservedFiles.source, sourceBytes);
        expect(preservedFiles.archiveExists, isFalse);
        expect(find.text('Gathering data could not be opened'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}

Future<void> _verifyReadOnlyMixedHistory(
  WidgetTester tester,
  CompanionHome home,
) async {
  await tester.runAsync(
    () => home.store.upsert(
      GatheringSession(
        id: 'modern-history-session',
        createdAt: DateTime.utc(2026, 9, 15, 12),
        methodId: 'mining',
        methodLabel: 'Mining',
        methodIcon: '',
        spotId: 'custom',
        spotName: 'Modern Ridge',
        durationSeconds: 1800,
        mastery: 1800,
        notes: 'Modern note',
        loot: [
          LootEntry(id: 'modern-item', name: 'Modern item', overrideTotal: 25),
        ],
        buffs: const [],
        pets: const [],
        buffTotals: const {},
        catalogDate: 'test',
      ),
    ),
  );

  await tester.tap(find.byKey(const ValueKey('workflow-history')));
  await tester.pumpAndSettle();

  expect(find.text('Legacy <Meadow> & Grove'), findsOneWidget);
  expect(find.text('Harvesting'), findsWidgets);
  expect(
    find.byKey(const ValueKey('stable-v017-read-only-legacy-history-session')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('edit-session-legacy-history-session')),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey('delete-session-legacy-history-session')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('edit-session-modern-history-session')),
    findsOneWidget,
  );
  expect(
    find.text('v0.1.7 did not store gathered item totals'),
    findsOneWidget,
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-items')))
        .data,
    '25 + not recorded',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-sessions')))
        .data,
    '2',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-time')))
        .data,
    '1 h 30 min',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-spots')))
        .data,
    '2',
  );

  await tester.enterText(
    find.byKey(const ValueKey('history-search')),
    'Modern Ridge',
  );
  await tester.pump();
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-items')))
        .data,
    '25',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-time')))
        .data,
    '30 min',
  );

  await tester.enterText(
    find.byKey(const ValueKey('history-search')),
    'Legacy <Meadow>',
  );
  await tester.pump();
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-items')))
        .data,
    'Not recorded',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('history-summary-time')))
        .data,
    '1 h',
  );

  await tester.tap(
    find.byKey(const ValueKey('history-session-legacy-history-session')),
  );
  await tester.pumpAndSettle();
  expect(find.text('Imported v0.1.7 · read-only'), findsWidgets);
  expect(find.text('Item totals were not recorded in v0.1.7.'), findsOneWidget);
  expect(find.text('Exact legacy <notes> & "quoted" text'), findsOneWidget);
  expect(find.text('Edit session'), findsNothing);
}

Map<String, dynamic> _stableV017Document({
  String sessionId = 'stable-v017-feature-session',
  String method = 'Butchering',
  String location = 'Stable destination',
  String notes = 'Preserve this stable note',
}) => <String, dynamic>{
  'version': 1,
  'profile': <String, dynamic>{
    'mastery': 2111,
    'loadoutNotes': 'Preserve this stable loadout',
  },
  'sessions': <Object?>[
    <String, dynamic>{
      'id': sessionId,
      'recordedAtUtc': '2026-09-14T10:30:00.000Z',
      'method': method,
      'location': location,
      'durationMinutes': 60,
      'mastery': 2111,
      'notes': notes,
    },
  ],
};

Map<String, dynamic> _currentSession() => <String, dynamic>{
  'id': 'current-feature-session',
  'createdAt': '2026-09-15T08:00:00.000Z',
  'methodId': 'mining',
  'methodLabel': 'Mining',
  'methodIcon': '',
  'spotId': 'custom',
  'spotName': 'Current destination',
  'durationSeconds': 1800,
  'mastery': 1777,
  'notes': 'Keep current data',
  'loot': <Object?>[],
  'buffs': <Object?>[],
  'pets': <Object?>[],
  'buffTotals': <String, double>{},
  'catalogDate': '',
};

Future<_FeatureFixture> _featureFixture(
  WidgetTester tester,
  String label,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1500, 940);
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp(
      'bdo-gathering-stable-v017-feature-$label-',
    ),
  ))!;
  final directory = Directory('${root.path}${Platform.pathSeparator}gathering');
  final fixture = _FeatureFixture(root: root, directory: directory);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await tester.runAsync(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  });
  return fixture;
}

Future<void> _untilHomeLoads(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CompanionHome).evaluate().isNotEmpty) return;
    if (find.text('Gathering data could not be opened').evaluate().isNotEmpty) {
      final details = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText())
          .whereType<String>()
          .join(' | ');
      fail('GatheringCompanionFeature reported a load error: $details');
    }
  }
  fail('GatheringCompanionFeature did not load within the bounded test.');
}

Future<GatheringMarketLoadResult> _noNetworkMarket(
  Map<String, String> itemsById, {
  required bool includePreorders,
  required bool forceRefresh,
  required void Function(GatheringMarketReceipt receipt) onItem,
  Future<void>? cancelled,
}) async => const GatheringMarketLoadResult();

final class _FeatureFixture {
  const _FeatureFixture({required this.root, required this.directory});

  final Directory root;
  final Directory directory;

  File get source =>
      File('${directory.path}${Platform.pathSeparator}gathering-state.json');

  File get destination =>
      File('${directory.path}${Platform.pathSeparator}sessions.json');

  Directory get archiveRoot =>
      Directory('${root.path}${Platform.pathSeparator}migration-archive');
}
