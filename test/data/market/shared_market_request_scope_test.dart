import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final initial = DateTime.utc(2026, 9, 11, 12);
  late DateTime now;
  late _Transport transport;
  late SharedMarketRepository repository;

  Future<void> create({int concurrency = 1}) async {
    transport = _Transport();
    repository = SharedMarketRepository(
      transport: transport,
      utcNow: () => now,
      concurrency: concurrency,
      requestSpacing: Duration.zero,
    );
    await repository.ready;
  }

  setUp(() async {
    now = initial;
    await create();
  });
  tearDown(() => repository.close());

  test(
    'partial release keeps retained work and original receipt ages',
    () async {
      await repository.fetch(quoteKeys: [_key('1')]);
      transport.requests.clear();
      now = now.add(const Duration(minutes: 1));
      transport.hold = true;
      final scope = SharedMarketRequestScope();
      final progress = <(int, int)>[];
      final result = repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1'), _key('2'), _key('3')],
        scope: scope,
        onProgress: (done, total) => progress.add((done, total)),
      );
      await _until(() => transport.requests.length == 1);
      expect(progress.last, (1, 4));
      scope.release([_book('2')]);
      expect(progress.last, (1, 3));
      expect(transport.requests.single.id, '1');
      expect(transport.aborted, isEmpty);
      transport.hold = false;
      transport.release('1');
      final batch = await result;
      expect(transport.requests.map((request) => request.id), ['1', '3']);
      expect(transport.aborted, isEmpty);
      expect(batch.items.keys.toSet(), {_key('1'), _key('3')});
      expect(batch.failures, isEmpty);
      expect(batch.retryableFailures, isEmpty);
      expect(batch.items[_key('1')]!.quoteFetchedAt, initial);
      expect(batch.items[_key('1')]!.bookFetchedAt, now);
      expect(progress.last, (3, 3));
      final bookAt = now;
      now = now.add(const Duration(hours: 1));
      final replay = await repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1'), _key('3')],
      );
      expect(transport.requests, hasLength(2));
      expect(replay.items[_key('1')]!.quoteFetchedAt, initial);
      expect(replay.items[_key('1')]!.bookFetchedAt, bookAt);
    },
  );

  test('released shared book remains owned by its other caller', () async {
    await repository.close();
    await create(concurrency: 2);
    transport.hold = true;
    final scope = SharedMarketRequestScope();
    final deliveries = <SharedMarketReceipt>[];
    final first = repository.fetch(
      bookKeys: [_key('1'), _key('2')],
      scope: scope,
      onItem: deliveries.add,
    );
    final sibling = repository.fetch(bookKeys: [_key('1')]);
    await _until(() => transport.requests.length == 2);
    scope.release([_book('1')]);
    await _turn();
    expect(transport.aborted, isEmpty);
    transport.release('2');
    final firstBatch = await first;
    expect(firstBatch.items.keys, [_key('2')]);
    expect(firstBatch.failures, isEmpty);
    transport.release('1');
    final siblingBatch = await sibling;
    expect(siblingBatch.items.keys, [_key('1')]);
    expect(deliveries.map((receipt) => receipt.key), [_key('2')]);
    expect(
      transport.requests.where((request) => request.id == '1'),
      hasLength(1),
    );
    expect(repository.snapshot('eu').items.keys.toSet(), {'1', '2'});
  });

  test(
    'only unowned removed in-flight work aborts; obsolete queue never starts',
    () async {
      await repository.close();
      await create(concurrency: 2);
      transport.hold = true;
      final scope = SharedMarketRequestScope();
      final result = repository.fetch(
        bookKeys: [_key('1'), _key('2'), _key('3')],
        scope: scope,
      );
      await _until(() => transport.requests.length == 2);
      scope.release([_book('2'), _book('3')]);
      await _until(() => transport.aborted.isNotEmpty);
      expect(transport.aborted, ['2']);
      expect(transport.requests.map((request) => request.id), ['1', '2']);
      transport.release('1');
      final batch = await result;
      expect(batch.items.keys, [_key('1')]);
      expect(batch.failures, isEmpty);
      expect(batch.retryableFailures, isEmpty);
      expect(repository.snapshot('eu').items.containsKey('3'), isFalse);
    },
  );

  test(
    'release before fetch attaches never dispatches or manufactures failure',
    () async {
      final scope = SharedMarketRequestScope();
      final progress = <(int, int)>[];
      final result = repository.fetch(
        bookKeys: [_key('1')],
        scope: scope,
        onProgress: (done, total) => progress.add((done, total)),
      );
      scope.release([_book('1')]);
      final batch = await result;
      expect(transport.requests, isEmpty);
      expect(batch.items, isEmpty);
      expect(batch.failures, isEmpty);
      expect(batch.retryableFailures, isEmpty);
      expect(progress, [(0, 0)]);
    },
  );

  test('release during cached delivery skips later obsolete parts', () async {
    await repository.fetch(quoteKeys: [_key('1')]);
    final scope = SharedMarketRequestScope();
    final result = await repository.fetch(
      quoteKeys: [_key('1')],
      bookKeys: [_key('2')],
      scope: scope,
      onItem: (_) => scope.release([_book('2')]),
    );
    expect(transport.requests, hasLength(1));
    expect(result.items.keys, [_key('1')]);
    expect(result.failures, isEmpty);
    expect(result.items[_key('1')]!.quoteFetchedAt, initial);
  });

  test(
    'completed removed failures leave progress and retry results too',
    () async {
      await repository.close();
      await create(concurrency: 2);
      transport.hold = true;
      transport.failed.add('1');
      final scope = SharedMarketRequestScope();
      final progress = <(int, int)>[];
      final result = repository.fetch(
        bookKeys: [_key('1'), _key('2')],
        scope: scope,
        onProgress: (done, total) => progress.add((done, total)),
      );
      await _until(() => transport.requests.length == 2);
      transport.release('1');
      await _until(() => progress.last == (1, 2));
      scope.release([_book('1')]);
      expect(progress.last, (0, 1));
      transport.release('2');
      final batch = await result;
      expect(progress.last, (1, 1));
      expect(batch.failures, isEmpty);
      expect(batch.retryableFailures, isEmpty);
      expect(batch.items.keys, [_key('2')]);
    },
  );

  test(
    'explicit Stop still aborts retained work after partial release',
    () async {
      transport.hold = true;
      final scope = SharedMarketRequestScope();
      final cancellation = MarketCancellationController();
      final result = repository.fetch(
        bookKeys: [_key('1'), _key('2'), _key('3')],
        scope: scope,
        cancellationToken: cancellation.token,
      );
      final stopped = expectLater(
        result,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await _until(() => transport.requests.isNotEmpty);
      scope.release([_book('2')]);
      cancellation.cancel();
      await stopped;
      await _until(() => transport.aborted.isNotEmpty);
      expect(transport.aborted, ['1']);
      expect(transport.requests.map((request) => request.id), ['1']);
      expect(repository.snapshot('eu').items, isEmpty);
    },
  );
}

