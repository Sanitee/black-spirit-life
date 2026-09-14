import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final all in [false, true]) {
    test(
      '${all ? 'global' : 'selected'} manual Refresh overlaps books with held quotes without a second force',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.controller.ensureMarketDepth(['9101']);
        f.now = f.now.add(const Duration(seconds: 61));
        final bookTime = f.now;
        final held = f.transport.hold(_part('9201', SharedMarketPart.quote));
        f.transport.requests.clear();
        final loading = all
            ? f.controller.refreshAll(onlyStale: false)
            : f.controller.refresh();
        await held.entered.future;
        await _until(
          () => f.controller.market.items['9101']!.bookFetchedAt == bookTime,
        );
        expect(f.controller.scanning, isTrue);
        expect(f.controller.detailStatus.complete, isTrue);
        // The request takes longer than both reuse windows, but its already
        // resolved book must not be forced again when the quote finally arrives.
        f.now = f.now.add(const Duration(seconds: 70));
        held.release.complete();
        await loading;
        await f.controller.ensureMarketDepth(['9101']);
        expect(f.transport.books, ['9101']);
        expect(
          f.transport.quotes.toSet(),
          containsAll(['9101', '9102', '9201', '9202']),
        );
        expect(f.transport.quotes.length, f.transport.quotes.toSet().length);
        if (all) expect(f.transport.quotes.length, greaterThan(4));
        expect(f.controller.market.items['9101']!.bookFetchedAt, bookTime);
        expect(f.controller.market.items['9201']!.quoteFetchedAt, f.now);
        expect(f.controller.summaryStatus.complete, isTrue);
        expect(f.controller.failedItems, 0);
      },
    );
  }

  test(
    'a young required book keeps the whole fresh toolbar reload disabled',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.now = f.now.add(const Duration(seconds: 30));
      await f.controller.ensureMarketDepth(['9101']);
      final bookTime = f.controller.market.items['9101']!.bookFetchedAt;
      f.now = f.now.add(const Duration(seconds: 59));
      f.transport.requests.clear();
      expect(f.controller.refreshReadiness.wait, const Duration(seconds: 1));
      await f.controller.refresh();
      expect(f.transport.books, isEmpty);
      expect(f.transport.quotes, isEmpty);
      expect(f.controller.market.items['9101']!.bookFetchedAt, bookTime);
      expect(f.controller.detailStatus.complete, isTrue);
      f.now = f.now.add(const Duration(seconds: 1));
      await f.controller.refresh();
      expect(f.transport.books, ['9101']);
      expect(f.transport.quotes.toSet(), {'9101', '9102', '9201', '9202'});
    },
  );

  test(
    'closing depth releases its held book but preserves every quote in the combined call',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.ensureMarketDepth(['9101']);
      final oldBook = f.controller.market.items['9101']!.bookFetchedAt;
      f.now = f.now.add(const Duration(seconds: 61));
      final quotePart = _part('9201', SharedMarketPart.quote);
      final bookPart = _part('9101', SharedMarketPart.orderBook);
      final quote = f.transport.hold(quotePart);
      final book = f.transport.hold(bookPart);
      f.transport.requests.clear();
      final loading = f.controller.refresh();
      await Future.wait([quote.entered.future, book.entered.future]);
      await f.controller.ensureMarketDepth([]);
      await _until(() => f.transport.aborted.contains(bookPart));
      expect(f.transport.aborted, isNot(contains(quotePart)));
      quote.release.complete();
      await loading;
      expect(f.transport.quotes.toSet(), {'9101', '9102', '9201', '9202'});
      expect(f.controller.summaryStatus.complete, isTrue);
      expect(f.controller.detailStatus.total, 0);
      expect(f.controller.market.items['9101']!.bookFetchedAt, oldBook);
      expect(f.controller.failedItems, 0);
    },
  );

  test(
    'changed prices force only newly profitable Demand outputs after calculations settle',
    () async {
      final f = await _Fixture.create(secondPrice: 10);
      addTearDown(f.dispose);
      f.controller.change((p) {
        p.craftSort = 'preorders';
        p.profitableOnly = true;
      });
      f.controller.setWorkspaceActive(true);
      await f.controller.calculationSettled;
      await f.controller.ensureMarketDepth([]);
      expect(f.controller.visibleQuotes.map((q) => q.recipeName), ['First']);
      // A previously viewed, still three-hour-valid book is nevertheless due for
      // this manual refresh once its output becomes newly profitable.
      await f.broker.fetch(
        bookKeys: [_part('9102', SharedMarketPart.orderBook).key],
      );
      f.now = f.now.add(const Duration(seconds: 61));
      f.transport.prices['9102'] = 1000;
      f.transport.requests.clear();
      await f.controller.refresh();
      await f.controller.ensureMarketDepth([]);
      expect(f.controller.visibleQuotes.map((q) => q.recipeName).toSet(), {
        'First',
        'Second',
      });
      expect(f.transport.books, ['9101', '9102']);
      expect(f.transport.quotes.toSet(), {'9101', '9102', '9201', '9202'});
      expect(f.controller.market.items['9102']!.bookFetchedAt, f.now);
      expect(f.controller.detailStatus.complete, isTrue);
    },
  );

  for (final boundary in ['Stop', 'flush', 'region', 'dispose']) {
    test(
      '$boundary prevents a queued newly active book from following a manual refresh',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.controller.ensureMarketDepth(['9101']);
        f.now = f.now.add(const Duration(seconds: 61));
        final quote = f.transport.hold(_part('9201', SharedMarketPart.quote));
        f.transport.requests.clear();
        final loading = f.controller.refresh();
        await quote.entered.future;
        final addition = f.controller.ensureMarketDepth(['9101', '9102']);
        switch (boundary) {
          case 'Stop':
            f.controller.cancel();
          case 'flush':
            await f.controller.flush();
          case 'region':
            f.controller.change((p) => p.region = 'na');
          case 'dispose':
            f.controller.dispose();
            f.controllerDisposed = true;
        }
        await loading;
        await addition;
        expect(f.transport.books, isNot(contains('9102')));
        expect(
          f.transport.requests.any((part) => part.key.region == 'na'),
          isFalse,
        );
        expect(
          f.transport.aborted,
          contains(_part('9201', SharedMarketPart.quote)),
        );
      },
    );
  }
}

