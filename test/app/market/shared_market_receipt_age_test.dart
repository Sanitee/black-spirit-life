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
  final fresh = DateTime.utc(2026, 9, 10, 12);
  final old = fresh.subtract(const Duration(hours: 1));
  final recipes = {
    'Wheat': _recipe('Wheat'),
    'Grain alias': _recipe('Grain alias'),
  };
  final repository = CatalogRepository(
    CatalogSnapshot(
      sourceSha256: 'fixture',
      sourceByteCount: 1,
      alchemy: _mode(CraftMode.alchemy, recipes),
      cooking: _mode(CraftMode.cooking, const {}),
      processing: _mode(CraftMode.processing, const {}),
      supportingData: const {},
      collisions: const [],
    ),
  );
  final coordinator = MarketRefreshCoordinator(
    gateway: _NoFetch(),
    catalogRepository: repository,
  );

  MarketRefreshResult merge(MarketState current, MarketPriceRow row) =>
      coordinator.mergeAvailable(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: current,
        names: current.prices.keys,
        fetched: MarketPriceFetchResult(
          region: 'eu',
          language: 'en',
          fetchedAt: row.fetchedAt,
          items: [row],
          attemptedSources: const [MarketPriceSource.pearlAbyssCentralMarket],
        ),
      )!;

  MarketState current({bool aliases = false, String id = '1'}) => MarketState(
    prices: {'Wheat': 999, if (aliases) 'Grain alias': 888},
    stock: {'Wheat': 77, if (aliases) 'Grain alias': 66},
    tradeMarketIds: {'Wheat': id, if (aliases) 'Grain alias': '1'},
    totalTrades: {'Wheat': 1000, if (aliases) 'Grain alias': 800},
    tradeObservedAt: {
      'Wheat': fresh.millisecondsSinceEpoch,
      if (aliases)
        'Grain alias': old
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
    },
    observedDailyTrades: const {'Wheat': 24},
    tradeObservationHours: const {'Wheat': 1},
    fetchedAt: fresh.millisecondsSinceEpoch,
  );

  test(
    'older shared quote cannot overwrite a newer same-item saved price or stock',
    () {
      final result = merge(current(), _row(old));
      expect(result.prices['Wheat'], 999);
      expect(result.stock['Wheat'], 77);
      expect(result.totalTrades['Wheat'], 1000);
      expect(result.tradeObservedAt['Wheat'], fresh.millisecondsSinceEpoch);
      expect(result.observedDailyTrades['Wheat'], 24);
      expect(result.summary.updatedMaterialCount, 0);
      expect(result.summary.failedRequestCount, 0);
      expect(result.fetchedAt, fresh.millisecondsSinceEpoch);
    },
  );

  test('an older unlisted receipt cannot clear newer verified values', () {
    final result = merge(current(), _row(old, unlisted: true));
    expect(result.prices['Wheat'], 999);
    expect(result.stock['Wheat'], 77);
    expect(result.market.unlistedItemNames, isEmpty);
    expect(result.summary.updatedMaterialCount, 0);
    expect(result.summary.failedRequestCount, 0);
  });

  test('each alias uses its own date, so an older alias can still update', () {
    final result = merge(current(aliases: true), _row(old));
    expect(result.prices, {'Wheat': 999, 'Grain alias': 100});
    expect(result.stock, {'Wheat': 77, 'Grain alias': 3});
    expect(result.totalTrades, {'Wheat': 1000, 'Grain alias': 900});
    expect(result.summary.updatedMaterialCount, 1);
  });

  test(
    'a remapped item never borrows the previous identity freshness barrier',
    () {
      final result = merge(current(id: '2'), _row(old));
      expect(result.prices['Wheat'], 100);
      expect(result.stock['Wheat'], 3);
      expect(result.tradeMarketIds['Wheat'], '1');
      expect(result.totalTrades['Wheat'], 900);
      expect(result.observedDailyTrades.containsKey('Wheat'), isFalse);
      expect(result.tradeObservedAt['Wheat'], old.millisecondsSinceEpoch);
    },
  );

  test(
    'equal timestamp remains idempotent and a newer unlisted receipt still clears',
    () {
      final same = merge(current(), _row(fresh));
      expect(same.prices['Wheat'], 100);
      expect(same.tradeObservedAt['Wheat'], fresh.millisecondsSinceEpoch);
      final unavailable = merge(
        current(),
        _row(fresh.add(const Duration(minutes: 1)), unlisted: true),
      );
      expect(unavailable.prices.containsKey('Wheat'), isFalse);
      expect(unavailable.stock.containsKey('Wheat'), isFalse);
      expect(unavailable.market.unlistedItemNames, contains('wheat'));
    },
  );

  test(
    'failed read is not converted into a successful receipt by the time guard',
    () {
      final result = merge(
        current(),
        MarketPriceRow(
          name: 'Wheat',
          id: '1',
          ok: false,
          price: 0,
          stock: null,
          source: MarketPriceSource.pearlAbyssCentralMarket,
          fetchedAt: old,
          diagnosticCode: MarketDiagnosticCode.network,
        ),
      );
      expect(result.summary.failedRequestCount, 1);
      expect(result.prices['Wheat'], 999);
    },
  );
}

MarketPriceRow _row(DateTime time, {bool unlisted = false}) => MarketPriceRow(
  name: 'Wheat',
  id: '1',
  ok: !unlisted,
  price: unlisted ? 0 : 100,
  stock: unlisted ? null : 3,
  source: MarketPriceSource.pearlAbyssCentralMarket,
  fetchedAt: time,
  diagnosticCode: unlisted
      ? MarketDiagnosticCode.itemMissing
      : MarketDiagnosticCode.none,
  totalTrades: unlisted ? null : 900,
);

Recipe _recipe(String name) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const [],
  marketId: '1',
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

ModeCatalog _mode(CraftMode mode, Map<String, Recipe> recipes) => ModeCatalog(
  mode: mode,
  items: recipes,
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

class _NoFetch implements MarketPriceGateway {
  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) => throw StateError('Receipt merge must not make a network request');
}
