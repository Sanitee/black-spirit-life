import 'package:flutter/material.dart';

import '../../domain/models/catalog_models.dart';
import '../../domain/opportunities/opportunity_recipe_routes.dart';
import '../../visual/visual.dart';
import '../shared/recipe_switch_controls.dart';

/// Independent route and batch axes, backed by complete recorded formulas.
class OpportunityRecipeControls extends StatelessWidget {
  const OpportunityRecipeControls({
    required this.routes,
    required this.recipe,
    required this.variantId,
    required this.onSelected,
    super.key,
  });

  final List<OpportunityRecipeRoute> routes;
  final Recipe recipe;
  final String? variantId;
  final ValueChanged<OpportunityRecipeFormula> onSelected;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final selectedIndex = routes.indexWhere(
      (r) => r.contains(recipe, variantId),
    );
    final currentRoute = selectedIndex < 0 ? null : routes[selectedIndex];
    final batch =
        recipe.variantById(variantId)?.batchMultiplier ??
        recipe.defaultVariant?.batchMultiplier ??
        1;
    final batches = currentRoute?.formulas.toList()
      ?..sort((a, b) => a.batchMultiplier.compareTo(b.batchMultiplier));
    final formula = recipe.resolveVariant(variantId);
    final method = formula.method?.trim();
    final methodLabel = method?.isNotEmpty == true
        ? method!
        : switch (formula.type) {
            'alchemy' => 'Alchemy',
            'cooking' => 'Cooking',
            _ => 'Processing',
          };
    final recipeButtons = routes.length < 2
        ? null
        : RecipeSwitchAxis(
            label: 'Recipe',
            child: RecipeSwitchGroup(
              children: [
                for (var index = 0; index < routes.length; index++)
                  RecipeSwitchChoice(
                    key: ValueKey('opportunity-recipe-route:$index'),
                    label: opportunityRecipeLetter(index),
                    semanticLabel:
                        'Recipe ${opportunityRecipeLetter(index)} for ${recipe.name}',
                    selected: index == selectedIndex,
                    onPressed: () =>
                        onSelected(routes[index].selectBatch(batch)),
                  ),
              ],
            ),
          );
    final batchButtons = batches == null || batches.length < 2
        ? null
        : RecipeSwitchAxis(
            label: 'Batch',
            child: RecipeSwitchGroup(
              children: [
                for (final formula in batches)
                  RecipeSwitchChoice(
                    key: ValueKey(
                      'opportunity-recipe-batch:${formula.batchMultiplier}',
                    ),
                    label: '${formula.batchMultiplier}×',
                    semanticLabel:
                        '${formula.batchMultiplier} times batch for ${recipe.name}',
                    selected: batch == formula.batchMultiplier,
                    onPressed: () => onSelected(formula),
                  ),
              ],
            ),
          );
    return Column(
      key: const ValueKey('opportunity-recipe-controls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recipeButtons != null || batchButtons != null) ...[
          RecipeSwitchAxes(children: [?recipeButtons, ?batchButtons]),
          const SizedBox(height: 12),
        ],
        Text(
          methodLabel,
          key: const ValueKey('opportunity-recipe-method'),
          style: spec.typography.meta,
        ),
        const SizedBox(height: 20),
        Divider(height: 1, color: spec.palette.trim.withAlpha(120)),
        const SizedBox(height: 16),
      ],
    );
  }
}
