import 'dart:convert';
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

/// A JSON save boundary without touching live or temporary user files.
class _InlineMemoryStore extends SessionStore {
  _InlineMemoryStore() : super(directory: Directory.systemTemp);
  Map<String, dynamic>? saved;
  int writes = 0;

  @override
  Future<void> save() async {
    writes++;
    saved = objectMap(
      jsonDecode(
        jsonEncode({
          'preferences': preferences,
          'sessions': sessions.map((session) => session.toJson()).toList(),
        }),
      ),
    );
  }

  _InlineMemoryStore reload() {
    final restored = _InlineMemoryStore();
    restored.preferences = objectMap(saved!['preferences']);
    restored.sessions.addAll(
      objectList(saved!['sessions']).map(GatheringSession.fromJson),
    );
    return restored;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Spot wolves;
  setUpAll(() async {
    catalog = await Catalog.load();
    wolves = catalog.spots.firstWhere((spot) => spot.id == 'imp-cave-wolves');
  });

  Finder field(String suffix) =>
      find.byKey(ValueKey('inline-stats-$suffix'), skipOffstage: false);
  String input(WidgetTester tester, String suffix) =>
      tester.widget<TextField>(field(suffix)).controller!.text;
  GatheringPreparationPanel panel(WidgetTester tester) =>
      tester.widget<GatheringPreparationPanel>(
        find.byType(GatheringPreparationPanel, skipOffstage: false),
      );
  FieldGuide guide(WidgetTester tester) =>
      tester.widget<FieldGuide>(find.byType(FieldGuide, skipOffstage: false));
  GatheringPreparation stored(_InlineMemoryStore store) =>
      GatheringPreparation.fromPreferences(store.preferences, catalog: catalog);
  Buff buff(String id) => catalog.buffs.firstWhere((buff) => buff.id == id);

  _InlineMemoryStore newStore({GatheringPreparation? profile}) =>
      _InlineMemoryStore()
        ..preferences = {
          'methodId': 'butcher',
          'spotId': wolves.id,
          if (profile != null)
            gatheringPreparationPreferenceKey: profile.toJson(),
        };

  Future<void> open(
    WidgetTester tester,
    _InlineMemoryStore store, {
    bool prepare = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1100);
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
            glassOpacityPercent: 60,
            onGlassOpacityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (prepare) {
      await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> enter(WidgetTester tester, String suffix, String value) async {
    await tester.ensureVisible(field(suffix));
    await tester.enterText(field(suffix), value);
    await tester.pumpAndSettle();
  }

  void expectActionsEnabled(
    WidgetTester tester,
    bool enabled, {
    String saveLabel = 'Save session',
  }) {
    expect(
      tester
              .widget<FilledButton>(
                find.byKey(
                  const ValueKey('start-gathering'),
                  skipOffstage: false,
                ),
              )
              .onPressed !=
          null,
      enabled,
    );
    expect(
      tester
              .widget<TextButton>(
                find.byKey(
                  const ValueKey('record-results'),
                  skipOffstage: false,
                ),
              )
              .onPressed !=
          null,
      enabled,
    );
    expect(
      tester
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  saveLabel,
                  skipOffstage: false,
                ),
              )
              .onPressed !=
          null,
      enabled,
    );
  }

  testWidgets(
    'saved base values stay visible and updated values survive a JSON reload',
    (tester) async {
      final store = newStore(
        profile: GatheringPreparation(
          baseSettings: const BairogCalculatorSettings(
            mastery: 1723,
            gatheringDropRatePercent: 43.5,
            enabledExpenseItemIds: {},
          ),
          statsConfirmed: true,
        ),
      );
      await open(tester, store);
      expect(input(tester, 'mastery'), '1723');
      expect(
        double.parse(input(tester, 'drop-rate').replaceAll(',', '.')),
        43.5,
      );
      expect(
        store.writes,
        0,
        reason: 'Showing saved values must not confirm or rewrite them.',
      );
      await enter(tester, 'mastery', '1850');
      await enter(tester, 'drop-rate', '47.5');
      expect(stored(store).baseSettings.mastery, 1850);
      expect(stored(store).baseSettings.gatheringDropRatePercent, 47.5);
      final restored = store.reload();
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, restored);
      expect(input(tester, 'mastery'), '1850');
      expect(
        double.parse(input(tester, 'drop-rate').replaceAll(',', '.')),
        47.5,
      );
      expect(panel(tester).statsConfirmed, isTrue);
      expect(restored.writes, 0);
    },
  );

