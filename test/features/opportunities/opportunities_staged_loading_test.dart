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

  test(
    'whole catalog startup completes all basic quotes without any books',
    () async {
      final f = await _Fixture.create(startup: true);
      addTearDown(f.dispose);
      await _until(
        () => f.controller.summaryComplete && !f.controller.scanning,
      );
      expect(f.transport.quotes.length, greaterThan(1000));
      expect(f.transport.books, isEmpty);
      expect(f.transport.requests.length, f.transport.quotes.toSet().length);
      expect(f.controller.summaryStatus.loaded, f.transport.quotes.length);
      expect(f.controller.summaryStatus.failed, 0);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.hasChecked, isTrue);
    },
  );

  test(
    'preorder window resumes automatically and keeps loaded quotes usable',
    () async {
      final f = await _Fixture.create(
        requestWindowLimit: 2,
        requestWindowDuration: const Duration(milliseconds: 250),
      );
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.controller.calculationSettled;
      final saved = Map.of(f.controller.market.items);
      final quotes = f.controller.quotes.toList();
      f.transport.requests.clear();
      final details = f.controller.ensureMarketDepth(['9101', '9102', '9201']);
      await _until(() => f.controller.activeDispatchWait > Duration.zero);
      expect(f.controller.scanning, isTrue);
      expect(f.controller.summaryComplete, isTrue);
      expect(f.controller.quotes.length, quotes.length);
      for (final entry in saved.entries) {
        expect(
          f.controller.market.items[entry.key]!.quoteFetchedAt,
          entry.value.quoteFetchedAt,
        );
      }
      await details;
      expect(f.transport.books.toSet(), {'9101', '9102', '9201'});
      expect(f.transport.quotes, isEmpty);
      expect(f.controller.detailStatus.complete, isTrue);
      expect(f.controller.activeDispatchWait, Duration.zero);
      expect(f.controller.summaryComplete, isTrue);
    },
  );

  test(
    'global toolbar Refresh renews all summaries without reviving closed books',
    () async {
      final f = await _Fixture.create(startup: true);
      addTearDown(f.dispose);
      await _until(
        () => f.controller.summaryComplete && !f.controller.scanning,
      );
      final allIds = f.transport.quotes.toSet();
      final sampleId = allIds.first;
      await f.controller.ensureMarketDepth([sampleId]);
      final bookAt = f.controller.market.items[sampleId]!.bookFetchedAt;
      await f.controller.ensureMarketDepth([]);
      f.controller.change((p) {
        p.section = 'exchanges';
        p.currencyId = 'witchs-delicacy';
      });
      f.now = f.now.add(const Duration(minutes: 1));
      f.transport.requests.clear();
      await f.controller.refresh();
      expect(f.transport.quotes.toSet(), allIds);
      expect(f.transport.quotes.length, allIds.length);
      expect(f.transport.books, isEmpty);
      expect(f.controller.market.items[sampleId]!.quoteFetchedAt, f.now);
      expect(f.controller.market.items[sampleId]!.bookFetchedAt, bookAt);
      expect(f.controller.summaryComplete, isTrue);
    },
  );

  test(
    'saved Demand preference remains quote-only while workspace is hidden',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.controller.change((p) => p.craftSort = 'preorders');
      await f.controller.refresh();
      await f.controller.calculationSettled;
      expect(f.transport.books, isEmpty);
      expect(f.controller.detailStatus.requested, isFalse);
    },
  );

  test(
    'recipe inspection requests only selected formula candidates and output',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      final quoteTimes = {
        for (final entry in f.controller.market.items.entries)
          entry.key: entry.value.quoteFetchedAt,
      };
      f.transport.requests.clear();
      final recipe = f.controller.recipes['First']!;
      f.controller.setInspectedRecipe(recipe, selectedVariantId: 'one');
      await _until(() => f.controller.detailStatus.complete);
      expect(f.transport.books.toSet(), {'9101', '9201', '9203'});
      expect(f.transport.quotes, isEmpty);
      f.transport.requests.clear();
      f.controller.setInspectedRecipe(recipe, selectedVariantId: 'two');
      await _until(
        () => f.controller.detailStatus.complete && !f.controller.scanning,
      );
      expect(f.transport.books, ['9202']);
      expect(f.controller.detailStatus.total, 2);
      for (final entry in quoteTimes.entries) {
        expect(
          f.controller.market.items[entry.key]!.quoteFetchedAt,
          entry.value,
        );
      }
      f.controller.setInspectedRecipe(null);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.summaryComplete, isTrue);
    },
  );

  test(
    'rare inspection uses requested output identity and not normal output',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      f.transport.requests.clear();
      f.controller.setInspectedRecipe(
        f.controller.recipes['First'],
        selectedVariantId: 'one',
        itemName: 'Rare First',
      );
      await _until(
        () => f.controller.detailStatus.complete && !f.controller.scanning,
      );
      expect(f.transport.books.toSet(), {'9199', '9201', '9203'});
      expect(f.transport.quotes, ['9199']);
      expect(f.transport.books, isNot(contains('9101')));
    },
  );

  test('invalid inspected formula does not fan out to every variant', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.controller.refresh();
    f.transport.requests.clear();
    f.controller.setInspectedRecipe(
      f.controller.recipes['First'],
      selectedVariantId: 'missing',
    );
    await Future<void>.delayed(Duration.zero);
    expect(f.transport.requests, isEmpty);
    expect(f.controller.detailStatus.requested, isFalse);
  });

  test(
    'Demand loads filtered outputs only and never their ingredient books',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.controller.calculationSettled;
      f.transport.requests.clear();
      f.controller.change((p) {
        p.craftSearch = 'First';
        p.craftSort = 'preorders';
        p.profitableOnly = false;
      });
      f.controller.setWorkspaceActive(true);
      await _until(
        () => f.controller.detailStatus.complete && !f.controller.scanning,
      );
      expect(f.transport.books, ['9101']);
      expect(f.transport.quotes, isEmpty);
      expect(f.controller.detailStatus.total, 1);
      f.controller.change((p) => p.craftSort = 'profit');
      expect(f.controller.detailStatus.requested, isFalse);
    },
  );

  test(
    'a blocked detail does not undo completed basic prices and stock',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      final price = f.controller.market.items['9101']!;
      f.transport.protectedBooks = true;
      await f.controller.ensureMarketDepth(['9101']);
      expect(f.controller.summaryStatus.complete, isTrue);
      expect(f.controller.summaryStatus.failed, 0);
      expect(f.controller.summaryNotice, isNull);
      expect(f.controller.detailStatus.complete, isFalse);
      expect(f.controller.detailStatus.failed, 1);
      expect(f.controller.detailStatus.blocked, isTrue);
      expect(f.controller.detailNotice, contains('blocked'));
      expect(
        f.controller.market.items['9101']!.quoteFetchedAt,
        price.quoteFetchedAt,
      );
      expect(f.controller.market.items['9101']!.stock, 50);
      expect(f.controller.market.items['9101']!.preorderCount, isNull);
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(minutes: 2));
      await f.controller.ensureMarketDepth(['9101']);
      expect(f.transport.requests, hasLength(count));
      await f.controller.ensureMarketDepth([]);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.failedItems, 0);
    },
  );

  test(
    'zero listed stock never manufactures a preorder without its book',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.zeroStockIds.add('9101');
      await f.controller.refresh();
      expect(f.controller.market.items['9101']!.stock, 0);
      expect(f.controller.market.items['9101']!.preorderCount, isNull);
      expect(f.transport.books, isEmpty);
      expect(f.controller.summaryStatus.complete, isTrue);
    },
  );

  test(
    'detail requested during summary waits without discarding summary work',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.heldPart = _part('9101', false);
      final summary = f.controller.refresh();
      await f.transport.held.future;
      final details = f.controller.ensureMarketDepth(['9102']);
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.aborted, isFalse);
      f.transport.release.complete();
      await summary;
      await details;
      expect(f.controller.summaryComplete, isTrue);
      expect(f.controller.detailStatus.complete, isTrue);
      expect(f.transport.books, ['9102']);
    },
  );

  test(
    'closing detail releases its pending scope and preserves the quote',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      f.transport.requests.clear();
      f.transport.heldPart = _part('9101', true);
      final details = f.controller.ensureMarketDepth(['9101', '9102']);
      await f.transport.held.future;
      await f.controller.ensureMarketDepth([]);
      await details;
      expect(f.transport.aborted, isTrue);
      expect(f.transport.books, ['9101']);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.summaryComplete, isTrue);
      expect(f.controller.market.items['9101']!.bookFetchedAt, isNull);
      expect(f.controller.summaryNotice, isNull);
    },
  );

  for (final stop in [false, true]) {
    test(
      'narrowing detail retains its held book${stop ? ' until explicit Stop' : ''}',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.controller.refresh();
        final quoteAt = f.controller.market.items['9101']!.quoteFetchedAt;
        f.now = f.now.add(const Duration(minutes: 1));
        f.transport.requests.clear();
        f.transport.heldPart = _part('9101', true);
        final details = f.controller.ensureMarketDepth(['9101', '9102']);
        await f.transport.held.future;
        final narrowed = f.controller.ensureMarketDepth(['9101']);
        await Future<void>.delayed(Duration.zero);
        expect(f.transport.aborted, isFalse);
        expect(f.controller.detailStatus.total, 1);
        expect(f.controller.detailStatus.loaded, 0);
        expect(f.controller.detailStatus.failed, 0);
        expect(f.controller.progressFraction, 0);
        if (stop) {
          f.controller.cancel();
        } else {
          f.transport.release.complete();
        }
        await Future.wait([details, narrowed]);
        expect(f.transport.books, ['9101']);
        expect(f.transport.aborted, stop);
        expect(f.controller.detailStatus.failed, 0);
        expect(f.controller.detailStatus.complete, !stop);
        expect(f.controller.market.items['9101']!.quoteFetchedAt, quoteAt);
        expect(
          f.controller.market.items['9101']!.bookFetchedAt,
          stop ? null : f.now,
        );
        expect(f.controller.market.items['9102']!.bookFetchedAt, isNull);
        expect(
          f.controller.summaryNotice,
          stop ? 'Stopped. Loaded prices are kept.' : isNull,
        );
      },
    );
  }

  test(
    'replacing detail queues only added books after retained work completes',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      f.transport.requests.clear();
      f.transport.heldPart = _part('9101', true);
      final details = f.controller.ensureMarketDepth(['9101', '9102']);
      await f.transport.held.future;
      final replaced = f.controller.ensureMarketDepth(['9101', '9201']);
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.aborted, isFalse);
      expect(f.controller.detailStatus.total, 2);
      f.transport.release.complete();
      await Future.wait([details, replaced]);
      expect(f.transport.books, ['9101', '9201']);
      expect(f.controller.detailStatus.complete, isTrue);
      expect(f.controller.detailStatus.failed, 0);
      expect(f.controller.detailNotice, isNull);
      expect(f.controller.market.items['9102']!.bookFetchedAt, isNull);
    },
  );

  test(
    'nested recipe browsing reuses six-minute books and fetches only a new formula input',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      final first = f.controller.recipes['First']!;
      f.controller.setInspectedRecipe(first, selectedVariantId: 'one');
      await f.controller.ensureMarketDepth([]);
      expect(f.controller.detailStatus.complete, isTrue);
      final loadedBooks = f.transport.books.toSet();
      final at = f.now;
      f.controller.setInspectedRecipe(null);
      await f.controller.ensureMarketDepth([]);
      f.now = at.add(const Duration(minutes: 6));
      f.transport.requests.clear();

      f.controller.setInspectedRecipe(first, selectedVariantId: 'one');
      await f.controller.ensureMarketDepth([]);
      expect(f.transport.requests, isEmpty);
      expect(f.controller.detailStatus.complete, isTrue);
      for (final id in loadedBooks) {
        expect(f.controller.market.items[id]!.bookFetchedAt, at);
      }
      f.controller.setInspectedRecipe(first, selectedVariantId: 'two');
      await f.controller.ensureMarketDepth([]);
      expect(f.transport.books, ['9202']);
      expect(f.transport.quotes, isEmpty);
      expect(f.controller.market.items['9202']!.bookFetchedAt, f.now);
      expect(f.controller.market.items['9202']!.quoteFetchedAt, at);
    },
  );

  test(
    'same-tab depth keeps the thirty-minute boundary but rechecks on later use',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.controller.ensureMarketDepth(['9101']);
      final at = f.now;
      f.transport.requests.clear();
      f.now = at.add(OpportunitiesController.inWorkspaceMarketAge);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(f.transport.requests, isEmpty, reason: 'Idle age is not a check.');
      await f.controller.ensureMarketDepth(['9101']);
      expect(f.transport.requests, isEmpty);
      expect(f.controller.market.items['9101']!.bookFetchedAt, at);

      f.now = f.now.add(const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(f.transport.requests, isEmpty);
      f.transport.heldPart = _part('9101', false);
      final check = f.controller.ensureMarketDepth(['9101']);
      await f.transport.held.future;
      expect(
        f.controller.market.items['9101']!.quoteFetchedAt,
        at,
        reason: 'Original receipts remain visible while replacements load.',
      );
      f.transport.release.complete();
      await check;
      expect(f.transport.quotes, ['9101']);
      expect(f.transport.books, ['9101']);
      expect(f.controller.market.items['9101']!.quoteFetchedAt, f.now);
      expect(f.controller.market.items['9101']!.bookFetchedAt, f.now);
    },
  );

  test(
    'true tab return keeps the stricter five-minute Demand check when browsing coalesces',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.controller.preferences
        ..profitableOnly = false
        ..craftSort = 'preorders';
      await f.controller.refresh();
      f.controller.setWorkspaceActive(true);
      await f.controller.ensureMarketDepth([]);
      final outputs = f.transport.books.toSet();
      expect(outputs, {'9101', '9102'});
      final at = f.now;
      f.controller.setWorkspaceActive(false);
      f.now = at.add(const Duration(minutes: 6));
      f.transport.requests.clear();

      // The application host activates the actual scope before tab-entry
      // validation. A same-tab request queued immediately afterward is30m.
      f.controller.setWorkspaceActive(true);
      f.controller.ensureMarketCurrent();
      await f.controller.ensureMarketDepth([]);
      expect(f.transport.books.toSet(), outputs);
      expect(f.transport.quotes.toSet(), outputs);
      expect(f.transport.requests, hasLength(outputs.length * 2));
      for (final id in outputs) {
        expect(f.controller.market.items[id]!.quoteFetchedAt, f.now);
        expect(f.controller.market.items[id]!.bookFetchedAt, f.now);
      }
      expect(
        f.controller.market.items['9201']!.quoteFetchedAt,
        at,
        reason: 'A detail-only check does not refresh unrelated ingredients.',
      );
      f.transport.requests.clear();
      await f.controller.ensureMarketDepth(['9201']);
      expect(f.transport.books, ['9201']);
      expect(
        f.transport.quotes,
        isEmpty,
        reason: 'Entry must not leave a five-minute flag on later browsing.',
      );
    },
  );

  test(
    'Opportunities thirty-minute reuse does not extend another feature cache',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.controller.ensureMarketDepth(['9101']);
      final at = f.now;
      f.now = at.add(const Duration(minutes: 6));
      f.transport.requests.clear();
      await f.controller.ensureMarketDepth(['9101']);
      expect(f.transport.requests, isEmpty);
      await f.broker.fetch(quoteKeys: [_part('9101', false).key]);
      expect(f.transport.quotes, ['9101']);
      expect(f.transport.books, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(f.controller.market.items['9101']!.quoteFetchedAt, f.now);
      expect(f.controller.market.items['9101']!.bookFetchedAt, at);
      f.transport.requests.clear();
      await f.controller.ensureMarketDepth(['9101']);
      expect(f.transport.requests, isEmpty);
    },
  );

  test(
    'manual Refresh bypasses thirty-minute automatic reuse and honors sixty-second cooldown',
    () async {
      final f = await _Fixture.create(
        minimumRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.controller.ensureMarketDepth(['9101']);
      final at = f.now;
      f.transport.requests.clear();
      f.now = at.add(const Duration(seconds: 59));
      await f.controller.refresh();
      expect(f.transport.requests, isEmpty);
      f.now = at.add(const Duration(minutes: 1));
      await f.controller.refresh();
      expect(f.transport.quotes, isNotEmpty);
      expect(f.transport.books, ['9101']);
      expect(f.controller.market.items['9101']!.quoteFetchedAt, f.now);
      expect(f.controller.market.items['9101']!.bookFetchedAt, f.now);
    },
  );

  test(
    'ordinary stale check refreshes quotes but not previously closed books',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.controller.ensureMarketDepth(['9101']);
      final oldBookAt = f.controller.market.items['9101']!.bookFetchedAt;
      await f.controller.ensureMarketDepth([]);
      f.now = f.now.add(const Duration(hours: 4));
      f.transport.requests.clear();
      await f.controller.refresh(onlyStale: true);
      expect(f.transport.quotes, isNotEmpty);
      expect(f.transport.books, isEmpty);
      expect(f.controller.market.items['9101']!.bookFetchedAt, oldBookAt);
      expect(f.controller.summaryComplete, isTrue);
    },
  );

  test(
    'region changes release the old detail scope instead of reviving it',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      f.transport.requests.clear();
      f.transport.heldPart = _part('9101', true);
      final details = f.controller.ensureMarketDepth(['9101', '9102']);
      await f.transport.held.future;
      f.controller.change((p) => p.region = 'na');
      await details;
      expect(f.transport.aborted, isTrue);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.market.items['9101'], isNull);
      await f.controller.refresh();
      expect(f.controller.summaryComplete, isTrue);
      f.controller.change((p) => p.region = 'eu');
      await f.controller.refresh(onlyStale: true);
      expect(f.controller.summaryComplete, isTrue);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.transport.books, ['9101']);
      expect(f.controller.market.items['9101']!.bookFetchedAt, isNull);
    },
  );

  test(
    'closing detail does not cancel a shared book needed by another feature',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      f.transport.requests.clear();
      f.transport.heldPart = _part('9101', true);
      final sibling = f.broker.fetch(bookKeys: [_part('9101', true).key]);
      await f.transport.held.future;
      final details = f.controller.ensureMarketDepth(['9101']);
      await _until(() => f.controller.scanning);
      await f.controller.ensureMarketDepth([]);
      await details;
      expect(f.transport.aborted, isFalse);
      expect(f.transport.books, ['9101']);
      f.transport.release.complete();
      final result = await sibling;
      expect(result.failures, isEmpty);
      await _until(
        () => f.controller.market.items['9101']!.bookFetchedAt != null,
      );
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.summaryComplete, isTrue);
    },
  );
}

