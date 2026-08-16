import 'dart:collection';

import '../model/resource_map_data.dart';

/// Severity of a production-node path diagnostic.
enum BdoProductionNodePathDiagnosticSeverity { warning, error }

/// Stable reasons why a production-node path could not be fully resolved.
enum BdoProductionNodePathDiagnosticCode {
  unknownTargetNode,
  targetIsNotProductionNode,
  unknownRootNode,
  invalidRootNode,
  noRootNodes,
  unknownCurrentNode,
  invalidNodeContributionPoints,
  unreachableTargetNode,
}

/// A validation or reachability issue discovered while calculating a path.
class BdoProductionNodePathDiagnostic {
  const BdoProductionNodePathDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.nodeIds = const <String>[],
  });

  final BdoProductionNodePathDiagnosticCode code;
  final BdoProductionNodePathDiagnosticSeverity severity;
  final String message;
  final List<String> nodeIds;
}

/// One directed step in an ordered root-to-production-node path.
class BdoProductionNodePathEdge {
  const BdoProductionNodePathEdge({
    required this.fromNodeId,
    required this.toNodeId,
  });

  final String fromNodeId;
  final String toNodeId;

  String get key => '$fromNodeId\u0000$toNodeId';
}

/// A complete connection from one allowed root to one production node.
class BdoProductionNodePath {
  const BdoProductionNodePath({
    required this.targetNodeId,
    required this.rootNodeId,
    required this.orderedNodeIds,
    required this.edges,
    required this.totalContributionPoints,
    required this.incrementalContributionPoints,
    required this.retainedNodeIds,
    required this.connectNodeIds,
  });

  final String targetNodeId;
  final String rootNodeId;

  /// Node IDs in traversal order, including the root and target.
  final List<String> orderedNodeIds;
  final List<BdoProductionNodePathEdge> edges;

  /// CP used by every non-root node in this path, including saved nodes.
  final int totalContributionPoints;

  /// CP added by nodes in this path that are not in the saved network.
  final int incrementalContributionPoints;

  /// Saved, non-root nodes reused by this path.
  final List<String> retainedNodeIds;

  /// Non-root nodes that must be activated for this path.
  final List<String> connectNodeIds;

  bool get isAlreadyConnected => incrementalContributionPoints == 0;
}

/// Inputs for one production-node path calculation.
class BdoProductionNodePathRequest {
  BdoProductionNodePathRequest({
    required this.targetNodeId,
    Set<String> currentNodeIds = const <String>{},
    Set<String>? allowedRootNodeIds,
  }) : currentNodeIds = Set<String>.unmodifiable(currentNodeIds),
       allowedRootNodeIds = allowedRootNodeIds == null
           ? null
           : Set<String>.unmodifiable(allowedRootNodeIds);

  final String targetNodeId;

  /// Node IDs in the user's currently active network.
  final Set<String> currentNodeIds;

  /// Explicit zero-CP city/town roots.
  ///
  /// When omitted, every zero-CP City and Town in the dataset is allowed.
  final Set<String>? allowedRootNodeIds;
}

/// The two useful cheapest paths to a production node.
///
/// [minimumTotalPath] minimizes the complete CP footprint first, matching the
/// primary cost used by [BdoNodeNetworkOptimizer]. [minimumIncrementalPath]
/// instead minimizes only newly activated CP first, so an existing longer
/// branch can be reused when that costs the user less additional CP.
class BdoProductionNodePathResult {
  const BdoProductionNodePathResult({
    required this.minimumTotalPath,
    required this.minimumIncrementalPath,
    required this.diagnostics,
  });

  final BdoProductionNodePath? minimumTotalPath;
  final BdoProductionNodePath? minimumIncrementalPath;
  final List<BdoProductionNodePathDiagnostic> diagnostics;

  bool get hasPath =>
      minimumTotalPath != null && minimumIncrementalPath != null;

  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoProductionNodePathDiagnosticSeverity.error,
  );
}

/// Calculates exact cheapest root-to-production-node paths.
///
/// Worker-node links are normalized as undirected, just as they are in
/// [BdoNodeNetworkOptimizer]. Production nodes other than the requested target
/// are never allowed as transit vertices.
class BdoProductionNodePathCostService {
  const BdoProductionNodePathCostService();

