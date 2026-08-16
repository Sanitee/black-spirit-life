import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoNodeNetworkOptimizer exact search', () {
    test('chooses a globally cheaper shared path across resources', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('wood', 'Ash Timber'),
          _resource('ore', 'Iron Ore'),
        ],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['direct-wood', 'direct-ore', 'shared'],
          ),
          _node(
            'direct-wood',
            cp: 3,
            links: const <String>['root', 'wood-direct'],
          ),
          _production(
            'wood-direct',
            cp: 1,
            parent: 'direct-wood',
            outputs: const <String, String>{'wood': 'Ash Timber'},
          ),
          _node(
            'direct-ore',
            cp: 3,
            links: const <String>['root', 'ore-direct'],
          ),
          _production(
            'ore-direct',
            cp: 1,
            parent: 'direct-ore',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
          _node(
            'shared',
            cp: 3,
            links: const <String>['root', 'wood-branch', 'ore-branch'],
          ),
          _node(
            'wood-branch',
            cp: 1,
            links: const <String>['shared', 'wood-shared'],
          ),
          _production(
            'wood-shared',
            cp: 1,
            parent: 'wood-branch',
            outputs: const <String, String>{'wood': 'Ash Timber'},
          ),
          _node(
            'ore-branch',
            cp: 1,
            links: const <String>['shared', 'ore-shared'],
          ),
          _production(
            'ore-shared',
            cp: 1,
            parent: 'ore-branch',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 20,
          desiredResourceNodeCounts: const <String, int>{'wood': 1, 'ore': 1},
        ),
      );

      expect(result.hasErrors, isFalse);
      expect(result.plan, isNotNull);
      expect(result.plan!.isExact, isTrue);
      expect(result.plan!.totalContributionPoints, 7);
      expect(result.plan!.selectedProductionNodeIds, <String>[
        'ore-shared',
        'wood-shared',
      ]);
      expect(
        result.plan!.selectedNodeIds,
        containsAll(<String>[
          'root',
          'shared',
          'wood-branch',
          'wood-shared',
          'ore-branch',
          'ore-shared',
        ]),
      );
      expect(result.plan!.selectedNodeIds, isNot(contains('direct-wood')));
      expect(result.plan!.changeSet.edges, hasLength(5));
    });

    test('uses multiple roots and chooses the cheapest city branch', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('fish', 'Dried Fish')],
        nodes: <BdoWorkerNode>[
          _node(
            'city-a',
            type: 'City',
            cp: 0,
            links: const <String>['expensive'],
          ),
          _node('expensive', cp: 6, links: const <String>['city-a', 'fish-a']),
          _production(
            'fish-a',
            cp: 1,
            parent: 'expensive',
            type: 'Fish Drying Yard',
            outputs: const <String, String>{'fish': 'Dried Fish'},
          ),
          _node('town-b', type: 'Town', cp: 0, links: const <String>['cheap']),
          _node('cheap', cp: 1, links: const <String>['town-b', 'fish-b']),
          _production(
            'fish-b',
            cp: 1,
            parent: 'cheap',
            type: 'Fish Drying Yard',
            outputs: const <String, String>{'fish': 'Dried Fish'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'Dried Fish': 1},
        ),
      );

      expect(result.plan!.totalContributionPoints, 2);
      expect(result.plan!.selectedRootNodeIds, <String>['town-b']);
      expect(result.plan!.selectedProductionNodeIds, <String>['fish-b']);

      final cityAOnly = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'fish': 1},
          rootNodeIds: const <String>{'city-a'},
        ),
      );
      expect(cityAOnly.plan!.totalContributionPoints, 7);
      expect(cityAOnly.plan!.selectedRootNodeIds, <String>['city-a']);
      expect(cityAOnly.plan!.selectedProductionNodeIds, <String>['fish-a']);
    });

    test('only zero-CP cities and towns may act as free roots', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('ash', 'Ash Timber')],
        nodes: <BdoWorkerNode>[
          _node('city', type: 'City', cp: 0, links: const <String>['bridge']),
          _node('bridge', cp: 1, links: const <String>['city', 'ash-node']),
          _node(
            'paid-town',
            type: 'Town',
            cp: 3,
            links: const <String>['ash-node'],
          ),
          _production(
            'ash-node',
            cp: 1,
            parent: 'bridge',
            outputs: const <String, String>{'ash': 'Ash Timber'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'ash': 1},
        ),
      );
      expect(result.plan!.totalContributionPoints, 2);
      expect(result.plan!.selectedRootNodeIds, <String>['city']);

      final invalid = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'ash': 1},
          rootNodeIds: const <String>{'paid-town'},
        ),
      );
      expect(invalid.plan, isNull);
      expect(
        invalid.diagnostics.map((item) => item.code),
        contains(BdoNodeNetworkDiagnosticCode.invalidRootNode),
      );
    });

    test('honors requested distinct-node counts and aliases', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('ash', 'Ash Timber', aliases: const <String>['Ash Log']),
        ],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['ash-1', 'ash-2', 'long'],
          ),
          _production(
            'ash-1',
            cp: 1,
            parent: 'root',
            outputs: const <String, String>{'ash': 'Ash Timber'},
          ),
          _production(
            'ash-2',
            cp: 2,
            parent: 'root',
            outputs: const <String, String>{'ash': 'Ash Timber'},
          ),
          _node('long', cp: 8, links: const <String>['root', 'ash-3']),
          _production(
            'ash-3',
            cp: 1,
            parent: 'long',
            outputs: const <String, String>{'ash': 'Ash Timber'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 20,
          desiredResourceNodeCounts: const <String, int>{'  ash   LOG ': 2},
        ),
      );

      expect(result.plan!.requestedNodeCountByResource, <String, int>{
        'ash': 2,
      });
      expect(result.plan!.workerNodeIdsByResource['ash'], <String>[
        'ash-1',
        'ash-2',
      ]);
      expect(result.plan!.totalContributionPoints, 3);
    });

    test('one shared production node can satisfy two requested outputs', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('timber', 'Thuja Timber'),
          _resource('sap', 'Thuja Sap'),
        ],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['thuja', 'timber-only', 'sap-only'],
          ),
          _production(
            'thuja',
            cp: 2,
            parent: 'root',
            outputs: const <String, String>{
              'timber': 'Thuja Timber',
              'sap': 'Thuja Sap',
            },
          ),
          _production(
            'timber-only',
            cp: 2,
            parent: 'root',
            outputs: const <String, String>{'timber': 'Thuja Timber'},
          ),
          _production(
            'sap-only',
            cp: 2,
            parent: 'root',
            outputs: const <String, String>{'sap': 'Thuja Sap'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'timber': 1, 'sap': 1},
        ),
      );

      expect(result.plan!.selectedProductionNodeIds, <String>['thuja']);
      expect(result.plan!.workerNodeIdsByResource, <String, List<String>>{
        'sap': <String>['thuja'],
        'timber': <String>['thuja'],
      });
      expect(result.plan!.totalContributionPoints, 2);
    });

    test('exact limits count shared terminal sets, not resource rows', () {
      final resources = <BdoResourceDefinition>[
        for (var index = 0; index < 11; index++)
          _resource('resource-$index', 'Resource $index'),
      ];
      final outputs = <String, String>{
        for (var index = 0; index < 11; index++)
          'resource-$index': 'Resource $index',
      };
      final data = _dataset(
        resources: resources,
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['shared-cheap', 'shared-expensive'],
          ),
          _production('shared-cheap', cp: 1, parent: 'root', outputs: outputs),
          _production(
            'shared-expensive',
            cp: 2,
            parent: 'root',
            outputs: outputs,
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: <String, int>{
            for (var index = 0; index < 11; index++) 'resource-$index': 1,
          },
        ),
      );

      expect(result.hasErrors, isFalse);
      expect(result.plan, isNotNull);
      expect(result.plan!.isExact, isTrue);
      expect(result.plan!.selectedProductionNodeIds, <String>['shared-cheap']);
      expect(result.plan!.totalContributionPoints, 1);
    });

    test('prefers retained nodes after total CP in an exact tie', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('wood', 'Ash Timber')],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['left', 'right'],
          ),
          _node(
            'left',
            cp: 1,
            links: const <String>['root', 'left-production'],
          ),
          _production(
            'left-production',
            cp: 1,
            parent: 'left',
            outputs: const <String, String>{'wood': 'Ash Timber'},
          ),
          _node(
            'right',
            cp: 1,
            links: const <String>['root', 'right-production'],
          ),
          _production(
            'right-production',
            cp: 1,
            parent: 'right',
            outputs: const <String, String>{'wood': 'Ash Timber'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'wood': 1},
          currentNodeIds: const <String>{'right', 'right-production'},
        ),
      );

      expect(result.plan!.selectedProductionNodeIds, <String>[
        'right-production',
      ]);
      expect(result.plan!.changeSet.retainedNodeIds, <String>[
        'right',
        'right-production',
      ]);
      expect(result.plan!.changeSet.connectNodeIds, isEmpty);
      expect(result.plan!.changeSet.disconnectNodeIds, isEmpty);
      expect(
        result.plan!.changeSet.edges.map((edge) => edge.kind).toSet(),
        <BdoNodeNetworkChangeKind>{BdoNodeNetworkChangeKind.retained},
      );
    });

    test(
      'recomputes all routes when a removed target ends a sharing discount',
      () {
        final data = _dataset(
          resources: <BdoResourceDefinition>[
            _resource('x', 'X Material'),
            _resource('y', 'Y Material'),
          ],
          nodes: <BdoWorkerNode>[
            _node(
              'root',
              type: 'City',
              cp: 0,
              links: const <String>['shared', 'x-direct', 'y-direct'],
            ),
            _node(
              'shared',
              cp: 3,
              links: const <String>['root', 'x-shared', 'y-shared'],
            ),
            _production(
              'x-shared',
              cp: 1,
              parent: 'shared',
              outputs: const <String, String>{'x': 'X Material'},
            ),
            _production(
              'y-shared',
              cp: 1,
              parent: 'shared',
              outputs: const <String, String>{'y': 'Y Material'},
            ),
            _production(
              'x-direct',
              cp: 4,
              parent: 'root',
              outputs: const <String, String>{'x': 'X Material'},
            ),
            _production(
              'y-direct',
              cp: 2,
              parent: 'root',
              outputs: const <String, String>{'y': 'Y Material'},
            ),
          ],
        );
        const optimizer = BdoNodeNetworkOptimizer();
        final sharedPlan = optimizer.optimize(
          data: data,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: <String, int>{'x': 1, 'y': 1},
          ),
        );

        expect(sharedPlan.plan!.totalContributionPoints, 5);
        expect(sharedPlan.plan!.selectedProductionNodeIds, <String>[
          'x-shared',
          'y-shared',
        ]);

        final recomputed = optimizer.optimize(
          data: data,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'y': 1},
            currentNodeIds: sharedPlan.plan!.selectedNodeIds.toSet(),
          ),
        );

        expect(recomputed.plan!.totalContributionPoints, 2);
        expect(recomputed.plan!.selectedProductionNodeIds, <String>[
          'y-direct',
        ]);
        expect(recomputed.plan!.changeSet.connectNodeIds, contains('y-direct'));
        expect(
          recomputed.plan!.changeSet.disconnectNodeIds,
          containsAll(<String>['shared', 'x-shared', 'y-shared']),
        );
      },
    );
  });

  group('saved-network changes and diagnostics', () {
    test('classifies retained, connect, and disconnect nodes and edges', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('old', 'Old Timber'),
          _resource('new', 'New Ore'),
        ],
        nodes: <BdoWorkerNode>[
          _node('root', type: 'City', cp: 0, links: const <String>['trunk']),
          _node(
            'trunk',
            cp: 2,
            links: const <String>['root', 'old-production', 'new-production'],
          ),
          _production(
            'old-production',
            cp: 1,
            parent: 'trunk',
            outputs: const <String, String>{'old': 'Old Timber'},
          ),
          _production(
            'new-production',
            cp: 1,
            parent: 'trunk',
            outputs: const <String, String>{'new': 'New Ore'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'new': 1},
          currentNodeIds: const <String>{'trunk', 'old-production'},
        ),
      );
      final changes = result.plan!.changeSet;

      expect(changes.retainedNodeIds, <String>['trunk']);
      expect(changes.connectNodeIds, <String>['new-production']);
      expect(changes.disconnectNodeIds, <String>['old-production']);
      expect(changes.connectContributionPoints, 1);
      expect(changes.disconnectContributionPoints, 1);
      expect(changes.netContributionPointChange, 0);
      expect(_edgeKinds(changes), <String, BdoNodeNetworkChangeKind>{
        'root-trunk': BdoNodeNetworkChangeKind.retained,
        'new-production-trunk': BdoNodeNetworkChangeKind.connect,
        'old-production-trunk': BdoNodeNetworkChangeKind.disconnect,
      });
    });

    test('reports factual unlinked production nodes as unreachable', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('sap', 'Rare Sap')],
        nodes: <BdoWorkerNode>[
          _node('root', type: 'City', cp: 0, links: const <String>['linked']),
          _production(
            'linked',
            cp: 1,
            parent: 'root',
            outputs: const <String, String>{'sap': 'Rare Sap'},
          ),
          _production(
            'unlinked',
            cp: 1,
            parent: null,
            outputs: const <String, String>{'sap': 'Rare Sap'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'sap': 2},
        ),
      );

      expect(result.plan, isNull);
      expect(result.hasErrors, isTrue);
      final diagnostic = result.diagnostics.singleWhere(
        (item) =>
            item.code ==
            BdoNodeNetworkDiagnosticCode.unreachableProductionNodes,
      );
      expect(diagnostic.nodeIds, <String>['unlinked']);
    });

    test('returns the cheapest complete plan with an over-budget warning', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('ore', 'Iron Ore')],
        nodes: <BdoWorkerNode>[
          _node('root', type: 'City', cp: 0, links: const <String>['path']),
          _node('path', cp: 4, links: const <String>['root', 'ore']),
          _production(
            'ore',
            cp: 2,
            parent: 'path',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 5,
          desiredResourceNodeCounts: const <String, int>{'ore': 1},
        ),
      );

      expect(result.plan, isNotNull);
      expect(result.plan!.totalContributionPoints, 6);
      expect(result.plan!.isWithinBudget, isFalse);
      expect(result.plan!.remainingContributionPoints, -1);
      expect(
        result.diagnostics.any(
          (item) =>
              item.code ==
              BdoNodeNetworkDiagnosticCode.contributionPointBudgetExceeded,
        ),
        isTrue,
      );
    });
  });

  group('network optimizer invariants', () {
    test('scalable over-budget warning describes only the proposed route', () {
      final resources = <BdoResourceDefinition>[
        for (var index = 0; index < 6; index++)
          _resource('resource-$index', 'Resource $index'),
      ];
      final allOutputs = <String, String>{
        for (var index = 0; index < 6; index++)
          'resource-$index': 'Resource $index',
      };
      final firstFourOutputs = <String, String>{
        for (var index = 0; index < 4; index++)
          'resource-$index': 'Resource $index',
      };
      final lastTwoOutputs = <String, String>{
        for (var index = 4; index < 6; index++)
          'resource-$index': 'Resource $index',
      };
      final data = _dataset(
        resources: resources,
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['all', 'first-four', 'last-two'],
          ),
          _production('all', cp: 4, parent: 'root', outputs: allOutputs),
          _production(
            'first-four',
            cp: 2,
            parent: 'root',
            outputs: firstFourOutputs,
          ),
          _production(
            'last-two',
            cp: 3,
            parent: 'root',
            outputs: lastTwoOutputs,
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 4,
          desiredResourceNodeCounts: <String, int>{
            for (var index = 0; index < 6; index++) 'resource-$index': 1,
          },
          maxExactTerminalNodes: 1,
        ),
      );

      expect(result.plan, isNotNull);
      expect(result.plan!.usesScalableOptimization, isTrue);
      expect(result.plan!.selectedProductionNodeIds, <String>[
        'first-four',
        'last-two',
      ]);
      expect(result.plan!.totalContributionPoints, 5);
      expect(result.plan!.isWithinBudget, isFalse);
      final warning = result.diagnostics.singleWhere(
        (diagnostic) =>
            diagnostic.code ==
            BdoNodeNetworkDiagnosticCode.contributionPointBudgetExceeded,
      );
      expect(warning.message, contains('proposed scalable route'));
      expect(warning.message, contains('does not prove'));
      expect(warning.message, isNot(contains('cheapest')));
    });

    test('saved node investments retain every induced real cycle edge', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('x', 'X Material'),
          _resource('y', 'Y Material'),
        ],
        nodes: <BdoWorkerNode>[
          _node('root', type: 'City', cp: 0, links: const <String>['a', 'b']),
          _node('a', cp: 1, links: const <String>['root', 'b', 'x-production']),
          _node('b', cp: 1, links: const <String>['root', 'a', 'y-production']),
          _production(
            'x-production',
            cp: 1,
            parent: 'a',
            outputs: const <String, String>{'x': 'X Material'},
          ),
          _production(
            'y-production',
            cp: 1,
            parent: 'b',
            outputs: const <String, String>{'y': 'Y Material'},
          ),
        ],
      );
      const optimizer = BdoNodeNetworkOptimizer();
      final first = optimizer.optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
        ),
      );

      expect(first.plan!.changeSet.edges, hasLength(5));
      expect(
        first.plan!.changeSet.edges.map((edge) => edge.key),
        contains('a\u0000b'),
      );

      final unchanged = optimizer.optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
          currentNodeIds: first.plan!.selectedNodeIds.toSet(),
        ),
      );

      expect(unchanged.plan!.changeSet.connectNodeIds, isEmpty);
      expect(unchanged.plan!.changeSet.disconnectNodeIds, isEmpty);
      expect(unchanged.plan!.changeSet.edges, hasLength(5));
      expect(
        unchanged.plan!.changeSet.edges.map((edge) => edge.kind).toSet(),
        <BdoNodeNetworkChangeKind>{BdoNodeNetworkChangeKind.retained},
      );
    });

    test('production nodes stay endpoints in exact and scalable routes', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('x', 'X Material'),
          _resource('y', 'Y Material'),
        ],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['x-production', 'expensive'],
          ),
          _production(
            'x-production',
            cp: 1,
            parent: 'root',
            links: const <String>['root', 'junction'],
            outputs: const <String, String>{'x': 'X Material'},
          ),
          _node('expensive', cp: 8, links: const <String>['root', 'junction']),
          _node(
            'junction',
            cp: 1,
            links: const <String>['x-production', 'expensive', 'y-production'],
          ),
          _production(
            'y-production',
            cp: 1,
            parent: 'junction',
            outputs: const <String, String>{'y': 'Y Material'},
          ),
        ],
      );

      for (final exactLimit in <int>[10, 1]) {
        final result = const BdoNodeNetworkOptimizer().optimize(
          data: data,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
            maxExactTerminalNodes: exactLimit,
          ),
        );

        expect(result.hasErrors, isFalse, reason: 'exact limit $exactLimit');
        expect(
          result.plan!.isExact,
          exactLimit == 10,
          reason: 'exact limit $exactLimit',
        );
        expect(
          result.plan!.totalContributionPoints,
          11,
          reason: 'exact limit $exactLimit',
        );
        expect(
          result.plan!.changeSet.edges.map((edge) => edge.key),
          isNot(contains('junction\u0000x-production')),
          reason: 'A production endpoint cannot become a route trunk.',
        );
      }
    });

    test('unsafe nonnegative CP costs return an actionable diagnostic', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('ore', 'Iron Ore')],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['ore-production'],
          ),
          _production(
            'ore-production',
            cp: 1 << 62,
            parent: 'root',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 500,
          desiredResourceNodeCounts: const <String, int>{'ore': 1},
        ),
      );

      expect(result.plan, isNull);
      final diagnostic = result.diagnostics.singleWhere(
        (item) =>
            item.code ==
            BdoNodeNetworkDiagnosticCode.unsafeNodeContributionPoints,
      );
      expect(diagnostic.severity, BdoNodeNetworkDiagnosticSeverity.error);
      expect(diagnostic.nodeIds, <String>['ore-production']);
      expect(diagnostic.message, contains('safe optimization limit'));
      expect(diagnostic.message, contains('Correct the listed map records'));
    });

    test('scalable coverage ratios stay exact near the safe CP limit', () {
      final commonResources = <BdoResourceDefinition>[
        for (var index = 0; index < 100; index++)
          _resource('common-$index', 'Common Material $index'),
      ];
      final commonOutputs = <String, String>{
        for (var index = 0; index < 100; index++)
          'common-$index': 'Common Material $index',
      };
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          ...commonResources,
          _resource('unique-1', 'Unique Material 1'),
          _resource('unique-2', 'Unique Material 2'),
        ],
        nodes: <BdoWorkerNode>[
          _node(
            'root',
            type: 'City',
            cp: 0,
            links: const <String>['trunk-a', 'trunk-b'],
          ),
          _node(
            'trunk-a',
            cp: 40_000_000_000_000_000,
            links: const <String>[
              'root',
              'all-common',
              'unique-1-a',
              'unique-2-a',
            ],
          ),
          _node(
            'trunk-b',
            cp: 10_000_000_000_000_000,
            links: const <String>[
              'root',
              'bait-common',
              'unique-1-b',
              'unique-2-b',
            ],
          ),
          _production(
            'all-common',
            cp: 40_000_000_000_000_000,
            parent: 'trunk-a',
            outputs: commonOutputs,
          ),
          _production(
            'bait-common',
            cp: 10_000_000_000_000_000,
            parent: 'trunk-b',
            outputs: const <String, String>{'common-0': 'Common Material 0'},
          ),
          _production(
            'unique-1-a',
            cp: 1,
            parent: 'trunk-a',
            outputs: const <String, String>{'unique-1': 'Unique Material 1'},
          ),
          _production(
            'unique-1-b',
            cp: 1,
            parent: 'trunk-b',
            outputs: const <String, String>{'unique-1': 'Unique Material 1'},
          ),
          _production(
            'unique-2-a',
            cp: 1,
            parent: 'trunk-a',
            outputs: const <String, String>{'unique-2': 'Unique Material 2'},
          ),
          _production(
            'unique-2-b',
            cp: 1,
            parent: 'trunk-b',
            outputs: const <String, String>{'unique-2': 'Unique Material 2'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 100_000_000_000_000_000,
          desiredResourceNodeCounts: <String, int>{
            for (var index = 0; index < 100; index++) 'common-$index': 1,
            'unique-1': 1,
            'unique-2': 1,
          },
          maxExactTerminalNodes: 1,
        ),
      );

      expect(result.hasErrors, isFalse);
      expect(result.plan!.usesScalableOptimization, isTrue);
      expect(result.plan!.totalContributionPoints, 80_000_000_000_000_002);
      expect(result.plan!.selectedNodeIds, isNot(contains('trunk-b')));
      expect(result.plan!.selectedProductionNodeIds, <String>[
        'all-common',
        'unique-1-a',
        'unique-2-a',
      ]);
    });

    test('equal-cost exact terminal sets use numeric graph-index order', () {
      const candidateIds = <String>[
        '02-low-a',
        '03-low-b',
        '10-high-a',
        '11-high-b',
      ];
      final data = _dataset(
        resources: <BdoResourceDefinition>[_resource('ore', 'Iron Ore')],
        nodes: <BdoWorkerNode>[
          _node('00-root', type: 'City', cp: 0, links: candidateIds),
          _node('01-filler', cp: 0),
          _production(
            '02-low-a',
            cp: 1,
            parent: '00-root',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
          _production(
            '03-low-b',
            cp: 1,
            parent: '00-root',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
          for (var index = 4; index < 10; index++)
            _node('0$index-filler', cp: 0),
          _production(
            '10-high-a',
            cp: 1,
            parent: '00-root',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
          _production(
            '11-high-b',
            cp: 1,
            parent: '00-root',
            outputs: const <String, String>{'ore': 'Iron Ore'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{'ore': 2},
        ),
      );

      expect(result.plan, isNotNull);
      expect(result.plan!.selectedProductionNodeIds, <String>[
        '02-low-a',
        '03-low-b',
      ]);
    });

    test('equal-cost scalable improvements use numeric graph-index order', () {
      final data = _dataset(
        resources: <BdoResourceDefinition>[
          _resource('primary', 'Primary Material'),
          _resource('anchor', 'Anchor Material'),
        ],
        nodes: <BdoWorkerNode>[
          _node(
            '00-root',
            type: 'City',
            cp: 0,
            links: const <String>['01-trunk', '10-high'],
          ),
          _node(
            '01-trunk',
            cp: 3,
            links: const <String>['00-root', '02-low', '11-anchor-production'],
          ),
          _production(
            '02-low',
            cp: 2,
            parent: '01-trunk',
            outputs: const <String, String>{'primary': 'Primary Material'},
          ),
          for (var index = 3; index < 10; index++)
            _node('0$index-filler', cp: 0),
          _production(
            '10-high',
            cp: 2,
            parent: '00-root',
            outputs: const <String, String>{'primary': 'Primary Material'},
          ),
          _production(
            '11-anchor-production',
            cp: 1,
            parent: '01-trunk',
            outputs: const <String, String>{'anchor': 'Anchor Material'},
          ),
        ],
      );

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 10,
          desiredResourceNodeCounts: const <String, int>{
            'primary': 1,
            'anchor': 1,
          },
          maxExactTerminalNodes: 1,
        ),
      );

      expect(result.hasErrors, isFalse);
      expect(result.plan!.usesScalableOptimization, isTrue);
      expect(result.plan!.totalContributionPoints, 6);
      expect(result.plan!.selectedProductionNodeIds, <String>[
        '02-low',
        '11-anchor-production',
      ]);
    });
  });

  test(
    'solves one-node resource groups exactly without enumerating combinations',
    () {
      final resources = <BdoResourceDefinition>[
        _resource('herb', 'Sunrise Herb'),
        _resource('sap', 'Ash Sap'),
        _resource('ore', 'Iron Ore'),
      ];
      final nodes = <BdoWorkerNode>[
        _node('root', type: 'City', cp: 0, links: const <String>['shared']),
        _node('shared', cp: 4, links: const <String>['root']),
      ];
      for (final resource in resources) {
        nodes.add(
          _production(
            '${resource.id}-shared',
            cp: 1,
            parent: 'shared',
            outputs: <String, String>{resource.id: resource.name},
          ),
        );
        for (var index = 1; index < 7; index++) {
          nodes.add(
            _production(
              '${resource.id}-direct-$index',
              cp: 10 + index,
              parent: 'root',
              outputs: <String, String>{resource.id: resource.name},
            ),
          );
        }
      }
      final data = _dataset(resources: resources, nodes: nodes);

      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 20,
          desiredResourceNodeCounts: const <String, int>{
            'herb': 1,
            'sap': 1,
            'ore': 1,
          },
          // Seven choices per resource create 343 terminal selections. The
          // direct group solver must not use this enumeration-only limit.
          maxExactSelectionCombinations: 1,
        ),
      );

      expect(result.hasErrors, isFalse);
      expect(result.plan, isNotNull);
      expect(result.plan!.isExact, isTrue);
      expect(result.plan!.totalContributionPoints, 7);
      expect(result.plan!.selectedProductionNodeIds, <String>[
        'herb-shared',
        'ore-shared',
        'sap-shared',
      ]);
      expect(result.plan!.changeSet.edges, hasLength(4));
    },
  );

  test('uses connected deterministic large-plan routes for both grouped and '
      'repeated-node requests', () {
    final data = _dataset(
      resources: <BdoResourceDefinition>[
        _resource('wood', 'Ash Timber'),
        _resource('ore', 'Iron Ore'),
      ],
      nodes: <BdoWorkerNode>[
        _node(
          'root',
          type: 'City',
          cp: 0,
          links: const <String>['common', 'wood-b', 'ore-b'],
        ),
        _node(
          'common',
          cp: 1,
          links: const <String>['root', 'wood-a', 'ore-a'],
        ),
        _production(
          'wood-a',
          cp: 1,
          parent: 'common',
          outputs: const <String, String>{'wood': 'Ash Timber'},
        ),
        _production(
          'ore-a',
          cp: 1,
          parent: 'common',
          outputs: const <String, String>{'ore': 'Iron Ore'},
        ),
        _production(
          'wood-b',
          cp: 4,
          parent: 'root',
          outputs: const <String, String>{'wood': 'Ash Timber'},
        ),
        _production(
          'ore-b',
          cp: 4,
          parent: 'root',
          outputs: const <String, String>{'ore': 'Iron Ore'},
        ),
      ],
    );

    final scalable = const BdoNodeNetworkOptimizer().optimize(
      data: data,
      request: BdoNodeNetworkRequest(
        contributionPointBudget: 20,
        desiredResourceNodeCounts: const <String, int>{'wood': 1, 'ore': 1},
        maxExactTerminalNodes: 1,
      ),
    );
    expect(scalable.plan, isNotNull);
    expect(scalable.hasErrors, isFalse);
    expect(scalable.plan!.isExact, isFalse);
    expect(scalable.plan!.usesScalableOptimization, isTrue);
    expect(scalable.plan!.selectedProductionNodeIds, <String>[
      'ore-a',
      'wood-a',
    ]);
    expect(scalable.plan!.changeSet.edges, hasLength(3));
    expect(
      scalable.diagnostics
          .singleWhere(
            (item) =>
                item.code ==
                BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed,
          )
          .severity,
      BdoNodeNetworkDiagnosticSeverity.info,
    );

    final repeated = const BdoNodeNetworkOptimizer().optimize(
      data: data,
      request: BdoNodeNetworkRequest(
        contributionPointBudget: 20,
        desiredResourceNodeCounts: const <String, int>{'wood': 2, 'ore': 1},
        maxExactSelectionCombinations: 1,
      ),
    );
    expect(repeated.plan, isNotNull);
    expect(repeated.hasErrors, isFalse);
    expect(repeated.plan!.usesScalableOptimization, isTrue);
    expect(repeated.plan!.workerNodeIdsByResource['wood'], hasLength(2));
    expect(repeated.plan!.workerNodeIdsByResource['ore'], hasLength(1));
    expect(repeated.plan!.selectedProductionNodeIds, <String>[
      'ore-a',
      'wood-a',
      'wood-b',
    ]);
    expect(repeated.plan!.changeSet.edges, hasLength(4));
    final diagnostic = repeated.diagnostics.singleWhere(
      (item) =>
          item.code == BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed,
    );
    expect(diagnostic.severity, BdoNodeNetworkDiagnosticSeverity.info);
    expect(diagnostic.message, contains('every requested production-node'));
  });

  test(
    'bundled current dataset can optimize a real worker output by name',
    () async {
      final data = await BdoResourceMapLoader.loadBundled();
      final result = const BdoNodeNetworkOptimizer().optimize(
        data: data,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 500,
          desiredResourceNodeCounts: const <String, int>{'Ash Timber': 1},
        ),
      );

      expect(result.plan, isNotNull);
      expect(result.hasErrors, isFalse);
      expect(result.plan!.workerNodeIdsByResource.values.single, isNotEmpty);
      expect(result.plan!.selectedRootNodeIds, isNotEmpty);
    },
  );

  test('bundled Alchemy materials with hundreds of candidate combinations '
      'still return an exact connected plan', () async {
    final data = await BdoResourceMapLoader.loadBundled();
    const requested = <String, int>{
      'item:5005': 1, // Bloody Tree Knot
      'item:5006': 1, // Spirit's Leaf
      'item:5007': 1, // Monk's Branch
    };
    final candidateProduct = requested.keys.fold<int>(
      1,
      (product, resourceId) =>
          product * data.workerNodesForResource(resourceId).length,
    );
    expect(candidateProduct, greaterThan(256));

    final result = const BdoNodeNetworkOptimizer().optimize(
      data: data,
      request: BdoNodeNetworkRequest(
        contributionPointBudget: 500,
        desiredResourceNodeCounts: requested,
      ),
    );

    expect(result.hasErrors, isFalse);
    expect(result.plan, isNotNull);
    expect(result.plan!.isExact, isTrue);
    expect(result.plan!.workerNodeIdsByResource.keys, requested.keys);
    expect(
      result.plan!.workerNodeIdsByResource.values,
      everyElement(isNotEmpty),
    );
    expect(result.plan!.changeSet.edges, isNotEmpty);
    expect(
      result.diagnostics,
      isNot(
        contains(
          isA<BdoNodeNetworkDiagnostic>().having(
            (diagnostic) => diagnostic.code,
            'code',
            BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded,
          ),
        ),
      ),
    );
  });

  test('bundled 28-material worker portfolio returns a complete connected '
      'scalable route', () async {
    final data = await BdoResourceMapLoader.loadBundled();
    final requestedIds = data.resources
        .where(
          (resource) => data.workerNodesForResource(resource.id).isNotEmpty,
        )
        .map((resource) => resource.id)
        .take(28)
        .toList(growable: false);
    expect(requestedIds, hasLength(28));
    final requested = <String, int>{
      for (final resourceId in requestedIds) resourceId: 1,
    };

    final optimizer = const BdoNodeNetworkOptimizer();
    final first = optimizer.optimize(
      data: data,
      request: BdoNodeNetworkRequest(
        contributionPointBudget: 500,
        desiredResourceNodeCounts: requested,
      ),
    );
    final second = optimizer.optimize(
      data: data,
      request: BdoNodeNetworkRequest(
        contributionPointBudget: 500,
        desiredResourceNodeCounts: requested,
      ),
    );

    expect(first.hasErrors, isFalse);
    expect(first.plan, isNotNull);
    expect(first.plan!.usesScalableOptimization, isTrue);
    expect(
      first.plan!.workerNodeIdsByResource.keys.toSet(),
      requested.keys.toSet(),
    );
    expect(
      first.plan!.workerNodeIdsByResource.values,
      everyElement(isNotEmpty),
    );
    expect(first.plan!.selectedRootNodeIds, isNotEmpty);
    expect(first.plan!.changeSet.edges, isNotEmpty);
    expect(
      first.plan!.changeSet.edges.map((edge) => edge.key).toSet().length,
      first.plan!.changeSet.edges.length,
    );
    final routeAdjacency = <String, Set<String>>{};
    for (final edge in first.plan!.changeSet.edges) {
      routeAdjacency
          .putIfAbsent(edge.firstNodeId, () => <String>{})
          .add(edge.secondNodeId);
      routeAdjacency
          .putIfAbsent(edge.secondNodeId, () => <String>{})
          .add(edge.firstNodeId);
      final firstNode = data.workerNodesById[edge.firstNodeId]!;
      final secondNode = data.workerNodesById[edge.secondNodeId]!;
      expect(
        firstNode.linkIds.contains(secondNode.id) ||
            secondNode.linkIds.contains(firstNode.id),
        isTrue,
        reason: 'Every drawn route segment must be a real map connection.',
      );
    }
    final reached = <String>{...first.plan!.selectedRootNodeIds};
    final pending = <String>[...first.plan!.selectedRootNodeIds];
    while (pending.isNotEmpty) {
      final nodeId = pending.removeLast();
      for (final neighbor in routeAdjacency[nodeId] ?? const <String>{}) {
        if (reached.add(neighbor)) {
          pending.add(neighbor);
        }
      }
    }
    expect(
      reached,
      containsAll(first.plan!.selectedNodeIds),
      reason: 'Every selected node must have a drawn path to a town root.',
    );
    expect(
      second.plan!.totalContributionPoints,
      first.plan!.totalContributionPoints,
    );
    expect(second.plan!.selectedNodeIds, first.plan!.selectedNodeIds);
    expect(
      second.plan!.changeSet.edges.map((edge) => edge.key),
      first.plan!.changeSet.edges.map((edge) => edge.key),
    );
    expect(
      first.diagnostics.map((item) => item.code),
      contains(BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed),
    );
  });
}

