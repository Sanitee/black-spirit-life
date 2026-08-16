import 'dart:collection';

import '../model/resource_map_data.dart';
import 'production_node_path_cost.dart';

/// The deliberately limited optimization claim made by a raw-sale plan.
enum BdoRawSaleNetworkPlanQuality {
  deterministicValuePerAddedContributionPointHeuristic,
}

extension BdoRawSaleNetworkPlanQualityDescription
    on BdoRawSaleNetworkPlanQuality {
  String get label => switch (this) {
    BdoRawSaleNetworkPlanQuality
        .deterministicValuePerAddedContributionPointHeuristic =>
      'Deterministic signal-per-added-CP heuristic',
  };

  String get disclosure => switch (this) {
    BdoRawSaleNetworkPlanQuality
        .deterministicValuePerAddedContributionPointHeuristic =>
      'Not globally optimal. The planner reuses shared connection paths and '
          'orders supplied current or marginal signals by added CP; the '
          'caller must state whether those signals are price comparisons or '
          'estimated income.',
  };
}

enum BdoRawSaleNetworkDiagnosticSeverity { info, warning, error }

enum BdoRawSaleNetworkDiagnosticCode {
  invalidContributionPointBudget,
  invalidReservedContributionPoints,
  invalidMaximumProductionNodeCount,
  baselineExceedsBudget,
  noUsablePositiveValueSignals,
  pathServiceWarning,
  pathServiceError,
}

class BdoRawSaleNetworkDiagnostic {
  const BdoRawSaleNetworkDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.nodeIds = const <String>[],
    this.pathCode,
  });

  final BdoRawSaleNetworkDiagnosticCode code;
  final BdoRawSaleNetworkDiagnosticSeverity severity;
  final String message;
  final List<String> nodeIds;
  final BdoProductionNodePathDiagnosticCode? pathCode;
}

enum BdoRawSaleNetworkExclusionReason {
  invalidValueSignal,
  unknownNode,
  nodeIsNotProductionNode,
  unreachableFromAllowedRoots,
  invalidNetworkConfiguration,
  exceedsRemainingContributionPointBudget,
  portfolioNodeLimitReached,
  noPositiveMarginalValueSignal,
}

class BdoRawSaleNetworkExclusion {
  const BdoRawSaleNetworkExclusion({
    required this.nodeId,
    required this.reason,
    required this.message,
    this.currentSaleValueSignal,
    this.requiredAddedContributionPoints,
  });

  final String nodeId;
  final BdoRawSaleNetworkExclusionReason reason;
  final String message;
  final double? currentSaleValueSignal;
  final int? requiredAddedContributionPoints;
}

/// One production node accepted by the portfolio heuristic.
class BdoRawSaleNetworkSelection {
  const BdoRawSaleNetworkSelection({
    required this.productionNodeId,
    required this.currentSaleValueSignal,
    required this.addedContributionPointsAtSelection,
    required this.path,
  });

  final String productionNodeId;
  final double currentSaleValueSignal;
  final int addedContributionPointsAtSelection;

  /// The complete root-to-production-node path at selection time.
  final BdoProductionNodePath path;
}

/// One physical, undirected connection included in the returned network.
class BdoRawSaleNetworkEdge {
  factory BdoRawSaleNetworkEdge(String firstNodeId, String secondNodeId) {
    return _compareIds(firstNodeId, secondNodeId) <= 0
        ? BdoRawSaleNetworkEdge._(firstNodeId, secondNodeId)
        : BdoRawSaleNetworkEdge._(secondNodeId, firstNodeId);
  }

  const BdoRawSaleNetworkEdge._(this.firstNodeId, this.secondNodeId);

  final String firstNodeId;
  final String secondNodeId;

  String get key => '$firstNodeId\u0000$secondNodeId';

  @override
  bool operator ==(Object other) =>
      other is BdoRawSaleNetworkEdge &&
      other.firstNodeId == firstNodeId &&
      other.secondNodeId == secondNodeId;

  @override
  int get hashCode => Object.hash(firstNodeId, secondNodeId);
}

class BdoRawSaleNetworkPlanRequest {
  BdoRawSaleNetworkPlanRequest({
    required this.totalContributionPointBudget,
    required Set<String> currentNodeIds,
    required Map<String, double> currentSaleValueSignalsByProductionNodeId,
    Set<String>? allowedRootNodeIds,
    this.marginalValueSignalProvider,
    this.reservedContributionPoints = 0,
    this.maximumProductionNodeCount,
  }) : currentNodeIds = Set<String>.unmodifiable(currentNodeIds),
       currentSaleValueSignalsByProductionNodeId =
           Map<String, double>.unmodifiable(
             currentSaleValueSignalsByProductionNodeId,
           ),
       allowedRootNodeIds = allowedRootNodeIds == null
           ? null
           : Set<String>.unmodifiable(allowedRootNodeIds);

