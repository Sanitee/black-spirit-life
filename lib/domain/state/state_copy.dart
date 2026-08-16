import '../models/catalog_models.dart';
import 'planner_state.dart';

const Object _unchanged = Object();

extension ModeStateCopy on ModeState {
  ModeState copyWith({
    String? target,
    int? want,
    String? bonusTarget,
    int? bonusWant,
    Map<String, double>? inventory,
    String? view,
    Map<String, RecipeState?>? recipeEdits,
    Map<String, String>? iconAliases,
    Map<String, CustomIconReference>? customIcons,
    Map<String, IngredientMetadata>? ingredientMeta,
    Iterable<String>? customCategories,
    Map<String, String>? substituteChoices,
    Map<String, String>? ingredientGrades,
    Map<String, String>? recipeVariantChoices,
    Iterable<String>? favoriteRecipes,
    Iterable<String>? hiddenItems,
    bool? bookFavoritesOnly,
    bool? bookSearchIngredients,
    MarketState? market,
    AppearanceSettings? appearance,
    bool? ignoreTargetInventory,
    bool? ignoreIngredientInventory,
    int? alchemyMastery,
    int? cookingMastery,
    int? processingMastery,
    bool? useMassProcessing,
    Iterable<String>? completedSteps,
    Map<String, AfkCraftProgress>? afkCraftProgress,
    LegacyModeState? compatibility,
    Map<String, Object?>? extensions,
  }) => ModeState(
    target: target ?? this.target,
    want: want ?? this.want,
    bonusTarget: bonusTarget ?? this.bonusTarget,
    bonusWant: bonusWant ?? this.bonusWant,
    inventory: inventory ?? this.inventory,
    view: view ?? this.view,
    recipeEdits: recipeEdits ?? this.recipeEdits,
    iconAliases: iconAliases ?? this.iconAliases,
    customIcons: customIcons ?? this.customIcons,
    ingredientMeta: ingredientMeta ?? this.ingredientMeta,
    customCategories: customCategories ?? this.customCategories,
    substituteChoices: substituteChoices ?? this.substituteChoices,
    ingredientGrades: ingredientGrades ?? this.ingredientGrades,
    recipeVariantChoices: recipeVariantChoices ?? this.recipeVariantChoices,
    favoriteRecipes: favoriteRecipes ?? this.favoriteRecipes,
    hiddenItems: hiddenItems ?? this.hiddenItems,
    bookFavoritesOnly: bookFavoritesOnly ?? this.bookFavoritesOnly,
    bookSearchIngredients: bookSearchIngredients ?? this.bookSearchIngredients,
    market: market ?? this.market,
    appearance: appearance ?? this.appearance,
    ignoreTargetInventory: ignoreTargetInventory ?? this.ignoreTargetInventory,
    ignoreIngredientInventory:
        ignoreIngredientInventory ?? this.ignoreIngredientInventory,
    alchemyMastery: alchemyMastery ?? this.alchemyMastery,
    cookingMastery: cookingMastery ?? this.cookingMastery,
    processingMastery: processingMastery ?? this.processingMastery,
    useMassProcessing: useMassProcessing ?? this.useMassProcessing,
    completedSteps: completedSteps ?? this.completedSteps,
    afkCraftProgress: afkCraftProgress ?? this.afkCraftProgress,
    compatibility: compatibility ?? this.compatibility,
    extensions: extensions ?? this.extensions,
  );

  AfkCraftProgress? afkCraftProgressFor(
    String recipeName, {
    String? progressKey,
  }) =>
      afkCraftProgress[_afkCraftProgressKey(
        recipeName,
        progressKey: progressKey,
      )];

  /// Creates or reconciles one bounded, mode-local AFK craft session.
  ///
  /// This is intended for `ModeFeatureController.updateState`, keeping widgets
  /// free from persistence details while still requiring an explicit user
  /// action before any completed attempts are recorded.
  ModeState reconcileAfkCraftProgress({
    required String targetName,
    required int targetAmount,
    required String recipeName,
    required String planSignature,
    required int totalAttempts,
    required int attemptsPerRound,
    String? progressKey,
  }) {
    final key = _afkCraftProgressKey(recipeName, progressKey: progressKey);
    final current = afkCraftProgress[key];
    final next = current == null
        ? AfkCraftProgress(
            stepKey: key,
            targetName: targetName,
            targetAmount: targetAmount,
            recipeName: recipeName,
            planSignature: planSignature,
            totalAttempts: totalAttempts,
            attemptsPerRound: attemptsPerRound,
          )
        : current.reconcile(
            stepKey: key,
            targetName: targetName,
            targetAmount: targetAmount,
            recipeName: recipeName,
            planSignature: planSignature,
            totalAttempts: totalAttempts,
            attemptsPerRound: attemptsPerRound,
          );
    if (current != null && current.sameValuesAs(next)) return this;
    return copyWith(afkCraftProgress: _upsertAfkCraftProgress(this, next));
  }

