/// User-entered worker capacity for one verified worker-hiring town.
///
/// Both values describe capacity that is already available without buying
/// more lodging:
///
/// - [availableWorkerCount] is the number of already-hired workers that are
///   free to take a planned production-node job.
/// - [freeLodgingSlotCount] is the number of currently vacant worker slots in
///   lodging the user already owns. Filling one of these slots requires hiring
///   a worker, but does not require another lodging investment.
///
/// Older saved preferences contain only those two effective values. Newer
/// preferences may also persist the user's raw [hiredWorkerCount] and
/// [bonusLodgingSlotCount]. Call [resolveForKnownTownLodging] before planning
/// to combine those raw values with the town's free base slot and active owned
/// lodging. Keeping the legacy effective values allows old saves to retain
/// their exact meaning.
class BdoTownWorkerCapacity {
  const BdoTownWorkerCapacity({
    required this.availableWorkerCount,
    required this.freeLodgingSlotCount,
    this.hiredWorkerCount,
    this.bonusLodgingSlotCount,
    this.pearlLodgingPurchasedCount,
    this.loyaltyLodgingPurchasedCount,
    this.otherBonusLodgingSlotCount,
  });

  final int availableWorkerCount;
  final int freeLodgingSlotCount;

  /// Workers the user has already hired in this town.
  ///
  /// Null identifies a legacy saved value whose [availableWorkerCount] and
  /// [freeLodgingSlotCount] must remain authoritative.
  final int? hiredWorkerCount;

  /// Aggregate extra lodging slots that are not represented by mapped houses.
  ///
  /// This remains authoritative for older saves that do not have a source
  /// breakdown. New saves also keep the aggregate for downgrade/export
  /// compatibility, while [effectiveBonusLodgingSlotCount] derives from the
  /// presence-aware Pearl, Loyalty, and Other fields.
  final int? bonusLodgingSlotCount;

  /// Town-specific Pearl lodging coupons the player owns.
  final int? pearlLodgingPurchasedCount;

  /// Town-specific Loyalty lodging coupons the player owns.
  final int? loyaltyLodgingPurchasedCount;

  /// Event, choice-box, or older bonus slots outside standard town coupons.
  final int? otherBonusLodgingSlotCount;

  /// Whether the saved bonus has an explicit source breakdown.
  ///
  /// Older saves contain only [bonusLodgingSlotCount]. That total remains
  /// authoritative until the player deliberately saves a split.
  bool get hasBonusLodgingBreakdown =>
      pearlLodgingPurchasedCount != null ||
      loyaltyLodgingPurchasedCount != null ||
      otherBonusLodgingSlotCount != null;

  int get effectiveBonusLodgingSlotCount {
    if (!hasBonusLodgingBreakdown) {
      return _nonNegative(bonusLodgingSlotCount ?? 0);
    }
    return _nonNegative(pearlLodgingPurchasedCount ?? 0) +
        _nonNegative(loyaltyLodgingPurchasedCount ?? 0) +
        _nonNegative(otherBonusLodgingSlotCount ?? 0);
  }

  /// Whether this value should be derived from the town and housing dataset.
  bool get usesKnownTownLodging =>
      hiredWorkerCount != null ||
      bonusLodgingSlotCount != null ||
      hasBonusLodgingBreakdown;

  /// Resolves a persisted value into the effective capacity consumed by the
  /// network planners.
  ///
  /// Already-hired workers remain usable even when their count is greater than
  /// the currently mapped slots. Otherwise, every known empty slot can be
  /// filled without buying another lodging house.
  BdoTownWorkerCapacity resolveForKnownTownLodging({
    required int baseWorkerSlotCount,
    required int activeOwnedLodgingSlotCount,
  }) {
    if (!usesKnownTownLodging) {
      return this;
    }
    final hired = _nonNegative(hiredWorkerCount ?? availableWorkerCount);
    final bonus = effectiveBonusLodgingSlotCount;
    final knownSlotCount =
        _nonNegative(baseWorkerSlotCount) +
        _nonNegative(activeOwnedLodgingSlotCount) +
        bonus;
    return BdoTownWorkerCapacity(
      availableWorkerCount: hired,
      freeLodgingSlotCount: knownSlotCount > hired ? knownSlotCount - hired : 0,
      hiredWorkerCount: hired,
      bonusLodgingSlotCount: bonus,
      pearlLodgingPurchasedCount: pearlLodgingPurchasedCount,
      loyaltyLodgingPurchasedCount: loyaltyLodgingPurchasedCount,
      otherBonusLodgingSlotCount: otherBonusLodgingSlotCount,
    );
  }
}

