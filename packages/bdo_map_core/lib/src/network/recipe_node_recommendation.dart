import 'dart:collection';

import '../model/planner_material_need.dart';
import '../model/resource_map_data.dart';
import 'node_network_models.dart';
import 'node_network_optimizer.dart';

/// A positive leaf-material shortage produced by the craft planner.
///
/// [missingQuantity] is retained for presentation and prioritization only. The
/// map dataset does not contain worker cycle time, yield, worker stats, or
/// lodging costs, so it would be misleading to turn an item quantity into a
/// production-node count.
class BdoRecipeLeafShortage {
  const BdoRecipeLeafShortage({
    required this.name,
    required this.missingQuantity,
    this.gameItemId,
  });

  factory BdoRecipeLeafShortage.fromPlannerNeed(BdoPlannerMaterialNeed need) {
    return BdoRecipeLeafShortage(
      name: need.name,
      missingQuantity: need.missingQuantity,
      gameItemId: need.gameItemId,
    );
  }

  final String name;
  final double missingQuantity;
  final int? gameItemId;
}

/// An explicit desired number of distinct production nodes for one material.
///
/// This count is not an item quantity, hourly output, or worker-cycle target.
class BdoRecipeNodeMaterialTarget {
  const BdoRecipeNodeMaterialTarget({
    required this.query,
    this.distinctProductionNodeCount = 1,
    this.gameItemId,
  });

  /// Canonical resource ID, resource name, alias, or worker-output name.
  final String query;
  final int? gameItemId;
  final int distinctProductionNodeCount;
}

/// Inputs for a minimum-CP recipe-coverage recommendation.
class BdoRecipeNodeRecommendationRequest {
  BdoRecipeNodeRecommendationRequest({
    required this.contributionPointBudget,
    Iterable<BdoRecipeLeafShortage> recipeLeafShortages =
        const <BdoRecipeLeafShortage>[],
    Iterable<BdoRecipeNodeMaterialTarget> materialTargets =
        const <BdoRecipeNodeMaterialTarget>[],
    Set<String> currentNodeIds = const <String>{},
    Set<String>? rootNodeIds,
    this.maxExactTerminalNodes = 10,
    this.maxExactSelectionCombinations = 256,
  }) : recipeLeafShortages = List<BdoRecipeLeafShortage>.unmodifiable(
         recipeLeafShortages,
       ),
       materialTargets = List<BdoRecipeNodeMaterialTarget>.unmodifiable(
         materialTargets,
       ),
       currentNodeIds = Set<String>.unmodifiable(currentNodeIds),
       rootNodeIds = rootNodeIds == null
           ? null
           : Set<String>.unmodifiable(rootNodeIds);

  factory BdoRecipeNodeRecommendationRequest.fromPlannerNeeds({
    required int contributionPointBudget,
    required Iterable<BdoPlannerMaterialNeed> needs,
    Iterable<BdoRecipeNodeMaterialTarget> materialTargets =
        const <BdoRecipeNodeMaterialTarget>[],
    Set<String> currentNodeIds = const <String>{},
    Set<String>? rootNodeIds,
    int maxExactTerminalNodes = 10,
    int maxExactSelectionCombinations = 256,
  }) {
    return BdoRecipeNodeRecommendationRequest(
      contributionPointBudget: contributionPointBudget,
      recipeLeafShortages: needs.map(BdoRecipeLeafShortage.fromPlannerNeed),
      materialTargets: materialTargets,
      currentNodeIds: currentNodeIds,
      rootNodeIds: rootNodeIds,
      maxExactTerminalNodes: maxExactTerminalNodes,
      maxExactSelectionCombinations: maxExactSelectionCombinations,
    );
  }

  final int contributionPointBudget;
  final List<BdoRecipeLeafShortage> recipeLeafShortages;
  final List<BdoRecipeNodeMaterialTarget> materialTargets;
  final Set<String> currentNodeIds;

  /// Null lets the optimizer use every mapped zero-CP city and town.
  final Set<String>? rootNodeIds;
  final int maxExactTerminalNodes;
  final int maxExactSelectionCombinations;
}