SharedMarketPartKey _part(String id, bool book, {String region = 'eu'}) =>
    SharedMarketPartKey(
      SharedMarketKey(region: region, itemId: id),
      book ? SharedMarketPart.orderBook : SharedMarketPart.quote,
    );

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 10, 19);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;

  static Future<_Fixture> create({
    bool startup = false,
    Duration minimumRefreshAge = Duration.zero,
    int? requestWindowLimit,
    Duration requestWindowDuration = const Duration(minutes: 1),
  }) async {
    final f = _Fixture(await ApplicationTestHarness.create());
    f.transport = _Transport(() => f.now);
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      quoteBatchSize: startup ? 40 : 1,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      concurrency: 1,
      cacheMaxAge: sharedMarketFreshness,
      minimumQuoteRefreshAge: minimumRefreshAge,
      minimumBookRefreshAge: minimumRefreshAge,
      requestWindowLimit: requestWindowLimit,
      requestWindowDuration: requestWindowDuration,
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      clock: () => f.now,
      sharedMarket: f.broker,
      autoCheck: startup,
      prefetchAll: startup,
    );
    await f.controller.ready;
    if (!startup) {
      f.controller.recipes = {
        'First': _recipe(
          'First',
          '9101',
          input: 'Raw A',
          variants: [
            RecipeVariant(
              id: 'one',
              label: 'First formula',
              type: 'cooking',
              method: null,
              baseOutput: 1,
              outputMinimum: 1,
              outputMaximum: 1,
              ingredients: [
                _ingredient('Raw A', ['Raw C']),
              ],
            ),
            RecipeVariant(
              id: 'two',
              label: 'Second formula',
              type: 'cooking',
              method: null,
              baseOutput: 1,
              outputMinimum: 1,
              outputMaximum: 1,
              ingredients: [_ingredient('Raw B')],
            ),
          ],
        ),
        'Second': _recipe('Second', '9102', input: 'Raw B'),
        'Rare First': _recipe('Rare First', '9199'),
        'Raw A': _recipe('Raw A', '9201'),
        'Raw B': _recipe('Raw B', '9202'),
        'Raw C': _recipe('Raw C', '9203'),
      };
      f.controller.recalculate();
      await f.controller.calculationSettled;
    }
    return f;
  }

  Future<void> dispose() async {
    controller.cancel();
    if (!transport.release.isCompleted) transport.release.complete();
    await broker.close();
    // Drain queued broker receipts before the controller's final history save.
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

Ingredient _ingredient(String name, [List<String> options = const []]) =>
    Ingredient(
      name: name,
      quantity: 1,
      options: options,
      substituteGroup: null,
      substituteRatios: const {},
    );

Recipe _recipe(
  String name,
  String id, {
  String? input,
  List<RecipeVariant> variants = const [],
}) => Recipe(
  name: name,
  type: input == null ? 'gathered' : 'cooking',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [if (input != null) _ingredient(input)],
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 2,
  outputMaximum: 2,
  variants: variants,
);

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.now);
  final DateTime Function() now;
  final List<SharedMarketPartKey> requests = [];
  Iterable<String> get quotes => requests
      .where((part) => part.part == SharedMarketPart.quote)
      .map((part) => part.key.itemId);
  Iterable<String> get books => requests
      .where((part) => part.part == SharedMarketPart.orderBook)
      .map((part) => part.key.itemId);
  final Set<String> zeroStockIds = {};
  bool protectedBooks = false;
  SharedMarketPartKey? heldPart;
  final held = Completer<void>();
  final release = Completer<void>();
  bool aborted = false;

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
    final region = uri.host.startsWith('na-') ? 'na' : 'eu';
    final parts = ids.map((id) => _part(id, book, region: region)).toList();
    requests.addAll(parts);
    if (parts.contains(heldPart) && !release.isCompleted) {
      if (!held.isCompleted) held.complete();
      await Future.any([
        release.future,
        if (abortTrigger != null)
          abortTrigger.then((_) {
            aborted = true;
            throw const MarketFetchCancelledException();
          }),
      ]);
    }
    if (book && protectedBooks) {
      return OpportunityHttpResponse(
        statusCode: 200,
        bytes: Uint8List.fromList(
          utf8.encode('<html>Incapsula incident ID</html>'),
        ),
      );
    }
    int stock(String id) => zeroStockIds.contains(id) ? 0 : 50;
    final text = ids.length > 1
        ? ids.map((id) => '$id-${stock(id)}-1000-500000').join('|')
        : book
        ? '1000-50-3|'
        : '${ids.single}-0-0-1000-${stock(ids.single)}-500000-100-10000-1000-${now().millisecondsSinceEpoch ~/ 1000}|';
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
    if (DateTime.now().isAfter(deadline)) {
      fail('Staged market load did not settle.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
