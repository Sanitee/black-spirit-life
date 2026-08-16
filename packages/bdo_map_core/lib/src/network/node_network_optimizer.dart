import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/resource_map_data.dart';
import 'node_network_models.dart';

part 'node_network_worker.dart';

/// Builds a contribution-point-minimal worker-node network.
///
/// Requests for one production node per resource are solved directly as an
/// exact group-Steiner forest. This avoids enumerating the cartesian product of
/// every possible production-node choice. Requests for repeated nodes of a
/// resource exhaustively enumerate every inclusion-minimal production-node
/// selection, then connect each selection with the Dreyfus-Wagner dynamic
/// program. A zero-cost virtual root joins all configured zero-CP cities/towns,
/// so separate branches may originate at different roots while shared paths
/// are still costed once.
///
/// Tractable requests are provably minimum-CP for the normalized graph and
/// requested counts. Equal-CP plans prefer fewer newly activated nodes, then
/// stable node-ID order.
///
/// Exact search is bounded by [BdoNodeNetworkRequest.maxExactTerminalNodes].
/// [BdoNodeNetworkRequest.maxExactSelectionCombinations] additionally bounds
/// repeated-node requests that still require explicit selection enumeration.
/// Large one-node-per-resource portfolios use a deterministic incremental
/// Steiner heuristic with terminal-by-terminal local improvement. It always
/// emits a complete connected route after reachability validation, while its
/// optimization mode and diagnostic make clear that global optimality is not
/// guaranteed. Repeated-node requests still fail closed when exact enumeration
/// would exceed its configured safety limits.
class BdoNodeNetworkOptimizer {
  const BdoNodeNetworkOptimizer();

  BdoNodeNetworkResult optimize({
    required BdoResourceMapDataset data,
    required BdoNodeNetworkRequest request,
  }) => _PreparedNodeNetworkOptimizer(data).optimize(request);
}

class _PreparedNodeNetworkOptimizer {
  _PreparedNodeNetworkOptimizer(BdoResourceMapDataset data)
    : this.fromNetworkData(
        resources: data.resources,
        workerNodes: data.workerNodes,
      );

  _PreparedNodeNetworkOptimizer.fromNetworkData({
    required List<BdoResourceDefinition> resources,
    required List<BdoWorkerNode> workerNodes,
  }) : resources = List<BdoResourceDefinition>.unmodifiable(resources),
       resourcesById = <String, BdoResourceDefinition>{
         for (final resource in resources) resource.id: resource,
       },
       graph = _NetworkGraph(workerNodes);

  final List<BdoResourceDefinition> resources;
  final Map<String, BdoResourceDefinition> resourcesById;
  final _NetworkGraph graph;

