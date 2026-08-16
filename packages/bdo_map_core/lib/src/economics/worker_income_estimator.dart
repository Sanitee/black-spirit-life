import 'dart:math' as math;

import 'worker_economics_data.dart';

enum BdoWorkerIncomeRankingBasis {
  netSilverPerOnlineHour,
  netSilverPerTotalContributionPointHour,
  netSilverPerAddedContributionPointHour,
}

enum BdoWorkerIncomeConfidence { unavailable, low, medium, high }

enum BdoWorkerIncomeExclusionReason {
  invalidMarketNetRate,
  invalidOnlineHours,
  invalidResourceAvailability,
  missingProductionEconomics,
  incompleteProductionOutputMapping,
  noEligibleWorkerTown,
  noOutputs,
  noMarketableExpectedOutputs,
  noUsableMarketPrices,
  incompleteMarketPrices,
  invalidContributionPoints,
  nonFiniteCalculation,
}

enum BdoWorkerIncomeCaveat {
  level40MedianWorker,
  workerSkillsExcluded,
  resourceAvailabilityAssumption,
  expectedYieldEstimate,
  lodgingContributionPointsExcluded,
  partialPriceDataUsed,
  listedStockIsNotDemand,
  observedTradeVolumeUnavailable,
  shortTradeObservation,
  marketVolumeCeilingApplied,
  marketVolumeCeilingIsOptimistic,
}

extension BdoWorkerIncomeCaveatDescription on BdoWorkerIncomeCaveat {
  String get description => switch (this) {
    BdoWorkerIncomeCaveat.level40MedianWorker =>
      'Cycle time uses a level-40 median worker profile.',
    BdoWorkerIncomeCaveat.workerSkillsExcluded =>
      'Worker skill bonuses are not included.',
    BdoWorkerIncomeCaveat.resourceAvailabilityAssumption =>
      'Cycle time uses the selected node resource-availability percentage.',
    BdoWorkerIncomeCaveat.expectedYieldEstimate =>
      'Output quantities are expected values per completed worker cycle.',
    BdoWorkerIncomeCaveat.lodgingContributionPointsExcluded =>
      'Lodging CP is not included because no verified house plan was supplied.',
    BdoWorkerIncomeCaveat.partialPriceDataUsed =>
      'At least one expected marketable output has no current price.',
    BdoWorkerIncomeCaveat.listedStockIsNotDemand =>
      'Listed stock is competition evidence, not demand.',
    BdoWorkerIncomeCaveat.observedTradeVolumeUnavailable =>
      'No two-snapshot trade-volume observation is available.',
    BdoWorkerIncomeCaveat.shortTradeObservation =>
      'Observed sales cover less than 24 hours and may be volatile.',
    BdoWorkerIncomeCaveat.marketVolumeCeilingApplied =>
      'The income score is capped when expected output exceeds all observed '
          'market sales during the same online-time period.',
    BdoWorkerIncomeCaveat.marketVolumeCeilingIsOptimistic =>
      'The sales-volume cap is an optimistic ceiling; other sellers also '
          'compete for those sales.',
  };
}

final class BdoWorkerIncomeMarketOutputInput {
  const BdoWorkerIncomeMarketOutputInput({
    required this.gameItemId,
    required this.resourceId,
    required this.name,
    required this.isMarketable,
    required this.currentUnitPrice,
    required this.listedStock,
    this.observedDailyTradeVolume,
    this.tradeObservationHours,
  });

  final int gameItemId;
  final String resourceId;
  final String name;
  final bool isMarketable;
  final double? currentUnitPrice;
  final int? listedStock;

  /// Actual item-count change between two cumulative trade snapshots,
  /// normalized to 24 hours.
  final double? observedDailyTradeVolume;

  /// Elapsed time between the snapshots behind [observedDailyTradeVolume].
  final double? tradeObservationHours;
}

