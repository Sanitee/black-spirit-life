import 'dart:math' as math;

import 'package:bdo_map_core/src/economics/worker_economics_data.dart';
import 'package:bdo_map_core/src/economics/worker_income_estimator.dart';
import 'package:bdo_map_core/src/economics/worker_income_portfolio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const portfolioEstimator = BdoWorkerIncomePortfolioEstimator();

  test('reuses one selected context across shared-cap candidates', () {
    final selected = <BdoWorkerIncomeNodeEvaluation>[
      _node(
        nodeId: 'selected-a',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 1, observedDailyTradeVolume: 80),
          _output(itemId: 2, price: 600),
        ],
      ),
      _node(
        nodeId: 'selected-b',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 1, observedDailyTradeVolume: 120),
          _output(
            itemId: 3,
            observedDailyTradeVolume: -1,
            tradeObservationHours: 24,
          ),
        ],
      ),
    ];
    final candidates = <BdoWorkerIncomeNodeEvaluation>[
      _node(
        nodeId: 'lowers-shared-cap',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 1, observedDailyTradeVolume: 60),
        ],
      ),
      _node(
        nodeId: 'keeps-shared-cap',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 1, observedDailyTradeVolume: 200),
        ],
      ),
      _node(
        nodeId: 'uncapped-new-item',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 4, price: 750),
        ],
      ),
    ];
    final marginal = portfolioEstimator.prepareMarginalEvaluator(
      BdoWorkerIncomePortfolioRequest(nodes: selected, onlineHoursPerDay: 8),
    );

    expect(marginal.selectedNodeCount, 2);
    for (final candidate in candidates) {
      _expectEquivalent(
        marginal: marginal,
        selected: selected,
        candidate: candidate,
      );
    }

    expect(
      marginal.evaluate(candidates.first),
      isNegative,
      reason: 'Lower conflicting evidence reduces the whole shared ceiling.',
    );
    expect(marginal.evaluate(candidates.last), isPositive);
  });

  test('deduplicates node IDs with the full estimator first-wins rule', () {
    final retained = _node(
      nodeId: 'same-node',
      outputs: <BdoWorkerIncomeMarketOutputInput>[
        _output(itemId: 1, price: 1000, observedDailyTradeVolume: 70),
      ],
    );
    final ignored = _node(
      nodeId: 'same-node',
      outputs: <BdoWorkerIncomeMarketOutputInput>[
        _output(itemId: 1, price: 9000, observedDailyTradeVolume: 5),
      ],
    );
    final selected = <BdoWorkerIncomeNodeEvaluation>[
      retained,
      ignored,
      retained,
    ];
    final marginal = BdoWorkerIncomePortfolioMarginalEvaluator(
      selectedNodes: selected,
      onlineHoursPerDay: 8,
    );

    expect(marginal.selectedNodeCount, 1);
    expect(marginal.containsSelectedNodeId('same-node'), isTrue);
    expect(marginal.evaluate(ignored), 0);
    expect(
      _fullMarginal(selected: selected, candidate: ignored),
      0,
      reason: 'The full portfolio also ignores a later duplicate node ID.',
    );

    final distinctCandidate = _node(
      nodeId: 'different-node',
      outputs: <BdoWorkerIncomeMarketOutputInput>[
        _output(itemId: 1, price: 1200, observedDailyTradeVolume: 50),
      ],
    );
    _expectEquivalent(
      marginal: marginal,
      selected: selected,
      candidate: distinctCandidate,
    );
  });

  test('ignores missing and invalid trade evidence exactly', () {
    final selected = <BdoWorkerIncomeNodeEvaluation>[
      _node(
        nodeId: 'missing',
        outputs: <BdoWorkerIncomeMarketOutputInput>[_output(itemId: 5)],
      ),
      _node(
        nodeId: 'nan-volume',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(
            itemId: 5,
            observedDailyTradeVolume: double.nan,
            tradeObservationHours: 24,
          ),
        ],
      ),
      _node(
        nodeId: 'invalid-hours',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(
            itemId: 6,
            observedDailyTradeVolume: 20,
            tradeObservationHours: 0,
          ),
        ],
      ),
    ];
    final selectedPortfolio = _portfolio(selected);
    expect(
      selectedPortfolio.items
          .firstWhere((item) => item.gameItemId == 5)
          .observedDailyTradeVolume,
      isNull,
    );
    expect(
      selectedPortfolio.items
          .firstWhere((item) => item.gameItemId == 6)
          .observedDailyTradeVolume,
      isNull,
    );

    final marginal = BdoWorkerIncomePortfolioMarginalEvaluator(
      selectedNodes: selected,
      onlineHoursPerDay: 8,
    );
    final candidates = <BdoWorkerIncomeNodeEvaluation>[
      _node(
        nodeId: 'still-invalid',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(
            itemId: 5,
            observedDailyTradeVolume: -10,
            tradeObservationHours: 48,
          ),
        ],
      ),
      _node(
        nodeId: 'first-valid-observation',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(
            itemId: 5,
            observedDailyTradeVolume: 25,
            tradeObservationHours: 48,
          ),
        ],
      ),
    ];

    for (final candidate in candidates) {
      _expectEquivalent(
        marginal: marginal,
        selected: selected,
        candidate: candidate,
      );
    }
  });

  test('uses the lowest conflicting evidence for exact marginal value', () {
    final selected = <BdoWorkerIncomeNodeEvaluation>[
      _node(
        nodeId: 'snapshot-100',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 7, observedDailyTradeVolume: 100),
        ],
      ),
      _node(
        nodeId: 'snapshot-60',
        outputs: <BdoWorkerIncomeMarketOutputInput>[
          _output(itemId: 7, observedDailyTradeVolume: 60),
        ],
      ),
    ];
    final unchangedMinimum = _node(
      nodeId: 'snapshot-80',
      outputs: <BdoWorkerIncomeMarketOutputInput>[
        _output(itemId: 7, observedDailyTradeVolume: 80),
      ],
    );
    final lowerMinimum = _node(
      nodeId: 'snapshot-40',
      outputs: <BdoWorkerIncomeMarketOutputInput>[
        _output(itemId: 7, observedDailyTradeVolume: 40),
      ],
    );
    final marginal = BdoWorkerIncomePortfolioMarginalEvaluator(
      selectedNodes: selected,
      onlineHoursPerDay: 8,
    );

    for (final candidate in <BdoWorkerIncomeNodeEvaluation>[
      unchangedMinimum,
      lowerMinimum,
    ]) {
      _expectEquivalent(
        marginal: marginal,
        selected: selected,
        candidate: candidate,
      );
      final combined = _portfolio(<BdoWorkerIncomeNodeEvaluation>[
        ...selected,
        candidate,
      ]);
      expect(combined.items.single.hasConflictingTradeEvidence, isTrue);
      expect(
        combined.items.single.observedDailyTradeVolume,
        candidate == lowerMinimum ? 40 : 60,
      );
    }
  });

  test('validates online hours before preparing selected state', () {
    for (final hours in <double>[0, -1, 25, double.nan, double.infinity]) {
      expect(
        () => BdoWorkerIncomePortfolioMarginalEvaluator(
          selectedNodes: const <BdoWorkerIncomeNodeEvaluation>[],
          onlineHoursPerDay: hours,
        ),
        throwsArgumentError,
      );
    }
  });
}

