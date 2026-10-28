import 'dart:math' as math;

import '../catalog/temporarily_archived_items.dart';
import '../market/market_calculations.dart';
import '../market/market_price_models.dart';
import '../models/catalog_models.dart';
import '../planner/ingredient_quality.dart';
import '../planner/planner_engine.dart';
import '../planner/planner_models.dart' as planning;
import '../planner/source_resolution.dart';
import '../state/planner_state.dart';
import 'opportunity_market_models.dart';

enum OpportunitySaleMode { listing, currentBuyers }

enum OpportunityInputEstimateKind { uncheckedDepth, missingStock }

enum OpportunityIssue {
  recipeNotCraftable,
  invalidQuantity,
  invalidOutput,
  invalidTax,
  unknownVariant,
  outputUnlisted,
  outputMarketUnknown,
  outputQuoteStale,
  inputUnlisted,
  inputMarketUnknown,
  inputBookUnknown,
  inputBookStale,
  insufficientInputs,
  outputBookUnknown,
  outputBookStale,
  insufficientBuyers,
  invalidTiming,
  invalidExtraCost,
  invalidSubstitute,
  invalidSalePrice,
}

/// Inventory resolved once for a group of calculations using the same inputs.
/// Copies the recipe map so later in-place edits cannot reuse stale identities.
final class OpportunityInventorySnapshot {
  OpportunityInventorySnapshot._(
    Map<String, Recipe> recipes,
    this._inventory,
    this._rules,
  ) : _recipes = Map.unmodifiable(recipes),
      _owned = _ownedInventory(_inventory, recipes, _rules);

  final Map<String, Recipe> _recipes;
  final Map<String, double> _inventory;
  final planning.PlannerRules _rules;
  final Map<String, int> _owned;

  bool _matches(
    Map<String, Recipe> recipes,
    ModeState state,
    planning.PlannerRules rules,
  ) =>
      identical(_inventory, state.inventory) &&
      identical(_rules, rules) &&
      recipes.length == _recipes.length &&
      recipes.entries.every(
        (entry) => identical(_recipes[entry.key], entry.value),
      );
}

/// A user's own measured or estimated timing, not an asserted game speed.
/// One craft means one complete selected formula, including a 10x formula.
final class OpportunityTimingAssumption {
  const OpportunityTimingAssumption({
    required this.secondsPerCraft,
    this.setupSeconds = 0,
    this.refillSeconds = 0,
    this.craftsPerLoad,
  });

  final double secondsPerCraft;
  final double setupSeconds;
  final double refillSeconds;
  final int? craftsPerLoad;

  double? secondsFor(int crafts) {
    if (crafts <= 0 ||
        !secondsPerCraft.isFinite ||
        secondsPerCraft <= 0 ||
        !setupSeconds.isFinite ||
        setupSeconds < 0 ||
        !refillSeconds.isFinite ||
        refillSeconds < 0 ||
        (craftsPerLoad != null && craftsPerLoad! <= 0) ||
        (refillSeconds > 0 && craftsPerLoad == null)) {
      return null;
    }
    final loads = craftsPerLoad == null ? 1 : (crafts / craftsPerLoad!).ceil();
    final seconds =
        crafts * secondsPerCraft + setupSeconds + (loads - 1) * refillSeconds;
    return seconds.isFinite && seconds > 0 ? seconds : null;
  }
}

final class OpportunityIngredientQuote {
  OpportunityIngredientQuote({
    required this.name,
    required this.itemId,
    required Iterable<String> originalNames,
    required this.quantityPerCraft,
    required this.quantity,
    required this.npcUnitPrice,
    required this.market,
    required this.buyCost,
    required this.preliminaryCost,
    required this.filledQuantity,
    required this.marketQuantity,
    required this.npcQuantity,
    required this.depthKnown,
    required this.availableQuantity,
    required Iterable<OpportunityIssue> issues,
    this.estimatedMarketQuantity = 0,
    this.estimatedUnitPrice,
    this.estimatedFromPreorder = false,
    this.estimatedCost,
    this.estimateKind,
    this.marketUnitPrice,
    this.marketUnitPriceEstimated = false,
    this.stockCoversRequest = false,
    this.ownedQuantity = 0,
    this.ownedSaleAfterTax = 0,
    this.allSaleAfterTax,
  }) : originalNames = Set<String>.unmodifiable(originalNames),
       issues = Set<OpportunityIssue>.unmodifiable(issues);

  final String name;
  final String? itemId;
  final Set<String> originalNames;
  final double quantityPerCraft;
  final int quantity;

  /// Owned units consumed by this batch, capped at its requirement.
  final int ownedQuantity;
  int get purchaseQuantity => quantity - ownedQuantity;

  /// Forgone listing proceeds. Null means an owned sellable input is unpriced.
  final double? ownedSaleAfterTax;

  /// Listing proceeds for the entire selected input, independent of inventory.
  /// Null means unpriced; an audited non-marketable input contributes no market
  /// proceeds. Its NPC purchase price is never substituted as a resale price.
  final double? allSaleAfterTax;
  double? get comparisonCost => _sumCost(costForCalculation, ownedSaleAfterTax);
  final double? npcUnitPrice;

  /// Cheapest checked sell order, or highest fresh preorder / summary estimate.
  /// This remains visible independently of which supplier the calculation uses.
  final double? marketUnitPrice;
  final bool marketUnitPriceEstimated;
  final OpportunityMarketItem? market;
  final double? buyCost;
  final double? preliminaryCost;

  /// Units valued at a fresh preorder or base price, never buyable stock.
  final int estimatedMarketQuantity;
  final double? estimatedUnitPrice;
  final bool estimatedFromPreorder;
  final OpportunityInputEstimateKind? estimateKind;

  /// Full input cost: verified asks/NPC costs plus current-price estimated units.
  final double? estimatedCost;
  double? get costForCalculation => buyCost ?? estimatedCost;
  final int filledQuantity;
  final int marketQuantity;
  final int npcQuantity;
  final bool depthKnown;

  /// Null with known depth means the audited NPC supply is not market-limited.
  final int? availableQuantity;
  final Set<OpportunityIssue> issues;

  /// The latest scoped stock observation or audited NPC supply covers this
  /// quantity. This does not verify the ask-tier cost of a summary-only quote.
  final bool stockCoversRequest;

  bool get coversRequest => buyCost != null && filledQuantity >= quantity;
  double get missingQuantity => (quantity - filledQuantity).toDouble();
}

