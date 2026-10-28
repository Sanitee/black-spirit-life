import '../market/market_calculations.dart';
import '../market/market_price_models.dart';
import '../models/catalog_models.dart';
import '../models/craft_mode.dart';
import '../planner/planner_models.dart' as planning;
import '../state/planner_state.dart';
import 'opportunity_calculator.dart';
import 'opportunity_market_models.dart';

/// One complete, direct-use formula. [quote] remains the ordinary purchase
/// calculation; [extraProfitPerUnit] instead compares using the selected item
/// with listing that same consumed material after tax. Neither implies a fill.
final class OpportunityBestUseQuote {
  OpportunityBestUseQuote({
    required this.recipe,
    required this.mode,
    required this.quote,
    required this.itemName,
    required this.selectedQuantity,
    required Map<String, String> ingredientChoices,
    required this.extraProfitPerUnit,
    required this.otherInputCost,
    required this.otherIngredientsAvailable,
    required this.isEstimated,
    this.selectedItemId,
    this.comparison,
  }) : ingredientChoices = Map.unmodifiable(ingredientChoices);

  final Recipe recipe;
  final CraftMode mode;
  final OpportunityQuote quote;
  final String itemName;
  final int selectedQuantity;
  final Map<String, String> ingredientChoices;
  final double? extraProfitPerUnit;
  final double? otherInputCost;
  final bool otherIngredientsAvailable;
  final bool isEstimated;

  /// Canonical selected-material identity, retained across mode-local aliases.
  final String? selectedItemId;
  final OpportunityBestUseComparison? comparison;
}

/// Compare using the selected material with listing that same consumed material.
/// Totals refer to [selectedQuantity] raw units, never finished-output units.
/// Independently known values remain available when another price is missing.
final class OpportunityBestUseComparison {
  const OpportunityBestUseComparison._({
    required this.selectedQuantity,
    required this.rawIngredientSale,
    required this.otherInputCost,
    required this.craftingReturn,
    required this.isEstimated,
    required this.otherIngredientsAvailable,
  });

  final int selectedQuantity;

  /// Listing proceeds after tax for only the selected consumed raw material.
  final double? rawIngredientSale;
  final double? otherInputCost;

  /// Output listing proceeds after tax, minus the other ingredients' cost.
  /// The selected material's purchase price is deliberately not deducted.
  final double? craftingReturn;
  final bool isEstimated;
  final bool otherIngredientsAvailable;

  double? get profitLoss => rawIngredientSale == null || craftingReturn == null
      ? null
      : _finiteBestUseValue(craftingReturn! - rawIngredientSale!);
  double? get profitLossPerUnit => _perUnit(profitLoss);
  double? get rawSalePerUnit => _perUnit(rawIngredientSale);
  double? get craftingReturnPerUnit => _perUnit(craftingReturn);

  double? _perUnit(double? value) =>
      value == null ? null : _finiteBestUseValue(value / selectedQuantity);
}

