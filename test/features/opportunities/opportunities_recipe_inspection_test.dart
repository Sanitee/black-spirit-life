import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_calculations.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/opportunities/opportunity_calculator_test.dart'
    as market_fixture;
import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'custom price uses source mastery and tax without market or saved edits',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.checkMarket();
      final controller = fixture.controller;
      final recipe = fixture.recipe(CraftMode.cooking, 'Oatmeal');
      final standard = controller
          .inspectRecipe(
            recipe: recipe,
            crafts: 4,
            extraCostPerRun: 100,
            extraCostPerCraft: 20,
          )
          .quote;
      final document = fixture.app.documentSnapshot;
      final preferences = jsonEncode(controller.preferences.toJson());
      final rootQuotes = controller.quotes;
      final requests = fixture.transportCalls;
      var notifications = 0;
      controller.addListener(() => notifications++);
      final custom = controller.inspectRecipe(
        recipe: recipe,
        crafts: 4,
        extraCostPerRun: 100,
        extraCostPerCraft: 20,
        customSalePrice: 25000,
      );
      expect(custom.mastery, 2000);
      expect(custom.quote.expectedOutput, standard.expectedOutput);
      expect(custom.quote.customSalePrice, 25000);
      expect(
        custom.quote.listingRevenue,
        closeTo(
          standard.expectedOutput! *
              25000 *
              marketNetRate(fixture.app.marketTax.value),
          .000001,
        ),
      );
      expect(custom.quote.inputCost, standard.inputCost);
      expect(custom.quote.extraCost, 180);
      expect(custom.quote.totalCost, standard.totalCost);
      expect(custom.quote.buyerRevenue, standard.buyerRevenue);
      expect(custom.quote.buyerFilledQuantity, standard.buyerFilledQuantity);
      expect(custom.quote.outputMarket, same(standard.outputMarket));
      expect(
        custom.quote.profitFor(OpportunitySaleMode.currentBuyers),
        custom.quote.listingProfit,
      );
      final restored = controller
          .inspectRecipe(
            recipe: recipe,
            crafts: 4,
            extraCostPerRun: 100,
            extraCostPerCraft: 20,
          )
          .quote;
      expect(restored.hasCustomSalePrice, isFalse);
      expect(restored.listingProfit, standard.listingProfit);
      final invalid = controller
          .inspectRecipe(recipe: recipe, customSalePrice: 0)
          .quote;
      expect(invalid.customSalePrice, 0);
      expect(invalid.issues, contains(OpportunityIssue.invalidSalePrice));
      expect(invalid.listingProfit, isNull);
      expect(fixture.app.documentSnapshot, same(document));
      expect(jsonEncode(controller.preferences.toJson()), preferences);
      expect(controller.quotes, same(rootQuotes));
      expect(fixture.transportCalls, requests);
      expect(notifications, 0);
    },
  );

  test(
    'rare custom-price inspection retains expenses without guessing yield',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.checkMarket();
      final recipe = fixture.recipe(CraftMode.cooking, 'Oatmeal');
      final standard = fixture.controller
          .inspectRecipe(
            recipe: recipe,
            crafts: 3,
            extraCostPerRun: 50,
            extraCostPerCraft: 7,
          )
          .quote;
      final rare = fixture.controller
          .inspectRecipe(
            recipe: recipe,
            itemName: 'Refined Oatmeal',
            crafts: 3,
            extraCostPerRun: 50,
            extraCostPerCraft: 7,
            customSalePrice: 1000000,
          )
          .quote;
      expect(rare.hasCustomSalePrice, isTrue);
      expect(rare.customSalePrice, 1000000);
      expect(rare.expectedOutput, isNull);
      expect(rare.outputPerCraft, isNull);
      expect(rare.listingRevenue, isNull);
      expect(rare.listingProfit, isNull);
      expect(rare.profitFor(OpportunitySaleMode.currentBuyers), isNull);
      expect(rare.buyerRevenue, isNull);
      expect(rare.inputCost, standard.inputCost);
      expect(rare.extraCost, 71);
      expect(rare.totalCost, standard.totalCost);
      expect(rare.marketReady, isFalse);
    },
  );

  test(
    'explicit recipe search includes losses, zero and unknown without changing filters',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      await controller.calculationSettled;
      controller.quotes = [
        _searchQuote('Match Positive', revenue: 200),
        _searchQuote('Match Zero', revenue: 100),
        _searchQuote('Match Negative', revenue: 50),
        _searchQuote('Match Unknown'),
        _searchQuote('Match Unavailable', revenue: 200, stock: 0),
        _searchQuote('Other Positive', revenue: 200),
      ];
      controller.preferences
        ..profitableOnly = true
        ..readyOnly = false;
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName).toSet(),
        {
          'Match Positive',
          'Match Unknown',
          'Match Unavailable',
          'Other Positive',
        },
      );
      controller.preferences.craftSearch = '  MaTcH  ';
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName).toSet(),
        {
          'Match Positive',
          'Match Zero',
          'Match Negative',
          'Match Unknown',
          'Match Unavailable',
        },
      );
      controller.preferences.readyOnly = true;
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName).toSet(),
        {'Match Positive', 'Match Zero', 'Match Negative', 'Match Unknown'},
      );
      controller.preferences
        ..readyOnly = false
        ..craftSearch = '  ';
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName).toSet(),
        {
          'Match Positive',
          'Match Unknown',
          'Match Unavailable',
          'Other Positive',
        },
      );
      expect(controller.preferences.profitableOnly, isTrue);
      expect(fixture.transportCalls, 0);
    },
  );

  test(
    'real Cup of Earths Sorrows remains findable at a loss in Processing',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      controller.change((preferences) {
        preferences.mode = CraftMode.processing;
        preferences.craftSearch = 'sorro';
        preferences.profitableOnly = false;
        preferences.readyOnly = false;
      }, assemble: true);
      await controller.calculationSettled;
      const name = "Cup of Earth's Sorrows";
      final recipe = controller.recipes[name]!;
      expect(recipe.isCraftable, isTrue);
      expect(recipe.type, 'processing');
      expect(recipe.marketId, '8417');
      expect(recipe.outputMinimum, 1);
      expect(recipe.outputMaximum, 1);
      expect(
        recipe.ingredients.map((input) => (input.name, input.quantity)).toSet(),
        {
          ('Magical Shard', 30.0),
          ('Shard of the Furious Night', 50.0),
          ('Shard of the Tearful Night', 50.0),
          ('Shard of the Drained Night', 100.0),
          ('Black Stone', 100.0),
        },
      );
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName),
        contains(name),
      );
      await fixture.checkMarket();
      final quote = controller.quotes.singleWhere(
        (quote) => quote.recipeName == name,
      );
      expect(quote.listingProfit, lessThan(0));
      controller.preferences.profitableOnly = true;
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName),
        contains(name),
      );
      controller.preferences.craftSearch = '';
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName),
        isNot(contains(name)),
      );
      controller.change((preferences) {
        preferences.mode = CraftMode.cooking;
        preferences.craftSearch = 'sorro';
      }, assemble: true);
      await controller.calculationSettled;
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName),
        isNot(contains(name)),
      );
      controller.change(
        (preferences) => preferences.mode = CraftMode.processing,
        assemble: true,
      );
      await controller.calculationSettled;
      fixture.app.modes[CraftMode.processing]!.updateState(
        (state) => state.copyWith(hiddenItems: {...state.hiddenItems, name}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await controller.calculationSettled;
      expect(controller.recipes, isNot(contains(name)));
      expect(
        controller.visibleQuotes.map((quote) => quote.recipeName),
        isNot(contains(name)),
      );
    },
  );

  test('child calculations use source-mode mastery and shared tax', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.checkMarket();
    final controller = fixture.controller;
    controller.preferences
      ..mode = CraftMode.processing
      ..crafts = 17
      ..extraCostPerRun = 999999
      ..extraCostPerCraft = 888;
    final document = fixture.app.documentSnapshot;
    final preferences = jsonEncode(controller.preferences.toJson());
    final quotes = controller.quotes;
    final rootRecipes = controller.recipes;
    var notifications = 0;
    controller.addListener(() => notifications++);

    for (final (mode, name, mastery) in [
      (CraftMode.cooking, 'Oatmeal', 2000),
      (CraftMode.alchemy, 'Clear Liquid Reagent', 1900),
    ]) {
      final inspection = controller.inspectRecipe(
        recipe: fixture.recipe(mode, name),
      );
      final formula = inspection.recipe;
      final expected =
          formula.baseOutput *
          (mode == CraftMode.cooking
              ? cookingExpectedOutput(
                  mastery.toDouble(),
                  formula.outputMinimum ?? 1,
                  formula.outputMaximum ?? 4,
                )
              : alchemyExpectedOutput(
                  mastery.toDouble(),
                  formula.outputMinimum ?? 1,
                  formula.outputMaximum ?? 4,
                ));
      expect(inspection.sourceMode, mode);
      expect(inspection.mastery, mastery);
      expect(inspection.isRareOutput, isFalse);
      expect(inspection.quote.crafts, 1);
      expect(inspection.quote.expectedOutput, closeTo(expected, .000001));
      expect(inspection.quote.extraCost, 0);
      expect(inspection.quote.inputCost, greaterThan(0));
      if (name == 'Oatmeal') {
        expect(
          inspection.quote.ingredients.any(
            (input) =>
                input.originalNames.contains('Cooking Honey') &&
                input.costForCalculation! > 0,
          ),
          isTrue,
        );
        expect(
          inspection.quote.ingredients.any(
            (input) => input.name.contains('Beehive'),
          ),
          isFalse,
          reason: 'Inspecting a child never recursively crafts its own inputs.',
        );
      }
      expect(
        inspection.quote.listingRevenue,
        closeTo(
          expected * 1000 * marketNetRate(fixture.app.marketTax.value),
          .001,
        ),
      );
      expect(
        inspection.quote.listingProfit,
        closeTo(
          inspection.quote.listingRevenue! - inspection.quote.inputCost!,
          .001,
        ),
      );
    }
    expect(fixture.app.documentSnapshot, same(document));
    expect(jsonEncode(controller.preferences.toJson()), preferences);
    expect(controller.quotes, same(quotes));
    expect(controller.recipes, same(rootRecipes));
    expect(notifications, 0);
  });

  test('cross-mode Honey uses its bounded Processing formula', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.checkMarket();
    final embedded = fixture.recipe(CraftMode.cooking, 'Cooking Honey');
    expect(embedded.type, 'processing');
    fixture.controller.recipes = {
      ...fixture.controller.recipes,
      embedded.name: embedded,
    };
    final inspection = fixture.controller.inspectRecipe(recipe: embedded);
    expect(inspection.sourceMode, CraftMode.processing);
    expect(inspection.mastery, 3000);
    expect(inspection.recipe.outputMinimum, 1);
    expect(inspection.recipe.outputMaximum, 2);
    expect(inspection.recipe.isCraftable, isTrue);
    expect(inspection.quote.expectedOutput, 1.5);
    expect(inspection.quote.ingredients, hasLength(1));
    expect(inspection.quote.ingredients.single.name, contains('Beehive'));
    expect(inspection.quote.ingredients.single.quantity, 3);
    expect(inspection.quote.inputCost, 3030);
  });

  test('each chosen bulk formula stays one complete child craft', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.checkMarket();
    final recipe = fixture.recipe(CraftMode.processing, 'Corruption Draught');
    expect(recipe.variants.length, greaterThan(1));
    final before = fixture.app.documentSnapshot;
    final preferences = jsonEncode(fixture.controller.preferences.toJson());
    for (final variant in recipe.variants) {
      final inspection = fixture.controller.inspectRecipe(
        recipe: recipe,
        selectedVariantId: variant.id,
      );
      expect(inspection.quote.selectedVariantId, variant.id);
      expect(inspection.quote.batchMultiplier, variant.batchMultiplier);
      expect(inspection.quote.crafts, 1);
      expect(
        inspection.quote.expectedOutput,
        processingOutputPerCraft(recipe: recipe.resolveVariant(variant.id)),
      );
      expect(
        inspection.recipe.ingredients.map((row) => (row.name, row.quantity)),
        variant.ingredients.map((row) => (row.name, row.quantity)),
      );
    }
    final defaultInspection = fixture.controller.inspectRecipe(recipe: recipe);
    expect(
      defaultInspection.quote.selectedVariantId,
      recipe.defaultVariant!.id,
    );
    final invalid = fixture.controller.inspectRecipe(
      recipe: recipe,
      selectedVariantId: 'not-a-real-formula',
    );
    expect(invalid.quote.issues, contains(OpportunityIssue.unknownVariant));
    expect(invalid.quote.expectedOutput, isNull);
    expect(invalid.quote.totalCost, isNull);
    expect(invalid.quote.listingProfit, isNull);
    expect(fixture.app.documentSnapshot, same(before));
    expect(jsonEncode(fixture.controller.preferences.toJson()), preferences);
  });

  test(
    'an intentional current-mode formula is not replaced by bundled data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final original = fixture.controller.recipes['Oatmeal']!;
      // Warm the canonical inspection cache before replacing the active formula.
      fixture.controller.inspectRecipe(recipe: original);
      final custom = Recipe(
        name: original.name,
        type: original.type,
        baseOutput: 1,
        group: original.group,
        method: original.method,
        ingredients: [
          Ingredient(
            name: 'Mineral Water',
            quantity: 7,
            options: const [],
            substituteGroup: null,
            substituteRatios: const {},
          ),
        ],
        marketId: original.marketId,
        sourceNote: 'Intentional custom formula',
        vendor: original.vendor,
        location: original.location,
        npcPrice: original.npcPrice,
        qualityBase: original.qualityBase,
        qualityGrade: original.qualityGrade,
        outputMinimum: 2,
        outputMaximum: 2,
      );
      fixture.controller.recipes = {
        ...fixture.controller.recipes,
        custom.name: custom,
      };
      final document = fixture.app.documentSnapshot;
      final inspection = fixture.controller.inspectRecipe(recipe: custom);
      expect(inspection.recipe, same(custom));
      expect(inspection.quote.ingredients, hasLength(1));
      expect(inspection.quote.ingredients.single.name, 'Mineral Water');
      expect(inspection.quote.ingredients.single.quantity, 7);
      expect(inspection.quote.expectedOutput, 2);
      expect(fixture.app.documentSnapshot, same(document));
    },
  );

  test(
    'Refined Oatmeal keeps source costs but never borrows ordinary yield',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.checkMarket();
      final recipe = fixture.recipe(CraftMode.cooking, 'Oatmeal');
      final normal = fixture.controller.inspectRecipe(recipe: recipe);
      final rare = fixture.controller.inspectRecipe(
        recipe: recipe,
        itemName: 'Refined Oatmeal',
      );
      expect(normal.quote.listingProfit, isNotNull);
      expect(rare.itemName, 'Refined Oatmeal');
      expect(rare.recipe.name, 'Oatmeal');
      expect(rare.sourceMode, CraftMode.cooking);
      expect(rare.mastery, 2000);
      expect(rare.isRareOutput, isTrue);
      expect(rare.quote.recipeName, 'Refined Oatmeal');
      expect(rare.quote.inputCost, normal.quote.inputCost);
      expect(rare.quote.totalCost, normal.quote.totalCost);
      expect(
        rare.quote.ingredients.map(
          (row) => (row.name, row.quantity, row.buyCost),
        ),
        normal.quote.ingredients.map(
          (row) => (row.name, row.quantity, row.buyCost),
        ),
      );
      expect(rare.quote.outputMarket, isNotNull);
      expect(
        rare.quote.outputMarket!.itemId,
        '9276',
        reason:
            'The curated recipe ID takes precedence over legacy supporting IDs.',
      );
      expect(
        rare.quote.outputMarket!.itemId,
        isNot(normal.quote.outputMarket!.itemId),
      );
      for (final unknown in [
        rare.quote.outputPerCraft,
        rare.quote.expectedOutput,
        rare.quote.listingRevenue,
        rare.quote.buyerRevenue,
        rare.quote.listingProfit,
        rare.quote.preliminaryListingProfit,
        rare.quote.buyerProfit,
        rare.quote.listingProfitPerCraft,
        rare.quote.buyerCraftCapacity,
      ]) {
        expect(unknown, isNull);
      }
      expect(rare.quote.marketReady, isFalse);
      expect(rare.quote.buyersCoverOutput, isFalse);
      expect(rare.quote.buyerFilledQuantity, 0);
    },
  );

  test(
    'unchecked ingredients and another region never become free inputs',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final recipe = fixture.recipe(CraftMode.cooking, 'Oatmeal');
      final unchecked = fixture.controller.inspectRecipe(recipe: recipe);
      expect(unchecked.quote.expectedOutput, greaterThan(0));
      expect(unchecked.quote.inputCost, isNull);
      expect(unchecked.quote.totalCost, isNull);
      expect(unchecked.quote.listingProfit, isNull);
      expect(unchecked.quote.marketReady, isFalse);
      expect(
        unchecked.quote.ingredients.any((input) => input.buyCost == null),
        isTrue,
      );
      await fixture.checkMarket();
      expect(
        fixture.controller.inspectRecipe(recipe: recipe).quote.listingProfit,
        isNotNull,
      );
      fixture.controller.preferences.region = 'na';
      final otherRegion = fixture.controller.inspectRecipe(recipe: recipe);
      expect(otherRegion.quote.outputMarket, isNull);
      expect(otherRegion.quote.totalCost, isNull);
      expect(otherRegion.quote.listingProfit, isNull);
    },
  );

  test(
    'child reads latest source mastery and shared tax without saving a choice',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.checkMarket();
      final recipe = fixture.recipe(CraftMode.cooking, 'Oatmeal');
      final before = fixture.controller.inspectRecipe(recipe: recipe);
      fixture.app.modes[CraftMode.cooking]!.updateState(
        (state) => state.copyWith(cookingMastery: 0),
      );
      fixture.app.marketTax.value = MarketTax(valuePack: false);
      final afterChanges = fixture.app.documentSnapshot;
      final after = fixture.controller.inspectRecipe(recipe: recipe);
      expect(after.mastery, 0);
      expect(
        after.quote.expectedOutput,
        lessThan(before.quote.expectedOutput!),
      );
      expect(
        after.quote.listingRevenue,
        closeTo(after.quote.expectedOutput! * 1000 * .65, .001),
      );
      expect(after.quote.inputCost, before.quote.inputCost);
      expect(fixture.app.documentSnapshot, same(afterChanges));
    },
  );
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  late final OpportunitiesController controller;
  final now = DateTime.utc(2026, 9, 9, 20);
  int transportCalls = 0;
  PlannerApplicationController get app => harness.bundle.controller;

  static Future<_Fixture> create() async {
    final harness = await ApplicationTestHarness.create();
    final fixture = _Fixture(harness);
    for (final mode in CraftMode.values) {
      fixture.app.modes[mode]!.updateState(
        (ModeState state) => state.copyWith(
          cookingMastery: mode == CraftMode.cooking ? 2000 : 0,
          alchemyMastery: mode == CraftMode.alchemy ? 1900 : 0,
          processingMastery: mode == CraftMode.processing ? 3000 : 0,
          useMassProcessing: true,
          inventory: {
            for (final recipe
                in harness.bundle.catalog.forMode(mode).items.keys)
              recipe: 1000000,
          },
        ),
      );
    }
    fixture.app.marketTax.value = MarketTax(valuePack: true);
    fixture.controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: CatalogRepository(harness.bundle.catalog),
      directory: harness.temporaryDirectory,
      clock: () => fixture.now,
      serviceFactory: (region) => OpportunityMarketService(
        region: region,
        quoteBatchSize: 1,
        transport: _MarketTransport(
          fixture.now,
          onPost: () => fixture.transportCalls++,
        ),
        utcNow: () => fixture.now,
        requestSpacing: Duration.zero,
      ),
    );
    await fixture.controller.ready;
    return fixture;
  }

  Recipe recipe(CraftMode mode, String name) =>
      controller.catalog.recipe(mode, name)!;

  Future<void> checkMarket() async {
    await controller.refreshAll(onlyStale: false);
    // These pure inspection tests start with explicitly checked ask prices;
    // production startup itself no longer requests every item's order book.
    await controller.ensureMarketDepth(controller.market.items.keys);
    await controller.ensureMarketDepth(const []);
    await controller.calculationSettled;
  }

  Future<void> dispose() async {
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

final class _MarketTransport implements OpportunityMarketTransport {
  _MarketTransport(this.now, {this.onPost});
  final DateTime now;
  final void Function()? onPost;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    onPost?.call();
    final id = '${(jsonDecode(body) as Map)['mainKey']}';
    final message = uri.path.endsWith('GetBiddingInfoList')
        ? '990-0-100000|1010-100000-0|'
        : '$id-0-0-1000-100000-500000-100-10000-1000-${now.millisecondsSinceEpoch ~/ 1000}|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': message})),
      ),
    );
  }

  @override
  void close() {}
}

