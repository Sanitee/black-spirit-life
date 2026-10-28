import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
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
      'Planner only marks checked empty stock amber in ${spec.family}',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness(
          sunriseNpcPrice: 0,
          marketRefresh: const PlannerMarketRefresh(
            prices: {'Sunrise Herb': 1000},
            preorderPrices: {'Sunrise Herb': 1200},
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
              market: state.market.copyWith(
                stock: {
                  'Sunrise Herb': ?stock,
                  // No available substitute: this test isolates the stock badge.
                  'Silver Azalea': 0,
                  'High-Quality Sunrise Herb': 0,
                  'Special Sunrise Herb': 0,
                  'High-Quality Silver Azalea': 0,
                  'Special Silver Azalea': 0,
                },
              ),
            ),
            immediate: true,
          );
          await tester.pumpAndSettle();
          final label = stock == null
              ? 'Stock —'
              : stock == 0
              ? 'Out of stock'
              : 'Stock ${stock.toInt()}';
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
            expect(stockBox.color, spec.plannerOutOfStockAccent);
            final textColor = tester.widget<Text>(count).style!.color!;
            final backgroundLuminance = stockBox.color!.computeLuminance();
            final textLuminance = textColor.computeLuminance();
            final contrast = backgroundLuminance > textLuminance
                ? (backgroundLuminance + .05) / (textLuminance + .05)
                : (textLuminance + .05) / (backgroundLuminance + .05);
            expect(contrast, greaterThanOrEqualTo(4.5));
          } else {
            expect(stockBox.color, neutral.color);
            expect(stockBox.border, neutral.border);
          }
          final edge = find.byKey(
            const ValueKey('planner-market-accent:Sunrise Herb'),
          );
          if (stock == null) {
            expect(edge, findsNothing);
            expect(find.text('Out of stock'), findsNothing);
          } else {
            expect(edge, findsOneWidget);
            final edgeBox =
                tester.widget<DecoratedBox>(edge).decoration as BoxDecoration;
            expect(
              edgeBox.color,
              stock == 0
                  ? spec.plannerOutOfStockAccent
                  : spec.plannerAvailableAccent,
            );
          }
          final currentNeed =
              harness.controller.active.plan.value.missing.single;
          expect(currentNeed.name, initialNeed.name);
          expect(currentNeed.need, initialNeed.need);
          expect(currentNeed.missing, initialNeed.missing);
          final budget = currentNeed.missing * (stock == 0 ? 1200 : 1000);
          expect(currentNeed.market.total, budget);
          expect(find.text('Total ${formatSilver(budget)}'), findsOneWidget);
          expect(find.text(formatSilver(budget)), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byKey(PlannerActionKeys.p16));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('planner-market-accent:Sunrise Herb')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Planner vendors share available colour without market warnings in ${spec.id}',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness(
          marketRefresh: const PlannerMarketRefresh(
            prices: {'Sunrise Herb': 1000},
            stock: {'Sunrise Herb': 0},
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
        final row = find.byKey(const ValueKey('need:Sunrise Herb'));
        final edge = find.byKey(
          const ValueKey('planner-market-accent:Sunrise Herb'),
        );
        expect(edge, findsOneWidget);
        expect(
          (tester.widget<DecoratedBox>(edge).decoration as BoxDecoration).color,
          spec.plannerAvailableAccent,
        );
        expect(
          find.descendant(of: row, matching: find.text('Vendor item')),
          findsOneWidget,
        );
        expect(find.text('Out of stock'), findsNothing);
        expect(find.text('Stock 0'), findsNothing);
        expect(tester.takeException(), isNull);
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
