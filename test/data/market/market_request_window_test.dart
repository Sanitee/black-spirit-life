import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_request_window.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'short spacing cannot exceed the rolling allowance; slots reopen individually',
    () {
      var elapsed = Duration.zero;
      final budget = MarketRequestWindow(
        limit: 2,
        window: const Duration(minutes: 1),
        elapsed: () => elapsed,
      );
      budget.started();
      elapsed = const Duration(seconds: 5);
      budget.started();
      expect(budget.remainingDelay, const Duration(seconds: 55));
      expect(budget.started, throwsStateError);
      elapsed = const Duration(minutes: 1);
      expect(budget.remainingDelay, Duration.zero);
      budget.started();
      expect(budget.remainingDelay, const Duration(seconds: 5));
    },
  );

  test(
    'saved starts retain their age across restart and clock corrections',
    () {
      var now = DateTime.utc(2026, 9, 10);
      var elapsed = Duration.zero;
      final original = MarketRequestWindow(
        limit: 2,
        window: const Duration(minutes: 1),
        utcNow: () => now,
        elapsed: () => elapsed,
      );
      original.started();
      elapsed = const Duration(seconds: 10);
      now = now.add(elapsed);
      original.started();
      final saved = original.snapshot();
      final restored = MarketRequestWindow(
        limit: 2,
        window: const Duration(minutes: 1),
        utcNow: () => now,
        elapsed: () => Duration.zero,
      )..restore(saved);
      expect(restored.remainingDelay, const Duration(seconds: 50));
      now = now.subtract(const Duration(hours: 1));
      final rewound = MarketRequestWindow(
        limit: 2,
        window: const Duration(minutes: 1),
        utcNow: () => now,
        elapsed: () => Duration.zero,
      )..restore(saved);
      expect(rewound.remainingDelay, const Duration(minutes: 1));
    },
  );

  test('next available start is not the whole 98-start allowance', () {
    var elapsed = Duration.zero;
    final budget = MarketRequestWindow(
      limit: 98,
      window: const Duration(seconds: 60, milliseconds: 20),
      elapsed: () => elapsed,
    );
    for (var i = 0; i < 98; i++) {
      elapsed = Duration(milliseconds: i * 40);
      budget.started();
    }
    elapsed = const Duration(seconds: 4);
    expect(
      budget.remainingDelay,
      const Duration(seconds: 56, milliseconds: 20),
    );
    expect(budget.delayForStarts(1), budget.remainingDelay);
    expect(budget.delayForStarts(98), const Duration(milliseconds: 59900));

    elapsed = const Duration(seconds: 60, milliseconds: 20);
    expect(budget.remainingDelay, Duration.zero);
    expect(budget.delayForStarts(2), const Duration(milliseconds: 40));
    expect(budget.delayForStarts(98), const Duration(milliseconds: 3880));
  });

  test('partial scope waits only for the exact number of missing slots', () {
    var elapsed = Duration.zero;
    final budget = MarketRequestWindow(
      limit: 5,
      window: const Duration(minutes: 1),
      elapsed: () => elapsed,
    );
    for (final seconds in [0, 10, 20]) {
      elapsed = Duration(seconds: seconds);
      budget.started();
    }
    elapsed = const Duration(seconds: 25);
    expect(budget.delayForStarts(0), Duration.zero);
    expect(budget.delayForStarts(1), Duration.zero);
    expect(budget.delayForStarts(2), Duration.zero);
    expect(budget.delayForStarts(3), const Duration(seconds: 35));
    expect(budget.delayForStarts(4), const Duration(seconds: 45));
    expect(budget.delayForStarts(5), const Duration(seconds: 55));

    // Readiness queries do not reserve the two currently available starts.
    budget.started();
    budget.started();
    expect(budget.started, throwsStateError);
    expect(budget.remainingDelay, const Duration(seconds: 35));
    expect(budget.delayForStarts(5), const Duration(minutes: 1));
  });

  test('scope waits expire at the exact guarded window boundary', () {
    var elapsed = Duration.zero;
    final budget = MarketRequestWindow(
      limit: 3,
      window: const Duration(seconds: 60, milliseconds: 20),
      elapsed: () => elapsed,
    );
    for (final milliseconds in [0, 100, 200]) {
      elapsed = Duration(milliseconds: milliseconds);
      budget.started();
    }
    elapsed = const Duration(minutes: 1);
    expect(budget.delayForStarts(1), const Duration(milliseconds: 20));
    expect(budget.delayForStarts(2), const Duration(milliseconds: 120));
    expect(budget.delayForStarts(3), const Duration(milliseconds: 220));
    elapsed = const Duration(seconds: 60, milliseconds: 20);
    expect(budget.delayForStarts(1), Duration.zero);
    expect(budget.delayForStarts(3), const Duration(milliseconds: 200));
    elapsed = const Duration(seconds: 60, milliseconds: 219);
    expect(budget.delayForStarts(3), const Duration(milliseconds: 1));
    elapsed = const Duration(seconds: 60, milliseconds: 220);
    expect(budget.delayForStarts(3), Duration.zero);
    expect(budget.snapshot(), isEmpty);
    elapsed = const Duration(minutes: 5);
    expect(budget.delayForStarts(3), Duration.zero);
  });

  test('live scope waits use elapsed time despite wall-clock changes', () {
    final initial = DateTime.utc(2026, 9, 11);
    var now = initial;
    var elapsed = Duration.zero;
    final budget = MarketRequestWindow(
      limit: 3,
      window: const Duration(minutes: 1),
      utcNow: () => now,
      elapsed: () => elapsed,
    );
    budget.started();
    elapsed = const Duration(seconds: 10);
    budget.started();
    elapsed = const Duration(seconds: 20);
    for (final offset in [const Duration(hours: 1), const Duration(days: -1)]) {
      now = initial.add(offset);
      expect(budget.delayForStarts(1), Duration.zero);
      expect(budget.delayForStarts(2), const Duration(seconds: 40));
      expect(budget.delayForStarts(3), const Duration(seconds: 50));
    }
    elapsed = const Duration(seconds: 30);
    expect(budget.delayForStarts(3), const Duration(seconds: 40));
  });

  test(
    'restored scope waits sort ages and retain future-dated spent slots',
    () {
      final initial = DateTime.utc(2026, 9, 11);
      var now = initial;
      var elapsed = Duration.zero;
      final saved = [
        initial.subtract(const Duration(seconds: 15)),
        initial.add(const Duration(hours: 1)),
        initial.subtract(const Duration(seconds: 50)),
        initial.subtract(const Duration(seconds: 61)),
        initial.subtract(const Duration(seconds: 30)),
      ];
      final budget = MarketRequestWindow(
        limit: 4,
        window: const Duration(minutes: 1),
        utcNow: () => now,
        elapsed: () => elapsed,
      )..restore(saved);
      expect(budget.delayForStarts(1), const Duration(seconds: 10));
      expect(budget.delayForStarts(2), const Duration(seconds: 30));
      expect(budget.delayForStarts(3), const Duration(seconds: 45));
      expect(budget.delayForStarts(4), const Duration(minutes: 1));
      final retained = budget.snapshot();
      expect(retained, [
        initial.subtract(const Duration(seconds: 50)),
        initial.subtract(const Duration(seconds: 30)),
        initial.subtract(const Duration(seconds: 15)),
        initial,
      ]);

      now = initial.subtract(const Duration(hours: 2));
      final restoredAfterRollback = MarketRequestWindow(
        limit: 4,
        window: const Duration(minutes: 1),
        utcNow: () => now,
        elapsed: () => elapsed,
      )..restore(retained);
      expect(
        restoredAfterRollback.delayForStarts(1),
        const Duration(minutes: 1),
      );
      expect(
        restoredAfterRollback.delayForStarts(4),
        const Duration(minutes: 1),
      );
      elapsed = const Duration(seconds: 10);
      expect(
        restoredAfterRollback.delayForStarts(4),
        const Duration(seconds: 50),
      );
    },
  );

  test('zero-count reads are free and invalid scope counts are rejected', () {
    var elapsed = Duration.zero;
    final budget = MarketRequestWindow(
      limit: 2,
      window: const Duration(minutes: 1),
      elapsed: () => elapsed,
    );
    expect(budget.delayForStarts(0), Duration.zero);
    budget.started();
    budget.started();
    expect(budget.delayForStarts(0), Duration.zero);
    for (final count in [-1, 3]) {
      expect(() => budget.delayForStarts(count), throwsArgumentError);
    }
    expect(budget.remainingDelay, const Duration(minutes: 1));
    elapsed = const Duration(minutes: 1);
    expect(budget.delayForStarts(0), Duration.zero);
    expect(budget.delayForStarts(2), Duration.zero);
  });

  test(
    'expired starts and invalid configuration do not produce negative waits',
    () {
      final now = DateTime.utc(2026, 9, 10);
      final budget = MarketRequestWindow(
        limit: 2,
        window: const Duration(minutes: 1),
        utcNow: () => now,
        elapsed: () => Duration.zero,
      )..restore([now.subtract(const Duration(minutes: 1))]);
      expect(budget.remainingDelay, Duration.zero);
      expect(budget.snapshot(), isEmpty);
      expect(
        () => MarketRequestWindow(limit: 0, window: const Duration(minutes: 1)),
        throwsArgumentError,
      );
    },
  );

  test(
    'broker batches count once, queued requests wait, cache hits cost no allowance',
    () async {
      final transport = _Transport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
        quoteBatchSize: 100,
        requestWindowLimit: 2,
        requestWindowDuration: const Duration(milliseconds: 160),
      );
      addTearDown(broker.close);
      final keys = [
        for (var i = 1; i <= 201; i++)
          SharedMarketKey(region: 'eu', itemId: '$i'),
      ];
      final result = await broker.fetch(quoteKeys: keys);
      expect(result.failures, isEmpty);
      expect(result.items.length, 201);
      expect(transport.starts.length, 3);
      expect(
        transport.starts.last.difference(transport.starts.first).inMilliseconds,
        greaterThanOrEqualTo(150),
      );
      await broker.fetch(quoteKeys: keys);
      expect(transport.starts.length, 3);
    },
  );

  test(
    'clean restart keeps spent allowance without delaying cache hits',
    () async {
      final root = await Directory.systemTemp.createTemp('market-window-test-');
      addTearDown(() => root.delete(recursive: true));
      final cache = OpportunityMarketCacheStore(directory: root);
      final transport = _Transport();
      final first = SharedMarketRepository(
        cacheStore: cache,
        transport: transport,
        requestSpacing: Duration.zero,
        requestWindowLimit: 1,
        requestWindowDuration: const Duration(seconds: 2),
      );
      final key = SharedMarketKey(region: 'eu', itemId: '1');
      await first.fetch(quoteKeys: [key]);
      await first.close();
      final second = SharedMarketRepository(
        cacheStore: cache,
        transport: transport,
        requestSpacing: Duration.zero,
        requestWindowLimit: 1,
        requestWindowDuration: const Duration(seconds: 2),
      );
      addTearDown(second.close);
      await second.fetch(quoteKeys: [key]);
      expect(transport.starts.length, 1);
      final cancellation = MarketCancellationController();
      final pending = second.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: '2')],
        cancellationToken: cancellation.token,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(transport.starts.length, 1);
      cancellation.cancel();
      await expectLater(pending, throwsA(isA<MarketFetchCancelledException>()));
    },
  );

  test(
    'malformed ledger waits one local window instead of allowing a new burst',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'market-window-corrupt-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/market-request-window.json').writeAsString('{}');
      final transport = _Transport();
      final broker = SharedMarketRepository(
        cacheStore: OpportunityMarketCacheStore(directory: root),
        transport: transport,
        requestSpacing: Duration.zero,
        requestWindowLimit: 1,
        requestWindowDuration: const Duration(milliseconds: 200),
      );
      addTearDown(broker.close);
      final timer = Stopwatch()..start();
      await broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: '1')],
      );
      expect(timer.elapsedMilliseconds, greaterThanOrEqualTo(180));
      expect(transport.starts.length, 1);
    },
  );
}

final class _Transport implements OpportunityMarketTransport {
  final starts = <DateTime>[];
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    starts.add(DateTime.now());
    final payload = jsonDecode(body) as Map;
    final bulk = payload['searchResult'] as String?;
    final message = bulk == null
        ? '${payload['mainKey']}-0-0-1000-100-500000-100-10000-1000-0|'
        : bulk.split(',').map((id) => '$id-100-1000-500000').join('|');
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