int _nonNegative(int value) => value < 0 ? 0 : value;

/// Inputs for a worker-capacity assessment of a selected production network.
///
/// Every unique ID in [selectedProductionNodeIds] creates exactly one worker
/// demand, even when a shared production node supplies several requested
/// materials. The caller must supply only selected production-node IDs.
///
/// [candidateTownNodeIdsByProductionNodeId] is explicit reachability supplied
/// by the caller. This service does not infer worker towns or graph paths from
/// map node types. Every candidate town must have an explicit entry in
/// [townCapacitiesByNodeId], including towns whose entered capacity is zero.
class BdoWorkerCapacityAssessmentRequest {
  BdoWorkerCapacityAssessmentRequest({
    required Iterable<String> selectedProductionNodeIds,
    required Map<String, BdoTownWorkerCapacity> townCapacitiesByNodeId,
    required Map<String, Iterable<String>>
    candidateTownNodeIdsByProductionNodeId,
  }) : selectedProductionNodeIds = List<String>.unmodifiable(
         selectedProductionNodeIds,
       ),
       townCapacitiesByNodeId = Map<String, BdoTownWorkerCapacity>.unmodifiable(
         townCapacitiesByNodeId,
       ),
       candidateTownNodeIdsByProductionNodeId =
           Map<String, List<String>>.unmodifiable(<String, List<String>>{
             for (final entry in candidateTownNodeIdsByProductionNodeId.entries)
               entry.key: List<String>.unmodifiable(entry.value),
           });

  final List<String> selectedProductionNodeIds;
  final Map<String, BdoTownWorkerCapacity> townCapacitiesByNodeId;
  final Map<String, List<String>> candidateTownNodeIdsByProductionNodeId;
}

/// Severity of a malformed worker-capacity input.
enum BdoWorkerCapacityDiagnosticSeverity { error }

/// Stable validation codes suitable for concise UI messages.
enum BdoWorkerCapacityDiagnosticCode {
  blankProductionNodeId,
  blankTownNodeId,
  invalidAvailableWorkerCount,
  invalidFreeLodgingSlotCount,
  blankCandidateTownNodeId,
  missingTownCapacity,
}

/// A malformed input that prevents an honest capacity assessment.
class BdoWorkerCapacityDiagnostic {
  const BdoWorkerCapacityDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.productionNodeId,
    this.townNodeId,
  });

  final BdoWorkerCapacityDiagnosticCode code;
  final BdoWorkerCapacityDiagnosticSeverity severity;
  final String message;
  final String? productionNodeId;
  final String? townNodeId;
}

/// Which already-entered town capacity covers one production-node job.
enum BdoWorkerCapacityAssignmentSource {
  /// Reuses an already-hired, currently available worker.
  availableWorker,

  /// Uses a vacant slot in lodging the user already owns.
  ///
  /// The user still needs to hire the worker, but no additional lodging slot
  /// is required.
  freeLodgingSlot,
}

/// One worker assigned to one selected production node.
class BdoProductionWorkerAssignment {
  const BdoProductionWorkerAssignment({
    required this.productionNodeId,
    required this.townNodeId,
    required this.source,
  });

  final String productionNodeId;
  final String townNodeId;
  final BdoWorkerCapacityAssignmentSource source;
}

/// Capacity usage for one town after maximum feasible assignment.
class BdoTownWorkerCapacityUsage {
  BdoTownWorkerCapacityUsage({
    required this.townNodeId,
    required this.availableWorkerCount,
    required this.freeLodgingSlotCount,
    required this.availableWorkersUsed,
    required this.freeLodgingSlotsUsed,
    required Iterable<String> assignedProductionNodeIds,
  }) : assignedProductionNodeIds = List<String>.unmodifiable(
         assignedProductionNodeIds,
       );