final class BdoWorkerIncomeNodeInput {
  BdoWorkerIncomeNodeInput({
    required this.nodeId,
    required this.nodeName,
    required Iterable<BdoWorkerIncomeMarketOutputInput> outputs,
    required this.minimumContributionPoints,
    required this.incrementalContributionPoints,
    this.incrementalLodgingContributionPoints,
    Set<String>? allowedTownNodeIds,
  }) : outputs = List<BdoWorkerIncomeMarketOutputInput>.unmodifiable(outputs),
       allowedTownNodeIds = allowedTownNodeIds == null
           ? null
           : Set<String>.unmodifiable(allowedTownNodeIds);

  final String nodeId;
  final String nodeName;
  final List<BdoWorkerIncomeMarketOutputInput> outputs;
  final int? minimumContributionPoints;
  final int? incrementalContributionPoints;

  /// Optional verified lodging CP added specifically for this assignment.
  ///
  /// Null means lodging has not been planned and is excluded from CP ratios.
  final int? incrementalLodgingContributionPoints;

  /// Towns that may dispatch the worker for this candidate.
  ///
  /// Null uses every verified town in the economics dataset. An empty set
  /// deliberately makes the candidate unavailable.
  final Set<String>? allowedTownNodeIds;
}

final class BdoWorkerIncomeRequest {
  BdoWorkerIncomeRequest({
    required this.dataset,
    required Iterable<BdoWorkerIncomeNodeInput> candidates,
    required this.marketNetRate,
    required this.onlineHoursPerDay,
    this.resourceAvailabilityPercent = 100,
    this.rankingBasis =
        BdoWorkerIncomeRankingBasis.netSilverPerAddedContributionPointHour,
    this.allowPartialPriceData = false,
    this.applyObservedTradeVolumeCeiling = false,
  }) : candidates = List<BdoWorkerIncomeNodeInput>.unmodifiable(candidates);

  final BdoWorkerEconomicsDataset dataset;
  final List<BdoWorkerIncomeNodeInput> candidates;
  final double marketNetRate;
  final double onlineHoursPerDay;

  /// In-game node resource availability from 0 through 100 percent.
  final double resourceAvailabilityPercent;
  final BdoWorkerIncomeRankingBasis rankingBasis;
  final bool allowPartialPriceData;
  final bool applyObservedTradeVolumeCeiling;
}

final class BdoWorkerIncomeOutputEvaluation {
  const BdoWorkerIncomeOutputEvaluation({
    required this.gameItemId,
    required this.resourceId,
    required this.name,
    required this.isMarketable,
    required this.expectedQuantityPerCycle,
    required this.expectedQuantityPerOnlineHour,
    required this.expectedQuantityPerOnlineDay,
    required this.currentUnitPrice,
    required this.listedStock,
    required this.observedDailyTradeVolume,
    required this.tradeObservationHours,
    required this.netSilverPerOnlineHour,
    required this.marketVolumeCeilingFactor,
    required this.stockCoverageDays,
  });

  final int gameItemId;
  final String resourceId;
  final String name;
  final bool isMarketable;
  final double expectedQuantityPerCycle;
  final double expectedQuantityPerOnlineHour;
  final double expectedQuantityPerOnlineDay;
  final double? currentUnitPrice;
  final int? listedStock;
  final double? observedDailyTradeVolume;
  final double? tradeObservationHours;
  final double? netSilverPerOnlineHour;

  /// Optimistic sellable fraction when all observed daily sales are available
  /// to this one worker's output.
  final double? marketVolumeCeilingFactor;

  /// Current listed quantity divided by observed sales per 24 hours.
  final double? stockCoverageDays;
}

