import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_pause_store.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_request_window.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final initial = DateTime.utc(2026, 9, 11, 12);

  for (final age in [Duration.zero, const Duration(microseconds: 59999999)]) {
    test('forced books reuse unchanged receipts at age $age', () async {
      var now = initial;
      final transport = _Transport();
      final repository = _repository(transport, () => now);
      addTearDown(repository.close);
      await repository.fetch(bookKeys: [_key('1')]);
      final events = <SharedMarketReceipt>[];
      final subscription = repository.receipts.listen(events.add);
      addTearDown(subscription.cancel);
      now = initial.add(age);
      final delivered = <SharedMarketReceipt>[];
      final batch = await repository.fetch(
        bookKeys: [_key('1')],
        forceRefresh: true,
        userInitiated: true,
        onItem: delivered.add,
      );
      await Future<void>.delayed(Duration.zero);
      expect(batch.failures, isEmpty);
      expect(batch.items[_key('1')]!.bookFetchedAt, initial);
      expect(batch.items[_key('1')]!.preorderCount, 7);
      expect(delivered.single.fromCache, isTrue);
      expect(delivered.single.item.bookFetchedAt, initial);
      expect(events, isEmpty, reason: 'Cache hits are not new observations.');
      expect(transport.requests, hasLength(1));
      expect(repository.diagnostics.cacheHits, 1);
    });
  }

  for (final age in [
    const Duration(minutes: 1),
    const Duration(microseconds: 60000001),
  ]) {
    test('forced books fetch again at age $age', () async {
      var now = initial;
      final transport = _Transport();
      final repository = _repository(transport, () => now);
      addTearDown(repository.close);
      await repository.fetch(bookKeys: [_key('1')]);
      now = initial.add(age);
      final receipts = <SharedMarketReceipt>[];
      final batch = await repository.fetch(
        bookKeys: [_key('1')],
        forceRefresh: true,
        onItem: receipts.add,
      );
      expect(batch.failures, isEmpty);
      expect(batch.items[_key('1')]!.bookFetchedAt, now);
      expect(receipts.single.fromCache, isFalse);
      expect(transport.requests, hasLength(2));
    });
  }

  for (final age in [Duration.zero, const Duration(microseconds: 59999999)]) {
    test('forced quotes reuse unchanged receipts at age $age', () async {
      var now = initial;
      final transport = _Transport();
      final repository = _repository(
        transport,
        () => now,
        minimumQuoteRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(repository.close);
      await repository.fetch(quoteKeys: [_key('1')]);
      final events = <SharedMarketReceipt>[];
      final subscription = repository.receipts.listen(events.add);
      addTearDown(subscription.cancel);
      now = initial.add(age);
      transport.price = 200;
      final delivered = <SharedMarketReceipt>[];
      final batch = await repository.fetch(
        quoteKeys: [_key('1')],
        forceRefresh: true,
        userInitiated: true,
        onItem: delivered.add,
      );
      await Future<void>.delayed(Duration.zero);
      expect(batch.failures, isEmpty);
      expect(batch.items[_key('1')]!.quoteFetchedAt, initial);
      expect(batch.items[_key('1')]!.basePrice, 100);
      expect(batch.items[_key('1')]!.stock, 5);
      expect(delivered.single.fromCache, isTrue);
      expect(delivered.single.item.quoteFetchedAt, initial);
      expect(events, isEmpty, reason: 'Cache hits are not new observations.');
      expect(transport.requests, hasLength(1));
      expect(repository.diagnostics.cacheHits, 1);
    });
  }

  for (final age in [
    const Duration(minutes: 1),
    const Duration(microseconds: 60000001),
  ]) {
    test('forced quotes fetch again at age $age', () async {
      var now = initial;
      final transport = _Transport();
      final repository = _repository(
        transport,
        () => now,
        minimumQuoteRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(repository.close);
      await repository.fetch(quoteKeys: [_key('1')]);
      now = initial.add(age);
      transport.price = 200;
      final receipts = <SharedMarketReceipt>[];
      final batch = await repository.fetch(
        quoteKeys: [_key('1')],
        forceRefresh: true,
        onItem: receipts.add,
      );
      expect(batch.failures, isEmpty);
      expect(batch.items[_key('1')]!.quoteFetchedAt, now);
      expect(batch.items[_key('1')]!.basePrice, 200);
      expect(receipts.single.fromCache, isFalse);
      expect(transport.requests, hasLength(2));
    });
  }

  test('quote and book ages decide reuse independently per item', () async {
    var now = initial;
    final transport = _Transport();
    final repository = _repository(
      transport,
      () => now,
      minimumQuoteRefreshAge: const Duration(minutes: 1),
    );
    addTearDown(repository.close);
    await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('2')]);
    final recentAt = initial.add(const Duration(seconds: 40));
    now = recentAt;
    await repository.fetch(quoteKeys: [_key('2')], bookKeys: [_key('1')]);
    now = initial.add(const Duration(seconds: 70));
    final before = transport.requests.length;
    final receipts = <SharedMarketReceipt>[];
    final result = await repository.fetch(
      quoteKeys: [_key('1'), _key('2'), _key('3')],
      bookKeys: [_key('1'), _key('2'), _key('3')],
      forceRefresh: true,
      onItem: receipts.add,
    );
    expect(result.failures, isEmpty);
    expect(
      transport.requests
          .skip(before)
          .where((r) => !r.book)
          .expand((r) => r.ids)
          .toSet(),
      {'1', '3'},
    );
    expect(
      transport.requests
          .skip(before)
          .where((r) => r.book)
          .expand((r) => r.ids)
          .toSet(),
      {'2', '3'},
    );
    expect(result.items[_key('1')]!.quoteFetchedAt, now);
    expect(result.items[_key('1')]!.bookFetchedAt, recentAt);
    expect(result.items[_key('2')]!.quoteFetchedAt, recentAt);
    expect(result.items[_key('2')]!.bookFetchedAt, now);
    expect(result.items[_key('3')]!.quoteFetchedAt, now);
    expect(result.items[_key('3')]!.bookFetchedAt, now);
    expect(receipts.where((r) => r.fromCache), hasLength(2));
    expect(receipts.where((r) => !r.fromCache), hasLength(4));
  });

  test('quote reuse respects ordinary cache and stricter caller age', () async {
    var now = initial;
    final transport = _Transport();
    final repository = _repository(
      transport,
      () => now,
      minimumQuoteRefreshAge: const Duration(minutes: 1),
    );
    addTearDown(repository.close);
    await repository.fetch(quoteKeys: [_key('1')]);
    now = initial.add(const Duration(hours: 2));
    await repository.fetch(quoteKeys: [_key('1')]);
    expect(transport.requests, hasLength(1));
    await repository.fetch(quoteKeys: [_key('1')], forceRefresh: true);
    expect(transport.requests, hasLength(2));
    now = now.add(const Duration(seconds: 30));
    final result = await repository.fetch(
      quoteKeys: [_key('1')],
      forceRefresh: true,
      maxAge: const Duration(seconds: 10),
    );
    expect(result.failures, isEmpty);
    expect(result.items[_key('1')]!.quoteFetchedAt, now);
    expect(transport.requests, hasLength(3));
  });

  test(
    'invalid, missing and future quotes are fetched instead of reused',
    () async {
      final directory = await _temporaryDirectory();
      final cache = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => initial,
      );
      await cache.save({
        'eu': {
          '1': OpportunityMarketItem(itemId: '1', quoteFetchedAt: initial),
          '2': OpportunityMarketItem(
            itemId: '2',
            basePrice: 0,
            quoteFetchedAt: initial,
          ),
          '3': _item('3', initial.add(const Duration(seconds: 10))),
          '4': OpportunityMarketItem(itemId: '4', basePrice: 100),
        },
      });
      final transport = _Transport();
      final repository = _repository(
        transport,
        () => initial,
        cache: cache,
        minimumQuoteRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(repository.close);
      final result = await repository.fetch(
        quoteKeys: [_key('1'), _key('2'), _key('3'), _key('4'), _key('5')],
        forceRefresh: true,
      );
      expect(result.failures, isEmpty);
      expect(transport.requests.expand((r) => r.ids).toSet(), {
        '1',
        '2',
        '3',
        '4',
        '5',
      });
      expect(
        result.items.values.every((item) => item.quoteFetchedAt == initial),
        isTrue,
      );
      expect(
        result.items.values.every((item) => item.basePrice == 100),
        isTrue,
      );
      expect(repository.diagnostics.cacheHits, 0);
    },
  );

  test(
    'quotes refresh independently while young zero-buyer books reuse',
    () async {
      var now = initial;
      final transport = _Transport()..buyers = 0;
      final repository = _repository(transport, () => now);
      addTearDown(repository.close);
      await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
      now = initial.add(const Duration(seconds: 30));
      transport.price = 200;
      final receipts = <SharedMarketReceipt>[];
      final batch = await repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1')],
        forceRefresh: true,
        onItem: receipts.add,
      );
      final item = batch.items[_key('1')]!;
      expect(batch.failures, isEmpty);
      expect(item.basePrice, 200);
      expect(item.quoteFetchedAt, now);
      expect(item.bookFetchedAt, initial);
      expect(item.preorderCount, 0, reason: 'Checked zero is not missing.');
      expect(transport.requests.where((request) => request.book), hasLength(1));
      expect(
        transport.requests.where((request) => !request.book),
        hasLength(2),
      );
      expect(
        receipts.singleWhere((r) => r.part == SharedMarketPart.quote).fromCache,
        isFalse,
      );
      expect(
        receipts
            .singleWhere((r) => r.part == SharedMarketPart.orderBook)
            .fromCache,
        isTrue,
      );
    },
  );

  test('mixed requests fetch only missing or old books', () async {
    var now = initial;
    final transport = _Transport();
    final repository = _repository(transport, () => now);
    addTearDown(repository.close);
    await repository.fetch(bookKeys: [_key('1')]);
    now = initial.add(const Duration(seconds: 40));
    await repository.fetch(bookKeys: [_key('2')]);
    now = initial.add(const Duration(seconds: 70));
    final before = transport.requests.length;
    final receipts = <SharedMarketReceipt>[];
    final result = await repository.fetch(
      bookKeys: [_key('1'), _key('2'), _key('3')],
      forceRefresh: true,
      onItem: receipts.add,
    );
    expect(result.failures, isEmpty);
    expect(transport.requests.skip(before).expand((r) => r.ids).toSet(), {
      '1',
      '3',
    });
    expect(
      result.items[_key('2')]!.bookFetchedAt,
      initial.add(const Duration(seconds: 40)),
    );
    expect(result.items[_key('1')]!.bookFetchedAt, now);
    expect(result.items[_key('3')]!.bookFetchedAt, now);
    expect(receipts.where((r) => r.fromCache).single.key.itemId, '2');
  });

  test(
    'ordinary three-hour cache and stricter caller age remain intact',
    () async {
      var now = initial;
      final transport = _Transport();
      final repository = _repository(transport, () => now);
      addTearDown(repository.close);
      await repository.fetch(bookKeys: [_key('1')]);
      now = initial.add(const Duration(hours: 2));
      await repository.fetch(bookKeys: [_key('1')]);
      expect(transport.requests, hasLength(1));
      await repository.fetch(bookKeys: [_key('1')], forceRefresh: true);
      expect(transport.requests, hasLength(2));
      now = now.add(const Duration(seconds: 30));
      await repository.fetch(
        bookKeys: [_key('1')],
        forceRefresh: true,
        maxAge: const Duration(seconds: 10),
      );
      expect(transport.requests, hasLength(3));
    },
  );

  test('generic strict force remains opt-in compatible', () async {
    final transport = _Transport();
    final repository = SharedMarketRepository(
      transport: transport,
      requestSpacing: Duration.zero,
    );
    addTearDown(repository.close);
    expect(repository.minimumQuoteRefreshAge, Duration.zero);
    expect(repository.minimumBookRefreshAge, Duration.zero);
    await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
    await repository.fetch(
      quoteKeys: [_key('1')],
      bookKeys: [_key('1')],
      forceRefresh: true,
    );
    expect(transport.requests, hasLength(4));
    expect(
      () => SharedMarketRepository(
        transport: transport,
        minimumBookRefreshAge: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => SharedMarketRepository(
        transport: transport,
        minimumQuoteRefreshAge: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test(
    'missing sides or a future cached timestamp are fetched, not reused',
    () async {
      final directory = await _temporaryDirectory();
      final cache = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => initial,
      );
      await cache.save({
        'eu': {
          '1': _item('1', initial, asks: null),
          '2': _item('2', initial, bids: null),
          '3': _item('3', initial.add(const Duration(seconds: 10))),
        },
      });
      final transport = _Transport();
      final repository = _repository(transport, () => initial, cache: cache);
      addTearDown(repository.close);
      final result = await repository.fetch(
        bookKeys: [_key('1'), _key('2'), _key('3')],
        forceRefresh: true,
      );
      expect(result.failures, isEmpty);
      expect(transport.requests, hasLength(3));
      expect(
        result.items.values.every((item) => item.bookFetchedAt == initial),
        isTrue,
      );
      expect(repository.diagnostics.cacheHits, 0);
    },
  );

  for (final used in [79, 80]) {
    test(
      'young persisted quotes and books reuse with $used starts already used',
      () async {
        final directory = await _temporaryDirectory();
        final cache = OpportunityMarketCacheStore(
          directory: directory,
          utcNow: () => initial,
        );
        final bookAt = initial.subtract(const Duration(seconds: 30));
        await cache.save({
          'eu': {'1': _item('1', bookAt)},
        });
        final window = MarketRequestWindowStore(directory: directory);
        await window.save(List.filled(used, initial));
        final transport = _Transport();
        final repository = SharedMarketRepository.application(
          transport: transport,
          cacheStore: cache,
          utcNow: () => initial,
        );
        addTearDown(repository.close);
        final result = await repository
            .fetch(
              quoteKeys: [_key('1')],
              bookKeys: [_key('1')],
              forceRefresh: true,
              userInitiated: true,
            )
            .timeout(const Duration(seconds: 2));
        expect(result.failures, isEmpty);
        expect(result.items[_key('1')]!.bookFetchedAt, bookAt);
        expect(result.items[_key('1')]!.quoteFetchedAt, bookAt);
        expect(transport.requests, isEmpty);
        expect(repository.diagnostics.startedRequests, 0);
        expect(await window.load(), List.filled(used, initial));
        expect((await cache.load())['eu']!['1']!.bookFetchedAt, bookAt);
        expect((await cache.load())['eu']!['1']!.quoteFetchedAt, bookAt);
      },
    );
  }

  test('cache reuse never clears an active provider pause', () async {
    final directory = await _temporaryDirectory();
    final cache = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => initial,
    );
    final bookAt = initial.subtract(const Duration(seconds: 30));
    await cache.save({
      'eu': {'1': _item('1', bookAt)},
    });
    final pauses = MarketPauseStore(directory: directory);
    final pause = MarketRequestPause(
      reason: MarketRequestPauseReason.protected,
      retryAt: initial.add(const Duration(hours: 1)),
    );
    await pauses.save({'eu': pause});
    final transport = _Transport();
    final repository = _repository(
      transport,
      () => initial,
      cache: cache,
      minimumQuoteRefreshAge: const Duration(minutes: 1),
    );
    addTearDown(repository.close);
    final cached = await repository.fetch(
      quoteKeys: [_key('1')],
      bookKeys: [_key('1')],
      forceRefresh: true,
    );
    expect(cached.failures, isEmpty);
    final refused = await repository.fetch(
      quoteKeys: [_key('2')],
      bookKeys: [_key('2')],
      forceRefresh: true,
      userInitiated: true,
    );
    expect(refused.failures, hasLength(2));
    expect(
      repository.pauseFor('eu')!.reason,
      MarketRequestPauseReason.protected,
    );
    expect(repository.pauseFor('eu')!.retryAt, pause.retryAt);
    expect(transport.requests, isEmpty);
    expect((await pauses.load())['eu']!.retryAt, pause.retryAt);
  });

  test('one region cannot reuse another region book', () async {
    final transport = _Transport();
    final repository = _repository(transport, () => initial);
    addTearDown(repository.close);
    await repository.fetch(bookKeys: [_key('1')]);
    await repository.fetch(
      bookKeys: [SharedMarketKey(region: 'na', itemId: '1')],
      forceRefresh: true,
    );
    expect(transport.requests, hasLength(2));
    expect(transport.requests.map((r) => r.region).toSet(), {'eu', 'na'});
  });
}

SharedMarketKey _key(String id) => SharedMarketKey(region: 'eu', itemId: id);

SharedMarketRepository _repository(
  _Transport transport,
  DateTime Function() now, {
  OpportunityMarketCacheStore? cache,
  Duration minimumQuoteRefreshAge = Duration.zero,
}) => SharedMarketRepository(
  transport: transport,
  cacheStore: cache,
  utcNow: now,
  requestSpacing: Duration.zero,
  minimumBookRefreshAge: const Duration(minutes: 1),
  minimumQuoteRefreshAge: minimumQuoteRefreshAge,
);

OpportunityMarketItem _item(
  String id,
  DateTime at, {
  List<OpportunityMarketLevel>? asks = const [],
  List<OpportunityMarketLevel>? bids = const [],
}) => OpportunityMarketItem(
  itemId: id,
  basePrice: 100,
  stock: 5,
  quoteFetchedAt: at,
  bookFetchedAt: at,
  asks: asks,
  bids: bids,
);

Future<Directory> _temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'recent-market-books-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

final class _Transport implements OpportunityMarketTransport {
  final requests = <({bool book, List<String> ids, String region})>[];
  int buyers = 7;
  int price = 100;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final ids =
        payload['searchResult']?.toString().split(',') ??
        ['${payload['mainKey']}'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    requests.add((book: book, ids: ids, region: uri.host.split('-').first));
    final message = book
        ? '100-5-0|90-0-$buyers'
        : ids.length > 1
        ? ids.map((id) => '$id-5-$price-1000').join('|')
        : '${ids.single}-0-0-$price-5-1000';
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
