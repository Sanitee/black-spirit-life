import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as planning;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CatalogRepository catalog;
  late planning.PlannerRules rules;
  final now = DateTime.utc(2026, 9, 11, 16);
  setUpAll(() async {
    catalog = CatalogRepository(
      const BundledCatalogParser().parse(
        await File('assets/data/app-data.json').readAsString(),
      ),
    );
    rules = const PlannerAssembly().plannerRules(
      catalog.snapshot.supportingData,
    );
  });

  OpportunityIngredientQuote price({
    String name = 'Mineral Water',
    String? id,
    double? override,
    OpportunityMarketItem? market,
    int crafts = 1,
  }) {
    final product = _recipe('Test product', input: name);
    return OpportunityCalculator(catalogNpcPrices: catalog.npcPurchasePrices)
        .evaluate(
          recipe: product,
          recipes: {
            product.name: product,
            name: _recipe(name, id: id, npcPrice: override ?? 0),
          },
          state: _state(),
          rules: rules,
          marketTax: MarketTax(),
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: market == null ? const {} : {market.itemId: market},
          ),
          now: now,
          crafts: crafts,
        )
        .ingredients
        .single;
  }

  test(
    'all existing NPC prices survive mode-local zero-price placeholders',
    () {
      expect(catalog.npcPurchasePrices, hasLength(12));
      final known = <String, double>{...catalog.npcPurchasePrices};
      for (final entry in rules.vendorInfo.entries) {
        if (entry.value.price > 0) {
          known[entry.key.toLowerCase()] = entry.value.price;
        }
      }
      expect(known, hasLength(34));
      for (final entry in known.entries) {
        final input = price(name: entry.key, crafts: 3);
        expect(input.npcUnitPrice, entry.value, reason: entry.key);
        expect(input.buyCost, entry.value * 3, reason: entry.key);
        expect(input.npcQuantity, 3, reason: entry.key);
        expect(input.marketQuantity, 0, reason: entry.key);
        expect(input.availableQuantity, isNull, reason: entry.key);
        expect(input.issues, isEmpty, reason: entry.key);
      }
      expect(
        () => catalog.npcPurchasePrices['mineral water'] = 1,
        throwsUnsupportedError,
      );
    },
  );

  test('positive custom NPC price overrides the cross-mode catalog price', () {
    final input = price(override: 12, crafts: 7);
    expect(input.npcUnitPrice, 12);
    expect(input.buyCost, 84);
    expect(price(name: 'Not a known NPC item').buyCost, isNull);
  });

  for (final conflict in ['price', 'identity']) {
    test('conflicting cross-mode NPC $conflict is not silently guessed', () {
      ModeCatalog mode(CraftMode kind, double price, String id) => ModeCatalog(
        mode: kind,
        items: {'Water': _recipe('Water', id: id, npcPrice: price)},
        iconDataUris: const {},
        defaults: const {},
        metadata: const {},
        searchAliases: const {},
      );
      final mixed = CatalogRepository(
        CatalogSnapshot(
          sourceSha256: 'synthetic',
          sourceByteCount: 0,
          alchemy: mode(CraftMode.alchemy, 30, '9059'),
          cooking: mode(
            CraftMode.cooking,
            conflict == 'price' ? 40 : 30,
            conflict == 'identity' ? '123456' : '9059',
          ),
          processing: mode(CraftMode.processing, 30, '9059'),
          supportingData: const {},
          collisions: const [],
        ),
      );
      expect(mixed.npcPurchasePrices, isEmpty);
    });
  }

  test(
    'NPC and cheapest valid market offer remain distinct in a mixed fill',
    () {
      final input = price(
        name: 'Ore',
        id: '123456',
        override: 100,
        crafts: 5,
        market: OpportunityMarketItem(
          itemId: '123456',
          basePrice: 70,
          quoteFetchedAt: now,
          asks: const [
            OpportunityMarketLevel(price: 150, quantity: 10),
            OpportunityMarketLevel(price: 80, quantity: 2),
          ],
          bids: const [],
          bookFetchedAt: now,
        ),
      );
      expect(input.npcUnitPrice, 100);
      expect(input.marketUnitPrice, 80);
      expect(input.marketUnitPriceEstimated, isFalse);
      expect(input.marketQuantity, 2);
      expect(input.npcQuantity, 3);
      expect(input.buyCost, 460);
    },
  );

  test('all-NPC purchase retains a dearer checked market alternative', () {
    final input = price(
      name: 'Ore',
      id: '123456',
      override: 100,
      crafts: 5,
      market: OpportunityMarketItem(
        itemId: '123456',
        asks: const [OpportunityMarketLevel(price: 150, quantity: 10)],
        bids: const [],
        bookFetchedAt: now,
      ),
    );
    expect(input.buyCost, 500);
    expect(input.marketQuantity, 0);
    expect(input.marketUnitPrice, 150);
    expect(input.marketUnitPriceEstimated, isFalse);
  });

  test('fresh summary is marked estimated while NPC cost stays verified', () {
    final input = price(
      name: 'Ore',
      id: '123456',
      override: 100,
      market: OpportunityMarketItem(
        itemId: '123456',
        basePrice: 80,
        quoteFetchedAt: now,
      ),
    );
    expect(input.buyCost, 100);
    expect(input.marketUnitPrice, 80);
    expect(input.marketUnitPriceEstimated, isTrue);
    expect(input.estimatedMarketQuantity, 0);
  });

  for (final invalid in ['stale', 'future', 'unlisted']) {
    test('$invalid market data never supplies a supplier price', () {
      final at = invalid == 'future'
          ? now.add(const Duration(seconds: 1))
          : now.subtract(const Duration(hours: 1));
      final input = price(
        name: 'Ore',
        id: '123456',
        override: 100,
        market: OpportunityMarketItem(
          itemId: '123456',
          basePrice: 80,
          quoteFetchedAt: invalid == 'unlisted' ? now : at,
          asks: const [OpportunityMarketLevel(price: 70, quantity: 10)],
          bids: const [],
          bookFetchedAt: invalid == 'unlisted' ? now : at,
          unlisted: invalid == 'unlisted',
        ),
      );
      expect(input.marketUnitPrice, isNull);
      expect(input.marketUnitPriceEstimated, isFalse);
      expect(input.buyCost, 100);
    });
  }

  test(
    'nested Processing inspection and root isolate both retain NPC costs',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final before = fixture.harness.bundle.controller.documentSnapshot;
      for (final (name, ingredient, npcPrice) in [
        ('Wheat Dough', 'Mineral Water', 30),
        ('Butter', 'Salt', 20),
        ('Cream', 'Sugar', 20),
        ('Corruption Draught', 'Spellbound Catalyst', 1000000),
      ]) {
        final inspection = fixture.controller.inspectRecipe(
          recipe: fixture.controller.catalog.recipe(
            CraftMode.processing,
            name,
          )!,
        );
        final input = inspection.quote.ingredients.firstWhere(
          (row) => row.name == ingredient,
        );
        expect(input.npcUnitPrice, npcPrice, reason: name);
        expect(input.buyCost, npcPrice * input.quantity, reason: name);
        expect(input.issues, isEmpty, reason: name);
      }
      fixture.controller.change(
        (p) => p.mode = CraftMode.processing,
        assemble: true,
      );
      await fixture.controller.calculationSettled;
      final dough = fixture.controller.quotes.firstWhere(
        (q) => q.recipeName == 'Wheat Dough',
      );
      expect(
        dough.ingredients.firstWhere((i) => i.name == 'Mineral Water').buyCost,
        30,
      );
      expect(fixture.harness.bundle.controller.documentSnapshot, same(before));
      expect(fixture.requests, 0);
    },
  );

  for (final excluded in ['hidden', 'deleted']) {
    test(
      '$excluded NPC source is not restored by the cross-mode fallback',
      () async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        fixture.harness.bundle.controller.modes[CraftMode.processing]!
            .updateState(
              (state) => excluded == 'hidden'
                  ? state.copyWith(
                      hiddenItems: {...state.hiddenItems, 'Mineral Water'},
                    )
                  : state.copyWith(
                      recipeEdits: {
                        ...state.recipeEdits,
                        'Mineral Water': null,
                      },
                    ),
            );
        final inspection = fixture.controller.inspectRecipe(
          recipe: fixture.controller.catalog.recipe(
            CraftMode.processing,
            'Wheat Dough',
          )!,
        );
        final input = inspection.quote.ingredients.firstWhere(
          (i) => i.name == 'Mineral Water',
        );
        expect(input.npcUnitPrice, isNull);
        expect(input.buyCost, isNull);
        expect(fixture.requests, 0);
      },
    );
  }

  test(
    'mode-local custom NPC metadata takes precedence in nested inspection',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      fixture.harness.bundle.controller.modes[CraftMode.processing]!
          .updateState(
            (state) => state.copyWith(
              ingredientMeta: {
                ...state.ingredientMeta,
                'Mineral Water': IngredientMetadata(npcPrice: 12),
              },
            ),
          );
      final inspection = fixture.controller.inspectRecipe(
        recipe: fixture.controller.catalog.recipe(
          CraftMode.processing,
          'Wheat Dough',
        )!,
      );
      final input = inspection.quote.ingredients.firstWhere(
        (i) => i.name == 'Mineral Water',
      );
      expect(input.npcUnitPrice, 12);
      expect(input.buyCost, 12);
      expect(fixture.requests, 0);
    },
  );
}

