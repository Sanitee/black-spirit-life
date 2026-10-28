import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate, ImageByteFormat;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_calculations.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_best_use.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_craft_card_material.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/profile_game_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void _glassTestWidgets(
  String description,
  Future<void> Function(WidgetTester) callback, {
  bool? skip,
}) => testWidgets(description, (tester) async {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    await callback(tester);
  } finally {
    debugDisableShadows = previous;
  }
}, skip: skip);

void main() {
  setUpAll(_loadFonts);

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    for (final view in [
      (const Size(1200, 752), 1.0),
      (const Size(900, 1000), 1.0),
      (const Size(1200, 1200), 2.0),
    ]) {
      _glassTestWidgets(
        'life-skill icons precede mode labels $background ${view.$1.width} ${view.$2}',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            view.$1,
            textScaleFactor: view.$2,
          );
          final fixture = (await tester.runAsync(
            () => _Fixture.create(exchange: false, backgroundId: background),
          ))!;
          try {
            final controller = fixture.controller;
            await tester.pumpWidget(_host(controller));
            await _settleImages(tester);
            final planner = controller.appController.documentSnapshot;
            for (final mode in [
              CraftMode.cooking,
              CraftMode.alchemy,
              CraftMode.processing,
            ]) {
              final button = find.byKey(ValueKey('craft-mode-${mode.name}'));
              final icon = find.descendant(
                of: button,
                matching: find.byType(ProfileIcon),
              );
              final label = find.descendant(
                of: button,
                matching: find.text(mode.label),
              );
              expect(icon, findsOneWidget);
              expect(tester.widget<ProfileIcon>(icon).artwork.name, mode.name);
              expect(tester.getSize(icon), const Size(20, 20));
              final iconBounds = tester.getRect(icon);
              final labelBounds = tester.getRect(label);
              expect(labelBounds.left - iconBounds.right, closeTo(8, .01));
              expect(iconBounds.center.dy, closeTo(labelBounds.center.dy, .01));
              expect(
                tester.getRect(button).contains(labelBounds.bottomRight),
                isTrue,
              );
              await tester.ensureVisible(button);
              await tester.tap(button);
              await _settleCalculation(tester, controller);
              await _settleImages(tester);
              expect(controller.preferences.mode, mode);
              expect(controller.appController.documentSnapshot, same(planner));
              expect(tester.takeException(), isNull);
            }
            await _captureSubstitutes(
              tester,
              'skill-icons-$background-${view.$1.width.toInt()}-${view.$2}',
              region: find.byKey(const ValueKey('craft-mode-tabs')),
            );
            if (background == 'sakura-night-garden' &&
                view.$1.width == 1200 &&
                view.$2 == 1) {
              await _captureSubstitutes(tester, 'skill-icons-full-workspace');
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await _settleWork(tester, fixture.dispose());
          }
        },
      );
    }
  }

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    _glassTestWidgets('best use clear draft and selection $background', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1200, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, backgroundId: background),
      ))!;
      try {
        final controller = fixture.controller;
        controller.change((p) => p.section = 'best-use');
        await tester.pumpWidget(_host(controller));
        await _settleImages(tester);
        final input = find.descendant(
          of: find.byKey(const ValueKey('best-use-item')),
          matching: find.byType(TextField),
        );
        final clear = find.byKey(const ValueKey('best-use-clear'));
        final popup = find.byWidgetPredicate(
          (w) =>
              w is AppSurface && w.semanticLabel == 'Best use for item choices',
        );
        expect(clear, findsNothing);
        await tester.enterText(input, 'not a real ingredient');
        await tester.pumpAndSettle();
        expect(clear, findsOneWidget);
        expect(find.text('No matching items'), findsOneWidget);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        expect(controller.preferences.bestUseItem, isEmpty);
        expect(clear, findsNothing);
        expect(popup, findsNothing);

        await tester.enterText(input, 'Aloe');
        await _settleImages(tester);
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is AppButton && w.semanticLabel == 'Select Aloe',
          ),
        );
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
        expect(controller.preferences.bestUseItem, 'Aloe');
        expect(controller.bestUseQuotes, isNotEmpty);
        expect(popup, findsNothing);
        await _captureSubstitutes(
          tester,
          'best-use-search-selected-$background',
        );
        final requests = List<String>.of(fixture.requests);
        final planner = controller.appController.documentSnapshot;
        // An emptied draft must still offer clear for the committed selection.
        await tester.enterText(input, '');
        await tester.pumpAndSettle();
        expect(clear, findsOneWidget);
        final mouse = await tester.startGesture(
          tester.getCenter(clear),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await mouse.up();
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
        expect(controller.preferences.bestUseItem, isEmpty);
        expect(controller.bestUseQuotes, isEmpty);
        expect(find.text('Choose an item'), findsOneWidget);
        expect(find.byKey(const ValueKey('best-use-basis')), findsNothing);
        expect(popup, findsNothing);
        expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(controller.preferences.bestUseItem, isEmpty);
        expect(fixture.requests, requests);
        expect(controller.appController.documentSnapshot, same(planner));

        // The dropdown remains useful after clearing, including keyboard use.
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('best-use-item')),
            matching: find.byIcon(Icons.expand_more),
          ),
        );
        await tester.pumpAndSettle();
        expect(popup, findsOneWidget);
        await tester.tap(input);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
        expect(controller.preferences.bestUseItem, controller.bestUseItems[1]);

        configureApplicationTestSurface(
          tester,
          const Size(900, 1100),
          textScaleFactor: 2,
        );
        await _settleImages(tester);
        final bounds = tester.getRect(input);
        expect(bounds.contains(tester.getCenter(clear)), isTrue);
        expect(tester.getSize(clear), const Size(40, 40));
        await _captureSubstitutes(tester, 'best-use-search-large-$background');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    _glassTestWidgets('best use balance compact cards $background', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1200, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          backgroundId: background,
          seedNonMarketPrices: false,
          pricesByName: const {'Aloe': 1100, 'Aloe Yogurt': 32000},
        ),
      ))!;
      try {
        await _prepareAloeBestUse(tester, fixture);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final requests = List<String>.of(fixture.requests);
        final quotes = fixture.controller.bestUseQuotes;
        for (final view in [
          (size: const Size(1200, 900), scale: 1.0),
          (size: const Size(1500, 940), scale: 1.0),
          (size: const Size(900, 1100), scale: 2.0),
        ]) {
          configureApplicationTestSurface(
            tester,
            view.size,
            textScaleFactor: view.scale,
          );
          await _settleImages(tester);
          expect(
            find.text('Compared with selling 1 Aloe · after tax'),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('best-use-basis')), findsOneWidget);
          expect(find.text('Per 1 Aloe · after tax'), findsNothing);
          expect(find.text('Profit/Loss per item'), findsNothing);
          for (final name in ['Aloe Yogurt', 'Aloe Cookie']) {
            _expectBalancedBestUseCard(tester, name, compact: view.scale == 1);
          }
          expect(
            tester
                .getSize(find.byKey(const ValueKey('craft-card:Aloe Yogurt')))
                .height,
            closeTo(
              tester
                  .getSize(find.byKey(const ValueKey('craft-card:Aloe Cookie')))
                  .height,
              .01,
            ),
          );
          expect(tester.takeException(), isNull);
          await _captureSubstitutes(
            tester,
            'best-use-balance-$background-${view.size.width.toInt()}-text${view.scale.toInt()}',
          );
          if (view.size.width == 1200 && background == 'sakura-night-garden') {
            await _captureSubstitutes(
              tester,
              'best-use-balance-card-sakura',
              region: find.byKey(const ValueKey('craft-card:Aloe Yogurt')),
            );
          }
        }
        expect(fixture.requests, requests);
        expect(fixture.controller.bestUseQuotes, same(quotes));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  _glassTestWidgets('best use balance long name and large preorder stock', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1000, 940));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(
        exchange: false,
        backgroundId: 'sakura-night-garden',
        seedNonMarketPrices: false,
        missingStock: true,
        buyerCount: 123456789,
      ),
    ))!;
    try {
      final controller = fixture.controller;
      controller.change((p) {
        p.section = 'best-use';
        p.profitableOnly = false;
        p.demandOnly = false;
        p.readyOnly = false;
      });
      controller.selectBestUseItem('Frenzy Draught of Corruption');
      await _settleCalculation(tester, controller);
      await _settleWork(tester, controller.refresh());
      await _settleWork(
        tester,
        controller.ensureMarketDepth(controller.market.items.keys),
      );
      await _settleCalculation(tester, controller);
      await tester.pumpWidget(_host(controller));
      await _settleImages(tester);
      const name = 'Immortal: Frenzy Draught of Corruption';
      final card = find.byKey(const ValueKey('craft-card:$name'));
      expect(card, findsOneWidget);
      for (final view in [
        (size: const Size(1000, 940), scale: 1.0),
        (size: const Size(840, 940), scale: 1.0),
        (size: const Size(900, 1100), scale: 2.0),
      ]) {
        configureApplicationTestSurface(
          tester,
          view.size,
          textScaleFactor: view.scale,
        );
        await _settleImages(tester);
        _expectBalancedBestUseCard(tester, name);
        final title = find.descendant(of: card, matching: find.text(name));
        expect(
          tester.getSize(title).width,
          greaterThanOrEqualTo(150 * view.scale),
          reason:
              'A large stock count must not squeeze the title into fragments.',
        );
        if (view.scale == 1) {
          expect(tester.getSize(card).height, lessThanOrEqualTo(320));
        }
        expect(
          find.descendant(of: card, matching: find.text('Stock −123.456.789')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _captureSubstitutes(
          tester,
          'best-use-balance-long-preorders-${view.size.width.toInt()}-text${view.scale.toInt()}',
          region: card,
        );
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    }
  });

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    _glassTestWidgets('best use clarity Aloe layout $background', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1200, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          backgroundId: background,
          seedNonMarketPrices: false,
          pricesByName: const {'Aloe': 1100, 'Aloe Yogurt': 32000},
        ),
      ))!;
      final controller = fixture.controller;
      try {
        await _prepareAloeBestUse(tester, fixture);
        await tester.pumpWidget(_host(controller));
        await _settleImages(tester);
        final card = find.byKey(const ValueKey('craft-card:Aloe Yogurt'));
        expect(card, findsOneWidget);
        for (final key in [
          'best-use-output-strip:Aloe Yogurt',
          'best-use-equation:Aloe Yogurt',
          'best-use-sale:Aloe Yogurt',
          'best-use-ingredients:Aloe Yogurt',
          'best-use-profit:Aloe Yogurt',
          'best-use-stock:Aloe Yogurt',
          'best-use-calculation:Aloe Yogurt',
        ]) {
          expect(
            find.descendant(of: card, matching: find.byKey(ValueKey(key))),
            findsOneWidget,
          );
        }
        expect(find.text('Other costs / item'), findsNothing);
        String readoutText(String key) => tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(Text),
                  )
                  .last,
            )
            .data!;
        final use = controller.visibleBestUseQuotes.firstWhere(
          (row) => row.recipe.name == 'Aloe Yogurt',
        );
        final quote = use.quote;
        final sale = quote.listingRevenue == null
            ? null
            : quote.listingRevenue! / quote.crafts;
        final ingredients =
            quote.totalCost == null ||
                (quote.usesInventory && quote.ownedIngredientSales == null)
            ? null
            : (quote.totalCost! +
                      (quote.usesInventory ? quote.ownedIngredientSales! : 0)) /
                  quote.crafts;
        final profit = quote.profitFor(OpportunitySaleMode.listing) == null
            ? null
            : quote.profitFor(OpportunitySaleMode.listing)! / quote.crafts;
        String silver(num? value, {bool signed = false}) => value == null
            ? '—'
            : '${signed && value > 0 ? '+' : ''}${formatCompactOpportunitySilver(value)}';
        expect(readoutText('best-use-sale:Aloe Yogurt'), silver(sale));
        expect(
          readoutText('best-use-ingredients:Aloe Yogurt'),
          silver(ingredients),
        );
        expect(
          readoutText('best-use-profit:Aloe Yogurt'),
          silver(profit, signed: true),
        );
        expect(find.textContaining('Makes ~'), findsWidgets);
        await tester.tap(
          find.byKey(const ValueKey('best-use-calculation:Aloe Yogurt')),
        );
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('best-use-inline-calculation:Aloe Yogurt')),
          findsOneWidget,
        );
        expect(find.text('Average output'), findsOneWidget);
        expect(find.text('Profit per craft'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('best-use-calculation:Aloe Yogurt')),
        );
        await _settleImages(tester);
        await _captureSubstitutes(
          tester,
          'best-use-clarity-cards-$background-1200',
        );
        await _openCalculation(tester, 'Aloe Yogurt');
        await _settleDepth(tester, controller);
        await _settleImages(tester);
        final summary = find.byKey(const ValueKey('best-use-detail-summary'));
        expect(summary, findsOneWidget);
        expect(
          find.byKey(const ValueKey('best-use-profit-loss')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('best-use-raw-sale')), findsOneWidget);
        expect(
          find.descendant(
            of: summary,
            matching: find.text('Per 1 Aloe · after tax'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('craft-money-summary')), findsNothing);
        expect(
          find.byKey(const ValueKey('raw-ingredient-sales')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('opportunity-recipe-controls')),
          findsOneWidget,
        );
        final aloe = find.byKey(
          const ValueKey('opportunity-item:ingredient:Aloe'),
        );
        expect(
          find.descendant(of: aloe, matching: find.text('Raw sale')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: aloe, matching: find.text('Cost')),
          findsNothing,
        );
        final iconBounds = tester.getRect(
          find.descendant(of: aloe, matching: find.byType(ModeItemIcon)),
        );
        final amountBounds = tester.getRect(
          find.descendant(
            of: aloe,
            matching: find.byKey(const ValueKey('inventory-amount-button')),
          ),
        );
        expect(amountBounds.center.dx, closeTo(iconBounds.center.dx, .01));
        expect(amountBounds.top, greaterThanOrEqualTo(iconBounds.bottom));
        expect(
          find.descendant(of: summary, matching: find.byType(Tooltip)),
          findsNothing,
        );
        final requests = List<String>.of(fixture.requests);
        for (final view in [
          (size: const Size(1200, 900), scale: 1.0),
          (size: const Size(1500, 940), scale: 1.0),
          (size: const Size(900, 1100), scale: 2.0),
        ]) {
          configureApplicationTestSurface(
            tester,
            view.size,
            textScaleFactor: view.scale,
          );
          await _settleImages(tester);
          expect(tester.getSize(summary).width, lessThanOrEqualTo(968));
          expect(tester.takeException(), isNull);
          await _captureSubstitutes(
            tester,
            'best-use-clarity-detail-$background-${view.size.width.toInt()}-text${view.scale.toInt()}',
            region: find.byType(Dialog),
          );
        }
        expect(
          fixture.requests,
          requests,
          reason: 'Resizing comparison only paints the existing quote.',
        );
        configureApplicationTestSurface(tester, const Size(1200, 900));
        await _settleImages(tester);
        await tester.tap(find.byKey(const ValueKey('best-use-batch-totals')));
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('best-use-total-sale')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('best-use-total-other-cost')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('best-use-total-raw-sale')),
          findsOneWidget,
        );
        await _captureSubstitutes(
          tester,
          'best-use-clarity-totals-$background',
          region: find.byType(Dialog),
        );
        await tester.tap(find.byKey(const ValueKey('craft-market-details')));
        await _settleImages(tester);
        expect(find.text('Market details'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settleImages(tester);
        expect(summary, findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  _glassTestWidgets(
    'best use clarity recomputes current crafts and sale price',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 1000));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          seedNonMarketPrices: false,
          pricesByName: const {'Aloe': 1100, 'Aloe Cookie': 32000},
        ),
      ))!;
      final controller = fixture.controller;
      final targets = {
        for (final entry in controller.appController.modes.entries)
          entry.key: entry.value.state.value.target,
      };
      try {
        await _prepareAloeBestUse(tester, fixture);
        await tester.pumpWidget(_host(controller));
        await _settleImages(tester);
        final use = controller.visibleBestUseQuotes.firstWhere(
          (row) => row.recipe.name == 'Aloe Cookie',
        );
        await _openCalculation(tester, 'Aloe Cookie');
        await _settleDepth(tester, controller);
        await _settleImages(tester);
        await tester.enterText(_detailCraftCount(), '3');
        await tester.enterText(
          _inlineNumber('opportunity-custom-sale-price'),
          '54000',
        );
        await _settleImages(tester);
        final inspection = controller.inspectRecipe(
          recipe: use.recipe,
          selectedVariantId: use.quote.selectedVariantId,
          crafts: 3,
          ingredientChoices: use.ingredientChoices,
          customSalePrice: 54000,
          useInventory: false,
        );
        final expected = calculateOpportunityBestUseComparison(
          quote: inspection.quote,
          itemName: use.itemName,
          selectedItemId: use.selectedItemId,
          marketTax: controller.appController.marketTax.value,
          now: controller.clock(),
          maxMarketAge: controller.cachedMarketMaxAge,
        )!;
        for (final entry in {
          'best-use-profit-loss': expected.profitLossPerUnit,
          'best-use-raw-sale': expected.rawSalePerUnit,
          'best-use-craft-return': expected.craftingReturnPerUnit,
        }.entries) {
          expect(
            _bestUseReadout(tester, entry.key).value,
            closeTo(entry.value!, .000001),
          );
        }
        expect(_bestUseReadout(tester, 'best-use-raw-sale').estimated, isFalse);
        await tester.tap(find.byKey(const ValueKey('best-use-batch-totals')));
        await _settleImages(tester);
        expect(
          _bestUseReadout(tester, 'best-use-total-raw-sale').value,
          expected.rawIngredientSale,
        );
        expect(
          _bestUseReadout(tester, 'best-use-total-sale').estimated,
          isFalse,
        );
        expect(find.text('Batch totals · 3 crafts'), findsOneWidget);
        final dough = inspection.quote.ingredients
            .firstWhere((input) => input.name.contains('Dough'))
            .name;
        await _openIngredient(tester, dough);
        expect(
          find.byKey(const ValueKey('best-use-detail-summary')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('craft-money-summary')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('best-use-detail-summary')),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(_detailCraftCount()).controller!.text,
          '3',
        );
        expect(
          _bestUseReadout(tester, 'best-use-profit-loss').value,
          closeTo(expected.profitLossPerUnit!, .000001),
        );
        expect({
          for (final entry in controller.appController.modes.entries)
            entry.key: entry.value.state.value.target,
        }, targets);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'best use clarity keeps known returns when raw price is unavailable',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          seedNonMarketPrices: false,
          unavailableNames: const {'Aloe'},
        ),
      ))!;
      try {
        await _prepareAloeBestUse(tester, fixture);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Aloe Yogurt');
        await _settleDepth(tester, fixture.controller);
        await _settleImages(tester);
        expect(_bestUseReadout(tester, 'best-use-profit-loss').value, isNull);
        expect(_bestUseReadout(tester, 'best-use-raw-sale').value, isNull);
        expect(
          _bestUseReadout(tester, 'best-use-craft-return').value,
          isNotNull,
        );
        expect(find.byKey(const ValueKey('craft-money-summary')), findsNothing);
        await _captureSubstitutes(
          tester,
          'best-use-clarity-unknown-raw',
          region: find.byType(Dialog),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    _glassTestWidgets(
      'icon-only Crafting and Best use card hover $background',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1500, 1000));
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, backgroundId: background),
        ))!;
        try {
          final controller = fixture.controller;
          controller.change((p) => p.craftSearch = 'Beer');
          await _settleCalculation(tester, controller);
          await tester.pumpWidget(_host(controller));
          await _settleImages(tester);
          for (final bestUse in [false, true]) {
            if (bestUse) {
              controller.change((p) {
                p.section = 'best-use';
                p.profitableOnly = false;
                p.demandOnly = false;
                p.readyOnly = false;
              });
              controller.selectBestUseItem('Trace of Nature');
              await _settleCalculation(tester, controller);
              await _settleWork(tester, controller.refresh());
              await _settleCalculation(tester, controller);
              await _settleImages(tester);
              expect(controller.visibleBestUseQuotes, isNotEmpty);
            }
            final name = bestUse
                ? controller.visibleBestUseQuotes.first.recipe.name
                : 'Beer';
            final card = find.byKey(ValueKey('craft-card:$name'));
            await tester.ensureVisible(card);
            await _settleImages(tester);
            final icon = find.descendant(
              of: bestUse
                  ? find.byKey(ValueKey('craft-artwork-rail:$name'))
                  : card,
              matching: find.byType(RecipeBookItemInfoHover),
            );
            final nameLabel = find.descendant(
              of: card,
              matching: find.text(name),
            );
            final details = bestUse
                ? find.descendant(
                    of: card,
                    matching: find.byWidgetPredicate(
                      (w) =>
                          w is AppButton &&
                          w.semanticLabel == 'Show calculation for $name',
                    ),
                  )
                : find.byKey(ValueKey('craft-expand-button:$name'));
            await _expectIconOnlyCardHover(
              tester,
              fixture,
              card: card,
              icon: icon,
              name: name,
              probes: [
                nameLabel,
                find.descendant(
                  of: card,
                  matching: find.text(bestUse ? 'Profit' : 'Sell ingredients'),
                ),
                bestUse
                    ? find.descendant(
                        of: card,
                        matching: find.textContaining('Stock '),
                      )
                    : find.byKey(ValueKey('craft-market-counts:$name')),
                if (bestUse) find.byKey(ValueKey('best-use-equation:$name')),
                details,
              ],
            );
            await _openCalculation(tester, name);
            await _settleDepth(tester, controller);
            await _settleImages(tester);
            expect(
              find.byKey(const ValueKey('root-recipe-page')),
              findsOneWidget,
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _settleImages(tester);
            expect(find.byType(Dialog), findsNothing);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );

    _glassTestWidgets('icon-only Exchange card hover $background', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1500, 1000));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: true, backgroundId: background),
      ))!;
      try {
        final controller = fixture.controller;
        controller.change((p) => p.currencyId = 'seal-of-solare');
        await _settleWork(tester, controller.refresh());
        await _settleCalculation(tester, controller);
        await tester.pumpWidget(_host(controller));
        await _settleImages(tester);
        const name = 'Perfume of Courage';
        final details = find.byWidgetPredicate(
          (w) =>
              w is AppButton && w.semanticLabel == 'Exchange details for $name',
        );
        await tester.scrollUntilVisible(
          details,
          300,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('exchange-seal-of-solare')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _settleImages(tester);
        final card = find
            .ancestor(of: details, matching: find.byType(OpportunitySurface))
            .first;
        final icon = find.descendant(
          of: card,
          matching: find.byKey(
            const ValueKey('opportunity-item:exchange-icon:734'),
          ),
        );
        final rewardName = find.descendant(
          of: card,
          matching: find.byKey(
            const ValueKey('opportunity-item:exchange-name:734'),
          ),
        );
        final currencyName = find.descendant(
          of: card,
          matching: find.byKey(
            ValueKey(
              'opportunity-item:exchange-name:${controller.currency.item.id}',
            ),
          ),
        );
        final stock = find.descendant(
          of: card,
          matching: find.textContaining('Stock '),
        );
        await _expectIconOnlyCardHover(
          tester,
          fixture,
          card: card,
          icon: icon,
          name: name,
          probes: [
            rewardName,
            currencyName,
            find.descendant(of: card, matching: find.text('Value')),
            find.descendant(of: card, matching: find.text('Per seal')),
            stock,
            details,
          ],
        );
        final stockSemantics = find.ancestor(
          of: stock,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label?.contains('Preorders:') ?? false),
          ),
        );
        expect(stockSemantics, findsOneWidget);
        expect(
          tester.widget<Semantics>(stockSemantics).properties.label,
          contains('Stock:'),
        );
        await tester.tap(icon);
        await _settleImages(tester);
        expect(find.byType(ItemReferenceCard), findsOneWidget);
        expect(find.text('Give'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settleImages(tester);
        await tester.tap(details);
        await _settleDepth(tester, controller);
        await _settleImages(tester);
        expect(find.text('Give'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });

    _glassTestWidgets('icon-only ingredient and title hover $background', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1500, 1000));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          backgroundId: background,
          seedNonMarketPrices: false,
          stocksByName: const {'Vinegar': 0},
        ),
      ))!;
      try {
        final controller = fixture.controller;
        controller.change((p) => p.craftSearch = 'Pickled Fish');
        await _settleCalculation(tester, controller);
        await tester.pumpWidget(_host(controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Pickled Fish');
        await _settleDepth(tester, controller);
        await _settleImages(tester);
        final grid = find.byKey(const ValueKey('craft-ingredient-grid'));
        final vinegar = find.byKey(
          const ValueKey('opportunity-item:ingredient:Vinegar'),
        );
        final icon = find.descendant(
          of: vinegar,
          matching: find.byType(RecipeBookItemInfoHover),
        );
        final amount = find.descendant(
          of: vinegar,
          matching: find.byKey(const ValueKey('inventory-amount-button')),
        );
        final substitutes = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'ingredient-substitutes:',
              ),
        );
        await _expectIconOnlyCardHover(
          tester,
          fixture,
          card: grid,
          icon: icon,
          name: 'Vinegar',
          probes: [
            find.descendant(of: vinegar, matching: find.text('Vinegar')),
            find.byKey(const ValueKey('ingredient-quantity:Vinegar')),
            find.byKey(const ValueKey('ingredient-stock:Vinegar')),
            find
                .descendant(
                  of: vinegar,
                  matching: find.byType(OpportunitySilverAmount),
                )
                .first,
            amount,
            substitutes.first,
          ],
        );
        final summary = find.byKey(const ValueKey('craft-money-summary'));
        final marketDetails = find.descendant(
          of: summary,
          matching: find.byKey(const ValueKey('craft-market-details')),
        );
        expect(find.bySemanticsLabel('Market details'), findsOneWidget);
        await tester.tap(marketDetails);
        await _settleDepth(tester, controller);
        await _settleImages(tester);
        expect(find.byType(Dialog), findsNWidgets(2));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settleImages(tester);
        await tester.tap(amount);
        await tester.pump();
        final field = find.descendant(
          of: vinegar,
          matching: find.byType(TextField),
        );
        expect(field, findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('ingredient-recipe-Vinegar')),
        );
        await _settleDepth(tester, controller);
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-page')),
          findsOneWidget,
        );
        final titleIcon = find
            .byWidgetPredicate(
              (w) => w is RecipeBookItemInfoHover && w.name == 'Vinegar',
            )
            .last;
        final artwork = find.descendant(
          of: titleIcon,
          matching: find.byType(ModeItemIcon),
        );
        final inner = tester.getRect(titleIcon);
        expect(
          inner,
          tester.getRect(artwork),
          reason:
              'The trigger must match the artwork, not surrounding title spacing.',
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        await mouse.moveTo(Offset(inner.right + 3, inner.center.dy));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(ItemReferenceCard), findsNothing);
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    for (final scale in [1.0, 2.0]) {
      _glassTestWidgets(
        'exchange balance label stays outside every rim $background $scale',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            scale == 1 ? const Size(1280, 820) : const Size(900, 820),
            textScaleFactor: scale,
          );
          final fixture = (await tester.runAsync(
            () => _Fixture.create(exchange: true, backgroundId: background),
          ))!;
          final controller = fixture.controller;
          controller.change((p) => p.owned[controller.currency.id] = 0);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          try {
            await tester.pumpWidget(_host(controller));
            await _settleImages(tester);
            final owner = find.byKey(const ValueKey('You have'));
            final input = find.descendant(
              of: owner,
              matching: find.byType(TextField),
            );
            final label = find.descendant(
              of: owner,
              matching: find.text('You have'),
            );
            void checkGeometry() {
              expect(input, findsOneWidget);
              expect(label, findsOneWidget);
              expect(
                tester.widget<TextField>(input).decoration!.labelText,
                isNull,
              );
              expect(
                tester.getRect(label).bottom + 5,
                lessThanOrEqualTo(tester.getRect(input).top + .01),
              );
              final editable = tester
                  .state<EditableTextState>(
                    find.descendant(
                      of: input,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .renderEditable;
              expect(
                editable.maxScrollExtent,
                lessThanOrEqualTo(.1),
                reason: 'The entire legal balance fits at this text size.',
              );
              expect(tester.takeException(), isNull);
            }

            Future<void> capture(String state) => _captureSubstitutes(
              tester,
              '$background-$scale-balance-$state',
              region: find.byKey(const ValueKey('exchange-toolbar')),
            );
            checkGeometry();
            final initial = tester.getRect(owner);
            await capture('idle');
            await mouse.addPointer(location: const Offset(1, 1));
            await mouse.moveTo(tester.getCenter(input));
            await tester.pump(const Duration(milliseconds: 220));
            checkGeometry();
            expect(tester.getRect(owner), initial);
            await capture('hover');
            tester.widget<TextField>(input).focusNode!.requestFocus();
            await tester.pump(const Duration(milliseconds: 220));
            await tester.enterText(input, '1000000000');
            await tester.pump(const Duration(milliseconds: 220));
            expect(controller.owned, 1000000000);
            checkGeometry();
            expect(tester.getRect(owner), initial);
            await capture('focused');
            await tester.enterText(input, '1000000001');
            await tester.pump();
            expect(controller.owned, 1000000000);
            expect(find.text('Use 0–1.000.000.000'), findsOneWidget);
            tester.widget<TextField>(input).focusNode!.unfocus();
            await tester.pump(const Duration(milliseconds: 220));
            expect(
              tester.widget<TextField>(input).controller!.text,
              '1000000000',
            );
            expect(find.text('Use 0–1.000.000.000'), findsNothing);
            final focus = tester.widget<TextField>(input).focusNode;
            tester.view.physicalSize = scale == 1
                ? const Size(900, 820)
                : const Size(1200, 820);
            await tester.pump(const Duration(milliseconds: 220));
            checkGeometry();
            expect(tester.widget<TextField>(input).focusNode, same(focus));
            expect(controller.owned, 1000000000);
            await capture('resized');
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox.shrink());
            await _settleWork(tester, fixture.dispose());
          }
        },
      );
    }
  }

  // The independent Beta by Codex experiment deliberately changes geometry.
  // Real production data and callback contracts stay behind these captures.
  for (final view in [
    (
      name: 'crafting_sakura',
      size: const Size(1500, 940),
      scale: 1.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'crafting_ledger',
      size: const Size(1280, 820),
      scale: 1.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'crafting_greenhouse',
      size: const Size(1500, 940),
      scale: 1.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'crafting_1280',
      size: const Size(1280, 820),
      scale: 1.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'crafting_1500',
      size: const Size(1500, 940),
      scale: 1.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'crafting_900',
      size: const Size(900, 700),
      scale: 1.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'crafting_900_large',
      size: const Size(900, 700),
      scale: 2.0,
      section: 'crafting',
      detail: false,
    ),
    (
      name: 'exchanges_1280',
      size: const Size(1280, 820),
      scale: 1.0,
      section: 'exchanges',
      detail: false,
    ),
    (
      name: 'exchanges_900_large',
      size: const Size(900, 700),
      scale: 2.0,
      section: 'exchanges',
      detail: false,
    ),
    (
      name: 'best_use_1280',
      size: const Size(1280, 820),
      scale: 1.0,
      section: 'best-use',
      detail: false,
    ),
    (
      name: 'recipe_1280',
      size: const Size(1280, 820),
      scale: 1.0,
      section: 'crafting',
      detail: true,
    ),
    (
      name: 'recipe_900_large',
      size: const Size(900, 700),
      scale: 1.3,
      section: 'crafting',
      detail: true,
    ),
  ]) {
    _glassTestWidgets('Codex workbench ${view.name}', (tester) async {
      configureApplicationTestSurface(
        tester,
        view.size,
        textScaleFactor: view.scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: view.section == 'exchanges',
          seedNonMarketPrices: false,
        ),
      ))!;
      try {
        if (view.section == 'best-use') {
          fixture.controller.change((p) => p.section = 'best-use');
          fixture.controller.selectBestUseItem('Trace of Nature');
          await _settleCalculation(tester, fixture.controller);
          await _settleWork(tester, fixture.controller.refresh());
          await _settleCalculation(tester, fixture.controller);
          expect(fixture.controller.visibleBestUseQuotes, isNotEmpty);
        }
        if (view.detail) {
          fixture.controller.change((p) => p.craftSearch = 'Pickled Fish');
          await _settleCalculation(tester, fixture.controller);
        }
        await tester.pumpWidget(
          _host(
            fixture.controller,
            theme:
                view.name == 'crafting_ledger' ||
                    view.name == 'crafting_sakura' ||
                    view.name == 'crafting_greenhouse'
                ? ValueNotifier(
                    applicationThemeForAppearance(
                      _appearanceSettings(
                        background: switch (view.name) {
                          'crafting_ledger' => 'illuminated-ledger',
                          'crafting_greenhouse' => 'greenhouse',
                          _ => 'sakura-night-garden',
                        },
                      ),
                    ),
                  )
                : null,
          ),
        );
        await _settleImages(tester);
        if (view.detail) await _openCalculation(tester, 'Pickled Fish');
        expect(tester.takeException(), isNull);
        if (!view.detail) _expectWorkbenchGeometry(tester);
        if (!view.detail && view.section == 'crafting') {
          expect(fixture.controller.quotes.length, greaterThan(100));
          final cards = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('craft-card:'),
          );
          expect(
            cards.evaluate().length,
            lessThan(35),
            reason: 'Only the viewport is built.',
          );
          if (view.scale == 1) {
            final first = tester.getRect(cards.first);
            expect(first.height, lessThan(200));
            expect(first.top, lessThan(310));
            if (view.size.width >= 1280) {
              _expectCraftCardLayout(
                tester,
                expectedColumns: view.size.width >= 1500 ? 4 : 3,
              );
              final header = tester.getRect(
                find.byKey(const ValueKey('opportunities-header')),
              );
              expect(header.height, closeTo(40, 1));
            }
          }
        }
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/codex_${view.name}.png'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    }, skip: !Platform.isWindows);
  }

  _glassTestWidgets(
    'Codex workbench retains search across rail breakpoint resize',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final field = find.descendant(
          of: find.byKey(const ValueKey('craft-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'Beer');
        await _settleCalculation(tester, fixture.controller);
        final editor = tester.widget<TextField>(field).controller;
        final element = tester.element(field);
        for (final size in [
          const Size(900, 700),
          const Size(1500, 940),
          const Size(1280, 820),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          _expectWorkbenchGeometry(tester);
          expect(tester.element(field), same(element));
          expect(tester.widget<TextField>(field).controller, same(editor));
          expect(editor!.text, 'Beer');
          expect(_focusIsWithin(tester, field), isTrue);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets('Codex workbench exchange chooser $scale', (
      tester,
    ) async {
      configureApplicationTestSurface(
        tester,
        const Size(900, 700),
        textScaleFactor: scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: true),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await tester.tap(find.byKey(const ValueKey('exchange-choose-item')));
        await tester.pumpAndSettle();
        final search = find.descendant(
          of: find.byKey(const ValueKey('exchange-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'delicacy');
        await tester.pumpAndSettle();
        await _settleImages(tester);
        final choice = find.byKey(
          const ValueKey('exchange-currency-witchs-delicacy'),
        );
        expect(choice, findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile(
            'goldens/codex_exchange_picker_${scale.toInt()}.png',
          ),
        );
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(fixture.controller.currency.id, 'witchs-delicacy');
        expect(search, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    }, skip: !Platform.isWindows);
  }

  for (final finish in ['moon', 'bronze']) {
    for (final scenario in [
      (
        name: 'listed',
        stock: 123,
        buyers: 1290,
        summary: false,
        age: 0,
        scale: 1.0,
      ),
      (
        name: 'preorders',
        stock: 0,
        buyers: 1290,
        summary: false,
        age: 0,
        scale: 1.0,
      ),
      (name: 'empty', stock: 0, buyers: 0, summary: false, age: 0, scale: 1.0),
      (
        name: 'unchecked orders',
        stock: 0,
        buyers: 1290,
        summary: true,
        age: 0,
        scale: 1.0,
      ),
      (
        name: 'stale',
        stock: 0,
        buyers: 1290,
        summary: false,
        age: 4,
        scale: 1.0,
      ),
      (
        name: 'large preorders',
        stock: 0,
        buyers: 123456789,
        summary: false,
        age: 0,
        scale: 2.0,
      ),
    ]) {
      _glassTestWidgets('shared stock badges $finish ${scenario.name}', (
        tester,
      ) async {
        configureApplicationTestSurface(
          tester,
          const Size(1200, 940),
          textScaleFactor: scenario.scale,
        );
        var now = DateTime.utc(2026, 9, 8, 16);
        final fixture = (await tester.runAsync(
          () => _Fixture.create(
            exchange: false,
            seedNonMarketPrices: false,
            clock: () => now,
            summaryOnly: scenario.summary,
            stocksByName: {
              'Pickled Fish': scenario.stock,
              'Vinegar': scenario.stock,
            },
            preordersByName: {
              for (final name in ['Pickled Fish', 'Vinegar'])
                name: [
                  OpportunityMarketLevel(
                    price: 1000,
                    quantity: scenario.buyers ~/ 2,
                  ),
                  OpportunityMarketLevel(
                    price: 1100,
                    quantity: scenario.buyers - scenario.buyers ~/ 2,
                  ),
                ],
            },
          ),
        ))!;
        try {
          final controller = fixture.controller;
          controller.cancel();
          now = now.add(Duration(hours: scenario.age));
          controller.change((p) {
            p.craftSearch = 'Pickled Fish';
            p.glassFinish = finish;
          });
          await _settleCalculation(tester, controller);
          await tester.pumpWidget(_host(controller));
          await _settleImages(tester);
          final text = scenario.age > 0
              ? 'Stock —'
              : scenario.stock > 0
              ? 'Stock ${formatQuantity(scenario.stock.toDouble())}'
              : scenario.summary || scenario.buyers == 0
              ? 'Stock 0'
              : 'Stock −${formatQuantity(scenario.buyers.toDouble())}';
          final card = find.byKey(const ValueKey('craft-card:Pickled Fish'));
          final cardStock = find.descendant(
            of: card,
            matching: find.text(text.replaceFirst('Stock −', 'Preorders ')),
          );
          expect(cardStock, findsOneWidget);
          final cardStyle = tester.widget<Text>(cardStock).style!;
          expect(cardStyle.fontSize, 12);
          final cardSpec = tester.element(card).visualTheme;
          expect(
            cardStyle.color,
            OpportunityCraftCardMaterial.forSpec(
              cardSpec,
              scenario.age > 0
                  ? OpportunityStockTone.unknown
                  : scenario.stock == 0
                  ? OpportunityStockTone.outOfStock
                  : scenario.summary || scenario.buyers == 0
                  ? OpportunityStockTone.available
                  : OpportunityStockTone.mixed,
            ).badgeInk,
          );
          await _openCalculation(tester, 'Pickled Fish');
          final summary = find.byKey(const ValueKey('craft-money-summary'));
          final summaryStock = find.descendant(
            of: summary,
            matching: find.text(text),
          );
          expect(summaryStock, findsOneWidget);
          final summaryStyle = tester.widget<Text>(summaryStock).style!;
          expect(summaryStyle.fontSize, 16);
          expect(summaryStyle.fontWeight, FontWeight.w700);
          final spec = tester.element(summaryStock).visualTheme;
          expect(
            summaryStyle.color,
            OpportunitiesVisualSpec.readableValueColor(
              spec,
              scenario.age > 0 || scenario.summary || scenario.buyers == 0
                  ? spec.palette.textMuted
                  : scenario.stock > 0
                  ? spec.palette.success
                  : spec.palette.danger,
            ),
          );
          final marketDetails = find.byKey(
            const ValueKey('craft-market-details'),
          );
          expect(marketDetails, findsOneWidget);
          // The compact badge retains the existing market-depth action.
          await tester.ensureVisible(marketDetails);
          await tester.tap(marketDetails);
          await _settleImages(tester);
          expect(find.text('Market details'), findsWidgets);
          await tester.tap(
            find
                .byWidgetPredicate(
                  (w) => w is AppButton && w.semanticLabel == 'Close',
                )
                .hitTestable()
                .last,
          );
          await _settleImages(tester);
          final ingredient = find.byKey(
            const ValueKey('ingredient-stock:Vinegar'),
          );
          await tester.ensureVisible(ingredient);
          await _settleImages(tester);
          expect(tester.widget<Text>(ingredient).data, text);
          expect(tester.widget<Text>(ingredient).style?.fontSize, 16);
          expect(
            tester.widget<Text>(ingredient).style?.fontWeight,
            FontWeight.w700,
          );
          BoxDecoration badgeDecoration(Finder label) =>
              tester
                      .widget<DecoratedBox>(
                        find
                            .ancestor(
                              of: label,
                              matching: find.byKey(
                                const ValueKey('market-stock-badge'),
                              ),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          expect(
            badgeDecoration(ingredient).borderRadius,
            badgeDecoration(summaryStock).borderRadius,
          );
          if (scenario.stock > 0 ||
              (!scenario.summary && scenario.buyers > 0) ||
              scenario.age > 0) {
            expect(badgeDecoration(ingredient), badgeDecoration(summaryStock));
          }
          for (final npc in ['Salt', 'Leavening Agent']) {
            expect(find.byKey(ValueKey('ingredient-stock:$npc')), findsNothing);
          }
          if (scenario.scale == 2) {
            final value = tester.widget<Text>(ingredient).data!;
            final paragraph = tester.renderObject<RenderParagraph>(ingredient);
            expect(
              paragraph.getBoxesForSelection(
                TextSelection(
                  baseOffset: value.indexOf('−'),
                  extentOffset: value.length,
                ),
              ),
              hasLength(1),
              reason: 'Do not split preorder digits at enlarged text.',
            );
          }
          if (scenario.name == 'preorders') {
            await _captureSubstitutes(
              tester,
              'stock-badges-$finish',
              region: find.byType(Dialog),
            );
          }
          if (scenario.summary) {
            await _settleWork(
              tester,
              controller.ensureMarketDepth([
                controller.catalog.bundledMarketId('Pickled Fish')!,
                controller.catalog.bundledMarketId('Vinegar')!,
              ], forceRefresh: true),
            );
            await _settleCalculation(tester, controller);
            await _settleImages(tester);
            expect(
              find.descendant(of: summary, matching: find.text('Stock −1.290')),
              findsOneWidget,
            );
            expect(
              tester.widget<Text>(ingredient).data,
              'Stock −1.290',
              reason:
                  'Open details update when the checked preorder receipt arrives.',
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      });
    }
  }

  _glassTestWidgets('shared stock badges in substitute and split choices', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 940));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(
        exchange: false,
        stocksByName: const {'Wheat': 0, 'Barley': 0},
        buyerCount: 1234,
      ),
    ))!;
    try {
      fixture.harness.bundle.controller.modes[CraftMode.cooking]!.updateState(
        (state) => state.copyWith(
          recipeEdits: {
            ...state.recipeEdits,
            'Beer': RecipeState(
              type: 'cooking',
              marketId: fixture.controller.catalog.bundledMarketId('Beer'),
              ingredients: [
                IngredientState(
                  name: 'Wheat',
                  quantity: 5,
                  options: const ['Wheat', 'Barley'],
                ),
              ],
            ),
          },
        ),
      );
      fixture.controller.preferences.craftSearch = 'Beer';
      fixture.controller.recalculate();
      await _settleCalculation(tester, fixture.controller);
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, 'Beer');
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'ingredient-substitutes:',
              ),
        ),
      );
      await _settleImages(tester);
      for (final split in [false, true]) {
        if (split) {
          await tester.tap(find.text('Split batch'));
          await _settleImages(tester);
        }
        for (final name in ['Wheat', 'Barley']) {
          final row = find.byKey(ValueKey('substitute-option:$name'));
          final badge = find.descendant(
            of: row,
            matching: find.byKey(const ValueKey('market-stock-badge')),
          );
          expect(badge, findsOneWidget);
          final text = find.descendant(
            of: badge,
            matching: find.text('Stock −1.234'),
          );
          expect(text, findsOneWidget);
          expect(
            tester.widget<Text>(text).style?.color,
            OpportunitiesVisualSpec.readableValueColor(
              tester.element(text).visualTheme,
              tester.element(text).visualTheme.palette.danger,
            ),
          );
          expect(
            find.descendant(of: row, matching: find.text('Fill remaining')),
            findsNothing,
            reason: 'Preorders must not be treated as available stock.',
          );
        }
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    }
  });

  _glassTestWidgets(
    'Frenzy best use shows NPC and preorder costs without notices',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          seedNonMarketPrices: false,
          pricesByName: const {
            'Frenzy Draught': 2240000,
            'Abyssal Essence': 560000,
            'Elixir of Frenzy': 228000,
            'Elixir of Demihuman Hunt': 19400,
          },
          stocksByName: const {
            'Frenzy Draught': 959,
            'Elixir of Demihuman Hunt': 0,
          },
          preordersByName: const {
            'Elixir of Demihuman Hunt': [
              OpportunityMarketLevel(price: 20800, quantity: 91),
            ],
          },
        ),
      ))!;
      try {
        fixture.controller.change((p) {
          p.section = 'best-use';
          p.glassFinish = 'moon';
        });
        fixture.controller.selectBestUseItem('Abyssal Essence');
        await _settleCalculation(tester, fixture.controller);
        await _settleWork(tester, fixture.controller.refresh());
        await _settleWork(
          tester,
          fixture.controller.ensureMarketDepth(
            fixture.controller.market.items.keys,
          ),
        );
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final use = fixture.controller.bestUseQuotes.singleWhere(
          (use) => use.recipe.name == 'Frenzy Draught',
        );
        expect(use.otherInputCost, isNotNull);
        expect(use.extraProfitPerUnit, isNotNull);
        final card = find.byKey(const ValueKey('craft-card:Frenzy Draught'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('—')),
          findsNothing,
        );
        expect(find.text('Some prices are missing'), findsNothing);
        await _captureSubstitutes(tester, 'frenzy-best-use-fixed');
        await _openCalculation(tester, 'Frenzy Draught');
        await _settleImages(tester);
        await tester.tap(find.byKey(const ValueKey('best-use-batch-totals')));
        await _settleImages(tester);
        expect(
          _bestUseReadout(tester, 'best-use-total-other-cost').value,
          use.otherInputCost,
        );
        final tears = find.byKey(
          const ValueKey(
            'opportunity-item:ingredient:Tears of the Falling Moon',
          ),
        );
        await tester.ensureVisible(tears);
        await _settleImages(tester);
        expect(
          find.descendant(of: tears, matching: find.text('NPC each')),
          findsOneWidget,
        );
        expect(
          find.text('Some ingredients are not sold on the market'),
          findsNothing,
        );
        expect(find.text('Some prices are missing'), findsNothing);
        expect(
          fixture.requests.where((request) => request.endsWith(':4925')),
          isEmpty,
        );
        await _captureSubstitutes(tester, 'frenzy-details-fixed');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'display mount hover is finite and retains results in every Appearance',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      final controller = fixture.controller;
      final theme = ValueNotifier(
        applicationThemeForAppearance(
          _appearanceSettings(background: 'plain-cobalt'),
        ),
      );
      try {
        controller.change((p) => p.craftSearch = 'Beer');
        await _settleCalculation(tester, controller);
        await tester.pumpWidget(_host(controller, theme: theme));
        await _settleImages(tester);
        final quotes = controller.quotes;
        final requests = List<String>.of(fixture.requests);
        final card = find.byKey(const ValueKey('craft-card:Beer'));
        final element = tester.element(card);
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        for (final background in [
          'plain-cobalt',
          'sakura-night-garden',
          'illuminated-ledger',
        ]) {
          theme.value = applicationThemeForAppearance(
            _appearanceSettings(background: background),
          );
          await tester.pumpAndSettle();
          final bounds = tester.getRect(card);
          await pointer.moveTo(Offset(bounds.right - 4, bounds.bottom - 4));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(card),
            bounds,
            reason: 'Hover never moves or relays out cards.',
          );
          expect(tester.element(card), same(element));
          expect(controller.quotes, same(quotes));
          expect(controller.calculating, isFalse);
          expect(fixture.requests, requests);
          expect(tester.binding.transientCallbackCount, 0);
          await _captureSubstitutes(tester, 'polish-hover-$background');
          await pointer.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
        }
        await pointer.removePointer();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        theme.dispose();
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'Appearance changes live including open detail without calculations or requests',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      final controller = fixture.controller;
      final theme = ValueNotifier(
        applicationThemeForAppearance(
          _appearanceSettings(background: 'sakura-night-garden'),
        ),
      );
      try {
        await tester.pumpWidget(_host(controller, theme: theme));
        await _settleImages(tester);
        final list = find
            .descendant(
              of: find.byKey(const PageStorageKey('craft-opportunities')),
              matching: find.byType(Scrollable),
            )
            .first;
        ScrollPosition getScroll() =>
            tester.state<ScrollableState>(list).position;
        final scrollState = tester.state<ScrollableState>(list);
        final scroll = getScroll();
        scroll.jumpTo(180);
        await tester.pumpAndSettle();
        final offset = scroll.pixels;
        final quotes = controller.quotes;
        final requests = List<String>.of(fixture.requests);
        final values = controller.preferences.toJson();
        final panes = tester.element(
          find.byKey(const ValueKey('opportunities-panes')),
        );
        for (final background in [
          'illuminated-ledger',
          'plain-cobalt',
          'sakura-night-garden',
        ]) {
          theme.value = applicationThemeForAppearance(
            _appearanceSettings(background: background),
          );
          await tester.pumpAndSettle();
          expect(
            tester.element(find.text('Opportunities')).visualTheme.palette,
            same(theme.value.palette),
          );
          expect(
            controller.quotes,
            same(quotes),
            reason: 'Appearance must never recompute quotes.',
          );
          expect(controller.calculating, isFalse);
          expect(fixture.requests, requests);
          expect(controller.preferences.toJson(), values);
          expect(tester.state<ScrollableState>(list), same(scrollState));
          expect(getScroll().pixels, offset);
          expect(
            tester.element(find.byKey(const ValueKey('opportunities-panes'))),
            same(panes),
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(tester.binding.transientCallbackCount, 0);
        }
        controller.change((p) => p.craftSearch = 'Beer');
        await _settleCalculation(tester, controller);
        controller.selectGlassFinish('moon');
        await tester.pumpAndSettle();
        expect(controller.preferences.craftSearch, 'Beer');
        expect(
          tester.element(find.text('Opportunities')).visualTheme.palette,
          same(theme.value.palette),
          reason:
              'A readable legacy finish preference cannot override Appearance.',
        );
        await _openCalculation(tester, 'Beer');
        await _settleImages(tester);
        final dialogElement = tester.element(find.text('Ingredients').last);
        for (final background in [
          'illuminated-ledger',
          'plain-rose',
          'sakura-night-garden',
        ]) {
          theme.value = applicationThemeForAppearance(
            _appearanceSettings(background: background),
          );
          await tester.pumpAndSettle();
          expect(
            tester.element(find.text('Ingredients').last),
            same(dialogElement),
          );
          expect(dialogElement.visualTheme.palette, same(theme.value.palette));
          expect(Theme.of(dialogElement).brightness, theme.value.brightness);
          await _captureSubstitutes(
            tester,
            'appearance-open-detail-$background',
          );
        }
        await tester.tap(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is AppButton && widget.semanticLabel == 'Close',
              )
              .last,
        );
        await _settleImages(tester);
        final beerName = find
            .descendant(
              of: find.byKey(const ValueKey('craft-card:Beer')),
              matching: find.text('Beer'),
            )
            .first;
        await tester.tap(
          beerName,
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final itemMenu = tester.element(find.text('Item info'));
        for (final background in ['illuminated-ledger', 'plain-cobalt']) {
          theme.value = applicationThemeForAppearance(
            _appearanceSettings(background: background),
          );
          await tester.pumpAndSettle();
          expect(tester.element(find.text('Item info')), same(itemMenu));
          expect(itemMenu.visualTheme.palette, same(theme.value.palette));
          final material = find
              .ancestor(
                of: find.text('Item info'),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Material && widget.type == MaterialType.card,
                ),
              )
              .first;
          expect(
            tester.widget<Material>(material).color,
            theme.value.palette.surfaceRaised,
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final search = _inlineNumber('craft-search');
        await tester.tap(search);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus;
        final searchController = tester.widget<TextField>(search).controller;
        theme.value = applicationThemeForAppearance(
          _appearanceSettings(background: 'sakura-night-garden'),
        );
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(focused));
        expect(
          tester.widget<TextField>(search).controller,
          same(searchController),
        );
        expect(searchController!.text, 'Beer');
        expect(tester.takeException(), isNull);
        await _settleWork(tester, controller.flush());
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        theme.dispose();
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final theme in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    for (final scale in [1.0, 2.0]) {
      _glassTestWidgets(
        'exchange reference directly shows Maehwa $theme $scale',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            const Size(1280, 900),
            textScaleFactor: scale,
          );
          final fixture = (await tester.runAsync(
            () => _Fixture.create(
              exchange: true,
              backgroundId: theme,
              seedNonMarketPrices: false,
            ),
          ))!;
          final controller = fixture.controller;
          try {
            controller.change((p) => p.currencyId = 'sangpyeong');
            await _settleCalculation(tester, controller);
            final retainedBook = controller.itemInfoController;
            // The retained controller's creation mode must not become stale.
            controller.change((p) => p.mode = CraftMode.processing);
            await _settleCalculation(tester, controller);
            await tester.pumpWidget(_host(controller));
            await _settleImages(tester);
            final requests = List<String>.of(fixture.requests);
            final targets = {
              for (final entry in controller.appController.modes.entries)
                entry.key: entry.value.state.value.target,
            };
            await _openExchangeReward(tester, controller, 'Iridescent Maehwa');
            final body = find.byKey(
              const ValueKey('exchange-reference:820141'),
            );
            expect(body, findsOneWidget);
            final sections = tester.widget<ItemReferenceSections>(body);
            expect(sections.controller, same(retainedBook));
            expect(sections.mode, CraftMode.processing);
            expect(
              sections.info.craftUses.map((use) => use.output),
              contains('Iridescent Maehwa Liquor'),
            );
            expect(
              sections.info.effects,
              isEmpty,
              reason: 'The liquor buffs must not be assigned to the flower.',
            );
            expect(
              sections.info.acquisitionNotes.join(' '),
              contains('chance'),
            );
            expect(
              find.descendant(
                of: body,
                matching: find.text('Iridescent Maehwa Liquor'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: body,
                matching: find.textContaining('All Damage Reduction +5'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.text('Sangpyeong Coin ×50'),
              ),
              findsOneWidget,
            );
            expect(
              find.byType(ItemReferenceCard),
              findsNothing,
              reason: 'Inline facts must not nest another header/card/scroll.',
            );
            expect(
              find.byKey(const ValueKey('exchange-detail-summary')),
              findsNothing,
            );
            expect(find.text('No source details recorded yet.'), findsNothing);
            expect(
              fixture.requests,
              requests,
              reason: 'Reading bundled item facts requires no market requests.',
            );
            expect({
              for (final entry in controller.appController.modes.entries)
                entry.key: entry.value.state.value.target,
            }, targets);
            await _captureSubstitutes(
              tester,
              'exchange-reference-$theme-$scale',
              region: find
                  .byWidgetPredicate(
                    (w) =>
                        w is OpportunitySurface &&
                        w.role == AppSurfaceRole.modal,
                  )
                  .last,
            );
            final use = find.descendant(
              of: body,
              matching: find.text('Use recipe'),
            );
            expect(use, findsWidgets);
            await tester.ensureVisible(use.last);
            await _settleImages(tester);
            expect(use.last.hitTestable(), findsOneWidget);
            await _captureSubstitutes(
              tester,
              'exchange-reference-$theme-$scale-recipe',
              region: find
                  .byWidgetPredicate(
                    (w) =>
                        w is OpportunitySurface &&
                        w.role == AppSurfaceRole.modal,
                  )
                  .last,
            );
            if (theme == 'sakura-night-garden' && scale == 1) {
              await tester.tap(use.last);
              await _settleCalculation(tester, controller);
              await _settleImages(tester);
              expect(find.byType(Dialog), findsNothing);
              expect(
                controller.appController.active.state.value.target,
                'Iridescent Maehwa Liquor',
              );
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await _settleImages(tester);
              expect(find.byType(Dialog), findsNothing);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await _settleWork(tester, fixture.dispose());
          }
        },
      );
    }
  }

  for (final item in [
    (
      id: 820143,
      name: 'Strange and Beautiful Herb',
      purpose: 'Miraculous Herbal Medicine',
    ),
    (
      id: 820140,
      name: 'Strange and Beautiful Rice',
      purpose: 'Miraculous Tteokguk',
    ),
    (id: 820139, name: 'Live Meat', purpose: 'Miraculous Nourishing Soup'),
  ]) {
    testWidgets('exchange reference preserves known facts for ${item.name}', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1280, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: true, seedNonMarketPrices: false),
      ))!;
      try {
        fixture.controller.change((p) => p.currencyId = 'sangpyeong');
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openExchangeReward(tester, fixture.controller, item.name);
        final body = find.byKey(ValueKey('exchange-reference:${item.id}'));
        if (item.purpose.isNotEmpty) {
          expect(body, findsOneWidget);
          final info = tester.widget<ItemReferenceSections>(body).info;
          expect(
            info.craftUses.map((use) => use.output),
            contains(item.purpose),
          );
          expect(
            info.effects,
            isEmpty,
            reason: 'An ingredient must not inherit its finished food buffs.',
          );
          if (item.id == 820143) {
            expect(
              info.acquisitionNotes.join(' ').toLowerCase(),
              contains('night'),
            );
            expect(info.acquisitionNotes.join(' '), contains('Deokpal'));
          } else {
            final formula = info.craftUses
                .singleWhere((use) => use.output == item.purpose)
                .formulas
                .single;
            expect(formula.method, 'Simple Cooking');
            expect(formula.ingredients, hasLength(5));
            expect(
              fixture.controller.itemInfoController.canActivateFormula(formula),
              isFalse,
              reason: 'Reference-only formulas do not invent Planner targets.',
            );
          }
          expect(
            find.descendant(of: body, matching: find.text(item.purpose)),
            findsOneWidget,
          );
        }
        await _captureSubstitutes(
          tester,
          'item-facts-material-${item.id}',
          region: find
              .byWidgetPredicate(
                (w) =>
                    w is OpportunitySurface && w.role == AppSurfaceRole.modal,
              )
              .last,
        );
        if (item.id != 820143) {
          final note = find.textContaining('The finished').last;
          await tester.ensureVisible(note);
          await _settleImages(tester);
          expect(note.hitTestable(), findsOneWidget);
          await _captureSubstitutes(
            tester,
            'item-facts-material-${item.id}-recipe',
            region: find
                .byWidgetPredicate(
                  (w) =>
                      w is OpportunitySurface && w.role == AppSurfaceRole.modal,
                )
                .last,
          );
        }
        expect(find.text('No source details recorded yet.'), findsNothing);
        expect(find.text('Durability'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  testWidgets(
    'exchange item facts retain non-crafting uses alongside recipes',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: true, seedNonMarketPrices: false),
      ))!;
      try {
        final currency = exchangeCatalog.firstWhere(
          (c) => c.routes.any(
            (r) => r.rewards.any((reward) => reward.item?.id == 768160),
          ),
        );
        fixture.controller.change((p) => p.currencyId = currency.id);
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openExchangeReward(
          tester,
          fixture.controller,
          'Sealed Black Magic Crystal',
        );
        final info = tester
            .widget<ItemReferenceSections>(
              find.byKey(const ValueKey('exchange-reference:768160')),
            )
            .info;
        expect(info.craftUses, isNotEmpty);
        expect(
          info.uses,
          containsAll([
            'Open for a random Black Magic Crystal.',
            'Grind to obtain Black Stone Powder.',
          ]),
        );
        expect(info.uses.toSet().length, info.uses.length);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final theme in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    for (final scale in [1.0, 2.0]) {
      _glassTestWidgets('exchange item facts open directly $theme $scale', (
        tester,
      ) async {
        configureApplicationTestSurface(
          tester,
          const Size(1280, 900),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(
            exchange: true,
            seedNonMarketPrices: false,
            backgroundId: theme,
          ),
        ))!;
        try {
          final controller = fixture.controller;
          controller.change((p) => p.currencyId = 'sangpyeong');
          await _settleCalculation(tester, controller);
          await tester.pumpWidget(_host(controller));
          await _settleImages(tester);
          final icon = find.byKey(
            const ValueKey('opportunity-item:exchange-icon:3750'),
          );
          await tester.ensureVisible(icon);
          await tester.pumpAndSettle();
          final requests = List<String>.of(fixture.requests);
          final targets = {
            for (final e in controller.appController.modes.entries)
              e.key: e.value.state.value.target,
          };
          await tester.tap(icon);
          await _settleImages(tester);
          expect(find.text('Item info'), findsNothing);
          expect(
            find.text('Give'),
            findsNothing,
            reason:
                'The icon opens the item reference, not exchange economics.',
          );
          final card = tester.widget<ItemReferenceCard>(
            find.byType(ItemReferenceCard),
          );
          expect(card.controller, same(controller.itemInfoController));
          expect(card.info.kind, 'Alchemy tool');
          expect(
            card.info.effects,
            containsAll(['Alchemy Time −1 sec', 'Durability: 3,000']),
          );
          expect(card.info.acquisitionNotes.join(' '), contains('Deokpal'));
          expect(card.info.notes.join(' '), contains('Alchemy Repair Tool'));
          expect(find.text('No source details recorded yet.'), findsNothing);
          expect(find.text('Recipe material'), findsNothing);
          expect(fixture.requests, requests);
          expect({
            for (final e in controller.appController.modes.entries)
              e.key: e.value.state.value.target,
          }, targets);
          await _captureSubstitutes(
            tester,
            'item-facts-tool-$theme-$scale',
            region: find.byType(ItemReferenceCard),
          );
          await tester.ensureVisible(
            find.textContaining('Restore durability').last,
          );
          await _settleImages(tester);
          expect(
            find.textContaining('Restore durability').last.hitTestable(),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settleImages(tester);
          expect(find.byType(ItemReferenceCard), findsNothing);
          await _openExchangeReward(
            tester,
            controller,
            'Morning Light Traditional Alchemy Tool',
          );
          expect(
            find.text('Give'),
            findsOneWidget,
            reason: 'The separate exchange details action is retained.',
          );
          final inline = tester.widget<ItemReferenceSections>(
            find.byKey(const ValueKey('exchange-reference:3750')),
          );
          expect(inline.info.effects, card.info.effects);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      });
    }
  }

  _glassTestWidgets('exchange items omit empty prices and reuse item links', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(
        exchange: true,
        seedNonMarketPrices: false,
        backgroundId: 'sakura-night-garden',
        pricesById: const {'734': 14000000},
        stockCount: 1538,
      ),
    ))!;
    final controller = fixture.controller;
    final planned = <PlannerTargetRequest>[];
    final mapped = <PlannerMapLookupRequest>[];
    final copied = <String>[];
    final detailSurface = find
        .byWidgetPredicate(
          (w) => w is OpportunitySurface && w.role == AppSurfaceRole.modal,
        )
        .last;
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('opportunities-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: OpportunityItemActionsScope(
              externalActions: PlannerExternalActions(
                openRecipeBook: (_) {},
                copyName: (name) async => copied.add(name),
                checkPrices: (_) async => throw UnimplementedError(),
                openPlannerTarget: planned.add,
                resolveMapLookup: (name) async => PlannerMapLookupAvailability(
                  materialName: name,
                  hasNpcVendors: name == 'Milk',
                ),
                openMapLookup: mapped.add,
              ),
              child: Scaffold(
                body: OpportunitiesWorkspace(controller: controller),
              ),
            ),
          ),
        ),
      );
      Future<void> selectCurrency(String id) async {
        controller.change((p) => p.currencyId = id);
        await _settleWork(tester, controller.refresh());
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
      }

      Finder openFor(String name) => find.byWidgetPredicate(
        (w) =>
            w is AppButton && w.semanticLabel == 'Exchange details for $name',
      );
      Future<void> showRoute(String name) async {
        final open = openFor(name);
        await tester.scrollUntilVisible(
          open,
          350,
          scrollable: find
              .descendant(
                of: find.byKey(
                  PageStorageKey('exchange-${controller.currency.id}'),
                ),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 80,
        );
        await tester.pump();
        expect(open.hitTestable(), findsOneWidget);
        await tester.tap(open);
        await _settleDepth(tester, controller);
        await _settleImages(tester);
      }

      Future<void> rightClickItem(int id) async {
        final icon = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byKey(
                ValueKey('opportunity-item:exchange-icon:$id'),
              ),
            )
            .first;
        await tester.tap(
          icon,
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
      }

      Future<void> closeDialog() async {
        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is AppButton && w.semanticLabel == 'Close',
              )
              .hitTestable()
              .last,
        );
        await _settleImages(tester);
      }

      await selectCurrency('energy-of-lakiaro');
      controller.change((p) => p.remainingLimits['lakiaro-tea'] = 5);
      await _settleCalculation(tester, controller);
      await showRoute(exchangeItems[750490]!.name);
      final inlineTea = tester.widget<ItemReferenceSections>(
        find.byKey(const ValueKey('exchange-reference:750490')),
      );
      expect(inlineTea.info.effects, contains('Life EXP +30%'));
      await _captureSubstitutes(
        tester,
        'exchange-bound-reward',
        region: detailSurface,
      );
      expect(
        find.byKey(const ValueKey('exchange-detail-summary')),
        findsNothing,
      );
      for (final text in [
        'Value',
        'Total value',
        'Stock',
        'No price',
        'No preorders',
        'Silver value unavailable',
      ]) {
        expect(
          find.descendant(of: find.byType(Dialog), matching: find.text(text)),
          findsNothing,
        );
      }
      await rightClickItem(750490);
      expect(find.text('View recipe'), findsNothing);
      expect(find.text('Set planner target'), findsNothing);
      await tester.tap(find.text('Item info'));
      await _settleImages(tester);
      final reference = tester.widget<ItemReferenceCard>(
        find.byType(ItemReferenceCard),
      );
      expect(reference.controller, same(controller.itemInfoController));
      expect(reference.info.effects, contains('Life EXP +30%'));
      expect(reference.icon, isNotNull);
      await _captureSubstitutes(
        tester,
        'exchange-item-info',
        region: find.byType(ItemReferenceCard),
      );
      await tester.tap(
        find.bySemanticsLabel(
          "Close ${exchangeItems[750490]!.name} information",
        ),
      );
      await _settleImages(tester);
      await closeDialog();

      await selectCurrency('seal-of-solare');
      await showRoute('Perfume of Courage');
      await _captureSubstitutes(
        tester,
        'exchange-market-reward',
        region: detailSurface,
      );
      expect(
        find.byKey(const ValueKey('exchange-detail-summary')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.textContaining('Stock '),
        ),
        findsOneWidget,
      );
      await rightClickItem(734);
      expect(find.text('View recipe'), findsOneWidget);
      await _captureSubstitutes(
        tester,
        'exchange-right-click',
        region: detailSurface,
      );
      await tester.tap(find.text('Set planner target'));
      await _settleImages(tester);
      expect(planned.single.exactName, 'Perfume of Courage');
      expect(planned.single.mode, CraftMode.alchemy);
      expect(controller.currency.id, 'seal-of-solare');
      expect(
        find.byKey(const ValueKey('exchange-detail-summary')),
        findsOneWidget,
        reason: 'Navigation callbacks must retain the exchange dialog.',
      );
      await closeDialog();

      await selectCurrency('witchs-delicacy');
      await showRoute('Beer');
      await rightClickItem(9213);
      await tester.tap(find.text('View recipe'));
      await _settleImages(tester);
      expect(
        find.byKey(const ValueKey('craft-money-summary')),
        findsOneWidget,
        reason: 'A cooking recipe opens from Exchanges even in Alchemy mode.',
      );
      await closeDialog();
      await rightClickItem(9213);
      await tester.tap(find.text('Set planner target'));
      await _settleImages(tester);
      expect(planned.last.exactName, 'Beer');
      expect(planned.last.mode, CraftMode.cooking);
      await closeDialog();
      await showRoute('Milk');
      await rightClickItem(9065);
      await tester.tap(find.text('Show NPC vendors'));
      await _settleImages(tester);
      expect(mapped.single.materialName, 'Milk');
      expect(mapped.single.source, PlannerMapLookupSource.npcVendors);
      expect(controller.currency.id, 'witchs-delicacy');
      await rightClickItem(9065);
      await tester.tap(find.text('Copy name'));
      await _settleImages(tester);
      expect(copied, ['Milk']);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    }
  });

  for (final view in [
    (theme: 'sakura-night-garden', size: const Size(1200, 900), scale: 1.0),
    (theme: 'illuminated-ledger', size: const Size(1500, 940), scale: 1.0),
    (theme: 'greenhouse', size: const Size(1200, 752), scale: 1.0),
    (theme: 'plain-cobalt', size: const Size(900, 1100), scale: 2.0),
  ]) {
    _glassTestWidgets('selected full exchanges are searchable ${view.theme}', (
      tester,
    ) async {
      configureApplicationTestSurface(
        tester,
        view.size,
        textScaleFactor: view.scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: true,
          backgroundId: view.theme,
          seedNonMarketPrices: false,
        ),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        for (final currency in exchangeCatalog.skip(22)) {
          final scrollable = find
              .descendant(
                of: find.byKey(
                  PageStorageKey(
                    'exchange-${fixture.controller.preferences.currencyId}',
                  ),
                ),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('exchange-choose-item')));
          await _settleImages(tester);
          final search = find.descendant(
            of: find.byKey(const ValueKey('exchange-search')),
            matching: find.byType(TextField),
          );
          await tester.ensureVisible(search);
          await tester.enterText(search, currency.item.name);
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          final picker = find.byKey(
            ValueKey('exchange-currency-${currency.id}'),
          );
          expect(picker, findsOneWidget);
          await tester.ensureVisible(picker);
          await tester.tap(picker);
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          expect(fixture.controller.preferences.currencyId, currency.id);
          expect(
            fixture.controller.exchangeQuotes.map((q) => q.route.id).toSet(),
            currency.routes.map((r) => r.id).toSet(),
          );
          await _captureSubstitutes(
            tester,
            'selected-exchanges-${currency.id}-${view.theme}',
          );
          for (final route in [
            ...currency.routes.where((r) => r.limit.isRepeatable),
            ...currency.routes.where((r) => !r.limit.isRepeatable),
          ]) {
            final detail = find.byWidgetPredicate(
              (w) =>
                  w is AppButton &&
                  w.semanticLabel ==
                      'Exchange details for ${route.rewards.first.name}',
            );
            await tester.scrollUntilVisible(
              detail,
              350,
              scrollable: find
                  .descendant(
                    of: find.byKey(PageStorageKey('exchange-${currency.id}')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
              maxScrolls: 80,
            );
            await tester.pump();
            expect(detail.hitTestable(), findsOneWidget, reason: route.id);
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  for (final view in [
    (theme: 'sakura-night-garden', size: const Size(1200, 900), scale: 1.0),
    (theme: 'illuminated-ledger', size: const Size(1500, 940), scale: 1.0),
    (theme: 'greenhouse', size: const Size(1200, 752), scale: 1.0),
    (theme: 'plain-cobalt', size: const Size(900, 1100), scale: 2.0),
  ]) {
    _glassTestWidgets('inventory comparison B ${view.theme} ${view.scale}', (
      tester,
    ) async {
      configureApplicationTestSurface(
        tester,
        view.size,
        textScaleFactor: view.scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          backgroundId: view.theme,
          seedNonMarketPrices: false,
        ),
      ))!;
      final controller = fixture.controller;
      try {
        controller.change((p) => p.craftSearch = 'Beer');
        await _settleCalculation(tester, controller);
        await tester.pumpWidget(_host(controller));
        await _settleImages(tester);
        await tester.tap(find.byKey(const ValueKey('craft-ingredients-menu')));
        await _settleImages(tester);
        expect(find.text('Only available'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('craft-use-inventory')));
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
        expect(controller.preferences.useInventory, isTrue);
        expect(find.text('Ingredients · owned'), findsOneWidget);
        await _captureSubstitutes(
          tester,
          'inventory-menu-${view.theme}-text${view.scale}',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settleImages(tester);
        await _openCalculation(tester, 'Beer');
        expect(find.text('Craft & sell'), findsOneWidget);
        expect(find.text('Sell owned ingredients'), findsOneWidget);
        expect(find.text('Profit from crafting'), findsWidgets);
        expect(find.text('Inventory'), findsNothing);
        await tester.enterText(_detailCraftCount(), '3');
        await _settleImages(tester);
        final before = controller
            .inspectRecipe(recipe: controller.recipes['Beer']!, crafts: 3)
            .quote;
        final item = before.ingredients.first;
        final inventory = find.byKey(
          ValueKey('ingredient-inventory:${item.name}'),
        );
        final amount = find.descendant(
          of: inventory,
          matching: find.byKey(const ValueKey('inventory-amount-button')),
        );
        await tester.ensureVisible(inventory);
        await tester.tap(amount);
        await tester.pump();
        final input = find.descendant(
          of: inventory,
          matching: find.byType(TextField),
        );
        await tester.enterText(input, '25430');
        expect(tester.widget<TextField>(input).controller!.text, '25.430');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
        expect(
          find.descendant(of: inventory, matching: find.text('25.4k')),
          findsOneWidget,
        );
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          tester.widget<TextField>(_detailCraftCount()).controller!.text,
          '3',
        );
        final after = controller
            .inspectRecipe(recipe: controller.recipes['Beer']!, crafts: 3)
            .quote;
        expect(after.ingredients.first.ownedQuantity, item.quantity);
        expect(after.totalCost, lessThan(before.totalCost!));
        expect(after.profitFor(controller.craftSaleMode), isNotNull);
        final difference = find.byKey(
          const ValueKey('crafting-difference-value'),
        );
        await tester.ensureVisible(difference);
        expect(
          tester.widget<Text>(difference).data,
          '${after.hasEstimatedInputs ? '≈ ' : ''}+${formatCompactOpportunitySilver(after.profitFor(controller.craftSaleMode)!)} silver',
        );
        final raw = tester
            .widget<Text>(
              find.byKey(const ValueKey('raw-ingredient-sales-value')),
            )
            .data;
        expect(
          raw,
          '≈ ${formatCompactOpportunitySilver(after.ownedIngredientSales!)} silver',
        );
        final scrollables = tester.stateList<ScrollableState>(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          ),
        );
        for (final scrollable in scrollables) {
          if (scrollable.position.axis == Axis.vertical) {
            scrollable.position.jumpTo(0);
          }
        }
        await _settleImages(tester);
        await _captureSubstitutes(
          tester,
          'inventory-comparison-${view.theme}-text${view.scale}',
        );
        final toggle = find.byKey(const ValueKey('detail-use-inventory'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await _settleCalculation(tester, controller);
        await _settleImages(tester);
        expect(controller.preferences.useInventory, isFalse);
        expect(find.text('Craft & sell'), findsOneWidget);
        expect(find.text('After tax and investment'), findsOneWidget);
        expect(find.byKey(const ValueKey('crafting-difference')), findsNothing);
        await _captureSubstitutes(
          tester,
          'inventory-off-${view.theme}-text${view.scale}',
        );
        expect(
          controller.modeController.state.value.inventory[item.name],
          25430,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    });
  }

  _glassTestWidgets(
    'estimated EXP uses a tilde without changing silver formatting',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, summaryOnly: true),
      ))!;
      try {
        fixture.controller.change((p) {
          p.mode = CraftMode.alchemy;
          p.craftSearch = 'Elixir of Brawn';
          p.craftSort = 'exp';
        }, assemble: true);
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final quote = fixture.controller.visibleQuotes.single;
        final experience = fixture.controller.experienceForQuote(quote)!;
        expect(experience.estimated, isTrue);
        final card = find.byKey(const ValueKey('craft-card:Elixir of Brawn'));
        final expected = 'EXP ~${formatQuantity(experience.value)}';
        expect(
          find.descendant(of: card, matching: find.text(expected)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('≈ ${formatQuantity(experience.value)}'),
          ),
          findsNothing,
        );
        await _captureSubstitutes(tester, 'exp-estimated-1200-text100');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final view in [
    (size: const Size(1900, 1080), scale: 1.0),
    (size: const Size(1200, 940), scale: 1.0),
    (size: const Size(900, 1100), scale: 2.0),
  ]) {
    _glassTestWidgets(
      'EXP populated and unknown ascending overview ${view.size.width} ${view.scale}',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          view.size,
          textScaleFactor: view.scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, summaryOnly: true),
        ))!;
        try {
          fixture.controller.change((p) {
            p.mode = CraftMode.processing;
            p.craftSort = 'exp';
          }, assemble: true);
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          expect(fixture.controller.visibleQuotes, isNotEmpty);
          expect(
            fixture.controller.visibleQuotes.any(
              (quote) => fixture.controller.experienceForQuote(quote) != null,
            ),
            isTrue,
          );
          _expectCraftOverviewTypography(tester);
          final suffix =
              '${view.size.width.toInt()}-text${(view.scale * 100).toInt()}';
          await _captureSubstitutes(tester, 'exp-include-$suffix');
          fixture.controller.setUnknownExpFilter('only');
          fixture.controller.reverseCraftSort('exp');
          await _settleImages(tester);
          expect(fixture.controller.visibleQuotes, isNotEmpty);
          expect(fixture.controller.preferences.craftAscending, isTrue);
          expect(
            fixture.controller.visibleQuotes.every(
              (quote) => fixture.controller.experienceForQuote(quote) == null,
            ),
            isTrue,
          );
          final summary = find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'craft-summary:',
                ),
          );
          expect(summary, findsWidgets);
          expect(
            find.descendant(of: summary, matching: find.text('EXP')),
            findsNothing,
          );
          expect(
            find.descendant(of: summary, matching: find.text('?')),
            findsNothing,
          );
          _expectCraftOverviewTypography(tester);
          await _captureSubstitutes(tester, 'exp-unknown-ascending-$suffix');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  for (final view in [
    (size: const Size(1200, 752), scale: 1.0),
    (size: const Size(900, 900), scale: 2.0),
  ]) {
    _glassTestWidgets(
      'EXP sort menu is beside, split and dismissible at ${view.scale}',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          view.size,
          textScaleFactor: view.scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, summaryOnly: true),
        ))!;
        try {
          fixture.controller.change((p) => p.craftSearch = 'Beer');
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          final exp = find.byKey(const ValueKey('craft-sort-exp'));
          final menu = find.byKey(const ValueKey('popover:craft-exp-filter'));
          await tester.tap(exp);
          await _settleImages(tester);
          expect(fixture.controller.preferences.craftSort, 'exp');
          expect(fixture.controller.preferences.craftAscending, isFalse);
          expect(menu, findsOneWidget);
          final labels = ['Include unknown', 'Hide unknown', 'Only unknown'];
          for (final label in labels) {
            expect(find.text(label), findsOneWidget);
          }
          for (var i = 1; i < labels.length; i++) {
            expect(
              tester.getRect(find.text(labels[i])).top,
              greaterThan(tester.getRect(find.text(labels[i - 1])).bottom),
            );
          }
          final menuRect = tester.getRect(menu);
          final expRect = tester.getRect(exp);
          final directionRect = tester.getRect(
            find.byKey(const ValueKey('craft-sort-exp-direction')),
          );
          expect(
            menuRect.right <= expRect.left ||
                menuRect.left >= directionRect.right,
            isTrue,
            reason: 'The menu sits beside the control, never over it.',
          );
          expect(menuRect.right, lessThanOrEqualTo(view.size.width));
          expect(menuRect.left, greaterThanOrEqualTo(0));
          expect(menuRect.bottom, lessThanOrEqualTo(view.size.height));
          await _captureSubstitutes(
            tester,
            'exp-menu-${view.size.width.toInt()}-text${(view.scale * 100).toInt()}',
          );
          await tester.tap(
            find.byKey(const ValueKey('craft-sort-exp-direction')),
          );
          await _settleImages(tester);
          expect(fixture.controller.preferences.craftAscending, isTrue);
          expect(fixture.controller.preferences.unknownExpFilter, 'include');
          expect(menu, findsOneWidget);
          await tester.tap(exp);
          await _settleImages(tester);
          expect(menu, findsNothing);
          expect(
            fixture.controller.preferences.craftAscending,
            isTrue,
            reason: 'The label toggles only the menu, not sort direction.',
          );
          for (final filter in ['hide', 'only', 'include']) {
            await tester.tap(exp);
            await _settleImages(tester);
            await tester.tap(find.byKey(ValueKey('craft-exp-filter-$filter')));
            await _settleImages(tester);
            expect(fixture.controller.preferences.unknownExpFilter, filter);
            expect(menu, findsNothing);
          }
          await tester.tap(exp);
          await _settleImages(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settleImages(tester);
          expect(menu, findsNothing);
          await tester.tap(exp);
          await _settleImages(tester);
          await tester.tapAt(const Offset(30, 30));
          await _settleImages(tester);
          expect(menu, findsNothing);
          await tester.tap(find.byKey(const ValueKey('craft-sort-preorders')));
          await _settleImages(tester);
          expect(fixture.controller.preferences.craftSort, 'preorders');
          expect(fixture.controller.preferences.craftAscending, isFalse);
          await tester.tap(find.byKey(const ValueKey('craft-sort-preorders')));
          await _settleImages(tester);
          expect(fixture.controller.preferences.craftAscending, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  _glassTestWidgets(
    'EXP cards show blue known values and completely blank unknowns',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, summaryOnly: true),
      ))!;
      try {
        fixture.controller.change((p) {
          p.craftSearch = 'Beer';
          p.craftSort = 'exp';
        });
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final card = find.byKey(const ValueKey('craft-card:Beer'));
        final quote = fixture.controller.visibleQuotes.single;
        final experience = fixture.controller.experienceForQuote(quote);
        expect(experience, isNotNull);
        final expLabel = find.byKey(const ValueKey('craft-exp:Beer'));
        expect(expLabel, findsOneWidget);
        final amount = expLabel;
        expect(
          tester.widget<Text>(amount).data,
          'EXP ${experience!.estimated ? '~' : ''}${formatQuantity(experience.value)}',
        );
        expect(
          tester.widget<Text>(amount).style!.fontSize,
          lessThanOrEqualTo(14),
        );
        final valueTheme = OpportunitiesVisualSpec.of(tester.element(amount));
        expect(
          tester.widget<Text>(amount).style!.color,
          OpportunitiesVisualSpec.informationColor(valueTheme),
        );
        final investment = find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('craft-per-item-profit:Beer')),
        );
        expect(
          tester.getTopLeft(expLabel).dy,
          greaterThan(tester.getBottomLeft(investment).dy),
        );
        await _captureSubstitutes(tester, 'exp-known-beer-1200-text100');
        await tester.tap(find.text('Best use'));
        fixture.controller.selectBestUseItem('Wheat');
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        expect(
          find.descendant(
            of: find.byKey(const PageStorageKey('best-use-opportunities')),
            matching: find.text('EXP'),
          ),
          findsNothing,
        );
        await tester.tap(find.text('Crafting'));
        fixture.controller.recipes = {
          ...fixture.controller.recipes,
          'Beer': _recipeWithIngredients(
            fixture.controller.recipes['Beer']!,
            const ['Milk'],
          ),
        };
        fixture.controller.recalculate();
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        expect(
          fixture.controller.experienceForQuote(
            fixture.controller.visibleQuotes.single,
          ),
          isNull,
        );
        expect(
          find.descendant(of: card, matching: find.text('EXP')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('?')),
          findsNothing,
        );
        final unknownSlot = find.byKey(
          const ValueKey('craft-unknown-exp:Beer'),
        );
        expect(unknownSlot, findsNothing);
        expect(
          find.descendant(of: unknownSlot, matching: find.byType(Text)),
          findsNothing,
        );
        expect(
          find.descendant(of: unknownSlot, matching: find.byType(Tooltip)),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('Investment')),
          findsNothing,
        );
        await _captureSubstitutes(tester, 'exp-unknown-beer-1200-text100');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final view in [
    (size: const Size(1500, 940), scale: 1.0),
    (size: const Size(1200, 752), scale: 1.0),
    (size: const Size(900, 900), scale: 2.0),
  ]) {
    _glassTestWidgets(
      'overview typography keeps names primary at ${view.size.width.toInt()} '
      'pixels and ${(view.scale * 100).toInt()} percent',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          view.size,
          textScaleFactor: view.scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false),
        ))!;
        final captureSuffix =
            '${view.size.width.toInt()}-text${(view.scale * 100).toInt()}';
        try {
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          _expectCraftOverviewTypography(tester);
          expect(find.text('Main item only'), findsNothing);
          final information = find.byWidgetPredicate(
            (widget) =>
                widget is AppButton &&
                widget.semanticLabel == 'Crafting profit',
          );
          expect(information, findsOneWidget);
          await _captureSubstitutes(
            tester,
            'typography-crafting-$captureSuffix',
          );
          await tester.tap(information);
          await _settleImages(tester);
          expect(find.byType(Dialog), findsOneWidget);
          expect(
            find.text(
              'Profit is the main product’s sale price after tax, minus '
              'the cost of buying the ingredients.',
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settleImages(tester);
          expect(find.byType(Dialog), findsNothing);

          await tester.enterText(
            _inlineNumber('craft-search'),
            'Rainbow Button',
          );
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          expect(fixture.controller.visibleQuotes, hasLength(2));
          _expectCraftOverviewTypography(tester);
          await _captureSubstitutes(
            tester,
            'typography-long-names-$captureSuffix',
          );

          await tester.tap(find.text('Best use'));
          fixture.controller.selectBestUseItem('Trace of Nature');
          await _settleCalculation(tester, fixture.controller);
          await _settleWork(tester, fixture.controller.refresh());
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          expect(fixture.controller.visibleBestUseQuotes, isNotEmpty);
          _expectCraftOverviewTypography(tester, bestUse: true);
          await _captureSubstitutes(
            tester,
            'typography-best-use-$captureSuffix',
          );

          await tester.tap(find.text('Exchanges'));
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          final exchangeCards = find.descendant(
            of: find.byKey(
              PageStorageKey('exchange-${fixture.controller.currency.id}'),
            ),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is OpportunitySurface &&
                  widget.role == AppSurfaceRole.card,
            ),
          );
          if (exchangeCards.evaluate().isEmpty) {
            await tester.drag(
              find.byKey(
                PageStorageKey('exchange-${fixture.controller.currency.id}'),
              ),
              const Offset(0, -350),
            );
            await tester.pumpAndSettle();
          }
          expect(exchangeCards, findsWidgets);
          for (
            var index = 0;
            index < exchangeCards.evaluate().length;
            index++
          ) {
            final card = exchangeCards.at(index);
            final name = find
                .descendant(
                  of: card,
                  matching: find.byWidgetPredicate((widget) {
                    final key = widget.key;
                    return key is ValueKey<String> &&
                        key.value.startsWith('opportunity-copy-name:');
                  }),
                )
                .first;
            final hasTotal = find
                .descendant(of: card, matching: find.text('Total value'))
                .evaluate()
                .isNotEmpty;
            final hasValue = find
                .descendant(of: card, matching: find.text('Value'))
                .evaluate()
                .isNotEmpty;
            _expectOverviewCardTypography(
              tester,
              card: card,
              name: find.descendant(of: name, matching: find.byType(Text)),
              // Nonmarket rewards intentionally omit financial metrics.
              primaryLabel: hasTotal
                  ? 'Total value'
                  : (hasValue ? 'Value' : null),
              secondaryLabels: [
                if (hasTotal || hasValue) 'Per coin',
                if (find
                    .descendant(
                      of: card,
                      matching: find.textContaining('Stock '),
                    )
                    .evaluate()
                    .isNotEmpty)
                  'Stock',
              ],
            );
          }
          final firstExchange = exchangeCards.first;
          await tester.ensureVisible(firstExchange);
          await _settleImages(tester);
          await _captureSubstitutes(
            tester,
            'typography-exchanges-$captureSuffix',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  for (final view in [
    (const Size(1200, 820), 1.0),
    (const Size(820, 900), 1.0),
    (const Size(1200, 1100), 2.0),
  ]) {
    _glassTestWidgets(
      'raw ingredient sales and Inventory in Chowder ${view.$1.width} ${view.$2}',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          view.$1,
          textScaleFactor: view.$2,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(
            exchange: false,
            seedNonMarketPrices: false,
            pricesByName: {
              'Chowder': 70000,
              'Milk': 24800,
              'Teff Bread': 3770,
              'Special Pepper': 900,
            },
          ),
        ))!;
        fixture.controller.change((p) {
          p.mode = CraftMode.cooking;
          p.craftSearch = 'Chowder';
        }, assemble: true);
        await _settleWork(tester, fixture.controller.refresh());
        await _settleWork(
          tester,
          fixture.controller.ensureMarketDepth(
            fixture.controller.market.items.keys,
          ),
        );
        await _settleCalculation(tester, fixture.controller);
        final quote = fixture.controller.quotes.firstWhere(
          (q) => q.recipeName == 'Chowder',
        );
        final planner = fixture.harness.bundle.controller;
        final taxRate = marketNetRate(planner.marketTax.value);
        planner.active.commitInventory('Teff Bread', '400000');
        planner.active.commitInventory('Milk', '1000000');
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Chowder');
        final rawValue = find.byKey(
          const ValueKey('raw-ingredient-sales-value'),
        );
        final gross = quote.ingredients.fold<double>(
          0,
          (sum, input) =>
              sum +
              (isOpportunityMarketRequestEligible(input.itemId!)
                  ? input.quantity * input.market!.basePrice!
                  : 0),
        );
        expect(
          tester.widget<Text>(rawValue).data,
          '≈ ${formatCompactOpportunitySilver(gross * taxRate)} silver',
        );
        if (view.$1.width == 1200 && view.$2 == 1) {
          final raw = tester.getRect(
            find.byKey(const ValueKey('raw-ingredient-sales')),
          );
          final summary = tester.getRect(
            find.byKey(const ValueKey('craft-money-summary')),
          );
          expect(raw.left, greaterThan(summary.left));
          expect(raw.right, lessThanOrEqualTo(summary.right));
          expect(raw.top, greaterThan(summary.top));
          expect(raw.bottom, lessThanOrEqualTo(summary.bottom));
          expect(raw.height, lessThan(140));
        }
        await _captureSubstitutes(
          tester,
          'chowder-inventory-${view.$1.width.toInt()}-${(view.$2 * 100).toInt()}',
        );
        final inventory = find.byKey(
          const ValueKey('ingredient-inventory:Teff Bread'),
        );
        final field = find.descendant(
          of: inventory,
          matching: find.byType(TextField),
        );
        final amountButton = find.descendant(
          of: inventory,
          matching: find.byKey(const ValueKey('inventory-amount-button')),
        );
        await tester.ensureVisible(inventory);
        expect(field, findsNothing);
        expect(
          find.descendant(of: amountButton, matching: find.text('400k')),
          findsOneWidget,
        );
        expect(
          tester.getSize(inventory).height,
          lessThanOrEqualTo(80 * view.$2),
        );
        final requests = fixture.requests.length;
        await tester.tap(amountButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.widget<TextField>(field).controller!.text, '400.000');
        final editState = tester.state<EditableTextState>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        expect(editState.renderEditable.text!.toPlainText(), '400.000');
        expect(
          editState.renderEditable.offset.pixels,
          closeTo(0, 1),
          reason:
              'The inline editor must not inherit the dialog scroll offset.',
        );
        final firstDigit = editState.renderEditable.getLocalRectForCaret(
          const TextPosition(offset: 0),
        );
        expect(
          firstDigit.right,
          greaterThan(0),
          reason: 'The full amount must actually paint inside the editor.',
        );
        await _captureSubstitutes(
          tester,
          'chowder-inventory-${view.$1.width.toInt()}-${(view.$2 * 100).toInt()}-editing',
        );
        expect(
          find.byKey(const ValueKey('ingredient-recipe-back')),
          findsNothing,
          reason:
              'Editing inventory must not activate the surrounding recipe link.',
        );
        await tester.enterText(field, '123456');
        expect(tester.widget<TextField>(field).controller!.text, '123.456');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 200));
        for (final mode in CraftMode.values) {
          expect(
            planner.modes[mode]!.state.value.inventory['Teff Bread'],
            123456,
          );
        }
        expect(field, findsNothing);
        expect(
          find.descendant(of: amountButton, matching: find.text('123.4k')),
          findsOneWidget,
        );
        await tester.tap(amountButton);
        await tester.pump();
        await tester.enterText(field, '700000');
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Chowder'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(field, findsNothing);
        expect(
          planner.active.state.value.inventory['Teff Bread'],
          700000,
          reason: 'Clicking away commits without needing Enter.',
        );
        await tester.tap(amountButton);
        await tester.pump();
        await tester.enterText(field, '999');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(field, findsNothing);
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          planner.active.state.value.inventory['Teff Bread'],
          700000,
          reason: 'Escape cancels the input, not the recipe dialog.',
        );
        expect(
          fixture.requests.length,
          requests,
          reason: 'Inventory edits do not request market data.',
        );
        expect(
          tester.widget<Text>(rawValue).data,
          '≈ ${formatCompactOpportunitySilver(gross * taxRate)} silver',
        );
        expect(
          fixture.controller
              .inspectRecipe(recipe: fixture.controller.recipes['Chowder']!)
              .quote
              .listingProfit,
          quote.listingProfit,
          reason: 'Owned inventory does not make crafting inputs free.',
        );
        final crafts = find.descendant(
          of: find.byKey(const ValueKey('opportunity-detail-crafts')),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(crafts);
        await tester.enterText(crafts, '2');
        await tester.pump();
        final batch = fixture.controller
            .inspectRecipe(
              recipe: fixture.controller.recipes['Chowder']!,
              crafts: 2,
            )
            .quote;
        final batchGross = batch.ingredients.fold<double>(
          0,
          (sum, input) =>
              sum +
              (isOpportunityMarketRequestEligible(input.itemId!)
                  ? input.quantity * input.market!.basePrice!
                  : 0),
        );
        expect(
          tester.widget<Text>(rawValue).data,
          '≈ ${formatCompactOpportunitySilver(batchGross * taxRate)} silver',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets(
      'nonmarket ingredient is not presented as unchecked market stock $scale',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          const Size(1200, 940),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, seedNonMarketPrices: false),
        ))!;
        try {
          fixture.controller.change((p) {
            p.mode = CraftMode.processing;
            p.craftSearch = 'Life Crystal';
          }, assemble: true);
          await _settleWork(tester, fixture.controller.refresh());
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          expect(
            find.text('Some ingredients are not sold on the market'),
            findsNothing,
          );
          expect(find.text('Some prices are missing'), findsNothing);
          await _openCalculation(tester, 'Life Crystal');
          expect(
            find.text('Some ingredients are not sold on the market'),
            findsNothing,
          );
          final forest = find.byKey(
            const ValueKey('opportunity-item:ingredient:Forest Crystal'),
          );
          await tester.ensureVisible(forest);
          await _settleImages(tester);
          await _captureSubstitutes(
            tester,
            'nonmarket-ingredient-${scale.toInt() * 100}',
          );
          expect(forest, findsOneWidget);
          expect(find.text('Buy these ingredients'), findsNothing);
          expect(find.text('Ingredients'), findsWidgets);
          expect(
            find.descendant(
              of: forest,
              matching: find.text('Not sold on the market'),
            ),
            findsNothing,
          );
          for (final label in [
            'Cost',
            'Avg. each',
            'Stock',
            'Stock needs checking',
            'Not in stock',
          ]) {
            expect(
              find.descendant(of: forest, matching: find.text(label)),
              findsNothing,
            );
          }
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    const ValueKey('ingredient-quantity:Forest Crystal'),
                  ),
                )
                .data,
            'Need 1',
          );
          final quote = fixture.controller
              .inspectRecipe(
                recipe: fixture.controller.recipes['Life Crystal']!,
              )
              .quote;
          expect(
            quote.ingredients
                .firstWhere((input) => input.name == 'Forest Crystal')
                .costForCalculation,
            isNull,
          );
          expect(
            quote.listingProfit,
            isNull,
            reason: 'Nonmarket materials are not free.',
          );
          expect(
            fixture.requests.where((request) => request.contains('820036')),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  _glassTestWidgets(
    'nonmarket substitutes keep manual selection without market claims',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, stockCount: 2),
      ))!;
      try {
        fixture.harness.bundle.controller.modes[CraftMode.cooking]!.updateState(
          (state) => state.copyWith(
            recipeEdits: {
              ...state.recipeEdits,
              'Beer': RecipeState(
                type: 'cooking',
                marketId: fixture.controller.catalog.bundledMarketId('Beer'),
                ingredients: [
                  IngredientState(
                    name: 'Forest Crystal',
                    quantity: 1,
                    options: const [
                      'Forest Crystal',
                      'Trace of Nature',
                      'Mineral Water',
                    ],
                  ),
                ],
              ),
            },
          ),
        );
        fixture.controller.preferences.craftSearch = 'Beer';
        fixture.controller.recalculate();
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Beer');
        Future<void> openSubstitutes() async {
          final swaps = find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'ingredient-substitutes:',
                ),
          );
          await tester.tap(swaps.first);
          await _settleImages(tester);
        }

        await openSubstitutes();
        final forest = find.byKey(
          const ValueKey('substitute-option:Forest Crystal'),
        );
        expect(forest, findsOneWidget);
        expect(
          find.descendant(
            of: forest,
            matching: find.text('Not sold on the market'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: forest, matching: find.textContaining('Stock ')),
          findsNothing,
        );
        expect(
          find.descendant(of: forest, matching: find.text('Prices')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('use-substitute-stock:Forest Crystal')),
          findsNothing,
        );
        final npc = find.byKey(
          const ValueKey('substitute-option:Mineral Water'),
        );
        expect(
          find.descendant(of: npc, matching: find.text('NPC each')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('use-substitute:Forest Crystal')),
        );
        await _settleImages(tester);
        final quantity = find.byKey(
          const ValueKey('ingredient-quantity:Forest Crystal'),
        );
        expect(tester.widget<Text>(quantity).data, 'Need 1');
        expect(
          find.byKey(const ValueKey('opportunity-substitute-chooser')),
          findsNothing,
        );
        await openSubstitutes();
        await tester.tap(find.text('Split batch'));
        await _settleImages(tester);
        expect(
          find.descendant(of: forest, matching: find.textContaining('Stock')),
          findsNothing,
        );
        expect(
          find.descendant(of: forest, matching: find.text('Fill remaining')),
          findsNothing,
        );
        final count = find.descendant(
          of: find.byKey(const ValueKey('split-crafts:Forest Crystal')),
          matching: find.byType(TextField),
        );
        await tester.enterText(count, '1');
        await tester.pump();
        await _captureSubstitutes(tester, 'nonmarket-substitute-split');
        await tester.tap(find.byKey(const ValueKey('apply-substitute-split')));
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('opportunity-substitute-chooser')),
          findsNothing,
        );
        expect(tester.widget<Text>(quantity).data, 'Need 1');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'missing market quote is not classified as a nonmarket ingredient',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          unavailableNames: const {'Trace of Nature'},
        ),
      ))!;
      try {
        fixture.controller.recipes = {
          ...fixture.controller.recipes,
          'Beer': _recipeWithIngredients(
            fixture.controller.recipes['Beer']!,
            const ['Trace of Nature'],
          ),
        };
        fixture.controller.preferences.craftSearch = 'Beer';
        fixture.controller.recalculate();
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Beer');
        final trace = find.byKey(
          const ValueKey('opportunity-item:ingredient:Trace of Nature'),
        );
        expect(find.text('Ingredients'), findsWidgets);
        expect(
          find.descendant(of: trace, matching: find.text('Cost')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: trace, matching: find.text('Stock —')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: trace,
            matching: find.text('Not sold on the market'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'best use suggests items and reuses filters without changing planner targets',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          pricesByName: const {'Gem Polisher': 100000, 'Elixir of Sky': 70000},
          stocksByName: const {
            'Trace of Nature': 0,
            'Gem Polisher': 0,
            'Elixir of Sky': 0,
          },
        ),
      ))!;
      final plannerStates = {
        for (final entry in fixture.controller.appController.modes.entries)
          entry.key: entry.value.state.value,
      };
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await tester.tap(find.text('Best use'));
        fixture.controller.setWorkspaceActive(true);
        await tester.pumpAndSettle();
        expect(find.text('Best use for'), findsOneWidget);
        expect(find.text('Choose an item'), findsOneWidget);
        expect(find.text('Crafts'), findsNothing);
        final itemInput = find.descendant(
          of: find.byKey(const ValueKey('best-use-item')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(itemInput, 'trace');
        await _settleImages(tester);
        final suggestion = find.byWidgetPredicate(
          (widget) =>
              widget is AppButton &&
              widget.semanticLabel == 'Select Trace of Nature',
        );
        expect(suggestion, findsOneWidget);
        await _captureSubstitutes(tester, 'best-use-item-suggestions-1500');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(suggestion));
        await mouse.down(tester.getCenter(suggestion));
        await tester.pump();
        await mouse.up();
        await mouse.removePointer();
        await _settleCalculation(tester, fixture.controller);
        await _settleWork(tester, fixture.controller.refresh());
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        expect(fixture.controller.preferences.bestUseItem, 'Trace of Nature');
        expect(fixture.controller.bestUseQuotes, isNotEmpty);
        expect(find.text('Sale'), findsWidgets);
        expect(find.text('Ingredients'), findsWidgets);
        expect(find.text('Profit'), findsWidgets);
        expect(find.textContaining('Makes ~'), findsWidgets);
        expect(find.text('Crafts'), findsNothing);
        for (final size in [const Size(1500, 940), const Size(1200, 752)]) {
          tester.view.physicalSize = size;
          await _settleImages(tester);
          expect(tester.takeException(), isNull);
          await _captureSubstitutes(
            tester,
            'best-use-results-${size.width.toInt()}',
          );
        }
        await tester.tap(find.byKey(const ValueKey('best-use-out-of-stock')));
        await tester.tap(
          find.byKey(const ValueKey('best-use-ingredients-available')),
        );
        await tester.tap(find.byKey(const ValueKey('best-use-profitable')));
        await _settleCalculation(tester, fixture.controller);
        await _settleWork(tester, fixture.controller.refresh());
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        final rows = fixture.controller.visibleBestUseQuotes;
        expect(rows.map((row) => row.recipe.name), contains('Gem Polisher'));
        expect(rows.every((row) => row.otherIngredientsAvailable), isTrue);
        expect(rows.every((row) => row.extraProfitPerUnit! > 0), isTrue);
        for (final row in rows) {
          expect(
            fixture.controller
                .outputMarketFor(row.recipe.name, mode: row.mode)
                ?.stockFor(
                  fixture.controller.clock(),
                  fixture.controller.cachedMarketMaxAge,
                ),
            0,
          );
          expect(
            tester
                .getSize(find.byKey(ValueKey('craft-card:${row.recipe.name}')))
                .width,
            lessThanOrEqualTo(640),
          );
        }
        await _captureSubstitutes(tester, 'best-use-filtered-1200');
        tester.view.physicalSize = const Size(1200, 470);
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _captureSubstitutes(tester, 'best-use-overview-compact');
        tester.view.physicalSize = const Size(1200, 752);
        await _settleImages(tester);
        await _openCalculation(tester, 'Gem Polisher');
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        expect(find.byKey(const ValueKey('root-recipe-page')), findsOneWidget);
        expect(
          find.text('This recipe is no longer in the current results.'),
          findsNothing,
        );
        expect(find.text('Trace of Nature'), findsWidgets);
        await _captureSubstitutes(tester, 'best-use-recipe-detail-1200');
        await tester.tap(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is AppButton && widget.semanticLabel == 'Close',
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(fixture.controller.preferences.mode, CraftMode.cooking);
        for (final entry in plannerStates.entries) {
          expect(
            identical(
              fixture.controller.appController.modes[entry.key]!.state.value,
              entry.value,
            ),
            isTrue,
          );
        }
        await tester.tap(find.text('Crafting').first);
        await _settleImages(tester);
        expect(find.byKey(const ValueKey('craft-search')), findsOneWidget);
        await tester.tap(find.text('Best use'));
        await _settleImages(tester);
        expect(
          tester.widget<EditableText>(itemInput).controller.text,
          'Trace of Nature',
        );
        configureApplicationTestSurface(
          tester,
          const Size(900, 900),
          textScaleFactor: 2,
        );
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _captureSubstitutes(tester, 'best-use-results-900-text200');
        configureApplicationTestSurface(
          tester,
          const Size(900, 650),
          textScaleFactor: 2,
        );
        await tester.enterText(itemInput, 't');
        await _settleImages(tester);
        final suggestions = find.byType(ListView).last;
        expect(tester.getRect(suggestions).bottom, lessThanOrEqualTo(650));
        expect(tester.getRect(suggestions).right, lessThanOrEqualTo(900));
        expect(tester.takeException(), isNull);
        await _captureSubstitutes(tester, 'best-use-suggestions-900-text200');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'craft cards stay bounded with a full catalog and two matching recipes',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        expect(fixture.controller.quotes.length, greaterThan(100));
        for (final scenario in [
          (size: const Size(1200, 752), columns: 3),
          (size: const Size(1500, 940), columns: 4),
          (size: const Size(1900, 1100), columns: 5),
        ]) {
          tester.view.physicalSize = scenario.size;
          await _settleImages(tester);
          _expectCraftCardLayout(
            tester,
            expectedColumns: scenario.columns,
            firstRowTop: 191,
          );
          _expectCraftControlPlacement(tester);
          expect(tester.takeException(), isNull);
          await _captureSubstitutes(
            tester,
            'clean-composition-populated-${scenario.size.width.toInt()}',
          );
        }
        final requests = fixture.requests.length;
        await tester.enterText(_inlineNumber('craft-search'), 'Rainbow Button');
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        expect(
          fixture.controller.visibleQuotes.map((quote) => quote.recipeName),
          unorderedEquals([
            'Rainbow Button Mushroom Sandwich',
            'Rainbow Button Mushroom Cheese Melt',
          ]),
        );
        for (final size in [const Size(1500, 940), const Size(1200, 752)]) {
          tester.view.physicalSize = size;
          await _settleImages(tester);
          _expectCraftCardLayout(tester, expectedColumns: 2, firstRowTop: 191);
          final bounds = tester.getRect(
            find.byKey(const PageStorageKey('craft-opportunities')),
          );
          final cards = [
            for (final quote in fixture.controller.visibleQuotes)
              tester.getRect(
                find.byKey(ValueKey('craft-card:${quote.recipeName}')),
              ),
          ];
          for (final card in cards) {
            expect(card.width, lessThanOrEqualTo(332.1));
          }
          expect(
            cards.last.right,
            lessThanOrEqualTo(bounds.right),
            reason:
                'Two matches keep the bounded card width within the workbench.',
          );
          expect(tester.takeException(), isNull);
        }
        expect(fixture.requests.length, requests);
        await _captureSubstitutes(tester, 'clean-composition-two-results-1200');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'ordinary workbench cards remain compact without fixing their height',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        for (final name in ['Beer', 'Dressing']) {
          fixture.controller.change((p) => p.craftSearch = name);
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          final card = tester.getRect(find.byKey(ValueKey('craft-card:$name')));
          expect(card.top, closeTo(191, 1));
          expect(
            tester.getSize(find.byKey(ValueKey('craft-header:$name'))).height,
            inInclusiveRange(100, 165),
            reason:
                'The original item summary stays compact above the new disclosure.',
          );
          expect(
            card.height -
                tester
                    .getSize(find.byKey(ValueKey('craft-header:$name')))
                    .height,
            lessThanOrEqualTo(92),
            reason:
                'Sell ingredients and the disclosure add only two compact rows.',
          );
          _expectCraftCardLayout(tester, expectedColumns: 1);
          _expectWorkbenchCard(tester, name);
          debugPrint('Finishing $name: top=${card.top}, height=${card.height}');
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'workbench card keeps artwork and full values at 900 pixels and 200 percent',
    (tester) async {
      configureApplicationTestSurface(
        tester,
        const Size(900, 900),
        textScaleFactor: 2,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      try {
        fixture.controller.change((p) => p.craftSearch = 'Beer');
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        _expectCraftCardLayout(tester, expectedColumns: 1);
        _expectWorkbenchCard(tester, 'Beer');
        final card = find.byKey(const ValueKey('craft-card:Beer'));
        final quote = fixture.controller.visibleQuotes.single;
        for (final value in [
          _cardSilver(
            quote.listingProfit! / quote.expectedOutput!,
            signed: true,
          ),
          'Preorders 100.000',
        ]) {
          final text = find.descendant(of: card, matching: find.text(value));
          expect(text, findsOneWidget);
          await tester.ensureVisible(text);
          await _settleImages(tester);
          final box = tester.getRect(text);
          final bounds = tester.getRect(card);
          expect(box.left, greaterThanOrEqualTo(bounds.left));
          expect(box.right, lessThanOrEqualTo(bounds.right));
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        await _captureSubstitutes(tester, 'direction-b-card-900-200');
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets(
      'split toolbar keeps sorting and filters independent $scale',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scale == 1 ? const Size(1200, 752) : const Size(900, 900),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, summaryOnly: true),
        ))!;
        final semantics = tester.ensureSemantics();
        try {
          fixture.controller.change((p) => p.craftSearch = 'Beer');
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          final stock = _menuFilter('craft-has-demand');
          final available = _menuFilter('craft-ingredients-menu');
          for (final label in [
            'Demand',
            'Profit',
            'Out of stock',
            'Ingredients',
            'Profitable',
          ]) {
            final inRail = scale == 1 && ['Demand', 'Profit'].contains(label);
            expect(
              find.descendant(
                of: find.byKey(
                  ValueKey(inRail ? 'opportunities-sidebar' : 'craft-toolbar'),
                ),
                matching: find.text(label),
              ),
              findsOneWidget,
            );
          }
          for (final retired in [
            'Filter & sort',
            'Crafts & costs',
            'Silver / batch',
            'Silver / craft',
          ]) {
            expect(find.text(retired), findsNothing);
          }
          expect(find.byKey(const ValueKey('Crafts')), findsNothing);
          expect(
            find.byKey(const ValueKey('craft-filter-panel')),
            findsNothing,
          );
          expect(find.byType(Dialog), findsNothing);
          expect(stock.hitTestable(), findsOneWidget);
          expect(available.hitTestable(), findsOneWidget);
          _expectWorkbenchGeometry(tester);
          if (scale == 1) _expectCraftControlPlacement(tester);
          await _captureSubstitutes(
            tester,
            'clean-composition-toolbar-${scale.toInt() * 100}',
          );
          final requests = fixture.requests.length;
          for (final onlyStock in [false, true, false]) {
            if (fixture.controller.preferences.demandOnly != onlyStock) {
              await tester.tap(stock);
              await _settleCalculation(tester, fixture.controller);
            }
            for (final sort in ['preorders', 'profit']) {
              await tester.tap(find.byKey(ValueKey('craft-sort-$sort')));
              await _settleCalculation(tester, fixture.controller);
              expect(fixture.controller.preferences.craftSort, sort);
              expect(fixture.controller.preferences.demandOnly, onlyStock);
              expect(tester.widget<FilterChip>(stock).selected, onlyStock);
              _expectSortSelected(tester, sort);
            }
          }
          await tester.tap(find.byKey(const ValueKey('craft-sort-preorders')));
          await _settleCalculation(tester, fixture.controller);
          await tester.tap(stock);
          await _settleCalculation(tester, fixture.controller);
          await tester.tap(stock);
          await _settleCalculation(tester, fixture.controller);
          expect(fixture.controller.preferences.demandOnly, isFalse);
          expect(fixture.controller.preferences.craftSort, 'preorders');
          for (var i = 0; i < 40 && !_focusIsWithin(tester, available); i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(_focusIsWithin(tester, available), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await _settleImages(tester);
          await tester.tap(_menuFilter('craft-ingredients-available'));
          await _settleCalculation(tester, fixture.controller);
          expect(fixture.controller.preferences.readyOnly, isTrue);
          expect(fixture.controller.visibleQuotes.single.recipeName, 'Beer');
          await tester.tap(_menuFilter('craft-ingredients-available'));
          await _settleCalculation(tester, fixture.controller);
          expect(fixture.controller.preferences.readyOnly, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settleImages(tester);
          expect(fixture.requests.length, requests);
          for (final key in [
            'craft-has-demand',
            'craft-ingredients-available',
            'craft-profitable',
          ]) {
            await _toggleCraftFilter(tester, fixture.controller, key);
            expect(
              key == 'craft-ingredients-available'
                  ? fixture.controller.preferences.readyOnly
                  : tester.widget<FilterChip>(_menuFilter(key)).selected,
              isTrue,
            );
          }
          await _captureSubstitutes(
            tester,
            'split-all-filters-${scale.toInt() * 100}',
          );
          for (final key in [
            'craft-has-demand',
            'craft-ingredients-available',
            'craft-profitable',
          ]) {
            await _toggleCraftFilter(tester, fixture.controller, key);
          }
          final search = _inlineNumber('craft-search');
          await tester.enterText(search, 'Beer');
          await _settleCalculation(tester, fixture.controller);
          final textController = tester.widget<TextField>(search).controller!;
          const selection = TextSelection(baseOffset: 1, extentOffset: 3);
          textController.selection = selection;
          final editable = find.descendant(
            of: search,
            matching: find.byType(EditableText),
          );
          final editState = tester.state<EditableTextState>(editable);
          final focus = FocusManager.instance.primaryFocus;
          for (final size in [const Size(760, 900), const Size(1500, 940)]) {
            tester.view.physicalSize = size;
            await _settleImages(tester);
            expect(tester.state<EditableTextState>(editable), same(editState));
            expect(
              tester.widget<TextField>(search).controller,
              same(textController),
            );
            expect(FocusManager.instance.primaryFocus, same(focus));
            expect(textController.selection, selection);
            expect(textController.text, 'Beer');
            expect(fixture.controller.preferences.craftSort, 'preorders');
            expect(fixture.controller.preferences.demandOnly, isFalse);
            final bounds = tester.getRect(
              find.byKey(const ValueKey('craft-toolbar')),
            );
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
            expect(find.byType(Dialog), findsNothing);
            expect(tester.takeException(), isNull);
          }
          await _captureSubstitutes(
            tester,
            'split-toolbar-wide-${scale.toInt() * 100}',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets(
      'out of stock and available ingredients combine with profit ordering $scale',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scale == 1 ? const Size(1200, 752) : const Size(900, 900),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(
            exchange: false,
            pricesByName: {
              'Wheat Flour': 30000,
              'Corn Flour': 20000,
              'Potato Flour': 90000,
            },
            stocksByName: {
              'Wheat Flour': 0,
              'Corn Flour': 0,
              'Potato Flour': 12,
            },
            preordersByName: {'Corn Flour': const []},
            unavailableNames: {'Teff Flour'},
          ),
        ))!;
        try {
          fixture.controller.change((p) {
            p.mode = CraftMode.processing;
            p.craftSearch = 'flour';
          });
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          for (final key in [
            'craft-has-demand',
            'craft-ingredients-available',
          ]) {
            await _toggleCraftFilter(tester, fixture.controller, key);
          }
          expect(fixture.controller.preferences.demandOnly, isTrue);
          expect(fixture.controller.preferences.readyOnly, isTrue);
          expect(fixture.controller.preferences.craftSort, 'profit');
          expect(
            fixture.controller.visibleQuotes.map((quote) => quote.recipeName),
            ['Wheat Flour', 'Corn Flour'],
            reason:
                'Zero stock qualifies without bids; listed and unknown outputs do not.',
          );
          expect(
            find.byKey(const ValueKey('craft-card:Potato Flour')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('craft-card:Teff Flour')),
            findsNothing,
          );
          final first = fixture.controller.visibleQuotes.first;
          final second = fixture.controller.visibleQuotes.last;
          expect(
            first.profitFor(fixture.controller.craftSaleMode),
            greaterThan(second.profitFor(fixture.controller.craftSaleMode)!),
          );
          expect(
            fixture.controller.demandPendingCount,
            greaterThan(0),
            reason: 'The unavailable output stays unchecked, never zero.',
          );
          expect(
            tester.widget<FilterChip>(_menuFilter('craft-has-demand')).selected,
            isTrue,
          );
          expect(fixture.controller.preferences.readyOnly, isTrue);
          await _captureSubstitutes(
            tester,
            'split-stock-profit-${scale.toInt() * 100}',
          );
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets('custom sale price is local, grouped and reversible $scale', (
      tester,
    ) async {
      configureApplicationTestSurface(
        tester,
        const Size(1200, 940),
        textScaleFactor: scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          pricesByName: {
            'Cup of Reticent Moonbeams': 6500000000,
            "Cup of Earth's Sorrows": 3950000000,
            'Essence of Dawn': 67500000,
          },
        ),
      ))!;
      fixture.controller.change((p) {
        p.mode = CraftMode.processing;
        p.craftSearch = 'Cup of Reticent Moonbeams';
      }, assemble: true);
      await _settleWork(tester, fixture.controller.refresh());
      await _settleWork(
        tester,
        fixture.controller.ensureMarketDepth(
          fixture.controller.market.items.keys,
        ),
      );
      await _settleCalculation(tester, fixture.controller);
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, 'Cup of Reticent Moonbeams');
      Finder price() => find.descendant(
        of: find.byKey(const ValueKey('opportunity-custom-sale-price')),
        matching: find.byType(TextField),
      );
      Finder crafts() => find.descendant(
        of: find.byKey(const ValueKey('opportunity-detail-crafts')),
        matching: find.byType(TextField),
      );
      expect(find.text('Custom sale price'), findsOneWidget);
      expect(tester.widget<TextField>(price()).controller!.text, isEmpty);
      expect(tester.widget<TextField>(price()).decoration!.labelText, isNull);
      expect(tester.getSize(crafts()).height, greaterThanOrEqualTo(42));
      expect(tester.getSize(price()).height, tester.getSize(crafts()).height);
      final originalQuotes = fixture.controller.quotes;
      final requests = fixture.requests.length;
      for (var length = 1; length <= 10; length++) {
        final digits = '6400000000'.substring(0, length);
        await tester.enterText(price(), digits);
        await tester.pump();
        expect(
          tester.widget<TextField>(price()).controller!.text,
          formatQuantity(double.parse(digits)),
        );
      }
      await tester.enterText(crafts(), '2');
      await tester.pump();
      final recipe = fixture.controller.recipes['Cup of Reticent Moonbeams']!;
      void checkPrice(int? customPrice) {
        final quote = fixture.controller
            .inspectRecipe(
              recipe: recipe,
              crafts: 2,
              customSalePrice: customPrice,
            )
            .quote;
        final money = find.byKey(const ValueKey('craft-money-summary'));
        expect(
          find.descendant(
            of: money,
            matching: find.text(
              '${formatCompactOpportunitySilver(quote.listingRevenue!)} silver',
            ),
          ),
          findsOneWidget,
        );
        _expectMetricText(
          tester,
          find.byKey(const ValueKey('craft-result:Cup of Reticent Moonbeams')),
          'Profit',
          '${quote.hasEstimatedInputs ? '≈ ' : ''}${formatCompactOpportunitySilver(quote.listingProfit!)}',
        );
      }

      checkPrice(6400000000);
      expect(identical(fixture.controller.quotes, originalQuotes), isTrue);
      expect(
        fixture.requests.length,
        requests,
        reason: 'Typing uses the existing receipts; it must not fetch.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _settleImages(tester);
      await _captureSubstitutes(
        tester,
        'custom-sale-price-${scale.toInt() * 100}',
      );
      await _openIngredient(tester, "Cup of Earth's Sorrows");
      expect(tester.widget<TextField>(price()).controller!.text, isEmpty);
      await tester.enterText(price(), '2000000000');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      expect(
        tester.widget<TextField>(price()).controller!.text,
        '6.400.000.000',
      );
      expect(tester.widget<TextField>(crafts()).controller!.text, '2');
      checkPrice(6400000000);
      await tester.enterText(price(), '0');
      await tester.pump();
      expect(find.text('Enter a whole price above 0'), findsOneWidget);
      _expectMetricText(
        tester,
        find.byKey(const ValueKey('craft-result:Cup of Reticent Moonbeams')),
        'Profit',
        '—',
      );
      await tester.enterText(price(), '');
      await tester.pump();
      expect(find.text('Enter a whole price above 0'), findsNothing);
      checkPrice(null);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settleImages(tester);
      await _captureSubstitutes(
        tester,
        'custom-sale-price-cleared-${scale.toInt() * 100}',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  for (final exchange in [false, true]) {
    _glassTestWidgets('search placeholder does not float $exchange', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: exchange),
      ))!;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      if (exchange) {
        await tester.tap(find.byKey(const ValueKey('exchange-choose-item')));
        await _settleImages(tester);
      }
      final field = find.descendant(
        of: find.byKey(ValueKey(exchange ? 'exchange-search' : 'craft-search')),
        matching: find.byType(TextField),
      );
      final expectedHint = exchange ? 'Find an exchange item' : 'Find a recipe';
      expect(tester.widget<TextField>(field).decoration!.labelText, isNull);
      expect(
        tester.widget<TextField>(field).decoration!.hintText,
        expectedHint,
      );
      final bounds = tester.getRect(field);
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<TextField>(field).decoration!.hintText, isNull);
      expect(tester.widget<TextField>(field).decoration!.labelText, isNull);
      expect(tester.getRect(field), bounds);
      await _captureSubstitutes(
        tester,
        exchange ? 'exchange-search-focused' : 'recipe-search-focused',
      );
      await tester.enterText(field, 'cup');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'cup');
      await tester.enterText(field, '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(
        tester.widget<TextField>(field).decoration!.hintText,
        expectedHint,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets(
      'substitute chooser quantity split and name-only copy $scale',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          const Size(1280, 940),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, stockCount: 19),
        ))!;
        fixture.controller.change((preferences) {
          preferences.mode = CraftMode.processing;
          preferences.craftSearch = 'JIN Dawn Crystal - Accuracy';
        }, assemble: true);
        await _settleWork(tester, fixture.controller.refresh());
        await _settleWork(
          tester,
          fixture.controller.ensureMarketDepth(
            fixture.controller.market.items.keys,
          ),
        );
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'JIN Dawn Crystal - Accuracy');
        await _openIngredient(tester, 'Magical Shard');
        final before = fixture.controller
            .inspectRecipe(
              recipe: fixture.controller.catalog.recipe(
                CraftMode.processing,
                'Magical Shard',
              )!,
            )
            .quote;
        final customPriceField = find.descendant(
          of: find.byKey(const ValueKey('opportunity-custom-sale-price')),
          matching: find.byType(TextField),
        );
        await tester.enterText(customPriceField, '5000');
        await tester.pump();
        final customBefore = fixture.controller
            .inspectRecipe(
              recipe: fixture.controller.catalog.recipe(
                CraftMode.processing,
                'Magical Shard',
              )!,
              customSalePrice: 5000,
            )
            .quote;
        final name = before.ingredients.first.name;
        final swap = find.byKey(ValueKey('ingredient-substitutes:$name'));
        expect(swap, findsOneWidget);
        await tester.ensureVisible(swap);
        await tester.tap(swap);
        await _settleImages(tester);
        final chooser = find.byKey(
          const ValueKey('opportunity-substitute-chooser'),
        );
        expect(chooser, findsOneWidget);
        expect(find.byType(Dialog), findsNWidgets(2));
        await _captureSubstitutes(
          tester,
          'substitutes-compare-${scale.toInt() * 100}',
        );
        final pricesButton = find
            .descendant(of: chooser, matching: find.text('Prices'))
            .first;
        await tester.ensureVisible(pricesButton);
        await tester.tap(pricesButton);
        await tester.pump();
        expect(find.textContaining('/ craft'), findsWidgets);
        final amount = find.descendant(
          of: chooser,
          matching: find.byKey(const ValueKey('opportunity-detail-crafts')),
        );
        await tester.enterText(
          find.descendant(of: amount, matching: find.byType(TextField)),
          '30',
        );
        await tester.pump();
        await tester.tap(
          find.descendant(of: chooser, matching: find.text('Split batch')),
        );
        await tester.pump();
        final options = find
            .descendant(
              of: chooser,
              matching: find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'split-crafts:',
                    ),
              ),
            )
            .evaluate()
            .toList();
        expect(options.length, greaterThan(2));
        final names = options
            .take(2)
            .map(
              (e) => (e.widget.key! as ValueKey<String>).value.substring(
                'split-crafts:'.length,
              ),
            )
            .toList();
        for (final entry in [MapEntry(names[0], 19), MapEntry(names[1], 11)]) {
          final field = find.descendant(
            of: find.byKey(ValueKey('split-crafts:${entry.key}')),
            matching: find.byType(TextField),
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, '${entry.value}');
          await tester.pump();
        }
        final apply = find.byKey(const ValueKey('apply-substitute-split'));
        final repairField = find.descendant(
          of: find.byKey(ValueKey('split-crafts:${names[0]}')),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(repairField);
        await tester.enterText(repairField, '1000000001');
        await tester.pump();
        expect(tester.widget<AppButton>(apply).onPressed, isNull);
        final fill = find.byKey(ValueKey('use-substitute-stock:${names[0]}'));
        await tester.ensureVisible(fill);
        await tester.pumpAndSettle();
        await tester.tap(fill);
        await tester.pump();
        expect(tester.widget<AppButton>(apply).onPressed, isNotNull);
        expect(tester.widget<TextField>(repairField).controller!.text, '19');
        await tester.ensureVisible(apply);
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('substitute-options-scroll')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .jumpTo(0);
        await _settleImages(tester);
        await _captureSubstitutes(tester, 'substitutes-${scale.toInt() * 100}');
        expect(tester.takeException(), isNull);
        await tester.tap(apply);
        await _settleImages(tester);
        expect(chooser, findsNothing);
        for (final entry in [MapEntry(names[0], 19), MapEntry(names[1], 11)]) {
          final quantity = find.byKey(
            ValueKey('ingredient-quantity:${entry.key}'),
          );
          expect(quantity, findsOneWidget);
          expect(
            (tester.widget(quantity) as Text).data,
            startsWith('Need ${entry.value}'),
          );
        }
        expect(fixture.controller.preferences.crafts, isNot(30));
        expect(
          tester.widget<TextField>(customPriceField).controller!.text,
          '5.000',
        );
        _expectMetricText(
          tester,
          find.byKey(const ValueKey('craft-result:Magical Shard')),
          'Profit',
          formatCompactOpportunitySilver(customBefore.listingProfit! * 30),
        );
        await _captureSubstitutes(
          tester,
          'split-result-${scale.toInt() * 100}',
        );
        await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
        await _settleImages(tester);
        await _openIngredient(tester, 'Magical Shard');
        // Navigating to the parent and reopening starts a new child inspection,
        // without changing the parent/global opportunity quantity or saved plan.
        expect(
          fixture.controller.preferences.craftSearch,
          'JIN Dawn Crystal - Accuracy',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
    );
  }

  for (final scenario in [
    (name: 'mixed', price: 100, stock: 2, scale: 1.0),
    (name: 'npc_cheaper', price: 10000, stock: 10, scale: 1.0),
    (name: 'no_stock', price: 100, stock: 0, scale: 1.0),
    (name: 'large_text', price: 100, stock: 2, scale: 2.0),
  ]) {
    _glassTestWidgets(
      'NPC source prices and copy navigation ${scenario.name}',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          const Size(1280, 940),
          textScaleFactor: scenario.scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(
            exchange: false,
            stockCount: scenario.stock,
            pricesByName: {'Purified Water': scenario.price},
          ),
        ))!;
        fixture.controller.recipes = {
          ...fixture.controller.recipes,
          'Beer': _recipeWithIngredients(fixture.controller.recipes['Beer']!, [
            'Purified Water',
            'Mineral Water',
          ]),
        };
        fixture.controller.preferences
          ..craftSearch = 'Beer'
          ..crafts = 5;
        fixture.controller.recalculate();
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Beer');
        await tester.enterText(_detailCraftCount(), '5');
        await _settleImages(tester);
        final water = find.byKey(
          const ValueKey('opportunity-item:ingredient:Mineral Water'),
        );
        final purified = find.byKey(
          const ValueKey('opportunity-item:ingredient:Purified Water'),
        );
        expect(
          find.descendant(of: water, matching: find.text('NPC each')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: water, matching: find.text('30')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: water, matching: find.text('150')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: water, matching: find.textContaining('Stock ')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: water,
            matching: find.text('Stock needs checking'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: purified, matching: find.text('NPC each')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: purified, matching: find.text('5k')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: purified, matching: find.text('Market each')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: purified,
            matching: find.textContaining('Stock '),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: purified,
            matching: find.text(
              scenario.stock == 0
                  ? '≈ 100'
                  : scenario.price == 100
                  ? '110'
                  : '10k',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: purified,
            matching: find.text(scenario.stock == 2 ? '15,2k' : '25k'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/npc_source_prices_${scenario.name}.png'),
        );

        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final requestsBeforeCopy = List<String>.of(fixture.requests);
        for (final name in ['Mineral Water', 'Purified Water']) {
          final title = find.descendant(
            of: find.byType(Dialog),
            matching: find.byKey(ValueKey('opportunity-copy-name:$name')),
          );
          await tester.ensureVisible(title);
          await tester.tap(title);
          await tester.pump();
        }
        expect(copied, ['Mineral Water', 'Purified Water']);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-page')),
          findsNothing,
        );
        expect(fixture.requests, requestsBeforeCopy);
        final cost = find.descendant(of: purified, matching: find.text('Cost'));
        await tester.ensureVisible(cost);
        await tester.tap(cost);
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-page')),
          findsOneWidget,
        );
        expect(copied, ['Mineral Water', 'Purified Water']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
      skip: !Platform.isWindows,
    );
  }

  for (final scenario in [
    (
      name: 'gold_bar',
      currency: 'divine-coin',
      item: 4,
      missing: false,
      scale: 1.0,
    ),
    (
      name: 'gluttony',
      currency: 'divine-coin',
      item: 821344,
      missing: false,
      scale: 1.0,
    ),
    (
      name: 'cooks_clothes',
      currency: 'imperial-cuisine-seal',
      item: 705037,
      missing: true,
      scale: 1.0,
    ),
    (
      name: 'cooks_clothes_large',
      currency: 'imperial-cuisine-seal',
      item: 705037,
      missing: true,
      scale: 2.0,
    ),
    (
      name: 'milk_batch',
      currency: 'imperial-cuisine-seal',
      item: 9065,
      missing: false,
      scale: 1.0,
    ),
    (
      name: 'no_preorders',
      currency: 'divine-coin',
      item: 821344,
      missing: false,
      scale: 1.0,
    ),
  ]) {
    _glassTestWidgets('exchange clarity ${scenario.name}', (tester) async {
      configureApplicationTestSurface(
        tester,
        const Size(1280, 820),
        textScaleFactor: scenario.scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: true,
          missingStock: scenario.missing,
          buyerCount: 15,
          stockCount: 6,
          noBuyers: scenario.name == 'no_preorders',
          preorders: scenario.item == 705037
              ? const {
                  '705037': [
                    OpportunityMarketLevel(price: 259000000, quantity: 13),
                    OpportunityMarketLevel(price: 224000000, quantity: 1),
                    OpportunityMarketLevel(price: 223000000, quantity: 1),
                  ],
                }
              : const {},
          pricesById: const {
            '705037': 241000000,
            '821344': 46600000,
            '9065': 23400,
          },
        ),
      ))!;
      fixture.controller.change((p) => p.currencyId = scenario.currency);
      await _settleWork(tester, fixture.controller.refresh());
      await _settleCalculation(tester, fixture.controller);
      final quote = fixture.controller.exchangeQuotes.firstWhere(
        (q) => q.route.rewards.any((r) => r.item?.id == scenario.item),
      );
      expect(quote.isReference, isTrue);
      expect(quote.displayQuote.exchanges, 1);
      expect(
        quote.displayQuote.valuePerCurrency,
        closeTo(quote.displayQuote.netProceeds! / quote.route.inputCount, .001),
      );
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      final open = find.byWidgetPredicate(
        (w) =>
            w is AppButton &&
            w.semanticLabel ==
                'Exchange details for ${quote.route.rewards.first.name}',
      );
      await tester.ensureVisible(open);
      await tester.tap(open);
      await _settleDepth(tester, fixture.controller);
      await _settleImages(tester);
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Value')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(_testSilver(quote.displayQuote.netProceeds!)),
        ),
        findsWidgets,
      );
      expect(find.textContaining('Calculation for one exchange'), findsNothing);
      expect(find.text('Listing estimate'), findsNothing);
      final summary = find.byKey(const ValueKey('exchange-detail-summary'));
      expect(
        find.descendant(of: summary, matching: find.text('Value')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text(
            scenario.currency == 'divine-coin' ? 'Per coin' : 'Per seal',
          ),
        ),
        findsOneWidget,
      );
      for (final removed in [
        'Value after selling',
        'Price',
        'Earlier price',
        'Orders by price',
        'Manage Currency',
      ]) {
        expect(
          find.descendant(of: dialog, matching: find.text(removed)),
          findsNothing,
        );
      }
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Checked ')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      if (scenario.item != 4) {
        expect(
          find.descendant(of: summary, matching: find.textContaining('Stock ')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Preorders')),
          scenario.name == 'no_preorders' ? findsNothing : findsOneWidget,
        );
        if (scenario.name == 'no_preorders') {
          expect(
            find.descendant(of: dialog, matching: find.text('No preorders')),
            findsNothing,
          );
        } else {
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(scenario.item == 705037 ? '13' : '15'),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(scenario.missing ? 'Stock −15' : 'Stock 6'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.byType(Table)),
          scenario.name == 'no_preorders' ? findsNothing : findsOneWidget,
        );
        if (scenario.name != 'no_preorders') {
          expect(
            tester
                .getRect(
                  find.descendant(of: dialog, matching: find.text('Preorders')),
                )
                .top,
            greaterThan(tester.getRect(summary).bottom),
          );
        }
      } else {
        expect(
          find.descendant(of: dialog, matching: find.textContaining('Stock ')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
      if (Platform.isWindows) {
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/exchange_detail_${scenario.name}.png'),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  testWidgets(
    'summary overview shows honest estimates before scoped inspection',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, summaryOnly: true),
      ))!;
      fixture.controller.preferences.craftSearch = 'Beer';
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      OpportunityQuote beer() =>
          fixture.controller.quotes.firstWhere((q) => q.recipeName == 'Beer');
      final estimate = beer();
      expect(estimate.hasUncheckedInputDepth, isTrue);
      expect(estimate.inputCost, isNull);
      expect(estimate.totalCost, greaterThan(0));
      expect(estimate.listingProfit, isNotNull);
      expect(estimate.marketReady, isFalse);
      expect(
        fixture.requests.where(
          (request) => request.startsWith('GetBiddingInfoList:'),
        ),
        isEmpty,
      );
      final summary = find.byKey(const ValueKey('craft-summary:Beer'));
      expect(
        find.descendant(
          of: summary,
          matching: find.text(
            _cardSilver(
              estimate.listingProfit! / estimate.expectedOutput!,
              signed: true,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('Cost')),
        findsNothing,
      );
      expect(
        find.descendant(of: summary, matching: find.text('Stock 0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('Stock −100.000')),
        findsNothing,
      );
      await _expectPassiveCraftEstimates(tester, estimate);

      final recipe = fixture.controller.recipes['Beer']!;
      final expectedIds = const OpportunityCalculator()
          .marketItemIds(
            recipe: recipe,
            recipes: fixture.controller.recipes,
            rules: fixture.harness.bundle.controller.plannerRules,
            selectedVariantId: estimate.selectedVariantId,
          )
          .where(isOpportunityMarketRequestEligible)
          .toSet();
      await _openCalculation(tester, 'Beer');
      await _settleDepth(tester, fixture.controller);
      final requests = fixture.requests
          .where((request) => request.startsWith('GetBiddingInfoList:'))
          .map((request) => request.split(':').last)
          .toSet();
      expect(requests, isNotEmpty);
      expect(requests.difference(expectedIds), isEmpty);
      expect(beer().hasEstimatedInputs, isFalse);
      expect(beer().inputCost, isNotNull);
      expect(beer().marketReady, isTrue);
      expect(beer().crafts, estimate.crafts);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('craft-result:Beer')),
          matching: find.text(
            formatCompactOpportunitySilver(beer().listingProfit!),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is AppButton && w.semanticLabel == 'Close',
            )
            .hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(fixture.controller.detailStatus.requested, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  for (final scenario in [
    (currency: 'imperial-training-seal', route: 'training-seal-vera'),
    (currency: 'crow-coin', route: 'crow-box-752066'),
    (currency: 'witchs-delicacy', route: 'witchs-delicacy-exp'),
  ]) {
    testWidgets('exchange prerequisites ${scenario.route}', (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: true,
          summaryOnly: true,
          buyerCount: 15,
          stockCount: 6,
          pricesById: const {'721003': 2000},
        ),
      ))!;
      fixture.controller.change((p) => p.currencyId = scenario.currency);
      await _settleWork(tester, fixture.controller.refresh());
      await _settleCalculation(tester, fixture.controller);
      ExchangeQuote current() => fixture.controller.exchangeQuotes.firstWhere(
        (quote) => quote.route.id == scenario.route,
      );
      final route = current().route;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      fixture.requests.clear();
      final open = find.byWidgetPredicate(
        (widget) =>
            widget is AppButton &&
            widget.semanticLabel ==
                'Exchange details for ${route.rewards.first.name}',
      );
      await tester.scrollUntilVisible(
        open,
        400,
        scrollable: find
            .descendant(
              of: find.byKey(PageStorageKey('exchange-${scenario.currency}')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await _settleDepth(tester, fixture.controller);
      await _settleImages(tester);
      final dialog = find.byType(Dialog);
      final summary = find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('exchange-detail-summary')),
      );
      Finder textInDialog(String value) =>
          find.descendant(of: dialog, matching: find.text(value));
      void expectAboveSummary(Finder finder) {
        expect(finder, findsOneWidget);
        if (summary.evaluate().isNotEmpty) {
          expect(
            tester.getBottomLeft(finder).dy,
            lessThanOrEqualTo(tester.getTopLeft(summary).dy),
          );
        }
      }

      expect(
        summary,
        scenario.route == 'crow-box-752066' ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(ExpansionTile)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('exchange-instructions')), findsNothing);
      expect(
        textInDialog(route.location),
        findsNothing,
        reason: 'There is no location or Manage Currency disclosure.',
      );
      for (final label in ['Price', 'Earlier price', 'Orders by price']) {
        expect(textInDialog(label), findsNothing);
      }
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Checked ')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Orders:')),
        findsNothing,
      );

      if (scenario.route == 'training-seal-vera') {
        expectAboveSummary(
          textInDialog('Remaining exchanges · Once per family'),
        );
        expectAboveSummary(textInDialog(route.requirements.single));
        expectAboveSummary(textInDialog('Requirements met'));
        expect(current().availability, ExchangeAvailability.confirmationNeeded);
        await tester.tap(textInDialog('1'));
        await _settleCalculation(tester, fixture.controller);
        expect(fixture.controller.preferences.remainingLimits[route.id], 1);
        expect(current().availability, ExchangeAvailability.confirmationNeeded);
        await tester.tap(textInDialog('Requirements met'));
        await _settleCalculation(tester, fixture.controller);
        expect(
          fixture.controller.preferences.confirmedRequirements,
          contains(route.id),
        );
        expect(current().availability, ExchangeAvailability.available);
        expect(current().exchanges, 1);
        await tester.tap(textInDialog('0'));
        await _settleCalculation(tester, fixture.controller);
        expect(fixture.controller.preferences.remainingLimits[route.id], 0);
        expect(current().availability, ExchangeAvailability.limitReached);
        expect(current().exchanges, 0);
        expect(
          textInDialog(route.requirements.single),
          findsOneWidget,
          reason: 'Manage Currency in a real requirement stays visible.',
        );
      } else if (scenario.route == 'crow-box-752066') {
        expect(textInDialog('Box of 20 Caphras Stones'), findsOneWidget);
        expectAboveSummary(textInDialog('Caphras Stone ×20'));
        expectAboveSummary(
          textInDialog('Remaining exchanges · Up to 10 per week'),
        );
        await tester.tap(textInDialog('10'));
        await _settleCalculation(tester, fixture.controller);
        expect(fixture.controller.preferences.remainingLimits[route.id], 10);
        expect(current().availability, ExchangeAvailability.available);
        expect(current().exchanges, 1);
        expect(current().rewardQuotes.single.quantity, 20);
        expect(current().netProceeds, closeTo(20 * 2000 * .65, .001));
        expect(
          fixture.requests,
          ['GetBiddingInfoList:721003'],
          reason: 'Only the guaranteed contents need a book, not the box.',
        );
        final preorders = find.descendant(
          of: dialog,
          matching: find.byKey(const ValueKey('exchange-preorders-721003')),
        );
        expect(preorders, findsOneWidget);
        expect(
          tester.getTopLeft(preorders).dy,
          greaterThan(tester.getBottomLeft(summary).dy),
        );
        expect(textInDialog('Preorders'), findsOneWidget);
        expect(
          find.descendant(of: preorders, matching: find.byType(Table)),
          findsOneWidget,
          reason: 'The preorder rows are visible without an extra click.',
        );
      } else {
        expect(textInDialog('Exchange rewards'), findsOneWidget);
        expectAboveSummary(textInDialog('Contribution EXP ×900'));
        expectAboveSummary(textInDialog('Cooking EXP ×30'));
        expect(current().hasUnpricedRewards, isTrue);
        expect(current().netProceeds, isNull);
        expect(textInDialog('Value'), findsNothing);
        expect(textInDialog('Stock'), findsNothing);
      }

      final summaryBottom = summary.evaluate().isEmpty
          ? double.infinity
          : tester.getBottomLeft(summary).dy;
      final belowSummaryText = <String>[];
      for (final element
          in find
              .descendant(of: dialog, matching: find.byType(Text))
              .evaluate()) {
        final finder = find.byElementPredicate(
          (candidate) => identical(candidate, element),
        );
        if (tester.getTopLeft(finder).dy >= summaryBottom) {
          belowSummaryText.add((element.widget as Text).data ?? '');
        }
      }
      if (scenario.route == 'crow-box-752066') {
        expect(belowSummaryText.take(5), [
          'Preorders',
          'Quantity',
          'Price each',
          '15',
          '2.000',
        ]);
        final reference = find.byKey(
          const ValueKey('exchange-reference:721003'),
        );
        expect(reference, findsOneWidget);
        expect(
          tester.widget<ItemReferenceSections>(reference).name,
          'Caphras Stone',
        );
        expect(
          tester.getTopLeft(reference).dy,
          greaterThan(tester.getBottomLeft(summary).dy),
        );
      } else {
        expect(belowSummaryText, isEmpty);
        expect(textInDialog('Stock'), findsNothing);
        expect(textInDialog('Preorders'), findsNothing);
        expect(
          fixture.requests,
          isEmpty,
          reason: 'Utility and non-market rewards must not fetch market books.',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  testWidgets('exchange details request only their market reward books', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(exchange: true, summaryOnly: true),
    ))!;
    fixture.controller.change((p) => p.currencyId = 'divine-coin');
    await _settleWork(tester, fixture.controller.refresh());
    await _settleCalculation(tester, fixture.controller);
    await tester.pumpWidget(_host(fixture.controller));
    await _settleImages(tester);
    expect(
      fixture.requests.where(
        (request) => request.startsWith('GetBiddingInfoList:'),
      ),
      isEmpty,
    );
    final quote = fixture.controller.exchangeQuotes.firstWhere(
      (quote) => quote.route.rewards.any((reward) => reward.item?.id == 821344),
    );
    final open = find.byWidgetPredicate(
      (widget) =>
          widget is AppButton &&
          widget.semanticLabel ==
              'Exchange details for ${quote.route.rewards.first.name}',
    );
    await tester.ensureVisible(open);
    await tester.tap(open);
    await _settleDepth(tester, fixture.controller);
    expect(
      fixture.requests
          .where((request) => request.startsWith('GetBiddingInfoList:'))
          .toSet(),
      {'GetBiddingInfoList:821344'},
    );
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is AppButton && w.semanticLabel == 'Close',
          )
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    await _settleImages(tester);
    // The controller was created in the real I/O zone; allow its completed
    // ready future to release the panel scope after Navigator.pop.
    for (var i = 0; i < 100 && fixture.controller.detailStatus.requested; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(fixture.controller.detailStatus.requested, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleWork(tester, fixture.dispose());
  });

  for (final scenario in [
    (name: 'crafting_overview', exchange: false, details: false),
    (name: 'ingredient_popup', exchange: false, details: true),
    (name: 'exchange_picker', exchange: true, details: false),
  ]) {
    _glassTestWidgets('Sakura ${scenario.name} stays clear', (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: scenario.exchange,
          backgroundId: SakuraNightGardenSpec.backgroundId,
        ),
      ))!;
      if (scenario.details) {
        fixture.controller.preferences.craftSearch = 'Beer';
      }
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      if (!scenario.exchange) {
        _expectCraftControlPlacement(tester);
        _expectMarketNumberOnOneLine(tester);
      }
      if (scenario.exchange) {
        _expectExchangeHeaderSpacing(tester);
        expect(
          find.byKey(const ValueKey('exchange-choose-item')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('exchange-search')), findsNothing);
      } else if (scenario.details) {
        await _openCalculation(tester, 'Beer');
        await _settleImages(tester);
        expect(find.text('Ingredients'), findsWidgets);
        _expectIngredientColumns(tester, columns: 2);
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('opportunities-capture')),
        matchesGoldenFile('goldens/sakura_${scenario.name}.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    }, skip: !Platform.isWindows);
  }

  for (final scenario in [
    (
      name: 'crafting_glass_1500',
      size: const Size(1500, 940),
      scale: 1.0,
      exchange: false,
    ),
    (
      name: 'crafting_1280',
      size: const Size(1280, 820),
      scale: 1.0,
      exchange: false,
    ),
    (
      name: 'exchanges_1280',
      size: const Size(1280, 820),
      scale: 1.0,
      exchange: true,
    ),
    (
      name: 'crafting_900_large',
      size: const Size(900, 700),
      scale: 1.3,
      exchange: false,
    ),
    (
      name: 'exchanges_900_large',
      size: const Size(900, 700),
      scale: 1.3,
      exchange: true,
    ),
    (
      name: 'crafting_900_200',
      size: const Size(900, 700),
      scale: 2.0,
      exchange: false,
    ),
    (
      name: 'exchanges_900_200',
      size: const Size(900, 700),
      scale: 2.0,
      exchange: true,
    ),
  ]) {
    _glassTestWidgets(
      '${scenario.name} uses real items and fits without overflow',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scenario.size,
          textScaleFactor: scenario.scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: scenario.exchange),
        ))!;
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Opportunities'), findsOneWidget);
        // The refresh action matches the neighboring compact Market action.
        final refresh = tester.getRect(
          find.byKey(const ValueKey('opportunities-refresh')),
        );
        final market = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AppButton && widget.semanticLabel == 'Market · EU',
          ),
        );
        expect(refresh.height, closeTo(market.height, .01));
        if (scenario.scale == 1) expect(refresh.height, closeTo(40, .01));
        _expectWorkbenchGeometry(tester);
        if (scenario.exchange) {
          _expectExchangeHeaderSpacing(tester);
          expect(
            find.byKey(const ValueKey('exchange-choose-item')).hitTestable(),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('exchange-search')), findsNothing);
          if (scenario.scale < 2) {
            expect(find.text('Repeatable'), findsOneWidget);
          }
          expect(
            fixture.controller.exchangeQuotes.any(
              (quote) => quote.netProceeds != null && quote.netProceeds! > 0,
            ),
            isTrue,
          );
        } else {
          if (scenario.size.width >= 1280 && scenario.scale == 1) {
            _expectCraftControlPlacement(tester);
          }
          expect(fixture.controller.quotes.length, greaterThan(100));
          expect(
            fixture.controller.quotes.any(
              (quote) =>
                  (quote.profitFor(OpportunitySaleMode.listing) ?? 0) > 0,
            ),
            isTrue,
          );
          expect(
            fixture.controller.quotes.any(
              (quote) =>
                  (quote.profitFor(OpportunitySaleMode.listing) ?? 0) < 0,
            ),
            isTrue,
          );
          expect(find.text('per item'), findsNothing);
          expect(find.text('Sell ingredients'), findsWidgets);
          expect(find.text('Sale after tax'), findsNothing);
          expect(find.textContaining('Buyers cover this batch'), findsNothing);
          expect(
            find.byKey(const ValueKey('craft-sort-options')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('craft-sort-options')),
              matching: find.text('Demand'),
            ),
            findsOneWidget,
          );
          expect(find.text('Sales'), findsNothing);
          expect(find.text('Time estimate'), findsNothing);
          expect(find.text('Profit / hour'), findsNothing);
          _expectMarketNumberOnOneLine(tester);
          expect(
            find.byKey(const ValueKey('craft-comparison-board')),
            findsNothing,
          );
          _expectCraftCardLayout(
            tester,
            expectedColumns: scenario.scale == 1
                ? (scenario.size.width >= 1500 ? 4 : 3)
                : scenario.scale == 2
                ? 1
                : 2,
          );
          expect(find.textContaining('Makes '), findsNothing);
          if (scenario.scale == 2) {
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('craft-card:Beer')))
                  .width,
              closeTo(332 * 2, .01),
              reason:
                  'Double-sized text uses one column with the established card density.',
            );
          }
        }
        if (scenario.name == 'crafting_glass_1500') {
          await _captureSubstitutes(tester, 'fullwidth-populated-1500');
        }
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/${scenario.name}.png'),
        );
        if (!scenario.exchange && scenario.scale == 2) {
          final card = find.byKey(const ValueKey('craft-card:Beer'));
          final beer = fixture.controller.quotes.firstWhere(
            (quote) => quote.recipeName == 'Beer',
          );
          await tester.ensureVisible(
            find.descendant(
              of: card,
              matching: find.text(
                _cardSilver(
                  beer.listingProfit! / beer.expectedOutput!,
                  signed: true,
                ),
              ),
            ),
          );
          await _settleImages(tester);
          for (final value in [
            _cardSilver(
              beer.listingProfit! / beer.expectedOutput!,
              signed: true,
            ),
            'Preorders 100.000',
          ]) {
            // At 200% text the viewport can be shorter than one card. Each
            // value remains reachable instead of forcing fixed card heights.
            await tester.ensureVisible(
              find.descendant(of: card, matching: find.text(value)),
            );
            await _settleImages(tester);
            expect(
              find
                  .descendant(of: card, matching: find.text(value))
                  .hitTestable(),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('opportunities-capture')),
            matchesGoldenFile('goldens/crafting_900_200_values.png'),
          );
        }
        if (scenario.exchange && scenario.scale == 2) {
          await tester.scrollUntilVisible(
            find.text('Repeatable'),
            180,
            scrollable: find.descendant(
              of: find.byKey(
                PageStorageKey('exchange-${fixture.controller.currency.id}'),
              ),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            ),
          );
          await _settleImages(tester);
          expect(find.text('Repeatable'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('opportunities-capture')),
            matchesGoldenFile('goldens/exchanges_900_200_rewards.png'),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
      skip: !Platform.isWindows,
    );
  }

  for (final scenario in [
    (
      name: 'partial',
      stock: 20,
      summary: false,
      unavailable: false,
      stale: false,
      red: true,
    ),
    (
      name: 'exact',
      stock: 450,
      summary: false,
      unavailable: false,
      stale: false,
      red: false,
    ),
    (
      name: 'ample',
      stock: 451,
      summary: false,
      unavailable: false,
      stale: false,
      red: false,
    ),
    (
      name: 'zero',
      stock: 0,
      summary: false,
      unavailable: false,
      stale: false,
      red: true,
    ),
    (
      name: 'summary-only shortage',
      stock: 20,
      summary: true,
      unavailable: false,
      stale: false,
      red: true,
    ),
    (
      name: 'unknown',
      stock: 20,
      summary: true,
      unavailable: true,
      stale: false,
      red: false,
    ),
    (
      name: 'stale',
      stock: 20,
      summary: false,
      unavailable: false,
      stale: true,
      red: false,
    ),
  ]) {
    testWidgets('ingredient quantity color ${scenario.name}', (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      var now = DateTime.utc(2026, 9, 8, 16);
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          stockCount: scenario.stock,
          summaryOnly: scenario.summary,
          clock: () => now,
          unavailableNames: scenario.unavailable ? const {'Milk'} : const {},
        ),
      ))!;
      // Reuse the existing controlled-recipe helper to make the boundary
      // exactly 450 units, independently of automatic grain substitutions.
      fixture.controller.recipes = {
        ...fixture.controller.recipes,
        'Beer': _recipeWithIngredients(fixture.controller.recipes['Beer']!, [
          'Milk',
          'Sugar',
        ]),
      };
      fixture.controller.preferences
        ..craftSearch = 'Beer'
        ..crafts = 450;
      // Keep the intended missing/stale/summary-only fixture unchanged when
      // opening its calculation. This is the public Stop behavior, not a fake
      // receipt or a manufactured empty order book.
      fixture.controller.cancel();
      if (scenario.stale) now = now.add(const Duration(hours: 4));
      await tester.runAsync(() async {
        fixture.controller.recalculate();
        await fixture.controller.calculationSettled;
      });
      await _settleCalculation(tester, fixture.controller);
      final quote = fixture.controller
          .inspectRecipe(
            recipe: fixture.controller.recipes['Beer']!,
            crafts: 450,
          )
          .quote;
      final milk = quote.ingredients.firstWhere((item) => item.name == 'Milk');
      final sugar = quote.ingredients.firstWhere(
        (item) => item.name == 'Sugar',
      );
      expect(milk.quantity, 450);
      expect(milk.npcQuantity, 0);
      expect(
        milk.market?.stockFor(now, fixture.controller.cachedMarketMaxAge),
        scenario.unavailable || scenario.stale ? isNull : scenario.stock,
      );
      if (scenario.summary) {
        expect(milk.marketQuantity, 0);
        expect(milk.depthKnown, isFalse);
      } else if (!scenario.stale) {
        expect(
          milk.marketQuantity,
          scenario.stock < 450 ? scenario.stock : 450,
        );
      }
      expect(sugar.npcQuantity, sugar.quantity);
      expect(sugar.coversRequest, isTrue);
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, 'Beer');
      await tester.enterText(_detailCraftCount(), '450');
      await _settleImages(tester);
      final subtitle = find.byKey(const ValueKey('ingredient-quantity:Milk'));
      expect(subtitle, findsOneWidget);
      final spec = tester.element(subtitle).visualTheme;
      expect(tester.widget<Text>(subtitle).data, startsWith('Need 450'));
      if (scenario.name == 'partial') {
        expect(tester.widget<Text>(subtitle).data, 'Need 450');
      }
      expect(
        tester.widget<Text>(subtitle).style?.color,
        spec.typography.meta.color,
      );
      final badge = tester.widget<Text>(
        find.byKey(const ValueKey('ingredient-stock:Milk')),
      );
      final unknown = scenario.unavailable || scenario.stale;
      expect(
        badge.data,
        unknown
            ? 'Stock —'
            : scenario.stock == 0
            ? 'Stock −100.000'
            : 'Stock ${scenario.stock}',
      );
      expect(
        badge.style?.color,
        OpportunitiesVisualSpec.readableValueColor(
          spec,
          unknown
              ? spec.palette.textMuted
              : scenario.stock == 0
              ? spec.palette.danger
              : scenario.stock < 450
              ? spec.palette.warning
              : spec.palette.success,
        ),
      );
      expect(
        find.byKey(const ValueKey('ingredient-stock:Sugar')),
        findsNothing,
      );
      final npc = find.byKey(const ValueKey('ingredient-quantity:Sugar'));
      expect(tester.widget<Text>(npc).data, 'Need 450 · NPC');
      expect(
        tester.widget<Text>(npc).style?.color,
        spec.typography.meta.color,
        reason: 'NPC supplies cover the request even when market stock is low.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  testWidgets('ingredient quantity color also applies inside nested recipes', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(exchange: false, stockCount: 0),
    ))!;
    fixture.controller.preferences.craftSearch = 'Margoria Seafood Meal';
    await tester.pumpWidget(_host(fixture.controller));
    await _settleImages(tester);
    await _openCalculation(tester, 'Margoria Seafood Meal');
    await _openIngredient(tester, 'Butter-roasted Lobster');
    await _openIngredient(tester, 'Butter');
    await _openIngredient(tester, 'Cream');
    expect(
      find.byKey(const ValueKey('ingredient-recipe-page')),
      findsOneWidget,
    );
    final subtitle = find.byKey(const ValueKey('ingredient-quantity:Milk'));
    expect(subtitle, findsOneWidget);
    expect(
      tester.widget<Text>(subtitle).style?.color,
      tester.element(subtitle).visualTheme.typography.meta.color,
    );
    final badge = tester.widget<Text>(
      find.byKey(const ValueKey('ingredient-stock:Milk')),
    );
    expect(badge.data, 'Stock −100.000');
    expect(
      badge.style?.color,
      OpportunitiesVisualSpec.readableValueColor(
        tester.element(subtitle).visualTheme,
        tester.element(subtitle).visualTheme.palette.danger,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleWork(tester, fixture.dispose());
  });

  _glassTestWidgets(
    'missing ingredients show a price estimate without becoming available',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          missingStock: true,
          noBuyers: true,
        ),
      ))!;
      fixture.controller.preferences.craftSearch = 'Beer';
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      final beer = fixture.controller.quotes.firstWhere(
        (q) => q.recipeName == 'Beer',
      );
      expect(beer.hasEstimatedInputs, isTrue);
      expect(beer.marketReady, isFalse);
      expect(beer.listingProfit, isNotNull);
      expect(find.text('per item'), findsNothing);
      expect(find.text('Sell ingredients'), findsWidgets);
      expect(find.text('Estimate · missing stock'), findsNothing);
      await _expectPassiveCraftEstimates(tester, beer);
      await _openCalculation(tester, 'Beer');
      await _settleImages(tester);
      _expectIngredientColumns(tester, columns: 2);
      expect(
        find.textContaining('missing · estimated at 1.000 silver each'),
        findsNothing,
      );
      expect(find.text('Estimated profit'), findsNothing);
      expect(find.text('Ingredients · estimated'), findsNothing);
      expect(find.text('Ingredients'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('craft-result:Beer')),
          matching: find.text(
            '≈ ${formatCompactOpportunitySilver(beer.listingProfit!)}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Complete crafts'), findsNothing);
      if (Platform.isWindows) {
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/missing_stock_estimate.png'),
        );
      }
      final about = find.byKey(const ValueKey('craft-calculation-info'));
      await tester.ensureVisible(about);
      await tester.tap(about);
      await _settleImages(tester);
      expect(
        find.text(
          '≈ uses current prices for the missing quantity where there is not enough stock.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is AppButton && widget.semanticLabel == 'Close',
            )
            .last,
      );
      await _settleImages(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppButton && w.semanticLabel == 'Close',
        ),
      );
      fixture.controller.change((p) => p.readyOnly = true);
      await _settleCalculation(tester, fixture.controller);
      expect(
        fixture.controller.visibleQuotes.any((q) => q.recipeName == 'Beer'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  for (final width in [1280.0, 900.0]) {
    _glassTestWidgets('large Market counts stay on one line at $width pixels', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, Size(width, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          buyerCount: 123456789,
          stockCount: 123456789,
        ),
      ))!;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      expect(
        find.byKey(const ValueKey('craft-comparison-board')),
        findsNothing,
        reason: 'All window widths use the approved card layout.',
      );
      for (final prefix in ['Preorders ', 'Stock ']) {
        const value = '123.456.789';
        final number = find.descendant(
          of: find.byKey(const PageStorageKey('craft-opportunities')),
          matching: find.text('$prefix$value'),
        );
        expect(number, findsWidgets);
        final paragraph = tester.renderObject<RenderParagraph>(number.first);
        expect(
          paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: prefix.length,
              extentOffset: prefix.length + value.length,
            ),
          ),
          hasLength(1),
          reason: '$value must stay readable without wrapping its digits.',
        );
      }
      expect(tester.takeException(), isNull);
      if (Platform.isWindows) {
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/large_market_counts_${width.toInt()}.png'),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  _glassTestWidgets(
    'exchanges use listing prices without buyer warnings or padded fractions',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: true, noBuyers: true),
      ))!;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      expect(
        fixture.controller.exchangeQuotes.any((q) => q.netProceeds != null),
        isTrue,
      );
      expect(fixture.controller.exchangeSaleMode, ExchangeSaleMode.listing);
      expect(
        fixture.controller.exchangeQuotes.any((q) => q.hasListingEstimate),
        isFalse,
      );
      expect(find.text('Per coin'), findsWidgets);
      expect(find.text('Total value'), findsWidgets);
      expect(find.text('Estimate · not enough buyers'), findsNothing);
      expect(find.text('Current buyers'), findsNothing);
      expect(find.text('List for sale'), findsNothing);
      expect(find.text('0,1000'), findsNothing);
      final fractionalQuote = fixture.controller.exchangeQuotes.firstWhere(
        (q) =>
            q.displayQuote.valuePerCurrency != null &&
            q.displayQuote.valuePerCurrency! > 0 &&
            q.displayQuote.valuePerCurrency! < 1,
      );
      // Keep the existing precise per-currency value, not the old rounded 0.1.
      final fractionalValue = formatGroupedEditableQuantity(
        fractionalQuote.displayQuote.valuePerCurrency!,
        fractionDigits: 4,
      );
      final fractionalText = find.text(fractionalValue);
      await tester.scrollUntilVisible(
        fractionalText.first,
        250,
        scrollable: find
            .descendant(
              of: find.byKey(
                PageStorageKey('exchange-${fixture.controller.currency.id}'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(fractionalText, findsWidgets);
      if (Platform.isWindows) {
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/exchanges_listing_estimate.png'),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'rare ingredient recipes keep their previous page and parent calculation',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      final parent = fixture.controller.quotes.firstWhere(
        (q) => q.ingredients.any((i) => i.name == 'Refined Oatmeal'),
      );
      fixture.controller.preferences.craftSearch = parent.recipeName;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, parent.recipeName);
      await _settleImages(tester);
      final link = find.byKey(
        const ValueKey('ingredient-recipe-Refined Oatmeal'),
      );
      await tester.ensureVisible(link);
      await tester.tap(link);
      await _settleImages(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ingredient-recipe-page')),
        findsOneWidget,
      );
      expect(
        find.text('Rare result from Oatmeal. Not guaranteed.'),
        findsNothing,
      );
      expect(
        find.text(
          'Just the recipe. Profit still uses the cost of buying this item.',
        ),
        findsNothing,
      );
      final rare = fixture.controller.inspectRecipe(
        recipe: fixture.controller.catalog.recipe(
          CraftMode.cooking,
          'Oatmeal',
        )!,
        itemName: 'Refined Oatmeal',
      );
      expect(rare.isRareOutput, isTrue);
      expect(rare.quote.expectedOutput, isNull);
      expect(rare.quote.listingRevenue, isNull);
      expect(rare.quote.listingProfit, isNull);
      expect(rare.quote.totalCost, greaterThan(0));
      _expectInspectionCalculation(tester, rare);
      if (Platform.isWindows) {
        await expectLater(
          find.byKey(const ValueKey('opportunities-capture')),
          matchesGoldenFile('goldens/rare_ingredient_recipe.png'),
        );
      }
      await _openCalculationInfo(tester);
      _expectMetricText(
        tester,
        find.byType(Dialog).last,
        'Expected output',
        '—',
      );
      expect(
        find.textContaining(
          'Refined Oatmeal is a rare result of Oatmeal. These are the ingredient costs for one craft.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Profit is left blank because its chance to appear is not known.',
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleImages(tester);
      expect(find.byType(Dialog), findsOneWidget);
      final innerLinks = find.descendant(
        of: find.byKey(const ValueKey('ingredient-recipe-page')),
        matching: find.byWidgetPredicate(
          (w) => w is InkWell && '${w.key}'.contains('ingredient-recipe-'),
        ),
      );
      expect(innerLinks, findsWidgets);
      await tester.tap(innerLinks.first);
      await _settleImages(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ingredient-recipe-page')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      _expectInspectionCalculation(tester, rare);
      expect(
        find.byKey(const ValueKey('ingredient-recipe-crumb:1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      expect(
        find.byKey(const ValueKey('ingredient-recipe-page')),
        findsNothing,
      );
      expect(find.text('Ingredients'), findsWidgets);
      final after = fixture.controller.quotes.firstWhere(
        (q) => q.recipeName == parent.recipeName,
      );
      expect(after, same(parent));
      expect(after.listingProfit, parent.listingProfit);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets(
      'Margoria recipe trail goes back one level at $scale text scale',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scale == 1 ? const Size(1280, 820) : const Size(900, 700),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false),
        ))!;
        fixture.controller.preferences.craftSearch = 'Margoria Seafood Meal';
        final parent = fixture.controller.quotes.firstWhere(
          (quote) => quote.recipeName == 'Margoria Seafood Meal',
        );
        final plannerBefore =
            fixture.harness.bundle.controller.documentSnapshot;
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Margoria Seafood Meal');
        await _openIngredient(tester, 'Butter-roasted Lobster');
        await _openIngredient(tester, 'Butter');
        await _openIngredient(tester, 'Cream');
        _expectRecipeTrail(tester, const [
          'Margoria Seafood Meal',
          'Butter-roasted Lobster',
          'Butter',
          'Cream',
        ]);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Milk'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-Milk')),
          findsNothing,
          reason: 'A raw ingredient is a leaf, not an empty recipe page.',
        );
        expect(tester.takeException(), isNull);
        if (Platform.isWindows) {
          await expectLater(
            find.byKey(const ValueKey('opportunities-capture')),
            matchesGoldenFile(
              'goldens/margoria_recipe_trail_${scale == 1 ? '1280' : '900_200'}.png',
            ),
          );
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await _settleImages(tester);
        _expectRecipeTrail(tester, const [
          'Margoria Seafood Meal',
          'Butter-roasted Lobster',
          'Butter',
        ]);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await _settleImages(tester);
        _expectRecipeTrail(tester, const [
          'Margoria Seafood Meal',
          'Butter-roasted Lobster',
        ]);

        await _openIngredient(tester, 'Butter');
        await _openIngredient(tester, 'Cream');
        final crumb = find.byKey(const ValueKey('ingredient-recipe-crumb:1'));
        await tester.ensureVisible(crumb);
        await tester.tap(crumb);
        await _settleImages(tester);
        _expectRecipeTrail(tester, const [
          'Margoria Seafood Meal',
          'Butter-roasted Lobster',
        ]);
        await tester.tap(
          find.byKey(const ValueKey('ingredient-recipe-crumb:0')),
        );
        await _settleImages(tester);
        expect(find.text('Ingredients'), findsWidgets);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-trail')),
          findsNothing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Ingredients'), findsWidgets);
        expect(
          fixture.controller.quotes.firstWhere(
            (quote) => quote.recipeName == parent.recipeName,
          ),
          same(parent),
        );
        expect(
          fixture.harness.bundle.controller.documentSnapshot,
          same(plannerBefore),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
    );
  }

  _glassTestWidgets(
    'nested Back restores the previous recipe scroll position',
    (tester) async {
      configureApplicationTestSurface(
        tester,
        const Size(900, 700),
        textScaleFactor: 2,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      fixture.controller.preferences.craftSearch = 'Margoria Seafood Meal';
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, 'Margoria Seafood Meal');
      await _openIngredient(tester, 'Butter-roasted Lobster');
      final butter = find.byKey(const ValueKey('ingredient-recipe-Butter'));
      await tester.ensureVisible(butter);
      await _settleImages(tester);
      Finder previousScroller() => find
          .descendant(
            of: find.byKey(const PageStorageKey('Butter-roasted Lobster')),
            matching: find.byType(Scrollable),
          )
          .first;
      final offset = tester
          .state<ScrollableState>(previousScroller())
          .position
          .pixels;
      expect(offset, greaterThan(0));
      await tester.tap(butter);
      await _settleImages(tester);
      _expectRecipeTrail(tester, const [
        'Margoria Seafood Meal',
        'Butter-roasted Lobster',
        'Butter',
      ]);
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      expect(
        tester.state<ScrollableState>(previousScroller()).position.pixels,
        closeTo(offset, .1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets('recipe variants survive deeper navigation and returning', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1280, 820));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(exchange: false),
    ))!;
    fixture.controller.change((preferences) {
      preferences.mode = CraftMode.processing;
      preferences.craftSearch = 'Concentrated Magical Black Gem';
    }, assemble: true);
    await tester.pumpWidget(_host(fixture.controller));
    await _settleWork(
      tester,
      fixture.controller.refresh(
        recipe: fixture.controller.recipes['Concentrated Magical Black Gem'],
      ),
    );
    await _settleCalculation(tester, fixture.controller);
    await _settleImages(tester);
    final recipe = fixture.controller.catalog.recipe(
      CraftMode.processing,
      'Black Gem',
    )!;
    await _settleWork(tester, fixture.controller.refresh(recipe: recipe));
    await _settleCalculation(tester, fixture.controller);
    final parent = fixture.controller.quotes.firstWhere(
      (quote) => quote.recipeName == 'Concentrated Magical Black Gem',
    );
    await _openCalculation(tester, parent.recipeName);
    await _openIngredient(tester, 'Black Gem');
    final standard = fixture.controller.inspectRecipe(recipe: recipe);
    _expectInspectionCalculation(tester, standard);
    final hundred = _buttonWithText('100×');
    await tester.ensureVisible(hundred);
    await tester.tap(hundred);
    await _settleImages(tester);
    expect(tester.widget<AppButton>(hundred).selected, isTrue);
    final variant = recipe.variants.firstWhere(
      (variant) => variant.batchMultiplier == 100,
    );
    final batch = fixture.controller.inspectRecipe(
      recipe: recipe,
      selectedVariantId: variant.id,
    );
    expect(batch.quote.crafts, 1);
    expect(batch.quote.batchMultiplier, 100);
    expect(batch.quote.expectedOutput, 100);
    expect(batch.quote.totalCost, greaterThan(standard.quote.totalCost!));
    expect(
      batch.quote.ingredients.any((item) => item.name == 'Pure Powder Reagent'),
      isTrue,
    );
    _expectInspectionCalculation(tester, batch);
    await _openIngredient(tester, 'Pure Powder Reagent');
    await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
    await _settleImages(tester);
    expect(tester.widget<AppButton>(hundred).selected, isTrue);
    expect(find.text('Pure Powder Reagent'), findsOneWidget);
    _expectInspectionCalculation(tester, batch);
    await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
    await _settleImages(tester);
    expect(find.text('Ingredients'), findsWidgets);
    final restored = fixture.controller.quotes.firstWhere(
      (quote) => quote.recipeName == parent.recipeName,
    );
    expect(restored.selectedVariantId, parent.selectedVariantId);
    expect(restored.crafts, parent.crafts);
    expect(restored.expectedOutput, parent.expectedOutput);
    expect(restored.totalCost, parent.totalCost);
    expect(restored.listingRevenue, parent.listingRevenue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleWork(tester, fixture.dispose());
  });

  for (final view in [
    (theme: 'plain-cobalt', size: const Size(1280, 820), scale: 1.0),
    (theme: 'sakura-night-garden', size: const Size(1200, 900), scale: 1.5),
  ]) {
    _glassTestWidgets('Tenacity recipe switches ${view.theme}', (tester) async {
      configureApplicationTestSurface(
        tester,
        view.size,
        textScaleFactor: view.scale,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          backgroundId: view.theme,
          pricesByName: const {
            'Perfume of Tenacity': 40000000,
            'Perfume of Deep Sea': 28000000,
            'Shining Powder': 70000,
            'Caphras Essence': 930000,
            "Rusalka's Coral": 900000,
          },
        ),
      ))!;
      final controller = fixture.controller;
      controller.change((p) {
        p.mode = CraftMode.processing;
        p.craftSearch = 'Immortal: Perfume of Tenacity';
      }, assemble: true);
      await tester.pumpWidget(_host(controller));
      await _settleWork(
        tester,
        controller.refresh(
          recipe: controller.recipes['Immortal: Perfume of Tenacity'],
        ),
      );
      await _settleCalculation(tester, controller);
      await _settleImages(tester);
      final parent = controller.quotes.firstWhere(
        (q) => q.recipeName == 'Immortal: Perfume of Tenacity',
      );
      final saved = fixture.harness.bundle.controller.documentSnapshot;
      await _openCalculation(tester, parent.recipeName);
      await _openIngredient(tester, 'Perfume of Tenacity');
      await _settleDepth(tester, controller);
      await _settleImages(tester);
      final recipeA = find.byKey(const ValueKey('opportunity-recipe-route:0'));
      final recipeB = find.byKey(const ValueKey('opportunity-recipe-route:1'));
      final ten = find.byKey(const ValueKey('opportunity-recipe-batch:10'));
      final one = find.byKey(const ValueKey('opportunity-recipe-batch:1'));
      expect(tester.widget<AppButton>(recipeA).selected, isTrue);
      expect(
        tester.getSize(recipeA).height,
        closeTo(tester.getSize(ten).height, .01),
      );
      expect(tester.getSize(recipeA).height, greaterThanOrEqualTo(37));
      await _captureSubstitutes(
        tester,
        'recipe-a-${view.theme}',
        region: find.byType(Dialog),
      );
      await tester.ensureVisible(ten);
      await tester.tap(ten);
      await _settleImages(tester);
      expect(tester.widget<AppButton>(ten).selected, isTrue);
      expect(find.text("Ibellab's Essence"), findsOneWidget);
      await tester.tap(one);
      await _settleImages(tester);
      await tester.enterText(_detailCraftCount(), '3');
      final price = _inlineNumber('opportunity-custom-sale-price');
      await tester.enterText(price, '42000000');
      await _settleImages(tester);
      final coralId = controller.catalog.bundledMarketId("Rusalka's Coral")!;
      fixture.requests.clear();
      await tester.ensureVisible(recipeB);
      await tester.tap(recipeB);
      await _settleDepth(tester, controller);
      await _settleImages(tester);
      expect(tester.widget<AppButton>(recipeB).selected, isTrue);
      expect(find.text("Rusalka's Coral"), findsOneWidget);
      expect(find.text('Perfume of Deep Sea'), findsNothing);
      expect(ten, findsNothing);
      expect(
        fixture.requests.any((request) => request.endsWith(':$coralId')),
        isTrue,
      );
      expect(
        tester.widget<TextField>(_detailCraftCount()).controller!.text,
        '3',
      );
      expect(
        tester.widget<TextField>(price).controller!.text.replaceAll('.', ''),
        '42000000',
      );
      final coral = controller.catalog.recipe(
        CraftMode.alchemy,
        'Perfume of Tenacity',
      )!;
      final inspection = controller.inspectRecipe(
        recipe: coral,
        crafts: 3,
        customSalePrice: 42000000,
      );
      _expectInspectionCalculation(tester, inspection);
      expect(
        inspection.quote.ingredients
            .firstWhere((i) => i.name == "Rusalka's Coral")
            .quantity,
        90,
      );
      await _captureSubstitutes(
        tester,
        'recipe-b-${view.theme}',
        region: find.byType(Dialog),
      );
      await _openIngredient(tester, 'Pure Powder Reagent');
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      expect(tester.widget<AppButton>(recipeB).selected, isTrue);
      expect(
        tester.widget<TextField>(_detailCraftCount()).controller!.text,
        '3',
      );
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      expect(
        controller.quotes.firstWhere((q) => q.recipeName == parent.recipeName),
        same(parent),
      );
      expect(fixture.harness.bundle.controller.documentSnapshot, same(saved));
      expect(controller.preferences.mode, CraftMode.processing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    });
  }

  _glassTestWidgets(
    'root recipe switch clears the old batch without saved edits',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 900));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      final controller = fixture.controller;
      controller.change((p) {
        p.mode = CraftMode.processing;
        p.craftSearch = 'Perfume of Tenacity';
      }, assemble: true);
      await tester.pumpWidget(_host(controller));
      final recipe = controller.recipes['Perfume of Tenacity']!;
      await _settleWork(tester, controller.refresh(recipe: recipe));
      await _settleCalculation(tester, controller);
      await _settleImages(tester);
      await _openCalculation(tester, recipe.name);
      final saved = fixture.harness.bundle.controller.documentSnapshot;
      final quote = controller.quotes.firstWhere(
        (q) => q.recipeName == recipe.name,
      );
      await tester.tap(
        find.byKey(const ValueKey('opportunity-recipe-batch:10')),
      );
      await _settleImages(tester);
      expect(find.text("Ibellab's Essence"), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('opportunity-recipe-route:1')),
      );
      await _settleDepth(tester, controller);
      await _settleImages(tester);
      final coral = controller.catalog.recipe(CraftMode.alchemy, recipe.name)!;
      final inspection = controller.inspectRecipe(recipe: coral);
      _expectInspectionCalculation(
        tester,
        inspection,
        page: find.byKey(const ValueKey('root-recipe-page')),
      );
      expect(find.text("Rusalka's Coral"), findsOneWidget);
      expect(find.text("Ibellab's Essence"), findsNothing);
      expect(
        find.byKey(const ValueKey('opportunity-recipe-batch:10')),
        findsNothing,
      );
      expect(fixture.harness.bundle.controller.documentSnapshot, same(saved));
      expect(
        controller.quotes.firstWhere((q) => q.recipeName == recipe.name),
        same(quote),
      );
      await tester.tap(
        find.byKey(const ValueKey('opportunity-recipe-route:0')),
      );
      await _settleImages(tester);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey('opportunity-recipe-batch:1')),
            )
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'nested calculations use source mastery and their own market without changing the parent',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(
          exchange: false,
          pricesByName: const {'Cream': 2300},
        ),
      ))!;
      fixture.harness.bundle.controller.modes[CraftMode.cooking]!.updateState(
        (state) => state.copyWith(cookingMastery: 925),
      );
      fixture.harness.bundle.controller.modes[CraftMode.processing]!
          .updateState((state) => state.copyWith(processingMastery: 2750));
      fixture.controller.change((preferences) {
        preferences.craftSearch = 'Margoria Seafood Meal';
        preferences.crafts = 7;
        preferences.extraCostPerRun = 1200;
        preferences.extraCostPerCraft = 25;
      });
      await tester.pumpWidget(_host(fixture.controller));
      final recipe = fixture.controller.catalog.recipe(
        CraftMode.processing,
        'Cream',
      )!;
      await _settleWork(tester, fixture.controller.refresh(recipe: recipe));
      await _settleCalculation(tester, fixture.controller);
      await _settleImages(tester);
      final parent = fixture.controller.quotes.firstWhere(
        (quote) => quote.recipeName == 'Margoria Seafood Meal',
      );
      final plannerBefore = fixture.harness.bundle.controller.documentSnapshot;
      final child = fixture.controller.inspectRecipe(recipe: recipe);
      expect(child.sourceMode, CraftMode.processing);
      expect(child.mastery, 2750);
      expect(child.quote.crafts, 1);
      expect(child.quote.extraCost, 0);
      expect(child.quote.outputMarket!.basePrice, 2300);
      expect(child.quote.listingProfit, isNotNull);
      expect(parent.crafts, 1);
      expect(parent.extraCost, 0);

      await _openCalculation(tester, parent.recipeName);
      await _openIngredient(tester, 'Butter-roasted Lobster');
      await _openIngredient(tester, 'Butter');
      await _openIngredient(tester, 'Cream');
      _expectInspectionCalculation(tester, child);
      await _openCalculationInfo(tester);
      final info = find.byType(Dialog).last;
      _expectMetricText(tester, info, 'Mastery', '2750');
      _expectMetricText(tester, info, 'Complete crafts', '1');
      _expectMetricText(
        tester,
        info,
        'Expected output',
        formatQuantity(child.quote.expectedOutput!),
      );
      expect(
        find.text('1.375 silver in extra costs is included.'),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleImages(tester);
      final market = find.byKey(const ValueKey('craft-market-details'));
      await tester.ensureVisible(market);
      await tester.tap(market);
      await _settleImages(tester);
      _expectMetricText(tester, find.byType(Dialog).last, 'Price', '2.300');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleImages(tester);
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-crumb:0')));
      await _settleImages(tester);
      expect(
        find.byKey(ValueKey('craft-result:${parent.recipeName}')),
        findsOneWidget,
      );
      expect(
        fixture.controller.quotes.firstWhere(
          (quote) => quote.recipeName == parent.recipeName,
        ),
        same(parent),
      );
      expect(
        fixture.harness.bundle.controller.documentSnapshot,
        same(plannerBefore),
      );
      expect(fixture.controller.preferences.mode, CraftMode.cooking);
      expect(fixture.controller.preferences.crafts, 7);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'cyclic recipe links return to an ancestor instead of stacking',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      fixture.controller.preferences.craftSearch = 'Margoria Seafood Meal';
      // A deliberately cyclic, in-memory reference tests bad custom recipe data.
      // Neither the real catalog nor the user's planner is changed.
      fixture.controller.recipes = {
        ...fixture.controller.recipes,
        'Cream': _recipeWithIngredients(
          fixture.controller.recipes['Cream']!,
          ['Butter', 'Margoria Seafood Meal'],
          // This intentionally custom formula belongs to the active source
          // mode; a Processing reference must not override that mode's recipe.
          type: CraftMode.cooking.key,
        ),
      };
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, 'Margoria Seafood Meal');
      await _openIngredient(tester, 'Butter-roasted Lobster');
      await _openIngredient(tester, 'Butter');
      await _openIngredient(tester, 'Cream');
      await _openIngredient(tester, 'Butter');
      _expectRecipeTrail(tester, const [
        'Margoria Seafood Meal',
        'Butter-roasted Lobster',
        'Butter',
      ]);
      await _openIngredient(tester, 'Cream');
      await _openIngredient(tester, 'Margoria Seafood Meal');
      expect(find.text('Ingredients'), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ingredient-recipe-trail')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'preorder counts do not cap listing-value exchange bundles',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () =>
            _Fixture.create(exchange: true, missingStock: true, buyerCount: 1),
      ))!;
      fixture.controller.change((preferences) {
        preferences.currencyId = 'dormant-fairys-breath';
      });
      await tester.pumpWidget(_host(fixture.controller));
      await _settleWork(tester, fixture.controller.refresh());
      await _settleCalculation(tester, fixture.controller);
      await _settleImages(tester);
      final quote = fixture.controller.exchangeQuotes.firstWhere(
        (quote) => quote.route.id == 'dormant-fairy-sharp',
      );
      await _settleWork(
        tester,
        fixture.controller.ensureMarketDepth([
          for (final reward in quote.route.rewards)
            if (reward.item?.marketable == true) '${reward.item!.id}',
        ]),
      );
      await _settleCalculation(tester, fixture.controller);
      await _settleImages(tester);
      expect(quote.exchanges, 1);
      expect(quote.netProceeds, isNotNull);
      expect(quote.hasListingEstimate, isFalse);
      expect(find.text('Stock −1'), findsWidgets);
      expect(find.text('Estimate · not enough buyers'), findsNothing);
      expect(find.textContaining('no buyers'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'different craftable ingredients return to the same opportunity',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      bool hasRecipe(String name) => CraftMode.values.any(
        (mode) =>
            fixture.controller.catalog.recipe(mode, name)?.isCraftable == true,
      );
      final parent = fixture.controller.quotes.firstWhere(
        (quote) =>
            quote.ingredients
                .where((ingredient) => hasRecipe(ingredient.name))
                .length >=
            2,
      );
      final names = parent.ingredients
          .where((ingredient) => hasRecipe(ingredient.name))
          .take(2)
          .map((ingredient) => ingredient.name)
          .toList();
      fixture.controller.preferences.craftSearch = parent.recipeName;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, parent.recipeName);
      await _settleImages(tester);
      for (final name in names) {
        final link = find.byKey(ValueKey('ingredient-recipe-$name'));
        expect(
          link,
          findsOneWidget,
          reason: '${parent.recipeName} must link the recipe for $name',
        );
        await tester.ensureVisible(link);
        await tester.tap(link);
        await _settleImages(tester);
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-page')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
        await _settleImages(tester);
        expect(find.text('Ingredients'), findsWidgets);
        expect(
          fixture.controller.quotes.firstWhere(
            (quote) => quote.recipeName == parent.recipeName,
          ),
          same(parent),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'search and amounts survive switching while legacy sale modes stay intact',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      final plannerBefore = fixture.harness.bundle.controller.documentSnapshot;
      final search = find.descendant(
        of: find.byKey(const ValueKey('craft-search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'Beer');
      await tester.pump();
      expect(
        fixture.controller.visibleQuotes.every(
          (quote) => quote.recipeName.contains('Beer'),
        ),
        isTrue,
      );
      await tester.tap(find.text('Exchanges').first);
      await tester.pump();
      expect(fixture.controller.preferences.section, 'exchanges');
      expect(fixture.controller.exchangeSaleMode, ExchangeSaleMode.listing);
      expect(fixture.controller.preferences.exchangeSale, 'buyers');
      expect(find.text('List for sale'), findsNothing);
      expect(find.text('Current buyers'), findsNothing);
      await tester.tap(find.text('Crafting').first);
      await tester.pump();
      expect(fixture.controller.preferences.craftSearch, 'Beer');
      expect(tester.widget<TextField>(search).controller!.text, 'Beer');
      expect(fixture.controller.preferences.craftSale, 'buyers');
      expect(fixture.controller.craftSaleMode, OpportunitySaleMode.listing);
      await tester.tap(find.text('Exchanges').first);
      await tester.pump();
      expect(fixture.controller.preferences.exchangeSale, 'buyers');
      expect(fixture.controller.owned, 10000);
      expect(
        identical(
          fixture.harness.bundle.controller.documentSnapshot,
          plannerBefore,
        ),
        isTrue,
        reason:
            'Opportunities navigation and estimates must not edit the planner.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'glass cards have distinct keyboard actions for opening and copying',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      final card = find.byKey(const ValueKey('craft-card:Beer'));
      expect(card, findsOneWidget);
      expect(
        find.textContaining(RegExp(r'^\d+ recipes?$')),
        findsOneWidget,
        reason: 'The overview keeps only the compact recipe count.',
      );
      expect(find.textContaining('Per craft'), findsNothing);
      final arrow = find.byKey(const ValueKey('craft-expand-button:Beer'));
      expect(arrow, findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 40 && !_focusIsWithin(tester, card);
        attempt++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        _focusIsWithin(tester, card),
        isTrue,
        reason: 'The whole recipe card must be reachable by Tab.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settleImages(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.byKey(const ValueKey('craft-inline-details:Beer')),
        findsOneWidget,
      );
      expect(_focusIsWithin(tester, card), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _focusIsWithin(tester, card),
        isTrue,
        reason: 'The new name-copy action has its own accessible Tab stop.',
      );
      String? copiedName;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedName = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(copiedName, 'Beer');
      expect(find.byType(Dialog), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _focusIsWithin(tester, card),
        isTrue,
        reason:
            'The silver amount retains its own full/compact keyboard toggle.',
      );
      await _openCalculation(tester, 'Beer');
      await _settleImages(tester);
      expect(find.byKey(const ValueKey('craft-result:Beer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'Codex sidebar owns applicable sorting across sections and resize',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, summaryOnly: true),
      ))!;
      try {
        fixture.controller.change((p) => p.craftSearch = 'Beer');
        await _settleCalculation(tester, fixture.controller);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final panes = tester.element(
          find.byKey(const ValueKey('opportunities-panes')),
        );
        for (final width in [1280.0, 900.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 820);
          await _settleImages(tester);
          final sidebar = find.byKey(const ValueKey('opportunities-sidebar'));
          for (final section in ['crafting', 'best-use', 'exchanges']) {
            await tester.tap(
              find.byKey(
                ValueKey(
                  'opportunities-section-${section.replaceAll('-', ' ')}',
                ),
              ),
            );
            await _settleCalculation(tester, fixture.controller);
            await _settleImages(tester);
            final sort = find.byKey(const ValueKey('craft-sort-options'));
            if (section == 'exchanges') {
              expect(sort, findsNothing);
              continue;
            }
            expect(sort, findsOneWidget);
            expect(
              find.descendant(of: sidebar, matching: sort),
              width >= 1120 ? findsOneWidget : findsNothing,
            );
            for (final key in ['preorders', 'profit']) {
              final control = find.byKey(ValueKey('craft-sort-$key'));
              expect(control, findsOneWidget);
              await tester.ensureVisible(control);
              await tester.tap(control);
              await _settleCalculation(tester, fixture.controller);
              expect(fixture.controller.activeCraftSort, key);
              final ascending = fixture.controller.preferences.craftAscending;
              await tester.tap(control);
              await _settleCalculation(tester, fixture.controller);
              expect(fixture.controller.preferences.craftAscending, !ascending);
            }
            expect(
              find.byKey(const ValueKey('craft-sort-exp')),
              section == 'crafting' ? findsOneWidget : findsNothing,
            );
            expect(
              tester.element(find.byKey(const ValueKey('opportunities-panes'))),
              same(panes),
            );
          }
          expect(fixture.controller.preferences.craftSearch, 'Beer');
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'Codex sidebar sorting remains reachable in a short window',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 480));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false, summaryOnly: true),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final exp = find.byKey(const ValueKey('craft-sort-exp'));
        await tester.ensureVisible(exp);
        await tester.tap(exp);
        await _settleImages(tester);
        expect(fixture.controller.activeCraftSort, 'exp');
        expect(exp.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const ValueKey('popover:craft-exp-filter')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settleImages(tester);
        expect(
          find.byKey(const ValueKey('opportunities-finish-moon')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'Codex rail keeps live craft modes without conflicting theme controls',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        final sidebar = find.byKey(const ValueKey('opportunities-sidebar'));
        final panes = tester.element(
          find.byKey(const ValueKey('opportunities-panes')),
        );
        for (final mode in [
          CraftMode.alchemy,
          CraftMode.processing,
          CraftMode.cooking,
        ]) {
          final control = find.byKey(ValueKey('craft-mode-${mode.name}'));
          expect(
            find.descendant(of: sidebar, matching: control),
            findsOneWidget,
          );
          await tester.tap(control);
          await _settleCalculation(tester, fixture.controller);
          await _settleImages(tester);
          expect(fixture.controller.preferences.mode, mode);
          expect(fixture.controller.recipes, isNotEmpty);
          _expectCraftControlPlacement(tester);
        }
        for (final finish in ['moon', 'bronze']) {
          expect(
            find.byKey(ValueKey('opportunities-finish-$finish')),
            findsNothing,
          );
        }
        tester.view.physicalSize = const Size(900, 700);
        await _settleImages(tester);
        _expectWorkbenchGeometry(tester);
        for (final mode in ['cooking', 'alchemy', 'processing']) {
          expect(find.byKey(ValueKey('craft-mode-$mode')), findsOneWidget);
        }
        for (final finish in ['moon', 'bronze']) {
          expect(
            find.byKey(ValueKey('opportunities-finish-$finish')),
            findsNothing,
          );
        }
        expect(
          tester.element(find.byKey(const ValueKey('opportunities-panes'))),
          same(panes),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets(
    'raised section controls keep selection and keyboard actions',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1280, 820));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      final semantics = tester.ensureSemantics();
      final brand = tester.widget<Image>(
        find.byKey(const ValueKey('opportunities-brand-icon')),
      );
      expect(brand.width, 30);
      expect(brand.height, 30);
      expect(brand.filterQuality, FilterQuality.high);
      expect(
        (brand.image as AssetImage).assetName,
        'assets/opportunities/items/66771.webp',
      );
      final navigationPosition = tester.getTopLeft(
        find.byKey(const ValueKey('opportunities-sections')),
      );
      const sections = ['crafting', 'exchanges', 'best-use'];
      Finder sectionControl(String section) => find.byKey(
        ValueKey('opportunities-section-${section.replaceAll('-', ' ')}'),
      );
      for (final section in [...sections, 'crafting']) {
        final control = sectionControl(section);
        expect(tester.getSize(control).height, greaterThanOrEqualTo(40));
        final detector = tester.widget<FocusableActionDetector>(
          find.descendant(
            of: control,
            matching: find.byType(FocusableActionDetector),
          ),
        );
        detector.focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _settleImages(tester);
        expect(fixture.controller.preferences.section, section);
        expect(
          tester.getTopLeft(
            find.byKey(const ValueKey('opportunities-sections')),
          ),
          navigationPosition,
          reason: 'Section choices stay put when Mastery appears or hides.',
        );
        for (final name in sections) {
          final tab = sectionControl(name);
          expect(tester.widget<AppButton>(tab).selected, name == section);
          final flags = tester
              .getSemantics(tab)
              .getSemanticsData()
              .flagsCollection;
          expect(flags.isButton, isTrue);
          expect(
            flags.isSelected,
            name == section ? Tristate.isTrue : Tristate.isFalse,
          );
        }
      }
      semantics.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
  );

  _glassTestWidgets(
    'workbench rail retains independent pane scrolling through resize',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      try {
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        Finder scroller(String key) => find
            .descendant(
              of: find.byKey(PageStorageKey(key)),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first;
        final craftScroll = scroller('craft-opportunities');
        final craftState = tester.state<ScrollableState>(craftScroll);
        await tester.drag(craftScroll, const Offset(0, -500));
        await _settleImages(tester);
        final craftOffset = craftState.position.pixels;
        expect(craftOffset, greaterThan(0));
        _expectWorkbenchGeometry(tester);
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('opportunities-sections')),
            matching: find.text('Exchanges'),
          ),
        );
        await _settleImages(tester);
        final exchangeScroll = scroller(
          'exchange-${fixture.controller.currency.id}',
        );
        final exchangeState = tester.state<ScrollableState>(exchangeScroll);
        await tester.drag(exchangeScroll, const Offset(0, -350));
        await _settleImages(tester);
        final exchangeOffset = exchangeState.position.pixels;
        expect(exchangeOffset, greaterThan(0));
        for (final size in [const Size(900, 700), const Size(1200, 752)]) {
          tester.view.physicalSize = size;
          await _settleImages(tester);
          _expectWorkbenchGeometry(tester);
          expect(
            tester.state<ScrollableState>(exchangeScroll),
            same(exchangeState),
          );
        }
        expect(exchangeState.position.pixels, closeTo(exchangeOffset, .01));
        await tester.tap(find.text('Crafting').first);
        await _settleImages(tester);
        expect(tester.state<ScrollableState>(craftScroll), same(craftState));
        expect(craftState.position.pixels, closeTo(craftOffset, .01));
        await tester.tap(find.text('Exchanges').first);
        await _settleImages(tester);
        expect(
          tester.state<ScrollableState>(exchangeScroll),
          same(exchangeState),
        );
        expect(exchangeState.position.pixels, closeTo(exchangeOffset, .01));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      }
    },
  );

  _glassTestWidgets('responsive toolbar preserves search focus and caret', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1280, 820));
    final fixture = (await tester.runAsync(
      () => _Fixture.create(exchange: false),
    ))!;
    await tester.pumpWidget(_host(fixture.controller));
    await _settleImages(tester);
    final search = find.descendant(
      of: find.byKey(const ValueKey('craft-search')),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'Beer');
    await tester.pump();
    final textController = tester.widget<TextField>(search).controller!;
    const selection = TextSelection(baseOffset: 1, extentOffset: 3);
    textController.selection = selection;
    final editable = find.descendant(
      of: search,
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(editable);
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    expect(state.widget.focusNode.hasFocus, isTrue);
    for (final size in [const Size(900, 700), const Size(1280, 820)]) {
      tester.view.physicalSize = size;
      await _settleImages(tester);
      expect(tester.state<EditableTextState>(editable), same(state));
      expect(tester.widget<TextField>(search).controller, same(textController));
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(state.widget.focusNode.hasFocus, isTrue);
      expect(textController.selection, selection);
      expect(textController.text, 'Beer');
      expect(fixture.controller.preferences.craftSearch, 'Beer');
      expect(tester.getRect(search).right, lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    }
    _expectCraftControlPlacement(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleWork(tester, fixture.dispose());
  });

  for (final scenario in [
    (name: 'Beer', mode: CraftMode.cooking, batches: false),
    (name: 'Corruption Draught', mode: CraftMode.processing, batches: true),
  ]) {
    _glassTestWidgets(
      '${scenario.name} overview ignores legacy quantity and details scale locally',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1280, 820));
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false),
        ))!;
        fixture.controller.change((preferences) {
          preferences.mode = scenario.mode;
          preferences.craftSearch = scenario.name;
          preferences.crafts = 2;
        }, assemble: true);
        await tester.pumpWidget(_host(fixture.controller));
        await _settleWork(
          tester,
          fixture.controller.refresh(
            recipe: fixture.controller.recipes[scenario.name],
          ),
        );
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        final quote = fixture.controller.quotes.firstWhere(
          (quote) => quote.recipeName == scenario.name,
        );
        expect(quote.crafts, 1);
        expect(quote.extraCost, 0);
        expect(find.textContaining('1 recipes'), findsNothing);
        if (scenario.name == 'Beer') {
          expect(find.text('1 recipe'), findsOneWidget);
          expect(find.text('1 recipe · 2 crafts'), findsNothing);
        }
        expect(quote.listingProfit, isNotNull);
        expect(
          quote.listingProfit,
          closeTo(quote.listingRevenue! - quote.totalCost!, .001),
        );
        final card = find.byKey(ValueKey('craft-card:${scenario.name}'));
        final summary = find.byKey(ValueKey('craft-summary:${scenario.name}'));
        expect(
          find.descendant(of: summary, matching: find.text('per item')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: summary,
            matching: find.text(
              _cardSilver(
                quote.listingProfit! / quote.expectedOutput!,
                signed: true,
              ),
            ),
          ),
          findsOneWidget,
        );
        for (final label in [
          'Profit',
          'Investment',
          'Average yield',
          'Crafts available',
        ]) {
          expect(
            find.descendant(of: card, matching: find.text(label)),
            findsNothing,
          );
        }
        _expectWorkbenchCard(tester, scenario.name);
        await tester.tap(
          find.byKey(ValueKey('craft-expand-button:${scenario.name}')),
        );
        await _settleImages(tester);
        final details = find.byKey(
          ValueKey('craft-inline-details:${scenario.name}'),
        );
        expect(
          tester.getSize(details).width,
          closeTo(tester.getSize(card).width, .01),
        );
        expect(
          find.descendant(
            of: details,
            matching: find.text('Buy missing materials'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: details,
            matching: find.text(
              _cardSilver(-quote.calculationInputCost! / quote.expectedOutput!),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: details,
            matching: find.text(
              _cardSilver(quote.listingRevenue! / quote.expectedOutput!),
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(Dialog), findsNothing);
        await _openCalculation(tester, scenario.name);
        final result = find.byKey(ValueKey('craft-result:${scenario.name}'));
        expect(result, findsOneWidget);
        final money = find.byKey(const ValueKey('craft-money-summary'));
        expect(
          find.descendant(of: money, matching: find.text('Sale after tax')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: money,
            matching: find.text(
              '${formatCompactOpportunitySilver(quote.listingRevenue!)} silver',
            ),
          ),
          findsOneWidget,
        );
        await tester.enterText(_detailCraftCount(), '2');
        await _settleImages(tester);
        final scoped = fixture.controller.inspectRecipe(
          recipe: fixture.controller.recipes[scenario.name]!,
          crafts: 2,
        );
        _expectInspectionCalculation(tester, scoped, page: find.byType(Dialog));
        expect(
          fixture.controller.quotes
              .firstWhere((item) => item.recipeName == scenario.name)
              .crafts,
          1,
        );
        expect(fixture.controller.preferences.crafts, 2);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settleImages(tester);
        fixture.controller.change((preferences) => preferences.crafts = 1);
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        final single = fixture.controller.quotes.firstWhere(
          (quote) => quote.recipeName == scenario.name,
        );
        if (scenario.name == 'Beer') {
          expect(find.text('1 recipe'), findsOneWidget);
          expect(find.textContaining('Per craft'), findsNothing);
        }
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              '${formatQuantity(single.expectedOutput!)} items per batch',
            ),
          ),
          findsNothing,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('craft-per-item-profit:${scenario.name}')),
              )
              .data,
          _cardSilver(
            single.listingProfit! / single.expectedOutput!,
            signed: true,
          ),
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Makes ')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('1 craft')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
    );
  }

  _glassTestWidgets(
    'calculation popup stays readable at compact large text',
    (tester) async {
      configureApplicationTestSurface(
        tester,
        const Size(900, 700),
        textScaleFactor: 1.3,
      );
      final fixture = (await tester.runAsync(
        () => _Fixture.create(exchange: false),
      ))!;
      fixture.controller.preferences.craftSearch = 'Beer';
      await tester.pumpWidget(_host(fixture.controller));
      await _settleImages(tester);
      await _openCalculation(tester, 'Beer');
      await _settleImages(tester);
      expect(find.text('Ingredients'), findsWidgets);
      _expectIngredientColumns(tester, columns: 1);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('opportunities-capture')),
        matchesGoldenFile('goldens/craft_details_900_large.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
    },
    skip: !Platform.isWindows,
  );

  for (final missingStock in [false, true]) {
    _glassTestWidgets(
      'retired global costs stay saved without affecting ${missingStock ? 'estimated' : 'available'} profit',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1280, 820));
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false, missingStock: missingStock),
        ))!;
        try {
          fixture.controller.change((p) => p.craftSearch = 'Beer');
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          final baseline = fixture.controller.quotes.firstWhere(
            (q) => q.recipeName == 'Beer',
          );
          fixture.controller.change((p) {
            p.crafts = 2;
            p.extraCostPerRun = 1000;
            p.extraCostPerCraft = 25;
          });
          await _settleCalculation(tester, fixture.controller);
          final overview = fixture.controller.quotes.firstWhere(
            (q) => q.recipeName == 'Beer',
          );
          expect(overview.crafts, 1);
          expect(overview.extraCost, 0);
          expect(overview.listingProfit, baseline.listingProfit);
          expect(overview.totalCost, baseline.totalCost);
          expect(overview.hasEstimatedInputs, baseline.hasEstimatedInputs);
          for (final key in [
            'Crafts',
            'Silver / batch',
            'Silver / craft',
            'craft-filter-panel',
          ]) {
            expect(find.byKey(ValueKey(key)), findsNothing);
          }
          final recipe = fixture.controller.recipes['Beer']!;
          final local = fixture.controller.inspectRecipe(
            recipe: recipe,
            crafts: 2,
          );
          final costed = fixture.controller.inspectRecipe(
            recipe: recipe,
            crafts: 2,
            extraCostPerRun: 1000,
            extraCostPerCraft: 25,
          );
          expect(costed.quote.extraCost, 1050);
          expect(
            costed.quote.listingProfit,
            closeTo(local.quote.listingProfit! - 1050, .001),
          );
          final updated = fixture.controller.inspectRecipe(
            recipe: recipe,
            crafts: 2,
            extraCostPerRun: 1200,
            extraCostPerCraft: 25,
          );
          expect(updated.quote.extraCost, 1250);
          expect(
            updated.quote.listingProfit,
            closeTo(local.quote.listingProfit! - 1250, .001),
          );
          expect(updated.quote.estimatedSeconds, isNull);
          expect(find.byType(Dialog), findsNothing);
          await _openCalculation(tester, 'Beer');
          final count = _detailCraftCount();
          expect(tester.widget<TextField>(count).controller!.text, '1');
          await tester.enterText(count, '2');
          await _settleImages(tester);
          _expectInspectionCalculation(
            tester,
            local,
            page: find.byType(Dialog),
          );
          expect(
            fixture.controller.quotes
                .firstWhere((q) => q.recipeName == 'Beer')
                .crafts,
            1,
          );
          expect(fixture.controller.preferences.crafts, 2);
          expect(find.text('Ingredients + extras'), findsNothing);
          await _openCalculationInfo(tester);
          expect(
            find.text('1.050 silver in extra costs is included.'),
            findsNothing,
          );
          expect(
            find.text('1.250 silver in extra costs is included.'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await _settleWork(tester, fixture.controller.flush());
          final saved = (await tester.runAsync(
            () async =>
                jsonDecode(
                      await File(
                        '${fixture.harness.temporaryDirectory.path}/opportunities-settings.json',
                      ).readAsString(),
                    )
                    as Map<String, dynamic>,
          ))!;
          expect(saved['crafts'], 2);
          expect(saved['extraCostPerRun'], 1000);
          expect(saved['extraCostPerCraft'], 25);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }

  for (final scenario in [
    (size: const Size(600, 820), scale: 1.0),
    (size: const Size(900, 700), scale: 2.0),
  ]) {
    _glassTestWidgets(
      'ingredient cards stack at ${scenario.size.width} wide and ${scenario.scale} text',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scenario.size,
          textScaleFactor: scenario.scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false),
        ))!;
        fixture.controller.preferences.craftSearch = 'Beer';
        await tester.pumpWidget(_host(fixture.controller));
        await _settleImages(tester);
        await _openCalculation(tester, 'Beer');
        await _settleImages(tester);
        _expectIngredientColumns(tester, columns: 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
    );
  }

  for (final legacyEnabled in [true, false]) {
    _glassTestWidgets(
      'market bonuses update shared tax and profit with legacy enabled $legacyEnabled',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1280, 820));
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false),
        ))!;
        final app = fixture.harness.bundle.controller;
        app.updateDocument(
          (document) => document.copyWith(
            marketTax: MarketTax(
              enabled: legacyEnabled,
              extensions: const {'testUnknownField': 'keep'},
            ),
          ),
        );
        fixture.controller.preferences.craftSearch = 'Beer';
        await tester.pumpWidget(_host(fixture.controller));
        await _settleCalculation(tester, fixture.controller);
        await _settleImages(tester);
        final modesBefore = {
          for (final mode in CraftMode.values)
            mode: app.documentSnapshot.forMode(mode),
        };
        OpportunityQuote beer() => fixture.controller.quotes.firstWhere(
          (quote) => quote.recipeName == 'Beer',
        );
        final gross = beer().expectedOutput! * 100000;
        final cost = beer().totalCost!;
        expect(beer().listingRevenue, closeTo(gross * .65, .001));
        expect(find.textContaining('Tax off'), findsNothing);
        await tester.tap(find.text('Market · EU'));
        await _settleImages(tester);
        expect(find.text('Market settings'), findsOneWidget);
        expect(find.text('Apply market tax'), findsNothing);
        expect(find.text('Market tax · 35%'), findsOneWidget);
        expect(find.text('65% of each market sale'), findsOneWidget);

        for (final step in [
          (label: 'Value Pack', valuePack: true, ring: false, rate: .845),
          (
            label: 'Rich Merchant’s Ring',
            valuePack: true,
            ring: true,
            rate: .8775,
          ),
          (label: 'Value Pack', valuePack: false, ring: true, rate: .6825),
          (
            label: 'Rich Merchant’s Ring',
            valuePack: false,
            ring: false,
            rate: .65,
          ),
        ]) {
          await tester.tap(find.text(step.label));
          await _settleCalculation(tester, fixture.controller);
          final tax = app.marketTax.value;
          expect(tax.valuePack, step.valuePack);
          expect(tax.merchantRing, step.ring);
          expect(tax.enabled, legacyEnabled);
          expect(tax.extensions['testUnknownField'], 'keep');
          expect(app.documentSnapshot.marketTax, same(tax));
          expect(
            find.text(
              '${formatGroupedEditableQuantity(step.rate * 100)}% of each market sale',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Market tax · ${formatGroupedEditableQuantity((1 - step.rate) * 100)}%',
            ),
            findsOneWidget,
          );
          expect(beer().listingRevenue, closeTo(gross * step.rate, .001));
          expect(beer().listingProfit, closeTo(gross * step.rate - cost, .001));
          expect(beer().totalCost, cost);
          for (final mode in CraftMode.values) {
            expect(app.documentSnapshot.forMode(mode), same(modesBefore[mode]));
          }
        }

        final fame = find.descendant(
          of: find.byKey(const ValueKey('Family Fame %')),
          matching: find.byType(TextField),
        );
        await tester.enterText(fame, '1.5');
        await _settleCalculation(tester, fixture.controller);
        expect(app.documentSnapshot.marketTax.familyFameBonus, .015);
        expect(app.documentSnapshot.marketTax.enabled, legacyEnabled);
        expect(find.text('65,975% of each market sale'), findsOneWidget);
        expect(find.text('Market tax · 34,025%'), findsOneWidget);
        expect(beer().listingRevenue, closeTo(gross * .65975, .001));
        expect(beer().listingProfit, closeTo(gross * .65975 - cost, .001));

        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is AppButton && widget.semanticLabel == 'Close',
          ),
        );
        await _settleImages(tester);
        final summary = find.byKey(const ValueKey('craft-summary:Beer'));
        expect(
          find.descendant(
            of: summary,
            matching: find.text(
              _cardSilver(
                beer().listingProfit! / beer().expectedOutput!,
                signed: true,
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Tax off'), findsNothing);
        expect(fixture.controller.preferences.craftSearch, 'Beer');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleWork(tester, fixture.dispose());
      },
    );
  }

  _glassTestWidgets('market timestamp retains the receipt date as prices age', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1280, 820));
    var now = DateTime.utc(2026, 9, 8, 16);
    final fixture = (await tester.runAsync(
      () => _Fixture.create(
        exchange: false,
        clock: () => now,
        savedBookAge: const Duration(hours: 2),
      ),
    ))!;
    await tester.pumpWidget(_host(fixture.controller));
    await _settleImages(tester);
    final stamp = find.byKey(const ValueKey('opportunities-market-timestamp'));
    expect(stamp, findsOneWidget);
    final original = tester.widget<Text>(stamp).data!;
    final local = now.toLocal();
    expect(
      fixture.controller.market.items.values.any(
        (item) =>
            item.bookFetchedAt != null &&
            item.quoteFetchedAt != null &&
            item.bookFetchedAt!.isBefore(item.quoteFetchedAt!),
      ),
      isTrue,
      reason: 'Deferred old orders must not date fresh overview prices.',
    );
    expect(
      original,
      'Prices from ${local.day}.${local.month}. '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}',
    );
    now = now.add(const Duration(days: 1));
    fixture.controller.recalculate();
    await _settleCalculation(tester, fixture.controller);
    expect(tester.widget<Text>(stamp).data, original);
    expect(fixture.controller.lastCheck, now.subtract(const Duration(days: 1)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleWork(tester, fixture.dispose());
  });

  for (final scale in [1.0, 2.0]) {
    _glassTestWidgets(
      'inline mastery commits on Enter or blur and cancels invalid edits $scale',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scale == 1 ? const Size(1200, 752) : const Size(900, 900),
          textScaleFactor: scale,
        );
        final fixture = (await tester.runAsync(
          () => _Fixture.create(exchange: false),
        ))!;
        try {
          fixture.controller.change((p) => p.craftSearch = 'Beer');
          await _settleCalculation(tester, fixture.controller);
          await tester.pumpWidget(_host(fixture.controller));
          await _settleImages(tester);
          final search = _inlineNumber('craft-search');
          final before = fixture.controller.quotes
              .firstWhere((quote) => quote.recipeName == 'Beer')
              .profitFor(OpportunitySaleMode.listing)!;
          final idle = tester.getRect(
            find.byKey(const ValueKey('craft-mastery')),
          );
          await tester.tap(find.byKey(const ValueKey('craft-mastery')));
          await tester.pump();
          final input = _masteryInput();
          expect(input, findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          expect(find.text('Crafting mastery'), findsNothing);
          expect(tester.getRect(input).center.dy, closeTo(idle.center.dy, 1));
          await tester.enterText(input, '2000');
          await tester.pump();
          expect(fixture.controller.state.cookingMastery, 0);
          expect(
            fixture.controller.quotes
                .firstWhere((quote) => quote.recipeName == 'Beer')
                .profitFor(OpportunitySaleMode.listing),
            before,
          );
          await _captureSubstitutes(
            tester,
            'inline-mastery-${scale.toInt() * 100}',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _settleCalculation(tester, fixture.controller);
          expect(input, findsNothing);
          expect(fixture.controller.state.cookingMastery, 2000);
          _expectMasteryValue(tester, 2000);
          expect(
            fixture.controller.quotes
                .firstWhere((quote) => quote.recipeName == 'Beer')
                .profitFor(OpportunitySaleMode.listing)!,
            greaterThan(before),
          );
          for (final invalid in ['', '-1', '3001', '1.5', '2,5', 'abc']) {
            await tester.tap(find.byKey(const ValueKey('craft-mastery')));
            await tester.pump();
            await tester.enterText(input, invalid);
            await tester.pump();
            expect(fixture.controller.state.cookingMastery, 2000);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pump();
            expect(input, findsOneWidget);
            expect(fixture.controller.state.cookingMastery, 2000);
            await tester.tap(search);
            await tester.pump();
            expect(input, findsNothing);
            _expectMasteryValue(tester, 2000);
            expect(fixture.controller.state.cookingMastery, 2000);
          }
          await tester.tap(find.byKey(const ValueKey('craft-mastery')));
          await tester.pump();
          await tester.enterText(input, '1200');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(input, findsNothing);
          expect(fixture.controller.state.cookingMastery, 2000);
          for (final boundary in [0, 3000]) {
            await tester.tap(find.byKey(const ValueKey('craft-mastery')));
            await tester.pump();
            await tester.enterText(input, '$boundary');
            if (boundary == 0) {
              await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
            } else {
              await tester.testTextInput.receiveAction(TextInputAction.done);
            }
            await _settleCalculation(tester, fixture.controller);
            expect(fixture.controller.state.cookingMastery, boundary);
          }
          await tester.tap(find.byKey(const ValueKey('craft-mastery')));
          await tester.pump();
          await tester.enterText(input, '1500');
          await tester.tap(search);
          await _settleCalculation(tester, fixture.controller);
          expect(input, findsNothing);
          expect(fixture.controller.state.cookingMastery, 1500);
          expect(fixture.controller.preferences.craftSearch, 'Beer');

          // A programmatic mode switch occurs before focus loss can commit.
          // The old pending value must never be written to the new mode.
          final alchemyBefore = fixture
              .harness
              .bundle
              .controller
              .modes[CraftMode.alchemy]!
              .state
              .value
              .alchemyMastery;
          await tester.tap(find.byKey(const ValueKey('craft-mastery')));
          await tester.pump();
          await tester.enterText(input, '1700');
          fixture.controller.change(
            (p) => p.mode = CraftMode.alchemy,
            assemble: true,
          );
          await _settleCalculation(tester, fixture.controller);
          expect(input, findsNothing);
          expect(fixture.controller.state.alchemyMastery, alchemyBefore);
          expect(
            fixture
                .harness
                .bundle
                .controller
                .modes[CraftMode.cooking]!
                .state
                .value
                .cookingMastery,
            1500,
          );
          _expectMasteryValue(tester, alchemyBefore);
          await tester.tap(find.byKey(const ValueKey('craft-mode-cooking')));
          await _settleCalculation(tester, fixture.controller);
          _expectMasteryValue(tester, 1500);
          expect(fixture.controller.preferences.craftSearch, 'Beer');
          expect(fixture.controller.preferences.craftSale, 'buyers');
          await tester.tap(find.text('Exchanges').first);
          await tester.pump();
          expect(fixture.controller.owned, 10000);
          expect(fixture.controller.preferences.currencyId, 'sangpyeong');
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleWork(tester, fixture.dispose());
        }
      },
    );
  }
}

