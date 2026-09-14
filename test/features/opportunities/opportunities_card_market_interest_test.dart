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
    'registration is build-safe, idempotent and output-only in Profit sort',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final owner = Object();
      var notifications = 0;
      f.controller.addListener(() => notifications++);
      final original = f.controller.market.items['9101']!;
      expect(original.stock, 0);
      expect(original.preorderCount, isNull);
      f.controller.setWorkspaceActive(true);
      notifications = 0;
      for (var i = 0; i < 10; i++) {
        f.interest(owner, 'First');
      }
      expect(notifications, 0);
      expect(f.transport.requests, isEmpty);
      await f.settle();
      expect(f.transport.books, ['9101']);
      expect(f.transport.quotes, isEmpty);
      final current = f.controller.market.items['9101']!;
      expect(current.stockFor(f.now, OpportunitiesController.maxMarketAge), 0);
      expect(current.preorderCount, 20691);
      expect(current.quoteFetchedAt, original.quoteFetchedAt);
      expect(f.controller.detailStatus.total, 1);
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(minutes: 31));
      f.interest(owner, 'First');
      f.controller.recalculate();
      await f.settle();
      expect(
        f.transport.requests,
        hasLength(count),
        reason: 'Identical rebuilds and idle age are not refreshes.',
      );
    },
  );

  test(
    'offstage cards retain registrations but own no network scope',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final owner = Object();
      f.interest(owner, 'First');
      await f.settle();
      expect(f.transport.requests, isEmpty);
      expect(f.controller.detailStatus.requested, isFalse);
      f.controller.setWorkspaceActive(true);
      await f.settle();
      expect(f.transport.books, ['9101']);
      f.controller.setWorkspaceActive(false);
      expect(f.controller.detailStatus.requested, isFalse);
      f.transport.requests.clear();
      f.now = f.now.add(const Duration(minutes: 6));
      f.controller.setWorkspaceActive(true);
      f.controller.ensureMarketCurrent();
      await f.settle();
      expect(f.transport.books, ['9101']);
      expect(f.transport.quotes, ['9101']);
    },
  );

  test(
    'shared output owners deduplicate and one release preserves the other',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final first = Object(), alias = Object();
      f.controller.setWorkspaceActive(true);
      f.interest(first, 'First');
      f.interest(alias, 'Alias');
      await f.settle();
      expect(f.transport.books, ['9101']);
      f.controller.releaseCardMarketInterest(first);
      await f.settle();
      expect(f.controller.detailStatus.total, 1);
      expect(f.transport.books, ['9101']);
      f.controller.releaseCardMarketInterest(alias);
      await f.settle();
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.controller.market.items['9101']!.preorderCount, 20691);
    },
  );

  test(
    'current mode and filtered membership bound mounted owner interest',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.controller.change((p) => p.craftSearch = 'First');
      f.controller.setWorkspaceActive(true);
      f.interest(Object(), 'First');
      f.interest(Object(), 'Second');
      f.interest(Object(), 'Third', mode: CraftMode.processing);
      f.interest(Object(), 'Unknown');
      f.interest(Object(), 'Raw');
      await f.settle();
      expect(f.transport.books, ['9101']);
      f.transport.requests.clear();
      f.controller.change((p) => p.craftSearch = 'Second');
      await f.settle();
      expect(f.transport.books, ['9102']);
      expect(f.controller.detailStatus.total, 1);
      f.controller.change((p) => p.section = 'exchanges');
      expect(f.controller.detailStatus.requested, isFalse);
      await f.settle();
      expect(f.transport.books, ['9102']);
    },
  );

  test(
    'owner reuse replaces output interest without retaining the previous card',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final owner = Object();
      f.controller.setWorkspaceActive(true);
      f.interest(owner, 'First');
      f.interest(owner, 'Second');
      await f.settle();
      expect(f.transport.books, ['9102']);
      expect(f.controller.detailStatus.total, 1);
    },
  );

  test(
    'obsolete queued books never start while retained in-flight work survives',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.holdId = '9101';
      final removed = Object();
      f.controller.setWorkspaceActive(true);
      f.interest(Object(), 'First');
      f.interest(Object(), 'Second');
      f.interest(removed, 'Third');
      await f.transport.held.future.timeout(const Duration(seconds: 10));
      f.controller.releaseCardMarketInterest(removed);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(f.transport.aborted, isFalse);
      expect(f.transport.books, ['9101']);
      f.transport.release.complete();
      await f.settle();
      expect(f.transport.books, ['9101', '9102']);
      expect(f.controller.detailStatus.total, 2);
      expect(f.controller.detailStatus.failed, 0);
      expect(f.controller.market.items['9103']!.bookFetchedAt, isNull);
    },
  );

  test(
    'Demand retains its filtered output scope alongside mounted cards',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.controller.change((p) => p.craftSort = 'preorders');
      f.interest(Object(), 'First');
      f.controller.setWorkspaceActive(true);
      await f.settle();
      expect(f.transport.books.toSet(), {'9101', '9102', '9103'});
      expect(f.transport.books.length, 3);
      expect(f.transport.quotes, isEmpty);
    },
  );

  test(
    'tab entry before first cards carries five minutes only to that initial batch',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.seedBooks(['9101', '9102']);
      final original = f.now;
      f.now = f.now.add(const Duration(minutes: 6));
      f.transport.requests.clear();
      f.controller.setWorkspaceActive(true);
      f.controller.ensureMarketCurrent();
      await f.settle();
      expect(f.transport.requests, isEmpty);
      final owner = Object();
      f.interest(owner, 'First');
      await f.settle();
      expect(f.transport.quotes, ['9101']);
      expect(f.transport.books, ['9101']);
      expect(f.controller.market.items['9101']!.bookFetchedAt, f.now);
      f.transport.requests.clear();
      f.interest(owner, 'Second');
      await f.settle();
      expect(f.transport.requests, isEmpty);
      expect(f.controller.market.items['9102']!.bookFetchedAt, original);
      expect(f.controller.market.items['9102']!.quoteFetchedAt, original);
    },
  );

  test(
    'ordinary later card use keeps thirty-minute inclusive receipt boundary',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.seedBooks(['9101']);
      final original = f.now;
      final owner = Object();
      f.controller.setWorkspaceActive(true);
      f.now = original.add(const Duration(minutes: 30));
      f.transport.requests.clear();
      f.interest(owner, 'First');
      await f.settle();
      expect(f.transport.requests, isEmpty);
      f.controller.releaseCardMarketInterest(owner);
      await f.settle();
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.interest(owner, 'First');
      await f.settle();
      expect(f.transport.quotes, ['9101']);
      expect(f.transport.books, ['9101']);
      expect(f.controller.market.items['9101']!.bookFetchedAt, f.now);
    },
  );

  test(
    'known empty books and inspected output reuse do not repeat requests',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.emptyBooks = true;
      f.controller.setWorkspaceActive(true);
      f.interest(Object(), 'First');
      await f.settle();
      final item = f.controller.market.items['9101']!;
      expect(item.preorderCount, 0);
      expect(item.bookIsFresh(f.now, sharedMarketFreshness), isTrue);
      f.transport.requests.clear();
      f.controller.setInspectedRecipe(f.controller.recipes['First']);
      await f.settle();
      expect(f.transport.books, ['9201']);
      expect(
        f.controller.market.items['9101']!.bookFetchedAt,
        item.bookFetchedAt,
      );
      f.controller.setInspectedRecipe(null);
      await f.settle();
      expect(f.controller.detailStatus.total, 1);
    },
  );

  test(
    'manual refresh retains minute cooldown for mounted output books',
    () async {
      final f = await _Fixture.create(
        minimumRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(f.dispose);
      f.controller.setWorkspaceActive(true);
      f.interest(Object(), 'First');
      await f.settle();
      final original = f.now;
      f.now = original.add(const Duration(seconds: 59));
      f.transport.requests.clear();
      await f.controller.refresh();
      expect(f.transport.requests, isEmpty);
      f.now = original.add(const Duration(seconds: 60));
      await f.controller.refresh();
      await f.settle();
      expect(f.transport.books, ['9101']);
      expect(f.controller.market.items['9101']!.bookFetchedAt, f.now);
    },
  );

  test(
    'protection and Stop are not bypassed by scrolling or remounting',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final owner = Object();
      f.transport.protectedBooks = true;
      f.controller.setWorkspaceActive(true);
      f.interest(owner, 'First');
      await f.settle();
      expect(f.controller.detailStatus.blocked, isTrue);
      expect(f.controller.market.items['9101']!.preorderCount, isNull);
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(minutes: 10));
      f.interest(owner, 'Second');
      await f.settle();
      expect(f.transport.requests, hasLength(count));
      f.controller.cancel();
      f.interest(owner, 'Third');
      await f.settle();
      expect(f.transport.requests, hasLength(count));
      expect(f.controller.detailStatus.failed, 0);
    },
  );

  test(
    'card lifecycle retains the explicit Stop notice until a real retry',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.holdId = '9101';
      final owner = Object();
      f.controller.setWorkspaceActive(true);
      f.interest(owner, 'First');
      await f.transport.held.future.timeout(const Duration(seconds: 10));
      f.controller.cancel();
      await f.settle();
      expect(f.transport.aborted, isTrue);
      expect(f.controller.notice, 'Stopped. Loaded prices are kept.');
      final count = f.transport.requests.length;
      f.interest(owner, 'Second');
      await f.settle();
      expect(f.transport.requests, hasLength(count));
      expect(f.controller.notice, 'Stopped. Loaded prices are kept.');
      f.controller.releaseCardMarketInterest(owner);
      await f.settle();
      expect(f.controller.notice, 'Stopped. Loaded prices are kept.');
    },
  );

  test(
    'region change cancels old card work without injecting its receipt into the destination',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.holdId = '9101';
      f.controller.setWorkspaceActive(true);
      f.interest(Object(), 'First');
      await f.transport.held.future.timeout(const Duration(seconds: 10));
      f.transport.holdId = null;
      f.controller.change((p) => p.region = 'na');
      await f.settle();
      expect(f.transport.aborted, isTrue);
      expect(
        f.transport.requests
            .where((part) => part.part == SharedMarketPart.orderBook)
            .map((part) => part.key.region),
        ['eu', 'na'],
      );
      expect(f.controller.market.items['9101']!.preorderCount, 20691);
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
      expect(f.broker.snapshot('eu').items['9101']!.bookFetchedAt, isNull);
    },
  );

  test(
    'Stop cancels the initial debounce and later lifecycle updates cannot restart it',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final owner = Object();
      f.controller.setWorkspaceActive(true);
      f.interest(owner, 'First');
      f.controller.cancel();
      await f.settle();
      expect(f.transport.requests, isEmpty);
      f.interest(owner, 'Second');
      await f.settle();
      expect(f.transport.requests, isEmpty);
    },
  );
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 12, 16);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;

  static Future<_Fixture> create({
    Duration minimumRefreshAge = Duration.zero,
  }) async {
    final f = _Fixture(await ApplicationTestHarness.create());
    f.transport = _Transport(() => f.now);
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      quoteBatchSize: 1,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      concurrency: 1,
      cacheMaxAge: sharedMarketFreshness,
      minimumQuoteRefreshAge: minimumRefreshAge,
      minimumBookRefreshAge: minimumRefreshAge,
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      clock: () => f.now,
      sharedMarket: f.broker,
    );
    await f.controller.ready;
    f.controller.preferences.profitableOnly = false;
    f.controller.recipes = {
      'First': _recipe('First', '9101'),
      'Alias': _recipe('Alias', '9101'),
      'Second': _recipe('Second', '9102'),
      'Third': _recipe('Third', '9103'),
      'Raw': _recipe('Raw', '9201', craftable: false),
    };
    f.controller.recalculate();
    await f.controller.calculationSettled;
    await f.controller.refresh();
    await f.settle();
    f.transport.requests.clear();
    return f;
  }

  void interest(
    Object owner,
    String name, {
    CraftMode mode = CraftMode.cooking,
  }) => controller.setCardMarketInterest(owner, recipeName: name, mode: mode);

  Future<void> seedBooks(List<String> ids) async {
    await broker.fetch(
      bookKeys: ids.map((id) => SharedMarketKey(region: 'eu', itemId: id)),
    );
    await settle();
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (controller.scanning ||
        controller.calculating ||
        controller.detailStatus.loading) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Card market check did not settle.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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

Recipe _recipe(String name, String id, {bool craftable = true}) => Recipe(
  name: name,
  type: craftable ? 'cooking' : 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    if (craftable)
      Ingredient(
        name: 'Raw',
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
  final List<SharedMarketPartKey> requests = [];
  Iterable<String> get quotes => requests
      .where((part) => part.part == SharedMarketPart.quote)
      .map((part) => part.key.itemId);
  Iterable<String> get books => requests
      .where((part) => part.part == SharedMarketPart.orderBook)
      .map((part) => part.key.itemId);
  String? holdId;
  final held = Completer<void>();
  final release = Completer<void>();
  bool aborted = false;
  bool emptyBooks = false;
  bool protectedBooks = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final id = '${payload['mainKey']}';
    final book = uri.path.endsWith('GetBiddingInfoList');
    requests.add(
      SharedMarketPartKey(
        SharedMarketKey(
          region: uri.host.startsWith('na-') ? 'na' : 'eu',
          itemId: id,
        ),
        book ? SharedMarketPart.orderBook : SharedMarketPart.quote,
      ),
    );
    if (book && id == holdId && !release.isCompleted) {
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
    final text = book
        ? emptyBooks
              ? '1000-0-0|'
              : '1000-0-20691|'
        : '$id-0-0-1000-0-500000-100-10000-1000-${now().millisecondsSinceEpoch ~/ 1000}|';
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
