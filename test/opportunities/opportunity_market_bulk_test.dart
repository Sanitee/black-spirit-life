import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_bulk_codec.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 19, 39, 34);

  test(
    'captured PA summary has prices, stock and trades, not book or sale time',
    () {
      // Two unchanged rows from the bounded 40-ID EU check at 19:39 UTC.
      final decoded = decodeOpportunityBulkQuotes(
        bytes: _json('1180-20981-343000-33819711|6216-0-39400-1593623'),
        requestedIds: ['1180', '6216'],
        fetchedAt: now,
      );
      expect(decoded.failures, isEmpty);
      final item = decoded.items['1180']!;
      expect(item.basePrice, 343000);
      expect(item.stock, 20981);
      expect(item.totalTrades, 33819711);
      expect(item.quoteFetchedAt, now);
      expect(item.lastSoldAt, isNull);
      expect(item.bookFetchedAt, isNull);
      expect(item.asks, isNull);
      expect(item.bids, isNull);
      expect(decoded.items['6216']!.stock, 0);
      expect(decoded.items['6216']!.preorderCount, isNull);
      expect(decoded.items['6216']!.unlisted, isFalse);
    },
  );

  test('missing and invalid rows fail only their IDs; zero is not absence', () {
    final decoded = decodeOpportunityBulkQuotes(
      bytes: _json('1-0-1000-0|2-1-0-30|3-bad-500-40|4-2-600|99-10-900-5'),
      requestedIds: ['1', '2', '3', '4', '5'],
      fetchedAt: now,
    );
    expect(decoded.items.keys, ['1']);
    expect(decoded.items['1']!.stock, 0);
    expect(decoded.items['1']!.totalTrades, 0);
    expect(decoded.failures.keys, ['2', '3', '4', '5']);
    expect(decoded.items.containsKey('99'), isFalse);
  });

  test('duplicate rows remain invalid even if a third row looks valid', () {
    final decoded = decodeOpportunityBulkQuotes(
      bytes: _json('1-0-1000-4|1-0-1001-4|1-0-1002-4|2-1-50-0'),
      requestedIds: ['1', '2'],
      fetchedAt: now,
    );
    expect(decoded.items.keys, ['2']);
    expect(decoded.failures.keys, ['1']);
  });

  test('numeric overflow, decimals, signs and extra fields are not quotes', () {
    final decoded = decodeOpportunityBulkQuotes(
      bytes: _json(
        '1-0-999999999999999999999999999-2|2-1-1.2-0|3-+1-50-0|4-0-60-0-extra',
      ),
      requestedIds: ['1', '2', '3', '4'],
      fetchedAt: now,
    );
    expect(decoded.items, isEmpty);
    expect(decoded.failures, hasLength(4));
  });

  test(
    'an empty successful response means unknown quotes, not unlisted items',
    () {
      final decoded = decodeOpportunityBulkQuotes(
        bytes: _json(''),
        requestedIds: ['1', '2'],
        fetchedAt: now,
      );
      expect(decoded.items, isEmpty);
      expect(decoded.failures, hasLength(2));
    },
  );

  test('unsuccessful, oversized, invalid UTF-8 and wrong envelopes fail', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List(1024 * 1024 + 1),
      Uint8List.fromList([255]),
      Uint8List.fromList(utf8.encode('{"resultCode":1,"resultMsg":""}')),
      Uint8List.fromList(utf8.encode('{"resultCode":0,"resultMsg":null}')),
      Uint8List.fromList(utf8.encode('[]')),
    ]) {
      expect(
        () => decodeOpportunityBulkQuotes(
          bytes: bytes,
          requestedIds: ['1'],
          fetchedAt: now,
        ),
        throwsFormatException,
      );
    }
  });

  test('defaults use 20 workers, batch40 and 40ms request pacing', () {
    final service = OpportunityMarketService(transport: _Transport(_success));
    addTearDown(service.close);
    expect(service.concurrency, 20);
    expect(service.effectiveConcurrency, 20);
    expect(service.quoteBatchSize, 40);
    expect(service.requestSpacing, const Duration(milliseconds: 40));
    for (final size in [0, 101]) {
      expect(
        () => OpportunityMarketService(
          quoteBatchSize: size,
          transport: _Transport(_success),
        ),
        throwsArgumentError,
      );
    }
    for (final count in [0, 41]) {
      expect(
        () => OpportunityMarketService(
          concurrency: count,
          transport: _Transport(_success),
        ),
        throwsArgumentError,
      );
    }
  });

  test('a retained regional ceiling can only lower a new service pool', () {
    final service = OpportunityMarketService(
      transport: _Transport(_success),
      requestSpacing: Duration.zero,
    );
    addTearDown(service.close);
    service.limitConcurrency(5);
    expect(service.effectiveConcurrency, 5);
    service.limitConcurrency(40);
    expect(service.effectiveConcurrency, 5);
    expect(service.concurrency, 20);
    expect(() => service.limitConcurrency(0), throwsArgumentError);
  });

  test(
    '81 canonical quotes use two 40-ID requests plus one detailed quote',
    () async {
      final requests = <_Request>[];
      final receipts = <OpportunityMarketItem>[];
      final progress = <(int, int)>[];
      final service = OpportunityMarketService(
        utcNow: () => now,
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          requests.add(request);
          expect(request.uri.host, 'eu-trade.naeu.playblackdesert.com');
          expect(request.headers['User-Agent'], 'BlackDesert');
          return _success(request);
        }),
      );
      addTearDown(service.close);
      final result = await service.fetchQuotes(
        [..._ids(81), '001', 'bad'],
        onItem: receipts.add,
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(requests, hasLength(3));
      expect(requests.map((request) => request.ids.length), [40, 40, 1]);
      expect(
        requests
            .take(2)
            .every((request) => request.endpoint == 'GetWorldMarketSearchList'),
        isTrue,
      );
      expect(requests.last.endpoint, 'GetWorldMarketSubList');
      expect(requests.first.body.keys, ['searchResult']);
      expect(result.items, hasLength(81));
      expect(receipts, hasLength(81));
      expect(result.failures.keys, ['bad']);
      expect(progress.first, (0, 81));
      expect(progress.last, (81, 81));
    },
  );

  test(
    'a held bulk summary cannot block the twelve-worker rolling book pool',
    () async {
      final held = Completer<OpportunityHttpResponse>();
      final requests = <_Request>[];
      var active = 0, peak = 0;
      var clock = now;
      final service = OpportunityMarketService(
        concurrency: 12,
        utcNow: () => clock,
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          requests.add(request);
          active++;
          if (active > peak) peak = active;
          final response = request.endpoint == 'GetWorldMarketSearchList'
              ? await held.future
              : await Future<OpportunityHttpResponse>.delayed(
                  Duration.zero,
                  () => _success(request),
                );
          active--;
          return response;
        }),
      );
      addTearDown(service.close);
      final scan = service.fetchMarket(quoteIds: _ids(24), bookIds: _ids(24));
      await _until(() => requests.length == 25 && active == 1);
      expect(peak, 12);
      clock = now.add(const Duration(seconds: 1));
      held.complete(_success(requests.first));
      final result = await scan;
      expect(result.failures, isEmpty);
      expect(result.items, hasLength(24));
      for (final item in result.items.values) {
        expect(item.quoteFetchedAt, clock);
        expect(item.bookFetchedAt, now);
        expect(item.preorderCount, 7);
        expect(item.asks!.map((level) => level.price), [900, 1100]);
      }
    },
  );

  test(
    'dynamic priority changes the next batch and retains its item books',
    () async {
      final held = Completer<OpportunityHttpResponse>();
      final requests = <_Request>[];
      var priority = <String>[];
      final service = OpportunityMarketService(
        concurrency: 1,
        quoteBatchSize: 2,
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          requests.add(request);
          return requests.length == 1 ? held.future : _success(request);
        }),
      );
      addTearDown(service.close);
      final scan = service.fetchMarket(
        quoteIds: _ids(6),
        bookIds: _ids(6),
        priorityIds: () => priority,
      );
      await _until(() => requests.isNotEmpty);
      expect(requests.first.ids, ['1', '2']);
      priority = ['6', '5'];
      held.complete(_success(requests.first));
      final result = await scan;
      expect(requests[1].ids, ['6', '5']);
      expect(requests[2].ids, ['3', '4']);
      expect(requests[2].endpoint, 'GetWorldMarketSearchList');
      expect(requests[3].ids, ['6']);
      expect(requests[3].endpoint, 'GetBiddingInfoList');
      expect(requests[4].ids, ['5']);
      expect(result.items, hasLength(6));
      expect(result.failures, isEmpty);
    },
  );

  test(
    'partial bulk results keep valid sibling quotes and full books',
    () async {
      final service = OpportunityMarketService(
        requestSpacing: Duration.zero,
        transport: _Transport(
          (request) async => request.endpoint == 'GetWorldMarketSearchList'
              ? _response('1-0-1000-5|3-bad-1000-6')
              : _success(request),
        ),
      );
      addTearDown(service.close);
      final result = await service.fetchMarket(
        quoteIds: _ids(3),
        bookIds: _ids(3),
      );
      expect(result.failures.keys, ['2', '3']);
      expect(result.items['1']!.basePrice, 1000);
      for (final id in ['2', '3']) {
        expect(result.items[id]!.basePrice, isNull);
        expect(result.items[id]!.quoteFetchedAt, isNull);
        expect(result.items[id]!.bookFetchedAt, isNotNull);
      }
    },
  );

  test(
    'a failed bulk request retains books and does not create retry traffic',
    () async {
      final requests = <_Request>[];
      final service = OpportunityMarketService(
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          requests.add(request);
          return request.endpoint == 'GetWorldMarketSearchList'
              ? OpportunityHttpResponse(statusCode: 503, bytes: Uint8List(0))
              : _success(request);
        }),
      );
      addTearDown(service.close);
      final result = await service.fetchMarket(
        quoteIds: _ids(10),
        bookIds: _ids(10),
      );
      expect(requests, hasLength(11));
      expect(result.failures, hasLength(10));
      expect(result.items, hasLength(10));
      expect(
        result.items.values.every(
          (item) => item.quoteFetchedAt == null && item.bookFetchedAt != null,
        ),
        isTrue,
      );
    },
  );

  test(
    'bulk 429 stops queued and in-flight work but keeps delivered receipts',
    () async {
      final requests = <_Request>[];
      final pending = <String, Completer<OpportunityHttpResponse>>{};
      final receipts = <OpportunityMarketItem>[];
      var callbacks = 0;
      final service = OpportunityMarketService(
        concurrency: 2,
        requestSpacing: Duration.zero,
        transport: _Transport((request) {
          requests.add(request);
          if (request.ids.first == '1') return _success(request);
          final completion = Completer<OpportunityHttpResponse>();
          pending[request.ids.first] = completion;
          return completion.future;
        }),
      );
      addTearDown(service.close);
      final scan = service.fetchMarket(
        quoteIds: _ids(100),
        bookIds: _ids(100),
        onItem: receipts.add,
        onRateLimited: () => callbacks++,
      );
      await _until(() => receipts.length == 40 && pending.length == 2);
      expect(requests.map((request) => request.ids.length), [40, 40, 20]);
      pending['41']!.complete(
        OpportunityHttpResponse(statusCode: 429, bytes: Uint8List(0)),
      );
      final result = await scan;
      expect(requests, hasLength(3));
      expect(callbacks, 1);
      expect(result.rateLimited, isTrue);
      expect(result.failures, hasLength(100));
      expect(result.items.keys, _ids(40));
      expect(receipts, hasLength(40));
      expect(
        result.items.values.every(
          (item) => item.basePrice != null && item.bookFetchedAt == null,
        ),
        isTrue,
      );
    },
  );

  test('Stop aborts bulk and books without dispatching more IDs', () async {
    final cancellation = MarketCancellationController();
    final requests = <_Request>[];
    var aborted = 0;
    final service = OpportunityMarketService(
      concurrency: 12,
      requestSpacing: Duration.zero,
      transport: _Transport((request) {
        requests.add(request);
        request.abortTrigger!.then((_) => aborted++);
        return Completer<OpportunityHttpResponse>().future;
      }),
    );
    addTearDown(service.close);
    final scan = service.fetchMarket(
      quoteIds: _ids(100),
      bookIds: _ids(100),
      cancellationToken: cancellation.token,
    );
    final expected = expectLater(
      scan,
      throwsA(isA<MarketFetchCancelledException>()),
    );
    await _until(() => requests.length == 12);
    cancellation.cancel();
    await expected;
    await _until(() => aborted == 12);
    expect(requests, hasLength(12));
  });

  test('cancelling inside a bulk receipt stops later item callbacks', () async {
    final cancellation = MarketCancellationController();
    final receipts = <String>[];
    final service = OpportunityMarketService(
      transport: _Transport(_success),
      requestSpacing: Duration.zero,
    );
    addTearDown(service.close);
    await expectLater(
      service.fetchQuotes(
        _ids(40),
        cancellationToken: cancellation.token,
        onItem: (item) {
          receipts.add(item.itemId);
          cancellation.cancel();
        },
      ),
      throwsA(isA<MarketFetchCancelledException>()),
    );
    expect(receipts, ['1']);
  });

  test(
    'simultaneous callers cannot multiply the twelve-connection cap',
    () async {
      final held = Completer<void>();
      final requests = <_Request>[];
      var active = 0, peak = 0;
      final service = OpportunityMarketService(
        concurrency: 12,
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          requests.add(request);
          active++;
          if (active > peak) peak = active;
          await held.future;
          active--;
          return _success(request);
        }),
      );
      addTearDown(service.close);
      final first = service.fetchMarket(quoteIds: _ids(24), bookIds: _ids(24));
      final second = service.fetchQuotes(['101', '102']);
      await _until(() => requests.length == 12);
      expect(requests.any((request) => request.ids.contains('101')), isFalse);
      held.complete();
      final results = await Future.wait([first, second]);
      expect(results.every((result) => result.failures.isEmpty), isTrue);
      expect(peak, 12);
      expect(requests.last.ids, ['101', '102']);
    },
  );

  for (final cap in [20, 40]) {
    test('the shared pool never exceeds its configured $cap slots', () async {
      final held = Completer<void>();
      var active = 0, peak = 0, starts = 0;
      final service = OpportunityMarketService(
        concurrency: cap,
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          starts++;
          active++;
          if (active > peak) peak = active;
          await held.future;
          active--;
          return _success(request);
        }),
      );
      addTearDown(service.close);
      final first = service.fetchOrderBooks(_ids(64));
      final second = service.fetchQuotes(['101', '102']);
      await _until(() => starts == cap);
      expect(active, cap);
      held.complete();
      final results = await Future.wait([first, second]);
      expect(results.every((result) => result.failures.isEmpty), isTrue);
      expect(peak, cap);
      expect(starts, 65);
    });
  }

  for (final failure in ['503', 'timeout']) {
    test(
      '$failure halves dispatch slots and keeps the smaller pool next scan',
      () async {
        final pending =
            <String, (Completer<OpportunityHttpResponse>, _Request)>{};
        final starts = <String>[];
        var automatic = false;
        final service = OpportunityMarketService(
          concurrency: 8,
          requestSpacing: Duration.zero,
          transport: _Transport((request) {
            final id = request.ids.single;
            starts.add(id);
            if (automatic) return _success(request);
            final completion = Completer<OpportunityHttpResponse>();
            pending[id] = (completion, request);
            return completion.future;
          }),
        );
        addTearDown(service.close);
        final first = service.fetchOrderBooks(_ids(16));
        await _until(() => starts.length == 8);
        if (failure == '503') {
          pending['1']!.$1.complete(
            OpportunityHttpResponse(statusCode: 503, bytes: Uint8List(0)),
          );
        } else {
          pending['1']!.$1.completeError(
            TimeoutException('test response timeout'),
          );
        }
        await _until(() => starts.length == 9);
        for (final id in ['5', '6', '7', '8']) {
          final entry = pending[id]!;
          entry.$1.complete(_success(entry.$2));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          starts,
          hasLength(9),
          reason: 'Retired high-index workers cannot dispatch more jobs.',
        );
        automatic = true;
        for (final entry in pending.values) {
          if (!entry.$1.isCompleted) entry.$1.complete(_success(entry.$2));
        }
        final result = await first;
        expect(result.failures.keys, ['1']);
        expect(result.items, hasLength(15));
        expect(
          starts.toSet(),
          hasLength(16),
          reason: 'Failed IDs are never retried.',
        );

        automatic = false;
        pending.clear();
        final second = service.fetchOrderBooks(
          List.generate(12, (index) => '${101 + index}'),
        );
        await _until(() => starts.length == 20);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          pending,
          hasLength(4),
          reason: 'A new scan must not immediately ramp up again.',
        );
        automatic = true;
        for (final entry in pending.values) {
          entry.$1.complete(_success(entry.$2));
        }
        expect((await second).failures, isEmpty);
        expect(
          service.concurrency,
          8,
          reason: 'The requested configuration stays unchanged.',
        );
      },
    );
  }

  test(
    'repeated server failures retain a two-slot floor, not zero workers',
    () async {
      var failing = true, starts = 0;
      final held = Completer<void>();
      final service = OpportunityMarketService(
        concurrency: 8,
        requestSpacing: Duration.zero,
        transport: _Transport((request) async {
          starts++;
          if (failing) {
            return OpportunityHttpResponse(
              statusCode: 503,
              bytes: Uint8List(0),
            );
          }
          await held.future;
          return _success(request);
        }),
      );
      addTearDown(service.close);
      final failed = await service.fetchOrderBooks(_ids(8));
      expect(failed.failures, hasLength(8));
      expect(starts, 8);
      failing = false;
      final recovered = service.fetchOrderBooks(_ids(6));
      await _until(() => starts == 10);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(starts, 10);
      held.complete();
      expect((await recovered).items, hasLength(6));
    },
  );

  test(
    'a bulk timeout aborts once and marks every requested quote unknown',
    () async {
      var calls = 0, aborted = 0;
      final service = OpportunityMarketService(
        requestTimeout: const Duration(milliseconds: 5),
        requestSpacing: Duration.zero,
        transport: _Transport((request) {
          calls++;
          request.abortTrigger!.then((_) => aborted++);
          return Completer<OpportunityHttpResponse>().future;
        }),
      );
      addTearDown(service.close);
      final result = await service.fetchQuotes(_ids(40));
      expect(result.items, isEmpty);
      expect(result.failures, hasLength(40));
      expect(calls, 1);
      await _until(() => aborted == 1);
    },
  );
}