Finder _buttonWithText(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is AppButton),
);

Finder _menuFilter(String key) => find.byKey(ValueKey(key));

Future<void> _toggleCraftFilter(
  WidgetTester tester,
  OpportunitiesController controller,
  String key,
) async {
  if (key == 'craft-ingredients-available') {
    await tester.tap(_menuFilter('craft-ingredients-menu'));
    await _settleImages(tester);
  }
  await tester.tap(_menuFilter(key));
  await _settleCalculation(tester, controller);
  if (key == 'craft-ingredients-available') {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settleImages(tester);
  }
}

Finder _masteryInput() => find.descendant(
  of: find.byKey(const ValueKey('craft-mastery-input')),
  matching: find.byType(TextField),
  matchRoot: true,
);

void _expectMasteryValue(WidgetTester tester, int value) {
  final display = find.byKey(const ValueKey('craft-mastery'));
  expect(display, findsOneWidget);
  final row = find.ancestor(of: display, matching: find.byType(Row)).first;
  expect(
    find.descendant(of: row, matching: find.text('Mastery ·')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: display, matching: find.text('$value')),
    findsOneWidget,
  );
}

Finder _inlineNumber(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

void _expectBalancedBestUseCard(
  WidgetTester tester,
  String name, {
  bool compact = false,
}) {
  final card = find.byKey(ValueKey('craft-card:$name'));
  expect(card, findsOneWidget);
  final bounds = tester.getRect(card);
  final header = tester.getRect(
    find.byKey(ValueKey('best-use-card-header:$name')),
  );
  final output = tester.getRect(
    find.byKey(ValueKey('best-use-output-strip:$name')),
  );
  final equation = tester.getRect(
    find.byKey(ValueKey('best-use-equation:$name')),
  );
  final stock = tester.getRect(find.byKey(ValueKey('best-use-stock:$name')));
  final mount = tester.getRect(
    find.byKey(ValueKey('craft-artwork-rail:$name')),
  );
  final icon = find.descendant(
    of: find.byKey(ValueKey('craft-artwork-rail:$name')),
    matching: find.byType(ModeItemIcon),
  );
  final title = find.descendant(of: card, matching: find.text(name));
  expect(mount.size, const Size(56, 56));
  expect(tester.getSize(icon), const Size(48, 48));
  expect(tester.getCenter(icon), mount.center);
  expect(header.contains(stock.topLeft), isTrue);
  expect(header.contains(stock.bottomRight - const Offset(.01, .01)), isTrue);
  expect(output.top, greaterThan(header.bottom));
  expect(equation.top, greaterThan(output.bottom));
  expect(output.left, closeTo(bounds.left + 15, 1.1));
  expect(output.right, closeTo(bounds.right - 15, 1.1));
  expect(equation.left, closeTo(bounds.left + 15, 1.1));
  expect(equation.right, closeTo(bounds.right - 15, 1.1));
  expect(find.byKey(ValueKey('best-use-unit-context:$name')), findsNothing);
  expect(
    tester
        .widget<OpportunityCraftCardFinish>(
          find.descendant(
            of: card,
            matching: find.byType(OpportunityCraftCardFinish),
          ),
        )
        .artworkRail,
    isFalse,
  );
  if (compact) {
    expect(bounds.height, lessThanOrEqualTo(300));
  }
  final titleBounds = tester.getRect(title);
  if (stock.top >= titleBounds.bottom) {
    expect(stock.left, closeTo(titleBounds.left, .01));
  } else {
    expect(stock.center.dy, closeTo(titleBounds.center.dy, .01));
  }
  Finder metricText(String key, {required bool value}) {
    final texts = find.descendant(
      of: find.byKey(ValueKey('$key:$name')),
      matching: find.byType(Text),
    );
    return value ? texts.last : texts.first;
  }

  final saleLabel = metricText('best-use-sale', value: false);
  final saleValue = metricText('best-use-sale', value: true);
  final ingredientsLabel = metricText('best-use-ingredients', value: false);
  final ingredientsValue = metricText('best-use-ingredients', value: true);
  final profitLabel = metricText('best-use-profit', value: false);
  final profitValue = metricText('best-use-profit', value: true);
  final saleBounds = tester.getRect(
    find.byKey(ValueKey('best-use-sale:$name')),
  );
  final ingredientsBounds = tester.getRect(
    find.byKey(ValueKey('best-use-ingredients:$name')),
  );
  final profitBounds = tester.getRect(
    find.byKey(ValueKey('best-use-profit:$name')),
  );
  for (final pair in [
    (saleLabel, saleValue),
    (ingredientsLabel, ingredientsValue),
    (profitLabel, profitValue),
  ]) {
    expect(
      tester.getCenter(pair.$1).dx,
      closeTo(tester.getCenter(pair.$2).dx, 1.1),
    );
    expect(
      tester.getRect(pair.$2).top,
      greaterThan(tester.getRect(pair.$1).bottom),
    );
    expect(tester.widget<Text>(pair.$2).style?.fontSize, 18.5);
    expect(tester.widget<Text>(pair.$2).style?.fontWeight, FontWeight.w700);
  }
  if (ingredientsBounds.left > saleBounds.left + 1) {
    expect(ingredientsBounds.top, closeTo(saleBounds.top, .01));
    expect(profitBounds.top, closeTo(saleBounds.top, .01));
    expect(ingredientsBounds.width, closeTo(saleBounds.width, .01));
    expect(profitBounds.width, closeTo(saleBounds.width, .01));
  } else {
    expect(ingredientsBounds.top, greaterThan(saleBounds.bottom));
    expect(profitBounds.top, greaterThan(ingredientsBounds.bottom));
  }
  for (final text in [
    title,
    saleLabel,
    saleValue,
    ingredientsLabel,
    ingredientsValue,
    profitLabel,
    profitValue,
  ]) {
    final rect = tester.getRect(text);
    expect(bounds.contains(rect.topLeft), isTrue);
    expect(bounds.contains(rect.bottomRight - const Offset(.01, .01)), isTrue);
    expect(
      tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
      isFalse,
    );
  }
  expect(
    find.descendant(of: card, matching: find.text('After tax · per craft')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: card, matching: find.text('Calculation')),
    findsOneWidget,
  );
}

Future<void> _prepareAloeBestUse(WidgetTester tester, _Fixture fixture) async {
  final controller = fixture.controller;
  controller.change((p) {
    p.section = 'best-use';
    p.profitableOnly = false;
    p.demandOnly = false;
    p.readyOnly = false;
  });
  controller.selectBestUseItem('Aloe');
  await _settleCalculation(tester, controller);
  await _settleWork(tester, controller.refresh());
  await _settleWork(
    tester,
    controller.ensureMarketDepth(controller.market.items.keys),
  );
  await _settleCalculation(tester, controller);
}

OpportunitySilverAmount _bestUseReadout(WidgetTester tester, String key) =>
    tester.widget<OpportunitySilverAmount>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(OpportunitySilverAmount),
      ),
    );

