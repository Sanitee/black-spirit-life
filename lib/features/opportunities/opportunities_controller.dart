import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../app/state/planner_application_controller.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/market/market_response_guard.dart';
import '../../data/market/shared_market_repository.dart';
import '../../data/opportunities/exchange_catalog.dart';
import '../../data/opportunities/market_eligibility.dart';
import '../../data/opportunities/opportunity_market_cache_store.dart';
import '../../data/opportunities/opportunity_market_observation_store.dart';
import '../../data/opportunities/opportunity_market_service.dart';
import '../../domain/catalog/temporarily_archived_items.dart';
import '../../domain/market/market_calculations.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/opportunities/exchange_calculator.dart';
import '../../domain/opportunities/exchange_models.dart';
import '../../domain/opportunities/opportunity_best_use.dart';
import '../../domain/opportunities/opportunity_calculator.dart';
import '../../domain/planner/planner_models.dart' as planning;
import '../../domain/state/planner_state.dart';
import '../planner/planner_contracts.dart'
    show RecipeBookCallingContext, PlannerTargetRequest;
import '../recipe_book/recipe_book_controller.dart';
import 'opportunities_preferences.dart';

/// One source formula inspected independently of the selected opportunity.
/// Rare-result pages retain the source inputs but never reuse its normal yield.
final class OpportunityRecipeInspection {
  const OpportunityRecipeInspection({
    required this.itemName,
    required this.sourceMode,
    required this.recipe,
    required this.quote,
    required this.mastery,
    required this.isRareOutput,
  });

  final String itemName;
  final CraftMode sourceMode;
  final Recipe recipe;
  final OpportunityQuote quote;
  final int mastery;
  final bool isRareOutput;
}

/// Basic quotes and requested order details have independent completion.
/// Unrequested depth is not a failed request or a confirmed zero count.
final class OpportunityMarketLoadStatus {
  const OpportunityMarketLoadStatus({
    required this.total,
    required this.loaded,
    required this.failed,
    required this.loading,
    required this.blocked,
  });

  final int total;
  final int loaded;
  final int failed;
  final bool loading;
  final bool blocked;
  bool get requested => total > 0;
  bool get complete => requested && loaded == total;
}

class OpportunitiesController extends ChangeNotifier {
  OpportunitiesController({
    required this.appController,
    required this.catalog,
    required Directory directory,
    this.autoCheck = false,
    this.prefetchAll = false,
    DateTime Function()? clock,
    OpportunityMarketService Function(String region)? serviceFactory,
    OpportunityMarketObservationStore? observationStore,
    OpportunityMarketCacheStore? marketCacheStore,
    this.sharedMarket,
    @visibleForTesting
    Timer Function(Duration, void Function())? recoveryTimerFactory,
  }) : clock = clock ?? DateTime.now,
       _recoveryTimerFactory = recoveryTimerFactory ?? Timer.new,
       _serviceFactory =
           serviceFactory ??
           ((region) => OpportunityMarketService(region: region)),
       _preferencesStore = OpportunitiesPreferenceStore(directory),
       _marketCache =
           marketCacheStore ??
           OpportunityMarketCacheStore(directory: directory, utcNow: clock),
       _observations =
           observationStore ??
           OpportunityMarketObservationStore(
             directory: directory,
             utcNow: clock,
           ) {
    for (final mode in appController.modes.values) {
      mode.state.addListener(_plannerChanged);
    }
    appController.marketTax.addListener(_plannerChanged);
    ready = _load();
  }

  static const maxMarketAge = Duration(hours: 3);
  // Keep saved calculations usable while an on-demand update is in progress.
  // Network freshness is deliberately separate from display/valuation age.
  static const automaticMarketAge = sharedMarketFreshness;
  // Browsing this workspace is not a five-minute refresh gesture. Only a
  // genuine tab entry/startup uses the shorter shared freshness policy.
  static const inWorkspaceMarketAge = Duration(minutes: 30);
  final PlannerApplicationController appController;
  final bool autoCheck;
  final bool prefetchAll;
  final CatalogRepository catalog;
  RecipeBookController? _itemInfoController;

  // One read-only reference session for the workspace and its nested dialogs.
  // No price-check callback: showing item information never fetches market data.
  RecipeBookController get itemInfoController =>
      _itemInfoController ??= RecipeBookController(
        modeController: modeController,
        catalogRepository: catalog,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );

