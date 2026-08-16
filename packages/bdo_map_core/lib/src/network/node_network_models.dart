/// Quality guarantee attached to a returned worker-network plan.
///
/// [BdoNodeNetworkOptimizer] keeps globally exact solving for tractable
/// requests and uses a deterministic, locally improved network heuristic for
/// large one-node-per-resource portfolios.
enum BdoNodeNetworkOptimizationMode {
  /// Every feasible production-node combination was evaluated and every
  /// connection was solved as a minimum node-weighted Steiner forest.
  exact,

  /// The request exceeded the exponential exact-search boundary, so a
  /// deterministic greedy network followed by terminal-by-terminal local
  /// improvement was used.
  ///
  /// The returned route is complete and connected, but global minimum CP is
  /// not guaranteed.
  scalable,
}

/// Severity of a network-planning diagnostic.
enum BdoNodeNetworkDiagnosticSeverity { info, warning, error }

/// Stable diagnostic identifiers suitable for UI-specific presentation.
enum BdoNodeNetworkDiagnosticCode {
  invalidContributionPointBudget,
  invalidRequestedCount,
  unknownResource,
  ambiguousResource,
  unknownRootNode,
  invalidRootNode,
  noRootNodes,
  unknownCurrentNode,
  invalidNodeContributionPoints,
  unsafeNodeContributionPoints,
  insufficientProductionNodes,
  unreachableProductionNodes,
  exactSearchLimitExceeded,
  scalableOptimizationUsed,
  contributionPointBudgetExceeded,
}

/// A user-actionable issue discovered while resolving or optimizing a request.
class BdoNodeNetworkDiagnostic {
  const BdoNodeNetworkDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.query,
    this.resourceId,
    this.nodeIds = const <String>[],
  });

  final BdoNodeNetworkDiagnosticCode code;
  final BdoNodeNetworkDiagnosticSeverity severity;
  final String message;
  final String? query;
  final String? resourceId;
  final List<String> nodeIds;
}

/// The desired worker network and the user's currently saved network.
///
/// Resource keys may be canonical resource IDs, exact resource names, exact
/// aliases, or exact worker-output names. Matching is case-insensitive and
/// whitespace-insensitive. Counts mean distinct production nodes, not output
/// quantity per cycle.
class BdoNodeNetworkRequest {
  BdoNodeNetworkRequest({
    required this.contributionPointBudget,
    required Map<String, int> desiredResourceNodeCounts,
    Set<String> currentNodeIds = const <String>{},
    Set<String>? rootNodeIds,
    this.maxExactTerminalNodes = 10,
    this.maxExactSelectionCombinations = 256,
  }) : desiredResourceNodeCounts = Map<String, int>.unmodifiable(
         desiredResourceNodeCounts,
       ),
       currentNodeIds = Set<String>.unmodifiable(currentNodeIds),
       rootNodeIds = rootNodeIds == null
           ? null
           : Set<String>.unmodifiable(rootNodeIds);

  /// The user's total CP ceiling. Existing nodes still consume this budget.
  final int contributionPointBudget;

  /// Requested production-node counts keyed by resource ID or exact name.
  final Map<String, int> desiredResourceNodeCounts;

  /// Node IDs in the last saved active network.
  final Set<String> currentNodeIds;

  /// Explicit free network roots. When omitted, every zero-CP City and Town
  /// is a root.
  final Set<String>? rootNodeIds;

  /// Maximum number of selected production terminals for exact Steiner search.
  ///
  /// A one-node-per-resource request that exceeds this limit uses the
  /// deterministic scalable optimizer and returns a complete connected plan
  /// with a [BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed] status.
  ///
  /// Repeated-node requests still need explicit terminal enumeration and can
  /// return [BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded].
  final int maxExactTerminalNodes;