Finder _detailCraftCount() => find.descendant(
  of: find.byKey(const ValueKey('opportunity-detail-crafts')),
  matching: find.byType(TextField),
);

void _expectSortSelected(WidgetTester tester, String selected) {
  for (final sort in ['preorders', 'profit']) {
    final flags = tester
        .getSemantics(find.byKey(ValueKey('craft-sort-$sort')))
        .getSemanticsData()
        .flagsCollection;
    expect(
      flags.isSelected,
      sort == selected ? Tristate.isTrue : Tristate.isFalse,
    );
    expect(flags.isInMutuallyExclusiveGroup, isTrue);
  }
}

Future<void> _expectPassiveCraftEstimates(
  WidgetTester tester,
  OpportunityQuote quote,
) async {
  final amount = find.byKey(
    ValueKey('craft-per-item-profit:${quote.recipeName}'),
  );
  expect(
    tester.widget<Text>(amount).data,
    _cardSilver(quote.listingProfit! / quote.expectedOutput!, signed: true),
  );
  expect(
    find.descendant(
      of: find.byKey(ValueKey('craft-summary:${quote.recipeName}')),
      matching: find.byType(Tooltip),
    ),
    findsNothing,
  );
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(amount));
  await tester.pump(const Duration(milliseconds: 900));
  expect(find.textContaining('Estimate using current'), findsNothing);
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