final class BdoWorkerIncomeNodeEvaluation {
  BdoWorkerIncomeNodeEvaluation._({
    required this.rank,
    required this.nodeId,
    required this.nodeName,
    required this.workerTownNodeId,
    required this.workerProfile,
    required this.cycleMinutes,
    required this.cyclesPerOnlineHour,
    required List<BdoWorkerIncomeOutputEvaluation> outputs,
    required this.minimumContributionPoints,
    required this.incrementalContributionPoints,
    required this.incrementalLodgingContributionPoints,
    required this.netSilverPerOnlineHour,
    required this.liquidityAdjustedNetSilverPerOnlineHour,
    required this.netSilverPerOnlineDay,
    required this.netSilverPerOnlineWeek,
    required this.contributionPointsUsedForRanking,
    required this.rankingScore,
    required this.zeroContributionPointRanking,
    required this.valueWeightedStockCoverageDays,
    required this.marketVolumeCeilingFactor,
    required this.incomeConfidence,
    required this.liquidityConfidence,
    required Set<BdoWorkerIncomeCaveat> caveats,
    required this.exclusionReason,
  }) : outputs = List<BdoWorkerIncomeOutputEvaluation>.unmodifiable(outputs),
       caveats = Set<BdoWorkerIncomeCaveat>.unmodifiable(caveats);

  final int? rank;
  final String nodeId;
  final String nodeName;
  final String? workerTownNodeId;
  final BdoWorkerProfileEstimate? workerProfile;
  final double? cycleMinutes;
  final double? cyclesPerOnlineHour;
  final List<BdoWorkerIncomeOutputEvaluation> outputs;
  final int? minimumContributionPoints;
  final int? incrementalContributionPoints;
  final int? incrementalLodgingContributionPoints;
  final double? netSilverPerOnlineHour;
  final double? liquidityAdjustedNetSilverPerOnlineHour;
  final double? netSilverPerOnlineDay;
  final double? netSilverPerOnlineWeek;
  final int? contributionPointsUsedForRanking;
  final double? rankingScore;
  final bool zeroContributionPointRanking;
  final double? valueWeightedStockCoverageDays;
  final double? marketVolumeCeilingFactor;
  final BdoWorkerIncomeConfidence incomeConfidence;
  final BdoWorkerIncomeConfidence liquidityConfidence;
  final Set<BdoWorkerIncomeCaveat> caveats;
  final BdoWorkerIncomeExclusionReason? exclusionReason;

  bool get isRanked => rank != null && exclusionReason == null;

  BdoWorkerIncomeNodeEvaluation _withRank(int value) =>
      BdoWorkerIncomeNodeEvaluation._(
        rank: value,
        nodeId: nodeId,
        nodeName: nodeName,
        workerTownNodeId: workerTownNodeId,
        workerProfile: workerProfile,
        cycleMinutes: cycleMinutes,
        cyclesPerOnlineHour: cyclesPerOnlineHour,
        outputs: outputs,
        minimumContributionPoints: minimumContributionPoints,
        incrementalContributionPoints: incrementalContributionPoints,
        incrementalLodgingContributionPoints:
            incrementalLodgingContributionPoints,
        netSilverPerOnlineHour: netSilverPerOnlineHour,
        liquidityAdjustedNetSilverPerOnlineHour:
            liquidityAdjustedNetSilverPerOnlineHour,
        netSilverPerOnlineDay: netSilverPerOnlineDay,
        netSilverPerOnlineWeek: netSilverPerOnlineWeek,
        contributionPointsUsedForRanking: contributionPointsUsedForRanking,
        rankingScore: rankingScore,
        zeroContributionPointRanking: zeroContributionPointRanking,
        valueWeightedStockCoverageDays: valueWeightedStockCoverageDays,
        marketVolumeCeilingFactor: marketVolumeCeilingFactor,
        incomeConfidence: incomeConfidence,
        liquidityConfidence: liquidityConfidence,
        caveats: caveats,
        exclusionReason: exclusionReason,
      );
}

final class BdoWorkerIncomeResult {
  BdoWorkerIncomeResult({
    required this.rankingBasis,
    required this.onlineHoursPerDay,
    required this.resourceAvailabilityPercent,
    required List<BdoWorkerIncomeNodeEvaluation> ranked,
    required List<BdoWorkerIncomeNodeEvaluation> excluded,
  }) : ranked = List<BdoWorkerIncomeNodeEvaluation>.unmodifiable(ranked),
       excluded = List<BdoWorkerIncomeNodeEvaluation>.unmodifiable(excluded);