/// Reuses an already evaluated quote, including its current formula, crafts,
/// substitutions and optional custom output price. No price lookup or fill is
/// performed here. Use the same tax and freshness policy as that quote.
///
/// Null means the selected material is absent or has invalid consumption (or an
/// explicitly supplied ID is invalid), not that a price is unknown. An ID takes
/// precedence over the name so aliases and duplicate input slots stay unified.
OpportunityBestUseComparison? calculateOpportunityBestUseComparison({
  required OpportunityQuote quote,
  required String itemName,
  String? selectedItemId,
  required MarketTax marketTax,
  required DateTime now,
  required Duration maxMarketAge,
}) {
  final selectedId = selectedItemId == null
      ? null
      : normalizeNumericMarketId(selectedItemId);
  if (selectedItemId != null && selectedId == null) return null;
  final selectedName = _fold(itemName);
  if (selectedId == null && selectedName.isEmpty) return null;
  bool matches(OpportunityIngredientQuote input) => selectedId == null
      ? _fold(input.name) == selectedName
      : normalizeNumericMarketId(input.itemId ?? '') == selectedId;
  final selected = quote.ingredients.where(matches).toList(growable: false);
  if (selected.isEmpty || selected.any((input) => input.quantity <= 0)) {
    return null;
  }
  final consumed = selected.fold<int>(0, (sum, input) => sum + input.quantity);
  if (consumed <= 0) return null;
  final others = quote.ingredients
      .where((input) => !matches(input))
      .toList(growable: false);
  double? otherCost = 0;
  for (final input in others) {
    final cost = input.costForCalculation;
    if (cost == null || !cost.isFinite) {
      otherCost = null;
      break;
    }
    otherCost = otherCost! + cost;
  }
  otherCost = _finiteBestUseValue(otherCost);

  final taxRate = marketNetRate(marketTax);
  double? directSale = taxRate.isFinite && taxRate > 0 && taxRate <= 1
      ? 0
      : null;
  if (directSale != null) {
    for (final input in selected) {
      final item = input.market;
      final inputId = normalizeNumericMarketId(input.itemId ?? '');
      if (item == null ||
          inputId == null ||
          normalizeNumericMarketId(item.itemId) != inputId ||
          item.subId != 0 ||
          item.unlisted ||
          !item.quoteIsFresh(now, maxMarketAge)) {
        directSale = null;
        break;
      }
      final gross = input.quantity * item.basePrice!.toDouble();
      if (!gross.isFinite) {
        directSale = null;
        break;
      }
      directSale = directSale! + marketNetProceeds(gross, marketTax);
    }
  }
  directSale = _finiteBestUseValue(directSale);
  final revenue = quote.listingRevenue;
  return OpportunityBestUseComparison._(
    selectedQuantity: consumed,
    rawIngredientSale: directSale,
    otherInputCost: otherCost,
    craftingReturn: revenue == null || otherCost == null
        ? null
        : _finiteBestUseValue(revenue - otherCost),
    otherIngredientsAvailable: others.every(
      (input) => input.quantity > 0 && input.stockCoversRequest,
    ),
    isEstimated: others.any((input) => input.estimatedMarketQuantity > 0),
  );
}

double? _finiteBestUseValue(double? value) =>
    value?.isFinite == true ? value : null;

/// Direct input identities only, including every complete variant and accepted
/// substitute/grade. This neither traverses upstream recipes nor reads prices.
Set<String> opportunityBestUseItems(
  Recipe recipe, {
  required Map<String, Recipe> recipes,
  required planning.PlannerRules rules,
}) {
  const calculator = OpportunityCalculator();
  final outputId = calculator.marketItemId(
    name: recipe.name,
    recipes: recipes,
    rules: rules,
  );
  final formulas = recipe.variants.isEmpty
      ? <(String?, Recipe)>[(null, recipe)]
      : <(String?, Recipe)>[
          for (final variant in recipe.variants)
            (variant.id, recipe.resolveVariant(variant.id)),
        ];
  final names = <String>{};
  for (final (variantId, formula) in formulas) {
    if (!formula.baseOutput.isFinite ||
        formula.baseOutput <= 0 ||
        formula.ingredients.any(
          (input) =>
              !input.quantity.isFinite ||
              input.quantity <= 0 ||
              input.quantity > 9007199254740991,
        )) {
      continue;
    }
    names.addAll(
      calculator.marketItemNames(
        recipe: recipe,
        recipes: recipes,
        rules: rules,
        selectedVariantId: variantId,
      ),
    );
  }
  return Set.unmodifiable(
    names.where(
      (name) =>
          _fold(name) != _fold(recipe.name) &&
          (outputId == null ||
              calculator.marketItemId(
                    name: name,
                    recipes: recipes,
                    rules: rules,
                  ) !=
                  outputId),
    ),
  );
}

