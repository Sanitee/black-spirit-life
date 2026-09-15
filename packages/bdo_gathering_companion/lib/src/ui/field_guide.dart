import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../assets.dart';
import '../domain/bairog_benchmarks.dart';
import '../domain/bairog_calculator.dart';
import '../domain/models.dart';
import '../domain/spot_performance.dart';
import '../services/gathering_market_service.dart';
import '../services/shared_market_loader.dart';
import '../services/native_bridge.dart';
import '../widgets/spot_map.dart';
import '../widgets/spot_media_gallery.dart';
import 'buff_picker.dart';
import 'theme.dart';

typedef SpotMarketPriceLoader =
    Future<Map<String, int>> Function(Map<String, String> itemsById);

typedef SpotMarketOrderBookLoader =
    Future<Map<String, GatheringMarketQuote>> Function(
      Map<String, String> itemsById, {
      bool includePreorders,
    });

final class _MarketBaseStage {
  const _MarketBaseStage({
    required this.quotes,
    this.unavailableItemIds = const <String>{},
    this.failedItemIds = const <String>{},
  });

  final Map<String, GatheringMarketQuote> quotes;
  final Set<String> unavailableItemIds;
  final Set<String> failedItemIds;
}

final class _MarketPreorderStage {
  const _MarketPreorderStage({
    required this.counts,
    this.failedItemIds = const <String>{},
    this.deferredItemIds = const <String>{},
  });

  final Map<String, int> counts;
  final Set<String> failedItemIds;
  final Set<String> deferredItemIds;
}

enum _SpotRanking {
  browse,
  sharp,
  dust,
  caphras,
  nostosCrackedTerrashard,
  nostosWitheredWoodChip,
  nostosThinEssenceOfLife,
  nostosDimHeartveinShard,
  nostosFaintWildsoul,
  nostosFadedNaturewovenHide,
  profit,
  demand,
}

enum _RankingSource { personal, bairog }

enum _SpotCardMode { browse, yield, value, demand }

enum _MarketLoadScope { value, demand }

enum _DemandSort { preorders, value }

enum _MarketPriceSource { market, custom, vendor }

enum _MarketEstimateBound { exact, lower, upper, partial }

final class _MarketContribution {
  const _MarketContribution({
    required this.itemId,
    required this.name,
    required this.icon,
    required this.perHour,
    required this.unitPrice,
    required this.grossValuePerHour,
    required this.netValuePerHour,
    required this.stock,
    required this.preorders,
    required this.vendorPrice,
    required this.priceSource,
    required this.fetchedAt,
    this.detailsOnly = false,
  });

  final String itemId;
  final String name;
  final String icon;
  final double perHour;
  final double? unitPrice;
  final double grossValuePerHour;
  final double netValuePerHour;
  final int? stock;
  final int? preorders;
  final bool vendorPrice;
  final _MarketPriceSource priceSource;
  final DateTime? fetchedAt;
  final bool detailsOnly;

  bool get missingPrice => unitPrice == null;
}

final class _MarketCostLine {
  const _MarketCostLine({
    required this.itemId,
    required this.name,
    required this.icon,
    required this.quantityPerHour,
    required this.unitPrice,
    required this.valuePerHour,
  });

  final String itemId;
  final String name;
  final String icon;
  final double quantityPerHour;
  final double? unitPrice;
  final double valuePerHour;

  bool get missingPrice => unitPrice == null;
}

final class _MarketContributionAccumulator {
  _MarketContributionAccumulator({
    required this.itemId,
    required this.name,
    required this.icon,
  });

  final String itemId;
  final String name;
  final String icon;
  double perHour = 0;
  double grossValuePerHour = 0;
  double netValuePerHour = 0;
  bool allVendorPrices = true;
  bool visibleOnCard = false;
  bool missingPrice = false;
  _MarketPriceSource priceSource = _MarketPriceSource.market;

  void add({
    required double amount,
    required double grossValue,
    required double netValue,
    required bool vendorPrice,
    required _MarketPriceSource source,
    required bool showOnCard,
  }) {
    perHour += amount;
    grossValuePerHour += grossValue;
    netValuePerHour += netValue;
    allVendorPrices &= vendorPrice;
    visibleOnCard |= showOnCard;
    if (source == _MarketPriceSource.custom ||
        (source == _MarketPriceSource.vendor &&
            priceSource == _MarketPriceSource.market)) {
      priceSource = source;
    }
  }

  void addMissing({required double amount}) {
    perHour += amount;
    missingPrice = true;
    allVendorPrices = false;
  }
}

final class _MarketSummary {
  const _MarketSummary({
    required this.contributions,
    required this.missingItemIds,
    required this.compactCardItemIds,
    this.costLines = const <_MarketCostLine>[],
    this.missingCostItemIds = const <String>{},
    this.hourlyExpenses = 0,
    this.goldKeyExpenses = 0,
    this.calculatedTotal,
    this.missingGoldKeyPrice = false,
  });

  final List<_MarketContribution> contributions;
  final Set<String> missingItemIds;
  final List<String> compactCardItemIds;
  final List<_MarketCostLine> costLines;
  final Set<String> missingCostItemIds;
  final double hourlyExpenses;
  final double goldKeyExpenses;
  final double? calculatedTotal;
  final bool missingGoldKeyPrice;

  double get grossIncome => contributions.fold(
    0.0,
    (total, contribution) => total + contribution.grossValuePerHour,
  );

  double get afterTaxIncome => contributions.fold(
    0.0,
    (total, contribution) => total + contribution.netValuePerHour,
  );

  double get marketplaceTax => math.max(0, grossIncome - afterTaxIncome);

  bool get hasPricedIncome => contributions.any(
    (contribution) =>
        !contribution.missingPrice && contribution.netValuePerHour > 0,
  );

  _MarketEstimateBound get estimateBound {
    final missingIncome = missingItemIds.isNotEmpty;
    final missingCosts = missingCostItemIds.isNotEmpty;
    if (missingIncome && missingCosts) return _MarketEstimateBound.partial;
    if (missingIncome) return _MarketEstimateBound.lower;
    if (missingCosts) return _MarketEstimateBound.upper;
    return _MarketEstimateBound.exact;
  }

  double get total =>
      calculatedTotal ??
      contributions.fold(
            0.0,
            (total, contribution) => total + contribution.netValuePerHour,
          ) -
          hourlyExpenses -
          goldKeyExpenses;

  _MarketContribution? get lowestSupply {
    final listed =
        contributions
            .where(
              (entry) =>
                  !entry.detailsOnly &&
                  entry.stock != null &&
                  entry.perHour > 0,
            )
            .toList()
          ..sort((a, b) {
            final coverage = (a.stock! / a.perHour).compareTo(
              b.stock! / b.perHour,
            );
            if (coverage != 0) return coverage;
            final value = b.netValuePerHour.compareTo(a.netValuePerHour);
            if (value != 0) return value;
            return b.perHour.compareTo(a.perHour);
          });
    return listed.firstOrNull;
  }

  _MarketContribution? get highestPreorders {
    final ordered =
        contributions
            .where(
              (entry) =>
                  !entry.detailsOnly &&
                  entry.preorders != null &&
                  entry.preorders! > 0 &&
                  entry.perHour > 0,
            )
            .toList()
          ..sort((a, b) {
            final preorders = b.preorders!.compareTo(a.preorders!);
            if (preorders != 0) return preorders;
            final aCoverage = a.stock == null
                ? double.infinity
                : a.stock! / a.perHour;
            final bCoverage = b.stock == null
                ? double.infinity
                : b.stock! / b.perHour;
            final coverage = aCoverage.compareTo(bCoverage);
            if (coverage != 0) return coverage;
            return b.netValuePerHour.compareTo(a.netValuePerHour);
          });
    return ordered.firstOrNull;
  }

  _MarketContribution? get demandItem => highestPreorders ?? lowestSupply;
}

/// Presents Bairog's immutable route evidence with yields recalculated for the
/// user's current calculator setup. Route speed, sessions, hours, videos, and
/// map coordinates always remain the audited Bairog source facts.
final class _BairogRouteView {
  const _BairogRouteView({
    required this.source,
    this.projection,
    this.settings = const BairogCalculatorSettings(),
  });

  final BairogRouteBenchmark source;
  final BairogRouteProjection? projection;
  final BairogCalculatorSettings settings;

  int get sourceRouteId => source.sourceRouteId;
  String get sourceRouteName => source.sourceRouteName;
  String? get spotId => source.spotId;
  String get methodId => source.methodId;
  String get videoUrl => source.videoUrl;
  int get gathersPerHour =>
      projection?.effectiveGathersPerHour ?? source.gathersPerHour;
  int get sourceSessionCount => source.sourceSessionCount;
  double get sourceHours => source.sourceHours;
  String get sourceUpdatedOn => source.sourceUpdatedOn;
  bool get isMapped => source.isMapped;

  Iterable<BairogItemYield> get itemYields {
    final calculated = projection;
    if (calculated == null) return source.itemYields;
    final metadata = <int, BairogGatheringItemType>{};
    final amounts = <int, double>{};
    for (final item in calculated.items) {
      if (settings.hiddenDropItemTypeIds.contains(item.itemType.id) ||
          (!settings.includeEvergreenShard &&
              item.itemType.item.id == bairogEvergreenShardItemId)) {
        continue;
      }
      metadata.putIfAbsent(item.itemType.item.id, () => item.itemType);
      amounts.update(
        item.itemType.item.id,
        (value) => value + item.totalPerHour,
        ifAbsent: () => item.totalPerHour,
      );
    }
    return amounts.entries.map((entry) {
      final itemType = metadata[entry.key];
      final sourceItem = source.itemYield(entry.key);
      return BairogItemYield(
        itemId: entry.key,
        name: itemType?.item.name ?? sourceItem?.name ?? '${entry.key}',
        perHour: entry.value,
        vendorUnitPrice:
            itemType?.vendorUnitPrice?.round() ?? sourceItem?.vendorUnitPrice,
      );
    });
  }

  double? customUnitPrice(int bdoItemId) {
    final calculated = projection;
    if (calculated == null) return null;
    for (final item in calculated.items) {
      if (item.itemType.item.id != bdoItemId) continue;
      final custom = settings.customItemPrices[item.itemType.id];
      if (custom != null) return custom;
    }
    return null;
  }

  double marketMultiplier(int bdoItemId) {
    final calculated = projection;
    if (calculated != null) {
      for (final item in calculated.items) {
        if (item.itemType.item.id != bdoItemId ||
            item.itemType.vendorUnitPrice != null) {
          continue;
        }
        final taxed =
            settings.dropTaxed[item.itemType.id] ?? settings.showTaxed;
        return taxed ? settings.marketNetRate : 1;
      }
    }
    return settings.showTaxed ? settings.marketNetRate : 1;
  }

  BairogItemYield? itemYield(int itemId) {
    for (final item in itemYields) {
      if (item.itemId == itemId) return item;
    }
    return null;
  }

  BairogItemYield get nostosYield {
    final projected = itemYield(source.yieldProfile.nostosItemId);
    if (projected != null) return projected;
    if (projection == null) return source.nostosYield;
    return BairogItemYield(
      itemId: source.yieldProfile.nostosItemId,
      name: source.yieldProfile.nostosItemName,
      perHour: 0,
    );
  }

  double score(BairogBenchmarkGoal goal) => switch (goal) {
    BairogBenchmarkGoal.sharp => itemYield(4998)?.perHour ?? 0,
    BairogBenchmarkGoal.dust => itemYield(721002)?.perHour ?? 0,
    BairogBenchmarkGoal.caphras => itemYield(721003)?.perHour ?? 0,
    BairogBenchmarkGoal.sourceValue =>
      projection?.netSilverPerHour ??
          source.sourceSilverAfterTaxPerHour.toDouble(),
  };
}

final class _SpotListEntry {
  const _SpotListEntry({required this.spot, this.performance, this.benchmark});

  final Spot? spot;
  final SpotPerformance? performance;
  final _BairogRouteView? benchmark;

  String get key => benchmark == null
      ? 'spot-${spot!.id}'
      : 'route-${benchmark!.sourceRouteId}';
}

class FieldGuide extends StatefulWidget {
  const FieldGuide({
    super.key,
    required this.catalog,
    required this.onUse,
    this.sessions = const <GatheringSession>[],
    this.initialSpot,
    this.initialMethodId,
    this.onUseWithMethod,
    this.marketPriceLoader,
    this.marketQuoteLoader,
    this.marketOrderBookLoader,
    this.sharedMarketLoader,
    this.sharedMarketUpdates,
    this.marketFreshFor = const Duration(minutes: 2),
    this.bairogCalculatorData,
    this.bairogSettings = const BairogCalculatorSettings(),
    this.navigationRequest = 0,
    this.initialFiltersExpanded = false,
    this.useLabel = 'Use spot',
  });
  final Catalog catalog;
  final List<GatheringSession> sessions;
  final Spot? initialSpot;
  final String? initialMethodId;
  final ValueChanged<Spot> onUse;
  final void Function(Spot, String)? onUseWithMethod;

  /// Legacy price-only hook retained for existing embedders and tests.
  final SpotMarketPriceLoader? marketPriceLoader;

  /// Rich current Marketplace quotes, including seller listings and time.
  final GatheringMarketLoader? marketQuoteLoader;

  /// Rich quote loader for hosts that can explicitly request current buy orders.
  final SpotMarketOrderBookLoader? marketOrderBookLoader;
  final GatheringSharedMarketLoader? sharedMarketLoader;
  final Stream<GatheringMarketReceipt>? sharedMarketUpdates;
  final Duration marketFreshFor;

  /// The captured public calculator tables used to recalculate Bairog's
  /// per-route estimates for [bairogSettings]. A null value keeps the audited
  /// fixed benchmark as a safe offline fallback.
  final BairogCalculatorData? bairogCalculatorData;
  final BairogCalculatorSettings bairogSettings;
  final int navigationRequest;
  final bool initialFiltersExpanded;
  final String useLabel;

  @override
  State<FieldGuide> createState() => _FieldGuideState();
}

class _FieldGuideState extends State<FieldGuide> {
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  final _stripScroll = ScrollController();
  final _detailScroll = ScrollController();
  double _listReturnOffset = 0;
  double _stripReturnOffset = 0;
  Spot? _selected;
  _BairogRouteView? _selectedBenchmark;
  String _method = 'all';
  String? _detailMethodId;
  _SpotRanking _ranking = _SpotRanking.browse;
  _RankingSource _rankingSource = _RankingSource.bairog;
  _DemandSort _demandSort = _DemandSort.preorders;
  Map<String, GatheringMarketQuote> _marketQuotes =
      const <String, GatheringMarketQuote>{};
  Set<String> _unavailableMarketIds = const <String>{};
  final Map<String, DateTime> _baseCoveredAtById = <String, DateTime>{};
  final Map<String, DateTime> _baseRetryAfterById = <String, DateTime>{};
  final Map<String, DateTime> _preorderCoveredAtById = <String, DateTime>{};
  final Map<String, DateTime> _preorderRetryAfterById = <String, DateTime>{};
  Future<void>? _marketLoad;
  _MarketLoadScope? _marketLoadScope;
  bool _marketLoading = false;
  final Set<String> _calculationLoadingEntries = <String>{};
  String? _marketError;
  bool _filterRailExpanded = false;
  late List<_BairogRouteView> _bairogRoutes;

