import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoRawSaleNetworkPlanner', () {
    test('recomputes marginal paths and reuses a shared connection trunk', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['trunk']),
        _node('trunk', cp: 2, links: const <String>['root', 'p1', 'p2']),
        _production('p1', cp: 1, links: const <String>['trunk']),
        _production('p2', cp: 1, links: const <String>['trunk']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 4,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'p1': 9,
            'p2': 8,
          },
        ),
      );

      expect(result.selectedProductionNodeIds, <String>['p1', 'p2']);
      expect(
        result.selections.map(
          (selection) => selection.addedContributionPointsAtSelection,
        ),
        <int>[3, 1],
      );
      expect(result.selections[0].path.orderedNodeIds, <String>[
        'root',
        'trunk',
        'p1',
      ]);
      expect(result.selections[1].path.orderedNodeIds, <String>[
        'root',
        'trunk',
        'p2',
      ]);
      expect(result.addedNodeIds, <String>['p1', 'p2', 'trunk']);
      expect(result.networkNodeIds, result.addedNodeIds);
      expect(result.addedContributionPoints, 4);
      expect(result.totalContributionPoints, 4);
      expect(result.currentSaleValueSignal, 17);
      expect(
        result.routeEdges,
        unorderedEquals(<BdoRawSaleNetworkEdge>[
          BdoRawSaleNetworkEdge('root', 'trunk'),
          BdoRawSaleNetworkEdge('trunk', 'p1'),
          BdoRawSaleNetworkEdge('trunk', 'p2'),
        ]),
      );
      expect(result.routeNodeIds, <String>['p1', 'p2', 'root', 'trunk']);
      expect(result.qualityLabel, contains('heuristic'));
      expect(result.qualityDisclosure, contains('Not globally optimal'));
      expect(result.qualityDisclosure, contains('shared connection paths'));
      expect(result.qualityDisclosure, contains('current or marginal signals'));
    });

    test(
      'recalculates a shared-portfolio marginal signal after every pick',
      () {
        final data = _dataset(<BdoWorkerNode>[
          _node('root', type: 'City', cp: 0, links: const <String>['trunk']),
          _node('trunk', cp: 2, links: const <String>['root', 'p1', 'p2']),
          _production('p1', cp: 1, links: const <String>['trunk']),
          _production('p2', cp: 1, links: const <String>['trunk']),
        ]);

        final result = const BdoRawSaleNetworkPlanner().plan(
          data: data,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 4,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'p1': 9,
              'p2': 8,
            },
            marginalValueSignalProvider: _sharedPortfolioMarginalSignal,
          ),
        );

        expect(result.selectedProductionNodeIds, <String>['p1']);
        expect(result.currentSaleValueSignal, 9);
        expect(result.totalContributionPoints, 3);
        expect(
          _exclusion(result, 'p2').reason,
          BdoRawSaleNetworkExclusionReason.noPositiveMarginalValueSignal,
        );
      },
    );

    test(
      'planAsync preserves synchronous results and callback order',
      () async {
        final data = _dataset(<BdoWorkerNode>[
          _node('root', type: 'City', cp: 0, links: const <String>['trunk']),
          _node('trunk', cp: 2, links: const <String>['root', 'p1', 'p2']),
          _production('p1', cp: 1, links: const <String>['trunk']),
          _production('p2', cp: 1, links: const <String>['trunk']),
          _production('unreachable', cp: 1),
        ]);
        final synchronousCalls = <String>[];
        final asynchronousCalls = <String>[];

        BdoRawSaleNetworkPlanRequest requestFor(List<String> calls) {
          return BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 4,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'p1': 9,
              'p2': 8,
              'unreachable': 7,
            },
            marginalValueSignalProvider: (nodeId, selectedNodeIds) {
              calls.add('$nodeId:${selectedNodeIds.join(',')}');
              if (nodeId == 'p2' && selectedNodeIds.contains('p1')) {
                return 0;
              }
              return switch (nodeId) {
                'p1' => 9,
                'p2' => 8,
                _ => 7,
              };
            },
          );
        }

        const planner = BdoRawSaleNetworkPlanner();
        final synchronous = planner.plan(
          data: data,
          request: requestFor(synchronousCalls),
        );
        final asynchronous = await planner.planAsync(
          data: data,
          request: requestFor(asynchronousCalls),
          yieldEveryCandidates: 1,
        );

        expect(asynchronousCalls, synchronousCalls);
        _expectSamePlan(asynchronous, synchronous);
      },
    );

    test(
      'planAsync can cancel after yielding during a candidate scan',
      () async {
        final data = _dataset(<BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['p1', 'p2', 'p3'],
          ),
          _production('p1', cp: 1, links: const <String>['root']),
          _production('p2', cp: 1, links: const <String>['root']),
          _production('p3', cp: 1, links: const <String>['root']),
        ]);
        var shouldCancel = false;
        var providerCalls = 0;

        final future = const BdoRawSaleNetworkPlanner().planAsync(
          data: data,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 3,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'p1': 3,
              'p2': 2,
              'p3': 1,
            },
            marginalValueSignalProvider: (nodeId, selectedNodeIds) {
              providerCalls += 1;
              if (providerCalls == 1) {
                Timer.run(() => shouldCancel = true);
              }
              return switch (nodeId) {
                'p1' => 3,
                'p2' => 2,
                _ => 1,
              };
            },
          ),
          shouldCancel: () => shouldCancel,
          yieldEveryCandidates: 1,
        );

        await expectLater(
          future,
          throwsA(isA<BdoRawSaleNetworkPlanningCancelled>()),
        );
        expect(providerCalls, 1);
      },
    );

    test('planAsync honors cancellation before doing planner work', () async {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['p']),
        _production('p', cp: 1, links: const <String>['root']),
      ]);
      var providerCalls = 0;

      await expectLater(
        const BdoRawSaleNetworkPlanner().planAsync(
          data: data,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 1,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{
              'p': 1,
            },
            marginalValueSignalProvider: (nodeId, selectedNodeIds) {
              providerCalls += 1;
              return 1;
            },
          ),
          shouldCancel: () => true,
        ),
        throwsA(isA<BdoRawSaleNetworkPlanningCancelled>()),
      );
      expect(providerCalls, 0);
    });

    test('preserves the saved baseline and includes its existing edges', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['trunk']),
        _node('trunk', cp: 2, links: const <String>['root', 'p1', 'p2']),
        _production('p1', cp: 1, links: const <String>['trunk']),
        _production('p2', cp: 1, links: const <String>['trunk']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 3,
          currentNodeIds: const <String>{'trunk', 'p1', 'legacy-id'},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'p1': 10,
            'p2': 8,
          },
        ),
      );

      expect(result.currentNodeIds, <String>['legacy-id', 'p1', 'trunk']);
      expect(result.networkNodeIds, result.currentNodeIds);
      expect(result.addedNodeIds, isEmpty);
      expect(result.baselineContributionPoints, 3);
      expect(result.addedContributionPoints, 0);
      expect(result.totalContributionPoints, 3);
      expect(result.selectedProductionNodeIds, <String>['p1']);
      expect(result.selections.single.addedContributionPointsAtSelection, 0);
      expect(
        result.routeEdges,
        unorderedEquals(<BdoRawSaleNetworkEdge>[
          BdoRawSaleNetworkEdge('root', 'trunk'),
          BdoRawSaleNetworkEdge('trunk', 'p1'),
        ]),
      );
      expect(
        result.diagnostics,
        contains(
          isA<BdoRawSaleNetworkDiagnostic>()
              .having(
                (diagnostic) => diagnostic.pathCode,
                'pathCode',
                BdoProductionNodePathDiagnosticCode.unknownCurrentNode,
              )
              .having((diagnostic) => diagnostic.nodeIds, 'nodeIds', <String>[
                'legacy-id',
              ]),
        ),
      );
      final excluded = _exclusion(result, 'p2');
      expect(
        excluded.reason,
        BdoRawSaleNetworkExclusionReason
            .exceedsRemainingContributionPointBudget,
      );
      expect(excluded.requiredAddedContributionPoints, 1);
    });

    test(
      'renders saved baseline edges to valid implicit and allowed roots',
      () {
        final data = _dataset(<BdoWorkerNode>[
          _node(
            'root-a',
            type: 'City',
            cp: 0,
            links: const <String>['trunk-a'],
          ),
          _node(
            'root-b',
            type: 'City',
            cp: 0,
            links: const <String>['paid-bridge'],
          ),
          _node(
            'root-c',
            type: 'Town',
            cp: 0,
            links: const <String>['trunk-c'],
          ),
          _node(
            'paid-bridge',
            cp: 2,
            links: const <String>['root-b', 'trunk-b'],
          ),
          _node('trunk-a', cp: 2, links: const <String>['root-a', 'p']),
          _node('trunk-b', cp: 1, links: const <String>['paid-bridge']),
          _node('trunk-c', cp: 1, links: const <String>['root-c']),
          _production('p', cp: 1, links: const <String>['trunk-a']),
        ]);
        const currentIds = <String>{'trunk-a', 'trunk-b', 'trunk-c', 'p'};

        final implicitRoots = const BdoRawSaleNetworkPlanner().plan(
          data: data,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 5,
            currentNodeIds: currentIds,
            currentSaleValueSignalsByProductionNodeId: const <String, double>{},
          ),
        );

        expect(implicitRoots.routeEdges, <BdoRawSaleNetworkEdge>[
          BdoRawSaleNetworkEdge('p', 'trunk-a'),
          BdoRawSaleNetworkEdge('root-a', 'trunk-a'),
          BdoRawSaleNetworkEdge('root-c', 'trunk-c'),
        ]);
        expect(implicitRoots.routeNodeIds, <String>[
          'p',
          'root-a',
          'root-c',
          'trunk-a',
          'trunk-c',
        ]);
        expect(implicitRoots.routeNodeIds, isNot(contains('paid-bridge')));

        final allowedRoot = const BdoRawSaleNetworkPlanner().plan(
          data: data,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 5,
            currentNodeIds: currentIds,
            allowedRootNodeIds: const <String>{'root-a'},
            currentSaleValueSignalsByProductionNodeId: const <String, double>{},
          ),
        );

        expect(allowedRoot.routeEdges, <BdoRawSaleNetworkEdge>[
          BdoRawSaleNetworkEdge('p', 'trunk-a'),
          BdoRawSaleNetworkEdge('root-a', 'trunk-a'),
        ]);
        expect(allowedRoot.routeNodeIds, <String>['p', 'root-a', 'trunk-a']);
      },
    );

    test('reports unknown saved IDs without any usable candidate', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['p']),
        _production('p', cp: 1, links: const <String>['root']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 1,
          currentNodeIds: const <String>{'legacy-id'},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'p': 0,
          },
        ),
      );

      expect(
        result.diagnostics,
        contains(
          isA<BdoRawSaleNetworkDiagnostic>()
              .having(
                (diagnostic) => diagnostic.pathCode,
                'pathCode',
                BdoProductionNodePathDiagnosticCode.unknownCurrentNode,
              )
              .having((diagnostic) => diagnostic.nodeIds, 'nodeIds', <String>[
                'legacy-id',
              ]),
        ),
      );
    });

    test('reports path validation alongside an invalid budget', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['p']),
        _production('p', cp: 1, links: const <String>['root']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: -1,
          currentNodeIds: const <String>{'legacy-id'},
          allowedRootNodeIds: const <String>{'missing-root'},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'p': 5,
          },
        ),
      );

      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains(
          BdoRawSaleNetworkDiagnosticCode.invalidContributionPointBudget,
        ),
      );
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.pathCode),
        containsAll(<BdoProductionNodePathDiagnosticCode>[
          BdoProductionNodePathDiagnosticCode.unknownCurrentNode,
          BdoProductionNodePathDiagnosticCode.unknownRootNode,
          BdoProductionNodePathDiagnosticCode.noRootNodes,
        ]),
      );
    });

    test('selects zero-added-CP paths without division or loop hazards', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['free']),
        _node('free', cp: 0, links: const <String>['root', 'p0']),
        _production('p0', cp: 0, links: const <String>['free']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 0,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'p0': 12,
          },
        ),
      );

      expect(result.selectedProductionNodeIds, <String>['p0']);
      expect(result.addedNodeIds, <String>['free', 'p0']);
      expect(result.addedContributionPoints, 0);
      expect(result.totalContributionPoints, 0);
      expect(result.currentSaleValueSignal, 12);
      expect(result.exclusions, isEmpty);
    });

    test('recomputes each zero-CP path against the actual active network', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['free']),
        _node('free', cp: 0, links: const <String>['root', 'p1', 'p2']),
        _production('p1', cp: 0, links: const <String>['free']),
        _production('p2', cp: 0, links: const <String>['free']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 0,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'p1': 20,
            'p2': 10,
          },
        ),
      );

      expect(result.selectedProductionNodeIds, <String>['p1', 'p2']);
      expect(result.selections[0].path.retainedNodeIds, isEmpty);
      expect(result.selections[0].path.connectNodeIds, <String>['free', 'p1']);
      expect(result.selections[1].path.retainedNodeIds, <String>['free']);
      expect(result.selections[1].path.connectNodeIds, <String>['p2']);
    });

    test('breaks equal score ties by numeric-aware production-node ID', () {
      BdoResourceMapDataset buildData(bool reverse) => _dataset(<BdoWorkerNode>[
        _node(
          '1',
          type: 'City',
          cp: 0,
          links: reverse
              ? const <String>['10', '2']
              : const <String>['2', '10'],
        ),
        if (reverse) ...<BdoWorkerNode>[
          _production('10', cp: 2, links: const <String>['1']),
          _production('2', cp: 2, links: const <String>['1']),
        ] else ...<BdoWorkerNode>[
          _production('2', cp: 2, links: const <String>['1']),
          _production('10', cp: 2, links: const <String>['1']),
        ],
      ]);

      for (final reverse in <bool>[false, true]) {
        final signals = reverse
            ? const <String, double>{'10': 10, '2': 10}
            : const <String, double>{'2': 10, '10': 10};
        final result = const BdoRawSaleNetworkPlanner().plan(
          data: buildData(reverse),
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: 2,
            currentNodeIds: const <String>{},
            currentSaleValueSignalsByProductionNodeId: signals,
          ),
        );

        expect(result.selectedProductionNodeIds, <String>['2']);
        expect(
          _exclusion(result, '10').reason,
          BdoRawSaleNetworkExclusionReason
              .exceedsRemainingContributionPointBudget,
        );
      }
    });

    test('forwards the optional allowed-root boundary to every path', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('city-a', type: 'City', cp: 0, links: const <String>['a-bridge']),
        _node('city-b', type: 'City', cp: 0, links: const <String>['b-bridge']),
        _node('a-bridge', cp: 3, links: const <String>['city-a', 'target']),
        _node('b-bridge', cp: 1, links: const <String>['city-b', 'target']),
        _production(
          'target',
          cp: 1,
          links: const <String>['a-bridge', 'b-bridge'],
        ),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 4,
          currentNodeIds: const <String>{},
          allowedRootNodeIds: const <String>{'city-a'},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'target': 10,
          },
        ),
      );

      expect(result.selectedProductionNodeIds, <String>['target']);
      expect(result.addedContributionPoints, 4);
      expect(result.selections.single.path.rootNodeId, 'city-a');
      expect(result.selections.single.path.orderedNodeIds, <String>[
        'city-a',
        'a-bridge',
        'target',
      ]);
    });

    test('returns explicit validation and budget exclusions', () {
      final data = _dataset(<BdoWorkerNode>[
        _node(
          'root',
          type: 'City',
          cp: 0,
          links: const <String>['connection', 'costly'],
        ),
        _node('connection', cp: 1, links: const <String>['root']),
        _production('costly', cp: 2, links: const <String>['root']),
        _production('unreachable', cp: 1),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 0,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'bad': 0,
            'missing': 2,
            'connection': 3,
            'unreachable': 4,
            'costly': 5,
          },
        ),
      );

      expect(result.selections, isEmpty);
      expect(
        _exclusion(result, 'bad').reason,
        BdoRawSaleNetworkExclusionReason.invalidValueSignal,
      );
      expect(
        _exclusion(result, 'missing').reason,
        BdoRawSaleNetworkExclusionReason.unknownNode,
      );
      expect(
        _exclusion(result, 'connection').reason,
        BdoRawSaleNetworkExclusionReason.nodeIsNotProductionNode,
      );
      expect(
        _exclusion(result, 'unreachable').reason,
        BdoRawSaleNetworkExclusionReason.unreachableFromAllowedRoots,
      );
      final costly = _exclusion(result, 'costly');
      expect(
        costly.reason,
        BdoRawSaleNetworkExclusionReason
            .exceedsRemainingContributionPointBudget,
      );
      expect(costly.requiredAddedContributionPoints, 2);
    });

    test('preserves a baseline above budget and only takes free choices', () {
      final data = _dataset(<BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['trunk']),
        _node('trunk', cp: 3, links: const <String>['root', 'owned', 'new']),
        _production('owned', cp: 1, links: const <String>['trunk']),
        _production('new', cp: 1, links: const <String>['trunk']),
      ]);

      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 2,
          currentNodeIds: const <String>{'trunk', 'owned'},
          currentSaleValueSignalsByProductionNodeId: const <String, double>{
            'owned': 7,
            'new': 20,
          },
        ),
      );

      expect(result.baselineContributionPoints, 4);
      expect(result.totalContributionPoints, 4);
      expect(result.baselineExceedsBudget, isTrue);
      expect(result.selectedProductionNodeIds, <String>['owned']);
      expect(result.addedNodeIds, isEmpty);
      expect(
        result.diagnostics,
        contains(
          isA<BdoRawSaleNetworkDiagnostic>().having(
            (diagnostic) => diagnostic.code,
            'code',
            BdoRawSaleNetworkDiagnosticCode.baselineExceedsBudget,
          ),
        ),
      );
      expect(
        _exclusion(result, 'new').reason,
        BdoRawSaleNetworkExclusionReason
            .exceedsRemainingContributionPointBudget,
      );
    });
  });

  test(
    'bundled production dataset stays deterministic, connected, and bounded',
    () async {
      final data = await BdoResourceMapLoader.loadBundled();
      final productionNodes = data.workerNodes
          .where((node) => node.isProductionNode && node.outputs.isNotEmpty)
          .toList(growable: false);
      final signals = <String, double>{
        for (final node in productionNodes)
          node.id:
              (1000 +
                      node.outputs.length * 100 +
                      int.parse(node.id).remainder(97))
                  .toDouble(),
      };

      final stopwatch = Stopwatch()..start();
      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 60,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: signals,
        ),
      );
      stopwatch.stop();

      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 15)),
        reason: 'The production dataset should remain interactive in tests.',
      );
      expect(result.selections, isNotEmpty);
      expect(result.totalContributionPoints, lessThanOrEqualTo(60));
      expect(result.baselineContributionPoints, 0);
      expect(result.totalContributionPoints, result.addedContributionPoints);
      expect(
        result.addedNodeIds.fold<int>(
          0,
          (total, nodeId) =>
              total + data.workerNodesById[nodeId]!.contributionPoints,
        ),
        result.addedContributionPoints,
      );
      expect(result.networkNodeIds.toSet(), <String>{
        ...result.currentNodeIds,
        ...result.addedNodeIds,
      });

      final returnedEdges = result.routeEdges.toSet();
      for (final selection in result.selections) {
        final target = data.workerNodesById[selection.productionNodeId];
        expect(target, isNotNull);
        expect(target!.isProductionNode, isTrue);
        expect(selection.path.orderedNodeIds.last, selection.productionNodeId);
        expect(
          selection.path.edges.map(
            (edge) => BdoRawSaleNetworkEdge(edge.fromNodeId, edge.toNodeId),
          ),
          everyElement(isIn(returnedEdges)),
        );
        expect(
          selection.path.connectNodeIds,
          everyElement(isIn(result.networkNodeIds)),
        );
      }
      for (final edge in result.routeEdges) {
        expect(data.workerNodesById, contains(edge.firstNodeId));
        expect(data.workerNodesById, contains(edge.secondNodeId));
      }

      final reversedSignals = <String, double>{
        for (final entry in signals.entries.toList().reversed)
          entry.key: entry.value,
      };
      final repeated = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 60,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: reversedSignals,
        ),
      );
      expect(
        repeated.selectedProductionNodeIds,
        result.selectedProductionNodeIds,
      );
      expect(repeated.addedNodeIds, result.addedNodeIds);
      expect(repeated.routeEdges, result.routeEdges);
      expect(repeated.currentSaleValueSignal, result.currentSaleValueSignal);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'bundled 500 CP portfolio stays responsive at the application budget',
    () async {
      final data = await BdoResourceMapLoader.loadBundled();
      final signals = <String, double>{
        for (final node in data.workerNodes.where(
          (node) => node.isProductionNode && node.outputs.isNotEmpty,
        ))
          node.id:
              (1000 +
                      node.outputs.length * 100 +
                      int.parse(node.id).remainder(97))
                  .toDouble(),
      };

      final stopwatch = Stopwatch()..start();
      final result = const BdoRawSaleNetworkPlanner().plan(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: 500,
          currentNodeIds: const <String>{},
          currentSaleValueSignalsByProductionNodeId: signals,
        ),
      );
      stopwatch.stop();

      expect(result.selections, isNotEmpty);
      expect(result.totalContributionPoints, lessThanOrEqualTo(500));
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason:
            'The saved 500 CP setting must not turn the map action into a '
            'long-running desktop calculation.',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