  final BdoWorkerIncomeRankingBasis rankingBasis;
  final double onlineHoursPerDay;
  final double resourceAvailabilityPercent;
  final List<BdoWorkerIncomeNodeEvaluation> ranked;
  final List<BdoWorkerIncomeNodeEvaluation> excluded;
}

/// Calculates worker-cycle income from pinned workload/yield/distance inputs.
///
/// This is an estimate, not a guaranteed profit forecast. It deliberately
/// separates current listed stock from observed trade volume and never treats
/// stock alone as demand.
final class BdoWorkerIncomeEstimator {
  const BdoWorkerIncomeEstimator();

  BdoWorkerIncomeResult evaluate(BdoWorkerIncomeRequest request) {
    final evaluations = <BdoWorkerIncomeNodeEvaluation>[
      for (final candidate in request.candidates)
        _evaluateCandidate(request, candidate),
    ];
    final ranked =
        evaluations
            .where((evaluation) => evaluation.exclusionReason == null)
            .toList(growable: false)
          ..sort(_compareRanked);
    final rankedWithPositions = <BdoWorkerIncomeNodeEvaluation>[
      for (var index = 0; index < ranked.length; index++)
        ranked[index]._withRank(index + 1),
    ];
    final excluded =
        evaluations
            .where((evaluation) => evaluation.exclusionReason != null)
            .toList(growable: false)
          ..sort((left, right) => _compareIds(left.nodeId, right.nodeId));
    return BdoWorkerIncomeResult(
      rankingBasis: request.rankingBasis,
      onlineHoursPerDay: request.onlineHoursPerDay,
      resourceAvailabilityPercent: request.resourceAvailabilityPercent,
      ranked: rankedWithPositions,
      excluded: excluded,
    );
  }

