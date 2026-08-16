import '../models/catalog_models.dart';
import '../planner/planner_engine.dart';
import '../planner/planner_models.dart' as planning;
import '../planner/source_resolution.dart';
import '../state/planner_state.dart';
import 'market_calculations.dart';

enum RecipeIngredientPriceSource { vendor, market }

enum RecipeProfitabilityUnavailableReason {
  recipeNotCraftable,
  invalidOutputQuantity,
  invalidMarketNetRate,
  outputUnlisted,
  outputPriceUnavailable,
  invalidIngredientQuantity,
  ingredientUnlisted,
  ingredientPriceUnavailable,
  invalidIngredientCost,
}

final class RecipeIngredientCost {
  const RecipeIngredientCost({
    required this.originalName,
    required this.selectedName,
    required this.grade,
    required this.quantity,
    required this.unitPrice,
    required this.priceSource,
    required this.total,
  });

  final String originalName;
  final String selectedName;
  final String grade;
  final double quantity;
  final double unitPrice;
  final RecipeIngredientPriceSource priceSource;
  final double total;
}

final class RecipeProfitabilityQuote {
  RecipeProfitabilityQuote._({
    required this.unavailableReason,
    required this.unavailableItemName,
    required this.selectedVariantId,
    required this.outputPerCraft,
    required this.ingredientCost,
    required this.grossRevenue,
    required this.netRevenue,
    required this.profitPerCraft,
    required this.profitPerPiece,
    required this.returnOnCostPercent,
    required this.marketNetRate,
    required List<RecipeIngredientCost> ingredientCosts,
    required Set<String> directMarketItemNames,
  }) : ingredientCosts = List<RecipeIngredientCost>.unmodifiable(
         ingredientCosts,
       ),
       directMarketItemNames = Set<String>.unmodifiable(directMarketItemNames);

  final RecipeProfitabilityUnavailableReason? unavailableReason;
  final String? unavailableItemName;
  final String? selectedVariantId;
  final double? outputPerCraft;
  final double? ingredientCost;
  final double? grossRevenue;
  final double? netRevenue;
  final double? profitPerCraft;
  final double? profitPerPiece;
  final double? returnOnCostPercent;
  final double? marketNetRate;
  final List<RecipeIngredientCost> ingredientCosts;
  final Set<String> directMarketItemNames;

  bool get isAvailable => unavailableReason == null;

  bool get isProfitable => isAvailable && profitPerPiece! > 0;
}

/// Estimates the return from buying every direct ingredient and selling the
/// recipe's expected main output.
///
/// The estimate intentionally ignores owned inventory, recursively crafted
/// inputs, byproducts, utensils, energy, and production time. It uses the
/// active complete recipe variant plus the user's saved substitute and quality
/// selections. Only prices in the current mode's market cache are accepted;
/// bundled fallback prices are never considered current market evidence.
final class RecipeProfitabilityCalculator {
  const RecipeProfitabilityCalculator({this.engine = const PlannerEngine()});

  final PlannerEngine engine;

