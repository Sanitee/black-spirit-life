import 'dart:math' as math;

/// The signal used to order worker-node market-value evaluations.
///
/// Every value is based on a comparison basket containing exactly one unit of
/// each included output. It is not a node yield, profit, or silver-per-hour
/// estimate.
enum MarketValueRankingBasis {
  netUnitBasketValue,
  netUnitBasketValuePerMinimumContributionPoint,
  netUnitBasketValuePerIncrementalContributionPoint,
}

/// How complete and directly comparable the data behind a recommendation is.
enum MarketValueDataConfidence { unavailable, low, medium, high }

/// Why a node could not be included in the ordered recommendations.
enum MarketValueCandidateExclusionReason {
  invalidMarketNetRate,
  missingNodeIdentity,
  noOutputs,
  noMarketableOutputs,
  noUsableMarketPrices,
  incompleteMarketPrices,
  minimumContributionPointsUnavailable,
  incrementalContributionPointsUnavailable,
  invalidContributionPoints,
  nonFiniteCalculatedValue,
}

/// Why an individual output is not part of the comparison basket.
enum MarketValueOutputExclusionReason {
  nonMarketable,
  missingIdentity,
  missingPrice,
  invalidPrice,
  duplicateOutput,
}

/// Stable facts that callers should surface beside a market-value ranking.
enum MarketValueCaveat {
  oneUnitComparisonBasket,
  productionYieldUnknown,
  productionCycleTimeUnknown,
  salesVelocityUnknown,
  listedStockIsNotLiquidity,
  listedStockCompetitionHeuristicApplied,
  unknownListedStock,
  invalidListedStockTreatedAsUnknown,
  unknownListedStockPenaltyApplied,
  nonMarketableOutputsExcluded,
  unavailablePrices,
  partialPriceDataUsed,
  duplicateOutputsIgnored,
  zeroIncrementalContributionPoints,
  pathMetadataIsInformational,
}

extension MarketValueCaveatDescription on MarketValueCaveat {
  String get description => switch (this) {
    MarketValueCaveat.oneUnitComparisonBasket =>
      'Values compare one unit of each included output, not actual node yield.',
    MarketValueCaveat.productionYieldUnknown =>
      'Production quantity is not available and is not estimated.',
    MarketValueCaveat.productionCycleTimeUnknown =>
      'Worker cycle time is not available and is not estimated.',
    MarketValueCaveat.salesVelocityUnknown =>
      'Recent sales and sell-through are not available.',
    MarketValueCaveat.listedStockIsNotLiquidity =>
      'Current listed stock does not prove demand, liquidity, or sell-through.',
    MarketValueCaveat.listedStockCompetitionHeuristicApplied =>
      'The optional listed-stock competition heuristic changed this signal.',
    MarketValueCaveat.unknownListedStock =>
      'At least one included output has unknown listed stock.',
    MarketValueCaveat.invalidListedStockTreatedAsUnknown =>
      'At least one invalid listed-stock value was treated as unknown.',
    MarketValueCaveat.unknownListedStockPenaltyApplied =>
      'The configured unknown-stock factor was applied.',
    MarketValueCaveat.nonMarketableOutputsExcluded =>
      'Nonmarketable outputs were excluded from the comparison basket.',
    MarketValueCaveat.unavailablePrices =>
      'At least one marketable output has no usable current price.',
    MarketValueCaveat.partialPriceDataUsed =>
      'The ranking uses only priced outputs and may understate this node.',
    MarketValueCaveat.duplicateOutputsIgnored =>
      'Duplicate output identities were ignored to prevent double counting.',
    MarketValueCaveat.zeroIncrementalContributionPoints =>
      'This node requires no additional CP; its value is ordered before '
          'positive incremental-CP ratios without dividing by zero.',
    MarketValueCaveat.pathMetadataIsInformational =>
      'Path node IDs are informational; only the supplied CP value affects '
          'the score.',
  };
}

