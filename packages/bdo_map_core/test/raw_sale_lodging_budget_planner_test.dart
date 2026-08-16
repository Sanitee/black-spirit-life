import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoRawSaleLodgingBudgetPlanner', () {
    test(
      'repairs a node-only plan so lodging shares the same CP budget',
      () async {
        final fixture = _smallFixture();

        final nodeOnly = const BdoRawSaleNetworkPlanner().plan(
          data: fixture.map,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 3,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'production:best': 10,
              'production:second': 9,
            },
          ),
        );
        expect(nodeOnly.selectedProductionNodeIds, <String>[
          'production:best',
          'production:second',
        ]);

        final result = await const BdoRawSaleLodgingBudgetPlanner().planAsync(
          data: fixture.map,
          economics: fixture.economics,
          lodgingDataset: fixture.lodging,
          request: BdoRawSaleLodgingBudgetRequest(
            totalContributionPointBudget: 3,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'production:best': 10,
              'production:second': 9,
            },
            townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
              'town': BdoTownWorkerCapacity(
                availableWorkerCount: 0,
                freeLodgingSlotCount: 0,
              ),
            },
          ),
        );

        expect(result.networkPlan.selectedProductionNodeIds, <String>[
          'production:best',
        ]);
        expect(result.networkPlan.totalContributionPoints, 1);
        expect(result.lodgingContributionPoints, 2);
        expect(result.combinedContributionPoints, 3);
        expect(result.isWithinBudget, isTrue);
        expect(result.repairIterations, 2);
        expect(result.lodgingPlanning?.plan?.requiredWorkerSlots, 1);
      },
    );

    test(
      'owned prerequisite lodging lowers CP and keeps another node',
      () async {
        final fixture = _smallFixture();

        final withoutOwned = await const BdoRawSaleLodgingBudgetPlanner()
            .planAsync(
              data: fixture.map,
              economics: fixture.economics,
              lodgingDataset: fixture.lodging,
              request: BdoRawSaleLodgingBudgetRequest(
                totalContributionPointBudget: 3,
                currentNodeIds: const <String>{},
                currentSaleValueSignalsByProductionNodeId:
                    const <String, double>{
                      'production:best': 10,
                      'production:second': 9,
                    },
                townWorkerCapacitiesByNodeId:
                    const <String, BdoTownWorkerCapacity>{
                      'town': BdoTownWorkerCapacity(
                        availableWorkerCount: 0,
                        freeLodgingSlotCount: 0,
                      ),
                    },
              ),
            );
        final withOwned = await const BdoRawSaleLodgingBudgetPlanner()
            .planAsync(
              data: fixture.map,
              economics: fixture.economics,
              lodgingDataset: fixture.lodging,
              request: BdoRawSaleLodgingBudgetRequest(
                totalContributionPointBudget: 3,
                currentNodeIds: const <String>{},
                currentSaleValueSignalsByProductionNodeId:
                    const <String, double>{
                      'production:best': 10,
                      'production:second': 9,
                    },
                townWorkerCapacitiesByNodeId:
                    const <String, BdoTownWorkerCapacity>{
                      'town': BdoTownWorkerCapacity(
                        availableWorkerCount: 0,
                        freeLodgingSlotCount: 0,
                      ),
                    },
                currentOwnedHouseIds: const <String>{'house:prerequisite'},
              ),
            );

        expect(withoutOwned.networkPlan.selections, hasLength(1));
        expect(withoutOwned.lodgingContributionPoints, 2);
        expect(withOwned.networkPlan.selections, hasLength(2));
        expect(withOwned.lodgingContributionPoints, 1);
        expect(withOwned.combinedContributionPoints, 3);
        expect(withOwned.isWithinBudget, isTrue);
        expect(withOwned.lodgingPlanning?.plan?.newlyRequiredHouseIds, <String>[
          'house:lodging',
        ]);
      },
    );

    test(
      'entered available workers are reused before buying lodging',
      () async {
        final fixture = _smallFixture();

        final result = await const BdoRawSaleLodgingBudgetPlanner().planAsync(
          data: fixture.map,
          economics: fixture.economics,
          lodgingDataset: fixture.lodging,
          request: BdoRawSaleLodgingBudgetRequest(
            totalContributionPointBudget: 2,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'production:best': 10,
              'production:second': 9,
            },
            townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
              'town': BdoTownWorkerCapacity(
                availableWorkerCount: 2,
                freeLodgingSlotCount: 0,
              ),
            },
          ),
        );

        expect(result.networkPlan.selections, hasLength(2));
        expect(result.workerCapacity?.assessment?.availableWorkersUsed, 2);
        expect(result.lodgingContributionPoints, 0);
        expect(result.combinedContributionPoints, 2);
        expect(result.isWithinBudget, isTrue);
      },
    );

    test(
      'every repaired recommendation stays inside the combined cap',
      () async {
        final fixture = _smallFixture();

        for (final owned in <Set<String>>[
          const <String>{},
          const <String>{'house:prerequisite'},
        ]) {
          for (var budget = 0; budget <= 5; budget += 1) {
            final result = await const BdoRawSaleLodgingBudgetPlanner()
                .planAsync(
                  data: fixture.map,
                  economics: fixture.economics,
                  lodgingDataset: fixture.lodging,
                  request: BdoRawSaleLodgingBudgetRequest(
                    totalContributionPointBudget: budget,
                    currentNodeIds: const <String>{},
                    currentSaleValueSignalsByProductionNodeId:
                        const <String, double>{
                          'production:best': 10,
                          'production:second': 9,
                        },
                    townWorkerCapacitiesByNodeId:
                        const <String, BdoTownWorkerCapacity>{
                          'town': BdoTownWorkerCapacity(
                            availableWorkerCount: 0,
                            freeLodgingSlotCount: 0,
                          ),
                        },
                    currentOwnedHouseIds: owned,
                  ),
                );

            expect(
              result.combinedContributionPoints,
              lessThanOrEqualTo(budget),
              reason: 'budget=$budget owned=$owned',
            );
            expect(result.isWithinBudget, isTrue);
          }
        }
      },
    );

    test(
      'replaces a town-blocking prefix node with a staffable later node',
      () async {
        final fixture = _asymmetricFixture();

        final result = await const BdoRawSaleLodgingBudgetPlanner().planAsync(
          data: fixture.map,
          economics: fixture.economics,
          lodgingDataset: fixture.lodging,
          request: BdoRawSaleLodgingBudgetRequest(
            totalContributionPointBudget: 4,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'production:high-a': 30,
              'production:blocked-a': 20,
              'production:lower-b': 10,
            },
            townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
              'town:a': BdoTownWorkerCapacity(
                availableWorkerCount: 0,
                freeLodgingSlotCount: 0,
              ),
              'town:b': BdoTownWorkerCapacity(
                availableWorkerCount: 0,
                freeLodgingSlotCount: 0,
              ),
            },
          ),
        );

        expect(result.networkPlan.selectedProductionNodeIds, <String>[
          'production:high-a',
          'production:lower-b',
        ]);
        expect(result.lodgingContributionPoints, 2);
        expect(result.combinedContributionPoints, 4);
        expect(result.isWithinBudget, isTrue);
        expect(result.repairIterations, 2);
      },
    );

    test('bundled CP500 lodging-aware planning stays cooperative', () async {
      final map = BdoResourceMapDataset.fromJson(
        jsonDecode(File('assets/data/resource_map.json').readAsStringSync())
            as Map<String, Object?>,
      );
      final economics = BdoWorkerEconomicsDataset.fromJsonString(
        File('assets/data/worker_economics.json').readAsStringSync(),
      );
      final lodging = LodgingDataset.fromJsonString(
        File('assets/data/lodging_houses.json').readAsStringSync(),
      );
      final signals = <String, double>{
        for (
          var index = 0;
          index < economics.productionNodesById.length;
          index++
        )
          economics.productionNodesById.keys.elementAt(index): (index + 1)
              .toDouble(),
      };
      var completed = false;
      var heartbeatCount = 0;
      final heartbeat = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => heartbeatCount += 1,
      );

      final future = const BdoRawSaleLodgingBudgetPlanner()
          .planAsync(
            data: map,
            economics: economics,
            lodgingDataset: lodging,
            request: BdoRawSaleLodgingBudgetRequest(
              totalContributionPointBudget: 500,
              currentNodeIds: const <String>{},
              currentSaleValueSignalsByProductionNodeId: signals,
              townWorkerCapacitiesByNodeId: <String, BdoTownWorkerCapacity>{
                for (final townId in economics.townsByNodeId.keys)
                  townId: const BdoTownWorkerCapacity(
                    availableWorkerCount: 0,
                    freeLodgingSlotCount: 0,
                  ),
              },
            ),
          )
          .whenComplete(() => completed = true);

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      final result = await future.timeout(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);
      heartbeat.cancel();
      expect(result.lodgingBudgetApplied, isTrue);
      expect(result.repairIterations, greaterThan(1));
      expect(result.lodgingContributionPoints, greaterThan(0));
      expect(result.combinedContributionPoints, lessThanOrEqualTo(500));
      expect(result.networkPlan.selections, isNotEmpty);
      expect(heartbeatCount, greaterThan(5));
    });
  });
}

