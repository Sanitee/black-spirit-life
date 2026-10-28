import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'opportunity_calculator_test.dart' as f;

void main() {
  const listing = OpportunitySaleMode.listing;
  test('buying missing inputs can lose while owning all can gain', () {
    final quote = f.calculate(
      product: f.recipe('Product', ingredients: [f.ingredient('Ore', 2)]),
      output: f.marketItem('1', price: 205),
      input: f.marketItem('2', price: 100, asks: [f.level(100, 100)]),
      useInventory: true,
      state: f.state(inventory: {'Ore': 1}),
    );
    final comparison = OpportunityCraftComparison(quote, listing);
    expect(comparison.sale, closeTo(173.225, 1e-8));
    expect(comparison.purchases, 100);
    expect(comparison.ownedSales, closeTo(84.5, 1e-8));
    expect(comparison.allSales, closeTo(169, 1e-8));
    expect(comparison.inventoryProfit, closeTo(-11.275, 1e-8));
    expect(comparison.allOwnedProfit, closeTo(4.225, 1e-8));
    expect(
      comparison.inventoryProfit,
      closeTo(OpportunityPerItemQuote(quote, listing).profit!, 1e-8),
    );
    expect(
      OpportunityCraftComparison.decision(comparison.inventoryProfit),
      OpportunityCraftDecision.sell,
    );
    expect(
      OpportunityCraftComparison.decision(comparison.allOwnedProfit),
      OpportunityCraftDecision.craft,
    );
    expect(quote.ingredients.single.ownedQuantity, 1);
  });
  test(
    'all-owned uses identical formula and retains extra costs exactly once',
    () {
      final quote = f.calculate(
        crafts: 3,
        product: f.recipe(
          'Product',
          variants: [
            f.variant('ten', [f.ingredient('Ore', 10)], output: 10, batch: 10),
          ],
        ),
        selectedVariantId: 'ten',
        useInventory: true,
        state: f.state(inventory: {'Ore': 999}),
        extraCostPerRun: 30,
        extraCostPerCraft: 10,
      );
      final c = OpportunityCraftComparison(quote, listing);
      expect(c.extraCosts, 2);
      expect(c.purchases, 0);
      expect(c.allSales, closeTo(8.45, 1e-8));
      expect(c.ownedSales, c.allSales);
      expect(c.inventoryProfit, c.allOwnedProfit);
      expect(c.allOwnedProfit, closeTo(c.sale! - 2 - c.allSales!, 1e-8));
      expect(quote.ingredients.single.quantity, 30);
    },
  );
  test('unpriced resale is unknown even when a purchase cost is known', () {
    for (final input in [
      f.marketItem('2', quoteTime: f.now.subtract(const Duration(days: 1))),
      f.marketItem('2', unlisted: true),
    ]) {
      final c = OpportunityCraftComparison(f.calculate(input: input), listing);
      expect(c.allSales, isNull);
      expect(c.allOwnedProfit, isNull);
      expect(
        OpportunityCraftComparison.decision(c.allOwnedProfit),
        OpportunityCraftDecision.unknown,
      );
    }
    final c = OpportunityCraftComparison(f.calculate(omitInput: true), listing);
    expect(c.allSales, isNull);
    expect(c.inventoryProfit, isNull);
  });
  test('non-marketable inputs have no market resale; purchase costs stay', () {
    final quote = f.calculate(nonMarketableIds: {'2'});
    final c = OpportunityCraftComparison(quote, listing);
    expect(c.allSales, 0);
    expect(c.purchases, 10);
    expect(c.allOwnedProfit, c.sale);
  });
  test('inventory off, sale modes, invalid quantities and rounded ties', () {
    final quote = f.calculate(
      state: f.state(inventory: {'Ore': 999}),
      output: f.marketItem('1', bids: [f.level(50, 100)]),
    );
    final c = OpportunityCraftComparison(
      quote,
      OpportunitySaleMode.currentBuyers,
    );
    expect(c.ownedSales, 0);
    expect(c.purchases, 10);
    expect(c.sale, closeTo(42.25, 1e-8));
    final custom = OpportunityCraftComparison(
      f.calculate(customSalePrice: 200),
      OpportunitySaleMode.currentBuyers,
    );
    expect(custom.sale, closeTo(169, 1e-8));
    final invalid = OpportunityCraftComparison(f.calculate(crafts: 0), listing);
    expect(invalid.allSales, isNull);
    for (final value in [double.nan, double.infinity, null]) {
      expect(
        OpportunityCraftComparison.decision(value),
        OpportunityCraftDecision.unknown,
      );
    }
    for (final value in [-.49, 0.0, .49]) {
      expect(
        OpportunityCraftComparison.decision(value),
        OpportunityCraftDecision.equal,
      );
    }
  });
  test('divides full run by expected items, not crafts or a second yield', () {
    for (final crafts in [1, 10, 100]) {
      final quote = f.calculate(
        crafts: crafts,
        product: f.recipe('Product', minimum: 2, maximum: 3),
      );
      final card = OpportunityPerItemQuote(quote, listing);
      expect(quote.expectedOutput, crafts * 2.5);
      expect(card.cost, 4);
      expect(card.saleAfterTax, closeTo(84.5, 1e-8));
      expect(card.profit, closeTo(80.5, 1e-8));
    }
  });
  test('batch route and extra expenses are counted exactly once', () {
    final quote = f.calculate(
      crafts: 3,
      product: f.recipe(
        'Product',
        variants: [
          f.variant('ten', [f.ingredient('Ore', 10)], output: 10, batch: 10),
        ],
      ),
      selectedVariantId: 'ten',
      extraCostPerRun: 30,
      extraCostPerCraft: 10,
    );
    final card = OpportunityPerItemQuote(quote, listing);
    expect(quote.expectedOutput, 30);
    expect(card.cost, 12);
    expect(card.profit, closeTo(72.5, 1e-8));
  });
  test('inventory cost includes forgone sales and reconciles with margin', () {
    final quote = f.calculate(
      crafts: 5,
      useInventory: true,
      state: f.state(inventory: {'Ore': 2}),
      extraCostPerRun: 7,
      extraCostPerCraft: 2,
    );
    final card = OpportunityPerItemQuote(quote, listing);
    expect(card.cost, closeTo((30 + 16.9 + 17) / 5, 1e-8));
    expect(card.saleAfterTax! - card.cost!, closeTo(card.profit!, 1e-8));
    final unknown = OpportunityPerItemQuote(
      f.calculate(
        useInventory: true,
        state: f.state(inventory: {'Ore': 1}),
        omitInput: true,
      ),
      listing,
    );
    expect(unknown.cost, isNull);
    expect(unknown.profit, isNull);
  });
  test(
    'sale modes, custom prices, shortages, losses and unknown stay honest',
    () {
      final quote = f.calculate(
        crafts: 2,
        output: f.marketItem(
          '1',
          price: 100,
          bids: [f.level(80, 1), f.level(70, 5)],
        ),
      );
      expect(
        OpportunityPerItemQuote(
          quote,
          OpportunitySaleMode.currentBuyers,
        ).saleAfterTax,
        closeTo(126.75 / 2, 1e-8),
      );
      final custom = OpportunityPerItemQuote(
        f.calculate(customSalePrice: 5),
        OpportunitySaleMode.currentBuyers,
      );
      expect(custom.saleAfterTax, closeTo(4.225, 1e-8));
      expect(custom.profit, isNegative);
      final shortage = f.calculate(input: f.marketItem('2', unknownBook: true));
      expect(shortage.hasEstimatedInputs, isTrue);
      expect(OpportunityPerItemQuote(shortage, listing).cost, 10);
      for (final quote in [
        f.calculate(omitOutput: true),
        f.calculate(omitInput: true),
        f.calculate(crafts: 0),
      ]) {
        expect(OpportunityPerItemQuote(quote, listing).profit, isNull);
      }
    },
  );
  const age = Duration(minutes: 5);
  OpportunityCardStock read(OpportunityMarketItem? item) =>
      OpportunityCardStock(item, f.now, age);
  test('four stock states use both independently checked quantities', () {
    expect(read(null).tone, OpportunityStockTone.unknown);
    expect(
      read(f.marketItem('1', stock: 10)).tone,
      OpportunityStockTone.available,
    );
    expect(
      read(f.marketItem('1', stock: 10, bids: [f.level(10, 4)])).tone,
      OpportunityStockTone.mixed,
    );
    for (final bids in [
      <OpportunityMarketLevel>[],
      [f.level(10, 4)],
    ]) {
      expect(
        read(f.marketItem('1', stock: 0, bids: bids)).tone,
        OpportunityStockTone.outOfStock,
      );
    }
    final unchecked = read(f.marketItem('1', stock: 10, unknownBook: true));
    expect(unchecked.tone, OpportunityStockTone.available);
    expect(unchecked.preorders, isNull);
    expect(read(f.marketItem('1')).preorders, 0);
  });
  test('stale books do not imply mixed or zero preorders', () {
    final stale = read(
      f.marketItem(
        '1',
        stock: 10,
        bids: [f.level(10, 4)],
        bookTime: f.now.subtract(const Duration(days: 1)),
      ),
    );
    expect(stale.stock, 10);
    expect(stale.preorders, isNull);
    expect(stale.tone, OpportunityStockTone.available);
    final allStale = read(
      f.marketItem(
        '1',
        stock: 0,
        quoteTime: f.now.subtract(const Duration(days: 1)),
        bookTime: f.now.subtract(const Duration(days: 1)),
      ),
    );
    expect(allStale.tone, OpportunityStockTone.unknown);
    expect(allStale.stock, isNull);
  });
  test('all-level aggregate never becomes requested-level stock', () {
    final item = OpportunityMarketItem(
      itemId: '1',
      basePrice: 100,
      aggregateStock: 500,
      quoteFetchedAt: f.now,
    );
    expect(read(item).tone, OpportunityStockTone.unknown);
  });
}