/// Why an input material could not be included in worker-node coverage.
enum BdoRecipeNodeUncoveredReason {
  invalidMaterialReference,
  invalidShortageQuantity,
  invalidDistinctProductionNodeCount,
  unmatchedMaterial,
  ambiguousMaterial,
  noWorkerProductionNodes,
}

/// One invalid, unmatched, ambiguous, or worker-unsupported material input.
class BdoRecipeNodeUncoveredMaterial {
  BdoRecipeNodeUncoveredMaterial({
    required this.reason,
    required this.query,
    required this.message,
    this.gameItemId,
    this.missingQuantity,
    this.distinctProductionNodeCount,
    Iterable<String> candidateResourceIds = const <String>[],
  }) : candidateResourceIds = List<String>.unmodifiable(
         candidateResourceIds.toSet().toList()..sort(),
       );

  final BdoRecipeNodeUncoveredReason reason;
  final String query;
  final String message;
  final int? gameItemId;
  final double? missingQuantity;
  final int? distinctProductionNodeCount;
  final List<String> candidateResourceIds;
}

/// One canonical material requirement sent to the network optimizer.
class BdoRecipeNodeCoverageTarget {
  BdoRecipeNodeCoverageTarget({
    required this.resourceId,
    required this.resourceName,
    required this.requestedDistinctProductionNodeCount,
    required this.availableDistinctProductionNodeCount,
    required this.hasRecipeShortage,
    required this.hasExplicitMaterialTarget,
    required Iterable<String> inputLabels,
    this.gameItemId,
    this.totalRecipeShortageQuantity,
    this.recipeShortageInputCount = 0,
    this.explicitMaterialTargetInputCount = 0,
  }) : inputLabels = List<String>.unmodifiable(inputLabels);

  final String resourceId;
  final String resourceName;
  final int? gameItemId;

  /// Absolute desired production-node count, not output quantity.
  final int requestedDistinctProductionNodeCount;
  final int availableDistinctProductionNodeCount;

  /// Sum of matching leaf shortages, retained for display only.
  final double? totalRecipeShortageQuantity;
  final bool hasRecipeShortage;
  final bool hasExplicitMaterialTarget;
  final List<String> inputLabels;

  /// Number of original planner rows represented by this canonical resource.
  ///
  /// This can be greater than one when Cooking and Alchemy both require the
  /// same material. It is separate from [inputLabels], which intentionally
  /// deduplicates identical display labels.
  final int recipeShortageInputCount;

  /// Number of explicit node-count targets represented by this resource.
  final int explicitMaterialTargetInputCount;
}

/// Network result plus transparent material-coverage diagnostics.
class BdoRecipeNodeRecommendation {
  BdoRecipeNodeRecommendation({
    required Iterable<BdoRecipeNodeCoverageTarget> coverageTargets,
    required Iterable<BdoRecipeNodeUncoveredMaterial> uncoveredMaterials,
    required this.networkResult,
  }) : coverageTargets = List<BdoRecipeNodeCoverageTarget>.unmodifiable(
         coverageTargets,
       ),
       uncoveredMaterials = List<BdoRecipeNodeUncoveredMaterial>.unmodifiable(
         uncoveredMaterials,
       );

  final List<BdoRecipeNodeCoverageTarget> coverageTargets;
  final List<BdoRecipeNodeUncoveredMaterial> uncoveredMaterials;

  /// Null when no valid material has a mapped worker-production node.
  final BdoNodeNetworkResult? networkResult;

  bool get hasRecommendation => networkResult?.plan != null;

  bool get isExact => networkResult?.plan?.isExact ?? false;

  /// True when every input was eligible and the optimizer returned a complete
  /// plan. A large portfolio can use scalable optimization; an over-budget
  /// plan remains complete and is reported through
  /// [BdoNodeNetworkResult.diagnostics].
  bool get coversEveryRequestedMaterial =>
      uncoveredMaterials.isEmpty && networkResult?.plan != null;

  Map<String, int> get requestedDistinctNodeCountsByResource =>
      Map<String, int>.unmodifiable(
        SplayTreeMap<String, int>.from(<String, int>{
          for (final target in coverageTargets)
            target.resourceId: target.requestedDistinctProductionNodeCount,
        }),
      );
}