/// One raw worker-node output and its current market evidence.
final class MarketValueOutputInput {
  const MarketValueOutputInput({
    required this.outputId,
    required this.outputName,
    required this.isMarketable,
    required this.currentUnitPrice,
    required this.listedStock,
    this.observedDailyTradeVolume,
    this.tradeObservationHours,
  });

  final String outputId;
  final String outputName;
  final bool isMarketable;

  /// Current gross Central Market price for one unit.
  ///
  /// Null means no current price is available. Non-finite and nonpositive
  /// values are rejected rather than treated as zero.
  final double? currentUnitPrice;

  /// Current quantity listed, when the market source asserts it.
  ///
  /// Null is unknown. Zero is known zero. This is never interpreted as recent
  /// sales, demand, or liquidity.
  final int? listedStock;

  /// Cumulative-trade change between two observations, normalized to 24 hours.
  ///
  /// Null means that fewer than two comparable observations are available.
  final double? observedDailyTradeVolume;

  /// Elapsed time between the observations behind
  /// [observedDailyTradeVolume].
  final double? tradeObservationHours;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarketValueOutputInput &&
          outputId == other.outputId &&
          outputName == other.outputName &&
          isMarketable == other.isMarketable &&
          currentUnitPrice == other.currentUnitPrice &&
          listedStock == other.listedStock &&
          observedDailyTradeVolume == other.observedDailyTradeVolume &&
          tradeObservationHours == other.tradeObservationHours;

  @override
  int get hashCode => Object.hash(
    outputId,
    outputName,
    isMarketable,
    currentUnitPrice,
    listedStock,
    observedDailyTradeVolume,
    tradeObservationHours,
  );
}

/// Neutral worker-node and path data consumed by the recommendation service.
final class MarketValueNodeInput {
  MarketValueNodeInput({
    required this.nodeId,
    required this.nodeName,
    required Iterable<MarketValueOutputInput> outputs,
    this.minimumContributionPoints,
    this.incrementalContributionPoints,
    Iterable<String> pathNodeIds = const <String>[],
    Iterable<String> incrementalPathNodeIds = const <String>[],
  }) : outputs = List<MarketValueOutputInput>.unmodifiable(outputs),
       pathNodeIds = List<String>.unmodifiable(
         _normalizedDistinctPath(pathNodeIds),
       ),
       incrementalPathNodeIds = List<String>.unmodifiable(
         _normalizedDistinctPath(incrementalPathNodeIds),
       );

  final String nodeId;
  final String nodeName;
  final List<MarketValueOutputInput> outputs;

  /// CP for the cheapest complete path from an allowed root to this node.
  final int? minimumContributionPoints;

  /// Additional CP required relative to the user's current network.
  ///
  /// Zero is valid and means the node requires no additional CP.
  final int? incrementalContributionPoints;

  /// Optional complete-path metadata. The service never derives CP from it.
  final List<String> pathNodeIds;

  /// Optional newly connected path metadata. The service never derives CP
  /// from it.
  final List<String> incrementalPathNodeIds;
}

/// Optional, explicitly heuristic treatment of current listed stock.
///
/// With [enabled] false, listed stock cannot affect ranking. With it true,
/// known stock receives a linear competition factor: `1` at zero stock and
/// [minimumKnownStockFactor] at or above [referenceListedStock]. Unknown stock
/// receives [unknownStockFactor].
///
/// This policy deliberately says nothing about recent sales or liquidity.
final class ListedStockCompetitionPolicy {
  const ListedStockCompetitionPolicy.ignore()
    : enabled = false,
      referenceListedStock = 1,
      minimumKnownStockFactor = 1,
      unknownStockFactor = 1;

  const ListedStockCompetitionPolicy.penalize({
    required this.referenceListedStock,
    this.minimumKnownStockFactor = .25,
    this.unknownStockFactor = .75,
  }) : enabled = true,
       assert(referenceListedStock > 0),
       assert(minimumKnownStockFactor >= 0 && minimumKnownStockFactor <= 1),
       assert(unknownStockFactor >= 0 && unknownStockFactor <= 1);

