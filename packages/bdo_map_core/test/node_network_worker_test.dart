import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BdoNodeNetworkWorker', () {
    test(
      'reuses one prepared graph across sequential reroute requests',
      () async {
        final data = _rerouteDataset();
        final worker = await BdoNodeNetworkWorker.start(data);
        addTearDown(worker.dispose);

        final shared = await worker.optimize(
          generation: 1,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
          ),
        );
        expect(shared.requestId, 1);
        expect(shared.generation, 1);
        expect(shared.result.plan!.totalContributionPoints, 5);
        expect(shared.result.plan!.selectedProductionNodeIds, <String>[
          'x-shared',
          'y-shared',
        ]);

        final rerouted = await worker.optimize(
          generation: 2,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'y': 1},
            currentNodeIds: shared.result.plan!.selectedNodeIds.toSet(),
          ),
        );
        expect(rerouted.requestId, 2);
        expect(rerouted.generation, 2);
        expect(rerouted.result.plan!.isExact, isTrue);
        expect(rerouted.result.plan!.totalContributionPoints, 2);
        expect(rerouted.result.plan!.selectedProductionNodeIds, <String>[
          'y-direct',
        ]);
        expect(
          rerouted.result.plan!.changeSet.disconnectNodeIds,
          containsAll(<String>['shared', 'x-shared', 'y-shared']),
        );
      },
    );

    test(
      'echoes generations so the UI can reject a superseded result',
      () async {
        final worker = await BdoNodeNetworkWorker.start(_rerouteDataset());
        addTearDown(worker.dispose);

        final olderFuture = worker.optimize(
          generation: 40,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
          ),
        );
        final currentFuture = worker.optimize(
          generation: 41,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'y': 1},
          ),
        );
        final responses = await Future.wait(
          <Future<BdoNodeNetworkWorkerResponse>>[olderFuture, currentFuture],
        );

        expect(responses[0].requestId, 1);
        expect(responses[1].requestId, 2);
        expect(responses[0].belongsToGeneration(41), isFalse);
        expect(responses[1].belongsToGeneration(41), isTrue);
      },
    );

    test('dispose is idempotent and rejects later requests', () async {
      final worker = await BdoNodeNetworkWorker.start(_rerouteDataset());

      expect(worker.isRunning, isTrue);
      final pending = worker.optimize(
        generation: 1,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 20,
          desiredResourceNodeCounts: const <String, int>{'x': 1, 'y': 1},
        ),
      );
      final firstDispose = worker.dispose();
      await expectLater(
        pending,
        throwsA(isA<BdoNodeNetworkWorkerDisposedException>()),
      );
      await firstDispose;
      await worker.dispose();

      expect(worker.isDisposed, isTrue);
      expect(worker.isRunning, isFalse);
      await expectLater(
        worker.optimize(
          generation: 1,
          request: BdoNodeNetworkRequest(
            contributionPointBudget: 20,
            desiredResourceNodeCounts: const <String, int>{'y': 1},
          ),
        ),
        throwsA(isA<BdoNodeNetworkWorkerDisposedException>()),
      );
    });

    testWidgets('unawaited widget teardown leaves no pending timer', (
      tester,
    ) async {
      late final BdoNodeNetworkWorker worker;
      await tester.runAsync(() async {
        worker = await BdoNodeNetworkWorker.start(_rerouteDataset());
      });

      unawaited(worker.dispose());
      await tester.pump();

      expect(worker.isDisposed, isTrue);
    });

    test('a remote request failure is deterministic and recoverable', () async {
      final worker = await BdoNodeNetworkWorker.start(_rerouteDataset());
      addTearDown(worker.dispose);

      await expectLater(
        worker.optimize(generation: 1, request: _ThrowingNodeNetworkRequest()),
        throwsA(
          isA<BdoNodeNetworkWorkerException>()
              .having(
                (error) => error.message,
                'message',
                contains('failed in the worker'),
              )
              .having(
                (error) => error.remoteStackTrace,
                'remoteStackTrace',
                isNot(isEmpty),
              )
              .having((error) => error.requestId, 'requestId', 1)
              .having((error) => error.generation, 'generation', 1),
        ),
      );

      final recovered = await worker.optimize(
        generation: 2,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 20,
          desiredResourceNodeCounts: const <String, int>{'y': 1},
        ),
      );
      expect(recovered.requestId, 2);
      expect(recovered.result.plan!.selectedProductionNodeIds, <String>[
        'y-direct',
      ]);
      expect(worker.isRunning, isTrue);
    });

    test('prepares and queries the bundled worker dataset', () async {
      final data = await BdoResourceMapLoader.loadBundled();
      final worker = await BdoNodeNetworkWorker.start(data);
      addTearDown(worker.dispose);

      final response = await worker.optimize(
        generation: 1,
        request: BdoNodeNetworkRequest(
          contributionPointBudget: 500,
          desiredResourceNodeCounts: const <String, int>{'Ash Timber': 1},
        ),
      );

      expect(response.result.hasErrors, isFalse);
      expect(response.result.plan, isNotNull);
      expect(
        response.result.plan!.workerNodeIdsByResource.values.single,
        isNotEmpty,
      );
    });

    test('startup failures propagate without returning a worker', () async {
      await expectLater(
        BdoNodeNetworkWorker.start(_startupFailureDataset()),
        throwsA(
          isA<BdoNodeNetworkWorkerException>()
              .having(
                (error) => error.message,
                'message',
                allOf(
                  contains('could not prepare the dataset'),
                  contains('deliberate dataset failure'),
                ),
              )
              .having(
                (error) => error.remoteStackTrace,
                'remoteStackTrace',
                contains('_ThrowingWorkerNode.linkIds'),
              ),
        ),
      );
    });
  });
}