/// Converts recipe leaves or explicit material targets into one shared worker
/// network.
///
/// Every positive recipe shortage contributes a desired count of one distinct
/// production node. Explicit targets can request a larger absolute count.
/// Duplicate inputs for one canonical resource are idempotent: the largest
/// desired count wins while shortage quantities are summed for display.
///
/// All supported targets are submitted in one [BdoNodeNetworkRequest], so
/// tractable requests receive an exact minimum-CP route and large portfolios
/// can still share paths through the deterministic scalable optimizer. Saved
/// node IDs and root restrictions are forwarded unchanged, preserving connect,
/// retain, and disconnect comparisons.
class BdoRecipeNodeRecommendationService {
  const BdoRecipeNodeRecommendationService({
    this.optimizer = const BdoNodeNetworkOptimizer(),
  });

  final BdoNodeNetworkOptimizer optimizer;

  BdoRecipeNodeRecommendation recommend({
    required BdoResourceMapDataset data,
    required BdoRecipeNodeRecommendationRequest request,
  }) {
    final index = _RecipeResourceIndex(data);
    final accumulators = <String, _CoverageAccumulator>{};
    final uncovered = <BdoRecipeNodeUncoveredMaterial>[];

    final shortages = List<BdoRecipeLeafShortage>.of(
      request.recipeLeafShortages,
    )..sort(_compareShortages);
    for (final shortage in shortages) {
      final label = _materialLabel(shortage.name, shortage.gameItemId);
      if (!shortage.missingQuantity.isFinite || shortage.missingQuantity <= 0) {
        uncovered.add(
          BdoRecipeNodeUncoveredMaterial(
            reason: BdoRecipeNodeUncoveredReason.invalidShortageQuantity,
            query: label,
            gameItemId: shortage.gameItemId,
            missingQuantity: shortage.missingQuantity,
            message:
                'Recipe shortage quantities must be finite and greater than '
                'zero.',
          ),
        );
        continue;
      }
      final resolution = index.resolve(
        query: shortage.name,
        gameItemId: shortage.gameItemId,
      );
      final issue = _resolutionIssue(
        resolution: resolution,
        query: label,
        gameItemId: shortage.gameItemId,
        missingQuantity: shortage.missingQuantity,
      );
      if (issue != null) {
        uncovered.add(issue);
        continue;
      }
      final resourceId = resolution.resourceId!;
      final accumulator = accumulators.putIfAbsent(
        resourceId,
        () => _CoverageAccumulator(index.resource(resourceId)),
      );
      accumulator
        ..hasRecipeShortage = true
        ..recipeShortageInputCount += 1
        ..requestedDistinctProductionNodeCount =
            accumulator.requestedDistinctProductionNodeCount < 1
            ? 1
            : accumulator.requestedDistinctProductionNodeCount
        ..shortageQuantities.add(shortage.missingQuantity)
        ..inputLabels.add(label);
    }

    final materialTargets = List<BdoRecipeNodeMaterialTarget>.of(
      request.materialTargets,
    )..sort(_compareMaterialTargets);
    for (final target in materialTargets) {
      final label = _materialLabel(target.query, target.gameItemId);
      if (target.distinctProductionNodeCount <= 0) {
        uncovered.add(
          BdoRecipeNodeUncoveredMaterial(
            reason:
                BdoRecipeNodeUncoveredReason.invalidDistinctProductionNodeCount,
            query: label,
            gameItemId: target.gameItemId,
            distinctProductionNodeCount: target.distinctProductionNodeCount,
            message:
                'Distinct production-node counts must be greater than zero.',
          ),
        );
        continue;
      }
      final resolution = index.resolve(
        query: target.query,
        gameItemId: target.gameItemId,
      );
      final issue = _resolutionIssue(
        resolution: resolution,
        query: label,
        gameItemId: target.gameItemId,
        distinctProductionNodeCount: target.distinctProductionNodeCount,
      );
      if (issue != null) {
        uncovered.add(issue);
        continue;
      }
      final resourceId = resolution.resourceId!;
      final accumulator = accumulators.putIfAbsent(
        resourceId,
        () => _CoverageAccumulator(index.resource(resourceId)),
      );
      accumulator
        ..hasExplicitMaterialTarget = true
        ..explicitMaterialTargetInputCount += 1
        ..requestedDistinctProductionNodeCount =
            target.distinctProductionNodeCount >
                accumulator.requestedDistinctProductionNodeCount
            ? target.distinctProductionNodeCount
            : accumulator.requestedDistinctProductionNodeCount
        ..inputLabels.add(label);
    }

    final targets = accumulators.values.map((item) => item.build()).toList()
      ..sort(_compareCoverageTargets);
    uncovered.sort(_compareUncoveredMaterials);

    if (targets.isEmpty) {
      return BdoRecipeNodeRecommendation(
        coverageTargets: const <BdoRecipeNodeCoverageTarget>[],
        uncoveredMaterials: uncovered,
        networkResult: null,
      );
    }

    final networkResult = optimizer.optimize(
      data: data,
      request: BdoNodeNetworkRequest(
        contributionPointBudget: request.contributionPointBudget,
        desiredResourceNodeCounts: <String, int>{
          for (final target in targets)
            target.resourceId: target.requestedDistinctProductionNodeCount,
        },
        currentNodeIds: request.currentNodeIds,
        rootNodeIds: request.rootNodeIds,
        maxExactTerminalNodes: request.maxExactTerminalNodes,
        maxExactSelectionCombinations: request.maxExactSelectionCombinations,
      ),
    );

    return BdoRecipeNodeRecommendation(
      coverageTargets: targets,
      uncoveredMaterials: uncovered,
      networkResult: networkResult,
    );
  }
}

