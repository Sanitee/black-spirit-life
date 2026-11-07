import 'dart:math' as math;

import '../planner/planner_choice_market.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_usage.dart';

/// Availability for this exact reverse-recipe route. Do not resolve it through
/// the Planner's current substitutions: that can change the displayed formula.
List<RecipeBookIngredientChoice> recipeBookUsedInIngredients({
  required RecipeBookController controller,
  required RecipeBookUseRoute route,
}) => [
  for (final ingredient in route.ingredients)
    (() {
      RecipeBookUseMatch? match;
      for (final candidate in route.matches) {
        if (_fold(candidate.ingredientName) == _fold(ingredient.name)) {
          match = candidate;
          break;
        }
      }
      final name = match?.sourceName ?? ingredient.name;
      final identity = choiceMarketIdentity(
        controller.modeController,
        name,
        acrossModes: true,
      );
      var owned = 0.0;
      for (final entry
          in controller.modeController.state.value.inventory.entries) {
        if (_fold(entry.key) == _fold(name)) {
          owned = entry.value;
          break;
        }
      }
      return RecipeBookIngredientChoice(
        ingredient: ingredient,
        name: name,
        baseName: ingredient.name,
        grade: match?.grade ?? 'normal',
        quantity: match?.sourceQuantity ?? ingredient.quantity,
        owned: owned.isFinite ? math.max(0, owned) : 0,
        npc: identity.npc,
        marketable: identity.marketId != null,
        stock: null,
        preorders: null,
      );
    })(),
];

String _fold(String value) => value.trim().toLowerCase();