({
  BdoResourceMapDataset map,
  BdoWorkerEconomicsDataset economics,
  LodgingDataset lodging,
})
_smallFixture() {
  final map = BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'lodging-budget-test',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[],
    workerNodes: <BdoWorkerNode>[
      _mapNode(
        'town',
        type: 'City',
        contributionPoints: 0,
        links: const <String>['production:best', 'production:second'],
      ),
      _productionNode('production:best'),
      _productionNode('production:second'),
    ],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
  final profile = const BdoWorkerProfileEstimate(
    id: 'worker',
    label: 'Worker',
    workerType: 0,
    characterKey: 1,
    isGiant: false,
    workSpeed: 100,
    movementSpeed: 10,
    luck: 20,
  );
  final economics = BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: BdoWorkerEconomicsManifest(
      datasetVersion: 'lodging-budget-test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid/test'),
      sourceCommit: 'test',
      sourcePackageVersion: 'test',
      sourceLicenseExpression: 'test-only',
      upstreamWorkermanCommit: 'test',
      permittedUse: 'test-only',
      sourceSha256: const <String, String>{'test': 'test'},
      assumptions: const <String>['Synthetic test dataset.'],
    ),
    townsByNodeId: <String, BdoWorkerTownEconomics>{
      'town': BdoWorkerTownEconomics(
        nodeId: 'town',
        regionId: 1,
        baseWorkerSlots: 1,
        profiles: <BdoWorkerProfileEstimate>[profile],
      ),
    },
    productionNodesById: <String, BdoWorkerProductionEconomics>{
      for (final id in <String>['production:best', 'production:second'])
        id: BdoWorkerProductionEconomics(
          nodeId: id,
          baseWorkload: 100,
          workerTypes: const <int>{0},
          standardYields: const <int, double>{1: 1},
          giantYields: const <int, double>{1: 1},
          luckyBonusYields: const <int, double>{},
          townDistances: const <String, double>{'town': 100},
        ),
    },
  );
  final houses = <LodgingHouse>[
    _house(id: 'house:prerequisite', contributionPoints: 1, lodgingSpaces: 0),
    _house(
      id: 'house:lodging',
      contributionPoints: 1,
      lodgingSpaces: 2,
      prerequisiteHouseId: 'house:prerequisite',
    ),
  ];
  final lodging = LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'lodging-budget-test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid/test'),
      sourceCommit: 'test',
      sourceLicenseExpression: 'test-only',
      permittedUse: 'test-only',
      sourceSha256: const <String, String>{'test': 'test'},
      townCount: 1,
      workerTownCount: 1,
      lodgingHouseCount: 1,
      nonLodgingHouseCount: 1,
      houseCount: 2,
      assumptions: const <String>['Synthetic test dataset.'],
    ),
    towns: <LodgingTown>[
      LodgingTown(
        regionId: 1,
        townNodeId: 'town',
        name: 'Town',
        isWorkerTown: true,
        baseWorkerSlots: 1,
        position: const LodgingPosition(x: 0, y: 0, z: 0),
        houses: houses,
      ),
    ],
  );
  return (map: map, economics: economics, lodging: lodging);
}

