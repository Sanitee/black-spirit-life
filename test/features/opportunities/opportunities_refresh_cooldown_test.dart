import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'toolbar rechecks cooldown and keeps every saved receipt unchanged',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      expect(controller.refreshReadiness.canRefresh, isTrue);
      expect(controller.refreshReadiness.requestCount, 8);
      await controller.refresh();
      await controller.calculationSettled;
      final before = fixture.transport.calls;
      final saved = fixture.broker.snapshot('eu');
      expect(saved.items.length, 1438);
      expect(controller.refreshReadiness.wait, const Duration(minutes: 1));
      expect(controller.refreshReadiness.canRefresh, isFalse);

      await controller.refresh();
      await controller.refreshAll(onlyStale: false);
      expect(fixture.transport.calls, before);
      expect(controller.scanning, isFalse);
      expect(controller.lastCheck, fixture.now);
      for (final entry in saved.items.entries) {
        expect(
          fixture.broker.snapshot('eu').items[entry.key]!.quoteFetchedAt,
          entry.value.quoteFetchedAt,
        );
      }
      fixture.now = fixture.now.add(const Duration(seconds: 59));
      expect(controller.refreshReadiness.wait, const Duration(seconds: 1));
      fixture.now = fixture.now.add(const Duration(seconds: 1));
      expect(controller.refreshReadiness.canRefresh, isTrue);
      await controller.refresh();
      await controller.calculationSettled;
      expect(fixture.transport.calls, before + 8);
      expect(controller.refreshReadiness.wait, const Duration(minutes: 1));
      expect(
        fixture.broker
            .snapshot('eu')
            .items
            .values
            .every((item) => item.quoteFetchedAt == fixture.now),
        isTrue,
      );
    },
  );

  test(
    'another feature freshening one required item extends full reload cooldown',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      await fixture.controller.calculationSettled;
      fixture.now = fixture.now.add(const Duration(seconds: 65));
      expect(fixture.controller.refreshReadiness.canRefresh, isTrue);
      final id = fixture.broker.snapshot('eu').items.keys.first;
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: id)],
        forceRefresh: true,
      );
      expect(
        fixture.controller.refreshReadiness.wait,
        const Duration(minutes: 1),
      );
      final calls = fixture.transport.calls;
      await fixture.controller.refresh();
      expect(fixture.transport.calls, calls);
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      expect(fixture.controller.refreshReadiness.canRefresh, isTrue);
    },
  );

  test(
    'unrelated in-flight work prevents a stale enabled button starting a reload',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final hold = Completer<void>();
      fixture.transport.hold = hold;
      final other = fixture.broker.fetch(
        bookKeys: [SharedMarketKey(region: 'na', itemId: '1')],
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.controller.refreshReadiness.pendingWork, isTrue);
      expect(fixture.controller.refreshReadiness.canRefresh, isFalse);
      final before = fixture.transport.calls;
      await fixture.controller.refresh();
      expect(fixture.transport.calls, before);
      hold.complete();
      await other;
      expect(fixture.controller.refreshReadiness.canRefresh, isTrue);
    },
  );

  test(
    'Planner reuses Opportunities receipts through five minutes and refreshes only requested expired items',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      await fixture.controller.calculationSettled;
      final at = fixture.now;
      final ids = fixture.broker.snapshot('eu').items.keys.take(2).toList();
      final gateway = SharedMarketPriceGateway(repository: fixture.broker);
      final requests = [
        for (final id in ids) MarketPriceRequest(name: 'Item $id', id: id),
      ];
      final before = fixture.transport.calls;
      fixture.now = at.add(const Duration(minutes: 4, seconds: 59));
      final young = await gateway.fetch(requests);
      expect(fixture.transport.calls, before);
      expect(young.items.every((row) => row.ok && row.fetchedAt == at), isTrue);
      expect(young.fetchedAt, at);

      fixture.now = at.add(sharedMarketFreshness);
      final boundary = await gateway.fetch(requests);
      expect(fixture.transport.calls, before);
      expect(boundary.items.every((row) => row.fetchedAt == at), isTrue);
      expect(boundary.fetchedAt, at);

      fixture.now = fixture.now.add(const Duration(milliseconds: 1));
      fixture.transport.price = 1200;
      final fresh = await gateway.fetch([requests.first]);
      expect(fixture.transport.calls, before + 1);
      expect(fixture.transport.requests.last.book, isFalse);
      expect(fixture.transport.requests.last.ids, [ids.first]);
      expect(fresh.items.single.price, 1200);
      expect(fresh.items.single.fetchedAt, fixture.now);
      expect(fresh.fetchedAt, fixture.now);
      expect(
        fixture.broker.snapshot('eu').items[ids.last]!.quoteFetchedAt,
        at,
        reason: 'Unused expired items must not trigger a catalog reload.',
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.controller.market.items[ids.first]!.basePrice, 1200);
      expect(
        fixture.controller.market.items[ids.first]!.quoteFetchedAt,
        fixture.now,
        reason: 'Planner receipts flow back into Opportunities.',
      );
      expect(fixture.controller.market.items[ids.last]!.quoteFetchedAt, at);
    },
  );

  test('quote and preorder reuse keep independent five-minute ages', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.refresh();
    await fixture.controller.calculationSettled;
    final at = fixture.now;
    final id = fixture.broker.snapshot('eu').items.keys.first;
    final key = SharedMarketKey(region: 'eu', itemId: id);
    fixture.now = at.add(const Duration(minutes: 1));
    await fixture.broker.fetch(bookKeys: [key]);
    final bookAt = fixture.now;
    final before = fixture.transport.calls;
    final gateway = SharedMarketPriceGateway(repository: fixture.broker);

    fixture.now = at.add(
      sharedMarketFreshness + const Duration(milliseconds: 1),
    );
    await gateway.fetch([MarketPriceRequest(name: 'Item $id', id: id)]);
    final quoteAt = fixture.now;
    expect(fixture.transport.calls, before + 1);
    expect(fixture.transport.requests.last.book, isFalse);
    await fixture.broker.fetch(bookKeys: [key]);
    expect(fixture.transport.calls, before + 1);
    expect(fixture.broker.snapshot('eu').items[id]!.bookFetchedAt, bookAt);
    expect(fixture.broker.snapshot('eu').items[id]!.quoteFetchedAt, quoteAt);

    fixture.now = bookAt.add(sharedMarketFreshness);
    await fixture.broker.fetch(quoteKeys: [key], bookKeys: [key]);
    expect(fixture.transport.calls, before + 1);
    fixture.now = fixture.now.add(const Duration(milliseconds: 1));
    await fixture.broker.fetch(quoteKeys: [key], bookKeys: [key]);
    expect(fixture.transport.calls, before + 2);
    expect(fixture.transport.requests.last.book, isTrue);
    expect(fixture.transport.requests.last.ids, [id]);
    expect(fixture.broker.snapshot('eu').items[id]!.quoteFetchedAt, quoteAt);
    expect(fixture.broker.snapshot('eu').items[id]!.bookFetchedAt, fixture.now);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.controller.market.items[id]!.quoteFetchedAt, quoteAt);
    expect(fixture.controller.market.items[id]!.bookFetchedAt, fixture.now);
  });
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  var now = DateTime.utc(2026, 9, 11, 12);
  final transport = _Transport();
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;

  static Future<_Fixture> create() async {
    final fixture = _Fixture(await ApplicationTestHarness.create());
    fixture.broker = SharedMarketRepository(
      transport: fixture.transport,
      concurrency: 20,
      quoteBatchSize: 200,
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: Duration.zero,
      requestWindowLimit: 98,
      requestWindowDuration: const Duration(seconds: 60, milliseconds: 20),
      minimumQuoteRefreshAge: const Duration(minutes: 1),
      minimumBookRefreshAge: const Duration(minutes: 1),
      cacheMaxAge: sharedMarketFreshness,
      utcNow: () => fixture.now,
    );
    fixture.controller = OpportunitiesController(
      appController: fixture.harness.bundle.controller,
      catalog: CatalogRepository(fixture.harness.bundle.catalog),
      directory: Directory(
        '${fixture.harness.temporaryDirectory.path}/opportunities',
      ),
      sharedMarket: fixture.broker,
      prefetchAll: true,
      clock: () => fixture.now,
    );
    await fixture.controller.ready;
    await fixture.controller.calculationSettled;
    return fixture;
  }

  Future<void> dispose() async {
    controller.cancel();
    await broker.close();
    await controller.calculationSettled;
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

final class _Transport implements OpportunityMarketTransport {
  var calls = 0;
  var price = 1000;
  final requests = <({bool book, List<String> ids})>[];
  Completer<void>? hold;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    calls++;
    await hold?.future;
    final payload = jsonDecode(body) as Map;
    final book = uri.path.endsWith('GetBiddingInfoList');
    final ids = '${payload['searchResult'] ?? payload['mainKey']}'.split(',');
    requests.add((book: book, ids: ids));
    final message = book
        ? '1000-0-7'
        : ids.length > 1
        ? ids.map((id) => '$id-10-$price-2000').join('|')
        : '${ids.single}-0-0-$price-10-2000';
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