OpportunityQuote _searchQuote(String name, {double? revenue, int stock = 10}) =>
    OpportunityQuote(
      recipeName: name,
      selectedVariantId: null,
      variantLabel: null,
      batchMultiplier: 1,
      crafts: 1,
      outputPerCraft: 1,
      expectedOutput: 1,
      outputMarket: null,
      ingredients: [_searchIngredient(stock)],
      listingRevenue: revenue,
      inputCost: 100,
      preliminaryInputCost: 100,
      buyerRevenue: null,
      buyerFilledQuantity: 0,
      marketReady: revenue != null,
      buyersCoverOutput: false,
      inputCapacityKnown: true,
      inputCraftCapacity: 1,
      buyerCraftCapacity: null,
      estimatedSeconds: null,
      issues: const {},
    );

OpportunityIngredientQuote _searchIngredient(int stock) {
  final now = DateTime.utc(2026, 9, 9, 20);
  return const OpportunityCalculator()
      .evaluate(
        recipe: market_fixture.recipe('Search fixture'),
        recipes: {'Ore': market_fixture.leaf('Ore', id: '2')},
        state: market_fixture.state(),
        rules: PlannerRules(),
        marketTax: MarketTax(),
        market: OpportunityMarketSnapshot(
          region: 'eu',
          items: {
            '2': OpportunityMarketItem(
              itemId: '2',
              basePrice: 100,
              stock: stock,
              quoteFetchedAt: now,
              asks: [market_fixture.level(100, stock)],
              bids: const [],
              bookFetchedAt: now,
            ),
          },
        ),
        now: now,
      )
      .ingredients
      .single;
}
