import 'dart:async';

import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_identity.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/icons/custom_icon_store.dart';
import '../../data/market/market_price_service.dart';
import '../../data/market/package_http_market_transport.dart';
import '../../data/persistence/personal_data_location_service.dart';
import '../../data/portable/portable_custom_icon_bridge.dart';
import '../../domain/market/market_price_gateway.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';
import '../../features/about/about.dart';
import '../../features/appearance/appearance.dart';
import '../../features/data/data.dart';
import '../../features/editor/editor.dart';
import '../../features/inventory/inventory.dart';
import '../../features/planner/planner.dart';
import '../../features/recipe_book/recipe_book.dart';
import '../../features/resource_map/resource_map_theme_adapter.dart';
import '../../features/resource_map/resource_map_workspace.dart';
import '../../features/shared/custom_icon_store_scope.dart';
import '../../features/shell/shell.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../shared/overlays/draggable_overlay_surface.dart';
import '../../visual/visual.dart';
import '../application_bootstrap.dart';
import '../market/market_refresh_coordinator.dart';
import '../state/planner_application_controller.dart';
import '../update/beta_update.dart';
import '../update/beta_update_indicator.dart';
import '../update/beta_update_process_service.dart';
import '../window/app_title_bar.dart';
import '../window/native_active_node_video_service.dart';
import '../window/native_clipboard_image_reader.dart';
import '../window/native_file_dialog_service.dart';
import '../window/native_still_image_ocr_service.dart';
import '../window/window_host_service.dart';
import 'application_copy_toast.dart';

enum _TopWorkspaceDestination { planner, resourceMap }

class ApplicationWorkspace extends StatefulWidget {
  const ApplicationWorkspace({
    required this.bundle,
    this.marketGateway,
    this.windowHost = const WindowHostService(),
    this.fileDialogs = const NativeFileDialogService(),
    this.resourceMapConfiguration = const ResourceMapWorkspaceConfiguration(),
    this.updateService,
    this.updateSource,
    this.enableBetaUpdates = AppIdentity.outOfProcessBetaUpdatesEnabled,
    super.key,
  });

  static const Key contentClipKey = ValueKey<String>(
    'application-workspace-content-clip',
  );

  final ApplicationBundle bundle;
  final MarketPriceGateway? marketGateway;
  final WindowHostService windowHost;
  final NativeFileDialogService fileDialogs;
  final ResourceMapWorkspaceConfiguration resourceMapConfiguration;
  final BetaUpdateService? updateService;
  final String? updateSource;
  final bool enableBetaUpdates;

  @override
  State<ApplicationWorkspace> createState() => _ApplicationWorkspaceState();
}

Map<String, List<PlannerMarketRowDiagnostic>> mapPlannerMarketRowDiagnostics(
  Iterable<MarketRefreshDiagnostic> diagnostics,
) {
  final result = <String, List<PlannerMarketRowDiagnostic>>{};
  for (final diagnostic in diagnostics) {
    if (diagnostic.code == MarketRefreshDiagnosticCode.duplicateMaterialName) {
      continue;
    }
    final names = diagnostic.relatedMaterialNames.isNotEmpty
        ? diagnostic.relatedMaterialNames
        : diagnostic.materialName == null
        ? const <String>[]
        : <String>[diagnostic.materialName!];
    if (names.isEmpty) continue;
    final item = PlannerMarketRowDiagnostic(
      message: diagnostic.message,
      severity: switch (diagnostic.code) {
        MarketRefreshDiagnosticCode.duplicateMaterialName ||
        MarketRefreshDiagnosticCode.duplicateMarketId ||
        MarketRefreshDiagnosticCode.marketUnlisted =>
          PlannerMarketDiagnosticSeverity.info,
        MarketRefreshDiagnosticCode.rowFailure =>
          PlannerMarketDiagnosticSeverity.error,
        _ => PlannerMarketDiagnosticSeverity.warning,
      },
      isMarketUnlisted:
          diagnostic.code == MarketRefreshDiagnosticCode.marketUnlisted,
    );
    for (final name in names) {
      final key = name.trim().toLowerCase();
      if (key.isEmpty) continue;
      final entries = result.putIfAbsent(
        key,
        () => <PlannerMarketRowDiagnostic>[],
      );
      if (!entries.any((entry) => entry.message == item.message)) {
        entries.add(item);
      }
    }
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<PlannerMarketRowDiagnostic>.unmodifiable(entry.value),
  });
}

PlannerMapLookupAvailability resolvePlannerMapLookupAvailability(
  BdoResourceMapDataset dataset,
  String materialName,
) {
  final normalizedName = _normalizeMapLookupText(materialName);
  final vendorListings = dataset.vendorListingsForItem(materialName);
  final listedVendorIds = vendorListings
      .map((listing) => listing.vendorId)
      .toSet();
  final mappedVendorCount = dataset
      .vendorNpcsForItem(materialName)
      .where((vendor) => listedVendorIds.contains(vendor.id))
      .map((vendor) => vendor.id)
      .toSet()
      .length;
  final matchingResourceIds = <String>{};
  if (normalizedName.isNotEmpty) {
    for (final resource in dataset.resources) {
      if (<String>[
        resource.id,
        resource.name,
        ...resource.aliases,
      ].any((value) => _normalizeMapLookupText(value) == normalizedName)) {
        matchingResourceIds.add(resource.id);
      }
    }
    for (final node in dataset.workerNodes.where(
      (node) => node.isResourceNode,
    )) {
      for (final output in node.outputs) {
        if (_normalizeMapLookupText(output.resourceId) == normalizedName ||
            _normalizeMapLookupText(output.name) == normalizedName) {
          matchingResourceIds.add(output.resourceId);
        }
      }
    }
  }

  final manualIds =
      matchingResourceIds
          .where(
            (resourceId) =>
                dataset.hasMappedManualSource(resourceId) ||
                dataset.fieldSourcesForResource(resourceId).isNotEmpty,
          )
          .toList()
        ..sort();
  final workerIds = matchingResourceIds.where(dataset.hasWorkerSource).toList()
    ..sort();
  final manualLocationCount = manualIds.toSet().fold<int>(0, (total, id) {
    final fieldSources = dataset.fieldSourcesForResource(id).toList();
    final pointIds = <String>{
      ...dataset.gatheringPointsForResource(id).map((point) => point.id),
      for (final source in fieldSources)
        ...dataset
            .gatheringPointsForFieldSource(source.id)
            .map((point) => point.id),
    };
    final spotIds = <String>{
      ...dataset.gatheringSpotsForResource(id).map((spot) => spot.id),
      for (final source in fieldSources)
        ...dataset
            .gatheringSpotsForFieldSource(source.id)
            .map((spot) => spot.id),
    };
    final routeIds = dataset
        .gatheringRoutesForResource(id)
        .map((route) => route.id)
        .toSet();
    return total + pointIds.length + spotIds.length + routeIds.length;
  });
  final workerNodeCount = workerIds
      .expand(dataset.workerNodesForResource)
      .map((node) => node.id)
      .toSet()
      .length;
  return PlannerMapLookupAvailability(
    materialName: materialName.trim(),
    hasNpcVendors: mappedVendorCount > 0,
    npcVendorCount: mappedVendorCount,
    hasManualGathering: manualIds.isNotEmpty,
    manualResourceId: manualIds.length == 1 ? manualIds.single : null,
    manualLocationCount: manualLocationCount,
    hasWorkerNodes: workerIds.isNotEmpty,
    workerResourceId: workerIds.length == 1 ? workerIds.single : null,
    workerNodeCount: workerNodeCount,
  );
}