  /// Total CP available, including the preserved saved-node baseline.
  final int totalContributionPointBudget;

  /// CP held back for costs outside the node graph, such as worker lodging.
  ///
  /// Candidate paths are accepted only while node CP plus this reserve stays
  /// within [totalContributionPointBudget].
  final int reservedContributionPoints;

  /// Optional deterministic cap used by a higher-level portfolio repair.
  ///
  /// Null leaves the candidate count unconstrained. Zero returns only the
  /// preserved saved-node baseline.
  final int? maximumProductionNodeCount;

  /// Saved node IDs are never removed by this planner.
  final Set<String> currentNodeIds;

  /// Optional zero-CP city/town roots accepted by the path service.
  final Set<String>? allowedRootNodeIds;

  /// Positive, finite current raw-sale signals keyed by production-node ID.
  ///
  /// The planner does not interpret these values as yield, profit, or income
  /// over time.
  final Map<String, double> currentSaleValueSignalsByProductionNodeId;

  /// Optional shared-portfolio marginal signal recalculated after every pick.
  ///
  /// The callback receives a candidate ID and the production nodes already
  /// selected. It must return the additional current value created by adding
  /// that candidate. A non-positive or non-finite value makes the candidate
  /// ineligible at that stage. The static signal map still defines the initial
  /// candidate set and is used when this callback is absent.
  final BdoRawSaleNetworkMarginalValueSignalProvider?
  marginalValueSignalProvider;
}

typedef BdoRawSaleNetworkMarginalValueSignalProvider =
    double Function(
      String productionNodeId,
      Set<String> selectedProductionNodeIds,
    );

/// Returns true when an in-progress asynchronous plan is no longer wanted.
///
/// A UI can close over its latest request generation and return true after a
/// newer request supersedes this one.
typedef BdoRawSaleNetworkCancellationPredicate = bool Function();

/// Cooperative cancellation from [BdoRawSaleNetworkPlanner.planAsync].
final class BdoRawSaleNetworkPlanningCancelled implements Exception {
  const BdoRawSaleNetworkPlanningCancelled();

  @override
  String toString() => 'Raw-sale network planning was cancelled.';
}

class BdoRawSaleNetworkPlanResult {
  BdoRawSaleNetworkPlanResult({
    required this.quality,
    required this.totalContributionPointBudget,
    required this.currentNodeIds,
    required this.addedNodeIds,
    required this.networkNodeIds,
    required this.routeNodeIds,
    required this.selections,
    required this.routeEdges,
    required this.baselineContributionPoints,
    required this.addedContributionPoints,
    required this.totalContributionPoints,
    required this.currentSaleValueSignal,
    required this.exclusions,
    required this.diagnostics,
    this.reservedContributionPoints = 0,
  });

  final BdoRawSaleNetworkPlanQuality quality;
  final int totalContributionPointBudget;
  final int reservedContributionPoints;

  /// Requested saved IDs, including IDs no longer known by the dataset.
  final List<String> currentNodeIds;

  /// Newly activated, non-root node IDs from every selected path.
  final List<String> addedNodeIds;

  /// The exact set union of [currentNodeIds] and [addedNodeIds].
  final List<String> networkNodeIds;

  /// Every endpoint used by [routeEdges], including implicit zero-CP roots.
  final List<String> routeNodeIds;

  /// Selection order is the deterministic greedy order.
  final List<BdoRawSaleNetworkSelection> selections;

  /// Baseline connections plus the complete path of every selection.
  final List<BdoRawSaleNetworkEdge> routeEdges;

  final int baselineContributionPoints;
  final int addedContributionPoints;
  final int totalContributionPoints;

  /// Sum of the selected input signals, without a yield or time multiplier.
  final double currentSaleValueSignal;

  final List<BdoRawSaleNetworkExclusion> exclusions;
  final List<BdoRawSaleNetworkDiagnostic> diagnostics;

  String get qualityLabel => quality.label;

  String get qualityDisclosure => quality.disclosure;

  List<String> get selectedProductionNodeIds => List<String>.unmodifiable(
    selections.map((selection) => selection.productionNodeId),
  );

