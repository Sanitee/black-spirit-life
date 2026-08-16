import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/shared/custom_icon_store_scope.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class PlannerTestHarness {
  PlannerTestHarness({
    CraftMode activeMode = CraftMode.alchemy,
    bool emptyAlchemyBonusPool = false,
    Map<String, String> alchemyIconDataUris = const <String, String>{},
    Map<String, Object?> supportingDataOverrides = const <String, Object?>{},
    PlannerMarketRefresh? marketRefresh,
    CheckPlannerPrices? checkPrices,
    ResolvePlannerMapLookup? resolveMapLookup,
    OpenPlannerMapLookup? openMapLookup,
    AddPlannerGatherChecklistItem? addToGatherChecklist,
    AddPlannerWorkerNetworkMaterial? addToPlannedNetwork,
    CopyAfkLoad? copyAfkLoad,
    OpenAfkWeightSettings? openAfkWeightSettings,
    MarketState? alchemyMarket,
    double sunriseNpcPrice = 500,
    bool includeRecipeVariants = false,
    bool showAdvancedEditor = false,
  }) : copied = <String>[],
       copiedAfkLoads = <String>[],
       recipeRequests = <RecipeBookRequest>[],
       mapLookupRequests = <PlannerMapLookupRequest>[],
       plannedNetworkAdds = <PlannerMapLookupAvailability>[],
       controller = PlannerApplicationController(
         catalog: _catalog(
           emptyAlchemyBonusPool: emptyAlchemyBonusPool,
           alchemyIconDataUris: alchemyIconDataUris,
           supportingDataOverrides: supportingDataOverrides,
           includeRecipeVariants: includeRecipeVariants,
         ),
         initialState: _document(
           activeMode,
           alchemyMarket: alchemyMarket,
           sunriseNpcPrice: sunriseNpcPrice,
           showAdvancedEditor: showAdvancedEditor,
         ),
         saveState: (state) async => state,
         saveDebounce: Duration.zero,
       ) {
    actions = PlannerExternalActions(
      openRecipeBook: recipeRequests.add,
      copyName: (name) async => copied.add(name),
      checkPrices: (request) async {
        marketRequest = request;
        if (checkPrices != null) return checkPrices(request);
        return marketRefresh ??
            const PlannerMarketRefresh(
              prices: <String, double>{
                'Sunrise Herb': 1200,
                'Silver Azalea': 1800,
              },
              stock: <String, double>{'Sunrise Herb': 500, 'Silver Azalea': 20},
              unlistedItemNames: <String>{},
              fetchedAt: 1784534400000,
              summary: '2 prices refreshed from the EU market.',
              region: 'eu',
              rowDiagnostics: <String, List<PlannerMarketRowDiagnostic>>{
                'sunrise herb': <PlannerMarketRowDiagnostic>[
                  PlannerMarketRowDiagnostic(
                    message: 'Market ID was normalized before lookup.',
                    severity: PlannerMarketDiagnosticSeverity.info,
                  ),
                ],
              },
            );
      },
      resolveMapLookup: resolveMapLookup,
      openMapLookup:
          openMapLookup ??
          (resolveMapLookup == null ? null : mapLookupRequests.add),
      addToGatherChecklist: addToGatherChecklist,
      addToPlannedNetwork:
          addToPlannedNetwork ??
          (resolveMapLookup == null ? null : plannedNetworkAdds.add),
      copyAfkLoad: copyAfkLoad ?? (text) async => copiedAfkLoads.add(text),
      openAfkWeightSettings:
          openAfkWeightSettings ?? () => afkWeightSettingsOpenCount += 1,
    );
  }

  final PlannerApplicationController controller;
  final List<String> copied;
  final List<String> copiedAfkLoads;
  final List<RecipeBookRequest> recipeRequests;
  final List<PlannerMapLookupRequest> mapLookupRequests;
  final List<PlannerMapLookupAvailability> plannedNetworkAdds;
  late final PlannerExternalActions actions;
  PlannerMarketRequest? marketRequest;
  int afkWeightSettingsOpenCount = 0;

  Widget plannerHost({
    CustomIconStore? iconStore,
    TextScaler textScaler = TextScaler.noScaling,
    ThemeSpec spec = StandardSpec.theme,
  }) {
    final planner = PlannerView(
      controller: controller.active,
      externalActions: actions,
    );
    return _host(
      iconStore == null
          ? planner
          : CustomIconStoreScope(store: iconStore, child: planner),
      textScaler: textScaler,
      spec: spec,
    );
  }

  Widget bonusHost({
    TextScaler textScaler = TextScaler.noScaling,
    ThemeSpec spec = StandardSpec.theme,
  }) => _host(
    BonusView(controller: controller.active, externalActions: actions),
    textScaler: textScaler,
    spec: spec,
  );
}