  final String townNodeId;
  final int availableWorkerCount;
  final int freeLodgingSlotCount;
  final int availableWorkersUsed;
  final int freeLodgingSlotsUsed;
  final List<String> assignedProductionNodeIds;

  int get assignedWorkerCount => availableWorkersUsed + freeLodgingSlotsUsed;

  int get remainingAvailableWorkerCount =>
      availableWorkerCount - availableWorkersUsed;

  int get remainingFreeLodgingSlotCount =>
      freeLodgingSlotCount - freeLodgingSlotsUsed;
}

/// One production-node job not covered by the entered current capacity.
class BdoUnmetWorkerDemand {
  BdoUnmetWorkerDemand({
    required this.productionNodeId,
    required Iterable<String> candidateTownNodeIds,
  }) : candidateTownNodeIds = List<String>.unmodifiable(candidateTownNodeIds);

  final String productionNodeId;

  /// Verified, explicitly supplied towns that can reach this production node.
  ///
  /// An empty list means that buying more lodging cannot solve the demand
  /// under the reachability data supplied to this assessment.
  final List<String> candidateTownNodeIds;

  bool get isReachable => candidateTownNodeIds.isNotEmpty;
}

/// Maximum use of current worker capacity plus transparent remaining demand.
///
/// This result contains no lodging-house choice, lodging CP, worker travel
/// time, workload, yield, or silver-per-hour claim.
class BdoWorkerCapacityAssessment {
  BdoWorkerCapacityAssessment({
    required Iterable<String> productionNodeIds,
    required Iterable<BdoProductionWorkerAssignment> assignments,
    required Iterable<BdoTownWorkerCapacityUsage> townUsages,
    required Iterable<BdoUnmetWorkerDemand> unmetDemands,
  }) : productionNodeIds = List<String>.unmodifiable(productionNodeIds),
       assignments = List<BdoProductionWorkerAssignment>.unmodifiable(
         assignments,
       ),
       townUsages = List<BdoTownWorkerCapacityUsage>.unmodifiable(townUsages),
       unmetDemands = List<BdoUnmetWorkerDemand>.unmodifiable(unmetDemands);

  /// Unique selected production-node IDs in deterministic order.
  final List<String> productionNodeIds;
  final List<BdoProductionWorkerAssignment> assignments;
  final List<BdoTownWorkerCapacityUsage> townUsages;
  final List<BdoUnmetWorkerDemand> unmetDemands;

  int get workerDemandCount => productionNodeIds.length;
  int get assignedWorkerCount => assignments.length;
  int get unmetWorkerCount => unmetDemands.length;

  int get availableWorkersUsed => assignments
      .where(
        (assignment) =>
            assignment.source ==
            BdoWorkerCapacityAssignmentSource.availableWorker,
      )
      .length;

  int get freeLodgingSlotsUsed => assignedWorkerCount - availableWorkersUsed;

  List<String> get unreachableProductionNodeIds => List<String>.unmodifiable(
    unmetDemands
        .where((demand) => !demand.isReachable)
        .map((demand) => demand.productionNodeId),
  );

  /// Minimum number of new lodging slots needed for every currently unmet
  /// demand that has at least one supplied candidate town.
  ///
  /// Each selected production node requires one worker. Once maximum current
  /// capacity is used, one additional slot at any candidate town is therefore
  /// both necessary and sufficient for each reachable unmet demand.
  int get minimumAdditionalLodgingSlotsForReachableDemand =>
      unmetDemands.where((demand) => demand.isReachable).length;

  /// Minimum new lodging slots needed to cover the complete selected network.
  ///
  /// Null means at least one production node has no supplied reachable worker
  /// town, so lodging alone cannot cover the complete request. This is a count
  /// only, not a house or CP recommendation.
  int? get minimumAdditionalLodgingSlotsToCoverAll =>
      unreachableProductionNodeIds.isEmpty
      ? minimumAdditionalLodgingSlotsForReachableDemand
      : null;

  bool get isCoveredByCurrentCapacity => unmetDemands.isEmpty;

