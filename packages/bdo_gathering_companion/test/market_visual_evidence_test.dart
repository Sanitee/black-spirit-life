import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/services/gathering_market_service.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureMarket = bool.fromEnvironment('CAPTURE_GATHERING_MARKET');
const _captureDirectory = String.fromEnvironment(
  'MARKET_CAPTURE_DIRECTORY',
  defaultValue: 'build/gathering-clarity-evidence',
);
const _settings = BairogCalculatorSettings();

// Deliberately fixed review prices, never a live-market claim or app input.
int _price(String id) => switch (id) {
  '4998' => 4800000,
  '4999' => 1500000,
  '7922' || '7924' => 30000,
  '821348' ||
  '821349' ||
  '821350' ||
  '821351' ||
  '821352' ||
  '821353' => 100000000,
  _ => 100000,
};

int _stock(String id) => switch (id) {
  '4998' || '4999' || '7924' => 0,
  '7922' => 33700,
  _ => 57089,
};

int _preorders(String id) => switch (id) {
  '4998' => 24163,
  '7924' => 5276,
  _ => 0,
};

class _TileOverrides extends HttpOverrides {
  final clients = <_TileClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _TileClient(
      _captureMarket ? super.createHttpClient(context) : null,
    );
    clients.add(client);
    return client;
  }

  void close() {
    for (final client in clients) {
      client.close(force: true);
    }
  }
}

class _TileClient implements HttpClient {
  _TileClient(this.inner);
  final HttpClient? inner;
  int pendingRequests = 0;
  bool closed = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (inner == null) throw const HttpException('Offline tile fixture');
    if (url.scheme != 'https' ||
        url.host != 'shrddr.github.io' ||
        !url.path.startsWith('/maptiles/') ||
        !url.path.endsWith('.webp')) {
      throw StateError('Visual capture only permits the actual map tiles.');
    }
    pendingRequests++;
    var completed = false;
    void complete() {
      if (!completed) {
        completed = true;
        pendingRequests--;
      }
    }

