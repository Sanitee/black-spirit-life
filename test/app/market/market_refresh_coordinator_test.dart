import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/market/market_refresh_coordinator.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fetchedAt = DateTime.utc(2026, 7, 20, 11, 30);

  test(
    'uses exact recipe, alias, then normalized catalog ID precedence',
    () async {
      final recipes = <String, Recipe>{
        'Exact': _recipe('Exact', marketId: '000100'),
        'Alias': _recipe('Alias'),
        'Normalized   Item': _recipe('Normalized   Item'),
      };
      final gateway = _FakeGateway((requests, _) async {
        expect(requests.map((request) => request.id), <String>[
          '100',
          '300',
          '400',
        ]);
        return _fetchResult(
          fetchedAt: fetchedAt,
          rows: [
            _success(requests[0], price: 101, stock: 1, fetchedAt: fetchedAt),
            _success(requests[1], price: 301, stock: 3, fetchedAt: fetchedAt),
            _success(requests[2], price: 401, stock: 4, fetchedAt: fetchedAt),
          ],
        );
      });
      final coordinator = MarketRefreshCoordinator(
        gateway: gateway,
        catalogRepository: _repository(
          recipes: recipes,
          supportingData: <String, Object?>{
            'marketIds': <String, Object?>{'Exact': 200, 'Canonical': 300},
            'marketNameAliases': <String, Object?>{'Alias': 'Canonical'},
            'marketNameIds': <String, Object?>{'normalized item': 400},
          },
        ),
      );

      final result = await coordinator.refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: _market(),
        missingMaterialNames: const ['Exact', 'Alias', 'Normalized   Item'],
      );

      expect(result.status, MarketRefreshStatus.updated);
      expect(result.prices, containsPair('Exact', 101));
      expect(result.prices, containsPair('Alias', 301));
      expect(result.prices, containsPair('Normalized   Item', 401));
      expect(result.fetchedAt, fetchedAt.millisecondsSinceEpoch);
      expect(result.market.region, 'na');
      expect(result.summary.successfulRequestCount, 3);
    },
  );

  test('first cumulative-trade snapshot is not presented as demand', () async {
    final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _success(
            requests.single,
            price: 900,
            stock: 12,
            fetchedAt: fetchedAt,
            totalTrades: 1000,
            lastSoldAtEpochSeconds: 1785346251,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: _market(),
      missingMaterialNames: const <String>['A'],
    );

    expect(result.tradeMarketIds, const <String, String>{'A': '1'});
    expect(result.totalTrades, const <String, int>{'A': 1000});
    expect(result.tradeObservedAt, <String, int>{
      'A': fetchedAt.millisecondsSinceEpoch,
    });
    expect(result.observedDailyTrades, isEmpty);
    expect(result.tradeObservationHours, isEmpty);
    expect(result.lastSoldAtEpochSeconds, const <String, int>{'A': 1785346251});
  });

  test('successive counters produce an elapsed-time demand rate', () async {
    final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
    final baselineAt = fetchedAt.subtract(const Duration(hours: 6));
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _success(
            requests.single,
            price: 900,
            stock: 12,
            fetchedAt: fetchedAt,
            totalTrades: 1120,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: _market(
        tradeMarketIds: const <String, String>{'A': '1'},
        totalTrades: const <String, int>{'A': 1000},
        tradeObservedAt: <String, int>{'A': baselineAt.millisecondsSinceEpoch},
      ),
      missingMaterialNames: const <String>['A'],
    );

    expect(result.totalTrades['A'], 1120);
    expect(result.observedDailyTrades['A'], closeTo(480, 0.000001));
    expect(result.tradeObservationHours['A'], 6);
  });

  test('an unchanged later counter records measured zero demand', () async {
    final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
    final baselineAt = fetchedAt.subtract(const Duration(hours: 6));
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _success(
            requests.single,
            price: 900,
            stock: 12,
            fetchedAt: fetchedAt,
            totalTrades: 1000,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: _market(
        tradeMarketIds: const <String, String>{'A': '1'},
        totalTrades: const <String, int>{'A': 1000},
        tradeObservedAt: <String, int>{'A': baselineAt.millisecondsSinceEpoch},
      ),
      missingMaterialNames: const <String>['A'],
    );

    expect(result.observedDailyTrades, const <String, double>{'A': 0});
    expect(result.tradeObservationHours, const <String, double>{'A': 6});
  });

  test('a lower cumulative counter resets the demand baseline', () async {
    final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
    final baselineAt = fetchedAt.subtract(const Duration(hours: 12));
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _success(
            requests.single,
            price: 900,
            stock: 12,
            fetchedAt: fetchedAt,
            totalTrades: 20,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: _market(
        tradeMarketIds: const <String, String>{'A': '1'},
        totalTrades: const <String, int>{'A': 500},
        tradeObservedAt: <String, int>{'A': baselineAt.millisecondsSinceEpoch},
        observedDailyTrades: const <String, double>{'A': 300},
        tradeObservationHours: const <String, double>{'A': 12},
      ),
      missingMaterialNames: const <String>['A'],
    );

    expect(result.totalTrades, const <String, int>{'A': 20});
    expect(result.tradeObservedAt['A'], fetchedAt.millisecondsSinceEpoch);
    expect(result.observedDailyTrades, isEmpty);
    expect(result.tradeObservationHours, isEmpty);
  });

  test('a changed market ID cannot reuse an old item counter', () async {
    final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _success(
            requests.single,
            price: 900,
            stock: 12,
            fetchedAt: fetchedAt,
            totalTrades: 5000,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: _market(
        tradeMarketIds: const <String, String>{'A': '99'},
        totalTrades: const <String, int>{'A': 100},
        tradeObservedAt: <String, int>{
          'A': fetchedAt
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
        observedDailyTrades: const <String, double>{'A': 24},
        tradeObservationHours: const <String, double>{'A': 1},
      ),
      missingMaterialNames: const <String>['A'],
    );

    expect(result.tradeMarketIds, const <String, String>{'A': '1'});
    expect(result.totalTrades, const <String, int>{'A': 5000});
    expect(result.observedDailyTrades, isEmpty);
    expect(result.tradeObservationHours, isEmpty);
  });

  test('a source without a trade counter preserves measured demand', () async {
    final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
    final previous = _market(
      tradeMarketIds: const <String, String>{'A': '1'},
      totalTrades: const <String, int>{'A': 100},
      tradeObservedAt: const <String, int>{'A': 1000},
      observedDailyTrades: const <String, double>{'A': 24},
      tradeObservationHours: const <String, double>{'A': 8},
      lastSoldAtEpochSeconds: const <String, int>{'A': 900},
    );
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _success(
            requests.single,
            price: 901,
            stock: null,
            fetchedAt: fetchedAt,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: previous,
      missingMaterialNames: const <String>['A'],
    );

    expect(result.tradeMarketIds, previous.tradeMarketIds);
    expect(result.totalTrades, previous.totalTrades);
    expect(result.tradeObservedAt, previous.tradeObservedAt);
    expect(result.observedDailyTrades, previous.observedDailyTrades);
    expect(result.tradeObservationHours, previous.tradeObservationHours);
    expect(result.lastSoldAtEpochSeconds, previous.lastSoldAtEpochSeconds);
  });

  test(
    'partial refresh merges successes and preserves every failed field',
    () async {
      final recipes = <String, Recipe>{
        'A': _recipe('A', marketId: '1'),
        'B': _recipe('B', marketId: '2'),
      };
      final gateway = _FakeGateway((requests, _) async {
        return _fetchResult(
          fetchedAt: fetchedAt,
          rows: [
            _success(
              requests[0],
              price: 900,
              stock: null,
              fetchedAt: fetchedAt,
            ),
            _failure(
              requests[1],
              MarketDiagnosticCode.timeout,
              fetchedAt: fetchedAt,
            ),
          ],
        );
      });
      final previous = _market(
        prices: const {'A': 10, 'B': 20, 'Unrequested': 30},
        stock: const {'A': 7, 'B': 8, 'Unrequested': 9},
        fetchedAt: 1234,
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: previous,
        missingMaterialNames: const ['A', 'B'],
      );

      expect(result.status, MarketRefreshStatus.partiallyUpdated);
      expect(result.prices, const {'A': 900, 'B': 20, 'Unrequested': 30});
      expect(result.stock, const {'A': 7, 'B': 8, 'Unrequested': 9});
      expect(result.summary.successfulRequestCount, 1);
      expect(result.summary.failedRequestCount, 1);
      expect(result.summary.unknownStockCount, 1);
      expect(result.fetchedAt, fetchedAt.millisecondsSinceEpoch);
      expect(previous.prices['A'], 10);
      expect(previous.stock['A'], 7);
    },
  );

  test(
    'total row failure keeps the complete stale cache and timestamp',
    () async {
      final recipes = <String, Recipe>{
        'A': _recipe('A', marketId: '1'),
        'B': _recipe('B', marketId: '2'),
      };
      final gateway = _FakeGateway(
        (requests, _) async => _fetchResult(
          fetchedAt: fetchedAt,
          rows: [
            for (final request in requests)
              _failure(
                request,
                MarketDiagnosticCode.network,
                fetchedAt: fetchedAt,
              ),
          ],
        ),
      );
      final previous = _market(
        prices: const {'A': 11, 'B': 22},
        stock: const {'A': 3, 'B': 4},
        fetchedAt: 777,
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: previous,
        missingMaterialNames: const ['A', 'B'],
      );

      expect(result.status, MarketRefreshStatus.failed);
      expect(result.prices, previous.prices);
      expect(result.stock, previous.stock);
      expect(result.fetchedAt, 777);
      expect(result.market.region, previous.region);
      expect(result.summary.failedRequestCount, 2);
    },
  );

  test(
    'unlisted rows do not count as failures and clear stale market pills',
    () async {
      final recipes = <String, Recipe>{
        'Listed': _recipe('Listed', marketId: '1'),
        'Unlisted': _recipe('Unlisted', marketId: '2'),
      };
      final gateway = _FakeGateway(
        (requests, _) async => _fetchResult(
          fetchedAt: fetchedAt,
          rows: <MarketPriceRow>[
            _success(requests[0], price: 900, stock: 12, fetchedAt: fetchedAt),
            _failure(
              requests[1],
              MarketDiagnosticCode.itemMissing,
              fetchedAt: fetchedAt,
            ),
          ],
        ),
      );
      final previous = _market(
        prices: const <String, double>{
          'Listed': 10,
          'Unlisted': 20,
          'Unrequested': 30,
        },
        stock: const <String, double>{
          'Listed': 1,
          'Unlisted': 2,
          'Unrequested': 3,
        },
        tradeMarketIds: const <String, String>{
          'Unlisted': '2',
          'Unrequested': '3',
        },
        totalTrades: const <String, int>{'Unlisted': 200, 'Unrequested': 300},
        tradeObservedAt: const <String, int>{
          'Unlisted': 2000,
          'Unrequested': 3000,
        },
        observedDailyTrades: const <String, double>{
          'Unlisted': 20,
          'Unrequested': 30,
        },
        tradeObservationHours: const <String, double>{
          'Unlisted': 2,
          'Unrequested': 3,
        },
        lastSoldAtEpochSeconds: const <String, int>{
          'Unlisted': 200,
          'Unrequested': 300,
        },
        fetchedAt: 777,
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.processing,
        assembledRecipes: recipes,
        currentMarket: previous,
        missingMaterialNames: const <String>['Listed', 'Unlisted'],
      );

      expect(result.status, MarketRefreshStatus.updated);
      expect(result.summary.successfulRequestCount, 1);
      expect(result.summary.unlistedRequestCount, 1);
      expect(result.summary.failedRequestCount, 0);
      expect(result.prices, const <String, double>{
        'Listed': 900,
        'Unrequested': 30,
      });
      expect(result.stock, const <String, double>{
        'Listed': 12,
        'Unrequested': 3,
      });
      expect(result.tradeMarketIds, const <String, String>{'Unrequested': '3'});
      expect(result.totalTrades, const <String, int>{'Unrequested': 300});
      expect(result.tradeObservedAt, const <String, int>{'Unrequested': 3000});
      expect(result.observedDailyTrades, const <String, double>{
        'Unrequested': 30,
      });
      expect(result.tradeObservationHours, const <String, double>{
        'Unrequested': 3,
      });
      expect(result.lastSoldAtEpochSeconds, const <String, int>{
        'Unrequested': 300,
      });
      expect(
        result.diagnostics.last.code,
        MarketRefreshDiagnosticCode.marketUnlisted,
      );
      expect(
        result.diagnostics.last.gatewayCode,
        MarketDiagnosticCode.itemMissing,
      );
      expect(
        result.diagnostics.last.message,
        "Can't be registered on the Central Market.",
      );
      expect(result.market.unlistedItemNames, const <String>{'unlisted'});
    },
  );

  test(
    'transient failures preserve confirmed-unlisted classification',
    () async {
      final recipes = <String, Recipe>{
        'Unlisted': _recipe('Unlisted', marketId: '2'),
      };
      final gateway = _FakeGateway(
        (requests, _) async => _fetchResult(
          fetchedAt: fetchedAt,
          rows: <MarketPriceRow>[
            _failure(
              requests.single,
              MarketDiagnosticCode.timeout,
              fetchedAt: fetchedAt,
            ),
          ],
        ),
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.processing,
        assembledRecipes: recipes,
        currentMarket: _market(
          unlistedItemNames: const <String>{'Unlisted'},
          fetchedAt: 777,
        ),
        missingMaterialNames: const <String>['Unlisted'],
      );

      expect(result.status, MarketRefreshStatus.failed);
      expect(result.market.unlistedItemNames, const <String>{'unlisted'});
      expect(
        result.diagnostics.last.code,
        MarketRefreshDiagnosticCode.rowFailure,
      );
    },
  );

  test(
    'a successful listed result clears prior unlisted classification',
    () async {
      final recipes = <String, Recipe>{
        'Recovered': _recipe('Recovered', marketId: '3'),
      };
      final gateway = _FakeGateway(
        (requests, _) async => _fetchResult(
          fetchedAt: fetchedAt,
          rows: <MarketPriceRow>[
            _success(
              requests.single,
              price: 1200,
              stock: 4,
              fetchedAt: fetchedAt,
            ),
          ],
        ),
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.processing,
        assembledRecipes: recipes,
        currentMarket: _market(
          unlistedItemNames: const <String>{'RECOVERED', 'Other'},
        ),
        missingMaterialNames: const <String>['Recovered'],
      );

      expect(result.status, MarketRefreshStatus.updated);
      expect(result.market.unlistedItemNames, const <String>{'other'});
      expect(result.prices['Recovered'], 1200);
      expect(result.stock['Recovered'], 4);
    },
  );

  test(
    'an all-unlisted refresh is successful without a failure warning',
    () async {
      final recipes = <String, Recipe>{
        'Missing': _recipe('Missing', marketId: '1'),
        'Zero Price': _recipe('Zero Price', marketId: '2'),
      };
      final gateway = _FakeGateway(
        (requests, _) async => _fetchResult(
          fetchedAt: fetchedAt,
          rows: <MarketPriceRow>[
            _failure(
              requests[0],
              MarketDiagnosticCode.itemMissing,
              fetchedAt: fetchedAt,
            ),
            _failure(
              requests[1],
              MarketDiagnosticCode.unusablePrice,
              fetchedAt: fetchedAt,
            ),
          ],
        ),
      );
      final previous = _market(
        prices: const <String, double>{
          'Missing': 10,
          'Zero Price': 20,
          'Unrequested': 30,
        },
        stock: const <String, double>{
          'Missing': 1,
          'Zero Price': 2,
          'Unrequested': 3,
        },
        fetchedAt: 777,
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.processing,
        assembledRecipes: recipes,
        currentMarket: previous,
        missingMaterialNames: const <String>['Missing', 'Zero Price'],
      );

      expect(result.status, MarketRefreshStatus.noMarketListings);
      expect(result.summary.successfulRequestCount, 0);
      expect(result.summary.unlistedRequestCount, 2);
      expect(result.summary.failedRequestCount, 0);
      expect(
        result.summary.message,
        'None of the requested materials are registered on the Central Market.',
      );
      expect(result.prices, const <String, double>{'Unrequested': 30});
      expect(result.stock, const <String, double>{'Unrequested': 3});
      expect(result.fetchedAt, fetchedAt.millisecondsSinceEpoch);
    },
  );

  test(
    'unresolved and malformed IDs are skipped with actionable diagnostics',
    () async {
      final recipes = <String, Recipe>{
        'Missing': _recipe('Missing'),
        'Malformed': _recipe('Malformed', marketId: 'not-a-number'),
      };
      final gateway = _FakeGateway((_, _) async {
        fail('The gateway must not run when no ID can be resolved.');
      });

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: _market(prices: const {'Old': 5}, fetchedAt: 44),
        missingMaterialNames: const ['Missing', 'Malformed', '   '],
      );

      expect(result.status, MarketRefreshStatus.noResolvableItems);
      expect(gateway.calls, isEmpty);
      expect(result.summary.unresolvedMaterialCount, 3);
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        containsAll(<MarketRefreshDiagnosticCode>[
          MarketRefreshDiagnosticCode.unresolvedMarketId,
          MarketRefreshDiagnosticCode.invalidMarketId,
          MarketRefreshDiagnosticCode.emptyMaterialName,
        ]),
      );
      expect(
        result.diagnostics.every((item) => item.message.isNotEmpty),
        isTrue,
      );
      expect(result.prices, const {'Old': 5});
      expect(result.fetchedAt, 44);
    },
  );

  test(
    'deduplicates exact names and IDs without folding case collisions',
    () async {
      final recipes = <String, Recipe>{
        'Herb': _recipe('Herb', marketId: '1'),
        'herb': _recipe('herb', marketId: '2'),
        'Alias Herb': _recipe('Alias Herb', marketId: '1'),
      };
      final gateway = _FakeGateway((requests, _) async {
        expect(requests, hasLength(2));
        expect(requests[0].name, 'Herb');
        expect(requests[0].id, '1');
        expect(requests[1].name, 'herb');
        expect(requests[1].id, '2');
        return _fetchResult(
          fetchedAt: fetchedAt,
          rows: [
            _success(requests[0], price: 111, stock: 10, fetchedAt: fetchedAt),
            _success(requests[1], price: 222, stock: 20, fetchedAt: fetchedAt),
          ],
        );
      });

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: _market(),
        missingMaterialNames: const ['Herb', 'Herb', 'herb', 'Alias Herb'],
      );

      expect(result.status, MarketRefreshStatus.updated);
      expect(result.summary.duplicateNameCount, 1);
      expect(result.summary.duplicateIdCount, 1);
      expect(result.summary.uniqueNameCount, 3);
      expect(result.summary.requestCount, 2);
      expect(result.summary.resolvedMaterialCount, 3);
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains(MarketRefreshDiagnosticCode.duplicateMaterialName),
      );
      expect(result.prices['Herb'], 111);
      expect(result.prices['Alias Herb'], 111);
      expect(result.prices['herb'], 222);
      expect(result.stock['Herb'], 10);
      expect(result.stock['Alias Herb'], 10);
      expect(result.stock['herb'], 20);
    },
  );

  test(
    'gateway exception is typed as failure and preserves stale cache',
    () async {
      final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
      final gateway = _FakeGateway((_, _) async {
        throw StateError('deterministic fixture failure');
      });
      final previous = _market(
        prices: const {'A': 81},
        stock: const {'A': 9},
        fetchedAt: 8181,
      );

      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: previous,
        missingMaterialNames: const ['A'],
      );

      expect(result.status, MarketRefreshStatus.failed);
      expect(result.market.toJson(), previous.toJson());
      expect(
        result.diagnostics.last.code,
        MarketRefreshDiagnosticCode.gatewayFailure,
      );
    },
  );

  test('shared-ID failures retain every affected material name', () async {
    final recipes = <String, Recipe>{
      'A': _recipe('A', marketId: '1'),
      'B': _recipe('B', marketId: '1'),
    };
    final gateway = _FakeGateway(
      (requests, _) async => _fetchResult(
        fetchedAt: fetchedAt,
        rows: <MarketPriceRow>[
          _failure(
            requests.single,
            MarketDiagnosticCode.timeout,
            fetchedAt: fetchedAt,
          ),
        ],
      ),
    );

    final result = await _coordinator(gateway, recipes).refresh(
      mode: CraftMode.alchemy,
      assembledRecipes: recipes,
      currentMarket: _market(),
      missingMaterialNames: const <String>['A', 'B'],
    );

    final failure = result.diagnostics.singleWhere(
      (item) => item.code == MarketRefreshDiagnosticCode.rowFailure,
    );
    expect(failure.relatedMaterialNames, <String>['A', 'B']);
  });

  test(
    'cancellation returns a typed result without changing stale cache',
    () async {
      final started = Completer<void>();
      final recipes = <String, Recipe>{'A': _recipe('A', marketId: '1')};
      final gateway = _FakeGateway((_, token) async {
        started.complete();
        await token!.whenCancelled;
        throw const MarketFetchCancelledException();
      });
      final cancellation = MarketCancellationController();
      final previous = _market(
        prices: const {'A': 19, 'Old': 4},
        stock: const {'A': 2, 'Old': 1},
        fetchedAt: 9191,
      );

      final future = _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: previous,
        missingMaterialNames: const ['A'],
        cancellationToken: cancellation.token,
      );
      await started.future;
      cancellation.cancel();
      final result = await future;

      expect(result.status, MarketRefreshStatus.cancelled);
      expect(result.market.toJson(), previous.toJson());
      expect(
        result.diagnostics.last.code,
        MarketRefreshDiagnosticCode.cancelled,
      );
    },
  );
}