final class OpportunityQuote {
  OpportunityQuote({
    required this.recipeName,
    required this.selectedVariantId,
    required this.variantLabel,
    required this.batchMultiplier,
    required this.crafts,
    required this.outputPerCraft,
    required this.expectedOutput,
    required this.outputMarket,
    required Iterable<OpportunityIngredientQuote> ingredients,
    required this.listingRevenue,
    required this.inputCost,
    required this.preliminaryInputCost,
    required this.buyerRevenue,
    required this.buyerFilledQuantity,
    required this.marketReady,
    required this.buyersCoverOutput,
    required this.inputCapacityKnown,
    required this.inputCraftCapacity,
    required this.buyerCraftCapacity,
    required this.estimatedSeconds,
    required Iterable<OpportunityIssue> issues,
    this.extraCostPerRun = 0,
    this.extraCostPerCraft = 0,
    this.estimatedInputCost,
    this.customSalePrice,
    this.usesInventory = false,
  }) : ingredients = List<OpportunityIngredientQuote>.unmodifiable(ingredients),
       issues = Set<OpportunityIssue>.unmodifiable(issues);

  final String recipeName;
  final String? selectedVariantId;
  final String? variantLabel;
  final int batchMultiplier;
  final int crafts;
  final double? outputPerCraft;
  final double? expectedOutput;
  final OpportunityMarketItem? outputMarket;
  final List<OpportunityIngredientQuote> ingredients;
  final bool usesInventory;
  double? get allIngredientSales =>
      ingredients.isEmpty ||
          ingredients.any((input) => input.allSaleAfterTax == null)
      ? null
      : ingredients.fold<double>(
          0,
          (sum, input) => sum + input.allSaleAfterTax!,
        );
  double? get ownedIngredientSales =>
      ingredients.isEmpty ||
          ingredients.any((input) => input.ownedSaleAfterTax == null)
      ? null
      : ingredients.fold<double>(
          0,
          (sum, input) => sum + input.ownedSaleAfterTax!,
        );

  bool get ingredientsAvailable =>
      crafts > 0 &&
      outputPerCraft != null &&
      outputPerCraft!.isFinite &&
      outputPerCraft! > 0 &&
      expectedOutput != null &&
      expectedOutput!.isFinite &&
      expectedOutput! > 0 &&
      ingredients.isNotEmpty &&
      ingredients.every(
        (input) => input.quantity > 0 && input.stockCoversRequest,
      );

  /// Optional hypothetical pre-tax unit price, never an order-book receipt.
  /// Invalid supplied values remain present and do not revert to market prices.
  final int? customSalePrice;
  bool get hasCustomSalePrice => customSalePrice != null;

  /// Main-output proceeds after tax, at the supplied price or current base price.
  final double? listingRevenue;

  /// Current ask-depth/NPC cost of purchases still needed. Null is not free.
  final double? inputCost;

  /// Full run input estimate, only when every input can be priced and at least
  /// one input uses a fresh base quote instead of verified asks. This does not
  /// imply stock; [hasUncheckedInputDepth] distinguishes unverified depth.
  final double? estimatedInputCost;
  double? get calculationInputCost => inputCost ?? estimatedInputCost;
  bool get hasEstimatedInputs =>
      ingredients.any((input) => input.estimatedMarketQuantity > 0);
  bool get hasUncheckedInputDepth => ingredients.any(
    (input) =>
        input.estimateKind == OpportunityInputEstimateKind.uncheckedDepth,
  );
  bool get hasEstimatedStockShortfall => ingredients.any(
    (input) => input.estimateKind == OpportunityInputEstimateKind.missingStock,
  );

  /// Entered non-ingredient expenses. These are never inferred from game data.
  /// Per-craft means one complete selected formula, including a 10x formula.
  final double extraCostPerRun;
  final double extraCostPerCraft;

  /// Discovery only: fresh base quotes and NPC prices, without buyable depth.
  final double? preliminaryInputCost;

  /// Main-output proceeds after tax at actual current bids, only when covered.
  final double? buyerRevenue;
  final double buyerFilledQuantity;
  final bool marketReady;
  final bool buyersCoverOutput;
  final bool inputCapacityKnown;

  /// Null with [inputCapacityKnown] means no market-limited input (NPC only).
  final int? inputCraftCapacity;
  final int? buyerCraftCapacity;
  final double? estimatedSeconds;
  final Set<OpportunityIssue> issues;

  double get extraCost => extraCostPerRun + extraCostPerCraft * crafts;
  double? get totalCost => _sumCost(calculationInputCost, extraCost);
  double? get capitalNeeded => totalCost;
  double? get listingProfit => _difference(listingRevenue, totalCost);
  double? get preliminaryListingProfit =>
      _difference(listingRevenue, _sumCost(preliminaryInputCost, extraCost));
  double? get preliminaryComparisonProfit => usesInventory
      ? _difference(preliminaryListingProfit, ownedIngredientSales)
      : preliminaryListingProfit;
  double? get buyerProfit => _difference(buyerRevenue, totalCost);
  double? get listingProfitPerCraft =>
      crafts > 0 && listingProfit != null ? listingProfit! / crafts : null;
  double? get buyerProfitPerCraft =>
      crafts > 0 && buyerProfit != null ? buyerProfit! / crafts : null;
  double? get listingProfitPerHour => _hourly(listingProfit, estimatedSeconds);
  double? get buyerProfitPerHour => _hourly(buyerProfit, estimatedSeconds);

  double? cashProfitFor(OpportunitySaleMode mode) =>
      hasCustomSalePrice || mode == OpportunitySaleMode.listing
      ? listingProfit
      : buyerProfit;

  /// With inventory, compare both choices from the same starting inventory.
  double? profitFor(OpportunitySaleMode mode) => usesInventory
      ? _difference(cashProfitFor(mode), ownedIngredientSales)
      : cashProfitFor(mode);
}

/// Direct inputs only, optionally using owned stock with its resale value.
/// No upstream crafts, unrecorded byproducts, saved fallback prices or speeds.
/// Unchecked depth or a confirmed shortage may use a fresh base-price estimate,
/// never availability. Every input must still have a real price.
final class OpportunityCalculator {
  const OpportunityCalculator({
    this.engine = const PlannerEngine(),
    this.catalogNpcPrices = const {},
  });

  static const int maxCustomSalePrice = 999999999999999;