  int get remainingContributionPoints {
    final remaining =
        totalContributionPointBudget -
        totalContributionPoints -
        reservedContributionPoints;
    return remaining > 0 ? remaining : 0;
  }

  int get combinedReservedContributionPoints =>
      totalContributionPoints + reservedContributionPoints;

  bool get baselineExceedsBudget =>
      baselineContributionPoints > totalContributionPointBudget;

  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoRawSaleNetworkDiagnosticSeverity.error,
  );
}

/// Builds a budgeted portfolio from current raw-sale value signals.
///
/// After every positive-CP selection the service recalculates exact cheapest
/// incremental paths. This lets later candidates reuse the connection trunks
/// selected earlier. Candidate choice remains a deterministic greedy
/// heuristic; it is intentionally not presented as a globally optimal
/// portfolio.
class BdoRawSaleNetworkPlanner {
  const BdoRawSaleNetworkPlanner();

  static const _pathCostService = BdoProductionNodePathCostService();

  BdoRawSaleNetworkPlanResult plan({
    required BdoResourceMapDataset data,
    required BdoRawSaleNetworkPlanRequest request,
  }) {
    final output = _RawSaleNetworkPlanOutput();
    for (final _ in _execute(
      data: data,
      request: request,
      output: output,
      yieldEveryCandidates: 1 << 30,
    )) {
      // The synchronous API deliberately consumes checkpoints immediately.
    }
    return output.value;
  }

  /// Runs the same deterministic greedy plan while cooperatively yielding.
  ///
  /// Expensive path traversals remain synchronous work units, but the planner
  /// yields before starting, after path preparation, between selection rounds,
  /// and after each [yieldEveryCandidates] candidate evaluations. This keeps a
  /// Flutter event loop responsive and gives [shouldCancel] regular chances to
  /// supersede stale work.
  ///
  /// Cancellation throws [BdoRawSaleNetworkPlanningCancelled]. No partial
  /// result is returned or applied.
  Future<BdoRawSaleNetworkPlanResult> planAsync({
    required BdoResourceMapDataset data,
    required BdoRawSaleNetworkPlanRequest request,
    BdoRawSaleNetworkCancellationPredicate? shouldCancel,
    int yieldEveryCandidates = 32,
  }) async {
    if (yieldEveryCandidates <= 0) {
      throw ArgumentError.value(
        yieldEveryCandidates,
        'yieldEveryCandidates',
        'must be greater than zero',
      );
    }

    void throwIfCancelled() {
      if (shouldCancel?.call() ?? false) {
        throw const BdoRawSaleNetworkPlanningCancelled();
      }
    }

    throwIfCancelled();
    final output = _RawSaleNetworkPlanOutput();
    final checkpoints = _execute(
      data: data,
      request: request,
      output: output,
      yieldEveryCandidates: yieldEveryCandidates,
    ).iterator;
    while (true) {
      throwIfCancelled();
      final hasCheckpoint = checkpoints.moveNext();
      throwIfCancelled();
      if (!hasCheckpoint) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
      throwIfCancelled();
    }
    return output.value;
  }