({
  BdoResourceMapDataset map,
  BdoWorkerEconomicsDataset economics,
  LodgingDataset lodging,
})
_asymmetricFixture() {
  final map = BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'asymmetric-lodging-budget-test',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[],
    workerNodes: <BdoWorkerNode>[
      _mapNode(
        'town:a',
        type: 'City',
        contributionPoints: 0,
        links: const <String>['production:high-a', 'production:blocked-a'],
      ),
      _mapNode(
        'town:b',
        type: 'City',
        contributionPoints: 0,
        links: const <String>['production:lower-b'],
      ),
      _productionNode('production:high-a', townNodeId: 'town:a'),
      _productionNode('production:blocked-a', townNodeId: 'town:a'),
      _productionNode('production:lower-b', townNodeId: 'town:b'),
    ],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
  const profile = BdoWorkerProfileEstimate(
    id: 'worker',
    label: 'Worker',
    workerType: 0,
    characterKey: 1,
    isGiant: false,
    workSpeed: 100,
    movementSpeed: 10,
    luck: 20,
  );
  BdoWorkerTownEconomics town(String id, int regionId) {
    return BdoWorkerTownEconomics(
      nodeId: id,
      regionId: regionId,
      baseWorkerSlots: 1,
      profiles: const <BdoWorkerProfileEstimate>[profile],
    );
  }

  BdoWorkerProductionEconomics production(String id, String townId) {
    return BdoWorkerProductionEconomics(
      nodeId: id,
      baseWorkload: 100,
      workerTypes: const <int>{0},
      standardYields: const <int, double>{1: 1},
      giantYields: const <int, double>{1: 1},
      luckyBonusYields: const <int, double>{},
      townDistances: <String, double>{townId: 100},
    );
  }

  final economics = BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: BdoWorkerEconomicsManifest(
      datasetVersion: 'asymmetric-lodging-budget-test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid/test'),
      sourceCommit: 'test',
      sourcePackageVersion: 'test',
      sourceLicenseExpression: 'test-only',
      upstreamWorkermanCommit: 'test',
      permittedUse: 'test-only',
      sourceSha256: const <String, String>{'test': 'test'},
      assumptions: const <String>['Synthetic test dataset.'],
    ),
    townsByNodeId: <String, BdoWorkerTownEconomics>{
      'town:a': town('town:a', 1),
      'town:b': town('town:b', 2),
    },
    productionNodesById: <String, BdoWorkerProductionEconomics>{
      'production:high-a': production('production:high-a', 'town:a'),
      'production:blocked-a': production('production:blocked-a', 'town:a'),
      'production:lower-b': production('production:lower-b', 'town:b'),
    },
  );
  final townAHouses = <LodgingHouse>[
    _house(
      id: 'house:a',
      contributionPoints: 1,
      lodgingSpaces: 1,
      townNodeId: 'town:a',
      regionId: 1,
    ),
  ];
  final townBHouses = <LodgingHouse>[
    _house(
      id: 'house:b',
      contributionPoints: 1,
      lodgingSpaces: 1,
      townNodeId: 'town:b',
      regionId: 2,
    ),
  ];
  final lodging = LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'asymmetric-lodging-budget-test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid/test'),
      sourceCommit: 'test',
      sourceLicenseExpression: 'test-only',
      permittedUse: 'test-only',
      sourceSha256: const <String, String>{'test': 'test'},
      townCount: 2,
      workerTownCount: 2,
      lodgingHouseCount: 2,
      nonLodgingHouseCount: 0,
      houseCount: 2,
      assumptions: const <String>['Synthetic test dataset.'],
    ),
    towns: <LodgingTown>[
      LodgingTown(
        regionId: 1,
        townNodeId: 'town:a',
        name: 'Town A',
        isWorkerTown: true,
        baseWorkerSlots: 1,
        position: const LodgingPosition(x: 0, y: 0, z: 0),
        houses: townAHouses,
      ),
      LodgingTown(
        regionId: 2,
        townNodeId: 'town:b',
        name: 'Town B',
        isWorkerTown: true,
        baseWorkerSlots: 1,
        position: const LodgingPosition(x: 0, y: 0, z: 0),
        houses: townBHouses,
      ),
    ],
  );
  return (map: map, economics: economics, lodging: lodging);
}

