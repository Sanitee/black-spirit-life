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
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show capture, checkColumnAlignment, checkBadgeLines;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
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
  Future<void> host(
    WidgetTester tester,
    ThemeSpec spec,
    double scale,
    double width,
    Widget child, {
    SharedMarketRepository? broker,
  }) async {
    tester.view.physicalSize = Size(width, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture-root'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: PlannerChoiceMarketScope(
              repository: broker,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 960),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  key: const ValueKey('capture'),
                  backgroundColor: spec.palette.canvas,
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (broker != null) {
      await settle(tester, broker);
      await tester.pumpAndSettle();
    }
  }

  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Details and adaptive choices ${spec.id} $scale', (
        tester,
      ) async {
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
          allowedTargets: ['Aloe Cookie', 'Eilton Sandwich'],
        )..openPreview('Aloe Cookie');
        app.active.updateState(
          (state) => state.copyWith(
            inventory: {
              'Aloe': 120,
              'Sugar': 0,
              'Cooking Honey': 999900,
              'Wheat Dough': 45,
            },
          ),
          immediate: true,
        );
        final transport = ChoiceMarketTransport();
        transport.values[repository.bundledMarketId('Aloe')!] = (
          price: 480,
          stock: 0,
          preorders: 28800,
        );
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        addTearDown(book.dispose);
        addTearDown(app.dispose);
        addTearDown(broker.dispose);
        await host(
          tester,
          spec,
          scale,
          1440,
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
          broker: broker,
        );
        final panel = find.byKey(RecipeBookKeys.previewPanel);
        final table = find.descendant(
          of: panel,
          matching: find.byType(RecipeIngredientTable),
        );
        expect(table, findsOneWidget);
        final backing =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('recipe-preview-backing')),
                    )
                    .decoration
                as BoxDecoration;
        expect(
          backing.color!.a,
          spec.isSakuraNightGarden || spec.isIlluminatedLedger ? 0 : 1,
          reason:
              'Text behind the Standard Details popup must not bleed through.',
        );
        expect(
          tester.widget<RecipeIngredientTable>(table).rows.map((r) => r.name),
          ['Aloe', 'Wheat Dough', 'Sugar', 'Cooking Honey'],
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.byType(InventoryCountBadge),
          ),
          findsNWidgets(4),
        );
        expect(
          find.descendant(of: panel, matching: find.text('NPC')),
          findsOneWidget,
        );
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        final rect = tester.getRect(panel);
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(1428));
        if (scale == 1) expect(rect.width, lessThan(850));
        await capture(tester, 'details-${spec.id}-$scale');
        app.active.updateState(
          (state) =>
              state.copyWith(inventory: {...state.inventory, 'Aloe': 777}),
          immediate: true,
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<RecipeIngredientTable>(table).rows.first.owned,
          777,
        );
        await tester.tap(
          find.byKey(
            ValueKey(
              'recipe-substitutes:Aloe Cookie:${tester.widget<RecipeIngredientTable>(table).rows[1].ingredient.name}',
            ),
          ),
        );
        await settle(tester, broker);
        await tester.pumpAndSettle();
        final chooser = find.byWidgetPredicate(
          (w) => w is RecipeIngredientTable && w.onChoose != null,
        );
        expect(chooser, findsOneWidget);
        final choicesWidget = tester.widget<RecipeIngredientTable>(chooser);
        expect(choicesWidget.rows.length, greaterThan(1));
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        final alternate = choicesWidget.rows.firstWhere(
          (r) => r.name != 'Wheat Dough',
        );
        await tester.ensureVisible(
          find.byKey(ValueKey('recipe-choose:Aloe Cookie:${alternate.name}')),
        );
        await tester.tap(
          find.byKey(ValueKey('recipe-choose:Aloe Cookie:${alternate.name}')),
        );
        await settle(tester, broker);
        await tester.pumpAndSettle();
        expect(
          tester.widget<RecipeIngredientTable>(table).rows[1].name,
          alternate.name,
        );
        expect(
          tester.widget<RecipeIngredientTable>(table).rows[1].quantity,
          alternate.quantity,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        book.connectAvailabilityMarket(null);
        await tester.pumpAndSettle();
      });

      testWidgets('content-sized Hot Pepper chooser ${spec.id} $scale', (
        tester,
      ) async {
        final app = fixture.controller(
          catalog,
          CraftMode.processing,
          'Red Pepper Powder',
          1,
        );
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: ['Red Pepper Powder'],
        )..openPreview('Red Pepper Powder');
        final transport = ChoiceMarketTransport();
        transport.values[repository.bundledMarketId('Hot Pepper')!] = (
          price: 800,
          stock: 0,
          preorders: 269900,
        );
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        addTearDown(book.dispose);
        addTearDown(app.dispose);
        addTearDown(broker.dispose);
        await host(
          tester,
          spec,
          scale,
          1440,
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
          broker: broker,
        );
        await tester.tap(
          find.byKey(
            const ValueKey('recipe-substitutes:Red Pepper Powder:Hot Pepper'),
          ),
        );
        await settle(tester, broker);
        await tester.pumpAndSettle();
        final chooser = find.byWidgetPredicate(
          (w) => w is RecipeIngredientTable && w.onChoose != null,
        );
        expect(chooser, findsOneWidget);
        final choices = tester.widget<RecipeIngredientTable>(chooser);
        expect(choices.rows, hasLength(3));
        final content = RecipeIngredientTable.contentWidth(
          tester.element(chooser),
          rows: choices.rows,
          marketFor: choices.marketFor,
          now: choices.now,
        );
        final width = tester.getSize(chooser).width;
        if (scale == 1) {
          expect(width, inInclusiveRange(content - 1, content + 16));
          expect(width, lessThan(850));
        }
        final rich = find.descendant(
          of: chooser,
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('×'),
          ),
        );
        for (final element in rich.evaluate()) {
          final render = tester.renderObject<RenderParagraph>(
            find.byWidget(element.widget),
          );
          expect(
            render
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: 0,
                    extentOffset: (element.widget as RichText).text
                        .toPlainText()
                        .length,
                  ),
                  boxHeightStyle: ui.BoxHeightStyle.max,
                )
                .map((box) => box.top)
                .toSet(),
            hasLength(1),
          );
        }
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        await capture(tester, 'adaptive-choices-${spec.id}-$scale');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        // The preview uses its own mode controller when opened through routes.
        book.previewController.connectAvailabilityMarket(null);
        book.connectAvailabilityMarket(null);
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('measured labels grow naturally and cap at narrow viewport', (
    tester,
  ) async {
    final app = fixture.controller(
      catalog,
      CraftMode.cooking,
      'Eilton Sandwich',
      1,
    );
    final book = RecipeBookController(
      modeController: app.active,
      catalogRepository: repository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: ['Eilton Sandwich'],
    )..openPreview('Eilton Sandwich');
    addTearDown(book.dispose);
    addTearDown(app.dispose);
    await host(
      tester,
      RetainedThemeRegistry.themes.firstWhere(
        (spec) => spec.isSakuraNightGarden,
      ),
      2,
      720,
      RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
    );
    final table = find.byType(RecipeIngredientTable);
    final rows = tester.widget<RecipeIngredientTable>(table).rows;
    final context = tester.element(table);
    double measure(String label) => RecipeIngredientTable.contentWidth(
      context,
      rows: [
        RecipeBookIngredientChoice(
          ingredient: rows.first.ingredient,
          name: label,
          baseName: label,
          grade: 'normal',
          quantity: 123,
          owned: 0,
          npc: false,
          marketable: true,
          stock: null,
          preorders: null,
        ),
      ],
    );
    expect(
      measure('Extraordinarily Long Ingredient Name'),
      greaterThan(measure('Aloe') + 200),
    );
    final rect = tester.getRect(find.byKey(RecipeBookKeys.previewPanel));
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.right, lessThanOrEqualTo(708));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsWidgets,
    );
    checkColumnAlignment(tester);
    checkBadgeLines(tester);
    await capture(tester, 'details-narrow-200');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    book.connectAvailabilityMarket(null);
    await tester.pumpAndSettle();
  });
}
