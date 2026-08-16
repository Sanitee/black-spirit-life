import 'dart:math' as math;

import '../economics/worker_economics_data.dart';
import '../lodging/lodging_data.dart';
import '../lodging/lodging_network_planner.dart';
import '../lodging/lodging_optimizer.dart';
import '../model/resource_map_data.dart';
import 'raw_sale_network_planner.dart';
import 'worker_capacity_assessment.dart';

typedef BdoRawSaleMarginalValueSignalProviderFactory =
    BdoRawSaleNetworkMarginalValueSignalProvider Function();

/// User-owned worker and housing inputs for a lodging-aware raw-sale plan.
final class BdoRawSaleLodgingBudgetRequest {
  BdoRawSaleLodgingBudgetRequest({
    required this.totalContributionPointBudget,
    required Set<String> currentNodeIds,
    required Map<String, double> currentSaleValueSignalsByProductionNodeId,
    required Map<String, BdoTownWorkerCapacity> townWorkerCapacitiesByNodeId,
    Set<String>? allowedRootNodeIds,
    Set<String> currentOwnedHouseIds = const <String>{},
    this.marginalValueSignalProviderFactory,
    this.maxRepairIterations = 16,
  }) : currentNodeIds = Set<String>.unmodifiable(currentNodeIds),
       currentSaleValueSignalsByProductionNodeId =
           Map<String, double>.unmodifiable(
             currentSaleValueSignalsByProductionNodeId,
           ),
       townWorkerCapacitiesByNodeId =
           Map<String, BdoTownWorkerCapacity>.unmodifiable(
             townWorkerCapacitiesByNodeId,
           ),
       allowedRootNodeIds = allowedRootNodeIds == null
           ? null
           : Set<String>.unmodifiable(allowedRootNodeIds),
       currentOwnedHouseIds = Set<String>.unmodifiable(currentOwnedHouseIds);

  final int totalContributionPointBudget;
  final Set<String> currentNodeIds;
  final Set<String>? allowedRootNodeIds;
  final Map<String, double> currentSaleValueSignalsByProductionNodeId;

  /// Explicit current worker/free-slot inputs.
  ///
  /// An empty map means the user has not configured staffing yet. In that
  /// state this service preserves the normal node-only recommendation and does
  /// not assume that every town has zero workers. To request an authoritative
  /// zero-capacity plan, provide zero entries for the relevant worker towns.
  final Map<String, BdoTownWorkerCapacity> townWorkerCapacitiesByNodeId;
  final Set<String> currentOwnedHouseIds;
  final BdoRawSaleMarginalValueSignalProviderFactory?
  marginalValueSignalProviderFactory;
  final int maxRepairIterations;
}

/// One network whose worker lodging has been reconciled with the same CP cap.
final class BdoRawSaleLodgingBudgetResult {
  const BdoRawSaleLodgingBudgetResult({
    required this.networkPlan,
    required this.workerCapacity,
    required this.lodgingPlanning,
    required this.lodgingContributionPoints,
    required this.combinedContributionPoints,
    required this.repairIterations,
    required this.lodgingBudgetApplied,
  });

  final BdoRawSaleNetworkPlanResult networkPlan;
  final BdoWorkerCapacityAssessmentResult? workerCapacity;
  final BdoLodgingNetworkPlanningResult? lodgingPlanning;
  final int lodgingContributionPoints;
  final int combinedContributionPoints;
  final int repairIterations;
  final bool lodgingBudgetApplied;

  bool get isWithinBudget =>
      combinedContributionPoints <= networkPlan.totalContributionPointBudget;
}

/// Reconciles a greedy node portfolio with its actual worker-lodging CP.
///
/// The raw-sale planner remains a deterministic heuristic. This service adds a
/// deterministic repair/refill loop:
///
/// 1. build the best current node portfolio;
/// 2. assign entered workers and free lodging;
/// 3. solve the exact/bounded cross-town lodging graph;
/// 4. reserve that lodging CP inside the same maximum CP and rebuild;
/// 5. if housing capacity is insufficient, trim the weakest tail and refill
///    toward the highest feasible worker count.
///
/// Every raw-plan pass remains cooperative and cancellable. A fresh marginal
/// provider is requested for each pass so cached portfolio state cannot leak
/// between different repaired selections.
final class BdoRawSaleLodgingBudgetPlanner {
  const BdoRawSaleLodgingBudgetPlanner();

