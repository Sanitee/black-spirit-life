import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
  });

  const syntheticSurveyArea = BdoGatheringSpot(
    id: 'gathering:test-nymphamare',
    name: 'Nymphamaré Snake Survey Area',
    region: 'Synthetic test region',
    nearestNode: 'Synthetic test node',
    location: BdoWorldPoint(100000, -295000),
    resourceIds: <String>['item:7922'],
    targets: <BdoGatheringTarget>[
      BdoGatheringTarget(
        name: 'Synthetic Snake',
        tool: 'Butcher Knife',
        resourceIds: <String>['item:7922'],
      ),
    ],
    quality: 'Synthetic test fixture',
    summary: 'Synthetic area used only for model behavior tests.',
    verification: BdoGatheringVerification.independentSurvey,
    provenanceId: 'test-only',
    radiusWorld: 10000,
  );

  test('loads the attributed Stable v17 dataset', () {
    expect(dataset.manifest.schemaVersion, 1);
    expect(dataset.manifest.datasetVersion, '2026.08.16-stable-v1');
    expect(dataset.manifest.provenance, isNotEmpty);
    expect(dataset.workerNodes.length, 1052);
    expect(dataset.resources.length, 356);
    expect(dataset.gatheringSpots, hasLength(3));
    expect(dataset.gatheringPoints, hasLength(13315));
    expect(dataset.fieldSources, hasLength(38));
    expect(dataset.vendorNpcs, hasLength(266));
    expect(dataset.vendorListings, hasLength(1241));
    expect(
      dataset.workerNodes
          .where((node) => node.isResourceNode)
          .map((node) => node.nodeType)
          .toSet(),
      equals(<String>{
        'Excavation',
        'Farm',
        'Fish Drying Yard',
        'Gathering',
        'Lumbering',
        'Mining',
        'Mushrooms',
      }),
    );
  });

  test('indexes exact NPC sellers for reviewed planner items', () {
    final saltListings = dataset.vendorListingsForItem(' salt ');
    final saltVendors = dataset.vendorNpcsForItem('SALT');
    final strawberryVendors = dataset.vendorNpcsForItem(
      'Strawberry',
      itemId: 7304,
    );

    expect(saltListings, hasLength(46));
    expect(saltVendors, hasLength(46));
    expect(strawberryVendors, hasLength(14));
    expect(
      saltVendors.any(
        (vendor) =>
            vendor.id == 'npc:40013:1:location:0' &&
            vendor.name == 'David Finto' &&
            vendor.role == 'Chef' &&
            vendor.location == const BdoWorldPoint(15362, 76470.3),
      ),
      isTrue,
    );
    final davidSalt = saltListings.singleWhere(
      (listing) => listing.vendorId == 'npc:40013:1:location:0',
    );
    expect(davidSalt.itemId, 9001);
    expect(davidSalt.priceSilver, 20);
    expect(
      dataset.vendorListingsForVendor(davidSalt.vendorId),
      contains(davidSalt),
    );
    expect(
      () => saltListings.clear(),
      throwsUnsupportedError,
      reason: 'Vendor indexes must stay immutable.',
    );
  });

  test('keeps only curated physical NPC locations in the seller index', () {
    const excludedInteractionObjects = <String>{
      'npc:44102:2:location:0',
      'npc:62319:1:location:0',
      'npc:62319:2:location:0',
      'npc:62319:3:location:0',
      'npc:59605:1:location:0',
      'npc:59605:2:location:0',
      'npc:59605:3:location:0',
      'npc:59591:2:location:0',
      'npc:59591:3:location:0',
      'npc:59773:3:location:0',
      'npc:59773:1:location:0',
      'npc:59773:2:location:0',
      'npc:22472:0:location:0',
      'npc:22388:0:location:0',
      'npc:59591:1:location:0',
    };
    expect(
      dataset.vendorNpcsById.keys.toSet().intersection(
        excludedInteractionObjects,
      ),
      isEmpty,
    );
    expect(dataset.vendorNpcsById, contains('npc:44013:1:location:0'));
    expect(dataset.vendorNpcsById, isNot(contains('npc:44013:1:location:1')));
    expect(dataset.vendorNpcsById, contains('npc:40605:1:location:0'));
    expect(dataset.vendorNpcsById, isNot(contains('npc:40605:2:location:0')));
    expect(dataset.vendorNpcsById, contains('npc:45124:1:location:0'));
    expect(dataset.vendorNpcsById, isNot(contains('npc:45322:1:location:0')));
  });

  test('indexes the reviewed Spellbound Catalyst Old Moon sellers', () {
    final listings = dataset.vendorListingsForItem(
      'Spellbound Catalyst',
      itemId: 820936,
    );
    final vendors = dataset.vendorNpcsForItem(
      'Spellbound Catalyst',
      itemId: 820936,
    );

    expect(listings, hasLength(10));
    expect(vendors, hasLength(10));
    expect(listings.every((listing) => listing.priceSilver == 1000000), isTrue);
    expect(
      vendors.map((vendor) => vendor.name).toSet(),
      containsAll(<String>{'Jak', 'Klau', 'Lajee', 'Mene', 'Ploux', 'Sahin'}),
    );
  });

  test('every mapped NPC seller is inside the active basemap', () {
    final bounds = BdoTileSource.workermanCommunity.worldBounds;
    final outside = dataset.vendorNpcs
        .where((vendor) => !bounds.contains(vendor.location.mapPoint))
        .map((vendor) => vendor.id)
        .toList(growable: false);

    expect(outside, isEmpty);
  });

  test('loads the curated resource sections with stable totals', () {
    const expectedCounts = <BdoResourceSection, int>{
      BdoResourceSection.plantsWood: 123,
      BdoResourceSection.oresMinerals: 58,
      BdoResourceSection.meat: 18,
      BdoResourceSection.bloodHides: 30,
      BdoResourceSection.mushrooms: 27,
      BdoResourceSection.seafoodMarine: 57,
      BdoResourceSection.other: 43,
    };

    for (final entry in expectedCounts.entries) {
      final resources = dataset.resourcesForSection(entry.key);
      expect(resources, hasLength(entry.value), reason: entry.key.name);
      expect(
        resources.every((resource) => resource.section == entry.key),
        isTrue,
        reason: entry.key.name,
      );
      expect(
        () => resources.clear(),
        throwsUnsupportedError,
        reason: '${entry.key.name} index must be immutable',
      );
    }
    expect(
      expectedCounts.values.reduce((left, right) => left + right),
      dataset.resources.length,
    );

    const expectedSections = <int, BdoResourceSection>{
      4605: BdoResourceSection.plantsWood,
      5406: BdoResourceSection.plantsWood,
      5522: BdoResourceSection.plantsWood,
      5804: BdoResourceSection.bloodHides,
      6001: BdoResourceSection.bloodHides,
      6013: BdoResourceSection.bloodHides,
      6201: BdoResourceSection.bloodHides,
      7901: BdoResourceSection.meat,
      5851: BdoResourceSection.plantsWood,
      5852: BdoResourceSection.plantsWood,
      5853: BdoResourceSection.plantsWood,
      5854: BdoResourceSection.plantsWood,
      5960: BdoResourceSection.other,
      4476: BdoResourceSection.seafoodMarine,
      4477: BdoResourceSection.seafoodMarine,
      4998: BdoResourceSection.oresMinerals,
      6501: BdoResourceSection.seafoodMarine,
      6504: BdoResourceSection.seafoodMarine,
      6509: BdoResourceSection.seafoodMarine,
      6511: BdoResourceSection.seafoodMarine,
      6515: BdoResourceSection.seafoodMarine,
      6516: BdoResourceSection.seafoodMarine,
      6533: BdoResourceSection.seafoodMarine,
      6656: BdoResourceSection.other,
      6657: BdoResourceSection.other,
      7360: BdoResourceSection.plantsWood,
      7702: BdoResourceSection.other,
      7921: BdoResourceSection.meat,
      8246: BdoResourceSection.seafoodMarine,
      9064: BdoResourceSection.other,
      752023: BdoResourceSection.oresMinerals,
      821255: BdoResourceSection.seafoodMarine,
    };
    for (final entry in expectedSections.entries) {
      expect(
        dataset.resourcesById['item:${entry.key}']!.section,
        entry.value,
        reason: 'item:${entry.key}',
      );
    }
  });

  test('reuses immutable O(1) resource-source indexes', () {
    final potatoNodes = dataset.workerNodesForResource('item:7003');
    expect(
      identical(potatoNodes, dataset.workerNodesForResource('item:7003')),
      isTrue,
    );
    expect(
      () => (potatoNodes as List<BdoWorkerNode>).clear(),
      throwsUnsupportedError,
    );

    final snakeSpots = dataset.gatheringSpotsForResource('item:7922');
    final snakePoints = dataset.gatheringPointsForResource('item:7922');
    final snakeRoutes = dataset.gatheringRoutesForResource('item:7922');
    expect(
      identical(snakeSpots, dataset.gatheringSpotsForResource('item:7922')),
      isTrue,
    );
    expect(
      identical(snakePoints, dataset.gatheringPointsForResource('item:7922')),
      isTrue,
    );
    expect(
      identical(snakeRoutes, dataset.gatheringRoutesForResource('item:7922')),
      isTrue,
    );
    expect(
      () => (snakePoints as List<BdoGatheringPoint>).clear(),
      throwsUnsupportedError,
    );

    expect(dataset.hasWorkerSource('item:7003'), isTrue);
    expect(dataset.hasMappedManualSource('item:7003'), isFalse);
    expect(dataset.hasWorkerSource('item:7922'), isFalse);
    expect(dataset.hasMappedManualSource('item:7922'), isTrue);
    expect(dataset.hasWorkerSource('item:821255'), isFalse);
    expect(dataset.hasMappedManualSource('item:821255'), isTrue);
    expect(dataset.hasWorkerSource('item:missing'), isFalse);
    expect(dataset.hasMappedManualSource('item:missing'), isFalse);
  });

  test('links Citron to both the real worker node and named orchard focus', () {
    final resource = dataset.resourcesById['item:7360']!;
    final workerNodes = dataset.workerNodesForResource(resource.id);
    final spots = dataset.gatheringSpotsForResource(resource.id);
    final sources = dataset.fieldSourcesForResource(resource.id);

    expect(resource.name, 'Citron');
    expect(resource.section, BdoResourceSection.plantsWood);
    expect(resource.acquisitionModes, contains(BdoAcquisitionMode.workerNode));
    expect(
      resource.acquisitionModes,
      contains(BdoAcquisitionMode.fieldGathering),
    );
    expect(workerNodes.map((node) => node.id), contains('1768'));
    expect(spots, hasLength(1));
    expect(spots.single.id, 'gathering:maslans-yulas-citron-orchard');
    expect(spots.single.radiusWorld, isNull);
    expect(spots.single.targets.single.name, 'Citron Tree');
    expect(spots.single.targets.single.gameNpcIds, <int>[11989]);
    expect(
      sources.map((source) => source.id),
      contains('field-source:citron-tree'),
    );
    expect(dataset.hasWorkerSource(resource.id), isTrue);
    expect(dataset.hasMappedManualSource(resource.id), isTrue);
  });

  test('loads all current numeric nodes and deduplicates client extracts', () {
    expect(
      dataset.workerNodes.where((node) => node.id.startsWith('client:')),
      isEmpty,
    );
    expect(dataset.workerNodesById, hasLength(1052));
    expect(
      dataset.workerNodes
          .where((node) => node.isProductionNode)
          .toList(growable: false),
      hasLength(442),
    );
    expect(
      dataset.workerNodes.where((node) => !node.isProductionNode),
      hasLength(610),
    );
    expect(
      dataset.workerNodes.where((node) => node.sourceLayerFlag == 1),
      hasLength(610),
    );
    expect(
      dataset.workerNodes.where((node) => node.sourceLayerFlag == 0),
      hasLength(442),
    );
    final unlinkedProductionRows = dataset.workerNodes
        .where((node) => node.isProductionNode && node.parentId == null)
        .toList(growable: false);
    expect(unlinkedProductionRows, hasLength(5));
    expect(
      unlinkedProductionRows.every((node) => node.sourceLayerFlag == 0),
      isTrue,
    );
    expect(
      unlinkedProductionRows.where((node) => node.isResourceNode),
      hasLength(4),
    );
    expect(
      unlinkedProductionRows.where((node) => node.nodeType == 'Workshop'),
      isEmpty,
    );
    expect(
      unlinkedProductionRows.where((node) => node.nodeType == 'Connection'),
      hasLength(1),
    );
    expect(
      dataset.workerNodes.where(
        (node) => node.isProductionNode && node.parentId != null,
      ),
      hasLength(437),
    );
    expect(
      dataset.resources.every(
        (resource) => dataset
            .workerNodesForResource(resource.id)
            .every((node) => node.isResourceNode),
      ),
      isTrue,
      reason:
          'Banks, specialties, and workshops stay searchable as nodes but '
          'must not become worker-material sources.',
    );
    expect(
      dataset.workerNodesForResource('item:4001').map((node) => node.id),
      isNot(contains(anyOf('1734', '1735', '1736', '1737'))),
    );
    const reviewedParents = <String, String>{
      '206': '66',
      '207': '72',
      '208': '72',
      '209': '63',
      '1677': '1668',
      '1678': '1668',
      '1717': '1704',
      '1720': '1704',
      '1734': '1007',
      '1735': '1008',
      '1736': '1099',
      '1737': '1100',
    };
    for (final entry in reviewedParents.entries) {
      final child = dataset.workerNodesById[entry.key]!;
      final parent = dataset.workerNodesById[entry.value]!;
      expect(child.parentId, entry.value, reason: entry.key);
      expect(child.linkIds, contains(entry.value), reason: entry.key);
      expect(parent.linkIds, contains(entry.key), reason: entry.value);
      expect(child.name, isNot(contains('Unlinked map record')));
    }
    expect(
      dataset.workerNodes.every(
        (node) =>
            node.provenanceId ==
            'bdo-codex-current-worldmap-nodes-2026-08-15-reference',
      ),
      isTrue,
    );

    for (final node in dataset.workerNodes) {
      for (final linkId in node.linkIds) {
        final linked = dataset.workerNodesById[linkId];
        expect(linked, isNotNull, reason: '${node.id} -> $linkId');
        expect(
          linked!.linkIds,
          contains(node.id),
          reason: '$linkId must link back to ${node.id}',
        );
      }
      for (final output in node.outputs) {
        expect(
          dataset.resourcesById[output.resourceId],
          isNotNull,
          reason: '${node.id} -> ${output.resourceId}',
        );
      }
      if (node.parentId != null) {
        expect(node.linkIds, contains(node.parentId), reason: node.id);
      }
      if (node.isResourceNode) {
        expect(() => node.activity, returnsNormally, reason: node.id);
      }
    }

    final ancientRuins = dataset.workerNodesById['2037']!;
    expect(ancientRuins.name, 'Ancient Ruins - Lumbering');
    expect(ancientRuins.parentId, '2030');
    expect(
      ancientRuins.outputs.map((output) => output.resourceId),
      containsAll(<String>['item:4624', 'item:5025']),
    );
    final frozenHalo = dataset.workerNodesById['2054']!;
    expect(frozenHalo.name, 'Frozen Halo - Gathering');
    expect(
      frozenHalo.outputs.map((output) => output.name),
      containsAll(<String>['Purified Water', 'Bag of Muddy Water']),
    );
    expect(dataset.workerNodesById, containsPair('2084', isNotNull));
  });

  test('normalizes production nodes into stable worker activities', () {
    final counts = <BdoWorkerActivity, int>{
      for (final activity in BdoWorkerActivity.values)
        activity: dataset.workerNodes
            .where((node) => node.isResourceNode && node.activity == activity)
            .length,
    };

    expect(counts, <BdoWorkerActivity, int>{
      BdoWorkerActivity.mining: 84,
      BdoWorkerActivity.farming: 58,
      BdoWorkerActivity.lumbering: 79,
      BdoWorkerActivity.gathering: 59,
      BdoWorkerActivity.fishing: 41,
      BdoWorkerActivity.excavation: 45,
    });
    expect(counts.values.reduce((left, right) => left + right), 366);

    final result = dataset
        .search('primal giant post')
        .firstWhere((entry) => entry.kind == BdoSearchKind.workerNode);
    expect(result.title, 'Lead Ore · Primal Giant Post');
  });

  test('indexes every current map node by its meaningful name', () {
    for (final node in dataset.workerNodes) {
      final matches = dataset.search(node.name, limit: 2000);
      expect(
        matches.any(
          (result) =>
              result.kind == BdoSearchKind.workerNode && result.id == node.id,
        ),
        isTrue,
        reason: '${node.id}: ${node.name}',
      );
      expect(node.sourceIconType, isNotNull, reason: node.id);
    }

    expect(
      dataset
          .search('Neruda Shen Investment Bank', limit: 2000)
          .where((result) => result.kind == BdoSearchKind.workerNode),
      isNotEmpty,
    );
    expect(
      dataset
          .search("Chiro's Figurehead Workshop", limit: 2000)
          .where((result) => result.kind == BdoSearchKind.workerNode),
      isNotEmpty,
    );
  });

  test('contains the official June 2026 node additions and output changes', () {
    void expectOutputs(String nodeId, Iterable<String> expected) {
      expect(
        dataset.workerNodesById[nodeId]!.outputs
            .map((output) => output.name)
            .toSet(),
        containsAll(expected),
        reason: nodeId,
      );
    }

    expect(dataset.workerNodesById['201']!.name, 'Wolf Hills - Lumbering');
    expectOutputs('201', <String>['Ash Timber', 'Ash Sap']);
    expectOutputs('1675', <String>['Thuja Timber', 'Thuja Plank', 'Thuja Sap']);
    expectOutputs('2060', <String>['Cedar Timber', 'Cedar Sap']);
    expectOutputs('2068', <String>['Thornwood Timber', 'Thornwood Sap']);
    expectOutputs('2058', <String>['Trace of Nature', 'Rough Black Crystal']);
    expectOutputs('2079', <String>['Trace of Nature', 'Rough Violet Crystal']);

    for (final query in <String>[
      'Wolf Hills Ash Sap',
      'Gervish Mountains Thuja Sap',
      'Blood Wolf Settlement Cedar Sap',
      "La O'delle Thornwood Sap",
      'Pila Fe Rough Violet Crystal',
    ]) {
      expect(
        dataset
            .search(query, limit: 2000)
            .where((result) => result.kind == BdoSearchKind.workerNode),
        isNotEmpty,
        reason: query,
      );
    }

    final official = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'pearl-abyss-production-node-update-2026-06-04',
    );
    expect(official.url.toString(), contains('_boardNo=13267'));
    expect(official.permittedUse, contains('Wolf Hills'));
  });

  test('maps only known worker activity types and fails closed', () {
    const cases =
        <({String nodeType, String name, BdoWorkerActivity expected})>[
          (
            nodeType: 'Excavation',
            name: 'Test Site - Excavation',
            expected: BdoWorkerActivity.excavation,
          ),
          (
            nodeType: 'Farm',
            name: 'Test Farm - Potato Farming',
            expected: BdoWorkerActivity.farming,
          ),
          (
            nodeType: 'Fish Drying Yard',
            name: 'Test Coast - Fish Drying Yard',
            expected: BdoWorkerActivity.fishing,
          ),
          (
            nodeType: 'Fishing',
            name: 'Fish Drying Yard 1',
            expected: BdoWorkerActivity.fishing,
          ),
          (
            nodeType: 'Forest',
            name: 'Test Forest - Lumbering',
            expected: BdoWorkerActivity.lumbering,
          ),
          (
            nodeType: 'Lumbering',
            name: 'Test Woods - Lumbering',
            expected: BdoWorkerActivity.lumbering,
          ),
          (
            nodeType: 'Gathering',
            name: 'Test Field - Gathering',
            expected: BdoWorkerActivity.gathering,
          ),
          (
            nodeType: 'Mushrooms',
            name: 'Test Cave - Gathering',
            expected: BdoWorkerActivity.gathering,
          ),
          (
            nodeType: 'Mining',
            name: 'Test Quarry - Mining',
            expected: BdoWorkerActivity.mining,
          ),
          (
            nodeType: 'Mine',
            name: 'Test Ruins - Excavation',
            expected: BdoWorkerActivity.excavation,
          ),
          (
            nodeType: 'Mine',
            name: 'Test Volcano - Vanadium',
            expected: BdoWorkerActivity.mining,
          ),
        ];

    for (final testCase in cases) {
      expect(
        _workerNode(nodeType: testCase.nodeType, name: testCase.name).activity,
        testCase.expected,
        reason: '${testCase.nodeType}: ${testCase.name}',
      );
    }

    final futureType = _workerNode(
      nodeType: 'Future Production',
      name: 'Future Site - Mining',
    );
    expect(
      () => futureType.activity,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Future Production'), contains(futureType.id)),
        ),
      ),
    );

    final futureMineActivity = _workerNode(
      nodeType: 'Mine',
      name: 'Future Mine - Mythril',
    );
    expect(
      () => futureMineActivity.activity,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Mythril'), contains(futureMineActivity.id)),
        ),
      ),
    );
  });

  test(
    'styles known topology-only nodes without accepting production data',
    () {
      expect(dataset.workerNodes.map((node) => node.nodeType).toSet(), <String>{
        'Bank',
        'City',
        'Connection',
        'Dangerous',
        'Excavation',
        'Farm',
        'Fish Drying Yard',
        'Gateway',
        'Gathering',
        'Lumbering',
        'Mining',
        'Mushrooms',
        'Specialty',
        'Town',
        'Trading Post',
        'Workshop',
      });

      const topologyTypes = <String>{
        'City',
        'Connection',
        'Dangerous',
        'Gateway',
        'Town',
        'Trading Post',
      };
      final topologyNodes = dataset.workerNodes
          .where(
            (node) =>
                topologyTypes.contains(node.nodeType) &&
                !node.isResourceNode &&
                !node.isProductionNode &&
                node.outputs.isEmpty,
          )
          .toList(growable: false);
      expect(topologyNodes, isNotEmpty);
      expect(topologyNodes.map((node) => node.nodeType).toSet(), topologyTypes);
      for (final node in topologyNodes) {
        expect(node.isResourceNode, isFalse, reason: node.id);
        expect(node.isProductionNode, isFalse, reason: node.id);
        expect(node.outputs, isEmpty, reason: node.id);
        expect(
          node.activity,
          BdoWorkerActivity.excavation,
          reason: '${node.id}: ${node.nodeType}',
        );
        expect(node.activityLabel, node.nodeType, reason: node.id);
      }

      final cronCastle = dataset.workerNodesById['3']!;
      expect(cronCastle.name, 'Cron Castle');
      expect(cronCastle.nodeType, 'Dangerous');
      expect(() => cronCastle.activity, returnsNormally);

      final productionDangerous = _workerNode(
        nodeType: 'Dangerous',
        name: 'Invalid Production Site - Dangerous',
        isResourceNode: false,
        isProductionNode: true,
      );
      final outputBearingDangerous = _workerNode(
        nodeType: 'Dangerous',
        name: 'Invalid Output Site - Dangerous',
        isResourceNode: false,
        outputs: const <BdoNodeOutput>[
          BdoNodeOutput(
            resourceId: 'item:test',
            name: 'Test Output',
            isPrimary: true,
          ),
        ],
      );
      final futureTopology = _workerNode(
        nodeType: 'Future Topology',
        name: 'Future Topology Node',
        isResourceNode: false,
      );

      for (final invalid in <BdoWorkerNode>[
        productionDangerous,
        outputBearingDangerous,
        futureTopology,
      ]) {
        expect(
          () => invalid.activity,
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(invalid.id),
            ),
          ),
          reason: invalid.id,
        );
      }
    },
  );

  test('uses current Edania item names and searchable worker results', () {
    expect(dataset.resourcesById['item:5960']!.name, 'Trace of Nature');
    expect(
      dataset.workerNodes
          .expand((node) => node.outputs)
          .where((output) => output.resourceId == 'item:5960')
          .every((output) => output.name == 'Trace of Nature'),
      isTrue,
    );

    final caphrasSap = dataset
        .search('caphras tree sap')
        .firstWhere((result) => result.kind == BdoSearchKind.resource);
    expect(caphrasSap.id, 'item:5025');
    expect(caphrasSap.subtitle, contains('4 worker nodes'));
    expect(
      dataset
          .workerNodesForResource(caphrasSap.resourceId!)
          .map((node) => node.id)
          .toSet(),
      <String>{'2037', '2044', '2119', '2120'},
    );
  });

  test('uses one exact-dot Tshira focus without a broad radius', () {
    final spot =
        dataset.gatheringSpotsById['gathering:tshira-snake-scorpion-rotation']!;
    expect(spot.name, 'Tshira Ruins Snake & Scorpion Rotation');
    expect(spot.radiusWorld, isNull);
    expect(spot.areaBounds, isNull);
    expect(spot.location, const BdoWorldPoint(105950, -299439));
    expect(
      dataset.gatheringPoints.where((point) => point.areaId == spot.id).length,
      29,
    );
  });

  test('adds source-isolated Marni sniper hunting at Beombawi Valley', () {
    final source =
        dataset.fieldSourcesById['field-source:marni-sniper-hunting']!;
    final spot =
        dataset.gatheringSpotsById['gathering:beombawi-marni-sniper-preserve']!;
    const expectedResources = <String>{
      'item:7905',
      'item:6205',
      'item:6005',
      'item:7912',
      'item:6213',
      'item:6013',
      'item:820039',
      'item:820038',
      'item:820037',
      'item:820036',
      'item:820139',
    };

    expect(source.name, 'Marni Sniper Hunting');
    expect(source.category, 'Hunting');
    expect(source.resourceIds.toSet(), expectedResources);
    expect(
      source.products.every(
        (product) =>
            product.method == 'Sniper hunt and butcher' &&
            product.tool == 'Sniper Rifle + Butcher Knife',
      ),
      isTrue,
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:7905')
          .instruction,
      contains('Pork, Pig Blood, and Pig Hide together'),
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:6013')
          .instruction,
      contains('Bear Meat, Bear Blood, and Bear Hide together'),
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:820039')
          .instruction,
      contains('rare sniper-hunting reward from bears'),
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:820038')
          .instruction,
      contains('rare sniper-hunting reward from bears'),
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:820036')
          .instruction,
      contains('not a guaranteed result'),
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:820037')
          .instruction,
      contains('rare sniper-hunting reward from hawks'),
    );
    expect(
      source.products
          .singleWhere((product) => product.resourceId == 'item:820139')
          .instruction,
      contains('rare cooking material'),
    );

    expect(spot.location, const BdoWorldPoint(-1198000, 1389200));
    expect(spot.nearestNode, 'Beombawi Valley');
    expect(spot.radiusWorld, isNull);
    expect(spot.areaBounds, isNull);
    expect(spot.fieldSourceIds, <String>[source.id]);
    expect(spot.resourceIds.toSet(), expectedResources);
    expect(spot.summary, contains('no fake coverage circle'));
    expect(spot.targets.map((target) => target.name), <String>[
      'Sensitive / Atrocious Boar',
      'Sensitive / Atrocious Bear',
      'Sensitive Hawk',
      'Rare Tiger',
    ]);
    expect(
      spot.targets.every(
        (target) => target.tool == 'Sniper Rifle + Butcher Knife',
      ),
      isTrue,
    );
    expect(
      dataset.gatheringSpotsForFieldSource(source.id).map((entry) => entry.id),
      <String>[spot.id],
    );
    expect(dataset.gatheringSpotsForFieldSource('field-source:pig'), isEmpty);
    expect(dataset.gatheringSpotsForFieldSource('field-source:bear'), isEmpty);

    for (final resourceId in expectedResources) {
      expect(
        dataset.resourcesById[resourceId]!.acquisitionModes,
        contains(BdoAcquisitionMode.hunting),
        reason: resourceId,
      );
    }
    expect(
      dataset.search('marni sniper').map((result) => result.id),
      containsAll(<String>[source.id, spot.id]),
    );
    expect(
      dataset.search('pig hunting').map((result) => result.id),
      contains(source.id),
    );
    expect(
      dataset.search('bear hide').map((result) => result.id),
      containsAll(<String>['item:6013', source.id]),
    );
    expect(
      dataset.search('crystal of decimation').map((result) => result.id),
      containsAll(<String>['item:820039', source.id]),
    );
    expect(
      dataset.search('atrocious bear').map((result) => result.id),
      containsAll(<String>[source.id, spot.id]),
    );
    expect(
      dataset.search('crystal of darkness').map((result) => result.id),
      containsAll(<String>['item:820037', source.id]),
    );
    expect(
      dataset.search('live meat').map((result) => result.id),
      containsAll(<String>['item:820139', source.id]),
    );

    final provenance = dataset.manifest.provenance.singleWhere(
      (record) =>
          record.id == 'pearl-abyss-marni-sniper-hunting-guide-2026-08-01',
    );
    expect(provenance.url.host, contains('playblackdesert.com'));
    expect(provenance.permittedUse, contains('region anchor'));
    expect(provenance.permittedUse, contains('not an exact animal spawn'));
  });

  test('records the Edania rights and official cross-check boundaries', () {
    final current = dataset.manifest.provenance.singleWhere(
      (record) =>
          record.id == 'bdo-codex-current-worldmap-nodes-2026-08-15-reference',
    );
    expect(current.url.toString(), 'https://bdocodex.com/us/worldmap/');
    expect(current.license, contains('Pearl Abyss-origin game facts'));
    expect(current.permittedUse, contains('1,052 current records'));
    expect(current.permittedUse, contains('610 raw exploration-layer records'));
    expect(current.permittedUse, contains('442 raw production-layer records'));
    expect(current.permittedUse, contains('425 unique parent-linked children'));
    expect(current.permittedUse, contains('17 upstream'));
    expect(current.permittedUse, contains('Twelve'));
    expect(current.permittedUse, contains('five'));
    expect(current.permittedUse, contains('No parent'));
    expect(current.permittedUse, contains('Raw HTML'));
    expect(current.permittedUse, contains('free noncommercial fan-content'));

    final client = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'na-client-edania-node-facts-2026-reference',
    );
    expect(
      client.url.toString(),
      contains('2e4ace61e2a3967663cb36580edb7201b7ca3fd4'),
    );
    expect(client.license, contains('noncommercial licence'));
    expect(client.license, contains('Pearl Abyss-origin game facts'));
    expect(client.permittedUse, contains('free noncommercial fan-content'));
    expect(client.permittedUse, contains('extractor source'));

    final production2025 = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'pearl-abyss-edania-production-node-facts-2025',
    );
    final frozen2026 = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'pearl-abyss-frozen-halo-node-facts-2026',
    );
    expect(production2025.url.toString(), contains('_boardNo=19155'));
    expect(frozen2026.url.toString(), contains('_boardNo=19517'));
    expect(
      dataset.manifest.provenance.map((record) => record.id),
      isNot(contains('pearl-abyss-edania-hunting-approx-areas-2026')),
    );
    expect(
      dataset.manifest.provenance.map((record) => record.id),
      isNot(contains('tshira-area-independent-synthesis')),
    );

    final animalPoints = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'bdo-codex-drieghan-animal-points-reference',
    );
    expect(animalPoints.url.toString(), contains('/npc/21758/'));
    expect(animalPoints.license, contains('Pearl Abyss-origin game facts'));
    expect(
      animalPoints.permittedUse,
      contains('free noncommercial fan-content'),
    );
    expect(
      animalPoints.permittedUse,
      contains('open to current-game correction'),
    );

    final tshiraRotation = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'bdo-workshop-tshira-rotation-facts-2026',
    );
    expect(
      tshiraRotation.url.toString(),
      'https://bdoworkshop.com/gathering-calculator',
    );
    expect(tshiraRotation.permittedUse, contains('four logged sessions'));
    expect(tshiraRotation.permittedUse, contains('two-to-one'));
    expect(tshiraRotation.permittedUse, contains('no video frames'));

    final vedelona = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'bdo-codex-vedelona-item-facts-2026-07-29',
    );
    expect(vedelona.url.toString(), 'https://bdocodex.com/us/item/5522/');
    expect(vedelona.permittedUse, contains('bare-hands-or-hoe'));
    expect(vedelona.permittedUse, contains('Exact manual plant positions'));
  });

  test('parses gathering-point metadata and optional survey fields', () {
    final point = BdoGatheringPoint.fromJson(<String, Object?>{
      'id': 'gathering-point:survey:1',
      'x': 123.5,
      'z': -456,
      'resourceIds': <String>['item:7922'],
      'target': 'Snake',
      'kind': 'butchering',
      'label': 'Survey point',
      'verification': 'independentSurvey',
      'provenanceId': 'test-survey',
      'areaId': 'gathering:test-area',
      'verifiedAt': '2026-07-28T12:00:00Z',
    });

    expect(point.id, 'gathering-point:survey:1');
    expect(point.location, const BdoWorldPoint(123.5, -456));
    expect(point.resourceIds, <String>['item:7922']);
    expect(point.target, 'Snake');
    expect(point.kind, 'butchering');
    expect(point.label, 'Survey point');
    expect(point.verification, BdoGatheringVerification.independentSurvey);
    expect(point.provenanceId, 'test-survey');
    expect(point.areaId, 'gathering:test-area');
    expect(point.verifiedAt, DateTime.utc(2026, 7, 28, 12));
  });

  test('deduplicates and merges pinned animal-family coordinates', () {
    Set<String> pointIdsFor(String resourceId) {
      return dataset
          .gatheringPointsForResource(resourceId)
          .map((point) => point.id)
          .toSet();
    }

    final snakeMeat = pointIdsFor('item:7922');
    final snakeSkin = pointIdsFor('item:6019');
    final cobraBlood = pointIdsFor('item:6222');
    final scorpionMeat = pointIdsFor('item:7924');
    final scorpionBlood = pointIdsFor('item:6224');
    final lambMeat = pointIdsFor('item:7902');
    final sheepBlood = pointIdsFor('item:6202');
    final sheepHide = pointIdsFor('item:6002');

    expect(snakeMeat, hasLength(657));
    expect(snakeSkin, hasLength(133));
    expect(cobraBlood, snakeSkin);
    expect(snakeMeat, containsAll(snakeSkin));
    expect(scorpionMeat, hasLength(475));
    expect(scorpionBlood, hasLength(240));
    expect(scorpionMeat, containsAll(scorpionBlood));
    expect(lambMeat, hasLength(1068));
    expect(sheepBlood, lambMeat);
    expect(sheepHide, lambMeat);
    expect(<String>{
      ...snakeMeat,
      ...scorpionMeat,
      ...lambMeat,
    }, hasLength(2200));
    expect(dataset.gatheringPointsById, hasLength(13315));
    expect(
      dataset.gatheringPoints
          .map(
            (point) =>
                '${point.location.x.toStringAsFixed(6)},'
                '${point.location.z.toStringAsFixed(6)}',
          )
          .toSet(),
      hasLength(dataset.gatheringPoints.length),
    );
    expect(
      dataset.gatheringPointsById['gathering-point:390825:49175']!.resourceIds,
      <String>['item:6019', 'item:6222', 'item:7922'],
    );
    final knownSnakePoint =
        dataset.gatheringPointsById['gathering-point:390825:49175']!;
    expect(knownSnakePoint.target, 'Snake');
    expect(knownSnakePoint.kind, 'butchering / fluid collecting / tanning');
    expect(knownSnakePoint.label, 'Historical snake gathering location');
    expect(knownSnakePoint.areaId, isNull);
    expect(knownSnakePoint.verifiedAt, isNull);
    expect(
      dataset
          .gatheringPointsById['gathering-point:-19000:-366881']!
          .resourceIds,
      <String>['item:6224', 'item:7924'],
    );
    final knownScorpionPoint =
        dataset.gatheringPointsById['gathering-point:-19000:-366881']!;
    expect(knownScorpionPoint.target, 'Scorpion');
    expect(knownScorpionPoint.kind, 'butchering / fluid collecting');
    expect(knownScorpionPoint.label, 'Historical scorpion gathering location');
    final knownSheepPoint =
        dataset.gatheringPointsById['gathering-point:-25551:126']!;
    expect(knownSheepPoint.resourceIds, <String>[
      'item:6002',
      'item:6202',
      'item:7902',
    ]);
    expect(knownSheepPoint.target, 'Sheep');
    expect(knownSheepPoint.kind, 'butchering / fluid collecting / tanning');
    expect(knownSheepPoint.label, 'Historical sheep gathering location');
    expect(
      dataset.resourcesById['item:7922']!.acquisitionModes,
      <BdoAcquisitionMode>{
        BdoAcquisitionMode.fieldGathering,
        BdoAcquisitionMode.hunting,
      },
    );
    expect(
      dataset.resourcesById['item:7922']!.aliases,
      allOf(contains('cobra'), isNot(contains('golden leaf snake'))),
    );
    expect(
      dataset.resourcesById['item:821259']!.aliases,
      contains('golden leaf snake'),
    );
    expect(
      dataset.resourcesById['item:7902']!.acquisitionModes,
      <BdoAcquisitionMode>{
        BdoAcquisitionMode.fieldGathering,
        BdoAcquisitionMode.hunting,
      },
    );
    expect(
      dataset.resourcesById['item:7902']!.aliases,
      containsAll(<String>['cliffside mountain sheep', 'lamb']),
    );
    for (final resourceId in <String>[
      'item:6002',
      'item:6019',
      'item:6202',
      'item:6222',
      'item:6224',
      'item:7924',
    ]) {
      expect(
        dataset.resourcesById[resourceId]!.acquisitionModes,
        <BdoAcquisitionMode>{BdoAcquisitionMode.fieldGathering},
        reason: resourceId,
      );
    }
    expect(
      dataset.gatheringPoints
          .where(
            (point) =>
                point.provenanceId == 'somethinglovely-mit-gathering-points',
          )
          .every(
            (point) => point.verification == BdoGatheringVerification.stale,
          ),
      isTrue,
    );
  });

  test('loads the prioritized historical material layers', () {
    const expectedCounts = <String, int>{
      'item:5420': 96,
      'item:5406': 112,
      'item:5601': 142,
      'item:5602': 142,
      'item:4616': 591,
      'item:5020': 591,
      'item:5538': 752,
      'item:5526': 966,
      'item:5517': 50,
    };

    for (final entry in expectedCounts.entries) {
      final resource = dataset.resourcesById[entry.key]!;
      final points = dataset
          .gatheringPointsForResource(entry.key)
          .toList(growable: false);
      expect(
        resource.acquisitionModes,
        contains(BdoAcquisitionMode.fieldGathering),
        reason: entry.key,
      );
      expect(points, hasLength(entry.value), reason: entry.key);
      expect(
        points.every(
          (point) =>
              point.verification == BdoGatheringVerification.stale &&
              point.provenanceId == 'somethinglovely-mit-gathering-points',
        ),
        isTrue,
        reason: entry.key,
      );
    }

    expect(
      dataset
          .gatheringPointsForResource('item:5601')
          .map((point) => point.id)
          .toSet(),
      dataset
          .gatheringPointsForResource('item:5602')
          .map((point) => point.id)
          .toSet(),
    );
    expect(
      dataset
          .gatheringPointsForResource('item:4616')
          .map((point) => point.id)
          .toSet(),
      dataset
          .gatheringPointsForResource('item:5020')
          .map((point) => point.id)
          .toSet(),
    );
    expect(
      dataset.resourcesById['item:5020']!.acquisitionModes,
      <BdoAcquisitionMode>{
        BdoAcquisitionMode.workerNode,
        BdoAcquisitionMode.fieldGathering,
      },
    );
    expect(
      dataset
          .search('poisonous plant flower')
          .firstWhere((result) => result.kind == BdoSearchKind.resource)
          .id,
      'item:5440',
    );
  });

  test(
    'separates gathered Insectivore products from poisonous-plant drops',
    () {
      final gathered =
          dataset.fieldSourcesById['field-source:insectivore-plant']!;
      final combat =
          dataset.fieldSourcesById['field-source:poisonous-swamp-plant']!;
      final gatheredPoints = dataset
          .gatheringPointsForFieldSource(gathered.id)
          .toList(growable: false);

      expect(gathered.name, 'Insectivore Plant');
      expect(gathered.note, contains('Gathering Beginner 10'));
      expect(
        gathered.products.map((product) => product.resourceId).toSet(),
        <String>{'item:5601', 'item:5602'},
      );
      expect(gatheredPoints, hasLength(142));
      expect(
        gatheredPoints.every(
          (point) =>
              point.fieldSourceIds.contains(gathered.id) &&
              <String>[
                'item:5601',
                'item:5602',
              ].every(point.resourceIds.contains) &&
              !point.resourceIds.any(
                <String>{
                  'item:5440',
                  'item:5441',
                  'item:5442',
                  'item:5443',
                }.contains,
              ),
        ),
        isTrue,
      );

      expect(combat.products, hasLength(4));
      expect(combat.note, contains('far above the plant level'));
      expect(dataset.gatheringPointsForFieldSource(combat.id), isEmpty);
      for (final resourceId in <String>[
        'item:5440',
        'item:5441',
        'item:5442',
        'item:5443',
      ]) {
        expect(dataset.gatheringPointsForResource(resourceId), isEmpty);
        expect(
          dataset
              .fieldSourcesForResource(resourceId)
              .map((source) => source.id),
          contains(combat.id),
        );
      }
    },
  );

  test('explains Vedelona without inventing manual map geometry', () {
    final resource = dataset.resourcesById['item:5522']!;
    final source = dataset.fieldSourcesById['field-source:vedelona-plant']!;

    expect(resource.name, 'Vedelona');
    expect(resource.category, 'Plants & flowers');
    expect(resource.aliases, contains('kamasylvia flower'));
    expect(source.name, 'Vedelona Plant');
    expect(source.products.single.method, 'Gather');
    expect(source.products.single.tool, 'Bare hands / Hoe');
    expect(source.note, contains('does not draw an approximate region'));
    expect(dataset.gatheringPointsForFieldSource(source.id), isEmpty);
    expect(dataset.gatheringPointsForResource(resource.id), isEmpty);
    expect(
      dataset.workerNodesForResource(resource.id).map((node) => node.siteName),
      containsAll(<String>[
        'Tooth Fairy Forest',
        'Looney Cabin',
        'Weenie Cabin',
      ]),
    );
  });

  test('retains the complete reviewed fish-drying-yard output boundary', () {
    final fishNodes = dataset.workerNodes
        .where((node) => node.nodeType == 'Fish Drying Yard')
        .toList(growable: false);
    final driedFishOutputs = fishNodes
        .expand((node) => node.outputs)
        .where((output) => output.name.startsWith('Dried '))
        .map((output) => output.resourceId)
        .toSet();
    final allReviewedOutputs = fishNodes
        .expand((node) => node.outputs)
        .map((output) => output.resourceId)
        .toSet();

    expect(fishNodes, hasLength(42));
    expect(fishNodes.where((node) => node.outputs.isNotEmpty), hasLength(41));
    expect(driedFishOutputs, hasLength(44));
    expect(allReviewedOutputs, hasLength(46));
    expect(
      allReviewedOutputs.difference(driedFishOutputs),
      <String>{'item:1027', 'item:6501'},
      reason:
          "Some Fisher's Sack and Coral Piece are reviewed yard byproducts, "
          'not dried fish.',
    );
    expect(dataset.workerNodesById['1044']!.outputs, isEmpty);
  });

  test('searches by product while resolving the shared field source', () {
    final results = dataset.search('thuja sap');

    expect(results.first.kind, BdoSearchKind.fieldSource);
    expect(results.first.fieldSourceId, 'field-source:thuja-tree');
    expect(
      results
          .where((result) => result.kind == BdoSearchKind.resource)
          .map((result) => result.id),
      contains('item:5020'),
    );
    final source = results.firstWhere(
      (result) =>
          result.kind == BdoSearchKind.fieldSource &&
          result.fieldSourceId == 'field-source:thuja-tree',
    );
    expect(source.title, 'Thuja Tree');
    expect(source.subtitle, contains('Thuja Timber'));
    expect(source.subtitle, contains('Thuja Sap'));
    expect(
      dataset.fieldSourcesForResource('item:5020').map((source) => source.id),
      contains('field-source:thuja-tree'),
    );
  });

  test('loads lightweight representative tree-source layers', () {
    const expectedCounts = <String, int>{
      'field-source:ash-tree': 299,
      'field-source:birch-tree': 300,
      'field-source:cedar-tree': 300,
      'field-source:fir-tree': 300,
      'field-source:maple-tree': 300,
      'field-source:pine-tree': 300,
      'field-source:acacia-tree': 300,
      'field-source:elder-tree': 300,
      'field-source:white-cedar-tree': 300,
      'field-source:thornwood-tree': 155,
    };

    for (final entry in expectedCounts.entries) {
      final source = dataset.fieldSourcesById[entry.key]!;
      final points = dataset
          .gatheringPointsForFieldSource(source.id)
          .toList(growable: false);
      expect(source.category, 'Trees', reason: source.id);
      expect(source.products, hasLength(3), reason: source.id);
      expect(
        source.products.map((product) => product.resourceId),
        contains('item:4605'),
        reason: source.id,
      );
      expect(source.products.map((product) => product.tool).toSet(), <String>{
        'Fluid Collector',
        'Lumbering Axe',
      }, reason: source.id);
      expect(source.note, contains('no coordinates are invented'));
      expect(points, hasLength(entry.value), reason: source.id);
      expect(
        points.every(
          (point) =>
              point.fieldSourceIds.contains(source.id) &&
              point.provenanceId == 'somethinglovely-mit-gathering-points',
        ),
        isTrue,
        reason: source.id,
      );
    }

    expect(dataset.gatheringPointsForResource('item:4605'), hasLength(3445));
    expect(
      dataset
          .fieldSourcesForResource('item:4605')
          .map((source) => source.id)
          .toSet(),
      <String>{...expectedCounts.keys, 'field-source:thuja-tree'},
    );
    expect(
      dataset.fieldSourcesById['field-source:thuja-tree']!.products
          .singleWhere((product) => product.resourceId == 'item:4605')
          .method,
      'Lumber',
    );
  });

  test('reuses one pinned payload per requested animal family', () {
    const families = <({List<String> resourceIds, int pointCount})>[
      (
        resourceIds: <String>['item:6014', 'item:6214', 'item:7913'],
        pointCount: 397,
      ),
      (
        resourceIds: <String>['item:6001', 'item:6201', 'item:7901'],
        pointCount: 549,
      ),
      (
        resourceIds: <String>['item:6003', 'item:6203', 'item:7903'],
        pointCount: 468,
      ),
      (
        resourceIds: <String>['item:6005', 'item:6205', 'item:7905'],
        pointCount: 719,
      ),
      (
        resourceIds: <String>['item:6006', 'item:6206', 'item:7906'],
        pointCount: 531,
      ),
      (
        resourceIds: <String>['item:6013', 'item:6213', 'item:7912'],
        pointCount: 62,
      ),
      (resourceIds: <String>['item:6216', 'item:7915'], pointCount: 61),
      (resourceIds: <String>['item:6218', 'item:7917'], pointCount: 103),
      (
        resourceIds: <String>['item:6008', 'item:6208', 'item:7908'],
        pointCount: 1109,
      ),
      (
        resourceIds: <String>['item:6010', 'item:6210', 'item:7910'],
        pointCount: 176,
      ),
      (
        resourceIds: <String>['item:6012', 'item:6212', 'item:7911'],
        pointCount: 1042,
      ),
      (
        resourceIds: <String>['item:6004', 'item:6204', 'item:7904'],
        pointCount: 103,
      ),
    ];

    for (final family in families) {
      final expectedPointIds = dataset
          .gatheringPointsForResource(family.resourceIds.first)
          .map((point) => point.id)
          .toSet();
      expect(
        expectedPointIds,
        hasLength(family.pointCount),
        reason: family.resourceIds.first,
      );
      for (final resourceId in family.resourceIds) {
        expect(
          dataset.resourcesById[resourceId]!.acquisitionModes,
          contains(BdoAcquisitionMode.fieldGathering),
          reason: resourceId,
        );
        expect(
          dataset
              .gatheringPointsForResource(resourceId)
              .map((point) => point.id)
              .toSet(),
          expectedPointIds,
          reason: resourceId,
        );
      }
    }
  });

  test('loads exact common-animal methods without vendor-source overlap', () {
    const animalProducts = <String, Set<String>>{
      'field-source:wolf': <String>{'item:6014', 'item:6214', 'item:7913'},
      'field-source:deer': <String>{'item:6001', 'item:6201', 'item:7901'},
      'field-source:fox': <String>{'item:6003', 'item:6203', 'item:7903'},
      'field-source:pig': <String>{'item:6005', 'item:6205', 'item:7905'},
      'field-source:cow-ox': <String>{'item:6006', 'item:6206', 'item:7906'},
    };

    for (final entry in animalProducts.entries) {
      final source = dataset.fieldSourcesById[entry.key]!;
      expect(source.category, 'Animals', reason: entry.key);
      expect(
        source.products.map((product) => product.resourceId).toSet(),
        entry.value,
        reason: entry.key,
      );
      expect(source.products.map((product) => product.method).toSet(), <String>{
        'Butcher',
        'Fluid collect',
        'Tan',
      }, reason: entry.key);
      expect(source.products.map((product) => product.tool).toSet(), <String>{
        'Butcher Knife',
        'Fluid Collector',
        'Tanning Knife',
      }, reason: entry.key);
    }

    final everlasting =
        dataset.fieldSourcesById['field-source:everlasting-herb']!;
    expect(everlasting.category, 'Plants');
    expect(everlasting.products.single.resourceId, 'item:5406');
    expect(everlasting.products.single.method, 'Gather');
    expect(everlasting.products.single.tool, 'Bare Hands or Hoe');
    expect(dataset.gatheringPointsForResource('item:5406'), hasLength(112));

    for (final excludedResourceId in <String>{
      'item:5402', // Silver Azalea: vendor/worker alternatives.
      'item:5007', // Monk's Branch: worker-node output.
    }) {
      expect(
        dataset.gatheringPointsForResource(excludedResourceId),
        isEmpty,
        reason: excludedResourceId,
      );
      expect(
        dataset.fieldSourcesForResource(excludedResourceId),
        isEmpty,
        reason: excludedResourceId,
      );
    }
  });

  test("loads exact Rusalka's Coral points without a broad area", () {
    final resource = dataset.resourcesById['item:821255']!;
    final points = dataset
        .gatheringPointsForResource(resource.id)
        .toList(growable: false);

    expect(resource.name, "Rusalka's Coral");
    expect(resource.acquisitionModes, <BdoAcquisitionMode>{
      BdoAcquisitionMode.fieldGathering,
    });
    expect(
      resource.aliases,
      containsAll(<String>[
        'coral stoneback crab',
        'rusalka coral',
        'rusalkas coral',
        'stoneback crab coral',
      ]),
    );
    expect(
      resource.aliases,
      isNot(contains('rusalka crystal')),
      reason: 'Rusalka Crystal is a separate sailing item, not this coral.',
    );
    expect(points, hasLength(34));
    expect(
      points.every(
        (point) =>
            point.verification == BdoGatheringVerification.communityReported &&
            point.provenanceId == 'bdo-codex-rusalka-coral-points-reference' &&
            point.target == 'Coral Stoneback Crab' &&
            point.kind == 'mining with a pickaxe' &&
            point.areaId == null,
      ),
      isTrue,
    );
    expect(
      dataset
          .gatheringPointsById['gathering-point:bdocodex:28115:2965']!
          .location,
      const BdoWorldPoint(486850, 681150),
    );
    expect(
      dataset
          .gatheringPointsById['gathering-point:bdocodex:28115:3034']!
          .location,
      const BdoWorldPoint(472062.5, 745209.375),
    );
    expect(points.first.verifiedAt, DateTime.utc(2026, 7, 28, 18, 5));
    expect(dataset.gatheringSpotsForResource(resource.id), isEmpty);
    expect(
      dataset
          .search('rusalkas coral')
          .firstWhere((result) => result.kind == BdoSearchKind.resource)
          .id,
      resource.id,
    );
    expect(
      dataset
          .search('rusalka crystal')
          .where(
            (result) =>
                result.kind == BdoSearchKind.resource &&
                result.id == resource.id,
          ),
      isEmpty,
    );

    final provenance = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'bdo-codex-rusalka-coral-points-reference',
    );
    expect(provenance.url.toString(), 'https://bdocodex.com/us/npc/28115/');
    expect(provenance.license, contains('Pearl Abyss-origin game facts'));
    expect(provenance.permittedUse, contains('free noncommercial fan-content'));
    expect(provenance.permittedUse, contains('open to correction'));
    expect(provenance.permittedUse, contains('source-recorded'));
    expect(provenance.permittedUse, contains('(pixelX - 68600) * 25'));
    expect(provenance.permittedUse, contains('(72200 - pixelY) * 25'));
  });

  test('loads Stillcoral coastal objects as exact dots, never a route', () {
    const sourceId = 'field-source:stillcoral-coastal-gathering';
    const usefulResourceIds = <String>{
      'item:4476',
      'item:4477',
      'item:4998',
      'item:6501',
      'item:6504',
      'item:6509',
      'item:6511',
      'item:6515',
      'item:6516',
      'item:8246',
    };
    const tradeResourceIds = <String>{'item:55880', 'item:55881', 'item:55883'};
    final source = dataset.fieldSourcesById[sourceId]!;
    final points = dataset
        .gatheringPointsForFieldSource(sourceId)
        .toList(growable: false);

    expect(source.name, 'Stillcoral Coastal Gathering');
    expect(source.category, 'Coastal gathering');
    expect(source.note, contains('no line'));
    expect(source.note, contains('separate from Coral Stoneback Crab'));
    expect(source.products, hasLength(10));
    expect(
      source.products.map((product) => product.resourceId).toSet(),
      usefulResourceIds,
    );
    expect(
      source.products.every(
        (product) => product.method == 'Gather' && product.tool == 'Hoe',
      ),
      isTrue,
    );
    expect(
      source.products
          .map((product) => product.resourceId)
          .toSet()
          .intersection(tradeResourceIds),
      isEmpty,
    );
    expect(
      tradeResourceIds.intersection(dataset.resourcesById.keys.toSet()),
      isEmpty,
    );

    expect(points, hasLength(198));
    expect(
      <String, int>{
        for (final group in points.fold<Map<String, List<BdoGatheringPoint>>>(
          <String, List<BdoGatheringPoint>>{},
          (groups, point) {
            (groups[point.target] ??= <BdoGatheringPoint>[]).add(point);
            return groups;
          },
        ).entries)
          group.key: group.value.length,
      },
      <String, int>{
        'Rainbow Coral': 105,
        'Oyster': 66,
        'Giant Pearl Clam': 6,
        'Sea Fan': 21,
      },
    );
    expect(
      points.every(
        (point) =>
            point.fieldSourceIds.contains(sourceId) &&
            point.verification == BdoGatheringVerification.communityReported &&
            point.provenanceId ==
                'bdo-codex-stillcoral-coastal-points-reference' &&
            point.kind == 'gathering with a hoe' &&
            point.areaId == null &&
            point.verifiedAt == DateTime.utc(2026, 8, 1),
      ),
      isTrue,
    );
    final knownRainbow = dataset
        .gatheringPointsById['gathering-point:bdocodex:stillcoral:10924:6273']!;
    expect(knownRainbow.location.x, closeTo(471778.688, 0.001));
    expect(knownRainbow.location.z, closeTo(674243, 0.001));
    expect(knownRainbow.resourceIds.toSet(), <String>{
      'item:4476',
      'item:4477',
      'item:4998',
      'item:6501',
      'item:6511',
    });
    expect(dataset.gatheringPointsForResource('item:6515'), hasLength(66));
    expect(dataset.gatheringPointsForResource('item:6511'), hasLength(132));
    expect(dataset.gatheringSpotsForResource('item:6515'), isEmpty);
    expect(dataset.gatheringRoutesForResource('item:6515'), isEmpty);
    expect(dataset.gatheringRoutes, isEmpty);
    expect(
      dataset
          .search('oyster rotation')
          .firstWhere((result) => result.kind == BdoSearchKind.fieldSource)
          .fieldSourceId,
      sourceId,
    );

    final provenance = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'bdo-codex-stillcoral-coastal-points-reference',
    );
    expect(provenance.license, contains('Pearl Abyss-origin game facts'));
    expect(provenance.permittedUse, contains('198'));
    expect(provenance.permittedUse, contains('does not connect the dots'));
    expect(provenance.permittedUse, contains('open to correction'));
  });

  test('keeps crab outputs and coastal objects on separate exact layers', () {
    const crabSourceId = 'field-source:coral-stoneback-crab';
    const normalOutputIds = <String>{
      'item:821255',
      'item:6533',
      'item:6501',
      'item:4411',
      'item:4406',
      'item:4203',
      'item:4201',
      'item:4006',
    };
    final source = dataset.fieldSourcesById[crabSourceId]!;
    final points = dataset
        .gatheringPointsForFieldSource(crabSourceId)
        .toList(growable: false);

    expect(source.category, 'Coastal gathering');
    expect(source.summary, contains('shore and land targets'));
    expect(source.note, contains('separate from nearby Oyster'));
    expect(source.products, hasLength(9));
    expect(
      source.products
          .where((product) => product.method == 'Defeat and mine')
          .map((product) => product.resourceId)
          .toSet(),
      normalOutputIds,
    );
    expect(points, hasLength(34));
    expect(
      points.every(
        (point) => point.resourceIds.toSet().containsAll(normalOutputIds),
      ),
      isTrue,
    );
    expect(
      points
          .map((point) => point.id)
          .toSet()
          .intersection(
            dataset
                .gatheringPointsForFieldSource(
                  'field-source:stillcoral-coastal-gathering',
                )
                .map((point) => point.id)
                .toSet(),
          ),
      isEmpty,
    );
    for (final resourceId in normalOutputIds) {
      expect(
        dataset.resourcesById[resourceId]!.acquisitionModes,
        contains(BdoAcquisitionMode.fieldGathering),
        reason: resourceId,
      );
    }
  });

  test('attributes exact points and states their historical limit', () {
    final provenance = dataset.manifest.provenance.singleWhere(
      (record) => record.id == 'somethinglovely-mit-gathering-points',
    );

    expect(provenance.license, 'MIT');
    expect(
      provenance.url.toString(),
      contains('289c833d34851dc84f3a647a2d9cf604eda9c93a'),
    );
    expect(provenance.permittedUse, contains('historical through 2021'));
    expect(provenance.permittedUse, contains('deduplicated'));
    expect(provenance.permittedUse, contains('byte-identical'));
    expect(provenance.permittedUse, contains('one pinned payload'));
    expect(provenance.permittedUse, contains('shared lumbering product'));
    expect(
      dataset.gatheringPoints.where(
        (point) => point.provenanceId == provenance.id,
      ),
      hasLength(12582),
    );
    expect(
      dataset.gatheringPoints
          .where(
            (point) =>
                point.provenanceId == 'somethinglovely-mit-gathering-points',
          )
          .every((point) => point.provenanceId == provenance.id),
      isTrue,
    );
  });

  test('finds materials and their worker nodes', () {
    final results = dataset.search('potato');
    final potato = results.firstWhere(
      (result) => result.kind == BdoSearchKind.resource,
    );

    expect(potato.title, 'Potato');
    expect(
      dataset
          .workerNodesForResource(potato.resourceId!)
          .map((node) => node.name),
      contains('Bartali Farm - Potato Farming'),
    );
  });

  test(
    'finds exact snake and scorpion locations with the Tshira rotation focus',
    () {
      final snake = dataset.search('snake meat');
      final snakeResource = snake.firstWhere(
        (result) => result.kind == BdoSearchKind.resource,
      );

      expect(snakeResource.title, 'Snake Meat');
      expect(snakeResource.subtitle, contains('1 gathering area'));
      expect(snakeResource.subtitle, contains('657 exact gathering locations'));
      expect(snakeResource.subtitle, isNot(contains('(historical)')));
      final snakeSpots = dataset
          .gatheringSpotsForResource(snakeResource.resourceId!)
          .toList(growable: false);
      expect(snakeSpots, hasLength(1));
      expect(snakeSpots.single.name, 'Tshira Ruins Snake & Scorpion Rotation');
      expect(dataset.search('Tshira South'), isEmpty);
      expect(
        snake.where((result) => result.kind == BdoSearchKind.gatheringSpot),
        hasLength(1),
      );
      expect(
        snake.where((result) => result.title.contains('Historical Snake Meat')),
        isEmpty,
      );
      expect(
        dataset
            .search('Historical Snake Meat', limit: 1000)
            .where((result) => result.title.startsWith('Historical ')),
        isEmpty,
      );
      final scorpionResource = dataset
          .search('scorpion meat')
          .firstWhere((result) => result.kind == BdoSearchKind.resource);
      expect(
        scorpionResource.subtitle,
        contains('475 exact gathering locations'),
      );
      expect(scorpionResource.subtitle, isNot(contains('(historical)')));
    },
  );

  test('groups the compact current Tshira dots by species', () {
    const spotId = 'gathering:tshira-snake-scorpion-rotation';
    final points = dataset.gatheringPoints
        .where((point) => point.areaId == spotId)
        .toList(growable: false);
    final snakePoints = points
        .where(
          (point) =>
              point.target == 'Stone Cobra' &&
              point.resourceIds.contains('item:7922'),
        )
        .toList(growable: false);
    final scorpionPoints = points
        .where(
          (point) =>
              point.target == 'Rock Scorpion' &&
              point.resourceIds.contains('item:7924'),
        )
        .toList(growable: false);

    expect(points, hasLength(29));
    expect(snakePoints, hasLength(21));
    expect(scorpionPoints, hasLength(8));
    expect(
      points.every(
        (point) =>
            point.verification == BdoGatheringVerification.communityReported &&
            point.provenanceId ==
                'bdo-codex-drieghan-animal-points-reference' &&
            point.verifiedAt == DateTime.utc(2026, 7, 28, 20, 30),
      ),
      isTrue,
    );
    expect(
      snakePoints.any(
        (point) =>
            (point.location.x - 107956).abs() < 0.001 &&
            (point.location.z + 294449).abs() < 0.001,
      ),
      isTrue,
    );
    expect(
      scorpionPoints.any(
        (point) =>
            (point.location.x - 108143).abs() < 0.001 &&
            (point.location.z + 296462).abs() < 0.001,
      ),
      isTrue,
    );
    expect(
      dataset.search('tshira rotation').map((result) => result.title),
      containsAll(<String>[
        'Snake Meat',
        'Scorpion Meat',
        'Tshira Ruins Snake & Scorpion Rotation',
      ]),
    );
  });

  test('reports shared exact-location counts without indexing every dot', () {
    const expectedCounts = <String, int>{
      'snake skin': 133,
      'cobra blood': 133,
      'scorpion blood': 240,
      'lamb meat': 1068,
      'sheep blood': 1068,
      'sheep hide': 1068,
    };

    for (final entry in expectedCounts.entries) {
      final results = dataset.search(entry.key, limit: 2000);
      final resource = results.firstWhere(
        (result) => result.kind == BdoSearchKind.resource,
      );
      expect(
        resource.subtitle,
        contains('${entry.value} exact gathering locations'),
        reason: entry.key,
      );
      expect(
        resource.subtitle,
        isNot(contains('(historical)')),
        reason: entry.key,
      );
      expect(
        results.where((result) => result.title.startsWith('Historical ')),
        isEmpty,
        reason: entry.key,
      );
      expect(results.length, lessThan(10), reason: entry.key);
    }
  });

  test('multi-token search requires every token regardless of order', () {
    expect(dataset.search('snake potato'), isEmpty);
    expect(dataset.search('potato snake'), isEmpty);
  });

  test('search folds diacritics in both the query and indexed names', () {
    final fixture = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: dataset.resources,
      workerNodes: dataset.workerNodes,
      gatheringSpots: const <BdoGatheringSpot>[syntheticSurveyArea],
      gatheringRoutes: const <BdoGatheringRoute>[],
    );
    final plain = fixture.search('Nymphamare');
    final accented = fixture.search('Nymphamaré');

    expect(plain.map((result) => result.id), contains(syntheticSurveyArea.id));
    expect(
      plain.map((result) => result.id).toSet(),
      containsAll(accented.map((result) => result.id)),
    );
  });

  test('gathering spot and route search filters are independent', () {
    final fixture = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: dataset.resources,
      workerNodes: dataset.workerNodes,
      gatheringSpots: const <BdoGatheringSpot>[syntheticSurveyArea],
      gatheringPoints: dataset.gatheringPoints,
      gatheringRoutes: const <BdoGatheringRoute>[
        BdoGatheringRoute(
          id: 'route:test-snake',
          spotId: 'gathering:test-nymphamare',
          name: 'Tshira Snake Survey Route',
          region: 'Drieghan',
          resourceIds: <String>['item:7922'],
          tool: 'Butcher Knife',
          loop: true,
          summary: 'Synthetic route used only to verify layer filtering.',
          waypoints: <BdoGatheringWaypoint>[
            BdoGatheringWaypoint(
              order: 1,
              location: BdoWorldPoint(100000, -295000),
              kind: 'cluster',
              label: 'One',
              targets: <String>['Drieghan Stone Cobra'],
            ),
            BdoGatheringWaypoint(
              order: 2,
              location: BdoWorldPoint(110000, -300000),
              kind: 'cluster',
              label: 'Two',
              targets: <String>['Drieghan Stone Cobra'],
            ),
          ],
          verification: BdoGatheringVerification.independentSurvey,
          provenanceId: 'test-only',
        ),
      ],
    );

    final routesOnly = fixture.search(
      'snake',
      includeGatheringSpots: false,
      includeGatheringRoutes: true,
    );
    expect(
      routesOnly.where((result) => result.kind == BdoSearchKind.gatheringSpot),
      isEmpty,
    );
    expect(
      routesOnly.where((result) => result.kind == BdoSearchKind.gatheringRoute),
      isNotEmpty,
    );

    final spotsOnly = fixture.search(
      'snake',
      includeGatheringSpots: true,
      includeGatheringRoutes: false,
    );
    expect(
      spotsOnly.where((result) => result.kind == BdoSearchKind.gatheringSpot),
      isNotEmpty,
    );
    expect(
      spotsOnly.where((result) => result.kind == BdoSearchKind.gatheringRoute),
      isEmpty,
    );
  });
}

BdoWorkerNode _workerNode({
  required String nodeType,
  required String name,
  bool isResourceNode = true,
  bool isProductionNode = false,
  List<BdoNodeOutput> outputs = const <BdoNodeOutput>[],
}) {
  return BdoWorkerNode(
    id: 'test:$nodeType:$name',
    name: name,
    nodeType: nodeType,
    region: 'Test Region',
    location: const BdoWorldPoint(0, 0),
    contributionPoints: 1,
    linkIds: const <String>[],
    outputs: outputs,
    isResourceNode: isResourceNode,
    isProductionNode: isProductionNode,
  );
}