MarketRefreshCoordinator _coordinator(
  MarketPriceGateway gateway,
  Map<String, Recipe> recipes,
) => MarketRefreshCoordinator(
  gateway: gateway,
  catalogRepository: _repository(recipes: recipes),
);

CatalogRepository _repository({
  required Map<String, Recipe> recipes,
  Map<String, Object?> supportingData = const {},
}) => CatalogRepository(
  CatalogSnapshot(
    sourceSha256: 'fixture',
    sourceByteCount: 1,
    alchemy: _modeCatalog(CraftMode.alchemy, recipes),
    cooking: _modeCatalog(CraftMode.cooking, const {}),
    processing: _modeCatalog(CraftMode.processing, const {}),
    supportingData: supportingData,
    collisions: const [],
  ),
);

ModeCatalog _modeCatalog(CraftMode mode, Map<String, Recipe> recipes) =>
    ModeCatalog(
      mode: mode,
      items: recipes,
      iconDataUris: const {},
      defaults: const {},
      metadata: const {},
      searchAliases: const {},
    );

Recipe _recipe(String name, {String? marketId}) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const [],
  marketId: marketId,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

MarketState _market({
  Map<String, double> prices = const {},
  Map<String, double> stock = const {},
  Map<String, String> tradeMarketIds = const {},
  Map<String, int> totalTrades = const {},
  Map<String, int> tradeObservedAt = const {},
  Map<String, double> observedDailyTrades = const {},
  Map<String, double> tradeObservationHours = const {},
  Map<String, int> lastSoldAtEpochSeconds = const {},
  Iterable<String> unlistedItemNames = const <String>[],
  int fetchedAt = 0,
}) => MarketState(
  prices: prices,
  stock: stock,
  tradeMarketIds: tradeMarketIds,
  totalTrades: totalTrades,
  tradeObservedAt: tradeObservedAt,
  observedDailyTrades: observedDailyTrades,
  tradeObservationHours: tradeObservationHours,
  lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
  unlistedItemNames: unlistedItemNames,
  search: 'needle',
  sort: 'price',
  amount: 75,
  selected: 'A',
  fetchedAt: fetchedAt,
  region: 'eu',
  extensions: const {'retained': true},
);