  bool get canBeCoveredByAddingLodgingSlots =>
      unreachableProductionNodeIds.isEmpty;
}

/// Validation diagnostics and, when valid, the completed assessment.
class BdoWorkerCapacityAssessmentResult {
  BdoWorkerCapacityAssessmentResult({
    required this.assessment,
    required Iterable<BdoWorkerCapacityDiagnostic> diagnostics,
  }) : diagnostics = List<BdoWorkerCapacityDiagnostic>.unmodifiable(
         diagnostics,
       );

  final BdoWorkerCapacityAssessment? assessment;
  final List<BdoWorkerCapacityDiagnostic> diagnostics;

  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoWorkerCapacityDiagnosticSeverity.error,
  );

  bool get hasAssessment => assessment != null;
}

/// Deterministically assesses whether user-entered town capacity can staff a
/// selected worker-node network.
///
/// The service solves a capacitated bipartite matching:
///
/// 1. maximize the number of selected production nodes that receive a worker;
/// 2. among maximum assignments, reuse as many already-hired workers as
///    possible before consuming vacant lodging slots;
/// 3. normalize all input IDs into a stable total order so equivalent
///    maximum/minimum-cost requests return the same assignment regardless of
///    caller collection order.
///
/// When several assignments have identical coverage and worker-reuse cost,
/// the returned assignment is deterministic but is not presented as a
/// lexicographically optimal town allocation.
///
/// Reachability and capacity are never inferred. The result cannot recommend
/// lodging houses or add lodging CP because those inputs are intentionally
/// absent.
class BdoWorkerCapacityAssessmentService {
  const BdoWorkerCapacityAssessmentService();

