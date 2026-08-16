import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/catalog_models.dart';
import '../../visual/visual.dart';

/// Compact, theme-aware selector for complete recipe formulas.
///
/// Recipe routes and supported batch sizes are presented as independent axes,
/// but callers still persist one complete [RecipeVariant.id]. No ingredient
/// formula is ever synthesized by multiplying another formula.
class RecipeVariantSelector extends StatelessWidget {
  const RecipeVariantSelector({
    required this.recipe,
    required this.selectedVariantId,
    required this.onSelected,
    this.compact = false,
    this.allowedVariantIds,
    this.showSingleAllowedIdentity = false,
    this.keyNamespace,
    this.axisSpacing,
    super.key,
  });

  final Recipe recipe;
  final String? selectedVariantId;
  final ValueChanged<String>? onSelected;
  final bool compact;

  /// Optional extra separation between the Recipe and Batch groups.
  final double? axisSpacing;

  /// Limits the selector to recorded formulas relevant to the calling surface.
  ///
  /// Route letters still come from the complete recipe, so filtering out
  /// recipe A never relabels recipe B as A.
  final Set<String>? allowedVariantIds;

  /// Keeps a lone filtered formula identifiable as its original recipe route
  /// and batch instead of leaving an otherwise ambiguous ingredient list.
  final bool showSingleAllowedIdentity;

  /// Keeps action-contract keys unique when more than one selector for the
  /// same recipe is mounted in layered UI.
  final String? keyNamespace;

  static Key choiceKey(
    String recipeName,
    String variantId, {
    String? keyNamespace,
  }) => routeChoiceKey(recipeName, variantId, keyNamespace: keyNamespace);

  static Key routeChoiceKey(
    String recipeName,
    String routeId, {
    String? keyNamespace,
  }) => ValueKey<String>(
    '${_keyPrefix(keyNamespace)}recipe-variant:$recipeName:$routeId',
  );

  static Key batchChoiceKey(
    String recipeName,
    int batchMultiplier, {
    String? keyNamespace,
  }) => ValueKey<String>(
    '${_keyPrefix(keyNamespace)}recipe-batch:$recipeName:$batchMultiplier',
  );

