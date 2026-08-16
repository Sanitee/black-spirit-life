import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../../app/state/planner_application_controller.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../domain/market/recipe_profitability.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/acquisition_recipe_resolution.dart';
import '../../domain/planner/planner_models.dart' show ResolvedSourceInfo;
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../domain/state/transactions/state_transactions.dart';
import '../planner/planner_contracts.dart';
import 'recipe_book_item_info.dart';
import 'recipe_book_models.dart';
import 'recipe_book_usage.dart';

final Expando<Map<String, List<String>>> _processingConsumerIndexes =
    Expando<Map<String, List<String>>>('processing consumer indexes');
final Expando<Map<String, ProcessingRecipeGroup>> _processingGroupIndexes =
    Expando<Map<String, ProcessingRecipeGroup>>('processing group indexes');
const Duration _marketLoadingLeadIn = Duration(milliseconds: 48);
const RecipeProfitabilityCalculator _profitabilityCalculator =
    RecipeProfitabilityCalculator();

/// Dedicated session state and commands for one open Recipe Book.
///
/// Persisted choices are committed through [ModeFeatureController]; modal-only
/// state never enters the document.
final class RecipeBookController extends ChangeNotifier {
  RecipeBookController({
    required this.modeController,
    required this.catalogRepository,
    required this.callingContext,
    required Iterable<String> allowedTargets,
    String initialSearch = '',
    this.checkPrices,
    DeleteRecipeBookSelection? deleteSelection,
  }) : allowedTargets = List<String>.unmodifiable(allowedTargets),
       _search = initialSearch,
       _deleteSelection =
           deleteSelection ??
           TransactionalRecipeBookDeletion(
             modeController: modeController,
           ).call {
    for (final controller in modeController.owner.modes.values) {
      controller.state.addListener(_documentStateChanged);
    }
    modeController.owner.deleteToolsEnabled.addListener(_editorOptionsChanged);
    modeController.owner.marketTax.addListener(_marketTaxChanged);
  }

  final ModeFeatureController modeController;
  final CatalogRepository catalogRepository;
  final RecipeBookCallingContext callingContext;
  final List<String> allowedTargets;
  final CheckPlannerPrices? checkPrices;
  final DeleteRecipeBookSelection _deleteSelection;

  String _search;
  RecipeBookDensity _density = RecipeBookDensity.fourByThree;
  ProcessingRecipeGroup _group = ProcessingRecipeGroup.all;
  int _page = 0;
  double _scrollOffset = 0;
  int _scrollResetRevision = 0;
  String? _previewName;
  final Set<String> _manualSearchSubstituteKeys = <String>{};
  final Set<String> _manualSearchVariantNames = <String>{};
  bool _deleteSelectionMode = false;
  final Set<String> _selectedForDeletion = <String>{};
  bool _deleteConfirmationVisible = false;
  bool _deletionInProgress = false;
  bool _showHidden = false;
  String? _restoringHiddenName;
  String? _deletionError;
  String? _statusMessage;
  bool _marketChecked = false;
  bool _marketLoading = false;
  bool _outOfStockOnly = false;
  bool _profitableOnly = false;
  RecipeBookMarketSort _marketSort = RecipeBookMarketSort.none;
  String? _marketMessage;
  Set<String>? _estimatedOutputNamesCache;
  RecipeBookDeletionOutcome? _lastDeletion;
  math.Point<double>? _pointerOrigin;
  bool _activationSuppressed = false;
  bool _searchRefreshScheduled = false;
  bool _documentRefreshScheduled = false;
  bool _disposed = false;
  Map<String, Recipe>? _poolRecipesSource;
  List<String>? _poolNamesCache;
  Map<String, RecipeState?>? _hiddenRecipeEditsSource;
  Map<String, IngredientMetadata>? _hiddenIngredientMetaSource;
  Set<String>? _hiddenItemsSource;
  Map<String, Recipe>? _hiddenRecipeCache;
  RecipeBookUsageIndex? _usageIndex;
  final Map<CraftMode, Map<String, Recipe>> _usageRecipeSources =
      <CraftMode, Map<String, Recipe>>{};

  String get search => _search;
  RecipeBookDensity get density => _density;
  ProcessingRecipeGroup get group => _group;
  int get page => _page;
  double get scrollOffset => _scrollOffset;
  int get scrollResetRevision => _scrollResetRevision;
  String? get previewName => _previewName;
  bool get deleteToolsEnabled =>
      modeController.mode == CraftMode.processing &&
      callingContext == RecipeBookCallingContext.planner &&
      modeController.owner.deleteToolsEnabled.value;
  bool get editorOptionsEnabled =>
      callingContext == RecipeBookCallingContext.planner &&
      modeController.owner.deleteToolsEnabled.value;
  bool get deleteSelectionMode => _deleteSelectionMode && deleteToolsEnabled;
  int get selectedForDeletionCount =>
      deleteSelectionMode ? _selectedForDeletion.length : 0;
  Set<String> get selectedForDeletion =>
      Set<String>.unmodifiable(_selectedForDeletion);
  bool get deleteConfirmationVisible => _deleteConfirmationVisible;
  bool get deletionInProgress => _deletionInProgress;
  bool get showHidden => _showHidden && editorOptionsEnabled;
  int get hiddenItemCount => _hiddenRecipeMap().length;
  int get totalHiddenItemCount => CraftMode.values.fold<int>(
    0,
    (total, mode) => total + _hiddenRecipeMapForMode(mode).length,
  );
  bool get canShowHidden =>
      editorOptionsEnabled && !deleteSelectionMode && totalHiddenItemCount > 0;
  String? get restoringHiddenName => _restoringHiddenName;
  String? get deletionError => _deletionError;
  String? get statusMessage => _statusMessage;
  bool get marketChecked => _marketChecked;
  bool get marketLoading => _marketLoading;
  bool get marketControlsVisible => _marketChecked || _marketLoading;
  bool get outOfStockOnly => _outOfStockOnly;
  bool get profitableOnly => _profitableOnly;
  RecipeBookMarketSort get marketSort => _marketSort;
  String? get marketMessage => _marketMessage;
  bool get canUndoDeletion => _lastDeletion != null;
  bool get activationSuppressed => _activationSuppressed;

  bool isEstimatedOutput(String name) =>
      _estimatedOutputNames.contains(_fold(name));

  bool get usesProcessingPaging =>
      modeController.mode == CraftMode.processing &&
      callingContext == RecipeBookCallingContext.planner;

  bool get favoritesOnly => modeController.state.value.bookFavoritesOnly;
  bool get searchByIngredient =>
      modeController.state.value.bookSearchIngredients;

  String get searchHint {
    if (searchByIngredient) {
      return usesProcessingPaging
          ? 'Ingredient name, for example Black Stone Powder'
          : 'Type an ingredient name';
    }
    return usesProcessingPaging
        ? 'Recipe name or keyword, for example sovereign'
        : 'Search recipes';
  }

