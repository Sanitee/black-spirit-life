import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_pause_store.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_request_window.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

// All transport responses are synthetic; readiness checks never contact a server.
void main() {
  late Directory directory;
  late DateTime now;
  late _Transport transport;
  SharedMarketRepository? repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('market-readiness-test-');
    now = DateTime.utc(2026, 9, 11, 12);
    transport = _Transport();
    repository = null;
  });
  tearDown(() async {
    await repository?.close();
    await directory.delete(recursive: true);
  });

  Future<SharedMarketRepository> open({
    int limit = 98,
    int concurrency = 2,
    int quoteBatchSize = 200,
    Duration minimumQuoteAge = const Duration(minutes: 1),
    Duration minimumBookAge = const Duration(minutes: 1),
  }) async {
    final result = SharedMarketRepository(
      cacheStore: OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
      ),
      pauseStore: MarketPauseStore(directory: directory, utcNow: () => now),
      transport: transport,
      utcNow: () => now,
      quoteBatchSize: quoteBatchSize,
      concurrency: concurrency,
      requestWindowLimit: limit,
      requestWindowDuration: const Duration(seconds: 60, milliseconds: 20),
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: Duration.zero,
      minimumQuoteRefreshAge: minimumQuoteAge,
      minimumBookRefreshAge: minimumBookAge,
    );
    repository = result;
    await result.ready;
    return result;
  }

  Future<void> saveItems(List<OpportunityMarketItem> items) =>
      OpportunityMarketCacheStore(directory: directory).save({
        'eu': {for (final item in items) item.itemId: item},
      });

  test(
    'cost deduplicates identities but keeps quote and book parts separate',
    () async {
      final broker = await open();
      final keys = [for (var id = 1000; id <= 1200; id++) _key('$id')];
      final quotes = [...keys, keys.first, _key('0001000')];
      final books = [keys.first, keys.first];
      final readiness = broker.refreshReadiness(
        region: ' EU ',
        quoteKeys: quotes,
        bookKeys: books,
      );
      expect(readiness.requestCount, 3);
      expect(readiness.windowLimit, 98);
      expect(readiness.staged, isFalse);
      expect(readiness.canRefresh, isTrue);
      expect(transport.requests, isEmpty);

      final result = await broker.fetch(quoteKeys: quotes, bookKeys: books);
      expect(result.failures, isEmpty);
      expect(transport.requests, hasLength(readiness.requestCount));
      expect(
        transport.requests
            .where((request) => !request.book)
            .map((request) => request.ids.length),
        [200, 1],
      );
      expect(transport.requests.where((request) => request.book), hasLength(1));
      expect(
        broker
            .refreshReadiness(region: 'eu', quoteKeys: quotes, bookKeys: books)
            .requestCount,
        3,
      );
    },
  );

  test(
    'cost respects both the 200-ID and 999-character packing boundaries',
    () async {
      final broker = await open();
      final short = [for (var id = 1000; id < 1200; id++) _key('$id')];
      final long = [for (var id = 100000; id < 100143; id++) _key('$id')];
      expect(short.map((key) => key.itemId).join(',').length, 999);
      expect(long.map((key) => key.itemId).join(',').length, 1000);
      expect(
        broker.refreshReadiness(region: 'eu', quoteKeys: short).requestCount,
        1,
      );
      expect(
        broker.refreshReadiness(region: 'eu', quoteKeys: long).requestCount,
        2,
      );
      expect(transport.requests, isEmpty);

      final result = await broker.fetch(quoteKeys: long);
      expect(result.failures, isEmpty);
      expect(transport.requests.map((request) => request.ids.length), [142, 1]);
      expect(
        transport.requests.every(
          (request) => request.ids.join(',').length <= 999,
        ),
        isTrue,
      );
    },
  );

  test('cost respects a caller-configured smaller quote batch size', () async {
    final broker = await open(quoteBatchSize: 3);
    final keys = [for (var id = 1; id <= 7; id++) _key('$id')];
    expect(
      broker.refreshReadiness(region: 'eu', quoteKeys: keys).requestCount,
      3,
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'wait follows the latest requested receipt and keeps quote/book dates separate',
    () async {
      final quoteAt = now.subtract(const Duration(seconds: 59));
      final bookAt = now.subtract(const Duration(seconds: 20));
      final newerQuoteAt = now.subtract(const Duration(seconds: 10));
      await saveItems([
        _item('1', quoteAt: quoteAt, bookAt: bookAt),
        _item(
          '2',
          quoteAt: newerQuoteAt,
          bookAt: now.subtract(const Duration(hours: 4)),
        ),
        _item('3', quoteAt: now, bookAt: now),
      ]);
      final broker = await open();
      expect(
        broker.refreshReadiness(region: 'eu', quoteKeys: [_key('1')]).wait,
        const Duration(seconds: 1),
      );
      expect(
        broker.refreshReadiness(region: 'eu', bookKeys: [_key('1')]).wait,
        const Duration(seconds: 40),
      );
      expect(
        broker
            .refreshReadiness(
              region: 'eu',
              quoteKeys: [_key('1'), _key('2')],
              bookKeys: [_key('1')],
            )
            .wait,
        const Duration(seconds: 50),
      );
      now = now.add(const Duration(milliseconds: 999));
      expect(
        broker.refreshReadiness(region: 'eu', quoteKeys: [_key('1')]).wait,
        const Duration(milliseconds: 1),
      );
      now = now.add(const Duration(milliseconds: 1));
      expect(
        broker
            .refreshReadiness(region: 'eu', quoteKeys: [_key('1')])
            .canRefresh,
        isTrue,
      );
      now = now.add(const Duration(seconds: 49));
      expect(
        broker
            .refreshReadiness(
              region: 'eu',
              quoteKeys: [_key('1'), _key('2')],
              bookKeys: [_key('1')],
            )
            .canRefresh,
        isTrue,
      );
      expect(broker.snapshot('eu').items['1']!.quoteFetchedAt, quoteAt);
      expect(broker.snapshot('eu').items['1']!.bookFetchedAt, bookAt);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'a checked zero-buyer book still requires its genuine age to expire',
    () async {
      await saveItems([_item('1', bookAt: now, emptyBook: true)]);
      final broker = await open();
      expect(broker.snapshot('eu').items['1']!.preorderCount, 0);
      expect(
        broker.refreshReadiness(region: 'eu', bookKeys: [_key('1')]).wait,
        const Duration(minutes: 1),
      );
      expect(
        broker.refreshReadiness(region: 'eu', quoteKeys: [_key('1')]).wait,
        Duration.zero,
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'missing, old, or future-dated parts do not become a false fresh cooldown',
    () async {
      await saveItems([
        _item(
          '1',
          quoteAt: now.subtract(const Duration(hours: 4)),
          bookAt: now.subtract(const Duration(hours: 4)),
        ),
        _item('2', quoteAt: now, bookAt: now),
      ]);
      final broker = await open();
      expect(
        broker
            .refreshReadiness(
              region: 'eu',
              quoteKeys: [_key('1'), _key('9')],
              bookKeys: [_key('1'), _key('9')],
            )
            .canRefresh,
        isTrue,
      );
      now = now.subtract(const Duration(seconds: 1));
      final future = broker.refreshReadiness(
        region: 'eu',
        quoteKeys: [_key('2')],
        bookKeys: [_key('2')],
      );
      expect(future.wait, Duration.zero);
      expect(future.canRefresh, isTrue);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'whole-scope budget waits despite one free slot and survives reopening',
    () async {
      final ledger = MarketRequestWindowStore(directory: directory);
      final starts = [
        for (var i = 0; i < 97; i++)
          now
              .subtract(const Duration(seconds: 20))
              .add(Duration(milliseconds: i * 100)),
      ];
      await ledger.save(starts);
      final ledgerFile = File('${directory.path}/market-request-window.json');
      final original = await ledgerFile.readAsString();
      final broker = await open();
      final keys = [for (var id = 1000; id < 1098; id++) _key('$id')];
      expect(
        broker.refreshReadiness(region: 'eu', bookKeys: keys.take(1)).wait,
        Duration.zero,
      );
      final two = broker.refreshReadiness(region: 'eu', bookKeys: keys.take(2));
      final full = broker.refreshReadiness(region: 'eu', bookKeys: keys);
      expect(two.wait.inMilliseconds, inInclusiveRange(39020, 40020));
      expect(full.wait.inMilliseconds, inInclusiveRange(48620, 49620));
      expect(full.requestCount, 98);
      expect(full.canRefresh, isFalse);
      expect(await ledgerFile.readAsString(), original);
      await broker.close();

      now = now.add(const Duration(seconds: 20));
      final restored = await open();
      final after = restored.refreshReadiness(region: 'eu', bookKeys: keys);
      expect(after.wait.inMilliseconds, inInclusiveRange(28620, 29620));
      expect(after.canRefresh, isFalse);
      expect(await ledger.load(), starts);
      expect(transport.requests, isEmpty);
    },
  );

  test('other-region requests spend the same global allowance', () async {
    final broker = await open(limit: 2);
    final result = await broker.fetch(
      bookKeys: [
        _key('1', region: 'na'),
        _key('2', region: 'na'),
      ],
    );
    expect(result.failures, isEmpty);
    expect(
      transport.requests.every((request) => request.region == 'na'),
      isTrue,
    );
    final readiness = broker.refreshReadiness(
      region: 'eu',
      bookKeys: [_key('3')],
    );
    expect(readiness.providerPaused, isFalse);
    expect(readiness.pendingWork, isFalse);
    expect(readiness.wait.inMilliseconds, inInclusiveRange(59020, 60020));
    expect(readiness.canRefresh, isFalse);
    expect(transport.requests, hasLength(2));
  });

  test(
    'provider pauses are region-specific and a longer pause wins over receipt age',
    () async {
      await saveItems([_item('1', quoteAt: now)]);
      final pauses = MarketPauseStore(directory: directory);
      await pauses.save({
        'na': MarketRequestPause(
          reason: MarketRequestPauseReason.protected,
          retryAt: now.add(const Duration(minutes: 5)),
        ),
        'eu': MarketRequestPause(
          reason: MarketRequestPauseReason.throttled,
          retryAt: now.add(const Duration(minutes: 2)),
        ),
      });
      final broker = await open();
      final eu = broker.refreshReadiness(region: 'eu', quoteKeys: [_key('1')]);
      expect(eu.wait, const Duration(minutes: 2));
      expect(eu.providerPaused, isTrue);
      expect(eu.canRefresh, isFalse);
      final na = broker.refreshReadiness(
        region: 'na',
        bookKeys: [_key('2', region: 'na')],
      );
      expect(na.wait, const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 2));
      expect(
        broker
            .refreshReadiness(region: 'eu', quoteKeys: [_key('1')])
            .canRefresh,
        isTrue,
      );
      expect(
        broker
            .refreshReadiness(
              region: 'na',
              bookKeys: [_key('2', region: 'na')],
            )
            .providerPaused,
        isTrue,
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'expired protection permits a manual readiness check without erasing its latch',
    () async {
      final pause = MarketRequestPause(
        reason: MarketRequestPauseReason.protected,
        retryAt: now.subtract(const Duration(seconds: 1)),
      );
      await MarketPauseStore(directory: directory).save({'eu': pause});
      final broker = await open();
      final readiness = broker.refreshReadiness(
        region: 'eu',
        quoteKeys: [_key('1')],
      );
      expect(readiness.canRefresh, isTrue);
      expect(readiness.providerPaused, isFalse);
      expect(broker.pauseFor('eu')!.reason, MarketRequestPauseReason.protected);
      expect(broker.pauseFor('eu')!.retryAt, pause.retryAt);
      final automatic = await broker.fetch(quoteKeys: [_key('1')]);
      expect(automatic.failures, isNotEmpty);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'queued work signals busy then cancellation without starting transport',
    () async {
      await MarketRequestWindowStore(directory: directory).save([now]);
      final broker = await open(limit: 1);
      final activity = <bool>[];
      final subscription = broker.activityChanges.listen((_) {
        activity.add(
          broker
              .refreshReadiness(region: 'eu', bookKeys: [_key('1')])
              .pendingWork,
        );
      });
      addTearDown(subscription.cancel);
      final cancellation = MarketCancellationController();
      final loading = broker.fetch(
        bookKeys: [_key('1')],
        cancellationToken: cancellation.token,
      );
      final cancelled = expectLater(
        loading,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await _drain();
      expect(broker.diagnostics.queuedParts, 1);
      expect(
        broker
            .refreshReadiness(region: 'eu', bookKeys: [_key('1')])
            .pendingWork,
        isTrue,
      );
      expect(activity, contains(true));
      expect(transport.requests, isEmpty);
      cancellation.cancel();
      await cancelled;
      await _drain();
      expect(broker.diagnostics.queuedParts, 0);
      expect(
        broker
            .refreshReadiness(region: 'eu', bookKeys: [_key('1')])
            .pendingWork,
        isFalse,
      );
      expect(activity.last, isFalse);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'other-region in-flight work is busy and cancellation drops its queued sibling',
    () async {
      transport.hold = true;
      final broker = await open(concurrency: 1);
      final activity = <bool>[];
      final subscription = broker.activityChanges.listen((_) {
        activity.add(
          broker
              .refreshReadiness(region: 'eu', bookKeys: [_key('3')])
              .pendingWork,
        );
      });
      addTearDown(subscription.cancel);
      final cancellation = MarketCancellationController();
      final loading = broker.fetch(
        bookKeys: [
          _key('1', region: 'na'),
          _key('2', region: 'na'),
        ],
        cancellationToken: cancellation.token,
      );
      final cancelled = expectLater(
        loading,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await transport.entered.future;
      await _drain();
      final busy = broker.refreshReadiness(region: 'eu', bookKeys: [_key('3')]);
      expect(busy.pendingWork, isTrue);
      expect(busy.canRefresh, isFalse);
      expect(busy.providerPaused, isFalse);
      expect(broker.diagnostics.activeRequests, 1);
      expect(broker.diagnostics.queuedParts, 1);
      expect(activity, contains(true));
      cancellation.cancel();
      await cancelled;
      await _drain();
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.aborted, isTrue);
      expect(broker.diagnostics.activeRequests, 0);
      expect(broker.diagnostics.queuedParts, 0);
      expect(broker.diagnostics.failedRequests, 0);
      expect(
        broker.refreshReadiness(region: 'eu', bookKeys: [_key('3')]).canRefresh,
        isTrue,
      );
      expect(activity.last, isFalse);
    },
  );

  test('successful shared work emits activity when it finishes', () async {
    transport.hold = true;
    final broker = await open();
    final activity = <bool>[];
    final subscription = broker.activityChanges.listen((_) {
      activity.add(
        broker
            .refreshReadiness(region: 'eu', bookKeys: [_key('3')])
            .pendingWork,
      );
    });
    addTearDown(subscription.cancel);
    final loading = broker.fetch(bookKeys: [_key('1', region: 'na')]);
    await transport.entered.future;
    await _drain();
    expect(activity, contains(true));
    transport.release.complete();
    expect((await loading).failures, isEmpty);
    await _drain();
    expect(activity.last, isFalse);
    expect(
      broker.refreshReadiness(region: 'eu', bookKeys: [_key('3')]).canRefresh,
      isTrue,
    );
  });

  test(
    'oversized scope admits one full window instead of waiting forever',
    () async {
      await MarketRequestWindowStore(directory: directory).save([
        now.subtract(const Duration(seconds: 40)),
        now.subtract(const Duration(seconds: 20)),
      ]);
      final broker = await open(limit: 2);
      final keys = [for (var id = 1; id <= 5; id++) _key('$id')];
      final readiness = broker.refreshReadiness(region: 'eu', bookKeys: keys);
      expect(readiness.requestCount, 5);
      expect(readiness.staged, isTrue);
      expect(readiness.wait.inMilliseconds, inInclusiveRange(39020, 40020));
      expect(readiness.canRefresh, isFalse);
      await broker.close();
      now = now.add(const Duration(seconds: 41));
      final restored = await open(limit: 2);
      final ready = restored.refreshReadiness(region: 'eu', bookKeys: keys);
      expect(ready.staged, isTrue);
      expect(ready.wait, Duration.zero);
      expect(ready.canRefresh, isTrue);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'temporarily archived identities contribute neither cost nor receipt wait',
    () async {
      await saveItems([_item('6211', quoteAt: now, bookAt: now)]);
      final broker = await open();
      final archived = broker.refreshReadiness(
        region: 'eu',
        quoteKeys: [_key('6211')],
        bookKeys: [_key('6211')],
      );
      expect(archived.requestCount, 0);
      expect(archived.wait, Duration.zero);
      expect(archived.canRefresh, isTrue);
      final mixed = broker.refreshReadiness(
        region: 'eu',
        quoteKeys: [_key('6211'), _key('1')],
        bookKeys: [_key('6211'), _key('2')],
      );
      expect(mixed.requestCount, 2);
      expect(transport.requests, isEmpty);
      expect(broker.snapshot('eu').items['6211']!.bookFetchedAt, now);
    },
  );

  test(
    'readiness reads do not emit work, mutate receipts, or rewrite stored state',
    () async {
      await saveItems([_item('1', quoteAt: now, bookAt: now)]);
      await MarketRequestWindowStore(
        directory: directory,
      ).save([now.subtract(const Duration(seconds: 10))]);
      await MarketPauseStore(directory: directory).save({});
      final files = [
        for (final name in [
          'opportunity-market-cache.json',
          'market-request-window.json',
          'market-request-pauses.json',
        ])
          File('${directory.path}/$name'),
      ];
      final before = [for (final file in files) await file.readAsString()];
      final broker = await open();
      await _drain();
      var changes = 0;
      final subscription = broker.activityChanges.listen((_) => changes++);
      addTearDown(subscription.cancel);
      for (var i = 0; i < 100; i++) {
        expect(
          broker
              .refreshReadiness(
                region: 'eu',
                quoteKeys: [_key('1')],
                bookKeys: [_key('1')],
              )
              .wait,
          const Duration(minutes: 1),
        );
      }
      await _drain();
      await broker.flush();
      expect(changes, 0);
      expect(transport.requests, isEmpty);
      expect(broker.diagnostics.startedRequests, 0);
      expect(broker.diagnostics.cacheHits, 0);
      expect(broker.diagnostics.coalescedParts, 0);
      expect(broker.snapshot('eu').items['1']!.quoteFetchedAt, now);
      expect(broker.snapshot('eu').items['1']!.bookFetchedAt, now);
      expect([for (final file in files) await file.readAsString()], before);
    },
  );

  test('mixed-region scopes are rejected without dispatch', () async {
    final broker = await open();
    expect(
      () => broker.refreshReadiness(
        region: 'eu',
        quoteKeys: [_key('1', region: 'na')],
      ),
      throwsArgumentError,
    );
    expect(
      () => broker.refreshReadiness(region: 'na', bookKeys: [_key('1')]),
      throwsArgumentError,
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'readiness stays unavailable until hydration and after shutdown',
    () async {
      final broker = SharedMarketRepository(
        cacheStore: OpportunityMarketCacheStore(directory: directory),
        transport: transport,
      );
      repository = broker;
      final before = broker.refreshReadiness(
        region: 'eu',
        bookKeys: [_key('1')],
      );
      expect(before.initializing, isTrue);
      expect(before.canRefresh, isFalse);
      await broker.ready;
      expect(
        broker.refreshReadiness(region: 'eu', bookKeys: [_key('1')]).canRefresh,
        isTrue,
      );
      await broker.close();
      final after = broker.refreshReadiness(
        region: 'eu',
        bookKeys: [_key('1')],
      );
      expect(after.initializing, isTrue);
      expect(after.canRefresh, isFalse);
      expect(transport.requests, isEmpty);
    },
  );
}

SharedMarketKey _key(String id, {String region = 'eu'}) =>
    SharedMarketKey(region: region, itemId: id);

OpportunityMarketItem _item(
  String id, {
  DateTime? quoteAt,
  DateTime? bookAt,
  bool emptyBook = false,
}) => OpportunityMarketItem(
  itemId: id,
  basePrice: quoteAt == null ? null : 100,
  stock: quoteAt == null ? null : 0,
  totalTrades: quoteAt == null ? null : 10,
  quoteFetchedAt: quoteAt,
  bookFetchedAt: bookAt,
  asks: bookAt == null
      ? null
      : emptyBook
      ? const []
      : const [OpportunityMarketLevel(price: 100, quantity: 3)],
  bids: bookAt == null
      ? null
      : emptyBook
      ? const []
      : const [OpportunityMarketLevel(price: 90, quantity: 7)],
);

Future<void> _drain() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Request {
  _Request(this.region, this.book, this.ids);
  final String region;
  final bool book;
  final List<String> ids;
  bool aborted = false;
}

final class _Transport implements OpportunityMarketTransport {
  final requests = <_Request>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  bool hold = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final request = _Request(
      uri.host.split('-').first,
      uri.path.endsWith('GetBiddingInfoList'),
      '${payload['searchResult'] ?? payload['mainKey']}'.split(','),
    );
    requests.add(request);
    if (!entered.isCompleted) entered.complete();
    if (hold) {
      await Future.any<void>([
        release.future,
        if (abortTrigger != null)
          abortTrigger.then((_) {
            request.aborted = true;
            throw const MarketFetchCancelledException();
          }),
      ]);
    }
    final message = request.book
        ? '100-3-0|90-0-7'
        : payload.containsKey('searchResult')
        ? request.ids.map((id) => '$id-0-100-10').join('|')
        : '${request.ids.single}-0-0-100-0-10';
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
