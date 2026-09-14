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

// Entirely synthetic responses: this suite never creates an HTTP client.
const _protectedHtml =
    '<html><body><iframe src="/_Incapsula_Resource?fixture">'
    'Request unsuccessful. Incapsula incident ID: TEST'
    '</iframe></body></html>';

void main() {
  final initial = DateTime.utc(2026, 9, 10, 12);

  test('application factory fixes the shared production policy', () async {
    final directory = await _temporaryDirectory();
    final cache = OpportunityMarketCacheStore(directory: directory);
    final pauses = MarketPauseStore(directory: directory);
    final transport = _Transport();
    final repository = SharedMarketRepository.application(
      cacheStore: cache,
      pauseStore: pauses,
      transport: transport,
      utcNow: () => initial,
    );
    addTearDown(repository.close);
    await repository.ready;

    expect(repository.cacheStore, same(cache));
    expect(repository.pauseStore, same(pauses));
    expect(repository.concurrency, 20);
    expect(repository.primeSession, isTrue);
    expect(repository.quoteBatchSize, 200);
    expect(repository.requestSpacing, const Duration(milliseconds: 40));
    expect(
      repository.orderBookRequestSpacing,
      const Duration(milliseconds: 40),
    );
    expect(repository.requestWindowLimit, 98);
    expect(
      repository.requestWindowDuration,
      const Duration(seconds: 60, milliseconds: 20),
    );
    expect(repository.recoveryRequestSpacing, const Duration(seconds: 1));
    expect(repository.requestTimeout, const Duration(seconds: 6));
    expect(repository.cacheMaxAge, const Duration(minutes: 5));
    expect(repository.minimumQuoteRefreshAge, const Duration(minutes: 1));
    expect(repository.minimumBookRefreshAge, const Duration(minutes: 1));
    expect(transport.requests, isEmpty);
  });

  test('application request budget keeps a 20 ms guard beyond 60 seconds', () {
    final repository = _windowedRepository(transport: _Transport());
    addTearDown(repository.close);
    var elapsed = Duration.zero;
    final budget = MarketRequestWindow(
      limit: repository.requestWindowLimit!,
      window: repository.requestWindowDuration,
      elapsed: () => elapsed,
    );
    for (var i = 0; i < 98; i++) {
      budget.started();
    }
    expect(budget.started, throwsStateError);

    elapsed = const Duration(seconds: 60);
    expect(budget.remainingDelay, const Duration(milliseconds: 20));
    expect(budget.started, throwsStateError);
    elapsed = const Duration(seconds: 60, milliseconds: 19);
    expect(budget.remainingDelay, const Duration(milliseconds: 1));
    expect(budget.started, throwsStateError);
    elapsed = const Duration(seconds: 60, milliseconds: 20);
    expect(budget.remainingDelay, Duration.zero);
    budget.started();
    expect(budget.snapshot(), hasLength(1));
  });

  test('millisecond-rounded restored ledger retains the boundary margin', () {
    final repository = _windowedRepository(transport: _Transport());
    addTearDown(repository.close);
    final firstAt = initial.add(const Duration(microseconds: 123456));
    var now = firstAt;
    var elapsed = Duration.zero;
    final original = MarketRequestWindow(
      limit: repository.requestWindowLimit!,
      window: repository.requestWindowDuration,
      utcNow: () => now,
      elapsed: () => elapsed,
    );
    for (var i = 0; i < 98; i++) {
      original.started();
    }
    elapsed = const Duration(seconds: 5);
    now = firstAt.add(elapsed);
    // Match the persisted ledger's millisecond precision, which can move an
    // entry backwards by less than 1 ms when its original clock has microseconds.
    final saved = original.snapshot().map(
      (at) => DateTime.fromMillisecondsSinceEpoch(
        at.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
    var restoredElapsed = Duration.zero;
    final restored = MarketRequestWindow(
      limit: repository.requestWindowLimit!,
      window: repository.requestWindowDuration,
      utcNow: () => now,
      elapsed: () => restoredElapsed,
    )..restore(saved);

    restoredElapsed = const Duration(seconds: 55);
    // It is now exactly 60 real seconds after the original starts. The guard
    // still has 19.544 ms, despite the 456 microseconds lost to persistence.
    expect(restored.remainingDelay, const Duration(microseconds: 19544));
    expect(restored.started, throwsStateError);
    restoredElapsed = const Duration(seconds: 55, milliseconds: 19);
    expect(restored.remainingDelay, const Duration(microseconds: 544));
    expect(restored.started, throwsStateError);
    restoredElapsed = const Duration(seconds: 55, milliseconds: 20);
    expect(restored.remainingDelay, Duration.zero);
    restored.started();
    expect(restored.snapshot(), hasLength(1));
  });

  test('eight fresh books do not retain the old 250 ms launch delay', () async {
    final transport = _Transport();
    final repository = SharedMarketRepository.application(transport: transport);
    addTearDown(repository.close);
    final keys = [for (var id = 100001; id <= 100008; id++) _key(id)];

    final result = await repository.fetch(bookKeys: keys, forceRefresh: true);

    expect(result.failures, isEmpty);
    expect(result.items.keys.toSet(), keys.toSet());
    expect(transport.requests, hasLength(8));
    expect(transport.requests.every((request) => request.book), isTrue);
    expect(
      result.items.values.every((item) => item.preorderCount == 7),
      isTrue,
    );
    expect(
      result.items.values.every((item) => item.quoteFetchedAt == null),
      isTrue,
    );
    for (var i = 1; i < transport.requests.length; i++) {
      expect(
        transport.requests[i].startedMs - transport.requests[i - 1].startedMs,
        greaterThanOrEqualTo(35),
        reason: 'Workers must still share a paced start gate, not burst.',
      );
    }
    // 40 ms x seven gaps is normally about 280 ms. Allow ample runner jitter,
    // while excluding the old policy's unavoidable minimum of 1,750 ms.
    expect(
      transport.requests.last.startedMs - transport.requests.first.startedMs,
      lessThan(1500),
    );
  });

  test(
    'forced callers deduplicate and cached replay preserves both dates',
    () async {
      var now = initial;
      final transport = _Transport();
      final repository = SharedMarketRepository.application(
        transport: transport,
        utcNow: () => now,
      );
      addTearDown(repository.close);
      final key = _key(100001);
      await repository.fetch(quoteKeys: [key]);
      now = initial.add(const Duration(minutes: 1));
      await repository.fetch(bookKeys: [key]);

      now = initial.add(const Duration(minutes: 2));
      final held = Completer<OpportunityHttpResponse>();
      final entered = Completer<void>();
      transport.answer = (request) {
        if (!entered.isCompleted) entered.complete();
        return held.future;
      };
      final first = repository.fetch(bookKeys: [key], forceRefresh: true);
      await entered.future;
      final second = repository.fetch(bookKeys: [key], forceRefresh: true);
      await _turn();
      expect(transport.requests, hasLength(3));
      held.complete(_valid(transport.requests.last));
      for (final result in await Future.wait([first, second])) {
        expect(result.failures, isEmpty);
        expect(result.items[key]!.bookFetchedAt, now);
      }
      expect(repository.diagnostics.coalescedParts, 1);

      final events = <SharedMarketReceipt>[];
      final deliveries = <SharedMarketReceipt>[];
      final subscription = repository.receipts.listen(events.add);
      addTearDown(subscription.cancel);
      now = initial.add(const Duration(minutes: 5));
      final cached = await repository.fetch(
        quoteKeys: [key],
        bookKeys: [key],
        onItem: deliveries.add,
      );
      await _turn();
      expect(transport.requests, hasLength(3));
      expect(deliveries, hasLength(2));
      expect(deliveries.every((receipt) => receipt.fromCache), isTrue);
      expect(events, isEmpty);
      expect(cached.items[key]!.quoteFetchedAt, initial);
      expect(
        cached.items[key]!.bookFetchedAt,
        initial.add(const Duration(minutes: 2)),
      );
    },
  );

  for (final failure in [
    (
      label: '429 Retry-After',
      status: 429,
      body: '{"resultCode":1,"resultMsg":"busy"}',
      headers: <String, String>{'Retry-After': '120'},
      seconds: 120,
      reason: MarketRequestPauseReason.throttled,
    ),
    (
      label: 'protected HTML',
      status: 200,
      body: _protectedHtml,
      headers: <String, String>{'Content-Type': 'text/html'},
      seconds: 60,
      reason: MarketRequestPauseReason.protected,
    ),
    (
      label: '503 Retry-After',
      status: 503,
      body: '{"resultCode":1,"resultMsg":"unavailable"}',
      headers: <String, String>{'Retry-After': '90'},
      seconds: 90,
      reason: MarketRequestPauseReason.serverUnavailable,
    ),
  ]) {
    test(
      '${failure.label} stops the application queue and rejects late data',
      () async {
        var now = initial;
        final transport = _Transport();
        final repository = SharedMarketRepository.application(
          transport: transport,
          utcNow: () => now,
        );
        addTearDown(repository.close);
        final retained = _key(100099);
        await repository.fetch(quoteKeys: [retained]);
        final first = Completer<OpportunityHttpResponse>();
        final late = Completer<OpportunityHttpResponse>();
        final bothStarted = Completer<void>();
        addTearDown(() {
          if (!first.isCompleted) {
            first.complete(_valid(transport.requests.last));
          }
          if (!late.isCompleted) late.complete(_valid(transport.requests.last));
        });
        transport.answer = (request) {
          if (request.ids.single == '100001') return first.future;
          if (request.ids.single == '100002') {
            bothStarted.complete();
            return late.future;
          }
          return Future.value(_valid(request));
        };
        final keys = [for (var id = 100001; id <= 100008; id++) _key(id)];
        var notices = 0;
        final loading = repository.fetch(
          bookKeys: keys,
          forceRefresh: true,
          onRateLimited: () => notices++,
        );
        await bothStarted.future;
        first.complete(
          OpportunityHttpResponse(
            statusCode: failure.status,
            bytes: _bytes(failure.body),
            headers: failure.headers,
          ),
        );
        final result = await loading;
        await _turn();

        expect(result.rateLimited, isTrue);
        expect(result.bookFailures, keys.toSet());
        expect(result.failures.values.toSet(), {'Market busy'});
        expect(result.pause!.reason, failure.reason);
        expect(
          result.pause!.retryAt,
          initial.add(Duration(seconds: failure.seconds)),
        );
        expect(notices, 1);
        expect(transport.requests, hasLength(3));
        expect(transport.aborted, contains('eu/book/100002'));
        expect(
          repository.snapshot('eu').items[retained.itemId]!.quoteFetchedAt,
          initial,
        );

        late.complete(_valid(transport.requests.last));
        await _turn();
        expect(repository.snapshot('eu').items.keys.toSet(), {retained.itemId});
        now = initial.add(Duration(seconds: failure.seconds - 1));
        final blocked = await repository.fetch(
          bookKeys: keys,
          forceRefresh: true,
          userInitiated: true,
        );
        expect(blocked.rateLimited, isTrue);
        expect(transport.requests, hasLength(3));
        expect(repository.snapshot('eu').items.keys.toSet(), {retained.itemId});
      },
    );
  }

  test(
    'one-second recovery pacing survives faster healthy book starts',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository.application(
        transport: transport,
      );
      addTearDown(repository.close);
      final first = repository.fetch(
        bookKeys: [_key(100001), _key(100002)],
        recovery: true,
        forceRefresh: true,
      );
      final joining = repository.fetch(bookKeys: [_key(100001)]);
      for (final result in await Future.wait([first, joining])) {
        expect(result.failures, isEmpty);
      }
      await repository.fetch(bookKeys: [_key(100003)]);

      expect(transport.requests, hasLength(3));
      expect(repository.diagnostics.coalescedParts, 1);
      for (var i = 1; i < transport.requests.length; i++) {
        expect(
          transport.requests[i].startedMs - transport.requests[i - 1].startedMs,
          greaterThanOrEqualTo(950),
          reason:
              'Recovery applies to the shared gate and its next transition.',
        );
      }
    },
  );

  test(
    'application 98-start budget survives restart while cached parts spend no slots',
    () async {
      final directory = await _temporaryDirectory();
      final cache = OpportunityMarketCacheStore(directory: directory);
      final ledger = MarketRequestWindowStore(directory: directory);
      final transport = _Transport();
      final repository = _windowedRepository(
        cacheStore: cache,
        transport: transport,
      );
      addTearDown(repository.close);
      final quotes = [for (var id = 100001; id <= 100401; id++) _key(id)];
      final books = [for (var id = 200001; id <= 200095; id++) _key(id)];
      final loaded = await repository.fetch(quoteKeys: quotes, bookKeys: books);
      expect(loaded.failures, isEmpty);
      expect(loaded.items, hasLength(496));
      expect(
        transport.requests
            .where((request) => !request.book)
            .map((request) => request.ids.length),
        [142, 142, 117],
      );
      expect(
        transport.requests.where((request) => request.book),
        hasLength(95),
      );
      expect(transport.requests, hasLength(98));

      final cached = await repository.fetch(quoteKeys: quotes, bookKeys: books);
      expect(cached.failures, isEmpty);
      expect(repository.diagnostics.cacheHits, 496);
      expect(transport.requests, hasLength(98));
      await _expectQueuedWithoutStarting(repository, transport);
      await repository.flush();
      final saved = await ledger.load();
      expect(saved, hasLength(98));
      await repository.close();

      final nextTransport = _Transport();
      final restored = _windowedRepository(
        cacheStore: cache,
        transport: nextTransport,
      );
      addTearDown(restored.close);
      final replayed = await restored.fetch(quoteKeys: quotes, bookKeys: books);
      expect(replayed.failures, isEmpty);
      expect(nextTransport.requests, isEmpty);
      expect(
        replayed.items[_key(100001)]!.quoteFetchedAt!.millisecondsSinceEpoch,
        loaded.items[_key(100001)]!.quoteFetchedAt!.millisecondsSinceEpoch,
      );
      expect(
        replayed.items[_key(200001)]!.bookFetchedAt!.millisecondsSinceEpoch,
        loaded.items[_key(200001)]!.bookFetchedAt!.millisecondsSinceEpoch,
      );
      await _expectQueuedWithoutStarting(restored, nextTransport);
      await restored.flush();
      final resaved = await ledger.load();
      expect(resaved, hasLength(98));
      // Persistence rounds to milliseconds; reopening must not reset any entry
      // to the restart time or erase the combined quote/book budget.
      for (var i = 0; i < saved.length; i++) {
        expect(
          resaved[i].difference(saved[i]).inMilliseconds.abs(),
          lessThan(20),
        );
      }
    },
  );

  test('a healthy check within the allowance keeps fast dispatch', () async {
    final transport = _Transport();
    final repository = SharedMarketRepository.application(transport: transport);
    addTearDown(repository.close);
    final keys = [for (var id = 100001; id <= 100098; id++) _key(id)];
    final loaded = await repository.fetch(bookKeys: keys, forceRefresh: true);
    expect(loaded.failures, isEmpty);
    expect(loaded.items.keys.toSet(), keys.toSet());
    expect(transport.requests, hasLength(98));
    expect(
      transport.requests.last.startedMs - transport.requests.first.startedMs,
      lessThan(15000),
    );
    for (var i = 1; i < transport.requests.length; i++) {
      expect(
        transport.requests[i].startedMs - transport.requests[i - 1].startedMs,
        greaterThanOrEqualTo(35),
      );
    }
  });

  test(
    'first healthy response establishes the session before parallel work',
    () async {
      final first = Completer<OpportunityHttpResponse>();
      final entered = Completer<void>();
      final transport = _Transport();
      transport.answer = (request) {
        if (request.ids.single == '100001') {
          entered.complete();
          return first.future;
        }
        return Future.value(_valid(request));
      };
      final repository = SharedMarketRepository.application(
        transport: transport,
      );
      addTearDown(repository.close);
      final loading = repository.fetch(
        bookKeys: [_key(100001), _key(100002), _key(100003)],
      );
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(transport.requests, hasLength(1));
      first.complete(_valid(transport.requests.single));
      final batch = await loading;
      expect(batch.failures, isEmpty);
      expect(transport.requests, hasLength(3));
    },
  );

  test(
    'Stop cancels a queued application scan without later paced launches',
    () async {
      final transport = _Transport();
      final held = Completer<OpportunityHttpResponse>();
      final entered = Completer<void>();
      transport.answer = (request) {
        if (!entered.isCompleted) entered.complete();
        return held.future;
      };
      final repository = SharedMarketRepository.application(
        transport: transport,
      );
      addTearDown(repository.close);
      final cancellation = MarketCancellationController();
      final pending = repository.fetch(
        bookKeys: [for (var id = 100001; id <= 100008; id++) _key(id)],
        cancellationToken: cancellation.token,
      );
      final cancelled = expectLater(
        pending,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await entered.future;
      cancellation.cancel();
      await cancelled;
      held.complete(_valid(transport.requests.single));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(transport.requests, hasLength(1));
      expect(transport.aborted, contains('eu/book/100001'));
      expect(repository.snapshot('eu').items, isEmpty);
      expect(repository.diagnostics.queuedParts, 0);
    },
  );
}

Future<Directory> _temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'application-market-policy-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

SharedMarketRepository _windowedRepository({
  OpportunityMarketCacheStore? cacheStore,
  OpportunityMarketTransport? transport,
}) => SharedMarketRepository.application(
  cacheStore: cacheStore,
  transport: transport,
);

Future<void> _expectQueuedWithoutStarting(
  SharedMarketRepository repository,
  _Transport transport,
) async {
  final count = transport.requests.length;
  final cancellation = MarketCancellationController();
  final pending = repository.fetch(
    quoteKeys: [_key(300001, region: 'na')],
    bookKeys: [_key(300002)],
    forceRefresh: true,
    cancellationToken: cancellation.token,
  );
  final cancelled = expectLater(
    pending,
    throwsA(isA<MarketFetchCancelledException>()),
  );
  await Future<void>.delayed(const Duration(milliseconds: 120));
  expect(transport.requests, hasLength(count));
  expect(repository.diagnostics.queuedParts, 2);
  cancellation.cancel();
  await cancelled;
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);
SharedMarketKey _key(int id, {String region = 'eu'}) =>
    SharedMarketKey(region: region, itemId: '$id');
Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

final class _Request {
  const _Request(this.region, this.book, this.ids, this.startedMs);
  final String region;
  final bool book;
  final List<String> ids;
  final int startedMs;
  String get tag => '$region/${book ? 'book' : 'quote'}/${ids.join(',')}';
}

OpportunityHttpResponse _valid(_Request request) {
  final message = request.book
      ? '100-3-0|90-0-7'
      : request.ids.length > 1
      ? request.ids.map((id) => '$id-10-100-1000').join('|')
      : '${request.ids.single}-0-0-100-10-1000';
  return OpportunityHttpResponse(
    statusCode: 200,
    bytes: _bytes(jsonEncode({'resultCode': 0, 'resultMsg': message})),
  );
}

final class _Transport implements OpportunityMarketTransport {
  final _watch = Stopwatch()..start();
  final requests = <_Request>[];
  final aborted = <String>[];
  Future<OpportunityHttpResponse> Function(_Request)? answer;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final request = _Request(
      uri.host.startsWith('eu-') ? 'eu' : 'na',
      uri.path.endsWith('GetBiddingInfoList'),
      payload['searchResult']?.toString().split(',') ??
          ['${payload['mainKey']}'],
      _watch.elapsedMilliseconds,
    );
    requests.add(request);
    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => aborted.add(request.tag)));
    }
    return answer?.call(request) ?? _valid(request);
  }

  @override
  void close() {}
}
