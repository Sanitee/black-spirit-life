import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_glass_material.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _captureKey = ValueKey('artwork-alignment-capture');
Finder _card(String name) => find.byKey(ValueKey('craft-card:$name'));

void main() {
  setUpAll(_fonts);

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    testWidgets('material depth native workspace matrix $background', (
      tester,
    ) async {
      final f = await _fixture(tester, background);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      final geometry = <Map<String, Object?>>[];
      try {
        for (final section in ['crafting', 'best-use', 'exchanges']) {
          f.controller.change((p) {
            p.section = section;
            p.mode = CraftMode.cooking;
            p.craftSearch = 'Beer';
            p.craftSort = 'exp';
            p.currencyId = 'sangpyeong';
          });
          if (section == 'best-use') f.controller.selectBestUseItem('Aloe');
          await _settleCalculation(tester, f.controller);
          await tester.pumpWidget(_host(f));
          for (final view in [
            (size: const Size(1200, 900), scale: 1.0),
            (size: const Size(900, 1100), scale: 2.0),
          ]) {
            configureApplicationTestSurface(
              tester,
              view.size,
              textScaleFactor: view.scale,
            );
            await _settleImages(tester);
            final card = section == 'crafting'
                ? _card('Beer')
                : section == 'best-use'
                ? _card('Aloe Yogurt')
                : find
                      .byWidgetPredicate(
                        (widget) =>
                            widget is OpportunitySurface &&
                            widget.role == AppSurfaceRole.card,
                      )
                      .first;
            expect(card, findsOneWidget);
            if (section == 'crafting') _expectCenteredArtwork(tester, 'Beer');
            if (section == 'best-use') expect(_relief(card), findsNothing);
            expect(find.byType(BackdropFilter), findsNothing);
            expect(tester.takeException(), isNull);
            final name =
                'material-$background-$section-text${view.scale.toInt()}';
            await _capture(tester, find.byKey(_captureKey), name);
            await _capture(tester, card, '$name-card');
            final bounds = tester.getRect(card);
            final baseline = Platform
                .environment['OPPORTUNITY_MATERIAL_BASELINE_CAPTURE_DIR'];
            if (section == 'crafting' && baseline != null) {
              final beforeBytes = await tester.runAsync(
                () => File(
                  '$baseline/craft-artwork-$background-cooking-text${view.scale.toInt()}.png',
                ).readAsBytes(),
              );
              final dimensions = ByteData.sublistView(beforeBytes!);
              expect(bounds.width + 16, closeTo(dimensions.getUint32(16), 1));
              expect(bounds.height + 16, closeTo(dimensions.getUint32(20), 1));
            }
            geometry.add({
              'section': section,
              'viewport': [view.size.width, view.size.height],
              'textScale': view.scale,
              'cardBounds': [
                bounds.left,
                bounds.top,
                bounds.width,
                bounds.height,
              ],
              'text': [
                for (final widget in tester.widgetList<Text>(
                  find.descendant(of: card, matching: find.byType(Text)),
                ))
                  if (widget.data != null) widget.data,
              ],
              'artwork': [
                for (final element
                    in find
                        .descendant(
                          of: card,
                          matching: find.byType(ModeItemIcon),
                        )
                        .evaluate())
                  {
                    'name': (element.widget as ModeItemIcon).name,
                    'size': (element.widget as ModeItemIcon).size,
                  },
              ],
            });
          }
        }
        expect(f.transport.requests, 0);
        final output = Platform.environment['OPPORTUNITY_MATERIAL_REPORT_DIR'];
        if (output != null) {
          final phase =
              Platform.environment['OPPORTUNITY_MATERIAL_PHASE'] ??
              'unspecified';
          await tester.runAsync(
            () =>
                File(
                  '$output/material-depth-$phase-$background-geometry.json',
                ).writeAsString(
                  const JsonEncoder.withIndent('  ').convert(geometry),
                ),
          );
        }
      } finally {
        debugDisableShadows = previousShadows;
        await _dispose(tester, f);
      }
    });
  }

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    testWidgets('Crafting artwork centers in its full rail $background', (
      tester,
    ) async {
      final f = await _fixture(tester, background);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        for (final selection in [
          (CraftMode.cooking, 'Beer'),
          (CraftMode.alchemy, 'Elixir of Brawn'),
          (CraftMode.processing, 'Sturdy Whale Tendon Potion'),
        ]) {
          f.controller.change((p) {
            p.mode = selection.$1;
            p.craftSearch = selection.$2;
            p.craftSort = 'exp';
          }, assemble: true);
          await _settleCalculation(tester, f.controller);
          await tester.pumpWidget(_host(f));
          for (final view in [
            (size: const Size(1200, 900), scale: 1.0),
            (size: const Size(900, 1100), scale: 2.0),
          ]) {
            configureApplicationTestSurface(
              tester,
              view.size,
              textScaleFactor: view.scale,
            );
            await _settleImages(tester);
            _expectCenteredArtwork(tester, selection.$2);
            expect(tester.takeException(), isNull);
            await _capture(
              tester,
              _card(selection.$2),
              'craft-artwork-$background-${selection.$1.name}-text${view.scale.toInt()}',
            );
          }
        }
        expect(f.transport.requests, 0);
      } finally {
        debugDisableShadows = previousShadows;
        await _dispose(tester, f);
      }
    });
  }

  testWidgets('centered artwork keeps icon-only reference hover', (
    tester,
  ) async {
    final f = await _fixture(tester, 'sakura-night-garden');
    try {
      await tester.pumpWidget(_host(f));
      await _settleImages(tester);
      final card = _card('Beer');
      _expectCenteredArtwork(tester, 'Beer');
      final paint = find.byKey(const ValueKey('craft-header:Beer'));
      final rail = tester.getRect(paint);
      final mount = tester.getRect(
        find.byKey(const ValueKey('craft-artwork-rail:Beer')),
      );
      final icon = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (w) => w is ModeItemIcon && w.name == 'Beer',
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      try {
        for (final point in [
          rail.topLeft + const Offset(8, 8),
          Offset(rail.left + 46, rail.bottom - 8),
          mount.topLeft + const Offset(1, 1),
          tester.getCenter(
            find.descendant(of: card, matching: find.text('Beer')),
          ),
        ]) {
          await mouse.moveTo(point);
          await tester.pump(const Duration(milliseconds: 800));
          expect(find.byType(ItemReferenceCard), findsNothing);
        }
        await mouse.moveTo(tester.getCenter(icon));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(ItemReferenceCard), findsOneWidget);
        expect(
          tester.widget<ItemReferenceCard>(find.byType(ItemReferenceCard)).name,
          'Beer',
        );
        expect(f.transport.requests, 0);
      } finally {
        await mouse.moveTo(const Offset(1, 1));
        await tester.pump(const Duration(milliseconds: 550));
        await tester.pumpAndSettle();
        await mouse.removePointer();
        await tester.pumpAndSettle();
      }
      expect(find.byType(ItemReferenceCard), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, f);
    }
  });

  testWidgets('Best use keeps its compact artwork header without a full rail', (
    tester,
  ) async {
    final f = await _fixture(tester, 'sakura-night-garden');
    try {
      f.controller.change((p) => p.section = 'best-use');
      f.controller.selectBestUseItem('Aloe');
      await _settleCalculation(tester, f.controller);
      await tester.pumpWidget(_host(f));
      await _settleImages(tester);
      final card = _card('Aloe Yogurt');
      expect(card, findsOneWidget);
      expect(_relief(card), findsNothing);
      final mount = find.byKey(
        const ValueKey('craft-artwork-rail:Aloe Yogurt'),
      );
      final icon = find.descendant(
        of: mount,
        matching: find.byType(ModeItemIcon),
      );
      expect(tester.getSize(icon), const Size(48, 48));
      expect(tester.getSize(mount), const Size(56, 56));
      expect(tester.getCenter(icon), tester.getCenter(mount));
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('best-use-card-header:Aloe Yogurt')),
            )
            .contains(tester.getCenter(icon)),
        isTrue,
      );
      expect(f.transport.requests, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, f);
    }
  });
}