  final PlannerEngine engine;
  final Map<String, double> catalogNpcPrices;

  OpportunityInventorySnapshot prepareInventory({
    required Map<String, Recipe> recipes,
    required ModeState state,
    required planning.PlannerRules rules,
  }) => OpportunityInventorySnapshot._(recipes, state.inventory, rules);

  Set<String> marketItemNames({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required planning.PlannerRules rules,
    String? selectedVariantId,
  }) => _marketNames(
    recipe: recipe,
    recipes: recipes,
    rules: rules,
    selectedVariantId: selectedVariantId,
    includeOutput: true,
  );

  Set<String> _marketNames({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required planning.PlannerRules rules,
    required bool includeOutput,
    String? selectedVariantId,
  }) {
    if (!recipe.isCraftable ||
        isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId) ||
        _contains(rules.legacyUnavailableItems, recipe.name)) {
      return const <String>{};
    }
    final locked = selectedVariantId == null
        ? null
        : recipe.variantById(selectedVariantId);
    if (selectedVariantId != null && locked == null) return const <String>{};
    final names = <String>{if (includeOutput) recipe.name};
    final formulas = locked == null
        ? _completeFormulas(recipe)
        : <(Recipe, RecipeVariant?)>[
            (recipe.resolveVariant(locked.id), locked),
          ];
    for (final variant in formulas) {
      for (final ingredient in variant.$1.ingredients) {
        for (final name in _optionNames(ingredient, recipes, rules)) {
          names.add(name);
          if (variant.$1.type.trim().toLowerCase() != 'processing' &&
              !recipeHasAuthoritativeQualityVariants(recipe.name)) {
            names.addAll(
              ingredientQualityAlternatives(
                rules: rules,
                ingredientName: name,
              ).map((alternative) => alternative.name),
            );
          }
        }
      }
    }
    return Set<String>.unmodifiable(names);
  }

  Set<String> marketItemIds({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required planning.PlannerRules rules,
    String? selectedVariantId,
  }) => Set<String>.unmodifiable({
    for (final name in marketItemNames(
      recipe: recipe,
      recipes: recipes,
      rules: rules,
      selectedVariantId: selectedVariantId,
    ))
      if (_itemId(name, recipes, rules) case final String id) id,
  });

  /// Exact input candidates, including an output item when it is also consumed.
  Set<String> marketInputIds({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required planning.PlannerRules rules,
    String? selectedVariantId,
  }) => Set<String>.unmodifiable({
    for (final name in _marketNames(
      recipe: recipe,
      recipes: recipes,
      rules: rules,
      selectedVariantId: selectedVariantId,
      includeOutput: false,
    ))
      if (_itemId(name, recipes, rules) case final String id) id,
  });

  String? marketItemId({
    required String name,
    required Map<String, Recipe> recipes,
    required planning.PlannerRules rules,
  }) => _itemId(name, recipes, rules);

  OpportunityQuote evaluate({
    required Recipe recipe,
    required Map<String, Recipe> recipes,
    required ModeState state,
    required planning.PlannerRules rules,
    required MarketTax marketTax,
    required OpportunityMarketSnapshot market,
    required DateTime now,
    int crafts = 1,
    OpportunitySaleMode saleMode = OpportunitySaleMode.listing,
    bool preferAvailableInputs = false,
    bool useInventory = false,
    Set<String> nonMarketableIds = const {},
    String? selectedVariantId,
    OpportunityTimingAssumption? timing,
    double extraCostPerRun = 0,
    double extraCostPerCraft = 0,
    int? customSalePrice,
    Duration maxMarketAge = const Duration(minutes: 5),
    Map<String, String> ingredientChoices = const {},
    Map<String, Map<String, int>> ingredientAllocations = const {},
    OpportunityInventorySnapshot? preparedInventory,
    void Function(String originalName, OpportunityIngredientQuote candidate)?
    onInputCandidate,
  }) {
    OpportunityQuote unavailable(OpportunityIssue issue) => _unavailable(
      recipe,
      crafts,
      issue,
      customSalePrice: customSalePrice,
      usesInventory: useInventory,
    );
    final forbidden =
        _contains(rules.legacyUnavailableItems, recipe.name) ||
        isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId);
    if (!recipe.isCraftable || forbidden) {
      return unavailable(OpportunityIssue.recipeNotCraftable);
    }
    if (crafts <= 0 || crafts > 1000000000 || maxMarketAge.isNegative) {
      return unavailable(OpportunityIssue.invalidQuantity);
    }
    if (!extraCostPerRun.isFinite ||
        extraCostPerRun < 0 ||
        !extraCostPerCraft.isFinite ||
        extraCostPerCraft < 0 ||
        !(extraCostPerRun + extraCostPerCraft * crafts).isFinite) {
      return unavailable(OpportunityIssue.invalidExtraCost);
    }
    final taxRate = marketNetRate(marketTax);
    if (!taxRate.isFinite || taxRate <= 0 || taxRate > 1) {
      return unavailable(OpportunityIssue.invalidTax);
    }
    final locked = selectedVariantId == null
        ? null
        : recipe.variantById(selectedVariantId);
    if (selectedVariantId != null && locked == null) {
      return unavailable(OpportunityIssue.unknownVariant);
    }
    final formulas = locked == null
        ? _completeFormulas(recipe)
        : <(Recipe, RecipeVariant?)>[
            (recipe.resolveVariant(locked.id), locked),
          ];
    final owned = !useInventory
        ? const <String, int>{}
        : preparedInventory?._matches(recipes, state, rules) == true
        ? preparedInventory!._owned
        : _ownedInventory(state.inventory, recipes, rules);
    OpportunityQuote? best;
    for (final (formula, variant) in formulas) {
      final quote = _evaluateFormula(
        formula: formula,
        variant: variant,
        recipes: recipes,
        state: state,
        rules: rules,
        marketTax: marketTax,
        market: market,
        now: now,
        crafts: crafts,
        timing: timing,
        extraCostPerRun: extraCostPerRun,
        extraCostPerCraft: extraCostPerCraft,
        customSalePrice: customSalePrice,
        maxMarketAge: maxMarketAge,
        ingredientChoices: ingredientChoices,
        ingredientAllocations: ingredientAllocations,
        onInputCandidate: onInputCandidate,
        preferAvailableInputs: preferAvailableInputs,
        useInventory: useInventory,
        owned: owned,
        nonMarketableIds: nonMarketableIds,
      );
      if (best == null ||
          _compareQuotes(quote, best, saleMode, preferAvailableInputs) < 0) {
        best = quote;
      }
    }
    return best ?? unavailable(OpportunityIssue.invalidOutput);
  }

  OpportunityQuote _evaluateFormula({
    required Recipe formula,
    required RecipeVariant? variant,
    required Map<String, Recipe> recipes,
    required ModeState state,
    required planning.PlannerRules rules,
    required MarketTax marketTax,
    required OpportunityMarketSnapshot market,
    required DateTime now,
    required int crafts,
    required bool preferAvailableInputs,
    required bool useInventory,
    required Map<String, int> owned,
    required Set<String> nonMarketableIds,
    required OpportunityTimingAssumption? timing,
    required double extraCostPerRun,
    required double extraCostPerCraft,
    required int? customSalePrice,
    required Duration maxMarketAge,
    required Map<String, String> ingredientChoices,
    required Map<String, Map<String, int>> ingredientAllocations,
    required void Function(String, OpportunityIngredientQuote)?
    onInputCandidate,
  }) {
    OpportunityQuote unavailable(OpportunityIssue issue) => _unavailable(
      formula,
      crafts,
      issue,
      customSalePrice: customSalePrice,
      usesInventory: useInventory,
    );
    final plannerRules = _withoutFallbacks(rules);
    final excludedNpcSources = <String>{
      for (final name in state.hiddenItems) name.trim().toLowerCase(),
      for (final entry in state.recipeEdits.entries)
        if (entry.value == null) entry.key.trim().toLowerCase(),
    };
    OpportunityIngredientQuote buy(_Input input) => _buy(
      input,
      crafts,
      market,
      now,
      maxMarketAge,
      owned: owned[input.key] ?? 0,
      taxRate: marketNetRate(marketTax),
      nonMarketable: nonMarketableIds.contains(input.id),
    );
    // The same resolved formula is used for every substitute/grade candidate.
    // Build its catalog overlay once, not once per candidate.
    final formulaRecipes = <String, Recipe>{...recipes, formula.name: formula};
    PreparedIngredientPreview? preparedPreview;
    final issues = <OpportunityIssue>{};
    final outputId = _itemId(formula.name, recipes, rules);
    final output = _marketItem(market, outputId);
    if (output?.unlisted ?? false) {
      issues.add(OpportunityIssue.outputUnlisted);
    }
    if (!formula.baseOutput.isFinite || formula.baseOutput <= 0) {
      return unavailable(OpportunityIssue.invalidOutput);
    }
    double outputPerCraft;
    try {
      outputPerCraft = engine.outputPerCraft(
        recipe: formula,
        state: _selectionState(formula, variant, state),
      );
    } on Object {
      return unavailable(OpportunityIssue.invalidOutput);
    }
    final expectedOutput = outputPerCraft * crafts;
    if (!outputPerCraft.isFinite ||
        outputPerCraft <= 0 ||
        !expectedOutput.isFinite ||
        expectedOutput <= 0) {
      return unavailable(OpportunityIssue.invalidOutput);
    }
    final aggregated = <String, _Input>{};
    if ([
      ...ingredientChoices.keys,
      ...ingredientAllocations.keys,
    ].any((name) => !formula.ingredients.any((input) => input.name == name))) {
      return unavailable(OpportunityIssue.invalidSubstitute);
    }
    for (final ingredient in formula.ingredients) {
      if (!_validQuantity(ingredient.quantity, crafts)) {
        return unavailable(OpportunityIssue.invalidQuantity);
      }
      _Input? chosen;
      OpportunityIngredientQuote? chosenQuote;
      double? chosenIncrement;
      final availableOptions = <String, _Input>{};
      final allocation = ingredientAllocations[ingredient.name];
      if (allocation != null &&
          (allocation.isEmpty ||
              allocation.values.any((count) => count <= 0) ||
              allocation.values.fold<int>(0, (sum, count) => sum + count) !=
                  crafts)) {
        return unavailable(OpportunityIssue.invalidSubstitute);
      }
      for (final name in _optionNames(ingredient, recipes, plannerRules)) {
        final grades = <String>{'normal'};
        if (formula.type.trim().toLowerCase() != 'processing' &&
            !recipeHasAuthoritativeQualityVariants(formula.name)) {
          grades.addAll(
            ingredientQualityAlternatives(
              rules: plannerRules,
              ingredientName: name,
            ).map((alternative) => alternative.grade),
          );
        }
        for (final grade in grades) {
          planning.PlanStepIngredient selected;
          try {
            preparedPreview ??= engine.prepareIngredientPreview(
              recipes: formulaRecipes,
              state: _selectionState(formula, variant, state),
              rules: plannerRules,
            );
            selected = preparedPreview.preview(
              state: _selectionState(
                formula,
                variant,
                state,
                ingredient: ingredient,
                substitute: name,
                grade: grade,
              ),
              parentName: formula.name,
              ingredient: ingredient,
            );
          } on Object {
            continue;
          }
          if (!_validQuantity(selected.need, crafts)) continue;
          if (_contains(rules.legacyUnavailableItems, selected.name)) continue;
          if (isTemporarilyArchivedItem(
            selected.name,
            itemId: _itemId(selected.name, recipes, rules),
          )) {
            continue;
          }
          final source = resolveSourceInfo(
            name: selected.name,
            recipe: _lookup(recipes, selected.name),
            rules: rules,
          );
          final id = _itemId(selected.name, recipes, rules);
          final alias = _lookup(rules.marketNameAliases, selected.name);
          final npc =
              excludedNpcSources.contains(selected.name.trim().toLowerCase())
              ? null
              : _positive(source.npcPrice) ??
                    _positive(_lookup(catalogNpcPrices, selected.name) ?? 0) ??
                    (alias == null
                        ? null
                        : _positive(_lookup(catalogNpcPrices, alias) ?? 0));
          final input = _Input(
            name: selected.name,
            id: id,
            quantityPerCraft: selected.need,
            npcPrice: npc,
            originals: <String>{ingredient.name},
          );
          final previous = aggregated[input.key];
          final combined = previous == null ? input : previous.plus(input);
          final quote = buy(combined);
          if ((availableOptions[selected.name]?.quantityPerCraft ??
                  double.infinity) >
              input.quantityPerCraft) {
            availableOptions[selected.name] = input;
          }
          onInputCandidate?.call(
            ingredient.name,
            previous == null ? quote : buy(input),
          );
          final explicit = ingredientChoices[ingredient.name];
          if (explicit != null && selected.name != explicit) continue;
          final previousQuote = previous == null ? null : buy(previous);
          final incrementalCost = quote.comparisonCost != null
              ? quote.comparisonCost! - (previousQuote?.comparisonCost ?? 0)
              : quote.preliminaryCost == null || quote.ownedSaleAfterTax == null
              ? null
              : quote.preliminaryCost! +
                    quote.ownedSaleAfterTax! -
                    (previousQuote?.preliminaryCost ?? 0) -
                    (previousQuote?.ownedSaleAfterTax ?? 0);
          if (chosenQuote == null ||
              _compareInputs(
                    quote,
                    incrementalCost,
                    chosenQuote,
                    chosenIncrement,
                    preferAvailableInputs,
                  ) <
                  0) {
            chosen = input;
            chosenQuote = quote;
            chosenIncrement = incrementalCost;
          }
        }
      }
      if (allocation != null) {
        for (final entry in allocation.entries) {
          final candidate = availableOptions[entry.key];
          if (candidate == null) {
            return unavailable(OpportunityIssue.invalidSubstitute);
          }
          final allocated = candidate.forCrafts(entry.value);
          aggregated.update(
            allocated.key,
            (previous) => previous.plus(allocated),
            ifAbsent: () => allocated,
          );
        }
        continue;
      }
      if (chosen == null && ingredientChoices.containsKey(ingredient.name)) {
        return unavailable(OpportunityIssue.invalidSubstitute);
      }
      if (chosen == null) {
        if (isTemporarilyArchivedItem(
          ingredient.name,
          itemId: _itemId(ingredient.name, recipes, rules),
        )) {
          // Keep an archived-only input visibly required and unpriced. Never
          // drop it from the formula or turn historical cached prices into a
          // currently actionable purchase recommendation.
          planning.PlanStepIngredient requiredInput;
          try {
            preparedPreview ??= engine.prepareIngredientPreview(
              recipes: formulaRecipes,
              state: _selectionState(formula, variant, state),
              rules: plannerRules,
            );
            requiredInput = preparedPreview.preview(
              state: _selectionState(
                formula,
                variant,
                state,
                ingredient: ingredient,
                substitute: ingredient.name,
                grade: 'normal',
              ),
              parentName: formula.name,
              ingredient: ingredient,
            );
          } on Object {
            return unavailable(OpportunityIssue.invalidQuantity);
          }
          if (!_validQuantity(requiredInput.need, crafts)) {
            return unavailable(OpportunityIssue.invalidQuantity);
          }
          chosen = _Input(
            name: ingredient.name,
            id: _itemId(ingredient.name, recipes, rules),
            quantityPerCraft: requiredInput.need,
            npcPrice: null,
            originals: {ingredient.name},
          );
        }
      }
      if (chosen == null) {
        return unavailable(OpportunityIssue.invalidQuantity);
      }
      aggregated.update(
        chosen.key,
        (previous) => previous.plus(chosen!),
        ifAbsent: () => chosen!,
      );
    }
    final inputs = <OpportunityIngredientQuote>[
      for (final input in aggregated.values) buy(input),
    ];
    for (final input in inputs) {
      issues.addAll(input.issues);
    }
    final allInputs = inputs.isNotEmpty && inputs.every((i) => i.coversRequest);
    final inputCost = allInputs
        ? inputs.fold<double>(0, (sum, input) => sum + input.buyCost!)
        : null;
    final estimatedInputCost =
        !allInputs &&
            inputs.isNotEmpty &&
            inputs.every((input) => input.costForCalculation != null)
        ? inputs.fold<double>(
            0,
            (sum, input) => sum + input.costForCalculation!,
          )
        : null;
    final preliminaryInputCost =
        inputs.isNotEmpty &&
            inputs.every((input) => input.preliminaryCost != null)
        ? inputs.fold<double>(0, (sum, input) => sum + input.preliminaryCost!)
        : null;
    final quoteFresh = output != null && output.quoteIsFresh(now, maxMarketAge);
    double? listingRevenue;
    if (!(output?.unlisted ?? false)) {
      if (output == null || (output.basePrice ?? 0) <= 0) {
        issues.add(OpportunityIssue.outputMarketUnknown);
      } else if (!quoteFresh) {
        issues.add(OpportunityIssue.outputQuoteStale);
      } else {
        listingRevenue = marketNetProceeds(
          expectedOutput * output.basePrice!,
          marketTax,
        );
      }
    }
    final marketListingKnown = listingRevenue != null;
    if (customSalePrice != null) {
      listingRevenue = null;
      final gross = expectedOutput * customSalePrice;
      if (customSalePrice <= 0 ||
          customSalePrice > maxCustomSalePrice ||
          !gross.isFinite) {
        issues.add(OpportunityIssue.invalidSalePrice);
      } else if (!(output?.unlisted ?? false)) {
        listingRevenue = marketNetProceeds(gross, marketTax);
      }
    }
    double? buyerRevenue;
    var buyerFilledQuantity = 0.0;
    int? buyerCapacity;
    var buyersCover = false;
    if (!(output?.unlisted ?? false)) {
      if (output == null || output.bids == null) {
        issues.add(OpportunityIssue.outputBookUnknown);
      } else if (!output.bookIsFresh(now, maxMarketAge)) {
        issues.add(OpportunityIssue.outputBookStale);
      } else {
        final bids = _validLevels(output.bids!, buying: false);
        final available = bids.fold<int>(
          0,
          (sum, level) => sum + level.quantity,
        );
        buyerCapacity = (available / outputPerCraft).floor();
        final filled = _expectedSale(bids, expectedOutput);
        buyerFilledQuantity = filled.$1;
        buyersCover = available >= expectedOutput.ceil();
        if (buyersCover) {
          buyerRevenue = marketNetProceeds(filled.$2, marketTax);
        } else {
          issues.add(OpportunityIssue.insufficientBuyers);
        }
      }
    }
    final capacityKnown =
        inputs.isNotEmpty && inputs.every((i) => i.depthKnown);
    int? inputCapacity;
    for (final input in inputs.where(
      (input) => input.availableQuantity != null,
    )) {
      final capacity = (input.availableQuantity! / input.quantityPerCraft)
          .floor();
      inputCapacity = inputCapacity == null
          ? capacity
          : math.min(inputCapacity, capacity);
    }
    final seconds = timing?.secondsFor(crafts);
    if (timing != null && seconds == null) {
      issues.add(OpportunityIssue.invalidTiming);
    }
    return OpportunityQuote(
      recipeName: formula.name,
      selectedVariantId: variant?.id,
      variantLabel: variant?.label,
      batchMultiplier: variant?.batchMultiplier ?? 1,
      crafts: crafts,
      outputPerCraft: outputPerCraft,
      expectedOutput: expectedOutput,
      outputMarket: output,
      ingredients: inputs,
      listingRevenue: listingRevenue,
      inputCost: inputCost,
      estimatedInputCost: estimatedInputCost,
      preliminaryInputCost: preliminaryInputCost,
      buyerRevenue: buyerRevenue,
      buyerFilledQuantity: buyerFilledQuantity,
      marketReady: allInputs && marketListingKnown && listingRevenue != null,
      buyersCoverOutput: buyersCover,
      inputCapacityKnown: capacityKnown,
      inputCraftCapacity: inputCapacity,
      buyerCraftCapacity: buyerCapacity,
      estimatedSeconds: seconds,
      extraCostPerRun: extraCostPerRun,
      extraCostPerCraft: extraCostPerCraft,
      customSalePrice: customSalePrice,
      usesInventory: useInventory,
      issues: issues,
    );
  }
}