SharedMarketKey _key(String id) => SharedMarketKey(region: 'eu', itemId: id);
SharedMarketPartKey _book(String id) =>
    SharedMarketPartKey(_key(id), SharedMarketPart.orderBook);
Future<void> _turn() => Future<void>.delayed(Duration.zero);
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Scoped market work did not settle');
    }
    await _turn();
  }
}

final class _Request {
  _Request(this.id);
  final String id;
  final done = Completer<void>();
}

final class _Transport implements OpportunityMarketTransport {
  final requests = <_Request>[];
  final aborted = <String>[];
  final failed = <String>{};
  bool hold = false;

  void release(String id) =>
      requests.firstWhere((request) => request.id == id).done.complete();

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final id = '${payload['mainKey'] ?? payload['searchResult']}';
    final book = uri.path.endsWith('GetBiddingInfoList');
    final request = _Request(id);
    requests.add(request);
    if (hold) {
      unawaited(
        abortTrigger?.then((_) {
          if (!request.done.isCompleted) {
            aborted.add(id);
            request.done.completeError(const MarketFetchCancelledException());
          }
        }),
      );
      await request.done.future;
    }
    return OpportunityHttpResponse(
      statusCode: failed.contains(id) ? 500 : 200,
      bytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'resultCode': 0,
            'resultMsg': book ? '100-3-0|90-0-7' : '$id-0-0-100-5-1000',
          }),
        ),
      ),
    );
  }

  @override
  void close() {}
}
