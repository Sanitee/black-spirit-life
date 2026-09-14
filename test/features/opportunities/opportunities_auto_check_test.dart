import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_observation_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/atomic_file_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Demand uses fresh preorders, not stock or historical sales', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    controller.cancel();
    controller.preferences
      ..profitableOnly = false
      ..craftSort = 'preorders';
    final recipes = controller.recipes.values
        .where(
          (recipe) =>
              recipe.isCraftable &&
              recipe.marketId != null &&
              recipe.type.toLowerCase() == controller.preferences.mode.key,
        )
        .take(5)
        .toList();
    expect(recipes, hasLength(5));
    final quantities = <int?>[0, 4, null, 99, 1000];
    controller.quotes = [
      for (var i = 0; i < recipes.length; i++)
        const OpportunityCalculator().evaluate(
          recipe: recipes[i],
          recipes: controller.recipes,
          state: controller.state,
          rules: controller.appController.plannerRules,
          marketTax: controller.appController.marketTax.value,
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: {
              recipes[i].marketId!: OpportunityMarketItem(
                itemId: recipes[i].marketId!,
                basePrice: 1000,
                stock: i == 0 ? 999999 : 0,
                quoteFetchedAt: fixture.now,
                bookFetchedAt: i == 4
                    ? fixture.now.subtract(const Duration(hours: 4))
                    : fixture.now,
                asks: quantities[i] == null ? null : [],
                bids: quantities[i] == null
                    ? null
                    : [
                        OpportunityMarketLevel(
                          price: 1000,
                          quantity: quantities[i]!,
                        ),
                      ],
                salesActivity: OpportunitySalesActivity(
                  soldCount: i == 0 ? 10000000 : 0,
                  startedAt: fixture.now.subtract(const Duration(hours: 2)),
                  endedAt: fixture.now,
                ),
              ),
            },
          ),
          now: fixture.now,
        ),
    ];
    expect(controller.visibleQuotes.take(3).map((quote) => quote.recipeName), [
      recipes[3].name,
      recipes[1].name,
      recipes[0].name,
    ]);
    expect(
      controller.visibleQuotes.skip(3).map((quote) => quote.recipeName).toSet(),
      {recipes[2].name, recipes[4].name},
    );
  });

  test('Divine Coin refresh requests only its three market rewards', () async {
    final fixture = await _Fixture.create(autoCheck: false);
    addTearDown(fixture.dispose);
    fixture.controller.change((p) => p.currencyId = 'divine-coin');
    await fixture.controller.refresh();
    final requests = fixture.sessions.single.requests;
    expect(requests.every((request) => !request.book), isTrue);
    expect(requests.map((request) => request.id).toSet(), {
      '821344',
      '821347',
      '821182',
    });
    expect(requests.length, 3);
  });

  test(
    'startup prefetch covers all modes and currencies once, without edits',
    () async {
      final fixture = await _Fixture.create(prefetchAll: true);
      addTearDown(fixture.dispose);
      final plannerBefore = fixture.harness.bundle.controller.documentSnapshot;
      final preferencesBefore = fixture.controller.preferences.toJson();
      var publications = 0;
      fixture.controller.addListener(() => publications++);
      // Opening the tab before the startup debounce must not narrow the scan.
      fixture.controller.ensureMarketCurrent();
      await fixture.waitForChecks(1);
      final requests = fixture.sessions.single.requests;
      expect(
        publications,
        lessThan(requests.length ~/ 4),
        reason: 'Progress is coalesced rather than rebuilding per request.',
      );
      final expected = _allIds(fixture);
      expect(expected, containsAll(['821344', '821347', '821182']));
      expect(expected, isNot(contains('980170')));
      expect(expected, isNot(contains('4')));
      expect(requests.every((request) => !request.book), isTrue);
      expect(requests.map((request) => request.id).toSet(), expected);
      expect(
        requests.length,
        expected.length,
        reason:
            'Shared price IDs are fetched once; depth is not a startup job.',
      );
      expect(fixture.controller.preferences.toJson(), preferencesBefore);
      expect(
        fixture.harness.bundle.controller.documentSnapshot,
        same(plannerBefore),
      );
      for (final mode in CraftMode.values) {
        fixture.controller.change((p) {
          p.section = 'crafting';
          p.mode = mode;
        }, assemble: true);
        await _pastDebounce();
        expect(fixture.controller.hasChecked, isTrue);
      }
      fixture.controller.change((p) {
        p.section = 'exchanges';
        p.currencyId = 'sangpyeong';
      });
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
    },
  );

  test('opening another pane joins an active all-section scan', () async {
    final fixture = await _Fixture.create(
      prefetchAll: true,
      holdFirstCheck: true,
    );
    addTearDown(fixture.dispose);
    await _until(
      () =>
          fixture.sessions.isNotEmpty &&
          fixture.sessions.first.requests.isNotEmpty,
    );
    fixture.controller.change((p) => p.currencyId = 'blush-leaf');
    fixture.controller.ensureMarketCurrent();
    await _pastDebounce();
    expect(fixture.sessions, hasLength(1));
    expect(fixture.sessions.single.aborted, isFalse);
    expect(fixture.controller.scanning, isTrue);
    fixture.controller.cancel();
    await fixture.waitForChecks(1);
    expect(fixture.sessions.single.aborted, isTrue);
    expect(fixture.controller.hasChecked, isFalse);
    expect(fixture.controller.lastCheck, isNull);
  });

  test(
    'region change replaces the all-section scan without crossing caches',
    () async {
      final fixture = await _Fixture.create(
        prefetchAll: true,
        holdFirstCheck: true,
      );
      addTearDown(fixture.dispose);
      await _until(
        () =>
            fixture.sessions.isNotEmpty &&
            fixture.sessions.first.requests.isNotEmpty,
      );
      fixture.controller.change((p) => p.region = 'na');
      await fixture.waitForChecks(2);
      expect(fixture.sessions.first.aborted, isTrue);
      expect(fixture.sessions.last.region, 'na');
      expect(
        fixture.sessions.last.requests.map((request) => request.id).toSet(),
        _allIds(fixture),
      );
      expect(fixture.controller.market.region, 'na');
      fixture.controller.change((p) => p.region = 'eu');
      await fixture.waitForChecks(3);
      expect(fixture.sessions.last.region, 'eu');
      expect(fixture.sessions.last.requests, isNotEmpty);
    },
  );

  test('retry fetches only failed books, not already fresh prices', () async {
    final failedId = _rewardIds('witchs-delicacy').first;
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.waitForChecks(1);
    fixture.failNextParts = {'b$failedId': 503};
    await fixture.controller.ensureMarketDepth([failedId]);
    await fixture.waitForChecks(2);
    expect(fixture.controller.hasChecked, isTrue);
    expect(fixture.controller.failedItems, 1);
    expect(
      fixture.controller.market.items[failedId]!.quoteIsFresh(
        fixture.now,
        OpportunitiesController.maxMarketAge,
      ),
      isTrue,
    );
    await fixture.controller.refresh();
    await fixture.waitForChecks(3);
    expect(fixture.sessions.last.requests, hasLength(1));
    expect(fixture.sessions.last.requests.single.id, failedId);
    expect(fixture.sessions.last.requests.single.book, isTrue);
    expect(fixture.controller.hasChecked, isTrue);
    expect(fixture.controller.failedItems, 0);
  });

  test(
    'receipts are visible before a slow batch finishes and survive Stop',
    () async {
      final fixture = await _Fixture.create(holdAfterRequests: 1);
      addTearDown(fixture.dispose);
      await _until(
        () =>
            fixture.sessions.isNotEmpty &&
            fixture.sessions.single.requests.length >= 2,
      );
      final firstId = fixture.sessions.single.requests.first.id;
      expect(fixture.controller.scanning, isTrue);
      expect(fixture.controller.market.items[firstId]?.basePrice, 1000);
      fixture.controller.cancel();
      await fixture.waitForChecks(1);
      expect(fixture.controller.market.items[firstId]?.basePrice, 1000);
      expect(fixture.controller.hasChecked, isFalse);
    },
  );

  test('first load checks quotes without books or planner edits', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final plannerBefore = fixture.harness.bundle.controller.documentSnapshot;
    await fixture.waitForChecks(1);
    final requests = fixture.sessions.single.requests;
    final ids = _rewardIds('witchs-delicacy');
    expect(requests.where((r) => !r.book).map((r) => r.id).toSet(), ids);
    expect(requests.where((r) => r.book), isEmpty);
    expect(
      requests.take(ids.length).every((r) => !r.book),
      isTrue,
      reason: 'Opening the overview needs price summaries only.',
    );
    expect(fixture.controller.hasChecked, isTrue);
    for (final id in ids) {
      final item = fixture.controller.market.items[id]!;
      expect(
        item.quoteIsFresh(fixture.now, OpportunitiesController.maxMarketAge),
        isTrue,
      );
      expect(item.asks, isNull);
      expect(item.bids, isNull);
      expect(
        item.bookIsFresh(fixture.now, OpportunitiesController.maxMarketAge),
        isFalse,
        reason: 'Unchecked depth is not a confirmed empty book.',
      );
    }
    expect(
      identical(
        fixture.harness.bundle.controller.documentSnapshot,
        plannerBefore,
      ),
      isTrue,
    );
  });

  test('fresh pane revisit and ordinary filters do not refetch', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.waitForChecks(1);
    fixture.controller.change((p) => p.currencyId = 'mysterious-catalyst');
    await fixture.waitForChecks(2);
    fixture.controller.change((p) => p.currencyId = 'witchs-delicacy');
    await _pastDebounce();
    expect(fixture.sessions, hasLength(2));
    fixture.controller.change((p) {
      p.exchangeSearch = 'Milk';
      p.owned['witchs-delicacy'] = 500;
      p.exchangeSale = 'listing';
    });
    await _pastDebounce();
    expect(fixture.sessions, hasLength(2));
    expect(fixture.controller.preferences.exchangeSearch, 'Milk');
    expect(fixture.controller.owned, 500);
  });

  test(
    'region changes check the new region and preserve the old region cache',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      fixture.controller.change((p) => p.region = 'na');
      await fixture.waitForChecks(2);
      expect(fixture.sessions.map((s) => s.region), ['eu', 'na']);
      expect(
        fixture.sessions[1].requests.every(
          (r) => r.host == 'na-trade.naeu.playblackdesert.com',
        ),
        isTrue,
      );
      fixture.controller.change((p) => p.region = 'eu');
      await _pastDebounce();
      expect(fixture.sessions, hasLength(2));
      expect(fixture.controller.market.region, 'eu');
      expect(fixture.controller.hasChecked, isTrue);
    },
  );

  test(
    'a selection change keeps summary work and queues only the latest pane',
    () async {
      final fixture = await _Fixture.create(holdFirstCheck: true);
      addTearDown(fixture.dispose);
      await _until(
        () =>
            fixture.sessions.isNotEmpty &&
            fixture.sessions.first.requests.isNotEmpty,
      );
      fixture.controller.change((p) => p.currencyId = 'mysterious-catalyst');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      fixture.controller.change((p) => p.currencyId = 'blush-leaf');
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
      expect(fixture.sessions.first.aborted, isFalse);
      expect(fixture.sessions.first.closed, isFalse);
      fixture.sessions.first.release.complete();
      await fixture.waitForChecks(2);
      expect(fixture.sessions.first.aborted, isFalse);
      expect(fixture.sessions.first.closed, isTrue);
      expect(fixture.sessions, hasLength(2));
      expect(
        fixture.sessions.last.requests.map((r) => r.id).toSet(),
        _rewardIds('blush-leaf'),
      );
      expect(fixture.controller.currency.id, 'blush-leaf');
      expect(fixture.controller.hasChecked, isTrue);
      expect(fixture.controller.notice, isNull);
    },
  );

  test('flush cancels the pending automatic check', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.flush();
    await _pastDebounce();
    expect(fixture.sessions, isEmpty);
    expect(fixture.controller.scanning, isFalse);
  });

  test('Stop cancels an automatic check before its debounce expires', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.controller.cancel();
    await _pastDebounce();
    expect(fixture.sessions, isEmpty);
    expect(fixture.controller.scanning, isFalse);
    expect(fixture.controller.hasChecked, isFalse);
  });

  test('Stop cancels an active check and its queued replacement', () async {
    final fixture = await _Fixture.create(holdFirstCheck: true);
    addTearDown(fixture.dispose);
    await _until(
      () =>
          fixture.sessions.isNotEmpty &&
          fixture.sessions.first.requests.isNotEmpty,
    );
    fixture.controller.change((p) => p.currencyId = 'mysterious-catalyst');
    fixture.controller.cancel();
    await fixture.waitForChecks(1);
    await _pastDebounce();
    expect(fixture.sessions, hasLength(1));
    expect(fixture.sessions.single.aborted, isTrue);
    expect(fixture.controller.scanning, isFalse);
    expect(fixture.controller.currency.id, 'mysterious-catalyst');
  });

  test(
    'tab return retains prices within five minutes but manual Refresh forces a check',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      fixture.controller.ensureMarketCurrent();
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));

      fixture.now = fixture.now.add(const Duration(minutes: 4, seconds: 59));
      fixture.controller.ensureMarketCurrent();
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
      final oldTime = fixture.controller.lastCheck;
      expect(oldTime, isNot(fixture.now));
      for (final item in fixture.controller.market.items.values) {
        expect(item.quoteFetchedAt, oldTime);
        expect(item.bookFetchedAt, isNull);
        expect(
          item.quoteIsFresh(fixture.now, const Duration(minutes: 4)),
          isFalse,
        );
        expect(
          item.quoteIsFresh(fixture.now, fixture.controller.cachedMarketMaxAge),
          isTrue,
        );
      }
      await fixture.controller.refresh();
      expect(fixture.sessions, hasLength(2));
      for (final item in fixture.controller.market.items.values) {
        expect(item.quoteFetchedAt, fixture.now);
        expect(item.bookFetchedAt, isNull);
      }
    },
  );

  test(
    'dispose cancels the pending automatic check without starting a service',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      fixture.disposeController();
      await _pastDebounce();
      expect(fixture.sessions, isEmpty);
    },
  );

  test(
    'five-minute expiry is checked on use, not by an idle refresh timer',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final checkedAt = fixture.controller.lastCheck;
      fixture.now = fixture.now.add(OpportunitiesController.automaticMarketAge);
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
      fixture.controller.ensureMarketCurrent();
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
      expect(fixture.controller.lastCheck, checkedAt);
      fixture.now = fixture.now.add(const Duration(milliseconds: 1));
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
      expect(fixture.controller.hasChecked, isTrue);
      fixture.controller.ensureMarketCurrent();
      await fixture.waitForChecks(2);
      expect(fixture.controller.lastCheck, fixture.now);
      expect(fixture.sessions, hasLength(2));
    },
  );

  test(
    'six-minute same-tab pane browsing keeps original quote timestamps',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final at = fixture.controller.lastCheck;
      fixture.now = fixture.now.add(const Duration(minutes: 6));
      fixture.controller.change((p) => p.currencyId = 'mysterious-catalyst');
      fixture.controller.change((p) => p.currencyId = 'witchs-delicacy');
      await _pastDebounce();
      expect(fixture.sessions, hasLength(1));
      expect(fixture.controller.lastCheck, at);
      expect(
        fixture.controller.market.items.values.every(
          (item) => item.quoteFetchedAt == at,
        ),
        isTrue,
      );
      fixture.controller.ensureMarketCurrent();
      await fixture.waitForChecks(2);
      expect(
        fixture.controller.lastCheck,
        fixture.now,
        reason: 'True tab entry retains the separate five-minute check.',
      );
    },
  );

  test('thirty-minute cache is refreshed on same-tab pane return', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.waitForChecks(1);
    final before = fixture.controller.market.items.values.first.quoteFetchedAt;
    fixture.now = fixture.now.add(
      OpportunitiesController.inWorkspaceMarketAge + const Duration(seconds: 1),
    );
    fixture.controller.change((p) => p.currencyId = 'mysterious-catalyst');
    fixture.controller.change((p) => p.currencyId = 'witchs-delicacy');
    await fixture.waitForChecks(2);
    expect(fixture.sessions, hasLength(2));
    for (final item in fixture.controller.market.items.values) {
      expect(item.quoteFetchedAt, fixture.now);
      expect(item.bookFetchedAt, isNull);
      expect(item.quoteFetchedAt, isNot(before));
    }
  });

  test(
    'a service construction failure is handled inside the automatic callback',
    () async {
      final fixture = await _Fixture.create(failFactory: true);
      addTearDown(fixture.dispose);
      await _until(() => fixture.controller.notice != null);
      expect(fixture.controller.notice, contains('market'));
      expect(fixture.controller.scanning, isFalse);
      expect(fixture.controller.market.items, isEmpty);
      expect(fixture.controller.hasChecked, isFalse);
    },
  );

  test(
    'legacy buyer preferences now use listing proceeds without losing saved fields',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final controller = fixture.controller;
      expect(controller.preferences.craftSale, 'buyers');
      expect(controller.preferences.exchangeSale, 'buyers');
      expect(controller.craftSaleMode, OpportunitySaleMode.listing);
      expect(controller.exchangeSaleMode, ExchangeSaleMode.listing);
      expect(
        controller.exchangeQuotes.every(
          (quote) => quote.saleMode == ExchangeSaleMode.listing,
        ),
        isTrue,
      );
      await controller.flush();
      final saved = await OpportunitiesPreferenceStore(
        fixture.harness.temporaryDirectory,
      ).load();
      expect(saved.craftSale, 'buyers');
      expect(saved.exchangeSale, 'buyers');
    },
  );

  test(
    'prices within three hours calculate changed tax and amounts without refetch',
    () async {
      final fixture = await _Fixture.create(
        prefetchAll: true,
        autoCheck: false,
      );
      addTearDown(fixture.dispose);
      await fixture.controller.refreshAll();
      await fixture.waitForChecks(1);
      final controller = fixture.controller;
      final checkedAt = controller.lastCheck;
      controller.appController.marketTax.value = MarketTax(valuePack: false);
      final before = controller.exchangeQuotes.firstWhere(
        (quote) => quote.netProceeds != null,
      );
      fixture.now = fixture.now.add(const Duration(hours: 2, minutes: 59));
      controller.appController.marketTax.value = MarketTax(valuePack: true);
      controller.change(
        (p) => p.owned[controller.currency.id] = before.route.inputCount * 2,
      );
      final after = controller.exchangeQuotes.firstWhere(
        (quote) => quote.route.id == before.route.id,
      );
      expect(after.netProceeds, greaterThan(before.netProceeds! * 2));
      expect(controller.lastCheck, checkedAt);
      controller.change((p) {
        p.section = 'crafting';
        p.mode = CraftMode.cooking;
        p.profitableOnly = false;
      }, assemble: true);
      await _pastDebounce();
      await controller.calculationSettled;
      expect(
        controller.quotes.any((quote) => quote.listingRevenue != null),
        isTrue,
      );
      expect(fixture.sessions, hasLength(1));
      expect(controller.lastCheck, checkedAt);
      // Turning the clock back does not make future-dated prices acceptable.
      fixture.now = checkedAt!.subtract(const Duration(minutes: 1));
      controller.change((p) => p.section = 'exchanges');
      controller.cancel();
      expect(
        controller.exchangeQuotes
            .where((quote) => quote.route.id == before.route.id)
            .single
            .netProceeds,
        isNull,
      );
    },
  );

  test(
    'region with no receipts has no timestamp; failed refresh keeps old parts',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final controller = fixture.controller;
      final oldTime = controller.lastCheck;
      controller.change((p) => p.region = 'na');
      controller.cancel();
      expect(controller.market.items, isEmpty);
      expect(controller.lastCheck, isNull);
      controller.change((p) => p.region = 'eu');
      controller.cancel();
      expect(controller.lastCheck, oldTime);
      final failedId = _rewardIds('witchs-delicacy').first;
      fixture.now = fixture.now.add(const Duration(hours: 2));
      fixture.failNextParts = {'q$failedId': 503};
      await controller.refresh();
      await controller.ensureMarketDepth(_rewardIds('witchs-delicacy'));
      expect(controller.market.items[failedId]!.quoteFetchedAt, oldTime);
      expect(controller.market.items[failedId]!.basePrice, 1000);
      expect(controller.market.items[failedId]!.bookFetchedAt, fixture.now);
      expect(controller.lastCheck, fixture.now);
      expect(controller.failedItems, 1);
      expect(controller.notice, 'Retrying missing market data shortly.');
      final mixedSnapshot = controller.market.items;
      final lastSuccess = controller.lastCheck;
      fixture.now = fixture.now.add(const Duration(hours: 1));
      fixture.failNextParts = {
        for (final id in _rewardIds('witchs-delicacy')) 'q$id': 503,
        for (final id in _rewardIds('witchs-delicacy')) 'b$id': 503,
      };
      await controller.refresh();
      expect(controller.market.items, mixedSnapshot);
      expect(controller.lastCheck, lastSuccess);
    },
  );

  test('429 wait is retained across early Refresh and tab return', () async {
    final fixture = await _Fixture.create(failFirstRequestStatus: 429);
    addTearDown(fixture.dispose);
    fixture.controller.cancel();
    await fixture.controller.refresh();
    expect(fixture.sessions.single.requests, hasLength(1));
    expect(fixture.controller.lastCheck, isNull);
    expect(
      fixture.controller.notice,
      'Market is busy. Retrying automatically.',
    );
    fixture.controller.ensureMarketCurrent();
    fixture.controller.change((p) => p.currencyId = 'blush-leaf');
    await _pastDebounce();
    expect(fixture.sessions, hasLength(1));
    await fixture.controller.refresh();
    expect(
      fixture.sessions,
      hasLength(1),
      reason: 'Recreating the fallback service must not bypass the block.',
    );
    fixture.now = fixture.now.add(const Duration(seconds: 61));
    await fixture.controller.refresh();
    expect(fixture.sessions, hasLength(2));
    expect(fixture.controller.notice, isNull);
    expect(fixture.controller.hasChecked, isTrue);
  });

  test(
    'fallback preserves Retry-After across service recreation per region',
    () async {
      final fixture = await _Fixture.create(
        autoCheck: false,
        failFirstRequestStatus: 429,
        firstRequestHeaders: const {'retry-after': '120'},
      );
      addTearDown(fixture.dispose);
      await fixture.controller.refresh();
      expect(fixture.sessions, hasLength(1));
      fixture.now = fixture.now.add(const Duration(seconds: 61));
      await fixture.controller.refresh();
      expect(fixture.sessions, hasLength(1));
      fixture.controller.change((p) => p.region = 'na');
      await fixture.controller.refresh();
      expect(fixture.sessions, hasLength(2));
      expect(fixture.sessions.last.region, 'na');
      fixture.controller.change((p) => p.region = 'eu');
      await fixture.controller.refresh();
      expect(fixture.sessions, hasLength(2));
      fixture.now = fixture.now.add(const Duration(seconds: 60));
      await fixture.controller.refresh();
      expect(fixture.sessions, hasLength(3));
      expect(fixture.sessions.last.region, 'eu');
      expect(fixture.controller.failedItems, 0);
      expect(fixture.controller.notice, isNull);
    },
  );

  test(
    'one buffered history commit never blocks prices and flush awaits durability',
    () async {
      final committer = _HeldCommitter();
      final fixture = await _Fixture.create(
        prefetchAll: true,
        observationCommitter: committer,
      );
      addTearDown(fixture.dispose);
      addTearDown(() {
        if (!committer.release.isCompleted) committer.release.complete();
      });
      await fixture.waitForChecks(1);
      await committer.started.future;
      expect(fixture.controller.scanning, isFalse);
      expect(fixture.controller.hasChecked, isTrue);
      expect(fixture.controller.market.items.keys.toSet(), _allIds(fixture));
      expect(committer.commits, 1);
      var flushed = false;
      final flush = fixture.controller.flush().then((_) => flushed = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(flushed, isFalse);
      committer.release.complete();
      await flush;
      expect(flushed, isTrue);
      final saved =
          jsonDecode(
                await File(
                  '${fixture.harness.temporaryDirectory.path}/opportunity-market-observations.json',
                ).readAsString(),
              )
              as Map;
      expect((saved['series'] as Map).length, _allIds(fixture).length);
    },
  );

  test('Stop after 429 cannot clear the automatic-retry pause', () async {
    final fixture = await _Fixture.create(
      holdAfterRequests: 1,
      concurrency: 4,
      failFirstRequestStatus: 429,
    );
    addTearDown(fixture.dispose);
    fixture.controller.cancel();
    final scan = fixture.controller.refresh();
    await _until(
      () =>
          fixture.sessions.isNotEmpty &&
          fixture.sessions.single.requests.length ==
              _rewardIds('witchs-delicacy').length,
    );
    fixture.controller.cancel();
    await scan;
    await _until(() => fixture.sessions.single.aborted);
    fixture.controller.change((p) => p.currencyId = 'blush-leaf');
    fixture.controller.ensureMarketCurrent();
    await _pastDebounce();
    expect(fixture.sessions, hasLength(1));
    expect(fixture.controller.scanning, isFalse);
  });

  test(
    'Stop saves already received counters without awaiting the whole market',
    () async {
      final fixture = await _Fixture.create(holdAfterRequests: 1);
      addTearDown(fixture.dispose);
      await _until(
        () =>
            fixture.sessions.isNotEmpty &&
            fixture.sessions.single.requests.length == 2,
      );
      final firstId = fixture.sessions.single.requests.first.id;
      await fixture.controller.flush();
      final saved =
          jsonDecode(
                await File(
                  '${fixture.harness.temporaryDirectory.path}/opportunity-market-observations.json',
                ).readAsString(),
              )
              as Map;
      expect((saved['series'] as Map).keys, ['eu:$firstId:0']);
      final receipts = await OpportunityMarketCacheStore(
        directory: fixture.harness.temporaryDirectory,
        utcNow: () => fixture.now,
      ).load();
      expect(receipts['eu']!.keys, [firstId]);
      expect(receipts['eu']![firstId]!.quoteFetchedAt, fixture.now);
      expect(receipts['eu']![firstId]!.bookFetchedAt, isNull);
      expect(fixture.sessions.single.aborted, isTrue);
      expect(fixture.sessions.single.requests, hasLength(2));
    },
  );

  test(
    'restarting restores preferences and fresh raw market receipts independently',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      await fixture.controller.flush();
      fixture.disposeController();
      final restarted = OpportunitiesController(
        appController: fixture.harness.bundle.controller,
        catalog: CatalogRepository(fixture.harness.bundle.catalog),
        directory: fixture.harness.temporaryDirectory,
        clock: () => fixture.now,
      );
      addTearDown(restarted.dispose);
      await restarted.ready;
      expect(restarted.currency.id, 'witchs-delicacy');
      expect(
        restarted.market.items.keys.toSet(),
        _rewardIds('witchs-delicacy'),
      );
      expect(restarted.lastCheck, fixture.now);
      expect(restarted.hasChecked, isTrue);
      expect(
        restarted.exchangeQuotes.where(
          (quote) =>
              !quote.route.directVendorSale &&
              quote.route.rewards.any(
                (reward) => reward.item?.marketable == true,
              ) &&
              quote.netProceeds != null,
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'restart at 4 min 59 sec uses cached prices without starting a service',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final checkedAt = fixture.controller.lastCheck;
      await fixture.controller.flush();
      fixture.disposeController();
      fixture.now = fixture.now.add(const Duration(minutes: 4, seconds: 59));
      var requested = false;
      final restarted = OpportunitiesController(
        appController: fixture.harness.bundle.controller,
        catalog: CatalogRepository(fixture.harness.bundle.catalog),
        directory: fixture.harness.temporaryDirectory,
        clock: () => fixture.now,
        autoCheck: true,
        serviceFactory: (_) {
          requested = true;
          throw StateError('Fresh cache should not request data');
        },
      );
      addTearDown(restarted.dispose);
      await restarted.ready;
      expect(restarted.hasChecked, isTrue);
      expect(restarted.lastCheck, checkedAt);
      await _pastDebounce();
      expect(requested, isFalse);
      expect(restarted.notice, isNull);
    },
  );

  test(
    'restart refreshes five-minute quotes but retains younger books',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final first = fixture.controller.market.items.keys.first;
      final before = fixture.now;
      fixture.now = fixture.now.add(const Duration(minutes: 3));
      fixture.failNextParts = {
        for (final id in _rewardIds('witchs-delicacy')) 'q$id': 503,
      };
      await fixture.controller.refresh();
      await fixture.controller.ensureMarketDepth(_rewardIds('witchs-delicacy'));
      await fixture.controller.flush();
      fixture.disposeController();
      fixture.now = before.add(const Duration(minutes: 5, seconds: 1));
      final transport = _RecordedTransport('eu', () => fixture.now);
      final restarted = OpportunitiesController(
        appController: fixture.harness.bundle.controller,
        catalog: CatalogRepository(fixture.harness.bundle.catalog),
        directory: fixture.harness.temporaryDirectory,
        clock: () => fixture.now,
        autoCheck: true,
        serviceFactory: (region) => OpportunityMarketService(
          region: region,
          transport: transport,
          utcNow: () => fixture.now,
          concurrency: 1,
          quoteBatchSize: 1,
          requestSpacing: Duration.zero,
        ),
      );
      addTearDown(restarted.dispose);
      await restarted.ready;
      expect(
        restarted.hasChecked,
        isTrue,
        reason:
            'Old receipts remain displayable while their replacements load.',
      );
      expect(restarted.market.items[first]!.quoteFetchedAt, before);
      expect(
        restarted.market.items[first]!.bookFetchedAt,
        before.add(const Duration(minutes: 3)),
      );
      await _until(() => transport.closed && !restarted.scanning);
      expect(transport.requests.every((request) => !request.book), isTrue);
      expect(
        transport.requests.map((request) => request.id).toSet(),
        _rewardIds('witchs-delicacy'),
      );
      expect(restarted.hasChecked, isTrue);
      expect(
        restarted.market.items[first]!.bookFetchedAt,
        before.add(const Duration(minutes: 3)),
      );
      await restarted.flush();
    },
  );

  test(
    'background expiry clears stale calculated profit without a user action',
    () async {
      final fixture = await _Fixture.create(
        seedAlmostExpired: true,
        autoCheck: false,
      );
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.cancel();
      controller.change((p) {
        p.section = 'crafting';
        p.mode = CraftMode.cooking;
      }, assemble: true);
      controller.cancel();
      await controller.calculationSettled;
      expect(
        controller.quotes.any((quote) => quote.listingRevenue != null),
        isTrue,
      );
      expect(controller.hasChecked, isTrue);
      fixture.now = fixture.now.add(const Duration(milliseconds: 250));
      await _until(
        () =>
            !controller.calculating &&
            controller.quotes.isNotEmpty &&
            controller.quotes.every((quote) => quote.listingRevenue == null),
      );
      controller.cancel();
      expect(controller.hasChecked, isFalse);
      expect(fixture.sessions, isEmpty);
    },
  );

  test(
    'exact three-hour boundary is valid; one millisecond later is not',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.waitForChecks(1);
      final controller = fixture.controller;
      fixture.now = fixture.now.add(const Duration(hours: 3));
      controller.recalculate();
      expect(controller.hasChecked, isTrue);
      final route = controller.exchangeQuotes.firstWhere(
        (quote) =>
            quote.route.rewards.any(
              (reward) => reward.item?.marketable == true,
            ) &&
            quote.netProceeds != null,
      );
      fixture.now = fixture.now.add(const Duration(milliseconds: 1));
      controller.recalculate();
      controller.cancel();
      expect(controller.hasChecked, isFalse);
      expect(
        controller.exchangeQuotes
            .firstWhere((quote) => quote.route.id == route.route.id)
            .netProceeds,
        isNull,
      );
      expect(fixture.sessions, hasLength(1));
    },
  );

  test('raw cache write is off the request path and flush awaits it', () async {
    final committer = _HeldCommitter();
    final fixture = await _Fixture.create(cacheCommitter: committer);
    addTearDown(fixture.dispose);
    addTearDown(() {
      if (!committer.release.isCompleted) committer.release.complete();
    });
    await fixture.waitForChecks(1);
    await committer.started.future;
    expect(fixture.controller.scanning, isFalse);
    expect(fixture.controller.hasChecked, isTrue);
    var flushed = false;
    final flush = fixture.controller.flush().then((_) => flushed = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(flushed, isFalse);
    committer.release.complete();
    await flush;
    expect(
      committer.commits,
      1,
      reason: 'Flush does not duplicate the queued receipt revision.',
    );
    final saved = await OpportunityMarketCacheStore(
      directory: fixture.harness.temporaryDirectory,
      utcNow: () => fixture.now,
    ).load();
    expect(saved['eu']!.keys.toSet(), _rewardIds('witchs-delicacy'));
  });
  test(
    'backend slowdown carries across refreshes only in its current region',
    () async {
      final fixture = await _Fixture.create(concurrency: 8);
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.cancel();
      final first = _rewardIds('witchs-delicacy').first;
      fixture.failNextParts = {'q$first': 503};
      await controller.refresh();
      expect(fixture.services.last.effectiveConcurrency, 4);
      await controller.refresh();
      expect(fixture.services.last.effectiveConcurrency, 4);
      controller.change((p) => p.region = 'na');
      controller.cancel();
      await controller.refresh();
      expect(fixture.services.last.effectiveConcurrency, 8);
      controller.change((p) => p.region = 'eu');
      controller.cancel();
      await controller.refresh();
      expect(fixture.services.last.effectiveConcurrency, 4);
      await controller.flush();
      final saved = await OpportunitiesPreferenceStore(
        fixture.harness.temporaryDirectory,
      ).load();
      expect(jsonEncode(saved.toJson()), isNot(contains('concurrency')));
    },
  );
  test(
    'cache expiry does not cancel an already active manual refresh',
    () async {
      final fixture = await _Fixture.create(
        seedAlmostExpired: true,
        holdFirstCheck: true,
      );
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.cancel();
      final refresh = controller.refresh();
      await _until(
        () =>
            fixture.sessions.isNotEmpty &&
            fixture.sessions.first.requests.isNotEmpty,
      );
      fixture.now = fixture.now.add(const Duration(milliseconds: 250));
      await _pastDebounce();
      expect(controller.scanning, isTrue);
      expect(controller.hasChecked, isFalse);
      expect(fixture.sessions, hasLength(1));
      expect(fixture.sessions.single.aborted, isFalse);
      controller.cancel();
      await refresh;
      await _until(() => fixture.sessions.single.aborted);
      expect(fixture.sessions.single.aborted, isTrue);
    },
  );
  test(
    'expiry cannot restart network during flush; tab return revalidates afterward',
    () async {
      final committer = _HeldCommitter();
      final fixture = await _Fixture.create(
        seedAlmostExpired: true,
        cacheCommitter: committer,
      );
      addTearDown(fixture.dispose);
      addTearDown(() {
        if (!committer.release.isCompleted) committer.release.complete();
      });
      final controller = fixture.controller;
      final plannerBefore = fixture.harness.bundle.controller.documentSnapshot;
      controller.cancel();
      await controller.refresh();
      await committer.started.future;
      controller.change((p) {
        p.section = 'crafting';
        p.mode = CraftMode.cooking;
      }, assemble: true);
      var flushed = false;
      final flush = controller.flush().then((_) => flushed = true);
      await controller.calculationSettled;
      expect(
        controller.quotes.any((quote) => quote.listingRevenue != null),
        isTrue,
      );
      fixture.now = fixture.now.add(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(flushed, isFalse);
      expect(fixture.sessions, hasLength(1));
      expect(controller.scanning, isFalse);
      committer.release.complete();
      await flush;
      await _pastDebounce();
      expect(
        fixture.sessions,
        hasLength(1),
        reason: 'Flush return does not silently restart the queue.',
      );
      controller.ensureMarketCurrent();
      expect(
        controller.quotes,
        isEmpty,
        reason: 'The expired visible profit is invalidated immediately.',
      );
      expect(controller.hasChecked, isFalse);
      await fixture.waitForChecks(2);
      expect(controller.hasChecked, isTrue);
      expect(
        controller.quotes.any((quote) => quote.listingRevenue != null),
        isTrue,
      );
      expect(
        fixture.harness.bundle.controller.documentSnapshot,
        same(plannerBefore),
      );
    },
  );
}

Set<String> _rewardIds(String currencyId) => {
  for (final route
      in exchangeCatalog.firstWhere((c) => c.id == currencyId).routes)
    for (final reward in route.rewards)
      if (reward.item?.marketable == true) '${reward.item!.id}',
};

Set<String> _allIds(_Fixture fixture) {
  final app = fixture.harness.bundle.controller;
  final snapshot = fixture.harness.bundle.catalog;
  final catalog = CatalogRepository(snapshot);
  final ids = <String>{};
  for (final mode in CraftMode.values) {
    final recipes = app.assembly.assembleRecipes(
      catalog: snapshot.forMode(mode),
      state: app.modes[mode]!.state.value,
      supportingData: snapshot.supportingData,
      sharedMetadata: snapshot.alchemy.metadata,
      mode: mode,
    );
    for (final recipe in recipes.values.where(
      (recipe) => recipe.isCraftable && recipe.type.toLowerCase() == mode.key,
    )) {
      ids.addAll(
        const OpportunityCalculator().marketItemIds(
          recipe: recipe,
          recipes: recipes,
          rules: app.plannerRules,
        ),
      );
      // Some supporting/quality items have IDs only in the shared catalog.
      // Startup resolves those too, not just the IDs on a mode's recipe rows.
      for (final name in const OpportunityCalculator().marketItemNames(
        recipe: recipe,
        recipes: recipes,
        rules: app.plannerRules,
      )) {
        final id = recipes[name]?.marketId ?? catalog.bundledMarketId(name);
        if (id != null) ids.add(id);
      }
    }
  }
  for (final currency in exchangeCatalog) {
    ids.addAll(_rewardIds(currency.id));
  }
  return ids.where(isOpportunityMarketRequestEligible).toSet();
}

Future<void> _pastDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 500));

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Automatic market check did not reach the expected state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  final List<_RecordedTransport> sessions = [];
  final List<OpportunityMarketService> services = [];
  late final OpportunitiesController controller;
  DateTime now = DateTime.utc(2026, 9, 8, 20);
  bool _controllerDisposed = false;
  Map<String, int> failNextParts = {};

  static Future<_Fixture> create({
    bool autoCheck = true,
    bool holdFirstCheck = false,
    bool failFactory = false,
    bool prefetchAll = false,
    String? failFirstBookId,
    int? holdAfterRequests,
    int? failFirstRequestStatus,
    Map<String, String> firstRequestHeaders = const {},
    AtomicFileCommitter? observationCommitter,
    AtomicFileCommitter? cacheCommitter,
    bool seedAlmostExpired = false,
    int concurrency = 1,
  }) async {
    final harness = await ApplicationTestHarness.create();
    final fixture = _Fixture(harness);
    final preferences = OpportunitiesPreferences()
      ..section = 'exchanges'
      ..currencyId = 'witchs-delicacy';
    await OpportunitiesPreferenceStore(
      harness.temporaryDirectory,
    ).save(preferences);
    if (seedAlmostExpired) {
      final at = fixture.now
          .subtract(const Duration(hours: 3))
          .add(const Duration(milliseconds: 200));
      await OpportunityMarketCacheStore(
        directory: harness.temporaryDirectory,
        utcNow: () => fixture.now,
      ).save({
        'eu': {
          for (final id in _allIds(fixture))
            id: OpportunityMarketItem(
              itemId: id,
              basePrice: 1000,
              stock: 1000000,
              quoteFetchedAt: at,
              asks: const [
                OpportunityMarketLevel(price: 1000, quantity: 1000000),
              ],
              bids: const [],
              bookFetchedAt: at,
            ),
        },
      });
    }
    fixture.controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: CatalogRepository(harness.bundle.catalog),
      directory: harness.temporaryDirectory,
      autoCheck: autoCheck,
      prefetchAll: prefetchAll,
      clock: () => fixture.now,
      marketCacheStore: cacheCommitter == null
          ? null
          : OpportunityMarketCacheStore(
              directory: harness.temporaryDirectory,
              utcNow: () => fixture.now,
              committer: cacheCommitter,
            ),
      observationStore: observationCommitter == null
          ? null
          : OpportunityMarketObservationStore(
              directory: harness.temporaryDirectory,
              utcNow: () => fixture.now,
              committer: observationCommitter,
            ),
      serviceFactory: (region) {
        if (failFactory) {
          throw StateError('Synthetic transport construction failure');
        }
        final transport = _RecordedTransport(
          region,
          () => fixture.now,
          hold: holdFirstCheck && fixture.sessions.isEmpty,
          failBookId: fixture.sessions.isEmpty ? failFirstBookId : null,
          holdAfterRequests: holdAfterRequests,
          failFirstRequestStatus: fixture.sessions.isEmpty
              ? failFirstRequestStatus
              : null,
          firstRequestHeaders: firstRequestHeaders,
          failures: fixture.failNextParts,
        );
        fixture.failNextParts = {};
        fixture.sessions.add(transport);
        final service = OpportunityMarketService(
          region: region,
          transport: transport,
          utcNow: () => fixture.now,
          requestSpacing: Duration.zero,
          orderBookRequestSpacing: Duration.zero,
          recoveryRequestSpacing: Duration.zero,
          concurrency: concurrency,
          quoteBatchSize: 1,
        );
        fixture.services.add(service);
        return service;
      },
    );
    await fixture.controller.ready;
    return fixture;
  }

  Future<void> waitForChecks(int count) async {
    await _until(
      () =>
          sessions.length >= count &&
          sessions[count - 1].closed &&
          !controller.scanning,
    );
    await controller.calculationSettled;
  }

  void disposeController() {
    if (_controllerDisposed) return;
    controller.dispose();
    _controllerDisposed = true;
  }

  Future<void> dispose() async {
    if (!_controllerDisposed) await controller.flush();
    disposeController();
    await harness.dispose();
  }
}

