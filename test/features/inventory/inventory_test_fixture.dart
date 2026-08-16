import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/shared/custom_icon_store_scope.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class InventoryTestHarness {
  InventoryTestHarness({
    bool showDeleteTools = false,
    int additionalHerbs = 0,
    SavePlannerState? saveState,
    PlannerState? initialState,
    AcquireInventoryScreenshot? pasteScreenshot,
    AcquireInventoryScreenshot? chooseScreenshot,
  }) : session = InventorySessionController(),
       controller = PlannerApplicationController(
         catalog: inventoryCatalog(additionalHerbs: additionalHerbs),
         initialState:
             initialState ??
             inventoryDocument(showDeleteTools: showDeleteTools),
         saveState: saveState ?? (state) async => state,
         saveDebounce: Duration.zero,
       ) {
    actions = InventoryExternalActions(
      confirmClear: (request) async {
        clearRequests.add(request);
        return clearApprovals.isEmpty ? true : clearApprovals.removeAt(0);
      },
      confirmDelete: (request) async {
        deleteRequests.add(request);
        return deleteApprovals.isEmpty ? true : deleteApprovals.removeAt(0);
      },
      copyName: (name) async => copiedNames.add(name),
      reportTransaction: transactionNotices.add,
      offerUndo: undoOffers.add,
      reportUndo: undoResults.add,
      pasteScreenshot: pasteScreenshot,
      chooseScreenshot: chooseScreenshot,
    );
  }

  final PlannerApplicationController controller;
  final InventorySessionController session;
  late final InventoryExternalActions actions;
  final List<bool> clearApprovals = <bool>[];
  final List<bool> deleteApprovals = <bool>[];
  final List<InventoryClearRequest> clearRequests = <InventoryClearRequest>[];
  final List<InventoryDeleteRequest> deleteRequests =
      <InventoryDeleteRequest>[];
  final List<String> copiedNames = <String>[];
  final List<InventoryTransactionNotice> transactionNotices =
      <InventoryTransactionNotice>[];
  final List<InventoryUndoOffer> undoOffers = <InventoryUndoOffer>[];
  final List<InventoryUndoResult> undoResults = <InventoryUndoResult>[];

  Widget host({
    CustomIconStore? iconStore,
    TextScaler textScaler = TextScaler.noScaling,
    ThemeSpec spec = StandardSpec.theme,
  }) => MaterialApp(
    theme: spec.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: ColoredBox(
          color: StandardSpec.palette.canvas,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: iconStore == null
                ? InventoryView(
                    controller: controller.active,
                    externalActions: actions,
                    sessionController: session,
                  )
                : CustomIconStoreScope(
                    store: iconStore,
                    child: InventoryView(
                      controller: controller.active,
                      externalActions: actions,
                      sessionController: session,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    session.dispose();
  }
}

Future<void> pumpInventory(
  WidgetTester tester,
  InventoryTestHarness harness, {
  Size size = const Size(1200, 752),
  CustomIconStore? iconStore,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeSpec spec = StandardSpec.theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    harness.dispose();
  });
  await tester.pumpWidget(
    harness.host(iconStore: iconStore, textScaler: textScaler, spec: spec),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

PlannerState inventoryDocument({required bool showDeleteTools}) => PlannerState(
  applicationVersion: 'inventory-test',
  lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 20),
  activeMode: CraftMode.alchemy,
  alchemy: ModeState(
    target: 'Clear Liquid Reagent',
    want: 10,
    bonusTarget: 'Clear Liquid Reagent',
    inventory: const <String, double>{'Sunrise Herb': 3, 'Silver Azalea': 7},
    ingredientMeta: <String, IngredientMetadata>{
      'Sunrise Herb': IngredientMetadata(
        category: 'Herbs',
        sourceNote: 'Gathered near Heidel roads.',
        searchKeywords: 'serendia dawn gathering',
        vendor: 'Material Vendor Lara',
        location: 'Heidel',
      ),
    },
    customCategories: const <String>['Field Kit'],
    market: MarketState(),
    appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
  ),
  cooking: _emptyMode(CraftMode.cooking, target: 'Beer'),
  processing: _emptyMode(CraftMode.processing, target: 'Wheat Flour'),
  processingYields: const <String, double>{'defaultYield': 2.5},
  marketTax: MarketTax(),
  showDeleteTools: showDeleteTools,
);

ModeState _emptyMode(CraftMode mode, {required String target}) => ModeState(
  target: target,
  bonusTarget: mode == CraftMode.processing ? '' : target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

CatalogSnapshot inventoryCatalog({int additionalHerbs = 0}) => CatalogSnapshot(
  sourceSha256: 'inventory-real-domain-fixture',
  sourceByteCount: 1,
  alchemy: ModeCatalog(
    mode: CraftMode.alchemy,
    items: <String, Recipe>{
      'Clear Liquid Reagent': _recipe(
        'Clear Liquid Reagent',
        type: 'alchemy',
        group: 'Alchemy Reagents',
        ingredients: <Ingredient>[
          _ingredient('Sunrise Herb', 1),
          _ingredient('Salt', 1),
        ],
      ),
      'Pure Powder Reagent': _recipe(
        'Pure Powder Reagent',
        type: 'alchemy',
        group: 'Alchemy Reagents',
        ingredients: <Ingredient>[_ingredient('Silver Azalea', 1)],
      ),
      'Sunrise Herb': _leaf(
        'Sunrise Herb',
        group: 'Wild Herbs',
        sourceNote: 'Collected from wild herb nodes.',
      ),
      'Silver Azalea': _leaf('Silver Azalea', group: 'Wild Herbs'),
      'Salt': _leaf(
        'Salt',
        group: 'Vendor Materials',
        vendor: 'Innkeeper',
        location: 'Velia',
      ),
      'Blood Wolf Blood': _leaf(
        'Blood Wolf Blood',
        group: 'Creature Blood',
        sourceNote: 'Gathered from Blood Wolves in Kamasylvia.',
      ),
      for (var index = 1; index <= additionalHerbs; index++)
        'Silver Azalea Reserve ${index.toString().padLeft(2, '0')}': _leaf(
          'Silver Azalea Reserve ${index.toString().padLeft(2, '0')}',
          group: 'Wild Herbs',
          location: 'Balenos herb route',
        ),
    },
    iconDataUris: const <String, String>{
      'Clear Liquid Reagent': _onePixelPng,
      'Pure Powder Reagent': _onePixelPng,
      'Sunrise Herb': _onePixelPng,
      'Silver Azalea': _onePixelPng,
      'Salt': _onePixelPng,
      'Blood Wolf Blood': _onePixelPng,
    },
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{
      'Morning Herb': 'Sunrise Herb',
      'Wolf Blood': 'Blood Wolf Blood',
    },
  ),
  cooking: ModeCatalog(
    mode: CraftMode.cooking,
    items: <String, Recipe>{
      'Beer': _recipe(
        'Beer',
        type: 'cooking',
        group: 'Cooking',
        ingredients: <Ingredient>[_ingredient('Wheat', 5)],
      ),
      'Wheat': _leaf('Wheat', group: 'Crops'),
    },
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  ),
  processing: ModeCatalog(
    mode: CraftMode.processing,
    items: <String, Recipe>{
      'Wheat Flour': _recipe(
        'Wheat Flour',
        type: 'processing',
        group: 'Grinding',
        ingredients: <Ingredient>[_ingredient('Wheat', 1)],
      ),
      'Wheat': _leaf('Wheat', group: 'Crops'),
    },
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  ),
  supportingData: const <String, Object?>{},
  collisions: const <CaseCollision>[],
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: <String>[name],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

Recipe _leaf(
  String name, {
  required String group,
  String? sourceNote,
  String? vendor,
  String? location,
}) => _recipe(
  name,
  type: 'gathered',
  group: group,
  ingredients: const <Ingredient>[],
  sourceNote: sourceNote,
  vendor: vendor,
  location: location,
);

Recipe _recipe(
  String name, {
  required String type,
  required String group,
  required List<Ingredient> ingredients,
  String? sourceNote,
  String? vendor,
  String? location,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: group,
  method: type == 'processing' ? 'Grinding' : null,
  ingredients: ingredients,
  marketId: null,
  sourceNote: sourceNote,
  vendor: vendor,
  location: location,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
);

const String _onePixelPng =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
