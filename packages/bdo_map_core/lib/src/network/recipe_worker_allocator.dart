import 'dart:math' as math;

import '../economics/worker_economics_data.dart';
import '../model/resource_map_data.dart';
import 'node_network_models.dart';
import 'production_node_path_cost.dart';

/// One complete-chain leaf. Alternatives are real recipe substitutions: a
/// resource's multiplier converts its output into units of this requirement.
class BdoWorkerRecipeDemand {
  BdoWorkerRecipeDemand({
    required this.id,
    required this.name,
    required this.quantity,
    required Map<String, double> resourceUnits,
  }) : resourceUnits = Map.unmodifiable(resourceUnits);
  final String id;
  final String name;
  final double quantity;
  final Map<String, double> resourceUnits;
}

class BdoRecipeWorkerPlan {
  BdoRecipeWorkerPlan({
    required this.budget,
    required this.demands,
    required Map<String, BdoProductionNodePath> paths,
    required Map<String, Map<String, double>> rates,
    required this.costs,
  }) : paths = Map.unmodifiable(paths),
       rates = Map.unmodifiable(rates);
  final int budget;
  final List<BdoWorkerRecipeDemand> demands;
  final Map<String, BdoProductionNodePath> paths;
  final Map<String, Map<String, double>> rates;
  final Map<String, int> costs;
  Set<String> get nodeIds => {
    for (final p in paths.values) ...p.orderedNodeIds,
  };
  int get spent => nodeIds.fold(0, (sum, id) => sum + (costs[id] ?? 0));
  int get remaining => budget - spent;
  List<String> nodesFor(String demandId) =>
      paths.keys.where((id) => (rates[id]?[demandId] ?? 0) > 0).toList()
        ..sort();
  double coverage(BdoWorkerRecipeDemand d) =>
      paths.keys.fold<double>(0, (sum, id) => sum + (rates[id]?[d.id] ?? 0)) /
      d.quantity;
  BdoNodeNetworkPlan get network {
    final ids = nodeIds.toList()..sort();
    final edges = <String, BdoNodeNetworkEdgeChange>{};
    for (final path in paths.values) {
      for (final edge in path.edges) {
        final pair = [edge.fromNodeId, edge.toNodeId]..sort();
        edges[pair.join('\u0000')] = BdoNodeNetworkEdgeChange(
          firstNodeId: pair[0],
          secondNodeId: pair[1],
          kind: BdoNodeNetworkChangeKind.connect,
        );
      }
    }
    return BdoNodeNetworkPlan(
      optimizationMode: BdoNodeNetworkOptimizationMode.scalable,
      contributionPointBudget: budget,
      totalContributionPoints: spent,
      currentContributionPoints: 0,
      requestedNodeCountByResource: {
        for (final d in demands) d.id: nodesFor(d.id).length,
      },
      workerNodeIdsByResource: {for (final d in demands) d.id: nodesFor(d.id)},
      selectedNodeIds: ids,
      selectedRootNodeIds:
          paths.values.map((p) => p.rootNodeId).toSet().toList()..sort(),
      selectedProductionNodeIds: paths.keys.toList()..sort(),
      changeSet: BdoNodeNetworkChangeSet(
        retainedNodeIds: const [],
        connectNodeIds: ids,
        disconnectNodeIds: const [],
        edges: edges.values.toList(),
        connectContributionPoints: spent,
        disconnectContributionPoints: 0,
      ),
    );
  }
}

