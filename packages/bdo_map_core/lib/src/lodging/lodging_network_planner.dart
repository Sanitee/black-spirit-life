import '../network/worker_capacity_assessment.dart';
import 'lodging_data.dart';
import 'lodging_optimizer.dart';

/// Whether the returned cross-town lodging allocation has a proof of minimum
/// incremental contribution-point cost.
enum BdoLodgingNetworkSolutionQuality {
  /// Every reachable town-count allocation was considered.
  exact,

  /// A deterministic bounded search returned a feasible allocation after the
  /// exact state limit was reached.
  deterministicFallback,
}

enum BdoLodgingNetworkDiagnosticSeverity { warning, error }

enum BdoLodgingNetworkDiagnosticCode {
  blankProductionNodeId,
  duplicateProductionNodeId,
  blankCandidateTownNodeId,
  unknownCandidateTown,
  candidateTownCannotHireWorkers,
  unreachableProductionNode,
  blankOwnedHouseId,
  unknownOwnedHouse,
  blankBlockedHouseId,
  unknownBlockedHouse,
  ownedHouseAlsoBlocked,
  blankExistingCapacityTownNodeId,
  unknownExistingCapacityTown,
  invalidExistingCapacity,
  insufficientLodgingCapacity,
  exactSearchLimitReached,
}

final class BdoLodgingNetworkDiagnostic {
  const BdoLodgingNetworkDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.productionNodeId,
    this.townNodeId,
    this.houseId,
  });

  final BdoLodgingNetworkDiagnosticCode code;
  final BdoLodgingNetworkDiagnosticSeverity severity;
  final String message;
  final String? productionNodeId;
  final String? townNodeId;
  final String? houseId;
}

/// A complete assignment of unmet production jobs to newly purchased lodging.
final class BdoLodgingNetworkPlan {
  BdoLodgingNetworkPlan({
    required Map<String, String> townNodeIdByProductionNodeId,
    required Iterable<LodgingPlan> townPlans,
    required this.quality,
    required this.searchStateCount,
  }) : townNodeIdByProductionNodeId = Map<String, String>.unmodifiable(
         _sortedStringMap(townNodeIdByProductionNodeId),
       ),
       townPlans = List<LodgingPlan>.unmodifiable(
         townPlans.toList(growable: false)..sort(
           (left, right) => _compareIds(left.townNodeId, right.townNodeId),
         ),
       );

  final Map<String, String> townNodeIdByProductionNodeId;
  final List<LodgingPlan> townPlans;
  final BdoLodgingNetworkSolutionQuality quality;

  /// Number of distinct town-capacity states retained by the successful
  /// search. This is diagnostic only and is not a measure of game complexity.
  final int searchStateCount;

  bool get isOptimalityProven =>
      quality == BdoLodgingNetworkSolutionQuality.exact;

  Map<String, LodgingPlan> get townPlansByNodeId =>
      Map<String, LodgingPlan>.unmodifiable(<String, LodgingPlan>{
        for (final plan in townPlans) plan.townNodeId: plan,
      });

  int get requiredWorkerSlots => townNodeIdByProductionNodeId.length;

  /// Actual lodging capacity acquired. This can exceed [requiredWorkerSlots]
  /// because a house may add several lodging slots at once.
  int get addedLodgingSlots =>
      townPlans.fold(0, (sum, plan) => sum + plan.addedCapacity);

  int get capacityOversupply =>
      townPlans.fold(0, (sum, plan) => sum + plan.capacityOversupply);

  int get totalIncrementalContributionPoints => townPlans.fold(
    0,
    (sum, plan) => sum + plan.incrementalContributionPoints,
  );

  List<String> get newlyRequiredHouseIds =>
      _sortedIds(townPlans.expand((plan) => plan.newlyRequiredHouseIds));

  List<String> get ownedHouseIdsUsed =>
      _sortedIds(townPlans.expand((plan) => plan.ownedHouseIdsUsed));
}