OpportunityIngredientQuote _buy(
  _Input input,
  int crafts,
  OpportunityMarketSnapshot market,
  DateTime now,
  Duration maxAge, {
  int owned = 0,
  double taxRate = 1,
  bool nonMarketable = false,
}) {
  final required = (input.quantityPerCraft * crafts + input.allocatedQuantity)
      .ceil();
  final archived = isTemporarilyArchivedItem(input.name, itemId: input.id);
  final item = archived ? null : _marketItem(market, input.id);
  final npc = archived ? null : input.npcPrice;
  final base =
      item != null &&
          !item.unlisted &&
          item.quoteIsFresh(now, maxAge) &&
          (item.basePrice ?? 0) > 0
      ? item.basePrice!.toDouble()
      : null;
  final issues = <OpportunityIssue>{};
  final bookFresh = item != null && item.bookIsFresh(now, maxAge);
  final bookKnown =
      bookFresh &&
      item.asks != null &&
      !item.unlisted &&
      item.asks!.every((level) => level.price > 0 && level.quantity >= 0);
  final asks = bookKnown
      ? _validLevels(item.asks!, buying: true)
      : const <OpportunityMarketLevel>[];
  double? preorderPrice;
  if (bookKnown) {
    for (final bid in item.bids!) {
      if (bid.price <= 0 || bid.quantity < 0) {
        preorderPrice = null;
        break;
      }
      if (bid.quantity > 0 && bid.price > (preorderPrice ?? 0)) {
        preorderPrice = bid.price.toDouble();
      }
    }
  }
  final estimateUnit = preorderPrice ?? base;
  final preliminaryUnit = npc == null
      ? estimateUnit
      : estimateUnit == null
      ? npc
      : math.min(npc, estimateUnit);
  final usedOwned = math.min(required, owned);
  final purchasing = required - usedOwned;
  final ownedSale = usedOwned == 0 || nonMarketable
      ? 0.0
      : base == null
      ? null
      : usedOwned * base * taxRate;
  var left = purchasing;
  var cost = 0.0;
  var marketUnits = 0;
  var npcUnits = 0;
  for (final level in asks) {
    if (npc != null && level.price >= npc) break;
    final units = math.min(left, level.quantity);
    cost += units * level.price;
    marketUnits += units;
    left -= units;
    if (left == 0) break;
  }
  if (left > 0 && npc != null) {
    npcUnits = left;
    cost += left * npc;
    left = 0;
  }
  if (left > 0) {
    if (item?.unlisted ?? false) {
      issues.add(OpportunityIssue.inputUnlisted);
    } else if (item == null) {
      issues.add(OpportunityIssue.inputMarketUnknown);
    } else if (item.asks == null) {
      issues.add(OpportunityIssue.inputBookUnknown);
    } else if (!bookFresh) {
      issues.add(OpportunityIssue.inputBookStale);
    } else if (!bookKnown) {
      issues.add(OpportunityIssue.inputBookUnknown);
    } else {
      issues.add(OpportunityIssue.insufficientInputs);
    }
  }
  // Price the shortfall at the highest active preorder, falling back to a fresh
  // summary only when no valid bid is available. Neither implies seller stock.
  // Preserve the actual ask/NPC portion; unknown prices never become zero.
  final estimatedUnits = left > 0 && estimateUnit != null ? left : 0;
  final estimatedCost = estimatedUnits > 0
      ? cost + estimatedUnits * estimateUnit!
      : null;
  final invalidLatestBook =
      bookFresh &&
      !bookKnown &&
      (item.aggregateStock != null ||
          item.stock == null ||
          !item.quoteIsFresh(now, maxAge) ||
          item.bookFetchedAt!.isAfter(item.quoteFetchedAt!));
  final stock = item == null || item.unlisted || invalidLatestBook
      ? null
      : item.stockFor(now, maxAge);
  return OpportunityIngredientQuote(
    name: input.name,
    itemId: input.id,
    originalNames: input.originals,
    quantityPerCraft: input.quantityPerCraft + input.allocatedQuantity / crafts,
    quantity: required,
    ownedQuantity: usedOwned,
    ownedSaleAfterTax: ownedSale,
    allSaleAfterTax: nonMarketable
        ? 0.0
        : base == null
        ? null
        : required * base * taxRate,
    npcUnitPrice: npc,
    marketUnitPrice: asks.isNotEmpty
        ? asks.first.price.toDouble()
        : estimateUnit,
    marketUnitPriceEstimated: asks.isEmpty && estimateUnit != null,
    market: item,
    buyCost: left == 0 && cost.isFinite && (cost > 0 || purchasing == 0)
        ? cost
        : null,
    estimatedMarketQuantity: estimatedCost?.isFinite == true
        ? estimatedUnits
        : 0,
    estimatedUnitPrice: estimatedCost?.isFinite == true ? estimateUnit : null,
    estimatedFromPreorder:
        estimatedCost?.isFinite == true && preorderPrice != null,
    estimatedCost: estimatedCost?.isFinite == true ? estimatedCost : null,
    estimateKind: estimatedCost?.isFinite == true
        ? bookKnown
              ? OpportunityInputEstimateKind.missingStock
              : OpportunityInputEstimateKind.uncheckedDepth
        : null,
    preliminaryCost: purchasing == 0
        ? 0
        : preliminaryUnit == null
        ? null
        : purchasing * preliminaryUnit,
    filledQuantity: required - left,
    marketQuantity: marketUnits,
    npcQuantity: npcUnits,
    depthKnown: npc != null || bookKnown,
    availableQuantity: npc != null
        ? null
        : bookKnown
        ? owned + asks.fold<int>(0, (sum, level) => sum + level.quantity)
        : null,
    stockCoversRequest:
        required > 0 &&
        (purchasing == 0 ||
            npc != null ||
            (stock != null && stock >= purchasing)),
    issues: issues,
  );
}

