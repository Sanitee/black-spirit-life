import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_pause_store.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'continuous receipts checkpoint before completion without waiting for disk',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'market-checkpoint-',
      );
      final committer = _HeldCommitter();
      final transport = _Transport()
        ..respond = (call) async {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          return _valid(call);
        };
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
        cacheStore: OpportunityMarketCacheStore(
          directory: directory,
          committer: committer,
        ),
      );
      addTearDown(() async {
        if (!committer.release.isCompleted) committer.release.complete();
        await repository.close();
        await directory.delete(recursive: true);
      });
      var finished = false;
      final loading = repository
          .fetch(bookKeys: [for (var id = 1; id <= 12; id++) _key('$id')])
          .then((result) {
            finished = true;
            return result;
          });
      await committer.entered.future.timeout(const Duration(seconds: 3));
      expect(finished, isFalse);
      final countAtSave = transport.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(transport.calls.length, greaterThan(countAtSave));
      committer.release.complete();
      expect((await loading).failures, isEmpty);
      await repository.flush();
      final saved = await OpportunityMarketCacheStore(
        directory: directory,
      ).load();
      expect(saved['eu'], hasLength(12));
    },
  );

  test(
    'a later429 keeps its own cause despite earlier transient failures',
    () async {
      final transport = _Transport()
        ..respond = (call) async {
          if (call.ids.single == '1') throw const SocketException('fixture');
          return _response(status: 429, headers: {'retry-after': '120'});
        };
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final batch = await repository.fetch(
        bookKeys: [_key('1'), _key('2'), _key('3')],
      );
      expect(batch.retryableFailures, {_book('1')});
      expect(batch.pause!.reason, MarketRequestPauseReason.throttled);
      expect(batch.bookFailures, {_key('1'), _key('2'), _key('3')});
    },
  );

  test('defaults keep quote batching fast and bound detailed book starts', () {
    final repository = SharedMarketRepository(transport: _Transport());
    final service = OpportunityMarketService(transport: _Transport());
    addTearDown(repository.close);
    addTearDown(service.close);
    expect(repository.requestSpacing, const Duration(milliseconds: 40));
    expect(
      repository.orderBookRequestSpacing,
      const Duration(milliseconds: 250),
    );
    expect(service.orderBookRequestSpacing, const Duration(milliseconds: 250));
    final fixture = SharedMarketRepository(
      transport: _Transport(),
      requestSpacing: Duration.zero,
    );
    addTearDown(fixture.close);
    expect(fixture.orderBookRequestSpacing, Duration.zero);
  });

  test(
    'only transport, timeout and 5xx parts are retryable including cooldown hits',
    () async {
      final transport = _Transport()
        ..respond = (call) async {
          switch (call.ids.single) {
            case '1':
              throw TimeoutException('fixture');
            case '2':
              throw const SocketException('fixture');
            case '3':
              return _response(status: 503);
            case '4':
              return _response(status: 404);
            case '5':
              return _response(body: '<html>Maintenance</html>');
            case '6':
              return _response(body: '{"resultCode":0,"resultMsg":"0"}');
            case '8':
              throw StateError('not a network failure');
            default:
              return _valid(call);
          }
        };
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final keys = [for (var id = 1; id <= 8; id++) _key('$id')];
      final first = await repository.fetch(bookKeys: keys);
      expect(first.retryableFailures, {_book('1'), _book('2'), _book('3')});
      expect(
        first.bookFailures,
        keys.where((key) => key.itemId != '7').toSet(),
      );
      expect(first.pause, isNull);
      final again = await repository.fetch(bookKeys: keys);
      expect(transport.calls, hasLength(8));
      expect(again.retryableFailures, first.retryableFailures);
      expect(repository.snapshot('eu').items.keys, ['7']);
    },
  );

  test(
    'retry identity keeps a healthy quote separate from a failed book',
    () async {
      final transport = _Transport()
        ..respond = (call) async {
          if (call.book) throw const SocketException('fixture');
          return _valid(call);
        };
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final batch = await repository.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1')],
      );
      expect(batch.retryableFailures, {_book('1')});
      expect(batch.items[_key('1')]!.stock, 10);
      expect(batch.items[_key('1')]!.bookFetchedAt, isNull);
    },
  );

  test(
    '503 Retry-After pauses and marks every queued part transient',
    () async {
      var now = DateTime.utc(2026, 9, 10, 14);
      final transport = _Transport()
        ..respond = (_) async => _response(
          status: 503,
          headers: {
            'Retry-After': HttpDate.format(now.add(const Duration(minutes: 2))),
          },
        );
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(repository.close);
      final batch = await repository.fetch(
        quoteKeys: [_key('1'), _key('2')],
        bookKeys: [_key('1'), _key('2')],
      );
      expect(batch.pause!.reason, MarketRequestPauseReason.serverUnavailable);
      expect(batch.pause!.retryAt, now.add(const Duration(minutes: 2)));
      expect(batch.retryableFailures, {
        _quote('1'),
        _quote('2'),
        _book('1'),
        _book('2'),
      });
      expect(transport.calls, hasLength(1));
      now = now.add(const Duration(seconds: 119));
      final waiting = await repository.fetch(
        bookKeys: [_key('1')],
        forceRefresh: true,
        userInitiated: true,
      );
      expect(waiting.pause!.retryAt, batch.pause!.retryAt);
      expect(transport.calls, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      transport.respond = null;
      final recovered = await repository.fetch(bookKeys: [_key('1')]);
      expect(recovered.failures, isEmpty);
      expect(repository.pauseFor('eu'), isNull);
    },
  );

  test(
    'protective HTML overrides 429 and cannot become an automatic retry',
    () async {
      var now = DateTime.utc(2026, 9, 10, 14);
      final transport = _Transport()
        ..respond = (_) async => _protected(status: 429);
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(repository.close);
      final batch = await repository.fetch(bookKeys: [_key('1'), _key('2')]);
      expect(batch.pause!.reason, MarketRequestPauseReason.protected);
      expect(batch.retryableFailures, isEmpty);
      now = now.add(const Duration(minutes: 10));
      transport.respond = null;
      for (final recovery in [false, true]) {
        final blocked = await repository.fetch(
          bookKeys: [_key('1')],
          forceRefresh: true,
          recovery: recovery,
        );
        expect(blocked.pause!.reason, MarketRequestPauseReason.protected);
      }
      expect(transport.calls, hasLength(1));
      final manual = await repository.fetch(
        bookKeys: [_key('1')],
        userInitiated: true,
      );
      expect(manual.failures, isEmpty);
      expect(repository.pauseFor('eu'), isNull);
    },
  );

  test(
    'persisted protection permits cached receipts but not automatic startup after deadline',
    () async {
      var now = DateTime.utc(2026, 9, 10, 14);
      final directory = await Directory.systemTemp.createTemp(
        'market-pause-restart-',
      );
      final transport = _Transport();
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
      );
      final first = SharedMarketRepository(
        cacheStore: store,
        transport: transport,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      await first.fetch(quoteKeys: [_key('1')]);
      transport.respond = (_) async => _protected();
      await first.fetch(bookKeys: [_key('1')]);
      await first.close();
      now = now.add(const Duration(minutes: 2));
      final freshTransport = _Transport();
      final reopened = SharedMarketRepository(
        cacheStore: store,
        transport: freshTransport,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });
      final startup = await reopened.fetch(
        quoteKeys: [_key('1')],
        bookKeys: [_key('1')],
      );
      expect(startup.items[_key('1')]!.stock, 10);
      expect(startup.pause!.reason, MarketRequestPauseReason.protected);
      expect(freshTransport.calls, isEmpty);
      await reopened.flush();
      expect(
        (await MarketPauseStore(directory: directory).load())['eu']!.reason,
        MarketRequestPauseReason.protected,
      );
      await reopened.fetch(bookKeys: [_key('1')], userInitiated: true);
      await reopened.flush();
      expect(await MarketPauseStore(directory: directory).load(), isEmpty);
    },
  );

  test(
    'persisted throttling cannot be shortened by restart or manual refresh',
    () async {
      var now = DateTime.utc(2026, 9, 10, 14);
      final directory = await Directory.systemTemp.createTemp(
        'market-throttle-restart-',
      );
      final pauseStore = MarketPauseStore(directory: directory);
      final retryAt = now.add(const Duration(minutes: 3));
      await pauseStore.save({
        'eu': MarketRequestPause(
          reason: MarketRequestPauseReason.throttled,
          retryAt: retryAt,
        ),
      });
      final transport = _Transport();
      final repository = SharedMarketRepository(
        pauseStore: pauseStore,
        transport: transport,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(() async {
        await repository.close();
        await directory.delete(recursive: true);
      });
      final waiting = await repository.fetch(
        bookKeys: [_key('1')],
        forceRefresh: true,
        userInitiated: true,
      );
      expect(waiting.pause!.retryAt, retryAt);
      expect(transport.calls, isEmpty);
      now = retryAt;
      expect((await repository.fetch(bookKeys: [_key('1')])).failures, isEmpty);
    },
  );

  test(
    'corrupt pause storage fails closed for automatic reads but allows explicit recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'market-pause-invalid-',
      );
      final pauseStore = MarketPauseStore(directory: directory);
      await File(pauseStore.path).writeAsString('not valid JSON');
      final transport = _Transport();
      final repository = SharedMarketRepository(
        pauseStore: pauseStore,
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(() async {
        await repository.close();
        await directory.delete(recursive: true);
      });
      final waiting = await repository.fetch(bookKeys: [_key('1')]);
      expect(waiting.failures.values, ['Market pause could not be read']);
      expect(waiting.retryableFailures, isEmpty);
      expect(waiting.pause, isNull);
      expect(repository.pauseReadError, isNotNull);
      expect(transport.calls, isEmpty);
      await repository.fetch(bookKeys: [_key('1')], userInitiated: true);
      await expectLater(repository.flush(), throwsFormatException);
      expect(repository.pauseReadError, isNotNull);
      expect(repository.persistenceError, isNotNull);
      expect(await File(pauseStore.path).readAsString(), 'not valid JSON');
      final recoveredEu = await repository.fetch(bookKeys: [_key('2')]);
      expect(recoveredEu.failures, isEmpty);
      final beforeNa = transport.calls.length;
      final unknownNa = await repository.fetch(
        bookKeys: [SharedMarketKey(region: 'na', itemId: '1')],
      );
      expect(unknownNa.failures.values, ['Market pause could not be read']);
      expect(transport.calls, hasLength(beforeNa));
    },
  );

  test(
    'normal quotes and books have separate minimum gaps without catch-up bursts',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository(
        transport: transport,
        quoteBatchSize: 1,
        requestSpacing: const Duration(milliseconds: 20),
        orderBookRequestSpacing: const Duration(milliseconds: 80),
      );
      addTearDown(repository.close);
      await repository.fetch(
        quoteKeys: [_key('1'), _key('2')],
        bookKeys: [_key('1'), _key('2')],
      );
      expect(transport.calls.map((call) => call.book), [
        false,
        false,
        true,
        true,
      ]);
      expect(
        transport.calls[1].start - transport.calls[0].start,
        greaterThanOrEqualTo(18),
      );
      for (var index = 2; index < 4; index++) {
        expect(
          transport.calls[index].start - transport.calls[index - 1].start,
          greaterThanOrEqualTo(78),
        );
      }
    },
  );

  test(
    'queued recovery coalescing uses strictest gap before dispatch and is not downgraded',
    () async {
      final first = Completer<OpportunityHttpResponse>();
      final transport = _Transport()
        ..respond = (call) =>
            call.ids.single == '1' ? first.future : Future.value(_valid(call));
      final repository = SharedMarketRepository(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final initial = repository.fetch(bookKeys: [_key('1'), _key('2')]);
      await _turn();
      final recovery = repository.fetch(bookKeys: [_key('2')], recovery: true);
      final normal = repository.fetch(bookKeys: [_key('2')]);
      await _turn();
      first.complete(_valid(transport.calls.first));
      await Future.wait([initial, recovery, normal]);
      expect(transport.calls, hasLength(2));
      expect(
        transport.calls[1].start - transport.calls[0].start,
        greaterThanOrEqualTo(990),
      );
    },
  );

  test(
    'in-flight recovery joins without duplicate request or retroactive delay',
    () async {
      final held = Completer<OpportunityHttpResponse>();
      final transport = _Transport()..respond = (_) => held.future;
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final first = repository.fetch(bookKeys: [_key('1')]);
      await _turn();
      final second = repository.fetch(bookKeys: [_key('1')], recovery: true);
      await _turn();
      held.complete(_valid(transport.calls.single));
      await Future.wait([first, second]);
      expect(transport.calls, hasLength(1));
    },
  );

  test(
    'fallback 503 and transport failures preserve equivalent part metadata',
    () async {
      final now = DateTime.utc(2026, 9, 10, 14);
      final transport = _Transport()
        ..respond = (_) async =>
            _response(status: 503, headers: {'retry-after': '90'});
      final service = OpportunityMarketService(
        transport: transport,
        concurrency: 1,
        requestSpacing: Duration.zero,
        utcNow: () => now,
      );
      addTearDown(service.close);
      final batch = await service.fetchMarket(
        quoteIds: ['1', '2'],
        bookIds: ['1', '2'],
      );
      expect(batch.pause!.reason, MarketRequestPauseReason.serverUnavailable);
      expect(batch.pause!.retryAt, now.add(const Duration(seconds: 90)));
      expect(service.pause, same(batch.pause));
      expect(batch.retryableQuoteFailures, {'1', '2'});
      expect(batch.retryableBookFailures, {'1', '2'});
      expect(transport.calls, hasLength(1));
    },
  );

  test('fallback recovery requests use the slower global interval', () async {
    final transport = _Transport();
    final service = OpportunityMarketService(
      transport: transport,
      requestSpacing: Duration.zero,
    );
    addTearDown(service.close);
    await service.fetchOrderBooks(['1']);
    await service.fetchOrderBooks(['2', '3'], recovery: true);
    expect(transport.calls, hasLength(3));
    for (var index = 1; index < 3; index++) {
      expect(
        transport.calls[index].start - transport.calls[index - 1].start,
        greaterThanOrEqualTo(990),
      );
    }
  });
}

