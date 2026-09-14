import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_request_pacer.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_response_guard.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Sanitized shape only: no real incident, challenge query, cookie or IP.
const _denial =
    '<html><body><iframe src="/_Incapsula_Resource?fixture">'
    'Request unsuccessful. Incapsula incident ID: TEST'
    '</iframe></body></html>';

void main() {
  test('only positive HTML protection evidence is classified as blocked', () {
    for (final text in [_denial, ' \n<!DOCTYPE html>$_denial']) {
      expect(isProtectedMarketResponse(bytes: _bytes(text)), isTrue);
    }
    expect(
      isProtectedMarketResponse(
        bytes: _bytes('<iframe src="/_Incapsula_Resource"></iframe>'),
        headers: {'Content-Type': 'text/html; charset=UTF-8'},
      ),
      isTrue,
    );
    for (final text in [
      '<html>Server maintenance, please return later.</html>',
      '{"resultCode":0,"resultMsg":"0"}',
      '{"resultCode":1,"resultMsg":"/_Incapsula_Resource"}',
    ]) {
      expect(isProtectedMarketResponse(bytes: _bytes(text)), isFalse);
    }
    expect(
      isProtectedMarketResponse(bytes: Uint8List.fromList([0, 123, 0, 44])),
      isFalse,
    );
  });

  test('Retry-After accepts seconds and HTTP-date without changing clocks', () {
    final now = DateTime.utc(2026, 9, 10, 12);
    expect(
      marketRetryAfter({'retry-after': '120'}, now),
      const Duration(minutes: 2),
    );
    expect(
      marketRetryAfter({
        'Retry-After': HttpDate.format(now.add(const Duration(minutes: 3))),
      }, now),
      const Duration(minutes: 3),
    );
    expect(marketRetryAfter({'retry-after': 'invalid'}, now), isNull);
  });

  test(
    'denial settles the origin once, retains successes and rejects late data',
    () async {
      var now = DateTime.utc(2026, 9, 10, 12);
      final first = Completer<OpportunityHttpResponse>();
      final late = Completer<OpportunityHttpResponse>();
      final transport = _Transport();
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 2,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(repository.close);
      await repository.fetch(quoteKeys: [_key('99')]);
      transport.answer = (request) => switch (request.tag) {
        'eu/b1' => first.future,
        'eu/b2' => late.future,
        _ => Future.value(_valid(request)),
      };
      var euNotices = 0, siblingNotices = 0;
      final eu = repository.fetch(
        bookKeys: [_key('1'), _key('2'), _key('3')],
        onRateLimited: () => euNotices++,
      );
      await _turn();
      final sibling = repository.fetch(
        bookKeys: [_key('2')],
        onRateLimited: () => siblingNotices++,
      );
      final na = repository.fetch(quoteKeys: [_key('7', 'na')]);
      await _turn();
      first.complete(_html());
      final blocked = await eu;
      expect(blocked.rateLimited, isTrue);
      expect(blocked.bookFailures, {_key('1'), _key('2'), _key('3')});
      expect(blocked.failures.values.toSet(), {'Market busy'});
      expect((await sibling).rateLimited, isTrue);
      expect(euNotices, 1);
      expect(siblingNotices, 1);
      expect((await na).items[_key('7', 'na')]!.basePrice, 100);
      expect(repository.snapshot('eu').items['99']!.basePrice, 100);
      late.complete(_valid(_Request('eu', true, ['2'], 0)));
      await _turn();
      expect(repository.snapshot('eu').items.containsKey('2'), isFalse);
      expect(transport.requests.any((r) => r.tag == 'eu/b3'), isFalse);
      expect(transport.aborted, contains('eu/b2'));
      final before = transport.requests.length;
      now = now.add(const Duration(seconds: 59));
      expect(
        (await repository.fetch(
          bookKeys: [_key('2')],
          forceRefresh: true,
        )).rateLimited,
        isTrue,
      );
      expect(transport.requests, hasLength(before));
      now = now.add(const Duration(seconds: 2));
      transport.answer = null;
      expect(
        (await repository.fetch(
          bookKeys: [_key('2')],
          forceRefresh: true,
          userInitiated: true,
        )).failures,
        isEmpty,
      );
      expect(transport.requests, hasLength(before + 1));
    },
  );

  test(
    'HTML protection in a bulk quote blocks queued books without fabricated rows',
    () async {
      final transport = _Transport()..answer = (_) async => _html();
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final result = await repository.fetch(
        quoteKeys: [_key('1'), _key('2')],
        bookKeys: [_key('1'), _key('2')],
      );
      expect(transport.requests, hasLength(1));
      expect(result.rateLimited, isTrue);
      expect(result.failures, hasLength(4));
      expect(result.items, isEmpty);
      expect(repository.snapshot('eu').items, isEmpty);
    },
  );

  test(
    'unrelated HTML remains unknown and does not block a healthy sibling',
    () async {
      final transport = _Transport()
        ..answer = (request) async => request.ids.single == '1'
            ? _html('<html>Maintenance</html>')
            : _valid(request);
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final result = await repository.fetch(bookKeys: [_key('1'), _key('2')]);
      expect(result.rateLimited, isFalse);
      expect(result.bookFailures, {_key('1')});
      expect(result.items[_key('2')]!.preorderCount, 7);
    },
  );

  test(
    'broker pacing is global, burst-free and independent of the receipt clock',
    () async {
      final transport = _Transport();
      final now = DateTime.utc(2026, 9, 10, 12);
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 20,
        requestSpacing: const Duration(milliseconds: 30),
        utcNow: () => now,
      );
      addTearDown(repository.close);
      final first = repository.fetch(bookKeys: [_key('1'), _key('2')]);
      final second = repository.fetch(bookKeys: [_key('3'), _key('4')]);
      await _turn();
      expect(transport.requests, hasLength(1));
      for (final result in await Future.wait([first, second])) {
        expect(result.failures, isEmpty);
      }
      _expectPaced(transport.requests);
    },
  );

  test(
    'queued consumer cancellation and close cancel pacing wakeups',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: const Duration(seconds: 10),
      );
      final cancellation = MarketCancellationController();
      final loading = repository.fetch(
        bookKeys: [_key('1'), _key('2')],
        cancellationToken: cancellation.token,
      );
      await _turn();
      expect(transport.requests, hasLength(1));
      final cancelled = expectLater(
        loading,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      cancellation.cancel();
      await cancelled;
      await repository.close().timeout(const Duration(seconds: 1));
      expect(transport.requests, hasLength(1));
      expect(transport.closed, isTrue);
    },
  );

  test(
    'relative pacer close releases waiters without running its callback',
    () async {
      var ready = 0;
      final pacer = MarketRequestPacer(
        const Duration(milliseconds: 20),
        onReady: () => ready++,
      );
      pacer.started();
      final waiter = pacer.whenReady;
      pacer.close();
      await waiter;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ready, 0);
      expect(pacer.canStart, isFalse);
    },
  );

  test(
    'standalone denial stops work and honors its cooldown before a new scan',
    () async {
      var now = DateTime.utc(2026, 9, 10, 12);
      final transport = _Transport()..answer = (_) async => _html();
      final service = OpportunityMarketService(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(service.close);
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = await service.fetchMarket(
          quoteIds: ['1', '2'],
          bookIds: ['1', '2'],
        );
        expect(result.rateLimited, isTrue);
        expect(result.failures.keys.toSet(), {'1', '2'});
        expect(result.items, isEmpty);
      }
      expect(transport.requests, hasLength(1));
      now = now.add(const Duration(seconds: 61));
      transport.answer = null;
      expect(
        (await service.fetchMarket(
          quoteIds: ['1', '2'],
          bookIds: ['1', '2'],
          userInitiated: true,
        )).failures,
        isEmpty,
      );
      expect(transport.requests, hasLength(4));
    },
  );

  test(
    'standalone workers share one start interval rather than one per worker',
    () async {
      final transport = _Transport();
      final service = OpportunityMarketService(
        transport: transport,
        concurrency: 20,
        requestSpacing: const Duration(milliseconds: 30),
        utcNow: () => DateTime.utc(2026, 9, 10, 12),
      );
      addTearDown(service.close);
      final result = await service.fetchOrderBooks(['1', '2', '3', '4']);
      expect(result.failures, isEmpty);
      _expectPaced(transport.requests);
    },
  );
}