  @override
  Widget build(BuildContext context) {
    final allowed = allowedVariantIds
        ?.map(_foldId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final availableVariants = recipe.variants
        .where(
          (variant) => allowed == null || allowed.contains(_foldId(variant.id)),
        )
        .toList(growable: false);
    if (availableVariants.isEmpty ||
        (availableVariants.length < 2 && !showSingleAllowedIdentity)) {
      return const SizedBox.shrink();
    }
    final requested = recipe.variantById(selectedVariantId);
    final defaultVariant = recipe.defaultVariant;
    final selected = requested != null && availableVariants.contains(requested)
        ? requested
        : defaultVariant != null && availableVariants.contains(defaultVariant)
        ? defaultVariant
        : availableVariants.first;
    final allRoutes = recipe.variantRoutes;
    final routes = allRoutes
        .where((route) => route.variants.any(availableVariants.contains))
        .toList(growable: false);
    final batches =
        availableVariants
            .map((variant) => variant.batchMultiplier)
            .toSet()
            .toList()
          ..sort();

    RecipeVariant? routeSelection(RecipeVariantRoute route) {
      final variants = route.variants
          .where(availableVariants.contains)
          .toList(growable: false);
      for (final variant in variants) {
        if (variant.batchMultiplier == selected.batchMultiplier) return variant;
      }
      for (final variant in variants) {
        if (variant.batchMultiplier == 1) return variant;
      }
      if (variants.isEmpty) return null;
      return variants.reduce(
        (current, candidate) =>
            candidate.batchMultiplier < current.batchMultiplier
            ? candidate
            : current,
      );
    }

    RecipeVariant? batchSelection(int batchMultiplier) {
      final route = recipe.variantRouteById(selected.routeId);
      if (route == null) return null;
      for (final variant in route.variants) {
        if (availableVariants.contains(variant) &&
            variant.batchMultiplier == batchMultiplier) {
          return variant;
        }
      }
      return null;
    }

    String routeLabel(RecipeVariantRoute route) {
      final originalIndex = allRoutes.indexWhere(
        (candidate) => _sameId(candidate.id, route.id),
      );
      return '${_variantLetter(originalIndex)} - ${route.label}';
    }

    final routeSelectWidth = AppSelect.readableWidthFor<RecipeVariantRoute>(
      context,
      items: routes,
      labelFor: routeLabel,
      minimumWidth: compact ? 152 : 180,
      maximumWidth: MediaQuery.sizeOf(context).width - 32,
    );

    final axes = <Widget>[
      if (routes.length > 1 ||
          (showSingleAllowedIdentity && recipe.hasRecipeRouteChoices))
        _VariantAxis(
          label: 'RECIPE',
          compact: compact,
          child: routes.length <= 5
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var index = 0; index < routes.length; index += 1) ...[
                      if (index > 0) SizedBox(width: compact ? 3 : 4),
                      _RouteSquare(
                        key: routeChoiceKey(
                          recipe.name,
                          routes[index].id,
                          keyNamespace: keyNamespace,
                        ),
                        letter: _variantLetter(
                          allRoutes.indexWhere(
                            (route) => _sameId(route.id, routes[index].id),
                          ),
                        ),
                        recipeName: recipe.name,
                        route: routes[index],
                        targetVariant: routeSelection(routes[index])!,
                        selected: _sameId(selected.routeId, routes[index].id),
                        compact: compact,
                        onPressed: onSelected == null
                            ? null
                            : () {
                                final target = routeSelection(routes[index]);
                                if (target != null) onSelected!(target.id);
                              },
                      ),
                    ],
                  ],
                )
              : SizedBox(
                  width: routeSelectWidth,
                  height: compact ? 28 : 30,
                  child: AppSelect<String>(
                    value: selected.routeId,
                    items: <String>[for (final route in routes) route.id],
                    labelFor: (routeId) {
                      final index = routes.indexWhere(
                        (route) => _sameId(route.id, routeId),
                      );
                      final route = index < 0 ? routes.first : routes[index];
                      return routeLabel(route);
                    },
                    semanticLabel: 'Recipe route for ${recipe.name}',
                    onChanged: onSelected == null
                        ? null
                        : (routeId) {
                            if (routeId == null) return;
                            final route = routes.firstWhere(
                              (candidate) => _sameId(candidate.id, routeId),
                            );
                            final target = routeSelection(route);
                            if (target != null) onSelected!(target.id);
                          },
                  ),
                ),
        ),
      if (batches.length > 1 ||
          (showSingleAllowedIdentity && recipe.hasRecipeBatchChoices))
        _VariantAxis(
          label: 'BATCH',
          compact: compact,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < batches.length; index += 1) ...[
                if (index > 0) SizedBox(width: compact ? 3 : 4),
                _BatchSquare(
                  key: batchChoiceKey(
                    recipe.name,
                    batches[index],
                    keyNamespace: keyNamespace,
                  ),
                  recipeName: recipe.name,
                  route: recipe.variantRouteById(selected.routeId)!,
                  routeLetter: _variantLetter(
                    allRoutes.indexWhere(
                      (route) => _sameId(route.id, selected.routeId),
                    ),
                  ),
                  batchMultiplier: batches[index],
                  targetVariant: batchSelection(batches[index]),
                  selected: selected.batchMultiplier == batches[index],
                  compact: compact,
                  filteredToAllowedVariants: allowed != null,
                  onSelected: onSelected,
                ),
              ],
            ],
          ),
        ),
    ];
    if (axes.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Recipe and batch variation for ${recipe.name}',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: axisSpacing ?? (compact ? 10 : 14),
        runSpacing: compact ? 6 : 8,
        children: axes,
      ),
    );
  }
}

class _VariantAxis extends StatelessWidget {
  const _VariantAxis({
    required this.label,
    required this.compact,
    required this.child,
  });

  final String label;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: spec.typography.meta.copyWith(
            color: spec.palette.textMuted,
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .45,
            height: 1,
          ),
        ),
        SizedBox(width: compact ? 5 : 7),
        child,
      ],
    );
  }
}

