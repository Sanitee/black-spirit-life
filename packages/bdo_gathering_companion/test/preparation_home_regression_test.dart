import 'dart:async';
import 'dart:io';

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/services/session_store.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/gathering_preparation_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends SessionStore {
  _MemoryStore() : super(directory: Directory.systemTemp);
  bool holdWrites = false;
  final pending = <Completer<void>>[];
  int writeCount = 0;
  @override
  Future<void> save() async {
    writeCount++;
    if (holdWrites) {
      final completion = Completer<void>();
      pending.add(completion);
      await completion.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Spot wolves;
  setUpAll(() async {
    catalog = await Catalog.load();
    wolves = catalog.spots.firstWhere((s) => s.id == 'imp-cave-wolves');
  });

  GatheringPreparationPanel panel(WidgetTester tester) =>
      tester.widget<GatheringPreparationPanel>(
        find.byType(GatheringPreparationPanel, skipOffstage: false),
      );
  FieldGuide guide(WidgetTester tester) =>
      tester.widget<FieldGuide>(find.byType(FieldGuide, skipOffstage: false));

  Future<void> open(
    WidgetTester tester,
    _MemoryStore store, {
    GatheringPreparation? profile,
    String methodId = 'butcher',
    String? spotId,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1100);
    addTearDown(tester.view.reset);
    store.preferences = {
      'methodId': methodId,
      'spotId': spotId ?? wolves.id,
      if (profile != null) gatheringPreparationPreferenceKey: profile.toJson(),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: companionBackdropBuilder,
        home: GatheringHostServicesScope(
          services: GatheringHostServices(openExternal: (_) async => true),
          child: CompanionHome(
            catalog: catalog,
            store: store,
            glassOpacityPercent: 60,
            onGlassOpacityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, String id) async {
    tester
        .widget<TextButton>(
          find.byKey(ValueKey('edit-session-$id'), skipOffstage: false),
        )
        .onPressed!();
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    tester
        .widget<FilledButton>(
          find.widgetWithText(
            FilledButton,
            'Save changes',
            skipOffstage: false,
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
  }

  Buff buff(String id) => catalog.buffs.firstWhere((b) => b.id == id);

  GatheringSession record({Map<String, dynamic>? snapshot}) => GatheringSession(
    id: 'record',
    createdAt: DateTime.utc(2026, 9, 1),
    methodId: 'butcher',
    methodLabel: 'Butchering',
    methodIcon: '',
    spotId: wolves.id,
    spotName: wolves.name,
    durationSeconds: 1800,
    mastery: 1234,
    loot: [LootEntry(id: '7913', name: 'Wolf Meat', overrideTotal: 100)],
    buffs: [buff('buff-890').snapshot()],
    pets: const [
      {
        'id': 'hedgehog',
        'name': 'Historical Hedgehog',
        'icon': '',
        'summary': 'Historical pet details',
      },
    ],
    buffTotals: {'lifeMastery': 17},
    catalogDate: 'historical',
    preparationSnapshot: snapshot,
  );

  testWidgets(
    'legacy history uses neutral unknown stats and preserves mastery on buff-only edits',
    (tester) async {
      final store = _MemoryStore()..sessions.add(record());
      final current = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(
          mastery: 2500,
          gatheringDropRatePercent: 99,
          hedgehogTier: BairogHedgehogTier.tier4,
          minigameMode: BairogMinigameMode.event,
        ),
      );
      final rememberedSpot = catalog.spots.firstWhere(
        (spot) => spot.methodIds.contains('hunting'),
      );
      await open(
        tester,
        store,
        profile: current,
        methodId: 'hunting',
        spotId: rememberedSpot.id,
      );
      await edit(tester, 'record');
      expect(panel(tester).baseSettings.mastery, 1234);
      expect(panel(tester).baseSettings.gatheringDropRatePercent, 0);
      expect(panel(tester).baseSettings.hedgehogTier, BairogHedgehogTier.none);
      expect(panel(tester).baseSettings.minigameMode, BairogMinigameMode.none);
      expect(panel(tester).statsConfirmed, isFalse);
      expect(
        panel(tester).effectiveSettings.mastery,
        1251,
        reason:
            'Untouched legacy totals use archived17, not the current catalog50.',
      );
      panel(tester).onToggleBuff(buff('buff-9691'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(store.sessions.single.mastery, 1234);
      expect(
        store.sessions.single.pets,
        record().pets,
        reason: 'A buff-only edit must not replace historical pet metadata.',
      );
      expect(
        GatheringPreparation.fromPreferences(
          store.preferences,
        ).hasSameValuesAs(current),
        isTrue,
      );
      expect(panel(tester).baseSettings.mastery, 2500);
      expect(store.preferences['methodId'], 'hunting');
      expect(
        store.preferences['spotId'],
        rememberedSpot.id,
        reason:
            'Saving an old butcher run must not move the current kit into its historical context.',
      );
    },
  );

  testWidgets(
    'pet-only edits preserve historical buff snapshots and effective mastery',
    (tester) async {
      final original = record();
      final store = _MemoryStore()..sessions.add(original);
      await open(tester, store);
      await edit(tester, 'record');
      final pet = panel(
        tester,
      ).pets.firstWhere((pet) => pet.id == 'bareeds-junaid');
      panel(tester).onTogglePet(pet);
      await tester.pumpAndSettle();
      expect(panel(tester).effectiveSettings.mastery, 1251);
      await save(tester);
      final changed = store.sessions.single;
      expect(changed.mastery, 1234);
      expect(changed.buffTotals, original.buffTotals);
      expect(changed.buffs, original.buffs);
      expect(changed.preparationSnapshot!['buffTotals'], original.buffTotals);
      expect(
        objectMap(changed.preparationSnapshot!['effectiveSettings'])['mastery'],
        1251,
      );
    },
  );

  testWidgets(
    'untouched frozen effective settings survive preview cancel and unrelated save',
    (tester) async {
      final frozenProfile = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(
          mastery: 1000,
          gatheringDropRatePercent: 20,
        ),
        buffIds: {'buff-890'},
        statsConfirmed: true,
      );
      final snapshot = {
        ...frozenProfile.snapshot(catalog, methodId: 'butcher'),
        'effectiveSettings': const BairogCalculatorSettings(
          mastery: 2300,
          gatheringDropRatePercent: 71,
        ).toJson(),
      };
      final store = _MemoryStore()..sessions.add(record(snapshot: snapshot));
      await open(tester, store);
      await edit(tester, 'record');
      expect(panel(tester).effectiveSettings.mastery, 2300);
      await tester.tap(find.byKey(const ValueKey('workflow-spots')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-gathering-setup')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gathering-setup-mastery')),
        '1200',
      );
      await tester.pumpAndSettle();
      expect(panel(tester).effectiveSettings.mastery, 1250);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(panel(tester).effectiveSettings.mastery, 2300);
      await tester.tap(find.byKey(const ValueKey('workflow-gather')));
      await tester.pumpAndSettle();
      await save(tester);
      expect(store.sessions.single.preparationSnapshot, snapshot);
      expect(store.sessions.single.buffTotals, {'lifeMastery': 17});
      expect(store.sessions.single.mastery, 1234);
    },
  );

  testWidgets(
    'context reconciliation persists pet removal and clears the same stored tier',
    (tester) async {
      final profile = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(
          hedgehogTier: BairogHedgehogTier.tier3,
        ),
        petIds: {'hedgehog'},
        statsConfirmed: true,
      );
      final store = _MemoryStore();
      await open(tester, store, profile: profile);
      final other = catalog.spots.firstWhere(
        (s) =>
            s.methodIds.contains('hunting') && s.id != 'narcion-deer-hunting',
      );
      guide(tester).onUseWithMethod!(other, 'hunting');
      await tester.pumpAndSettle();
      expect(panel(tester).selectedPetIds, isEmpty);
      expect(panel(tester).baseSettings.hedgehogTier, BairogHedgehogTier.none);
      final persisted = GatheringPreparation.fromPreferences(store.preferences);
      expect(persisted.petIds, isEmpty);
      expect(persisted.baseSettings.hedgehogTier, BairogHedgehogTier.none);
      expect(store.preferences['methodId'], 'hunting');
      expect(store.preferences['spotId'], other.id);
    },
  );

  testWidgets(
    'two failed queued writes roll back to the last committed profile',
    (tester) async {
      final store = _MemoryStore();
      final initial = GatheringPreparation(statsConfirmed: true);
      await open(tester, store, profile: initial);
      store.holdWrites = true;
      panel(tester).onToggleBuff(buff('buff-9691'));
      await tester.pump();
      panel(tester).onToggleBuff(buff('buff-890'));
      await tester.pump();
      expect(store.pending, hasLength(1));
      store.pending[0].completeError(StateError('First write failed'));
      await tester.pump();
      await tester.pump();
      expect(store.pending, hasLength(2));
      store.pending[1].completeError(StateError('Second write failed'));
      await tester.pumpAndSettle();
      expect(panel(tester).selectedBuffIds, isEmpty);
      expect(
        GatheringPreparation.fromPreferences(
          store.preferences,
        ).hasSameValuesAs(initial),
        isTrue,
      );
      expect(
        find.textContaining('Could not save your preparation'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'start waits for the newest queued profile and blocks changes during transition',
    (tester) async {
      final store = _MemoryStore();
      await open(tester, store);
      final start = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('start-gathering'), skipOffstage: false),
          )
          .onPressed!;
      store.holdWrites = true;
      panel(tester).onToggleBuff(buff('buff-9691'));
      await tester.pump();
      panel(tester).onToggleBuff(buff('buff-890'));
      await tester.pump();
      start();
      await tester.pump();
      panel(tester).onToggleBuff(buff('buff-768064'));
      await tester.pump();
      store.pending[0].complete();
      await tester.pump();
      await tester.pump();
      expect(store.pending, hasLength(2));
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Pause timer',
          skipOffstage: false,
        ),
        findsNothing,
      );
      store.pending[1].complete();
      await tester.pump();
      await tester.pump();
      expect(panel(tester).selectedBuffIds, {'buff-9691', 'buff-890'});
      final pause = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Pause timer',
        skipOffstage: false,
      );
      expect(pause, findsOneWidget);
      tester
          .widget<OutlinedButton>(
            find.descendant(of: pause, matching: find.byType(OutlinedButton)),
          )
          .onPressed!();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'same spot keeps a paused run while another spot asks before clearing it',
    (tester) async {
      final store = _MemoryStore();
      await open(tester, store);
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('start-gathering'), skipOffstage: false),
          )
          .onPressed!();
      await tester.pump();
      // Production elapsed time uses DateTime.now, not the fake widget clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump();
      final pause = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Pause timer',
        skipOffstage: false,
      );
      tester
          .widget<OutlinedButton>(
            find.descendant(of: pause, matching: find.byType(OutlinedButton)),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      guide(tester).onUse(wolves);
      await tester.pumpAndSettle();
      expect(find.text('Change spot?'), findsNothing);
      expect(find.text('Resume gathering'), findsOneWidget);
      final other = catalog.spots.firstWhere(
        (s) => s.methodIds.contains('butcher') && s.id != wolves.id,
      );
      guide(tester).onUse(other);
      await tester.pumpAndSettle();
      expect(find.text('Change spot?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(panel(tester).spotId, wolves.id);
      expect(find.text('Resume gathering'), findsOneWidget);
    },
  );
}