final class BdoLodgingNetworkPlanningResult {
  BdoLodgingNetworkPlanningResult({
    required this.plan,
    required Iterable<BdoLodgingNetworkDiagnostic> diagnostics,
  }) : diagnostics = List<BdoLodgingNetworkDiagnostic>.unmodifiable(
         diagnostics,
       );

  final BdoLodgingNetworkPlan? plan;
  final List<BdoLodgingNetworkDiagnostic> diagnostics;

  bool get isFeasible => plan != null;

  bool get isOptimalityProven => plan?.isOptimalityProven ?? false;

  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoLodgingNetworkDiagnosticSeverity.error,
  );
}

/// Assigns unmet worker jobs to towns and chooses the cheapest added lodging.
///
/// Each [BdoUnmetWorkerDemand] already represents a job that could not use an
/// available worker or a free slot in existing lodging. Consequently every
/// assigned job needs one *new* lodging slot.
///
/// [currentOwnedHouseIds] may contain any house usage: storage, stable,
/// workshop, residence, lodging, or another supported use. Selecting an owned
/// downstream house also implies its prerequisite chain is already invested,
/// which prevents the planner from charging those shared houses again.
///
/// The exact search works over per-town worker counts rather than individual
/// house combinations. [LodgingOptimizer] proves the cheapest house closure
/// for each count. If the cross-town state space exceeds [maxExactStates], a
/// deterministic bounded search is used and the result explicitly stops
/// claiming optimality.
final class BdoLodgingNetworkPlanner {
  const BdoLodgingNetworkPlanner({
    this.maxExactStates = 200000,
    this.fallbackBeamWidth = 4096,
  }) : assert(maxExactStates > 0),
       assert(fallbackBeamWidth > 0);

  final int maxExactStates;
  final int fallbackBeamWidth;

