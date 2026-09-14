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
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
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
          await _openCalculation(tester, 'Life Crystal');
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
            findsOneWidget,
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
            '1 needed',
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
          findsOneWidget,
        );
        expect(
          find.descendant(of: forest, matching: find.text('Stock')),
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
        expect(tester.widget<Text>(quantity).data, '1 needed');
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
        expect(tester.widget<Text>(quantity).data, '1 needed');
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
        expect(find.text('Buy these ingredients'), findsOneWidget);
        expect(
          find.descendant(of: trace, matching: find.text('Cost')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: trace,
            matching: find.text('Stock needs checking'),
          ),
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
        expect(find.text('Extra profit / item'), findsWidgets);
        expect(find.text('Other costs / item'), findsWidgets);
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
            lessThanOrEqualTo(rows.length <= 2 ? 480 : 560),
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
          (size: const Size(1200, 752), columns: 2),
          (size: const Size(1500, 940), columns: 3),
          (size: const Size(1900, 1100), columns: 4),
        ]) {
          tester.view.physicalSize = scenario.size;
          await _settleImages(tester);
          _expectCraftCardLayout(
            tester,
            expectedColumns: scenario.columns,
            firstRowTop: 260,
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
          _expectCraftCardLayout(tester, expectedColumns: 2, firstRowTop: 260);
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
            expect(card.width, lessThanOrEqualTo(480.1));
          }
          expect(
            cards.last.right,
            lessThan(bounds.right - 100),
            reason: 'Two matches do not stretch across the whole workspace.',
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
    'ordinary direction B cards remain compact without fixing their height',
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
          expect(card.top, closeTo(260, 1));
          expect(card.height, inInclusiveRange(156, 166));
          _expectCraftCardLayout(tester, expectedColumns: 1);
          _expectDirectionBCard(tester, name);
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
    'direction B card keeps rail and full values at 900 pixels and 200 percent',
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
        _expectDirectionBCard(tester, 'Beer');
        final card = find.byKey(const ValueKey('craft-card:Beer'));
        final quote = fixture.controller.visibleQuotes.single;
        for (final value in [
          _testSilver(quote.listingProfit!),
          _testSilver(quote.totalCost!),
          '−100.000',
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
          final available = _menuFilter('craft-ingredients-available');
          for (final label in [
            'Highest Demand',
            'Highest Profit',
            'Out of stock',
            'Ingredients available',
            'Profitable',
          ]) {
            expect(find.text(label), findsOneWidget);
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
          _expectFullWidthWorkspace(tester);
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
          await _settleCalculation(tester, fixture.controller);
          expect(fixture.controller.preferences.readyOnly, isTrue);
          expect(fixture.controller.visibleQuotes.single.recipeName, 'Beer');
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await _settleCalculation(tester, fixture.controller);
          expect(fixture.controller.preferences.readyOnly, isFalse);
          expect(fixture.requests.length, requests);
          for (final key in [
            'craft-has-demand',
            'craft-ingredients-available',
            'craft-profitable',
          ]) {
            await tester.tap(_menuFilter(key));
            await _settleCalculation(tester, fixture.controller);
            expect(
              tester.widget<FilterChip>(_menuFilter(key)).selected,
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
            await tester.tap(_menuFilter(key));
            await _settleCalculation(tester, fixture.controller);
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
            await tester.tap(_menuFilter(key));
            await _settleCalculation(tester, fixture.controller);
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
          expect(
            tester
                .widget<FilterChip>(_menuFilter('craft-ingredients-available'))
                .selected,
            isTrue,
          );
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
    _glassTestWidgets(
      'custom sale price is local, grouped and reversible $scale',
      (tester) async {
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
                '${formatQuantity(quote.listingRevenue!)} silver',
              ),
            ),
            findsOneWidget,
          );
          _expectMetricText(
            tester,
            find.byKey(
              const ValueKey('craft-result:Cup of Reticent Moonbeams'),
            ),
            'Profit',
            '${quote.hasEstimatedInputs ? '≈ ' : ''}${_testSilver(quote.listingProfit!)}',
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
      },
    );
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
            startsWith('${entry.value} needed'),
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
          _testSilver(customBefore.listingProfit! * 30),
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
          find.descendant(of: water, matching: find.text('Stock')),
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
          find.descendant(of: purified, matching: find.text('5.000')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: purified, matching: find.text('Market each')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: purified, matching: find.text('Stock')),
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
                  : '10.010',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: purified,
            matching: find.text(scenario.stock == 2 ? '15.220' : '25.000'),
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
          find.descendant(of: summary, matching: find.text('Stock')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('Preorders')),
          findsOneWidget,
        );
        if (scenario.name == 'no_preorders') {
          expect(
            find.descendant(of: dialog, matching: find.text('No preorders')),
            findsOneWidget,
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
            matching: find.text(scenario.missing ? '−15' : '6'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.byType(Table)),
          scenario.name == 'no_preorders' ? findsNothing : findsOneWidget,
        );
        expect(
          tester
              .getRect(
                find.descendant(of: dialog, matching: find.text('Preorders')),
              )
              .top,
          greaterThan(tester.getRect(summary).bottom),
        );
      } else {
        expect(
          find.descendant(of: dialog, matching: find.text('Stock')),
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
          matching: find.text('≈ ${_testSilver(estimate.listingProfit!)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('≈ ${_testSilver(estimate.totalCost!)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('−100.000')),
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
          matching: find.text(_testSilver(beer().listingProfit!)),
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
        expect(
          tester.getBottomLeft(finder).dy,
          lessThanOrEqualTo(tester.getTopLeft(summary).dy),
        );
      }

      expect(summary, findsOneWidget);
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
        expectAboveSummary(textInDialog('20× Caphras Stone'));
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
        expectAboveSummary(textInDialog('900× Contribution EXP'));
        expectAboveSummary(textInDialog('30× Cooking EXP'));
        expect(current().hasUnpricedRewards, isTrue);
        expect(current().netProceeds, isNull);
        expect(
          find.descendant(of: summary, matching: find.text('—')),
          findsNWidgets(2),
        );
      }

      final summaryBottom = tester.getBottomLeft(summary).dy;
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
        expect(belowSummaryText, [
          'Preorders',
          'Quantity',
          'Price each',
          '15',
          '2.000',
        ]);
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
        for (final currency in exchangeCatalog) {
          expect(
            find
                .byKey(ValueKey('exchange-currency-${currency.id}'))
                .hitTestable(),
            findsOneWidget,
          );
        }
      } else if (scenario.details) {
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is AppButton &&
                widget.semanticLabel == 'Calculation for Beer',
          ),
        );
        await _settleImages(tester);
        expect(find.text('Buy these ingredients'), findsOneWidget);
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
        _expectFullWidthWorkspace(tester);
        if (scenario.exchange) {
          _expectExchangeHeaderSpacing(tester);
          for (final currency in exchangeCatalog) {
            expect(
              find
                  .byKey(ValueKey('exchange-currency-${currency.id}'))
                  .hitTestable(),
              findsOneWidget,
            );
          }
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
          expect(find.text('Investment'), findsWidgets);
          expect(find.text('Sale after tax'), findsNothing);
          expect(find.textContaining('Buyers cover this batch'), findsNothing);
          expect(
            find.byKey(const ValueKey('craft-sort-options')),
            findsOneWidget,
          );
          expect(find.text('Demand'), findsNothing);
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
                ? (scenario.size.width >= 1280 ? 3 : 2)
                : 1,
          );
          expect(find.textContaining('Makes '), findsNothing);
          if (scenario.scale == 2) {
            final cardWidth = tester
                .getSize(find.byKey(const ValueKey('craft-card:Beer')))
                .width;
            expect(
              cardWidth,
              allOf(
                greaterThan(scenario.size.width * .84),
                lessThan(scenario.size.width * .86),
              ),
              reason:
                  'Double-sized text keeps the approved wide, centered card footprint.',
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
              matching: find.text(_testSilver(beer.listingProfit!)),
            ),
          );
          await _settleImages(tester);
          for (final value in [
            _testSilver(beer.listingProfit!),
            '−100.000',
            _testSilver(beer.totalCost!),
          ]) {
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
      fixture.controller.recalculate();
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
      expect(tester.widget<Text>(subtitle).data, startsWith('450 needed'));
      if (scenario.name == 'partial') {
        expect(
          tester.widget<Text>(subtitle).data,
          '450 needed · 20 from market',
        );
      }
      expect(
        tester.widget<Text>(subtitle).style?.color,
        scenario.red ? spec.palette.danger : spec.typography.meta.color,
      );
      final npc = find.byKey(const ValueKey('ingredient-quantity:Sugar'));
      expect(tester.widget<Text>(npc).data, '450 needed · NPC');
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
      tester.element(subtitle).visualTheme.palette.danger,
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
      expect(find.text('Investment'), findsWidgets);
      expect(find.text('Estimate · missing stock'), findsNothing);
      await _expectPassiveCraftEstimates(tester, beer);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppButton && w.semanticLabel == 'Calculation for Beer',
        ),
      );
      await _settleImages(tester);
      _expectIngredientColumns(tester, columns: 2);
      expect(
        find.textContaining('missing · estimated at 1.000 silver each'),
        findsNothing,
      );
      expect(find.text('Estimated profit'), findsNothing);
      expect(find.text('Ingredients · estimated'), findsNothing);
      expect(find.text('Ingredients'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('craft-result:Beer')),
          matching: find.text('≈ ${_testSilver(beer.listingProfit!)}'),
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
      for (final value in ['−123.456.789', '123.456.789']) {
        final number = find.descendant(
          of: find.byKey(const PageStorageKey('craft-opportunities')),
          matching: find.text(value),
        );
        expect(number, findsWidgets);
        final paragraph = tester.renderObject<RenderParagraph>(number.first);
        expect(
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: value.length),
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
      expect(find.text('0,1'), findsWidgets);
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
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is AppButton &&
              w.semanticLabel == 'Calculation for ${parent.recipeName}',
        ),
      );
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
      expect(find.text('Buy these ingredients'), findsOneWidget);
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
        expect(find.text('Buy these ingredients'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ingredient-recipe-trail')),
          findsNothing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Buy these ingredients'), findsOneWidget);
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
    final hundred = _buttonWithText('Standard · 100×');
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
    expect(find.text('Buy these ingredients'), findsOneWidget);
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
      expect(find.text('Buy these ingredients'), findsOneWidget);
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
      expect(find.text('−1'), findsWidgets);
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
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppButton &&
              widget.semanticLabel == 'Calculation for ${parent.recipeName}',
        ),
      );
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
        expect(find.text('Buy these ingredients'), findsOneWidget);
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
      final arrow = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppButton &&
              widget.semanticLabel == 'Calculation for Beer',
        ),
      );
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
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byKey(const ValueKey('craft-result:Beer')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settleImages(tester);
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
        isFalse,
        reason: 'The wrapper and decorative arrow must not add more Tab stops.',
      );
      await tester.tap(
        find.descendant(of: card, matching: find.text('Investment')),
      );
      await _settleImages(tester);
      expect(find.byKey(const ValueKey('craft-result:Beer')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, fixture.dispose());
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
      expect(brand.width, 32);
      expect(brand.height, 32);
      expect(brand.filterQuality, FilterQuality.high);
      expect(
        (brand.image as AssetImage).assetName,
        'assets/opportunities/items/66771.webp',
      );
      for (final section in ['crafting', 'exchanges', 'crafting']) {
        final control = find.byKey(ValueKey('opportunities-section-$section'));
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
        for (final name in ['crafting', 'exchanges']) {
          final tab = find.byKey(ValueKey('opportunities-section-$name'));
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
    'header tabs retain independent full-width pane scrolling',
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
        _expectFullWidthWorkspace(tester);
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
          _expectFullWidthWorkspace(tester);
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
          find.byKey(const ValueKey('craft-comparison-board')),
          findsNothing,
        );
        for (final label in ['Profit', 'Stock', 'Investment']) {
          expect(
            find.descendant(of: summary, matching: find.text(label)),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(
            of: summary,
            matching: find.text(_testSilver(quote.listingProfit!)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(_testSilver(quote.totalCost!)),
          ),
          findsOneWidget,
        );
        for (final metric in [
          (label: 'Profit', value: quote.listingProfit!),
          (label: 'Investment', value: quote.totalCost!),
        ]) {
          final heading = find.descendant(
            of: summary,
            matching: find.text(metric.label),
          );
          final amount = find.descendant(
            of: summary,
            matching: find.text(_testSilver(metric.value)),
          );
          expect(
            tester.getTopLeft(amount).dx,
            closeTo(tester.getTopLeft(heading).dx, .01),
            reason: '${metric.label} stays aligned with its card label.',
          );
          expect(
            tester.widget<Text>(amount).style?.fontSize,
            metric.label == 'Profit' ? 22 : 13,
          );
          expect(tester.widget<Text>(heading).style?.fontSize, 12);
          expect(
            tester.widget<Text>(amount).style?.fontWeight,
            metric.label == 'Profit' ? FontWeight.w700 : FontWeight.w500,
          );
        }
        final profitHeading = find.descendant(
          of: summary,
          matching: find.text('Profit'),
        );
        final profitAmount = find.descendant(
          of: summary,
          matching: find.text(_testSilver(quote.listingProfit!)),
        );
        final footer = find.byKey(ValueKey('craft-footer:${scenario.name}'));
        _expectDirectionBCard(tester, scenario.name);
        final title = find.descendant(
          of: card,
          matching: find.text(scenario.name),
        );
        expect(
          tester.getRect(profitHeading).top,
          greaterThan(tester.getRect(title).bottom),
          reason: 'Profit stays below the name in the right-hand content.',
        );
        expect(
          tester.getRect(footer).top,
          greaterThan(tester.getRect(profitAmount).bottom),
          reason: 'Stock and investment remain secondary to the profit.',
        );
        expect(
          find.descendant(of: footer, matching: find.text('Stock')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('Investment')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: footer, matching: find.text('Profit')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(_testSilver(quote.listingRevenue!)),
          ),
          findsNothing,
          reason:
              'Sale after tax belongs in the calculation, not the overview.',
        );
        expect(
          tester
              .widget<Text>(
                find.descendant(of: card, matching: find.text(scenario.name)),
              )
              .style
              ?.fontSize,
          16,
        );
        expect(
          tester
              .widget<Text>(
                find.descendant(of: card, matching: find.text(scenario.name)),
              )
              .style
              ?.fontWeight,
          FontWeight.w600,
        );
        final icon = tester.widget<ModeItemIcon>(
          find.descendant(of: card, matching: find.byType(ModeItemIcon)),
        );
        expect(icon.size, 40);
        expect(icon.showFrame, isFalse);
        expect(icon.fit, BoxFit.contain);
        expect(
          tester.getSize(
            find.byKey(ValueKey('craft-artwork-frame:${scenario.name}')),
          ),
          const Size(58, 58),
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              '${formatQuantity(quote.expectedOutput!)} items per batch',
            ),
          ),
          scenario.batches ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Profit /')),
          findsNothing,
        );
        await tester.tap(
          find.descendant(
            of: summary,
            matching: find.text(_testSilver(quote.totalCost!)),
          ),
        );
        await _settleImages(tester);
        expect(find.byType(Dialog), findsOneWidget);
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
              '${formatQuantity(quote.listingRevenue!)} silver',
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
          scenario.batches ? findsOneWidget : findsNothing,
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
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppButton &&
              widget.semanticLabel == 'Calculation for Beer',
        ),
      );
      await _settleImages(tester);
      expect(find.text('Buy these ingredients'), findsOneWidget);
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
        final calculation = find.byWidgetPredicate(
          (widget) =>
              widget is AppButton &&
              widget.semanticLabel == 'Calculation for Beer',
        );
        await tester.ensureVisible(calculation);
        await tester.tap(calculation);
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
            matching: find.text(_testSilver(beer().listingProfit!)),
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
  final summary = find.byKey(ValueKey('craft-summary:${quote.recipeName}'));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  try {
    for (final value in [quote.listingProfit!, quote.totalCost!]) {
      final amount = find.descendant(
        of: summary,
        matching: find.text('≈ ${_testSilver(value)}'),
      );
      expect(amount, findsOneWidget);
      await mouse.moveTo(tester.getCenter(amount));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Estimate using current'), findsNothing);
      expect(
        find.descendant(
          of: summary,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                (widget.message?.startsWith('Estimate using current') ?? false),
          ),
        ),
        findsNothing,
      );
    }
  } finally {
    await mouse.removePointer();
    await tester.pumpAndSettle();
  }
}