class _ThrowingNodeNetworkRequest extends BdoNodeNetworkRequest {
  _ThrowingNodeNetworkRequest()
    : super(
        contributionPointBudget: 20,
        desiredResourceNodeCounts: const <String, int>{'y': 1},
      );

  @override
  int get contributionPointBudget =>
      throw StateError('deliberate request failure');
}

BdoResourceMapDataset _startupFailureDataset() {
  return BdoResourceMapDataset(
    manifest: _manifest(),
    resources: const <BdoResourceDefinition>[],
    workerNodes: <BdoWorkerNode>[_ThrowingWorkerNode()],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

class _ThrowingWorkerNode extends BdoWorkerNode {
  _ThrowingWorkerNode()
    : super(
        id: 'throwing-node',
        name: 'Throwing Node',
        nodeType: 'Connection',
        region: 'Test',
        location: const BdoWorldPoint(0, 0),
        contributionPoints: 0,
        linkIds: const <String>[],
        outputs: const <BdoNodeOutput>[],
        isResourceNode: false,
      );

  @override
  List<String> get linkIds => throw StateError('deliberate dataset failure');
}

BdoResourceMapDataset _rerouteDataset() {
  return BdoResourceMapDataset(
    manifest: _manifest(),
    resources: <BdoResourceDefinition>[
      _resource('x', 'X Material'),
      _resource('y', 'Y Material'),
    ],
    workerNodes: <BdoWorkerNode>[
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
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}

BdoDatasetManifest _manifest() {
  return BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'network-worker-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'test',
    provenance: const <BdoProvenanceRecord>[],
  );
}

BdoResourceDefinition _resource(String id, String name) {
  return BdoResourceDefinition(
    id: id,
    name: name,
    category: 'Test',
    section: BdoResourceSection.other,
    aliases: const <String>[],
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
  required String parent,
  required Map<String, String> outputs,
}) {
  return BdoWorkerNode(
    id: id,
    name: id,
    nodeType: 'Gathering',
    region: 'Test',
    location: const BdoWorldPoint(0, 0),
    contributionPoints: cp,
    linkIds: <String>[parent],
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