  BdoWorkerCapacityAssessmentResult assess(
    BdoWorkerCapacityAssessmentRequest request,
  ) {
    final diagnostics = <BdoWorkerCapacityDiagnostic>[];
    final productionNodeIds = request.selectedProductionNodeIds.toSet().toList()
      ..sort(_compareIds);
    final townEntries = request.townCapacitiesByNodeId.entries.toList()
      ..sort((left, right) => _compareIds(left.key, right.key));

    for (final productionNodeId in productionNodeIds) {
      if (productionNodeId.trim().isEmpty) {
        diagnostics.add(
          const BdoWorkerCapacityDiagnostic(
            code: BdoWorkerCapacityDiagnosticCode.blankProductionNodeId,
            severity: BdoWorkerCapacityDiagnosticSeverity.error,
            message: 'Selected production-node IDs must not be blank.',
          ),
        );
      }
    }

    for (final entry in townEntries) {
      final townNodeId = entry.key;
      final capacity = entry.value;
      if (townNodeId.trim().isEmpty) {
        diagnostics.add(
          const BdoWorkerCapacityDiagnostic(
            code: BdoWorkerCapacityDiagnosticCode.blankTownNodeId,
            severity: BdoWorkerCapacityDiagnosticSeverity.error,
            message: 'Worker-town node IDs must not be blank.',
          ),
        );
      }
      if (capacity.availableWorkerCount < 0) {
        diagnostics.add(
          BdoWorkerCapacityDiagnostic(
            code: BdoWorkerCapacityDiagnosticCode.invalidAvailableWorkerCount,
            severity: BdoWorkerCapacityDiagnosticSeverity.error,
            message: 'Available worker counts must be non-negative.',
            townNodeId: townNodeId,
          ),
        );
      }
      if (capacity.freeLodgingSlotCount < 0) {
        diagnostics.add(
          BdoWorkerCapacityDiagnostic(
            code: BdoWorkerCapacityDiagnosticCode.invalidFreeLodgingSlotCount,
            severity: BdoWorkerCapacityDiagnosticSeverity.error,
            message: 'Free lodging-slot counts must be non-negative.',
            townNodeId: townNodeId,
          ),
        );
      }
    }

    final candidateTownsByProductionNodeId = <String, List<String>>{};
    for (final productionNodeId in productionNodeIds) {
      final candidates =
          (request.candidateTownNodeIdsByProductionNodeId[productionNodeId] ??
                  const <String>[])
              .toSet()
              .toList()
            ..sort(_compareIds);
      candidateTownsByProductionNodeId[productionNodeId] = candidates;
      for (final townNodeId in candidates) {
        if (townNodeId.trim().isEmpty) {
          diagnostics.add(
            BdoWorkerCapacityDiagnostic(
              code: BdoWorkerCapacityDiagnosticCode.blankCandidateTownNodeId,
              severity: BdoWorkerCapacityDiagnosticSeverity.error,
              message: 'Candidate worker-town node IDs must not be blank.',
              productionNodeId: productionNodeId,
            ),
          );
          continue;
        }
        if (!request.townCapacitiesByNodeId.containsKey(townNodeId)) {
          diagnostics.add(
            BdoWorkerCapacityDiagnostic(
              code: BdoWorkerCapacityDiagnosticCode.missingTownCapacity,
              severity: BdoWorkerCapacityDiagnosticSeverity.error,
              message:
                  'Every candidate worker town needs explicit user-entered '
                  'capacity, including a zero-capacity entry.',
              productionNodeId: productionNodeId,
              townNodeId: townNodeId,
            ),
          );
        }
      }
    }

    diagnostics.sort(_compareDiagnostics);
    if (diagnostics.isNotEmpty) {
      return BdoWorkerCapacityAssessmentResult(
        assessment: null,
        diagnostics: diagnostics,
      );
    }

    final assignments = _assignCurrentCapacity(
      productionNodeIds: productionNodeIds,
      townEntries: townEntries,
      candidateTownsByProductionNodeId: candidateTownsByProductionNodeId,
    );
    final assignedProductionNodeIds = assignments
        .map((assignment) => assignment.productionNodeId)
        .toSet();
    final unmetDemands = <BdoUnmetWorkerDemand>[
      for (final productionNodeId in productionNodeIds)
        if (!assignedProductionNodeIds.contains(productionNodeId))
          BdoUnmetWorkerDemand(
            productionNodeId: productionNodeId,
            candidateTownNodeIds:
                candidateTownsByProductionNodeId[productionNodeId]!,
          ),
    ];

    final assignmentsByTown = <String, List<BdoProductionWorkerAssignment>>{};
    for (final assignment in assignments) {
      (assignmentsByTown[assignment.townNodeId] ??=
              <BdoProductionWorkerAssignment>[])
          .add(assignment);
    }
    final townUsages = <BdoTownWorkerCapacityUsage>[];
    for (final entry in townEntries) {
      final townAssignments =
          assignmentsByTown[entry.key] ??
          const <BdoProductionWorkerAssignment>[];
      final assignedIds =
          townAssignments
              .map((assignment) => assignment.productionNodeId)
              .toList()
            ..sort(_compareIds);
      townUsages.add(
        BdoTownWorkerCapacityUsage(
          townNodeId: entry.key,
          availableWorkerCount: entry.value.availableWorkerCount,
          freeLodgingSlotCount: entry.value.freeLodgingSlotCount,
          availableWorkersUsed: townAssignments
              .where(
                (assignment) =>
                    assignment.source ==
                    BdoWorkerCapacityAssignmentSource.availableWorker,
              )
              .length,
          freeLodgingSlotsUsed: townAssignments
              .where(
                (assignment) =>
                    assignment.source ==
                    BdoWorkerCapacityAssignmentSource.freeLodgingSlot,
              )
              .length,
          assignedProductionNodeIds: assignedIds,
        ),
      );
    }

    return BdoWorkerCapacityAssessmentResult(
      assessment: BdoWorkerCapacityAssessment(
        productionNodeIds: productionNodeIds,
        assignments: assignments,
        townUsages: townUsages,
        unmetDemands: unmetDemands,
      ),
      diagnostics: const <BdoWorkerCapacityDiagnostic>[],
    );
  }
}