BdoRawSaleNetworkExclusion _exclusion(
  BdoRawSaleNetworkPlanResult result,
  String nodeId,
) => result.exclusions.singleWhere((exclusion) => exclusion.nodeId == nodeId);

void _expectSamePlan(
  BdoRawSaleNetworkPlanResult actual,
  BdoRawSaleNetworkPlanResult expected,
) {
  expect(actual.quality, expected.quality);
  expect(
    actual.totalContributionPointBudget,
    expected.totalContributionPointBudget,
  );
  expect(actual.currentNodeIds, expected.currentNodeIds);
  expect(actual.addedNodeIds, expected.addedNodeIds);
  expect(actual.networkNodeIds, expected.networkNodeIds);
  expect(actual.routeNodeIds, expected.routeNodeIds);
  expect(actual.routeEdges, expected.routeEdges);
  expect(
    actual.selections
        .map(
          (selection) => <String, Object?>{
            'nodeId': selection.productionNodeId,
            'signal': selection.currentSaleValueSignal,
            'addedCp': selection.addedContributionPointsAtSelection,
            'root': selection.path.rootNodeId,
            'orderedNodeIds': selection.path.orderedNodeIds,
            'retainedNodeIds': selection.path.retainedNodeIds,
            'connectNodeIds': selection.path.connectNodeIds,
            'edges': selection.path.edges
                .map((edge) => <String>[edge.fromNodeId, edge.toNodeId])
                .toList(),
          },
        )
        .toList(),
    expected.selections
        .map(
          (selection) => <String, Object?>{
            'nodeId': selection.productionNodeId,
            'signal': selection.currentSaleValueSignal,
            'addedCp': selection.addedContributionPointsAtSelection,
            'root': selection.path.rootNodeId,
            'orderedNodeIds': selection.path.orderedNodeIds,
            'retainedNodeIds': selection.path.retainedNodeIds,
            'connectNodeIds': selection.path.connectNodeIds,
            'edges': selection.path.edges
                .map((edge) => <String>[edge.fromNodeId, edge.toNodeId])
                .toList(),
          },
        )
        .toList(),
  );
  expect(
    actual.baselineContributionPoints,
    expected.baselineContributionPoints,
  );
  expect(actual.addedContributionPoints, expected.addedContributionPoints);
  expect(actual.totalContributionPoints, expected.totalContributionPoints);
  expect(actual.currentSaleValueSignal, expected.currentSaleValueSignal);
  expect(
    actual.exclusions
        .map(
          (exclusion) => <String, Object?>{
            'nodeId': exclusion.nodeId,
            'reason': exclusion.reason,
            'message': exclusion.message,
            'signal': exclusion.currentSaleValueSignal,
            'requiredCp': exclusion.requiredAddedContributionPoints,
          },
        )
        .toList(),
    expected.exclusions
        .map(
          (exclusion) => <String, Object?>{
            'nodeId': exclusion.nodeId,
            'reason': exclusion.reason,
            'message': exclusion.message,
            'signal': exclusion.currentSaleValueSignal,
            'requiredCp': exclusion.requiredAddedContributionPoints,
          },
        )
        .toList(),
  );
  expect(
    actual.diagnostics
        .map(
          (diagnostic) => <String, Object?>{
            'code': diagnostic.code,
            'severity': diagnostic.severity,
            'message': diagnostic.message,
            'nodeIds': diagnostic.nodeIds,
            'pathCode': diagnostic.pathCode,
          },
        )
        .toList(),
    expected.diagnostics
        .map(
          (diagnostic) => <String, Object?>{
            'code': diagnostic.code,
            'severity': diagnostic.severity,
            'message': diagnostic.message,
            'nodeIds': diagnostic.nodeIds,
            'pathCode': diagnostic.pathCode,
          },
        )
        .toList(),
  );
}

double _sharedPortfolioMarginalSignal(
  String productionNodeId,
  Set<String> selectedProductionNodeIds,
) {
  if (productionNodeId == 'p2' && selectedProductionNodeIds.contains('p1')) {
    return 0;
  }
  return productionNodeId == 'p1' ? 9 : 8;
}

BdoResourceMapDataset _dataset(List<BdoWorkerNode> nodes) {
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'raw-sale-network-test',
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
  List<String> links = const <String>[],
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