final class _Input {
  const _Input({
    required this.name,
    required this.id,
    required this.quantityPerCraft,
    required this.npcPrice,
    required this.originals,
    this.allocatedQuantity = 0,
  });

  final String name;
  final String? id;
  final double quantityPerCraft;
  final double? npcPrice;
  final Set<String> originals;
  final double allocatedQuantity;
  String get key => id == null ? 'name:${_fold(name)}' : 'id:$id';

  _Input plus(_Input other) => _Input(
    name: name,
    id: id,
    quantityPerCraft: quantityPerCraft + other.quantityPerCraft,
    allocatedQuantity: allocatedQuantity + other.allocatedQuantity,
    npcPrice: npcPrice == null
        ? other.npcPrice
        : other.npcPrice == null
        ? npcPrice
        : math.min(npcPrice!, other.npcPrice!),
    originals: <String>{...originals, ...other.originals},
  );

  // A split consists of complete crafts of a valid substitute, never fractions
  // of a formula or a claim that different ingredients mix within one craft.
  _Input forCrafts(int count) => _Input(
    name: name,
    id: id,
    quantityPerCraft: 0,
    allocatedQuantity: quantityPerCraft * count,
    npcPrice: npcPrice,
    originals: originals,
  );
}

List<OpportunityMarketLevel> _validLevels(
  List<OpportunityMarketLevel> levels, {
  required bool buying,
}) => levels.where((level) => level.price > 0 && level.quantity > 0).toList()
  ..sort(
    (a, b) => buying ? a.price.compareTo(b.price) : b.price.compareTo(a.price),
  );