  Iterable<_RawSaleNetworkPlanningCheckpoint> _execute({
    required BdoResourceMapDataset data,
    required BdoRawSaleNetworkPlanRequest request,
    required _RawSaleNetworkPlanOutput output,
    required int yieldEveryCandidates,
  }) sync* {
    // This first checkpoint lets the asynchronous API paint its loading state
    // or cancel before any graph preparation begins.
    yield _RawSaleNetworkPlanningCheckpoint.starting;

    final exclusions = <BdoRawSaleNetworkExclusion>[];
    final diagnostics = <BdoRawSaleNetworkDiagnostic>[];
    final diagnosticKeys = <String>{};
    final candidates = SplayTreeMap<String, double>(_compareIds);
    final signalEntries =
        request.currentSaleValueSignalsByProductionNodeId.entries.toList()
          ..sort((left, right) => _compareIds(left.key, right.key));

    for (final entry in signalEntries) {
      final signal = entry.value;
      if (!signal.isFinite || signal <= 0) {
        exclusions.add(
          BdoRawSaleNetworkExclusion(
            nodeId: entry.key,
            reason: BdoRawSaleNetworkExclusionReason.invalidValueSignal,
            message:
                'Current raw-sale value signals must be positive and finite.',
            currentSaleValueSignal: signal,
          ),
        );
        continue;
      }
      final node = data.workerNodesById[entry.key];
      if (node == null) {
        exclusions.add(
          BdoRawSaleNetworkExclusion(
            nodeId: entry.key,
            reason: BdoRawSaleNetworkExclusionReason.unknownNode,
            message: 'The signaled node is absent from this map dataset.',
            currentSaleValueSignal: signal,
          ),
        );
        continue;
      }
      if (!node.isProductionNode) {
        exclusions.add(
          BdoRawSaleNetworkExclusion(
            nodeId: entry.key,
            reason: BdoRawSaleNetworkExclusionReason.nodeIsNotProductionNode,
            message: 'The signaled node is not a production node.',
            currentSaleValueSignal: signal,
          ),
        );
        continue;
      }
      candidates[entry.key] = signal;
    }

    if (candidates.isEmpty) {
      diagnostics.add(
        const BdoRawSaleNetworkDiagnostic(
          code: BdoRawSaleNetworkDiagnosticCode.noUsablePositiveValueSignals,
          severity: BdoRawSaleNetworkDiagnosticSeverity.info,
          message: 'No usable positive production-node value signal exists.',
        ),
      );
    }

    final currentIds = request.currentNodeIds.toSet();
    final knownCurrentIds = currentIds
        .where(data.workerNodesById.containsKey)
        .toSet();
    final baselineContributionPoints = knownCurrentIds.fold<int>(0, (
      total,
      nodeId,
    ) {
      final cp = data.workerNodesById[nodeId]!.contributionPoints;
      return total + (cp > 0 ? cp : 0);
    });
    final reservedContributionPoints = request.reservedContributionPoints;
    final maximumProductionNodeCount = request.maximumProductionNodeCount;
    final networkContributionPointBudget =
        request.totalContributionPointBudget - reservedContributionPoints;

    if (request.totalContributionPointBudget < 0) {
      diagnostics.add(
        const BdoRawSaleNetworkDiagnostic(
          code: BdoRawSaleNetworkDiagnosticCode.invalidContributionPointBudget,
          severity: BdoRawSaleNetworkDiagnosticSeverity.error,
          message: 'The total contribution-point budget must be non-negative.',
        ),
      );
    } else if (reservedContributionPoints < 0 ||
        reservedContributionPoints > request.totalContributionPointBudget) {
      diagnostics.add(
        const BdoRawSaleNetworkDiagnostic(
          code:
              BdoRawSaleNetworkDiagnosticCode.invalidReservedContributionPoints,
          severity: BdoRawSaleNetworkDiagnosticSeverity.error,
          message:
              'Reserved contribution points must be between zero and the '
              'total contribution-point budget.',
        ),
      );
    } else if (maximumProductionNodeCount != null &&
        maximumProductionNodeCount < 0) {
      diagnostics.add(
        const BdoRawSaleNetworkDiagnostic(
          code:
              BdoRawSaleNetworkDiagnosticCode.invalidMaximumProductionNodeCount,
          severity: BdoRawSaleNetworkDiagnosticSeverity.error,
          message: 'The production-node limit must not be negative.',
        ),
      );
    } else if (baselineContributionPoints > networkContributionPointBudget) {
      diagnostics.add(
        BdoRawSaleNetworkDiagnostic(
          code: BdoRawSaleNetworkDiagnosticCode.baselineExceedsBudget,
          severity: BdoRawSaleNetworkDiagnosticSeverity.warning,
          message:
              'The preserved saved-node baseline uses '
              '$baselineContributionPoints CP, above the '
              '$networkContributionPointBudget CP node budget after reserving '
              '$reservedContributionPoints CP. Only '
              'zero-added-CP candidates can be selected.',
        ),
      );
    }

    final activeIds = currentIds.toSet();
    final addedIds = <String>{};
    final selections = <BdoRawSaleNetworkSelection>[];
    var addedContributionPoints = 0;
    var currentSaleValueSignal = 0.0;
    Map<String, BdoProductionNodePathResult>? latestPathResults;

    if (candidates.isNotEmpty && request.totalContributionPointBudget >= 0) {
      latestPathResults = _pathCostService.calculateAll(
        data: data,
        currentNodeIds: activeIds,
        allowedRootNodeIds: request.allowedRootNodeIds,
      );
    }
    final initialPathResult = latestPathResults?.values.firstOrNull;
    final validationResult =
        initialPathResult ??
        _pathCostService.calculate(
          data: data,
          request: BdoProductionNodePathRequest(
            targetNodeId: _unusedValidationTargetId(data),
            currentNodeIds: activeIds,
            allowedRootNodeIds: request.allowedRootNodeIds,
          ),
        );
    _collectPathDiagnostics(
      validationResult.diagnostics.where(_isPathContextDiagnostic),
      diagnostics: diagnostics,
      diagnosticKeys: diagnosticKeys,
    );
    yield _RawSaleNetworkPlanningCheckpoint.pathsPrepared;

    if (request.totalContributionPointBudget >= 0 &&
        reservedContributionPoints >= 0 &&
        reservedContributionPoints <= request.totalContributionPointBudget &&
        (maximumProductionNodeCount == null ||
            maximumProductionNodeCount >= 0)) {
      while (candidates.isNotEmpty &&
          (maximumProductionNodeCount == null ||
              selections.length < maximumProductionNodeCount)) {
        if (latestPathResults == null) {
          latestPathResults = _pathCostService.calculateAll(
            data: data,
            currentNodeIds: activeIds,
            allowedRootNodeIds: request.allowedRootNodeIds,
          );
          yield _RawSaleNetworkPlanningCheckpoint.pathsPrepared;
        }
        final evaluated = <_EvaluatedCandidate>[];
        final selectedProductionNodeIds = Set<String>.unmodifiable(
          selections.map((selection) => selection.productionNodeId),
        );
        var candidatesSinceYield = 0;
        for (final entry in candidates.entries) {
          if (candidatesSinceYield >= yieldEveryCandidates) {
            candidatesSinceYield = 0;
            yield _RawSaleNetworkPlanningCheckpoint.candidateBatch;
          }
          candidatesSinceYield += 1;
          final pathResult = latestPathResults[entry.key];
          if (pathResult == null) {
            continue;
          }
          _collectPathDiagnostics(
            pathResult.diagnostics,
            diagnostics: diagnostics,
            diagnosticKeys: diagnosticKeys,
          );
          final path = pathResult.minimumIncrementalPath;
          if (path != null && !pathResult.hasErrors) {
            final currentSignal =
                request.marginalValueSignalProvider?.call(
                  entry.key,
                  selectedProductionNodeIds,
                ) ??
                entry.value;
            if (!currentSignal.isFinite || currentSignal <= 0) {
              continue;
            }
            evaluated.add(
              _EvaluatedCandidate(
                nodeId: entry.key,
                currentSaleValueSignal: currentSignal,
                path: path,
              ),
            );
          }
        }

        final zeroAddedCandidates =
            evaluated
                .where(
                  (candidate) =>
                      candidate.path.incrementalContributionPoints == 0,
                )
                .toList()
              ..sort(_compareEvaluatedCandidates);
        if (zeroAddedCandidates.isNotEmpty) {
          final selected = zeroAddedCandidates.first;
          _selectCandidate(
            selected,
            candidates: candidates,
            currentIds: currentIds,
            activeIds: activeIds,
            addedIds: addedIds,
            selections: selections,
          );
          currentSaleValueSignal += selected.currentSaleValueSignal;
          // A zero-CP path can still activate zero-CP vertices. Recalculate
          // before the next selection so its retained/connect metadata and
          // deterministic path ties reflect the actual active network.
          latestPathResults = null;
          yield _RawSaleNetworkPlanningCheckpoint.roundComplete;
          continue;
        }

        final totalContributionPoints =
            baselineContributionPoints + addedContributionPoints;
        final budgetRemaining =
            networkContributionPointBudget - totalContributionPoints;
        final affordable =
            evaluated
                .where(
                  (candidate) =>
                      candidate.path.incrementalContributionPoints > 0 &&
                      candidate.path.incrementalContributionPoints <=
                          budgetRemaining,
                )
                .toList()
              ..sort(_compareEvaluatedCandidates);
        if (affordable.isEmpty) {
          yield _RawSaleNetworkPlanningCheckpoint.roundComplete;
          break;
        }

        final selected = affordable.first;
        _selectCandidate(
          selected,
          candidates: candidates,
          currentIds: currentIds,
          activeIds: activeIds,
          addedIds: addedIds,
          selections: selections,
        );
        addedContributionPoints += selected.path.incrementalContributionPoints;
        currentSaleValueSignal += selected.currentSaleValueSignal;
        latestPathResults = null;
        yield _RawSaleNetworkPlanningCheckpoint.roundComplete;
      }
    }

    if (candidates.isNotEmpty) {
      if (request.totalContributionPointBudget >= 0) {
        if (latestPathResults == null) {
          latestPathResults = _pathCostService.calculateAll(
            data: data,
            currentNodeIds: activeIds,
            allowedRootNodeIds: request.allowedRootNodeIds,
          );
          yield _RawSaleNetworkPlanningCheckpoint.pathsPrepared;
        }
      }
      final remainingBudget =
          networkContributionPointBudget -
          baselineContributionPoints -
          addedContributionPoints;
      var exclusionsSinceYield = 0;
      for (final entry in candidates.entries) {
        if (exclusionsSinceYield >= yieldEveryCandidates) {
          exclusionsSinceYield = 0;
          yield _RawSaleNetworkPlanningCheckpoint.candidateBatch;
        }
        exclusionsSinceYield += 1;
        if (request.totalContributionPointBudget < 0) {
          exclusions.add(
            BdoRawSaleNetworkExclusion(
              nodeId: entry.key,
              reason:
                  BdoRawSaleNetworkExclusionReason.invalidNetworkConfiguration,
              message:
                  'No portfolio was built because the CP budget is invalid.',
              currentSaleValueSignal: entry.value,
            ),
          );
          continue;
        }
        if (reservedContributionPoints < 0 ||
            reservedContributionPoints > request.totalContributionPointBudget ||
            (maximumProductionNodeCount != null &&
                maximumProductionNodeCount < 0)) {
          exclusions.add(
            BdoRawSaleNetworkExclusion(
              nodeId: entry.key,
              reason:
                  BdoRawSaleNetworkExclusionReason.invalidNetworkConfiguration,
              message:
                  'No portfolio was built because its budget constraints are '
                  'invalid.',
              currentSaleValueSignal: entry.value,
            ),
          );
          continue;
        }
        if (maximumProductionNodeCount != null &&
            selections.length >= maximumProductionNodeCount) {
          exclusions.add(
            BdoRawSaleNetworkExclusion(
              nodeId: entry.key,
              reason:
                  BdoRawSaleNetworkExclusionReason.portfolioNodeLimitReached,
              message:
                  'This candidate was left out by the repaired worker-count '
                  'limit.',
              currentSaleValueSignal: entry.value,
            ),
          );
          continue;
        }
        final pathResult = latestPathResults?[entry.key];
        if (pathResult == null) {
          exclusions.add(
            BdoRawSaleNetworkExclusion(
              nodeId: entry.key,
              reason:
                  BdoRawSaleNetworkExclusionReason.invalidNetworkConfiguration,
              message: 'No path result exists for this production node.',
              currentSaleValueSignal: entry.value,
            ),
          );
          continue;
        }
        _collectPathDiagnostics(
          pathResult.diagnostics,
          diagnostics: diagnostics,
          diagnosticKeys: diagnosticKeys,
        );
        final path = pathResult.minimumIncrementalPath;
        if (path == null || pathResult.hasErrors) {
          final unreachable = pathResult.diagnostics.any(
            (diagnostic) =>
                diagnostic.code ==
                BdoProductionNodePathDiagnosticCode.unreachableTargetNode,
          );
          exclusions.add(
            BdoRawSaleNetworkExclusion(
              nodeId: entry.key,
              reason: unreachable
                  ? BdoRawSaleNetworkExclusionReason.unreachableFromAllowedRoots
                  : BdoRawSaleNetworkExclusionReason
                        .invalidNetworkConfiguration,
              message: unreachable
                  ? 'No complete path from an allowed root reaches this node.'
                  : 'Network validation prevented a complete path.',
              currentSaleValueSignal: entry.value,
            ),
          );
          continue;
        }
        final marginalSignal =
            request.marginalValueSignalProvider?.call(
              entry.key,
              Set<String>.unmodifiable(
                selections.map((selection) => selection.productionNodeId),
              ),
            ) ??
            entry.value;
        if (!marginalSignal.isFinite || marginalSignal <= 0) {
          exclusions.add(
            BdoRawSaleNetworkExclusion(
              nodeId: entry.key,
              reason: BdoRawSaleNetworkExclusionReason
                  .noPositiveMarginalValueSignal,
              message:
                  'Adding this node does not create a positive finite '
                  'portfolio-value increase after the selected nodes.',
              currentSaleValueSignal: marginalSignal,
            ),
          );
          continue;
        }
        exclusions.add(
          BdoRawSaleNetworkExclusion(
            nodeId: entry.key,
            reason: BdoRawSaleNetworkExclusionReason
                .exceedsRemainingContributionPointBudget,
            message:
                'The cheapest current path needs '
                '${path.incrementalContributionPoints} added CP; '
                '${remainingBudget > 0 ? remainingBudget : 0} remain.',
            currentSaleValueSignal: entry.value,
            requiredAddedContributionPoints: path.incrementalContributionPoints,
          ),
        );
      }
    }

    exclusions.sort(_compareExclusions);
    final routeRootNodeIds = _resolveValidRootNodeIds(
      data,
      request.allowedRootNodeIds,
    );
    final routeEdges = _buildRouteEdges(
      data: data,
      knownCurrentIds: knownCurrentIds,
      rootNodeIds: routeRootNodeIds,
      selections: selections,
    );
    final routeNodeIds = <String>{
      for (final edge in routeEdges) ...<String>[
        edge.firstNodeId,
        edge.secondNodeId,
      ],
    };
    final sortedCurrentIds = _sortIds(currentIds);
    final sortedAddedIds = _sortIds(addedIds);
    final networkIds = _sortIds(<String>{...currentIds, ...addedIds});
    final finalTotalContributionPoints =
        baselineContributionPoints + addedContributionPoints;

    yield _RawSaleNetworkPlanningCheckpoint.finalizing;
    output.value = BdoRawSaleNetworkPlanResult(
      quality: BdoRawSaleNetworkPlanQuality
          .deterministicValuePerAddedContributionPointHeuristic,
      totalContributionPointBudget: request.totalContributionPointBudget,
      currentNodeIds: sortedCurrentIds,
      addedNodeIds: sortedAddedIds,
      networkNodeIds: networkIds,
      routeNodeIds: _sortIds(routeNodeIds),
      selections: List<BdoRawSaleNetworkSelection>.unmodifiable(selections),
      routeEdges: routeEdges,
      baselineContributionPoints: baselineContributionPoints,
      addedContributionPoints: addedContributionPoints,
      totalContributionPoints: finalTotalContributionPoints,
      currentSaleValueSignal: currentSaleValueSignal,
      exclusions: List<BdoRawSaleNetworkExclusion>.unmodifiable(exclusions),
      diagnostics: List<BdoRawSaleNetworkDiagnostic>.unmodifiable(diagnostics),
      reservedContributionPoints: reservedContributionPoints,
    );
    yield _RawSaleNetworkPlanningCheckpoint.complete;
  }
}