  final bool enabled;
  final int referenceListedStock;
  final double minimumKnownStockFactor;
  final double unknownStockFactor;

  double factorFor(int? listedStock) {
    if (!enabled) return 1;
    if (listedStock == null || listedStock < 0) return unknownStockFactor;
    final saturation = math.min(1.0, listedStock / referenceListedStock);
    return 1 - saturation * (1 - minimumKnownStockFactor);
  }
}

final class MarketValueRecommendationRequest {
  MarketValueRecommendationRequest({
    required Iterable<MarketValueNodeInput> candidates,
    required this.marketNetRate,
    this.rankingBasis = MarketValueRankingBasis.netUnitBasketValue,
    this.stockPolicy = const ListedStockCompetitionPolicy.ignore(),
    this.allowPartialPriceData = false,
  }) : candidates = List<MarketValueNodeInput>.unmodifiable(candidates);

  final List<MarketValueNodeInput> candidates;

  /// Tax-adjusted share of gross sale value received by the seller.
  ///
  /// A valid value is finite, greater than zero, and no greater than one.
  final double marketNetRate;
  final MarketValueRankingBasis rankingBasis;
  final ListedStockCompetitionPolicy stockPolicy;

  /// When false, a candidate with any unpriced marketable output is excluded.
  ///
  /// When true, known priced outputs may still be ranked, with low confidence
  /// and explicit partial-data caveats.
  final bool allowPartialPriceData;
}

final class MarketValueOutputEvaluation {
  const MarketValueOutputEvaluation({
    required this.outputId,
    required this.outputName,
    required this.isMarketable,
    required this.currentUnitPrice,
    required this.listedStock,
    required this.exclusionReason,
    required this.grossUnitValue,
    required this.netUnitValue,
    required this.listedStockFactor,
    required this.stockAdjustedNetUnitSignal,
  });

  final String outputId;
  final String outputName;
  final bool isMarketable;
  final double? currentUnitPrice;
  final int? listedStock;
  final MarketValueOutputExclusionReason? exclusionReason;
  final double? grossUnitValue;
  final double? netUnitValue;
  final double? listedStockFactor;
  final double? stockAdjustedNetUnitSignal;

  bool get isIncluded => exclusionReason == null;
}

/// One evaluated worker node.
///
/// [rankingScore] is either a tax-adjusted one-unit basket value or that value
/// divided by a supplied CP amount. It is never profit or silver per hour.
final class MarketValueNodeEvaluation {
  MarketValueNodeEvaluation._({
    required this.rank,
    required this.nodeId,
    required this.nodeName,
    required List<MarketValueOutputEvaluation> outputs,
    required this.minimumContributionPoints,
    required this.incrementalContributionPoints,
    required List<String> pathNodeIds,
    required List<String> incrementalPathNodeIds,
    required this.grossUnitBasketValue,
    required this.netUnitBasketValue,
    required this.stockAdjustedNetValueSignal,
    required this.contributionPointsUsedForRanking,
    required this.rankingScore,
    required this.exclusionReason,
    required this.confidence,
    required Set<MarketValueCaveat> caveats,
  }) : outputs = List<MarketValueOutputEvaluation>.unmodifiable(outputs),
       pathNodeIds = List<String>.unmodifiable(pathNodeIds),
       incrementalPathNodeIds = List<String>.unmodifiable(
         incrementalPathNodeIds,
       ),
       caveats = Set<MarketValueCaveat>.unmodifiable(caveats);

  final int? rank;
  final String nodeId;
  final String nodeName;
  final List<MarketValueOutputEvaluation> outputs;
  final int? minimumContributionPoints;
  final int? incrementalContributionPoints;
  final List<String> pathNodeIds;
  final List<String> incrementalPathNodeIds;
  final double? grossUnitBasketValue;
  final double? netUnitBasketValue;
  final double? stockAdjustedNetValueSignal;
  final int? contributionPointsUsedForRanking;
  final double? rankingScore;
  final MarketValueCandidateExclusionReason? exclusionReason;
  final MarketValueDataConfidence confidence;
  final Set<MarketValueCaveat> caveats;

