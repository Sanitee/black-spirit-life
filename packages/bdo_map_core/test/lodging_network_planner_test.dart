import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chooses shared prerequisite lodging across candidate towns', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, <LodgingHouse>[
        _house(1, townId: 'town:a', regionId: 1, cp: 2),
        _house(
          2,
          townId: 'town:a',
          regionId: 1,
          cp: 1,
          spaces: 1,
          prerequisiteId: 'house:1',
        ),
        _house(
          3,
          townId: 'town:a',
          regionId: 1,
          cp: 1,
          spaces: 1,
          prerequisiteId: 'house:1',
        ),
      ]),
      _town('town:b', 2, <LodgingHouse>[
        _house(4, townId: 'town:b', regionId: 2, cp: 3, spaces: 1),
        _house(5, townId: 'town:b', regionId: 2, cp: 3, spaces: 1),
      ]),
    ]);

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: <BdoUnmetWorkerDemand>[
        _demand('production:1', <String>['town:a', 'town:b']),
        _demand('production:2', <String>['town:a', 'town:b']),
      ],
    );

    expect(result.isFeasible, isTrue);
    expect(result.isOptimalityProven, isTrue);
    expect(result.plan!.totalIncrementalContributionPoints, 4);
    expect(result.plan!.townNodeIdByProductionNodeId, <String, String>{
      'production:1': 'town:a',
      'production:2': 'town:a',
    });
    expect(result.plan!.townPlans, hasLength(1));
    expect(result.plan!.townPlans.single.newlyRequiredHouseIds, <String>[
      'house:1',
      'house:2',
      'house:3',
    ]);
    expect(result.plan!.requiredWorkerSlots, 2);
    expect(result.plan!.addedLodgingSlots, 2);
  });

  test('solves a global assignment that per-job cheapest choice misses', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, <LodgingHouse>[
        _house(1, townId: 'town:a', regionId: 1, cp: 1, spaces: 1),
        _house(2, townId: 'town:a', regionId: 1, cp: 100, spaces: 1),
      ]),
      _town('town:b', 2, <LodgingHouse>[
        _house(3, townId: 'town:b', regionId: 2, cp: 2, spaces: 1),
      ]),
    ]);

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: <BdoUnmetWorkerDemand>[
        _demand('production:flexible', <String>['town:a', 'town:b']),
        _demand('production:a-only', <String>['town:a']),
      ],
    );

    expect(result.plan!.totalIncrementalContributionPoints, 3);
    expect(result.plan!.townNodeIdByProductionNodeId, <String, String>{
      'production:a-only': 'town:a',
      'production:flexible': 'town:b',
    });
  });

  test('optimizes current worker capacity and new lodging together', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, const <LodgingHouse>[]),
      _town('town:b', 2, <LodgingHouse>[
        _house(3, townId: 'town:b', regionId: 2, cp: 1, spaces: 1),
      ]),
    ]);

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: <BdoUnmetWorkerDemand>[
        _demand('production:flexible', <String>['town:a', 'town:b']),
        _demand('production:a-only', <String>['town:a']),
      ],
      existingWorkerCapacityByTownNodeId: const <String, int>{'town:a': 1},
    );

    expect(result.isFeasible, isTrue);
    expect(result.plan!.townNodeIdByProductionNodeId, <String, String>{
      'production:a-only': 'town:a',
      'production:flexible': 'town:b',
    });
    expect(result.plan!.totalIncrementalContributionPoints, 1);
    expect(result.plan!.requiredWorkerSlots, 2);
    expect(result.plan!.addedLodgingSlots, 1);
    expect(result.plan!.capacityOversupply, 0);
    expect(result.plan!.townPlansByNodeId['town:a']?.existingCapacity, 1);
    expect(
      result.plan!.townPlansByNodeId['town:a']?.incrementalContributionPoints,
      0,
    );
  });

  test(
    'owned workshop implies its prerequisite path and removes shared CP',
    () {
      final dataset = _dataset(<LodgingTown>[
        _town('town:a', 1, <LodgingHouse>[
          _house(
            1,
            townId: 'town:a',
            regionId: 1,
            cp: 4,
            usage: const HouseUsage(typeId: 2, label: 'Storage', level: 2),
          ),
          _house(
            2,
            townId: 'town:a',
            regionId: 1,
            cp: 3,
            prerequisiteId: 'house:1',
            usage: const HouseUsage(typeId: 5, label: 'Workshop', level: 3),
          ),
          _house(
            3,
            townId: 'town:a',
            regionId: 1,
            cp: 2,
            spaces: 1,
            prerequisiteId: 'house:2',
          ),
        ]),
      ]);

      final result = const BdoLodgingNetworkPlanner().plan(
        dataset: dataset,
        unmetDemands: <BdoUnmetWorkerDemand>[
          _demand('production:1', <String>['town:a']),
        ],
        currentOwnedHouseIds: const <String>{'house:2'},
      );

      expect(result.plan!.totalIncrementalContributionPoints, 2);
      expect(result.plan!.newlyRequiredHouseIds, <String>['house:3']);
      expect(result.plan!.ownedHouseIdsUsed, <String>['house:1', 'house:2']);
      expect(result.plan!.townPlans.single.fullHouseClosureIds, <String>[
        'house:1',
        'house:2',
        'house:3',
      ]);
    },
  );

  test('already-owned lodging is not counted again for an unmet job', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, <LodgingHouse>[
        _house(1, townId: 'town:a', regionId: 1, cp: 2, spaces: 1),
        _house(
          2,
          townId: 'town:a',
          regionId: 1,
          cp: 1,
          spaces: 1,
          prerequisiteId: 'house:1',
        ),
      ]),
    ]);

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: <BdoUnmetWorkerDemand>[
        _demand('production:1', <String>['town:a']),
      ],
      currentOwnedHouseIds: const <String>{'house:1'},
    );

    expect(result.plan!.totalIncrementalContributionPoints, 1);
    expect(result.plan!.newlyRequiredHouseIds, <String>['house:2']);
    expect(result.plan!.addedLodgingSlots, 1);
  });

  test('forced bounded search is feasible but never claims exactness', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, <LodgingHouse>[
        _house(1, townId: 'town:a', regionId: 1, cp: 1, spaces: 2),
      ]),
      _town('town:b', 2, <LodgingHouse>[
        _house(2, townId: 'town:b', regionId: 2, cp: 2, spaces: 2),
      ]),
    ]);

    final result =
        const BdoLodgingNetworkPlanner(
          maxExactStates: 1,
          fallbackBeamWidth: 1,
        ).plan(
          dataset: dataset,
          unmetDemands: <BdoUnmetWorkerDemand>[
            _demand('production:1', <String>['town:a', 'town:b']),
            _demand('production:2', <String>['town:a', 'town:b']),
          ],
        );

    expect(result.isFeasible, isTrue);
    expect(result.isOptimalityProven, isFalse);
    expect(
      result.plan!.quality,
      BdoLodgingNetworkSolutionQuality.deterministicFallback,
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains(BdoLodgingNetworkDiagnosticCode.exactSearchLimitReached),
    );
  });

  test('insufficient cross-town capacity is reported without a plan', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, <LodgingHouse>[
        _house(1, townId: 'town:a', regionId: 1, cp: 1, spaces: 1),
      ]),
    ]);

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: <BdoUnmetWorkerDemand>[
        _demand('production:1', <String>['town:a']),
        _demand('production:2', <String>['town:a']),
      ],
    );

    expect(result.isFeasible, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains(BdoLodgingNetworkDiagnosticCode.insufficientLodgingCapacity),
    );
  });

  test('invalid town and house inputs are not silently ignored', () {
    final dataset = _dataset(<LodgingTown>[
      _town('town:a', 1, <LodgingHouse>[
        _house(1, townId: 'town:a', regionId: 1, cp: 1, spaces: 1),
      ]),
    ]);

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: <BdoUnmetWorkerDemand>[
        _demand('production:1', <String>['town:missing']),
      ],
      currentOwnedHouseIds: const <String>{'house:missing'},
    );

    expect(result.isFeasible, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll(<BdoLodgingNetworkDiagnosticCode>[
        BdoLodgingNetworkDiagnosticCode.unknownCandidateTown,
        BdoLodgingNetworkDiagnosticCode.unreachableProductionNode,
        BdoLodgingNetworkDiagnosticCode.unknownOwnedHouse,
      ]),
    );
  });

  test('empty unmet demand produces a zero-cost proven plan', () {
    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: _dataset(const <LodgingTown>[]),
      unmetDemands: const <BdoUnmetWorkerDemand>[],
    );

    expect(result.isFeasible, isTrue);
    expect(result.isOptimalityProven, isTrue);
    expect(result.plan!.requiredWorkerSlots, 0);
    expect(result.plan!.totalIncrementalContributionPoints, 0);
    expect(result.plan!.townPlans, isEmpty);
  });

  test('a moderate request over real housing chains remains exact', () {
    final dataset = LodgingDataset.fromJsonString(
      File('assets/data/lodging_houses.json').readAsStringSync(),
    );
    final demands = <BdoUnmetWorkerDemand>[
      for (var index = 1; index <= 12; index += 1)
        _demand('production:$index', <String>['601', '2001']),
    ];

    final result = const BdoLodgingNetworkPlanner().plan(
      dataset: dataset,
      unmetDemands: demands.reversed,
    );

    expect(result.isFeasible, isTrue);
    expect(result.isOptimalityProven, isTrue);
    expect(result.plan!.requiredWorkerSlots, 12);
    expect(
      result.plan!.townPlansByNodeId.keys,
      everyElement(isIn(<String>['601', '2001'])),
    );
    expect(result.plan!.totalIncrementalContributionPoints, greaterThan(0));
  });
}