enum _RawSaleNetworkPlanningCheckpoint {
  starting,
  pathsPrepared,
  candidateBatch,
  roundComplete,
  finalizing,
  complete,
}

final class _RawSaleNetworkPlanOutput {
  late final BdoRawSaleNetworkPlanResult value;
}

class _EvaluatedCandidate {
  const _EvaluatedCandidate({
    required this.nodeId,
    required this.currentSaleValueSignal,
    required this.path,
  });

  final String nodeId;
  final double currentSaleValueSignal;
  final BdoProductionNodePath path;
}

void _selectCandidate(
  _EvaluatedCandidate candidate, {
  required Map<String, double> candidates,
  required Set<String> currentIds,
  required Set<String> activeIds,
  required Set<String> addedIds,
  required List<BdoRawSaleNetworkSelection> selections,
}) {
  selections.add(
    BdoRawSaleNetworkSelection(
      productionNodeId: candidate.nodeId,
      currentSaleValueSignal: candidate.currentSaleValueSignal,
      addedContributionPointsAtSelection:
          candidate.path.incrementalContributionPoints,
      path: candidate.path,
    ),
  );
  candidates.remove(candidate.nodeId);
  for (final nodeId in candidate.path.connectNodeIds) {
    activeIds.add(nodeId);
    if (!currentIds.contains(nodeId)) {
      addedIds.add(nodeId);
    }
  }
}

