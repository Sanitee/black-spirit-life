import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_calculations.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'audited non-market output explains its missing price without hiding the recipe',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(_Fixture.create))!;
      final bound = _recipe('Bound output', '16080', input: 'Raw A');
      await tester.runAsync(() async {
        fixture.controller.recipes = {
          'Bound output': bound,
          'Raw A': _recipe('Raw A', '9201'),
        };
        fixture.controller.recalculate();
        await fixture.controller.calculationSettled;
      });
      final before = fixture.controller.quotes.single;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpportunitiesWorkspace(controller: fixture.controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('craft-card:Bound output')),
        findsOneWidget,
      );
      expect(find.text('Not sold on the market'), findsOneWidget);
      expect(find.text('Check prices'), findsNothing);
      expect(fixture.controller.quotes.single, same(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.dispose);
    },
  );

  test(
    'shared startup overlaps calculation without a post-ready debounce',
    () async {
      final fixture = await _Fixture.create(autoCheck: true);
      addTearDown(fixture.dispose);
      expect(
        fixture.requestsAtReady,
        greaterThan(0),
        reason:
            'Startup requests begin before the initial calculation settles.',
      );
    },
  );

  test(
    'raw stock and exact costs appear before a slow detail scan ends',
    () async {
      final fixture = await _Fixture.create(holdBook: '9202');
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      await controller.refresh();
      final scan = controller.ensureMarketDepth(_fixtureIds);
      await _until(() => controller.scanning);
      await _until(() => controller.outputMarketFor('First')?.stock == 1234);
      expect(controller.scanning, isTrue);
      await _until(() => fixture.quote('First').inputCost != null);
      expect(controller.scanning, isTrue);
      expect(fixture.quote('Second').inputCost, isNull);
      expect(fixture.quote('Second').hasEstimatedInputs, isTrue);
      expect(
        fixture.quote('First').listingRevenue,
        2000 * marketNetRate(controller.appController.marketTax.value),
      );
      expect(fixture.quote('First').inputCost, 1000);
      fixture.transport.release.complete();
      await scan;
      await controller.calculationSettled;
      expect(fixture.quote('Second').listingProfit, isNotNull);
      expect(fixture.quote('Second').inputCost, 1000);
      expect(fixture.quote('Second').hasEstimatedInputs, isFalse);
    },
  );

  test(
    'other callers update raw receipts and only dependent recipes',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.loadDepth();
      await fixture.controller.calculationSettled;
      final second = fixture.quote('Second');
      fixture.transport.price = 2000;
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: '9101')],
        forceRefresh: true,
      );
      await _until(
        () =>
            fixture.quote('First').listingRevenue ==
            4000 *
                marketNetRate(fixture.controller.appController.marketTax.value),
      );
      expect(fixture.quote('Second'), same(second));
      expect(fixture.controller.outputMarketFor('First')!.basePrice, 2000);
      final first = fixture.quote('First');
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: '999999')],
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await fixture.controller.calculationSettled;
      expect(fixture.quote('First'), same(first));
      expect(fixture.quote('Second'), same(second));
    },
  );

  test(
    'tax A-to-B-to-A restores quotes after debounced invalidation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.loadDepth();
      await fixture.controller.calculationSettled;
      final calls = fixture.transport.requests;
      fixture.controller.appController.marketTax.value = MarketTax(
        enabled: false,
        valuePack: false,
        merchantRing: false,
      );
      expect(fixture.controller.quotes, isEmpty);
      fixture.controller.appController.marketTax.value = MarketTax(
        enabled: true,
        valuePack: false,
        merchantRing: false,
      );
      // Planner notifications debounce their recalculation independently of a
      // direct Opportunities preference change.
      await Future<void>.delayed(const Duration(milliseconds: 240));
      await fixture.controller.calculationSettled;
      expect(fixture.controller.quotes, hasLength(2));
      for (final quote in fixture.controller.quotes) {
        expect(quote.crafts, 1);
        expect(quote.listingRevenue, 2000 * .65);
        expect(quote.inputCost, 1000);
      }
      final settled = fixture.controller.quotes;
      await Future<void>.delayed(const Duration(milliseconds: 240));
      await fixture.controller.calculationSettled;
      expect(fixture.controller.quotes, same(settled));
      expect(fixture.transport.requests, calls);
    },
  );

  test(
    'retired saved counts and costs cannot affect overview quotes or filters',
    () async {
      final saved = OpportunitiesPreferences()
        ..crafts = 300
        ..extraCostPerRun = 12000
        ..extraCostPerCraft = 75.5
        ..craftSale = 'listing'
        ..readyOnly = true;
      final fixture = await _Fixture.create(savedPreferences: saved);
      addTearDown(fixture.dispose);
      await fixture.loadDepth();
      final controller = fixture.controller;
      expect(controller.preferences.toJson(), saved.toJson());
      expect(controller.visibleQuotes, hasLength(2));
      for (final quote in controller.quotes) {
        expect(quote.crafts, 1);
        expect(quote.expectedOutput, 2);
        expect(quote.extraCostPerRun, 0);
        expect(quote.extraCostPerCraft, 0);
        expect(quote.totalCost, 1000);
        expect(quote.listingProfit, greaterThan(0));
        expect(quote.ingredientsAvailable, isTrue);
      }

      final overview = controller.quotes;
      final calls = fixture.transport.requests;
      controller.change((p) {
        p.crafts = 700;
        p.extraCostPerRun = 999999;
        p.extraCostPerCraft = 888;
      });
      await controller.calculationSettled;
      expect(controller.quotes, same(overview));
      expect(controller.visibleQuotes, hasLength(2));
      expect(fixture.transport.requests, calls);

      // Detail inspection resolves source-mode catalog inputs, not a test's
      // cropped overview recipe map. Use a real, priced NPC input here.
      final detailRecipe = _recipe(
        'Local detail',
        '9101',
        input: 'Mineral Water',
      );
      final single = controller.inspectRecipe(recipe: detailRecipe).quote;
      expect(single.inputCost, greaterThan(0));
      final detail = controller.inspectRecipe(
        recipe: detailRecipe,
        crafts: 7,
        extraCostPerRun: 1200,
        extraCostPerCraft: 25,
        customSalePrice: 5000,
      );
      expect(detail.quote.crafts, 7);
      expect(detail.quote.expectedOutput, 14);
      expect(detail.quote.inputCost, single.inputCost! * 7);
      expect(detail.quote.extraCost, 1375);
      expect(detail.quote.totalCost, single.inputCost! * 7 + 1375);
      expect(detail.quote.customSalePrice, 5000);
      expect(
        detail.quote.listingRevenue,
        70000 * marketNetRate(controller.appController.marketTax.value),
      );
      expect(controller.quotes, same(overview));
      expect(fixture.transport.requests, calls);
      await controller.flush();
      final restored = await OpportunitiesPreferenceStore(
        fixture.harness.temporaryDirectory,
      ).load();
      expect(restored.crafts, 700);
      expect(restored.extraCostPerRun, 999999);
      expect(restored.extraCostPerCraft, 888);
    },
  );

  test(
    'planner inventory and market updates do not discard financial quotes',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.loadDepth();
      await fixture.controller.calculationSettled;
      final before = fixture.controller.quotes;
      final mode = fixture.controller.modeController;
      mode.state.value = mode.state.value.copyWith(
        inventory: {'First': 99},
        market: mode.state.value.market.copyWith(prices: {'First': 9000000}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 240));
      await fixture.controller.calculationSettled;
      expect(fixture.controller.quotes, same(before));
      expect(fixture.quote('First').inputCost, 1000);
    },
  );

  test(
    'stopping Opportunities does not cancel another shared consumer',
    () async {
      final fixture = await _Fixture.create(holdBook: '9202');
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      final scan = fixture.controller.ensureMarketDepth(_fixtureIds);
      await _until(() => fixture.transport.held);
      final other = fixture.broker.fetch(
        bookKeys: [SharedMarketKey(region: 'eu', itemId: '9202')],
      );
      await Future<void>.delayed(Duration.zero);
      fixture.controller.cancel();
      await scan;
      expect(fixture.transport.closed, isFalse);
      fixture.transport.release.complete();
      final result = await other;
      expect(result.failures, isEmpty);
      expect(result.items.values.single.bookFetchedAt, fixture.now);
      expect(fixture.controller.outputMarketFor('First')!.stock, 1234);
    },
  );

  test(
    'shared five-minute warm cache preserves dates and avoids a service',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.loadDepth();
      await fixture.controller.calculationSettled;
      final at = fixture.now;
      await fixture.controller.flush();
      fixture.controller.dispose();
      fixture.controllerDisposed = true;
      await fixture.broker.close();
      fixture.brokerClosed = true;
      fixture.now = at.add(const Duration(minutes: 4, seconds: 59));
      final transport = _Transport(() => fixture.now);
      final broker = SharedMarketRepository(
        cacheMaxAge: sharedMarketFreshness,
        cacheStore: OpportunityMarketCacheStore(
          directory: fixture.harness.temporaryDirectory,
          utcNow: () => fixture.now,
        ),
        transport: transport,
        utcNow: () => fixture.now,
        requestSpacing: Duration.zero,
        orderBookRequestSpacing: Duration.zero,
      );
      final controller = OpportunitiesController(
        appController: fixture.harness.bundle.controller,
        catalog: CatalogRepository(fixture.harness.bundle.catalog),
        directory: fixture.harness.temporaryDirectory,
        clock: () => fixture.now,
        sharedMarket: broker,
        serviceFactory: (_) => throw StateError('Must use app broker'),
      );
      try {
        await controller.ready;
        controller.recipes = _recipes();
        controller.recalculate();
        await controller.calculationSettled;
        await controller.refresh(onlyStale: true);
        expect(transport.requests, 0);
        expect(controller.outputMarketFor('First')!.quoteFetchedAt, at);
        expect(controller.quotes.first.listingProfit, isNotNull);
        fixture.now = at.add(const Duration(hours: 3, milliseconds: 1));
        controller.recalculate();
        expect(controller.quotes, isEmpty);
        await controller.calculationSettled;
        expect(controller.quotes.every((q) => q.listingProfit == null), isTrue);
      } finally {
        await controller.flush();
        controller.dispose();
        await broker.close();
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 10, 10);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;
  bool controllerDisposed = false;
  bool brokerClosed = false;
  int requestsAtReady = 0;

  static Future<_Fixture> create({
    String? holdBook,
    bool autoCheck = false,
    OpportunitiesPreferences? savedPreferences,
  }) async {
    final fixture = _Fixture(await ApplicationTestHarness.create());
    if (savedPreferences != null) {
      await OpportunitiesPreferenceStore(
        fixture.harness.temporaryDirectory,
      ).save(savedPreferences);
    }
    fixture.transport = _Transport(() => fixture.now, holdBook: holdBook);
    fixture.broker = SharedMarketRepository(
      transport: fixture.transport,
      utcNow: () => fixture.now,
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: Duration.zero,
      cacheStore: OpportunityMarketCacheStore(
        directory: fixture.harness.temporaryDirectory,
        utcNow: () => fixture.now,
      ),
    );
    fixture.controller = OpportunitiesController(
      appController: fixture.harness.bundle.controller,
      catalog: CatalogRepository(fixture.harness.bundle.catalog),
      directory: fixture.harness.temporaryDirectory,
      clock: () => fixture.now,
      sharedMarket: fixture.broker,
      autoCheck: autoCheck,
      serviceFactory: (_) => throw StateError('Must use app broker'),
    );
    await fixture.controller.ready;
    fixture.requestsAtReady = fixture.transport.requests;
    fixture.controller.recipes = _recipes();
    fixture.controller.recalculate();
    await fixture.controller.calculationSettled;
    return fixture;
  }

  OpportunityQuote quote(String name) =>
      controller.quotes.singleWhere((quote) => quote.recipeName == name);

  Future<void> loadDepth() async {
    await controller.refresh();
    await controller.ensureMarketDepth(_fixtureIds);
    await controller.calculationSettled;
  }

  Future<void> dispose() async {
    if (!transport.release.isCompleted) transport.release.complete();
    if (!controllerDisposed) {
      await controller.flush();
      controller.dispose();
    }
    if (!brokerClosed) await broker.close();
    await harness.dispose();
  }
}