class _RouteSquare extends StatelessWidget {
  const _RouteSquare({
    required this.letter,
    required this.recipeName,
    required this.route,
    required this.targetVariant,
    required this.selected,
    required this.compact,
    required this.onPressed,
    super.key,
  });

  final String letter;
  final String recipeName;
  final RecipeVariantRoute route;
  final RecipeVariant targetVariant;
  final bool selected;
  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 26.0 : 28.0;
    return Tooltip(
      message:
          '$letter - ${route.label}\n'
          '${_batchSummary(targetVariant)}\n'
          '${_formulaSummary(targetVariant.ingredients)}',
      child: SizedBox.square(
        dimension: size,
        child: AppButton(
          role: AppButtonRole.optionPill,
          selected: selected,
          minimumSize: Size.square(size),
          padding: EdgeInsets.zero,
          semanticLabel: 'Use recipe $letter for $recipeName: ${route.label}',
          onPressed: onPressed,
          child: Text(
            letter,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchSquare extends StatelessWidget {
  const _BatchSquare({
    required this.recipeName,
    required this.route,
    required this.routeLetter,
    required this.batchMultiplier,
    required this.targetVariant,
    required this.selected,
    required this.compact,
    required this.filteredToAllowedVariants,
    required this.onSelected,
    super.key,
  });

  final String recipeName;
  final RecipeVariantRoute route;
  final String routeLetter;
  final int batchMultiplier;
  final RecipeVariant? targetVariant;
  final bool selected;
  final bool compact;
  final bool filteredToAllowedVariants;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final target = targetVariant;
    final height = compact ? 26.0 : 28.0;
    final width = switch (batchMultiplier) {
      >= 100 => compact ? 41.0 : 45.0,
      >= 10 => compact ? 35.0 : 39.0,
      _ => compact ? 29.0 : 32.0,
    };
    final enabled = target != null && onSelected != null;
    final tooltip = target == null
        ? filteredToAllowedVariants
              ? 'No matching $batchMultiplier× formula is available for '
                    'recipe $routeLetter - ${route.label} in this Used In '
                    'result.'
              : 'No recorded $batchMultiplier× formula is available for '
                    'recipe $routeLetter - ${route.label}.'
        : '$batchMultiplier× batch - ${route.label}\n'
              '${_outputSummary(target)}\n'
              '${_formulaSummary(target.ingredients)}\n'
              'Uses the recorded in-game formula; the requested target '
              'amount is unchanged.';
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: height,
        child: AppButton(
          role: AppButtonRole.optionPill,
          selected: selected,
          minimumSize: Size(width, height),
          padding: EdgeInsets.zero,
          semanticLabel: target == null
              ? '$batchMultiplier times batch is unavailable for recipe '
                    '$routeLetter of $recipeName'
              : 'Use recorded $batchMultiplier times batch formula for recipe '
                    '$routeLetter of $recipeName',
          onPressed: enabled ? () => onSelected!(target.id) : null,
          child: Text(
            '$batchMultiplier×',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

String _formulaSummary(Iterable<Ingredient> ingredients) => ingredients
    .map(
      (ingredient) =>
          '${formatQuantity(ingredient.quantity)} × ${ingredient.name}',
    )
    .join(' + ');

String _batchSummary(RecipeVariant variant) =>
    '${variant.batchMultiplier}× batch - ${_outputSummary(variant)}';

String _outputSummary(RecipeVariant variant) {
  final minimum = variant.outputMinimum;
  final maximum = variant.outputMaximum;
  if (minimum == null) {
    return 'Makes ${formatQuantity(variant.baseOutput)}';
  }
  if (maximum == null || maximum == minimum) {
    return 'Makes ${formatQuantity(minimum)}';
  }
  return 'Makes ${formatQuantity(minimum)}–${formatQuantity(maximum)}';
}

String _variantLetter(int index) {
  if (index < 0) return 'A';
  if (index < 26) return String.fromCharCode(65 + index);
  return '${index + 1}';
}

bool _sameId(String? left, String right) =>
    left?.trim().toLowerCase() == right.trim().toLowerCase();

String _foldId(String value) => value.trim().toLowerCase();

String _keyPrefix(String? namespace) {
  final value = namespace?.trim() ?? '';
  return value.isEmpty ? '' : '$value:';
}