Finder _relief(Finder card) => find.descendant(
  of: card,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint && widget.painter is OpportunityCraftCardRelief,
  ),
);

void _expectCenteredArtwork(WidgetTester tester, String name) {
  final card = _card(name);
  expect(card, findsOneWidget);
  final paint = find.byKey(ValueKey('craft-header:$name'));
  expect(paint, findsOneWidget);
  final bounds = tester.getRect(paint);
  final icon = find.descendant(
    of: card,
    matching: find.byWidgetPredicate(
      (w) => w is ModeItemIcon && w.name == name,
    ),
  );
  final mount = find.byKey(ValueKey('craft-artwork-rail:$name'));
  final bay = tester.getRect(find.byKey(ValueKey('craft-colour-bay:$name')));
  expect(bay.height, bounds.height);
  final center = Offset(bounds.left + 31, bounds.center.dy);
  expect(tester.getSize(icon), const Size(40, 40));
  expect(tester.getSize(mount), const Size(46, 46));
  expect(tester.getCenter(icon).dx, closeTo(center.dx, .01));
  expect(tester.getCenter(icon).dy, closeTo(center.dy, .01));
  expect(tester.getCenter(mount), tester.getCenter(icon));
  expect(
    tester.getRect(find.byKey(ValueKey('craft-summary:$name'))).left,
    closeTo(bay.right + 12, .01),
  );
  expect(
    find.descendant(of: card, matching: find.byType(IntrinsicHeight)),
    findsNothing,
  );
  expect(
    find.descendant(of: card, matching: find.byType(IntrinsicWidth)),
    findsNothing,
  );
}

