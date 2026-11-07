import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show checkColumnAlignment, checkBadgeLines, checkValueAlignment;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
  setUpAll(() async {
    final fonts = '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
    final artifacts = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent.path;
    for (final entry in {
      'Segoe UI': ['$fonts/segoeui.ttf', '$fonts/seguisb.ttf'],
      'Georgia': ['$fonts/georgia.ttf', '$fonts/georgiab.ttf'],
      'MaterialIcons': ['$artifacts/material_fonts/MaterialIcons-Regular.otf'],
    }.entries) {
      if (!File(entry.value.first).existsSync()) continue;
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final layout in [
      (width: 1100.0, scale: 1.0),
      (width: 720.0, scale: 2.0),
    ]) {
      testWidgets('missing item pairs ${spec.id} ${layout.width} ${layout.scale}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(layout.width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixture.controller(
          catalog,
          CraftMode.cooking,
          'Aloe Cookie',
          1,
        );
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: const ['Aloe Cookie'],
        );
        for (final row in book.availabilityFor('Aloe Cookie').ingredients) {
          final choices = book.ingredientChoices('Aloe Cookie', row.ingredient);
          book.selectIngredientChoice(
            'Aloe Cookie',
            choices.firstWhere(
              (choice) => choice.name == 'Wheat Dough',
              orElse: () => row,
            ),
          );
        }
        book.toggleFavorite('Aloe Cookie');
        book.setFavoritesOnly(true);
        book.setMarketSort(RecipeBookMarketSort.availability);
        app.active.updateState(
          (s) => s.copyWith(
            inventory: {
              'Aloe': 3,
              'Wheat Dough': 3,
              'Sugar': 0,
              'Cooking Honey': 1,
            },
          ),
          immediate: true,
        );
        final transport = ChoiceMarketTransport();
        for (final entry in {
          'Aloe': (32100, 4900),
          'Wheat Dough': (0, 28500),
          'Cooking Honey': (585, 712),
          'Aloe Cookie': (11258, 0),
        }.entries) {
          transport.values[repository.bundledMarketId(entry.key)!] = (
            price: entry.key == 'Aloe Cookie' ? 2000 : 480,
            stock: entry.value.$1,
            preorders: entry.value.$2,
          );
        }
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('missing-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: spec.materialTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                child: child!,
              ),
              home: ThemeSpecScope(
                spec: spec,
                child: PlannerChoiceMarketScope(
                  repository: broker,
                  child: Scaffold(
                    body: RecipeBookModal(
                      controller: book,
                      onClose: () {},
                      onActivated: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester, broker);
        await tester.pumpAndSettle();
        final missing = find.byKey(
          const ValueKey('recipe-missing:Aloe Cookie'),
        );
        await tester.ensureVisible(missing);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(missing);
        final expected = {
          'Aloe': 2.0,
          'Wheat Dough': 4.0,
          'Sugar': 4.0,
          'Cooking Honey': 2.0,
        };
        expect(book.availabilityFor('Aloe Cookie').missing, expected);
        final rects = <Rect>[];
        for (final entry in expected.entries) {
          final pair = find.byKey(
            ValueKey('recipe-missing-item:Aloe Cookie:${entry.key}'),
          );
          final rect = tester.getRect(pair);
          rects.add(rect);
          final icon = find.descendant(
            of: pair,
            matching: find.byType(RecipeBookItemIcon),
          );
          final quantity = find.descendant(
            of: pair,
            matching: find.text('×${entry.value.toInt()}'),
          );
          expect(tester.widget<RecipeBookItemIcon>(icon).name, entry.key);
          expect(
            find.descendant(of: pair, matching: find.text(entry.key)),
            findsNothing,
          );
          expect(
            tester.getRect(icon).center.dy,
            closeTo(tester.getRect(quantity).center.dy, .1),
          );
          expect(
            tester.getRect(quantity).left - tester.getRect(icon).right,
            closeTo(7, .1),
          );
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right + .1));
        }
        for (var i = 1; i < rects.length; i++) {
          if ((rects[i].top - rects[i - 1].top).abs() < .1) {
            expect(rects[i].left - rects[i - 1].right, closeTo(12, .1));
          } else {
            expect(
              rects[i].top - rects[i - 1].bottom,
              greaterThanOrEqualTo(7.9),
            );
          }
        }
        if (layout.width == 1100) {
          expect(rects.map((r) => r.top).toSet().length, 1);
        }
        expect(
          find.byKey(const ValueKey('recipe-can-craft:Aloe Cookie')),
          findsNothing,
        );
        expect(find.textContaining('ingredients owned'), findsNothing);
        expect(find.text('Est. silver per craft · after tax'), findsNothing);
        for (final label in [
          'Buy all',
          'Buy missing',
          'Sell owned',
          'Profit',
          'Cash return',
          'Sale value',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        checkValueAlignment(tester, 'Aloe Cookie');
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(
              image.image,
              tester.element(find.byKey(const ValueKey('missing-capture'))),
            );
          }
        });
        await tester.pumpAndSettle();
        final root = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('missing-capture')),
        );
        final card = tester.getRect(
          find.byKey(RecipeBookKeys.card('Aloe Cookie')),
        );
        final table = tester.getRect(find.byType(RecipeIngredientTable));
        final crop = Rect.fromLTRB(
          table.left - 14,
          table.bottom + 3,
          table.right + 14,
          card.bottom - 5,
        );
        expect(crop.top, greaterThanOrEqualTo(0));
        expect(crop.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
        await tester.runAsync(() async {
          final image = await (root.debugLayer! as OffsetLayer).toImage(crop);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/missing-icons-captures/${spec.id}-${layout.width.toInt()}-${(layout.scale * 100).toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });

        if (layout.width == 1100 && spec.isSakuraNightGarden) {
          // Live inventory removes satisfied items and restores the craft count.
          app.active.updateState(
            (s) => s.copyWith(
              inventory: {
                'Aloe': 120,
                'Wheat Dough': 45,
                'Sugar': 0,
                'Cooking Honey': 60,
              },
            ),
            immediate: true,
          );
          await tester.pumpAndSettle();
          expect(book.availabilityFor('Aloe Cookie').missing, {'Sugar': 4.0});
          expect(
            find.descendant(
              of: missing,
              matching: find.byType(RecipeBookItemIcon),
            ),
            findsOneWidget,
          );
          // Artwork remains useful without adding ordinary hover text.
          final anchor = RecipeBookKeys.itemInfoAnchor(
            'Sugar',
            'recipe-missing:Aloe Cookie:Sugar',
          );
          await tester.tap(find.byKey(anchor));
          await tester.pumpAndSettle();
          expect(
            find.byKey(
              RecipeBookKeys.pinnedItemInfo(
                'Sugar',
                'recipe-missing:Aloe Cookie:Sugar',
              ),
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          app.active.commitInventory('Sugar', '8');
          await tester.pumpAndSettle();
          expect(missing, findsNothing);
          expect(find.text('Can craft 2'), findsOneWidget);
          // A selected substitute must change the missing picture and quantity.
          final dough = book
              .availabilityFor('Aloe Cookie')
              .ingredients
              .firstWhere((r) => r.name == 'Wheat Dough');
          final barley = book
              .ingredientChoices('Aloe Cookie', dough.ingredient)
              .firstWhere((r) => r.name == 'Barley Dough');
          book.selectIngredientChoice('Aloe Cookie', barley);
          await settle(tester, broker);
          await tester.pumpAndSettle();
          expect(
            find.byKey(
              const ValueKey('recipe-missing-item:Aloe Cookie:Barley Dough'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey('recipe-missing-item:Aloe Cookie:Wheat Dough'),
            ),
            findsNothing,
          );
          final pair = find.byKey(
            const ValueKey('recipe-missing-item:Aloe Cookie:Barley Dough'),
          );
          expect(
            book.availabilityFor('Aloe Cookie').missing['Barley Dough'],
            barley.quantity,
          );
          expect(
            find.descendant(
              of: pair,
              matching: find.byType(RecipeBookItemIcon),
            ),
            findsOneWidget,
          );
          for (final sort in [
            RecipeBookMarketSort.availabilityProfit,
            RecipeBookMarketSort.none,
          ]) {
            book.setMarketSort(sort);
            await settle(tester, broker);
            await tester.pumpAndSettle();
            expect(
              missing,
              sort == RecipeBookMarketSort.availabilityProfit
                  ? findsOneWidget
                  : findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        }
        if (layout.width == 720) {
          // Constrain the actual footer independently of the desktop toolbar.
          final wrap = tester.widget<Wrap>(missing);
          await tester.pumpWidget(
            MaterialApp(
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 260,
                        child: RepaintBoundary(
                          key: const ValueKey('wrap-capture'),
                          child: ColoredBox(
                            color: spec.palette.surface,
                            child: wrap,
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
          final wrapped = [
            for (final name in expected.keys)
              tester.getRect(
                find.byKey(ValueKey('recipe-missing-item:Aloe Cookie:$name')),
              ),
          ];
          expect(wrapped.map((r) => r.top).toSet().length, greaterThan(1));
          for (final rect in wrapped) {
            expect(rect.right, lessThanOrEqualTo(260));
          }
          expect(tester.takeException(), isNull);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('wrap-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/missing-icons-captures/${spec.id}-wrapped.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        book.connectAvailabilityMarket(null);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        book.dispose();
        await broker.dispose();
        await app.dispose();
      });
    }
  }
}
