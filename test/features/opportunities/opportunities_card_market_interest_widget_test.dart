import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _whale = 'Sturdy Whale Tendon Potion';
const _copper = 'Copper Ingot';
const _captureKey = ValueKey('card-market-capture');
Finder _key(String value) => find.byKey(ValueKey(value));
Finder _card(String name) => _key('craft-card:$name');
Finder _summary(String name) => _key('craft-summary:$name');
Finder _stock(String name, String text) =>
    find.descendant(of: _summary(name), matching: find.text(text));

void main() {
  setUpAll(_fonts);
  for (final (name, count) in [(_whale, 20691), (_copper, 249)]) {
    testWidgets(
      '$name confirms red preorders on Profit card without opening details',
      (tester) async {
        final f = await _fixture(tester, search: name);
        try {
          await tester.pumpWidget(_host(f));
          final id = f.id(name);
          await _until(tester, () => f.transport.books.contains(id));
          expect(find.text('Profit'), findsWidgets);
          expect(_card(name), findsOneWidget);
          expect(_stock(name, '0'), findsOneWidget);
          final palette = tester.element(_card(name)).visualTheme.palette;
          expect(
            tester.widget<Text>(_stock(name, '0')).style?.color,
            palette.textMuted,
          );
          expect(_stockTooltip(name), contains('Preorders: Not checked'));
          expect(find.byType(Dialog), findsNothing);
          expect(_key('root-recipe-page'), findsNothing);
          expect(f.transport.quotes, isEmpty);
          final quoteTime = f.controller.market.items[id]!.quoteFetchedAt;
          if (name == _whale) await _capture(tester, 'sturdy-card-before');
          f.transport.complete(id, preorders: count);
          final negative = name == _whale ? '−20.691' : '−249';
          await _until(
            tester,
            () => _stock(name, negative).evaluate().isNotEmpty,
          );
          expect(
            tester.widget<Text>(_stock(name, negative)).style?.color,
            palette.danger,
          );
          expect(
            _stockTooltip(name),
            contains(name == _whale ? 'Preorders: 20.691' : 'Preorders: 249'),
          );
          expect(f.controller.market.items[id]!.quoteFetchedAt, quoteTime);
          expect(f.controller.market.items[id]!.preorderCount, count);
          expect(f.transport.books, [id]);
          expect(f.transport.quotes, isEmpty);
          expect(find.byType(Dialog), findsNothing);
          expect(_key('root-recipe-page'), findsNothing);
          if (name == _whale) await _capture(tester, 'sturdy-card-after');
        } finally {
          await _dispose(tester, f);
        }
      },
    );
  }

  testWidgets('known zero visible book remains neutral on the unopened card', (
    tester,
  ) async {
    final f = await _fixture(tester, search: _whale);
    try {
      await tester.pumpWidget(_host(f));
      final id = f.id(_whale);
      await _until(tester, () => f.transport.books.contains(id));
      f.transport.complete(id, preorders: 0);
      await _until(tester, () => f.controller.market.items[id]!.bids != null);
      expect(_stock(_whale, '0'), findsOneWidget);
      expect(
        tester.widget<Text>(_stock(_whale, '0')).style?.color,
        tester.element(_card(_whale)).visualTheme.palette.textMuted,
      );
      expect(_stockTooltip(_whale), contains('Preorders: 0'));
      expect(find.byType(Dialog), findsNothing);
    } finally {
      await _dispose(tester, f);
    }
  });

  testWidgets('failed visible book never invents a negative preorder count', (
    tester,
  ) async {
    final f = await _fixture(tester, search: _whale);
    try {
      await tester.pumpWidget(_host(f));
      final id = f.id(_whale);
      await _until(tester, () => f.transport.books.contains(id));
      f.transport.complete(id, status: 500);
      await _until(
        tester,
        () => !f.controller.scanning && f.controller.failedItems > 0,
      );
      expect(_stock(_whale, '0'), findsOneWidget);
      expect(
        tester.widget<Text>(_stock(_whale, '0')).style?.color,
        tester.element(_card(_whale)).visualTheme.palette.textMuted,
      );
      expect(_stockTooltip(_whale), contains('Preorders: Not checked'));
      expect(f.controller.market.items[id]!.preorderCount, isNull);
      expect(find.byType(Dialog), findsNothing);
    } finally {
      await _dispose(tester, f);
    }
  });

  testWidgets(
    'scrolling requests only mounted card outputs and releases old work',
    (tester) async {
      final f = await _fixture(tester);
      try {
        await tester.pumpWidget(_host(f));
        await _until(tester, () => f.transport.books.length == 4);
        await _until(
          tester,
          () => f.controller.detailStatus.total == _mountedIds(f).length,
        );
        final initialIds = _mountedIds(f);
        final allIds = f.controller.visibleQuotes
            .map((quote) => f.maybeId(quote.recipeName))
            .whereType<String>()
            .toSet();
        expect(allIds.length, greaterThan(100));
        expect(initialIds.length, lessThan(allIds.length ~/ 3));
        expect(initialIds, containsAll(f.transport.books));
        expect(f.controller.detailStatus.total, initialIds.length);
        final initialRequests = f.transport.books.toSet();
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const PageStorageKey('craft-opportunities')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent.clamp(0, 5000));
        await tester.pump();
        await _until(
          tester,
          () =>
              f.transport.books.toSet().difference(initialRequests).isNotEmpty,
        );
        await _until(
          tester,
          () => f.controller.detailStatus.total == _mountedIds(f).length,
        );
        final nextIds = _mountedIds(f);
        expect(
          nextIds.intersection(initialIds),
          isEmpty,
          reason: 'Jump far enough to replace the naturally cached viewport.',
        );
        expect(
          nextIds,
          containsAll(f.transport.books.toSet().difference(initialRequests)),
        );
        expect(f.transport.aborted, containsAll(initialRequests));
        expect(f.controller.detailStatus.total, nextIds.length);
        expect(f.transport.books.length, lessThan(allIds.length ~/ 3));
        expect(f.transport.quotes, isEmpty);
        expect(find.byType(Dialog), findsNothing);
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  testWidgets('search replaces held card output without inspecting recipes', (
    tester,
  ) async {
    final f = await _fixture(tester, search: _whale);
    try {
      await tester.pumpWidget(_host(f));
      await _until(tester, () => f.transport.books.contains(f.id(_whale)));
      await _search(tester, _copper);
      await _until(tester, () => f.transport.books.contains(f.id(_copper)));
      expect(_card(_whale), findsNothing);
      expect(_card(_copper), findsOneWidget);
      expect(f.transport.aborted, contains(f.id(_whale)));
      expect(f.transport.books, [f.id(_whale), f.id(_copper)]);
      expect(f.controller.detailStatus.total, 1);
      expect(f.transport.quotes, isEmpty);
      expect(find.byType(Dialog), findsNothing);
    } finally {
      await _dispose(tester, f);
    }
  });

  testWidgets(
    'mode and offstage lifecycle cancel old cards and fetch only active outputs',
    (tester) async {
      final f = await _fixture(tester, search: _whale);
      try {
        await tester.pumpWidget(_host(f));
        await _until(tester, () => f.transport.books.contains(f.id(_whale)));
        await tester.tap(find.text('Cooking'));
        await tester.pump();
        await _until(tester, () => f.transport.aborted.contains(f.id(_whale)));
        expect(f.controller.preferences.mode, CraftMode.cooking);
        expect(_card(_whale), findsNothing);
        expect(f.transport.books, [f.id(_whale)]);

        f.controller.setWorkspaceActive(false);
        await tester.pumpWidget(_host(f, active: false));
        f.controller.change((preferences) {
          preferences.mode = CraftMode.processing;
          preferences.craftSearch = _copper;
        });
        await _work(tester, f.controller.calculationSettled);
        await tester.pump(const Duration(seconds: 1));
        expect(f.transport.books, [
          f.id(_whale),
        ], reason: 'Retained inactive tab must not load cards.');
        expect(f.controller.detailStatus.requested, isFalse);

        f.controller.setWorkspaceActive(true);
        await tester.pumpWidget(_host(f));
        await _until(tester, () => f.transport.books.contains(f.id(_copper)));
        expect(_card(_copper), findsOneWidget);
        expect(f.transport.books, [f.id(_whale), f.id(_copper)]);
        expect(f.transport.quotes, isEmpty);
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  testWidgets('Stop check cancels card work and search cannot restart it', (
    tester,
  ) async {
    final f = await _fixture(tester, search: _whale);
    try {
      await tester.pumpWidget(_host(f));
      await _until(tester, () => f.transport.books.contains(f.id(_whale)));
      await tester.tap(find.text('Stop check'));
      await tester.pump();
      await _until(tester, () => !f.controller.scanning);
      await _search(tester, _copper);
      await _work(tester, f.controller.calculationSettled);
      await tester.pump(const Duration(seconds: 1));
      expect(_card(_copper), findsOneWidget);
      expect(f.transport.books, [f.id(_whale)]);
      expect(f.transport.aborted, contains(f.id(_whale)));
      expect(_stock(_copper, '0'), findsOneWidget);
      expect(f.controller.market.items[f.id(_copper)]!.preorderCount, isNull);
    } finally {
      await _dispose(tester, f);
    }
  });
}

Set<String> _mountedIds(_Fixture f) => find
    .byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('craft-card:');
    }, skipOffstage: false)
    .evaluate()
    .map((element) {
      final name = (element.widget.key! as ValueKey<String>).value.substring(
        'craft-card:'.length,
      );
      return f.maybeId(name);
    })
    .whereType<String>()
    .toSet();

Future<void> _search(WidgetTester tester, String value) => tester.enterText(
  find.descendant(of: _key('craft-search'), matching: find.byType(TextField)),
  value,
);

String _stockTooltip(String name) => find
    .descendant(of: _summary(name), matching: find.byType(Tooltip))
    .evaluate()
    .map((element) => (element.widget as Tooltip).message ?? '')
    .firstWhere((message) => message.startsWith('Stock:'));

Widget _host(_Fixture f, {bool active = true}) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Offstage(
        offstage: !active,
        child: TickerMode(
          enabled: active,
          child: OpportunitiesWorkspace(
            controller: f.controller,
            active: active,
          ),
        ),
      ),
    ),
  ),
);

