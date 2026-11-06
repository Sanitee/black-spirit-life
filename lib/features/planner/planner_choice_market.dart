import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/state/planner_application_controller.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/market/shared_market_repository.dart';
import '../../data/opportunities/market_eligibility.dart';
import '../../domain/market/market_price_models.dart';
import '../../domain/models/catalog_models.dart';

// Recipe keys are immutable per document revision. Case-only imported labels
// (High-quality / High-Quality) must resolve the same exact item, without fuzzy
// matching or conflating different numeric identities.
final _choiceNameIndexes = Expando<Map<String, List<Recipe>>>();
List<Recipe> _choiceRecipes(Map<String, Recipe> recipes, String name) {
  final index = _choiceNameIndexes[recipes] ??= <String, List<Recipe>>{};
  if (index.isEmpty) {
    for (final recipe in recipes.values) {
      (index[normalizeMarketName(recipe.name)] ??= []).add(recipe);
    }
  }
  return index[normalizeMarketName(name)] ?? const [];
}

/// Exact reference identity, without changing the selected recipe or mode.
/// A missing cross-mode identity is usable only when all exact names agree.
({Recipe? recipe, bool npc, String? marketId}) choiceMarketIdentity(
  ModeFeatureController controller,
  String name, {
  bool acrossModes = false,
}) {
  final local = acrossModes
      ? _choiceRecipes(controller.recipes, name)
      : <Recipe>[?controller.recipes[name]];
  var recipe = local.length == 1 ? local.single : controller.recipes[name];
  ModeFeatureController source = controller;
  var excludedByFallback = false;
  var conflictingIdentities = false;
  if (acrossModes) {
    final candidates = [
      for (final mode in controller.owner.modes.values)
        for (final candidate in _choiceRecipes(mode.recipes, name))
          if (normalizeNumericMarketId(candidate.marketId ?? '') != null)
            (mode, candidate),
    ];
    final identities = candidates
        .map((entry) => normalizeNumericMarketId(entry.$2.marketId!))
        .toSet();
    conflictingIdentities = identities.length > 1;
    if (identities.length == 1 &&
        normalizeNumericMarketId(recipe?.marketId ?? '') == null) {
      source = candidates.first.$1;
      recipe = candidates.first.$2;
    }
    excludedByFallback = controller.owner.modes.values.any(
      (mode) => _choiceRecipes(mode.recipes, name).any(
        (candidate) => mode.state.value.market.isItemUnlisted(candidate.name),
      ),
    );
  }
  final npc =
      controller
          .resolveItemSource(recipe?.name ?? name, recipe: recipe)
          .npcPrice >
      0;
  // Reference-only quality grades may exist in the exact bundled identity
  // registry without a marketId on their recipe stub. Do not hide their stock.
  final id = conflictingIdentities
      ? null
      : normalizeNumericMarketId(
          recipe?.marketId ??
              (acrossModes
                  ? CatalogRepository.cached(
                      controller.owner.catalog,
                    ).bundledMarketId(name)
                  : null) ??
              '',
        );
  final eligible =
      id != null &&
      isOpportunityMarketRequestEligible(id) &&
      !excludedByFallback &&
      !controller.state.value.market.isItemUnlisted(name) &&
      !source.state.value.market.isItemUnlisted(name);
  return (recipe: recipe, npc: npc, marketId: eligible ? id : null);
}

/// Shared broker access, not a separate cache, profile field or request client.
class PlannerChoiceMarketScope extends InheritedTheme {
  const PlannerChoiceMarketScope({
    required this.repository,
    required super.child,
    super.key,
  });
  final SharedMarketRepository? repository;
  static SharedMarketRepository? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlannerChoiceMarketScope>()
      ?.repository;
  @override
  bool updateShouldNotify(PlannerChoiceMarketScope oldWidget) =>
      repository != oldWidget.repository;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      PlannerChoiceMarketScope(repository: repository, child: child);
}

class PlannerChoiceMarket extends StatefulWidget {
  const PlannerChoiceMarket({
    required this.controller,
    required this.names,
    required this.builder,
    this.preferNpcSources = false,
    this.resolveAcrossModes = false,
    super.key,
  });
  final ModeFeatureController controller;
  final List<String> names;