class _RecipeResourceIndex {
  _RecipeResourceIndex(BdoResourceMapDataset data)
    : _resourceById = <String, _IndexedResource>{} {
    for (final resource in data.resources) {
      final indexed = _resourceById.putIfAbsent(
        resource.id,
        () => _IndexedResource(
          id: resource.id,
          name: resource.name,
          gameItemId: resource.gameItemId,
        ),
      );
      _addQuery(resource.id, resource.id);
      _addQuery(resource.name, resource.id);
      for (final alias in resource.aliases) {
        _addQuery(alias, resource.id);
      }
      _addGameItemId(resource.gameItemId, resource.id);
      indexed.preferredNames.add(resource.name);
    }

    final workerNodes = List<BdoWorkerNode>.of(data.workerNodes)
      ..sort((left, right) => _compareNodeIds(left.id, right.id));
    for (final node in workerNodes.where((item) => item.isResourceNode)) {
      for (final output in node.outputs) {
        final indexed = _resourceById.putIfAbsent(
          output.resourceId,
          () => _IndexedResource(
            id: output.resourceId,
            name: output.name,
            gameItemId: output.gameItemId,
          ),
        );
        indexed
          ..productionNodeIds.add(node.id)
          ..preferredNames.add(output.name);
        _addQuery(output.resourceId, output.resourceId);
        _addQuery(output.name, output.resourceId);
        _addGameItemId(output.gameItemId, output.resourceId);
      }
    }

    for (final resource in _resourceById.values) {
      resource.preferredNames.sort(_compareText);
    }
  }

  final Map<String, _IndexedResource> _resourceById;
  final Map<String, Set<String>> _resourceIdsByQuery = <String, Set<String>>{};
  final Map<int, Set<String>> _resourceIdsByGameItemId = <int, Set<String>>{};

  _IndexedResource resource(String resourceId) => _resourceById[resourceId]!;

