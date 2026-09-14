import '../catalog/temporarily_archived_items.dart';
import '../models/catalog_models.dart';
import 'planner_models.dart';
import 'source_resolution.dart';

/// Keeps the user's recorded batch size while returning the route to Auto.
String autoRecipeRouteChoice(int batchMultiplier) =>
    '__auto_batch_${batchMultiplier < 1 ? 1 : batchMultiplier}';

/// Compares only an interchangeable leaf ingredient in otherwise identical,
/// deterministic Processing formulas. No new formulas are synthesized, and
/// arbitrary crafting, salvage, and probabilistic routes are never optimized.
RecipeRouteSelection resolveRecipeRoute({
  required Recipe recipe,
  required Map<String, Recipe> recipes,
  required PlannerState state,
  required PlannerRules rules,
  double? requestedOutput,
}) {
  final saved = _lookup(state.recipeVariantChoices, recipe.name);
  final savedVariant = recipe.variantById(saved);
  final availableVariants = recipe.variants
      .where((variant) => !_hasArchivedOnlyInput(variant, recipes, rules))
      .toList(growable: false);
  final manual = availableVariants
      .where((variant) => variant.id == savedVariant?.id)
      .firstOrNull;
  final autoMatch = RegExp(
    r'^__auto_batch_([1-9][0-9]*)$',
  ).firstMatch(saved ?? '');
  final batch =
      savedVariant?.batchMultiplier ??
      (autoMatch == null ? null : int.tryParse(autoMatch.group(1)!)) ??
      recipe.defaultVariant?.batchMultiplier ??
      1;
  final reference =
      availableVariants
          .where(
            (variant) =>
                variant.routeId == recipe.defaultVariant?.routeId &&
                variant.batchMultiplier == batch,
          )
          .firstOrNull ??
      availableVariants
          .where((variant) => variant.batchMultiplier == batch)
          .firstOrNull ??
      availableVariants
          .where((variant) => variant.id == recipe.defaultVariant?.id)
          .firstOrNull ??
      availableVariants.firstOrNull;
  final fallbackId = manual?.id ?? reference?.id;
  RecipeRouteSelection fallback() => RecipeRouteSelection(
    selectedVariantId: fallbackId,
    automaticVariantId: reference?.id,
    isAutomatic: manual == null,
    options: const <RecipeRouteOption>[],
  );
  if (!recipe.isCraftable ||
      reference == null ||
      !_fixedProcessing(reference)) {
    return fallback();
  }

  final base = _formula(reference);
  if (base == null) return fallback();
  final swaps = <(RecipeVariant, Ingredient)>[];
  String? exchangedBaseName;
  for (final candidate in availableVariants) {
    if (candidate.id == reference.id ||
        candidate.batchMultiplier != reference.batchMultiplier ||
        candidate.routeId == reference.routeId ||
        !_fixedProcessing(candidate) ||
        _fold(candidate.method ?? '') != _fold(reference.method ?? '') ||
        !_close(candidate.outputMinimum!, reference.outputMinimum!)) {
      continue;
    }
    final other = _formula(candidate);
    if (other == null) continue;
    final removed = base.keys
        .where((name) => !other.containsKey(name))
        .toList();
    final added = other.keys.where((name) => !base.containsKey(name)).toList();
    if (removed.length != 1 ||
        added.length != 1 ||
        (exchangedBaseName != null && exchangedBaseName != removed.single)) {
      continue;
    }
    final commonMatches = base.entries.every(
      (entry) =>
          !other.containsKey(entry.key) ||
          _close(
            entry.value.quantity / reference.outputMinimum!,
            other[entry.key]!.quantity / candidate.outputMinimum!,
          ),
    );
    final oldIngredient = base[removed.single]!;
    final newIngredient = other[added.single]!;
    if (!commonMatches ||
        !_leafAllowed(oldIngredient.name, recipes, rules) ||
        !_leafAllowed(newIngredient.name, recipes, rules)) {
      continue;
    }
    if (exchangedBaseName == null) {
      exchangedBaseName = removed.single;
      swaps.add((reference, oldIngredient));
    }
    swaps.add((candidate, newIngredient));
  }
  if (swaps.length < 2) return fallback();

  final options = swaps
      .map((entry) {
        final (variant, ingredient) = entry;
        final source = resolveSourceInfo(
          name: ingredient.name,
          recipe: _lookup(recipes, ingredient.name),
          rules: rules,
        );
        final npc = source.npcPrice.isFinite && source.npcPrice > 0;
        final marketable =
            (_lookup(recipes, ingredient.name)?.marketId?.trim().isNotEmpty ??
                false) ||
            (_lookup(rules.marketIds, ingredient.name)?.trim().isNotEmpty ??
                false);
        final rawPrice = npc
            ? source.npcPrice
            : marketable
            ? _lookup(state.marketPrices, ingredient.name) ??
                  _lookup(rules.fallbackMarketPrices, ingredient.name)
            : null;
        final price = rawPrice != null && rawPrice.isFinite && rawPrice > 0
            ? rawPrice
            : null;
        final output = variant.outputMinimum!;
        final requested = requestedOutput ?? output;
        final count = requested.isFinite && requested > 0
            ? (requested / output).ceilToDouble()
            : 0.0;
        final needed = ingredient.quantity * count;
        final inventory = state.ignoreIngredientInventory
            ? 0.0
            : _nonNegative(_lookup(state.inventory, ingredient.name) ?? 0);
        final owned = inventory < needed ? inventory : needed;
        final missing = needed - owned;
        final stock = _lookup(state.marketStock, ingredient.name);
        return RecipeRouteOption(
          variantId: variant.id,
          ingredientName: ingredient.name,
          ingredientQuantity: ingredient.quantity,
          outputPerCraft: output,
          batchMultiplier: variant.batchMultiplier,
          unitPrice: price,
          npcBuyable: npc,
          neededQuantity: needed,
          ownedQuantity: owned,
          missingQuantity: missing,
          purchaseCost: missing <= 0
              ? 0
              : price == null
              ? null
              : price * missing,
          stockKnown: npc || stock != null,
          availableStock: npc ? missing : _nonNegative(stock ?? 0),
        );
      })
      .toList(growable: false);
  if (!options.any((option) => option.npcBuyable)) return fallback();
  // A manual formula outside the eligible group keeps its existing behavior.
  if (manual != null &&
      !options.any((option) => option.variantId == manual.id)) {
    return fallback();
  }
  var best = options.first;
  for (final option in options.skip(1)) {
    if (_compare(option, best) < 0) best = option;
  }
  return RecipeRouteSelection(
    selectedVariantId: manual?.id ?? best.variantId,
    automaticVariantId: best.variantId,
    isAutomatic: manual == null,
    options: options,
  );
}

