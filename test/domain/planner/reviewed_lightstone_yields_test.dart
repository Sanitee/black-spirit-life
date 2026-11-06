import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/market/recipe_profitability.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as plan;
import 'package:bdo_craft_planner_flutter/domain/planner/reviewed_recipe_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, Recipe> recipes;
  ModeState state(int mastery) => ModeState(
    target: '',
    bonusTarget: '',
    alchemyMastery: mastery,
    market: MarketState(prices: {for (final name in recipes.keys) name: 100.0}),
    appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
  );
  setUpAll(() {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    recipes = {};
    recipes = const PlannerAssembly().assembleRecipes(
      catalog: catalog.alchemy,
      state: state(0),
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.alchemy,
      processingRecipes: catalog.processing.items,
    );
  });
  for (final type in ['Fire', 'Earth', 'Wind', 'Flora']) {
    for (final mastery in [0, 1000, 2000, 3000]) {
      test('$type/$mastery counts the base result in every calculation', () {
        final recipe = recipes['Purified Lightstone of $type']!;
        expect(usesReviewedLightstoneBaseOutput(recipe), isTrue);
        expect(recipe.outputMinimum, 1);
        expect(recipe.outputMaximum, 2);
        expect(
          const PlannerEngine().outputPerCraft(
            recipe: recipe,
            state: plan.PlannerState(
              target: recipe.name,
              alchemyMastery: mastery,
            ),
          ),
          1,
        );
        final quote = const RecipeProfitabilityCalculator().calculate(
          recipe: recipe,
          recipes: recipes,
          state: state(mastery),
          rules: plan.PlannerRules(),
          marketTax: MarketTax(),
        );
        expect(quote.isAvailable, isTrue);
        expect(quote.outputPerCraft, 1);
        expect(quote.grossRevenue, 100);
        expect(quote.outputNote, reviewedLightstoneYieldNote);
        final opportunity = const OpportunityCalculator().evaluate(
          recipe: recipe,
          recipes: recipes,
          state: state(mastery),
          rules: plan.PlannerRules(),
          marketTax: MarketTax(),
          crafts: 10,
          market: OpportunityMarketSnapshot(region: 'EU', items: {}),
          now: DateTime.utc(2026, 11, 3),
          customSalePrice: 100,
        );
        expect(opportunity.outputPerCraft, 1);
        expect(opportunity.expectedOutput, 10);
        expect(opportunity.listingRevenue, 650);
        expect(opportunity.outputNote, reviewedLightstoneYieldNote);
        expect(
          experienceFor(recipe, CraftMode.alchemy),
          isNull,
          reason: 'No unverified EXP inherited from an edited signature.',
        );
      });
    }
  }
  test('custom, wrong-identity and changed formulas do not inherit policy', () {
    final original = recipes['Purified Lightstone of Flora']!;
    Recipe changed({
      String? name,
      String? id,
      String? type,
      double? base,
      double? min,
      double? max,
      List<Ingredient>? inputs,
    }) => Recipe(
      name: name ?? original.name,
      type: type ?? original.type,
      baseOutput: base ?? original.baseOutput,
      group: original.group,
      method: original.method,
      ingredients: inputs ?? original.ingredients,
      marketId: id ?? original.marketId,
      sourceNote: original.sourceNote,
      vendor: original.vendor,
      location: original.location,
      npcPrice: original.npcPrice,
      qualityBase: original.qualityBase,
      qualityGrade: original.qualityGrade,
      outputMinimum: min ?? original.outputMinimum,
      outputMaximum: max ?? original.outputMaximum,
    );
    for (final recipe in [
      changed(name: '[Event] ${original.name}'),
      changed(id: '0'),
      changed(type: 'processing'),
      changed(base: 2),
      changed(min: 2),
      changed(max: 4),
      changed(inputs: original.ingredients.take(4).toList()),
      changed(
        inputs: [...original.ingredients.take(4), original.ingredients.first],
      ),
    ]) {
      expect(usesReviewedLightstoneBaseOutput(recipe), isFalse);
      expect(reviewedRecipeYieldNote(recipe), isNull);
    }
    final ordinary = recipes['Clear Liquid Reagent']!;
    expect(
      const PlannerEngine().outputPerCraft(
        recipe: ordinary,
        state: plan.PlannerState(target: ordinary.name),
      ),
      2.5,
    );
    expect(reviewedRecipeYieldNote(ordinary), isNull);
  });
}
