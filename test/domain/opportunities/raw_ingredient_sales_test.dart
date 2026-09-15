import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/raw_ingredient_sales.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 15);

void main() {
  RawIngredientSales sales(
    List<OpportunityIngredientQuote> inputs, {
    MarketTax? tax,
  }) => calculateRawIngredientSales(
    ingredients: inputs,
    tax: tax ?? MarketTax(valuePack: true),
    now: _now,
    maxAge: const Duration(minutes: 30),
    isMarketable: (id) => id != 'npc',
  );

  test('exact selected quantities and current listing prices, taxed once', () {
    final value = sales([
      _input(quantity: 2, price: 14700),
      _input(quantity: 3, price: 24800),
    ]);
    expect(value.afterTax, closeTo((29400 + 74400) * .845, 1e-8));
    expect(value.excludedNames, isEmpty);
    expect(value.unpricedNames, isEmpty);
  });

  test(
    'respects Value Pack, ring and family fame without using purchase costs',
    () {
      final input = _input(quantity: 2, price: 10000);
      expect(sales([input], tax: MarketTax(valuePack: false)).afterTax, 13000);
      expect(
        sales(
          [input],
          tax: MarketTax(
            valuePack: true,
            merchantRing: true,
            familyFameBonus: .015,
          ),
        ).afterTax,
        closeTo(20000 * .65 * 1.365, 1e-8),
      );
      expect(
        input.buyCost,
        1,
        reason: 'Listing value is independent of supplier cost.',
      );
    },
  );

  test('batch scaling and substitute replacement use only supplied inputs', () {
    expect(
      sales([_input(quantity: 6, price: 100)]).afterTax,
      closeTo(sales([_input(quantity: 2, price: 100)]).afterTax! * 3, 1e-8),
    );
    expect(
      sales([_input(quantity: 1, price: 200)]).afterTax,
      closeTo(169, 1e-8),
    );
  });

  test(
    'known nonmarket inputs are explicitly excluded, never valued at NPC cost',
    () {
      final value = sales([
        _input(id: 'npc', price: 999999),
        _input(price: 100),
      ]);
      expect(value.afterTax, closeTo(84.5, 1e-8));
      expect(value.excludedNames, ['Input npc']);
      expect(sales([_input(id: 'npc')]).afterTax, 0);
    },
  );

  for (final scenario in [
    'stale',
    'future',
    'missing',
    'unlisted',
    'zero',
    'unknown id',
    'wrong id',
    'wrong level',
  ]) {
    test('$scenario never yields a partial or zero-priced total', () {
      final value = sales([_input(price: 200), _input(scenario: scenario)]);
      expect(value.afterTax, isNull);
      expect(value.unpricedNames, hasLength(1));
    });
  }

  test('no asks or buyers does not block hypothetical listing proceeds', () {
    expect(sales([_input(price: 100)]).afterTax, closeTo(84.5, 1e-8));
  });

  test('empty formula is unknown', () => expect(sales([]).afterTax, isNull));
}

OpportunityIngredientQuote _input({
  String id = '1',
  int quantity = 1,
  int price = 100,
  String? scenario,
}) => OpportunityIngredientQuote(
  name: 'Input $id',
  itemId: scenario == 'unknown id' ? null : id,
  originalNames: const ['Original ingredient'],
  quantityPerCraft: quantity.toDouble(),
  quantity: quantity,
  npcUnitPrice: 1,
  market: scenario == 'missing'
      ? null
      : OpportunityMarketItem(
          itemId: scenario == 'wrong id' ? 'wrong' : id,
          subId: scenario == 'wrong level' ? 1 : 0,
          basePrice: scenario == 'zero' ? 0 : price,
          stock: 0,
          unlisted: scenario == 'unlisted',
          quoteFetchedAt: scenario == 'stale'
              ? _now.subtract(const Duration(hours: 1))
              : scenario == 'future'
              ? _now.add(const Duration(hours: 1))
              : _now,
          asks: const [],
          bids: const [],
          bookFetchedAt: _now,
        ),
  buyCost: 1,
  preliminaryCost: 1,
  filledQuantity: quantity,
  marketQuantity: 0,
  npcQuantity: quantity,
  depthKnown: true,
  availableQuantity: null,
  issues: const [],
);
