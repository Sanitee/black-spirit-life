import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_calculations.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
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

  test(
    'visited crafting modes restore immediately without recalculation',
    () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.change((p) => p.profitableOnly = false);
      final saved = <CraftMode, List<OpportunityQuote>>{};
      for (final mode in CraftMode.values) {
        controller.change((p) => p.mode = mode, assemble: true);
        await controller.calculationSettled;
        expect(controller.quotes, isNotEmpty);
        saved[mode] = controller.quotes;
      }
      for (final mode in [...CraftMode.values.reversed, ...CraftMode.values]) {
        controller.change((p) => p.mode = mode, assemble: true);
        expect(controller.quotes, same(saved[mode]));
        expect(controller.calculating, isFalse);
        expect(controller.visibleQuotes, isNotEmpty);
      }
      expect(fixture.transport.requests, 0);
    },
  );

  test(
    'mode changes assemble the destination even with no old-mode matches',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.change((p) {
        p.mode = CraftMode.processing;
        p.craftSearch = 'Copper Ingot';
        p.profitableOnly = false;
      });
      await controller.calculationSettled;
      expect(controller.recipes['Copper Ingot'], isNotNull);
      expect(
        controller.visibleQuotes.map((q) => q.recipeName),
        contains('Copper Ingot'),
      );
      expect(controller.calculating, isFalse);
      expect(fixture.transport.requests, 0);
    },
  );

  testWidgets(
    'warm Opportunities mode buttons never blank the cards or show a spinner',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(useCatalog: true),
      ))!;
      final controller = fixture.controller;
      await tester.runAsync(() async {
        controller.change((p) => p.profitableOnly = false);
        for (final mode in CraftMode.values) {
          controller.change((p) => p.mode = mode, assemble: true);
          await controller.calculationSettled;
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OpportunitiesWorkspace(controller: controller)),
        ),
      );
      for (final mode in [...CraftMode.values, ...CraftMode.values.reversed]) {
        await tester.tap(find.byKey(ValueKey('craft-mode-${mode.name}')));
        // Inspect the first frame, not pumpAndSettle after the old work completes.
        await tester.pump();
        expect(controller.preferences.mode, mode);
        expect(controller.calculating, isFalse);
        expect(controller.visibleQuotes, isNotEmpty);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(fixture.transport.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(fixture.dispose);
    },
  );

  test(
    'market updates received in another mode refresh only dependent cached rows',
    () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.change((p) {
        p.mode = CraftMode.cooking;
        p.profitableOnly = false;
      });
      final id = controller.recipes['Beer']!.marketId!;
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: id)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await controller.calculationSettled;
      final beer = fixture.quote('Beer');
      final other = fixture.quote('Vinegar');
      expect(beer.listingRevenue, isNotNull);
      controller.change((p) => p.mode = CraftMode.alchemy, assemble: true);
      await controller.calculationSettled;
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      fixture.transport.price = 2000;
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: id)],
        forceRefresh: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await controller.calculationSettled;
      final requests = fixture.transport.requests;
      controller.change((p) => p.mode = CraftMode.cooking, assemble: true);
      expect(fixture.quote('Beer'), same(beer));
      expect(fixture.quote('Vinegar'), same(other));
      await controller.calculationSettled;
      expect(fixture.quote('Beer').listingRevenue, beer.listingRevenue! * 2);
      expect(fixture.quote('Vinegar'), same(other));
      expect(fixture.transport.requests, requests);
    },
  );

  for (final backwards in [false, true]) {
    test(
      '${backwards ? 'clock rollback' : 'expiry'} cannot restore an invalid market valuation',
      () async {
        final fixture = await _Fixture.create(useCatalog: true);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        controller.change((p) => p.profitableOnly = false);
        final id = controller.recipes['Beer']!.marketId!;
        await fixture.broker.fetch(
          quoteKeys: [SharedMarketKey(region: 'eu', itemId: id)],
        );
        await Future<void>.delayed(const Duration(milliseconds: 280));
        await controller.calculationSettled;
        expect(fixture.quote('Beer').listingRevenue, isNotNull);
        controller.change((p) => p.mode = CraftMode.alchemy, assemble: true);
        await controller.calculationSettled;
        fixture.now = backwards
            ? fixture.now.subtract(const Duration(seconds: 1))
            : fixture.now.add(const Duration(hours: 3, milliseconds: 1));
        controller.change((p) => p.mode = CraftMode.cooking, assemble: true);
        expect(controller.quotes, isEmpty);
        await controller.calculationSettled;
        expect(fixture.quote('Beer').listingRevenue, isNull);
      },
    );
  }

  test('editing a hidden category invalidates its cached recipes', () async {
    final fixture = await _Fixture.create(useCatalog: true);
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    controller.change((p) => p.profitableOnly = false);
    expect(controller.recipes, contains('Beer'));
    controller.change((p) => p.mode = CraftMode.alchemy, assemble: true);
    await controller.calculationSettled;
    final cooking = controller.appController.modes[CraftMode.cooking]!;
    cooking.state.value = cooking.state.value.copyWith(
      recipeEdits: {...cooking.state.value.recipeEdits, 'Beer': null},
    );
    controller.change((p) => p.mode = CraftMode.cooking, assemble: true);
    expect(controller.quotes, isEmpty);
    await controller.calculationSettled;
    // Assembly may keep the ingredient/reference stub, but not its formula.
    expect(controller.recipes['Beer']?.isCraftable ?? false, isFalse);
    expect(
      controller.quotes.any((quote) => quote.recipeName == 'Beer'),
      isFalse,
    );
  });

  for (final change in ['mastery', 'inventory', 'tax']) {
    test('$change changes invalidate a cached category valuation', () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.change((p) => p.useInventory = true);
      await controller.calculationSettled;
      controller.change((p) => p.mode = CraftMode.alchemy, assemble: true);
      await controller.calculationSettled;
      final cooking = controller.appController.modes[CraftMode.cooking]!;
      switch (change) {
        case 'mastery':
          cooking.state.value = cooking.state.value.copyWith(
            cookingMastery: 1700,
          );
        case 'inventory':
          cooking.state.value = cooking.state.value.copyWith(
            inventory: {'Corn': 200},
          );
        case 'tax':
          controller.appController.marketTax.value = MarketTax(
            enabled: false,
            valuePack: false,
            merchantRing: false,
          );
      }
      controller.change((p) => p.mode = CraftMode.cooking, assemble: true);
      expect(controller.quotes, isEmpty);
      await controller.calculationSettled;
      expect(controller.quotes, isNotEmpty);
    });
  }

  test(
    'a warm return during another category calculation keeps the destination results',
    () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final cooking = controller.quotes;
      controller.change((p) => p.mode = CraftMode.processing, assemble: true);
      expect(controller.calculating, isTrue);
      controller.change((p) => p.mode = CraftMode.cooking, assemble: true);
      expect(controller.quotes, same(cooking));
      await controller.calculationSettled;
      expect(controller.quotes, same(cooking));
    },
  );

  test(
    'equal inventory survives mode switching and unrelated planner market edits',
    () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final cooking = controller.appController.modes[CraftMode.cooking]!;
      cooking.state.value = cooking.state.value.copyWith(
        inventory: {'Corn': 200},
      );
      controller.change((p) => p.useInventory = true);
      await controller.calculationSettled;
      final saved = controller.quotes;
      controller.change((p) => p.mode = CraftMode.alchemy, assemble: true);
      await controller.calculationSettled;
      cooking.state.value = cooking.state.value.copyWith(
        market: cooking.state.value.market.copyWith(prices: {'Corn': 9999}),
      );
      controller.change((p) => p.mode = CraftMode.cooking, assemble: true);
      expect(controller.quotes, same(saved));
      expect(controller.calculating, isFalse);
    },
  );

  test(
    'regions keep separate valuations and warm returns restore the correct one',
    () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final id = controller.recipes['Beer']!.marketId!;
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: id)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await controller.calculationSettled;
      final eu = controller.quotes;
      expect(fixture.quote('Beer').listingRevenue, isNotNull);
      controller.change((p) => p.region = 'na');
      expect(controller.quotes, isEmpty);
      await controller.calculationSettled;
      final na = controller.quotes;
      expect(fixture.quote('Beer').listingRevenue, isNull);
      controller.change((p) => p.region = 'eu');
      expect(controller.quotes, same(eu));
      expect(controller.calculating, isFalse);
      controller.change((p) => p.region = 'na');
      expect(controller.quotes, same(na));
      expect(controller.calculating, isFalse);
    },
  );

  test(
    'partly searched categories retain known matches and fill missing rows on return',
    () async {
      final fixture = await _Fixture.create(useCatalog: true);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.change((p) {
        p.craftSearch = 'Beer';
        p.profitableOnly = false;
        p.useInventory = true;
      });
      await controller.calculationSettled;
      final beer = fixture.quote('Beer');
      controller.change((p) => p.mode = CraftMode.alchemy, assemble: true);
      await controller.calculationSettled;
      controller.change((p) {
        p.mode = CraftMode.cooking;
        p.craftSearch = '';
      }, assemble: true);
      expect(fixture.quote('Beer'), same(beer));
      await controller.calculationSettled;
      expect(controller.quotes.length, greaterThan(2));
      expect(fixture.quote('Beer'), same(beer));
    },
  );

  test(
    'search prices only missing matches and reuses valid cached quotes',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      // Searches are session-local; begin a fresh, filtered calculation after
      // startup instead of relying on a persisted search from an older run.
      controller.change((p) {
        p.craftSearch = 'First';
        p.useInventory = true;
      });
      await controller.calculationSettled;
      expect(controller.quotes.map((q) => q.recipeName), ['First']);
      final notifications = <bool>[];
      controller.addListener(() => notifications.add(controller.calculating));

      // Start new economics, then change the search while the isolate is active.
      controller.change((p) => p.useInventory = false);
      expect(controller.calculating, isTrue);
      controller.change((p) => p.craftSearch = 'Second');
      controller.change((p) => p.craftSearch = 'First');
      await controller.calculationSettled;
      expect(controller.visibleQuotes.map((q) => q.recipeName), ['First']);
      expect(controller.quotes.map((q) => q.recipeName), ['First']);
      expect(notifications.last, isFalse);
      final first = fixture.quote('First');

      controller.change((p) => p.craftSearch = ' Second ');
      await controller.calculationSettled;
      expect(controller.visibleQuotes.map((q) => q.recipeName), ['Second']);
      expect(fixture.quote('First'), same(first));
      final second = fixture.quote('Second');
      controller.change((p) => p.craftSearch = '');
      expect(controller.calculating, isFalse);
      expect(fixture.quote('First'), same(first));
      expect(fixture.quote('Second'), same(second));
      expect(fixture.transport.requests, 0);
    },
  );

  test(
    'hidden stale quotes are recalculated when the search is cleared',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.loadDepth();
      final controller = fixture.controller;
      final first = fixture.quote('First');
      controller.change((p) => p.craftSearch = 'First');
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      fixture.transport.price = 2000;
      await fixture.broker.fetch(
        quoteKeys: [SharedMarketKey(region: 'eu', itemId: '9102')],
        forceRefresh: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await controller.calculationSettled;
      expect(fixture.quote('First'), same(first));
      expect(controller.quotes.map((q) => q.recipeName), ['First']);
      final requests = fixture.transport.requests;
      controller.change((p) => p.craftSearch = '');
      await controller.calculationSettled;
      expect(fixture.quote('First'), same(first));
      expect(
        fixture.quote('Second').listingRevenue,
        4000 * marketNetRate(controller.appController.marketTax.value),
      );
      expect(fixture.transport.requests, requests);
    },
  );

  testWidgets('empty search result stops showing the calculation spinner', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final fixture = (await tester.runAsync(_Fixture.create))!;
    final controller = fixture.controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OpportunitiesWorkspace(controller: controller)),
      ),
    );
    await tester.runAsync(() async {
      controller.change((p) => p.useInventory = true);
      controller.change((p) => p.craftSearch = 'no matching recipe');
      expect(controller.calculating, isTrue);
      await controller.calculationSettled;
    });
    await tester.pumpAndSettle();
    expect(controller.calculating, isFalse);
    expect(controller.visibleQuotes, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(fixture.dispose);
  });

  testWidgets(
    'nonmarket output stays visible without redundant market explanations',
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
      expect(find.text('Not sold on the market'), findsNothing);
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
    bool useCatalog = false,
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
    if (!useCatalog) {
      fixture.controller.recipes = _recipes();
      fixture.controller.recalculate();
      await fixture.controller.calculationSettled;
    }
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
