import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'market output inputs have value semantics for stable UI projections',
    () {
      const first = MarketValueOutputInput(
        outputId: 'ash-timber',
        outputName: 'Ash Timber',
        isMarketable: true,
        currentUnitPrice: 1250,
        listedStock: 42,
      );
      const same = MarketValueOutputInput(
        outputId: 'ash-timber',
        outputName: 'Ash Timber',
        isMarketable: true,
        currentUnitPrice: 1250,
        listedStock: 42,
      );
      const changed = MarketValueOutputInput(
        outputId: 'ash-timber',
        outputName: 'Ash Timber',
        isMarketable: true,
        currentUnitPrice: 1300,
        listedStock: 42,
      );

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(changed));
    },
  );

  group('market-value semantics', () {
    test('uses tax-adjusted unit value and excludes nonmarketable outputs', () {
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'iron-node',
            name: 'Coastal Cave - Mining',
            outputs: <MarketValueOutputInput>[
              _output(id: 'iron', name: 'Iron Ore', price: 100, stock: 20),
              _output(
                id: 'sack',
                name: "Miner's Sack",
                price: 5000,
                stock: 1,
                marketable: false,
              ),
            ],
          ),
        ],
        marketNetRate: .65,
      );

      final recommendation = result.ranked.single;
      expect(recommendation.rank, 1);
      expect(recommendation.grossUnitBasketValue, 100);
      expect(recommendation.netUnitBasketValue, 65);
      expect(recommendation.stockAdjustedNetValueSignal, 65);
      expect(recommendation.rankingScore, 65);
      expect(recommendation.confidence, MarketValueDataConfidence.high);
      expect(
        recommendation.caveats,
        contains(MarketValueCaveat.nonMarketableOutputsExcluded),
      );
      final sack = recommendation.outputs.singleWhere(
        (output) => output.outputId == 'sack',
      );
      expect(
        sack.exclusionReason,
        MarketValueOutputExclusionReason.nonMarketable,
      );
      expect(sack.netUnitValue, isNull);
    });

    test('compares exactly one unit of every included output', () {
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'multi',
            outputs: <MarketValueOutputInput>[
              _output(id: 'main', name: 'Main Output', price: 100),
              _output(id: 'side', name: 'Side Output', price: 40),
            ],
          ),
        ],
        marketNetRate: .845,
      );

      final recommendation = result.ranked.single;
      expect(recommendation.grossUnitBasketValue, 140);
      expect(recommendation.netUnitBasketValue, closeTo(118.3, 1e-12));
      expect(
        result.globalCaveats,
        containsAll(<MarketValueCaveat>{
          MarketValueCaveat.oneUnitComparisonBasket,
          MarketValueCaveat.productionYieldUnknown,
          MarketValueCaveat.productionCycleTimeUnknown,
          MarketValueCaveat.salesVelocityUnknown,
        }),
      );
      expect(
        MarketValueCaveat.oneUnitComparisonBasket.description,
        contains('not actual node yield'),
      );
      expect(
        MarketValueCaveat.salesVelocityUnknown.description,
        contains('not available'),
      );
    });
  });

  group('contribution-point ranking', () {
    test('orders by net unit basket value per minimum CP', () {
      final candidates = <MarketValueNodeInput>[
        _node(
          id: 'expensive-path',
          name: 'Expensive Path',
          minimumCp: 10,
          outputs: <MarketValueOutputInput>[
            _output(id: 'a', name: 'A', price: 100),
          ],
        ),
        _node(
          id: 'efficient-path',
          name: 'Efficient Path',
          minimumCp: 3,
          outputs: <MarketValueOutputInput>[
            _output(id: 'b', name: 'B', price: 60),
          ],
        ),
      ];

      final first = _evaluate(
        candidates: candidates,
        marketNetRate: 1,
        basis: MarketValueRankingBasis
            .netUnitBasketValuePerMinimumContributionPoint,
      );
      final reversed = _evaluate(
        candidates: candidates.reversed,
        marketNetRate: 1,
        basis: MarketValueRankingBasis
            .netUnitBasketValuePerMinimumContributionPoint,
      );

      expect(first.ranked.map((item) => item.nodeId), <String>[
        'efficient-path',
        'expensive-path',
      ]);
      expect(reversed.ranked.map((item) => item.nodeId), <String>[
        'efficient-path',
        'expensive-path',
      ]);
      expect(first.ranked.first.rankingScore, 20);
      expect(first.ranked.last.rankingScore, 10);
      expect(first.ranked.first.contributionPointsUsedForRanking, 3);
    });

    test(
      'orders zero incremental CP before ratios without dividing by zero',
      () {
        final result = _evaluate(
          candidates: <MarketValueNodeInput>[
            _node(
              id: 'paid',
              incrementalCp: 1,
              outputs: <MarketValueOutputInput>[
                _output(id: 'paid-output', name: 'Paid', price: 1000),
              ],
            ),
            _node(
              id: 'already-connected',
              incrementalCp: 0,
              outputs: <MarketValueOutputInput>[
                _output(id: 'free-output', name: 'Free', price: 20),
              ],
            ),
          ],
          marketNetRate: 1,
          basis: MarketValueRankingBasis
              .netUnitBasketValuePerIncrementalContributionPoint,
        );

        expect(result.ranked.first.nodeId, 'already-connected');
        expect(result.ranked.first.contributionPointsUsedForRanking, 0);
        expect(result.ranked.first.rankingScore, 20);
        expect(result.ranked.first.rankingScore!.isFinite, isTrue);
        expect(
          result.ranked.first.caveats,
          contains(MarketValueCaveat.zeroIncrementalContributionPoints),
        );
      },
    );

    test('requires the selected CP measure and rejects invalid values', () {
      final minimum = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'missing',
            outputs: <MarketValueOutputInput>[
              _output(id: 'a', name: 'A', price: 1),
            ],
          ),
          _node(
            id: 'zero',
            minimumCp: 0,
            outputs: <MarketValueOutputInput>[
              _output(id: 'b', name: 'B', price: 1),
            ],
          ),
        ],
        marketNetRate: 1,
        basis: MarketValueRankingBasis
            .netUnitBasketValuePerMinimumContributionPoint,
      );

      expect(minimum.ranked, isEmpty);
      expect(
        _excludedReason(minimum, 'missing'),
        MarketValueCandidateExclusionReason
            .minimumContributionPointsUnavailable,
      );
      expect(
        _excludedReason(minimum, 'zero'),
        MarketValueCandidateExclusionReason.invalidContributionPoints,
      );

      final incremental = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'missing',
            outputs: <MarketValueOutputInput>[
              _output(id: 'a', name: 'A', price: 1),
            ],
          ),
          _node(
            id: 'negative',
            incrementalCp: -1,
            outputs: <MarketValueOutputInput>[
              _output(id: 'b', name: 'B', price: 1),
            ],
          ),
        ],
        marketNetRate: 1,
        basis: MarketValueRankingBasis
            .netUnitBasketValuePerIncrementalContributionPoint,
      );

      expect(
        _excludedReason(incremental, 'missing'),
        MarketValueCandidateExclusionReason
            .incrementalContributionPointsUnavailable,
      );
      expect(
        _excludedReason(incremental, 'negative'),
        MarketValueCandidateExclusionReason.invalidContributionPoints,
      );
    });
  });

  group('listed-stock competition signal', () {
    final candidates = <MarketValueNodeInput>[
      _node(
        id: 'high-stock',
        name: 'High Stock',
        outputs: <MarketValueOutputInput>[
          _output(id: 'high', name: 'High', price: 1000, stock: 1000),
        ],
      ),
      _node(
        id: 'low-stock',
        name: 'Low Stock',
        outputs: <MarketValueOutputInput>[
          _output(id: 'low', name: 'Low', price: 900, stock: 0),
        ],
      ),
      _node(
        id: 'unknown-stock',
        name: 'Unknown Stock',
        outputs: <MarketValueOutputInput>[
          _output(id: 'unknown', name: 'Unknown', price: 950),
        ],
      ),
    ];

    test('does not let stock affect ranking when the policy is disabled', () {
      final result = _evaluate(candidates: candidates, marketNetRate: 1);

      expect(result.ranked.first.nodeId, 'high-stock');
      expect(
        result.globalCaveats,
        isNot(contains(MarketValueCaveat.listedStockIsNotLiquidity)),
      );
      expect(result.ranked.first.outputs.single.listedStockFactor, 1);
    });

    test('applies an explicit high-stock and unknown-stock penalty', () {
      final result = _evaluate(
        candidates: candidates,
        marketNetRate: 1,
        stockPolicy: const ListedStockCompetitionPolicy.penalize(
          referenceListedStock: 1000,
          minimumKnownStockFactor: .25,
          unknownStockFactor: .5,
        ),
      );

      expect(result.ranked.map((item) => item.nodeId), <String>[
        'low-stock',
        'unknown-stock',
        'high-stock',
      ]);
      expect(
        result.ranked
            .singleWhere((item) => item.nodeId == 'high-stock')
            .stockAdjustedNetValueSignal,
        250,
      );
      final unknown = result.ranked.singleWhere(
        (item) => item.nodeId == 'unknown-stock',
      );
      expect(unknown.stockAdjustedNetValueSignal, 475);
      expect(unknown.confidence, MarketValueDataConfidence.medium);
      expect(
        unknown.caveats,
        containsAll(<MarketValueCaveat>{
          MarketValueCaveat.unknownListedStock,
          MarketValueCaveat.unknownListedStockPenaltyApplied,
        }),
      );
      expect(
        result.globalCaveats,
        containsAll(<MarketValueCaveat>{
          MarketValueCaveat.listedStockIsNotLiquidity,
          MarketValueCaveat.listedStockCompetitionHeuristicApplied,
        }),
      );
    });

    test(
      'treats negative listed stock as unknown rather than as sales data',
      () {
        final result = _evaluate(
          candidates: <MarketValueNodeInput>[
            _node(
              id: 'invalid-stock',
              outputs: <MarketValueOutputInput>[
                _output(id: 'a', name: 'A', price: 100, stock: -5),
              ],
            ),
          ],
          marketNetRate: 1,
          stockPolicy: const ListedStockCompetitionPolicy.penalize(
            referenceListedStock: 100,
            unknownStockFactor: .4,
          ),
        );

        final recommendation = result.ranked.single;
        expect(recommendation.outputs.single.listedStock, isNull);
        expect(recommendation.stockAdjustedNetValueSignal, 40);
        expect(recommendation.confidence, MarketValueDataConfidence.medium);
        expect(
          recommendation.caveats,
          contains(MarketValueCaveat.invalidListedStockTreatedAsUnknown),
        );
      },
    );
  });

  group('missing and excluded market data', () {
    test('excludes incomplete market baskets by default', () {
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'partial',
            outputs: <MarketValueOutputInput>[
              _output(id: 'known', name: 'Known', price: 100),
              _output(id: 'unknown', name: 'Unknown'),
            ],
          ),
        ],
        marketNetRate: 1,
      );

      expect(result.ranked, isEmpty);
      expect(
        result.excluded.single.exclusionReason,
        MarketValueCandidateExclusionReason.incompleteMarketPrices,
      );
      expect(
        result.excluded.single.caveats,
        contains(MarketValueCaveat.unavailablePrices),
      );
    });

    test('can rank known-only partial baskets with low confidence', () {
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'partial',
            outputs: <MarketValueOutputInput>[
              _output(id: 'known', name: 'Known', price: 100),
              _output(id: 'unknown', name: 'Unknown'),
            ],
          ),
        ],
        marketNetRate: 1,
        allowPartialPriceData: true,
      );

      final recommendation = result.ranked.single;
      expect(recommendation.netUnitBasketValue, 100);
      expect(recommendation.confidence, MarketValueDataConfidence.low);
      expect(
        recommendation.caveats,
        containsAll(<MarketValueCaveat>{
          MarketValueCaveat.unavailablePrices,
          MarketValueCaveat.partialPriceDataUsed,
        }),
      );
    });

    test('distinguishes no marketable outputs from no usable prices', () {
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'bound-only',
            outputs: <MarketValueOutputInput>[
              _output(
                id: 'bound',
                name: 'Bound Output',
                price: 999,
                marketable: false,
              ),
            ],
          ),
          _node(
            id: 'unpriced',
            outputs: <MarketValueOutputInput>[
              _output(id: 'missing', name: 'Missing'),
              _output(id: 'zero', name: 'Zero', price: 0),
            ],
          ),
        ],
        marketNetRate: 1,
      );

      expect(
        _excludedReason(result, 'bound-only'),
        MarketValueCandidateExclusionReason.noMarketableOutputs,
      );
      expect(
        _excludedReason(result, 'unpriced'),
        MarketValueCandidateExclusionReason.noUsableMarketPrices,
      );
    });

    test('rejects missing candidate data and an invalid net rate', () {
      final missing = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(id: '', name: '', outputs: const <MarketValueOutputInput>[]),
          _node(id: 'empty', outputs: const <MarketValueOutputInput>[]),
        ],
        marketNetRate: 1,
      );
      expect(
        missing.excluded.map((item) => item.exclusionReason),
        containsAll(<MarketValueCandidateExclusionReason>{
          MarketValueCandidateExclusionReason.missingNodeIdentity,
          MarketValueCandidateExclusionReason.noOutputs,
        }),
      );

      final invalidRate = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'a',
            outputs: <MarketValueOutputInput>[
              _output(id: 'a', name: 'A', price: 100),
            ],
          ),
        ],
        marketNetRate: 1.01,
      );
      expect(invalidRate.ranked, isEmpty);
      expect(
        invalidRate.excluded.single.exclusionReason,
        MarketValueCandidateExclusionReason.invalidMarketNetRate,
      );
    });

    test('rejects non-finite aggregate calculations', () {
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[
          _node(
            id: 'overflow',
            outputs: <MarketValueOutputInput>[
              _output(id: 'a', name: 'A', price: double.maxFinite),
              _output(id: 'b', name: 'B', price: double.maxFinite),
            ],
          ),
        ],
        marketNetRate: 1,
      );

      expect(
        result.excluded.single.exclusionReason,
        MarketValueCandidateExclusionReason.nonFiniteCalculatedValue,
      );
    });
  });

  group('determinism and immutable integration data', () {
    test('uses stable identity tie-breaks independent of input order', () {
      final candidates = <MarketValueNodeInput>[
        _node(
          id: '2',
          name: 'Beta',
          outputs: <MarketValueOutputInput>[
            _output(id: 'b', name: 'B', price: 100),
          ],
        ),
        _node(
          id: '9',
          name: 'Alpha',
          outputs: <MarketValueOutputInput>[
            _output(id: 'a', name: 'A', price: 100),
          ],
        ),
        _node(
          id: '1',
          name: 'Alpha',
          outputs: <MarketValueOutputInput>[
            _output(id: 'a-2', name: 'A2', price: 100),
          ],
        ),
      ];

      final forward = _evaluate(candidates: candidates, marketNetRate: 1);
      final reverse = _evaluate(
        candidates: candidates.reversed,
        marketNetRate: 1,
      );

      expect(forward.ranked.map((item) => item.nodeId), <String>[
        '1',
        '9',
        '2',
      ]);
      expect(reverse.ranked.map((item) => item.nodeId), <String>[
        '1',
        '9',
        '2',
      ]);
      expect(forward.ranked.map((item) => item.rank), <int>[1, 2, 3]);
    });

    test('deduplicates outputs deterministically before summing values', () {
      final first = _node(
        id: 'duplicate-test',
        outputs: <MarketValueOutputInput>[
          _output(id: 'same', name: 'Zulu', price: 900),
          _output(id: 'same', name: 'Alpha', price: 100),
        ],
      );
      final reversed = _node(
        id: 'duplicate-test',
        outputs: first.outputs.reversed,
      );

      for (final candidate in <MarketValueNodeInput>[first, reversed]) {
        final result = _evaluate(
          candidates: <MarketValueNodeInput>[candidate],
          marketNetRate: 1,
        );
        final recommendation = result.ranked.single;
        expect(recommendation.netUnitBasketValue, 100);
        expect(
          recommendation.caveats,
          contains(MarketValueCaveat.duplicateOutputsIgnored),
        );
        expect(
          recommendation.outputs
              .singleWhere((output) => output.outputName == 'Zulu')
              .exclusionReason,
          MarketValueOutputExclusionReason.duplicateOutput,
        );
      }
    });

    test('normalizes path metadata without deriving or changing CP', () {
      final candidate = _node(
        id: 'path',
        minimumCp: 7,
        path: const <String>[' town ', 'bridge', 'TOWN', '', 'node'],
        incrementalPath: const <String>['bridge', 'node', ' bridge '],
        outputs: <MarketValueOutputInput>[
          _output(id: 'a', name: 'A', price: 70),
        ],
      );
      final result = _evaluate(
        candidates: <MarketValueNodeInput>[candidate],
        marketNetRate: 1,
        basis: MarketValueRankingBasis
            .netUnitBasketValuePerMinimumContributionPoint,
      );

      final recommendation = result.ranked.single;
      expect(recommendation.pathNodeIds, <String>['town', 'bridge', 'node']);
      expect(recommendation.incrementalPathNodeIds, <String>['bridge', 'node']);
      expect(recommendation.rankingScore, 10);
      expect(
        recommendation.caveats,
        contains(MarketValueCaveat.pathMetadataIsInformational),
      );
      expect(
        () => recommendation.pathNodeIds.add('mutate'),
        throwsUnsupportedError,
      );
      expect(
        () => recommendation.outputs.add(recommendation.outputs.first),
        throwsUnsupportedError,
      );
      expect(
        () => result.globalCaveats.add(MarketValueCaveat.partialPriceDataUsed),
        throwsUnsupportedError,
      );
    });
  });
}