  BdoWorkerIncomeNodeEvaluation _evaluateCandidate(
    BdoWorkerIncomeRequest request,
    BdoWorkerIncomeNodeInput candidate,
  ) {
    if (!request.marketNetRate.isFinite ||
        request.marketNetRate <= 0 ||
        request.marketNetRate > 1) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.invalidMarketNetRate,
      );
    }
    if (!request.onlineHoursPerDay.isFinite ||
        request.onlineHoursPerDay <= 0 ||
        request.onlineHoursPerDay > 24) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.invalidOnlineHours,
      );
    }
    if (!request.resourceAvailabilityPercent.isFinite ||
        request.resourceAvailabilityPercent < 0 ||
        request.resourceAvailabilityPercent > 100) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.invalidResourceAvailability,
      );
    }
    final economics = request.dataset.productionNodesById[candidate.nodeId];
    if (economics == null) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.missingProductionEconomics,
      );
    }
    if (candidate.outputs.isEmpty) {
      return _excluded(candidate, BdoWorkerIncomeExclusionReason.noOutputs);
    }
    final pricedOutputsMissingEconomics = candidate.outputs.where(
      (output) =>
          _hasUsablePrice(output) &&
          !economics.outputItemIds.contains(output.gameItemId),
    );
    if (pricedOutputsMissingEconomics.isNotEmpty) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.incompleteProductionOutputMapping,
      );
    }
    final marketableExpectedOutputs = candidate.outputs.where(
      (output) =>
          output.isMarketable &&
          economics.outputItemIds.contains(output.gameItemId),
    );
    if (marketableExpectedOutputs.isEmpty) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.noMarketableExpectedOutputs,
      );
    }
    final pricedCount = marketableExpectedOutputs.where(_hasUsablePrice).length;
    if (pricedCount == 0) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.noUsableMarketPrices,
      );
    }
    if (pricedCount != marketableExpectedOutputs.length &&
        !request.allowPartialPriceData) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.incompleteMarketPrices,
      );
    }
    if (!_validContributionPoints(candidate)) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.invalidContributionPoints,
      );
    }

    final allowedTowns =
        candidate.allowedTownNodeIds ?? request.dataset.workerTownNodeIds;
    _AssignmentEvaluation? best;
    for (final entry in economics.townDistances.entries) {
      if (!allowedTowns.contains(entry.key)) {
        continue;
      }
      final town = request.dataset.townsByNodeId[entry.key];
      if (town == null) {
        continue;
      }
      for (final worker in town.profiles) {
        if (!economics.workerTypes.contains(worker.workerType)) {
          continue;
        }
        final evaluated = _evaluateAssignment(
          request: request,
          candidate: candidate,
          economics: economics,
          town: town,
          worker: worker,
          distance: entry.value,
        );
        if (evaluated == null) {
          continue;
        }
        if (best == null ||
            _compareAssignment(
                  evaluated,
                  best,
                  applyObservedTradeVolumeCeiling:
                      request.applyObservedTradeVolumeCeiling,
                ) <
                0) {
          best = evaluated;
        }
      }
    }
    if (best == null) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.noEligibleWorkerTown,
      );
    }

    final baseValue = request.applyObservedTradeVolumeCeiling
        ? best.adjustedNetSilverPerHour
        : best.netSilverPerHour;
    final cpResolution = _resolveContributionPointRanking(
      candidate,
      request.rankingBasis,
      baseValue,
    );
    if (cpResolution == null ||
        !baseValue.isFinite ||
        !best.netSilverPerHour.isFinite ||
        !best.adjustedNetSilverPerHour.isFinite) {
      return _excluded(
        candidate,
        BdoWorkerIncomeExclusionReason.nonFiniteCalculation,
      );
    }

    final caveats = <BdoWorkerIncomeCaveat>{
      BdoWorkerIncomeCaveat.level40MedianWorker,
      BdoWorkerIncomeCaveat.workerSkillsExcluded,
      BdoWorkerIncomeCaveat.resourceAvailabilityAssumption,
      BdoWorkerIncomeCaveat.expectedYieldEstimate,
      BdoWorkerIncomeCaveat.listedStockIsNotDemand,
      if (candidate.incrementalLodgingContributionPoints == null)
        BdoWorkerIncomeCaveat.lodgingContributionPointsExcluded,
      if (pricedCount != marketableExpectedOutputs.length)
        BdoWorkerIncomeCaveat.partialPriceDataUsed,
      if (best.liquidityConfidence == BdoWorkerIncomeConfidence.unavailable)
        BdoWorkerIncomeCaveat.observedTradeVolumeUnavailable,
      if (best.liquidityConfidence == BdoWorkerIncomeConfidence.low ||
          best.liquidityConfidence == BdoWorkerIncomeConfidence.medium)
        BdoWorkerIncomeCaveat.shortTradeObservation,
      if (request.applyObservedTradeVolumeCeiling)
        BdoWorkerIncomeCaveat.marketVolumeCeilingApplied,
      if (request.applyObservedTradeVolumeCeiling)
        BdoWorkerIncomeCaveat.marketVolumeCeilingIsOptimistic,
    };
    final displayedHourly = request.applyObservedTradeVolumeCeiling
        ? best.adjustedNetSilverPerHour
        : best.netSilverPerHour;
    return BdoWorkerIncomeNodeEvaluation._(
      rank: null,
      nodeId: candidate.nodeId,
      nodeName: candidate.nodeName,
      workerTownNodeId: best.town.nodeId,
      workerProfile: best.worker,
      cycleMinutes: best.cycleMinutes,
      cyclesPerOnlineHour: best.cyclesPerOnlineHour,
      outputs: best.outputs,
      minimumContributionPoints: candidate.minimumContributionPoints,
      incrementalContributionPoints: candidate.incrementalContributionPoints,
      incrementalLodgingContributionPoints:
          candidate.incrementalLodgingContributionPoints,
      netSilverPerOnlineHour: best.netSilverPerHour,
      liquidityAdjustedNetSilverPerOnlineHour: best.adjustedNetSilverPerHour,
      netSilverPerOnlineDay: displayedHourly * request.onlineHoursPerDay,
      netSilverPerOnlineWeek: displayedHourly * request.onlineHoursPerDay * 7,
      contributionPointsUsedForRanking: cpResolution.contributionPoints,
      rankingScore: cpResolution.score,
      zeroContributionPointRanking: cpResolution.zeroContributionPoints,
      valueWeightedStockCoverageDays: best.valueWeightedStockCoverageDays,
      marketVolumeCeilingFactor: best.marketVolumeCeilingFactor,
      incomeConfidence: pricedCount == marketableExpectedOutputs.length
          ? BdoWorkerIncomeConfidence.medium
          : BdoWorkerIncomeConfidence.low,
      liquidityConfidence: best.liquidityConfidence,
      caveats: caveats,
      exclusionReason: null,
    );
  }
}