class _Fixture {
  _Fixture(this.harness, this.controller, this.broker, this.transport);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final SharedMarketRepository broker;
  final _Transport transport;
  String? maybeId(String name) {
    final id = controller.outputMarketFor(name)?.itemId;
    return id != null && isOpportunityMarketRequestEligible(id) ? id : null;
  }

  String id(String name) =>
      CatalogRepository(harness.bundle.catalog).bundledMarketId(name)!;
}

Future<_Fixture> _fixture(WidgetTester tester, {String search = ''}) async {
  configureApplicationTestSurface(tester, const Size(1200, 752));
  final f = (await tester.runAsync(() async {
    final harness = await ApplicationTestHarness.create(
      activeMode: CraftMode.processing,
    );
    final catalog = CatalogRepository(harness.bundle.catalog);
    final now = DateTime.utc(2026, 9, 12, 16);
    final directory = Directory(
      '${harness.temporaryDirectory.path}/opportunities',
    );
    final cache = OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => now,
    );
    final ids = <String>{
      ...(harness.bundle.catalog.supportingData['marketIds']! as Map).values
          .map((id) => '$id'),
      for (final mode in harness.bundle.controller.modes.values)
        for (final recipe in mode.recipes.values)
          if (recipe.marketId != null) recipe.marketId!,
    };
    await cache.save({
      'eu': {
        for (final id in ids)
          id: OpportunityMarketItem(
            itemId: id,
            basePrice: 1000,
            stock: 0,
            quoteFetchedAt: now.subtract(const Duration(minutes: 1)),
          ),
      },
    });
    final preferences = OpportunitiesPreferences()
      ..mode = CraftMode.processing
      ..craftSearch = search
      ..craftSort = 'profit'
      ..profitableOnly = false;
    await OpportunitiesPreferenceStore(directory).save(preferences);
    final transport = _Transport();
    final broker = SharedMarketRepository(
      cacheStore: cache,
      transport: transport,
      utcNow: () => now,
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      concurrency: 4,
      requestTimeout: const Duration(minutes: 5),
    );
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: catalog,
      directory: directory,
      sharedMarket: broker,
      clock: () => now,
      autoCheck: false,
    );
    await controller.ready;
    await controller.calculationSettled;
    return _Fixture(harness, controller, broker, transport);
  }))!;
  f.controller.setWorkspaceActive(true);
  return f;
}

