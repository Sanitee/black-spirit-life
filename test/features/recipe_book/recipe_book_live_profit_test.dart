import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
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
  for (final scenario in ['quotes', 'scroll', 'region']) {
    testWidgets('live profit $scenario', (tester) async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: repository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: ['Beer'],
      );
      final transport = ChoiceMarketTransport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      book.connectAvailabilityMarket(broker);
      book.setMarketSort(RecipeBookMarketSort.availabilityProfit);
      final grain = app.active.recipes['Beer']!.ingredients.first;
      final hq = book
          .ingredientChoices('Beer', grain)
          .firstWhere((row) => row.name == 'High-Quality Wheat');
      book.selectIngredientChoice('Beer', hq);
      final rows = book.availabilityFor('Beer').ingredients;
      app.active.updateState(
        (state) => state.copyWith(
          inventory: {for (final row in rows) row.name: row.quantity * 8},
        ),
        immediate: true,
      );
      await tester.pump();
      final before = jsonEncode(app.documentSnapshot.toJson());
      expect(book.profitabilityFor('Beer')!.isAvailable, isFalse);
      final keys = [
        for (final name in ['Beer', ...rows.map((r) => r.name)])
          if (choiceMarketIdentity(app.active, name, acrossModes: true).marketId
              case final id?)
            SharedMarketKey(region: 'eu', itemId: id),
      ];
      final beerId = repository.bundledMarketId('Beer')!;
      final wheatId = repository.bundledMarketId(hq.name)!;
      transport.values[beerId] = (price: 10000, stock: 0, preorders: 10);
      transport.values[wheatId] = (price: 900, stock: 0, preorders: 84);
      Future<void> fetch(
        List<SharedMarketKey> requested, {
        bool force = false,
      }) async {
        final pending = broker.fetch(
          quoteKeys: requested,
          bookKeys: requested,
          forceRefresh: force,
        );
        await settle(tester, broker);
        await pending;
        await tester.pump(const Duration(milliseconds: 300));
      }

      await fetch(keys);
      final quote = book.profitabilityFor('Beer')!;
      expect(quote.isAvailable, isTrue);
      expect(quote.ingredientCosts.first.selectedName, hq.name);
      expect(quote.ingredientCosts.first.quantity, 2);
      expect(quote.ingredientCosts.first.unitPrice, 900);
      final result = book.craftComparisonFor('Beer');
      expect(result.buyAllProfit, quote.profitPerCraft);
      expect(result.buyMissingReturn, quote.netRevenue);
      expect(
        result.sellOwnedProceeds,
        closeTo(2 * 900 * quote.marketNetRate!, .001),
      );
      if (scenario == 'quotes') {
        transport.values[wheatId] = (price: 1200, stock: 0, preorders: 84);
        await fetch(keys, force: true);
        expect(
          book.profitabilityFor('Beer')!.ingredientCosts.first.unitPrice,
          1200,
        );
        expect(
          book.craftComparisonFor('Beer').buyAllProfit,
          closeTo(result.buyAllProfit! - 600, .001),
        );
        expect(
          jsonEncode(app.documentSnapshot.toJson()),
          before,
          reason:
              'Live valuation must not write saved price or inventory data.',
        );
        app.marketTax.value = MarketTax(valuePack: true);
        await tester.pump();
        expect(
          book.profitabilityFor('Beer')!.marketNetRate,
          closeTo(.845, .0001),
        );
        expect(
          book.craftComparisonFor('Beer').sellOwnedProceeds,
          closeTo(2 * 1200 * .845, .001),
        );
        app.active.updateState(
          (state) => state.copyWith(cookingMastery: 2000),
          immediate: true,
        );
        await tester.pump();
        final mastered = book.profitabilityFor('Beer')!;
        expect(
          book.craftComparisonFor('Beer').buyMissingReturn,
          mastered.netRevenue,
        );
      } else if (scenario == 'scroll') {
        var notifications = 0;
        book.addListener(() => notifications++);
        await fetch(keys); // cached receipts from remounting visible cards
        expect(notifications, 0);
        await fetch([SharedMarketKey(region: 'eu', itemId: '999999')]);
        expect(
          notifications,
          0,
          reason: 'Unrelated market activity must not rebuild Recipe Book.',
        );
        final pending = broker.fetch(
          quoteKeys: keys,
          bookKeys: keys,
          forceRefresh: true,
        );
        for (var i = 0; i < 10; i++) {
          book.recordScrollOffset(i * 100);
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            notifications,
            0,
            reason: 'Keep card order steady during scrolling.',
          );
        }
        await pending;
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          notifications,
          1,
          reason: 'One batched resort after scrolling stops.',
        );
      } else {
        app.active.updateState(
          (state) =>
              state.copyWith(market: state.market.copyWith(region: 'na')),
          immediate: true,
        );
        await tester.pump();
        expect(book.profitabilityFor('Beer')!.isAvailable, isFalse);
        expect(book.craftComparisonFor('Beer').buyMissingReturn, isNull);
        expect(book.craftComparisonFor('Beer').sellOwnedProceeds, isNull);
      }
      book.dispose();
      await broker.dispose();
      await app.dispose();
    });
  }
}
