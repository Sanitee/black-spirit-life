import 'dart:convert';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('node-network preferences round-trip normalized user choices', () {
    final preferences = BdoNodeNetworkPreferences(
      contributionPointBudget: 275,
      desiredResourceNodeCounts: const <String, int>{
        ' ash-timber ': 2,
        'unused': 0,
      },
      currentNodeIds: const <String>{'20', ' 3 ', ''},
      currentOwnedHouseIds: const <String>{'heidel-1-2', '  heidel-3-1  ', ''},
      currentHouseUsageTypeIds: const <String, int>{
        'heidel-1-2': 2,
        ' heidel-3-1 ': 3,
        'not-owned': 1,
        'negative': -1,
      },
      rootNodeIds: const <String>{'100', '2'},
      onlineHoursPerDay: 12.5,
      resourceAvailabilityPercent: 73,
      useObservedTradeVolume: true,
      showCitiesAndTowns: false,
      showGatewayHubs: false,
      showAllMapNodes: false,
      showAllNodeConnections: false,
      showWorkerOutputIcons: false,
      mapVisualStyle: BdoMapVisualStyle.standard,
      townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
        ' 100 ': BdoTownWorkerCapacity(
          availableWorkerCount: 3,
          freeLodgingSlotCount: 1,
        ),
        '2': BdoTownWorkerCapacity(
          availableWorkerCount: 0,
          freeLodgingSlotCount: 2,
        ),
      },
    );

    final restored = BdoNodeNetworkPreferences.fromJson(preferences.toJson());

    expect(restored.sameValuesAs(preferences), isTrue);
    expect(restored.desiredResourceNodeCounts, const <String, int>{
      'ash-timber': 2,
    });
    expect(restored.currentNodeIds, const <String>{'3', '20'});
    expect(restored.currentOwnedHouseIds, const <String>{
      'heidel-1-2',
      'heidel-3-1',
    });
    expect(restored.toJson()['currentOwnedHouseIds'], const <String>[
      'heidel-1-2',
      'heidel-3-1',
    ]);
    expect(restored.currentHouseUsageTypeIds, const <String, int>{
      'heidel-1-2': 2,
      'heidel-3-1': 3,
    });
    expect(restored.toJson()['rootNodeIds'], const <String>['2', '100']);
    expect(restored.onlineHoursPerDay, 12.5);
    expect(restored.resourceAvailabilityPercent, 73);
    expect(restored.useObservedTradeVolume, isTrue);
    expect(restored.showCitiesAndTowns, isFalse);
    expect(restored.showGatewayHubs, isFalse);
    expect(restored.showAllMapNodes, isFalse);
    expect(restored.showAllNodeConnections, isFalse);
    expect(restored.showWorkerOutputIcons, isFalse);
    expect(restored.mapVisualStyle, BdoMapVisualStyle.standard);
    expect(restored.toJson()['showCitiesAndTowns'], isFalse);
    expect(restored.toJson()['showGatewayHubs'], isFalse);
    expect(restored.toJson()['showAllMapNodes'], isFalse);
    expect(restored.toJson()['showAllNodeConnections'], isFalse);
    expect(restored.toJson()['showWorkerOutputIcons'], isFalse);
    expect(restored.toJson()['mapVisualStyle'], 'standard');
    expect(restored.townWorkerCapacitiesByNodeId.keys, const <String>{
      '2',
      '100',
    });
    expect(
      restored.townWorkerCapacitiesByNodeId['100']!.availableWorkerCount,
      3,
    );
    expect(restored.townWorkerCapacitiesByNodeId['2']!.freeLodgingSlotCount, 2);
    expect(restored.toJson()['townWorkerCapacitiesByNodeId'], {
      '2': {'availableWorkerCount': 0, 'freeLodgingSlotCount': 2},
      '100': {'availableWorkerCount': 3, 'freeLodgingSlotCount': 1},
    });
  });

  test(
    'new profiles enable every display option while explicit off choices persist',
    () {
      final defaults = BdoNodeNetworkPreferences();
      final defaultJson = defaults.toJson();

      expect(defaults.isDefault, isTrue);
      expect(defaults.showCitiesAndTowns, isTrue);
      expect(defaults.showGatewayHubs, isTrue);
      expect(defaults.showAllMapNodes, isTrue);
      expect(defaults.showAllNodeConnections, isTrue);
      expect(defaults.showWorkerOutputIcons, isTrue);
      expect(defaults.mapVisualStyle, BdoMapVisualStyle.vivid);
      expect(defaultJson.containsKey('showCitiesAndTowns'), isFalse);
      expect(defaultJson.containsKey('showGatewayHubs'), isFalse);
      expect(defaultJson.containsKey('showAllMapNodes'), isFalse);
      expect(defaultJson.containsKey('showAllNodeConnections'), isFalse);
      expect(defaultJson.containsKey('showWorkerOutputIcons'), isFalse);
      expect(defaultJson.containsKey('mapVisualStyle'), isFalse);

      final legacyWithoutDisplayKeys = BdoNodeNetworkPreferences.fromJson(
        const <String, Object?>{
          'schemaVersion': 9,
          'contributionPointBudget': 275,
        },
      );
      expect(legacyWithoutDisplayKeys.showCitiesAndTowns, isTrue);
      expect(legacyWithoutDisplayKeys.showGatewayHubs, isTrue);
      expect(legacyWithoutDisplayKeys.showAllMapNodes, isTrue);
      expect(legacyWithoutDisplayKeys.showAllNodeConnections, isTrue);
      expect(legacyWithoutDisplayKeys.showWorkerOutputIcons, isTrue);
      expect(legacyWithoutDisplayKeys.mapVisualStyle, BdoMapVisualStyle.vivid);

      final explicitOff =
          BdoNodeNetworkPreferences.fromJson(const <String, Object?>{
            'schemaVersion': 10,
            'showCitiesAndTowns': false,
            'showGatewayHubs': false,
            'showAllMapNodes': false,
            'showAllNodeConnections': false,
            'showWorkerOutputIcons': false,
            'mapVisualStyle': 'standard',
          });
      final explicitJson = explicitOff.toJson();
      expect(explicitOff.isDefault, isFalse);
      expect(explicitOff.showCitiesAndTowns, isFalse);
      expect(explicitOff.showGatewayHubs, isFalse);
      expect(explicitOff.showAllMapNodes, isFalse);
      expect(explicitOff.showAllNodeConnections, isFalse);
      expect(explicitOff.showWorkerOutputIcons, isFalse);
      expect(explicitOff.mapVisualStyle, BdoMapVisualStyle.standard);
      expect(explicitJson['showCitiesAndTowns'], isFalse);
      expect(explicitJson['showGatewayHubs'], isFalse);
      expect(explicitJson['showAllMapNodes'], isFalse);
      expect(explicitJson['showAllNodeConnections'], isFalse);
      expect(explicitJson['showWorkerOutputIcons'], isFalse);
      expect(explicitJson['mapVisualStyle'], 'standard');
      expect(
        BdoNodeNetworkPreferences.fromJson(
          explicitJson,
        ).sameValuesAs(explicitOff),
        isTrue,
      );
    },
  );

  test('schema v6 preserves an older unsplit bonus total', () {
    final preferences = BdoNodeNetworkPreferences(
      townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
        '100': BdoTownWorkerCapacity(
          availableWorkerCount: 4,
          freeLodgingSlotCount: 6,
          hiredWorkerCount: 4,
          bonusLodgingSlotCount: 8,
        ),
      },
    );

    final json = preferences.toJson();
    final restored = BdoNodeNetworkPreferences.fromJson(json);

    expect(json['schemaVersion'], 10);
    expect(json['townWorkerCapacitiesByNodeId'], {
      '100': {
        'availableWorkerCount': 4,
        'freeLodgingSlotCount': 6,
        'hiredWorkerCount': 4,
        'bonusLodgingSlotCount': 8,
      },
    });
    expect(restored.sameValuesAs(preferences), isTrue);
    expect(restored.townWorkerCapacitiesByNodeId['100']!.hiredWorkerCount, 4);
    expect(
      restored.townWorkerCapacitiesByNodeId['100']!.bonusLodgingSlotCount,
      8,
    );
    expect(
      restored.townWorkerCapacitiesByNodeId['100']!.hasBonusLodgingBreakdown,
      isFalse,
    );
    expect(
      restored
          .townWorkerCapacitiesByNodeId['100']!
          .effectiveBonusLodgingSlotCount,
      8,
    );
  });

  test('schema v5 bonus migrates without guessing its source split', () {
    final restored = BdoNodeNetworkPreferences.fromJson(<String, Object?>{
      'schemaVersion': 5,
      'townWorkerCapacitiesByNodeId': <String, Object?>{
        '601': <String, Object?>{
          'availableWorkerCount': 4,
          'freeLodgingSlotCount': 6,
          'hiredWorkerCount': 4,
          'bonusLodgingSlotCount': 8,
        },
      },
    });
    final capacity = restored.townWorkerCapacitiesByNodeId['601']!;

    expect(capacity.bonusLodgingSlotCount, 8);
    expect(capacity.hasBonusLodgingBreakdown, isFalse);
    expect(capacity.pearlLodgingPurchasedCount, isNull);
    expect(capacity.loyaltyLodgingPurchasedCount, isNull);
    expect(capacity.otherBonusLodgingSlotCount, isNull);
    expect(capacity.effectiveBonusLodgingSlotCount, 8);
  });

  test('schema v6 round-trips Pearl Loyalty and Other bonus sources', () {
    final preferences = BdoNodeNetworkPreferences(
      townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
        '601': BdoTownWorkerCapacity(
          availableWorkerCount: 4,
          freeLodgingSlotCount: 6,
          hiredWorkerCount: 4,
          bonusLodgingSlotCount: 8,
          pearlLodgingPurchasedCount: 3,
          loyaltyLodgingPurchasedCount: 1,
          otherBonusLodgingSlotCount: 4,
        ),
      },
    );

    final json = preferences.toJson();
    final restored = BdoNodeNetworkPreferences.fromJson(json);
    final capacity = restored.townWorkerCapacitiesByNodeId['601']!;

    expect(json['schemaVersion'], 10);
    expect(json['townWorkerCapacitiesByNodeId'], {
      '601': {
        'availableWorkerCount': 4,
        'freeLodgingSlotCount': 6,
        'hiredWorkerCount': 4,
        'bonusLodgingSlotCount': 8,
        'pearlLodgingPurchasedCount': 3,
        'loyaltyLodgingPurchasedCount': 1,
        'otherBonusLodgingSlotCount': 4,
      },
    });
    expect(restored.sameValuesAs(preferences), isTrue);
    expect(capacity.hasBonusLodgingBreakdown, isTrue);
    expect(capacity.pearlLodgingPurchasedCount, 3);
    expect(capacity.loyaltyLodgingPurchasedCount, 1);
    expect(capacity.otherBonusLodgingSlotCount, 4);
    expect(capacity.effectiveBonusLodgingSlotCount, 8);
  });

  test('legacy town capacity retains its exact persisted meaning', () {
    final restored = BdoNodeNetworkPreferences.fromJson(<String, Object?>{
      'schemaVersion': 4,
      'townWorkerCapacitiesByNodeId': <String, Object?>{
        '100': <String, Object?>{
          'availableWorkerCount': 3,
          'freeLodgingSlotCount': 2,
        },
      },
    });
    final capacity = restored.townWorkerCapacitiesByNodeId['100']!;

    expect(capacity.usesKnownTownLodging, isFalse);
    expect(capacity.hiredWorkerCount, isNull);
    expect(capacity.bonusLodgingSlotCount, isNull);
    expect(
      capacity.resolveForKnownTownLodging(
        baseWorkerSlotCount: 1,
        activeOwnedLodgingSlotCount: 20,
      ),
      same(capacity),
    );
    expect(restored.toJson()['townWorkerCapacitiesByNodeId'], {
      '100': {'availableWorkerCount': 3, 'freeLodgingSlotCount': 2},
    });
  });

  test('schema v1 data loads safe worker-economics defaults', () {
    final restored = BdoNodeNetworkPreferences.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'contributionPointBudget': 'not a number',
      'desiredResourceNodeCounts': <String, Object?>{'ash': '2', 'invalid': -1},
    });

    expect(
      restored.contributionPointBudget,
      BdoNodeNetworkPreferences.defaultContributionPointBudget,
    );
    expect(restored.desiredResourceNodeCounts, const <String, int>{'ash': 2});
    expect(restored.rootNodeIds, isNull);
    expect(
      restored.onlineHoursPerDay,
      BdoNodeNetworkPreferences.defaultOnlineHoursPerDay,
    );
    expect(
      restored.resourceAvailabilityPercent,
      BdoNodeNetworkPreferences.defaultResourceAvailabilityPercent,
    );
    expect(restored.useObservedTradeVolume, isFalse);
    expect(restored.showCitiesAndTowns, isTrue);
    expect(restored.showGatewayHubs, isTrue);
    expect(restored.showAllMapNodes, isTrue);
    expect(restored.showAllNodeConnections, isTrue);
    expect(restored.showWorkerOutputIcons, isTrue);
    expect(restored.mapVisualStyle, BdoMapVisualStyle.vivid);
    expect(restored.townWorkerCapacitiesByNodeId, isEmpty);
    expect(restored.currentOwnedHouseIds, isEmpty);
    expect(restored.currentHouseUsageTypeIds, isEmpty);
  });

  test('explicitly empty roots remain explicit', () {
    final restored = BdoNodeNetworkPreferences.fromJson(<String, Object?>{
      'rootNodeIds': const <String>[],
    });

    expect(restored.rootNodeIds, isEmpty);
    expect(restored.copyWith(useDefaultRootNodes: true).rootNodeIds, isNull);
  });

  test('invalid estimate settings and capacity counts normalize safely', () {
    final fromJson = BdoNodeNetworkPreferences.fromJson(<String, Object?>{
      'onlineHoursPerDay': double.nan,
      'resourceAvailabilityPercent': 101,
      'useObservedTradeVolume': 'yes',
      'showCitiesAndTowns': 'no',
      'showGatewayHubs': 0,
      'showAllMapNodes': null,
      'showAllNodeConnections': 'false',
      'showWorkerOutputIcons': 1,
      'townWorkerCapacitiesByNodeId': <String, Object?>{
        ' 100 ': <String, Object?>{
          'availableWorkerCount': -2,
          'freeLodgingSlotCount': '3',
          'hiredWorkerCount': -5,
          'bonusLodgingSlotCount': '8',
        },
        '200': <String, Object?>{
          'availableWorkerCount': 1.5,
          'freeLodgingSlotCount': double.infinity,
        },
        '': <String, Object?>{
          'availableWorkerCount': 9,
          'freeLodgingSlotCount': 9,
        },
        'not-an-object': 4,
      },
    });

    expect(
      fromJson.onlineHoursPerDay,
      BdoNodeNetworkPreferences.defaultOnlineHoursPerDay,
    );
    expect(
      fromJson.resourceAvailabilityPercent,
      BdoNodeNetworkPreferences.defaultResourceAvailabilityPercent,
    );
    expect(fromJson.useObservedTradeVolume, isFalse);
    expect(fromJson.showCitiesAndTowns, isTrue);
    expect(fromJson.showGatewayHubs, isTrue);
    expect(fromJson.showAllMapNodes, isTrue);
    expect(fromJson.showAllNodeConnections, isTrue);
    expect(fromJson.showWorkerOutputIcons, isTrue);
    expect(fromJson.townWorkerCapacitiesByNodeId.keys, const <String>{
      '100',
      '200',
    });
    expect(
      fromJson.townWorkerCapacitiesByNodeId['100']!.availableWorkerCount,
      0,
    );
    expect(
      fromJson.townWorkerCapacitiesByNodeId['100']!.freeLodgingSlotCount,
      3,
    );
    expect(fromJson.townWorkerCapacitiesByNodeId['100']!.hiredWorkerCount, 0);
    expect(
      fromJson.townWorkerCapacitiesByNodeId['100']!.bonusLodgingSlotCount,
      8,
    );
    expect(
      fromJson.townWorkerCapacitiesByNodeId['200']!.availableWorkerCount,
      0,
    );
    expect(
      fromJson.townWorkerCapacitiesByNodeId['200']!.freeLodgingSlotCount,
      0,
    );

    final constructed = BdoNodeNetworkPreferences(
      onlineHoursPerDay: -1,
      resourceAvailabilityPercent: double.infinity,
      townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
        ' town ': BdoTownWorkerCapacity(
          availableWorkerCount: -3,
          freeLodgingSlotCount: -4,
          hiredWorkerCount: -5,
          bonusLodgingSlotCount: -6,
        ),
      },
    );
    expect(
      constructed.onlineHoursPerDay,
      BdoNodeNetworkPreferences.defaultOnlineHoursPerDay,
    );
    expect(
      constructed.resourceAvailabilityPercent,
      BdoNodeNetworkPreferences.defaultResourceAvailabilityPercent,
    );
    expect(
      constructed.townWorkerCapacitiesByNodeId['town']!.availableWorkerCount,
      0,
    );
    expect(
      constructed.townWorkerCapacitiesByNodeId['town']!.freeLodgingSlotCount,
      0,
    );
    expect(
      constructed.townWorkerCapacitiesByNodeId['town']!.hiredWorkerCount,
      0,
    );
    expect(
      constructed.townWorkerCapacitiesByNodeId['town']!.bonusLodgingSlotCount,
      0,
    );
  });

  test('zero availability is valid and copyWith preserves new settings', () {
    final original = BdoNodeNetworkPreferences(
      onlineHoursPerDay: 24,
      resourceAvailabilityPercent: 0,
      useObservedTradeVolume: true,
      mapVisualStyle: BdoMapVisualStyle.vivid,
      showCitiesAndTowns: false,
      showGatewayHubs: false,
      showAllMapNodes: false,
      showAllNodeConnections: false,
      showWorkerOutputIcons: false,
      currentOwnedHouseIds: const <String>{'velia-2-1'},
      currentHouseUsageTypeIds: const <String, int>{'velia-2-1': 1},
      townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
        '10': BdoTownWorkerCapacity(
          availableWorkerCount: 2,
          freeLodgingSlotCount: 1,
        ),
      },
    );

    final changed = original.copyWith(contributionPointBudget: 250);
    expect(changed.onlineHoursPerDay, 24);
    expect(changed.resourceAvailabilityPercent, 0);
    expect(changed.useObservedTradeVolume, isTrue);
    expect(changed.mapVisualStyle, BdoMapVisualStyle.vivid);
    expect(changed.showCitiesAndTowns, isFalse);
    expect(changed.showGatewayHubs, isFalse);
    expect(changed.showAllMapNodes, isFalse);
    expect(changed.showAllNodeConnections, isFalse);
    expect(changed.showWorkerOutputIcons, isFalse);
    expect(changed.currentOwnedHouseIds, const <String>{'velia-2-1'});
    expect(changed.currentHouseUsageTypeIds, const <String, int>{
      'velia-2-1': 1,
    });
    expect(changed.townWorkerCapacitiesByNodeId['10']!.availableWorkerCount, 2);
    expect(
      changed
          .copyWith(
            townWorkerCapacitiesByNodeId:
                const <String, BdoTownWorkerCapacity>{},
          )
          .townWorkerCapacitiesByNodeId,
      isEmpty,
    );
    expect(
      changed
          .copyWith(currentOwnedHouseIds: const <String>{})
          .currentOwnedHouseIds,
      isEmpty,
    );
    expect(
      changed
          .copyWith(currentOwnedHouseIds: const <String>{})
          .currentHouseUsageTypeIds,
      isEmpty,
    );
    expect(
      changed
          .copyWith(mapVisualStyle: BdoMapVisualStyle.standard)
          .mapVisualStyle,
      BdoMapVisualStyle.standard,
    );
  });

  test('unknown persisted map treatment falls back conservatively', () {
    final restored = BdoNodeNetworkPreferences.fromJson(<String, Object?>{
      'mapVisualStyle': 'cinematic',
    });

    expect(restored.mapVisualStyle, BdoMapVisualStyle.standard);
  });

  test('serialization is deterministic across caller map order', () {
    BdoNodeNetworkPreferences preferences(bool reverse) =>
        BdoNodeNetworkPreferences(
          desiredResourceNodeCounts: reverse
              ? const <String, int>{'zinc': 2, 'ash': 1}
              : const <String, int>{'ash': 1, 'zinc': 2},
          currentNodeIds: reverse
              ? const <String>{'20', '3'}
              : const <String>{'3', '20'},
          townWorkerCapacitiesByNodeId: reverse
              ? const <String, BdoTownWorkerCapacity>{
                  '100': BdoTownWorkerCapacity(
                    availableWorkerCount: 1,
                    freeLodgingSlotCount: 2,
                  ),
                  '2': BdoTownWorkerCapacity(
                    availableWorkerCount: 3,
                    freeLodgingSlotCount: 4,
                  ),
                }
              : const <String, BdoTownWorkerCapacity>{
                  '2': BdoTownWorkerCapacity(
                    availableWorkerCount: 3,
                    freeLodgingSlotCount: 4,
                  ),
                  '100': BdoTownWorkerCapacity(
                    availableWorkerCount: 1,
                    freeLodgingSlotCount: 2,
                  ),
                },
        );

    expect(
      jsonEncode(preferences(false).toJson()),
      jsonEncode(preferences(true).toJson()),
    );
  });
}
