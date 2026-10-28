import 'dart:convert';

import '../models/catalog_models.dart';

/// A recorded formula and the source recipe needed to inspect or plan it.
/// Keeping the source identity avoids inventing cross-mode variant IDs.
final class OpportunityRecipeFormula {
  const OpportunityRecipeFormula(this.recipe, [this.variant]);

  final Recipe recipe;
  final RecipeVariant? variant;
  String? get variantId => variant?.id;
  int get batchMultiplier => variant?.batchMultiplier ?? 1;
  Recipe get resolved => recipe.resolveVariant(variantId);

  String get identity => _formulaIdentity(resolved, batchMultiplier);
}

/// A complete recipe route, with only its recorded batch alternatives.
final class OpportunityRecipeRoute {
  OpportunityRecipeRoute(Iterable<OpportunityRecipeFormula> formulas)
    : formulas = List.unmodifiable(formulas);

  final List<OpportunityRecipeFormula> formulas;

  OpportunityRecipeFormula? forBatch(int batch) =>
      formulas.where((formula) => formula.batchMultiplier == batch).firstOrNull;

  OpportunityRecipeFormula selectBatch(int preferredBatch) =>
      forBatch(preferredBatch) ??
      forBatch(1) ??
      formulas.reduce((a, b) => a.batchMultiplier < b.batchMultiplier ? a : b);

  bool contains(Recipe recipe, String? variantId) {
    final resolved = recipe.resolveVariant(variantId);
    final batch =
        recipe.variantById(variantId)?.batchMultiplier ??
        recipe.defaultVariant?.batchMultiplier ??
        1;
    final identity = _formulaIdentity(resolved, batch);
    return formulas.any((formula) => formula.identity == identity);
  }
}

/// Collapses duplicate catalogue copies, never different ingredient formulas,
/// outputs, quality rules, or batches. Ordering comes from the source catalogue.
List<OpportunityRecipeRoute> opportunityRecipeRoutes(Iterable<Recipe> recipes) {
  final routes = <OpportunityRecipeRoute>[];
  final seen = <String>{};
  for (final recipe in recipes.where((recipe) => recipe.isCraftable)) {
    final candidates = recipe.variants.isEmpty
        ? [
            OpportunityRecipeRoute([OpportunityRecipeFormula(recipe)]),
          ]
        : [
            for (final route in recipe.variantRoutes)
              OpportunityRecipeRoute([
                for (final variant in route.variants)
                  OpportunityRecipeFormula(recipe, variant),
              ]),
          ];
    for (final route in candidates) {
      final identities = route.formulas.map((f) => f.identity).toList()..sort();
      if (seen.add(jsonEncode(identities))) routes.add(route);
    }
  }
  return List.unmodifiable(routes);
}

String opportunityRecipeLetter(int index) {
  var result = '';
  for (var value = index + 1; value > 0; value = (value - 1) ~/ 26) {
    result = String.fromCharCode(65 + (value - 1) % 26) + result;
  }
  return result;
}

String _formulaIdentity(Recipe recipe, int batch) {
  String fold(String? text) => text?.trim().toLowerCase() ?? '';
  return jsonEncode([
    fold(recipe.name),
    fold(recipe.type),
    fold(recipe.method),
    batch,
    recipe.baseOutput,
    recipe.outputMinimum,
    recipe.outputMaximum,
    for (final ingredient in recipe.ingredients)
      [
        fold(ingredient.name),
        ingredient.quantity,
        fold(ingredient.substituteGroup),
        ingredient.options.map(fold).toList(),
        for (final key in ingredient.substituteRatios.keys.toList()..sort())
          [fold(key), ingredient.substituteRatios[key]],
      ],
  ]);
}
