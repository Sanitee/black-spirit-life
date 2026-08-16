import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoRecipeNodeRecommendationService', () {
    test(
      'solves all recipe shortages together so connection paths can share',
      () {
        final result = const BdoRecipeNodeRecommendationService().recommend(
          data: _sharedDataset(),
          request: BdoRecipeNodeRecommendationRequest(
            contributionPointBudget: 20,
            recipeLeafShortages: const <BdoRecipeLeafShortage>[
              BdoRecipeLeafShortage(name: 'Ash Log', missingQuantity: 12),
              BdoRecipeLeafShortage(
                name: '',
                gameItemId: 200,
                missingQuantity: 7,
              ),
            ],
          ),
        );

        expect(result.uncoveredMaterials, isEmpty);
        expect(result.coversEveryRequestedMaterial, isTrue);
        expect(result.isExact, isTrue);
        expect(result.requestedDistinctNodeCountsByResource, <String, int>{
          'ore': 1,
          'wood': 1,
        });
        expect(result.networkResult!.plan!.totalContributionPoints, 4);
        expect(result.networkResult!.plan!.selectedProductionNodeIds, <String>[
          'ore-shared',
          'wood-shared',
        ]);
      },
    );

    test(
      'deduplicates matching leaves and preserves their quantity as context',
      () {
        final result = const BdoRecipeNodeRecommendationService().recommend(
          data: _sharedDataset(),
          request: BdoRecipeNodeRecommendationRequest(
            contributionPointBudget: 20,
            recipeLeafShortages: const <BdoRecipeLeafShortage>[
              BdoRecipeLeafShortage(name: 'Ash Timber', missingQuantity: 2),
              BdoRecipeLeafShortage(name: 'ash log', missingQuantity: 5),
            ],
          ),
        );

        expect(result.coverageTargets, hasLength(1));
        final target = result.coverageTargets.single;
        expect(target.resourceId, 'wood');
        expect(target.requestedDistinctProductionNodeCount, 1);
        expect(target.totalRecipeShortageQuantity, 7);
        expect(target.hasRecipeShortage, isTrue);
        expect(target.availableDistinctProductionNodeCount, 2);
      },
    );

    test('explicit targets can request multiple distinct production nodes', () {
      final result = const BdoRecipeNodeRecommendationService().recommend(
        data: _sharedDataset(),
        request: BdoRecipeNodeRecommendationRequest(
          contributionPointBudget: 20,
          recipeLeafShortages: const <BdoRecipeLeafShortage>[
            BdoRecipeLeafShortage(name: 'Ash Timber', missingQuantity: 50),
          ],
          materialTargets: const <BdoRecipeNodeMaterialTarget>[
            BdoRecipeNodeMaterialTarget(
              query: 'wood',
              distinctProductionNodeCount: 2,
            ),
          ],
        ),
      );

      expect(result.uncoveredMaterials, isEmpty);
      expect(result.requestedDistinctNodeCountsByResource, <String, int>{
        'wood': 2,
      });
      expect(
        result.networkResult!.plan!.workerNodeIdsByResource['wood'],
        <String>['wood-direct', 'wood-shared'],
      );
      expect(result.coverageTargets.single.hasExplicitMaterialTarget, isTrue);
    });

    test(
      'forwards the saved network and selected roots to change planning',
      () {
        final result = const BdoRecipeNodeRecommendationService().recommend(
          data: _sharedDataset(),
          request: BdoRecipeNodeRecommendationRequest(
            contributionPointBudget: 20,
            recipeLeafShortages: const <BdoRecipeLeafShortage>[
              BdoRecipeLeafShortage(name: 'Ash Timber', missingQuantity: 1),
              BdoRecipeLeafShortage(name: 'Iron Ore', missingQuantity: 1),
            ],
            currentNodeIds: const <String>{'root', 'shared', 'wood-shared'},
            rootNodeIds: const <String>{'root'},
          ),
        );

        final plan = result.networkResult!.plan!;
        expect(plan.selectedRootNodeIds, <String>['root']);
        expect(
          plan.changeSet.retainedNodeIds,
          containsAll(<String>['shared', 'wood-shared']),
        );
        expect(plan.changeSet.connectNodeIds, <String>['ore-shared']);
        expect(plan.changeSet.disconnectNodeIds, isEmpty);
      },
    );

    test(
      'reports every invalid or unsupported material without inventing a plan',
      () {
        final result = const BdoRecipeNodeRecommendationService().recommend(
          data: _diagnosticDataset(),
          request: BdoRecipeNodeRecommendationRequest(
            contributionPointBudget: 20,
            recipeLeafShortages: const <BdoRecipeLeafShortage>[
              BdoRecipeLeafShortage(name: '', missingQuantity: 1),
              BdoRecipeLeafShortage(name: 'Ash Timber', missingQuantity: 0),
              BdoRecipeLeafShortage(
                name: 'Missing Material',
                missingQuantity: 1,
              ),
              BdoRecipeLeafShortage(name: 'Wild Herb', missingQuantity: 1),
              BdoRecipeLeafShortage(name: 'Twin', missingQuantity: 1),
            ],
            materialTargets: const <BdoRecipeNodeMaterialTarget>[
              BdoRecipeNodeMaterialTarget(
                query: 'Ash Timber',
                distinctProductionNodeCount: 0,
              ),
            ],
          ),
        );

        expect(result.networkResult, isNull);
        expect(result.coverageTargets, isEmpty);
        expect(
          result.uncoveredMaterials.map((item) => item.reason).toSet(),
          <BdoRecipeNodeUncoveredReason>{
            BdoRecipeNodeUncoveredReason.invalidMaterialReference,
            BdoRecipeNodeUncoveredReason.invalidShortageQuantity,
            BdoRecipeNodeUncoveredReason.invalidDistinctProductionNodeCount,
            BdoRecipeNodeUncoveredReason.unmatchedMaterial,
            BdoRecipeNodeUncoveredReason.ambiguousMaterial,
            BdoRecipeNodeUncoveredReason.noWorkerProductionNodes,
          },
        );
        final ambiguous = result.uncoveredMaterials.singleWhere(
          (item) =>
              item.reason == BdoRecipeNodeUncoveredReason.ambiguousMaterial,
        );
        expect(ambiguous.candidateResourceIds, <String>['twin-a', 'twin-b']);
      },
    );

    test(
      'exposes optimizer diagnostics when requested coverage is impossible',
      () {
        final result = const BdoRecipeNodeRecommendationService().recommend(
          data: _sharedDataset(),
          request: BdoRecipeNodeRecommendationRequest(
            contributionPointBudget: 20,
            materialTargets: const <BdoRecipeNodeMaterialTarget>[
              BdoRecipeNodeMaterialTarget(
                query: 'Iron Ore',
                distinctProductionNodeCount: 3,
              ),
            ],
          ),
        );

        expect(
          result.coverageTargets.single.availableDistinctProductionNodeCount,
          2,
        );
        expect(result.networkResult, isNotNull);
        expect(result.networkResult!.plan, isNull);
        expect(
          result.networkResult!.diagnostics.map((item) => item.code),
          contains(BdoNodeNetworkDiagnosticCode.insufficientProductionNodes),
        );
      },
    );

    test(
      'current 28-material Alchemy request returns a complete mapped route',
      () async {
        final data = await BdoResourceMapLoader.loadBundled();
        const plannerMaterialIds = <int>[
          4801,
          4802,
          4803,
          4804,
          4805,
          5001,
          5002,
          5003,
          5004,
          5005,
          5006,
          5007,
          5008,
          5010,
          5011,
          5020,
          5024,
          5401,
          5402,
          5407,
          5408,
          5409,
          5410,
          5411,
          5412,
          5413,
          5414,
          5960,
        ];

        final recommendation = const BdoRecipeNodeRecommendationService()
            .recommend(
              data: data,
              request: BdoRecipeNodeRecommendationRequest(
                contributionPointBudget: 500,
                recipeLeafShortages: <BdoRecipeLeafShortage>[
                  for (final gameItemId in plannerMaterialIds)
                    BdoRecipeLeafShortage(
                      name: '',
                      gameItemId: gameItemId,
                      missingQuantity: 1,
                    ),
                ],
              ),
            );

        expect(
          recommendation.coverageTargets.length +
              recommendation.uncoveredMaterials.length,
          plannerMaterialIds.length,
        );
        expect(recommendation.coverageTargets, hasLength(28));
        expect(recommendation.uncoveredMaterials, isEmpty);
        expect(recommendation.networkResult, isNotNull);
        expect(recommendation.networkResult!.hasErrors, isFalse);
        final plan = recommendation.networkResult!.plan;
        expect(plan, isNotNull);
        expect(plan!.usesScalableOptimization, isTrue);
        expect(recommendation.isExact, isFalse);
        expect(plan.selectedProductionNodeIds, isNotEmpty);
        expect(plan.changeSet.edges, isNotEmpty);
        expect(
          plan.workerNodeIdsByResource.keys.toSet(),
          recommendation.requestedDistinctNodeCountsByResource.keys.toSet(),
        );
        expect(
          recommendation.networkResult!.diagnostics.map(
            (diagnostic) => diagnostic.code,
          ),
          isNot(
            contains(BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded),
          ),
        );
        expect(
          recommendation.networkResult!.diagnostics.map(
            (diagnostic) => diagnostic.code,
          ),
          contains(BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed),
        );
      },
    );
  });
}

