import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_used_in_panel.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_switch_controls.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show checkColumnAlignment, checkBadgeLines;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repo = CatalogRepository.cached(catalog);
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
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final theme in RetainedThemeRegistry.themes) {
    for (final view in [
      (width: 1440.0, scale: 1.0),
      (width: 1440.0, scale: 2.0),
      (width: 720.0, scale: 2.0),
    ]) {
      testWidgets(
        'Visible recipes and switch alignment ${theme.id} ${view.width} ${view.scale}',
        (tester) async {
          tester.view.physicalSize = Size(view.width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = fixture.controller(
            catalog,
            CraftMode.cooking,
            'Seafood Cron Meal',
            1,
          );
          final book = RecipeBookController(
            modeController: app.active,
            catalogRepository: repo,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: ['Seafood Cron Meal'],
          );
          final transport = ChoiceMarketTransport();
          final values = {
            'Balenos Meal': (138200, 21900),
            'Sute Tea': (41700, 0),
            'Savory Steak': (0, 32100),
          };
          for (final e in values.entries) {
            transport.values[repo.bundledMarketId(e.key)!] = (
              price: 100000,
              stock: e.value.$1,
              preorders: e.value.$2,
            );
          }
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          addTearDown(book.dispose);
          addTearDown(app.dispose);
          addTearDown(broker.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.materialTheme(),
              home: ThemeSpecScope(
                spec: theme,
                child: PlannerChoiceMarketScope(
                  repository: broker,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(view.width, 1000),
                      textScaler: TextScaler.linear(view.scale),
                    ),
                    child: Scaffold(
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: RepaintBoundary(
                            key: const ValueKey('switch-capture'),
                            child: RecipeBookUsedInPanel(
                              controller: book,
                              sourceName: 'Balenos Meal',
                              snapshot: book.usedInFor('Balenos Meal'),
                              onClose: () {},
                              onActivate: (_, _) => false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle(tester, broker);
          await tester.pumpAndSettle();
          final tableFinder = find.byType(RecipeIngredientTable);
          expect(tableFinder, findsOneWidget);
          expect(
            find.byKey(
              RecipeBookKeys.expandUsedInResult(
                'Balenos Meal',
                book.usedInFor('Balenos Meal').entries.single.mode.key,
                'Seafood Cron Meal',
              ),
            ),
            findsNothing,
          );
          expect(
            tester.widget<RecipeIngredientTable>(tableFinder).rows.length,
            4,
          );
          final selector = find.byType(RecipeVariantSelector);
          final choices = find.descendant(
            of: selector,
            matching: find.byType(RecipeSwitchChoice),
          );
          expect(choices, findsNWidgets(4));
          for (final label in ['Recipe', 'Batch']) {
            final labelFinder = find.descendant(
              of: selector,
              matching: find.text(label),
            );
            final rect = tester.getRect(labelFinder);
            final switches = tester.getRect(
              find
                  .descendant(
                    of: selector,
                    matching: find.byType(RecipeSwitchGroup),
                  )
                  .at(label == 'Recipe' ? 0 : 1),
            );
            expect(rect.center.dy, closeTo(switches.center.dy, 1));
            expect(switches.left - rect.right, closeTo(10, 1));
            expect(tester.widget<Text>(labelFinder).style!.fontSize, 14);
          }
          final routeB = choices.at(1);
          await tester.ensureVisible(routeB);
          await tester.tap(routeB);
          await settle(tester, broker);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RecipeIngredientTable>(tableFinder)
                .rows
                .map((r) => r.quantity),
            [3, 3, 1, 1],
          );
          final batch10 = find.descendant(
            of: selector,
            matching: find.text('10×'),
          );
          await tester.ensureVisible(batch10);
          await tester.tap(batch10);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RecipeIngredientTable>(tableFinder)
                .rows
                .map((r) => r.quantity),
            [30, 30, 10, 10, 1],
          );
          await tester.tap(
            find.descendant(of: selector, matching: find.text('1×')),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<RecipeIngredientTable>(tableFinder).rows.length,
            4,
          );
          final target = find.byKey(
            RecipeBookKeys.targetUsedInResult(
              'Balenos Meal',
              book.usedInFor('Balenos Meal').entries.single.mode.key,
              'Seafood Cron Meal',
            ),
          );
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          checkColumnAlignment(tester);
          checkBadgeLines(tester);
          final panel = find.byKey(RecipeBookKeys.usedInPanel('Balenos Meal'));
          final bounds = tester.getRect(panel);
          expect(bounds.left, greaterThanOrEqualTo(20));
          expect(bounds.right, lessThanOrEqualTo(view.width - 20));
          expect(bounds.top, greaterThanOrEqualTo(20));
          expect(bounds.bottom, lessThanOrEqualTo(980));
          if (view.scale == 1) {
            expect(bounds.width, lessThan(850));
            expect(bounds.height, lessThan(650));
          }
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: tester.getCenter(routeB));
          await mouse.moveTo(tester.getCenter(routeB));
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(Tooltip), findsNothing);
          await mouse.removePointer();
          await tester.runAsync(() async {
            for (final image in tester.widgetList<Image>(find.byType(Image))) {
              await precacheImage(image.image, tester.element(panel));
            }
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('switch-capture')),
            );
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/recipe-switch-captures/${theme.id}-${view.width.toInt()}-${view.scale}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
