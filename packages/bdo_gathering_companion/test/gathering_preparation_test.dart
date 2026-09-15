import 'dart:convert';

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/src/domain/gathering_preparation.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async => catalog = await Catalog.load());

  const customized = BairogCalculatorSettings(
    mastery: 1732,
    gatheringDropRatePercent: 42.5,
    minigameMode: BairogMinigameMode.event,
    hedgehogTier: BairogHedgehogTier.tier3,
    agrisEnabled: true,
    enabledExpenseItemIds: {589, 820150, 821144},
    displayMode: BairogDisplayMode.energyDump,
    yourEnergy: 321,
    naturalEnergyRecoveryPerThreeMinutes: 7,
    includeAfuaru: false,
    includeChest: false,
    includeChestX10: true,
    includeFeverTime: false,
    includeEvergreenShard: false,
    showTaxed: false,
    marketNetRate: .7,
    dropTaxed: {1: false, 2: true},
    hiddenDropItemTypeIds: {3, 5},
    customGathersPerHour: {4: 1234},
    customItemPrices: {6: 123.5},
  );

  test(
    'fresh examples are unconfirmed and never select a paid buff or pet',
    () {
      final preparation = GatheringPreparation.fromPreferences(
        {},
        catalog: catalog,
      );
      expect(preparation.statsConfirmed, isFalse);
      expect(preparation.buffIds, isEmpty);
      expect(preparation.petIds, isEmpty);
      expect(preparation.baseSettings.mastery, 2000);
      expect(preparation.baseSettings.gatheringDropRatePercent, 60);
      expect(
        preparation.effectiveSettings(catalog).toJson(),
        const BairogCalculatorSettings(enabledExpenseItemIds: {}).toJson(),
      );
      expect(preparation.baseSettings.enabledExpenseItemIds, isEmpty);
      expect(preparation.hasSameValuesAs(GatheringPreparation()), isTrue);
    },
  );

  test('legacy inputs remain exact, unconfirmed, and are not buffed twice', () {
    final preparation = GatheringPreparation.fromPreferences({
      'gatheringEstimateSetup': customized.toJson(),
      'buffIds': ['buff-890', 'buff-yawning-hedgehog'],
      'petIds': ['hedgehog'],
    }, catalog: catalog);
    expect(preparation.baseSettings.toJson(), customized.toJson());
    expect(
      preparation.effectiveSettings(catalog).toJson(),
      customized.toJson(),
    );
    expect(preparation.statsConfirmed, isFalse);
    expect(
      preparation.buffIds,
      {'buff-820150'},
      reason:
          'Only an already enabled energy-only item is safe to represent during migration.',
    );
    expect(preparation.petIds, isEmpty);
    expect(preparation.baseSettings.hedgehogTier, BairogHedgehogTier.tier3);
  });

  test('explicit preparation wins over legacy preferences and round-trips', () {
    final preparation = GatheringPreparation(
      baseSettings: customized,
      buffIds: {'buff-890'},
      petIds: {'golden-hedgehog'},
      statsConfirmed: true,
    );
    final restored = GatheringPreparation.fromPreferences({
      gatheringPreparationPreferenceKey: jsonDecode(
        jsonEncode(preparation.toJson()),
      ),
      'gatheringEstimateSetup': const BairogCalculatorSettings().toJson(),
    }, catalog: catalog);
    expect(restored.hasSameValuesAs(preparation), isTrue);
    expect(restored.statsConfirmed, isTrue);
  });

  test('effective mastery and drop add catalog totals exactly once', () {
    final preparation = GatheringPreparation(
      baseSettings: customized.copyWith(
        mastery: 1000,
        gatheringDropRatePercent: 15,
      ),
      buffIds: {'buff-9691', 'buff-890', 'buff-yawning-hedgehog', 'buff-45514'},
    );
    final effective = preparation.effectiveSettings(catalog);
    expect(preparation.buffTotals(catalog)['gatheringMastery'], 25);
    expect(preparation.buffTotals(catalog)['lifeMastery'], 75);
    expect(effective.mastery, 1100);
    expect(effective.gatheringDropRatePercent, 37);
    expect(
      effective.toJson(),
      customized.copyWith(mastery: 1100, gatheringDropRatePercent: 37).toJson(),
    );
    expect(
      preparation.baseSettings.mastery,
      1000,
      reason: 'Derivation never writes totals back into the base.',
    );
  });

  test(
    'negative catalog mastery is retained and calculator limits are honored',
    () {
      final reduced = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(mastery: 200),
        buffIds: {'buff-choice-focus-gathering'},
      );
      expect(reduced.buffTotals(catalog)['gatheringMastery'], -500);
      expect(reduced.effectiveSettings(catalog).mastery, 0);
      final capped = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(mastery: 2950),
        buffIds: {'buff-768064'},
      );
      expect(capped.effectiveSettings(catalog).mastery, 3000);
    },
  );

  test(
    'unknown and reference-only selections never contribute stats or expenses',
    () {
      final reference = Buff({
        'id': 'reference',
        'referenceOnly': true,
        'effects': {'lifeMastery': 999, 'gatheringItemDropPct': 999},
      });
      final fixture = Catalog(
        methods: [],
        spots: [],
        buffs: [reference],
        items: [],
        categories: [],
        stats: [],
        presets: [],
        stackingNotes: [],
        reviewedAt: 'test',
      );
      final preparation = GatheringPreparation(
        buffIds: {'reference', 'unknown'},
      );
      expect(preparation.buffTotals(fixture), isEmpty);
      expect(preparation.activeBuffIds(fixture), isEmpty);
      expect(preparation.buffIds, {
        'reference',
        'unknown',
      }, reason: 'Reading does not rewrite saved IDs.');
      final real = GatheringPreparation(
        baseSettings: const BairogCalculatorSettings(enabledExpenseItemIds: {}),
        buffIds: {'buff-589', 'buff-17503'},
      );
      expect(real.effectiveSettings(catalog).enabledExpenseItemIds, isEmpty);
    },
  );

  test(
    'conflicting selections resolve deterministically without mutating catalog',
    () {
      final first = GatheringPreparation(
        buffIds: ['buff-9301', 'buff-9691', 'buff-9216'],
      );
      final reverse = GatheringPreparation(
        buffIds: ['buff-9216', 'buff-9691', 'buff-9301'],
      );
      expect(first.activeBuffIds(catalog).length, 1);
      expect(first.activeBuffIds(catalog), reverse.activeBuffIds(catalog));
      expect(
        first.buffTotals(catalog),
        catalog.sumBuffs(first.activeBuffIds(catalog)),
      );
      expect(first.buffIds.length, 3);
    },
  );

  test(
    'herbal selections and advanced expense checkboxes stay bidirectionally connected',
    () {
      final initial = GatheringPreparation(baseSettings: customized);
      final selected = initial.withBuffIds({
        'buff-821145',
        'buff-890',
      }, catalog);
      expect(selected.baseSettings.enabledExpenseItemIds, {589, 821145});
      expect(selected.effectiveSettings(catalog).enabledExpenseItemIds, {
        589,
        821145,
      });
      expect(selected.baseSettings.naturalEnergyRecoveryPerThreeMinutes, 7);
      expect(
        selected
            .effectiveSettings(catalog)
            .naturalEnergyRecoveryPerThreeMinutes,
        7,
        reason:
            'Mapped recovery must not be added twice as natural regeneration.',
      );
      final removed = selected.withBuffIds({'buff-890'}, catalog);
      expect(removed.effectiveSettings(catalog).enabledExpenseItemIds, {589});
      final advanced = removed.withBaseSettings(
        customized.copyWith(enabledExpenseItemIds: {589, 820150}),
        catalog,
        statsConfirmed: true,
      );
      expect(advanced.buffIds, {'buff-890', 'buff-820150'});
      expect(advanced.statsConfirmed, isTrue);
      expect(
        advanced.baseSettings.toJson(),
        customized.copyWith(enabledExpenseItemIds: {589, 820150}).toJson(),
      );
    },
  );

  test(
    'conflicting royal herbs cannot create two active expense assumptions',
    () {
      final profile = GatheringPreparation().withBaseSettings(
        const BairogCalculatorSettings(enabledExpenseItemIds: {821144, 821145}),
        catalog,
      );
      expect(profile.buffIds.length, 1);
      expect(
        profile.effectiveSettings(catalog).enabledExpenseItemIds.length,
        1,
      );
      expect(
        profile.effectiveSettings(catalog).enabledExpenseItemIds.single,
        int.parse(profile.buffIds.single.substring(5)),
      );
    },
  );

  test(
    'pet selection never invents a tier and removing the last proc pet clears it',
    () {
      final fresh = GatheringPreparation().withPetIds({'hedgehog'});
      expect(
        fresh.effectiveSettings(catalog).hedgehogTier,
        BairogHedgehogTier.none,
      );
      final configured = fresh.copyWith(baseSettings: customized);
      expect(
        configured.withPetIds({'pwudgy-llama'}).baseSettings.hedgehogTier,
        BairogHedgehogTier.tier3,
      );
      expect(
        configured.withPetIds({'bareeds-junaid'}).baseSettings.hedgehogTier,
        BairogHedgehogTier.none,
      );
      final legacy = GatheringPreparation(baseSettings: customized);
      expect(
        legacy.withPetIds({'bareeds-junaid'}).baseSettings.hedgehogTier,
        BairogHedgehogTier.tier3,
      );
      expect(
        configured.effectiveSettings(catalog).gatheringDropRatePercent,
        customized.gatheringDropRatePercent,
      );
    },
  );

  test(
    'profile collections and effective settings cannot be externally mutated',
    () {
      final ids = <String>{'buff-890'};
      final prices = <int, double>{7: 100};
      final preparation = GatheringPreparation(
        baseSettings: BairogCalculatorSettings(customItemPrices: prices),
        buffIds: ids,
      );
      ids.clear();
      prices.clear();
      expect(preparation.buffIds, {'buff-890'});
      expect(preparation.baseSettings.customItemPrices, {7: 100});
      expect(() => preparation.buffIds.clear(), throwsUnsupportedError);
      expect(
        () => preparation.effectiveSettings(catalog).customItemPrices.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => preparation.buffTotals(catalog).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'session preparation snapshot freezes profile, derived values and method',
    () {
      final preparation = GatheringPreparation(
        baseSettings: customized,
        buffIds: {'buff-890'},
        statsConfirmed: true,
      );
      final snapshot = preparation.snapshot(catalog, methodId: 'butcher');
      expect(snapshot['methodId'], 'butcher');
      expect(snapshot['statsConfirmed'], isTrue);
      expect(objectMap(snapshot['effectiveSettings'])['mastery'], 1782);
      expect(
        GatheringPreparation.fromJson(
          objectMap(snapshot['profile']),
        ).hasSameValuesAs(preparation),
        isTrue,
      );
      expect(
        () => (snapshot['profile'] as Map)['statsConfirmed'] = false,
        throwsUnsupportedError,
      );
      expect(
        () => (objectMap(snapshot['profile'])['buffIds'] as List).clear(),
        throwsUnsupportedError,
      );
      final logged = _session(snapshot);
      final reloaded = GatheringSession.fromJson(
        jsonDecode(jsonEncode(logged.toJson())),
      );
      expect(reloaded.preparationSnapshot, snapshot);
      expect(reloaded.toJson(), logged.toJson());
      expect(
        () =>
            (reloaded.preparationSnapshot!['effectiveSettings']
                    as Map)['mastery'] =
                999,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'old sessions retain their canonical JSON without a preparation key',
    () {
      final old = _session(null).toJson();
      final restored = GatheringSession.fromJson(jsonDecode(jsonEncode(old)));
      expect(restored.preparationSnapshot, isNull);
      expect(restored.toJson().containsKey('preparationSnapshot'), isFalse);
      expect(restored.toJson(), old);
    },
  );

  test('damaged preparation objects and non-JSON snapshots are rejected', () {
    expect(
      () => GatheringPreparation.fromJson({'baseSettings': []}),
      throwsFormatException,
    );
    expect(
      () => GatheringPreparation.fromJson({
        'baseSettings': {},
        'buffIds': [1],
      }),
      throwsFormatException,
    );
    expect(
      () => GatheringPreparation.fromPreferences({
        gatheringPreparationPreferenceKey: 'bad',
      }),
      throwsFormatException,
    );
    expect(() => _session({'invalid': double.nan}), throwsFormatException);
    expect(
      () => GatheringSession.fromJson({
        ..._session(null).toJson(),
        'preparationSnapshot': [],
      }),
      throwsFormatException,
    );
  });
}

GatheringSession _session(Map<String, dynamic>? snapshot) => GatheringSession(
  id: 'record',
  createdAt: DateTime.utc(2026, 9, 7),
  methodId: 'butcher',
  methodLabel: 'Butchering',
  methodIcon: '',
  spotId: 'wolves',
  spotName: 'Wolves',
  durationSeconds: 3600,
  loot: [],
  buffs: [],
  buffTotals: {},
  catalogDate: '2026-09-07',
  preparationSnapshot: snapshot,
);