  BdoProductionNodePathResult calculate({
    required BdoResourceMapDataset data,
    required BdoProductionNodePathRequest request,
  }) => _PreparedProductionNodePathService(data.workerNodes).calculate(request);

  /// Calculates paths for every production node while preparing the graph only
  /// once. The returned map iterates in stable numeric-aware node-ID order.
  Map<String, BdoProductionNodePathResult> calculateAll({
    required BdoResourceMapDataset data,
    Set<String> currentNodeIds = const <String>{},
    Set<String>? allowedRootNodeIds,
  }) => _PreparedProductionNodePathService(data.workerNodes).calculateAll(
    currentNodeIds: currentNodeIds,
    allowedRootNodeIds: allowedRootNodeIds,
  );
}

class _PreparedProductionNodePathService {
  _PreparedProductionNodePathService(List<BdoWorkerNode> unsortedNodes)
    : nodes = List<BdoWorkerNode>.of(unsortedNodes)
        ..sort((left, right) => _compareIds(left.id, right.id)),
      indexById = <String, int>{},
      adjacency = <List<int>>[] {
    for (var index = 0; index < nodes.length; index++) {
      indexById[nodes[index].id] = index;
      adjacency.add(<int>[]);
    }
    final neighborSets = List<Set<int>>.generate(nodes.length, (_) => <int>{});
    for (var index = 0; index < nodes.length; index++) {
      for (final linkId in nodes[index].linkIds) {
        final neighbor = indexById[linkId];
        if (neighbor == null || neighbor == index) {
          continue;
        }
        neighborSets[index].add(neighbor);
        neighborSets[neighbor].add(index);
      }
    }
    for (var index = 0; index < nodes.length; index++) {
      adjacency[index] = neighborSets[index].toList()..sort();
    }
  }

  final List<BdoWorkerNode> nodes;
  final Map<String, int> indexById;
  final List<List<int>> adjacency;

  BdoProductionNodePathResult calculate(BdoProductionNodePathRequest request) {
    final context = _prepareRequest(
      targetNodeId: request.targetNodeId,
      currentNodeIds: request.currentNodeIds,
      allowedRootNodeIds: request.allowedRootNodeIds,
    );
    final targetIndex = context.targetIndex;
    if (targetIndex == null || context.hasErrors) {
      return _emptyResult(context.diagnostics);
    }

    final minimumTotal = _findEndpointPath(
      targetIndex: targetIndex,
      basePaths: _findBasePaths(
        roots: context.roots,
        currentIndexes: context.currentIndexes,
        objective: _PathObjective.totalContributionPoints,
      ),
      roots: context.roots,
      currentIndexes: context.currentIndexes,
      objective: _PathObjective.totalContributionPoints,
    );
    final minimumIncremental = _findEndpointPath(
      targetIndex: targetIndex,
      basePaths: _findBasePaths(
        roots: context.roots,
        currentIndexes: context.currentIndexes,
        objective: _PathObjective.incrementalContributionPoints,
      ),
      roots: context.roots,
      currentIndexes: context.currentIndexes,
      objective: _PathObjective.incrementalContributionPoints,
    );
    return _resultForTarget(
      targetIndex: targetIndex,
      context: context,
      minimumTotal: minimumTotal,
      minimumIncremental: minimumIncremental,
    );
  }

