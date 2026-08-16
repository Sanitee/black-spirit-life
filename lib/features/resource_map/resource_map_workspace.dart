import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app/state/planner_application_controller.dart';
import '../../app_identity.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../domain/market/market_calculations.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/planner_models.dart' show ItemAcquisitionRoute;
import '../../domain/state/planner_state.dart' show MarketState;
import '../shared/mode_item_icon.dart';
import 'worker_output_market_policy.dart';

class ResourceMapWorkspaceConfiguration {
  const ResourceMapWorkspaceConfiguration({
    this.cacheDirectory,
    this.tileSource = BdoTileSource.workermanCommunity,
    this.tileHttpClient,
    this.showSourceNotice = true,
  });

  final Directory? cacheDirectory;
  final BdoTileSource tileSource;
  final http.Client? tileHttpClient;
  final bool showSourceNotice;
}

class ResourceMapDatasetCache {
  ResourceMapDatasetCache({Future<BdoResourceMapDataset> Function()? loader})
    : _loader = loader ?? _loadBundled;

  final Future<BdoResourceMapDataset> Function() _loader;
  Future<BdoResourceMapDataset>? _dataset;

  Future<BdoResourceMapDataset> load() => _dataset ??= _loader();

  void invalidate() {
    _dataset = null;
  }

  static Future<BdoResourceMapDataset> _loadBundled() =>
      BdoResourceMapLoader.loadBundled();
}

class ResourceMapWorkerEconomicsCache {
  ResourceMapWorkerEconomicsCache({
    Future<BdoWorkerEconomicsDataset> Function()? loader,
  }) : _loader = loader ?? BdoWorkerEconomicsLoader.loadBundled;

  final Future<BdoWorkerEconomicsDataset> Function() _loader;
  Future<BdoWorkerEconomicsDataset>? _dataset;

  Future<BdoWorkerEconomicsDataset> load() => _dataset ??= _loader();

  void invalidate() {
    _dataset = null;
  }
}

class ResourceMapLodgingCache {
  ResourceMapLodgingCache({Future<LodgingDataset> Function()? loader})
    : _loader = loader ?? LodgingDataLoader.loadBundled;

  final Future<LodgingDataset> Function() _loader;
  Future<LodgingDataset>? _dataset;

  Future<LodgingDataset> load() => _dataset ??= _loader();

  void invalidate() {
    _dataset = null;
  }
}

class ResourceMapWorkspace extends StatefulWidget {
  const ResourceMapWorkspace({
    required this.fallbackApplicationDirectory,
    required this.appController,
    required this.catalogRepository,
    this.configuration = const ResourceMapWorkspaceConfiguration(),
    this.controller,
    this.datasetCache,
    this.workerEconomicsCache,
    this.lodgingCache,
    this.screenshotPicker,
    this.screenshotClipboardReader,
    this.activeNodeRecordingLauncher,
    this.activeNodeRecordingFinder,
    this.activeNodeRecordingPicker,
    this.activeNodeRecordingScanner,
    this.onRefreshMarketEvidence,
    super.key,
  });

  final Directory fallbackApplicationDirectory;
  final PlannerApplicationController appController;
  final CatalogRepository catalogRepository;
  final ResourceMapWorkspaceConfiguration configuration;
  final BdoResourceMapController? controller;
  final ResourceMapDatasetCache? datasetCache;
  final ResourceMapWorkerEconomicsCache? workerEconomicsCache;
  final ResourceMapLodgingCache? lodgingCache;
  final Future<Uint8List?> Function()? screenshotPicker;
  final Future<Uint8List?> Function()? screenshotClipboardReader;
  final BdoActiveNodeRecordingLauncher? activeNodeRecordingLauncher;
  final BdoActiveNodeRecordingFinder? activeNodeRecordingFinder;
  final BdoActiveNodeRecordingPicker? activeNodeRecordingPicker;
  final BdoActiveNodeRecordingScanner? activeNodeRecordingScanner;
  final BdoMarketEvidenceRefresh? onRefreshMarketEvidence;

  @override
  State<ResourceMapWorkspace> createState() => _ResourceMapWorkspaceState();
}

class _ResourceMapWorkspaceState extends State<ResourceMapWorkspace> {
  late ResourceMapDatasetCache _datasetCache;
  late ResourceMapWorkerEconomicsCache _workerEconomicsCache;
  late ResourceMapLodgingCache _lodgingCache;
  late Future<_ResourceMapWorkspaceData> _data;