bool _hasArchivedOnlyInput(
  RecipeVariant variant,
  Map<String, Recipe> recipes,
  PlannerRules rules,
) => variant.ingredients.any(
  (ingredient) => <String>[ingredient.name, ...ingredient.options].every(
    (name) => isTemporarilyArchivedItem(
      name,
      itemId:
          _lookup(recipes, name)?.marketId ?? _lookup(rules.marketIds, name),
    ),
  ),
);

bool _fixedProcessing(RecipeVariant variant) =>
    _fold(variant.type) == 'processing' &&
    variant.outputMinimum != null &&
    variant.outputMaximum != null &&
    variant.outputMinimum!.isFinite &&
    variant.outputMinimum! > 0 &&
    _close(variant.outputMinimum!, variant.outputMaximum!);

Map<String, Ingredient>? _formula(RecipeVariant variant) {
  final result = <String, Ingredient>{};
  for (final ingredient in variant.ingredients) {
    final key = _fold(ingredient.name);
    if (key.isEmpty ||
        !ingredient.quantity.isFinite ||
        ingredient.quantity <= 0 ||
        ingredient.options.isNotEmpty ||
        ingredient.substituteRatios.isNotEmpty ||
        result.containsKey(key)) {
      return null;
    }
    result[key] = ingredient;
  }
  return result;
}

bool _leafAllowed(
  String name,
  Map<String, Recipe> recipes,
  PlannerRules rules,
) {
  final item = _lookup(recipes, name);
  return item != null &&
      !item.isCraftable &&
      !isTemporarilyArchivedItem(
        name,
        itemId: item.marketId ?? _lookup(rules.marketIds, name),
      ) &&
      !rules.legacyUnavailableItems.any((value) => _fold(value) == _fold(name));
}

int _availability(RecipeRouteOption option) => option.canCoverNeed
    ? 0
    : !option.stockKnown
    ? 1
    : option.availableStock > 0
    ? 2
    : 3;

int _compare(RecipeRouteOption left, RecipeRouteOption right) {
  final availability = _availability(left).compareTo(_availability(right));
  if (availability != 0) return availability;
  if (_availability(left) == 2) {
    final coverage = (right.availableStock / right.missingQuantity).compareTo(
      left.availableStock / left.missingQuantity,
    );
    if (coverage != 0) return coverage;
  }
  return (left.purchaseCost ?? double.infinity).compareTo(
    right.purchaseCost ?? double.infinity,
  );
}

T? _lookup<T>(Map<String, T> values, String name) {
  final direct = values[name];
  if (direct != null) return direct;
  final folded = _fold(name);
  for (final entry in values.entries) {
    if (_fold(entry.key) == folded) return entry.value;
  }
  return null;
}

double _nonNegative(double value) => value.isFinite && value > 0 ? value : 0;
bool _close(double left, double right) => (left - right).abs() <= 0.0000001;
String _fold(String value) => value.trim().toLowerCase();