BdoUnmetWorkerDemand _demand(String id, List<String> townIds) {
  return BdoUnmetWorkerDemand(
    productionNodeId: id,
    candidateTownNodeIds: townIds,
  );
}

LodgingDataset _dataset(List<LodgingTown> towns) {
  final houses = towns.expand((town) => town.houses).toList(growable: false);
  final lodgingCount = houses.where((house) => house.isLodging).length;
  return LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'lodging-network-test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid/test'),
      sourceCommit: 'test',
      sourceLicenseExpression: 'test-only',
      permittedUse: 'test-only',
      sourceSha256: const <String, String>{'test': 'test'},
      townCount: towns.length,
      workerTownCount: towns.where((town) => town.isWorkerTown).length,
      lodgingHouseCount: lodgingCount,
      nonLodgingHouseCount: houses.length - lodgingCount,
      houseCount: houses.length,
      assumptions: const <String>['Synthetic test dataset.'],
    ),
    towns: towns,
  );
}

LodgingTown _town(
  String townId,
  int regionId,
  List<LodgingHouse> houses, {
  bool isWorkerTown = true,
}) {
  return LodgingTown(
    regionId: regionId,
    townNodeId: townId,
    name: townId,
    isWorkerTown: isWorkerTown,
    baseWorkerSlots: isWorkerTown ? 1 : 0,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
    houses: houses,
  );
}

LodgingHouse _house(
  int key, {
  required String townId,
  required int regionId,
  required int cp,
  int spaces = 0,
  String? prerequisiteId,
  HouseUsage? usage,
}) {
  return LodgingHouse(
    id: 'house:$key',
    sourceKey: key,
    name: 'House $key',
    regionId: regionId,
    townNodeId: townId,
    parentNodeId: townId,
    contributionPoints: cp,
    lodgingSpaces: spaces,
    isLodging: spaces > 0,
    usages: <HouseUsage>[
      if (spaces > 0)
        const HouseUsage(typeId: 1, label: 'Lodging', level: 1)
      else if (usage != null)
        usage
      else
        const HouseUsage(typeId: 2, label: 'Storage', level: 1),
    ],
    prerequisiteHouseId: prerequisiteId,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
}