String _cardSilver(double value, {bool signed = false}) {
  final rounded = value.round();
  return '${signed && rounded > 0 ? '+' : ''}${formatQuantity(rounded.toDouble())}'
      .replaceFirst('-', '−');
}

Future<void> _expectIconOnlyCardHover(
  WidgetTester tester,
  _Fixture fixture, {
  required Finder card,
  required Finder icon,
  required String name,
  required List<Finder> probes,
}) async {
  expect(card, findsOneWidget);
  expect(icon, findsOneWidget);
  for (final element
      in find.descendant(of: card, matching: find.byType(Tooltip)).evaluate()) {
    expect(
      element.findAncestorWidgetOfExactType<RecipeBookItemInfoHover>(),
      isNotNull,
      reason: 'Only the item artwork may own a card hover popup.',
    );
  }
  final requests = List<String>.of(fixture.requests);
  final targets = {
    for (final entry in fixture.controller.appController.modes.entries)
      entry.key: entry.value.state.value.target,
  };
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  try {
    for (final probe in probes) {
      expect(probe, findsOneWidget);
      await tester.ensureVisible(probe);
      await mouse.moveTo(const Offset(1, 1));
      Tooltip.dismissAllToolTips();
      await tester.pump(const Duration(milliseconds: 550));
      final baseline = [
        for (final text in tester.widgetList<RichText>(find.byType(RichText)))
          text.text.toPlainText(),
      ];
      final size = tester.getSize(card);
      await mouse.moveTo(tester.getCenter(probe));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(ItemReferenceCard), findsNothing);
      expect(
        [
          for (final text in tester.widgetList<RichText>(find.byType(RichText)))
            text.text.toPlainText(),
        ],
        baseline,
        reason:
            'Names, values, stock and actions must not add a hover overlay.',
      );
      expect(tester.getSize(card), size);
    }
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.ensureVisible(icon);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 250));
    final reference = find.byType(ItemReferenceCard);
    expect(reference, findsOneWidget);
    expect(tester.widget<ItemReferenceCard>(reference).name, name);
    expect(
      tester.widget<ItemReferenceCard>(reference).controller,
      same(fixture.controller.itemInfoController),
    );
    expect(
      fixture.requests,
      requests,
      reason: 'Hover must use bundled item facts.',
    );
    expect({
      for (final entry in fixture.controller.appController.modes.entries)
        entry.key: entry.value.state.value.target,
    }, targets);
  } finally {
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pumpAndSettle();
  }
  expect(find.byType(ItemReferenceCard), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _openCalculation(WidgetTester tester, String name) async {
  final expand = find.byKey(ValueKey('craft-expand-button:$name'));
  if (expand.evaluate().isNotEmpty) {
    final header = find.byKey(ValueKey('craft-expand:$name'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(header),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View recipe'));
    await _settleImages(tester);
    return;
  }
  final card = find.byKey(ValueKey('craft-card:$name'));
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getCenter(card), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('View recipe'));
  await _settleImages(tester);
}

Future<void> _openIngredient(WidgetTester tester, String name) async {
  final link = find.byKey(ValueKey('ingredient-recipe-$name'));
  expect(link, findsOneWidget);
  await tester.ensureVisible(link);
  await tester.pumpAndSettle();
  await tester.tap(link);
  await _settleImages(tester);
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _openCalculationInfo(WidgetTester tester) async {
  final info = find.byKey(const ValueKey('craft-calculation-info'));
  await tester.ensureVisible(info);
  await tester.tap(info);
  await _settleImages(tester);
  expect(find.byType(Dialog), findsNWidgets(2));
}

void _expectMetricText(
  WidgetTester tester,
  Finder scope,
  String label,
  String value,
) {
  if (label == 'Profit' &&
      find
          .descendant(of: scope, matching: find.text('Craft & sell'))
          .evaluate()
          .isNotEmpty) {
    expect(
      find.descendant(of: scope, matching: find.text(value)),
      findsOneWidget,
    );
    return;
  }
  final heading = find.descendant(of: scope, matching: find.text(label));
  expect(heading, findsOneWidget);
  final cell = find.ancestor(of: heading, matching: find.byType(Column)).first;
  expect(find.descendant(of: cell, matching: find.text(value)), findsOneWidget);
}

void _expectInspectionCalculation(
  WidgetTester tester,
  OpportunityRecipeInspection inspection, {
  Finder? page,
}) {
  final quote = inspection.quote;
  final result = find.byKey(ValueKey('craft-result:${quote.recipeName}'));
  expect(
    find.descendant(
      of: page ?? find.byKey(const ValueKey('ingredient-recipe-page')),
      matching: result,
    ),
    findsOneWidget,
  );
  _expectMetricText(
    tester,
    result,
    'Profit',
    quote.listingProfit == null
        ? '—'
        : '${quote.hasEstimatedInputs ? '≈ ' : ''}${formatCompactOpportunitySilver(quote.listingProfit!)}',
  );
  final money = find.byKey(const ValueKey('craft-money-summary'));
  expect(
    find.descendant(
      of: money,
      matching: find.text(
        quote.listingRevenue == null
            ? '—'
            : '${formatCompactOpportunitySilver(quote.listingRevenue!)} silver',
      ),
    ),
    findsWidgets,
  );
  expect(
    find.descendant(
      of: money,
      matching: find.text(
        '${quote.hasEstimatedInputs ? '≈ ' : ''}${formatCompactOpportunitySilver(-quote.totalCost!)} silver',
      ),
    ),
    findsOneWidget,
  );
  if (quote.listingProfit != null) {
    expect(
      quote.listingProfit,
      closeTo(quote.listingRevenue! - quote.totalCost!, .001),
    );
  }
}

void _expectRecipeTrail(WidgetTester tester, List<String> names) {
  final trail = find.byKey(const ValueKey('ingredient-recipe-trail'));
  expect(trail, findsOneWidget);
  for (var index = 0; index < names.length; index++) {
    final crumb = find.byKey(ValueKey('ingredient-recipe-crumb:$index'));
    expect(find.descendant(of: trail, matching: crumb), findsOneWidget);
    expect(
      find.descendant(
        of: crumb,
        matching: find.text(names[index]),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<InkWell>(crumb).onTap,
      index == names.length - 1 ? isNull : isNotNull,
      reason: 'Only earlier steps should be clickable.',
    );
  }
  expect(
    find.byKey(ValueKey('ingredient-recipe-crumb:${names.length}')),
    findsNothing,
  );
}

Recipe _recipeWithIngredients(
  Recipe recipe,
  List<String> ingredients, {
  String? type,
}) => Recipe(
  name: recipe.name,
  type: type ?? recipe.type,
  baseOutput: recipe.baseOutput,
  group: recipe.group,
  method: recipe.method,
  ingredients: [
    for (final name in ingredients)
      Ingredient(
        name: name,
        quantity: 1,
        options: const [],
        substituteGroup: null,
        substituteRatios: const {},
      ),
  ],
  marketId: recipe.marketId,
  sourceNote: recipe.sourceNote,
  vendor: recipe.vendor,
  location: recipe.location,
  npcPrice: recipe.npcPrice,
  qualityBase: recipe.qualityBase,
  qualityGrade: recipe.qualityGrade,
  outputMinimum: recipe.outputMinimum,
  outputMaximum: recipe.outputMaximum,
);

String _testSilver(double value) {
  for (final unit in [(1000000000, 'B'), (1000000, 'M'), (10000, 'K')]) {
    if (value.abs() >= unit.$1) {
      return '${formatQuantity(value / (unit.$2 == 'K' ? 1000 : unit.$1))}${unit.$2}';
    }
  }
  return formatQuantity(value);
}

void _expectExchangeHeaderSpacing(WidgetTester tester) {
  final toolbar = tester.getRect(
    find.byKey(const ValueKey('exchange-toolbar')),
  );
  final identity = tester.getRect(
    find.byKey(const ValueKey('exchange-identity')),
  );
  expect(identity.top, greaterThanOrEqualTo(toolbar.top + 14));
  expect(identity.bottom, lessThan(toolbar.bottom));
  final chooser = tester.getRect(
    find.byKey(const ValueKey('exchange-choose-item')),
  );
  expect(chooser.top, greaterThanOrEqualTo(identity.bottom + 10));
  expect(
    find.textContaining('exchanges covered by current buyers'),
    findsNothing,
  );
  expect(
    find.textContaining('One exchange covered by current buyers'),
    findsNothing,
  );
}

bool _focusIsWithin(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  if (identical(target, focused)) return true;
  var within = false;
  focused.visitAncestorElements((element) {
    if (identical(element, target)) {
      within = true;
      return false;
    }
    return true;
  });
  return within;
}

void _expectCraftControlPlacement(WidgetTester tester) {
  final toolbar = find.byKey(const ValueKey('craft-toolbar'));
  final sidebar = find.byKey(const ValueKey('opportunities-sidebar'));
  expect(toolbar, findsOneWidget);
  _expectWorkbenchGeometry(tester);
  final hasRail = sidebar.evaluate().isNotEmpty;
  final modes = find.byKey(const ValueKey('craft-mode-tabs'));
  for (final mode in ['cooking', 'alchemy', 'processing']) {
    expect(
      find.descendant(
        of: hasRail ? sidebar : toolbar,
        matching: find.byKey(ValueKey('craft-mode-$mode')),
      ),
      findsOneWidget,
      reason:
          'Craft modes use the rail space, or the compact toolbar fallback.',
    );
    expect(find.byKey(ValueKey('craft-mode-$mode')), findsOneWidget);
  }
  final search = tester.getRect(find.byKey(const ValueKey('craft-search')));
  final sort = tester.getRect(find.byKey(const ValueKey('craft-sort-options')));
  final bounds = tester.getRect(toolbar);
  for (final rect in [search]) {
    expect(rect.left, greaterThanOrEqualTo(bounds.left - .01));
    expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
    expect(rect.height, closeTo(40, .01));
  }
  final filters = tester.getRect(find.byKey(const ValueKey('craft-filters')));
  expect(search.left, closeTo(bounds.left, .01));
  if (hasRail) {
    expect(filters.right, closeTo(bounds.right, .01));
    expect(filters.left, greaterThan(search.right));
    expect(filters.center.dy, closeTo(search.center.dy, 1));
    final modeBounds = tester.getRect(modes);
    final railBounds = tester.getRect(sidebar);
    expect(modeBounds.left, greaterThanOrEqualTo(railBounds.left));
    expect(modeBounds.right, lessThanOrEqualTo(railBounds.right));
    final lastTask = tester.getRect(
      find.byKey(const ValueKey('opportunities-section-best use')),
    );
    expect(modeBounds.top, greaterThan(lastTask.bottom + 20));
    expect(sort.left, greaterThanOrEqualTo(railBounds.left));
    expect(sort.right, lessThanOrEqualTo(railBounds.right));
    expect(sort.top, greaterThan(modeBounds.bottom + 20));
    final sortButtons = [
      for (final name in ['preorders', 'profit', 'exp'])
        tester.getRect(find.byKey(ValueKey('craft-sort-$name'))),
    ];
    for (var i = 0; i < sortButtons.length; i++) {
      expect(sortButtons[i].height, closeTo(40, .01));
      if (i > 0) {
        expect(sortButtons[i].top, closeTo(sortButtons[i - 1].bottom + 6, .01));
      }
    }
    expect(
      find.descendant(
        of: toolbar,
        matching: find.byKey(const ValueKey('craft-sort-options')),
      ),
      findsNothing,
    );
  } else {
    expect(filters.right, closeTo(bounds.right - 8, .01));
    expect(sort.height, closeTo(40, .01));
    expect(sort.top, greaterThanOrEqualTo(search.bottom + 10));
    expect(sort.left, closeTo(bounds.left + 8, .01));
    expect(sort.right, lessThanOrEqualTo(bounds.right));
    expect(filters.left, greaterThan(sort.right));
    expect(sort.center.dy, closeTo(filters.center.dy, 1));
    final modeBounds = tester.getRect(modes);
    expect(search.center.dy, closeTo(modeBounds.center.dy, 1));
    expect(modeBounds.right, closeTo(bounds.right, .01));
    expect(modeBounds.left, greaterThan(search.right));
  }
  expect(
    find.descendant(
      of: toolbar,
      matching: find.byKey(const ValueKey('craft-mastery')),
    ),
    findsNothing,
  );
  final mastery = tester.getRect(find.byKey(const ValueKey('craft-mastery')));
  expect(mastery.bottom, lessThanOrEqualTo(bounds.top));
}

void _expectWorkbenchGeometry(WidgetTester tester) {
  final sections = find.byKey(const ValueKey('opportunities-sections'));
  final sidebar = find.byKey(const ValueKey('opportunities-sidebar'));
  final header = find.byKey(const ValueKey('opportunities-header'));
  expect(sections, findsOneWidget);
  expect(find.descendant(of: header, matching: sections), findsNothing);
  final headerBounds = tester.getRect(header);
  final sectionBounds = tester.getRect(sections);
  expect(sectionBounds.top, greaterThanOrEqualTo(headerBounds.bottom));
  for (final section in ['Crafting', 'Exchanges', 'Best use']) {
    expect(
      find.descendant(of: sections, matching: find.text(section)),
      findsOneWidget,
    );
    expect(find.text(section), findsOneWidget);
  }
  final workspace = tester.getRect(find.byType(OpportunitiesWorkspace));
  final panes = tester.getRect(
    find.byKey(const ValueKey('opportunities-panes')),
  );
  final scale = MediaQuery.textScalerOf(tester.element(header)).scale(14) / 14;
  if (workspace.width >= 1120 * scale) {
    expect(sidebar, findsOneWidget);
    final rail = tester.getRect(sidebar);
    expect(rail.width, closeTo(134 * scale, .01));
    expect(rail.left, closeTo(workspace.left + 20, .01));
    expect(panes.left, closeTo(rail.right + 22, .01));
    expect(find.descendant(of: sidebar, matching: sections), findsOneWidget);
    for (final finish in ['bronze', 'moon']) {
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byKey(ValueKey('opportunities-finish-$finish')),
        ),
        findsNothing,
      );
    }
  } else {
    expect(sidebar, findsNothing);
    expect(panes.left, closeTo(workspace.left + 20, .01));
    expect(sectionBounds.bottom, lessThanOrEqualTo(panes.top));
  }
  expect(panes.right, closeTo(workspace.right - 20, .01));
  expect(panes.top, greaterThanOrEqualTo(headerBounds.bottom));
  final list = find.byKey(const PageStorageKey('craft-opportunities'));
  if (list.evaluate().isNotEmpty) {
    expect(tester.getRect(list).left, closeTo(panes.left, .01));
    expect(tester.getRect(list).right, closeTo(panes.right, .01));
  }
}

void _expectCraftOverviewTypography(
  WidgetTester tester, {
  bool bestUse = false,
}) {
  final cards = find.descendant(
    of: find.byKey(
      PageStorageKey(
        bestUse ? 'best-use-opportunities' : 'craft-opportunities',
      ),
    ),
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('craft-card:');
    }),
  );
  expect(cards, findsWidgets);
  for (var index = 0; index < cards.evaluate().length; index++) {
    final card = cards.at(index);
    final key = tester.widget(card).key! as ValueKey<String>;
    final name = key.value.substring('craft-card:'.length);
    if (!bestUse) {
      final title = tester.widget<Text>(
        find.descendant(of: card, matching: find.text(name)),
      );
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w600);
      final profit = tester.widget<Text>(
        find.byKey(ValueKey('craft-per-item-profit:$name')),
      );
      expect(profit.style!.fontSize, 20);
      expect(profit.style!.fontWeight, FontWeight.w600);
      expect(
        find.descendant(of: card, matching: find.text('per item')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Sell ingredients')),
        findsOneWidget,
      );
      final bounds = tester.getRect(card);
      for (final text
          in find
              .descendant(of: card, matching: find.byType(Text))
              .evaluate()) {
        final finder = find.byElementPredicate(
          (element) => identical(element, text),
        );
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(bounds.left));
        expect(rect.right, lessThanOrEqualTo(bounds.right));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(
          tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
          isFalse,
        );
      }
      continue;
    }
    _expectOverviewCardTypography(
      tester,
      card: card,
      name: find.descendant(of: card, matching: find.text(name)),
      primaryLabel: null,
      secondaryLabels: const [],
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(ValueKey('best-use-output-strip:$name')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(ValueKey('best-use-equation:$name')),
      ),
      findsOneWidget,
    );
    for (final label in const [
      'Sale',
      'Ingredients',
      'Profit',
      'After tax · per craft',
      'Calculation',
    ]) {
      expect(
        find.descendant(of: card, matching: find.text(label)),
        findsOneWidget,
      );
    }
  }
}