  ModeState markNextAfkCraftRoundCompleted(
    String recipeName, {
    String? progressKey,
  }) => _updateAfkCraftProgress(
    this,
    recipeName,
    (progress) => progress.markNextRoundCompleted(),
    progressKey: progressKey,
  );

  ModeState completeAfkCraftThrough(
    String recipeName,
    int completedAttemptsAfter, {
    String? progressKey,
  }) => _updateAfkCraftProgress(
    this,
    recipeName,
    (progress) => progress.completeThrough(completedAttemptsAfter),
    progressKey: progressKey,
  );

  ModeState undoLastAfkCraftRound(String recipeName, {String? progressKey}) =>
      _updateAfkCraftProgress(
        this,
        recipeName,
        (progress) => progress.undoLastCompletedRound(),
        progressKey: progressKey,
      );

  ModeState resetAfkCraftProgress(String recipeName, {String? progressKey}) =>
      _updateAfkCraftProgress(
        this,
        recipeName,
        (progress) => progress.reset(),
        progressKey: progressKey,
      );
}

Map<String, AfkCraftProgress> _upsertAfkCraftProgress(
  ModeState state,
  AfkCraftProgress progress,
) {
  final next = Map<String, AfkCraftProgress>.of(state.afkCraftProgress)
    ..remove(progress.stepKey)
    ..[progress.stepKey] = progress;
  while (next.length > AfkCraftProgress.maximumStoredStepsPerMode) {
    next.remove(next.keys.first);
  }
  return next;
}

ModeState _updateAfkCraftProgress(
  ModeState state,
  String recipeName,
  AfkCraftProgress Function(AfkCraftProgress progress) update, {
  String? progressKey,
}) {
  final key = _afkCraftProgressKey(recipeName, progressKey: progressKey);
  final current = state.afkCraftProgress[key];
  if (current == null) return state;
  final next = update(current);
  if (current.sameValuesAs(next)) return state;
  return state.copyWith(afkCraftProgress: _upsertAfkCraftProgress(state, next));
}

String _afkCraftProgressKey(String recipeName, {String? progressKey}) {
  final explicit = progressKey?.trim();
  return explicit == null || explicit.isEmpty
      ? AfkCraftProgress.storageKeyFor(recipeName)
      : explicit;
}

extension RecipeStateCopy on RecipeState {
  RecipeState copyWith({
    String? type,
    double? baseOutput,
    Object? role = _unchanged,
    Object? group = _unchanged,
    Object? method = _unchanged,
    Iterable<IngredientState>? ingredients,
    Object? marketId = _unchanged,
    Object? sourceNote = _unchanged,
    Object? vendor = _unchanged,
    Object? location = _unchanged,
    double? npcPrice,
    Object? qualityBase = _unchanged,
    Object? qualityGrade = _unchanged,
    Object? outputMinimum = _unchanged,
    Object? outputMaximum = _unchanged,
    Map<String, Object?>? extensions,
  }) => RecipeState(
    type: type ?? this.type,
    baseOutput: baseOutput ?? this.baseOutput,
    role: identical(role, _unchanged) ? this.role : role as RecipeRole?,
    group: identical(group, _unchanged) ? this.group : group as String?,
    method: identical(method, _unchanged) ? this.method : method as String?,
    ingredients: ingredients ?? this.ingredients,
    marketId: identical(marketId, _unchanged)
        ? this.marketId
        : marketId as String?,
    sourceNote: identical(sourceNote, _unchanged)
        ? this.sourceNote
        : sourceNote as String?,
    vendor: identical(vendor, _unchanged) ? this.vendor : vendor as String?,
    location: identical(location, _unchanged)
        ? this.location
        : location as String?,
    npcPrice: npcPrice ?? this.npcPrice,
    qualityBase: identical(qualityBase, _unchanged)
        ? this.qualityBase
        : qualityBase as String?,
    qualityGrade: identical(qualityGrade, _unchanged)
        ? this.qualityGrade
        : qualityGrade as String?,
    outputMinimum: identical(outputMinimum, _unchanged)
        ? this.outputMinimum
        : outputMinimum as double?,
    outputMaximum: identical(outputMaximum, _unchanged)
        ? this.outputMaximum
        : outputMaximum as double?,
    extensions: extensions ?? this.extensions,
  );
}

extension IngredientStateCopy on IngredientState {
  IngredientState copyWith({
    String? name,
    double? quantity,
    Iterable<String>? options,
    Object? substituteGroup = _unchanged,
    Map<String, double>? substituteRatios,
    Map<String, Object?>? extensions,
  }) => IngredientState(
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    options: options ?? this.options,
    substituteGroup: identical(substituteGroup, _unchanged)
        ? this.substituteGroup
        : substituteGroup as String?,
    substituteRatios: substituteRatios ?? this.substituteRatios,
    extensions: extensions ?? this.extensions,
  );
}