Widget _host(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  ThemeSpec spec = StandardSpec.theme,
}) => AppOverlayCoordinatorHost(
  child: MaterialApp(
    theme: spec.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: ColoredBox(
          color: spec.palette.canvas,
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ),
    ),
  ),
);

PlannerState _document(
  CraftMode activeMode, {
  MarketState? alchemyMarket,
  required double sunriseNpcPrice,
  required bool showAdvancedEditor,
}) => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 20),
  activeMode: activeMode,
  alchemy: _mode(
    CraftMode.alchemy,
    target: 'Clear Liquid Reagent',
    bonusTarget: 'Clear Liquid Reagent',
    market: alchemyMarket,
    sunriseNpcPrice: sunriseNpcPrice,
  ),
  cooking: _mode(CraftMode.cooking, target: 'Beer', bonusTarget: 'Beer'),
  processing: _mode(
    CraftMode.processing,
    target: 'Wheat Flour',
    bonusTarget: '',
  ),
  processingYields: const <String, double>{'defaultYield': 2.5},
  marketTax: MarketTax(),
  showDeleteTools: showAdvancedEditor,
);

ModeState _mode(
  CraftMode mode, {
  required String target,
  required String bonusTarget,
  MarketState? market,
  double sunriseNpcPrice = 500,
}) => ModeState(
  target: target,
  want: 10,
  bonusTarget: bonusTarget,
  bonusWant: 6,
  ingredientMeta: mode == CraftMode.alchemy
      ? <String, IngredientMetadata>{
          'Sunrise Herb': IngredientMetadata(
            category: 'Herbs',
            sourceNote: 'Gathered near Heidel roads.',
            vendor: 'Material Vendor',
            location: 'Heidel',
            npcPrice: sunriseNpcPrice,
          ),
        }
      : const <String, IngredientMetadata>{},
  market: market ?? MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

CatalogSnapshot _catalog({
  required bool emptyAlchemyBonusPool,
  required Map<String, String> alchemyIconDataUris,
  required Map<String, Object?> supportingDataOverrides,
  required bool includeRecipeVariants,
}) => CatalogSnapshot(
  sourceSha256: 'planner-widget-fixture',
  sourceByteCount: 1,
  alchemy: ModeCatalog(
    mode: CraftMode.alchemy,
    items: <String, Recipe>{
      if (!emptyAlchemyBonusPool) ...<String, Recipe>{
        'Clear Liquid Reagent': _recipe(
          'Clear Liquid Reagent',
          'alchemy',
          <Ingredient>[_ingredient('Intermediate Reagent', 1)],
          variants: includeRecipeVariants
              ? <RecipeVariant>[
                  RecipeVariant(
                    id: 'reagent-route',
                    label: 'Reagent Route',
                    type: 'alchemy',
                    baseOutput: 1,
                    method: null,
                    ingredients: <Ingredient>[
                      _ingredient('Intermediate Reagent', 1),
                    ],
                    outputMinimum: 1,
                    outputMaximum: 1,
                  ),
                  RecipeVariant(
                    id: 'reagent-route-10x',
                    routeId: 'reagent-route',
                    label: 'Reagent Route',
                    batchMultiplier: 10,
                    type: 'alchemy',
                    baseOutput: 10,
                    method: null,
                    ingredients: <Ingredient>[
                      _ingredient('Intermediate Reagent', 10),
                    ],
                    outputMinimum: 10,
                    outputMaximum: 10,
                  ),
                  RecipeVariant(
                    id: 'herb-route',
                    label: 'Herb Route',
                    type: 'alchemy',
                    baseOutput: 1,
                    method: null,
                    ingredients: <Ingredient>[_ingredient('Silver Azalea', 4)],
                    outputMinimum: 1,
                    outputMaximum: 1,
                  ),
                  RecipeVariant(
                    id: 'herb-route-10x',
                    routeId: 'herb-route',
                    label: 'Herb Route',
                    batchMultiplier: 10,
                    type: 'alchemy',
                    baseOutput: 10,
                    method: null,
                    ingredients: <Ingredient>[_ingredient('Silver Azalea', 40)],
                    outputMinimum: 10,
                    outputMaximum: 10,
                  ),
                ]
              : const <RecipeVariant>[],
          defaultVariantId: includeRecipeVariants ? 'reagent-route' : null,
        ),
        'Pure Powder Reagent': _recipe(
          'Pure Powder Reagent',
          'alchemy',
          <Ingredient>[_ingredient('Sunrise Herb', 1)],
        ),
        "Clown's Blood": _recipe("Clown's Blood", 'alchemy', <Ingredient>[
          _ingredient('Sunrise Herb', 2),
        ]),
      },
      'Intermediate Reagent': _recipe(
        'Intermediate Reagent',
        'alchemy',
        <Ingredient>[
          Ingredient(
            name: 'Sunrise Herb',
            quantity: 2,
            options: const <String>['Sunrise Herb', 'Silver Azalea'],
            substituteGroup: 'Wild Herbs',
            substituteRatios: const <String, double>{
              'Sunrise Herb': 1,
              'Silver Azalea': 2,
            },
          ),
        ],
      ),
      'Sunrise Herb': _leaf(
        'Sunrise Herb',
        sourceNote: 'Gathered from wild herb nodes.',
      ),
      'Silver Azalea': _leaf('Silver Azalea'),
    },
    iconDataUris: alchemyIconDataUris,
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  ),
  cooking: ModeCatalog(
    mode: CraftMode.cooking,
    items: <String, Recipe>{
      'Beer': _recipe('Beer', 'cooking', <Ingredient>[_ingredient('Wheat', 5)]),
      'Grilled Bird Meat': _recipe('Grilled Bird Meat', 'cooking', <Ingredient>[
        _ingredient('Chicken Meat', 2),
      ]),
      'Pickled Vegetables': _recipe(
        'Pickled Vegetables',
        'cooking',
        <Ingredient>[_ingredient('Cabbage', 8)],
      ),
      'Wheat': _leaf('Wheat'),
      'Chicken Meat': _leaf('Chicken Meat'),
      'Cabbage': _leaf('Cabbage'),
    },
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  ),
  processing: ModeCatalog(
    mode: CraftMode.processing,
    items: <String, Recipe>{
      'Wheat Flour': _recipe('Wheat Flour', 'processing', <Ingredient>[
        _ingredient('Wheat', 1),
      ], method: 'Grinding'),
      'Wheat': _leaf('Wheat'),
    },
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  ),
  supportingData: <String, Object?>{
    'qualityIngredients': const <String>['Sunrise Herb', 'Silver Azalea'],
    'qualityConversions': const <String, Object?>{
      'Sunrise Herb': <String, Object?>{
        'high': <String, Object?>{
          'name': 'High-Quality Sunrise Herb',
          'ratio': 3,
        },
        'special': <String, Object?>{
          'name': 'Special Sunrise Herb',
          'ratio': 5,
        },
      },
      'Silver Azalea': <String, Object?>{
        'high': <String, Object?>{
          'name': 'High-Quality Silver Azalea',
          'ratio': 3,
        },
        'special': <String, Object?>{
          'name': 'Special Silver Azalea',
          'ratio': 5,
        },
      },
    },
    'marketIds': const <String, String>{
      'Sunrise Herb': '5401',
      'Silver Azalea': '5402',
    },
    ...supportingDataOverrides,
  },
  collisions: const <CaseCollision>[],
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: <String>[name],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

Recipe _leaf(String name, {String? sourceNote}) =>
    _recipe(name, 'gathered', const <Ingredient>[], sourceNote: sourceNote);

Recipe _recipe(
  String name,
  String type,
  List<Ingredient> ingredients, {
  String? method,
  String? sourceNote,
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: type == 'gathered' ? 'Materials' : 'Quest Recipes',
  method: method,
  ingredients: ingredients,
  marketId: null,
  sourceNote: sourceNote,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  variants: variants,
  defaultVariantId: defaultVariantId,
);

Future<void> setPlannerTestSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