  /// Use live, user-edited definitions, never resurrect a bundled/deleted recipe
  /// or silently substitute a rare result's base recipe.
  PlannerTargetRequest? plannerTargetFor(
    String name, {
    CraftMode? mode,
    String? variantId,
  }) {
    final folded = name.trim().toLowerCase();
    if (folded.isEmpty) return null;
    final modes = mode == null
        ? [
            preferences.mode,
            ...CraftMode.values.where((m) => m != preferences.mode),
          ]
        : [mode];
    for (final candidateMode in modes) {
      final recipe = appController.modes[candidateMode]!.recipes.values
          .where((recipe) => recipe.name.trim().toLowerCase() == folded)
          .firstOrNull;
      if (recipe == null ||
          !recipe.isCraftable ||
          isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId)) {
        continue;
      }
      if (variantId != null && recipe.variantById(variantId) == null) {
        return null;
      }
      return PlannerTargetRequest(
        exactName: recipe.name,
        mode: candidateMode,
        variantId: variantId,
      );
    }
    return null;
  }

  final SharedMarketRepository? sharedMarket;
  final DateTime Function() clock;
  final Timer Function(Duration, void Function()) _recoveryTimerFactory;
  final OpportunityMarketService Function(String) _serviceFactory;
  final OpportunitiesPreferenceStore _preferencesStore;
  final OpportunityMarketObservationStore _observations;
  final OpportunityMarketCacheStore _marketCache;
  final _calculator = const OpportunityCalculator();
  late final Future<void> ready;
  OpportunitiesPreferences preferences = OpportunitiesPreferences();
  final Map<String, Map<String, OpportunityMarketItem>> _regionItems = {};
  List<OpportunityQuote> quotes = [];
  List<OpportunityBestUseQuote> bestUseQuotes = [];
  final Map<CraftMode, _BestUseSource> _bestUseSources = {};
  Object? _bestUseCalculationKey;
  Object? _bestUseContextKey;
  Object? _bestUseSuggestionKey;
  List<String> _bestUseSuggestions = const [];
  int _bestUseRevision = 0;
  bool _calculatingBestUse = false;
  Future<void>? _bestUseCalculation;
  _BestUseCalculationInput? _pendingBestUseCalculation;
  Set<String> _bestUseDepthIds = {};
  Map<String, Recipe> recipes = {};
  bool loading = true;
  bool scanning = false;
  bool _disposed = false;
  final Map<String, String> _regionNotices = {};
  // A failed quote does not invalidate a successful book (or vice versa).
  // Retain the prior receipt time so an old cache replay cannot erase a
  // failed explicit refresh. Failures are session state, never saved prices.
  final Map<SharedMarketPartKey, DateTime?> _marketFailures = {};
  String? get notice =>
      _recoveryNotice ??
      _regionNotices[preferences.region] ??
      _marketFailureNotice;
  set notice(String? value) => _setRegionNotice(preferences.region, value);
  String? saveError;
  String progress = '';
  double? progressFraction;
  int get failedItems =>
      _regionFailureParts.map((part) => part.key.itemId).toSet().length;

  Iterable<SharedMarketPartKey> get _regionFailureParts =>
      _marketFailures.keys.where(
        (part) =>
            part.key.region == preferences.region &&
            (part.part == SharedMarketPart.quote ||
                _activeDepthIds.contains(part.key.itemId)),
      );

  String? get _marketFailureNotice {
    final parts = _regionFailureParts.toList();
    if (parts.isEmpty) return null;
    final subject = parts.every((part) => part.part == SharedMarketPart.quote)
        ? 'Prices'
        : parts.every((part) => part.part == SharedMarketPart.orderBook)
        ? 'Buy/sell orders'
        : 'Market data';
    final count = parts.map((part) => part.key.itemId).toSet().length;
    return '$subject didn’t load for $count ${count == 1 ? 'item' : 'items'}. Try Refresh.';
  }

  void _setRegionNotice(String region, String? value) {
    if (value == null) {
      _regionNotices.remove(region);
    } else {
      _regionNotices[region] = value;
    }
  }

  /// Latest successful receipt in the selected region, not a scan start time.
  DateTime? get lastCheck {
    DateTime? latest;
    for (final item in market.items.values) {
      for (final at in [item.quoteFetchedAt, item.bookFetchedAt]) {
        if (at != null &&
            !at.isAfter(clock()) &&
            (latest == null || at.isAfter(latest))) {
          latest = at;
        }
      }
    }
    return latest;
  }

  /// Quotes and books expire independently from their original receipt times.
  Duration get cachedMarketMaxAge => maxMarketAge;

  /// The next queued start owned by this scan, not a new full-refresh deadline.
  Duration get activeDispatchWait => !scanning
      ? Duration.zero
      : sharedMarket?.activeDispatchWait(
              region: _scanRegion ?? preferences.region,
              parts: _scanParts,
            ) ??
            Duration.zero;

  /// The toolbar checks this again on activation; a displayed countdown never
  /// grants permission to ignore another tab's starts or a market pause.
  SharedMarketRefreshReadiness get refreshReadiness {
    final broker = sharedMarket;
    if (broker == null) return const SharedMarketRefreshReadiness();
    final region = preferences.region;
    final recovery = {
      ..._regionFailureParts,
      ...?_recoveryCycles[region]?.targets.where(
        (part) =>
            _needsMarketPart(part) &&
            (part.part == SharedMarketPart.quote ||
                _activeDepthIds.contains(part.key.itemId)),
      ),
    };
    if (recovery.isNotEmpty) {
      for (final id in _selectionIds()) {
        final part = _marketPart(region, id, SharedMarketPart.quote);
        if (!_partIsFresh(part, _regionItems[region]?[id])) recovery.add(part);
      }
      return broker.refreshReadiness(
        region: region,
        quoteKeys: recovery
            .where((p) => p.part == SharedMarketPart.quote)
            .map((p) => p.key),
        bookKeys: recovery
            .where((p) => p.part == SharedMarketPart.orderBook)
            .map((p) => p.key),
      );
    }
    final quoteIds = prefetchAll
        ? _allRefreshTargets().values.expand((ids) => ids).toSet()
        : _selectionIds();
    return broker.refreshReadiness(
      region: region,
      quoteKeys: {
        ...quoteIds,
        for (final id in _activeDepthIds)
          if (!(_regionItems[region]?[id]?.quoteIsFresh(
                clock(),
                maxMarketAge,
              ) ??
              false))
            id,
      }.map((id) => SharedMarketKey(region: region, itemId: id)),
      bookKeys: _activeDepthIds.map(
        (id) => SharedMarketKey(region: region, itemId: id),
      ),
    );
  }

  Timer? _recalculateTimer;
  Timer? _saveTimer;
  Timer? _autoCheckTimer;
  Timer? _marketPublishTimer;
  Timer? _cacheExpiryTimer;
  Timer? _cacheSaveTimer;
  Timer? _sharedObservationTimer;
  StreamSubscription<SharedMarketReceipt>? _sharedSubscription;
  final Map<String, Map<String, OpportunityMarketItem>> _sharedObservations =
      {};
  final Map<String, Set<String>> _freshReceipts = {};
  Future<void> _cacheTail = Future.value();
  bool _cacheDirty = false;
  int _cacheRevision = 0;
  int _cacheQueuedRevision = -1;
  int _flushDepth = 0;
  bool _marketPausedForFlush = false;
  String? _scanRegion;
  bool _scanningAll = false;
  bool _pendingAutoCheckAll = false;
  Duration? _pendingAutoCheckMaxAge;
  int _selectionRevision = 0;
  Future<void> _saveTail = Future.value();
  Future<void> _observationTail = Future.value();
  bool _preferencesDirty = false;
  int _preferenceRevision = 0;
  Completer<void>? _scanCompletion;
  MarketCancellationController? _cancellation;
  Future<void>? _calculation;
  _CalculationInput? _pendingCalculation;
  bool _calculating = false;
  int _calculationRevision = 0;
  int _marketRevision = 0;
  bool _needsFullCalculation = true;
  final Map<String, Set<String>> _changedMarketIds = {};
  Map<String, Recipe>? _dependencyRecipes;
  (CraftMode, ModeState)? _assembledSource;
  final Map<String, Set<String>> _recipeMarketIds = {};
  final Map<String, String?> _outputMarketIds = {};
  Set<String> _detailPriorityIds = {};
  final Map<String, Set<String>> _summaryIds = {};
  Set<String> _inspectedDepthIds = {};
  Set<String> _explicitDepthIds = {};
  Set<String> _demandDepthIds = {};
  final Map<Object, (String, CraftMode)> _cardMarketInterests = Map.identity();
  Set<String> _cardDepthIds = {};
  Timer? _cardInterestTimer;
  Duration? _cardEntryMaxAge;
  Set<SharedMarketPartKey> _scanParts = {};
  SharedMarketRequestScope? _scanScope;
  bool _scanIsDepth = false;
  bool _scopeCancellation = false;
  bool _pendingDepthCheck = false;
  Duration? _pendingDepthMaxAge;
  bool _forceDepthCheck = false;
  bool _depthUserInitiated = false;
  Future<void>? _depthWork;
  _ManualMarketRefresh? _manualMarketRefresh;
  bool _workspaceActive = false;
  Object? _calculationKey;
  Object? _quoteContextKey;
  bool get calculating => _calculating || _calculatingBestUse;
  bool get calculatingBestUse => _calculatingBestUse;
  Future<void> get calculationSettled =>
      Future.wait<void>([?_calculation, ?_bestUseCalculation]);
  final Set<String> _rateLimitedRegions = {};
  final Map<String, DateTime> _fallbackBlockedUntil = {};
  final Map<String, MarketRequestPause> _fallbackPauses = {};
  final Map<String, _MarketRecoveryCycle> _recoveryCycles = {};
  final Set<String> _automaticStoppedRegions = {};
  Timer? _recoveryTimer;
  String? _recoveryTimerRegion;
  DateTime? _recoveryTimerDueAt;
  int _recoveryGeneration = 0;
  final Map<String, int> _regionConcurrency = {};
  final Map<CraftMode, (ModeState, Map<String, Recipe>)> _inspectionRecipes =
      {};

  ModeFeatureController get modeController =>
      appController.modes[preferences.mode]!;
  ModeState get state => modeController.state.value;
  OpportunityMarketSnapshot get market => OpportunityMarketSnapshot(
    region: preferences.region,
    items: _regionItems[preferences.region] ?? {},
  );

  /// Raw receipts can reach the screen before a coherent financial calculation
  /// finishes. They do not replace any of that calculation's cost/profit data.
  OpportunityMarketItem? outputMarketFor(String recipeName, {CraftMode? mode}) {
    if (mode != null) {
      final source = _bestUseSourceFor(mode).recipes;
      final id = _calculator.marketItemId(
        name: recipeName,
        recipes: source,
        rules: appController.plannerRules,
      );
      return id == null ? null : _regionItems[preferences.region]?[id];
    }
    _prepareMarketDependencies();
    final id = _outputMarketIds[recipeName];
    return id == null ? null : _regionItems[preferences.region]?[id];
  }

  Recipe? liveRecipeFor(String name, {CraftMode? preferredMode}) {
    final folded = name.trim().toLowerCase();
    final preferred = preferredMode ?? preferences.mode;
    for (final mode in [
      preferred,
      ...CraftMode.values.where((mode) => mode != preferred),
    ]) {
      final recipe = _bestUseSourceFor(mode).recipes.values
          .where((recipe) => recipe.name.trim().toLowerCase() == folded)
          .firstOrNull;
      if (recipe != null &&
          recipe.isCraftable &&
          !isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId)) {
        return recipe;
      }
    }
    return null;
  }

  Set<String> get _activeDepthIds => {
    ..._inspectedDepthIds,
    ..._explicitDepthIds,
    ..._demandDepthIds,
    ..._cardDepthIds,
    ..._bestUseDepthIds,
  };

  OpportunityMarketLoadStatus get summaryStatus => _loadStatus(
    _summaryIds[preferences.region] ?? _selectionIds(),
    SharedMarketPart.quote,
  );

  OpportunityMarketLoadStatus get detailStatus =>
      _loadStatus(_activeDepthIds, SharedMarketPart.orderBook);

  bool get summaryComplete => summaryStatus.complete;

  String? get summaryNotice =>
      summaryComplete ? _regionNotices[preferences.region] : notice;

  String? get detailNotice {
    final status = detailStatus;
    if (!status.requested || status.complete) return null;
    if (status.blocked) {
      return _recoveryCycles[preferences.region]?.protectionWasEarlier == true
          ? 'Market details were blocked earlier. Prices are kept.'
          : 'Market details are blocked. Prices are kept.';
    }
    final cycle = _recoveryCycles[preferences.region];
    if (cycle?.waiting == true) return _recoveryNotice;
    if (status.failed > 0) {
      return 'Order details didn’t load for ${status.failed} '
          '${status.failed == 1 ? 'item' : 'items'}. Prices are kept.';
    }
    return null;
  }

  /// Startup can warm basic quotes while this workspace is offstage. Demand
  /// books belong only to the visible workspace, not a saved sort preference.
  void setWorkspaceActive(bool active) {
    if (_disposed || _workspaceActive == active) return;
    _workspaceActive = active;
    if (!active) {
      if (preferences.section == 'best-use') {
        _autoCheckTimer?.cancel();
        _pendingAutoCheckAll = false;
        _pendingAutoCheckMaxAge = null;
        _selectionRevision++;
      }
      _inspectedDepthIds = {};
      _explicitDepthIds = {};
      _detailPriorityIds = {};
      _cardDepthIds = {};
      _cardEntryMaxAge = null;
      _cardInterestTimer?.cancel();
      _cardInterestTimer = null;
    }
    _updateDemandDepthScope();
    _updateBestUseDepthScope();
    if (!active) _depthScopeChanged();
    if (active) _scheduleCardInterestCheck();
  }

  /// Lazy list cards own only their output's orders. Registration is safe from
  /// widget lifecycle methods: reconciliation and notifications happen later.
  void setCardMarketInterest(
    Object owner, {
    required String recipeName,
    required CraftMode mode,
  }) {
    if (_disposed) return;
    final interest = (recipeName, mode);
    if (_cardMarketInterests[owner] == interest) return;
    _cardMarketInterests[owner] = interest;
    _scheduleCardInterestCheck();
  }

  void releaseCardMarketInterest(Object owner) {
    if (_disposed || _cardMarketInterests.remove(owner) == null) return;
    _scheduleCardInterestCheck();
  }

  void _scheduleCardInterestCheck() {
    _cardInterestTimer?.cancel();
    _cardInterestTimer = null;
    if (_disposed ||
        !_workspaceActive ||
        _flushDepth > 0 ||
        _marketPausedForFlush) {
      return;
    }
    _cardInterestTimer = Timer(
      const Duration(milliseconds: 150),
      _reconcileCardMarketInterests,
    );
  }

  void _reconcileCardMarketInterests() {
    _cardInterestTimer = null;
    if (_disposed || loading || _flushDepth > 0 || _marketPausedForFlush) {
      return;
    }
    final ids = <String>{};
    if (_workspaceActive && preferences.section == 'crafting') {
      final eligibleNames = {
        for (final quote in visibleQuotes) quote.recipeName,
      };
      for (final (name, mode) in _cardMarketInterests.values) {
        if (mode != preferences.mode || !eligibleNames.contains(name)) continue;
        final id = _outputMarketIds[name];
        if (id != null && isOpportunityMarketRequestEligible(id)) ids.add(id);
      }
    } else if (_workspaceActive && preferences.section == 'best-use') {
      final visible = {
        for (final use in visibleBestUseQuotes)
          (use.recipe.name, use.mode): use,
      };
      for (final interest in _cardMarketInterests.values) {
        final use = visible[interest];
        if (use == null) continue;
        final id = _bestUseOutputId(use);
        if (id != null) ids.add(id);
      }
    }
    final added = ids.difference(_cardDepthIds).isNotEmpty;
    if (!setEquals(ids, _cardDepthIds)) {
      _cardDepthIds = ids;
      _depthScopeChanged(schedule: false, preserveStoppedRecovery: true);
    }
    if (ids.isEmpty) return;
    // Tab activation can precede the first card build. Consume that stricter
    // check only after its initial debounced batch exists; later scrolling uses
    // the ordinary thirty-minute age.
    final entryMaxAge = _cardEntryMaxAge;
    _cardEntryMaxAge = null;
    if (added || entryMaxAge != null) {
      unawaited(_queueDepthCheck(maxAge: entryMaxAge ?? inWorkspaceMarketAge));
    }
  }

  OpportunityMarketLoadStatus _loadStatus(
    Set<String> ids,
    SharedMarketPart kind,
  ) {
    final region = preferences.region;
    final parts = ids.map((id) => _marketPart(region, id, kind)).toSet();
    final missing = parts.where(_needsMarketPart).toSet();
    final pause = sharedMarket?.pauseFor(region) ?? _fallbackPauses[region];
    return OpportunityMarketLoadStatus(
      total: parts.length,
      loaded: parts.length - missing.length,
      failed: missing.where(_marketFailures.containsKey).length,
      loading:
          (_scanRegion == region && _scanParts.any(parts.contains)) ||
          (kind == SharedMarketPart.orderBook &&
              _pendingDepthCheck &&
              parts.isNotEmpty),
      blocked:
          missing.isNotEmpty &&
          (pause?.reason == MarketRequestPauseReason.protected ||
              pause?.isActive(clock()) == true),
    );
  }

  /// The open recipe owns a bounded depth scope, not an all-catalog scan.
  /// Navigating Back or changing a formula replaces that scope; closing it
  /// releases only this controller's interest in its pending requests.
  void setInspectedRecipe(
    Recipe? recipe, {
    String? selectedVariantId,
    String? itemName,
  }) {
    final ids = <String>{};
    if (recipe != null) {
      final inspection = inspectRecipe(
        recipe: recipe,
        itemName: itemName,
        selectedVariantId: selectedVariantId,
      );
      final source = {
        ...(inspection.sourceMode == preferences.mode
            ? recipes
            : _assembleRecipes(inspection.sourceMode)),
        inspection.recipe.name: inspection.recipe,
      };
      final validVariant =
          selectedVariantId == null ||
          inspection.recipe.variantById(selectedVariantId) != null;
      if (validVariant) {
        ids.addAll(
          _calculator.marketInputIds(
            recipe: inspection.recipe,
            recipes: source,
            rules: appController.plannerRules,
            selectedVariantId: inspection.quote.selectedVariantId,
          ),
        );
        final output =
            _calculator.marketItemId(
              name: inspection.itemName,
              recipes: source,
              rules: appController.plannerRules,
            ) ??
            catalog.bundledMarketId(inspection.itemName);
        if (output != null) ids.add(output);
      }
    }
    final eligible = ids.where(isOpportunityMarketRequestEligible).toSet();
    if (setEquals(eligible, _inspectedDepthIds)) return;
    _inspectedDepthIds = eligible;
    _detailPriorityIds = eligible;
    _depthScopeChanged();
  }

  /// An explicitly opened item/exchange Market panel can ask for its books.
  /// An empty set closes that panel's scope. Only Refresh grants permission to
  /// retry a previous protection after its deadline; opening a panel does not.
  Future<void> ensureMarketDepth(
    Iterable<String> itemIds, {
    bool forceRefresh = false,
  }) async {
    await ready;
    if (_disposed) return;
    final ids = itemIds.where(isOpportunityMarketRequestEligible).toSet();
    final changed = !setEquals(ids, _explicitDepthIds);
    _explicitDepthIds = ids;
    if (changed) _depthScopeChanged(schedule: false);
    if (forceRefresh) _resumeManualMarketCheck();
    await _queueDepthCheck(
      forceRefresh: forceRefresh,
      userInitiated: forceRefresh,
    );
  }

  void _depthScopeChanged({
    bool schedule = true,
    bool preserveStoppedRecovery = false,
  }) {
    final active = _activeDepthIds;
    final removed = _scanParts
        .where(
          (part) =>
              part.part == SharedMarketPart.orderBook &&
              !active.contains(part.key.itemId),
        )
        .toSet();
    if (_scanIsDepth && removed.isNotEmpty) {
      if (_scanScope case final scope?) {
        // Keep retained books in flight, and stop only obsolete subscriptions.
        // Quotes remain useful to the shared summary even after detail closes.
        _scanParts.removeAll(removed);
        final manual = _manualMarketRefresh;
        if (manual?.region == preferences.region) {
          manual!.attemptedBooks.removeAll(
            removed
                .map((part) => part.key.itemId)
                .where((id) => !manual.completedBooks.contains(id)),
          );
        }
        scope.release(removed);
      } else {
        _scopeCancellation = true;
        _cancellation?.cancel();
      }
    }
    final cycle = _recoveryCycles[preferences.region];
    bool noLongerNeeded(SharedMarketPartKey part) =>
        part.part == SharedMarketPart.orderBook &&
        !active.contains(part.key.itemId);
    cycle?.targets.removeWhere(noLongerNeeded);
    cycle?.retryableParts.removeWhere(noLongerNeeded);
    if (!preserveStoppedRecovery ||
        !_automaticStoppedRegions.contains(preferences.region)) {
      _settleRecoveryCycle(preferences.region);
    }
    if (schedule) unawaited(_queueDepthCheck());
    if (!_disposed) notifyListeners();
  }

  void _updateDemandDepthScope() {
    final ids = <String>{};
    if (_workspaceActive &&
        preferences.section == 'crafting' &&
        (preferences.craftSort == 'preorders' || preferences.demandOnly)) {
      // Unknown books must still be requested when Demand hides their
      // rows. Applying that last filter here would strand them permanently.
      for (final quote in _demandCandidates) {
        final id = _demandOutputId(quote);
        if (id != null) ids.add(id);
      }
    }
    if (setEquals(ids, _demandDepthIds)) return;
    final added = ids.difference(_demandDepthIds).isNotEmpty;
    _demandDepthIds = ids;
    _depthScopeChanged(schedule: added);
  }

  Future<void> _queueDepthCheck({
    bool forceRefresh = false,
    bool userInitiated = false,
    Duration maxAge = inWorkspaceMarketAge,
  }) {
    if (_disposed || loading || _activeDepthIds.isEmpty) {
      return Future<void>.value();
    }
    _pendingDepthCheck = true;
    _pendingDepthMaxAge = _stricterMarketAge(_pendingDepthMaxAge, maxAge);
    _forceDepthCheck = _forceDepthCheck || forceRefresh;
    _depthUserInitiated = _depthUserInitiated || userInitiated;
    if (_manualMarketRefresh case final manual?) return manual.done.future;
    return _depthWork ??= Future<void>.microtask(_drainDepthChecks);
  }

  Future<void> _drainDepthChecks() async {
    try {
      while (_pendingDepthCheck && !_disposed) {
        await _scanCompletion?.future;
        await _manualMarketRefresh?.done.future;
        if (_disposed || _flushDepth > 0 || _marketPausedForFlush) break;
        final region = preferences.region;
        if (_automaticStoppedRegions.contains(region)) break;
        _pendingDepthCheck = false;
        final force = _forceDepthCheck;
        final userInitiated = _depthUserInitiated;
        final maxAge = _pendingDepthMaxAge ?? inWorkspaceMarketAge;
        _pendingDepthMaxAge = null;
        _forceDepthCheck = false;
        _depthUserInitiated = false;
        final ids = _activeDepthIds;
        if (ids.isEmpty) continue;
        final cycle = _recoveryCycles[region];
        final deferred = !force && cycle?.waiting == true
            ? cycle!.retryableParts
            : const <SharedMarketPartKey>{};
        final parts = {
          for (final id in ids)
            _marketPart(region, id, SharedMarketPart.orderBook),
          for (final id in ids)
            if (!(_regionItems[region]?[id]?.quoteIsFresh(clock(), maxAge) ??
                false))
              _marketPart(region, id, SharedMarketPart.quote),
        }..removeAll(deferred);
        if (parts.isEmpty) continue;
        await _refreshTargets(
          {'$region:details': ids},
          onlyStale: !force,
          recoveryParts: parts,
          detail: true,
          userInitiated: userInitiated,
          maxAge: maxAge,
        );
      }
    } finally {
      _depthWork = null;
      _pendingDepthCheck = false;
      _pendingDepthMaxAge = null;
      _forceDepthCheck = false;
      _depthUserInitiated = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Reorders already requested work only; opening details never starts an
  /// extra scan or changes a recipe, balance, selection, or saved preference.
  void prioritizeRecipe(Recipe? recipe) {
    if (recipe == null) {
      _detailPriorityIds = {};
      return;
    }
    final mode = CraftMode.values
        .where((mode) => mode.key == recipe.type.trim().toLowerCase())
        .firstOrNull;
    final source = mode == null || mode == preferences.mode
        ? recipes
        : _assembleRecipes(mode);
    _detailPriorityIds = _calculator.marketItemIds(
      recipe: recipe,
      recipes: source,
      rules: appController.plannerRules,
    );
  }

  Iterable<String> _priorityIds(Iterable<String> activeIds) sync* {
    yield* _detailPriorityIds;
    yield* _cardDepthIds;
    final outputs = _recipeMarketIds.keys
        .map((name) => _outputMarketIds[name])
        .toSet();
    yield* activeIds.where((id) => !outputs.contains(id));
    yield* activeIds.where(outputs.contains);
  }

  // Old sale preferences remain round-trippable; this screen now consistently
  // compares listing proceeds after tax, not an instant wholesale sale.
  OpportunitySaleMode get craftSaleMode => OpportunitySaleMode.listing;
  ExchangeSaleMode get exchangeSaleMode => ExchangeSaleMode.listing;
  ExchangeCurrency get currency => exchangeCatalog.firstWhere(
    (currency) => currency.id == preferences.currencyId,
    orElse: () => exchangeCatalog.first,
  );
  int get owned => preferences.owned[currency.id] ?? 0;
  bool get hasChecked {
    if (loading) return false;
    final items = _regionItems[preferences.region] ?? const {};
    final now = clock();
    return _selectionIds().every((id) {
      final item = items[id];
      return item != null && item.quoteIsFresh(now, maxMarketAge);
    });
  }

  List<ExchangeQuote> get exchangeQuotes => owned == 0
      ? calculateExchangeReferenceOptions(
          currency: currency,
          market: market,
          now: clock(),
          saleMode: exchangeSaleMode,
          taxMultiplier: marketNetRate(appController.marketTax.value),
          remainingLimitedExchanges: preferences.remainingLimits,
          confirmedRequirementRoutes: preferences.confirmedRequirements,
          maxMarketAge: cachedMarketMaxAge,
        )
      : calculateExchangeOptions(
          currency: currency,
          owned: owned,
          market: market,
          now: clock(),
          saleMode: exchangeSaleMode,
          taxMultiplier: marketNetRate(appController.marketTax.value),
          remainingLimitedExchanges: preferences.remainingLimits,
          confirmedRequirementRoutes: preferences.confirmedRequirements,
          maxMarketAge: cachedMarketMaxAge,
        );

  Iterable<OpportunityQuote> get _demandCandidates {
    final search = preferences.craftSearch.trim().toLowerCase();
    return quotes.where((quote) {
      if (search.isNotEmpty &&
          !quote.recipeName.toLowerCase().contains(search)) {
        return false;
      }
      final profit = quote.profitFor(craftSaleMode);
      // Unchecked data stays discoverable; it is not silently treated as a loss.
      if (search.isEmpty &&
          preferences.profitableOnly &&
          profit != null &&
          profit <= 0) {
        return false;
      }
      if (preferences.readyOnly && !quote.ingredientsAvailable) {
        return false;
      }
      return true;
    });
  }

  /// Unknown/stale scoped stock is not a match, but remains in the bounded
  /// demand scan scope. Confirmed zero does not require confirmed preorders.
  int get demandPendingCount => preferences.demandOnly
      ? _demandCandidates
            .where(
              (quote) =>
                  _demandOutputId(quote) != null &&
                  _demandStockFor(quote) == null,
            )
            .length
      : 0;

  String? _demandOutputId(OpportunityQuote quote) {
    final id = _outputMarketIds[quote.recipeName];
    return id != null && isOpportunityMarketRequestEligible(id) ? id : null;
  }

  int? _demandStockFor(OpportunityQuote quote) {
    if (_demandOutputId(quote) == null) return null;
    final item = outputMarketFor(quote.recipeName);
    if (item == null || item.unlisted) return null;
    final stock = item.stockFor(clock(), cachedMarketMaxAge);
    return stock != null && stock >= 0 ? stock : null;
  }

  double? _demandFor(OpportunityQuote quote) =>
      _currentDemand(quote.outputMarket, clock(), cachedMarketMaxAge);

  List<OpportunityQuote> get visibleQuotes {
    final rows = _demandCandidates
        .where(
          (quote) => !preferences.demandOnly || _demandStockFor(quote) == 0,
        )
        .toList();
    double? sortValue(OpportunityQuote quote) =>
        switch (preferences.craftSort) {
          'preorders' => _demandFor(quote),
          _ => quote.profitFor(craftSaleMode),
        };
    rows.sort((a, b) {
      final av = sortValue(a), bv = sortValue(b);
      if (av == null && bv != null) return 1;
      if (av != null && bv == null) return -1;
      final comparison = av == null || bv == null ? 0 : bv.compareTo(av);
      return comparison != 0
          ? comparison
          : a.recipeName.compareTo(b.recipeName);
    });
    return rows;
  }

  /// Directly consumed materials from the live definitions in all three modes.
  /// Building suggestions does not read prices or request market data.
  List<String> get bestUseItems {
    final sources = [
      for (final mode in CraftMode.values) _bestUseSourceFor(mode),
    ];
    final key = (sources[0], sources[1], sources[2]);
    if (key == _bestUseSuggestionKey) return _bestUseSuggestions;
    final names = <String, String>{};
    for (final source in sources) {
      for (final inputs in source.inputNames.values) {
        for (final name in inputs) {
          names.putIfAbsent(name.toLowerCase(), () => name);
        }
      }
    }
    _bestUseSuggestionKey = key;
    return _bestUseSuggestions = List.unmodifiable(
      names.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
  }

  void selectBestUseItem(String name) {
    final trimmed = name.trim();
    final canonical =
        bestUseItems
            .where((item) => item.toLowerCase() == trimmed.toLowerCase())
            .firstOrNull ??
        trimmed;
    if (canonical == preferences.bestUseItem) return;
    change((p) => p.bestUseItem = canonical);
  }

  _BestUseSource _bestUseSourceFor(CraftMode mode) {
    final sourceState = appController.modes[mode]!.state.value;
    final previous = _bestUseSources[mode];
    if (previous != null && previous.matches(sourceState)) return previous;
    final source = _assembleRecipes(mode);
    final inputs = <String, Set<String>>{};
    for (final recipe in source.values) {
      if (!recipe.isCraftable ||
          recipe.type.toLowerCase() != mode.key ||
          isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId)) {
        continue;
      }
      final outputId = _calculator.marketItemId(
        name: recipe.name,
        recipes: source,
        rules: appController.plannerRules,
      );
      if (outputId != null && !isOpportunityMarketRequestEligible(outputId)) {
        continue;
      }
      final names = opportunityBestUseItems(
        recipe,
        recipes: source,
        rules: appController.plannerRules,
      );
      if (names.isNotEmpty) inputs[recipe.name] = names;
    }
    return _bestUseSources[mode] = _BestUseSource(
      sourceState,
      source,
      inputs,
      appController.plannerRules,
    );
  }

  String? get _bestUseSelectedId {
    for (final mode in CraftMode.values) {
      final id = _calculator.marketItemId(
        name: preferences.bestUseItem,
        recipes: _bestUseSourceFor(mode).recipes,
        rules: appController.plannerRules,
      );
      if (id != null) return id;
    }
    return null;
  }

  Iterable<(CraftMode, Recipe, Map<String, Recipe>)> get _bestUseRecipes sync* {
    final selected = preferences.bestUseItem.trim().toLowerCase();
    if (selected.isEmpty) return;
    final selectedId = _bestUseSelectedId;
    final identity = selectedId == null ? 'name:$selected' : 'id:$selectedId';
    for (final mode in CraftMode.values) {
      final source = _bestUseSourceFor(mode);
      for (final name in source.consumers[identity] ?? const <String>[]) {
        yield (mode, source.recipes[name]!, source.recipes);
      }
    }
  }

  Set<String> get _bestUseSelectionIds => {
    for (final (mode, recipe, source) in _bestUseRecipes)
      ..._bestUseSourceFor(mode).marketIds.putIfAbsent(
        recipe.name,
        () => _idsForRecipes([recipe], assembled: source),
      ),
  };

  String? _bestUseOutputId(OpportunityBestUseQuote use) {
    final id = _calculator.marketItemId(
      name: use.recipe.name,
      recipes: _bestUseSourceFor(use.mode).recipes,
      rules: appController.plannerRules,
    );
    return id != null && isOpportunityMarketRequestEligible(id) ? id : null;
  }

  OpportunityMarketItem? _bestUseOutput(OpportunityBestUseQuote use) {
    final id = _bestUseOutputId(use);
    return id == null ? null : _regionItems[preferences.region]?[id];
  }

  int? _bestUseStock(OpportunityBestUseQuote use) {
    final item = _bestUseOutput(use);
    if (item == null || item.unlisted) return null;
    final stock = item.stockFor(clock(), cachedMarketMaxAge);
    return stock != null && stock >= 0 ? stock : null;
  }

  Iterable<OpportunityBestUseQuote> get _bestUseFilterCandidates =>
      bestUseQuotes.where(
        (use) =>
            (!preferences.profitableOnly ||
                use.extraProfitPerUnit == null ||
                use.extraProfitPerUnit! > 0) &&
            (!preferences.readyOnly || use.otherIngredientsAvailable),
      );

  int get bestUseDemandPendingCount => !preferences.demandOnly
      ? 0
      : _bestUseFilterCandidates
            .where(
              (use) =>
                  _bestUseOutputId(use) != null && _bestUseStock(use) == null,
            )
            .length;

  List<OpportunityBestUseQuote> get visibleBestUseQuotes {
    final rows = _bestUseFilterCandidates
        .where((use) => !preferences.demandOnly || _bestUseStock(use) == 0)
        .toList();
    double? value(OpportunityBestUseQuote use) =>
        preferences.craftSort == 'preorders'
        ? _currentDemand(_bestUseOutput(use), clock(), cachedMarketMaxAge)
        : use.extraProfitPerUnit;
    rows.sort((a, b) {
      final av = value(a), bv = value(b);
      if (av == null && bv != null) return 1;
      if (av != null && bv == null) return -1;
      final compared = av == null || bv == null ? 0 : bv.compareTo(av);
      if (compared != 0) return compared;
      final named = a.recipe.name.compareTo(b.recipe.name);
      return named != 0 ? named : a.mode.index.compareTo(b.mode.index);
    });
    return rows;
  }

  void _updateBestUseDepthScope() {
    final ids = <String>{};
    if (_workspaceActive && preferences.section == 'best-use') {
      for (final (mode, recipe, source) in _bestUseRecipes) {
        if (preferences.readyOnly) {
          // Resolve other-input availability before hiding unknown rows.
          ids.addAll(
            _bestUseSourceFor(mode).marketIds.putIfAbsent(
              recipe.name,
              () => _idsForRecipes([recipe], assembled: source),
            ),
          );
          final selectedId = _bestUseSelectedId;
          if (selectedId != null) ids.remove(selectedId);
        }
        if (preferences.demandOnly || preferences.craftSort == 'preorders') {
          final id = _calculator.marketItemId(
            name: recipe.name,
            recipes: source,
            rules: appController.plannerRules,
          );
          if (id != null && isOpportunityMarketRequestEligible(id)) ids.add(id);
        }
      }
    }
    if (setEquals(ids, _bestUseDepthIds)) return;
    final added = ids.difference(_bestUseDepthIds).isNotEmpty;
    _bestUseDepthIds = ids;
    _depthScopeChanged(schedule: added, preserveStoppedRecovery: true);
  }

  void _recalculateBestUse() {
    if (preferences.section != 'best-use') return;
    final sources = [
      for (final mode in CraftMode.values) _bestUseSourceFor(mode),
    ];
    final contextKey = (
      preferences.bestUseItem,
      preferences.region,
      preferences.readyOnly,
      sources[0].recipes,
      sources[1].recipes,
      sources[2].recipes,
      appController.modes[CraftMode.alchemy]!.state.value.alchemyMastery,
      appController.modes[CraftMode.cooking]!.state.value.cookingMastery,
      appController.modes[CraftMode.processing]!.state.value.processingMastery,
      appController.marketTax.value,
    );
    final key = (contextKey, _marketRevision);
    if (key == _bestUseCalculationKey) return;
    _bestUseCalculationKey = key;
    final revision = ++_bestUseRevision;
    if (contextKey != _bestUseContextKey) bestUseQuotes = [];
    _bestUseContextKey = contextKey;
    final selected = _bestUseRecipes.toList();
    _pendingBestUseCalculation = selected.isEmpty
        ? null
        : _BestUseCalculationInput(
            revision: revision,
            itemName: preferences.bestUseItem,
            selectedItemId: _bestUseSelectedId,
            candidates: [
              for (final (mode, recipe, source) in selected)
                _BestUseCandidateInput(
                  mode,
                  recipe,
                  source,
                  appController.modes[mode]!.state.value,
                  _npcPricesFor(appController.modes[mode]!.state.value),
                ),
            ],
            rules: appController.plannerRules,
            tax: appController.marketTax.value,
            market: OpportunityMarketSnapshot(
              region: preferences.region,
              items: {
                for (final entry in market.items.entries)
                  if (isOpportunityMarketRequestEligible(entry.key))
                    entry.key: entry.value,
              },
            ),
            now: clock(),
            maxMarketAge: cachedMarketMaxAge,
            preferAvailableInputs: preferences.readyOnly,
          );
    _updateBestUseDepthScope();
    if (!_calculatingBestUse && _pendingBestUseCalculation != null) {
      _bestUseCalculation = _drainBestUseCalculations();
    }
  }

  Future<void> _drainBestUseCalculations() async {
    _calculatingBestUse = true;
    try {
      while (_pendingBestUseCalculation != null && !_disposed) {
        final input = _pendingBestUseCalculation!;
        _pendingBestUseCalculation = null;
        final next = await compute(_calculateBestUses, input);
        if (_disposed) break;
        _updateCacheFreshness();
        _recalculateBestUse();
        if (input.revision != _bestUseRevision) continue;
        bestUseQuotes = next;
        _updateBestUseDepthScope();
        _scheduleCardInterestCheck();
        notifyListeners();
      }
    } on Object {
      if (!_disposed) {
        bestUseQuotes = [];
        notice = 'These recipes could not be calculated. Try Refresh.';
      }
    } finally {
      _calculatingBestUse = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _load() async {
    _sharedSubscription = sharedMarket?.receipts.listen(_receiveSharedReceipt);
    try {
      preferences = await _preferencesStore.load(
        fallbackRegion: appController.active.state.value.market.region,
      );
    } on Object {
      notice =
          'Saved settings could not be read. Your file has been left untouched.';
    }
    try {
      await _observations.load();
    } on Object {
      notice =
          'Saved sales history could not be read. You can still check prices.';
    }
    try {
      final Map<String, Map<String, OpportunityMarketItem>> saved;
      if (sharedMarket case final broker?) {
        await broker.ready;
        saved = {
          for (final region in ['eu', 'na'])
            region: broker.snapshot(region).items,
        };
        if (broker.persistenceError != null) {
          notice =
              'Saved prices could not be read. Refresh to load them again.';
        }
      } else {
        saved = await _marketCache.load();
      }
      for (final entry in saved.entries) {
        _regionItems[entry.key] = _observations
            .withActivity(entry.key, entry.value, now: clock())
            .map((id, item) => MapEntry(id, item));
      }
    } on Object {
      notice = 'Saved prices could not be read. Refresh to load them again.';
    }
    if (_disposed) return;
    loading = false;
    _assemble();
    recalculate();
    if (sharedMarket != null) {
      _scheduleAutoCheck(
        all: prefetchAll,
        delay: Duration.zero,
        maxAge: automaticMarketAge,
      );
    }
    await calculationSettled;
    if (sharedMarket == null) {
      _scheduleAutoCheck(all: prefetchAll, maxAge: automaticMarketAge);
    }
  }

  void _plannerChanged() {
    if (!loading &&
        (!_assemblyMatches() || _economicContext != _quoteContextKey)) {
      // A shared loader may update planner market fields often; those do not
      // affect these direct-purchase calculations. Real inputs/tax do.
      if (_flushDepth == 0) _marketPausedForFlush = false;
      _calculationRevision++;
      _needsFullCalculation = true;
      quotes = [];
      notifyListeners();
    }
    _recalculateTimer?.cancel();
    _recalculateTimer = Timer(const Duration(milliseconds: 150), () {
      if (_disposed) return;
      _assemble();
      recalculate(marketUpdate: true);
    });
  }

  bool _assemblyMatches() {
    final previous = _assembledSource;
    return previous != null &&
        previous.$1 == preferences.mode &&
        mapEquals(previous.$2.recipeEdits, state.recipeEdits) &&
        mapEquals(previous.$2.ingredientMeta, state.ingredientMeta) &&
        setEquals(previous.$2.hiddenItems, state.hiddenItems);
  }

  void _assemble({bool force = false}) {
    if (!force && _assemblyMatches()) return;
    _calculationKey = null;
    _needsFullCalculation = true;
    recipes = _assembleRecipes(preferences.mode);
    _assembledSource = (preferences.mode, state);
  }

  void _prepareMarketDependencies() {
    if (identical(_dependencyRecipes, recipes)) return;
    _dependencyRecipes = recipes;
    _recipeMarketIds.clear();
    _outputMarketIds.clear();
    for (final recipe in recipes.values) {
      _outputMarketIds[recipe.name] = _calculator.marketItemId(
        name: recipe.name,
        recipes: recipes,
        rules: appController.plannerRules,
      );
      if (recipe.isCraftable &&
          recipe.type.toLowerCase() == preferences.mode.key) {
        _recipeMarketIds[recipe.name] = _calculator.marketItemIds(
          recipe: recipe,
          recipes: recipes,
          rules: appController.plannerRules,
        );
      }
    }
  }

  Map<String, Recipe> _assembleRecipes(CraftMode mode) {
    final assembled = appController.assembly.assembleRecipes(
      catalog: catalog.snapshot.forMode(mode),
      state: appController.modes[mode]!.state.value,
      supportingData: catalog.snapshot.supportingData,
      sharedMetadata: catalog.snapshot.alchemy.metadata,
      mode: mode,
    );
    return {
      for (final entry in assembled.entries)
        entry.key: _withMarketId(
          entry.value,
          entry.value.marketId ?? catalog.bundledMarketId(entry.key),
        ),
    };
  }

  Map<String, double> _npcPricesFor(ModeState source) {
    final excluded = {
      for (final name in source.hiddenItems) name.trim().toLowerCase(),
      for (final entry in source.recipeEdits.entries)
        if (entry.value == null) entry.key.trim().toLowerCase(),
    };
    if (excluded.isEmpty) return catalog.npcPurchasePrices;
    return Map.unmodifiable({
      for (final entry in catalog.npcPurchasePrices.entries)
        if (!excluded.contains(entry.key)) entry.key: entry.value,
    });
  }

  /// Reads one complete formula without changing the root quote or any saved
  /// choice. Inputs are still bought directly; opening a child is not a request
  /// to recursively craft it for its parent. Parent run costs do not apply here.
  OpportunityRecipeInspection inspectRecipe({
    required Recipe recipe,
    String? itemName,
    String? selectedVariantId,
    int crafts = 1,
    Map<String, String> ingredientChoices = const {},
    Map<String, Map<String, int>> ingredientAllocations = const {},
    double extraCostPerRun = 0,
    double extraCostPerCraft = 0,
    int? customSalePrice,
    void Function(String, OpportunityIngredientQuote)? onInputCandidate,
  }) {
    CraftMode modeFor(String type) => CraftMode.values.firstWhere(
      (mode) => mode.key == type.trim().toLowerCase(),
      orElse: () => throw ArgumentError.value(type, 'recipe.type'),
    );
    Map<String, Recipe> recipesFor(CraftMode mode) {
      final sourceState = appController.modes[mode]!.state.value;
      final cached = _inspectionRecipes[mode];
      if (cached != null && identical(cached.$1, sourceState)) {
        return cached.$2;
      }
      final assembled = _assembleRecipes(mode);
      _inspectionRecipes[mode] = (sourceState, assembled);
      return assembled;
    }

    final initialMode = modeFor(recipe.type);
    final initialRecipes = recipesFor(initialMode);
    final isCurrentDefinition =
        initialMode == preferences.mode &&
        identical(recipes[recipe.name], recipe);
    final sourceRecipe = isCurrentDefinition
        ? recipe
        : initialRecipes.values
                  .where(
                    (candidate) =>
                        candidate.name.trim().toLowerCase() ==
                        recipe.name.trim().toLowerCase(),
                  )
                  .firstOrNull ??
              _withMarketId(
                recipe,
                recipe.marketId ?? catalog.bundledMarketId(recipe.name),
              );
    // An explicitly invalid ID must reach the calculator, not silently resolve
    // to the default formula. Only an absent choice uses the source default.
    final displayedVariant = preferences.readyOnly && isCurrentDefinition
        ? quotes
              .where((quote) => quote.recipeName == sourceRecipe.name)
              .firstOrNull
              ?.selectedVariantId
        : null;
    final variantId =
        selectedVariantId ??
        displayedVariant ??
        sourceRecipe.defaultVariant?.id;
    final formula = sourceRecipe.resolveVariant(variantId);
    final sourceMode = modeFor(formula.type);
    final sourceRecipes = {
      ...recipesFor(sourceMode),
      sourceRecipe.name: sourceRecipe,
    };
    final sourceState = appController.modes[sourceMode]!.state.value;
    final requestedName = itemName?.trim().isNotEmpty == true
        ? itemName!.trim()
        : sourceRecipe.name;
    final rare =
        requestedName.toLowerCase() != sourceRecipe.name.trim().toLowerCase();
    final snapshot = market;
    final now = clock();
    final baseQuote =
        OpportunityCalculator(
          catalogNpcPrices: _npcPricesFor(sourceState),
        ).evaluate(
          recipe: sourceRecipe,
          recipes: sourceRecipes,
          state: sourceState,
          rules: appController.plannerRules,
          marketTax: appController.marketTax.value,
          market: snapshot,
          now: now,
          selectedVariantId: variantId,
          maxMarketAge: cachedMarketMaxAge,
          crafts: crafts,
          ingredientChoices: ingredientChoices,
          ingredientAllocations: ingredientAllocations,
          extraCostPerRun: extraCostPerRun,
          extraCostPerCraft: extraCostPerCraft,
          customSalePrice: customSalePrice,
          onInputCandidate: onInputCandidate,
          preferAvailableInputs: preferences.readyOnly,
        );
    OpportunityMarketItem? requestedMarket;
    if (rare) {
      final id =
          _calculator.marketItemId(
            name: requestedName,
            recipes: sourceRecipes,
            rules: appController.plannerRules,
          ) ??
          catalog.bundledMarketId(requestedName);
      final item = snapshot.items[id];
      if (item != null && item.subId == 0 && item.itemId == id) {
        requestedMarket = item;
      }
    }
    return OpportunityRecipeInspection(
      itemName: requestedName,
      sourceMode: sourceMode,
      recipe: formula,
      quote: rare
          ? _unknownRareOutput(baseQuote, requestedName, requestedMarket)
          : baseQuote,
      mastery: switch (sourceMode) {
        CraftMode.alchemy => sourceState.alchemyMastery,
        CraftMode.cooking => sourceState.cookingMastery,
        CraftMode.processing => sourceState.processingMastery,
      },
      isRareOutput: rare,
    );
  }

  void change(
    void Function(OpportunitiesPreferences value) mutation, {
    bool assemble = false,
  }) {
    final before = (
      preferences.section,
      preferences.mode,
      preferences.region,
      preferences.currencyId,
      preferences.bestUseItem,
    );
    mutation(preferences);
    final cardContextChanged =
        before.$1 != preferences.section ||
        before.$2 != preferences.mode ||
        before.$3 != preferences.region ||
        (preferences.section == 'best-use' &&
            before.$5 != preferences.bestUseItem);
    // Region changes already cancel the old caller and prune its recovery
    // scope below. Do not settle the destination's recovery for old card IDs.
    final removedCardScope =
        cardContextChanged &&
        before.$3 == preferences.region &&
        _cardDepthIds.isNotEmpty;
    if (cardContextChanged) {
      _cardDepthIds = {};
      _cardEntryMaxAge = null;
    }
    if (before.$3 != preferences.region) {
      _manualMarketRefresh?.cancelled = true;
      _autoCheckTimer?.cancel();
      _pendingAutoCheckAll = false;
      _pendingAutoCheckMaxAge = null;
      _selectionRevision++;
      if (scanning && _scanRegion != preferences.region) {
        _cancellation?.cancel();
      }
      _cancelRecoveryTimer();
      final previousCycle = _recoveryCycles[before.$3];
      previousCycle?.targets.removeWhere(
        (part) => part.part == SharedMarketPart.orderBook,
      );
      previousCycle?.retryableParts.removeWhere(
        (part) => part.part == SharedMarketPart.orderBook,
      );
      _settleRecoveryCycle(before.$3);
      _inspectedDepthIds = {};
      _explicitDepthIds = {};
      _demandDepthIds = {};
      _bestUseDepthIds = {};
      _detailPriorityIds = {};
      _pendingDepthCheck = false;
      _pendingDepthMaxAge = null;
    }
    _preferencesDirty = true;
    _preferenceRevision++;
    if (assemble) {
      quotes = [];
      _assemble(force: true);
    }
    recalculate();
    _updateDemandDepthScope();
    _updateBestUseDepthScope();
    if (removedCardScope) {
      _depthScopeChanged(schedule: false, preserveStoppedRecovery: true);
    }
    _scheduleCardInterestCheck();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _save);
    if (before !=
        (
          preferences.section,
          preferences.mode,
          preferences.region,
          preferences.currencyId,
          preferences.bestUseItem,
        )) {
      _scheduleAutoCheck(all: prefetchAll && before.$3 != preferences.region);
    }
  }

  void _scheduleAutoCheck({
    bool all = false,
    Duration delay = const Duration(milliseconds: 350),
    Duration maxAge = inWorkspaceMarketAge,
  }) {
    if (!autoCheck || _disposed || _flushDepth > 0 || _marketPausedForFlush) {
      return;
    }
    if (preferences.section == 'best-use' && !_workspaceActive) return;
    if (_automaticStoppedRegions.contains(preferences.region)) return;
    final cycle = _recoveryCycles[preferences.region];
    if (cycle != null) {
      if (cycle.waiting) {
        _armRecoveryTimer(preferences.region, cycle);
        return;
      }
      if (cycle.stage == _RecoveryStage.protected ||
          cycle.stage == _RecoveryStage.stopped) {
        return;
      }
      if (cycle.stage == _RecoveryStage.incomplete &&
          clock().difference(cycle.startedAt) < maxAge) {
        return;
      }
    }
    _pendingAutoCheckAll = _pendingAutoCheckAll || all;
    _pendingAutoCheckMaxAge = _stricterMarketAge(
      _pendingAutoCheckMaxAge,
      maxAge,
    );
    _autoCheckTimer?.cancel();
    final revision = ++_selectionRevision;
    _autoCheckTimer = Timer(delay, () async {
      // A section change can use the same in-flight startup scan. Its pending
      // requests are reprioritized below; only a region change replaces it.
      if (scanning && _scanningAll && _scanRegion == preferences.region) {
        _pendingAutoCheckAll = false;
        _pendingAutoCheckMaxAge = null;
        return;
      }
      if (_scanRegion != null && _scanRegion != preferences.region) {
        _cancellation?.cancel();
      }
      await _scanCompletion?.future;
      await _manualMarketRefresh?.done.future;
      if (_disposed || revision != _selectionRevision) return;
      if (preferences.section == 'best-use' && !_workspaceActive) return;
      final checkAll = _pendingAutoCheckAll;
      final checkMaxAge = _pendingAutoCheckMaxAge ?? maxAge;
      _pendingAutoCheckAll = false;
      _pendingAutoCheckMaxAge = null;
      if (checkAll) {
        await refreshAll(onlyStale: true, automaticMaxAge: checkMaxAge);
      } else {
        await refresh(onlyStale: true, automaticMaxAge: checkMaxAge);
      }
    });
  }

  void ensureMarketCurrent() {
    if (_workspaceActive) {
      _cardEntryMaxAge = automaticMarketAge;
      _scheduleCardInterestCheck();
    }
    if (!loading) {
      recalculate();
      _scheduleAutoCheck(maxAge: automaticMarketAge);
      unawaited(_queueDepthCheck(maxAge: automaticMarketAge));
    }
  }

  static Duration _stricterMarketAge(Duration? pending, Duration requested) =>
      pending != null && pending < requested ? pending : requested;

  Object get _economicContext => (
    preferences.mode,
    recipes,
    (state.alchemyMastery, state.cookingMastery, state.processingMastery),
    (
      appController.marketTax.value.enabled,
      appController.marketTax.value.valuePack,
      appController.marketTax.value.merchantRing,
      appController.marketTax.value.familyFameBonus,
    ),
    preferences.readyOnly,
    craftSaleMode,
    preferences.region,
  );

  void recalculate({bool marketUpdate = false}) {
    if (_disposed || loading) return;
    if (!marketUpdate && _flushDepth == 0) _marketPausedForFlush = false;
    _updateCacheFreshness();
    _recalculateBestUse();
    final contextKey = _economicContext;
    if (contextKey != _quoteContextKey) {
      _quoteContextKey = contextKey;
      _calculationRevision++;
      _needsFullCalculation = true;
      _pendingCalculation = null;
      quotes = [];
    }
    final key = (contextKey, _marketRevision);
    if (key != _calculationKey || _needsFullCalculation) {
      _calculationKey = key;
      _prepareMarketDependencies();
      final changed = _changedMarketIds.remove(preferences.region) ?? const {};
      final names = <String>{
        ...?_pendingCalculation?.recipeNames,
        if (_needsFullCalculation)
          ..._recipeMarketIds.keys
        else
          for (final entry in _recipeMarketIds.entries)
            if (entry.value.any(changed.contains)) entry.key,
      };
      _needsFullCalculation = false;
      if (names.isNotEmpty) {
        _pendingCalculation = _CalculationInput(
          revision: _calculationRevision,
          recipeNames: names,
          modeKey: preferences.mode.key,
          recipes: recipes,
          state: state,
          rules: appController.plannerRules,
          tax: appController.marketTax.value,
          catalogNpcPrices: _npcPricesFor(state),
          market: market,
          now: clock(),
          maxMarketAge: cachedMarketMaxAge,
          preferAvailableInputs: preferences.readyOnly,
          saleMode: craftSaleMode,
        );
        if (!_calculating) _calculation = _drainCalculations();
      }
    }
    notifyListeners();
  }

  void _updateCacheFreshness() {
    final now = clock();
    final fresh = <String>{};
    DateTime? nextExpiry;
    for (final item in (_regionItems[preferences.region] ?? const {}).values) {
      void include(String part, DateTime? at, bool valid) {
        if (!valid || at == null) return;
        fresh.add('${item.itemId}:$part');
        // Domain freshness includes the exact boundary; expire just after it.
        final expiry = at
            .add(maxMarketAge)
            .add(const Duration(milliseconds: 1));
        if (nextExpiry == null || expiry.isBefore(nextExpiry!)) {
          nextExpiry = expiry;
        }
      }

      include(
        'quote',
        item.quoteFetchedAt,
        item.quoteIsFresh(now, maxMarketAge),
      );
      include('book', item.bookFetchedAt, item.bookIsFresh(now, maxMarketAge));
    }
    final previous = _freshReceipts[preferences.region];
    if (previous != null && !setEquals(previous, fresh)) {
      if (previous.difference(fresh).isNotEmpty) {
        // Never leave an old profitable row visible while its expired inputs
        // are being recalculated in the background isolate.
        quotes = [];
        bestUseQuotes = [];
        _bestUseCalculationKey = null;
        _bestUseRevision++;
        _calculationRevision++;
        _marketRevision++;
        _needsFullCalculation = true;
        _pendingCalculation = null;
        _calculationKey = null;
      }
    }
    _freshReceipts[preferences.region] = fresh;
    _cacheExpiryTimer?.cancel();
    if (_flushDepth > 0 || _marketPausedForFlush) return;
    _cacheExpiryTimer = nextExpiry == null
        ? null
        : Timer(nextExpiry!.difference(now), () {
            if (_disposed) return;
            recalculate();
            // Expiration only updates the display. A tab/recipe/check action
            // requests newer data; leaving the app open never polls the market.
          });
  }

  Future<void> _drainCalculations() async {
    _calculating = true;
    try {
      while (_pendingCalculation != null && !_disposed) {
        final input = _pendingCalculation!;
        _pendingCalculation = null;
        final next = await compute(_calculateRecipes, input);
        // A receipt may expire while this isolate is busy (or the clock may
        // have advanced). Expired results must never be published afterwards.
        if (!_disposed) {
          _updateCacheFreshness();
          if (!_assemblyMatches() || _economicContext != _quoteContextKey) {
            _assemble();
            recalculate(marketUpdate: true);
          }
        }
        if (!_disposed && input.revision == _calculationRevision) {
          final merged = {for (final quote in quotes) quote.recipeName: quote};
          for (final quote in next) {
            merged[quote.recipeName] = quote;
          }
          quotes = [
            for (final recipe in recipes.values)
              if (merged[recipe.name] case final OpportunityQuote quote) quote,
          ];
          _updateDemandDepthScope();
          if (_cardMarketInterests.isNotEmpty) _scheduleCardInterestCheck();
          notifyListeners();
        } else if (!_disposed && _needsFullCalculation) {
          recalculate(marketUpdate: true);
        }
      }
    } on Object {
      if (!_disposed) {
        quotes = [];
        notice = 'The recipes could not be calculated. Try checking again.';
        notifyListeners();
      }
    } finally {
      _calculating = false;
    }
  }

  Set<String> _idsForRecipes(
    Iterable<Recipe> selected, {
    Map<String, Recipe>? assembled,
  }) {
    if (assembled == null || identical(assembled, recipes)) {
      _prepareMarketDependencies();
    }
    final ids = <String>{};
    for (final recipe in selected) {
      ids.addAll(
        (assembled == null || identical(assembled, recipes)
                ? _recipeMarketIds[recipe.name]
                : null) ??
            _calculator.marketItemIds(
              recipe: recipe,
              recipes: assembled ?? recipes,
              rules: appController.plannerRules,
            ),
      );
    }
    return ids.where(isOpportunityMarketRequestEligible).toSet();
  }

  Set<String> _exchangeIds(ExchangeCurrency selected) => {
    for (final route in selected.routes)
      for (final reward in route.rewards)
        if (reward.item?.marketable == true &&
            isOpportunityMarketRequestEligible('${reward.item!.id}'))
          '${reward.item!.id}',
  };

  Set<String> _selectionIds({Recipe? recipe}) =>
      preferences.section == 'best-use'
      ? _bestUseSelectionIds
      : preferences.section == 'crafting'
      ? _idsForRecipes(
          recipe == null
              ? recipes.values.where(
                  (item) =>
                      item.isCraftable &&
                      item.type.toLowerCase() == preferences.mode.key,
                )
              : [recipe],
        )
      : _exchangeIds(currency);

  String get _selectionKey =>
      '${preferences.region}:${preferences.section}:${preferences.section == 'best-use'
          ? preferences.bestUseItem
          : preferences.section == 'crafting'
          ? preferences.mode.key
          : currency.id}';

  Future<void> refresh({
    Recipe? recipe,
    bool onlyStale = false,
    Duration automaticMaxAge = automaticMarketAge,
  }) async {
    if (!onlyStale && recipe == null && _manualMarketRefresh != null) {
      return _manualMarketRefresh!.done.future;
    }
    if (!onlyStale && recipe == null && !refreshReadiness.canRefresh) return;
    if (!onlyStale) _resumeManualMarketCheck();
    if (recipe != null) {
      setInspectedRecipe(recipe);
      return _queueDepthCheck(
        forceRefresh: !onlyStale,
        userInitiated: !onlyStale,
        maxAge: automaticMaxAge,
      );
    }
    _reconcileMarketFailures(preferences.region);
    final recovery = {
      ..._regionFailureParts,
      ...?_recoveryCycles[preferences.region]?.targets.where(
        (part) =>
            _needsMarketPart(part) &&
            (part.part == SharedMarketPart.quote ||
                _activeDepthIds.contains(part.key.itemId)),
      ),
    };
    if (!onlyStale && recipe == null && recovery.isNotEmpty) {
      // A newly selected pane may not belong to the earlier scan (for
      // example, a selection made while requests were blocked).
      final region = preferences.region;
      for (final id in _selectionIds()) {
        final part = _marketPart(region, id, SharedMarketPart.quote);
        if (!_partIsFresh(part, _regionItems[region]?[id])) {
          recovery.add(part);
        }
      }
      // The toolbar recovers the whole startup load, even when the user has
      // since selected another mode/currency. Force only these failed parts:
      // this bypasses a short failure cooldown, not successful cached parts.
      return _refreshTargets(
        {_selectionKey: recovery.map((part) => part.key.itemId).toSet()},
        onlyStale: false,
        all: true,
        recoveryParts: recovery,
        userInitiated: true,
      );
    }
    if (!onlyStale && prefetchAll && preferences.section != 'best-use') {
      return refreshAll(onlyStale: false);
    }
    if (!onlyStale && sharedMarket != null) {
      return _refreshSharedManualTargets({
        _selectionKey: _selectionIds(recipe: recipe),
      });
    }
    final region = preferences.region;
    await _refreshTargets(
      {_selectionKey: _selectionIds(recipe: recipe)},
      onlyStale: onlyStale,
      userInitiated: !onlyStale,
      maxAge: automaticMaxAge,
    );
    if (onlyStale) await calculationSettled;
    if (_disposed || preferences.region != region) return;
    await _queueDepthCheck(
      forceRefresh: !onlyStale,
      userInitiated: !onlyStale,
      maxAge: automaticMaxAge,
    );
  }

  /// Warms one region for all sections without changing a planner or selection.
  Future<void> refreshAll({
    bool onlyStale = true,
    Duration automaticMaxAge = automaticMarketAge,
  }) async {
    if (!onlyStale && _manualMarketRefresh != null) {
      return _manualMarketRefresh!.done.future;
    }
    if (!onlyStale && !refreshReadiness.canRefresh) return;
    if (!onlyStale) _resumeManualMarketCheck();
    if (loading || scanning || _disposed || _flushDepth > 0) return;
    final region = preferences.region;
    final targets = _allRefreshTargets();
    if (!onlyStale &&
        sharedMarket != null &&
        _regionFailureParts.isEmpty &&
        !(_recoveryCycles[region]?.targets.any(_needsMarketPart) ?? false)) {
      return _refreshSharedManualTargets(targets, all: true);
    }
    await _refreshTargets(
      targets,
      onlyStale: onlyStale,
      all: true,
      userInitiated: !onlyStale,
      maxAge: automaticMaxAge,
    );
    if (onlyStale) await calculationSettled;
    if (_disposed || preferences.region != region) return;
    await _queueDepthCheck(
      forceRefresh: !onlyStale,
      userInitiated: !onlyStale,
      maxAge: automaticMaxAge,
    );
  }

  final _allModeTargets = <CraftMode, (ModeState, Set<String>)>{};

  Map<String, Set<String>> _allRefreshTargets() {
    final region = preferences.region;
    final targets = <String, Set<String>>{_selectionKey: _selectionIds()};
    if (preferences.section == 'best-use') return targets;
    for (final mode in CraftMode.values) {
      final source = appController.modes[mode]!.state.value;
      var cached = _allModeTargets[mode];
      if (cached == null || !identical(cached.$1, source)) {
        final assembled = mode == preferences.mode
            ? recipes
            : _assembleRecipes(mode);
        cached = (
          source,
          Set.unmodifiable(
            _idsForRecipes(
              assembled.values.where(
                (recipe) =>
                    recipe.isCraftable && recipe.type.toLowerCase() == mode.key,
              ),
              assembled: assembled,
            ),
          ),
        );
        _allModeTargets[mode] = cached;
      }
      // The countdown must not rebuild all recipe catalogs each second.
      targets['$region:crafting:${mode.key}'] = cached.$2;
    }
    for (final selected in exchangeCatalog) {
      targets['$region:exchanges:${selected.id}'] = _exchangeIds(selected);
    }
    return targets;
  }

  Future<void> _refreshSharedManualTargets(
    Map<String, Set<String>> targets, {
    bool all = false,
  }) async {
    if (_manualMarketRefresh case final existing?) return existing.done.future;
    if (loading || scanning || _disposed || _flushDepth > 0) return;
    final manual = _ManualMarketRefresh(preferences.region);
    _manualMarketRefresh = manual;
    bool canContinue() =>
        !_disposed &&
        !manual.cancelled &&
        identical(_manualMarketRefresh, manual) &&
        preferences.region == manual.region &&
        _flushDepth == 0 &&
        !_marketPausedForFlush &&
        !_automaticStoppedRegions.contains(manual.region);
    Set<SharedMarketPartKey> partsFor(
      Set<String> quoteIds,
      Set<String> bookIds,
    ) => {
      for (final id in quoteIds)
        _marketPart(manual.region, id, SharedMarketPart.quote),
      for (final id in bookIds) ...{
        _marketPart(manual.region, id, SharedMarketPart.orderBook),
        if (!(_regionItems[manual.region]?[id]?.quoteIsFresh(
              clock(),
              maxMarketAge,
            ) ??
            false))
          _marketPart(manual.region, id, SharedMarketPart.quote),
      },
    };
    try {
      final books = _activeDepthIds;
      manual.attemptedBooks.addAll(books);
      await _refreshTargets(
        {...targets, '${manual.region}:manual-details': books},
        onlyStale: false,
        all: all,
        recoveryParts: partsFor(
          targets.values.expand((ids) => ids).toSet(),
          books,
        ),
        userInitiated: true,
      );
      while (canContinue()) {
        // Final price receipts may change which profitable outputs are visible.
        // Keep auto-depth work deferred until those calculations settle too.
        await calculationSettled;
        if (!canContinue()) break;
        final newlyActive = _activeDepthIds.difference(manual.attemptedBooks)
          ..removeWhere(
            (id) => _marketFailures.containsKey(
              _marketPart(manual.region, id, SharedMarketPart.orderBook),
            ),
          );
        if (newlyActive.isEmpty) break;
        manual.attemptedBooks.addAll(newlyActive);
        await _refreshTargets(
          {'${manual.region}:manual-new-details': newlyActive},
          onlyStale: false,
          recoveryParts: partsFor({}, newlyActive),
          detail: true,
          userInitiated: true,
        );
      }
    } finally {
      if (identical(_manualMarketRefresh, manual)) {
        _manualMarketRefresh = null;
        if (!manual.cancelled && preferences.region == manual.region) {
          // A queued depth request joined this manual pass. Its selected books
          // were already checked; the remaining ordinary drain is stale-only.
          _forceDepthCheck = false;
          _depthUserInitiated = false;
        }
        manual.done.complete();
        if (_pendingDepthCheck && !_disposed) {
          _depthWork ??= Future<void>.microtask(_drainDepthChecks);
        }
      }
    }
  }

  Future<void> _refreshTargets(
    Map<String, Set<String>> targets, {
    required bool onlyStale,
    bool all = false,
    Set<SharedMarketPartKey>? recoveryParts,
    bool recovery = false,
    bool userInitiated = false,
    bool detail = false,
    Duration maxAge = automaticMarketAge,
  }) async {
    if (loading || scanning || _disposed || _flushDepth > 0) return;
    final region = preferences.region;
    final knownPause =
        sharedMarket?.pauseFor(region) ?? _fallbackPauses[region];
    final requestedIds = targets.values.expand((ids) => ids).toSet();
    final requestedParts =
        recoveryParts ??
        {
          for (final id in requestedIds)
            _marketPart(region, id, SharedMarketPart.quote),
        };
    _summaryIds
        .putIfAbsent(region, () => {})
        .addAll(
          requestedParts
              .where((part) => part.part == SharedMarketPart.quote)
              .map((part) => part.key.itemId),
        );
    _reconcileMarketFailures(region);
    if (sharedMarket == null &&
        ((_fallbackBlockedUntil[region]?.isAfter(clock()) ?? false) ||
            (!userInitiated &&
                _fallbackPauses[region]?.reason ==
                    MarketRequestPauseReason.protected))) {
      final pause = _fallbackPauses[region];
      if (pause != null) {
        final parts = requestedParts;
        final cycle = _recoveryCycles.putIfAbsent(
          region,
          () => _MarketRecoveryCycle(clock()),
        );
        cycle.targets.addAll(parts);
        _finishRecoveryAttempt(
          region,
          attempted: parts,
          retryable: pause.reason == MarketRequestPauseReason.serverUnavailable
              ? parts
              : {},
          pause: pause,
          earlierPause: true,
        );
      }
      notifyListeners();
      return;
    }
    // Tab changes do not bypass user Stop or create a new retry budget.
    if (onlyStale && _automaticStoppedRegions.contains(region)) return;
    if (!onlyStale) _rateLimitedRegions.remove(region);
    final cache = _regionItems.putIfAbsent(region, () => {});
    var cycle = _recoveryCycles[region];
    if (cycle == null ||
        (!recovery && cycle.stage == _RecoveryStage.complete)) {
      cycle = _MarketRecoveryCycle(clock());
      _recoveryCycles[region] = cycle;
    }
    cycle.targets.addAll(requestedParts);
    final quoteIds = requestedIds
        .where(
          (id) => requestedParts.contains(
            _marketPart(region, id, SharedMarketPart.quote),
          ),
        )
        .where(
          (id) =>
              !onlyStale ||
              !(cache[id]?.quoteIsFresh(clock(), maxAge) ?? false),
        )
        .toSet();
    final bookIds = requestedIds
        .where(
          (id) => requestedParts.contains(
            _marketPart(region, id, SharedMarketPart.orderBook),
          ),
        )
        .where(
          (id) =>
              !onlyStale || !(cache[id]?.bookIsFresh(clock(), maxAge) ?? false),
        )
        .toSet();
    final ids = {...quoteIds, ...bookIds};
    if (ids.isEmpty) {
      _settleRecoveryCycle(region);
      notifyListeners();
      return;
    }
    final previousReceipts = <SharedMarketPartKey, DateTime?>{
      for (final id in quoteIds)
        _marketPart(region, id, SharedMarketPart.quote):
            cache[id]?.quoteFetchedAt,
      for (final id in bookIds)
        _marketPart(region, id, SharedMarketPart.orderBook):
            cache[id]?.bookFetchedAt,
    };
    final cancellation = MarketCancellationController();
    final token = cancellation.token;
    OpportunityMarketService? service;
    try {
      if (sharedMarket == null) {
        service = _serviceFactory(region);
        final ceiling = _regionConcurrency[region];
        if (ceiling != null) service.limitConcurrency(ceiling);
      }
    } on Object catch (error) {
      if (!_recoverTransientScanFailure(region, previousReceipts, error)) {
        _setRegionNotice(
          region,
          'The market could not be reached. Try again in a moment.',
        );
      }
      notifyListeners();
      return;
    }
    _cancellation = cancellation;
    scanning = true;
    _scanRegion = region;
    _scanParts = previousReceipts.keys.toSet();
    _scanIsDepth = detail || bookIds.isNotEmpty;
    _scanScope = sharedMarket != null && _scanIsDepth
        ? SharedMarketRequestScope()
        : null;
    _scopeCancellation = false;
    _scanningAll = all;
    _scanCompletion = Completer<void>();
    _setRegionNotice(region, null);
    cycle.stage = _RecoveryStage.loading;
    var receivedFreshPart = false;
    final observations = <String, OpportunityMarketItem>{};
    Map<SharedMarketPartKey, DateTime?> currentReceipts() => {
      for (final entry in previousReceipts.entries)
        if (_scanParts.contains(entry.key)) entry.key: entry.value,
    };
    void publish() {
      _marketPublishTimer?.cancel();
      _marketPublishTimer = null;
      if (_disposed) return;
      if (_changedMarketIds[region]?.isNotEmpty ?? false) _marketRevision++;
      recalculate(marketUpdate: true);
    }

    void receive(OpportunityMarketItem item) {
      if (_disposed) return;
      receivedFreshPart =
          receivedFreshPart ||
          item.quoteIsFresh(clock(), maxMarketAge) ||
          item.bookIsFresh(clock(), maxMarketAge);
      _mergeMarketItem(region, item);
      if (item.quoteFetchedAt != null) observations[item.itemId] = item;
      _cacheDirty = true;
      _cacheRevision++;
      _cacheSaveTimer ??= Timer(const Duration(seconds: 2), _queueCacheSave);
      // Show successful receipts even if another request in this pool is slow
      // or cancelled. Coalesce calculations rather than rebuilding per receipt.
      _marketPublishTimer ??= Timer(const Duration(milliseconds: 200), publish);
    }

    try {
      void onProgress(int completed, int total) {
        if (_disposed) return;
        final label = _scanIsDepth
            ? 'Loading market details'
            : 'Loading prices and stock';
        progress = total == 0
            ? label
            : '$label · ${(completed * 100 / total).round()}%';
        progressFraction = total == 0 ? null : completed / total;
        if (completed == 0) {
          notifyListeners();
        } else {
          _marketPublishTimer ??= Timer(
            const Duration(milliseconds: 200),
            publish,
          );
        }
      }

      bool rateLimited;
      MarketRequestPause? pause;
      Set<SharedMarketPartKey> retryable;
      if (sharedMarket case final broker?) {
        SharedMarketKey key(String id) =>
            SharedMarketKey(region: region, itemId: id);
        final batch = await broker.fetch(
          quoteKeys: quoteIds.map(key),
          bookKeys: bookIds.map(key),
          forceRefresh: !onlyStale,
          recovery: recovery,
          userInitiated: userInitiated,
          maxAge: maxAge,
          cancellationToken: token,
          scope: _scanScope,
          onItem: (receipt) {
            final manual = _manualMarketRefresh;
            if (manual?.region == region &&
                receipt.part == SharedMarketPart.orderBook) {
              manual!.completedBooks.add(receipt.key.itemId);
            }
          },
          onRateLimited: () => _rateLimitedRegions.add(region),
          priorityKeys: () => region == preferences.region
              ? _priorityIds(
                  all ? targets[_selectionKey] ?? const {} : ids,
                ).map(key)
              : const <SharedMarketKey>[],
          onProgress: onProgress,
        );
        // Broadcast delivery is asynchronous. Merge the completed call now so
        // refresh + calculationSettled includes its final receipt too; a later
        // identical stream event is then a no-op, not another calculation.
        for (final entry in batch.items.entries) {
          _mergeMarketItem(entry.key.region, entry.value);
        }
        _recordMarketResult(
          previousReceipts: currentReceipts(),
          failures: batch.failures.keys.toSet(),
          received: {
            for (final entry in batch.items.entries)
              entry.key.itemId: entry.value,
          },
        );
        rateLimited = batch.rateLimited;
        pause = batch.pauses[region];
        retryable = batch.retryableFailures.intersection(_scanParts);
      } else {
        final batch = await service!.fetchMarket(
          quoteIds: quoteIds,
          bookIds: bookIds,
          recovery: recovery,
          userInitiated: userInitiated,
          cancellationToken: token,
          onItem: receive,
          onRateLimited: () => _rateLimitedRegions.add(region),
          priorityIds: () => region == preferences.region
              ? _priorityIds(all ? targets[_selectionKey] ?? const {} : ids)
              : const <String>[],
          onProgress: onProgress,
        );
        _recordMarketResult(
          previousReceipts: previousReceipts,
          failures: {
            for (final part in previousReceipts.keys)
              if ((batch.rateLimited ||
                      batch.failures.containsKey(part.key.itemId)) &&
                  !_partIsFresh(part, batch.items[part.key.itemId]))
                part,
          },
          received: batch.items,
        );
        rateLimited = batch.rateLimited;
        pause = batch.pause;
        retryable = {
          for (final id in batch.retryableQuoteFailures)
            _marketPart(region, id, SharedMarketPart.quote),
          for (final id in batch.retryableBookFailures)
            _marketPart(region, id, SharedMarketPart.orderBook),
        };
      }
      if (rateLimited) _rateLimitedRegions.add(region);
      // Refusing an existing pause (including one restored from disk) is not
      // a new server denial. Network denials create a new pause instance.
      final earlierPause = pause != null && identical(pause, knownPause);
      if (!_disposed) {
        if (token.isCancelled) {
          _setRegionNotice(
            region,
            _scopeCancellation ? null : 'Stopped. Loaded prices are kept.',
          );
        } else if (rateLimited) {
          if (pause != null) {
            _noteMarketPause(region, pause, earlierPause: earlierPause);
          }
        }
      }
      if (!token.isCancelled) {
        _finishRecoveryAttempt(
          region,
          attempted: _scanParts.toSet(),
          retryable: retryable,
          pause: pause,
          earlierPause: earlierPause,
        );
      }
    } on MarketFetchCancelledException {
      if (!_disposed) {
        _setRegionNotice(
          region,
          _scopeCancellation ? null : 'Stopped. Loaded prices are kept.',
        );
      }
    } on Object catch (error) {
      if (!_disposed) {
        if (token.isCancelled ||
            !_recoverTransientScanFailure(region, currentReceipts(), error)) {
          _setRegionNotice(
            region,
            'The market could not be reached. Try again in a moment.',
          );
        }
      }
    } finally {
      if (service != null) {
        _regionConcurrency[region] = service.effectiveConcurrency;
        // The fallback creates a service per scan. Preserve its server block
        // before closing it, including cancellation after the block arrived.
        if (service.blockedUntil case final until?) {
          final previous = _fallbackBlockedUntil[region];
          if (previous == null || until.isAfter(previous)) {
            _fallbackBlockedUntil[region] = until;
          }
        }
        if (service.pause case final pause?) {
          _fallbackPauses[region] = pause;
        } else if (receivedFreshPart) {
          _fallbackPauses.remove(region);
          _fallbackBlockedUntil.remove(region);
        }
        service.close();
      }
      // One history commit per scan, including completed receipts before Stop.
      // Disk I/O must not hold up network workers or visible price results.
      if (observations.isNotEmpty) {
        _queueObservations(region, observations.values.toList());
      }
      _flushSharedObservations();
      _queueCacheSave();
      _marketPublishTimer?.cancel();
      _marketPublishTimer = null;
      scanning = false;
      _scanRegion = null;
      _scanParts = {};
      _scanScope = null;
      _scanIsDepth = false;
      _scopeCancellation = false;
      _scanningAll = false;
      _cancellation = null;
      progressFraction = null;
      _scanCompletion?.complete();
      _scanCompletion = null;
      if (token.isCancelled &&
          _recoveryCycles[region]?.stage == _RecoveryStage.loading) {
        _recoveryCycles[region]!.stage = _RecoveryStage.idle;
      }
      if (!_disposed) publish();
    }
  }

  void _queueCacheSave() {
    _cacheSaveTimer?.cancel();
    _cacheSaveTimer = null;
    if (sharedMarket != null) return;
    if (!_cacheDirty || _cacheQueuedRevision == _cacheRevision) return;
    final revision = _cacheRevision;
    _cacheQueuedRevision = revision;
    final snapshot = {
      for (final region in _regionItems.entries)
        region.key: Map<String, OpportunityMarketItem>.of(region.value),
    };
    _cacheTail = _cacheTail.then((_) async {
      try {
        await _marketCache.save(snapshot);
        if (revision == _cacheRevision) _cacheDirty = false;
      } on Object {
        if (_cacheQueuedRevision == revision) _cacheQueuedRevision = -1;
        if (!_disposed) {
          notice ??= 'Prices loaded, but could not be saved for next time.';
          notifyListeners();
        }
      }
    });
  }

  void _receiveSharedReceipt(SharedMarketReceipt receipt) {
    if (_disposed || receipt.key.subId != 0) return;
    final region = receipt.key.region;
    final item = receipt.item;
    final changed = _mergeMarketItem(region, item);
    if (!receipt.fromCache && receipt.part == SharedMarketPart.quote) {
      _sharedObservations.putIfAbsent(region, () => {})[item.itemId] = item;
      _sharedObservationTimer ??= Timer(
        const Duration(seconds: 2),
        _flushSharedObservations,
      );
    }
    if (!changed) return;
    _marketPublishTimer ??= Timer(const Duration(milliseconds: 200), () {
      _marketPublishTimer = null;
      if (_disposed) return;
      _marketRevision++;
      recalculate(marketUpdate: true);
    });
  }

  SharedMarketPartKey _marketPart(
    String region,
    String id,
    SharedMarketPart part,
  ) => SharedMarketPartKey(SharedMarketKey(region: region, itemId: id), part);

  String? get _recoveryNotice {
    final cycle = _recoveryCycles[preferences.region];
    return switch (cycle?.stage) {
      _RecoveryStage.waitingTransient =>
        'Retrying missing market data shortly.',
      _RecoveryStage.waitingThrottle =>
        'Market is busy. Retrying automatically.',
      _RecoveryStage.protected =>
        cycle!.protectionWasEarlier
            ? 'Market access was blocked earlier. Prices are kept. Try Refresh.'
            : 'Market access is blocked. Loaded prices are kept.',
      _ => null,
    };
  }

  void _resumeManualMarketCheck() {
    if (scanning ||
        _manualMarketRefresh != null ||
        _disposed ||
        _flushDepth > 0) {
      return;
    }
    _autoCheckTimer?.cancel();
    _pendingAutoCheckAll = false;
    _pendingAutoCheckMaxAge = null;
    _selectionRevision++;
    _cancelRecoveryTimer();
    _automaticStoppedRegions.remove(preferences.region);
    _marketPausedForFlush = false;
    final previous = _recoveryCycles[preferences.region];
    if (previous?.waiting == true) {
      previous!.stage = _RecoveryStage.idle;
      previous.dueAt = null;
    } else {
      _recoveryCycles[preferences.region] = _MarketRecoveryCycle(clock())
        ..targets.addAll(previous?.targets ?? const {});
    }
  }

  void _cancelRecoveryTimer() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryTimerRegion = null;
    _recoveryTimerDueAt = null;
    _recoveryGeneration++;
  }

  bool _needsMarketPart(SharedMarketPartKey part) {
    if (_marketFailures.containsKey(part)) {
      return !_hasNewerReceipt(part, _marketFailures[part]);
    }
    return !_partIsFresh(part, _regionItems[part.key.region]?[part.key.itemId]);
  }

  void _noteMarketPause(
    String region,
    MarketRequestPause pause, {
    bool earlierPause = false,
  }) {
    final cycle = _recoveryCycles.putIfAbsent(
      region,
      () => _MarketRecoveryCycle(clock()),
    );
    cycle.pause = pause;
    _setRegionNotice(region, null);
    if (pause.reason == MarketRequestPauseReason.protected) {
      cycle.protectionWasEarlier = earlierPause;
      cycle.stage = _RecoveryStage.protected;
      if (_recoveryTimerRegion == region) _cancelRecoveryTimer();
    } else if (!autoCheck) {
      _setRegionNotice(
        region,
        'Market requests are temporarily blocked. Loaded prices are kept. Try Refresh later.',
      );
    }
  }

  void _settleRecoveryCycle(String region) {
    final cycle = _recoveryCycles[region];
    if (cycle == null) return;
    cycle.retryableParts.removeWhere((part) => !_needsMarketPart(part));
    if (cycle.targets.every((part) => !_needsMarketPart(part))) {
      cycle.stage = _RecoveryStage.complete;
      cycle.pause = null;
      cycle.dueAt = null;
      _setRegionNotice(region, null);
      if (_recoveryTimerRegion == region) _cancelRecoveryTimer();
    } else if (cycle.stage == _RecoveryStage.complete) {
      cycle.stage = _RecoveryStage.idle;
    } else if (cycle.waiting && cycle.retryableParts.isEmpty) {
      cycle.stage = _RecoveryStage.incomplete;
      cycle.dueAt = null;
      if (_recoveryTimerRegion == region) _cancelRecoveryTimer();
    }
  }

  void _finishRecoveryAttempt(
    String region, {
    required Set<SharedMarketPartKey> attempted,
    required Set<SharedMarketPartKey> retryable,
    required MarketRequestPause? pause,
    bool earlierPause = false,
  }) {
    final cycle = _recoveryCycles[region];
    if (cycle == null ||
        _disposed ||
        _automaticStoppedRegions.contains(region)) {
      return;
    }
    // An ordinary depth scan may temporarily mark this same cycle as loading.
    // Its completion must preserve the deadline of previously failed parts.
    final earlierDueAt = cycle.dueAt;
    cycle.retryableParts
      ..removeAll(attempted)
      ..addAll(retryable);
    cycle.stage = _RecoveryStage.idle;
    cycle.pause = pause;
    if (pause != null) {
      _noteMarketPause(region, pause, earlierPause: earlierPause);
    }
    if (pause?.reason == MarketRequestPauseReason.protected) return;
    // The pause cause is authoritative, including a429 after an earlier
    // timeout in the same batch. A retryable-part set cannot identify it.
    final throttled = pause?.reason == MarketRequestPauseReason.throttled;
    if (pause != null) {
      cycle.retryableParts.addAll(attempted.where(_needsMarketPart));
    }
    _settleRecoveryCycle(region);
    if (cycle.stage == _RecoveryStage.complete) return;
    if (!autoCheck ||
        _flushDepth > 0 ||
        _marketPausedForFlush ||
        cycle.retryableParts.isEmpty) {
      cycle.stage = _RecoveryStage.incomplete;
      cycle.dueAt = null;
      return;
    }
    final delay = _automaticRetryDelay(
      throttled ? cycle.throttleRetries : cycle.transientRetries,
    );
    var dueAt = clock().add(delay);
    // Other successful/newly requested parts must not keep postponing a
    // failure's existing deadline. A newer server pause may still extend it.
    if (earlierDueAt != null && earlierDueAt.isBefore(dueAt)) {
      dueAt = earlierDueAt;
    }
    if (pause != null && pause.retryAt.isAfter(dueAt)) dueAt = pause.retryAt;
    cycle.stage = throttled
        ? _RecoveryStage.waitingThrottle
        : _RecoveryStage.waitingTransient;
    cycle.dueAt = dueAt;
    _armRecoveryTimer(region, cycle);
  }

  void _armRecoveryTimer(String region, _MarketRecoveryCycle cycle) {
    if (!autoCheck ||
        region != preferences.region ||
        !cycle.waiting ||
        _disposed ||
        _flushDepth > 0 ||
        _marketPausedForFlush ||
        _automaticStoppedRegions.contains(region)) {
      return;
    }
    final pause = sharedMarket?.pauseFor(region) ?? _fallbackPauses[region];
    if (pause?.reason == MarketRequestPauseReason.protected) {
      _noteMarketPause(region, pause!, earlierPause: true);
      return;
    }
    var dueAt = cycle.dueAt ?? clock();
    if (pause != null && pause.retryAt.isAfter(dueAt)) dueAt = pause.retryAt;
    cycle.dueAt = dueAt;
    if (_recoveryTimerRegion == region &&
        _recoveryTimer?.isActive == true &&
        _recoveryTimerDueAt == dueAt) {
      return;
    }
    _cancelRecoveryTimer();
    _recoveryTimerRegion = region;
    _recoveryTimerDueAt = dueAt;
    final generation = _recoveryGeneration;
    final delay = dueAt.difference(clock());
    _recoveryTimer = _recoveryTimerFactory(
      delay.isNegative ? Duration.zero : delay,
      () async {
        if (_disposed ||
            generation != _recoveryGeneration ||
            region != preferences.region ||
            !identical(_recoveryCycles[region], cycle) ||
            _automaticStoppedRegions.contains(region) ||
            _flushDepth > 0 ||
            _marketPausedForFlush) {
          return;
        }
        _recoveryTimer = null;
        _recoveryTimerRegion = null;
        _recoveryTimerDueAt = null;
        _reconcileMarketFailures(region);
        _settleRecoveryCycle(region);
        final ordinaryScanOwnsCycle =
            scanning && _scanRegion == region && cycle.dueAt != null;
        if (!cycle.waiting && !ordinaryScanOwnsCycle) {
          notifyListeners();
          return;
        }
        // A same-region ordinary check may still be completing; do not cancel
        // its caller merely to start the recovery lane.
        await _scanCompletion?.future;
        await _manualMarketRefresh?.done.future;
        if (_disposed ||
            generation != _recoveryGeneration ||
            region != preferences.region ||
            !identical(_recoveryCycles[region], cycle) ||
            !cycle.waiting ||
            _automaticStoppedRegions.contains(region) ||
            _flushDepth > 0 ||
            _marketPausedForFlush) {
          return;
        }
        final currentPause =
            sharedMarket?.pauseFor(region) ?? _fallbackPauses[region];
        if (currentPause?.reason == MarketRequestPauseReason.protected) {
          _noteMarketPause(region, currentPause!, earlierPause: true);
          notifyListeners();
          return;
        }
        var currentDueAt = cycle.dueAt ?? clock();
        if (currentPause != null &&
            currentPause.retryAt.isAfter(currentDueAt)) {
          currentDueAt = currentPause.retryAt;
          cycle.dueAt = currentDueAt;
        }
        if (currentDueAt.isAfter(clock())) {
          _armRecoveryTimer(region, cycle);
          return;
        }
        final parts = cycle.retryableParts
            .where(
              (part) =>
                  _needsMarketPart(part) &&
                  (part.part == SharedMarketPart.quote ||
                      _activeDepthIds.contains(part.key.itemId)),
            )
            .toSet();
        if (parts.isEmpty) {
          _settleRecoveryCycle(region);
          notifyListeners();
          return;
        }
        if (cycle.stage == _RecoveryStage.waitingThrottle) {
          cycle.throttleRetries++;
        } else {
          cycle.transientRetries++;
        }
        cycle.dueAt = null;
        cycle.stage = _RecoveryStage.loading;
        await _refreshTargets(
          {'$region:recovery': parts.map((part) => part.key.itemId).toSet()},
          onlyStale: false,
          all: true,
          recoveryParts: parts,
          recovery: true,
          detail: parts.any((part) => part.part == SharedMarketPart.orderBook),
        );
      },
    );
  }

  static Duration _automaticRetryDelay(int completedRetries) =>
      switch (completedRetries) {
        0 => const Duration(seconds: 5),
        1 => const Duration(seconds: 20),
        2 => const Duration(minutes: 1),
        3 => const Duration(minutes: 2),
        _ => const Duration(minutes: 5),
      };

  bool _recoverTransientScanFailure(
    String region,
    Map<SharedMarketPartKey, DateTime?> previousReceipts,
    Object error,
  ) {
    if (error is! TimeoutException && !isRetryableMarketTransportError(error)) {
      return false;
    }
    final attempted = previousReceipts.keys.toSet();
    _recordMarketResult(
      previousReceipts: previousReceipts,
      failures: attempted,
      received: const {},
    );
    final pause = sharedMarket?.pauseFor(region) ?? _fallbackPauses[region];
    _finishRecoveryAttempt(
      region,
      attempted: attempted,
      retryable: attempted.where(_needsMarketPart).toSet(),
      pause: pause,
      earlierPause: pause != null,
    );
    return true;
  }

  DateTime? _partReceiptAt(
    SharedMarketPartKey part,
    OpportunityMarketItem? item,
  ) => part.part == SharedMarketPart.quote
      ? item?.quoteFetchedAt
      : item?.bookFetchedAt;

  bool _partIsFresh(SharedMarketPartKey part, OpportunityMarketItem? item) =>
      (part.part == SharedMarketPart.quote
          ? item?.quoteIsFresh(clock(), maxMarketAge)
          : item?.bookIsFresh(clock(), maxMarketAge)) ??
      false;

  bool _hasNewerReceipt(SharedMarketPartKey part, DateTime? previous) {
    final item = _regionItems[part.key.region]?[part.key.itemId];
    final at = _partReceiptAt(part, item);
    return _partIsFresh(part, item) &&
        at != null &&
        (previous == null || at.isAfter(previous));
  }

  bool _reconcileMarketFailures(String region) {
    final before = _marketFailures.length;
    _marketFailures.removeWhere(
      (part, previous) =>
          part.key.region == region && _hasNewerReceipt(part, previous),
    );
    return _marketFailures.length != before;
  }

  void _recordMarketResult({
    required Map<SharedMarketPartKey, DateTime?> previousReceipts,
    required Set<SharedMarketPartKey> failures,
    required Map<String, OpportunityMarketItem> received,
  }) {
    for (final entry in previousReceipts.entries) {
      final part = entry.key;
      // A completed successful part is authoritative even when a clock has
      // coarse resolution. Failed calls may retain old cache data; they are
      // cleared only by a genuinely newer receipt, not that retained value.
      if (!failures.contains(part) &&
          _partIsFresh(part, received[part.key.itemId])) {
        _marketFailures.remove(part);
      } else if (failures.contains(part) &&
          !_hasNewerReceipt(part, entry.value)) {
        _marketFailures[part] = entry.value;
      }
    }
  }

  bool _mergeMarketItem(String region, OpportunityMarketItem item) {
    final cache = _regionItems.putIfAbsent(region, () => {});
    final before = cache[item.itemId];
    final merged = before?.mergeFrom(item) ?? item;
    final changed = !_sameMarketData(before, merged);
    if (changed) {
      cache[item.itemId] = merged;
      _changedMarketIds.putIfAbsent(region, () => {}).add(item.itemId);
    }
    final recovered = _reconcileMarketFailures(region);
    _settleRecoveryCycle(region);
    return changed || recovered;
  }

  void _flushSharedObservations() {
    _sharedObservationTimer?.cancel();
    _sharedObservationTimer = null;
    for (final entry in _sharedObservations.entries) {
      _queueObservations(entry.key, entry.value.values.toList());
    }
    _sharedObservations.clear();
  }

  void _queueObservations(String region, List<OpportunityMarketItem> items) {
    _observationTail = _observationTail.then((_) async {
      try {
        await _observations.record(region, items);
        final cache = _regionItems[region];
        if (cache != null) {
          cache.addAll(_observations.withActivity(region, cache, now: clock()));
        }
        if (!_disposed && preferences.region == region) {
          // Sales history changes descriptive activity only, not ingredients,
          // listing prices, current orders, or any financial calculation.
          notifyListeners();
        }
      } on Object {
        if (!_disposed) {
          notice ??= 'Prices loaded, but sales history could not be saved.';
          notifyListeners();
        }
      }
    });
  }

  void cancel() {
    _automaticStoppedRegions.add(preferences.region);
    final cycle = _recoveryCycles[preferences.region];
    if (cycle != null) cycle.stage = _RecoveryStage.stopped;
    _cancelMarketCalls();
  }

  void _cancelMarketCalls() {
    _manualMarketRefresh?.cancelled = true;
    _scopeCancellation = false;
    _pendingDepthCheck = false;
    _pendingDepthMaxAge = null;
    _forceDepthCheck = false;
    _depthUserInitiated = false;
    _cardInterestTimer?.cancel();
    _cardInterestTimer = null;
    _cardEntryMaxAge = null;
    _cancelRecoveryTimer();
    _autoCheckTimer?.cancel();
    _pendingAutoCheckAll = false;
    _pendingAutoCheckMaxAge = null;
    _selectionRevision++;
    _cancellation?.cancel();
  }

  void _save() {
    if (!_preferencesDirty) return;
    final revision = _preferenceRevision;
    final snapshot = OpportunitiesPreferences.fromJson(preferences.toJson());
    _saveTail = _saveTail.then((_) async {
      try {
        await _preferencesStore.save(snapshot);
        saveError = null;
        if (revision == _preferenceRevision) _preferencesDirty = false;
      } on Object {
        saveError = 'Opportunities settings could not be saved.';
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> flush() async {
    _flushDepth++;
    _marketPausedForFlush = true;
    _cacheExpiryTimer?.cancel();
    _recalculateTimer?.cancel();
    try {
      await ready;
      _autoCheckTimer?.cancel();
      _selectionRevision++;
      _cancelMarketCalls();
      await _scanCompletion?.future;
      _flushSharedObservations();
      await _observationTail;
      _queueCacheSave();
      await _cacheTail;
      try {
        await sharedMarket?.flush();
      } on Object {
        notice ??= 'Prices loaded, but could not be saved for next time.';
      }
      _saveTimer?.cancel();
      _marketPublishTimer?.cancel();
      _save();
      await _saveTail;
      if (saveError != null) throw StateError(saveError!);
    } finally {
      _flushDepth--;
      // A close/profile operation owns the boundary. Only the next ordinary
      // recalculation or tab activation may resume expiration and auto-checks.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _itemInfoController?.dispose();
    _autoCheckTimer?.cancel();
    cancel();
    _recalculateTimer?.cancel();
    _saveTimer?.cancel();
    _marketPublishTimer?.cancel();
    _cacheExpiryTimer?.cancel();
    unawaited(_sharedSubscription?.cancel());
    _flushSharedObservations();
    _queueCacheSave();
    for (final mode in appController.modes.values) {
      mode.state.removeListener(_plannerChanged);
    }
    appController.marketTax.removeListener(_plannerChanged);
    super.dispose();
  }
}

final class _ManualMarketRefresh {
  _ManualMarketRefresh(this.region);
  final String region;
  final attemptedBooks = <String>{};
  final completedBooks = <String>{};
  final done = Completer<void>();
  bool cancelled = false;
}

enum _RecoveryStage {
  idle,
  loading,
  waitingTransient,
  waitingThrottle,
  complete,
  incomplete,
  protected,
  stopped,
}

final class _MarketRecoveryCycle {
  _MarketRecoveryCycle(this.startedAt);
  final DateTime startedAt;
  final Set<SharedMarketPartKey> targets = {};
  final Set<SharedMarketPartKey> retryableParts = {};
  int transientRetries = 0;
  int throttleRetries = 0;
  DateTime? dueAt;
  MarketRequestPause? pause;
  bool protectionWasEarlier = false;
  _RecoveryStage stage = _RecoveryStage.idle;
  bool get waiting =>
      stage == _RecoveryStage.waitingTransient ||
      stage == _RecoveryStage.waitingThrottle;
}

Recipe _withMarketId(Recipe recipe, String? id) => Recipe(
  name: recipe.name,
  type: recipe.type,
  baseOutput: recipe.baseOutput,
  group: recipe.group,
  method: recipe.method,
  ingredients: recipe.ingredients,
  marketId: id,
  sourceNote: recipe.sourceNote,
  vendor: recipe.vendor,
  location: recipe.location,
  npcPrice: recipe.npcPrice,
  qualityBase: recipe.qualityBase,
  qualityGrade: recipe.qualityGrade,
  outputMinimum: recipe.outputMinimum,
  outputMaximum: recipe.outputMaximum,
  role: recipe.role,
  variants: recipe.variants,
  defaultVariantId: recipe.defaultVariantId,
);

bool _sameMarketData(OpportunityMarketItem? a, OpportunityMarketItem b) {
  bool sameLevels(
    List<OpportunityMarketLevel>? x,
    List<OpportunityMarketLevel>? y,
  ) {
    if (x == null || y == null) return x == null && y == null;
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i].price != y[i].price || x[i].quantity != y[i].quantity) {
        return false;
      }
    }
    return true;
  }

  return a != null &&
      a.quoteFetchedAt == b.quoteFetchedAt &&
      a.bookFetchedAt == b.bookFetchedAt &&
      a.basePrice == b.basePrice &&
      a.stock == b.stock &&
      a.aggregateStock == b.aggregateStock &&
      a.totalTrades == b.totalTrades &&
      a.lastSoldAt == b.lastSoldAt &&
      a.unlisted == b.unlisted &&
      sameLevels(a.asks, b.asks) &&
      sameLevels(a.bids, b.bids);
}

OpportunityQuote _unknownRareOutput(
  OpportunityQuote source,
  String name,
  OpportunityMarketItem? output,
) => OpportunityQuote(
  recipeName: name,
  selectedVariantId: source.selectedVariantId,
  variantLabel: source.variantLabel,
  batchMultiplier: source.batchMultiplier,
  crafts: source.crafts,
  outputPerCraft: null,
  expectedOutput: null,
  outputMarket: output,
  ingredients: source.ingredients,
  listingRevenue: null,
  inputCost: source.inputCost,
  preliminaryInputCost: source.preliminaryInputCost,
  estimatedInputCost: source.estimatedInputCost,
  extraCostPerRun: source.extraCostPerRun,
  extraCostPerCraft: source.extraCostPerCraft,
  customSalePrice: source.customSalePrice,
  buyerRevenue: null,
  buyerFilledQuantity: 0,
  marketReady: false,
  buyersCoverOutput: false,
  inputCapacityKnown: source.inputCapacityKnown,
  inputCraftCapacity: source.inputCraftCapacity,
  buyerCraftCapacity: null,
  estimatedSeconds: null,
  issues: {
    ...source.issues.where(
      (issue) => !const {
        OpportunityIssue.outputUnlisted,
        OpportunityIssue.outputMarketUnknown,
        OpportunityIssue.outputQuoteStale,
        OpportunityIssue.outputBookUnknown,
        OpportunityIssue.outputBookStale,
        OpportunityIssue.insufficientBuyers,
      }.contains(issue),
    ),
    OpportunityIssue.invalidOutput,
    if (output == null) OpportunityIssue.outputMarketUnknown,
    if (output?.unlisted == true) OpportunityIssue.outputUnlisted,
  },
);

double? _currentDemand(
  OpportunityMarketItem? item,
  DateTime now,
  Duration maxAge,
) => item == null || !item.bookIsFresh(now, maxAge)
    ? null
    : item.preorderCount?.toDouble();

final class _BestUseSource {
  _BestUseSource(
    this.state,
    this.recipes,
    this.inputNames,
    planning.PlannerRules rules,
  ) {
    for (final entry in inputNames.entries) {
      for (final name in entry.value) {
        final id = const OpportunityCalculator().marketItemId(
          name: name,
          recipes: recipes,
          rules: rules,
        );
        final identity = id == null ? 'name:${name.toLowerCase()}' : 'id:$id';
        consumers.putIfAbsent(identity, () => <String>{}).add(entry.key);
      }
    }
  }
  final ModeState state;
  final Map<String, Recipe> recipes;
  final Map<String, Set<String>> inputNames;
  final Map<String, Set<String>> consumers = {};
  final Map<String, Set<String>> marketIds = {};
  bool matches(ModeState next) =>
      mapEquals(state.recipeEdits, next.recipeEdits) &&
      mapEquals(state.ingredientMeta, next.ingredientMeta) &&
      setEquals(state.hiddenItems, next.hiddenItems);
}

final class _BestUseCandidateInput {
  const _BestUseCandidateInput(
    this.mode,
    this.recipe,
    this.recipes,
    this.state,
    this.npcPrices,
  );
  final CraftMode mode;
  final Recipe recipe;
  final Map<String, Recipe> recipes;
  final ModeState state;
  final Map<String, double> npcPrices;
}

final class _BestUseCalculationInput {
  const _BestUseCalculationInput({
    required this.revision,
    required this.itemName,
    required this.selectedItemId,
    required this.candidates,
    required this.rules,
    required this.tax,
    required this.market,
    required this.now,
    required this.maxMarketAge,
    required this.preferAvailableInputs,
  });
  final int revision;
  final String itemName;
  final String? selectedItemId;
  final List<_BestUseCandidateInput> candidates;
  final planning.PlannerRules rules;
  final MarketTax tax;
  final OpportunityMarketSnapshot market;
  final DateTime now;
  final Duration maxMarketAge;
  final bool preferAvailableInputs;
}

List<OpportunityBestUseQuote> _calculateBestUses(
  _BestUseCalculationInput input,
) => [
  for (final candidate in input.candidates)
    if (evaluateOpportunityBestUse(
          itemName: input.itemName,
          selectedItemId: input.selectedItemId,
          recipe: candidate.recipe,
          mode: candidate.mode,
          recipes: candidate.recipes,
          state: candidate.state,
          rules: input.rules,
          marketTax: input.tax,
          market: input.market,
          now: input.now,
          maxMarketAge: input.maxMarketAge,
          catalogNpcPrices: candidate.npcPrices,
          preferAvailableInputs: input.preferAvailableInputs,
        )
        case final OpportunityBestUseQuote result)
      result,
];

class _CalculationInput {
  const _CalculationInput({
    required this.revision,
    required this.recipeNames,
    required this.modeKey,
    required this.recipes,
    required this.state,
    required this.rules,
    required this.tax,
    required this.catalogNpcPrices,
    required this.market,
    required this.now,
    required this.maxMarketAge,
    required this.preferAvailableInputs,
    required this.saleMode,
  });
  final int revision;
  final Set<String> recipeNames;
  final String modeKey;
  final Map<String, Recipe> recipes;
  final ModeState state;
  final planning.PlannerRules rules;
  final MarketTax tax;
  final Map<String, double> catalogNpcPrices;
  final OpportunityMarketSnapshot market;
  final DateTime now;
  final Duration maxMarketAge;
  final bool preferAvailableInputs;
  final OpportunitySaleMode saleMode;
}

List<OpportunityQuote> _calculateRecipes(_CalculationInput input) => [
  for (final recipe in input.recipes.values)
    if (input.recipeNames.contains(recipe.name) &&
        recipe.isCraftable &&
        recipe.type.toLowerCase() == input.modeKey)
      OpportunityCalculator(catalogNpcPrices: input.catalogNpcPrices).evaluate(
        recipe: recipe,
        recipes: input.recipes,
        state: input.state,
        rules: input.rules,
        marketTax: input.tax,
        market: input.market,
        now: input.now,
        // Overview rows compare one complete craft without hidden global costs.
        // Detail inspections pass their own quantities and optional costs.
        preferAvailableInputs: input.preferAvailableInputs,
        saleMode: input.saleMode,
        maxMarketAge: input.maxMarketAge,
      ),
];
