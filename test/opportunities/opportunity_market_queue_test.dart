import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a slow quote does not block books or the next free worker', () async {
    final held = Completer<OpportunityHttpResponse>();
    final starts = <String>[];
    var active = 0, peak = 0;
    final service = OpportunityMarketService(
      concurrency: 4,
      quoteBatchSize: 1,
      requestSpacing: Duration.zero,
      transport: _Transport((key, abort) async {
        starts.add(key);
        active++;
        if (active > peak) peak = active;
        final result = key == 'q1'
            ? await held.future
            : await Future<OpportunityHttpResponse>.delayed(
                Duration.zero,
                () => _response(key),
              );
        active--;
        return result;
      }),
    );
    addTearDown(service.close);
    final batchFuture = service.fetchMarket(
      quoteIds: ['1', '2', '3', '4'],
      bookIds: ['1', '2', '3', '4'],
    );
    await _until(() => starts.length == 8);
    expect(held.isCompleted, isFalse);
    expect(starts.take(4), ['q1', 'q2', 'q3', 'q4']);
    expect(peak, 4);
    held.complete(_response('q1'));
    final batch = await batchFuture;
    expect(batch.failures, isEmpty);
    expect(batch.items, hasLength(4));
    for (final item in batch.items.values) {
      expect(item.basePrice, 1000);
      expect(item.preorderCount, 3);
      expect(item.stock, 20);
      expect(item.quoteFetchedAt, isNotNull);
      expect(item.bookFetchedAt, isNotNull);
    }
  });

  test(
    'mixed scans deduplicate each part and keep successful siblings',
    () async {
      final starts = <String>[];
      final receipts = <String>[];
      final progress = <int>[];
      final service = OpportunityMarketService(
        concurrency: 1,
        quoteBatchSize: 1,
        requestSpacing: Duration.zero,
        transport: _Transport((key, abort) async {
          starts.add(key);
          return key == 'b1'
              ? OpportunityHttpResponse(statusCode: 429, bytes: Uint8List(0))
              : _response(key);
        }),
      );
      addTearDown(service.close);
      final batch = await service.fetchMarket(
        quoteIds: ['001', '1', '2', 'bad'],
        bookIds: ['1', '01', '2'],
        onItem: (item) => receipts.add(
          '${item.quoteFetchedAt == null ? 'b' : 'q'}${item.itemId}',
        ),
        onProgress: (done, total) {
          expect(total, 4);
          progress.add(done);
        },
      );
      expect(starts, ['q1', 'q2', 'b1']);
      expect(receipts.toSet(), {'q1', 'q2'});
      expect(batch.failures, {
        'bad': 'Invalid item ID',
        '1': 'Market busy',
        '2': 'Market busy',
      });
      expect(batch.items['1']!.basePrice, 1000);
      expect(batch.items['1']!.bookFetchedAt, isNull);
      expect(batch.items['1']!.bids, isNull);
      expect(progress, [0, 1, 2, 3, 4]);
    },
  );

  test('selected section reprioritizes the very next free worker', () async {
    final first = Completer<OpportunityHttpResponse>();
    var priority = <String>[];
    final starts = <String>[];
    final service = OpportunityMarketService(
      concurrency: 1,
      quoteBatchSize: 1,
      requestSpacing: Duration.zero,
      transport: _Transport((key, abort) async {
        starts.add(key);
        return key == 'q1' ? first.future : _response(key);
      }),
    );
    addTearDown(service.close);
    final result = service.fetchMarket(
      quoteIds: ['1', '2', '3'],
      bookIds: ['1', '2', '3'],
      priorityIds: () => priority,
    );
    await _until(() => starts.isNotEmpty);
    priority = ['3'];
    first.complete(_response('q1'));
    await result;
    expect(starts, ['q1', 'q3', 'q2', 'b3', 'b1', 'b2']);
  });

  test(
    '429 settles queued work while retaining already delivered receipts',
    () async {
      final starts = <String>[];
      final service = OpportunityMarketService(
        concurrency: 1,
        quoteBatchSize: 1,
        requestSpacing: Duration.zero,
        transport: _Transport((key, abort) async {
          starts.add(key);
          return key == 'q2'
              ? OpportunityHttpResponse(statusCode: 429, bytes: Uint8List(0))
              : _response(key);
        }),
      );
      addTearDown(service.close);
      final batch = await service.fetchMarket(
        quoteIds: [for (var id = 1; id <= 100; id++) '$id'],
        bookIds: [for (var id = 1; id <= 100; id++) '$id'],
      );
      expect(starts, ['q1', 'q2']);
      expect(batch.rateLimited, isTrue);
      expect(batch.failures, hasLength(100));
      expect(batch.failures.values.toSet(), {'Market busy'});
      expect(batch.items['1']!.quoteFetchedAt, isNotNull);
      expect(batch.items['1']!.bookFetchedAt, isNull);
      expect(batch.items.containsKey('2'), isFalse);
      expect(batch.items.containsKey('3'), isFalse);
    },
  );

  test(
    'reentrant and parallel callers cannot multiply the four worker cap',
    () async {
      final gates = <String, Completer<OpportunityHttpResponse>>{};
      final starts = <String>[];
      var active = 0, peak = 0;
      final service = OpportunityMarketService(
        concurrency: 4,
        quoteBatchSize: 1,
        requestSpacing: Duration.zero,
        transport: _Transport((key, abort) async {
          starts.add(key);
          active++;
          if (active > peak) peak = active;
          final result = await (gates[key] = Completer()).future;
          active--;
          return result;
        }),
      );
      addTearDown(service.close);
      Future<OpportunityMarketBatch>? reentrant;
      final first = service.fetchQuotes([
        '1',
        '2',
        '3',
        '4',
      ], onItem: (_) => reentrant ??= service.fetchOrderBooks(['6']));
      final second = service.fetchQuotes(['5']);
      await _until(() => starts.length == 4);
      gates['q1']!.complete(_response('q1'));
      await _until(() => reentrant != null);
      expect(starts, ['q1', 'q2', 'q3', 'q4']);
      for (final key in ['q2', 'q3', 'q4']) {
        gates[key]!.complete(_response(key));
      }
      await first;
      await _until(() => gates.containsKey('q5'));
      gates['q5']!.complete(_response('q5'));
      await second;
      await _until(() => gates.containsKey('b6'));
      gates['b6']!.complete(_response('b6'));
      await reentrant;
      expect(peak, 4);
      expect(starts, ['q1', 'q2', 'q3', 'q4', 'q5', 'b6']);
    },
  );

  test('network time counts toward global start spacing', () async {
    final stopwatch = Stopwatch()..start();
    final starts = <Duration>[];
    Duration? firstResponse;
    final service = OpportunityMarketService(
      concurrency: 1,
      quoteBatchSize: 1,
      requestSpacing: const Duration(milliseconds: 200),
      transport: _Transport((key, abort) async {
        starts.add(stopwatch.elapsed);
        if (key == 'q1') {
          await Future<void>.delayed(const Duration(milliseconds: 240));
          firstResponse = stopwatch.elapsed;
        }
        return _response(key);
      }),
    );
    addTearDown(service.close);
    await service.fetchQuotes(['1', '2', '3']);
    expect(
      starts[1] - firstResponse!,
      lessThan(const Duration(milliseconds: 150)),
    );
    expect(
      starts[2] - starts[1],
      greaterThanOrEqualTo(const Duration(milliseconds: 195)),
    );
  });

  test(
    'Stop interrupts pacing and never dispatches the next queued request',
    () async {
      final cancellation = MarketCancellationController();
      final starts = <String>[];
      final service = OpportunityMarketService(
        concurrency: 1,
        quoteBatchSize: 1,
        requestSpacing: const Duration(seconds: 2),
        transport: _Transport((key, abort) async {
          starts.add(key);
          return _response(key);
        }),
      );
      addTearDown(service.close);
      final scan = service.fetchMarket(
        quoteIds: ['1', '2'],
        bookIds: ['1', '2'],
        cancellationToken: cancellation.token,
      );
      final expected = expectLater(
        scan,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await _until(() => starts.isNotEmpty);
      cancellation.cancel();
      await expected.timeout(const Duration(seconds: 1));
      expect(starts, ['q1']);
    },
  );
}

Future<void> _until(bool Function() check) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Queue did not reach the expected state.');
}

OpportunityHttpResponse _response(String key) => OpportunityHttpResponse(
  statusCode: 200,
  bytes: Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'resultCode': 0,
        'resultMsg': key.startsWith('b')
            ? '1000-20-3|'
            : '${key.substring(1)}-0-0-1000-20-500-1-10000-1000-1788860000|',
      }),
    ),
  ),
);

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.handler);
  final Future<OpportunityHttpResponse> Function(String, Future<void>?) handler;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) {
    final id = (jsonDecode(body) as Map)['mainKey'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    return handler('${book ? 'b' : 'q'}$id', abortTrigger);
  }

  @override
  void close() {}
}