  Future<BdoRawSaleLodgingBudgetResult> planAsync({
    required BdoResourceMapDataset data,
    required BdoWorkerEconomicsDataset economics,
    required LodgingDataset? lodgingDataset,
    required BdoRawSaleLodgingBudgetRequest request,
    BdoRawSaleNetworkCancellationPredicate? shouldCancel,
  }) async {
    if (request.maxRepairIterations <= 0) {
      throw ArgumentError.value(
        request.maxRepairIterations,
        'maxRepairIterations',
        'must be greater than zero',
      );
    }

    void throwIfCancelled() {
      if (shouldCancel?.call() ?? false) {
        throw const BdoRawSaleNetworkPlanningCancelled();
      }
    }

    final excludedProductionNodeIds = <String>{};

    Future<BdoRawSaleNetworkPlanResult> buildNetwork({
      required int lodgingReserve,
      required int? maximumProductionNodeCount,
    }) {
      return const BdoRawSaleNetworkPlanner().planAsync(
        data: data,
        request: BdoRawSaleNetworkPlanRequest(
          totalContributionPointBudget: request.totalContributionPointBudget,
          reservedContributionPoints: lodgingReserve,
          maximumProductionNodeCount: maximumProductionNodeCount,
          currentNodeIds: request.currentNodeIds,
          allowedRootNodeIds: request.allowedRootNodeIds,
          currentSaleValueSignalsByProductionNodeId: <String, double>{
            for (final entry
                in request.currentSaleValueSignalsByProductionNodeId.entries)
              if (!excludedProductionNodeIds.contains(entry.key))
                entry.key: entry.value,
          },
          marginalValueSignalProvider: request
              .marginalValueSignalProviderFactory
              ?.call(),
        ),
        shouldCancel: shouldCancel,
      );
    }

    final canPlanLodging =
        lodgingDataset != null &&
        request.townWorkerCapacitiesByNodeId.isNotEmpty;
    if (!canPlanLodging) {
      final plan = await buildNetwork(
        lodgingReserve: 0,
        maximumProductionNodeCount: null,
      );
      throwIfCancelled();
      final capacity = request.townWorkerCapacitiesByNodeId.isEmpty
          ? null
          : _assessWorkerCapacity(
              plan: plan,
              economics: economics,
              configuredCapacity: request.townWorkerCapacitiesByNodeId,
            );
      return BdoRawSaleLodgingBudgetResult(
        networkPlan: plan,
        workerCapacity: capacity,
        lodgingPlanning: null,
        lodgingContributionPoints: 0,
        combinedContributionPoints: plan.totalContributionPoints,
        repairIterations: 1,
        lodgingBudgetApplied: false,
      );
    }

    var lodgingReserve = 0;
    int? maximumProductionNodeCount;
    int? knownInfeasibleWorkerCount;
    BdoRawSaleLodgingBudgetResult? bestFeasible;
    BdoRawSaleLodgingBudgetResult? latest;
    final visitedStates = <String>{};
    Map<String, BdoTownWorkerCapacity>? maximumTownCapacities;

    for (
      var iteration = 1;
      iteration <= request.maxRepairIterations;
      iteration += 1
    ) {
      throwIfCancelled();
      final excludedKey = (excludedProductionNodeIds.toList()..sort()).join(
        ',',
      );
      final stateKey =
          '$lodgingReserve|${maximumProductionNodeCount ?? -1}|$excludedKey';
      if (!visitedStates.add(stateKey)) {
        break;
      }

      final plan = await buildNetwork(
        lodgingReserve: lodgingReserve,
        maximumProductionNodeCount: maximumProductionNodeCount,
      );
      throwIfCancelled();
      final candidateTowns = _workerTownCandidatesForPlan(
        plan: plan,
        economics: economics,
      );
      final staffing = _planJointStaffing(
        plan: plan,
        lodgingDataset: lodgingDataset,
        configuredCapacity: request.townWorkerCapacitiesByNodeId,
        candidateTowns: candidateTowns,
        currentOwnedHouseIds: request.currentOwnedHouseIds,
      );
      final capacity = staffing.capacity;
      final lodging = staffing.lodging;
      final lodgingPlan = lodging.plan;
      final lodgingCp = lodgingPlan?.totalIncrementalContributionPoints ?? 0;
      final combinedCp = plan.totalContributionPoints + lodgingCp;
      latest = BdoRawSaleLodgingBudgetResult(
        networkPlan: plan,
        workerCapacity: capacity,
        lodgingPlanning: lodging,
        lodgingContributionPoints: lodgingCp,
        combinedContributionPoints: combinedCp,
        repairIterations: iteration,
        lodgingBudgetApplied: true,
      );

      if (lodgingPlan == null) {
        final selectedCount = plan.selections.length;
        if (selectedCount == 0) {
          break;
        }
        knownInfeasibleWorkerCount = knownInfeasibleWorkerCount == null
            ? selectedCount
            : math.min(knownInfeasibleWorkerCount, selectedCount);
        maximumTownCapacities ??= _maximumTownWorkerCapacities(
          lodgingDataset: lodgingDataset,
          configuredCapacity: request.townWorkerCapacitiesByNodeId,
          currentOwnedHouseIds: request.currentOwnedHouseIds,
        );
        final rejectedProductionNodeIds =
            _prioritizedUnstaffableProductionNodeIds(
              plan: plan,
              candidateTowns: candidateTowns,
              maximumTownCapacities: maximumTownCapacities,
            );
        if (rejectedProductionNodeIds.isNotEmpty) {
          excludedProductionNodeIds.addAll(rejectedProductionNodeIds);
          final capacityUpperBound = maximumTownCapacities.values.fold<int>(
            0,
            (sum, capacity) =>
                sum +
                capacity.availableWorkerCount +
                capacity.freeLodgingSlotCount,
          );
          maximumProductionNodeCount = math.min(
            selectedCount,
            capacityUpperBound,
          );
          await Future<void>.delayed(Duration.zero);
          continue;
        }

        final reducedByQuarter =
            selectedCount - math.max<int>(1, (selectedCount / 4).ceil());
        maximumProductionNodeCount = math.max(
          0,
          math.min(selectedCount - 1, reducedByQuarter),
        );
        await Future<void>.delayed(Duration.zero);
        continue;
      }

      if (combinedCp <= request.totalContributionPointBudget) {
        if (_isBetterFeasible(latest, bestFeasible)) {
          bestFeasible = latest;
        }

        final infeasibleCount = knownInfeasibleWorkerCount;
        if (infeasibleCount != null &&
            plan.selections.length + 1 < infeasibleCount) {
          maximumProductionNodeCount =
              (plan.selections.length + infeasibleCount) ~/ 2;
          lodgingReserve = lodgingCp;
          continue;
        }

        if (lodgingReserve > lodgingCp) {
          lodgingReserve = lodgingCp;
          continue;
        }
        return bestFeasible!;
      }

      if (lodgingCp > lodgingReserve) {
        lodgingReserve = lodgingCp.clamp(
          0,
          request.totalContributionPointBudget,
        );
        continue;
      }

      final selectedCount = plan.selections.length;
      if (selectedCount == 0) {
        break;
      }
      knownInfeasibleWorkerCount = knownInfeasibleWorkerCount == null
          ? selectedCount
          : math.min(knownInfeasibleWorkerCount, selectedCount);
      maximumProductionNodeCount = selectedCount - 1;
    }

    if (bestFeasible != null) {
      return bestFeasible;
    }

    // A saved baseline can itself exceed the user's budget and is never
    // disconnected automatically. Otherwise a zero-selection final pass
    // guarantees that the recommendation adds no unaffordable workers.
    final emptyPlan = await buildNetwork(
      lodgingReserve: 0,
      maximumProductionNodeCount: 0,
    );
    throwIfCancelled();
    final emptyCandidateTowns = _workerTownCandidatesForPlan(
      plan: emptyPlan,
      economics: economics,
    );
    final emptyStaffing = _planJointStaffing(
      plan: emptyPlan,
      lodgingDataset: lodgingDataset,
      configuredCapacity: request.townWorkerCapacitiesByNodeId,
      candidateTowns: emptyCandidateTowns,
      currentOwnedHouseIds: request.currentOwnedHouseIds,
    );
    return BdoRawSaleLodgingBudgetResult(
      networkPlan: emptyPlan,
      workerCapacity: emptyStaffing.capacity,
      lodgingPlanning: emptyStaffing.lodging,
      lodgingContributionPoints: 0,
      combinedContributionPoints: emptyPlan.totalContributionPoints,
      repairIterations:
          (latest?.repairIterations ?? request.maxRepairIterations) + 1,
      lodgingBudgetApplied: true,
    );
  }
}