  Map<String, BdoProductionNodePathResult> calculateAll({
    required Set<String> currentNodeIds,
    required Set<String>? allowedRootNodeIds,
  }) {
    final context = _prepareRequest(
      currentNodeIds: currentNodeIds,
      allowedRootNodeIds: allowedRootNodeIds,
    );
    final productionIndexes = <int>[
      for (var index = 0; index < nodes.length; index++)
        if (nodes[index].isProductionNode) index,
    ];
    final results = SplayTreeMap<String, BdoProductionNodePathResult>(
      _compareIds,
    );
    if (context.hasErrors) {
      for (final targetIndex in productionIndexes) {
        results[nodes[targetIndex].id] = _emptyResult(context.diagnostics);
      }
      return Map<String, BdoProductionNodePathResult>.unmodifiable(results);
    }

    // A production node is always an endpoint, never transit. Therefore the
    // best path to every possible endpoint shares the same best paths through
    // the non-production graph. Two traversals cover every target: one for
    // total CP and one for incremental CP.
    final totalBasePaths = _findBasePaths(
      roots: context.roots,
      currentIndexes: context.currentIndexes,
      objective: _PathObjective.totalContributionPoints,
    );
    final incrementalBasePaths = _findBasePaths(
      roots: context.roots,
      currentIndexes: context.currentIndexes,
      objective: _PathObjective.incrementalContributionPoints,
    );
    for (final targetIndex in productionIndexes) {
      results[nodes[targetIndex].id] = _resultForTarget(
        targetIndex: targetIndex,
        context: context,
        minimumTotal: _findEndpointPath(
          targetIndex: targetIndex,
          basePaths: totalBasePaths,
          roots: context.roots,
          currentIndexes: context.currentIndexes,
          objective: _PathObjective.totalContributionPoints,
        ),
        minimumIncremental: _findEndpointPath(
          targetIndex: targetIndex,
          basePaths: incrementalBasePaths,
          roots: context.roots,
          currentIndexes: context.currentIndexes,
          objective: _PathObjective.incrementalContributionPoints,
        ),
      );
    }
    return Map<String, BdoProductionNodePathResult>.unmodifiable(results);
  }

  _PreparedPathRequest _prepareRequest({
    String? targetNodeId,
    required Set<String> currentNodeIds,
    required Set<String>? allowedRootNodeIds,
  }) {
    final diagnostics = <BdoProductionNodePathDiagnostic>[];
    final negativeCostIds = nodes
        .where((node) => node.contributionPoints < 0)
        .map((node) => node.id)
        .toList(growable: false);
    if (negativeCostIds.isNotEmpty) {
      diagnostics.add(
        BdoProductionNodePathDiagnostic(
          code:
              BdoProductionNodePathDiagnosticCode.invalidNodeContributionPoints,
          severity: BdoProductionNodePathDiagnosticSeverity.error,
          message: 'Worker-node CP costs must be non-negative.',
          nodeIds: _sortIds(negativeCostIds),
        ),
      );
    }

    int? targetIndex;
    if (targetNodeId != null) {
      targetIndex = indexById[targetNodeId];
      if (targetIndex == null) {
        diagnostics.add(
          BdoProductionNodePathDiagnostic(
            code: BdoProductionNodePathDiagnosticCode.unknownTargetNode,
            severity: BdoProductionNodePathDiagnosticSeverity.error,
            message:
                'Production node "$targetNodeId" is absent from this map '
                'dataset.',
            nodeIds: <String>[targetNodeId],
          ),
        );
      } else if (!nodes[targetIndex].isProductionNode) {
        diagnostics.add(
          BdoProductionNodePathDiagnostic(
            code: BdoProductionNodePathDiagnosticCode.targetIsNotProductionNode,
            severity: BdoProductionNodePathDiagnosticSeverity.error,
            message: 'Node "$targetNodeId" is not a production node.',
            nodeIds: <String>[targetNodeId],
          ),
        );
      }
    }

    final knownCurrentIndexes = <int>{};
    final unknownCurrentIds = <String>[];
    for (final nodeId in currentNodeIds) {
      final index = indexById[nodeId];
      if (index == null) {
        unknownCurrentIds.add(nodeId);
      } else {
        knownCurrentIndexes.add(index);
      }
    }
    if (unknownCurrentIds.isNotEmpty) {
      diagnostics.add(
        BdoProductionNodePathDiagnostic(
          code: BdoProductionNodePathDiagnosticCode.unknownCurrentNode,
          severity: BdoProductionNodePathDiagnosticSeverity.warning,
          message:
              '${unknownCurrentIds.length} saved node '
              '${unknownCurrentIds.length == 1 ? 'ID is' : 'IDs are'} no '
              'longer present in this map dataset.',
          nodeIds: _sortIds(unknownCurrentIds),
        ),
      );
    }

    final roots = _resolveRoots(allowedRootNodeIds, diagnostics: diagnostics);
    if (roots.isEmpty &&
        !diagnostics.any(
          (diagnostic) =>
              diagnostic.code ==
              BdoProductionNodePathDiagnosticCode.noRootNodes,
        )) {
      diagnostics.add(
        const BdoProductionNodePathDiagnostic(
          code: BdoProductionNodePathDiagnosticCode.noRootNodes,
          severity: BdoProductionNodePathDiagnosticSeverity.error,
          message: 'No usable zero-CP city or town root is available.',
        ),
      );
    }

    return _PreparedPathRequest(
      targetIndex: targetIndex,
      currentIndexes: Set<int>.unmodifiable(knownCurrentIndexes),
      roots: Set<int>.unmodifiable(roots),
      diagnostics: List<BdoProductionNodePathDiagnostic>.unmodifiable(
        diagnostics,
      ),
    );
  }

