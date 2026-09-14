import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/market/market_pause_store.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_request_pause.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late MarketPauseStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('market-pause-test-');
    store = MarketPauseStore(directory: directory);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'missing operational state starts empty without creating a file',
    () async {
      expect(await store.load(), isEmpty);
      expect(await File(store.path).exists(), isFalse);
    },
  );

  test('restart keeps each region and its exact server deadline', () async {
    final deadline = DateTime.utc(2026, 9, 10, 18, 4, 17);
    await store.save({
      'eu': MarketRequestPause(
        reason: MarketRequestPauseReason.throttled,
        retryAt: deadline,
      ),
      'na': MarketRequestPause(
        reason: MarketRequestPauseReason.protected,
        retryAt: deadline.add(const Duration(minutes: 20)),
      ),
    });
    final restarted = MarketPauseStore(directory: directory);
    final result = await restarted.load();
    expect(result.keys, unorderedEquals(['eu', 'na']));
    expect(result['eu']!.retryAt, deadline);
    expect(result['eu']!.reason, MarketRequestPauseReason.throttled);
    expect(result['na']!.reason, MarketRequestPauseReason.protected);
    expect(result['na']!.retryAt, deadline.add(const Duration(minutes: 20)));
  });

  test(
    'an expired local deadline does not erase protective evidence',
    () async {
      final old = DateTime.utc(2020);
      await store.save({
        'eu': MarketRequestPause(
          reason: MarketRequestPauseReason.protected,
          retryAt: old,
        ),
      });
      final restored = await store.load();
      expect(restored['eu']!.reason, MarketRequestPauseReason.protected);
      expect(restored['eu']!.retryAt, old);
    },
  );

  test('503 keeps its own retry cause after restart', () async {
    final deadline = DateTime.utc(2026, 9, 10, 18, 5);
    await store.save({
      'eu': MarketRequestPause(
        reason: MarketRequestPauseReason.serverUnavailable,
        retryAt: deadline,
      ),
    });
    final restored = await MarketPauseStore(directory: directory).load();
    expect(restored['eu']!.reason, MarketRequestPauseReason.serverUnavailable);
    expect(restored['eu']!.retryAt, deadline);
  });

  test('successful access can explicitly clear the saved pause', () async {
    await store.save({
      'eu': MarketRequestPause(
        reason: MarketRequestPauseReason.throttled,
        retryAt: DateTime.utc(2026),
      ),
    });
    await store.save({});
    expect(await MarketPauseStore(directory: directory).load(), isEmpty);
  });

  test('invalid state is reported and left untouched', () async {
    for (final regions in [
      {
        'kr': {'reason': 'throttled', 'retryAt': 1},
      },
      {
        'eu': {'reason': 'unknown', 'retryAt': 1},
      },
      {
        'eu': {'reason': 'protected', 'retryAt': -1},
      },
      {
        'eu': {'reason': 'protected', 'retryAt': 'later'},
      },
      {
        'eu': {'reason': 'protected', 'retryAt': 8640000000000001},
      },
    ]) {
      final raw = jsonEncode({
        'version': 1,
        'source': 'pearl-abyss',
        'regions': regions,
      });
      await File(store.path).writeAsString(raw);
      await expectLater(store.load(), throwsFormatException);
      expect(await File(store.path).readAsString(), raw);
    }
  });

  test('oversize state is rejected before decoding', () async {
    await File(store.path).writeAsString(' ' * 16385);
    await expectLater(store.load(), throwsFormatException);
  });

  test('pauses do not overwrite the independent raw price cache', () async {
    final cache = File('${directory.path}/opportunity-market-cache.json');
    await cache.writeAsString('independent existing receipts');
    await store.save({
      'eu': MarketRequestPause(
        reason: MarketRequestPauseReason.throttled,
        retryAt: DateTime.utc(2026),
      ),
    });
    expect(await cache.readAsString(), 'independent existing receipts');
  });
}
