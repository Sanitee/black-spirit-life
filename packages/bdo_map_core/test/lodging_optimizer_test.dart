import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authoritative existing capacity avoids CP and double counting', () {
    final town = _town(<LodgingHouse>[_house(1, cp: 4, spaces: 5)]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 3,
      existingCapacity: 3,
      currentOwnedHouseIds: const <String>{'house:1'},
    );

    expect(plan.isFeasible, isTrue);
    expect(plan.incrementalContributionPoints, 0);
    expect(plan.addedCapacity, 0);
    expect(plan.selectedLodgingHouseIds, isEmpty);
  });

  test('shared prerequisite is purchased once', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 2),
      _house(2, cp: 2, spaces: 2, prerequisiteId: 'house:1'),
      _house(3, cp: 2, spaces: 2, prerequisiteId: 'house:1'),
    ]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 4,
      existingCapacity: 0,
    );

    expect(plan.isFeasible, isTrue);
    expect(plan.incrementalContributionPoints, 6);
    expect(plan.selectedLodgingHouseIds, <String>['house:2', 'house:3']);
    expect(plan.newlyRequiredHouseIds, <String>[
      'house:1',
      'house:2',
      'house:3',
    ]);
  });

  test('owned prerequisite ends acquisition chain and costs zero', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 5),
      _house(2, cp: 2),
      _house(3, cp: 3, spaces: 2, prerequisiteId: 'house:2'),
      _house(4, cp: 3, spaces: 2, prerequisiteId: 'house:2'),
    ]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 2,
      existingCapacity: 0,
      currentOwnedHouseIds: const <String>{'house:2'},
    );

    expect(plan.incrementalContributionPoints, 3);
    expect(plan.selectedLodgingHouseIds, <String>['house:3']);
    expect(plan.fullHouseClosureIds, <String>['house:2', 'house:3']);
    expect(plan.newlyRequiredHouseIds, <String>['house:3']);
    expect(plan.ownedHouseIdsUsed, <String>['house:2']);
  });

  test('oversupply and lexical tie breaks are deterministic', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 1, spaces: 4),
      _house(2, cp: 1, spaces: 3),
      _house(3, cp: 1, spaces: 3),
    ]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 2,
      existingCapacity: 0,
    );

    expect(plan.incrementalContributionPoints, 1);
    expect(plan.addedCapacity, 3);
    expect(plan.selectedLodgingHouseIds, <String>['house:2']);
    expect(plan.capacityOversupply, 1);
  });

  test('alternative chains choose exact cheapest shared route', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 1),
      _house(2, cp: 2, spaces: 4, prerequisiteId: 'house:1'),
      _house(3, cp: 4, spaces: 4),
      _house(4, cp: 1, spaces: 1, prerequisiteId: 'house:1'),
    ]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 4,
      existingCapacity: 0,
    );

    expect(plan.incrementalContributionPoints, 3);
    expect(plan.selectedLodgingHouseIds, <String>['house:2']);
    expect(plan.newlyRequiredHouseIds, <String>['house:1', 'house:2']);
  });

  test('blocked lodging houses can be prerequisites but not capacity', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 1, spaces: 5),
      _house(2, cp: 1, spaces: 3, prerequisiteId: 'house:1'),
      _house(3, cp: 3, spaces: 3),
    ]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 3,
      existingCapacity: 0,
      blockedHouseIds: const <String>{'house:1'},
    );

    expect(plan.incrementalContributionPoints, 2);
    expect(plan.selectedLodgingHouseIds, <String>['house:2']);
    expect(plan.newlyRequiredHouseIds, <String>['house:1', 'house:2']);
  });

  test('impossible request returns maximum reachable capacity', () {
    final town = _town(<LodgingHouse>[_house(1, cp: 1, spaces: 2)]);

    final plan = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 5,
      existingCapacity: 1,
    );

    expect(plan.isFeasible, isFalse);
    expect(plan.addedCapacity, 2);
    expect(plan.capacityShortfall, 2);
  });
}

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
  int key, {
  required int cp,
  int spaces = 0,
  String? prerequisiteId,
}) {
  return LodgingHouse(
    id: 'house:$key',
    sourceKey: key,
    name: 'House $key',
    regionId: 1,
    townNodeId: 'town',
    parentNodeId: 'town',
    contributionPoints: cp,
    lodgingSpaces: spaces,
    isLodging: spaces > 0,
    usages: <HouseUsage>[
      HouseUsage(
        typeId: spaces > 0 ? 1 : 2,
        label: spaces > 0 ? 'Lodging' : 'Storage',
        level: 1,
      ),
    ],
    prerequisiteHouseId: prerequisiteId,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
}