  BdoNodeNetworkResult optimize(BdoNodeNetworkRequest request) {
    final diagnostics = <BdoNodeNetworkDiagnostic>[];
    if (request.contributionPointBudget < 0) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.invalidContributionPointBudget,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message: 'Contribution-point budget cannot be negative.',
        ),
      );
    }

    final invalidCostIds = graph.nodes
        .where((node) => node.contributionPoints < 0)
        .map((node) => node.id)
        .toList(growable: false);
    if (invalidCostIds.isNotEmpty) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.invalidNodeContributionPoints,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message: 'Worker-node CP costs must be non-negative.',
          nodeIds: _sortIds(invalidCostIds),
        ),
      );
    }
    final unsafeCostIds = graph.nodes
        .where(
          (node) => node.contributionPoints > graph.maxSafeContributionPoints,
        )
        .map((node) => node.id)
        .toList(growable: false);
    if (unsafeCostIds.isNotEmpty) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.unsafeNodeContributionPoints,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message:
              'Worker-node CP costs exceed the safe optimization limit of '
              '${graph.maxSafeContributionPoints} CP per node for this '
              '${graph.nodes.length}-node dataset. Correct the listed map '
              'records before building a network.',
          nodeIds: _sortIds(unsafeCostIds),
        ),
      );
    }

    final knownCurrentIds = <String>{};
    final unknownCurrentIds = <String>[];
    for (final nodeId in request.currentNodeIds) {
      if (graph.indexById.containsKey(nodeId)) {
        knownCurrentIds.add(nodeId);
      } else {
        unknownCurrentIds.add(nodeId);
      }
    }
    if (unknownCurrentIds.isNotEmpty) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.unknownCurrentNode,
          severity: BdoNodeNetworkDiagnosticSeverity.warning,
          message:
              '${unknownCurrentIds.length} saved node '
              '${unknownCurrentIds.length == 1 ? 'ID is' : 'IDs are'} no '
              'longer present in this map dataset.',
          nodeIds: _sortIds(unknownCurrentIds),
        ),
      );
    }

    final resolvedCounts = _resolveRequirements(
      resources: resources,
      graph: graph,
      requestedCounts: request.desiredResourceNodeCounts,
      diagnostics: diagnostics,
    );

    if (diagnostics.any(
      (diagnostic) =>
          diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error,
    )) {
      return BdoNodeNetworkResult(
        plan: null,
        diagnostics: List<BdoNodeNetworkDiagnostic>.unmodifiable(diagnostics),
      );
    }

    final roots = _resolveRoots(
      graph: graph,
      requestedRootIds: request.rootNodeIds,
      diagnostics: diagnostics,
    );
    if (resolvedCounts.isNotEmpty && roots.isEmpty) {
      diagnostics.add(
        const BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.noRootNodes,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message: 'No usable city or town root is available for this network.',
        ),
      );
    }

    if (diagnostics.any(
      (diagnostic) =>
          diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error,
    )) {
      return BdoNodeNetworkResult(
        plan: null,
        diagnostics: List<BdoNodeNetworkDiagnostic>.unmodifiable(diagnostics),
      );
    }

    if (resolvedCounts.isEmpty) {
      return _emptyPlan(
        graph: graph,
        request: request,
        roots: roots,
        knownCurrentIds: knownCurrentIds,
        diagnostics: diagnostics,
      );
    }

    final requirements = <_ResolvedRequirement>[];
    final reachableBase = graph.reachableNonProductionNodes(roots);
    for (final entry in resolvedCounts.entries) {
      final allCandidates = graph.resourceCandidateIndexes(entry.key);
      final reachableCandidates = allCandidates
          .where(
            (candidate) => graph.productionNodeIsReachable(
              candidate,
              roots: roots,
              reachableBase: reachableBase,
            ),
          )
          .toList(growable: false);

      if (allCandidates.length < entry.value) {
        diagnostics.add(
          BdoNodeNetworkDiagnostic(
            code: BdoNodeNetworkDiagnosticCode.insufficientProductionNodes,
            severity: BdoNodeNetworkDiagnosticSeverity.error,
            message:
                '${_resourceName(resourcesById, entry.key)} has only '
                '${allCandidates.length} production '
                '${allCandidates.length == 1 ? 'node' : 'nodes'}, but '
                '${entry.value} were requested.',
            resourceId: entry.key,
            nodeIds: allCandidates
                .map((index) => graph.nodes[index].id)
                .toList(growable: false),
          ),
        );
        continue;
      }
      if (reachableCandidates.length < entry.value) {
        final unreachableIds = allCandidates
            .where((candidate) => !reachableCandidates.contains(candidate))
            .map((index) => graph.nodes[index].id)
            .toList(growable: false);
        diagnostics.add(
          BdoNodeNetworkDiagnostic(
            code: BdoNodeNetworkDiagnosticCode.unreachableProductionNodes,
            severity: BdoNodeNetworkDiagnosticSeverity.error,
            message:
                '${_resourceName(resourcesById, entry.key)} has only '
                '${reachableCandidates.length} connected production '
                '${reachableCandidates.length == 1 ? 'node' : 'nodes'}; '
                '${entry.value} were requested. Unlinked map records are not '
                'given guessed connections.',
            resourceId: entry.key,
            nodeIds: _sortIds(unreachableIds),
          ),
        );
        continue;
      }
      requirements.add(
        _ResolvedRequirement(
          resourceId: entry.key,
          count: entry.value,
          candidateIndexes: reachableCandidates,
        ),
      );
    }

    if (diagnostics.any(
      (diagnostic) =>
          diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error,
    )) {
      return BdoNodeNetworkResult(
        plan: null,
        diagnostics: List<BdoNodeNetworkDiagnostic>.unmodifiable(diagnostics),
      );
    }

    requirements.sort((left, right) {
      final candidateComparison = left.candidateIndexes.length.compareTo(
        right.candidateIndexes.length,
      );
      return candidateComparison != 0
          ? candidateComparison
          : left.resourceId.compareTo(right.resourceId);
    });

    final exactTerminalLimit = math.max(1, request.maxExactTerminalNodes);
    final exactCombinationLimit = math.max(
      1,
      request.maxExactSelectionCombinations,
    );
    late final _NetworkSolution solution;
    late final BdoNodeNetworkOptimizationMode optimizationMode;
    final hasOneNodePerResource = requirements.every(
      (requirement) => requirement.count == 1,
    );
    if (hasOneNodePerResource && requirements.length <= exactTerminalLimit) {
      solution = _solveExactResourceGroups(
        graph: graph,
        roots: roots,
        requirements: requirements,
        currentIds: knownCurrentIds,
      );
      optimizationMode = BdoNodeNetworkOptimizationMode.exact;
    } else if (hasOneNodePerResource) {
      // Resource rows can still collapse to a small exact terminal selection
      // when one production node provides several requested outputs. Preserve
      // exact solving when bounded enumeration proves that case, otherwise
      // build the scalable connected route.
      final compressedTerminalSets = _enumerateExactTerminalSets(
        requirements: requirements,
        maxTerminalNodes: exactTerminalLimit,
        maxSelectionCombinations: exactCombinationLimit,
      );
      if (!compressedTerminalSets.terminalLimitExceeded &&
          !compressedTerminalSets.selectionLimitExceeded) {
        solution = _solveExact(
          graph: graph,
          roots: roots,
          terminalSets: compressedTerminalSets.values,
          currentIds: knownCurrentIds,
        );
        optimizationMode = BdoNodeNetworkOptimizationMode.exact;
      } else {
        solution = _solveScalableResourceGroups(
          graph: graph,
          roots: roots,
          requirements: requirements,
          currentIds: knownCurrentIds,
        );
        optimizationMode = BdoNodeNetworkOptimizationMode.scalable;
        diagnostics.add(
          BdoNodeNetworkDiagnostic(
            code: BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed,
            severity: BdoNodeNetworkDiagnosticSeverity.info,
            message:
                'Route optimized for all ${requirements.length} materials. '
                'Large-plan mode includes every connection, but the absolute '
                'lowest possible CP cannot be proven.',
          ),
        );
      }
    } else {
      final terminalSets = _enumerateExactTerminalSets(
        requirements: requirements,
        maxTerminalNodes: exactTerminalLimit,
        maxSelectionCombinations: exactCombinationLimit,
      );
      if (terminalSets.terminalLimitExceeded ||
          terminalSets.selectionLimitExceeded) {
        solution = _solveScalableResourceGroups(
          graph: graph,
          roots: roots,
          requirements: requirements,
          currentIds: knownCurrentIds,
        );
        optimizationMode = BdoNodeNetworkOptimizationMode.scalable;
        diagnostics.add(
          BdoNodeNetworkDiagnostic(
            code: BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed,
            severity: BdoNodeNetworkDiagnosticSeverity.info,
            message:
                'Route optimized for every requested production-node count. '
                'Large-plan mode includes every connection and requested '
                'node, but the absolute lowest possible CP cannot be proven.',
          ),
        );
      } else {
        solution = _solveExact(
          graph: graph,
          roots: roots,
          terminalSets: terminalSets.values,
          currentIds: knownCurrentIds,
        );
        optimizationMode = BdoNodeNetworkOptimizationMode.exact;
      }
    }
    final plan = _buildPlan(
      graph: graph,
      request: request,
      mode: optimizationMode,
      roots: roots,
      resolvedCounts: resolvedCounts,
      knownCurrentIds: knownCurrentIds,
      solution: solution,
    );
    if (!plan.isWithinBudget) {
      final exceededBy =
          plan.totalContributionPoints - request.contributionPointBudget;
      final message =
          optimizationMode == BdoNodeNetworkOptimizationMode.scalable
          ? 'This proposed scalable route uses '
                '${plan.totalContributionPoints} CP, exceeding the '
                '${request.contributionPointBudget} CP budget by $exceededBy. '
                'Large-plan mode does not prove that every complete route is '
                'over budget.'
          : 'The cheapest complete network needs '
                '${plan.totalContributionPoints} CP, exceeding the '
                '${request.contributionPointBudget} CP budget by $exceededBy.';
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.contributionPointBudgetExceeded,
          severity: BdoNodeNetworkDiagnosticSeverity.warning,
          message: message,
        ),
      );
    }

    return BdoNodeNetworkResult(
      plan: plan,
      diagnostics: List<BdoNodeNetworkDiagnostic>.unmodifiable(diagnostics),
    );
  }

  BdoNodeNetworkResult _emptyPlan({
    required _NetworkGraph graph,
    required BdoNodeNetworkRequest request,
    required Set<int> roots,
    required Set<String> knownCurrentIds,
    required List<BdoNodeNetworkDiagnostic> diagnostics,
  }) {
    final solution = const _NetworkSolution(
      nodeIndexes: <int>{},
      edges: <_IndexEdge>{},
      terminalIndexes: <int>{},
    );
    final plan = _buildPlan(
      graph: graph,
      request: request,
      mode: BdoNodeNetworkOptimizationMode.exact,
      roots: roots,
      resolvedCounts: const <String, int>{},
      knownCurrentIds: knownCurrentIds,
      solution: solution,
    );
    return BdoNodeNetworkResult(
      plan: plan,
      diagnostics: List<BdoNodeNetworkDiagnostic>.unmodifiable(diagnostics),
    );
  }
}

