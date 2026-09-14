import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/market/market_refresh_coordinator.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);
  final archivedIds = [
    '6211',
    '6011',
    '6007',
    '15202',
    '15208',
    '15209',
    '15210',
    '15215',
  ];
  late _Transport transport;
  late SharedMarketRepository repository;
  setUp(() {
    transport = _Transport();
    repository = SharedMarketRepository(
      transport: transport,
      utcNow: () => now,
    );
  });
  tearDown(() async => repository.close());

  test(
    'exact eight archived IDs never request quote or book in either region',
    () async {
      final keys = [
        for (final region in ['eu', 'na'])
          for (final id in archivedIds)
            SharedMarketKey(region: region, itemId: '00$id'),
      ];
      for (final force in [false, true]) {
        final progress = <(int, int)>[];
        final receipts = <SharedMarketReceipt>[];
        final result = await repository.fetch(
          quoteKeys: keys,
          bookKeys: keys,
          forceRefresh: force,
          onItem: receipts.add,
          onProgress: (done, total) => progress.add((done, total)),
        );
        expect(result.failures, hasLength(32));
        expect(result.failures.values.toSet(), {'Item temporarily archived'});
        expect(result.items, isEmpty);
        expect(result.rateLimited, isFalse);
        expect(receipts, isEmpty);
        expect(progress.last, (32, 32));
      }
      expect(transport.ids, isEmpty);
      expect(repository.snapshot('eu').items, isEmpty);
      expect(repository.diagnostics.startedRequests, 0);
    },
  );

  test('mixed requests still fetch normal and custom identities', () async {
    final result = await repository.fetch(
      quoteKeys: [_key('6211'), _key('7011'), _key('999999999')],
      bookKeys: [_key('6011'), _key('7011')],
    );
    expect(transport.ids.toSet(), {'7011', '999999999'});
    expect(result.quoteFailures, {_key('6211')});
    expect(result.bookFailures, {_key('6011')});
    expect(result.items[_key('7011')]!.basePrice, 100);
    expect(result.items[_key('7011')]!.preorderCount, 7);
  });

  test(
    'stored archived receipts survive but are not replayed as active data',
    () async {
      await repository.close();
      final directory = await Directory.systemTemp.createTemp(
        'archived-market-test-',
      );
      try {
        final store = OpportunityMarketCacheStore(
          directory: directory,
          utcNow: () => now,
        );
        final saved = OpportunityMarketItem(
          itemId: '6211',
          basePrice: 987,
          stock: 19,
          quoteFetchedAt: now,
          asks: const [OpportunityMarketLevel(price: 987, quantity: 19)],
          bids: const [],
          bookFetchedAt: now,
        );
        await store.save({
          'eu': {'6211': saved},
        });
        repository = SharedMarketRepository(
          cacheStore: store,
          transport: transport,
          utcNow: () => now,
        );
        final result = await repository.fetch(
          quoteKeys: [_key('6211')],
          bookKeys: [_key('6211')],
        );
        expect(result.items, isEmpty);
        expect(transport.ids, isEmpty);
        expect(repository.snapshot('eu').items['6211']!.basePrice, 987);
        expect(repository.snapshot('eu').items['6211']!.quoteFetchedAt, now);
        await repository.flush();
        expect((await store.load())['eu']!['6211']!.stock, 19);
        await repository.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'shared gateway marks intentional archive, not a network failure or deletion',
    () async {
      final result = await SharedMarketPriceGateway(repository: repository)
          .fetchProgressive(
            const [MarketPriceRequest(name: 'An alias', id: '06211')],
            region: 'eu',
            forceRefresh: true,
          );
      expect(
        result.items.single.diagnosticCode,
        MarketDiagnosticCode.temporarilyArchived,
      );
      expect(result.items.single.ok, isFalse);
      expect(result.items.single.stock, isNull);
      expect(result.items.single.fetchedAt.millisecondsSinceEpoch, 0);
      expect(result.attemptedSources, isEmpty);
      expect(transport.ids, isEmpty);
    },
  );

  test(
    'Planner skips archives without a request or clearing historical state',
    () async {
      final recipes = {
        for (final entry in temporarilyArchivedItemsById.entries)
          entry.value: _recipe(entry.value, entry.key),
      };
      final gateway = _Gateway(now);
      final current = MarketState(
        prices: const {'Monkey Blood': 456},
        stock: const {'Monkey Blood': 12},
        tradeMarketIds: const {'Monkey Blood': '6211'},
        totalTrades: const {'Monkey Blood': 300},
        tradeObservedAt: {'Monkey Blood': now.millisecondsSinceEpoch},
        fetchedAt: now.millisecondsSinceEpoch,
      );
      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: current,
        missingMaterialNames: recipes.keys,
        forceRefresh: true,
      );
      expect(gateway.requested, isEmpty);
      expect(result.status, MarketRefreshStatus.temporarilyArchived);
      expect(result.summary.message, 'Archived items were skipped.');
      expect(result.summary.requestCount, 0);
      expect(result.summary.failedRequestCount, 0);
      expect(result.summary.unresolvedMaterialCount, 0);
      expect(result.prices, current.prices);
      expect(result.stock, current.stock);
      expect(result.totalTrades, current.totalTrades);
      expect(result.market.unlistedItemNames, isEmpty);
    },
  );

  test(
    'Planner excludes aliases by ID but keeps custom remaps and related items',
    () async {
      final recipes = {
        'Archived alias': _recipe('Archived alias', '06211'),
        'Monkey Blood': _recipe('Monkey Blood', '7011'),
        'Black Magic Crystal - Precision': _recipe(
          'Black Magic Crystal - Precision',
          '15201',
        ),
        'Custom material': _recipe('Custom material', '999999999'),
      };
      final gateway = _Gateway(now);
      final result = await _coordinator(gateway, recipes).refresh(
        mode: CraftMode.alchemy,
        assembledRecipes: recipes,
        currentMarket: MarketState(),
        missingMaterialNames: recipes.keys,
      );
      expect(gateway.requested.map((request) => request.id).toSet(), {
        '7011',
        '15201',
        '999999999',
      });
      expect(result.summary.failedRequestCount, 0);
      expect(result.summary.unresolvedMaterialCount, 0);
      expect(
        result.prices.keys,
        containsAll([
          'Monkey Blood',
          'Black Magic Crystal - Precision',
          'Custom material',
        ]),
      );
      expect(result.prices, isNot(contains('Archived alias')));
    },
  );
}

