import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../recipe_book/recipe_book_test_support.dart';
import 'planner_test_fixture.dart';

void main() {
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    testWidgets(
      'Planner only marks checked empty stock red in ${spec.family}',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness(
          sunriseNpcPrice: 0,
          marketRefresh: const PlannerMarketRefresh(
            prices: {'Sunrise Herb': 1000},
            stock: {},
            unlistedItemNames: {},
            fetchedAt: 42,
            summary: 'Prices checked.',
          ),
        );
        addTearDown(harness.controller.dispose);
        await tester.pumpWidget(harness.plannerHost(spec: spec));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PlannerActionKeys.p15));
        await tester.pumpAndSettle();
        final initialNeed = harness.controller.active.plan.value.missing.single;

        for (final stock in <double?>[null, 0, 5, 500]) {
          harness.controller.active.updateState(
            (state) => state.copyWith(
              market: state.market.copyWith(stock: {'Sunrise Herb': ?stock}),
            ),
            immediate: true,
          );
          await tester.pumpAndSettle();
          final label = stock == null ? 'Stock —' : 'Stock ${stock.toInt()}';
          final count = find.text(label);
          expect(count, findsOneWidget);
          final total = find
              .byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    (widget.data?.startsWith('Total ') ?? false),
              )
              .first;
          final neutral = _nearestBox(tester.element(total));
          final stockBox = _nearestBox(tester.element(count));
          if (stock == 0) {
            expect(stockBox.color, isNot(neutral.color));
            expect(stockBox.border, isNot(neutral.border));
            expect(stockBox.color, switch (spec.family) {
              _ when spec.isStandard => const Color(0x98553532),
              _ when spec.isIlluminatedLedger => const Color(0xFFEACDC4),
              _ => const Color(0x66542A39),
            });
          } else {
            expect(stockBox.color, neutral.color);
            expect(stockBox.border, neutral.border);
          }
          final currentNeed =
              harness.controller.active.plan.value.missing.single;
          expect(currentNeed.name, initialNeed.name);
          expect(currentNeed.need, initialNeed.need);
          expect(currentNeed.missing, initialNeed.missing);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('Recipe Book Market counts remain neutral in ${spec.family}', (
      tester,
    ) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final mode = environment.application.active;
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: {
            'Clear Liquid Reagent': IngredientMetadata(marketId: '5301'),
            'Pure Powder Reagent': IngredientMetadata(marketId: '5302'),
            'Elixir of Life': IngredientMetadata(marketId: '5303'),
          },
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        checkPrices: (_) async => const PlannerMarketRefresh(
          prices: {},
          stock: {'Clear Liquid Reagent': 0, 'Pure Powder Reagent': 12},
          unlistedItemNames: {},
          fetchedAt: 42,
          summary: 'Market checked.',
        ),
      );
      addTearDown(book.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: RecipeBookModal(
                controller: book,
                onClose: () {},
                onActivated: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stock —'), findsNothing);
      await tester.tap(find.byKey(RecipeBookKeys.r21CheckMarket));
      await tester.pumpAndSettle();
      for (final label in ['Stock 0', 'Stock 12', 'Stock —']) {
        final count = find.text(label);
        expect(count, findsOneWidget);
        final decoration = _nearestBox(tester.element(count));
        expect(decoration.color, spec.palette.surfaceRaised.withAlpha(86));
        expect(
          (decoration.border! as Border).top.color,
          spec.palette.textMuted.withAlpha(165),
        );
      }
      expect(find.text('0 stock'), findsNothing);
      book.setOutOfStockOnly(true);
      await tester.pumpAndSettle();
      expect(find.text('Stock 0'), findsOneWidget);
      expect(find.text('Stock 12'), findsNothing);
      expect(find.text('Stock —'), findsNothing);
      book.hideMarket();
      await tester.pumpAndSettle();
      expect(find.text('Stock 0'), findsNothing);
      expect(find.text('Stock —'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Unknown Market badge excludes NPC, reference and unlisted items',
    (tester) async {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        includeNpcPurchaseFixture: true,
        includeEdaniaReferenceFixture: true,
      );
      addTearDown(environment.dispose);
      final mode = environment.application.active;
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: {
            'Black Stone Batch 01': IngredientMetadata(marketId: '100'),
            'Mystical Parchment': IngredientMetadata(
              marketId: '101',
              npcPrice: 500,
              vendor: 'NPC shop',
            ),
            'Dawnbound Ekleta Necklace': IngredientMetadata(marketId: '102'),
            'Polished Marble': IngredientMetadata(marketId: '103'),
          },
          market: state.market.copyWith(unlistedItemNames: {'Polished Marble'}),
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      await book.checkMarket();
      expect(book.showsMarketStockFor('Black Stone Batch 01'), isTrue);
      expect(book.marketStockFor('Black Stone Batch 01'), isNull);
      expect(book.showsMarketStockFor('Mystical Parchment'), isFalse);
      expect(book.showsMarketStockFor('Dawnbound Ekleta Necklace'), isFalse);
      expect(book.showsMarketStockFor('Polished Marble'), isFalse);
      expect(book.showsMarketStockFor('Raw Material 01'), isFalse);
    },
  );
}

BoxDecoration _nearestBox(Element element) {
  BoxDecoration? result;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      result = widget.decoration as BoxDecoration;
      return false;
    }
    return true;
  });
  expect(result, isNotNull);
  return result!;
}
