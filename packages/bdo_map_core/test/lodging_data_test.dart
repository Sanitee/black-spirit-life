import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled lodging graph is pinned, complete, and attributed', () {
    final bytes = File('assets/data/lodging_houses.json').readAsBytesSync();
    final dataset = LodgingDataset.fromJsonString(String.fromCharCodes(bytes));

    expect(bytes, hasLength(789050));
    expect(
      sha256.convert(bytes).toString(),
      '096d1205bbb12fd0ed0ad0f9ae1a613c680ae0e037cdaa4af91c7f4ad4efa6f6',
    );
    expect(
      dataset.manifest.sourceCommit,
      'cb4965a5be4e68f231c4bbad7b7a87003e27038b',
    );
    expect(dataset.manifest.sourceLicenseExpression, 'NOASSERTION');
    expect(dataset.manifest.permittedUse, contains('Project-owner approved'));
    expect(dataset.manifest.permittedUse, contains('no separate licence'));
    expect(dataset.towns, hasLength(31));
    expect(dataset.towns.where((town) => town.isWorkerTown), hasLength(30));
    expect(dataset.housesById, hasLength(812));
    expect(
      dataset.housesById.values.where((house) => house.isLodging),
      hasLength(225),
    );
    expect(
      dataset.housesById.values.where((house) => !house.isLodging),
      hasLength(587),
    );
    expect(dataset.townsByRegionId[694]!.name, 'Muiquun');
    expect(dataset.townsByRegionId[694]!.isWorkerTown, isFalse);
    expect(dataset.townsByRegionId[694]!.townNodeId, '1381');
    expect(dataset.townsByRegionId[694]!.houses, hasLength(2));
  });

  test(
    'Hakinza has exact houses, coordinates, chains, and a cheapest plan',
    () {
      final dataset = LodgingDataset.fromJsonString(
        File('assets/data/lodging_houses.json').readAsStringSync(),
      );
      final hakinza = dataset.townsByRegionId[1553]!;

      expect(hakinza.name, 'Hakinza Sanctuary');
      expect(hakinza.townNodeId, '2001');
      expect(hakinza.houses, hasLength(6));
      expect(hakinza.housesById['house:3869']!.name, 'Shore of Ruins 2');
      expect(
        hakinza.housesById['house:3869']!.prerequisiteHouseId,
        'house:3868',
      );
      expect(hakinza.housesById['house:3869']!.lodgingSpaces, 4);
      expect(hakinza.housesById['house:3869']!.position.x, 535092.25);

      final plan = LodgingOptimizer.solve(
        town: hakinza,
        requiredCapacity: 5,
        existingCapacity: 1,
      );
      expect(plan.isFeasible, isTrue);
      expect(plan.incrementalContributionPoints, 2);
      expect(plan.addedCapacity, 4);
      expect(plan.selectedLodgingHouseIds, <String>['house:3869']);
      expect(plan.newlyRequiredHouseIds, <String>['house:3868', 'house:3869']);
    },
  );

  test('an owned non-lodging house reduces a real lodging path CP', () {
    final dataset = LodgingDataset.fromJsonString(
      File('assets/data/lodging_houses.json').readAsStringSync(),
    );
    final calpheon = dataset.townsByNodeId['601']!;
    final prerequisite = calpheon.housesById['house:2666']!;
    expect(prerequisite.isLodging, isFalse);
    expect(
      prerequisite.usages.map((usage) => usage.label),
      containsAll(<String>['Residence', 'Storage', 'Armor Workshop']),
    );
    const allowedLodgingId = 'house:2667';
    final plan = LodgingOptimizer.solve(
      town: calpheon,
      requiredCapacity: 2,
      existingCapacity: 0,
      currentOwnedHouseIds: const <String>{'house:2666'},
      blockedHouseIds: <String>{
        for (final house in calpheon.lodgingHouses)
          if (house.id != allowedLodgingId) house.id,
      },
    );

    expect(plan.isFeasible, isTrue);
    expect(plan.selectedLodgingHouseIds, <String>[allowedLodgingId]);
    expect(plan.incrementalContributionPoints, 1);
    expect(plan.ownedHouseIdsUsed, <String>['house:2666']);
  });

  test('parser rejects missing, cross-town, and cyclic prerequisites', () {
    expect(
      () => LodgingDataset.fromJson(
        _datasetJson(<Map<String, Object?>>[
          _townJson(
            regionId: 1,
            nodeId: 'town-a',
            houses: <Map<String, Object?>>[
              _houseJson(1, prerequisiteId: 'house:2'),
            ],
          ),
        ]),
      ),
      throwsFormatException,
    );

    expect(
      () => LodgingDataset.fromJson(
        _datasetJson(<Map<String, Object?>>[
          _townJson(
            regionId: 1,
            nodeId: 'town-a',
            houses: <Map<String, Object?>>[
              _houseJson(1, prerequisiteId: 'house:2'),
              _houseJson(2, prerequisiteId: 'house:1'),
            ],
          ),
        ]),
      ),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _datasetJson(List<Map<String, Object?>> towns) {
  final houses = <Map<String, Object?>>[
    for (final town in towns) ...town['houses']! as List<Map<String, Object?>>,
  ];
  final lodgingCount = houses
      .where((house) => house['isLodging'] == true)
      .length;
  return <String, Object?>{
    'schemaVersion': 2,
    'manifest': <String, Object?>{
      'datasetVersion': 'test',
      'generatedAt': '2026-07-30T00:00:00.000Z',
      'sourceRepository': 'https://example.invalid',
      'sourceCommit': 'test',
      'sourceLicenseExpression': 'test',
      'permittedUse': 'test',
      'sourceSha256': <String, String>{'test': 'test'},
      'townCount': towns.length,
      'workerTownCount': towns.length,
      'lodgingHouseCount': lodgingCount,
      'nonLodgingHouseCount': houses.length - lodgingCount,
      'houseCount': houses.length,
      'assumptions': <String>['test'],
    },
    'towns': towns,
  };
}

Map<String, Object?> _townJson({
  required int regionId,
  required String nodeId,
  required List<Map<String, Object?>> houses,
}) {
  return <String, Object?>{
    'regionId': regionId,
    'townNodeId': nodeId,
    'name': nodeId,
    'isWorkerTown': true,
    'baseWorkerSlots': 1,
    'position': _positionJson(),
    'houses': <Map<String, Object?>>[
      for (final house in houses)
        <String, Object?>{...house, 'regionId': regionId, 'townNodeId': nodeId},
    ],
  };
}

Map<String, Object?> _houseJson(int key, {String? prerequisiteId}) {
  return <String, Object?>{
    'id': 'house:$key',
    'sourceKey': key,
    'name': 'House $key',
    'regionId': 1,
    'townNodeId': 'town-a',
    'parentNodeId': 'town-a',
    'contributionPoints': 1,
    'lodgingSpaces': 1,
    'isLodging': true,
    'usages': <Map<String, Object?>>[
      <String, Object?>{'typeId': 1, 'label': 'Lodging', 'level': 1},
    ],
    'prerequisiteHouseId': prerequisiteId,
    'position': _positionJson(),
  };
}

Map<String, Object?> _positionJson() => <String, Object?>{
  'x': 0.0,
  'y': 0.0,
  'z': 0.0,
};