final class _RecordedTransport implements OpportunityMarketTransport {
  _RecordedTransport(
    this.region,
    this.now, {
    this.hold = false,
    this.failBookId,
    this.holdAfterRequests,
    this.failFirstRequestStatus,
    this.firstRequestHeaders = const {},
    this.failures = const {},
  });
  final String region;
  final DateTime Function() now;
  final bool hold;
  final String? failBookId;
  final int? holdAfterRequests;
  final int? failFirstRequestStatus;
  final Map<String, String> firstRequestHeaders;
  final Map<String, int> failures;
  final List<({String id, String host, bool book})> requests = [];
  final release = Completer<void>();
  bool closed = false;
  bool aborted = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final id = '${(jsonDecode(body) as Map)['mainKey']}';
    final book = uri.path.endsWith('GetBiddingInfoList');
    requests.add((id: id, host: uri.host, book: book));
    // Exercise the actual first dispatch, independently of priority ordering.
    if (requests.length == 1 && failFirstRequestStatus != null) {
      return OpportunityHttpResponse(
        statusCode: failFirstRequestStatus!,
        headers: firstRequestHeaders,
        bytes: Uint8List(0),
      );
    }
    if (hold ||
        (holdAfterRequests != null && requests.length > holdAfterRequests!)) {
      final released = await Future.any<bool>([
        release.future.then((_) => true),
        if (abortTrigger != null) abortTrigger.then((_) => false),
      ]);
      if (!released) {
        aborted = true;
        throw const MarketFetchCancelledException();
      }
    }
    if (book && id == failBookId) {
      return OpportunityHttpResponse(statusCode: 503, bytes: Uint8List(0));
    }
    final failure = failures['${book ? 'b' : 'q'}$id'];
    if (failure != null) {
      return OpportunityHttpResponse(statusCode: failure, bytes: Uint8List(0));
    }
    final text = book
        ? '1000-0-100|1010-100-0|'
        : '$id-0-0-1000-100-500000-100-10000-1000-${now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000}|';
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

final class _HeldCommitter implements AtomicFileCommitter {
  final started = Completer<void>();
  final release = Completer<void>();
  var commits = 0;
  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    commits++;
    if (!started.isCompleted) started.complete();
    await release.future;
    await stagedFile.rename(targetFile.path);
  }
}