  BdoProductionNodePathResult _resultForTarget({
    required int targetIndex,
    required _PreparedPathRequest context,
    required _PathCandidate? minimumTotal,
    required _PathCandidate? minimumIncremental,
  }) {
    if (minimumTotal == null || minimumIncremental == null) {
      final diagnostics = <BdoProductionNodePathDiagnostic>[
        ...context.diagnostics,
        BdoProductionNodePathDiagnostic(
          code: BdoProductionNodePathDiagnosticCode.unreachableTargetNode,
          severity: BdoProductionNodePathDiagnosticSeverity.error,
          message:
              'Production node "${nodes[targetIndex].id}" cannot be reached '
              'from the allowed roots without using another production node '
              'as transit.',
          nodeIds: <String>[nodes[targetIndex].id],
        ),
      ];
      return _emptyResult(diagnostics);
    }

    return BdoProductionNodePathResult(
      minimumTotalPath: _buildPath(
        minimumTotal,
        currentIndexes: context.currentIndexes,
        roots: context.roots,
      ),
      minimumIncrementalPath: _buildPath(
        minimumIncremental,
        currentIndexes: context.currentIndexes,
        roots: context.roots,
      ),
      diagnostics: context.diagnostics,
    );
  }

  BdoProductionNodePathResult _emptyResult(
    Iterable<BdoProductionNodePathDiagnostic> diagnostics,
  ) {
    return BdoProductionNodePathResult(
      minimumTotalPath: null,
      minimumIncrementalPath: null,
      diagnostics: List<BdoProductionNodePathDiagnostic>.unmodifiable(
        diagnostics,
      ),
    );
  }

  Set<int> _resolveRoots(
    Set<String>? requestedRootIds, {
    required List<BdoProductionNodePathDiagnostic> diagnostics,
  }) {
    if (requestedRootIds == null) {
      return <int>{
        for (var index = 0; index < nodes.length; index++)
          if (_isDefaultRoot(nodes[index])) index,
      };
    }

    final roots = <int>{};
    final unknownIds = <String>[];
    final invalidIds = <String>[];
    for (final nodeId in requestedRootIds) {
      final index = indexById[nodeId];
      if (index == null) {
        unknownIds.add(nodeId);
      } else if (!_isDefaultRoot(nodes[index])) {
        invalidIds.add(nodeId);
      } else {
        roots.add(index);
      }
    }
    if (unknownIds.isNotEmpty) {
      diagnostics.add(
        BdoProductionNodePathDiagnostic(
          code: BdoProductionNodePathDiagnosticCode.unknownRootNode,
          severity: BdoProductionNodePathDiagnosticSeverity.error,
          message:
              '${unknownIds.length} allowed network '
              '${unknownIds.length == 1 ? 'root is' : 'roots are'} absent '
              'from this map dataset.',
          nodeIds: _sortIds(unknownIds),
        ),
      );
    }
    if (invalidIds.isNotEmpty) {
      diagnostics.add(
        BdoProductionNodePathDiagnostic(
          code: BdoProductionNodePathDiagnosticCode.invalidRootNode,
          severity: BdoProductionNodePathDiagnosticSeverity.error,
          message:
              '${invalidIds.length} allowed network '
              '${invalidIds.length == 1 ? 'root is not' : 'roots are not'} a '
              'zero-CP city or town.',
          nodeIds: _sortIds(invalidIds),
        ),
      );
    }
    return roots;
  }

