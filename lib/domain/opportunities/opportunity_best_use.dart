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
}

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
    final selected = quote.ingredients
        .where((input) => matches(input.name, input.itemId))
        .toList();
    final consumed = selected.fold<int>(
      0,
      (sum, input) => sum + input.quantity,
    );
    if (consumed <= 0 ||
        quote.expectedOutput == null ||
        !quote.expectedOutput!.isFinite ||
        quote.expectedOutput! <= 0) {
      continue;
    }
    final others = quote.ingredients
        .where((input) => !matches(input.name, input.itemId))
        .toList();
    double? otherCost = 0;
    for (final input in others) {
      final cost = input.costForCalculation;
      if (cost == null || !cost.isFinite) {
        otherCost = null;
        break;
      }
      otherCost = otherCost! + cost;
    }
    if (otherCost?.isFinite == false) otherCost = null;

    double? directSale = 0;
    for (final input in selected) {
      final item = input.market;
      if (item == null ||
          item.unlisted ||
          !item.quoteIsFresh(now, maxMarketAge)) {
        directSale = null;
        break;
      }
      directSale =
          directSale! +
          marketNetProceeds(
            input.quantity * item.basePrice!.toDouble(),
            marketTax,
          );
    }
    final revenue = quote.listingRevenue;
    final extra = revenue == null || otherCost == null || directSale == null
        ? null
        : (revenue - otherCost - directSale) / consumed;
    final result = OpportunityBestUseQuote(
      recipe: recipe,
      mode: mode,
      quote: quote,
      itemName: selectedName,
      selectedQuantity: consumed,
      ingredientChoices: choices,
      extraProfitPerUnit: extra?.isFinite == true ? extra : null,
      otherInputCost: otherCost,
      otherIngredientsAvailable: others.every(
        (input) => input.quantity > 0 && input.stockCoversRequest,
      ),
      isEstimated: others.any((input) => input.estimatedMarketQuantity > 0),
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
