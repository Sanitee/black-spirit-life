import 'package:bdo_map_core/src/network/worker_capacity_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BdoTownWorkerCapacity', () {
    test('keeps legacy effective capacity unchanged', () {
      const legacy = BdoTownWorkerCapacity(
        availableWorkerCount: 2,
        freeLodgingSlotCount: 4,
      );

      final resolved = legacy.resolveForKnownTownLodging(
        baseWorkerSlotCount: 1,
        activeOwnedLodgingSlotCount: 20,
      );

      expect(identical(resolved, legacy), isTrue);
      expect(resolved.availableWorkerCount, 2);
      expect(resolved.freeLodgingSlotCount, 4);
    });

    test('combines hired workers, mapped lodging, and bonus lodging', () {
      const configured = BdoTownWorkerCapacity(
        availableWorkerCount: 0,
        freeLodgingSlotCount: 0,
        hiredWorkerCount: 5,
        bonusLodgingSlotCount: 8,
      );

      final resolved = configured.resolveForKnownTownLodging(
        baseWorkerSlotCount: 1,
        activeOwnedLodgingSlotCount: 3,
      );

      expect(resolved.availableWorkerCount, 5);
      expect(resolved.freeLodgingSlotCount, 7);
      expect(resolved.availableWorkerCount + resolved.freeLodgingSlotCount, 12);
      expect(resolved.bonusLodgingSlotCount, 8);
    });

    test('does not discard hired workers above the known slot count', () {
      const configured = BdoTownWorkerCapacity(
        availableWorkerCount: 0,
        freeLodgingSlotCount: 0,
        hiredWorkerCount: 7,
        bonusLodgingSlotCount: 0,
      );

      final resolved = configured.resolveForKnownTownLodging(
        baseWorkerSlotCount: 1,
        activeOwnedLodgingSlotCount: 2,
      );

      expect(resolved.availableWorkerCount, 7);
      expect(resolved.freeLodgingSlotCount, 0);
    });

    test('source breakdown overrides a stale legacy total', () {
      const configured = BdoTownWorkerCapacity(
        availableWorkerCount: 0,
        freeLodgingSlotCount: 0,
        hiredWorkerCount: 4,
        bonusLodgingSlotCount: 99,
        pearlLodgingPurchasedCount: 3,
        loyaltyLodgingPurchasedCount: 1,
        otherBonusLodgingSlotCount: 4,
      );

      final resolved = configured.resolveForKnownTownLodging(
        baseWorkerSlotCount: 1,
        activeOwnedLodgingSlotCount: 2,
      );

      expect(configured.hasBonusLodgingBreakdown, isTrue);
      expect(configured.effectiveBonusLodgingSlotCount, 8);
      expect(resolved.bonusLodgingSlotCount, 8);
      expect(resolved.availableWorkerCount, 4);
      expect(resolved.freeLodgingSlotCount, 7);
      expect(resolved.pearlLodgingPurchasedCount, 3);
      expect(resolved.loyaltyLodgingPurchasedCount, 1);
      expect(resolved.otherBonusLodgingSlotCount, 4);
    });
  });

  group('BdoWorkerCapacityAssessmentService', () {
    const service = BdoWorkerCapacityAssessmentService();

    test('creates one worker demand per unique selected production node', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['20', '10', '10'],
          capacities: const <String, BdoTownWorkerCapacity>{
            '100': BdoTownWorkerCapacity(
              availableWorkerCount: 2,
              freeLodgingSlotCount: 0,
            ),
          },
          candidates: const <String, Iterable<String>>{
            '10': <String>['100'],
            '20': <String>['100'],
          },
        ),
      );

      expect(result.hasErrors, isFalse);
      final assessment = result.assessment!;
      expect(assessment.productionNodeIds, <String>['10', '20']);
      expect(assessment.workerDemandCount, 2);
      expect(assessment.assignedWorkerCount, 2);
      expect(
        assessment.assignments
            .map(
              (assignment) => (
                assignment.productionNodeId,
                assignment.townNodeId,
                assignment.source,
              ),
            )
            .toList(),
        <(String, String, BdoWorkerCapacityAssignmentSource)>[
          ('10', '100', BdoWorkerCapacityAssignmentSource.availableWorker),
          ('20', '100', BdoWorkerCapacityAssignmentSource.availableWorker),
        ],
      );
      expect(assessment.minimumAdditionalLodgingSlotsToCoverAll, 0);
    });

    test('finds maximum capacity assignment instead of a greedy dead end', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['20', '10'],
          capacities: const <String, BdoTownWorkerCapacity>{
            '100': BdoTownWorkerCapacity(
              availableWorkerCount: 1,
              freeLodgingSlotCount: 0,
            ),
            '200': BdoTownWorkerCapacity(
              availableWorkerCount: 1,
              freeLodgingSlotCount: 0,
            ),
          },
          candidates: const <String, Iterable<String>>{
            '10': <String>['100', '200'],
            '20': <String>['100'],
          },
        ),
      );

      expect(result.assessment!.assignedWorkerCount, 2);
      expect(
        result.assessment!.assignments
            .map(
              (assignment) =>
                  '${assignment.productionNodeId}:${assignment.townNodeId}',
            )
            .toList(),
        <String>['10:200', '20:100'],
      );
    });

    test(
      'maximizes existing-worker reuse before consuming vacant lodging slots',
      () {
        final result = service.assess(
          _request(
            productionNodeIds: const <String>['10'],
            capacities: const <String, BdoTownWorkerCapacity>{
              '100': BdoTownWorkerCapacity(
                availableWorkerCount: 0,
                freeLodgingSlotCount: 1,
              ),
              '200': BdoTownWorkerCapacity(
                availableWorkerCount: 1,
                freeLodgingSlotCount: 0,
              ),
            },
            candidates: const <String, Iterable<String>>{
              '10': <String>['100', '200'],
            },
          ),
        );

        final assessment = result.assessment!;
        expect(assessment.assignedWorkerCount, 1);
        expect(assessment.availableWorkersUsed, 1);
        expect(assessment.freeLodgingSlotsUsed, 0);
        expect(assessment.assignments.single.townNodeId, '200');
        expect(
          assessment.assignments.single.source,
          BdoWorkerCapacityAssignmentSource.availableWorker,
        );
      },
    );

    test('uses owned vacant lodging only after available workers', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['1', '2', '3'],
          capacities: const <String, BdoTownWorkerCapacity>{
            'town': BdoTownWorkerCapacity(
              availableWorkerCount: 2,
              freeLodgingSlotCount: 1,
            ),
          },
          candidates: const <String, Iterable<String>>{
            '1': <String>['town'],
            '2': <String>['town'],
            '3': <String>['town'],
          },
        ),
      );

      final assessment = result.assessment!;
      expect(assessment.availableWorkersUsed, 2);
      expect(assessment.freeLodgingSlotsUsed, 1);
      final usage = assessment.townUsages.single;
      expect(usage.assignedWorkerCount, 3);
      expect(usage.availableWorkersUsed, 2);
      expect(usage.freeLodgingSlotsUsed, 1);
      expect(usage.remainingAvailableWorkerCount, 0);
      expect(usage.remainingFreeLodgingSlotCount, 0);
      expect(usage.assignedProductionNodeIds, <String>['1', '2', '3']);
    });

    test('reports the exact additional slots for reachable unmet demand', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['1', '2', '3'],
          capacities: const <String, BdoTownWorkerCapacity>{
            'town': BdoTownWorkerCapacity(
              availableWorkerCount: 1,
              freeLodgingSlotCount: 0,
            ),
          },
          candidates: const <String, Iterable<String>>{
            '1': <String>['town'],
            '2': <String>['town'],
            '3': <String>['town'],
          },
        ),
      );

      final assessment = result.assessment!;
      expect(assessment.assignedWorkerCount, 1);
      expect(assessment.unmetWorkerCount, 2);
      expect(
        assessment.unmetDemands
            .map((demand) => demand.productionNodeId)
            .toList(),
        <String>['2', '3'],
      );
      expect(assessment.minimumAdditionalLodgingSlotsForReachableDemand, 2);
      expect(assessment.minimumAdditionalLodgingSlotsToCoverAll, 2);
      expect(assessment.canBeCoveredByAddingLodgingSlots, isTrue);
    });

    test('separates unreachable jobs from lodging-solvable shortages', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['1', '2'],
          capacities: const <String, BdoTownWorkerCapacity>{
            'town': BdoTownWorkerCapacity(
              availableWorkerCount: 0,
              freeLodgingSlotCount: 0,
            ),
          },
          candidates: const <String, Iterable<String>>{
            '1': <String>['town'],
          },
        ),
      );

      final assessment = result.assessment!;
      expect(assessment.unmetWorkerCount, 2);
      expect(assessment.minimumAdditionalLodgingSlotsForReachableDemand, 1);
      expect(assessment.minimumAdditionalLodgingSlotsToCoverAll, isNull);
      expect(assessment.unreachableProductionNodeIds, <String>['2']);
      expect(assessment.canBeCoveredByAddingLodgingSlots, isFalse);
      expect(assessment.unmetDemands.first.candidateTownNodeIds, <String>[
        'town',
      ]);
      expect(assessment.unmetDemands.last.candidateTownNodeIds, isEmpty);
    });

    test('returns every entered town in stable usage order', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['10'],
          capacities: const <String, BdoTownWorkerCapacity>{
            '20': BdoTownWorkerCapacity(
              availableWorkerCount: 0,
              freeLodgingSlotCount: 0,
            ),
            '3': BdoTownWorkerCapacity(
              availableWorkerCount: 1,
              freeLodgingSlotCount: 2,
            ),
          },
          candidates: const <String, Iterable<String>>{
            '10': <String>['3'],
          },
        ),
      );

      final usages = result.assessment!.townUsages;
      expect(usages.map((usage) => usage.townNodeId), <String>['3', '20']);
      expect(usages.first.remainingAvailableWorkerCount, 0);
      expect(usages.first.remainingFreeLodgingSlotCount, 2);
      expect(usages.last.assignedProductionNodeIds, isEmpty);
    });

    test('is deterministic regardless of caller collection order', () {
      BdoWorkerCapacityAssessmentResult run(bool reverse) {
        return service.assess(
          _request(
            productionNodeIds: reverse
                ? const <String>['30', '20', '10']
                : const <String>['10', '20', '30'],
            capacities: reverse
                ? const <String, BdoTownWorkerCapacity>{
                    '200': BdoTownWorkerCapacity(
                      availableWorkerCount: 1,
                      freeLodgingSlotCount: 1,
                    ),
                    '100': BdoTownWorkerCapacity(
                      availableWorkerCount: 1,
                      freeLodgingSlotCount: 0,
                    ),
                  }
                : const <String, BdoTownWorkerCapacity>{
                    '100': BdoTownWorkerCapacity(
                      availableWorkerCount: 1,
                      freeLodgingSlotCount: 0,
                    ),
                    '200': BdoTownWorkerCapacity(
                      availableWorkerCount: 1,
                      freeLodgingSlotCount: 1,
                    ),
                  },
            candidates: reverse
                ? const <String, Iterable<String>>{
                    '30': <String>['200', '100'],
                    '20': <String>['200', '100'],
                    '10': <String>['200', '100'],
                  }
                : const <String, Iterable<String>>{
                    '10': <String>['100', '200'],
                    '20': <String>['100', '200'],
                    '30': <String>['100', '200'],
                  },
          ),
        );
      }

      List<(String, String, BdoWorkerCapacityAssignmentSource)> snapshot(
        BdoWorkerCapacityAssessmentResult result,
      ) {
        return result.assessment!.assignments
            .map(
              (assignment) => (
                assignment.productionNodeId,
                assignment.townNodeId,
                assignment.source,
              ),
            )
            .toList();
      }

      expect(snapshot(run(true)), snapshot(run(false)));
    });

    test('uses a total deterministic order for mixed numeric and text IDs', () {
      BdoWorkerCapacityAssessmentResult run(bool reverse) {
        return service.assess(
          _request(
            productionNodeIds: reverse
                ? const <String>['15x', '10', '2']
                : const <String>['2', '10', '15x'],
            capacities: reverse
                ? const <String, BdoTownWorkerCapacity>{
                    'town-b': BdoTownWorkerCapacity(
                      availableWorkerCount: 2,
                      freeLodgingSlotCount: 0,
                    ),
                    '20': BdoTownWorkerCapacity(
                      availableWorkerCount: 1,
                      freeLodgingSlotCount: 0,
                    ),
                  }
                : const <String, BdoTownWorkerCapacity>{
                    '20': BdoTownWorkerCapacity(
                      availableWorkerCount: 1,
                      freeLodgingSlotCount: 0,
                    ),
                    'town-b': BdoTownWorkerCapacity(
                      availableWorkerCount: 2,
                      freeLodgingSlotCount: 0,
                    ),
                  },
            candidates: reverse
                ? const <String, Iterable<String>>{
                    '15x': <String>['town-b', '20'],
                    '10': <String>['town-b', '20'],
                    '2': <String>['town-b', '20'],
                  }
                : const <String, Iterable<String>>{
                    '2': <String>['20', 'town-b'],
                    '10': <String>['20', 'town-b'],
                    '15x': <String>['20', 'town-b'],
                  },
          ),
        );
      }

      List<(String, String)> snapshot(
        BdoWorkerCapacityAssessmentResult result,
      ) {
        return result.assessment!.assignments
            .map(
              (assignment) =>
                  (assignment.productionNodeId, assignment.townNodeId),
            )
            .toList();
      }

      final forward = run(false);
      final reverse = run(true);
      expect(forward.assessment!.productionNodeIds, <String>['2', '10', '15x']);
      expect(
        forward.assessment!.townUsages.map((usage) => usage.townNodeId),
        <String>['20', 'town-b'],
      );
      expect(snapshot(reverse), snapshot(forward));
    });

    test('defensively copies caller-owned request collections', () {
      final productionNodeIds = <String>['1'];
      final capacities = <String, BdoTownWorkerCapacity>{
        'town': const BdoTownWorkerCapacity(
          availableWorkerCount: 1,
          freeLodgingSlotCount: 0,
        ),
      };
      final candidateTowns = <String>['town'];
      final candidates = <String, Iterable<String>>{'1': candidateTowns};
      final request = BdoWorkerCapacityAssessmentRequest(
        selectedProductionNodeIds: productionNodeIds,
        townCapacitiesByNodeId: capacities,
        candidateTownNodeIdsByProductionNodeId: candidates,
      );

      productionNodeIds.add('2');
      capacities.clear();
      candidateTowns.clear();
      candidates.clear();

      final result = service.assess(request);
      expect(result.hasErrors, isFalse);
      expect(result.assessment!.productionNodeIds, <String>['1']);
      expect(result.assessment!.assignedWorkerCount, 1);
    });

    test('returns a valid empty assessment for an empty network', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>[],
          capacities: const <String, BdoTownWorkerCapacity>{},
          candidates: const <String, Iterable<String>>{},
        ),
      );

      expect(result.hasErrors, isFalse);
      expect(result.assessment!.workerDemandCount, 0);
      expect(result.assessment!.isCoveredByCurrentCapacity, isTrue);
      expect(result.assessment!.minimumAdditionalLodgingSlotsToCoverAll, 0);
    });

    test('rejects negative capacity and blank IDs', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>[' ', 'node'],
          capacities: const <String, BdoTownWorkerCapacity>{
            '': BdoTownWorkerCapacity(
              availableWorkerCount: -1,
              freeLodgingSlotCount: -2,
            ),
            'town': BdoTownWorkerCapacity(
              availableWorkerCount: 0,
              freeLodgingSlotCount: 0,
            ),
          },
          candidates: const <String, Iterable<String>>{
            'node': <String>[''],
          },
        ),
      );

      expect(result.hasErrors, isTrue);
      expect(result.assessment, isNull);
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        containsAll(<BdoWorkerCapacityDiagnosticCode>[
          BdoWorkerCapacityDiagnosticCode.blankProductionNodeId,
          BdoWorkerCapacityDiagnosticCode.blankTownNodeId,
          BdoWorkerCapacityDiagnosticCode.invalidAvailableWorkerCount,
          BdoWorkerCapacityDiagnosticCode.invalidFreeLodgingSlotCount,
          BdoWorkerCapacityDiagnosticCode.blankCandidateTownNodeId,
        ]),
      );
    });

    test('requires an explicit capacity entry for every candidate town', () {
      final result = service.assess(
        _request(
          productionNodeIds: const <String>['node'],
          capacities: const <String, BdoTownWorkerCapacity>{},
          candidates: const <String, Iterable<String>>{
            'node': <String>['town'],
          },
        ),
      );

      expect(result.hasErrors, isTrue);
      expect(result.assessment, isNull);
      expect(result.diagnostics, hasLength(1));
      expect(
        result.diagnostics.single.code,
        BdoWorkerCapacityDiagnosticCode.missingTownCapacity,
      );
      expect(result.diagnostics.single.productionNodeId, 'node');
      expect(result.diagnostics.single.townNodeId, 'town');
    });
  });
}

BdoWorkerCapacityAssessmentRequest _request({
  required Iterable<String> productionNodeIds,
  required Map<String, BdoTownWorkerCapacity> capacities,
  required Map<String, Iterable<String>> candidates,
}) {
  return BdoWorkerCapacityAssessmentRequest(
    selectedProductionNodeIds: productionNodeIds,
    townCapacitiesByNodeId: capacities,
    candidateTownNodeIdsByProductionNodeId: candidates,
  );
}