Map<String, int> _resolveRequirements({
  required List<BdoResourceDefinition> resources,
  required _NetworkGraph graph,
  required Map<String, int> requestedCounts,
  required List<BdoNodeNetworkDiagnostic> diagnostics,
}) {
  final lookup = <String, Set<String>>{};

  void addLookup(String value, String resourceId) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) {
      return;
    }
    lookup.putIfAbsent(normalized, () => <String>{}).add(resourceId);
  }

  for (final resource in resources) {
    addLookup(resource.id, resource.id);
    addLookup(resource.name, resource.id);
    for (final alias in resource.aliases) {
      addLookup(alias, resource.id);
    }
  }
  for (final node in graph.nodes.where((node) => node.isResourceNode)) {
    for (final output in node.outputs) {
      addLookup(output.resourceId, output.resourceId);
      addLookup(output.name, output.resourceId);
    }
  }

  final result = <String, int>{};
  for (final entry in requestedCounts.entries) {
    if (entry.value <= 0) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.invalidRequestedCount,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message:
              'Requested production-node counts must be greater than zero.',
          query: entry.key,
        ),
      );
      continue;
    }
    final matches = lookup[_normalize(entry.key)] ?? const <String>{};
    if (matches.isEmpty) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.unknownResource,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message:
              '"${entry.key}" does not match a worker-node resource ID, '
              'name, alias, or output name.',
          query: entry.key,
        ),
      );
      continue;
    }
    if (matches.length > 1) {
      diagnostics.add(
        BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.ambiguousResource,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message:
              '"${entry.key}" matches multiple worker resources. Select one '
              'by its canonical resource ID.',
          query: entry.key,
        ),
      );
      continue;
    }
    final resourceId = matches.single;
    result.update(
      resourceId,
      (count) => count + entry.value,
      ifAbsent: () => entry.value,
    );
  }
  return Map<String, int>.unmodifiable(SplayTreeMap<String, int>.from(result));
}

Set<int> _resolveRoots({
  required _NetworkGraph graph,
  required Set<String>? requestedRootIds,
  required List<BdoNodeNetworkDiagnostic> diagnostics,
}) {
  if (requestedRootIds == null) {
    return <int>{
      for (var index = 0; index < graph.nodes.length; index++)
        if (_isDefaultRoot(graph.nodes[index])) index,
    };
  }

  final roots = <int>{};
  final unknownIds = <String>[];
  final invalidIds = <String>[];
  for (final nodeId in requestedRootIds) {
    final index = graph.indexById[nodeId];
    if (index == null) {
      unknownIds.add(nodeId);
    } else if (!_isDefaultRoot(graph.nodes[index])) {
      invalidIds.add(nodeId);
    } else {
      roots.add(index);
    }
  }
  if (unknownIds.isNotEmpty) {
    diagnostics.add(
      BdoNodeNetworkDiagnostic(
        code: BdoNodeNetworkDiagnosticCode.unknownRootNode,
        severity: BdoNodeNetworkDiagnosticSeverity.error,
        message:
            '${unknownIds.length} configured network '
            '${unknownIds.length == 1 ? 'root is' : 'roots are'} absent from '
            'this map dataset.',
        nodeIds: _sortIds(unknownIds),
      ),
    );
  }
  if (invalidIds.isNotEmpty) {
    diagnostics.add(
      BdoNodeNetworkDiagnostic(
        code: BdoNodeNetworkDiagnosticCode.invalidRootNode,
        severity: BdoNodeNetworkDiagnosticSeverity.error,
        message:
            '${invalidIds.length} configured network '
            '${invalidIds.length == 1 ? 'root is not' : 'roots are not'} a '
            'zero-CP city or town.',
        nodeIds: _sortIds(invalidIds),
      ),
    );
  }
  return roots;
}

bool _isDefaultRoot(BdoWorkerNode node) =>
    node.contributionPoints == 0 &&
    (node.nodeType == 'City' || node.nodeType == 'Town');

String _resourceName(
  Map<String, BdoResourceDefinition> resourcesById,
  String resourceId,
) => resourcesById[resourceId]?.name ?? resourceId;

_ExactTerminalSets _enumerateExactTerminalSets({
  required List<_ResolvedRequirement> requirements,
  required int maxTerminalNodes,
  required int maxSelectionCombinations,
}) {
  final terminalSets = <String, List<int>>{};
  final selected = <int>{};
  var terminalLimitExceeded = false;
  var selectionLimitExceeded = false;

  bool requirementsAreMet(Set<int> terminals) {
    return requirements.every(
      (requirement) =>
          terminals.where(requirement.candidateIndexes.contains).length >=
          requirement.count,
    );
  }

  List<int> minimalSelection() {
    final minimal = <int>{...selected};
    for (final candidate in minimal.toList()..sort()) {
      minimal.remove(candidate);
      if (!requirementsAreMet(minimal)) {
        minimal.add(candidate);
      }
    }
    return minimal.toList()..sort();
  }

  void enumerateRequirement(int requirementIndex) {
    if (terminalLimitExceeded || selectionLimitExceeded) {
      return;
    }
    if (requirementIndex == requirements.length) {
      final terminals = minimalSelection();
      if (terminals.length > maxTerminalNodes) {
        terminalLimitExceeded = true;
        return;
      }
      terminalSets.putIfAbsent(
        terminals.join(','),
        () => List<int>.unmodifiable(terminals),
      );
      if (terminalSets.length > maxSelectionCombinations) {
        selectionLimitExceeded = true;
      }
      return;
    }

    final requirement = requirements[requirementIndex];
    final alreadySatisfied = selected
        .where(requirement.candidateIndexes.contains)
        .length;
    final stillNeeded = math.max(0, requirement.count - alreadySatisfied);
    if (stillNeeded == 0) {
      enumerateRequirement(requirementIndex + 1);
      return;
    }

    final available = requirement.candidateIndexes
        .where((candidate) => !selected.contains(candidate))
        .toList(growable: false);

    void choose(int start, int remaining) {
      if (remaining == 0) {
        enumerateRequirement(requirementIndex + 1);
        return;
      }
      final lastStart = available.length - remaining;
      for (var index = start; index <= lastStart; index++) {
        final candidate = available[index];
        selected.add(candidate);
        choose(index + 1, remaining - 1);
        selected.remove(candidate);
      }
    }

    choose(0, stillNeeded);
  }

  enumerateRequirement(0);
  return _ExactTerminalSets(
    values: List<List<int>>.unmodifiable(terminalSets.values),
    terminalLimitExceeded: terminalLimitExceeded,
    selectionLimitExceeded: selectionLimitExceeded,
  );
}

_NetworkSolution _solveExact({
  required _NetworkGraph graph,
  required Set<int> roots,
  required List<List<int>> terminalSets,
  required Set<String> currentIds,
}) {
  List<int>? bestTerminals;
  var bestCompositeCost = _infinity;
  for (final terminals in terminalSets) {
    final cost = _SteinerSolver(
      graph: graph,
      roots: roots,
      terminals: terminals,
      currentIds: currentIds,
      recordTrace: false,
    ).solveCost();
    if (cost < bestCompositeCost ||
        (cost == bestCompositeCost &&
            (bestTerminals == null ||
                _compareIntLists(terminals, bestTerminals) < 0))) {
      bestCompositeCost = cost;
      bestTerminals = terminals;
    }
  }

  if (bestTerminals == null || bestCompositeCost >= _infinity) {
    throw StateError(
      'Reachability validation succeeded, but exact network solving failed.',
    );
  }
  return _SteinerSolver(
    graph: graph,
    roots: roots,
    terminals: bestTerminals,
    currentIds: currentIds,
    recordTrace: true,
  ).solveWithTrace();
}