List<BdoProductionWorkerAssignment> _assignCurrentCapacity({
  required List<String> productionNodeIds,
  required List<MapEntry<String, BdoTownWorkerCapacity>> townEntries,
  required Map<String, List<String>> candidateTownsByProductionNodeId,
}) {
  if (productionNodeIds.isEmpty || townEntries.isEmpty) {
    return const <BdoProductionWorkerAssignment>[];
  }

  const sourceVertex = 0;
  final productionVertexById = <String, int>{};
  var nextVertex = 1;
  for (final productionNodeId in productionNodeIds) {
    productionVertexById[productionNodeId] = nextVertex++;
  }

  final availableWorkerVertexByTownId = <String, int>{};
  final freeLodgingVertexByTownId = <String, int>{};
  for (final entry in townEntries) {
    availableWorkerVertexByTownId[entry.key] = nextVertex++;
    freeLodgingVertexByTownId[entry.key] = nextVertex++;
  }
  final sinkVertex = nextVertex++;
  final graph = _MinCostFlowGraph(nextVertex);

  for (final productionNodeId in productionNodeIds) {
    graph.addEdge(
      sourceVertex,
      productionVertexById[productionNodeId]!,
      capacity: 1,
      cost: 0,
    );
  }

  final maximumUsefulCapacity = productionNodeIds.length;
  for (final entry in townEntries) {
    graph.addEdge(
      availableWorkerVertexByTownId[entry.key]!,
      sinkVertex,
      capacity: _boundedCapacity(
        entry.value.availableWorkerCount,
        maximumUsefulCapacity,
      ),
      cost: 0,
    );
    graph.addEdge(
      freeLodgingVertexByTownId[entry.key]!,
      sinkVertex,
      capacity: _boundedCapacity(
        entry.value.freeLodgingSlotCount,
        maximumUsefulCapacity,
      ),
      cost: 0,
    );
  }

  final assignmentEdges = <_WorkerAssignmentEdge>[];
  final capacityByTownId = <String, BdoTownWorkerCapacity>{
    for (final entry in townEntries) entry.key: entry.value,
  };
  for (final productionNodeId in productionNodeIds) {
    final productionVertex = productionVertexById[productionNodeId]!;
    for (final townNodeId
        in candidateTownsByProductionNodeId[productionNodeId]!) {
      final capacity = capacityByTownId[townNodeId]!;
      if (capacity.availableWorkerCount > 0) {
        assignmentEdges.add(
          _WorkerAssignmentEdge(
            productionNodeId: productionNodeId,
            townNodeId: townNodeId,
            source: BdoWorkerCapacityAssignmentSource.availableWorker,
            edge: graph.addEdge(
              productionVertex,
              availableWorkerVertexByTownId[townNodeId]!,
              capacity: 1,
              cost: 0,
            ),
          ),
        );
      }
      if (capacity.freeLodgingSlotCount > 0) {
        assignmentEdges.add(
          _WorkerAssignmentEdge(
            productionNodeId: productionNodeId,
            townNodeId: townNodeId,
            source: BdoWorkerCapacityAssignmentSource.freeLodgingSlot,
            edge: graph.addEdge(
              productionVertex,
              freeLodgingVertexByTownId[townNodeId]!,
              capacity: 1,
              cost: 1,
            ),
          ),
        );
      }
    }
  }

  graph.sendMaximumMinimumCostFlow(sourceVertex, sinkVertex);

  final assignments =
      assignmentEdges
          .where((assignmentEdge) => assignmentEdge.edge.flow == 1)
          .map(
            (assignmentEdge) => BdoProductionWorkerAssignment(
              productionNodeId: assignmentEdge.productionNodeId,
              townNodeId: assignmentEdge.townNodeId,
              source: assignmentEdge.source,
            ),
          )
          .toList()
        ..sort(_compareAssignments);
  return List<BdoProductionWorkerAssignment>.unmodifiable(assignments);
}

int _boundedCapacity(int capacity, int maximumUsefulCapacity) =>
    capacity < maximumUsefulCapacity ? capacity : maximumUsefulCapacity;

class _WorkerAssignmentEdge {
  const _WorkerAssignmentEdge({
    required this.productionNodeId,
    required this.townNodeId,
    required this.source,
    required this.edge,
  });

  final String productionNodeId;
  final String townNodeId;
  final BdoWorkerCapacityAssignmentSource source;
  final _FlowEdge edge;
}

class _MinCostFlowGraph {
  _MinCostFlowGraph(int vertexCount)
    : edgesByVertex = List<List<_FlowEdge>>.generate(
        vertexCount,
        (_) => <_FlowEdge>[],
      );