Map<String, BdoNodeNetworkChangeKind> _edgeKinds(
  BdoNodeNetworkChangeSet changes,
) {
  return <String, BdoNodeNetworkChangeKind>{
    for (final edge in changes.edges)
      '${edge.firstNodeId}-${edge.secondNodeId}': edge.kind,
  };
}

BdoResourceMapDataset _dataset({
  required List<BdoResourceDefinition> resources,
  required List<BdoWorkerNode> nodes,
}) {
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'network-test',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: resources,
    workerNodes: nodes,
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

BdoResourceDefinition _resource(
  String id,
  String name, {
  List<String> aliases = const <String>[],
}) {
  return BdoResourceDefinition(
    id: id,
    name: name,
    category: 'Test',
    section: BdoResourceSection.other,
    aliases: aliases,
    acquisitionModes: const <BdoAcquisitionMode>{BdoAcquisitionMode.workerNode},
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
  required String? parent,
  List<String>? links,
  String type = 'Gathering',
  required Map<String, String> outputs,
}) {
  return BdoWorkerNode(
    id: id,
    name: id,
    nodeType: type,
    region: 'Test',
    location: const BdoWorldPoint(0, 0),
    contributionPoints: cp,
    linkIds: links ?? (parent == null ? const <String>[] : <String>[parent]),
    outputs: <BdoNodeOutput>[
      for (final entry in outputs.entries)
        BdoNodeOutput(
          resourceId: entry.key,
          name: entry.value,
          isPrimary: true,
        ),
    ],
    isResourceNode: true,
    isProductionNode: true,
    parentId: parent,
  );
}