extension IngredientMetadataCopy on IngredientMetadata {
  IngredientMetadata copyWith({
    Object? category = _unchanged,
    double? npcPrice,
    Object? sourceNote = _unchanged,
    Object? searchKeywords = _unchanged,
    Object? vendor = _unchanged,
    Object? location = _unchanged,
    Object? marketId = _unchanged,
    Object? qualityBase = _unchanged,
    Object? qualityTier = _unchanged,
    Map<String, Object?>? extensions,
  }) => IngredientMetadata(
    category: identical(category, _unchanged)
        ? this.category
        : category as String?,
    npcPrice: npcPrice ?? this.npcPrice,
    sourceNote: identical(sourceNote, _unchanged)
        ? this.sourceNote
        : sourceNote as String?,
    searchKeywords: identical(searchKeywords, _unchanged)
        ? this.searchKeywords
        : searchKeywords as String?,
    vendor: identical(vendor, _unchanged) ? this.vendor : vendor as String?,
    location: identical(location, _unchanged)
        ? this.location
        : location as String?,
    marketId: identical(marketId, _unchanged)
        ? this.marketId
        : marketId as String?,
    qualityBase: identical(qualityBase, _unchanged)
        ? this.qualityBase
        : qualityBase as String?,
    qualityTier: identical(qualityTier, _unchanged)
        ? this.qualityTier
        : qualityTier as String?,
    extensions: extensions ?? this.extensions,
  );
}

extension MarketStateCopy on MarketState {
  MarketState copyWith({
    Map<String, double>? prices,
    Map<String, double>? stock,
    Map<String, String>? tradeMarketIds,
    Map<String, int>? totalTrades,
    Map<String, int>? tradeObservedAt,
    Map<String, double>? observedDailyTrades,
    Map<String, double>? tradeObservationHours,
    Map<String, int>? lastSoldAtEpochSeconds,
    Iterable<String>? unlistedItemNames,
    String? search,
    String? sort,
    int? amount,
    String? selected,
    int? fetchedAt,
    String? region,
    Map<String, Object?>? extensions,
  }) => MarketState(
    prices: prices ?? this.prices,
    stock: stock ?? this.stock,
    tradeMarketIds: tradeMarketIds ?? this.tradeMarketIds,
    totalTrades: totalTrades ?? this.totalTrades,
    tradeObservedAt: tradeObservedAt ?? this.tradeObservedAt,
    observedDailyTrades: observedDailyTrades ?? this.observedDailyTrades,
    tradeObservationHours: tradeObservationHours ?? this.tradeObservationHours,
    lastSoldAtEpochSeconds:
        lastSoldAtEpochSeconds ?? this.lastSoldAtEpochSeconds,
    unlistedItemNames: unlistedItemNames ?? this.unlistedItemNames,
    search: search ?? this.search,
    sort: sort ?? this.sort,
    amount: amount ?? this.amount,
    selected: selected ?? this.selected,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    region: region ?? this.region,
    extensions: extensions ?? this.extensions,
  );
}

extension MarketTaxCopy on MarketTax {
  MarketTax copyWith({
    bool? enabled,
    bool? valuePack,
    bool? merchantRing,
    double? familyFameBonus,
    Map<String, Object?>? extensions,
  }) => MarketTax(
    enabled: enabled ?? this.enabled,
    valuePack: valuePack ?? this.valuePack,
    merchantRing: merchantRing ?? this.merchantRing,
    familyFameBonus: familyFameBonus ?? this.familyFameBonus,
    extensions: extensions ?? this.extensions,
  );
}

extension AfkWeightProfileCopy on AfkWeightProfile {
  AfkWeightProfile copyWith({
    double? maximumWeightLt,
    double? currentCarriedWeightLt,
    double? safetyBufferLt,
    int? featheryStepsLevel,
    Map<String, Object?>? extensions,
  }) => AfkWeightProfile(
    maximumWeightLt: maximumWeightLt ?? this.maximumWeightLt,
    currentCarriedWeightLt:
        currentCarriedWeightLt ?? this.currentCarriedWeightLt,
    safetyBufferLt: safetyBufferLt ?? this.safetyBufferLt,
    featheryStepsLevel: featheryStepsLevel ?? this.featheryStepsLevel,
    extensions: extensions ?? this.extensions,
  );
}

extension LegacyModeStateCopy on LegacyModeState {
  LegacyModeState copyWith({
    int? sourceVersion,
    Map<String, Object?>? done,
    String? planSearch,
    bool? bookSearchRelatedItems,
    double? alchemyYield,
    Map<String, Object?>? extensions,
  }) => LegacyModeState(
    sourceVersion: sourceVersion ?? this.sourceVersion,
    done: done ?? this.done,
    planSearch: planSearch ?? this.planSearch,
    bookSearchRelatedItems:
        bookSearchRelatedItems ?? this.bookSearchRelatedItems,
    alchemyYield: alchemyYield ?? this.alchemyYield,
    extensions: extensions ?? this.extensions,
  );
}
