import 'dart:math' as math;

import 'worker_income_estimator.dart';

/// Selected worker-node evaluations to combine into one market portfolio.
final class BdoWorkerIncomePortfolioRequest {
  BdoWorkerIncomePortfolioRequest({
    required Iterable<BdoWorkerIncomeNodeEvaluation> nodes,
    required this.onlineHoursPerDay,
  }) : nodes = List<BdoWorkerIncomeNodeEvaluation>.unmodifiable(nodes);

  final List<BdoWorkerIncomeNodeEvaluation> nodes;
  final double onlineHoursPerDay;
}

/// One selected node's proportional share of one shared item market.
final class BdoWorkerIncomePortfolioOutputAllocation {
  const BdoWorkerIncomePortfolioOutputAllocation({
    required this.nodeId,
    required this.gameItemId,
    required this.resourceId,
    required this.name,
    required this.expectedQuantityPerOnlineDay,
    required this.sellableQuantityPerOnlineDay,
    required this.observedDailyTradeVolume,
    required this.sharedMarketVolumeCeilingFactor,
    required this.netSilverPerOnlineHour,
    required this.liquidityAdjustedNetSilverPerOnlineHour,
  });

  final String nodeId;
  final int gameItemId;
  final String resourceId;
  final String name;
  final double expectedQuantityPerOnlineDay;
  final double sellableQuantityPerOnlineDay;

  /// One shared market volume for this item, not a separate allowance per node.
  final double? observedDailyTradeVolume;
  final double sharedMarketVolumeCeilingFactor;
  final double? netSilverPerOnlineHour;
  final double? liquidityAdjustedNetSilverPerOnlineHour;
}

/// Income allocated to one selected production node after shared item caps.
final class BdoWorkerIncomePortfolioNodeAllocation {
  BdoWorkerIncomePortfolioNodeAllocation({
    required this.nodeId,
    required this.nodeName,
    required Iterable<BdoWorkerIncomePortfolioOutputAllocation> outputs,
    required this.netSilverPerOnlineHour,
    required this.liquidityAdjustedNetSilverPerOnlineHour,
    required this.netSilverPerOnlineDay,
    required this.liquidityAdjustedNetSilverPerOnlineDay,
    required this.netSilverPerOnlineWeek,
    required this.liquidityAdjustedNetSilverPerOnlineWeek,
  }) : outputs = List<BdoWorkerIncomePortfolioOutputAllocation>.unmodifiable(
         outputs,
       );

  final String nodeId;
  final String nodeName;
  final List<BdoWorkerIncomePortfolioOutputAllocation> outputs;
  final double netSilverPerOnlineHour;
  final double liquidityAdjustedNetSilverPerOnlineHour;
  final double netSilverPerOnlineDay;
  final double liquidityAdjustedNetSilverPerOnlineDay;
  final double netSilverPerOnlineWeek;
  final double liquidityAdjustedNetSilverPerOnlineWeek;
}

/// Aggregate production and income for one market item across every node.
final class BdoWorkerIncomePortfolioItemAllocation {
  const BdoWorkerIncomePortfolioItemAllocation({
    required this.gameItemId,
    required this.expectedQuantityPerOnlineDay,
    required this.sellableQuantityPerOnlineDay,
    required this.observedDailyTradeVolume,
    required this.tradeObservationHours,
    required this.sharedMarketVolumeCeilingFactor,
    required this.hasConflictingTradeEvidence,
    required this.netSilverPerOnlineHour,
    required this.liquidityAdjustedNetSilverPerOnlineHour,
  });

  final int gameItemId;
  final double expectedQuantityPerOnlineDay;
  final double sellableQuantityPerOnlineDay;
  final double? observedDailyTradeVolume;
  final double? tradeObservationHours;
  final double sharedMarketVolumeCeilingFactor;

  /// True when selected nodes carried different valid snapshots for one item.
  ///
  /// The estimator uses the lowest observed volume in that case so it cannot
  /// exceed any supplied shared-market ceiling.
  final bool hasConflictingTradeEvidence;
  final double netSilverPerOnlineHour;
  final double liquidityAdjustedNetSilverPerOnlineHour;
}

/// One complete selected network evaluated as a shared market portfolio.
final class BdoWorkerIncomePortfolioResult {
  BdoWorkerIncomePortfolioResult({
    required Iterable<BdoWorkerIncomePortfolioNodeAllocation> nodes,
    required Iterable<BdoWorkerIncomePortfolioItemAllocation> items,
    required this.netSilverPerOnlineHour,
    required this.liquidityAdjustedNetSilverPerOnlineHour,
    required this.netSilverPerOnlineDay,
    required this.liquidityAdjustedNetSilverPerOnlineDay,
    required this.netSilverPerOnlineWeek,
    required this.liquidityAdjustedNetSilverPerOnlineWeek,
  }) : nodes = List<BdoWorkerIncomePortfolioNodeAllocation>.unmodifiable(nodes),
       items = List<BdoWorkerIncomePortfolioItemAllocation>.unmodifiable(items);

