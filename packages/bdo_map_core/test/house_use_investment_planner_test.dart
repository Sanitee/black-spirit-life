import 'package:bdo_map_core/src/lodging/house_use_investment_planner.dart';
import 'package:bdo_map_core/src/lodging/lodging_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('charges a shared prerequisite only once for multiple facilities', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 2, usages: const <HouseUsage>[_residence]),
      _house(
        2,
        cp: 3,
        prerequisiteId: 'house:1',
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 1),
        ],
      ),
      _house(
        3,
        cp: 4,
        prerequisiteId: 'house:1',
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 2),
        ],
      ),
    ]);

    final plan = HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: 14,
      requestedAdditionalFacilityCount: 2,
    );

    expect(plan.isFeasible, isTrue);
    expect(plan.selectedFacilityCount, 2);
    expect(plan.incrementalContributionPoints, 9);
    expect(plan.selectedCapability, 3);
    expect(plan.selectedUseHouseIds, <String>['house:2', 'house:3']);
    expect(plan.newPrerequisiteHouseIds, <String>['house:1']);
    expect(plan.newlyRequiredHouseIds, <String>[
      'house:1',
      'house:2',
      'house:3',
    ]);
    expect(plan.fullHouseClosureIds, <String>['house:1', 'house:2', 'house:3']);
  });

  test('owned houses are protected zero-cost prerequisites, not targets', () {
    final town = _town(<LodgingHouse>[
      _house(
        1,
        cp: 8,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 5),
        ],
      ),
      _house(
        2,
        cp: 2,
        prerequisiteId: 'house:1',
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 1),
        ],
      ),
      _house(3, cp: 1, usages: const <HouseUsage>[_residence]),
    ]);

    final plan = HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: 14,
      requestedAdditionalFacilityCount: 1,
      currentOwnedHouseIds: const <String>{'house:1', 'house:3'},
      currentHouseUsageTypeIds: const <String, int>{'house:1': 14},
    );

    expect(plan.selectedUseHouseIds, <String>['house:2']);
    expect(plan.incrementalContributionPoints, 2);
    expect(plan.ownedPrerequisiteHouseIds, <String>['house:1']);
    expect(plan.protectedOwnedHouseIds, <String>['house:1', 'house:3']);
    expect(plan.unknownUseOwnedHouseIds, <String>['house:3']);
  });

  test('matches the exact usage id instead of a shared display label', () {
    final town = _town(<LodgingHouse>[
      _house(
        1,
        cp: 1,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 16, label: 'Tool Workshop', level: 5),
        ],
      ),
      _house(
        2,
        cp: 4,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 21, label: 'Tool Workshop', level: 1),
        ],
      ),
    ]);

    final plan = HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: 21,
      requestedAdditionalFacilityCount: 1,
    );

    expect(plan.selectedUseHouseIds, <String>['house:2']);
    expect(plan.incrementalContributionPoints, 4);
  });

  test('filters exact facilities below the requested minimum level', () {
    final town = _town(<LodgingHouse>[
      _house(
        1,
        cp: 1,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 1),
        ],
      ),
      _house(
        2,
        cp: 3,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 3),
        ],
      ),
    ]);

    final plan = HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: 14,
      minimumLevel: 2,
      requestedAdditionalFacilityCount: 1,
    );

    expect(plan.selectedUseHouseIds, <String>['house:2']);
    expect(plan.selectedCapability, 3);
  });

  test('returns the best partial plan and shortfall when infeasible', () {
    final town = _town(<LodgingHouse>[
      _house(
        1,
        cp: 1,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 1),
        ],
      ),
      _house(
        2,
        cp: 2,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 2),
        ],
      ),
    ]);

    final plan = HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: 14,
      requestedAdditionalFacilityCount: 3,
    );

    expect(plan.isFeasible, isFalse);
    expect(plan.selectedFacilityCount, 2);
    expect(plan.facilityShortfall, 1);
    expect(plan.selectedUseHouseIds, <String>['house:1', 'house:2']);
    expect(plan.incrementalContributionPoints, 3);
  });

  test('uses CP, house count, capability, then stable id for ties', () {
    final fewerHousesTown = _town(<LodgingHouse>[
      _house(1, cp: 0, usages: const <HouseUsage>[_residence]),
      _house(
        2,
        cp: 2,
        prerequisiteId: 'house:1',
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 1),
        ],
      ),
      _house(
        3,
        cp: 2,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 1),
        ],
      ),
    ]);
    final fewerHouses = HouseUseInvestmentPlanner.solve(
      town: fewerHousesTown,
      usageTypeId: 14,
      requestedAdditionalFacilityCount: 1,
    );
    expect(fewerHouses.selectedUseHouseIds, <String>['house:3']);

    final capabilityTown = _town(<LodgingHouse>[
      _house(
        4,
        cp: 2,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 2),
        ],
      ),
      _house(
        5,
        cp: 2,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 4),
        ],
      ),
    ]);
    final capability = HouseUseInvestmentPlanner.solve(
      town: capabilityTown,
      usageTypeId: 14,
      requestedAdditionalFacilityCount: 1,
    );
    expect(capability.selectedUseHouseIds, <String>['house:5']);

    final stableIdTown = _town(<LodgingHouse>[
      _house(
        9,
        cp: 2,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 2),
        ],
      ),
      _house(
        7,
        cp: 2,
        usages: const <HouseUsage>[
          HouseUsage(typeId: 14, label: 'Carpentry Workshop', level: 2),
        ],
      ),
    ]);
    final stableId = HouseUseInvestmentPlanner.solve(
      town: stableIdTown,
      usageTypeId: 14,
      requestedAdditionalFacilityCount: 1,
    );
    expect(stableId.selectedUseHouseIds, <String>['house:7']);
  });

  test('bundled Grana collision keeps Tool Workshop ids distinct', () async {
    final dataset = await LodgingDataLoader.loadBundled();
    final town = dataset.townsByNodeId['1623']!;

    final plan = HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: 21,
      requestedAdditionalFacilityCount: 1,
    );

    expect(plan.isFeasible, isTrue);
    expect(plan.selectedUseHouseIds, hasLength(1));
    final selected = town.housesById[plan.selectedUseHouseIds.single]!;
    expect(selected.usagesByTypeId[21], isNotNull);
    expect(selected.usagesByTypeId[16], isNull);
  });

  test('rejects invalid usage, level, and facility counts', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 1, usages: const <HouseUsage>[_residence]),
    ]);

    expect(
      () => HouseUseInvestmentPlanner.solve(
        town: town,
        usageTypeId: -1,
        requestedAdditionalFacilityCount: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => HouseUseInvestmentPlanner.solve(
        town: town,
        usageTypeId: 0,
        minimumLevel: 0,
        requestedAdditionalFacilityCount: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => HouseUseInvestmentPlanner.solve(
        town: town,
        usageTypeId: 0,
        requestedAdditionalFacilityCount: -1,
      ),
      throwsArgumentError,
    );
  });
}

const _residence = HouseUsage(typeId: 0, label: 'Residence', level: 1);

LodgingTown _town(List<LodgingHouse> houses) {
  return LodgingTown(
    regionId: 1,
    townNodeId: 'town',
    name: 'Town',
    isWorkerTown: true,
    baseWorkerSlots: 1,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
    houses: houses,
  );
}

LodgingHouse _house(
  int sourceKey, {
  required int cp,
  required List<HouseUsage> usages,
  String? prerequisiteId,
}) {
  final lodging = usages.where((usage) => usage.typeId == 1).firstOrNull;
  return LodgingHouse(
    id: 'house:$sourceKey',
    sourceKey: sourceKey,
    name: 'House $sourceKey',
    regionId: 1,
    townNodeId: 'town',
    parentNodeId: 'town',
    contributionPoints: cp,
    lodgingSpaces: lodging?.level ?? 0,
    isLodging: lodging != null,
    usages: usages,
    prerequisiteHouseId: prerequisiteId,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
}
