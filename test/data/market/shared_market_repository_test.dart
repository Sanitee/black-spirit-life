import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_dispatch_policy.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final initial = DateTime.utc(2026, 9, 10, 12);
  late DateTime now;
  late _Transport transport;
  late SharedMarketRepository repository;
  late Directory directory;

  setUp(() async {
    now = initial;
    directory = await Directory.systemTemp.createTemp('shared-market-test-');
    transport = _Transport();
    repository = SharedMarketRepository(
      requestSpacing: Duration.zero,
      transport: transport,
      utcNow: () => now,
    );
    await repository.ready;
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'identity is canonical, region-aware and rejects unsupported subIds',
    () async {
      expect(SharedMarketKey(region: ' EU ', itemId: '00042'), _key('42'));
      expect(_key('42'), isNot(_key('42', region: 'na')));
      expect(
        () => SharedMarketKey(region: 'eu', itemId: '1.5'),
        throwsArgumentError,
      );
      await expectLater(
        repository.fetch(
          quoteKeys: [SharedMarketKey(region: 'eu', itemId: '42', subId: 1)],
        ),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'concurrent features coalesce overlapping quotes into one bulk request',
    () async {
      final events = <SharedMarketReceipt>[];
      final subscription = repository.receipts.listen(events.add);
      final first = repository.fetch(quoteKeys: [_key('1'), _key('2')]);
      final second = repository.fetch(quoteKeys: [_key('2'), _key('3')]);
      final results = await Future.wait([first, second]);
      await _turn();
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.ids.toSet(), {'1', '2', '3'});
      expect(results[0].items.keys.toSet(), {_key('1'), _key('2')});
      expect(results[1].items.keys.toSet(), {_key('2'), _key('3')});
      expect(events, hasLength(3));
      expect(events.every((receipt) => !receipt.fromCache), isTrue);
      expect(repository.diagnostics.coalescedParts, 1);
      await subscription.cancel();
    },
  );

  test(
    'same book is one request and known empty depth is zero, not unknown',
    () async {
      transport.book = '100-0-0';
      final results = await Future.wait([
        repository.fetch(bookKeys: [_key('1')]),
        repository.fetch(bookKeys: [_key('1')]),
      ]);
      expect(transport.requests, hasLength(1));
      expect(results.first.items[_key('1')]!.preorderCount, 0);
      expect(results.first.items[_key('1')]!.stock, isNull);
      expect(results.first.items[_key('1')]!.quoteFetchedAt, isNull);
    },
  );

  test(
    '100-ID batches cover 1442 summaries in 15 requests without books',
    () async {
      await repository.close();
      repository = SharedMarketRepository(
        quoteBatchSize: 100,
        requestSpacing: Duration.zero,
        transport: transport,
        utcNow: () => now,
      );
      final keys = List.generate(1442, (index) => _key('${100000 + index}'));
      final batch = await repository.fetch(quoteKeys: keys);
      expect(batch.failures, isEmpty);
      expect(batch.items.keys.toSet(), keys.toSet());
      expect(transport.requests, hasLength(15));
      expect(transport.requests.every((request) => !request.book), isTrue);
      expect(transport.requests.map((request) => request.ids.length), [
        ...List.filled(14, 100),
        42,
      ]);
      expect(
        batch.items.values.every((item) => item.bookFetchedAt == null),
        isTrue,
      );
      expect(
        batch.items.values.every((item) => item.preorderCount == null),
        isTrue,
      );
      await repository.fetch(quoteKeys: keys);
      expect(transport.requests, hasLength(15));
    },
  );

  test(
    '200-ID batches cover 1442 summaries in 8 requests without books',
    () async {
      await repository.close();
      repository = SharedMarketRepository(
        quoteBatchSize: 200,
        requestSpacing: Duration.zero,
        transport: transport,
        utcNow: () => now,
      );
      final keys = List.generate(1442, (index) => _key('${1000 + index}'));
      final receipts = <SharedMarketReceipt>[];
      final batch = await repository.fetch(
        quoteKeys: keys,
        onItem: receipts.add,
      );
      expect(batch.failures, isEmpty);
      expect(batch.items.keys.toSet(), keys.toSet());
      expect(receipts, hasLength(1442));
      expect(receipts.every((receipt) => !receipt.fromCache), isTrue);
      expect(transport.requests, hasLength(8));
      expect(transport.requests.every((request) => !request.book), isTrue);
      expect(transport.requests.map((request) => request.ids.length), [
        ...List.filled(7, 200),
        42,
      ]);
      expect(
        transport.requests.every(
          (request) =>
              request.ids.join(',').length <= sharedMarketSearchCharacterLimit,
        ),
        isTrue,
      );
      expect(
        transport.requests.expand((request) => request.ids).toSet(),
        keys.map((key) => key.itemId).toSet(),
      );
      expect(
        batch.items.values.every(
          (item) =>
              item.quoteFetchedAt == initial &&
              item.basePrice == 100 &&
              item.stock == 0 &&
              item.totalTrades == 1000 &&
              item.bookFetchedAt == null &&
              item.preorderCount == null,
        ),
        isTrue,
      );
      await repository.fetch(quoteKeys: keys);
      expect(transport.requests, hasLength(8));
    },
  );

  for (final malformed in [false, true]) {
    test(
      '200-ID batch keeps valid rows when one is ${malformed ? 'malformed' : 'missing'}',
      () async {
        await repository.close();
        if (malformed) {
          transport.malformedQuotes = {'1150'};
        } else {
          transport.omit = {'1150'};
        }
        repository = SharedMarketRepository(
          quoteBatchSize: 200,
          requestSpacing: Duration.zero,
          transport: transport,
          utcNow: () => now,
        );
        final keys = List.generate(200, (index) => _key('${1000 + index}'));
        final batch = await repository.fetch(quoteKeys: keys);
        expect(transport.requests, hasLength(1));
        expect(transport.requests.single.ids, hasLength(200));
        expect(batch.items, hasLength(199));
        expect(batch.quoteFailures, {_key('1150')});
        expect(batch.bookFailures, isEmpty);
        expect(repository.snapshot('eu').items.containsKey('1150'), isFalse);
        expect(
          batch.items.keys.toSet(),
          keys.where((key) => key.itemId != '1150').toSet(),
        );
        expect(
          batch.items.values.every(
            (item) =>
                item.quoteFetchedAt == initial &&
                item.basePrice == 100 &&
                item.bookFetchedAt == null,
          ),
          isTrue,
        );
        expect(
          repository.diagnostics.startedRequests,
          1,
          reason: 'Partial responses must not trigger split retries.',
        );
      },
    );
  }

  test('exactly 999 search characters fit but the next item splits', () async {
    await repository.close();
    repository = SharedMarketRepository(
      quoteBatchSize: 200,
      requestSpacing: Duration.zero,
      transport: transport,
      utcNow: () => now,
    );
    expect(sharedMarketSearchCharacterLimit, 999);
    final keys = List.generate(201, (index) => _key('${1000 + index}'));
    final result = await repository.fetch(quoteKeys: keys);
    expect(result.failures, isEmpty);
    expect(result.items.keys.toSet(), keys.toSet());
    expect(transport.requests.map((request) => request.ids.length), [200, 1]);
    expect(transport.requests.first.ids.join(',').length, 999);
    expect(
      transport.requests.expand((request) => request.ids),
      keys.map((key) => key.itemId),
    );
  });

  test('1000-character six-digit search splits before the last item', () async {
    await repository.close();
    repository = SharedMarketRepository(
      quoteBatchSize: 200,
      requestSpacing: Duration.zero,
      transport: transport,
      utcNow: () => now,
    );
    final keys = List.generate(143, (index) => _key('${100000 + index}'));
    expect(keys.map((key) => key.itemId).join(',').length, 1000);
    final result = await repository.fetch(quoteKeys: keys);
    expect(result.failures, isEmpty);
    expect(result.items.keys.toSet(), keys.toSet());
    expect(transport.requests.map((request) => request.ids.length), [142, 1]);
    expect(transport.requests.map((request) => request.ids.join(',').length), [
      993,
      6,
    ]);
    expect(
      transport.requests.expand((request) => request.ids),
      keys.map((key) => key.itemId),
    );
  });

  test(
    'mixed-width prioritized batches survive a coalesced caller cancellation',
    () async {
      await repository.close();
      repository = SharedMarketRepository(
        quoteBatchSize: 200,
        concurrency: 1,
        requestSpacing: Duration.zero,
        transport: transport,
        utcNow: () => now,
      );
      transport.hold = true;
      final keys = [
        for (var index = 0; index < 150; index++) _key('${100000 + index}'),
        for (var index = 0; index < 30; index++) _key('${5000 + index}'),
        for (var index = 0; index < 20; index++) _key('${900 + index}'),
      ];
      final priorities = [keys.last, keys[160], keys[149]];
      final cancel = MarketCancellationController();
      final first = repository.fetch(
        quoteKeys: keys,
        priorityKeys: () => priorities,
        cancellationToken: cancel.token,
      );
      final cancelled = expectLater(
        first,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      final retained = repository.fetch(
        quoteKeys: keys,
        priorityKeys: () => priorities,
      );
      await _turn();
      expect(transport.requests, hasLength(1));
      expect(
        transport.requests.first.ids.take(3),
        priorities.map((key) => key.itemId),
      );
      cancel.cancel();
      await cancelled;
      expect(transport.abortCount, 0);
      transport.hold = false;
      transport.releaseAll();
      final result = await retained;
      expect(result.failures, isEmpty);
      expect(result.items.keys.toSet(), keys.toSet());
      final sent = transport.requests.expand((request) => request.ids).toList();
      expect(sent, hasLength(keys.length));
      expect(sent.toSet(), keys.map((key) => key.itemId).toSet());
      expect(transport.requests, hasLength(2));
      expect(
        transport.requests.every(
          (request) =>
              request.ids.length <= 200 &&
              request.ids.join(',').length <= sharedMarketSearchCharacterLimit,
        ),
        isTrue,
      );
      expect(repository.diagnostics.queuedParts, 0);
    },
  );

  test(
    'bulk response omissions remain unknown and are not split-retried',
    () async {
      await repository.close();
      transport.omit = {'100050'};
      repository = SharedMarketRepository(
        quoteBatchSize: 100,
        requestSpacing: Duration.zero,
        transport: transport,
        utcNow: () => now,
      );
      final batch = await repository.fetch(
        quoteKeys: List.generate(100, (index) => _key('${100000 + index}')),
      );
      expect(transport.requests, hasLength(1));
      expect(batch.items, hasLength(99));
      expect(batch.quoteFailures, {_key('100050')});
      expect(repository.snapshot('eu').items.containsKey('100050'), isFalse);
    },
  );

  test('summary batch bound is independent of request concurrency', () async {
    for (final count in [0, 201]) {
      expect(
        () => SharedMarketRepository(quoteBatchSize: count),
        throwsArgumentError,
      );
    }
    expect(() => SharedMarketRepository(concurrency: 41), throwsArgumentError);
  });

  test(
    'cached replay keeps each timestamp and never rebroadcasts a new observation',
    () async {
      await repository.fetch(quoteKeys: [_key('1')]);
      now = now.add(const Duration(minutes: 1));
      await repository.fetch(bookKeys: [_key('1')]);
      final events = <SharedMarketReceipt>[];
      final subscription = repository.receipts.listen(events.add);
      final deliveries = <SharedMarketReceipt>[];
      final progress = <(int, int)>[];
      now = now.add(const Duration(hours: 1));
      final cached = await repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1')],
        onItem: deliveries.add,
        onProgress: (done, total) => progress.add((done, total)),
      );
      await _turn();
      expect(transport.requests, hasLength(2));
      expect(deliveries.every((receipt) => receipt.fromCache), isTrue);
      expect(events, isEmpty);
      expect(progress.last, (2, 2));
      expect(cached.items[_key('1')]!.quoteFetchedAt, initial);
      expect(
        cached.items[_key('1')]!.bookFetchedAt,
        initial.add(const Duration(minutes: 1)),
      );
      await subscription.cancel();
    },
  );

  test(
    'cancelling one caller does not abort another caller in the mixed bulk',
    () async {
      transport.hold = true;
      final cancel = MarketCancellationController();
      final first = repository.fetch(
        quoteKeys: [_key('1'), _key('2')],
        cancellationToken: cancel.token,
      );
      final firstCancelled = expectLater(
        first,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      final second = repository.fetch(quoteKeys: [_key('2'), _key('3')]);
      await _turn();
      expect(transport.requests.single.ids.toSet(), {'1', '2', '3'});
      cancel.cancel();
      await firstCancelled;
      expect(transport.abortCount, 0);
      transport.releaseAll();
      expect((await second).items.keys.toSet(), {_key('2'), _key('3')});
      expect(
        repository.snapshot('eu').items.keys,
        containsAll(['1', '2', '3']),
      );
    },
  );

  test(
    'last caller cancellation aborts and a later request can start cleanly',
    () async {
      transport.hold = true;
      final cancel = MarketCancellationController();
      final future = repository.fetch(
        bookKeys: [_key('1')],
        cancellationToken: cancel.token,
      );
      final cancelled = expectLater(
        future,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await _turn();
      cancel.cancel();
      await cancelled;
      await _turn();
      expect(transport.abortCount, 1);
      transport.hold = false;
      final next = await repository.fetch(bookKeys: [_key('1')]);
      expect(next.bookFailures, isEmpty);
      expect(transport.requests, hasLength(2));
    },
  );

  test('global cap covers both regions, quote batches and books', () async {
    await repository.close();
    repository = SharedMarketRepository(
      requestSpacing: Duration.zero,
      transport: transport,
      concurrency: 4,
      utcNow: () => now,
    );
    transport.delay = const Duration(milliseconds: 2);
    final keys = [
      for (final region in ['eu', 'na'])
        for (var id = 1; id <= 20; id++) _key('$id', region: region),
    ];
    final result = await repository.fetch(quoteKeys: keys, bookKeys: keys);
    expect(result.failures, isEmpty);
    expect(transport.peak, 4);
    expect(repository.diagnostics.peakActiveRequests, 4);
    expect(transport.requests.where((request) => !request.book), hasLength(2));
    expect(transport.requests.where((request) => request.book), hasLength(40));
  });

  test(
    'force bypasses cache but concurrent forced refreshes still deduplicate',
    () async {
      await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
      now = now.add(const Duration(minutes: 1));
      final receipts = <SharedMarketReceipt>[];
      await Future.wait([
        repository.fetch(
          quoteKeys: [_key('1')],
          forceRefresh: true,
          onItem: receipts.add,
        ),
        repository.fetch(quoteKeys: [_key('1')], forceRefresh: true),
      ]);
      expect(transport.requests, hasLength(3));
      expect(receipts.single.fromCache, isFalse);
      expect(repository.snapshot('eu').items['1']!.quoteFetchedAt, now);
      expect(repository.snapshot('eu').items['1']!.bookFetchedAt, initial);
    },
  );

  test(
    'missing bulk rows fail only their quote, never become known zero',
    () async {
      transport.omit = {'2'};
      final result = await repository.fetch(
        quoteKeys: [_key('1'), _key('2')],
        bookKeys: [_key('2')],
      );
      expect(result.quoteFailures, {_key('2')});
      expect(result.bookFailures, isEmpty);
      expect(result.items[_key('2')]!.basePrice, isNull);
      expect(result.items[_key('2')]!.stock, isNull);
      expect(result.items[_key('2')]!.preorderCount, 7);
    },
  );

  test(
    'quote failure never stamps cached data or its successful book fresh',
    () async {
      await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
      now = now.add(const Duration(hours: 4));
      transport.status = (request) => request.book ? 200 : 503;
      final result = await repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1')],
      );
      final cached = repository.snapshot('eu').items['1']!;
      expect(result.quoteFailures, {_key('1')});
      expect(cached.quoteFetchedAt, initial);
      expect(cached.quoteIsFresh(now, const Duration(hours: 3)), isFalse);
      expect(cached.bookFetchedAt, now);
    },
  );

  for (final asDate in [false, true]) {
    test(
      '429 pauses all same-origin callers and honors ${asDate ? 'HTTP-date' : 'seconds'} Retry-After',
      () async {
        await repository.close();
        repository = SharedMarketRepository(
          requestSpacing: Duration.zero,
          transport: transport,
          concurrency: 1,
          utcNow: () => now,
        );
        transport.headers = {
          'Retry-After': asDate
              ? HttpDate.format(now.add(const Duration(minutes: 2)))
              : '120',
        };
        transport.status = (request) => request.region == 'eu' ? 429 : 200;
        var notified = 0;
        final eu = repository.fetch(
          bookKeys: [_key('1'), _key('2')],
          onRateLimited: () => notified++,
        );
        final na = repository.fetch(bookKeys: [_key('1', region: 'na')]);
        final euResult = await eu;
        expect(euResult.rateLimited, isTrue);
        expect(euResult.bookFailures, {_key('1'), _key('2')});
        expect(notified, 1);
        expect((await na).failures, isEmpty);
        expect(transport.requests, hasLength(2));
        transport.status = null;
        now = now.add(const Duration(seconds: 119));
        expect(
          (await repository.fetch(
            bookKeys: [_key('1')],
            forceRefresh: true,
          )).rateLimited,
          isTrue,
        );
        expect(transport.requests, hasLength(2));
        now = now.add(const Duration(seconds: 2));
        expect(
          (await repository.fetch(bookKeys: [_key('1')])).failures,
          isEmpty,
        );
        expect(transport.requests, hasLength(3));
      },
    );
  }

  test(
    'automatic failure cooldown expires after 30 seconds without a receipt',
    () async {
      transport.book = 'malformed';
      final events = <SharedMarketReceipt>[];
      final subscription = repository.receipts.listen(events.add);
      final first = await repository.fetch(bookKeys: [_key('1')]);
      expect(first.bookFailures, {_key('1')});
      now = now.add(const Duration(seconds: 29));
      final paused = await repository.fetch(bookKeys: [_key('1')]);
      expect(paused.failures, first.failures);
      expect(transport.requests, hasLength(1));
      expect(repository.snapshot('eu').items, isEmpty);
      expect(events, isEmpty);
      transport.book = '100-0-7';
      now = now.add(const Duration(seconds: 1));
      final next = await repository.fetch(bookKeys: [_key('1')]);
      expect(next.failures, isEmpty);
      expect(transport.requests, hasLength(2));
      expect(next.items[_key('1')]!.bookFetchedAt, now);
      await subscription.cancel();
    },
  );

  test('failure cooldown is independent by part and region', () async {
    transport.status = (request) =>
        request.region == 'eu' && !request.book ? 503 : 200;
    await repository.fetch(quoteKeys: [_key('1')]);
    final next = await repository.fetch(
      quoteKeys: [
        _key('1'),
        _key('1', region: 'na'),
      ],
      bookKeys: [_key('1')],
    );
    expect(transport.requests, hasLength(3));
    expect(next.quoteFailures, {_key('1')});
    expect(next.bookFailures, isEmpty);
    expect(next.items[_key('1')]!.basePrice, isNull);
    expect(next.items[_key('1')]!.bookFetchedAt, now);
    expect(next.items[_key('1', region: 'na')]!.basePrice, 100);
  });

  test(
    'manual refresh bypasses failure cooldown and success clears it',
    () async {
      transport.status = (_) => 503;
      await repository.fetch(quoteKeys: [_key('1')]);
      transport.status = null;
      now = now.add(const Duration(seconds: 1));
      final forced = await repository.fetch(
        quoteKeys: [_key('1')],
        forceRefresh: true,
      );
      expect(forced.failures, isEmpty);
      expect(transport.requests, hasLength(2));
      // Expire only the successful receipt, still within the old failure period.
      now = now.add(const Duration(seconds: 1));
      final automatic = await repository.fetch(
        quoteKeys: [_key('1')],
        maxAge: Duration.zero,
      );
      expect(automatic.failures, isEmpty);
      expect(transport.requests, hasLength(3));
    },
  );

  test(
    'automatic caller joins a forced in-flight retry despite old failure',
    () async {
      transport.status = (_) => 503;
      await repository.fetch(bookKeys: [_key('1')]);
      transport.status = null;
      transport.hold = true;
      final forced = repository.fetch(
        bookKeys: [_key('1')],
        forceRefresh: true,
      );
      await _turn();
      final automatic = repository.fetch(bookKeys: [_key('1')]);
      await _turn();
      expect(transport.requests, hasLength(2));
      transport.releaseAll();
      for (final result in await Future.wait([forced, automatic])) {
        expect(result.failures, isEmpty);
      }
    },
  );

  test('failure cooldown is not written to the three-hour raw cache', () async {
    await repository.close();
    final store = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => now,
    );
    repository = SharedMarketRepository(
      requestSpacing: Duration.zero,
      cacheStore: store,
      transport: transport,
      utcNow: () => now,
    );
    transport.book = 'malformed';
    await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
    await repository.flush();
    expect((await store.load())['eu']!['1']!.bookFetchedAt, isNull);
    await repository.close();
    transport = _Transport();
    repository = SharedMarketRepository(
      requestSpacing: Duration.zero,
      cacheStore: store,
      transport: transport,
      utcNow: () => now,
    );
    final next = await repository.fetch(bookKeys: [_key('1')]);
    expect(next.failures, isEmpty);
    expect(transport.requests, hasLength(1));
  });

  test(
    'three isolated server failures do not collapse the shared pool',
    () async {
      transport.status = (request) =>
          int.parse(request.ids.single) <= 3 ? 503 : 200;
      final result = await repository.fetch(
        bookKeys: [for (var id = 1; id <= 100; id++) _key('$id')],
      );
      expect(result.bookFailures, hasLength(3));
      expect(repository.diagnostics.effectiveConcurrencyByRegion['eu'], 20);
      expect(repository.diagnostics.startedRequests, 100);
    },
  );

  test(
    'sustained congestion reduces once per window and healthy service recovers',
    () {
      final policy = MarketDispatchPolicy(maximumConcurrency: 20);
      for (var i = 0; i < 20; i++) {
        policy.record(now, transientFailure: i < 6);
      }
      expect(policy.effectiveConcurrency, 10);
      for (var i = 0; i < 19; i++) {
        policy.record(now, transientFailure: true);
      }
      expect(policy.effectiveConcurrency, 10);
      now = now.add(const Duration(seconds: 11));
      for (var i = 0; i < 32; i++) {
        policy.record(now, transientFailure: false);
      }
      expect(policy.effectiveConcurrency, 14);
      for (var recovery = 0; recovery < 3; recovery++) {
        now = now.add(const Duration(seconds: 4));
        for (var i = 0; i < 32; i++) {
          policy.record(now, transientFailure: false);
        }
      }
      expect(policy.effectiveConcurrency, 20);
    },
  );

  test('timeout aborts its request and leaves other callers usable', () async {
    await repository.close();
    repository = SharedMarketRepository(
      requestSpacing: Duration.zero,
      transport: transport,
      requestTimeout: const Duration(milliseconds: 10),
      utcNow: () => now,
    );
    transport.hold = true;
    final result = await repository.fetch(bookKeys: [_key('1')]);
    expect(result.bookFailures, {_key('1')});
    expect(transport.abortCount, 1);
    transport.hold = false;
    expect((await repository.fetch(bookKeys: [_key('2')])).failures, isEmpty);
  });

  test(
    'one broken receipt callback does not poison the other subscriber',
    () async {
      final broken = repository.fetch(
        quoteKeys: [_key('1')],
        onItem: (_) => throw StateError('Synthetic callback failure'),
      );
      final failure = expectLater(broken, throwsStateError);
      final healthy = repository.fetch(quoteKeys: [_key('1')]);
      await failure;
      expect((await healthy).failures, isEmpty);
      expect(repository.snapshot('eu').items['1']!.basePrice, 100);
    },
  );

  test(
    'old three-hour cache hydrates and only an expired part is fetched',
    () async {
      await repository.close();
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
      );
      await store.save({
        'eu': {'1': _item(initial, initial.subtract(const Duration(hours: 4)))},
      });
      repository = SharedMarketRepository(
        requestSpacing: Duration.zero,
        cacheStore: store,
        transport: transport,
        utcNow: () => now,
      );
      await repository.ready;
      final result = await repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1')],
      );
      expect(transport.requests.single.book, isTrue);
      expect(result.items[_key('1')]!.quoteFetchedAt, initial);
      await repository.flush();
      final persisted = await store.load();
      expect(persisted['eu']!['1']!.bookFetchedAt, initial);
      await repository.close();
      transport = _Transport();
      repository = SharedMarketRepository(
        requestSpacing: Duration.zero,
        cacheStore: store,
        transport: transport,
        utcNow: () => now,
      );
      await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'future receipt is discarded on hydration, not allowed to become valid later',
    () async {
      await repository.close();
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
      );
      await store.save({
        'eu': {'1': _item(now.add(const Duration(hours: 1)), now)},
      });
      repository = SharedMarketRepository(
        requestSpacing: Duration.zero,
        cacheStore: store,
        transport: transport,
        utcNow: () => now,
      );
      await repository.ready;
      expect(repository.snapshot('eu').items['1']!.quoteFetchedAt, isNull);
      now = now.add(const Duration(hours: 2));
      await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.book, isFalse);
    },
  );

  test(
    'pending slow cache write does not stall HTTP and concurrent flushes retain newer data',
    () async {
      await repository.close();
      final committer = _HeldCommitter();
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
        committer: committer,
      );
      repository = SharedMarketRepository(
        requestSpacing: Duration.zero,
        cacheStore: store,
        transport: transport,
        utcNow: () => now,
      );
      await repository.fetch(quoteKeys: [_key('1')]);
      final firstFlush = repository.flush();
      await committer.entered.future;
      await repository.fetch(quoteKeys: [_key('2')]);
      expect(repository.snapshot('eu').items.keys, containsAll(['1', '2']));
      final secondFlush = repository.flush();
      committer.release.complete();
      await Future.wait([firstFlush, secondFlush]);
      expect((await store.load())['eu']!.keys, containsAll(['1', '2']));
      expect(committer.maximumActive, 1);
    },
  );

  test(
    'flush surfaces cache failure but close stays safe and preserves the error',
    () async {
      await repository.close();
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
        committer: const _FailCommitter(),
      );
      repository = SharedMarketRepository(
        requestSpacing: Duration.zero,
        cacheStore: store,
        transport: transport,
        utcNow: () => now,
      );
      await repository.fetch(quoteKeys: [_key('1')]);
      await expectLater(
        repository.flush(),
        throwsA(isA<FileSystemException>()),
      );
      await repository.close();
      expect(repository.persistenceError, isA<FileSystemException>());
      expect(transport.closed, isTrue);
    },
  );

  test(
    'close cancels owned requests, closes client once and refuses further work',
    () async {
      transport.hold = true;
      final future = repository.fetch(bookKeys: [_key('1')]);
      final cancelled = expectLater(
        future,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await _turn();
      await Future.wait([repository.close(), repository.dispose()]);
      await cancelled;
      expect(transport.closeCount, 1);
      await expectLater(
        repository.fetch(quoteKeys: [_key('1')]),
        throwsStateError,
      );
    },
  );
}

