import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoPlannerNeedSelection', () {
    test(
      'uses per-material defaults and supports material and group changes',
      () {
        final cooking = BdoPlannerNeedGroup(
          id: 'cooking',
          label: 'Cooking',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'potato',
              need: _need('Potato', quantity: 12),
            ),
            BdoPlannerNeedMaterial(
              id: 'wheat',
              need: _need('Wheat', quantity: 8),
              selectedByDefault: false,
            ),
          ],
        );
        final alchemy = BdoPlannerNeedGroup(
          id: 'alchemy',
          label: 'Alchemy',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'ash-timber',
              need: _need('Ash Timber', quantity: 3),
            ),
          ],
        );

        final defaults = BdoPlannerNeedSelection(
          groups: <BdoPlannerNeedGroup>[cooking, alchemy],
        );

        expect(defaults.totalMaterialCount, 3);
        expect(defaults.selectedMaterialCount, 2);
        expect(
          defaults.groupSelectionState('cooking'),
          BdoPlannerNeedGroupSelectionState.partial,
        );
        expect(
          defaults.groupSelectionState('alchemy'),
          BdoPlannerNeedGroupSelectionState.all,
        );

        final cookingSelected = defaults.withGroupSelected(
          groupId: 'cooking',
          selected: true,
        );
        expect(cookingSelected.selectedMaterialCount, 3);
        expect(
          cookingSelected.groupSelectionState('cooking'),
          BdoPlannerNeedGroupSelectionState.all,
        );

        final ashRemoved = cookingSelected.toggleMaterial(
          groupId: 'alchemy',
          materialId: 'ash-timber',
        );
        expect(ashRemoved.selectedMaterialCount, 2);
        expect(
          ashRemoved.groupSelectionState('alchemy'),
          BdoPlannerNeedGroupSelectionState.none,
        );
        expect(defaults.selectedMaterialCount, 2, reason: 'state is immutable');
      },
    );

    test(
      'retains original need snapshots and produces stable request order',
      () {
        final cookingNeed = _need(
          'Potato',
          quantity: 12,
          gameItemId: 7003,
          stock: 62528,
        );
        final alchemyNeed = _need(
          'Ash Timber',
          quantity: 3,
          gameItemId: 5013,
          stock: 14,
        );
        final selection = BdoPlannerNeedSelection(
          groups: <BdoPlannerNeedGroup>[
            BdoPlannerNeedGroup(
              id: 'cooking',
              label: 'Cooking',
              materials: <BdoPlannerNeedMaterial>[
                BdoPlannerNeedMaterial(id: 'potato', need: cookingNeed),
              ],
            ),
            BdoPlannerNeedGroup(
              id: 'alchemy',
              label: 'Alchemy',
              materials: <BdoPlannerNeedMaterial>[
                BdoPlannerNeedMaterial(id: 'ash', need: alchemyNeed),
              ],
            ),
          ],
        );

        final merged = selection.selectedPositivePlannerNeeds;

        expect(merged, hasLength(2));
        expect(identical(merged[0], alchemyNeed), isTrue);
        expect(identical(merged[1], cookingNeed), isTrue);
        expect(merged[0].stock, 14);
        expect(merged[1].gameItemId, 7003);
      },
    );

    test('filters nonpositive needs only when building the recommendation', () {
      final selection = BdoPlannerNeedSelection(
        groups: <BdoPlannerNeedGroup>[
          BdoPlannerNeedGroup(
            id: 'cooking',
            label: 'Cooking',
            materials: <BdoPlannerNeedMaterial>[
              BdoPlannerNeedMaterial(
                id: 'potato',
                need: _need('Potato', quantity: 2),
              ),
              BdoPlannerNeedMaterial(
                id: 'already-owned',
                need: _need('Wheat', quantity: 0),
              ),
            ],
          ),
        ],
      );

      expect(selection.selectedMaterialCount, 2);
      expect(selection.selectedPositiveMaterialCount, 1);
      expect(selection.selectedPositivePlannerNeeds.single.name, 'Potato');
    });

    test('rejects duplicate stable IDs and ignores stale persisted keys', () {
      expect(
        () => BdoPlannerNeedGroup(
          id: 'cooking',
          label: 'Cooking',
          materials: <BdoPlannerNeedMaterial>[
            BdoPlannerNeedMaterial(
              id: 'potato',
              need: _need('Potato', quantity: 1),
            ),
            BdoPlannerNeedMaterial(
              id: 'potato',
              need: _need('Potato', quantity: 2),
            ),
          ],
        ),
        throwsArgumentError,
      );

      final group = BdoPlannerNeedGroup(
        id: 'cooking',
        label: 'Cooking',
        materials: <BdoPlannerNeedMaterial>[
          BdoPlannerNeedMaterial(
            id: 'potato',
            need: _need('Potato', quantity: 1),
          ),
        ],
      );
      final restored = BdoPlannerNeedSelection(
        groups: <BdoPlannerNeedGroup>[group],
        selectedMaterialKeys: <BdoPlannerNeedKey>{
          const BdoPlannerNeedKey(
            groupId: 'cooking',
            materialId: 'removed-item',
          ),
        },
      );

      expect(restored.selectedMaterialKeys, isEmpty);
    });
  });

  group('BdoGroupedRecipeNodeRecommendationService', () {
    test('optimizes checked Cooking and Alchemy needs in one shared route', () {
      final selection = _selection(
        cooking: <BdoPlannerNeedMaterial>[
          BdoPlannerNeedMaterial(
            id: 'ash',
            need: _need('Ash Timber', quantity: 12),
          ),
        ],
        alchemy: <BdoPlannerNeedMaterial>[
          BdoPlannerNeedMaterial(
            id: 'iron',
            need: _need('Iron Ore', quantity: 7, gameItemId: 200),
          ),
        ],
      );

      final result = const BdoGroupedRecipeNodeRecommendationService()
          .recommend(
            data: _sharedDataset(),
            request: BdoGroupedRecipeNodeRecommendationRequest(
              selection: selection,
              contributionPointBudget: 20,
            ),
          );

      expect(result.selectedMaterialCount, 2);
      expect(result.selectedPositiveMaterialCount, 2);
      expect(result.mappedSelectedMaterialCount, 2);
      expect(result.unmappedSelectedMaterialCount, 0);
      expect(result.mappedResourceCount, 2);
      expect(result.mapsEverySelectedMaterial, isTrue);
      expect(
        result.recommendation.networkResult!.plan!.totalContributionPoints,
        4,
      );
      expect(
        result.recommendation.networkResult!.plan!.selectedProductionNodeIds,
        <String>['ore-shared', 'wood-shared'],
      );
    });

    test('counts duplicate cross-mode needs as two rows and one resource', () {
      final result = const BdoGroupedRecipeNodeRecommendationService()
          .recommend(
            data: _sharedDataset(),
            request: BdoGroupedRecipeNodeRecommendationRequest(
              selection: _selection(
                cooking: <BdoPlannerNeedMaterial>[
                  BdoPlannerNeedMaterial(
                    id: 'ash-log',
                    need: _need('Ash Log', quantity: 2),
                  ),
                ],
                alchemy: <BdoPlannerNeedMaterial>[
                  BdoPlannerNeedMaterial(
                    id: 'ash-timber',
                    need: _need('Ash Timber', quantity: 3),
                  ),
                ],
              ),
              contributionPointBudget: 20,
            ),
          );

      expect(result.selectedPositiveMaterialCount, 2);
      expect(result.mappedSelectedMaterialCount, 2);
      expect(result.mappedResourceCount, 1);
      expect(result.recommendation.coverageTargets, hasLength(1));
      expect(
        result.recommendation.coverageTargets.single.recipeShortageInputCount,
        2,
      );
      expect(
        result
            .recommendation
            .coverageTargets
            .single
            .totalRecipeShortageQuantity,
        5,
      );
    });

    test('reports selected, mapped, and unmapped row counts honestly', () {
      final result = const BdoGroupedRecipeNodeRecommendationService()
          .recommend(
            data: _sharedDataset(),
            request: BdoGroupedRecipeNodeRecommendationRequest(
              selection: _selection(
                cooking: <BdoPlannerNeedMaterial>[
                  BdoPlannerNeedMaterial(
                    id: 'ash',
                    need: _need('Ash Timber', quantity: 1),
                  ),
                  BdoPlannerNeedMaterial(
                    id: 'missing',
                    need: _need('Unknown Ingredient', quantity: 4),
                  ),
                ],
                alchemy: <BdoPlannerNeedMaterial>[
                  BdoPlannerNeedMaterial(
                    id: 'unchecked',
                    need: _need('Iron Ore', quantity: 1),
                    selectedByDefault: false,
                  ),
                ],
              ),
              contributionPointBudget: 20,
            ),
          );

      expect(result.totalMaterialCount, 3);
      expect(result.selectedMaterialCount, 2);
      expect(result.selectedPositiveMaterialCount, 2);
      expect(result.mappedSelectedMaterialCount, 1);
      expect(result.unmappedSelectedMaterialCount, 1);
      expect(result.mappedResourceCount, 1);
      expect(result.mapsEverySelectedMaterial, isFalse);
      expect(
        result.recommendation.uncoveredMaterials.single.reason,
        BdoRecipeNodeUncoveredReason.unmatchedMaterial,
      );
    });

    test('excludes direct vendor materials from worker coverage', () {
      final vendorNeed = BdoPlannerMaterialNeed(
        name: 'Iron Ore',
        missingQuantity: 7,
        marketable: true,
        stockKnown: true,
        stock: 0,
        marketRegion: 'EU',
        marketFetchedAt: DateTime.utc(2026, 7, 30),
        gameItemId: 200,
        vendorPurchaseAvailable: true,
        reviewedWorkerRoute: true,
      );
      final result = const BdoGroupedRecipeNodeRecommendationService()
          .recommend(
            data: _sharedDataset(),
            request: BdoGroupedRecipeNodeRecommendationRequest(
              selection: _selection(
                cooking: <BdoPlannerNeedMaterial>[
                  BdoPlannerNeedMaterial(id: 'vendor-ore', need: vendorNeed),
                ],
                alchemy: <BdoPlannerNeedMaterial>[
                  BdoPlannerNeedMaterial(
                    id: 'ash',
                    need: _need('Ash Timber', quantity: 2),
                  ),
                ],
              ),
              contributionPointBudget: 20,
            ),
          );

      expect(result.selectedPositiveMaterialCount, 1);
      expect(result.recommendation.requestedDistinctNodeCountsByResource, {
        'wood': 1,
      });
    });

    test(
      'can request every mapped node for bundled recipe materials',
      () async {
        final data = await BdoResourceMapLoader.loadBundled();
        final ash = data.resources.singleWhere(
          (resource) => resource.name == 'Ash Timber',
        );
        final iron = data.resources.singleWhere(
          (resource) => resource.name == 'Iron Ore',
        );
        final result = const BdoGroupedRecipeNodeRecommendationService()
            .recommend(
              data: data,
              request: BdoGroupedRecipeNodeRecommendationRequest(
                selection: _selection(
                  cooking: <BdoPlannerNeedMaterial>[
                    BdoPlannerNeedMaterial(
                      id: 'ash',
                      need: _need('Ash Timber', quantity: 2),
                    ),
                  ],
                  alchemy: <BdoPlannerNeedMaterial>[
                    BdoPlannerNeedMaterial(
                      id: 'iron',
                      need: _need('Iron Ore', quantity: 2),
                    ),
                  ],
                ),
                contributionPointBudget: 250,
                materialTargets: <BdoRecipeNodeMaterialTarget>[
                  BdoRecipeNodeMaterialTarget(
                    query: ash.id,
                    distinctProductionNodeCount: data
                        .workerNodesForResource(ash.id)
                        .length,
                  ),
                  BdoRecipeNodeMaterialTarget(
                    query: iron.id,
                    distinctProductionNodeCount: data
                        .workerNodesForResource(iron.id)
                        .length,
                  ),
                ],
              ),
            );

        expect(
          result.recommendation.networkResult?.plan,
          isNotNull,
          reason: result.recommendation.networkResult?.diagnostics
              .map((item) => '${item.code}: ${item.message}')
              .join('\n'),
        );
      },
    );
  });
}