void _expectPaced(List<_Request> requests) {
  expect(requests, hasLength(4));
  for (var i = 1; i < requests.length; i++) {
    // Relative timers can run late; they must not release an initial burst.
    expect(
      requests[i].startedMs - requests[i - 1].startedMs,
      greaterThanOrEqualTo(25),
    );
  }
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));
OpportunityHttpResponse _html([String html = _denial]) =>
    OpportunityHttpResponse(
      statusCode: 200,
      headers: const {'content-type': 'text/html'},
      bytes: _bytes(html),
    );
SharedMarketKey _key(String id, [String region = 'eu']) =>
    SharedMarketKey(region: region, itemId: id);
Future<void> _turn() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Request {
  _Request(this.region, this.book, this.ids, this.startedMs);
  final String region;
  final bool book;
  final List<String> ids;
  final int startedMs;
  String get tag => '$region/${book ? 'b' : 'q'}${ids.join(',')}';
}

OpportunityHttpResponse _valid(_Request request) {
  final message = request.book
      ? '100-0-7'
      : request.ids.length > 1
      ? request.ids.map((id) => '$id-10-100-1000').join('|')
      : '${request.ids.single}-0-0-100-10-1000';
  return OpportunityHttpResponse(
    statusCode: 200,
    bytes: _bytes(jsonEncode({'resultCode': 0, 'resultMsg': message})),
  );
}

final class _Transport implements OpportunityMarketTransport {
  final watch = Stopwatch()..start();
  final requests = <_Request>[];
  final aborted = <String>[];
  Future<OpportunityHttpResponse> Function(_Request)? answer;
  bool closed = false;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final parsed = jsonDecode(body) as Map;
    final request = _Request(
      uri.host.startsWith('eu-') ? 'eu' : 'na',
      uri.path.endsWith('GetBiddingInfoList'),
      parsed['searchResult']?.toString().split(',') ?? ['${parsed['mainKey']}'],
      watch.elapsedMilliseconds,
    );
    requests.add(request);
    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => aborted.add(request.tag)));
    }
    return answer?.call(request) ?? _valid(request);
  }

  @override
  void close() => closed = true;
}