  testWidgets(
    'untouched examples stay optional and both explicit fields are required to confirm',
    (tester) async {
      final store = newStore();
      await open(tester, store);
      expect(input(tester, 'mastery'), isEmpty);
      expect(input(tester, 'drop-rate'), isEmpty);
      expect(panel(tester).statsConfirmed, isFalse);
      expect(store.writes, 0);
      expectActionsEnabled(tester, true);
      await enter(tester, 'mastery', '1650');
      expect(panel(tester).statsConfirmed, isFalse);
      expect(
        stored(store).baseSettings.mastery,
        2000,
        reason: 'A partial pair is not a complete persisted base-stat edit.',
      );
      expect(stored(store).baseSettings.gatheringDropRatePercent, 60);
      expectActionsEnabled(tester, false);
      await enter(tester, 'drop-rate', '25');
      expect(panel(tester).statsConfirmed, isTrue);
      expect(stored(store).baseSettings.mastery, 1650);
      expect(stored(store).baseSettings.gatheringDropRatePercent, 25);
      expectActionsEnabled(tester, true);
    },
  );

  testWidgets(
    'invalid and partial values block actions without coercion or losing raw text',
    (tester) async {
      final store = newStore(
        profile: GatheringPreparation(
          baseSettings: const BairogCalculatorSettings(
            mastery: 1234,
            gatheringDropRatePercent: 20,
            enabledExpenseItemIds: {},
          ),
          statsConfirmed: true,
        ),
      );
      await open(tester, store);
      await enter(tester, 'mastery', '');
      expectActionsEnabled(tester, false);
      expect(stored(store).baseSettings.mastery, 1234);
      await enter(tester, 'mastery', '3001');
      expectActionsEnabled(tester, false);
      panel(tester).onToggleBuff(buff('buff-890'));
      await tester.pumpAndSettle();
      expect(
        input(tester, 'mastery'),
        '3001',
        reason: 'A buff rebuild must not overwrite the visible invalid draft.',
      );
      expect(stored(store).baseSettings.mastery, 1234);
      expect(stored(store).baseSettings.gatheringDropRatePercent, 20);
      await enter(tester, 'mastery', '1400');
      await enter(tester, 'drop-rate', '2..5');
      expectActionsEnabled(tester, false);
      expect(stored(store).baseSettings.gatheringDropRatePercent, 20);
      expect(input(tester, 'drop-rate'), '2..5');
      final reset = find.byKey(const ValueKey('inline-stats-reset'));
      expect(panel(tester).statsEnabled, isTrue);
      expect(tester.widget<IconButton>(reset).onPressed, isNotNull);
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(input(tester, 'mastery'), '1400');
      expect(double.parse(input(tester, 'drop-rate')), 20);
      expectActionsEnabled(tester, true);
    },
  );