Recipe _recipe(String name, {String? input, String? id, double npcPrice = 0}) =>
    Recipe(
      name: name,
      type: input == null ? 'gathered' : 'processing',
      baseOutput: 1,
      group: null,
      method: input == null ? null : 'Simple Alchemy',
      ingredients: [
        if (input != null)
          Ingredient(
            name: input,
            quantity: 1,
            options: const [],
            substituteGroup: null,
            substituteRatios: const {},
          ),
      ],
      marketId: id,
      sourceNote: null,
      vendor: null,
      location: null,
      npcPrice: npcPrice,
      qualityBase: null,
      qualityGrade: null,
      outputMinimum: input == null ? null : 1,
      outputMaximum: input == null ? null : 1,
    );

ModeState _state() => ModeState(
  target: 'Test product',
  bonusTarget: 'Test product',
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
);

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  late final OpportunitiesController controller;
  int requests = 0;
  static Future<_Fixture> create() async {
    final fixture = _Fixture(await ApplicationTestHarness.create());
    fixture.controller = OpportunitiesController(
      appController: fixture.harness.bundle.controller,
      catalog: CatalogRepository(fixture.harness.bundle.catalog),
      directory: fixture.harness.temporaryDirectory,
      serviceFactory: (_) {
        fixture.requests++;
        throw StateError('NPC checks must not issue market requests');
      },
    );
    await fixture.controller.ready;
    await fixture.controller.calculationSettled;
    return fixture;
  }

  Future<void> dispose() async {
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}