  bool get isRanked => rank != null && exclusionReason == null;

  MarketValueNodeEvaluation _withRank(int value) => MarketValueNodeEvaluation._(
    rank: value,
    nodeId: nodeId,
    nodeName: nodeName,
    outputs: outputs,
    minimumContributionPoints: minimumContributionPoints,
    incrementalContributionPoints: incrementalContributionPoints,
    pathNodeIds: pathNodeIds,
    incrementalPathNodeIds: incrementalPathNodeIds,
    grossUnitBasketValue: grossUnitBasketValue,
    netUnitBasketValue: netUnitBasketValue,
    stockAdjustedNetValueSignal: stockAdjustedNetValueSignal,
    contributionPointsUsedForRanking: contributionPointsUsedForRanking,
    rankingScore: rankingScore,
    exclusionReason: exclusionReason,
    confidence: confidence,
    caveats: caveats,
  );
}

final class MarketValueRecommendationResult {
  MarketValueRecommendationResult({
    required this.marketNetRate,
    required this.rankingBasis,
    required List<MarketValueNodeEvaluation> ranked,
    required List<MarketValueNodeEvaluation> excluded,
    required Set<MarketValueCaveat> globalCaveats,
  }) : ranked = List<MarketValueNodeEvaluation>.unmodifiable(ranked),
       excluded = List<MarketValueNodeEvaluation>.unmodifiable(excluded),
       globalCaveats = Set<MarketValueCaveat>.unmodifiable(globalCaveats);

  final double marketNetRate;
  final MarketValueRankingBasis rankingBasis;
  final List<MarketValueNodeEvaluation> ranked;
  final List<MarketValueNodeEvaluation> excluded;
  final Set<MarketValueCaveat> globalCaveats;

  bool get hasRankedCandidates => ranked.isNotEmpty;
}

/// Deterministically ranks worker nodes using current market price signals.
///
/// The service intentionally has no production-yield, worker-cycle,
/// transaction-history, or sales-velocity inputs. Consequently it cannot and
/// does not calculate profit, silver per hour, or liquidity.
final class MarketValueRecommendationService {
  const MarketValueRecommendationService();

  MarketValueRecommendationResult evaluate(
    MarketValueRecommendationRequest request,
  ) {
    final globalCaveats = <MarketValueCaveat>{
      MarketValueCaveat.oneUnitComparisonBasket,
      MarketValueCaveat.productionYieldUnknown,
      MarketValueCaveat.productionCycleTimeUnknown,
      MarketValueCaveat.salesVelocityUnknown,
    };
    if (request.stockPolicy.enabled) {
      globalCaveats
        ..add(MarketValueCaveat.listedStockIsNotLiquidity)
        ..add(MarketValueCaveat.listedStockCompetitionHeuristicApplied);
    }

    final marketNetRateIsValid =
        request.marketNetRate.isFinite &&
        request.marketNetRate > 0 &&
        request.marketNetRate <= 1;
    final evaluations = <MarketValueNodeEvaluation>[
      for (final candidate in request.candidates)
        _evaluateCandidate(
          candidate: candidate,
          request: request,
          marketNetRateIsValid: marketNetRateIsValid,
        ),
    ];

    final ranked =
        evaluations
            .where((evaluation) => evaluation.exclusionReason == null)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                _compareRanked(left, right, basis: request.rankingBasis),
          );
    final rankedWithPositions = <MarketValueNodeEvaluation>[
      for (var index = 0; index < ranked.length; index++)
        ranked[index]._withRank(index + 1),
    ];
    final excluded =
        evaluations
            .where((evaluation) => evaluation.exclusionReason != null)
            .toList(growable: false)
          ..sort(_compareExcluded);