Widget _host(_Fixture f) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ThemeSpecScope(
      spec: applicationThemeForAppearance(
        f.controller.modeController.state.value.appearance,
      ),
      child: Scaffold(body: OpportunitiesWorkspace(controller: f.controller)),
    ),
  ),
);

class _Fixture {
  _Fixture(this.harness, this.controller, this.transport);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final _NoNetwork transport;
}

Future<_Fixture> _fixture(WidgetTester tester, String background) async {
  configureApplicationTestSurface(tester, const Size(1200, 900));
  return (await tester.runAsync(() async {
    final harness = await ApplicationTestHarness.create(
      activeMode: CraftMode.cooking,
      backgroundId: background,
    );
    final catalog = CatalogRepository(harness.bundle.catalog);
    final now = DateTime.utc(2026, 10, 18, 8);
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
            stock: 100000,
            quoteFetchedAt: now,
            asks: const [OpportunityMarketLevel(price: 1000, quantity: 100000)],
            bids: const [],
            bookFetchedAt: now,
          ),
      },
    });
    final preferences = OpportunitiesPreferences()
      ..mode = CraftMode.cooking
      ..profitableOnly = false
      ..demandOnly = false
      ..readyOnly = false;
    await OpportunitiesPreferenceStore(directory).save(preferences);
    final transport = _NoNetwork();
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: catalog,
      directory: directory,
      clock: () => now,
      autoCheck: false,
      serviceFactory: (region) => OpportunityMarketService(
        region: region,
        transport: transport,
        utcNow: () => now,
      ),
    );
    await controller.ready;
    controller.change((p) => p.craftSearch = 'Beer');
    await controller.calculationSettled;
    return _Fixture(harness, controller, transport);
  }))!;
}

class _NoNetwork implements OpportunityMarketTransport {
  int requests = 0;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests++;
    throw StateError('The complete fresh fixture must not fetch: $uri');
  }

  @override
  void close() {}
}

Future<void> _work(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? error;
  StackTrace? stack;
  unawaited(
    work.then(
      (_) => done = true,
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 500 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue, reason: 'Fixture work must finish.');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

Future<void> _settleCalculation(
  WidgetTester tester,
  OpportunitiesController controller,
) async {
  await tester.pump(const Duration(milliseconds: 200));
  await _work(tester, controller.calculationSettled);
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _dispose(WidgetTester tester, _Fixture f) async {
  f.controller.setWorkspaceActive(false);
  f.controller.cancel();
  await tester.pumpWidget(const SizedBox.shrink());
  await _work(tester, () async {
    await f.controller.flush();
    f.controller.dispose();
    await f.harness.dispose();
  }());
}

Future<void> _capture(WidgetTester tester, Finder region, String name) async {
  final directory = Platform.environment['OPPORTUNITY_SUBSTITUTE_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final bounds = tester
      .getRect(region)
      .shift(-boundary.localToGlobal(Offset.zero))
      .inflate(8)
      .intersect(Offset.zero & boundary.size);
  await tester.runAsync(() async {
    final image = await (boundary.debugLayer! as OffsetLayer).toImage(bounds);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
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
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in <String, List<String>>{
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