  final List<BdoWorkerIncomePortfolioNodeAllocation> nodes;
  final List<BdoWorkerIncomePortfolioItemAllocation> items;
  final double netSilverPerOnlineHour;
  final double liquidityAdjustedNetSilverPerOnlineHour;
  final double netSilverPerOnlineDay;
  final double liquidityAdjustedNetSilverPerOnlineDay;
  final double netSilverPerOnlineWeek;
  final double liquidityAdjustedNetSilverPerOnlineWeek;
}

/// Reuses one selected portfolio while evaluating many possible next nodes.
///
/// [evaluate] is mathematically equivalent to evaluating the selected nodes
/// plus the candidate as a complete [BdoWorkerIncomePortfolioResult], then
/// subtracting the selected portfolio's
/// [BdoWorkerIncomePortfolioResult.liquidityAdjustedNetSilverPerOnlineHour].
///
/// The selected nodes are deduplicated by node ID with first-node-wins
/// semantics, matching [BdoWorkerIncomePortfolioEstimator]. Preparing this
/// evaluator scans that selected set once. Each [evaluate] call then scans only
/// the candidate's outputs and recalculates the shared item markets touched by
/// that candidate; it does not construct either full portfolio result.
final class BdoWorkerIncomePortfolioMarginalEvaluator {
  factory BdoWorkerIncomePortfolioMarginalEvaluator({
    required Iterable<BdoWorkerIncomeNodeEvaluation> selectedNodes,
    required double onlineHoursPerDay,
  }) {
    _validateOnlineHoursPerDay(onlineHoursPerDay);
    return BdoWorkerIncomePortfolioMarginalEvaluator._(
      onlineHoursPerDay,
      _PreparedMarginalPortfolio(selectedNodes),
    );
  }

  const BdoWorkerIncomePortfolioMarginalEvaluator._(
    this.onlineHoursPerDay,
    this._selected,
  );

  final double onlineHoursPerDay;
  final _PreparedMarginalPortfolio _selected;

  /// Number of unique selected node IDs retained by this evaluator.
  int get selectedNodeCount => _selected.nodeIds.length;

  /// Whether [nodeId] is already represented by the prepared selected set.
  bool containsSelectedNodeId(String nodeId) =>
      _selected.nodeIds.contains(nodeId);

  /// Returns the candidate's shared-market-adjusted marginal silver per hour.
  ///
  /// A candidate whose node ID is already selected returns zero because the
  /// complete portfolio estimator would discard that duplicate.
  double evaluate(BdoWorkerIncomeNodeEvaluation candidate) =>
      _selected.evaluate(candidate);
}

/// Combines selected node estimates without multiplying one item's market.
///
/// Individual-node comparisons intentionally remain independent. For a
/// complete network, this service groups outputs by game item, sums expected
/// daily production, and applies one common sellable fraction:
///
/// `min(1, observed daily trades / combined expected daily quantity)`.
///
/// Every node receives a proportional share through that common fraction, so
/// the portfolio's summed sellable quantity cannot exceed the one shared
/// observed market volume.
final class BdoWorkerIncomePortfolioEstimator {
  const BdoWorkerIncomePortfolioEstimator();

  /// Prepares a selected set for repeated exact marginal candidate evaluation.
  BdoWorkerIncomePortfolioMarginalEvaluator prepareMarginalEvaluator(
    BdoWorkerIncomePortfolioRequest selected,
  ) => BdoWorkerIncomePortfolioMarginalEvaluator(
    selectedNodes: selected.nodes,
    onlineHoursPerDay: selected.onlineHoursPerDay,
  );

