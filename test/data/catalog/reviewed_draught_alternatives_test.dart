import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/domain/market/recipe_profitability.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as plan;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final review =
      jsonDecode(
            File('docs/reviewed-draught-alternatives.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final changes = (review['changes'] as List).cast<Map<String, dynamic>>();
  late CatalogSnapshot catalog;
  late Map<String, Recipe> recipes;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    recipes = const PlannerAssembly().assembleRecipes(
      catalog: catalog.processing,
      state: ModeState(
        target: '',
        bonusTarget: '',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      ),
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.processing,
      processingRecipes: catalog.processing.items,
    );
  });
  test(
    'Deep Blue Tidal supports both official input sets without changing output',
    () {
      const name = 'Deep Blue Tidal Draught';
      final recipe = recipes[name]!;
      final input = recipe.ingredients.first;
      expect(input.options, ['Tidal Draught', 'Blue Tidal Draught']);
      expect(input.substituteRatios, {
        'Tidal Draught': 1.0,
        'Blue Tidal Draught': 0.5,
      });
      expect(input.substituteGroup, 'Tidal Draught');
      expect(recipe.marketId, '767695');
      expect(recipe.outputMinimum, 1);
      expect(recipe.outputMaximum, 1);
      expect(experienceFor(recipe, CraftMode.processing), isNull);
      for (final entry in {
        'Tidal Draught': 4.0,
        'Blue Tidal Draught': 2.0,
      }.entries) {
        final choices = {'recipe:$name:Tidal Draught': entry.key};
        final selected = const PlannerEngine().previewIngredientSelection(
          recipes: recipes,
          state: plan.PlannerState(
            target: name,
            inventory: {entry.key: 1},
            ignoreIngredientInventory: false,
            substituteChoices: choices,
          ),
          parentName: name,
          ingredient: input,
        );
        expect(selected.name, entry.key);
        expect(selected.need, entry.value);
        expect(selected.have, 1);
        expect(selected.missing, entry.value - 1);
        final result = const PlannerEngine().buildPlan(
          mode: CraftMode.processing,
          recipes: recipes,
          state: plan.PlannerState(
            target: name,
            want: 10,
            substituteChoices: choices,
          ),
        );
        final step = result.steps.singleWhere((s) => s.name == name);
        expect(step.count, 10);
        expect(step.produced, 10);
        expect(
          {for (final i in step.ingredients) i.name: i.need},
          {entry.key: entry.value * 10, 'Essence of Tides': 10.0},
        );
        final quote = const RecipeProfitabilityCalculator().calculate(
          recipe: recipe,
          recipes: recipes,
          state: ModeState(
            target: name,
            bonusTarget: '',
            substituteChoices: choices,
            market: MarketState(
              prices: {
                name: 1000,
                'Tidal Draught': 100,
                'Blue Tidal Draught': 190,
                'Essence of Tides': 25,
              },
            ),
            appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
          ),
          rules: plan.PlannerRules(),
          marketTax: MarketTax(),
        );
        expect(quote.isAvailable, isTrue);
        expect(quote.outputPerCraft, 1);
        expect(quote.ingredientCost, entry.key == 'Tidal Draught' ? 425 : 405);
      }
    },
  );

  for (final row in [
    (
      "Khan's Heart: Destruction",
      "Khan's Concentrated Magic",
      "Khan's Dim Magic",
      3.0,
    ),
    (
      "Khan's Heart: Protection",
      "Khan's Concentrated Magic",
      "Khan's Dim Magic",
      3.0,
    ),
    (
      "Khan's Heart: Life",
      "Khan's Concentrated Magic",
      "Khan's Dim Magic",
      3.0,
    ),
    (
      'Sturdy Whale Tendon Elixir',
      'Whale Tendon Elixir',
      'Whale Tendon Elixir',
      3.0,
    ),
    (
      'Sturdy Whale Tendon Potion',
      'Whale Tendon Potion',
      'Superior Whale Tendon Potion',
      1.0,
    ),
    ('Fiery Celerity Draught', 'Celerity Draught', 'Celerity Draught', 4.0),
  ]) {
    test('${row.$1} consumes the exact alternative, including owned stock', () {
      final recipe = recipes[row.$1]!;
      final input = recipe.ingredients.singleWhere(
        (i) => i.options.contains(row.$3),
      );
      final choices = {'recipe:${row.$1}:${row.$2}': row.$3};
      final state = plan.PlannerState(
        target: row.$1,
        want: 2,
        inventory: {row.$3: 1},
        ignoreIngredientInventory: false,
        substituteChoices: choices,
      );
      final preview = const PlannerEngine().previewIngredientSelection(
        recipes: recipes,
        state: state,
        parentName: row.$1,
        ingredient: input,
      );
      expect(preview.name, row.$3);
      expect(preview.need, row.$4);
      expect(preview.have, 1);
      expect(preview.missing, row.$4 - 1);
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.processing,
        recipes: recipes,
        state: state,
      );
      final step = result.steps.singleWhere((s) => s.name == row.$1);
      expect(step.count, 2);
      expect(step.produced, 2);
      expect(
        step.ingredients.singleWhere((i) => i.name == row.$3).need,
        row.$4 * 2,
      );
      expect(recipe.outputMinimum, 1);
      expect(recipe.outputMaximum, 1);
    });
  }

  test('bound Khan quest material is never priced as a market purchase', () {
    const name = "Khan's Heart: Life";
    final rules = const PlannerAssembly().plannerRules(catalog.supportingData);
    expect(rules.marketIds["Khan's Dim Magic"], '45517');
    expect(reviewedNonMarketableOpportunityIds, contains('45517'));
    for (final owned in [0.0, 2.0, 3.0]) {
      final quote = const OpportunityCalculator().evaluate(
        recipe: recipes[name]!,
        recipes: recipes,
        state: ModeState(
          target: name,
          bonusTarget: '',
          inventory: {"Khan's Dim Magic": owned},
          ignoreIngredientInventory: false,
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
        ),
        rules: rules,
        marketTax: MarketTax(),
        market: OpportunityMarketSnapshot(region: 'eu', items: {}),
        now: DateTime.utc(2026, 11, 4),
        ingredientChoices: {"Khan's Concentrated Magic": "Khan's Dim Magic"},
        useInventory: true,
        nonMarketableIds: reviewedNonMarketableOpportunityIds,
      );
      final material = quote.ingredients.singleWhere(
        (i) => i.name == "Khan's Dim Magic",
      );
      expect(material.quantity, 3);
      expect(material.ownedQuantity, owned);
      expect(material.purchaseQuantity, 3 - owned);
      expect(
        quote.inputCost,
        isNull,
      ); // No fabricated prices for missing inputs.
      expect(quote.marketReady, isFalse);
    }
  });

  for (final row in [
    ('Immortal: Perfume of Envy', 'Immortal: Perfume of Courage'),
    ('Immortal: Perfume of Tenacity', 'Immortal: Perfume of Deep Sea'),
  ]) {
    for (final batch in [1, 10]) {
      test(
        '${row.$1} exact conversion route x$batch drives plan and price',
        () {
          final id = batch == 1 ? 'immortal-perfume' : 'immortal-perfume-10x';
          final state = ModeState(
            target: row.$1,
            bonusTarget: '',
            recipeVariantChoices: {row.$1: id},
            market: MarketState(prices: {for (final n in recipes.keys) n: 100}),
            appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
          );
          final selected = const PlannerAssembly().assembleRecipes(
            catalog: catalog.processing,
            state: state,
            supportingData: catalog.supportingData,
            sharedMetadata: catalog.alchemy.metadata,
            mode: CraftMode.processing,
            processingRecipes: catalog.processing.items,
          );
          final recipe = selected[row.$1]!.resolveVariant(id);
          final expected = {
            row.$2: batch.toDouble(),
            'Shining Powder': batch * 3.0,
            'Caphras Essence': batch * 10.0,
            if (batch == 10) "Ibellab's Essence": 1.0,
          };
          expect({
            for (final i in recipe.ingredients) i.name: i.quantity,
          }, expected);
          expect(recipe.outputMinimum, batch);
          expect(recipe.outputMaximum, batch);
          expect(recipe.defaultVariantId, 'standard');
          expect(recipe.variants, hasLength(4));
          final result = const PlannerEngine().buildPlan(
            mode: CraftMode.processing,
            recipes: selected,
            state: plan.PlannerState(
              target: row.$1,
              want: batch * 2,
              recipeVariantChoices: {row.$1: id},
            ),
          );
          final step = result.steps.singleWhere((s) => s.name == row.$1);
          expect(step.count, 2);
          expect(step.produced, batch * 2);
          expect(
            {for (final i in step.ingredients) i.name: i.need},
            {for (final e in expected.entries) e.key: e.value * 2},
          );
          final quote = const RecipeProfitabilityCalculator().calculate(
            recipe: recipe,
            recipes: selected,
            state: state,
            rules: plan.PlannerRules(),
            marketTax: MarketTax(),
          );
          expect(quote.isAvailable, isTrue);
          expect(quote.outputPerCraft, batch);
          expect(
            quote.ingredientCost,
            expected.values.reduce((a, b) => a + b) * 100,
          );
        },
      );
    }
  }

  test(
    'Tidal alternatives retain exact costs and inventory in Opportunities',
    () {
      const name = 'Deep Blue Tidal Draught';
      final now = DateTime.utc(2026, 11, 3);
      final prices = {
        name: 1000,
        'Tidal Draught': 100,
        'Blue Tidal Draught': 190,
      };
      final rules = const PlannerAssembly().plannerRules(
        catalog.supportingData,
      );
      expect(rules.marketIds['Essence of Tides'], '767696');
      expect(reviewedNonMarketableOpportunityIds, contains('767696'));
      final market = OpportunityMarketSnapshot(
        region: 'eu',
        items: {
          for (final entry in prices.entries)
            recipes[entry.key]!.marketId!: OpportunityMarketItem(
              itemId: recipes[entry.key]!.marketId!,
              basePrice: entry.value,
              stock: 10000,
              quoteFetchedAt: now,
              asks: [
                OpportunityMarketLevel(price: entry.value, quantity: 10000),
              ],
              bids: [],
              bookFetchedAt: now,
            ),
        },
      );
      for (final choice in ['Tidal Draught', 'Blue Tidal Draught']) {
        for (final owned in [0, 1]) {
          final quote = const OpportunityCalculator().evaluate(
            recipe: recipes[name]!,
            recipes: recipes,
            state: ModeState(
              target: name,
              bonusTarget: '',
              inventory: {choice: owned.toDouble(), 'Essence of Tides': 10},
              ignoreIngredientInventory: false,
              market: MarketState(),
              appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
            ),
            rules: rules,
            marketTax: MarketTax(),
            market: market,
            now: now,
            crafts: 10,
            ingredientChoices: {'Tidal Draught': choice},
            useInventory: true,
            nonMarketableIds: reviewedNonMarketableOpportunityIds,
          );
          final amount = choice == 'Tidal Draught' ? 40 : 20;
          final input = quote.ingredients.singleWhere((i) => i.name == choice);
          expect(input.quantity, amount);
          expect(input.ownedQuantity, owned);
          expect(input.purchaseQuantity, amount - owned);
          expect(
            quote.ingredients
                .singleWhere((i) => i.name == 'Essence of Tides')
                .quantity,
            10,
          );
          expect(quote.expectedOutput, 10);
          expect(
            quote.inputCost,
            (choice == 'Tidal Draught' ? 4000 : 3800) - owned * prices[choice]!,
          );
          expect(quote.marketReady, isTrue);
        }
      }
      final missingReward = const OpportunityCalculator().evaluate(
        recipe: recipes[name]!,
        recipes: recipes,
        state: ModeState(
          target: name,
          bonusTarget: '',
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
        ),
        rules: rules,
        marketTax: MarketTax(),
        market: market,
        now: now,
        ingredientChoices: {'Tidal Draught': 'Blue Tidal Draught'},
        nonMarketableIds: reviewedNonMarketableOpportunityIds,
      );
      expect(missingReward.inputCost, isNull);
      expect(missingReward.marketReady, isFalse);
      expect(
        missingReward.ingredients
            .singleWhere((i) => i.name == 'Essence of Tides')
            .purchaseQuantity,
        1,
      );
    },
  );

  test('review is narrowly scoped and uses exact normal/rare identities', () {
    expect(changes, hasLength(63));
    expect(changes.map((r) => r['name']).toSet(), hasLength(10));
    for (final row in changes) {
      final pair =
          (review['identities'] as Map<String, dynamic>)[row['group']]
              as Map<String, dynamic>;
      expect(catalog.processing.items[row['name']]!.marketId, '${row['id']}');
      expect(
        {row['input'], row['alternative']},
        {pair['normal'], pair['rare']},
      );
      expect(recipes.containsKey(row['alternative']), isTrue);
    }
  });
  for (final name in ["Beast's Draught", "Giant's Draught"]) {
    for (final batch in [1, 10]) {
      for (final second in [
        '[Mix] Swiftness-Wind-Spell Elixir',
        '[Mix] Thorn-Defense Elixir',
      ]) {
        test('$name mixed $second/$batch keeps complete correlated inputs', () {
          final id = batch == 1 ? 'mixed-elixirs' : 'mixed-elixirs-10x';
          final source = recipes[name]!;
          final recipe = source.resolveVariant(id);
          expect(source.defaultVariantId, 'standard');
          expect(recipe.ingredients, hasLength(batch == 1 ? 3 : 4));
          final primary = name == "Beast's Draught"
              ? '[Mix] EXP-Reaper Elixir'
              : '[Mix] Manhunt-Rage Elixir';
          final result = const PlannerEngine().buildPlan(
            mode: CraftMode.processing,
            recipes: recipes,
            state: plan.PlannerState(
              target: name,
              want: batch,
              recipeVariantChoices: {name: id},
              substituteChoices: {'recipe:$name:Mixed Elixir': second},
            ),
          );
          final step = result.steps.singleWhere((s) => s.name == name);
          expect(step.count, 1);
          expect(step.produced, batch);
          expect(
            {for (final i in step.ingredients) i.name: i.need},
            {
              primary: batch.toDouble(),
              second: batch.toDouble(),
              'Tears of the Falling Moon': batch.toDouble(),
              if (batch == 10) "Ibellab's Essence": 1.0,
            },
          );
          expect(recipes[primary]!.isCraftable, isFalse);
          expect(recipes[second]!.isCraftable, isFalse);
          expect(experienceFor(recipe, CraftMode.processing), isNull);
        });
      }
    }
    for (final batch in [1, 10]) {
      test(
        '$name restored $batch batch produces exact output and scales all inputs',
        () {
          final source = recipes[name]!;
          final id = batch == 1 ? 'standard' : 'standard-10x';
          final recipe = source.resolveVariant(id);
          expect(source.defaultVariantId, 'standard');
          expect(recipe.ingredients, hasLength(batch == 1 ? 4 : 5));
          expect(
            const PlannerEngine().outputPerCraft(
              recipe: recipe,
              state: plan.PlannerState(target: name),
            ),
            batch,
          );
          final selected = {
            for (final i in recipe.ingredients.where(
              (i) => i.options.isNotEmpty,
            ))
              'recipe:$name:${i.substituteGroup}': i.options.last,
          };
          final result = const PlannerEngine().buildPlan(
            mode: CraftMode.processing,
            recipes: recipes,
            state: plan.PlannerState(
              target: name,
              want: batch,
              substituteChoices: selected,
              recipeVariantChoices: {name: id},
            ),
          );
          final step = result.steps.singleWhere((s) => s.name == name);
          expect(step.count, 1);
          expect(step.produced, batch);
          for (final i in step.ingredients) {
            expect(i.need, i.name == "Ibellab's Essence" ? 1 : batch);
          }
          expect(experienceFor(recipe, CraftMode.processing), isNull);
        },
      );
    }
  }
  for (final row in changes) {
    final name = row['name'] as String, variant = row['variant'] as String;
    final input = row['input'] as String,
        alternative = row['alternative'] as String;
    final quantity = (row['qty'] as num).toDouble(),
        ratio = (row['ratio'] as num).toDouble();
    test(
      '$name/$variant/$input keeps primary and exact alternative quantities',
      () {
        final source = recipes[name]!;
        final recipe = variant == 'base'
            ? source
            : source.resolveVariant(variant);
        final ingredient = recipe.ingredients.singleWhere(
          (i) => i.name == input,
        );
        expect(ingredient.quantity, quantity);
        expect(ingredient.options, [input, alternative]);
        expect(ingredient.substituteRatios, {input: 1.0, alternative: ratio});
        expect(ingredient.substituteGroup, row['group']);
        expect(
          experienceFor(recipe, CraftMode.processing),
          isNull,
          reason: 'Do not invent previously unknown EXP.',
        );
        for (final choice in [input, alternative]) {
          final expected = quantity * (choice == input ? 1 : ratio);
          final state = plan.PlannerState(
            target: name,
            want: 1,
            inventory: {choice: 1},
            ignoreIngredientInventory: false,
            substituteChoices: {'recipe:$name:${row['group']}': choice},
          );
          final selected = const PlannerEngine().previewIngredientSelection(
            recipes: recipes,
            state: state,
            parentName: name,
            ingredient: ingredient,
          );
          expect(selected.name, choice);
          expect(selected.need, closeTo(expected, 1e-9));
          expect(selected.have, 1);
          expect(
            selected.missing,
            closeTo(expected > 1 ? expected - 1 : 0, 1e-9),
          );
        }
      },
    );
  }
  test(
    'Armor Draught Auto compares cost per replacement and uses owned alternatives',
    () {
      final ingredient = recipes['Armor Draught']!.ingredients.first;
      plan.PlanStepIngredient preview(
        Map<String, double> inventory,
        Map<String, double> stock,
      ) => const PlannerEngine().previewIngredientSelection(
        recipes: recipes,
        parentName: 'Armor Draught',
        ingredient: ingredient,
        rules: const PlannerAssembly().plannerRules(catalog.supportingData),
        state: plan.PlannerState(
          target: 'Armor Draught',
          want: 1,
          ignoreIngredientInventory: false,
          inventory: inventory,
          marketPrices: {
            'Elixir of Will': 100,
            'Elixir of Remarkable Will': 250,
          },
          marketStock: stock,
        ),
      );
      final cheaper = preview({}, {
        'Elixir of Will': 100,
        'Elixir of Remarkable Will': 100,
      });
      expect(cheaper.name, 'Elixir of Remarkable Will');
      expect(cheaper.need, 1);
      expect(
        preview({}, {
          'Elixir of Will': 100,
          'Elixir of Remarkable Will': 0,
        }).name,
        'Elixir of Will',
      );
      final owned = preview(
        {'Elixir of Remarkable Will': 1},
        {'Elixir of Will': 100, 'Elixir of Remarkable Will': 0},
      );
      expect(owned.name, 'Elixir of Remarkable Will');
      expect(owned.missing, 0);
    },
  );
}
