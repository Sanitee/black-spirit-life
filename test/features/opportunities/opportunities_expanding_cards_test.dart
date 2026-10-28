import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_craft_card_material.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
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
  for (final theme in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    testWidgets('compact inline cards, artwork and scale $theme', (
      tester,
    ) async {
      final f = await _fixture(tester, theme, beerPrice: 100);
      try {
        await tester.pumpWidget(_host(f));
        for (final view in [
          (const Size(1200, 900), 1.0),
          (const Size(1000, 1000), 1.5),
          (const Size(900, 1100), 2.0),
        ]) {
          configureApplicationTestSurface(
            tester,
            view.$1,
            textScaleFactor: view.$2,
          );
          await _settleImages(tester);
          final card = _card('Beer');
          final header = find.byKey(const ValueKey('craft-header:Beer'));
          final mount = find.byKey(const ValueKey('craft-artwork-rail:Beer'));
          final before = tester.getRect(header);
          final bay = find.byKey(const ValueKey('craft-colour-bay:Beer'));
          expect(tester.getRect(bay).height, closeTo(before.height, .01));
          expect(tester.getRect(bay).width, 62);
          expect(
            tester.getCenter(mount).dx,
            closeTo(tester.getCenter(bay).dx, .01),
          );
          expect(tester.getCenter(mount).dy, closeTo(before.center.dy, .01));
          expect(
            find.byKey(const ValueKey('craft-inline-details:Beer')),
            findsNothing,
          );
          if (view.$2 == 1) {
            expect(before.height, lessThan(160));
            expect(before.width, lessThanOrEqualTo(332));
          }
          final icons = find.descendant(
            of: card,
            matching: find.byType(ModeItemIcon),
          );
          expect(
            tester.widgetList<ModeItemIcon>(icons).map((w) => w.name),
            containsAll(['Beer', 'Silver']),
          );
          expect(find.byKey(ModeItemIconKeys.image('Silver')), findsWidgets);
          expect(tester.takeException(), isNull);
          await _capture(tester, card, '$theme-${view.$2}-closed');
          await tester.tap(
            find.byKey(const ValueKey('craft-expand-button:Beer')),
          );
          await tester.pumpAndSettle();
          final detail = find.byKey(
            const ValueKey('craft-inline-details:Beer'),
          );
          expect(detail, findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          expect(tester.getRect(detail).width, closeTo(before.width, .01));
          expect(tester.getRect(detail).top, greaterThan(before.bottom));
          expect(tester.getRect(header), before);
          expect(tester.getCenter(mount).dy, closeTo(before.center.dy, .01));
          for (final label in [
            'Sell ingredients',
            'Craft or sell',
            'Sales after tax',
            'All owned',
            'Buy missing materials',
          ]) {
            expect(
              find.descendant(of: card, matching: find.text(label)),
              findsOneWidget,
            );
          }
          for (final label in [
            'Investment',
            'Average yield',
            'Crafts available',
            'per item',
            'Using your inventory',
          ]) {
            expect(
              find.descendant(of: card, matching: find.text(label)),
              findsNothing,
            );
          }
          final quote = f.controller.visibleQuotes.single;
          final reading = OpportunityPerItemQuote(
            quote,
            f.controller.craftSaleMode,
          );
          expect(reading.profit, isNegative);
          final text = tester.widget<Text>(
            find.byKey(const ValueKey('craft-per-item-profit:Beer')),
          );
          expect(text.data, startsWith('−'));
          expect(text.data, isNot(contains('≈')));
          final spec = tester.element(card).visualTheme;
          expect(
            text.style!.color,
            OpportunityCraftCardMaterial.forSpec(
              spec,
              OpportunityStockTone.available,
            ).lossInk,
          );
          await _capture(tester, card, '$theme-${view.$2}-open');
          await tester.tap(
            find.byKey(const ValueKey('craft-scenario-all:Beer')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Sell all materials'), findsOneWidget);
          expect(find.text('Buy missing materials'), findsNothing);
          expect(tester.takeException(), isNull);
          await _capture(tester, card, '$theme-${view.$2}-all-owned');
          await tester.ensureVisible(
            find.byKey(const ValueKey('craft-expand-button:Beer')),
          );
          await tester.tap(
            find.byKey(const ValueKey('craft-expand-button:Beer')),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('craft-per-item-profit:Beer')),
                )
                .data,
            text.data,
          );
          expect(tester.takeException(), isNull);
          final recipeButton = find.byKey(
            const ValueKey('craft-recipe-button:Beer'),
          );
          final compareButton = find.byKey(
            const ValueKey('craft-expand-button:Beer'),
          );
          expect(
            tester.getRect(recipeButton).width,
            closeTo(tester.getRect(compareButton).width, .01),
          );
          expect(
            tester.getRect(recipeButton).top,
            tester.getRect(compareButton).top,
          );
          await tester.tap(recipeButton);
          await _settleImages(tester);
          final recipe = find.byKey(const ValueKey('craft-inline-recipe:Beer'));
          expect(recipe, findsOneWidget);
          expect(
            find.byKey(const ValueKey('craft-inline-details:Beer')),
            findsNothing,
          );
          expect(tester.getRect(recipe).width, closeTo(before.width, .01));
          expect(tester.getRect(header), before);
          for (final input in quote.ingredients) {
            final row = find.byKey(
              ValueKey('craft-recipe-row:Beer:${input.name}'),
            );
            final bay = find.byKey(
              ValueKey('craft-ingredient-bay:Beer:${input.name}'),
            );
            final art = find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (w) => w is ModeItemIcon && w.name == input.name,
              ),
            );
            expect(row, findsOneWidget);
            expect(
              tester.getCenter(art).dy,
              closeTo(tester.getCenter(bay).dy, .01),
            );
            expect(
              tester.getCenter(art).dx,
              closeTo(tester.getCenter(bay).dx, .01),
            );
            final npc = (input.npcUnitPrice ?? 0) > 0;
            expect(
              find.descendant(
                of: row,
                matching: find.byIcon(npc ? Icons.person_outline : Icons.check),
              ),
              findsOneWidget,
            );
          }
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
          await _capture(tester, card, '$theme-${view.$2}-recipe');
          final planner = find.byKey(const ValueKey('craft-planner:Beer'));
          await tester.ensureVisible(planner);
          await tester.pumpAndSettle();
          expect(planner.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (view.$2 == 2) {
            await _capture(tester, card, '$theme-2.0-recipe-scrolled');
          }
          await tester.ensureVisible(compareButton);
          await tester.pumpAndSettle();
          await tester.tap(compareButton);
          await tester.pumpAndSettle();
          expect(recipe, findsNothing);
          expect(
            find.byKey(const ValueKey('craft-inline-details:Beer')),
            findsOneWidget,
          );
          await tester.tap(recipeButton);
          await tester.pumpAndSettle();
          expect(recipe, findsOneWidget);
          await tester.tap(recipeButton);
          await tester.pumpAndSettle();
          expect(recipe, findsNothing);
          expect(
            find.byKey(const ValueKey('craft-inline-details:Beer')),
            findsNothing,
          );
        }
        expect(f.transport.requests, 0);
      } finally {
        await _dispose(tester, f);
      }
    });
  }

  for (final target in [
    (CraftMode.alchemy, 'Clear Liquid Reagent'),
    (CraftMode.processing, 'Corn Flour'),
  ]) {
    testWidgets('Recipe uses the selected formula in ${target.$1.name}', (
      tester,
    ) async {
      final f = await _fixture(tester, 'sakura-night-garden');
      try {
        f.controller.change((p) {
          p.mode = target.$1;
          p.craftSearch = target.$2;
        }, assemble: true);
        await _settleCalculation(tester, f.controller);
        await tester.pumpWidget(_host(f));
        await _settleImages(tester);
        final quote = f.controller.visibleQuotes.singleWhere(
          (q) => q.recipeName == target.$2,
        );
        final before = f.controller.appController.documentSnapshot;
        await tester.tap(
          find.byKey(ValueKey('craft-recipe-button:${target.$2}')),
        );
        await _settleImages(tester);
        for (final input in quote.ingredients) {
          expect(
            find.byKey(ValueKey('craft-recipe-row:${target.$2}:${input.name}')),
            findsOneWidget,
          );
        }
        final planner = find.byKey(ValueKey('craft-planner:${target.$2}'));
        await tester.ensureVisible(planner);
        await tester.pumpAndSettle();
        await tester.tap(planner);
        expect(f.planned.single.exactName, target.$2);
        expect(f.planned.single.mode, target.$1);
        expect(f.controller.appController.documentSnapshot, same(before));
        expect(f.transport.requests, 0);
        expect(tester.takeException(), isNull);
        await _capture(tester, _card(target.$2), 'recipe-${target.$1.name}');
      } finally {
        await _dispose(tester, f);
      }
    });
  }

  for (final state in [
    (0, 25, false, OpportunityStockTone.outOfStock, Icons.remove),
    (100000, 25, false, OpportunityStockTone.mixed, Icons.check),
    (100000, 25, true, OpportunityStockTone.unknown, Icons.help_outline),
  ]) {
    testWidgets(
      'recipe availability ${state.$4.name} never confuses NPC or stale data',
      (tester) async {
        final f = await _fixture(
          tester,
          'sakura-night-garden',
          inputStock: state.$1,
          inputPreorders: state.$2,
          staleInputs: state.$3,
        );
        try {
          await tester.pumpWidget(_host(f));
          await _settleImages(tester);
          final snapshot = f.controller.appController.documentSnapshot;
          final quote = f.controller.visibleQuotes.single;
          await tester.tap(
            find.byKey(const ValueKey('craft-recipe-button:Beer')),
          );
          await _settleImages(tester);
          var npcCount = 0;
          var marketCount = 0;
          for (final input in quote.ingredients) {
            final npc = (input.npcUnitPrice ?? 0) > 0;
            if (npc) {
              npcCount++;
            } else {
              marketCount++;
            }
            final row = find.byKey(
              ValueKey('craft-recipe-row:Beer:${input.name}'),
            );
            final bay = tester.widget<DecoratedBox>(
              find.byKey(ValueKey('craft-ingredient-bay:Beer:${input.name}')),
            );
            final material = OpportunityCraftCardMaterial.forSpec(
              tester.element(row).visualTheme,
              npc ? OpportunityStockTone.available : state.$4,
            );
            expect((bay.decoration as BoxDecoration).color, material.bay);
            expect(
              find.descendant(
                of: row,
                matching: find.byIcon(npc ? Icons.person_outline : state.$5),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: row,
                matching: find.byIcon(Icons.shopping_basket_outlined),
              ),
              npc || state.$3 ? findsNothing : findsOneWidget,
            );
            expect(
              find.descendant(of: row, matching: find.text('NPC')),
              npc ? findsOneWidget : findsNothing,
            );
            if (!npc && state.$3) {
              expect(
                find.descendant(of: row, matching: find.text('Stock —')),
                findsOneWidget,
              );
            }
          }
          expect(npcCount, greaterThan(0));
          expect(marketCount, greaterThan(0));
          expect(f.controller.visibleQuotes.single, same(quote));
          expect(f.controller.appController.documentSnapshot, same(snapshot));
          expect(f.transport.requests, 0);
          expect(tester.takeException(), isNull);
          await _capture(tester, _card('Beer'), 'recipe-${state.$4.name}');
        } finally {
          await _dispose(tester, f);
        }
      },
    );
  }

  testWidgets('inventory comparison is local and has no sell-info tooltip', (
    tester,
  ) async {
    final f = await _fixture(tester, 'sakura-night-garden', beerPreorders: 25);
    try {
      final input = f.controller.visibleQuotes.single.ingredients.first;
      f.controller.modeController.commitInventory(input.name, '100');
      f.controller.change((p) => p.useInventory = true);
      await _settleCalculation(tester, f.controller);
      await tester.pumpWidget(_host(f));
      await _settleImages(tester);
      final quote = f.controller.visibleQuotes.single;
      expect(quote.usesInventory, isTrue);
      expect(quote.ingredients.any((i) => i.ownedQuantity > 0), isTrue);
      final initialState = f.controller.appController.documentSnapshot;
      final card = _card('Beer');
      final initialProfit = tester
          .widget<Text>(
            find.byKey(const ValueKey('craft-per-item-profit:Beer')),
          )
          .data;
      expect(
        find.ancestor(
          of: find.text('Sell ingredients'),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.info_outline)),
        findsNothing,
      );
      final counts = find.byKey(const ValueKey('craft-market-counts:Beer'));
      final initialCounts = tester
          .widgetList<Text>(
            find.descendant(of: counts, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      expect(initialCounts.any((s) => s!.startsWith('Stock ')), isTrue);
      expect(initialCounts.any((s) => s!.startsWith('Preorders ')), isTrue);
      await tester.tap(find.byKey(const ValueKey('craft-expand-button:Beer')));
      await tester.pumpAndSettle();
      expect(find.text('Your inventory'), findsOneWidget);
      expect(find.text('Sell owned materials'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('craft-scenario-all:Beer')));
      await tester.pumpAndSettle();
      expect(find.text('Sell all materials'), findsOneWidget);
      expect(f.controller.visibleQuotes.single, same(quote));
      expect(f.controller.appController.documentSnapshot, same(initialState));
      expect(f.controller.preferences.useInventory, isTrue);
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: counts, matching: find.byType(Text)),
            )
            .map((t) => t.data)
            .toList(),
        initialCounts,
      );
      await tester.tap(
        find.byKey(const ValueKey('craft-scenario-inventory:Beer')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('craft-per-item-profit:Beer')),
            )
            .data,
        initialProfit,
      );
      expect(f.transport.requests, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, f);
    }
  });

  testWidgets(
    'one expansion, independent columns, sorted position and scrolling',
    (tester) async {
      final f = await _fixture(tester, 'sakura-night-garden');
      try {
        f.controller.change((p) {
          p.craftSearch = '';
          p.craftSort = 'profit';
        });
        await _settleCalculation(tester, f.controller);
        await tester.pumpWidget(_host(f));
        await _settleImages(tester);
        final margins = f.controller.visibleQuotes
            .map(
              (quote) => OpportunityPerItemQuote(
                quote,
                f.controller.craftSaleMode,
              ).profit,
            )
            .whereType<double>()
            .toList();
        for (var i = 1; i < margins.length; i++) {
          expect(margins[i], lessThanOrEqualTo(margins[i - 1]));
        }
        final names = f.controller.visibleQuotes
            .take(4)
            .map((q) => q.recipeName)
            .toList();
        final first = find.byKey(ValueKey('craft-expand-button:${names[0]}'));
        final second = find.byKey(ValueKey('craft-expand-button:${names[1]}'));
        final neighborBefore = tester.getRect(_card(names[1]));
        expect(
          neighborBefore.left,
          greaterThan(tester.getRect(_card(names[0])).left),
        );
        final initialState = f.controller.appController.documentSnapshot;
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(tester.getRect(_card(names[1])), neighborBefore);
        expect(
          find.byKey(ValueKey('craft-inline-details:${names[0]}')),
          findsOneWidget,
        );
        await tester.tap(second);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('craft-inline-details:${names[0]}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('craft-inline-details:${names[1]}')),
          findsOneWidget,
        );
        expect(f.controller.appController.documentSnapshot, same(initialState));
        await _capture(tester, find.byKey(_captureKey), 'workspace-expanded');
        await tester.drag(
          find.byKey(const PageStorageKey('craft-opportunities')),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('craft-expand-button:${names[0]}')).hitTestable(),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        expect(f.transport.requests, 0);
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  testWidgets(
    'stock colours stay independent from profit and unknown stays unknown',
    (tester) async {
      for (final state in [
        (100, 0, 1000, OpportunityStockTone.available),
        (100, 25, 100, OpportunityStockTone.mixed),
        (0, 25, 1000, OpportunityStockTone.outOfStock),
        (0, 0, 763, OpportunityStockTone.outOfStock),
        (null, 0, 1000, OpportunityStockTone.unknown),
      ]) {
        final f = await _fixture(
          tester,
          'sakura-night-garden',
          beerStock: state.$1,
          beerPreorders: state.$2,
          beerPrice: state.$3,
        );
        try {
          await tester.pumpWidget(_host(f));
          await _settleImages(tester);
          final reading = OpportunityCardStock(
            f.controller.outputMarketFor('Beer'),
            f.controller.clock(),
            f.controller.cachedMarketMaxAge,
          );
          expect(reading.tone, state.$4);
          expect(reading.stock, state.$1);
          final card = _card('Beer');
          final palette = tester.element(card).visualTheme.palette;
          final material = OpportunityCraftCardMaterial.forSpec(
            tester.element(card).visualTheme,
            state.$4,
          );
          final bay = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('craft-colour-bay:Beer')),
          );
          expect((bay.decoration as BoxDecoration).color, material.bay);
          final header = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('craft-header:Beer')),
          );
          expect(
            (header.decoration as BoxDecoration).gradient,
            material.headerWash,
          );
          final counts = find.byKey(const ValueKey('craft-market-counts:Beer'));
          final label = tester.widget<Text>(
            find.descendant(of: counts, matching: find.byType(Text)).first,
          );
          expect(label.style!.color, material.badgeInk);
          if (state.$1 == null) expect(label.data, 'Stock —');
          if (state.$1 == 0) expect(label.data, 'Stock 0');
          if ((state.$1 ?? 0) > 0 && state.$2 > 0) {
            expect(
              find.descendant(of: counts, matching: find.text('Preorders 25')),
              findsOneWidget,
            );
          }
          final profit = tester.widget<Text>(
            find.byKey(const ValueKey('craft-per-item-profit:Beer')),
          );
          if (state.$3 == 100) expect(profit.data, startsWith('−'));
          if (state.$3 == 1000) expect(profit.style!.color, palette.text);
          if (state.$3 == 763) {
            expect(profit.data, '0');
            expect(profit.style!.color, material.mutedInk);
          }
          await _capture(tester, card, 'stock-${state.$4.name}-${state.$2}');
          expect(tester.takeException(), isNull);
          expect(f.transport.requests, 0);
        } finally {
          await _dispose(tester, f);
        }
      }
    },
  );

  testWidgets(
    'favourite, inline ingredients, copy, Planner and advanced inspection work',
    (tester) async {
      final f = await _fixture(tester, 'sakura-night-garden');
      try {
        await tester.pumpWidget(_host(f));
        await _settleImages(tester);
        await tester.tap(
          find.byKey(const ValueKey('craft-expand-button:Beer')),
        );
        await tester.pumpAndSettle();
        final inv = f.controller.modeController.state.value.inventory;
        final wasFavorite = f
            .controller
            .modeController
            .state
            .value
            .favoriteRecipes
            .contains('Beer');
        await tester.tap(find.byKey(const ValueKey('craft-favourite:Beer')));
        await _settleCalculation(tester, f.controller);
        expect(
          f.controller.modeController.state.value.favoriteRecipes.contains(
            'Beer',
          ),
          !wasFavorite,
        );
        expect(f.controller.modeController.state.value.inventory, inv);
        await tester.tap(
          find.byKey(const ValueKey('craft-recipe-button:Beer')),
        );
        await _settleImages(tester);
        for (final input in f.controller.visibleQuotes.single.ingredients) {
          expect(
            find.descendant(of: _card('Beer'), matching: find.text(input.name)),
            findsOneWidget,
          );
        }
        await _capture(tester, _card('Beer'), 'inline-ingredients');
        await tester.tap(
          find.byKey(const ValueKey('opportunity-copy-name:Beer')),
        );
        await tester.pumpAndSettle();
        expect(f.copied, ['Beer']);
        await tester.tap(find.byKey(const ValueKey('craft-planner:Beer')));
        expect(f.planned.single.exactName, 'Beer');
        expect(f.planned.single.mode, CraftMode.cooking);
        expect(find.byKey(const ValueKey('craft-inspect:Beer')), findsNothing);
        expect(
          find.descendant(
            of: _card('Beer'),
            matching: find.text('Ingredients'),
          ),
          findsNothing,
        );
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('craft-expand:Beer'))),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('View recipe'));
        await _settleImages(tester);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byKey(const ValueKey('root-recipe-page')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(
          find.byKey(const ValueKey('craft-inline-recipe:Beer')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  testWidgets('item-only hover remains and keyboard expands without a modal', (
    tester,
  ) async {
    final f = await _fixture(tester, 'sakura-night-garden');
    try {
      await tester.pumpWidget(_host(f));
      await _settleImages(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(
        tester.getCenter(
          find.descendant(of: _card('Beer'), matching: find.text('Beer')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(ItemReferenceCard), findsNothing);
      final icon = find.descendant(
        of: _card('Beer'),
        matching: find.byWidgetPredicate(
          (w) => w is ModeItemIcon && w.name == 'Beer',
        ),
      );
      await mouse.moveTo(tester.getCenter(icon));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.byType(ItemReferenceCard), findsOneWidget);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 800));
      await mouse.removePointer();
      await tester.pumpAndSettle();
      final ink = find.byKey(const ValueKey('craft-expand:Beer'));
      final focus = find
          .descendant(of: ink, matching: find.byType(Focus))
          .first;
      Focus.of(
        tester.element(
          find.descendant(of: focus, matching: find.byType(Actions)).first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('craft-inline-details:Beer')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(f.transport.requests, 0);
    } finally {
      await _dispose(tester, f);
    }
  });
}

Widget _host(_Fixture f) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ThemeSpecScope(
      spec: applicationThemeForAppearance(
        f.controller.modeController.state.value.appearance,
      ),
      child: OpportunityItemActionsScope(
        externalActions: PlannerExternalActions(
          openRecipeBook: (_) => throw StateError('Unexpected recipe book'),
          copyName: (name) async => f.copied.add(name),
          checkPrices: (_) async =>
              throw StateError('Unexpected price request'),
          openPlannerTarget: f.planned.add,
        ),
        child: Scaffold(body: OpportunitiesWorkspace(controller: f.controller)),
      ),
    ),
  ),
);

class _Fixture {
  _Fixture(this.harness, this.controller, this.transport);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final _NoNetwork transport;
  final planned = <PlannerTargetRequest>[];
  final copied = <String>[];
}

Future<_Fixture> _fixture(
  WidgetTester tester,
  String background, {
  int beerPrice = 1000,
  int? beerStock = 100000,
  int beerPreorders = 0,
  int inputStock = 100000,
  int inputPreorders = 0,
  bool staleInputs = false,
}) async {
  configureApplicationTestSurface(tester, const Size(1200, 900));
  return (await tester.runAsync(() async {
    final harness = await ApplicationTestHarness.create(
      activeMode: CraftMode.cooking,
      backgroundId: background,
    );
    final catalog = CatalogRepository(harness.bundle.catalog);
    final beerId = harness
        .bundle
        .controller
        .modes[CraftMode.cooking]!
        .recipes['Beer']!
        .marketId;
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
            basePrice: id == beerId ? beerPrice : 1000,
            stock: id == beerId ? beerStock : inputStock,
            quoteFetchedAt: id != beerId && staleInputs
                ? now.subtract(const Duration(days: 2))
                : now,
            asks: id == beerId && beerStock == null
                ? null
                : [
                    OpportunityMarketLevel(
                      price: id == beerId ? beerPrice : 1000,
                      quantity: id == beerId ? beerStock! : inputStock,
                    ),
                  ],
            bids: (id == beerId ? beerPreorders : inputPreorders) > 0
                ? [
                    OpportunityMarketLevel(
                      price: beerPrice,
                      quantity: id == beerId ? beerPreorders : inputPreorders,
                    ),
                  ]
                : const [],
            bookFetchedAt: id != beerId && staleInputs
                ? now.subtract(const Duration(days: 2))
                : now,
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
  final directory = Platform.environment['BSL_OPPORTUNITY_CAPTURE_DIR'];
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
