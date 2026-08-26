import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reviewed Storage levels map to exact slot counts', () {
    expect(storageSlotsByLevel, const <int, int>{
      1: 3,
      2: 5,
      3: 8,
      4: 12,
      5: 16,
    });
    expect(() => storageSlotsForLevel(6), throwsArgumentError);
  });

  test('bundled house graph uses only reviewed Storage levels', () async {
    final dataset = await LodgingDataLoader.loadBundled();
    final storageHouses = dataset.housesById.values
        .where((house) => house.supportsUsage(2))
        .toList(growable: false);

    expect(storageHouses, isNotEmpty);
    expect(
      storageHouses.every(
        (house) =>
            storageSlotsByLevel.containsKey(house.usagesByTypeId[2]!.level),
      ),
      isTrue,
    );
  });

  test(
    'chooses the exact cheapest connected path without forced oversupply',
    () {
      final town = _town(<LodgingHouse>[
        _house(1, cp: 1, storageLevel: 1),
        _house(2, cp: 1, storageLevel: 2, prerequisiteId: 'house:1'),
        _house(3, cp: 3, storageLevel: 3),
      ]);

      final plan = StorageHouseOptimizer.solve(
        town: town,
        requestedAdditionalSlots: 5,
      );

      expect(plan.isFeasible, isTrue);
      expect(plan.incrementalContributionPoints, 2);
      expect(plan.addedStorageSlots, 5);
      expect(plan.slotOversupply, 0);
      expect(plan.selectedStorageHouseIds, <String>['house:2']);
      expect(plan.newlyRequiredHouseIds, <String>['house:1', 'house:2']);
      expect(plan.prerequisiteHouseIds, <String>['house:1']);
    },
  );

  test('active owned Storage counts at mapped max without double counting', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 4, storageLevel: 2),
      _house(2, cp: 2, storageLevel: 1, prerequisiteId: 'house:1'),
    ]);

    final plan = StorageHouseOptimizer.solve(
      town: town,
      requestedAdditionalSlots: 3,
      currentOwnedHouseIds: const <String>{'house:1'},
      currentHouseUsageTypeIds: const <String, int>{'house:1': 2},
    );

    expect(plan.existingStorageSlots, 5);
    expect(plan.addedStorageSlots, 3);
    expect(plan.incrementalContributionPoints, 2);
    expect(plan.selectedStorageHouseIds, <String>['house:2']);
    expect(plan.ownedHouseIdsUsed, <String>['house:1']);
  });

  test('saved non-Storage and unknown owned uses remain protected', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 4, storageLevel: 2, alsoLodging: true),
      _house(2, cp: 1, storageLevel: 1, prerequisiteId: 'house:1'),
      _house(3, cp: 1, storageLevel: 5),
    ]);

    final plan = StorageHouseOptimizer.solve(
      town: town,
      requestedAdditionalSlots: 3,
      currentOwnedHouseIds: const <String>{'house:1', 'house:3'},
      currentHouseUsageTypeIds: const <String, int>{'house:1': 1},
    );

    expect(plan.incrementalContributionPoints, 1);
    expect(plan.selectedStorageHouseIds, <String>['house:2']);
    expect(plan.protectedOwnedHouseIds, <String>['house:1']);
    expect(plan.unknownUseOwnedHouseIds, <String>['house:3']);
    expect(plan.ownedHouseIdsUsed, <String>['house:1']);
  });

  test('impossible target returns the maximum reachable Storage', () {
    final town = _town(<LodgingHouse>[
      _house(1, cp: 1, storageLevel: 1),
      _house(2, cp: 1, storageLevel: 2),
    ]);

    final plan = StorageHouseOptimizer.solve(
      town: town,
      requestedAdditionalSlots: 20,
    );

    expect(plan.isFeasible, isFalse);
    expect(plan.addedStorageSlots, 8);
    expect(plan.slotShortfall, 12);
    expect(plan.incrementalContributionPoints, 2);
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
  required int storageLevel,
  String? prerequisiteId,
  bool alsoLodging = false,
}) {
  return LodgingHouse(
    id: 'house:$key',
    sourceKey: key,
    name: 'House $key',
    regionId: 1,
    townNodeId: 'town',
    parentNodeId: 'town',
    contributionPoints: cp,
    lodgingSpaces: alsoLodging ? 1 : 0,
    isLodging: alsoLodging,
    usages: <HouseUsage>[
      if (alsoLodging) const HouseUsage(typeId: 1, label: 'Lodging', level: 1),
      HouseUsage(typeId: 2, label: 'Storage', level: storageLevel),
    ],
    prerequisiteHouseId: prerequisiteId,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
}