  testWidgets(
    'valid inline edits update FieldGuide without losing search or ranking filters',
    (tester) async {
      final store = newStore(
        profile: GatheringPreparation(
          baseSettings: const BairogCalculatorSettings(
            mastery: 1000,
            gatheringDropRatePercent: 10,
            enabledExpenseItemIds: {},
          ),
          statsConfirmed: true,
        ),
      );
      await open(tester, store, prepare: false);
      await tester.enterText(find.byKey(const ValueKey('spot-search')), 'Wolf');
      await tester.pumpAndSettle();
      final rank = find.byKey(const ValueKey('spot-ranking-caphras'));
      await tester.ensureVisible(rank);
      await tester.tap(rank);
      await tester.pumpAndSettle();
      final guideState = tester.state(find.byType(FieldGuide));
      await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
      await tester.pumpAndSettle();
      await enter(tester, 'mastery', '1800');
      await enter(tester, 'drop-rate', '35');
      expect(guide(tester).bairogSettings.mastery, 1800);
      expect(guide(tester).bairogSettings.gatheringDropRatePercent, 35);
      expect(
        tester.state(find.byType(FieldGuide, skipOffstage: false)),
        same(guideState),
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('spot-search'), skipOffstage: false),
            )
            .controller!
            .text,
        'Wolf',
      );
      expect(
        tester
            .widget<GlassControl>(
              find.byKey(
                const ValueKey('spot-ranking-caphras'),
                skipOffstage: false,
              ),
            )
            .selected,
        isTrue,
      );
    },
  );

  testWidgets(
    'inline base edits and selected buffs add once before and after reload',
    (tester) async {
      final store = newStore(
        profile: GatheringPreparation(
          baseSettings: const BairogCalculatorSettings(
            mastery: 1000,
            gatheringDropRatePercent: 5,
            enabledExpenseItemIds: {},
          ),
          buffIds: {'buff-890', 'buff-yawning-hedgehog'},
          statsConfirmed: true,
        ),
      );
      await open(tester, store);
      expect(input(tester, 'mastery'), '1000');
      expect(panel(tester).effectiveSettings.mastery, 1075);
      expect(panel(tester).effectiveSettings.gatheringDropRatePercent, 15);
      await enter(tester, 'mastery', '1200');
      await enter(tester, 'drop-rate', '7');
      expect(panel(tester).effectiveSettings.mastery, 1275);
      expect(panel(tester).effectiveSettings.gatheringDropRatePercent, 17);
      panel(tester).onToggleBuff(buff('buff-9691'));
      await tester.pumpAndSettle();
      expect(input(tester, 'mastery'), '1200');
      expect(panel(tester).effectiveSettings.mastery, 1300);
      expect(stored(store).baseSettings.mastery, 1200);
      final restored = store.reload();
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, restored);
      expect(input(tester, 'mastery'), '1200');
      expect(panel(tester).effectiveSettings.mastery, 1300);
      expect(panel(tester).effectiveSettings.gatheringDropRatePercent, 17);
    },
  );

  testWidgets(
    'historical inline stats edits preserve recorded buffs pets and the global kit',
    (tester) async {
      final current = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(
          mastery: 2500,
          gatheringDropRatePercent: 90,
        ),
        statsConfirmed: true,
      );
      final historical = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(
          mastery: 1000,
          gatheringDropRatePercent: 20,
          enabledExpenseItemIds: {},
        ),
        buffIds: {'buff-890'},
        petIds: {'hedgehog'},
        statsConfirmed: true,
      );
      final original = GatheringSession(
        id: 'history',
        createdAt: DateTime.utc(2026, 9, 1),
        methodId: 'butcher',
        methodLabel: 'Butchering',
        methodIcon: '',
        spotId: wolves.id,
        spotName: wolves.name,
        durationSeconds: 1800,
        mastery: 1000,
        loot: [LootEntry(id: '7913', name: 'Wolf Meat', overrideTotal: 100)],
        buffs: [buff('buff-890').snapshot()],
        pets: const [
          {
            'id': 'hedgehog',
            'name': 'Historical pet',
            'icon': '',
            'summary': 'Recorded details',
          },
        ],
        buffTotals: {'lifeMastery': 17, 'gatheringItemDropPct': 4},
        catalogDate: 'historical',
        preparationSnapshot: {
          ...historical.snapshot(catalog, methodId: 'butcher'),
          'effectiveSettings': historical.baseSettings
              .copyWith(mastery: 1017, gatheringDropRatePercent: 24)
              .toJson(),
        },
      );
      final store = newStore(profile: current)..sessions.add(original);
      await open(tester, store);
      tester
          .widget<TextButton>(
            find.byKey(
              const ValueKey('edit-session-history'),
              skipOffstage: false,
            ),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
      await tester.pumpAndSettle();
      expect(input(tester, 'mastery'), '1000');
      await enter(tester, 'mastery', '1300');
      await enter(tester, 'drop-rate', '25');
      expect(panel(tester).effectiveSettings.mastery, 1317);
      expect(panel(tester).effectiveSettings.gatheringDropRatePercent, 29);
      tester
          .widget<TextButton>(find.byKey(const ValueKey('record-results')))
          .onPressed!();
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save changes'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      final saved = store.sessions.single;
      expect(saved.mastery, 1300);
      expect(saved.buffTotals, original.buffTotals);
      expect(saved.buffs, original.buffs);
      expect(saved.pets, original.pets);
      expect(
        objectMap(saved.preparationSnapshot!['effectiveSettings'])['mastery'],
        1317,
      );
      expect(stored(store).hasSameValuesAs(current), isTrue);
      expect(input(tester, 'mastery'), '2500');
    },
  );
}