  BdoLodgingNetworkPlanningResult plan({
    required LodgingDataset dataset,
    required Iterable<BdoUnmetWorkerDemand> unmetDemands,
    Set<String> currentOwnedHouseIds = const <String>{},
    Set<String> blockedHouseIds = const <String>{},
    Map<String, int> existingWorkerCapacityByTownNodeId = const <String, int>{},
  }) {
    if (maxExactStates <= 0 || fallbackBeamWidth <= 0) {
      throw StateError('Lodging search limits must be positive.');
    }

    final diagnostics = <BdoLodgingNetworkDiagnostic>[];
    final normalizedDemands = _validateDemands(
      dataset: dataset,
      unmetDemands: unmetDemands,
      diagnostics: diagnostics,
    );
    final owned = _validateHouseIds(
      dataset: dataset,
      values: currentOwnedHouseIds,
      blankCode: BdoLodgingNetworkDiagnosticCode.blankOwnedHouseId,
      unknownCode: BdoLodgingNetworkDiagnosticCode.unknownOwnedHouse,
      label: 'owned',
      diagnostics: diagnostics,
    );
    final blocked = _validateHouseIds(
      dataset: dataset,
      values: blockedHouseIds,
      blankCode: BdoLodgingNetworkDiagnosticCode.blankBlockedHouseId,
      unknownCode: BdoLodgingNetworkDiagnosticCode.unknownBlockedHouse,
      label: 'blocked',
      diagnostics: diagnostics,
    );
    final existingWorkerCapacity = _validateExistingWorkerCapacity(
      dataset: dataset,
      values: existingWorkerCapacityByTownNodeId,
      diagnostics: diagnostics,
    );

    for (final houseId
        in owned.intersection(blocked).toList()..sort(_compareIds)) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.ownedHouseAlsoBlocked,
          severity: BdoLodgingNetworkDiagnosticSeverity.warning,
          message:
              'Owned house $houseId remains usable as an already-invested '
              'prerequisite even though it is also blocked.',
          houseId: houseId,
        ),
      );
    }

    _sortDiagnostics(diagnostics);
    if (_hasErrors(diagnostics)) {
      return BdoLodgingNetworkPlanningResult(
        plan: null,
        diagnostics: diagnostics,
      );
    }

    final ownedClosure = _expandOwnedPrerequisiteClosure(dataset, owned);
    if (normalizedDemands.isEmpty) {
      return BdoLodgingNetworkPlanningResult(
        plan: BdoLodgingNetworkPlan(
          townNodeIdByProductionNodeId: const <String, String>{},
          townPlans: const <LodgingPlan>[],
          quality: BdoLodgingNetworkSolutionQuality.exact,
          searchStateCount: 1,
        ),
        diagnostics: diagnostics,
      );
    }

    final relevantTownIds =
        normalizedDemands
            .expand((demand) => demand.candidateTownNodeIds)
            .toSet()
            .toList(growable: false)
          ..sort(_compareIds);
    final townOptions = <_TownLodgingOptions>[
      for (final townId in relevantTownIds)
        _TownLodgingOptions(
          town: dataset.townsByNodeId[townId]!,
          ownedHouseIds: ownedClosure,
          blockedHouseIds: blocked,
          existingCapacity: existingWorkerCapacity[townId] ?? 0,
          maximumUsefulCapacity: normalizedDemands.length,
        ),
    ];
    final townIndexById = <String, int>{
      for (var index = 0; index < townOptions.length; index += 1)
        townOptions[index].town.townNodeId: index,
    };
    final jobs =
        <_WorkerJob>[
          for (final demand in normalizedDemands)
            _WorkerJob(
              productionNodeId: demand.productionNodeId,
              candidateTownIndices: <int>[
                for (final townId in demand.candidateTownNodeIds)
                  townIndexById[townId]!,
              ]..sort(),
            ),
        ]..sort((left, right) {
          final candidateCountComparison = left.candidateTownIndices.length
              .compareTo(right.candidateTownIndices.length);
          if (candidateCountComparison != 0) return candidateCountComparison;
          return _compareIds(left.productionNodeId, right.productionNodeId);
        });

    final baseline = _findFeasibleAssignment(
      jobs: jobs,
      townOptions: townOptions,
    );
    if (baseline == null) {
      diagnostics.add(
        const BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.insufficientLodgingCapacity,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message:
              'The candidate towns do not have enough additional lodging '
              'capacity to staff every selected production node.',
        ),
      );
      _sortDiagnostics(diagnostics);
      return BdoLodgingNetworkPlanningResult(
        plan: null,
        diagnostics: diagnostics,
      );
    }

    final exactSearch = _searchAssignments(
      jobs: jobs,
      townOptions: townOptions,
      stateLimit: maxExactStates,
      useBeam: false,
    );
    late final _AssignmentState selected;
    late final BdoLodgingNetworkSolutionQuality quality;
    late final int searchStateCount;
    if (!exactSearch.didReachLimit) {
      selected = exactSearch.best!;
      quality = BdoLodgingNetworkSolutionQuality.exact;
      searchStateCount = exactSearch.retainedStateCount;
    } else {
      final beamSearch = _searchAssignments(
        jobs: jobs,
        townOptions: townOptions,
        stateLimit: fallbackBeamWidth,
        useBeam: true,
      );
      final improvedBaseline = _improveAssignment(
        baseline,
        jobs: jobs,
        townOptions: townOptions,
      );
      final beamBest = beamSearch.best;
      selected =
          beamBest != null &&
              _compareAssignmentStates(
                    beamBest,
                    improvedBaseline,
                    townOptions,
                  ) <
                  0
          ? beamBest
          : improvedBaseline;
      quality = BdoLodgingNetworkSolutionQuality.deterministicFallback;
      searchStateCount = beamSearch.retainedStateCount;
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.exactSearchLimitReached,
          severity: BdoLodgingNetworkDiagnosticSeverity.warning,
          message:
              'The lodging request exceeded the exact $maxExactStates-state '
              'search limit. A deterministic feasible plan is shown, but the '
              'absolute lowest CP cost is not proven.',
        ),
      );
    }

    final townPlans = <LodgingPlan>[];
    for (var townIndex = 0; townIndex < townOptions.length; townIndex += 1) {
      final requiredSlots = selected.counts[townIndex];
      if (requiredSlots == 0) continue;
      townPlans.add(townOptions[townIndex].planFor(requiredSlots));
    }
    final assignments = <String, String>{};
    for (var jobIndex = 0; jobIndex < jobs.length; jobIndex += 1) {
      assignments[jobs[jobIndex].productionNodeId] =
          townOptions[selected.assignedTownIndices[jobIndex]].town.townNodeId;
    }
    _sortDiagnostics(diagnostics);
    return BdoLodgingNetworkPlanningResult(
      plan: BdoLodgingNetworkPlan(
        townNodeIdByProductionNodeId: assignments,
        townPlans: townPlans,
        quality: quality,
        searchStateCount: searchStateCount,
      ),
      diagnostics: diagnostics,
    );
  }
}