  RecipeBookSnapshot get snapshot {
    final visibleRecipes = modeController.recipes;
    final hiddenRecipes = _hiddenRecipeMap();
    final hiddenNames = hiddenRecipes.keys.map(_fold).toSet();
    final recipes = showHidden
        ? Map<String, Recipe>.unmodifiable(<String, Recipe>{
            ...visibleRecipes,
            ...hiddenRecipes,
          })
        : visibleRecipes;
    final pool = _poolNames(recipes);
    final processingConsumers =
        modeController.mode == CraftMode.processing &&
            !searchByIngredient &&
            _search.trim().isNotEmpty
        ? _processingConsumers(recipes)
        : const <String, List<String>>{};
    final processingGroups = usesProcessingPaging
        ? _processingGroups(recipes)
        : const <String, ProcessingRecipeGroup>{};
    final favorites = modeController.state.value.favoriteRecipes
        .map(_fold)
        .toSet();
    final groupCounts = <ProcessingRecipeGroup, int>{
      for (final group in ProcessingRecipeGroup.values) group: 0,
    };
    groupCounts[ProcessingRecipeGroup.all] = pool.length;
    for (final name in pool) {
      final group = processingGroups[name] ?? ProcessingRecipeGroup.other;
      groupCounts[group] = (groupCounts[group] ?? 0) + 1;
    }

    final filtered = <String>[];
    final profitability = <String, RecipeProfitabilityQuote>{};
    RecipeProfitabilityQuote quoteFor(String name, Recipe recipe) =>
        profitability.putIfAbsent(name, () => _calculateProfitability(recipe));
    for (final name in pool) {
      final recipe = recipes[name]!;
      final hidden = hiddenNames.contains(_fold(name));
      if (!hidden && favoritesOnly && !favorites.contains(_fold(name))) {
        continue;
      }
      if (usesProcessingPaging &&
          _group != ProcessingRecipeGroup.all &&
          processingGroups[name] != _group) {
        continue;
      }
      if (!_matchesSearch(name, recipe, processingConsumers)) continue;
      if (!hidden &&
          _outOfStockOnly &&
          marketControlsVisible &&
          !_knownOutOfStock(name)) {
        continue;
      }
      if (!hidden && _profitableOnly && marketControlsVisible) {
        if (!_hasProfitabilityMarketIds(recipe, recipes)) continue;
        final quote = quoteFor(name, recipe);
        if (!quote.isProfitable) continue;
      }
      filtered.add(name);
    }
    filtered.sort((left, right) {
      if (showHidden) {
        final leftHidden = hiddenNames.contains(_fold(left));
        final rightHidden = hiddenNames.contains(_fold(right));
        if (leftHidden != rightHidden) return leftHidden ? -1 : 1;
        if (leftHidden) return _compareExactNames(left, right);
      }
      return _compareSnapshotNames(left, right, profitability);
    });

    // The grid is virtualized by visible row, so even the full Processing
    // catalog can remain one continuous, lightweight scroll surface. Keeping
    // every filtered entry here avoids an extra page-size choice and the
    // disorienting Previous/Next hop that the other Recipe Books do not use.
    const pageCount = 1;
    const boundedPage = 0;
    final pageNames = filtered;
    return RecipeBookSnapshot(
      entries: List<RecipeBookEntry>.unmodifiable(
        pageNames.map((name) {
          final recipe = recipes[name]!;
          final isHidden = hiddenNames.contains(_fold(name));
          return RecipeBookEntry(
            name: name,
            recipe: recipe,
            favorite: favorites.contains(_fold(name)),
            selectedForDeletion: _containsFolded(_selectedForDeletion, name),
            hidden: isHidden,
            processingGroup:
                processingGroups[name] ?? ProcessingRecipeGroup.other,
            usedInCount: usedInFor(name).recipeCount,
            marketStock: !isHidden && marketControlsVisible
                ? marketStockFor(name)
                : null,
            profitability: !isHidden && _profitableOnly
                ? quoteFor(name, recipe)
                : null,
          );
        }),
      ),
      filteredCount: filtered.length,
      poolCount: pool.length,
      page: boundedPage,
      pageCount: pageCount,
      groupCounts: List<RecipeBookGroupCount>.unmodifiable(
        ProcessingRecipeGroup.values
            .where(
              (group) =>
                  group == ProcessingRecipeGroup.all ||
                  (groupCounts[group] ?? 0) > 0,
            )
            .map(
              (group) => RecipeBookGroupCount(
                group: group,
                count: groupCounts[group] ?? 0,
              ),
            ),
      ),
    );
  }

  Recipe? recipeDefinitionFor(String name) => _foldedEntry(
    showHidden
        ? <String, Recipe>{...modeController.recipes, ..._hiddenRecipeMap()}
        : modeController.recipes,
    name,
  )?.value;

  Recipe? recipeFor(String name) {
    final recipe = recipeDefinitionFor(name);
    if (recipe == null) return null;
    final contextualVariant = _ingredientSearchMatch(name, recipe)?.variantId;
    return recipe.resolveVariant(
      contextualVariant ?? _savedRecipeVariantId(recipe),
    );
  }

  String? selectedRecipeVariantId(String name) {
    final recipe = recipeDefinitionFor(name);
    if (recipe == null) return null;
    return _ingredientSearchMatch(name, recipe)?.variantId ??
        recipe.resolvedVariantId(_savedRecipeVariantId(recipe));
  }

  RecipeBookUseSnapshot usedInFor(String name) =>
      _usageIndexForState().snapshotFor(name, currentMode: modeController.mode);

  bool canActivateUsedIn(RecipeBookUseEntry entry) =>
      !entry.hidden &&
      (callingContext == RecipeBookCallingContext.planner ||
          (entry.mode == modeController.mode &&
              _poolExactName(entry.name) != null));

  RecipeBookActivation? activateUsedIn(
    RecipeBookUseEntry entry, {
    String? variantId,
  }) {
    if (!canActivateUsedIn(entry)) return null;
    final destination = modeController.owner.modes[entry.mode]!;
    RecipeBookUseRoute? route;
    final requestedVariantId = variantId?.trim();
    if (requestedVariantId != null && requestedVariantId.isNotEmpty) {
      for (final candidate in entry.routes) {
        if (_fold(candidate.variantId ?? '') == _fold(requestedVariantId)) {
          route = candidate;
          break;
        }
      }
      if (route == null) return null;
    } else {
      route = entry.preferredRoute(
        destination.selectedRecipeVariantId(entry.name),
      );
    }
    if (route == null) return null;
    final resolvedVariantId = route.variantId;
    final ingredientSelections = route.matches
        .map(
          (match) => RecipeTargetIngredientSelection(
            ingredientName: match.ingredientName,
            selectedIngredientName: match.selectedIngredientName,
            grade: match.grade,
          ),
        )
        .toList(growable: false);

    if (entry.mode == modeController.mode) {
      final exact = _poolExactName(entry.name);
      if (exact == null) return null;
      if (callingContext == RecipeBookCallingContext.bonus) {
        if (!destination.selectTargetVariant(
          exact,
          variantId: resolvedVariantId,
          bonus: true,
          ingredientSelections: ingredientSelections,
        )) {
          return null;
        }
      } else if (!destination.selectTargetVariant(
        exact,
        variantId: resolvedVariantId,
        ingredientSelections: ingredientSelections,
      )) {
        return null;
      }
      _clearUndo();
      return RecipeBookActivation(
        exactName: exact,
        context: callingContext,
        mode: entry.mode,
        variantId: resolvedVariantId,
      );
    }

    if (callingContext != RecipeBookCallingContext.planner ||
        !destination.selectTargetVariant(
          entry.name,
          variantId: resolvedVariantId,
          ingredientSelections: ingredientSelections,
        )) {
      return null;
    }
    destination.navigate('plan');
    _clearUndo();
    final activation = RecipeBookActivation(
      exactName: entry.name,
      context: callingContext,
      mode: entry.mode,
      variantId: resolvedVariantId,
    );
    modeController.owner.switchMode(entry.mode);
    return activation;
  }

  bool selectRecipeVariant(String name, String variantId) {
    _clearUndo();
    final changed = modeController.selectRecipeVariant(
      recipeName: name,
      variantId: variantId,
    );
    if (changed) _manualSearchVariantNames.add(_fold(name));
    return changed;
  }

  bool isHiddenRecipe(String name) =>
      _foldedEntry(_hiddenRecipeMap(), name) != null;

  RecipeBookItemInfo? itemInfoFor(String name, {CraftMode? mode}) {
    final preferredMode = mode ?? modeController.mode;
    final recipesByMode = <CraftMode, Map<String, Recipe>>{
      for (final mode in CraftMode.values)
        mode: showHidden
            ? <String, Recipe>{
                ...modeController.owner.modes[mode]!.recipes,
                ..._hiddenRecipeMapForMode(mode),
              }
            : modeController.owner.modes[mode]!.recipes,
    };
    final resolved = _itemInfoRecipe(
      name,
      recipesByMode,
      preferredMode: preferredMode,
    );
    final resolvedName = resolved?.name ?? name;
    final resolvedMode = resolved?.mode ?? preferredMode;
    final resolvedController = modeController.owner.modes[resolvedMode]!;
    final resolvedSource = resolvedController.resolveItemSource(
      resolvedName,
      recipe: resolved?.recipe,
    );
    final acquisitionRecipe = _withResolvedAcquisitionSource(
      name: resolvedName,
      recipe: resolved?.recipe,
      source: resolvedSource,
    );
    final consumerRecipes = recipesByMode.values.expand((recipes) {
      final consumerIndex = _processingConsumers(recipes);
      return (consumerIndex[_fold(name)] ?? const <String>[])
          .map((consumer) => _foldedEntry(recipes, consumer)?.value)
          .whereType<Recipe>();
    });
    final info = recipeBookInfoFor(
      name: resolvedName,
      recipe: acquisitionRecipe,
      searchTerms: _processingSearchTerms(resolvedName, mode: resolvedMode),
      consumerRecipes: consumerRecipes,
    );
    if (info == null) return null;
    final researched = withResearchedAcquisition(
      info,
      resolvedController
              .resolveItemAcquisition(resolvedName)
              ?.displayableSummaries ??
          const <String>[],
    );
    return withEstimatedRecipeBookOutputs(researched, _estimatedOutputNames);
  }

