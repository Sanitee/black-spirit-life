import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_pause_store.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final ageSeconds in [59, 60]) {
    test(
      'toolbar minute-policy Refresh at ${ageSeconds}s waits or loads genuinely new parts',
      () async {
        final fixture = await _Fixture.create(
          minimumQuoteRefreshAge: const Duration(minutes: 1),
          minimumBookRefreshAge: const Duration(minutes: 1),
        );
        addTearDown(fixture.dispose);
        await fixture.controller.refresh();
        await fixture.controller.ensureMarketDepth(['9101']);
        final original = fixture.now;
        fixture.now = fixture.now.add(Duration(seconds: ageSeconds));
        fixture.transport.requests.clear();
        expect(
          fixture.controller.refreshReadiness.canRefresh,
          ageSeconds >= 60,
        );
        await fixture.controller.refresh();
        final reused = ageSeconds < 60;
        expect(fixture.transport.requests, hasLength(reused ? 0 : 5));
        if (!reused) {
          expect(
            fixture.transport.requests.where(
              (part) => part.part == SharedMarketPart.orderBook,
            ),
            [_part('9101', SharedMarketPart.orderBook)],
          );
        }
        final item = fixture.controller.market.items['9101']!;
        expect(item.quoteFetchedAt, reused ? original : fixture.now);
        expect(item.bookFetchedAt, reused ? original : fixture.now);
        expect(item.preorderCount, 0);
        expect(fixture.controller.summaryStatus.complete, isTrue);
        expect(fixture.controller.detailStatus.complete, isTrue);
        expect(fixture.controller.failedItems, 0);
        expect(fixture.controller.notice, isNull);
      },
    );
  }

  test(
    'a backward clock correction cannot clear failures through disabled Refresh',
    () async {
      final fixture = await _Fixture.create(
        minimumQuoteRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      final original = fixture.now;
      final quote = _part('9101', SharedMarketPart.quote);
      final quotes = fixture.transport.requests.toSet();
      fixture.now = original.add(const Duration(seconds: 60));
      fixture.transport.failures.addAll(quotes);
      await fixture.controller.refresh();
      expect(fixture.controller.failedItems, 4);
      expect(fixture.controller.market.items['9101']!.quoteFetchedAt, original);
      // The clock correction makes the retained receipt younger than one minute.
      // A disabled toolbar call cannot pretend to deliver a successful receipt.
      fixture.now = original.add(const Duration(seconds: 59));
      fixture.transport.requests.clear();
      expect(fixture.controller.refreshReadiness.canRefresh, isFalse);
      await fixture.controller.refresh();
      expect(fixture.transport.requests, isEmpty);
      expect(fixture.controller.failedItems, 4);
      expect(fixture.controller.market.items['9101']!.quoteFetchedAt, original);
      fixture.now = original.add(const Duration(seconds: 121));
      fixture.transport.requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests, contains(quote));
      expect(fixture.controller.failedItems, 4);
      expect(fixture.controller.market.items['9101']!.quoteFetchedAt, original);
      fixture.now = original.add(const Duration(seconds: 122));
      fixture.transport
        ..failures.clear()
        ..requests.clear();
      expect(fixture.controller.refreshReadiness.canRefresh, isTrue);
      await fixture.controller.refresh();
      expect(fixture.transport.requests.toSet(), quotes);
      expect(fixture.controller.failedItems, 0);
      expect(
        fixture.controller.market.items['9101']!.quoteFetchedAt,
        fixture.now,
      );
    },
  );

  test(
    'minute-policy Refresh still requests missing quotes and preserves real failures',
    () async {
      final fixture = await _Fixture.create(
        minimumQuoteRefreshAge: const Duration(minutes: 1),
        minimumBookRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(fixture.dispose);
      final quote = _part('9101', SharedMarketPart.quote);
      fixture.transport.failures.add(quote);
      await fixture.controller.refresh();
      expect(fixture.controller.failedItems, 1);
      expect(fixture.controller.market.items['9101']?.quoteFetchedAt, isNull);
      fixture.now = fixture.now.add(const Duration(seconds: 30));
      fixture.transport.requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests, [quote]);
      expect(fixture.controller.failedItems, 1);
      expect(fixture.controller.market.items['9101']?.quoteFetchedAt, isNull);
      fixture.transport.failures.clear();
      fixture.transport.requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests, [quote]);
      expect(fixture.controller.failedItems, 0);
      expect(
        fixture.controller.market.items['9101']!.quoteFetchedAt,
        fixture.now,
      );
    },
  );

  test(
    'toolbar recovers all startup failures from another selected pane',
    () async {
      final fixture = await _Fixture.create(startup: true);
      addTearDown(fixture.dispose);
      await _until(
        () =>
            fixture.transport.requests.isNotEmpty &&
            !fixture.controller.scanning &&
            fixture.controller.failedItems == 2,
      );
      final controller = fixture.controller;
      final before = fixture.harness.bundle.controller.documentSnapshot;
      final startupRequests = fixture.transport.requests.toSet();
      expect(startupRequests, containsAll(fixture.startupFailures));
      expect(startupRequests.length, greaterThan(1000));
      expect(
        startupRequests.every((part) => part.part == SharedMarketPart.quote),
        isTrue,
        reason: 'Startup covers all price summaries without requesting books.',
      );
      expect(
        fixture.transport.requests.length,
        startupRequests.length,
        reason: 'All modes and currencies share one request per item/part.',
      );
      controller.change((p) {
        p.section = 'crafting';
        p.mode = CraftMode.cooking;
      }, assemble: true);
      controller.cancel();
      fixture.transport
        ..failures.clear()
        ..requests.clear();
      fixture.now = fixture.now.add(const Duration(seconds: 1));
      await controller.refresh();
      expect(fixture.transport.requests.toSet(), fixture.startupFailures);
      expect(fixture.transport.requests, hasLength(2));
      expect(controller.failedItems, 0);
      expect(controller.notice, isNull);
      expect(controller.preferences.mode, CraftMode.cooking);
      expect(fixture.harness.bundle.controller.documentSnapshot, same(before));
    },
  );

  test(
    'partial failures count an item once and retry only its failed part',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final price = _part('9101', SharedMarketPart.quote);
      final stock = _part('9101', SharedMarketPart.orderBook);
      fixture.transport.failures.addAll([price, stock]);
      await fixture.controller.refresh();
      await fixture.controller.ensureMarketDepth(['9101']);
      expect(fixture.controller.failedItems, 1);
      expect(
        fixture.controller.notice,
        'Market data didn’t load for 1 item. Try Refresh.',
      );
      fixture.transport.failures.remove(price);
      fixture.now = fixture.now.add(const Duration(seconds: 1));
      await fixture.broker.fetch(quoteKeys: [price.key], forceRefresh: true);
      await _until(
        () =>
            fixture.controller.notice ==
            'Buy/sell orders didn’t load for 1 item. Try Refresh.',
      );
      expect(fixture.controller.failedItems, 1);
      fixture.transport
        ..failures.clear()
        ..requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests, [stock]);
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.notice, isNull);
    },
  );

  test(
    'sibling recovery clears the banner before an all-fresh check',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final stock = _part('9101', SharedMarketPart.orderBook);
      fixture.transport.failures.add(stock);
      await fixture.controller.refresh();
      await fixture.controller.ensureMarketDepth(['9101']);
      expect(fixture.controller.failedItems, 1);
      fixture.transport.failures.clear();
      fixture.now = fixture.now.add(const Duration(seconds: 1));
      await fixture.broker.fetch(bookKeys: [stock.key], forceRefresh: true);
      await _until(() => fixture.controller.notice == null);
      fixture.transport.requests.clear();
      await fixture.controller.refresh(onlyStale: true);
      expect(fixture.transport.requests, isEmpty);
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.notice, isNull);
    },
  );

  test('old fresh cache cannot hide a failed force refresh', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final price = _part('9101', SharedMarketPart.quote);
    await fixture.controller.refresh();
    final oldReceipt = fixture.controller.market.items['9101']!.quoteFetchedAt;
    fixture.now = fixture.now.add(const Duration(minutes: 1));
    fixture.transport.failures.add(price);
    await fixture.controller.refresh();
    expect(fixture.controller.failedItems, 1);
    expect(
      fixture.controller.notice,
      'Prices didn’t load for 1 item. Try Refresh.',
    );
    expect(fixture.controller.market.items['9101']!.quoteFetchedAt, oldReceipt);
    fixture.transport.requests.clear();
    await fixture.broker.fetch(quoteKeys: [price.key]);
    await fixture.controller.refresh(onlyStale: true);
    expect(fixture.transport.requests, isEmpty);
    expect(fixture.controller.failedItems, 1);
    expect(fixture.controller.notice, isNotNull);
    fixture.transport.failures.clear();
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.controller.refresh();
    expect(
      fixture.transport.requests,
      [price],
      reason: 'Explicit recovery bypasses the recent failure cooldown.',
    );
    expect(fixture.controller.failedItems, 0);
    expect(fixture.controller.notice, isNull);
  });

  test('failures and successful receipts stay in their own region', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final stock = _part('9101', SharedMarketPart.orderBook);
    fixture.transport.failures.add(stock);
    await fixture.controller.refresh();
    await fixture.controller.ensureMarketDepth(['9101']);
    expect(fixture.controller.failedItems, 1);
    fixture.controller.change((p) => p.region = 'na');
    expect(fixture.controller.failedItems, 0);
    expect(fixture.controller.notice, isNull);
    await fixture.controller.refresh();
    fixture.controller.change((p) => p.region = 'eu');
    await fixture.controller.ensureMarketDepth(['9101']);
    expect(fixture.controller.failedItems, 1);
    expect(
      fixture.controller.notice,
      'Buy/sell orders didn’t load for 1 item. Try Refresh.',
    );
    fixture.transport
      ..failures.clear()
      ..requests.clear();
    fixture.now = fixture.now.add(const Duration(seconds: 1));
    await fixture.controller.refresh();
    expect(fixture.transport.requests, [stock]);
    expect(fixture.controller.failedItems, 0);
  });

  test(
    'old-region scan completion cannot put its failure on the new region',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final stock = _part('9101', SharedMarketPart.orderBook);
      fixture.transport
        ..failures.add(stock)
        ..heldPart = stock;
      await fixture.controller.refresh();
      final scan = fixture.controller.ensureMarketDepth(['9101']);
      await fixture.transport.held.future;
      fixture.controller.change((p) => p.region = 'na');
      fixture.transport.release.complete();
      await scan;
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.notice, isNull);
      fixture.controller.change((p) => p.region = 'eu');
      expect(
        fixture.controller.failedItems,
        0,
        reason:
            'Changing region cancels the old request, rather than recording a failure.',
      );
      expect(fixture.controller.market.items['9101']?.bookFetchedAt, isNull);
      expect(fixture.controller.notice, 'Stopped. Loaded prices are kept.');
    },
  );

  test(
    'Stop keeps recovered parts and the remaining failure for the next retry',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final first = _part('9101', SharedMarketPart.quote);
      final second = _part('9102', SharedMarketPart.quote);
      fixture.transport.failures.addAll([first, second]);
      await fixture.controller.refresh();
      expect(fixture.controller.failedItems, 2);
      fixture.transport
        ..failures.clear()
        ..heldPart = second;
      fixture.now = fixture.now.add(const Duration(seconds: 1));
      final retry = fixture.controller.refresh();
      await fixture.transport.held.future;
      await _until(() => fixture.controller.failedItems == 1);
      fixture.controller.cancel();
      await retry;
      expect(fixture.controller.notice, 'Stopped. Loaded prices are kept.');
      expect(fixture.controller.market.items['9101']!.basePrice, 1000);
      expect(fixture.controller.failedItems, 1);
      fixture.transport.release.complete();
      fixture.transport.requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests, [second]);
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.notice, isNull);
    },
  );

  test(
    'protective block is not bypassed by repeated toolbar recovery',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      final oldPrice = fixture.controller.market.items['9101']!.basePrice;
      fixture.transport.protectedResponse = true;
      fixture.now = fixture.now.add(const Duration(seconds: 1));
      await fixture.controller.refresh();
      expect(
        fixture.controller.notice,
        'Market access is blocked. Loaded prices are kept.',
      );
      expect(fixture.controller.failedItems, greaterThan(0));
      expect(fixture.controller.market.items['9101']!.basePrice, oldPrice);
      final requestCount = fixture.transport.requests.length;
      final pause = fixture.broker.pauseFor('eu');
      fixture.transport.protectedResponse = false;
      expect(fixture.controller.refreshReadiness.canRefresh, isFalse);
      await fixture.controller.refresh();
      await fixture.controller.refresh();
      expect(fixture.transport.requests.length, requestCount);
      expect(fixture.broker.pauseFor('eu'), same(pause));
      expect(
        fixture.controller.notice,
        'Market access is blocked. Loaded prices are kept.',
      );
      fixture.now = fixture.now.add(const Duration(seconds: 61));
      expect(fixture.controller.refreshReadiness.canRefresh, isTrue);
      await fixture.controller.refresh();
      expect(fixture.transport.requests.length, greaterThan(requestCount));
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.notice, isNull);
    },
  );

  test(
    'restored protection is labelled earlier until a new denial arrives',
    () async {
      final savedPause = MarketRequestPause(
        reason: MarketRequestPauseReason.protected,
        retryAt: DateTime.utc(2026, 9, 10, 11),
      );
      final fixture = await _Fixture.create(savedPause: savedPause);
      addTearDown(fixture.dispose);
      await fixture.controller.refresh(onlyStale: true);
      expect(fixture.transport.requests, isEmpty);
      expect(
        fixture.controller.notice,
        'Market access was blocked earlier. Prices are kept. Try Refresh.',
      );
      final restored = fixture.broker.pauseFor('eu');
      expect(restored!.retryAt, savedPause.retryAt);
      fixture.transport.protectedResponse = true;
      await fixture.controller.refresh();
      expect(fixture.transport.requests, isNotEmpty);
      expect(fixture.broker.pauseFor('eu'), isNot(same(restored)));
      expect(
        fixture.controller.notice,
        'Market access is blocked. Loaded prices are kept.',
      );
    },
  );

  test(
    'without failures manual Refresh still force-refreshes the selected scope',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      final firstRequests = fixture.transport.requests.toSet();
      expect(firstRequests, hasLength(4));
      expect(
        firstRequests.every((part) => part.part == SharedMarketPart.quote),
        isTrue,
      );
      fixture.transport.requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests.toSet(), firstRequests);
      expect(fixture.transport.requests, hasLength(4));
      expect(fixture.controller.notice, isNull);
    },
  );

  for (final ageMilliseconds in [59999, 60000, 61000]) {
    test(
      'toolbar Refresh at ${ageMilliseconds}ms waits for its youngest requested part',
      () async {
        final fixture = await _Fixture.create(
          minimumBookRefreshAge: const Duration(minutes: 1),
        );
        addTearDown(fixture.dispose);
        await fixture.controller.refresh();
        await fixture.controller.ensureMarketDepth(['9101']);
        final original = fixture.controller.market.items['9101']!.bookFetchedAt;
        expect(fixture.controller.market.items['9101']!.preorderCount, 0);
        fixture.now = fixture.now.add(Duration(milliseconds: ageMilliseconds));
        fixture.transport.requests.clear();
        final waiting = ageMilliseconds < 60000;
        expect(fixture.controller.refreshReadiness.canRefresh, !waiting);
        await fixture.controller.refresh();
        expect(
          fixture.transport.requests.where(
            (part) => part.part == SharedMarketPart.quote,
          ),
          hasLength(waiting ? 0 : 4),
        );
        expect(
          fixture.transport.requests.where(
            (part) => part.part == SharedMarketPart.orderBook,
          ),
          waiting ? isEmpty : [_part('9101', SharedMarketPart.orderBook)],
        );
        final item = fixture.controller.market.items['9101']!;
        expect(item.quoteFetchedAt, waiting ? original : fixture.now);
        expect(item.bookFetchedAt, waiting ? original : fixture.now);
        expect(item.preorderCount, 0);
        expect(fixture.controller.summaryStatus.complete, isTrue);
        expect(fixture.controller.detailStatus.complete, isTrue);
        expect(fixture.controller.failedItems, 0);
        expect(fixture.controller.notice, isNull);
      },
    );
  }

  test(
    'failed-quote recovery leaves the recent successful book untouched',
    () async {
      final fixture = await _Fixture.create(
        minimumBookRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(fixture.dispose);
      final quote = _part('9101', SharedMarketPart.quote);
      final book = _part('9101', SharedMarketPart.orderBook);
      fixture.transport.failures.add(quote);
      await fixture.controller.refresh();
      await fixture.controller.ensureMarketDepth(['9101']);
      final originalBook =
          fixture.controller.market.items['9101']!.bookFetchedAt;
      expect(originalBook, fixture.now);
      expect(fixture.controller.summaryStatus.failed, 1);
      fixture.now = fixture.now.add(const Duration(seconds: 30));
      fixture.transport.failures.addAll([quote, book]);
      fixture.transport.requests.clear();
      expect(fixture.controller.refreshReadiness.canRefresh, isTrue);
      await fixture.controller.refresh();
      expect(fixture.transport.requests, [quote]);
      expect(fixture.controller.summaryStatus.failed, 1);
      expect(fixture.controller.detailStatus.failed, 0);
      expect(fixture.controller.detailStatus.complete, isTrue);
      expect(
        fixture.controller.market.items['9101']!.bookFetchedAt,
        originalBook,
      );
      fixture.now = fixture.now.add(const Duration(seconds: 5));
      fixture.transport.failures.clear();
      fixture.transport.requests.clear();
      await fixture.controller.refresh();
      expect(fixture.transport.requests, [quote]);
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.detailStatus.complete, isTrue);
      expect(
        fixture.controller.market.items['9101']!.quoteFetchedAt,
        fixture.now,
      );
      expect(
        fixture.controller.market.items['9101']!.bookFetchedAt,
        originalBook,
      );
    },
  );
}