  List<_PathCandidate?> _findBasePaths({
    required Set<int> roots,
    required Set<int> currentIndexes,
    required _PathObjective objective,
  }) {
    final bestByNode = List<_PathCandidate?>.filled(nodes.length, null);
    final heap = _PathCandidateHeap(objective);
    for (final root in roots.toList()..sort()) {
      final candidate = _PathCandidate(
        path: <int>[root],
        totalContributionPoints: 0,
        incrementalContributionPoints: 0,
        newlyActivatedNodeCount: 0,
      );
      final currentBest = bestByNode[root];
      if (currentBest == null ||
          _compareCandidates(candidate, currentBest, objective) < 0) {
        bestByNode[root] = candidate;
        heap.add(candidate);
      }
    }

    while (heap.isNotEmpty) {
      final current = heap.removeFirst();
      final currentIndex = current.path.last;
      if (!identical(bestByNode[currentIndex], current)) {
        continue;
      }
      if (nodes[currentIndex].isProductionNode) {
        continue;
      }

      for (final neighbor in adjacency[currentIndex]) {
        if (current.path.contains(neighbor)) {
          continue;
        }
        if (nodes[neighbor].isProductionNode) {
          continue;
        }
        final candidate = _extendPath(
          current,
          neighbor,
          roots: roots,
          currentIndexes: currentIndexes,
        );
        final previous = bestByNode[neighbor];
        if (previous == null ||
            _compareCandidates(candidate, previous, objective) < 0) {
          bestByNode[neighbor] = candidate;
          heap.add(candidate);
        }
      }
    }
    return bestByNode;
  }

  _PathCandidate? _findEndpointPath({
    required int targetIndex,
    required List<_PathCandidate?> basePaths,
    required Set<int> roots,
    required Set<int> currentIndexes,
    required _PathObjective objective,
  }) {
    _PathCandidate? best;
    if (roots.contains(targetIndex)) {
      best = basePaths[targetIndex];
    }
    for (final neighbor in adjacency[targetIndex]) {
      final base = basePaths[neighbor];
      if (base == null || base.path.contains(targetIndex)) {
        continue;
      }
      final candidate = _extendPath(
        base,
        targetIndex,
        roots: roots,
        currentIndexes: currentIndexes,
      );
      if (best == null || _compareCandidates(candidate, best, objective) < 0) {
        best = candidate;
      }
    }
    return best;
  }

  _PathCandidate _extendPath(
    _PathCandidate current,
    int neighbor, {
    required Set<int> roots,
    required Set<int> currentIndexes,
  }) {
    final isRoot = roots.contains(neighbor);
    final isCurrent = currentIndexes.contains(neighbor);
    final contributionPoints = isRoot ? 0 : nodes[neighbor].contributionPoints;
    return _PathCandidate(
      path: <int>[...current.path, neighbor],
      totalContributionPoints:
          current.totalContributionPoints + contributionPoints,
      incrementalContributionPoints:
          current.incrementalContributionPoints +
          (isCurrent ? 0 : contributionPoints),
      newlyActivatedNodeCount:
          current.newlyActivatedNodeCount + (isRoot || isCurrent ? 0 : 1),
    );
  }

  BdoProductionNodePath _buildPath(
    _PathCandidate candidate, {
    required Set<int> currentIndexes,
    required Set<int> roots,
  }) {
    final orderedIds = candidate.path
        .map((index) => nodes[index].id)
        .toList(growable: false);
    final retainedIds = <String>[];
    final connectIds = <String>[];
    for (final index in candidate.path) {
      if (roots.contains(index)) {
        continue;
      }
      if (currentIndexes.contains(index)) {
        retainedIds.add(nodes[index].id);
      } else {
        connectIds.add(nodes[index].id);
      }
    }
    final edges = <BdoProductionNodePathEdge>[
      for (var index = 1; index < orderedIds.length; index++)
        BdoProductionNodePathEdge(
          fromNodeId: orderedIds[index - 1],
          toNodeId: orderedIds[index],
        ),
    ];
    return BdoProductionNodePath(
      targetNodeId: orderedIds.last,
      rootNodeId: orderedIds.first,
      orderedNodeIds: List<String>.unmodifiable(orderedIds),
      edges: List<BdoProductionNodePathEdge>.unmodifiable(edges),
      totalContributionPoints: candidate.totalContributionPoints,
      incrementalContributionPoints: candidate.incrementalContributionPoints,
      retainedNodeIds: _sortIds(retainedIds),
      connectNodeIds: _sortIds(connectIds),
    );
  }
}

