import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

void main() {
  test(
    'public identity is isolated from accepted and former state targets',
    () {
      const acceptedStateDirectory = 'BDO Craft Planner Flutter';
      const appDataRoot = r'C:\Users\Test\AppData\Roaming';
      final policy = PlannerStatePathPolicy.fromEnvironment(const {
        'APPDATA': appDataRoot,
      });

      expect(AppIdentity.displayName, 'Black Spirit Life');
      expect(AppIdentity.releaseChannel, 'win-x64-stable');
      expect(
        AppIdentity.installerPackageId,
        isNot(AppIdentity.localCacheDirectoryName),
      );
      expect(AppIdentity.stateDirectoryName, isNot(acceptedStateDirectory));
      expect(
        AppIdentity.stateDirectoryName,
        isNot(AppIdentity.formerStateDirectoryName),
      );
      expect(
        AppIdentity.stateDirectoryName,
        AppIdentity.stableStateDirectoryName,
      );
      expect(
        policy.applicationDirectory.path,
        '$appDataRoot${Platform.pathSeparator}'
        '${AppIdentity.stateDirectoryName}',
      );
      expect(
        policy.applicationDirectory.path,
        isNot('$appDataRoot${Platform.pathSeparator}$acceptedStateDirectory'),
      );
      expect(policy.formerNativeApplicationDirectory, isNull);
      expect(policy.allowLegacyMigration, isFalse);
      expect(AppIdentity.importFormerProfilesOnFirstLaunch, isFalse);
    },
  );

  testWidgets(
    'top tabs lazily open the shared map and retain both workspaces',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);

      final plannerTab = _workspaceTab('Craft Planner');
      final mapTab = _workspaceTab('Resource Map');
      expect(plannerTab, findsOneWidget);
      expect(mapTab, findsOneWidget);
      expect(_isSelected(tester, plannerTab), isTrue);
      expect(_isSelected(tester, mapTab), isFalse);
      expect(_visibleTabLabel(plannerTab, 'Craft Planner'), findsOneWidget);
      expect(_visibleTabLabel(mapTab, 'Resource Map'), findsNothing);
      expect(tester.getSize(plannerTab).width, greaterThan(100));
      expect(tester.getSize(mapTab).width, 52);
      expect(find.byKey(AppTitleBar.iconFrameKey), findsNothing);
      expect(
        find.byKey(AppTitleTabStrip.artworkKey('Craft Planner')),
        findsOneWidget,
      );
      expect(
        find.byKey(AppTitleTabStrip.artworkKey('Resource Map')),
        findsOneWidget,
      );
      expect(
        ((tester
                            .widget<Image>(
                              find.descendant(
                                of: plannerTab,
                                matching: find.byType(Image),
                              ),
                            )
                            .image
                        as ResizeImage)
                    .imageProvider
                as AssetImage)
            .assetName,
        'assets/app/bdo_tool_icon.png',
      );
      expect(
        ((tester
                            .widget<Image>(
                              find.descendant(
                                of: mapTab,
                                matching: find.byType(Image),
                              ),
                            )
                            .image
                        as ResizeImage)
                    .imageProvider
                as AssetImage)
            .assetName,
        'assets/app/bdo_resource_map_icon.png',
      );
      expect(find.byType(PlannerView), findsOneWidget);
      expect(
        find.byType(ResourceMapWorkspace, skipOffstage: false),
        findsNothing,
        reason: 'the heavier map workspace should be created on first use',
      );

      final plannerElement = tester.element(find.byType(PlannerView));
      final plannerWidget = tester.widget<PlannerView>(
        find.byType(PlannerView),
      );
      final plannerTarget = harness.bundle.controller.active.state.value.target;

      await tester.tap(mapTab);
      await _pumpUntilMapIsReady(tester);

      expect(_isSelected(tester, plannerTab), isFalse);
      expect(_isSelected(tester, mapTab), isTrue);
      expect(_visibleTabLabel(plannerTab, 'Craft Planner'), findsNothing);
      expect(_visibleTabLabel(mapTab, 'Resource Map'), findsOneWidget);
      expect(tester.getSize(plannerTab).width, 52);
      expect(tester.getSize(mapTab).width, greaterThan(100));
      expect(find.byType(ResourceMapWorkspace), findsOneWidget);
      expect(find.byType(BdoResourceMap), findsOneWidget);
      final resourceMap = tester.widget<BdoResourceMap>(
        find.byType(BdoResourceMap),
      );
      expect(resourceMap.workerOutputIconBuilder, isNotNull);
      final outputArtwork = resourceMap.workerOutputIconBuilder!(
        tester.element(find.byType(BdoResourceMap)),
        resourceMap.dataset.resources.first,
        24,
      );
      expect(outputArtwork, isA<ModeItemIcon>());
      expect(
        (outputArtwork as ModeItemIcon).showFrame,
        isFalse,
        reason:
            'Map artwork must keep the item image own border without adding '
            'a second theme frame.',
      );
      expect(
        outputArtwork.fallbackIcon,
        Icons.image_not_supported_outlined,
        reason:
            'Worker output artwork must never fall back to a leaf, tree, paw, '
            'or other resource-category symbol.',
      );
      expect(resourceMap.vendorPortraitBuilder, isNotNull);
      final siemo = resourceMap.dataset.vendorNpcs.firstWhere(
        (vendor) => vendor.sourceVendorId == 'npc:46022:1',
      );
      final siemoPortrait = resourceMap.vendorPortraitBuilder!(
        tester.element(find.byType(BdoResourceMap)),
        siemo,
        80,
      );
      expect(siemoPortrait, isA<Image>());
      final siemoImage = siemoPortrait as Image;
      expect(
        (siemoImage.image as AssetImage).assetName,
        bdoBundledVendorPortraitAsset(siemo.sourceVendorId),
      );
      expect(siemoImage.width, 80);
      expect(siemoImage.height, 80);
      expect(siemoImage.fit, BoxFit.contain);
      expect(siemoImage.alignment, Alignment.bottomCenter);
      expect(siemoImage.filterQuality, FilterQuality.high);
      expect(
        find.widgetWithText(TextField, 'Find an item, source, node or town'),
        findsOneWidget,
      );
      expect(find.byType(PlannerView), findsNothing);
      expect(
        tester.element(find.byType(PlannerView, skipOffstage: false)),
        same(plannerElement),
      );

      await tester.enterText(find.byType(TextField), 'snake meat');
      await tester.pump();
      expect(find.text('Snake Meat'), findsWidgets);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Resource-map search',
      );
      expect(tester.takeException(), isNull);

      await tester.tap(plannerTab);
      await tester.pump(const Duration(milliseconds: 160));

      expect(_isSelected(tester, plannerTab), isTrue);
      expect(_isSelected(tester, mapTab), isFalse);
      expect(find.byType(PlannerView), findsOneWidget);
      expect(tester.element(find.byType(PlannerView)), same(plannerElement));
      expect(
        tester.widget<PlannerView>(find.byType(PlannerView)),
        same(plannerWidget),
      );
      expect(
        harness.bundle.controller.active.state.value.target,
        plannerTarget,
      );
      expect(find.byType(ResourceMapWorkspace), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('Resource-map search'),
        reason: 'the hidden map must not retain keyboard focus',
      );
      expect(
        find.byType(ResourceMapWorkspace, skipOffstage: false),
        findsOneWidget,
        reason: 'the initialized map remains mounted behind the Planner tab',
      );
      expect(tester.takeException(), isNull);

      final mapInkWell = tester.widget<InkWell>(
        _workspaceTabInkWell('Resource Map'),
      );
      mapInkWell.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 160));
      expect(_isSelected(tester, mapTab), isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'snake meat',
        reason: 'the lazily-created map workspace is retained too',
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'Planner theme changes automatically pair the retained Resource Map skin',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      harness.bundle.controller.updateDocument(
        (document) => AppearanceActions.selectSharedBackground(
          document,
          'sakura-night-garden',
        ),
        immediate: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);

      final mapFinder = find.byType(BdoResourceMap);
      final retainedMapState = tester.state(mapFinder);
      expect(
        ResourceMapChromeTheme.of(tester.element(mapFinder)).variant,
        ResourceMapChromeThemeVariant.sakuraCartographer,
      );

      await tester.enterText(find.byType(TextField), 'snake meat');
      harness.bundle.controller.updateDocument(
        (document) => AppearanceActions.selectSharedBackground(
          document,
          'illuminated-ledger',
        ),
        immediate: true,
      );
      await tester.pump();

      expect(tester.state(mapFinder), same(retainedMapState));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'snake meat',
        reason: 'theme pairing must not recreate the retained map workspace',
      );
      expect(
        ResourceMapChromeTheme.of(tester.element(mapFinder)).variant,
        ResourceMapChromeThemeVariant.illuminatedAtlas,
      );

      harness.bundle.controller.updateDocument(
        (document) => AppearanceActions.selectSharedBackground(
          document,
          'sakura-night-garden',
        ),
        immediate: true,
      );
      await tester.pump();

      expect(tester.state(mapFinder), same(retainedMapState));
      expect(
        ResourceMapChromeTheme.of(tester.element(mapFinder)).variant,
        ResourceMapChromeThemeVariant.sakuraCartographer,
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'map projects active-plan shortages, stock, and catalog artwork',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final controller = harness.bundle.controller.active;
      expect(controller.selectTarget('Perfume of Tenacity'), isTrue);
      expect(controller.commitAmount('1'), isTrue);
      final stock = <String, double>{
        for (final material in controller.plan.value.missing)
          material.name: material.name == "Rusalka's Coral" ? 0 : 999999,
      };
      controller.replaceMarketValues(
        prices: <String, double>{
          for (final material in controller.plan.value.missing)
            material.name: 1,
        },
        stock: stock,
        unlistedItemNames: const <String>[],
        fetchedAt: DateTime.utc(2026, 7, 28, 12).millisecondsSinceEpoch,
        region: 'eu',
      );

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-command-gather')),
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-gather-plan-shortlist'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 260));

      final rusalkaRow = find.byKey(
        const ValueKey<String>('resource-map-plan-need-item:821255'),
      );
      final homeScrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-gather-hub')),
        matching: find.byType(Scrollable),
      );
      final neededHeading = find.text('NEEDED FOR YOUR PLAN');
      if (neededHeading.evaluate().isEmpty &&
          homeScrollable.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          neededHeading,
          180,
          scrollable: homeScrollable.first,
        );
      }
      await tester.pump();
      expect(neededHeading, findsOneWidget);
      expect(find.text('Alchemy · Perfume of Tenacity'), findsOneWidget);
      if (rusalkaRow.evaluate().isEmpty &&
          homeScrollable.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          rusalkaRow,
          120,
          scrollable: homeScrollable.first,
        );
      }
      await tester.pump();
      expect(rusalkaRow, findsOneWidget);
      expect(
        find.descendant(of: rusalkaRow, matching: find.text("Rusalka's Coral")),
        findsOneWidget,
      );
      final stockTooltip = tester.widget<Tooltip>(
        find.descendant(of: rusalkaRow, matching: find.byType(Tooltip)),
      );
      expect(stockTooltip.message, '0 stock at last EU check · 2026-07-28');
      expect(
        find.descendant(
          of: rusalkaRow,
          matching: find.byKey(ModeItemIconKeys.image("Rusalka's Coral")),
        ),
        findsOneWidget,
      );

      final mapElement = tester.element(find.byType(BdoResourceMap));
      await tester.enterText(find.byType(TextField), "Rusalka's Coral");
      controller.replaceMarketValues(
        prices: <String, double>{
          for (final material in controller.plan.value.missing)
            material.name: 1,
        },
        stock: <String, double>{...stock, "Rusalka's Coral": 99},
        unlistedItemNames: const <String>[],
        fetchedAt: DateTime.utc(2026, 7, 28, 13).millisecondsSinceEpoch,
        region: 'eu',
      );
      await tester.pump();

      expect(tester.element(find.byType(BdoResourceMap)), same(mapElement));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        "Rusalka's Coral",
        reason: 'market updates must not reset the retained map workspace',
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'worker-node market bridge projects cached evidence, tax, region, and timestamp',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final checkedAt = DateTime.utc(2026, 7, 29, 8, 45);
      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(marketTax: MarketTax(valuePack: true)),
        immediate: true,
      );
      harness.bundle.controller.active.replaceMarketValues(
        prices: const <String, double>{'Silver Azalea': 4321},
        stock: const <String, double>{'Silver Azalea': 76543},
        observedDailyTrades: const <String, double>{'Silver Azalea': 99},
        unlistedItemNames: const <String>[],
        fetchedAt: checkedAt.millisecondsSinceEpoch,
        region: 'na',
      );
      harness.bundle.controller.modes[CraftMode.cooking]!.replaceMarketValues(
        prices: const <String, double>{},
        stock: const <String, double>{},
        tradeObservationHours: const <String, double>{'Silver Azalea': 24},
        unlistedItemNames: const <String>[],
        fetchedAt: checkedAt
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
        region: 'na',
      );
      harness.bundle.controller.modes[CraftMode.processing]!
          .replaceMarketValues(
            prices: const <String, double>{},
            stock: const <String, double>{},
            observedDailyTrades: const <String, double>{'Silver Azalea': 12},
            tradeObservationHours: const <String, double>{'Silver Azalea': 6},
            unlistedItemNames: const <String>['Silver Azalea'],
            fetchedAt: checkedAt
                .subtract(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
            region: 'na',
          );

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump();

      final map = tester.widget<BdoResourceMap>(find.byType(BdoResourceMap));
      final evidence = map.marketOutputEvidenceByResourceId['item:5402'];
      expect(evidence, isNotNull);
      expect(evidence!.outputName, 'Silver Azalea');
      expect(evidence.currentUnitPrice, 4321);
      expect(evidence.listedStock, 76543);
      expect(evidence.observedDailyTradeVolume, 12);
      expect(evidence.tradeObservationHours, 6);
      expect(evidence.isMarketable, isTrue);
      expect(map.marketNetRate, closeTo(.845, 1e-12));
      expect(map.marketRegion, 'na');
      expect(map.marketFetchedAt, checkedAt);
      expect(map.onRefreshMarketEvidence, isNotNull);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'worker-node market refresh persists values without replacing the map workspace',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final refreshedAt = DateTime.utc(2026, 7, 29, 9, 30);
      final gateway = _RecordingMarketGateway(
        region: 'na',
        fetchedAt: refreshedAt,
        price: 24680,
        stock: 135,
      );
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: gateway,
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump();

      final mapFinder = find.byType(BdoResourceMap);
      final mapElement = tester.element(mapFinder);
      await tester.enterText(find.byType(TextField), 'Silver Azalea');
      await tester.pump();
      final refresh = tester
          .widget<BdoResourceMap>(mapFinder)
          .onRefreshMarketEvidence;
      expect(refresh, isNotNull);

      late String summary;
      await tester.runAsync(() async {
        summary = await refresh!(const <String>{'Silver Azalea'});
      });
      await tester.pump();

      expect(summary, 'Market updated for 1 material(s).');
      expect(gateway.requests, hasLength(1));
      expect(gateway.requests.single.name, 'Silver Azalea');
      expect(gateway.requests.single.id, '5402');
      final market = harness.bundle.controller.active.state.value.market;
      expect(market.prices['Silver Azalea'], 24680);
      expect(market.stock['Silver Azalea'], 135);
      expect(market.region, 'na');
      expect(market.fetchedAt, refreshedAt.millisecondsSinceEpoch);
      final persistedMarket =
          harness.bundle.controller.documentSnapshot.alchemy.market;
      expect(persistedMarket.prices['Silver Azalea'], 24680);
      expect(persistedMarket.stock['Silver Azalea'], 135);
      expect(persistedMarket.region, 'na');
      expect(persistedMarket.fetchedAt, refreshedAt.millisecondsSinceEpoch);

      expect(tester.element(mapFinder), same(mapElement));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Silver Azalea',
      );
      final updatedMap = tester.widget<BdoResourceMap>(mapFinder);
      final evidence = updatedMap.marketOutputEvidenceByResourceId['item:5402'];
      expect(evidence, isNotNull);
      expect(evidence!.currentUnitPrice, 24680);
      expect(evidence.listedStock, 135);
      expect(updatedMap.marketRegion, 'na');
      expect(updatedMap.marketFetchedAt, refreshedAt);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'resource favorites survive workspace tabs and craft-mode changes',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);

      final mapFinder = find.byType(BdoResourceMap);
      final mapElement = tester.element(mapFinder);
      final map = tester.widget<BdoResourceMap>(mapFinder);
      final snakeMeat = map.dataset.resources.singleWhere(
        (resource) => resource.name == 'Snake Meat',
      );
      expect(harness.bundle.controller.resourceMapFavoriteIds.value, isEmpty);

      await tester.enterText(find.byType(TextField), 'Snake Meat');
      await tester.pump();
      final addFavorite = find.byTooltip('Add Snake Meat to favorites');
      expect(addFavorite, findsOneWidget);
      await tester.tap(addFavorite);
      await tester.pump();

      expect(
        harness.bundle.controller.resourceMapFavoriteIds.value,
        contains(snakeMeat.id),
      );
      final resourceMapExtension =
          harness.bundle.controller.documentSnapshot.extensions['resourceMap']
              as Map;
      expect(
        resourceMapExtension['favoriteResourceIds'],
        contains(snakeMeat.id),
      );
      expect(
        tester.widget<BdoResourceMap>(mapFinder).favoriteResourceIds,
        contains(snakeMeat.id),
      );
      expect(
        find.byTooltip('Remove Snake Meat from favorites'),
        findsOneWidget,
      );

      await tester.tap(_workspaceTab('Craft Planner'));
      await tester.pump(const Duration(milliseconds: 160));
      final cookingMode = find.bySemanticsLabel('Switch to Cooking');
      expect(cookingMode, findsOneWidget);
      await tester.tap(cookingMode);
      await tester.pump(const Duration(milliseconds: 160));
      expect(harness.bundle.controller.activeMode.value, CraftMode.cooking);

      await tester.tap(_workspaceTab('Resource Map'));
      await tester.pump(const Duration(milliseconds: 160));

      expect(tester.element(mapFinder), same(mapElement));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Snake Meat',
      );
      expect(
        tester.widget<BdoResourceMap>(mapFinder).favoriteResourceIds,
        contains(snakeMeat.id),
      );
      expect(
        harness.bundle.controller.resourceMapFavoriteIds.value,
        contains(snakeMeat.id),
      );
      expect(
        find.byTooltip('Remove Snake Meat from favorites'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'map receives stable Cooking and Alchemy shortage groups with shared rows',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final alchemy = harness.bundle.controller.modes[CraftMode.alchemy]!;
      final cooking = harness.bundle.controller.modes[CraftMode.cooking]!;
      expect(alchemy.selectTarget('Pure Powder Reagent'), isTrue);
      expect(alchemy.commitAmount('2'), isTrue);
      expect(cooking.selectTarget('Beer'), isTrue);
      expect(cooking.commitAmount('2'), isTrue);

      final alchemyCheckedAt = DateTime.utc(2026, 7, 29, 10, 15);
      final cookingCheckedAt = DateTime.utc(2026, 7, 29, 11, 45);
      alchemy.replaceMarketValues(
        prices: const <String, double>{'Sugar': 111},
        stock: const <String, double>{'Sugar': 11},
        unlistedItemNames: const <String>[],
        fetchedAt: alchemyCheckedAt.millisecondsSinceEpoch,
        region: 'eu',
      );
      cooking.replaceMarketValues(
        prices: const <String, double>{'Sugar': 222},
        stock: const <String, double>{'Sugar': 22},
        unlistedItemNames: const <String>[],
        fetchedAt: cookingCheckedAt.millisecondsSinceEpoch,
        region: 'na',
      );
      expect(
        alchemy.plan.value.missing.any((material) => material.name == 'Sugar'),
        isTrue,
      );
      expect(
        cooking.plan.value.missing.any((material) => material.name == 'Sugar'),
        isTrue,
      );

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump();

      var map = tester.widget<BdoResourceMap>(find.byType(BdoResourceMap));
      expect(
        map.plannerNeedGroups.map((group) => group.id).toList(),
        const <String>['cooking', 'alchemy'],
      );
      expect(
        map.plannerNeedGroups.map((group) => group.label).toList(),
        const <String>['Cooking', 'Alchemy'],
      );
      final cookingGroup = map.plannerNeedGroups[0];
      final alchemyGroup = map.plannerNeedGroups[1];
      final cookingSugar = cookingGroup.materials.singleWhere(
        (material) => material.need.name == 'Sugar',
      );
      final alchemySugar = alchemyGroup.materials.singleWhere(
        (material) => material.need.name == 'Sugar',
      );

      expect(cookingSugar.id, alchemySugar.id);
      expect(cookingSugar.id, 'item:${cookingSugar.need.gameItemId}');
      expect(cookingSugar.need.gameItemId, isNotNull);
      expect(cookingSugar.need.gameItemId, alchemySugar.need.gameItemId);
      expect(cookingSugar.need.marketRegion, 'na');
      expect(cookingSugar.need.marketFetchedAt, cookingCheckedAt);
      final cookingPlanSugar = cooking.plan.value.missing.singleWhere(
        (material) => material.name == 'Sugar',
      );
      expect(cookingSugar.need.marketable, cookingPlanSugar.market.marketable);
      expect(cookingSugar.need.stockKnown, cookingPlanSugar.market.stockKnown);
      expect(cookingSugar.need.stock, cookingPlanSugar.market.stock);
      expect(cookingSugar.need.vendorPurchaseAvailable, isTrue);
      expect(alchemySugar.need.marketRegion, 'eu');
      expect(alchemySugar.need.marketFetchedAt, alchemyCheckedAt);
      final alchemyPlanSugar = alchemy.plan.value.missing.singleWhere(
        (material) => material.name == 'Sugar',
      );
      expect(alchemySugar.need.marketable, alchemyPlanSugar.market.marketable);
      expect(alchemySugar.need.stockKnown, alchemyPlanSugar.market.stockKnown);
      expect(alchemySugar.need.stock, alchemyPlanSugar.market.stock);
      expect(alchemySugar.need.vendorPurchaseAvailable, isTrue);

      final selectedSharedRows = BdoPlannerNeedSelection(
        groups: map.plannerNeedGroups,
      ).selectedPositivePlannerNeeds.where((need) => need.name == 'Sugar');
      expect(
        selectedSharedRows,
        isEmpty,
        reason:
            'direct vendor items remain visible but do not enter a worker '
            'network by default',
      );

      final legacyAlchemySugar = map.plannerNeeds.singleWhere(
        (need) => need.name == 'Sugar',
      );
      expect(legacyAlchemySugar.gameItemId, alchemySugar.need.gameItemId);
      expect(
        legacyAlchemySugar.missingQuantity,
        alchemySugar.need.missingQuantity,
      );
      expect(legacyAlchemySugar.marketRegion, alchemySugar.need.marketRegion);
      expect(legacyAlchemySugar.stock, alchemySugar.need.stock);
      expect(
        legacyAlchemySugar.vendorPurchaseAvailable,
        alchemySugar.need.vendorPurchaseAvailable,
      );
      expect(
        legacyAlchemySugar.reviewedWorkerRoute,
        alchemySugar.need.reviewedWorkerRoute,
      );

      final stableCookingSugarId = cookingSugar.id;
      expect(cooking.commitAmount('20'), isTrue);
      await tester.pump();
      map = tester.widget<BdoResourceMap>(find.byType(BdoResourceMap));
      final updatedCookingSugar = map.plannerNeedGroups
          .singleWhere((group) => group.id == 'cooking')
          .materials
          .singleWhere((material) => material.need.name == 'Sugar');
      expect(updatedCookingSugar.id, stableCookingSugarId);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'vendor-direct plan materials stay searchable without entering the shortlist',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final controller = harness.bundle.controller.active;
      expect(controller.selectTarget('Pure Powder Reagent'), isTrue);
      expect(controller.commitAmount('1'), isTrue);

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump();

      final map = tester.widget<BdoResourceMap>(find.byType(BdoResourceMap));
      final silverAzalea = map.plannerNeeds.singleWhere(
        (need) => need.name == 'Silver Azalea',
      );
      expect(
        silverAzalea.vendorPurchaseAvailable,
        isTrue,
        reason: 'the planner resolves Nieves as a direct NPC source',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-plan-need-item:5402')),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField), 'Silver Azalea');
      await tester.pump();
      expect(find.text('Silver Azalea'), findsWidgets);
      expect(
        find.textContaining('2 worker nodes'),
        findsWidgets,
        reason: 'shortlist filtering must not remove normal material search',
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'loaded map paint stays below the title strip at maximized width',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1920, 1080));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump(const Duration(milliseconds: 240));

      final titleBar = find.byType(AppTitleBar);
      final contentClip = find.byKey(ApplicationWorkspace.contentClipKey);
      final titleRect = tester.getRect(titleBar);
      final contentRect = tester.getRect(contentClip);

      expect(find.byType(BdoResourceMap), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(BdoResourceMap), matching: contentClip),
        findsOneWidget,
      );
      expect(tester.widget<ClipRect>(contentClip).clipBehavior, Clip.hardEdge);
      expect(titleRect, const Rect.fromLTWH(0, 0, 1920, 40));
      expect(contentRect.top, titleRect.bottom);
      expect(contentRect, const Rect.fromLTWH(0, 40, 1920, 1040));
      expect(
        _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
        findsNothing,
      );
      expect(
        _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets('top tabs and map remain render-safe at 200% text scale', (
    tester,
  ) async {
    configureApplicationTestSurface(
      tester,
      const Size(1200, 752),
      textScaleFactor: 2,
    );
    final harness = await _createHarness(tester);
    final tileClient = _localFailureTileClient();
    addTearDown(tileClient.close);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
      ),
    );
    await _pumpWorkspace(tester);

    expect(_isSelected(tester, _workspaceTab('Craft Planner')), isTrue);
    expect(
      _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
      findsOneWidget,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(_workspaceTab('Resource Map'));
    await tester.pump();
    expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
    expect(
      _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
      findsNothing,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
      findsOneWidget,
    );
    await _pumpUntilMapIsReady(tester);

    expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
    expect(find.byType(BdoResourceMap), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Find an item, source, node or town'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(_workspaceTab('Craft Planner'));
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byType(PlannerView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _disposeWidgetHarness(tester, harness);
  });

  testWidgets(
    'planner right-click persists the exact mapped item in the gather checklist',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final modeController = harness.bundle.controller.active;
      expect(modeController.selectTarget('Pure Powder Reagent'), isTrue);
      expect(modeController.commitAmount('1'), isTrue);
      expect(
        modeController.plan.value.missing.any(
          (material) => material.name == 'Silver Azalea',
        ),
        isTrue,
      );

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);

      final row = find.byKey(
        PlannerActionKeys.mapLookupRegion('need:Silver Azalea'),
      );
      await tester.scrollUntilVisible(
        row,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('planner-need-first'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(row, findsOneWidget);

      await tester.tap(
        row,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.text('Show gathering locations'), findsNothing);
      expect(find.text('Add to planned network'), findsOneWidget);
      expect(find.text('Add to checklist'), findsOneWidget);

      await tester.tap(
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'need:Silver Azalea',
            'addToGatherChecklist',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 180));

      final checklist =
          harness.bundle.controller.resourceMapGatherChecklist.value;
      expect(checklist.entries, hasLength(1));
      expect(
        checklist.entries.single,
        isA<BdoGatherChecklistEntry>()
            .having((entry) => entry.resourceId, 'resourceId', 'item:5402')
            .having(
              (entry) => entry.displayName,
              'displayName',
              'Silver Azalea',
            )
            .having(
              (entry) => entry.sourceKind,
              'sourceKind',
              BdoGatherChecklistSourceKind.workerNode,
            ),
      );
      final resourceMap =
          harness.bundle.controller.documentSnapshot.extensions['resourceMap']
              as Map;
      expect(resourceMap['gatherChecklist'], <String, Object?>{
        'schemaVersion': 1,
        'entries': <Object?>[
          <String, Object?>{
            'resourceId': 'item:5402',
            'displayName': 'Silver Azalea',
            'sourceKind': 'workerNode',
          },
        ],
      });
      expect(_isSelected(tester, _workspaceTab('Craft Planner')), isTrue);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'planner right-click opens the planned network with its worker target',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final controller = harness.bundle.controller.active;
      expect(controller.selectTarget('Pure Powder Reagent'), isTrue);
      expect(controller.commitAmount('1'), isTrue);
      expect(
        controller.plan.value.missing.any(
          (material) => material.name == 'Silver Azalea',
        ),
        isTrue,
      );

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);

      final row = find.byKey(
        PlannerActionKeys.mapLookupRegion('need:Silver Azalea'),
      );
      await tester.scrollUntilVisible(
        row,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('planner-need-first'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(row, findsOneWidget);

      await tester.tap(
        row,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Show gathering locations'), findsNothing);
      expect(find.text('Add to planned network'), findsOneWidget);

      await tester.tap(
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'need:Silver Azalea',
            'addToPlannedNetwork',
          ),
        ),
      );
      await tester.pump();
      await _pumpUntilMapIsReady(tester);
      await tester.pump(const Duration(milliseconds: 220));

      expect(_isSelected(tester, _workspaceTab('Craft Planner')), isFalse);
      expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
      expect(find.byType(BdoResourceMap), findsOneWidget);
      expect(find.text('Planned network'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-node-target-item:5402'),
        ),
        findsOneWidget,
      );
      expect(
        harness
            .bundle
            .controller
            .resourceMapNodeNetworkPreferences
            .value
            .desiredResourceNodeCounts,
        <String, int>{'item:5402': 1},
      );
      expect(
        find.text('Silver Azalea added to your planned network (1 node).'),
        findsOneWidget,
      );
      final resourceMap =
          harness.bundle.controller.documentSnapshot.extensions['resourceMap']
              as Map;
      final nodeNetwork = resourceMap['nodeNetwork'] as Map;
      expect(nodeNetwork['desiredResourceNodeCounts'], <String, Object?>{
        'item:5402': 1,
      });

      final current =
          harness.bundle.controller.resourceMapNodeNetworkPreferences.value;
      harness.bundle.controller.setResourceMapNodeNetworkPreferences(
        current.copyWith(
          desiredResourceNodeCounts: <String, int>{
            ...current.desiredResourceNodeCounts,
            'item:5402': 2,
          },
        ),
      );
      await tester.pump();
      await tester.tap(_workspaceTab('Craft Planner'));
      await tester.pump(const Duration(milliseconds: 180));
      await tester.tap(
        row,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'need:Silver Azalea',
            'addToPlannedNetwork',
          ),
        ),
      );
      await tester.pump();
      await _pumpUntilMapIsReady(tester);
      // A repeated action first dismisses the existing SnackBar (250 ms),
      // then presents the replacement message with its own entrance motion.
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 320));

      expect(
        harness
            .bundle
            .controller
            .resourceMapNodeNetworkPreferences
            .value
            .desiredResourceNodeCounts['item:5402'],
        2,
      );
      expect(
        find.text('Silver Azalea is already planned for 2 nodes.'),
        findsOneWidget,
      );
      expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
      expect(find.text('Planned network'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'title tabs survive map panels, transient UI, and repeated switching',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);

      void expectPersistentTabs({required bool mapSelected}) {
        final titleBar = find.byType(AppTitleBar);
        expect(titleBar, findsOneWidget);
        expect(
          find.byKey(AppTitleBar.workspaceNavigationHostKey),
          findsOneWidget,
        );
        expect(tester.getRect(titleBar), const Rect.fromLTWH(0, 0, 1500, 40));
        expect(_workspaceTab('Craft Planner'), findsOneWidget);
        expect(_workspaceTab('Resource Map'), findsOneWidget);
        expect(
          _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
          mapSelected ? findsNothing : findsOneWidget,
        );
        expect(
          _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
          mapSelected ? findsOneWidget : findsNothing,
        );
        expect(
          _isSelected(tester, _workspaceTab('Craft Planner')),
          !mapSelected,
        );
        expect(_isSelected(tester, _workspaceTab('Resource Map')), mapSelected);
      }

      expectPersistentTabs(mapSelected: false);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      expectPersistentTabs(mapSelected: true);

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Snake Meat');
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-search')),
        findsNothing,
      );
      expectPersistentTabs(mapSelected: true);

      await tester.tap(searchField);
      await tester.pump();
      final snakeResult = find
          .descendant(
            of: find.byType(ListTile),
            matching: find.text('Snake Meat'),
          )
          .first;
      expect(snakeResult, findsOneWidget);
      await tester.tap(snakeResult);
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);

      final detailSize = find.byKey(
        const ValueKey<String>('resource-map-sidebar-detail-size'),
      );
      expect(detailSize, findsOneWidget);
      await tester.tap(detailSize);
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.byTooltip('Use compact details'), findsOneWidget);
      expectPersistentTabs(mapSelected: true);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-layer-menu-toggle')),
      );
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        find.byKey(const ValueKey<String>('resource-map-layer-menu')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        find.byKey(const ValueKey<String>('resource-map-layer-menu')),
        findsNothing,
      );
      expectPersistentTabs(mapSelected: true);

      final gatherCommand = find.byKey(
        const ValueKey<String>('resource-map-command-gather'),
      );
      await tester.tap(gatherCommand);
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-hub')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);
      await tester.tap(gatherCommand);
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-hub')),
        findsNothing,
      );
      expectPersistentTabs(mapSelected: true);

      for (var iteration = 0; iteration < 3; iteration++) {
        await tester.tap(_workspaceTab('Craft Planner'));
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.byType(PlannerView), findsOneWidget);
        expectPersistentTabs(mapSelected: false);

        await tester.tap(_workspaceTab('Resource Map'));
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.byType(BdoResourceMap), findsOneWidget);
        expectPersistentTabs(mapSelected: true);
      }
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-hub')),
        findsNothing,
        reason: 'The retained map session should stay on its clean map home.',
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );
}