List<BdoUnmetWorkerDemand> _validateDemands({
  required LodgingDataset dataset,
  required Iterable<BdoUnmetWorkerDemand> unmetDemands,
  required List<BdoLodgingNetworkDiagnostic> diagnostics,
}) {
  final seenProductionNodeIds = <String>{};
  final normalized = <BdoUnmetWorkerDemand>[];
  for (final demand in unmetDemands) {
    final productionNodeId = demand.productionNodeId.trim();
    if (productionNodeId.isEmpty) {
      diagnostics.add(
        const BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.blankProductionNodeId,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message: 'Production-node IDs must not be blank.',
        ),
      );
      continue;
    }
    if (!seenProductionNodeIds.add(productionNodeId)) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.duplicateProductionNodeId,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message:
              'Production node $productionNodeId appears more than once. '
              'Each production node creates only one worker job.',
          productionNodeId: productionNodeId,
        ),
      );
      continue;
    }

    final candidateTownIds = <String>{};
    for (final rawTownId in demand.candidateTownNodeIds) {
      final townId = rawTownId.trim();
      if (townId.isEmpty) {
        diagnostics.add(
          BdoLodgingNetworkDiagnostic(
            code: BdoLodgingNetworkDiagnosticCode.blankCandidateTownNodeId,
            severity: BdoLodgingNetworkDiagnosticSeverity.error,
            message: 'Candidate worker-town IDs must not be blank.',
            productionNodeId: productionNodeId,
          ),
        );
        continue;
      }
      final town = dataset.townsByNodeId[townId];
      if (town == null) {
        diagnostics.add(
          BdoLodgingNetworkDiagnostic(
            code: BdoLodgingNetworkDiagnosticCode.unknownCandidateTown,
            severity: BdoLodgingNetworkDiagnosticSeverity.error,
            message:
                'Candidate town $townId is absent from the verified housing '
                'dataset.',
            productionNodeId: productionNodeId,
            townNodeId: townId,
          ),
        );
        continue;
      }
      if (!town.isWorkerTown) {
        diagnostics.add(
          BdoLodgingNetworkDiagnostic(
            code:
                BdoLodgingNetworkDiagnosticCode.candidateTownCannotHireWorkers,
            severity: BdoLodgingNetworkDiagnosticSeverity.error,
            message: '${town.name} is not a worker-hiring town.',
            productionNodeId: productionNodeId,
            townNodeId: townId,
          ),
        );
        continue;
      }
      candidateTownIds.add(townId);
    }
    if (candidateTownIds.isEmpty) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.unreachableProductionNode,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message:
              'Production node $productionNodeId has no verified worker town '
              'that can staff it.',
          productionNodeId: productionNodeId,
        ),
      );
    }
    normalized.add(
      BdoUnmetWorkerDemand(
        productionNodeId: productionNodeId,
        candidateTownNodeIds: candidateTownIds.toList(growable: false)
          ..sort(_compareIds),
      ),
    );
  }
  return normalized;
}