    try {
      return _TileRequest(await inner!.getUrl(url), complete);
    } catch (_) {
      complete();
      rethrow;
    }
  }

  @override
  set connectionTimeout(Duration? value) {
    inner?.connectionTimeout = value;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    inner?.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TileRequest implements HttpClientRequest {
  _TileRequest(this.inner, this.complete);
  final HttpClientRequest inner;
  final VoidCallback complete;
  @override
  Future<HttpClientResponse> close() async {
    try {
      final response = await inner.close();
      return _TileResponse(response, complete);
    } catch (_) {
      complete();
      rethrow;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TileResponse extends Stream<List<int>> implements HttpClientResponse {
  _TileResponse(this.inner, this.complete);
  final HttpClientResponse inner;
  final VoidCallback complete;
  @override
  int get statusCode => inner.statusCode;
  Stream<List<int>> get _body async* {
    try {
      yield* inner;
    } finally {
      complete();
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async {
    catalog = await Catalog.load();
    if (_captureMarket || Platform.isWindows) await _loadFonts();
  });

  for (final viewport in const [
    (size: Size(1563, 950), textScale: 1.0, opacity: 60),
    (size: Size(540, 900), textScale: 1.0, opacity: 60),
    (size: Size(700, 900), textScale: 2.0, opacity: 60),
    (size: Size(1563, 950), textScale: 1.0, opacity: 0),
    (size: Size(700, 900), textScale: 2.0, opacity: 0),
    (size: Size(540, 900), textScale: 1.0, opacity: 25),
  ]) {
    final suffix =
        '${viewport.size.width.toInt()}x${viewport.size.height.toInt()}'
        '-text${(viewport.textScale * 100).round()}'
        '${viewport.opacity == 60 ? '' : '-opacity${viewport.opacity}'}';
    testWidgets('market cards and exact popup stay comparable at $suffix', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = viewport.size;
      addTearDown(tester.view.reset);
      final previousShadows = debugDisableShadows;
      if (_captureMarket) debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);
      final capture = GlobalKey();
      final requested = <String, String>{};
      final overrides = _TileOverrides();
      final oldHttp = HttpOverrides.current;
      if (_captureMarket) HttpOverrides.global = overrides;
      addTearDown(overrides.close);

      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: companionTheme(opacityPercent: viewport.opacity),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(viewport.textScale)),
                  child: companionBackdropBuilder(
                    context,
                    Column(
                      children: [
                        Material(
                          color: const Color(0xff263745),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            child: Text(
                              'Visual review · fixed test prices, not live market data',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ),
                        Expanded(child: child!),
                      ],
                    ),
                  ),
                ),
                home: Scaffold(
                  body: FieldGuide(
                    catalog: catalog,
                    bairogCalculatorData: catalog.bairogCalculatorData,
                    bairogSettings: _settings,
                    marketOrderBookLoader:
                        (items, {includePreorders = false}) async {
                          requested.addAll(items);
                          return {
                            for (final id in items.keys)
                              id: GatheringMarketQuote(
                                itemId: int.parse(id),
                                price: _price(id),
                                stock: _stock(id),
                                preorders: includePreorders
                                    ? _preorders(id)
                                    : null,
                                fetchedAt: DateTime.now().toUtc(),
                              ),
                          };
                        },
                    onUse: (_) {},
                  ),
                ),
              ),
            ),
          );
          if (_captureMarket) await _settleRealTiles(tester);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('spot-search')),
            'Tshira',
          );
          if (_captureMarket) await _settleRealTiles(tester);
          await tester.pumpAndSettle();

          List<String>? valueIds;
          String? valueTotal;
          Set<int>? valueDetailIds;
          for (final mode in ['value', 'demand']) {
            await tester.tap(_filterControl());
            await tester.pumpAndSettle();
            final rank = find.byKey(
              ValueKey(
                mode == 'value' ? 'spot-ranking-profit' : 'spot-ranking-demand',
              ),
            );
            await tester.ensureVisible(rank);
            await tester.tap(rank);
            await tester.pumpAndSettle();
            await tester.tap(_filterControl());
            await tester.pumpAndSettle();

            final card = find.byKey(const ValueKey('spot-route-48'));
            expect(card, findsOneWidget);
            final rows = _rows(card, '$mode-contribution-row-');
            final ids = rows
                .evaluate()
                .map(
                  (element) => (element.widget.key! as ValueKey<String>).value
                      .substring('$mode-contribution-row-'.length),
                )
                .toList();
            expect(
              ids,
              containsAll(['7922', '7924', '821351', '4998', '4999']),
            );
            final snake = tester.getRect(
              find.descendant(
                of: card,
                matching: find.byKey(ValueKey('$mode-contribution-row-7922')),
              ),
            );
            final scorpion = tester.getRect(
              find.descendant(
                of: card,
                matching: find.byKey(ValueKey('$mode-contribution-row-7924')),
              ),
            );
            expect(snake.bottom, lessThanOrEqualTo(scorpion.top));
            expect(snake.left, moreOrLessEquals(scorpion.left, epsilon: 1));
            final error = Theme.of(tester.element(card)).colorScheme.error;
            for (final id in ['7922', '7924', '4998', '4999']) {
              final row = find.descendant(
                of: card,
                matching: find.byKey(ValueKey('$mode-contribution-row-$id')),
              );
              final hasPreorders = _preorders(id) > 0;
              final countColor = mode == 'value' && hasPreorders
                  ? error
                  : muted;
              final stock = tester.widget<Text>(
                find.descendant(
                  of: row,
                  matching: find.byKey(ValueKey('$mode-stock-$id')),
                ),
              );
              expect(stock.style?.color, countColor);
              final stockIcon = tester.widget<Icon>(
                find.descendant(
                  of: row,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Icon &&
                        widget.icon == Icons.storefront_outlined,
                  ),
                ),
              );
              expect(stockIcon.color, countColor);
              if (mode == 'demand') {
                final preorder = tester.widget<Text>(
                  find.descendant(
                    of: row,
                    matching: find.byKey(ValueKey('demand-preorders-$id')),
                  ),
                );
                expect(preorder.style?.color, hasPreorders ? error : muted);
                expect(preorder.data!.startsWith('−'), hasPreorders);
              } else {
                expect(stock.data!.startsWith('−'), hasPreorders);
              }
              expect(
                find.descendant(
                  of: row,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Text && widget.style?.color == positive,
                  ),
                ),
                findsOneWidget,
                reason: 'Only hourly earnings remain green, not market stock.',
              );
            }
            final total = tester
                .widget<Text>(
                  find.descendant(
                    of: find.descendant(
                      of: card,
                      matching: find.byKey(ValueKey('$mode-card-total')),
                    ),
                    matching: find.byType(Text),
                  ),
                )
                .data;
            if (mode == 'value') {
              valueIds = ids;
              valueTotal = total;
            } else {
              expect(ids, orderedEquals(valueIds!));
              expect(total, valueTotal);
            }
            expect(tester.takeException(), isNull);
            if (_captureMarket) {
              await _capture(tester, capture, '$mode-cards-$suffix');
            }

            final info = find.byKey(ValueKey('$mode-calculation-info-48'));
            await tester.ensureVisible(info);
            await tester.tap(info);
            for (
              var attempt = 0;
              attempt < 100 &&
                  find
                      .byKey(const ValueKey('market-calculation-dialog'))
                      .evaluate()
                      .isEmpty;
              attempt++
            ) {
              await tester.pump(const Duration(milliseconds: 16));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
            }
            await tester.pumpAndSettle();
            final dialog = find.byKey(
              const ValueKey('market-calculation-dialog'),
            );
            expect(dialog, findsOneWidget);
            expect(
              tester
                  .widget<GlassSurface>(
                    find.byKey(const ValueKey('market-calculation-surface')),
                  )
                  .reading,
              isTrue,
              reason:
                  'Exact calculations remain a protected reading surface even with transparent map UI.',
            );
            final detailText = find
                .descendant(of: dialog, matching: find.byType(Text))
                .first;
            expect(
              tester.element(detailText).glass.opacityPercent,
              greaterThanOrEqualTo(96),
            );
            final columns =
                viewport.size.width >= 700 && viewport.textScale == 1 ? 2 : 1;
            expect(
              find.byKey(ValueKey('market-calculation-columns-$columns')),
              findsOneWidget,
            );
            final rect = tester.getRect(
              find.byKey(const ValueKey('market-calculation-surface')),
            );
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(viewport.size.width));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(viewport.size.height));

            final projection = BairogCalculator(catalog.bairogCalculatorData!)
                .projectRoute(
                  routeId: 48,
                  settings: _settings,
                  marketPricesByBdoItemId: {
                    for (final id in requested.keys)
                      int.parse(id): _price(id).toDouble(),
                  },
                );
            final expectedValues = <int, double>{};
            final expectedQuantities = <int, double>{};
            final expectedIds = <int>{};
            for (final item in projection.items) {
              if (item.totalPerHour <= 0) continue;
              final id = item.itemType.item.id;
              expectedIds.add(id);
              expectedQuantities.update(
                id,
                (previous) => previous + item.totalPerHour,
                ifAbsent: () => item.totalPerHour,
              );
              final vendor = item.itemType.vendorUnitPrice;
              final value =
                  item.totalPerHour *
                  (vendor ?? _price('$id')) *
                  (vendor == null ? _settings.marketNetRate : 1);
              if (value <= 0) continue;
              expectedValues.update(
                id,
                (previous) => previous + value,
                ifAbsent: () => value,
              );
            }
            final incomeRows = _rows(dialog, 'calculation-income-');
            final actualIds = incomeRows
                .evaluate()
                .map(
                  (element) => int.parse(
                    (element.widget.key! as ValueKey<String>).value.substring(
                      'calculation-income-'.length,
                    ),
                  ),
                )
                .toSet();
            // The detail composer also exposes supplemental bonus-only materials.
            // Every positively projected material must remain present.
            expect(actualIds, containsAll(expectedIds));
            if (mode == 'value') {
              valueDetailIds = actualIds;
            } else {
              expect(actualIds, unorderedEquals(valueDetailIds!));
            }
            for (final id in actualIds) {
              expect(
                find.byKey(ValueKey('calculation-icon-$id')),
                findsOneWidget,
              );
            }
            for (final entry in expectedValues.entries) {
              final income = find.byKey(
                ValueKey('calculation-income-${entry.key}'),
              );
              expect(income, findsOneWidget);
              expect(
                find.descendant(
                  of: income,
                  matching: find.text(_fullSilver(entry.value)),
                ),
                findsOneWidget,
              );
              expect(
                tester
                    .widget<Text>(
                      find.descendant(
                        of: income,
                        matching: find.text(_fullSilver(entry.value)),
                      ),
                    )
                    .style
                    ?.color,
                positive,
                reason: 'Neutral market stock must not recolour item earnings.',
              );
              expect(
                find.byKey(ValueKey('calculation-icon-${entry.key}')),
                findsOneWidget,
              );
            }
            for (final entry in expectedQuantities.entries) {
              expect(
                tester
                    .widget<Text>(
                      find.byKey(ValueKey('calculation-quantity-${entry.key}')),
                    )
                    .data,
                '≈ ${_fullSilver(entry.value)} / h',
                reason:
                    'Each exact value exposes its same projected hourly quantity.',
              );
            }
            for (final entry in const {
              '7922': '33.700',
              '7924': '−5.276',
              '4998': '−24.163',
              '4999': '0',
            }.entries) {
              final text = tester.widget<Text>(
                find.byKey(ValueKey('calculation-market-${entry.key}')),
              );
              expect(text.data, entry.value);
              expect(
                text.style?.color,
                entry.value.startsWith('−')
                    ? Theme.of(tester.element(dialog)).colorScheme.error
                    : muted,
              );
            }
            expect(tester.takeException(), isNull);
            if (_captureMarket) {
              await _capture(tester, capture, '$mode-calculation-$suffix');
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
        }, overrides);
      } finally {
        // Restore before Flutter checks painting invariants (before tearDown).
        debugDisableShadows = previousShadows;
        if (_captureMarket) HttpOverrides.global = oldHttp;
      }
    });
  }
}