  BdoWorkerIncomePortfolioResult evaluate(
    BdoWorkerIncomePortfolioRequest request,
  ) {
    _validateOnlineHoursPerDay(request.onlineHoursPerDay);

    final nodesById = <String, BdoWorkerIncomeNodeEvaluation>{};
    for (final node in request.nodes) {
      nodesById.putIfAbsent(node.nodeId, () => node);
    }

    final itemsById = <int, _PortfolioItemAccumulator>{};
    for (final node in nodesById.values) {
      for (final output in node.outputs) {
        if (!_participatesInSharedMarket(output)) {
          continue;
        }
        (itemsById[output.gameItemId] ??= _PortfolioItemAccumulator(
          gameItemId: output.gameItemId,
        )).add(node.nodeId, output);
      }
    }

    final itemAccumulators = itemsById.values.toList()
      ..sort((left, right) => left.gameItemId.compareTo(right.gameItemId));
    final itemAllocationsById = <int, _ResolvedPortfolioItem>{
      for (final item in itemAccumulators) item.gameItemId: item.resolve(),
    };

    final nodeAllocations = <BdoWorkerIncomePortfolioNodeAllocation>[];
    var rawHourly = 0.0;
    var adjustedHourly = 0.0;
    for (final node in nodesById.values) {
      final outputAllocations = <BdoWorkerIncomePortfolioOutputAllocation>[];
      var nodeRawHourly = 0.0;
      var nodeAdjustedHourly = 0.0;
      for (final output in node.outputs) {
        final item = itemAllocationsById[output.gameItemId];
        final factor = output.isMarketable && item != null
            ? item.ceilingFactor
            : 1.0;
        final expectedDaily = output.expectedQuantityPerOnlineDay.isFinite
            ? math.max(0.0, output.expectedQuantityPerOnlineDay)
            : 0.0;
        final rawOutputHourly = output.netSilverPerOnlineHour;
        final adjustedOutputHourly = rawOutputHourly == null
            ? null
            : rawOutputHourly * factor;
        if (rawOutputHourly != null && rawOutputHourly.isFinite) {
          nodeRawHourly += rawOutputHourly;
          nodeAdjustedHourly += adjustedOutputHourly!;
        }
        outputAllocations.add(
          BdoWorkerIncomePortfolioOutputAllocation(
            nodeId: node.nodeId,
            gameItemId: output.gameItemId,
            resourceId: output.resourceId,
            name: output.name,
            expectedQuantityPerOnlineDay: expectedDaily,
            sellableQuantityPerOnlineDay: expectedDaily * factor,
            observedDailyTradeVolume: item?.observedDailyTradeVolume,
            sharedMarketVolumeCeilingFactor: factor,
            netSilverPerOnlineHour: rawOutputHourly,
            liquidityAdjustedNetSilverPerOnlineHour: adjustedOutputHourly,
          ),
        );
      }
      rawHourly += nodeRawHourly;
      adjustedHourly += nodeAdjustedHourly;
      nodeAllocations.add(
        BdoWorkerIncomePortfolioNodeAllocation(
          nodeId: node.nodeId,
          nodeName: node.nodeName,
          outputs: outputAllocations,
          netSilverPerOnlineHour: nodeRawHourly,
          liquidityAdjustedNetSilverPerOnlineHour: nodeAdjustedHourly,
          netSilverPerOnlineDay: nodeRawHourly * request.onlineHoursPerDay,
          liquidityAdjustedNetSilverPerOnlineDay:
              nodeAdjustedHourly * request.onlineHoursPerDay,
          netSilverPerOnlineWeek: nodeRawHourly * request.onlineHoursPerDay * 7,
          liquidityAdjustedNetSilverPerOnlineWeek:
              nodeAdjustedHourly * request.onlineHoursPerDay * 7,
        ),
      );
    }

    return BdoWorkerIncomePortfolioResult(
      nodes: nodeAllocations,
      items: <BdoWorkerIncomePortfolioItemAllocation>[
        for (final item in itemAccumulators)
          itemAllocationsById[item.gameItemId]!.allocation,
      ],
      netSilverPerOnlineHour: rawHourly,
      liquidityAdjustedNetSilverPerOnlineHour: adjustedHourly,
      netSilverPerOnlineDay: rawHourly * request.onlineHoursPerDay,
      liquidityAdjustedNetSilverPerOnlineDay:
          adjustedHourly * request.onlineHoursPerDay,
      netSilverPerOnlineWeek: rawHourly * request.onlineHoursPerDay * 7,
      liquidityAdjustedNetSilverPerOnlineWeek:
          adjustedHourly * request.onlineHoursPerDay * 7,
    );
  }
}

void _validateOnlineHoursPerDay(double onlineHoursPerDay) {
  if (!onlineHoursPerDay.isFinite ||
      onlineHoursPerDay <= 0 ||
      onlineHoursPerDay > 24) {
    throw ArgumentError.value(
      onlineHoursPerDay,
      'onlineHoursPerDay',
      'must be finite and between 0 and 24',
    );
  }
}

bool _participatesInSharedMarket(BdoWorkerIncomeOutputEvaluation output) =>
    output.isMarketable &&
    output.expectedQuantityPerOnlineDay.isFinite &&
    output.expectedQuantityPerOnlineDay > 0;