Future<void> _openCalculation(WidgetTester tester, String name) async {
  final button = find.byWidgetPredicate(
    (widget) =>
        widget is AppButton && widget.semanticLabel == 'Calculation for $name',
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settleImages(tester);
}

Future<void> _openIngredient(WidgetTester tester, String name) async {
  final link = find.byKey(ValueKey('ingredient-recipe-$name'));
  expect(link, findsOneWidget);
  await tester.ensureVisible(link);
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
        : '${quote.hasEstimatedInputs ? '≈ ' : ''}${_testSilver(quote.listingProfit!)}',
  );
  final money = find.byKey(const ValueKey('craft-money-summary'));
  expect(
    find.descendant(
      of: money,
      matching: find.text(
        quote.listingRevenue == null
            ? '—'
            : '${formatQuantity(quote.listingRevenue!)} silver',
      ),
    ),
    findsWidgets,
  );
  expect(
    find.descendant(
      of: money,
      matching: find.text(
        '${quote.hasEstimatedInputs ? '≈ ' : ''}−${formatQuantity(quote.totalCost!)} silver',
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
  expect(identity.top - toolbar.bottom, greaterThanOrEqualTo(15));
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
  expect(toolbar, findsOneWidget);
  _expectFullWidthWorkspace(tester);
  for (final mode in ['cooking', 'alchemy', 'processing']) {
    expect(
      find.descendant(
        of: toolbar,
        matching: find.byKey(ValueKey('craft-mode-$mode')),
      ),
      findsOneWidget,
      reason: 'Craft modes remain in the toolbar rather than a sidebar.',
    );
    expect(find.byKey(ValueKey('craft-mode-$mode')), findsOneWidget);
  }
  final groups = [
    find.descendant(
      of: toolbar,
      matching: find.byKey(const ValueKey('craft-mode-tabs')),
    ),
    find.descendant(
      of: toolbar,
      matching: find.byKey(const ValueKey('craft-search')),
    ),
    find.descendant(
      of: toolbar,
      matching: find.byKey(const ValueKey('craft-sort-options')),
    ),
  ];
  final rects = [for (final group in groups) tester.getRect(group)];
  final bounds = tester.getRect(toolbar);
  for (final rect in rects) {
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
    expect(rect.height, closeTo(40, .01));
  }
  final filters = tester.getRect(find.byKey(const ValueKey('craft-filters')));
  final [modes, search, sort] = rects;
  expect(search.top, closeTo(sort.top, .01));
  expect(search.left, closeTo(bounds.left, .01));
  expect(sort.right, closeTo(bounds.right, .01));
  expect(sort.left, greaterThan(search.right));
  expect(modes.top, greaterThanOrEqualTo(search.bottom));
  expect(modes.left, closeTo(bounds.left, .01));
  expect(filters.right, closeTo(bounds.right, .01));
  expect(filters.left, greaterThan(modes.right));
  expect(modes.center.dy, closeTo(filters.center.dy, 1));
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

void _expectFullWidthWorkspace(WidgetTester tester) {
  expect(find.byKey(const ValueKey('opportunities-sidebar')), findsNothing);
  final sections = find.byKey(const ValueKey('opportunities-sections'));
  expect(sections, findsOneWidget);
  for (final section in ['Crafting', 'Exchanges']) {
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
  expect(panes.left, closeTo(workspace.left + 24, .01));
  expect(panes.right, closeTo(workspace.right - 24, .01));
  final list = find.byKey(const PageStorageKey('craft-opportunities'));
  if (list.evaluate().isNotEmpty) {
    expect(tester.getRect(list).left, closeTo(panes.left, .01));
    expect(tester.getRect(list).right, closeTo(panes.right, .01));
  }
}

void _expectDirectionBCard(WidgetTester tester, String name) {
  final card = tester.getRect(find.byKey(ValueKey('craft-card:$name')));
  final rail = tester.getRect(find.byKey(ValueKey('craft-artwork-rail:$name')));
  final frame = tester.getRect(
    find.byKey(ValueKey('craft-artwork-frame:$name')),
  );
  final summary = find.byKey(ValueKey('craft-summary:$name'));
  final title = tester.getRect(
    find.descendant(of: summary, matching: find.text(name)),
  );
  final profit = tester.getRect(
    find.descendant(of: summary, matching: find.text('Profit')),
  );
  final footer = find.byKey(ValueKey('craft-footer:$name'));
  final stock = tester.getRect(
    find.descendant(of: footer, matching: find.text('Stock')),
  );
  expect(rail.width, closeTo(76, .01));
  expect(rail.left, closeTo(card.left, 1.1));
  expect(rail.top, closeTo(card.top, 1.1));
  expect(rail.bottom, closeTo(card.bottom, 1.1));
  expect(frame.size, const Size(58, 58));
  expect(frame.center.dx, closeTo(rail.center.dx, .01));
  expect(frame.center.dy, closeTo(rail.center.dy, .01));
  final holder = tester.widget<DecoratedBox>(
    find.byKey(ValueKey('craft-artwork-frame:$name')),
  );
  expect((holder.decoration as BoxDecoration).border, isNull);
  final artwork = tester.widget<ModeItemIcon>(
    find.descendant(
      of: find.byKey(ValueKey('craft-artwork-frame:$name')),
      matching: find.byType(ModeItemIcon),
    ),
  );
  expect(artwork.size, 40);
  expect(artwork.fit, BoxFit.contain);
  expect(artwork.showFrame, isFalse);
  for (final label in ['Stock', 'Investment']) {
    expect(
      tester
          .widget<Text>(find.descendant(of: footer, matching: find.text(label)))
          .style
          ?.fontSize,
      12,
    );
  }
  expect(title.left, closeTo(rail.right + 16, .01));
  expect(profit.left, closeTo(title.left, .01));
  expect(stock.left, closeTo(title.left, .01));
  expect(title.right, lessThanOrEqualTo(card.right));
  expect(profit.top, greaterThan(title.bottom));
  expect(tester.getRect(footer).top, greaterThan(profit.bottom));
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
      lessThanOrEqualTo(560 * scale + .1),
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
      rects[i].left,
      closeTo(firstRow[i % expectedColumns].left, .01),
      reason: 'Following rows retain the same column alignment.',
    );
  }
}

void _expectMarketNumberOnOneLine(WidgetTester tester) {
  final value = find.descendant(
    of: find.byKey(const PageStorageKey('craft-opportunities')),
    matching: find.text('−100.000'),
  );
  expect(value, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(value);
  final boxes = paragraph.getBoxesForSelection(
    const TextSelection(baseOffset: 0, extentOffset: 8),
  );
  expect(
    boxes,
    hasLength(1),
    reason: 'Market counts must not split digits across lines at large text.',
  );
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

Widget _host(OpportunitiesController controller) => RepaintBoundary(
  key: const ValueKey('opportunities-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: OpportunitiesWorkspace(controller: controller)),
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

Future<void> _captureSubstitutes(WidgetTester tester, String name) async {
  final directory = Platform.environment['OPPORTUNITY_SUBSTITUTE_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('opportunities-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
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