SharedMarketPartKey _part(
  String id,
  SharedMarketPart part, {
  String region = 'eu',
}) => SharedMarketPartKey(SharedMarketKey(region: region, itemId: id), part);

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 11, 12);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;
  bool controllerDisposed = false;

  static Future<_Fixture> create({int secondPrice = 1000}) async {
    final f = _Fixture(await ApplicationTestHarness.create());
    f.transport = _Transport()..prices['9102'] = secondPrice;
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      quoteBatchSize: 100,
      concurrency: 20,
      primeSession: true,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      minimumBookRefreshAge: const Duration(minutes: 1),
      minimumQuoteRefreshAge: const Duration(minutes: 1),
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      clock: () => f.now,
      sharedMarket: f.broker,
      autoCheck: false,
      prefetchAll: false,
    );
    await f.controller.ready;
    f.controller.recipes = {
      'First': _recipe('First', '9101', input: 'Raw A'),
      'Second': _recipe('Second', '9102', input: 'Raw B'),
      'Raw A': _recipe('Raw A', '9201'),
      'Raw B': _recipe('Raw B', '9202'),
    };
    f.controller.recalculate();
    await f.controller.calculationSettled;
    await f.controller.refresh();
    return f;
  }

  Future<void> dispose() async {
    for (final hold in transport.holds.values) {
      if (!hold.release.isCompleted) hold.release.complete();
    }
    if (!controllerDisposed) controller.cancel();
    await broker.close();
    await controller.calculationSettled;
    await controller.flush();
    if (!controllerDisposed) {
      controller.dispose();
    }
    await harness.dispose();
  }
}

Recipe _recipe(String name, String id, {String? input}) => Recipe(
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

final class _Hold {
  final entered = Completer<void>();
  final release = Completer<void>();
}

final class _Transport implements OpportunityMarketTransport {
  final requests = <SharedMarketPartKey>[];
  final holds = <SharedMarketPartKey, _Hold>{};
  final aborted = <SharedMarketPartKey>{};
  final prices = <String, int>{
    '9101': 1000,
    '9102': 1000,
    '9201': 100,
    '9202': 100,
  };
  _Hold hold(SharedMarketPartKey part) => holds[part] = _Hold();
  List<String> get books => [
    for (final part in requests)
      if (part.part == SharedMarketPart.orderBook) part.key.itemId,
  ];
  List<String> get quotes => [
    for (final part in requests)
      if (part.part == SharedMarketPart.quote) part.key.itemId,
  ];

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final ids = payload['searchResult'] is String
        ? (payload['searchResult'] as String).split(',')
        : ['${payload['mainKey']}'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    final region = uri.host.startsWith('na-') ? 'na' : 'eu';
    final parts = [
      for (final id in ids)
        _part(
          id,
          book ? SharedMarketPart.orderBook : SharedMarketPart.quote,
          region: region,
        ),
    ];
    requests.addAll(parts);
    for (final part in parts) {
      final hold = holds[part];
      if (hold == null || hold.release.isCompleted) continue;
      if (!hold.entered.isCompleted) hold.entered.complete();
      await Future.any([
        hold.release.future,
        if (abortTrigger != null)
          abortTrigger.then((_) {
            aborted.addAll(parts);
            throw const MarketFetchCancelledException();
          }),
      ]);
    }
    final message = book
        ? '1000-10000-0|900-0-7'
        : ids.length > 1
        ? ids.map((id) => '$id-1000-${prices[id] ?? 1000}-10000').join('|')
        : '${ids.single}-0-0-${prices[ids.single] ?? 1000}-1000-10000';
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

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'Expected the controlled market phase.');
}