(double, double) _expectedSale(
  List<OpportunityMarketLevel> bids,
  double quantity,
) {
  var remaining = quantity;
  var total = 0.0;
  for (final level in bids) {
    final units = math.min(remaining, level.quantity.toDouble());
    total += units * level.price;
    remaining -= units;
    if (remaining <= 0) break;
  }
  return (quantity - remaining, total);
}

int _compareInputs(
  OpportunityIngredientQuote a,
  double? aCost,
  OpportunityIngredientQuote b,
  double? bCost,
  bool preferAvailableInputs,
) {
  if (preferAvailableInputs && a.stockCoversRequest != b.stockCoversRequest) {
    return a.stockCoversRequest ? -1 : 1;
  }
  if (a.coversRequest != b.coversRequest) return a.coversRequest ? -1 : 1;
  if (a.coversRequest) {
    return (aCost ?? double.infinity).compareTo(bCost ?? double.infinity);
  }
  if ((a.estimatedCost != null) != (b.estimatedCost != null)) {
    return a.estimatedCost != null ? -1 : 1;
  }
  if (a.preliminaryCost != null || b.preliminaryCost != null) {
    final price = (aCost ?? double.infinity).compareTo(
      bCost ?? double.infinity,
    );
    if (price != 0) return price;
  }
  final coverage = (b.filledQuantity / b.quantity).compareTo(
    a.filledQuantity / a.quantity,
  );
  if (coverage != 0) return coverage;
  if (a.depthKnown != b.depthKnown) return a.depthKnown ? -1 : 1;
  return _fold(a.name).compareTo(_fold(b.name));
}