  final List<List<_FlowEdge>> edgesByVertex;

  _FlowEdge addEdge(
    int from,
    int to, {
    required int capacity,
    required int cost,
  }) {
    final forward = _FlowEdge(
      to: to,
      reverseIndex: edgesByVertex[to].length,
      capacity: capacity,
      cost: cost,
    );
    final reverse = _FlowEdge(
      to: from,
      reverseIndex: edgesByVertex[from].length,
      capacity: 0,
      cost: -cost,
    );
    edgesByVertex[from].add(forward);
    edgesByVertex[to].add(reverse);
    return forward;
  }

  void sendMaximumMinimumCostFlow(int source, int sink) {
    while (true) {
      final predecessorVertex = List<int>.filled(edgesByVertex.length, -1);
      final predecessorEdge = List<int>.filled(edgesByVertex.length, -1);
      final distance = List<int?>.filled(edgesByVertex.length, null);
      distance[source] = 0;

      for (var pass = 0; pass < edgesByVertex.length - 1; pass += 1) {
        var changed = false;
        for (var vertex = 0; vertex < edgesByVertex.length; vertex += 1) {
          final fromDistance = distance[vertex];
          if (fromDistance == null) {
            continue;
          }
          final edges = edgesByVertex[vertex];
          for (var edgeIndex = 0; edgeIndex < edges.length; edgeIndex += 1) {
            final edge = edges[edgeIndex];
            if (edge.capacity <= 0) {
              continue;
            }
            final candidateDistance = fromDistance + edge.cost;
            final currentDistance = distance[edge.to];
            if (currentDistance != null &&
                candidateDistance >= currentDistance) {
              continue;
            }
            distance[edge.to] = candidateDistance;
            predecessorVertex[edge.to] = vertex;
            predecessorEdge[edge.to] = edgeIndex;
            changed = true;
          }
        }
        if (!changed) {
          break;
        }
      }

      if (predecessorVertex[sink] < 0) {
        return;
      }

      var vertex = sink;
      while (vertex != source) {
        final from = predecessorVertex[vertex];
        final edge = edgesByVertex[from][predecessorEdge[vertex]];
        final reverse = edgesByVertex[edge.to][edge.reverseIndex];
        edge
          ..capacity -= 1
          ..flow += 1;
        reverse
          ..capacity += 1
          ..flow -= 1;
        vertex = from;
      }
    }
  }
}

class _FlowEdge {
  _FlowEdge({
    required this.to,
    required this.reverseIndex,
    required this.capacity,
    required this.cost,
  });

  final int to;
  final int reverseIndex;
  int capacity;
  final int cost;
  int flow = 0;
}

int _compareAssignments(
  BdoProductionWorkerAssignment left,
  BdoProductionWorkerAssignment right,
) {
  final productionComparison = _compareIds(
    left.productionNodeId,
    right.productionNodeId,
  );
  if (productionComparison != 0) {
    return productionComparison;
  }
  final townComparison = _compareIds(left.townNodeId, right.townNodeId);
  if (townComparison != 0) {
    return townComparison;
  }
  return left.source.index.compareTo(right.source.index);
}

int _compareDiagnostics(
  BdoWorkerCapacityDiagnostic left,
  BdoWorkerCapacityDiagnostic right,
) {
  final productionComparison = _compareIds(
    left.productionNodeId ?? '',
    right.productionNodeId ?? '',
  );
  if (productionComparison != 0) {
    return productionComparison;
  }
  final townComparison = _compareIds(
    left.townNodeId ?? '',
    right.townNodeId ?? '',
  );
  if (townComparison != 0) {
    return townComparison;
  }
  return left.code.index.compareTo(right.code.index);
}

int _compareIds(String left, String right) {
  final leftNumber = BigInt.tryParse(left);
  final rightNumber = BigInt.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final numberComparison = leftNumber.compareTo(rightNumber);
    if (numberComparison != 0) {
      return numberComparison;
    }
    return left.compareTo(right);
  }
  if (leftNumber != null) {
    return -1;
  }
  if (rightNumber != null) {
    return 1;
  }
  return left.compareTo(right);
}