/// Deterministic, budget-bounded bottleneck-first allocation, not a claim of a
/// globally optimal worker simulation. Standard yield / base workload is used
/// only to compare relative supply. No worker stats, market prices, inventory,
/// lucky bonuses, paid slots or personalized output forecasts enter the score.
/// The budget covers production and connection nodes, not worker lodging.
class BdoRecipeWorkerAllocator {
  BdoRecipeWorkerAllocator({
    required this.data,
    required this.economics,
    required Iterable<BdoWorkerRecipeDemand> demands,
    Set<String>? roots,
  }) : demands = List.unmodifiable(demands),
       roots = Set.unmodifiable(
         (roots ?? economics.verifiedFreeNetworkRootNodeIds(data)).intersection(
           economics.verifiedFreeNetworkRootNodeIds(data),
         ),
       ),
       costs = Map.unmodifiable({
         for (final n in data.workerNodes) n.id: n.contributionPoints,
       }) {
    if (costs.values.any((cp) => cp < 0)) {
      throw ArgumentError('Invalid node CP');
    }
    if (this.demands.map((d) => d.id).toSet().length != this.demands.length ||
        this.demands.any(
          (d) =>
              !d.quantity.isFinite ||
              d.quantity <= 0 ||
              d.resourceUnits.values.any((v) => !v.isFinite || v <= 0),
        )) {
      throw ArgumentError('Invalid recipe demand');
    }
    final relevantIds = {
      for (final node in data.workerNodes)
        if (node.isProductionNode &&
            node.outputs.any(
              (o) => this.demands.any(
                (d) => d.resourceUnits.containsKey(o.resourceId),
              ),
            ))
          node.id,
    };
    for (final production in economics.productionNodesById.values.where(
      (p) => relevantIds.contains(p.nodeId),
    )) {
      _eligibleRoots[production.nodeId] = this.roots.where((id) {
        final town = economics.townsByNodeId[id];
        return production.townDistances.containsKey(id) &&
            town != null &&
            town.profiles.any(
              (p) => production.workerTypes.contains(p.workerType),
            );
      }).toSet();
    }
    final initial = _paths(const {});
    for (final node in data.workerNodes.where((n) => n.isProductionNode)) {
      final base = economics.productionNodesById[node.id];
      if (base == null ||
          base.baseWorkload <= 0 ||
          !base.baseWorkload.isFinite ||
          initial[node.id]?.minimumIncrementalPath == null) {
        continue;
      }
      // Missing/partial economics never become a fabricated one-node estimate.
      final values = <String, double>{};
      for (final demand in this.demands) {
        var quantity = 0.0;
        final seen = <int>{};
        for (final output in node.outputs) {
          final itemId = output.gameItemId;
          if (itemId == null || !seen.add(itemId)) continue;
          quantity +=
              (base.standardYields[itemId] ?? 0) *
              (demand.resourceUnits[output.resourceId] ?? 0);
        }
        final rate = quantity / base.baseWorkload;
        if (rate.isFinite && rate > 0) values[demand.id] = rate;
      }
      if (values.isNotEmpty) rates[node.id] = Map.unmodifiable(values);
    }
  }
  final BdoResourceMapDataset data;
  final BdoWorkerEconomicsDataset economics;
  final List<BdoWorkerRecipeDemand> demands;
  final Set<String> roots;
  final Map<String, int> costs;
  final Map<String, Map<String, double>> rates = {};
  final Map<String, Set<String>> _eligibleRoots = {};
  static const _pathService = BdoProductionNodePathCostService();
  Map<String, BdoProductionNodePathResult> _paths(Set<String> current) {
    final results = Map<String, BdoProductionNodePathResult>.of(
      _pathService.calculateAll(
        data: data,
        currentNodeIds: current,
        allowedRootNodeIds: roots,
      ),
    );
    for (final entry in _eligibleRoots.entries) {
      final path = results[entry.key]?.minimumIncrementalPath;
      if (path != null && !entry.value.contains(path.rootNodeId)) {
        results[entry.key] = _pathService.calculate(
          data: data,
          request: BdoProductionNodePathRequest(
            targetNodeId: entry.key,
            currentNodeIds: current,
            allowedRootNodeIds: entry.value,
          ),
        );
      }
    }
    return results;
  }

  BdoRecipeWorkerPlan _plan(
    int budget,
    Map<String, BdoProductionNodePath> paths,
  ) => BdoRecipeWorkerPlan(
    budget: budget,
    demands: demands,
    paths: paths,
    rates: rates,
    costs: costs,
  );
  int available(String id) =>
      rates.values.where((r) => (r[id] ?? 0) > 0).length;