int _compareQuotes(
  OpportunityQuote a,
  OpportunityQuote b,
  OpportunitySaleMode mode,
  bool preferAvailableInputs,
) {
  if (preferAvailableInputs &&
      a.ingredientsAvailable != b.ingredientsAvailable) {
    return a.ingredientsAvailable ? -1 : 1;
  }
  // A cheaper estimate must never displace a fully buyable complete formula.
  final aBuyable =
      a.ingredients.isNotEmpty &&
      a.ingredients.every((input) => input.coversRequest);
  final bBuyable =
      b.ingredients.isNotEmpty &&
      b.ingredients.every((input) => input.coversRequest);
  if (aBuyable != bBuyable) return aBuyable ? -1 : 1;
  final aProfit = a.profitFor(mode);
  final bProfit = b.profitFor(mode);
  if ((aProfit != null) != (bProfit != null)) return aProfit != null ? -1 : 1;
  if (aProfit != null && bProfit != null) {
    // Different complete batch sizes must be compared per unit of output.
    final result = (bProfit / b.expectedOutput!).compareTo(
      aProfit / a.expectedOutput!,
    );
    if (result != 0) return result;
  }
  if (aProfit == null &&
      bProfit == null &&
      (a.preliminaryComparisonProfit != null ||
          b.preliminaryComparisonProfit != null)) {
    final aEstimate = a.preliminaryComparisonProfit == null
        ? double.negativeInfinity
        : a.preliminaryComparisonProfit! / a.expectedOutput!;
    final bEstimate = b.preliminaryComparisonProfit == null
        ? double.negativeInfinity
        : b.preliminaryComparisonProfit! / b.expectedOutput!;
    final result = bEstimate.compareTo(aEstimate);
    if (result != 0) return result;
  }
  if (a.marketReady != b.marketReady) return a.marketReady ? -1 : 1;
  if (a.batchMultiplier != b.batchMultiplier) {
    return a.batchMultiplier.compareTo(b.batchMultiplier);
  }
  return (a.selectedVariantId ?? '').compareTo(b.selectedVariantId ?? '');
}

List<(Recipe, RecipeVariant?)> _completeFormulas(Recipe recipe) =>
    recipe.variants.isEmpty
    ? <(Recipe, RecipeVariant?)>[(recipe, null)]
    : <(Recipe, RecipeVariant?)>[
        for (final variant in recipe.variants)
          (recipe.resolveVariant(variant.id), variant),
      ];