void _expectEquivalent({
  required BdoWorkerIncomePortfolioMarginalEvaluator marginal,
  required List<BdoWorkerIncomeNodeEvaluation> selected,
  required BdoWorkerIncomeNodeEvaluation candidate,
}) {
  final expected = _fullMarginal(selected: selected, candidate: candidate);
  final tolerance = math.max(1e-8, expected.abs() * 1e-11);
  expect(
    marginal.evaluate(candidate),
    closeTo(expected, tolerance),
    reason: 'Candidate ${candidate.nodeId} must match full recomputation.',
  );
}

double _fullMarginal({
  required List<BdoWorkerIncomeNodeEvaluation> selected,
  required BdoWorkerIncomeNodeEvaluation candidate,
}) =>
    _portfolio(<BdoWorkerIncomeNodeEvaluation>[
      ...selected,
      candidate,
    ]).liquidityAdjustedNetSilverPerOnlineHour -
    _portfolio(selected).liquidityAdjustedNetSilverPerOnlineHour;

BdoWorkerIncomePortfolioResult _portfolio(
  List<BdoWorkerIncomeNodeEvaluation> nodes,
) => const BdoWorkerIncomePortfolioEstimator().evaluate(
  BdoWorkerIncomePortfolioRequest(nodes: nodes, onlineHoursPerDay: 8),
);

BdoWorkerIncomeNodeEvaluation _node({
  required String nodeId,
  required List<BdoWorkerIncomeMarketOutputInput> outputs,
}) {
  final result = const BdoWorkerIncomeEstimator().evaluate(
    BdoWorkerIncomeRequest(
      dataset: _dataset(
        nodeId: nodeId,
        itemIds: outputs.map((output) => output.gameItemId),
      ),
      candidates: <BdoWorkerIncomeNodeInput>[
        BdoWorkerIncomeNodeInput(
          nodeId: nodeId,
          nodeName: nodeId,
          outputs: outputs,
          minimumContributionPoints: 2,
          incrementalContributionPoints: 1,
        ),
      ],
      marketNetRate: .65,
      onlineHoursPerDay: 8,
      rankingBasis: BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour,
      allowPartialPriceData: true,
    ),
  );
  expect(result.excluded, isEmpty);
  return result.ranked.single;
}

BdoWorkerIncomeMarketOutputInput _output({
  required int itemId,
  double? price = 1000,
  double? observedDailyTradeVolume,
  double? tradeObservationHours = 24,
}) => BdoWorkerIncomeMarketOutputInput(
  gameItemId: itemId,
  resourceId: 'item:$itemId',
  name: 'Item $itemId',
  isMarketable: true,
  currentUnitPrice: price,
  listedStock: 0,
  observedDailyTradeVolume: observedDailyTradeVolume,
  tradeObservationHours: tradeObservationHours,
);

BdoWorkerEconomicsDataset _dataset({
  required String nodeId,
  required Iterable<int> itemIds,
}) {
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
  final uniqueItemIds = itemIds.toSet();
  return BdoWorkerEconomicsDataset(
    schemaVersion: 1,
    manifest: BdoWorkerEconomicsManifest(
      datasetVersion: 'marginal-test',
      generatedAt: DateTime.utc(2026, 7, 30),
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
      nodeId: BdoWorkerProductionEconomics(
        nodeId: nodeId,
        baseWorkload: 100,
        workerTypes: const <int>{0},
        standardYields: <int, double>{
          for (final itemId in uniqueItemIds) itemId: 10,
        },
        giantYields: <int, double>{
          for (final itemId in uniqueItemIds) itemId: 12,
        },
        luckyBonusYields: <int, double>{
          for (final itemId in uniqueItemIds) itemId: 2,
        },
        townDistances: const <String, double>{'town': 600},
      ),
    },
  );
}
