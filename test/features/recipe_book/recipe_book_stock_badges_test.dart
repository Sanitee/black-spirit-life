import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show capture, checkOutputStockAlignment;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
  const names = ['Beer', 'Vinegar', 'Butter-roasted Lobster', 'Citron Juice'];

  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/segoeuib.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final theme in RetainedThemeRegistry.themes) {
    for (final width in [1464.0, 1920.0]) {
      for (final scale in [1.0, 2.0]) {
        final label = 'stock-${theme.id}-$width-$scale';
        testWidgets(label, (tester) async {
          final size = Size(width, 1080);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
          final book = RecipeBookController(
            modeController: app.active,
            catalogRepository: repository,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: names,
          );
          for (final name in names) {
            book.toggleFavorite(name);
          }
          book.setFavoritesOnly(true);
          final transport = ChoiceMarketTransport();
          transport.values[repository.bundledMarketId('Beer')!] = (
            price: 480,
            stock: 0,
            preorders: 23456,
          );
          transport.values[repository.bundledMarketId('Vinegar')!] = (
            price: 480,
            stock: 12594,
            preorders: 84,
          );
          transport.values[repository.bundledMarketId(
            'Butter-roasted Lobster',
          )!] = (
            price: 480,
            stock: 1500000,
            preorders: 2000000,
          );
          transport.values[repository.bundledMarketId('Citron Juice')!] = (
            price: 480,
            stock: 23,
            preorders: 0,
          );
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('capture-root'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme.materialTheme(),
                home: ThemeSpecScope(
                  spec: theme,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: PlannerChoiceMarketScope(
                      repository: broker,
                      child: Scaffold(
                        body: RepaintBoundary(
                          key: const ValueKey('capture'),
                          child: RecipeBookModal(
                            controller: book,
                            onClose: () {},
                            onActivated: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(transport.requests, isEmpty);
          expect(find.byType(MarketCountBadges), findsNothing);
          final hold = transport.hold = Completer<void>();
          await tester.tap(find.byKey(RecipeBookKeys.r23MarketSort));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Stock ↑').last);
          await tester.pumpAndSettle();
          expect(book.marketControlsVisible, isFalse);
          expect(find.byType(InventoryCountBadge), findsNothing);
          expect(find.textContaining('Can craft'), findsNothing);
          checkOutputStockAlignment(tester);
          for (final badge in tester.widgetList<MarketCountBadges>(
            find.byType(MarketCountBadges),
          )) {
            expect(badge.stock, isNull);
            expect(badge.preorders, isNull);
          }
          await capture(tester, '$label-unknown');
          transport.hold = null;
          hold.complete();
          await settle(tester, broker);
          await tester.pumpAndSettle();
          checkOutputStockAlignment(tester);
          expect(book.snapshot.entries.map((e) => e.name), [
            'Beer',
            'Citron Juice',
            'Vinegar',
            'Butter-roasted Lobster',
          ]);
          for (final name in names) {
            final output = find.byKey(ValueKey('recipe-output-stock:$name'));
            if (output.evaluate().isEmpty) continue;
            final badge = tester.widget<MarketCountBadges>(
              find.descendant(
                of: output,
                matching: find.byType(MarketCountBadges),
              ),
            );
            final expected =
                transport.values[repository.bundledMarketId(name)]!;
            expect(badge.stock, expected.stock);
            expect(badge.preorders, expected.preorders);
            expect(
              find.descendant(of: output, matching: find.byType(Tooltip)),
              findsNothing,
            );
            final texts = find.descendant(
              of: output,
              matching: find.byType(Text),
            );
            final rectangles = texts
                .evaluate()
                .map((e) => tester.getRect(find.byWidget(e.widget)))
                .toList();
            for (final rect in rectangles) {
              expect(
                tester.getRect(output).inflate(.1).contains(rect.topLeft),
                isTrue,
              );
              expect(
                tester.getRect(output).inflate(.1).contains(rect.bottomRight),
                isTrue,
              );
            }
            if (rectangles.length == 2 &&
                (rectangles[0].top - rectangles[1].top).abs() < 1) {
              expect(
                rectangles[0].center.dy,
                closeTo(rectangles[1].center.dy, .1),
              );
              expect(
                rectangles[1].left - rectangles[0].right,
                greaterThanOrEqualTo(6),
              );
            }
          }
          expect(tester.takeException(), isNull);
          await capture(tester, '$label-loaded');
          book.setMarketSort(RecipeBookMarketSort.stockHighToLow);
          await tester.pumpAndSettle();
          expect(book.snapshot.entries.first.name, 'Butter-roasted Lobster');
          checkOutputStockAlignment(tester);
          expect(find.byType(InventoryCountBadge), findsNothing);
          expect(book.debugCachedItemInfoCount, 0);
          final outputIds = names.map(repository.bundledMarketId).toSet();
          expect(
            transport.requests.expand((r) => r.ids).every(outputIds.contains),
            isTrue,
          );
          // Cached redraws and changing direction must not refetch or load ingredients.
          final requestCount = transport.requests.length;
          book.setMarketSort(RecipeBookMarketSort.none);
          await tester.pumpAndSettle();
          expect(find.byType(MarketCountBadges), findsNothing);
          book.setMarketSort(RecipeBookMarketSort.stockLowToHigh);
          await settle(tester, broker);
          await tester.pumpAndSettle();
          expect(transport.requests.length, requestCount);
          await tester.pumpWidget(const SizedBox());
          book.dispose();
          await broker.dispose();
          await app.dispose();
        });
      }
    }
  }

  test(
    'live stock sorting rejects expired saved stock, offline preserves it',
    () async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: repository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: names,
      );
      final broker = SharedMarketRepository(transport: ChoiceMarketTransport());
      app.active.updateState(
        (state) => state.copyWith(
          market: state.market.copyWith(stock: {'Beer': 99}, fetchedAt: 1),
        ),
        immediate: true,
      );
      expect(book.marketStockFor('Beer'), 99);
      book.connectAvailabilityMarket(broker);
      expect(book.marketStockFor('Beer'), isNull);
      app.active.updateState(
        (state) => state.copyWith(
          market: state.market.copyWith(
            fetchedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        immediate: true,
      );
      expect(book.marketStockFor('Beer'), 99);
      book.dispose();
      await broker.dispose();
      await app.dispose();
    },
  );
}