  RecipeProfitabilityQuote calculate({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required ModeState state,
    required planning.PlannerRules rules,
    required MarketTax marketTax,
  }) {
    final selection = _resolveSelection(
      engine: engine,
      recipe: recipe,
      recipes: recipes,
      state: state,
      rules: rules,
    );
    final marketItemNames = _directMarketItemNames(
      outputName: recipe.name,
      ingredients: selection.ingredients,
      recipes: recipes,
      rules: rules,
    );
    RecipeProfitabilityQuote unavailable(
      RecipeProfitabilityUnavailableReason reason, {
      String? itemName,
      double? outputPerCraft,
      double? netRate,
      List<RecipeIngredientCost> ingredientCosts =
          const <RecipeIngredientCost>[],
    }) => RecipeProfitabilityQuote._(
      unavailableReason: reason,
      unavailableItemName: itemName,
      selectedVariantId: selection.selectedVariantId,
      outputPerCraft: outputPerCraft,
      ingredientCost: null,
      grossRevenue: null,
      netRevenue: null,
      profitPerCraft: null,
      profitPerPiece: null,
      returnOnCostPercent: null,
      marketNetRate: netRate,
      ingredientCosts: ingredientCosts,
      directMarketItemNames: marketItemNames,
    );

    if (!recipe.isCraftable) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.recipeNotCraftable,
        itemName: recipe.name,
      );
    }

    final plannerState = _plannerState(state);
    final outputPerCraft = engine.outputPerCraft(
      recipe: selection.recipe,
      state: plannerState,
    );
    if (!outputPerCraft.isFinite || outputPerCraft <= 0) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.invalidOutputQuantity,
        itemName: recipe.name,
      );
    }

    final netRate = marketNetRate(marketTax);
    if (!netRate.isFinite || netRate <= 0) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.invalidMarketNetRate,
        outputPerCraft: outputPerCraft,
      );
    }

    if (state.market.isItemUnlisted(recipe.name)) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.outputUnlisted,
        itemName: recipe.name,
        outputPerCraft: outputPerCraft,
        netRate: netRate,
      );
    }
    final outputPrice = _positiveMapValue(state.market.prices, recipe.name);
    if (outputPrice == null) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.outputPriceUnavailable,
        itemName: recipe.name,
        outputPerCraft: outputPerCraft,
        netRate: netRate,
      );
    }

    final ingredientCosts = <RecipeIngredientCost>[];
    var totalIngredientCost = 0.0;
    for (final ingredient in selection.ingredients) {
      if (!ingredient.quantity.isFinite || ingredient.quantity <= 0) {
        return unavailable(
          RecipeProfitabilityUnavailableReason.invalidIngredientQuantity,
          itemName: ingredient.selectedName,
          outputPerCraft: outputPerCraft,
          netRate: netRate,
          ingredientCosts: ingredientCosts,
        );
      }
      final ingredientRecipe = _mapValue(recipes, ingredient.selectedName);
      final source = resolveSourceInfo(
        name: ingredient.selectedName,
        recipe: ingredientRecipe,
        rules: rules,
      );
      final vendorPrice = source.npcPrice;
      late final double unitPrice;
      late final RecipeIngredientPriceSource priceSource;
      if (vendorPrice.isFinite && vendorPrice > 0) {
        unitPrice = vendorPrice;
        priceSource = RecipeIngredientPriceSource.vendor;
      } else {
        if (state.market.isItemUnlisted(ingredient.selectedName)) {
          return unavailable(
            RecipeProfitabilityUnavailableReason.ingredientUnlisted,
            itemName: ingredient.selectedName,
            outputPerCraft: outputPerCraft,
            netRate: netRate,
            ingredientCosts: ingredientCosts,
          );
        }
        final marketPrice = _positiveMapValue(
          state.market.prices,
          ingredient.selectedName,
        );
        if (marketPrice == null) {
          return unavailable(
            RecipeProfitabilityUnavailableReason.ingredientPriceUnavailable,
            itemName: ingredient.selectedName,
            outputPerCraft: outputPerCraft,
            netRate: netRate,
            ingredientCosts: ingredientCosts,
          );
        }
        unitPrice = marketPrice;
        priceSource = RecipeIngredientPriceSource.market;
      }
      final total = ingredient.quantity * unitPrice;
      if (!total.isFinite || total <= 0) {
        return unavailable(
          RecipeProfitabilityUnavailableReason.invalidIngredientCost,
          itemName: ingredient.selectedName,
          outputPerCraft: outputPerCraft,
          netRate: netRate,
          ingredientCosts: ingredientCosts,
        );
      }
      ingredientCosts.add(
        RecipeIngredientCost(
          originalName: ingredient.originalName,
          selectedName: ingredient.selectedName,
          grade: ingredient.grade,
          quantity: ingredient.quantity,
          unitPrice: unitPrice,
          priceSource: priceSource,
          total: total,
        ),
      );
      totalIngredientCost += total;
    }
    if (!totalIngredientCost.isFinite || totalIngredientCost <= 0) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.invalidIngredientCost,
        outputPerCraft: outputPerCraft,
        netRate: netRate,
        ingredientCosts: ingredientCosts,
      );
    }

    final grossRevenue = outputPrice * outputPerCraft;
    final netRevenue = marketNetProceeds(grossRevenue, marketTax);
    final profitPerCraft = netRevenue - totalIngredientCost;
    final profitPerPiece = profitPerCraft / outputPerCraft;
    final returnOnCostPercent = (profitPerCraft / totalIngredientCost) * 100;
    if (!grossRevenue.isFinite ||
        !netRevenue.isFinite ||
        !profitPerCraft.isFinite ||
        !profitPerPiece.isFinite ||
        !returnOnCostPercent.isFinite) {
      return unavailable(
        RecipeProfitabilityUnavailableReason.invalidIngredientCost,
        outputPerCraft: outputPerCraft,
        netRate: netRate,
        ingredientCosts: ingredientCosts,
      );
    }

    return RecipeProfitabilityQuote._(
      unavailableReason: null,
      unavailableItemName: null,
      selectedVariantId: selection.selectedVariantId,
      outputPerCraft: outputPerCraft,
      ingredientCost: totalIngredientCost,
      grossRevenue: grossRevenue,
      netRevenue: netRevenue,
      profitPerCraft: profitPerCraft,
      profitPerPiece: profitPerPiece,
      returnOnCostPercent: returnOnCostPercent,
      marketNetRate: netRate,
      ingredientCosts: ingredientCosts,
      directMarketItemNames: marketItemNames,
    );
  }

  /// Returns the exact display names whose current Central Market prices are
  /// needed for this direct-buy estimate.
  ///
  /// The output is always first. Direct ingredients with a positive resolved
  /// vendor price are omitted because their complete cost is known without a
  /// market request. The coordinator remains responsible for resolving each
  /// name to a market ID.
  Set<String> directMarketItemNames({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required ModeState state,
    required planning.PlannerRules rules,
  }) {
    final selection = _resolveSelection(
      engine: engine,
      recipe: recipe,
      recipes: recipes,
      state: state,
      rules: rules,
    );
    return Set<String>.unmodifiable(
      _directMarketItemNames(
        outputName: recipe.name,
        ingredients: selection.ingredients,
        recipes: recipes,
        rules: rules,
      ),
    );
  }
}