Finder _workspaceTab(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == label,
  description: '$label top-level workspace tab',
);

Finder _workspaceTabInkWell(String label) =>
    find.descendant(of: _workspaceTab(label), matching: find.byType(InkWell));

Finder _visibleTabLabel(Finder tab, String label) =>
    find.descendant(of: tab, matching: find.text(label));

bool? _isSelected(WidgetTester tester, Finder tab) =>
    tester.widget<Semantics>(tab).properties.selected;

final class _RecordingMarketGateway implements MarketPriceGateway {
  _RecordingMarketGateway({
    required this.region,
    required this.fetchedAt,
    required this.price,
    required this.stock,
  });

  final String region;
  final DateTime fetchedAt;
  final int price;
  final int stock;
  final List<MarketPriceRequest> requests = <MarketPriceRequest>[];

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requested, {
    MarketCancellationToken? cancellationToken,
  }) async {
    requests
      ..clear()
      ..addAll(requested);
    return MarketPriceFetchResult(
      region: region,
      language: 'en-US',
      fetchedAt: fetchedAt,
      attemptedSources: const <MarketPriceSource>[
        MarketPriceSource.pearlAbyssCentralMarket,
      ],
      items: <MarketPriceRow>[
        for (final request in requests)
          MarketPriceRow(
            name: request.name,
            id: request.id,
            ok: true,
            price: price,
            stock: stock,
            source: MarketPriceSource.pearlAbyssCentralMarket,
            fetchedAt: fetchedAt,
            diagnosticCode: MarketDiagnosticCode.none,
          ),
      ],
    );
  }
}