    return MarketValueRecommendationResult(
      marketNetRate: request.marketNetRate,
      rankingBasis: request.rankingBasis,
      ranked: rankedWithPositions,
      excluded: excluded,
      globalCaveats: globalCaveats,
    );
  }
}

MarketValueNodeEvaluation _evaluateCandidate({
  required MarketValueNodeInput candidate,
  required MarketValueRecommendationRequest request,
  required bool marketNetRateIsValid,
}) {
  final caveats = <MarketValueCaveat>{};
  if (candidate.pathNodeIds.isNotEmpty ||
      candidate.incrementalPathNodeIds.isNotEmpty) {
    caveats.add(MarketValueCaveat.pathMetadataIsInformational);
  }

  if (!marketNetRateIsValid) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: const <MarketValueOutputEvaluation>[],
      reason: MarketValueCandidateExclusionReason.invalidMarketNetRate,
      caveats: caveats,
    );
  }
  if (candidate.nodeId.trim().isEmpty && candidate.nodeName.trim().isEmpty) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: const <MarketValueOutputEvaluation>[],
      reason: MarketValueCandidateExclusionReason.missingNodeIdentity,
      caveats: caveats,
    );
  }
  if (candidate.outputs.isEmpty) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: const <MarketValueOutputEvaluation>[],
      reason: MarketValueCandidateExclusionReason.noOutputs,
      caveats: caveats,
    );
  }

  final outputEvaluations = _evaluateOutputs(
    outputs: candidate.outputs,
    marketNetRate: request.marketNetRate,
    stockPolicy: request.stockPolicy,
    caveats: caveats,
  );
  final marketableOutputs = outputEvaluations.where(
    (output) =>
        output.exclusionReason !=
        MarketValueOutputExclusionReason.nonMarketable,
  );
  if (marketableOutputs.isEmpty) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: outputEvaluations,
      reason: MarketValueCandidateExclusionReason.noMarketableOutputs,
      caveats: caveats,
    );
  }

  final includedOutputs = outputEvaluations
      .where((output) => output.isIncluded)
      .toList(growable: false);
  final unavailablePriceCount = marketableOutputs
      .where(
        (output) =>
            output.exclusionReason ==
                MarketValueOutputExclusionReason.missingPrice ||
            output.exclusionReason ==
                MarketValueOutputExclusionReason.invalidPrice,
      )
      .length;
  if (includedOutputs.isEmpty) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: outputEvaluations,
      reason: MarketValueCandidateExclusionReason.noUsableMarketPrices,
      caveats: caveats,
    );
  }
  if (unavailablePriceCount > 0 && !request.allowPartialPriceData) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: outputEvaluations,
      reason: MarketValueCandidateExclusionReason.incompleteMarketPrices,
      caveats: caveats,
    );
  }
  if (unavailablePriceCount > 0) {
    caveats.add(MarketValueCaveat.partialPriceDataUsed);
  }

  final grossUnitBasketValue = includedOutputs.fold<double>(
    0,
    (total, output) => total + output.grossUnitValue!,
  );
  final netUnitBasketValue = includedOutputs.fold<double>(
    0,
    (total, output) => total + output.netUnitValue!,
  );
  final stockAdjustedNetValueSignal = includedOutputs.fold<double>(
    0,
    (total, output) => total + output.stockAdjustedNetUnitSignal!,
  );
  if (!grossUnitBasketValue.isFinite ||
      !netUnitBasketValue.isFinite ||
      !stockAdjustedNetValueSignal.isFinite) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: outputEvaluations,
      reason: MarketValueCandidateExclusionReason.nonFiniteCalculatedValue,
      caveats: caveats,
    );
  }

  final valueSignal = request.stockPolicy.enabled
      ? stockAdjustedNetValueSignal
      : netUnitBasketValue;
  final cpResolution = _resolveContributionPointScore(
    candidate: candidate,
    rankingBasis: request.rankingBasis,
    valueSignal: valueSignal,
    caveats: caveats,
  );
  if (cpResolution.exclusionReason != null) {
    return _excludedEvaluation(
      candidate: candidate,
      outputs: outputEvaluations,
      reason: cpResolution.exclusionReason!,
      caveats: caveats,
      grossUnitBasketValue: grossUnitBasketValue,
      netUnitBasketValue: netUnitBasketValue,
      stockAdjustedNetValueSignal: stockAdjustedNetValueSignal,
    );
  }

  final confidence = unavailablePriceCount > 0
      ? MarketValueDataConfidence.low
      : request.stockPolicy.enabled &&
            caveats.any(
              (caveat) =>
                  caveat == MarketValueCaveat.unknownListedStock ||
                  caveat ==
                      MarketValueCaveat.invalidListedStockTreatedAsUnknown,
            )
      ? MarketValueDataConfidence.medium
      : MarketValueDataConfidence.high;

  return MarketValueNodeEvaluation._(
    rank: null,
    nodeId: candidate.nodeId.trim(),
    nodeName: _displayNodeName(candidate),
    outputs: outputEvaluations,
    minimumContributionPoints: candidate.minimumContributionPoints,
    incrementalContributionPoints: candidate.incrementalContributionPoints,
    pathNodeIds: candidate.pathNodeIds,
    incrementalPathNodeIds: candidate.incrementalPathNodeIds,
    grossUnitBasketValue: grossUnitBasketValue,
    netUnitBasketValue: netUnitBasketValue,
    stockAdjustedNetValueSignal: stockAdjustedNetValueSignal,
    contributionPointsUsedForRanking: cpResolution.contributionPoints,
    rankingScore: cpResolution.score,
    exclusionReason: null,
    confidence: confidence,
    caveats: caveats,
  );
}