BdoWorkerCapacityAssessmentResult _assessWorkerCapacity({
  required BdoRawSaleNetworkPlanResult plan,
  required BdoWorkerEconomicsDataset economics,
  required Map<String, BdoTownWorkerCapacity> configuredCapacity,
  Map<String, Set<String>>? candidateTowns,
}) {
  final towns =
      candidateTowns ??
      _workerTownCandidatesForPlan(plan: plan, economics: economics);
  return const BdoWorkerCapacityAssessmentService().assess(
    BdoWorkerCapacityAssessmentRequest(
      selectedProductionNodeIds: plan.selectedProductionNodeIds,
      townCapacitiesByNodeId: configuredCapacity,
      candidateTownNodeIdsByProductionNodeId: <String, Iterable<String>>{
        for (final productionNodeId in plan.selectedProductionNodeIds)
          productionNodeId: (towns[productionNodeId] ?? const <String>{}).where(
            configuredCapacity.containsKey,
          ),
      },
    ),
  );
}

({
  BdoWorkerCapacityAssessmentResult capacity,
  BdoLodgingNetworkPlanningResult lodging,
})
_planJointStaffing({
  required BdoRawSaleNetworkPlanResult plan,
  required LodgingDataset lodgingDataset,
  required Map<String, BdoTownWorkerCapacity> configuredCapacity,
  required Map<String, Set<String>> candidateTowns,
  required Set<String> currentOwnedHouseIds,
}) {
  final existingCapacityByTownNodeId = <String, int>{
    for (final entry in configuredCapacity.entries)
      if (lodgingDataset.townsByNodeId[entry.key]?.isWorkerTown == true)
        entry.key:
            entry.value.availableWorkerCount + entry.value.freeLodgingSlotCount,
  };
  final combined = const BdoLodgingNetworkPlanner().plan(
    dataset: lodgingDataset,
    unmetDemands: <BdoUnmetWorkerDemand>[
      for (final productionNodeId in plan.selectedProductionNodeIds)
        BdoUnmetWorkerDemand(
          productionNodeId: productionNodeId,
          candidateTownNodeIds:
              (candidateTowns[productionNodeId] ?? const <String>{}).where(
                (townNodeId) =>
                    lodgingDataset.townsByNodeId[townNodeId]?.isWorkerTown ==
                    true,
              ),
        ),
    ],
    currentOwnedHouseIds: currentOwnedHouseIds
        .where(lodgingDataset.housesById.containsKey)
        .toSet(),
    existingWorkerCapacityByTownNodeId: existingCapacityByTownNodeId,
  );
  final combinedPlan = combined.plan;
  if (combinedPlan == null) {
    final capacity = const BdoWorkerCapacityAssessmentService().assess(
      BdoWorkerCapacityAssessmentRequest(
        selectedProductionNodeIds: plan.selectedProductionNodeIds,
        townCapacitiesByNodeId: configuredCapacity,
        candidateTownNodeIdsByProductionNodeId: <String, Iterable<String>>{
          for (final productionNodeId in plan.selectedProductionNodeIds)
            productionNodeId:
                (candidateTowns[productionNodeId] ?? const <String>{}).where(
                  configuredCapacity.containsKey,
                ),
        },
      ),
    );
    return (capacity: capacity, lodging: combined);
  }

  final selectionOrder = <String, int>{
    for (var index = 0; index < plan.selections.length; index += 1)
      plan.selections[index].productionNodeId: index,
  };
  final productionNodeIdsByTown = <String, List<String>>{};
  for (final entry in combinedPlan.townNodeIdByProductionNodeId.entries) {
    (productionNodeIdsByTown[entry.value] ??= <String>[]).add(entry.key);
  }
  for (final productionNodeIds in productionNodeIdsByTown.values) {
    productionNodeIds.sort(
      (left, right) => (selectionOrder[left] ?? 1 << 30).compareTo(
        selectionOrder[right] ?? 1 << 30,
      ),
    );
  }

  final currentAssignments = <BdoProductionWorkerAssignment>[];
  final townUsages = <BdoTownWorkerCapacityUsage>[];
  final currentAssignedProductionNodeIds = <String>{};
  final configuredEntries = configuredCapacity.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in configuredEntries) {
    final productionNodeIds =
        productionNodeIdsByTown[entry.key] ?? const <String>[];
    final availableUsed = math.min(
      entry.value.availableWorkerCount,
      productionNodeIds.length,
    );
    final freeUsed = math.min(
      entry.value.freeLodgingSlotCount,
      productionNodeIds.length - availableUsed,
    );
    for (var index = 0; index < availableUsed + freeUsed; index += 1) {
      final productionNodeId = productionNodeIds[index];
      currentAssignedProductionNodeIds.add(productionNodeId);
      currentAssignments.add(
        BdoProductionWorkerAssignment(
          productionNodeId: productionNodeId,
          townNodeId: entry.key,
          source: index < availableUsed
              ? BdoWorkerCapacityAssignmentSource.availableWorker
              : BdoWorkerCapacityAssignmentSource.freeLodgingSlot,
        ),
      );
    }
    townUsages.add(
      BdoTownWorkerCapacityUsage(
        townNodeId: entry.key,
        availableWorkerCount: entry.value.availableWorkerCount,
        freeLodgingSlotCount: entry.value.freeLodgingSlotCount,
        availableWorkersUsed: availableUsed,
        freeLodgingSlotsUsed: freeUsed,
        assignedProductionNodeIds: productionNodeIds.take(
          availableUsed + freeUsed,
        ),
      ),
    );
  }
  final lodgingAssignments = <String, String>{
    for (final entry in combinedPlan.townNodeIdByProductionNodeId.entries)
      if (!currentAssignedProductionNodeIds.contains(entry.key))
        entry.key: entry.value,
  };
  final lodgingTownNodeIds = lodgingAssignments.values.toSet();
  final capacity = BdoWorkerCapacityAssessmentResult(
    assessment: BdoWorkerCapacityAssessment(
      productionNodeIds: plan.selectedProductionNodeIds,
      assignments: currentAssignments,
      townUsages: townUsages,
      unmetDemands: <BdoUnmetWorkerDemand>[
        for (final entry in lodgingAssignments.entries)
          BdoUnmetWorkerDemand(
            productionNodeId: entry.key,
            candidateTownNodeIds: candidateTowns[entry.key] ?? const <String>{},
          ),
      ],
    ),
    diagnostics: const <BdoWorkerCapacityDiagnostic>[],
  );
  final lodging = BdoLodgingNetworkPlanningResult(
    plan: BdoLodgingNetworkPlan(
      townNodeIdByProductionNodeId: lodgingAssignments,
      townPlans: combinedPlan.townPlans.where(
        (townPlan) => lodgingTownNodeIds.contains(townPlan.townNodeId),
      ),
      quality: combinedPlan.quality,
      searchStateCount: combinedPlan.searchStateCount,
    ),
    diagnostics: combined.diagnostics,
  );
  return (capacity: capacity, lodging: lodging);
}