  /// Maximum unique, inclusion-minimal production-node selections considered
  /// by exact search when one or more resources request repeated production
  /// nodes.
  ///
  /// One-node-per-resource requests use direct exact resource-group solving
  /// and do not enumerate candidate selections. A repeated-node request that
  /// exceeds this limit returns no plan and an
  /// [BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded] error.
  final int maxExactSelectionCombinations;
}

/// Visual state for a node or graph edge when comparing two saved plans.
enum BdoNodeNetworkChangeKind {
  /// Active before and after the proposed change.
  retained,

  /// Must be activated for the proposed network.
  connect,

  /// Active now but absent from the proposed network.
  disconnect,
}

/// One canonical undirected graph edge for colored map rendering.
class BdoNodeNetworkEdgeChange {
  const BdoNodeNetworkEdgeChange({
    required this.firstNodeId,
    required this.secondNodeId,
    required this.kind,
  });

  final String firstNodeId;
  final String secondNodeId;
  final BdoNodeNetworkChangeKind kind;

  String get key => '$firstNodeId\u0000$secondNodeId';
}

/// Node and edge changes between the saved and proposed networks.
class BdoNodeNetworkChangeSet {
  const BdoNodeNetworkChangeSet({
    required this.retainedNodeIds,
    required this.connectNodeIds,
    required this.disconnectNodeIds,
    required this.edges,
    required this.connectContributionPoints,
    required this.disconnectContributionPoints,
  });

  final List<String> retainedNodeIds;
  final List<String> connectNodeIds;
  final List<String> disconnectNodeIds;
  final List<BdoNodeNetworkEdgeChange> edges;

  /// CP added by nodes in [connectNodeIds].
  final int connectContributionPoints;

  /// CP released by nodes in [disconnectNodeIds].
  final int disconnectContributionPoints;

  int get netContributionPointChange =>
      connectContributionPoints - disconnectContributionPoints;
}

/// A complete, connected worker-node proposal.
class BdoNodeNetworkPlan {
  const BdoNodeNetworkPlan({
    required this.optimizationMode,
    required this.contributionPointBudget,
    required this.totalContributionPoints,
    required this.currentContributionPoints,
    required this.requestedNodeCountByResource,
    required this.workerNodeIdsByResource,
    required this.selectedNodeIds,
    required this.selectedRootNodeIds,
    required this.selectedProductionNodeIds,
    required this.changeSet,
  });

  final BdoNodeNetworkOptimizationMode optimizationMode;
  final int contributionPointBudget;
  final int totalContributionPoints;
  final int currentContributionPoints;

  /// Canonical resource IDs and their requested distinct-node counts.
  final Map<String, int> requestedNodeCountByResource;

  /// Every selected production node that produces each requested resource.
  ///
  /// A shared production node can appear under more than one resource.
  final Map<String, List<String>> workerNodeIdsByResource;
  final List<String> selectedNodeIds;
  final List<String> selectedRootNodeIds;
  final List<String> selectedProductionNodeIds;
  final BdoNodeNetworkChangeSet changeSet;

  bool get isExact => optimizationMode == BdoNodeNetworkOptimizationMode.exact;

  bool get usesScalableOptimization =>
      optimizationMode == BdoNodeNetworkOptimizationMode.scalable;

  /// Whether this returned proposal fits the requested CP budget.
  ///
  /// A scalable proposal is not a proof that every possible network exceeds
  /// the budget when this is false.
  bool get isWithinBudget => totalContributionPoints <= contributionPointBudget;

  int get remainingContributionPoints =>
      contributionPointBudget - totalContributionPoints;
}

/// Result of resolving and optimizing a worker-network request.
class BdoNodeNetworkResult {
  const BdoNodeNetworkResult({required this.plan, required this.diagnostics});

  /// Null when validation fails, the requirements are impossible, or a
  /// repeated-node exact search exceeds a configured safety limit.
  final BdoNodeNetworkPlan? plan;
  final List<BdoNodeNetworkDiagnostic> diagnostics;

  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error,
  );

  bool get hasPlan => plan != null;
}