_NetworkSolution _solveExactResourceGroups({
  required _NetworkGraph graph,
  required Set<int> roots,
  required List<_ResolvedRequirement> requirements,
  required Set<String> currentIds,
}) {
  if (requirements.any((requirement) => requirement.count != 1)) {
    throw ArgumentError(
      'Exact resource-group solving requires one production node per resource.',
    );
  }
  return _SteinerSolver.forTerminalGroups(
    graph: graph,
    roots: roots,
    terminalGroups: <List<int>>[
      for (final requirement in requirements)
        List<int>.unmodifiable(requirement.candidateIndexes),
    ],
    currentIds: currentIds,
    recordTrace: true,
  ).solveWithTrace();
}

_NetworkSolution _solveScalableResourceGroups({
  required _NetworkGraph graph,
  required Set<int> roots,
  required List<_ResolvedRequirement> requirements,
  required Set<String> currentIds,
}) {
  final groupsByCandidate = <int, Set<int>>{};
  final requiredCounts = <int, int>{};
  for (var group = 0; group < requirements.length; group++) {
    requiredCounts[group] = requirements[group].count;
    for (final candidate in requirements[group].candidateIndexes) {
      groupsByCandidate.putIfAbsent(candidate, () => <int>{}).add(group);
    }
  }
  final allowedProductionIndexes = groupsByCandidate.keys.toSet();
  final currentIndexes = currentIds
      .map((id) => graph.indexById[id])
      .whereType<int>()
      .toSet();
  final weights = graph.compositeWeights(
    roots: roots,
    currentIndexes: currentIndexes,
    scale: graph.nodes.length + 1,
  );
  final selectedNodes = <int>{};
  final selectedEdges = <_IndexEdge>{};

  Map<int, int> coverageFor(Iterable<int> nodes) {
    final coverage = <int, int>{
      for (final group in requiredCounts.keys) group: 0,
    };
    for (final node in nodes) {
      for (final group in groupsByCandidate[node] ?? const <int>{}) {
        coverage.update(group, (count) => count + 1);
      }
    }
    return coverage;
  }

  bool everyRequirementMet(Map<int, int> coverage) => requiredCounts.entries
      .every((entry) => (coverage[entry.key] ?? 0) >= entry.value);

  var coverage = coverageFor(selectedNodes);
  while (!everyRequirementMet(coverage)) {
    final paths = _shortestPathsFromNetwork(
      graph: graph,
      roots: roots,
      selectedNodeIndexes: selectedNodes,
      allowedProductionIndexes: allowedProductionIndexes,
      weights: weights,
    );
    _ScalablePathChoice? bestChoice;
    for (final candidate in allowedProductionIndexes.toList()..sort()) {
      if (selectedNodes.contains(candidate)) {
        continue;
      }
      if (paths.distances[candidate] >= _infinity) {
        continue;
      }
      final path = paths.pathTo(candidate);
      final newlyCovered = <int>{};
      for (final group in groupsByCandidate[candidate] ?? const <int>{}) {
        if ((coverage[group] ?? 0) < (requiredCounts[group] ?? 0)) {
          newlyCovered.add(group);
        }
      }
      if (newlyCovered.isEmpty) {
        continue;
      }
      final choice = _ScalablePathChoice(
        targetIndex: candidate,
        marginalCost: paths.distances[candidate],
        newlyCoveredGroupCount: newlyCovered.length,
        path: path,
      );
      if (bestChoice == null ||
          _compareScalableChoices(choice, bestChoice) < 0) {
        bestChoice = choice;
      }
    }
    if (bestChoice == null) {
      throw StateError(
        'Reachability validation succeeded, but scalable network solving '
        'could not connect every resource group.',
      );
    }
    selectedNodes.addAll(bestChoice.path.nodeIndexes);
    selectedEdges.addAll(bestChoice.path.edges);
    coverage = coverageFor(selectedNodes);
  }

  var best = _normalizeScalableSolution(
    roots: roots,
    nodeIndexes: selectedNodes,
    edges: selectedEdges,
    requiredCounts: requiredCounts,
    groupsByCandidate: groupsByCandidate,
  );

  // Rebuild each terminal branch against the rest of the route. This catches
  // the most common greedy-ordering loss: an early, individually cheap branch
  // that becomes wasteful after later materials establish a shared trunk.
  for (var pass = 0; pass < 3; pass++) {
    var improved = false;
    for (var group = 0; group < requirements.length; group++) {
      final relaxedCounts = <int, int>{...requiredCounts, group: 0};
      final base = _normalizeScalableSolution(
        roots: roots,
        nodeIndexes: best.nodeIndexes,
        edges: best.edges,
        requiredCounts: relaxedCounts,
        groupsByCandidate: groupsByCandidate,
      );
      final trialNodes = <int>{...base.nodeIndexes};
      final trialEdges = <_IndexEdge>{...base.edges};
      while (_solutionCoverageCount(
            nodeIndexes: trialNodes,
            group: group,
            groupsByCandidate: groupsByCandidate,
          ) <
          requiredCounts[group]!) {
        final paths = _shortestPathsFromNetwork(
          graph: graph,
          roots: roots,
          selectedNodeIndexes: trialNodes,
          allowedProductionIndexes: allowedProductionIndexes,
          weights: weights,
        );
        int? bestCandidate;
        var bestDistance = _infinity;
        for (final candidate in requirements[group].candidateIndexes) {
          if (trialNodes.contains(candidate)) {
            continue;
          }
          final distance = paths.distances[candidate];
          if (distance < bestDistance ||
              (distance == bestDistance &&
                  (bestCandidate == null || candidate < bestCandidate))) {
            bestDistance = distance;
            bestCandidate = candidate;
          }
        }
        if (bestCandidate == null || bestDistance >= _infinity) {
          continue;
        }
        final path = paths.pathTo(bestCandidate);
        trialNodes.addAll(path.nodeIndexes);
        trialEdges.addAll(path.edges);
      }
      final trial = _normalizeScalableSolution(
        roots: roots,
        nodeIndexes: trialNodes,
        edges: trialEdges,
        requiredCounts: requiredCounts,
        groupsByCandidate: groupsByCandidate,
      );
      if (_compareScalableSolutions(
            trial,
            best,
            roots: roots,
            weights: weights,
          ) <
          0) {
        best = trial;
        improved = true;
      }
    }
    if (!improved) {
      break;
    }
  }

  if (!_solutionMeetsEveryRequirement(
    solution: best,
    requiredCounts: requiredCounts,
    groupsByCandidate: groupsByCandidate,
  )) {
    throw StateError(
      'Scalable network solving returned an incomplete resource selection.',
    );
  }
  if (best.edges.isEmpty &&
      best.terminalIndexes.any((terminal) => !roots.contains(terminal))) {
    throw StateError(
      'Scalable network solving returned terminals without connection paths.',
    );
  }
  return best;
}