bool _hasValidTradeEvidence(BdoWorkerIncomeOutputEvaluation output) {
  final dailyVolume = output.observedDailyTradeVolume;
  final hours = output.tradeObservationHours;
  return dailyVolume != null &&
      dailyVolume.isFinite &&
      dailyVolume >= 0 &&
      hours != null &&
      hours.isFinite &&
      hours > 0;
}

double _sharedMarketCeilingFactor({
  required bool hasParticipatingOutput,
  required double expectedQuantityPerOnlineDay,
  required double? observedDailyTradeVolume,
}) {
  if (!hasParticipatingOutput ||
      observedDailyTradeVolume == null ||
      expectedQuantityPerOnlineDay <= 0) {
    return 1.0;
  }
  return (observedDailyTradeVolume / expectedQuantityPerOnlineDay)
      .clamp(0.0, 1.0)
      .toDouble();
}

double? _minimumNullable(double? left, double? right) {
  if (left == null) {
    return right;
  }
  if (right == null) {
    return left;
  }
  return math.min(left, right);
}

final class _PreparedMarginalPortfolio {
  _PreparedMarginalPortfolio(Iterable<BdoWorkerIncomeNodeEvaluation> nodes)
    : nodeIds = <String>{},
      itemsById = <int, _PreparedMarginalMarketItem>{} {
    final itemBuilders = <int, _MarginalMarketItemBuilder>{};
    for (final node in nodes) {
      if (!nodeIds.add(node.nodeId)) {
        continue;
      }
      for (final output in node.outputs) {
        if (!output.isMarketable) {
          continue;
        }
        final rawHourly = output.netSilverPerOnlineHour;
        final participates = _participatesInSharedMarket(output);
        if ((rawHourly == null || !rawHourly.isFinite) && !participates) {
          continue;
        }
        (itemBuilders[output.gameItemId] ??= _MarginalMarketItemBuilder()).add(
          output,
        );
      }
    }
    for (final entry in itemBuilders.entries) {
      itemsById[entry.key] = entry.value.prepare();
    }
  }

  final Set<String> nodeIds;
  final Map<int, _PreparedMarginalMarketItem> itemsById;

  double evaluate(BdoWorkerIncomeNodeEvaluation candidate) {
    if (nodeIds.contains(candidate.nodeId)) {
      return 0.0;
    }

    var marginalHourly = 0.0;
    final candidateItems = <int, _MarginalMarketItemBuilder>{};
    for (final output in candidate.outputs) {
      final rawHourly = output.netSilverPerOnlineHour;
      if (!output.isMarketable) {
        if (rawHourly != null && rawHourly.isFinite) {
          marginalHourly += rawHourly;
        }
        continue;
      }

      final participates = _participatesInSharedMarket(output);
      if ((rawHourly == null || !rawHourly.isFinite) && !participates) {
        continue;
      }
      (candidateItems[output.gameItemId] ??= _MarginalMarketItemBuilder()).add(
        output,
      );
    }

    for (final entry in candidateItems.entries) {
      final selected = itemsById[entry.key];
      final candidateItem = entry.value.prepare();
      final selectedRawHourly = selected?.rawHourly ?? 0.0;
      final selectedExpectedDaily =
          selected?.expectedQuantityPerOnlineDay ?? 0.0;
      final oldFactor = selected?.ceilingFactor ?? 1.0;

      final hasParticipatingOutput =
          (selected?.hasParticipatingOutput ?? false) ||
          candidateItem.hasParticipatingOutput;
      final expectedDaily =
          selectedExpectedDaily + candidateItem.expectedQuantityPerOnlineDay;
      final observedDailyTradeVolume = _minimumNullable(
        selected?.observedDailyTradeVolume,
        candidateItem.observedDailyTradeVolume,
      );
      final newFactor = _sharedMarketCeilingFactor(
        hasParticipatingOutput: hasParticipatingOutput,
        expectedQuantityPerOnlineDay: expectedDaily,
        observedDailyTradeVolume: observedDailyTradeVolume,
      );
      marginalHourly +=
          (selectedRawHourly + candidateItem.rawHourly) * newFactor -
          selectedRawHourly * oldFactor;
    }
    return marginalHourly;
  }
}

final class _MarginalMarketItemBuilder {
  var rawHourly = 0.0;
  var expectedQuantityPerOnlineDay = 0.0;
  var hasParticipatingOutput = false;
  double? observedDailyTradeVolume;