void _expectOverviewCardTypography(
  WidgetTester tester, {
  required Finder card,
  required Finder name,
  required String? primaryLabel,
  required List<String> secondaryLabels,
}) {
  expect(name, findsOneWidget);
  final explicitNameStyle = tester.widget<Text>(name).style;
  final nameStyle =
      explicitNameStyle ?? DefaultTextStyle.of(tester.element(name)).style;
  if (explicitNameStyle != null) {
    expect(nameStyle.fontSize, OpportunitiesVisualSpec.cardNameFontSize);
    expect(nameStyle.fontWeight, FontWeight.w700);
  } else {
    // Virtual rewards such as EXP inherit body text; they are not item titles
    // and intentionally have neither a price nor a marketplace metric.
    expect(primaryLabel, isNull);
    expect(secondaryLabels, isEmpty);
  }
  final bounds = tester.getRect(card);
  void expectUnclipped(Finder text) {
    final rect = tester.getRect(text);
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.top, greaterThanOrEqualTo(bounds.top));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
    expect(
      tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
      isFalse,
    );
  }

  expectUnclipped(name);
  for (final label in [?primaryLabel, ...secondaryLabels]) {
    if (label == 'Stock') {
      final stock = find.descendant(
        of: card,
        matching: find.textContaining('Stock '),
      );
      expect(stock, findsOneWidget);
      expect(tester.widget<Text>(stock).style?.fontSize, 16);
      expect(tester.widget<Text>(stock).style?.fontWeight, FontWeight.w700);
      expectUnclipped(stock);
      continue;
    }
    final heading = find.descendant(of: card, matching: find.text(label));
    expect(heading, findsOneWidget);
    expect(
      tester.widget<Text>(heading).style?.fontSize,
      OpportunitiesVisualSpec.cardLabelFontSize,
    );
    final badge = find.ancestor(
      of: heading,
      matching: find.byKey(const ValueKey('market-stock-badge')),
    );
    final isBadge = badge.evaluate().isNotEmpty;
    final metric = isBadge
        ? badge.first
        : find.ancestor(of: heading, matching: find.byType(Column)).first;
    final value = find.descendant(of: metric, matching: find.byType(Text)).last;
    final style = tester.widget<Text>(value).style!;
    final primary = label == primaryLabel;
    expect(
      style.fontSize,
      primary
          ? OpportunitiesVisualSpec.cardPrimaryValueFontSize
          : label == 'Raw ingredient sale' || label == 'Crafted item sale'
          ? OpportunitiesVisualSpec.cardPrimaryValueFontSize
          : 15,
    );
    expect(
      style.fontWeight,
      primary ||
              isBadge ||
              label == 'Raw ingredient sale' ||
              label == 'Crafted item sale'
          ? FontWeight.w600
          : FontWeight.w500,
    );
    expect(
      style.fontWeight!.value,
      lessThanOrEqualTo(nameStyle.fontWeight!.value),
    );
    expectUnclipped(heading);
    expectUnclipped(value);
  }
}