Set<String> _validateHouseIds({
  required LodgingDataset dataset,
  required Iterable<String> values,
  required BdoLodgingNetworkDiagnosticCode blankCode,
  required BdoLodgingNetworkDiagnosticCode unknownCode,
  required String label,
  required List<BdoLodgingNetworkDiagnostic> diagnostics,
}) {
  final normalized = <String>{};
  for (final rawHouseId in values) {
    final houseId = rawHouseId.trim();
    if (houseId.isEmpty) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: blankCode,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message: 'The $label house list must not contain blank IDs.',
        ),
      );
      continue;
    }
    if (!dataset.housesById.containsKey(houseId)) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: unknownCode,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message:
              'The $label house $houseId is absent from the verified housing '
              'dataset.',
          houseId: houseId,
        ),
      );
      continue;
    }
    normalized.add(houseId);
  }
  return normalized;
}

Map<String, int> _validateExistingWorkerCapacity({
  required LodgingDataset dataset,
  required Map<String, int> values,
  required List<BdoLodgingNetworkDiagnostic> diagnostics,
}) {
  final normalized = <String, int>{};
  for (final entry in values.entries) {
    final townNodeId = entry.key.trim();
    if (townNodeId.isEmpty) {
      diagnostics.add(
        const BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.blankExistingCapacityTownNodeId,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message: 'Existing worker-capacity town IDs must not be blank.',
        ),
      );
      continue;
    }
    final town = dataset.townsByNodeId[townNodeId];
    if (town == null || !town.isWorkerTown) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.unknownExistingCapacityTown,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message:
              'Existing worker capacity references unknown worker town '
              '$townNodeId.',
          townNodeId: townNodeId,
        ),
      );
      continue;
    }
    if (entry.value < 0) {
      diagnostics.add(
        BdoLodgingNetworkDiagnostic(
          code: BdoLodgingNetworkDiagnosticCode.invalidExistingCapacity,
          severity: BdoLodgingNetworkDiagnosticSeverity.error,
          message: 'Existing worker capacity must not be negative.',
          townNodeId: townNodeId,
        ),
      );
      continue;
    }
    normalized[townNodeId] = entry.value;
  }
  return normalized;
}

Set<String> _expandOwnedPrerequisiteClosure(
  LodgingDataset dataset,
  Set<String> ownedHouseIds,
) {
  final closure = <String>{};
  for (final houseId in ownedHouseIds) {
    String? currentId = houseId;
    while (currentId != null && closure.add(currentId)) {
      currentId = dataset.housesById[currentId]!.prerequisiteHouseId;
    }
  }
  return closure;
}

final class _TownLodgingOptions {
  _TownLodgingOptions({
    required this.town,
    required Set<String> ownedHouseIds,
    required Set<String> blockedHouseIds,
    required this.existingCapacity,
    required int maximumUsefulCapacity,
  }) : ownedHouseIds = Set<String>.unmodifiable(
         ownedHouseIds.where(town.housesById.containsKey),
       ),
       blockedHouseIds = Set<String>.unmodifiable(
         blockedHouseIds.where(town.housesById.containsKey),
       ),
       maxAssignableCapacity =
           (existingCapacity +
                   town.lodgingHouses
                       .where(
                         (house) =>
                             !ownedHouseIds.contains(house.id) &&
                             !blockedHouseIds.contains(house.id),
                       )
                       .fold<int>(0, (sum, house) => sum + house.lodgingSpaces))
               .clamp(0, maximumUsefulCapacity);

  final LodgingTown town;
  final Set<String> ownedHouseIds;
  final Set<String> blockedHouseIds;
  final int existingCapacity;
  final int maxAssignableCapacity;
  final Map<int, LodgingPlan> _plans = <int, LodgingPlan>{};

  LodgingPlan planFor(int requiredCapacity) {
    if (requiredCapacity < 0 || requiredCapacity > maxAssignableCapacity) {
      throw RangeError.range(
        requiredCapacity,
        0,
        maxAssignableCapacity,
        'requiredCapacity',
      );
    }
    return _plans.putIfAbsent(
      requiredCapacity,
      () => LodgingOptimizer.solve(
        town: town,
        requiredCapacity: requiredCapacity,
        existingCapacity: existingCapacity,
        currentOwnedHouseIds: ownedHouseIds,
        blockedHouseIds: blockedHouseIds,
      ),
    );
  }
}

