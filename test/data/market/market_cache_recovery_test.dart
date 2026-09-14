import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/market/market_pause_store.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_request_window.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  final now = DateTime.utc(2026, 9, 11);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('market-cache-repair-');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'fresh market receipts repair the cache and preserve invalid bytes',
    () async {
      final store = OpportunityMarketCacheStore(
        directory: directory,
        utcNow: () => now,
      );
      await File(store.path).writeAsString('invalid cache');
      await expectLater(store.load(), throwsFormatException);
      await store.save({
        'eu': {
          '1': OpportunityMarketItem(
            itemId: '1',
            basePrice: 123,
            stock: 4,
            quoteFetchedAt: now.subtract(const Duration(minutes: 5)),
            asks: const [],
            bids: const [OpportunityMarketLevel(price: 123, quantity: 7)],
            bookFetchedAt: now.subtract(const Duration(minutes: 10)),
          ),
        },
      });
      final item = (await store.load())['eu']!['1']!;
      expect(item.basePrice, 123);
      expect(item.preorderCount, 7);
      expect(item.quoteFetchedAt, now.subtract(const Duration(minutes: 5)));
      expect(item.bookFetchedAt, now.subtract(const Duration(minutes: 10)));
      final original = await directory
          .list()
          .where((entry) => entry.path.contains('.corrupt-'))
          .cast<File>()
          .single;
      expect(await original.readAsString(), 'invalid cache');
    },
  );

  test(
    'unreadable ledger is repaired before requests without restarting its wait',
    () async {
      final ledger = File('${directory.path}/market-request-window.json');
      await ledger.writeAsString('{}');
      var clock = now;
      SharedMarketRepository createBroker() => SharedMarketRepository(
        cacheStore: OpportunityMarketCacheStore(
          directory: directory,
          utcNow: () => clock,
        ),
        utcNow: () => clock,
        requestWindowLimit: 2,
        requestWindowDuration: const Duration(minutes: 1),
      );
      final first = createBroker();
      await first.ready;
      expect(first.diagnostics.startedRequests, 0);
      final repaired = jsonDecode(await ledger.readAsString()) as Map;
      expect(repaired['starts'], hasLength(2));
      await first.close();

      clock = now.add(const Duration(seconds: 20));
      final second = createBroker();
      await second.ready;
      expect(second.diagnostics.startedRequests, 0);
      expect(second.persistenceError, isNull);
      final saved = await MarketRequestWindowStore(directory: directory).load();
      final window = MarketRequestWindow(
        limit: 2,
        window: const Duration(minutes: 1),
        utcNow: () => clock,
        elapsed: () => Duration.zero,
      )..restore(saved);
      expect(
        window.remainingDelay.inMilliseconds,
        inInclusiveRange(39990, 40000),
      );
      await second.close();
      final original = await directory
          .list()
          .where((entry) => entry.path.contains('.corrupt-'))
          .cast<File>()
          .single;
      expect(await original.readAsString(), '{}');
    },
  );

  test('market pause records keep strict existing-file protection', () async {
    final pause = File('${directory.path}/market-request-pauses.json');
    await pause.writeAsString('{}');
    await expectLater(
      MarketPauseStore(directory: directory, utcNow: () => now).save({}),
      throwsFormatException,
    );
    expect(await pause.readAsString(), '{}');
    expect(await directory.list().length, 1);
  });
}
