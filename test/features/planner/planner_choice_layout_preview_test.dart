import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_review_panels.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/features/shared/missing_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/npc_source_marker.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import '../../support/choice_market_transport.dart';
import 'planner_choice_market_test.dart' show settle;
import 'planner_review_projection_test.dart' as projection;

void main() {
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'Roboto': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('choice preview ${spec.id} $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1600, 1100);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final catalog = const BundledCatalogParser().parse(
          File('assets/data/app-data.json').readAsStringSync(),
        );
        final app = projection.controller(
          catalog,
          CraftMode.cooking,
          'Stir-Fried Vegetables',
          100,
        );
        final mode = app.active;
        final ingredient = mode.recipes['Stir-Fried Vegetables']!.ingredients
            .firstWhere((i) => i.options.contains('Pumpkin'));
        mode.selectSubstitute(
          parentName: 'Stir-Fried Vegetables',
          ingredient: ingredient,
          selection: 'Pumpkin',
        );
        mode.commitInventory('Pumpkin', '461600');
        mode.commitInventory('Olive', '12700');
        mode.setIgnoreOwnedIngredients(false);
        final transport = ChoiceMarketTransport();
        final names = ['Pumpkin', 'Paprika', 'Tomato', 'Cabbage', 'Olive'];
        final stocks = [10000, 0, 1609, 0, 57132];
        final orders = [8419, 9447, 0, 30754, 5000];
        for (var i = 0; i < names.length; i++) {
          final id = choiceMarketIdentity(
            mode,
            names[i],
            acrossModes: true,
          ).marketId!;
          transport.values[id] = (
            price: 480 + i * 100,
            stock: stocks[i],
            preorders: orders[i],
          );
        }
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ThemeSpecScope(
              spec: spec,
              child: PlannerChoiceMarketScope(
                repository: broker,
                child: Scaffold(
                  backgroundColor: spec.palette.surfaceInset,
                  body: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: PlannerOwnedChoices(
                        controller: mode,
                        parentName: 'Stir-Fried Vegetables',
                        ingredient: ingredient,
                        options: names,
                        selected: 'Pumpkin',
                        anchorBuilder: (context, toggle, open) => TextButton(
                          onPressed: toggle,
                          child: const Text('Substitutes'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Substitutes'));
        await settle(tester, broker);
        await tester.pumpAndSettle();
        for (final element in find.byType(Image).evaluate()) {
          await tester.runAsync(
            () => precacheImage((element.widget as Image).image, element),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final panel = find.byKey(const ValueKey('planner-owned-choices-panel'));
        expect(panel, findsOneWidget);
        expect(tester.getRect(panel).right, lessThanOrEqualTo(1600));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .ancestor(of: panel, matching: find.byType(RepaintBoundary))
              .first,
        );
        final stage = Platform.environment['BSL_CHOICE_STAGE'] ?? 'suggested';
        if (stage == 'suggested') {
          final inventoryCenter = tester.getCenter(find.text('Inventory')).dx;
          final marketCenter = tester.getCenter(find.text('Market')).dx;
          expect(find.text('NPC'), findsOneWidget);
          for (final name in names) {
            final row = find.byKey(ValueKey('planner-owned-option:$name'));
            final inventory = find.descendant(
              of: row,
              matching: find.byType(InventoryCountBadge),
            );
            expect(tester.getCenter(inventory).dx, closeTo(inventoryCenter, 1));
            final stock = find
                .descendant(of: row, matching: find.byType(MarketCountBadges))
                .last;
            final badge = tester.widget<MarketCountBadges>(stock);
            expect(
              tester.getTopLeft(stock).dx + badge.stockColumnWidth! / 2,
              closeTo(marketCenter, 1),
            );
            if (name == 'Paprika') {
              final npc = find.descendant(
                of: row,
                matching: find.byType(NpcSourceMarker),
              );
              final nameRect = tester.getRect(
                find.descendant(of: row, matching: find.text('Paprika')),
              );
              expect(tester.getRect(npc).left - nameRect.right, closeTo(12, 1));
              expect(tester.getCenter(npc).dy, closeTo(nameRect.center.dy, 1));
            }
          }
          expect(find.byType(MissingCountBadge), findsNWidgets(names.length));
          expect(find.byType(Tooltip), findsNothing);
        }
        final out = Platform.environment['BSL_CHOICE_CAPTURE'];
        if (out != null) {
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
            await File('$out/$stage-${spec.id}-$scale.png').writeAsBytes(bytes);
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await broker.close();
        await app.dispose();
      });
    }
  }
  testWidgets('Need First card preview', (tester) async {
    final priceTheme =
        Platform.environment['BSL_PRICE_THEME'] ?? 'sakura-night-garden';
    final priceScale = double.parse(
      Platform.environment['BSL_PRICE_SCALE'] ?? '1.0',
    );
    configureApplicationTestSurface(
      tester,
      const Size(1600, 1000),
      textScaleFactor: priceScale,
    );
    final original = (await tester.runAsync(
      () => ApplicationTestHarness.create(
        activeMode: CraftMode.cooking,
        backgroundId: priceTheme == 'standard' ? 'greenhouse' : priceTheme,
      ),
    ))!;
    final harness = original.rebindControllerInCurrentZone();
    await tester.runAsync(original.disposeControllerOnly);
    final mode = harness.bundle.controller.active;
    mode.selectTarget('Beer');
    mode.commitAmount('100');
    mode.commitInventory('Wheat', '50');
    mode.setIgnoreOwnedIngredients(false);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('need-preview-root'),
        child: BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          enableOpportunityAutoCheck: false,
          marketGateway: const _PreviewMarket(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check Prices'));
    await tester.pumpAndSettle();
    for (final element in find.byType(Image).evaluate()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final list = find.byKey(const PageStorageKey<String>('planner-need-first'));
    expect(list, findsOneWidget);
    if (Platform.environment['BSL_NUMBER_CAPTURE'] == 'true') {
      final field = find
          .descendant(of: list, matching: find.byType(TextField))
          .first;
      await tester.enterText(field, '10000');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '10.000');
    }
    final view = tester.renderObject<RenderBox>(list);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('need-preview-root')),
    );
    final origin = boundary.globalToLocal(view.localToGlobal(Offset.zero));
    final lastRowBottom = tester
        .getRect(find.byType(PlannerNeedQuantities).last)
        .bottom;
    final captureHeight =
        (lastRowBottom - view.localToGlobal(Offset.zero).dy + 16).clamp(
          0.0,
          view.size.height,
        );
    final out = Platform.environment['BSL_CHOICE_CAPTURE'];
    final stage = Platform.environment['BSL_CHOICE_STAGE'] ?? 'suggested';
    if (stage == 'suggested' || stage == 'final') {
      final rows = find.byType(PlannerNeedQuantities);
      for (final vendorName in ['Mineral Water', 'Leavening Agent', 'Sugar']) {
        final name = find.descendant(of: list, matching: find.text(vendorName));
        if (name.evaluate().isEmpty) continue;
        final row = find.ancestor(of: name, matching: rows).first;
        final marker = find.descendant(
          of: row,
          matching: find.byType(NpcSourceMarker),
        );
        expect(marker, findsOneWidget);
        expect(
          tester.getRect(marker).left - tester.getRect(name).right,
          closeTo(12, 2),
        );
        expect(
          tester.getRect(marker).center.dy,
          closeTo(tester.getRect(name).center.dy, 1),
        );
      }
      final inventoryStarts = <double>[];
      final missingStarts = <double>[];
      for (final element in rows.evaluate()) {
        final row = find.byWidget(element.widget);
        inventoryStarts.add(
          tester
              .getTopLeft(
                find.descendant(
                  of: row,
                  matching: find.byType(InventoryCountBadge),
                ),
              )
              .dx,
        );
        final quantities = element.widget as PlannerNeedQuantities;
        final actions = find.byKey(
          ValueKey('planner-need-purchase:${quantities.stableId}'),
        );
        final each = find.byKey(
          ValueKey('planner-need-price:${quantities.stableId}:each'),
        );
        final total = find.byKey(
          ValueKey('planner-need-price:${quantities.stableId}:Total'),
        );
        expect(
          tester.getRect(each).center.dy,
          closeTo(tester.getRect(total).center.dy, 1),
        );
        expect(
          tester.getRect(each).left,
          greaterThanOrEqualTo(tester.getRect(row).left + 60),
        );
        expect(
          tester.getRect(total).right,
          lessThanOrEqualTo(tester.getRect(row).right),
        );
        final editor = find.descendant(
          of: actions,
          matching: find.byType(TextField),
        );
        expect(
          tester.getRect(editor).right,
          lessThan(tester.getRect(actions).right),
        );
        expect(
          tester.getRect(total).left,
          greaterThan(tester.getRect(each).right),
        );
        missingStarts.add(
          tester
              .getTopLeft(
                find.descendant(
                  of: row,
                  matching: find.byType(MissingCountBadge),
                ),
              )
              .dx,
        );
      }
      for (final start in inventoryStarts) {
        expect(start, closeTo(inventoryStarts.first, 1));
      }
      for (final start in missingStarts) {
        expect(start, closeTo(missingStarts.first, 1));
      }
    }
    if (out != null) {
      await tester.runAsync(() async {
        final image = await (boundary.debugLayer! as OffsetLayer).toImage(
          Rect.fromLTWH(origin.dx, origin.dy, view.size.width, captureHeight),
          pixelRatio: 1.5,
        );
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        await File(
          '$out/$stage-$priceTheme-$priceScale-need-first.png',
        ).writeAsBytes(bytes);
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.disposeControllerOnly();
    await tester.runAsync(
      () => harness.temporaryDirectory.delete(recursive: true),
    );
  });
}

class _PreviewMarket implements MarketPriceGateway {
  const _PreviewMarket();
  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async {
    final now = DateTime.now().toUtc();
    return MarketPriceFetchResult(
      region: 'eu',
      language: 'en-US',
      fetchedAt: now,
      items: [
        for (final request in requests)
          MarketPriceRow(
            name: request.name,
            id: request.id,
            ok: true,
            price: 735,
            stock: 10000,
            source: MarketPriceSource.pearlAbyssCentralMarket,
            fetchedAt: now,
            diagnosticCode: MarketDiagnosticCode.none,
          ),
      ],
      attemptedSources: const [MarketPriceSource.pearlAbyssCentralMarket],
    );
  }
}
