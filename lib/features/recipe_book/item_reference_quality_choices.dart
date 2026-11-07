part of 'recipe_book_item_info_view.dart';

// Use the same quality conversions and whole-item rounding as the planner.
// Processing only accepts its explicitly recorded alternatives, never a
// residence-Cooking/Alchemy quality inference.
List<List<_FormulaAlternative>> _qualityChoiceRows(
  RecipeBookController book,
  RecipeBookFormula formula,
  Ingredient ingredient,
  CraftMode fallbackMode,
) {
  if (formula.type.toLowerCase() == 'processing') return const [];
  final mode = formula.mode ?? fallbackMode;
  final recipes = book.modeController.owner.modes[mode]!.recipes;
  final rows = <List<_FormulaAlternative>>[];
  final bases = [
    _FormulaAlternative(name: ingredient.name, quantity: ingredient.quantity),
    ..._formulaAlternatives(ingredient, recipes: recipes),
  ];
  final seen = <String>{};
  var hasQuality = false;
  for (final base in bases) {
    if (!seen.add(base.name.toLowerCase())) continue;
    final row = <_FormulaAlternative>[base];
    for (final quality in ingredientQualityAlternatives(
      rules: book.modeController.owner.plannerRules,
      ingredientName: base.name,
    )) {
      final id = book.catalogRepository.bundledMarketId(quality.name);
      // Do not manufacture a grade that has no actual reference identity.
      if (id == null || isTemporarilyArchivedItem(quality.name, itemId: id)) {
        continue;
      }
      if (!seen.add(quality.name.toLowerCase())) continue;
      final explicit = bases
          .where((b) => b.name.toLowerCase() == quality.name.toLowerCase())
          .firstOrNull;
      row.add(
        explicit ??
            _FormulaAlternative(
              name: quality.name,
              quantity: quality.requiredQuantityFor(base.quantity),
            ),
      );
      hasQuality = true;
    }
    rows.add(row);
  }
  return hasQuality ? rows : const [];
}

List<String> _referenceFormulaNames(
  RecipeBookController book,
  RecipeBookFormula formula,
  CraftMode mode,
) => <String>{
  for (final ingredient in formula.ingredients) ...[
    ingredient.name,
    for (final choice in _formulaAlternatives(
      ingredient,
      recipes: book.modeController.owner.modes[formula.mode ?? mode]!.recipes,
    ))
      choice.name,
    for (final row in _qualityChoiceRows(book, formula, ingredient, mode))
      for (final choice in row) choice.name,
  ],
}.toList();