  void _addQuery(String value, String resourceId) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) {
      return;
    }
    (_resourceIdsByQuery[normalized] ??= <String>{}).add(resourceId);
  }

  void _addGameItemId(int? gameItemId, String resourceId) {
    if (gameItemId == null || gameItemId <= 0) {
      return;
    }
    (_resourceIdsByGameItemId[gameItemId] ??= <String>{}).add(resourceId);
  }

  _ResourceResolution resolve({required String query, int? gameItemId}) {
    final normalizedQuery = _normalize(query);
    final hasUsableGameItemId = gameItemId != null && gameItemId > 0;
    if (normalizedQuery.isEmpty && !hasUsableGameItemId) {
      return const _ResourceResolution(
        status: _ResourceResolutionStatus.invalidReference,
      );
    }

    final byQuery = normalizedQuery.isEmpty
        ? const <String>{}
        : _resourceIdsByQuery[normalizedQuery] ?? const <String>{};
    final byGameItemId = hasUsableGameItemId
        ? _resourceIdsByGameItemId[gameItemId] ?? const <String>{}
        : const <String>{};

    Set<String> candidates;
    if (byGameItemId.isNotEmpty && byQuery.isNotEmpty) {
      final intersection = byGameItemId.intersection(byQuery);
      if (intersection.isEmpty) {
        candidates = <String>{...byGameItemId, ...byQuery};
      } else {
        candidates = intersection;
      }
    } else if (byGameItemId.isNotEmpty) {
      candidates = byGameItemId;
    } else {
      candidates = byQuery;
    }

    if (candidates.isEmpty) {
      return const _ResourceResolution(
        status: _ResourceResolutionStatus.unmatched,
      );
    }
    if (candidates.length > 1) {
      return _ResourceResolution(
        status: _ResourceResolutionStatus.ambiguous,
        candidateResourceIds: candidates.toList()..sort(),
      );
    }

    final resourceId = candidates.single;
    final resource = _resourceById[resourceId]!;
    if (resource.productionNodeIds.isEmpty) {
      return _ResourceResolution(
        status: _ResourceResolutionStatus.noWorkerProductionNodes,
        candidateResourceIds: <String>[resourceId],
      );
    }
    return _ResourceResolution(
      status: _ResourceResolutionStatus.resolved,
      resourceId: resourceId,
    );
  }
}

enum _ResourceResolutionStatus {
  resolved,
  invalidReference,
  unmatched,
  ambiguous,
  noWorkerProductionNodes,
}

class _ResourceResolution {
  const _ResourceResolution({
    required this.status,
    this.resourceId,
    this.candidateResourceIds = const <String>[],
  });

  final _ResourceResolutionStatus status;
  final String? resourceId;
  final List<String> candidateResourceIds;
}

class _IndexedResource {
  _IndexedResource({
    required this.id,
    required this.name,
    required this.gameItemId,
  }) : preferredNames = <String>[name];

  final String id;
  final String name;
  final int? gameItemId;
  final Set<String> productionNodeIds = <String>{};
  final List<String> preferredNames;

  String get displayName => preferredNames.first;
}

class _CoverageAccumulator {
  _CoverageAccumulator(this.resource);

  final _IndexedResource resource;
  int requestedDistinctProductionNodeCount = 0;
  bool hasRecipeShortage = false;
  bool hasExplicitMaterialTarget = false;
  int recipeShortageInputCount = 0;
  int explicitMaterialTargetInputCount = 0;
  final List<double> shortageQuantities = <double>[];
  final Set<String> inputLabels = <String>{};

  BdoRecipeNodeCoverageTarget build() {
    shortageQuantities.sort();
    final totalShortage = shortageQuantities.isEmpty
        ? null
        : shortageQuantities.fold<double>(0, (total, value) => total + value);
    final labels = inputLabels.toList()..sort(_compareText);
    return BdoRecipeNodeCoverageTarget(
      resourceId: resource.id,
      resourceName: resource.displayName,
      gameItemId: resource.gameItemId,
      requestedDistinctProductionNodeCount:
          requestedDistinctProductionNodeCount,
      availableDistinctProductionNodeCount: resource.productionNodeIds.length,
      totalRecipeShortageQuantity: totalShortage,
      hasRecipeShortage: hasRecipeShortage,
      hasExplicitMaterialTarget: hasExplicitMaterialTarget,
      inputLabels: labels,
      recipeShortageInputCount: recipeShortageInputCount,
      explicitMaterialTargetInputCount: explicitMaterialTargetInputCount,
    );
  }
}

