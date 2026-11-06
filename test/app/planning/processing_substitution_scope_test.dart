import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/market/recipe_profitability.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as plan;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late Map<String, Recipe> processing;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    processing = _assemble(catalog, CraftMode.processing);
  });

  test('every Processing formula preserves its declared substitute scope', () {
    for (final original in catalog.processing.items.values) {
      if (original.type != 'processing') continue;
      final assembled = processing[original.name]!;
      expect(
        _rows(assembled.ingredients),
        _rows(original.ingredients),
        reason: original.name,
      );
      expect(
        assembled.variants.map((v) => v.id),
        original.variants.map((v) => v.id),
      );
      for (final variant in original.variants) {
        final actual = assembled.variants.singleWhere(
          (v) => v.id == variant.id,
        );
        expect(
          _rows(actual.ingredients),
          _rows(variant.ingredients),
          reason: '${original.name}/${variant.id}',
        );
        expect(actual.outputMinimum, variant.outputMinimum);
        expect(actual.outputMaximum, variant.outputMaximum);
      }
    }
  });

  for (final (name, route, prefix) in [
    ('Concentrated Herbal Juice', 'high-quality-herbs', 'High-quality '),
    ('Highly Concentrated Herbal Juice', 'special-herbs', 'Special '),
  ]) {
    test('$name only offers the declared herb grade', () {
      final recipe = processing[name]!;
      final ingredient = recipe.resolveVariant(route).ingredients.first;
      expect(ingredient.options, hasLength(6));
      expect(ingredient.options, everyElement(startsWith(prefix)));
      expect(ingredient.substituteRatios.values, everyElement(1));
      expect(recipe.variantBatchMultipliers, [1, 10, 100]);
    });
  }

  test('Elixir of Regeneration keeps exact Troll Blood and Grape inputs', () {
    final recipe = processing['Elixir of Regeneration']!;
    for (final (name, amount) in [('Troll Blood', 2), ('Grape', 4)]) {
      final ingredient = recipe.ingredients.singleWhere((i) => i.name == name);
      expect(ingredient.quantity, amount);
      expect(ingredient.options, isEmpty);
      expect(ingredient.substituteRatios, isEmpty);
    }
  });

  test('Grape-scented Herbal Wine does not gain the generic fruit group', () {
    final grape = processing['Grape-scented Herbal Wine']!.ingredients.first;
    expect(grape.name, 'Grape');
    expect(grape.options, isEmpty);
    expect(grape.substituteRatios, isEmpty);
  });

  test('declared Processing substitutions and recipe roles are retained', () {
    final powder = processing['Insectivore Plant Powder']!;
    expect(powder.variants, hasLength(2));
    final fragment = processing['Black Gem Fragment']!;
    expect(fragment.role, catalog.processing.items[fragment.name]!.role);
    expect(fragment.isCraftable, isFalse);
    final draught = processing['Berserk Draught']!;
    expect(draught.ingredients.any((i) => i.options.isNotEmpty), isTrue);
  });

  test('ordinary residence Alchemy retains its blood substitutions', () {
    final alchemy = _assemble(catalog, CraftMode.alchemy);
    final clowns = alchemy['Clown\'s Blood']!.ingredients.singleWhere(
      (i) => i.name == 'Wolf Blood',
    );
    expect(clowns.options, contains('Flamingo Blood'));
    expect(clowns.substituteRatios['Flamingo Blood'], .5);
  });

  test('stale saved Processing choices cannot restore inferred inputs', () {
    const engine = PlannerEngine();
    final rules = const PlannerAssembly().plannerRules(catalog.supportingData);
    for (final (name, route, original, invalid) in [
      ('Elixir of Regeneration', null, 'Troll Blood', 'Bear Blood'),
      ('Elixir of Regeneration', null, 'Grape', 'Apple'),
      ('Grape-scented Herbal Wine', null, 'Grape', 'Apple'),
      (
        'Concentrated Herbal Juice',
        'high-quality-herbs',
        'High-quality Sunrise Herb',
        'Sunrise Herb',
      ),
      (
        'Highly Concentrated Herbal Juice',
        'special-herbs',
        'Special Sunrise Herb',
        'High-quality Sunrise Herb',
      ),
    ]) {
      final recipe = processing[name]!.resolveVariant(route);
      final ingredient = recipe.ingredients.singleWhere(
        (i) => i.name == original,
      );
      final state = plan.PlannerState(
        target: name,
        recipeVariantChoices: {name: ?route},
        substituteChoices: {
          engine.substituteChoiceKey(name, ingredient): invalid,
          'recipe:$name:Blood Group 4': invalid,
          'recipe:$name:Fruit Group 6007': invalid,
          'recipe:$name:Sunrise Herb Group 3001': invalid,
        },
        ingredientGrades: {'recipe:$name:$original': 'special'},
        inventory: {invalid: 1000000},
        marketPrices: {invalid: 1, for (final n in ingredient.options) n: 100},
      );
      final selected = engine.previewIngredientSelection(
        recipes: processing,
        state: state,
        parentName: name,
        ingredient: ingredient,
        rules: rules,
      );
      expect(selected.name, isNot(invalid), reason: '$name/$original');
      expect(selected.need, ingredient.quantity);
      expect(selected.options, isNot(contains(invalid)));
      expect(state.inventory[invalid], 1000000);
    }
  });

  test(
    'Opportunities prices exact Processing inputs despite cheaper substitutes',
    () {
      const name = 'Elixir of Regeneration';
      final quote = const RecipeProfitabilityCalculator().calculate(
        recipe: processing[name]!,
        recipes: processing,
        state: ModeState(
          target: name,
          bonusTarget: name,
          market: MarketState(
            prices: {
              for (final n in processing.keys) n: 10,
              'Bear Blood': 1,
              'Apple': 1,
            },
          ),
          appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
          substituteChoices: const {
            'recipe:Elixir of Regeneration:Blood Group 4': 'Bear Blood',
            'recipe:Elixir of Regeneration:Fruit Group 6007': 'Apple',
          },
        ),
        rules: plan.PlannerRules(),
        marketTax: MarketTax(),
      );
      expect(quote.isAvailable, isTrue);
      expect(
        quote.ingredientCosts.map((i) => i.selectedName),
        isNot(anyOf(contains('Bear Blood'), contains('Apple'))),
      );
      final blood = quote.ingredientCosts.singleWhere(
        (i) => i.originalName == 'Troll Blood',
      );
      final grape = quote.ingredientCosts.singleWhere(
        (i) => i.originalName == 'Grape',
      );
      expect(
        (blood.selectedName, blood.quantity, blood.total),
        ('Troll Blood', 2, 20),
      );
      expect(
        (grape.selectedName, grape.quantity, grape.total),
        ('Grape', 4, 40),
      );
    },
  );

  test('explicit custom Processing alternatives survive unchanged', () {
    final custom = RecipeState(
      type: 'processing',
      ingredients: [
        IngredientState(
          name: 'Troll Blood',
          quantity: 2,
          options: ['Troll Blood', 'Bear Blood'],
          substituteGroup: 'User-authored pair',
          substituteRatios: {'Troll Blood': 1, 'Bear Blood': 2},
        ),
      ],
    );
    final recipes = const PlannerAssembly().assembleRecipes(
      catalog: catalog.processing,
      state: ModeState(
        target: '',
        bonusTarget: '',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
        recipeEdits: {'Synthetic explicit Processing recipe': custom},
      ),
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.processing,
    );
    final ingredient =
        recipes['Synthetic explicit Processing recipe']!.ingredients.single;
    expect(ingredient.options, ['Troll Blood', 'Bear Blood']);
    expect(ingredient.substituteRatios, {'Troll Blood': 1, 'Bear Blood': 2});
    expect(ingredient.substituteGroup, 'User-authored pair');
  });
}

Map<String, Recipe> _assemble(CatalogSnapshot catalog, CraftMode mode) =>
    const PlannerAssembly().assembleRecipes(
      catalog: catalog.forMode(mode),
      state: ModeState(
        target: '',
        bonusTarget: '',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(mode),
      ),
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: mode,
    );

List<Object?> _rows(Iterable<Ingredient> ingredients) => [
  for (final i in ingredients)
    [i.name, i.quantity, i.options, i.substituteGroup, i.substituteRatios],
];