  ResolvedAcquisitionRecipe? _itemInfoRecipe(
    String name,
    Map<CraftMode, Map<String, Recipe>> recipesByMode, {
    required CraftMode preferredMode,
  }) {
    final foldedName = _fold(name);
    final hidden = showHidden
        ? _foldedEntry(_hiddenRecipeMapForMode(preferredMode), name)
        : null;
    final suppressedModes = <CraftMode>{
      for (final mode in CraftMode.values)
        if (!(mode == preferredMode && hidden != null) &&
            modeController.owner.modes[mode]!.state.value.recipeEdits.entries
                .any(
                  (entry) =>
                      _fold(entry.key) == foldedName && entry.value == null,
                ))
          mode,
    };
    final preferredReference = _foldedEntry(
      recipesByMode[preferredMode]!,
      hidden?.key ?? name,
    );
    if (preferredReference != null &&
        isBrowsableRecipeBookReference(preferredReference.value)) {
      return ResolvedAcquisitionRecipe(
        name: preferredReference.key,
        recipe: preferredReference.value,
        mode: preferredMode,
      );
    }
    final resolved = resolveAcquisitionRecipe(
      name: hidden?.key ?? name,
      currentMode: preferredMode,
      recipesByMode: recipesByMode,
      suppressedModes: suppressedModes,
    );
    return resolved;
  }

  String? iconDataUriFor(String name) {
    return iconDataUriForMode(modeController.mode, name);
  }