_ShortestPathTree _shortestPathsFromNetwork({
  required _NetworkGraph graph,
  required Set<int> roots,
  required Set<int> selectedNodeIndexes,
  required Set<int> allowedProductionIndexes,
  required Int64List weights,
}) {
  final sources = <int>{
    ...roots,
    ...selectedNodeIndexes.where(
      (index) => !graph.nodes[index].isProductionNode,
    ),
  };
  final distances = Int64List(graph.nodes.length)
    ..fillRange(0, graph.nodes.length, _infinity);
  final parents = Int32List(graph.nodes.length)
    ..fillRange(0, graph.nodes.length, -1);
  final heap = _MinHeap();
  for (final source in sources.toList()..sort()) {
    distances[source] = 0;
    heap.add(_HeapEntry(vertex: source, cost: 0));
  }

  bool allowed(int index) =>
      roots.contains(index) ||
      !graph.nodes[index].isProductionNode ||
      allowedProductionIndexes.contains(index);

  while (heap.isNotEmpty) {
    final entry = heap.removeFirst();
    if (entry.cost != distances[entry.vertex]) {
      continue;
    }
    if (graph.nodes[entry.vertex].isProductionNode &&
        !roots.contains(entry.vertex)) {
      continue;
    }
    for (final neighbor in graph.adjacency[entry.vertex]) {
      if (!allowed(neighbor)) {
        continue;
      }
      final stepCost = sources.contains(neighbor) ? 0 : weights[neighbor];
      final candidate = _saturatingCostSum(entry.cost, stepCost);
      if (candidate < distances[neighbor]) {
        distances[neighbor] = candidate;
        parents[neighbor] = entry.vertex;
        heap.add(_HeapEntry(vertex: neighbor, cost: candidate));
      }
    }
  }
  return _ShortestPathTree(
    distances: distances,
    parents: parents,
    sources: sources,
  );
}

_NetworkSolution _normalizeScalableSolution({
  required Set<int> roots,
  required Set<int> nodeIndexes,
  required Set<_IndexEdge> edges,
  required Map<int, int> requiredCounts,
  required Map<int, Set<int>> groupsByCandidate,
}) {
  final nodes = <int>{...nodeIndexes};
  for (final edge in edges) {
    nodes
      ..add(edge.first)
      ..add(edge.second);
  }
  final edgeAdjacency = <int, List<int>>{
    for (final node in nodes) node: <int>[],
  };
  for (final edge in edges) {
    if (!nodes.contains(edge.first) || !nodes.contains(edge.second)) {
      continue;
    }
    edgeAdjacency[edge.first]!.add(edge.second);
    edgeAdjacency[edge.second]!.add(edge.first);
  }
  for (final neighbors in edgeAdjacency.values) {
    neighbors.sort();
  }

  final visited = <int>{};
  final queue = Queue<int>();
  for (final root in roots.where(nodes.contains).toList()..sort()) {
    visited.add(root);
    queue.add(root);
  }
  final treeEdges = <_IndexEdge>{};
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    for (final neighbor in edgeAdjacency[current] ?? const <int>[]) {
      if (!visited.add(neighbor)) {
        continue;
      }
      treeEdges.add(_IndexEdge(current, neighbor));
      queue.add(neighbor);
    }
  }
  if (visited.length != nodes.length) {
    throw StateError(
      'Scalable route normalization found nodes without a city/town path.',
    );
  }

  final treeAdjacency = <int, Set<int>>{
    for (final node in visited) node: <int>{},
  };
  for (final edge in treeEdges) {
    treeAdjacency[edge.first]!.add(edge.second);
    treeAdjacency[edge.second]!.add(edge.first);
  }
  final coverageCounts = <int, int>{
    for (final entry in requiredCounts.entries)
      if (entry.value > 0) entry.key: 0,
  };
  for (final node in visited) {
    for (final group in groupsByCandidate[node] ?? const <int>{}) {
      if ((requiredCounts[group] ?? 0) > 0) {
        coverageCounts.update(group, (count) => count + 1);
      }
    }
  }
  final leaves = Queue<int>();
  for (final node in visited.toList()..sort()) {
    if (!roots.contains(node) && treeAdjacency[node]!.length <= 1) {
      leaves.add(node);
    }
  }
  while (leaves.isNotEmpty) {
    final leaf = leaves.removeFirst();
    if (!visited.contains(leaf) ||
        roots.contains(leaf) ||
        treeAdjacency[leaf]!.length > 1) {
      continue;
    }
    final groups = (groupsByCandidate[leaf] ?? const <int>{}).where(
      (group) => (requiredCounts[group] ?? 0) > 0,
    );
    if (groups.any(
      (group) => (coverageCounts[group] ?? 0) <= (requiredCounts[group] ?? 0),
    )) {
      continue;
    }
    for (final group in groups) {
      coverageCounts.update(group, (count) => count - 1);
    }
    final neighbors = treeAdjacency[leaf]!.toList();
    visited.remove(leaf);
    treeAdjacency.remove(leaf);
    for (final neighbor in neighbors) {
      treeAdjacency[neighbor]!.remove(leaf);
      treeEdges.remove(_IndexEdge(leaf, neighbor));
      if (!roots.contains(neighbor) && treeAdjacency[neighbor]!.length <= 1) {
        leaves.add(neighbor);
      }
    }
  }

  final terminals = <int>{
    for (final node in visited)
      if ((groupsByCandidate[node] ?? const <int>{}).any(
        (group) => (requiredCounts[group] ?? 0) > 0,
      ))
        node,
  };
  return _NetworkSolution(
    nodeIndexes: Set<int>.unmodifiable(visited),
    edges: Set<_IndexEdge>.unmodifiable(treeEdges),
    terminalIndexes: Set<int>.unmodifiable(terminals),
  );
}

int _solutionCoverageCount({
  required Set<int> nodeIndexes,
  required int group,
  required Map<int, Set<int>> groupsByCandidate,
}) => nodeIndexes
    .where((node) => (groupsByCandidate[node] ?? const <int>{}).contains(group))
    .length;

bool _solutionMeetsEveryRequirement({
  required _NetworkSolution solution,
  required Map<int, int> requiredCounts,
  required Map<int, Set<int>> groupsByCandidate,
}) {
  return requiredCounts.entries.every(
    (entry) =>
        _solutionCoverageCount(
          nodeIndexes: solution.nodeIndexes,
          group: entry.key,
          groupsByCandidate: groupsByCandidate,
        ) >=
        entry.value,
  );
}

int _compareScalableChoices(
  _ScalablePathChoice left,
  _ScalablePathChoice right,
) {
  final leftRatio =
      BigInt.from(left.marginalCost) *
      BigInt.from(right.newlyCoveredGroupCount);
  final rightRatio =
      BigInt.from(right.marginalCost) *
      BigInt.from(left.newlyCoveredGroupCount);
  final ratioComparison = leftRatio.compareTo(rightRatio);
  if (ratioComparison != 0) {
    return ratioComparison;
  }
  final costComparison = left.marginalCost.compareTo(right.marginalCost);
  if (costComparison != 0) {
    return costComparison;
  }
  final coverageComparison = right.newlyCoveredGroupCount.compareTo(
    left.newlyCoveredGroupCount,
  );
  if (coverageComparison != 0) {
    return coverageComparison;
  }
  return left.targetIndex.compareTo(right.targetIndex);
}

int _compareScalableSolutions(
  _NetworkSolution left,
  _NetworkSolution right, {
  required Set<int> roots,
  required Int64List weights,
}) {
  int cost(_NetworkSolution solution) => solution.nodeIndexes
      .where((node) => !roots.contains(node))
      .fold<int>(0, (total, node) => total + weights[node]);
  final costComparison = cost(left).compareTo(cost(right));
  if (costComparison != 0) {
    return costComparison;
  }
  final leftNodes = left.nodeIndexes.toList()..sort();
  final rightNodes = right.nodeIndexes.toList()..sort();
  final nodeComparison = _compareIntLists(leftNodes, rightNodes);
  if (nodeComparison != 0) {
    return nodeComparison;
  }
  final leftEdges = left.edges.toList()..sort();
  final rightEdges = right.edges.toList()..sort();
  return _compareEdgeLists(leftEdges, rightEdges);
}