void _expectWorkbenchCard(WidgetTester tester, String name) {
  final card = tester.getRect(find.byKey(ValueKey('craft-header:$name')));
  final rail = tester.getRect(find.byKey(ValueKey('craft-artwork-rail:$name')));
  final icon = find.descendant(
    of: find.byKey(ValueKey('craft-artwork-rail:$name')),
    matching: find.byType(ModeItemIcon),
  );
  final frame = tester.getRect(icon);
  final summary = find.byKey(ValueKey('craft-summary:$name'));
  final title = tester.getRect(
    find.descendant(of: summary, matching: find.text(name)),
  );
  final stock = tester.getRect(
    find.byKey(ValueKey('craft-market-counts:$name')),
  );
  expect(rail.size, const Size(46, 46));
  expect(rail.left, closeTo(card.left + 8, 1.1));
  // Artwork was accepted centered in the full-height rail, not title-aligned.
  expect(rail.center.dy, closeTo(card.center.dy, 1.1));
  expect(frame.size, const Size(40, 40));
  expect(frame.center, rail.center);
  final artwork = tester.widget<ModeItemIcon>(icon);
  expect(artwork.size, 40);
  expect(artwork.fit, BoxFit.contain);
  expect(artwork.showFrame, isTrue);
  const artworkToTitleGap = 20;
  expect(title.left, closeTo(rail.right + artworkToTitleGap, .01));
  expect(stock.left, greaterThanOrEqualTo(title.left));
  expect(stock.right, lessThanOrEqualTo(card.right - 16));
  expect(title.right, lessThanOrEqualTo(card.right - 16));
  expect(
    tester.getRect(find.byKey(ValueKey('craft-per-item-profit:$name'))).top,
    greaterThan(title.bottom),
  );
}