List<MarketValueOutputEvaluation> _evaluateOutputs({
  required List<MarketValueOutputInput> outputs,
  required double marketNetRate,
  required ListedStockCompetitionPolicy stockPolicy,
  required Set<MarketValueCaveat> caveats,
}) {
  final sorted = List<MarketValueOutputInput>.of(outputs)
    ..sort(_compareOutputInputs);
  final seen = <String>{};
  final result = <MarketValueOutputEvaluation>[];
  for (final output in sorted) {
    final outputId = output.outputId.trim();
    final outputName = output.outputName.trim();
    final identity = _outputIdentity(outputId, outputName);
    if (identity == null) {
      result.add(
        _excludedOutput(
          output,
          MarketValueOutputExclusionReason.missingIdentity,
        ),
      );
      continue;
    }
    if (!seen.add(identity)) {
      caveats.add(MarketValueCaveat.duplicateOutputsIgnored);
      result.add(
        _excludedOutput(
          output,
          MarketValueOutputExclusionReason.duplicateOutput,
        ),
      );
      continue;
    }
    if (!output.isMarketable) {
      caveats.add(MarketValueCaveat.nonMarketableOutputsExcluded);
      result.add(
        _excludedOutput(output, MarketValueOutputExclusionReason.nonMarketable),
      );
      continue;
    }

    final price = output.currentUnitPrice;
    if (price == null) {
      caveats.add(MarketValueCaveat.unavailablePrices);
      result.add(
        _excludedOutput(output, MarketValueOutputExclusionReason.missingPrice),
      );
      continue;
    }
    if (!price.isFinite || price <= 0) {
      caveats.add(MarketValueCaveat.unavailablePrices);
      result.add(
        _excludedOutput(output, MarketValueOutputExclusionReason.invalidPrice),
      );
      continue;
    }

    var normalizedStock = output.listedStock;
    if (normalizedStock != null && normalizedStock < 0) {
      normalizedStock = null;
      caveats.add(MarketValueCaveat.invalidListedStockTreatedAsUnknown);
    }
    if (stockPolicy.enabled && normalizedStock == null) {
      caveats.add(MarketValueCaveat.unknownListedStock);
      if (stockPolicy.unknownStockFactor != 1) {
        caveats.add(MarketValueCaveat.unknownListedStockPenaltyApplied);
      }
    }
    final stockFactor = stockPolicy.factorFor(normalizedStock);
    final netUnitValue = price * marketNetRate;
    result.add(
      MarketValueOutputEvaluation(
        outputId: outputId,
        outputName: outputName,
        isMarketable: true,
        currentUnitPrice: price,
        listedStock: normalizedStock,
        exclusionReason: null,
        grossUnitValue: price,
        netUnitValue: netUnitValue,
        listedStockFactor: stockFactor,
        stockAdjustedNetUnitSignal: netUnitValue * stockFactor,
      ),
    );
  }
  return List<MarketValueOutputEvaluation>.unmodifiable(result);
}