BdoNodeNetworkPlan _buildPlan({
  required _NetworkGraph graph,
  required BdoNodeNetworkRequest request,
  required BdoNodeNetworkOptimizationMode mode,
  required Set<int> roots,
  required Map<String, int> resolvedCounts,
  required Set<String> knownCurrentIds,
  required _NetworkSolution solution,
}) {
  final targetIndexes = <int>{...solution.nodeIndexes};
  final degree = <int, int>{};
  for (final edge in solution.edges) {
    degree.update(edge.first, (value) => value + 1, ifAbsent: () => 1);
    degree.update(edge.second, (value) => value + 1, ifAbsent: () => 1);
  }
  targetIndexes.removeWhere(
    (index) =>
        roots.contains(index) &&
        !solution.terminalIndexes.contains(index) &&
        (degree[index] ?? 0) == 0,
  );
  final investedTargetIndexes = targetIndexes.difference(roots);
  for (final root in roots) {
    if (graph.adjacency[root].any(investedTargetIndexes.contains)) {
      targetIndexes.add(root);
    }
  }
  final targetEdges = _inducedNetworkEdges(
    graph: graph,
    nodeIndexes: targetIndexes,
    roots: roots,
  );

  final targetIds = targetIndexes.map((index) => graph.nodes[index].id).toSet();
  final rootIds = roots.map((index) => graph.nodes[index].id).toSet();
  final comparableTargetIds = targetIds.difference(rootIds);
  final comparableCurrentIds = knownCurrentIds.difference(rootIds);

  final retainedIds = comparableTargetIds.intersection(comparableCurrentIds);
  final connectIds = comparableTargetIds.difference(comparableCurrentIds);
  final disconnectIds = comparableCurrentIds.difference(comparableTargetIds);

  final currentIndexes = <int>{
    ...roots,
    ...knownCurrentIds.map((id) => graph.indexById[id]).whereType<int>(),
  };
  final currentEdges = _inducedNetworkEdges(
    graph: graph,
    nodeIndexes: currentIndexes,
    roots: roots,
  );

  final edgeChanges = <BdoNodeNetworkEdgeChange>[];
  final allEdges = <_IndexEdge>{...currentEdges, ...targetEdges}.toList()
    ..sort();
  for (final edge in allEdges) {
    final inCurrent = currentEdges.contains(edge);
    final inTarget = targetEdges.contains(edge);
    final kind = inCurrent && inTarget
        ? BdoNodeNetworkChangeKind.retained
        : inTarget
        ? BdoNodeNetworkChangeKind.connect
        : BdoNodeNetworkChangeKind.disconnect;
    edgeChanges.add(
      BdoNodeNetworkEdgeChange(
        firstNodeId: graph.nodes[edge.first].id,
        secondNodeId: graph.nodes[edge.second].id,
        kind: kind,
      ),
    );
  }

  int cpForIds(Iterable<String> ids) => ids.fold<int>(
    0,
    (total, id) => total + graph.nodes[graph.indexById[id]!].contributionPoints,
  );

  final totalCp = cpForIds(comparableTargetIds);
  final currentCp = cpForIds(comparableCurrentIds);
  final selectedProductionIndexes = targetIndexes
      .where(
        (index) =>
            graph.nodes[index].isResourceNode &&
            graph.nodes[index].isProductionNode,
      )
      .toList();
  final byResource = <String, List<String>>{};
  for (final resourceId in resolvedCounts.keys) {
    final nodeIds = selectedProductionIndexes
        .where(
          (index) => graph.nodes[index].outputs.any(
            (output) => output.resourceId == resourceId,
          ),
        )
        .map((index) => graph.nodes[index].id)
        .toList();
    byResource[resourceId] = _sortIds(nodeIds);
  }

  final selectedRootIds = targetIndexes
      .where(roots.contains)
      .map((index) => graph.nodes[index].id);
  final selectedProductionIds = selectedProductionIndexes.map(
    (index) => graph.nodes[index].id,
  );

  return BdoNodeNetworkPlan(
    optimizationMode: mode,
    contributionPointBudget: request.contributionPointBudget,
    totalContributionPoints: totalCp,
    currentContributionPoints: currentCp,
    requestedNodeCountByResource: Map<String, int>.unmodifiable(
      SplayTreeMap<String, int>.from(resolvedCounts),
    ),
    workerNodeIdsByResource: Map<String, List<String>>.unmodifiable(
      SplayTreeMap<String, List<String>>.from(byResource),
    ),
    selectedNodeIds: _sortIds(targetIds),
    selectedRootNodeIds: _sortIds(selectedRootIds),
    selectedProductionNodeIds: _sortIds(selectedProductionIds),
    changeSet: BdoNodeNetworkChangeSet(
      retainedNodeIds: _sortIds(retainedIds),
      connectNodeIds: _sortIds(connectIds),
      disconnectNodeIds: _sortIds(disconnectIds),
      edges: List<BdoNodeNetworkEdgeChange>.unmodifiable(edgeChanges),
      connectContributionPoints: cpForIds(connectIds),
      disconnectContributionPoints: cpForIds(disconnectIds),
    ),
  );
}

Set<_IndexEdge> _inducedNetworkEdges({
  required _NetworkGraph graph,
  required Set<int> nodeIndexes,
  required Set<int> roots,
}) {
  final edges = <_IndexEdge>{};
  for (final first in nodeIndexes.toList()..sort()) {
    for (final second in graph.adjacency[first]) {
      if (first >= second ||
          !nodeIndexes.contains(second) ||
          (roots.contains(first) && roots.contains(second))) {
        continue;
      }
      edges.add(_IndexEdge(first, second));
    }
  }
  return edges;
}