final class _WorkerJob {
  const _WorkerJob({
    required this.productionNodeId,
    required this.candidateTownIndices,
  });

  final String productionNodeId;
  final List<int> candidateTownIndices;
}

final class _AssignmentState {
  _AssignmentState({
    required Iterable<int> counts,
    required Iterable<int> assignedTownIndices,
  }) : counts = List<int>.unmodifiable(counts),
       assignedTownIndices = List<int>.unmodifiable(assignedTownIndices);

  final List<int> counts;
  final List<int> assignedTownIndices;

  String get countKey => counts.join(',');

  _AssignmentState assign(int townIndex) {
    final nextCounts = counts.toList(growable: false);
    nextCounts[townIndex] += 1;
    return _AssignmentState(
      counts: nextCounts,
      assignedTownIndices: <int>[...assignedTownIndices, townIndex],
    );
  }
}

final class _AssignmentSearchResult {
  const _AssignmentSearchResult({
    required this.best,
    required this.didReachLimit,
    required this.retainedStateCount,
  });

  final _AssignmentState? best;
  final bool didReachLimit;
  final int retainedStateCount;
}

_AssignmentSearchResult _searchAssignments({
  required List<_WorkerJob> jobs,
  required List<_TownLodgingOptions> townOptions,
  required int stateLimit,
  required bool useBeam,
}) {
  var states = <String, _AssignmentState>{
    List<int>.filled(townOptions.length, 0).join(','): _AssignmentState(
      counts: List<int>.filled(townOptions.length, 0),
      assignedTownIndices: const <int>[],
    ),
  };
  var maximumRetainedStates = states.length;
  var didReachLimit = false;
  for (final job in jobs) {
    final next = <String, _AssignmentState>{};
    final orderedStates = states.values.toList(growable: false)
      ..sort(
        (left, right) => _compareAssignmentLexically(left, right, townOptions),
      );
    for (final state in orderedStates) {
      for (final townIndex in job.candidateTownIndices) {
        if (state.counts[townIndex] >=
            townOptions[townIndex].maxAssignableCapacity) {
          continue;
        }
        final candidate = state.assign(townIndex);
        final key = candidate.countKey;
        final incumbent = next[key];
        if (incumbent == null ||
            _compareAssignmentLexically(candidate, incumbent, townOptions) <
                0) {
          next[key] = candidate;
        }
        if (!useBeam && next.length > stateLimit) {
          return _AssignmentSearchResult(
            best: null,
            didReachLimit: true,
            retainedStateCount: maximumRetainedStates,
          );
        }
      }
    }
    if (useBeam && next.length > stateLimit) {
      didReachLimit = true;
      final ranked = next.values.toList(growable: false)
        ..sort(
          (left, right) => _compareAssignmentStates(left, right, townOptions),
        );
      states = <String, _AssignmentState>{
        for (final state in ranked.take(stateLimit)) state.countKey: state,
      };
    } else {
      states = next;
    }
    maximumRetainedStates = maximumRetainedStates > states.length
        ? maximumRetainedStates
        : states.length;
    if (states.isEmpty) {
      return _AssignmentSearchResult(
        best: null,
        didReachLimit: didReachLimit,
        retainedStateCount: maximumRetainedStates,
      );
    }
  }

  final ranked = states.values.toList(growable: false)
    ..sort((left, right) => _compareAssignmentStates(left, right, townOptions));
  return _AssignmentSearchResult(
    best: ranked.first,
    didReachLimit: didReachLimit,
    retainedStateCount: maximumRetainedStates,
  );
}