BdoRecipeNodeUncoveredMaterial? _resolutionIssue({
  required _ResourceResolution resolution,
  required String query,
  required int? gameItemId,
  double? missingQuantity,
  int? distinctProductionNodeCount,
}) {
  final reason = switch (resolution.status) {
    _ResourceResolutionStatus.resolved => null,
    _ResourceResolutionStatus.invalidReference =>
      BdoRecipeNodeUncoveredReason.invalidMaterialReference,
    _ResourceResolutionStatus.unmatched =>
      BdoRecipeNodeUncoveredReason.unmatchedMaterial,
    _ResourceResolutionStatus.ambiguous =>
      BdoRecipeNodeUncoveredReason.ambiguousMaterial,
    _ResourceResolutionStatus.noWorkerProductionNodes =>
      BdoRecipeNodeUncoveredReason.noWorkerProductionNodes,
  };
  if (reason == null) {
    return null;
  }
  final message = switch (reason) {
    BdoRecipeNodeUncoveredReason.invalidMaterialReference =>
      'A material name or positive game item ID is required.',
    BdoRecipeNodeUncoveredReason.unmatchedMaterial =>
      '"$query" does not match a mapped worker-node resource.',
    BdoRecipeNodeUncoveredReason.ambiguousMaterial =>
      '"$query" matches multiple worker-node resources. Use a canonical '
          'resource ID.',
    BdoRecipeNodeUncoveredReason.noWorkerProductionNodes =>
      '"$query" is known, but has no mapped worker-production node.',
    BdoRecipeNodeUncoveredReason.invalidShortageQuantity ||
    BdoRecipeNodeUncoveredReason.invalidDistinctProductionNodeCount =>
      throw StateError('Input validation issues are created before lookup.'),
  };
  return BdoRecipeNodeUncoveredMaterial(
    reason: reason,
    query: query,
    message: message,
    gameItemId: gameItemId,
    missingQuantity: missingQuantity,
    distinctProductionNodeCount: distinctProductionNodeCount,
    candidateResourceIds: resolution.candidateResourceIds,
  );
}

String _materialLabel(String query, int? gameItemId) {
  final trimmed = query.trim();
  if (trimmed.isNotEmpty) {
    return trimmed;
  }
  return gameItemId != null && gameItemId > 0 ? 'Game item $gameItemId' : '';
}

int _compareShortages(BdoRecipeLeafShortage left, BdoRecipeLeafShortage right) {
  final byName = _compareText(left.name, right.name);
  if (byName != 0) {
    return byName;
  }
  final byItemId = (left.gameItemId ?? -1).compareTo(right.gameItemId ?? -1);
  if (byItemId != 0) {
    return byItemId;
  }
  return left.missingQuantity.compareTo(right.missingQuantity);
}

int _compareMaterialTargets(
  BdoRecipeNodeMaterialTarget left,
  BdoRecipeNodeMaterialTarget right,
) {
  final byQuery = _compareText(left.query, right.query);
  if (byQuery != 0) {
    return byQuery;
  }
  final byItemId = (left.gameItemId ?? -1).compareTo(right.gameItemId ?? -1);
  if (byItemId != 0) {
    return byItemId;
  }
  return left.distinctProductionNodeCount.compareTo(
    right.distinctProductionNodeCount,
  );
}

int _compareCoverageTargets(
  BdoRecipeNodeCoverageTarget left,
  BdoRecipeNodeCoverageTarget right,
) {
  final byName = _compareText(left.resourceName, right.resourceName);
  return byName != 0 ? byName : left.resourceId.compareTo(right.resourceId);
}

int _compareUncoveredMaterials(
  BdoRecipeNodeUncoveredMaterial left,
  BdoRecipeNodeUncoveredMaterial right,
) {
  final byReason = left.reason.index.compareTo(right.reason.index);
  if (byReason != 0) {
    return byReason;
  }
  final byQuery = _compareText(left.query, right.query);
  if (byQuery != 0) {
    return byQuery;
  }
  return (left.gameItemId ?? -1).compareTo(right.gameItemId ?? -1);
}

int _compareText(String left, String right) {
  final normalizedComparison = _normalize(left).compareTo(_normalize(right));
  return normalizedComparison != 0
      ? normalizedComparison
      : left.compareTo(right);
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _compareNodeIds(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final byNumber = leftNumber.compareTo(rightNumber);
    if (byNumber != 0) {
      return byNumber;
    }
  }
  return left.compareTo(right);
}