MarketPriceFetchResult _fetchResult({
  required DateTime fetchedAt,
  required List<MarketPriceRow> rows,
}) => MarketPriceFetchResult(
  region: 'na',
  language: 'en',
  fetchedAt: fetchedAt,
  items: rows,
  attemptedSources: const [MarketPriceSource.arshaV2Batch],
);

MarketPriceRow _success(
  MarketPriceRequest request, {
  required int price,
  required int? stock,
  required DateTime fetchedAt,
  int? totalTrades,
  int? lastSoldAtEpochSeconds,
}) => MarketPriceRow(
  name: request.name,
  id: request.id,
  ok: true,
  price: price,
  stock: stock,
  source: MarketPriceSource.arshaV2Batch,
  fetchedAt: fetchedAt,
  diagnosticCode: MarketDiagnosticCode.none,
  totalTrades: totalTrades,
  lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
);

MarketPriceRow _failure(
  MarketPriceRequest request,
  MarketDiagnosticCode code, {
  required DateTime fetchedAt,
}) => MarketPriceRow(
  name: request.name,
  id: request.id,
  ok: false,
  price: 0,
  stock: null,
  source: MarketPriceSource.arshaV2Batch,
  fetchedAt: fetchedAt,
  diagnosticCode: code,
);

typedef _Handler =
    Future<MarketPriceFetchResult> Function(
      List<MarketPriceRequest> requests,
      MarketCancellationToken? cancellationToken,
    );

final class _FakeGateway implements MarketPriceGateway {
  _FakeGateway(this._handler);

  final _Handler _handler;
  final List<List<MarketPriceRequest>> calls = [];

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) {
    final recorded = List<MarketPriceRequest>.unmodifiable(requests);
    calls.add(recorded);
    return _handler(recorded, cancellationToken);
  }
}