  @override
  void initState() {
    super.initState();
    _datasetCache = widget.datasetCache ?? ResourceMapDatasetCache();
    _workerEconomicsCache =
        widget.workerEconomicsCache ?? ResourceMapWorkerEconomicsCache();
    _lodgingCache = widget.lodgingCache ?? ResourceMapLodgingCache();
    _data = _loadData();
  }

  @override
  void didUpdateWidget(ResourceMapWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.datasetCache == widget.datasetCache &&
        oldWidget.workerEconomicsCache == widget.workerEconomicsCache &&
        oldWidget.lodgingCache == widget.lodgingCache) {
      return;
    }
    _datasetCache = widget.datasetCache ?? ResourceMapDatasetCache();
    _workerEconomicsCache =
        widget.workerEconomicsCache ?? ResourceMapWorkerEconomicsCache();
    _lodgingCache = widget.lodgingCache ?? ResourceMapLodgingCache();
    _data = _loadData();
  }

  Future<_ResourceMapWorkspaceData> _loadData() async {
    final map = _datasetCache.load();
    final workerEconomics = _workerEconomicsCache.load();
    final lodging = _lodgingCache.load();
    return _ResourceMapWorkspaceData(
      map: await map,
      workerEconomics: await workerEconomics,
      lodging: await lodging,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return ResourceMapChromeTheme(
      data: chrome,
      child: FutureBuilder<_ResourceMapWorkspaceData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ResourceMapLoadFailure(
              error: snapshot.error!,
              onRetry: () {
                _datasetCache.invalidate();
                _workerEconomicsCache.invalidate();
                _lodgingCache.invalidate();
                setState(() {
                  _data = _loadData();
                });
              },
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const _ResourceMapLoading();
          }
          final dataset = data.map;
          return ValueListenableBuilder<Set<String>>(
            valueListenable: widget.appController.resourceMapFavoriteIds,
            builder: (context, favoriteResourceIds, _) {
              return ValueListenableBuilder<CraftMode>(
                valueListenable: widget.appController.activeMode,
                builder: (context, mode, _) {
                  final modeController = widget.appController.modes[mode]!;
                  return ValueListenableBuilder<BdoNodeNetworkPreferences>(
                    valueListenable:
                        widget.appController.resourceMapNodeNetworkPreferences,
                    builder: (context, nodeNetworkPreferences, _) {
                      return ValueListenableBuilder<BdoGatherChecklist>(
                        valueListenable:
                            widget.appController.resourceMapGatherChecklist,
                        builder: (context, gatherChecklist, _) {
                          return AnimatedBuilder(
                            animation: Listenable.merge(<Listenable>[
                              for (final controller
                                  in widget.appController.modes.values) ...[
                                controller.state,
                                controller.plan,
                              ],
                              widget.appController.marketTax,
                            ]),
                            builder: (context, _) {
                              final plan = modeController.plan.value;
                              final market = modeController.state.value.market;
                              final marketStates =
                                  <MarketState>[
                                        market,
                                        for (final entry
                                            in widget
                                                .appController
                                                .modes
                                                .entries)
                                          if (entry.key != mode)
                                            entry.value.state.value.market,
                                      ]
                                      .where(
                                        (state) =>
                                            state.region.trim().toLowerCase() ==
                                            market.region.trim().toLowerCase(),
                                      )
                                      .toList()
                                    ..sort(
                                      (left, right) => right.fetchedAt
                                          .compareTo(left.fetchedAt),
                                    );
                              final marketEvidence = _marketEvidence(
                                dataset,
                                marketStates,
                              );
                              final latestMarketTimestamp = marketStates
                                  .fold<int>(
                                    0,
                                    (latest, state) => state.fetchedAt > latest
                                        ? state.fetchedAt
                                        : latest,
                                  );
                              final needs = _plannerNeedsFor(modeController);
                              final plannerNeedGroups = _plannerNeedGroups();
                              final target = plan.target.trim();
                              return BdoResourceMap(
                                dataset: dataset,
                                workerEconomics: data.workerEconomics,
                                lodgingDataset: data.lodging,
                                cacheDirectory: _cacheDirectory(),
                                tileSource: widget.configuration.tileSource,
                                tileHttpClient:
                                    widget.configuration.tileHttpClient,
                                showSourceNotice:
                                    widget.configuration.showSourceNotice,
                                plannerNeeds: needs,
                                plannerNeedGroups: plannerNeedGroups,
                                favoriteResourceIds: favoriteResourceIds,
                                onFavoriteResourceIdsChanged: widget
                                    .appController
                                    .setResourceMapFavoriteIds,
                                gatherChecklist: gatherChecklist,
                                onGatherChecklistChanged: widget
                                    .appController
                                    .setResourceMapGatherChecklist,
                                nodeNetworkPreferences: nodeNetworkPreferences,
                                setupScreenshotPicker: widget.screenshotPicker,
                                setupScreenshotClipboardReader:
                                    widget.screenshotClipboardReader,
                                activeNodeRecordingLauncher:
                                    widget.activeNodeRecordingLauncher,
                                activeNodeRecordingFinder:
                                    widget.activeNodeRecordingFinder,
                                activeNodeRecordingPicker:
                                    widget.activeNodeRecordingPicker,
                                activeNodeRecordingScanner:
                                    widget.activeNodeRecordingScanner,
                                onNodeNetworkPreferencesChanged: widget
                                    .appController
                                    .setResourceMapNodeNetworkPreferences,
                                marketOutputEvidenceByResourceId:
                                    marketEvidence,
                                marketNetRate: marketNetRate(
                                  widget.appController.marketTax.value,
                                ),
                                marketRegion: market.region,
                                marketFetchedAt: latestMarketTimestamp > 0
                                    ? DateTime.fromMillisecondsSinceEpoch(
                                        latestMarketTimestamp,
                                        isUtc: true,
                                      )
                                    : null,
                                onRefreshMarketEvidence:
                                    widget.onRefreshMarketEvidence,
                                controller: widget.controller,
                                plannerContextLabel: target.isEmpty
                                    ? '${mode.label} plan'
                                    : '${mode.label} · $target',
                                resourceIconBuilder:
                                    (context, resource, size) => ModeItemIcon(
                                      controller: modeController,
                                      name: resource.name,
                                      size: size,
                                      catalogRepository:
                                          widget.catalogRepository,
                                      searchAcrossModes: true,
                                      fallbackIcon: _fallbackIconFor(resource),
                                      showFrame: false,
                                    ),
                                workerOutputIconBuilder:
                                    (context, resource, size) => ModeItemIcon(
                                      controller: modeController,
                                      name: resource.name,
                                      size: size,
                                      catalogRepository:
                                          widget.catalogRepository,
                                      searchAcrossModes: true,
                                      fallbackIcon:
                                          Icons.image_not_supported_outlined,
                                      showFrame: false,
                                    ),
                                vendorItemIconBuilder:
                                    (context, itemName, size) => ModeItemIcon(
                                      controller: modeController,
                                      name: itemName,
                                      size: size,
                                      catalogRepository:
                                          widget.catalogRepository,
                                      searchAcrossModes: true,
                                      fallbackIcon: Icons.inventory_2_outlined,
                                      showFrame: false,
                                    ),
                                vendorPortraitBuilder: (context, vendor, size) {
                                  final assetPath =
                                      bdoBundledVendorPortraitAsset(
                                        vendor.sourceVendorId,
                                      );
                                  final fallback = Icon(
                                    Icons.person_rounded,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: size,
                                  );
                                  if (assetPath == null) {
                                    return fallback;
                                  }
                                  return Image.asset(
                                    assetPath,
                                    width: size,
                                    height: size,
                                    alignment: Alignment.bottomCenter,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (context, error, stack) =>
                                        fallback,
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  List<BdoPlannerMaterialNeed> _plannerNeedsFor(
    ModeFeatureController modeController,
  ) {
    final market = modeController.state.value.market;
    final fetchedAt = market.fetchedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(market.fetchedAt, isUtc: true)
        : null;
    return modeController.plan.value.missing
        .map((material) {
          final source = modeController.resolveItemSource(material.name);
          final acquisition = modeController.resolveItemAcquisition(
            material.name,
          );
          final Iterable<ItemAcquisitionRoute> reviewedRoutes =
              acquisition != null &&
                  acquisition.status.trim().toLowerCase() == 'reviewed'
              ? acquisition.routes.where((route) => route.isDisplayable)
              : const <ItemAcquisitionRoute>[];
          return BdoPlannerMaterialNeed(
            gameItemId: _marketItemId(modeController, material.name),
            name: material.name,
            missingQuantity: material.missing,
            marketable: material.market.marketable,
            stockKnown: material.market.stockKnown,
            stock: material.market.stock,
            marketRegion: market.region,
            marketFetchedAt: fetchedAt,
            vendorPurchaseAvailable:
                source.npcPrice > 0 ||
                reviewedRoutes.any(
                  (route) => route.kind.trim().toLowerCase() == 'npc_purchase',
                ),
            reviewedWorkerRoute: reviewedRoutes.any(
              (route) => route.kind.trim().toLowerCase() == 'worker_node',
            ),
          );
        })
        .toList(growable: false);
  }

  List<BdoPlannerNeedGroup> _plannerNeedGroups() {
    const groupedModes = <CraftMode>[CraftMode.cooking, CraftMode.alchemy];
    final groups = <BdoPlannerNeedGroup>[];
    for (final mode in groupedModes) {
      final needs = _plannerNeedsFor(widget.appController.modes[mode]!);
      if (needs.isEmpty) {
        continue;
      }
      groups.add(_plannerNeedGroup(mode: mode, needs: needs));
    }
    return List<BdoPlannerNeedGroup>.unmodifiable(groups);
  }

  BdoPlannerNeedGroup _plannerNeedGroup({
    required CraftMode mode,
    required List<BdoPlannerMaterialNeed> needs,
  }) {
    final baseIdCounts = <String, int>{};
    for (final need in needs) {
      final baseId = _plannerMaterialBaseId(need);
      baseIdCounts[baseId] = (baseIdCounts[baseId] ?? 0) + 1;
    }

    final usedIds = <String>{};
    final materials = <BdoPlannerNeedMaterial>[];
    for (final need in needs) {
      final baseId = _plannerMaterialBaseId(need);
      final materialId = baseIdCounts[baseId] == 1
          ? baseId
          : '$baseId/name:${Uri.encodeComponent(need.name.trim())}';
      if (!usedIds.add(materialId)) {
        throw StateError(
          'The ${mode.label} plan returned duplicate material identity '
          '"$materialId".',
        );
      }
      materials.add(
        BdoPlannerNeedMaterial(
          id: materialId,
          need: need,
          selectedByDefault: !need.vendorPurchaseAvailable,
        ),
      );
    }
    return BdoPlannerNeedGroup(
      id: mode.name,
      label: mode.label,
      materials: materials,
    );
  }

  String _plannerMaterialBaseId(BdoPlannerMaterialNeed need) {
    final gameItemId = need.gameItemId;
    return gameItemId == null
        ? 'name:${normalizeMarketName(need.name)}'
        : 'item:$gameItemId';
  }

  int? _marketItemId(
    ModeFeatureController modeController,
    String materialName,
  ) {
    final recipeMarketId = modeController
        .recipeDefinition(materialName)
        ?.marketId
        ?.trim();
    final bundledMarketId = widget.catalogRepository
        .bundledMarketId(materialName)
        ?.trim();
    return int.tryParse(
      recipeMarketId != null && recipeMarketId.isNotEmpty
          ? recipeMarketId
          : bundledMarketId ?? '',
    );
  }

  Map<String, MarketValueOutputInput> _marketEvidence(
    BdoResourceMapDataset dataset,
    List<MarketState> marketStates,
  ) {
    final prices = <String, double>{};
    final stock = <String, double>{};
    final tradeEvidenceByState =
        <Map<String, ({double dailyTrades, double observationHours})>>[];
    final listingStatus = <String, bool>{};
    for (final state in marketStates) {
      for (final name in state.unlistedItemNames) {
        listingStatus.putIfAbsent(normalizeMarketName(name), () => false);
      }
      for (final entry in state.prices.entries) {
        final key = normalizeMarketName(entry.key);
        prices.putIfAbsent(key, () => entry.value);
        listingStatus.putIfAbsent(key, () => true);
      }
      for (final entry in state.stock.entries) {
        final key = normalizeMarketName(entry.key);
        stock.putIfAbsent(key, () => entry.value);
        listingStatus.putIfAbsent(key, () => true);
      }
      final normalizedObservationHours = <String, double>{
        for (final entry in state.tradeObservationHours.entries)
          normalizeMarketName(entry.key): entry.value,
      };
      final stateTradeEvidence =
          <String, ({double dailyTrades, double observationHours})>{};
      for (final entry in state.observedDailyTrades.entries) {
        final key = normalizeMarketName(entry.key);
        final observationHours = normalizedObservationHours[key];
        if (observationHours != null) {
          stateTradeEvidence[key] = (
            dailyTrades: entry.value,
            observationHours: observationHours,
          );
        }
      }
      tradeEvidenceByState.add(stateTradeEvidence);
    }

    final result = <String, MarketValueOutputInput>{};
    for (final node in dataset.workerNodes.where(
      (candidate) => candidate.isResourceNode,
    )) {
      for (final output in node.outputs) {
        final resource = dataset.resourcesById[output.resourceId];
        final names = <String>[
          output.name,
          if (resource != null) resource.name,
          ...?resource?.aliases,
        ];
        double? price;
        double? listed;
        double? dailyTrades;
        double? observationHours;
        bool? isListed;
        for (final name in names) {
          final key = normalizeMarketName(name);
          price ??= prices[key];
          listed ??= stock[key];
          isListed ??= listingStatus[key];
          if (dailyTrades == null && observationHours == null) {
            for (final stateTradeEvidence in tradeEvidenceByState) {
              final evidence = stateTradeEvidence[key];
              if (evidence != null) {
                dailyTrades = evidence.dailyTrades;
                observationHours = evidence.observationHours;
                break;
              }
            }
          }
        }
        final unlisted = isListed == false;
        final gameItemId = output.gameItemId ?? resource?.gameItemId;
        final marketId = widget.catalogRepository.bundledMarketId(
          output.name,
          aliases: names.skip(1),
        );
        result.putIfAbsent(
          output.resourceId,
          () => resolveWorkerOutputMarketEvidence(
            resourceId: output.resourceId,
            outputName: output.name,
            gameItemId: gameItemId,
            explicitlyUnlisted: unlisted,
            hasBundledMarketId: marketId != null,
            currentUnitPrice: price,
            listedStock: listed?.round(),
            observedDailyTradeVolume: dailyTrades,
            tradeObservationHours: observationHours,
          ),
        );
      }
    }
    return Map<String, MarketValueOutputInput>.unmodifiable(result);
  }

  IconData _fallbackIconFor(BdoResourceDefinition resource) =>
      switch (resource.section) {
        BdoResourceSection.plantsWood => Icons.park_rounded,
        BdoResourceSection.oresMinerals => Icons.diamond_outlined,
        BdoResourceSection.meat => Icons.restaurant_rounded,
        BdoResourceSection.bloodHides => Icons.water_drop_outlined,
        BdoResourceSection.mushrooms => Icons.spa_outlined,
        BdoResourceSection.seafoodMarine => Icons.set_meal_rounded,
        BdoResourceSection.other => Icons.inventory_2_outlined,
      };

  Directory _cacheDirectory() {
    final configured = widget.configuration.cacheDirectory;
    if (configured != null) {
      return configured;
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.trim().isNotEmpty) {
      return Directory(
        _join(_join(local, AppIdentity.localCacheDirectoryName), 'Map Cache'),
      );
    }
    return Directory(
      _join(widget.fallbackApplicationDirectory.path, 'Map Cache'),
    );
  }
}

class _ResourceMapWorkspaceData {
  const _ResourceMapWorkspaceData({
    required this.map,
    required this.workerEconomics,
    required this.lodging,
  });

  final BdoResourceMapDataset map;
  final BdoWorkerEconomicsDataset workerEconomics;
  final LodgingDataset lodging;
}

class _ResourceMapLoading extends StatelessWidget {
  const _ResourceMapLoading();

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return ColoredBox(
      key: const ValueKey<String>('resource-map-loading-surface'),
      color: chrome.canvas,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: chrome.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Indexing materials and worker nodes…',
              style: TextStyle(color: chrome.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceMapLoadFailure extends StatelessWidget {
  const _ResourceMapLoadFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return ColoredBox(
      key: const ValueKey<String>('resource-map-load-failure-surface'),
      color: chrome.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            key: const ValueKey<String>('resource-map-load-failure-card'),
            decoration: BoxDecoration(
              gradient: chrome.surfaceGradient,
              borderRadius: BorderRadius.circular(chrome.surfaceRadius),
              border: Border.all(color: chrome.warmOutline),
              boxShadow: chrome.surfaceShadows,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.map_outlined, color: chrome.error, size: 42),
                  const SizedBox(height: 14),
                  Text(
                    'The resource map could not open its dataset.',
                    textAlign: TextAlign.center,
                    style: chrome.headingStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: chrome.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: chrome.primary,
                      foregroundColor: chrome.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          chrome.controlRadius,
                        ),
                      ),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _join(String first, String second) {
  if (first.endsWith(Platform.pathSeparator)) {
    return '$first$second';
  }
  return '$first${Platform.pathSeparator}$second';
}