SharedMarketKey _key(String id) => SharedMarketKey(region: 'eu', itemId: id);

class _Transport implements OpportunityMarketTransport {
  final ids = <String>[];
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final data = jsonDecode(body) as Map;
    final requested = data.containsKey('searchResult')
        ? (data['searchResult'] as String).split(',')
        : ['${data['mainKey']}'];
    ids.addAll(requested);
    final text = uri.path.endsWith('GetBiddingInfoList')
        ? '100-0-7'
        : data.containsKey('searchResult')
        ? requested.map((id) => '$id-3-100-1000').join('|')
        : '${requested.single}-0-0-100-3-1000';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': text})),
      ),
    );
  }

  @override
  void close() {}
}

class _Gateway implements MarketPriceGateway {
  _Gateway(this.now);
  final DateTime now;
  final requested = <MarketPriceRequest>[];
  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async {
    requested.addAll(requests);
    return MarketPriceFetchResult(
      region: 'eu',
      language: 'en',
      fetchedAt: now,
      attemptedSources: const [MarketPriceSource.pearlAbyssCentralMarket],
      items: [
        for (final request in requests)
          MarketPriceRow(
            name: request.name,
            id: request.id,
            ok: true,
            price: 100,
            stock: 3,
            source: MarketPriceSource.pearlAbyssCentralMarket,
            fetchedAt: now,
            diagnosticCode: MarketDiagnosticCode.none,
          ),
      ],
    );
  }
}

MarketRefreshCoordinator _coordinator(
  _Gateway gateway,
  Map<String, Recipe> recipes,
) => MarketRefreshCoordinator(
  gateway: gateway,
  catalogRepository: CatalogRepository(
    CatalogSnapshot(
      sourceSha256: 'fixture',
      sourceByteCount: 1,
      alchemy: _mode(CraftMode.alchemy, recipes),
      cooking: _mode(CraftMode.cooking, const {}),
      processing: _mode(CraftMode.processing, const {}),
      supportingData: const {},
      collisions: const [],
    ),
  ),
);
ModeCatalog _mode(CraftMode mode, Map<String, Recipe> recipes) => ModeCatalog(
  mode: mode,
  items: recipes,
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);
Recipe _recipe(String name, String id) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const [],
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);
