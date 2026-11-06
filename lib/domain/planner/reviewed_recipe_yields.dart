import '../models/catalog_models.dart';

// The official PC artifact guide describes one result plus a rare extra, not
// ordinary 1–4 Alchemy production. Count the base result, never an invented
// bonus probability. Exact identities and complete inputs guard custom recipes.
const reviewedLightstoneYieldNote =
    'Standard recipe counts 1 per craft; random extras are not included.';

const _lightstoneRecipes = <String, (String, String, String)>{
  '766001': ('Fire', 'Powder of Flame', 'Clear Liquid Reagent'),
  '766011': ('Earth', 'Powder of Earth', 'Pure Powder Reagent'),
  '766021': ('Wind', 'Powder of Rifts', 'Clear Liquid Reagent'),
  '766031': ('Flora', 'Powder of Time', 'Pure Powder Reagent'),
};

bool usesReviewedLightstoneBaseOutput(Recipe recipe) {
  final row = _lightstoneRecipes[recipe.marketId];
  if (row == null ||
      !recipe.isCraftable ||
      recipe.name != 'Purified Lightstone of ${row.$1}' ||
      recipe.type != 'alchemy' ||
      (recipe.method != null && recipe.method != 'Alchemy') ||
      recipe.baseOutput != 1 ||
      recipe.outputMinimum != 1 ||
      recipe.outputMaximum != 2 ||
      recipe.ingredients.length != 5) {
    return false;
  }
  final exact = <String, double>{
    'Imperfect Lightstone of ${row.$1}': 1,
    'Black Stone': 10,
    row.$2: 50,
    row.$3: 50,
  };
  const catalysts = {'Black Gem Fragment', 'Magical Lightstone Crystal'};
  final seen = <String>{};
  var catalystCount = 0;
  for (final input in recipe.ingredients) {
    if (!seen.add(input.name)) return false;
    if (catalysts.contains(input.name)) {
      catalystCount++;
      if (input.quantity != 10 ||
          input.options.any((name) => !catalysts.contains(name)) ||
          input.substituteRatios.entries.any(
            (entry) => !catalysts.contains(entry.key) || entry.value != 1,
          )) {
        return false;
      }
    } else if (exact[input.name] != input.quantity ||
        input.options.any((name) => name != input.name) ||
        input.substituteRatios.entries.any(
          (entry) => entry.key != input.name || entry.value != 1,
        )) {
      return false;
    }
  }
  return catalystCount == 1 && seen.containsAll(exact.keys);
}

String? reviewedRecipeYieldNote(Recipe recipe) =>
    usesReviewedLightstoneBaseOutput(recipe)
    ? reviewedLightstoneYieldNote
    : null;