void _collectPathDiagnostics(
  Iterable<BdoProductionNodePathDiagnostic> pathDiagnostics, {
  required List<BdoRawSaleNetworkDiagnostic> diagnostics,
  required Set<String> diagnosticKeys,
}) {
  for (final diagnostic in pathDiagnostics) {
    final nodeIds = _sortIds(diagnostic.nodeIds);
    final key =
        '${diagnostic.code.name}\u0000${diagnostic.severity.name}\u0000'
        '${nodeIds.join('\u0000')}\u0000${diagnostic.message}';
    if (!diagnosticKeys.add(key)) {
      continue;
    }
    final isError =
        diagnostic.severity == BdoProductionNodePathDiagnosticSeverity.error;
    diagnostics.add(
      BdoRawSaleNetworkDiagnostic(
        code: isError
            ? BdoRawSaleNetworkDiagnosticCode.pathServiceError
            : BdoRawSaleNetworkDiagnosticCode.pathServiceWarning,
        severity: isError
            ? BdoRawSaleNetworkDiagnosticSeverity.error
            : BdoRawSaleNetworkDiagnosticSeverity.warning,
        message: diagnostic.message,
        nodeIds: nodeIds,
        pathCode: diagnostic.code,
      ),
    );
  }
}

List<BdoRawSaleNetworkEdge> _buildRouteEdges({
  required BdoResourceMapDataset data,
  required Set<String> knownCurrentIds,
  required Set<String> rootNodeIds,
  required List<BdoRawSaleNetworkSelection> selections,
}) {
  final byKey = SplayTreeMap<String, BdoRawSaleNetworkEdge>();
  final baselineNodeIds = <String>{...knownCurrentIds, ...rootNodeIds};
  for (final nodeId in baselineNodeIds) {
    final node = data.workerNodesById[nodeId]!;
    for (final linkId in node.linkIds) {
      if (!baselineNodeIds.contains(linkId) ||
          rootNodeIds.contains(nodeId) && rootNodeIds.contains(linkId)) {
        continue;
      }
      final edge = BdoRawSaleNetworkEdge(nodeId, linkId);
      byKey[edge.key] = edge;
    }
  }
  for (final selection in selections) {
    for (final pathEdge in selection.path.edges) {
      final edge = BdoRawSaleNetworkEdge(
        pathEdge.fromNodeId,
        pathEdge.toNodeId,
      );
      byKey[edge.key] = edge;
    }
  }
  return List<BdoRawSaleNetworkEdge>.unmodifiable(byKey.values);
}