BdoWorkerNode _mapNode(
  String id, {
  required String type,
  required int contributionPoints,
  List<String> links = const <String>[],
}) {
  return BdoWorkerNode(
    id: id,
    name: id,
    nodeType: type,
    region: 'Test',
    location: const BdoWorldPoint(0, 0),
    contributionPoints: contributionPoints,
    linkIds: links,
    outputs: const <BdoNodeOutput>[],
    isResourceNode: false,
  );
}

BdoWorkerNode _productionNode(String id, {String townNodeId = 'town'}) {
  return BdoWorkerNode(
    id: id,
    name: id,
    nodeType: 'Gathering',
    region: 'Test',
    location: const BdoWorldPoint(0, 0),
    contributionPoints: 1,
    linkIds: <String>[townNodeId],
    outputs: const <BdoNodeOutput>[
      BdoNodeOutput(
        resourceId: 'test-output',
        name: 'Test Output',
        isPrimary: true,
      ),
    ],
    isResourceNode: true,
    isProductionNode: true,
  );
}

LodgingHouse _house({
  required String id,
  required int contributionPoints,
  required int lodgingSpaces,
  String? prerequisiteHouseId,
  String townNodeId = 'town',
  int regionId = 1,
}) {
  return LodgingHouse(
    id: id,
    sourceKey: id.hashCode,
    name: id,
    regionId: regionId,
    townNodeId: townNodeId,
    parentNodeId: townNodeId,
    contributionPoints: contributionPoints,
    lodgingSpaces: lodgingSpaces,
    isLodging: lodgingSpaces > 0,
    usages: <HouseUsage>[
      if (lodgingSpaces > 0)
        const HouseUsage(typeId: 1, label: 'Lodging', level: 1)
      else
        const HouseUsage(typeId: 2, label: 'Storage', level: 1),
    ],
    prerequisiteHouseId: prerequisiteHouseId,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
}