_AssignmentEvaluation? _evaluateAssignment({
  required BdoWorkerIncomeRequest request,
  required BdoWorkerIncomeNodeInput candidate,
  required BdoWorkerProductionEconomics economics,
  required BdoWorkerTownEconomics town,
  required BdoWorkerProfileEstimate worker,
  required double distance,
}) {
  final activeWorkload =
      economics.baseWorkload * (2 - request.resourceAvailabilityPercent / 100);
  final workActions = (activeWorkload / worker.workSpeed).ceil();
  final workMinutes = 10 * workActions;
  final moveMinutes = 2 * distance / worker.movementSpeed / 60;
  final cycleMinutes = workMinutes + moveMinutes;
  if (!cycleMinutes.isFinite || cycleMinutes <= 0) {
    return null;
  }
  final cyclesPerOnlineHour = 60 / cycleMinutes;
  var netSilverPerHour = 0.0;
  var adjustedNetSilverPerHour = 0.0;
  var pricedOutputCount = 0;
  var observedVolumeCount = 0;
  var minimumObservationHours = double.infinity;
  var stockCoverageWeightedTotal = 0.0;
  var stockCoverageWeight = 0.0;
  final outputs = <BdoWorkerIncomeOutputEvaluation>[];

  for (final output in candidate.outputs) {
    final quantityPerCycle = economics.expectedQuantityPerCycle(
      output.gameItemId,
      worker,
    );
    if (quantityPerCycle <= 0) {
      continue;
    }
    final quantityPerHour = quantityPerCycle * cyclesPerOnlineHour;
    final quantityPerDay = quantityPerHour * request.onlineHoursPerDay;
    final usablePrice = _hasUsablePrice(output);
    final outputNetPerHour = usablePrice
        ? quantityPerHour * output.currentUnitPrice! * request.marketNetRate
        : null;
    double? marketVolumeFactor;
    double? stockCoverageDays;
    final dailyVolume = output.observedDailyTradeVolume;
    final observationHours = output.tradeObservationHours;
    if (dailyVolume != null &&
        dailyVolume.isFinite &&
        dailyVolume >= 0 &&
        observationHours != null &&
        observationHours.isFinite &&
        observationHours > 0) {
      observedVolumeCount += 1;
      minimumObservationHours = math.min(
        minimumObservationHours,
        observationHours,
      );
      marketVolumeFactor = quantityPerDay <= 0
          ? 1
          : (dailyVolume / quantityPerDay).clamp(0, 1).toDouble();
      final listed = output.listedStock;
      if (listed != null && listed >= 0 && dailyVolume > 0) {
        stockCoverageDays = listed / dailyVolume;
      }
    }
    if (outputNetPerHour != null) {
      pricedOutputCount += 1;
      netSilverPerHour += outputNetPerHour;
      adjustedNetSilverPerHour += outputNetPerHour * (marketVolumeFactor ?? 1);
      if (stockCoverageDays != null) {
        stockCoverageWeightedTotal += stockCoverageDays * outputNetPerHour;
        stockCoverageWeight += outputNetPerHour;
      }
    }
    outputs.add(
      BdoWorkerIncomeOutputEvaluation(
        gameItemId: output.gameItemId,
        resourceId: output.resourceId,
        name: output.name,
        isMarketable: output.isMarketable,
        expectedQuantityPerCycle: quantityPerCycle,
        expectedQuantityPerOnlineHour: quantityPerHour,
        expectedQuantityPerOnlineDay: quantityPerDay,
        currentUnitPrice: output.currentUnitPrice,
        listedStock: output.listedStock,
        observedDailyTradeVolume: output.observedDailyTradeVolume,
        tradeObservationHours: output.tradeObservationHours,
        netSilverPerOnlineHour: outputNetPerHour,
        marketVolumeCeilingFactor: marketVolumeFactor,
        stockCoverageDays: stockCoverageDays,
      ),
    );
  }
  if (pricedOutputCount == 0 || netSilverPerHour <= 0) {
    return null;
  }
  final liquidityConfidence = observedVolumeCount == 0
      ? BdoWorkerIncomeConfidence.unavailable
      : minimumObservationHours >= 24
      ? BdoWorkerIncomeConfidence.high
      : minimumObservationHours >= 6
      ? BdoWorkerIncomeConfidence.medium
      : BdoWorkerIncomeConfidence.low;
  return _AssignmentEvaluation(
    town: town,
    worker: worker,
    cycleMinutes: cycleMinutes,
    cyclesPerOnlineHour: cyclesPerOnlineHour,
    outputs: outputs,
    netSilverPerHour: netSilverPerHour,
    adjustedNetSilverPerHour: adjustedNetSilverPerHour,
    marketVolumeCeilingFactor: netSilverPerHour == 0
        ? null
        : adjustedNetSilverPerHour / netSilverPerHour,
    valueWeightedStockCoverageDays: stockCoverageWeight == 0
        ? null
        : stockCoverageWeightedTotal / stockCoverageWeight,
    liquidityConfidence: liquidityConfidence,
  );
}

