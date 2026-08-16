import 'package:bdo_map_core/src/data/resource_map_loader.dart';
import 'package:bdo_map_core/src/model/map_geometry.dart';
import 'package:bdo_map_core/src/model/resource_map_data.dart';
import 'package:bdo_map_core/src/network/production_node_path_cost.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoProductionNodePathCostService', () {
    test('chooses the cheapest default city or town root', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('city', type: 'City', cp: 0, links: const <String>['expensive']),
        _node('expensive', cp: 4, links: const <String>['city', 'target']),
        _node('town', type: 'Town', cp: 0, links: const <String>['cheap']),
        _node('cheap', cp: 1, links: const <String>['town', 'target']),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'target'),
      );

      expect(result.hasErrors, isFalse);
      expect(result.minimumTotalPath!.orderedNodeIds, <String>[
        'town',
        'cheap',
        'target',
      ]);
      expect(result.minimumTotalPath!.rootNodeId, 'town');
      expect(result.minimumTotalPath!.totalContributionPoints, 2);
      expect(result.minimumTotalPath!.incrementalContributionPoints, 2);
      expect(result.minimumTotalPath!.connectNodeIds, <String>[
        'cheap',
        'target',
      ]);
      expect(result.minimumTotalPath!.edges.map((edge) => edge.key), <String>[
        'town\u0000cheap',
        'cheap\u0000target',
      ]);
    });

    test('honors an explicit allowed-root set', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('city', type: 'City', cp: 0, links: const <String>['expensive']),
        _node('expensive', cp: 4, links: const <String>['city', 'target']),
        _node('town', type: 'Town', cp: 0, links: const <String>['target']),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: 'target',
          allowedRootNodeIds: const <String>{'city'},
        ),
      );

      expect(result.minimumTotalPath!.orderedNodeIds, <String>[
        'city',
        'expensive',
        'target',
      ]);
      expect(result.minimumTotalPath!.totalContributionPoints, 5);
    });

    test('reports separate minimum-total and minimum-incremental paths', () {
      final data = _dataset(<BdoWorkerNode>[
        _node(
          'root',
          type: 'City',
          cp: 0,
          links: const <String>['short', 'old-a'],
        ),
        _node('short', cp: 1, links: const <String>['target']),
        _node('old-a', cp: 2, links: const <String>['old-b']),
        _node('old-b', cp: 2, links: const <String>['target']),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: 'target',
          currentNodeIds: const <String>{'old-a', 'old-b'},
        ),
      );

      expect(result.minimumTotalPath!.orderedNodeIds, <String>[
        'root',
        'short',
        'target',
      ]);
      expect(result.minimumTotalPath!.totalContributionPoints, 2);
      expect(result.minimumTotalPath!.incrementalContributionPoints, 2);

      expect(result.minimumIncrementalPath!.orderedNodeIds, <String>[
        'root',
        'old-a',
        'old-b',
        'target',
      ]);
      expect(result.minimumIncrementalPath!.totalContributionPoints, 5);
      expect(result.minimumIncrementalPath!.incrementalContributionPoints, 1);
      expect(result.minimumIncrementalPath!.retainedNodeIds, <String>[
        'old-a',
        'old-b',
      ]);
      expect(result.minimumIncrementalPath!.connectNodeIds, <String>['target']);
    });

    test('treats one-sided link records as undirected', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0),
        _node('bridge', cp: 2, links: const <String>['root']),
        _production('target', cp: 1, links: const <String>['bridge']),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'target'),
      );

      expect(result.minimumTotalPath!.orderedNodeIds, <String>[
        'root',
        'bridge',
        'target',
      ]);
      expect(result.minimumTotalPath!.totalContributionPoints, 3);
    });

    test('never uses another production node as transit', () {
      final data = _dataset(<BdoWorkerNode>[
        _node(
          'root',
          type: 'City',
          cp: 0,
          links: const <String>['blocked-production', 'safe-a'],
        ),
        _production(
          'blocked-production',
          cp: 0,
          links: const <String>['target'],
        ),
        _node('safe-a', cp: 2, links: const <String>['safe-b']),
        _node('safe-b', cp: 2, links: const <String>['target']),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'target'),
      );

      expect(result.minimumTotalPath!.orderedNodeIds, <String>[
        'root',
        'safe-a',
        'safe-b',
        'target',
      ]);
      expect(
        result.minimumTotalPath!.orderedNodeIds,
        isNot(contains('blocked-production')),
      );
    });

    test('allows the current target as the production endpoint', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['bridge']),
        _node('bridge', cp: 2, links: const <String>['target']),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: 'target',
          currentNodeIds: const <String>{'bridge', 'target'},
        ),
      );

      expect(result.minimumIncrementalPath!.totalContributionPoints, 3);
      expect(result.minimumIncrementalPath!.incrementalContributionPoints, 0);
      expect(result.minimumIncrementalPath!.isAlreadyConnected, isTrue);
      expect(result.minimumIncrementalPath!.connectNodeIds, isEmpty);
      expect(result.minimumIncrementalPath!.retainedNodeIds, <String>[
        'bridge',
        'target',
      ]);
    });

    test('breaks equal-cost ties deterministically by numeric-aware IDs', () {
      BdoResourceMapDataset data(bool reverse) => _dataset(<BdoWorkerNode>[
        _production('target', cp: 1, links: const <String>[]),
        if (reverse) ...<BdoWorkerNode>[
          _node('10', cp: 1, links: const <String>['root', 'target']),
          _node('2', cp: 1, links: const <String>['root', 'target']),
        ] else ...<BdoWorkerNode>[
          _node('2', cp: 1, links: const <String>['target', 'root']),
          _node('10', cp: 1, links: const <String>['target', 'root']),
        ],
        _node(
          'root',
          type: 'City',
          cp: 0,
          links: reverse
              ? const <String>['10', '2']
              : const <String>['2', '10'],
        ),
      ]);

      for (final reverse in <bool>[false, true]) {
        final result = const BdoProductionNodePathCostService().calculate(
          data: data(reverse),
          request: BdoProductionNodePathRequest(targetNodeId: 'target'),
        );
        expect(result.minimumTotalPath!.orderedNodeIds, <String>[
          'root',
          '2',
          'target',
        ], reason: 'reverse=$reverse');
      }
    });

    test('warns about unknown saved nodes without blocking a valid path', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['target']),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: 'target',
          currentNodeIds: const <String>{'removed-node'},
        ),
      );

      expect(result.hasPath, isTrue);
      expect(result.hasErrors, isFalse);
      expect(
        result.diagnostics.single.code,
        BdoProductionNodePathDiagnosticCode.unknownCurrentNode,
      );
      expect(result.diagnostics.single.nodeIds, <String>['removed-node']);
    });

    test('rejects unknown and non-production targets', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['ordinary']),
        _node('ordinary', cp: 1),
      ]);
      final service = const BdoProductionNodePathCostService();

      final unknown = service.calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'missing'),
      );
      final ordinary = service.calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'ordinary'),
      );

      expect(unknown.hasPath, isFalse);
      expect(
        unknown.diagnostics.map((item) => item.code),
        contains(BdoProductionNodePathDiagnosticCode.unknownTargetNode),
      );
      expect(ordinary.hasPath, isFalse);
      expect(
        ordinary.diagnostics.map((item) => item.code),
        contains(BdoProductionNodePathDiagnosticCode.targetIsNotProductionNode),
      );
    });

    test('rejects missing, unknown, and paid roots', () {
      final service = const BdoProductionNodePathCostService();
      final noRootsData = _dataset(<BdoWorkerNode>[
        _production('target', cp: 1, links: const <String>[]),
      ]);
      final invalidRootsData = _dataset(<BdoWorkerNode>[
        _node(
          'paid-town',
          type: 'Town',
          cp: 2,
          links: const <String>['target'],
        ),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final noRoots = service.calculate(
        data: noRootsData,
        request: BdoProductionNodePathRequest(targetNodeId: 'target'),
      );
      final invalidRoots = service.calculate(
        data: invalidRootsData,
        request: BdoProductionNodePathRequest(
          targetNodeId: 'target',
          allowedRootNodeIds: const <String>{'paid-town', 'missing'},
        ),
      );

      expect(noRoots.hasPath, isFalse);
      expect(
        noRoots.diagnostics.map((item) => item.code),
        contains(BdoProductionNodePathDiagnosticCode.noRootNodes),
      );
      expect(invalidRoots.hasPath, isFalse);
      expect(
        invalidRoots.diagnostics.map((item) => item.code),
        containsAll(<BdoProductionNodePathDiagnosticCode>[
          BdoProductionNodePathDiagnosticCode.unknownRootNode,
          BdoProductionNodePathDiagnosticCode.invalidRootNode,
          BdoProductionNodePathDiagnosticCode.noRootNodes,
        ]),
      );
    });

    test('rejects negative CP data and reports stable node IDs', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['target']),
        _node('10', cp: -1),
        _node('2', cp: -1),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'target'),
      );

      expect(result.hasPath, isFalse);
      final diagnostic = result.diagnostics.singleWhere(
        (item) =>
            item.code ==
            BdoProductionNodePathDiagnosticCode.invalidNodeContributionPoints,
      );
      expect(diagnostic.nodeIds, <String>['2', '10']);
    });

    test('reports a target that is unreachable without production transit', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0),
        _production('target', cp: 1, links: const <String>[]),
      ]);

      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: 'target'),
      );

      expect(result.hasPath, isFalse);
      expect(
        result.diagnostics.map((item) => item.code),
        contains(BdoProductionNodePathDiagnosticCode.unreachableTargetNode),
      );
    });

    test('calculates all production nodes once in stable ID order', () {
      final data = _dataset(<BdoWorkerNode>[
        _node(
          'root',
          type: 'City',
          cp: 0,
          links: const <String>['10', '2', 'ordinary'],
        ),
        _production('10', cp: 2, links: const <String>[]),
        _node('ordinary', cp: 1),
        _production('2', cp: 1, links: const <String>[]),
      ]);

      final results = const BdoProductionNodePathCostService().calculateAll(
        data: data,
      );

      expect(results.keys, <String>['2', '10']);
      expect(results['2']!.minimumTotalPath!.totalContributionPoints, 1);
      expect(results['10']!.minimumTotalPath!.totalContributionPoints, 2);
      expect(() => results.remove('2'), throwsUnsupportedError);
    });

    test(
      'calculateAll exactly matches calculate for every production target',
      () {
        final data = _dataset(<BdoWorkerNode>[
          _node(
            'city',
            type: 'City',
            cp: 0,
            links: const <String>['short', 'current-a', 'blocker'],
          ),
          _node(
            'town',
            type: 'Town',
            cp: 0,
            links: const <String>['town-branch'],
          ),
          _node('short', cp: 1, links: const <String>['2']),
          _node('current-a', cp: 3, links: const <String>['current-b']),
          _node('current-b', cp: 2, links: const <String>['2', '10']),
          _node('town-branch', cp: 2, links: const <String>['10']),
          _production(
            'blocker',
            cp: 1,
            links: const <String>['behind-blocker'],
          ),
          _production('2', cp: 1, links: const <String>[]),
          _production('10', cp: 1, links: const <String>[]),
          _production('behind-blocker', cp: 1, links: const <String>[]),
          _production('disconnected', cp: 1, links: const <String>[]),
        ]);
        final service = const BdoProductionNodePathCostService();
        final scenarios =
            <({Set<String> currentNodeIds, Set<String>? allowedRootNodeIds})>[
              (
                currentNodeIds: const <String>{
                  'current-a',
                  'current-b',
                  '10',
                  'removed-current',
                },
                allowedRootNodeIds: null,
              ),
              (
                currentNodeIds: const <String>{'current-a', 'current-b'},
                allowedRootNodeIds: const <String>{'city'},
              ),
              (
                currentNodeIds: const <String>{},
                allowedRootNodeIds: const <String>{'missing-root'},
              ),
            ];

        for (final scenario in scenarios) {
          final all = service.calculateAll(
            data: data,
            currentNodeIds: scenario.currentNodeIds,
            allowedRootNodeIds: scenario.allowedRootNodeIds,
          );
          for (final target in data.workerNodes.where(
            (node) => node.isProductionNode,
          )) {
            final single = service.calculate(
              data: data,
              request: BdoProductionNodePathRequest(
                targetNodeId: target.id,
                currentNodeIds: scenario.currentNodeIds,
                allowedRootNodeIds: scenario.allowedRootNodeIds,
              ),
            );
            _expectEquivalentResults(
              all[target.id]!,
              single,
              reason:
                  'target=${target.id}, roots='
                  '${scenario.allowedRootNodeIds}',
            );
          }
        }
      },
    );

    test(
      'full bundled dataset calculateAll stays lightweight',
      () async {
        final data = await BdoResourceMapLoader.loadBundled();
        final currentNodeIds = data.workerNodes
            .where((node) => node.contributionPoints > 0)
            .take(24)
            .map((node) => node.id)
            .toSet();
        final productionCount = data.workerNodes
            .where((node) => node.isProductionNode)
            .length;
        final resourceProductionCount = data.workerNodes
            .where((node) => node.isProductionNode && node.isResourceNode)
            .length;
        expect(data.workerNodes.length, greaterThanOrEqualTo(1000));
        expect(resourceProductionCount, greaterThanOrEqualTo(350));

        final stopwatch = Stopwatch()..start();
        final results = const BdoProductionNodePathCostService().calculateAll(
          data: data,
          currentNodeIds: currentNodeIds,
        );
        stopwatch.stop();

        debugPrint(
          'Production path calculateAll: ${data.workerNodes.length} graph nodes, '
          '$productionCount endpoints, ${stopwatch.elapsedMilliseconds} ms',
        );
        expect(results, hasLength(productionCount));
        expect(results.values.where((result) => result.hasPath), isNotEmpty);
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason:
              'The generous five-second ceiling is a regression guard, not a '
              'microbenchmark. Measured ${stopwatch.elapsedMilliseconds} ms.',
        );

        final service = const BdoProductionNodePathCostService();
        for (final target in data.workerNodes.where(
          (node) => node.isProductionNode,
        )) {
          final single = service.calculate(
            data: data,
            request: BdoProductionNodePathRequest(
              targetNodeId: target.id,
              currentNodeIds: currentNodeIds,
            ),
          );
          _expectEquivalentResults(
            results[target.id]!,
            single,
            reason: 'bundled target=${target.id}',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

void _expectEquivalentResults(
  BdoProductionNodePathResult actual,
  BdoProductionNodePathResult expected, {
  required String reason,
}) {
  expect(actual.hasErrors, expected.hasErrors, reason: reason);
  expect(actual.hasPath, expected.hasPath, reason: reason);
  expect(
    actual.diagnostics
        .map(
          (item) => (
            item.code,
            item.severity,
            item.message,
            item.nodeIds.join('\u0000'),
          ),
        )
        .toList(),
    expected.diagnostics
        .map(
          (item) => (
            item.code,
            item.severity,
            item.message,
            item.nodeIds.join('\u0000'),
          ),
        )
        .toList(),
    reason: reason,
  );
  _expectEquivalentPath(
    actual.minimumTotalPath,
    expected.minimumTotalPath,
    reason: '$reason, minimum total',
  );
  _expectEquivalentPath(
    actual.minimumIncrementalPath,
    expected.minimumIncrementalPath,
    reason: '$reason, minimum incremental',
  );
}

void _expectEquivalentPath(
  BdoProductionNodePath? actual,
  BdoProductionNodePath? expected, {
  required String reason,
}) {
  if (expected == null) {
    expect(actual, isNull, reason: reason);
    return;
  }
  expect(actual, isNotNull, reason: reason);
  expect(actual!.targetNodeId, expected.targetNodeId, reason: reason);
  expect(actual.rootNodeId, expected.rootNodeId, reason: reason);
  expect(actual.orderedNodeIds, expected.orderedNodeIds, reason: reason);
  expect(
    actual.edges.map((edge) => edge.key),
    expected.edges.map((edge) => edge.key),
    reason: reason,
  );
  expect(
    actual.totalContributionPoints,
    expected.totalContributionPoints,
    reason: reason,
  );
  expect(
    actual.incrementalContributionPoints,
    expected.incrementalContributionPoints,
    reason: reason,
  );
  expect(actual.retainedNodeIds, expected.retainedNodeIds, reason: reason);
  expect(actual.connectNodeIds, expected.connectNodeIds, reason: reason);
}

BdoResourceMapDataset _dataset(List<BdoWorkerNode> nodes) {
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'production-path-test',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[],
    workerNodes: nodes,
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

BdoWorkerNode _node(
  String id, {
  String type = 'Connection',
  required int cp,
  List<String> links = const <String>[],
}) {
  return BdoWorkerNode(
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
}

BdoWorkerNode _production(
  String id, {
  required int cp,
  required List<String> links,
}) {
  return BdoWorkerNode(
    id: id,
    name: id,
    nodeType: 'Gathering',
    region: 'Test',
    location: const BdoWorldPoint(0, 0),
    contributionPoints: cp,
    linkIds: links,
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
