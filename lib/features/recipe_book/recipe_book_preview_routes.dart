import '../../domain/models/craft_mode.dart';
import 'recipe_book_item_info.dart';

/// A real recipe family, independent of which catalogue also lists it.
class RecipeBookPreviewRoute {
  const RecipeBookPreviewRoute({
    required this.mode,
    required this.label,
    required this.equivalentModes,
    required this.formulas,
  });

  final CraftMode mode;
  final String label;
  final Set<CraftMode> equivalentModes;
  final List<RecipeBookFormula> formulas;
}

List<RecipeBookPreviewRoute> recipeBookPreviewRoutes(
  Iterable<RecipeBookFormula> formulas,
) {
  final grouped = <String, List<RecipeBookFormula>>{};
  final modes = <String, Set<CraftMode>>{};
  // The original Alchemy/Cooking catalogue retains its ingredient and quality
  // controls when the Processing catalogue carries an identical formula.
  for (final mode in CraftMode.values) {
    final family = formulas.where((formula) => formula.mode == mode).toList();
    if (family.isEmpty) continue;
    final identities =
        family.map(recipeBookPreviewFormulaIdentity).toSet().toList()..sort();
    final key = identities.join('\n');
    grouped.putIfAbsent(key, () => family);
    modes.putIfAbsent(key, () => <CraftMode>{}).add(mode);
  }
  final result = <RecipeBookPreviewRoute>[];
  for (final entry in grouped.entries) {
    final methods = entry.value
        .map((formula) => recipeBookPreviewMethodLabel(formula.method))
        .toSet();
    final label = methods.length == 1
        ? methods.single
        : entry.value.first.mode!.label;
    result.add(
      RecipeBookPreviewRoute(
        mode: entry.value.first.mode!,
        label: label,
        equivalentModes: Set.unmodifiable(modes[entry.key]!),
        formulas: List.unmodifiable(entry.value),
      ),
    );
  }
  return [
    for (final route in result)
      if (result.where((candidate) => candidate.label == route.label).length ==
          1)
        route
      else
        RecipeBookPreviewRoute(
          mode: route.mode,
          label:
              '${route.label} · Recipe ${result.where((candidate) => candidate.label == route.label).toList().indexOf(route) + 1}',
          equivalentModes: route.equivalentModes,
          formulas: route.formulas,
        ),
  ];
}

String recipeBookPreviewMethodLabel(String method) =>
    switch (method.trim().toLowerCase()) {
      'alchemy' => 'Residence Alchemy',
      'cooking' => 'Residence Cooking',
      _ => method.trim(),
    };

/// Only identical full formulas collapse: retain different batches, outputs,
/// ingredient quantities, substitutes and exchange ratios as genuine choices.
String recipeBookPreviewFormulaIdentity(RecipeBookFormula formula) {
  String fold(String value) => value.trim().toLowerCase();
  final ingredients = formula.ingredients.map((ingredient) {
    final options = <String>{
      ingredient.name,
      ...ingredient.options,
      ...ingredient.substituteRatios.keys,
    };
    final alternatives =
        options
            .map((name) {
              final ratio =
                  ingredient.substituteRatios.entries
                      .where((entry) => fold(entry.key) == fold(name))
                      .map((entry) => entry.value)
                      .firstOrNull ??
                  1.0;
              return '${fold(name)}:$ratio';
            })
            .toSet()
            .toList()
          ..sort();
    return '${fold(ingredient.name)}:${ingredient.quantity}:${alternatives.join(',')}';
  }).toList()..sort();
  return [
    fold(recipeBookPreviewMethodLabel(formula.method)),
    '${formula.batchMultiplier}',
    '${formula.outputMinimum ?? formula.baseOutput}',
    '${formula.outputMaximum ?? formula.outputMinimum ?? formula.baseOutput}',
    '${formula.outputEstimated}',
    ...ingredients,
  ].join('|');
}