bool _hasUsablePrice(BdoWorkerIncomeMarketOutputInput output) =>
    output.isMarketable &&
    output.currentUnitPrice != null &&
    output.currentUnitPrice!.isFinite &&
    output.currentUnitPrice! > 0;

bool _validContributionPoints(BdoWorkerIncomeNodeInput candidate) {
  final values = <int?>[
    candidate.minimumContributionPoints,
    candidate.incrementalContributionPoints,
    candidate.incrementalLodgingContributionPoints,
  ];
  return values.every((value) => value == null || value >= 0) &&
      candidate.minimumContributionPoints != null &&
      candidate.incrementalContributionPoints != null;
}

_ContributionPointRanking? _resolveContributionPointRanking(
  BdoWorkerIncomeNodeInput candidate,
  BdoWorkerIncomeRankingBasis basis,
  double value,
) {
  final lodging = candidate.incrementalLodgingContributionPoints ?? 0;
  final contributionPoints = switch (basis) {
    BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour => null,
    BdoWorkerIncomeRankingBasis.netSilverPerTotalContributionPointHour =>
      candidate.minimumContributionPoints! + lodging,
    BdoWorkerIncomeRankingBasis.netSilverPerAddedContributionPointHour =>
      candidate.incrementalContributionPoints! + lodging,
  };
  if (contributionPoints == null) {
    return _ContributionPointRanking(
      contributionPoints: null,
      score: value,
      zeroContributionPoints: false,
    );
  }
  if (contributionPoints == 0) {
    return _ContributionPointRanking(
      contributionPoints: 0,
      score: value,
      zeroContributionPoints: true,
    );
  }
  final score = value / contributionPoints;
  if (!score.isFinite) {
    return null;
  }
  return _ContributionPointRanking(
    contributionPoints: contributionPoints,
    score: score,
    zeroContributionPoints: false,
  );
}

int _compareAssignment(
  _AssignmentEvaluation left,
  _AssignmentEvaluation right, {
  required bool applyObservedTradeVolumeCeiling,
}) {
  if (applyObservedTradeVolumeCeiling) {
    final byAdjusted = right.adjustedNetSilverPerHour.compareTo(
      left.adjustedNetSilverPerHour,
    );
    if (byAdjusted != 0) return byAdjusted;
  }
  final byRaw = right.netSilverPerHour.compareTo(left.netSilverPerHour);
  if (byRaw != 0) return byRaw;
  final byCycle = left.cycleMinutes.compareTo(right.cycleMinutes);
  if (byCycle != 0) return byCycle;
  final byTown = _compareIds(left.town.nodeId, right.town.nodeId);
  if (byTown != 0) return byTown;
  return left.worker.id.compareTo(right.worker.id);
}