BdoResourceMapDataset _sharedDataset() => _dataset(
  resources: <BdoResourceDefinition>[
    _resource(
      'wood',
      'Ash Timber',
      gameItemId: 100,
      aliases: const <String>['Ash Log'],
    ),
    _resource('ore', 'Iron Ore', gameItemId: 200),
  ],
  nodes: <BdoWorkerNode>[
    _node(
      'root',
      type: 'City',
      cp: 0,
      links: const <String>['shared', 'wood-bridge', 'ore-bridge'],
    ),
    _node(
      'shared',
      cp: 2,
      links: const <String>['root', 'wood-shared', 'ore-shared'],
    ),
    _production(
      'wood-shared',
      cp: 1,
      parent: 'shared',
      outputs: const <String, String>{'wood': 'Ash Timber'},
    ),
    _production(
      'ore-shared',
      cp: 1,
      parent: 'shared',
      outputs: const <String, String>{'ore': 'Iron Ore'},
    ),
    _node('wood-bridge', cp: 3, links: const <String>['root', 'wood-direct']),
    _production(
      'wood-direct',
      cp: 1,
      parent: 'wood-bridge',
      outputs: const <String, String>{'wood': 'Ash Timber'},
    ),
    _node('ore-bridge', cp: 3, links: const <String>['root', 'ore-direct']),
    _production(
      'ore-direct',
      cp: 1,
      parent: 'ore-bridge',
      outputs: const <String, String>{'ore': 'Iron Ore'},
    ),
  ],
);