const _fixtureIds = ['9101', '9102', '9201', '9202'];

Map<String, Recipe> _recipes() => {
  'First': _recipe('First', '9101', input: 'Raw A'),
  'Second': _recipe('Second', '9102', input: 'Raw B'),
  'Raw A': _recipe('Raw A', '9201'),
  'Raw B': _recipe('Raw B', '9202'),
};

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
  _Transport(this.now, {this.holdBook});
  final DateTime Function() now;
  final String? holdBook;
  final release = Completer<void>();
  int price = 1000;
  int requests = 0;
  bool held = false;
  bool closed = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests++;
    final payload = jsonDecode(body) as Map;
    final book = uri.path.endsWith('GetBiddingInfoList');
    final id = '${payload['mainKey']}';
    if (book && id == holdBook && !release.isCompleted) {
      held = true;
      await Future.any([
        release.future,
        if (abortTrigger != null)
          abortTrigger.then((_) => throw const MarketFetchCancelledException()),
      ]);
    }
    final String text;
    if (payload['searchResult'] case final String ids) {
      text = ids.split(',').map((id) => '$id-1234-$price-500000').join('|');
    } else {
      text = book
          ? '$price-100000-0|'
          : '$id-0-0-$price-1234-500000-100-10000-$price-${now().millisecondsSinceEpoch ~/ 1000}|';
    }
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': text})),
      ),
    );
  }

  @override
  void close() => closed = true;
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Expected progressive result.');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}