SharedMarketKey _key(String id, {String region = 'eu'}) =>
    SharedMarketKey(region: region, itemId: id);
Future<void> _turn() => Future<void>.delayed(Duration.zero);
OpportunityMarketItem _item(DateTime quote, DateTime book) =>
    OpportunityMarketItem(
      itemId: '1',
      basePrice: 100,
      stock: 0,
      quoteFetchedAt: quote,
      asks: const [],
      bids: const [OpportunityMarketLevel(price: 100, quantity: 7)],
      bookFetchedAt: book,
    );

class _Request {
  _Request(this.region, this.book, this.ids);
  final String region;
  final bool book;
  final List<String> ids;
  final done = Completer<void>();
}

class _Transport implements OpportunityMarketTransport {
  final requests = <_Request>[];
  bool hold = false, closed = false;
  int active = 0, peak = 0, abortCount = 0, closeCount = 0;
  Duration delay = Duration.zero;
  int Function(_Request)? status;
  Set<String> omit = {};
  Set<String> malformedQuotes = {};
  String book = '100-3-0|90-0-7';
  Map<String, String> headers = {};
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    final ids = parsed.containsKey('searchResult')
        ? (parsed['searchResult'] as String).split(',')
        : ['${parsed['mainKey']}'];
    final request = _Request(
      uri.host.startsWith('eu-') ? 'eu' : 'na',
      uri.path.endsWith('GetBiddingInfoList'),
      ids,
    );
    requests.add(request);
    active++;
    if (active > peak) peak = active;
    if (hold && abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          if (!request.done.isCompleted) {
            abortCount++;
            request.done.completeError(StateError('Aborted'));
          }
        }),
      );
    }
    try {
      if (hold) await request.done.future;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final result = request.book
          ? book
          : parsed.containsKey('searchResult')
          ? ids
                .where((id) => !omit.contains(id))
                .map(
                  (id) => malformedQuotes.contains(id)
                      ? '$id-0-invalid-1000'
                      : '$id-0-100-1000',
                )
                .join('|')
          : omit.contains(ids.single)
          ? ''
          : '${ids.single}-0-0-100-0-1000';
      return OpportunityHttpResponse(
        statusCode: status?.call(request) ?? 200,
        bytes: Uint8List.fromList(
          utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': result})),
        ),
        headers: this.headers,
      );
    } finally {
      active--;
    }
  }

  void releaseAll() {
    for (final request in requests) {
      if (!request.done.isCompleted) request.done.complete();
    }
  }

  @override
  void close() {
    closed = true;
    closeCount++;
  }
}

class _HeldCommitter implements AtomicFileCommitter {
  final entered = Completer<void>();
  final release = Completer<void>();
  int active = 0, maximumActive = 0;
  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    active++;
    if (active > maximumActive) maximumActive = active;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await stagedFile.rename(targetFile.path);
    active--;
  }
}

class _FailCommitter implements AtomicFileCommitter {
  const _FailCommitter();
  @override
  Future<void> replace(File stagedFile, File targetFile) async =>
      throw const FileSystemException('Synthetic write failure');
}
