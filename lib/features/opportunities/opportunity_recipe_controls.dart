import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/opportunities/opportunity_recipe_routes.dart';
import '../../visual/visual.dart';
import 'opportunities_visuals.dart';

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
        : _group(context, [
            for (var index = 0; index < routes.length; index++)
              _choice(
                context,
                key: ValueKey('opportunity-recipe-route:$index'),
                label: 'Recipe ${opportunityRecipeLetter(index)}',
                selected: index == selectedIndex,
                tooltip: _formulaDescription(routes[index].selectBatch(batch)),
                onPressed: () => onSelected(routes[index].selectBatch(batch)),
              ),
          ]);
    final batchButtons = batches == null || batches.length < 2
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Batch', style: spec.typography.meta),
              const SizedBox(width: 10),
              Flexible(
                child: _group(context, [
                  for (final formula in batches)
                    _choice(
                      context,
                      key: ValueKey(
                        'opportunity-recipe-batch:${formula.batchMultiplier}',
                      ),
                      label: '${formula.batchMultiplier}×',
                      selected: batch == formula.batchMultiplier,
                      tooltip: _formulaDescription(formula),
                      onPressed: () => onSelected(formula),
                    ),
                ]),
              ),
            ],
          );
    return Column(
      key: const ValueKey('opportunity-recipe-controls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recipeButtons != null || batchButtons != null) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (recipeButtons != null &&
                  batchButtons != null &&
                  constraints.maxWidth >= 560 * scale &&
                  routes.length <= 3) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: recipeButtons),
                    const SizedBox(width: 24),
                    Flexible(child: batchButtons),
                  ],
                );
              }
              return Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [?recipeButtons, ?batchButtons],
              );
            },
          ),
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

  Widget _group(BuildContext context, List<Widget> buttons) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.visualTheme.palette.surfaceInset,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Wrap(spacing: 3, runSpacing: 3, children: buttons),
    ),
  );

  Widget _choice(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required String tooltip,
    required VoidCallback onPressed,
  }) => OpportunityButton(
    key: key,
    compact: true,
    role: AppButtonRole.infoChip,
    minimumSize: const Size(44, 37),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    selected: selected,
    tooltip: tooltip,
    semanticLabel: '$label for ${recipe.name}',
    onPressed: onPressed,
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
    ),
  );

  String _formulaDescription(OpportunityRecipeFormula choice) {
    final formula = choice.resolved;
    return [
      formula.method ?? formula.type,
      for (final input in formula.ingredients)
        '${input.name} ×${formatQuantity(input.quantity)}',
    ].join('\n');
  }
}