  void add(BdoWorkerIncomeOutputEvaluation output) {
    final outputHourly = output.netSilverPerOnlineHour;
    if (outputHourly != null && outputHourly.isFinite) {
      rawHourly += outputHourly;
    }
    if (!_participatesInSharedMarket(output)) {
      return;
    }
    hasParticipatingOutput = true;
    expectedQuantityPerOnlineDay += output.expectedQuantityPerOnlineDay;
    if (_hasValidTradeEvidence(output)) {
      observedDailyTradeVolume = _minimumNullable(
        observedDailyTradeVolume,
        output.observedDailyTradeVolume,
      );
    }
  }

  _PreparedMarginalMarketItem prepare() => _PreparedMarginalMarketItem(
    rawHourly: rawHourly,
    expectedQuantityPerOnlineDay: expectedQuantityPerOnlineDay,
    hasParticipatingOutput: hasParticipatingOutput,
    observedDailyTradeVolume: observedDailyTradeVolume,
  );
}

final class _PreparedMarginalMarketItem {
  const _PreparedMarginalMarketItem({
    required this.rawHourly,
    required this.expectedQuantityPerOnlineDay,
    required this.hasParticipatingOutput,
    required this.observedDailyTradeVolume,
  });

  final double rawHourly;
  final double expectedQuantityPerOnlineDay;
  final bool hasParticipatingOutput;
  final double? observedDailyTradeVolume;

  double get ceilingFactor => _sharedMarketCeilingFactor(
    hasParticipatingOutput: hasParticipatingOutput,
    expectedQuantityPerOnlineDay: expectedQuantityPerOnlineDay,
    observedDailyTradeVolume: observedDailyTradeVolume,
  );
}

final class _PortfolioItemAccumulator {
  _PortfolioItemAccumulator({required this.gameItemId});

  final int gameItemId;
  final List<({String nodeId, BdoWorkerIncomeOutputEvaluation output})>
  outputs = <({String nodeId, BdoWorkerIncomeOutputEvaluation output})>[];

  void add(String nodeId, BdoWorkerIncomeOutputEvaluation output) {
    outputs.add((nodeId: nodeId, output: output));
  }

  _ResolvedPortfolioItem resolve() {
    var expectedDaily = 0.0;
    var rawHourly = 0.0;
    final observedVolumes = <double>[];
    final observationHours = <double>[];
    for (final entry in outputs) {
      final output = entry.output;
      expectedDaily += output.expectedQuantityPerOnlineDay;
      final outputHourly = output.netSilverPerOnlineHour;
      if (outputHourly != null && outputHourly.isFinite) {
        rawHourly += outputHourly;
      }
      final dailyVolume = output.observedDailyTradeVolume;
      final hours = output.tradeObservationHours;
      if (_hasValidTradeEvidence(output)) {
        observedVolumes.add(dailyVolume!);
        observationHours.add(hours!);
      }
    }

    final observedDailyTradeVolume = observedVolumes.isEmpty
        ? null
        : observedVolumes.reduce(math.min);
    final minimumObservationHours = observationHours.isEmpty
        ? null
        : observationHours.reduce(math.min);
    final ceilingFactor = _sharedMarketCeilingFactor(
      hasParticipatingOutput: outputs.isNotEmpty,
      expectedQuantityPerOnlineDay: expectedDaily,
      observedDailyTradeVolume: observedDailyTradeVolume,
    );
    final firstVolume = observedVolumes.firstOrNull;
    final conflicting =
        firstVolume != null &&
        observedVolumes.any((volume) => (volume - firstVolume).abs() > 1e-9);
    return _ResolvedPortfolioItem(
      observedDailyTradeVolume: observedDailyTradeVolume,
      ceilingFactor: ceilingFactor,
      allocation: BdoWorkerIncomePortfolioItemAllocation(
        gameItemId: gameItemId,
        expectedQuantityPerOnlineDay: expectedDaily,
        sellableQuantityPerOnlineDay: expectedDaily * ceilingFactor,
        observedDailyTradeVolume: observedDailyTradeVolume,
        tradeObservationHours: minimumObservationHours,
        sharedMarketVolumeCeilingFactor: ceilingFactor,
        hasConflictingTradeEvidence: conflicting,
        netSilverPerOnlineHour: rawHourly,
        liquidityAdjustedNetSilverPerOnlineHour: rawHourly * ceilingFactor,
      ),
    );
  }
}

final class _ResolvedPortfolioItem {
  const _ResolvedPortfolioItem({
    required this.observedDailyTradeVolume,
    required this.ceilingFactor,
    required this.allocation,
  });

  final double? observedDailyTradeVolume;
  final double ceilingFactor;
  final BdoWorkerIncomePortfolioItemAllocation allocation;
}
