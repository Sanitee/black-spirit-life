import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const estimator = BdoWorkerIncomeEstimator();

  test('calculates tax-adjusted online hour, day, week, and CP income', () {
    final result = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );

    expect(result.excluded, isEmpty);
    final node = result.ranked.single;
    expect(node.workerTownNodeId, 'town');
    expect(node.workerProfile!.label, 'Human');
    expect(node.cycleMinutes, closeTo(12, 1e-9));
    expect(node.cyclesPerOnlineHour, closeTo(5, 1e-9));
    expect(node.outputs.single.expectedQuantityPerCycle, closeTo(10.4, 1e-9));
    expect(node.netSilverPerOnlineHour, closeTo(33800, 1e-6));
    expect(node.netSilverPerOnlineDay, closeTo(270400, 1e-6));
    expect(node.netSilverPerOnlineWeek, closeTo(1892800, 1e-6));
    expect(node.contributionPointsUsedForRanking, 2);
    expect(node.rankingScore, closeTo(16900, 1e-6));
    expect(
      node.caveats,
      contains(BdoWorkerIncomeCaveat.lodgingContributionPointsExcluded),
    );
  });

  test('optional observed-sales ceiling uses demand history, not stock', () {
    final result = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            observedDailyTradeVolume: 20,
            tradeObservationHours: 48,
            listedStock: 100,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
        rankingBasis: BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour,
        applyObservedTradeVolumeCeiling: true,
      ),
    );

    final node = result.ranked.single;
    final expectedDaily = node.outputs.single.expectedQuantityPerOnlineDay;
    expect(expectedDaily, closeTo(416, 1e-9));
    expect(node.marketVolumeCeilingFactor, closeTo(20 / 416, 1e-9));
    expect(
      node.liquidityAdjustedNetSilverPerOnlineHour,
      closeTo(33800 * 20 / 416, 1e-6),
    );
    expect(node.rankingScore, node.liquidityAdjustedNetSilverPerOnlineHour);
    expect(node.outputs.single.stockCoverageDays, 5);
    expect(node.liquidityConfidence, BdoWorkerIncomeConfidence.high);
    expect(
      node.caveats,
      contains(BdoWorkerIncomeCaveat.marketVolumeCeilingIsOptimistic),
    );
  });

  test(
    'portfolio shares one observed item volume across every selected node',
    () {
      final independent = estimator.evaluate(
        BdoWorkerIncomeRequest(
          dataset: _dataset(twoNodes: true),
          candidates: <BdoWorkerIncomeNodeInput>[
            _candidate(
              minimumContributionPoints: 4,
              incrementalContributionPoints: 2,
              observedDailyTradeVolume: 20,
              tradeObservationHours: 48,
            ),
            _candidate(
              nodeId: 'node-2',
              minimumContributionPoints: 4,
              incrementalContributionPoints: 2,
              observedDailyTradeVolume: 20,
              tradeObservationHours: 48,
            ),
          ],
          marketNetRate: .65,
          onlineHoursPerDay: 8,
          rankingBasis: BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour,
          applyObservedTradeVolumeCeiling: true,
        ),
      );

      expect(independent.ranked, hasLength(2));
      expect(
        independent.ranked
            .map(
              (node) =>
                  node.outputs.single.expectedQuantityPerOnlineDay *
                  node.outputs.single.marketVolumeCeilingFactor!,
            )
            .reduce((left, right) => left + right),
        closeTo(40, 1e-9),
        reason:
            'Independent comparisons deliberately let each node use the full '
            'market ceiling.',
      );

      final portfolio = const BdoWorkerIncomePortfolioEstimator().evaluate(
        BdoWorkerIncomePortfolioRequest(
          nodes: independent.ranked,
          onlineHoursPerDay: 8,
        ),
      );

      final item = portfolio.items.single;
      expect(item.expectedQuantityPerOnlineDay, closeTo(832, 1e-9));
      expect(item.observedDailyTradeVolume, 20);
      expect(item.sharedMarketVolumeCeilingFactor, closeTo(20 / 832, 1e-12));
      expect(item.sellableQuantityPerOnlineDay, closeTo(20, 1e-9));
      expect(
        portfolio.nodes
            .expand((node) => node.outputs)
            .map((output) => output.sellableQuantityPerOnlineDay)
            .reduce((left, right) => left + right),
        closeTo(20, 1e-9),
      );
      expect(
        portfolio.liquidityAdjustedNetSilverPerOnlineHour,
        closeTo(67600 * 20 / 832, 1e-6),
      );
      expect(
        portfolio.liquidityAdjustedNetSilverPerOnlineDay,
        closeTo(portfolio.liquidityAdjustedNetSilverPerOnlineHour * 8, 1e-6),
      );
      expect(
        portfolio.liquidityAdjustedNetSilverPerOnlineWeek,
        closeTo(
          portfolio.liquidityAdjustedNetSilverPerOnlineHour * 8 * 7,
          1e-6,
        ),
      );
    },
  );

  test('portfolio uses the lower of conflicting shared trade snapshots', () {
    final independent = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(twoNodes: true),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            observedDailyTradeVolume: 20,
            tradeObservationHours: 48,
          ),
          _candidate(
            nodeId: 'node-2',
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            observedDailyTradeVolume: 30,
            tradeObservationHours: 24,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );

    final portfolio = const BdoWorkerIncomePortfolioEstimator().evaluate(
      BdoWorkerIncomePortfolioRequest(
        nodes: independent.ranked,
        onlineHoursPerDay: 8,
      ),
    );

    final item = portfolio.items.single;
    expect(item.observedDailyTradeVolume, 20);
    expect(item.tradeObservationHours, 24);
    expect(item.hasConflictingTradeEvidence, isTrue);
    expect(item.sellableQuantityPerOnlineDay, closeTo(20, 1e-9));
  });

  test('listed stock alone never becomes observed demand', () {
    final result = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            listedStock: 999999,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
        applyObservedTradeVolumeCeiling: true,
      ),
    );

    final node = result.ranked.single;
    expect(node.marketVolumeCeilingFactor, 1);
    expect(
      node.liquidityAdjustedNetSilverPerOnlineHour,
      node.netSilverPerOnlineHour,
    );
    expect(node.liquidityConfidence, BdoWorkerIncomeConfidence.unavailable);
    expect(
      node.caveats,
      contains(BdoWorkerIncomeCaveat.listedStockIsNotDemand),
    );
  });

  test('adds supplied lodging CP to total and incremental CP ratios', () {
    final result = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            incrementalLodgingContributionPoints: 3,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );

    final node = result.ranked.single;
    expect(node.contributionPointsUsedForRanking, 5);
    expect(node.rankingScore, closeTo(6760, 1e-6));
    expect(
      node.caveats,
      isNot(contains(BdoWorkerIncomeCaveat.lodgingContributionPointsExcluded)),
    );
  });

  test('reports unavailable candidates without inventing estimates', () {
    final missingPrices = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            price: null,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );
    expect(
      missingPrices.excluded.single.exclusionReason,
      BdoWorkerIncomeExclusionReason.noUsableMarketPrices,
    );

    final noTown = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
            allowedTownNodeIds: const <String>{},
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );
    expect(
      noTown.excluded.single.exclusionReason,
      BdoWorkerIncomeExclusionReason.noEligibleWorkerTown,
    );
  });

  test('rejects a priced map output missing from pinned yield economics', () {
    final result = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(),
        candidates: <BdoWorkerIncomeNodeInput>[
          BdoWorkerIncomeNodeInput(
            nodeId: 'node',
            nodeName: 'Mismatched production node',
            outputs: const <BdoWorkerIncomeMarketOutputInput>[
              BdoWorkerIncomeMarketOutputInput(
                gameItemId: 1,
                resourceId: 'item:1',
                name: 'Known byproduct',
                isMarketable: true,
                currentUnitPrice: 1000,
                listedStock: 0,
              ),
              BdoWorkerIncomeMarketOutputInput(
                gameItemId: 2,
                resourceId: 'item:2',
                name: 'Unmapped primary output',
                isMarketable: true,
                currentUnitPrice: 10000,
                listedStock: 0,
              ),
            ],
            minimumContributionPoints: 4,
            incrementalContributionPoints: 2,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );

    expect(result.ranked, isEmpty);
    expect(
      result.excluded.single.exclusionReason,
      BdoWorkerIncomeExclusionReason.incompleteProductionOutputMapping,
    );
  });

  test('zero added CP ranks before a positive-CP candidate', () {
    final result = estimator.evaluate(
      BdoWorkerIncomeRequest(
        dataset: _dataset(twoNodes: true),
        candidates: <BdoWorkerIncomeNodeInput>[
          _candidate(
            nodeId: 'node-2',
            minimumContributionPoints: 2,
            incrementalContributionPoints: 1,
            price: 100000,
          ),
          _candidate(
            minimumContributionPoints: 4,
            incrementalContributionPoints: 0,
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );

    expect(result.ranked.first.nodeId, 'node');
    expect(result.ranked.first.zeroContributionPointRanking, isTrue);
  });
}

BdoWorkerIncomeNodeInput _candidate({
  String nodeId = 'node',
  required int minimumContributionPoints,
  required int incrementalContributionPoints,
  int? incrementalLodgingContributionPoints,
  double? price = 1000,
  int? listedStock,
  double? observedDailyTradeVolume,
  double? tradeObservationHours,
  Set<String>? allowedTownNodeIds,
}) {
  return BdoWorkerIncomeNodeInput(
    nodeId: nodeId,
    nodeName: nodeId,
    outputs: <BdoWorkerIncomeMarketOutputInput>[
      BdoWorkerIncomeMarketOutputInput(
        gameItemId: 1,
        resourceId: 'item:1',
        name: 'Output',
        isMarketable: true,
        currentUnitPrice: price,
        listedStock: listedStock,
        observedDailyTradeVolume: observedDailyTradeVolume,
        tradeObservationHours: tradeObservationHours,
      ),
    ],
    minimumContributionPoints: minimumContributionPoints,
    incrementalContributionPoints: incrementalContributionPoints,
    incrementalLodgingContributionPoints: incrementalLodgingContributionPoints,
    allowedTownNodeIds: allowedTownNodeIds,
  );
}

BdoWorkerEconomicsDataset _dataset({bool twoNodes = false}) {
  const worker = BdoWorkerProfileEstimate(
    id: 'worker',
    label: 'Human',
    workerType: 0,
    characterKey: 1,
    isGiant: false,
    workSpeed: 100,
    movementSpeed: 10,
    luck: 20,
  );
  BdoWorkerProductionEconomics node(String id) => BdoWorkerProductionEconomics(
    nodeId: id,
    baseWorkload: 100,
    workerTypes: const <int>{0},
    standardYields: const <int, double>{1: 10},
    giantYields: const <int, double>{1: 12},
    luckyBonusYields: const <int, double>{1: 2},
    townDistances: const <String, double>{'town': 600},
  );
  return BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: BdoWorkerEconomicsManifest(
      datasetVersion: 'test',
      generatedAt: DateTime.utc(2026, 7, 29),
      sourceRepository: Uri.parse('https://example.invalid/source'),
      sourceCommit: 'test',
      sourcePackageVersion: 'test',
      sourceLicenseExpression: 'test',
      upstreamWorkermanCommit: 'test',
      permittedUse: 'test',
      sourceSha256: const <String, String>{'test': 'test'},
      assumptions: const <String>['test'],
    ),
    townsByNodeId: <String, BdoWorkerTownEconomics>{
      'town': BdoWorkerTownEconomics(
        nodeId: 'town',
        regionId: 1,
        baseWorkerSlots: 1,
        profiles: const <BdoWorkerProfileEstimate>[worker],
      ),
    },
    productionNodesById: <String, BdoWorkerProductionEconomics>{
      'node': node('node'),
      if (twoNodes) 'node-2': node('node-2'),
    },
  );
}
