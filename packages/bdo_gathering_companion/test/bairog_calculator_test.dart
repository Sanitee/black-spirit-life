import 'dart:io';

import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BairogCalculatorData data;
  late BairogCalculator calculator;

  setUpAll(() {
    final source = File(
      'assets/data/bairog_calculator.json',
    ).readAsStringSync();
    data = BairogCalculatorData.fromJsonString(source);
    expect(data.gatheringTypes, hasLength(12));
    expect(data.gatheringItemTypes, hasLength(118));
    expect(data.dropRates, hasLength(286));
    expect(data.rotations, hasLength(20));
    calculator = BairogCalculator(data);
  });

  test('mastery lookup uses the exact clamped 50-point site tiers', () {
    expect(bairogMasteryBonuses, hasLength(61));
    expect(bairogMasteryTier(-2), 0);
    expect(bairogMasteryTier(49), 0);
    expect(bairogMasteryTier(50), 50);
    expect(bairogMasteryTier(2049), 2000);
    expect(bairogMasteryTier(4000), 3000);
    final mastery = bairogBonusesForMastery(2000);
    expect(mastery.commonRatePercent, 80);
    expect(mastery.commonAmountPercent, 400);
    expect(mastery.specialRatePercent, 200);
    expect(mastery.specialAmountPercent, 100);
    expect(mastery.rareRatePercent, 249.85);
    expect(mastery.rareAmountPercent, 85);
  });

  test('saved calculator setup is validated and round-trips stably', () {
    final settings = BairogCalculatorSettings.fromJson(<String, dynamic>{
      'mastery': 9000,
      'additionalDroprateBonus': -4,
      'minigameMode': 'event',
      'hedgehogTier': 4,
      'agrisEnabled': true,
      'expensesEnabled': <String, dynamic>{
        '589': true,
        '821144': 'true',
        '999': true,
      },
      'displayMode': 'energy_dump',
      'yourEnergy': -100,
      'energyRecovery': '9',
      'includeAfuaru': false,
      'includeChest': true,
      'includeChestX10': true,
      'includeFeverTime': false,
      'includeWonCrystal': false,
      'showTaxed': true,
      'marketNetRate': 2,
      'dropTaxed': <String, dynamic>{'16': false, 'bad': true},
      'hiddenDropIds': <String, dynamic>{'27': true, '28': false},
      'customGathersPerHour': <String, dynamic>{'17': '999', '39': -1},
      'customItemPrices': <String, dynamic>{'16': '123.5', '17': -1},
    });

    expect(settings.mastery, 3000);
    expect(settings.gatheringDropRatePercent, 0);
    expect(settings.yourEnergy, 0);
    expect(settings.marketNetRate, 1);
    expect(settings.enabledExpenseItemIds, {589, 821144});
    expect(settings.hiddenDropItemTypeIds, {27});
    expect(settings.customGathersPerHour, {17: 999});
    expect(settings.customItemPrices, {16: 123.5});
    expect(settings.includeEvergreenShard, isFalse);
    expect(settings.toJson()['schemaVersion'], 2);
    expect(settings.toJson()['includeEvergreenShard'], isFalse);
    expect(settings.toJson(), isNot(contains('includeWonCrystal')));
    final restored = BairogCalculatorSettings.fromJsonString(
      settings.toJsonString(),
    );
    expect(restored.toJson(), settings.toJson());
  });

  group('raw Bairog route fixtures', () {
    const setupA = BairogCalculatorSettings();
    const setupB = BairogCalculatorSettings(
      mastery: 1500,
      gatheringDropRatePercent: 0,
      minigameMode: BairogMinigameMode.none,
      hedgehogTier: BairogHedgehogTier.tier4,
      enabledExpenseItemIds: <int>{},
      includeAfuaru: false,
      includeChest: false,
      includeFeverTime: false,
      includeEvergreenShard: false,
    );
    const setupC = BairogCalculatorSettings(
      mastery: 2500,
      gatheringDropRatePercent: 100,
      minigameMode: BairogMinigameMode.event,
      hedgehogTier: BairogHedgehogTier.tier4,
      agrisEnabled: true,
      includeChestX10: true,
    );

    test('A: 2000 mastery, 60 GDR, normal minigame', () {
      _expectRoute(
        calculator.projectRoute(routeId: 17, settings: setupA),
        <int, double>{
          7913: 20227.5,
          821351: 115.9678787401152,
          4998: 283.66668351266696,
          721002: 101.7035824499341,
          721003: 9.528502955327054,
          4999: 588.9251894366553,
          5651: 968.7402077270692,
          5960: 116.55509972935634,
          766107: 6.972792879592757,
          50810: 6.335044017749326,
          821469: 0.31780734632985397,
        },
      );
      _expectRoute(
        calculator.projectRoute(routeId: 39, settings: setupA),
        <int, double>{
          5439: 22663.5,
          821350: 108.51258331720553,
          4998: 232.33499969721245,
          721002: 185.94142038396845,
          721003: 17.447672100272744,
          4999: 211.39951488881456,
          5651: 1462.7126015412339,
          5960: 144.1277452364812,
          766107: 5.908028916329016,
          50810: 3.2807001451528457,
          821469: 0.3560809192211912,
        },
      );
    });

    test('B: 1500 mastery, T4 pet and no optional sources', () {
      _expectRoute(
        calculator.projectRoute(routeId: 17, settings: setupB),
        <int, double>{
          7913: 11504.844000000001,
          821351: 48.337168313109785,
          4998: 88.09372740619382,
          721002: 35.7692095383572,
          721003: 3.971624350875407,
          4999: 245.47293884218033,
          5651: 401.610518423786,
          5960: 48.32023452094698,
          766107: 2.8907099559801637,
          50810: 2.626318482408459,
        },
      );
      _expectRoute(
        calculator.projectRoute(routeId: 39, settings: setupB),
        <int, double>{
          5439: 12890.3736,
          821350: 45.22968826263194,
          4998: 66.95591610663553,
          721002: 70.08328183777243,
          721003: 7.272453994548213,
          4999: 88.11451967134808,
          5651: 606.3965978951954,
          5960: 59.75102305238729,
          766107: 2.4492908800767994,
          50810: 1.3600794883689107,
        },
      );
    });

    test('C: 2500 mastery, event minigame, Agris and all sources', () {
      final wolves = calculator.projectRoute(routeId: 17, settings: setupC);
      _expectRoute(wolves, <int, double>{
        7913: 38118.97329999999,
        821351: 193.03923936718598,
        4998: 495.7303676398769,
        721002: 182.11168954515523,
        721003: 15.861072762453215,
        4999: 980.3203425648425,
        5651: 1632.3843151281485,
        5960: 196.40220889851065,
        766107: 11.749566745031062,
        50810: 10.674922345262999,
        821469: 0.3994065952569243,
      });
      final behr = calculator.projectRoute(routeId: 39, settings: setupC);
      _expectRoute(behr, <int, double>{
        5439: 42709.645353333326,
        821350: 180.62921192397195,
        4998: 417.0072027974467,
        721002: 323.87686206120367,
        721003: 29.043260837016994,
        4999: 351.89400720332895,
        5651: 2464.7568968964565,
        5960: 242.86374078642825,
        766107: 9.955376745398976,
        50810: 5.528172999189639,
        821469: 0.44750717447066146,
      });

      expect(wolves.sourceBenchmark?.sourceSessionCount, 8);
      expect(wolves.sourceBenchmark?.sourceHours, 10);
      expect(wolves.energy.energyUsePerHour, closeTo(1515.9, 1e-10));
      expect(wolves.energy.netEnergyDrainPerHour, closeTo(1180.9, 1e-10));
      expect(wolves.energy.sessionHours, closeTo(0.423405876873571, 1e-12));
      expect(behr.energy.energyUsePerHour, closeTo(1698.46, 1e-10));
      expect(behr.energy.netEnergyDrainPerHour, closeTo(1363.46, 1e-10));
      expect(behr.energy.sessionHours, closeTo(0.366714095022956, 1e-12));
    });

    test('Evergreen toggle removes only Evergreen Shard value', () {
      const prices = <int, double>{
        821469: 1000000,
        752023: 2000000,
        735353: 3000000,
        735367: 4000000,
        735351: 5000000,
        735352: 6000000,
        735356: 7000000,
      };
      const includedSettings = BairogCalculatorSettings(
        enabledExpenseItemIds: <int>{},
        includeAfuaru: false,
        includeChest: false,
        includeFeverTime: false,
        showTaxed: false,
      );
      const excludedSettings = BairogCalculatorSettings(
        enabledExpenseItemIds: <int>{},
        includeAfuaru: false,
        includeChest: false,
        includeFeverTime: false,
        includeEvergreenShard: false,
        showTaxed: false,
      );
      final included = calculator.projectRoute(
        routeId: 17,
        settings: includedSettings,
        marketPricesByBdoItemId: prices,
      );
      final excluded = calculator.projectRoute(
        routeId: 17,
        settings: excludedSettings,
        marketPricesByBdoItemId: prices,
      );
      final shard = included.itemByBdoId(bairogEvergreenShardItemId)!;
      final mass = included.itemByBdoId(752023)!;

      expect(mass.itemType.globalDrop, isTrue);
      expect(mass.totalPerHour, greaterThan(0));
      expect(
        included.totalSilverPerHour - excluded.totalSilverPerHour,
        closeTo(shard.totalPerHour * prices[bairogEvergreenShardItemId]!, 1e-6),
      );
    });

    test(
      'mixed primary ratios price the same split shown in projected loot',
      () {
        final hiddenNonPrimary = <int>{
          for (final itemType in data.gatheringItemTypes)
            if (!itemType.isPrimary) itemType.id,
        };
        const tshiraPrices = <int, double>{7922: 30000, 7924: 22000};
        final tshira = calculator.projectRoute(
          routeId: 48,
          settings: BairogCalculatorSettings(
            enabledExpenseItemIds: const <int>{},
            includeAfuaru: false,
            includeChest: false,
            includeFeverTime: false,
            includeEvergreenShard: false,
            showTaxed: false,
            hiddenDropItemTypeIds: hiddenNonPrimary,
          ),
          marketPricesByBdoItemId: tshiraPrices,
        );
        final expectedTshiraSilver =
            tshira.bdoItemAmountsPerHour[7922]! * tshiraPrices[7922]! +
            tshira.bdoItemAmountsPerHour[7924]! * tshiraPrices[7924]!;
        // The live BDO Workshop branch scales primary drop amount by these
        // composition shares for a one-gathering-type route. At 2,000 Mastery
        // with the normal minigame, Butchering's 3-item primary roll becomes
        // one 21.75-item stream per gather, not one full stream per meat.
        const expectedPrimaryPerHour = 749 * 3 * 5 * 1.45;
        const expectedSnakePerHour = expectedPrimaryPerHour * .6669;
        const expectedScorpionPerHour = expectedPrimaryPerHour * .3331;
        const expectedSiteSilver =
            expectedSnakePerHour * 30000 + expectedScorpionPerHour * 22000;
        const rejectedDoubleFullStreamSilver =
            expectedPrimaryPerHour * 30000 + expectedPrimaryPerHour * 22000;

        expect(tshira.effectiveGathersPerHour, 749);
        expect(
          tshira.bdoItemAmountsPerHour[7922],
          closeTo(expectedSnakePerHour, 1e-6),
        );
        expect(
          tshira.bdoItemAmountsPerHour[7924],
          closeTo(expectedScorpionPerHour, 1e-6),
        );
        expect(expectedTshiraSilver, closeTo(expectedSiteSilver, .01));
        expect(tshira.baseSilverPerHour, closeTo(expectedTshiraSilver, .01));
        expect(tshira.totalSilverPerHour, closeTo(expectedTshiraSilver, .01));
        expect(
          tshira.totalSilverPerHour,
          lessThan(rejectedDoubleFullStreamSilver),
          reason:
              'Snake and Scorpion Meat must not each receive the complete '
              'primary stream.',
        );

        final mixedRoutes = data.rotations
            .where((route) => (route.primaryItemRatios?.length ?? 0) > 1)
            .toList(growable: false);
        expect(
          mixedRoutes.map((route) => route.id),
          containsAll(<int>[35, 40, 48]),
        );
        for (final route in mixedRoutes) {
          final primaryTypes = <BairogGatheringItemType>[
            for (final itemTypeId in route.primaryItemRatios!.keys)
              data.gatheringItemTypesById[itemTypeId]!,
          ];
          final prices = <int, double>{
            for (final itemType in primaryTypes)
              itemType.item.id: itemType.vendorUnitPrice ?? 1000,
          };
          final projection = calculator.projectRoute(
            routeId: route.id,
            settings: BairogCalculatorSettings(
              enabledExpenseItemIds: const <int>{},
              includeAfuaru: false,
              includeChest: false,
              includeFeverTime: false,
              includeEvergreenShard: false,
              showTaxed: false,
              hiddenDropItemTypeIds: hiddenNonPrimary,
            ),
            marketPricesByBdoItemId: prices,
          );
          final expectedSilver = projection.items
              .where((item) => item.itemType.isPrimary && item.totalPerHour > 0)
              .fold<double>(
                0,
                (total, item) =>
                    total +
                    item.totalPerHour *
                        (item.itemType.vendorUnitPrice ??
                            prices[item.itemType.item.id]!),
              );

          expect(
            route.primaryItemRatios!.values.fold<double>(
              0,
              (total, ratio) => total + ratio,
            ),
            closeTo(1, 1e-9),
            reason: '${route.name} primary shares must form one yield stream',
          );
          expect(
            projection.totalSilverPerHour,
            closeTo(expectedSilver, .01),
            reason: '${route.name} must not price each primary at 100%',
          );
        }
      },
    );

    test('energy estimate uses the Professional 3+ no-consumption cap', () {
      BairogRouteProjection projection(BairogMinigameMode minigameMode) =>
          calculator.projectRoute(
            routeId: 17,
            settings: BairogCalculatorSettings(
              minigameMode: minigameMode,
              enabledExpenseItemIds: const <int>{},
              customGathersPerHour: const <int, int>{17: 100},
            ),
          );

      expect(
        projection(BairogMinigameMode.none).energy.energyUsePerHour,
        closeTo(70, 1e-10),
      );
      expect(
        projection(BairogMinigameMode.normal).energy.energyUsePerHour,
        closeTo(116.5, 1e-10),
      );
      expect(
        projection(BairogMinigameMode.event).energy.energyUsePerHour,
        closeTo(163, 1e-10),
      );
    });
  });
}

void _expectRoute(BairogRouteProjection projection, Map<int, double> expected) {
  for (final entry in expected.entries) {
    expect(
      projection.bdoItemAmountsPerHour[entry.key],
      closeTo(entry.value, 1e-9),
      reason: '${projection.route.name}: BDO item ${entry.key}',
    );
  }
}
