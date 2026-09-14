import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_codec.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_observation_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 16);
  Uint8List message(String text, {int code = 0}) => Uint8List.fromList(
    utf8.encode(jsonEncode({'resultCode': code, 'resultMsg': text})),
  );
  OpportunityMarketItem quote(int count, DateTime at, {String id = '4998'}) =>
      OpportunityMarketItem(
        itemId: id,
        basePrice: 5000,
        stock: 50,
        totalTrades: count,
        quoteFetchedAt: at,
      );

  test(
    'depth fills respect price order and partial quantity, not base price',
    () {
      const levels = [
        OpportunityMarketLevel(price: 30, quantity: 2),
        OpportunityMarketLevel(price: 10, quantity: 3),
        OpportunityMarketLevel(price: 20, quantity: 1),
      ];
      final buy = fillMarketDepth(levels: levels, quantity: 4, buying: true);
      expect(buy.totalSilver, 50);
      expect(buy.isComplete, isTrue);
      final sell = fillMarketDepth(levels: levels, quantity: 4, buying: false);
      expect(sell.totalSilver, 90);
      final partial = fillMarketDepth(
        levels: levels,
        quantity: 10,
        buying: true,
      );
      expect(partial.filledQuantity, 6);
      expect(partial.remainingQuantity, 4);
      expect(partial.totalSilver, 110);
      expect(
        () => fillMarketDepth(levels: levels, quantity: -1, buying: true),
        throwsArgumentError,
      );
    },
  );

  test('parts merge independently and unknown never becomes fresh', () {
    final old = quote(100, now.subtract(const Duration(minutes: 10)));
    final book = OpportunityMarketItem(
      itemId: '4998',
      asks: [],
      bids: [],
      bookFetchedAt: now,
    );
    final merged = old.mergeFrom(book);
    expect(merged.stock, 50);
    expect(merged.quoteIsFresh(now, const Duration(minutes: 5)), isFalse);
    expect(merged.bookIsFresh(now, const Duration(minutes: 5)), isTrue);
    expect(merged.preorderCount, 0);
    expect(OpportunityMarketItem(itemId: '1').preorderCount, isNull);
    expect(
      merged.bookIsFresh(
        now.subtract(const Duration(seconds: 1)),
        const Duration(minutes: 5),
      ),
      isFalse,
    );
    final newest = merged.mergeFrom(quote(102, now));
    expect(newest.bookFetchedAt, now);
    expect(newest.mergeFrom(old).totalTrades, 102);
    expect(
      () =>
          merged.asks!.add(const OpportunityMarketLevel(price: 1, quantity: 1)),
      throwsUnsupportedError,
    );
  });

  test(
    'official quote decodes its own trade evidence and rejects bad rows',
    () {
      final bytes = message(
        '4998-0-0-5450000-2770-432100-3500000-6500000-5500000-1788860000|',
      );
      final item = decodeOpportunityQuote(
        bytes: bytes,
        itemId: '4998',
        fetchedAt: now,
      );
      expect(item.stock, 2770);
      expect(item.totalTrades, 432100);
      expect(
        item.lastSoldAt,
        DateTime.fromMillisecondsSinceEpoch(1788860000000, isUtc: true),
      );
      expect(item.bookFetchedAt, isNull);
      for (final invalid in [
        '4998-0-0-500-x|',
        '4998-1-1-500-10|',
        '4999-0-0-500-10|',
        '4998-0-0-0-10|',
      ]) {
        expect(
          () => decodeOpportunityQuote(
            bytes: message(invalid),
            itemId: '4998',
            fetchedAt: now,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => decodeOpportunityQuote(
          bytes: message('4998-0-0-500-0|', code: -1),
          itemId: '4998',
          fetchedAt: now,
        ),
        throwsFormatException,
      );
    },
  );

  test('captured binary book retains seller and buyer price levels', () {
    final item = decodeOpportunityOrderBook(
      bytes: Uint8List.fromList(_capturedOrderBookFixture),
      itemId: '4998',
      fetchedAt: now,
    );
    expect(item.preorderCount, 1627);
    expect(item.asks, isNotEmpty);
    expect(item.bids, isNotEmpty);
    expect(item.basePrice, isNull);
    expect(item.stock, isNull);
    expect(
      item.asks!.map((level) => level.price),
      orderedEquals(item.asks!.map((level) => level.price).toList()..sort()),
    );
    final truncated = Uint8List.fromList(
      _capturedOrderBookFixture.sublist(
        0,
        _capturedOrderBookFixture.length - 1,
      ),
    );
    expect(
      () => decodeOpportunityOrderBook(
        bytes: truncated,
        itemId: '4998',
        fetchedAt: now,
      ),
      throwsFormatException,
    );
  });

  test('known empty books differ from failed or malformed books', () {
    final item = decodeOpportunityOrderBook(
      bytes: message('500-0-0|'),
      itemId: '1',
      fetchedAt: now,
    );
    expect(item.asks, isEmpty);
    expect(item.bids, isEmpty);
    for (final text in ['', '500--1|', '500-1-0|500-2-0|', '500-x-0|']) {
      expect(
        () => decodeOpportunityOrderBook(
          bytes: message(text),
          itemId: '1',
          fetchedAt: now,
        ),
        throwsFormatException,
      );
    }
  });

  test('malformed binary headers and oversized output are rejected safely', () {
    for (final mutation in <void Function(Uint8List)>[
      (bytes) => ByteData.sublistView(bytes).setUint32(0, 1, Endian.little),
      (bytes) => ByteData.sublistView(bytes).setUint32(4, 1, Endian.little),
      (bytes) => ByteData.sublistView(bytes).setUint32(8, 257, Endian.little),
      (bytes) => ByteData.sublistView(bytes).setUint32(12, 0, Endian.little),
      (bytes) => bytes[24] = bytes[16],
      (bytes) => bytes[16] = 255,
      (bytes) =>
          ByteData.sublistView(bytes).setUint32(116, 0xffffffff, Endian.little),
    ]) {
      final bytes = Uint8List.fromList(_capturedOrderBookFixture);
      mutation(bytes);
      expect(decodePearlAbyssOrderBook(bytes), isNull);
    }
    for (var length = 0; length < _capturedOrderBookFixture.length; length++) {
      expect(
        decodePearlAbyssOrderBook(
          Uint8List.fromList(_capturedOrderBookFixture.take(length).toList()),
        ),
        isNull,
      );
    }
    expect(decodePearlAbyssOrderBook(Uint8List(1024 * 1024 + 1)), isNull);
  });

  test(
    'bounded quote scan deduplicates IDs and reports per-item failures',
    () async {
      var active = 0;
      var peak = 0;
      final seen = <Uri>[];
      final transport = _Transport((uri, body, abort) async {
        seen.add(uri);
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        final id = (jsonDecode(body) as Map)['mainKey'];
        return OpportunityHttpResponse(
          statusCode: id == 3 ? 503 : 200,
          bytes: message('$id-0-0-500-0-100-1-1000-500-1788860000|'),
        );
      });
      final service = OpportunityMarketService(
        region: 'EU',
        quoteBatchSize: 1,
        transport: transport,
        utcNow: () => now,
        concurrency: 2,
        requestSpacing: Duration.zero,
      );
      addTearDown(service.close);
      final progress = <int>[];
      final batch = await service.fetchQuotes(
        ['001', '1', '2', '3', '4', 'bad'],
        onProgress: (done, total) {
          progress.add(done);
          expect(total, 4);
        },
      );
      expect(peak, 2);
      expect(seen.length, 4);
      expect(
        seen.every((uri) => uri.host == 'eu-trade.naeu.playblackdesert.com'),
        isTrue,
      );
      expect(batch.items.keys.toSet(), {'1', '2', '4'});
      expect(batch.failures.keys.toSet(), {'3', 'bad'});
      expect(batch.items['1']!.quoteFetchedAt, now);
      expect(progress, [0, 1, 2, 3, 4]);
    },
  );

  test('cancellation aborts in-flight work and stops queued IDs', () async {
    var requests = 0;
    final started = Completer<void>();
    final aborted = Completer<void>();
    final transport = _Transport((uri, body, abort) {
      requests++;
      if (!started.isCompleted) started.complete();
      abort!.then((_) {
        if (!aborted.isCompleted) aborted.complete();
      });
      return Completer<OpportunityHttpResponse>().future;
    });
    final service = OpportunityMarketService(
      transport: transport,
      concurrency: 1,
      quoteBatchSize: 1,
      requestSpacing: Duration.zero,
    );
    addTearDown(service.close);
    final cancellation = MarketCancellationController();
    final scan = service.fetchQuotes([
      '1',
      '2',
      '3',
    ], cancellationToken: cancellation.token);
    final expectation = expectLater(
      scan,
      throwsA(isA<MarketFetchCancelledException>()),
    );
    await started.future;
    cancellation.cancel();
    await expectation;
    await aborted.future;
    expect(requests, 1);
  });

  test('timeout does not invent a fresh quote', () async {
    final transport = _Transport(
      (_, _, _) => Completer<OpportunityHttpResponse>().future,
    );
    final service = OpportunityMarketService(
      transport: transport,
      requestTimeout: const Duration(milliseconds: 5),
      requestSpacing: Duration.zero,
    );
    addTearDown(service.close);
    final batch = await service.fetchQuotes(['1']);
    expect(batch.items, isEmpty);
    expect(batch.failures['1'], 'Market timed out');
  });

  group('observation persistence', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('opportunity-market-test-');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test(
      'first sample unknown; actual interval survives restart and region isolation',
      () async {
        var clock = now;
        final store = OpportunityMarketObservationStore(
          directory: dir,
          utcNow: () => clock,
        );
        await store.load();
        await store.record('eu', [quote(1000, clock)]);
        expect(store.activityFor('eu', '4998'), isNull);
        clock = clock.add(const Duration(minutes: 5));
        await store.record('eu', [quote(1050, clock)]);
        expect(store.activityFor('eu', '4998'), isNull);
        clock = clock.add(const Duration(hours: 2));
        await store.record('EU', [quote(1200, clock)]);
        final activity = store.activityFor('eu', '4998')!;
        expect(activity.soldCount, 200);
        expect(activity.interval, const Duration(hours: 2, minutes: 5));
        expect(store.activityFor('na', '4998'), isNull);
        final restored = OpportunityMarketObservationStore(
          directory: dir,
          utcNow: () => clock,
        );
        await restored.load();
        expect(restored.activityFor('eu', '4998')!.soldCount, 200);
        expect(
          restored
              .withActivity('eu', {'4998': quote(1200, clock)})['4998']!
              .salesActivity!
              .soldCount,
          200,
        );
        expect(
          restored.activityFor(
            'eu',
            '4998',
            now: clock.add(const Duration(days: 2)),
          ),
          isNull,
        );
      },
    );

    test(
      'counter resets start a new baseline; old/future samples cannot add sales',
      () async {
        var clock = now;
        final store = OpportunityMarketObservationStore(
          directory: dir,
          utcNow: () => clock,
        );
        await store.record('eu', [quote(1000, clock)]);
        clock = clock.add(const Duration(hours: 2));
        await store.record('eu', [quote(1500, clock)]);
        expect(store.activityFor('eu', '4998')!.soldCount, 500);
        await store.record('eu', [
          quote(50000, now),
          quote(90000, clock.add(const Duration(hours: 1))),
        ]);
        expect(store.activityFor('eu', '4998')!.soldCount, 500);
        clock = clock.add(const Duration(hours: 2));
        await store.record('eu', [quote(10, clock)]);
        expect(store.activityFor('eu', '4998'), isNull);
      },
    );

    test('observed zero sales is known zero, not lifetime count', () async {
      var clock = now;
      final store = OpportunityMarketObservationStore(
        directory: dir,
        utcNow: () => clock,
      );
      await store.record('eu', [quote(9999999, clock)]);
      clock = clock.add(const Duration(hours: 1));
      await store.record('eu', [quote(9999999, clock)]);
      expect(store.activityFor('eu', '4998')!.soldCount, 0);
    });

    test('failed commit preserves the file and in-memory history', () async {
      var clock = now;
      final committer = _FailingCommitter();
      final store = OpportunityMarketObservationStore(
        directory: dir,
        utcNow: () => clock,
        committer: committer,
      );
      await store.record('eu', [quote(1000, clock)]);
      final previous = await File(store.path).readAsBytes();
      clock = clock.add(const Duration(hours: 1));
      committer.fail = true;
      await expectLater(
        store.record('eu', [quote(2000, clock)]),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(store.path).readAsBytes(), previous);
      expect(store.activityFor('eu', '4998'), isNull);
      committer.fail = false;
      await store.record('eu', [quote(2100, clock)]);
      expect(store.activityFor('eu', '4998')!.soldCount, 1100);
    });

    test(
      'history is bounded and keeps a useful baseline through rapid refreshes',
      () async {
        var clock = now;
        final store = OpportunityMarketObservationStore(
          directory: dir,
          utcNow: () => clock,
        );
        for (var index = 0; index < 150; index++) {
          clock = now.add(Duration(minutes: index * 15));
          await store.record('eu', [quote(1000 + index, clock)]);
        }
        final data = jsonDecode(await File(store.path).readAsString()) as Map;
        expect(((data['series'] as Map)['eu:4998:0'] as List).length, 128);
        expect(store.activityFor('eu', '4998')!.soldCount, greaterThan(0));
        clock = clock.add(const Duration(days: 8));
        await store.record('eu', [quote(2000, clock)]);
        expect(store.activityFor('eu', '4998'), isNull);
      },
    );
  });
}