MarketValueOutputEvaluation _excludedOutput(
  MarketValueOutputInput output,
  MarketValueOutputExclusionReason reason,
) {
  return MarketValueOutputEvaluation(
    outputId: output.outputId.trim(),
    outputName: output.outputName.trim(),
    isMarketable: output.isMarketable,
    currentUnitPrice: output.currentUnitPrice,
    listedStock: output.listedStock,
    exclusionReason: reason,
    grossUnitValue: null,
    netUnitValue: null,
    listedStockFactor: null,
    stockAdjustedNetUnitSignal: null,
  );
}

_ContributionPointScore _resolveContributionPointScore({
  required MarketValueNodeInput candidate,
  required MarketValueRankingBasis rankingBasis,
  required double valueSignal,
  required Set<MarketValueCaveat> caveats,
}) {
  switch (rankingBasis) {
    case MarketValueRankingBasis.netUnitBasketValue:
      return _ContributionPointScore(score: valueSignal);
    case MarketValueRankingBasis.netUnitBasketValuePerMinimumContributionPoint:
      final cp = candidate.minimumContributionPoints;
      if (cp == null) {
        return const _ContributionPointScore(
          exclusionReason: MarketValueCandidateExclusionReason
              .minimumContributionPointsUnavailable,
        );
      }
      if (cp <= 0) {
        return const _ContributionPointScore(
          exclusionReason:
              MarketValueCandidateExclusionReason.invalidContributionPoints,
        );
      }
      return _ContributionPointScore(
        contributionPoints: cp,
        score: valueSignal / cp,
      );
    case MarketValueRankingBasis
        .netUnitBasketValuePerIncrementalContributionPoint:
      final cp = candidate.incrementalContributionPoints;
      if (cp == null) {
        return const _ContributionPointScore(
          exclusionReason: MarketValueCandidateExclusionReason
              .incrementalContributionPointsUnavailable,
        );
      }
      if (cp < 0) {
        return const _ContributionPointScore(
          exclusionReason:
              MarketValueCandidateExclusionReason.invalidContributionPoints,
        );
      }
      if (cp == 0) {
        caveats.add(MarketValueCaveat.zeroIncrementalContributionPoints);
        return _ContributionPointScore(
          contributionPoints: 0,
          score: valueSignal,
        );
      }
      return _ContributionPointScore(
        contributionPoints: cp,
        score: valueSignal / cp,
      );
  }
}

MarketValueNodeEvaluation _excludedEvaluation({
  required MarketValueNodeInput candidate,
  required List<MarketValueOutputEvaluation> outputs,
  required MarketValueCandidateExclusionReason reason,
  required Set<MarketValueCaveat> caveats,
  double? grossUnitBasketValue,
  double? netUnitBasketValue,
  double? stockAdjustedNetValueSignal,
}) {
  return MarketValueNodeEvaluation._(
    rank: null,
    nodeId: candidate.nodeId.trim(),
    nodeName: _displayNodeName(candidate),
    outputs: outputs,
    minimumContributionPoints: candidate.minimumContributionPoints,
    incrementalContributionPoints: candidate.incrementalContributionPoints,
    pathNodeIds: candidate.pathNodeIds,
    incrementalPathNodeIds: candidate.incrementalPathNodeIds,
    grossUnitBasketValue: grossUnitBasketValue,
    netUnitBasketValue: netUnitBasketValue,
    stockAdjustedNetValueSignal: stockAdjustedNetValueSignal,
    contributionPointsUsedForRanking: null,
    rankingScore: null,
    exclusionReason: reason,
    confidence: MarketValueDataConfidence.unavailable,
    caveats: caveats,
  );
}