void _expectCraftCardLayout(
  WidgetTester tester, {
  required int expectedColumns,
  double? firstRowTop,
}) {
  final list = find.byKey(const PageStorageKey('craft-opportunities'));
  final cards = find.descendant(
    of: list,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('craft-card:');
    }),
  );
  expect(cards, findsWidgets);
  final rects = [
    for (final element in cards.evaluate())
      tester.getRect(
        find.byElementPredicate((candidate) => identical(candidate, element)),
      ),
  ];
  expect(rects.length, greaterThanOrEqualTo(expectedColumns));
  final firstTop = rects.first.top;
  if (firstRowTop != null) {
    expect(firstTop, closeTo(firstRowTop, 1));
    debugPrint(
      'Finishing grid: viewport=${tester.view.physicalSize}, '
      'columns=$expectedColumns, top=$firstTop, '
      'firstHeight=${rects.first.height}',
    );
  }
  final firstRow = rects
      .where((rect) => (rect.top - firstTop).abs() < .1)
      .toList();
  expect(firstRow, hasLength(expectedColumns));
  final bounds = tester.getRect(list);
  expect(
    firstRow.first.left - bounds.left,
    closeTo(bounds.right - firstRow.last.right, .01),
    reason: 'Center the occupied card grid without stretching sparse results.',
  );
  final scale = MediaQuery.textScalerOf(tester.element(list)).scale(14) / 14;
  for (final rect in rects) {
    expect(rect.width, greaterThan(0));
    expect(
      rect.width,
      lessThanOrEqualTo(332 * scale + .1),
      reason: 'Recipe cards retain a bounded, readable line length.',
    );
    expect(rect.left, greaterThanOrEqualTo(bounds.left - .1));
    expect(rect.right, lessThanOrEqualTo(bounds.right + .1));
  }
  for (var i = 1; i < firstRow.length; i++) {
    expect(firstRow[i].left - firstRow[i - 1].right, closeTo(14, .01));
  }
  for (var i = expectedColumns; i < rects.length; i++) {
    expect(
      firstRow.any((column) => (column.left - rects[i].left).abs() < .01),
      isTrue,
      reason: 'Following rows retain the same column alignment.',
    );
  }
}