MarketValueRecommendationResult _evaluate({
  required Iterable<MarketValueNodeInput> candidates,
  required double marketNetRate,
  MarketValueRankingBasis basis = MarketValueRankingBasis.netUnitBasketValue,
  ListedStockCompetitionPolicy stockPolicy =
      const ListedStockCompetitionPolicy.ignore(),
  bool allowPartialPriceData = false,
}) {
  return const MarketValueRecommendationService().evaluate(
    MarketValueRecommendationRequest(
      candidates: candidates,
      marketNetRate: marketNetRate,
      rankingBasis: basis,
      stockPolicy: stockPolicy,
      allowPartialPriceData: allowPartialPriceData,
    ),
  );
}

MarketValueNodeInput _node({
  required String id,
  String? name,
  required Iterable<MarketValueOutputInput> outputs,
  int? minimumCp,
  int? incrementalCp,
  Iterable<String> path = const <String>[],
  Iterable<String> incrementalPath = const <String>[],
}) {
  return MarketValueNodeInput(
    nodeId: id,
    nodeName: name ?? id,
    outputs: outputs,
    minimumContributionPoints: minimumCp,
    incrementalContributionPoints: incrementalCp,
    pathNodeIds: path,
    incrementalPathNodeIds: incrementalPath,
  );
}

MarketValueOutputInput _output({
  required String id,
  required String name,
  double? price,
  int? stock,
  bool marketable = true,
}) {
  return MarketValueOutputInput(
    outputId: id,
    outputName: name,
    isMarketable: marketable,
    currentUnitPrice: price,
    listedStock: stock,
  );
}

MarketValueCandidateExclusionReason _excludedReason(
  MarketValueRecommendationResult result,
  String nodeId,
) => result.excluded
    .singleWhere((evaluation) => evaluation.nodeId == nodeId)
    .exclusionReason!;