Map<String, Set<String>> _workerTownCandidatesForPlan({
  required BdoRawSaleNetworkPlanResult plan,
  required BdoWorkerEconomicsDataset economics,
}) {
  final adjacency = <String, Set<String>>{};
  for (final edge in plan.routeEdges) {
    (adjacency[edge.firstNodeId] ??= <String>{}).add(edge.secondNodeId);
    (adjacency[edge.secondNodeId] ??= <String>{}).add(edge.firstNodeId);
  }
  final result = <String, Set<String>>{};
  for (final productionNodeId in plan.selectedProductionNodeIds) {
    final reached = <String>{productionNodeId};
    final queue = <String>[productionNodeId];
    for (var index = 0; index < queue.length; index += 1) {
      for (final neighbor in adjacency[queue[index]] ?? const <String>{}) {
        if (reached.add(neighbor)) {
          queue.add(neighbor);
        }
      }
    }
    result[productionNodeId] = economics.eligibleWorkerTownNodeIds(
      productionNodeId: productionNodeId,
      connectedNodeIds: reached,
    );
  }
  return result;
}

Map<String, BdoTownWorkerCapacity> _maximumTownWorkerCapacities({
  required LodgingDataset lodgingDataset,
  required Map<String, BdoTownWorkerCapacity> configuredCapacity,
  required Set<String> currentOwnedHouseIds,
}) {
  final result = <String, BdoTownWorkerCapacity>{
    for (final entry in configuredCapacity.entries)
      entry.key: BdoTownWorkerCapacity(
        availableWorkerCount:
            entry.value.availableWorkerCount + entry.value.freeLodgingSlotCount,
        freeLodgingSlotCount: 0,
      ),
  };
  for (final town in lodgingDataset.towns.where((town) => town.isWorkerTown)) {
    final ownedClosure = _ownedHouseClosureForTown(town, currentOwnedHouseIds);
    final maximum = LodgingOptimizer.solve(
      town: town,
      requiredCapacity: 1 << 30,
      existingCapacity: 0,
      currentOwnedHouseIds: ownedClosure,
    );
    final current = result[town.townNodeId];
    result[town.townNodeId] = BdoTownWorkerCapacity(
      availableWorkerCount:
          (current?.availableWorkerCount ?? 0) + maximum.addedCapacity,
      freeLodgingSlotCount: 0,
    );
  }
  return result;
}