BdoPlannerNeedSelection _selection({
  required List<BdoPlannerNeedMaterial> cooking,
  required List<BdoPlannerNeedMaterial> alchemy,
}) => BdoPlannerNeedSelection(
  groups: <BdoPlannerNeedGroup>[
    BdoPlannerNeedGroup(id: 'cooking', label: 'Cooking', materials: cooking),
    BdoPlannerNeedGroup(id: 'alchemy', label: 'Alchemy', materials: alchemy),
  ],
);

BdoPlannerMaterialNeed _need(
  String name, {
  required double quantity,
  int? gameItemId,
  double stock = 0,
}) => BdoPlannerMaterialNeed(
  name: name,
  missingQuantity: quantity,
  marketable: gameItemId != null,
  stockKnown: true,
  stock: stock,
  marketRegion: 'EU',
  marketFetchedAt: DateTime.utc(2026, 7, 29),
  gameItemId: gameItemId,
  vendorPurchaseAvailable: false,
  reviewedWorkerRoute: true,
);

BdoResourceMapDataset _sharedDataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'grouped-recipe-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'test',
    provenance: const <BdoProvenanceRecord>[],
  ),
  resources: const <BdoResourceDefinition>[
    BdoResourceDefinition(
      id: 'wood',
      name: 'Ash Timber',
      gameItemId: 100,
      category: 'Wood',
      section: BdoResourceSection.plantsWood,
      aliases: <String>['Ash Log'],
      acquisitionModes: <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
    ),
    BdoResourceDefinition(
      id: 'ore',
      name: 'Iron Ore',
      gameItemId: 200,
      category: 'Ore',
      section: BdoResourceSection.oresMinerals,
      aliases: <String>[],
      acquisitionModes: <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
    ),
  ],
  workerNodes: const <BdoWorkerNode>[
    BdoWorkerNode(
      id: 'root',
      name: 'Root',
      nodeType: 'City',
      region: 'Test',
      location: BdoWorldPoint(0, 0),
      contributionPoints: 0,
      linkIds: <String>['shared'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'shared',
      name: 'Shared path',
      nodeType: 'Connection',
      region: 'Test',
      location: BdoWorldPoint(1, 0),
      contributionPoints: 2,
      linkIds: <String>['root', 'wood-shared', 'ore-shared'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'wood-shared',
      name: 'Ash Forest',
      nodeType: 'Lumbering',
      region: 'Test',
      location: BdoWorldPoint(2, 0),
      contributionPoints: 1,
      linkIds: <String>['shared'],
      outputs: <BdoNodeOutput>[
        BdoNodeOutput(
          resourceId: 'wood',
          gameItemId: 100,
          name: 'Ash Timber',
          isPrimary: true,
        ),
      ],
      isResourceNode: true,
      isProductionNode: true,
      parentId: 'shared',
    ),
    BdoWorkerNode(
      id: 'ore-shared',
      name: 'Iron Mine',
      nodeType: 'Mining',
      region: 'Test',
      location: BdoWorldPoint(2, 1),
      contributionPoints: 1,
      linkIds: <String>['shared'],
      outputs: <BdoNodeOutput>[
        BdoNodeOutput(
          resourceId: 'ore',
          gameItemId: 200,
          name: 'Iron Ore',
          isPrimary: true,
        ),
      ],
      isResourceNode: true,
      isProductionNode: true,
      parentId: 'shared',
    ),
  ],
  gatheringSpots: const <BdoGatheringSpot>[],
  gatheringRoutes: const <BdoGatheringRoute>[],
);