List<String> _ids(int count) => List.generate(count, (index) => '${index + 1}');
Uint8List _json(String message) => Uint8List.fromList(
  utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': message})),
);
OpportunityHttpResponse _response(String message) =>
    OpportunityHttpResponse(statusCode: 200, bytes: _json(message));

OpportunityHttpResponse _success(_Request request) {
  if (request.endpoint == 'GetWorldMarketSearchList') {
    return _response(request.ids.map((id) => '$id-20-1000-500').join('|'));
  }
  if (request.endpoint == 'GetBiddingInfoList') {
    return _response('1100-5-0|1000-0-7|900-10-0');
  }
  return _response(
    '${request.ids.single}-0-0-1000-20-500-1-10000-1000-1788860000',
  );
}

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('The market queue did not reach the expected state.');
}

final class _Request {
  const _Request(this.uri, this.headers, this.body, this.abortTrigger);
  final Uri uri;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  final Future<void>? abortTrigger;
  String get endpoint => uri.pathSegments.last;
  List<String> get ids => body.containsKey('searchResult')
      ? (body['searchResult'] as String).split(',')
      : ['${body['mainKey']}'];
}

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.handler);
  final FutureOr<OpportunityHttpResponse> Function(_Request) handler;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async => handler(
    _Request(
      uri,
      headers,
      jsonDecode(body) as Map<String, dynamic>,
      abortTrigger,
    ),
  );
  @override
  void close() {}
}