/// Finds lower-priority selections that cannot be staffed even if every
/// remaining lodging house is available.
///
/// Each new selection may reroute an earlier selection to another compatible
/// town, but an earlier selection is never dropped to retain a later one.
Set<String> _prioritizedUnstaffableProductionNodeIds({
  required BdoRawSaleNetworkPlanResult plan,
  required Map<String, Set<String>> candidateTowns,
  required Map<String, BdoTownWorkerCapacity> maximumTownCapacities,
}) {
  if (plan.selections.isEmpty) {
    return const <String>{};
  }

  final slotTownIds = <String>[];
  final townEntries = maximumTownCapacities.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in townEntries) {
    final capacity = math.min(
      plan.selections.length,
      entry.value.availableWorkerCount + entry.value.freeLodgingSlotCount,
    );
    for (var slot = 0; slot < capacity; slot += 1) {
      slotTownIds.add(entry.key);
    }
  }
  if (slotTownIds.isEmpty) {
    return <String>{
      for (final selection in plan.selections) selection.productionNodeId,
    };
  }

  final slotIndicesByTown = <String, List<int>>{};
  for (var slotIndex = 0; slotIndex < slotTownIds.length; slotIndex += 1) {
    (slotIndicesByTown[slotTownIds[slotIndex]] ??= <int>[]).add(slotIndex);
  }
  final matchedSelectionIndexBySlot = List<int>.filled(slotTownIds.length, -1);

  bool augment(int selectionIndex, Set<int> visitedSlots) {
    final productionNodeId = plan.selections[selectionIndex].productionNodeId;
    final townIds =
        (candidateTowns[productionNodeId] ?? const <String>{}).toList()..sort();
    for (final townId in townIds) {
      for (final slotIndex in slotIndicesByTown[townId] ?? const <int>[]) {
        if (!visitedSlots.add(slotIndex)) {
          continue;
        }
        final displacedSelectionIndex = matchedSelectionIndexBySlot[slotIndex];
        if (displacedSelectionIndex == -1 ||
            augment(displacedSelectionIndex, visitedSlots)) {
          matchedSelectionIndexBySlot[slotIndex] = selectionIndex;
          return true;
        }
      }
    }
    return false;
  }

  final rejected = <String>{};
  for (
    var selectionIndex = 0;
    selectionIndex < plan.selections.length;
    selectionIndex += 1
  ) {
    if (!augment(selectionIndex, <int>{})) {
      rejected.add(plan.selections[selectionIndex].productionNodeId);
    }
  }
  return rejected;
}