Set<String> _resolveValidRootNodeIds(
  BdoResourceMapDataset data,
  Set<String>? allowedRootNodeIds,
) {
  if (allowedRootNodeIds == null) {
    return <String>{
      for (final node in data.workerNodes)
        if (_isValidRootNode(node)) node.id,
    };
  }
  return <String>{
    for (final nodeId in allowedRootNodeIds)
      if (data.workerNodesById[nodeId] case final node?)
        if (_isValidRootNode(node)) nodeId,
  };
}

bool _isValidRootNode(BdoWorkerNode node) =>
    node.contributionPoints == 0 &&
    (node.nodeType == 'City' || node.nodeType == 'Town');

String _unusedValidationTargetId(BdoResourceMapDataset data) {
  var nodeId = '\u0000raw-sale-network-validation';
  while (data.workerNodesById.containsKey(nodeId)) {
    nodeId = '$nodeId\u0000';
  }
  return nodeId;
}

bool _isPathContextDiagnostic(BdoProductionNodePathDiagnostic diagnostic) {
  return switch (diagnostic.code) {
    BdoProductionNodePathDiagnosticCode.unknownTargetNode ||
    BdoProductionNodePathDiagnosticCode.targetIsNotProductionNode ||
    BdoProductionNodePathDiagnosticCode.unreachableTargetNode => false,
    _ => true,
  };
}