  Duration get _marketFreshFor => widget.marketFreshFor;
  StreamSubscription<GatheringMarketReceipt>? _sharedMarketSubscription;
  Completer<void>? _sharedMarketCancellation;
  int _sharedMarketGeneration = 0;
  final Set<String> _sharedMarketIds = {};
  final Map<String, GatheringMarketReceipt> _pendingSharedReceipts = {};
  final Map<String, (int, DateTime)> _sharedPreorderParts = {};
  Timer? _sharedMarketPublishTimer;
  static const _marketRetryAfter = Duration(seconds: 30);
  static const _nostosMarketPriority = <String>[
    '821348',
    '821349',
    '821350',
    '821351',
    '821352',
    '821353',
  ];
  static const _legacyItemIconAliases = <String, String>{
    '820014': 'assets/icons/items/821371.webp',
    '6210': 'assets/icons/items/6203.webp',
    '821116': 'assets/icons/items/4624.webp',
  };

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSpot;
    _method = _validMethod(widget.initialMethodId);
    _filterRailExpanded = widget.initialFiltersExpanded;
    _bairogRoutes = _buildBairogRoutes();
    _subscribeSharedMarket();
  }

  String _validMethod(String? id) =>
      widget.catalog.methods.any((method) => method.id == id) ? id! : 'all';

  List<_BairogRouteView> _buildBairogRoutes() {
    final data = widget.bairogCalculatorData;
    if (data == null) {
      return <_BairogRouteView>[
        for (final route in bairogBenchmarkSet.routes)
          _BairogRouteView(source: route),
      ];
    }
    final calculator = BairogCalculator(data);
    final prices = <int, double>{};
    for (final entry in _marketQuotes.entries) {
      final id = int.tryParse(entry.key);
      if (id != null) prices[id] = entry.value.price.toDouble();
    }
    return <_BairogRouteView>[
      for (final route in bairogBenchmarkSet.routes)
        if (data.rotationsById.containsKey(route.sourceRouteId))
          _BairogRouteView(
            source: route,
            settings: widget.bairogSettings,
            projection: calculator.projectRoute(
              routeId: route.sourceRouteId,
              settings: widget.bairogSettings,
              marketPricesByBdoItemId: prices,
            ),
          )
        else
          _BairogRouteView(source: route, settings: widget.bairogSettings),
    ];
  }

  String get _setupCompactLabel {
    final rate = widget.bairogSettings.gatheringDropRatePercent;
    return '${widget.bairogSettings.mastery} mastery · '
        '${_plainNumber(rate)}% GDR · '
        '${_compactMinigameLabel(widget.bairogSettings.minigameMode)}';
  }

  String get _setupAccessibleLabel =>
      '${widget.bairogSettings.mastery} mastery · '
      '${_plainNumber(widget.bairogSettings.gatheringDropRatePercent)}% '
      'Gathering Item Drop Rate';

  @override
  void didUpdateWidget(FieldGuide old) {
    super.didUpdateWidget(old);
    if (old.sharedMarketUpdates != widget.sharedMarketUpdates) {
      _subscribeSharedMarket();
    }
    final projectionInputsChanged =
        old.catalog != widget.catalog ||
        old.bairogCalculatorData != widget.bairogCalculatorData ||
        !old.bairogSettings.hasSameValuesAs(widget.bairogSettings);
    final marketCostScopeChanged =
        !_sameIds(
          old.bairogSettings.enabledExpenseItemIds,
          widget.bairogSettings.enabledExpenseItemIds,
        ) ||
        (old.bairogSettings.includeChest ||
                old.bairogSettings.includeChestX10) !=
            (widget.bairogSettings.includeChest ||
                widget.bairogSettings.includeChestX10);
    if (projectionInputsChanged) _bairogRoutes = _buildBairogRoutes();
    if (old.initialSpot?.id != widget.initialSpot?.id ||
        old.navigationRequest != widget.navigationRequest) {
      _selected = widget.initialSpot;
      _selectedBenchmark = null;
      _detailMethodId = null;
      if (old.navigationRequest == widget.navigationRequest) _search.clear();
    }
    if (old.initialMethodId != widget.initialMethodId) {
      _method = _validMethod(widget.initialMethodId);
      _detailMethodId = null;
      if (_selected != null &&
          _method != 'all' &&
          !_selected!.methodIds.contains(_method)) {
        _selected = null;
      }
    }
    final selected = _selected;
    if (selected != null &&
        _isGoalRanking &&
        _rankingSource == _RankingSource.bairog) {
      _selectedBenchmark = _bestBairogBenchmark(selected);
    }
    if (_usesMarket && marketCostScopeChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _usesMarket) {
          unawaited(_refreshMarketAfterSetupCostChange());
        }
      });
    }
  }

  bool _sameIds(Set<int> first, Set<int> second) =>
      first.length == second.length && first.containsAll(second);

  Future<void> _refreshMarketAfterSetupCostChange() async {
    final running = _marketLoad;
    if (running != null && widget.sharedMarketLoader == null) await running;
    if (!mounted || !_usesMarket) return;
    await _loadMarketQuotes(replaceScope: widget.sharedMarketLoader != null);
  }

  @override
  void dispose() {
    _sharedMarketGeneration++;
    _cancelSharedMarketWaiter();
    _sharedMarketSubscription?.cancel();
    _sharedMarketPublishTimer?.cancel();
    _search.dispose();
    _listScroll.dispose();
    _stripScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  List<SpotPerformance> get _performances =>
      aggregateSpotPerformance(widget.sessions);

  bool get _isGoalRanking =>
      _ranking == _SpotRanking.sharp ||
      _ranking == _SpotRanking.dust ||
      _ranking == _SpotRanking.caphras ||
      _isNostosRanking ||
      _ranking == _SpotRanking.profit ||
      _ranking == _SpotRanking.demand;

  bool get _usesMarket =>
      _ranking == _SpotRanking.profit || _ranking == _SpotRanking.demand;

  bool get _isNostosRanking => _nostosMaterial != null;

  BairogNostosMaterial? get _nostosMaterial => switch (_ranking) {
    _SpotRanking.nostosCrackedTerrashard => bairogNostosMaterials[0],
    _SpotRanking.nostosWitheredWoodChip => bairogNostosMaterials[1],
    _SpotRanking.nostosThinEssenceOfLife => bairogNostosMaterials[2],
    _SpotRanking.nostosDimHeartveinShard => bairogNostosMaterials[3],
    _SpotRanking.nostosFaintWildsoul => bairogNostosMaterials[4],
    _SpotRanking.nostosFadedNaturewovenHide => bairogNostosMaterials[5],
    _ => null,
  };

  _SpotCardMode get _cardMode => switch (_ranking) {
    _SpotRanking.browse => _SpotCardMode.browse,
    _SpotRanking.sharp ||
    _SpotRanking.dust ||
    _SpotRanking.caphras ||
    _SpotRanking.nostosCrackedTerrashard ||
    _SpotRanking.nostosWitheredWoodChip ||
    _SpotRanking.nostosThinEssenceOfLife ||
    _SpotRanking.nostosDimHeartveinShard ||
    _SpotRanking.nostosFaintWildsoul ||
    _SpotRanking.nostosFadedNaturewovenHide => _SpotCardMode.yield,
    _SpotRanking.profit => _SpotCardMode.value,
    _SpotRanking.demand => _SpotCardMode.demand,
  };

  BairogBenchmarkGoal get _bairogGoal => switch (_ranking) {
    _SpotRanking.sharp => BairogBenchmarkGoal.sharp,
    _SpotRanking.dust => BairogBenchmarkGoal.dust,
    _SpotRanking.caphras => BairogBenchmarkGoal.caphras,
    _SpotRanking.profit => BairogBenchmarkGoal.sourceValue,
    _SpotRanking.demand => BairogBenchmarkGoal.sourceValue,
    _SpotRanking.nostosCrackedTerrashard ||
    _SpotRanking.nostosWitheredWoodChip ||
    _SpotRanking.nostosThinEssenceOfLife ||
    _SpotRanking.nostosDimHeartveinShard ||
    _SpotRanking.nostosFaintWildsoul ||
    _SpotRanking.nostosFadedNaturewovenHide => throw StateError(
      'Nostos rankings use the selected material yield.',
    ),
    _ => throw StateError('The current view is not a benchmark goal.'),
  };

  List<_SpotListEntry> get _visibleEntries {
    final terms = _search.text.toLowerCase().trim().split(RegExp(r'\s+'));
    final filteredTerms = terms.where((term) => term.isNotEmpty).toList();
    if (_isGoalRanking && _rankingSource == _RankingSource.bairog) {
      final spotsById = <String, Spot>{
        for (final spot in widget.catalog.spots) spot.id: spot,
      };
      final entries = _bairogRoutes
          .where((benchmark) {
            final spot = benchmark.spotId == null
                ? null
                : spotsById[benchmark.spotId];
            final searchable =
                '${benchmark.sourceRouteName} ${spot?.displayName ?? ''} '
                        '${spot?.nodeName ?? ''} ${spot?.region ?? ''}'
                    .toLowerCase();
            final nostos = _nostosMaterial;
            return (_method == 'all' || benchmark.methodId == _method) &&
                (nostos == null ||
                    (benchmark.nostosYield.itemId == nostos.itemId &&
                        benchmark.nostosYield.perHour > 0)) &&
                filteredTerms.every(searchable.contains);
          })
          .map((benchmark) {
            final spot = benchmark.spotId == null
                ? null
                : spotsById[benchmark.spotId];
            return _SpotListEntry(spot: spot, benchmark: benchmark);
          })
          .toList();
      entries.sort((a, b) {
        final aBenchmark = a.benchmark!;
        final bBenchmark = b.benchmark!;
        final score = _ranking == _SpotRanking.demand
            ? _compareMarketDemand(
                _marketSummaryForBenchmark(aBenchmark),
                _marketSummaryForBenchmark(bBenchmark),
              )
            : _benchmarkScore(
                bBenchmark,
              ).compareTo(_benchmarkScore(aBenchmark));
        if (score != 0) return score;
        final evidence = bBenchmark.sourceHours.compareTo(
          aBenchmark.sourceHours,
        );
        if (evidence != 0) return evidence;
        return aBenchmark.sourceRouteName.compareTo(bBenchmark.sourceRouteName);
      });
      return entries;
    }

    final performances = _performances;
    final spots = widget.catalog.spots.where((spot) {
      final searchable =
          '${spot.displayName} ${spot.nodeName} ${spot.name} ${spot.region} '
                  '${spot.materials.map((item) => item['name']).join(' ')}'
              .toLowerCase();
      return (_method == 'all' || spot.methodIds.contains(_method)) &&
          filteredTerms.every(searchable.contains) &&
          switch (_ranking) {
            _SpotRanking.sharp ||
            _SpotRanking.dust ||
            _SpotRanking.caphras ||
            _SpotRanking.nostosCrackedTerrashard ||
            _SpotRanking.nostosWitheredWoodChip ||
            _SpotRanking.nostosThinEssenceOfLife ||
            _SpotRanking.nostosDimHeartveinShard ||
            _SpotRanking.nostosFaintWildsoul ||
            _SpotRanking.nostosFadedNaturewovenHide ||
            _SpotRanking.profit ||
            _SpotRanking.demand => _hasPersonalResult(spot, performances),
            _SpotRanking.browse => true,
          };
    }).toList();
    if (_ranking == _SpotRanking.sharp ||
        _ranking == _SpotRanking.dust ||
        _ranking == _SpotRanking.caphras ||
        _isNostosRanking ||
        _ranking == _SpotRanking.profit ||
        _ranking == _SpotRanking.demand) {
      spots.sort((a, b) {
        final aPerformance = _bestPerformance(a, performances)!;
        final bPerformance = _bestPerformance(b, performances)!;
        final score = _ranking == _SpotRanking.demand
            ? _compareMarketDemand(
                _marketSummaryForPerformance(aPerformance),
                _marketSummaryForPerformance(bPerformance),
              )
            : _score(bPerformance).compareTo(_score(aPerformance));
        if (score != 0) return score;
        final evidence = bPerformance.durationSeconds.compareTo(
          aPerformance.durationSeconds,
        );
        if (evidence != 0) return evidence;
        return a.priority.compareTo(b.priority);
      });
    }
    return <_SpotListEntry>[
      for (final spot in spots)
        _SpotListEntry(
          spot: spot,
          performance: _isGoalRanking
              ? _bestPerformance(spot, performances)
              : null,
        ),
    ];
  }

  List<Spot> get _visibleSpots {
    final seen = <String>{};
    return <Spot>[
      for (final entry in _visibleEntries)
        if (entry.spot case final spot? when seen.add(spot.id)) spot,
    ];
  }

  bool _hasPersonalResult(Spot spot, [List<SpotPerformance>? candidates]) {
    final performance = _bestPerformance(spot, candidates);
    if (performance == null) return false;
    if (_ranking == _SpotRanking.profit) {
      return performance.itemTotals.values.any((value) => value > 0);
    }
    if (_ranking == _SpotRanking.demand) {
      return performance.itemTotals.values.any((value) => value > 0);
    }
    return _score(performance) > 0;
  }

  SpotPerformance? _bestPerformance(
    Spot spot, [
    List<SpotPerformance>? candidates,
  ]) {
    SpotPerformance? best;
    for (final performance in candidates ?? _performances) {
      if (performance.spotId != spot.id ||
          !spot.methodIds.contains(performance.methodId) ||
          (_method != 'all' && performance.methodId != _method)) {
        continue;
      }
      if (best == null) {
        best = performance;
        continue;
      }
      if (_ranking == _SpotRanking.demand) {
        if (_compareMarketDemand(
              _marketSummaryForPerformance(performance),
              _marketSummaryForPerformance(best),
            ) <
            0) {
          best = performance;
        }
      } else if (_score(performance) > _score(best)) {
        best = performance;
      }
    }
    return best;
  }

  double _score(SpotPerformance performance) =>
      _personalScore(performance, _ranking);

  double _personalScore(SpotPerformance performance, _SpotRanking ranking) =>
      switch (ranking) {
        _SpotRanking.sharp => performance.itemsPerHour('4998'),
        _SpotRanking.dust => performance.itemsPerHour('721002'),
        _SpotRanking.caphras => performance.itemsPerHour('721003'),
        _SpotRanking.nostosCrackedTerrashard ||
        _SpotRanking.nostosWitheredWoodChip ||
        _SpotRanking.nostosThinEssenceOfLife ||
        _SpotRanking.nostosDimHeartveinShard ||
        _SpotRanking.nostosFaintWildsoul ||
        _SpotRanking.nostosFadedNaturewovenHide => 0,
        _SpotRanking.profit => _marketSummaryForPerformance(performance).total,
        _SpotRanking.demand => _demandScore(
          _marketSummaryForPerformance(performance),
        ),
        _ => 0,
      };

  double _benchmarkScore(_BairogRouteView benchmark) {
    final nostos = _nostosMaterial;
    if (nostos != null) {
      return benchmark.nostosYield.itemId == nostos.itemId
          ? benchmark.nostosYield.perHour
          : 0;
    }
    return switch (_ranking) {
      _SpotRanking.profit => _marketSummaryForBenchmark(benchmark).total,
      _SpotRanking.demand => _demandScore(
        _marketSummaryForBenchmark(benchmark),
      ),
      _ => benchmark.score(_bairogGoal),
    };
  }

  int _compareMarketDemand(_MarketSummary a, _MarketSummary b) {
    final aCovered = _hasFreshDemandStockCoverage(a);
    final bCovered = _hasFreshDemandStockCoverage(b);
    if (aCovered != bCovered) return aCovered ? -1 : 1;
    if (!aCovered) return 0;
    final aPreordersCovered = _hasFreshDemandPreorderCoverage(a);
    final bPreordersCovered = _hasFreshDemandPreorderCoverage(b);
    if (aPreordersCovered != bPreordersCovered) {
      return aPreordersCovered ? -1 : 1;
    }
    final aPreorders = aPreordersCovered ? a.highestPreorders : null;
    final bPreorders = bPreordersCovered ? b.highestPreorders : null;
    if (aPreorders != null || bPreorders != null) {
      if (aPreorders == null) return 1;
      if (bPreorders == null) return -1;
    }
    if (_demandSort == _DemandSort.value) {
      final totalValue = b.total.compareTo(a.total);
      if (totalValue != 0) return totalValue;
    }
    if (aPreorders != null && bPreorders != null) {
      final preorderCount = bPreorders.preorders!.compareTo(
        aPreorders.preorders!,
      );
      if (preorderCount != 0) return preorderCount;
    }
    final aItem = aPreorders ?? a.lowestSupply;
    final bItem = bPreorders ?? b.lowestSupply;
    if (aItem == null) return bItem == null ? 0 : 1;
    if (bItem == null) return -1;
    final aCoverage = aItem.stock == null
        ? double.infinity
        : aItem.stock! / aItem.perHour;
    final bCoverage = bItem.stock == null
        ? double.infinity
        : bItem.stock! / bItem.perHour;
    final stock = aCoverage.compareTo(bCoverage);
    if (stock != 0) return stock;
    final value = bItem.netValuePerHour.compareTo(aItem.netValuePerHour);
    if (value != 0) return value;
    return bItem.perHour.compareTo(aItem.perHour);
  }

  double _demandScore(_MarketSummary summary) {
    if (!_hasFreshDemandStockCoverage(summary)) return 0;
    final hasCompletePreorders = _hasFreshDemandPreorderCoverage(summary);
    final item = _demandItemForSummary(summary);
    if (item == null) return 0;
    final scarcity = item.stock == null ? 0 : 1e12 / (item.stock! + 1);
    final preorders = item.preorders;
    if (hasCompletePreorders) {
      return 1e30 + (preorders ?? 0) * 1e18 + scarcity + item.netValuePerHour;
    }
    return scarcity + item.netValuePerHour;
  }

  _BairogRouteView? _bestBairogBenchmark(Spot spot) {
    final nostos = _nostosMaterial;
    if (nostos == null) {
      if (_usesMarket) {
        final routes = _bairogRoutes
            .where((route) => route.isMapped)
            .where(
              (route) =>
                  route.spotId == spot.id &&
                  (_method == 'all' || route.methodId == _method),
            )
            .toList();
        routes.sort((a, b) {
          if (_ranking == _SpotRanking.demand) {
            return _compareMarketDemand(
              _marketSummaryForBenchmark(a),
              _marketSummaryForBenchmark(b),
            );
          }
          return _benchmarkScore(b).compareTo(_benchmarkScore(a));
        });
        return routes.firstOrNull;
      }
      final routes =
          _bairogRoutes
              .where(
                (route) =>
                    route.isMapped &&
                    route.spotId == spot.id &&
                    (_method == 'all' || route.methodId == _method),
              )
              .toList()
            ..sort((a, b) => _benchmarkScore(b).compareTo(_benchmarkScore(a)));
      return routes.firstOrNull;
    }
    final routes =
        _bairogRoutes
            .where((route) => route.isMapped)
            .where(
              (route) =>
                  route.spotId == spot.id &&
                  route.nostosYield.itemId == nostos.itemId &&
                  (_method == 'all' || route.methodId == _method),
            )
            .toList()
          ..sort(
            (a, b) => b.nostosYield.perHour.compareTo(a.nostosYield.perHour),
          );
    return routes.firstOrNull;
  }

  void _filterChanged() {
    setState(() {
      if (!_visibleSpots.any((spot) => spot.id == _selected?.id)) {
        _selected = null;
        _selectedBenchmark = null;
      }
    });
  }

  Future<void> _setRanking(_SpotRanking ranking) async {
    setState(() {
      _ranking = ranking;
      if (ranking == _SpotRanking.sharp ||
          ranking == _SpotRanking.dust ||
          ranking == _SpotRanking.caphras ||
          _isNostosRanking ||
          ranking == _SpotRanking.profit ||
          ranking == _SpotRanking.demand) {
        _method = 'all';
        _detailMethodId = null;
        _rankingSource = _RankingSource.bairog;
      }
      _marketError = null;
      if (!_visibleSpots.any((spot) => spot.id == _selected?.id)) {
        _selected = null;
        _selectedBenchmark = null;
      } else if (_selected case final selected?) {
        _selectedBenchmark = _rankingSource == _RankingSource.bairog
            ? _bestBairogBenchmark(selected)
            : null;
      }
    });
    if (ranking == _SpotRanking.profit || ranking == _SpotRanking.demand) {
      await _loadMarketQuotes();
    }
  }

  void _setDemandSort(_DemandSort sort) {
    if (_demandSort == sort) return;
    setState(() {
      _demandSort = sort;
      if (_selected case final selected?) {
        _selectedBenchmark = _rankingSource == _RankingSource.bairog
            ? _bestBairogBenchmark(selected)
            : null;
      }
    });
  }

  Future<void> _loadMarketQuotes({
    bool force = false,
    _MarketLoadScope? scope,
    bool replaceScope = false,
  }) {
    final requestedScope =
        scope ??
        (_ranking == _SpotRanking.demand
            ? _MarketLoadScope.demand
            : _MarketLoadScope.value);
    final running = _marketLoad;
    if (running != null) {
      final runningScope = _marketLoadScope;
      final runningCoversRequest =
          runningScope == requestedScope ||
          (runningScope == _MarketLoadScope.demand &&
              requestedScope == _MarketLoadScope.value);
      if (!force && !replaceScope && runningCoversRequest) return running;
      if (widget.sharedMarketLoader == null) {
        return running.then(
          (_) => _loadMarketQuotes(force: force, scope: requestedScope),
        );
      }
      _cancelSharedMarketWaiter();
    }
    _marketLoadScope = requestedScope;
    final load = _loadMarketQuotesInner(
      force: force,
      fullPreorderCoverage: requestedScope == _MarketLoadScope.demand,
    );
    _marketLoad = load;
    return load.whenComplete(() {
      if (identical(_marketLoad, load)) {
        _marketLoad = null;
        _marketLoadScope = null;
      }
    });
  }

  Future<void> _loadMarketQuotesInner({
    required bool force,
    required bool fullPreorderCoverage,
  }) async {
    final vendorItemIds = <String>{
      for (final itemType
          in widget.bairogCalculatorData?.gatheringItemTypes ??
              const <BairogGatheringItemType>[])
        if (itemType.vendorUnitPrice != null) itemType.item.id.toString(),
      for (final route in _bairogRoutes)
        for (final item in route.itemYields)
          if (item.vendorUnitPrice != null) item.itemId.toString(),
    };
    final demandItems = <String, String>{};
    for (final session in widget.sessions) {
      for (final loot in session.loot) {
        if (loot.total > 0 &&
            RegExp(r'^\d+$').hasMatch(loot.id) &&
            !vendorItemIds.contains(loot.id)) {
          demandItems.putIfAbsent(loot.id, () => loot.name);
        }
      }
    }
    for (final route in _bairogRoutes) {
      for (final item in route.itemYields) {
        if (item.perHour > 0 && item.vendorUnitPrice == null) {
          demandItems.putIfAbsent(item.itemId.toString(), () => item.name);
        }
      }
    }
    final calculatorData = widget.bairogCalculatorData;
    if (calculatorData != null) {
      final bonusItemTypeIds = <int>{};
      for (final route in _bairogRoutes) {
        final projection = route.projection;
        if (projection == null) continue;
        final ratios = projection.route.typeRatios.isEmpty
            ? <BairogGatheringTypeRatio>[
                BairogGatheringTypeRatio(
                  gatheringTypeId: projection.route.gatheringTypeId,
                  ratio: 1,
                ),
              ]
            : projection.route.typeRatios;
        for (final ratio in ratios) {
          final type = calculatorData.gatheringTypesById[ratio.gatheringTypeId];
          if (type == null) continue;
          if (widget.bairogSettings.includeAfuaru) {
            bonusItemTypeIds.addAll(type.afuaruItemAverages.keys);
          }
          if (widget.bairogSettings.includeChest ||
              widget.bairogSettings.includeChestX10) {
            bonusItemTypeIds.addAll(type.chestItemAverages.keys);
          }
          if (widget.bairogSettings.includeFeverTime) {
            bonusItemTypeIds.addAll(type.feverTimeItemAverages.keys);
          }
        }
      }
      for (final itemTypeId in bonusItemTypeIds) {
        final itemType = calculatorData.gatheringItemTypesById[itemTypeId];
        if (itemType == null ||
            itemType.vendorUnitPrice != null ||
            widget.bairogSettings.hiddenDropItemTypeIds.contains(itemType.id) ||
            (!widget.bairogSettings.includeEvergreenShard &&
                itemType.item.id == bairogEvergreenShardItemId)) {
          continue;
        }
        demandItems.putIfAbsent(
          itemType.item.id.toString(),
          () => itemType.item.name,
        );
      }
    }
    final items = <String, String>{...demandItems};
    for (final expense in bairogEnergyExpenses) {
      if (widget.bairogSettings.enabledExpenseItemIds.contains(
        expense.bdoItemId,
      )) {
        items.putIfAbsent(expense.bdoItemId.toString(), () => expense.name);
      }
    }
    if (widget.bairogSettings.includeChest ||
        widget.bairogSettings.includeChestX10) {
      items.putIfAbsent('44164', () => 'Gold Key');
    }
    if (items.isEmpty) return;
    if (widget.sharedMarketLoader != null) {
      await _loadSharedMarketQuotes(
        items,
        demandItems: demandItems.keys,
        force: force,
        includePreorders: fullPreorderCoverage,
      );
      return;
    }
    final startedAt = DateTime.now().toUtc();
    final baseIds = <String>[
      for (final id in items.keys)
        if (_needsBaseRefresh(id, startedAt, force: force)) id,
    ];
    bool needsScopedPreorderRefresh(String id) {
      final stock = _marketQuotes[id]?.stock;
      return stock != null &&
          (fullPreorderCoverage || stock == 0) &&
          _needsPreorderRefresh(id, startedAt, force: force);
    }

    if (baseIds.isEmpty && !demandItems.keys.any(needsScopedPreorderRefresh)) {
      return;
    }
    setState(() {
      _marketLoading = true;
      _marketError = null;
    });
    final usesDefaultService =
        widget.marketOrderBookLoader == null &&
        widget.marketQuoteLoader == null &&
        widget.marketPriceLoader == null;
    final service = usesDefaultService ? GatheringMarketService() : null;
    try {
      final priorityBaseIds = fullPreorderCoverage
          ? <String>[
              for (final id in _nostosMarketPriority)
                if (baseIds.contains(id)) id,
            ]
          : const <String>[];
      final remainingBaseIds = <String>[
        for (final id in baseIds)
          if (!priorityBaseIds.contains(id)) id,
      ];
      var priorityBaseFailed = false;
      if (priorityBaseIds.isNotEmpty) {
        final stageItems = <String, String>{
          for (final id in priorityBaseIds) id: items[id]!,
        };
        final stage = await _fetchMarketBaseStage(stageItems, service: service);
        priorityBaseFailed = stage.failedItemIds.isNotEmpty;
        _mergeMarketBaseStage(stage, DateTime.now().toUtc());
      }
      if (remainingBaseIds.isNotEmpty) {
        if (priorityBaseFailed) {
          _deferBaseIds(remainingBaseIds, DateTime.now().toUtc());
        } else {
          final stageItems = <String, String>{
            for (final id in remainingBaseIds) id: items[id]!,
          };
          final stage = await _fetchMarketBaseStage(
            stageItems,
            service: service,
          );
          _mergeMarketBaseStage(stage, DateTime.now().toUtc());
        }
      }

      if (mounted) {
        final now = DateTime.now().toUtc();
        final preorderIds =
            <String>[
              for (final id in demandItems.keys)
                if (_marketQuotes[id]?.stock case final stock?
                    when (fullPreorderCoverage || stock == 0) &&
                        _needsPreorderRefresh(id, now, force: force))
                  id,
            ]..sort((a, b) {
              final aNostos = _nostosMarketPriority.indexOf(a);
              final bNostos = _nostosMarketPriority.indexOf(b);
              if (aNostos >= 0 || bNostos >= 0) {
                if (aNostos < 0) return 1;
                if (bNostos < 0) return -1;
                return aNostos.compareTo(bNostos);
              }
              final aStock = _marketQuotes[a]?.stock;
              final bStock = _marketQuotes[b]?.stock;
              final aZero = aStock == 0;
              final bZero = bStock == 0;
              if (aZero != bZero) return aZero ? -1 : 1;
              return (aStock ?? 0).compareTo(bStock ?? 0);
            });
        final priorityPreorderIds = <String>[
          for (final id in preorderIds)
            if (_nostosMarketPriority.contains(id)) id,
        ];
        final remainingPreorderIds = <String>[
          for (final id in preorderIds)
            if (!priorityPreorderIds.contains(id)) id,
        ];
        var priorityPreordersFailed = false;
        if (priorityPreorderIds.isNotEmpty) {
          final stageItems = <String, String>{
            for (final id in priorityPreorderIds) id: demandItems[id]!,
          };
          final stage = await _fetchMarketPreorderStage(
            stageItems,
            service: service,
          );
          priorityPreordersFailed =
              stage.failedItemIds.isNotEmpty ||
              stage.deferredItemIds.isNotEmpty;
          _mergeMarketPreorderStage(stage, DateTime.now().toUtc());
        }
        if (remainingPreorderIds.isNotEmpty) {
          if (priorityPreordersFailed) {
            _deferPreorderIds(remainingPreorderIds, DateTime.now().toUtc());
          } else {
            final stageItems = <String, String>{
              for (final id in remainingPreorderIds) id: demandItems[id]!,
            };
            final stage = await _fetchMarketPreorderStage(
              stageItems,
              service: service,
            );
            _mergeMarketPreorderStage(stage, DateTime.now().toUtc());
          }
        }
      }
      if (mounted) _updateMarketStatus(demandItems.keys);
    } catch (_) {
      if (mounted) {
        setState(
          () => _marketError = 'Market prices are unavailable right now.',
        );
      }
    } finally {
      service?.close();
      if (mounted) setState(() => _marketLoading = false);
    }
  }

  void _subscribeSharedMarket() {
    _sharedMarketSubscription?.cancel();
    _sharedMarketSubscription = widget.sharedMarketUpdates?.listen(
      _queueSharedMarketReceipt,
    );
  }

  void _cancelSharedMarketWaiter() {
    final cancellation = _sharedMarketCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  Future<void> _loadSharedMarketQuotes(
    Map<String, String> items, {
    required Iterable<String> demandItems,
    required bool force,
    required bool includePreorders,
  }) async {
    final loader = widget.sharedMarketLoader!;
    final generation = ++_sharedMarketGeneration;
    final cancellation = Completer<void>();
    _sharedMarketCancellation = cancellation;
    _sharedMarketIds
      ..clear()
      ..addAll(items.keys);
    setState(() {
      _marketLoading = true;
      _marketError = null;
    });
    try {
      final result = await loader(
        items,
        includePreorders: includePreorders,
        forceRefresh: force,
        cancelled: cancellation.future,
        onItem: (receipt) {
          if (generation == _sharedMarketGeneration &&
              !cancellation.isCompleted) {
            _queueSharedMarketReceipt(receipt);
          }
        },
      );
      if (!mounted || generation != _sharedMarketGeneration) return;
      _publishSharedMarketReceipts();
      final retryAt = DateTime.now().toUtc().add(_marketRetryAfter);
      for (final id in result.priceFailures) {
        _baseRetryAfterById[id] = retryAt;
      }
      for (final id in result.preorderFailures) {
        _preorderRetryAfterById[id] = retryAt;
      }
      _updateMarketStatus(demandItems);
    } catch (_) {
      if (mounted && generation == _sharedMarketGeneration) {
        _publishSharedMarketReceipts();
        setState(() {
          _marketError = 'Market prices are unavailable right now.';
        });
      }
    } finally {
      if (mounted && generation == _sharedMarketGeneration) {
        _sharedMarketCancellation = null;
        setState(() => _marketLoading = false);
      }
    }
  }

  void _queueSharedMarketReceipt(GatheringMarketReceipt receipt) {
    if (!mounted || !_sharedMarketIds.contains(receipt.itemId)) return;
    final prior = _pendingSharedReceipts[receipt.itemId];
    final useQuote =
        receipt.quoteFetchedAt != null &&
        (prior?.quoteFetchedAt == null ||
            !receipt.quoteFetchedAt!.isBefore(prior!.quoteFetchedAt!));
    final useBook =
        receipt.preorderFetchedAt != null &&
        (prior?.preorderFetchedAt == null ||
            !receipt.preorderFetchedAt!.isBefore(prior!.preorderFetchedAt!));
    _pendingSharedReceipts[receipt.itemId] = GatheringMarketReceipt(
      itemId: receipt.itemId,
      price: useQuote ? receipt.price : prior?.price,
      stock: useQuote ? receipt.stock : prior?.stock,
      quoteFetchedAt: useQuote ? receipt.quoteFetchedAt : prior?.quoteFetchedAt,
      unavailable: useQuote ? receipt.unavailable : prior?.unavailable ?? false,
      preorders: useBook ? receipt.preorders : prior?.preorders,
      preorderFetchedAt: useBook
          ? receipt.preorderFetchedAt
          : prior?.preorderFetchedAt,
    );
    // One projection update can cover many receipts from the shared pool.
    _sharedMarketPublishTimer ??= Timer(
      const Duration(milliseconds: 100),
      _publishSharedMarketReceipts,
    );
  }

  void _publishSharedMarketReceipts() {
    _sharedMarketPublishTimer?.cancel();
    _sharedMarketPublishTimer = null;
    if (!mounted || _pendingSharedReceipts.isEmpty) return;
    final receipts = _pendingSharedReceipts.values.toList();
    _pendingSharedReceipts.clear();
    final now = DateTime.now().toUtc();
    bool fresh(DateTime? at) =>
        at != null && !at.isAfter(now) && now.difference(at) < _marketFreshFor;
    setState(() {
      final merged = Map<String, GatheringMarketQuote>.from(_marketQuotes);
      final unavailable = Set<String>.from(_unavailableMarketIds);
      for (final receipt in receipts) {
        final id = receipt.itemId;
        if (!_sharedMarketIds.contains(id)) continue;
        final quoteAt = receipt.quoteFetchedAt;
        final priorQuoteAt = _baseCoveredAtById[id];
        if (fresh(quoteAt) &&
            (priorQuoteAt == null || !quoteAt!.isBefore(priorQuoteAt))) {
          if (receipt.unavailable) {
            merged.remove(id);
            unavailable.add(id);
            _baseCoveredAtById[id] = quoteAt!;
            _preorderCoveredAtById.remove(id);
            _sharedPreorderParts.remove(id);
          } else if (receipt.price case final price? when price > 0) {
            merged[id] = GatheringMarketQuote(
              itemId: int.parse(id),
              price: price,
              stock: receipt.stock != null && receipt.stock! >= 0
                  ? receipt.stock
                  : null,
              fetchedAt: quoteAt!,
              preorders: merged[id]?.preorders,
            );
            unavailable.remove(id);
            _baseCoveredAtById[id] = quoteAt;
            _baseRetryAfterById.remove(id);
          }
        }
        final bookAt = receipt.preorderFetchedAt;
        final priorBookAt = _sharedPreorderParts[id]?.$2;
        if (fresh(bookAt) &&
            receipt.preorders != null &&
            receipt.preorders! >= 0 &&
            (priorBookAt == null || !bookAt!.isBefore(priorBookAt))) {
          _sharedPreorderParts[id] = (receipt.preorders!, bookAt!);
        }
        final book = _sharedPreorderParts[id];
        final quote = merged[id];
        if (quote != null && book != null && fresh(book.$2)) {
          merged[id] = GatheringMarketQuote(
            itemId: quote.itemId,
            price: quote.price,
            stock: quote.stock,
            fetchedAt: quote.fetchedAt,
            preorders: book.$1,
          );
          _preorderCoveredAtById[id] = book.$2;
          _preorderRetryAfterById.remove(id);
        }
      }
      _marketQuotes = Map.unmodifiable(merged);
      _unavailableMarketIds = Set.unmodifiable(unavailable);
      _refreshMarketDerivedState();
    });
  }

  bool _needsBaseRefresh(String id, DateTime now, {required bool force}) {
    if (force) return true;
    final retryAfter = _baseRetryAfterById[id];
    if (retryAfter != null && now.isBefore(retryAfter)) return false;
    final coveredAt = _baseCoveredAtById[id];
    return coveredAt == null || now.difference(coveredAt) >= _marketFreshFor;
  }

  bool _needsPreorderRefresh(String id, DateTime now, {required bool force}) {
    if (force) return true;
    final retryAfter = _preorderRetryAfterById[id];
    if (retryAfter != null && now.isBefore(retryAfter)) return false;
    final coveredAt = _preorderCoveredAtById[id];
    final baseCoveredAt = _baseCoveredAtById[id];
    return coveredAt == null ||
        baseCoveredAt == null ||
        coveredAt.isBefore(baseCoveredAt) ||
        now.difference(baseCoveredAt) >= _marketFreshFor ||
        now.difference(coveredAt) >= _marketFreshFor;
  }

  int? _freshPreorderCount(
    String id,
    GatheringMarketQuote? quote, {
    DateTime? now,
  }) {
    final preorders = quote?.preorders;
    final baseCoveredAt = _baseCoveredAtById[id];
    final preorderCoveredAt = _preorderCoveredAtById[id];
    if (preorders == null ||
        baseCoveredAt == null ||
        preorderCoveredAt == null ||
        (widget.sharedMarketLoader == null &&
            preorderCoveredAt.isBefore(baseCoveredAt))) {
      return null;
    }
    final checkedAt = now ?? DateTime.now().toUtc();
    if (checkedAt.difference(baseCoveredAt) >= _marketFreshFor ||
        checkedAt.difference(preorderCoveredAt) >= _marketFreshFor) {
      return null;
    }
    return preorders;
  }

  Future<_MarketBaseStage> _fetchMarketBaseStage(
    Map<String, String> items, {
    required GatheringMarketService? service,
  }) async {
    try {
      if (service != null) {
        final batch = await service.fetchBaseQuotes(items.keys);
        return _MarketBaseStage(
          quotes: <String, GatheringMarketQuote>{
            for (final entry in batch.quotes.entries)
              entry.key.toString(): entry.value,
          },
          unavailableItemIds: {
            for (final id in batch.unavailableItemIds) id.toString(),
          },
          failedItemIds: {for (final id in batch.failedItemIds) id.toString()},
        );
      }
      final Map<String, GatheringMarketQuote> quotes;
      if (widget.marketOrderBookLoader case final loader?) {
        quotes = await loader(items, includePreorders: false);
      } else if (widget.marketQuoteLoader case final loader?) {
        quotes = await loader(items);
      } else if (widget.marketPriceLoader case final loader?) {
        final fetchedAt = DateTime.now().toUtc();
        final prices = await loader(items);
        quotes = <String, GatheringMarketQuote>{
          for (final entry in prices.entries)
            if (entry.value > 0 && items.containsKey(entry.key))
              entry.key: GatheringMarketQuote(
                itemId: int.parse(entry.key),
                price: entry.value,
                stock: null,
                fetchedAt: fetchedAt,
              ),
        };
      } else {
        throw StateError('No market loader is available.');
      }
      return _MarketBaseStage(
        quotes: {
          for (final entry in quotes.entries)
            if (items.containsKey(entry.key)) entry.key: entry.value,
        },
        failedItemIds: {
          for (final id in items.keys)
            if (!quotes.containsKey(id)) id,
        },
      );
    } catch (_) {
      return _MarketBaseStage(
        quotes: const <String, GatheringMarketQuote>{},
        failedItemIds: items.keys.toSet(),
      );
    }
  }

  Future<_MarketPreorderStage> _fetchMarketPreorderStage(
    Map<String, String> items, {
    required GatheringMarketService? service,
  }) async {
    try {
      if (service != null) {
        final batch = await service.fetchPreorderCounts(items.keys);
        return _MarketPreorderStage(
          counts: <String, int>{
            for (final entry in batch.counts.entries)
              entry.key.toString(): entry.value,
          },
          failedItemIds: {for (final id in batch.failedItemIds) id.toString()},
          deferredItemIds: {
            for (final id in batch.deferredItemIds) id.toString(),
          },
        );
      }
      final loader = widget.marketOrderBookLoader;
      if (loader == null) {
        return _MarketPreorderStage(
          counts: const <String, int>{},
          failedItemIds: items.keys.toSet(),
        );
      }
      final quotes = await loader(items, includePreorders: true);
      return _MarketPreorderStage(
        counts: <String, int>{
          for (final entry in quotes.entries)
            if (items.containsKey(entry.key) && entry.value.preorders != null)
              entry.key: entry.value.preorders!,
        },
        failedItemIds: {
          for (final id in items.keys)
            if (quotes[id]?.preorders == null) id,
        },
      );
    } catch (_) {
      return _MarketPreorderStage(
        counts: const <String, int>{},
        failedItemIds: items.keys.toSet(),
      );
    }
  }

  void _mergeMarketBaseStage(_MarketBaseStage stage, DateTime completedAt) {
    if (!mounted) return;
    setState(() {
      final merged = Map<String, GatheringMarketQuote>.from(_marketQuotes);
      final unavailable = Set<String>.from(_unavailableMarketIds);
      for (final entry in stage.quotes.entries) {
        final prior = merged[entry.key];
        final quote = entry.value;
        merged[entry.key] = GatheringMarketQuote(
          itemId: quote.itemId,
          price: quote.price,
          stock: quote.stock,
          fetchedAt: quote.fetchedAt,
          preorders: quote.preorders ?? prior?.preorders,
        );
        unavailable.remove(entry.key);
        _baseCoveredAtById[entry.key] = completedAt;
        _baseRetryAfterById.remove(entry.key);
        if (quote.preorders != null) {
          _preorderCoveredAtById[entry.key] = completedAt;
          _preorderRetryAfterById.remove(entry.key);
        }
      }
      for (final id in stage.unavailableItemIds) {
        merged.remove(id);
        unavailable.add(id);
        _baseCoveredAtById[id] = completedAt;
        _baseRetryAfterById.remove(id);
        _preorderCoveredAtById.remove(id);
        _preorderRetryAfterById.remove(id);
      }
      for (final id in stage.failedItemIds) {
        _baseCoveredAtById.remove(id);
        _preorderCoveredAtById.remove(id);
        _baseRetryAfterById[id] = completedAt.add(_marketRetryAfter);
      }
      _marketQuotes = Map.unmodifiable(merged);
      _unavailableMarketIds = Set.unmodifiable(unavailable);
      _refreshMarketDerivedState();
    });
  }

  void _mergeMarketPreorderStage(
    _MarketPreorderStage stage,
    DateTime completedAt,
  ) {
    if (!mounted) return;
    setState(() {
      final merged = Map<String, GatheringMarketQuote>.from(_marketQuotes);
      for (final entry in stage.counts.entries) {
        final quote = merged[entry.key];
        if (quote == null) continue;
        merged[entry.key] = GatheringMarketQuote(
          itemId: quote.itemId,
          price: quote.price,
          stock: quote.stock,
          preorders: entry.value,
          fetchedAt: quote.fetchedAt,
        );
        _preorderCoveredAtById[entry.key] = completedAt;
        _preorderRetryAfterById.remove(entry.key);
      }
      for (final id in <String>{
        ...stage.failedItemIds,
        ...stage.deferredItemIds,
      }) {
        _preorderCoveredAtById.remove(id);
        _preorderRetryAfterById[id] = completedAt.add(_marketRetryAfter);
      }
      _marketQuotes = Map.unmodifiable(merged);
      _refreshMarketDerivedState();
    });
  }

  void _deferBaseIds(Iterable<String> ids, DateTime now) {
    for (final id in ids) {
      _baseRetryAfterById[id] = now.add(_marketRetryAfter);
    }
  }

  void _deferPreorderIds(Iterable<String> ids, DateTime now) {
    for (final id in ids) {
      _preorderCoveredAtById.remove(id);
      _preorderRetryAfterById[id] = now.add(_marketRetryAfter);
    }
  }

  void _refreshMarketDerivedState() {
    _bairogRoutes = _buildBairogRoutes();
    final selected = _selected;
    if (selected != null &&
        _isGoalRanking &&
        _rankingSource == _RankingSource.bairog) {
      _selectedBenchmark = _bestBairogBenchmark(selected);
    }
  }

  void _updateMarketStatus(Iterable<String> demandIds) {
    if (!mounted) return;
    final hasQuote = _marketQuotes.isNotEmpty;
    final hasPending = demandIds.any((id) {
      final quote = _marketQuotes[id];
      return !_unavailableMarketIds.contains(id) && quote?.stock == null;
    });
    setState(() {
      _marketError = !hasQuote
          ? 'Market prices are unavailable right now.'
          : hasPending
          ? 'Some market data is still updating.'
          : null;
    });
  }

  bool _hasFreshDemandStockCoverage(_MarketSummary summary) {
    final now = DateTime.now().toUtc();
    for (final contribution in summary.contributions) {
      if (contribution.detailsOnly) continue;
      if (contribution.vendorPrice) continue;
      final coveredAt = _baseCoveredAtById[contribution.itemId];
      if (_unavailableMarketIds.contains(contribution.itemId) &&
          coveredAt != null &&
          now.difference(coveredAt) < _marketFreshFor) {
        continue;
      }
      if (contribution.stock == null ||
          coveredAt == null ||
          now.difference(coveredAt) >= _marketFreshFor) {
        return false;
      }
    }
    for (final id in summary.missingItemIds) {
      final coveredAt = _baseCoveredAtById[id];
      if (!_unavailableMarketIds.contains(id) ||
          coveredAt == null ||
          now.difference(coveredAt) >= _marketFreshFor) {
        return false;
      }
    }
    return true;
  }

  bool _hasFreshDemandPreorderCoverage(_MarketSummary summary) {
    if (!_hasFreshDemandStockCoverage(summary)) return false;
    final now = DateTime.now().toUtc();
    for (final contribution in summary.contributions) {
      if (contribution.detailsOnly) continue;
      if (contribution.vendorPrice) continue;
      final baseCoveredAt = _baseCoveredAtById[contribution.itemId];
      if (_unavailableMarketIds.contains(contribution.itemId) &&
          baseCoveredAt != null &&
          now.difference(baseCoveredAt) < _marketFreshFor) {
        continue;
      }
      if (_freshPreorderCount(
            contribution.itemId,
            _marketQuotes[contribution.itemId],
            now: now,
          ) ==
          null) {
        return false;
      }
    }
    return true;
  }

  _MarketContribution? _demandItemForSummary(_MarketSummary summary) =>
      _hasFreshDemandPreorderCoverage(summary)
      ? summary.highestPreorders ?? summary.lowestSupply
      : summary.lowestSupply;

  Set<String> _routePrimaryBdoIds(int routeId) {
    final data = widget.bairogCalculatorData;
    final ratios = data?.rotationsById[routeId]?.primaryItemRatios;
    if (data == null || ratios == null) return const <String>{};
    return <String>{
      for (final entry in ratios.entries)
        if (entry.value > 0 &&
            data.gatheringItemTypesById[entry.key]?.isPrimary == true)
          data.gatheringItemTypesById[entry.key]!.item.id.toString(),
    };
  }

  List<String> _primaryCardItemIdsForBenchmark(_BairogRouteView benchmark) {
    final ordered = <String>{};
    final yieldedItemIds = <String>{
      for (final item in benchmark.itemYields)
        if (item.perHour > 0) item.itemId.toString(),
    };
    final routePrimaryIds = _routePrimaryBdoIds(benchmark.sourceRouteId);
    final spot = widget.catalog.spots
        .where((entry) => entry.id == benchmark.spotId)
        .firstOrNull;
    if (spot != null && routePrimaryIds.isNotEmpty) {
      for (final material in spot.materials) {
        final itemId = textOf(material, 'itemId');
        if (strings(material['methodIds']).contains(benchmark.methodId) &&
            routePrimaryIds.contains(itemId) &&
            yieldedItemIds.contains(itemId)) {
          ordered.add(itemId);
        }
      }
    }
    for (final itemId in routePrimaryIds) {
      if (yieldedItemIds.contains(itemId)) ordered.add(itemId);
    }
    final projection = benchmark.projection;
    if (ordered.isEmpty && projection != null) {
      for (final item in projection.items) {
        if (item.itemType.isPrimary && item.basePerHour > 0) {
          ordered.add(item.itemType.item.id.toString());
        }
      }
    }
    if (ordered.isEmpty) {
      ordered.add(benchmark.source.yieldProfile.primaryItemId.toString());
    }
    return List.unmodifiable(ordered);
  }

  List<String> _compactCardItemIdsForBenchmark(_BairogRouteView benchmark) {
    final ordered = <String>{..._primaryCardItemIdsForBenchmark(benchmark)};
    ordered.addAll(_nostosMarketPriority);
    ordered
      ..add('4998')
      ..add('4999');
    return List.unmodifiable(ordered);
  }

  List<String> _compactCardItemIdsForPerformance(SpotPerformance performance) {
    final ordered = <String>{};
    final recordedItemIds = <String>{
      for (final entry in performance.itemTotals.entries)
        if (entry.value > 0) entry.key,
    };
    final benchmarks = _bairogRoutes.where(
      (entry) =>
          entry.spotId == performance.spotId &&
          entry.methodId == performance.methodId,
    );
    for (final benchmark in benchmarks) {
      for (final itemId in _primaryCardItemIdsForBenchmark(benchmark)) {
        if (recordedItemIds.contains(itemId)) ordered.add(itemId);
      }
    }
    final spot = widget.catalog.spots
        .where((entry) => entry.id == performance.spotId)
        .firstOrNull;
    if (spot != null) {
      if (ordered.isEmpty &&
          widget.catalog.methods
                  .where((entry) => entry.id == performance.methodId)
                  .firstOrNull
                  ?.activity ==
              'gathering') {
        final globalPrimaryIds = <String>{
          for (final itemType
              in widget.bairogCalculatorData?.gatheringItemTypesById.values ??
                  const <BairogGatheringItemType>[])
            if (itemType.isPrimary) itemType.item.id.toString(),
        };
        for (final material in spot.materials) {
          final itemId = textOf(material, 'itemId');
          if (strings(material['methodIds']).contains(performance.methodId) &&
              globalPrimaryIds.contains(itemId) &&
              recordedItemIds.contains(itemId)) {
            ordered.add(itemId);
          }
        }
      }
      if (ordered.isEmpty) {
        for (final material in spot.materials) {
          final itemId = textOf(material, 'itemId');
          if (strings(material['methodIds']).contains(performance.methodId) &&
              textOf(material, 'rarity') != 'rare' &&
              recordedItemIds.contains(itemId)) {
            ordered.add(itemId);
            break;
          }
        }
      }
    }
    ordered.addAll(_nostosMarketPriority);
    ordered
      ..add('4998')
      ..add('4999');
    return List.unmodifiable(ordered);
  }

  _MarketSummary _marketSummaryForBenchmark(_BairogRouteView benchmark) {
    final contributions = <_MarketContribution>[];
    final missing = <String>{};
    final projection = benchmark.projection;
    if (projection == null) {
      for (final item in benchmark.itemYields) {
        if (item.perHour <= 0) continue;
        final itemId = item.itemId.toString();
        final quote = _marketQuotes[itemId];
        final customPrice = benchmark.customUnitPrice(item.itemId);
        final unitPrice = customPrice ?? item.vendorUnitPrice ?? quote?.price;
        if (unitPrice == null || unitPrice <= 0) {
          missing.add(itemId);
          contributions.add(
            _MarketContribution(
              itemId: itemId,
              name: item.name,
              icon: _itemIcon(itemId),
              perHour: item.perHour,
              unitPrice: null,
              grossValuePerHour: 0,
              netValuePerHour: 0,
              stock: quote?.stock,
              preorders: _freshPreorderCount(itemId, quote),
              vendorPrice: false,
              priceSource: _MarketPriceSource.market,
              fetchedAt: quote?.fetchedAt,
              detailsOnly: true,
            ),
          );
          continue;
        }
        final vendor = item.vendorUnitPrice != null;
        final marketMultiplier = benchmark.marketMultiplier(item.itemId);
        final grossValue = item.perHour * unitPrice;
        contributions.add(
          _MarketContribution(
            itemId: itemId,
            name: item.name,
            icon: _itemIcon(itemId),
            perHour: item.perHour,
            unitPrice: unitPrice.toDouble(),
            grossValuePerHour: grossValue,
            netValuePerHour: grossValue * (vendor ? 1 : marketMultiplier),
            stock: vendor ? null : quote?.stock,
            preorders: vendor ? null : _freshPreorderCount(itemId, quote),
            vendorPrice: vendor,
            priceSource: customPrice != null
                ? _MarketPriceSource.custom
                : vendor
                ? _MarketPriceSource.vendor
                : _MarketPriceSource.market,
            fetchedAt: vendor ? null : quote?.fetchedAt,
          ),
        );
      }
    } else {
      final settings = benchmark.settings;
      final accumulated = <String, _MarketContributionAccumulator>{};
      for (final item in projection.items) {
        final itemType = item.itemType;
        if (item.totalPerHour <= 0 ||
            settings.hiddenDropItemTypeIds.contains(itemType.id) ||
            (!settings.includeEvergreenShard &&
                itemType.item.id == bairogEvergreenShardItemId)) {
          continue;
        }
        final itemId = itemType.item.id.toString();
        final quote = _marketQuotes[itemId];
        final customPrice = settings.customItemPrices[itemType.id];
        final vendorUnitPrice = itemType.vendorUnitPrice;
        final unitPrice = customPrice ?? vendorUnitPrice ?? quote?.price;
        if (unitPrice == null || unitPrice <= 0) {
          missing.add(itemId);
          accumulated
              .putIfAbsent(
                itemId,
                () => _MarketContributionAccumulator(
                  itemId: itemId,
                  name: itemType.item.name,
                  icon: _itemIcon(itemId),
                ),
              )
              .addMissing(amount: item.totalPerHour);
          continue;
        }
        final vendor = vendorUnitPrice != null;
        final itemTaxed = settings.dropTaxed[itemType.id] ?? settings.showTaxed;
        final baseMultiplier = vendor
            ? 1.0
            : itemTaxed
            ? settings.marketNetRate
            : 1.0;
        final bonusMultiplier = vendor
            ? 1.0
            : settings.showTaxed
            ? settings.marketNetRate
            : 1.0;
        final bonusPerHour = math.max(
          0.0,
          item.totalPerHour - item.basePerHour,
        );
        final grossValue = item.totalPerHour * unitPrice;
        final netValue =
            item.basePerHour * unitPrice * baseMultiplier +
            bonusPerHour * unitPrice * bonusMultiplier;
        accumulated
            .putIfAbsent(
              itemId,
              () => _MarketContributionAccumulator(
                itemId: itemId,
                name: itemType.item.name,
                icon: _itemIcon(itemId),
              ),
            )
            .add(
              amount: item.totalPerHour,
              grossValue: grossValue,
              netValue: netValue,
              vendorPrice: vendor,
              source: customPrice != null
                  ? _MarketPriceSource.custom
                  : vendor
                  ? _MarketPriceSource.vendor
                  : _MarketPriceSource.market,
              showOnCard: true,
            );
      }
      final data = widget.bairogCalculatorData!;
      final expectedBonusByType = <int, double>{};
      void addExpectedBonus(int itemTypeId, double amount) {
        if (amount <= 0) return;
        expectedBonusByType.update(
          itemTypeId,
          (current) => current + amount,
          ifAbsent: () => amount,
        );
      }

      final ratios = projection.route.typeRatios.isEmpty
          ? <BairogGatheringTypeRatio>[
              BairogGatheringTypeRatio(
                gatheringTypeId: projection.route.gatheringTypeId,
                ratio: 1,
              ),
            ]
          : projection.route.typeRatios;
      final gathers = projection.effectiveGathersPerHour;
      if (settings.includeAfuaru) {
        final nonMinigameGathers =
            gathers * (1 - settings.minigameMode.procChance);
        for (final ratio in ratios) {
          final type = data.gatheringTypesById[ratio.gatheringTypeId];
          if (type == null ||
              !type.hasAfuaru ||
              type.afuaruSpawnRate == null ||
              type.name.toLowerCase().contains('sap')) {
            continue;
          }
          for (final entry in type.afuaruItemAverages.entries) {
            addExpectedBonus(
              entry.key,
              nonMinigameGathers *
                  ratio.ratio *
                  type.afuaruSpawnRate! *
                  entry.value,
            );
          }
        }
      }
      if (settings.includeChest || settings.includeChestX10) {
        final mastery = bairogBonusesForMastery(settings.mastery);
        final rareRateFactor =
            1 +
            mastery.rareRatePercent / 100 +
            settings.gatheringDropRatePercent / 100;
        final rareAmount = 1 + mastery.rareAmountPercent / 100;
        final rareAmountFloor = rareAmount.floor();
        final rareAmountFraction = rareAmount - rareAmountFloor;
        final rareAmountFactor =
            rareAmountFloor * (1 - rareAmountFraction) +
            (rareAmountFloor + 1) * rareAmountFraction;
        for (final ratio in ratios) {
          final type = data.gatheringTypesById[ratio.gatheringTypeId];
          if (type?.chestSpawnRate == null || type!.chestItemAverages.isEmpty) {
            continue;
          }
          final baseEvents =
              gathers * ratio.ratio * type.chestSpawnRate! * rareRateFactor;
          for (final isX10 in <bool>[false, true]) {
            final enabled = isX10
                ? settings.includeChestX10
                : settings.includeChest;
            final eventFactor = isX10
                ? 10 * settings.minigameMode.procChance
                : 1 - settings.minigameMode.procChance;
            if (!enabled || eventFactor <= 0) continue;
            final resultFactor = rareAmountFactor * eventFactor;
            for (final entry in type.chestItemAverages.entries) {
              addExpectedBonus(
                entry.key,
                baseEvents * entry.value * resultFactor,
              );
            }
          }
        }
      }
      if (settings.includeFeverTime) {
        for (final ratio in ratios) {
          final type = data.gatheringTypesById[ratio.gatheringTypeId];
          if (type?.feverTimeSpawnRate == null ||
              type!.feverTimeItemAverages.isEmpty) {
            continue;
          }
          for (final entry in type.feverTimeItemAverages.entries) {
            addExpectedBonus(
              entry.key,
              gathers * ratio.ratio * type.feverTimeSpawnRate! * entry.value,
            );
          }
        }
      }
      final projectedBonusByType = <int, double>{
        for (final item in projection.items)
          item.itemType.id:
              item.afuaruPerHour +
              item.chestPerHour +
              item.chestX10PerHour +
              item.feverTimePerHour,
      };
      for (final entry in expectedBonusByType.entries) {
        final supplementalAmount =
            entry.value - (projectedBonusByType[entry.key] ?? 0);
        if (supplementalAmount <= .000001) continue;
        final itemType = data.gatheringItemTypesById[entry.key];
        if (itemType == null ||
            settings.hiddenDropItemTypeIds.contains(itemType.id) ||
            (!settings.includeEvergreenShard &&
                itemType.item.id == bairogEvergreenShardItemId)) {
          continue;
        }
        final itemId = itemType.item.id.toString();
        final quote = _marketQuotes[itemId];
        final customPrice = settings.customItemPrices[itemType.id];
        final vendorUnitPrice = itemType.vendorUnitPrice;
        final unitPrice = customPrice ?? vendorUnitPrice ?? quote?.price;
        if (unitPrice == null || unitPrice <= 0) {
          missing.add(itemId);
          accumulated
              .putIfAbsent(
                itemId,
                () => _MarketContributionAccumulator(
                  itemId: itemId,
                  name: itemType.item.name,
                  icon: _itemIcon(itemId),
                ),
              )
              .addMissing(amount: supplementalAmount);
          continue;
        }
        final vendor = vendorUnitPrice != null;
        final netMultiplier = vendor
            ? 1.0
            : settings.showTaxed
            ? settings.marketNetRate
            : 1.0;
        accumulated
            .putIfAbsent(
              itemId,
              () => _MarketContributionAccumulator(
                itemId: itemId,
                name: itemType.item.name,
                icon: _itemIcon(itemId),
              ),
            )
            .add(
              amount: supplementalAmount,
              grossValue: supplementalAmount * unitPrice,
              netValue: supplementalAmount * unitPrice * netMultiplier,
              vendorPrice: vendor,
              source: customPrice != null
                  ? _MarketPriceSource.custom
                  : vendor
                  ? _MarketPriceSource.vendor
                  : _MarketPriceSource.market,
              showOnCard: false,
            );
      }
      for (final accumulatedItem in accumulated.values) {
        final quote = _marketQuotes[accumulatedItem.itemId];
        final vendor = accumulatedItem.allVendorPrices;
        contributions.add(
          _MarketContribution(
            itemId: accumulatedItem.itemId,
            name: accumulatedItem.name,
            icon: accumulatedItem.icon,
            perHour: accumulatedItem.perHour,
            unitPrice: accumulatedItem.missingPrice
                ? null
                : accumulatedItem.grossValuePerHour / accumulatedItem.perHour,
            grossValuePerHour: accumulatedItem.grossValuePerHour,
            netValuePerHour: accumulatedItem.netValuePerHour,
            stock: vendor ? null : quote?.stock,
            preorders: vendor
                ? null
                : _freshPreorderCount(accumulatedItem.itemId, quote),
            vendorPrice: vendor,
            priceSource: accumulatedItem.priceSource,
            fetchedAt: vendor ? null : quote?.fetchedAt,
            detailsOnly:
                accumulatedItem.missingPrice || !accumulatedItem.visibleOnCard,
          ),
        );
      }
    }
    contributions.sort(
      (a, b) => b.netValuePerHour.compareTo(a.netValuePerHour),
    );
    final costLines = <_MarketCostLine>[];
    final missingCostItemIds = <String>{};
    if (projection != null) {
      for (final expense in bairogEnergyExpenses) {
        if (!benchmark.settings.enabledExpenseItemIds.contains(
          expense.bdoItemId,
        )) {
          continue;
        }
        final itemId = expense.bdoItemId.toString();
        final quotePrice = _marketQuotes[itemId]?.price;
        final unitPrice = quotePrice != null && quotePrice > 0
            ? quotePrice.toDouble()
            : null;
        final quantityPerHour =
            expense.usesPerHour ?? 1 / expense.durationHours!;
        if (unitPrice == null) missingCostItemIds.add(itemId);
        costLines.add(
          _MarketCostLine(
            itemId: itemId,
            name: expense.name,
            icon: 'assets/icons/buffs/$itemId.webp',
            quantityPerHour: quantityPerHour,
            unitPrice: unitPrice,
            valuePerHour: unitPrice == null ? 0 : quantityPerHour * unitPrice,
          ),
        );
      }
    }
    final keyCount = projection == null
        ? 0.0
        : projection.chestsPerHour + projection.chestX10PerHour;
    final keyPrice = _marketQuotes['44164']?.price;
    final missingGoldKeyPrice =
        keyCount > 0 && (keyPrice == null || keyPrice <= 0);
    if (missingGoldKeyPrice) missingCostItemIds.add('44164');
    final goldKeyExpenses = keyCount > 0 && keyPrice != null && keyPrice > 0
        ? keyCount * keyPrice
        : 0.0;
    if (keyCount > 0) {
      costLines.add(
        _MarketCostLine(
          itemId: '44164',
          name: 'Gold Key',
          icon: 'assets/icons/items/44164.webp',
          quantityPerHour: keyCount,
          unitPrice: keyPrice != null && keyPrice > 0
              ? keyPrice.toDouble()
              : null,
          valuePerHour: goldKeyExpenses,
        ),
      );
    }
    final summary = _MarketSummary(
      contributions: List.unmodifiable(contributions),
      missingItemIds: Set.unmodifiable(missing),
      compactCardItemIds: _compactCardItemIdsForBenchmark(benchmark),
      costLines: List.unmodifiable(costLines),
      missingCostItemIds: Set.unmodifiable(missingCostItemIds),
      hourlyExpenses: projection?.energy.hourlyExpenseSilver ?? 0,
      goldKeyExpenses: goldKeyExpenses,
      calculatedTotal: projection?.netSilverPerHour,
      missingGoldKeyPrice: missingGoldKeyPrice,
    );
    assert(
      projection == null ||
          (summary.afterTaxIncome -
                      summary.hourlyExpenses -
                      summary.goldKeyExpenses -
                      summary.total)
                  .abs() <
              .01,
      'Market calculation details must reconcile with the Bairog total.',
    );
    return summary;
  }

  _MarketSummary _marketSummaryForPerformance(SpotPerformance performance) {
    final contributions = <_MarketContribution>[];
    final missing = <String>{};
    for (final entry in performance.itemTotals.entries) {
      if (entry.value <= 0) continue;
      final perHour = performance.itemsPerHour(entry.key);
      final quote = _marketQuotes[entry.key];
      final vendorPrice = entry.key == '5651' ? 10000 : null;
      final unitPrice = vendorPrice ?? quote?.price;
      if (unitPrice == null || unitPrice <= 0) {
        missing.add(entry.key);
        contributions.add(
          _MarketContribution(
            itemId: entry.key,
            name: _itemName(entry.key),
            icon: _itemIcon(entry.key),
            perHour: perHour,
            unitPrice: null,
            grossValuePerHour: 0,
            netValuePerHour: 0,
            stock: quote?.stock,
            preorders: _freshPreorderCount(entry.key, quote),
            vendorPrice: false,
            priceSource: _MarketPriceSource.market,
            fetchedAt: quote?.fetchedAt,
            detailsOnly: true,
          ),
        );
        continue;
      }
      final vendor = vendorPrice != null;
      final grossValue = perHour * unitPrice;
      contributions.add(
        _MarketContribution(
          itemId: entry.key,
          name: _itemName(entry.key),
          icon: _itemIcon(entry.key),
          perHour: perHour,
          unitPrice: unitPrice.toDouble(),
          grossValuePerHour: grossValue,
          netValuePerHour:
              grossValue * (vendor ? 1 : centralMarketAfterTaxRate),
          stock: vendor ? null : quote?.stock,
          preorders: vendor ? null : _freshPreorderCount(entry.key, quote),
          vendorPrice: vendor,
          priceSource: vendor
              ? _MarketPriceSource.vendor
              : _MarketPriceSource.market,
          fetchedAt: vendor ? null : quote?.fetchedAt,
        ),
      );
    }
    contributions.sort(
      (a, b) => b.netValuePerHour.compareTo(a.netValuePerHour),
    );
    return _MarketSummary(
      contributions: List.unmodifiable(contributions),
      missingItemIds: Set.unmodifiable(missing),
      compactCardItemIds: _compactCardItemIdsForPerformance(performance),
    );
  }

  String _itemName(String itemId) {
    final catalogItem = widget.catalog.items
        .where((entry) => entry.id == itemId)
        .firstOrNull;
    if (catalogItem != null && catalogItem.name.isNotEmpty) {
      return catalogItem.name;
    }
    for (final session in widget.sessions) {
      final loot = session.loot
          .where((entry) => entry.id == itemId)
          .firstOrNull;
      if (loot != null && loot.name.isNotEmpty) return loot.name;
    }
    return itemId;
  }

  String _itemIcon(String itemId) {
    final catalogItem = widget.catalog.items
        .where((entry) => entry.id == itemId)
        .firstOrNull;
    if (catalogItem != null && catalogItem.icon.isNotEmpty) {
      return catalogItem.icon;
    }
    for (final session in widget.sessions) {
      final loot = session.loot
          .where((entry) => entry.id == itemId)
          .firstOrNull;
      if (loot != null && loot.icon.isNotEmpty) return loot.icon;
    }
    return _legacyItemIconAliases[itemId] ?? 'assets/icons/items/$itemId.webp';
  }

  void _select(Spot spot, {String? methodId, _BairogRouteView? benchmark}) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_listScroll.hasClients) _listReturnOffset = _listScroll.offset;
    if (_stripScroll.hasClients) _stripReturnOffset = _stripScroll.offset;
    setState(() {
      _selected = spot;
      _selectedBenchmark = benchmark;
      if (methodId != null) {
        _detailMethodId = methodId;
      } else if (_ranking == _SpotRanking.sharp ||
          _ranking == _SpotRanking.dust ||
          _ranking == _SpotRanking.caphras ||
          _isNostosRanking ||
          _ranking == _SpotRanking.profit ||
          _ranking == _SpotRanking.demand) {
        _detailMethodId = _rankingSource == _RankingSource.personal
            ? _bestPerformance(spot)?.methodId
            : _bestBairogBenchmark(spot)?.methodId;
        _selectedBenchmark = _rankingSource == _RankingSource.bairog
            ? _bestBairogBenchmark(spot)
            : null;
      }
    });
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
  }

  void _chooseAnotherSpot() {
    setState(() => _selected = null);
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selected != null) return;
      for (final (controller, offset) in [
        (_listScroll, _listReturnOffset),
        (_stripScroll, _stripReturnOffset),
      ]) {
        if (controller.hasClients) {
          controller.jumpTo(
            offset.clamp(0, controller.position.maxScrollExtent),
          );
        }
      }
    });
  }

  void _selectEntry(_SpotListEntry entry) {
    final spot = entry.spot;
    if (spot != null) {
      _select(
        spot,
        methodId: entry.benchmark?.methodId ?? entry.performance?.methodId,
        benchmark: entry.benchmark,
      );
      return;
    }
    final benchmark = entry.benchmark;
    if (benchmark != null) _showBairogRouteDetails(benchmark);
  }

  String get _goalIconPath {
    final nostos = _nostosMaterial;
    if (nostos != null) return nostos.iconAssetPath;
    return switch (_ranking) {
      _SpotRanking.sharp => 'assets/icons/items/4998.webp',
      _SpotRanking.dust => 'assets/icons/items/721002.webp',
      _SpotRanking.caphras => 'assets/icons/items/721003.webp',
      _SpotRanking.profit => 'assets/icons/items/1.webp',
      _SpotRanking.demand || _SpotRanking.browse => '',
      _ => '',
    };
  }

  double _cardMainExtent(double textScale) {
    final extra = math.max(0, textScale - 1);
    return (switch (_cardMode) {
      _SpotCardMode.browse => 70 + 36 * extra,
      _SpotCardMode.yield => 98 + 44 * extra,
      _SpotCardMode.value => 132 + 68 * extra,
      _SpotCardMode.demand => 132 + 68 * extra,
    }).toDouble();
  }

  Future<void> _showBairogRouteDetails(_BairogRouteView route) {
    final method = widget.catalog.methods.firstWhere(
      (entry) => entry.id == route.methodId,
    );
    final sourceEvidence =
        'At ${route.gathersPerHour} gathers/h · $_setupCompactLabel';
    final routeMetric = switch (_cardMode) {
      _SpotCardMode.value => _valueCardMetric(
        _marketSummaryForBenchmark(route),
        sourceEvidence,
        null,
      ),
      _SpotCardMode.demand => _demandRouteMetric(
        route,
        _marketSummaryForBenchmark(route),
        sourceEvidence,
      ),
      _SpotCardMode.yield => Row(
        children: [
          GameIcon(_goalIconPath, size: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _benchmarkMetricText(route),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
      _SpotCardMode.browse => const SizedBox.shrink(),
    };
    final media = SpotMedia(<String, dynamic>{
      'type': 'video',
      'title': '${route.sourceRouteName} gathering guide',
      'url': route.videoUrl,
      'sourceUrl': route.videoUrl,
      'author': bairogBenchmarkSet.creator,
      'publishedDate': route.sourceUpdatedOn,
      'methodIds': <String>[route.methodId],
    });
    final matchedSpot = widget.catalog.spots
        .where((spot) => spot.id == route.spotId)
        .firstOrNull;
    final references = <SpotMedia>[
      media,
      if (matchedSpot != null)
        ...matchedSpot.media.where(
          (entry) => entry.matchesMethod(route.methodId),
        ),
    ];
    // This is a different region, not another source for Seoul's measured route.
    final relatedEdania = route.sourceRouteId == 46 && route.spotId == null
        ? widget.catalog.spots
              .where((spot) => spot.id == 'edania-thuja-bunnygirl')
              .firstOrNull
        : null;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            _methodArtwork(method.icon, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                route.sourceRouteName,
                style: const TextStyle(fontSize: 19),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'At ${route.gathersPerHour} gathers/h',
                key: ValueKey('bairog-route-evidence-${route.sourceRouteId}'),
                style: const TextStyle(
                  fontSize: 13,
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                route.projection == null
                    ? 'Captured baseline · '
                          '${bairogBenchmarkSet.conditions.compactLabel}'
                    : 'Estimated for your setup · $_setupAccessibleLabel',
                style: const TextStyle(
                  fontSize: 13,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (route.projection case final projection?) ...[
                const SizedBox(height: 4),
                Text(
                  _energyEvidence(projection.energy),
                  style: const TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
              const SizedBox(height: 10),
              routeMetric,
              const SizedBox(height: 12),
              SpotMediaGallery(
                key: ValueKey('bairog-route-media-${route.sourceRouteId}'),
                media: references,
                height: 390,
              ),
            ],
          ),
        ),
        actions: [
          if (relatedEdania != null)
            TextButton(
              key: const ValueKey('open-related-edania-thuja-guides'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _select(relatedEdania, methodId: route.methodId);
              },
              child: const Text('Edania Thuja guides'),
            ),
          TextButton(
            onPressed: _openBairogCalculator,
            child: const Text('BDO Workshop'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BackdropGroup(
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (_selected case final spot?) {
          return SingleChildScrollView(
            key: const ValueKey('spot-guide-scroll'),
            controller: _detailScroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: _detail(spot),
          );
        }
        final entries = _visibleEntries;
        final compact = constraints.maxWidth < 900;
        const sidebarWidth = 376.0;
        final textScale = math.max(
          1.0,
          MediaQuery.textScalerOf(context).scale(15) / 15,
        );
        final cardExtent = _cardMainExtent(textScale);
        final compactListHeight = math.min(
          cardExtent * 2 + 16,
          math.max(cardExtent + 8, constraints.maxHeight * .36),
        );
        final compactFilterHeight =
            (constraints.maxHeight - compactListHeight - 170).clamp(
              96.0,
              312.0,
            );
        final mapHeight = (constraints.maxHeight - compactListHeight - 112)
            .clamp(260.0, 1600.0);
        final detail = SingleChildScrollView(
          key: const ValueKey('spot-guide-scroll'),
          controller: _detailScroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_map(mapHeight)],
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: _searchBar(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _compactFilterControl(),
              ),
              AnimatedSize(
                duration: _filterAnimationDuration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _filterRailExpanded
                    ? SizedBox(
                        height: compactFilterHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: _floatingFilterPalette(),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(
                height: compactListHeight,
                child: entries.isEmpty
                    ? _emptyResults()
                    : ListView.builder(
                        key: const ValueKey('spot-strip'),
                        controller: _stripScroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        itemCount: entries.length,
                        itemBuilder: (context, index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index + 1 == entries.length ? 0 : 8,
                          ),
                          child: _spotCard(entries[index]),
                        ),
                      ),
              ),
              Expanded(child: detail),
            ],
          );
        }
        const sidebarLeft = 16.0;
        const dividerLeft = sidebarLeft + sidebarWidth + 12;
        const paletteLeft = dividerLeft + 18;
        const paletteWidth = 286.0;
        return Stack(
          key: const ValueKey('spot-guide-layered-layout'),
          fit: StackFit.expand,
          children: [
            _map(constraints.maxHeight),
            Positioned(
              left: sidebarLeft,
              top: 16,
              bottom: 16,
              width: sidebarWidth,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  key: const ValueKey('spot-journal-surface'),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _searchBar(),
                      ),
                      Flexible(
                        child: entries.isEmpty
                            ? _emptyResults()
                            : ListView.builder(
                                key: const ValueKey('spot-list'),
                                controller: _listScroll,
                                hitTestBehavior: HitTestBehavior.deferToChild,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: entries.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index + 1 == entries.length ? 0 : 6,
                                  ),
                                  child: _spotCard(entries[index]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: dividerLeft,
              top: 0,
              bottom: 0,
              width: 1,
              child: DecoratedBox(
                key: const ValueKey('spot-filter-divider'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      context.glass.strongLine,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: dividerLeft - 13,
              top: 0,
              bottom: 0,
              width: 27,
              child: Align(child: _filterRailControl()),
            ),
            Positioned(
              left: paletteLeft,
              top: 16,
              bottom: 16,
              width: paletteWidth,
              child: IgnorePointer(
                ignoring: !_filterRailExpanded,
                child: AnimatedSlide(
                  duration: _filterAnimationDuration,
                  curve: Curves.easeOutCubic,
                  offset: _filterRailExpanded
                      ? Offset.zero
                      : const Offset(-.08, 0),
                  child: AnimatedOpacity(
                    key: const ValueKey('spot-filter-overlay'),
                    duration: _filterAnimationDuration,
                    curve: Curves.easeOutCubic,
                    opacity: _filterRailExpanded ? 1 : 0,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _floatingFilterPalette(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Duration get _filterAnimationDuration =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 240);

  Widget _searchBar() => Row(
    children: [
      Expanded(
        child: _mapContentBox(
          TextField(
            key: const ValueKey('spot-search'),
            controller: _search,
            style: const TextStyle(fontSize: 15),
            onChanged: (_) => _filterChanged(),
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              hintStyle: const TextStyle(fontSize: 15),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : Semantics(
                      label: 'Clear search',
                      button: true,
                      child: IconButton(
                        key: const ValueKey('spot-clear-search'),
                        onPressed: () {
                          _search.clear();
                          _filterChanged();
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      _mapContentBox(_methodFilter(), radius: 9),
      if (_usesMarket)
        Semantics(
          label: _ranking == _SpotRanking.demand
              ? 'Refresh current EU Marketplace prices, listings, and preorders'
              : 'Refresh current EU Marketplace prices, listings, and '
                    'out-of-stock preorders',
          button: true,
          child: _mapContentBox(
            GlassControl(
              child: IconButton(
                key: const ValueKey('spot-market-refresh'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                onPressed: _marketLoading
                    ? null
                    : () => _loadMarketQuotes(force: true),
                icon: _marketLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 19),
              ),
            ),
          ),
        ),
      if (_isGoalRanking)
        Semantics(
          label: 'Bairog source details',
          button: true,
          child: _mapContentBox(
            GlassControl(
              child: IconButton(
                key: const ValueKey('bairog-benchmark-details'),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                onPressed: _showBairogBenchmarkDetails,
                icon: const Icon(Icons.info_outline, size: 19),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _methodArtwork(String path, {required double size}) =>
      GlassArtworkWell(
        tool: true,
        child: GameIcon(path, size: size, backgroundColor: Colors.transparent),
      );

  double get _toolMenuWidth {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
    var labelWidth = 0.0;
    for (final label in [
      'All tools',
      ...widget.catalog.methods.map((method) => method.label),
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      labelWidth = math.max(labelWidth, painter.width);
      painter.dispose();
    }
    return (labelWidth + 84).clamp(
      224.0,
      math.max(224.0, MediaQuery.sizeOf(context).width - 48),
    );
  }

  Widget _methodFilter() => TooltipVisibility(
    visible: false,
    child: Semantics(
      label: _method == 'all'
          ? 'Choose gathering tool'
          : widget.catalog.methods
                .firstWhere((method) => method.id == _method)
                .label,
      button: true,
      child: MenuAnchor(
        useRootOverlay: true,
        alignmentOffset: const Offset(0, 4),
        style: _menuPanelStyle(_toolMenuWidth),
        menuChildren: [
          MenuItemButton(
            style: _menuItemStyle(_toolMenuWidth),
            onPressed: () => _selectMethod('all'),
            child: Row(
              children: [
                _allToolsIcon(size: 30),
                const SizedBox(width: 10),
                const Text('All tools', style: TextStyle(fontSize: 15)),
              ],
            ),
          ),
          Divider(height: 6, color: context.glass.line),
          ...widget.catalog.methods.map(
            (method) => MenuItemButton(
              style: _menuItemStyle(_toolMenuWidth),
              onPressed: () => _selectMethod(method.id),
              child: Row(
                children: [
                  _methodArtwork(method.icon, size: 31),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      method.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        builder: (context, controller, child) => GlassControl(
          key: const ValueKey('spot-method-filter'),
          radius: 9,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: SizedBox.square(
              dimension: 40,
              child: Center(
                child: _method == 'all'
                    ? _allToolsIcon(size: 28)
                    : _methodArtwork(
                        widget.catalog.methods
                            .firstWhere((method) => method.id == _method)
                            .icon,
                        size: 27,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _selectMethod(String method) {
    _method = method;
    _detailMethodId = null;
    _filterChanged();
  }

  Widget _allToolsIcon({required double size}) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: GameIcon(
            'assets/icons/tools/fluid_collector.webp',
            size: size * .72,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GameIcon(
            'assets/icons/tools/lumbering_axe.webp',
            size: size * .72,
          ),
        ),
      ],
    ),
  );

  MenuStyle _menuPanelStyle(double width) => MenuStyle(
    alignment: AlignmentDirectional.bottomStart,
    backgroundColor: WidgetStatePropertyAll(context.glass.popup),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(10),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
    minimumSize: WidgetStatePropertyAll(Size(width, 0)),
    maximumSize: WidgetStatePropertyAll(Size(width, 420)),
    side: WidgetStatePropertyAll(BorderSide(color: context.glass.line)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  ButtonStyle _menuItemStyle(double width) => MenuItemButton.styleFrom(
    minimumSize: Size(width, 48),
    maximumSize: Size(width, double.infinity),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    foregroundColor: ink,
    alignment: Alignment.centerLeft,
  );

  static const _dropRankings = <_SpotRanking>[
    _SpotRanking.browse,
    _SpotRanking.sharp,
    _SpotRanking.dust,
    _SpotRanking.caphras,
  ];

  static const _marketRankings = <_SpotRanking>[
    _SpotRanking.profit,
    _SpotRanking.demand,
  ];

  static const _nostosRankings = <_SpotRanking>[
    _SpotRanking.nostosCrackedTerrashard,
    _SpotRanking.nostosWitheredWoodChip,
    _SpotRanking.nostosThinEssenceOfLife,
    _SpotRanking.nostosDimHeartveinShard,
    _SpotRanking.nostosFaintWildsoul,
    _SpotRanking.nostosFadedNaturewovenHide,
  ];

  Widget _filterRailControl() => Tooltip(
    message: _filterRailExpanded ? 'Hide filters' : 'Show filters',
    child: Semantics(
      button: true,
      expanded: _filterRailExpanded,
      label: _filterRailExpanded ? 'Hide filters' : 'Show filters',
      child: GlassControl(
        key: const ValueKey('spot-filter-rail-control'),
        radius: 8,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              setState(() => _filterRailExpanded = !_filterRailExpanded),
          child: AnimatedContainer(
            duration: _filterAnimationDuration,
            curve: Curves.easeOutCubic,
            width: 27,
            height: _filterRailExpanded ? 44 : 106,
            child: Center(
              child: _filterRailExpanded
                  ? const Icon(
                      Icons.chevron_left_rounded,
                      key: ValueKey('spot-filter-hide-arrow'),
                      size: 23,
                      color: ink,
                    )
                  : const Text(
                      'F\nI\nL\nT\nE\nR',
                      key: ValueKey('spot-filter-vertical-label'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.22,
                        color: ink,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _compactFilterControl() => GlassControl(
    key: const ValueKey('spot-filter-compact-control'),
    radius: 9,
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _filterRailExpanded = !_filterRailExpanded),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              const Text(
                'FILTER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: muted,
                ),
              ),
              const SizedBox(width: 10),
              if (_rankingIconPath(_ranking) case final icon?) ...[
                GameIcon(icon, size: 24),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  _rankingLabel(_ranking),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                _filterRailExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _floatingFilterPalette() => Padding(
    key: const ValueKey('spot-filter-journal-surface'),
    padding: const EdgeInsets.all(10),
    child: SingleChildScrollView(
      key: const ValueKey('spot-ranking-palette'),
      hitTestBehavior: HitTestBehavior.deferToChild,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filterGroup('DROPS', _dropRankings),
          const SizedBox(height: 14),
          _filterGroup('MARKETPLACE', _marketRankings),
          if (_ranking == _SpotRanking.demand) ...[
            const SizedBox(height: 9),
            _demandSortControl(),
          ],
          const SizedBox(height: 14),
          _filterGroup('STAR OF NOSTOS', _nostosRankings),
        ],
      ),
    ),
  );

  Widget _filterGroup(String label, List<_SpotRanking> rankings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _filterGroupHeader(label),
      const SizedBox(height: 6),
      LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 7.0;
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns =
              rankings == _nostosRankings || constraints.maxWidth < 240 * scale
              ? 1
              : 2;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final ranking in rankings)
                SizedBox(
                  width: width,
                  child: _mapContentBox(
                    _rankingPaletteButton(ranking),
                    radius: 9,
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _filterGroupHeader(String label) => _mapContentBox(
    DecoratedBox(
      decoration: BoxDecoration(
        color: context.glass.row,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: muted,
            fontSize: 11.5,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    ),
    radius: 4,
  );

  // Blur only the content boxes, not the empty journal/filter footprints.
  // Grouping these non-overlapping clips shares the map sampling work.
  Widget _mapContentBox(Widget child, {double radius = 10}) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter.grouped(
      filter: ImageFilter.blur(sigmaX: glassBlurSigma, sigmaY: glassBlurSigma),
      child: child,
    ),
  );

  Widget _demandSortControl() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: _filterGroupHeader('SORT DEMAND BY'),
      ),
      const SizedBox(height: 5),
      Row(
        children: [
          Expanded(
            child: _mapContentBox(
              _demandSortButton(
                sort: _DemandSort.preorders,
                label: 'Preorders',
                semanticLabel:
                    'Sort Demand spots by preorder count and scarcity',
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _mapContentBox(
              _demandSortButton(
                sort: _DemandSort.value,
                label: 'Value',
                semanticLabel:
                    'Keep spots with preorders first, then sort each group by total value per hour',
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _demandSortButton({
    required _DemandSort sort,
    required String label,
    required String semanticLabel,
  }) {
    final selected = _demandSort == sort;
    return Semantics(
      label: semanticLabel,
      button: true,
      selected: selected,
      child: GlassControl(
        key: ValueKey('spot-demand-sort-${sort.name}'),
        selected: selected,
        radius: 8,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _setDemandSort(sort),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: 12.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankingPaletteButton(_SpotRanking ranking) {
    final iconPath = _rankingIconPath(ranking);
    final selected = ranking == _ranking;
    final loading = selected && _usesMarket && _marketLoading;
    return Semantics(
      label: _rankingSemanticLabel(ranking),
      button: true,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: GlassControl(
          key: ValueKey('spot-ranking-${_rankingKeySuffix(ranking)}'),
          selected: selected,
          radius: 9,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => _setRanking(ranking),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 31,
                    child: Center(
                      child: loading
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : iconPath == null
                          ? const Icon(Icons.grid_view_rounded, size: 25)
                          : GameIcon(iconPath, size: 30),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _rankingLabel(ranking),
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _rankingLabel(_SpotRanking ranking) => switch (ranking) {
    _SpotRanking.browse => 'All spots',
    _SpotRanking.sharp => 'Sharp',
    _SpotRanking.dust => 'Dust',
    _SpotRanking.caphras => 'Caphras',
    _SpotRanking.profit => 'Value',
    _SpotRanking.demand => 'Demand',
    _ => _nostosForRanking(ranking)!.name,
  };

  String _rankingKeySuffix(_SpotRanking ranking) {
    final nostos = _nostosForRanking(ranking);
    return nostos == null ? ranking.name : 'nostos-${nostos.itemId}';
  }

  String? _rankingIconPath(_SpotRanking ranking) => switch (ranking) {
    _SpotRanking.browse => null,
    _SpotRanking.sharp => 'assets/icons/items/4998.webp',
    _SpotRanking.dust => 'assets/icons/items/721002.webp',
    _SpotRanking.caphras => 'assets/icons/items/721003.webp',
    _SpotRanking.profit || _SpotRanking.demand => 'assets/icons/items/1.webp',
    _ => _nostosForRanking(ranking)?.iconAssetPath,
  };

  String _rankingSemanticLabel(_SpotRanking ranking) => switch (ranking) {
    _SpotRanking.browse => 'Show all gathering spots',
    _SpotRanking.sharp => 'Compare Sharp Black Crystal Shards per hour',
    _SpotRanking.dust => 'Rank Ancient Spirit Dust per hour',
    _SpotRanking.caphras => 'Compare direct Caphras Stones per hour',
    _SpotRanking.profit => 'Compare current after-tax value per hour',
    _SpotRanking.demand =>
      'Compare current marketplace preorders, availability, and value',
    _ => '${_rankingLabel(ranking)} per hour from Bairog routes',
  };

  BairogNostosMaterial? _nostosForRanking(_SpotRanking ranking) =>
      switch (ranking) {
        _SpotRanking.nostosCrackedTerrashard => bairogNostosMaterials[0],
        _SpotRanking.nostosWitheredWoodChip => bairogNostosMaterials[1],
        _SpotRanking.nostosThinEssenceOfLife => bairogNostosMaterials[2],
        _SpotRanking.nostosDimHeartveinShard => bairogNostosMaterials[3],
        _SpotRanking.nostosFaintWildsoul => bairogNostosMaterials[4],
        _SpotRanking.nostosFadedNaturewovenHide => bairogNostosMaterials[5],
        _ => null,
      };

  Future<void> _openBairogCalculator() async {
    try {
      await NativeBridge.openExternal(bairogBenchmarkSet.calculatorUrl);
    } catch (_) {
      // External navigation is optional; the embedded source facts remain usable.
    }
  }

  Future<void> _showBairogBenchmarkDetails() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Bairog calculator & source'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_bairogRoutes.length} public routes · '
              'estimated for your setup',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_setupAccessibleLabel · '
              '${_minigameLabel(widget.bairogSettings.minigameMode)} · '
              '${_hedgehogLabel(widget.bairogSettings.hedgehogTier)}',
              style: const TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 8),
            Text(
              'Gathering Item Drop Rate (GDR) is your final total chance bonus. '
              'Yields use the same public BDO Workshop mastery, drop, minigame, '
              'pet, proc, Agris, energy, tax, and route-speed model. Route speed, '
              'sessions, hours, videos, and locations remain Bairog Haan source '
              'evidence.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '${_bairogRoutes.where((route) => route.isMapped).length} routes '
              'have verified map coordinates; '
              '${_bairogRoutes.where((route) => !route.isMapped).length} '
              'source-only routes open their Bairog guide after selection. '
              'Calculator data captured ${_calculatorCaptureDate()}.',
              style: const TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _openBairogCalculator,
          child: const Text('BDO Workshop'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _emptyResults() {
    final message = switch (_ranking) {
      _SpotRanking.browse => 'No matching spots',
      _SpotRanking.profit when _marketLoading => 'Checking market prices…',
      _SpotRanking.profit when _marketError != null => _marketError!,
      _SpotRanking.demand when _marketLoading => 'Checking market demand…',
      _SpotRanking.demand when _marketError != null => _marketError!,
      _ when _isGoalRanking && _rankingSource == _RankingSource.bairog =>
        'No Bairog route matches these filters',
      _ => 'Save a session here to rank your results',
    };
    return _mapContentBox(
      DecoratedBox(
        decoration: BoxDecoration(
          color: context.glass.row,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: const TextStyle(fontSize: 15, color: muted),
          ),
        ),
      ),
    );
  }

  Widget _spotCard(_SpotListEntry entry) {
    final spot = entry.spot;
    final performance = entry.performance;
    final benchmark = entry.benchmark;
    final methodId = performance?.methodId ?? benchmark?.methodId;
    final method = methodId == null
        ? null
        : widget.catalog.methods
              .where((entry) => entry.id == methodId)
              .firstOrNull;
    final selected =
        spot?.id == _selected?.id &&
        (methodId == null || methodId == _detailMethodId);
    final title = benchmark?.sourceRouteName ?? spot!.displayName;
    final cardKey = benchmark == null
        ? ValueKey('spot-card-${spot!.id}')
        : ValueKey('spot-route-${benchmark.sourceRouteId}');
    final metric = performance != null
        ? _metricText(performance)
        : benchmark != null
        ? _benchmarkMetricText(benchmark)
        : null;
    final marketSummary = benchmark != null
        ? _marketSummaryForBenchmark(benchmark)
        : performance != null
        ? _marketSummaryForPerformance(performance)
        : null;
    final evidence = performance != null
        ? 'Your ${performance.sessionCount} saved '
              '${performance.sessionCount == 1 ? 'session' : 'sessions'} · '
              '${_hoursText(performance.hours)}'
        : benchmark != null
        ? 'At ${benchmark.gathersPerHour} gathers/h · $_setupCompactLabel'
        : spot!.nodeName;
    return _mapContentBox(
      GlassControl(
        key: cardKey,
        selected: selected,
        radius: 10,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectEntry(entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: _cardMode == _SpotCardMode.browse
                ? _browseCardContent(
                    icon: spot!.icon,
                    title: title,
                    location: evidence,
                  )
                : _cardMode == _SpotCardMode.value
                ? _valueGoalCardContent(
                    icon: _primaryCardIcon(entry),
                    title: title,
                    method: method,
                    benchmark: benchmark,
                    summary: marketSummary!,
                    evidence: evidence,
                    performance: performance,
                  )
                : _cardMode == _SpotCardMode.demand
                ? _demandGoalCardContent(
                    icon: _primaryCardIcon(entry),
                    title: title,
                    method: method,
                    benchmark: benchmark,
                    summary: marketSummary!,
                    evidence: evidence,
                    performance: performance,
                  )
                : _goalCardContent(
                    icon: _primaryCardIcon(entry),
                    title: title,
                    method: method,
                    benchmark: benchmark,
                    metric: _yieldCardMetric(metric!, evidence),
                  ),
          ),
        ),
      ),
    );
  }

  String _primaryCardIcon(_SpotListEntry entry) {
    final spotIcon = entry.spot?.icon.trim() ?? '';
    if (spotIcon.isNotEmpty) return spotIcon;

    final benchmark = entry.benchmark;
    if (benchmark != null) {
      final primaryItemId = benchmark.source.yieldProfile.primaryItemId;
      return _itemIcon(primaryItemId.toString());
    }

    return _goalIconPath;
  }

  Widget _browseCardContent({
    required String icon,
    required String title,
    required String location,
  }) => Row(
    children: [
      GameIcon(icon, size: 44),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.12,
              ),
            ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _goalCardContent({
    required String icon,
    required String title,
    required Method? method,
    required _BairogRouteView? benchmark,
    required Widget metric,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GameIcon(icon, size: 44),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.12,
              ),
            ),
            const SizedBox(height: 5),
            metric,
            if (benchmark != null) ...[
              const SizedBox(height: 4),
              Text(
                'At ${benchmark.gathersPerHour} gathers/h',
                key: ValueKey(
                  'bairog-card-evidence-${benchmark.sourceRouteId}',
                ),
                softWrap: true,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.1,
                  color: muted,
                ),
              ),
            ],
          ],
        ),
      ),
      if (method != null) ...[
        const SizedBox(width: 8),
        Semantics(
          label: method.label,
          image: true,
          child: _methodArtwork(method.icon, size: 30),
        ),
      ],
    ],
  );

  Widget _yieldCardMetric(String metric, String evidence) => Semantics(
    label: '$metric. $evidence',
    excludeSemantics: true,
    child: Row(
      children: [
        GameIcon(_goalIconPath, size: 23),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            metric,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.1,
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _valueGoalCardContent({
    required String icon,
    required String title,
    required Method? method,
    required _BairogRouteView? benchmark,
    required _MarketSummary summary,
    required String evidence,
    required SpotPerformance? performance,
  }) {
    final displayedContributions = _displayedValueContributions(summary);
    return Semantics(
      key: ValueKey(
        'value-card-semantics-'
        '${displayedContributions.map((entry) => entry.itemId).join('-')}',
      ),
      label:
          '$title. ${method == null ? '' : '${method.label}. '}'
          '${_valueCardAccessibility(summary, evidence, performance)}',
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const ValueKey('value-card-header'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GameIcon(icon, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _valueTotalRow(summary, performance),
                  ],
                ),
              ),
              if (method != null) ...[
                const SizedBox(width: 8),
                _methodArtwork(method.icon, size: 30),
              ],
              const SizedBox(width: 5),
              _calculationInfoButton(
                mode: _SpotCardMode.value,
                icon: icon,
                title: title,
                benchmark: benchmark,
                summary: summary,
                performance: performance,
              ),
            ],
          ),
          if (displayedContributions.isNotEmpty) ...[
            const SizedBox(height: 5),
            _valueLootRows(summary),
          ],
          if (benchmark != null) ...[
            const SizedBox(height: 4),
            Text(
              'At ${benchmark.gathersPerHour} gathers/h',
              key: ValueKey('bairog-card-evidence-${benchmark.sourceRouteId}'),
              softWrap: true,
              style: const TextStyle(fontSize: 11.5, height: 1.1, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _valueCardMetric(
    _MarketSummary summary,
    String evidence,
    SpotPerformance? performance,
  ) {
    if (!summary.hasPricedIncome) {
      return Text(
        _marketLoading ? 'Updating…' : _marketError ?? 'No current value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: muted),
      );
    }
    final displayedContributions = _displayedValueContributions(summary);
    return Semantics(
      key: ValueKey(
        'value-card-semantics-'
        '${displayedContributions.map((entry) => entry.itemId).join('-')}',
      ),
      label: _valueCardAccessibility(summary, evidence, performance),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _valueTotalRow(summary, performance),
          const SizedBox(height: 4),
          _valueLootRows(summary),
        ],
      ),
    );
  }

  String _valuePrefix(_MarketSummary summary, SpotPerformance? performance) =>
      switch (summary.estimateBound) {
        _MarketEstimateBound.lower => '≥ ',
        _MarketEstimateBound.upper => '≤ ',
        _MarketEstimateBound.partial => '≈ ',
        _MarketEstimateBound.exact =>
          performance?.containsApproximateLoot == true ? '≈ ' : '',
      };

  Widget _valueTotalRow(_MarketSummary summary, SpotPerformance? performance) {
    if (!summary.hasPricedIncome) {
      return Text(
        _marketLoading ? 'Updating…' : _marketError ?? 'No current value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: muted),
      );
    }
    final prefix = _valuePrefix(summary, performance);
    return Row(
      key: const ValueKey('value-card-total'),
      children: [
        const GameIcon('assets/icons/items/1.webp', size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$prefix${_silverText(summary.total)}/h',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.1,
              color: positive,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  List<_MarketContribution> _displayedValueContributions(
    _MarketSummary summary,
  ) => _orderedPositiveContributions(summary);

  List<_MarketContribution> _orderedPositiveContributions(
    _MarketSummary summary,
  ) {
    final byItemId = <String, _MarketContribution>{
      for (final contribution in summary.contributions)
        contribution.itemId: contribution,
    };
    return List.unmodifiable(<_MarketContribution>[
      for (final itemId in summary.compactCardItemIds)
        if (byItemId[itemId] case final contribution?
            when !contribution.detailsOnly &&
                contribution.perHour > 0 &&
                contribution.netValuePerHour > 0)
          contribution,
    ]);
  }

  String _valueCardAccessibility(
    _MarketSummary summary,
    String evidence,
    SpotPerformance? performance,
  ) {
    if (!summary.hasPricedIncome) {
      final status = _marketLoading
          ? 'Marketplace values are updating.'
          : _marketError ?? 'No current value.';
      return '$status $evidence';
    }
    final prefix = _valuePrefix(summary, performance);
    final contributionEvidence = _displayedValueContributions(
      summary,
    ).map(_valueContributionAccessibility).join('. ');
    return '$prefix${_silverText(summary.total)} per hour. '
        '${contributionEvidence.isEmpty ? '' : '$contributionEvidence. '}'
        '${_marketEvidence(summary, evidence)}';
  }

  Widget _valueLootRows(_MarketSummary summary) {
    final displayed = _displayedValueContributions(summary);
    return SizedBox(
      key: const ValueKey('value-card-loot'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final contribution in displayed) _contributionRow(contribution),
        ],
      ),
    );
  }

  String _valueContributionAccessibility(_MarketContribution contribution) {
    return '${contribution.name}: '
        '${_silverText(contribution.netValuePerHour)} per hour'
        '${contribution.vendorPrice ? '' : '. ${_valueMarketAccessibility(contribution)}'}';
  }

  String _valueMarketAccessibility(_MarketContribution contribution) {
    final stock = contribution.stock;
    if (stock == null) {
      return 'Stock ${_marketLoading ? 'updating' : 'unavailable'}';
    }
    if (stock > 0) {
      return 'Current stock: ${_groupedWholeNumber(stock)}';
    }
    final preorders = contribution.preorders;
    if (preorders != null) {
      return 'Current stock: 0. '
          'Current preorders: ${_groupedWholeNumber(preorders)}';
    }
    return 'Current stock: 0. '
        'Preorder count is ${_marketLoading ? 'updating' : 'unavailable'}';
  }

  String _valueMarketTooltip(_MarketContribution contribution) {
    final stock = contribution.stock;
    if (stock == null) {
      return 'Stock\nListings\n${_marketLoading ? 'Updating…' : 'Not available'}';
    }
    if (stock > 0) {
      return 'Stock\nListings\n${_groupedWholeNumber(stock)}';
    }
    final preorders = contribution.preorders;
    return 'Stock\n'
        'Listings\n0\n'
        'Preorders\n'
        '${preorders == null ? (_marketLoading ? 'Updating…' : 'Not available') : _groupedWholeNumber(preorders)}';
  }

  Widget _contributionRow(_MarketContribution contribution) => Padding(
    key: ValueKey('value-contribution-row-${contribution.itemId}'),
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        GameIcon(
          contribution.icon,
          key: ValueKey('value-contribution-icon-${contribution.itemId}'),
          size: 24,
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: Text(
            contribution.name,
            key: ValueKey('value-contribution-name-${contribution.itemId}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, height: 1.1),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _silverText(contribution.netValuePerHour),
                  style: const TextStyle(
                    fontSize: 12,
                    color: positive,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!contribution.vendorPrice) ...[
                  const SizedBox(width: 5),
                  _valueStockCount(contribution),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _valueStockCount(
    _MarketContribution contribution, {
    double fontSize = 11,
    double iconSize = 10,
  }) {
    final stock = contribution.stock;
    final preorders = stock == 0 ? contribution.preorders : null;
    final hasPreorders = preorders != null && preorders > 0;
    final color = hasPreorders ? Theme.of(context).colorScheme.error : muted;
    final displayCount = stock == null
        ? '—'
        : hasPreorders
        ? '−${_groupedWholeNumber(preorders)}'
        : _compactMarketCount(stock);
    return Tooltip(
      key: ValueKey('value-stock-tooltip-${contribution.itemId}'),
      message: _valueMarketTooltip(contribution),
      child: Semantics(
        label: _valueMarketAccessibility(contribution),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: iconSize, color: color),
            const SizedBox(width: 2),
            Text(
              displayCount,
              key: ValueKey('value-stock-${contribution.itemId}'),
              maxLines: 1,
              style: TextStyle(
                fontSize: fontSize,
                height: 1,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _demandGoalCardContent({
    required String icon,
    required String title,
    required Method? method,
    required _BairogRouteView? benchmark,
    required _MarketSummary summary,
    required String evidence,
    required SpotPerformance? performance,
  }) {
    final displayedContributions = _displayedDemandContributions(summary);
    final demandDriver = _freshDemandItemForSummary(summary);
    return Semantics(
      key: ValueKey(
        'demand-card-semantics-'
        '${displayedContributions.map((item) => item.itemId).join('-')}',
      ),
      label:
          '$title. ${method == null ? '' : '${method.label}. '}'
          '${_demandCardAccessibility(summary, displayedContributions, demandDriver, evidence, performance)}',
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const ValueKey('demand-card-header'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GameIcon(icon, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _demandTotalRow(summary, performance),
                  ],
                ),
              ),
              if (method != null) ...[
                const SizedBox(width: 8),
                _methodArtwork(method.icon, size: 30),
              ],
              const SizedBox(width: 5),
              _calculationInfoButton(
                mode: _SpotCardMode.demand,
                icon: icon,
                title: title,
                benchmark: benchmark,
                summary: summary,
                performance: performance,
              ),
            ],
          ),
          if (displayedContributions.isNotEmpty) ...[
            const SizedBox(height: 5),
            _demandLootRows(displayedContributions),
          ],
          if (benchmark != null) ...[
            const SizedBox(height: 4),
            Text(
              'At ${benchmark.gathersPerHour} gathers/h',
              key: ValueKey('bairog-card-evidence-${benchmark.sourceRouteId}'),
              softWrap: true,
              style: const TextStyle(fontSize: 11.5, height: 1.1, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _demandTotalRow(_MarketSummary summary, SpotPerformance? performance) {
    if (!summary.hasPricedIncome) {
      return Text(
        _marketLoading
            ? 'Updating…'
            : _marketError ?? 'Market data unavailable',
        key: const ValueKey('demand-card-total'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: muted),
      );
    }
    final prefix = _valuePrefix(summary, performance);
    return Row(
      key: const ValueKey('demand-card-total'),
      children: [
        const GameIcon('assets/icons/items/1.webp', size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$prefix${_silverText(summary.total)}/h',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.1,
              color: positive,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  List<_MarketContribution> _displayedDemandContributions(
    _MarketSummary summary,
  ) => _orderedPositiveContributions(summary);

  String _demandCardAccessibility(
    _MarketSummary summary,
    List<_MarketContribution> displayed,
    _MarketContribution? demandDriver,
    String evidence,
    SpotPerformance? performance,
  ) {
    if (!summary.hasPricedIncome) {
      final status = _marketLoading
          ? 'Marketplace values are updating.'
          : _marketError ?? 'Marketplace data is unavailable.';
      return '$status $evidence';
    }
    final prefix = _valuePrefix(summary, performance);
    final rows = displayed.map(_demandContributionAccessibility).join('. ');
    final rankedBy = demandDriver == null
        ? ''
        : 'Ranked by demand for ${demandDriver.name}. ';
    return '$prefix${_silverText(summary.total)} per hour. '
        '$rankedBy${rows.isEmpty ? '' : '$rows. '}'
        '${_marketEvidence(summary, evidence)}';
  }

  Widget _demandLootRows(List<_MarketContribution> displayed) {
    return SizedBox(
      key: const ValueKey('demand-card-loot'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final contribution in displayed)
            _demandContributionRow(contribution),
        ],
      ),
    );
  }

  Widget _demandRouteMetric(
    _BairogRouteView route,
    _MarketSummary summary,
    String evidence,
  ) {
    final displayed = _displayedDemandContributions(summary);
    return Semantics(
      label: _demandCardAccessibility(
        summary,
        displayed,
        _freshDemandItemForSummary(summary),
        evidence,
        null,
      ),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _demandTotalRow(summary, null),
          if (displayed.isNotEmpty) ...[
            const SizedBox(height: 4),
            _demandLootRows(displayed),
          ],
        ],
      ),
    );
  }

  int? _freshDemandStock(_MarketContribution contribution) {
    if (contribution.vendorPrice || contribution.stock == null) return null;
    final coveredAt = _baseCoveredAtById[contribution.itemId];
    if (coveredAt == null ||
        DateTime.now().toUtc().difference(coveredAt) >= _marketFreshFor) {
      return null;
    }
    return contribution.stock;
  }

  _MarketContribution? _freshDemandItemForSummary(_MarketSummary summary) =>
      _hasFreshDemandStockCoverage(summary)
      ? _demandItemForSummary(summary)
      : null;

  String _demandContributionAccessibility(_MarketContribution contribution) {
    final stock = _freshDemandStock(contribution);
    final preorders = contribution.preorders;
    final market = contribution.vendorPrice
        ? 'Sold to a vendor.'
        : '${stock == null ? 'Stock unavailable.' : 'Current stock: ${_groupedWholeNumber(stock)}.'} '
              '${preorders == null ? 'Preorders unavailable.' : 'Current preorders: ${_groupedWholeNumber(preorders)}.'}';
    return '${contribution.name}: ${_rateText(contribution.perHour)} per hour, '
        '${_silverText(contribution.netValuePerHour)} silver per hour. $market';
  }

  String _demandContributionTooltip(_MarketContribution contribution) {
    final stock = _freshDemandStock(contribution);
    final preorders = contribution.preorders;
    if (contribution.vendorPrice) {
      return '${contribution.name}\n'
          'Estimate\n${_rateText(contribution.perHour)}/h\n'
          'Value\n${_silverText(contribution.netValuePerHour)}/h\n'
          'Sale\nVendor';
    }
    return '${contribution.name}\n'
        'Estimate\n${_rateText(contribution.perHour)}/h\n'
        'Value\n${_silverText(contribution.netValuePerHour)}/h\n'
        'Stock\n'
        'Listings\n${stock == null ? 'Not available' : _groupedWholeNumber(stock)}\n'
        'Preorders\n${preorders == null ? (_marketLoading ? 'Updating…' : 'Not available') : _groupedWholeNumber(preorders)}';
  }

  Widget _demandContributionRow(_MarketContribution contribution) => Padding(
    key: ValueKey('demand-contribution-row-${contribution.itemId}'),
    padding: const EdgeInsets.only(bottom: 3),
    child: Tooltip(
      key: ValueKey('demand-contribution-tooltip-${contribution.itemId}'),
      message: _demandContributionTooltip(contribution),
      child: Semantics(
        key: ValueKey('demand-semantics-${contribution.itemId}'),
        label: _demandContributionAccessibility(contribution),
        excludeSemantics: true,
        child: Row(
          children: [
            GameIcon(
              contribution.icon,
              key: ValueKey('demand-contribution-icon-${contribution.itemId}'),
              size: 24,
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: Text(
                contribution.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, height: 1.1),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _silverText(contribution.netValuePerHour),
                      key: ValueKey('demand-value-${contribution.itemId}'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: positive,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!contribution.vendorPrice) ...[
                      const SizedBox(width: 5),
                      _demandMarketCounts(contribution),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _demandMarketCounts(
    _MarketContribution contribution, {
    double fontSize = 11,
    double iconSize = 10,
  }) {
    final stock = _freshDemandStock(contribution);
    final preorders = contribution.preorders;
    if (stock == null && preorders == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: iconSize, color: muted),
          const SizedBox(width: 2),
          Text(
            '—',
            key: ValueKey('demand-stock-${contribution.itemId}'),
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stock != null) ...[
          Icon(Icons.storefront_outlined, size: iconSize, color: muted),
          const SizedBox(width: 2),
          Text(
            _groupedWholeNumber(stock),
            key: ValueKey('demand-stock-${contribution.itemId}'),
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (stock != null && preorders != null)
          const Text(
            ' · ',
            style: TextStyle(fontSize: 11, height: 1, color: muted),
          ),
        if (preorders != null)
          Text(
            preorders > 0 ? '−${_groupedWholeNumber(preorders)}' : '0',
            key: ValueKey('demand-preorders-${contribution.itemId}'),
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              color: preorders > 0
                  ? Theme.of(context).colorScheme.error
                  : muted,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  Widget _calculationInfoButton({
    required _SpotCardMode mode,
    required String icon,
    required String title,
    required _BairogRouteView? benchmark,
    required _MarketSummary summary,
    required SpotPerformance? performance,
  }) {
    final modeLabel = mode == _SpotCardMode.demand ? 'demand' : 'value';
    final entryId =
        benchmark?.sourceRouteId.toString() ??
        '${performance?.spotId}-${performance?.methodId}';
    final loadingKey = '$modeLabel-$entryId';
    final loading = _calculationLoadingEntries.contains(loadingKey);
    return IconButton(
      key: ValueKey('$modeLabel-calculation-info-$entryId'),
      tooltip: 'Show calculation for $title',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      iconSize: 18,
      color: muted,
      onPressed: loading
          ? null
          : () => _openMarketCalculationDetails(
              loadingKey: loadingKey,
              icon: icon,
              title: title,
              benchmark: benchmark,
              summary: summary,
              performance: performance,
            ),
      icon: loading
          ? SizedBox.square(
              key: ValueKey('$modeLabel-calculation-loading-$entryId'),
              dimension: 18,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.info_outline_rounded),
    );
  }

  Future<void> _openMarketCalculationDetails({
    required String loadingKey,
    required String icon,
    required String title,
    required _BairogRouteView? benchmark,
    required _MarketSummary summary,
    required SpotPerformance? performance,
  }) async {
    if (_calculationLoadingEntries.contains(loadingKey)) return;
    setState(() => _calculationLoadingEntries.add(loadingKey));
    late final _MarketSummary refreshedSummary;
    try {
      try {
        await _loadMarketQuotes(scope: _MarketLoadScope.demand);
      } catch (_) {
        // The dialog still opens with explicit unavailable-price rows.
      }
      if (!mounted) return;
      final refreshedBenchmark = benchmark == null
          ? null
          : _bairogRoutes
                    .where(
                      (route) => route.sourceRouteId == benchmark.sourceRouteId,
                    )
                    .firstOrNull ??
                benchmark;
      refreshedSummary = refreshedBenchmark != null
          ? _marketSummaryForBenchmark(refreshedBenchmark)
          : performance != null
          ? _marketSummaryForPerformance(performance)
          : summary;
      await _precacheCalculationIcons(icon, refreshedSummary);
    } finally {
      if (mounted) {
        setState(() => _calculationLoadingEntries.remove(loadingKey));
      }
    }
    if (!mounted) return;
    await _showMarketCalculationDetails(
      icon: icon,
      title: title,
      summary: refreshedSummary,
    );
  }

  Future<void> _precacheCalculationIcons(
    String spotIcon,
    _MarketSummary summary,
  ) async {
    final paths = <String>{
      if (spotIcon.isNotEmpty) spotIcon,
      for (final contribution in summary.contributions)
        if (contribution.icon.isNotEmpty) contribution.icon,
    };
    await Future.wait<void>([
      for (final path in paths)
        () async {
          try {
            await precacheImage(
              AssetImage(path, package: gatheringAssetPackage),
              context,
              onError: (_, _) {
                return;
              },
            );
          } catch (_) {
            // GameIcon keeps its explicit unavailable-artwork fallback.
          }
        }(),
    ]);
  }

  Future<void> _showMarketCalculationDetails({
    required String icon,
    required String title,
    required _MarketSummary summary,
  }) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      final maxHeight = (viewport.height - 32).clamp(280.0, 880.0);
      return Dialog(
        key: const ValueKey('market-calculation-dialog'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
          child: GlassSurface(
            key: const ValueKey('market-calculation-surface'),
            elevated: true,
            reading: true,
            radius: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: context.glass.headerGradient,
                  ),
                  child: _calculationDialogHeader(
                    dialogContext: dialogContext,
                    icon: icon,
                    title: title,
                  ),
                ),
                Divider(height: 1, color: context.glass.strongLine),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('market-calculation-scroll'),
                    padding: const EdgeInsets.all(12),
                    child: _calculationIncomeGrid(summary.contributions),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _calculationIncomeGrid(List<_MarketContribution> contributions) =>
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final scaledBody = MediaQuery.textScalerOf(context).scale(13.5);
          final useTwoColumns =
              constraints.maxWidth >= 600 && scaledBody <= 17.0;
          final tileWidth = useTwoColumns
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;
          return Wrap(
            key: ValueKey(
              useTwoColumns
                  ? 'market-calculation-columns-2'
                  : 'market-calculation-columns-1',
            ),
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final contribution in contributions)
                SizedBox(
                  width: tileWidth,
                  child: _calculationIncomeRow(contribution),
                ),
            ],
          );
        },
      );

  Widget _calculationDialogHeader({
    required BuildContext dialogContext,
    required String icon,
    required String title,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 11, 8, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GameIcon(icon, size: 42),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(dialogContext).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );

  Widget _calculationIncomeRow(_MarketContribution contribution) {
    final valueText = contribution.missingPrice
        ? 'Value unavailable'
        : _fullSilverText(contribution.netValuePerHour);
    final displayedValue = contribution.missingPrice
        ? 'Unavailable'
        : _fullSilverNumber(contribution.netValuePerHour);
    final marketText = _calculationMarketText(contribution);
    return Container(
      key: ValueKey('calculation-income-${contribution.itemId}'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: context.glass.groupGradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.glass.insetLine),
      ),
      child: Semantics(
        label:
            '${contribution.name}. Expected quantity per hour: ${contribution.perHour}. '
            'Value per hour: $valueText. '
            '${_calculationMarketAccessibility(contribution)}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GameIcon(
              contribution.icon,
              key: ValueKey('calculation-icon-${contribution.itemId}'),
              size: 34,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contribution.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    contribution.perHour > 0 && contribution.perHour < .01
                        ? '< 0,01 / h'
                        : '≈ ${_fullSilverNumber(contribution.perHour)} / h',
                    key: ValueKey(
                      'calculation-quantity-${contribution.itemId}',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _calculationFact(
                          'Value / h',
                          displayedValue,
                          valueColor: contribution.missingPrice
                              ? muted
                              : positive,
                          scaleDown: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 72,
                        child: _calculationFact(
                          'Stock',
                          marketText,
                          valueKey: ValueKey(
                            'calculation-market-${contribution.itemId}',
                          ),
                          valueColor: _calculationMarketColor(contribution),
                          scaleDown: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculationMarketText(_MarketContribution contribution) {
    final stock = _freshDemandStock(contribution);
    if (stock == null) return '—';
    if (stock > 0) return _groupedWholeNumber(stock);
    final preorders = contribution.preorders;
    if (preorders == null) return '0';
    if (preorders > 0) {
      return '−${_groupedWholeNumber(preorders)}';
    }
    return '0';
  }

  Color _calculationMarketColor(_MarketContribution contribution) {
    final stock = _freshDemandStock(contribution);
    if (stock == null) return muted;
    if (stock > 0) return muted;
    final preorders = contribution.preorders;
    if (preorders != null && preorders > 0) {
      return Theme.of(context).colorScheme.error;
    }
    return muted;
  }

  String _calculationMarketAccessibility(_MarketContribution contribution) {
    final stock = _freshDemandStock(contribution);
    if (stock == null) return 'Stock information unavailable.';
    if (stock > 0) {
      return 'Stock: ${_groupedWholeNumber(stock)}.';
    }
    final preorders = contribution.preorders;
    if (preorders == null) {
      return 'Stock: 0. Preorder information unavailable.';
    }
    if (preorders > 0) {
      return 'Preorders: ${_groupedWholeNumber(preorders)}.';
    }
    return 'Stock and preorders: 0.';
  }

  Widget _calculationFact(
    String label,
    String value, {
    Key? valueKey,
    Color? valueColor,
    bool scaleDown = false,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, height: 1, color: muted),
      ),
      const SizedBox(height: 2),
      if (scaleDown)
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: valueKey,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.1,
              color: valueColor ?? ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        )
      else
        Text(
          value,
          key: valueKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.1,
            color: valueColor ?? ink,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );

  String _fullSilverNumber(double value) {
    final roundedToHundredth = (value * 100).round() / 100;
    final absolute = roundedToHundredth.abs();
    final fixed = absolute.toStringAsFixed(2).split('.');
    final fraction = fixed[1].replaceFirst(RegExp(r'0+$'), '');
    final whole = _groupedWholeNumber(int.parse(fixed[0]));
    return '${roundedToHundredth < 0 ? '−' : ''}$whole'
        '${fraction.isEmpty ? '' : ',$fraction'}';
  }

  String _fullSilverText(double value) => '${_fullSilverNumber(value)} silver';

  String _marketEvidence(_MarketSummary summary, String sourceEvidence) {
    final current = summary.contributions
        .where((entry) => entry.fetchedAt != null)
        .map((entry) => entry.fetchedAt!)
        .fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    final time = current == null
        ? ''
        : ' · EU Marketplace ${_clockText(current.toLocal())}';
    final missingIncome = summary.missingItemIds.isEmpty
        ? ''
        : ' · lower bound (${summary.missingItemIds.length} unavailable)';
    final missingCosts = summary.missingCostItemIds.isEmpty
        ? ''
        : ' · costs incomplete (${summary.missingCostItemIds.length} unavailable)';
    final keyWarning = summary.missingGoldKeyPrice
        ? ' · Gold Key not priced'
        : '';
    return '$sourceEvidence$time$missingIncome$missingCosts$keyWarning';
  }

  String _metricText(SpotPerformance performance) {
    final approximate = performance.containsApproximateLoot ? '≈ ' : '';
    return switch (_ranking) {
      _SpotRanking.sharp =>
        '$approximate${_rateText(performance.itemsPerHour('4998'))}/h',
      _SpotRanking.dust =>
        '$approximate${_rateText(performance.itemsPerHour('721002'))}/h',
      _SpotRanking.caphras =>
        '$approximate${_rateText(performance.itemsPerHour('721003'))}/h',
      _SpotRanking.profit => '',
      _SpotRanking.demand => '',
      _ => '',
    };
  }

  String _benchmarkMetricText(_BairogRouteView benchmark) {
    final nostos = _nostosMaterial;
    if (nostos != null) {
      return benchmark.nostosYield.itemId == nostos.itemId
          ? '≈${_rateText(benchmark.nostosYield.perHour)}/h'
          : '';
    }
    final value = benchmark.score(_bairogGoal);
    return switch (_ranking) {
      _SpotRanking.profit || _SpotRanking.demand => '',
      _SpotRanking.sharp ||
      _SpotRanking.dust ||
      _SpotRanking.caphras => '≈${_rateText(value)}/h',
      _ => '',
    };
  }

  String _clockText(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _groupedWholeNumber(int value) {
    final digits = value.abs().toString();
    final firstGroupLength = digits.length % 3;
    final groups = <String>[
      if (firstGroupLength > 0) digits.substring(0, firstGroupLength),
      for (var index = firstGroupLength; index < digits.length; index += 3)
        digits.substring(index, index + 3),
    ];
    return '${value < 0 ? '−' : ''}${groups.join('.')}';
  }

  String _compactMarketCount(int value) {
    if (value < 10000) return _groupedWholeNumber(value);
    if (value < 1000000) {
      final scaled = value / 1000;
      return '${scaled.toStringAsFixed(value < 100000 ? 1 : 0)}K';
    }
    final scaled = value / 1000000;
    return '${scaled.toStringAsFixed(value < 10000000 ? 1 : 0)}M';
  }

  String _rateText(double value) {
    if (value >= 100) return value.toStringAsFixed(0);
    if (value >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  String _plainNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  String _minigameLabel(BairogMinigameMode mode) => switch (mode) {
    BairogMinigameMode.none => 'No minigame',
    BairogMinigameMode.normal => 'Normal minigame (5%)',
    BairogMinigameMode.event => 'Event minigame (10%)',
  };

  String _compactMinigameLabel(BairogMinigameMode mode) => switch (mode) {
    BairogMinigameMode.none => 'No minigame',
    BairogMinigameMode.normal => 'Normal 5%',
    BairogMinigameMode.event => 'Event 10%',
  };

  String _hedgehogLabel(BairogHedgehogTier tier) => switch (tier) {
    BairogHedgehogTier.none => 'No Hedgehog/Llama',
    _ => 'Tier ${tier.storageValue} Hedgehog/Llama',
  };

  String _calculatorCaptureDate() {
    final captured = widget.bairogCalculatorData?.source.capturedAtUtc;
    if (captured == null) return bairogBenchmarkSet.capturedOn;
    return '${captured.year.toString().padLeft(4, '0')}-'
        '${captured.month.toString().padLeft(2, '0')}-'
        '${captured.day.toString().padLeft(2, '0')}';
  }

  String _energyEvidence(BairogEnergyMetrics energy) {
    final net = energy.netEnergyDrainPerHour;
    final drain = net > 0
        ? '${_rateText(net)} net Energy/h'
        : 'no net Energy drain';
    final session = energy.sessionHours.isFinite
        ? ' · ${_rateText(energy.sessionHours)}h from '
              '${_rateText(energy.startingEnergy + energy.energyBoost)} Energy'
        : '';
    return '${_rateText(energy.energyUsePerHour)} Energy used/h · '
        '$drain$session';
  }

  String _hoursText(double value) => value >= 10
      ? '${value.toStringAsFixed(0)}h'
      : '${value.toStringAsFixed(1)}h';

  String _silverText(double value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(2)}B';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value >= 100000000 ? 0 : 1)}M';
    }
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }

  Widget _map(double height) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        SpotMap(
          key: const ValueKey('spot-guide-map'),
          spots: _visibleSpots,
          selected: _selected,
          methods: widget.catalog.methods,
          nodes: widget.catalog.mapNodes,
          overview: _selected == null,
          onSelect: _select,
        ),
        if (_isGoalRanking)
          Positioned(right: 12, bottom: 12, child: _bairogMapLink()),
      ],
    ),
  );

  Widget _bairogMapLink() => Tooltip(
    message: 'Bairog',
    child: Semantics(
      label: 'Bairog · BDO Workshop source',
      link: true,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          key: const ValueKey('bairog-calculator-link'),
          radius: 22,
          onTap: _openBairogCalculator,
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: GameIcon(
              'assets/icons/sources/bdoworkshop_logo.png',
              size: 34,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _detail(Spot spot) {
    final methods = widget.catalog.methods
        .where((method) => spot.methodIds.contains(method.id))
        .toList();
    final selectedMethod =
        methods
            .where((method) => method.id == (_detailMethodId ?? _method))
            .firstOrNull ??
        methods.first;
    final selectedBenchmark =
        _isGoalRanking && _rankingSource == _RankingSource.bairog
        ? (_selectedBenchmark?.spotId == spot.id &&
                  _selectedBenchmark?.methodId == selectedMethod.id
              ? _selectedBenchmark
              : _bestBairogBenchmark(spot))
        : null;
    final media = spot.media
        .where((entry) => entry.matchesMethod(selectedMethod.id))
        .toList();
    final loot = widget.catalog.lootForSpot(spot, selectedMethod.id);
    final primaryIds = spot.materials
        .where(
          (item) =>
              strings(item['methodIds']).contains(selectedMethod.id) &&
              textOf(item, 'rarity') != 'rare',
        )
        .map((item) => textOf(item, 'itemId'))
        .toSet();
    final primary = loot
        .where((item) => primaryIds.contains(item.id))
        .take(2)
        .toList();
    final other = loot.where((item) => !primary.contains(item)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 660;
        final gap = 16.0;
        final rightWidth = wide
            ? math.max(
                300.0,
                (constraints.maxWidth - gap) / (media.isEmpty ? 2.9 : 2.6),
              )
            : constraints.maxWidth;
        final mediaHeight = media.any((entry) => entry.type == 'video')
            ? math.max(320.0, rightWidth * 9 / 16 + 92)
            : math.max(240.0, rightWidth * 9 / 16 + 40);
        final columns = ((rightWidth + 6) / 54).floor().clamp(1, 20);
        final rows = (other.length / columns).ceil();
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final lootHeight = 36 * scale + primary.length * 56 * scale + rows * 54;
        final mapHeight = wide
            ? math.max(
                media.isEmpty ? 430.0 : 460.0,
                (media.isEmpty ? 0.0 : mediaHeight + gap) + lootHeight - 40,
              )
            : 320.0;
        final pickups = _pickups(
          spot,
          selectedMethod.id,
          primary,
          other,
          benchmark: selectedBenchmark,
        );
        final references = SpotMediaGallery(
          key: ValueKey('guide-media-${spot.id}'),
          media: media,
          height: mediaHeight,
        );
        final map = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Map',
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                    if (spot.mapNote.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: spot.mapNote,
                        child: const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _map(mapHeight),
          ],
        );
        return Column(
          key: ValueKey('spot-detail-${spot.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(spot, methods, selectedMethod, media),
            const SizedBox(height: 12),
            if (!spot.mapped) ...[
              if (spot.summary.isNotEmpty) ...[
                Text(
                  spot.summary,
                  style: const TextStyle(fontSize: 14, color: muted),
                ),
                const SizedBox(height: 12),
              ],
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (media.isNotEmpty) ...[
                      Expanded(flex: 2, child: references),
                      const SizedBox(width: 16),
                    ],
                    Expanded(child: pickups),
                  ],
                )
              else ...[
                if (media.isNotEmpty) ...[
                  references,
                  const SizedBox(height: 16),
                ],
                pickups,
              ],
              const SizedBox(height: 8),
              _unmappedGuideNotes(spot),
            ] else if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: map),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: rightWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (media.isNotEmpty) ...[
                          references,
                          const SizedBox(height: 16),
                        ],
                        pickups,
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              map,
              const SizedBox(height: 16),
              if (media.isNotEmpty) ...[references, const SizedBox(height: 16)],
              pickups,
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              'Buffs',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            RecommendedBuffs(
              catalog: widget.catalog,
              activity: selectedMethod.activity,
              horizontal: true,
              methodId: selectedMethod.id,
              spotId: spot.id,
            ),
          ],
        );
      },
    );
  }

  Widget _unmappedGuideNotes(Spot spot) => ExpansionTile(
    key: const ValueKey('unmapped-spot-guide-notes'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    title: const Text('Route tips', style: TextStyle(fontSize: 15)),
    children: [
      Text(spot.mapNote, style: const TextStyle(fontSize: 14, color: muted)),
      if (spot.tips.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final tip in spot.tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(tip, style: const TextStyle(fontSize: 14)),
          ),
      ],
    ],
  );

  Widget _heading(
    Spot spot,
    List<Method> methods,
    Method selectedMethod,
    List<SpotMedia> media,
  ) {
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const ValueKey('guide-change-spot'),
          onPressed: _chooseAnotherSpot,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Choose another spot'),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              GameIcon(spot.icon, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.displayName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spot.nodeName,
                      style: const TextStyle(fontSize: 15, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final tools = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final method in methods)
          Tooltip(
            message: method.label,
            child: Semantics(
              button: true,
              selected: method.id == selectedMethod.id,
              label: method.label,
              child: GlassControl(
                selected: method.id == selectedMethod.id,
                radius: 8,
                child: InkWell(
                  key: ValueKey('guide-tool-${method.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _detailMethodId = method.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _methodArtwork(method.icon, size: 44),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final use = FilledButton(
      key: const ValueKey('use-spot'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      onPressed: () {
        final useWithMethod = widget.onUseWithMethod;
        if (useWithMethod != null) {
          useWithMethod(spot, selectedMethod.id);
        } else {
          widget.onUse(spot);
        }
      },
      child: Text(widget.useLabel, style: const TextStyle(fontSize: 14)),
    );
    final directions = IconButton(
      key: const ValueKey('guide-directions'),
      tooltip: 'Directions',
      onPressed: () => _showDirections(spot, media),
      icon: const Icon(Icons.info_outline, size: 21, color: muted),
    );
    return LayoutBuilder(
      key: const ValueKey('guide-context'),
      builder: (context, constraints) =>
          constraints.maxWidth >=
              1000 *
                  math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14)
          ? Row(
              children: [
                SizedBox(
                  width: math.min(520, constraints.maxWidth * .52),
                  child: name,
                ),
                const Spacer(),
                directions,
                const SizedBox(width: 10),
                tools,
                const SizedBox(width: 12),
                use,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: name),
                    directions,
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: tools),
                    const SizedBox(width: 12),
                    use,
                  ],
                ),
              ],
            ),
    );
  }

  Widget _pickups(
    Spot spot,
    String methodId,
    List<GameItem> primary,
    List<GameItem> other, {
    _BairogRouteView? benchmark,
  }) => Column(
    key: const ValueKey('guide-loot-grid'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Loot',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              if (benchmark != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'At ${benchmark.gathersPerHour} gathers/h',
                    key: const ValueKey('bairog-selected-route-evidence'),
                    textAlign: TextAlign.end,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.15,
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      for (final item in primary) ...[
        _material(spot, methodId, item, named: true),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final item in other) _material(spot, methodId, item)],
      ),
    ],
  );

  Widget _material(
    Spot spot,
    String methodId,
    GameItem item, {
    bool named = false,
  }) {
    final metadata = [...spot.materials, ...widget.catalog.commonLoot]
        .where(
          (row) =>
              textOf(row, 'itemId') == item.id &&
              strings(row['methodIds']).contains(methodId) &&
              !strings(row['excludedSpotIds']).contains(spot.id),
        )
        .firstOrNull;
    final note = metadata == null ? '' : textOf(metadata, 'conditionalNote');
    final noteLines = note
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final description = [item.name, if (note.isNotEmpty) note].join('\n');
    final icon = GameIcon(item.icon, size: 44);
    return Tooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: item.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (noteLines.isNotEmpty)
            TextSpan(text: '\n\n${noteLines.join('\n')}'),
        ],
      ),
      constraints: const BoxConstraints(maxWidth: 340),
      textAlign: TextAlign.left,
      child: Semantics(
        label: description,
        button: true,
        child: InkWell(
          key: ValueKey('guide-loot-${item.id}'),
          borderRadius: BorderRadius.circular(7),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              content: noteLines.isEmpty
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < noteLines.length; index++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: index == noteLines.length - 1 ? 0 : 8,
                            ),
                            child: Text(noteLines[index]),
                          ),
                      ],
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: named
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      icon,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                )
              : SizedBox(width: 48, height: 48, child: Center(child: icon)),
        ),
      ),
    );
  }

  Future<void> _showDirections(Spot spot, List<SpotMedia> media) {
    String? error;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(spot.displayName),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final direction in spot.directions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        direction,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  for (final link
                      in spot.guideLinks
                          .where(
                            (link) =>
                                textOf(link, 'type') != 'video' ||
                                !media.any((entry) => entry.type == 'video'),
                          )
                          .take(2))
                    TextButton.icon(
                      onPressed: () async {
                        var opened = false;
                        try {
                          opened = await NativeBridge.openExternal(
                            textOf(link, 'url'),
                          );
                        } catch (_) {
                          // Preserve the directions when Windows cannot open a guide.
                        }
                        if (!opened && context.mounted) {
                          update(() => error = 'Could not open the guide.');
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(textOf(link, 'label', 'Guide')),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
