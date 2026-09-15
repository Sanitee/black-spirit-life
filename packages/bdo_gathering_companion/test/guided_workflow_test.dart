import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/ui/buff_picker.dart';
import 'package:bdo_gathering_companion/src/ui/loot_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorkflowStore extends SessionStore {
  _WorkflowStore(Directory directory) : super(directory: directory);

  @override
  Future<void> save() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Directory temporaryRoot;

  setUpAll(() async {
    catalog = await Catalog.load();
    temporaryRoot = await Directory.systemTemp.createTemp(
      'bdo-guided-workflow-',
    );
  });

  tearDownAll(() async {
    if (temporaryRoot.parent.absolute.path !=
            Directory.systemTemp.absolute.path ||
        !temporaryRoot.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('bdo-guided-workflow-')) {
      throw StateError('Refusing to remove an unexpected test directory.');
    }
    await temporaryRoot.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, _WorkflowStore store) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1563, 950);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: companionBackdropBuilder,
        home: GatheringHostServicesScope(
          services: GatheringHostServices(openExternal: (_) async => true),
          child: CompanionHome(
            catalog: catalog,
            store: store,
            glassOpacityPercent: defaultGlassOpacityPercent,
            onGlassOpacityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder lootTotals() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('loot-total-'),
  );

  testWidgets(
    'choose a spot, prepare, start, preserve the timer and save results',
    (tester) async {
      final store = _WorkflowStore(temporaryRoot);
      await mount(tester, store);
      expect(find.byKey(const ValueKey('spot-list')), findsOneWidget);
      expect(find.byType(LootPanel), findsNothing);
      expect(find.byType(BuffPicker), findsNothing);
      for (final key in ['workflow-prepare', 'workflow-gather']) {
        expect(
          tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }

      final cards = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('spot-card-'),
      );
      expect(cards, findsWidgets);
      final cardKey = tester.widget(cards.first).key! as ValueKey<String>;
      final chosen = catalog.spots.firstWhere(
        (spot) => 'spot-card-${spot.id}' == cardKey.value,
      );
      await tester.tap(cards.first);
      await tester.pumpAndSettle();
      final use = find.byKey(const ValueKey('use-spot'));
      await tester.ensureVisible(use);
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gathering-preparation-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('preparation-stats')), findsOneWidget);
      expect(find.byType(LootPanel), findsNothing);

      final start = find.byKey(const ValueKey('start-gathering'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LootPanel), findsOneWidget);
      expect(find.byTooltip('Pause timer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workflow-spots')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('workflow-gather')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byTooltip('Pause timer'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('time-30')));
      await tester.pumpAndSettle();

      expect(lootTotals(), findsWidgets);
      final quantity = lootTotals().first;
      final itemId = (tester.widget(quantity).key! as ValueKey<String>).value
          .substring('loot-total-'.length);
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '23');
      await tester.pumpAndSettle();
      final save = find.text('Save session');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-filters')), findsOneWidget);
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.spotId, chosen.id);
      expect(store.sessions.single.durationSeconds, 1800);
      expect(
        store.sessions.single.loot
            .singleWhere((entry) => entry.id == itemId)
            .total,
        23,
      );
      expect(store.preferences['spotId'], chosen.id);
      expect(find.byType(LootPanel), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'inline stats preserve drafts and gate run actions until both values are valid',
    (tester) async {
      final store = _WorkflowStore(temporaryRoot);
      final spot = catalog.spots.firstWhere(
        (spot) => spot.methodIds.contains('butcher') && spot.mapped,
      );
      store.preferences = {'methodId': 'butcher', 'spotId': spot.id};
      await mount(tester, store);
      Finder keyed(String key, {bool skipOffstage = true}) =>
          find.byKey(ValueKey(key), skipOffstage: skipOffstage);
      Future<void> tap(String key) async {
        await tester.ensureVisible(keyed(key));
        await tester.tap(keyed(key));
        await tester.pumpAndSettle();
      }

      void expectActionsEnabled(bool enabled) {
        for (final key in [
          'start-gathering',
          'record-results',
          'workflow-gather',
        ]) {
          expect(
            tester
                    .widget<ButtonStyleButton>(keyed(key, skipOffstage: false))
                    .onPressed !=
                null,
            enabled,
            reason: key,
          );
        }
        final save = find.ancestor(
          of: find.text('Save session', skipOffstage: false),
          matching: find.byType(FilledButton, skipOffstage: false),
        );
        expect(save, findsOneWidget);
        expect(tester.widget<FilledButton>(save).onPressed != null, enabled);
      }

      await tap('workflow-prepare');
      final mastery = keyed('inline-stats-mastery');
      final dropRate = keyed('inline-stats-drop-rate');
      expect(tester.widget<TextField>(mastery).controller!.text, '');
      expect(tester.widget<TextField>(dropRate).controller!.text, '');
      expectActionsEnabled(true);
      final before = jsonEncode(store.preferences);

      await tester.enterText(mastery, '1735');
      await tester.pumpAndSettle();
      expectActionsEnabled(false);
      expect(jsonEncode(store.preferences), before);
      await tap('workflow-spots');
      await tap('workflow-prepare');
      expect(tester.widget<TextField>(mastery).controller!.text, '1735');
      expect(tester.widget<TextField>(dropRate).controller!.text, '');
      expectActionsEnabled(false);

      await tester.enterText(dropRate, '47');
      await tester.pumpAndSettle();
      expectActionsEnabled(true);
      final confirmed = GatheringPreparation.fromPreferences(store.preferences);
      expect(confirmed.statsConfirmed, isTrue);
      expect(confirmed.baseSettings.mastery, 1735);
      expect(confirmed.baseSettings.gatheringDropRatePercent, 47);

      await tester.enterText(mastery, '3001');
      await tester.pumpAndSettle();
      expectActionsEnabled(false);
      expect(
        GatheringPreparation.fromPreferences(store.preferences).toJson(),
        confirmed.toJson(),
      );
      await tap('inline-stats-reset');
      expect(tester.widget<TextField>(mastery).controller!.text, '1735');
      expect(tester.widget<TextField>(dropRate).controller!.text, '47');
      expectActionsEnabled(true);

      await tap('preparation-lightstones-buff-yawning-hedgehog');
      final buffed = GatheringPreparation.fromPreferences(store.preferences);
      expect(buffed.baseSettings.toJson(), confirmed.baseSettings.toJson());
      expect(buffed.buffIds, contains('buff-yawning-hedgehog'));
      final effective = buffed.effectiveSettings(catalog);
      expect(effective.mastery, greaterThan(1735));
      expect(effective.gatheringDropRatePercent, greaterThan(47));
      expect(tester.widget<TextField>(mastery).controller!.text, '1735');
      expect(tester.widget<TextField>(dropRate).controller!.text, '47');

      await tap('record-results');
      expect(find.byTooltip('Pause timer'), findsNothing);
      final quantity = lootTotals().first;
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '29');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save session'));
      await tester.tap(find.text('Save session'));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.totalItems, 29);
      final snapshot = store.sessions.single.preparationSnapshot!;
      final recordedProfile = GatheringPreparation.fromJson(
        objectMap(snapshot['profile']),
      );
      expect(recordedProfile.baseSettings.mastery, 1735);
      expect(recordedProfile.baseSettings.gatheringDropRatePercent, 47);
      expect(
        objectMap(snapshot['effectiveSettings'])['mastery'],
        effective.mastery,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'historical sessions without preparation snapshots remain editable',
    (tester) async {
      final store = _WorkflowStore(temporaryRoot);
      final method = catalog.methods.firstWhere(
        (entry) => entry.id == 'butcher',
      );
      final spot = catalog.spots.firstWhere(
        (entry) => entry.methodIds.contains(method.id),
      );
      final item = catalog.items.first;
      final buff = catalog.buffs.first;
      final original = GatheringSession(
        id: 'legacy-record',
        createdAt: DateTime.utc(2025, 8, 10, 12),
        methodId: method.id,
        methodLabel: method.label,
        methodIcon: method.icon,
        spotId: spot.id,
        spotName: spot.name,
        durationSeconds: 3600,
        mastery: 1234,
        notes: 'Keep this old note',
        loot: [
          LootEntry(
            id: item.id,
            name: item.name,
            icon: item.icon,
            overrideTotal: 41,
          ),
        ],
        buffs: [buff.snapshot()],
        buffTotals: Map<String, double>.from(buff.effects),
        catalogDate: 'legacy-catalog',
      );
      final legacy = GatheringSession.fromJson(original.toJson());
      expect(legacy.preparationSnapshot, isNull);
      store.sessions.add(legacy);
      await mount(tester, store);
      await tester.tap(find.byKey(const ValueKey('workflow-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit session'));
      await tester.pumpAndSettle();
      final quantity = find.byKey(ValueKey('loot-total-${item.id}'));
      await tester.ensureVisible(quantity);
      expect(tester.widget<TextField>(quantity).controller!.text, '41');
      await tester.enterText(quantity, '43');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final saved = store.sessions.single;
      expect(saved.id, legacy.id);
      expect(saved.createdAt.toUtc(), legacy.createdAt.toUtc());
      expect(saved.durationSeconds, 3600);
      expect(saved.mastery, 1234);
      expect(saved.notes, legacy.notes);
      expect(saved.buffs, legacy.buffs);
      expect(saved.buffTotals, legacy.buffTotals);
      expect(saved.catalogDate, 'legacy-catalog');
      expect(saved.preparationSnapshot, isNull);
      expect(saved.totalItems, 43);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'record results skips the timer and saved sessions stay editable',
    (tester) async {
      final store = _WorkflowStore(temporaryRoot);
      final spot = catalog.spots.firstWhere(
        (spot) => spot.methodIds.contains('butcher') && spot.mapped,
      );
      store.preferences = {'methodId': 'butcher', 'spotId': spot.id};
      await mount(tester, store);
      await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
      await tester.pumpAndSettle();
      final record = find.byKey(const ValueKey('record-results'));
      await tester.ensureVisible(record);
      await tester.tap(record);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause timer'), findsNothing);
      expect(find.byKey(const ValueKey('paste-screenshot')), findsOneWidget);
      final quantity = lootTotals().first;
      final quantityKey = tester.widget(quantity).key!;
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '17');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save session'));
      await tester.tap(find.text('Save session'));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(1));
      final savedId = store.sessions.single.id;
      final savedDuration = store.sessions.single.durationSeconds;
      await tester.tap(find.byTooltip('Edit session'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(quantityKey)).controller!.text,
        '17',
      );
      expect(find.text('Save changes'), findsOneWidget);
      await tester.ensureVisible(find.byKey(quantityKey));
      await tester.enterText(find.byKey(quantityKey), '21');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.id, savedId);
      expect(store.sessions.single.durationSeconds, savedDuration);
      expect(store.sessions.single.totalItems, 21);
      expect(find.byKey(const ValueKey('history-filters')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
