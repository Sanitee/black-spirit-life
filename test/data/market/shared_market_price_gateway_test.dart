import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/shared_market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (book: '1300-0-0|1100-0-2|1200-0-1|900-0-20', expected: 1200, fails: false),
    (book: '1300-0-0|1100-0-0', expected: 0, fails: false),
    (book: '800-0-2|900-0-1', expected: 900, fails: false),
    (book: '1300-0-1', expected: null, fails: true),
  ]) {
    test(
      'sold-out quote budgets highest occupied bid ${scenario.expected}',
      () async {
        final now = DateTime.utc(2026, 9, 24, 14);
        final transport = _Transport()
          ..stock = 0
          ..book = scenario.book
          ..bookFails = scenario.fails;
        final repository = SharedMarketRepository(
          transport: transport,
          utcNow: () => now,
          requestSpacing: Duration.zero,
        );
        addTearDown(repository.close);
        final gateway = SharedMarketPriceGateway(
          repository: repository,
          utcNow: () => now,
        );
        final result = await gateway.fetchProgressive(const [
          MarketPriceRequest(name: 'Milk', id: '1'),
        ], region: 'eu');
        final row = result.items.single;
        expect(row.ok, isTrue);
        expect(
          row.price,
          1000,
          reason: 'Do not replace selling/base quotes with buy orders',
        );
        expect(row.stock, 0);
        expect(row.preorderPrice, scenario.expected);
        expect(row.fetchedAt, now);
        expect(transport.bookCalls, 1);
        if (!scenario.fails) {
          await gateway.fetchProgressive(const [
            MarketPriceRequest(name: 'Milk', id: '1'),
          ], region: 'eu');
          expect(transport.bookCalls, 1, reason: 'Reuse the shared book cache');
        }
      },
    );
  }

  test(
    'bulk sold-out quotes request books, regions stay isolated and restocking stops preorder use',
    () async {
      var now = DateTime.utc(2026, 9, 24, 14);
      final transport = _Transport()..stock = 0;
      final repository = SharedMarketRepository(
        transport: transport,
        utcNow: () => now,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final gateway = SharedMarketPriceGateway(
        repository: repository,
        utcNow: () => now,
      );
      const requests = [
        MarketPriceRequest(name: 'Milk', id: '1'),
        MarketPriceRequest(name: 'Egg', id: '2'),
      ];
      final eu = await gateway.fetchProgressive(requests, region: 'eu');
      expect(eu.items.map((row) => row.preorderPrice), everyElement(1200));
      expect(eu.items.map((row) => row.stock), everyElement(0));
      expect(transport.bookCalls, 2);
      transport.book = '1500-0-2';
      final na = await gateway.fetchProgressive(requests, region: 'na');
      expect(na.items.map((row) => row.preorderPrice), everyElement(1500));
      expect(transport.bookCalls, 4);
      now = now.add(const Duration(minutes: 1));
      transport.stock = 20;
      final restocked = await gateway.fetchProgressive(
        [requests.first],
        region: 'eu',
        forceRefresh: true,
      );
      expect(restocked.items.single.stock, 20);
      expect(restocked.items.single.preorderPrice, 0);
      expect(transport.bookCalls, 4);
    },
  );

  test('stale and future books do not become preorder prices', () {
    final now = DateTime.utc(2026, 9, 24, 14);
    for (final time in [
      now.subtract(const Duration(minutes: 6)),
      now.add(const Duration(seconds: 1)),
    ]) {
      final row = sharedMarketPriceRow(
        OpportunityMarketItem(
          itemId: '1',
          basePrice: 1000,
          stock: 0,
          quoteFetchedAt: now,
          asks: const [],
          bids: const [OpportunityMarketLevel(price: 1200, quantity: 1)],
          bookFetchedAt: time,
        ),
        name: 'Milk',
        now: now,
      );
      expect(row.preorderPrice, isNull);
      expect(row.price, 1000);
    }
  });

  for (final ageSeconds in [59, 60]) {
    test(
      'Planner minute-policy Refresh at ${ageSeconds}s preserves the true quote age',
      () async {
        final transport = _Transport();
        var now = DateTime.utc(2026, 9, 11, 12);
        final original = now;
        final repository = SharedMarketRepository(
          transport: transport,
          utcNow: () => now,
          requestSpacing: Duration.zero,
          minimumQuoteRefreshAge: const Duration(minutes: 1),
          minimumBookRefreshAge: const Duration(minutes: 1),
        );
        addTearDown(repository.close);
        final gateway = SharedMarketPriceGateway(repository: repository);
        const requests = [MarketPriceRequest(name: 'Wheat', id: '1')];
        await gateway.fetchProgressive(requests, region: 'eu');
        now = now.add(Duration(seconds: ageSeconds));
        final refreshed = await gateway.fetchProgressive(
          requests,
          region: 'eu',
          forceRefresh: true,
        );
        final reused = ageSeconds < 60;
        expect(transport.calls, reused ? 1 : 2);
        expect(refreshed.items.single.ok, isTrue);
        expect(refreshed.items.single.fetchedAt, reused ? original : now);
        expect(refreshed.fetchedAt, reused ? original : now);
        expect(
          repository.snapshot('eu').items['1']!.quoteFetchedAt,
          reused ? original : now,
        );
      },
    );
  }

  test(
    'Planner Refresh still renews quotes within the book reuse minute',
    () async {
      final transport = _Transport();
      var now = DateTime.utc(2026, 9, 11, 12);
      final original = now;
      final repository = SharedMarketRepository(
        transport: transport,
        utcNow: () => now,
        requestSpacing: Duration.zero,
        minimumBookRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(repository.close);
      final gateway = SharedMarketPriceGateway(repository: repository);
      const requests = [MarketPriceRequest(name: 'Wheat', id: '1')];
      final first = await gateway.fetchProgressive(requests, region: 'eu');
      expect(first.items.single.fetchedAt, original);
      now = now.add(const Duration(seconds: 30));
      final refreshed = await gateway.fetchProgressive(
        requests,
        region: 'eu',
        forceRefresh: true,
      );
      expect(transport.calls, 2);
      expect(refreshed.items.single.ok, isTrue);
      expect(refreshed.items.single.fetchedAt, now);
      expect(repository.snapshot('eu').items['1']!.quoteFetchedAt, now);
    },
  );

  test(
    'Planner and another tab share one bulk request; warm reads keep receipt time',
    () async {
      final transport = _Transport();
      var now = DateTime.utc(2026, 9, 10, 12);
      final receivedAt = now;
      final repository = SharedMarketRepository(
        transport: transport,
        utcNow: () => now,
      );
      addTearDown(repository.close);
      final gateway = SharedMarketPriceGateway(repository: repository);
      final first = gateway.fetchProgressive(const [
        MarketPriceRequest(name: 'Wheat', id: '0001'),
        MarketPriceRequest(name: 'Milk', id: '2'),
      ], region: 'eu');
      final sibling = repository.fetch(
        quoteKeys: [
          SharedMarketKey(region: 'EU', itemId: '1'),
          SharedMarketKey(region: 'eu', itemId: '2'),
        ],
      );
      final result = await first;
      await sibling;
      expect(transport.calls, 1);
      expect(result.items.map((item) => item.name), ['Wheat', 'Milk']);
      expect(result.items.first.stock, 20);
      expect(result.items.first.totalTrades, 500);
      now = now.add(const Duration(hours: 2));
      final cached = await gateway.fetch(const [
        MarketPriceRequest(name: 'Another name', id: '1'),
      ]);
      expect(transport.calls, 1);
      expect(cached.fetchedAt, receivedAt);
      expect(cached.items.single.fetchedAt, receivedAt);
      expect(cached.items.single.name, 'Another name');
      expect(cached.items.single.lastSoldAtEpochSeconds, isNull);
    },
  );

  test(
    'NA is fetched separately and unsupported regions never issue requests',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository(transport: transport);
      addTearDown(repository.close);
      final gateway = SharedMarketPriceGateway(repository: repository);
      const requests = [MarketPriceRequest(name: 'Wheat', id: '1')];
      await gateway.fetchProgressive(requests, region: 'eu');
      final na = await gateway.fetchProgressive(requests, region: 'na');
      expect(na.region, 'na');
      expect(transport.hosts, [
        'eu-trade.naeu.playblackdesert.com',
        'na-trade.naeu.playblackdesert.com',
      ]);
      final unsupported = await gateway.fetchProgressive(
        requests,
        region: 'kr',
      );
      expect(
        unsupported.items.single.diagnosticCode,
        MarketDiagnosticCode.unsupportedRegion,
      );
      expect(transport.calls, 2);
    },
  );

  test('one slow quote does not hide completed prices', () async {
    final slow = Completer<void>();
    final transport = _Transport(holdId: '41', hold: slow.future);
    final repository = SharedMarketRepository(transport: transport);
    addTearDown(repository.close);
    final gateway = SharedMarketPriceGateway(repository: repository);
    final visible = Completer<MarketPriceFetchResult>();
    var finished = false;
    final all = gateway
        .fetchProgressive(
          [
            for (var i = 1; i <= 41; i++)
              MarketPriceRequest(name: 'Item $i', id: '$i'),
          ],
          region: 'eu',
          onUpdate: (partial) {
            if (!visible.isCompleted) visible.complete(partial);
          },
        )
        .then((result) {
          finished = true;
          return result;
        });
    final partial = await visible.future.timeout(const Duration(seconds: 3));
    expect(partial.items, hasLength(40));
    expect(partial.items.every((row) => row.ok), isTrue);
    expect(finished, isFalse);
    slow.complete();
    expect((await all).items, hasLength(41));
  });

  test(
    'a failed refresh is unknown, not free or proof that an item is unlisted',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository(transport: transport);
      addTearDown(repository.close);
      final gateway = SharedMarketPriceGateway(repository: repository);
      const requests = [MarketPriceRequest(name: 'Wheat', id: '1')];
      await gateway.fetch(requests);
      transport.fails = true;
      final result = await gateway.fetchProgressive(
        requests,
        region: 'eu',
        forceRefresh: true,
      );
      final failed = result.items.single;
      expect(failed.ok, isFalse);
      expect(failed.stock, isNull);
      expect(failed.diagnosticCode, MarketDiagnosticCode.network);
      expect(repository.snapshot('eu').items['1']!.basePrice, 1000);
    },
  );
}

final class _Transport implements OpportunityMarketTransport {
  _Transport({this.holdId, this.hold});
  final String? holdId;
  final Future<void>? hold;
  int calls = 0;
  bool fails = false;
  int stock = 20;
  String book = '1200-0-1';
  bool bookFails = false;
  int bookCalls = 0;
  final hosts = <String>[];

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    calls++;
    final isBook = uri.path.endsWith('GetBiddingInfoList');
    if (isBook) bookCalls++;
    hosts.add(uri.host);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final ids = data.containsKey('searchResult')
        ? (data['searchResult'] as String).split(',')
        : ['${data['mainKey']}'];
    if (ids.contains(holdId)) await hold;
    await Future<void>.delayed(Duration.zero);
    if (fails || (isBook && bookFails)) {
      return OpportunityHttpResponse(statusCode: 503, bytes: Uint8List(0));
    }
    final message = isBook
        ? book
        : ids.length > 1
        ? ids.map((id) => '$id-$stock-1000-500').join('|')
        : '${ids.single}-0-0-1000-$stock-500-1-10000-1000-1788860000';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': message})),
      ),
    );
  }

  @override
  void close() {}
}