class _NetworkGraph {
  _NetworkGraph(List<BdoWorkerNode> unsortedNodes)
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
    // Production sites are endpoint investments, never connection hubs. Keep
    // only their recorded real parent edge. A legacy/custom record without a
    // parent remains usable when it has exactly one unambiguous non-production
    // link; ambiguous multi-link records fail normal reachability validation
    // instead of becoming illegal shortcuts.
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      if (!node.isProductionNode) {
        continue;
      }
      final nonProductionNeighbors =
          neighborSets[index]
              .where((neighbor) => !nodes[neighbor].isProductionNode)
              .toList()
            ..sort();
      int? attachment;
      final parentId = node.parentId;
      if (parentId != null) {
        final parent = indexById[parentId];
        if (parent != null &&
            !nodes[parent].isProductionNode &&
            neighborSets[index].contains(parent)) {
          attachment = parent;
        }
      } else if (nonProductionNeighbors.length == 1) {
        attachment = nonProductionNeighbors.single;
      }
      for (final neighbor in neighborSets[index].toList()) {
        if (neighbor == attachment) {
          continue;
        }
        neighborSets[index].remove(neighbor);
        neighborSets[neighbor].remove(index);
      }
    }
    for (var index = 0; index < nodes.length; index++) {
      adjacency[index] = neighborSets[index].toList()..sort();
    }
  }

  final List<BdoWorkerNode> nodes;
  final Map<String, int> indexById;
  final List<List<int>> adjacency;

  int get maxSafeContributionPoints {
    if (nodes.isEmpty) {
      return _infinity - 1;
    }
    final nodeCount = nodes.length;
    final scale = nodeCount + 1;
    return (_infinity - 1 - nodeCount) ~/ (nodeCount * scale);
  }

  List<int> resourceCandidateIndexes(String resourceId) {
    return <int>[
      for (var index = 0; index < nodes.length; index++)
        if (nodes[index].isResourceNode &&
            nodes[index].isProductionNode &&
            nodes[index].outputs.any(
              (output) => output.resourceId == resourceId,
            ))
          index,
    ];
  }

  Set<int> reachableNonProductionNodes(Set<int> roots) {
    final reachable = <int>{};
    final queue = Queue<int>();
    for (final root in roots.toList()..sort()) {
      reachable.add(root);
      queue.add(root);
    }
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final neighbor in adjacency[current]) {
        if (reachable.contains(neighbor)) {
          continue;
        }
        if (nodes[neighbor].isProductionNode && !roots.contains(neighbor)) {
          continue;
        }
        reachable.add(neighbor);
        queue.add(neighbor);
      }
    }
    return reachable;
  }

  bool productionNodeIsReachable(
    int candidate, {
    required Set<int> roots,
    required Set<int> reachableBase,
  }) {
    if (roots.contains(candidate) || reachableBase.contains(candidate)) {
      return true;
    }
    return adjacency[candidate].any(reachableBase.contains);
  }

  Int64List compositeWeights({
    required Set<int> roots,
    required Set<int> currentIndexes,
    required int scale,
  }) {
    final weights = Int64List(nodes.length + 1);
    for (var index = 0; index < nodes.length; index++) {
      if (roots.contains(index)) {
        weights[index] = 0;
      } else {
        weights[index] = _saturatingCompositeValue(
          nodes[index].contributionPoints * scale +
              (currentIndexes.contains(index) ? 0 : 1),
        );
      }
    }
    weights[nodes.length] = 0;
    return weights;
  }
}

class _SteinerSolver {
  _SteinerSolver({
    required this.graph,
    required this.roots,
    required List<int> terminals,
    required Set<String> currentIds,
    required this.recordTrace,
  }) : terminalGroups = List<List<int>>.unmodifiable(
         terminals.map((terminal) => List<int>.unmodifiable(<int>[terminal])),
       ),
       currentIndexes = currentIds
           .map((id) => graph.indexById[id])
           .whereType<int>()
           .toSet(),
       scale = graph.nodes.length + 1;

  _SteinerSolver.forTerminalGroups({
    required this.graph,
    required this.roots,
    required List<List<int>> terminalGroups,
    required Set<String> currentIds,
    required this.recordTrace,
  }) : terminalGroups = List<List<int>>.unmodifiable(
         terminalGroups.map(
           (group) => List<int>.unmodifiable(group.toSet().toList()..sort()),
         ),
       ),
       currentIndexes = currentIds
           .map((id) => graph.indexById[id])
           .whereType<int>()
           .toSet(),
       scale = graph.nodes.length + 1;

  final _NetworkGraph graph;
  final Set<int> roots;
  final List<List<int>> terminalGroups;
  final Set<int> currentIndexes;
  final bool recordTrace;
  final int scale;

  int solveCost() => _run().cost;

  _NetworkSolution solveWithTrace() {
    final run = _run();
    if (run.traceTypes == null || run.traceValues == null) {
      throw StateError('Steiner trace was not recorded.');
    }
    final nodeIndexes = <int>{};
    final edges = <_IndexEdge>{};
    final visitedStates = <int>{};
    final selectedTerminalIndexes = <int>{};
    final vertexCount = graph.nodes.length + 1;
    final virtualRoot = graph.nodes.length;
    final fullMask = (1 << terminalGroups.length) - 1;

    void visit(int mask, int vertex) {
      final stateKey = mask * vertexCount + vertex;
      if (!visitedStates.add(stateKey)) {
        return;
      }
      if (vertex != virtualRoot) {
        nodeIndexes.add(vertex);
      }
      final type = run.traceTypes![mask][vertex];
      final value = run.traceValues![mask][vertex];
      switch (type) {
        case _traceSeed:
          if (vertex != virtualRoot) {
            selectedTerminalIndexes.add(vertex);
          }
          return;
        case _traceMerge:
          visit(value, vertex);
          visit(mask ^ value, vertex);
          return;
        case _traceMove:
          visit(mask, value);
          if (vertex != virtualRoot && value != virtualRoot) {
            edges.add(_IndexEdge(vertex, value));
          }
          return;
        default:
          throw StateError(
            'Missing Steiner trace for mask $mask at vertex $vertex.',
          );
      }
    }

    visit(fullMask, virtualRoot);
    return _NetworkSolution(
      nodeIndexes: Set<int>.unmodifiable(nodeIndexes),
      edges: Set<_IndexEdge>.unmodifiable(edges),
      terminalIndexes: Set<int>.unmodifiable(selectedTerminalIndexes),
    );
  }

  _SteinerRun _run() {
    if (terminalGroups.isEmpty) {
      return _SteinerRun(
        cost: 0,
        traceTypes: recordTrace ? <Uint8List>[Uint8List(1)] : null,
        traceValues: recordTrace ? <Int32List>[Int32List(1)] : null,
      );
    }
    final realCount = graph.nodes.length;
    final virtualRoot = realCount;
    final vertexCount = realCount + 1;
    final stateCount = 1 << terminalGroups.length;
    final weights = graph.compositeWeights(
      roots: roots,
      currentIndexes: currentIndexes,
      scale: scale,
    );
    final expandedAdjacency = <List<int>>[
      for (final neighbors in graph.adjacency) List<int>.of(neighbors),
      roots.toList()..sort(),
    ];
    for (final root in roots) {
      expandedAdjacency[root].add(virtualRoot);
      expandedAdjacency[root].sort();
    }

    final distances = List<Int64List>.generate(stateCount, (_) {
      final values = Int64List(vertexCount);
      values.fillRange(0, vertexCount, _infinity);
      return values;
    });
    final traceTypes = recordTrace
        ? List<Uint8List>.generate(stateCount, (_) => Uint8List(vertexCount))
        : null;
    final traceValues = recordTrace
        ? List<Int32List>.generate(stateCount, (_) {
            final values = Int32List(vertexCount);
            values.fillRange(0, vertexCount, -1);
            return values;
          })
        : null;
    final terminalSet = terminalGroups.expand((group) => group).toSet();

    bool allowed(int vertex) =>
        vertex == virtualRoot ||
        roots.contains(vertex) ||
        !graph.nodes[vertex].isProductionNode ||
        terminalSet.contains(vertex);

    for (var mask = 1; mask < stateCount; mask++) {
      final distance = distances[mask];
      if (_isPowerOfTwo(mask)) {
        final terminalBit = mask.bitLength - 1;
        for (final terminal in terminalGroups[terminalBit]) {
          distance[terminal] = weights[terminal];
          if (recordTrace) {
            traceTypes![mask][terminal] = _traceSeed;
          }
        }
      } else {
        for (var submask = 1; submask < mask; submask++) {
          if ((submask & mask) != submask) {
            continue;
          }
          final complement = mask ^ submask;
          if (submask >= complement) {
            continue;
          }
          final left = distances[submask];
          final right = distances[complement];
          for (var vertex = 0; vertex < vertexCount; vertex++) {
            if (!allowed(vertex) ||
                left[vertex] >= _infinity ||
                right[vertex] >= _infinity) {
              continue;
            }
            final candidate = _saturatingMergedCost(
              left[vertex],
              right[vertex],
              weights[vertex],
            );
            if (candidate < distance[vertex]) {
              distance[vertex] = candidate;
              if (recordTrace) {
                traceTypes![mask][vertex] = _traceMerge;
                traceValues![mask][vertex] = submask;
              }
            }
          }
        }
      }

      final heap = _MinHeap();
      for (var vertex = 0; vertex < vertexCount; vertex++) {
        if (distance[vertex] < _infinity) {
          heap.add(_HeapEntry(vertex: vertex, cost: distance[vertex]));
        }
      }
      while (heap.isNotEmpty) {
        final entry = heap.removeFirst();
        if (entry.cost != distance[entry.vertex]) {
          continue;
        }
        for (final neighbor in expandedAdjacency[entry.vertex]) {
          if (!allowed(neighbor)) {
            continue;
          }
          final candidate = _saturatingCostSum(entry.cost, weights[neighbor]);
          if (candidate < distance[neighbor]) {
            distance[neighbor] = candidate;
            if (recordTrace) {
              traceTypes![mask][neighbor] = _traceMove;
              traceValues![mask][neighbor] = entry.vertex;
            }
            heap.add(_HeapEntry(vertex: neighbor, cost: candidate));
          }
        }
      }
    }

    return _SteinerRun(
      cost: distances[stateCount - 1][virtualRoot],
      traceTypes: traceTypes,
      traceValues: traceValues,
    );
  }
}