int _compareRanked(
  BdoWorkerIncomeNodeEvaluation left,
  BdoWorkerIncomeNodeEvaluation right,
) {
  if (left.zeroContributionPointRanking != right.zeroContributionPointRanking) {
    return left.zeroContributionPointRanking ? -1 : 1;
  }
  final byScore = right.rankingScore!.compareTo(left.rankingScore!);
  if (byScore != 0) return byScore;
  final leftStock = left.valueWeightedStockCoverageDays;
  final rightStock = right.valueWeightedStockCoverageDays;
  if (leftStock != null || rightStock != null) {
    if (leftStock == null) return 1;
    if (rightStock == null) return -1;
    final byStock = leftStock.compareTo(rightStock);
    if (byStock != 0) return byStock;
  }
  final byHourly = right.netSilverPerOnlineHour!.compareTo(
    left.netSilverPerOnlineHour!,
  );
  if (byHourly != 0) return byHourly;
  return _compareIds(left.nodeId, right.nodeId);
}

BdoWorkerIncomeNodeEvaluation _excluded(
  BdoWorkerIncomeNodeInput candidate,
  BdoWorkerIncomeExclusionReason reason,
) {
  return BdoWorkerIncomeNodeEvaluation._(
    rank: null,
    nodeId: candidate.nodeId,
    nodeName: candidate.nodeName,
    workerTownNodeId: null,
    workerProfile: null,
    cycleMinutes: null,
    cyclesPerOnlineHour: null,
    outputs: const <BdoWorkerIncomeOutputEvaluation>[],
    minimumContributionPoints: candidate.minimumContributionPoints,
    incrementalContributionPoints: candidate.incrementalContributionPoints,
    incrementalLodgingContributionPoints:
        candidate.incrementalLodgingContributionPoints,
    netSilverPerOnlineHour: null,
    liquidityAdjustedNetSilverPerOnlineHour: null,
    netSilverPerOnlineDay: null,
    netSilverPerOnlineWeek: null,
    contributionPointsUsedForRanking: null,
    rankingScore: null,
    zeroContributionPointRanking: false,
    valueWeightedStockCoverageDays: null,
    marketVolumeCeilingFactor: null,
    incomeConfidence: BdoWorkerIncomeConfidence.unavailable,
    liquidityConfidence: BdoWorkerIncomeConfidence.unavailable,
    caveats: const <BdoWorkerIncomeCaveat>{},
    exclusionReason: reason,
  );
}

final class _ContributionPointRanking {
  const _ContributionPointRanking({
    required this.contributionPoints,
    required this.score,
    required this.zeroContributionPoints,
  });

  final int? contributionPoints;
  final double score;
  final bool zeroContributionPoints;
}

final class _AssignmentEvaluation {
  const _AssignmentEvaluation({
    required this.town,
    required this.worker,
    required this.cycleMinutes,
    required this.cyclesPerOnlineHour,
    required this.outputs,
    required this.netSilverPerHour,
    required this.adjustedNetSilverPerHour,
    required this.marketVolumeCeilingFactor,
    required this.valueWeightedStockCoverageDays,
    required this.liquidityConfidence,
  });

  final BdoWorkerTownEconomics town;
  final BdoWorkerProfileEstimate worker;
  final double cycleMinutes;
  final double cyclesPerOnlineHour;
  final List<BdoWorkerIncomeOutputEvaluation> outputs;
  final double netSilverPerHour;
  final double adjustedNetSilverPerHour;
  final double? marketVolumeCeilingFactor;
  final double? valueWeightedStockCoverageDays;
  final BdoWorkerIncomeConfidence liquidityConfidence;
}

int _compareIds(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final byNumber = leftNumber.compareTo(rightNumber);
    if (byNumber != 0) return byNumber;
  }
  return left.compareTo(right);
}