final class _FailingCommitter implements AtomicFileCommitter {
  bool fail = false;
  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    if (fail) throw const FileSystemException('Test write failure');
    await stagedFile.rename(targetFile.path);
  }
}

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.handler);
  final Future<OpportunityHttpResponse> Function(Uri, String, Future<void>?)
  handler;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) => handler(uri, body, abortTrigger);
  @override
  void close() {}
}

const _capturedOrderBookFixture = <int>[
  155,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  12,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  45,
  0,
  0,
  0,
  56,
  0,
  0,
  0,
  48,
  0,
  0,
  0,
  4,
  0,
  0,
  0,
  49,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  50,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  51,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  52,
  0,
  0,
  0,
  11,
  0,
  0,
  0,
  53,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  54,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  55,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  56,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  57,
  0,
  0,
  0,
  8,
  0,
  0,
  0,
  124,
  0,
  0,
  0,
  20,
  1,
  0,
  0,
  35,
  0,
  0,
  0,
  111,
  0,
  0,
  0,
  31,
  170,
  103,
  113,
  30,
  168,
  196,
  59,
  134,
  190,
  152,
  89,
  24,
  174,
  12,
  61,
  22,
  209,
  74,
  224,
  227,
  211,
  117,
  112,
  127,
  166,
  117,
  112,
  111,
  162,
  85,
  195,
  127,
  85,
  112,
];