int _compareEvaluatedCandidates(
  _EvaluatedCandidate left,
  _EvaluatedCandidate right,
) {
  final leftCost = left.path.incrementalContributionPoints;
  final rightCost = right.path.incrementalContributionPoints;
  if (leftCost == 0 || rightCost == 0) {
    if (leftCost == 0 && rightCost != 0) {
      return -1;
    }
    if (rightCost == 0 && leftCost != 0) {
      return 1;
    }
  } else {
    final leftRatio = left.currentSaleValueSignal / leftCost;
    final rightRatio = right.currentSaleValueSignal / rightCost;
    final ratioComparison = rightRatio.compareTo(leftRatio);
    if (ratioComparison != 0) {
      return ratioComparison;
    }
  }

  final valueComparison = right.currentSaleValueSignal.compareTo(
    left.currentSaleValueSignal,
  );
  if (valueComparison != 0) {
    return valueComparison;
  }
  final costComparison = leftCost.compareTo(rightCost);
  if (costComparison != 0) {
    return costComparison;
  }
  return _compareIds(left.nodeId, right.nodeId);
}

int _compareExclusions(
  BdoRawSaleNetworkExclusion left,
  BdoRawSaleNetworkExclusion right,
) {
  final idComparison = _compareIds(left.nodeId, right.nodeId);
  if (idComparison != 0) {
    return idComparison;
  }
  return left.reason.index.compareTo(right.reason.index);
}

List<String> _sortIds(Iterable<String> ids) {
  final result = ids.toSet().toList()..sort(_compareIds);
  return List<String>.unmodifiable(result);
}

int _compareIds(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final numberComparison = leftNumber.compareTo(rightNumber);
    if (numberComparison != 0) {
      return numberComparison;
    }
  }
  return left.compareTo(right);
}
