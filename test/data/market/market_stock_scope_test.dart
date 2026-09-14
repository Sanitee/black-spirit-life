import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/shared_market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_bulk_codec.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_codec.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/enhanceable_market_items.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final quoteAt = DateTime.utc(2026, 9, 11, 14, 8, 11, 125);
  final bookAt = DateTime.utc(2026, 9, 11, 14, 8, 16, 763);
  const age = Duration(minutes: 5);
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('market-stock-scope-');
  });
  tearDown(() async => directory.delete(recursive: true));

  OpportunityMarketItem summary({int stock = 6, DateTime? at}) =>
      decodeOpportunityBulkQuotes(
        bytes: _payload('705037-$stock-241000000-96771'),
        requestedIds: ['705037'],
        fetchedAt: at ?? quoteAt,
      ).items['705037']!;

  OpportunityMarketItem book({String? rows, DateTime? at}) =>
      decodeOpportunityOrderBook(
        bytes: _payload(rows ?? '259000000-0-13|224000000-0-1|223000000-0-1'),
        itemId: '705037',
        fetchedAt: at ?? bookAt,
      );

  test('reviewed client registry covers exact current gear identities', () {
    expect(enhanceableMarketItemIds, hasLength(2842));
    for (final id in ['705037', '705047', '705015', '10010', '11607']) {
      expect(isEnhanceableMarketItemId(id), isTrue, reason: id);
    }
    for (final id in ['4998', '1', '900000001', 'not-an-id']) {
      expect(isEnhanceableMarketItemId(id), isFalse, reason: id);
    }
  });

  test('Search aggregate stock is not assigned to the unenhanced item', () {
    final gear = summary();
    expect(gear.stock, isNull);
    expect(gear.aggregateStock, 6);
    expect(gear.basePrice, 241000000);
    expect(gear.stockFor(quoteAt, age), isNull);
    expect(gear.quoteFetchedAt, quoteAt);
    final material = decodeOpportunityBulkQuotes(
      bytes: _payload('4998-6-1000-20'),
      requestedIds: ['4998'],
      fetchedAt: quoteAt,
    ).items['4998']!;
    expect(material.stock, 6);
    expect(material.aggregateStock, isNull);
    expect(material.stockFor(quoteAt, age), 6);
  });

  test('documented multi-enhancement summary does not imply base supply', () {
    // Operator documentation: the 10210 Search count 13 is the sum of all
    // SubList enhancement rows; its base enhancement group has stock zero.
    final gear = decodeOpportunityBulkQuotes(
      bytes: _payload('10210-13-64000000-26322'),
      requestedIds: ['10210'],
      fetchedAt: quoteAt,
    ).items['10210']!;
    expect(gear.aggregateStock, 13);
    expect(gear.stock, isNull);
    expect(gear.stockFor(quoteAt, age), isNull);
  });

  test('saved Manos evidence means zero base sellers and fifteen buyers', () {
    final item = summary().mergeFrom(book());
    expect(item.aggregateStock, 6);
    expect(item.stock, isNull);
    expect(item.asks, isEmpty);
    expect(item.stockFor(bookAt, age), 0);
    expect(item.preorderCount, 15);
    expect(item.bids!.map((level) => level.quantity), [13, 1, 1]);
    expect(item.bids!.map((level) => level.price), [
      259000000,
      224000000,
      223000000,
    ]);
    expect(item.quoteFetchedAt, quoteAt);
    expect(item.bookFetchedAt, bookAt);
    final copy = item.withSalesActivity(null);
    expect(copy.aggregateStock, 6);
    expect(copy.stockFor(bookAt, age), 0);
    expect(copy.quoteFetchedAt, quoteAt);
    expect(copy.bookFetchedAt, bookAt);
  });

  test('positive scoped sell orders and buy orders stay separate', () {
    final item = summary().mergeFrom(
      book(rows: '270000000-2-0|259000000-0-13|275000000-1-0'),
    );
    expect(item.stockFor(bookAt, age), 3);
    expect(item.preorderCount, 13);
    expect(item.aggregateStock, 6);
    expect(item.asks!.map((level) => level.quantity), [2, 1]);
  });

  test('stale and future books never lend their stock to a fresh summary', () {
    final now = quoteAt.add(const Duration(hours: 1));
    final stale = summary(at: now).mergeFrom(book());
    expect(stale.stockFor(now, age), isNull);
    expect(stale.aggregateStock, 6);
    final future = summary().mergeFrom(
      book(at: quoteAt.add(const Duration(seconds: 1))),
    );
    expect(future.stockFor(quoteAt, age), isNull);
    final current = summary().mergeFrom(book(rows: '270000000-2-0'));
    expect(current.stockFor(bookAt.add(age), age), 2);
    expect(
      current.stockFor(
        bookAt.add(age).add(const Duration(milliseconds: 1)),
        age,
      ),
      isNull,
    );
  });

  test(
    'a fresh scoped book remains usable without refreshing the old quote',
    () {
      final currentBookAt = quoteAt.add(const Duration(hours: 1));
      final item = summary().mergeFrom(book(at: currentBookAt));
      expect(item.quoteIsFresh(currentBookAt, age), isFalse);
      expect(item.stockFor(currentBookAt, age), 0);
      expect(item.quoteFetchedAt, quoteAt);
      expect(item.bookFetchedAt, currentBookAt);
    },
  );

  test(
    'a genuine scoped quote replaces aggregate provenance, not book dates',
    () {
      final scoped = decodeOpportunityQuote(
        bytes: _payload('705037-0-0-241000000-4-96771'),
        itemId: '705037',
        fetchedAt: bookAt.add(const Duration(seconds: 1)),
      );
      final item = summary().mergeFrom(book()).mergeFrom(scoped);
      expect(item.aggregateStock, isNull);
      expect(item.stockFor(scoped.quoteFetchedAt!, age), 4);
      expect(item.bookFetchedAt, bookAt);
      final older = item.mergeFrom(summary());
      expect(older.stock, 4);
      expect(older.aggregateStock, isNull);
      expect(older.quoteFetchedAt, scoped.quoteFetchedAt);
    },
  );

  test('newer scoped material quote retains stock ahead of an older book', () {
    final newerQuoteAt = bookAt.add(const Duration(seconds: 1));
    final item = OpportunityMarketItem(
      itemId: '4998',
      basePrice: 100,
      stock: 6,
      quoteFetchedAt: newerQuoteAt,
      asks: const [],
      bids: const [],
      bookFetchedAt: bookAt,
    );
    expect(item.stockFor(newerQuoteAt, age), 6);
    expect(item.quoteFetchedAt, newerQuoteAt);
    expect(item.bookFetchedAt, bookAt);
  });

  for (final quoteState in ['expired', 'absent', 'unknown stock']) {
    for (final sellers in [3, 0]) {
      test(
        'ordinary material uses fresh book stock $sellers with $quoteState quote',
        () {
          final now = bookAt.add(const Duration(hours: 1));
          final at = switch (quoteState) {
            'expired' => quoteAt,
            'unknown stock' => now,
            _ => null,
          };
          final item =
              OpportunityMarketItem(
                itemId: '4998',
                basePrice: at == null ? null : 100,
                stock: quoteState == 'expired' ? 6 : null,
                quoteFetchedAt: at,
              ).mergeFrom(
                decodeOpportunityOrderBook(
                  bytes: _payload('110-$sellers-0|90-0-13'),
                  itemId: '4998',
                  fetchedAt: now,
                ),
              );
          expect(item.stockFor(now, age), sellers);
          expect(item.preorderCount, 13);
          expect(item.stock, quoteState == 'expired' ? 6 : isNull);
          expect(item.quoteFetchedAt, at);
          expect(item.bookFetchedAt, now);
        },
      );
    }
  }

  for (final invalidBook in ['expired', 'future', 'missing date']) {
    test('ordinary material does not use a $invalidBook book as stock', () {
      final now = bookAt.add(const Duration(hours: 1));
      final at = switch (invalidBook) {
        'expired' =>
          now.subtract(age).subtract(const Duration(milliseconds: 1)),
        'future' => now.add(const Duration(milliseconds: 1)),
        _ => null,
      };
      final item = OpportunityMarketItem(
        itemId: '4998',
        basePrice: 100,
        stock: 6,
        quoteFetchedAt: quoteAt,
        asks: const [OpportunityMarketLevel(price: 110, quantity: 3)],
        bids: const [OpportunityMarketLevel(price: 90, quantity: 13)],
        bookFetchedAt: at,
      );
      expect(item.stockFor(now, age), isNull);
      expect(item.quoteFetchedAt, quoteAt);
      expect(item.bookFetchedAt, at);
    });
  }

  test(
    'equal-date scoped zero stock is retained ahead of a differing book',
    () {
      final item = OpportunityMarketItem(
        itemId: '4998',
        basePrice: 100,
        stock: 0,
        quoteFetchedAt: bookAt,
        asks: const [OpportunityMarketLevel(price: 110, quantity: 3)],
        bids: const [OpportunityMarketLevel(price: 90, quantity: 13)],
        bookFetchedAt: bookAt,
      );
      expect(item.stockFor(bookAt, age), 0);
    },
  );

  test('a newer fresh book replaces older scoped zero stock with sellers', () {
    final item = OpportunityMarketItem(
      itemId: '4998',
      basePrice: 100,
      stock: 0,
      quoteFetchedAt: quoteAt,
      asks: const [OpportunityMarketLevel(price: 110, quantity: 3)],
      bids: const [OpportunityMarketLevel(price: 90, quantity: 13)],
      bookFetchedAt: bookAt,
    );
    expect(item.stockFor(bookAt, age), 3);
    expect(item.preorderCount, 13);
    expect(item.stock, 0);
    expect(item.quoteFetchedAt, quoteAt);
    expect(item.bookFetchedAt, bookAt);
  });

  test('stock scope never permits merging different identities or subIds', () {
    expect(
      () => summary().mergeFrom(
        OpportunityMarketItem(
          itemId: '705037',
          subId: 1,
          asks: const [],
          bids: const [],
          bookFetchedAt: bookAt,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => summary().mergeFrom(
        OpportunityMarketItem(
          itemId: '705047',
          asks: const [],
          bids: const [],
          bookFetchedAt: bookAt,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'legacy cache reclassifies gear without changing bytes or receipt times',
    () async {
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => bookAt,
      );
      final legacy = jsonEncode({
        'version': 1,
        'source': 'pearl-abyss',
        'regions': {
          'eu': {
            '705037': {
              'itemId': '705037',
              'subId': 0,
              'basePrice': 241000000,
              'stock': 6,
              'quoteFetchedAt': quoteAt.millisecondsSinceEpoch,
              'asks': <Object?>[],
              'bids': [
                [259000000, 13],
                [224000000, 1],
                [223000000, 1],
              ],
              'bookFetchedAt': bookAt.millisecondsSinceEpoch,
              'totalTrades': 96771,
              'lastSoldAt': null,
              'unlisted': false,
            },
          },
        },
      });
      await File(store.path).writeAsString(legacy);
      final loaded = await store.load();
      final item = loaded['eu']!['705037']!;
      expect(await File(store.path).readAsString(), legacy);
      expect(item.stock, isNull);
      expect(item.aggregateStock, 6);
      expect(item.stockFor(bookAt, age), 0);
      expect(item.quoteFetchedAt, quoteAt);
      expect(item.bookFetchedAt, bookAt);
      await store.save(loaded);
      final reopened = (await store.load())['eu']!['705037']!;
      expect(reopened.aggregateStock, 6);
      expect(reopened.quoteFetchedAt, quoteAt);
      expect(reopened.bookFetchedAt, bookAt);
      final encoded =
          jsonDecode(await File(store.path).readAsString())
              as Map<String, Object?>;
      final regions = encoded['regions']! as Map<String, Object?>;
      final region = regions['eu']! as Map<String, Object?>;
      final encodedItem = region['705037']! as Map<String, Object?>;
      expect(encodedItem['stockScope'], 'allEnhancements');
      expect(encodedItem['stock'], isNull);
    },
  );

  test(
    'cache retains explicit scoped stock and separate regional aggregate books',
    () async {
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => bookAt,
      );
      await store.save({
        'eu': {'705037': summary().mergeFrom(book())},
        'na': {
          '705037': OpportunityMarketItem(
            itemId: '705037',
            basePrice: 241000000,
            stock: 9,
            quoteFetchedAt: quoteAt,
          ),
        },
      });
      final loaded = await store.load();
      expect(loaded['eu']!['705037']!.stockFor(bookAt, age), 0);
      expect(loaded['eu']!['705037']!.aggregateStock, 6);
      expect(loaded['na']!['705037']!.stockFor(bookAt, age), 9);
      expect(loaded['na']!['705037']!.aggregateStock, isNull);
    },
  );

  test('cache distinguishes a known zero aggregate from no evidence', () async {
    final store = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => bookAt,
    );
    await store.save({
      'eu': {'705037': summary(stock: 0)},
    });
    final item = (await store.load())['eu']!['705037']!;
    expect(item.aggregateStock, 0);
    expect(item.stock, isNull);
    expect(item.stockFor(bookAt, age), isNull);
  });

  test(
    'future quote hydration discards aggregate but preserves the valid book',
    () async {
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => bookAt,
      );
      await store.save({
        'eu': {
          '705037': summary(
            at: bookAt.add(const Duration(seconds: 1)),
          ).mergeFrom(book()),
        },
      });
      final item = (await store.load())['eu']!['705037']!;
      expect(item.quoteFetchedAt, isNull);
      expect(item.aggregateStock, isNull);
      expect(item.bookFetchedAt, bookAt);
      expect(item.stockFor(bookAt, age), 0);
    },
  );

  test('cache rejects contradictory or unknown scope metadata', () async {
    final store = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => bookAt,
    );
    await store.save({
      'eu': {'705037': summary()},
    });
    final document =
        jsonDecode(await File(store.path).readAsString())
            as Map<String, Object?>;
    final regions = document['regions']! as Map<String, Object?>;
    final region = regions['eu']! as Map<String, Object?>;
    final item = region['705037']! as Map<String, Object?>;
    item['stockScope'] = 'item';
    await File(store.path).writeAsString(jsonEncode(document));
    await expectLater(store.load(), throwsFormatException);
    item['stockScope'] = 'guessed';
    await File(store.path).writeAsString(jsonEncode(document));
    await expectLater(store.load(), throwsFormatException);
  });

  test(
    'shared dispatch, cache delivery, and gateway preserve aggregate scope',
    () async {
      final transport = _Transport();
      var now = quoteAt;
      final repository = SharedMarketRepository(
        transport: transport,
        utcNow: () => now,
        requestSpacing: Duration.zero,
        orderBookRequestSpacing: Duration.zero,
        quoteBatchSize: 200,
      );
      addTearDown(repository.close);
      final gateway = SharedMarketPriceGateway(repository: repository);
      const requests = [
        MarketPriceRequest(name: "Manos Cook's Clothes", id: '705037'),
        MarketPriceRequest(name: 'Material', id: '4998'),
      ];
      final first = await gateway.fetchProgressive(requests, region: 'eu');
      final gear = first.items.singleWhere((row) => row.id == '705037');
      expect(gear.stock, isNull);
      expect(gear.aggregateStock, 6);
      expect(gear.fetchedAt, quoteAt);
      expect(first.items.singleWhere((row) => row.id == '4998').stock, 7);
      now = bookAt;
      final receipts = <SharedMarketReceipt>[];
      await repository.fetch(
        bookKeys: [SharedMarketKey(region: 'eu', itemId: '705037')],
      );
      await repository.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: '705037')],
        onItem: receipts.add,
      );
      expect(receipts.single.fromCache, isTrue);
      expect(receipts.single.item.aggregateStock, 6);
      expect(receipts.single.item.quoteFetchedAt, quoteAt);
      expect(receipts.single.item.bookFetchedAt, isNull);
      final item = repository.snapshot('eu').items['705037']!;
      expect(item.stockFor(bookAt, age), 0);
      final warm = await gateway.fetchProgressive(requests, region: 'eu');
      expect(
        warm.items.singleWhere((row) => row.id == '705037').stock,
        isNull,
        reason:
            'A quote-only adapter must not redatestamp independently dated book stock.',
      );
      expect(transport.calls, 2);
    },
  );
}

Uint8List _payload(String rows) => Uint8List.fromList(
  utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': rows})),
);

final class _Transport implements OpportunityMarketTransport {
  int calls = 0;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    calls++;
    final book = uri.path.endsWith('GetBiddingInfoList');
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: _payload(
        book
            ? '259000000-0-13|224000000-0-1|223000000-0-1'
            : '705037-6-241000000-96771|4998-7-1000-20',
      ),
    );
  }

  @override
  void close() {}
}
