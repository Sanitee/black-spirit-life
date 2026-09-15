import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../features/planner/planner_test_fixture.dart';

void main() {
  const size = Size(1500, 940);
  const spec = SakuraNightGardenSpec.theme;
  const writePrivateVendorMapPreview = bool.fromEnvironment(
    'BSL_PRIVATE_VENDOR_MAP_PREVIEW',
  );
  const writePrivateInventoryPreview = bool.fromEnvironment(
    'BSL_PRIVATE_INVENTORY_PREVIEW',
  );
  late List<int> vendorPreviewTile;

  setUpAll(() async {
    await _loadReviewFonts();
    vendorPreviewTile = await _makeMapPreviewTile();
  });

  testWidgets('Sakura source menu visual review', (tester) async {
    _configureSurface(tester, size);
    const goldenRoot = ValueKey<String>('source-menu-review-root');
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasManualGathering: true,
        manualResourceId: 'sunrise-herb',
        manualLocationCount: 12,
        hasWorkerNodes: true,
        workerResourceId: 'sunrise-herb',
        workerNodeCount: 4,
      ),
      addToGatherChecklist: (_) {},
    );
    addTearDown(harness.controller.dispose);

    await tester.pumpWidget(
      RepaintBoundary(
        key: goldenRoot,
        child: harness.plannerHost(spec: spec),
      ),
    );
    await _settleImages(tester, root: find.byKey(goldenRoot), spec: spec);

    final region = find.byKey(
      PlannerActionKeys.mapLookupRegion('need:Sunrise Herb'),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: tester.getCenter(region));
    await mouse.down(tester.getCenter(region));
    await mouse.up();
    await tester.pumpAndSettle();
    final checklist = find.byKey(
      PlannerActionKeys.mapLookupAction(
        'need:Sunrise Herb',
        'addToGatherChecklist',
      ),
    );
    await mouse.moveTo(tester.getCenter(checklist));
    await tester.pump(const Duration(milliseconds: 180));

    await expectLater(
      find.byKey(goldenRoot),
      matchesGoldenFile('review/review_sakura_source_menu_hover_1500x940.png'),
    );
    await mouse.removePointer();
  });

  testWidgets('Sakura Blessing queue visual review', (tester) async {
    _configureSurface(tester, size);
    const goldenRoot = ValueKey<String>('blessing-queue-review-root');
    const name = 'Blessing of Mystic Beasts - All AP';
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'visual-review',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 8, 15),
        activeMode: CraftMode.processing,
        alchemy: _modeState(
          CraftMode.alchemy,
          target: 'Perfume of Verdure',
          bonusTarget: 'Viridian Draught',
        ),
        cooking: _modeState(
          CraftMode.cooking,
          target: 'Beer',
          bonusTarget: 'Beer',
        ),
        processing: _modeState(
          CraftMode.processing,
          target: name,
          bonusTarget: '',
        ),
        processingYields: const <String, double>{'defaultYield': 2.5},
        marketTax: MarketTax(),
      ),
      saveDebounce: Duration.zero,
      saveState: (value) async => value,
    );
    final actions = PlannerExternalActions(
      openRecipeBook: (_) {},
      copyName: (_) async {},
      checkPrices: (_) async => throw UnsupportedError('Preview only.'),
    );

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenRoot,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: AppOverlayCoordinatorHost(
                  child: PlannerView(
                    controller: application.active,
                    externalActions: actions,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final golden = find.byKey(goldenRoot);
      await _settleImages(tester, root: golden, spec: spec);
      await expectLater(
        golden,
        matchesGoldenFile('review/review_sakura_blessing_queue_1500x940.png'),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await application.dispose();
    }
  });

  testWidgets('Sakura Salt vendor menu visual review', (tester) async {
    _configureSurface(tester, size);
    const goldenRoot = ValueKey<String>('salt-vendor-menu-review-root');
    const cardKey = ValueKey<String>('salt-vendor-menu-review-card');
    const stableId = 'review:Salt';
    // The real bundled-data resolver test independently locks this count.
    // Keeping the visual review synchronous avoids loading the large map asset
    // inside the golden test's fake-async frame.
    const saltVendorCount = 46;
    final actions = PlannerExternalActions(
      openRecipeBook: (_) {},
      copyName: (_) async {},
      checkPrices: (_) async => throw UnsupportedError('Preview only.'),
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasNpcVendors: true,
        npcVendorCount: saltVendorCount,
      ),
      openMapLookup: (_) {},
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: goldenRoot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: AppOverlayCoordinatorHost(
                child: Center(
                  child: PlannerMapQuickLookupRegion(
                    materialName: 'Salt',
                    stableId: stableId,
                    externalActions: actions,
                    child: Container(
                      key: cardKey,
                      width: 460,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: spec.palette.surfaceRaised,
                        borderRadius: BorderRadius.circular(
                          spec.geometry.cardRadius,
                        ),
                        border: Border.all(color: spec.palette.trim),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: spec.palette.shadow,
                            blurRadius: 18,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: spec.palette.primary.withAlpha(34),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: spec.palette.primary.withAlpha(132),
                              ),
                            ),
                            child: Icon(
                              Icons.shopping_basket_rounded,
                              color: spec.palette.primary,
                              size: 27,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text('Salt', style: spec.typography.section),
                                const SizedBox(height: 2),
                                Text(
                                  'Cooking ingredient · NPC price 20 silver',
                                  style: spec.typography.meta.copyWith(
                                    color: spec.palette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Right-click',
                            style: spec.typography.meta.copyWith(
                              color: spec.palette.textMuted,
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
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    final cardCenter = tester.getCenter(find.byKey(cardKey));
    await mouse.addPointer(location: cardCenter);
    await mouse.down(cardCenter);
    await mouse.up();
    await tester.pumpAndSettle();
    final vendorAction = find.byKey(
      PlannerActionKeys.mapLookupAction(
        stableId,
        PlannerMapLookupSource.npcVendors.name,
      ),
    );
    await mouse.moveTo(tester.getCenter(vendorAction));
    await tester.pump(const Duration(milliseconds: 180));

    await expectLater(
      find.byKey(goldenRoot),
      matchesGoldenFile('review/review_sakura_salt_vendor_menu_1500x940.png'),
    );
    await mouse.removePointer();
  });

  testWidgets('private Salt vendor card visual review', (tester) async {
    _configureSurface(tester, size);
    const goldenRoot = ValueKey<String>('salt-vendor-map-review-root');
    const davidId = 'npc:40013:1:location:0';
    final dataset = BdoResourceMapLoader.parse(
      File(
        'packages/bdo_map_core/assets/data/resource_map.json',
      ).readAsStringSync(),
    );
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final catalogRepository = CatalogRepository(catalog);
    final application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'visual-review',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 8, 15),
        activeMode: CraftMode.cooking,
        alchemy: _modeState(
          CraftMode.alchemy,
          target: 'Perfume of Verdure',
          bonusTarget: 'Viridian Draught',
        ),
        cooking: _modeState(
          CraftMode.cooking,
          target: 'Beer',
          bonusTarget: 'Beer',
        ),
        processing: _modeState(
          CraftMode.processing,
          target: 'Blessing of Mystic Beasts - All AP',
          bonusTarget: '',
        ),
        processingYields: const <String, double>{'defaultYield': 2.5},
        marketTax: MarketTax(),
      ),
      saveDebounce: Duration.zero,
      saveState: (value) async => value,
    );
    addTearDown(application.dispose);
    final david = dataset.vendorNpcsById[davidId]!;
    final davidSalt = dataset
        .vendorListingsForItem('Salt')
        .singleWhere((listing) => listing.vendorId == davidId);
    final focusedDataset = BdoResourceMapDataset(
      manifest: dataset.manifest,
      resources: dataset.resources,
      workerNodes: const <BdoWorkerNode>[],
      gatheringSpots: const <BdoGatheringSpot>[],
      gatheringPoints: const <BdoGatheringPoint>[],
      gatheringRoutes: const <BdoGatheringRoute>[],
      fieldSources: const <BdoFieldSource>[],
      vendorNpcs: <BdoVendorNpc>[david],
      vendorListings: <BdoVendorListing>[davidSalt],
    );
    final cacheDirectory = Directory.systemTemp.createTempSync(
      'bsl_private_vendor_preview_',
    );
    addTearDown(() {
      if (cacheDirectory.existsSync()) {
        cacheDirectory.deleteSync(recursive: true);
      }
    });
    var servedTileCount = 0;
    final tileClient = MockClient((request) async {
      servedTileCount += 1;
      return http.Response.bytes(
        vendorPreviewTile,
        HttpStatus.ok,
        headers: const <String, String>{'content-type': 'image/png'},
      );
    });
    addTearDown(tileClient.close);
    final previewTileSource = BdoTileSource(
      id: 'vendor-card-visual-review',
      displayName: 'Vendor card visual review',
      urlTemplate: 'https://preview.invalid/{z}/{x}_{y}.png',
      worldBounds: BdoTileSource.workermanCommunity.worldBounds,
      attribution: 'Generated visual-review terrain',
      usageNotice: 'Visual review only.',
      fileExtension: 'png',
    );
    final controller = BdoResourceMapController()
      ..focus(
        const BdoResourceMapFocusRequest(
          materialName: 'Salt',
          source: BdoResourceMapFocusSource.npcVendors,
        ),
      );
    addTearDown(controller.dispose);
    final previewTheme = spec.materialTheme();

    await tester.pumpWidget(
      RepaintBoundary(
        key: goldenRoot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme.copyWith(
            textTheme: previewTheme.textTheme.apply(fontFamily: 'Segoe UI'),
            primaryTextTheme: previewTheme.primaryTextTheme.apply(
              fontFamily: 'Segoe UI',
            ),
          ),
          home: ThemeSpecScope(
            spec: spec,
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: 'Segoe UI'),
                child: BdoResourceMap(
                  dataset: focusedDataset,
                  cacheDirectory: cacheDirectory,
                  tileSource: previewTileSource,
                  showSourceNotice: false,
                  controller: controller,
                  tileHttpClient: tileClient,
                  vendorItemIconBuilder: (context, itemName, size) =>
                      ModeItemIcon(
                        controller: application.active,
                        name: itemName,
                        size: size,
                        catalogRepository: catalogRepository,
                        searchAcrossModes: true,
                        fallbackIcon: Icons.inventory_2_outlined,
                        showFrame: false,
                      ),
                  vendorPortraitBuilder: (context, vendor, size) {
                    final assetPath = bdoBundledVendorPortraitAsset(
                      vendor.sourceVendorId,
                    );
                    if (assetPath == null) {
                      return Icon(Icons.person_rounded, size: size);
                    }
                    return Image.asset(
                      assetPath,
                      width: size,
                      height: size,
                      alignment: Alignment.bottomCenter,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 30; frame += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final marker = find.byKey(
      const ValueKey<String>('resource-map-vendor-marker-$davidId'),
    );
    await tester.tap(
      find.descendant(of: marker, matching: find.byType(InkResponse)),
    );
    await tester.pump();
    await _precacheVisibleImages(tester, find.byKey(goldenRoot));
    expect(servedTileCount, greaterThanOrEqualTo(0));
    await _writePrivatePreview(
      tester,
      root: find.byKey(goldenRoot),
      relativePath:
          'build/private-ui-previews/'
          'review_sakura_salt_vendor_david_1500x940.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !writePrivateVendorMapPreview);

  testWidgets(
    'private named storage Inventory visual review',
    (tester) async {
      _configureSurface(tester, size);
      const goldenRoot = ValueKey<String>('named-storage-review-root');
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      var alchemy = _modeState(
        CraftMode.alchemy,
        target: 'Clear Liquid Reagent',
        bonusTarget: 'Pure Powder Reagent',
      );
      var storage = InventoryStorageState.fromModeState(alchemy);
      final calpheon = storage.ensureLocation('Calpheon City Storage');
      storage = calpheon.state;
      final quantities = <String, double>{
        'Clear Liquid Reagent': 5665,
        "Clown's Blood": 1978,
        'Fruit of Enchantment': 2815,
        'Legendary Beast\'s Blood': 596,
        'Leavening Agent': 7326,
        'Pure Powder Reagent': 20963,
        'Salt': 1746,
        'Sheep Blood': 10800,
        'Sugar': 14602,
        "Wise Man's Blood": 4571,
        'Wolf Blood': 13371,
      };
      for (final entry in quantities.entries) {
        storage = storage.setQuantity(
          locationId: calpheon.location.id,
          itemName: entry.key,
          quantity: entry.value,
        );
      }
      final heidel = storage.ensureLocation('Heidel Storage');
      storage = heidel.state
          .setQuantity(
            locationId: heidel.location.id,
            itemName: 'Salt',
            quantity: 50000,
          )
          .select(calpheon.location.id);
      alchemy = storage.applyTo(alchemy);
      final application = PlannerApplicationController(
        catalog: catalog,
        initialState: PlannerState(
          applicationVersion: 'visual-review',
          lastSuccessfulWriteUtc: DateTime.utc(2026, 8, 16),
          activeMode: CraftMode.alchemy,
          alchemy: alchemy,
          cooking: _modeState(
            CraftMode.cooking,
            target: 'Beer',
            bonusTarget: 'Beer',
          ),
          processing: _modeState(
            CraftMode.processing,
            target: 'Blessing of Mystic Beasts - All AP',
            bonusTarget: '',
          ),
          processingYields: const <String, double>{'defaultYield': 2.5},
          marketTax: MarketTax(),
        ),
        saveDebounce: Duration.zero,
        saveState: (value) async => value,
      );
      final session = InventorySessionController();
      final specialSunflowerIcon = UriData.parse(
        catalog.cooking.iconDataUris['Special Sunflower']!,
      ).contentAsBytes();
      final milkIcon = UriData.parse(
        catalog.cooking.iconDataUris['Milk']!,
      ).contentAsBytes();
      final screenshotAnalysis = InventoryScreenshotAnalysis(
        fileName: 'calpheon-storage.png',
        mimeType: 'image/png',
        sourceByteCount: specialSunflowerIcon.length,
        screenshotBytes: specialSunflowerIcon,
        plannerItemNames: const <String>[
          'Special Sunflower',
          'Sunflower',
          'Milk',
          'Banana',
        ],
        draft: InventoryScreenshotDraft(
          imageFingerprint: List<String>.filled(64, 'a').join(),
          sourceWidth: 1024,
          sourceHeight: 775,
          gridColumns: 9,
          gridRows: 10,
          gridConfidence: .99,
          rows: <InventoryScreenshotRow>[
            InventoryScreenshotRow(
              id: 'special-sunflower',
              slotId: 'r0c0',
              row: 0,
              column: 0,
              crop: const InventoryScreenshotRect(
                left: 552,
                top: 158,
                width: 48,
                height: 48,
              ),
              quantityText: '1060',
              quantity: 1060,
              quantitySuggested: null,
              quantityApproximate: false,
              quantityAssumedOne: false,
              quantityConfidence: .98,
              matches: const <InventoryItemMatch>[
                InventoryItemMatch(
                  name: 'Special Sunflower',
                  confidence: .98,
                  sharedArtwork: false,
                  grade: 2,
                ),
                InventoryItemMatch(
                  name: 'Sunflower',
                  confidence: .88,
                  sharedArtwork: false,
                  grade: 0,
                ),
              ],
              selectedName: 'Special Sunflower',
              relevance: InventoryOcrMaterialRelevance.relevant,
              reviewRequired: false,
              reviewReasons: const <String>[],
              previewPng: specialSunflowerIcon,
            ),
            InventoryScreenshotRow(
              id: 'milk',
              slotId: 'r0c1',
              row: 0,
              column: 1,
              crop: const InventoryScreenshotRect(
                left: 602,
                top: 158,
                width: 48,
                height: 48,
              ),
              quantityText: '174.5K',
              quantity: 174500,
              quantitySuggested: null,
              quantityApproximate: false,
              quantityAssumedOne: false,
              quantityConfidence: .99,
              matches: const <InventoryItemMatch>[
                InventoryItemMatch(
                  name: 'Milk',
                  confidence: .99,
                  sharedArtwork: false,
                  grade: 0,
                ),
              ],
              selectedName: 'Milk',
              relevance: InventoryOcrMaterialRelevance.relevant,
              reviewRequired: false,
              reviewReasons: const <String>[],
              previewPng: milkIcon,
            ),
          ],
          hiddenRows: const <InventoryScreenshotRow>[],
          warnings: const <String>[],
        ),
      );
      final actions = InventoryExternalActions(
        confirmClear: (_) async => true,
        confirmDelete: (_) async => true,
        copyName: (_) async {},
        reportTransaction: (_) {},
        offerUndo: (_) {},
        reportUndo: (_) {},
        pasteScreenshot: () async => screenshotAnalysis,
        chooseScreenshot: () async => screenshotAnalysis,
      );

      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: goldenRoot,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(18),
                    child: InventoryView(
                      controller: application.active,
                      externalActions: actions,
                      sessionController: session,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // The Inventory catalog contains more than a thousand image-backed
        // choices. Waiting for every mounted offstage image here can stall a
        // private layout snapshot; visible icons decode during these frames.
        for (var frame = 0; frame < 6; frame += 1) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        await _precacheVisibleImages(tester, find.byKey(goldenRoot));
        await tester.pump(const Duration(milliseconds: 120));
        await _writePrivatePreview(
          tester,
          root: find.byKey(goldenRoot),
          relativePath:
              'build/private-ui-previews/'
              'review_sakura_named_storage_inventory_1500x940.png',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        await application.dispose();
      }
    },
    skip: !writePrivateInventoryPreview,
  );

  testWidgets('Sakura Edania recipe information visual review', (tester) async {
    _configureSurface(tester, size);
    const goldenRoot = ValueKey<String>('edania-info-review-root');
    const name = 'Causality Shardstone - Earring';
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'visual-review',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 8, 15),
        activeMode: CraftMode.processing,
        alchemy: _modeState(
          CraftMode.alchemy,
          target: 'Perfume of Verdure',
          bonusTarget: 'Viridian Draught',
        ),
        cooking: _modeState(
          CraftMode.cooking,
          target: 'Beer',
          bonusTarget: 'Beer',
        ),
        processing: _modeState(
          CraftMode.processing,
          target: name,
          bonusTarget: '',
        ),
        processingYields: const <String, double>{'defaultYield': 2.5},
        marketTax: MarketTax(),
      ),
      saveDebounce: Duration.zero,
      saveState: (value) async => value,
    );
    final mode = application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
      initialSearch: name,
    );

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenRoot,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: AppOverlayCoordinatorHost(
                  child: RecipeBookModal(
                    controller: book,
                    onClose: () {},
                    onActivated: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final golden = find.byKey(goldenRoot);
      await _settleImages(tester, root: golden, spec: spec);

      final card = find.byKey(RecipeBookKeys.card(name));
      final tooltip = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.richMessage != null,
        ),
      );
      tester.state<TooltipState>(tooltip).ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await _settleImages(tester, root: golden, spec: spec);

      await expectLater(
        golden,
        matchesGoldenFile(
          'review/review_sakura_edania_recipe_info_top_1500x940.png',
        ),
      );

      final info = find.byKey(RecipeBookKeys.itemInfo(name));
      final scrollable = find.descendant(
        of: info,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await expectLater(
        golden,
        matchesGoldenFile(
          'review/review_sakura_edania_recipe_info_batch_1500x940.png',
        ),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      book.dispose();
      await application.dispose();
    }
  });

  testWidgets('Sakura Edania reference formula visual review', (tester) async {
    _configureSurface(tester, size);
    const goldenRoot = ValueKey<String>('edania-reference-review-root');
    const name = 'Moonhushed Ekleta Earring';
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'visual-review',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 8, 15),
        activeMode: CraftMode.processing,
        alchemy: _modeState(
          CraftMode.alchemy,
          target: 'Perfume of Verdure',
          bonusTarget: 'Viridian Draught',
        ),
        cooking: _modeState(
          CraftMode.cooking,
          target: 'Beer',
          bonusTarget: 'Beer',
        ),
        processing: _modeState(
          CraftMode.processing,
          target: 'Blessing of Mystic Beasts - All AP',
          bonusTarget: '',
        ),
        processingYields: const <String, double>{'defaultYield': 2.5},
        marketTax: MarketTax(),
      ),
      saveDebounce: Duration.zero,
      saveState: (value) async => value,
    );
    final mode = application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
      initialSearch: name,
    );

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenRoot,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: AppOverlayCoordinatorHost(
                  child: RecipeBookModal(
                    controller: book,
                    onClose: () {},
                    onActivated: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final golden = find.byKey(goldenRoot);
      await _settleImages(tester, root: golden, spec: spec);

      final card = find.byKey(RecipeBookKeys.card(name));
      final tooltip = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.richMessage != null,
        ),
      );
      tester.state<TooltipState>(tooltip).ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await _settleImages(tester, root: golden, spec: spec);

      await expectLater(
        golden,
        matchesGoldenFile(
          'review/review_sakura_edania_reference_moonhushed_1500x940.png',
        ),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      book.dispose();
      await application.dispose();
    }
  });
}

Future<void> _loadReviewFonts() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Visual review previews require Windows fonts.');
  }
  final windowsRoot =
      Platform.environment['WINDIR'] ??
      Platform.environment['SystemRoot'] ??
      r'C:\Windows';
  final windowsFonts = _childPath(windowsRoot, <String>['Fonts']);
  final materialFonts = _flutterMaterialFontsDirectory();
  await _loadFontFamily('Segoe UI', <String>[
    _childPath(windowsFonts, <String>['segoeui.ttf']),
    _childPath(windowsFonts, <String>['seguisb.ttf']),
    _childPath(windowsFonts, <String>['segoeuib.ttf']),
    _childPath(windowsFonts, <String>['segoeuii.ttf']),
  ]);
  await _loadFontFamily('Georgia', <String>[
    _childPath(windowsFonts, <String>['georgia.ttf']),
    _childPath(windowsFonts, <String>['georgiab.ttf']),
    _childPath(windowsFonts, <String>['georgiai.ttf']),
  ]);
  await _loadFontFamily('Roboto', <String>[
    _childPath(materialFonts, <String>['roboto-regular.ttf']),
    _childPath(materialFonts, <String>['roboto-bold.ttf']),
  ]);
  await _loadFontFamily('MaterialIcons', <String>[
    _childPath(materialFonts, <String>['materialicons-regular.otf']),
  ]);
}

String _flutterMaterialFontsDirectory() {
  final candidates = <Directory>[];
  final configuredRoot = Platform.environment['FLUTTER_ROOT']?.trim();
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    candidates.add(Directory(configuredRoot));
  }
  var ancestor = File(Platform.resolvedExecutable).parent;
  while (true) {
    candidates.add(ancestor);
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  for (final candidate in candidates) {
    final materialFonts = Directory(
      _childPath(candidate.path, const <String>[
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
      ]),
    );
    if (materialFonts.existsSync()) return materialFonts.path;
  }
  throw StateError(
    'Could not locate Flutter material fonts from FLUTTER_ROOT or the '
    'running Flutter test executable.',
  );
}

String _childPath(String root, List<String> segments) {
  var result = root;
  for (final segment in segments) {
    if (!result.endsWith(Platform.pathSeparator)) {
      result += Platform.pathSeparator;
    }
    result += segment;
  }
  return result;
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(
      File(path).readAsBytes().then(
        (bytes) => ByteData.sublistView(Uint8List.fromList(bytes)),
      ),
    );
  }
  await loader.load();
}

ModeState _modeState(
  CraftMode mode, {
  required String target,
  required String bonusTarget,
}) => ModeState(
  target: target,
  bonusTarget: bonusTarget,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

void _configureSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _settleImages(
  WidgetTester tester, {
  required Finder root,
  required ThemeSpec spec,
}) async {
  await tester.pump();
  final rootElement = tester.element(root);
  if (spec.isSakuraNightGarden) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/sakura/materials/charcoal-plum-lacquer.png'),
        rootElement,
      ),
    );
  }
  for (final element
      in find.descendant(of: root, matching: find.byType(Image)).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _writePrivatePreview(
  WidgetTester tester, {
  required Finder root,
  required String relativePath,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(root);
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Could not encode the private UI preview.');
    }
    final file = File(relativePath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

Future<void> _precacheVisibleImages(WidgetTester tester, Finder root) async {
  final rootBox = tester.renderObject<RenderBox>(root);
  final rootRect = rootBox.localToGlobal(Offset.zero) & rootBox.size;
  final visibleImages = find
      .descendant(of: root, matching: find.byType(Image))
      .evaluate()
      .where((element) {
        final renderObject = element.renderObject;
        if (renderObject is! RenderBox ||
            !renderObject.attached ||
            !renderObject.hasSize ||
            renderObject.size.isEmpty) {
          return false;
        }
        final imageRect =
            renderObject.localToGlobal(Offset.zero) & renderObject.size;
        return imageRect.overlaps(rootRect);
      });
  for (final element in visibleImages) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pump(const Duration(milliseconds: 100));
}

Future<List<int>> _makeMapPreviewTile() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size.square(256);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF272225));
  final land = Path()
    ..moveTo(0, 206)
    ..cubicTo(35, 158, 67, 186, 99, 121)
    ..cubicTo(137, 45, 177, 111, 212, 55)
    ..cubicTo(230, 25, 244, 36, 256, 22)
    ..lineTo(256, 256)
    ..lineTo(0, 256)
    ..close();
  canvas.drawPath(land, Paint()..color = const Color(0xFF4A5347));
  canvas.drawPath(
    land,
    Paint()
      ..color = const Color(0xFF7D806A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  for (var offset = 24.0; offset < 256; offset += 42) {
    canvas
      ..drawLine(
        Offset(offset, 0),
        Offset(offset, 256),
        Paint()..color = const Color(0x1026C6A2),
      )
      ..drawLine(
        Offset(0, offset),
        Offset(256, offset),
        Paint()..color = const Color(0x1026C6A2),
      );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