SharedMarketKey _key(String id) => SharedMarketKey(region: 'eu', itemId: id);
SharedMarketPartKey _book(String id) =>
    SharedMarketPartKey(_key(id), SharedMarketPart.orderBook);
SharedMarketPartKey _quote(String id) =>
    SharedMarketPartKey(_key(id), SharedMarketPart.quote);
Future<void> _turn() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

OpportunityHttpResponse _response({
  int status = 200,
  String body = '',
  Map<String, String> headers = const {},
}) => OpportunityHttpResponse(
  statusCode: status,
  bytes: Uint8List.fromList(utf8.encode(body)),
  headers: headers,
);
OpportunityHttpResponse _protected({int status = 200}) => _response(
  status: status,
  headers: {'content-type': 'text/html', 'retry-after': '60'},
  body:
      '<html>Request unsuccessful. Incapsula incident ID: TEST <iframe src="/_Incapsula_Resource?fixture"></iframe></html>',
);
OpportunityHttpResponse _valid(_Call call) => _response(
  body: jsonEncode({
    'resultCode': 0,
    'resultMsg': call.book
        ? '100-0-7'
        : call.ids.length > 1
        ? call.ids.map((id) => '$id-10-100-1000').join('|')
        : '${call.ids.single}-0-0-100-10-1000',
  }),
);

final class _Call {
  _Call(this.ids, this.book, this.start);
  final List<String> ids;
  final bool book;
  final int start;
}

final class _Transport implements OpportunityMarketTransport {
  final watch = Stopwatch()..start();
  final calls = <_Call>[];
  Future<OpportunityHttpResponse> Function(_Call)? respond;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final request = jsonDecode(body) as Map;
    final call = _Call(
      request['searchResult']?.toString().split(',') ??
          ['${request['mainKey']}'],
      uri.path.endsWith('GetBiddingInfoList'),
      watch.elapsedMilliseconds,
    );
    calls.add(call);
    return respond?.call(call) ?? _valid(call);
  }

  @override
  void close() {}
}

final class _HeldCommitter implements AtomicFileCommitter {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await stagedFile.rename(targetFile.path);
  }
}