Iterable<String> _optionNames(
  Ingredient ingredient,
  Map<String, Recipe> recipes,
  planning.PlannerRules rules,
) sync* {
  final seen = <String>{};
  for (final name in <String>[ingredient.name, ...ingredient.options]) {
    if (name.trim().isEmpty ||
        !seen.add(_fold(name)) ||
        isTemporarilyArchivedItem(
          name,
          itemId: _itemId(name, recipes, rules),
        ) ||
        _contains(rules.legacyUnavailableItems, name)) {
      continue;
    }
    if (name == ingredient.name || _lookup(recipes, name) != null) yield name;
  }
}

Map<String, int> _ownedInventory(
  Map<String, double> inventory,
  Map<String, Recipe> recipes,
  planning.PlannerRules rules,
) {
  final owned = <String, int>{};
  for (final entry in inventory.entries) {
    if (!entry.value.isFinite || entry.value <= 0) continue;
    final id = _itemId(entry.key, recipes, rules);
    final key = id == null ? 'name:${_fold(entry.key)}' : 'id:$id';
    // Aliases for the same item must not count the same stock twice.
    owned[key] = math.max(owned[key] ?? 0, entry.value.floor());
  }
  return owned;
}

planning.PlannerState _selectionState(
  Recipe formula,
  RecipeVariant? variant,
  ModeState state, {
  Ingredient? ingredient,
  String? substitute,
  String? grade,
}) => planning.PlannerState(
  target: formula.name,
  ignoreTargetInventory: true,
  ignoreIngredientInventory: true,
  alchemyMastery: state.alchemyMastery,
  cookingMastery: state.cookingMastery,
  processingMastery: state.processingMastery,
  recipeVariantChoices: {if (variant != null) formula.name: variant.id},
  substituteChoices: {
    if (ingredient != null && substitute != null)
      'recipe:${formula.name}:${ingredient.substituteGroup ?? ingredient.name}':
          substitute,
  },
  ingredientGrades: {
    if (ingredient != null && grade != null)
      'recipe:${formula.name}:${ingredient.name}': grade,
  },
);

// PlannerRules owns immutable copies of all collections. Its direct-purchase
// projection is therefore reusable by identity throughout a calculation batch.
// Weak keys keep replaced catalogs/rules from being retained by this cache.
final _directPurchaseRules = Expando<planning.PlannerRules>();

planning.PlannerRules _withoutFallbacks(planning.PlannerRules rules) =>
    _directPurchaseRules[rules] ??= planning.PlannerRules(
      legacyUnavailableItems: rules.legacyUnavailableItems,
      qualityIngredients: rules.qualityIngredients,
      qualityConversions: rules.qualityConversions,
      blueElixirMap: rules.blueElixirMap,
      cookingSpecialMap: rules.cookingSpecialMap,
      marketIds: rules.marketIds,
      marketNameAliases: rules.marketNameAliases,
      vendorInfo: rules.vendorInfo,
      acquisitionInfo: rules.acquisitionInfo,
    );

String? _itemId(
  String name,
  Map<String, Recipe> recipes,
  planning.PlannerRules rules,
) {
  final recipeId = _lookup(recipes, name)?.marketId;
  final direct = recipeId == null ? null : normalizeNumericMarketId(recipeId);
  if (direct != null) return direct;
  final ruleId = _lookup(rules.marketIds, name);
  final fallback = ruleId == null ? null : normalizeNumericMarketId(ruleId);
  if (fallback != null) return fallback;
  final alias = _lookup(rules.marketNameAliases, name);
  if (alias == null || _fold(alias) == _fold(name)) return null;
  final aliasRecipeId = _lookup(recipes, alias)?.marketId;
  final aliasDirect = aliasRecipeId == null
      ? null
      : normalizeNumericMarketId(aliasRecipeId);
  if (aliasDirect != null) return aliasDirect;
  final aliasRuleId = _lookup(rules.marketIds, alias);
  return aliasRuleId == null ? null : normalizeNumericMarketId(aliasRuleId);
}

OpportunityQuote _unavailable(
  Recipe recipe,
  int crafts,
  OpportunityIssue issue, {
  int? customSalePrice,
  bool usesInventory = false,
}) => OpportunityQuote(
  recipeName: recipe.name,
  usesInventory: usesInventory,
  selectedVariantId: null,
  variantLabel: null,
  batchMultiplier: 1,
  crafts: crafts,
  outputPerCraft: null,
  expectedOutput: null,
  outputMarket: null,
  ingredients: const [],
  listingRevenue: null,
  inputCost: null,
  preliminaryInputCost: null,
  buyerRevenue: null,
  buyerFilledQuantity: 0,
  marketReady: false,
  buyersCoverOutput: false,
  inputCapacityKnown: false,
  inputCraftCapacity: null,
  buyerCraftCapacity: null,
  estimatedSeconds: null,
  issues: {issue},
  customSalePrice: customSalePrice,
);

T? _lookup<T>(Map<String, T> values, String name) {
  final direct = values[name];
  if (direct != null) return direct;
  final folded = _fold(name);
  for (final entry in values.entries) {
    if (_fold(entry.key) == folded) return entry.value;
  }
  return null;
}

bool _contains(Iterable<String> values, String name) {
  final folded = _fold(name);
  return values.any((value) => _fold(value) == folded);
}

String _fold(String name) => name.trim().toLowerCase();
double? _positive(double value) => value.isFinite && value > 0 ? value : null;
bool _validQuantity(double quantity, int crafts) =>
    quantity.isFinite &&
    quantity > 0 &&
    (quantity * crafts) <= 9007199254740991;
OpportunityMarketItem? _marketItem(
  OpportunityMarketSnapshot snapshot,
  String? id,
) {
  if (id == null) return null;
  final item = snapshot.items[id];
  return item != null &&
          item.subId == 0 &&
          normalizeNumericMarketId(item.itemId) == id
      ? item
      : null;
}

double? _sumCost(double? inputCost, double? extraCost) =>
    inputCost != null && extraCost != null && (inputCost + extraCost).isFinite
    ? inputCost + extraCost
    : null;
double? _difference(double? revenue, double? cost) =>
    revenue != null && cost != null && (revenue - cost).isFinite
    ? revenue - cost
    : null;
double? _hourly(double? profit, double? seconds) =>
    profit != null && seconds != null ? profit * 3600 / seconds : null;
