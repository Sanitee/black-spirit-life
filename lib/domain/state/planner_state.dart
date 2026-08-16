import 'dart:collection';

import '../models/catalog_models.dart';
import '../models/craft_mode.dart';

typedef JsonMap = Map<String, Object?>;

Object? immutableJsonValue(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<String, Object?>(
      value.map(
        (key, nested) => MapEntry(key.toString(), immutableJsonValue(nested)),
      ),
    );
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(immutableJsonValue));
  }
  return value;
}

Map<String, T> _immutableMap<T>(Map<String, T> source) =>
    UnmodifiableMapView<String, T>(Map<String, T>.of(source));

Map<String, Object?> immutableExtensions(Map<String, Object?> source) =>
    UnmodifiableMapView<String, Object?>(
      source.map((key, value) => MapEntry(key, immutableJsonValue(value))),
    );

class MigrationOrigin {
  MigrationOrigin({
    required this.sourceKind,
    required this.sourceVersion,
    required Map<CraftMode, int> sourceModeVersions,
    required this.sourceSha256,
    required this.sourceByteCount,
    required this.migratedAtUtc,
    this.archiveRelativePath,
  }) : sourceModeVersions = UnmodifiableMapView(
         Map<CraftMode, int>.of(sourceModeVersions),
       );

  final String sourceKind;
  final int sourceVersion;
  final Map<CraftMode, int> sourceModeVersions;
  final String sourceSha256;
  final int sourceByteCount;
  final DateTime migratedAtUtc;
  final String? archiveRelativePath;

  JsonMap toJson() => {
    'sourceKind': sourceKind,
    'sourceVersion': sourceVersion,
    'sourceModeVersions': {
      for (final entry in sourceModeVersions.entries)
        entry.key.key: entry.value,
    },
    'sourceSha256': sourceSha256,
    'sourceByteCount': sourceByteCount,
    'migratedAtUtc': migratedAtUtc.toUtc().toIso8601String(),
    if (archiveRelativePath != null) 'archiveRelativePath': archiveRelativePath,
  };
}

/// Account-wide settings used to estimate a safe uninterrupted AFK craft load.
///
/// The penalty threshold is kept separate from the character's displayed
/// maximum LT because Feathery Steps changes when the weight penalty begins; it
/// does not change the displayed maximum itself.
class AfkWeightProfile {
  AfkWeightProfile({
    this.maximumWeightLt = 0,
    this.currentCarriedWeightLt = 0,
    this.safetyBufferLt = 20,
    this.featheryStepsLevel = 0,
    Map<String, Object?> extensions = const {},
  }) : extensions = immutableExtensions(extensions);

  final double maximumWeightLt;
  final double currentCarriedWeightLt;
  final double safetyBufferLt;
  final int featheryStepsLevel;
  final Map<String, Object?> extensions;

  bool get isConfigured => maximumWeightLt.isFinite && maximumWeightLt > 0;

  double get penaltyMultiplier =>
      1 + featheryStepsLevel.clamp(0, 5).toDouble() * .05;

  double get penaltyThresholdLt =>
      isConfigured ? maximumWeightLt * penaltyMultiplier : 0;

  /// Weight that can still be loaded before the configured safe threshold.
  double get safeLimitLt {
    final remaining =
        penaltyThresholdLt - safetyBufferLt - currentCarriedWeightLt;
    return remaining.isFinite && remaining > 0 ? remaining : 0;
  }

