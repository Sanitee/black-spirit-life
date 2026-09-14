import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'opportunity_calculator_test.dart' as fixture;

void main() {
  test(
    'scoped summary supply does not claim verified costs or need output prices',
    () {
      final quote = _quote(crafts: 5);
      expect(quote.ingredientsAvailable, isTrue);
      expect(quote.ingredients.single.stockCoversRequest, isTrue);
      expect(quote.ingredients.single.coversRequest, isFalse);
      expect(quote.inputCost, isNull);
      expect(quote.estimatedInputCost, 50);
      expect(quote.hasUncheckedInputDepth, isTrue);
      expect(quote.marketReady, isFalse);
      expect(quote.listingProfit, isNull);
      expect(quote.outputMarket, isNull);
    },
  );

  for (final stock in [0, 4, 5, 6]) {
    test('selected five crafts require five actual units: stock$stock', () {
      expect(
        _quote(crafts: 5, input: _stock(stock: stock)).ingredientsAvailable,
        stock >= 5,
      );
    });
  }

  for (final scenario in [
    'missing',
    'stale',
    'future',
    'unlisted',
    'other-tier',
    'aggregate',
  ]) {
    test('$scenario stock cannot qualify', () {
      final item = switch (scenario) {
        'missing' => null,
        'stale' => _stock(at: fixture.now.subtract(const Duration(minutes: 6))),
        'future' => _stock(at: fixture.now.add(const Duration(seconds: 1))),
        'unlisted' => _stock(unlisted: true),
        'other-tier' => _stock(subId: 1),
        _ => _stock(aggregate: true),
      };
      expect(
        _quote(
          input: item,
          omitInput: scenario == 'missing',
        ).ingredientsAvailable,
        isFalse,
      );
    });
  }

  test(
    'latest fresh same-tier observation wins independently of price depth',
    () {
      final older = fixture.now.subtract(const Duration(seconds: 1));
      OpportunityMarketItem observed({
        required int stock,
        required List<OpportunityMarketLevel> asks,
        required bool newerBook,
      }) => OpportunityMarketItem(
        itemId: '2',
        basePrice: 10,
        stock: stock,
        quoteFetchedAt: newerBook ? older : fixture.now,
        asks: asks,
        bids: const [],
        bookFetchedAt: newerBook ? fixture.now : older,
      );
      expect(
        _quote(
          input: observed(stock: 100, asks: const [], newerBook: true),
        ).ingredientsAvailable,
        isFalse,
      );
      expect(
        _quote(
          input: observed(
            stock: 0,
            asks: [fixture.level(11, 5)],
            newerBook: true,
          ),
          crafts: 5,
        ).ingredientsAvailable,
        isTrue,
      );
      expect(
        _quote(
          input: observed(stock: 5, asks: const [], newerBook: false),
          crafts: 5,
        ).ingredientsAvailable,
        isTrue,
      );
      final bookOnly = OpportunityMarketItem(
        itemId: '2',
        asks: [fixture.level(11, 5)],
        bids: const [],
        bookFetchedAt: fixture.now,
      );
      expect(_quote(input: bookOnly, crafts: 5).ingredientsAvailable, isTrue);
    },
  );

  test(
    'audited NPC supply covers absent market and mixed purchase remainder',
    () {
      final npc = _quote(omitInput: true, npc: 20, crafts: 5);
      expect(npc.ingredientsAvailable, isTrue);
      expect(npc.inputCost, 100);
      final mixed = _quote(
        npc: 20,
        crafts: 5,
        input: OpportunityMarketItem(
          itemId: '2',
          asks: [fixture.level(10, 2)],
          bids: const [],
          bookFetchedAt: fixture.now,
        ),
      );
      expect(mixed.ingredientsAvailable, isTrue);
      expect(mixed.inputCost, 80);
      expect(mixed.ingredients.single.marketQuantity, 2);
      expect(mixed.ingredients.single.npcQuantity, 3);
      expect(_quote(omitInput: true, npc: 0).ingredientsAvailable, isFalse);
    },
  );

  test('shared market aliases aggregate quantities before testing supply', () {
    final recipe = fixture.recipe(
      'Product',
      ingredients: [
        fixture.ingredient('Ore', 2),
        fixture.ingredient('Alias Ore', 3),
      ],
    );
    final extras = {'Alias Ore': fixture.leaf('Alias Ore', id: '0002')};
    final short = _quote(
      product: recipe,
      extras: extras,
      input: _stock(stock: 4),
    );
    expect(short.ingredients, hasLength(1));
    expect(short.ingredients.single.quantity, 5);
    expect(short.ingredientsAvailable, isFalse);
    expect(
      _quote(
        product: recipe,
        extras: extras,
        input: _stock(stock: 5),
      ).ingredientsAvailable,
      isTrue,
    );
  });

  test('owned inventory never becomes supplier stock', () {
    expect(
      _quote(
        input: _stock(stock: 0),
        state: fixture.state(inventory: {'Ore': 1000000}),
      ).ingredientsAvailable,
      isFalse,
    );
  });

  test(
    'availability preference changes substitutes only when explicitly enabled',
    () {
      final recipe = fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', 1, options: ['Ore', 'Fine Ore']),
        ],
      );
      final off = _quote(product: recipe, input: _stock(stock: 0));
      final on = _quote(product: recipe, input: _stock(stock: 0), prefer: true);
      expect(off.ingredients.single.name, 'Ore');
      expect(off.ingredientsAvailable, isFalse);
      expect(on.ingredients.single.name, 'Fine Ore');
      expect(on.ingredientsAvailable, isTrue);
      expect(on.inputCost, isNull);
      expect(on.hasEstimatedInputs, isTrue);
      expect(on.marketReady, isFalse);
      final locked = _quote(
        product: recipe,
        input: _stock(stock: 0),
        prefer: true,
        choices: {'Ore': 'Ore'},
      );
      expect(locked.ingredients.single.name, 'Ore');
      expect(locked.ingredientsAvailable, isFalse);
    },
  );

  test(
    'complete formulas prefer known supply without overriding a manual variant',
    () {
      final recipe = fixture.recipe(
        'Product',
        variants: [
          fixture.variant('cheap', [fixture.ingredient('Ore', 1)]),
          fixture.variant('stocked', [fixture.ingredient('Fine Ore', 1)]),
        ],
      );
      expect(
        _quote(product: recipe, input: _stock(stock: 0)).selectedVariantId,
        'cheap',
      );
      final on = _quote(product: recipe, input: _stock(stock: 0), prefer: true);
      expect(on.selectedVariantId, 'stocked');
      expect(on.ingredientsAvailable, isTrue);
      final locked = _quote(
        product: recipe,
        input: _stock(stock: 0),
        prefer: true,
        variant: 'cheap',
      );
      expect(locked.selectedVariantId, 'cheap');
      expect(locked.ingredientsAvailable, isFalse);
    },
  );

  test(
    'whole-craft splits use each selected alternative actual required quantity',
    () {
      final recipe = fixture.recipe(
        'Product',
        ingredients: [
          fixture.ingredient('Ore', 2, options: ['Ore', 'Fine Ore']),
        ],
      );
      final split = {
        'Ore': {'Ore': 2, 'Fine Ore': 3},
      };
      expect(
        _quote(
          product: recipe,
          crafts: 5,
          input: _stock(stock: 3),
          allocations: split,
        ).ingredientsAvailable,
        isFalse,
      );
      final covered = _quote(
        product: recipe,
        crafts: 5,
        input: _stock(stock: 4),
        allocations: split,
      );
      expect(covered.ingredientsAvailable, isTrue);
      expect(covered.ingredients.map((i) => i.quantity), [4, 6]);
    },
  );

  test('invalid and empty formulas cannot become available', () {
    expect(_quote(crafts: 0).ingredientsAvailable, isFalse);
    expect(
      _quote(
        product: fixture.recipe('Product', ingredients: const []),
      ).ingredientsAvailable,
      isFalse,
    );
    expect(
      _quote(
        product: fixture.recipe(
          'Product',
          ingredients: [fixture.ingredient('Ore', double.nan)],
        ),
      ).ingredientsAvailable,
      isFalse,
    );
  });

  test('malformed latest book cannot revive older positive stock', () {
    for (final asks in [
      [fixture.level(0, 10)],
      [fixture.level(10, 20), fixture.level(10, -1)],
    ]) {
      final invalid = OpportunityMarketItem(
        itemId: '2',
        basePrice: 10,
        stock: 100,
        quoteFetchedAt: fixture.now.subtract(const Duration(seconds: 1)),
        asks: asks,
        bids: const [],
        bookFetchedAt: fixture.now,
      );
      expect(_quote(input: invalid).ingredientsAvailable, isFalse);
    }
  });
}