Finder _filterControl() {
  final rail = find.byKey(const ValueKey('spot-filter-compact-control'));
  return rail.evaluate().isNotEmpty
      ? rail
      : find.byKey(const ValueKey('spot-filter-compact-control'));
}

Finder _rows(Finder parent, String prefix) => find.descendant(
  of: parent,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(prefix),
  ),
);

String _fullSilver(double value) {
  final fixed = ((value * 100).round() / 100).toStringAsFixed(2).split('.');
  final whole = fixed[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]}.',
  );
  final fraction = fixed[1].replaceFirst(RegExp(r'0+$'), '');
  return '$whole${fraction.isEmpty ? '' : ',$fraction'}';
}

Future<void> _settleRealTiles(WidgetTester tester) async {
  // Wait for response bodies and queued tile requests, not only the first image.
  var previousCount = 0;
  var stable = 0;
  for (var i = 0; i < 240; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final images = find
        .byType(Image)
        .evaluate()
        .where((element) => (element.widget as Image).image is MemoryImage)
        .length;
    final override = HttpOverrides.current;
    final pending = override is _TileOverrides
        ? override.clients
              .where((client) => !client.closed)
              .fold(0, (sum, client) => sum + client.pendingRequests)
        : 0;
    stable = images > 0 && images == previousCount && pending == 0
        ? stable + 1
        : 0;
    previousCount = images;
    if (i >= 10 && stable >= 5) break;
  }
  if (stable < 5) {
    throw StateError(
      'Real market-view map tiles did not settle; refusing an empty-map capture.',
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final providers = find
      .descendant(of: find.byKey(key), matching: find.byType(Image))
      .evaluate()
      .map((element) => (element.widget as Image).image)
      .toSet();
  for (final provider in providers) {
    await tester.runAsync(() => precacheImage(provider, key.currentContext!));
  }
  await _settleRealTiles(tester);
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    final parent = flutterRoot.parent;
    if (parent.path == flutterRoot.path) {
      throw StateError('Flutter fonts not found.');
    }
    flutterRoot = parent;
  }
  final fonts = <String, List<String>>{
    'Segoe UI': [
      for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
        '$windowsRoot/Fonts/$name',
    ],
    'Roboto': [
      for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf'])
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$name',
    ],
    'MaterialIcons': [
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