  JsonMap toJson() => {
    'maximumWeightLt': maximumWeightLt,
    'currentCarriedWeightLt': currentCarriedWeightLt,
    'safetyBufferLt': safetyBufferLt,
    'featheryStepsLevel': featheryStepsLevel,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

/// Persisted, user-confirmed progress through one AFK craft queue step.
///
/// The application never infers that Black Desert completed a craft. Progress
/// advances only when the user explicitly marks a numbered round complete.
/// [completedAttempts] is stored instead of a set of round numbers so changing
/// the safe load capacity can split the remaining work differently without
/// losing already-confirmed crafts.
class AfkCraftProgress {
  AfkCraftProgress({
    required this.stepKey,
    required this.targetName,
    required this.targetAmount,
    required this.recipeName,
    required this.planSignature,
    required this.totalAttempts,
    required this.attemptsPerRound,
    this.completedAttempts = 0,
    Map<String, Object?> extensions = const {},
  }) : extensions = immutableExtensions(extensions);

  static const int maximumStoredStepsPerMode = 64;

  /// Stable JSON-safe key for one mode-local queue recipe.
  static String storageKeyFor(String recipeName) =>
      Uri.encodeComponent(recipeName.trim());

  /// Stable key for the same recipe appearing under different planner goals.
  static String sessionKeyFor({
    required String targetName,
    required String recipeName,
    bool bonus = false,
  }) => Uri.encodeComponent(
    '${bonus ? 'bonus' : 'plan'}\u001f${targetName.trim()}\u001f${recipeName.trim()}',
  );

  /// Stable mode-local identity for the queue step, normally its recipe name.
  final String stepKey;

  /// The planner goal that owned the queue when this session was started.
  final String targetName;
  final int targetAmount;

  /// Display name and an opaque signature of the selected recipe definition.
  ///
  /// Callers should include variant, substitute, grade, and batch selections in
  /// [planSignature]. A changed signature starts a fresh session rather than
  /// applying old checkmarks to a materially different recipe.
  final String recipeName;
  final String planSignature;

  /// Total recipe attempts required by this queue step and the current safe
  /// number of attempts per AFK round.
  final int totalAttempts;
  final int attemptsPerRound;

  /// Sequential attempts the user explicitly confirmed as finished.
  final int completedAttempts;
  final Map<String, Object?> extensions;

  int get totalRounds => totalAttempts <= 0 || attemptsPerRound <= 0
      ? 0
      : (totalAttempts + attemptsPerRound - 1) ~/ attemptsPerRound;

  int get remainingAttempts =>
      (totalAttempts - completedAttempts).clamp(0, totalAttempts).toInt();

  bool get isComplete =>
      totalAttempts > 0 && completedAttempts >= totalAttempts;

  int attemptsInRound(int roundNumber) {
    if (roundNumber < 1 || roundNumber > totalRounds) return 0;
    final before = (roundNumber - 1) * attemptsPerRound;
    return (totalAttempts - before).clamp(0, attemptsPerRound).toInt();
  }

  int completedAttemptsInRound(int roundNumber) {
    if (roundNumber < 1 || roundNumber > totalRounds) return 0;
    final before = (roundNumber - 1) * attemptsPerRound;
    return (completedAttempts - before)
        .clamp(0, attemptsInRound(roundNumber))
        .toInt();
  }

  bool isRoundCompleted(int roundNumber) {
    final attempts = attemptsInRound(roundNumber);
    return attempts > 0 && completedAttemptsInRound(roundNumber) == attempts;
  }

  bool isRoundPartiallyCompleted(int roundNumber) {
    final completed = completedAttemptsInRound(roundNumber);
    return completed > 0 && completed < attemptsInRound(roundNumber);
  }

  /// Number of fully finished rounds in the current capacity split.
  ///
  /// This remains O(1) even for an unusually large planner target. Widgets can
  /// query [isRoundCompleted] for only the visible, lazily built rows.
  int get completedRoundCount =>
      isComplete ? totalRounds : completedAttempts ~/ attemptsPerRound;

  /// Marks this round and every preceding round complete.
  ///
  /// Sequential progress is deliberate: a later round cannot be represented
  /// as finished while an earlier load is still unchecked.
  AfkCraftProgress markRoundCompleted(int roundNumber) {
    if (roundNumber < 1 || roundNumber > totalRounds) return this;
    final throughRound = (roundNumber * attemptsPerRound)
        .clamp(0, totalAttempts)
        .toInt();
    if (throughRound <= completedAttempts) return this;
    return copyWith(completedAttempts: throughRound);
  }

  /// Unchecks this round and every later round, preserving sequential order.
  AfkCraftProgress markRoundIncomplete(int roundNumber) {
    if (roundNumber < 1 || roundNumber > totalRounds) return this;
    final beforeRound = ((roundNumber - 1) * attemptsPerRound)
        .clamp(0, totalAttempts)
        .toInt();
    if (beforeRound >= completedAttempts) return this;
    return copyWith(completedAttempts: beforeRound);
  }

  AfkCraftProgress reset() => copyWith(completedAttempts: 0);

  int? get nextRoundNumber {
    if (isComplete || totalRounds == 0) return null;
    return (completedAttempts ~/ attemptsPerRound + 1)
        .clamp(1, totalRounds)
        .toInt();
  }

  /// Confirms the next current load. No timer or game state calls this method.
  AfkCraftProgress markNextRoundCompleted() {
    final round = nextRoundNumber;
    return round == null ? this : markRoundCompleted(round);
  }

  /// Confirms the exact endpoint of a load calculated from remaining work.
  ///
  /// Unlike current round boundaries, this endpoint remains correct when a
  /// changed weight capacity leaves the session partway through a newly split
  /// round (for example 40 completed, then a 30-attempt load ending at 70).
  AfkCraftProgress completeThrough(int completedAttemptsAfter) {
    final endpoint = completedAttemptsAfter.clamp(0, totalAttempts).toInt();
    if (endpoint <= completedAttempts) return this;
    return copyWith(completedAttempts: endpoint);
  }

  /// Rolls back the most recent round in the current capacity split.
  AfkCraftProgress undoLastCompletedRound() {
    if (completedAttempts <= 0 || totalRounds == 0) return this;
    final round = ((completedAttempts - 1) ~/ attemptsPerRound + 1)
        .clamp(1, totalRounds)
        .toInt();
    return markRoundIncomplete(round);
  }

  /// Reconciles persisted progress with the currently calculated queue.
  ///
  /// Completed attempts survive capacity and queue-size changes and are
  /// clamped to the new queue total. A different goal or recipe definition is
  /// a new session and starts at zero.
  AfkCraftProgress reconcile({
    required String stepKey,
    required String targetName,
    required int targetAmount,
    required String recipeName,
    required String planSignature,
    required int totalAttempts,
    required int attemptsPerRound,
  }) {
    final sameSession =
        _sameAfkIdentity(this.stepKey, stepKey) &&
        _sameAfkIdentity(this.targetName, targetName) &&
        this.targetAmount == targetAmount &&
        _sameAfkIdentity(this.recipeName, recipeName) &&
        this.planSignature == planSignature;
    if (!sameSession) {
      return AfkCraftProgress(
        stepKey: stepKey,
        targetName: targetName,
        targetAmount: targetAmount,
        recipeName: recipeName,
        planSignature: planSignature,
        totalAttempts: totalAttempts,
        attemptsPerRound: attemptsPerRound,
      );
    }
    return copyWith(
      stepKey: stepKey,
      targetName: targetName,
      recipeName: recipeName,
      totalAttempts: totalAttempts,
      attemptsPerRound: attemptsPerRound,
      completedAttempts: completedAttempts.clamp(0, totalAttempts).toInt(),
    );
  }

  AfkCraftProgress copyWith({
    String? stepKey,
    String? targetName,
    int? targetAmount,
    String? recipeName,
    String? planSignature,
    int? totalAttempts,
    int? attemptsPerRound,
    int? completedAttempts,
    Map<String, Object?>? extensions,
  }) => AfkCraftProgress(
    stepKey: stepKey ?? this.stepKey,
    targetName: targetName ?? this.targetName,
    targetAmount: targetAmount ?? this.targetAmount,
    recipeName: recipeName ?? this.recipeName,
    planSignature: planSignature ?? this.planSignature,
    totalAttempts: totalAttempts ?? this.totalAttempts,
    attemptsPerRound: attemptsPerRound ?? this.attemptsPerRound,
    completedAttempts: completedAttempts ?? this.completedAttempts,
    extensions: extensions ?? this.extensions,
  );

  bool sameValuesAs(AfkCraftProgress other) =>
      stepKey == other.stepKey &&
      targetName == other.targetName &&
      targetAmount == other.targetAmount &&
      recipeName == other.recipeName &&
      planSignature == other.planSignature &&
      totalAttempts == other.totalAttempts &&
      attemptsPerRound == other.attemptsPerRound &&
      completedAttempts == other.completedAttempts &&
      identical(extensions, other.extensions);

  JsonMap toJson() => {
    'stepKey': stepKey,
    'targetName': targetName,
    'targetAmount': targetAmount,
    'recipeName': recipeName,
    'planSignature': planSignature,
    'totalAttempts': totalAttempts,
    'attemptsPerRound': attemptsPerRound,
    'completedAttempts': completedAttempts,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

bool _sameAfkIdentity(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

class PlannerState {
  PlannerState({
    this.schemaVersion = 1,
    required this.applicationVersion,
    required this.lastSuccessfulWriteUtc,
    this.origin,
    this.activeMode = CraftMode.alchemy,
    required this.alchemy,
    required this.cooking,
    required this.processing,
    required Map<String, double> processingYields,
    required this.marketTax,
    AfkWeightProfile? afkWeightProfile,
    this.showDeleteTools = false,
    Map<String, Object?> extensions = const {},
  }) : processingYields = _immutableMap(processingYields),
       afkWeightProfile = afkWeightProfile ?? AfkWeightProfile(),
       extensions = immutableExtensions(extensions);

  final int schemaVersion;
  final String applicationVersion;
  final DateTime lastSuccessfulWriteUtc;
  final MigrationOrigin? origin;
  final CraftMode activeMode;
  final ModeState alchemy;
  final ModeState cooking;
  final ModeState processing;

  /// Legacy Avalonia/native values retained for lossless import, export, and
  /// rollback compatibility. Current plans use each recipe's recorded output
  /// range instead of this global map.
  final Map<String, double> processingYields;
  final MarketTax marketTax;
  final AfkWeightProfile afkWeightProfile;
  final bool showDeleteTools;
  final Map<String, Object?> extensions;

  ModeState forMode(CraftMode mode) => switch (mode) {
    CraftMode.alchemy => alchemy,
    CraftMode.cooking => cooking,
    CraftMode.processing => processing,
  };

  PlannerState copyWith({
    String? applicationVersion,
    DateTime? lastSuccessfulWriteUtc,
    MigrationOrigin? origin,
    CraftMode? activeMode,
    ModeState? alchemy,
    ModeState? cooking,
    ModeState? processing,
    Map<String, double>? processingYields,
    MarketTax? marketTax,
    AfkWeightProfile? afkWeightProfile,
    bool? showDeleteTools,
    Map<String, Object?>? extensions,
  }) => PlannerState(
    schemaVersion: schemaVersion,
    applicationVersion: applicationVersion ?? this.applicationVersion,
    lastSuccessfulWriteUtc:
        lastSuccessfulWriteUtc ?? this.lastSuccessfulWriteUtc,
    origin: origin ?? this.origin,
    activeMode: activeMode ?? this.activeMode,
    alchemy: alchemy ?? this.alchemy,
    cooking: cooking ?? this.cooking,
    processing: processing ?? this.processing,
    processingYields: processingYields ?? this.processingYields,
    marketTax: marketTax ?? this.marketTax,
    afkWeightProfile: afkWeightProfile ?? this.afkWeightProfile,
    showDeleteTools: showDeleteTools ?? this.showDeleteTools,
    extensions: extensions ?? this.extensions,
  );

  JsonMap toJson() => {
    'schemaVersion': schemaVersion,
    'applicationVersion': applicationVersion,
    'lastSuccessfulWriteUtc': lastSuccessfulWriteUtc.toUtc().toIso8601String(),
    if (origin != null) 'origin': origin!.toJson(),
    'activeMode': activeMode.key,
    'alchemy': alchemy.toJson(),
    'cooking': cooking.toJson(),
    'processing': processing.toJson(),
    'processingYields': processingYields,
    'marketTax': marketTax.toJson(),
    'afkWeightProfile': afkWeightProfile.toJson(),
    'showDeleteTools': showDeleteTools,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class ModeState {
  ModeState({
    required this.target,
    this.want = 100,
    required this.bonusTarget,
    this.bonusWant = 100,
    Map<String, double> inventory = const {},
    this.view = 'plan',
    Map<String, RecipeState?> recipeEdits = const {},
    Map<String, String> iconAliases = const {},
    Map<String, CustomIconReference> customIcons = const {},
    Map<String, IngredientMetadata> ingredientMeta = const {},
    Iterable<String> customCategories = const [],
    Map<String, String> substituteChoices = const {},
    Map<String, String> ingredientGrades = const {},
    Map<String, String> recipeVariantChoices = const {},
    Iterable<String> favoriteRecipes = const [],
    Iterable<String> hiddenItems = const [],
    this.bookFavoritesOnly = false,
    this.bookSearchIngredients = false,
    required this.market,
    required this.appearance,
    this.ignoreTargetInventory = true,
    this.ignoreIngredientInventory = true,
    this.alchemyMastery = 0,
    this.cookingMastery = 0,
    this.processingMastery = 0,
    this.useMassProcessing = false,
    Iterable<String> completedSteps = const [],
    Map<String, AfkCraftProgress> afkCraftProgress = const {},
    LegacyModeState? compatibility,
    Map<String, Object?> extensions = const {},
  }) : inventory = _immutableMap(inventory),
       recipeEdits = _immutableMap(recipeEdits),
       iconAliases = _immutableMap(iconAliases),
       customIcons = _immutableMap(customIcons),
       ingredientMeta = _immutableMap(ingredientMeta),
       customCategories = List<String>.unmodifiable(customCategories),
       substituteChoices = _immutableMap(substituteChoices),
       ingredientGrades = _immutableMap(ingredientGrades),
       recipeVariantChoices = _immutableMap(recipeVariantChoices),
       favoriteRecipes = List<String>.unmodifiable(favoriteRecipes),
       hiddenItems = Set<String>.unmodifiable(hiddenItems),
       completedSteps = Set<String>.unmodifiable(completedSteps),
       afkCraftProgress = _immutableMap(afkCraftProgress),
       compatibility = compatibility ?? LegacyModeState(),
       extensions = immutableExtensions(extensions);

  final String target;
  final int want;
  final String bonusTarget;
  final int bonusWant;
  final Map<String, double> inventory;
  final String view;
  final Map<String, RecipeState?> recipeEdits;
  final Map<String, String> iconAliases;
  final Map<String, CustomIconReference> customIcons;
  final Map<String, IngredientMetadata> ingredientMeta;
  final List<String> customCategories;
  final Map<String, String> substituteChoices;
  final Map<String, String> ingredientGrades;
  final Map<String, String> recipeVariantChoices;
  final List<String> favoriteRecipes;
  final Set<String> hiddenItems;
  final bool bookFavoritesOnly;
  final bool bookSearchIngredients;
  final MarketState market;
  final AppearanceSettings appearance;
  final bool ignoreTargetInventory;
  final bool ignoreIngredientInventory;
  final int alchemyMastery;
  final int cookingMastery;
  final int processingMastery;
  final bool useMassProcessing;
  final Set<String> completedSteps;
  final Map<String, AfkCraftProgress> afkCraftProgress;
  final LegacyModeState compatibility;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'target': target,
    'want': want,
    'bonusTarget': bonusTarget,
    'bonusWant': bonusWant,
    'inventory': inventory,
    'view': view,
    'recipeEdits': {
      for (final entry in recipeEdits.entries) entry.key: entry.value?.toJson(),
    },
    'iconAliases': iconAliases,
    'customIcons': {
      for (final entry in customIcons.entries) entry.key: entry.value.toJson(),
    },
    'ingredientMeta': {
      for (final entry in ingredientMeta.entries)
        entry.key: entry.value.toJson(),
    },
    'customCategories': customCategories,
    'substituteChoices': substituteChoices,
    'ingredientGrades': ingredientGrades,
    'recipeVariantChoices': recipeVariantChoices,
    'favoriteRecipes': favoriteRecipes,
    'hiddenItems': hiddenItems.toList(growable: false),
    'bookFavoritesOnly': bookFavoritesOnly,
    'bookSearchIngredients': bookSearchIngredients,
    'market': market.toJson(),
    'appearance': appearance.toJson(),
    'ignoreTargetInventory': ignoreTargetInventory,
    'ignoreIngredientInventory': ignoreIngredientInventory,
    'alchemyMastery': alchemyMastery,
    'cookingMastery': cookingMastery,
    'processingMastery': processingMastery,
    'useMassProcessing': useMassProcessing,
    'completedSteps': completedSteps.toList(growable: false),
    'afkCraftProgress': {
      for (final entry in afkCraftProgress.entries)
        entry.key: entry.value.toJson(),
    },
    'compatibility': compatibility.toJson(),
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class LegacyModeState {
  LegacyModeState({
    this.sourceVersion = 1,
    Map<String, Object?> done = const {},
    this.planSearch = '',
    this.bookSearchRelatedItems = false,
    this.alchemyYield = 3.2,
    Map<String, Object?> extensions = const {},
  }) : done = immutableExtensions(done),
       extensions = immutableExtensions(extensions);

  final int sourceVersion;
  final Map<String, Object?> done;
  final String planSearch;
  final bool bookSearchRelatedItems;
  final double alchemyYield;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'sourceVersion': sourceVersion,
    'done': done,
    'planSearch': planSearch,
    'bookSearchRelatedItems': bookSearchRelatedItems,
    'alchemyYield': alchemyYield,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class RecipeState {
  RecipeState({
    this.type = 'gathered',
    this.baseOutput = 1,
    this.role,
    this.group,
    this.method,
    Iterable<IngredientState> ingredients = const [],
    this.marketId,
    this.sourceNote,
    this.vendor,
    this.location,
    this.npcPrice = 0,
    this.qualityBase,
    this.qualityGrade,
    this.outputMinimum,
    this.outputMaximum,
    Map<String, Object?> extensions = const {},
  }) : ingredients = List<IngredientState>.unmodifiable(ingredients),
       extensions = immutableExtensions(extensions);

  final String type;
  final double baseOutput;
  final RecipeRole? role;
  final String? group;
  final String? method;
  final List<IngredientState> ingredients;
  final String? marketId;
  final String? sourceNote;
  final String? vendor;
  final String? location;
  final double npcPrice;
  final String? qualityBase;
  final String? qualityGrade;
  final double? outputMinimum;
  final double? outputMaximum;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'type': type,
    'baseOutput': baseOutput,
    if (role != null) 'recipeRole': role!.catalogValue,
    if (group != null) 'group': group,
    if (method != null) 'method': method,
    'ingredients': ingredients.map((value) => value.toJson()).toList(),
    if (marketId != null) 'marketId': marketId,
    if (sourceNote != null) 'sourceNote': sourceNote,
    if (vendor != null) 'vendor': vendor,
    if (location != null) 'location': location,
    'npcPrice': npcPrice,
    if (qualityBase != null) 'qualityBase': qualityBase,
    if (qualityGrade != null) 'qualityGrade': qualityGrade,
    if (outputMinimum != null) 'outputMinimum': outputMinimum,
    if (outputMaximum != null) 'outputMaximum': outputMaximum,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class IngredientState {
  IngredientState({
    required this.name,
    required this.quantity,
    Iterable<String> options = const [],
    this.substituteGroup,
    Map<String, double> substituteRatios = const {},
    Map<String, Object?> extensions = const {},
  }) : options = List<String>.unmodifiable(options),
       substituteRatios = _immutableMap(substituteRatios),
       extensions = immutableExtensions(extensions);

  final String name;
  final double quantity;
  final List<String> options;
  final String? substituteGroup;
  final Map<String, double> substituteRatios;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'name': name,
    'quantity': quantity,
    'options': options,
    if (substituteGroup != null) 'substituteGroup': substituteGroup,
    'substituteRatios': substituteRatios,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class IngredientMetadata {
  IngredientMetadata({
    this.category,
    this.npcPrice = 0,
    this.sourceNote,
    this.searchKeywords,
    this.vendor,
    this.location,
    this.marketId,
    this.qualityBase,
    this.qualityTier,
    Map<String, Object?> extensions = const {},
  }) : extensions = immutableExtensions(extensions);

  final String? category;
  final double npcPrice;
  final String? sourceNote;
  final String? searchKeywords;
  final String? vendor;
  final String? location;
  final String? marketId;
  final String? qualityBase;
  final String? qualityTier;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    if (category != null) 'category': category,
    'npcPrice': npcPrice,
    if (sourceNote != null) 'sourceNote': sourceNote,
    if (searchKeywords != null) 'searchKeywords': searchKeywords,
    if (vendor != null) 'vendor': vendor,
    if (location != null) 'location': location,
    if (marketId != null) 'marketId': marketId,
    if (qualityBase != null) 'qualityBase': qualityBase,
    if (qualityTier != null) 'qualityTier': qualityTier,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class MarketState {
  MarketState({
    Map<String, double> prices = const {},
    Map<String, double> stock = const {},
    Map<String, String> tradeMarketIds = const {},
    Map<String, int> totalTrades = const {},
    Map<String, int> tradeObservedAt = const {},
    Map<String, double> observedDailyTrades = const {},
    Map<String, double> tradeObservationHours = const {},
    Map<String, int> lastSoldAtEpochSeconds = const {},
    Iterable<String> unlistedItemNames = const [],
    this.search = '',
    this.sort = 'name',
    this.amount = 100,
    this.selected = '',
    this.fetchedAt = 0,
    this.region = 'eu',
    Map<String, Object?> extensions = const {},
  }) : prices = _immutableMap(prices),
       stock = _immutableMap(stock),
       tradeMarketIds = _immutableMap(tradeMarketIds),
       totalTrades = _immutableMap(totalTrades),
       tradeObservedAt = _immutableMap(tradeObservedAt),
       observedDailyTrades = _immutableMap(observedDailyTrades),
       tradeObservationHours = _immutableMap(tradeObservationHours),
       lastSoldAtEpochSeconds = _immutableMap(lastSoldAtEpochSeconds),
       unlistedItemNames = Set<String>.unmodifiable(
         unlistedItemNames
             .map(_foldedMarketItemName)
             .where((name) => name.isNotEmpty),
       ),
       extensions = immutableExtensions(extensions);

  final Map<String, double> prices;
  final Map<String, double> stock;

  /// Market IDs owning each cumulative-trade snapshot.
  ///
  /// Keeping the ID with the snapshot prevents an edited item mapping from
  /// comparing two unrelated counters.
  final Map<String, String> tradeMarketIds;

  /// Latest source-reported cumulative completed-trade counters.
  final Map<String, int> totalTrades;

  /// Milliseconds since Unix epoch when [totalTrades] was observed.
  final Map<String, int> tradeObservedAt;

  /// Completed trades per 24 elapsed hours, measured between two observations.
  ///
  /// A missing entry means demand has not been measured yet. A stored zero is
  /// a real observation interval in which the cumulative counter did not move.
  final Map<String, double> observedDailyTrades;

  /// Length of the interval used for [observedDailyTrades], in hours.
  final Map<String, double> tradeObservationHours;

  /// Source-reported Unix timestamp, in seconds, for the most recent sale.
  final Map<String, int> lastSoldAtEpochSeconds;

  /// Folded item names that the market gateway has explicitly confirmed
  /// cannot be registered. Unlike a transient row diagnostic, this survives
  /// later request failures and application restarts.
  final Set<String> unlistedItemNames;
  final String search;
  final String sort;
  final int amount;
  final String selected;
  final int fetchedAt;
  final String region;
  final Map<String, Object?> extensions;

  bool isItemUnlisted(String name) =>
      unlistedItemNames.contains(_foldedMarketItemName(name));

  JsonMap toJson() => {
    'prices': prices,
    'stock': stock,
    if (tradeMarketIds.isNotEmpty) 'tradeMarketIds': tradeMarketIds,
    if (totalTrades.isNotEmpty) 'totalTrades': totalTrades,
    if (tradeObservedAt.isNotEmpty) 'tradeObservedAt': tradeObservedAt,
    if (observedDailyTrades.isNotEmpty)
      'observedDailyTrades': observedDailyTrades,
    if (tradeObservationHours.isNotEmpty)
      'tradeObservationHours': tradeObservationHours,
    if (lastSoldAtEpochSeconds.isNotEmpty)
      'lastSoldAtEpochSeconds': lastSoldAtEpochSeconds,
    'unlistedItemNames': (unlistedItemNames.toList()..sort()),
    'search': search,
    'sort': sort,
    'amount': amount,
    'selected': selected,
    'fetchedAt': fetchedAt,
    'region': region,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

String _foldedMarketItemName(String name) => name.trim().toLowerCase();

class MarketTax {
  MarketTax({
    this.enabled = true,
    this.valuePack = false,
    this.merchantRing = false,
    this.familyFameBonus = 0,
    Map<String, Object?> extensions = const {},
  }) : extensions = immutableExtensions(extensions);

  final bool enabled;
  final bool valuePack;
  final bool merchantRing;
  final double familyFameBonus;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'enabled': enabled,
    'valuePack': valuePack,
    'merchantRing': merchantRing,
    'familyFameBonus': familyFameBonus,
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class CustomIconReference {
  const CustomIconReference({
    required this.relativePath,
    required this.sha256,
    required this.mediaType,
    required this.byteCount,
    this.width,
    this.height,
  });

  final String relativePath;
  final String sha256;
  final String mediaType;
  final int byteCount;
  final int? width;
  final int? height;

  JsonMap toJson() => {
    'relativePath': relativePath,
    'sha256': sha256,
    'mediaType': mediaType,
    'byteCount': byteCount,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };
}

class AppearanceSettings {
  AppearanceSettings({
    required this.background,
    this.liveBackdrop = true,
    this.motionIntensity = .42,
    this.motionSpeed = .42,
    required this.particleStyle,
    this.particleDensity = .36,
    this.particleOpacity = .72,
    required this.particleMinSize,
    required this.particleMaxSize,
    this.particleSize = 1,
    this.particleBlur = .12,
    this.particleCustomColor = false,
    required this.particleHue,
    this.particleRainbow = false,
    this.particleNeon = false,
    required this.buttonEffect,
    this.buttonEffectIntensity = .62,
    this.buttonEffectSpeed = .48,
    this.buttonEffectBlur = .08,
    this.buttonEffectActiveOnly = false,
    this.buttonEffectCustomColor = false,
    required this.buttonEffectHue,
    this.buttonEffectRainbow = false,
    this.buttonEffectNeon = false,
    required this.accentHue,
    this.rainbow = false,
    this.neon = false,
    this.backdropBlur = 0,
    this.tabFade = true,
    this.tabTransition = 'slide',
    this.tabTransitionSpeed = 'normal',
    Iterable<AppearancePreset?> presets = const [],
    Map<String, Object?> extensions = const {},
  }) : presets = List<AppearancePreset?>.unmodifiable(presets),
       extensions = immutableExtensions(extensions);

  /// Canonical appearance for new, missing, or otherwise unspecified state.
  ///
  /// Sakura is the product default. Classic remains available explicitly via
  /// [classicDefaultsFor] and through the theme selector.
  factory AppearanceSettings.defaultsFor(CraftMode mode) =>
      AppearanceSettings.sakuraDefaultsFor(mode);

  factory AppearanceSettings.classicDefaultsFor(CraftMode mode) =>
      switch (mode) {
        CraftMode.alchemy => AppearanceSettings(
          background: 'greenhouse',
          particleStyle: 'fumes',
          particleMinSize: .72,
          particleMaxSize: 1.6,
          particleHue: 158,
          buttonEffect: 'glow',
          buttonEffectHue: 158,
          accentHue: 158,
          presets: List<AppearancePreset?>.filled(6, null),
        ),
        CraftMode.cooking => AppearanceSettings(
          background: 'hearth',
          particleStyle: 'embers',
          particleMinSize: .65,
          particleMaxSize: 1.45,
          particleHue: 30,
          buttonEffect: 'embers',
          buttonEffectHue: 30,
          accentHue: 30,
          presets: List<AppearancePreset?>.filled(6, null),
        ),
        CraftMode.processing => AppearanceSettings(
          background: 'tide',
          particleStyle: 'bubbles',
          particleMinSize: .62,
          particleMaxSize: 1.55,
          particleHue: 192,
          buttonEffect: 'sweep',
          buttonEffectHue: 192,
          accentHue: 192,
          presets: List<AppearancePreset?>.filled(6, null),
        ),
      };

  /// Theme defaults used only when the repository creates a genuinely new
  /// profile. Existing and migrated profiles keep their recorded appearance.
  factory AppearanceSettings.sakuraDefaultsFor(CraftMode mode) =>
      switch (mode) {
        CraftMode.alchemy => AppearanceSettings(
          background: 'sakura-night-garden',
          particleStyle: 'petals',
          particleMinSize: .72,
          particleMaxSize: 1.6,
          particleHue: 341,
          buttonEffect: 'glow',
          buttonEffectHue: 341,
          accentHue: 341,
          presets: List<AppearancePreset?>.filled(6, null),
        ),
        CraftMode.cooking => AppearanceSettings(
          background: 'sakura-night-garden',
          particleStyle: 'petals',
          particleMinSize: .65,
          particleMaxSize: 1.45,
          particleHue: 341,
          buttonEffect: 'embers',
          buttonEffectHue: 341,
          accentHue: 341,
          presets: List<AppearancePreset?>.filled(6, null),
        ),
        CraftMode.processing => AppearanceSettings(
          background: 'sakura-night-garden',
          particleStyle: 'petals',
          particleMinSize: .62,
          particleMaxSize: 1.55,
          particleHue: 341,
          buttonEffect: 'sweep',
          buttonEffectHue: 341,
          accentHue: 341,
          presets: List<AppearancePreset?>.filled(6, null),
        ),
      };

  final String background;
  final bool liveBackdrop;
  final double motionIntensity;
  final double motionSpeed;
  final String particleStyle;
  final double particleDensity;
  final double particleOpacity;
  final double particleMinSize;
  final double particleMaxSize;
  final double particleSize;
  final double particleBlur;
  final bool particleCustomColor;
  final double particleHue;
  final bool particleRainbow;
  final bool particleNeon;
  final String buttonEffect;
  final double buttonEffectIntensity;
  final double buttonEffectSpeed;
  final double buttonEffectBlur;
  final bool buttonEffectActiveOnly;
  final bool buttonEffectCustomColor;
  final double buttonEffectHue;
  final bool buttonEffectRainbow;
  final bool buttonEffectNeon;
  final double accentHue;
  final bool rainbow;
  final bool neon;
  final double backdropBlur;
  final bool tabFade;
  final String tabTransition;
  final String tabTransitionSpeed;
  final List<AppearancePreset?> presets;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'background': background,
    'liveBackdrop': liveBackdrop,
    'motionIntensity': motionIntensity,
    'motionSpeed': motionSpeed,
    'particleStyle': particleStyle,
    'particleDensity': particleDensity,
    'particleOpacity': particleOpacity,
    'particleMinSize': particleMinSize,
    'particleMaxSize': particleMaxSize,
    'particleSize': particleSize,
    'particleBlur': particleBlur,
    'particleCustomColor': particleCustomColor,
    'particleHue': particleHue,
    'particleRainbow': particleRainbow,
    'particleNeon': particleNeon,
    'buttonEffect': buttonEffect,
    'buttonEffectIntensity': buttonEffectIntensity,
    'buttonEffectSpeed': buttonEffectSpeed,
    'buttonEffectBlur': buttonEffectBlur,
    'buttonEffectActiveOnly': buttonEffectActiveOnly,
    'buttonEffectCustomColor': buttonEffectCustomColor,
    'buttonEffectHue': buttonEffectHue,
    'buttonEffectRainbow': buttonEffectRainbow,
    'buttonEffectNeon': buttonEffectNeon,
    'accentHue': accentHue,
    'rainbow': rainbow,
    'neon': neon,
    'backdropBlur': backdropBlur,
    'tabFade': tabFade,
    'tabTransition': tabTransition,
    'tabTransitionSpeed': tabTransitionSpeed,
    'presets': presets.map((value) => value?.toJson()).toList(),
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

class AppearancePreset {
  AppearancePreset({
    this.name = 'Preset',
    required this.settings,
    Map<String, Object?> extensions = const {},
  }) : extensions = immutableExtensions(extensions);

  final String name;
  final AppearanceSettings settings;
  final Map<String, Object?> extensions;

  JsonMap toJson() => {
    'name': name,
    'settings': settings.toJson(),
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}