OpportunityMarketItem _stock({
  int stock = 10,
  DateTime? at,
  bool unlisted = false,
  bool aggregate = false,
  int subId = 0,
}) => OpportunityMarketItem(
  itemId: '2',
  subId: subId,
  basePrice: 10,
  stock: aggregate ? null : stock,
  aggregateStock: aggregate ? stock : null,
  quoteFetchedAt: at ?? fixture.now,
  unlisted: unlisted,
);

OpportunityQuote _quote({
  Recipe? product,
  OpportunityMarketItem? input,
  bool omitInput = false,
  int crafts = 1,
  double npc = 0,
  bool prefer = false,
  Map<String, Recipe> extras = const {},
  ModeState? state,
  String? variant,
  Map<String, String> choices = const {},
  Map<String, Map<String, int>> allocations = const {},
}) {
  final selected = product ?? fixture.recipe('Product');
  return const OpportunityCalculator().evaluate(
    recipe: selected,
    recipes: {
      selected.name: selected,
      'Ore': fixture.leaf('Ore', id: '2', npc: npc),
      'Fine Ore': fixture.leaf('Fine Ore', id: '3'),
      ...extras,
    },
    state: state ?? fixture.state(),
    rules: PlannerRules(),
    marketTax: MarketTax(),
    market: OpportunityMarketSnapshot(
      region: 'eu',
      items: {
        if (!omitInput) '2': input ?? _stock(),
        '3': OpportunityMarketItem(
          itemId: '3',
          basePrice: 20,
          stock: 100,
          quoteFetchedAt: fixture.now,
        ),
      },
    ),
    now: fixture.now,
    crafts: crafts,
    preferAvailableInputs: prefer,
    selectedVariantId: variant,
    ingredientChoices: choices,
    ingredientAllocations: allocations,
  );
}