MockClient _localFailureTileClient() {
  return MockClient(
    (request) async => http.Response(
      'Tile networking is disabled by the integration-test fixture.',
      HttpStatus.serviceUnavailable,
    ),
  );
}

ResourceMapWorkspaceConfiguration _testMapConfiguration(
  ApplicationTestHarness harness,
  http.Client tileClient,
) {
  return ResourceMapWorkspaceConfiguration(
    cacheDirectory: Directory(
      '${harness.temporaryDirectory.path}${Platform.pathSeparator}map-cache',
    ),
    tileHttpClient: tileClient,
    showSourceNotice: false,
  );
}

Future<ApplicationTestHarness> _createHarness(WidgetTester tester) async {
  var harness = (await tester.runAsync(() => ApplicationTestHarness.create()))!;
  await tester.runAsync(harness.disposeControllerOnly);
  await tester.runAsync(BdoResourceMapLoader.loadBundled);
  await tester.runAsync(BdoWorkerEconomicsLoader.loadBundled);
  await tester.runAsync(LodgingDataLoader.loadBundled);
  harness = harness.rebindControllerInCurrentZone();
  return harness;
}

Future<void> _pumpWorkspace(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pumpUntilMapIsReady(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(BdoResourceMap).evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    find.byType(BdoResourceMap),
    findsOneWidget,
    reason:
        'the bundled resource-map dataset should load without the network; '
        'visible text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().join(' | ')}',
  );
}

Future<void> _disposeWidgetHarness(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var disposed = false;
  final disposeFuture = harness.bundle.controller.dispose().whenComplete(
    () => disposed = true,
  );
  for (var attempt = 0; attempt < 20 && !disposed; attempt++) {
    await tester.pump();
  }
  expect(disposed, isTrue, reason: 'controller disposal must drain in-zone');
  await disposeFuture;
  await tester.runAsync(() async {
    if (await harness.temporaryDirectory.exists()) {
      await harness.temporaryDirectory.delete(recursive: true);
    }
  });
}