Set<String> _ownedHouseClosureForTown(
  LodgingTown town,
  Set<String> currentOwnedHouseIds,
) {
  final result = <String>{};
  for (final houseId in currentOwnedHouseIds.where(
    town.housesById.containsKey,
  )) {
    String? currentId = houseId;
    while (currentId != null && result.add(currentId)) {
      currentId = town.housesById[currentId]?.prerequisiteHouseId;
    }
  }
  return result;
}

bool _isBetterFeasible(
  BdoRawSaleLodgingBudgetResult candidate,
  BdoRawSaleLodgingBudgetResult? incumbent,
) {
  if (incumbent == null) {
    return true;
  }
  final valueComparison = candidate.networkPlan.currentSaleValueSignal
      .compareTo(incumbent.networkPlan.currentSaleValueSignal);
  if (valueComparison != 0) {
    return valueComparison > 0;
  }
  if (candidate.networkPlan.selections.length !=
      incumbent.networkPlan.selections.length) {
    return candidate.networkPlan.selections.length >
        incumbent.networkPlan.selections.length;
  }
  if (candidate.combinedContributionPoints !=
      incumbent.combinedContributionPoints) {
    return candidate.combinedContributionPoints <
        incumbent.combinedContributionPoints;
  }
  return _selectionKey(
        candidate.networkPlan,
      ).compareTo(_selectionKey(incumbent.networkPlan)) <
      0;
}

String _selectionKey(BdoRawSaleNetworkPlanResult plan) =>
    plan.selectedProductionNodeIds.join('\u0000');