  BdoRecipeWorkerPlan allocate(
    int budget, {
    Set<String> seedNodeIds = const {},
    Set<String>? automaticDemandIds,
  }) {
    if (budget < 0) throw ArgumentError.value(budget, 'budget');
    var plan = restore(budget, seedNodeIds);
    // Every iteration adds exactly one distinct production site. Shared route
    // vertices cost zero incrementally, but remain charged once in total CP.
    while (true) {
      final next = add(plan, automaticDemandIds: automaticDemandIds);
      if (next == null) return plan;
      plan = next;
    }
  }

  /// Reconnect only the saved proposal's sites. Never invest the current-game
  /// network or silently replenish a deliberately removed material on restart.
  BdoRecipeWorkerPlan restore(int budget, Set<String> nodeIds) {
    var plan = _plan(budget, {});
    for (final id in nodeIds) {
      if (!rates.containsKey(id)) continue;
      final path = _paths(plan.nodeIds)[id]?.minimumIncrementalPath;
      if (path != null &&
          path.incrementalContributionPoints <= plan.remaining) {
        plan = _plan(budget, {...plan.paths, id: path});
      }
    }
    return plan;
  }

  BdoRecipeWorkerPlan? add(
    BdoRecipeWorkerPlan plan, {
    String? demandId,
    Set<String>? automaticDemandIds,
  }) {
    final paths = _paths(plan.nodeIds);
    BdoProductionNodePath? best;
    var bestScore = -1.0;
    var bestBottleneck = double.infinity;
    for (final id in rates.keys.toList()..sort()) {
      if (plan.paths.containsKey(id) ||
          (automaticDemandIds != null &&
              !automaticDemandIds.any((d) => (rates[id]?[d] ?? 0) > 0)) ||
          (demandId != null && (rates[id]?[demandId] ?? 0) <= 0)) {
        continue;
      }
      final path = paths[id]?.minimumIncrementalPath;
      if (path == null || path.incrementalContributionPoints > plan.remaining) {
        continue;
      }
      var gain = 0.0;
      var bottleneck = double.infinity;
      for (final d in demands) {
        if (automaticDemandIds != null && !automaticDemandIds.contains(d.id)) {
          continue;
        }
        final delta = (rates[id]?[d.id] ?? 0) / d.quantity;
        if (delta > 0) {
          final coverage = plan.coverage(d);
          if (coverage < bottleneck - 1e-12) {
            bottleneck = coverage;
            gain = delta;
          } else if ((coverage - bottleneck).abs() < 1e-12) {
            gain += delta;
          }
        }
      }
      final score = gain / math.max(1, path.incrementalContributionPoints);
      if (bottleneck < bestBottleneck - 1e-12 ||
          ((bottleneck - bestBottleneck).abs() < 1e-12 &&
              (score > bestScore + 1e-12 ||
                  ((score - bestScore).abs() < 1e-12 &&
                      best != null &&
                      path.incrementalContributionPoints <
                          best.incrementalContributionPoints)))) {
        best = path;
        bestScore = score;
        bestBottleneck = bottleneck;
      }
    }
    if (best == null) return null;
    final next = _plan(plan.budget, {...plan.paths, best.targetNodeId: best});
    assert(next.remaining >= 0);
    return next;
  }

  BdoRecipeWorkerPlan? remove(BdoRecipeWorkerPlan plan, String demandId) {
    BdoRecipeWorkerPlan? best;
    List<double>? bestCoverage;
    for (final id in plan.nodesFor(demandId)) {
      final next = _plan(plan.budget, {...plan.paths}..remove(id));
      final coverage =
          demands.where((d) => available(d.id) > 0).map(next.coverage).toList()
            ..sort();
      final comparison = bestCoverage == null
          ? 1
          : _compare(coverage, bestCoverage);
      if (comparison > 0 || (comparison == 0 && next.spent < best!.spent)) {
        best = next;
        bestCoverage = coverage;
      }
    }
    return best;
  }

  static int _compare(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-12) return a[i].compareTo(b[i]);
    }
    return 0;
  }
}
