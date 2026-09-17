import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/afk_weight_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pile-selected production plan has an exact usable AFK load', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    const assembly = PlannerAssembly();
    const recipeName = 'Clear Liquid Reagent';
    const selectedHerb = 'Pile of Sunrise Herbs';
    final state = ModeState(
      target: recipeName,
      want: 100,
      bonusTarget: '',
      ignoreTargetInventory: true,
      ignoreIngredientInventory: true,
      substituteChoices: const {
        'recipe:Clear Liquid Reagent:Sunrise Herb Group 3001': selectedHerb,
      },
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
    );
    final recipes = assembly.assembleRecipes(
      catalog: catalog.alchemy,
      state: state,
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.alchemy,
      processingRecipes: catalog.processing.items,
    );
    final plan = assembly.build(
      catalog: catalog,
      mode: CraftMode.alchemy,
      state: state,
    );
    final step = plan.steps.singleWhere((step) => step.name == recipeName);
    final selected = step.ingredients.singleWhere(
      (ingredient) => ingredient.name == selectedHerb,
    );
    expect(selected.need / step.count, 1);
    expect(
      step.ingredients.any((item) => item.name == 'Sunrise Herb'),
      isFalse,
    );

    final rules = assembly.plannerRules(catalog.supportingData);
    final result = const AfkWeightCalculator().calculateSessionPlan(
      mode: CraftMode.alchemy,
      step: step,
      recipe: recipes[recipeName]!,
      rules: rules,
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );
    expect(rules.itemWeightIdFor(selectedHerb), '5421');
    expect(result.maximumCapacity.available, isTrue);
    expect(result.maximumCapacity.missingWeightItems, isEmpty);
    expect(
      result.maximumCapacity.warnings,
      isNot(contains(AfkWeightWarning.missingItemWeights)),
    );
    expect(result.loads, isNotEmpty);
    expect(result.plannedAttempts, step.count);
    for (final load in result.loads) {
      final herbs = load.ingredientStacks.singleWhere(
        (stack) => stack.itemName == selectedHerb,
      );
      expect(herbs.unitWeightLt, 0.1);
      expect(herbs.perAttemptQuantity, 1);
      expect(herbs.quantity, load.attempts);
      expect(herbs.loadLt, closeTo(load.attempts * 0.1, 0.000001));
    }
  });
}