void _expectMarketNumberOnOneLine(WidgetTester tester) {
  final value = find.descendant(
    of: find.byKey(const PageStorageKey('craft-opportunities')),
    matching: find.text('Preorders 100.000'),
  );
  expect(value, findsWidgets);
  for (var index = 0; index < value.evaluate().length; index++) {
    final paragraph = tester.renderObject<RenderParagraph>(value.at(index));
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 10, extentOffset: 17),
    );
    expect(
      boxes,
      hasLength(1),
      reason: 'Market counts must not split digits across lines at large text.',
    );
  }
}

void _expectIngredientColumns(WidgetTester tester, {required int columns}) {
  final grid = find.byKey(const ValueKey('craft-ingredient-grid'));
  expect(grid, findsOneWidget);
  final children = tester.widget<Wrap>(grid).children;
  expect(children.length, greaterThanOrEqualTo(3));
  final rects = [
    for (final child in children) tester.getRect(find.byWidget(child)),
  ];
  final bounds = tester.getRect(grid);
  for (final rect in rects) {
    expect(rect.width, greaterThan(0));
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
  }
  if (columns == 2) {
    expect(rects[1].top, closeTo(rects[0].top, 0.01));
    expect(rects[1].left, greaterThanOrEqualTo(rects[0].right));
    expect(rects[2].left, closeTo(rects[0].left, 0.01));
    expect(rects[2].top, greaterThanOrEqualTo(rects[0].bottom));
    expect(rects[2].top, greaterThanOrEqualTo(rects[1].bottom));
  } else {
    for (var index = 1; index < rects.length; index++) {
      expect(rects[index].left, closeTo(rects[0].left, 0.01));
      expect(rects[index].top, greaterThanOrEqualTo(rects[index - 1].bottom));
    }
  }
}

Future<void> _settleCalculation(
  WidgetTester tester,
  OpportunitiesController controller,
) async {
  await tester.pump(const Duration(milliseconds: 200));
  var done = false;
  unawaited(
    controller.calculationSettled.then((_) {
      done = true;
    }),
  );
  for (var attempt = 0; attempt < 500 && !done; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue, reason: 'Background calculation should finish');
}

Future<void> _settleDepth(
  WidgetTester tester,
  OpportunitiesController controller,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (
    var attempt = 0;
    attempt < 500 && controller.detailStatus.loading;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(controller.detailStatus.loading, isFalse);
  await _settleCalculation(tester, controller);
}

// UI edits create save continuations in the fake zone, while file I/O and the
// initial fixture run in the real zone. Starting disposal in runAsync blocks
// those fake-zone continuations. Start it here and allow both queues to drain.
Future<void> _settleWork(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? failure;
  StackTrace? stack;
  unawaited(
    work.then(
      (_) => done = true,
      onError: (Object error, StackTrace trace) {
        failure = error;
        stack = trace;
        done = true;
      },
    ),
  );
  for (var attempt = 0; attempt < 1000 && !done; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    done,
    isTrue,
    reason: 'Fixture persistence and disposal should finish',
  );
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
}

Future<void> _openExchangeReward(
  WidgetTester tester,
  OpportunitiesController controller,
  String name,
) async {
  final open = find.byWidgetPredicate(
    (widget) =>
        widget is AppButton &&
        widget.semanticLabel == 'Exchange details for $name',
  );
  await tester.scrollUntilVisible(
    open,
    350,
    scrollable: find
        .descendant(
          of: find.byKey(PageStorageKey('exchange-${controller.currency.id}')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 80,
  );
  await tester.pump();
  expect(open.hitTestable(), findsOneWidget);
  await tester.tap(open);
  await _settleDepth(tester, controller);
  await _settleImages(tester);
}

Widget _host(
  OpportunitiesController controller, {
  ValueListenable<ThemeSpec>? theme,
}) => RepaintBoundary(
  key: const ValueKey('opportunities-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ThemeSpecScope(
      spec: applicationThemeForAppearance(
        controller.modeController.state.value.appearance,
      ),
      child: Scaffold(
        body: OpportunitiesWorkspace(controller: controller, theme: theme),
      ),
    ),
  ),
);

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pump(const Duration(milliseconds: 300));
}

final class _Fixture {
  _Fixture(this.harness, this.controller, this.requests);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final List<String> requests;
  static Future<_Fixture> create({
    required bool exchange,
    bool missingStock = false,
    bool noBuyers = false,
    int buyerCount = 100000,
    int stockCount = 100000,
    String backgroundId = 'plain-cobalt',
    DateTime Function()? clock,
    Map<String, int> pricesByName = const {},
    Map<String, int> pricesById = const {},
    Map<String, int> stocksByName = const {},
    Map<String, List<OpportunityMarketLevel>> preorders = const {},
    Map<String, List<OpportunityMarketLevel>> preordersByName = const {},
    Set<String> unavailableNames = const {},
    bool summaryOnly = false,
    bool seedNonMarketPrices = true,
    Duration savedBookAge = Duration.zero,
  }) async {
    final harness = await ApplicationTestHarness.create(
      backgroundId: backgroundId,
    );
    final catalog = CatalogRepository(harness.bundle.catalog);
    final now = DateTime.utc(2026, 9, 8, 16);
    final readClock = clock ?? () => now;
    final requests = <String>[];
    final beerId = catalog.bundledMarketId('Beer')!;
    final prices = {
      ...pricesById,
      for (final entry in pricesByName.entries)
        catalog.bundledMarketId(entry.key)!: entry.value,
    };
    // These visual/calculation fixtures historically supplied synthetic market
    // receipts for every ingredient, including NPC-only Sugar. Preserve that
    // explicit scenario independently of the production request-eligibility
    // gate; this is not a claim that those items are sold on the live market.
    // The eligibility and progressive-market tests cover the honest unpriced
    // production path separately. No user cache or network is used here.
    await OpportunityMarketCacheStore(
      directory: harness.temporaryDirectory,
      utcNow: readClock,
    ).save({
      'eu': {
        for (final id
            in seedNonMarketPrices
                ? reviewedNonMarketableOpportunityIds
                : const <String>{})
          id: OpportunityMarketItem(
            itemId: id,
            basePrice: prices[id] ?? 1000,
            stock: missingStock ? 0 : stockCount,
            quoteFetchedAt: readClock(),
            totalTrades: 500000,
            lastSoldAt: readClock().subtract(const Duration(minutes: 10)),
            asks: [
              OpportunityMarketLevel(
                price: (prices[id] ?? 1000) + 10,
                quantity: missingStock ? 0 : stockCount,
              ),
            ],
            bids: [
              OpportunityMarketLevel(
                price: prices[id] ?? 1000,
                quantity: noBuyers ? 0 : buyerCount,
              ),
            ],
            bookFetchedAt: readClock().subtract(savedBookAge),
          ),
      },
    });
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: catalog,
      directory: harness.temporaryDirectory,
      clock: readClock,
      serviceFactory: (region) => OpportunityMarketService(
        region: region,
        quoteBatchSize: 1,
        utcNow: readClock,
        requestSpacing: Duration.zero,
        transport: _MarketFixture(
          beerId,
          readClock(),
          missingStock: missingStock,
          noBuyers: noBuyers,
          buyerCount: buyerCount,
          stockCount: stockCount,
          prices: prices,
          stocks: {
            for (final entry in stocksByName.entries)
              catalog.bundledMarketId(entry.key)!: entry.value,
          },
          preorders: {
            ...preorders,
            for (final entry in preordersByName.entries)
              catalog.bundledMarketId(entry.key)!: entry.value,
          },
          unavailableIds: {
            for (final name in unavailableNames) catalog.bundledMarketId(name)!,
          },
          requests: requests,
        ),
      ),
    );
    await controller.ready;
    await controller.calculationSettled;
    controller.change((p) {
      p.section = exchange ? 'exchanges' : 'crafting';
      p.owned['sangpyeong'] = 10000;
      p.profitableOnly = false;
    });
    await controller.refresh();
    if (!summaryOnly) {
      // Existing financial/golden scenarios deliberately exercise checked
      // order books. Startup itself now loads summary quotes only.
      await controller.ensureMarketDepth(controller.market.items.keys);
      await controller.ensureMarketDepth(const []);
    }
    await controller.calculationSettled;
    return _Fixture(harness, controller, requests);
  }

  Future<void> dispose() async {
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

/// Synthetic receipts exercise the production decoder; no request leaves tests.
final class _MarketFixture implements OpportunityMarketTransport {
  _MarketFixture(
    this.beerId,
    this.now, {
    this.missingStock = false,
    this.noBuyers = false,
    this.buyerCount = 100000,
    this.stockCount = 100000,
    this.unavailableIds = const {},
    this.prices = const {},
    this.stocks = const {},
    this.preorders = const {},
    this.requests,
  });
  final String beerId;
  final DateTime now;
  final bool missingStock;
  final bool noBuyers;
  final int buyerCount;
  final int stockCount;
  final Set<String> unavailableIds;
  final Map<String, int> prices;
  final Map<String, int> stocks;
  final Map<String, List<OpportunityMarketLevel>> preorders;
  final List<String>? requests;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final id = '${(jsonDecode(body) as Map)['mainKey']}';
    requests?.add('${uri.path.split('/').last}:$id');
    if (unavailableIds.contains(id)) {
      return OpportunityHttpResponse(statusCode: 500, bytes: Uint8List(0));
    }
    final price = prices[id] ?? (id == beerId ? 100000 : 1000);
    final quantity =
        stocks[id] ?? (missingStock || id == beerId ? 0 : stockCount);
    final listed = stocks[id] ?? (missingStock ? 0 : stockCount);
    final bidLevels =
        preorders[id] ??
        [
          OpportunityMarketLevel(
            price: price,
            quantity: noBuyers ? 0 : buyerCount,
          ),
        ];
    final text = uri.path.endsWith('GetBiddingInfoList')
        ? '${bidLevels.map((level) => '${level.price}-0-${level.quantity}').join('|')}|${price + 10}-$listed-0|'
        : '$id-0-0-$price-$quantity-500000-100-1000000-$price-${now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000}|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': text})),
      ),
    );
  }

  @override
  void close() {}
}

Future<void> _loadFonts() async {
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
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
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

Future<void> _captureSubstitutes(
  WidgetTester tester,
  String name, {
  Finder? region,
}) async {
  final directory = Platform.environment['OPPORTUNITY_SUBSTITUTE_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('opportunities-capture')),
  );
  final bounds = region == null
      ? Offset.zero & boundary.size
      : tester
            .getRect(region)
            .shift(-boundary.localToGlobal(Offset.zero))
            .inflate(8)
            .intersect(Offset.zero & boundary.size);
  await tester.runAsync(() async {
    final image = await (boundary.debugLayer! as OffsetLayer).toImage(bounds);
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

AppearanceSettings _appearanceSettings({
  required String background,
  double accentHue = 158,
  bool neon = false,
}) => AppearanceSettings(
  background: background,
  accentHue: accentHue,
  neon: neon,
  particleStyle: 'none',
  particleMinSize: 1,
  particleMaxSize: 1,
  particleHue: accentHue,
  buttonEffect: 'glow',
  buttonEffectHue: accentHue,
);