final class _RecipeSelection {
  const _RecipeSelection({
    required this.recipe,
    required this.selectedVariantId,
    required this.ingredients,
  });

  final Recipe recipe;
  final String? selectedVariantId;
  final List<_SelectedIngredient> ingredients;
}

final class _SelectedIngredient {
  const _SelectedIngredient({
    required this.originalName,
    required this.selectedName,
    required this.grade,
    required this.quantity,
  });

  final String originalName;
  final String selectedName;
  final String grade;
  final double quantity;
}

_RecipeSelection _resolveSelection({
  required PlannerEngine engine,
  required Recipe recipe,
  required Map<String, Recipe> recipes,
  required ModeState state,
  required planning.PlannerRules rules,
}) {
  final savedVariantId = _mapValue(state.recipeVariantChoices, recipe.name);
  final selectedVariantId = recipe.resolvedVariantId(savedVariantId);
  final resolvedRecipe = recipe.resolveVariant(savedVariantId);
  final plannerState = _plannerState(state);
  final ingredients = <_SelectedIngredient>[];
  for (final ingredient in resolvedRecipe.ingredients) {
    final selected = engine.previewIngredientSelection(
      recipes: recipes,
      state: plannerState,
      parentName: recipe.name,
      ingredient: ingredient,
      rules: rules,
    );
    ingredients.add(
      _SelectedIngredient(
        originalName: ingredient.name,
        selectedName: selected.name,
        grade: selected.grade,
        quantity: selected.need,
      ),
    );
  }
  return _RecipeSelection(
    recipe: resolvedRecipe,
    selectedVariantId: selectedVariantId,
    ingredients: List<_SelectedIngredient>.unmodifiable(ingredients),
  );
}

Set<String> _directMarketItemNames({
  required String outputName,
  required List<_SelectedIngredient> ingredients,
  required Map<String, Recipe> recipes,
  required planning.PlannerRules rules,
}) {
  final result = <String>{};
  final folded = <String>{};
  void add(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && folded.add(_fold(trimmed))) {
      result.add(trimmed);
    }
  }

  add(outputName);
  for (final ingredient in ingredients) {
    final source = resolveSourceInfo(
      name: ingredient.selectedName,
      recipe: _mapValue(recipes, ingredient.selectedName),
      rules: rules,
    );
    if (!(source.npcPrice.isFinite && source.npcPrice > 0)) {
      add(ingredient.selectedName);
    }
  }
  return result;
}

planning.PlannerState _plannerState(ModeState state) => planning.PlannerState(
  target: state.target,
  want: state.want,
  inventory: state.inventory,
  completedSteps: state.completedSteps,
  ignoreTargetInventory: state.ignoreTargetInventory,
  ignoreIngredientInventory: state.ignoreIngredientInventory,
  alchemyMastery: state.alchemyMastery,
  cookingMastery: state.cookingMastery,
  processingMastery: state.processingMastery,
  useMassProcessing: state.useMassProcessing,
  substituteChoices: state.substituteChoices,
  ingredientGrades: state.ingredientGrades,
  recipeVariantChoices: state.recipeVariantChoices,
  marketPrices: state.market.prices,
  marketStock: state.market.stock,
);

String? _mapKey<T>(Map<String, T> values, String name) {
  if (values.containsKey(name)) return name;
  final folded = _fold(name);
  final matches =
      values.keys.where((key) => _fold(key) == folded).toList(growable: false)
        ..sort();
  return matches.isEmpty ? null : matches.first;
}

T? _mapValue<T>(Map<String, T> values, String name) {
  final key = _mapKey(values, name);
  return key == null ? null : values[key];
}

double? _positiveMapValue(Map<String, double> values, String name) {
  final value = _mapValue(values, name);
  return value != null && value.isFinite && value > 0 ? value : null;
}

String _fold(String value) => value.trim().toLowerCase();