int _compareRanked(
  MarketValueNodeEvaluation left,
  MarketValueNodeEvaluation right, {
  required MarketValueRankingBasis basis,
}) {
  if (basis ==
      MarketValueRankingBasis
          .netUnitBasketValuePerIncrementalContributionPoint) {
    final leftIsFree = left.contributionPointsUsedForRanking == 0;
    final rightIsFree = right.contributionPointsUsedForRanking == 0;
    if (leftIsFree != rightIsFree) return leftIsFree ? -1 : 1;
  }
  final scoreComparison = right.rankingScore!.compareTo(left.rankingScore!);
  if (scoreComparison != 0) return scoreComparison;
  final adjustedComparison = right.stockAdjustedNetValueSignal!.compareTo(
    left.stockAdjustedNetValueSignal!,
  );
  if (adjustedComparison != 0) return adjustedComparison;
  final netComparison = right.netUnitBasketValue!.compareTo(
    left.netUnitBasketValue!,
  );
  if (netComparison != 0) return netComparison;
  final cpComparison = (left.contributionPointsUsedForRanking ?? 0).compareTo(
    right.contributionPointsUsedForRanking ?? 0,
  );
  if (cpComparison != 0) return cpComparison;
  return _compareIdentity(
    left.nodeName,
    left.nodeId,
    right.nodeName,
    right.nodeId,
  );
}

int _compareExcluded(
  MarketValueNodeEvaluation left,
  MarketValueNodeEvaluation right,
) {
  final reasonComparison = left.exclusionReason!.index.compareTo(
    right.exclusionReason!.index,
  );
  if (reasonComparison != 0) return reasonComparison;
  return _compareIdentity(
    left.nodeName,
    left.nodeId,
    right.nodeName,
    right.nodeId,
  );
}

int _compareOutputInputs(
  MarketValueOutputInput left,
  MarketValueOutputInput right,
) => _compareIdentity(
  left.outputName,
  left.outputId,
  right.outputName,
  right.outputId,
);

int _compareIdentity(
  String leftName,
  String leftId,
  String rightName,
  String rightId,
) {
  final foldedNameComparison = _fold(leftName).compareTo(_fold(rightName));
  if (foldedNameComparison != 0) return foldedNameComparison;
  final nameComparison = leftName.trim().compareTo(rightName.trim());
  if (nameComparison != 0) return nameComparison;
  final foldedIdComparison = _fold(leftId).compareTo(_fold(rightId));
  if (foldedIdComparison != 0) return foldedIdComparison;
  return leftId.trim().compareTo(rightId.trim());
}

String _displayNodeName(MarketValueNodeInput candidate) {
  final name = candidate.nodeName.trim();
  return name.isEmpty ? candidate.nodeId.trim() : name;
}

String? _outputIdentity(String outputId, String outputName) {
  if (outputId.isNotEmpty) return 'id:${_fold(outputId)}';
  if (outputName.isNotEmpty) return 'name:${_fold(outputName)}';
  return null;
}

String _fold(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

List<String> _normalizedDistinctPath(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty && seen.add(_fold(normalized))) {
      result.add(normalized);
    }
  }
  return result;
}

final class _ContributionPointScore {
  const _ContributionPointScore({
    this.contributionPoints,
    this.score,
    this.exclusionReason,
  });

  final int? contributionPoints;
  final double? score;
  final MarketValueCandidateExclusionReason? exclusionReason;
}
