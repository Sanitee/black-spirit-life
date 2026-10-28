import 'package:flutter/foundation.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/planner/planner_models.dart' as planning;
import '../../domain/state/planner_state.dart';

/// Read-only presentation of work covered in the current recipe chain.
///
/// The normal plan deliberately omits work supplied by stock or an already
/// completed parent. A zero-stock projection recovers those upstream crafts,
/// without manufacturing completion marks, inventory or transaction history.
final class PlannerCompletedProjection {
  ModeFeatureController? _controller;
  ModeState? _source;
  Map<String, Recipe>? _recipes;
  planning.PlanResult? _plan;
  planning.PlanResult? _fullPlan;
  List<String> _names = const [];

  List<String> namesFor(ModeFeatureController controller) {
    final source = controller.state.value;
    final recipes = controller.recipes;
    final plan = controller.plan.value;
    if (identical(controller, _controller) &&
        identical(plan, _plan) &&
        identical(recipes, _recipes)) {
      return _names;
    }

    final before = _source;
    final sameChain =
        identical(controller, _controller) &&
        identical(recipes, _recipes) &&
        before != null &&
        before.target == source.target &&
        before.want == source.want &&
        mapEquals(before.substituteChoices, source.substituteChoices) &&
        mapEquals(before.ingredientGrades, source.ingredientGrades) &&
        mapEquals(before.recipeVariantChoices, source.recipeVariantChoices);
    final variants = Map<String, String>.of(source.recipeVariantChoices);
    final substitutes = Map<String, String>.of(source.substituteChoices);
    final grades = Map<String, String>.of(source.ingredientGrades);

    void pinResolvedChoices(planning.PlanResult reference) {
      final activeNames = {
        for (final step in reference.steps) _fold(step.name),
      };
      for (final entry in reference.routeSelections.entries) {
        final selected = entry.value.selectedVariantId;
        if (selected != null && activeNames.contains(_fold(entry.key))) {
          _putFolded(variants, entry.key, selected);
        }
      }
      for (final ingredient in reference.steps.expand(
        (step) => step.ingredients,
      )) {
        _putFolded(
          substitutes,
          'recipe:${ingredient.parentName}:${ingredient.substituteGroup}',
          ingredient.baseName,
        );
        _putFolded(
          grades,
          'recipe:${ingredient.parentName}:${ingredient.original}',
          ingredient.grade,
        );
      }
    }

    // Keep the selected branch after its output is consumed by a later craft.
    // New active choices win; these temporary pins never enter saved state.
    if (sameChain && _fullPlan != null) pinResolvedChoices(_fullPlan!);
    pinResolvedChoices(plan);
    final full = controller.owner.assembly.engine.buildPlan(
      mode: controller.mode,
      recipes: recipes,
      state: planning.PlannerState(
        target: source.target,
        want: source.want,
        alchemyMastery: source.alchemyMastery,
        cookingMastery: source.cookingMastery,
        processingMastery: source.processingMastery,
        useMassProcessing: source.useMassProcessing,
        substituteChoices: substitutes,
        ingredientGrades: grades,
        recipeVariantChoices: variants,
        marketPrices: source.market.prices,
        marketStock: source.market.stock,
        marketPreorderPrices: source.market.preorderPrices,
      ),
      rules: controller.owner.plannerRules,
    );
    final remaining = {for (final step in plan.steps) _fold(step.name)};
    final seen = <String>{};
    _names = List.unmodifiable([
      for (final step in full.steps)
        if (!remaining.contains(_fold(step.name)) && seen.add(_fold(step.name)))
          step.name,
    ]);
    _controller = controller;
    _source = source;
    _recipes = recipes;
    _plan = plan;
    _fullPlan = full;
    return _names;
  }
}

void _putFolded(Map<String, String> values, String key, String value) {
  values.removeWhere((existing, _) => _fold(existing) == _fold(key));
  values[key] = value;
}

String _fold(String value) => value.trim().toLowerCase();
