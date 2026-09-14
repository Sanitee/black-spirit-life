import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  final now = DateTime.utc(2026, 9, 9, 20);
  late OpportunityMarketCacheStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'opportunity-cache-test-',
    );
    store = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => now,
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'raw receipts round trip with independent dates and regional identities',
    () async {
      final quoteAt = now.subtract(const Duration(hours: 2));
      final bookAt = now.subtract(const Duration(minutes: 20));
      await store.save({
        'eu': {'123': _item('123', quoteAt, bookAt)},
        'na': {
          '123': OpportunityMarketItem(
            itemId: '123',
            basePrice: 800,
            stock: 0,
            quoteFetchedAt: now,
            asks: [],
            bids: [],
            bookFetchedAt: now,
          ),
        },
      });
      final loaded = await store.load();
      final eu = loaded['eu']!['123']!;
      expect(eu.basePrice, 123456789);
      expect(eu.stock, 21);
      expect(eu.quoteFetchedAt, quoteAt);
      expect(eu.bookFetchedAt, bookAt);
      expect(eu.asks!.single.price, 123456700);
      expect(eu.asks!.single.quantity, 7);
      expect(eu.bids!.single.quantity, 12);
      expect(eu.totalTrades, 2345678901);
      expect(eu.lastSoldAt, quoteAt.subtract(const Duration(minutes: 1)));
      expect(
        eu.salesActivity,
        isNull,
        reason: 'Derived activity has its own store.',
      );
      expect(loaded['na']!['123']!.basePrice, 800);
      expect(loaded['na']!['123']!.asks, isEmpty);
      final json = await File(store.path).readAsString();
      for (final excluded in [
        'profit',
        'tax',
        'mastery',
        'owned',
        'salesActivity',
      ]) {
        expect(json, isNot(contains('"$excluded"')));
      }
    },
  );

  test(
    'unknown depth stays null; known empty stays empty; unlisted stays explicit',
    () async {
      await store.save({
        'eu': {
          '1': OpportunityMarketItem(
            itemId: '1',
            basePrice: 100,
            quoteFetchedAt: now,
          ),
          '2': OpportunityMarketItem(
            itemId: '2',
            asks: [],
            bids: [],
            bookFetchedAt: now,
          ),
          '3': OpportunityMarketItem(
            itemId: '3',
            unlisted: true,
            quoteFetchedAt: now,
          ),
        },
      });
      final items = (await store.load())['eu']!;
      expect(items['1']!.asks, isNull);
      expect(items['1']!.bids, isNull);
      expect(items['1']!.bookFetchedAt, isNull);
      expect(items['2']!.asks, isEmpty);
      expect(items['2']!.bids, isEmpty);
      expect(items['2']!.quoteFetchedAt, isNull);
      expect(items['3']!.unlisted, isTrue);
      expect(items['3']!.basePrice, isNull);
    },
  );

  test(
    'future quote or book is discarded independently and never becomes evidence',
    () async {
      final future = now.add(const Duration(minutes: 1));
      await store.save({
        'eu': {
          '1': _item('1', future, now),
          '2': _item('2', now, future),
          '3': _item('3', future, future),
        },
      });
      final items = (await store.load())['eu']!;
      expect(items.keys, ['1', '2']);
      expect(items['1']!.basePrice, isNull);
      expect(items['1']!.stock, isNull);
      expect(items['1']!.quoteFetchedAt, isNull);
      expect(items['1']!.bookFetchedAt, now);
      expect(items['2']!.quoteFetchedAt, now);
      expect(items['2']!.asks, isNull);
      expect(items['2']!.bookFetchedAt, isNull);
    },
  );

  test(
    'expired raw data retains its original date rather than renewing on load',
    () async {
      final old = now.subtract(const Duration(hours: 4));
      await store.save({
        'eu': {'1': _item('1', old, old)},
      });
      final item = (await store.load())['eu']!['1']!;
      expect(item.quoteFetchedAt, old);
      expect(item.bookFetchedAt, old);
      expect(item.quoteIsFresh(now, const Duration(hours: 3)), isFalse);
      expect(item.bookIsFresh(now, const Duration(hours: 3)), isFalse);
    },
  );

  for (final corruption in [
    'json',
    'version',
    'source',
    'region',
    'identity',
    'stock',
    'depth',
  ]) {
    test(
      'invalid $corruption cache stays untouched on load and is archived on repair',
      () async {
        final replacement = {
          'eu': {'1': _item('1', now, now)},
          'na': {
            '2': _item('2', now, now.subtract(const Duration(minutes: 20))),
          },
        };
        await store.save(replacement);
        final file = File(store.path);
        final validBytes = await file.readAsBytes();
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final regions = raw['regions'] as Map;
        final items = regions['eu'] as Map;
        final entry = items['1'] as Map;
        switch (corruption) {
          case 'version':
            raw['version'] = 999;
          case 'source':
            raw['source'] = 'unknown';
          case 'region':
            regions['xx'] = regions.remove('eu');
          case 'identity':
            entry['itemId'] = '2';
          case 'stock':
            entry['stock'] = -1;
          case 'depth':
            entry['asks'] = [
              [0, 12],
            ];
        }
        await file.writeAsString(
          corruption == 'json' ? '{broken' : jsonEncode(raw),
        );
        final original = await file.readAsBytes();
        await expectLater(store.load(), throwsFormatException);
        expect(await file.readAsBytes(), original);
        expect(await directory.list().length, 1);

        await store.save(replacement);
        expect(await file.readAsBytes(), validBytes);
        final loaded = await store.load();
        expect(loaded.keys, ['eu', 'na']);
        expect(loaded['eu']!['1']!.quoteFetchedAt, now);
        expect(loaded['eu']!['1']!.bookFetchedAt, now);
        expect(loaded['na']!['2']!.quoteFetchedAt, now);
        expect(
          loaded['na']!['2']!.bookFetchedAt,
          now.subtract(const Duration(minutes: 20)),
        );
        final preserved = await directory
            .list()
            .where((entry) => entry.path.contains('.corrupt-'))
            .cast<File>()
            .single;
        expect(await preserved.readAsBytes(), original);
        expect(await directory.list().length, 2);
      },
    );
  }

  test('failed atomic commit preserves all prior regional receipts', () async {
    await store.save({
      'eu': {'1': _item('1', now, now)},
    });
    final before = await File(store.path).readAsBytes();
    final failing = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => now,
      committer: const _FailCommitter(),
    );
    await expectLater(
      failing.save({
        'na': {'2': _item('2', now, now)},
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(store.path).readAsBytes(), before);
    expect((await store.load()).keys, ['eu']);
  });
}

OpportunityMarketItem _item(String id, DateTime quoteAt, DateTime bookAt) =>
    OpportunityMarketItem(
      itemId: id,
      basePrice: 123456789,
      stock: 21,
      quoteFetchedAt: quoteAt,
      asks: const [OpportunityMarketLevel(price: 123456700, quantity: 7)],
      bids: const [OpportunityMarketLevel(price: 123456600, quantity: 12)],
      bookFetchedAt: bookAt,
      totalTrades: 2345678901,
      lastSoldAt: quoteAt.subtract(const Duration(minutes: 1)),
      salesActivity: OpportunitySalesActivity(
        soldCount: 77,
        startedAt: quoteAt.subtract(const Duration(hours: 2)),
        endedAt: quoteAt,
      ),
    );

class _FailCommitter implements AtomicFileCommitter {
  const _FailCommitter();
  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    throw const FileSystemException('Synthetic commit failure');
  }
}