_AssignmentState? _findFeasibleAssignment({
  required List<_WorkerJob> jobs,
  required List<_TownLodgingOptions> townOptions,
}) {
  final slotTownIndices = <int>[];
  for (var townIndex = 0; townIndex < townOptions.length; townIndex += 1) {
    for (
      var slot = 0;
      slot < townOptions[townIndex].maxAssignableCapacity;
      slot += 1
    ) {
      slotTownIndices.add(townIndex);
    }
  }
  final slotsByTownIndex = <int, List<int>>{};
  for (var slotIndex = 0; slotIndex < slotTownIndices.length; slotIndex += 1) {
    (slotsByTownIndex[slotTownIndices[slotIndex]] ??= <int>[]).add(slotIndex);
  }
  final matchedJobBySlot = List<int>.filled(slotTownIndices.length, -1);

  bool augment(int jobIndex, Set<int> visitedSlots) {
    final rankedTownIndices =
        jobs[jobIndex].candidateTownIndices.toList(growable: false)
          ..sort((left, right) {
            final leftCost = townOptions[left]
                .planFor(townOptions[left].maxAssignableCapacity == 0 ? 0 : 1)
                .incrementalContributionPoints;
            final rightCost = townOptions[right]
                .planFor(townOptions[right].maxAssignableCapacity == 0 ? 0 : 1)
                .incrementalContributionPoints;
            if (leftCost != rightCost) return leftCost.compareTo(rightCost);
            return _compareIds(
              townOptions[left].town.townNodeId,
              townOptions[right].town.townNodeId,
            );
          });
    for (final townIndex in rankedTownIndices) {
      for (final slotIndex in slotsByTownIndex[townIndex] ?? const <int>[]) {
        if (!visitedSlots.add(slotIndex)) continue;
        final displacedJob = matchedJobBySlot[slotIndex];
        if (displacedJob == -1 || augment(displacedJob, visitedSlots)) {
          matchedJobBySlot[slotIndex] = jobIndex;
          return true;
        }
      }
    }
    return false;
  }

  for (var jobIndex = 0; jobIndex < jobs.length; jobIndex += 1) {
    if (!augment(jobIndex, <int>{})) return null;
  }
  final assignedTownIndices = List<int>.filled(jobs.length, -1);
  final counts = List<int>.filled(townOptions.length, 0);
  for (var slotIndex = 0; slotIndex < matchedJobBySlot.length; slotIndex += 1) {
    final jobIndex = matchedJobBySlot[slotIndex];
    if (jobIndex < 0) continue;
    final townIndex = slotTownIndices[slotIndex];
    assignedTownIndices[jobIndex] = townIndex;
    counts[townIndex] += 1;
  }
  if (assignedTownIndices.any((townIndex) => townIndex < 0)) return null;
  return _AssignmentState(
    counts: counts,
    assignedTownIndices: assignedTownIndices,
  );
}

_AssignmentState _improveAssignment(
  _AssignmentState seed, {
  required List<_WorkerJob> jobs,
  required List<_TownLodgingOptions> townOptions,
}) {
  var current = seed;
  var changed = true;
  while (changed) {
    changed = false;
    for (var jobIndex = 0; jobIndex < jobs.length; jobIndex += 1) {
      final currentTownIndex = current.assignedTownIndices[jobIndex];
      for (final nextTownIndex in jobs[jobIndex].candidateTownIndices) {
        if (nextTownIndex == currentTownIndex ||
            current.counts[nextTownIndex] >=
                townOptions[nextTownIndex].maxAssignableCapacity) {
          continue;
        }
        final nextCounts = current.counts.toList(growable: false);
        nextCounts[currentTownIndex] -= 1;
        nextCounts[nextTownIndex] += 1;
        final nextAssignments = current.assignedTownIndices.toList(
          growable: false,
        );
        nextAssignments[jobIndex] = nextTownIndex;
        final candidate = _AssignmentState(
          counts: nextCounts,
          assignedTownIndices: nextAssignments,
        );
        if (_compareAssignmentStates(candidate, current, townOptions) < 0) {
          current = candidate;
          changed = true;
          break;
        }
      }
      if (changed) break;
    }
  }
  return current;
}

