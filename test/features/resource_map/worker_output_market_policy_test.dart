import 'package:bdo_craft_planner_flutter/features/resource_map/worker_output_market_policy.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins the verified non-Central-Market Morning Light outputs', () {
    expect(WorkerOutputMarketPolicy.nonCentralMarketItemIds, const <int>{
      65267,
      820035,
      820036,
      820039,
    });
  });

  test(
    'known rare outputs cannot inherit a sale value from stale evidence',
    () {
      for (final itemId in WorkerOutputMarketPolicy.nonCentralMarketItemIds) {
        final evidence = resolveWorkerOutputMarketEvidence(
          resourceId: 'item:$itemId',
          outputName: 'Known non-market output',
          gameItemId: itemId,
          explicitlyUnlisted: false,
          hasBundledMarketId: true,
          currentUnitPrice: 999999999,
          listedStock: 123,
          observedDailyTradeVolume: 45,
          tradeObservationHours: 24,
        );

        expect(evidence.isMarketable, isFalse, reason: '$itemId');
        expect(evidence.currentUnitPrice, isNull, reason: '$itemId');
        expect(evidence.listedStock, isNull, reason: '$itemId');
        expect(evidence.observedDailyTradeVolume, isNull, reason: '$itemId');
        expect(evidence.tradeObservationHours, isNull, reason: '$itemId');
      }
    },
  );

  test('ordinary worker outputs retain normal market evidence behavior', () {
    final evidence = resolveWorkerOutputMarketEvidence(
      resourceId: 'item:4001',
      outputName: 'Iron Ore',
      gameItemId: 4001,
      explicitlyUnlisted: false,
      hasBundledMarketId: true,
      currentUnitPrice: 5100,
      listedStock: 1200,
      observedDailyTradeVolume: 800,
      tradeObservationHours: 24,
    );

    expect(evidence.isMarketable, isTrue);
    expect(evidence.currentUnitPrice, 5100);
    expect(evidence.listedStock, 1200);
    expect(evidence.observedDailyTradeVolume, 800);
    expect(evidence.tradeObservationHours, 24);
  });

  test('explicitly unlisted ordinary output remains non-marketable', () {
    final evidence = resolveWorkerOutputMarketEvidence(
      resourceId: 'item:1',
      outputName: 'Unlisted output',
      gameItemId: 1,
      explicitlyUnlisted: true,
      hasBundledMarketId: true,
      currentUnitPrice: null,
      listedStock: null,
      observedDailyTradeVolume: null,
      tradeObservationHours: null,
    );

    expect(evidence.isMarketable, isFalse);
  });

  test('non-market rare does not lower a priced node income confidence', () {
    final trace = resolveWorkerOutputMarketEvidence(
      resourceId: 'item:5960',
      outputName: 'Trace of Nature',
      gameItemId: 5960,
      explicitlyUnlisted: false,
      hasBundledMarketId: true,
      currentUnitPrice: 10000,
      listedStock: 100,
      observedDailyTradeVolume: null,
      tradeObservationHours: null,
    );
    final forestCrystal = resolveWorkerOutputMarketEvidence(
      resourceId: 'item:820036',
      outputName: 'Forest Crystal',
      gameItemId: 820036,
      explicitlyUnlisted: false,
      hasBundledMarketId: true,
      currentUnitPrice: null,
      listedStock: null,
      observedDailyTradeVolume: null,
      tradeObservationHours: null,
    );
    final result = const BdoWorkerIncomeEstimator().evaluate(
      BdoWorkerIncomeRequest(
        dataset: _morningLightEconomics(),
        candidates: <BdoWorkerIncomeNodeInput>[
          BdoWorkerIncomeNodeInput(
            nodeId: '1807',
            nodeName: 'Dokkebi Forest - Excavation',
            outputs: <BdoWorkerIncomeMarketOutputInput>[
              _incomeOutput(trace, 5960),
              _incomeOutput(forestCrystal, 820036),
            ],
            minimumContributionPoints: 3,
            incrementalContributionPoints: 3,
            allowedTownNodeIds: const <String>{'1781'},
          ),
        ],
        marketNetRate: .65,
        onlineHoursPerDay: 8,
      ),
    );

    expect(result.excluded, isEmpty);
    expect(result.ranked, hasLength(1));
    expect(
      result.ranked.single.incomeConfidence,
      BdoWorkerIncomeConfidence.medium,
    );
    expect(
      result.ranked.single.caveats,
      isNot(contains(BdoWorkerIncomeCaveat.partialPriceDataUsed)),
    );
    final rareEvaluation = result.ranked.single.outputs.singleWhere(
      (output) => output.gameItemId == 820036,
    );
    expect(rareEvaluation.expectedQuantityPerCycle, closeTo(.0126, 1e-9));
    expect(rareEvaluation.netSilverPerOnlineHour, isNull);
  });
}

BdoWorkerIncomeMarketOutputInput _incomeOutput(
  MarketValueOutputInput evidence,
  int gameItemId,
) {
  return BdoWorkerIncomeMarketOutputInput(
    gameItemId: gameItemId,
    resourceId: evidence.outputId,
    name: evidence.outputName,
    isMarketable: evidence.isMarketable,
    currentUnitPrice: evidence.currentUnitPrice,
    listedStock: evidence.listedStock,
    observedDailyTradeVolume: evidence.observedDailyTradeVolume,
    tradeObservationHours: evidence.tradeObservationHours,
  );
}

BdoWorkerEconomicsDataset _morningLightEconomics() {
  return BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: BdoWorkerEconomicsManifest(
      datasetVersion: 'test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid'),
      sourceCommit: 'test',
      sourcePackageVersion: 'test',
      sourceLicenseExpression: 'test',
      upstreamWorkermanCommit: 'test',
      permittedUse: 'test',
      sourceSha256: const <String, String>{'test': 'test'},
      assumptions: const <String>['test'],
    ),
    townsByNodeId: <String, BdoWorkerTownEconomics>{
      '1781': BdoWorkerTownEconomics(
        nodeId: '1781',
        regionId: 1210,
        baseWorkerSlots: 1,
        profiles: const <BdoWorkerProfileEstimate>[
          BdoWorkerProfileEstimate(
            id: '6:8050',
            label: 'Worker type 6',
            workerType: 6,
            characterKey: 8050,
            isGiant: false,
            workSpeed: 152.05,
            movementSpeed: 8.41,
            luck: 12.83,
          ),
        ],
      ),
    },
    productionNodesById: <String, BdoWorkerProductionEconomics>{
      '1807': BdoWorkerProductionEconomics(
        nodeId: '1807',
        baseWorkload: 5100,
        workerTypes: const <int>{6},
        standardYields: const <int, double>{5960: 4, 820036: .0126},
        giantYields: const <int, double>{5960: 6.33340566, 820036: .01267643},
        luckyBonusYields: const <int, double>{},
        townDistances: const <String, double>{'1781': 2828},
      ),
    },
  );
}
