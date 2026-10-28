import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_map_core/bdo_map_core.dart';

Recipe workerRecipe(
  String name,
  Map<String, double> ingredients, {
  double output = 1,
}) => Recipe(
  name: name,
  type: 'simple_alchemy',
  baseOutput: output,
  group: null,
  method: null,
  ingredients: [
    for (final e in ingredients.entries)
      Ingredient(
        name: e.key,
        quantity: e.value,
        options: [e.key],
        substituteGroup: null,
        substituteRatios: {},
      ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

RecipeWorkerCatalog workerCatalog() => RecipeWorkerCatalog({
  'Target': workerRecipe('Target', {'Part': 2, 'Other': 1, 'Milk': 3}),
  'Part': workerRecipe('Part', {'A': 5, 'B': 1}),
  'Other': workerRecipe('Other', {'A': 2}),
}, PlannerRules());

BdoResourceMapDataset workerMap() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'test',
    provenance: [],
  ),
  resources: [
    for (final r in ['A', 'B'])
      BdoResourceDefinition(
        id: r,
        name: r,
        gameItemId: r == 'A' ? 1 : 2,
        category: 'Test',
        section: BdoResourceSection.other,
        aliases: [],
        acquisitionModes: {BdoAcquisitionMode.workerNode},
      ),
  ],
  workerNodes: [
    _node('root', 0, ['bridge'], type: 'Town'),
    _node('bridge', 2, ['root']),
    for (final r in ['A', 'B'])
      for (var i = 0; i < 6; i++) _node('$r$i', 1, ['bridge'], output: r),
  ],
  gatheringSpots: [],
  gatheringRoutes: [],
);
BdoWorkerNode _node(
  String id,
  int cp,
  List<String> links, {
  String type = 'Connection',
  String? output,
}) => BdoWorkerNode(
  id: id,
  name: id,
  nodeType: output == null ? type : 'Gathering',
  region: 'Test',
  location: const BdoWorldPoint(0, 0),
  contributionPoints: cp,
  linkIds: links,
  outputs: [
    if (output != null)
      BdoNodeOutput(
        resourceId: output,
        name: output,
        gameItemId: output == 'A' ? 1 : 2,
        isPrimary: true,
      ),
  ],
  isResourceNode: output != null,
  isProductionNode: output != null,
);

BdoWorkerEconomicsDataset workerEconomics({double bWorkload = 1}) {
  final source = BdoWorkerEconomicsDataset.fromJson(
    jsonDecode(
      File(
        'packages/bdo_map_core/assets/data/worker_economics.json',
      ).readAsStringSync(),
    ),
  );
  return BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: source.manifest,
    townsByNodeId: {
      'root': BdoWorkerTownEconomics(
        nodeId: 'root',
        regionId: 1,
        baseWorkerSlots: 1,
        profiles: source.townsByNodeId.values.first.profiles,
      ),
    },
    productionNodesById: {
      for (final r in ['A', 'B'])
        for (var i = 0; i < 6; i++)
          '$r$i': BdoWorkerProductionEconomics(
            nodeId: '$r$i',
            baseWorkload: r == 'A' ? 1 : bWorkload,
            workerTypes: source.townsByNodeId.values.first.profiles.map(
              (p) => p.workerType,
            ),
            standardYields: {r == 'A' ? 1 : 2: 1},
            giantYields: {},
            luckyBonusYields: {},
            townDistances: {'root': 1},
          ),
    },
  );
}

List<BdoWorkerRecipeDemand> workerDemands({double a = 10, double b = 2}) => [
  BdoWorkerRecipeDemand(
    id: 'A',
    name: 'A',
    quantity: a,
    resourceUnits: {'A': 1},
  ),
  BdoWorkerRecipeDemand(
    id: 'B',
    name: 'B',
    quantity: b,
    resourceUnits: {'B': 1},
  ),
];
