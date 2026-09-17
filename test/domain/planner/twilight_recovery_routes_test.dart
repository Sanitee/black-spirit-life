import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_effort.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  const assembly = PlannerAssembly();
  const slots = ['Necklace', 'Earring', 'Ring', 'Belt'];

  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  ModeState stateFor(String target, {RecipeState? oldApeironRecipe}) =>
      ModeState(
        target: target,
        want: oldApeironRecipe == null ? 2 : 101,
        bonusTarget: '',
        inventory: {
          'Caphras Stone': 100,
          'Magical Shard': 100,
          'Essence of Dawn': 100,
          for (final slot in slots) 'Apeiron $slot': 100,
          for (final slot in slots) 'Causality Shardstone - $slot': 1,
        },
        ignoreTargetInventory: false,
        ignoreIngredientInventory: false,
        recipeEdits: {target: ?oldApeironRecipe},
        recipeVariantChoices: {
          for (final slot in slots)
            'Twilight of the End - $slot': 'from-causality-shardstone',
        },
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      );

  Map<String, Recipe> recipesFor(ModeState state) => assembly.assembleRecipes(
    catalog: catalog.processing,
    state: state,
    supportingData: catalog.supportingData,
    sharedMetadata: catalog.alchemy.metadata,
    mode: CraftMode.processing,
    processingRecipes: catalog.processing.items,
  );

  for (final slot in slots) {
    test('$slot recovery has two readable, exact, reference-only routes', () {
      final name = 'Twilight of the End - $slot';
      final recipe = catalog.processing.items[name]!;
      final recovered = recipe.resolveVariant('from-causality-shardstone');
      expect(isBrowsableRecipeBookReference(recipe), isTrue);
      expect(recipe.isCraftable, isFalse);
      expect(recovered.isCraftable, isFalse);
      expect(recipe.defaultVariantId, 'from-apeiron');
      expect(recovered.ingredients.single.name, 'Causality Shardstone - $slot');
      expect(recovered.ingredients.single.quantity, 1);
      expect(recovered.method, 'Heating');
      expect(recovered.outputMinimum, 5);
      expect(recovered.outputMaximum, 5);
      final state = stateFor(name);
      expect(
        const PlannerEngine().outputPerCraft(
          recipe: recovered,
          state: assembly.plannerState(state),
        ),
        5,
      );
      final info = recipeBookInfoFor(
        name: name,
        recipe: recipe,
        searchTerms: const [],
        consumerRecipes: catalog.processing.items.values.toList(),
      )!;
      expect(info.acquisitionFormulas, hasLength(2));
      final formula = info.acquisitionFormulas.singleWhere(
        (formula) => formula.variantId == 'from-causality-shardstone',
      );
      expect(formula.ingredients.single.name, 'Causality Shardstone - $slot');
      expect(formula.outputMinimum, 5);
      expect(formula.outputMaximum, 5);
      expect(formula.outputEstimated, isFalse);
      expect(experienceFor(recovered, CraftMode.processing), isNull);
      expect(
        resolveAcquisitionRecipe(
          name: name,
          currentMode: CraftMode.processing,
          recipesByMode: {CraftMode.processing: recipesFor(state)},
        ),
        isNull,
      );
    });

    test(
      '$slot owned accessories and Shardstones cannot cause recovery loops',
      () {
        final name = 'Causality Shardstone - $slot';
        final state = stateFor(name);
        final before = jsonEncode(state.toJson());
        final plan = assembly.build(
          catalog: catalog,
          mode: CraftMode.processing,
          state: state,
        );
        expect(plan.empty, isFalse);
        expect(plan.steps.map((step) => step.name), [name]);
        final twilight = plan.missing.singleWhere(
          (item) => item.name == 'Twilight of the End - $slot',
        );
        expect(twilight.missing, 5);
        expect(jsonEncode(state.toJson()), before);

        final recipes = recipesFor(state);
        final recovery = recipes['Twilight of the End - $slot']!;
        final quote = const OpportunityCalculator().evaluate(
          recipe: recovery,
          recipes: recipes,
          state: state,
          rules: assembly.plannerRules(catalog.supportingData),
          marketTax: MarketTax(),
          market: OpportunityMarketSnapshot(region: 'EU', items: const {}),
          now: DateTime.utc(2026, 9, 17),
          selectedVariantId: 'from-causality-shardstone',
        );
        expect(quote.issues, contains(OpportunityIssue.recipeNotCraftable));
        final withReferences = RecipeEffortIndex({
          CraftMode.processing: recipes,
        });
        final withoutReferences = RecipeEffortIndex({
          CraftMode.processing: {
            for (final entry in recipes.entries)
              if (!entry.value.isReferenceOnly) entry.key: entry.value,
          },
        });
        expect(
          withReferences.effortFor(recipes[name]!, CraftMode.processing),
          withoutReferences.effortFor(recipes[name]!, CraftMode.processing),
        );
      },
    );

    test('$slot obsolete saved Apeiron formula stays nonproduction', () {
      final name = 'Apeiron $slot';
      final state = stateFor(
        name,
        oldApeironRecipe: RecipeState(
          type: 'processing',
          role: RecipeRole.production,
          baseOutput: .4,
          method: 'Heating',
          outputMinimum: 1,
          outputMaximum: 1,
          ingredients: [
            IngredientState(name: 'Twilight of the End - $slot', quantity: 10),
            IngredientState(name: 'Caphras Stone', quantity: 10),
            IngredientState(name: 'Magical Shard', quantity: 10),
          ],
        ),
      );
      final before = jsonEncode(state.toJson());
      final recipe = recipesFor(state)[name]!;
      expect(recipe.role, RecipeRole.manualConversion);
      expect(recipe.isCraftable, isFalse);
      expect(
        assembly
            .build(catalog: catalog, mode: CraftMode.processing, state: state)
            .steps,
        isEmpty,
      );
      expect(jsonEncode(state.toJson()), before);
    });
  }
}