BdoResourceMapDataset _diagnosticDataset() => _dataset(
  resources: <BdoResourceDefinition>[
    _resource('wood', 'Ash Timber'),
    _resource(
      'herb',
      'Wild Herb',
      acquisitionModes: const <BdoAcquisitionMode>{
        BdoAcquisitionMode.fieldGathering,
      },
    ),
    _resource('twin-a', 'Twin A', aliases: const <String>['Twin']),
    _resource('twin-b', 'Twin B', aliases: const <String>['Twin']),
  ],
  nodes: <BdoWorkerNode>[
    _node(
      'root',
      type: 'City',
      cp: 0,
      links: const <String>['wood-node', 'twin-a-node', 'twin-b-node'],
    ),
    _production(
      'wood-node',
      cp: 1,
      parent: 'root',
      outputs: const <String, String>{'wood': 'Ash Timber'},
    ),
    _production(
      'twin-a-node',
      cp: 1,
      parent: 'root',
      outputs: const <String, String>{'twin-a': 'Twin A'},
    ),
    _production(
      'twin-b-node',
      cp: 1,
      parent: 'root',
      outputs: const <String, String>{'twin-b': 'Twin B'},
    ),
  ],
);

BdoResourceMapDataset _dataset({
  required List<BdoResourceDefinition> resources,
  required List<BdoWorkerNode> nodes,
}) => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'recipe-recommendation-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'test',
    provenance: const <BdoProvenanceRecord>[],
  ),
  resources: resources,
  workerNodes: nodes,
  gatheringSpots: const <BdoGatheringSpot>[],
  gatheringRoutes: const <BdoGatheringRoute>[],
);

BdoResourceDefinition _resource(
  String id,
  String name, {
  int? gameItemId,
  List<String> aliases = const <String>[],
  Set<BdoAcquisitionMode> acquisitionModes = const <BdoAcquisitionMode>{
    BdoAcquisitionMode.workerNode,
  },
}) => BdoResourceDefinition(
  id: id,
  name: name,
  gameItemId: gameItemId,
  category: 'Test',
  section: BdoResourceSection.other,
  aliases: aliases,
  acquisitionModes: acquisitionModes,
);

BdoWorkerNode _node(
  String id, {
  String type = 'Connection',
  required int cp,
  List<String> links = const <String>[],
}) => BdoWorkerNode(
  id: id,
  name: id,
  nodeType: type,
  region: 'Test',
  location: const BdoWorldPoint(0, 0),
  contributionPoints: cp,
  linkIds: links,
  outputs: const <BdoNodeOutput>[],
  isResourceNode: false,
);

BdoWorkerNode _production(
  String id, {
  required int cp,
  required String? parent,
  required Map<String, String> outputs,
}) => BdoWorkerNode(
  id: id,
  name: id,
  nodeType: 'Gathering',
  region: 'Test',
  location: const BdoWorldPoint(0, 0),
  contributionPoints: cp,
  linkIds: parent == null ? const <String>[] : <String>[parent],
  outputs: <BdoNodeOutput>[
    for (final entry in outputs.entries)
      BdoNodeOutput(resourceId: entry.key, name: entry.value, isPrimary: true),
  ],
  isResourceNode: true,
  isProductionNode: true,
  parentId: parent,
);