String _normalizeMapLookupText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _ApplicationWorkspaceState extends State<ApplicationWorkspace>
    with WidgetsBindingObserver {
  static const int _maximumMapScreenshotBytes = 40 * 1024 * 1024;
  static const NativeActiveNodeVideoService _activeNodeVideoService =
      NativeActiveNodeVideoService();
  static const NativeStillImageOcrService _stillImageOcrService =
      NativeStillImageOcrService();

  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final Map<CraftMode, GlobalKey> _modeKeys = <CraftMode, GlobalKey>{
    for (final mode in CraftMode.values) mode: GlobalKey(),
  };
  final Set<CraftMode> _visitedModes = <CraftMode>{};
  final Map<CraftMode, Widget> _modeWorkspaces = <CraftMode, Widget>{};

  late final CatalogRepository _catalogRepository;
  late final MarketRefreshCoordinator _marketCoordinator;
  late final PackageHttpMarketTransport? _ownedMarketTransport;
  late final InventorySessionController _inventorySessions;
  late final RecipeEditorSessionController _editorSessions;
  late final DataSessionController _dataSession;
  late final CustomIconStore _iconStore;
  late final PortableCustomIconBridge _iconBridge;
  late final BdoResourceMapController _resourceMapController;
  late final ResourceMapDatasetCache _resourceMapDatasetCache;
  late final PlannerExternalActions _plannerActions;
  late final InventoryExternalActions _inventoryActions;
  InventoryScreenshotRecognizer? _inventoryScreenshotRecognizer;
  late final EditorExternalActions _editorActions;
  late final BetaUpdateService _updateService;
  late final BetaUpdateController _updateController;
  late final bool _ownsUpdateService;
  bool _retryingSave = false;
  bool _oneClickUpdatePending = false;
  bool _restartAndApplyPending = false;
  bool _personalDataMovePending = false;
  bool _personalDataRestartRequired = false;
  bool _personalDataCloseRetryPending = false;
  bool _personalDataCloseIssued = false;
  String? _personalDataRestartError;
  bool _updateInsetVisible = false;
  Timer? _copyToastTimer;
  String _copyToastText = '';
  _TopWorkspaceDestination _topWorkspace = _TopWorkspaceDestination.planner;
  Widget? _resourceMapWorkspace;

  PlannerApplicationController get _controller => widget.bundle.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalogRepository = CatalogRepository(widget.bundle.catalog);
    final MarketPriceGateway gateway;
    if (widget.marketGateway case final supplied?) {
      _ownedMarketTransport = null;
      gateway = supplied;
    } else {
      final transport = PackageHttpMarketTransport();
      _ownedMarketTransport = transport;
      gateway = MarketPriceService(transport: transport);
    }
    _marketCoordinator = MarketRefreshCoordinator(
      gateway: gateway,
      catalogRepository: _catalogRepository,
    );
    _inventorySessions = InventorySessionController();
    _editorSessions = RecipeEditorSessionController();
    _dataSession = DataSessionController();
    _iconStore = CustomIconStore(
      applicationDirectory:
          widget.bundle.stateRepository.paths.applicationDirectory,
    );
    _iconBridge = PortableCustomIconBridge(iconStore: _iconStore);
    _resourceMapController = BdoResourceMapController();
    _resourceMapDatasetCache = ResourceMapDatasetCache();
    _plannerActions = PlannerExternalActions(
      openRecipeBook: _openRecipeBook,
      copyName: _copyName,
      checkPrices: _checkPrices,
      resolveMapLookup: _resolvePlannerMapLookup,
      openMapLookup: _openPlannerMapLookup,
      addToGatherChecklist: _addPlannerMaterialToGatherChecklist,
      addToPlannedNetwork: _addPlannerMaterialToPlannedNetwork,
      copyAfkLoad: _copyAfkLoad,
      openAfkWeightSettings: _openAfkWeightSettings,
    );
    _inventoryActions = InventoryExternalActions(
      confirmClear: _confirmInventoryClear,
      confirmDelete: _confirmInventoryDelete,
      copyName: _copyName,
      reportTransaction: (notice) => _showToast(notice.message),
      offerUndo: _offerInventoryUndo,
      reportUndo: (result) =>
          _showToast(result.message, error: !result.restored),
      pasteScreenshot: _pasteInventoryScreenshot,
      chooseScreenshot: _chooseInventoryScreenshot,
    );
    _editorActions = EditorExternalActions(
      // The running Avalonia editor deletes immediately and does not surface a
      // success toast or undo prompt. Keep the safer transaction machinery in
      // the feature layer, but match that observable production workflow here.
      confirmDelete: (_) async => true,
      reportTransaction: (_) {},
      offerUndo: (_) {},
      reportUndo: (_) {},
    );
    final resolvedUpdateSource =
        widget.updateSource ?? BetaUpdateSource.resolve();
    _ownsUpdateService = widget.updateService == null;
    _updateService =
        widget.updateService ??
        (widget.enableBetaUpdates
            ? ProcessBetaUpdateService(source: resolvedUpdateSource)
            : const PausedBetaUpdateService());
    _updateController = BetaUpdateController(
      service: _updateService,
      source: resolvedUpdateSource,
      enabled: widget.enableBetaUpdates,
    );
    _updateController.addListener(_updateVisibilityChanged);
    _visitedModes.add(_controller.activeMode.value);
    _controller.activeMode.addListener(_activeModeChanged);
    _controller.saveError.addListener(_saveErrorChanged);
    widget.windowHost.installCloseRequestHandler(_flushBeforeClose);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStartupNotices();
      if (widget.enableBetaUpdates) {
        unawaited(_updateController.checkOnce());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      unawaited(_controller.flush());
    }
  }

  void _activeModeChanged() {
    if (!mounted) return;
    for (final key in _modeKeys.values) {
      (key.currentState as _ModeWorkspaceState?)?.closeRecipeBook();
    }
    setState(() => _visitedModes.add(_controller.activeMode.value));
  }

  void _saveErrorChanged() {
    final error = _controller.saveError.value;
    if (!mounted || error == null || _retryingSave) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.saveError.value != error) return;
      _showSaveError(error);
    });
  }

  void _showSaveError(String error) {
    _showToast(
      'Planner state could not be written to disk. No success has been assumed. $error',
      error: true,
      actionLabel: 'Retry',
      onAction: () => unawaited(_retryPendingSave()),
    );
  }

  Future<void> _retryPendingSave() async {
    if (_retryingSave) return;
    _retryingSave = true;
    try {
      await _controller.flush();
      if (!mounted) return;
      if (_controller.saveError.value case final error?) {
        _showSaveError(error);
      } else {
        _showToast('Planner state is safely synchronized to disk.');
      }
    } finally {
      _retryingSave = false;
    }
  }

  Future<void> _flushBeforeClose() async {
    if (_personalDataMovePending) {
      throw StateError(
        'Wait for the personal-data move to finish before closing the app.',
      );
    }
    await _flushStateForRestart();
  }

  Future<void> _flushStateForRestart() async {
    await _controller.flush();
    if (_controller.saveError.value case final error?) {
      throw StateError('The planner state could not be saved: $error');
    }
  }

  void _updateVisibilityChanged() {
    final visible = _updateController.snapshot.showsIndicator;
    if (visible == _updateInsetVisible) return;
    _updateInsetVisible = visible;
    unawaited(
      widget.windowHost.setBottomInset(
        visible ? BetaUpdateIndicator.height : 0,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _copyToastTimer?.cancel();
    widget.windowHost.removeCloseRequestHandler();
    _controller.activeMode.removeListener(_activeModeChanged);
    _controller.saveError.removeListener(_saveErrorChanged);
    _inventorySessions.dispose();
    _editorSessions.dispose();
    _dataSession.dispose();
    _iconStore.dispose();
    _resourceMapController.dispose();
    _updateController.removeListener(_updateVisibilityChanged);
    if (_updateInsetVisible) {
      unawaited(widget.windowHost.setBottomInset(0));
    }
    _updateController.dispose();
    if (_ownsUpdateService) unawaited(_updateService.dispose());
    _ownedMarketTransport?.close();
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _controller.activeMode.value;
    final appearance = _controller.active.state.value.appearance;
    final spec = RetainedThemeRegistry.resolve(
      backgroundId: appearance.background,
    );
    final restartPending = _restartAndApplyPending || _personalDataMovePending;
    return AppOverlayCoordinatorHost(
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ExcludeFocus(
                excluding: restartPending,
                child: AbsorbPointer(
                  absorbing: restartPending,
                  child: Column(
                    children: <Widget>[
                      _ApplicationTitleStrip(
                        controller: _controller,
                        windowHost: widget.windowHost,
                        beforeClose: _flushBeforeClose,
                        activeWorkspace: _topWorkspace,
                        onWorkspaceChanged: _setTopWorkspace,
                        onCloseError: (error) => _showToast(
                          'Close canceled because the latest state could not be saved. $error',
                          error: true,
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Offstage(
                              offstage:
                                  _topWorkspace !=
                                  _TopWorkspaceDestination.planner,
                              child: ExcludeFocus(
                                excluding:
                                    _topWorkspace ==
                                    _TopWorkspaceDestination.resourceMap,
                                child: TickerMode(
                                  enabled:
                                      _topWorkspace ==
                                      _TopWorkspaceDestination.planner,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                      for (final mode in CraftMode.values)
                                        if (_visitedModes.contains(mode))
                                          Offstage(
                                            offstage: mode != active,
                                            child: TickerMode(
                                              enabled: mode == active,
                                              child: _modeWorkspaceFor(mode),
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_resourceMapWorkspace != null)
                              Offstage(
                                offstage:
                                    _topWorkspace !=
                                    _TopWorkspaceDestination.resourceMap,
                                child: ExcludeFocus(
                                  excluding:
                                      _topWorkspace ==
                                      _TopWorkspaceDestination.planner,
                                  child: TickerMode(
                                    enabled:
                                        _topWorkspace ==
                                        _TopWorkspaceDestination.resourceMap,
                                    child: ClipRect(
                                      key: ApplicationWorkspace.contentClipKey,
                                      clipBehavior: Clip.hardEdge,
                                      child: ResourceMapThemeBinding(
                                        controller: _controller,
                                        child: _resourceMapWorkspace!,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _ApplicationUpdateStrip(
                        controller: _controller,
                        updateController: _updateController,
                        onUpdateNow: _updateNow,
                      ),
                    ],
                  ),
                ),
              ),
              if (_copyToastText.isNotEmpty)
                Positioned.fill(
                  child: ApplicationCopyToastOverlay(
                    message: _copyToastText,
                    spec: spec,
                    standardSettings: StandardVisualSettings(
                      backgroundId: appearance.background,
                      accentHue: appearance.accentHue,
                      rainbow: appearance.rainbow,
                      neon: appearance.neon,
                    ),
                  ),
                ),
              if (_personalDataRestartRequired)
                Positioned.fill(
                  child: BlockSemantics(
                    child: _PersonalDataRestartOverlay(
                      closePending: _personalDataCloseRetryPending,
                      closeIssued: _personalDataCloseIssued,
                      error: _personalDataRestartError,
                      onRetryClose: _retryPersonalDataClose,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeWorkspaceFor(CraftMode mode) => _modeWorkspaces.putIfAbsent(
    mode,
    () => _ModeWorkspace(
      key: _modeKeys[mode],
      appController: _controller,
      modeController: _controller.modes[mode]!,
      catalogRepository: _catalogRepository,
      plannerActions: _plannerActions,
      inventoryActions: _inventoryActions,
      editorActions: _editorActions,
      inventorySessions: _inventorySessions,
      editorSessions: _editorSessions,
      dataSession: _dataSession,
      personalDataPath:
          widget.bundle.personalDataLocation.applicationDirectory.path,
      onMovePersonalData: widget.bundle.personalDataLocation.moveSupported
          ? _movePersonalData
          : null,
      onTestUpdate: AppIdentity.developerUpdateTestEnabled
          ? _showTestUpdate
          : null,
      fileDialogs: widget.fileDialogs,
      iconStore: _iconStore,
      iconBridge: _iconBridge,
    ),
  );

  Future<Uint8List?> _pickResourceMapScreenshot() async {
    final path = await widget.fileDialogs.pickImageToOpen();
    if (path == null) {
      return null;
    }
    final file = File(path);
    final byteLength = await file.length();
    if (byteLength > _maximumMapScreenshotBytes) {
      throw const FormatException(
        'That screenshot is larger than 40 MB. Crop it to one map region or '
        'town and try again.',
      );
    }
    return file.readAsBytes();
  }

  Future<Uint8List?> _pasteResourceMapScreenshot() =>
      const NativeClipboardImageReader().readPng();

  Future<InventoryScreenshotAnalysis?> _pasteInventoryScreenshot() async {
    final bytes = await const NativeClipboardImageReader().readPng();
    if (bytes == null) return null;
    final ocr = await _stillImageOcrService.scanPngBytes(bytes);
    return _analyzeInventoryScreenshot(bytes, ocr);
  }

  Future<InventoryScreenshotAnalysis?> _chooseInventoryScreenshot() async {
    final path = await widget.fileDialogs.pickImageToOpen();
    if (path == null) return null;
    final file = File(path);
    final byteLength = await file.length();
    if (byteLength > _maximumMapScreenshotBytes) {
      throw const FormatException(
        'That screenshot is larger than 40 MB. Crop it to the storage or '
        'inventory window and try again.',
      );
    }
    final bytes = await file.readAsBytes();
    final ocr = await _stillImageOcrService.scanPath(path);
    return _analyzeInventoryScreenshot(bytes, ocr);
  }

  InventoryScreenshotAnalysis _analyzeInventoryScreenshot(
    Uint8List bytes,
    StillImageOcrResult ocr,
  ) {
    final recognizer = _inventoryScreenshotRecognizer ??=
        InventoryScreenshotRecognizer.fromCatalog(widget.bundle.catalog);
    return InventoryScreenshotAnalysis(
      screenshotPng: bytes,
      draft: recognizer.recognize(screenshotPng: bytes, ocr: ocr),
    );
  }

  Future<String?> _pickActiveNodeRecording() =>
      widget.fileDialogs.pickVideoToOpen();

  void _setTopWorkspace(_TopWorkspaceDestination destination) {
    if (_topWorkspace == destination) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _topWorkspace = destination;
      if (destination == _TopWorkspaceDestination.resourceMap) {
        _resourceMapWorkspace ??= ResourceMapWorkspace(
          fallbackApplicationDirectory:
              widget.bundle.stateRepository.paths.applicationDirectory,
          appController: _controller,
          catalogRepository: _catalogRepository,
          configuration: widget.resourceMapConfiguration,
          controller: _resourceMapController,
          datasetCache: _resourceMapDatasetCache,
          screenshotPicker: _pickResourceMapScreenshot,
          screenshotClipboardReader: _pasteResourceMapScreenshot,
          activeNodeRecordingLauncher:
              _activeNodeVideoService.launchRectangleRecording,
          activeNodeRecordingFinder: (modifiedAfter) => _activeNodeVideoService
              .findLatestRecording(modifiedAfter: modifiedAfter),
          activeNodeRecordingPicker: _pickActiveNodeRecording,
          activeNodeRecordingScanner: _activeNodeVideoService.scanRecording,
          onRefreshMarketEvidence: _refreshResourceMapMarketEvidence,
        );
      }
    });
  }

  Future<PlannerMapLookupAvailability> _resolvePlannerMapLookup(
    String materialName,
  ) async {
    try {
      final dataset = await _resourceMapDatasetCache.load();
      return resolvePlannerMapLookupAvailability(dataset, materialName);
    } on Object catch (error) {
      _resourceMapDatasetCache.invalidate();
      if (mounted) {
        _showToast(
          'Map sources could not be checked. Please try again. $error',
          error: true,
        );
      }
      return PlannerMapLookupAvailability(materialName: materialName);
    }
  }

  void _openPlannerMapLookup(PlannerMapLookupRequest request) {
    final materialName = request.materialName.trim();
    if (materialName.isEmpty) return;
    _resourceMapController.focus(
      BdoResourceMapFocusRequest(
        materialName: materialName,
        resourceId: request.resourceId,
        source: switch (request.source) {
          PlannerMapLookupSource.npcVendors =>
            BdoResourceMapFocusSource.npcVendors,
          PlannerMapLookupSource.manualGathering =>
            BdoResourceMapFocusSource.manualGathering,
          PlannerMapLookupSource.workerNodes =>
            BdoResourceMapFocusSource.workerNodePlanner,
        },
      ),
    );
    _setTopWorkspace(_TopWorkspaceDestination.resourceMap);
  }

  void _addPlannerMaterialToGatherChecklist(
    PlannerMapLookupAvailability availability,
  ) {
    final resourceId =
        availability.manualResourceId ?? availability.workerResourceId;
    if (resourceId == null) {
      _showToast(
        'This material matches more than one mapped source. Open the map and '
        'choose the exact material first.',
        error: true,
      );
      return;
    }
    final current = _controller.resourceMapGatherChecklist.value;
    final alreadyIncluded = current.contains(resourceId);
    final next = current.addResource(
      resourceId: resourceId,
      displayName: availability.materialName,
      sourceKind: availability.manualResourceId != null
          ? BdoGatherChecklistSourceKind.manualGathering
          : BdoGatherChecklistSourceKind.workerNode,
    );
    _controller.setResourceMapGatherChecklist(next);
    _showToast(
      alreadyIncluded
          ? '${availability.materialName} is already in the gather checklist.'
          : '${availability.materialName} added to the gather checklist.',
    );
  }

  void _addPlannerMaterialToPlannedNetwork(
    PlannerMapLookupAvailability availability,
  ) {
    final resourceId = availability.workerResourceId;
    if (resourceId == null) {
      _showToast(
        'This material matches more than one worker resource. Open the map '
        'and choose the exact material first.',
        error: true,
      );
      return;
    }
    final current = _controller.resourceMapNodeNetworkPreferences.value;
    final currentCount = current.desiredResourceNodeCounts[resourceId] ?? 0;
    final plannedCount = currentCount > 0 ? currentCount : 1;
    final desiredCounts = <String, int>{
      ...current.desiredResourceNodeCounts,
      resourceId: plannedCount,
    };
    _controller.setResourceMapNodeNetworkPreferences(
      current.copyWith(desiredResourceNodeCounts: desiredCounts),
    );
    final focusRequest = BdoResourceMapFocusRequest(
      materialName: availability.materialName,
      resourceId: resourceId,
      source: BdoResourceMapFocusSource.workerNodePlanner,
    );
    _setTopWorkspace(_TopWorkspaceDestination.resourceMap);
    // Let the map receive the newly persisted preferences before opening the
    // target editor. Otherwise an already mounted offstage map could briefly
    // reuse its previous local count and lower a larger saved target.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resourceMapController.focus(focusRequest);
      }
    });
    final nodeLabel = plannedCount == 1 ? 'node' : 'nodes';
    _showToast(
      currentCount > 0
          ? '${availability.materialName} is already planned for '
                '$plannedCount $nodeLabel.'
          : '${availability.materialName} added to your planned network '
                '(1 node).',
    );
  }

  Future<String> _refreshResourceMapMarketEvidence(
    Set<String> outputNames,
  ) async {
    final mode = _controller.activeMode.value;
    final modeController = _controller.modes[mode]!;
    final result = await _marketCoordinator.refresh(
      mode: mode,
      assembledRecipes: modeController.recipes,
      currentMarket: modeController.state.value.market,
      missingMaterialNames: outputNames,
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
      unlistedItemNames: result.market.unlistedItemNames,
      fetchedAt: result.fetchedAt,
      region: result.market.region,
    );
    return result.summary.message;
  }

  BuildContext? _modeContext(CraftMode mode) =>
      (_modeKeys[mode]?.currentState as _ModeWorkspaceState?)?.dialogContext;

  void _openRecipeBook(RecipeBookRequest request) {
    final state = _modeKeys[request.controller.mode]?.currentState;
    if (state is! _ModeWorkspaceState) {
      _showToast(
        'Recipe Book could not open. Switch modes and try again.',
        error: true,
      );
      return;
    }
    state.openRecipeBook(request);
  }

  Future<void> _copyName(String exactName) async {
    try {
      await Clipboard.setData(ClipboardData(text: exactName));
      _showCopyToast(exactName);
    } on Object catch (error) {
      _showToast(
        '“$exactName” could not be copied because the Windows clipboard is unavailable. $error',
        error: true,
      );
    }
  }

  Future<void> _copyAfkLoad(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _showToast('AFK load list copied.');
    } on Object catch (error) {
      _showToast(
        'The AFK load list could not be copied because the Windows clipboard '
        'is unavailable. $error',
        error: true,
      );
    }
  }

  void _openAfkWeightSettings() {
    _dataSession.showAfkWeightSettings();
    _setTopWorkspace(_TopWorkspaceDestination.planner);
    _controller.active.navigate('data');
  }

  void _showCopyToast(String exactName) {
    _copyToastTimer?.cancel();
    if (!mounted) return;
    setState(() => _copyToastText = 'Copied $exactName');
    _copyToastTimer = Timer(const Duration(milliseconds: 1350), () {
      _copyToastTimer = null;
      if (!mounted) return;
      setState(() => _copyToastText = '');
    });
  }

  Future<PlannerMarketRefresh> _checkPrices(
    PlannerMarketRequest request,
  ) async {
    final result = await _marketCoordinator.refresh(
      mode: request.controller.mode,
      assembledRecipes: request.controller.recipes,
      currentMarket: request.controller.state.value.market,
      missingMaterialNames: request.namesForRefresh,
    );
    return PlannerMarketRefresh(
      prices: result.prices,
      stock: result.stock,
      unlistedItemNames: result.market.unlistedItemNames,
      fetchedAt: result.fetchedAt,
      summary: result.summary.message,
      region: result.market.region,
      tradeMarketIds: result.tradeMarketIds,
      totalTrades: result.totalTrades,
      tradeObservedAt: result.tradeObservedAt,
      observedDailyTrades: result.observedDailyTrades,
      tradeObservationHours: result.tradeObservationHours,
      lastSoldAtEpochSeconds: result.lastSoldAtEpochSeconds,
      rowDiagnostics: mapPlannerMarketRowDiagnostics(result.diagnostics),
    );
  }

  Future<bool> _confirmInventoryClear(
    InventoryClearRequest request,
  ) => _confirm(
    mode: request.mode,
    title: 'Clear Inventory',
    message:
        'Remove all ${request.entryCount} saved inventory entries for ${request.mode.label}?',
    actionLabel: 'Clear',
  );

  Future<bool> _confirmInventoryDelete(
    InventoryDeleteRequest request,
  ) => _confirm(
    mode: request.mode,
    title: '${request.actionLabel} Item',
    message: request.bundledItem
        ? 'Hide “${request.itemName}” from ${request.mode.label}? It can be restored from Craft Profile.'
        : 'Delete the custom item “${request.itemName}” and its owned values?',
    actionLabel: request.actionLabel,
  );

  Future<bool> _confirm({
    required CraftMode mode,
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final context = _modeContext(mode);
    if (context == null) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => DraggableModalRouteSurface(
            overlayId: 'inventory-confirm:${mode.key}:$title',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppSurface(
                role: AppSurfaceRole.modal,
                tone: AppSurfaceTone.warning,
                semanticLabel: title,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DraggableOverlayDragRegion(
                      key: const ValueKey<String>('inventory-confirm-drag'),
                      child: SectionHeader(title: title),
                    ),
                    const SizedBox(height: 12),
                    Text(message),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        AppButton.label(
                          'Cancel',
                          autofocus: true,
                          onPressed: () => Navigator.pop(dialogContext, false),
                        ),
                        const SizedBox(width: 8),
                        AppButton.label(
                          actionLabel,
                          role: AppButtonRole.danger,
                          onPressed: () => Navigator.pop(dialogContext, true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  void _offerInventoryUndo(InventoryUndoOffer offer) {
    _showToast(
      offer.message,
      actionLabel: 'Undo',
      onAction: () => unawaited(offer.undo()),
    );
  }

  void _showStartupNotices() {
    final notices = <String>[
      ...widget.bundle.stateLoad.notices,
      ...widget.bundle.startupNotices,
    ];
    if (!mounted || notices.isEmpty) return;
    _showToast(notices.join(' '));
  }

  Future<void> _updateNow() async {
    if (_oneClickUpdatePending ||
        _updateController.operationPending ||
        _personalDataMovePending) {
      return;
    }
    _oneClickUpdatePending = true;
    try {
      if (_updateController.snapshot.testOnly) {
        final completed = await _updateController.runTestUpdateDemo();
        if (mounted && completed) {
          _showToast(
            'Update test complete. Real updates use this same bar and install automatically.',
          );
        }
        return;
      }
      switch (_updateController.snapshot.phase) {
        case BetaUpdatePhase.available:
          await _updateController.download();
          if (_updateController.snapshot.phase == BetaUpdatePhase.ready) {
            await _restartAndApplyUpdate();
          } else if (_updateController.snapshot.phase ==
                  BetaUpdatePhase.offline ||
              _updateController.snapshot.phase == BetaUpdatePhase.error) {
            _showToast(
              _updateController.snapshot.message.isEmpty
                  ? 'The update could not be downloaded. Please try again later.'
                  : _updateController.snapshot.message,
              error: true,
            );
          }
          return;
        case BetaUpdatePhase.ready:
          await _restartAndApplyUpdate();
          return;
        default:
          return;
      }
    } finally {
      _oneClickUpdatePending = false;
    }
  }

  void _showTestUpdate() {
    final shown = _updateController.showTestUpdate(
      currentVersion: AppIdentity.applicationVersion,
    );
    _showToast(
      shown
          ? 'Test update shown. Click the bottom bar to run the safe demo.'
          : 'A real update is already active. Finish it before testing the bar.',
      error: !shown,
    );
  }

  Future<void> _restartAndApplyUpdate() async {
    if (_restartAndApplyPending || _personalDataMovePending) return;
    setState(() => _restartAndApplyPending = true);
    var closeIssued = false;
    var mutationsFrozen = false;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      // Focus-loss commits are delivered with the next frame. Keep input
      // absorbed while those final drafts enter the document, then freeze the
      // mutation surface before the durable restart flush.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _controller.freezeMutationsForRestart();
      mutationsFrozen = true;
      await _flushStateForRestart();
      final prepared = await _updateController.prepareRestart();
      if (!mounted) return;
      if (!prepared) {
        _showToast(
          _updateController.snapshot.message.isEmpty
              ? 'The update could not be prepared. Black Spirit Life remains open.'
              : _updateController.snapshot.message,
          error: true,
        );
        return;
      }
      await widget.windowHost.close();
      closeIssued = true;
    } on Object catch (error) {
      if (!mounted) return;
      _showToast(
        'Restart canceled because the latest planner state or update could not be prepared. $error',
        error: true,
      );
    } finally {
      if (!closeIssued) {
        if (mutationsFrozen) {
          _controller.resumeMutationsAfterRestartFailure();
        }
        if (mounted) {
          setState(() => _restartAndApplyPending = false);
        } else {
          _restartAndApplyPending = false;
        }
      }
    }
  }

  Future<void> _movePersonalData(String destinationPath) async {
    if (_personalDataMovePending ||
        _restartAndApplyPending ||
        _updateController.operationPending ||
        _dataSession.profileIoBusy) {
      throw StateError(
        'Finish the current update, restart, import, or export before moving personal data.',
      );
    }
    setState(() => _personalDataMovePending = true);
    var closeIssued = false;
    var mutationsFrozen = false;
    var locationSwitched = false;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _controller.freezeMutationsForRestart();
      mutationsFrozen = true;
      await _flushStateForRestart();
      final result = await widget.bundle.personalDataLocation.moveTo(
        destinationPath,
      );
      locationSwitched = true;
      if (result.cleanupPending) {
        _showToast(
          'The new personal-data folder is verified. Old-folder cleanup will finish at the next start.',
        );
      }
      closeIssued = await _closeAfterPersonalDataMove();
    } on PersonalDataMoveException catch (error) {
      locationSwitched = error.locationSwitched;
      if (locationSwitched) {
        closeIssued = await _closeAfterPersonalDataMove();
        return;
      }
      rethrow;
    } finally {
      if (!closeIssued && !locationSwitched) {
        if (mutationsFrozen) {
          _controller.resumeMutationsAfterRestartFailure();
        }
        if (mounted) {
          setState(() => _personalDataMovePending = false);
        } else {
          _personalDataMovePending = false;
        }
      }
    }
  }

  Future<bool> _closeAfterPersonalDataMove() async {
    try {
      await widget.windowHost.close();
      return true;
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _personalDataRestartRequired = true;
          _personalDataCloseIssued = false;
          _personalDataRestartError = '$error';
        });
      }
      return false;
    }
  }

  Future<void> _retryPersonalDataClose() async {
    if (_personalDataCloseRetryPending || _personalDataCloseIssued) return;
    setState(() {
      _personalDataCloseRetryPending = true;
      _personalDataRestartError = null;
    });
    try {
      await widget.windowHost.close();
      if (!mounted) return;
      setState(() {
        _personalDataCloseIssued = true;
        _personalDataCloseRetryPending = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _personalDataCloseRetryPending = false;
        _personalDataRestartError = '$error';
      });
    }
  }

  void _showToast(
    String message, {
    bool error = false,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    final appearance = _controller.active.state.value.appearance;
    final spec = RetainedThemeRegistry.resolve(
      backgroundId: appearance.background,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration:
              duration ??
              (actionLabel == null
                  ? const Duration(seconds: 4)
                  : const Duration(seconds: 8)),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            280,
            0,
            24,
            20 + (_updateInsetVisible ? BetaUpdateIndicator.height : 0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          padding: EdgeInsets.zero,
          content: ThemeSpecScope(
            spec: spec,
            child: Theme(
              data: spec.materialTheme(),
              child: AppSurface(
                role: AppSurfaceRole.popup,
                tone: error ? AppSurfaceTone.danger : AppSurfaceTone.success,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                semanticLabel: error ? 'Operation error' : 'Operation status',
                child: Row(
                  children: <Widget>[
                    Icon(
                      error ? Icons.error_outline : Icons.check_circle_outline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(message)),
                    if (actionLabel != null && onAction != null) ...<Widget>[
                      const SizedBox(width: 12),
                      AppButton.label(
                        actionLabel,
                        minimumSize: const Size(72, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed: onAction,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }
}

class _PersonalDataRestartOverlay extends StatelessWidget {
  const _PersonalDataRestartOverlay({
    required this.closePending,
    required this.closeIssued,
    required this.error,
    required this.onRetryClose,
  });

  final bool closePending;
  final bool closeIssued;
  final String? error;
  final Future<void> Function() onRetryClose;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xD9000000),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppSurface(
          role: AppSurfaceRole.modal,
          semanticLabel: 'Personal data moved; restart required',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionHeader(title: 'Restart Black Spirit Life'),
              const SizedBox(height: 12),
              const Text(
                'Your personal data is safely stored in the new folder. Black Spirit Life must restart before anything else can be changed.',
              ),
              if (error case final message?) ...<Widget>[
                const SizedBox(height: 10),
                Text('The window did not close: $message'),
              ],
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton.label(
                  closeIssued
                      ? 'Closing...'
                      : closePending
                      ? 'Retrying...'
                      : 'Retry close',
                  key: const ValueKey<String>(
                    'personal-data-restart-retry-close',
                  ),
                  role: AppButtonRole.primary,
                  onPressed: null,
                  onPressedAsync: closePending || closeIssued
                      ? null
                      : onRetryClose,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ApplicationTitleStrip extends StatefulWidget {
  const _ApplicationTitleStrip({
    required this.controller,
    required this.windowHost,
    required this.beforeClose,
    required this.onCloseError,
    required this.activeWorkspace,
    required this.onWorkspaceChanged,
  });

  final PlannerApplicationController controller;
  final WindowHostService windowHost;
  final Future<void> Function() beforeClose;
  final ValueChanged<Object> onCloseError;
  final _TopWorkspaceDestination activeWorkspace;
  final ValueChanged<_TopWorkspaceDestination> onWorkspaceChanged;

  @override
  State<_ApplicationTitleStrip> createState() => _ApplicationTitleStripState();
}

class _ApplicationTitleStripState extends State<_ApplicationTitleStrip> {
  late ModeFeatureController _mode;
  late AppearanceSettings _appearance;

  @override
  void initState() {
    super.initState();
    _mode = widget.controller.active;
    _appearance = _mode.state.value.appearance;
    widget.controller.activeMode.addListener(_modeChanged);
    _mode.state.addListener(_appearanceChanged);
  }

  void _modeChanged() {
    _mode.state.removeListener(_appearanceChanged);
    _mode = widget.controller.active;
    _mode.state.addListener(_appearanceChanged);
    _appearanceChanged(force: true);
  }

  void _appearanceChanged({bool force = false}) {
    final next = _mode.state.value.appearance;
    if (!force && identical(next, _appearance)) return;
    if (mounted) setState(() => _appearance = next);
  }

  @override
  void dispose() {
    widget.controller.activeMode.removeListener(_modeChanged);
    _mode.state.removeListener(_appearanceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = RetainedThemeRegistry.resolve(
      backgroundId: _appearance.background,
    );
    return ThemeSpecScope(
      spec: spec,
      child: StandardVisualScope(
        settings: StandardVisualSettings(
          backgroundId: _appearance.background,
          accentHue: _appearance.accentHue,
          rainbow: _appearance.rainbow,
          neon: _appearance.neon,
        ),
        child: Theme(
          data: spec.materialTheme(),
          child: AppTitleBar(
            windowHost: widget.windowHost,
            beforeClose: widget.beforeClose,
            onCloseError: widget.onCloseError,
            workspaceNavigation: _WorkspaceNavigation(
              active: widget.activeWorkspace,
              onChanged: widget.onWorkspaceChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplicationUpdateStrip extends StatefulWidget {
  const _ApplicationUpdateStrip({
    required this.controller,
    required this.updateController,
    required this.onUpdateNow,
  });

  final PlannerApplicationController controller;
  final BetaUpdateController updateController;
  final Future<void> Function() onUpdateNow;

  @override
  State<_ApplicationUpdateStrip> createState() =>
      _ApplicationUpdateStripState();
}

class _ApplicationUpdateStripState extends State<_ApplicationUpdateStrip> {
  late ModeFeatureController _mode;
  late AppearanceSettings _appearance;

  @override
  void initState() {
    super.initState();
    _mode = widget.controller.active;
    _appearance = _mode.state.value.appearance;
    widget.controller.activeMode.addListener(_modeChanged);
    _mode.state.addListener(_appearanceChanged);
  }

  void _modeChanged() {
    _mode.state.removeListener(_appearanceChanged);
    _mode = widget.controller.active;
    _mode.state.addListener(_appearanceChanged);
    _appearanceChanged(force: true);
  }

  void _appearanceChanged({bool force = false}) {
    final next = _mode.state.value.appearance;
    if (!force && identical(next, _appearance)) return;
    if (mounted) setState(() => _appearance = next);
  }

  @override
  void dispose() {
    widget.controller.activeMode.removeListener(_modeChanged);
    _mode.state.removeListener(_appearanceChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = RetainedThemeRegistry.resolve(
      backgroundId: _appearance.background,
    );
    return ThemeSpecScope(
      spec: spec,
      child: StandardVisualScope(
        settings: StandardVisualSettings(
          backgroundId: _appearance.background,
          accentHue: _appearance.accentHue,
          rainbow: _appearance.rainbow,
          neon: _appearance.neon,
        ),
        child: Theme(
          data: spec.materialTheme(),
          child: BetaUpdateIndicator(
            controller: widget.updateController,
            onUpdateNow: widget.onUpdateNow,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  const _WorkspaceNavigation({required this.active, required this.onChanged});

  static const plannerKey = ValueKey<String>('top-workspace-tab-planner');
  static const resourceMapKey = ValueKey<String>(
    'top-workspace-tab-resource-map',
  );

  final _TopWorkspaceDestination active;
  final ValueChanged<_TopWorkspaceDestination> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTitleTabStrip(
      tabs: <AppTitleTab>[
        AppTitleTab(
          tabKey: plannerKey,
          artworkAssetPath: 'assets/app/bdo_tool_icon.png',
          label: 'Craft Planner',
          selected: active == _TopWorkspaceDestination.planner,
          onPressed: () => onChanged(_TopWorkspaceDestination.planner),
        ),
        AppTitleTab(
          tabKey: resourceMapKey,
          artworkAssetPath: 'assets/app/bdo_resource_map_icon.png',
          label: 'Resource Map',
          selected: active == _TopWorkspaceDestination.resourceMap,
          onPressed: () => onChanged(_TopWorkspaceDestination.resourceMap),
        ),
      ],
    );
  }
}

class _ModeWorkspace extends StatefulWidget {
  const _ModeWorkspace({
    required this.appController,
    required this.modeController,
    required this.catalogRepository,
    required this.plannerActions,
    required this.inventoryActions,
    required this.editorActions,
    required this.inventorySessions,
    required this.editorSessions,
    required this.dataSession,
    required this.personalDataPath,
    required this.onMovePersonalData,
    required this.onTestUpdate,
    required this.fileDialogs,
    required this.iconStore,
    required this.iconBridge,
    super.key,
  });

  final PlannerApplicationController appController;
  final ModeFeatureController modeController;
  final CatalogRepository catalogRepository;
  final PlannerExternalActions plannerActions;
  final InventoryExternalActions inventoryActions;
  final EditorExternalActions editorActions;
  final InventorySessionController inventorySessions;
  final RecipeEditorSessionController editorSessions;
  final DataSessionController dataSession;
  final String personalDataPath;
  final Future<void> Function(String destinationPath)? onMovePersonalData;
  final VoidCallback? onTestUpdate;
  final NativeFileDialogService fileDialogs;
  final CustomIconStore iconStore;
  final PortableCustomIconBridge iconBridge;

  @override
  State<_ModeWorkspace> createState() => _ModeWorkspaceState();
}

class _ModeWorkspaceState extends State<_ModeWorkspace> {
  final GlobalKey _dialogContextKey = GlobalKey();
  late ShellDestination _destination;
  late AppearanceSettings _appearance;
  late bool _showAdvancedDestinations;
  final Set<ShellDestination> _visited = <ShellDestination>{};
  final Map<ShellDestination, Widget> _featureWidgets =
      <ShellDestination, Widget>{};
  RecipeBookController? _recipeBook;
  String _recipeBookSearch = '';

  BuildContext? get dialogContext => _dialogContextKey.currentContext;

  @override
  void initState() {
    super.initState();
    final state = widget.modeController.state.value;
    _showAdvancedDestinations = widget.appController.deleteToolsEnabled.value;
    _destination = _destinationFor(
      state.view,
      widget.modeController.mode,
      showAdvanced: _showAdvancedDestinations,
    );
    _appearance = state.appearance;
    _visited.add(_destination);
    widget.modeController.state.addListener(_modeStateChanged);
    widget.appController.deleteToolsEnabled.addListener(
      _advancedDestinationVisibilityChanged,
    );
  }

  void _modeStateChanged() {
    final state = widget.modeController.state.value;
    final destination = _destinationFor(
      state.view,
      widget.modeController.mode,
      showAdvanced: _showAdvancedDestinations,
    );
    final appearance = state.appearance;
    if (destination == _destination && identical(appearance, _appearance)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _destination = destination;
      _appearance = appearance;
      _visited.add(destination);
    });
  }

  void _advancedDestinationVisibilityChanged() {
    final showAdvanced = widget.appController.deleteToolsEnabled.value;
    if (showAdvanced == _showAdvancedDestinations) return;
    final hiddenDestination = !showAdvanced && _destination.isAdvanced;
    if (mounted) {
      setState(() {
        _showAdvancedDestinations = showAdvanced;
        if (hiddenDestination) {
          _destination = ShellDestination.planner;
          _visited.add(_destination);
        }
      });
    } else {
      _showAdvancedDestinations = showAdvanced;
    }
    if (hiddenDestination) {
      widget.modeController.navigate('plan');
    }
  }

  @override
  void didUpdateWidget(_ModeWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.modeController, widget.modeController) ||
        !identical(oldWidget.plannerActions, widget.plannerActions) ||
        !identical(oldWidget.inventoryActions, widget.inventoryActions) ||
        !identical(oldWidget.editorActions, widget.editorActions) ||
        !identical(oldWidget.inventorySessions, widget.inventorySessions) ||
        !identical(oldWidget.editorSessions, widget.editorSessions) ||
        !identical(oldWidget.dataSession, widget.dataSession) ||
        oldWidget.onTestUpdate != widget.onTestUpdate ||
        !identical(oldWidget.fileDialogs, widget.fileDialogs) ||
        !identical(oldWidget.iconStore, widget.iconStore) ||
        !identical(oldWidget.iconBridge, widget.iconBridge)) {
      _featureWidgets.clear();
    }
    if (!identical(oldWidget.appController, widget.appController)) {
      oldWidget.appController.deleteToolsEnabled.removeListener(
        _advancedDestinationVisibilityChanged,
      );
      _showAdvancedDestinations = widget.appController.deleteToolsEnabled.value;
      widget.appController.deleteToolsEnabled.addListener(
        _advancedDestinationVisibilityChanged,
      );
    }
  }

  @override
  void dispose() {
    widget.modeController.state.removeListener(_modeStateChanged);
    widget.appController.deleteToolsEnabled.removeListener(
      _advancedDestinationVisibilityChanged,
    );
    _recipeBook?.dispose();
    super.dispose();
  }

  void openRecipeBook(RecipeBookRequest request) {
    if (request.controller != widget.modeController) return;
    if (_recipeBook case final current?) {
      _recipeBookSearch = current.search;
      current.dispose();
    }
    setState(() {
      _recipeBook = RecipeBookController(
        modeController: widget.modeController,
        catalogRepository: widget.catalogRepository,
        callingContext: request.context,
        allowedTargets: request.allowedTargets,
        initialSearch: _recipeBookSearch,
        checkPrices: widget.plannerActions.checkPrices,
      );
    });
  }

  void closeRecipeBook() {
    final controller = _recipeBook;
    if (controller == null) return;
    _recipeBookSearch = controller.search;
    _recipeBook = null;
    controller.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final spec = RetainedThemeRegistry.resolve(
      backgroundId: _appearance.background,
    );
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shell = WorkspaceShell(
      mode: widget.modeController.mode,
      destination: _destination,
      showAdvancedDestinations: _showAdvancedDestinations,
      transition: _transitionFor(_appearance),
      transitionSpeed: _transitionSpeedFor(_appearance),
      reduceMotion: reducedMotion,
      onModeChanged: (mode) {
        AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
        widget.appController.switchMode(mode);
      },
      onDestinationChanged: (destination) {
        AppOverlayCoordinatorScope.maybeOf(context)?.dismissTop();
        closeRecipeBook();
        widget.modeController.navigate(_viewFor(destination));
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final destination in ShellDestination.values)
            if (_visited.contains(destination) &&
                destination.isVisibleFor(
                  widget.modeController.mode,
                  showAdvanced: _showAdvancedDestinations,
                ))
              Offstage(
                offstage: destination != _destination,
                child: TickerMode(
                  enabled: destination == _destination,
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      '${widget.modeController.mode.key}:${destination.name}',
                    ),
                    child: _featureFor(destination),
                  ),
                ),
              ),
        ],
      ),
    );
    // Avalonia's Recipe Book is a client-area modal: it dims and spans both
    // the shell rail and the active workspace. Keep it above WorkspaceShell
    // rather than constraining it to the shell's content pane.
    final workspace = CustomIconStoreScope(
      store: widget.iconStore,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          shell,
          if (_recipeBook case final book?)
            Positioned.fill(
              child: RecipeBookModal(
                controller: book,
                externalActions: widget.plannerActions,
                onClose: closeRecipeBook,
                onActivated: (_) => closeRecipeBook(),
              ),
            ),
        ],
      ),
    );
    final effects = ButtonEffectVisualSettings(
      effect: _appearance.buttonEffect,
      intensity: _appearance.buttonEffectIntensity,
      speed: _appearance.buttonEffectSpeed,
      blur: _appearance.buttonEffectBlur,
      activeOnly: _appearance.buttonEffectActiveOnly,
      hue: _appearance.buttonEffectHue,
      rainbow: _appearance.buttonEffectRainbow,
      neon: _appearance.buttonEffectNeon,
    );
    final themedWorkspace = ButtonEffectHost(
      settings: effects,
      reduceMotion: reducedMotion,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: workspace,
      ),
    );
    final ledgerFold = _ledgerFoldFor(_destination);
    // Keep the live workspace in a stable sibling slot while the visual
    // backdrop changes. Swapping a StandardBackdrop wrapper for a
    // LedgerBackdrop wrapper used to unmount every feature and lose transient
    // state (notably Appearance's open Themes section and scroll offsets).
    final backdrop = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: switch (spec.family) {
            RetainedVisualFamily.illuminatedLedger => LedgerBackdrop(
              showCenterFold: ledgerFold.show,
              showMarginalia: false,
              centerFoldX: ledgerFold.x,
              centerFoldRatio: ledgerFold.ratio,
              centerFoldWidth: ledgerFold.width,
            ),
            RetainedVisualFamily.sakuraNightGarden =>
              const SakuraNightGardenBackdrop(),
            RetainedVisualFamily.standard => StandardBackdrop(
              backgroundId: _appearance.background,
              blurSigma: _appearance.backdropBlur * 12,
              atmosphere: StandardAtmosphere(
                reduceMotion: reducedMotion,
                settings: AtmosphereVisualSettings(
                  style: _appearance.particleStyle,
                  density: _appearance.particleDensity,
                  opacity: _appearance.particleOpacity,
                  minimumSize:
                      _appearance.particleMinSize * _appearance.particleSize,
                  maximumSize:
                      _appearance.particleMaxSize * _appearance.particleSize,
                  blur: _appearance.particleBlur,
                  speed: _appearance.motionSpeed,
                  strength: _appearance.motionIntensity,
                  hue: _appearance.particleHue,
                  customColor: _appearance.particleCustomColor,
                  rainbow: _appearance.particleRainbow,
                  neon: _appearance.particleNeon,
                  animated: _appearance.liveBackdrop,
                ),
              ),
            ),
          },
        ),
        Positioned.fill(child: themedWorkspace),
      ],
    );
    return ThemeSpecScope(
      spec: spec,
      child: StandardVisualScope(
        settings: StandardVisualSettings(
          backgroundId: _appearance.background,
          accentHue: _appearance.accentHue,
          rainbow: _appearance.rainbow,
          neon: _appearance.neon,
        ),
        child: Theme(
          data: spec.materialTheme(),
          child: Builder(
            key: _dialogContextKey,
            builder: (context) => backdrop,
          ),
        ),
      ),
    );
  }

  Widget _featureFor(ShellDestination destination) => _featureWidgets
      .putIfAbsent(destination, () => _buildFeature(destination));

  Widget _buildFeature(ShellDestination destination) => switch (destination) {
    ShellDestination.planner => PlannerView(
      controller: widget.modeController,
      externalActions: widget.plannerActions,
    ),
    ShellDestination.bonusRecipes => BonusView(
      controller: widget.modeController,
      externalActions: widget.plannerActions,
    ),
    ShellDestination.inventory => InventoryView(
      controller: widget.modeController,
      externalActions: widget.inventoryActions,
      sessionController: widget.inventorySessions,
    ),
    ShellDestination.recipeEditor => RecipeEditorView(
      controller: widget.modeController,
      externalActions: widget.editorActions,
      fileDialogs: widget.fileDialogs,
      iconStore: widget.iconStore,
      sessionController: widget.editorSessions,
    ),
    ShellDestination.appearance => AppearanceView(
      controller: widget.appController,
      modeController: widget.modeController,
    ),
    ShellDestination.data => DataView(
      controller: widget.appController,
      sessionController: widget.dataSession,
      fileDialogs: widget.fileDialogs,
      iconBridge: widget.iconBridge,
      onTestUpdate: widget.onTestUpdate,
      personalDataPath: widget.personalDataPath,
      onMovePersonalData: widget.onMovePersonalData,
    ),
    ShellDestination.about => const AboutView(),
  };
}

ShellDestination _destinationFor(
  String view,
  CraftMode mode, {
  required bool showAdvanced,
}) {
  final destination = switch (view) {
    'bonus' => ShellDestination.bonusRecipes,
    'inventory' => ShellDestination.inventory,
    'editor' => ShellDestination.recipeEditor,
    'appearance' => ShellDestination.appearance,
    'data' => ShellDestination.data,
    'about' => ShellDestination.about,
    _ => ShellDestination.planner,
  };
  return destination.isVisibleFor(mode, showAdvanced: showAdvanced)
      ? destination
      : ShellDestination.planner;
}

String _viewFor(ShellDestination destination) => switch (destination) {
  ShellDestination.planner => 'plan',
  ShellDestination.bonusRecipes => 'bonus',
  ShellDestination.inventory => 'inventory',
  ShellDestination.recipeEditor => 'editor',
  ShellDestination.appearance => 'appearance',
  ShellDestination.data => 'data',
  ShellDestination.about => 'about',
};

ShellContentTransition _transitionFor(AppearanceSettings appearance) {
  if (!appearance.tabFade) return ShellContentTransition.off;
  return switch (appearance.tabTransition) {
    'fade' => ShellContentTransition.fade,
    'lift' => ShellContentTransition.lift,
    'off' => ShellContentTransition.off,
    _ => ShellContentTransition.slide,
  };
}

ShellContentTransitionSpeed _transitionSpeedFor(
  AppearanceSettings appearance,
) => switch (appearance.tabTransitionSpeed) {
  'slow' => ShellContentTransitionSpeed.slow,
  'fast' => ShellContentTransitionSpeed.fast,
  _ => ShellContentTransitionSpeed.normal,
};

({bool show, double? x, double ratio, double width}) _ledgerFoldFor(
  ShellDestination destination,
) => switch (destination) {
  // These are the view-specific live Avalonia Ledger coordinates. Ratio folds
  // follow responsive two-column gutters; fixed folds follow fixed-width
  // editor/inventory/data rails.
  ShellDestination.planner || ShellDestination.bonusRecipes => (
    show: true,
    x: null,
    ratio: .575,
    // Flutter's fold shader has a broader visible shoulder than Avalonia's
    // retained painter. An 18 px footprint produces the same compact seam
    // while preserving the responsive .575 page split.
    width: 18,
  ),
  ShellDestination.inventory => (show: true, x: 548, ratio: 0, width: 30),
  ShellDestination.recipeEditor => (show: true, x: 620, ratio: 0, width: 30),
  ShellDestination.appearance => (show: true, x: null, ratio: .659, width: 18),
  ShellDestination.data => (show: true, x: 649, ratio: 0, width: 24),
  ShellDestination.about => (show: false, x: null, ratio: 0, width: 0),
};