  String? iconDataUriForMode(CraftMode mode, String name) {
    final aliases = modeController.owner.modes[mode]!.state.value.iconAliases;
    final alias = _foldedValue(aliases, name);
    return catalogRepository.iconDataUri(
      mode,
      name,
      aliases: alias == null ? const <String>[] : <String>[alias],
    );
  }

  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    _clearManualSearchSelections();
    _resetPageAndScroll(notify: false);
    _scheduleSearchRefresh();
  }

  /// Windows sends editable-text updates through the platform text-input
  /// channel. Rebuilding the complete modal synchronously from TextField's
  /// `onChanged` can race that update and restore the preceding editing value.
  /// A microtask is still part of the current platform callback, so defer the
  /// visual refresh to the next event-loop turn. The query itself remains
  /// authoritative immediately.
  void _scheduleSearchRefresh() {
    if (_searchRefreshScheduled) return;
    _searchRefreshScheduled = true;
    Timer.run(() {
      _searchRefreshScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void setFavoritesOnly(bool value) {
    if (favoritesOnly == value) return;
    _clearUndo();
    modeController.updateState(
      (state) => state.copyWith(bookFavoritesOnly: value),
      immediate: true,
    );
    _resetPageAndScroll(notify: false);
  }

  void setShowHidden(bool value) {
    if (_showHidden == value ||
        (value && (!canShowHidden || deleteSelectionMode))) {
      return;
    }
    _showHidden = value;
    _usageIndex = null;
    if (!value && _previewName != null) {
      final hidden = _foldedEntry(_hiddenRecipeMap(), _previewName!);
      if (hidden != null) _previewName = null;
    }
    _resetPageAndScroll();
  }

  Future<void> restoreHiddenItem(String name, {CraftMode? mode}) async {
    if (!editorOptionsEnabled || _restoringHiddenName != null) return;
    final targetMode = mode ?? modeController.mode;
    final entry = _foldedEntry(_hiddenRecipeMapForMode(targetMode), name);
    if (entry == null) return;
    final exact = entry.key;
    _clearUndo();
    _restoringHiddenName = exact;
    _deletionError = null;
    notifyListeners();
    try {
      final owner = modeController.owner;
      await owner.updateDocumentDurably(
        (current) => const PlannerStateTransactions()
            .restoreHiddenItems(
              state: current,
              mode: targetMode,
              itemNames: <String>[exact],
            )
            .state,
      );
      _synchronizeDocumentSettings();
      _statusMessage = '$exact restored.';
      if (targetMode == modeController.mode &&
          _previewName != null &&
          _sameName(_previewName!, exact)) {
        _previewName = null;
      }
    } on Object catch (error) {
      _deletionError = '$exact could not be restored. $error';
    } finally {
      _restoringHiddenName = null;
      if (!_disposed) notifyListeners();
    }
  }

  void setSearchByIngredient(bool value) {
    if (searchByIngredient == value) return;
    _clearUndo();
    _clearManualSearchSelections();
    _resetPageAndScroll(notify: false);
    modeController.updateState(
      (state) => state.copyWith(bookSearchIngredients: value),
      immediate: true,
    );
  }

  void setDensity(RecipeBookDensity value) {
    if (!usesProcessingPaging || _density == value) return;
    _density = value;
    _resetPageAndScroll();
  }

  void setGroup(ProcessingRecipeGroup value) {
    if (!usesProcessingPaging || _group == value) return;
    _group = value;
    _resetPageAndScroll();
  }

  void setOutOfStockOnly(bool value) {
    if (!marketControlsVisible || _outOfStockOnly == value) return;
    _outOfStockOnly = value;
    _resetPageAndScroll();
  }

  void setProfitableOnly(bool value) {
    if (!marketControlsVisible || _profitableOnly == value) return;
    _profitableOnly = value;
    if (value) {
      _marketSort = RecipeBookMarketSort.profitHighToLow;
    } else if (_marketSort.sortsProfit) {
      _marketSort = RecipeBookMarketSort.none;
    }
    _resetPageAndScroll();
  }

  void setMarketSort(RecipeBookMarketSort value) {
    if (!marketControlsVisible ||
        (!profitableOnly && value.sortsProfit) ||
        _marketSort == value) {
      return;
    }
    _marketSort = value;
    _resetPageAndScroll();
  }

  void hideMarket() {
    if (!marketControlsVisible) return;
    _marketChecked = false;
    _outOfStockOnly = false;
    _profitableOnly = false;
    _marketSort = RecipeBookMarketSort.none;
    _marketMessage = null;
    _resetPageAndScroll();
  }

  double? marketStockFor(String name) =>
      _foldedValue(modeController.state.value.market.stock, name);

  RecipeProfitabilityQuote? profitabilityFor(String name) {
    final recipe = recipeDefinitionFor(name);
    if (recipe == null ||
        !_hasProfitabilityMarketIds(recipe, modeController.recipes)) {
      return null;
    }
    return _calculateProfitability(recipe);
  }

  Future<void> checkMarket() async {
    final refresh = checkPrices;
    if (_marketLoading) return;
    if (refresh == null) {
      _marketChecked = true;
      _marketMessage =
          'Market checking is unavailable in this Recipe Book session.';
      notifyListeners();
      return;
    }
    final names = _marketRefreshNames();
    if (names.isEmpty) {
      _marketChecked = true;
      _marketMessage =
          'No market-listed recipe results are visible for this search.';
      notifyListeners();
      return;
    }
    _marketLoading = true;
    _marketChecked = true;
    _marketMessage = 'Checking current market stock...';
    notifyListeners();
    try {
      // Give Flutter enough time to paint the loading controls before a large
      // catalog is resolved and hundreds of market rows begin refreshing.
      await Future<void>.delayed(_marketLoadingLeadIn);
      final result = await refresh(
        PlannerMarketRequest(
          controller: modeController,
          materials: const [],
          materialNames: names,
        ),
      );
      modeController.replaceMarketValues(
        prices: result.prices,
        stock: result.stock,
        tradeMarketIds: result.tradeMarketIds,
        totalTrades: result.totalTrades,
        tradeObservedAt: result.tradeObservedAt,
        observedDailyTrades: result.observedDailyTrades,
        tradeObservationHours: result.tradeObservationHours,
        lastSoldAtEpochSeconds: result.lastSoldAtEpochSeconds,
        unlistedItemNames: result.unlistedItemNames,
        fetchedAt: result.fetchedAt,
        region: result.region,
      );
      _marketMessage = result.summary;
    } on Object catch (error) {
      _marketMessage =
          'Market check failed. Cached stock is still available. $error';
    } finally {
      _marketLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void previousPage() {
    if (_page <= 0) return;
    _page -= 1;
    _resetScroll();
  }

  void nextPage() {
    final current = snapshot;
    if (!current.hasNextPage) return;
    _page += 1;
    _resetScroll();
  }

  void recordScrollOffset(double value) {
    if (!value.isFinite || value < 0) return;
    _scrollOffset = value;
  }

  void openPreview(String name) {
    final exact = _poolExactName(name);
    if (exact == null || _previewName == exact) return;
    _previewName = exact;
    notifyListeners();
  }

  void closePreview() {
    if (_previewName == null) return;
    _previewName = null;
    notifyListeners();
  }

  RecipeBookActivation? activate(String name) {
    if (_activationSuppressed) return null;
    final exact = _poolExactName(name);
    if (exact == null || _foldedEntry(_hiddenRecipeMap(), exact) != null) {
      return null;
    }
    final recipe = recipeDefinitionFor(exact);
    if (recipe == null || !recipe.isCraftable) return null;
    final context = _ingredientSearchMatch(exact, recipe);
    final ingredientSelections = context == null
        ? const <RecipeTargetIngredientSelection>[]
        : _targetIngredientSelections(exact, recipe, context);
    final changed = context == null
        ? switch (callingContext) {
            RecipeBookCallingContext.planner => modeController.selectTarget(
              exact,
            ),
            RecipeBookCallingContext.bonus => _selectBonusTarget(exact),
          }
        : modeController.selectTargetVariant(
            exact,
            variantId: context.variantId,
            bonus: callingContext == RecipeBookCallingContext.bonus,
            ingredientSelections: ingredientSelections,
          );
    if (!changed) return null;
    _clearUndo();
    return RecipeBookActivation(
      exactName: exact,
      context: callingContext,
      mode: modeController.mode,
      variantId: modeController.selectedRecipeVariantId(exact),
    );
  }

  void toggleFavorite(String name) {
    final exact = _poolExactName(name);
    if (exact == null || _foldedEntry(_hiddenRecipeMap(), exact) != null) {
      return;
    }
    final recipe = recipeDefinitionFor(exact);
    if (recipe == null || !recipe.isCraftable) return;
    _clearUndo();
    final current = modeController.state.value.favoriteRecipes;
    final foldedName = _fold(exact);
    final alreadyFavorite = current.any(
      (favorite) => _fold(favorite) == foldedName,
    );
    final distinct = <String, String>{};
    for (final favorite in current) {
      if (_fold(favorite) == foldedName) continue;
      final canonical = _canonicalCraftableName(favorite) ?? favorite;
      distinct.putIfAbsent(_fold(canonical), () => canonical);
    }
    if (!alreadyFavorite) distinct[foldedName] = exact;
    final sorted = distinct.values.toList()..sort(_compareExactNames);
    modeController.updateState(
      (state) => state.copyWith(favoriteRecipes: sorted),
      immediate: true,
    );
  }

  void beginDeleteSelection() {
    if (!deleteToolsEnabled || _deleteSelectionMode) return;
    _clearUndo();
    _showHidden = false;
    _deleteSelectionMode = true;
    _selectedForDeletion.clear();
    _statusMessage = null;
    notifyListeners();
  }

  void cancelDeleteSelection() {
    if (!_deleteSelectionMode && _selectedForDeletion.isEmpty) return;
    _deleteSelectionMode = false;
    _selectedForDeletion.clear();
    _deleteConfirmationVisible = false;
    _deletionError = null;
    notifyListeners();
  }

  void toggleDeleteSelection(String name) {
    if (!deleteSelectionMode) return;
    final exact = _poolExactName(name);
    if (exact == null) return;
    final recipe = recipeDefinitionFor(exact);
    if (recipe == null || !recipe.isCraftable) return;
    final existing = _foldedIn(_selectedForDeletion, exact);
    if (existing == null) {
      _selectedForDeletion.add(exact);
    } else {
      _selectedForDeletion.remove(existing);
    }
    _deletionError = null;
    notifyListeners();
  }

  void requestDeleteConfirmation() {
    if (!deleteSelectionMode || _selectedForDeletion.isEmpty) return;
    _deleteConfirmationVisible = true;
    _deletionError = null;
    notifyListeners();
  }

  void cancelDeleteConfirmation() {
    if (!_deleteConfirmationVisible || _deletionInProgress) return;
    _deleteConfirmationVisible = false;
    _deletionError = null;
    notifyListeners();
  }

  Future<RecipeBookDeletionOutcome?> confirmDeleteSelection() async {
    if (!deleteSelectionMode ||
        !_deleteConfirmationVisible ||
        _deletionInProgress ||
        _selectedForDeletion.isEmpty) {
      return null;
    }
    final names = _selectedForDeletion.toList()..sort(_compareExactNames);
    _deletionInProgress = true;
    _deletionError = null;
    notifyListeners();
    try {
      final outcome = await _deleteSelection(
        RecipeBookDeletionRequest(
          exactNames: List<String>.unmodifiable(names),
          expectedCount: names.length,
        ),
      );
      if (outcome.hiddenCount != names.length ||
          !_sameNameSet(outcome.hiddenNames, names)) {
        throw StateError(
          'Deletion completed for ${outcome.hiddenCount} of ${names.length} selected recipes.',
        );
      }
      _lastDeletion = outcome;
      _statusMessage = outcome.message;
      _deleteSelectionMode = false;
      _selectedForDeletion.clear();
      _deleteConfirmationVisible = false;
      _deletionError = null;
      _page = 0;
      _resetScroll(notify: false);
      return outcome;
    } on Object catch (error) {
      _deletionError =
          'The selected recipes were not hidden. Review the conflict and try again. $error';
      return null;
    } finally {
      _deletionInProgress = false;
      notifyListeners();
    }
  }

  Future<void> undoLastDeletion() async {
    final outcome = _lastDeletion;
    if (outcome == null || _deletionInProgress) return;
    _deletionInProgress = true;
    notifyListeners();
    try {
      await outcome.undo();
      _statusMessage = '${outcome.hiddenCount} processing recipes restored.';
      _lastDeletion = null;
      _deletionError = null;
    } on Object catch (error) {
      _deletionError = 'The deleted recipes could not be restored. $error';
    } finally {
      _deletionInProgress = false;
      notifyListeners();
    }
  }

  void synchronizeDocumentSettings() {
    if (!_synchronizeDocumentSettings()) return;
    notifyListeners();
  }

  bool _synchronizeDocumentSettings() {
    var changed = false;
    if ((!editorOptionsEnabled || totalHiddenItemCount == 0) && _showHidden) {
      _showHidden = false;
      _usageIndex = null;
      changed = true;
    }
    if (!deleteToolsEnabled &&
        (_deleteSelectionMode ||
            _selectedForDeletion.isNotEmpty ||
            _deleteConfirmationVisible)) {
      _deleteSelectionMode = false;
      _selectedForDeletion.clear();
      _deleteConfirmationVisible = false;
      _deletionError = null;
      changed = true;
    }
    return changed;
  }

  List<String> substituteOptions(Ingredient ingredient) {
    if (ingredient.options.isEmpty) return <String>[ingredient.name];
    final recipes = modeController.recipes;
    final unavailable = modeController.owner.assembly
        .plannerRules(modeController.owner.catalog.supportingData)
        .legacyUnavailableItems
        .map(_fold)
        .toSet();
    final seen = <String>{};
    final result = <String>[];
    for (final option in ingredient.options) {
      final entry = _foldedEntry(recipes, option);
      if (entry == null ||
          unavailable.contains(_fold(option)) ||
          !seen.add(_fold(entry.key))) {
        continue;
      }
      result.add(entry.key);
    }
    return result.isEmpty ? <String>[ingredient.name] : result;
  }

  String selectedSubstitute(String parentName, Ingredient ingredient) {
    final options = substituteOptions(ingredient);
    final key = _substituteDocumentKey(parentName, ingredient);
    final sessionKey = _searchSubstituteKey(parentName, ingredient);
    if (!_manualSearchSubstituteKeys.contains(sessionKey) &&
        _previewName != null &&
        _sameName(_previewName!, parentName)) {
      final recipe = recipeDefinitionFor(parentName);
      final context = recipe == null
          ? null
          : _ingredientSearchMatch(parentName, recipe);
      if (context != null &&
          _sameName(context.ingredientName, ingredient.name)) {
        final contextual = _foldedIn(options, context.selectedIngredientName);
        if (contextual != null) return contextual;
      }
    }
    final saved = _foldedValue(
      modeController.state.value.substituteChoices,
      key,
    );
    if (saved != null) {
      final selected = _foldedIn(options, saved);
      if (selected != null) return selected;
    }
    final base = _foldedIn(options, ingredient.name);
    return base ?? options.first;
  }

  void selectSubstitute({
    required String parentName,
    required Ingredient ingredient,
    required String selection,
  }) {
    _clearUndo();
    _manualSearchSubstituteKeys.add(
      _searchSubstituteKey(parentName, ingredient),
    );
    modeController.selectSubstitute(
      parentName: parentName,
      ingredient: ingredient,
      selection: selection,
    );
  }

  List<String> qualityGrades({
    required String parentName,
    required Ingredient ingredient,
    required String selectedName,
  }) {
    return modeController.availableIngredientGrades(
      parentName: parentName,
      selectedName: selectedName,
    );
  }

  String selectedQuality({
    required String parentName,
    required Ingredient ingredient,
    required String selectedName,
  }) {
    return modeController.selectedIngredientGrade(
      parentName: parentName,
      ingredientName: ingredient.name,
      selectedName: selectedName,
    );
  }

  void selectQuality({
    required String parentName,
    required Ingredient ingredient,
    required String grade,
  }) {
    _clearUndo();
    modeController.selectIngredientGrade(
      parentName: parentName,
      ingredientName: ingredient.name,
      grade: grade,
    );
  }

  double substituteRatio(Ingredient ingredient, String selection) {
    final ratio = _foldedValue(ingredient.substituteRatios, selection);
    return ratio == null || ratio < .0001 ? 1 : ratio;
  }

  ProcessingRecipeGroup processingGroupFor(String name, Recipe recipe) {
    final alias = _processingAlias(name);
    final foldedName = _fold(name);
    final text = '$name $alias ${recipe.group ?? ''} ${recipe.method ?? ''}'
        .toLowerCase();
    bool hasAny(Iterable<String> values) =>
        values.any((value) => text.contains(value.toLowerCase()));
    if (foldedName == 'black stone powder') {
      return ProcessingRecipeGroup.alchemy;
    }
    if (RegExp(
      r'^pure (copper|gold|iron|lead|mythril|nickel|noc|platinum|silver|tin|titanium|vanadium|zinc) crystal$',
    ).hasMatch(foldedName)) {
      return ProcessingRecipeGroup.metals;
    }
    if (foldedName == 'concentrated boss crystal' ||
        RegExp(
          r'^concentrated (bheg|dim tree spirit|giath|griffon|karanda|kutum|leebur|muskan|nouver|offin tett|red nose|urugon) crystal$',
        ).hasMatch(foldedName)) {
      return ProcessingRecipeGroup.enhancement;
    }
    if (hasAny(const <String>[
      'Mystic Beast',
      'Mystical Beast',
      'Blessing of Mystic',
      'Remnants of Mystic',
    ])) {
      return ProcessingRecipeGroup.buffs;
    }
    if (hasAny(const <String>[
      'Cup of ',
      'Black Stone',
      'Black Gem',
      'Ancient Spirit Dust',
      'Caphras',
      'Magical Shard',
      'Hard Black Crystal Shard',
      'Sharp Black Crystal Shard',
      'Memory Fragment',
      'Origin of Dark Hunger',
      'Reform Stone',
      'Soul Fragment',
      'Fallen God',
      'Blackstar',
      'Sovereign',
    ])) {
      return ProcessingRecipeGroup.enhancement;
    }
    if (hasAny(const <String>['Lightstone'])) {
      return ProcessingRecipeGroup.lightstones;
    }
    if (hasAny(const <String>[
      'Crystal',
      'Girin',
      'Bonghwang',
      'Haetae',
      "Ah'krad",
      'Olucas',
      'Elkarr',
      'Hoom',
      'Gervish',
      'Macalod',
    ])) {
      return ProcessingRecipeGroup.crystals;
    }
    if (hasAny(const <String>[
      'Draught',
      'Elixir',
      'Perfume',
      'Reagent',
      'Oil',
      'Solvent',
      'Polisher',
    ])) {
      return ProcessingRecipeGroup.alchemy;
    }
    if (hasAny(const <String>[
      'Flour',
      'Dough',
      'Cream',
      'Butter',
      'Cheese',
      'Cooking Honey',
      'Distilled Water',
      'Purified Water',
    ])) {
      return ProcessingRecipeGroup.cooking;
    }
    if (hasAny(const <String>['Plank', 'Plywood', 'Timber', 'Timber Square'])) {
      return ProcessingRecipeGroup.wood;
    }
    if (hasAny(const <String>['Ingot', 'Melted', 'Ore', 'Metal'])) {
      return ProcessingRecipeGroup.metals;
    }
    if (hasAny(const <String>[
      'Fabric',
      'Thread',
      'Yarn',
      'Leather',
      'Hide',
      'Pelt',
    ])) {
      return ProcessingRecipeGroup.cloth;
    }
    return ProcessingRecipeGroup.other;
  }

  void beginPointer(double x, double y) {
    _pointerOrigin = math.Point<double>(x, y);
    _activationSuppressed = false;
  }

  void updatePointer(double x, double y) {
    final origin = _pointerOrigin;
    if (origin == null || _activationSuppressed) return;
    final distance = origin.distanceTo(math.Point<double>(x, y));
    if (distance >= 7) _activationSuppressed = true;
  }

  void endPointer() {
    _pointerOrigin = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activationSuppressed = false;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in modeController.owner.modes.values) {
      controller.state.removeListener(_documentStateChanged);
    }
    modeController.owner.deleteToolsEnabled.removeListener(
      _editorOptionsChanged,
    );
    modeController.owner.marketTax.removeListener(_marketTaxChanged);
    super.dispose();
  }

  bool _selectBonusTarget(String exact) {
    if (_sameName(modeController.state.value.bonusTarget, exact)) return true;
    modeController.updateState(
      (state) => state.copyWith(bonusTarget: exact),
      immediate: true,
    );
    return true;
  }

  RecipeBookUsageIndex _usageIndexForState() {
    final cached = _usageIndex;
    if (cached != null) return cached;
    final recipesByMode = <CraftMode, Map<String, Recipe>>{};
    final hiddenNamesByMode = <CraftMode, Set<String>>{};
    _usageRecipeSources.clear();
    for (final mode in CraftMode.values) {
      final visible = modeController.owner.modes[mode]!.recipes;
      _usageRecipeSources[mode] = visible;
      if (!showHidden) {
        recipesByMode[mode] = visible;
        continue;
      }
      final hidden = _hiddenRecipeMapForMode(mode);
      recipesByMode[mode] = hidden.isEmpty
          ? visible
          : Map<String, Recipe>.unmodifiable(<String, Recipe>{
              ...visible,
              ...hidden,
            });
      if (hidden.isNotEmpty) {
        hiddenNamesByMode[mode] = Set<String>.unmodifiable(
          hidden.keys.map(_fold),
        );
      }
    }
    return _usageIndex = RecipeBookUsageIndex.build(
      recipesByMode: recipesByMode,
      rules: modeController.owner.plannerRules,
      hiddenNamesByMode: hiddenNamesByMode,
    );
  }

  Map<String, Recipe> _hiddenRecipeMap() {
    final state = modeController.state.value;
    final cached = _hiddenRecipeCache;
    if (cached != null &&
        mapEquals(_hiddenRecipeEditsSource, state.recipeEdits) &&
        mapEquals(_hiddenIngredientMetaSource, state.ingredientMeta) &&
        setEquals(_hiddenItemsSource, state.hiddenItems)) {
      return cached;
    }

    final hiddenNames = <String>{
      ...state.hiddenItems.map(_fold),
      for (final entry in state.recipeEdits.entries)
        if (entry.value == null) _fold(entry.key),
    }..remove('');
    if (hiddenNames.isEmpty) {
      _hiddenRecipeEditsSource = state.recipeEdits;
      _hiddenIngredientMetaSource = state.ingredientMeta;
      _hiddenItemsSource = state.hiddenItems;
      return _hiddenRecipeCache = const <String, Recipe>{};
    }

    final restoredEdits = <String, RecipeState?>{
      for (final entry in state.recipeEdits.entries)
        if (!(entry.value == null && hiddenNames.contains(_fold(entry.key))))
          entry.key: entry.value,
    };
    final recoverable = modeController.owner.assembly.assembleRecipes(
      catalog: modeController.owner.catalog.forMode(modeController.mode),
      state: state.copyWith(
        hiddenItems: const <String>[],
        recipeEdits: restoredEdits,
      ),
      supportingData: modeController.owner.catalog.supportingData,
      sharedMetadata: modeController.owner.catalog.alchemy.metadata,
      mode: modeController.mode,
    );
    final result = <String, Recipe>{
      for (final entry in recoverable.entries)
        if (hiddenNames.contains(_fold(entry.key)) && entry.value.isCraftable)
          entry.key: entry.value,
    };
    _hiddenRecipeEditsSource = state.recipeEdits;
    _hiddenIngredientMetaSource = state.ingredientMeta;
    _hiddenItemsSource = state.hiddenItems;
    return _hiddenRecipeCache = Map<String, Recipe>.unmodifiable(result);
  }

  Map<String, Recipe> _hiddenRecipeMapForMode(CraftMode mode) {
    if (mode == modeController.mode) return _hiddenRecipeMap();
    final controller = modeController.owner.modes[mode]!;
    final state = controller.state.value;
    final hiddenNames = <String>{
      ...state.hiddenItems.map(_fold),
      for (final entry in state.recipeEdits.entries)
        if (entry.value == null) _fold(entry.key),
    }..remove('');
    if (hiddenNames.isEmpty) return const <String, Recipe>{};

    final restoredEdits = <String, RecipeState?>{
      for (final entry in state.recipeEdits.entries)
        if (!(entry.value == null && hiddenNames.contains(_fold(entry.key))))
          entry.key: entry.value,
    };
    final recoverable = modeController.owner.assembly.assembleRecipes(
      catalog: modeController.owner.catalog.forMode(mode),
      state: state.copyWith(
        hiddenItems: const <String>[],
        recipeEdits: restoredEdits,
      ),
      supportingData: modeController.owner.catalog.supportingData,
      sharedMetadata: modeController.owner.catalog.alchemy.metadata,
      mode: mode,
    );
    return Map<String, Recipe>.unmodifiable(<String, Recipe>{
      for (final entry in recoverable.entries)
        if (hiddenNames.contains(_fold(entry.key)) && entry.value.isCraftable)
          entry.key: entry.value,
    });
  }

  List<String> _poolNames(Map<String, Recipe> recipes) {
    if (identical(_poolRecipesSource, recipes)) return _poolNamesCache!;
    final values = <String, String>{};
    final candidates = <String>[
      if (callingContext == RecipeBookCallingContext.planner)
        ...modeController.craftableNames,
      if (callingContext == RecipeBookCallingContext.planner &&
          modeController.mode == CraftMode.processing)
        ...recipes.entries
            .where((entry) => isBrowsableRecipeBookReference(entry.value))
            .map((entry) => entry.key)
      else
        ...allowedTargets,
      if (showHidden) ..._hiddenRecipeMap().keys,
    ];
    for (final allowed in candidates) {
      final entry = _foldedEntry(recipes, allowed);
      if (entry == null ||
          (!entry.value.isCraftable &&
              !isBrowsableRecipeBookReference(entry.value))) {
        continue;
      }
      values.putIfAbsent(_fold(entry.key), () => entry.key);
    }
    final result = values.values.toList()..sort(_compareExactNames);
    _poolRecipesSource = recipes;
    return _poolNamesCache = List<String>.unmodifiable(result);
  }

  String? _poolExactName(String name) {
    final folded = _fold(name);
    final recipes = showHidden
        ? <String, Recipe>{...modeController.recipes, ..._hiddenRecipeMap()}
        : modeController.recipes;
    for (final candidate in _poolNames(recipes)) {
      if (_fold(candidate) == folded) return candidate;
    }
    return null;
  }

  String? _canonicalCraftableName(String name) {
    final folded = _fold(name);
    for (final candidate in modeController.craftableNames) {
      if (_fold(candidate) == folded) return candidate;
    }
    return null;
  }

  String? _savedRecipeVariantId(Recipe recipe) => _foldedValue(
    modeController.state.value.recipeVariantChoices,
    recipe.name,
  );

  _RecipeIngredientSearchMatch? _ingredientSearchMatch(
    String name,
    Recipe recipe,
  ) => _evaluateSearch(
    name,
    recipe,
    const <String, List<String>>{},
  ).ingredientContext;

  _RecipeIngredientSearchMatch? _concreteIngredientSearchMatch(
    String name,
    Recipe recipe,
    String query,
  ) {
    if (_manualSearchVariantNames.contains(_fold(name))) return null;
    final formulas = <_RecipeSearchFormula>[];
    if (recipe.variants.isEmpty) {
      formulas.add(
        _RecipeSearchFormula(
          variantId: null,
          variantRouteId: null,
          ingredients: recipe.ingredients,
        ),
      );
    } else {
      final preferredId = recipe.resolvedVariantId(
        _savedRecipeVariantId(recipe),
      );
      final preferred = recipe.variantById(preferredId);
      if (preferred != null) {
        formulas.add(
          _RecipeSearchFormula(
            variantId: preferred.id,
            variantRouteId: preferred.routeId,
            ingredients: preferred.ingredients,
          ),
        );
      }
      for (final variant in recipe.variants) {
        if (preferred != null && _sameName(variant.id, preferred.id)) continue;
        formulas.add(
          _RecipeSearchFormula(
            variantId: variant.id,
            variantRouteId: variant.routeId,
            ingredients: variant.ingredients,
          ),
        );
      }
    }

    final matches = <_RecipeIngredientSearchMatch>[];
    for (var formulaIndex = 0; formulaIndex < formulas.length; formulaIndex++) {
      final formula = formulas[formulaIndex];
      for (
        var ingredientIndex = 0;
        ingredientIndex < formula.ingredients.length;
        ingredientIndex++
      ) {
        final ingredient = formula.ingredients[ingredientIndex];
        final options = substituteOptions(ingredient);
        for (var optionIndex = 0; optionIndex < options.length; optionIndex++) {
          final rank = _searchValueRank(options[optionIndex], query);
          if (rank == null) continue;
          final candidate = _RecipeIngredientSearchMatch(
            variantId: formula.variantId,
            variantRouteId: formula.variantRouteId,
            ingredientName: ingredient.name,
            selectedIngredientName: options[optionIndex],
            rank: rank,
            formulaIndex: formulaIndex,
            ingredientIndex: ingredientIndex,
            optionIndex: optionIndex,
          );
          matches.add(candidate);
        }
      }
    }
    if (matches.isEmpty) return null;
    final bestRank = matches
        .map((candidate) => candidate.rank)
        .reduce(math.min);
    final unique = <String, _RecipeIngredientSearchMatch>{};
    for (final candidate in matches.where(
      (candidate) => candidate.rank == bestRank,
    )) {
      final key = candidate.selectionIdentity;
      final current = unique[key];
      if (current == null || candidate.precedes(current)) {
        unique[key] = candidate;
      }
    }
    if (unique.length != 1) return null;
    return unique.values.single;
  }

  List<RecipeTargetIngredientSelection> _targetIngredientSelections(
    String parentName,
    Recipe recipe,
    _RecipeIngredientSearchMatch context,
  ) {
    final effectiveRecipe = recipe.resolveVariant(context.variantId);
    Ingredient? ingredient;
    for (final candidate in effectiveRecipe.ingredients) {
      if (_sameName(candidate.name, context.ingredientName)) {
        ingredient = candidate;
        break;
      }
    }
    if (ingredient == null) return const <RecipeTargetIngredientSelection>[];
    final options = substituteOptions(ingredient);
    final sessionKey = _searchSubstituteKey(parentName, ingredient);
    final selected = _manualSearchSubstituteKeys.contains(sessionKey)
        ? selectedSubstitute(parentName, ingredient)
        : _foldedIn(options, context.selectedIngredientName) ??
              selectedSubstitute(parentName, ingredient);
    final grade = modeController.selectedIngredientGrade(
      parentName: parentName,
      ingredientName: ingredient.name,
      selectedName: selected,
    );
    return <RecipeTargetIngredientSelection>[
      RecipeTargetIngredientSelection(
        ingredientName: ingredient.name,
        selectedIngredientName: selected,
        grade: grade,
      ),
    ];
  }

  String _substituteDocumentKey(String parentName, Ingredient ingredient) =>
      'recipe:$parentName:${ingredient.substituteGroup ?? ingredient.name}';

  String _searchSubstituteKey(String parentName, Ingredient ingredient) =>
      '${_fold(parentName)}\u0000${_fold(ingredient.substituteGroup ?? ingredient.name)}';

  void _clearManualSearchSelections() {
    _manualSearchSubstituteKeys.clear();
    _manualSearchVariantNames.clear();
  }

  bool _matchesSearch(
    String name,
    Recipe recipe,
    Map<String, List<String>> processingConsumers,
  ) => _evaluateSearch(name, recipe, processingConsumers).matches;

  _RecipeSearchEvaluation _evaluateSearch(
    String name,
    Recipe recipe,
    Map<String, List<String>> processingConsumers,
  ) {
    final query = _fold(_search);
    if (query.isEmpty) return const _RecipeSearchEvaluation(matches: true);
    final direct = <String>[
      name,
      recipe.group ?? '',
      recipe.method ?? '',
      _typeLabel(recipe.type),
    ];
    if (direct.any((value) => _fold(value).contains(query))) {
      return const _RecipeSearchEvaluation(matches: true);
    }
    if (modeController.mode == CraftMode.processing &&
        _processingTermsMatch(_processingSearchTerms(name), query)) {
      return const _RecipeSearchEvaluation(matches: true);
    }
    if (searchByIngredient) {
      var ingredientVisible = false;
      for (final ingredient in _allRecipeIngredients(recipe)) {
        final values = <String>[
          ingredient.name,
          ingredient.substituteGroup ?? '',
          ...ingredient.options,
          ...ingredient.substituteRatios.keys,
        ];
        if (values.any((value) => _fold(value).contains(query))) {
          ingredientVisible = true;
          continue;
        }
        if (modeController.mode == CraftMode.processing &&
            values.any(
              (value) =>
                  _processingTermsMatch(_processingSearchTerms(value), query),
            )) {
          ingredientVisible = true;
        }
      }
      if (!ingredientVisible) {
        return const _RecipeSearchEvaluation(matches: false);
      }
      return _RecipeSearchEvaluation(
        matches: true,
        ingredientContext: _concreteIngredientSearchMatch(name, recipe, query),
      );
    }
    if (modeController.mode != CraftMode.processing) {
      return const _RecipeSearchEvaluation(matches: false);
    }
    for (final consumer
        in processingConsumers[_fold(name)] ?? const <String>[]) {
      if (_sameName(consumer, name)) continue;
      if (_fold(consumer).contains(query) ||
          _processingTermsMatch(_processingSearchTerms(consumer), query)) {
        return const _RecipeSearchEvaluation(matches: true);
      }
    }
    return const _RecipeSearchEvaluation(matches: false);
  }

  List<String> _marketRefreshNames() {
    final recipes = modeController.recipes;
    final pool = _poolNames(recipes);
    final processingConsumers =
        modeController.mode == CraftMode.processing &&
            !searchByIngredient &&
            _search.trim().isNotEmpty
        ? _processingConsumers(recipes)
        : const <String, List<String>>{};
    final processingGroups = usesProcessingPaging
        ? _processingGroups(recipes)
        : const <String, ProcessingRecipeGroup>{};
    final favorites = modeController.state.value.favoriteRecipes
        .map(_fold)
        .toSet();
    final namesByFolded = <String, String>{};
    for (final name in pool) {
      final recipe = recipes[name]!;
      if (!_hasMarketId(name, recipe)) continue;
      if (favoritesOnly && !favorites.contains(_fold(name))) continue;
      if (usesProcessingPaging &&
          _group != ProcessingRecipeGroup.all &&
          processingGroups[name] != _group) {
        continue;
      }
      if (!_matchesSearch(name, recipe, processingConsumers)) continue;
      for (final marketName in _profitabilityCalculator.directMarketItemNames(
        recipe: recipe,
        recipes: recipes,
        state: modeController.state.value,
        rules: modeController.owner.plannerRules,
      )) {
        final item = _foldedEntry(recipes, marketName)?.value;
        if (_hasMarketId(marketName, item)) {
          namesByFolded.putIfAbsent(_fold(marketName), () => marketName);
        }
      }
    }
    final names = namesByFolded.values.toList(growable: false);
    names.sort(_compareExactNames);
    return List<String>.unmodifiable(names);
  }

  bool _knownOutOfStock(String name) {
    final stock = marketStockFor(name);
    return stock != null && stock <= 0;
  }

  int _compareSnapshotNames(
    String left,
    String right,
    Map<String, RecipeProfitabilityQuote> profitability,
  ) {
    if (!marketControlsVisible || _marketSort == RecipeBookMarketSort.none) {
      return _compareExactNames(left, right);
    }
    if (_marketSort.sortsProfit) {
      final leftQuote = profitability[left];
      final rightQuote = profitability[right];
      final leftProfit = leftQuote?.isAvailable == true
          ? leftQuote!.profitPerPiece!
          : null;
      final rightProfit = rightQuote?.isAvailable == true
          ? rightQuote!.profitPerPiece!
          : null;
      final compared = _compareOptionalNumber(
        leftProfit,
        rightProfit,
        ascending: _marketSort == RecipeBookMarketSort.profitLowToHigh,
      );
      if (compared != 0) return compared;
    } else {
      final compared = _compareOptionalNumber(
        marketStockFor(left),
        marketStockFor(right),
        ascending: _marketSort == RecipeBookMarketSort.stockLowToHigh,
      );
      if (compared != 0) return compared;
    }
    return _compareExactNames(left, right);
  }

  RecipeProfitabilityQuote _calculateProfitability(Recipe recipe) =>
      _profitabilityCalculator.calculate(
        recipe: recipe,
        recipes: modeController.recipes,
        state: modeController.state.value,
        rules: modeController.owner.plannerRules,
        marketTax: modeController.owner.documentSnapshot.marketTax,
      );

  bool _hasProfitabilityMarketIds(Recipe recipe, Map<String, Recipe> recipes) =>
      _profitabilityCalculator
          .directMarketItemNames(
            recipe: recipe,
            recipes: recipes,
            state: modeController.state.value,
            rules: modeController.owner.plannerRules,
          )
          .every(
            (name) => _hasMarketId(name, _foldedEntry(recipes, name)?.value),
          );

  bool _hasMarketId(String name, Recipe? recipe) {
    bool valid(String? value) {
      if (value == null) return false;
      final parsed = int.tryParse(value.trim());
      return parsed != null && parsed > 0;
    }

    if (valid(recipe?.marketId)) return true;
    final metadata = _foldedValue(
      modeController.state.value.ingredientMeta,
      name,
    );
    if (valid(metadata?.marketId)) return true;
    return valid(catalogRepository.bundledMarketId(name));
  }

  Map<String, List<String>> _processingConsumers(Map<String, Recipe> recipes) {
    final cached = _processingConsumerIndexes[recipes];
    if (cached != null) return cached;
    final index = <String, Set<String>>{};
    for (final entry in recipes.entries) {
      if (!entry.value.isCraftable) continue;
      for (final ingredient in _allRecipeIngredients(entry.value)) {
        final referenced = <String>{
          ingredient.name,
          ...ingredient.options,
          ...ingredient.substituteRatios.keys,
        };
        for (final value in referenced) {
          final folded = _fold(value);
          if (folded.isEmpty) continue;
          index.putIfAbsent(folded, () => <String>{}).add(entry.key);
        }
      }
    }
    final immutable = Map<String, List<String>>.unmodifiable({
      for (final entry in index.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
    _processingConsumerIndexes[recipes] = immutable;
    return immutable;
  }

  Map<String, ProcessingRecipeGroup> _processingGroups(
    Map<String, Recipe> recipes,
  ) {
    final cached = _processingGroupIndexes[recipes];
    if (cached != null) return cached;
    final groups = Map<String, ProcessingRecipeGroup>.unmodifiable({
      for (final entry in recipes.entries)
        entry.key: processingGroupFor(entry.key, entry.value),
    });
    _processingGroupIndexes[recipes] = groups;
    return groups;
  }

  Iterable<String> _processingSearchTerms(
    String name, {
    CraftMode? mode,
  }) sync* {
    final alias = _processingAlias(name);
    if (alias.isNotEmpty) yield alias;
    final metadataController =
        modeController.owner.modes[mode ?? modeController.mode]!;
    final metadata = _foldedValue(
      metadataController.state.value.ingredientMeta,
      name,
    );
    final keywords = metadata?.searchKeywords;
    if (keywords != null) {
      yield* keywords.split(RegExp(r'[,;\r\n]+')).map((value) => value.trim());
    }
  }

  String _processingAlias(String name) =>
      _foldedValue(catalogRepository.snapshot.processing.searchAliases, name) ??
      '';

  bool _processingTermsMatch(Iterable<String> terms, String query) {
    final tokens = query
        .split(RegExp(r'[\s\-_/:;,\.\[\]\(\)\\]+'))
        .where((token) => token.length >= 2)
        .toList(growable: false);
    return terms.any((term) {
      final folded = term.trim().toLowerCase();
      if (folded.isEmpty) return false;
      if (folded.contains(query) || query.contains(folded)) return true;
      return tokens.any(folded.contains);
    });
  }

  void _resetPageAndScroll({bool notify = true}) {
    _page = 0;
    _resetScroll(notify: notify);
  }

  void _resetScroll({bool notify = true}) {
    _scrollOffset = 0;
    _scrollResetRevision += 1;
    if (notify) notifyListeners();
  }

  void _clearUndo() {
    _lastDeletion = null;
  }

  void _documentStateChanged() {
    if (_usageIndex != null &&
        CraftMode.values.any(
          (mode) => !identical(
            _usageRecipeSources[mode],
            modeController.owner.modes[mode]!.recipes,
          ),
        )) {
      _usageIndex = null;
      _usageRecipeSources.clear();
    }
    if (_documentRefreshScheduled) return;
    _documentRefreshScheduled = true;
    // A ModeFeatureController notifies while its new state is committed but
    // before its derived plan is replaced. Defer the notification until that
    // commit has fully unwound. The next build owns projection work; eagerly
    // constructing [snapshot] here would calculate every reverse-use count
    // twice. [snapshot] already bounds its displayed page without mutating
    // this controller.
    scheduleMicrotask(() {
      _documentRefreshScheduled = false;
      if (_disposed) return;
      _synchronizeDocumentSettings();
      final exactPreview = _previewName == null
          ? null
          : _poolExactName(_previewName!);
      if (_previewName != null && exactPreview == null) _previewName = null;
      notifyListeners();
    });
  }

  void _editorOptionsChanged() {
    _usageIndex = null;
    _synchronizeDocumentSettings();
    notifyListeners();
  }

  void _marketTaxChanged() => _documentStateChanged();

  Set<String> get _estimatedOutputNames {
    final cached = _estimatedOutputNamesCache;
    if (cached != null) return cached;
    final review =
        modeController.owner.catalog.supportingData['edaniaPartIiReview'];
    final inferred = review is Map<String, Object?>
        ? review['inferredProcessingOutputs']
        : null;
    final names = <String>{};
    if (inferred is List<Object?>) {
      for (final record in inferred) {
        if (record is! Map<String, Object?>) continue;
        final name = record['name'];
        if (name is String && name.trim().isNotEmpty) names.add(_fold(name));
      }
    }
    return _estimatedOutputNamesCache = Set<String>.unmodifiable(names);
  }
}

Recipe? _withResolvedAcquisitionSource({
  required String name,
  required Recipe? recipe,
  required ResolvedSourceInfo source,
}) {
  final sourceNote = source.sourceNote ?? recipe?.sourceNote;
  final vendor = source.vendor ?? recipe?.vendor;
  final location = source.location ?? recipe?.location;
  final npcPrice = source.npcPrice > 0
      ? source.npcPrice
      : recipe?.npcPrice ?? 0;
  if (recipe == null &&
      sourceNote == null &&
      vendor == null &&
      location == null &&
      npcPrice <= 0) {
    return null;
  }
  if (recipe != null &&
      sourceNote == recipe.sourceNote &&
      vendor == recipe.vendor &&
      location == recipe.location &&
      npcPrice == recipe.npcPrice) {
    return recipe;
  }
  return Recipe(
    name: recipe?.name ?? name,
    type: recipe?.type ?? 'gathered',
    baseOutput: recipe?.baseOutput ?? 1,
    group: recipe?.group,
    method: recipe?.method,
    ingredients: recipe?.ingredients ?? const <Ingredient>[],
    marketId: recipe?.marketId,
    sourceNote: sourceNote,
    vendor: vendor,
    location: location,
    npcPrice: npcPrice,
    qualityBase: recipe?.qualityBase,
    qualityGrade: recipe?.qualityGrade,
    outputMinimum: recipe?.outputMinimum,
    outputMaximum: recipe?.outputMaximum,
    role: recipe?.role ?? RecipeRole.production,
    variants: recipe?.variants ?? const <RecipeVariant>[],
    defaultVariantId: recipe?.defaultVariantId,
  );
}

/// Default all-or-nothing Processing hide/delete orchestration.
///
/// Every selected name passes through the shared state transaction before the
/// assembled snapshot is committed. The source document is retained as the
/// session undo value.
final class TransactionalRecipeBookDeletion {
  const TransactionalRecipeBookDeletion({required this.modeController});

  final ModeFeatureController modeController;

  Future<RecipeBookDeletionOutcome> call(
    RecipeBookDeletionRequest request,
  ) async {
    if (modeController.mode != CraftMode.processing ||
        !modeController.owner.documentSnapshot.showDeleteTools) {
      throw const StateTransactionFailure(
        'delete-tools-disabled',
        'Processing delete tools are disabled.',
      );
    }
    if (request.exactNames.length != request.expectedCount ||
        request.expectedCount <= 0) {
      throw const StateTransactionFailure(
        'selection-count-changed',
        'The deletion selection changed before confirmation.',
      );
    }
    final selected = request.exactNames.map(_fold).toSet();
    if (selected.length != request.expectedCount) {
      throw const StateTransactionFailure(
        'duplicate-selection',
        'The deletion selection contains duplicate recipes.',
      );
    }
    final available = modeController.craftableNames;
    final fallback = available.where((name) => !selected.contains(_fold(name)));
    if (fallback.isEmpty) {
      throw const StateTransactionFailure(
        'no-repair-target',
        'At least one Processing recipe must remain as a repair target.',
      );
    }

    final owner = modeController.owner;
    final before = owner.documentSnapshot;
    var working = before;
    var pending = List<String>.of(request.exactNames);
    final transactions = const PlannerStateTransactions();
    StateTransactionFailure? lastFailure;
    while (pending.isNotEmpty) {
      var progressed = false;
      final deferred = <String>[];
      for (final name in pending) {
        try {
          final result = transactions.hideRecipeBookItem(
            state: working,
            mode: CraftMode.processing,
            itemName: name,
            fallbackTarget: fallback.first,
            additionallyHiddenRecipes: request.exactNames,
          );
          working = result.state;
          progressed = true;
        } on StateTransactionFailure catch (failure) {
          lastFailure = failure;
          deferred.add(name);
        }
      }
      if (!progressed) {
        throw lastFailure ??
            const StateTransactionFailure(
              'delete-conflict',
              'The selected recipes could not be hidden transactionally.',
            );
      }
      pending = deferred;
    }

    await owner.updateDocumentDurably((_) => working);
    final hidden = List<String>.unmodifiable(
      List<String>.of(request.exactNames)..sort(_compareExactNames),
    );
    return RecipeBookDeletionOutcome(
      hiddenNames: hidden,
      message:
          '${hidden.length} processing ${hidden.length == 1 ? 'recipe' : 'recipes'} hidden.',
      undo: () async {
        await owner.updateDocumentDurably((current) {
          final source = current.processing;
          final remainingHidden = Set<String>.of(source.hiddenItems)
            ..removeWhere((name) => _containsFolded(hidden, name));
          final committed = working.processing;
          final restored = source.copyWith(
            hiddenItems: remainingHidden,
            target: _sameName(source.target, committed.target)
                ? before.processing.target
                : source.target,
            bonusTarget: _sameName(source.bonusTarget, committed.bonusTarget)
                ? before.processing.bonusTarget
                : source.bonusTarget,
          );
          return _replaceMode(current, CraftMode.processing, restored);
        });
      },
    );
  }
}

PlannerState _replaceMode(
  PlannerState state,
  CraftMode mode,
  ModeState value,
) => switch (mode) {
  CraftMode.alchemy => state.copyWith(alchemy: value),
  CraftMode.cooking => state.copyWith(cooking: value),
  CraftMode.processing => state.copyWith(processing: value),
};

String _typeLabel(String type) => type
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _fold(String value) => value.trim().toLowerCase();

bool _sameName(String left, String right) => _fold(left) == _fold(right);

int _compareExactNames(String left, String right) {
  final folded = _fold(left).compareTo(_fold(right));
  return folded != 0 ? folded : left.compareTo(right);
}

int _compareOptionalNumber(
  double? left,
  double? right, {
  required bool ascending,
}) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return ascending ? left.compareTo(right) : right.compareTo(left);
}

MapEntry<String, T>? _foldedEntry<T>(Map<String, T> values, String name) {
  final exact = values[name];
  if (exact != null) return MapEntry<String, T>(name, exact);
  final folded = _fold(name);
  for (final entry in values.entries) {
    if (_fold(entry.key) == folded) return entry;
  }
  return null;
}

T? _foldedValue<T>(Map<String, T> values, String name) =>
    _foldedEntry(values, name)?.value;

String? _foldedIn(Iterable<String> values, String name) {
  final folded = _fold(name);
  for (final value in values) {
    if (_fold(value) == folded) return value;
  }
  return null;
}

bool _containsFolded(Iterable<String> values, String name) =>
    _foldedIn(values, name) != null;

int? _searchValueRank(String value, String foldedQuery) {
  final candidate = _fold(value);
  if (candidate == foldedQuery) return 0;
  if (candidate.startsWith(foldedQuery)) return 1;
  if (candidate.contains(foldedQuery)) return 2;
  return null;
}

final class _RecipeSearchFormula {
  const _RecipeSearchFormula({
    required this.variantId,
    required this.variantRouteId,
    required this.ingredients,
  });

  final String? variantId;
  final String? variantRouteId;
  final List<Ingredient> ingredients;
}

final class _RecipeSearchEvaluation {
  const _RecipeSearchEvaluation({
    required this.matches,
    this.ingredientContext,
  });

  final bool matches;
  final _RecipeIngredientSearchMatch? ingredientContext;
}

final class _RecipeIngredientSearchMatch {
  const _RecipeIngredientSearchMatch({
    required this.variantId,
    required this.variantRouteId,
    required this.ingredientName,
    required this.selectedIngredientName,
    required this.rank,
    required this.formulaIndex,
    required this.ingredientIndex,
    required this.optionIndex,
  });

  final String? variantId;
  final String? variantRouteId;
  final String ingredientName;
  final String selectedIngredientName;
  final int rank;
  final int formulaIndex;
  final int ingredientIndex;
  final int optionIndex;

  String get selectionIdentity => <String>[
    _fold(variantRouteId ?? variantId ?? 'base'),
    _fold(ingredientName),
    _fold(selectedIngredientName),
  ].join('\u0000');

  bool precedes(_RecipeIngredientSearchMatch other) {
    if (rank != other.rank) return rank < other.rank;
    if (formulaIndex != other.formulaIndex) {
      return formulaIndex < other.formulaIndex;
    }
    if (ingredientIndex != other.ingredientIndex) {
      return ingredientIndex < other.ingredientIndex;
    }
    return optionIndex < other.optionIndex;
  }
}

Iterable<Ingredient> _allRecipeIngredients(Recipe recipe) sync* {
  yield* recipe.ingredients;
  for (final variant in recipe.variants) {
    yield* variant.ingredients;
  }
}

bool _sameNameSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.map(_fold).toSet();
  final rightSet = right.map(_fold).toSet();
  return setEquals(leftSet, rightSet);
}