class _SteinerRun {
  const _SteinerRun({
    required this.cost,
    required this.traceTypes,
    required this.traceValues,
  });

  final int cost;
  final List<Uint8List>? traceTypes;
  final List<Int32List>? traceValues;
}

class _ResolvedRequirement {
  const _ResolvedRequirement({
    required this.resourceId,
    required this.count,
    required this.candidateIndexes,
  });

  final String resourceId;
  final int count;
  final List<int> candidateIndexes;
}

class _ExactTerminalSets {
  const _ExactTerminalSets({
    required this.values,
    required this.terminalLimitExceeded,
    required this.selectionLimitExceeded,
  });

  final List<List<int>> values;
  final bool terminalLimitExceeded;
  final bool selectionLimitExceeded;
}

class _ScalablePathChoice {
  const _ScalablePathChoice({
    required this.targetIndex,
    required this.marginalCost,
    required this.newlyCoveredGroupCount,
    required this.path,
  });

  final int targetIndex;
  final int marginalCost;
  final int newlyCoveredGroupCount;
  final _ScalablePath path;
}

class _ScalablePath {
  const _ScalablePath({required this.nodeIndexes, required this.edges});

  final Set<int> nodeIndexes;
  final Set<_IndexEdge> edges;
}

class _ShortestPathTree {
  const _ShortestPathTree({
    required this.distances,
    required this.parents,
    required this.sources,
  });

  final Int64List distances;
  final Int32List parents;
  final Set<int> sources;

  _ScalablePath pathTo(int target) {
    if (distances[target] >= _infinity) {
      throw StateError('Cannot trace an unreachable scalable-route target.');
    }
    final nodes = <int>{target};
    final edges = <_IndexEdge>{};
    var current = target;
    while (!sources.contains(current)) {
      final parent = parents[current];
      if (parent < 0) {
        throw StateError(
          'Scalable shortest-path trace ended before reaching the network.',
        );
      }
      nodes.add(parent);
      edges.add(_IndexEdge(current, parent));
      current = parent;
    }
    return _ScalablePath(
      nodeIndexes: Set<int>.unmodifiable(nodes),
      edges: Set<_IndexEdge>.unmodifiable(edges),
    );
  }
}

class _NetworkSolution {
  const _NetworkSolution({
    required this.nodeIndexes,
    required this.edges,
    required this.terminalIndexes,
  });

  final Set<int> nodeIndexes;
  final Set<_IndexEdge> edges;
  final Set<int> terminalIndexes;
}

class _IndexEdge implements Comparable<_IndexEdge> {
  _IndexEdge(int first, int second)
    : first = math.min(first, second),
      second = math.max(first, second);

  final int first;
  final int second;

  @override
  int compareTo(_IndexEdge other) {
    final firstComparison = first.compareTo(other.first);
    return firstComparison != 0
        ? firstComparison
        : second.compareTo(other.second);
  }

  @override
  bool operator ==(Object other) =>
      other is _IndexEdge && first == other.first && second == other.second;

  @override
  int get hashCode => Object.hash(first, second);
}

class _HeapEntry {
  const _HeapEntry({required this.vertex, required this.cost});

  final int vertex;
  final int cost;
}

class _MinHeap {
  final List<_HeapEntry> _values = <_HeapEntry>[];

  bool get isNotEmpty => _values.isNotEmpty;

  void add(_HeapEntry value) {
    _values.add(value);
    var index = _values.length - 1;
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (!_less(value, _values[parent])) {
        break;
      }
      _values[index] = _values[parent];
      index = parent;
    }
    _values[index] = value;
  }

  _HeapEntry removeFirst() {
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
      var child = right < _values.length && _less(_values[right], _values[left])
          ? right
          : left;
      if (!_less(_values[child], last)) {
        break;
      }
      _values[index] = _values[child];
      index = child;
    }
    _values[index] = last;
    return first;
  }

  bool _less(_HeapEntry left, _HeapEntry right) =>
      left.cost < right.cost ||
      (left.cost == right.cost && left.vertex < right.vertex);
}

bool _isPowerOfTwo(int value) => value > 0 && (value & (value - 1)) == 0;

int _saturatingCompositeValue(int value) {
  if (value < 0) {
    throw StateError('Composite network costs cannot be negative.');
  }
  return value >= _infinity ? _infinity : value;
}

int _saturatingCostSum(int left, int right) {
  if (left >= _infinity || right >= _infinity) {
    return _infinity;
  }
  return _saturatingCompositeValue(left + right);
}

int _saturatingMergedCost(int left, int right, int sharedWeight) {
  if (left >= _infinity || right >= _infinity) {
    return _infinity;
  }
  return _saturatingCompositeValue(left + right - sharedWeight);
}

int _compareIntLists(List<int> left, List<int> right) {
  final sharedLength = math.min(left.length, right.length);
  for (var index = 0; index < sharedLength; index++) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) {
      return comparison;
    }
  }
  return left.length.compareTo(right.length);
}

int _compareEdgeLists(List<_IndexEdge> left, List<_IndexEdge> right) {
  final sharedLength = math.min(left.length, right.length);
  for (var index = 0; index < sharedLength; index++) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) {
      return comparison;
    }
  }
  return left.length.compareTo(right.length);
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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

const _infinity = 0x3fffffffffffffff;
const _traceSeed = 1;
const _traceMerge = 2;
const _traceMove = 3;