class _PreparedPathRequest {
  const _PreparedPathRequest({
    required this.targetIndex,
    required this.currentIndexes,
    required this.roots,
    required this.diagnostics,
  });

  final int? targetIndex;
  final Set<int> currentIndexes;
  final Set<int> roots;
  final List<BdoProductionNodePathDiagnostic> diagnostics;

  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == BdoProductionNodePathDiagnosticSeverity.error,
  );
}

enum _PathObjective { totalContributionPoints, incrementalContributionPoints }

class _PathCandidate {
  const _PathCandidate({
    required this.path,
    required this.totalContributionPoints,
    required this.incrementalContributionPoints,
    required this.newlyActivatedNodeCount,
  });

  final List<int> path;
  final int totalContributionPoints;
  final int incrementalContributionPoints;
  final int newlyActivatedNodeCount;
}

class _PathCandidateHeap {
  _PathCandidateHeap(this.objective);

  final _PathObjective objective;
  final List<_PathCandidate> _values = <_PathCandidate>[];

  bool get isNotEmpty => _values.isNotEmpty;

  void add(_PathCandidate value) {
    _values.add(value);
    var index = _values.length - 1;
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_compareCandidates(value, _values[parent], objective) >= 0) {
        break;
      }
      _values[index] = _values[parent];
      index = parent;
    }
    _values[index] = value;
  }

  _PathCandidate removeFirst() {
    final first = _values.first;
    final last = _values.removeLast();
    if (_values.isEmpty) {
      return first;
    }
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _values.length) {
        break;
      }
      final right = left + 1;
      final child =
          right < _values.length &&
              _compareCandidates(_values[right], _values[left], objective) < 0
          ? right
          : left;
      if (_compareCandidates(_values[child], last, objective) >= 0) {
        break;
      }
      _values[index] = _values[child];
      index = child;
    }
    _values[index] = last;
    return first;
  }
}

int _compareCandidates(
  _PathCandidate left,
  _PathCandidate right,
  _PathObjective objective,
) {
  final primaryComparison = switch (objective) {
    _PathObjective.totalContributionPoints =>
      left.totalContributionPoints.compareTo(right.totalContributionPoints),
    _PathObjective.incrementalContributionPoints =>
      left.incrementalContributionPoints.compareTo(
        right.incrementalContributionPoints,
      ),
  };
  if (primaryComparison != 0) {
    return primaryComparison;
  }

  final secondaryComparison = left.newlyActivatedNodeCount.compareTo(
    right.newlyActivatedNodeCount,
  );
  if (secondaryComparison != 0) {
    return secondaryComparison;
  }

  final otherCostComparison = switch (objective) {
    _PathObjective.totalContributionPoints =>
      left.incrementalContributionPoints.compareTo(
        right.incrementalContributionPoints,
      ),
    _PathObjective.incrementalContributionPoints =>
      left.totalContributionPoints.compareTo(right.totalContributionPoints),
  };
  if (otherCostComparison != 0) {
    return otherCostComparison;
  }

  final lengthComparison = left.path.length.compareTo(right.path.length);
  if (lengthComparison != 0) {
    return lengthComparison;
  }
  for (var index = 0; index < left.path.length; index++) {
    final comparison = left.path[index].compareTo(right.path[index]);
    if (comparison != 0) {
      return comparison;
    }
  }
  return 0;
}

bool _isDefaultRoot(BdoWorkerNode node) =>
    node.contributionPoints == 0 &&
    (node.nodeType == 'City' || node.nodeType == 'Town');

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