Future<void> _dispose(WidgetTester tester, _Fixture f) async {
  f.controller.setWorkspaceActive(false);
  f.controller.cancel();
  f.transport.completeAll();
  await tester.pumpWidget(const SizedBox.shrink());
  await _work(tester, () async {
    await f.broker.close();
    await f.controller.flush();
    f.controller.dispose();
    await f.harness.dispose();
  }());
}

class _Transport implements OpportunityMarketTransport {
  final books = <String>[];
  final quotes = <String>[];
  final aborted = <String>{};
  final pending = <String, Completer<OpportunityHttpResponse>>{};
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) {
    final id = '${(jsonDecode(body) as Map)['mainKey']}';
    if (!uri.path.endsWith('GetBiddingInfoList')) {
      quotes.add(id);
      throw StateError('Fresh summary cache must be reused; unexpected $uri');
    }
    books.add(id);
    final response = Completer<OpportunityHttpResponse>();
    pending[id] = response;
    return Future.any([
      response.future,
      if (abortTrigger != null)
        abortTrigger.then<OpportunityHttpResponse>((_) {
          aborted.add(id);
          throw const MarketFetchCancelledException();
        }),
    ]);
  }

  void complete(String id, {int preorders = 7, int status = 200}) {
    final response = pending[id];
    if (response == null || response.isCompleted) return;
    response.complete(
      OpportunityHttpResponse(
        statusCode: status,
        bytes: Uint8List.fromList(
          utf8.encode(
            jsonEncode({'resultCode': 0, 'resultMsg': '1000-0-$preorders|'}),
          ),
        ),
      ),
    );
  }

  void completeAll() {
    for (final id in pending.keys.toList()) {
      complete(id);
    }
  }

  @override
  void close() {}
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 300 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: 'Market card state must settle.');
  await tester.pump();
}

Future<void> _work(WidgetTester tester, Future<void> future) async {
  var done = false;
  Object? error;
  StackTrace? stack;
  unawaited(
    future.then(
      (_) => done = true,
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  await _until(tester, () => done);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['OPPORTUNITY_CARD_CAPTURE_DIR'];
  if (path == null || path.isEmpty) return;
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pump(const Duration(milliseconds: 200));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    await Directory(path).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _fonts() async {
  if (!Platform.isWindows) return;
  final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
        '${sdk.path}/bin/cache/artifacts/material_fonts',
      ).existsSync() &&
      sdk.parent.path != sdk.path) {
    sdk = sdk.parent;
  }
  for (final entry in <String, List<String>>{
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      if (File(path).existsSync()) {
        loader.addFont(
          File(path).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      }
    }
    await loader.load();
  }
}
