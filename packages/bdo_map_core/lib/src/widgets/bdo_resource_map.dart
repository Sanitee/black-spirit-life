import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, compute, mapEquals, setEquals, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../checklist/gather_checklist.dart';
import '../checklist/gather_checklist_demand.dart';
import 'gather_checklist_quantity_row.dart';
import '../economics/worker_economics_data.dart';
import '../economics/worker_income_estimator.dart';
import '../economics/worker_income_portfolio.dart';
import '../engine/map_camera.dart';
import '../engine/tile_cache.dart';
import '../engine/tile_manager.dart';
import '../import/screenshot_map_import.dart';
import '../lodging/lodging_data.dart';
import '../lodging/house_use_investment_planner.dart';
import '../lodging/lodging_network_planner.dart';
import '../lodging/lodging_optimizer.dart';
import '../lodging/shop_lodging_catalog.dart';
import '../lodging/storage_house_planner.dart';
import '../lodging/town_house_investment.dart';
import '../model/map_geometry.dart';
import '../model/map_ui_opacity.dart';
import '../model/map_visual_style.dart';
import '../model/planner_material_need.dart';
import '../model/resource_map_data.dart';
import '../model/tile_source.dart';
import '../model/worker_node_unlock_guide.dart';
import '../network/market_value_recommendation.dart';
import '../network/grouped_recipe_node_recommendation.dart';
import '../network/node_network_models.dart';
import '../network/node_network_optimizer.dart';
import '../network/node_network_preferences.dart';
import '../network/production_node_path_cost.dart';
import '../network/raw_sale_lodging_budget_planner.dart';
import '../network/raw_sale_network_planner.dart';
import '../network/recipe_node_recommendation.dart';
import '../network/worker_capacity_assessment.dart';
import '../royal_workshop/royal_workshop_goods_loader.dart';
import '../royal_workshop/royal_workshop_models.dart';
import 'bdo_map_symbols.dart';
import 'active_node_recording_import_dialog.dart';
import 'camera_flow_overlay.dart';
import 'draggable_dialog_surface.dart';
import 'gathering_tool_icon.dart';
import 'map_canvas.dart';
import 'network_cp_breakdown.dart';
import 'network_cp_review.dart';
import 'readable_select_controls.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_annotation_clip.dart';
import 'resource_map_atlas_shell.dart';
import 'resource_map_discovery_home.dart';
import 'resource_map_field_desk.dart';
import 'resource_map_controller.dart';
import 'resource_map_desktop_shell.dart';
import 'resource_map_menu_artwork.dart';
import 'resource_map_panel_metrics.dart';
import 'resource_map_pill.dart';
import 'resource_map_node_quick_panel.dart';
import 'resource_map_steward_menu.dart';
import 'resource_map_zoom_dock.dart';
import 'royal_workshop_manager.dart';
import 'shop_lodging_setup_dialog.dart';
import 'town_shop_lodging_dialog.dart';
import 'town_house_panel.dart';
import 'setup_screenshot_import_dialog.dart';
import 'worker_activity_style.dart';

const double _resourceMapCompactBreakpoint = 700;
const double _desktopContextAvoidanceWidth = 340;
const double _desktopNetworkWorkbenchMaximumWidth = 520;
const double _desktopNetworkWorkbenchMinimumWidth = 400;
const double _compactDetailsBottom = 46;
const double _compactDetailsMaximumHeight = 310;
const double _minimumCompactFitBand = 112;
const double _minimumGatheringFocusWorldSpan = 8000;
const double _gatheringFocusMaximumZoom = 7.45;
const double _workerOutputArtworkMinimumZoom = 2.2;
const double _maximumOverlayWheelZoomStep = 0.75;
const Size _houseMapMarkerSize = Size.square(30);
const Offset _houseMapMarkerOffset = Offset(-16, -17);
const Size _houseClusterMarkerSize = Size(42, 40);
const Offset _houseClusterMarkerOffset = Offset(-18, -18);
const double _houseMarkerClearance = 4;
const double _townMarkerMinimumZoom = 3.15;
const double _nodeHubMarkerMinimumZoom = 4.55;
const double _allNodeLabelMinimumZoom = 5.45;
const int _maximumWorkerOutputArtwork = 34;
const Map<int, int> _featuredExactResourcePriority = <int, int>{
  821255: 0, // Rusalka's Coral
  5420: 1, // Truffle Mushroom
  5601: 2, // Insectivore Plant Powder
  5020: 3, // Thuja Sap
  5538: 4, // Delotia
  5526: 5, // Violet Flower
  5517: 6, // Volcanic Umbrella Mushroom
  7922: 7, // Snake Meat
};

const List<_BloodFamilyDefinition> _bloodFamilyDefinitions =
    <_BloodFamilyDefinition>[
      _BloodFamilyDefinition(
        id: 'blood-group-1',
        label: 'Blood Group 1',
        members: <_BloodFamilyMember>[
          _BloodFamilyMember(name: 'Wolf Blood', gameItemId: 6214),
          _BloodFamilyMember(name: 'Flamingo Blood', gameItemId: 6218),
          _BloodFamilyMember(name: 'Rhino Blood', gameItemId: 6204),
          _BloodFamilyMember(name: 'Cheetah Dragon Blood', gameItemId: 6216),
        ],
      ),
      _BloodFamilyDefinition(
        id: 'blood-group-2',
        label: 'Blood Group 2',
        members: <_BloodFamilyMember>[
          _BloodFamilyMember(name: 'Pig Blood', gameItemId: 6205),
          _BloodFamilyMember(name: 'Deer Blood', gameItemId: 6201),
          _BloodFamilyMember(name: 'Sheep Blood', gameItemId: 6202),
          _BloodFamilyMember(name: 'Ox Blood', gameItemId: 6206),
          _BloodFamilyMember(name: 'Waragon Blood', gameItemId: 6215),
          _BloodFamilyMember(name: 'Llama Blood', gameItemId: 6227),
          _BloodFamilyMember(name: 'Goat Blood', gameItemId: 6228),
        ],
      ),
      _BloodFamilyDefinition(
        id: 'blood-group-3',
        label: 'Blood Group 3',
        members: <_BloodFamilyMember>[
          _BloodFamilyMember(name: 'Fox Blood', gameItemId: 6203),
          _BloodFamilyMember(name: 'Weasel Blood', gameItemId: 6212),
          _BloodFamilyMember(name: 'Raccoon Blood', gameItemId: 6210),
          _BloodFamilyMember(name: 'Scorpion Blood', gameItemId: 6224),
          _BloodFamilyMember(name: 'Marmot Blood', gameItemId: 6226),
        ],
      ),
      _BloodFamilyDefinition(
        id: 'blood-group-4',
        label: 'Blood Group 4',
        members: <_BloodFamilyMember>[
          _BloodFamilyMember(name: 'Bear Blood', gameItemId: 6213),
          _BloodFamilyMember(name: 'Troll Blood', gameItemId: 6220),
          _BloodFamilyMember(name: 'Ogre Blood', gameItemId: 6221),
          _BloodFamilyMember(name: 'Lion Blood', gameItemId: 6223),
          _BloodFamilyMember(name: 'Yak Blood', gameItemId: 6225),
        ],
      ),
      _BloodFamilyDefinition(
        id: 'blood-group-5',
        label: 'Blood Group 5',
        members: <_BloodFamilyMember>[
          _BloodFamilyMember(name: 'Lizard Blood', gameItemId: 6208),
          _BloodFamilyMember(name: 'Worm Blood', gameItemId: 6209),
          _BloodFamilyMember(name: 'Bat Blood', gameItemId: 6219),
          _BloodFamilyMember(name: 'Kuku Bird Blood', gameItemId: 6217),
          _BloodFamilyMember(name: 'Cobra Blood', gameItemId: 6222),
        ],
      ),
    ];

enum _MaterialSourceFilter { all, manual, worker }

enum _MapSearchScope { all, items, wildlife, plantsAndTrees, nodesAndTowns }

enum _DesktopMapMode { gather, workers }

enum _HouseUsageFilter { all, lodging, storage, stable, workshops }

enum _NodeNetworkPlannerPage { home, editCurrent, targets, review, marketValue }

enum _NodeTargetView { all, selected, current, favorites }

enum _MarketValueMenuAction {
  highestBasket,
  perMinimumCp,
  perAddedCp,
  stockCompetition,
  partialPrices,
}

enum _NodeTargetGroup {
  woodSap,
  cropsPlants,
  oresMinerals,
  fishMarine,
  mushrooms,
  animalProducts,
  other,
}

typedef BdoResourceIconBuilder =
    Widget Function(
      BuildContext context,
      BdoResourceDefinition resource,
      double size,
    );
typedef BdoItemIconBuilder =
    Widget Function(BuildContext context, String itemName, double size);
typedef BdoVendorPortraitBuilder =
    Widget Function(BuildContext context, BdoVendorNpc vendor, double size);
typedef BdoLocationGuideImageBuilder =
    Widget Function(
      BuildContext context,
      BdoLocationGuideImage image,
      BoxFit fit,
    );
typedef BdoMarketEvidenceRefresh =
    Future<String> Function(Set<String> outputNames);

class BdoResourceMap extends StatefulWidget {
  const BdoResourceMap({
    super.key,
    required this.dataset,
    required this.cacheDirectory,
    this.workerEconomics,
    this.lodgingDataset,
    this.tileSource = BdoTileSource.workermanCommunity,
    this.showSourceNotice = true,
    this.tileHttpClient,
    this.plannerNeeds = const <BdoPlannerMaterialNeed>[],
    this.plannerNeedGroups = const <BdoPlannerNeedGroup>[],
    this.plannerContextLabel,
    this.resourceIconBuilder,
    this.workerOutputIconBuilder,
    this.vendorItemIconBuilder,
    this.vendorPortraitBuilder,
    this.locationGuideImageBuilder,
    this.interfaceStyle = ResourceMapInterfaceStyle.glassDock,
    this.onInterfaceStyleChanged,
    this.uiOpacity = ResourceMapUiOpacity.defaultValue,
    this.uiOpacityListenable,
    this.onUiOpacityChanged,
    this.onUiOpacityChangeEnd,
    this.favoriteResourceIds = const <String>{},
    this.onFavoriteResourceIdsChanged,
    this.gatherChecklist,
    this.onGatherChecklistChanged,
    this.gatherChecklistQuantities = const {},
    this.onRecordGathered,
    this.nodeNetworkPreferences,
    this.onNodeNetworkPreferencesChanged,
    this.marketOutputEvidenceByResourceId =
        const <String, MarketValueOutputInput>{},
    this.marketNetRate = .65,
    this.marketRegion = '',
    this.marketFetchedAt,
    this.onRefreshMarketEvidence,
    this.showSetupScreenshotImport = false,
    this.setupScreenshotPicker,
    this.setupScreenshotClipboardReader,
    this.activeNodeRecordingLauncher,
    this.activeNodeRecordingFinder,
    this.activeNodeRecordingPicker,
    this.activeNodeRecordingScanner,
    this.controller,
    this.debugOnSelectedHouseSnapshotBuilt,
    this.recipeWorkerBuilder,
    this.recipeWorkerPlan,
    this.recipeWorkerTitle,
    this.recipePlanArtwork,
    this.onRecipeWorkerBack,
  });

  final BdoResourceMapDataset dataset;
  final Widget Function(BuildContext, VoidCallback, ValueChanged<String>)?
  recipeWorkerBuilder;
  final BdoNodeNetworkPlan? recipeWorkerPlan;
  final String? recipeWorkerTitle;
  final Widget? recipePlanArtwork;
  final bool Function()? onRecipeWorkerBack;
  final BdoWorkerEconomicsDataset? workerEconomics;
  final LodgingDataset? lodgingDataset;
  final Directory cacheDirectory;
  final BdoTileSource tileSource;

  /// Shows the public attribution and correction-route notice.
  final bool showSourceNotice;
  final http.Client? tileHttpClient;
  final List<BdoPlannerMaterialNeed> plannerNeeds;
  final List<BdoPlannerNeedGroup> plannerNeedGroups;
  final String? plannerContextLabel;
  final BdoResourceIconBuilder? resourceIconBuilder;
  final BdoResourceIconBuilder? workerOutputIconBuilder;
  final BdoItemIconBuilder? vendorItemIconBuilder;
  final BdoVendorPortraitBuilder? vendorPortraitBuilder;
  final BdoLocationGuideImageBuilder? locationGuideImageBuilder;
  final ResourceMapInterfaceStyle interfaceStyle;
  final ValueChanged<ResourceMapInterfaceStyle>? onInterfaceStyleChanged;
  final double uiOpacity;
  final ValueListenable<double>? uiOpacityListenable;
  final ValueChanged<double>? onUiOpacityChanged;
  final ValueChanged<double>? onUiOpacityChangeEnd;

  /// Existing material IDs plus [BdoSearchResult.favoriteKey] for map entries.
  /// The legacy field name keeps profile and integration compatibility.
  final Set<String> favoriteResourceIds;
  final ValueChanged<Set<String>>? onFavoriteResourceIdsChanged;
  final BdoGatherChecklist? gatherChecklist;
  final ValueChanged<BdoGatherChecklist>? onGatherChecklistChanged;
  final Map<String, BdoGatherChecklistQuantity> gatherChecklistQuantities;
  final BdoRecordGathered? onRecordGathered;
  final BdoNodeNetworkPreferences? nodeNetworkPreferences;
  final ValueChanged<BdoNodeNetworkPreferences>?
  onNodeNetworkPreferencesChanged;
  final Map<String, MarketValueOutputInput> marketOutputEvidenceByResourceId;
  final double marketNetRate;
  final String marketRegion;
  final DateTime? marketFetchedAt;
  final BdoMarketEvidenceRefresh? onRefreshMarketEvidence;

  /// Keeps the experimental screenshot/recording importer out of the normal
  /// map UI until it is ready to return.
  final bool showSetupScreenshotImport;
  final Future<Uint8List?> Function()? setupScreenshotPicker;
  final Future<Uint8List?> Function()? setupScreenshotClipboardReader;
  final BdoActiveNodeRecordingLauncher? activeNodeRecordingLauncher;
  final BdoActiveNodeRecordingFinder? activeNodeRecordingFinder;
  final BdoActiveNodeRecordingPicker? activeNodeRecordingPicker;
  final BdoActiveNodeRecordingScanner? activeNodeRecordingScanner;
  final BdoResourceMapController? controller;

  /// Reports construction of the selected-house detail snapshot in tests.
  ///
  /// Camera-only changes must move the retained snapshot without invoking this
  /// callback. Ordinary housing state changes still rebuild it as expected.
  @visibleForTesting
  final VoidCallback? debugOnSelectedHouseSnapshotBuilt;

  @override
  State<BdoResourceMap> createState() => _BdoResourceMapState();
}

class _BdoResourceMapState extends State<BdoResourceMap> {
  double? _lastBuiltOpacity;
  double get _compactDetailsBottomInset =>
      _compactDetailsBottom + (widget.onUiOpacityChanged == null ? 0 : 48);

  late BdoMapCameraController _cameraController;
  late BdoTileManager _tileManager;
  late final TextEditingController _searchController;
  late final TextEditingController _nodeTargetSearchController;
  late final TextEditingController _nodeBudgetController;
  late final ScrollController _detailsScrollController;
  late final FocusNode _searchFocus;
  late final FocusNode _mapKeyboardFocus;
  late final FocusNode _detailsKeyboardFocus;

  Size _viewport = Size.zero;
  bool _compactLayout = false;
  bool _initialViewportFitted = false;
  List<BdoSearchResult> _searchResults = const <BdoSearchResult>[];
  bool _searchResultsVisible = false;
  bool _desktopSheetExpanded = false;
  bool _materialCatalogOpen = false;
  bool _desktopTaskSurfaceCollapsed = false;
  ResourceMapWorkerMenuSection? _workerMenuSection;
  ResourceMapWorkerMenuSection? _gatherMenuSection;
  bool _showWorkerNodes = true;
  bool _showGathering = true;
  bool _showRoutes = true;
  bool _showConnections = false;
  bool _layersMenuOpen = false;
  bool _browseAllWorkerNodes = false;
  bool _housingDirectoryOpen = false;
  bool _investNodeMode = false;
  bool _royalWorkshopOpen = false;
  bool _gatherChecklistOpen = false;
  bool _gatherPlanShortlistOpen = false;
  String? _expandedGatherBloodFamilyId;
  bool _nodeNetworkPlannerOpen = false;
  _NodeNetworkPlannerPage _nodeNetworkPlannerPage =
      _NodeNetworkPlannerPage.home;
  _NodeNetworkPlannerPage _nodeNetworkReviewOrigin =
      _NodeNetworkPlannerPage.targets;
  Set<String> _currentNodeDraftIds = <String>{};
  _NodeTargetView _nodeTargetView = _NodeTargetView.all;
  bool _nodeTargetSettingsExpanded = false;
  late BdoNodeNetworkPreferences _nodeNetworkPreferences;
  BdoNodeNetworkResult? _nodeNetworkResult;
  BdoRecipeNodeRecommendation? _recipeNodeRecommendation;
  MarketValueRecommendationResult? _marketValueRecommendation;
  BdoWorkerIncomeResult? _workerIncomeRecommendation;
  BdoWorkerIncomeResult? _rawSaleNetworkIncome;
  BdoWorkerIncomePortfolioResult? _rawSalePortfolioSummary;
  BdoWorkerCapacityAssessmentResult? _rawSaleWorkerCapacity;
  BdoLodgingNetworkPlanningResult? _rawSaleLodgingPlan;
  BdoWorkerCapacityAssessmentResult? _nodeNetworkWorkerCapacity;
  BdoLodgingNetworkPlanningResult? _nodeNetworkLodgingPlan;
  BdoRawSaleNetworkPlanResult? _rawSaleNetworkPlan;
  Map<String, BdoProductionNodePathResult> _marketValuePaths =
      const <String, BdoProductionNodePathResult>{};
  BdoProductionNodePath? _selectedMarketValuePath;
  BdoProductionNodePath? _selectedQuickNodePath;
  bool _nodeQuickPanelOpen = false;
  bool _marketValueDetailsExpanded = false;
  bool _workerLodgingDetailsExpanded = false;
  MarketValueRankingBasis _marketValueRankingBasis =
      MarketValueRankingBasis.netUnitBasketValuePerIncrementalContributionPoint;
  BdoWorkerIncomeRankingBasis _workerIncomeRankingBasis =
      BdoWorkerIncomeRankingBasis.netSilverPerAddedContributionPointHour;
  bool _marketValueUseStockCompetition = false;
  bool _marketValueAllowPartialPrices = false;
  int _marketValueOverBudgetCount = 0;
  String? _marketValueMessage;
  bool _marketValueRefreshing = false;
  bool _marketValueCalculating = false;
  int _marketValueCalculationGeneration = 0;
  String? _nodeNetworkInputError;
  String? _nodeNetworkCalculationError;
  String? _nodeNetworkSaveMessage;
  Future<BdoNodeNetworkWorker>? _nodeNetworkWorkerFuture;
  bool _nodeNetworkCalculating = false;
  int _nodeNetworkCalculationGeneration = 0;
  Timer? _nodeTargetPreviewDebounce;
  BdoNodeNetworkResult? _nodeTargetPreviewResult;
  BdoLodgingNetworkPlanningResult? _nodeTargetPreviewLodgingPlan;
  bool _nodeTargetPreviewCalculating = false;
  int _nodeTargetPreviewGeneration = 0;
  final Set<_NodeTargetGroup> _expandedNodeTargetGroups = <_NodeTargetGroup>{
    _NodeTargetGroup.woodSap,
  };
  bool _workerOverviewSelectionMade = false;
  BdoWorkerActivity? _workerActivityFilter;
  _MaterialSourceFilter _materialSourceFilter = _MaterialSourceFilter.all;
  _MapSearchScope _mapSearchScope = _MapSearchScope.all;
  BdoResourceSection? _selectedResourceSection;
  bool _browseFavorites = false;
  late Set<String> _favoriteResourceIds;
  late BdoGatherChecklist _gatherChecklist;
  late BdoPlannerNeedSelection _plannerNeedSelection;
  String? _selectedFieldSourceId;
  String? _selectedResourceId;
  String? _selectedNodeId;
  String? _selectedHouseId;
  int _houseSelectionPulseRevision = 0;
  String? _selectedSpotId;
  String? _selectedPointId;
  String? _selectedRouteId;
  Set<String> _explicitWorkerEmphasisNodeIds = <String>{};
  int _workerEmphasisRevision = 0;
  Set<String> _screenshotImportedHouseIds = <String>{};
  int _screenshotHousePulseRevision = 0;
  ({String id, String name, BdoWorldPoint location, String contextLabel})?
  _markedManager;
  String? _vendorLookupItemName;
  String? _selectedVendorId;
  List<String> _vendorClusterPickerIds = const <String>[];
  BdoMapPoint? _vendorClusterPickerAnchor;
  final List<_MapNavigationEntry> _navigationHistory = <_MapNavigationEntry>[];
  bool _showSourceNotice = false;
  bool _statusDetailsExpanded = false;
  bool _clearingCache = false;
  int? _cacheBytes;
  String? _cacheActionMessage;
  int _lastHandledFocusRevision = 0;
  _HouseUsageFilter _houseUsageFilter = _HouseUsageFilter.all;
  final Map<String, int> _lodgingWorkerTargetsByTownNodeId = <String, int>{};
  final Map<String, int> _storageSlotTargetsByTownNodeId = <String, int>{};
  final Map<String, int> _housePlannerUsageTypeByTownNodeId = <String, int>{};
  final Map<String, int> _housePlannerMinimumLevelByTownNodeId =
      <String, int>{};
  final Map<String, int> _housePlannerFacilityCountByTownNodeId =
      <String, int>{};
  String? _storagePlannerTownNodeId;
  final Map<String, List<TownHouseGoal>> _townHouseGoals = {};
  String? _townInvestmentKey;
  TownHouseInvestment? _townInvestment;
  (LodgingTown, List<TownHouseGoal>, Set<String>)? _townInvestmentRequest;
  bool _townInvestmentRunning = false;
  String? _townInvestmentError;
  bool _browseAllTownHouses = false;
  String? _dismissedPlannedLodgingSummaryTownNodeId;
  List<BdoRoyalWorkshopGood> _royalWorkshopGoods =
      const <BdoRoyalWorkshopGood>[];

  /// Royal Workshop remains preserved in the data model and source while its
  /// unfinished management experience is intentionally absent from the map.
  /// Keeping this as one policy point makes a future redesign reversible
  /// without letting hidden preferences affect ordinary worker calculations.
  bool get _royalWorkshopEnabled => false;

  bool get _royalWorkshopVisible => _royalWorkshopEnabled && _royalWorkshopOpen;

  int get _activeRoyalWorkshopReservedContributionPoints =>
      _royalWorkshopEnabled
      ? _nodeNetworkPreferences.royalWorkshopPlan.reservedContributionPoints
      : 0;

  BdoRoyalWorkshopIncomeEstimate get _activeRoyalWorkshopIncomeEstimate {
    if (!_royalWorkshopEnabled) {
      return const BdoRoyalWorkshopIncomeEstimate(
        netSilverPerOnlineHour: 0,
        includedAreaCount: 0,
        excludedRareAreaCount: 0,
        incompleteAreaCount: 0,
      );
    }
    return estimateRoyalWorkshopIncome(
      plan: _nodeNetworkPreferences.royalWorkshopPlan,
      goodsById: <int, BdoRoyalWorkshopGood>{
        for (final good in _royalWorkshopGoods) good.id: good,
      },
    );
  }

  bool get _showKnownTowns => true;
  bool get _editingCurrentNodeNetwork =>
      _nodeNetworkPlannerOpen &&
      _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent;
  bool get _showNodeHubs =>
      _showAllNodes ||
      _investNodeMode ||
      _editingCurrentNodeNetwork ||
      _visibleWorkerNodes.isNotEmpty;
  bool get _showAllNodes => _nodeNetworkPreferences.showAllMapNodes;
  bool get _showAllNetworkConnections =>
      _investNodeMode ||
      _editingCurrentNodeNetwork ||
      (_showAllNodes && _nodeNetworkPreferences.showAllNodeConnections);
  bool get _showWorkerOutputArtwork =>
      (_showAllNodes && _nodeNetworkPreferences.showWorkerOutputIcons) ||
      _visibleWorkerNodes.any((node) => node.isResourceNode);

  BdoNodeNetworkPreferences _withPermanentMapDisplay(
    BdoNodeNetworkPreferences preferences,
  ) => preferences.copyWith(
    showCitiesAndTowns: true,
    showGatewayHubs: true,
    mapVisualStyle: BdoMapVisualStyle.vivid,
  );

  Set<String>? get _effectiveNetworkRootNodeIds {
    final configured = _nodeNetworkPreferences.rootNodeIds;
    if (configured != null) {
      return configured;
    }
    return widget.workerEconomics?.verifiedFreeNetworkRootNodeIds(
      widget.dataset,
    );
  }

  _DesktopMapMode? get _desktopMapMode {
    if (_nodeNetworkPlannerOpen ||
        _housingDirectoryOpen ||
        _royalWorkshopVisible ||
        _browseAllWorkerNodes ||
        _materialSourceFilter == _MaterialSourceFilter.worker) {
      return _DesktopMapMode.workers;
    }
    if (_gatherChecklistOpen ||
        _materialSourceFilter == _MaterialSourceFilter.manual) {
      return _DesktopMapMode.gather;
    }
    return null;
  }

  bool get _desktopWorkerMenuVisible =>
      !_compactLayout &&
      !_desktopTaskSurfaceCollapsed &&
      _desktopSheetExpanded &&
      _desktopMapMode == _DesktopMapMode.workers &&
      !_investNodeMode &&
      !_searchResultsVisible &&
      !_hasDetailSelection &&
      !_nodeNetworkPlannerOpen &&
      !_gatherChecklistOpen &&
      !_gatherPlanShortlistOpen &&
      !_housingDirectoryOpen &&
      !_royalWorkshopVisible &&
      !_browseAllWorkerNodes &&
      _selectedResourceSection == null &&
      !_browseFavorites;

  bool get _desktopGatherMenuVisible =>
      !_compactLayout &&
      !_desktopTaskSurfaceCollapsed &&
      _desktopSheetExpanded &&
      _desktopMapMode == _DesktopMapMode.gather &&
      !_searchResultsVisible &&
      !_hasDetailSelection &&
      !_gatherChecklistOpen &&
      !_gatherPlanShortlistOpen &&
      !_housingDirectoryOpen &&
      !_royalWorkshopVisible &&
      !_browseAllWorkerNodes &&
      _selectedResourceSection == null &&
      !_browseFavorites;

  bool get _desktopStewardMenuVisible =>
      _desktopWorkerMenuVisible || _desktopGatherMenuVisible;

  bool get _desktopContextVisible =>
      !_desktopStewardMenuVisible &&
      !_desktopNetworkWorkbenchVisible &&
      _desktopSheetExpanded &&
      (_desktopMapMode != null ||
          _searchResultsVisible ||
          _hasDetailSelection ||
          _nodeNetworkPlannerOpen ||
          _gatherChecklistOpen ||
          _gatherPlanShortlistOpen ||
          _housingDirectoryOpen ||
          _royalWorkshopVisible ||
          _browseAllWorkerNodes ||
          _selectedResourceSection != null ||
          _browseFavorites);

  bool get _desktopNetworkWorkbenchVisible =>
      !_compactLayout &&
      _nodeNetworkPlannerOpen &&
      _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.home;

  bool get _recipeWorkerPlanVisible =>
      widget.recipeWorkerBuilder != null &&
      widget.recipeWorkerPlan != null &&
      _nodeNetworkPlannerOpen &&
      _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.home;

  bool get _desktopPlannedNetworkTargetsVisible =>
      !_compactLayout &&
      _nodeNetworkPlannerOpen &&
      _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.targets &&
      !(_searchResultsVisible && _searchController.text.trim().isNotEmpty);

  bool get _gatheringLayerOwnsMapTaps {
    final editingCurrentNetwork =
        _nodeNetworkPlannerOpen &&
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent;
    final gatheringContextActive =
        _materialSourceFilter == _MaterialSourceFilter.manual ||
        _selectedFieldSourceId != null ||
        _selectedSpotId != null ||
        _selectedPointId != null ||
        _selectedRouteId != null;
    return _showGathering &&
        gatheringContextActive &&
        !_investNodeMode &&
        !editingCurrentNetwork;
  }

  double get _activeDesktopContextAvoidanceWidth =>
      _desktopPlannedNetworkTargetsVisible
      ? 500
      : _desktopContextAvoidanceWidth;

  double get _activeDesktopLeftAvoidanceWidth {
    if (!_compactLayout) {
      return 0;
    }
    if (_desktopTaskSurfaceCollapsed) {
      return 0;
    }
    if (_desktopStewardMenuVisible) {
      return MediaQuery.textScalerOf(context).scale(14) > 20 ? 400 : 340;
    }
    if (_desktopContextVisible) {
      return _activeDesktopContextAvoidanceWidth;
    }
    return 0;
  }

  double get _activeDesktopRightAvoidanceWidth {
    return 0;
  }

  // Retained for compact-layout rollback parity; the atlas now resizes the map.
  // ignore: unused_element
  double _desktopNetworkWorkbenchWidthFor(double viewportWidth) {
    if (!viewportWidth.isFinite || viewportWidth <= 0) {
      return _desktopNetworkWorkbenchMaximumWidth;
    }
    return math
        .min(
          _desktopNetworkWorkbenchMaximumWidth,
          math.max(_desktopNetworkWorkbenchMinimumWidth, viewportWidth * .42),
        )
        .toDouble();
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _nodeTargetSearchController = TextEditingController();
    _detailsScrollController = ScrollController(
      debugLabel: 'Resource-map details',
    );
    _nodeNetworkPreferences = _withPermanentMapDisplay(
      widget.nodeNetworkPreferences ?? BdoNodeNetworkPreferences(),
    );
    _nodeBudgetController = TextEditingController(
      text: '${_nodeNetworkPreferences.contributionPointBudget}',
    );
    _searchFocus = FocusNode(debugLabel: 'Resource-map search');
    _searchFocus.addListener(_handleSearchFocus);
    _mapKeyboardFocus = FocusNode(debugLabel: 'Resource-map keyboard');
    _detailsKeyboardFocus = FocusNode(
      debugLabel: 'Resource-map details keyboard',
    );
    _favoriteResourceIds = widget.favoriteResourceIds
        .where(widget.dataset.favoriteEntriesByKey.containsKey)
        .toSet();
    _gatherChecklist = widget.gatherChecklist ?? BdoGatherChecklist();
    _plannerNeedSelection = BdoPlannerNeedSelection(
      groups: widget.plannerNeedGroups,
    );
    if (_royalWorkshopEnabled) {
      unawaited(_loadRoyalWorkshopGoods());
    }
    widget.controller?.addListener(_handleExternalFocusRequest);
    _createEngine();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleExternalFocusRequest();
      }
    });
  }

  Future<void> _loadRoyalWorkshopGoods() async {
    try {
      final goods = await const BdoRoyalWorkshopGoodsLoader().load();
      if (mounted) {
        setState(() => _royalWorkshopGoods = goods);
      }
    } on Object {
      // The management surface remains usable for persisted entries, while
      // the bundled catalog verifier catches a missing asset in development.
    }
  }

  @override
  void didUpdateWidget(BdoResourceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleExternalFocusRequest);
      widget.controller?.addListener(_handleExternalFocusRequest);
      _lastHandledFocusRevision = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleExternalFocusRequest();
        }
      });
    }
    if (oldWidget.tileSource != widget.tileSource ||
        oldWidget.cacheDirectory.path != widget.cacheDirectory.path ||
        oldWidget.tileHttpClient != widget.tileHttpClient) {
      _tileManager.dispose();
      _cameraController.dispose();
      _createEngine();
      _cacheBytes = null;
      _cacheActionMessage = null;
      if (!_viewport.isEmpty) {
        final replacementCamera = _cameraController;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !identical(_cameraController, replacementCamera) ||
              _viewport.isEmpty) {
            return;
          }
          _initialViewportFitted = true;
          _fitVisibleContentOrReset();
        });
      }
    }
    if (oldWidget.dataset != widget.dataset) {
      _invalidateNodeNetworkCalculation(clearResult: true);
      _discardNodeNetworkWorker();
      _favoriteResourceIds = widget.favoriteResourceIds
          .where(widget.dataset.favoriteEntriesByKey.containsKey)
          .toSet();
      _clearSelection(resetSearch: true);
    } else if (!setEquals(
      oldWidget.favoriteResourceIds,
      widget.favoriteResourceIds,
    )) {
      _favoriteResourceIds = widget.favoriteResourceIds
          .where(widget.dataset.favoriteEntriesByKey.containsKey)
          .toSet();
    }
    final nextGatherChecklist = widget.gatherChecklist;
    if (nextGatherChecklist != null &&
        nextGatherChecklist != _gatherChecklist) {
      _gatherChecklist = nextGatherChecklist;
    }
    if (!identical(oldWidget.plannerNeedGroups, widget.plannerNeedGroups)) {
      _plannerNeedSelection = _updatedPlannerNeedSelection(
        oldGroups: oldWidget.plannerNeedGroups,
        nextGroups: widget.plannerNeedGroups,
        previousSelection: _plannerNeedSelection,
      );
    }
    final nextNetworkPreferences = _withPermanentMapDisplay(
      widget.nodeNetworkPreferences ?? _nodeNetworkPreferences,
    );
    if (!nextNetworkPreferences.sameValuesAs(_nodeNetworkPreferences)) {
      final targetsChanged = !mapEquals(
        nextNetworkPreferences.desiredResourceNodeCounts,
        _nodeNetworkPreferences.desiredResourceNodeCounts,
      );
      _nodeNetworkPreferences = nextNetworkPreferences;
      _nodeBudgetController.text =
          '${nextNetworkPreferences.contributionPointBudget}';
      if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review &&
          targetsChanged) {
        _invalidateNodeNetworkCalculation(clearResult: true);
        _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.targets;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scheduleNodeTargetPreview();
          }
        });
      } else if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review) {
        unawaited(_rebuildNodeNetworkPlan());
      } else if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.targets) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scheduleNodeTargetPreview();
          }
        });
      } else if (_nodeNetworkPlannerPage ==
          _NodeNetworkPlannerPage.marketValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue) {
            _calculateMarketValueRecommendations();
          }
        });
      }
    }
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue &&
        (!mapEquals(
              oldWidget.marketOutputEvidenceByResourceId,
              widget.marketOutputEvidenceByResourceId,
            ) ||
            oldWidget.marketNetRate != widget.marketNetRate ||
            oldWidget.marketRegion != widget.marketRegion ||
            oldWidget.marketFetchedAt != widget.marketFetchedAt)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue) {
          _calculateMarketValueRecommendations();
        }
      });
    }
  }

  void _createEngine() {
    _initialViewportFitted = false;
    final initialZoom = math
        .max(0.85, widget.tileSource.minimumZoom.toDouble())
        .clamp(
          widget.tileSource.minimumZoom.toDouble(),
          BdoMapCameraController.maximumZoomFor(widget.tileSource),
        )
        .toDouble();
    _cameraController = BdoMapCameraController(
      tileSource: widget.tileSource,
      initialCamera: BdoMapCamera(
        center: widget.tileSource.worldBounds.center,
        zoom: initialZoom,
      ),
    );
    _tileManager = BdoTileManager(
      source: widget.tileSource,
      client: widget.tileHttpClient,
      diskCache: BdoMapDiskCache(
        rootDirectory: widget.cacheDirectory,
        sourceNamespace: widget.tileSource.id,
      ),
    );
  }

  BdoPlannerNeedSelection _updatedPlannerNeedSelection({
    required List<BdoPlannerNeedGroup> oldGroups,
    required List<BdoPlannerNeedGroup> nextGroups,
    required BdoPlannerNeedSelection previousSelection,
  }) {
    final oldKeys = <BdoPlannerNeedKey>{
      for (final group in oldGroups)
        for (final material in group.materials)
          BdoPlannerNeedKey(groupId: group.id, materialId: material.id),
    };
    final selectedKeys = <BdoPlannerNeedKey>{
      ...previousSelection.selectedMaterialKeys,
      for (final group in nextGroups)
        for (final material in group.materials)
          if (material.selectedByDefault &&
              !oldKeys.contains(
                BdoPlannerNeedKey(groupId: group.id, materialId: material.id),
              ))
            BdoPlannerNeedKey(groupId: group.id, materialId: material.id),
    };
    return BdoPlannerNeedSelection(
      groups: nextGroups,
      selectedMaterialKeys: selectedKeys,
    );
  }

  @override
  void dispose() {
    _marketValueCalculationGeneration += 1;
    _invalidateNodeNetworkCalculation(clearResult: false);
    _discardNodeNetworkWorker();
    _nodeTargetPreviewDebounce?.cancel();
    _tileManager.dispose();
    _cameraController.dispose();
    _searchController.dispose();
    _nodeTargetSearchController.dispose();
    _nodeBudgetController.dispose();
    _detailsScrollController.dispose();
    widget.controller?.removeListener(_handleExternalFocusRequest);
    _searchFocus.dispose();
    _mapKeyboardFocus.dispose();
    _detailsKeyboardFocus.dispose();
    super.dispose();
  }

  void _handleSearchFocus() {
    if (_searchFocus.hasFocus && _searchController.text.trim().isNotEmpty) {
      if (_compactLayout) {
        _search(_searchController.text, showResults: true);
      } else {
        _searchWholeMap(_searchController.text, showResults: true);
      }
    }
  }

  void _handleExternalFocusRequest() {
    final controller = widget.controller;
    if (controller == null ||
        controller.revision <= _lastHandledFocusRevision) {
      return;
    }
    _lastHandledFocusRevision = controller.revision;
    final request = controller.request;
    if (request == null) {
      return;
    }
    if (request.source == BdoResourceMapFocusSource.npcVendors) {
      _focusNpcVendors(request.materialName);
      return;
    }
    final resource = _resourceForFocusRequest(request);
    if (resource == null) {
      return;
    }
    final manual = request.source == BdoResourceMapFocusSource.manualGathering;
    final applicable = manual
        ? _hasManualMapSource(resource.id)
        : widget.dataset.hasWorkerSource(resource.id);
    if (!applicable) {
      return;
    }
    if (request.source == BdoResourceMapFocusSource.workerNodePlanner) {
      _openWorkerNodePlannerForResource(resource);
      return;
    }
    _focusResourceOnMap(resource, manual: manual);
  }

  List<BdoVendorNpc> get _activeVendorNpcs {
    final itemName = _vendorLookupItemName;
    return itemName == null
        ? const <BdoVendorNpc>[]
        : widget.dataset.vendorNpcsForItem(itemName);
  }

  BdoVendorNpc? get _selectedVendor {
    final id = _selectedVendorId;
    return id == null ? null : widget.dataset.vendorNpcsById[id];
  }

  List<BdoVendorNpc> get _vendorClusterPickerVendors => _vendorClusterPickerIds
      .map((id) => widget.dataset.vendorNpcsById[id])
      .whereType<BdoVendorNpc>()
      .toList(growable: false);

  BdoVendorListing? _activeListingForVendor(String vendorId) {
    final itemName = _vendorLookupItemName;
    if (itemName == null) return null;
    final normalized = _normalizePlannerMaterialName(itemName);
    for (final listing in widget.dataset.vendorListingsForVendor(vendorId)) {
      if (_normalizePlannerMaterialName(listing.itemName) == normalized) {
        return listing;
      }
    }
    return null;
  }

  void _showVendorDetails(String vendorId) {
    if (!widget.dataset.vendorNpcsById.containsKey(vendorId)) return;
    if (_selectedVendorId == null) _pushNavigationEntry();
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _selectedVendorId = vendorId;
      _desktopSheetExpanded = true;
      _desktopTaskSurfaceCollapsed = false;
      _searchResultsVisible = false;
      _vendorClusterPickerIds = const <String>[];
      _vendorClusterPickerAnchor = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _compactLayout) return;
      if (_detailsScrollController.hasClients) {
        _detailsScrollController.jumpTo(
          _detailsScrollController.position.minScrollExtent,
        );
      }
      _detailsKeyboardFocus.requestFocus();
    });
  }

  KeyEventResult _handleDetailsKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_detailsScrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _detailsScrollController.position;
    final key = event.logicalKey;
    final pageStep = math.max(80.0, position.viewportDimension * .82);
    final target = switch (key) {
      LogicalKeyboardKey.arrowDown => position.pixels + 52,
      LogicalKeyboardKey.arrowUp => position.pixels - 52,
      LogicalKeyboardKey.pageDown => position.pixels + pageStep,
      LogicalKeyboardKey.pageUp => position.pixels - pageStep,
      LogicalKeyboardKey.home => position.minScrollExtent,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) return KeyEventResult.ignored;
    position.jumpTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
    return KeyEventResult.handled;
  }

  void _openVendorClusterPicker(List<BdoVendorNpc> vendors) {
    if (vendors.length < 2) return;
    final center = vendors
        .map((vendor) => vendor.location.mapPoint)
        .reduce(
          (left, right) => BdoMapPoint(left.x + right.x, left.y + right.y),
        );
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _selectedVendorId = null;
      _vendorClusterPickerIds = vendors
          .map((vendor) => vendor.id)
          .toList(growable: false);
      _vendorClusterPickerAnchor = BdoMapPoint(
        center.x / vendors.length,
        center.y / vendors.length,
      );
    });
  }

  void _closeVendorClusterPicker() {
    if (_vendorClusterPickerIds.isEmpty && _vendorClusterPickerAnchor == null) {
      return;
    }
    setState(() {
      _vendorClusterPickerIds = const <String>[];
      _vendorClusterPickerAnchor = null;
    });
  }

  void _focusNpcVendors(String requestedItemName) {
    final itemName = requestedItemName.trim();
    if (itemName.isEmpty) return;
    final vendors = widget.dataset.vendorNpcsForItem(itemName);
    if (vendors.isEmpty) return;

    final currentItemName = _vendorLookupItemName;
    if (currentItemName != null &&
        _normalizePlannerMaterialName(currentItemName) ==
            _normalizePlannerMaterialName(itemName)) {
      _searchFocus.unfocus();
      _mapKeyboardFocus.requestFocus();
      setState(() {
        _selectedVendorId = null;
        _desktopTaskSurfaceCollapsed = true;
        _desktopSheetExpanded = false;
        _vendorClusterPickerIds = const <String>[];
        _vendorClusterPickerAnchor = null;
      });
      _scheduleVendorFit(vendors);
      return;
    }

    _pushNavigationEntry();
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _cancelMarketValueCalculation();
      _desktopTaskSurfaceCollapsed = true;
      _desktopSheetExpanded = false;
      _layersMenuOpen = false;
      _searchController.value = TextEditingValue(
        text: itemName,
        selection: TextSelection.collapsed(offset: itemName.length),
      );
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _selectedVendorId = null;
      _vendorClusterPickerIds = const <String>[];
      _vendorClusterPickerAnchor = null;
      _vendorLookupItemName = itemName;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _materialSourceFilter = _MaterialSourceFilter.all;
      _showWorkerNodes = false;
      _showGathering = false;
      _showRoutes = false;
      _showConnections = false;
    });
    _scheduleVendorFit(vendors);
  }

  void _scheduleVendorFit(List<BdoVendorNpc> vendors) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewport.isEmpty) return;
      final bounds = _boundsForPoints(
        vendors
            .map((vendor) => vendor.location.mapPoint)
            .toList(growable: false),
        minimumSpan: 16000,
      );
      if (bounds != null) {
        _fitBoundsAvoidingDetails(bounds, padding: 72, maximumZoom: 6.2);
      }
    });
  }

  bool _hasManualMapSource(String resourceId) =>
      widget.dataset.hasMappedManualSource(resourceId) ||
      widget.dataset.fieldSourcesForResource(resourceId).isNotEmpty;

  void _openWorkerNodePlannerForResource(BdoResourceDefinition resource) {
    if (!widget.dataset.hasWorkerSource(resource.id)) {
      return;
    }
    final counts = Map<String, int>.of(
      _nodeNetworkPreferences.desiredResourceNodeCounts,
    );
    // Opening an item must not change an existing request, even when the
    // chosen towns currently cannot supply it. The planner explains that case.
    counts.putIfAbsent(resource.id, () => 1);
    final preferences = _nodeNetworkPreferences.copyWith(
      desiredResourceNodeCounts: counts,
    );

    _pushNavigationEntry();
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _cancelMarketValueCalculation();
      _nodeTargetPreviewDebounce?.cancel();
      _nodeTargetPreviewGeneration++;
      _nodeTargetPreviewResult = null;
      _nodeTargetPreviewLodgingPlan = null;
      _nodeTargetPreviewCalculating = false;
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _nodeNetworkPreferences = preferences;
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchController.value = TextEditingValue(
        text: resource.name,
        selection: TextSelection.collapsed(offset: resource.name.length),
      );
      _nodeTargetSearchController.value = TextEditingValue(
        text: resource.name,
        selection: TextSelection.collapsed(offset: resource.name.length),
      );
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedResourceId = resource.id;
      _selectedFieldSourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _showWorkerNodes = true;
      _showGathering = false;
      _showRoutes = false;
      _showConnections = true;
      _nodeNetworkPlannerOpen = true;
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.targets;
      _nodeTargetView = _NodeTargetView.all;
      _nodeTargetSettingsExpanded = false;
      _recipeNodeRecommendation = null;
      _selectedMarketValuePath = null;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = null;
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fitResource(resource.id);
      }
    });
  }

  void _focusResourceOnMap(
    BdoResourceDefinition resource, {
    required bool manual,
    bool showPreferredFieldSourceDetails = true,
  }) {
    _pushNavigationEntry();
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _cancelMarketValueCalculation();
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchController.value = TextEditingValue(
        text: resource.name,
        selection: TextSelection.collapsed(offset: resource.name.length),
      );
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedResourceId = resource.id;
      _selectedFieldSourceId = manual && showPreferredFieldSourceDetails
          ? _preferredFieldSourceId(resource.id)
          : null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _materialSourceFilter = manual
          ? _MaterialSourceFilter.manual
          : _MaterialSourceFilter.worker;
      _showWorkerNodes = !manual;
      _showGathering = manual;
      _showRoutes = manual;
      _showConnections = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (manual) {
        final sourceId = _selectedFieldSourceId;
        if (sourceId != null && _focusFieldSource(sourceId)) {
          return;
        }
      }
      if (!_fitPreferredResourceFocus(resource.id)) {
        _fitResource(resource.id);
      }
    });
  }

  void _updateGatherChecklist(BdoGatherChecklist next) {
    if (next == _gatherChecklist) {
      return;
    }
    setState(() => _gatherChecklist = next);
    widget.onGatherChecklistChanged?.call(next);
  }

  BdoGatherChecklistSourceKind? _preferredChecklistSource(
    BdoResourceDefinition resource,
  ) {
    final hasManual = _hasManualMapSource(resource.id);
    final hasWorker = widget.dataset.hasWorkerSource(resource.id);
    return switch (_materialSourceFilter) {
      _MaterialSourceFilter.manual when hasManual =>
        BdoGatherChecklistSourceKind.manualGathering,
      _MaterialSourceFilter.worker when hasWorker =>
        BdoGatherChecklistSourceKind.workerNode,
      _ when hasManual => BdoGatherChecklistSourceKind.manualGathering,
      _ when hasWorker => BdoGatherChecklistSourceKind.workerNode,
      _ => null,
    };
  }

  void _addResourceToGatherChecklist(BdoResourceDefinition resource) {
    _updateGatherChecklist(
      _gatherChecklist.addResource(
        resourceId: resource.id,
        displayName: resource.name,
        sourceKind: _preferredChecklistSource(resource),
      ),
    );
  }

  void _removeResourceFromGatherChecklist(String resourceId) {
    _updateGatherChecklist(_gatherChecklist.remove(resourceId));
  }

  void _toggleGatherChecklistCompletion(String resourceId) {
    _updateGatherChecklist(_gatherChecklist.toggleCompletion(resourceId));
  }

  void _reorderGatherChecklist(int oldIndex, int newIndex) {
    _updateGatherChecklist(_gatherChecklist.reorder(oldIndex, newIndex));
  }

  bool _focusGatherChecklistEntry(BdoGatherChecklistEntry entry) {
    final resource = widget.dataset.resourcesById[entry.resourceId];
    if (resource == null) {
      return false;
    }
    final hasManual = _hasManualMapSource(resource.id);
    final hasWorker = widget.dataset.hasWorkerSource(resource.id);
    final manual = switch (entry.sourceKind) {
      BdoGatherChecklistSourceKind.manualGathering => hasManual || !hasWorker,
      BdoGatherChecklistSourceKind.workerNode ||
      BdoGatherChecklistSourceKind.fishing => !hasWorker && hasManual,
      null => hasManual || !hasWorker,
    };
    if ((manual && !hasManual) || (!manual && !hasWorker)) {
      return false;
    }
    _updateGatherChecklist(_gatherChecklist.select(entry.resourceId));
    _focusResourceOnMap(
      resource,
      manual: manual,
      showPreferredFieldSourceDetails: false,
    );
    return true;
  }

  void _focusNextGatherChecklistEntry() {
    final next = _gatherChecklist.nextIncompleteEntry(
      afterId: _gatherChecklist.selectedResourceId,
    );
    if (next != null) {
      _focusGatherChecklistEntry(next);
    }
  }

  void _completeGatherChecklistEntryAndAdvance(String resourceId) {
    if (!_gatherChecklist.contains(resourceId)) {
      return;
    }
    final completed = _gatherChecklist.setCompletion(resourceId, true);
    final next = completed.nextIncompleteEntry(afterId: resourceId);
    final updated = next == null
        ? completed.clearSelection()
        : completed.select(next.resourceId);
    _updateGatherChecklist(updated);
    if (next != null) {
      _focusGatherChecklistEntry(next);
    }
  }

  BdoResourceDefinition? _resourceForFocusRequest(
    BdoResourceMapFocusRequest request,
  ) {
    final requestedId = request.resourceId?.trim();
    if (requestedId != null && requestedId.isNotEmpty) {
      final exact = widget.dataset.resourcesById[requestedId];
      if (exact != null) {
        return exact;
      }
    }
    final query = _normalizePlannerMaterialName(request.materialName);
    if (query.isEmpty) {
      return null;
    }
    for (final resource in widget.dataset.resources) {
      if (_normalizePlannerMaterialName(resource.name) == query ||
          resource.aliases.any(
            (alias) => _normalizePlannerMaterialName(alias) == query,
          )) {
        return resource;
      }
    }
    for (final node in widget.dataset.workerNodes) {
      for (final output in node.outputs) {
        if (_normalizePlannerMaterialName(output.name) == query) {
          return widget.dataset.resourcesById[output.resourceId];
        }
      }
    }
    return null;
  }

  void _openSourceNotice() {
    _searchFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showSourceNotice = true;
      _cacheActionMessage = null;
    });
    unawaited(_refreshCacheSize());
  }

  void _closeSourceNotice() {
    if (_showSourceNotice) {
      setState(() => _showSourceNotice = false);
    }
  }

  Future<void> _refreshCacheSize() async {
    final bytes = await _tileManager.diskCache.byteSize();
    if (!mounted) {
      return;
    }
    setState(() => _cacheBytes = bytes);
  }

  Future<void> _clearMapCache() async {
    if (_clearingCache) {
      return;
    }
    setState(() {
      _clearingCache = true;
      _cacheActionMessage = null;
    });
    try {
      final removedBytes = await _tileManager.clearCache();
      final remainingBytes = await _tileManager.diskCache.byteSize();
      if (!mounted) {
        return;
      }
      setState(() {
        _cacheBytes = remainingBytes;
        _cacheActionMessage = remainingBytes == 0
            ? '${_formatByteCount(removedBytes)} removed. Map downloads are '
                  'paused until you enable them again.'
            : '${_formatByteCount(removedBytes)} removed; '
                  '${_formatByteCount(remainingBytes)} remains in use or '
                  'could not be removed. Downloads are paused.';
      });
    } finally {
      if (mounted) {
        setState(() => _clearingCache = false);
      }
    }
  }

  List<BdoWorkerNode> get _visibleWorkerNodes {
    if (_recipeWorkerPlanVisible) {
      final ids = widget.recipeWorkerPlan!.selectedNodeIds.toSet();
      return widget.dataset.workerNodes
          .where((node) => ids.contains(node.id))
          .toList();
    }
    if (_nodeNetworkPlannerOpen) {
      final includedIds = switch (_nodeNetworkPlannerPage) {
        _NodeNetworkPlannerPage.home => _markedNodeNetworkDisplayIds(
          _nodeNetworkPreferences.currentNodeIds,
        ),
        _NodeNetworkPlannerPage.editCurrent => _markedNodeNetworkDisplayIds(
          _currentNodeDraftIds,
        ),
        _NodeNetworkPlannerPage.targets => <String>{
          ..._nodeNetworkPreferences.currentNodeIds,
          for (final resourceId
              in _nodeNetworkPreferences.desiredResourceNodeCounts.keys)
            ...widget.dataset
                .workerNodesForResource(resourceId)
                .map((node) => node.id),
        },
        _NodeNetworkPlannerPage.review => <String>{
          ..._nodeNetworkPreferences.currentNodeIds,
          ...?_nodeNetworkResult?.plan?.selectedNodeIds,
        },
        _NodeNetworkPlannerPage.marketValue => <String>{
          ..._nodeNetworkPreferences.currentNodeIds,
          if (_selectedMarketValuePath case final path?)
            ...path.orderedNodeIds
          else
            ...?_rawSaleNetworkPlan?.routeNodeIds,
        },
      };
      if (_selectedNodeId case final selectedNodeId?) {
        includedIds.add(selectedNodeId);
      }
      return widget.dataset.workerNodes
          .where((node) => includedIds.contains(node.id))
          .toList(growable: false);
    }
    if (_explicitWorkerEmphasisNodeIds.isNotEmpty) {
      final includedIds = <String>{..._explicitWorkerEmphasisNodeIds};
      if (_selectedNodeId case final selectedNodeId?) {
        includedIds.add(selectedNodeId);
      }
      return widget.dataset.workerNodes
          .where((node) => includedIds.contains(node.id))
          .toList(growable: false);
    }
    if (!_showWorkerNodes) {
      final searchMatchIds = _workerSearchMatchNodeIds;
      if (searchMatchIds.isEmpty) {
        return const <BdoWorkerNode>[];
      }
      return widget.dataset.workerNodes
          .where((node) => searchMatchIds.contains(node.id))
          .toList(growable: false);
    }
    final searchMatchIds = _workerSearchMatchNodeIds;
    if (searchMatchIds.isNotEmpty) {
      final includedIds = <String>{...searchMatchIds};
      if (_showConnections) {
        for (final nodeId in searchMatchIds) {
          final parentId = widget.dataset.workerNodesById[nodeId]?.parentId;
          if (parentId != null) {
            includedIds.add(parentId);
          }
        }
      }
      return widget.dataset.workerNodes
          .where((node) => includedIds.contains(node.id))
          .toList(growable: false);
    }
    if (_browseAllWorkerNodes) {
      if (!_workerOverviewSelectionMade) {
        return const <BdoWorkerNode>[];
      }
      final resourceNodes = widget.dataset.workerNodes
          .where(
            (node) =>
                node.isResourceNode &&
                (_workerActivityFilter == null ||
                    node.activity == _workerActivityFilter),
          )
          .toList(growable: false);
      if (!_showConnections) {
        return resourceNodes;
      }
      final includedIds = resourceNodes.map((node) => node.id).toSet();
      for (final node in resourceNodes) {
        if (node.parentId != null) {
          includedIds.add(node.parentId!);
        }
      }
      return widget.dataset.workerNodes
          .where((node) => includedIds.contains(node.id))
          .toList(growable: false);
    }
    final selectedSource = _selectedFieldSource;
    final resourceId = _selectedResourceId;
    if (selectedSource != null || resourceId != null) {
      if (_materialSourceFilter == _MaterialSourceFilter.manual) {
        return const <BdoWorkerNode>[];
      }
      final matchingById = <String, BdoWorkerNode>{};
      for (final id
          in selectedSource == null
              ? <String>[resourceId!]
              : selectedSource.products.map((product) => product.resourceId)) {
        for (final node in widget.dataset.workerNodesForResource(id)) {
          matchingById[node.id] = node;
        }
      }
      final matching = matchingById.values.toList(growable: false);
      final includedIds = matching.map((node) => node.id).toSet();
      if (_showConnections) {
        for (final node in matching) {
          if (node.parentId != null) {
            includedIds.add(node.parentId!);
          }
        }
      }
      return widget.dataset.workerNodes
          .where((node) => includedIds.contains(node.id))
          .toList(growable: false);
    }
    final selectedNodeId = _selectedNodeId;
    if (selectedNodeId != null) {
      final selectedNode = widget.dataset.workerNodesById[selectedNodeId];
      if (selectedNode == null) {
        return const <BdoWorkerNode>[];
      }
      final includedIds = <String>{selectedNode.id};
      if (_showConnections && selectedNode.parentId != null) {
        includedIds.add(selectedNode.parentId!);
      }
      return widget.dataset.workerNodes
          .where((node) => includedIds.contains(node.id))
          .toList(growable: false);
    }
    return const <BdoWorkerNode>[];
  }

  Set<String> get _workerSearchMatchNodeIds {
    if (!_searchResultsVisible ||
        _searchController.text.trim().isEmpty ||
        _materialSourceFilter == _MaterialSourceFilter.manual) {
      return const <String>{};
    }
    return _workerNodeIdsForSearchResults(
      _searchResults,
      _searchController.text,
    );
  }

  Set<String> get _emphasizedWorkerNodeIds => <String>{
    ..._workerSearchMatchNodeIds,
    ..._explicitWorkerEmphasisNodeIds,
  };

  Set<String> _workerNodeIdsForSearchResults(
    Iterable<BdoSearchResult> results,
    String query,
  ) {
    final resultList = results.toList(growable: false);
    final nodeIds = <String>{};
    final normalizedQuery = _normalizePlannerMaterialName(query);
    final queryTokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final matchingResourceIds = <String>{};
    for (final result in resultList) {
      if (result.kind != BdoSearchKind.resource) {
        continue;
      }
      final resourceId = result.resourceId ?? result.id;
      final resource = widget.dataset.resourcesById[resourceId];
      if (resource == null) {
        continue;
      }
      final resourceSearchText = _normalizePlannerMaterialName(
        <String>[resource.name, ...resource.aliases].join(' '),
      );
      if (queryTokens.every(resourceSearchText.contains)) {
        matchingResourceIds.add(resourceId);
      }
    }

    void addResourceNodes(String? resourceId) {
      if (resourceId == null) {
        return;
      }
      nodeIds.addAll(
        widget.dataset
            .workerNodesForResource(resourceId)
            .map((node) => node.id),
      );
    }

    for (final result in resultList) {
      switch (result.kind) {
        case BdoSearchKind.workerNode:
          final node = widget.dataset.workerNodesById[result.id];
          if (node != null &&
              (matchingResourceIds.isEmpty ||
                  node.outputs.any(
                    (output) => matchingResourceIds.contains(output.resourceId),
                  ))) {
            nodeIds.add(result.id);
          }
          break;
        case BdoSearchKind.resource:
          final resourceId = result.resourceId ?? result.id;
          if (matchingResourceIds.isEmpty ||
              matchingResourceIds.contains(resourceId)) {
            addResourceNodes(resourceId);
          }
          break;
        case BdoSearchKind.fieldSource:
          final source = widget
              .dataset
              .fieldSourcesById[result.fieldSourceId ?? result.id];
          if (source != null) {
            final matchingProducts = source.products
                .where((product) {
                  if (matchingResourceIds.isNotEmpty) {
                    return matchingResourceIds.contains(product.resourceId);
                  }
                  final resource =
                      widget.dataset.resourcesById[product.resourceId];
                  if (resource == null || queryTokens.isEmpty) {
                    return false;
                  }
                  final resourceSearchText = _normalizePlannerMaterialName(
                    <String>[resource.name, ...resource.aliases].join(' '),
                  );
                  return queryTokens.every(resourceSearchText.contains);
                })
                .toList(growable: false);
            final products = matchingProducts.isNotEmpty
                ? matchingProducts
                : source.products;
            for (final product in products) {
              addResourceNodes(product.resourceId);
            }
          }
          break;
        case BdoSearchKind.gatheringSpot:
        case BdoSearchKind.gatheringRoute:
          break;
      }
    }
    return nodeIds;
  }

  Set<String> get _plannedWorkerOutputNodeIds {
    if (_recipeWorkerPlanVisible) {
      return widget.recipeWorkerPlan!.selectedProductionNodeIds.toSet();
    }
    final quickCandidate = _selectedQuickNodePath;
    if (!_desktopNetworkWorkbenchVisible &&
        quickCandidate != null &&
        quickCandidate.targetNodeId == _selectedNodeId) {
      return <String>{quickCandidate.targetNodeId};
    }
    if (!_nodeNetworkPlannerOpen) {
      return const <String>{};
    }
    return switch (_nodeNetworkPlannerPage) {
      _NodeNetworkPlannerPage.review => <String>{
        ...?_nodeNetworkResult?.plan?.selectedProductionNodeIds,
      },
      _NodeNetworkPlannerPage.marketValue =>
        _desktopNetworkWorkbenchVisible
            ? <String>{...?_rawSaleNetworkPlan?.selectedProductionNodeIds}
            : <String>{
                if (_selectedMarketValuePath case final path?)
                  path.targetNodeId
                else
                  ...?_rawSaleNetworkPlan?.selectedProductionNodeIds,
              },
      _ => const <String>{},
    };
  }

  List<BdoNodeNetworkEdgeChange> get _visibleNodeNetworkEdgeChanges {
    if (_recipeWorkerPlanVisible) {
      return widget.recipeWorkerPlan!.changeSet.edges;
    }
    final quickCandidate = _selectedQuickNodePath;
    final quickPath =
        !_desktopNetworkWorkbenchVisible &&
            quickCandidate != null &&
            quickCandidate.targetNodeId == _selectedNodeId
        ? quickCandidate
        : null;
    if (quickPath != null) {
      final path = quickPath;
      final connectIds = path.connectNodeIds.toSet();
      return <BdoNodeNetworkEdgeChange>[
        for (final edge in path.edges)
          BdoNodeNetworkEdgeChange(
            firstNodeId: edge.fromNodeId,
            secondNodeId: edge.toNodeId,
            kind:
                connectIds.contains(edge.fromNodeId) ||
                    connectIds.contains(edge.toNodeId)
                ? BdoNodeNetworkChangeKind.connect
                : BdoNodeNetworkChangeKind.retained,
          ),
      ];
    }
    if (!_nodeNetworkPlannerOpen) {
      return const <BdoNodeNetworkEdgeChange>[];
    }
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.home ||
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent) {
      return _markedNodeNetworkEdges(
        _markedNodeNetworkDisplayIds(
          _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent
              ? _currentNodeDraftIds
              : _nodeNetworkPreferences.currentNodeIds,
        ),
      );
    }
    if (!_desktopNetworkWorkbenchVisible &&
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue &&
        _selectedMarketValuePath != null) {
      final path = _selectedMarketValuePath!;
      final connectIds = path.connectNodeIds.toSet();
      return <BdoNodeNetworkEdgeChange>[
        for (final edge in path.edges)
          BdoNodeNetworkEdgeChange(
            firstNodeId: edge.fromNodeId,
            secondNodeId: edge.toNodeId,
            kind:
                connectIds.contains(edge.fromNodeId) ||
                    connectIds.contains(edge.toNodeId)
                ? BdoNodeNetworkChangeKind.connect
                : BdoNodeNetworkChangeKind.retained,
          ),
      ];
    }
    final rawSalePlan = _rawSaleNetworkPlan;
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue &&
        rawSalePlan != null) {
      final plan = rawSalePlan;
      final addedIds = plan.addedNodeIds.toSet();
      return <BdoNodeNetworkEdgeChange>[
        for (final edge in plan.routeEdges)
          BdoNodeNetworkEdgeChange(
            firstNodeId: edge.firstNodeId,
            secondNodeId: edge.secondNodeId,
            kind:
                addedIds.contains(edge.firstNodeId) ||
                    addedIds.contains(edge.secondNodeId)
                ? BdoNodeNetworkChangeKind.connect
                : BdoNodeNetworkChangeKind.retained,
          ),
      ];
    }
    if (_nodeNetworkPlannerPage != _NodeNetworkPlannerPage.review) {
      return const <BdoNodeNetworkEdgeChange>[];
    }
    return _nodeNetworkResult?.plan?.changeSet.edges ??
        const <BdoNodeNetworkEdgeChange>[];
  }

  Map<String, BdoNodeNetworkChangeKind> get _visibleNodeNetworkChangeKinds {
    if (_recipeWorkerPlanVisible) {
      return {
        for (final id in widget.recipeWorkerPlan!.selectedNodeIds)
          id: BdoNodeNetworkChangeKind.connect,
      };
    }
    final quickCandidate = _selectedQuickNodePath;
    final quickPath =
        !_desktopNetworkWorkbenchVisible &&
            _nodeQuickPanelOpen &&
            quickCandidate != null &&
            quickCandidate.targetNodeId == _selectedNodeId
        ? quickCandidate
        : null;
    if (quickPath != null) {
      final path = quickPath;
      return <String, BdoNodeNetworkChangeKind>{
        for (final id in path.retainedNodeIds)
          id: BdoNodeNetworkChangeKind.retained,
        for (final id in path.connectNodeIds)
          id: BdoNodeNetworkChangeKind.connect,
      };
    }
    if (!_nodeNetworkPlannerOpen) {
      return const <String, BdoNodeNetworkChangeKind>{};
    }
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.home ||
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent) {
      final markedIds =
          _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent
          ? _currentNodeDraftIds
          : _nodeNetworkPreferences.currentNodeIds;
      return <String, BdoNodeNetworkChangeKind>{
        for (final id in markedIds) id: BdoNodeNetworkChangeKind.retained,
      };
    }
    if (!_desktopNetworkWorkbenchVisible &&
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue &&
        _selectedMarketValuePath != null) {
      final path = _selectedMarketValuePath!;
      return <String, BdoNodeNetworkChangeKind>{
        for (final id in path.retainedNodeIds)
          id: BdoNodeNetworkChangeKind.retained,
        for (final id in path.connectNodeIds)
          id: BdoNodeNetworkChangeKind.connect,
      };
    }
    final rawSalePlan = _rawSaleNetworkPlan;
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue &&
        rawSalePlan != null) {
      final plan = rawSalePlan;
      return <String, BdoNodeNetworkChangeKind>{
        for (final id in plan.routeNodeIds)
          id: plan.addedNodeIds.contains(id)
              ? BdoNodeNetworkChangeKind.connect
              : BdoNodeNetworkChangeKind.retained,
      };
    }
    if (_nodeNetworkPlannerPage != _NodeNetworkPlannerPage.review) {
      return const <String, BdoNodeNetworkChangeKind>{};
    }
    final changeSet = _nodeNetworkResult?.plan?.changeSet;
    if (changeSet == null) {
      return const <String, BdoNodeNetworkChangeKind>{};
    }
    return <String, BdoNodeNetworkChangeKind>{
      for (final id in changeSet.retainedNodeIds)
        id: BdoNodeNetworkChangeKind.retained,
      for (final id in changeSet.connectNodeIds)
        id: BdoNodeNetworkChangeKind.connect,
      for (final id in changeSet.disconnectNodeIds)
        id: BdoNodeNetworkChangeKind.disconnect,
    };
  }

  List<BdoNodeNetworkEdgeChange> _markedNodeNetworkEdges(
    Set<String> markedNodeIds,
  ) {
    if (markedNodeIds.length < 2) {
      return const <BdoNodeNetworkEdgeChange>[];
    }
    final seen = <String>{};
    final edges = <BdoNodeNetworkEdgeChange>[];
    for (final node in widget.dataset.workerNodes) {
      if (!markedNodeIds.contains(node.id)) {
        continue;
      }
      for (final linkedId in node.linkIds) {
        if (!markedNodeIds.contains(linkedId) ||
            !widget.dataset.workerNodesById.containsKey(linkedId)) {
          continue;
        }
        final first = node.id.compareTo(linkedId) <= 0 ? node.id : linkedId;
        final second = first == node.id ? linkedId : node.id;
        final key = '$first\u0000$second';
        if (!seen.add(key)) {
          continue;
        }
        edges.add(
          BdoNodeNetworkEdgeChange(
            firstNodeId: first,
            secondNodeId: second,
            kind: BdoNodeNetworkChangeKind.retained,
          ),
        );
      }
    }
    return edges;
  }

  Set<String> _markedNodeNetworkDisplayIds(Set<String> markedNodeIds) {
    final displayIds = <String>{...markedNodeIds};
    for (final id in markedNodeIds) {
      final node = widget.dataset.workerNodesById[id];
      if (node == null) {
        continue;
      }
      for (final linkedId in node.linkIds) {
        final linkedNode = widget.dataset.workerNodesById[linkedId];
        if (linkedNode != null && _isNaturalWorkerRoot(linkedNode)) {
          displayIds.add(linkedId);
        }
      }
    }
    return displayIds;
  }

  List<BdoGatheringSpot> get _visibleGatheringSpots {
    if (!_showGathering) {
      return const <BdoGatheringSpot>[];
    }
    final selectedSource = _selectedFieldSource;
    final resourceId = _selectedResourceId;
    if (selectedSource != null || resourceId != null) {
      if (_materialSourceFilter == _MaterialSourceFilter.worker) {
        return const <BdoGatheringSpot>[];
      }
      if (selectedSource != null) {
        return _gatheringSpotsForFieldSource(selectedSource);
      }
      final spots = <String, BdoGatheringSpot>{};
      for (final id in <String>[resourceId!]) {
        for (final spot in widget.dataset.gatheringSpotsForResource(id)) {
          spots[spot.id] = spot;
        }
      }
      return spots.values.toList(growable: false);
    }
    final selectedSpotId = _selectedSpotId;
    if (selectedSpotId != null) {
      final selectedSpot = widget.dataset.gatheringSpotsById[selectedSpotId];
      return selectedSpot == null
          ? const <BdoGatheringSpot>[]
          : <BdoGatheringSpot>[selectedSpot];
    }
    return const <BdoGatheringSpot>[];
  }

  List<BdoGatheringSpot> _gatheringSpotsForFieldSource(BdoFieldSource source) {
    final resourceIds = source.resourceIds.toSet();
    final spots = <String, BdoGatheringSpot>{
      for (final spot in widget.dataset.gatheringSpotsForFieldSource(source.id))
        spot.id: spot,
    };
    for (final spot in widget.dataset.gatheringSpots) {
      if (spot.fieldSourceIds.isEmpty &&
          spot.resourceIds.any(resourceIds.contains)) {
        spots[spot.id] = spot;
      }
    }
    return spots.values.toList(growable: false);
  }

  List<BdoGatheringPoint> get _visibleGatheringPoints {
    if (!_showGathering) {
      return const <BdoGatheringPoint>[];
    }
    final selectedSource = _selectedFieldSource;
    final resourceId = _selectedResourceId;
    if (selectedSource != null || resourceId != null) {
      if (_materialSourceFilter == _MaterialSourceFilter.worker) {
        return const <BdoGatheringPoint>[];
      }
      if (selectedSource != null) {
        return widget.dataset
            .gatheringPointsForFieldSource(selectedSource.id)
            .toList(growable: false);
      }
      return widget.dataset
          .gatheringPointsForResource(resourceId!)
          .toList(growable: false);
    }
    final selectedSpotId = _selectedSpotId;
    if (selectedSpotId != null) {
      return widget.dataset.gatheringPoints
          .where((point) => point.areaId == selectedSpotId)
          .toList(growable: false);
    }
    final selectedPointId = _selectedPointId;
    if (selectedPointId != null) {
      final selectedPoint = widget.dataset.gatheringPointsById[selectedPointId];
      return selectedPoint == null
          ? const <BdoGatheringPoint>[]
          : <BdoGatheringPoint>[selectedPoint];
    }
    return const <BdoGatheringPoint>[];
  }

  List<BdoGatheringRoute> get _visibleGatheringRoutes {
    if (!_showRoutes) {
      return const <BdoGatheringRoute>[];
    }
    return _matchingGatheringRoutes;
  }

  List<BdoGatheringRoute> get _matchingGatheringRoutes {
    final selectedSource = _selectedFieldSource;
    final resourceId = _selectedResourceId;
    if (selectedSource != null || resourceId != null) {
      if (_materialSourceFilter == _MaterialSourceFilter.worker) {
        return const <BdoGatheringRoute>[];
      }
      final routes = <String, BdoGatheringRoute>{};
      for (final id
          in selectedSource == null
              ? <String>[resourceId!]
              : selectedSource.products.map((product) => product.resourceId)) {
        for (final route in widget.dataset.gatheringRoutesForResource(id)) {
          routes[route.id] = route;
        }
      }
      return routes.values.toList(growable: false);
    }
    final selectedRouteId = _selectedRouteId;
    if (selectedRouteId != null) {
      final selectedRoute = widget.dataset.gatheringRoutesById[selectedRouteId];
      return selectedRoute == null
          ? const <BdoGatheringRoute>[]
          : <BdoGatheringRoute>[selectedRoute];
    }
    return const <BdoGatheringRoute>[];
  }

  BdoFieldSource? get _selectedFieldSource {
    final id = _selectedFieldSourceId;
    return id == null ? null : widget.dataset.fieldSourcesById[id];
  }

  LodgingTown? get _selectedHousingTown {
    final nodeId = _selectedNodeId;
    return nodeId == null ? null : widget.lodgingDataset?.townsByNodeId[nodeId];
  }

  Set<String> _ownedHouseIdsForTown(LodgingTown town) => _nodeNetworkPreferences
      .currentOwnedHouseIds
      .where(town.housesById.containsKey)
      .toSet();

  int _ownedLodgingCapacityForTown(LodgingTown town) {
    final owned = _ownedHouseIdsForTown(town);
    return town.houses
        .where(
          (house) =>
              owned.contains(house.id) &&
              _nodeNetworkPreferences.currentHouseUsageTypeIds[house.id] == 1,
        )
        .fold<int>(0, (total, house) => total + house.lodgingSpaces);
  }

  BdoTownWorkerCapacity _effectiveTownWorkerCapacity(
    String townNodeId,
    BdoTownWorkerCapacity configured,
  ) {
    if (!configured.usesKnownTownLodging) {
      return configured;
    }
    final town = widget.lodgingDataset?.townsByNodeId[townNodeId];
    return configured.resolveForKnownTownLodging(
      baseWorkerSlotCount: town?.baseWorkerSlots ?? 0,
      activeOwnedLodgingSlotCount: town == null
          ? 0
          : _ownedLodgingCapacityForTown(town),
    );
  }

  Map<String, BdoTownWorkerCapacity>
  get _effectiveTownWorkerCapacitiesByNodeId {
    final configured = _nodeNetworkPreferences.townWorkerCapacitiesByNodeId;
    final lodgingDataset = widget.lodgingDataset;
    if (lodgingDataset == null) {
      return <String, BdoTownWorkerCapacity>{
        for (final entry in configured.entries)
          entry.key: _effectiveTownWorkerCapacity(entry.key, entry.value),
      };
    }

    final result = <String, BdoTownWorkerCapacity>{};
    for (final town in lodgingDataset.towns.where(
      (candidate) => candidate.isWorkerTown,
    )) {
      final saved = configured[town.townNodeId];
      if (saved != null) {
        // Legacy effective entries and newer hired/bonus breakdowns retain
        // their existing authoritative meanings.
        result[town.townNodeId] = _effectiveTownWorkerCapacity(
          town.townNodeId,
          saved,
        );
        continue;
      }
      // A player who has not entered worker data still owns the town's mapped
      // free base slot and every mapped house explicitly saved as Lodging.
      // No hired worker is invented; those vacant beds can be filled without
      // charging another house, while every later bed receives an exact plan.
      result[town.townNodeId] = BdoTownWorkerCapacity(
        availableWorkerCount: 0,
        freeLodgingSlotCount:
            town.baseWorkerSlots + _ownedLodgingCapacityForTown(town),
        hiredWorkerCount: 0,
        bonusLodgingSlotCount: 0,
      );
    }
    // Preserve a legacy saved town that is temporarily absent from the mapped
    // housing dataset. Validation downstream will keep it out of new plans.
    for (final entry in configured.entries) {
      result.putIfAbsent(
        entry.key,
        () => _effectiveTownWorkerCapacity(entry.key, entry.value),
      );
    }
    return result;
  }

  BdoLodgingNetworkPlan? get _activeNetworkLodgingPlan {
    if (!_nodeNetworkPlannerOpen) {
      return null;
    }
    return switch (_nodeNetworkPlannerPage) {
      _NodeNetworkPlannerPage.review => _nodeNetworkLodgingPlan?.plan,
      _NodeNetworkPlannerPage.marketValue => _rawSaleLodgingPlan?.plan,
      _ => null,
    };
  }

  LodgingPlan? _activeNetworkLodgingPlanForTown(LodgingTown town) =>
      _activeNetworkLodgingPlan?.townPlansByNodeId[town.townNodeId];

  LodgingPlan _displayedLodgingPlanForTown(LodgingTown town) =>
      _activeNetworkLodgingPlanForTown(town) ?? _lodgingPlanForTown(town);

  int _nodePlanCombinedContributionPoints(BdoNodeNetworkPlan plan) =>
      plan.totalContributionPoints +
      (_nodeNetworkLodgingPlan?.plan?.totalIncrementalContributionPoints ?? 0) +
      _activeRoyalWorkshopReservedContributionPoints;

  int _nodePlanRemainingContributionPoints(BdoNodeNetworkPlan plan) =>
      plan.contributionPointBudget - _nodePlanCombinedContributionPoints(plan);

  bool _nodePlanIsWithinCombinedBudget(BdoNodeNetworkPlan plan) =>
      _nodePlanRemainingContributionPoints(plan) >= 0;

  int _currentWorkerCapacityForTown(LodgingTown town) {
    final knownSlotCount =
        town.baseWorkerSlots + _ownedLodgingCapacityForTown(town);
    final configured =
        _nodeNetworkPreferences.townWorkerCapacitiesByNodeId[town.townNodeId];
    if (configured == null) {
      return knownSlotCount;
    }
    if (!configured.usesKnownTownLodging) {
      // Pre-housing saves already store the effective usable capacity. Do
      // not replace it with the newer mapped-house derivation.
      return math.max(configured.availableWorkerCount, 0) +
          math.max(configured.freeLodgingSlotCount, 0);
    }
    final effective = configured.resolveForKnownTownLodging(
      baseWorkerSlotCount: town.baseWorkerSlots,
      activeOwnedLodgingSlotCount: _ownedLodgingCapacityForTown(town),
    );
    return effective.availableWorkerCount + effective.freeLodgingSlotCount;
  }

  int _maximumWorkerCapacityForTown(LodgingTown town) {
    final bonus = _bonusLodgingCountForTown(town);
    final owned = _nodeNetworkPreferences.currentOwnedHouseIds;
    final savedUses = _nodeNetworkPreferences.currentHouseUsageTypeIds;
    final mappedMaximum =
        town.baseWorkerSlots +
        town.lodgingHouses.fold<int>(0, (total, house) {
          if (owned.contains(house.id) && savedUses[house.id] != 1) {
            return total;
          }
          return total + house.lodgingSpaces;
        }) +
        bonus;
    // Legacy profiles can contain authoritative lodging that predates the
    // mapped house/use breakdown. Never make their current capacity invalid.
    return math.max(mappedMaximum, _currentWorkerCapacityForTown(town));
  }

  int _bonusLodgingCountForTown(LodgingTown town) {
    final configured =
        _nodeNetworkPreferences.townWorkerCapacitiesByNodeId[town.townNodeId];
    return configured?.effectiveBonusLodgingSlotCount ?? 0;
  }

  int _housingTargetFloorForTown(LodgingTown town) => math.min(
    _currentWorkerCapacityForTown(town),
    _maximumWorkerCapacityForTown(town),
  );

  int _workerTargetForTown(LodgingTown town) {
    final minimum = _housingTargetFloorForTown(town);
    final maximum = _maximumWorkerCapacityForTown(town);
    return (_lodgingWorkerTargetsByTownNodeId[town.townNodeId] ?? minimum)
        .clamp(minimum, maximum)
        .toInt();
  }

  LodgingPlan _lodgingPlanForTown(LodgingTown town) {
    return LodgingOptimizer.solve(
      town: town,
      requiredCapacity: _workerTargetForTown(town),
      existingCapacity: _currentWorkerCapacityForTown(town),
      currentOwnedHouseIds: _nodeNetworkPreferences.currentOwnedHouseIds,
    );
  }

  bool _storagePlannerOpenForTown(LodgingTown town) =>
      _storagePlannerTownNodeId == town.townNodeId &&
      _selectedNodeId == town.townNodeId;

  List<HouseUsage> _housePlannerUsagesForTown(LodgingTown town) {
    final byTypeId = <int, HouseUsage>{};
    for (final house in town.houses) {
      for (final usage in house.usages) {
        final current = byTypeId[usage.typeId];
        if (current == null || usage.level > current.level) {
          byTypeId[usage.typeId] = usage;
        }
      }
    }
    final usages = byTypeId.values.toList(growable: false);
    usages.sort((left, right) {
      const preferred = <int, int>{2: 0, 1: 1, 3: 2, 0: 3};
      final leftPriority = preferred[left.typeId] ?? 4;
      final rightPriority = preferred[right.typeId] ?? 4;
      final byPriority = leftPriority.compareTo(rightPriority);
      if (byPriority != 0) return byPriority;
      final byLabel = _displayHouseUsageLabel(
        left,
      ).compareTo(_displayHouseUsageLabel(right));
      return byLabel != 0 ? byLabel : left.typeId.compareTo(right.typeId);
    });
    return usages;
  }

  int _housePlannerUsageTypeForTown(LodgingTown town) {
    final usages = _housePlannerUsagesForTown(town);
    final requested = _housePlannerUsageTypeByTownNodeId[town.townNodeId];
    if (requested != null && usages.any((usage) => usage.typeId == requested)) {
      return requested;
    }
    return usages
        .firstWhere((usage) => usage.typeId == 2, orElse: () => usages.first)
        .typeId;
  }

  int _housePlannerMaximumLevel(LodgingTown town, int usageTypeId) => town
      .houses
      .map((house) => house.usagesByTypeId[usageTypeId]?.level ?? 0)
      .fold<int>(0, (maximum, level) => level > maximum ? level : maximum);

  int _housePlannerMinimumLevelForTown(LodgingTown town) {
    final usageTypeId = _housePlannerUsageTypeForTown(town);
    final maximum = _housePlannerMaximumLevel(town, usageTypeId);
    return (_housePlannerMinimumLevelByTownNodeId[town.townNodeId] ?? 1)
        .clamp(1, math.max(1, maximum))
        .toInt();
  }

  int _maximumAdditionalFacilitiesForTown(LodgingTown town) {
    final usageTypeId = _housePlannerUsageTypeForTown(town);
    final minimumLevel = _housePlannerMinimumLevelForTown(town);
    return town.houses.where((house) {
      final usage = house.usagesByTypeId[usageTypeId];
      return usage != null &&
          usage.level >= minimumLevel &&
          !_nodeNetworkPreferences.currentOwnedHouseIds.contains(house.id);
    }).length;
  }

  int _housePlannerFacilityCountForTown(LodgingTown town) {
    final maximum = _maximumAdditionalFacilitiesForTown(town);
    if (maximum == 0) return 0;
    return (_housePlannerFacilityCountByTownNodeId[town.townNodeId] ?? 1)
        .clamp(1, maximum)
        .toInt();
  }

  bool _storagePlanActiveForTown(LodgingTown town) =>
      _storagePlannerOpenForTown(town) &&
      _housePlannerUsageTypeForTown(town) == 2;

  bool _lodgingPlanActiveForTown(LodgingTown town) =>
      _storagePlannerOpenForTown(town) &&
      _housePlannerUsageTypeForTown(town) == 1;

  HouseUseInvestmentPlan? _houseUsePlanForTown(LodgingTown town) {
    if (!_storagePlannerOpenForTown(town) ||
        const <int>{1, 2}.contains(_housePlannerUsageTypeForTown(town))) {
      return null;
    }
    return HouseUseInvestmentPlanner.solve(
      town: town,
      usageTypeId: _housePlannerUsageTypeForTown(town),
      minimumLevel: _housePlannerMinimumLevelForTown(town),
      requestedAdditionalFacilityCount: _housePlannerFacilityCountForTown(town),
      currentOwnedHouseIds: _nodeNetworkPreferences.currentOwnedHouseIds,
      currentHouseUsageTypeIds:
          _nodeNetworkPreferences.currentHouseUsageTypeIds,
    );
  }

  int _maximumAdditionalStorageSlotsForTown(LodgingTown town) => town.houses
      .where(
        (house) =>
            !_nodeNetworkPreferences.currentOwnedHouseIds.contains(house.id),
      )
      .fold<int>(0, (total, house) => total + storageSlotsForHouse(house));

  int _storageSlotTargetForTown(LodgingTown town) {
    final maximum = _maximumAdditionalStorageSlotsForTown(town);
    if (maximum == 0) return 0;
    return (_storageSlotTargetsByTownNodeId[town.townNodeId] ?? 3)
        .clamp(1, maximum)
        .toInt();
  }

  StorageHousePlan _storagePlanForTown(LodgingTown town) =>
      StorageHouseOptimizer.solve(
        town: town,
        requestedAdditionalSlots: _storageSlotTargetForTown(town),
        currentOwnedHouseIds: _nodeNetworkPreferences.currentOwnedHouseIds,
        currentHouseUsageTypeIds:
            _nodeNetworkPreferences.currentHouseUsageTypeIds,
      );

  BdoMapPoint _houseMapPoint(LodgingHouse house) =>
      BdoWorldPoint(house.position.x, house.position.z).mapPoint;

  String get _currentNavigationLabel {
    if (_searchResultsVisible && _searchController.text.trim().isNotEmpty) {
      return 'Search results';
    }
    if (_vendorLookupItemName case final itemName?) {
      return '$itemName vendors';
    }
    if (_selectedPointId case final id?) {
      return widget.dataset.gatheringPointsById[id]?.target ?? 'Location';
    }
    if (_selectedSpotId case final id?) {
      return widget.dataset.gatheringSpotsById[id]?.name ??
          'Gathering location';
    }
    if (_selectedRouteId case final id?) {
      return widget.dataset.gatheringRoutesById[id]?.name ?? 'Gathering route';
    }
    if (_selectedNodeId case final id?) {
      return widget.dataset.workerNodesById[id]?.siteName ?? 'Worker node';
    }
    if (_selectedFieldSource case final source?) {
      return source.name;
    }
    if (_selectedResourceId case final id?) {
      return widget.dataset.resourcesById[id]?.name ?? 'Material';
    }
    if (_nodeNetworkPlannerOpen) {
      return switch (_nodeNetworkPlannerPage) {
        _NodeNetworkPlannerPage.home => 'Worker planner',
        _NodeNetworkPlannerPage.editCurrent => 'In-game worker network',
        _NodeNetworkPlannerPage.targets => 'Node network targets',
        _NodeNetworkPlannerPage.review => 'Review node changes',
        _NodeNetworkPlannerPage.marketValue =>
          widget.workerEconomics == null
              ? 'Raw-sale price signals'
              : 'Worker income plan',
      };
    }
    if (_housingDirectoryOpen) {
      return 'Houses';
    }
    if (_royalWorkshopVisible) {
      return 'Royal Workshop';
    }
    if (_gatherChecklistOpen) {
      return 'To-do list';
    }
    if (_gatherPlanShortlistOpen) {
      return 'Needed for your plan';
    }
    if (_browseAllWorkerNodes) {
      return _workerOverviewSelectionMade
          ? '${_workerActivityFilter?.label ?? 'All'} nodes'
          : 'Worker nodes';
    }
    if (_gatherChecklistOpen) {
      return 'gather checklist';
    }
    if (_browseFavorites) {
      return 'Favorites';
    }
    if (_selectedResourceSection case final section?) {
      return _resourceSectionLabel(section);
    }
    return 'map home';
  }

  String get _backNavigationLabel {
    if (_navigationHistory.isNotEmpty) {
      return _navigationHistory.last.label;
    }
    final resource = _selectedResourceId == null
        ? null
        : widget.dataset.resourcesById[_selectedResourceId!];
    if (_canReturnToSelectedResource) {
      return _selectedFieldSource?.name ?? resource?.name ?? 'material';
    }
    if (_browseAllWorkerNodes) {
      return _workerOverviewSelectionMade
          ? '${_workerActivityFilter?.label ?? 'All'} nodes'
          : 'Worker nodes';
    }
    return _browseFavorites
        ? 'favorites'
        : _selectedResourceSection == null
        ? 'map home'
        : _resourceSectionLabel(_selectedResourceSection!).toLowerCase();
  }

  _MapNavigationEntry _captureNavigationEntry() {
    return _MapNavigationEntry(
      label: _currentNavigationLabel,
      camera: _cameraController.camera,
      desktopTaskSurfaceCollapsed: _desktopTaskSurfaceCollapsed,
      desktopSheetExpanded: _desktopSheetExpanded,
      materialCatalogOpen: _materialCatalogOpen,
      selectedFieldSourceId: _selectedFieldSourceId,
      selectedResourceId: _selectedResourceId,
      selectedNodeId: _selectedNodeId,
      selectedHouseId: _selectedHouseId,
      selectedSpotId: _selectedSpotId,
      selectedPointId: _selectedPointId,
      selectedRouteId: _selectedRouteId,
      vendorLookupItemName: _vendorLookupItemName,
      selectedVendorId: _selectedVendorId,
      gatherChecklistOpen: _gatherChecklistOpen,
      gatherPlanShortlistOpen: _gatherPlanShortlistOpen,
      housingDirectoryOpen: _housingDirectoryOpen,
      royalWorkshopOpen: _royalWorkshopOpen,
      nodeNetworkPlannerOpen: _nodeNetworkPlannerOpen,
      nodeNetworkPlannerPage: _nodeNetworkPlannerPage,
      browseAllWorkerNodes: _browseAllWorkerNodes,
      workerOverviewSelectionMade: _workerOverviewSelectionMade,
      workerActivityFilter: _workerActivityFilter,
      materialSourceFilter: _materialSourceFilter,
      mapSearchScope: _mapSearchScope,
      selectedResourceSection: _selectedResourceSection,
      browseFavorites: _browseFavorites,
      showWorkerNodes: _showWorkerNodes,
      showGathering: _showGathering,
      showRoutes: _showRoutes,
      showConnections: _showConnections,
      searchText: _searchController.text,
      searchResultsVisible: _searchResultsVisible,
    );
  }

  void _pushNavigationEntry() {
    final entry = _captureNavigationEntry();
    if (_navigationHistory.isNotEmpty &&
        _navigationHistory.last.sameDestination(entry)) {
      // The logical destination is unchanged, but the user may have panned or
      // changed layers since it was first captured. Keep one Back step while
      // refreshing the exact state that Back must restore.
      _navigationHistory[_navigationHistory.length - 1] = entry;
      return;
    }
    _navigationHistory.add(entry);
    if (_navigationHistory.length > 24) {
      _navigationHistory.removeAt(0);
    }
  }

  void _navigateBack() {
    if (_navigationHistory.isEmpty) {
      _dismissDetailsWithoutHistory();
      return;
    }
    _searchFocus.unfocus();
    final entry = _navigationHistory.removeLast();
    setState(() {
      _desktopTaskSurfaceCollapsed = entry.desktopTaskSurfaceCollapsed;
      _desktopSheetExpanded = entry.desktopSheetExpanded;
      _materialCatalogOpen = entry.materialCatalogOpen;
      _layersMenuOpen = false;
      _selectedFieldSourceId = entry.selectedFieldSourceId;
      _selectedResourceId = entry.selectedResourceId;
      _selectedNodeId = entry.selectedNodeId;
      _selectedHouseId = entry.selectedHouseId;
      _storagePlannerTownNodeId = null;
      _selectedSpotId = entry.selectedSpotId;
      _selectedPointId = entry.selectedPointId;
      _selectedRouteId = entry.selectedRouteId;
      _vendorLookupItemName = entry.vendorLookupItemName;
      _selectedVendorId = entry.selectedVendorId;
      _vendorClusterPickerIds = const <String>[];
      _vendorClusterPickerAnchor = null;
      _nodeQuickPanelOpen =
          entry.selectedNodeId != null &&
          entry.selectedHouseId == null &&
          (!entry.nodeNetworkPlannerOpen ||
              entry.nodeNetworkPlannerPage !=
                  _NodeNetworkPlannerPage.editCurrent) &&
          (!entry.desktopSheetExpanded ||
              entry.nodeNetworkPlannerOpen ||
              (_royalWorkshopEnabled && entry.royalWorkshopOpen));
      _selectedMarketValuePath =
          entry.nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue &&
              entry.selectedNodeId != null
          ? _marketValuePathForNode(entry.selectedNodeId!)
          : null;
      _selectedQuickNodePath = _nodeQuickPanelOpen
          ? _quickPathForNodeId(entry.selectedNodeId!)
          : null;
      _gatherChecklistOpen = entry.gatherChecklistOpen;
      _gatherPlanShortlistOpen = entry.gatherPlanShortlistOpen;
      _housingDirectoryOpen = entry.housingDirectoryOpen;
      _royalWorkshopOpen = _royalWorkshopEnabled && entry.royalWorkshopOpen;
      _nodeNetworkPlannerOpen = entry.nodeNetworkPlannerOpen;
      _nodeNetworkPlannerPage = entry.nodeNetworkPlannerPage;
      _browseAllWorkerNodes = entry.browseAllWorkerNodes;
      _workerOverviewSelectionMade = entry.workerOverviewSelectionMade;
      _workerActivityFilter = entry.workerActivityFilter;
      _materialSourceFilter = entry.materialSourceFilter;
      _mapSearchScope = entry.mapSearchScope;
      _selectedResourceSection = entry.selectedResourceSection;
      _browseFavorites = entry.browseFavorites;
      _showWorkerNodes = entry.showWorkerNodes;
      _showGathering = entry.showGathering;
      _showRoutes = entry.showRoutes;
      _showConnections = entry.showConnections;
      _searchController.value = TextEditingValue(
        text: entry.searchText,
        selection: TextSelection.collapsed(offset: entry.searchText.length),
      );
      _searchResultsVisible =
          entry.searchResultsVisible && entry.searchText.trim().isNotEmpty;
      _searchResults = _searchResultsVisible
          ? _searchResultsForCurrentSource(entry.searchText)
          : const <BdoSearchResult>[];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewport.isEmpty) return;
      _cameraController.setCamera(entry.camera, _viewport);
    });
  }

  String? _preferredFieldSourceId(String resourceId) {
    final sources = widget.dataset
        .fieldSourcesForResource(resourceId)
        .toList(growable: false);
    return sources.length == 1 ? sources.single.id : null;
  }

  void _search(String query, {bool? showResults}) {
    final keepSearchFocus = _searchFocus.hasFocus;
    final normalized = query.trim();
    final nextResults = _searchResultsForCurrentSource(query);
    final nextWorkerNodeIds = normalized.isEmpty
        ? const <String>{}
        : _workerNodeIdsForSearchResults(nextResults, query);
    setState(() {
      if (normalized.isNotEmpty) {
        _desktopSheetExpanded = true;
      }
      _explicitWorkerEmphasisNodeIds = <String>{};
      _searchResults = nextResults;
      _searchResultsVisible = normalized.isNotEmpty && (showResults ?? true);
      if (_selectedNodeId case final selectedNodeId?
          when !nextWorkerNodeIds.contains(selectedNodeId)) {
        _selectedNodeId = null;
        _nodeQuickPanelOpen = false;
        _selectedQuickNodePath = null;
      }
    });
    if (keepSearchFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_searchFocus.hasFocus) {
          _searchFocus.requestFocus();
        }
      });
    }
  }

  List<BdoSearchResult> _searchResultsForCurrentSource(String query) {
    return widget.dataset
        .search(query)
        .where(_searchResultMatchesCurrentSource)
        .where(_searchResultMatchesScope)
        .toList(growable: false);
  }

  bool _searchResultMatchesScope(BdoSearchResult result) {
    return switch (_mapSearchScope) {
      _MapSearchScope.all => true,
      _MapSearchScope.items => result.kind == BdoSearchKind.resource,
      _MapSearchScope.nodesAndTowns => result.kind == BdoSearchKind.workerNode,
      _MapSearchScope.wildlife => switch (result.kind) {
        BdoSearchKind.fieldSource =>
          widget.dataset.fieldSourcesById[result.fieldSourceId]?.category ==
              'Animals',
        BdoSearchKind.gatheringSpot => _gatheringSpotMatchesFieldSourceCategory(
          result.id,
          'Animals',
        ),
        _ => false,
      },
      _MapSearchScope.plantsAndTrees => switch (result.kind) {
        BdoSearchKind.fieldSource => _isPlantOrTreeFieldSource(
          widget.dataset.fieldSourcesById[result.fieldSourceId],
        ),
        BdoSearchKind.gatheringSpot => _gatheringSpotMatchesPlantOrTreeSource(
          result.id,
        ),
        _ => false,
      },
    };
  }

  bool _gatheringSpotMatchesFieldSourceCategory(
    String spotId,
    String category,
  ) {
    final spot = widget.dataset.gatheringSpotsById[spotId];
    return spot != null &&
        spot.fieldSourceIds.any(
          (id) => widget.dataset.fieldSourcesById[id]?.category == category,
        );
  }

  bool _gatheringSpotMatchesPlantOrTreeSource(String spotId) {
    final spot = widget.dataset.gatheringSpotsById[spotId];
    return spot != null &&
        spot.fieldSourceIds.any(
          (id) =>
              _isPlantOrTreeFieldSource(widget.dataset.fieldSourcesById[id]),
        );
  }

  bool _isPlantOrTreeFieldSource(BdoFieldSource? source) {
    final category = source?.category.toLowerCase() ?? '';
    return category.contains('plant') ||
        category.contains('tree') ||
        category.contains('mushroom');
  }

  void _selectMapSearchScope(_MapSearchScope scope) {
    if (scope == _mapSearchScope) {
      return;
    }
    setState(() {
      _mapSearchScope = scope;
      final query = _searchController.text;
      _searchResults = query.trim().isEmpty
          ? const <BdoSearchResult>[]
          : _searchResultsForCurrentSource(query);
      _searchResultsVisible = query.trim().isNotEmpty;
    });
    _searchFocus.requestFocus();
  }

  String get _mapSearchHintText => switch (_mapSearchScope) {
    _MapSearchScope.all => 'Search items, wildlife, plants, nodes or towns',
    _MapSearchScope.items => 'Search items',
    _MapSearchScope.wildlife => 'Search wildlife',
    _MapSearchScope.plantsAndTrees => 'Search plants, trees or mushrooms',
    _MapSearchScope.nodesAndTowns => 'Search nodes or towns',
  };

  String _mapSearchScopeLabel(_MapSearchScope scope) => switch (scope) {
    _MapSearchScope.all => 'All',
    _MapSearchScope.items => 'Items',
    _MapSearchScope.wildlife => 'Wildlife',
    _MapSearchScope.plantsAndTrees => 'Plants & trees',
    _MapSearchScope.nodesAndTowns => 'Nodes & towns',
  };

  IconData _mapSearchScopeIcon(_MapSearchScope scope) => switch (scope) {
    _MapSearchScope.all => Icons.manage_search_rounded,
    _MapSearchScope.items => Icons.inventory_2_outlined,
    _MapSearchScope.wildlife => Icons.pets_outlined,
    _MapSearchScope.plantsAndTrees => Icons.park_outlined,
    _MapSearchScope.nodesAndTowns => Icons.account_tree_outlined,
  };

  Widget _buildMapSearchScopeMenu(BuildContext context) {
    final active = _mapSearchScope;
    return PopupMenuButton<_MapSearchScope>(
      key: const ValueKey<String>('resource-map-search-scope'),
      tooltip: 'Filter map search: ${_mapSearchScopeLabel(active)}',
      initialValue: active,
      onSelected: _selectMapSearchScope,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_mapSearchScopeIcon(active), size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _mapSearchScopeLabel(active),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => <PopupMenuEntry<_MapSearchScope>>[
        for (final scope in _MapSearchScope.values)
          PopupMenuItem<_MapSearchScope>(
            value: scope,
            child: Row(
              children: <Widget>[
                Icon(_mapSearchScopeIcon(scope), size: 19),
                const SizedBox(width: 10),
                Expanded(child: Text(_mapSearchScopeLabel(scope))),
                if (scope == active) const Icon(Icons.check_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }

  bool _searchResultMatchesCurrentSource(BdoSearchResult result) {
    return switch (_materialSourceFilter) {
      _MaterialSourceFilter.all => true,
      _MaterialSourceFilter.manual => switch (result.kind) {
        BdoSearchKind.resource =>
          result.resourceId != null &&
              (widget.dataset.hasMappedManualSource(result.resourceId!) ||
                  widget.dataset
                      .fieldSourcesForResource(result.resourceId!)
                      .isNotEmpty),
        BdoSearchKind.fieldSource =>
          result.fieldSourceId != null &&
              widget.dataset.fieldSourcesById.containsKey(result.fieldSourceId),
        BdoSearchKind.workerNode => false,
        BdoSearchKind.gatheringSpot || BdoSearchKind.gatheringRoute => true,
      },
      _MaterialSourceFilter.worker => switch (result.kind) {
        BdoSearchKind.resource =>
          result.resourceId != null &&
              widget.dataset.hasWorkerSource(result.resourceId!),
        BdoSearchKind.fieldSource =>
          result.fieldSourceId != null &&
              (widget.dataset.fieldSourcesById[result.fieldSourceId!]?.products
                      .any(
                        (product) =>
                            widget.dataset.hasWorkerSource(product.resourceId),
                      ) ??
                  false),
        BdoSearchKind.workerNode => true,
        BdoSearchKind.gatheringSpot || BdoSearchKind.gatheringRoute => false,
      },
    };
  }

  List<BdoWorkerActivity> _workerActivitiesForQuery(String query) {
    if (_materialSourceFilter == _MaterialSourceFilter.manual) {
      return const <BdoWorkerActivity>[];
    }
    final normalized = query
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (normalized.length < 2) {
      return const <BdoWorkerActivity>[];
    }
    return BdoWorkerActivity.values
        .where((activity) => activity.label.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  void _submitSearch() {
    BdoSearchResult? firstResultOfKind(BdoSearchKind kind) {
      for (final result in _searchResults) {
        if (result.kind == kind) {
          return result;
        }
      }
      return null;
    }

    final activities = _workerActivitiesForQuery(_searchController.text);
    final normalizedQuery = _searchController.text.trim().toLowerCase();
    final exactActivities = activities.where(
      (activity) => activity.label.toLowerCase() == normalizedQuery,
    );
    if (exactActivities.isNotEmpty) {
      _selectWorkerActivity(exactActivities.first);
      return;
    }
    for (final kind in const <BdoSearchKind>[
      BdoSearchKind.fieldSource,
      BdoSearchKind.resource,
    ]) {
      final result = firstResultOfKind(kind);
      if (result != null) {
        _selectSearchResult(result);
        return;
      }
    }
    if (activities.isNotEmpty) {
      _selectWorkerActivity(activities.first);
      return;
    }
    for (final kind in const <BdoSearchKind>[
      BdoSearchKind.workerNode,
      BdoSearchKind.gatheringSpot,
      BdoSearchKind.gatheringRoute,
    ]) {
      final result = firstResultOfKind(kind);
      if (result != null) {
        _selectSearchResult(result);
        return;
      }
    }
  }

  void _runSuggestedSearch(String query) {
    final results = _searchResultsForCurrentSource(query);
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    BdoSearchResult? exactResource;
    BdoSearchResult? exactFieldSource;
    for (final result in results) {
      if (result.kind == BdoSearchKind.resource &&
          result.title.toLowerCase() == query.toLowerCase()) {
        exactResource = result;
        break;
      }
      if (result.kind == BdoSearchKind.fieldSource &&
          result.title.toLowerCase() == query.toLowerCase()) {
        exactFieldSource = result;
      }
    }
    if (exactResource != null) {
      _selectSearchResult(exactResource);
      return;
    }
    if (exactFieldSource != null) {
      _selectSearchResult(exactFieldSource);
      return;
    }
    setState(() {
      _desktopSheetExpanded = true;
      _searchResults = results;
      _searchResultsVisible = true;
    });
    _searchFocus.requestFocus();
  }

  void _openWorkerHub() {
    if (_desktopSheetExpanded &&
        _desktopMapMode == _DesktopMapMode.workers &&
        !_hasDetailSelection &&
        !_nodeNetworkPlannerOpen &&
        !_browseAllWorkerNodes &&
        !_housingDirectoryOpen &&
        _selectedResourceSection == null &&
        !_browseFavorites) {
      if (_workerMenuSection != null) {
        setState(() => _workerMenuSection = null);
        return;
      }
      _openMapHome();
      return;
    }
    _pushNavigationEntry();
    _showWorkerHub();
  }

  void _showWorkerHub() {
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _workerMenuSection = null;
      _gatherMenuSection = null;
      _cancelMarketValueCalculation();
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _workerActivityFilter = null;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = true;
      _showGathering = false;
      _showRoutes = false;
      _showConnections = true;
    });
  }

  void _returnFromHousingDirectory() {
    if (_navigationHistory.isNotEmpty) {
      _navigateBack();
      return;
    }
    _showWorkerHub();
  }

  void _navigateBackFromHousing() {
    if (_selectedHouseId != null) {
      setState(() => _selectedHouseId = null);
      return;
    }
    if (_selectedNodeId != null) {
      _navigateBack();
      return;
    }
    _returnFromHousingDirectory();
  }

  void _openWorkerOverview() {
    _pushNavigationEntry();
    _setWorkerOverview(true);
  }

  void _openHousingDirectory() {
    if (widget.lodgingDataset == null) {
      return;
    }
    if (!_housingDirectoryOpen) {
      _pushNavigationEntry();
    }
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _desktopTaskSurfaceCollapsed = false;
      _investNodeMode = false;
      _nodeNetworkSaveMessage = null;
      _cancelMarketValueCalculation();
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _storagePlannerTownNodeId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _housingDirectoryOpen = true;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = true;
      _showGathering = false;
      _showRoutes = false;
      _showConnections = true;
    });
  }

  Future<void> _openSetupScreenshotImport({
    BdoSetupScreenshotImportMode? initialMode,
    String? initialTownNodeId,
  }) async {
    final picker = widget.setupScreenshotPicker;
    if (picker == null) {
      return;
    }
    final selection = await showDialog<BdoSetupScreenshotImportSelection>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MapDialogScope(
        child: BdoSetupScreenshotImportDialog(
          dataset: widget.dataset,
          lodgingDataset: widget.lodgingDataset,
          picker: picker,
          clipboardReader: widget.setupScreenshotClipboardReader,
          activeNodeRecordingLauncher: widget.activeNodeRecordingLauncher,
          activeNodeRecordingFinder: widget.activeNodeRecordingFinder,
          activeNodeRecordingPicker: widget.activeNodeRecordingPicker,
          activeNodeRecordingScanner: widget.activeNodeRecordingScanner,
          existingWorkerNodeIds: _nodeNetworkPreferences.currentNodeIds,
          existingHouseIds: _nodeNetworkPreferences.currentOwnedHouseIds,
          initialMode: initialMode,
          initialTownNodeId: initialTownNodeId,
        ),
      ),
    );
    if (!mounted || selection == null) {
      return;
    }
    try {
      _applySetupScreenshotImport(selection);
    } on Object {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => _MapDialogScope(
          child: DraggableAlertDialog(
            identity: 'setup-screenshot-import-error',
            estimatedSize: const Size(440, 230),
            title: const Text('Could not add that screenshot'),
            content: const Text(
              'The reviewed choices could not be merged safely. Your saved '
              'setup was not changed. Reopen the screenshot and leave '
              'uncertain icons unchecked.',
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _applySetupScreenshotImport(
    BdoSetupScreenshotImportSelection selection,
  ) {
    final previousPreferences = _nodeNetworkPreferences;
    var preferences = previousPreferences;
    final lodgingDataset = widget.lodgingDataset;
    if (lodgingDataset != null) {
      for (final confirmation in selection.confirmations) {
        final persistableTargetIds = confirmation.targetIds.where((id) {
          final target = confirmation.analysis.targetsById[id]?.target;
          if (target == null) {
            return false;
          }
          if (target.kind == BdoScreenshotTargetKind.house) {
            return lodgingDataset.housesById.containsKey(id);
          }
          final node = widget.dataset.workerNodesById[id];
          return node != null && !_isNaturalWorkerRoot(node);
        }).toSet();
        if (persistableTargetIds.isEmpty) {
          continue;
        }
        final merge = BdoScreenshotImportMerge.mergeConfirmedActiveTargets(
          current: preferences,
          analysis: confirmation.analysis,
          confirmedActiveTargetIds: persistableTargetIds,
          lodgingDataset: lodgingDataset,
        );
        preferences = merge.preferences;
      }
    }
    // Recording imports and any future catalog-backed import can supply exact
    // worker-node IDs without a screenshot analysis object. Always merge those
    // IDs additively; an import must never disconnect the player's saved setup.
    preferences = preferences.copyWith(
      currentNodeIds: <String>{
        ...preferences.currentNodeIds,
        for (final id in selection.workerNodeIds)
          if (widget.dataset.workerNodesById[id] case final node?
              when !_isNaturalWorkerRoot(node))
            id,
      },
    );

    final normalizedNodeIds = <String>{
      for (final id in preferences.currentNodeIds)
        if (widget.dataset.workerNodesById[id] case final node?
            when !_isNaturalWorkerRoot(node))
          id,
    };
    preferences = preferences.copyWith(currentNodeIds: normalizedNodeIds);
    final addedNodeIds = normalizedNodeIds.difference(
      previousPreferences.currentNodeIds,
    );
    final allAddedHouseIds = preferences.currentOwnedHouseIds.difference(
      previousPreferences.currentOwnedHouseIds,
    );
    final addedHouseIds = allAddedHouseIds.intersection(selection.houseIds);
    final addedPrerequisiteHouseIds = allAddedHouseIds.difference(
      addedHouseIds,
    );
    _replaceNodeNetworkPreferences(preferences, rebuildPlan: false);

    if (selection.mode == BdoSetupScreenshotImportMode.workerNodes) {
      final recognizedNodeIds = <String>{
        for (final id in selection.workerNodeIds)
          if (normalizedNodeIds.contains(id)) id,
      };
      final message = addedNodeIds.isEmpty
          ? recognizedNodeIds.isEmpty
                ? 'No invested worker nodes were selected from the screenshot.'
                : 'The selected worker nodes were already in your saved setup.'
          : 'Added ${addedNodeIds.length} invested '
                '${addedNodeIds.length == 1 ? 'node' : 'nodes'} from the '
                'screenshot. Your existing setup was kept.';
      setState(() {
        _currentNodeDraftIds =
            _nodeNetworkPlannerOpen &&
                _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent
            ? <String>{..._currentNodeDraftIds, ...addedNodeIds}
            : <String>{...normalizedNodeIds};
        _explicitWorkerEmphasisNodeIds = recognizedNodeIds;
        _workerEmphasisRevision += 1;
        _showWorkerNodes = true;
        _showConnections = true;
        _nodeNetworkSaveMessage = message;
      });
      if (recognizedNodeIds.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _fitBrowseOverview(
            recognizedNodeIds
                .map((id) => widget.dataset.workerNodesById[id])
                .whereType<BdoWorkerNode>()
                .map((node) => node.location.mapPoint),
          );
        });
      }
      return;
    }

    final highlightedHouseIds = <String>{
      ...selection.houseIds,
      ...addedPrerequisiteHouseIds,
    };
    final selectedTownNodeId =
        selection.townNodeId ??
        selection.houseIds
            .map((id) => lodgingDataset?.housesById[id]?.townNodeId)
            .whereType<String>()
            .firstOrNull;
    final message = addedHouseIds.isEmpty && addedPrerequisiteHouseIds.isEmpty
        ? selection.houseIds.isEmpty
              ? 'No owned houses were selected from the screenshot.'
              : 'The selected houses were already in your saved setup.'
        : 'Added ${addedHouseIds.length} owned '
              '${addedHouseIds.length == 1 ? 'house' : 'houses'}'
              '${addedPrerequisiteHouseIds.isEmpty ? '' : ' and ${addedPrerequisiteHouseIds.length} required ${addedPrerequisiteHouseIds.length == 1 ? 'prerequisite' : 'prerequisites'}'}. '
              'Choose each house use when you know it.';
    if (selectedTownNodeId != null) {
      _openHousingTown(selectedTownNodeId);
    }
    setState(() {
      _screenshotImportedHouseIds = highlightedHouseIds;
      _screenshotHousePulseRevision += 1;
      _selectedHouseId = selection.houseIds.firstOrNull;
      _houseUsageFilter = _HouseUsageFilter.all;
      _nodeNetworkSaveMessage = message;
    });
    final town = selectedTownNodeId == null
        ? null
        : lodgingDataset?.townsByNodeId[selectedTownNodeId];
    if (town != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fitHousingTown(town);
        }
      });
    }
  }

  void _openRoyalWorkshop() {
    if (!_royalWorkshopEnabled) {
      return;
    }
    if (!_royalWorkshopOpen) {
      _pushNavigationEntry();
    }
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _cancelMarketValueCalculation();
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _royalWorkshopOpen = true;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = true;
      _showGathering = false;
      _showRoutes = false;
      _showConnections = true;
    });
  }

  void _updateRoyalWorkshopPlan(BdoRoyalWorkshopPlan plan) {
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(royalWorkshopPlan: plan),
      rebuildPlan: false,
    );
  }

  void _toggleManagerMarker({
    required String id,
    required String name,
    required BdoWorldPoint location,
    required String contextLabel,
  }) {
    setState(() {
      _markedManager = _markedManager?.id == id
          ? null
          : (
              id: id,
              name: name,
              location: location,
              contextLabel: contextLabel,
            );
    });
  }

  void _markRoyalWorkshopManager(BdoRoyalWorkshopArea area) {
    _toggleManagerMarker(
      id: 'royal:${area.id}',
      name: area.managerName,
      location: BdoWorldPoint(area.managerWorldX, area.managerWorldZ),
      contextLabel: '${area.name} Royal Workshop manager',
    );
  }

  void _openYukjoHousingFromRoyalWorkshop() {
    _openHousingTown('1853');
  }

  void _openHousingTown(String nodeId) {
    final town = widget.lodgingDataset?.townsByNodeId[nodeId];
    if (town == null) {
      return;
    }
    _openHousingDirectory();
    if (_selectedNodeId != nodeId) {
      _pushNavigationEntry();
    }
    setState(() {
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _selectedNodeId = nodeId;
      _selectedHouseId = null;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
    });
  }

  void _openGatherChecklist() {
    if (!_gatherChecklistOpen) {
      _pushNavigationEntry();
    }
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _royalWorkshopOpen = false;
      _housingDirectoryOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _gatherChecklistOpen = true;
    });
  }

  void _openGatherPlanShortlist() {
    if (!_gatherPlanShortlistOpen) {
      _pushNavigationEntry();
    }
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = true;
      _royalWorkshopOpen = false;
      _housingDirectoryOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _materialSourceFilter = _MaterialSourceFilter.manual;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = false;
      _showGathering = true;
      _showRoutes = true;
      _showConnections = false;
    });
  }

  void _openNodeNetworkPlanner() {
    if (!_nodeNetworkPlannerOpen) {
      _pushNavigationEntry();
    }
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = true;
      _layersMenuOpen = false;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _royalWorkshopOpen = false;
      _housingDirectoryOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = true;
      _showConnections = true;
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.home;
      _currentNodeDraftIds = <String>{
        ..._nodeNetworkPreferences.currentNodeIds,
      };
      _selectedMarketValuePath = null;
      _nodeNetworkSaveMessage = null;
      _nodeNetworkPlannerOpen = true;
    });
  }

  bool get _currentNodeDraftIsDirty =>
      !setEquals(_currentNodeDraftIds, _nodeNetworkPreferences.currentNodeIds);

  void _cancelMarketValueCalculation() {
    _marketValueCalculationGeneration += 1;
    _marketValueCalculating = false;
  }

  void _showNodePlannerHome() {
    setState(() {
      _cancelMarketValueCalculation();
      if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review) {
        _invalidateNodeNetworkCalculation(clearResult: true);
      }
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.home;
      _selectedMarketValuePath = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _showWorkerNodes = true;
      _showConnections = true;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = null;
    });
  }

  void _leaveNodePlannerGoal() {
    final hasTaskParent =
        _navigationHistory.isNotEmpty &&
        !_navigationHistory.last.nodeNetworkPlannerOpen;
    if (_compactLayout && !hasTaskParent) {
      _showNodePlannerHome();
      return;
    }
    _cancelMarketValueCalculation();
    _navigateBack();
  }

  void _openNodeTargets() {
    setState(() {
      _cancelMarketValueCalculation();
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.targets;
      _recipeNodeRecommendation = null;
      _selectedMarketValuePath = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _showWorkerNodes = true;
      _showConnections = false;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = null;
      _nodeTargetSettingsExpanded = false;
    });
    _scheduleNodeTargetPreview();
  }

  bool _isNaturalWorkerRoot(BdoWorkerNode node) =>
      node.contributionPoints == 0 &&
      (node.nodeType == 'City' || node.nodeType == 'Town');

  bool _showsAsNeutralOrientationNode(BdoWorkerNode node) =>
      node.contributionPoints > 0 ||
      node.isResourceNode ||
      _isNaturalWorkerRoot(node);

  bool _nodeIconIsActive(BdoWorkerNode node) {
    final plannedKind = _visibleNodeNetworkChangeKinds[node.id];
    return _isNaturalWorkerRoot(node) ||
        _nodeNetworkPreferences.currentNodeIds.contains(node.id) ||
        plannedKind == BdoNodeNetworkChangeKind.retained ||
        plannedKind == BdoNodeNetworkChangeKind.connect;
  }

  void _toggleCurrentNode(BdoWorkerNode node, {bool focus = false}) {
    if (_isNaturalWorkerRoot(node)) {
      setState(() {
        _nodeNetworkInputError =
            '${node.siteName} is a free worker-town root. Choose worker towns '
            'separately; only mark nodes you invested CP in.';
      });
      return;
    }
    setState(() {
      final next = <String>{..._currentNodeDraftIds};
      if (!next.add(node.id)) {
        next.remove(node.id);
      }
      _currentNodeDraftIds = next;
      _selectedNodeId = node.id;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = null;
    });
    if (focus && !_viewport.isEmpty) {
      _showPointAvoidingDetails(node.location);
    }
  }

  void _addCurrentWorkerDestination(BdoWorkerNode node, {bool focus = true}) {
    if (!node.isProductionNode) {
      _toggleCurrentNode(node, focus: focus);
      return;
    }
    final result = const BdoProductionNodePathCostService().calculate(
      data: widget.dataset,
      request: BdoProductionNodePathRequest(
        targetNodeId: node.id,
        currentNodeIds: _currentNodeDraftIds,
        allowedRootNodeIds: _effectiveNetworkRootNodeIds,
      ),
    );
    final path = result.minimumIncrementalPath ?? result.minimumTotalPath;
    if (path == null) {
      setState(() {
        _selectedNodeId = node.id;
        _nodeNetworkInputError =
            result.diagnostics.firstOrNull?.message ??
            'A complete path to ${node.siteName} could not be found.';
      });
      return;
    }
    final next = <String>{
      ..._currentNodeDraftIds,
      for (final id in path.orderedNodeIds)
        if (widget.dataset.workerNodesById[id] case final routeNode?
            when !_isNaturalWorkerRoot(routeNode))
          id,
    };
    final addedCount = next.length - _currentNodeDraftIds.length;
    setState(() {
      _currentNodeDraftIds = next;
      _selectedNodeId = node.id;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = path;
      _showConnections = true;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = addedCount == 0
          ? '${node.siteName} is already connected in this draft.'
          : 'Added ${node.siteName} and its complete path ($addedCount '
                '${addedCount == 1 ? 'node' : 'nodes'}).';
    });
    if (focus && !_viewport.isEmpty) {
      _fitBrowseOverview(
        path.orderedNodeIds
            .map((id) => widget.dataset.workerNodesById[id]?.location.mapPoint)
            .whereType<BdoMapPoint>(),
      );
    }
  }

  void _clearCurrentNodeDraft() {
    setState(() {
      _currentNodeDraftIds = <String>{};
      _selectedNodeId = null;
      _selectedQuickNodePath = null;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = 'Draft cleared. Your saved setup is unchanged.';
    });
  }

  void _saveCurrentNodeDraft() {
    final currentNodeIds = Set<String>.unmodifiable(_currentNodeDraftIds);
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: currentNodeIds,
    );
    setState(() {
      _nodeNetworkPreferences = preferences;
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.home;
      _desktopSheetExpanded = true;
      _selectedNodeId = null;
      _selectedQuickNodePath = null;
      _nodeNetworkSaveMessage =
          'In-game network saved in the planner. Nothing was changed in BDO.';
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
  }

  Future<void> _cancelCurrentNodeEditing() async {
    if (_currentNodeDraftIsDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => _MapDialogScope(
          child: DraggableAlertDialog(
            identity: 'discard-current-node-draft',
            estimatedSize: const Size(420, 230),
            title: const Text('Discard node changes?'),
            content: const Text(
              'Your saved in-game network will stay as it was before editing.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                key: const ValueKey<String>(
                  'resource-map-discard-current-node-draft',
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || discard != true) {
        return;
      }
    }
    setState(() {
      _currentNodeDraftIds = <String>{
        ..._nodeNetworkPreferences.currentNodeIds,
      };
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.home;
    });
  }

  void _handleWorkerNodeTap(BdoWorkerNode node, {bool focus = false}) {
    if (_investNodeMode) {
      _toggleNodeInCurrentSetup(node);
      return;
    }
    if (_nodeNetworkPlannerOpen &&
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent) {
      _addCurrentWorkerDestination(node, focus: focus);
      return;
    }
    _selectNode(node, focus: focus);
  }

  void _openMapSearch() {
    _setDesktopSheetExpanded(true, focusSearch: true);
  }

  void _searchWholeMap(String query, {bool? showResults}) {
    // The one visible search always searches the whole map, regardless of
    // which tool or acquisition source was open before it.
    _materialSourceFilter = _MaterialSourceFilter.all;
    _mapSearchScope = _MapSearchScope.all;
    _search(query, showResults: showResults);
  }

  void _openMaterialDiscovery() {
    _pushNavigationEntry();
    _searchFocus.unfocus();
    setState(() {
      _materialCatalogOpen = true;
      _desktopSheetExpanded = true;
      _desktopTaskSurfaceCollapsed = false;
      _materialSourceFilter = _MaterialSourceFilter.all;
      _mapSearchScope = _MapSearchScope.all;
    });
  }

  void _clearSearchQuery() {
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
    });
  }

  void _openMapHome() {
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    _navigationHistory.clear();
    setState(() {
      _materialCatalogOpen = false;
      _mapSearchScope = _MapSearchScope.all;
      _workerMenuSection = null;
      _gatherMenuSection = null;
      _investNodeMode = false;
      _cancelMarketValueCalculation();
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopTaskSurfaceCollapsed = false;
      _desktopSheetExpanded = false;
      _layersMenuOpen = false;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _storagePlannerTownNodeId = null;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.home;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _showConnections = false;
      _materialSourceFilter = _MaterialSourceFilter.all;
      _selectedResourceSection = null;
      _browseFavorites = false;
    });
  }

  void _setWorkerOverview(bool enable) {
    _searchFocus.unfocus();
    setState(() {
      _cancelMarketValueCalculation();
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _royalWorkshopOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = enable;
      _workerOverviewSelectionMade = false;
      _workerActivityFilter = null;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = true;
      _showConnections = false;
    });
  }

  void _selectWorkerActivity(BdoWorkerActivity? activity) {
    if (_browseAllWorkerNodes &&
        _workerOverviewSelectionMade &&
        _workerActivityFilter == activity) {
      return;
    }
    _pushNavigationEntry();
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _workerActivityFilter = activity;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _browseAllWorkerNodes = true;
      _workerOverviewSelectionMade = true;
      _materialSourceFilter = _MaterialSourceFilter.worker;
      _selectedResourceSection = null;
      _browseFavorites = false;
      _showWorkerNodes = true;
      _showConnections = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
    });
    _fitBrowseOverview(
      widget.dataset.workerNodes
          .where(
            (node) =>
                node.isResourceNode &&
                (activity == null || node.activity == activity),
          )
          .map((node) => node.location.mapPoint),
    );
  }

  void _fitBrowseOverview(Iterable<BdoMapPoint> points) {
    final bounds = _boundsForPoints(points.toList(growable: false));
    if (bounds == null || _viewport.isEmpty) {
      return;
    }
    _fitBoundsAvoidingDetails(bounds, padding: 58, maximumZoom: 3.4);
  }

  void _replaceNodeNetworkPreferences(
    BdoNodeNetworkPreferences preferences, {
    bool rebuildPlan = true,
  }) {
    preferences = _withPermanentMapDisplay(preferences);
    if (_nodeNetworkPreferences.sameValuesAs(preferences)) {
      return;
    }
    final shouldRebuild =
        rebuildPlan &&
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review;
    final shouldRecalculateMarket =
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue;
    setState(() {
      _nodeNetworkPreferences = preferences;
      _recipeNodeRecommendation = null;
      _nodeNetworkInputError = null;
      _nodeNetworkCalculationError = null;
      _nodeNetworkSaveMessage = null;
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    if (shouldRebuild) {
      unawaited(_rebuildNodeNetworkPlan());
    } else if (shouldRecalculateMarket) {
      _calculateMarketValueRecommendations();
    } else if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.targets) {
      _scheduleNodeTargetPreview();
    }
  }

  void _setMapDisplayPreferences(BdoNodeNetworkPreferences preferences) {
    preferences = _withPermanentMapDisplay(preferences);
    if (_nodeNetworkPreferences.sameValuesAs(preferences)) {
      return;
    }
    setState(() => _nodeNetworkPreferences = preferences);
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
  }

  void _toggleWorkerConnections() {
    final enabling =
        !(_showAllNodes && _nodeNetworkPreferences.showAllNodeConnections);
    _setMapDisplayPreferences(
      _nodeNetworkPreferences.copyWith(
        showAllMapNodes: enabling ? true : _showAllNodes,
        showAllNodeConnections: enabling,
      ),
    );
  }

  Future<void> _openShopLodgingSetup(LodgingTown town) async {
    final configured =
        _nodeNetworkPreferences.townWorkerCapacitiesByNodeId[town.townNodeId];
    final hasBreakdown = configured?.hasBonusLodgingBreakdown ?? false;
    final knownMappedSlots =
        town.baseWorkerSlots + _ownedLodgingCapacityForTown(town);
    // A legacy save can include vacant lodging that predates the house/shop
    // breakdown. Seed the difference as "Other" during migration so merely
    // opening and saving this editor cannot erase usable capacity.
    final legacyUnmappedSlots =
        configured != null && !configured.usesKnownTownLodging
        ? math.max(
            configured.availableWorkerCount +
                configured.freeLodgingSlotCount -
                knownMappedSlots,
            0,
          )
        : 0;
    final initial = WorkerLodgingShopSetup(
      pearlPurchased: configured?.pearlLodgingPurchasedCount ?? 0,
      loyaltyPurchased: configured?.loyaltyLodgingPurchasedCount ?? 0,
      otherBonus: configured?.otherBonusLodgingSlotCount ?? legacyUnmappedSlots,
    );
    WorkerLodgingShopSetup? saved;
    await showDialog<void>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: WorkerLodgingShopSetupDialog(
          townName: town.name,
          catalogTown:
              WorkerLodgingShopCatalog.findTown(town.townNodeId) ??
              WorkerLodgingShopCatalog.findTown(town.name),
          initialValue: initial,
          legacyUnsplitBonus: hasBreakdown
              ? 0
              : configured?.bonusLodgingSlotCount ?? legacyUnmappedSlots,
          onSave: (value) => saved = value,
        ),
      ),
    );
    if (!mounted || saved == null) {
      return;
    }
    final setup = saved!;
    final hired =
        configured?.hiredWorkerCount ?? configured?.availableWorkerCount ?? 0;
    final totalKnownSlots =
        town.baseWorkerSlots +
        _ownedLodgingCapacityForTown(town) +
        setup.totalBonus;
    final nextCapacity = BdoTownWorkerCapacity(
      availableWorkerCount: hired,
      freeLodgingSlotCount: math.max(totalKnownSlots - hired, 0),
      hiredWorkerCount: hired,
      bonusLodgingSlotCount: setup.totalBonus,
      pearlLodgingPurchasedCount: setup.pearlPurchased,
      loyaltyLodgingPurchasedCount: setup.loyaltyPurchased,
      otherBonusLodgingSlotCount: setup.otherBonus,
    );
    final capacities = Map<String, BdoTownWorkerCapacity>.of(
      _nodeNetworkPreferences.townWorkerCapacitiesByNodeId,
    )..[town.townNodeId] = nextCapacity;
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(
        townWorkerCapacitiesByNodeId: capacities,
      ),
    );
  }

  void _selectHouse(LodgingHouse house) {
    // House selection is an inspection action, not a camera command. Keep all
    // map movement behind the explicit town/route fit controls so selecting a
    // marker, list row, recommendation, or lodging-summary entry can never
    // surprise the user by changing their view.
    setState(() {
      _selectedHouseId = house.id;
      _houseSelectionPulseRevision += 1;
      _desktopSheetExpanded = true;
    });
  }

  Widget _revealSelectedHouse({
    required String? houseId,
    required Widget child,
  }) {
    if (houseId == null || houseId != _selectedHouseId) {
      return child;
    }
    return _HouseSelectionPulse(
      key: ValueKey<String>('resource-map-house-selection-pulse-$houseId'),
      revision: _houseSelectionPulseRevision,
      child: child,
    );
  }

  List<LodgingHouse> _housePathTo(LodgingTown town, LodgingHouse house) {
    final path = <LodgingHouse>[];
    final visited = <String>{};
    LodgingHouse? current = house;
    while (current != null && visited.add(current.id)) {
      path.add(current);
      final prerequisiteId = current.prerequisiteHouseId;
      current = prerequisiteId == null ? null : town.housesById[prerequisiteId];
    }
    return path.reversed.toList(growable: false);
  }

  Set<String> _houseBranchIds(LodgingTown town, LodgingHouse root) {
    final branch = <String>{root.id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final house in town.houses) {
        if (house.prerequisiteHouseId case final prerequisiteId?
            when branch.contains(prerequisiteId)) {
          changed = branch.add(house.id) || changed;
        }
      }
    }
    return branch;
  }

  Set<String> _visibleHousingHouseIds(LodgingTown town) {
    if (_housingDirectoryOpen &&
        !_browseAllTownHouses &&
        _goalsForTown(town).any((goal) => goal.amount > 0)) {
      final visible = <String>{...?_townInvestmentFor(town)?.requiredHouseIds};
      final selected = town.housesById[_selectedHouseId];
      if (selected != null) {
        visible.addAll(_housePathTo(town, selected).map((h) => h.id));
      }
      return visible;
    }
    if (_houseUsageFilter == _HouseUsageFilter.all) {
      return town.housesById.keys.toSet();
    }
    final visible = <String>{};
    for (final house in town.houses.where(_houseMatchesUsageFilter)) {
      visible.addAll(_housePathTo(town, house).map((entry) => entry.id));
    }
    final selectedId = _selectedHouseId;
    if (selectedId != null) {
      final selected = town.housesById[selectedId];
      if (selected != null) {
        visible.addAll(_housePathTo(town, selected).map((entry) => entry.id));
      }
    }
    return visible;
  }

  void _investHouse(LodgingTown town, LodgingHouse house, {int? usageTypeId}) {
    final owned = <String>{..._nodeNetworkPreferences.currentOwnedHouseIds};
    final usages = <String, int>{
      ..._nodeNetworkPreferences.currentHouseUsageTypeIds,
    };
    owned.addAll(_housePathTo(town, house).map((entry) => entry.id));
    if (usageTypeId != null && house.usagesByTypeId.containsKey(usageTypeId)) {
      usages[house.id] = usageTypeId;
    } else if (house.usages.length == 1) {
      usages[house.id] = house.usages.single.typeId;
    }
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(
        currentOwnedHouseIds: owned,
        currentHouseUsageTypeIds: usages,
      ),
      rebuildPlan: false,
    );
  }

  void _toggleOwnedHouse(LodgingHouse house) {
    final town = widget.lodgingDataset?.townsByNodeId[house.townNodeId];
    if (town == null) {
      return;
    }
    final owned = <String>{..._nodeNetworkPreferences.currentOwnedHouseIds};
    final usages = <String, int>{
      ..._nodeNetworkPreferences.currentHouseUsageTypeIds,
    };
    if (owned.contains(house.id)) {
      final removedIds = _houseBranchIds(town, house);
      owned.removeAll(removedIds);
      usages.removeWhere((id, _) => removedIds.contains(id));
      _replaceNodeNetworkPreferences(
        _nodeNetworkPreferences.copyWith(
          currentOwnedHouseIds: owned,
          currentHouseUsageTypeIds: usages,
        ),
        rebuildPlan: false,
      );
      return;
    }
    _investHouse(town, house);
  }

  void _setOwnedHouseUsage(LodgingHouse house, int typeId) {
    if (!house.usagesByTypeId.containsKey(typeId)) {
      return;
    }
    final town = widget.lodgingDataset?.townsByNodeId[house.townNodeId];
    if (town == null) {
      return;
    }
    _investHouse(town, house, usageTypeId: typeId);
  }

  bool _houseMatchesUsageFilter(LodgingHouse house) {
    return switch (_houseUsageFilter) {
      _HouseUsageFilter.all => true,
      _HouseUsageFilter.lodging => house.supportsUsage(1),
      _HouseUsageFilter.storage => house.supportsUsage(2),
      _HouseUsageFilter.stable => house.supportsUsage(3),
      _HouseUsageFilter.workshops => house.usages.any(
        (usage) => usage.typeId >= 4,
      ),
    };
  }

  void _fitHousingTown(LodgingTown town) {
    if (_viewport.isEmpty || town.houses.isEmpty) {
      return;
    }
    final bounds = _boundsForPoints(
      town.houses.map(_houseMapPoint).toList(growable: false),
    );
    if (bounds == null) {
      return;
    }
    _fitBoundsAvoidingDetails(
      bounds.inflate(700),
      padding: 44,
      maximumZoom: 7.7,
    );
  }

  void _showLodgingTownPlan(LodgingPlan plan) {
    final town = widget.lodgingDataset?.townsByNodeId[plan.townNodeId];
    final node = widget.dataset.workerNodesById[plan.townNodeId];
    if (town == null || node == null) {
      return;
    }
    setState(() {
      _selectedNodeId = node.id;
      _selectedHouseId = plan.newlyRequiredHouseIds.firstOrNull;
      _dismissedPlannedLodgingSummaryTownNodeId = null;
      _houseUsageFilter = _HouseUsageFilter.all;
      _showConnections = true;
    });
    final plannedHouses = plan.fullHouseClosureIds
        .map((id) => town.housesById[id])
        .whereType<LodgingHouse>()
        .toList(growable: false);
    if (plannedHouses.isEmpty) {
      _fitHousingTown(town);
    } else {
      final bounds = _boundsForPoints(
        plannedHouses.map(_houseMapPoint).toList(growable: false),
      );
      if (bounds == null) {
        _fitHousingTown(town);
      } else {
        _fitBoundsAvoidingDetails(
          bounds.inflate(320),
          padding: 46,
          maximumZoom: 7.35,
        );
      }
    }
  }

  void _showHousingTown(LodgingTown town) {
    final node = widget.dataset.workerNodesById[town.townNodeId];
    if (node == null) {
      return;
    }
    setState(() {
      _selectedNodeId = node.id;
      _selectedHouseId = null;
      if (_storagePlannerTownNodeId != node.id) {
        _storagePlannerTownNodeId = null;
      }
      _showConnections = true;
    });
    _fitHousingTown(town);
  }

  void _changeNodeTarget(BdoResourceDefinition resource, int nextCount) {
    final available = _reachableWorkerNodeCount(resource);
    final normalized = nextCount.clamp(0, available);
    final counts = Map<String, int>.of(
      _nodeNetworkPreferences.desiredResourceNodeCounts,
    );
    if (normalized == 0) {
      counts.remove(resource.id);
    } else {
      counts[resource.id] = normalized;
    }
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(desiredResourceNodeCounts: counts),
    );
  }

  int _reachableWorkerNodeCount(BdoResourceDefinition resource) => widget
      .dataset
      .workerNodesForResource(resource.id)
      .map((node) => node.id)
      .toSet()
      .intersection(_reachableWorkerProductionNodeIds())
      .length;

  void _scheduleNodeTargetPreview() {
    _nodeTargetPreviewDebounce?.cancel();
    final generation = ++_nodeTargetPreviewGeneration;
    if (_nodeNetworkPlannerPage != _NodeNetworkPlannerPage.targets ||
        _nodeNetworkPreferences.desiredResourceNodeCounts.isEmpty) {
      if (_nodeTargetPreviewResult != null || _nodeTargetPreviewCalculating) {
        setState(() {
          _nodeTargetPreviewResult = null;
          _nodeTargetPreviewLodgingPlan = null;
          _nodeTargetPreviewCalculating = false;
        });
      }
      return;
    }
    setState(() {
      _nodeTargetPreviewCalculating = true;
      _nodeTargetPreviewResult = null;
      _nodeTargetPreviewLodgingPlan = null;
    });
    _nodeTargetPreviewDebounce = Timer(
      const Duration(milliseconds: 190),
      () => unawaited(_calculateNodeTargetPreview(generation)),
    );
  }

  Future<void> _calculateNodeTargetPreview(int generation) async {
    final request = BdoNodeNetworkRequest(
      contributionPointBudget: _nodeNetworkPreferences.contributionPointBudget,
      desiredResourceNodeCounts:
          _nodeNetworkPreferences.desiredResourceNodeCounts,
      currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
      rootNodeIds: _effectiveNetworkRootNodeIds,
    );
    final workerFuture = _nodeNetworkWorkerFuture ??=
        BdoNodeNetworkWorker.start(widget.dataset);
    try {
      final worker = await workerFuture;
      final response = await worker.optimize(
        request: request,
        generation: generation,
      );
      if (!mounted ||
          generation != _nodeTargetPreviewGeneration ||
          _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.targets) {
        return;
      }
      final staffing = _planNodeNetworkStaffing(response.result.plan);
      setState(() {
        _nodeTargetPreviewCalculating = false;
        _nodeTargetPreviewResult = response.result;
        _nodeTargetPreviewLodgingPlan = staffing.lodging;
      });
    } on Object {
      if (!mounted ||
          generation != _nodeTargetPreviewGeneration ||
          _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.targets) {
        return;
      }
      if (identical(_nodeNetworkWorkerFuture, workerFuture)) {
        _nodeNetworkWorkerFuture = null;
      }
      setState(() {
        _nodeTargetPreviewCalculating = false;
        _nodeTargetPreviewResult = null;
        _nodeTargetPreviewLodgingPlan = null;
      });
    }
  }

  Map<String, int> _currentProductionCountsByResourceId() {
    final productionNodesByResource = <String, Set<String>>{};
    for (final nodeId in _nodeNetworkPreferences.currentNodeIds) {
      final node = widget.dataset.workerNodesById[nodeId];
      if (node == null || !node.isProductionNode) {
        continue;
      }
      for (final output in node.outputs) {
        (productionNodesByResource[output.resourceId] ??= <String>{}).add(
          node.id,
        );
      }
    }
    return <String, int>{
      for (final entry in productionNodesByResource.entries)
        entry.key: entry.value.length,
    };
  }

  void _useCurrentProductionCountsAsTargets() {
    final currentCounts = _currentProductionCountsByResourceId();
    if (currentCounts.isEmpty) {
      return;
    }
    final nextCounts = <String, int>{
      ..._nodeNetworkPreferences.desiredResourceNodeCounts,
    };
    for (final entry in currentCounts.entries) {
      final resource = widget.dataset.resourcesById[entry.key];
      if (resource == null) {
        continue;
      }
      final available = _reachableWorkerNodeCount(resource);
      if (available > 0) {
        nextCounts[entry.key] = math.max(
          nextCounts[entry.key] ?? 0,
          entry.value.clamp(1, available),
        );
      }
    }
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(desiredResourceNodeCounts: nextCounts),
    );
    setState(() => _nodeTargetView = _NodeTargetView.current);
  }

  void _changeRecipeReviewNodeTarget(
    BdoResourceDefinition resource,
    int nextCount,
  ) {
    final available = _reachableWorkerNodeCount(resource);
    final normalized = nextCount.clamp(0, available);
    final counts = Map<String, int>.of(
      _nodeNetworkPreferences.desiredResourceNodeCounts,
    );
    if (normalized == 0) {
      counts.remove(resource.id);
    } else {
      counts[resource.id] = normalized;
    }

    var nextSelection = _plannerNeedSelection;
    if (normalized == 0) {
      for (final group in nextSelection.groups) {
        for (final material in group.materials) {
          if (_plannerNeedMatchesResource(material.need, resource) &&
              nextSelection.isMaterialSelected(
                groupId: group.id,
                materialId: material.id,
              )) {
            nextSelection = nextSelection.withMaterialSelected(
              groupId: group.id,
              materialId: material.id,
              selected: false,
            );
          }
        }
      }
    }

    final currentRecommendation = _recipeNodeRecommendation;
    final nextRecommendation = currentRecommendation == null
        ? null
        : BdoRecipeNodeRecommendation(
            coverageTargets: <BdoRecipeNodeCoverageTarget>[
              for (final target in currentRecommendation.coverageTargets)
                if (counts[target.resourceId] case final requested?)
                  BdoRecipeNodeCoverageTarget(
                    resourceId: target.resourceId,
                    resourceName: target.resourceName,
                    gameItemId: target.gameItemId,
                    requestedDistinctProductionNodeCount: requested,
                    availableDistinctProductionNodeCount:
                        target.availableDistinctProductionNodeCount,
                    totalRecipeShortageQuantity:
                        target.totalRecipeShortageQuantity,
                    hasRecipeShortage: target.hasRecipeShortage,
                    hasExplicitMaterialTarget: target.hasExplicitMaterialTarget,
                    inputLabels: target.inputLabels,
                    recipeShortageInputCount: target.recipeShortageInputCount,
                    explicitMaterialTargetInputCount:
                        target.explicitMaterialTargetInputCount,
                  ),
            ],
            uncoveredMaterials: currentRecommendation.uncoveredMaterials,
            networkResult: null,
          );
    final preferences = _nodeNetworkPreferences.copyWith(
      desiredResourceNodeCounts: counts,
    );
    if (_nodeNetworkPreferences.sameValuesAs(preferences)) {
      return;
    }
    setState(() {
      _plannerNeedSelection = nextSelection;
      _nodeNetworkPreferences = preferences;
      _recipeNodeRecommendation = nextRecommendation;
      _nodeNetworkInputError = null;
      _nodeNetworkCalculationError = null;
      _nodeNetworkSaveMessage = null;
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    unawaited(_rebuildNodeNetworkPlan());
  }

  bool _plannerNeedMatchesResource(
    BdoPlannerMaterialNeed need,
    BdoResourceDefinition resource,
  ) {
    final needGameItemId = need.gameItemId;
    if (needGameItemId != null && needGameItemId == resource.gameItemId) {
      return true;
    }
    final normalizedNeed = _normalizePlannerMaterialName(need.name);
    return _normalizePlannerMaterialName(resource.name) == normalizedNeed ||
        resource.aliases.any(
          (alias) => _normalizePlannerMaterialName(alias) == normalizedNeed,
        );
  }

  bool _commitNodeBudget({bool rebuildPlan = false}) {
    final budget = int.tryParse(_nodeBudgetController.text.trim());
    if (budget == null || budget < 0) {
      setState(() {
        _nodeNetworkInputError = 'Enter a whole-number CP limit of 0 or more.';
      });
      return false;
    }
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(contributionPointBudget: budget),
      rebuildPlan: rebuildPlan,
    );
    return true;
  }

  Future<void> _calculateExactNodeNetwork() async {
    if (!_commitNodeBudget()) {
      return;
    }
    if (_nodeNetworkPreferences.desiredResourceNodeCounts.isEmpty) {
      setState(() {
        _nodeNetworkInputError =
            'Choose at least one worker material before building a network.';
      });
      return;
    }
    setState(() {
      _nodeNetworkReviewOrigin = _NodeNetworkPlannerPage.targets;
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.review;
      _showConnections = true;
      _nodeNetworkSaveMessage = null;
    });
    await _rebuildNodeNetworkPlan(fitWhenComplete: true);
  }

  Future<bool> _openGroupedRecipeGoals() async {
    if (widget.plannerNeedGroups.isEmpty) {
      _applyRecipeNodeRecommendation();
      return true;
    }
    final result = await showDialog<_PlannerNeedSelectionResult>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: _PlannerNeedSelectionDialog(
          initialSelection: _plannerNeedSelection,
          initialNodeCountsByResourceId:
              _nodeNetworkPreferences.desiredResourceNodeCounts,
          resourceIconBuilder: widget.resourceIconBuilder,
          dataset: widget.dataset,
          reachableProductionNodeIds: _reachableWorkerProductionNodeIds(),
          contributionPointBudget:
              _nodeNetworkPreferences.contributionPointBudget,
          currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
          rootNodeIds: _effectiveNetworkRootNodeIds,
        ),
      ),
    );
    if (!mounted || result == null) {
      return false;
    }
    setState(() {
      _plannerNeedSelection = result.selection;
      _nodeNetworkInputError = null;
    });
    _applyRecipeNodeRecommendation(materialTargets: result.materialTargets);
    return true;
  }

  void _applyRecipeNodeRecommendation({
    List<BdoRecipeNodeMaterialTarget> materialTargets =
        const <BdoRecipeNodeMaterialTarget>[],
  }) {
    if (!_commitNodeBudget()) {
      return;
    }
    final grouped = widget.plannerNeedGroups.isNotEmpty;
    final positiveNeeds = grouped
        ? _plannerNeedSelection.selectedPositiveWorkerPlannerNeeds
        : widget.plannerNeeds
              .where(
                (need) =>
                    !need.vendorPurchaseAvailable &&
                    need.missingQuantity.isFinite &&
                    need.missingQuantity > 0,
              )
              .toList(growable: false);
    if (positiveNeeds.isEmpty) {
      setState(() {
        _nodeNetworkInputError = grouped
            ? 'Check at least one missing Cooking or Alchemy material.'
            : 'The current craft plan has no missing materials to cover.';
      });
      return;
    }

    final recommendation = grouped
        ? const BdoGroupedRecipeNodeRecommendationService()
              .recommend(
                data: widget.dataset,
                request: BdoGroupedRecipeNodeRecommendationRequest(
                  selection: _plannerNeedSelection,
                  contributionPointBudget:
                      _nodeNetworkPreferences.contributionPointBudget,
                  currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
                  rootNodeIds: _effectiveNetworkRootNodeIds,
                  materialTargets: materialTargets,
                ),
              )
              .recommendation
        : const BdoRecipeNodeRecommendationService().recommend(
            data: widget.dataset,
            request: BdoRecipeNodeRecommendationRequest.fromPlannerNeeds(
              contributionPointBudget:
                  _nodeNetworkPreferences.contributionPointBudget,
              needs: positiveNeeds,
              materialTargets: materialTargets,
              currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
              rootNodeIds: _effectiveNetworkRootNodeIds,
            ),
          );
    final targets = recommendation.requestedDistinctNodeCountsByResource;
    if (targets.isEmpty) {
      setState(() {
        _recipeNodeRecommendation = recommendation;
        _nodeNetworkWorkerCapacity = null;
        _nodeNetworkLodgingPlan = null;
        _nodeNetworkInputError =
            'None of the missing recipe materials has a mapped worker node.';
      });
      return;
    }

    final preferences = _nodeNetworkPreferences.copyWith(
      desiredResourceNodeCounts: targets,
    );
    _replaceNodeNetworkPreferences(preferences, rebuildPlan: false);
    final result = recommendation.networkResult;
    final guidedResult = result == null
        ? null
        : _withExactLimitGuidance(result);
    final staffing = _planNodeNetworkStaffing(guidedResult?.plan);
    setState(() {
      _recipeNodeRecommendation = recommendation;
      _nodeNetworkResult = guidedResult;
      _nodeNetworkWorkerCapacity = staffing.capacity;
      _nodeNetworkLodgingPlan = staffing.lodging;
      _nodeNetworkReviewOrigin = _NodeNetworkPlannerPage.home;
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.review;
      _showConnections = true;
      _nodeNetworkCalculating = false;
      _nodeNetworkCalculationError = null;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = null;
    });
    final plan = _nodeNetworkResult?.plan;
    if (plan != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review) {
          _fitNodeNetworkPlan(plan);
        }
      });
    }
  }

  void _openMarketValueRecommendations() {
    if (widget.recipeWorkerBuilder != null) {
      _openNodeNetworkPlanner();
      return;
    }
    setState(() {
      _nodeNetworkPlannerPage = _NodeNetworkPlannerPage.marketValue;
      _showConnections = true;
      _nodeNetworkInputError = null;
      _nodeNetworkSaveMessage = null;
      _rawSaleNetworkPlan = null;
      _selectedMarketValuePath = null;
      _marketValueDetailsExpanded = false;
      _workerLodgingDetailsExpanded = false;
    });
    _calculateMarketValueRecommendations();
  }

  void _calculateMarketValueRecommendations() {
    unawaited(_calculateMarketValueRecommendationsAsync());
  }

  Future<void> _calculateMarketValueRecommendationsAsync() async {
    final calculationGeneration = ++_marketValueCalculationGeneration;
    if (mounted) {
      setState(() {
        _marketValueCalculating = true;
        _marketValueMessage = null;
      });
    }
    // Let settings dialogs close and the progress state paint before graph
    // preparation begins.
    await Future<void>.delayed(Duration.zero);
    if (!mounted ||
        calculationGeneration != _marketValueCalculationGeneration) {
      return;
    }
    final paths = const BdoProductionNodePathCostService().calculateAll(
      data: widget.dataset,
      currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
      allowedRootNodeIds: _effectiveNetworkRootNodeIds,
    );
    final candidates = <MarketValueNodeInput>[];
    final incomeCandidatesByNodeId = <String, BdoWorkerIncomeNodeInput>{};
    final economics = widget.workerEconomics;
    var overBudgetCount = 0;
    final currentCp = _contributionPointsForNodeIds(
      _nodeNetworkPreferences.currentNodeIds,
    );
    final royalReservedCp = _activeRoyalWorkshopReservedContributionPoints;
    final availableNodeAndLodgingBudget = math.max(
      0,
      _nodeNetworkPreferences.contributionPointBudget - royalReservedCp,
    );
    final remainingCp = math.max(0, availableNodeAndLodgingBudget - currentCp);
    for (final node in widget.dataset.workerNodes.where(
      (candidate) => candidate.isResourceNode && candidate.isProductionNode,
    )) {
      final pathResult = paths[node.id];
      if (pathResult == null || !pathResult.hasPath) {
        continue;
      }
      final minimumPath = pathResult.minimumTotalPath!;
      final incrementalPath = pathResult.minimumIncrementalPath!;
      final displayedPath = _marketValuePathFromResult(pathResult);
      if (displayedPath == null || displayedPath.edges.isEmpty) {
        continue;
      }
      if (displayedPath.incrementalContributionPoints > remainingCp) {
        overBudgetCount += 1;
        continue;
      }
      final evidence = <MarketValueOutputInput>[
        for (final output in node.outputs)
          widget.marketOutputEvidenceByResourceId[output.resourceId] ??
              MarketValueOutputInput(
                outputId: output.resourceId,
                outputName: output.name,
                isMarketable: true,
                currentUnitPrice: null,
                listedStock: null,
              ),
      ];
      candidates.add(
        MarketValueNodeInput(
          nodeId: node.id,
          nodeName: '${node.siteName} · ${node.activityLabel}',
          outputs: evidence,
          minimumContributionPoints: minimumPath.totalContributionPoints,
          incrementalContributionPoints:
              incrementalPath.incrementalContributionPoints,
          pathNodeIds: minimumPath.orderedNodeIds,
          incrementalPathNodeIds: incrementalPath.orderedNodeIds,
        ),
      );
      if (economics != null) {
        final allowedTownNodeIds = economics.eligibleWorkerTownNodeIds(
          productionNodeId: node.id,
          connectedNodeIds: displayedPath.orderedNodeIds,
        );
        incomeCandidatesByNodeId[node.id] = BdoWorkerIncomeNodeInput(
          nodeId: node.id,
          nodeName: '${node.siteName} · ${node.activityLabel}',
          outputs: <BdoWorkerIncomeMarketOutputInput>[
            for (var index = 0; index < node.outputs.length; index += 1)
              if ((node.outputs[index].gameItemId ??
                      widget
                          .dataset
                          .resourcesById[node.outputs[index].resourceId]
                          ?.gameItemId)
                  case final gameItemId?)
                BdoWorkerIncomeMarketOutputInput(
                  gameItemId: gameItemId,
                  resourceId: node.outputs[index].resourceId,
                  name: node.outputs[index].name,
                  isMarketable: evidence[index].isMarketable,
                  currentUnitPrice: evidence[index].currentUnitPrice,
                  listedStock: evidence[index].listedStock,
                  observedDailyTradeVolume:
                      evidence[index].observedDailyTradeVolume,
                  tradeObservationHours: evidence[index].tradeObservationHours,
                ),
          ],
          minimumContributionPoints: minimumPath.totalContributionPoints,
          incrementalContributionPoints:
              incrementalPath.incrementalContributionPoints,
          allowedTownNodeIds: allowedTownNodeIds,
        );
      }
    }
    final result = const MarketValueRecommendationService().evaluate(
      MarketValueRecommendationRequest(
        candidates: candidates,
        marketNetRate: widget.marketNetRate,
        rankingBasis: _marketValueRankingBasis,
        stockPolicy: _marketValueUseStockCompetition
            ? const ListedStockCompetitionPolicy.penalize(
                referenceListedStock: 100000,
              )
            : const ListedStockCompetitionPolicy.ignore(),
        allowPartialPriceData: _marketValueAllowPartialPrices,
      ),
    );
    final workerIncome = economics == null
        ? null
        : const BdoWorkerIncomeEstimator().evaluate(
            BdoWorkerIncomeRequest(
              dataset: economics,
              candidates: incomeCandidatesByNodeId.values,
              marketNetRate: widget.marketNetRate,
              onlineHoursPerDay: _nodeNetworkPreferences.onlineHoursPerDay,
              resourceAvailabilityPercent:
                  _nodeNetworkPreferences.resourceAvailabilityPercent,
              rankingBasis: _workerIncomeRankingBasis,
              allowPartialPriceData: _marketValueAllowPartialPrices,
              applyObservedTradeVolumeCeiling:
                  _nodeNetworkPreferences.useObservedTradeVolume,
            ),
          );
    final rawSaleSignals = workerIncome == null
        ? <String, double>{
            for (final recommendation in result.ranked)
              if ((_marketValueUseStockCompetition
                      ? recommendation.stockAdjustedNetValueSignal
                      : recommendation.netUnitBasketValue)
                  case final signal? when signal.isFinite && signal > 0)
                recommendation.nodeId: signal,
          }
        : _staffableIncomeSignals(
            workerIncome,
            incomeCandidatesByNodeId: incomeCandidatesByNodeId,
          );
    BdoRawSaleMarginalValueSignalProviderFactory?
    marginalIncomeSignalProviderFactory;
    if (workerIncome != null &&
        _nodeNetworkPreferences.useObservedTradeVolume) {
      final incomeByNodeId = <String, BdoWorkerIncomeNodeEvaluation>{
        for (final node in workerIncome.ranked)
          if (rawSaleSignals.containsKey(node.nodeId)) node.nodeId: node,
      };
      marginalIncomeSignalProviderFactory = () {
        BdoWorkerIncomePortfolioMarginalEvaluator? marginalEvaluator;
        var preparedSelectedCount = -1;
        return (productionNodeId, selectedProductionNodeIds) {
          // One raw-plan pass only grows its selected set. Each lodging repair
          // gets a fresh provider so a prior portfolio cannot leak into it.
          if (marginalEvaluator == null ||
              preparedSelectedCount != selectedProductionNodeIds.length) {
            marginalEvaluator = const BdoWorkerIncomePortfolioEstimator()
                .prepareMarginalEvaluator(
                  BdoWorkerIncomePortfolioRequest(
                    nodes: <BdoWorkerIncomeNodeEvaluation>[
                      for (final nodeId in selectedProductionNodeIds)
                        ?incomeByNodeId[nodeId],
                    ],
                    onlineHoursPerDay:
                        _nodeNetworkPreferences.onlineHoursPerDay,
                  ),
                );
            preparedSelectedCount = selectedProductionNodeIds.length;
          }
          final candidate = incomeByNodeId[productionNodeId];
          if (candidate == null) {
            return 0;
          }
          final marginalValue = marginalEvaluator!.evaluate(candidate);
          return marginalValue.isFinite && marginalValue > 0
              ? marginalValue
              : 0;
        };
      };
    }
    late final BdoRawSaleNetworkPlanResult rawSalePlan;
    BdoWorkerCapacityAssessmentResult? workerCapacity;
    BdoLodgingNetworkPlanningResult? lodgingPlan;
    try {
      bool shouldCancel() =>
          !mounted ||
          calculationGeneration != _marketValueCalculationGeneration;
      if (economics == null) {
        rawSalePlan = await const BdoRawSaleNetworkPlanner().planAsync(
          data: widget.dataset,
          request: BdoRawSaleNetworkPlanRequest(
            totalContributionPointBudget: availableNodeAndLodgingBudget,
            currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
            allowedRootNodeIds: _effectiveNetworkRootNodeIds,
            currentSaleValueSignalsByProductionNodeId: rawSaleSignals,
            marginalValueSignalProvider: marginalIncomeSignalProviderFactory
                ?.call(),
          ),
          shouldCancel: shouldCancel,
        );
      } else {
        final lodgingAwarePlan = await const BdoRawSaleLodgingBudgetPlanner()
            .planAsync(
              data: widget.dataset,
              economics: economics,
              lodgingDataset: widget.lodgingDataset,
              request: BdoRawSaleLodgingBudgetRequest(
                totalContributionPointBudget: availableNodeAndLodgingBudget,
                currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
                allowedRootNodeIds: _effectiveNetworkRootNodeIds,
                currentSaleValueSignalsByProductionNodeId: rawSaleSignals,
                townWorkerCapacitiesByNodeId:
                    _effectiveTownWorkerCapacitiesByNodeId,
                currentOwnedHouseIds:
                    _nodeNetworkPreferences.currentOwnedHouseIds,
                marginalValueSignalProviderFactory:
                    marginalIncomeSignalProviderFactory,
              ),
              shouldCancel: shouldCancel,
            );
        rawSalePlan = lodgingAwarePlan.networkPlan;
        workerCapacity = lodgingAwarePlan.workerCapacity;
        lodgingPlan = lodgingAwarePlan.lodgingPlanning;
      }
    } on BdoRawSaleNetworkPlanningCancelled {
      return;
    } catch (error) {
      if (mounted &&
          calculationGeneration == _marketValueCalculationGeneration) {
        setState(() {
          _marketValueCalculating = false;
          _marketValueMessage =
              'The worker route could not be updated. Please try again.';
        });
      }
      return;
    }
    if (!mounted ||
        calculationGeneration != _marketValueCalculationGeneration) {
      return;
    }
    final portfolioIncome = economics == null
        ? null
        : _evaluateRawSaleNetworkIncome(
            rawSalePlan,
            candidatesByNodeId: incomeCandidatesByNodeId,
            economics: economics,
            workerCapacity: workerCapacity,
            lodgingPlan: lodgingPlan,
          );
    final portfolioSummary = portfolioIncome == null
        ? null
        : const BdoWorkerIncomePortfolioEstimator().evaluate(
            BdoWorkerIncomePortfolioRequest(
              nodes: portfolioIncome.ranked,
              onlineHoursPerDay: _nodeNetworkPreferences.onlineHoursPerDay,
            ),
          );
    setState(() {
      _marketValuePaths = paths;
      _marketValueRecommendation = result;
      _workerIncomeRecommendation = workerIncome;
      _rawSaleNetworkIncome = portfolioIncome;
      _rawSalePortfolioSummary = portfolioSummary;
      _rawSaleWorkerCapacity = workerCapacity;
      _rawSaleLodgingPlan = lodgingPlan;
      _rawSaleNetworkPlan = rawSalePlan;
      _marketValueOverBudgetCount = overBudgetCount;
      _marketValueCalculating = false;
      _selectedMarketValuePath = null;
      _selectedNodeId = null;
      _showConnections = rawSalePlan.routeEdges.isNotEmpty;
    });
    if (rawSalePlan.routeNodeIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.marketValue ||
            !identical(_rawSaleNetworkPlan, rawSalePlan)) {
          return;
        }
        _fitRawSaleNetworkPlan(rawSalePlan);
      });
    }
  }

  Map<String, double> _staffableIncomeSignals(
    BdoWorkerIncomeResult result, {
    required Map<String, BdoWorkerIncomeNodeInput> incomeCandidatesByNodeId,
  }) {
    final entries = <({BdoWorkerIncomeNodeEvaluation node, double signal})>[
      for (final node in result.ranked)
        if ((_nodeNetworkPreferences.useObservedTradeVolume
                ? node.liquidityAdjustedNetSilverPerOnlineHour
                : node.netSilverPerOnlineHour)
            case final signal? when signal.isFinite && signal > 0)
          (node: node, signal: signal),
    ];
    final configuredCapacity = _effectiveTownWorkerCapacitiesByNodeId;
    if (configuredCapacity.isEmpty) {
      return <String, double>{
        for (final entry in entries) entry.node.nodeId: entry.signal,
      };
    }
    final lodging = widget.lodgingDataset;
    if (lodging != null) {
      return <String, double>{
        for (final entry in entries)
          if ((incomeCandidatesByNodeId[entry.node.nodeId]
                      ?.allowedTownNodeIds ??
                  const <String>{})
              .any(
                (townNodeId) =>
                    lodging.townsByNodeId[townNodeId]?.isWorkerTown == true,
              ))
            entry.node.nodeId: entry.signal,
      };
    }

    entries.sort((left, right) {
      final leftCp = left.node.incrementalContributionPoints ?? 0;
      final rightCp = right.node.incrementalContributionPoints ?? 0;
      if (leftCp == 0 || rightCp == 0) {
        if (leftCp == 0 && rightCp != 0) return -1;
        if (rightCp == 0 && leftCp != 0) return 1;
      } else {
        final ratio = (right.signal / rightCp).compareTo(left.signal / leftCp);
        if (ratio != 0) return ratio;
      }
      final byIncome = right.signal.compareTo(left.signal);
      if (byIncome != 0) return byIncome;
      return _compareMapNodeIds(left.node.nodeId, right.node.nodeId);
    });

    final accepted = <String>[];
    final candidateTowns = <String, Iterable<String>>{};
    final signals = <String, double>{};
    for (final entry in entries) {
      final candidate = incomeCandidatesByNodeId[entry.node.nodeId];
      final towns = (candidate?.allowedTownNodeIds ?? const <String>{})
          .where(configuredCapacity.containsKey)
          .toSet();
      if (towns.isEmpty) {
        continue;
      }
      final trialIds = <String>[...accepted, entry.node.nodeId];
      final trialTowns = <String, Iterable<String>>{
        ...candidateTowns,
        entry.node.nodeId: towns,
      };
      final assessment = const BdoWorkerCapacityAssessmentService().assess(
        BdoWorkerCapacityAssessmentRequest(
          selectedProductionNodeIds: trialIds,
          townCapacitiesByNodeId: configuredCapacity,
          candidateTownNodeIdsByProductionNodeId: trialTowns,
        ),
      );
      if (assessment.assessment?.isCoveredByCurrentCapacity != true) {
        continue;
      }
      accepted.add(entry.node.nodeId);
      candidateTowns[entry.node.nodeId] = towns;
      signals[entry.node.nodeId] = entry.signal;
    }
    return signals;
  }

  Map<String, int> _distributedLodgingCpByProductionNode(
    BdoLodgingNetworkPlan? plan,
  ) {
    if (plan == null) {
      return const <String, int>{};
    }
    final productionNodeIdsByTown = <String, List<String>>{};
    for (final entry in plan.townNodeIdByProductionNodeId.entries) {
      (productionNodeIdsByTown[entry.value] ??= <String>[]).add(entry.key);
    }
    final result = <String, int>{};
    final plansByTown = plan.townPlansByNodeId;
    for (final entry in productionNodeIdsByTown.entries) {
      final productionNodeIds = entry.value..sort(_compareMapNodeIds);
      final lodgingCp =
          plansByTown[entry.key]?.incrementalContributionPoints ?? 0;
      final quotient = lodgingCp ~/ productionNodeIds.length;
      final remainder = lodgingCp % productionNodeIds.length;
      for (var index = 0; index < productionNodeIds.length; index += 1) {
        result[productionNodeIds[index]] =
            quotient + (index < remainder ? 1 : 0);
      }
    }
    return result;
  }

  BdoWorkerIncomeResult _evaluateRawSaleNetworkIncome(
    BdoRawSaleNetworkPlanResult plan, {
    required Map<String, BdoWorkerIncomeNodeInput> candidatesByNodeId,
    required BdoWorkerEconomicsDataset economics,
    required BdoWorkerCapacityAssessmentResult? workerCapacity,
    required BdoLodgingNetworkPlanningResult? lodgingPlan,
  }) {
    final candidateTowns = _workerTownCandidatesForPlan(plan, economics);
    final assignedTownByProductionNodeId = <String, String>{
      for (final assignment
          in workerCapacity?.assessment?.assignments ??
              const <BdoProductionWorkerAssignment>[])
        assignment.productionNodeId: assignment.townNodeId,
      ...?lodgingPlan?.plan?.townNodeIdByProductionNodeId,
    };
    final lodgingCpByProductionNodeId = _distributedLodgingCpByProductionNode(
      lodgingPlan?.plan,
    );
    final hasConfiguredCapacity =
        _nodeNetworkPreferences.townWorkerCapacitiesByNodeId.isNotEmpty;
    final selectionByNodeId = <String, BdoRawSaleNetworkSelection>{
      for (final selection in plan.selections)
        selection.productionNodeId: selection,
    };
    Set<String> allowedTownNodeIdsFor(String productionNodeId) {
      if (!hasConfiguredCapacity) {
        return candidateTowns[productionNodeId] ?? const <String>{};
      }
      final assignedTown = assignedTownByProductionNodeId[productionNodeId];
      return assignedTown == null ? const <String>{} : <String>{assignedTown};
    }

    final selectedCandidates = <BdoWorkerIncomeNodeInput>[
      for (final productionNodeId in plan.selectedProductionNodeIds)
        if (candidatesByNodeId[productionNodeId] case final candidate?)
          BdoWorkerIncomeNodeInput(
            nodeId: candidate.nodeId,
            nodeName: candidate.nodeName,
            outputs: candidate.outputs,
            minimumContributionPoints:
                selectionByNodeId[productionNodeId]
                    ?.path
                    .totalContributionPoints ??
                candidate.minimumContributionPoints,
            incrementalContributionPoints:
                selectionByNodeId[productionNodeId]
                    ?.addedContributionPointsAtSelection ??
                candidate.incrementalContributionPoints,
            incrementalLodgingContributionPoints: lodgingPlan?.plan == null
                ? candidate.incrementalLodgingContributionPoints
                : lodgingCpByProductionNodeId[productionNodeId] ?? 0,
            allowedTownNodeIds: allowedTownNodeIdsFor(productionNodeId),
          ),
    ];
    return const BdoWorkerIncomeEstimator().evaluate(
      BdoWorkerIncomeRequest(
        dataset: economics,
        candidates: selectedCandidates,
        marketNetRate: widget.marketNetRate,
        onlineHoursPerDay: _nodeNetworkPreferences.onlineHoursPerDay,
        resourceAvailabilityPercent:
            _nodeNetworkPreferences.resourceAvailabilityPercent,
        rankingBasis: BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour,
        allowPartialPriceData: _marketValueAllowPartialPrices,
        applyObservedTradeVolumeCeiling:
            _nodeNetworkPreferences.useObservedTradeVolume,
      ),
    );
  }

  Map<String, Set<String>> _workerTownCandidatesForPlan(
    BdoRawSaleNetworkPlanResult plan,
    BdoWorkerEconomicsDataset economics,
  ) {
    final adjacency = <String, Set<String>>{};
    for (final edge in plan.routeEdges) {
      (adjacency[edge.firstNodeId] ??= <String>{}).add(edge.secondNodeId);
      (adjacency[edge.secondNodeId] ??= <String>{}).add(edge.firstNodeId);
    }
    final result = <String, Set<String>>{};
    for (final productionNodeId in plan.selectedProductionNodeIds) {
      final reached = <String>{productionNodeId};
      final queue = <String>[productionNodeId];
      for (var index = 0; index < queue.length; index += 1) {
        for (final neighbor in adjacency[queue[index]] ?? const <String>{}) {
          if (reached.add(neighbor)) {
            queue.add(neighbor);
          }
        }
      }
      result[productionNodeId] = economics.eligibleWorkerTownNodeIds(
        productionNodeId: productionNodeId,
        connectedNodeIds: reached,
      );
    }
    return result;
  }

  Map<String, Set<String>> _workerTownCandidatesForNodeNetworkPlan(
    BdoNodeNetworkPlan plan,
    BdoWorkerEconomicsDataset economics,
  ) {
    final adjacency = <String, Set<String>>{};
    for (final edge in plan.changeSet.edges) {
      (adjacency[edge.firstNodeId] ??= <String>{}).add(edge.secondNodeId);
      (adjacency[edge.secondNodeId] ??= <String>{}).add(edge.firstNodeId);
    }
    final result = <String, Set<String>>{};
    for (final productionNodeId in plan.selectedProductionNodeIds) {
      final reached = <String>{productionNodeId};
      final queue = <String>[productionNodeId];
      for (var index = 0; index < queue.length; index += 1) {
        for (final neighbor in adjacency[queue[index]] ?? const <String>{}) {
          if (reached.add(neighbor)) {
            queue.add(neighbor);
          }
        }
      }
      result[productionNodeId] = economics.eligibleWorkerTownNodeIds(
        productionNodeId: productionNodeId,
        connectedNodeIds: reached,
      );
    }
    return result;
  }

  ({
    BdoWorkerCapacityAssessmentResult? capacity,
    BdoLodgingNetworkPlanningResult? lodging,
  })
  _planNodeNetworkStaffing(BdoNodeNetworkPlan? plan) {
    final economics = widget.workerEconomics;
    final lodgingDataset = widget.lodgingDataset;
    final configuredCapacity = _effectiveTownWorkerCapacitiesByNodeId;
    if (plan == null ||
        economics == null ||
        lodgingDataset == null ||
        configuredCapacity.isEmpty) {
      return (capacity: null, lodging: null);
    }
    final candidateTowns = _workerTownCandidatesForNodeNetworkPlan(
      plan,
      economics,
    );
    final capacity = const BdoWorkerCapacityAssessmentService().assess(
      BdoWorkerCapacityAssessmentRequest(
        selectedProductionNodeIds: plan.selectedProductionNodeIds,
        townCapacitiesByNodeId: configuredCapacity,
        candidateTownNodeIdsByProductionNodeId: <String, Iterable<String>>{
          for (final productionNodeId in plan.selectedProductionNodeIds)
            productionNodeId:
                (candidateTowns[productionNodeId] ?? const <String>{}).where(
                  configuredCapacity.containsKey,
                ),
        },
      ),
    );
    final assignedProductionNodeIds =
        capacity.assessment?.assignments
            .map((assignment) => assignment.productionNodeId)
            .toSet() ??
        const <String>{};
    final demands = <BdoUnmetWorkerDemand>[
      for (final productionNodeId in plan.selectedProductionNodeIds)
        if (!assignedProductionNodeIds.contains(productionNodeId))
          BdoUnmetWorkerDemand(
            productionNodeId: productionNodeId,
            candidateTownNodeIds:
                (candidateTowns[productionNodeId] ?? const <String>{}).where(
                  (townNodeId) =>
                      lodgingDataset.townsByNodeId[townNodeId]?.isWorkerTown ==
                      true,
                ),
          ),
    ];
    final lodging = const BdoLodgingNetworkPlanner().plan(
      dataset: lodgingDataset,
      unmetDemands: demands,
      currentOwnedHouseIds: _nodeNetworkPreferences.currentOwnedHouseIds
          .where(lodgingDataset.housesById.containsKey)
          .toSet(),
    );
    return (capacity: capacity, lodging: lodging);
  }

  Future<void> _openWorkerIncomeSettings() async {
    final result = await showDialog<_WorkerIncomeSettings>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: _WorkerIncomeSettingsDialog(
          onlineHoursPerDay: _nodeNetworkPreferences.onlineHoursPerDay,
          resourceAvailabilityPercent:
              _nodeNetworkPreferences.resourceAvailabilityPercent,
          useObservedTradeVolume:
              _nodeNetworkPreferences.useObservedTradeVolume,
          allowPartialPrices: _marketValueAllowPartialPrices,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final partialPriceSettingChanged =
        _marketValueAllowPartialPrices != result.allowPartialPrices;
    final nextPreferences = _nodeNetworkPreferences.copyWith(
      onlineHoursPerDay: result.onlineHoursPerDay,
      resourceAvailabilityPercent: result.resourceAvailabilityPercent,
      useObservedTradeVolume: result.useObservedTradeVolume,
    );
    if (partialPriceSettingChanged) {
      setState(() {
        _marketValueAllowPartialPrices = result.allowPartialPrices;
      });
    }
    if (_nodeNetworkPreferences.sameValuesAs(nextPreferences)) {
      if (partialPriceSettingChanged) {
        _calculateMarketValueRecommendations();
      }
      return;
    }
    _replaceNodeNetworkPreferences(nextPreferences, rebuildPlan: false);
  }

  Future<void> _openWorkerCapacitySettings() async {
    final knownSlots = <String, int>{
      for (final town in widget.lodgingDataset?.towns ?? <LodgingTown>[])
        town.townNodeId:
            town.baseWorkerSlots + _ownedLodgingCapacityForTown(town),
    };
    final result = await showDialog<Map<String, BdoTownWorkerCapacity>>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: TownShopLodgingDialog(
          initialValues: _nodeNetworkPreferences.townWorkerCapacitiesByNodeId,
          knownSlotCountsByTownNodeId: knownSlots,
          onOpenExistingWorkers: widget.workerEconomics == null
              ? null
              : _editExistingWorkers,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    _replaceNodeNetworkPreferences(
      _nodeNetworkPreferences.copyWith(townWorkerCapacitiesByNodeId: result),
      rebuildPlan: false,
    );
  }

  Future<Map<String, BdoTownWorkerCapacity>?> _editExistingWorkers(
    Map<String, BdoTownWorkerCapacity> initialValues,
  ) async {
    final economics = widget.workerEconomics;
    if (economics == null) {
      return null;
    }
    final towns =
        <BdoWorkerNode>[
          for (final townId in economics.workerTownNodeIds)
            ?widget.dataset.workerNodesById[townId],
        ]..sort((left, right) {
          final byName = left.siteName.toLowerCase().compareTo(
            right.siteName.toLowerCase(),
          );
          return byName != 0 ? byName : _compareMapNodeIds(left.id, right.id);
        });
    final lodgingContextByTownNodeId = <String, _WorkerTownLodgingContext>{};
    for (final town in towns) {
      final lodgingTown = widget.lodgingDataset?.townsByNodeId[town.id];
      if (lodgingTown == null) {
        continue;
      }
      lodgingContextByTownNodeId[town.id] = _WorkerTownLodgingContext(
        baseWorkerSlotCount: lodgingTown.baseWorkerSlots,
        activeOwnedLodgingSlotCount: _ownedLodgingCapacityForTown(lodgingTown),
      );
    }
    return showDialog<Map<String, BdoTownWorkerCapacity>>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: _WorkerCapacityDialog(
          towns: towns,
          initialValues: initialValues,
          lodgingContextByTownNodeId: lodgingContextByTownNodeId,
        ),
      ),
    );
  }

  void _handleMarketValueMenuAction(_MarketValueMenuAction action) {
    if (widget.workerEconomics != null &&
        action == _MarketValueMenuAction.stockCompetition) {
      _replaceNodeNetworkPreferences(
        _nodeNetworkPreferences.copyWith(
          useObservedTradeVolume:
              !_nodeNetworkPreferences.useObservedTradeVolume,
        ),
        rebuildPlan: false,
      );
      return;
    }
    setState(() {
      if (widget.workerEconomics != null) {
        switch (action) {
          case _MarketValueMenuAction.highestBasket:
            _workerIncomeRankingBasis =
                BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour;
            break;
          case _MarketValueMenuAction.perMinimumCp:
            _workerIncomeRankingBasis = BdoWorkerIncomeRankingBasis
                .netSilverPerTotalContributionPointHour;
            break;
          case _MarketValueMenuAction.perAddedCp:
            _workerIncomeRankingBasis = BdoWorkerIncomeRankingBasis
                .netSilverPerAddedContributionPointHour;
            break;
          case _MarketValueMenuAction.stockCompetition:
            break;
          case _MarketValueMenuAction.partialPrices:
            _marketValueAllowPartialPrices = !_marketValueAllowPartialPrices;
            break;
        }
        return;
      }
      switch (action) {
        case _MarketValueMenuAction.highestBasket:
          _marketValueRankingBasis = MarketValueRankingBasis.netUnitBasketValue;
          break;
        case _MarketValueMenuAction.perMinimumCp:
          _marketValueRankingBasis = MarketValueRankingBasis
              .netUnitBasketValuePerMinimumContributionPoint;
          break;
        case _MarketValueMenuAction.perAddedCp:
          _marketValueRankingBasis = MarketValueRankingBasis
              .netUnitBasketValuePerIncrementalContributionPoint;
          break;
        case _MarketValueMenuAction.stockCompetition:
          _marketValueUseStockCompetition = !_marketValueUseStockCompetition;
          break;
        case _MarketValueMenuAction.partialPrices:
          _marketValueAllowPartialPrices = !_marketValueAllowPartialPrices;
          break;
      }
    });
    _calculateMarketValueRecommendations();
  }

  String get _marketValueMenuLabel {
    if (widget.workerEconomics != null) {
      return switch (_workerIncomeRankingBasis) {
        BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour =>
          'Net silver / online hour',
        BdoWorkerIncomeRankingBasis.netSilverPerTotalContributionPointHour =>
          'Net silver / total CP-hour',
        BdoWorkerIncomeRankingBasis.netSilverPerAddedContributionPointHour =>
          'Net silver / added CP-hour',
      };
    }
    return switch (_marketValueRankingBasis) {
      MarketValueRankingBasis.netUnitBasketValue => 'Highest sale value',
      MarketValueRankingBasis.netUnitBasketValuePerMinimumContributionPoint =>
        'Value / total CP',
      MarketValueRankingBasis
          .netUnitBasketValuePerIncrementalContributionPoint =>
        'Value / added CP',
    };
  }

  BdoProductionNodePath? _marketValuePathFromResult(
    BdoProductionNodePathResult result,
  ) {
    if (widget.workerEconomics != null) {
      return _workerIncomeRankingBasis ==
              BdoWorkerIncomeRankingBasis.netSilverPerTotalContributionPointHour
          ? result.minimumTotalPath
          : result.minimumIncrementalPath;
    }
    return _marketValueRankingBasis ==
            MarketValueRankingBasis
                .netUnitBasketValuePerIncrementalContributionPoint
        ? result.minimumIncrementalPath
        : result.minimumTotalPath;
  }

  BdoProductionNodePath? _marketValuePathForNode(
    String nodeId, {
    Map<String, BdoProductionNodePathResult>? paths,
  }) {
    final result = (paths ?? _marketValuePaths)[nodeId];
    if (result == null) {
      return null;
    }
    return _marketValuePathFromResult(result);
  }

  void _commitMarketValueBudget() {
    final previousBudget = _nodeNetworkPreferences.contributionPointBudget;
    if (!_commitNodeBudget()) {
      return;
    }
    if (_nodeNetworkPreferences.contributionPointBudget == previousBudget) {
      setState(() => _nodeNetworkInputError = null);
      _calculateMarketValueRecommendations();
    }
  }

  void _fitMarketValuePath(BdoProductionNodePath path) {
    _fitBrowseOverview(
      path.orderedNodeIds
          .map((id) => widget.dataset.workerNodesById[id]?.location.mapPoint)
          .whereType<BdoMapPoint>(),
    );
  }

  void _fitRawSaleNetworkPlan(BdoRawSaleNetworkPlanResult plan) {
    _fitBrowseOverview(
      plan.routeNodeIds
          .map((id) => widget.dataset.workerNodesById[id]?.location.mapPoint)
          .whereType<BdoMapPoint>(),
    );
  }

  void _showRecommendedRawSaleNetwork() {
    final plan = _rawSaleNetworkPlan;
    setState(() {
      _selectedMarketValuePath = null;
      _selectedNodeId = null;
      _showConnections = plan?.routeEdges.isNotEmpty ?? false;
    });
    if (plan != null && plan.routeNodeIds.isNotEmpty) {
      _fitRawSaleNetworkPlan(plan);
    }
  }

  void _selectMarketValueRecommendation(
    MarketValueNodeEvaluation recommendation,
  ) => _selectMarketValueNode(recommendation.nodeId);

  void _selectMarketValueNode(String nodeId) {
    final node = widget.dataset.workerNodesById[nodeId];
    final path = _marketValuePathForNode(nodeId);
    if (node == null || path == null) {
      return;
    }
    setState(() {
      _selectedMarketValuePath = path;
      _selectedNodeId = null;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _showConnections = true;
    });
    _fitMarketValuePath(path);
  }

  void _addSelectedMarketValueRoute() {
    final path = _selectedMarketValuePath;
    if (path == null) {
      return;
    }
    final nextCurrentIds = <String>{
      for (final id in _nodeNetworkPreferences.currentNodeIds)
        if (widget.dataset.workerNodesById[id] case final node?
            when !_isNaturalWorkerRoot(node))
          id,
      for (final id in path.orderedNodeIds)
        if (widget.dataset.workerNodesById[id] case final node?
            when !_isNaturalWorkerRoot(node))
          id,
    };
    if (setEquals(nextCurrentIds, _nodeNetworkPreferences.currentNodeIds)) {
      setState(() {
        _nodeNetworkSaveMessage =
            'This complete route is already in your in-game network.';
      });
      return;
    }
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: nextCurrentIds,
    );
    setState(() {
      _nodeNetworkPreferences = preferences;
      _currentNodeDraftIds = <String>{...nextCurrentIds};
      _nodeNetworkSaveMessage =
          'Route added to your in-game network in the planner. '
          'Nothing was changed in BDO.';
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    _calculateMarketValueRecommendations();
  }

  void _addRecommendedRawSaleNetwork() {
    final plan = _rawSaleNetworkPlan;
    if (plan == null || plan.addedNodeIds.isEmpty) {
      return;
    }
    final nextCurrentIds = <String>{
      for (final id in plan.networkNodeIds)
        if (widget.dataset.workerNodesById[id] case final node?
            when !_isNaturalWorkerRoot(node))
          id,
    };
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: nextCurrentIds,
    );
    setState(() {
      _nodeNetworkPreferences = preferences;
      _currentNodeDraftIds = <String>{...nextCurrentIds};
      _selectedMarketValuePath = null;
      _nodeNetworkSaveMessage =
          'Recommended ${widget.workerEconomics == null ? 'value' : 'income'} '
          'network added to your in-game network in the '
          'planner. Nothing was changed in BDO.';
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    _calculateMarketValueRecommendations();
  }

  Future<void> _refreshMarketValueEvidence() async {
    final refresh = widget.onRefreshMarketEvidence;
    if (refresh == null || _marketValueRefreshing) {
      return;
    }
    final names = <String>{
      for (final node in widget.dataset.workerNodes.where(
        (candidate) => candidate.isResourceNode && candidate.isProductionNode,
      ))
        for (final output in node.outputs) output.name,
    };
    setState(() {
      _marketValueRefreshing = true;
      _marketValueMessage = null;
    });
    try {
      final message = await refresh(names);
      if (!mounted) {
        return;
      }
      setState(() {
        _marketValueRefreshing = false;
        _marketValueMessage = message;
      });
      _calculateMarketValueRecommendations();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _marketValueRefreshing = false;
        _marketValueMessage =
            'Market data could not be refreshed. Existing cached values were '
            'kept. $error';
      });
    }
  }

  Future<void> _rebuildNodeNetworkPlan({bool fitWhenComplete = false}) async {
    final generation = ++_nodeNetworkCalculationGeneration;
    final request = BdoNodeNetworkRequest(
      contributionPointBudget: _nodeNetworkPreferences.contributionPointBudget,
      desiredResourceNodeCounts:
          _nodeNetworkPreferences.desiredResourceNodeCounts,
      currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
      rootNodeIds: _effectiveNetworkRootNodeIds,
    );
    final workerFuture = _nodeNetworkWorkerFuture ??=
        BdoNodeNetworkWorker.start(widget.dataset);
    setState(() {
      _nodeNetworkCalculating = true;
      _nodeNetworkCalculationError = null;
      _nodeNetworkResult = null;
      _nodeNetworkWorkerCapacity = null;
      _nodeNetworkLodgingPlan = null;
    });

    try {
      final worker = await workerFuture;
      final response = await worker.optimize(
        request: request,
        generation: generation,
      );
      if (!mounted ||
          !response.belongsToGeneration(_nodeNetworkCalculationGeneration) ||
          _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.review) {
        return;
      }
      final result = _withExactLimitGuidance(response.result);
      final staffing = _planNodeNetworkStaffing(result.plan);
      setState(() {
        _nodeNetworkCalculating = false;
        _nodeNetworkCalculationError = null;
        _nodeNetworkResult = result;
        _nodeNetworkWorkerCapacity = staffing.capacity;
        _nodeNetworkLodgingPlan = staffing.lodging;
      });
      final plan = result.plan;
      if (fitWhenComplete && plan != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              generation == _nodeNetworkCalculationGeneration &&
              _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review) {
            _fitNodeNetworkPlan(plan);
          }
        });
      }
    } catch (_) {
      if (identical(_nodeNetworkWorkerFuture, workerFuture)) {
        _nodeNetworkWorkerFuture = null;
        unawaited(
          workerFuture.then<void>(
            (worker) => worker.dispose(),
            onError: (_) {
              // Startup failed before a worker existed, so there is no cleanup.
            },
          ),
        );
      }
      if (!mounted ||
          generation != _nodeNetworkCalculationGeneration ||
          _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.review) {
        return;
      }
      setState(() {
        _nodeNetworkCalculating = false;
        _nodeNetworkResult = null;
        _nodeNetworkWorkerCapacity = null;
        _nodeNetworkLodgingPlan = null;
        _nodeNetworkCalculationError =
            'The exact calculation stopped unexpectedly. Your targets and '
            'saved network were not changed.';
      });
    }
  }

  BdoNodeNetworkResult _withExactLimitGuidance(BdoNodeNetworkResult result) {
    final exactLimitReached = result.diagnostics.any(
      (diagnostic) =>
          diagnostic.code ==
          BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded,
    );
    if (!exactLimitReached) {
      return result;
    }
    return BdoNodeNetworkResult(
      plan: null,
      diagnostics: <BdoNodeNetworkDiagnostic>[
        const BdoNodeNetworkDiagnostic(
          code: BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded,
          severity: BdoNodeNetworkDiagnosticSeverity.error,
          message:
              'This request is too large for an exact cheapest calculation. '
              'Reduce the number of selected materials or lower one or more '
              'node counts, then calculate again.',
        ),
        ...result.diagnostics.where(
          (diagnostic) =>
              diagnostic.code !=
                  BdoNodeNetworkDiagnosticCode.exactSearchLimitExceeded &&
              diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error,
        ),
      ],
    );
  }

  void _invalidateNodeNetworkCalculation({required bool clearResult}) {
    _nodeNetworkCalculationGeneration++;
    _nodeNetworkCalculating = false;
    _nodeNetworkCalculationError = null;
    if (clearResult) {
      _nodeNetworkResult = null;
      _recipeNodeRecommendation = null;
      _nodeNetworkWorkerCapacity = null;
      _nodeNetworkLodgingPlan = null;
    }
  }

  void _discardNodeNetworkWorker() {
    final workerFuture = _nodeNetworkWorkerFuture;
    _nodeNetworkWorkerFuture = null;
    if (workerFuture == null) {
      return;
    }
    unawaited(
      workerFuture.then<void>(
        (worker) => worker.dispose(),
        onError: (_) {
          // Startup failed before a worker existed, so there is no cleanup.
        },
      ),
    );
  }

  void _fitNodeNetworkPlan(BdoNodeNetworkPlan plan) {
    final points = plan.selectedNodeIds
        .map((id) => widget.dataset.workerNodesById[id]?.location.mapPoint)
        .whereType<BdoMapPoint>()
        .toList(growable: false);
    final currentPoints = _nodeNetworkPreferences.currentNodeIds
        .map((id) => widget.dataset.workerNodesById[id]?.location.mapPoint)
        .whereType<BdoMapPoint>();
    final bounds = _boundsForPoints(<BdoMapPoint>[...points, ...currentPoints]);
    if (bounds == null || _viewport.isEmpty) {
      return;
    }
    final compactRoute = bounds.width < 90000 && bounds.height < 90000;
    _fitBoundsAvoidingDetails(
      compactRoute ? bounds.inflate(9000) : bounds,
      padding: 68,
      maximumZoom: compactRoute ? 5.7 : 4.8,
    );
  }

  void _returnFromNodeReview() {
    if (_nodeNetworkReviewOrigin == _NodeNetworkPlannerPage.home &&
        !_compactLayout) {
      _invalidateNodeNetworkCalculation(clearResult: true);
      _navigateBack();
      return;
    }
    setState(() {
      _invalidateNodeNetworkCalculation(clearResult: true);
      _nodeNetworkPlannerPage = _nodeNetworkReviewOrigin;
      _selectedMarketValuePath = null;
      _nodeNetworkSaveMessage = null;
      _showConnections =
          _nodeNetworkReviewOrigin == _NodeNetworkPlannerPage.home;
    });
  }

  void _saveProposedNodeNetwork() {
    final plan = _nodeNetworkResult?.plan;
    if (plan == null || !_nodePlanIsWithinCombinedBudget(plan)) {
      return;
    }
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: <String>{
        for (final id in plan.selectedNodeIds)
          if (widget.dataset.workerNodesById[id] case final node?
              when !_isNaturalWorkerRoot(node))
            id,
      },
    );
    setState(() {
      _nodeNetworkPreferences = preferences;
      _nodeNetworkSaveMessage =
          'Saved as your in-game network in the planner. '
          'Nothing was changed in BDO.';
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    unawaited(_rebuildNodeNetworkPlan());
  }

  Future<void> _clearSavedNodeNetwork() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: DraggableAlertDialog(
          identity: 'clear-saved-node-network',
          estimatedSize: const Size(440, 250),
          title: const Text('Clear saved network?'),
          content: const Text(
            'This forgets the in-game nodes you recorded in the planner. '
            'Your selected materials stay unchanged.',
          ),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>(
                'resource-map-cancel-clear-node-network',
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>(
                'resource-map-confirm-clear-node-network',
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Forget saved nodes'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: const <String>{},
    );
    setState(() {
      _nodeNetworkPreferences = preferences;
      _currentNodeDraftIds = <String>{};
      _nodeNetworkSaveMessage = 'Saved in-game nodes forgotten.';
    });
    widget.onNodeNetworkPreferencesChanged?.call(preferences);
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.review) {
      unawaited(_rebuildNodeNetworkPlan());
    }
  }

  void _selectSearchResult(BdoSearchResult result) {
    final retainedWorkerEmphasis = result.kind == BdoSearchKind.workerNode
        ? _workerSearchMatchNodeIds
        : const <String>{};
    _pushNavigationEntry();
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _searchResultsVisible = false;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _explicitWorkerEmphasisNodeIds = retainedWorkerEmphasis;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _nodeNetworkPlannerOpen = false;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _browseFavorites = false;
      _selectedResourceSection = null;
      if (result.kind == BdoSearchKind.resource) {
        _selectedResourceId = result.resourceId;
        final resourceId = result.resourceId;
        _selectedFieldSourceId = resourceId == null
            ? null
            : _preferredFieldSourceId(resourceId);
        final hasWorkerNodes =
            resourceId != null &&
            widget.dataset.workerNodesForResource(resourceId).isNotEmpty;
        _showConnections = false;
        if (hasWorkerNodes) {
          _showWorkerNodes = true;
        }
        if (resourceId != null &&
            (widget.dataset.gatheringSpotsForResource(resourceId).isNotEmpty ||
                widget.dataset
                    .gatheringPointsForResource(resourceId)
                    .isNotEmpty)) {
          _showGathering = true;
        }
        if (resourceId != null &&
            widget.dataset.gatheringRoutesForResource(resourceId).isNotEmpty) {
          _showRoutes = true;
        }
      } else if (result.kind == BdoSearchKind.fieldSource) {
        final sourceId = result.fieldSourceId ?? result.id;
        final source = widget.dataset.fieldSourcesById[sourceId];
        _materialSourceFilter = _MaterialSourceFilter.manual;
        _selectedFieldSourceId = source?.id;
        _selectedResourceId = source == null
            ? null
            : _preferredProductForFieldSource(
                source,
                preferredResourceId: result.resourceId,
              )?.resourceId;
        _showGathering =
            source != null &&
            (widget.dataset
                    .gatheringPointsForFieldSource(source.id)
                    .isNotEmpty ||
                _gatheringSpotsForFieldSource(source).isNotEmpty ||
                source.products.any(
                  (product) => widget.dataset
                      .gatheringRoutesForResource(product.resourceId)
                      .isNotEmpty,
                ));
        _showRoutes =
            source != null &&
            source.products.any(
              (product) => widget.dataset
                  .gatheringRoutesForResource(product.resourceId)
                  .isNotEmpty,
            );
        _showWorkerNodes = false;
        _showConnections = false;
      } else {
        _selectedFieldSourceId = null;
        _selectedResourceId = result.resourceId;
        switch (result.kind) {
          case BdoSearchKind.workerNode:
            _selectedNodeId = result.id;
            _showWorkerNodes = true;
            final node = widget.dataset.workerNodesById[result.id];
            _nodeQuickPanelOpen = false;
            _selectedQuickNodePath = node == null
                ? null
                : _quickPathForNodeId(result.id);
            _desktopSheetExpanded = true;
            if (node != null && node.isResourceNode) {
              _workerActivityFilter = node.activity;
            } else {
              _workerActivityFilter = null;
            }
            break;
          case BdoSearchKind.gatheringSpot:
            _selectedSpotId = result.id;
            _showGathering = true;
            break;
          case BdoSearchKind.gatheringRoute:
            _selectedRouteId = result.id;
            _showRoutes = true;
            break;
          case BdoSearchKind.fieldSource:
          case BdoSearchKind.resource:
            break;
        }
      }
    });
    // Inspecting one worker node is a comparison action inside the current
    // map view. Keep the user's camera exactly where they placed it; the
    // details panel already identifies the chosen node and every search match
    // remains highlighted. Other search result kinds still intentionally
    // navigate to their location or bounds.
    if (result.kind != BdoSearchKind.workerNode) {
      _focusSearchResult(result);
    }
  }

  void _focusSearchResult(BdoSearchResult result) {
    if (_viewport.isEmpty) {
      return;
    }
    if (result.location != null) {
      _showPointAvoidingDetails(result.location!);
      return;
    }
    if (result.bounds != null) {
      _fitBoundsAvoidingDetails(result.bounds!);
      return;
    }
    if (result.fieldSourceId != null &&
        _focusFieldSource(result.fieldSourceId!)) {
      return;
    }
    if (result.resourceId != null) {
      if (!_fitPreferredResourceFocus(result.resourceId!)) {
        _fitResource(result.resourceId!);
      }
    }
  }

  bool _focusFieldSource(String sourceId) {
    final source = widget.dataset.fieldSourcesById[sourceId];
    if (source == null) {
      return false;
    }
    if (_materialSourceFilter != _MaterialSourceFilter.worker) {
      final linkedSpots = _gatheringSpotsForFieldSource(source);
      if (linkedSpots.length == 1 && linkedSpots.single.radiusWorld == null) {
        _fitGatheringSpot(linkedSpots.single, resourceId: _selectedResourceId);
        return true;
      }
      final exactAreaIds = widget.dataset
          .gatheringPointsForFieldSource(sourceId)
          .map((point) => point.areaId)
          .whereType<String>()
          .toSet();
      final focusedSpots = <String, BdoGatheringSpot>{};
      for (final product in source.products) {
        for (final spot in widget.dataset.gatheringSpotsForResource(
          product.resourceId,
        )) {
          if (spot.radiusWorld == null && exactAreaIds.contains(spot.id)) {
            focusedSpots[spot.id] = spot;
          }
        }
      }
      if (focusedSpots.length == 1) {
        _fitGatheringSpot(
          focusedSpots.values.single,
          resourceId: _selectedResourceId,
        );
        return true;
      }
    }
    return _fitFieldSource(sourceId);
  }

  bool _fitFieldSource(String sourceId) {
    final source = widget.dataset.fieldSourcesById[sourceId];
    if (source == null) {
      return false;
    }
    final resourceIds = source.products
        .map((product) => product.resourceId)
        .toSet();
    final points = <BdoMapPoint>[
      if (_materialSourceFilter !=
          _MaterialSourceFilter.worker) ...<BdoMapPoint>[
        ...widget.dataset
            .gatheringPointsForFieldSource(sourceId)
            .map((point) => point.location.mapPoint),
        for (final spot in _gatheringSpotsForFieldSource(source))
          if (spot.areaBounds case final bounds?) ...<BdoMapPoint>[
            BdoMapPoint(bounds.left, bounds.top),
            BdoMapPoint(bounds.right, bounds.bottom),
          ] else
            spot.location.mapPoint,
        for (final route in widget.dataset.gatheringRoutes.where(
          (route) => route.resourceIds.any(resourceIds.contains),
        ))
          ...route.waypoints.map((waypoint) => waypoint.location.mapPoint),
      ],
      if (_materialSourceFilter != _MaterialSourceFilter.manual)
        for (final resourceId in source.products.map(
          (product) => product.resourceId,
        ))
          ...widget.dataset
              .workerNodesForResource(resourceId)
              .map((node) => node.location.mapPoint),
    ];
    final bounds = _boundsForPoints(points);
    if (bounds == null || _viewport.isEmpty) {
      return false;
    }
    _fitBoundsAvoidingDetails(
      bounds,
      padding: 54,
      maximumZoom: points.length == 1 ? 5.7 : 6.2,
    );
    return true;
  }

  bool _fitPreferredResourceFocus(String resourceId) {
    if (_viewport.isEmpty ||
        _materialSourceFilter == _MaterialSourceFilter.worker) {
      return false;
    }
    final focuses = widget.dataset
        .gatheringSpotsForResource(resourceId)
        .where(
          (spot) =>
              spot.radiusWorld == null &&
              widget.dataset
                  .gatheringPointsForResource(resourceId)
                  .any((point) => point.areaId == spot.id),
        )
        .toList(growable: false);
    if (focuses.length != 1) {
      return false;
    }
    _fitGatheringSpot(focuses.single, resourceId: resourceId);
    return true;
  }

  bool _fitResource(String resourceId) {
    final points = <BdoMapPoint>[
      if (_materialSourceFilter != _MaterialSourceFilter.manual)
        ...widget.dataset
            .workerNodesForResource(resourceId)
            .map((node) => node.location.mapPoint),
      if (_materialSourceFilter !=
          _MaterialSourceFilter.worker) ...<BdoMapPoint>[
        ...widget.dataset.gatheringSpotsForResource(resourceId).expand((spot) {
          final bounds = spot.areaBounds;
          if (bounds == null) {
            return <BdoMapPoint>[spot.location.mapPoint];
          }
          return <BdoMapPoint>[
            BdoMapPoint(bounds.left, bounds.top),
            BdoMapPoint(bounds.right, bounds.bottom),
          ];
        }),
        ...widget.dataset
            .gatheringPointsForResource(resourceId)
            .map((point) => point.location.mapPoint),
        ...widget.dataset
            .gatheringRoutesForResource(resourceId)
            .expand((route) => route.waypoints)
            .map((waypoint) => waypoint.location.mapPoint),
      ],
    ];
    final bounds = _boundsForPoints(points);
    if (bounds != null && !_viewport.isEmpty) {
      _fitBoundsAvoidingDetails(
        bounds,
        padding: 54,
        maximumZoom: points.length == 1 ? 5.7 : 6.2,
      );
      return true;
    }
    return false;
  }

  void _setMaterialSourceFilter(_MaterialSourceFilter filter) {
    final resourceId = _selectedResourceId;
    final fieldSourceId = _selectedFieldSourceId;
    if (_materialSourceFilter == filter) {
      return;
    }
    final fieldSource = fieldSourceId == null
        ? null
        : widget.dataset.fieldSourcesById[fieldSourceId];
    final resourceIds = fieldSource == null
        ? <String>[?resourceId]
        : fieldSource.products
              .map((product) => product.resourceId)
              .toList(growable: false);
    final hasWorkerNodes = resourceIds.any(
      (id) => widget.dataset.workerNodesForResource(id).isNotEmpty,
    );
    final hasGathering =
        (fieldSource != null &&
            (widget.dataset
                    .gatheringPointsForFieldSource(fieldSource.id)
                    .isNotEmpty ||
                _gatheringSpotsForFieldSource(fieldSource).isNotEmpty)) ||
        (fieldSource == null &&
            resourceIds.any(
              (id) =>
                  widget.dataset.gatheringPointsForResource(id).isNotEmpty ||
                  widget.dataset.gatheringSpotsForResource(id).isNotEmpty,
            ));
    final hasRoutes = resourceIds.any(
      (id) => widget.dataset.gatheringRoutesForResource(id).isNotEmpty,
    );
    setState(() {
      _materialSourceFilter = filter;
      if (_searchController.text.trim().isNotEmpty) {
        _searchResults = _searchResultsForCurrentSource(_searchController.text);
      }
      _showWorkerNodes =
          filter != _MaterialSourceFilter.manual && hasWorkerNodes;
      _showGathering = filter != _MaterialSourceFilter.worker && hasGathering;
      _showRoutes = filter != _MaterialSourceFilter.worker && hasRoutes;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _showConnections = false;
    });
    if (fieldSourceId != null && _focusFieldSource(fieldSourceId)) {
      return;
    }
    if (resourceId != null && !_fitPreferredResourceFocus(resourceId)) {
      _fitResource(resourceId);
    }
  }

  void _setDesktopSheetExpanded(bool expanded, {bool focusSearch = false}) {
    if (_compactLayout) {
      if (focusSearch) {
        _focusSearchBox();
      }
      return;
    }
    if (_desktopSheetExpanded == expanded) {
      if (expanded && _desktopTaskSurfaceCollapsed) {
        setState(() => _desktopTaskSurfaceCollapsed = false);
      }
      if (focusSearch) {
        _focusSearchBox();
      }
      return;
    }
    if (!expanded) {
      _searchFocus.unfocus();
      _mapKeyboardFocus.requestFocus();
    }
    setState(() {
      _desktopSheetExpanded = expanded;
      if (expanded) {
        _desktopTaskSurfaceCollapsed = false;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (_hasDetailSelection ||
              (_browseAllWorkerNodes && _workerOverviewSelectionMade))) {
        _fitVisibleContentOrReset();
      }
    });
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusSearchBox();
        }
      });
    }
  }

  void _collapseDesktopTaskSurface() {
    if (_compactLayout || _desktopTaskSurfaceCollapsed) {
      return;
    }
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    setState(() => _desktopTaskSurfaceCollapsed = true);
  }

  void _openResourceSection(BdoResourceSection section) {
    _pushNavigationEntry();
    _searchFocus.unfocus();
    setState(() {
      _desktopSheetExpanded = true;
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _nodeNetworkPlannerOpen = false;
      _selectedResourceSection = section;
      _browseFavorites = false;
      _searchResultsVisible = false;
    });
  }

  void _openFavorites() {
    if (_browseFavorites && !_hasDetailSelection && !_searchResultsVisible) {
      _openMapHome();
      return;
    }
    _pushNavigationEntry();
    _searchFocus.unfocus();
    setState(() {
      _royalWorkshopOpen = false;
      _investNodeMode = false;
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _desktopTaskSurfaceCollapsed = false;
      _materialSourceFilter = _MaterialSourceFilter.all;
      _searchController.clear();
      _searchResults = const <BdoSearchResult>[];
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _housingDirectoryOpen = false;
      _nodeNetworkPlannerOpen = false;
      _selectedResourceSection = null;
      _browseFavorites = true;
      _searchResultsVisible = false;
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _showConnections = false;
    });
  }

  void _closeResourceBrowser() {
    _navigateBack();
  }

  void _toggleFavorite(BdoResourceDefinition resource) {
    _toggleFavoriteKey(resource.id);
  }

  void _toggleFavoriteKey(String key) {
    final next = Set<String>.of(_favoriteResourceIds);
    if (!next.add(key)) {
      next.remove(key);
    }
    setState(() => _favoriteResourceIds = next);
    widget.onFavoriteResourceIdsChanged?.call(Set<String>.unmodifiable(next));
  }

  List<BdoSearchResult> get _savedMapEntries {
    final entries = _favoriteResourceIds
        .map((key) => widget.dataset.favoriteEntriesByKey[key])
        .whereType<BdoSearchResult>()
        .toList();
    entries.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return entries;
  }

  Widget _buildSavedMapEntries(BuildContext context) {
    final entries = _savedMapEntries;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'No saved items',
          style: TextStyle(
            color: context.mapChrome.text,
            fontSize: ResourceMapPanelMetrics.secondary,
            height: 1.4,
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey<String>('resource-map-saved-entries'),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final entry in entries)
          _MapSearchResultTile(
            key: ValueKey<String>('resource-map-saved-${entry.favoriteKey}'),
            leading: _buildSearchResultArtwork(context, entry),
            title: _friendlySearchResultTitle(entry),
            subtitle: '',
            kindLabel: _friendlySearchResultKind(entry),
            trailing: _buildSearchFavorite(entry, savedList: true),
            onTap: () {
              // Saved shortcuts must work regardless of the previous search scope.
              setState(() {
                _materialSourceFilter = _MaterialSourceFilter.all;
                _mapSearchScope = _MapSearchScope.all;
              });
              _selectSearchResult(entry);
              if (entry.kind == BdoSearchKind.workerNode) {
                _focusSearchResult(entry);
              }
            },
          ),
      ],
    );
  }

  void _handleMapHit(BdoMapHit hit) {
    if (_vendorLookupItemName != null || _selectedVendorId != null) {
      setState(() {
        _vendorLookupItemName = null;
        _selectedVendorId = null;
      });
    }
    switch (hit.kind) {
      case BdoMapHitKind.workerNode:
        final node = widget.dataset.workerNodesById[hit.id];
        if (node == null) {
          return;
        }
        _handleWorkerNodeTap(node);
        break;
      case BdoMapHitKind.gatheringSpot:
        final spot = widget.dataset.gatheringSpotsById[hit.id];
        if (spot == null) {
          return;
        }
        _selectSpot(spot);
        break;
      case BdoMapHitKind.gatheringPoint:
        final point = widget.dataset.gatheringPointsById[hit.id];
        if (point == null) {
          return;
        }
        _selectPoint(point);
        break;
      case BdoMapHitKind.gatheringPointCluster:
        final bounds =
            hit.clusterBounds ??
            _boundsForPoints(
              hit.clusterPointIds
                  .map((id) => widget.dataset.gatheringPointsById[id])
                  .whereType<BdoGatheringPoint>()
                  .map((point) => point.location.mapPoint)
                  .toList(growable: false),
            );
        if (bounds != null && !_viewport.isEmpty) {
          _fitBoundsAvoidingDetails(
            bounds.inflate(6000),
            padding: 70,
            maximumZoom: math.max(4.6, _cameraController.camera.zoom + 1.8),
          );
        }
        break;
      case BdoMapHitKind.gatheringRoute:
        final route = widget.dataset.gatheringRoutesById[hit.id];
        if (route == null) {
          return;
        }
        _selectRoute(route);
        break;
      case BdoMapHitKind.workerCluster:
        final points = hit.clusterNodeIds
            .map((id) => widget.dataset.workerNodesById[id])
            .whereType<BdoWorkerNode>()
            .map((node) => node.location.mapPoint)
            .toList();
        final bounds = _boundsForPoints(points);
        if (bounds != null && !_viewport.isEmpty) {
          _fitBoundsAvoidingDetails(
            bounds.inflate(18000),
            padding: 100,
            maximumZoom: _cameraController.camera.zoom + 1.8,
          );
        }
        break;
    }
  }

  BdoProductionNodePath? _quickPathForNodeId(String nodeId) {
    final node = widget.dataset.workerNodesById[nodeId];
    if (node == null || !node.isProductionNode) {
      return null;
    }
    final result = const BdoProductionNodePathCostService().calculate(
      data: widget.dataset,
      request: BdoProductionNodePathRequest(
        targetNodeId: node.id,
        currentNodeIds: _nodeNetworkPreferences.currentNodeIds,
        allowedRootNodeIds: _effectiveNetworkRootNodeIds,
      ),
    );
    return result.minimumIncrementalPath ?? result.minimumTotalPath;
  }

  void _toggleNodeInCurrentSetup(BdoWorkerNode node) {
    if (_isNaturalWorkerRoot(node)) {
      setState(() {
        _nodeNetworkSaveMessage =
            '${node.siteName} is a free town node and does not need investment.';
      });
      return;
    }
    final nextIds = <String>{
      for (final id in _nodeNetworkPreferences.currentNodeIds)
        if (widget.dataset.workerNodesById[id] case final current?
            when !_isNaturalWorkerRoot(current))
          id,
    };
    final invested = nextIds.add(node.id);
    if (!invested) {
      nextIds.remove(node.id);
    }
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: nextIds,
    );
    _replaceNodeNetworkPreferences(preferences);
    setState(() {
      _currentNodeDraftIds = <String>{...nextIds};
      _selectedQuickNodePath = _desktopNetworkWorkbenchVisible
          ? null
          : _quickPathForNodeId(node.id);
      _nodeNetworkSaveMessage = invested
          ? '${node.siteName} saved as invested.'
          : '${node.siteName} removed from invested nodes.';
    });
  }

  void _toggleInvestNodeMode() {
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    final enabling = !_investNodeMode;
    if (enabling) {
      _clearSelection();
    }
    setState(() {
      _investNodeMode = enabling;
      _desktopTaskSurfaceCollapsed = enabling;
      _desktopSheetExpanded = true;
      _showWorkerNodes = true;
      _showConnections = true;
      _nodeNetworkSaveMessage = _investNodeMode
          ? 'Invest mode is on. Click nodes to save or remove them.'
          : null;
    });
  }

  void _addSelectedQuickNodeRoute() {
    final path = _selectedQuickNodePath;
    if (path == null) {
      return;
    }
    final nextIds = <String>{
      for (final id in _nodeNetworkPreferences.currentNodeIds)
        if (widget.dataset.workerNodesById[id] case final current?
            when !_isNaturalWorkerRoot(current))
          id,
      for (final id in path.orderedNodeIds)
        if (widget.dataset.workerNodesById[id] case final routeNode?
            when !_isNaturalWorkerRoot(routeNode))
          id,
    };
    final preferences = _nodeNetworkPreferences.copyWith(
      currentNodeIds: nextIds,
    );
    _replaceNodeNetworkPreferences(preferences, rebuildPlan: false);
    setState(() {
      _currentNodeDraftIds = <String>{...nextIds};
      _selectedQuickNodePath = _quickPathForNodeId(path.targetNodeId);
      _nodeNetworkSaveMessage =
          'Complete route saved in your planner setup. Nothing changed in BDO.';
    });
  }

  void _selectNode(BdoWorkerNode node, {bool focus = false}) {
    if (_selectedNodeId != node.id) {
      _pushNavigationEntry();
    }
    final quickPath = _quickPathForNodeId(node.id);
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _searchResultsVisible = false;
      _showWorkerNodes = true;
      _selectedNodeId = node.id;
      _selectedHouseId = null;
      if (_storagePlannerTownNodeId != node.id) {
        _storagePlannerTownNodeId = null;
      }
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = quickPath;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
    });
    if (focus && !_viewport.isEmpty) {
      _showPointAvoidingDetails(node.location);
    }
  }

  void _selectSpot(BdoGatheringSpot spot, {bool focus = false}) {
    if (_selectedSpotId != spot.id || _selectedPointId != null) {
      _pushNavigationEntry();
    }
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _searchResultsVisible = false;
      _showGathering = true;
      _selectedSpotId = spot.id;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
    });
    if (focus && !_viewport.isEmpty) {
      _fitGatheringSpot(spot, resourceId: _selectedResourceId);
    }
  }

  void _selectPoint(BdoGatheringPoint point, {bool focus = false}) {
    if (_selectedPointId != point.id) {
      _pushNavigationEntry();
    }
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _searchResultsVisible = false;
      _showGathering = true;
      _selectedPointId = point.id;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = point.areaId;
      _selectedRouteId = null;
    });
    if (focus && !_viewport.isEmpty) {
      _showPointAvoidingDetails(point.location, zoom: 6.1);
    }
  }

  void _selectRoute(BdoGatheringRoute route, {bool focus = false}) {
    if (_selectedRouteId != route.id) {
      _pushNavigationEntry();
    }
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _searchResultsVisible = false;
      _showRoutes = true;
      _selectedRouteId = route.id;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
    });
    if (focus && !_viewport.isEmpty) {
      _fitBoundsAvoidingDetails(route.bounds.inflate(12000), padding: 54);
    }
  }

  BdoFieldProduct? _preferredProductForFieldSource(
    BdoFieldSource source, {
    String? preferredResourceId,
  }) {
    if (source.products.isEmpty) {
      return null;
    }
    if (preferredResourceId != null) {
      for (final product in source.products) {
        if (product.resourceId == preferredResourceId) {
          return product;
        }
      }
    }
    var candidates = source.products;
    final section = _selectedResourceSection;
    if (section != null) {
      final matching = source.products
          .where(
            (product) =>
                widget.dataset.resourcesById[product.resourceId]?.section ==
                section,
          )
          .toList(growable: false);
      if (matching.isNotEmpty) {
        candidates = matching;
      }
    }
    if (_browseFavorites) {
      final matching = candidates
          .where((product) => _favoriteResourceIds.contains(product.resourceId))
          .toList(growable: false);
      if (matching.isNotEmpty) {
        candidates = matching;
      }
    }
    var preferred = candidates.first;
    var preferredSourceCount = widget.dataset
        .fieldSourcesForResource(preferred.resourceId)
        .length;
    for (final product in candidates.skip(1)) {
      final sourceCount = widget.dataset
          .fieldSourcesForResource(product.resourceId)
          .length;
      if (sourceCount < preferredSourceCount) {
        preferred = product;
        preferredSourceCount = sourceCount;
      }
    }
    return preferred;
  }

  void _selectFieldSource(
    BdoFieldSource source, {
    String? preferredResourceId,
    bool focus = true,
  }) {
    if (_selectedFieldSourceId != source.id || _hasChildDetailSelection) {
      _pushNavigationEntry();
    }
    final product = _preferredProductForFieldSource(
      source,
      preferredResourceId: preferredResourceId,
    );
    final resourceId = product?.resourceId;
    final hasGathering =
        widget.dataset.gatheringPointsForFieldSource(source.id).isNotEmpty ||
        source.products.any(
          (item) =>
              widget.dataset
                  .gatheringSpotsForResource(item.resourceId)
                  .isNotEmpty ||
              widget.dataset
                  .gatheringRoutesForResource(item.resourceId)
                  .isNotEmpty,
        );
    _searchFocus.unfocus();
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _selectedFieldSourceId = source.id;
      _selectedResourceId = resourceId;
      _materialSourceFilter = _MaterialSourceFilter.manual;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _showConnections = false;
      _showWorkerNodes = false;
      if (hasGathering) {
        _showGathering = true;
      }
    });
    if (focus) {
      _focusFieldSource(source.id);
    }
  }

  void _selectResourceFromDetails(BdoResourceDefinition resource) {
    if (_selectedResourceId != resource.id || _hasChildDetailSelection) {
      _pushNavigationEntry();
    }
    final resourceId = resource.id;
    final hasWorkerNodes = widget.dataset
        .workerNodesForResource(resourceId)
        .isNotEmpty;
    final hasGathering =
        widget.dataset.gatheringSpotsForResource(resourceId).isNotEmpty ||
        widget.dataset.gatheringPointsForResource(resourceId).isNotEmpty;
    final hasRoutes = widget.dataset
        .gatheringRoutesForResource(resourceId)
        .isNotEmpty;
    setState(() {
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _desktopSheetExpanded = true;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _selectedFieldSourceId = _preferredFieldSourceId(resourceId);
      _selectedResourceId = resourceId;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _browseAllWorkerNodes = false;
      _workerOverviewSelectionMade = false;
      _gatherChecklistOpen = false;
      _gatherPlanShortlistOpen = false;
      _nodeNetworkPlannerOpen = false;
      _showConnections = false;
      if (hasWorkerNodes) {
        _showWorkerNodes = true;
      }
      if (hasGathering) {
        _showGathering = true;
      }
      if (hasRoutes) {
        _showRoutes = true;
      }
    });
    if (_selectedFieldSourceId case final sourceId?
        when _focusFieldSource(sourceId)) {
      return;
    }
    if (!_fitPreferredResourceFocus(resourceId)) {
      _fitResource(resourceId);
    }
  }

  void _handleViewportChanged(Size size) {
    final previousViewport = _viewport;
    _viewport = size;
    if (size.isEmpty) {
      return;
    }
    if (!_initialViewportFitted) {
      _initialViewportFitted = true;
      _fitVisibleContentOrReset();
      return;
    }
    if (previousViewport != size && !previousViewport.isEmpty) {
      _cameraController.setCamera(_cameraController.camera, size);
    }
  }

  void _fitVisibleContentOrReset() {
    if (_viewport.isEmpty) {
      return;
    }
    final pointId = _selectedPointId;
    if (pointId != null) {
      final point = widget.dataset.gatheringPointsById[pointId];
      if (point != null) {
        _showPointAvoidingDetails(point.location, zoom: 6.1);
        return;
      }
    }
    final spotId = _selectedSpotId;
    if (spotId != null) {
      final spot = widget.dataset.gatheringSpotsById[spotId];
      if (spot != null) {
        _fitGatheringSpot(spot, resourceId: _selectedResourceId);
        return;
      }
    }
    final routeId = _selectedRouteId;
    if (routeId != null) {
      final route = widget.dataset.gatheringRoutesById[routeId];
      if (route != null) {
        _fitBoundsAvoidingDetails(route.bounds.inflate(12000), padding: 54);
        return;
      }
    }
    final nodeId = _selectedNodeId;
    if (nodeId != null) {
      final node = widget.dataset.workerNodesById[nodeId];
      if (node != null) {
        _showPointAvoidingDetails(node.location);
        return;
      }
    }
    final fieldSourceId = _selectedFieldSourceId;
    if (fieldSourceId != null && _focusFieldSource(fieldSourceId)) {
      return;
    }
    final resourceId = _selectedResourceId;
    if (resourceId != null) {
      if (_fitPreferredResourceFocus(resourceId) || _fitResource(resourceId)) {
        return;
      }
      _cameraController.reset(_viewport);
      return;
    }
    if (_browseAllWorkerNodes && _workerOverviewSelectionMade) {
      _fitBrowseOverview(
        widget.dataset.workerNodes
            .where(
              (node) =>
                  node.isResourceNode &&
                  (_workerActivityFilter == null ||
                      node.activity == _workerActivityFilter),
            )
            .map((node) => node.location.mapPoint),
      );
      return;
    }
    _cameraController.reset(_viewport);
  }

  void _fitGatheringSpot(BdoGatheringSpot spot, {String? resourceId}) {
    final exactPoints = widget.dataset.gatheringPoints
        .where(
          (point) =>
              point.areaId == spot.id &&
              (resourceId == null || point.resourceIds.contains(resourceId)),
        )
        .map((point) => point.location.mapPoint)
        .toList(growable: false);
    final exactBounds = _boundsForPoints(
      exactPoints,
      minimumSpan: _minimumGatheringFocusWorldSpan,
    );
    if (exactBounds != null) {
      _fitBoundsAvoidingDetails(
        exactBounds,
        padding: 64,
        maximumZoom: _gatheringFocusMaximumZoom,
      );
      return;
    }
    final areaBounds = spot.areaBounds;
    if (areaBounds != null) {
      _fitBoundsAvoidingDetails(areaBounds, padding: 54, maximumZoom: 5.7);
      return;
    }
    _showPointAvoidingDetails(spot.location);
  }

  void _fitBoundsAvoidingDetails(
    BdoMapBounds bounds, {
    double padding = 54,
    double maximumZoom = 6.4,
  }) {
    if (_viewport.isEmpty) {
      return;
    }
    final insets = _detailFitInsets;
    final effectivePadding = _fitPaddingForInsets(padding, insets);
    _cameraController.fitBounds(
      bounds,
      viewport: _viewport,
      padding: effectivePadding,
      maximumZoom: maximumZoom,
      insetLeft: insets.left,
      insetTop: insets.top,
      insetRight: insets.right,
      insetBottom: insets.bottom,
    );
  }

  double _fitPaddingForInsets(
    double requestedPadding,
    ({double left, double top, double right, double bottom}) insets,
  ) {
    if (!_compactLayout || !_hasDetailSelection) {
      return requestedPadding;
    }

    double maximumPaddingFor(double availableSpan) {
      final protectedBand = math.min(
        _minimumCompactFitBand,
        math.max(0, availableSpan),
      );
      return math.max(0, (availableSpan - protectedBand) / 2);
    }

    final availableWidth = _viewport.width - insets.left - insets.right;
    final availableHeight = _viewport.height - insets.top - insets.bottom;
    return math.min(
      requestedPadding,
      math.min(
        maximumPaddingFor(availableWidth),
        maximumPaddingFor(availableHeight),
      ),
    );
  }

  void _showPointAvoidingDetails(BdoWorldPoint point, {double zoom = 5.4}) {
    final center = point.mapPoint;
    _fitBoundsAvoidingDetails(
      BdoMapBounds(
        left: center.x - 1,
        top: center.y - 1,
        right: center.x + 1,
        bottom: center.y + 1,
      ),
      padding: 0,
      maximumZoom: zoom,
    );
  }

  ({double left, double top, double right, double bottom})
  get _detailFitInsets {
    if (_viewport.isEmpty) {
      return (left: 0, top: 0, right: 0, bottom: 0);
    }
    if (!_compactLayout) {
      if (_desktopTaskSurfaceCollapsed) {
        return (left: 0, top: 0, right: 0, bottom: 0);
      }
      if (_desktopNetworkWorkbenchVisible) {
        return (
          left: 0,
          top: 0,
          right: _activeDesktopRightAvoidanceWidth,
          bottom: 0,
        );
      }
      return (
        left: _activeDesktopLeftAvoidanceWidth,
        top: 0,
        right: 0,
        bottom: 0,
      );
    }
    if (!_hasDetailSelection) {
      return (left: 0, top: 0, right: 0, bottom: 0);
    }
    if (_compactLayout) {
      return (
        left: 0,
        top: math.min(112.0, _viewport.height * 0.18),
        right: 0,
        bottom: math.min(
          _compactDetailsBottomInset + _compactDetailsMaximumHeight,
          _viewport.height * 0.58,
        ),
      );
    }
    return (left: 0, top: 0, right: 0, bottom: 0);
  }

  bool get _hasChildDetailSelection =>
      (_selectedVendorId != null && !_compactLayout) ||
      _selectedNodeId != null ||
      _selectedSpotId != null ||
      _selectedPointId != null ||
      _selectedRouteId != null;

  bool get _canReturnToSelectedResource =>
      _selectedResourceId != null && _hasChildDetailSelection;

  void _dismissDetails() {
    _navigationHistory.clear();
    _dismissDetailsWithoutHistory();
  }

  void _dismissDetailsWithoutHistory() {
    if (!_hasChildDetailSelection) {
      _clearSelection();
      return;
    }
    final keepWorkerSearchOpen = _emphasizedWorkerNodeIds.isNotEmpty;
    setState(() {
      _selectedVendorId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      if (!keepWorkerSearchOpen) {
        _searchResults = const <BdoSearchResult>[];
        _searchResultsVisible = false;
      }
    });
  }

  void _clearSelection({bool resetSearch = false}) {
    _navigationHistory.clear();
    setState(() {
      _selectedFieldSourceId = null;
      _selectedResourceId = null;
      _selectedNodeId = null;
      _selectedHouseId = null;
      _nodeQuickPanelOpen = false;
      _selectedQuickNodePath = null;
      _selectedSpotId = null;
      _selectedPointId = null;
      _selectedRouteId = null;
      _vendorLookupItemName = null;
      _selectedVendorId = null;
      _explicitWorkerEmphasisNodeIds = <String>{};
      _searchResults = const <BdoSearchResult>[];
      _searchResultsVisible = false;
      _showConnections = false;
      if (resetSearch) {
        _searchController.clear();
      }
    });
  }

  void _dismissTransientMapUi() {
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    if (_desktopWorkerMenuVisible && _workerMenuSection != null) {
      setState(() => _workerMenuSection = null);
      return;
    }
    if (_desktopGatherMenuVisible && _gatherMenuSection != null) {
      setState(() => _gatherMenuSection = null);
      return;
    }
    if (_desktopStewardMenuVisible) {
      _openMapHome();
      return;
    }
    if (_investNodeMode) {
      setState(() {
        _investNodeMode = false;
        _desktopTaskSurfaceCollapsed = false;
        _nodeNetworkSaveMessage = null;
      });
      return;
    }
    if (_layersMenuOpen) {
      setState(() => _layersMenuOpen = false);
      return;
    }
    if (_searchResultsVisible) {
      setState(() => _searchResultsVisible = false);
      return;
    }
    if (_selectedVendorId != null) {
      setState(() => _selectedVendorId = null);
      return;
    }
    if (_vendorClusterPickerIds.isNotEmpty) {
      _closeVendorClusterPicker();
      return;
    }
    if (_vendorLookupItemName != null) {
      _navigateBack();
      return;
    }
    if (_hasDetailSelection) {
      _dismissDetails();
      return;
    }
    if (_nodeNetworkPlannerOpen) {
      switch (_nodeNetworkPlannerPage) {
        case _NodeNetworkPlannerPage.home:
          _navigateBack();
          break;
        case _NodeNetworkPlannerPage.editCurrent:
          unawaited(_cancelCurrentNodeEditing());
          break;
        case _NodeNetworkPlannerPage.review:
          _returnFromNodeReview();
          break;
        case _NodeNetworkPlannerPage.targets:
        case _NodeNetworkPlannerPage.marketValue:
          _leaveNodePlannerGoal();
          break;
      }
    }
  }

  void _dismissMapTapUi() {
    _searchFocus.unfocus();
    _mapKeyboardFocus.requestFocus();
    if (_desktopStewardMenuVisible) {
      _openMapHome();
      return;
    }
    if (_layersMenuOpen) {
      setState(() => _layersMenuOpen = false);
      return;
    }
    if (_searchResultsVisible) {
      setState(() => _searchResultsVisible = false);
      return;
    }
    if (_selectedVendorId != null) {
      setState(() => _selectedVendorId = null);
      return;
    }
    if (_vendorClusterPickerIds.isNotEmpty) {
      _closeVendorClusterPicker();
      return;
    }
    if (_hasDetailSelection) {
      _dismissDetails();
    }
  }

  void _focusSearchBox() {
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
    if (_searchController.text.trim().isNotEmpty) {
      _search(_searchController.text, showResults: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapTheme = _buildMapTheme(context);
    final opacity = context.mapChrome.uiOpacity;
    final opacityChanged = _lastBuiltOpacity != opacity;
    _lastBuiltOpacity = opacity;
    return ResourceMapAnnotationScope(
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape):
              _dismissTransientMapUi,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openMapSearch,
        },
        child: Focus(
          focusNode: _mapKeyboardFocus,
          autofocus: true,
          child: AnimatedTheme(
            data: mapTheme,
            duration: opacityChanged || MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : ResourceMapAtlasMotion.settle,
            curve: ResourceMapAtlasMotion.curve,
            child: Builder(
              builder: (context) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < _resourceMapCompactBreakpoint;
                    _compactLayout = compact;
                    return Material(
                      color: context.mapChrome.canvas,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: ExcludeFocus(
                              excluding: _showSourceNotice,
                              child: IgnorePointer(
                                ignoring: _showSourceNotice,
                                child: compact
                                    ? _buildCompactLayout(context, constraints)
                                    : _buildDesktopLayout(context, constraints),
                              ),
                            ),
                          ),
                          if (_showSourceNotice)
                            Positioned.fill(child: _buildSourceNotice(context)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _resourceSectionLabel(BdoResourceSection section) {
    if (_materialSourceFilter == _MaterialSourceFilter.manual &&
        section == BdoResourceSection.seafoodMarine) {
      return 'Coastal gathering';
    }
    return section.label;
  }

  double _atlasPanelTop(BuildContext context, double viewportWidth) =>
      16 +
      ResourceMapJourneySurface.headerHeight(context) +
      ResourceMapPanelMetrics.searchHeight(context) +
      8;

  Widget _buildAtlasDesktopLayout(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final resultsOpen =
        _searchController.text.trim().isNotEmpty && _searchResultsVisible;
    final focusedTask =
        _nodeNetworkPlannerOpen ||
        _housingDirectoryOpen ||
        _royalWorkshopVisible ||
        _gatherChecklistOpen ||
        _gatherPlanShortlistOpen ||
        _browseAllWorkerNodes;
    final inspectorOpen =
        _hasDetailSelection &&
        !_nodeNetworkPlannerOpen &&
        !_housingDirectoryOpen &&
        !_royalWorkshopVisible &&
        !_gatherChecklistOpen &&
        !_gatherPlanShortlistOpen &&
        !resultsOpen &&
        !_plannedLodgingSummaryVisible;
    final home =
        !resultsOpen &&
        !inspectorOpen &&
        !focusedTask &&
        !_browseFavorites &&
        _selectedResourceSection == null &&
        !_materialCatalogOpen &&
        _vendorLookupItemName == null &&
        _desktopMapMode == null;
    final minimized = _desktopTaskSurfaceCollapsed && !home && !resultsOpen;
    final setupOpen = _desktopWorkerMenuVisible;
    final materialsOpen = _materialCatalogOpen || _desktopGatherMenuVisible;
    final railWidth = (200.0 * MediaQuery.textScalerOf(context).scale(14) / 14)
        .clamp(200.0, 270.0);
    final taskLeft = railWidth + 28;
    final width = math
        .min(
          inspectorOpen
              ? _atlasDetailsContentWidth(context)
              : _housingDirectoryOpen && _selectedHousingTown != null
              ? _housingContentWidth(context, _selectedHousingTown!)
              : _selectedResourceSection != null
              ? _atlasWorkspaceContentWidth(context)
              : home
              ? _atlasLabelContentWidth(
                  context,
                  const ['Find a material', 'Worker income', 'Houses'],
                  minimum: ResourceMapPanelMetrics.menuWidth,
                  maximum: 360,
                  allowance: 82,
                )
              : _atlasWorkspaceContentWidth(context),
          constraints.maxWidth - taskLeft - 32,
        )
        .toDouble();
    final height = math.max(0.0, constraints.maxHeight - 32);
    final duration = ResourceMapAtlasMotion.resolve(
      context,
      ResourceMapAtlasMotion.quick,
    );
    final title = resultsOpen
        ? 'Search results'
        : home
        ? 'Resource Map'
        : inspectorOpen
        ? 'Resource Map'
        : _browseFavorites
        ? 'Saved'
        : setupOpen
        ? 'Your setup'
        : !focusedTask && _selectedResourceSection == null && materialsOpen
        ? 'Materials'
        : _atlasWorkspaceTitle;

    void back() {
      if (resultsOpen) {
        _clearSearchQuery();
      } else if (inspectorOpen || _browseFavorites) {
        _navigateBack();
      } else if (focusedTask || _selectedResourceSection != null) {
        _atlasWorkspaceBack();
      } else {
        _navigateBack();
      }
    }

    // Rail actions are independent destinations, now reachable from every task.
    // Clear the previous presentation before invoking its existing entry point.
    // Preferences, saved plans and the map controller remain in this State.
    void openRailTask(VoidCallback open) {
      _openMapHome();
      open();
    }

    Widget navigation() => ResourceMapDiscoveryHome(
      planArtwork: widget.recipePlanArtwork,
      selectedAction: resultsOpen
          ? null
          : _housingDirectoryOpen
          ? 'houses'
          : _browseFavorites
          ? 'saved'
          : _gatherChecklistOpen
          ? 'checklist'
          : _nodeNetworkPlannerOpen
          ? 'worker-income'
          : materialsOpen || _selectedResourceSection != null
          ? 'find-material'
          : null,
      onFindMaterial: () => openRailTask(_openMaterialDiscovery),
      onWorkerIncome: () => openRailTask(_openWorkerIncomePlanner),
      onHouses: widget.lodgingDataset == null
          ? null
          : () => openRailTask(_openHousingDirectory),
      onSaved: () => openRailTask(_openFavorites),
      onTodoList: () => openRailTask(_openGatherChecklist),
      onPlanMaterials: () => openRailTask(_openWorkerMaterialPlanner),
      onPlannerNeeds:
          widget.plannerNeeds.any(
                (need) =>
                    need.missingQuantity.isFinite && need.missingQuantity > 0,
              ) ||
              widget.plannerNeedGroups.any(
                (group) => group.materials.any(
                  (material) =>
                      material.need.missingQuantity.isFinite &&
                      material.need.missingQuantity > 0,
                ),
              )
          ? () => openRailTask(_openWorkerRecipePlanner)
          : null,
      onBrowseWorkerNodes: () => openRailTask(_openWorkerOverview),
      onSetup: () => openRailTask(_openWorkerHub),
    );

    Widget content() {
      if (resultsOpen) {
        return _buildSearchResults(context, constrained: false);
      }
      if (inspectorOpen) {
        return KeyedSubtree(
          key: const ValueKey('resource-map-sidebar-details'),
          child: Focus(
            key: const ValueKey('resource-map-sidebar-details-focus'),
            focusNode: _detailsKeyboardFocus,
            onKeyEvent: _handleDetailsKeyEvent,
            child: SingleChildScrollView(
              controller: _detailsScrollController,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: _buildSelectedDetailsContent(),
            ),
          ),
        );
      }
      if (_browseFavorites) {
        return Padding(
          key: const ValueKey('resource-map-saved-list'),
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildSavedMapEntries(context),
        );
      }
      if (setupOpen) {
        return _buildWorkerTaskHub(context, setupOnly: true, framed: false);
      }
      if (!focusedTask && _selectedResourceSection == null && materialsOpen) {
        return ResourceMapAtlasCommandMenu(
          key: const ValueKey('resource-map-material-categories'),
          semanticsLabel: 'Materials',
          framed: false,
          actions: [
            if (_manualPlannerTargets().isNotEmpty)
              ResourceMapAtlasCommandAction(
                key: const ValueKey('resource-map-gather-plan-shortlist'),
                label: 'Needed for your plan',
                icon: const ResourceMapMenuArtwork(
                  kind: ResourceMapMenuArtworkKind.plan,
                ),
                onPressed: _openGatherPlanShortlist,
              ),
            for (final section in BdoResourceSection.values)
              if (_browserEntryCountForSection(section) > 0)
                ResourceMapAtlasCommandAction(
                  key: ValueKey('resource-map-section-${section.name}'),
                  label: _resourceSectionLabel(section),
                  icon: _buildResourceSectionArtwork(context, section),
                  onPressed: () => _openResourceSection(section),
                ),
          ],
        );
      }
      return _buildAtlasWorkspaceContent(context);
    }

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(child: _buildMapSurface(context, compact: false)),
          Positioned(
            key: const ValueKey('resource-map-field-desk-position'),
            left: 12,
            top: 12,
            width: railWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight - 24,
              ),
              child: ResourceMapFieldDesk(
                key: const ValueKey('resource-map-field-desk'),
                onHome: _openMapHome,
                controls: _buildPanelOpacityControl(context),
                search: ResourceMapAtlasSearch(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  hintText: 'Search the map',
                  onChanged: _searchWholeMap,
                  onSubmitted: (_) => _submitSearch(),
                  onTap: () {
                    if (_searchController.text.trim().isNotEmpty) {
                      _searchWholeMap(
                        _searchController.text,
                        showResults: true,
                      );
                    }
                  },
                  onClear: _clearSearchQuery,
                ),
                navigation: navigation(),
              ),
            ),
          ),
          if (minimized)
            Positioned(
              left: taskLeft,
              top: 16,
              child: SizedBox(
                width: ResourceMapPanelMetrics.menuWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ResourceMapAtlasTaskChip(
                      key: const ValueKey('resource-map-atlas-task-chip'),
                      title: inspectorOpen ? _currentNavigationLabel : title,
                      leading: _atlasWorkspaceLeading,
                      onRestore: () => _setDesktopSheetExpanded(true),
                      onClose: _openMapHome,
                    ),
                  ],
                ),
              ),
            )
          else if (!home &&
              !(_vendorLookupItemName != null &&
                  !inspectorOpen &&
                  !focusedTask &&
                  !resultsOpen))
            Positioned(
              key: const ValueKey('resource-map-workspace-position'),
              left: inspectorOpen ? null : taskLeft,
              right: inspectorOpen ? 88 : null,
              top: 16,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height),
                child: ResourceMapJourneySurface(
                  key: const ValueKey('resource-map-atlas-dock'),
                  framedBody: true,
                  title: title,
                  onBack: home ? null : back,
                  onHome: widget.recipeWorkerBuilder != null || home
                      ? null
                      : _openMapHome,
                  onMinimize: widget.recipeWorkerBuilder != null || home
                      ? null
                      : _collapseDesktopTaskSurface,
                  child: AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: KeyedSubtree(
                      key: ValueKey(
                        resultsOpen
                            ? 'search'
                            : home
                            ? 'home'
                            : inspectorOpen
                            ? 'detail-$_selectedFieldSourceId-$_selectedResourceId-'
                                  '$_selectedNodeId-$_selectedSpotId-$_selectedPointId-'
                                  '$_selectedRouteId-$_selectedVendorId'
                            : _nodeNetworkPlannerOpen &&
                                  widget.recipeWorkerBuilder != null
                            ? 'recipe-workers'
                            : title,
                      ),
                      child: content(),
                    ),
                  ),
                ),
              ),
            ),
          // Transient map tools must paint above the persistent desk and task
          // surface. They remain separate from the camera/marker render layers.
          Positioned.fill(
            child: _buildPlannedLodgingSummaryOverlay(
              Size(constraints.maxWidth, constraints.maxHeight),
            ),
          ),
          if (_desktopTaskSurfaceCollapsed)
            Positioned.fill(
              child: _buildSelectedHouseOverlay(
                Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
          if (_vendorLookupItemName != null && !inspectorOpen)
            Positioned(
              left: taskLeft,
              top: 16,
              width: math.min(430, constraints.maxWidth - taskLeft - 88),
              child: _buildVendorLookupBanner(context),
            ),
          if (_investNodeMode)
            Positioned(
              right: 88,
              bottom: 12,
              child: _buildInvestModeBanner(context),
            ),
          Positioned.fill(
            child: _buildVendorClusterPickerOverlay(
              Size(constraints.maxWidth, constraints.maxHeight),
            ),
          ),
        ],
      ),
    );
  }

  double _housingContentWidth(BuildContext context, LodgingTown town) {
    double measure(String label) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: TownHousePanelMetrics.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var width = 320.0;
    for (final goal in _goalsForTown(town).where((g) => g.typeId > 3)) {
      final house = town.houses.firstWhere((h) => h.supportsUsage(goal.typeId));
      width = math.max(
        width,
        measure(house.usagesByTypeId[goal.typeId]!.label) + 142,
      );
    }
    final ids = _browseAllTownHouses
        ? town.housesById.keys
        : <String>{
            ...?_townInvestmentFor(town)?.requiredHouseIds,
            ?_selectedHouseId,
          };
    for (final id in ids) {
      final house = town.housesById[id];
      if (house != null) width = math.max(width, measure(house.name) + 120);
    }
    return width.clamp(320, 420).toDouble();
  }

  double _atlasLabelContentWidth(
    BuildContext context,
    Iterable<String> labels, {
    double minimum = ResourceMapPanelMetrics.menuWidth,
    double maximum = 440,
    double allowance = 100,
    double fontSize = ResourceMapPanelMetrics.primary,
  }) {
    var width = minimum;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width = math.max(width, painter.width + allowance);
      painter.dispose();
    }
    return width.clamp(minimum, maximum);
  }

  double _atlasWorkspaceContentWidth(BuildContext context) {
    if (_nodeNetworkPlannerOpen) {
      return _atlasLabelContentWidth(
        context,
        [
          _atlasWorkspaceTitle,
          for (final id
              in _nodeNetworkPreferences.desiredResourceNodeCounts.keys)
            widget.dataset.resourcesById[id]?.name ?? '',
        ],
        minimum: 300,
        maximum: 380,
        allowance: 140,
      );
    }
    if (_gatherChecklistOpen) {
      return _atlasLabelContentWidth(
        context,
        [
          'To-do list',
          for (final entry in _gatherChecklist.entries)
            widget.dataset.resourcesById[entry.resourceId]?.name ??
                entry.displayName ??
                entry.resourceId,
        ],
        minimum: 300,
        allowance: 140,
      );
    }
    if (_selectedResourceSection != null) {
      return _atlasLabelContentWidth(context, [
        _resourceSectionLabel(_selectedResourceSection!),
        ..._fieldSourcesForCurrentBrowser().map((source) => source.name),
        ..._resourcesForCurrentBrowser().map((resource) => resource.name),
      ], allowance: 136);
    }
    return _atlasLabelContentWidth(
      context,
      [_atlasWorkspaceTitle, 'Browse worker nodes'],
      minimum: 280,
      maximum: 350,
    );
  }

  double _atlasDetailsContentWidth(BuildContext context) {
    final node = widget.dataset.workerNodesById[_selectedNodeId];
    final source = _selectedFieldSource;
    final resource = widget.dataset.resourcesById[_selectedResourceId];
    return _atlasLabelContentWidth(
      context,
      [
        _currentNavigationLabel,
        if (node != null) ...node.outputs.map((output) => output.name),
        if (source != null)
          for (final product in source.products)
            widget.dataset.resourcesById[product.resourceId]?.name ?? '',
        if (resource != null && source == null) ...[
          ...widget.dataset
              .fieldSourcesForResource(resource.id)
              .map((entry) => entry.name),
          ...widget.dataset
              .workerNodesForResource(resource.id)
              .map((entry) => entry.siteName),
        ],
      ],
      minimum: 320,
      allowance: source == null ? 104 : 150,
    );
  }

  // Legacy palette builder retained only for rollback comparison.
  // ignore: unused_element
  Widget _buildAtlasSearchPalette(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 7),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _searchResults.isEmpty
                      ? 'No matches'
                      : '${_searchResults.length} matches',
                  style: TextStyle(
                    color: context.mapChrome.muted,
                    fontSize: ResourceMapPanelMetrics.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Enter to open first result',
                style: TextStyle(
                  color: context.mapChrome.muted.withValues(alpha: .8),
                  fontSize: ResourceMapPanelMetrics.secondary,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: context.mapChrome.softOutline.withValues(alpha: .6),
        ),
        Expanded(child: _buildSearchResults(context, constrained: false)),
      ],
    );
  }

  String get _atlasWorkspaceTitle {
    if (_royalWorkshopVisible) return 'Royal Workshop';
    if (_nodeNetworkPlannerOpen) {
      return switch (_nodeNetworkPlannerPage) {
        _NodeNetworkPlannerPage.home =>
          widget.recipeWorkerTitle ?? 'Plan a worker network',
        _NodeNetworkPlannerPage.editCurrent => 'Current network',
        _NodeNetworkPlannerPage.targets => 'Choose materials',
        _NodeNetworkPlannerPage.review => 'Review network',
        _NodeNetworkPlannerPage.marketValue => 'Worker income',
      };
    }
    if (_housingDirectoryOpen) {
      return _selectedHousingTown?.name ?? 'Houses';
    }
    if (_gatherChecklistOpen) return 'To-do list';
    if (_gatherPlanShortlistOpen) return 'Needed for your plan';
    if (_browseAllWorkerNodes) return 'Worker nodes';
    if (_browseFavorites) return 'Favorites';
    if (_selectedResourceSection case final section?) {
      return _resourceSectionLabel(section);
    }
    return _desktopMapMode == _DesktopMapMode.workers
        ? 'Worker tools'
        : 'Gathering';
  }

  Widget get _atlasWorkspaceLeading {
    if (_desktopMapMode == _DesktopMapMode.workers) {
      return const ResourceMapStewardIcon(
        kind: ResourceMapStewardIconKind.workersMode,
        size: 29,
      );
    }
    return const ResourceMapStewardIcon(
      kind: ResourceMapStewardIconKind.gatherMode,
      size: 29,
    );
  }

  void _atlasWorkspaceBack() {
    if (_housingDirectoryOpen) {
      _navigateBackFromHousing();
      return;
    }
    if (_nodeNetworkPlannerOpen) {
      switch (_nodeNetworkPlannerPage) {
        case _NodeNetworkPlannerPage.editCurrent:
          unawaited(_cancelCurrentNodeEditing());
        case _NodeNetworkPlannerPage.review:
          _returnFromNodeReview();
        case _NodeNetworkPlannerPage.targets ||
            _NodeNetworkPlannerPage.marketValue:
          _leaveNodePlannerGoal();
        case _NodeNetworkPlannerPage.home:
          if (widget.onRecipeWorkerBack?.call() != true) _navigateBack();
      }
      return;
    }
    _navigateBack();
  }

  Widget _buildAtlasWorkspaceContent(BuildContext context) {
    if (_royalWorkshopVisible) return _buildRoyalWorkshopPage(context);
    if (_desktopNetworkWorkbenchVisible) {
      return _buildDesktopNetworkWorkbench(context);
    }
    if (_nodeNetworkPlannerOpen) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: _buildNodeNetworkPlannerPage(context),
      );
    }
    if (_gatherChecklistOpen) return _buildGatherChecklistPage(context);
    if (_gatherPlanShortlistOpen) return _buildGatherPlanShortlistPage(context);
    if (_housingDirectoryOpen) {
      final town = _selectedHousingTown;
      if (town != null) {
        return KeyedSubtree(
          key: const ValueKey<String>('resource-map-sidebar-details'),
          child: SingleChildScrollView(
            controller: _detailsScrollController,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
            child: _buildTownHousingDetails(town),
          ),
        );
      }
      return _buildHousingDirectoryPage(context);
    }
    if (_browseAllWorkerNodes) return _buildWorkerExplorerPage(context);
    if (_selectedResourceSection != null || _browseFavorites) {
      return _buildResourceBrowserPage(context);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: _desktopMapMode == _DesktopMapMode.workers
          ? _buildWorkerTaskHub(context)
          : _buildGatherTaskHub(context),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    BoxConstraints constraints,
  ) => _buildAtlasDesktopLayout(context, constraints);

  Widget _buildDesktopNetworkWorkbench(BuildContext context) {
    final page = _nodeNetworkPlannerPage;
    Widget workbench = KeyedSubtree(
      key: ValueKey<String>('resource-map-network-workbench-mode-${page.name}'),
      child: Semantics(
        key: const ValueKey<String>('resource-map-network-workbench'),
        container: true,
        explicitChildNodes: true,
        label: 'Worker network plan, ${page.name}',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (page != _NodeNetworkPlannerPage.targets &&
                  page != _NodeNetworkPlannerPage.editCurrent &&
                  page != _NodeNetworkPlannerPage.review) ...<Widget>[
                _buildNetworkWorkbenchHeader(context),
                Divider(
                  height: 6,
                  color: context.mapChrome.softOutline.withValues(alpha: .7),
                ),
              ],
              Flexible(
                fit: FlexFit.loose,
                child: _buildNetworkWorkbenchBody(context),
              ),
            ],
          ),
        ),
      ),
    );
    if (page == _NodeNetworkPlannerPage.marketValue &&
        widget.workerEconomics != null) {
      workbench = Theme(
        data: _buildWorkerIncomeAtlasTheme(context),
        child: workbench,
      );
    }
    return workbench;
  }

  Widget _buildNetworkWorkbenchHeader(BuildContext context) {
    final page = _nodeNetworkPlannerPage;
    if (page == _NodeNetworkPlannerPage.editCurrent) {
      return const SizedBox.shrink();
    }
    final market = page == _NodeNetworkPlannerPage.marketValue;
    final commitBudget = market
        ? _commitMarketValueBudget
        : () => _commitNodeBudget(
            rebuildPlan: page == _NodeNetworkPlannerPage.review,
          );
    final settings = market && widget.workerEconomics != null
        ? MapQuietIconButton(
            key: const ValueKey<String>('resource-map-worker-income-settings'),
            tooltip: 'Estimate settings',
            onPressed: _openWorkerIncomeSettings,
            icon: const Icon(Icons.tune_rounded, size: 18),
          )
        : null;
    final budget = TextField(
      key: market
          ? const ValueKey<String>('resource-map-market-value-cp-budget')
          : const ValueKey<String>('resource-map-node-cp-budget'),
      controller: _nodeBudgetController,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => commitBudget(),
      onTapOutside: (_) {
        FocusScope.of(context).unfocus();
        commitBudget();
      },
      decoration: const InputDecoration(
        labelText: 'Network CP limit',
        isDense: true,
      ),
    );
    final apply = FilledButton(
      key: market
          ? const ValueKey<String>('resource-map-market-value-apply-cp')
          : const ValueKey<String>('resource-map-node-apply-cp'),
      onPressed: commitBudget,
      child: const Text('Update'),
    );
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    final header = Padding(
      key: ValueKey<String>('resource-map-node-planner-header-${page.name}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: largeText
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ?settings,
                    Expanded(child: budget),
                  ],
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: apply),
              ],
            )
          : Row(
              children: [
                ?settings,
                Expanded(child: budget),
                const SizedBox(width: 6),
                apply,
              ],
            ),
    );
    return market
        ? ResourceMapPill(padding: const EdgeInsets.all(8), child: header)
        : header;
  }

  Widget _buildNetworkWorkbenchBody(BuildContext context) {
    if (_nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent) {
      return _buildCurrentNodeWorkbench(context);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
        final marketValuePage =
            _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.marketValue;
        final useSideContext =
            constraints.maxWidth >= 920 && !largeText && !marketValuePage;
        final planner = KeyedSubtree(
          key: const ValueKey<String>('resource-map-network-workbench-body'),
          child: KeyedSubtree(
            key: const ValueKey<String>(
              'resource-map-network-workbench-scroll',
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _buildNodeNetworkPlannerPage(context),
            ),
          ),
        );
        if (!useSideContext) {
          final showCompactContext =
              _selectedNodeId != null && !marketValuePage;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (showCompactContext) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
                  child: _buildNetworkWorkbenchContext(compact: true),
                ),
                SizedBox(
                  height: 1,
                  child: ColoredBox(color: context.mapChrome.brassDeep),
                ),
              ],
              Flexible(fit: FlexFit.loose, child: planner),
            ],
          );
        }
        final contextWidth = (constraints.maxWidth * .245)
            .clamp(236.0, 302.0)
            .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: contextWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(17, 12, 15, 12),
                child: _buildNetworkWorkbenchContext(compact: false),
              ),
            ),
            SizedBox(
              width: 1,
              child: ColoredBox(color: context.mapChrome.brassDeep),
            ),
            Expanded(child: planner),
          ],
        );
      },
    );
  }

  Widget _buildNetworkWorkbenchContext({required bool compact}) {
    final selectedNode = _selectedNodeId == null
        ? null
        : widget.dataset.workerNodesById[_selectedNodeId!];
    if (selectedNode != null) {
      return _buildNetworkWorkbenchNodeDetails(selectedNode, compact: compact);
    }
    return const SizedBox.shrink();
  }

  Widget _buildNetworkWorkbenchNodeDetails(
    BdoWorkerNode node, {
    required bool compact,
  }) {
    final nodeColor = _colorForWorkerNode(context, node);
    final nodeIcon = _iconForWorkerNode(node);
    final availableWorkerNodeCount = node.isResourceNode
        ? 0
        : widget.dataset.workerNodes
              .where(
                (candidate) =>
                    candidate.isResourceNode && candidate.parentId == node.id,
              )
              .length;
    final heading = Row(
      children: <Widget>[
        SizedBox.square(
          dimension: 34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.mapChrome.graphiteRaised,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: nodeColor.withValues(alpha: .5)),
            ),
            child: Icon(nodeIcon, size: 19, color: nodeColor),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                node.siteName,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.secondary,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${node.isResourceNode ? node.activity.label : node.nodeType} '
                '· ${node.contributionPoints} CP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.mapChrome.muted,
                  fontSize: ResourceMapPanelMetrics.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final unlockGuide = bdoExcavationUnlockGuideFor(node);
    final unlockMarkerId = unlockGuide == null
        ? null
        : 'excavation:${unlockGuide.managerGameNpcId}';
    Widget buildOutputs({required double artworkSize}) {
      if (node.outputs.isEmpty) return const SizedBox.shrink();
      return Wrap(
        spacing: 9,
        runSpacing: 7,
        children: <Widget>[
          for (final output in node.outputs)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildWorkerOutputArtwork(
                  context,
                  widget.dataset.resourcesById[output.resourceId],
                  size: artworkSize,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 142),
                  child: Text(
                    output.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.mapChrome.ink,
                      fontSize: ResourceMapPanelMetrics.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    }

    Widget buildUnlockGuide() {
      if (unlockGuide == null) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 9),
          Text(
            'EXCAVATION ACCESS',
            style: TextStyle(
              color: context.mapChrome.accent,
              fontSize: ResourceMapPanelMetrics.secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: .65,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            unlockGuide.unlockInstructions,
            maxLines: compact ? 3 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: TextStyle(
              color: context.mapChrome.muted,
              fontSize: ResourceMapPanelMetrics.secondary,
              height: 1.32,
            ),
          ),
          if (unlockGuide.managerLocation != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>(
                  'resource-map-network-workbench-toggle-manager-marker',
                ),
                onPressed: () => _toggleManagerMarker(
                  id: unlockMarkerId!,
                  name: unlockGuide.managerName,
                  location: unlockGuide.managerLocation!,
                  contextLabel: 'excavation node manager location',
                ),
                icon: Icon(
                  _markedManager?.id == unlockMarkerId
                      ? Icons.location_off_outlined
                      : Icons.location_on_outlined,
                  size: 16,
                ),
                label: Text(
                  _markedManager?.id == unlockMarkerId
                      ? 'Hide ${unlockGuide.managerName}'
                      : 'Mark ${unlockGuide.managerName} on map',
                ),
              ),
            ),
        ],
      );
    }

    if (compact) {
      return KeyedSubtree(
        key: const ValueKey<String>(
          'resource-map-network-workbench-node-details',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            heading,
            if (node.outputs.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              buildOutputs(artworkSize: 34),
            ],
            buildUnlockGuide(),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey<String>(
        'resource-map-network-workbench-node-details',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'SELECTED NODE',
            style: TextStyle(
              color: context.mapChrome.accent,
              fontSize: ResourceMapPanelMetrics.secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: .75,
            ),
          ),
          const SizedBox(height: 7),
          heading,
          if (availableWorkerNodeCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '$availableWorkerNodeCount worker '
              '${availableWorkerNodeCount == 1 ? 'node' : 'nodes'} available',
              style: TextStyle(
                color: context.mapChrome.text,
                fontSize: ResourceMapPanelMetrics.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (node.outputs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            buildOutputs(artworkSize: 34),
          ],
          buildUnlockGuide(),
        ],
      ),
    );
  }

  Widget _buildCurrentNodeWorkbench(BuildContext context) {
    final selectedNode = _selectedNodeId == null
        ? null
        : widget.dataset.workerNodesById[_selectedNodeId!];
    return SingleChildScrollView(
      key: const ValueKey<String>('resource-map-network-workbench-scroll'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final blockWidth = wide
              ? math.max(250.0, (constraints.maxWidth - 36) / 3)
              : constraints.maxWidth;
          return Wrap(
            spacing: 18,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: blockWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[_buildCurrentNodeSearch()],
                ),
              ),
              SizedBox(
                width: blockWidth,
                child: selectedNode == null
                    ? const SizedBox.shrink()
                    : _buildNetworkWorkbenchNodeDetails(
                        selectedNode,
                        compact: true,
                      ),
              ),
              SizedBox(
                width: blockWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (_nodeNetworkInputError case final error?)
                      _NodePlannerNotice(
                        icon: Icons.error_outline_rounded,
                        message: error,
                        color: context.mapChrome.error,
                      ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        TextButton(
                          key: const ValueKey<String>(
                            'resource-map-clear-current-node-draft',
                          ),
                          onPressed: _currentNodeDraftIds.isEmpty
                              ? null
                              : _clearCurrentNodeDraft,
                          child: const Text('Clear draft'),
                        ),
                        TextButton(
                          key: const ValueKey<String>(
                            'resource-map-cancel-current-node-edit',
                          ),
                          onPressed: () =>
                              unawaited(_cancelCurrentNodeEditing()),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey<String>(
                            'resource-map-save-current-node-draft',
                          ),
                          onPressed: _saveCurrentNodeDraft,
                          icon: const Icon(Icons.save_outlined, size: 17),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNodePlannerFloatingHeader(
    BuildContext context, {
    required bool compact,
  }) {
    final page = _nodeNetworkPlannerPage;
    if (!compact &&
        page == _NodeNetworkPlannerPage.marketValue &&
        widget.workerEconomics != null) {
      return _buildWorkerIncomeAtlasHeader(context);
    }
    final title = switch (page) {
      _NodeNetworkPlannerPage.home => 'Worker planner',
      _NodeNetworkPlannerPage.editCurrent => 'Save node setup',
      _NodeNetworkPlannerPage.targets => 'Planned materials',
      _NodeNetworkPlannerPage.review => 'Review network',
      _NodeNetworkPlannerPage.marketValue =>
        widget.workerEconomics == null
            ? 'Raw-sale price signals'
            : 'Worker income plan',
    };
    final backTooltip = switch (page) {
      _NodeNetworkPlannerPage.home => 'Back to resource map',
      _NodeNetworkPlannerPage.editCurrent => 'Cancel editing',
      _NodeNetworkPlannerPage.targets || _NodeNetworkPlannerPage.marketValue =>
        _compactLayout ? 'Back to planner goals' : 'Back to Workers',
      _NodeNetworkPlannerPage.review =>
        _nodeNetworkReviewOrigin == _NodeNetworkPlannerPage.targets
            ? 'Back to material choices'
            : _compactLayout
            ? 'Back to planner goals'
            : 'Back to Workers',
    };
    final backAction = switch (page) {
      _NodeNetworkPlannerPage.home => _navigateBack,
      _NodeNetworkPlannerPage.editCurrent => () => unawaited(
        _cancelCurrentNodeEditing(),
      ),
      _NodeNetworkPlannerPage.targets ||
      _NodeNetworkPlannerPage.marketValue => _leaveNodePlannerGoal,
      _NodeNetworkPlannerPage.review => _returnFromNodeReview,
    };
    final backKey = page == _NodeNetworkPlannerPage.review
        ? const ValueKey<String>('resource-map-node-planner-back-targets')
        : page == _NodeNetworkPlannerPage.home && compact
        ? const ValueKey<String>('resource-map-node-planner-close')
        : ValueKey<String>('resource-map-node-planner-back-${page.name}');

    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 190),
      child: Column(
        key: ValueKey<String>('resource-map-node-planner-header-${page.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 5 : 7,
                6,
                compact ? 7 : 9,
                7,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      MapQuietIconButton(
                        key: backKey,
                        onPressed: backAction,
                        tooltip: backTooltip,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.arrow_back_rounded, size: 19),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.primary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (page != _NodeNetworkPlannerPage.editCurrent &&
                      page != _NodeNetworkPlannerPage.review) ...<Widget>[
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Semantics(
                            label: 'Contribution points available',
                            textField: true,
                            child: TextField(
                              key: page == _NodeNetworkPlannerPage.marketValue
                                  ? const ValueKey<String>(
                                      'resource-map-market-value-cp-budget',
                                    )
                                  : const ValueKey<String>(
                                      'resource-map-node-cp-budget',
                                    ),
                              controller: _nodeBudgetController,
                              keyboardType: TextInputType.number,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onSubmitted: (_) {
                                if (page ==
                                    _NodeNetworkPlannerPage.marketValue) {
                                  _commitMarketValueBudget();
                                } else {
                                  _commitNodeBudget(
                                    rebuildPlan:
                                        page == _NodeNetworkPlannerPage.review,
                                  );
                                }
                              },
                              onTapOutside: (_) {
                                FocusScope.of(context).unfocus();
                                if (page ==
                                    _NodeNetworkPlannerPage.marketValue) {
                                  _commitMarketValueBudget();
                                } else {
                                  _commitNodeBudget(
                                    rebuildPlan:
                                        page == _NodeNetworkPlannerPage.review,
                                  );
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: 'CP available',
                                isDense: true,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: page == _NodeNetworkPlannerPage.marketValue
                              ? const ValueKey<String>(
                                  'resource-map-market-value-apply-cp',
                                )
                              : const ValueKey<String>(
                                  'resource-map-node-apply-cp',
                                ),
                          onPressed: page == _NodeNetworkPlannerPage.marketValue
                              ? _commitMarketValueBudget
                              : () => _commitNodeBudget(
                                  rebuildPlan:
                                      page == _NodeNetworkPlannerPage.review,
                                ),
                          child: const Text('Update'),
                        ),
                      ],
                    ),
                  ],
                  if (page == _NodeNetworkPlannerPage.editCurrent) ...<Widget>[
                    const SizedBox(height: 4),
                    _buildCurrentNodeSearch(),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runAlignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        TextButton(
                          key: const ValueKey<String>(
                            'resource-map-clear-current-node-draft',
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: _currentNodeDraftIds.isEmpty
                              ? null
                              : _clearCurrentNodeDraft,
                          child: const Text('Clear draft'),
                        ),
                        TextButton(
                          key: const ValueKey<String>(
                            'resource-map-cancel-current-node-edit',
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () =>
                              unawaited(_cancelCurrentNodeEditing()),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey<String>(
                            'resource-map-save-current-node-draft',
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _saveCurrentNodeDraft,
                          icon: const Icon(Icons.save_outlined, size: 17),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                  if (_nodeNetworkInputError case final error?) ...<Widget>[
                    const SizedBox(height: 6),
                    _NodePlannerNotice(
                      icon: Icons.error_outline_rounded,
                      message: error,
                      color: context.mapChrome.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerIncomeAtlasHeader(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final cpInput = Semantics(
      label: 'Contribution points available',
      textField: true,
      child: TextField(
        key: const ValueKey<String>('resource-map-market-value-cp-budget'),
        controller: _nodeBudgetController,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        onSubmitted: (_) => _commitMarketValueBudget(),
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          _commitMarketValueBudget();
        },
        decoration: const InputDecoration(
          labelText: 'CP available',
          isDense: true,
        ),
      ),
    );
    final updateButton = FilledButton.icon(
      key: const ValueKey<String>('resource-map-market-value-apply-cp'),
      onPressed: _commitMarketValueBudget,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Update'),
    );
    return Semantics(
      container: true,
      header: true,
      label: 'Best worker setup',
      child: Column(
        key: const ValueKey<String>(
          'resource-map-node-planner-header-marketValue',
        ),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runAlignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              TextButton.icon(
                key: const ValueKey<String>(
                  'resource-map-node-planner-back-marketValue',
                ),
                onPressed: _leaveNodePlannerGoal,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
              ),
              TextButton.icon(
                key: const ValueKey<String>(
                  'resource-map-worker-income-settings',
                ),
                onPressed: _openWorkerIncomeSettings,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Adjust estimate'),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Best worker setup',
            style: TextStyle(
              color: context.mapChrome.ink,
              fontSize: 21,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 11),
          if (largeText)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                cpInput,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: updateButton),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(child: cpInput),
                const SizedBox(width: 10),
                updateButton,
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentNodeSearch() {
    return Autocomplete<BdoWorkerNode>(
      key: const ValueKey<String>('resource-map-current-node-search'),
      optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
      displayStringForOption: (node) => node.siteName,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) {
          return const <BdoWorkerNode>[];
        }
        final matches =
            widget.dataset.workerNodes
                .where(
                  (node) =>
                      node.isProductionNode &&
                      (node.siteName.toLowerCase().contains(query) ||
                          node.region.toLowerCase().contains(query) ||
                          node.outputs.any(
                            (output) =>
                                output.name.toLowerCase().contains(query),
                          )),
                )
                .toList(growable: false)
              ..sort((left, right) {
                final leftStarts = left.siteName.toLowerCase().startsWith(
                  query,
                );
                final rightStarts = right.siteName.toLowerCase().startsWith(
                  query,
                );
                if (leftStarts != rightStarts) {
                  return leftStarts ? -1 : 1;
                }
                return left.siteName.compareTo(right.siteName);
              });
        return matches.take(12);
      },
      onSelected: (node) => _addCurrentWorkerDestination(node),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
            key: const ValueKey<String>(
              'resource-map-current-node-search-field',
            ),
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
            onSubmitted: (_) => onFieldSubmitted(),
            decoration: const InputDecoration(
              hintText: 'Add a staffed production node',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) {
        final values = options.toList(growable: false);
        return LayoutBuilder(
          builder: (context, constraints) {
            final preferredWidth = readableSelectMenuWidth(
              context,
              values.map((node) => node.siteName),
              triggerWidth: constraints.maxWidth,
              horizontalChrome: 76,
              minimumWidth: 0,
            );
            final menuWidth = math.min(preferredWidth, constraints.maxWidth);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                key: const ValueKey<String>(
                  'resource-map-current-node-options',
                ),
                elevation: 18,
                shadowColor: const Color(0x3A17211F),
                color: context.mapChrome.paperRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                  side: BorderSide(color: context.mapChrome.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: menuWidth,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: values.length,
                      itemBuilder: (context, index) {
                        final node = values[index];
                        final marked = _currentNodeDraftIds.contains(node.id);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            marked
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: marked
                                ? context.mapChrome.primary
                                : context.mapChrome.muted,
                            size: 18,
                          ),
                          title: Text(
                            node.siteName,
                            softWrap: true,
                            maxLines: null,
                            overflow: TextOverflow.visible,
                          ),
                          subtitle: Text(
                            <String>[
                              if (node.region.isNotEmpty) node.region,
                              if (node.outputs.isNotEmpty)
                                node.outputs
                                    .take(2)
                                    .map((output) => output.name)
                                    .join(', '),
                              '${node.contributionPoints} CP',
                            ].join(' · '),
                            softWrap: true,
                            maxLines: null,
                            overflow: TextOverflow.visible,
                          ),
                          onTap: () => onSelected(node),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCompactLayout(BuildContext context, BoxConstraints constraints) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final searchWidth = math
        .min(math.max(0.0, constraints.maxWidth - 24), 480)
        .toDouble();
    final overlayMaximumHeight = math
        .max(0.0, constraints.maxHeight - _compactDetailsBottomInset - 12)
        .toDouble();
    final searchResultsMaximumHeight = math
        .max(0.0, constraints.maxHeight - 126)
        .toDouble();
    final nodePlannerHasContext =
        _nodeNetworkPlannerOpen &&
        _nodeNetworkPlannerPage != _NodeNetworkPlannerPage.editCurrent;
    final shortPlannerLayout =
        nodePlannerHasContext && constraints.maxHeight < 420;
    final compactOverlay = _royalWorkshopVisible
        ? _buildRoyalWorkshopPage(context)
        : _hasDetailSelection
        ? _buildDetailsCard(context, compact: true)
        : nodePlannerHasContext
        ? _buildCompactNodeNetworkPlanner(
            context,
            includeHeader: shortPlannerLayout,
          )
        : _gatherChecklistOpen
        ? _buildCompactGatherChecklist(context)
        : _browseAllWorkerNodes
        ? _buildCompactWorkerExplorer(context)
        : const SizedBox.shrink(
            key: ValueKey<String>('resource-map-compact-overlay-empty'),
          );
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _buildMapSurface(context, compact: true)),
        if (!_royalWorkshopVisible &&
            ((!_nodeNetworkPlannerOpen && !_gatherChecklistOpen) ||
                _hasDetailSelection))
          Positioned(
            left: 12,
            top: 12,
            width: searchWidth,
            child: _buildCompactSearchPanel(
              context,
              resultsMaximumHeight: searchResultsMaximumHeight,
            ),
          ),
        if (!_royalWorkshopVisible &&
            !_hasDetailSelection &&
            _vendorLookupItemName == null &&
            !_nodeNetworkPlannerOpen &&
            !_gatherChecklistOpen &&
            !_browseAllWorkerNodes &&
            !_searchResultsVisible)
          Positioned(
            left: 12,
            right: 12,
            top: 76,
            child: _buildCompactExploreButton(),
          ),
        if (_nodeNetworkPlannerOpen && !shortPlannerLayout)
          Positioned(
            left: 12,
            top: 12,
            right: 72,
            child: Material(
              key: const ValueKey<String>(
                'resource-map-compact-node-planner-header-surface',
              ),
              color: context.mapChrome.paperRaised,
              elevation: 8,
              shadowColor: const Color(0x4017211F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: context.mapChrome.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildNodePlannerFloatingHeader(context, compact: true),
            ),
          ),
        Positioned(
          right: shortPlannerLayout ? 238 : 12,
          left: 12,
          bottom: _compactDetailsBottomInset,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: overlayMaximumHeight),
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              reverseDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, .08),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: compactOverlay,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapSurface(BuildContext context, {required bool compact}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortCompactPlanner =
            compact && _nodeNetworkPlannerOpen && constraints.maxHeight < 420;
        const desktopRightPanelInset = 16.0;
        final zoomControlTop = shortCompactPlanner
            ? 12.0
            : compact
            ? (_nodeNetworkPlannerOpen ? 168.0 : 78.0)
            : 16.0;
        final layerControlTop = shortCompactPlanner
            ? 12.0
            : zoomControlTop +
                  ResourceMapZoomDock.sliderExtent +
                  ResourceMapZoomDock.controlExtent +
                  11;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: _handleMapSurfacePointerSignal,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: BdoMapCanvas(
                  cameraController: _cameraController,
                  tileManager: _tileManager,
                  chromeTheme: context.mapChrome,
                  workerNodes: _visibleWorkerNodes,
                  workerNodesById: widget.dataset.workerNodesById,
                  gatheringSpots: _visibleGatheringSpots,
                  gatheringPoints: _visibleGatheringPoints,
                  gatheringRoutes: _visibleGatheringRoutes,
                  showConnections: _showConnections,
                  showAllNetworkConnections: _showAllNetworkConnections,
                  nodeNetworkEdgeChanges: _visibleNodeNetworkEdgeChanges,
                  nodeNetworkChangeKinds: _visibleNodeNetworkChangeKinds,
                  activeNodeIds: _nodeNetworkPreferences.currentNodeIds,
                  emphasizedNodeIds: _emphasizedWorkerNodeIds,
                  emphasisRevision: _workerEmphasisRevision,
                  prioritizePlannedNetwork: _emphasizedWorkerNodeIds.isEmpty,
                  declutterWorkerLabelsForOutputArtwork:
                      _showWorkerOutputArtwork,
                  workerOutputArtworkMinimumZoom:
                      _workerOutputArtworkMinimumZoom,
                  visualStyle: BdoMapVisualStyle.vivid,
                  selectedNodeId: _selectedNodeId,
                  selectedSpotId: _selectedSpotId,
                  selectedPointId: _selectedPointId,
                  selectedRouteId: _selectedRouteId,
                  handlePointerSignals: false,
                  onHit: _handleMapHit,
                  onEmptyTap: _dismissMapTapUi,
                  onViewportChanged: _handleViewportChanged,
                  markerOverlays: <Widget>[
                    Positioned.fill(
                      child: _buildLandmarkOverlay(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ),
                    Positioned.fill(
                      child: _buildLodgingTownBadgeOverlay(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ),
                    Positioned.fill(
                      child: _buildHousingOverlay(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ),
                    Positioned.fill(
                      child: _buildAllNodeOverlay(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ),
                    Positioned.fill(
                      child: _buildWorkerOutputArtworkOverlay(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ),
                    Positioned.fill(
                      child: _buildVendorMarkerOverlay(
                        Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: ResourceMapAnnotationClip(
                  child: _buildManagerMarkerOverlay(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              ),
              Positioned(
                right: shortCompactPlanner ? 72 : desktopRightPanelInset,
                top: zoomControlTop,
                child: _buildZoomControls(context, compact: false),
              ),
              Positioned(
                right: desktopRightPanelInset,
                top: layerControlTop,
                child: _buildMapLayerControls(
                  context,
                  maximumMenuWidth: math.max(0.0, constraints.maxWidth - 32),
                  maximumMenuHeight: shortCompactPlanner
                      ? math.max(100.0, constraints.maxHeight - 63).toDouble()
                      : math
                            .max(
                              0.0,
                              constraints.maxHeight - layerControlTop - 56,
                            )
                            .toDouble(),
                ),
              ),
              if ((!shortCompactPlanner ||
                      (compact && widget.onUiOpacityChanged != null)) &&
                  (compact ||
                      !_desktopNetworkWorkbenchVisible ||
                      _desktopTaskSurfaceCollapsed))
                Positioned(
                  left: 12,
                  bottom: compact ? 8 : 12,
                  width: math.min(
                    compact ? 300 : 360,
                    math.max(0, constraints.maxWidth - 24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (compact && widget.onUiOpacityChanged != null)
                        _buildPanelOpacityControl(context)!,
                      if (!shortCompactPlanner &&
                          widget.recipeWorkerBuilder == null)
                        _buildStatusBar(context, compact: true),
                    ],
                  ),
                ),
              if (compact && _vendorLookupItemName != null)
                Positioned(
                  left: 12,
                  top: compact
                      ? null
                      : _atlasPanelTop(context, constraints.maxWidth),
                  bottom: compact ? _compactDetailsBottomInset + 2 : null,
                  width: math.min(430, math.max(0, constraints.maxWidth - 96)),
                  child: _buildVendorLookupBanner(context),
                ),
              if (compact && _investNodeMode)
                Positioned(
                  left: !compact && _activeDesktopLeftAvoidanceWidth > 0
                      ? _activeDesktopLeftAvoidanceWidth + 12
                      : 12,
                  top: compact
                      ? null
                      : _atlasPanelTop(context, constraints.maxWidth),
                  bottom: compact ? _compactDetailsBottomInset + 8 : null,
                  child: _buildInvestModeBanner(context),
                ),
              if (compact)
                Positioned.fill(
                  child: _buildVendorClusterPickerOverlay(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
              if (_compactLayout)
                Positioned.fill(
                  child: _buildSelectedVendorOverlay(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInvestModeBanner(BuildContext context) {
    return Material(
      key: const ValueKey<String>('resource-map-invest-mode-banner'),
      elevation: 8,
      color: context.mapChrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.mapChrome.primary),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 7, 6, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.bookmark_added_rounded,
              size: 18,
              color: context.mapChrome.primary,
            ),
            const SizedBox(width: 7),
            Text(
              'Edit nodes',
              style: TextStyle(
                color: context.mapChrome.ink,
                fontSize: ResourceMapPanelMetrics.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey<String>('resource-map-invest-mode-done'),
              onPressed: _toggleInvestNodeMode,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(48, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandmarkOverlay(Size viewport) {
    if (viewport.isEmpty || (!_showKnownTowns && !_showNodeHubs)) {
      return const SizedBox.shrink();
    }
    return _SettledCameraSnapshotOverlay(
      cameraController: _cameraController,
      viewport: viewport,
      builder: (context, geometry) {
        final snapshotViewport = geometry.snapshotSize;
        final visibleViewport = geometry.visibleViewport;
        final zoom = _cameraController.camera.zoom;
        final candidates =
            <({BdoWorkerNode node, Offset position, _MapLandmarkKind kind})>[];
        for (final node in widget.dataset.workerNodes) {
          final kind = _visibleLandmarkKind(node, zoom);
          if (kind == null) {
            continue;
          }
          final position = _cameraController.worldToScreen(
            node.location.mapPoint,
            snapshotViewport,
          );
          if (position.dx < -120 ||
              position.dy < -24 ||
              position.dx > snapshotViewport.width + 24 ||
              position.dy > snapshotViewport.height + 24) {
            continue;
          }
          candidates.add((node: node, position: position, kind: kind));
        }
        final center = snapshotViewport.center(Offset.zero);
        candidates.sort((left, right) {
          final byKind = left.kind.index.compareTo(right.kind.index);
          if (byKind != 0) {
            return byKind;
          }
          final byDistance = (left.position - center).distanceSquared.compareTo(
            (right.position - center).distanceSquared,
          );
          return byDistance != 0
              ? byDistance
              : left.node.id.compareTo(right.node.id);
        });
        final occupied = <Rect>[
          Rect.fromLTWH(
            math.max(visibleViewport.left, visibleViewport.right - 210),
            visibleViewport.top,
            math.min(210, visibleViewport.width),
            math.min(278, visibleViewport.height),
          ),
        ];
        final markers = <Widget>[];
        for (final candidate in candidates) {
          final labelWidth = math
              .min(154.0, 39 + candidate.node.siteName.length * 6.2)
              .toDouble();
          final bounds = Rect.fromLTWH(
            candidate.position.dx - 13,
            candidate.position.dy - 17,
            labelWidth,
            34,
          );
          if (occupied.any((other) => other.inflate(4).overlaps(bounds))) {
            continue;
          }
          occupied.add(bounds);
          markers.add(
            Positioned(
              key: ValueKey<String>(
                'resource-map-landmark-${candidate.node.id}',
              ),
              left: bounds.left,
              top: bounds.top,
              child: RepaintBoundary(
                child: _MapLandmarkMarker(
                  node: candidate.node,
                  label: candidate.node.siteName,
                  kind: candidate.kind,
                  active: _nodeIconIsActive(candidate.node),
                  semanticLabel: _investNodeMode
                      ? '${_nodeNetworkPreferences.currentNodeIds.contains(candidate.node.id) ? 'Remove' : 'Save'} '
                            '${candidate.node.siteName} as an invested node'
                      : _nodeNetworkPlannerOpen &&
                            _nodeNetworkPlannerPage ==
                                _NodeNetworkPlannerPage.editCurrent
                      ? '${_currentNodeDraftIds.contains(candidate.node.id) ? 'Unmark' : 'Mark'} '
                            '${candidate.node.siteName} as an in-game node'
                      : null,
                  onTap: () => _handleWorkerNodeTap(candidate.node),
                ),
              ),
            ),
          );
          if (markers.length >= (36 * geometry.areaScale).ceil()) {
            break;
          }
        }
        return IgnorePointer(
          ignoring: _gatheringLayerOwnsMapTaps,
          child: Stack(children: markers),
        );
      },
    );
  }

  void _handleMapSurfacePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _viewport.isEmpty) {
      return;
    }
    final delta = (-event.scrollDelta.dy / 240)
        .clamp(-_maximumOverlayWheelZoomStep, _maximumOverlayWheelZoomStep)
        .toDouble();
    if (delta == 0) {
      return;
    }
    _cameraController.zoomAround(
      zoom: _cameraController.camera.zoom + delta,
      anchor: event.localPosition,
      viewport: _viewport,
    );
  }

  Widget _buildHousingOverlay(Size viewport) {
    final town = _selectedHousingTown;
    if (town == null || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    return _SettledCameraSnapshotOverlay(
      cameraController: _cameraController,
      viewport: viewport,
      builder: (context, geometry) {
        final snapshotViewport = geometry.snapshotSize;
        final zoom = _cameraController.camera.zoom;
        final combined = _housingDirectoryOpen
            ? _townInvestmentFor(town)
            : null;
        final networkPlan = _displayedLodgingPlanForTown(town);
        Set<String> selectedUse(int type) =>
            combined?.usages.entries
                .where((e) => e.value == type)
                .map((e) => e.key)
                .toSet() ??
            {};
        final recommendedStorage = selectedUse(2);
        final recommendedHouseUse =
            combined?.usages.entries
                .where((e) => e.value > 2)
                .map((e) => e.key)
                .toSet() ??
            <String>{};
        final recommendedLodging = _housingDirectoryOpen
            ? selectedUse(1)
            : networkPlan.selectedLodgingHouseIds.toSet();
        final recommendedNew = _housingDirectoryOpen
            ? (combined?.requiredHouseIds ?? <String>{})
            : networkPlan.newlyRequiredHouseIds.toSet();
        final recommendedPrerequisites = _housingDirectoryOpen
            ? (<String>{...recommendedNew}
                ..removeAll(combined?.usages.keys ?? []))
            : networkPlan.prerequisiteHouseIds.toSet();
        final visibleHouseIds = _visibleHousingHouseIds(town);
        final positions = <String, Offset>{
          for (final house in town.houses)
            house.id: _cameraController.worldToScreen(
              _houseMapPoint(house),
              snapshotViewport,
            ),
        };
        final visibleHouses = town.houses
            .where((house) {
              if (!visibleHouseIds.contains(house.id)) {
                return false;
              }
              final position = positions[house.id]!;
              return position.dx >= -40 &&
                  position.dy >= -40 &&
                  position.dx <= snapshotViewport.width + 40 &&
                  position.dy <= snapshotViewport.height + 40;
            })
            .toList(growable: false);
        if (zoom < 4.8) {
          final townPoint = BdoWorldPoint(
            town.position.x,
            town.position.z,
          ).mapPoint;
          final position = _cameraController.worldToScreen(
            townPoint,
            snapshotViewport,
          );
          if (position.dx < -80 ||
              position.dy < -40 ||
              position.dx > snapshotViewport.width + 40 ||
              position.dy > snapshotViewport.height + 40) {
            return const SizedBox.shrink();
          }
          return Stack(
            children: <Widget>[
              Positioned(
                key: ValueKey<String>(
                  'resource-map-house-cluster-${town.townNodeId}',
                ),
                left: position.dx - 19,
                top: position.dy + 15,
                child: _revealSelectedHouse(
                  houseId: _selectedHouseId,
                  child: _ScreenshotImportPulse(
                    active: town.houses.any(
                      (house) => _screenshotImportedHouseIds.contains(house.id),
                    ),
                    revision: _screenshotHousePulseRevision,
                    child: _HouseClusterMarker(
                      count: town.houses.length,
                      label: 'Open ${town.houses.first.name}',
                      kind: recommendedStorage.isNotEmpty
                          ? BdoMapSymbolKind.storage
                          : recommendedLodging.isNotEmpty
                          ? BdoMapSymbolKind.lodging
                          : recommendedHouseUse.isNotEmpty
                          ? _houseSymbolKindForUsage(
                              _housePlannerUsagesForTown(town).singleWhere(
                                (usage) =>
                                    usage.typeId ==
                                    _housePlannerUsageTypeForTown(town),
                              ),
                            )
                          : BdoMapSymbolKind.residence,
                      states: bdoMapSymbolStates(
                        recommendedStorage: recommendedStorage.isNotEmpty,
                        recommendedLodging: recommendedLodging.isNotEmpty,
                        recommendedHouseUse: recommendedHouseUse.isNotEmpty,
                        selected: _selectedHouseId != null,
                      ),
                      onTap: () => _selectHouse(
                        _selectedHouseId == null
                            ? town.houses.first
                            : town.housesById[_selectedHouseId!] ??
                                  town.houses.first,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final owned = _ownedHouseIdsForTown(town);
        int housePriority(LodgingHouse house) {
          if (house.id == _selectedHouseId) return 0;
          if (recommendedStorage.contains(house.id)) return 1;
          if (recommendedHouseUse.contains(house.id)) return 2;
          if (recommendedPrerequisites.contains(house.id)) return 3;
          if (owned.contains(house.id)) return 4;
          if (recommendedLodging.contains(house.id)) return 5;
          if (recommendedNew.contains(house.id)) return 6;
          return 7;
        }

        _HouseMarkerStatus houseStatus(LodgingHouse house) {
          if (recommendedStorage.contains(house.id)) {
            return _HouseMarkerStatus.recommendedStorage;
          }
          if (recommendedHouseUse.contains(house.id)) {
            return _HouseMarkerStatus.recommendedHouseUse;
          }
          if (recommendedPrerequisites.contains(house.id) &&
              !owned.contains(house.id)) {
            return _HouseMarkerStatus.recommendedPrerequisite;
          }
          if (owned.contains(house.id)) {
            return _HouseMarkerStatus.owned;
          }
          if (recommendedLodging.contains(house.id)) {
            return _HouseMarkerStatus.recommendedLodging;
          }
          if (recommendedNew.contains(house.id) ||
              recommendedPrerequisites.contains(house.id)) {
            return _HouseMarkerStatus.recommendedPrerequisite;
          }
          return _HouseMarkerStatus.available;
        }

        final sortedVisibleHouses = visibleHouses.toList()
          ..sort((left, right) {
            final byPriority = housePriority(
              left,
            ).compareTo(housePriority(right));
            return byPriority != 0
                ? byPriority
                : left.sourceKey.compareTo(right.sourceKey);
          });
        final houseClusters = <List<LodgingHouse>>[];
        final clusterAnchors = <Offset>[];
        final clusterFootprints = <Rect>[];
        for (final house in sortedVisibleHouses) {
          final position = positions[house.id]!;
          var nearestCluster = -1;
          var nearestDistanceSquared = double.infinity;
          final candidateFootprint = _houseMarkerCollisionBounds(position);
          for (var index = 0; index < clusterAnchors.length; index += 1) {
            if (!candidateFootprint.overlaps(clusterFootprints[index])) {
              continue;
            }
            final delta = position - clusterAnchors[index];
            final distanceSquared = delta.dx * delta.dx + delta.dy * delta.dy;
            if (distanceSquared < nearestDistanceSquared) {
              nearestCluster = index;
              nearestDistanceSquared = distanceSquared;
            }
          }
          if (nearestCluster == -1) {
            houseClusters.add(<LodgingHouse>[house]);
            clusterAnchors.add(position);
            clusterFootprints.add(candidateFootprint);
          } else {
            houseClusters[nearestCluster].add(house);
          }
        }
        final markerWidgets = <Widget>[];
        final anchorIdByHouseId = <String, String>{
          for (final house in town.houses) house.id: house.id,
        };
        final anchorPositions = Map<String, Offset>.of(positions);
        for (final houses in houseClusters) {
          houses.sort((left, right) {
            final byPriority = housePriority(
              left,
            ).compareTo(housePriority(right));
            return byPriority != 0
                ? byPriority
                : left.sourceKey.compareTo(right.sourceKey);
          });
          final lead = houses.first;
          final position = positions[lead.id]!;
          for (final house in houses) {
            anchorIdByHouseId[house.id] = lead.id;
          }
          anchorPositions[lead.id] = position;
          final status = houseStatus(lead);
          final states = bdoMapSymbolStates(
            owned: status == _HouseMarkerStatus.owned,
            recommendedLodging: status == _HouseMarkerStatus.recommendedLodging,
            recommendedStorage: status == _HouseMarkerStatus.recommendedStorage,
            recommendedHouseUse:
                status == _HouseMarkerStatus.recommendedHouseUse,
            recommendedPrerequisite:
                status == _HouseMarkerStatus.recommendedPrerequisite,
            selected: lead.id == _selectedHouseId,
          );
          if (houses.length > 1) {
            markerWidgets.add(
              Positioned(
                key: ValueKey<String>(
                  'resource-map-house-map-cluster-${lead.id}',
                ),
                left: position.dx + _houseClusterMarkerOffset.dx,
                top: position.dy + _houseClusterMarkerOffset.dy,
                child: _revealSelectedHouse(
                  houseId: lead.id,
                  child: _ScreenshotImportPulse(
                    active: houses.any(
                      (house) => _screenshotImportedHouseIds.contains(house.id),
                    ),
                    revision: _screenshotHousePulseRevision,
                    child: _HouseClusterMarker(
                      count: houses.length,
                      label: 'Open ${lead.name}',
                      kind: _houseSymbolKind(
                        lead,
                        _nodeNetworkPreferences.currentHouseUsageTypeIds[lead
                            .id],
                      ),
                      states: states,
                      onTap: () => _selectHouse(lead),
                    ),
                  ),
                ),
              ),
            );
            continue;
          }
          for (final house in houses) {
            final housePosition = positions[house.id]!;
            markerWidgets.add(
              Positioned(
                key: ValueKey<String>('resource-map-house-marker-${house.id}'),
                left: housePosition.dx + _houseMapMarkerOffset.dx,
                top: housePosition.dy + _houseMapMarkerOffset.dy,
                child: _revealSelectedHouse(
                  houseId: house.id,
                  child: _ScreenshotImportPulse(
                    active: _screenshotImportedHouseIds.contains(house.id),
                    revision: _screenshotHousePulseRevision,
                    child: _HouseMapMarker(
                      house: house,
                      status: status,
                      selected: house.id == _selectedHouseId,
                      activeUsageTypeId: _nodeNetworkPreferences
                          .currentHouseUsageTypeIds[house.id],
                      onTap: () => _selectHouse(house),
                    ),
                  ),
                ),
              ),
            );
          }
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HousePrerequisitePainter(
                    town: town,
                    anchorIdByHouseId: anchorIdByHouseId,
                    anchorPositions: anchorPositions,
                    ownedHouseIds: owned,
                    recommendedNewHouseIds: recommendedNew,
                    selectedHouseId:
                        recommendedStorage.firstOrNull ?? _selectedHouseId,
                    visibleHouseIds: visibleHouseIds,
                  ),
                ),
              ),
            ),
            ...markerWidgets,
          ],
        );
      },
    );
  }

  Widget _buildLodgingTownBadgeOverlay(Size viewport) {
    final lodgingDataset = widget.lodgingDataset;
    final activePlan = _activeNetworkLodgingPlan;
    final housingContextVisible =
        _nodeNetworkPlannerOpen ||
        _housingDirectoryOpen ||
        _selectedHousingTown != null;
    if (lodgingDataset == null || viewport.isEmpty || !housingContextVisible) {
      return const SizedBox.shrink();
    }
    final townPlans =
        activePlan?.townPlansByNodeId ?? const <String, LodgingPlan>{};
    final badgeSpecs =
        <
          ({
            LodgingTown town,
            int ownedCount,
            int plannedCount,
            LodgingPlan? plan,
          })
        >[];
    for (final town in lodgingDataset.towns.where(
      (candidate) => candidate.isWorkerTown,
    )) {
      final ownedCount = _ownedHouseIdsForTown(town).length;
      final plan = townPlans[town.townNodeId];
      final plannedCount = plan?.newlyRequiredHouseIds.length ?? 0;
      if (ownedCount == 0 && plannedCount == 0) {
        continue;
      }
      badgeSpecs.add((
        town: town,
        ownedCount: ownedCount,
        plannedCount: plannedCount,
        plan: plan,
      ));
    }
    final specs = <_LodgingBadgeFlowSpec>[];
    final children = <Widget>[];
    for (final spec in badgeSpecs) {
      final town = spec.town;
      final childIndex = children.length;
      specs.add(_LodgingBadgeFlowSpec(town: town, childIndex: childIndex));
      final totalAfterPlan = spec.ownedCount + spec.plannedCount;
      children.add(
        KeyedSubtree(
          key: ValueKey<String>(
            'resource-map-lodging-town-badge-${town.townNodeId}',
          ),
          child: RepaintBoundary(
            child: _LodgingTownBadge(
              townName: town.name,
              count: totalAfterPlan,
              ownedCount: spec.ownedCount,
              plannedCount: spec.plannedCount,
              planned: spec.plan != null,
              onTap: spec.plan == null
                  ? () => _showHousingTown(town)
                  : () => _showLodgingTownPlan(spec.plan!),
            ),
          ),
        ),
      );
    }
    return Flow(
      delegate: _LodgingBadgeFlowDelegate(
        cameraController: _cameraController,
        specs: specs,
      ),
      children: children,
    );
  }

  bool get _plannedLodgingSummaryVisible {
    final town = _selectedHousingTown;
    return town != null &&
        _activeNetworkLodgingPlanForTown(town) != null &&
        _dismissedPlannedLodgingSummaryTownNodeId != town.townNodeId;
  }

  Widget _buildPlannedLodgingSummaryOverlay(Size viewport) {
    final town = _selectedHousingTown;
    if (town == null || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final plan = _activeNetworkLodgingPlanForTown(town);
    if (plan == null ||
        _dismissedPlannedLodgingSummaryTownNodeId == town.townNodeId) {
      return const SizedBox.shrink();
    }
    const width = 324.0;
    final maximumHeight = math
        .max(120.0, math.min(330.0, viewport.height - 96))
        .toDouble();
    final initialLeft = math.max(14.0, viewport.width - width - 88);
    final initialTop = math.min(
      _compactLayout ? 84.0 : _atlasPanelTop(context, viewport.width),
      math.max(12.0, viewport.height - 90),
    );
    return Stack(
      children: <Widget>[
        DraggablePositionedSurface(
          key: ValueKey<String>(
            'resource-map-planned-lodging-summary-drag-${town.townNodeId}',
          ),
          identity: 'planned-lodging:${town.townNodeId}',
          viewportSize: viewport,
          initialPosition: Offset(initialLeft, initialTop),
          estimatedSize: Size(width, maximumHeight),
          viewportPadding: const EdgeInsets.fromLTRB(12, 62, 12, 12),
          builder: (context, position, manuallyMoved) => Positioned(
            key: ValueKey<String>(
              'resource-map-planned-lodging-summary-${town.townNodeId}',
            ),
            left: position.dx,
            top: position.dy,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maximumHeight),
              child: _PlannedLodgingSummary(
                town: town,
                plan: plan,
                onSelectHouse: (house) => _selectHouse(house),
                onClose: () => setState(() {
                  _dismissedPlannedLodgingSummaryTownNodeId = town.townNodeId;
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedHouseOverlay(Size viewport) {
    final town = _selectedHousingTown;
    final selectedHouseId = _selectedHouseId;
    if (town == null || selectedHouseId == null || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final house = town.housesById[selectedHouseId];
    if (house == null) {
      return const SizedBox.shrink();
    }
    final popupWidth = math.min(304.0, viewport.width - 24).toDouble();
    final minimumLeft = _activeDesktopLeftAvoidanceWidth > 0
        ? math
              .min(
                _activeDesktopLeftAvoidanceWidth + 10,
                math.max(12, viewport.width - popupWidth - 12),
              )
              .toDouble()
        : 12.0;
    final owned = _nodeNetworkPreferences.currentOwnedHouseIds.contains(
      house.id,
    );
    widget.debugOnSelectedHouseSnapshotBuilt?.call();
    final plan = _displayedLodgingPlanForTown(town);
    final housePlannerOpen = _storagePlannerOpenForTown(town);
    final storagePlan = _storagePlanActiveForTown(town)
        ? _storagePlanForTown(town)
        : null;
    final lodgingPlan = _lodgingPlanActiveForTown(town)
        ? _lodgingPlanForTown(town)
        : null;
    final houseUsePlan = _houseUsePlanForTown(town);
    final recommendedStorage =
        storagePlan?.selectedStorageHouseIds.contains(house.id) ?? false;
    final recommendedHouseUse =
        houseUsePlan?.selectedUseHouseIds.contains(house.id) ?? false;
    final recommendedLodging = lodgingPlan != null
        ? lodgingPlan.selectedLodgingHouseIds.contains(house.id)
        : !housePlannerOpen && plan.selectedLodgingHouseIds.contains(house.id);
    final recommendedPrerequisite = storagePlan != null
        ? storagePlan.prerequisiteHouseIds.contains(house.id)
        : lodgingPlan != null
        ? lodgingPlan.prerequisiteHouseIds.contains(house.id) &&
              !recommendedLodging
        : houseUsePlan != null
        ? houseUsePlan.newPrerequisiteHouseIds.contains(house.id)
        : plan.prerequisiteHouseIds.contains(house.id) ||
              (plan.newlyRequiredHouseIds.contains(house.id) &&
                  !recommendedLodging);
    final retainedDetails = RepaintBoundary(
      child: SingleChildScrollView(
        child: _buildSelectedHouseDetails(
          town,
          house,
          owned: owned,
          recommendedLodging: recommendedLodging,
          recommendedStorage: recommendedStorage,
          recommendedHouseUse: recommendedHouseUse,
          recommendedPrerequisite: recommendedPrerequisite,
          onClose: () => setState(() => _selectedHouseId = null),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _cameraController,
      child: retainedDetails,
      builder: (context, child) {
        final anchor = _cameraController.worldToScreen(
          _houseMapPoint(house),
          viewport,
        );
        if (anchor.dx < -48 ||
            anchor.dy < -48 ||
            anchor.dx > viewport.width + 48 ||
            anchor.dy > viewport.height + 48) {
          return const SizedBox.shrink();
        }
        final fitsRight = anchor.dx + 30 + popupWidth <= viewport.width - 14;
        final requestedLeft = fitsRight
            ? anchor.dx + 24
            : anchor.dx - popupWidth - 24;
        final left = requestedLeft
            .clamp(
              minimumLeft,
              math.max(minimumLeft, viewport.width - popupWidth - 12),
            )
            .toDouble();
        final top = (anchor.dy - 54)
            .clamp(72.0, math.max(72.0, viewport.height - 360))
            .toDouble();
        return Stack(
          children: <Widget>[
            DraggablePositionedSurface(
              key: ValueKey<String>(
                'resource-map-house-flyout-drag-${house.id}',
              ),
              identity: '${town.townNodeId}:${house.id}',
              viewportSize: viewport,
              initialPosition: Offset(left, top),
              estimatedSize: Size(
                popupWidth,
                math.min(340, viewport.height - top - 12),
              ),
              viewportPadding: EdgeInsets.fromLTRB(minimumLeft, 72, 12, 12),
              builder: (context, position, manuallyMoved) => Positioned(
                key: ValueKey<String>('resource-map-house-flyout-${house.id}'),
                left: position.dx,
                top: position.dy,
                width: popupWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.min(
                      340,
                      viewport.height - position.dy - 12,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildManagerMarkerOverlay(Size viewport) {
    final marker = _markedManager;
    if (marker == null || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _cameraController,
        builder: (context, child) {
          final position = _cameraController.worldToScreen(
            marker.location.mapPoint,
            viewport,
          );
          final radius = ResourceMapManagerMarker.size / 2;
          if (position.dx < -radius ||
              position.dy < -radius ||
              position.dx > viewport.width + radius ||
              position.dy > viewport.height + radius) {
            return const SizedBox.shrink();
          }
          return Stack(
            children: <Widget>[
              Positioned(
                key: ValueKey<String>(
                  'resource-map-manager-marker-${marker.id}',
                ),
                left: position.dx - radius,
                top: position.dy - radius,
                child: ResourceMapManagerMarker(
                  managerName: marker.name,
                  contextLabel: marker.contextLabel,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVendorMarkerOverlay(Size viewport) {
    final vendors = _activeVendorNpcs;
    if (vendors.isEmpty || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _cameraController,
      builder: (context, child) {
        const markerSize = 56.0;
        const clusterDistance = 50.0;
        final clusters = <_VendorScreenCluster>[];
        for (final vendor in vendors) {
          final position = _cameraController.worldToScreen(
            vendor.location.mapPoint,
            viewport,
          );
          if (position.dx < -markerSize ||
              position.dy < -markerSize ||
              position.dx > viewport.width + markerSize ||
              position.dy > viewport.height + markerSize) {
            continue;
          }
          final nearby = clusters.cast<_VendorScreenCluster?>().firstWhere(
            (cluster) =>
                cluster != null &&
                (cluster.center - position).distance <= clusterDistance,
            orElse: () => null,
          );
          if (nearby == null) {
            clusters.add(_VendorScreenCluster(vendor, position));
          } else {
            nearby.add(vendor, position);
          }
        }
        final markers = <Widget>[];
        for (final cluster in clusters) {
          final position = cluster.center;
          if (cluster.vendors.length == 1) {
            final vendor = cluster.vendors.single;
            markers.add(
              Positioned(
                key: ValueKey<String>(
                  'resource-map-vendor-marker-${vendor.id}',
                ),
                left: position.dx - markerSize / 2,
                top: position.dy - markerSize,
                child: _VendorMapMarker(
                  vendor: vendor,
                  portrait: widget.vendorPortraitBuilder?.call(
                    context,
                    vendor,
                    44,
                  ),
                  selected: vendor.id == _selectedVendorId,
                  onPressed: () => _showVendorDetails(vendor.id),
                ),
              ),
            );
            continue;
          }
          final clusterVendors = List<BdoVendorNpc>.unmodifiable(
            cluster.vendors,
          );
          markers.add(
            Positioned(
              key: ValueKey<String>(
                'resource-map-vendor-cluster-${clusterVendors.first.id}',
              ),
              left: position.dx - markerSize / 2,
              top: position.dy - markerSize,
              child: _VendorClusterMarker(
                count: clusterVendors.length,
                onPressed: () => _openVendorClusterPicker(clusterVendors),
              ),
            ),
          );
        }
        return Stack(children: markers);
      },
    );
  }

  Widget _buildVendorClusterPickerOverlay(Size viewport) {
    final vendors = _vendorClusterPickerVendors;
    final anchorPoint = _vendorClusterPickerAnchor;
    final itemName = _vendorLookupItemName;
    if (vendors.length < 2 ||
        anchorPoint == null ||
        itemName == null ||
        viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final entries = vendors
        .map(
          (vendor) => _VendorPickerEntry(
            vendor: vendor,
            priceSilver: _activeListingForVendor(vendor.id)?.priceSilver,
          ),
        )
        .toList(growable: false);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final popupTopInset =
        _atlasPanelTop(context, viewport.width) +
        ResourceMapPanelMetrics.searchHeight(context) +
        12;
    final popupWidth = math
        .min(350 * textScale, math.max(1.0, viewport.width - 24))
        .toDouble();
    final popupMaxHeight = math
        .min(
          350 * textScale,
          math.max(1.0, viewport.height - popupTopInset - 12),
        )
        .toDouble();
    return AnimatedBuilder(
      animation: _cameraController,
      builder: (context, child) {
        final anchor = _cameraController.worldToScreen(anchorPoint, viewport);
        if (anchor.dx < -72 ||
            anchor.dy < -72 ||
            anchor.dx > viewport.width + 72 ||
            anchor.dy > viewport.height + 72) {
          return const SizedBox.shrink();
        }
        final availableRight = viewport.width - anchor.dx;
        final requestedLeft = availableRight >= popupWidth + 28
            ? anchor.dx + 22
            : anchor.dx - popupWidth - 22;
        final left = requestedLeft
            .clamp(12.0, math.max(12.0, viewport.width - popupWidth - 12))
            .toDouble();
        final top = (anchor.dy - 72)
            .clamp(
              popupTopInset,
              math.max(popupTopInset, viewport.height - popupMaxHeight - 12),
            )
            .toDouble();
        return Stack(
          children: <Widget>[
            Positioned(
              key: const ValueKey<String>('resource-map-vendor-cluster-picker'),
              left: left,
              top: top,
              width: popupWidth,
              child: child!,
            ),
          ],
        );
      },
      child: _VendorClusterPickerCard(
        itemName: itemName,
        itemIcon: _buildVendorItemIcon(
          context,
          itemName,
          ResourceMapPanelMetrics.artwork,
        ),
        entries: entries,
        portraitBuilder: widget.vendorPortraitBuilder,
        maximumHeight: popupMaxHeight,
        onClose: _closeVendorClusterPicker,
        onSelected: _showVendorDetails,
      ),
    );
  }

  Widget _buildSelectedVendorOverlay(Size viewport) {
    final vendor = _selectedVendor;
    final itemName = _vendorLookupItemName;
    if (vendor == null || itemName == null || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final listing = _activeListingForVendor(vendor.id);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final popupTopInset =
        _atlasPanelTop(context, viewport.width) +
        ResourceMapPanelMetrics.searchHeight(context) +
        12;
    final popupWidth = math
        .min(330 * textScale, math.max(1.0, viewport.width - 24))
        .toDouble();
    final popupMaxHeight = math
        .min(
          310 * textScale,
          math.max(1.0, viewport.height - popupTopInset - 12),
        )
        .toDouble();
    return AnimatedBuilder(
      animation: _cameraController,
      builder: (context, child) {
        final anchor = _cameraController.worldToScreen(
          vendor.location.mapPoint,
          viewport,
        );
        if (anchor.dx < -72 ||
            anchor.dy < -72 ||
            anchor.dx > viewport.width + 72 ||
            anchor.dy > viewport.height + 72) {
          return const SizedBox.shrink();
        }
        final availableRight = viewport.width - anchor.dx;
        final requestedLeft = availableRight >= popupWidth + 28
            ? anchor.dx + 22
            : anchor.dx - popupWidth - 22;
        final left = requestedLeft
            .clamp(12.0, math.max(12.0, viewport.width - popupWidth - 12))
            .toDouble();
        final top = (anchor.dy - 68)
            .clamp(
              popupTopInset,
              math.max(popupTopInset, viewport.height - popupMaxHeight - 12),
            )
            .toDouble();
        return Stack(
          children: <Widget>[
            Positioned(
              key: ValueKey<String>('resource-map-vendor-details-${vendor.id}'),
              left: left,
              top: top,
              width: popupWidth,
              child: child!,
            ),
          ],
        );
      },
      child: _VendorNpcMapCard(
        vendor: vendor,
        itemName: itemName,
        itemIcon: _buildVendorItemIcon(
          context,
          itemName,
          ResourceMapPanelMetrics.artwork,
        ),
        portraitBuilder: widget.vendorPortraitBuilder,
        priceSilver: listing?.priceSilver,
        maximumHeight: popupMaxHeight,
        onClose: () => setState(() => _selectedVendorId = null),
      ),
    );
  }

  Widget _buildVendorLookupBanner(BuildContext context) {
    final itemName = _vendorLookupItemName!;
    final vendorCount = _activeVendorNpcs.length;
    final chrome = context.mapChrome;
    return Material(
      key: const ValueKey<String>('resource-map-vendor-lookup-banner'),
      elevation: 12,
      shadowColor: const Color(0x5A17100F),
      color: chrome.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: chrome.primary.withAlpha(170)),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: chrome.subtleSurfaceGradient),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 7, 10, 7),
          child: Row(
            children: <Widget>[
              MapQuietIconButton(
                key: const ValueKey<String>('resource-map-vendor-lookup-back'),
                tooltip: 'Back to the previous map view',
                visualDensity: VisualDensity.compact,
                onPressed: _navigationHistory.isEmpty
                    ? _openMapHome
                    : _navigateBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chrome.primary.withAlpha(34),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: chrome.primary.withAlpha(122)),
                ),
                child: _buildVendorItemIcon(context, itemName, 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chrome.headingStyle(
                        fontSize: ResourceMapPanelMetrics.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '$vendorCount mapped NPC '
                      '${vendorCount == 1 ? 'location' : 'locations'} '
                      '· click a pin for details',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: chrome.muted,
                        fontSize: ResourceMapPanelMetrics.secondary,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVendorItemIcon(
    BuildContext context,
    String itemName,
    double size,
  ) {
    return widget.vendorItemIconBuilder?.call(context, itemName, size) ??
        Icon(
          Icons.inventory_2_outlined,
          color: context.mapChrome.primary,
          size: size,
        );
  }

  // Desktop details live in the shared journey surface.
  // ignore: unused_element
  Widget _buildSelectedNodeQuickOverlay(Size viewport) {
    final selectedNodeId = _selectedNodeId;
    if (_desktopNetworkWorkbenchVisible ||
        !_nodeQuickPanelOpen ||
        selectedNodeId == null ||
        _selectedHouseId != null ||
        viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final node = widget.dataset.workerNodesById[selectedNodeId];
    if (node == null) {
      return const SizedBox.shrink();
    }
    final availableWorkerNodes = node.isResourceNode
        ? <BdoWorkerNode>[]
        : widget.dataset.workerNodes
              .where(
                (candidate) =>
                    candidate.isResourceNode && candidate.parentId == node.id,
              )
              .toList(growable: true);
    availableWorkerNodes.sort((left, right) {
      final byCp = left.contributionPoints.compareTo(right.contributionPoints);
      if (byCp != 0) return byCp;
      final byName = left.name.compareTo(right.name);
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
    final parent = node.parentId == null
        ? null
        : widget.dataset.workerNodesById[node.parentId!];
    final unlockGuide = bdoExcavationUnlockGuideFor(node);
    final unlockMarkerId = unlockGuide == null
        ? null
        : 'excavation:${unlockGuide.managerGameNpcId}';
    final housingTownNodeId =
        widget.lodgingDataset?.townsByNodeId.containsKey(node.id) == true
        ? node.id
        : node.id == '1852' &&
              widget.lodgingDataset?.townsByNodeId.containsKey('1853') == true
        ? '1853'
        : null;
    final townActions = housingTownNodeId == null
        ? null
        : ResourceMapTownQuickActions(
            onOpenHouses: () => _openHousingTown(housingTownNodeId),
          );
    return AnimatedBuilder(
      animation: _cameraController,
      builder: (context, child) {
        final anchor = _cameraController.worldToScreen(
          node.location.mapPoint,
          viewport,
        );
        final anchorVisible =
            anchor.dx >= -48 &&
            anchor.dy >= -48 &&
            anchor.dx <= viewport.width + 48 &&
            anchor.dy <= viewport.height + 48;
        final popupWidth = math
            .min(ResourceMapNodeQuickPanel.maxWidth, viewport.width - 24)
            .toDouble();
        final minimumLeft = _activeDesktopLeftAvoidanceWidth > 0
            ? math
                  .min(
                    _activeDesktopLeftAvoidanceWidth + 10,
                    math.max(12, viewport.width - popupWidth - 12),
                  )
                  .toDouble()
            : 12.0;
        final fitsRight =
            anchorVisible && anchor.dx + 28 + popupWidth <= viewport.width - 14;
        final requestedLeft = !anchorVisible
            // Keep a fixed comparison panel clear of the zoom/layer dock.
            ? viewport.width - popupWidth - 76
            : fitsRight
            ? anchor.dx + 22
            : anchor.dx - popupWidth - 22;
        final left = requestedLeft
            .clamp(
              minimumLeft,
              math.max(minimumLeft, viewport.width - popupWidth - 12),
            )
            .toDouble();
        final quickPath = _selectedQuickNodePath?.targetNodeId == node.id
            ? _selectedQuickNodePath
            : null;
        final outputs = <ResourceMapNodeOutput>[
          for (final output in node.outputs)
            ResourceMapNodeOutput(
              id: output.resourceId,
              name: output.name,
              icon: _buildWorkerOutputArtwork(
                context,
                widget.dataset.resourcesById[output.resourceId],
                size: 26,
              ),
              onPressed: widget.dataset.resourcesById[output.resourceId] == null
                  ? null
                  : () => _selectResourceFromDetails(
                      widget.dataset.resourcesById[output.resourceId]!,
                    ),
            ),
        ];
        final workerNodeLinks = <ResourceMapNodeLink>[
          for (final childNode in availableWorkerNodes)
            ResourceMapNodeLink(
              id: childNode.id,
              title: childNode.name,
              subtitle: <String>[
                '${childNode.contributionPoints} CP',
                if (childNode.outputs.isNotEmpty)
                  childNode.outputs.map((output) => output.name).join(', ')
                else
                  'No recorded output',
              ].join(' · '),
              icon: _buildWorkerNodeArtwork(childNode, size: 26),
              onPressed: () => _selectNode(childNode),
            ),
        ];
        final connectedFrom = parent == null
            ? null
            : ResourceMapNodeLink(
                id: parent.id,
                title: parent.siteName,
                subtitle: parent.region,
                icon: _buildWorkerNodeArtwork(parent, size: 26),
                onPressed: () => _selectNode(parent),
              );
        final estimatedHeight =
            (197.0 +
                    (outputs.isEmpty ? 0 : 18 + outputs.length * 35) +
                    (workerNodeLinks.isEmpty
                        ? 0
                        : 30 + workerNodeLinks.length * 54) +
                    (connectedFrom == null ? 0 : 108) +
                    (quickPath == null ? 0 : 42) +
                    (unlockGuide == null ? 0 : 132) +
                    (townActions == null
                        ? 0
                        : 48 *
                              <VoidCallback?>[
                                townActions.onOpenRoyalWorkshops,
                                townActions.onOpenWorkersAndStorage,
                                townActions.onOpenHouses,
                              ].whereType<VoidCallback>().length))
                .clamp(197.0, 480.0);
        final maximumTop = math.max(
          66.0,
          viewport.height - estimatedHeight - 12,
        );
        final requestedTop = anchorVisible
            ? anchor.dy - estimatedHeight / 2
            : (viewport.height - estimatedHeight) / 2;
        final top = requestedTop.clamp(66.0, maximumTop).toDouble();
        final panelMaxHeight = math.max(
          1.0,
          math.min(480.0, viewport.height - top - 12),
        );
        final visibleEstimatedHeight = math.min(
          estimatedHeight,
          panelMaxHeight,
        );
        final sideTailOffset = anchorVisible
            ? (anchor.dy - top)
                  .clamp(22.0, math.max(22.0, visibleEstimatedHeight - 22))
                  .toDouble()
            : null;
        final tailAlignment = !anchorVisible
            ? ResourceMapNodeQuickPanelTailAlignment.none
            : fitsRight
            ? ResourceMapNodeQuickPanelTailAlignment.leftCenter
            : ResourceMapNodeQuickPanelTailAlignment.rightCenter;
        return Stack(
          children: <Widget>[
            DraggablePositionedSurface(
              key: ValueKey<String>(
                'resource-map-node-quick-flyout-drag-${node.id}',
              ),
              identity: node.id,
              viewportSize: viewport,
              initialPosition: Offset(left, top),
              estimatedSize: Size(popupWidth, visibleEstimatedHeight),
              viewportPadding: EdgeInsets.fromLTRB(minimumLeft, 66, 12, 12),
              builder: (context, position, manuallyMoved) => Positioned(
                key: ValueKey<String>(
                  'resource-map-node-quick-flyout-${node.id}',
                ),
                left: position.dx,
                top: position.dy,
                width: popupWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      1,
                      math.min(480, viewport.height - position.dy - 12),
                    ),
                  ),
                  child: RepaintBoundary(
                    key: const ValueKey<String>(
                      'resource-map-node-quick-boundary',
                    ),
                    child: ResourceMapNodeQuickPanel(
                      nodeName: node.siteName,
                      nodeType: node.isResourceNode
                          ? node.activity.label
                          : node.nodeType,
                      contributionPoints: node.contributionPoints,
                      region: node.region,
                      workloadLabel: node.workload,
                      workerSiteCount: availableWorkerNodes.length,
                      outputs: outputs,
                      availableWorkerNodes: workerNodeLinks,
                      connectedFrom: connectedFrom,
                      workerPathVisible: _showConnections,
                      onToggleWorkerPath: connectedFrom == null
                          ? null
                          : () {
                              setState(() {
                                _showConnections = !_showConnections;
                                if (_showConnections) {
                                  _showWorkerNodes = true;
                                }
                              });
                            },
                      provenance: null,
                      unlockNotice: unlockGuide == null
                          ? null
                          : ResourceMapNodeUnlockNotice(
                              managerName: unlockGuide.managerName,
                              instructions: unlockGuide.unlockInstructions,
                              managerMarkerVisible:
                                  _markedManager?.id == unlockMarkerId,
                              onToggleManagerMarker:
                                  unlockGuide.managerLocation == null
                                  ? null
                                  : () => _toggleManagerMarker(
                                      id: unlockMarkerId!,
                                      name: unlockGuide.managerName,
                                      location: unlockGuide.managerLocation!,
                                      contextLabel:
                                          'excavation node manager location',
                                    ),
                            ),
                      townActions: townActions,
                      onBack: _navigationHistory.isEmpty ? null : _navigateBack,
                      backLabel: _navigationHistory.isEmpty
                          ? null
                          : _backNavigationLabel,
                      invested: _nodeNetworkPreferences.currentNodeIds.contains(
                        node.id,
                      ),
                      onToggleInvested: null,
                      onAddCompleteRoute:
                          quickPath != null &&
                              quickPath.connectNodeIds.isNotEmpty
                          ? _addSelectedQuickNodeRoute
                          : null,
                      completeRouteContributionPoints:
                          quickPath?.incrementalContributionPoints,
                      onClose: _dismissDetails,
                      tailAlignment: manuallyMoved
                          ? ResourceMapNodeQuickPanelTailAlignment.none
                          : tailAlignment,
                      sideTailOffset: manuallyMoved ? null : sideTailOffset,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAllNodeOverlay(Size viewport) {
    if ((!_showAllNodes && !_investNodeMode && !_editingCurrentNodeNetwork) ||
        viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final interactiveNodeIds = _visibleWorkerNodes
        .map((node) => node.id)
        .toSet();
    final editCurrentNetwork =
        _nodeNetworkPlannerOpen &&
        _nodeNetworkPlannerPage == _NodeNetworkPlannerPage.editCurrent;
    return _SettledCameraSnapshotOverlay(
      cameraController: _cameraController,
      viewport: viewport,
      builder: (context, geometry) {
        final snapshotViewport = geometry.snapshotSize;
        final zoom = _cameraController.camera.zoom;
        final nodes = widget.dataset.workerNodes
            .where(
              (node) =>
                  _showsAsNeutralOrientationNode(node) &&
                  !interactiveNodeIds.contains(node.id) &&
                  _visibleLandmarkKind(node, zoom) == null,
            )
            .toList(growable: false);
        final initialPlacements = _resolveAllNodePlacements(
          cameraController: _cameraController,
          viewport: snapshotViewport,
          nodes: nodes,
          zoom: zoom,
          visibleViewport: geometry.visibleViewport,
          labelBudgetScale: geometry.areaScale,
          retainAllNodes: _investNodeMode,
        );
        return IgnorePointer(
          ignoring: _gatheringLayerOwnsMapTaps,
          child: Stack(
            children: <Widget>[
              for (final placement in initialPlacements)
                Positioned(
                  key: ValueKey<String>(
                    'resource-map-orientation-node-${placement.node.id}',
                  ),
                  left: placement.position.dx - 12,
                  top: placement.position.dy - 20,
                  child: RepaintBoundary(
                    child: _MapOrientationNodeMarker(
                      node: placement.node,
                      label: placement.node.siteName,
                      showLabel: placement.showLabel,
                      active: _nodeIconIsActive(placement.node),
                      largeHitTarget: editCurrentNetwork || _investNodeMode,
                      semanticLabel: _investNodeMode
                          ? '${_nodeNetworkPreferences.currentNodeIds.contains(placement.node.id) ? 'Remove' : 'Save'} '
                                '${placement.node.siteName} as an invested node'
                          : editCurrentNetwork
                          ? placement.node.isProductionNode
                                ? 'Add ${placement.node.siteName} and its complete '
                                      'route, ${placement.node.contributionPoints} CP '
                                      'at the production node'
                                : '${_currentNodeDraftIds.contains(placement.node.id) ? 'Unmark' : 'Mark'} '
                                      '${placement.node.siteName} as an in-game node, '
                                      '${placement.node.contributionPoints} CP'
                          : null,
                      onTap: () => _handleWorkerNodeTap(placement.node),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  _MapLandmarkKind? _visibleLandmarkKind(BdoWorkerNode node, double zoom) {
    return switch (node.nodeType) {
      'City' when _showKnownTowns => _MapLandmarkKind.city,
      'Town'
          when _showKnownTowns &&
              zoom >= _townMarkerMinimumZoom &&
              node.siteName != 'Port Ratt' =>
        _MapLandmarkKind.town,
      'Gateway' when _showNodeHubs && zoom >= _nodeHubMarkerMinimumZoom =>
        _MapLandmarkKind.gateway,
      _ => null,
    };
  }

  Widget _buildWorkerOutputArtworkOverlay(Size viewport) {
    if (!_showWorkerOutputArtwork || viewport.isEmpty) {
      return const SizedBox.shrink();
    }
    final plannedOutputNodeIds = _plannedWorkerOutputNodeIds;
    final focusPlannedOutputs = plannedOutputNodeIds.isNotEmpty;
    final visibleWorkerNodes = _visibleWorkerNodes;
    final focusVisibleOutputs = visibleWorkerNodes.any(
      (node) => node.isResourceNode,
    );
    final workerNodesById = <String, BdoWorkerNode>{
      for (final node in visibleWorkerNodes)
        if (node.isResourceNode &&
            (!focusPlannedOutputs || plannedOutputNodeIds.contains(node.id)))
          node.id: node,
      if (_showAllNodes &&
          _nodeNetworkPreferences.showWorkerOutputIcons &&
          !focusVisibleOutputs)
        for (final node in widget.dataset.workerNodes)
          if (node.isResourceNode &&
              (!focusPlannedOutputs || plannedOutputNodeIds.contains(node.id)))
            node.id: node,
    };
    final workerNodes = workerNodesById.values.toList(growable: false);
    if (workerNodes.isEmpty) {
      return const SizedBox.shrink();
    }
    final markerCache = <String, Widget>{};
    return _SettledCameraSnapshotOverlay(
      cameraController: _cameraController,
      viewport: viewport,
      builder: (context, geometry) {
        final snapshotViewport = geometry.snapshotSize;
        final visibleViewport = geometry.visibleViewport;
        final zoom = _cameraController.camera.zoom;
        if (zoom < _workerOutputArtworkMinimumZoom) {
          return const SizedBox.shrink();
        }
        final layout = BdoMapOverlayLayout(
          cameraController: _cameraController,
          viewport: snapshotViewport,
          workerNodes: workerNodes,
          workerNodesById: widget.dataset.workerNodesById,
          gatheringSpots: _visibleGatheringSpots,
          gatheringPoints: _visibleGatheringPoints,
          gatheringRoutes: _visibleGatheringRoutes,
          selectedNodeId: _selectedNodeId,
        );
        final center = snapshotViewport.center(Offset.zero);
        final revealProgress = Curves.easeOutCubic.transform(
          ((zoom - _workerOutputArtworkMinimumZoom) / 4.3)
              .clamp(0.0, 1.0)
              .toDouble(),
        );
        final artworkSize = 12 + 14 * revealProgress;
        final artworkOpacity = 0.52 + 0.48 * revealProgress;
        final visibleCandidateBudget = focusPlannedOutputs
            ? switch (zoom) {
                < 4 => 10,
                < 5 => 18,
                _ => 26,
              }
            : (12 + (_maximumWorkerOutputArtwork - 12) * revealProgress)
                  .round();
        final candidateBudget = math.max(
          visibleCandidateBudget,
          (visibleCandidateBudget * geometry.areaScale).ceil(),
        );
        final visibleOutputLimit = zoom < 3.75 ? 1 : 2;
        final showBadge = zoom >= 4.35;
        final candidates =
            <
              ({
                String key,
                List<BdoWorkerNode> nodes,
                List<_WorkerOutputArtwork> outputs,
                int additionalOutputs,
                Offset position,
              })
            >[];
        for (
          var clusterIndex = 0;
          clusterIndex < layout.nodeClusters.length;
          clusterIndex += 1
        ) {
          final cluster = layout.nodeClusters[clusterIndex];
          final nodes = cluster.nodes
              .where((node) => node.isResourceNode && node.outputs.isNotEmpty)
              .toList(growable: false);
          if (nodes.isEmpty) {
            continue;
          }
          final outputsById = <String, BdoNodeOutput>{};
          for (final node in nodes) {
            final orderedOutputs = <BdoNodeOutput>[
              ...node.outputs.where((output) => output.isPrimary),
              ...node.outputs.where((output) => !output.isPrimary),
            ];
            for (final output in orderedOutputs) {
              outputsById.putIfAbsent(output.resourceId, () => output);
            }
          }
          final outputs = outputsById.values
              .map(
                (output) => _WorkerOutputArtwork(
                  name: output.name,
                  resource: widget.dataset.resourcesById[output.resourceId],
                ),
              )
              .take(visibleOutputLimit)
              .toList(growable: false);
          if (outputs.isEmpty ||
              cluster.position.dx < -48 ||
              cluster.position.dy < -40 ||
              cluster.position.dx > snapshotViewport.width + 16 ||
              cluster.position.dy > snapshotViewport.height + 40) {
            continue;
          }
          candidates.add((
            key: nodes.length == 1
                ? nodes.single.id
                : 'cluster-$clusterIndex-${nodes.first.id}',
            nodes: nodes,
            outputs: outputs,
            additionalOutputs: math.max(0, outputsById.length - outputs.length),
            position: cluster.position,
          ));
        }
        candidates.sort((left, right) {
          final selectedOrder =
              (right.nodes.any((node) => node.id == _selectedNodeId) ? 1 : 0) -
              (left.nodes.any((node) => node.id == _selectedNodeId) ? 1 : 0);
          if (selectedOrder != 0) {
            return selectedOrder;
          }
          final byDistance = (left.position - center).distanceSquared.compareTo(
            (right.position - center).distanceSquared,
          );
          return byDistance != 0 ? byDistance : left.key.compareTo(right.key);
        });
        final markerObstacles = layout.nodeClusters
            .map(
              (cluster) => Rect.fromCircle(
                center: cluster.position,
                radius: cluster.nodes.length == 1 ? 16 : 19,
              ),
            )
            .toList(growable: false);
        final occupiedArtwork = <Rect>[
          Rect.fromLTWH(
            math.max(visibleViewport.left, visibleViewport.right - 210),
            visibleViewport.top,
            math.min(210, visibleViewport.width),
            math.min(278, visibleViewport.height),
          ),
        ];
        final selectedNode = _selectedNodeId == null
            ? null
            : workerNodesById[_selectedNodeId!];
        if (selectedNode != null) {
          final selectedCluster = layout.nodeClusters
              .where(
                (cluster) =>
                    cluster.nodes.any((node) => node.id == selectedNode.id),
              )
              .firstOrNull;
          if (selectedCluster != null) {
            final primaryName = selectedNode.outputs
                .where((output) => output.isPrimary)
                .map((output) => output.name)
                .firstOrNull;
            final label = primaryName == null
                ? selectedNode.siteName
                : '$primaryName \u00B7 ${selectedNode.siteName}';
            occupiedArtwork.add(
              Rect.fromCenter(
                center: selectedCluster.position + const Offset(0, 31),
                width: math.min(220, 24 + label.length * 6).toDouble(),
                height: 24,
              ),
            );
          }
        }
        final placements =
            <
              ({
                ({
                  String key,
                  List<BdoWorkerNode> nodes,
                  List<_WorkerOutputArtwork> outputs,
                  int additionalOutputs,
                  Offset position,
                })
                candidate,
                Rect rect,
              })
            >[];
        for (final candidate in candidates.take(candidateBudget)) {
          final markerSize = _workerOutputMarkerSize(
            visibleOutputCount: candidate.outputs.length,
            additionalOutputs: candidate.additionalOutputs,
            artworkSize: artworkSize,
            showBadge: showBadge,
          );
          final visibleCandidateBounds = Rect.fromLTRB(
            visibleViewport.left - 48,
            visibleViewport.top - 40,
            visibleViewport.right + 16,
            visibleViewport.bottom + 40,
          );
          final placementBounds =
              visibleCandidateBounds.contains(candidate.position)
              ? visibleViewport
              : (Offset.zero & snapshotViewport);
          Rect? chosen;
          for (final option in _workerOutputPlacementOptions(
            anchor: candidate.position,
            markerSize: markerSize,
            placementBounds: placementBounds,
          )) {
            final touchesNode = markerObstacles.any(
              (obstacle) => obstacle.inflate(2).overlaps(option),
            );
            final touchesArtwork = occupiedArtwork.any(
              (occupied) => occupied.inflate(4).overlaps(option),
            );
            if (!touchesNode && !touchesArtwork) {
              chosen = option;
              break;
            }
          }
          if (chosen == null) {
            continue;
          }
          occupiedArtwork.add(chosen);
          placements.add((candidate: candidate, rect: chosen));
        }
        if (markerCache.length > 128) {
          markerCache.clear();
        }
        return IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              children: <Widget>[
                for (final placement in placements)
                  Positioned(
                    key: ValueKey<String>(
                      'resource-map-worker-output-${placement.candidate.key}',
                    ),
                    left: placement.rect.left,
                    top: placement.rect.top,
                    child: markerCache.putIfAbsent(
                      <String>[
                        placement.candidate.key,
                        artworkSize.toStringAsFixed(2),
                        artworkOpacity.toStringAsFixed(2),
                        '${placement.candidate.additionalOutputs}',
                        if (showBadge) 'badge',
                        for (final output in placement.candidate.outputs)
                          output.name,
                      ].join('|'),
                      () => RepaintBoundary(
                        child: _buildWorkerOutputMarker(
                          context,
                          outputs: placement.candidate.outputs,
                          additionalOutputs:
                              placement.candidate.additionalOutputs,
                          artworkSize: artworkSize,
                          opacity: artworkOpacity,
                          showBadge: showBadge,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Size _workerOutputMarkerSize({
    required int visibleOutputCount,
    required int additionalOutputs,
    required double artworkSize,
    required bool showBadge,
  }) {
    final tileExtent = artworkSize + 3;
    final artworkWidth =
        visibleOutputCount * tileExtent +
        math.max(0, visibleOutputCount - 1) * 2;
    final badgeWidth = showBadge && additionalOutputs > 0
        ? math.max(18.0, 10 + '+$additionalOutputs'.length * 4.5)
        : 0.0;
    return Size(
      artworkWidth + (badgeWidth > 0 ? badgeWidth + 4 : 0),
      math.max(tileExtent, badgeWidth > 0 ? 15 : 0),
    );
  }

  List<Rect> _workerOutputPlacementOptions({
    required Offset anchor,
    required Size markerSize,
    required Rect placementBounds,
  }) {
    const markerGap = 20.0;
    const viewportMargin = 6.0;
    final viewportBounds = placementBounds.deflate(viewportMargin);
    final inwardIsRight = anchor.dx < placementBounds.center.dx;
    final horizontalDirection = inwardIsRight ? 1.0 : -1.0;
    final inwardX = horizontalDirection > 0
        ? anchor.dx + markerGap
        : anchor.dx - markerGap - markerSize.width;
    final outwardX = horizontalDirection > 0
        ? anchor.dx - markerGap - markerSize.width
        : anchor.dx + markerGap;
    final centeredX = anchor.dx - markerSize.width / 2;
    final centeredY = anchor.dy - markerSize.height / 2;
    final rawOptions = <Rect>[
      Rect.fromLTWH(
        centeredX,
        anchor.dy - markerGap - markerSize.height,
        markerSize.width,
        markerSize.height,
      ),
      Rect.fromLTWH(
        inwardX,
        anchor.dy - markerGap - markerSize.height / 2,
        markerSize.width,
        markerSize.height,
      ),
      Rect.fromLTWH(inwardX, centeredY, markerSize.width, markerSize.height),
      Rect.fromLTWH(
        inwardX,
        anchor.dy + markerGap - markerSize.height / 2,
        markerSize.width,
        markerSize.height,
      ),
      Rect.fromLTWH(
        centeredX,
        anchor.dy + markerGap,
        markerSize.width,
        markerSize.height,
      ),
      Rect.fromLTWH(
        outwardX,
        anchor.dy + markerGap - markerSize.height / 2,
        markerSize.width,
        markerSize.height,
      ),
      Rect.fromLTWH(outwardX, centeredY, markerSize.width, markerSize.height),
      Rect.fromLTWH(
        outwardX,
        anchor.dy - markerGap - markerSize.height / 2,
        markerSize.width,
        markerSize.height,
      ),
    ];
    return rawOptions
        .where(
          (rect) =>
              rect.left >= viewportBounds.left &&
              rect.top >= viewportBounds.top &&
              rect.right <= viewportBounds.right &&
              rect.bottom <= viewportBounds.bottom,
        )
        .toList(growable: false);
  }

  Widget _buildWorkerOutputMarker(
    BuildContext context, {
    required List<_WorkerOutputArtwork> outputs,
    required int additionalOutputs,
    required double artworkSize,
    required double opacity,
    required bool showBadge,
  }) {
    final markerSize = _workerOutputMarkerSize(
      visibleOutputCount: outputs.length,
      additionalOutputs: additionalOutputs,
      artworkSize: artworkSize,
      showBadge: showBadge,
    );
    final tileExtent = artworkSize + 3;
    final artworkWidth =
        outputs.length * tileExtent + math.max(0, outputs.length - 1) * 2;
    return SizedBox(
      width: markerSize.width,
      height: markerSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (var index = 0; index < outputs.length; index += 1)
            Positioned(
              left: index * (tileExtent + 2),
              top: 0,
              child: Opacity(
                opacity: opacity,
                child: SizedBox.square(
                  dimension: tileExtent,
                  child: Center(
                    child: Tooltip(
                      message: outputs[index].resource == null
                          ? '${outputs[index].name} artwork unavailable'
                          : outputs[index].name,
                      child: _buildWorkerOutputArtwork(
                        context,
                        outputs[index].resource,
                        size: artworkSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (showBadge && additionalOutputs > 0)
            Positioned(
              left: artworkWidth + 4,
              top: math.max(0, (markerSize.height - 15) / 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: context.mapChrome.graphiteRaised,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: context.mapChrome.brassLine),
                ),
                child: Text(
                  '+$additionalOutputs',
                  style: TextStyle(
                    color: context.mapChrome.accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildPanelOpacityControl(BuildContext context) {
    final onChanged = widget.onUiOpacityChanged;
    if (onChanged == null) return null;
    final liveOpacity = widget.uiOpacityListenable;
    if (liveOpacity != null) {
      return ValueListenableBuilder<double>(
        valueListenable: liveOpacity,
        builder: (context, value, _) =>
            _buildOpacitySlider(context, value, onChanged),
      );
    }
    return _buildOpacitySlider(context, widget.uiOpacity, onChanged);
  }

  Widget _buildOpacitySlider(
    BuildContext context,
    double opacity,
    ValueChanged<double> onChanged,
  ) {
    final chrome = context.mapChrome;
    final value = ResourceMapUiOpacity.normalize(opacity);
    final label = Tooltip(
      message: 'Panel backgrounds only. Text and item artwork stay clear.',
      child: Text(
        'Opacity',
        style: TextStyle(
          color: chrome.ink,
          fontSize: ResourceMapPanelMetrics.secondary,
        ),
      ),
    );
    final percentage = Text(
      '${(value * 100).round()}%',
      style: TextStyle(
        color: chrome.muted,
        fontSize: ResourceMapPanelMetrics.secondary,
      ),
    );
    final slider = SizedBox(
      height: 24,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        ),
        child: Slider(
          key: const ValueKey('resource-map-ui-opacity-slider'),
          value: value,
          min: ResourceMapUiOpacity.minimum,
          max: 1,
          label: '${(value * 100).round()}%',
          semanticFormatterCallback: (value) =>
              '${(value * 100).round()} percent panel opacity',
          onChanged: onChanged,
          onChangeEnd: widget.onUiOpacityChangeEnd,
        ),
      ),
    );
    return Material(
      key: const ValueKey('resource-map-ui-opacity-control'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: chrome.readingSurfaceGradient,
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              if (constraints.maxWidth < 160 * textScale) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 4,
                      children: [label, percentage],
                    ),
                    slider,
                  ],
                );
              }
              return Row(
                children: [
                  label,
                  Expanded(child: slider),
                  percentage,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMapLayerControls(
    BuildContext context, {
    required double maximumMenuWidth,
    double? maximumMenuHeight,
  }) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final menuSurface = Material(
      key: const ValueKey<String>('resource-map-layer-menu'),
      elevation: 10,
      shadowColor: const Color(0xA0000000),
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mapChrome.fillAlpha(context.mapChrome.chromeBase, .96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: context.mapChrome.ink.withValues(alpha: .11),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(8, 3, 8, 9),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.layers_outlined,
                      size: 17,
                      color: context.mapChrome.accent,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Map display',
                        style: TextStyle(
                          color: context.mapChrome.ink,
                          fontSize: ResourceMapPanelMetrics.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 1,
                child: ColoredBox(
                  color: context.mapChrome.softOutline.withValues(alpha: .55),
                ),
              ),
              _MapLayerMenuRow(
                key: const ValueKey<String>('resource-map-layer-all-nodes'),
                icon: Icons.scatter_plot_outlined,
                label: 'All map nodes',
                selected: _showAllNodes,
                onPressed: () => _setMapDisplayPreferences(
                  _nodeNetworkPreferences.copyWith(
                    showAllMapNodes: !_showAllNodes,
                  ),
                ),
              ),
              // Connections can turn their required node layer on, matching
              // the existing worker-menu action without another hidden toggle.
              KeyedSubtree(
                key: const ValueKey<String>(
                  'resource-map-worker-connections-action',
                ),
                child: _MapLayerMenuRow(
                  key: const ValueKey<String>(
                    'resource-map-layer-all-connections',
                  ),
                  icon: Icons.polyline_outlined,
                  label: 'All connections',
                  selected:
                      _showAllNodes &&
                      _nodeNetworkPreferences.showAllNodeConnections,
                  onPressed: _toggleWorkerConnections,
                ),
              ),
              if (_showAllNodes)
                _MapLayerMenuRow(
                  key: const ValueKey<String>(
                    'resource-map-layer-worker-outputs',
                  ),
                  icon: Icons.inventory_2_outlined,
                  label: 'All node products',
                  selected: _nodeNetworkPreferences.showWorkerOutputIcons,
                  onPressed: () => _setMapDisplayPreferences(
                    _nodeNetworkPreferences.copyWith(
                      showWorkerOutputIcons:
                          !_nodeNetworkPreferences.showWorkerOutputIcons,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final layerMenu = !_layersMenuOpen
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 7),
            child: maximumMenuHeight == null
                ? menuSurface
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maximumMenuHeight),
                    child: SingleChildScrollView(child: menuSurface),
                  ),
          );
    return SizedBox(
      key: const ValueKey<String>('resource-map-layer-controls'),
      width: math.min(
        226 * (MediaQuery.textScalerOf(context).scale(17) / 17).clamp(1, 2),
        maximumMenuWidth,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MapLayerToggleButton(
            key: const ValueKey<String>('resource-map-layer-menu-toggle'),
            tooltip: _layersMenuOpen ? 'Close map layers' : 'Open map layers',
            icon: Icons.layers_outlined,
            selected: _layersMenuOpen,
            onPressed: () => setState(() => _layersMenuOpen = !_layersMenuOpen),
          ),
          if (reduceMotion)
            layerMenu
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topRight,
              child: layerMenu,
            ),
        ],
      ),
    );
  }

  bool get _hasDetailSelection =>
      _selectedFieldSourceId != null ||
      _selectedResourceId != null ||
      (_selectedVendorId != null && !_compactLayout) ||
      _selectedNodeId != null ||
      _selectedSpotId != null ||
      _selectedPointId != null ||
      _selectedRouteId != null;

  void _openWorkerIncomePlanner() {
    _openNodeNetworkPlanner();
    if (widget.recipeWorkerBuilder != null) return;
    _openMarketValueRecommendations();
  }

  Future<void> _openWorkerRecipePlanner() async {
    _openNodeNetworkPlanner();
    if (widget.recipeWorkerBuilder != null) return;
    if (widget.plannerNeedGroups.isNotEmpty) {
      final applied = await _openGroupedRecipeGoals();
      if (!applied && mounted) {
        _openWorkerHub();
      }
    } else {
      _applyRecipeNodeRecommendation();
    }
  }

  void _openWorkerMaterialPlanner() {
    _openNodeNetworkPlanner();
    _openNodeTargets();
  }

  Widget _buildGatherPlanShortlistPage(BuildContext context) {
    final targets = _manualPlannerTargets();
    final targetsByName = <String, _MappedPlannerNeed>{
      for (final target in targets) target.resource.name.toLowerCase(): target,
    };
    final visibleRows = <Widget>[];
    final addedBloodFamilies = <String>{};
    for (final target in targets) {
      final family = _bloodFamilyForTarget(target);
      if (family == null) {
        visibleRows.add(_buildPlannerNeedRow(context, target));
        continue;
      }
      if (addedBloodFamilies.add(family.id)) {
        visibleRows.add(
          _buildPlannerBloodFamily(
            context,
            family,
            targetsByName: targetsByName,
          ),
        );
      }
    }
    return ListView(
      shrinkWrap: true,
      key: const ValueKey<String>('resource-map-gather-hub'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      children: visibleRows,
    );
  }

  _BloodFamilyDefinition? _bloodFamilyForTarget(_MappedPlannerNeed target) {
    final projected = target.need.substituteFamily;
    final projectedMembers = projected?.members
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final isProjectedBloodFamily =
        projected != null &&
        projectedMembers != null &&
        projectedMembers.length > 1 &&
        projectedMembers.every((name) => name.toLowerCase().endsWith(' blood'));
    if (isProjectedBloodFamily) {
      final projectedNames = <String>{
        for (final name in projectedMembers) name.toLowerCase(),
      };
      _BloodFamilyDefinition? fallback;
      var bestOverlap = 0;
      for (final family in _bloodFamilyDefinitions) {
        final exactLabel =
            family.label.toLowerCase() == projected.familyName.toLowerCase();
        final overlap = family.members
            .where(
              (member) => projectedNames.contains(member.name.toLowerCase()),
            )
            .length;
        if (exactLabel || overlap > bestOverlap) {
          fallback = family;
          bestOverlap = overlap;
          if (exactLabel) break;
        }
      }
      final members = <_BloodFamilyMember>[
        for (final name in projectedMembers)
          _BloodFamilyMember(
            name: name,
            gameItemId:
                widget.dataset.resources
                    .where(
                      (resource) =>
                          resource.name.toLowerCase() == name.toLowerCase(),
                    )
                    .firstOrNull
                    ?.gameItemId ??
                fallback?.members
                    .where(
                      (member) =>
                          member.name.toLowerCase() == name.toLowerCase(),
                    )
                    .firstOrNull
                    ?.gameItemId,
          ),
      ];
      if (members.isNotEmpty) {
        final id = projected.familyName
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
        return _BloodFamilyDefinition(
          id: id,
          label: projected.familyName.toLowerCase().contains('blood group')
              ? projected.familyName
              : fallback?.label ?? 'Blood alternatives',
          members: members,
          ratios: projected.ratios,
        );
      }
    }
    return _bloodFamilyForName(target.resource.name);
  }

  _BloodFamilyDefinition? _bloodFamilyForName(String name) {
    final folded = name.trim().toLowerCase();
    for (final family in _bloodFamilyDefinitions) {
      if (family.members.any((member) => member.name.toLowerCase() == folded)) {
        return family;
      }
    }
    return null;
  }

  BdoResourceDefinition? _resourceForBloodMember(_BloodFamilyMember member) {
    for (final resource in widget.dataset.resources) {
      if ((member.gameItemId != null &&
              resource.gameItemId == member.gameItemId) ||
          resource.name.toLowerCase() == member.name.toLowerCase()) {
        return resource;
      }
    }
    return null;
  }

  BdoResourceDefinition _artworkResourceForBloodMember(
    _BloodFamilyMember member,
  ) =>
      _resourceForBloodMember(member) ??
      BdoResourceDefinition(
        id: member.gameItemId == null
            ? 'planner-family:${member.name.toLowerCase()}'
            : 'item:${member.gameItemId}',
        gameItemId: member.gameItemId,
        name: member.name,
        category: 'Gathering blood',
        section: BdoResourceSection.bloodHides,
        aliases: const <String>[],
        acquisitionModes: const <BdoAcquisitionMode>{
          BdoAcquisitionMode.fieldGathering,
        },
      );

  Widget _buildPlannerBloodFamily(
    BuildContext context,
    _BloodFamilyDefinition family, {
    required Map<String, _MappedPlannerNeed> targetsByName,
  }) {
    final expanded = _expandedGatherBloodFamilyId == family.id;
    final neededQuantity = family.members.fold<double>(0, (sum, member) {
      final target = targetsByName[member.name.toLowerCase()];
      return sum + (target?.need.missingQuantity ?? 0);
    });
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final memberList = expanded
        ? Padding(
            padding: const EdgeInsetsDirectional.only(start: 18),
            child: Column(
              children: <Widget>[
                for (var index = 0; index < family.members.length; index++)
                  _buildBloodFamilyMemberRow(
                    context,
                    family,
                    family.members[index],
                    targetsByName[family.members[index].name.toLowerCase()],
                    index: index,
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();
    return Column(
      key: ValueKey<String>('resource-map-plan-blood-family-${family.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSidebarRowIsland(
          child: Material(
            color: Colors.transparent,
            child: Semantics(
              button: true,
              expanded: expanded,
              label: '${family.label}, ${family.members.length} choices',
              child: InkWell(
                key: ValueKey<String>(
                  'resource-map-plan-blood-family-toggle-${family.id}',
                ),
                onTap: () => setState(() {
                  _expandedGatherBloodFamilyId = expanded ? null : family.id;
                }),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                  child: Row(
                    children: <Widget>[
                      const ResourceMapStewardIcon(
                        kind: ResourceMapStewardIconKind.bloodHides,
                        size: ResourceMapPanelMetrics.optionArtwork,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              family.label,
                              style: TextStyle(
                                color: context.mapChrome.ink,
                                fontSize: ResourceMapPanelMetrics.optionLabel,
                                height: 1.12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Need ${_formatMapQuantity(neededQuantity)}',
                              style: TextStyle(
                                color: context.mapChrome.muted,
                                fontSize: ResourceMapPanelMetrics.secondary,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: expanded ? .25 : 0,
                        duration: reduceMotion
                            ? Duration.zero
                            : ResourceMapAtlasMotion.quick,
                        curve: ResourceMapAtlasMotion.curve,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: expanded
                              ? context.mapChrome.accent
                              : context.mapChrome.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (reduceMotion)
          memberList
        else
          AnimatedSize(
            duration: ResourceMapAtlasMotion.settle,
            curve: ResourceMapAtlasMotion.curve,
            alignment: Alignment.topCenter,
            child: memberList,
          ),
      ],
    );
  }

  Widget _buildBloodFamilyMemberRow(
    BuildContext context,
    _BloodFamilyDefinition family,
    _BloodFamilyMember member,
    _MappedPlannerNeed? plannerNeed, {
    required int index,
  }) {
    final resource = _resourceForBloodMember(member);
    final artworkResource = _artworkResourceForBloodMember(member);
    final hasMappedLocations =
        resource != null && widget.dataset.hasMappedManualSource(resource.id);
    final ratio = family.ratios[member.name] ?? 1;
    final ratioLabel = (ratio - 1).abs() <= .0001
        ? ''
        : '${_formatMapQuantity(ratio)}×';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final memberKey =
        member.gameItemId?.toString() ??
        member.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(
        'resource-map-plan-blood-family-${family.id}-member-$memberKey',
      ),
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 130 + math.min(index, 5) * 24),
      curve: ResourceMapAtlasMotion.curve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(10 * (1 - value), 0),
          child: child,
        ),
      ),
      child: _buildSidebarRowIsland(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: resource == null || !hasMappedLocations
                ? null
                : () => _runSuggestedSearch(resource.name),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
              child: Row(
                children: <Widget>[
                  _buildResourceArtwork(
                    context,
                    artworkResource,
                    size: ResourceMapPanelMetrics.optionArtwork,
                    fallbackIcon: Icons.water_drop_rounded,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          member.name,
                          style: TextStyle(
                            color: hasMappedLocations
                                ? context.mapChrome.ink
                                : context.mapChrome.muted,
                            fontSize: ResourceMapPanelMetrics.optionLabel,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (plannerNeed != null || ratioLabel.isNotEmpty)
                          Text(
                            plannerNeed == null
                                ? ratioLabel
                                : 'Need ${_formatMapQuantity(plannerNeed.need.missingQuantity)}'
                                      '${ratioLabel.isEmpty ? '' : ' · $ratioLabel'}',
                            style: TextStyle(
                              color: plannerNeed == null
                                  ? context.mapChrome.muted
                                  : context.mapChrome.accent,
                              fontSize: ResourceMapPanelMetrics.secondary,
                              height: 1.2,
                              fontWeight: plannerNeed == null
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasMappedLocations) ...<Widget>[
                    const SizedBox(width: 5),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: context.mapChrome.muted,
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

  Widget _buildGatherTaskHub(
    BuildContext context, {
    double maximumHeight = 600,
  }) {
    if (_compactLayout) {
      return _buildHomePanel(context);
    }
    final manualPlannerTargets = _manualPlannerTargets();
    return ResourceMapAtlasCommandMenu(
      key: const ValueKey<String>('resource-map-gather-hub'),
      semanticsLabel: 'Gathering tools',
      maximumHeight: maximumHeight,
      actions: <ResourceMapAtlasCommandAction>[
        if (manualPlannerTargets.isNotEmpty)
          ResourceMapAtlasCommandAction(
            key: const ValueKey<String>('resource-map-gather-plan-shortlist'),
            label: 'Needed for your plan',
            icon: const ResourceMapMenuArtwork(
              kind: ResourceMapMenuArtworkKind.plan,
            ),
            semanticHint: 'Show the gathering materials your plan still needs.',
            onPressed: _openGatherPlanShortlist,
          ),
        ResourceMapAtlasCommandAction(
          key: const ValueKey<String>('resource-map-command-checklist'),
          label: 'To-do list',
          icon: const ResourceMapMenuArtwork(
            kind: ResourceMapMenuArtworkKind.checklist,
          ),
          semanticHint: 'Open your gathering checklist.',
          onPressed: _openGatherChecklist,
        ),
        for (final section in BdoResourceSection.values)
          if (_browserEntryCountForSection(section) > 0)
            ResourceMapAtlasCommandAction(
              key: ValueKey<String>('resource-map-section-${section.name}'),
              label: _resourceSectionLabel(section),
              icon: _buildResourceSectionArtwork(context, section),
              semanticHint: 'Browse ${_resourceSectionLabel(section)}.',
              onPressed: () => _openResourceSection(section),
            ),
      ],
    );
  }

  Widget _buildWorkerTaskHub(
    BuildContext context, {
    double maximumHeight = 600,
    bool setupOnly = false,
    bool framed = true,
  }) {
    final ownedHouseCount = _nodeNetworkPreferences.currentOwnedHouseIds.length;
    final hasGroupedRecipeNeeds = widget.plannerNeedGroups.any(
      (group) => group.materials.any(
        (material) =>
            material.need.missingQuantity.isFinite &&
            material.need.missingQuantity > 0,
      ),
    );
    final hasRecipeNeeds =
        hasGroupedRecipeNeeds ||
        widget.plannerNeeds.any(
          (need) => need.missingQuantity.isFinite && need.missingQuantity > 0,
        );
    return ResourceMapAtlasCommandMenu(
      key: const ValueKey<String>('resource-map-worker-hub'),
      semanticsLabel: 'Worker tools',
      maximumHeight: maximumHeight,
      framed: framed,
      actions: setupOnly
          ? const []
          : <ResourceMapAtlasCommandAction>[
              if (hasRecipeNeeds || widget.recipeWorkerBuilder != null)
                ResourceMapAtlasCommandAction(
                  key: const ValueKey<String>(
                    'resource-map-recommend-current-recipe',
                  ),
                  label: widget.recipeWorkerBuilder == null
                      ? 'Needed for your plan'
                      : 'Recipe',
                  icon: const ResourceMapMenuArtwork(
                    kind: ResourceMapMenuArtworkKind.plan,
                  ),
                  semanticHint: hasGroupedRecipeNeeds
                      ? 'Combine shortages into one worker route.'
                      : 'Build a worker route for missing ingredients.',
                  onPressed: _openWorkerRecipePlanner,
                ),
              ResourceMapAtlasCommandAction(
                key: const ValueKey<String>('resource-map-node-mode-materials'),
                label: 'Specific items',
                icon: const ResourceMapMenuArtwork(
                  kind: ResourceMapMenuArtworkKind.materials,
                ),
                semanticHint: 'Choose materials and target node counts.',
                onPressed: _openWorkerMaterialPlanner,
              ),
              if (widget.recipeWorkerBuilder == null)
                ResourceMapAtlasCommandAction(
                  key: const ValueKey<String>(
                    'resource-map-open-market-value-recommendations',
                  ),
                  label: 'Best income',
                  icon: const ResourceMapMenuArtwork(
                    kind: ResourceMapMenuArtworkKind.income,
                  ),
                  semanticHint: 'Compare worker-node income.',
                  onPressed: _openWorkerIncomePlanner,
                ),
              ResourceMapAtlasCommandAction(
                key: const ValueKey<String>(
                  'resource-map-worker-browse-action',
                ),
                label: 'Find nodes',
                icon: const ResourceMapMenuArtwork(
                  kind: ResourceMapMenuArtworkKind.findNodes,
                ),
                semanticHint: 'Browse worker nodes.',
                onPressed: _openWorkerOverview,
              ),
            ],
      setupActions: <ResourceMapAtlasCommandAction>[
        ResourceMapAtlasCommandAction(
          key: const ValueKey<String>('resource-map-invest-node-mode'),
          label: 'Invest nodes',
          badge: _investNodeMode ? 'On' : null,
          selected: _investNodeMode,
          icon: const ResourceMapMenuArtwork(
            kind: ResourceMapMenuArtworkKind.invest,
          ),
          semanticHint: 'Add or remove invested nodes on the map.',
          onPressed: _toggleInvestNodeMode,
        ),
        if (_compactLayout && widget.lodgingDataset != null)
          ResourceMapAtlasCommandAction(
            key: const ValueKey<String>('resource-map-worker-houses-action'),
            label: 'Houses',
            badge: ownedHouseCount == 0 ? null : '$ownedHouseCount',
            icon: const ResourceMapMenuArtwork(
              kind: ResourceMapMenuArtworkKind.houses,
            ),
            semanticHint: 'Plan worker lodging.',
            onPressed: _openHousingDirectory,
          ),
        if (_royalWorkshopEnabled)
          ResourceMapAtlasCommandAction(
            key: const ValueKey<String>(
              'resource-map-worker-royal-workshop-action',
            ),
            label: 'Royal Workshop',
            icon: const ResourceMapMenuArtwork(
              kind: ResourceMapMenuArtworkKind.royalWorkshop,
            ),
            semanticHint: 'Open the Royal Workshop planner.',
            onPressed: _openRoyalWorkshop,
          ),
        if (widget.showSetupScreenshotImport &&
            widget.setupScreenshotPicker != null)
          ResourceMapAtlasCommandAction(
            key: const ValueKey<String>(
              'resource-map-worker-import-screenshot-action',
            ),
            label: 'Scan setup',
            icon: const ResourceMapMenuArtwork(
              kind: ResourceMapMenuArtworkKind.scan,
            ),
            semanticHint: 'Import nodes or houses from screenshots.',
            onPressed: () => unawaited(_openSetupScreenshotImport()),
          ),
      ],
    );
  }

  Widget _buildMapDashboardGrid(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledTitle = MediaQuery.textScalerOf(
          context,
        ).scale(ResourceMapPanelMetrics.primary);
        final oneColumn = constraints.maxWidth < 248 || scaledTitle > 19;
        if (oneColumn) {
          return Column(
            children: <Widget>[
              for (var index = 0; index < children.length; index += 1) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 6),
              ],
            ],
          );
        }
        final columnCount = constraints.maxWidth >= 760 ? 3 : 2;
        return Column(
          children: <Widget>[
            for (
              var index = 0;
              index < children.length;
              index += columnCount
            ) ...[
              SizedBox(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (var offset = 0; offset < columnCount; offset++) ...[
                      if (offset > 0) const SizedBox(width: 7),
                      Expanded(
                        child: index + offset < children.length
                            ? children[index + offset]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
              if (index + columnCount < children.length)
                const SizedBox(height: 7),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMapDashboardCard({
    required Key key,
    required IconData icon,
    required String title,
    required String semanticHint,
    required VoidCallback onPressed,
    String? subtitle,
    String? badge,
    bool selected = false,
    bool featured = false,
    Color? accentColor,
  }) => _MapDashboardTile(
    key: key,
    icon: icon,
    title: title,
    subtitle: subtitle,
    badge: badge,
    semanticHint: semanticHint,
    selected: selected,
    featured: featured,
    accentColor: accentColor,
    onPressed: onPressed,
  );

  Widget _buildWorkerHubAction({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ResourceMapPanelMetrics.optionGap),
      child: _buildMapDashboardCard(
        key: key,
        icon: icon,
        title: title,
        subtitle: subtitle,
        semanticHint: subtitle,
        featured: true,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSidebarPage({
    required Key key,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 10, 14, 16),
  }) {
    return KeyedSubtree(
      key: key,
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _buildGatherChecklistPage(BuildContext context) {
    return _buildSidebarPage(
      key: const ValueKey<String>('resource-map-sidebar-gather-checklist'),
      child: _buildGatherChecklistContent(context),
    );
  }

  Widget _buildHousingDirectoryPage(BuildContext context) {
    final dataset = widget.lodgingDataset;
    if (dataset == null) {
      return _buildSidebarPage(
        key: const ValueKey<String>('resource-map-sidebar-housing-unavailable'),
        child: const _EmptyAcquisition(
          text: 'House data is not available in this map build.',
        ),
      );
    }
    final towns = dataset.towns.toList(growable: false)
      ..sort((left, right) {
        final leftOwned = _ownedHouseIdsForTown(left).length;
        final rightOwned = _ownedHouseIdsForTown(right).length;
        final byOwned = rightOwned.compareTo(leftOwned);
        return byOwned != 0 ? byOwned : left.name.compareTo(right.name);
      });
    return _buildSidebarPage(
      key: const ValueKey<String>('resource-map-sidebar-housing-directory'),
      padding: EdgeInsets.zero,
      child: CustomScrollView(
        shrinkWrap: true,
        key: const ValueKey<String>('resource-map-housing-town-list'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.showSetupScreenshotImport &&
                    widget.setupScreenshotPicker != null) ...<Widget>[
                  const SizedBox(height: 8),
                  ResourceMapInlineAction(
                    key: const ValueKey<String>(
                      'resource-map-housing-import-screenshot',
                    ),
                    icon: Icons.document_scanner_outlined,
                    label: 'Scan screenshots',
                    onPressed: () => unawaited(
                      _openSetupScreenshotImport(
                        initialMode: BdoSetupScreenshotImportMode.townHouses,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: ResourceMapPanelMetrics.optionGap),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: towns.length,
            itemBuilder: (context, index) {
              final town = towns[index];
              final ownedCount = _ownedHouseIdsForTown(town).length;
              return _HousingTownDirectoryRow(
                key: ValueKey<String>(
                  'resource-map-housing-town-${town.townNodeId}',
                ),
                town: town,
                ownedCount: ownedCount,
                onTap: () => _openHousingTown(town.townNodeId),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
        ],
      ),
    );
  }

  Widget _buildRoyalWorkshopPage(BuildContext context) {
    if (_royalWorkshopGoods.isEmpty) {
      return const Center(
        key: ValueKey<String>('resource-map-royal-workshop-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final yukjoTown = widget.lodgingDataset?.townsByNodeId['1853'];
    final configured =
        _nodeNetworkPreferences.townWorkerCapacitiesByNodeId['1853'];
    final hiredWorkers =
        configured?.hiredWorkerCount ?? configured?.availableWorkerCount ?? 0;
    final lodgingSlots = yukjoTown == null
        ? 1 + (configured?.effectiveBonusLodgingSlotCount ?? 0)
        : _currentWorkerCapacityForTown(yukjoTown);
    return BdoRoyalWorkshopManager(
      key: const ValueKey<String>('resource-map-royal-workshop-manager'),
      plan: _nodeNetworkPreferences.royalWorkshopPlan,
      goods: _royalWorkshopGoods,
      onChanged: _updateRoyalWorkshopPlan,
      onOpenYukjoHousing: _openYukjoHousingFromRoyalWorkshop,
      onMarkManager: _markRoyalWorkshopManager,
      onClose: _navigateBack,
      yukjoHiredWorkers: hiredWorkers,
      yukjoLodgingSlots: lodgingSlots,
    );
  }

  Widget _buildGatherChecklistContent(BuildContext context) {
    final entries = _gatherChecklist.entries;
    final currentId = _gatherChecklist.currentEntry?.resourceId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            TextButton.icon(
              key: const ValueKey<String>('resource-map-gather-checklist-next'),
              onPressed: _gatherChecklist.remainingCount == 0
                  ? null
                  : _focusNextGatherChecklistEntry,
              icon: const Icon(Icons.near_me_outlined, size: 16),
              label: const Text('Next'),
            ),
          ],
        ),
        if (_gatherChecklist.completedCount > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>(
                'resource-map-gather-checklist-clear-completed',
              ),
              onPressed: () =>
                  _updateGatherChecklist(_gatherChecklist.clearCompleted()),
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Clear completed'),
            ),
          ),
        const SizedBox(height: 5),
        Flexible(
          fit: FlexFit.loose,
          child: entries.isEmpty
              ? const _GatherChecklistEmptyState()
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  key: const ValueKey<String>(
                    'resource-map-gather-checklist-list',
                  ),
                  buildDefaultDragHandles: false,
                  itemCount: entries.length,
                  onReorderItem: _reorderGatherChecklist,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final resource =
                        widget.dataset.resourcesById[entry.resourceId];
                    final hasLocation =
                        resource != null &&
                        (_hasManualMapSource(resource.id) ||
                            widget.dataset.hasWorkerSource(resource.id));
                    final selected = entry.resourceId == currentId;
                    final routeLabel = switch (entry.sourceKind) {
                      BdoGatherChecklistSourceKind.manualGathering =>
                        'Manual gathering',
                      BdoGatherChecklistSourceKind.workerNode => 'Worker node',
                      BdoGatherChecklistSourceKind.fishing => 'Fishing',
                      null => 'Best available source',
                    };
                    return _buildSidebarRowIsland(
                      key: ValueKey<String>(
                        'resource-map-gather-checklist-${entry.resourceId}',
                      ),
                      selected: selected,
                      child: GatherChecklistQuantityRow(
                        resourceId: entry.resourceId,
                        quantity:
                            widget.gatherChecklistQuantities[entry
                                .resourceId] ??
                            BdoGatherChecklistQuantity(
                              needed: entry.neededQuantity,
                            ),
                        onRecord: widget.onRecordGathered,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: hasLocation
                                ? () => _focusGatherChecklistEntry(entry)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 5,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Checkbox(
                                    key: ValueKey<String>(
                                      'resource-map-gather-checklist-complete-'
                                      '${entry.resourceId}',
                                    ),
                                    value: entry.isCompleted,
                                    onChanged: (_) =>
                                        _toggleGatherChecklistCompletion(
                                          entry.resourceId,
                                        ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          resource?.name ??
                                              entry.displayName ??
                                              entry.resourceId,
                                          style: TextStyle(
                                            color: entry.isCompleted
                                                ? context.mapChrome.muted
                                                : context.mapChrome.ink,
                                            fontSize: ResourceMapPanelMetrics
                                                .optionLabel,
                                            height: 1.12,
                                            fontWeight: FontWeight.w700,
                                            decoration: entry.isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          hasLocation
                                              ? routeLabel
                                              : 'No mapped location available',
                                          style: TextStyle(
                                            color: hasLocation
                                                ? context.mapChrome.muted
                                                : context.mapChrome.error,
                                            fontSize: ResourceMapPanelMetrics
                                                .secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hasLocation)
                                    MapQuietIconButton(
                                      key: ValueKey<String>(
                                        'resource-map-gather-checklist-locate-'
                                        '${entry.resourceId}',
                                      ),
                                      tooltip: 'Show on map',
                                      onPressed: () =>
                                          _focusGatherChecklistEntry(entry),
                                      icon: const Icon(
                                        Icons.near_me_outlined,
                                        size: 17,
                                      ),
                                    ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: EdgeInsets.all(9),
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        size: 18,
                                        color: context.mapChrome.muted,
                                      ),
                                    ),
                                  ),
                                  MapQuietIconButton(
                                    key: ValueKey<String>(
                                      'resource-map-gather-checklist-remove-'
                                      '${entry.resourceId}',
                                    ),
                                    tooltip: 'Remove from checklist',
                                    onPressed: () =>
                                        _removeResourceFromGatherChecklist(
                                          entry.resourceId,
                                        ),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHomePanel(BuildContext context) {
    final manualPlannerTargets = _manualPlannerTargets();
    final visiblePlannerTargets = manualPlannerTargets
        .take(4)
        .toList(growable: false);
    final featuredSources =
        widget.dataset.fieldSources
            .where(
              (source) =>
                  widget.dataset
                      .gatheringPointsForFieldSource(source.id)
                      .isNotEmpty ||
                  _gatheringSpotsForFieldSource(source).isNotEmpty,
            )
            .toList(growable: false)
          ..sort((a, b) {
            int priority(BdoFieldSource source) {
              if (source.id == 'field-source:marni-sniper-hunting') {
                return -1;
              }
              var result = 1 << 20;
              for (final product in source.products) {
                final itemId = widget
                    .dataset
                    .resourcesById[product.resourceId]
                    ?.gameItemId;
                result = math.min(
                  result,
                  _featuredExactResourcePriority[itemId] ?? 1 << 20,
                );
              }
              return result;
            }

            final aPriority = priority(a);
            final bPriority = priority(b);
            final byPriority = aPriority.compareTo(bPriority);
            if (byPriority != 0) {
              return byPriority;
            }
            final aCount = widget.dataset
                .gatheringPointsForFieldSource(a.id)
                .length;
            final bCount = widget.dataset
                .gatheringPointsForFieldSource(b.id)
                .length;
            final byCount = bCount.compareTo(aCount);
            return byCount != 0 ? byCount : a.name.compareTo(b.name);
          });
    return _buildSidebarPage(
      key: const ValueKey<String>('resource-map-sidebar-home-page'),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: <Widget>[
          _buildResourceSectionGrid(context),
          if (_materialSourceFilter ==
              _MaterialSourceFilter.worker) ...<Widget>[
            const SizedBox(height: 12),
            _buildInlineNavigationRow(
              key: const ValueKey<String>('resource-map-open-worker-network'),
              icon: Icons.account_tree_outlined,
              title: 'Browse by worker activity',
              subtitle: '',
              onTap: _openWorkerOverview,
            ),
          ],
          if (visiblePlannerTargets.isNotEmpty &&
              _materialSourceFilter !=
                  _MaterialSourceFilter.worker) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Plan materials',
                    style: TextStyle(
                      color: context.mapChrome.muted,
                      fontSize: ResourceMapPanelMetrics.secondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .9,
                    ),
                  ),
                ),
                if (widget.plannerContextLabel case final label?
                    when label.trim().isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 152),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: context.mapChrome.accent,
                        fontSize: ResourceMapPanelMetrics.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const SizedBox(height: 8),
            for (final item in visiblePlannerTargets)
              _buildPlannerNeedRow(context, item),
          ],
          if (featuredSources.isNotEmpty &&
              _materialSourceFilter !=
                  _MaterialSourceFilter.worker) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Locations',
              style: TextStyle(
                color: context.mapChrome.muted,
                fontSize: ResourceMapPanelMetrics.secondary,
                fontWeight: FontWeight.w600,
                letterSpacing: .9,
              ),
            ),
            const SizedBox(height: 5),
            const SizedBox(height: 7),
            for (final source in featuredSources.take(4))
              _buildFieldSourceBrowserRow(context, source),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  bool _resourceMatchesCurrentSource(BdoResourceDefinition resource) {
    return switch (_materialSourceFilter) {
      _MaterialSourceFilter.all =>
        widget.dataset.hasMappedManualSource(resource.id) ||
            widget.dataset.fieldSourcesForResource(resource.id).isNotEmpty ||
            widget.dataset.hasWorkerSource(resource.id),
      _MaterialSourceFilter.manual =>
        widget.dataset.hasMappedManualSource(resource.id) ||
            widget.dataset.fieldSourcesForResource(resource.id).isNotEmpty,
      _MaterialSourceFilter.worker => widget.dataset.hasWorkerSource(
        resource.id,
      ),
    };
  }

  List<BdoResourceDefinition> _resourcesForCurrentBrowser() {
    final resources = _browseFavorites
        ? _favoriteResourceIds
              .map((id) => widget.dataset.resourcesById[id])
              .whereType<BdoResourceDefinition>()
        : widget.dataset.resourcesForSection(_selectedResourceSection!);
    final result = resources
        .where(_resourceMatchesCurrentSource)
        .where((resource) {
          if (_materialSourceFilter == _MaterialSourceFilter.worker) {
            return true;
          }
          final fieldSources = widget.dataset.fieldSourcesForResource(
            resource.id,
          );
          if (_browseFavorites) {
            return fieldSources.isEmpty;
          }
          final section = _selectedResourceSection!;
          return fieldSources.every(
            (source) => !_fieldSourceAppearsInSection(source, section),
          );
        })
        .toList(growable: false);
    result.sort((left, right) => left.name.compareTo(right.name));
    return result;
  }

  List<BdoFieldSource> _fieldSourcesForCurrentBrowser() {
    if (_materialSourceFilter == _MaterialSourceFilter.worker) {
      return const <BdoFieldSource>[];
    }
    final section = _selectedResourceSection;
    final sources = widget.dataset.fieldSources
        .where((source) {
          final resources = source.products
              .map(
                (product) => widget.dataset.resourcesById[product.resourceId],
              )
              .whereType<BdoResourceDefinition>();
          if (_browseFavorites) {
            return resources.any(
              (resource) => _favoriteResourceIds.contains(resource.id),
            );
          }
          return section != null &&
              _fieldSourceAppearsInSection(source, section);
        })
        .toList(growable: false);
    sources.sort((left, right) => left.name.compareTo(right.name));
    return sources;
  }

  int _browserEntryCountForSection(BdoResourceSection? section) {
    final favorites = section == null;
    bool resourceInScope(BdoResourceDefinition resource) {
      return favorites
          ? _favoriteResourceIds.contains(resource.id)
          : resource.section == section;
    }

    if (_materialSourceFilter == _MaterialSourceFilter.worker) {
      return widget.dataset.resources
          .where(resourceInScope)
          .where((resource) => widget.dataset.hasWorkerSource(resource.id))
          .length;
    }
    final sourceIds = <String>{
      for (final source in widget.dataset.fieldSources)
        if (favorites
            ? source.products.any((product) {
                final resource =
                    widget.dataset.resourcesById[product.resourceId];
                return resource != null && resourceInScope(resource);
              })
            : _fieldSourceAppearsInSection(source, section))
          source.id,
    };
    if (_materialSourceFilter == _MaterialSourceFilter.manual) {
      final standaloneManual = widget.dataset.resources.where((resource) {
        final groupedInSection = favorites
            ? widget.dataset.fieldSourcesForResource(resource.id).isNotEmpty
            : widget.dataset
                  .fieldSourcesForResource(resource.id)
                  .any(
                    (source) => _fieldSourceAppearsInSection(source, section),
                  );
        return resourceInScope(resource) &&
            widget.dataset.hasMappedManualSource(resource.id) &&
            !groupedInSection;
      }).length;
      return sourceIds.length + standaloneManual;
    }
    final standaloneResources = widget.dataset.resources.where((resource) {
      final groupedInSection = favorites
          ? widget.dataset.fieldSourcesForResource(resource.id).isNotEmpty
          : widget.dataset
                .fieldSourcesForResource(resource.id)
                .any((source) => _fieldSourceAppearsInSection(source, section));
      return resourceInScope(resource) &&
          (widget.dataset.hasMappedManualSource(resource.id) ||
              widget.dataset.hasWorkerSource(resource.id)) &&
          !groupedInSection;
    }).length;
    return sourceIds.length + standaloneResources;
  }

  bool _fieldSourceAppearsInSection(
    BdoFieldSource source,
    BdoResourceSection section,
  ) {
    if (source.id == 'field-source:marni-sniper-hunting') {
      return section == BdoResourceSection.meat ||
          section == BdoResourceSection.bloodHides;
    }
    if (source.id == 'field-source:coral-stoneback-crab' ||
        source.id == 'field-source:stillcoral-coastal-gathering') {
      return section == BdoResourceSection.seafoodMarine;
    }
    return source.products.any((product) {
      final resource = widget.dataset.resourcesById[product.resourceId];
      return resource?.section == section;
    });
  }

  Widget _buildResourceSectionGrid(
    BuildContext context, {
    bool includeFavorites = true,
  }) {
    final entries = <({BdoResourceSection? section, int count})>[
      if (includeFavorites)
        (section: null, count: _browserEntryCountForSection(null)),
      for (final section in BdoResourceSection.values)
        (section: section, count: _browserEntryCountForSection(section)),
    ].where((entry) => entry.section == null || entry.count > 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledLabel = MediaQuery.textScalerOf(context).scale(12.5);
        final singleColumn = constraints.maxWidth < 255 || scaledLabel > 18.5;
        final tileWidth = singleColumn
            ? constraints.maxWidth
            : math.max(120.0, (constraints.maxWidth - 9) / 2);
        return Wrap(
          spacing: 9,
          runSpacing: 9,
          children: <Widget>[
            for (final entry in entries)
              SizedBox(
                width: tileWidth,
                child: _buildResourceSectionTile(
                  section: entry.section,
                  count: entry.count,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildResourceSectionTile({
    required BdoResourceSection? section,
    required int count,
  }) {
    final favorites = section == null;
    final label = favorites ? 'Favorites' : _resourceSectionLabel(section);
    return _buildMapDashboardCard(
      key: ValueKey<String>(
        favorites
            ? 'resource-map-section-favorites'
            : 'resource-map-section-${section.name}',
      ),
      icon: _resourceSectionIcon(section),
      title: label,
      semanticHint: 'Open $count mapped $label entries.',
      accentColor: _resourceSectionColor(section),
      onPressed: favorites
          ? _openFavorites
          : () => _openResourceSection(section),
    );
  }

  IconData _resourceSectionIcon(BdoResourceSection? section) =>
      switch (section) {
        null => Icons.bookmark_rounded,
        BdoResourceSection.plantsWood => Icons.eco_rounded,
        BdoResourceSection.oresMinerals => Icons.diamond_rounded,
        BdoResourceSection.meat => Icons.kebab_dining_rounded,
        BdoResourceSection.bloodHides => Icons.water_drop_rounded,
        BdoResourceSection.mushrooms => Icons.forest_rounded,
        BdoResourceSection.seafoodMarine => Icons.waves_rounded,
        BdoResourceSection.other => Icons.widgets_rounded,
      };

  Widget _buildResourceSectionArtwork(
    BuildContext context,
    BdoResourceSection section,
  ) {
    // Choose recognizable raw materials, independent of catalog sort order.
    final representativeId = switch (section) {
      BdoResourceSection.plantsWood => 'item:4605', // Log
      BdoResourceSection.oresMinerals => 'item:4001', // Iron Ore
      BdoResourceSection.meat => 'item:7902', // Lamb Meat
      BdoResourceSection.bloodHides => 'item:6214', // Wolf Blood
      BdoResourceSection.mushrooms => 'item:5409', // Dwarf Mushroom
      BdoResourceSection.seafoodMarine => 'item:4477', // Blue Coral
      BdoResourceSection.other => 'item:6656', // Purified Water
    };
    final resource =
        widget.dataset.resourcesById[representativeId] ??
        widget.dataset.resourcesForSection(section).firstOrNull;
    if (resource != null && widget.resourceIconBuilder != null) {
      return _buildResourceArtwork(
        context,
        resource,
        size: 36,
        fallbackIcon: _resourceSectionIcon(section),
      );
    }
    return Icon(_resourceSectionIcon(section));
  }

  Widget _buildWorkerNodeArtwork(BdoWorkerNode node, {double size = 26}) {
    final type = node.supportedSourceIconType;
    if (type != null) return BdoNodeTypeImage(sourceIconType: type, size: size);
    if (node.isResourceNode) {
      return BdoWorkerActivityImage(activity: node.activity, size: size);
    }
    return BdoNodeTypeImage(
      sourceIconType: node.nodeType == 'City'
          ? 2
          : node.nodeType == 'Town'
          ? 1
          : 0,
      size: size,
    );
  }

  Color _resourceSectionColor(BdoResourceSection? section) => switch (section) {
    null => context.mapChrome.accent,
    BdoResourceSection.plantsWood => context.mapChrome.positive,
    BdoResourceSection.oresMinerals => const Color(0xFFAFC1D7),
    BdoResourceSection.meat => context.mapChrome.primary,
    BdoResourceSection.bloodHides => const Color(0xFFE98D98),
    BdoResourceSection.mushrooms => const Color(0xFFC4A2D6),
    BdoResourceSection.seafoodMarine => const Color(0xFF83C8C7),
    BdoResourceSection.other => context.mapChrome.muted,
  };

  Widget _buildResourceBrowserPage(BuildContext context) {
    if (_browseFavorites) {
      return _buildSidebarPage(
        key: const ValueKey<String>('resource-map-resource-browser'),
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildSavedMapEntries(context),
      );
    }
    final fieldSources = _fieldSourcesForCurrentBrowser();
    final resources = _resourcesForCurrentBrowser();
    final title = _browseFavorites
        ? 'Favorite materials'
        : _resourceSectionLabel(_selectedResourceSection!);
    final entryCount = fieldSources.length + resources.length;
    final children = <Widget>[];
    if (fieldSources.isNotEmpty) {
      for (final source in fieldSources) {
        children.add(_buildFieldSourceBrowserRow(context, source));
      }
    }
    if (resources.isNotEmpty) {
      if (fieldSources.isNotEmpty) {
        children.add(
          const _SearchGroupHeading(
            key: ValueKey<String>(
              'resource-map-browser-worker-materials-heading',
            ),
            label: 'Worker materials',
            surface: false,
            compact: true,
          ),
        );
      }
      for (final resource in resources) {
        children.add(_buildResourceBrowserRow(context, resource));
      }
    }
    return _buildSidebarPage(
      key: const ValueKey<String>('resource-map-resource-browser'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_compactLayout)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey<String>(
                  'resource-map-browser-all-categories',
                ),
                onPressed: _closeResourceBrowser,
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: const Text('Categories'),
                style: TextButton.styleFrom(
                  foregroundColor: context.mapChrome.muted,
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(
                    fontFamily: 'Segoe UI',
                    fontSize: ResourceMapPanelMetrics.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Flexible(
            fit: FlexFit.loose,
            child: entryCount == 0
                ? Center(
                    heightFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _browseFavorites
                                ? Icons.star_outline_rounded
                                : Icons.filter_alt_off_outlined,
                            color: context.mapChrome.divider,
                            size: 36,
                          ),
                          const SizedBox(height: 9),
                          Text(
                            _browseFavorites
                                ? 'Star a material to keep it here.'
                                : 'No $title materials match this filter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.mapChrome.muted,
                              fontSize: ResourceMapPanelMetrics.secondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: children,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldSourceBrowserRow(
    BuildContext context,
    BdoFieldSource source,
  ) {
    final preferredProduct = _preferredProductForFieldSource(source);
    final preferredResource = preferredProduct == null
        ? null
        : widget.dataset.resourcesById[preferredProduct.resourceId];
    final workerResource =
        preferredResource != null &&
            widget.dataset.hasWorkerSource(preferredResource.id)
        ? preferredResource
        : source.products
              .map(
                (product) => widget.dataset.resourcesById[product.resourceId],
              )
              .whereType<BdoResourceDefinition>()
              .where((resource) => widget.dataset.hasWorkerSource(resource.id))
              .firstOrNull;
    final workerCount = workerResource == null
        ? 0
        : widget.dataset.workerNodesForResource(workerResource.id).length;
    final sourceFavoriteKey =
        'map:${BdoSearchKind.fieldSource.name}:${source.id}';
    return _buildGatheringBrowserEntry(
      key: ValueKey<String>('resource-map-browser-source-${source.id}'),
      title: source.name,
      artwork: preferredResource == null
          ? Icon(
              _iconForFieldSource(source),
              size: 30,
              color: context.mapChrome.primary,
            )
          : _buildResourceArtwork(
              context,
              preferredResource,
              size: ResourceMapPanelMetrics.optionArtwork,
              fallbackIcon: _iconForFieldSource(source),
            ),
      workerCount: workerCount,
      workerResource: workerResource,
      onTap: () => _selectFieldSource(source),
      favoriteButton: ResourceMapFavoriteButton(
        key: ValueKey<String>('resource-map-favorite-source-${source.id}'),
        name: source.name,
        saved: _favoriteResourceIds.contains(sourceFavoriteKey),
        onPressed: () => _toggleFavoriteKey(sourceFavoriteKey),
      ),
    );
  }

  Widget _buildResourceBrowserRow(
    BuildContext context,
    BdoResourceDefinition resource,
  ) {
    final favorite = _favoriteResourceIds.contains(resource.id);
    return _buildGatheringBrowserEntry(
      key: ValueKey<String>('resource-map-browser-resource-${resource.id}'),
      title: resource.name,
      artwork: _buildResourceArtwork(
        context,
        resource,
        size: ResourceMapPanelMetrics.optionArtwork,
        fallbackIcon: Icons.inventory_2_outlined,
      ),
      workerCount: widget.dataset.workerNodesForResource(resource.id).length,
      workerResource: resource,
      onTap: () => _selectBrowserResource(resource),
      favoriteButton: ResourceMapFavoriteButton(
        key: ValueKey<String>('resource-map-favorite-${resource.id}'),
        name: resource.name,
        saved: favorite,
        onPressed: () => _toggleFavorite(resource),
      ),
    );
  }

  void _selectBrowserResource(BdoResourceDefinition resource) {
    _searchController.value = TextEditingValue(
      text: resource.name,
      selection: TextSelection.collapsed(offset: resource.name.length),
    );
    // The row already identifies the item. Text search can choose a different
    // item with the same name, or exclude this one through an old search scope.
    _selectSearchResult(
      BdoSearchResult(
        kind: BdoSearchKind.resource,
        id: resource.id,
        resourceId: resource.id,
        title: resource.name,
        subtitle: '',
        searchText: resource.name,
      ),
    );
  }

  Widget _buildGatheringBrowserEntry({
    required Key key,
    required String title,
    required Widget artwork,
    required int workerCount,
    required BdoResourceDefinition? workerResource,
    required VoidCallback onTap,
    required Widget favoriteButton,
  }) {
    return _buildSidebarRowIsland(
      artworkWidth: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ResourceMapPanelMetrics.optionHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
              child: Row(
                children: [
                  ResourceMapArtworkMount(
                    size: ResourceMapPanelMetrics.optionArtwork,
                    child: artwork,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: context.mapChrome.ink,
                        fontSize: ResourceMapPanelMetrics.optionLabel,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (workerCount > 0 && workerResource != null) ...[
                    const SizedBox(width: 5),
                    MapQuietTooltip(
                      message: 'Plan worker nodes for ${workerResource.name}',
                      child: TextButton(
                        key: ValueKey<String>(
                          'resource-map-plan-workers-${workerResource.id}',
                        ),
                        onPressed: () =>
                            _openWorkerNodePlannerForResource(workerResource),
                        style: TextButton.styleFrom(
                          foregroundColor: context.mapChrome.text,
                          minimumSize: const Size(32, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Semantics(
                          label:
                              '$workerCount worker ${workerCount == 1 ? 'node' : 'nodes'} for ${workerResource.name}',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const BdoNodeTypeImage(
                                sourceIconType: 0,
                                size: ResourceMapPanelMetrics.controlGlyph,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 5),
                  favoriteButton,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarRowIsland({
    Key? key,
    required Widget child,
    bool selected = false,
    double? artworkWidth,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: ResourceMapPanelMetrics.optionGap),
    child: ResourceMapPill(
      selected: selected,
      leadingWidth: artworkWidth,
      child: child,
    ),
  );

  Widget _buildInlineNavigationRow({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _buildSidebarRowIsland(
      child: Material(
        key: key,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 19, color: context.mapChrome.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: context.mapChrome.ink,
                          fontSize: ResourceMapPanelMetrics.optionLabel,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: context.mapChrome.muted,
                            fontSize: ResourceMapPanelMetrics.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: context.mapChrome.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_MappedPlannerNeed> _manualPlannerTargets() {
    if (widget.plannerNeeds.isEmpty) {
      return const <_MappedPlannerNeed>[];
    }
    final resourcesByGameItemId = <int, BdoResourceDefinition>{};
    final resourcesByName = <String, BdoResourceDefinition>{};
    for (final resource in widget.dataset.resources) {
      final gameItemId = resource.gameItemId;
      if (gameItemId != null) {
        resourcesByGameItemId[gameItemId] = resource;
      }
      for (final candidate in <String>[resource.name, ...resource.aliases]) {
        resourcesByName.putIfAbsent(
          _normalizePlannerMaterialName(candidate),
          () => resource,
        );
      }
    }

    final result = <_MappedPlannerNeed>[];
    final includedResourceIds = <String>{};
    for (final need in widget.plannerNeeds) {
      final resource =
          (need.gameItemId == null
              ? null
              : resourcesByGameItemId[need.gameItemId!]) ??
          resourcesByName[_normalizePlannerMaterialName(need.name)];
      if (resource == null || !includedResourceIds.add(resource.id)) {
        continue;
      }
      result.add(
        _MappedPlannerNeed(
          need: need,
          resource: resource,
          exactLocationCount: widget.dataset
              .gatheringPointsForResource(resource.id)
              .length,
          workerNodeCount: widget.dataset
              .workerNodesForResource(resource.id)
              .length,
        ),
      );
    }
    final usefulManualTargets = result
        .where((item) => item.isUsefulManualTarget)
        .toList(growable: false);
    usefulManualTargets.sort((left, right) {
      final byScarcity = left.scarcityRank.compareTo(right.scarcityRank);
      if (byScarcity != 0) {
        return byScarcity;
      }
      final byManualPriority = left.manualPriority.compareTo(
        right.manualPriority,
      );
      if (byManualPriority != 0) {
        return byManualPriority;
      }
      final byCoverage = left.stockCoverage.compareTo(right.stockCoverage);
      if (byCoverage != 0) {
        return byCoverage;
      }
      final byMissing = right.need.missingQuantity.compareTo(
        left.need.missingQuantity,
      );
      return byMissing != 0
          ? byMissing
          : left.resource.name.compareTo(right.resource.name);
    });
    return List<_MappedPlannerNeed>.unmodifiable(usefulManualTargets);
  }

  Widget _buildPlannerNeedRow(BuildContext context, _MappedPlannerNeed item) {
    return _buildSidebarRowIsland(
      child: Material(
        key: ValueKey<String>('resource-map-plan-need-${item.resource.id}'),
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectBrowserResource(item.resource),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 3, 4),
            child: Row(
              children: <Widget>[
                _buildResourceArtwork(
                  context,
                  item.resource,
                  size: ResourceMapPanelMetrics.optionArtwork,
                  fallbackIcon: Icons.inventory_2_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Tooltip(
                        message: item.marketStatus,
                        child: Text(
                          item.resource.name,
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.optionLabel,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Need ${_formatMapQuantity(item.need.missingQuantity)}',
                        style: TextStyle(
                          color: context.mapChrome.muted,
                          fontSize: ResourceMapPanelMetrics.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.mapChrome.primary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResourceArtwork(
    BuildContext context,
    BdoResourceDefinition resource, {
    required double size,
    required IconData fallbackIcon,
  }) => _buildArtworkTile(
    context,
    resource,
    size: size,
    fallbackIcon: fallbackIcon,
    builder: widget.resourceIconBuilder,
  );

  Widget _buildWorkerOutputArtwork(
    BuildContext context,
    BdoResourceDefinition? resource, {
    required double size,
  }) => _buildArtworkTile(
    context,
    resource,
    size: size,
    fallbackIcon: Icons.image_not_supported_outlined,
    fallbackKey: const ValueKey<String>(
      'resource-map-missing-worker-output-artwork',
    ),
    builder: widget.workerOutputIconBuilder,
  );

  Widget _buildArtworkTile(
    BuildContext context,
    BdoResourceDefinition? resource, {
    required double size,
    required IconData fallbackIcon,
    required BdoResourceIconBuilder? builder,
    Key? fallbackKey,
  }) {
    if (builder != null && resource != null) {
      return SizedBox.square(
        dimension: size,
        child: builder(context, resource, size),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.mapChrome.paperRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.mapChrome.divider),
      ),
      child: Icon(
        key: fallbackKey,
        fallbackIcon,
        color: context.mapChrome.primary,
        size: size * .55,
      ),
    );
  }

  Widget _buildNodeNetworkPlannerPage(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<String>(
        'resource-map-node-planner-host-${_nodeNetworkPlannerPage.name}',
      ),
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 210),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) {
          final offset =
              Tween<Offset>(
                begin: const Offset(.055, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: switch (_nodeNetworkPlannerPage) {
          _NodeNetworkPlannerPage.home => _buildNodePlannerHomePage(context),
          _NodeNetworkPlannerPage.editCurrent => const SizedBox.shrink(),
          _NodeNetworkPlannerPage.targets => _buildNodeNetworkTargetsPage(
            context,
          ),
          _NodeNetworkPlannerPage.review => _buildNodeNetworkReviewPage(
            context,
          ),
          _NodeNetworkPlannerPage.marketValue =>
            _buildMarketValueRecommendationPage(context),
        },
      ),
    );
  }

  Widget _buildNodePlannerHomePage(BuildContext context) {
    if (widget.recipeWorkerBuilder case final builder?) {
      return builder(context, () => unawaited(_openWorkerCapacitySettings()), (
        id,
      ) {
        final node = widget.dataset.workerNodesById[id];
        if (node != null && !_viewport.isEmpty) {
          _showPointAvoidingDetails(node.location);
        }
      });
    }
    final hasGroupedRecipeNeeds = widget.plannerNeedGroups.any(
      (group) => group.materials.any(
        (material) =>
            material.need.missingQuantity.isFinite &&
            material.need.missingQuantity > 0,
      ),
    );
    final hasRecipeNeeds =
        hasGroupedRecipeNeeds ||
        widget.plannerNeeds.any(
          (need) => need.missingQuantity.isFinite && need.missingQuantity > 0,
        );
    return ListView(
      key: const ValueKey<String>('resource-map-node-planner-home'),
      shrinkWrap: true,
      primary: false,
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
      children: <Widget>[
        if (hasRecipeNeeds)
          _buildWorkerHubAction(
            key: const ValueKey<String>(
              'resource-map-recommend-current-recipe',
            ),
            icon: Icons.receipt_long_outlined,
            title: 'Needed for your plan',
            subtitle: '',
            onPressed: hasGroupedRecipeNeeds
                ? _openGroupedRecipeGoals
                : _applyRecipeNodeRecommendation,
          ),
        _buildWorkerHubAction(
          key: const ValueKey<String>('resource-map-node-mode-materials'),
          icon: Icons.tune_rounded,
          title: 'Plan specific items',
          subtitle: '',
          onPressed: _openNodeTargets,
        ),
        _buildWorkerHubAction(
          key: const ValueKey<String>(
            'resource-map-open-market-value-recommendations',
          ),
          icon: Icons.trending_up_rounded,
          title: widget.workerEconomics == null
              ? 'Compare valuable materials'
              : 'Worker income',
          subtitle: '',
          onPressed: _openMarketValueRecommendations,
        ),
        const SizedBox(height: 6),
        _buildMapDashboardGrid(
          context,
          children: <Widget>[
            _buildMapDashboardCard(
              key: const ValueKey<String>('resource-map-node-starting-towns'),
              icon: Icons.location_city_outlined,
              title: 'Worker towns',
              subtitle: '',
              semanticHint:
                  'Choose which towns your worker routes can start from.',
              onPressed: _openNodeRootPicker,
            ),
            if (widget.showSetupScreenshotImport &&
                widget.setupScreenshotPicker != null)
              _buildMapDashboardCard(
                key: const ValueKey<String>(
                  'resource-map-node-import-screenshot',
                ),
                icon: Icons.document_scanner_outlined,
                title: 'Scan setup',
                subtitle: '',
                semanticHint:
                    'Import invested nodes from reviewed screenshots.',
                onPressed: () => unawaited(
                  _openSetupScreenshotImport(
                    initialMode: BdoSetupScreenshotImportMode.workerNodes,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNodeTargetSearchAndSettings(BuildContext context) {
    final budget = _nodeNetworkPreferences.contributionPointBudget;
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: const ValueKey<String>('resource-map-node-target-search'),
            controller: _nodeTargetSearchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: ResourceMapPanelMetrics.primary),
            decoration: InputDecoration(
              hintText: 'Search materials',
              hintStyle: TextStyle(
                color: context.mapChrome.muted,
                fontSize: ResourceMapPanelMetrics.primary,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              suffixIcon: _nodeTargetSearchController.text.isEmpty
                  ? null
                  : MapQuietIconButton(
                      tooltip: 'Clear target search',
                      onPressed: () {
                        _nodeTargetSearchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: false,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.mapChrome.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          toggled: _nodeTargetSettingsExpanded,
          label: 'Network settings, $budget CP available',
          excludeSemantics: true,
          child: MapQuietTooltip(
            message: 'Network settings',
            child: TextButton.icon(
              key: const ValueKey<String>(
                'resource-map-node-target-settings-toggle',
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: const TextStyle(
                  fontFamily: 'Segoe UI',
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w600,
                ),
                foregroundColor: _nodeTargetSettingsExpanded
                    ? context.mapChrome.accent
                    : context.mapChrome.text,
              ),
              onPressed: () => setState(
                () =>
                    _nodeTargetSettingsExpanded = !_nodeTargetSettingsExpanded,
              ),
              icon: const Icon(Icons.settings_outlined, size: 19),
              label: const Text('Settings'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNodeTargetHiddenSettings(
    BuildContext context, {
    required Map<String, int> currentProductionCounts,
  }) {
    final hasCurrentSetup = currentProductionCounts.isNotEmpty;
    if (!_nodeTargetSettingsExpanded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 2,
            runSpacing: 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TextButton.icon(
                key: const ValueKey<String>(
                  'resource-map-node-starting-towns-targets',
                ),
                onPressed: _openNodeRootPicker,
                icon: const Icon(Icons.location_city_outlined, size: 16),
                label: const Text('Worker towns'),
              ),
              if (hasCurrentSetup)
                TextButton.icon(
                  key: const ValueKey<String>(
                    'resource-map-current-production-summary',
                  ),
                  onPressed: () =>
                      setState(() => _nodeTargetView = _NodeTargetView.current),
                  icon: const Icon(Icons.bookmark_added_outlined, size: 16),
                  label: const Text('Show my setup'),
                ),
              if (hasCurrentSetup)
                TextButton.icon(
                  key: const ValueKey<String>(
                    'resource-map-use-current-production-counts',
                  ),
                  onPressed: _useCurrentProductionCountsAsTargets,
                  icon: const Icon(Icons.add_task_rounded, size: 16),
                  label: const Text('Use my setup'),
                ),
              if (_nodeNetworkPreferences.currentNodeIds.isNotEmpty)
                MapQuietIconButton(
                  key: const ValueKey<String>(
                    'resource-map-clear-saved-node-network',
                  ),
                  tooltip: 'Clear saved setup',
                  onPressed: _clearSavedNodeNetwork,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTargetViewStrip(
    BuildContext context, {
    required int selectedCount,
  }) {
    return Wrap(
      spacing: 4,
      children: <Widget>[
        for (final view in _NodeTargetView.values)
          _NodeTargetViewButton(
            key: ValueKey<String>('resource-map-node-target-view-${view.name}'),
            view: view,
            selected: _nodeTargetView == view,
            selectedCount: selectedCount,
            onPressed: () => setState(() => _nodeTargetView = view),
          ),
      ],
    );
  }

  Widget _buildNodeTargetPreviewStatus() {
    final plan = _nodeTargetPreviewResult?.plan;
    if (_nodeTargetPreviewCalculating) {
      return Row(
        key: ValueKey<String>('resource-map-node-target-preview-loading'),
        children: <Widget>[
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    }
    if (plan == null) {
      return const SizedBox.shrink();
    }
    final lodgingCp =
        _nodeTargetPreviewLodgingPlan
            ?.plan
            ?.totalIncrementalContributionPoints ??
        0;
    final combinedCp = plan.totalContributionPoints + lodgingCp;
    final remaining = plan.contributionPointBudget - combinedCp;
    if (remaining >= 0) return const SizedBox.shrink();
    return Row(
      key: const ValueKey<String>('resource-map-node-target-preview'),
      children: <Widget>[
        Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: context.mapChrome.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Increase CP budget by ${-remaining}',
            style: TextStyle(
              color: context.mapChrome.error,
              fontSize: ResourceMapPanelMetrics.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNodeNetworkTargetsPage(BuildContext context) {
    final reachableProductionNodeIds = _reachableWorkerProductionNodeIds();
    final resources = _filteredNodeTargetResources(reachableProductionNodeIds);
    final grouped = <_NodeTargetGroup, List<BdoResourceDefinition>>{
      for (final group in _NodeTargetGroup.values)
        group: <BdoResourceDefinition>[],
    };
    for (final resource in resources) {
      grouped[_nodeTargetGroupFor(resource)]!.add(resource);
    }
    final selectedCount =
        _nodeNetworkPreferences.desiredResourceNodeCounts.length;
    final searching = _nodeTargetSearchController.text.trim().isNotEmpty;
    final currentProductionCounts = _currentProductionCountsByResourceId();
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;

    Widget budgetControls() => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: largeText ? 128 : 88,
          child: TextField(
            key: const ValueKey<String>('resource-map-node-cp-budget'),
            controller: _nodeBudgetController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: const TextStyle(
              fontSize: ResourceMapPanelMetrics.primary,
              fontWeight: FontWeight.w600,
            ),
            onSubmitted: (_) => _commitNodeBudget(),
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              _commitNodeBudget();
            },
            decoration: InputDecoration(
              labelText: 'CP available',
              labelStyle: TextStyle(
                fontSize: ResourceMapPanelMetrics.secondary,
                color: context.mapChrome.muted,
              ),
              filled: false,
              fillColor: Colors.transparent,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: context.mapChrome.softOutline),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.mapChrome.softOutline),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.mapChrome.accent),
              ),
            ),
          ),
        ),
        MapQuietIconButton(
          key: const ValueKey<String>('resource-map-node-apply-cp'),
          tooltip: 'Apply CP budget',
          onPressed: _commitNodeBudget,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
          padding: const EdgeInsets.all(4),
          icon: const Icon(Icons.check_rounded, size: 20),
        ),
      ],
    );
    Widget buildRouteAction() => MapQuietTooltip(
      message: selectedCount == 0
          ? 'Choose at least one material first'
          : 'Build the best shared route for $selectedCount '
                '${selectedCount == 1 ? 'material' : 'materials'}',
      child: FilledButton.icon(
        key: const ValueKey<String>('resource-map-build-node-network'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(
            fontFamily: 'Segoe UI',
            fontSize: ResourceMapPanelMetrics.primary,
            fontWeight: FontWeight.w700,
          ),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: selectedCount == 0 ? null : _calculateExactNodeNetwork,
        icon: const Icon(Icons.route_rounded, size: 18),
        label: const Text('Build route'),
      ),
    );
    Widget footer() => ResourceMapPill(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (selectedCount > 0) ...<Widget>[
            _buildNodeTargetPreviewStatus(),
            const SizedBox(height: 6),
          ],
          if (largeText)
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [budgetControls(), buildRouteAction()],
            )
          else
            Row(
              children: [
                Expanded(child: budgetControls()),
                const SizedBox(width: 8),
                buildRouteAction(),
              ],
            ),
        ],
      ),
    );
    final rows = <Widget>[
      if (resources.isEmpty)
        const _NodePlannerEmptyTargets()
      else if (searching)
        for (final resource in resources)
          _buildNodeTargetRow(
            context,
            resource,
            reachableProductionNodeIds: reachableProductionNodeIds,
          )
      else
        for (final group in _NodeTargetGroup.values)
          if (grouped[group]!.isNotEmpty)
            _buildNodeTargetGroup(
              context,
              group: group,
              resources: grouped[group]!,
              reachableProductionNodeIds: reachableProductionNodeIds,
            ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollWholePage = largeText || constraints.maxHeight < 300;
        final controls = <Widget>[
          ResourceMapPill(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNodeTargetSearchAndSettings(context),
                _buildNodeTargetHiddenSettings(
                  context,
                  currentProductionCounts: currentProductionCounts,
                ),
                const SizedBox(height: 4),
                _buildNodeTargetViewStrip(
                  context,
                  selectedCount: selectedCount,
                ),
              ],
            ),
          ),
          const SizedBox(height: ResourceMapPanelMetrics.optionGap),
        ];
        return KeyedSubtree(
          key: const ValueKey<String>('resource-map-node-planner-targets'),
          child: scrollWholePage
              ? SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...controls, ...rows, footer()],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...controls,
                    Flexible(
                      fit: FlexFit.loose,
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: rows,
                      ),
                    ),
                    const SizedBox(height: ResourceMapPanelMetrics.optionGap),
                    footer(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildNodeTargetGroup(
    BuildContext context, {
    required _NodeTargetGroup group,
    required List<BdoResourceDefinition> resources,
    required Set<String> reachableProductionNodeIds,
  }) {
    final searching = _nodeTargetSearchController.text.trim().isNotEmpty;
    final forcedOpen = searching || _nodeTargetView != _NodeTargetView.all;
    final expanded = forcedOpen || _expandedNodeTargetGroups.contains(group);
    final contents = expanded
        ? Column(
            children: <Widget>[
              for (final resource in resources)
                _buildNodeTargetRow(
                  context,
                  resource,
                  reachableProductionNodeIds: reachableProductionNodeIds,
                ),
            ],
          )
        : const SizedBox(width: double.infinity);
    return Column(
      key: ValueKey<String>('resource-map-node-target-group-${group.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSidebarRowIsland(
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: forcedOpen
                ? null
                : () {
                    setState(() {
                      if (!_expandedNodeTargetGroups.add(group)) {
                        _expandedNodeTargetGroups.remove(group);
                      }
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      group.label,
                      style: TextStyle(
                        color: context.mapChrome.ink,
                        fontSize: ResourceMapPanelMetrics.optionLabel,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 170),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: context.mapChrome.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (MediaQuery.disableAnimationsOf(context))
          contents
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: contents,
          ),
      ],
    );
  }

  Widget _buildNodeTargetRow(
    BuildContext context,
    BdoResourceDefinition resource, {
    required Set<String> reachableProductionNodeIds,
  }) {
    final available = widget.dataset
        .workerNodesForResource(resource.id)
        .map((node) => node.id)
        .toSet()
        .intersection(reachableProductionNodeIds)
        .length;
    final count =
        _nodeNetworkPreferences.desiredResourceNodeCounts[resource.id] ?? 0;
    final selected = count > 0;
    final invalidSelection = selected && count > available;
    final availabilityLabel = available == 0
        ? 'No reachable node'
        : 'Maximum $available';
    return _buildSidebarRowIsland(
      selected: selected,
      child: Semantics(
        label:
            '${resource.name}, $available reachable worker nodes, '
            '${selected ? '$count requested' : 'not selected'}',
        child: InkWell(
          key: ValueKey<String>('resource-map-node-target-${resource.id}'),
          onTap: selected ? null : () => _changeNodeTarget(resource, 1),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: ResourceMapPanelMetrics.optionArtwork,
                  height: ResourceMapPanelMetrics.optionArtwork,
                  child: _buildResourceArtwork(
                    context,
                    resource,
                    size: ResourceMapPanelMetrics.optionArtwork,
                    fallbackIcon: _groupIconForResource(resource),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        resource.name,
                        style: TextStyle(
                          color: selected
                              ? context.mapChrome.accent
                              : context.mapChrome.ink,
                          fontSize: ResourceMapPanelMetrics.optionLabel,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (invalidSelection)
                        Text(
                          availabilityLabel,
                          key: ValueKey<String>(
                            'resource-map-node-target-availability-${resource.id}',
                          ),
                          style: TextStyle(
                            color: invalidSelection
                                ? context.mapChrome.error
                                : context.mapChrome.muted,
                            fontSize: ResourceMapPanelMetrics.secondary,
                            fontWeight: invalidSelection
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!selected)
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: MapQuietIconButton(
                      tooltip: 'Add ${resource.name}',
                      padding: EdgeInsets.zero,
                      onPressed: () => _changeNodeTarget(resource, 1),
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        size: 22,
                        color: context.mapChrome.accent,
                      ),
                    ),
                  )
                else
                  _NodeCountControl(
                    resourceId: resource.id,
                    resourceName: resource.name,
                    count: count,
                    canDecrease: count > 1,
                    canIncrease: count < available,
                    onRemove: () => _changeNodeTarget(resource, 0),
                    onDecrease: () => _changeNodeTarget(resource, count - 1),
                    onIncrease: () => _changeNodeTarget(resource, count + 1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeNetworkReviewPage(BuildContext context) {
    final result = _nodeNetworkResult;
    final plan = result?.plan;
    final diagnostics =
        result?.diagnostics ?? const <BdoNodeNetworkDiagnostic>[];
    // Informational search caveats stay in the optional route tooltip.
    final additionalDiagnostics = diagnostics
        .where(
          (diagnostic) =>
              plan?.usesScalableOptimization != true ||
              diagnostic.code !=
                  BdoNodeNetworkDiagnosticCode.scalableOptimizationUsed,
        )
        .toList(growable: false);
    final workerCapacity = _nodeNetworkWorkerCapacity?.assessment;
    final lodgingResult = _nodeNetworkLodgingPlan;
    final lodgingPlan = lodgingResult?.plan;
    final withinCombinedBudget = plan == null
        ? false
        : _nodePlanIsWithinCombinedBudget(plan);
    final capacityConfigured =
        _nodeNetworkPreferences.townWorkerCapacitiesByNodeId.isNotEmpty;
    return Column(
      key: const ValueKey<String>('resource-map-node-planner-review'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (plan == null || _nodeNetworkCalculating) ...[
          NetworkCpReview(
            budgetController: _nodeBudgetController,
            onCommitBudget: () => _commitNodeBudget(rebuildPlan: true),
          ),
          const SizedBox(height: 8),
        ],
        if (_nodeNetworkCalculating)
          const Padding(
            padding: EdgeInsets.all(12),
            child: _NodeNetworkCalculating(),
          )
        else if (_nodeNetworkCalculationError case final error?)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NodePlannerNotice(
                icon: Icons.error_outline_rounded,
                message: error,
                color: context.mapChrome.error,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey<String>('resource-map-retry-node-network'),
                onPressed: _rebuildNodeNetworkPlan,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          )
        else if (plan == null)
          Flexible(
            child: _buildNodeNetworkDiagnostics(
              diagnostics,
              emptyMessage:
                  !diagnostics.any(
                    (diagnostic) =>
                        diagnostic.severity ==
                        BdoNodeNetworkDiagnosticSeverity.error,
                  )
                  ? 'No connected route'
                  : null,
            ),
          )
        else ...<Widget>[
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: <Widget>[
                _buildNodePlanSummary(plan),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: MapQuietTooltip(
                    message: plan.usesScalableOptimization
                        ? 'Best route found; lowest CP is not guaranteed.'
                        : 'Show route',
                    child: OutlinedButton.icon(
                      onPressed: () => _fitNodeNetworkPlan(plan),
                      icon: const Icon(Icons.map_outlined, size: 17),
                      label: const Text('Show route'),
                    ),
                  ),
                ),
                if (additionalDiagnostics.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  _buildNodeNetworkDiagnostics(additionalDiagnostics),
                ],
                if (widget.workerEconomics != null &&
                    widget.lodgingDataset != null) ...<Widget>[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const ValueKey<String>(
                      'resource-map-node-review-worker-capacity',
                    ),
                    onPressed: _openWorkerCapacitySettings,
                    icon: Icon(
                      !capacityConfigured
                          ? Icons.person_add_alt_1_rounded
                          : workerCapacity?.isCoveredByCurrentCapacity == true
                          ? Icons.groups_2_outlined
                          : Icons.bed_outlined,
                      size: 16,
                    ),
                    label: const Text('Extra lodging'),
                  ),
                  if (lodgingResult != null && lodgingPlan == null)
                    _NodePlannerInlineStatus(
                      icon: Icons.error_outline_rounded,
                      message:
                          lodgingResult.diagnostics.firstOrNull?.message ??
                          'A complete lodging plan could not be built.',
                      color: context.mapChrome.error,
                    )
                  else if (lodgingPlan != null &&
                      lodgingPlan.requiredWorkerSlots > 0) ...<Widget>[
                    for (final townPlan in lodgingPlan.townPlans)
                      _DetailLink(
                        key: ValueKey<String>(
                          'resource-map-review-lodging-town-'
                          '${townPlan.townNodeId}',
                        ),
                        icon: Icons.location_city_outlined,
                        title:
                            widget
                                .lodgingDataset
                                ?.townsByNodeId[townPlan.townNodeId]
                                ?.name ??
                            townPlan.townNodeId,
                        subtitle:
                            '${townPlan.newlyRequiredHouseIds.length} houses '
                            '· ${townPlan.incrementalContributionPoints} CP',
                        onTap: () => _showLodgingTownPlan(townPlan),
                      ),
                  ],
                  const SizedBox(height: 6),
                ],
                _buildNodePlanTargets(context, plan),
                const SizedBox(height: 8),
                _buildNodeChangeSection(
                  title: 'Connect',
                  icon: Icons.add_circle_outline_rounded,
                  color: const Color(0xFF55D69A),
                  nodeIds: plan.changeSet.connectNodeIds,
                  emptyLabel: 'Nothing new to connect',
                ),
                _buildNodeChangeSection(
                  title: 'Keep',
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFFE1C66F),
                  nodeIds: plan.changeSet.retainedNodeIds,
                  emptyLabel: 'No saved nodes are shared yet',
                ),
                _buildNodeChangeSection(
                  title: 'Remove',
                  icon: Icons.remove_circle_outline_rounded,
                  color: const Color(0xFFFF766A),
                  nodeIds: plan.changeSet.disconnectNodeIds,
                  emptyLabel: 'Nothing needs disconnecting',
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          NetworkReviewActionShelf(
            key: const ValueKey('resource-map-review-action-shelf'),
            child: FilledButton.icon(
              key: const ValueKey<String>(
                'resource-map-save-current-node-network',
              ),
              onPressed: withinCombinedBudget ? _saveProposedNodeNetwork : null,
              icon: const Icon(Icons.bookmark_added_outlined, size: 18),
              label: Text(
                withinCombinedBudget ? 'Save as current' : 'Increase CP limit',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkerIncomeAtlasPage(BuildContext context) {
    final summary = _rawSaleNetworkIncome == null
        ? null
        : _rawSalePortfolioSummary;
    final plan = _rawSaleNetworkPlan;
    final hourly =
        (summary == null
            ? 0.0
            : _nodeNetworkPreferences.useObservedTradeVolume
            ? summary.liquidityAdjustedNetSilverPerOnlineHour
            : summary.netSilverPerOnlineHour) +
        _activeRoyalWorkshopIncomeEstimate.netSilverPerOnlineHour;
    final remainingCp = math.max(
      0,
      _nodeNetworkPreferences.contributionPointBudget -
          _contributionPointsForNodeIds(
            _nodeNetworkPreferences.currentNodeIds,
          ) -
          _activeRoyalWorkshopReservedContributionPoints,
    );
    final lodgingResult = _rawSaleLodgingPlan;
    final lodgingPlan = lodgingResult?.plan;
    return SingleChildScrollView(
      key: const ValueKey<String>('resource-map-market-value-page'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResourceMapPill(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMarketFailure(),
                if (_marketValueCalculating)
                  Semantics(
                    key: const ValueKey<String>(
                      'resource-map-worker-income-calculating',
                    ),
                    liveRegion: true,
                    label: 'Updating worker income',
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                Row(
                  children: [
                    const ResourceMapArtworkMount(
                      size: 40,
                      child: ResourceMapMenuArtwork(
                        kind: ResourceMapMenuArtworkKind.income,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Tooltip(
                        message:
                            'Estimated net silver per online hour. Node sales include market tax; Royal Workshops use your recorded net values.'
                            '${_rawSaleWorkerCapacity == null ? '' : '\nWorker capacity is included in the route calculation.'}',
                        child: Text(
                          '${_formatMarketValueSignal(hourly)} / hour',
                          key: const ValueKey<String>(
                            'resource-map-worker-income-total-hourly',
                          ),
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 16, color: context.mapChrome.softOutline),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (plan case final network?) ...[
                      OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'resource-map-fit-recommended-value-network',
                        ),
                        onPressed: network.routeNodeIds.isEmpty
                            ? null
                            : () => _fitRawSaleNetworkPlan(network),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Show route'),
                      ),
                      FilledButton.icon(
                        key: const ValueKey<String>(
                          'resource-map-add-recommended-value-network',
                        ),
                        onPressed: network.addedNodeIds.isEmpty
                            ? null
                            : _addRecommendedRawSaleNetwork,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Update network'),
                      ),
                    ],
                    TextButton.icon(
                      key: const ValueKey<String>(
                        'resource-map-worker-capacity-settings',
                      ),
                      onPressed: _openWorkerCapacitySettings,
                      icon: const Icon(Icons.home_work_outlined, size: 18),
                      label: const Text('Extra lodging'),
                    ),
                    if (_royalWorkshopEnabled &&
                        _nodeNetworkPreferences
                            .royalWorkshopPlan
                            .accessInvested)
                      TextButton.icon(
                        key: const ValueKey<String>(
                          'resource-map-worker-income-royal-workshop',
                        ),
                        onPressed: _openRoyalWorkshop,
                        icon: const Icon(
                          Icons.account_balance_rounded,
                          size: 18,
                        ),
                        label: const Text('Royal Workshops'),
                      ),
                    TextButton.icon(
                      key: const ValueKey<String>(
                        'resource-map-toggle-market-node-details',
                      ),
                      onPressed: () => setState(
                        () => _marketValueDetailsExpanded =
                            !_marketValueDetailsExpanded,
                      ),
                      icon: Icon(
                        _marketValueDetailsExpanded
                            ? Icons.expand_less_rounded
                            : Icons.list_alt_rounded,
                        size: 18,
                      ),
                      label: const Text('Nodes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: ResourceMapPanelMetrics.optionGap),
          ..._buildWorkerIncomeAtlasLodging(
            lodgingResult: lodgingResult,
            lodgingPlan: lodgingPlan,
            lodgingCp: lodgingPlan?.totalIncrementalContributionPoints ?? 0,
            newLodgingHouseCount:
                lodgingPlan?.newlyRequiredHouseIds.length ?? 0,
          ),
          if (_marketValueDetailsExpanded)
            _buildWorkerIncomeAtlasNodeDetails(
              context,
              result: _workerIncomeRecommendation,
              remainingCp: remainingCp,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildWorkerIncomeAtlasLodging({
    required BdoLodgingNetworkPlanningResult? lodgingResult,
    required BdoLodgingNetworkPlan? lodgingPlan,
    required int lodgingCp,
    required int newLodgingHouseCount,
  }) {
    if (lodgingResult == null) {
      return const <Widget>[];
    }
    if (lodgingPlan == null) {
      return <Widget>[
        const SizedBox(height: 8),
        _WorkerIncomeNotice(
          icon: Icons.warning_amber_rounded,
          message: 'No lodging plan available.',
          color: context.mapChrome.error,
        ),
      ];
    }
    if (lodgingPlan.requiredWorkerSlots <= 0) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: 5),
      Align(
        alignment: Alignment.centerLeft,
        child: ResourceMapPill(
          child: TextButton.icon(
            key: const ValueKey<String>(
              'resource-map-toggle-worker-lodging-details',
            ),
            onPressed: () => setState(
              () => _workerLodgingDetailsExpanded =
                  !_workerLodgingDetailsExpanded,
            ),
            icon: Icon(
              _workerLodgingDetailsExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 18,
            ),
            label: const Text('Lodging'),
          ),
        ),
      ),
      if (_workerLodgingDetailsExpanded) ...<Widget>[
        const SizedBox(height: 3),
        for (final townPlan in lodgingPlan.townPlans)
          _WorkerIncomeTownLink(
            key: ValueKey<String>(
              'resource-map-income-lodging-town-${townPlan.townNodeId}',
            ),
            townName:
                widget
                    .lodgingDataset
                    ?.townsByNodeId[townPlan.townNodeId]
                    ?.name ??
                townPlan.townNodeId,
            summary: '',
            onTap: () => _showLodgingTownPlan(townPlan),
          ),
      ],
    ];
  }

  Widget _buildWorkerIncomeAtlasNodeDetails(
    BuildContext context, {
    required BdoWorkerIncomeResult? result,
    required int remainingCp,
  }) {
    final ranked = result?.ranked ?? const <BdoWorkerIncomeNodeEvaluation>[];

    final rankingMenuWidth = readableSelectMenuWidth(context, const <String>[
      'Most silver per online hour',
      'Most silver for all CP used',
      'Most silver for new CP',
      'Use measured market sales',
      'Allow missing prices',
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ResourceMapPill(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              PopupMenuButton<_MarketValueMenuAction>(
                key: const ValueKey<String>(
                  'resource-map-market-value-ranking-basis',
                ),
                tooltip: _marketValueStatusTooltip,
                position: PopupMenuPosition.under,
                constraints: BoxConstraints.tightFor(width: rankingMenuWidth),
                onSelected: _handleMarketValueMenuAction,
                itemBuilder: (context) =>
                    <PopupMenuEntry<_MarketValueMenuAction>>[
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-basis-highest',
                        ),
                        value: _MarketValueMenuAction.highestBasket,
                        checked:
                            _workerIncomeRankingBasis ==
                            BdoWorkerIncomeRankingBasis.netSilverPerOnlineHour,
                        child: const Text('Most silver per online hour'),
                      ),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-basis-total-cp',
                        ),
                        value: _MarketValueMenuAction.perMinimumCp,
                        checked:
                            _workerIncomeRankingBasis ==
                            BdoWorkerIncomeRankingBasis
                                .netSilverPerTotalContributionPointHour,
                        child: const Text('Most silver for all CP used'),
                      ),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-basis-added-cp',
                        ),
                        value: _MarketValueMenuAction.perAddedCp,
                        checked:
                            _workerIncomeRankingBasis ==
                            BdoWorkerIncomeRankingBasis
                                .netSilverPerAddedContributionPointHour,
                        child: const Text('Most silver for new CP'),
                      ),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-stock-toggle',
                        ),
                        value: _MarketValueMenuAction.stockCompetition,
                        checked: _nodeNetworkPreferences.useObservedTradeVolume,
                        child: const Text('Use measured market sales'),
                      ),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-partial-toggle',
                        ),
                        value: _MarketValueMenuAction.partialPrices,
                        checked: _marketValueAllowPartialPrices,
                        child: const Text('Allow missing prices'),
                      ),
                    ],
                child: SizedBox(
                  width: 90,
                  child: _WorkerIncomeMenuButton(
                    icon: Icons.sort_rounded,
                    label: 'Sort',
                  ),
                ),
              ),
              if (widget.onRefreshMarketEvidence != null)
                OutlinedButton.icon(
                  key: const ValueKey<String>(
                    'resource-map-refresh-market-value',
                  ),
                  onPressed: _marketValueRefreshing
                      ? null
                      : _refreshMarketValueEvidence,
                  icon: _marketValueRefreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    _marketValueRefreshing
                        ? 'Refreshing prices'
                        : 'Refresh prices',
                  ),
                ),
            ],
          ),
        ),
        if (ranked.isEmpty)
          _WorkerIncomeEmptyState(
            hasEvidence: widget.marketOutputEvidenceByResourceId.values.any(
              (output) =>
                  output.currentUnitPrice != null &&
                  output.currentUnitPrice! > 0,
            ),
            excludedCount: result?.excluded.length ?? 0,
          )
        else ...<Widget>[
          const SizedBox(height: 8),
          ListView.separated(
            key: const ValueKey<String>('resource-map-market-value-results'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: ranked.length,
            separatorBuilder: (_, _) => const SizedBox.shrink(),
            itemBuilder: (context, index) =>
                _buildWorkerIncomeAtlasNodeRow(ranked[index]),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkerIncomeAtlasNodeRow(
    BdoWorkerIncomeNodeEvaluation recommendation,
  ) {
    final hourly = _displayedWorkerIncomeHourly(recommendation);
    final selected =
        _selectedMarketValuePath?.targetNodeId == recommendation.nodeId;
    return _buildSidebarRowIsland(
      selected: selected,
      child: InkWell(
        key: ValueKey<String>(
          'resource-map-market-value-node-${recommendation.nodeId}',
        ),
        onTap: () => _selectMarketValueNode(recommendation.nodeId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  recommendation.nodeName,
                  style: TextStyle(
                    color: context.mapChrome.ink,
                    fontSize: ResourceMapPanelMetrics.optionLabel,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatMarketValueSignal(hourly)}/h',
                style: TextStyle(
                  color: context.mapChrome.text,
                  fontSize: ResourceMapPanelMetrics.primary,
                ),
              ),
              Icon(
                selected ? Icons.check_rounded : Icons.chevron_right_rounded,
                size: 18,
                color: context.mapChrome.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkerIncomeRecommendationPage(BuildContext context) =>
      _buildWorkerIncomeAtlasPage(context);

  double _displayedWorkerIncomeHourly(
    BdoWorkerIncomeNodeEvaluation evaluation,
  ) {
    return (_nodeNetworkPreferences.useObservedTradeVolume
            ? evaluation.liquidityAdjustedNetSilverPerOnlineHour
            : evaluation.netSilverPerOnlineHour) ??
        0;
  }

  Widget _buildMarketValueRecommendationPage(BuildContext context) {
    if (widget.workerEconomics != null) {
      return _buildWorkerIncomeRecommendationPage(context);
    }
    final ranked =
        _marketValueRecommendation?.ranked ??
        const <MarketValueNodeEvaluation>[];
    final rankingMenuWidth = readableSelectMenuWidth(context, const [
      'Highest sale value',
      'Value / total CP',
      'Value / added CP',
      'Prefer lower listed stock',
      'Include nodes with missing prices',
    ]);
    return SingleChildScrollView(
      key: const ValueKey<String>('resource-map-market-value-page'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMarketFailure(),
          if (_marketValueCalculating)
            const LinearProgressIndicator(minHeight: 2),
          ResourceMapPill(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SizedBox(
                  width: 90,
                  child: PopupMenuButton<_MarketValueMenuAction>(
                    key: const ValueKey<String>(
                      'resource-map-market-value-ranking-basis',
                    ),
                    tooltip: _marketValueStatusTooltip,
                    position: PopupMenuPosition.under,
                    constraints: BoxConstraints.tightFor(
                      width: rankingMenuWidth,
                    ),
                    onSelected: _handleMarketValueMenuAction,
                    itemBuilder: (context) => <PopupMenuEntry<_MarketValueMenuAction>>[
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-basis-highest',
                        ),
                        value: _MarketValueMenuAction.highestBasket,
                        checked:
                            _marketValueRankingBasis ==
                            MarketValueRankingBasis.netUnitBasketValue,
                        child: const Text('Highest sale value'),
                      ),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-basis-total-cp',
                        ),
                        value: _MarketValueMenuAction.perMinimumCp,
                        checked:
                            _marketValueRankingBasis ==
                            MarketValueRankingBasis
                                .netUnitBasketValuePerMinimumContributionPoint,
                        child: const Text('Value / total CP'),
                      ),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-basis-added-cp',
                        ),
                        value: _MarketValueMenuAction.perAddedCp,
                        checked:
                            _marketValueRankingBasis ==
                            MarketValueRankingBasis
                                .netUnitBasketValuePerIncrementalContributionPoint,
                        child: const Text('Value / added CP'),
                      ),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-stock-toggle',
                        ),
                        value: _MarketValueMenuAction.stockCompetition,
                        checked: _marketValueUseStockCompetition,
                        child: const Text('Prefer lower listed stock'),
                      ),
                      CheckedPopupMenuItem<_MarketValueMenuAction>(
                        key: const ValueKey<String>(
                          'resource-map-market-value-partial-toggle',
                        ),
                        value: _MarketValueMenuAction.partialPrices,
                        checked: _marketValueAllowPartialPrices,
                        child: const Text('Include nodes with missing prices'),
                      ),
                    ],
                    child: const _WorkerIncomeMenuButton(
                      icon: Icons.sort_rounded,
                      label: 'Sort',
                    ),
                  ),
                ),
                if (widget.onRefreshMarketEvidence != null)
                  OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'resource-map-refresh-market-value',
                    ),
                    onPressed: _marketValueRefreshing
                        ? null
                        : _refreshMarketValueEvidence,
                    icon: _marketValueRefreshing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                if (_rawSaleNetworkPlan case final plan?) ...[
                  OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'resource-map-fit-recommended-value-network',
                    ),
                    onPressed: plan.routeNodeIds.isEmpty
                        ? null
                        : () => _fitRawSaleNetworkPlan(plan),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Show route'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey<String>(
                      'resource-map-add-recommended-value-network',
                    ),
                    onPressed: plan.addedNodeIds.isEmpty
                        ? null
                        : _addRecommendedRawSaleNetwork,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('Update network'),
                  ),
                ],
                if (_selectedMarketValuePath != null) ...[
                  TextButton.icon(
                    key: const ValueKey<String>(
                      'resource-map-show-recommended-value-network',
                    ),
                    onPressed: _showRecommendedRawSaleNetwork,
                    icon: const Icon(Icons.auto_graph_rounded, size: 18),
                    label: const Text('Recommended'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey<String>(
                      'resource-map-add-market-route-to-current',
                    ),
                    onPressed: _addSelectedMarketValueRoute,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Add route'),
                  ),
                ],
                TextButton.icon(
                  key: const ValueKey<String>(
                    'resource-map-toggle-market-node-details',
                  ),
                  onPressed: () => setState(
                    () => _marketValueDetailsExpanded =
                        !_marketValueDetailsExpanded,
                  ),
                  icon: const Icon(Icons.list_alt_rounded, size: 18),
                  label: const Text('Nodes'),
                ),
              ],
            ),
          ),
          const SizedBox(height: ResourceMapPanelMetrics.optionGap),
          if (_marketValueDetailsExpanded)
            ListView.separated(
              key: const ValueKey<String>('resource-map-market-value-results'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: ranked.length,
              separatorBuilder: (_, _) => const SizedBox.shrink(),
              itemBuilder: (context, index) {
                final recommendation = ranked[index];
                return _buildSidebarRowIsland(
                  child: Tooltip(
                    message:
                        'Raw sale value; worker time and yield are not included.\n${_marketValueScoreSuffix(recommendation)}',
                    child: InkWell(
                      key: ValueKey<String>(
                        'resource-map-market-value-node-${recommendation.nodeId}',
                      ),
                      onTap: () =>
                          _selectMarketValueRecommendation(recommendation),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                recommendation.nodeName,
                                style: TextStyle(
                                  fontSize: ResourceMapPanelMetrics.optionLabel,
                                  height: 1.12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatMarketValueSignal(
                                recommendation.rankingScore ?? 0,
                              ),
                              style: TextStyle(
                                fontSize: ResourceMapPanelMetrics.primary,
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String get _marketValueStatusTooltip => <String>[
    _marketValueMenuLabel,
    if (_marketValueOverBudgetCount > 0)
      '$_marketValueOverBudgetCount routes exceed the available CP.',
    ?_marketValueMessage,
    ?_nodeNetworkSaveMessage,
    if (widget.marketFetchedAt case final fetched?)
      'Updated ${_formatMapTimestamp(fetched)}',
  ].join('\n');

  Widget _buildMarketFailure() {
    final message = _marketValueMessage;
    if (message == null ||
        !(message.startsWith('Market data could not') ||
            message.startsWith('The worker route could not'))) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: message,
      child: Text(
        'Update failed',
        style: TextStyle(
          color: context.mapChrome.error,
          fontSize: ResourceMapPanelMetrics.secondary,
        ),
      ),
    );
  }

  String _marketValueScoreSuffix(MarketValueNodeEvaluation recommendation) {
    return switch (_marketValueRankingBasis) {
      MarketValueRankingBasis.netUnitBasketValue => 'raw-sale value',
      MarketValueRankingBasis.netUnitBasketValuePerMinimumContributionPoint =>
        'per total CP',
      MarketValueRankingBasis
          .netUnitBasketValuePerIncrementalContributionPoint =>
        recommendation.contributionPointsUsedForRanking == 0
            ? 'already connected'
            : 'per added CP',
    };
  }

  Widget _buildNodePlanSummary(BdoNodeNetworkPlan plan) {
    final keptCp = _contributionPointsForNodeIds(
      plan.changeSet.retainedNodeIds,
    );
    return NetworkCpReview(
      budgetController: _nodeBudgetController,
      onCommitBudget: () => _commitNodeBudget(rebuildPlan: true),
      breakdown: NetworkCpBreakdown(
        key: const ValueKey<String>('resource-map-route-cp-breakdown'),
        limit: plan.contributionPointBudget,
        keptNodes: keptCp,
        newNodes: plan.totalContributionPoints - keptCp,
        lodgingHouses:
            _nodeNetworkLodgingPlan?.plan?.totalIncrementalContributionPoints ??
            0,
        royalWorkshops: _activeRoyalWorkshopReservedContributionPoints,
      ),
    );
  }

  Widget _buildNodePlanTargets(BuildContext context, BdoNodeNetworkPlan plan) {
    final reachableProductionNodeIds = _reachableWorkerProductionNodeIds();
    int availableNodeCount(BdoResourceDefinition resource) => widget.dataset
        .workerNodesForResource(resource.id)
        .map((node) => node.id)
        .toSet()
        .intersection(reachableProductionNodeIds)
        .length;
    return _NodePlanSection(
      title: 'Materials',
      icon: Icons.inventory_2_outlined,
      color: context.mapChrome.primary,
      children: <Widget>[
        for (final entry in plan.requestedNodeCountByResource.entries)
          if (widget.dataset.resourcesById[entry.key] case final resource?)
            Container(
              key: ValueKey<String>(
                'resource-map-review-material-${resource.id}',
              ),
              padding: const EdgeInsets.fromLTRB(2, 4, 0, 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.mapChrome.softOutline),
                ),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox.square(
                    dimension: ResourceMapPanelMetrics.artwork,
                    child: _buildResourceArtwork(
                      context,
                      resource,
                      size: ResourceMapPanelMetrics.artwork,
                      fallbackIcon: _groupIconForResource(resource),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          resource.name,
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _NodeCountControl(
                    resourceId: 'review-${resource.id}',
                    resourceName: resource.name,
                    count: entry.value,
                    canDecrease: entry.value > 1,
                    canIncrease: entry.value < availableNodeCount(resource),
                    onRemove: () => _changeRecipeReviewNodeTarget(resource, 0),
                    onDecrease: () => _changeRecipeReviewNodeTarget(
                      resource,
                      entry.value - 1,
                    ),
                    onIncrease: () => _changeRecipeReviewNodeTarget(
                      resource,
                      entry.value + 1,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildNodeChangeSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> nodeIds,
    required String emptyLabel,
  }) {
    if (nodeIds.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: PageStorageKey('resource-map-node-change-$title'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      dense: true,
      minTileHeight: 36,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: context.mapChrome.ink,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
      children: [
        for (final id in nodeIds)
          if (widget.dataset.workerNodesById[id] case final node?)
            _NodeChangeRow(node: node, color: color),
      ],
    );
  }

  Widget _buildNodeNetworkDiagnostics(
    List<BdoNodeNetworkDiagnostic> diagnostics, {
    String? emptyMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (emptyMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              emptyMessage,
              style: TextStyle(
                color: context.mapChrome.text,
                fontSize: ResourceMapPanelMetrics.secondary,
                height: 1.35,
              ),
            ),
          ),
        for (final diagnostic in diagnostics.where(
          (entry) => entry.severity == BdoNodeNetworkDiagnosticSeverity.error,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _NodePlannerNotice(
              icon:
                  diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error
                  ? Icons.error_outline_rounded
                  : diagnostic.severity ==
                        BdoNodeNetworkDiagnosticSeverity.warning
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              message: diagnostic.message,
              color:
                  diagnostic.severity == BdoNodeNetworkDiagnosticSeverity.error
                  ? context.mapChrome.error
                  : diagnostic.severity ==
                        BdoNodeNetworkDiagnosticSeverity.warning
                  ? context.mapChrome.warning
                  : context.mapChrome.primary,
            ),
          ),
      ],
    );
  }

  List<BdoResourceDefinition> _filteredNodeTargetResources(
    Set<String> reachableProductionNodeIds,
  ) {
    final query = _nodeTargetSearchController.text.trim().toLowerCase();
    final currentCounts = _currentProductionCountsByResourceId();
    final resources = widget.dataset.resources
        .where((resource) {
          final selected = _nodeNetworkPreferences.desiredResourceNodeCounts
              .containsKey(resource.id);
          final hasReachableNode = widget.dataset
              .workerNodesForResource(resource.id)
              .any((node) => reachableProductionNodeIds.contains(node.id));
          if (!hasReachableNode && !selected) {
            return false;
          }
          if (_nodeTargetView == _NodeTargetView.selected && !selected) {
            return false;
          }
          if (_nodeTargetView == _NodeTargetView.current &&
              !currentCounts.containsKey(resource.id)) {
            return false;
          }
          if (_nodeTargetView == _NodeTargetView.favorites &&
              !_favoriteResourceIds.contains(resource.id)) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return <String>[
            resource.name,
            resource.category,
            ...resource.aliases,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList(growable: false);
    resources.sort((left, right) {
      final leftSelected = _nodeNetworkPreferences.desiredResourceNodeCounts
          .containsKey(left.id);
      final rightSelected = _nodeNetworkPreferences.desiredResourceNodeCounts
          .containsKey(right.id);
      if (leftSelected != rightSelected) {
        return leftSelected ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return resources;
  }

  Set<String> _reachableWorkerProductionNodeIds() {
    final nodesById = widget.dataset.workerNodesById;
    final adjacency = <String, Set<String>>{
      for (final node in widget.dataset.workerNodes) node.id: <String>{},
    };
    for (final node in widget.dataset.workerNodes) {
      for (final linkedId in node.linkIds) {
        if (linkedId == node.id || !nodesById.containsKey(linkedId)) {
          continue;
        }
        adjacency[node.id]!.add(linkedId);
        adjacency[linkedId]!.add(node.id);
      }
    }

    bool validRoot(BdoWorkerNode node) =>
        node.contributionPoints == 0 &&
        (node.nodeType == 'City' || node.nodeType == 'Town');

    final configuredRootIds = _effectiveNetworkRootNodeIds;
    final rootIds = configuredRootIds == null
        ? <String>{
            for (final node in widget.dataset.workerNodes)
              if (validRoot(node)) node.id,
          }
        : <String>{
            for (final id in configuredRootIds)
              if (nodesById[id] case final node?)
                if (validRoot(node)) id,
          };
    final reachableBase = <String>{...rootIds};
    final queue = rootIds.toList(growable: true)..sort();
    for (var cursor = 0; cursor < queue.length; cursor += 1) {
      final currentId = queue[cursor];
      final neighbors = adjacency[currentId]?.toList() ?? const <String>[];
      neighbors.sort();
      for (final neighborId in neighbors) {
        if (reachableBase.contains(neighborId)) {
          continue;
        }
        final neighbor = nodesById[neighborId]!;
        if (neighbor.isProductionNode && !rootIds.contains(neighborId)) {
          continue;
        }
        reachableBase.add(neighborId);
        queue.add(neighborId);
      }
    }

    return <String>{
      for (final node in widget.dataset.workerNodes)
        if (node.isResourceNode &&
            (reachableBase.contains(node.id) ||
                (adjacency[node.id]?.any(reachableBase.contains) ?? false)))
          node.id,
    };
  }

  _NodeTargetGroup _nodeTargetGroupFor(BdoResourceDefinition resource) {
    final nodes = widget.dataset
        .workerNodesForResource(resource.id)
        .toList(growable: false);
    if (resource.section == BdoResourceSection.seafoodMarine ||
        nodes.any((node) => node.activity == BdoWorkerActivity.fishing)) {
      return _NodeTargetGroup.fishMarine;
    }
    final folded = '${resource.name} ${resource.category}'.toLowerCase();
    if (resource.section == BdoResourceSection.plantsWood &&
        RegExp(
          r'\b(timber|log|sap|tree|wood|branch|bark|plywood)\b',
        ).hasMatch(folded)) {
      return _NodeTargetGroup.woodSap;
    }
    return switch (resource.section) {
      BdoResourceSection.plantsWood => _NodeTargetGroup.cropsPlants,
      BdoResourceSection.oresMinerals => _NodeTargetGroup.oresMinerals,
      BdoResourceSection.mushrooms => _NodeTargetGroup.mushrooms,
      BdoResourceSection.meat ||
      BdoResourceSection.bloodHides => _NodeTargetGroup.animalProducts,
      BdoResourceSection.seafoodMarine => _NodeTargetGroup.fishMarine,
      BdoResourceSection.other => _NodeTargetGroup.other,
    };
  }

  int _contributionPointsForNodeIds(Iterable<String> nodeIds) {
    return nodeIds.fold<int>(
      0,
      (total, id) =>
          total + (widget.dataset.workerNodesById[id]?.contributionPoints ?? 0),
    );
  }

  IconData _groupIconForResource(BdoResourceDefinition resource) =>
      _nodeTargetGroupFor(resource).icon;

  Future<void> _openNodeRootPicker() async {
    final verifiedRootIds = widget.workerEconomics
        ?.verifiedFreeNetworkRootNodeIds(widget.dataset);
    final roots =
        widget.dataset.workerNodes
            .where(
              (node) =>
                  (node.nodeType == 'City' || node.nodeType == 'Town') &&
                  node.contributionPoints == 0 &&
                  (verifiedRootIds == null ||
                      verifiedRootIds.contains(node.id)) &&
                  node.siteName.trim().toLowerCase() != 'unknown',
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byRegion = left.region.compareTo(right.region);
            return byRegion != 0
                ? byRegion
                : left.siteName.compareTo(right.siteName);
          });
    final current = _nodeNetworkPreferences.rootNodeIds;
    final selection = await showDialog<_NodeRootSelection>(
      context: context,
      builder: (context) => _MapDialogScope(
        child: _NodeRootPickerDialog(
          roots: roots,
          initialUseAll: current == null,
          initialIds: current ?? roots.map((node) => node.id).toSet(),
        ),
      ),
    );
    if (!mounted || selection == null) {
      return;
    }
    _replaceNodeNetworkPreferences(
      selection.useAll
          ? _nodeNetworkPreferences.copyWith(useDefaultRootNodes: true)
          : _nodeNetworkPreferences.copyWith(rootNodeIds: selection.nodeIds),
    );
  }

  Widget _buildWorkerExplorerPage(BuildContext context) {
    return _buildSidebarPage(
      key: const ValueKey<String>('resource-map-worker-explorer'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SingleChildScrollView(child: _buildWorkerActivityPicker()),
    );
  }

  Widget _buildCompactExploreButton() {
    final style = FilledButton.styleFrom(
      backgroundColor: context.mapChrome.paperRaised,
      foregroundColor: context.mapChrome.primary,
      side: BorderSide(color: context.mapChrome.divider),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        FilledButton.tonalIcon(
          key: const ValueKey<String>('resource-map-compact-worker-network'),
          onPressed: _openWorkerOverview,
          icon: const Icon(Icons.account_tree_outlined, size: 17),
          label: const Text('Worker nodes'),
          style: style,
        ),
        FilledButton.tonalIcon(
          key: const ValueKey<String>('resource-map-compact-checklist'),
          onPressed: _openGatherChecklist,
          icon: const Icon(Icons.checklist_rounded, size: 17),
          label: const Text('To-do list'),
          style: style,
        ),
        FilledButton.tonalIcon(
          key: const ValueKey<String>('resource-map-compact-node-planner'),
          onPressed: _openNodeNetworkPlanner,
          icon: const Icon(Icons.route_outlined, size: 17),
          label: const Text('Add to planned network'),
          style: style,
        ),
        FilledButton.tonalIcon(
          key: const ValueKey<String>('resource-map-compact-invest-nodes'),
          onPressed: _toggleInvestNodeMode,
          icon: const Icon(Icons.bookmark_add_outlined, size: 17),
          label: const Text('Invest nodes'),
          style: style,
        ),
      ],
    );
  }

  Widget _buildCompactNodeNetworkPlanner(
    BuildContext context, {
    bool includeHeader = false,
  }) {
    final maximumHeight = (MediaQuery.sizeOf(context).height * .48)
        .clamp(260.0, 480.0)
        .toDouble();
    return Material(
      key: const ValueKey<String>('resource-map-compact-node-planner-sheet'),
      elevation: 18,
      shadowColor: const Color(0x4A17211F),
      color: context.mapChrome.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maximumHeight),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
              child: includeHeader
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildNodePlannerFloatingHeader(context, compact: true),
                        Divider(height: 1),
                        const SizedBox(height: 7),
                        Expanded(child: _buildNodeNetworkPlannerPage(context)),
                      ],
                    )
                  : _buildNodeNetworkPlannerPage(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactGatherChecklist(BuildContext context) {
    return Material(
      key: const ValueKey<String>('resource-map-compact-gather-checklist'),
      elevation: 18,
      shadowColor: Colors.black38,
      color: context.mapChrome.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 8, 13, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'To-do list',
                      style: TextStyle(
                        color: context.mapChrome.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  MapQuietIconButton(
                    key: const ValueKey<String>(
                      'resource-map-compact-checklist-back',
                    ),
                    tooltip: 'Back to $_backNavigationLabel',
                    onPressed: _navigateBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  ),
                ],
              ),
              Divider(height: 1),
              const SizedBox(height: 7),
              Expanded(child: _buildGatherChecklistContent(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactWorkerExplorer(BuildContext context) {
    return Material(
      key: const ValueKey<String>('resource-map-compact-worker-explorer'),
      elevation: 18,
      shadowColor: Colors.black38,
      color: context.mapChrome.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 6, 2),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        'Worker nodes',
                        style: TextStyle(
                          color: context.mapChrome.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  MapQuietIconButton(
                    key: const ValueKey<String>(
                      'resource-map-compact-worker-back',
                    ),
                    tooltip: 'Back to $_backNavigationLabel',
                    onPressed: _navigateBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                child: _buildWorkerActivityPicker(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactSearchPanel(
    BuildContext context, {
    required double resultsMaximumHeight,
  }) {
    final queryActive = _searchController.text.trim().isNotEmpty;
    final resultsOpen = queryActive && _searchResultsVisible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSearchField(context),
        if (resultsOpen) ...<Widget>[
          const SizedBox(height: 8),
          Material(
            elevation: 14,
            shadowColor: Colors.black38,
            color: context.mapChrome.paperRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(color: context.mapChrome.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildSearchResults(
              context,
              maximumHeight: resultsMaximumHeight,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final queryActive = _searchController.text.trim().isNotEmpty;
    return Material(
      key: const ValueKey<String>('resource-map-search-card'),
      elevation: _compactLayout ? 8 : 0,
      shadowColor: Colors.black38,
      color: _compactLayout
          ? context.mapChrome.paperRaised
          : context.mapChrome.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 46,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onChanged: _search,
          onTapAlwaysCalled: true,
          onTap: () {
            if (_searchController.text.trim().isNotEmpty) {
              _search(_searchController.text, showResults: true);
            }
          },
          onSubmitted: (_) => _submitSearch(),
          style: TextStyle(
            color: context.mapChrome.ink,
            fontSize: ResourceMapPanelMetrics.secondary,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: _mapSearchHintText,
            hintStyle: TextStyle(
              color: context.mapChrome.muted,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: IconTheme(
              data: IconThemeData(color: context.mapChrome.accent, size: 20),
              child: _buildMapSearchScopeMenu(context),
            ),
            suffixIcon: queryActive
                ? MapQuietIconButton(
                    tooltip: 'Clear search',
                    onPressed: _openMapHome,
                    icon: const Icon(Icons.close_rounded),
                  )
                : MapQuietTooltip(
                    message: 'Focus search (Ctrl+F)',
                    child: SizedBox(
                      width: 50,
                      child: Center(
                        child: Text(
                          'Ctrl F',
                          style: TextStyle(
                            color: context.mapChrome.muted,
                            fontSize: ResourceMapPanelMetrics.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 46,
              maxWidth: 50,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkerActivityPicker() {
    final selectedActivity = _workerActivityFilter;
    final activities = BdoWorkerActivity.values;
    int nodeCount(BdoWorkerActivity? activity) {
      return widget.dataset.workerNodes
          .where(
            (node) =>
                node.isResourceNode &&
                (activity == null || node.activity == activity),
          )
          .length;
    }

    return KeyedSubtree(
      key: const ValueKey<String>('resource-map-worker-activity-picker'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildActivityRow(
            key: const ValueKey<String>('resource-map-worker-activity-all'),
            label: 'All production',
            icon: const BdoNodeTypeImage(
              sourceIconType: 0,
              size: ResourceMapPanelMetrics.artwork,
            ),
            count: nodeCount(null),
            selected: _workerOverviewSelectionMade && selectedActivity == null,
            onSelected: () => _selectWorkerActivity(null),
          ),
          for (final activity in activities)
            _buildActivityRow(
              key: ValueKey<String>(
                'resource-map-worker-activity-${activity.name}',
              ),
              label: activity.label,
              icon: BdoWorkerActivityImage(
                activity: activity,
                size: ResourceMapPanelMetrics.artwork,
              ),
              count: nodeCount(activity),
              selected:
                  _workerOverviewSelectionMade && selectedActivity == activity,
              onSelected: () => _selectWorkerActivity(activity),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityRow({
    required Key key,
    required String label,
    required Widget icon,
    required int count,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return _buildSidebarRowIsland(
      selected: selected,
      child: Material(
        key: key,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: ResourceMapPanelMetrics.optionArtwork,
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: context.mapChrome.ink,
                      fontSize: ResourceMapPanelMetrics.optionLabel,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$count',
                  style: TextStyle(
                    color: selected
                        ? context.mapChrome.primary
                        : context.mapChrome.muted,
                    fontSize: ResourceMapPanelMetrics.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context, {
    bool constrained = true,
    double maximumHeight = 360,
    bool horizontal = false,
  }) {
    final query = _searchController.text.trim();
    final activityMatches = _workerActivitiesForQuery(query);
    if (_searchResults.isEmpty && activityMatches.isEmpty) {
      final noResults = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.search_off_rounded,
                  size: 18,
                  color: context.mapChrome.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No results',
                    style: TextStyle(color: context.mapChrome.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _clearSearchQuery,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Clear search'),
                ),
                TextButton.icon(
                  onPressed: _openWorkerOverview,
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: const Text('Worker nodes'),
                ),
              ],
            ),
          ],
        ),
      );
      return constrained
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maximumHeight),
              child: noResults,
            )
          : noResults;
    }
    final children = <Widget>[];
    final exactActivityQuery = activityMatches.any(
      (activity) => activity.label.toLowerCase() == query.toLowerCase(),
    );
    if (exactActivityQuery) {
      for (final activity in activityMatches.take(2)) {
        final nodeCount = widget.dataset.workerNodes
            .where((node) => node.isResourceNode && node.activity == activity)
            .length;
        children.add(
          _MapSearchResultTile(
            key: ValueKey<String>(
              'resource-map-search-activity-${activity.name}',
            ),
            leading: BdoWorkerActivityImage(activity: activity),
            title: activity.label,
            subtitle: '$nodeCount worker nodes',
            kindLabel: 'Activity',
            horizontal: horizontal,
            onTap: () => _selectWorkerActivity(activity),
          ),
        );
      }
    }
    for (final result in _searchResults.take(18)) {
      final workerNode = result.kind == BdoSearchKind.workerNode
          ? widget.dataset.workerNodesById[result.id]
          : null;
      children.add(
        _MapSearchResultTile(
          key: ValueKey<String>(
            'resource-map-search-result-${result.kind.name}-${result.id}',
          ),
          leading: _buildSearchResultArtwork(context, result),
          title: _friendlySearchResultTitle(result),
          subtitle: _friendlySearchResultSubtitle(result),
          kindLabel: _friendlySearchResultKind(result),
          horizontal: horizontal,
          selected: workerNode?.id == _selectedNodeId,
          trailing: _buildSearchFavorite(result),
          onTap: () => _selectSearchResult(result),
        ),
      );
    }
    if (!exactActivityQuery && activityMatches.isNotEmpty) {
      for (final activity in activityMatches.take(1)) {
        final nodeCount = widget.dataset.workerNodes
            .where((node) => node.isResourceNode && node.activity == activity)
            .length;
        children.add(
          _MapSearchResultTile(
            key: ValueKey<String>(
              'resource-map-search-activity-${activity.name}',
            ),
            leading: BdoWorkerActivityImage(activity: activity),
            title: activity.label,
            subtitle: '$nodeCount worker nodes',
            kindLabel: 'Activity',
            horizontal: horizontal,
            onTap: () => _selectWorkerActivity(activity),
          ),
        );
      }
    }

    final resultList = ListView(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      shrinkWrap: !horizontal,
      padding: horizontal
          ? const EdgeInsets.fromLTRB(18, 2, 18, 8)
          : const EdgeInsets.fromLTRB(2, 2, 2, 8),
      children: children,
    );
    return constrained
        ? ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maximumHeight),
            child: resultList,
          )
        : resultList;
  }

  Widget _buildSearchFavorite(
    BdoSearchResult result, {
    bool savedList = false,
  }) {
    return ResourceMapFavoriteButton(
      key: ValueKey<String>(
        'resource-map-${savedList ? 'saved' : 'search'}-favorite-${result.favoriteKey}',
      ),
      name: _friendlySearchResultTitle(result),
      saved: _favoriteResourceIds.contains(result.favoriteKey),
      onPressed: () => _toggleFavoriteKey(result.favoriteKey),
    );
  }

  Widget _buildSearchResultArtwork(
    BuildContext context,
    BdoSearchResult result,
  ) {
    final node = result.kind == BdoSearchKind.workerNode
        ? widget.dataset.workerNodesById[result.id]
        : null;
    final source = result.kind == BdoSearchKind.fieldSource
        ? widget.dataset.fieldSourcesById[result.fieldSourceId ?? result.id]
        : null;
    final resource = result.kind == BdoSearchKind.resource
        ? widget.dataset.resourcesById[result.id]
        : source == null
        ? null
        : widget.dataset.resourcesById[_preferredProductForFieldSource(
            source,
            preferredResourceId: result.resourceId,
          )?.resourceId];
    if (resource != null) {
      return _buildResourceArtwork(
        context,
        resource,
        size: ResourceMapPanelMetrics.artwork,
        fallbackIcon: source == null
            ? Icons.inventory_2_outlined
            : _iconForFieldSource(source),
      );
    }
    if (node != null) {
      return _buildWorkerNodeArtwork(
        node,
        size: ResourceMapPanelMetrics.artwork,
      );
    }
    return Icon(
      source != null
          ? _iconForFieldSource(source)
          : node == null
          ? _iconForSearchKind(result.kind)
          : _iconForWorkerNode(node),
      color: source != null
          ? context.mapChrome.primary
          : node == null
          ? _colorForSearchKind(context, result.kind)
          : _colorForWorkerNode(context, node),
      size: 30,
    );
  }

  String _friendlySearchResultTitle(BdoSearchResult result) {
    if (result.kind == BdoSearchKind.gatheringSpot &&
        result.title.endsWith(' Dairy Cows')) {
      return result.title.substring(
        0,
        result.title.length - ' Dairy Cows'.length,
      );
    }
    return result.title;
  }

  String _friendlySearchResultKind(BdoSearchResult result) {
    return switch (result.kind) {
      BdoSearchKind.resource => 'Item',
      BdoSearchKind.workerNode => 'Node',
      BdoSearchKind.gatheringSpot => 'Location',
      BdoSearchKind.gatheringRoute => 'Route',
      BdoSearchKind.fieldSource => switch (widget
          .dataset
          .fieldSourcesById[result.fieldSourceId ?? result.id]
          ?.category
          .toLowerCase()) {
        'animals' => 'Wildlife',
        final value when value?.contains('tree') ?? false => 'Tree',
        final value when value?.contains('plant') ?? false => 'Plant',
        final value when value?.contains('mushroom') ?? false => 'Mushroom',
        _ => 'Source',
      },
    };
  }

  String _friendlySearchResultSubtitle(BdoSearchResult result) {
    switch (result.kind) {
      case BdoSearchKind.fieldSource:
        return '';
      case BdoSearchKind.resource:
        final count = widget.dataset.workerNodesForResource(result.id).length;
        return count > 0
            ? '$count worker ${count == 1 ? 'node' : 'nodes'}'
            : '';
      case BdoSearchKind.gatheringSpot:
        return widget.dataset.gatheringSpotsById[result.id]?.region ?? '';
      case BdoSearchKind.gatheringRoute:
        return widget.dataset.gatheringRoutesById[result.id]?.region ?? '';
      case BdoSearchKind.workerNode:
        return widget.dataset.workerNodesById[result.id]?.region ?? '';
    }
  }

  Widget _buildZoomControls(BuildContext context, {required bool compact}) {
    void setZoom(double zoom) {
      if (_viewport.isEmpty) {
        return;
      }
      _cameraController.zoomAround(
        zoom: zoom,
        anchor: _viewport.center(Offset.zero),
        viewport: _viewport,
      );
    }

    void reset() {
      if (_viewport.isEmpty) {
        return;
      }
      _cameraController.reset(_viewport);
    }

    return ResourceMapZoomDock(
      key: const ValueKey<String>('resource-map-zoom-controls'),
      cameraController: _cameraController,
      onZoomChanged: setZoom,
      onShowFullWorld: reset,
    );
  }

  Widget _buildSelectedDetailsContent() {
    final vendor = _selectedVendor;
    final fieldSource = _selectedFieldSource;
    final resource = _selectedResourceId == null
        ? null
        : widget.dataset.resourcesById[_selectedResourceId!];
    final node = _selectedNodeId == null
        ? null
        : widget.dataset.workerNodesById[_selectedNodeId!];
    final spot = _selectedSpotId == null
        ? null
        : widget.dataset.gatheringSpotsById[_selectedSpotId!];
    final point = _selectedPointId == null
        ? null
        : widget.dataset.gatheringPointsById[_selectedPointId!];
    final route = _selectedRouteId == null
        ? null
        : widget.dataset.gatheringRoutesById[_selectedRouteId!];
    if (!_compactLayout) {
      return vendor != null
          ? _buildAtlasVendorDetails(vendor)
          : node != null
          ? _buildAtlasNodeDetails(node)
          : point != null
          ? _buildAtlasPointDetails(point)
          : spot != null
          ? _buildAtlasSpotDetails(spot)
          : route != null
          ? _buildAtlasRouteDetails(route)
          : fieldSource != null
          ? _buildAtlasFieldSourceDetails(
              fieldSource,
              selectedResource: resource,
            )
          : resource != null
          ? _buildAtlasResourceDetails(resource)
          : const SizedBox.shrink();
    }
    return node != null
        ? _buildNodeDetails(node)
        : point != null
        ? _buildPointDetails(point)
        : spot != null
        ? _buildSpotDetails(spot)
        : route != null
        ? _buildRouteDetails(route)
        : fieldSource != null
        ? _buildFieldSourceDetails(fieldSource, selectedResource: resource)
        : resource != null
        ? _buildResourceDetails(resource)
        : const SizedBox.shrink();
  }

  Widget _buildAtlasVendorDetails(BdoVendorNpc vendor) {
    final itemName = _vendorLookupItemName ?? 'Vendor item';
    final listing = _activeListingForVendor(vendor.id);
    final otherVendors = _activeVendorNpcs
        .where((candidate) => candidate.id != vendor.id)
        .toList(growable: false);
    return KeyedSubtree(
      key: ValueKey<String>('resource-map-vendor-details-${vendor.id}'),
      child: _buildAtlasInspectorLayout(
        identity: _buildAtlasInspectorIdentity(
          artwork: _buildVendorPortrait(
            context,
            vendor: vendor,
            size: 40,
            builder: widget.vendorPortraitBuilder,
            fallbackColor: context.mapChrome.primary,
          ),
          eyebrow: vendor.role,
          artworkSize: 40,
          title: vendor.name,
          meta: 'NPC seller',
        ),
        columns: <Widget>[
          _buildAtlasInspectorColumn(
            title: 'Sells',
            children: <Widget>[
              _buildAtlasInspectorLink(
                key: ValueKey<String>('resource-map-vendor-item-${vendor.id}'),
                leading: _buildVendorItemIcon(
                  context,
                  itemName,
                  ResourceMapPanelMetrics.artwork,
                ),
                title: itemName,
                value: listing == null
                    ? null
                    : '${_formatVendorSilver(listing.priceSilver)} silver',
              ),
            ],
          ),
          if (otherVendors.isNotEmpty)
            _buildAtlasInspectorColumn(
              title: 'Other sellers',
              count: otherVendors.length,
              children: otherVendors.isEmpty
                  ? <Widget>[_atlasQuietMessage('No other mapped seller')]
                  : <Widget>[
                      for (final other in otherVendors)
                        _buildAtlasInspectorLink(
                          key: ValueKey<String>(
                            'resource-map-other-vendor-${other.id}',
                          ),
                          leading: _buildVendorPortrait(
                            context,
                            vendor: other,
                            size: 40,
                            builder: widget.vendorPortraitBuilder,
                            fallbackColor: context.mapChrome.primary,
                          ),
                          title: other.name,
                          leadingWidth: 40,
                          subtitle: other.role,
                          onTap: () => _showVendorDetails(other.id),
                        ),
                    ],
            ),
        ],
      ),
    );
  }

  Widget _buildAtlasNodeDetails(BdoWorkerNode node) {
    final housingTown =
        widget.lodgingDataset?.townsByNodeId[node.id] ??
        (node.id == '1852'
            ? widget.lodgingDataset?.townsByNodeId['1853']
            : null);
    final parent = node.parentId == null
        ? null
        : widget.dataset.workerNodesById[node.parentId!];
    final childNodes =
        widget.dataset.workerNodes
            .where(
              (candidate) =>
                  candidate.isResourceNode && candidate.parentId == node.id,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byCp = left.contributionPoints.compareTo(
              right.contributionPoints,
            );
            return byCp != 0 ? byCp : left.name.compareTo(right.name);
          });
    final activity = node.isResourceNode ? node.activity : null;
    final quickPath = _selectedQuickNodePath?.targetNodeId == node.id
        ? _selectedQuickNodePath
        : _quickPathForNodeId(node.id);
    final outputLinks = <Widget>[
      for (final output in node.outputs)
        _buildAtlasInspectorLink(
          key: ValueKey<String>(
            'resource-map-node-output-${output.resourceId}',
          ),
          leading: _buildWorkerOutputArtwork(
            context,
            widget.dataset.resourcesById[output.resourceId],
            size: ResourceMapPanelMetrics.artwork,
          ),
          title: output.name,
          subtitle: '',
          onTap: widget.dataset.resourcesById[output.resourceId] == null
              ? null
              : () => _selectResourceFromDetails(
                  widget.dataset.resourcesById[output.resourceId]!,
                ),
        ),
      for (final child in childNodes)
        _buildAtlasInspectorLink(
          key: ValueKey<String>('resource-map-node-worker-site-${child.id}'),
          leading: _buildWorkerNodeArtwork(
            child,
            size: ResourceMapPanelMetrics.artwork,
          ),
          title: child.name,
          value: '${child.contributionPoints} CP',
          onTap: () => _selectNode(child, focus: true),
        ),
    ];
    final connectionLinks = <Widget>[
      if (parent != null)
        _buildAtlasInspectorLink(
          key: ValueKey<String>(
            'resource-map-node-connected-from-${parent.id}',
          ),
          leading: _buildWorkerNodeArtwork(
            parent,
            size: ResourceMapPanelMetrics.artwork,
          ),
          title: parent.siteName,
          subtitle: 'Connected from · ${parent.region}',
          onTap: () => _selectNode(parent),
        ),
      if (parent != null)
        _buildAtlasInspectorLink(
          key: const ValueKey<String>('resource-map-worker-path-toggle'),
          leading: Icon(
            _showConnections
                ? Icons.visibility_off_outlined
                : Icons.polyline_outlined,
            color: context.mapChrome.primary,
            size: 30,
          ),
          title: _showConnections ? 'Hide worker path' : 'Show worker path',
          onTap: () => setState(() {
            _showConnections = !_showConnections;
            if (_showConnections) _showWorkerNodes = true;
          }),
        ),
      if (quickPath != null && quickPath.connectNodeIds.isNotEmpty)
        _buildAtlasInspectorLink(
          key: const ValueKey<String>('resource-map-node-add-route'),
          leading: Icon(
            Icons.add_road_rounded,
            color: context.mapChrome.accent,
            size: 30,
          ),
          title: 'Save full path',
          value: '${quickPath.incrementalContributionPoints} CP',
          onTap: _addSelectedQuickNodeRoute,
        ),
      if (housingTown != null)
        _buildAtlasInspectorLink(
          key: ValueKey<String>('resource-map-town-open-houses'),
          leading: Icon(
            Icons.apartment_rounded,
            color: context.mapChrome.primary,
            size: 30,
          ),
          title: 'Houses',
          subtitle: '',
          onTap: () => _openHousingTown(housingTown.townNodeId),
        ),
    ];
    return KeyedSubtree(
      key: const ValueKey<String>('resource-map-node-quick-panel'),
      child: _buildAtlasInspectorLayout(
        identity: _buildAtlasInspectorIdentity(
          artwork: _buildWorkerNodeArtwork(
            node,
            size: ResourceMapPanelMetrics.artwork,
          ),
          eyebrow: activity?.label ?? node.nodeType,
          title: node.siteName,
          value: '${node.contributionPoints} CP',
          meta: <String>[
            if (node.region.isNotEmpty) node.region,
            '${node.contributionPoints} CP',
            if (node.workload?.trim().isNotEmpty == true) node.workload!,
            if (childNodes.isNotEmpty)
              '${childNodes.length} worker ${childNodes.length == 1 ? 'site' : 'sites'}',
          ].join(' · '),
        ),
        columns: <Widget>[
          if (outputLinks.isNotEmpty)
            _buildAtlasInspectorColumn(
              title: node.outputs.isNotEmpty ? 'Produces' : 'Work nodes',
              count: node.outputs.isNotEmpty ? null : childNodes.length,
              children: outputLinks,
            ),
          if (connectionLinks.isNotEmpty)
            _buildAtlasInspectorColumn(
              title: 'Actions',
              children: connectionLinks,
            ),
        ],
      ),
    );
  }

  Widget _buildAtlasResourceDetails(BdoResourceDefinition resource) {
    final fieldSources = widget.dataset
        .fieldSourcesForResource(resource.id)
        .toList(growable: false);
    final nodes = widget.dataset
        .workerNodesForResource(resource.id)
        .where((node) => node.isResourceNode)
        .toList(growable: false);
    final spots = widget.dataset
        .gatheringSpotsForResource(resource.id)
        .toList(growable: false);
    final routes = widget.dataset
        .gatheringRoutesForResource(resource.id)
        .toList(growable: false);
    final exactPointCount = widget.dataset
        .gatheringPointsForResource(resource.id)
        .length;
    final favorite = _favoriteResourceIds.contains(resource.id);
    final checklistEntry = _gatherChecklist.entries
        .where((entry) => entry.resourceId == resource.id)
        .firstOrNull;
    final manualLinks = <Widget>[
      for (final source in fieldSources)
        _buildAtlasInspectorLink(
          key: ValueKey<String>('resource-map-atlas-source-${source.id}'),
          leading: _buildGatheringToolIndicators(
            source.products.where(
              (product) => product.resourceId == resource.id,
            ),
          ),
          leadingWidth: _gatheringToolIndicatorWidth(
            source.products.where(
              (product) => product.resourceId == resource.id,
            ),
          ),
          title: source.name,
          onTap: () =>
              _selectFieldSource(source, preferredResourceId: resource.id),
        ),
      for (final spot in spots)
        _buildAtlasInspectorLink(
          key: ValueKey<String>('resource-map-atlas-spot-${spot.id}'),
          leading: Icon(
            Icons.location_on_rounded,
            color: context.mapChrome.primary,
            size: 19,
          ),
          title: _friendlyGatheringSpotName(spot),
          subtitle: spot.region,
          onTap: () => _selectSpot(spot, focus: true),
        ),
      for (final route in routes)
        _buildAtlasInspectorLink(
          key: ValueKey<String>('resource-map-atlas-route-${route.id}'),
          leading: Icon(
            Icons.route_rounded,
            color: context.mapChrome.primary,
            size: 19,
          ),
          title: route.name,

          onTap: () => _selectRoute(route, focus: true),
        ),
      if (fieldSources.isEmpty && spots.isEmpty && routes.isEmpty)
        _atlasQuietMessage(exactPointCount == 0 ? 'No source' : ''),
    ];
    final workerLinks = <Widget>[
      for (final node in nodes)
        _buildAtlasInspectorLink(
          key: ValueKey<String>('resource-map-atlas-node-${node.id}'),
          leading: _buildWorkerNodeArtwork(
            node,
            size: ResourceMapPanelMetrics.artwork,
          ),
          title: node.siteName,
          subtitle: [
            '${node.contributionPoints} CP',
            if (node.region.isNotEmpty) node.region,
          ].join(' · '),
          onTap: () => _selectNode(node, focus: true),
        ),
      if (nodes.isEmpty) _atlasQuietMessage('No worker source'),
    ];
    return _buildAtlasInspectorLayout(
      identity: _buildAtlasInspectorIdentity(
        artwork: _buildResourceArtwork(
          context,
          resource,
          size: ResourceMapPanelMetrics.artwork,
          fallbackIcon: Icons.inventory_2_outlined,
        ),
        eyebrow: '',
        title: resource.name,
        actions: <Widget>[
          MapQuietIconButton(
            key: ValueKey<String>(
              'resource-map-detail-favorite-${resource.id}',
            ),
            tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => _toggleFavorite(resource),
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: favorite
                  ? context.mapChrome.accent
                  : context.mapChrome.muted,
            ),
          ),
          MapQuietIconButton(
            key: ValueKey<String>(
              'resource-map-detail-checklist-${resource.id}',
            ),
            tooltip: checklistEntry == null
                ? 'Add to to-do list'
                : 'Remove from to-do list',
            onPressed: checklistEntry == null
                ? () => _addResourceToGatherChecklist(resource)
                : () => _removeResourceFromGatherChecklist(resource.id),
            icon: Icon(
              checklistEntry == null
                  ? Icons.playlist_add_rounded
                  : Icons.playlist_remove_rounded,
            ),
          ),
          if (checklistEntry != null &&
              (!checklistEntry.isCompleted ||
                  _gatherChecklist.remainingCount > 0))
            MapQuietIconButton(
              key: ValueKey<String>(
                'resource-map-detail-checklist-next-${resource.id}',
              ),
              tooltip: 'Complete and open next item',
              onPressed: () =>
                  _completeGatherChecklistEntryAndAdvance(resource.id),
              icon: const Icon(Icons.done_all_rounded),
            ),
          if (_gatherChecklist.isNotEmpty)
            MapQuietIconButton(
              key: const ValueKey<String>('resource-map-detail-open-checklist'),
              tooltip: 'Open to-do list',
              onPressed: _openGatherChecklist,
              icon: const Icon(Icons.checklist_rounded),
            ),
        ],
      ),
      columns: <Widget>[
        _buildAtlasInspectorColumn(title: 'Gather', children: manualLinks),
        _buildAtlasInspectorColumn(
          title: 'Workers',
          count: nodes.length,
          children: workerLinks,
        ),
      ],
    );
  }

  List<BdoFieldProduct> _distinctGatheringTools(
    Iterable<BdoFieldProduct> products,
  ) {
    final byMethod = <String, BdoFieldProduct>{};
    for (final product in products) {
      final key =
          '${product.method.trim().toLowerCase()}|${product.tool.trim().toLowerCase()}';
      byMethod.putIfAbsent(key, () => product);
    }
    return byMethod.values.toList(growable: false);
  }

  double _gatheringToolIndicatorWidth(Iterable<BdoFieldProduct> products) {
    final tools = _distinctGatheringTools(products);
    const size = ResourceMapPanelMetrics.gatheringToolArtwork;
    var width = math.max(0, tools.length - 1) * 6.0;
    for (final product in tools) {
      final count = resolveBdoGatheringTools(product.tool).tools.length;
      width += count * size + (count - 1) * size / 2;
    }
    return width.clamp(size, size * 2.5);
  }

  Widget _buildGatheringToolIndicators(Iterable<BdoFieldProduct> products) {
    final tools = _distinctGatheringTools(products);
    return SizedBox(
      width: _gatheringToolIndicatorWidth(tools),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final product in tools)
            BdoGatheringToolIcon(
              tool: product.tool,
              method: product.method,
              size: ResourceMapPanelMetrics.gatheringToolArtwork,
            ),
        ],
      ),
    );
  }

  Widget _buildAtlasFieldSourceDetails(
    BdoFieldSource source, {
    BdoResourceDefinition? selectedResource,
  }) {
    final identityResource =
        selectedResource ??
        widget.dataset.resourcesById[_preferredProductForFieldSource(
          source,
        )?.resourceId];
    final productGroups = <String, List<BdoFieldProduct>>{};
    for (final product in source.products) {
      productGroups.putIfAbsent(product.resourceId, () => []).add(product);
    }
    final products = productGroups.entries
        .map(
          (entry) => (
            products: entry.value,
            resource: widget.dataset.resourcesById[entry.key],
          ),
        )
        .where((entry) => entry.resource != null)
        .toList(growable: false);
    final sourceFavoriteKey =
        'map:${BdoSearchKind.fieldSource.name}:${source.id}';
    return _buildAtlasInspectorLayout(
      identity: _buildAtlasInspectorIdentity(
        artwork: identityResource == null
            ? Icon(
                _iconForFieldSource(source),
                color: context.mapChrome.primary,
                size: ResourceMapPanelMetrics.artwork,
              )
            : _buildResourceArtwork(
                context,
                identityResource,
                size: ResourceMapPanelMetrics.artwork,
                fallbackIcon: _iconForFieldSource(source),
              ),
        eyebrow: '',
        title: source.name,
        actions: <Widget>[
          ResourceMapFavoriteButton(
            key: ValueKey<String>(
              'resource-map-detail-favorite-source-${source.id}',
            ),
            name: source.name,
            saved: _favoriteResourceIds.contains(sourceFavoriteKey),
            onPressed: () => _toggleFavoriteKey(sourceFavoriteKey),
          ),
          MapQuietIconButton(
            key: ValueKey<String>('resource-map-fit-field-source-${source.id}'),
            tooltip: 'Show every location',
            onPressed: () => _fitFieldSource(source.id),
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
        ],
      ),
      columns: <Widget>[
        _buildAtlasInspectorColumn(
          title: 'Loot',
          children: <Widget>[
            for (final entry in products)
              _buildAtlasInspectorLink(
                key: ValueKey<String>(
                  'resource-map-atlas-product-${entry.resource!.id}',
                ),
                leading: _buildResourceArtwork(
                  context,
                  entry.resource!,
                  size: ResourceMapPanelMetrics.artwork,
                  fallbackIcon: _iconForFieldSource(source),
                ),
                title: entry.resource!.name,
                selected: entry.resource!.id == selectedResource?.id,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGatheringToolIndicators(entry.products),
                    const SizedBox(width: 5),
                    ResourceMapFavoriteButton(
                      key: ValueKey<String>(
                        'resource-map-detail-favorite-${entry.resource!.id}',
                      ),
                      name: entry.resource!.name,
                      saved: _favoriteResourceIds.contains(entry.resource!.id),
                      onPressed: () => _toggleFavorite(entry.resource!),
                    ),
                  ],
                ),
                onTap: () => _selectResourceFromDetails(entry.resource!),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAtlasPointDetails(BdoGatheringPoint point) {
    final area = point.areaId == null
        ? null
        : widget.dataset.gatheringSpotsById[point.areaId!];
    final resources = point.resourceIds
        .map((id) => widget.dataset.resourcesById[id])
        .whereType<BdoResourceDefinition>()
        .toList(growable: false);
    return _buildAtlasInspectorLayout(
      identity: _buildAtlasInspectorIdentity(
        artwork: Icon(
          Icons.location_on_rounded,
          color: context.mapChrome.primary,
          size: ResourceMapPanelMetrics.artwork,
        ),
        eyebrow: area == null
            ? 'Exact location'
            : _friendlyGatheringSpotName(area),
        title: point.target
            .replaceFirst(RegExp(r'^Representative historical\s+'), '')
            .replaceFirst(RegExp(r'^Historical\s+'), '')
            .replaceFirst(RegExp(r'\s+gathering location$'), ''),
        meta: _friendlyGatheringKind(point.kind),
      ),
      columns: <Widget>[
        _buildAtlasInspectorColumn(
          title: 'Loot',
          children: <Widget>[
            for (final resource in resources)
              _buildAtlasInspectorLink(
                leading: _buildResourceArtwork(
                  context,
                  resource,
                  size: ResourceMapPanelMetrics.artwork,
                  fallbackIcon: Icons.inventory_2_outlined,
                ),
                title: resource.name,
                onTap: () => _selectResourceFromDetails(resource),
              ),
          ],
        ),
        _buildAtlasInspectorColumn(
          title: 'Nearby',
          children: <Widget>[
            if (area != null)
              _buildAtlasInspectorLink(
                leading: Icon(
                  Icons.map_outlined,
                  color: context.mapChrome.primary,
                  size: 19,
                ),
                title: _friendlyGatheringSpotName(area),
                subtitle: area.region,
                onTap: () => _selectSpot(area, focus: true),
              )
            else
              _atlasQuietMessage('No named area'),
            if (point.guideImages.isNotEmpty)
              _buildLocationGuideGallery(context, point.guideImages),
          ],
        ),
      ],
    );
  }

  Widget _buildAtlasSpotDetails(BdoGatheringSpot spot) {
    final isDairy = spot.targets.any((target) => target.name == 'Dairy Cow');
    return _buildAtlasInspectorLayout(
      identity: _buildAtlasInspectorIdentity(
        artwork: Icon(
          isDairy ? Icons.pets_outlined : Icons.location_on_rounded,
          color: context.mapChrome.primary,
          size: ResourceMapPanelMetrics.artwork,
        ),
        eyebrow: isDairy ? 'Milk cows' : spot.region,
        title: _friendlyGatheringSpotName(spot),
      ),
      columns: <Widget>[
        _buildAtlasInspectorColumn(
          title: isDairy ? 'Collect' : 'Gather',
          children: <Widget>[
            for (final target in spot.targets)
              _buildAtlasInspectorLink(
                leading: BdoGatheringToolIcon(
                  tool: target.tool,
                  size: ResourceMapPanelMetrics.gatheringToolArtwork,
                ),
                leadingWidth:
                    resolveBdoGatheringTools(target.tool).tools.length > 1
                    ? ResourceMapPanelMetrics.gatheringToolArtwork * 2.5
                    : ResourceMapPanelMetrics.gatheringToolArtwork,
                title: isDairy ? 'Milk' : target.name,
              ),
          ],
        ),
        if (spot.guideImages.isNotEmpty)
          _buildAtlasInspectorColumn(
            title: 'Photos',
            children: <Widget>[
              _buildLocationGuideGallery(context, spot.guideImages),
            ],
          ),
      ],
    );
  }

  Widget _buildAtlasRouteDetails(BdoGatheringRoute route) {
    return _buildAtlasInspectorLayout(
      identity: _buildAtlasInspectorIdentity(
        artwork: BdoGatheringToolIcon(
          tool: route.tool,
          size: ResourceMapPanelMetrics.artwork,
        ),
        eyebrow: route.region,
        title: route.name,
      ),
      columns: <Widget>[
        _buildAtlasInspectorColumn(
          title: 'Stops',
          children: <Widget>[
            for (final waypoint in route.waypoints)
              _buildAtlasInspectorLink(
                leading: Container(
                  width: 25,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.mapChrome.primary.withValues(alpha: .16),
                  ),
                  child: Text(
                    waypoint.order.toString(),
                    style: TextStyle(
                      color: context.mapChrome.primary,
                      fontSize: ResourceMapPanelMetrics.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                title: waypoint.label.isEmpty
                    ? 'Gathering cluster'
                    : waypoint.label,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAtlasInspectorLayout({
    required Widget identity,
    required List<Widget> columns,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 680;
        if (stacked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              identity,
              const SizedBox(height: 6),
              ...columns.expand(
                (column) => <Widget>[column, const SizedBox(height: 6)],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 248, child: identity),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: 1,
                height: 180,
                color: context.mapChrome.softOutline.withValues(alpha: .55),
              ),
            ),
            for (var index = 0; index < columns.length; index++) ...<Widget>[
              Expanded(child: columns[index]),
              if (index != columns.length - 1) const SizedBox(width: 24),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAtlasInspectorIdentity({
    required Widget artwork,
    double artworkSize = ResourceMapPanelMetrics.artwork,
    required String eyebrow,
    required String title,
    String? meta,
    String? value,
    List<Widget> actions = const <Widget>[],
  }) {
    final chrome = context.mapChrome;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Short icon-only toolbars can share the identity row. Larger text and
        // labelled actions keep a separate wrapping row; no controls shrink.
        final inlineActions =
            actions.isNotEmpty &&
            actions.length <= 2 &&
            actions.every(
              (action) =>
                  action is IconButton || action is ResourceMapFavoriteButton,
            ) &&
            constraints.maxWidth >= 280 &&
            MediaQuery.textScalerOf(context).scale(18) <= 23;
        return Column(
          key: const ValueKey('resource-map-inspector-identity'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                ResourceMapArtworkMount(size: artworkSize + 6, child: artwork),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: [
                      eyebrow,
                      ?meta,
                    ].where((value) => value.trim().isNotEmpty).join(' · '),
                    child: Text(
                      title,
                      style: chrome
                          .headingStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          )
                          .copyWith(height: 1.12, letterSpacing: -.25),
                    ),
                  ),
                ),
                if (inlineActions) ...[const SizedBox(width: 4), ...actions],
              ],
            ),
            if (value != null) ...[
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: chrome.text,
                  fontSize: ResourceMapPanelMetrics.secondary,
                ),
              ),
            ],
            if (actions.isNotEmpty && !inlineActions) ...<Widget>[
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildAtlasInspectorColumn({
    required String title,
    int? count,
    required List<Widget> children,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.secondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .25,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Divider(
                height: 1,
                color: context.mapChrome.readingOutline.withValues(
                  alpha: .30 * context.mapChrome.materialOpacity,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _buildAtlasInspectorLink({
    Key? key,
    required Widget leading,
    double? leadingWidth,
    required String title,
    String subtitle = '',
    String? value,
    bool selected = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return _buildSidebarRowIsland(
      selected: selected,
      artworkWidth:
          (leadingWidth ?? ResourceMapPanelMetrics.optionArtwork) + 12,
      child: Material(
        key: key,
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 7, 8, 7),
            child: Row(
              children: <Widget>[
                if (leadingWidth == null)
                  ResourceMapArtworkMount(
                    size: ResourceMapPanelMetrics.optionArtwork,
                    child: leading,
                  )
                else
                  SizedBox(width: leadingWidth, child: leading),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Tooltip(
                        message: subtitle,
                        child: Text(
                          title,
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.optionLabel,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: context.mapChrome.text,
                        fontSize: ResourceMapPanelMetrics.secondary,
                      ),
                    ),
                  ),
                if (trailing != null)
                  trailing
                else if (onTap != null)
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 22,
                    color: context.mapChrome.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _atlasQuietMessage(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          color: context.mapChrome.muted,
          fontSize: ResourceMapPanelMetrics.secondary,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildDetailsCard(BuildContext context, {required bool compact}) {
    final content = _buildSelectedDetailsContent();
    final backLabel = _backNavigationLabel;

    return Material(
      key: const ValueKey<String>('resource-map-details-card'),
      elevation: 10,
      shadowColor: const Color(0x4517211F),
      color: context.mapChrome.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: compact
              ? _compactDetailsMaximumHeight
              : math.max(360, _viewport.height - 154),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Stack(
                children: <Widget>[
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 51, 18, 18),
                    child: content,
                  ),
                  Positioned(
                    top: 6,
                    left: 7,
                    child: Material(
                      color: context.mapChrome.paper,
                      borderRadius: BorderRadius.circular(999),
                      child: TextButton.icon(
                        key: const ValueKey<String>(
                          'resource-map-compact-back',
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: _navigateBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 17),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 185),
                          child: Text(
                            'Back to $backLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyGatheringSpotName(BdoGatheringSpot spot) {
    const dairySuffix = ' Dairy Cows';
    return spot.name.endsWith(dairySuffix)
        ? spot.name.substring(0, spot.name.length - dairySuffix.length)
        : spot.name;
  }

  String _friendlyGatheringKind(String value) {
    var result = value.trim();
    result = result.replaceFirst(
      RegExp(r'^gathering\s+with\s+', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    return _titleCase(result);
  }

  Widget _buildFieldSourceDetails(
    BdoFieldSource source, {
    BdoResourceDefinition? selectedResource,
  }) {
    final points = widget.dataset
        .gatheringPointsForFieldSource(source.id)
        .toList(growable: false);
    final spots = _gatheringSpotsForFieldSource(source)
      ..sort((left, right) => left.name.compareTo(right.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _DetailHeader(
                icon: _iconForFieldSource(source),
                eyebrow: source.category == 'Animals'
                    ? 'Wildlife'
                    : source.category,
                title: source.name,
                color: context.mapChrome.primary,
                titleSize: 20,
              ),
            ),
            if (selectedResource != null)
              MapQuietIconButton(
                key: ValueKey<String>(
                  'resource-map-detail-favorite-${selectedResource.id}',
                ),
                tooltip: _favoriteResourceIds.contains(selectedResource.id)
                    ? 'Remove ${selectedResource.name} from favorites'
                    : 'Add ${selectedResource.name} to favorites',
                onPressed: () => _toggleFavorite(selectedResource),
                icon: Icon(
                  _favoriteResourceIds.contains(selectedResource.id)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 19,
                  color: _favoriteResourceIds.contains(selectedResource.id)
                      ? context.mapChrome.accent
                      : context.mapChrome.muted,
                ),
              ),
            MapQuietIconButton(
              key: ValueKey<String>(
                'resource-map-fit-field-source-${source.id}',
              ),
              tooltip: 'Fit ${source.name} locations',
              onPressed: () => _fitFieldSource(source.id),
              icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
            ),
          ],
        ),
        if (source.products.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const _SectionHeading(title: 'What you get'),
          const SizedBox(height: 5),
          for (final product in source.products)
            if (widget.dataset.resourcesById[product.resourceId]
                case final resource?)
              _DetailLink(
                icon: _iconForFieldSource(source),
                title: resource.name,
                subtitle: <String>[
                  product.method,
                  product.tool,
                ].where((value) => value.trim().isNotEmpty).toSet().join(' · '),
                selected: resource.id == selectedResource?.id,
                onTap: () => _selectResourceFromDetails(resource),
              ),
        ],
        if (spots.isNotEmpty || points.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _SectionHeading(
            title: 'Locations',
            count: spots.isNotEmpty ? spots.length : points.length,
          ),
          if (spots.isNotEmpty)
            for (final spot in spots)
              _DetailLink(
                icon: Icons.location_on_rounded,
                title: _friendlyGatheringSpotName(spot),
                subtitle: <String>[
                  if (spot.region.isNotEmpty) spot.region,
                  ...spot.targets
                      .map((target) => target.tool)
                      .where((tool) => tool.trim().isNotEmpty)
                      .toSet(),
                ].join(' · '),
                onTap: () => _selectSpot(spot, focus: true),
              ),
        ],
      ],
    );
  }

  Widget _buildResourceDetails(BdoResourceDefinition resource) {
    final fieldSources = widget.dataset
        .fieldSourcesForResource(resource.id)
        .toList(growable: false);
    final allNodes = widget.dataset
        .workerNodesForResource(resource.id)
        .where((node) => node.isResourceNode)
        .toList(growable: false);
    final allSpots = widget.dataset
        .gatheringSpotsForResource(resource.id)
        .toList(growable: false);
    final allPoints = widget.dataset
        .gatheringPointsForResource(resource.id)
        .toList(growable: false);
    final allRoutes = widget.dataset
        .gatheringRoutesForResource(resource.id)
        .toList(growable: false);
    final hasWorkerSources = allNodes.isNotEmpty;
    final hasManualSources =
        fieldSources.isNotEmpty ||
        allSpots.isNotEmpty ||
        allPoints.isNotEmpty ||
        allRoutes.isNotEmpty;
    final favorite = _favoriteResourceIds.contains(resource.id);
    final checklistEntry = _gatherChecklist.entries
        .where((entry) => entry.resourceId == resource.id)
        .firstOrNull;
    final nodes = _materialSourceFilter == _MaterialSourceFilter.manual
        ? const <BdoWorkerNode>[]
        : allNodes;
    final spots = _materialSourceFilter == _MaterialSourceFilter.worker
        ? const <BdoGatheringSpot>[]
        : allSpots;
    final points = _materialSourceFilter == _MaterialSourceFilter.worker
        ? const <BdoGatheringPoint>[]
        : allPoints;
    final routes = _materialSourceFilter == _MaterialSourceFilter.worker
        ? const <BdoGatheringRoute>[]
        : allRoutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Stack(
          children: <Widget>[
            _DetailHeader(
              icon: Icons.inventory_2_outlined,
              eyebrow: resource.category,
              title: resource.name,
              color: context.mapChrome.accent,
              titleSize: 23,
            ),
            Positioned(
              right: 0,
              top: 0,
              child: MapQuietIconButton(
                key: ValueKey<String>(
                  'resource-map-detail-favorite-${resource.id}',
                ),
                tooltip: favorite
                    ? 'Remove ${resource.name} from favorites'
                    : 'Add ${resource.name} to favorites',
                onPressed: () => _toggleFavorite(resource),
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: favorite
                      ? context.mapChrome.accent
                      : context.mapChrome.muted,
                ),
              ),
            ),
          ],
        ),
        if (hasWorkerSources || hasManualSources) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                key: ValueKey<String>(
                  'resource-map-detail-checklist-${resource.id}',
                ),
                onPressed: checklistEntry == null
                    ? () => _addResourceToGatherChecklist(resource)
                    : () => _removeResourceFromGatherChecklist(resource.id),
                icon: Icon(
                  checklistEntry == null
                      ? Icons.playlist_add_rounded
                      : Icons.playlist_remove_rounded,
                  size: 17,
                ),
                label: Text(
                  checklistEntry == null
                      ? 'Add to to-do list'
                      : 'Remove from to-do list',
                ),
              ),
              if (checklistEntry != null &&
                  (!checklistEntry.isCompleted ||
                      _gatherChecklist.remainingCount > 0))
                FilledButton.tonalIcon(
                  key: ValueKey<String>(
                    'resource-map-detail-checklist-next-${resource.id}',
                  ),
                  onPressed: () =>
                      _completeGatherChecklistEntryAndAdvance(resource.id),
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('Complete & next'),
                ),
              if (_gatherChecklist.isNotEmpty)
                TextButton.icon(
                  key: const ValueKey<String>(
                    'resource-map-detail-open-checklist',
                  ),
                  onPressed: _openGatherChecklist,
                  icon: const Icon(Icons.checklist_rounded, size: 17),
                  label: const Text('Open list'),
                ),
            ],
          ),
        ],
        if (fieldSources.isNotEmpty) ...<Widget>[
          const SizedBox(height: 15),
          _SectionHeading(title: 'Gather from', count: fieldSources.length),
          const SizedBox(height: 5),
          for (final source in fieldSources)
            _DetailLink(
              icon: _iconForFieldSource(source),
              title: source.name,
              subtitle: source.products
                  .where((product) => product.resourceId == resource.id)
                  .map((product) {
                    final parts = <String>[
                      product.method,
                      product.tool,
                    ].where((value) => value.trim().isNotEmpty).toSet();
                    return parts.join(' / ');
                  })
                  .where((value) => value.isNotEmpty)
                  .join(', '),
              onTap: () =>
                  _selectFieldSource(source, preferredResourceId: resource.id),
            ),
        ],
        if (_compactLayout && hasWorkerSources && hasManualSources) ...<Widget>[
          const SizedBox(height: 18),
          _buildMaterialSourceSelector(),
        ],
        if (nodes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          _SectionHeading(title: 'Worker nodes', count: nodes.length),
          ...nodes.map(
            (node) => _DetailLink(
              icon: bdoWorkerActivityIcon(node.activity),
              title: node.siteName,
              subtitle: <String>[
                node.activityLabel,
                if (node.region.isNotEmpty) node.region,
                '${node.contributionPoints} CP',
              ].join(' · '),
              onTap: () => _selectNode(node, focus: true),
            ),
          ),
        ],
        if (spots.isNotEmpty) ...<Widget>[
          const SizedBox(height: 15),
          _SectionHeading(
            title: spots.every((spot) => spot.radiusWorld == null)
                ? 'Recommended rotations'
                : 'Gathering areas',
            count: spots.length,
          ),
          ...spots.map(
            (spot) => _DetailLink(
              icon: spot.radiusWorld == null
                  ? Icons.route_outlined
                  : Icons.nature_outlined,
              title: spot.name,
              subtitle: '${spot.region} · ${spot.quality}',
              onTap: () => _selectSpot(spot, focus: true),
            ),
          ),
        ],
        if (routes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 15),
          _SectionHeading(title: 'Routes', count: routes.length),
          ...routes.map(
            (route) => _DetailLink(
              icon: Icons.route_outlined,
              title: route.name,
              subtitle: '${route.waypoints.length} clusters · ${route.tool}',
              onTap: () => _selectRoute(route, focus: true),
            ),
          ),
        ],
        if (nodes.isEmpty &&
            spots.isEmpty &&
            points.isEmpty &&
            routes.isEmpty) ...<Widget>[
          const SizedBox(height: 18),
          const _EmptyAcquisition(
            text: 'No mapped acquisition source is available yet.',
          ),
        ],
      ],
    );
  }

  Widget _buildMaterialSourceSelector({bool global = false}) {
    return Container(
      key: const ValueKey<String>('resource-map-material-source-filter'),
      height: global ? 42 : null,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: context.mapChrome.paperRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.mapChrome.divider),
      ),
      child: Row(
        children: <Widget>[
          _buildMaterialSourceButton(
            filter: _MaterialSourceFilter.all,
            icon: Icons.grid_view_rounded,
            label: 'All',
          ),
          _buildMaterialSourceButton(
            filter: _MaterialSourceFilter.manual,
            icon: Icons.location_on_outlined,
            label: 'Gather',
          ),
          _buildMaterialSourceButton(
            filter: _MaterialSourceFilter.worker,
            icon: Icons.account_tree_outlined,
            label: 'Workers',
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialSourceButton({
    required _MaterialSourceFilter filter,
    required IconData icon,
    required String label,
  }) {
    final selected = _materialSourceFilter == filter;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Semantics(
          button: true,
          selected: selected,
          label: '$label mapped sources',
          child: Material(
            key: ValueKey<String>('resource-map-source-${filter.name}'),
            color: selected ? context.mapChrome.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _setMaterialSourceFilter(filter),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 15,
                      color: selected
                          ? context.mapChrome.onPrimary
                          : context.mapChrome.muted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? context.mapChrome.onPrimary
                              : context.mapChrome.text,
                          fontSize: ResourceMapPanelMetrics.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeDetails(BdoWorkerNode node) {
    final housingTown = widget.lodgingDataset?.townsByNodeId[node.id];
    if (housingTown != null) {
      return _buildTownHousingDetails(housingTown);
    }
    final parent = node.parentId == null
        ? null
        : widget.dataset.workerNodesById[node.parentId!];
    final availableWorkerNodes =
        widget.dataset.workerNodes
            .where(
              (candidate) =>
                  candidate.isResourceNode && candidate.parentId == node.id,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byCp = left.contributionPoints.compareTo(
              right.contributionPoints,
            );
            if (byCp != 0) return byCp;
            final byName = left.name.compareTo(right.name);
            return byName != 0 ? byName : left.id.compareTo(right.id);
          });
    final activity = node.isResourceNode ? node.activity : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailHeader(
          icon: activity == null
              ? Icons.account_balance_outlined
              : bdoWorkerActivityIcon(activity),
          eyebrow: activity?.label ?? 'Connection node',
          title: node.siteName,
          color: activity == null
              ? context.mapChrome.primary
              : bdoWorkerActivityColor(activity),
        ),
        const SizedBox(height: 7),
        Text(
          <String>[
            if (node.region.isNotEmpty) node.region,
            'Worker node',
          ].join(' · '),
          style: TextStyle(
            color: context.mapChrome.muted,
            fontSize: ResourceMapPanelMetrics.secondary,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _InfoPill(
              icon: Icons.stars_rounded,
              text: '${node.contributionPoints} CP',
            ),
            if (node.workload != null && node.workload!.isNotEmpty)
              _InfoPill(icon: Icons.schedule_rounded, text: node.workload!),
          ],
        ),
        if (node.outputs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 19),
          const _SectionHeading(title: 'Produces'),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: node.outputs
                .map((output) {
                  final resource =
                      widget.dataset.resourcesById[output.resourceId];
                  return ActionChip(
                    avatar: resource == null
                        ? _buildWorkerOutputArtwork(context, null, size: 24)
                        : _buildWorkerOutputArtwork(
                            context,
                            resource,
                            size: 24,
                          ),
                    label: Text(output.name),
                    onPressed: resource == null
                        ? null
                        : () => _selectResourceFromDetails(resource),
                  );
                })
                .toList(growable: false),
          ),
        ],
        if (availableWorkerNodes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 19),
          _SectionHeading(
            title: 'Available worker nodes (${availableWorkerNodes.length})',
          ),
          const SizedBox(height: 5),
          for (final childNode in availableWorkerNodes)
            _DetailLink(
              icon: bdoWorkerActivityIcon(childNode.activity),
              title: childNode.name,
              subtitle: <String>[
                '${childNode.contributionPoints} CP',
                if (childNode.outputs.isNotEmpty)
                  childNode.outputs.map((output) => output.name).join(', ')
                else
                  'No recorded output',
              ].join(' · '),
              onTap: () => _selectNode(childNode, focus: true),
            ),
        ],
        if (parent != null) ...<Widget>[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const ValueKey<String>('resource-map-worker-path-toggle'),
            onPressed: () {
              setState(() {
                _showConnections = !_showConnections;
                if (_showConnections) {
                  _showWorkerNodes = true;
                }
              });
            },
            icon: Icon(
              _showConnections
                  ? Icons.visibility_off_outlined
                  : Icons.polyline_outlined,
              size: 17,
            ),
            label: Text(
              _showConnections ? 'Hide worker path' : 'Show worker path',
            ),
          ),
          const SizedBox(height: 15),
          const _SectionHeading(title: 'Connected from'),
          _DetailLink(
            icon: Icons.account_balance_outlined,
            title: parent.name,
            subtitle: parent.region,
            onTap: () => _selectNode(parent, focus: true),
          ),
        ],
      ],
    );
  }

  List<TownHouseGoal> _goalsForTown(LodgingTown town) =>
      _townHouseGoals[town.townNodeId] ??
      const [TownHouseGoal(1, 0), TownHouseGoal(2, 0), TownHouseGoal(3, 0)];

  TownHouseInvestment? _townInvestmentFor(LodgingTown town) {
    final goals = _goalsForTown(town);
    final owned = _ownedHouseIdsForTown(town);
    final key =
        '${town.townNodeId}:${goals.map((g) => '${g.typeId}/${g.amount}/${g.minimumLevel}').join(',')}:${(owned.toList()..sort()).join(',')}';
    if (key != _townInvestmentKey) {
      _townInvestmentKey = key;
      _townInvestment = null;
      _townInvestmentError = null;
      _townInvestmentRequest = (town, goals, owned);
      if (!_townInvestmentRunning) _startTownHouseCalculation();
    }
    return _townInvestment;
  }

  void _startTownHouseCalculation() {
    final key = _townInvestmentKey;
    final request = _townInvestmentRequest!;
    _townInvestmentRunning = true;
    unawaited(
      compute(solveTownHouseInvestmentRequest, request)
          .then((plan) {
            if (!mounted || _townInvestmentKey != key) return;
            setState(() => _townInvestment = plan);
          })
          .catchError((Object error) {
            if (!mounted || _townInvestmentKey != key) return;
            setState(
              () => _townInvestmentError = error is TownHousePlanTooComplex
                  ? 'This combination is too large. Reduce a target or remove a workshop.'
                  : 'Unable to calculate houses. Change a target to retry.',
            );
          })
          .whenComplete(() {
            _townInvestmentRunning = false;
            // Rapid stepper presses replace the queued request instead of launching
            // competing calculations, and stale results never replace current goals.
            if (mounted && key != _townInvestmentKey) {
              _startTownHouseCalculation();
            }
          }),
    );
  }

  Widget _buildTownHousingDetails(LodgingTown town) {
    if (_selectedHouseId != null) {
      widget.debugOnSelectedHouseSnapshotBuilt?.call();
    }
    return TownHousePanel(
      town: town,
      goals: _goalsForTown(town),
      plan: _townInvestmentFor(town),
      error: _townInvestmentError,
      owned: _ownedHouseIdsForTown(town),
      ownedUsages: _nodeNetworkPreferences.currentHouseUsageTypeIds,
      selectedHouseId: _selectedHouseId,
      browseAll: _browseAllTownHouses,
      onGoalsChanged: (goals) => setState(() {
        _townHouseGoals[town.townNodeId] = goals;
        _selectedHouseId = null;
        _browseAllTownHouses = false;
      }),
      onSelectHouse: (id) {
        if (id == null) {
          setState(() => _selectedHouseId = null);
        } else {
          _selectHouse(town.housesById[id]!);
        }
      },
      onOwnedChanged: _toggleOwnedHouse,
      onUseChanged: _setOwnedHouseUsage,
      onBrowseChanged: (value) => setState(() => _browseAllTownHouses = value),
      onFit: () {
        final ids = _townInvestment?.requiredHouseIds;
        if (ids == null || ids.isEmpty || _browseAllTownHouses) {
          _fitHousingTown(town);
          return;
        }
        final bounds = _boundsForPoints(
          ids.map((id) => _houseMapPoint(town.housesById[id]!)).toList(),
        );
        if (bounds != null) {
          _fitBoundsAvoidingDetails(
            bounds.inflate(320),
            padding: 46,
            maximumZoom: 7.35,
          );
        }
      },
      onShopLodging: () => unawaited(_openShopLodgingSetup(town)),
      onImport:
          widget.showSetupScreenshotImport &&
              widget.setupScreenshotPicker != null
          ? () => unawaited(
              _openSetupScreenshotImport(
                initialMode: BdoSetupScreenshotImportMode.townHouses,
                initialTownNodeId: town.townNodeId,
              ),
            )
          : null,
    );
  }

  Widget _buildSelectedHouseDetails(
    LodgingTown town,
    LodgingHouse house, {
    required bool owned,
    required bool recommendedLodging,
    required bool recommendedStorage,
    required bool recommendedHouseUse,
    required bool recommendedPrerequisite,
    VoidCallback? onClose,
  }) {
    final selectedUsageTypeId =
        _nodeNetworkPreferences.currentHouseUsageTypeIds[house.id];
    final prerequisite = house.prerequisiteHouseId == null
        ? null
        : town.housesById[house.prerequisiteHouseId!];
    final path = _housePathTo(town, house);
    final missingPath = path
        .where(
          (entry) =>
              !_nodeNetworkPreferences.currentOwnedHouseIds.contains(entry.id),
        )
        .toList(growable: false);
    final pathCp = missingPath.fold<int>(
      0,
      (total, entry) => total + entry.contributionPoints,
    );
    final ownedBranchCount = _houseBranchIds(
      town,
      house,
    ).where(_nodeNetworkPreferences.currentOwnedHouseIds.contains).length;
    final states = bdoMapSymbolStates(
      owned: owned,
      recommendedLodging: recommendedLodging,
      recommendedStorage: recommendedStorage,
      recommendedHouseUse: recommendedHouseUse,
      recommendedPrerequisite: recommendedPrerequisite,
      selected: true,
    );
    return Material(
      key: ValueKey<String>('resource-map-selected-house-${house.id}'),
      elevation: 12,
      shadowColor: const Color(0x660D1916),
      color: context.mapChrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: DraggableDialogDragHandle(
                    key: ValueKey<String>(
                      'resource-map-house-drag-handle-${house.id}',
                    ),
                    child: Row(
                      children: <Widget>[
                        BdoMapSymbol(
                          kind: _houseSymbolKind(house, selectedUsageTypeId),
                          states: states,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                house.name,
                                style: TextStyle(
                                  color: context.mapChrome.ink,
                                  fontSize: ResourceMapPanelMetrics.primary,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -.1,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                <String>[
                                  '${house.contributionPoints} CP',
                                  if (prerequisite != null)
                                    'after ${prerequisite.name}'
                                  else
                                    'path start',
                                ].join(' · '),
                                style: TextStyle(
                                  color: context.mapChrome.muted,
                                  fontSize: ResourceMapPanelMetrics.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onClose != null)
                  MapQuietIconButton(
                    key: ValueKey<String>(
                      'resource-map-close-house-${house.id}',
                    ),
                    tooltip: 'Close house',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  owned ? Icons.check_circle_rounded : Icons.route_rounded,
                  size: 17,
                  color: owned
                      ? context.mapChrome.positive
                      : context.mapChrome.accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    owned
                        ? 'Saved'
                        : missingPath.length <= 1
                        ? '$pathCp CP to add'
                        : '$pathCp CP · ${missingPath.length} houses in this path',
                    style: TextStyle(
                      color: owned
                          ? context.mapChrome.positive
                          : context.mapChrome.text,
                      fontSize: ResourceMapPanelMetrics.secondary,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (owned)
              OutlinedButton.icon(
                key: ValueKey<String>('resource-map-house-owned-${house.id}'),
                onPressed: () => _toggleOwnedHouse(house),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                label: Text(
                  ownedBranchCount > 1
                      ? 'Remove connected branch'
                      : 'Remove house',
                ),
              )
            else
              FilledButton.icon(
                key: ValueKey<String>('resource-map-house-owned-${house.id}'),
                onPressed: () => _toggleOwnedHouse(house),
                icon: const Icon(Icons.add_home_work_rounded, size: 17),
                label: Text(
                  missingPath.length <= 1 ? 'Add house' : 'Add required path',
                ),
              ),
            const SizedBox(height: 10),
            Divider(height: 1, color: context.mapChrome.divider),
            const SizedBox(height: 9),
            Text(
              'Use',
              style: TextStyle(
                color: context.mapChrome.muted,
                fontSize: ResourceMapPanelMetrics.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            for (final usage in house.usages)
              _HouseUsageButton(
                key: ValueKey<String>(
                  'resource-map-house-usage-${house.id}-${usage.typeId}',
                ),
                selected: selectedUsageTypeId == usage.typeId,
                icon: bdoMapSymbolSpec(_houseSymbolKindForUsage(usage)).icon,
                label: _displayHouseUsageLabel(usage),
                level: usage.level,
                onPressed: () => _setOwnedHouseUsage(house, usage.typeId),
              ),
            if (recommendedLodging ||
                recommendedStorage ||
                recommendedHouseUse ||
                recommendedPrerequisite) ...<Widget>[
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    recommendedStorage
                        ? Icons.inventory_2_rounded
                        : recommendedHouseUse
                        ? Icons.home_work_rounded
                        : recommendedLodging
                        ? Icons.bed_rounded
                        : Icons.call_split_rounded,
                    size: 16,
                    color: recommendedStorage
                        ? context.mapChrome.primary
                        : recommendedHouseUse
                        ? const Color(0xFFD6A4FF)
                        : recommendedLodging
                        ? context.mapChrome.positive
                        : context.mapChrome.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      recommendedStorage
                          ? 'Storage plan'
                          : recommendedHouseUse
                          ? 'Best CP path'
                          : recommendedLodging
                          ? 'Worker plan'
                          : _storagePlannerOpenForTown(town)
                          ? 'Buy first'
                          : 'Required path',
                      style: TextStyle(
                        color: recommendedStorage
                            ? context.mapChrome.primary
                            : recommendedHouseUse
                            ? const Color(0xFFD6A4FF)
                            : recommendedLodging
                            ? context.mapChrome.positive
                            : context.mapChrome.warning,
                        fontSize: ResourceMapPanelMetrics.secondary,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationGuideImage(
    BuildContext context,
    BdoLocationGuideImage image, {
    required BoxFit fit,
  }) {
    final builder = widget.locationGuideImageBuilder;
    if (builder != null) {
      return builder(context, image, fit);
    }
    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) => ColoredBox(
      color: context.mapChrome.paper,
      child: Center(
        child: Semantics(
          label: 'Location photo could not be loaded',
          child: ExcludeSemantics(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: context.mapChrome.muted,
              size: 28,
            ),
          ),
        ),
      ),
    );
    final uri = Uri.tryParse(image.assetPath);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      return Image.network(
        image.assetPath,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
    return Image.asset(
      image.assetPath,
      package: 'bdo_map_core',
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }

  void _openLocationGuideGallery(
    List<BdoLocationGuideImage> images,
    int initialIndex,
  ) {
    if (images.isEmpty) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close location photos',
      barrierColor: Colors.black.withValues(alpha: .82),
      transitionDuration: reduceMotion
          ? Duration.zero
          : ResourceMapAtlasMotion.settle,
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          _LocationGuideLightbox(
            images: images,
            initialIndex: initialIndex,
            imageBuilder: (context, image, fit) =>
                _buildLocationGuideImage(context, image, fit: fit),
            provenanceRecord: _provenanceRecord,
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: ResourceMapAtlasMotion.curve,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .965, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildLocationGuideGallery(
    BuildContext context,
    List<BdoLocationGuideImage> images,
  ) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey<String>('resource-map-location-guide-gallery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 17),
        _SectionHeading(title: 'Location photos', count: images.length),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final image = images[index];
              return SizedBox(
                width: 152,
                child: ResourceMapStewardSurface(
                  child: Material(
                    type: MaterialType.transparency,
                    child: Semantics(
                      button: true,
                      label: image.caption.isEmpty
                          ? 'Open location photo ${index + 1}'
                          : 'Open location photo ${index + 1}: ${image.caption}',
                      child: ExcludeSemantics(
                        child: InkWell(
                          key: ValueKey<String>(
                            'resource-map-location-guide-thumbnail-$index',
                          ),
                          onTap: () => _openLocationGuideGallery(images, index),
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              _buildLocationGuideImage(
                                context,
                                image,
                                fit: BoxFit.cover,
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      Colors.transparent,
                                      Color(0xD90A0B0E),
                                    ],
                                    stops: <double>[.42, 1],
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                start: 8,
                                end: 8,
                                bottom: 7,
                                child: Text(
                                  image.caption.isEmpty
                                      ? 'Open photo ${index + 1}'
                                      : image.caption,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: ResourceMapPanelMetrics.secondary,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSpotDetails(BdoGatheringSpot spot) {
    final exactPoints = widget.dataset.gatheringPoints
        .where((point) => point.areaId == spot.id)
        .toList(growable: false);
    final isRotationFocus = spot.radiusWorld == null && exactPoints.isNotEmpty;
    final isDairyLocation = spot.targets.any(
      (target) => target.name == 'Dairy Cow',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailHeader(
          icon: isDairyLocation
              ? Icons.pets_outlined
              : isRotationFocus
              ? Icons.route_outlined
              : Icons.location_on_rounded,
          eyebrow: <String>[
            if (isDairyLocation) 'Milk cows',
            if (spot.region.isNotEmpty) spot.region,
          ].join(' · '),
          title: _friendlyGatheringSpotName(spot),
          color: context.mapChrome.primary,
        ),
        const SizedBox(height: 8),
        const _SectionHeading(title: 'Gather here'),
        ...spot.targets.map(
          (target) => _DetailLink(
            icon: isDairyLocation
                ? Icons.water_drop_outlined
                : Icons.nature_outlined,
            title: isDairyLocation ? 'Milk' : target.name,
            subtitle: target.tool,
          ),
        ),
        _buildLocationGuideGallery(context, spot.guideImages),
      ],
    );
  }

  Widget _buildPointDetails(BdoGatheringPoint point) {
    final area = point.areaId == null
        ? null
        : widget.dataset.gatheringSpotsById[point.areaId!];
    final resources = point.resourceIds
        .map((id) => widget.dataset.resourcesById[id])
        .whereType<BdoResourceDefinition>()
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailHeader(
          icon: Icons.location_on_rounded,
          eyebrow: area == null
              ? 'Exact location'
              : '${_friendlyGatheringSpotName(area)} · ${area.region}',
          title: point.target,
          color: context.mapChrome.primary,
        ),
        if (point.kind.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _InfoPill(
            icon: Icons.back_hand_outlined,
            text: _friendlyGatheringKind(point.kind),
          ),
        ],
        if (resources.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          const _SectionHeading(title: 'You can get'),
          for (final resource in resources)
            _DetailLink(
              icon: Icons.inventory_2_outlined,
              title: resource.name,
              onTap: () => _selectResourceFromDetails(resource),
            ),
        ],
        if (area != null) ...<Widget>[
          const SizedBox(height: 14),
          const _SectionHeading(title: 'Nearby'),
          _DetailLink(
            icon: area.radiusWorld == null
                ? Icons.route_outlined
                : Icons.nature_outlined,
            title: _friendlyGatheringSpotName(area),
            subtitle: area.region,
            onTap: () => _selectSpot(area, focus: true),
          ),
        ],
        _buildLocationGuideGallery(context, point.guideImages),
      ],
    );
  }

  Widget _buildRouteDetails(BdoGatheringRoute route) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailHeader(
          icon: Icons.route_outlined,
          eyebrow: <String>[
            if (route.region.isNotEmpty) route.region,
            if (route.tool.isNotEmpty) route.tool,
          ].join(' · '),
          title: route.name,
          color: context.mapChrome.primary,
        ),
        const SizedBox(height: 16),
        _SectionHeading(title: 'Stops', count: route.waypoints.length),
        ...route.waypoints.map(
          (waypoint) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 23,
                  height: 23,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.mapChrome.accent,
                  ),
                  child: Text(
                    waypoint.order.toString(),
                    style: TextStyle(
                      color: context.mapChrome.onPrimary,
                      fontSize: ResourceMapPanelMetrics.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    waypoint.label.isEmpty
                        ? 'Gathering cluster'
                        : waypoint.label,
                    style: TextStyle(
                      color: context.mapChrome.text,
                      fontSize: ResourceMapPanelMetrics.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BdoProvenanceRecord? _provenanceRecord(String provenanceId) {
    for (final provenance in widget.dataset.manifest.provenance) {
      if (provenance.id == provenanceId) {
        return provenance;
      }
    }
    return null;
  }

  Widget _buildStatusBar(BuildContext context, {required bool compact}) {
    return AnimatedBuilder(
      animation: _tileManager,
      builder: (context, child) =>
          _buildStatusBarSnapshot(context, compact: compact),
    );
  }

  Widget _buildStatusBarSnapshot(
    BuildContext context, {
    required bool compact,
  }) {
    final state = _tileManager.serviceState;
    final status = switch (state) {
      BdoTileServiceState.idle => ('Ready', context.mapChrome.muted),
      BdoTileServiceState.loading => ('Loading map', context.mapChrome.accent),
      BdoTileServiceState.online => ('Online', context.mapChrome.positive),
      BdoTileServiceState.cachedOnly => (
        'Cached / offline',
        context.mapChrome.primary,
      ),
      BdoTileServiceState.offlineMissing => (
        'Offline — area not cached',
        context.mapChrome.warning,
      ),
      BdoTileServiceState.degraded => (
        'Some tiles unavailable',
        context.mapChrome.error,
      ),
    };
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final expandedStatus = SizedBox(
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 34,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.only(left: 10, right: 3),
                  decoration: BoxDecoration(
                    color: context.mapChrome.graphite,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        context.mapChrome.graphiteHighlight,
                        context.mapChrome.graphite,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: context.mapChrome.brassDeep),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x70000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status.$2,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          status.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!compact) ...<Widget>[
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 13,
                          child: VerticalDivider(
                            width: 1,
                            color: context.mapChrome.brassDeep,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            '${widget.tileSource.attribution} · '
                            'Unofficial fan content',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.mapChrome.muted,
                              fontSize: ResourceMapPanelMetrics.secondary,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (state == BdoTileServiceState.degraded)
                        const _StatusIconVisual(icon: Icons.refresh_rounded),
                      _StatusIconVisual(
                        icon: _tileManager.networkEnabled
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                      ),
                      const _StatusIconVisual(icon: Icons.info_outline_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 3,
            top: 0,
            child: _StatusHitButton(
              tooltip: 'Map source and fan-content notice',
              onPressed: _openSourceNotice,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Semantics(
              key: const ValueKey<String>('resource-map-status-toggle'),
              button: true,
              toggled: true,
              label: 'Map status: ${status.$1}',
              hint: 'Hide map status details',
              child: _StatusHitButton(
                tooltip: 'Hide map status details',
                onPressed: () {
                  setState(() => _statusDetailsExpanded = false);
                },
              ),
            ),
          ),
          Positioned(
            right: 51,
            top: 0,
            child: _StatusHitButton(
              tooltip: _tileManager.networkEnabled
                  ? 'Use cached tiles only'
                  : 'Allow map downloads',
              onPressed: () {
                _tileManager.networkEnabled = !_tileManager.networkEnabled;
              },
            ),
          ),
          if (state == BdoTileServiceState.degraded)
            Positioned(
              right: 99,
              top: 0,
              child: _StatusHitButton(
                tooltip: 'Retry unavailable tiles',
                onPressed: _tileManager.retryVisible,
              ),
            ),
        ],
      ),
    );
    final collapsedStatus = Semantics(
      key: const ValueKey<String>('resource-map-status-toggle'),
      button: true,
      toggled: false,
      label: 'Map status: ${status.$1}',
      hint: 'Show map status details',
      child: ExcludeSemantics(
        child: MapQuietTooltip(
          message: 'Show map status details',
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Material(
                color: context.mapChrome.fillAlpha(
                  context.mapChrome.chromeBase,
                  .92,
                ),
                borderRadius: BorderRadius.circular(999),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() => _statusDetailsExpanded = true);
                  },
                  child: Container(
                    width: 38,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: context.mapChrome.ink.withValues(alpha: .11),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status.$2,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: status.$2.withValues(alpha: .34),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final statusControl = _statusDetailsExpanded
        ? SizedBox(
            key: const ValueKey<String>('resource-map-status-details'),
            width: compact ? 300 : 360,
            child: expandedStatus,
          )
        : collapsedStatus;
    return Align(
      alignment: Alignment.bottomLeft,
      child: KeyedSubtree(
        key: const ValueKey<String>('resource-map-status-animation'),
        child: reduceMotion
            ? statusControl
            : AnimatedSize(
                alignment: Alignment.bottomLeft,
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                clipBehavior: Clip.none,
                child: statusControl,
              ),
      ),
    );
  }

  Widget _buildSourceNotice(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _closeSourceNotice,
      },
      child: FocusTraversalGroup(
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ModalBarrier(
                color: const Color(0xB8000000),
                dismissible: true,
                onDismiss: _closeSourceNotice,
              ),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: DraggableDialogSurface(
                  identity: 'map-source-and-usage',
                  estimatedSize: Size(
                    580,
                    math.min(
                      640,
                      math.max(120, MediaQuery.sizeOf(context).height - 32),
                    ),
                  ),
                  builder: (context, alignment) => Align(
                    alignment: alignment,
                    child: Material(
                      elevation: 16,
                      shadowColor: const Color(0x5617211F),
                      color: context.mapChrome.paperRaised,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: context.mapChrome.divider),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 580,
                          maxHeight: math.max(
                            120.0,
                            MediaQuery.sizeOf(context).height - 32,
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: DraggableDialogDragHandle(
                                      key: const ValueKey<String>(
                                        'resource-map-source-notice-drag-handle',
                                      ),
                                      child: Row(
                                        children: <Widget>[
                                          Icon(
                                            Icons.map_outlined,
                                            color: context.mapChrome.accent,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Map source and usage',
                                              style: TextStyle(
                                                color: context.mapChrome.ink,
                                                fontSize:
                                                    ResourceMapPanelMetrics
                                                        .heading,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  MapQuietIconButton(
                                    tooltip: 'Close',
                                    onPressed: _closeSourceNotice,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'This is unofficial content which contains copyrighted '
                                'materials and IP from Pearl Abyss, and is not official '
                                'or endorsed content.',
                                style: TextStyle(
                                  color: context.mapChrome.text,
                                  fontSize: ResourceMapPanelMetrics.secondary,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                widget.tileSource.usageNotice,
                                style: TextStyle(
                                  color: context.mapChrome.muted,
                                  fontSize: ResourceMapPanelMetrics.secondary,
                                  height: 1.45,
                                ),
                              ),
                              if (widget.showSourceNotice) ...<Widget>[
                                const SizedBox(height: 14),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Color(0x26C79B58),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(10),
                                    ),
                                    border: Border.fromBorderSide(
                                      BorderSide(
                                        color: context.mapChrome.accent,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text(
                                      'Unofficial, free and noncommercial fan-project map. '
                                      'Pearl Abyss owns the Black Desert game content and '
                                      'facts. Workerman / Shrddr provides the credited '
                                      'community basemap, node icons, lodging and worker-data '
                                      'inputs; BDO Codex and BDOLytics are credited research '
                                      'references. Please use the public project issue route '
                                      'for corrections or removal requests.',
                                      style: TextStyle(
                                        color: context.mapChrome.text,
                                        fontSize:
                                            ResourceMapPanelMetrics.secondary,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.mapChrome.paper,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(10),
                                  ),
                                  border: Border.fromBorderSide(
                                    BorderSide(
                                      color: context.mapChrome.divider,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'Downloaded map tiles: '
                                        '${_cacheBytes == null ? 'measuring…' : _formatByteCount(_cacheBytes!)}',
                                        style: TextStyle(
                                          color: context.mapChrome.ink,
                                          fontSize:
                                              ResourceMapPanelMetrics.secondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (_cacheActionMessage !=
                                          null) ...<Widget>[
                                        const SizedBox(height: 7),
                                        Text(
                                          _cacheActionMessage!,
                                          style: TextStyle(
                                            color: context.mapChrome.positive,
                                            fontSize: ResourceMapPanelMetrics
                                                .secondary,
                                            fontWeight: FontWeight.w700,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        key: const ValueKey<String>(
                                          'resource-map-clear-cache',
                                        ),
                                        onPressed: _clearingCache
                                            ? null
                                            : _clearMapCache,
                                        icon: _clearingCache
                                            ? const SizedBox.square(
                                                dimension: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.delete_sweep_outlined,
                                                size: 17,
                                              ),
                                        label: Text(
                                          _clearingCache
                                              ? 'Clearing…'
                                              : 'Clear downloaded tiles',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatByteCount(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kibibytes = bytes / 1024;
  if (kibibytes < 1024) {
    return '${kibibytes.toStringAsFixed(kibibytes < 10 ? 1 : 0)} KiB';
  }
  final mebibytes = kibibytes / 1024;
  return '${mebibytes.toStringAsFixed(mebibytes < 10 ? 1 : 0)} MiB';
}

String _formatMarketValueSignal(double value) {
  if (!value.isFinite || value < 0) {
    return '—';
  }
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(2)}b';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(2)}m';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return value.toStringAsFixed(value < 10 ? 2 : 0);
}

String _formatCompactNumber(double value) {
  if (!value.isFinite) return '—';
  final rounded = value.roundToDouble();
  return value == rounded
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1);
}

String _formatMapTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatDate(DateTime value) {
  final date = value.toUtc();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _normalizePlannerMaterialName(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _formatMapQuantity(double value) {
  if (!value.isFinite) {
    return '—';
  }
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < .000001) {
    final digits = rounded.toInt().abs().toString();
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index += 1) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[index]);
    }
    return '${value < 0 ? '-' : ''}$grouped';
  }
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _MapDashboardTile extends StatefulWidget {
  const _MapDashboardTile({
    super.key,
    required this.icon,
    required this.title,
    required this.semanticHint,
    required this.onPressed,
    this.subtitle,
    this.badge,
    this.selected = false,
    this.featured = false,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String semanticHint;
  final VoidCallback onPressed;
  final String? subtitle;
  final String? badge;
  final bool selected;
  final bool featured;
  final Color? accentColor;

  @override
  State<_MapDashboardTile> createState() => _MapDashboardTileState();
}

class _MapDashboardTileState extends State<_MapDashboardTile> {
  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? context.mapChrome.primary;
    final semanticLabel = widget.badge == null
        ? '${widget.title}. ${widget.semanticHint}'
        : '${widget.title}, ${widget.badge}. ${widget.semanticHint}';
    return MapQuietTooltip(
      message: widget.semanticHint,
      waitDuration: const Duration(milliseconds: 420),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: ResourceMapPill(
            selected: widget.selected,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ResourceMapPanelMetrics.optionHeight,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scaledTitle = MediaQuery.textScalerOf(
                        context,
                      ).scale(ResourceMapPanelMetrics.optionLabel);
                      final stacked =
                          !widget.featured &&
                          (constraints.maxWidth < 155 || scaledTitle > 22);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        child: stacked
                            ? _buildStackedContent(
                                context,
                                accent: accent,
                                largeText: scaledTitle > 22,
                              )
                            : _buildWideContent(context, accent: accent),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStackedContent(
    BuildContext context, {
    required Color accent,
    required bool largeText,
  }) {
    final badge = _buildBadge(accent);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _buildTileIcon(accent, compact: true),
            if (badge != null) ...<Widget>[const SizedBox(width: 5), badge],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.mapChrome.ink,
            fontSize: ResourceMapPanelMetrics.optionLabel,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -.08,
          ),
        ),
      ],
    );
  }

  Widget _buildWideContent(BuildContext context, {required Color accent}) {
    final chrome = context.mapChrome;
    final badge = _buildBadge(accent);
    return Row(
      children: <Widget>[
        _buildTileIcon(accent),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.title,
                style: TextStyle(
                  color: chrome.ink,
                  fontSize: ResourceMapPanelMetrics.optionLabel,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.08,
                ),
              ),
              if (widget.subtitle case final subtitle?
                  when subtitle.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: chrome.text,
                    fontSize: ResourceMapPanelMetrics.secondary,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (badge != null) ...<Widget>[const SizedBox(width: 5), badge],
      ],
    );
  }

  Widget _buildTileIcon(Color accent, {bool compact = false}) {
    const size = ResourceMapPanelMetrics.optionArtwork;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(widget.icon, size: 30, color: accent),
    );
  }

  Widget? _buildBadge(Color accent) {
    final badge = widget.badge?.trim();
    if (badge == null || badge.isEmpty) return null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          badge,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            color: accent,
            fontSize: ResourceMapPanelMetrics.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BloodFamilyDefinition {
  const _BloodFamilyDefinition({
    required this.id,
    required this.label,
    required this.members,
    this.ratios = const <String, double>{},
  });

  final String id;
  final String label;
  final List<_BloodFamilyMember> members;
  final Map<String, double> ratios;
}

class _BloodFamilyMember {
  const _BloodFamilyMember({required this.name, required this.gameItemId});

  final String name;
  final int? gameItemId;
}

class _MappedPlannerNeed {
  const _MappedPlannerNeed({
    required this.need,
    required this.resource,
    required this.exactLocationCount,
    required this.workerNodeCount,
  });

  final BdoPlannerMaterialNeed need;
  final BdoResourceDefinition resource;
  final int exactLocationCount;
  final int workerNodeCount;

  bool get _hasWorkerAlternative =>
      workerNodeCount > 0 || need.reviewedWorkerRoute;

  bool get _marketNeedsAlternative =>
      !need.marketable || !need.stockKnown || need.stock < need.missingQuantity;

  /// The home shortlist is deliberately narrower than search. It recommends
  /// only exact manual layers that solve a real shortage and have neither a
  /// direct NPC purchase nor an easy worker-node alternative.
  bool get isUsefulManualTarget =>
      exactLocationCount > 0 &&
      !_hasWorkerAlternative &&
      !need.vendorPurchaseAvailable &&
      _marketNeedsAlternative;

  int get manualPriority =>
      _featuredExactResourcePriority[resource.gameItemId] ?? 1 << 20;

  bool get _zeroStock => need.marketable && need.stockKnown && need.stock <= 0;

  bool get _partialStock =>
      need.marketable &&
      need.stockKnown &&
      need.stock > 0 &&
      need.stock < need.missingQuantity;

  int get scarcityRank {
    if (_zeroStock) {
      return 0;
    }
    if (_partialStock) {
      return 1;
    }
    if (!need.marketable || !need.stockKnown) {
      return 2;
    }
    return 3;
  }

  double get stockCoverage {
    if (!need.marketable || !need.stockKnown || need.missingQuantity <= 0) {
      return 1;
    }
    return need.stock / need.missingQuantity;
  }

  String get shortStatus {
    if (!need.marketable) {
      return 'GATHER';
    }
    if (!need.stockKnown) {
      return 'Stock —';
    }
    return 'Stock ${_formatMapQuantity(need.stock)}';
  }

  String get marketStatus {
    final region = need.marketRegion.trim().toUpperCase();
    final checkedAt = need.marketFetchedAt;
    final context = <String>[
      if (region.isNotEmpty) region,
      if (checkedAt != null) _formatDate(checkedAt),
    ];
    final suffix = context.isEmpty ? '' : ' · ${context.join(' · ')}';
    if (!need.marketable) {
      return 'Not registered on Central Market$suffix';
    }
    if (!need.stockKnown) {
      return 'Stock unknown$suffix';
    }
    if (_zeroStock) {
      return region.isEmpty
          ? '0 stock at last market check'
          : '0 stock at last $region check'
                '${checkedAt == null ? '' : ' · ${_formatDate(checkedAt)}'}';
    }
    if (_partialStock) {
      return 'Stock below needed quantity · '
          '${_formatMapQuantity(need.stock)} available$suffix';
    }
    return '${_formatMapQuantity(need.stock)} available$suffix';
  }
}

ThemeData _buildWorkerIncomeAtlasTheme(BuildContext context) {
  final chrome = context.mapChrome;
  final base = ThemeData(brightness: chrome.brightness, useMaterial3: true);
  final headingFamily = chrome.headingFontFamily ?? 'Segoe UI';
  final scheme = ColorScheme(
    brightness: chrome.brightness,
    primary: chrome.primary,
    onPrimary: chrome.onPrimary,
    primaryContainer: chrome.deepAccent,
    onPrimaryContainer: chrome.text,
    secondary: chrome.accent,
    onSecondary: chrome.onPrimary,
    surface: chrome.chromeBase,
    onSurface: chrome.ink,
    surfaceContainerLow: chrome.chromeBase,
    surfaceContainer: chrome.chromeRaised,
    surfaceContainerHigh: chrome.chromeHighlight,
    outline: chrome.trimDeep,
    outlineVariant: chrome.softOutline,
    error: chrome.error,
    onError: chrome.onPrimary,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: chrome.chromeBase,
    canvasColor: chrome.chromeBase,
    splashFactory: InkRipple.splashFactory,
    textTheme: base.textTheme
        .apply(
          fontFamily: 'Segoe UI',
          bodyColor: chrome.ink,
          displayColor: chrome.ink,
        )
        .copyWith(
          bodyMedium: TextStyle(
            fontSize: ResourceMapPanelMetrics.primary,
            height: 1.42,
          ),
          bodySmall: TextStyle(
            fontSize: ResourceMapPanelMetrics.secondary,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            fontFamily: headingFamily,
            fontSize: ResourceMapPanelMetrics.primary,
            fontWeight: FontWeight.w700,
          ),
        )
        .apply(fontFamily: 'Segoe UI'),
    dividerColor: chrome.softOutline,
    dividerTheme: DividerThemeData(
      color: chrome.softOutline,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: chrome.chromeRaised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(
        color: chrome.muted,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: chrome.primary,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(chrome.controlRadius),
        borderSide: BorderSide(color: chrome.trimDeep),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(chrome.controlRadius),
        borderSide: BorderSide(color: chrome.trimDeep),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(chrome.controlRadius),
        borderSide: BorderSide(color: chrome.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        backgroundColor: chrome.primary,
        foregroundColor: chrome.onPrimary,
        disabledBackgroundColor: chrome.chromeHighlight,
        disabledForegroundColor: chrome.muted,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        textStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        foregroundColor: chrome.primary,
        side: BorderSide(color: chrome.primary),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        textStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        foregroundColor: chrome.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        textStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: chrome.chromeRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.surfaceRadius),
        side: BorderSide(color: chrome.trimDeep),
      ),
      textStyle: TextStyle(
        color: chrome.ink,
        fontFamily: headingFamily,
        fontSize: ResourceMapPanelMetrics.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: IconThemeData(color: chrome.primary),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: chrome.primary,
      linearTrackColor: chrome.chromeRaised,
    ),
  );
}

class _WorkerIncomeNotice extends StatelessWidget {
  const _WorkerIncomeNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: ResourceMapPanelMetrics.secondary,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerIncomeTownLink extends StatelessWidget {
  const _WorkerIncomeTownLink({
    required this.townName,
    required this.summary,
    required this.onTap,
    super.key,
  });

  final String townName;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$townName, $summary, show houses',
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: ResourceMapPanelMetrics.optionGap,
        ),
        child: ResourceMapPill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.location_city_outlined,
                      size: 19,
                      color: context.mapChrome.brassLine,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        townName,
                        style: TextStyle(
                          color: context.mapChrome.ink,
                          fontSize: ResourceMapPanelMetrics.optionLabel,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.mapChrome.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerIncomeMenuButton extends StatelessWidget {
  const _WorkerIncomeMenuButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mapChrome.graphiteRaised,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              context.mapChrome.graphiteHighlight,
              context.mapChrome.graphiteRaised,
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.mapChrome.brassDeep),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: context.mapChrome.primary),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    color: context.mapChrome.ink,
                    fontSize: ResourceMapPanelMetrics.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: context.mapChrome.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkerIncomeEmptyState extends StatelessWidget {
  const _WorkerIncomeEmptyState({
    required this.hasEvidence,
    required this.excludedCount,
  });
  final bool hasEvidence;
  final int excludedCount;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: hasEvidence
        ? 'Incomplete data excludes $excludedCount nodes.'
        : 'Refresh prices to compare nodes.',
    child: Text(
      'No results',
      style: TextStyle(
        fontSize: ResourceMapPanelMetrics.secondary,
        color: context.mapChrome.muted,
      ),
    ),
  );
}

class _MapSearchResultTile extends StatelessWidget {
  const _MapSearchResultTile({
    Key? key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.kindLabel,
    required this.onTap,
    this.selected = false,
    this.horizontal = false,
    this.trailing,
  }) : tileKey = key;

  final Key? tileKey;
  final Widget leading;
  final String title;
  final String subtitle;
  final String kindLabel;
  final VoidCallback onTap;
  final bool selected;
  final bool horizontal;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final content = Row(
      children: <Widget>[
        SizedBox.square(
          dimension: ResourceMapPanelMetrics.optionArtwork,
          child: leading,
        ),
        SizedBox(width: horizontal ? 13 : 11),
        Expanded(
          child: Tooltip(
            message: [
              kindLabel,
              subtitle,
            ].where((value) => value.isNotEmpty).join(' · '),
            child: Text(
              title,
              style: TextStyle(
                color: chrome.ink,
                fontSize: ResourceMapPanelMetrics.optionLabel,
                height: 1.12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        trailing ??
            Icon(
              Icons.arrow_forward_rounded,
              size: ResourceMapPanelMetrics.controlGlyph,
              color: chrome.text,
            ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: horizontal ? 0 : ResourceMapPanelMetrics.optionGap,
        right: horizontal ? ResourceMapPanelMetrics.optionGap : 0,
      ),
      child: SizedBox(
        width: horizontal ? 258 : null,
        child: ResourceMapPill(
          selected: selected,
          child: Material(
            key: tileKey,
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ResourceMapPanelMetrics.optionHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchGroupHeading extends StatelessWidget {
  const _SearchGroupHeading({
    super.key,
    required this.label,
    this.surface = false,
    this.compact = false,
  });

  final String label;
  final bool surface;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: TextStyle(
        color: surface ? context.mapChrome.ink : context.mapChrome.muted,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w700,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: ResourceMapPanelMetrics.optionGap),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ResourceMapPill(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: labelText,
        ),
      ),
    );
  }
}

class _NodePlannerInlineStatus extends StatelessWidget {
  const _NodePlannerInlineStatus({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: context.mapChrome.text,
              fontSize: ResourceMapPanelMetrics.secondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _NodePlannerNotice extends StatelessWidget {
  const _NodePlannerNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.mapChrome.paper,
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: context.mapChrome.text,
                  fontSize: ResourceMapPanelMetrics.secondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeNetworkCalculating extends StatelessWidget {
  const _NodeNetworkCalculating();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey<String>('resource-map-node-network-calculating'),
      liveRegion: true,
      label: 'Calculating a complete worker-node network',
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: context.mapChrome.primary,
                ),
              ),
              SizedBox(height: 13),
              Text(
                'Calculating route…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeTargetViewButton extends StatelessWidget {
  const _NodeTargetViewButton({
    required this.view,
    required this.selected,
    required this.selectedCount,
    required this.onPressed,
    super.key,
  });

  final _NodeTargetView view;
  final bool selected;
  final int selectedCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (view) {
      _NodeTargetView.all => 'All',
      _NodeTargetView.selected => 'Selected',
      _NodeTargetView.current => 'My setup',
      _NodeTargetView.favorites => 'Saved',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? context.mapChrome.accent
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.mapChrome.accent
                    : context.mapChrome.text,
                fontSize: ResourceMapPanelMetrics.primary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodePlannerEmptyTargets extends StatelessWidget {
  const _NodePlannerEmptyTargets();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 90) {
          return Center(
            heightFactor: 1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.search_off_rounded,
                    size: 18,
                    color: context.mapChrome.muted,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'No matches',
                      style: TextStyle(
                        color: context.mapChrome.muted,
                        fontSize: ResourceMapPanelMetrics.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.search_off_rounded,
                  size: 19,
                  color: context.mapChrome.muted,
                ),
                SizedBox(height: 8),
                Text(
                  'No matches',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.mapChrome.muted,
                    fontSize: ResourceMapPanelMetrics.secondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NodeCountControl extends StatelessWidget {
  const _NodeCountControl({
    required this.resourceId,
    required this.resourceName,
    required this.count,
    required this.canDecrease,
    required this.canIncrease,
    required this.onRemove,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String resourceId;
  final String resourceName;
  final int count;
  final bool canDecrease;
  final bool canIncrease;
  final VoidCallback onRemove;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: ResourceMapPanelMetrics.controlTarget,
      ),
      decoration: BoxDecoration(
        color: context.mapChrome.graphiteRaised,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            context.mapChrome.graphiteHighlight,
            context.mapChrome.graphiteRaised,
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.mapChrome.brassDeep),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _NodeCountButton(
            key: ValueKey<String>(
              'resource-map-node-target-remove-$resourceId',
            ),
            tooltip: 'Remove $resourceName',
            icon: Icons.close_rounded,
            onPressed: onRemove,
          ),
          _NodeCountButton(
            key: ValueKey<String>('resource-map-node-target-minus-$resourceId'),
            tooltip: 'Use one fewer node',
            icon: Icons.remove_rounded,
            onPressed: canDecrease ? onDecrease : null,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 24),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.mapChrome.ink,
                fontSize: ResourceMapPanelMetrics.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _NodeCountButton(
            key: ValueKey<String>('resource-map-node-target-plus-$resourceId'),
            tooltip: 'Use one more node',
            icon: Icons.add_rounded,
            onPressed: canIncrease ? onIncrease : null,
          ),
        ],
      ),
    );
  }
}

class _NodeCountButton extends StatelessWidget {
  const _NodeCountButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ResourceMapPanelMetrics.controlTarget,
      height: ResourceMapPanelMetrics.controlTarget,
      child: MapQuietIconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: ResourceMapPanelMetrics.controlTarget,
          height: ResourceMapPanelMetrics.controlTarget,
        ),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: context.mapChrome.ink,
          disabledForegroundColor: context.mapChrome.muted.withValues(
            alpha: .38,
          ),
          hoverColor: context.mapChrome.brassWash,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        icon: Icon(icon, size: ResourceMapPanelMetrics.controlGlyph),
      ),
    );
  }
}

class _NodePlanSection extends StatelessWidget {
  const _NodePlanSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
        SizedBox(
          height: 12,
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              height: 1,
              width: double.infinity,
              child: ColoredBox(color: context.mapChrome.brassDeep),
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeChangeRow extends StatelessWidget {
  const _NodeChangeRow({required this.node, required this.color});

  final BdoWorkerNode node;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: <String>[
                if (node.isResourceNode) node.activityLabel,
                if (node.region.isNotEmpty) node.region,
              ].join(' · '),
              child: Text(
                node.siteName,
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Text(
            '${node.contributionPoints} CP',
            style: TextStyle(
              color: color.withAlpha(220),
              fontSize: ResourceMapPanelMetrics.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AtlasDialogTitle extends StatelessWidget {
  const _AtlasDialogTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: subtitle,
      child: Row(
        children: [
          Icon(
            icon,
            size: ResourceMapPanelMetrics.artwork,
            color: context.mapChrome.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.mapChrome.ink,
                fontSize: ResourceMapPanelMetrics.heading,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeRootSelection {
  const _NodeRootSelection({required this.useAll, required this.nodeIds});

  final bool useAll;
  final Set<String> nodeIds;
}

class _PlannerNeedSelectionResult {
  const _PlannerNeedSelectionResult({
    required this.selection,
    required this.materialTargets,
  });

  final BdoPlannerNeedSelection selection;
  final List<BdoRecipeNodeMaterialTarget> materialTargets;
}

class _PlannerNeedSelectionDialog extends StatefulWidget {
  const _PlannerNeedSelectionDialog({
    required this.initialSelection,
    required this.initialNodeCountsByResourceId,
    required this.resourceIconBuilder,
    required this.dataset,
    required this.reachableProductionNodeIds,
    required this.contributionPointBudget,
    required this.currentNodeIds,
    required this.rootNodeIds,
  });

  final BdoPlannerNeedSelection initialSelection;
  final Map<String, int> initialNodeCountsByResourceId;
  final BdoResourceIconBuilder? resourceIconBuilder;
  final BdoResourceMapDataset dataset;
  final Set<String> reachableProductionNodeIds;
  final int contributionPointBudget;
  final Set<String> currentNodeIds;
  final Set<String>? rootNodeIds;

  @override
  State<_PlannerNeedSelectionDialog> createState() =>
      _PlannerNeedSelectionDialogState();
}

class _PlannerNeedSelectionDialogState
    extends State<_PlannerNeedSelectionDialog> {
  late BdoPlannerNeedSelection _selection;
  final Map<String, int> _nodeCountsByResourceId = <String, int>{};
  late BdoRecipeNodeRecommendation _recommendation;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
    for (final group in _selection.groups) {
      for (final material in group.materials) {
        if (material.need.vendorPurchaseAvailable) {
          _selection = _selection.withMaterialSelected(
            groupId: group.id,
            materialId: material.id,
            selected: false,
          );
          continue;
        }
        final resource = _resourceFor(material.need);
        if (resource == null || _availableNodeCount(resource) == 0) {
          _selection = _selection.withMaterialSelected(
            groupId: group.id,
            materialId: material.id,
            selected: false,
          );
          continue;
        }
        final available = _availableNodeCount(resource);
        if (available == 0) {
          continue;
        }
        final saved = widget.initialNodeCountsByResourceId[resource.id];
        _nodeCountsByResourceId[resource.id] = saved == null
            ? available
            : saved.clamp(1, available);
      }
    }
    _recommendation = _calculateRecommendation();
  }

  BdoResourceDefinition? _resourceFor(BdoPlannerMaterialNeed need) {
    final gameItemId = need.gameItemId;
    if (gameItemId != null) {
      for (final resource in widget.dataset.resources) {
        if (resource.gameItemId == gameItemId) {
          return resource;
        }
      }
    }
    final normalizedName = _normalizePlannerMaterialName(need.name);
    for (final resource in widget.dataset.resources) {
      if (_normalizePlannerMaterialName(resource.name) == normalizedName ||
          resource.aliases.any(
            (alias) => _normalizePlannerMaterialName(alias) == normalizedName,
          )) {
        return resource;
      }
    }
    return null;
  }

  int _availableNodeCount(BdoResourceDefinition resource) => widget.dataset
      .workerNodesForResource(resource.id)
      .map((node) => node.id)
      .toSet()
      .intersection(widget.reachableProductionNodeIds)
      .length;

  bool _isWorkerEligibleMaterial(BdoPlannerNeedMaterial material) {
    if (material.need.vendorPurchaseAvailable) {
      return false;
    }
    final resource = _resourceFor(material.need);
    return resource != null && _availableNodeCount(resource) > 0;
  }

  List<BdoRecipeNodeMaterialTarget> _materialTargets() {
    final selectedResourceIds = <String>{};
    for (final group in _selection.groups) {
      for (final material in group.materials) {
        if (material.need.vendorPurchaseAvailable ||
            !_selection.isMaterialSelected(
              groupId: group.id,
              materialId: material.id,
            )) {
          continue;
        }
        final resource = _resourceFor(material.need);
        if (resource != null && _availableNodeCount(resource) > 0) {
          selectedResourceIds.add(resource.id);
        }
      }
    }
    final resourceIds = selectedResourceIds.toList()..sort();
    return List<BdoRecipeNodeMaterialTarget>.unmodifiable(
      resourceIds.map((resourceId) {
        final resource = widget.dataset.resourcesById[resourceId]!;
        return BdoRecipeNodeMaterialTarget(
          query: resource.id,
          gameItemId: resource.gameItemId,
          distinctProductionNodeCount: _nodeCountsByResourceId[resourceId] ?? 1,
        );
      }),
    );
  }

  BdoRecipeNodeRecommendation _calculateRecommendation() =>
      const BdoGroupedRecipeNodeRecommendationService()
          .recommend(
            data: widget.dataset,
            request: BdoGroupedRecipeNodeRecommendationRequest(
              selection: _selection,
              contributionPointBudget: widget.contributionPointBudget,
              materialTargets: _materialTargets(),
              currentNodeIds: widget.currentNodeIds,
              rootNodeIds: widget.rootNodeIds,
            ),
          )
          .recommendation;

  void _updateSelection(BdoPlannerNeedSelection selection) {
    setState(() {
      _selection = selection;
      _recommendation = _calculateRecommendation();
    });
  }

  void _changeNodeCount(BdoResourceDefinition resource, int nextCount) {
    final available = _availableNodeCount(resource);
    if (available == 0) {
      return;
    }
    setState(() {
      _nodeCountsByResourceId[resource.id] = nextCount.clamp(1, available);
      _recommendation = _calculateRecommendation();
    });
  }

  BdoPlannerNeedSelection _withEligibleGroupSelected(
    BdoPlannerNeedGroup group,
    bool selected,
  ) {
    var next = _selection;
    for (final material in group.materials) {
      next = next.withMaterialSelected(
        groupId: group.id,
        materialId: material.id,
        selected: selected && _isWorkerEligibleMaterial(material),
      );
    }
    return next;
  }

  ({int selected, int total}) _eligibleGroupCounts(BdoPlannerNeedGroup group) {
    final eligible = group.materials
        .where(_isWorkerEligibleMaterial)
        .toList(growable: false);
    return (
      selected: eligible
          .where(
            (material) => _selection.isMaterialSelected(
              groupId: group.id,
              materialId: material.id,
            ),
          )
          .length,
      total: eligible.length,
    );
  }

  bool? _eligibleGroupValue(BdoPlannerNeedGroup group) {
    final counts = _eligibleGroupCounts(group);
    if (counts.selected == 0) {
      return false;
    }
    return counts.selected == counts.total ? true : null;
  }

  Widget _materialIcon(BuildContext context, BdoPlannerMaterialNeed need) {
    final resource = _resourceFor(need);
    final builder = widget.resourceIconBuilder;
    if (resource != null && builder != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: ResourceMapPanelMetrics.artwork,
          child: builder(context, resource, ResourceMapPanelMetrics.artwork),
        ),
      );
    }
    return Container(
      width: ResourceMapPanelMetrics.artwork,
      height: ResourceMapPanelMetrics.artwork,
      decoration: BoxDecoration(
        color: context.mapChrome.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.mapChrome.divider),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: 16,
        color: context.mapChrome.primary,
      ),
    );
  }

  Widget _buildRecipeMaterialTile(
    BuildContext context, {
    required BdoPlannerNeedGroup group,
    required BdoPlannerNeedMaterial material,
  }) {
    final resource = _resourceFor(material.need);
    final available = resource == null ? 0 : _availableNodeCount(resource);
    final vendor = material.need.vendorPurchaseAvailable;
    final eligible = !vendor && resource != null && available > 0;
    final selected =
        eligible &&
        _selection.isMaterialSelected(
          groupId: group.id,
          materialId: material.id,
        );
    final count = resource == null
        ? 0
        : _nodeCountsByResourceId[resource.id] ?? available;
    final status = vendor
        ? 'Vendor item · no CP investment'
        : available == 0
        ? 'No reachable worker node'
        : '$available worker nodes · Need '
              '${_formatMapQuantity(material.need.missingQuantity)}';
    return Tooltip(
      message: status,
      child: CheckboxListTile(
        key: ValueKey<String>(
          'resource-map-recipe-material-${group.id}-${material.id}',
        ),
        contentPadding: const EdgeInsets.only(left: 18, right: 4),
        visualDensity: VisualDensity.compact,
        value: selected,
        secondary: _materialIcon(context, material.need),
        title: Text(
          material.need.name,
          softWrap: true,
          style: TextStyle(
            color: eligible ? context.mapChrome.text : context.mapChrome.muted,
            fontSize: ResourceMapPanelMetrics.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: !eligible
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (eligible)
                    Text(
                      'Need ${_formatMapQuantity(material.need.missingQuantity)}',
                      softWrap: true,
                      style: TextStyle(
                        color: context.mapChrome.muted,
                        fontSize: ResourceMapPanelMetrics.secondary,
                      ),
                    ),
                  if (selected) ...<Widget>[
                    const SizedBox(height: 3),
                    _RecipeNodeCountControl(
                      controlId: '${group.id}-${material.id}',
                      resourceName: resource.name,
                      count: count,
                      maximum: available,
                      onRemove: () => _updateSelection(
                        _selection.withMaterialSelected(
                          groupId: group.id,
                          materialId: material.id,
                          selected: false,
                        ),
                      ),
                      onDecrease: count > 1
                          ? () => _changeNodeCount(resource, count - 1)
                          : null,
                      onIncrease: count < available
                          ? () => _changeNodeCount(resource, count + 1)
                          : null,
                    ),
                  ],
                ],
              ),
        onChanged: eligible
            ? (value) => _updateSelection(
                _selection.withMaterialSelected(
                  groupId: group.id,
                  materialId: material.id,
                  selected: value ?? false,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _recommendation.networkResult?.plan;
    final selectedWorkerMaterialCount =
        _selection.selectedPositiveWorkerPlannerNeeds.length;
    return DraggableAlertDialog(
      identity: 'planner-need-selection',
      estimatedSize: const Size(410, 500),
      scrollable: true,
      title: const _AtlasDialogTitle(
        icon: Icons.restaurant_menu_rounded,
        title: 'Recipe materials',
        subtitle: 'Cooking and Alchemy share one worker route.',
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (selectedWorkerMaterialCount > 0 && plan == null)
              Text(
                'No route available.',
                key: const ValueKey('resource-map-recipe-live-cp-preview'),
                style: TextStyle(
                  color: context.mapChrome.error,
                  fontSize: ResourceMapPanelMetrics.secondary,
                ),
              ),

            Divider(height: 1),
            const SizedBox(height: 4),
            for (final group in _selection.groups)
              ExpansionTile(
                key: PageStorageKey<String>(
                  'resource-map-recipe-group-${group.id}',
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                dense: true,
                visualDensity: VisualDensity.compact,
                iconColor: context.mapChrome.primary,
                collapsedIconColor: context.mapChrome.muted,
                shape: Border(
                  bottom: BorderSide(color: context.mapChrome.divider),
                ),
                collapsedShape: Border(
                  bottom: BorderSide(color: context.mapChrome.divider),
                ),
                leading: Checkbox(
                  tristate: true,
                  value: _eligibleGroupValue(group),
                  onChanged: _eligibleGroupCounts(group).total == 0
                      ? null
                      : (value) => _updateSelection(
                          _withEligibleGroupSelected(group, value ?? true),
                        ),
                ),
                title: Text(
                  group.label,
                  style: TextStyle(
                    color: context.mapChrome.ink,
                    fontSize: ResourceMapPanelMetrics.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                children: <Widget>[
                  for (final material in group.materials)
                    _buildRecipeMaterialTile(
                      context,
                      group: group,
                      material: material,
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>(
            'resource-map-optimize-selected-recipe-materials',
          ),
          onPressed:
              selectedWorkerMaterialCount == 0 ||
                  _recommendation.networkResult?.plan == null
              ? null
              : () => Navigator.of(context).pop(
                  _PlannerNeedSelectionResult(
                    selection: _selection,
                    materialTargets: _materialTargets(),
                  ),
                ),
          icon: const Icon(Icons.route_rounded, size: 17),
          label: const Text('Use selection'),
        ),
      ],
    );
  }
}

class _RecipeNodeCountControl extends StatelessWidget {
  const _RecipeNodeCountControl({
    required this.controlId,
    required this.resourceName,
    required this.count,
    required this.maximum,
    required this.onRemove,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String controlId;
  final String resourceName;
  final int count;
  final int maximum;
  final VoidCallback onRemove;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required Key key,
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) => SizedBox.square(
      dimension: ResourceMapPanelMetrics.controlTarget,
      child: MapQuietIconButton(
        key: key,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: context.mapChrome.ink,
          disabledForegroundColor: context.mapChrome.muted.withValues(
            alpha: .38,
          ),
          hoverColor: context.mapChrome.brassWash,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        icon: Icon(icon, size: 15),
      ),
    );

    return Semantics(
      label: '$resourceName, $count of $maximum worker nodes',
      child: Container(
        key: ValueKey<String>('resource-map-recipe-node-count-$controlId'),
        constraints: const BoxConstraints(
          minHeight: ResourceMapPanelMetrics.controlTarget + 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: context.mapChrome.graphiteRaised,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              context.mapChrome.graphiteHighlight,
              context.mapChrome.graphiteRaised,
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.mapChrome.brassDeep),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            button(
              key: ValueKey<String>(
                'resource-map-recipe-node-remove-$controlId',
              ),
              tooltip: 'Remove $resourceName',
              icon: Icons.close_rounded,
              onPressed: onRemove,
            ),
            button(
              key: ValueKey<String>(
                'resource-map-recipe-node-minus-$controlId',
              ),
              tooltip: 'Use one fewer $resourceName node',
              icon: Icons.remove_rounded,
              onPressed: onDecrease,
            ),
            SizedBox(
              width: 35,
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            button(
              key: ValueKey<String>('resource-map-recipe-node-plus-$controlId'),
              tooltip: 'Use one more $resourceName node',
              icon: Icons.add_rounded,
              onPressed: onIncrease,
            ),
          ],
        ),
      ),
    );
  }
}

final class _WorkerIncomeSettings {
  const _WorkerIncomeSettings({
    required this.onlineHoursPerDay,
    required this.resourceAvailabilityPercent,
    required this.useObservedTradeVolume,
    required this.allowPartialPrices,
  });

  final double onlineHoursPerDay;
  final double resourceAvailabilityPercent;
  final bool useObservedTradeVolume;
  final bool allowPartialPrices;
}

class _WorkerIncomeSettingsDialog extends StatefulWidget {
  const _WorkerIncomeSettingsDialog({
    required this.onlineHoursPerDay,
    required this.resourceAvailabilityPercent,
    required this.useObservedTradeVolume,
    required this.allowPartialPrices,
  });

  final double onlineHoursPerDay;
  final double resourceAvailabilityPercent;
  final bool useObservedTradeVolume;
  final bool allowPartialPrices;

  @override
  State<_WorkerIncomeSettingsDialog> createState() =>
      _WorkerIncomeSettingsDialogState();
}

class _WorkerIncomeSettingsDialogState
    extends State<_WorkerIncomeSettingsDialog> {
  late final TextEditingController _onlineHoursController;
  late final TextEditingController _availabilityController;
  late bool _useObservedTradeVolume;
  late bool _allowPartialPrices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _onlineHoursController = TextEditingController(
      text: _formatCompactNumber(widget.onlineHoursPerDay),
    );
    _availabilityController = TextEditingController(
      text: _formatCompactNumber(widget.resourceAvailabilityPercent),
    );
    _useObservedTradeVolume = widget.useObservedTradeVolume;
    _allowPartialPrices = widget.allowPartialPrices;
  }

  @override
  void dispose() {
    _onlineHoursController.dispose();
    _availabilityController.dispose();
    super.dispose();
  }

  void _save() {
    final hours = double.tryParse(_onlineHoursController.text.trim());
    final availability = double.tryParse(_availabilityController.text.trim());
    if (hours == null ||
        !hours.isFinite ||
        hours <= 0 ||
        hours > 24 ||
        availability == null ||
        !availability.isFinite ||
        availability < 0 ||
        availability > 100) {
      setState(() {
        _error = 'Hours: >0–24. Resources: 0–100%.';
      });
      return;
    }
    Navigator.of(context).pop(
      _WorkerIncomeSettings(
        onlineHoursPerDay: hours,
        resourceAvailabilityPercent: availability,
        useObservedTradeVolume: _useObservedTradeVolume,
        allowPartialPrices: _allowPartialPrices,
      ),
    );
  }

  Widget _numberField({
    required String label,
    required String inputKey,
    required TextEditingController controller,
    required double width,
  }) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              color: context.mapChrome.muted,
              fontSize: ResourceMapPanelMetrics.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: TextField(
            key: ValueKey<String>(inputKey),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fieldWidth = MediaQuery.textScalerOf(context).scale(150) <= 154
        ? 154.0
        : 320.0;
    return DraggableAlertDialog(
      identity: 'worker-income-settings',
      estimatedSize: const Size(380, 280),
      scrollable: true,
      title: const _AtlasDialogTitle(
        icon: Icons.tune_rounded,
        title: 'Income settings',
        subtitle: 'Online time and node resources.',
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              key: const ValueKey('resource-map-income-numeric-fields'),
              spacing: 12,
              runSpacing: 12,
              children: [
                _numberField(
                  label: 'Online hours/day',
                  inputKey: 'resource-map-online-hours-input',
                  controller: _onlineHoursController,
                  width: fieldWidth,
                ),
                _numberField(
                  label: 'Node resources (%)',
                  inputKey: 'resource-map-availability-input',
                  controller: _availabilityController,
                  width: fieldWidth,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1),
            const SizedBox(height: 5),
            SwitchListTile.adaptive(
              value: _useObservedTradeVolume,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Avoid slow sellers',
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),

              onChanged: (value) =>
                  setState(() => _useObservedTradeVolume = value),
            ),
            SwitchListTile.adaptive(
              value: _allowPartialPrices,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Allow partial prices',
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),

              onChanged: (value) => setState(() => _allowPartialPrices = value),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: 5),
              Text(
                error,
                style: TextStyle(
                  color: context.mapChrome.error,
                  fontSize: ResourceMapPanelMetrics.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('resource-map-save-income-settings'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

final class _WorkerTownLodgingContext {
  const _WorkerTownLodgingContext({
    required this.baseWorkerSlotCount,
    required this.activeOwnedLodgingSlotCount,
  });

  final int baseWorkerSlotCount;
  final int activeOwnedLodgingSlotCount;

  int get knownSlotCount => baseWorkerSlotCount + activeOwnedLodgingSlotCount;
}

class _WorkerCapacityDialog extends StatefulWidget {
  const _WorkerCapacityDialog({
    required this.towns,
    required this.initialValues,
    required this.lodgingContextByTownNodeId,
  });

  final List<BdoWorkerNode> towns;
  final Map<String, BdoTownWorkerCapacity> initialValues;
  final Map<String, _WorkerTownLodgingContext> lodgingContextByTownNodeId;

  @override
  State<_WorkerCapacityDialog> createState() => _WorkerCapacityDialogState();
}

class _WorkerCapacityDialogState extends State<_WorkerCapacityDialog> {
  final Map<String, _TownCapacityDraft> _drafts =
      <String, _TownCapacityDraft>{};
  final Map<String, BdoTownWorkerCapacity> _unknownInitialValues =
      <String, BdoTownWorkerCapacity>{};
  String? _townToAdd;
  String? _error;

  Map<String, BdoWorkerNode> get _townsById => <String, BdoWorkerNode>{
    for (final town in widget.towns) town.id: town,
  };

  _WorkerTownLodgingContext _lodgingContext(String townNodeId) =>
      widget.lodgingContextByTownNodeId[townNodeId] ??
      const _WorkerTownLodgingContext(
        baseWorkerSlotCount: 0,
        activeOwnedLodgingSlotCount: 0,
      );

  _TownCapacityDraft _createDraft(
    String townNodeId,
    BdoTownWorkerCapacity value,
  ) => _TownCapacityDraft(
    value,
    knownSlotCount: _lodgingContext(townNodeId).knownSlotCount,
  );

  @override
  void initState() {
    super.initState();
    final knownIds = widget.towns.map((town) => town.id).toSet();
    for (final entry in widget.initialValues.entries) {
      if (knownIds.contains(entry.key)) {
        _drafts[entry.key] = _createDraft(entry.key, entry.value);
      } else {
        _unknownInitialValues[entry.key] = entry.value;
      }
    }
    _townToAdd = _availableTowns().firstOrNull?.id;
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  List<BdoWorkerNode> _availableTowns() => widget.towns
      .where((town) => !_drafts.containsKey(town.id))
      .toList(growable: false);

  void _addTown() {
    final id = _townToAdd;
    if (id == null || _drafts.containsKey(id)) {
      return;
    }
    setState(() {
      _drafts[id] = _createDraft(
        id,
        const BdoTownWorkerCapacity(
          availableWorkerCount: 0,
          freeLodgingSlotCount: 0,
          hiredWorkerCount: 0,
          bonusLodgingSlotCount: 0,
        ),
      );
      _townToAdd = _availableTowns().firstOrNull?.id;
      _error = null;
    });
  }

  void _removeTown(String id) {
    setState(() {
      final draft = _drafts[id];
      if (draft != null && draft.hasLodgingToPreserve) {
        draft.hiredWorkers.text = '0';
        _error = null;
        return;
      }
      _drafts.remove(id)?.dispose();
      _townToAdd ??= _availableTowns().firstOrNull?.id;
      _error = null;
    });
  }

  void _save() {
    final values = <String, BdoTownWorkerCapacity>{..._unknownInitialValues};
    for (final entry in _drafts.entries) {
      final draft = entry.value;
      if (draft.isUnchanged) {
        values[entry.key] = draft.originalValue;
        continue;
      }
      final hiredWorkers = int.tryParse(draft.hiredWorkers.text.trim());
      final bonusLodging = int.tryParse(draft.bonusLodgingSlots.text.trim());
      if (hiredWorkers == null ||
          hiredWorkers < 0 ||
          bonusLodging == null ||
          bonusLodging < 0) {
        setState(() {
          _error =
              'Hired-worker and bonus-lodging counts must be whole numbers '
              'of at least 0.';
        });
        return;
      }
      final knownSlotCount =
          _lodgingContext(entry.key).knownSlotCount + bonusLodging;
      final preserveBonusBreakdown =
          draft.originalValue.hasBonusLodgingBreakdown &&
          bonusLodging == draft.originalValue.effectiveBonusLodgingSlotCount;
      values[entry.key] = BdoTownWorkerCapacity(
        availableWorkerCount: hiredWorkers,
        freeLodgingSlotCount: math.max(knownSlotCount - hiredWorkers, 0),
        hiredWorkerCount: hiredWorkers,
        bonusLodgingSlotCount: bonusLodging,
        pearlLodgingPurchasedCount: preserveBonusBreakdown
            ? draft.originalValue.pearlLodgingPurchasedCount
            : null,
        loyaltyLodgingPurchasedCount: preserveBonusBreakdown
            ? draft.originalValue.loyaltyLodgingPurchasedCount
            : null,
        otherBonusLodgingSlotCount: preserveBonusBreakdown
            ? draft.originalValue.otherBonusLodgingSlotCount
            : null,
      );
    }
    Navigator.of(context).pop(values);
  }

  Widget _townSelector(List<BdoWorkerNode> available, double width) {
    return InputDecorator(
      isEmpty: _townToAdd == null,
      decoration: const InputDecoration(
        labelText: 'Add a worker town',
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey<String>('resource-map-worker-town-add'),
          value: _townToAdd,
          isExpanded: true,
          itemHeight: null,
          menuMaxHeight: MediaQuery.sizeOf(context).height * .65,
          menuWidth: readableSelectMenuWidth(
            context,
            available.map((town) => town.siteName),
            triggerWidth: width,
          ),
          items: [
            for (final town in available)
              DropdownMenuItem(
                value: town.id,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(town.siteName, softWrap: true),
                ),
              ),
          ],
          onChanged: (value) => setState(() => _townToAdd = value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final townsById = _townsById;
    final entries = _drafts.entries.toList()
      ..sort((left, right) {
        final leftName = townsById[left.key]?.siteName ?? left.key;
        final rightName = townsById[right.key]?.siteName ?? right.key;
        return leftName.toLowerCase().compareTo(rightName.toLowerCase());
      });
    final available = _availableTowns();
    if (_townToAdd != null && !available.any((town) => town.id == _townToAdd)) {
      _townToAdd = available.firstOrNull?.id;
    }
    final contentWidth = math.max(
      0.0,
      math.min(340.0, MediaQuery.sizeOf(context).width - 128),
    );
    final stackControls =
        contentWidth < 300 || MediaQuery.textScalerOf(context).scale(14) > 19;
    final fieldWidth = stackControls ? contentWidth : (contentWidth - 10) / 2;
    return DraggableAlertDialog(
      identity: 'worker-capacity',
      dialogKey: const ValueKey('resource-map-existing-workers-dialog'),
      estimatedSize: const Size(390, 400),
      scrollable: true,
      title: const _AtlasDialogTitle(
        icon: Icons.groups_2_outlined,
        title: 'Existing workers',
        subtitle: 'Hired workers and saved lodging outside the house map.',
      ),
      content: SizedBox(
        width: contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (stackControls)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _townSelector(available, contentWidth),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const ValueKey<String>(
                        'resource-map-worker-town-add-action',
                      ),
                      onPressed: _townToAdd == null ? null : _addTown,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add town'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: <Widget>[
                  Expanded(child: _townSelector(available, contentWidth - 56)),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const ValueKey<String>(
                      'resource-map-worker-town-add-action',
                    ),
                    onPressed: _townToAdd == null ? null : _addTown,
                    tooltip: 'Add town',
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (entries.isNotEmpty)
              Column(
                children: [
                  for (final entry in entries) ...[
                    if (entry != entries.first) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  townsById[entry.key]!.siteName,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: context.mapChrome.ink,
                                    fontSize: ResourceMapPanelMetrics.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                key: ValueKey(
                                  'resource-map-clear-workers-${entry.key}',
                                ),
                                onPressed: () => _removeTown(entry.key),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: Text(
                                  entry.value.hasLodgingToPreserve
                                      ? 'Clear workers'
                                      : 'Remove',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Flex(
                            direction: stackControls
                                ? Axis.vertical
                                : Axis.horizontal,
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(
                                width: fieldWidth,
                                child: TextField(
                                  key: ValueKey<String>(
                                    'resource-map-hired-workers-${entry.key}',
                                  ),
                                  controller: entry.value.hiredWorkers,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Hired workers',
                                    prefixIcon: Icon(
                                      Icons.engineering_outlined,
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {
                                    _error = null;
                                  }),
                                ),
                              ),
                              SizedBox(
                                width: stackControls ? 0 : 10,
                                height: stackControls ? 10 : 0,
                              ),
                              SizedBox(
                                width: fieldWidth,
                                child: TextField(
                                  key: ValueKey<String>(
                                    'resource-map-bonus-lodging-${entry.key}',
                                  ),
                                  controller: entry.value.bonusLodgingSlots,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Bonus lodging slots',
                                    prefixIcon: Icon(Icons.bed_outlined),
                                  ),
                                  onChanged: (_) => setState(() {
                                    _error = null;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                error,
                style: TextStyle(
                  color: context.mapChrome.error,
                  fontSize: ResourceMapPanelMetrics.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

final class _TownCapacityDraft {
  _TownCapacityDraft(this.originalValue, {required int knownSlotCount})
    : _initialHiredText =
          '${originalValue.hiredWorkerCount ?? originalValue.availableWorkerCount}',
      _initialBonusText =
          '${_initialBonusLodging(originalValue, knownSlotCount)}',
      hiredWorkers = TextEditingController(
        text:
            '${originalValue.hiredWorkerCount ?? originalValue.availableWorkerCount}',
      ),
      bonusLodgingSlots = TextEditingController(
        text: '${_initialBonusLodging(originalValue, knownSlotCount)}',
      );

  final BdoTownWorkerCapacity originalValue;
  final String _initialHiredText;
  final String _initialBonusText;
  final TextEditingController hiredWorkers;
  final TextEditingController bonusLodgingSlots;

  bool get isUnchanged =>
      hiredWorkers.text.trim() == _initialHiredText &&
      bonusLodgingSlots.text.trim() == _initialBonusText;

  bool get hasLodgingToPreserve =>
      (int.tryParse(_initialBonusText) ?? 0) > 0 ||
      (int.tryParse(bonusLodgingSlots.text.trim()) ??
              originalValue.effectiveBonusLodgingSlotCount) >
          0;

  static int _initialBonusLodging(
    BdoTownWorkerCapacity value,
    int knownSlotCount,
  ) {
    final savedBonus = value.bonusLodgingSlotCount;
    if (value.hasBonusLodgingBreakdown) {
      return value.effectiveBonusLodgingSlotCount;
    }
    if (savedBonus != null) {
      return savedBonus;
    }
    final legacyTotal = value.availableWorkerCount + value.freeLodgingSlotCount;
    return math.max(legacyTotal - knownSlotCount, 0);
  }

  void dispose() {
    hiredWorkers.dispose();
    bonusLodgingSlots.dispose();
  }
}

class _NodeRootPickerDialog extends StatefulWidget {
  const _NodeRootPickerDialog({
    required this.roots,
    required this.initialUseAll,
    required this.initialIds,
  });

  final List<BdoWorkerNode> roots;
  final bool initialUseAll;
  final Set<String> initialIds;

  @override
  State<_NodeRootPickerDialog> createState() => _NodeRootPickerDialogState();
}

class _NodeRootPickerDialogState extends State<_NodeRootPickerDialog> {
  late bool _useAll;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _useAll = widget.initialUseAll;
    _selectedIds = Set<String>.of(widget.initialIds);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableAlertDialog(
      identity: 'node-root-picker',
      estimatedSize: const Size(370, 500),
      scrollable: true,
      title: const _AtlasDialogTitle(
        icon: Icons.location_city_rounded,
        title: 'Starting towns',
        subtitle: 'Unchecked towns are excluded from the plan.',
      ),
      contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      content: SizedBox(
        width: 310,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'All towns',
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),

              value: _useAll,
              onChanged: (value) {
                setState(() {
                  _useAll = value;
                  if (value) {
                    _selectedIds = widget.roots.map((node) => node.id).toSet();
                  }
                });
              },
            ),
            Divider(height: 1),
            for (final root in widget.roots)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _useAll || _selectedIds.contains(root.id),
                onChanged: _useAll
                    ? null
                    : (selected) {
                        setState(() {
                          if (selected ?? false) {
                            _selectedIds.add(root.id);
                          } else {
                            _selectedIds.remove(root.id);
                          }
                        });
                      },
                title: Text(
                  root.siteName,
                  style: TextStyle(
                    color: context.mapChrome.text,
                    fontSize: ResourceMapPanelMetrics.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('resource-map-save-starting-towns'),
          onPressed: _useAll || _selectedIds.isNotEmpty
              ? () => Navigator.of(context).pop(
                  _NodeRootSelection(
                    useAll: _useAll,
                    nodeIds: Set<String>.unmodifiable(_selectedIds),
                  ),
                )
              : null,
          child: Text(
            !_useAll && _selectedIds.isEmpty
                ? 'Choose a town'
                : 'Use selection',
          ),
        ),
      ],
    );
  }
}

extension on _NodeTargetGroup {
  String get label => switch (this) {
    _NodeTargetGroup.woodSap => 'Wood & sap',
    _NodeTargetGroup.cropsPlants => 'Crops & plants',
    _NodeTargetGroup.oresMinerals => 'Ores & traces',
    _NodeTargetGroup.fishMarine => 'Fish & marine',
    _NodeTargetGroup.mushrooms => 'Mushrooms',
    _NodeTargetGroup.animalProducts => 'Animal products',
    _NodeTargetGroup.other => 'Other materials',
  };

  IconData get icon => switch (this) {
    _NodeTargetGroup.woodSap => Icons.forest_outlined,
    _NodeTargetGroup.cropsPlants => Icons.grass_outlined,
    _NodeTargetGroup.oresMinerals => Icons.diamond_outlined,
    _NodeTargetGroup.fishMarine => Icons.set_meal_outlined,
    _NodeTargetGroup.mushrooms => Icons.eco_outlined,
    _NodeTargetGroup.animalProducts => Icons.pets_outlined,
    _NodeTargetGroup.other => Icons.auto_awesome_mosaic_outlined,
  };
}

extension on BdoResourceSection {
  String get label => switch (this) {
    BdoResourceSection.plantsWood => 'Plants & wood',
    BdoResourceSection.oresMinerals => 'Ores & minerals',
    BdoResourceSection.meat => 'Meat',
    BdoResourceSection.bloodHides => 'Blood & hides',
    BdoResourceSection.mushrooms => 'Mushrooms',
    BdoResourceSection.seafoodMarine => 'Fish & marine',
    BdoResourceSection.other => 'Other',
  };
}

class _WorkerOutputArtwork {
  const _WorkerOutputArtwork({required this.name, required this.resource});

  final String name;
  final BdoResourceDefinition? resource;
}

class _VendorPickerEntry {
  const _VendorPickerEntry({required this.vendor, required this.priceSilver});

  final BdoVendorNpc vendor;
  final int? priceSilver;
}

Widget _buildVendorPortrait(
  BuildContext context, {
  required BdoVendorNpc vendor,
  required double size,
  required BdoVendorPortraitBuilder? builder,
  required Color fallbackColor,
}) => ExcludeSemantics(
  child: SizedBox.square(
    dimension: size,
    child:
        builder?.call(context, vendor, size) ??
        Icon(Icons.person_rounded, color: fallbackColor, size: size),
  ),
);

const double _vendorPickerPortraitSize = 40;
const double _vendorDetailsPortraitSize = 80;

class _VendorClusterPickerCard extends StatelessWidget {
  const _VendorClusterPickerCard({
    required this.itemName,
    required this.itemIcon,
    required this.entries,
    required this.portraitBuilder,
    required this.maximumHeight,
    required this.onClose,
    required this.onSelected,
  });

  final String itemName;
  final Widget itemIcon;
  final List<_VendorPickerEntry> entries;
  final BdoVendorPortraitBuilder? portraitBuilder;
  final double maximumHeight;
  final VoidCallback onClose;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maximumHeight),
      child: Material(
        elevation: 18,
        shadowColor: const Color(0x6B17100F),
        color: chrome.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: chrome.primary.withAlpha(176)),
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: chrome.surfaceGradient),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: chrome.primary.withAlpha(34),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: chrome.primary.withAlpha(118),
                        ),
                      ),
                      child: itemIcon,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${entries.length} NPC sellers nearby',
                            style: chrome.headingStyle(
                              fontSize: ResourceMapPanelMetrics.heading,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            itemName,
                            style: TextStyle(
                              color: chrome.muted,
                              fontSize: ResourceMapPanelMetrics.secondary,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MapQuietIconButton(
                      key: const ValueKey<String>(
                        'resource-map-close-vendor-cluster-picker',
                      ),
                      tooltip: 'Close seller choices',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, thickness: 1, color: chrome.divider),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final vendor = entry.vendor;
                      final price = entry.priceSilver;
                      final label = StringBuffer(
                        '${vendor.name}, ${vendor.role}',
                      );
                      if (price != null) {
                        label.write(', ${_formatVendorSilver(price)} silver');
                      }
                      return Semantics(
                        button: true,
                        label: label.toString(),
                        onTap: () => onSelected(vendor.id),
                        child: ExcludeSemantics(
                          child: InkWell(
                            key: ValueKey<String>(
                              'resource-map-vendor-cluster-choice-${vendor.id}',
                            ),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onSelected(vendor.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Row(
                                children: <Widget>[
                                  _buildVendorPortrait(
                                    context,
                                    vendor: vendor,
                                    size: _vendorPickerPortraitSize,
                                    builder: portraitBuilder,
                                    fallbackColor: chrome.primary,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          vendor.name,
                                          style: const TextStyle(
                                            fontSize:
                                                ResourceMapPanelMetrics.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '<${vendor.role}>',
                                          style: TextStyle(
                                            color: chrome.accent,
                                            fontSize: ResourceMapPanelMetrics
                                                .secondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (price != null)
                                          Text(
                                            '${_formatVendorSilver(price)} silver',
                                            style: TextStyle(
                                              color: chrome.positive,
                                              fontSize: ResourceMapPanelMetrics
                                                  .secondary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: chrome.muted,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VendorScreenCluster {
  _VendorScreenCluster(BdoVendorNpc vendor, Offset position)
    : vendors = <BdoVendorNpc>[vendor],
      _positionTotal = position;

  final List<BdoVendorNpc> vendors;
  Offset _positionTotal;

  Offset get center => _positionTotal / vendors.length.toDouble();

  void add(BdoVendorNpc vendor, Offset position) {
    vendors.add(vendor);
    _positionTotal += position;
  }
}

class _VendorClusterMarker extends StatelessWidget {
  const _VendorClusterMarker({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Tooltip(
      message: '$count NPC seller locations · choose a seller',
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        label: '$count NPC seller locations. Choose a seller.',
        button: true,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              radius: 26,
              onTap: onPressed,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: chrome.selectedControlGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: chrome.accent, width: 1.5),
                      boxShadow: <BoxShadow>[
                        chrome.selectedShadow,
                        const BoxShadow(
                          color: Color(0x7A17100F),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: chrome.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VendorMapMarker extends StatefulWidget {
  const _VendorMapMarker({
    required this.vendor,
    required this.selected,
    required this.onPressed,
    this.portrait,
  });

  final BdoVendorNpc vendor;
  final Widget? portrait;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_VendorMapMarker> createState() => _VendorMapMarkerState();
}

class _VendorMapMarkerState extends State<_VendorMapMarker> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final highlighted = widget.selected || _hovered;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final semanticLabel =
        '${widget.vendor.name}, ${widget.vendor.role}. '
        'NPC seller map location.';
    return Tooltip(
      message: '${widget.vendor.name} · ${widget.vendor.role}',
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        label: semanticLabel,
        button: true,
        onTap: widget.onPressed,
        child: ExcludeSemantics(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: highlighted ? 1.13 : 1,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  radius: 24,
                  onTap: widget.onPressed,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: widget.portrait == null
                        ? Icon(
                            Icons.location_on_rounded,
                            size: 46,
                            color: highlighted ? chrome.accent : chrome.primary,
                            shadows: const <Shadow>[
                              Shadow(
                                color: Color(0xB017100F),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          )
                        : Center(
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: chrome.paperRaised,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: highlighted
                                      ? chrome.accent
                                      : chrome.primary,
                                ),
                              ),
                              child: widget.portrait,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VendorNpcMapCard extends StatelessWidget {
  const _VendorNpcMapCard({
    required this.vendor,
    required this.itemName,
    required this.itemIcon,
    required this.portraitBuilder,
    required this.priceSilver,
    required this.maximumHeight,
    required this.onClose,
  });

  final BdoVendorNpc vendor;
  final String itemName;
  final Widget itemIcon;
  final BdoVendorPortraitBuilder? portraitBuilder;
  final int? priceSilver;
  final double maximumHeight;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final price = priceSilver;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maximumHeight),
      child: Material(
        elevation: 18,
        shadowColor: const Color(0x6B17100F),
        color: chrome.paperRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: chrome.primary.withAlpha(176)),
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: chrome.surfaceGradient),
          child: SingleChildScrollView(
            primary: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildVendorPortrait(
                        context,
                        vendor: vendor,
                        size: _vendorDetailsPortraitSize,
                        builder: portraitBuilder,
                        fallbackColor: chrome.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              vendor.name,
                              style: chrome.headingStyle(
                                fontSize: ResourceMapPanelMetrics.heading,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '<${vendor.role}>',
                              style: TextStyle(
                                color: chrome.accent,
                                fontSize: ResourceMapPanelMetrics.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      MapQuietIconButton(
                        key: ValueKey<String>(
                          'resource-map-close-vendor-details-${vendor.id}',
                        ),
                        tooltip: 'Close seller details',
                        visualDensity: VisualDensity.compact,
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: chrome.fillAlpha(chrome.paper, 218 / 255),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: chrome.divider),
                    ),
                    child: Row(
                      children: <Widget>[
                        SizedBox.square(
                          dimension: ResourceMapPanelMetrics.artwork,
                          child: itemIcon,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                itemName,
                                style: const TextStyle(
                                  fontSize: ResourceMapPanelMetrics.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (price != null)
                                Text(
                                  '${_formatVendorSilver(price)} silver',
                                  style: TextStyle(
                                    color: chrome.positive,
                                    fontSize: ResourceMapPanelMetrics.secondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
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
}

String _formatVendorSilver(int value) {
  final digits = value.toString();
  final output = StringBuffer();
  for (var index = 0; index < digits.length; index += 1) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      output.write('.');
    }
    output.write(digits[index]);
  }
  return output.toString();
}

class _MapNavigationEntry {
  const _MapNavigationEntry({
    required this.label,
    required this.camera,
    required this.desktopTaskSurfaceCollapsed,
    required this.desktopSheetExpanded,
    required this.materialCatalogOpen,
    required this.selectedFieldSourceId,
    required this.selectedResourceId,
    required this.selectedNodeId,
    required this.selectedHouseId,
    required this.selectedSpotId,
    required this.selectedPointId,
    required this.selectedRouteId,
    required this.vendorLookupItemName,
    required this.selectedVendorId,
    required this.gatherChecklistOpen,
    required this.gatherPlanShortlistOpen,
    required this.housingDirectoryOpen,
    required this.royalWorkshopOpen,
    required this.nodeNetworkPlannerOpen,
    required this.nodeNetworkPlannerPage,
    required this.browseAllWorkerNodes,
    required this.workerOverviewSelectionMade,
    required this.workerActivityFilter,
    required this.materialSourceFilter,
    required this.mapSearchScope,
    required this.selectedResourceSection,
    required this.browseFavorites,
    required this.showWorkerNodes,
    required this.showGathering,
    required this.showRoutes,
    required this.showConnections,
    required this.searchText,
    required this.searchResultsVisible,
  });

  final String label;
  final BdoMapCamera camera;
  final bool desktopTaskSurfaceCollapsed;
  final bool desktopSheetExpanded;
  final bool materialCatalogOpen;
  final String? selectedFieldSourceId;
  final String? selectedResourceId;
  final String? selectedNodeId;
  final String? selectedHouseId;
  final String? selectedSpotId;
  final String? selectedPointId;
  final String? selectedRouteId;
  final String? vendorLookupItemName;
  final String? selectedVendorId;
  final bool gatherChecklistOpen;
  final bool gatherPlanShortlistOpen;
  final bool housingDirectoryOpen;
  final bool royalWorkshopOpen;
  final bool nodeNetworkPlannerOpen;
  final _NodeNetworkPlannerPage nodeNetworkPlannerPage;
  final bool browseAllWorkerNodes;
  final bool workerOverviewSelectionMade;
  final BdoWorkerActivity? workerActivityFilter;
  final _MaterialSourceFilter materialSourceFilter;
  final _MapSearchScope mapSearchScope;
  final BdoResourceSection? selectedResourceSection;
  final bool browseFavorites;
  final bool showWorkerNodes;
  final bool showGathering;
  final bool showRoutes;
  final bool showConnections;
  final String searchText;
  final bool searchResultsVisible;

  bool sameDestination(_MapNavigationEntry other) {
    return desktopTaskSurfaceCollapsed == other.desktopTaskSurfaceCollapsed &&
        materialCatalogOpen == other.materialCatalogOpen &&
        desktopSheetExpanded == other.desktopSheetExpanded &&
        selectedFieldSourceId == other.selectedFieldSourceId &&
        selectedResourceId == other.selectedResourceId &&
        selectedNodeId == other.selectedNodeId &&
        selectedHouseId == other.selectedHouseId &&
        selectedSpotId == other.selectedSpotId &&
        selectedPointId == other.selectedPointId &&
        selectedRouteId == other.selectedRouteId &&
        vendorLookupItemName == other.vendorLookupItemName &&
        selectedVendorId == other.selectedVendorId &&
        gatherChecklistOpen == other.gatherChecklistOpen &&
        gatherPlanShortlistOpen == other.gatherPlanShortlistOpen &&
        housingDirectoryOpen == other.housingDirectoryOpen &&
        royalWorkshopOpen == other.royalWorkshopOpen &&
        nodeNetworkPlannerOpen == other.nodeNetworkPlannerOpen &&
        nodeNetworkPlannerPage == other.nodeNetworkPlannerPage &&
        browseAllWorkerNodes == other.browseAllWorkerNodes &&
        workerOverviewSelectionMade == other.workerOverviewSelectionMade &&
        workerActivityFilter == other.workerActivityFilter &&
        materialSourceFilter == other.materialSourceFilter &&
        mapSearchScope == other.mapSearchScope &&
        selectedResourceSection == other.selectedResourceSection &&
        browseFavorites == other.browseFavorites &&
        searchText == other.searchText &&
        searchResultsVisible == other.searchResultsVisible;
  }
}

enum _HouseMarkerStatus {
  available,
  owned,
  recommendedLodging,
  recommendedStorage,
  recommendedHouseUse,
  recommendedPrerequisite,
}

String _displayHouseUsageLabel(HouseUsage usage) {
  if (usage.typeId == 3) {
    return 'Stable';
  }
  return usage.label;
}

BdoMapSymbolKind _houseSymbolKindForUsage(HouseUsage usage) {
  final label = usage.label.toLowerCase();
  if (usage.typeId == 0) return BdoMapSymbolKind.residence;
  if (usage.typeId == 1) return BdoMapSymbolKind.lodging;
  if (usage.typeId == 2) return BdoMapSymbolKind.storage;
  if (usage.typeId == 3) return BdoMapSymbolKind.stable;
  if (label.contains('ship') || label.contains('boat')) {
    return BdoMapSymbolKind.shipyard;
  }
  if (label.contains('refin') || label.contains('mill')) {
    return BdoMapSymbolKind.refinery;
  }
  return BdoMapSymbolKind.workshop;
}

BdoMapSymbolKind _houseSymbolKind(LodgingHouse house, int? activeUsageTypeId) {
  final usage =
      (house.usagesByTypeId[activeUsageTypeId] ??
      (house.supportsUsage(1)
          ? house.usagesByTypeId[1]
          : house.supportsUsage(2)
          ? house.usagesByTypeId[2]
          : house.supportsUsage(3)
          ? house.usagesByTypeId[3]
          : house.usages.first))!;
  return _houseSymbolKindForUsage(usage);
}

class _LodgingTownBadge extends StatelessWidget {
  const _LodgingTownBadge({
    required this.townName,
    required this.count,
    required this.ownedCount,
    required this.plannedCount,
    required this.planned,
    required this.onTap,
  });

  final String townName;
  final int count;
  final int ownedCount;
  final int plannedCount;
  final bool planned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final message = plannedCount == 0
        ? '$townName: $ownedCount saved houses. Open houses.'
        : '$townName: $ownedCount saved, $plannedCount to buy. Open lodging plan.';
    final color = planned
        ? context.mapChrome.positive
        : context.mapChrome.primary;
    return Tooltip(
      message: message,
      child: Semantics(
        button: true,
        label: message,
        child: Material(
          color: context.mapChrome.paperRaised,
          elevation: 7,
          shadowColor: const Color(0x660D1916),
          shape: CircleBorder(side: BorderSide(color: color, width: 2)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: 30,
              child: Center(
                child: Text(
                  '$count',
                  key: ValueKey<String>(
                    'resource-map-lodging-town-badge-count-$townName',
                  ),
                  style: TextStyle(
                    color: color,
                    // This is a numeric map badge inside an unchanged 30px
                    // marker, not instructional text or a menu label.
                    fontSize: count > 99 ? 9 : 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannedLodgingSummary extends StatelessWidget {
  const _PlannedLodgingSummary({
    required this.town,
    required this.plan,
    required this.onSelectHouse,
    required this.onClose,
  });

  final LodgingTown town;
  final LodgingPlan plan;
  final ValueChanged<LodgingHouse> onSelectHouse;
  final VoidCallback onClose;

  List<LodgingHouse> _houses(Iterable<String> ids) => ids
      .map((id) => town.housesById[id])
      .whereType<LodgingHouse>()
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final selectedLodgingIds = plan.selectedLodgingHouseIds.toSet();
    final ownedUsed = _houses(plan.ownedHouseIdsUsed);
    final lodgingToBuy = _houses(
      plan.newlyRequiredHouseIds.where(selectedLodgingIds.contains),
    );
    final prerequisiteToBuy = _houses(
      plan.newlyRequiredHouseIds.where(
        (id) => !selectedLodgingIds.contains(id),
      ),
    );

    Widget section({
      required String label,
      required List<LodgingHouse> houses,
      required IconData icon,
      required Color color,
    }) {
      if (houses.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: ResourceMapPanelMetrics.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            for (final house in houses)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey<String>(
                    'resource-map-planned-lodging-house-${house.id}',
                  ),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelectHouse(house),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            house.name,
                            style: TextStyle(
                              color: context.mapChrome.text,
                              fontSize: ResourceMapPanelMetrics.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${house.contributionPoints} CP',
                          style: TextStyle(
                            color: context.mapChrome.muted,
                            fontSize: ResourceMapPanelMetrics.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Material(
      elevation: 14,
      shadowColor: const Color(0x770D1916),
      color: context.mapChrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 10, 9, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: DraggableDialogDragHandle(
                    key: ValueKey<String>(
                      'resource-map-planned-lodging-summary-handle-'
                      '${town.townNodeId}',
                    ),
                    child: Row(
                      children: <Widget>[
                        BdoMapSymbol(
                          kind: BdoMapSymbolKind.lodging,
                          states: bdoMapSymbolStates(recommendedLodging: true),
                          size: 30,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${town.name} lodging',
                                style: TextStyle(
                                  color: context.mapChrome.ink,
                                  fontSize: ResourceMapPanelMetrics.heading,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                MapQuietIconButton(
                  key: ValueKey<String>(
                    'resource-map-close-planned-lodging-summary-'
                    '${town.townNodeId}',
                  ),
                  tooltip: 'Close lodging summary',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 17),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    section(
                      label: 'Use saved houses',
                      houses: ownedUsed,
                      icon: Icons.check_circle_outline_rounded,
                      color: context.mapChrome.primary,
                    ),
                    section(
                      label: 'Buy for lodging',
                      houses: lodgingToBuy,
                      icon: Icons.bed_rounded,
                      color: context.mapChrome.positive,
                    ),
                    section(
                      label: 'Buy first',
                      houses: prerequisiteToBuy,
                      icon: Icons.call_split_rounded,
                      color: context.mapChrome.warning,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HousingTownDirectoryRow extends StatelessWidget {
  const _HousingTownDirectoryRow({
    required this.town,
    required this.ownedCount,
    required this.onTap,
    super.key,
  });

  final LodgingTown town;
  final int ownedCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${town.houses.length} '
        '${town.houses.length == 1 ? 'house' : 'houses'}';
    final chrome = context.mapChrome;
    return Semantics(
      button: onTap != null,
      label:
          '${town.name}. $ownedCount saved houses. $subtitle. '
          'Open connected house network.',
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: ResourceMapPanelMetrics.optionGap,
        ),
        child: ResourceMapPill(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              hoverColor: chrome.ink.withValues(alpha: .055),
              focusColor: chrome.primary.withValues(alpha: .11),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: ResourceMapPanelMetrics.optionHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: <Widget>[
                    const ResourceMapStewardIcon(
                      kind: ResourceMapStewardIconKind.houses,
                      size: ResourceMapPanelMetrics.optionArtwork,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        town.name,
                        style: TextStyle(
                          color: chrome.ink,
                          fontSize: ResourceMapPanelMetrics.optionLabel,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: chrome.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StoragePlanHouseRole {
  ownedPrerequisite,
  storage,
  prerequisite;

  Color color(BuildContext context) => switch (this) {
    _StoragePlanHouseRole.ownedPrerequisite => context.mapChrome.primary,
    _StoragePlanHouseRole.storage => const Color(0xFF709EF0),
    _StoragePlanHouseRole.prerequisite => context.mapChrome.warning,
  };
}

/// Gives a newly selected house a short, unmistakable map reveal without
/// changing the camera or enlarging the marker's interactive hit target.
class _HouseSelectionPulse extends StatelessWidget {
  const _HouseSelectionPulse({
    required this.revision,
    required this.child,
    super.key,
  });

  final int revision;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(revision),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.linear,
        child: child,
        builder: (context, value, child) {
          final pulse = math.sin(value * math.pi * 3).abs();
          final glowAlpha = pulse * (.52 - value * .14);
          return Transform.scale(
            scale: 1 + pulse * .12,
            transformHitTests: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: context.mapChrome.accent.withValues(
                      alpha: glowAlpha,
                    ),
                    blurRadius: 7 + pulse * 11,
                    spreadRadius: pulse * 2.6,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _ScreenshotImportPulse extends StatelessWidget {
  const _ScreenshotImportPulse({
    required this.active,
    required this.revision,
    required this.child,
  });

  final bool active;
  final int revision;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return child;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(revision),
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 1800),
      curve: Curves.easeInOut,
      child: child,
      builder: (context, value, child) {
        final pulse = math.sin(value * math.pi * 4).abs();
        return Transform.scale(
          scale: 1 + pulse * .11,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: context.mapChrome.accent.withValues(
                    alpha: .18 + pulse * .34,
                  ),
                  blurRadius: 7 + pulse * 9,
                  spreadRadius: pulse * 2.5,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _HouseMapMarker extends StatelessWidget {
  const _HouseMapMarker({
    required this.house,
    required this.status,
    required this.selected,
    required this.activeUsageTypeId,
    required this.onTap,
  });

  final LodgingHouse house;
  final _HouseMarkerStatus status;
  final bool selected;
  final int? activeUsageTypeId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final states = bdoMapSymbolStates(
      owned: status == _HouseMarkerStatus.owned,
      recommendedLodging: status == _HouseMarkerStatus.recommendedLodging,
      recommendedStorage: status == _HouseMarkerStatus.recommendedStorage,
      recommendedHouseUse: status == _HouseMarkerStatus.recommendedHouseUse,
      recommendedPrerequisite:
          status == _HouseMarkerStatus.recommendedPrerequisite,
      selected: selected,
    );
    return Tooltip(
      message: '${house.name} · ${house.contributionPoints} CP',
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${house.name}, ${house.contributionPoints} contribution points, '
            '${status.name}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: BdoMapSymbol(
              kind: _houseSymbolKind(house, activeUsageTypeId),
              states: states,
              size: _houseMapMarkerSize.width,
              semanticLabel:
                  '${house.name}; ${bdoMapSymbolStyle(states).semanticStateLabel}',
            ),
          ),
        ),
      ),
    );
  }
}

class _HouseClusterMarker extends StatelessWidget {
  const _HouseClusterMarker({
    required this.count,
    required this.label,
    required this.kind,
    required this.states,
    required this.onTap,
  });

  final int count;
  final String label;
  final BdoMapSymbolKind kind;
  final Set<BdoMapSymbolState> states;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: _houseClusterMarkerSize.width,
              height: _houseClusterMarkerSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: BdoMapSymbol(
                      kind: kind,
                      states: states,
                      size: 34,
                      semanticLabel: label,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xF21A2826),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFE3C56C),
                          width: 1.2,
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Color(0x99000000), blurRadius: 3),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: TextStyle(
                            color: Color(0xFFFFE9A5),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
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
}

class _HouseUsageButton extends StatelessWidget {
  const _HouseUsageButton({
    required this.icon,
    required this.label,
    required this.level,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final int level;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? context.mapChrome.primary
        : context.mapChrome.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label level $level',
      child: Material(
        color: selected
            ? context.mapChrome.primary.withValues(alpha: .1)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? context.mapChrome.primary.withValues(alpha: .42)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
            child: Row(
              children: <Widget>[
                Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    color: selected
                        ? context.mapChrome.primary
                        : context.mapChrome.paper,
                    borderRadius: BorderRadius.circular(8),
                    border: selected
                        ? null
                        : Border.all(color: context.mapChrome.divider),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? context.mapChrome.onPrimary
                        : context.mapChrome.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: ResourceMapPanelMetrics.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'Lv. $level',
                  style: TextStyle(
                    color: selected
                        ? context.mapChrome.primary
                        : context.mapChrome.muted,
                    fontSize: ResourceMapPanelMetrics.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (selected) ...<Widget>[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: context.mapChrome.positive,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HousePrerequisitePainter extends CustomPainter {
  const _HousePrerequisitePainter({
    required this.town,
    required this.anchorIdByHouseId,
    required this.anchorPositions,
    required this.ownedHouseIds,
    required this.recommendedNewHouseIds,
    required this.selectedHouseId,
    required this.visibleHouseIds,
  });

  final LodgingTown town;
  final Map<String, String> anchorIdByHouseId;
  final Map<String, Offset> anchorPositions;
  final Set<String> ownedHouseIds;
  final Set<String> recommendedNewHouseIds;
  final String? selectedHouseId;
  final Set<String> visibleHouseIds;

  List<_HousePrerequisiteVisualEdge> get _visualEdges {
    final edgesByKey = <String, _HousePrerequisiteVisualEdge>{};
    for (final house in town.houses) {
      final prerequisiteId = house.prerequisiteHouseId;
      if (prerequisiteId == null ||
          !visibleHouseIds.contains(prerequisiteId) ||
          !visibleHouseIds.contains(house.id)) {
        continue;
      }
      final startAnchorId = anchorIdByHouseId[prerequisiteId] ?? prerequisiteId;
      final endAnchorId = anchorIdByHouseId[house.id] ?? house.id;
      if (startAnchorId == endAnchorId) {
        continue;
      }
      final start = anchorPositions[startAnchorId];
      final end = anchorPositions[endAnchorId];
      if (start == null || end == null) {
        continue;
      }
      final strength =
          selectedHouseId == prerequisiteId || selectedHouseId == house.id
          ? _HousePrerequisiteEdgeStrength.selected
          : recommendedNewHouseIds.contains(prerequisiteId) ||
                recommendedNewHouseIds.contains(house.id)
          ? _HousePrerequisiteEdgeStrength.recommended
          : ownedHouseIds.contains(prerequisiteId) &&
                ownedHouseIds.contains(house.id)
          ? _HousePrerequisiteEdgeStrength.owned
          : _HousePrerequisiteEdgeStrength.neutral;
      final firstAnchorId = startAnchorId.compareTo(endAnchorId) <= 0
          ? startAnchorId
          : endAnchorId;
      final secondAnchorId = firstAnchorId == startAnchorId
          ? endAnchorId
          : startAnchorId;
      final key = '$firstAnchorId\u0000$secondAnchorId';
      final existing = edgesByKey[key];
      if (existing != null && existing.strength.index >= strength.index) {
        continue;
      }
      edgesByKey[key] = _HousePrerequisiteVisualEdge(
        key: key,
        firstAnchorId: firstAnchorId,
        secondAnchorId: secondAnchorId,
        start: anchorPositions[firstAnchorId]!,
        end: anchorPositions[secondAnchorId]!,
        strength: strength,
      );
    }
    final edges = edgesByKey.values.toList(growable: false)
      ..sort((left, right) {
        final byStrength = left.strength.index.compareTo(right.strength.index);
        return byStrength != 0 ? byStrength : left.key.compareTo(right.key);
      });
    return edges;
  }

  Map<String, Object> get debugVisualGraph {
    return <String, Object>{
      'anchorIds': anchorIdByHouseId,
      'anchorPositions': anchorPositions,
      'ownedHouseIds': ownedHouseIds,
      'recommendedNewHouseIds': recommendedNewHouseIds,
      'selectedHouseId': selectedHouseId ?? '',
      'visibleHouseIds': visibleHouseIds,
      'edges': <Map<String, Object>>[
        for (final edge in _visualEdges)
          <String, Object>{
            'firstAnchorId': edge.firstAnchorId,
            'secondAnchorId': edge.secondAnchorId,
            'start': edge.start,
            'end': edge.end,
            'strength': edge.strength.name,
          },
      ],
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = const Color(0xB8000000)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final edge in _visualEdges) {
      final highlighted =
          edge.strength != _HousePrerequisiteEdgeStrength.neutral;
      outline.strokeWidth = highlighted ? 5.8 : 4.2;
      line.strokeWidth = highlighted ? 2.7 : 1.9;
      line.color = switch (edge.strength) {
        _HousePrerequisiteEdgeStrength.neutral => const Color(0xB8DCE5E0),
        _HousePrerequisiteEdgeStrength.owned => const Color(0xFF75D6E3),
        _HousePrerequisiteEdgeStrength.recommended => const Color(0xFFFFD066),
        _HousePrerequisiteEdgeStrength.selected => const Color(0xFFFFE39A),
      };
      canvas.drawLine(edge.start, edge.end, outline);
      canvas.drawLine(edge.start, edge.end, line);
    }
  }

  @override
  bool shouldRepaint(_HousePrerequisitePainter oldDelegate) {
    return oldDelegate.town != town ||
        !mapEquals(oldDelegate.anchorIdByHouseId, anchorIdByHouseId) ||
        !mapEquals(oldDelegate.anchorPositions, anchorPositions) ||
        !setEquals(oldDelegate.ownedHouseIds, ownedHouseIds) ||
        !setEquals(
          oldDelegate.recommendedNewHouseIds,
          recommendedNewHouseIds,
        ) ||
        oldDelegate.selectedHouseId != selectedHouseId ||
        !setEquals(oldDelegate.visibleHouseIds, visibleHouseIds);
  }
}

enum _HousePrerequisiteEdgeStrength { neutral, owned, recommended, selected }

class _HousePrerequisiteVisualEdge {
  const _HousePrerequisiteVisualEdge({
    required this.key,
    required this.firstAnchorId,
    required this.secondAnchorId,
    required this.start,
    required this.end,
    required this.strength,
  });

  final String key;
  final String firstAnchorId;
  final String secondAnchorId;
  final Offset start;
  final Offset end;
  final _HousePrerequisiteEdgeStrength strength;
}

Rect _houseMarkerCollisionBounds(Offset anchor) {
  return Rect.fromLTWH(
    anchor.dx + _houseClusterMarkerOffset.dx,
    anchor.dy + _houseClusterMarkerOffset.dy,
    _houseClusterMarkerSize.width,
    _houseClusterMarkerSize.height,
  ).inflate(_houseMarkerClearance / 2);
}

enum _MapLandmarkKind { city, town, gateway }

typedef _CameraSnapshotWidgetBuilder =
    Widget Function(
      BuildContext context,
      _SettledCameraSnapshotGeometry geometry,
    );

class _SettledCameraSnapshotGeometry {
  const _SettledCameraSnapshotGeometry({
    required this.viewport,
    required this.overscan,
  });

  /// The actual, clipped map viewport.
  final Size viewport;

  /// Extra retained pixels around every side of [viewport].
  final EdgeInsets overscan;

  Size get snapshotSize => Size(
    viewport.width + overscan.horizontal,
    viewport.height + overscan.vertical,
  );

  /// The actual map viewport expressed in the oversized snapshot's space.
  Rect get visibleViewport => Rect.fromLTWH(
    overscan.left,
    overscan.top,
    viewport.width,
    viewport.height,
  );

  double get areaScale {
    final visibleArea = viewport.width * viewport.height;
    if (visibleArea <= 0) {
      return 1;
    }
    return snapshotSize.width * snapshotSize.height / visibleArea;
  }
}

/// Retains an expensive screen-space overlay while the camera is moving.
///
/// At a fixed zoom every map point moves by the same screen-space delta, so a
/// complete collision-resolved overlay can be translated as one composited
/// layer during a drag. Once movement pauses, [builder] runs once against the
/// settled camera to admit newly visible markers and restore exact obstacle
/// placement. Zoom changes rebuild immediately because marker size and
/// clustering can legitimately change with zoom.
class _SettledCameraSnapshotOverlay extends StatefulWidget {
  const _SettledCameraSnapshotOverlay({
    required this.cameraController,
    required this.viewport,
    required this.builder,
  });

  final BdoMapCameraController cameraController;
  final Size viewport;
  final _CameraSnapshotWidgetBuilder builder;

  @override
  State<_SettledCameraSnapshotOverlay> createState() =>
      _SettledCameraSnapshotOverlayState();
}

class _SettledCameraSnapshotOverlayState
    extends State<_SettledCameraSnapshotOverlay> {
  static const Duration _settleDelay = Duration(milliseconds: 90);
  static const double _rebaseThreshold = .72;

  Timer? _settleTimer;
  Widget? _snapshot;
  BdoMapCamera? _snapshotCamera;
  late double _observedZoom;
  bool _snapshotDirty = true;

  _SettledCameraSnapshotGeometry get _geometry {
    final viewport = widget.viewport;
    // Keep the retained layer on whole logical pixels. A fractional overscan
    // offset makes the compositor resample the otherwise unchanged snapshot,
    // which both softens fine icon edges and adds needless work while panning.
    final horizontal = (viewport.width * .33)
        .clamp(256.0, 512.0)
        .roundToDouble();
    final vertical = (viewport.height * .33)
        .clamp(192.0, 384.0)
        .roundToDouble();
    return _SettledCameraSnapshotGeometry(
      viewport: viewport,
      overscan: EdgeInsets.symmetric(
        horizontal: horizontal,
        vertical: vertical,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _observedZoom = widget.cameraController.camera.zoom;
    widget.cameraController.addListener(_handleCameraChanged);
  }

  @override
  void didUpdateWidget(_SettledCameraSnapshotOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraController != widget.cameraController) {
      oldWidget.cameraController.removeListener(_handleCameraChanged);
      widget.cameraController.addListener(_handleCameraChanged);
      _observedZoom = widget.cameraController.camera.zoom;
    }
    _settleTimer?.cancel();
    _snapshotDirty = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _snapshotDirty = true;
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    widget.cameraController.removeListener(_handleCameraChanged);
    super.dispose();
  }

  void _handleCameraChanged() {
    if (!mounted) {
      return;
    }
    final zoom = widget.cameraController.camera.zoom;
    _settleTimer?.cancel();
    if (zoom != _observedZoom) {
      _observedZoom = zoom;
      setState(() => _snapshotDirty = true);
      return;
    }
    final snapshotCamera = _snapshotCamera;
    if (snapshotCamera != null && !_snapshotDirty) {
      final geometry = _geometry;
      final snapshotCenterNow = widget.cameraController.worldToScreen(
        snapshotCamera.center,
        widget.viewport,
      );
      final delta = snapshotCenterNow - widget.viewport.center(Offset.zero);
      final shouldRebase =
          delta.dx.abs() >=
              geometry.overscan.horizontal / 2 * _rebaseThreshold ||
          delta.dy.abs() >= geometry.overscan.vertical / 2 * _rebaseThreshold;
      if (shouldRebase) {
        setState(() => _snapshotDirty = true);
      }
    }
    _settleTimer = Timer(_settleDelay, () {
      if (mounted && !_snapshotDirty) {
        setState(() => _snapshotDirty = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    if (_snapshotDirty || _snapshot == null || _snapshotCamera == null) {
      _snapshotCamera = widget.cameraController.camera;
      _snapshot = RepaintBoundary(
        child: SizedBox.fromSize(
          size: geometry.snapshotSize,
          child: widget.builder(context, geometry),
        ),
      );
      _snapshotDirty = false;
    }
    return Flow(
      key: const ValueKey<String>('resource-map-worker-output-retained-flow'),
      clipBehavior: Clip.hardEdge,
      delegate: _SettledCameraSnapshotFlowDelegate(
        cameraController: widget.cameraController,
        snapshotCamera: _snapshotCamera!,
        geometry: geometry,
      ),
      children: <Widget>[_snapshot!],
    );
  }
}

class _SettledCameraSnapshotFlowDelegate extends BdoMapCameraFlowDelegate {
  _SettledCameraSnapshotFlowDelegate({
    required super.cameraController,
    required this.snapshotCamera,
    required this.geometry,
  });

  final BdoMapCamera snapshotCamera;
  final _SettledCameraSnapshotGeometry geometry;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(geometry.snapshotSize);

  @override
  void paintChildren(FlowPaintingContext context) {
    final currentCamera = cameraController.camera;
    if (currentCamera.zoom != snapshotCamera.zoom) {
      paintChildAt(
        context,
        0,
        topLeft: Offset(-geometry.overscan.left, -geometry.overscan.top),
      );
      return;
    }
    final snapshotCenterNow = worldToScreen(context, snapshotCamera.center);
    final delta = snapshotCenterNow - context.size.center(Offset.zero);
    paintChildAt(
      context,
      0,
      topLeft: delta - Offset(geometry.overscan.left, geometry.overscan.top),
    );
  }

  @override
  bool shouldRepaint(
    covariant _SettledCameraSnapshotFlowDelegate oldDelegate,
  ) =>
      super.shouldRepaint(oldDelegate) ||
      oldDelegate.snapshotCamera != snapshotCamera ||
      oldDelegate.geometry.viewport != geometry.viewport ||
      oldDelegate.geometry.overscan != geometry.overscan;
}

class _LodgingBadgeFlowSpec {
  const _LodgingBadgeFlowSpec({required this.town, required this.childIndex});

  final LodgingTown town;
  final int childIndex;
}

class _LodgingBadgeFlowDelegate extends BdoMapCameraFlowDelegate {
  _LodgingBadgeFlowDelegate({
    required super.cameraController,
    required this.specs,
  });

  final List<_LodgingBadgeFlowSpec> specs;

  @override
  void paintChildren(FlowPaintingContext context) {
    final viewport = context.size;
    for (final spec in specs) {
      final position = worldToScreen(
        context,
        BdoWorldPoint(spec.town.position.x, spec.town.position.z).mapPoint,
      );
      if (position.dx < -36 ||
          position.dy < -36 ||
          position.dx > viewport.width + 36 ||
          position.dy > viewport.height + 36) {
        continue;
      }
      paintChildAt(
        context,
        spec.childIndex,
        topLeft: position + const Offset(13, -25),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LodgingBadgeFlowDelegate oldDelegate) =>
      super.shouldRepaint(oldDelegate) || !identical(oldDelegate.specs, specs);
}

class _AllNodePlacement {
  const _AllNodePlacement({
    required this.node,
    required this.position,
    required this.showLabel,
  });

  final BdoWorkerNode node;
  final Offset position;
  final bool showLabel;
}

List<_AllNodePlacement> _resolveAllNodePlacements({
  required BdoMapCameraController cameraController,
  required Size viewport,
  required List<BdoWorkerNode> nodes,
  required double zoom,
  Rect? visibleViewport,
  double labelBudgetScale = 1,
  bool retainAllNodes = false,
}) {
  final cellSize = zoom < 3
      ? 28.0
      : zoom < 4.5
      ? 21.0
      : 14.0;
  final center = viewport.center(Offset.zero);
  final controlViewport = visibleViewport ?? (Offset.zero & viewport);
  final candidatesByCell =
      <(int, int), ({BdoWorkerNode node, Offset position})>{};
  final allCandidates = <({BdoWorkerNode node, Offset position})>[];
  for (final node in nodes) {
    final position = cameraController.worldToScreen(
      node.location.mapPoint,
      viewport,
    );
    if (position.dx < -90 ||
        position.dy < -24 ||
        position.dx > viewport.width + 24 ||
        position.dy > viewport.height + 24) {
      continue;
    }
    if (retainAllNodes) {
      allCandidates.add((node: node, position: position));
      continue;
    }
    final cell = (
      ((position.dx - controlViewport.left) / cellSize).floor(),
      ((position.dy - controlViewport.top) / cellSize).floor(),
    );
    final existing = candidatesByCell[cell];
    if (existing == null) {
      candidatesByCell[cell] = (node: node, position: position);
      continue;
    }
    final candidatePriority = _mapOrientationNodePriority(node);
    final existingPriority = _mapOrientationNodePriority(existing.node);
    if (candidatePriority < existingPriority ||
        (candidatePriority == existingPriority &&
            (position - center).distanceSquared <
                (existing.position - center).distanceSquared)) {
      candidatesByCell[cell] = (node: node, position: position);
    }
  }
  final candidates = retainAllNodes
      ? allCandidates
      : candidatesByCell.values.toList(growable: false);
  candidates.sort((left, right) {
    final byImportance = _mapOrientationNodePriority(
      left.node,
    ).compareTo(_mapOrientationNodePriority(right.node));
    if (byImportance != 0) {
      return byImportance;
    }
    return (left.position - center).distanceSquared.compareTo(
      (right.position - center).distanceSquared,
    );
  });
  final occupiedLabels = <Rect>[
    Rect.fromLTWH(
      math.max(controlViewport.left, controlViewport.right - 210),
      controlViewport.top,
      math.min(210, controlViewport.width),
      math.min(278, controlViewport.height),
    ),
  ];
  final placements = <_AllNodePlacement>[];
  final collisionCounts = <(int, int), int>{};
  var labelCount = 0;
  final labelBudget = math.max(54, (54 * labelBudgetScale).ceil());
  for (final candidate in candidates) {
    var markerPosition = candidate.position;
    if (retainAllNodes) {
      final collisionCell = (
        candidate.position.dx.round(),
        candidate.position.dy.round(),
      );
      final collisionIndex = collisionCounts.update(
        collisionCell,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      if (collisionIndex > 0) {
        const spacing = 34.0;
        final ring = ((collisionIndex - 1) ~/ 4) + 1;
        final distance = spacing * ring;
        markerPosition += switch ((collisionIndex - 1) % 4) {
          0 => Offset(distance, 0),
          1 => Offset(0, distance),
          2 => Offset(-distance, 0),
          _ => Offset(0, -distance),
        };
      }
    }
    var showLabel =
        zoom >= _allNodeLabelMinimumZoom && labelCount < labelBudget;
    final labelWidth = math
        .min(146.0, 34 + candidate.node.siteName.length * 6.1)
        .toDouble();
    final labelBounds = Rect.fromLTWH(
      markerPosition.dx - 12,
      markerPosition.dy - 16,
      showLabel ? labelWidth : 24,
      32,
    );
    if (showLabel &&
        occupiedLabels.any((other) => other.inflate(3).overlaps(labelBounds))) {
      showLabel = false;
    }
    if (showLabel) {
      occupiedLabels.add(labelBounds);
      labelCount += 1;
    }
    placements.add(
      _AllNodePlacement(
        node: candidate.node,
        position: markerPosition,
        showLabel: showLabel,
      ),
    );
  }
  return placements;
}

int _mapOrientationNodePriority(BdoWorkerNode node) {
  return switch (node.nodeType) {
    'City' => 0,
    'Town' => 1,
    'Gateway' => 2,
    _ when node.isResourceNode => 3,
    'Connection' => 5,
    _ => 4,
  };
}

class _MapLandmarkMarker extends StatelessWidget {
  const _MapLandmarkMarker({
    required this.node,
    required this.label,
    required this.kind,
    required this.active,
    required this.onTap,
    this.semanticLabel,
  });

  final BdoWorkerNode node;
  final String label;
  final _MapLandmarkKind kind;
  final bool active;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final presentation = switch (kind) {
      _MapLandmarkKind.city => (
        Icons.location_city_rounded,
        const Color(0xFFE7D18A),
        context.mapChrome.graphiteRaised,
      ),
      _MapLandmarkKind.town => (
        Icons.home_work_outlined,
        const Color(0xFFC7D6C8),
        context.mapChrome.graphiteRaised,
      ),
      _MapLandmarkKind.gateway => (
        Icons.hub_outlined,
        const Color(0xFF8FC9AE),
        context.mapChrome.graphiteRaised,
      ),
    };
    return Semantics(
      button: true,
      label: semanticLabel ?? 'Open $label node details',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: presentation.$3,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  context.mapChrome.graphiteHighlight,
                  context.mapChrome.graphiteRaised,
                ],
              ),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: presentation.$2.withAlpha(105)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _BdoNodeIconImage(
                    node: node,
                    active: active,
                    size: 26,
                    fallbackIcon: presentation.$1,
                    fallbackColor: presentation.$2,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 126),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.mapChrome.ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
}

class _BdoNodeIconImage extends StatelessWidget {
  const _BdoNodeIconImage({
    required this.node,
    required this.active,
    required this.size,
    required this.fallbackIcon,
    required this.fallbackColor,
  });

  final BdoWorkerNode node;
  final bool active;
  final double size;
  final IconData fallbackIcon;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final assetPath = node.nodeIconAssetPath(active: active);
    final fallback = Icon(fallbackIcon, size: size * .72, color: fallbackColor);
    if (assetPath == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: fallback),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        assetPath,
        package: 'bdo_map_core',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => Center(child: fallback),
      ),
    );
  }
}

class _MapOrientationNodeMarker extends StatelessWidget {
  const _MapOrientationNodeMarker({
    required this.node,
    required this.label,
    required this.showLabel,
    required this.active,
    required this.onTap,
    this.semanticLabel,
    this.largeHitTarget = false,
  });

  final BdoWorkerNode node;
  final String label;
  final bool showLabel;
  final bool active;
  final VoidCallback onTap;
  final String? semanticLabel;
  final bool largeHitTarget;

  @override
  Widget build(BuildContext context) {
    final color = switch (node.nodeType) {
      'City' || 'Town' => const Color(0xFFE0C979),
      'Gateway' => const Color(0xFF83C5A5),
      _ when node.isProductionNode => const Color(0xFFD8BC68),
      'Connection' => const Color(0xFF82908B),
      _ => const Color(0xFFAAB6B0),
    };
    return Semantics(
      button: true,
      toggled: semanticLabel?.startsWith('Unmark'),
      label: semanticLabel ?? 'Open $label node details',
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: showLabel
                    ? 0
                    : largeHitTarget
                    ? 44
                    : 40,
                minHeight: largeHitTarget ? 44 : 40,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _BdoNodeIconImage(
                      node: node,
                      active: active,
                      size: 24,
                      fallbackIcon: _iconForWorkerNode(node),
                      fallbackColor: color,
                    ),
                    if (showLabel) ...<Widget>[
                      const SizedBox(width: 4),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.mapChrome.graphiteRaised,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              context.mapChrome.graphiteHighlight,
                              context.mapChrome.graphiteRaised,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(72)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 126),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.mapChrome.text,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLayerToggleButton extends StatelessWidget {
  const _MapLayerToggleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: selected,
      child: Material(
        elevation: 8,
        shadowColor: const Color(0x66000000),
        color: context.mapChrome.fillAlpha(context.mapChrome.chromeBase, .94),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: context.mapChrome.ink.withValues(alpha: .11)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.square(
          dimension: 44,
          child: MapQuietIconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: selected
                  ? context.mapChrome.primary.withValues(alpha: .12)
                  : Colors.transparent,
            ),
            icon: Icon(
              icon,
              size: 19,
              color: selected
                  ? context.mapChrome.primary
                  : context.mapChrome.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLayerMenuRow extends StatelessWidget {
  const _MapLayerMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
          hoverColor: context.mapChrome.brassWash,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: selected
                  ? context.mapChrome.brassWash
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border(
                left: BorderSide(
                  color: selected
                      ? context.mapChrome.brassLine
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? context.mapChrome.accent
                        : context.mapChrome.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? context.mapChrome.ink
                            : context.mapChrome.text,
                        fontSize: ResourceMapPanelMetrics.primary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    child: Icon(
                      selected ? Icons.check_rounded : null,
                      key: ValueKey<bool>(selected),
                      size: 17,
                      color: selected
                          ? context.mapChrome.accent
                          : Colors.transparent,
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
}

class _StatusIconVisual extends StatelessWidget {
  const _StatusIconVisual({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 32,
      child: Icon(icon, size: 17, color: context.mapChrome.accent),
    );
  }
}

class _StatusHitButton extends StatelessWidget {
  const _StatusHitButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: MapQuietIconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: const SizedBox.shrink(),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.color,
    this.titleSize = ResourceMapPanelMetrics.heading,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final Color color;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: ResourceMapPanelMetrics.artwork,
            height: ResourceMapPanelMetrics.artwork,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Tooltip(
              message: eyebrow,
              child: Icon(icon, size: 19, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  softWrap: true,
                  style: TextStyle(
                    color: context.mapChrome.ink,
                    fontSize: math.min(
                      titleSize,
                      ResourceMapPanelMetrics.heading,
                    ),
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    letterSpacing: -.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.mapChrome.ink,
              fontSize: ResourceMapPanelMetrics.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationGuideLightbox extends StatefulWidget {
  const _LocationGuideLightbox({
    required this.images,
    required this.initialIndex,
    required this.imageBuilder,
    required this.provenanceRecord,
  });

  final List<BdoLocationGuideImage> images;
  final int initialIndex;
  final BdoLocationGuideImageBuilder imageBuilder;
  final BdoProvenanceRecord? Function(String provenanceId) provenanceRecord;

  @override
  State<_LocationGuideLightbox> createState() => _LocationGuideLightboxState();
}

class _LocationGuideLightboxState extends State<_LocationGuideLightbox> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1).toInt();
  }

  void _showPrevious() {
    setState(() {
      _index = (_index - 1 + widget.images.length) % widget.images.length;
    });
  }

  void _showNext() {
    setState(() {
      _index = (_index + 1) % widget.images.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.images[_index];
    final provenance = widget.provenanceRecord(image.provenanceId);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final chrome = context.mapChrome;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _showPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _showNext,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 360,
                  minHeight: 300,
                ),
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  label: 'Location photos',
                  explicitChildNodes: true,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Material(
                      key: const ValueKey<String>(
                        'resource-map-location-guide-lightbox',
                      ),
                      elevation: 24,
                      shadowColor: Colors.black,
                      color: chrome.chromeRaised,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: chrome.accent.withValues(alpha: .52),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              18,
                              10,
                              8,
                              10,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    image.caption.isEmpty
                                        ? 'Location photo'
                                        : image.caption,
                                    style: TextStyle(
                                      color: chrome.ink,
                                      fontSize: ResourceMapPanelMetrics.heading,
                                      height: 1.15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${_index + 1} / ${widget.images.length}',
                                  style: TextStyle(
                                    color: chrome.muted,
                                    fontSize: ResourceMapPanelMetrics.secondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                MapQuietIconButton(
                                  key: const ValueKey<String>(
                                    'resource-map-location-guide-close',
                                  ),
                                  tooltip: 'Close photos',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: chrome.divider),
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                AnimatedSwitcher(
                                  duration: reduceMotion
                                      ? Duration.zero
                                      : ResourceMapAtlasMotion.enter,
                                  switchInCurve: ResourceMapAtlasMotion.curve,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: Tween<double>(
                                            begin: .985,
                                            end: 1,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: InteractiveViewer(
                                    key: ValueKey<String>(
                                      '${image.assetPath}-$_index',
                                    ),
                                    minScale: 1,
                                    maxScale: 4,
                                    child: SizedBox.expand(
                                      child: widget.imageBuilder(
                                        context,
                                        image,
                                        BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                                if (widget.images.length > 1) ...<Widget>[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: _LocationGuideArrowButton(
                                        key: const ValueKey<String>(
                                          'resource-map-location-guide-previous',
                                        ),
                                        tooltip: 'Previous photo',
                                        icon: Icons.chevron_left_rounded,
                                        onPressed: _showPrevious,
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: _LocationGuideArrowButton(
                                        key: const ValueKey<String>(
                                          'resource-map-location-guide-next',
                                        ),
                                        tooltip: 'Next photo',
                                        icon: Icons.chevron_right_rounded,
                                        onPressed: _showNext,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 9, 18, 12),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * .25,
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  provenance == null
                                      ? 'Source details unavailable'
                                      : <String>[
                                          provenance.title,
                                          '${provenance.attribution} · ${provenance.license}',
                                          provenance.url.toString(),
                                          if (image.verifiedAt != null)
                                            'Photo checked ${image.verifiedAt!.toIso8601String().split('T').first}',
                                        ].join('\n'),
                                  style: TextStyle(
                                    color: chrome.muted,
                                    fontSize: ResourceMapPanelMetrics.secondary,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationGuideArrowButton extends StatelessWidget {
  const _LocationGuideArrowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: Colors.black.withValues(alpha: .62),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon, size: 30),
    );
  }
}

class _DetailLink extends StatelessWidget {
  const _DetailLink({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: selected
            ? context.mapChrome.primary.withValues(alpha: .11)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.white.withValues(alpha: .05),
          highlightColor: context.mapChrome.primary.withValues(alpha: .10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: ResourceMapPanelMetrics.artwork,
                  height: ResourceMapPanelMetrics.artwork,
                  decoration: BoxDecoration(
                    color: context.mapChrome.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: context.mapChrome.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Tooltip(
                        message: subtitle,
                        child: Text(
                          title,
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.primary,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: context.mapChrome.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAcquisition extends StatelessWidget {
  const _EmptyAcquisition({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: text,
    child: Text(
      'No sources',
      style: TextStyle(
        color: context.mapChrome.muted,
        fontSize: ResourceMapPanelMetrics.secondary,
      ),
    ),
  );
}

class _GatherChecklistEmptyState extends StatelessWidget {
  const _GatherChecklistEmptyState();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: text,
    child: Icon(icon, size: 18, color: context.mapChrome.muted),
  );
}

IconData _iconForSearchKind(BdoSearchKind kind) {
  return switch (kind) {
    BdoSearchKind.resource => Icons.inventory_2_outlined,
    BdoSearchKind.fieldSource => Icons.nature_people_outlined,
    BdoSearchKind.workerNode => Icons.hub_outlined,
    BdoSearchKind.gatheringSpot => Icons.nature_outlined,
    BdoSearchKind.gatheringRoute => Icons.route_outlined,
  };
}

Color _colorForSearchKind(BuildContext context, BdoSearchKind kind) {
  return switch (kind) {
    BdoSearchKind.resource => context.mapChrome.accent,
    BdoSearchKind.fieldSource => context.mapChrome.positive,
    BdoSearchKind.workerNode => context.mapChrome.primary,
    BdoSearchKind.gatheringSpot => context.mapChrome.positive,
    BdoSearchKind.gatheringRoute => context.mapChrome.warning,
  };
}

IconData _iconForWorkerNode(BdoWorkerNode node) {
  if (node.isResourceNode) {
    return bdoWorkerActivityIcon(node.activity);
  }
  return switch (node.nodeType) {
    'City' => Icons.location_city_outlined,
    'Town' => Icons.home_work_outlined,
    'Gateway' => Icons.hub_outlined,
    'Trading Post' => Icons.storefront_outlined,
    'Dangerous' => Icons.warning_amber_rounded,
    _ => Icons.alt_route_rounded,
  };
}

Color _colorForWorkerNode(BuildContext context, BdoWorkerNode node) {
  if (node.isResourceNode) {
    return bdoWorkerActivityColor(node.activity);
  }
  return switch (node.nodeType) {
    'City' || 'Town' => context.mapChrome.primary,
    'Gateway' => context.mapChrome.accent,
    'Dangerous' => context.mapChrome.error,
    _ => context.mapChrome.muted,
  };
}

IconData _iconForFieldSource(BdoFieldSource source) {
  final value = '${source.category} ${source.name}'.toLowerCase();
  if (value.contains('tree') ||
      value.contains('timber') ||
      value.contains('wood')) {
    return Icons.forest_outlined;
  }
  if (value.contains('mushroom') || value.contains('fung')) {
    return Icons.eco_outlined;
  }
  if (value.contains('coral') ||
      value.contains('marine') ||
      value.contains('underwater')) {
    return Icons.waves_outlined;
  }
  if (value.contains('rock') ||
      value.contains('ore') ||
      value.contains('mineral')) {
    return Icons.diamond_outlined;
  }
  if (value.contains('animal') ||
      value.contains('snake') ||
      value.contains('sheep') ||
      value.contains('wolf') ||
      value.contains('fox') ||
      value.contains('deer') ||
      value.contains('boar')) {
    return Icons.pets_outlined;
  }
  if (value.contains('hunt')) {
    return Icons.gps_fixed_rounded;
  }
  return Icons.local_florist_outlined;
}

BdoMapBounds? _boundsForPoints(
  List<BdoMapPoint> points, {
  double minimumSpan = 22000,
}) {
  assert(minimumSpan >= 0);
  if (points.isEmpty) {
    return null;
  }
  var left = points.first.x;
  var right = points.first.x;
  var top = points.first.y;
  var bottom = points.first.y;
  for (final point in points.skip(1)) {
    left = math.min(left, point.x);
    right = math.max(right, point.x);
    top = math.min(top, point.y);
    bottom = math.max(bottom, point.y);
  }
  if (right - left < minimumSpan) {
    final center = (right + left) / 2;
    left = center - minimumSpan / 2;
    right = center + minimumSpan / 2;
  }
  if (bottom - top < minimumSpan) {
    final center = (bottom + top) / 2;
    top = center - minimumSpan / 2;
    bottom = center + minimumSpan / 2;
  }
  return BdoMapBounds(left: left, top: top, right: right, bottom: bottom);
}

int _compareMapNodeIds(String left, String right) {
  final leftNumber = BigInt.tryParse(left);
  final rightNumber = BigInt.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final byNumber = leftNumber.compareTo(rightNumber);
    return byNumber != 0 ? byNumber : left.compareTo(right);
  }
  if (leftNumber != null) return -1;
  if (rightNumber != null) return 1;
  return left.compareTo(right);
}

/// Map opacity applies to the map's pills, not to modal reading surfaces.
/// As an inherited theme, this protected chrome also follows nested dialogs.
class _MapDialogScope extends StatelessWidget {
  const _MapDialogScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ResourceMapChromeTheme(
    data: context.mapChrome.withUiOpacity(1),
    liveData: ResourceMapChromeTheme.liveDataOf(context),
    opacityOverride: 1,
    child: Builder(
      builder: (context) => Theme(data: _buildMapTheme(context), child: child),
    ),
  );
}

ThemeData _buildMapTheme(BuildContext context) {
  final chrome = context.mapChrome;
  final base = ThemeData(brightness: chrome.brightness, useMaterial3: true);
  final headingFamily = chrome.headingFontFamily ?? 'Segoe UI';
  final scheme = ColorScheme(
    brightness: chrome.brightness,
    primary: chrome.primary,
    onPrimary: chrome.onPrimary,
    primaryContainer: chrome.deepAccent,
    onPrimaryContainer: chrome.text,
    secondary: chrome.accent,
    onSecondary: chrome.onPrimary,
    secondaryContainer: chrome.trimDeep,
    onSecondaryContainer: chrome.ink,
    tertiary: chrome.positive,
    onTertiary: chrome.onPrimary,
    tertiaryContainer: chrome.chromeHighlight,
    onTertiaryContainer: chrome.text,
    error: chrome.error,
    onError: chrome.onPrimary,
    errorContainer: chrome.deepAccent,
    onErrorContainer: chrome.ink,
    surface: chrome.chromeRaised,
    onSurface: chrome.ink,
    surfaceContainerLowest: chrome.controlInset,
    surfaceContainerLow: chrome.chromeBase,
    surfaceContainer: chrome.chromeRaised,
    surfaceContainerHigh: chrome.chromeHighlight,
    surfaceContainerHighest: chrome.chromeHighlight,
    outline: chrome.warmOutline,
    outlineVariant: chrome.softOutline,
    inverseSurface: chrome.chromeHighlight,
    onInverseSurface: chrome.ink,
    inversePrimary: chrome.primary,
    shadow: chrome.idleShadow.color,
    scrim: chrome.canvas.withValues(alpha: .82),
    surfaceTint: Colors.transparent,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: chrome.chromeBase,
    canvasColor: chrome.chromeBase,
    cardColor: chrome.chromeRaised,
    splashFactory: InkRipple.splashFactory,
    visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    textTheme: base.textTheme
        .apply(
          fontFamily: 'Segoe UI',
          bodyColor: chrome.text,
          displayColor: chrome.ink,
        )
        .copyWith(
          titleLarge: TextStyle(
            color: chrome.ink,
            fontFamily: headingFamily,
            fontSize: ResourceMapPanelMetrics.heading,
            height: 1.18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.25,
          ),
          titleMedium: TextStyle(
            color: chrome.ink,
            fontFamily: headingFamily,
            fontSize: ResourceMapPanelMetrics.primary,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -.08,
          ),
          titleSmall: TextStyle(
            color: chrome.ink,
            fontFamily: headingFamily,
            fontSize: ResourceMapPanelMetrics.primary,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(
            color: chrome.text,
            fontSize: ResourceMapPanelMetrics.primary,
            height: 1.45,
          ),
          bodyMedium: TextStyle(
            color: chrome.text,
            fontSize: ResourceMapPanelMetrics.primary,
            height: 1.42,
          ),
          bodySmall: TextStyle(
            color: chrome.muted,
            fontSize: ResourceMapPanelMetrics.secondary,
            height: 1.4,
          ),
          labelLarge: TextStyle(
            color: chrome.ink,
            fontFamily: headingFamily,
            fontSize: ResourceMapPanelMetrics.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: .05,
          ),
          labelMedium: TextStyle(
            color: chrome.text,
            fontFamily: headingFamily,
            fontSize: ResourceMapPanelMetrics.secondary,
            fontWeight: FontWeight.w700,
          ),
          labelSmall: TextStyle(
            color: chrome.muted,
            fontSize: ResourceMapPanelMetrics.secondary,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(fontFamily: 'Segoe UI'),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: chrome.primary,
      selectionColor: chrome.primary.withValues(alpha: .28),
      selectionHandleColor: chrome.primary,
    ),
    dividerColor: chrome.divider,
    cardTheme: CardThemeData(
      color: chrome.chromeRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(chrome.surfaceRadius)),
        side: BorderSide(color: chrome.warmOutline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: chrome.chromeRaised,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      hintStyle: TextStyle(
        color: chrome.muted,
        fontSize: ResourceMapPanelMetrics.primary,
        fontWeight: FontWeight.w500,
      ),
      labelStyle: TextStyle(
        color: chrome.muted,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: chrome.primary,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w700,
      ),
      prefixIconColor: chrome.muted,
      suffixIconColor: chrome.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(chrome.controlRadius)),
        borderSide: BorderSide(color: chrome.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(chrome.controlRadius)),
        borderSide: BorderSide(color: chrome.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(chrome.controlRadius)),
        borderSide: BorderSide(color: chrome.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(chrome.controlRadius)),
        borderSide: BorderSide(color: chrome.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(chrome.controlRadius)),
        borderSide: BorderSide(color: chrome.error, width: 1.4),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: chrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: const Color(0x52000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.surfaceRadius),
        side: BorderSide(color: chrome.divider),
      ),
      titleTextStyle: TextStyle(
        color: chrome.ink,
        fontFamily: headingFamily,
        fontSize: ResourceMapPanelMetrics.heading,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
      ),
      contentTextStyle: TextStyle(
        color: chrome.text,
        fontFamily: 'Segoe UI',
        fontSize: ResourceMapPanelMetrics.primary,
        height: 1.45,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: chrome.paperRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: const Color(0x42000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.surfaceRadius),
        side: BorderSide(color: chrome.divider),
      ),
      textStyle: TextStyle(
        color: chrome.ink,
        fontFamily: headingFamily,
        fontSize: ResourceMapPanelMetrics.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(ResourceMapPanelMetrics.controlTarget),
        padding: const EdgeInsets.all(5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: chrome.ink,
        hoverColor: chrome.primary.withValues(alpha: .09),
        highlightColor: chrome.primary.withValues(alpha: .14),
        focusColor: chrome.primary.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: chrome.primary,
        foregroundColor: chrome.onPrimary,
        disabledBackgroundColor: chrome.chromeHighlight,
        disabledForegroundColor: chrome.muted,
        elevation: 0,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        textStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: .05,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: chrome.primary,
        side: BorderSide(color: chrome.divider),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        textStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: chrome.primary,
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chrome.controlRadius),
        ),
        textStyle: TextStyle(
          fontFamily: headingFamily,
          fontSize: ResourceMapPanelMetrics.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: chrome.paper,
      selectedColor: chrome.deepAccent,
      disabledColor: chrome.chromeBase,
      side: BorderSide(color: chrome.divider),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.compactRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      labelStyle: TextStyle(
        color: chrome.text,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: chrome.primary,
        fontFamily: headingFamily,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: chrome.accent, size: 16),
      checkmarkColor: chrome.primary,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: chrome.muted, width: 1.2),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? chrome.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(chrome.onPrimary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? chrome.onPrimary
            : chrome.paperRaised,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? chrome.primary
            : chrome.chromeHighlight,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? chrome.primary
            : chrome.divider,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: chrome.chromeRaised,
        borderRadius: BorderRadius.circular(chrome.compactRadius),
        border: Border.all(color: chrome.divider),
      ),
      textStyle: TextStyle(
        color: chrome.ink,
        fontSize: ResourceMapPanelMetrics.secondary,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      waitDuration: const Duration(milliseconds: 450),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(chrome.primary.withValues(alpha: .48)),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      thickness: const WidgetStatePropertyAll(3),
      radius: const Radius.circular(99),
    ),
  );
}
