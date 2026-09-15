import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/item_acquisition_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/recipe_route_economics.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart'
    as saved;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  const assembly = PlannerAssembly();
  const engine = PlannerEngine();
  const calculator = OpportunityCalculator();
  final rules = assembly.plannerRules(catalog.supportingData);
  Map<String, Recipe> assembled(CraftMode mode) => assembly.assembleRecipes(
    catalog: catalog.forMode(mode),
    state: _state(mode),
    supportingData: catalog.supportingData,
    sharedMetadata: catalog.alchemy.metadata,
    mode: mode,
  );

  test('policy is exact, temporary and identity-aware', () {
    expect(temporarilyArchivedItemsById, {
      '6211': 'Monkey Blood',
      '6011': 'Monkey Hide',
      '6007': 'Dinosaur Hide',
      '15202': 'Black Magic Crystal - Power',
      '15208': 'Black Magic Crystal - Patience',
      '15209': 'Black Magic Crystal - Healing',
      '15210': 'Black Magic Crystal - Resonance',
      '15215': 'Black Magic Crystal - Endurance',
    });
    for (final entry in temporarilyArchivedItemsById.entries) {
      expect(isTemporarilyArchivedMarketItemId(entry.key), isTrue);
      expect(
        isTemporarilyArchivedItem(' ${entry.value.toUpperCase()} '),
        isTrue,
      );
      expect(
        isTemporarilyArchivedItem('Custom alias', itemId: entry.key),
        isTrue,
      );
      expect(isTemporarilyArchivedItem(entry.value, itemId: '999999'), isFalse);
    }
    for (final name in [
      'Sealed Black Magic Crystal',
      'Black Magic Crystal - Precision',
      'Black Magic Crystal - Armor',
      'BON Magic Crystal - Power',
      'Lizard Hide',
      'Fox Blood',
    ]) {
      expect(isTemporarilyArchivedItem(name), isFalse);
    }
    expect(temporarilyArchivedItemReason, 'No current source confirmed.');
  });

  test(
    'shared acquisition guidance suppresses claims but preserves history',
    () {
      for (final entry in temporarilyArchivedItemsById.entries) {
        final original = rules.acquisitionInfo[entry.value]!;
        final resolved = resolveItemAcquisition(
          name: entry.value,
          rules: rules,
        )!;
        expect(resolved.status, 'temporarily_archived');
        expect(resolved.displayableSummaries, isEmpty);
        expect(resolved.canonicalName, original.canonicalName);
        expect(resolved.itemId, original.itemId);
        expect(resolved.reviewedAt, original.reviewedAt);
        expect(resolved.routes, original.routes);
        expect(resolved.routes.first, same(original.routes.first));
        expect(original.status, 'reviewed');
        expect(original.routes, isNotEmpty);
      }
      final aliasedRules = PlannerRules(
        acquisitionInfo: rules.acquisitionInfo,
        marketNameAliases: const {'Historical alias': 'Monkey Blood'},
      );
      expect(
        resolveItemAcquisition(
          name: 'Historical alias',
          rules: aliasedRules,
        )!.displayableSummaries,
        isEmpty,
      );
      expect(
        resolveItemAcquisition(name: 'Sugar', rules: rules),
        same(rules.acquisitionInfo['Sugar']),
      );
    },
  );

  for (final scenario in [
    ('Hard Hide', 'Dinosaur Hide', 'Lizard Hide'),
    ('Thin Hide', 'Monkey Hide', 'Raccoon Hide'),
  ]) {
    test('${scenario.$1} retains history but chooses an active hide', () {
      final recipes = assembled(CraftMode.processing);
      final recipe = recipes[scenario.$1]!;
      final ingredient = recipe.ingredients.single;
      final choiceKey =
          'recipe:${recipe.name}:${ingredient.substituteGroup ?? ingredient.name}';
      final state = PlannerState(
        target: recipe.name,
        inventory: {scenario.$2: 1000},
        marketPrices: {scenario.$2: 1, scenario.$3: 100},
        marketStock: {scenario.$2: 1000, scenario.$3: 1000},
        substituteChoices: {choiceKey: scenario.$2},
      );
      final selected = engine.previewIngredientSelection(
        recipes: recipes,
        state: state,
        parentName: recipe.name,
        ingredient: ingredient,
        rules: rules,
      );
      expect(selected.name, scenario.$3);
      expect(selected.need, 5);
      expect(selected.options, isNot(contains(scenario.$2)));
      expect(ingredient.options, contains(scenario.$2));
      expect(ingredient.substituteRatios[scenario.$2], 1);
      expect(state.substituteChoices[choiceKey], scenario.$2);
      expect(state.inventory[scenario.$2], 1000);
    });
  }

  test('blood ratios and saved keys survive archive filtering', () {
    final recipes = assembled(CraftMode.alchemy);
    final recipe = recipes.values.firstWhere(
      (recipe) => recipe.ingredients.any(
        (ingredient) => ingredient.options.contains('Monkey Blood'),
      ),
    );
    final ingredient = recipe.ingredients.firstWhere(
      (ingredient) => ingredient.options.contains('Monkey Blood'),
    );
    final key =
        'recipe:${recipe.name}:${ingredient.substituteGroup ?? ingredient.name}';
    final state = PlannerState(
      target: recipe.name,
      inventory: const {'Monkey Blood': 1000},
      substituteChoices: {key: 'Monkey Blood'},
      marketPrices: const {'Monkey Blood': 1, 'Weasel Blood': 100},
      marketStock: const {'Monkey Blood': 1000, 'Weasel Blood': 1000},
    );
    final selected = engine.previewIngredientSelection(
      recipes: recipes,
      state: state,
      parentName: recipe.name,
      ingredient: ingredient,
      rules: rules,
    );
    expect(selected.name, 'Weasel Blood');
    expect(
      selected.need,
      ingredient.quantity * ingredient.substituteRatios['Weasel Blood']!,
    );
    expect(selected.options, isNot(contains('Monkey Blood')));
    expect(ingredient.options, contains('Monkey Blood'));
    expect(recipes['Monkey Blood']!.marketId, '6211');
    expect(state.substituteChoices[key], 'Monkey Blood');
  });

  test('Magical Shard keeps real alternatives and historical variants', () {
    final recipes = assembled(CraftMode.processing);
    final recipe = recipes['Magical Shard']!;
    final ids = calculator.marketItemIds(
      recipe: recipe,
      recipes: recipes,
      rules: rules,
    );
    expect(ids.any(isTemporarilyArchivedMarketItemId), isFalse);
    for (final formula in [
      recipe,
      ...recipe.variants.map((v) => recipe.resolveVariant(v.id)),
    ]) {
      final ingredient = formula.ingredients.first;
      expect(ingredient.options, contains('Black Magic Crystal - Power'));
      final selected = engine.previewIngredientSelection(
        recipes: recipes,
        state: PlannerState(target: recipe.name),
        parentName: recipe.name,
        ingredient: ingredient,
        rules: rules,
      );
      expect(selected.options.any(isTemporarilyArchivedItem), isFalse);
      expect(selected.options, contains('Sealed Black Magic Crystal'));
      expect(selected.options, contains('Black Magic Crystal - Precision'));
      expect(selected.options, contains('Black Magic Crystal - Armor'));
    }
  });

  test(
    'archived-only input preserves original ratio and stays unpriced despite cache',
    () {
      final ingredient = Ingredient(
        name: 'Monkey Hide',
        quantity: 5,
        options: const [],
        substituteGroup: 'saved-original-key',
        substituteRatios: const {'Monkey Hide': 2},
      );
      final product = _recipe(
        'Product',
        id: '999991',
        ingredients: [ingredient],
      );
      final recipes = {
        'Product': product,
        'Monkey Hide': _recipe('Monkey Hide', id: '6011'),
      };
      final now = DateTime.utc(2026, 9, 10);
      final snapshot = OpportunityMarketSnapshot(
        region: 'eu',
        items: {
          for (final id in ['999991', '6011'])
            id: OpportunityMarketItem(
              itemId: id,
              basePrice: 100,
              stock: 1000,
              quoteFetchedAt: now,
              asks: const [OpportunityMarketLevel(price: 100, quantity: 1000)],
              bids: const [],
              bookFetchedAt: now,
            ),
        },
      );
      final quote = calculator.evaluate(
        recipe: product,
        recipes: recipes,
        state: _state(CraftMode.processing),
        rules: rules,
        marketTax: saved.MarketTax(),
        market: snapshot,
        now: now,
      );
      expect(quote.ingredients.single.name, 'Monkey Hide');
      expect(quote.ingredients.single.quantity, 10);
      expect(quote.ingredients.single.quantityPerCraft, 10);
      expect(quote.ingredients.single.market, isNull);
      expect(quote.ingredients.single.preliminaryCost, isNull);
      expect(quote.inputCost, isNull);
      expect(quote.listingProfit, isNull);
      expect(quote.marketReady, isFalse);
      expect(snapshot.items['6011']!.basePrice, 100);
      expect(
        calculator.marketItemIds(
          recipe: product,
          recipes: recipes,
          rules: rules,
        ),
        {'999991'},
      );
      final plan = engine.buildPlan(
        mode: CraftMode.processing,
        recipes: recipes,
        state: PlannerState(
          target: 'Product',
          want: 1,
          marketPrices: const {'Monkey Hide': 1},
          marketStock: const {'Monkey Hide': 1000},
        ),
        rules: rules,
      );
      expect(plan.missing.single.name, 'Monkey Hide');
      expect(plan.missing.single.missing, 10);
      expect(plan.missing.single.market.buyable, 0);
      expect(plan.missing.single.market.stockKnown, isFalse);
      expect(ingredient.quantity, 5);
      expect(ingredient.substituteGroup, 'saved-original-key');
      expect(ingredient.substituteRatios, {'Monkey Hide': 2});
    },
  );

  test(
    'automatic routes bypass archived defaults without rewriting saved choice',
    () {
      final archived = _variant('archived', 'Monkey Hide');
      final active = _variant('active', 'NPC Input');
      final product = _recipe(
        'Product',
        ingredients: archived.ingredients,
        variants: [archived, active],
      );
      final recipes = {
        'Product': product,
        'Monkey Hide': _recipe('Monkey Hide', id: '6011'),
        'NPC Input': _recipe('NPC Input', npc: 50),
      };
      final state = PlannerState(
        target: 'Product',
        recipeVariantChoices: const {'Product': 'archived'},
        marketPrices: const {'Monkey Hide': 1},
        marketStock: const {'Monkey Hide': 1000},
      );
      final selected = resolveRecipeRoute(
        recipe: product,
        recipes: recipes,
        state: state,
        rules: rules,
      );
      expect(selected.selectedVariantId, 'active');
      expect(selected.automaticVariantId, 'active');
      expect(state.recipeVariantChoices['Product'], 'archived');
      expect(product.defaultVariant!.id, 'archived');
    },
  );

  test('ordinary unsupported batch retains a non-first recorded default', () {
    final first = _variant('first', 'NPC Input');
    final recordedDefault = _variant('recorded-default', 'NPC Input');
    final product = _recipe(
      'Product',
      ingredients: recordedDefault.ingredients,
      variants: [first, recordedDefault],
      defaultVariantId: 'recorded-default',
    );
    final state = PlannerState(
      target: 'Product',
      recipeVariantChoices: const {'Product': '__auto_batch_7'},
    );
    final selected = resolveRecipeRoute(
      recipe: product,
      recipes: {'Product': product, 'NPC Input': _recipe('NPC Input', npc: 50)},
      state: state,
      rules: rules,
    );
    expect(selected.selectedVariantId, 'recorded-default');
    expect(selected.automaticVariantId, 'recorded-default');
    expect(state.recipeVariantChoices['Product'], '__auto_batch_7');
    expect(product.variants.first.id, 'first');
  });
}

saved.ModeState _state(CraftMode mode) => saved.ModeState(
  target: '',
  bonusTarget: '',
  market: saved.MarketState(),
  appearance: saved.AppearanceSettings.defaultsFor(mode),
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const [],
  substituteGroup: null,
  substituteRatios: const {},
);

RecipeVariant _variant(String id, String input) => RecipeVariant(
  id: id,
  label: id,
  type: 'processing',
  baseOutput: 1,
  method: 'Heating',
  ingredients: [_ingredient(input, 5)],
  outputMinimum: 1,
  outputMaximum: 1,
);

Recipe _recipe(
  String name, {
  String? id,
  double npc = 0,
  List<Ingredient> ingredients = const [],
  List<RecipeVariant> variants = const [],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: ingredients.isEmpty ? 'gathered' : 'processing',
  baseOutput: 1,
  group: null,
  method: 'Heating',
  ingredients: ingredients,
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: npc,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: ingredients.isEmpty ? null : 1,
  outputMaximum: ingredients.isEmpty ? null : 1,
  variants: variants,
  defaultVariantId: defaultVariantId ?? variants.firstOrNull?.id,
);