  /// Availability normally shows both sources. Purchase calculations may still
  /// prefer a vendor; that must not hide the market's informational badges.
  final bool preferNpcSources;
  final bool resolveAcrossModes;
  final Widget Function(
    BuildContext,
    OpportunityMarketItem? Function(String),
    DateTime,
  )
  builder;
  @override
  State<PlannerChoiceMarket> createState() => _PlannerChoiceMarketState();
}

class _PlannerChoiceMarketState extends State<PlannerChoiceMarket> {
  SharedMarketRepository? _repository;
  final Map<String, SharedMarketKey> _keys = {};
  MarketCancellationController? _request;
  StreamSubscription<SharedMarketReceipt>? _subscription;
  Timer? _publication, _expiry;
  String _identity = '';
  @override
  void initState() {
    super.initState();
    _listen(widget, true);
  }

  void _listen(PlannerChoiceMarket target, bool listen) {
    for (final controller
        in target.resolveAcrossModes
            ? target.controller.owner.modes.values
            : [target.controller]) {
      if (listen) {
        controller.state.addListener(_stateChanged);
      } else {
        controller.state.removeListener(_stateChanged);
      }
    }
  }

  void _stateChanged() {
    if (!mounted) return;
    _configure();
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(PlannerChoiceMarket oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.resolveAcrossModes != widget.resolveAcrossModes) {
      _listen(oldWidget, false);
      _listen(widget, true);
    }
    _configure();
  }

  void _configure() {
    final repository = PlannerChoiceMarketScope.of(context);
    final region = widget.controller.state.value.market.region.toLowerCase();
    final keys = <String, SharedMarketKey>{};
    for (final name in widget.names) {
      final item = choiceMarketIdentity(
        widget.controller,
        name,
        acrossModes: widget.resolveAcrossModes,
      );
      final id = item.marketId;
      if (id == null ||
          !const {'eu', 'na'}.contains(region) ||
          (widget.preferNpcSources && item.npc)) {
        continue;
      }
      keys[name] = SharedMarketKey(region: region, itemId: id);
    }
    final identity = keys.entries.map((e) => '${e.key}:${e.value}').join('|');
    if (identical(repository, _repository) && identity == _identity) return;
    _request?.cancel();
    _subscription?.cancel();
    _expiry?.cancel();
    _publication?.cancel();
    _publication = null;
    _repository = repository;
    _identity = identity;
    _keys
      ..clear()
      ..addAll(keys);
    if (repository == null || keys.isEmpty) return;
    final request = _request = MarketCancellationController();
    _subscription = repository.receipts.listen((receipt) {
      if (keys.values.contains(receipt.key)) _schedulePaint(request);
    });
    unawaited(_load(repository, request, keys.values.toSet()));
  }

  Future<void> _load(
    SharedMarketRepository repository,
    MarketCancellationController request,
    Set<SharedMarketKey> keys,
  ) async {
    try {
      await repository.fetch(
        quoteKeys: keys,
        bookKeys: keys,
        maxAge: sharedMarketFreshness,
        cancellationToken: request.token,
        onItem: (_) => _schedulePaint(request),
      );
    } catch (_) {
      // Failed/cancelled requests keep unknown values. The shared broker retains
      // its rate-limit/recovery state; opening a chooser never bypasses it.
    }
    _schedulePaint(request);
  }

  void _schedulePaint(MarketCancellationController request) {
    if (!mounted || request.isCancelled || !identical(request, _request)) {
      return;
    }
    _publication ??= Timer(const Duration(milliseconds: 100), () {
      _publication = null;
      if (mounted && !request.isCancelled && identical(request, _request)) {
        setState(() {});
      }
    });
  }

  OpportunityMarketItem? _item(String name) {
    final key = _keys[name];
    return key == null ? null : _repository?.cachedItem(key);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    _expiry?.cancel();
    DateTime? next;
    for (final key in _keys.keys) {
      final item = _item(key);
      for (final date in [item?.quoteFetchedAt, item?.bookFetchedAt]) {
        if (date == null) continue;
        final expires = date
            .add(sharedMarketFreshness)
            .add(const Duration(milliseconds: 1));
        if (expires.isAfter(now) && (next == null || expires.isBefore(next))) {
          next = expires;
        }
      }
    }
    if (next != null) {
      _expiry = Timer(next.difference(now), () {
        if (mounted) setState(() {});
      });
    }
    return widget.builder(context, _item, now);
  }

  @override
  void dispose() {
    _listen(widget, false);
    _request?.cancel();
    _subscription?.cancel();
    _publication?.cancel();
    _expiry?.cancel();
    super.dispose();
  }
}