SharedMarketPartKey _part(
  String id,
  SharedMarketPart part, {
  String region = 'eu',
}) => SharedMarketPartKey(SharedMarketKey(region: region, itemId: id), part);

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 10, 12);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;
  final Set<SharedMarketPartKey> startupFailures = {};

  static Future<_Fixture> create({
    bool startup = false,
    MarketRequestPause? savedPause,
    Duration minimumQuoteRefreshAge = Duration.zero,
    Duration minimumBookRefreshAge = Duration.zero,
  }) async {
    final fixture = _Fixture(await ApplicationTestHarness.create());
    fixture.transport = _Transport(() => fixture.now);
    MarketPauseStore? pauseStore;
    if (savedPause != null) {
      pauseStore = MarketPauseStore(
        directory: fixture.harness.temporaryDirectory,
      );
      await pauseStore.save({'eu': savedPause});
    }
    if (startup) {
      final processingId = fixture
          .harness
          .bundle
          .catalog
          .processing
          .items
          .values
          .where(
            (recipe) =>
                recipe.isCraftable &&
                recipe.marketId != null &&
                isOpportunityMarketRequestEligible(recipe.marketId!),
          )
          .first
          .marketId!;
      final exchangeId = exchangeCatalog
          .expand((currency) => currency.routes)
          .expand((route) => route.rewards)
          .where(
            (reward) =>
                reward.item?.marketable == true &&
                '${reward.item!.id}' != processingId &&
                isOpportunityMarketRequestEligible('${reward.item!.id}'),
          )
          .first
          .item!
          .id;
      fixture.startupFailures.addAll([
        _part(processingId, SharedMarketPart.quote),
        _part('$exchangeId', SharedMarketPart.quote),
      ]);
      fixture.transport.failures.addAll(fixture.startupFailures);
      await OpportunitiesPreferenceStore(
        fixture.harness.temporaryDirectory,
      ).save(
        OpportunitiesPreferences()
          ..section = 'exchanges'
          ..currencyId = 'witchs-delicacy',
      );
    }
    fixture.broker = SharedMarketRepository(
      transport: fixture.transport,
      pauseStore: pauseStore,
      utcNow: () => fixture.now,
      quoteBatchSize: startup ? 40 : 1,
      // This suite tests selection/recovery, not real-time request pacing.
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      minimumBookRefreshAge: minimumBookRefreshAge,
      minimumQuoteRefreshAge: minimumQuoteRefreshAge,
    );
    fixture.controller = OpportunitiesController(
      appController: fixture.harness.bundle.controller,
      catalog: CatalogRepository(fixture.harness.bundle.catalog),
      directory: fixture.harness.temporaryDirectory,
      clock: () => fixture.now,
      sharedMarket: fixture.broker,
      autoCheck: startup,
      prefetchAll: startup,
      serviceFactory: (_) => throw StateError('Must use shared broker'),
    );
    await fixture.controller.ready;
    if (!startup) {
      fixture.controller.recipes = {
        'First': _recipe('First', '9101', input: 'Raw A'),
        'Second': _recipe('Second', '9102', input: 'Raw B'),
        'Raw A': _recipe('Raw A', '9201'),
        'Raw B': _recipe('Raw B', '9202'),
      };
      fixture.controller.recalculate();
      await fixture.controller.calculationSettled;
    }
    return fixture;
  }

  Future<void> dispose() async {
    if (!transport.release.isCompleted) transport.release.complete();
    // This fixture owns the whole broker. Drain its asynchronous receipt
    // stream before flushing the controller's final history writes.
    await broker.close();
    await controller.flush();
    controller.dispose();
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

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.now);
  final DateTime Function() now;
  final Set<SharedMarketPartKey> failures = {};
  final List<SharedMarketPartKey> requests = [];
  bool protectedResponse = false;
  SharedMarketPartKey? heldPart;
  final held = Completer<void>();
  final release = Completer<void>();

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final book = uri.path.endsWith('GetBiddingInfoList');
    final region = uri.host.startsWith('na-') ? 'na' : 'eu';
    final ids = payload['searchResult'] is String
        ? (payload['searchResult'] as String).split(',')
        : ['${payload['mainKey']}'];
    final parts = ids
        .map(
          (id) => _part(
            id,
            book ? SharedMarketPart.orderBook : SharedMarketPart.quote,
            region: region,
          ),
        )
        .toList();
    requests.addAll(parts);
    if (protectedResponse) {
      return OpportunityHttpResponse(
        statusCode: 200,
        headers: const {'content-type': 'text/html'},
        bytes: Uint8List.fromList(
          utf8.encode(
            '<html><iframe src="/_Incapsula_Resource"></iframe></html>',
          ),
        ),
      );
    }
    if (parts.contains(heldPart) && !release.isCompleted) {
      if (!held.isCompleted) held.complete();
      await Future.any([
        release.future,
        if (abortTrigger != null)
          abortTrigger.then((_) => throw const MarketFetchCancelledException()),
      ]);
    }
    if (ids.length == 1 && failures.contains(parts.single)) {
      return OpportunityHttpResponse(statusCode: 503, bytes: Uint8List(0));
    }
    final text = ids.length > 1
        ? [
            for (final part in parts)
              if (!failures.contains(part))
                '${part.key.itemId}-1234-1000-500000',
          ].join('|')
        : book
        ? '1000-100000-0|'
        : '${ids.single}-0-0-1000-1234-500000-100-10000-1000-${now().millisecondsSinceEpoch ~/ 1000}|';
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

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Expected market recovery.');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
