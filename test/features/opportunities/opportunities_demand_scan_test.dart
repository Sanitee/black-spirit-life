import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '116 of 123 resumes after the shared window without duplicate books',
    () async {
      final f = await _Fixture.create(
        count: 123,
        limit: 98,
        window: const Duration(milliseconds: 1200),
      );
      addTearDown(f.dispose);
      await f.seedBooks(f.ids.take(18));
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      f.transport.books.clear();
      final oldTimes = {
        for (final id in f.ids.take(18))
          id: f.controller.market.items[id]!.bookFetchedAt,
      };
      f.startDemand();
      await _until(() => f.controller.detailStatus.loaded == 116);
      expect(f.controller.scanning, isTrue);
      expect(f.controller.detailStatus.total, 123);
      expect(f.controller.detailStatus.failed, 0);
      expect(f.broker.diagnostics.activeRequests, 0);
      expect(f.broker.diagnostics.queuedParts, 7);
      expect(f.transport.books, hasLength(98));
      expect(f.controller.activeDispatchWait, greaterThan(Duration.zero));
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.complete,
      );
      expect(f.transport.books, hasLength(105));
      expect(f.transport.books.toSet(), f.ids.skip(18).toSet());
      expect(f.broker.diagnostics.queuedParts, 0);
      expect(f.controller.progressFraction, isNull);
      expect(f.controller.activeDispatchWait, Duration.zero);
      expect(f.controller.failedItems, 0);
      for (final entry in oldTimes.entries) {
        expect(
          f.controller.market.items[entry.key]!.bookFetchedAt,
          entry.value,
        );
      }
      await f.settle();
      expect(
        f.transport.books,
        hasLength(105),
        reason: 'Completion must not rescan the same scope.',
      );
    },
  );

  test(
    'Stop releases queued work and sort changes cannot restart it',
    () async {
      final f = await _Fixture.create(
        count: 5,
        limit: 2,
        window: const Duration(milliseconds: 600),
      );
      addTearDown(f.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      f.startDemand();
      await _until(() => f.transport.books.length == 2);
      f.controller.cancel();
      await _until(() => !f.controller.scanning);
      expect(f.broker.diagnostics.queuedParts, 0);
      expect(f.controller.activeDispatchWait, Duration.zero);
      f.controller.change((p) => p.craftSort = 'profit');
      f.controller.change((p) => p.craftSort = 'preorders');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(f.transport.books, hasLength(2));
      expect(f.controller.detailStatus.loading, isFalse);
      expect(
        f.controller.failedItems,
        0,
        reason: 'Released work is not a failed receipt.',
      );
    },
  );

  test(
    'a hung HTTP body times out and scan settles with honest unresolved count',
    () async {
      final f = await _Fixture.create(
        timeout: const Duration(milliseconds: 80),
      );
      addTearDown(f.dispose);
      f.transport.heldId = f.ids.last;
      f.startDemand();
      await _until(() => f.transport.books.contains(f.ids.last));
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.failed == 1,
      );
      expect(f.transport.aborted, contains(f.ids.last));
      expect(f.controller.detailStatus.loaded, 2);
      expect(f.controller.detailStatus.loading, isFalse);
      expect(f.controller.detailNotice, contains('didn’t load'));
      expect(f.controller.market.items[f.ids.last]!.preorderCount, isNull);
      expect(f.controller.progressFraction, isNull);
      await f.settle();
      expect(f.transport.books, hasLength(3));
    },
  );

  test(
    'malformed final book ends the scan without pretending it has zero demand',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.malformedIds.add(f.ids.last);
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.controller.change((p) => p.demandOnly = true);
      f.controller.setWorkspaceActive(true);
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.failed == 1,
      );
      await f.settle();
      expect(
        f.controller.demandPendingCount,
        0,
        reason: 'The failed book does not erase the known stocked quote.',
      );
      expect(f.controller.visibleQuotes, hasLength(2));
      expect(f.controller.detailStatus.loading, isFalse);
      final count = f.transport.books.length;
      f.controller.recalculate();
      await f.settle();
      expect(f.transport.books, hasLength(count));
    },
  );

  test(
    'protection ends all pending work and filtering never bypasses the pause',
    () async {
      final f = await _Fixture.create(concurrency: 1);
      addTearDown(f.dispose);
      f.transport.protectedIds.add(f.ids.first);
      f.startDemand();
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.blocked,
      );
      expect(f.controller.detailStatus.failed, 3);
      expect(f.broker.diagnostics.queuedParts, 0);
      expect(f.transport.books, [f.ids.first]);
      f.now = f.now.add(const Duration(minutes: 2));
      f.controller.change((p) {
        p.craftSort = 'profit';
        p.demandOnly = true;
      });
      await f.settle();
      expect(f.transport.books, [f.ids.first]);
      expect(f.controller.visibleQuotes, isEmpty);
      expect(
        f.controller.demandPendingCount,
        0,
        reason: 'Known positive stock is excluded, not an unchecked match.',
      );
      expect(
        f.broker.pauseFor('eu')!.reason,
        MarketRequestPauseReason.protected,
      );
    },
  );

  test(
    'leaving Demand releases obsolete queued books but preserves a visible card',
    () async {
      final f = await _Fixture.create(concurrency: 1);
      addTearDown(f.dispose);
      final owner = Object();
      f.transport.heldId = f.ids.first;
      f.controller.setWorkspaceActive(true);
      f.controller.setCardMarketInterest(
        owner,
        recipeName: 'Recipe 000',
        mode: CraftMode.cooking,
      );
      await _until(() => f.transport.books.length == 1);
      f.controller.change((p) => p.craftSort = 'preorders');
      f.controller.change((p) => p.craftSort = 'profit');
      f.transport.release.complete();
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.complete,
      );
      expect(f.transport.books, [f.ids.first]);
      expect(f.transport.aborted, isEmpty);
      expect(f.controller.detailStatus.total, 1);
      expect(f.controller.failedItems, 0);
    },
  );

  test(
    'Demand excludes stocked bids and includes zero without bids in Profit order',
    () async {
      final f = await _Fixture.create(count: 4);
      addTearDown(f.dispose);
      f.transport.demands[f.ids[0]] = 100;
      f.transport.demands[f.ids[1]] = 1;
      f.transport.demands[f.ids[2]] = 200;
      f.transport.bookStocks[f.ids[2]] = 5;
      f.transport.demands[f.ids[3]] = 0;
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.controller.change((p) {
        p.demandOnly = true;
        p.readyOnly = true;
      });
      await f.controller.calculationSettled;
      expect(f.controller.visibleQuotes, isEmpty);
      expect(f.controller.demandPendingCount, 0);
      f.controller.setWorkspaceActive(true);
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.complete,
      );
      await f.settle();
      expect(f.transport.books.toSet(), f.ids.toSet());
      expect(f.controller.demandPendingCount, 0);
      expect(f.controller.visibleQuotes.map((q) => q.recipeName), [
        'Recipe 003',
        'Recipe 001',
        'Recipe 000',
      ]);
      expect(
        f.controller
            .outputMarketFor('Recipe 002')!
            .stockFor(f.now, OpportunitiesController.maxMarketAge),
        5,
        reason: 'Stock wins even when there are more preorders.',
      );
      final quoteObjects = f.controller.quotes.toList();
      f.controller.change((p) => p.craftSort = 'preorders');
      expect(f.controller.visibleQuotes.map((q) => q.recipeName), [
        'Recipe 000',
        'Recipe 001',
        'Recipe 003',
      ]);
      await f.settle();
      for (var i = 0; i < quoteObjects.length; i++) {
        expect(identical(f.controller.quotes[i], quoteObjects[i]), isTrue);
      }
      expect(f.transport.books, hasLength(4));
    },
  );

  test(
    'Demand uses latest raw scoped stock before calculation and zero needs no book',
    () async {
      final f = await _Fixture.create(count: 1);
      addTearDown(f.dispose);
      f.controller.change((p) => p.demandOnly = true);
      final id = f.ids.single;
      final initialQuote = f.controller.quotes.single;
      expect(f.controller.visibleQuotes, isEmpty);
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.transport.quoteStocks[id] = 0;
      await f.broker.fetch(quoteKeys: [f.key(id)], forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(identical(f.controller.quotes.single, initialQuote), isTrue);
      expect(f.controller.outputMarketFor('Recipe 000')!.bookFetchedAt, isNull);
      expect(f.controller.visibleQuotes, hasLength(1));
      expect(f.controller.demandPendingCount, 0);
      await f.settle();
      final zeroQuote = f.controller.quotes.single;
      expect(zeroQuote.outputMarket!.stock, 0);
      final quoteAt = f.now;

      f.now = f.now.add(const Duration(milliseconds: 1));
      f.transport.bookStocks[id] = 7;
      f.transport.demands[id] = 100;
      await f.broker.fetch(bookKeys: [f.key(id)], forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(identical(f.controller.quotes.single, zeroQuote), isTrue);
      expect(f.controller.visibleQuotes, isEmpty);
      expect(
        f.controller.outputMarketFor('Recipe 000')!.quoteFetchedAt,
        quoteAt,
      );

      f.now = f.now.add(const Duration(milliseconds: 1));
      f.transport.bookStocks[id] = 0;
      await f.broker.fetch(bookKeys: [f.key(id)], forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(f.controller.visibleQuotes, hasLength(1));
      final bookAt = f.now;
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.transport.quoteStocks[id] = 9;
      await f.broker.fetch(quoteKeys: [f.key(id)], forceRefresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        f.controller.visibleQuotes,
        isEmpty,
        reason: 'A newer stocked quote overrides the older zero-ask book.',
      );
      expect(f.controller.outputMarketFor('Recipe 000')!.bookFetchedAt, bookAt);
      expect(f.transport.books, hasLength(2));
    },
  );

  test(
    'enhanced output needs scoped stock and ignores all-level summary totals',
    () async {
      final f = await _Fixture.create(count: 1);
      addTearDown(f.dispose);
      const id = '705037';
      f.controller.recipes = {
        ...f.controller.recipes,
        'Recipe 000': _recipe('Recipe 000', id, input: 'Raw input'),
      };
      f.controller.change((p) => p.demandOnly = true);
      await f.controller.calculationSettled;
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.transport.quoteStocks[id] = 6;
      await f.broker.fetch(
        quoteKeys: [f.key(id), f.key('20001')],
        forceRefresh: true,
      );
      await Future<void>.delayed(Duration.zero);
      final summary = f.controller.outputMarketFor('Recipe 000')!;
      expect(summary.aggregateStock, 6);
      expect(
        summary.stockFor(f.now, OpportunitiesController.maxMarketAge),
        isNull,
      );
      expect(f.controller.visibleQuotes, isEmpty);
      expect(f.controller.demandPendingCount, 1);

      f.now = f.now.add(const Duration(milliseconds: 1));
      await f.broker.fetch(bookKeys: [f.key(id)]);
      await Future<void>.delayed(Duration.zero);
      expect(f.controller.visibleQuotes, hasLength(1));
      final bookAt = f.now;
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.transport.quoteStocks[id] = 9;
      await f.broker.fetch(
        quoteKeys: [f.key(id), f.key('20001')],
        forceRefresh: true,
      );
      await Future<void>.delayed(Duration.zero);
      final latest = f.controller.outputMarketFor('Recipe 000')!;
      expect(latest.aggregateStock, 9);
      expect(latest.stockFor(f.now, OpportunitiesController.maxMarketAge), 0);
      expect(latest.bookFetchedAt, bookAt);
      expect(f.controller.visibleQuotes, hasLength(1));
      expect(f.controller.demandPendingCount, 0);
      expect(f.transport.books, [id]);
    },
  );

  test(
    'search and available-input filters bound demand loading before strict filtering',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.controller.change((p) {
        p.demandOnly = true;
        p.readyOnly = true;
        p.craftSearch = '001';
      });
      await f.controller.calculationSettled;
      expect(f.controller.demandPendingCount, 0);
      f.controller.setWorkspaceActive(true);
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.complete,
      );
      await f.settle();
      expect(f.transport.books, [f.ids[1]]);
      expect(f.controller.visibleQuotes.single.recipeName, 'Recipe 001');
      // A real one-craft ingredient shortage, not a retired global quantity,
      // removes the row and its output demand scope.
      f.transport.quoteStocks['20001'] = 0;
      f.now = f.now.add(const Duration(milliseconds: 1));
      await f.broker.fetch(quoteKeys: [f.key('20001')], forceRefresh: true);
      await f.settle();
      expect(f.controller.visibleQuotes, isEmpty);
      expect(f.controller.demandPendingCount, 0);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.transport.books, [f.ids[1]]);
    },
  );

  test(
    'nonmarket and unmapped outputs are neither pending checks nor demand matches',
    () async {
      final f = await _Fixture.create(count: 1, seedOutputQuotes: false);
      addTearDown(f.dispose);
      f.transport.quoteStocks[f.ids.single] = 0;
      f.controller.recipes = {
        ...f.controller.recipes,
        'Custom no ID': _recipe('Custom no ID', null, input: 'Raw input'),
        'Reviewed nonmarket': _recipe(
          'Reviewed nonmarket',
          '5303',
          input: 'Raw input',
        ),
        'Archived': _recipe('Archived', '6211', input: 'Raw input'),
      };
      f.controller.recalculate();
      await f.controller.calculationSettled;
      // Simulate imported/synthetic cached bids. A source-reviewed nonmarket
      // identity is still not an eligible Demand result or request target.
      await f.seedBooks(['5303']);
      final nonmarket = f.controller.quotes.singleWhere(
        (quote) => quote.recipeName == 'Reviewed nonmarket',
      );
      expect(nonmarket.outputMarket!.preorderCount, 3);
      expect(f.controller.visibleQuotes, hasLength(4));
      f.controller.change((p) => p.demandOnly = true);
      expect(f.controller.visibleQuotes, isEmpty);
      expect(f.controller.demandPendingCount, 1);
      f.controller.setWorkspaceActive(true);
      await _until(
        () => !f.controller.scanning && f.controller.detailStatus.complete,
      );
      await f.settle();
      expect(f.transport.books, ['5303', f.ids.single]);
      expect(f.controller.detailStatus.total, 1);
      expect(f.controller.demandPendingCount, 0);
      expect(f.controller.visibleQuotes.single.recipeName, 'Recipe 000');
      f.controller.change((p) {
        p.demandOnly = false;
        p.craftSort = 'preorders';
      });
      expect(f.controller.visibleQuotes, hasLength(4));
      expect(
        identical(
          f.controller.quotes.singleWhere(
            (q) => q.recipeName == 'Reviewed nonmarket',
          ),
          nonmarket,
        ),
        isTrue,
        reason: 'Ordinary sort and price calculations are unchanged.',
      );
    },
  );

  test(
    'stale and future books are not demand matches and hiding tab adds no requests',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.seedBooks(f.ids);
      f.controller.change((p) => p.demandOnly = true);
      expect(f.controller.visibleQuotes, hasLength(3));
      final receiptAt = f.now;
      f.now = receiptAt.add(const Duration(hours: 3, milliseconds: 1));
      f.controller.recalculate();
      await f.controller.calculationSettled;
      expect(f.controller.visibleQuotes, isEmpty);
      expect(f.controller.demandPendingCount, 3);
      f.now = receiptAt.subtract(const Duration(seconds: 1));
      f.controller.recalculate();
      await f.controller.calculationSettled;
      expect(f.controller.visibleQuotes, isEmpty);
      expect(f.controller.demandPendingCount, 3);
      expect(f.transport.books, hasLength(3));
    },
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _Fixture {
  _Fixture(this.harness, this.ids);
  final ApplicationTestHarness harness;
  final List<String> ids;
  DateTime now = DateTime.utc(2026, 9, 13, 9);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;

  static Future<_Fixture> create({
    int count = 3,
    int? limit,
    Duration window = const Duration(minutes: 1),
    Duration timeout = const Duration(seconds: 5),
    int concurrency = 20,
    bool seedOutputQuotes = true,
  }) async {
    final f = _Fixture(await ApplicationTestHarness.create(), [
      // Deliberately unknown ordinary IDs: do not borrow the enhancement
      // scope of real equipment IDs for a single-tier material fixture.
      for (var i = 0; i < count; i++) '${990001 + i}',
    ]);
    f.transport = _Transport(() => f.now);
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      quoteBatchSize: 200,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      requestWindowLimit: limit,
      requestWindowDuration: window,
      requestTimeout: timeout,
      concurrency: concurrency,
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      sharedMarket: f.broker,
      clock: () => f.now,
    );
    await f.controller.ready;
    f.controller.change((p) {
      p.mode = CraftMode.cooking;
      p.profitableOnly = false;
      p.crafts = 1;
    }, assemble: true);
    await f.controller.calculationSettled;
    f.controller.recipes = {
      for (var i = 0; i < count; i++)
        'Recipe ${i.toString().padLeft(3, '0')}': _recipe(
          'Recipe ${i.toString().padLeft(3, '0')}',
          f.ids[i],
          input: 'Raw input',
        ),
      'Raw input': _recipe('Raw input', '20001'),
    };
    f.controller.recalculate();
    await f.controller.calculationSettled;
    await f.broker.fetch(
      quoteKeys: [
        for (final id in [if (seedOutputQuotes) ...f.ids, '20001']) f.key(id),
      ],
    );
    await f.settle();
    return f;
  }

  SharedMarketKey key(String id) => SharedMarketKey(region: 'eu', itemId: id);
  void startDemand() {
    controller.change((p) => p.craftSort = 'preorders');
    controller.setWorkspaceActive(true);
  }

  Future<void> seedBooks(Iterable<String> ids) async {
    now = now.add(const Duration(milliseconds: 1));
    await broker.fetch(bookKeys: ids.map(key));
    await settle();
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await controller.calculationSettled;
  }

  Future<void> dispose() async {
    controller.cancel();
    if (!transport.release.isCompleted) transport.release.complete();
    await broker.close();
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

Recipe _recipe(String name, String? id, {String? input}) => Recipe(
  name: name,
  type: input == null ? 'gathered' : 'cooking',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    if (input != null)
      Ingredient(
        name: input,
        quantity: 1,
        options: const [],
        substituteGroup: null,
        substituteRatios: const {},
      ),
  ],
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 2,
  outputMaximum: 2,
);

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.now);
  final DateTime Function() now;
  final List<String> books = [];
  final Set<String> aborted = {};
  final Set<String> malformedIds = {};
  final Set<String> protectedIds = {};
  final Map<String, int> demands = {};
  final Map<String, int> quoteStocks = {};
  final Map<String, int> bookStocks = {};
  String? heldId;
  final release = Completer<void>();

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final ids = payload['searchResult'] is String
        ? (payload['searchResult'] as String).split(',')
        : ['${payload['mainKey']}'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    if (book) {
      books.add(ids.single);
      if (ids.single == heldId && !release.isCompleted) {
        await Future.any([
          release.future,
          if (abortTrigger != null)
            abortTrigger.then((_) {
              aborted.add(ids.single);
              throw const MarketFetchCancelledException();
            }),
        ]);
      }
      if (protectedIds.contains(ids.single)) {
        return OpportunityHttpResponse(
          statusCode: 200,
          bytes: Uint8List.fromList(
            utf8.encode('<html>Incapsula incident ID</html>'),
          ),
        );
      }
      if (malformedIds.contains(ids.single)) {
        return OpportunityHttpResponse(
          statusCode: 200,
          bytes: Uint8List.fromList(utf8.encode('invalid order book')),
        );
      }
    }
    int price(String id) => id == '20001'
        ? 10
        : id == '5303' || id == '705037'
        ? 1000
        : (int.parse(id) - 990000) * 1000;
    final text = ids.length > 1
        ? ids
              .map((id) => '$id-${quoteStocks[id] ?? 100}-${price(id)}-500000')
              .join('|')
        : book
        ? '${price(ids.single)}-${bookStocks[ids.single] ?? 0}-${demands[ids.single] ?? 3}|'
        : '${ids.single}-0-0-${price(ids.single)}-${quoteStocks[ids.single] ?? 100}-500000-1-1000000-${price(ids.single)}-${now().millisecondsSinceEpoch ~/ 1000}|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': text})),
      ),
    );
  }

  @override
  void close() {}
}
