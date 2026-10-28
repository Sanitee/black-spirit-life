import 'dart:async';

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/services/shared_market_loader.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Call {
  _Call(this.items, this.includePreorders, this.forceRefresh, this.onItem);
  final Map<String, String> items;
  final bool includePreorders;
  final bool forceRefresh;
  final void Function(GatheringMarketReceipt) onItem;
  final done = Completer<GatheringMarketLoadResult>();
  bool cancelled = false;

  void finish() {
    if (!done.isCompleted) done.complete(const GatheringMarketLoadResult());
  }
}

class _Feed {
  final calls = <_Call>[];
  final updates = StreamController<GatheringMarketReceipt>.broadcast(
    sync: true,
  );

  Future<GatheringMarketLoadResult> load(
    Map<String, String> items, {
    required bool includePreorders,
    required bool forceRefresh,
    required void Function(GatheringMarketReceipt) onItem,
    Future<void>? cancelled,
  }) {
    final call = _Call(items, includePreorders, forceRefresh, onItem);
    calls.add(call);
    cancelled?.then((_) {
      call.cancelled = true;
      call.finish();
    });
    return call.done.future;
  }

  void base(_Call call, {DateTime? at, int snakeStock = 0}) {
    final receivedAt = at ?? DateTime.now().toUtc();
    for (final id in call.items.keys) {
      call.onItem(
        GatheringMarketReceipt(
          itemId: id,
          price: 30000,
          stock: id == '7922' ? snakeStock : 100000,
          quoteFetchedAt: receivedAt,
        ),
      );
    }
  }

  Future<void> close() async {
    for (final call in calls) {
      call.finish();
    }
    await updates.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async => catalog = await Catalog.load());

  Future<void> mount(WidgetTester tester, _Feed feed) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: FieldGuide(
            catalog: catalog,
            bairogCalculatorData: catalog.bairogCalculatorData,
            sharedMarketLoader: feed.load,
            sharedMarketUpdates: feed.updates.stream,
            marketFreshFor: const Duration(hours: 3),
            onUse: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('spot-filter-compact-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('spot-search')), 'Tshira');
    await tester.pump(const Duration(milliseconds: 120));
  }

  Finder snakeFinder() => find.descendant(
    of: find.byKey(const ValueKey('spot-route-48')),
    matching: find.byKey(const ValueKey('value-stock-7922')),
  );

  Future<void> unmount(WidgetTester tester, _Feed feed) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await feed.close();
  }

  testWidgets('shared receipts appear before the full load finishes', (
    tester,
  ) async {
    final feed = _Feed();
    await mount(tester, feed);
    final call = feed.calls.single;
    expect(call.includePreorders, isFalse);
    final now = DateTime.now().toUtc();
    call.onItem(
      GatheringMarketReceipt(
        itemId: '7922',
        preorders: 777,
        preorderFetchedAt: now.subtract(const Duration(hours: 2)),
      ),
    );
    feed.base(call, at: now.subtract(const Duration(hours: 1)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(call.done.isCompleted, isFalse);
    expect(tester.widget<Text>(snakeFinder()).data, '−777');
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('spot-market-refresh')))
          .onPressed,
      isNull,
    );
    call.finish();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('spot-market-refresh')))
          .onPressed,
      isNotNull,
    );
    await unmount(tester, feed);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'original cached timestamps expire instead of being refreshed on read',
    (tester) async {
      final feed = _Feed();
      await mount(tester, feed);
      final call = feed.calls.single;
      feed.base(call);
      call.onItem(
        GatheringMarketReceipt(
          itemId: '7922',
          preorders: 999,
          preorderFetchedAt: DateTime.now().toUtc().subtract(
            const Duration(hours: 4),
          ),
        ),
      );
      call.finish();
      await tester.pumpAndSettle();
      final stale = tester.widget<Text>(snakeFinder());
      expect(stale.data, '0');
      expect(stale.style?.color, muted);
      feed.updates.add(
        GatheringMarketReceipt(
          itemId: '7922',
          preorders: 234,
          preorderFetchedAt: DateTime.now().toUtc(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<Text>(snakeFinder()).data, '−234');
      expect(feed.calls, hasLength(1));
      await unmount(tester, feed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sibling updates preserve newer data and do not start another fetch',
    (tester) async {
      final feed = _Feed();
      await mount(tester, feed);
      final call = feed.calls.single;
      final now = DateTime.now().toUtc();
      feed.base(
        call,
        at: now.subtract(const Duration(minutes: 3)),
        snakeStock: 100,
      );
      call.finish();
      await tester.pumpAndSettle();
      feed.updates.add(
        GatheringMarketReceipt(
          itemId: '7922',
          price: 30000,
          stock: 321,
          quoteFetchedAt: now,
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<Text>(snakeFinder()).data, '321');
      feed.updates.add(
        GatheringMarketReceipt(
          itemId: '7922',
          price: 1,
          stock: 12,
          quoteFetchedAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<Text>(snakeFinder()).data, '321');
      expect(feed.calls, hasLength(1));
      await unmount(tester, feed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Demand detaches an unfinished Value waiter immediately', (
    tester,
  ) async {
    final feed = _Feed();
    await mount(tester, feed);
    final first = feed.calls.single;
    await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
    await tester.pump();
    expect(feed.calls, hasLength(2));
    expect(first.cancelled, isTrue);
    expect(feed.calls.last.includePreorders, isTrue);
    feed.base(feed.calls.last);
    feed.calls.last.finish();
    await tester.pumpAndSettle();
    await unmount(tester, feed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual Refresh bypasses cache and unmount detaches its waiter', (
    tester,
  ) async {
    final feed = _Feed();
    await mount(tester, feed);
    feed.base(feed.calls.single);
    feed.calls.single.finish();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spot-market-refresh')));
    await tester.pump();
    expect(feed.calls, hasLength(2));
    expect(feed.calls.last.forceRefresh, isTrue);
    await unmount(tester, feed);
    expect(feed.calls.last.cancelled, isTrue);
    feed.calls.last.onItem(
      GatheringMarketReceipt(
        itemId: '7922',
        price: 1,
        stock: 1,
        quoteFetchedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