int _compareAssignmentStates(
  _AssignmentState left,
  _AssignmentState right,
  List<_TownLodgingOptions> townOptions,
) {
  final leftCost = _totalIncrementalCp(left, townOptions);
  final rightCost = _totalIncrementalCp(right, townOptions);
  if (leftCost != rightCost) return leftCost.compareTo(rightCost);

  final leftCapacity = _totalAddedCapacity(left, townOptions);
  final rightCapacity = _totalAddedCapacity(right, townOptions);
  if (leftCapacity != rightCapacity) {
    return leftCapacity.compareTo(rightCapacity);
  }

  final leftHouseCount = _totalNewHouseCount(left, townOptions);
  final rightHouseCount = _totalNewHouseCount(right, townOptions);
  if (leftHouseCount != rightHouseCount) {
    return leftHouseCount.compareTo(rightHouseCount);
  }
  return _compareAssignmentLexically(left, right, townOptions);
}

int _compareAssignmentLexically(
  _AssignmentState left,
  _AssignmentState right,
  List<_TownLodgingOptions> townOptions,
) {
  final length =
      left.assignedTownIndices.length < right.assignedTownIndices.length
      ? left.assignedTownIndices.length
      : right.assignedTownIndices.length;
  for (var index = 0; index < length; index += 1) {
    final comparison = _compareIds(
      townOptions[left.assignedTownIndices[index]].town.townNodeId,
      townOptions[right.assignedTownIndices[index]].town.townNodeId,
    );
    if (comparison != 0) return comparison;
  }
  if (left.assignedTownIndices.length != right.assignedTownIndices.length) {
    return left.assignedTownIndices.length.compareTo(
      right.assignedTownIndices.length,
    );
  }
  return left.countKey.compareTo(right.countKey);
}

int _totalIncrementalCp(
  _AssignmentState state,
  List<_TownLodgingOptions> townOptions,
) {
  var total = 0;
  for (var index = 0; index < state.counts.length; index += 1) {
    total += townOptions[index]
        .planFor(state.counts[index])
        .incrementalContributionPoints;
  }
  return total;
}

int _totalAddedCapacity(
  _AssignmentState state,
  List<_TownLodgingOptions> townOptions,
) {
  var total = 0;
  for (var index = 0; index < state.counts.length; index += 1) {
    total += townOptions[index].planFor(state.counts[index]).addedCapacity;
  }
  return total;
}

int _totalNewHouseCount(
  _AssignmentState state,
  List<_TownLodgingOptions> townOptions,
) {
  var total = 0;
  for (var index = 0; index < state.counts.length; index += 1) {
    total += townOptions[index]
        .planFor(state.counts[index])
        .newlyRequiredHouseIds
        .length;
  }
  return total;
}

bool _hasErrors(Iterable<BdoLodgingNetworkDiagnostic> diagnostics) {
  return diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoLodgingNetworkDiagnosticSeverity.error,
  );
}

void _sortDiagnostics(List<BdoLodgingNetworkDiagnostic> diagnostics) {
  diagnostics.sort((left, right) {
    final severityComparison = left.severity.index.compareTo(
      right.severity.index,
    );
    if (severityComparison != 0) return severityComparison;
    final codeComparison = left.code.index.compareTo(right.code.index);
    if (codeComparison != 0) return codeComparison;
    final productionComparison = _compareIds(
      left.productionNodeId ?? '',
      right.productionNodeId ?? '',
    );
    if (productionComparison != 0) return productionComparison;
    final townComparison = _compareIds(
      left.townNodeId ?? '',
      right.townNodeId ?? '',
    );
    if (townComparison != 0) return townComparison;
    return _compareIds(left.houseId ?? '', right.houseId ?? '');
  });
}

Map<String, String> _sortedStringMap(Map<String, String> values) {
  final keys = values.keys.toList(growable: false)..sort(_compareIds);
  return <String, String>{for (final key in keys) key: values[key]!};
}

List<String> _sortedIds(Iterable<String> values) =>
    values.toSet().toList(growable: false)..sort(_compareIds);

int _compareIds(String left, String right) {
  final leftKey = int.tryParse(left.split(':').last);
  final rightKey = int.tryParse(right.split(':').last);
  if (leftKey != null && rightKey != null && leftKey != rightKey) {
    return leftKey.compareTo(rightKey);
  }
  return left.compareTo(right);
}