/// Evaluates one craft of each complete formula with the selected material
/// forced into its eligible direct-input slots. The existing calculator owns
/// quantities, grade ratios, shared-ID aggregation, other substitutes and tax.
/// There is no inventory mutation, assumed amount, recursive crafting or
/// allocation of a stockpile across multiple recipes.
OpportunityBestUseQuote? evaluateOpportunityBestUse({
  required String itemName,
  String? selectedItemId,
  required Recipe recipe,
  required CraftMode mode,
  required Map<String, Recipe> recipes,
  required ModeState state,
  required planning.PlannerRules rules,
  required MarketTax marketTax,
  required OpportunityMarketSnapshot market,
  required DateTime now,
  required Duration maxMarketAge,
  Map<String, double> catalogNpcPrices = const {},
  bool preferAvailableInputs = false,
}) {
  final selectedName = itemName.trim();
  if (selectedName.isEmpty) return null;
  final calculator = OpportunityCalculator(catalogNpcPrices: catalogNpcPrices);
  // A caller may resolve the canonical selection across live mode catalogs.
  // The consumer mode can contain only an alias of that exact same item.
  final selectedId = selectedItemId == null
      ? calculator.marketItemId(
          name: selectedName,
          recipes: recipes,
          rules: rules,
        )
      : normalizeNumericMarketId(selectedItemId);
  if (selectedItemId != null && selectedId == null) return null;
  bool matches(String name, String? id) => selectedId == null
      ? _fold(name) == _fold(selectedName)
      : id == selectedId;
  final candidates = opportunityBestUseItems(
    recipe,
    recipes: recipes,
    rules: rules,
  );
  if (!candidates.any(
    (name) => matches(
      name,
      calculator.marketItemId(name: name, recipes: recipes, rules: rules),
    ),
  )) {
    return null;
  }

  final Iterable<String?> variantIds = recipe.variants.isEmpty
      ? <String?>[null]
      : recipe.variants.map((variant) => variant.id);
  OpportunityBestUseQuote? best;
  for (final variantId in variantIds) {
    final choices = <String, String>{};
    OpportunityQuote evaluate({bool discover = false}) => calculator.evaluate(
      recipe: recipe,
      recipes: recipes,
      state: state,
      rules: rules,
      marketTax: marketTax,
      market: market,
      now: now,
      maxMarketAge: maxMarketAge,
      selectedVariantId: variantId,
      ingredientChoices: discover ? const {} : choices,
      preferAvailableInputs: preferAvailableInputs,
      onInputCandidate: discover
          ? (originalName, candidate) {
              if (!matches(candidate.name, candidate.itemId)) return;
              final previous = choices[originalName];
              // Prefer the selected exact name when equivalent market aliases
              // are offered; the calculator still aggregates their actual ID.
              if (previous == null ||
                  (_fold(candidate.name) == _fold(selectedName) &&
                      _fold(previous) != _fold(selectedName))) {
                choices[originalName] = candidate.name;
              }
            }
          : null,
    );
    evaluate(discover: true);
    if (choices.isEmpty) continue;
    final quote = evaluate();
    final comparison = calculateOpportunityBestUseComparison(
      quote: quote,
      itemName: selectedName,
      selectedItemId: selectedId,
      marketTax: marketTax,
      now: now,
      maxMarketAge: maxMarketAge,
    );
    if (comparison == null ||
        quote.expectedOutput == null ||
        !quote.expectedOutput!.isFinite ||
        quote.expectedOutput! <= 0) {
      continue;
    }
    final result = OpportunityBestUseQuote(
      recipe: recipe,
      mode: mode,
      quote: quote,
      itemName: selectedName,
      selectedQuantity: comparison.selectedQuantity,
      ingredientChoices: choices,
      extraProfitPerUnit: comparison.profitLossPerUnit,
      otherInputCost: comparison.otherInputCost,
      otherIngredientsAvailable: comparison.otherIngredientsAvailable,
      isEstimated: comparison.isEstimated,
      selectedItemId: selectedId,
      comparison: comparison,
    );
    if (best == null || _compare(result, best, preferAvailableInputs) < 0) {
      best = result;
    }
  }
  return best;
}

int _compare(
  OpportunityBestUseQuote a,
  OpportunityBestUseQuote b,
  bool preferAvailableInputs,
) {
  if (preferAvailableInputs &&
      a.otherIngredientsAvailable != b.otherIngredientsAvailable) {
    return a.otherIngredientsAvailable ? -1 : 1;
  }
  final av = a.extraProfitPerUnit;
  final bv = b.extraProfitPerUnit;
  if ((av != null) != (bv != null)) return av != null ? -1 : 1;
  if (av != null && bv != null) {
    final value = bv.compareTo(av);
    if (value != 0) return value;
  }
  if (a.isEstimated != b.isEstimated) return a.isEstimated ? 1 : -1;
  if (a.otherIngredientsAvailable != b.otherIngredientsAvailable) {
    return a.otherIngredientsAvailable ? -1 : 1;
  }
  final batch = a.quote.batchMultiplier.compareTo(b.quote.batchMultiplier);
  return batch != 0
      ? batch
      : (a.quote.selectedVariantId ?? '').compareTo(
          b.quote.selectedVariantId ?? '',
        );
}

String _fold(String name) => name.trim().toLowerCase();
