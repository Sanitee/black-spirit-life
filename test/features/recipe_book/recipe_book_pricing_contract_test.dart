import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
  test(
    'both local and cross-mode profit sorts use per craft, not per output',
    () async {
      final app = fixture.controller(
        catalog,
        CraftMode.processing,
        'Wheat Flour',
        1,
      );
      app.active.updateState(
        (state) => state.copyWith(
          recipeEdits: {
            for (final batch in [false, true])
              (batch ? 'Audit Batch' : 'Audit Small'): RecipeState(
                type: 'processing',
                method: 'Heating',
                baseOutput: batch ? 10 : 1,
                outputMinimum: batch ? 10 : 1,
                outputMaximum: batch ? 10 : 1,
                marketId: batch ? '990002' : '990001',
                ingredients: [IngredientState(name: 'Wheat', quantity: 1)],
              ),
          },
          favoriteRecipes: ['Audit Batch', 'Audit Small'],
          bookFavoritesOnly: true,
          market: state.market.copyWith(
            prices: {'Wheat': 10, 'Audit Small': 1000, 'Audit Batch': 200},
            fetchedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: repository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: ['Audit Batch', 'Audit Small'],
      );
      final small = book.profitabilityFor('Audit Small')!;
      final batch = book.profitabilityFor('Audit Batch')!;
      expect(batch.profitPerCraft, greaterThan(small.profitPerCraft!));
      expect(batch.profitPerPiece, lessThan(small.profitPerPiece!));
      for (final search in ['', 'Audit']) {
        book.setSearch(search);
        book.setMarketSort(RecipeBookMarketSort.profitHighToLow);
        expect(book.snapshot.entries.map((e) => e.name), [
          'Audit Batch',
          'Audit Small',
        ]);
        book.setMarketSort(RecipeBookMarketSort.profitLowToHigh);
        expect(book.snapshot.entries.map((e) => e.name), [
          'Audit Small',
          'Audit Batch',
        ]);
      }
      book.dispose();
      await app.dispose();
    },
  );

  for (final savedFallback in [false, true]) {
    testWidgets(
      'zero stock values all three comparisons, saved fallback $savedFallback',
      (tester) async {
        final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: ['Beer'],
        );
        final grain = app.active.recipes['Beer']!.ingredients.first;
        final selected = book
            .ingredientChoices('Beer', grain)
            .firstWhere((r) => r.name == 'High-Quality Wheat');
        book.selectIngredientChoice('Beer', selected);
        final rows = book.availabilityFor('Beer').ingredients;
        final now = DateTime.now();
        app.active.updateState(
          (state) => state.copyWith(
            inventory: {for (final r in rows) r.name: r.quantity / 2},
            market: state.market.copyWith(
              region: 'eu',
              prices: {'Beer': 6000, selected.name: 200},
              stock: {'Beer': 0, selected.name: 0},
              fetchedAt: now.millisecondsSinceEpoch,
              preorderPrices: savedFallback
                  ? {'Beer': 10000, selected.name: 900}
                  : {},
              preorderObservedAt: savedFallback
                  ? {
                      'Beer': now.millisecondsSinceEpoch,
                      selected.name: now.millisecondsSinceEpoch,
                    }
                  : {},
            ),
          ),
          immediate: true,
        );
        final transport = ChoiceMarketTransport();
        final beer = repository.bundledMarketId('Beer')!;
        final wheat = repository.bundledMarketId(selected.name)!;
        transport.values[beer] = (price: 6000, stock: 0, preorders: 8);
        transport.values[wheat] = (price: 200, stock: 0, preorders: 3);
        transport.bookLevels[beer] = '9000-0-7|12000-0-0|10000-0-1';
        transport.bookLevels[wheat] = '500-0-2|1100-0-0|900-0-1';
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
          utcNow: () => savedFallback
              ? now.subtract(const Duration(minutes: 6))
              : DateTime.now(),
        );
        book.connectAvailabilityMarket(broker);
        final keys = [
          for (final id in [beer, wheat])
            SharedMarketKey(region: 'eu', itemId: id),
        ];
        final pending = broker.fetch(quoteKeys: keys, bookKeys: keys);
        await settle(tester, broker);
        await pending;
        await tester.pump(const Duration(milliseconds: 300));
        final quote = book.profitabilityFor('Beer')!;
        expect(quote.isAvailable, isTrue);
        expect(quote.ingredientCosts.first.unitPrice, 900);
        expect(
          quote.netRevenue,
          closeTo(quote.outputPerCraft! * 10000 * quote.marketNetRate!, .001),
        );
        final comparison = book.craftComparisonFor('Beer');
        expect(comparison.buyAllProfit, quote.profitPerCraft);
        expect(
          comparison.buyMissingReturn,
          closeTo(quote.netRevenue! - quote.ingredientCost! / 2, .001),
        );
        expect(
          comparison.sellOwnedProceeds,
          closeTo(selected.quantity / 2 * 900 * quote.marketNetRate!, .001),
        );
        book.dispose();
        await broker.dispose();
        await app.dispose();
      },
    );
  }
}
