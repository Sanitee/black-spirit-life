import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/first_run_setup_view.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar_visual.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/fishing/fish_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/diagnostics/resource_map_frame_capture.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/diagnostics/resource_map_redraw_diagnostic.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../packages/bdo_map_core/test/support/map_menu_capture.dart';
import '../../support/application_test_harness.dart';

void main() {
  test(
    'public identity uses the Stable state target',
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
    'deferred Fish diagnostic mounts no page during loading or startup failure',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final pendingApplication = Completer<ApplicationBundle>();
      final fishService = _FakeFishCompanionServiceHandle();
      var serviceStarts = 0;
      var readinessChecks = 0;
      final runtimeHost = FishCompanionRuntimeHost.withStarter((_) async {
        serviceStarts += 1;
        return fishService;
      });

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          diagnosticDeferFishPrewarm: true,
          enableOpportunityAutoCheck: false,
          applicationFuture: pendingApplication.future,
          marketGateway: const EmptyMarketGateway(),
          fishCompanionRuntimeHost: runtimeHost,
          fishCompanionPageReadinessOverride: () async {
            readinessChecks += 1;
            await runtimeHost.ready();
            return FishCompanionPageStatus.ready;
          },
        ),
      );
      await _pumpWorkspace(tester);
      expect(find.text('Preparing your planner'), findsOneWidget);
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);

      pendingApplication.completeError(
        StateError('diagnostic fixture failure'),
      );
      await _pumpWorkspace(tester);
      expect(
        find.text('${AppIdentity.displayName} could not start.'),
        findsOneWidget,
      );
      expect(find.textContaining('diagnostic fixture failure'), findsOneWidget);
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await expectLater(runtimeHost.ready(), throwsStateError);
      expect(serviceStarts, 0);
      expect(fishService.disposeCount, 0);
    },
  );

  testWidgets(
    'deferred Fish diagnostic stays unmounted through first-run setup',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester, setupCompleted: false);
      final fishService = _FakeFishCompanionServiceHandle();
      var serviceStarts = 0;
      var readinessChecks = 0;

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          diagnosticDeferFishPrewarm: true,
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          fishCompanionRuntimeStarter: (_) async {
            serviceStarts += 1;
            return fishService;
          },
          fishCompanionPageReadinessOverride: () async {
            readinessChecks += 1;
            return FishCompanionPageStatus.ready;
          },
        ),
      );
      await _pumpWorkspace(tester);

      expect(find.byType(FirstRunSetupView), findsOneWidget);
      expect(
        find.byType(ApplicationWorkspace, skipOffstage: false),
        findsNothing,
      );
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);

      final skip = find.byKey(const ValueKey('first-run-setup-skip'));
      await tester.ensureVisible(skip);
      await tester.tap(skip);
      await _pumpWorkspace(tester);
      expect(find.byType(FirstRunSetupView), findsNothing);
      expect(find.byType(ApplicationWorkspace), findsOneWidget);
      expect(find.byType(PlannerView), findsOneWidget);
      expect(
        tester
            .widget<ApplicationWorkspace>(find.byType(ApplicationWorkspace))
            .diagnosticDeferFishPrewarm,
        isTrue,
      );
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
      expect(fishService.disposeCount, 0);
    },
  );

  testWidgets(
    'deferred Fish diagnostic stays unmounted for Resource first then retains Fish',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      final fishService = _FakeFishCompanionServiceHandle();
      final pageTerminal = Completer<FishCompanionPageStatus>();
      var serviceStarts = 0;
      var readinessChecks = 0;
      final runtimeHost = FishCompanionRuntimeHost.withStarter((_) async {
        serviceStarts += 1;
        return fishService;
      });

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          diagnosticDeferFishPrewarm: true,
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
          fishCompanionRuntimeHost: runtimeHost,
          fishCompanionPageReadinessOverride: () async {
            readinessChecks += 1;
            // FLUTTER_TEST skips native WebView/runtime initialization.
            // Exercise the real injected host from this readiness seam.
            await runtimeHost.ready();
            return pageTerminal.future;
          },
        ),
      );
      await _pumpWorkspace(tester);
      expect(find.byType(PlannerView), findsOneWidget);
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);
      final plannerElement = tester.element(find.byType(PlannerView));

      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);
      final mapElement = tester.element(find.byType(BdoResourceMap));
      final mapState = tester.state(find.byType(BdoResourceMap));

      await tester.tap(_workspaceTab('Craft Planner'));
      await _pumpWorkspace(tester);
      expect(tester.element(find.byType(PlannerView)), same(plannerElement));
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpWorkspace(tester);
      expect(tester.element(find.byType(BdoResourceMap)), same(mapElement));
      expect(tester.state(find.byType(BdoResourceMap)), same(mapState));
      _expectNoMountedFish();
      expect(serviceStarts, 0);
      expect(readinessChecks, 0);

      await tester.tap(_workspaceTab('Fish Map'));
      await _pumpWorkspace(tester);
      expect(_isSelected(tester, _workspaceTab('Fish Map')), isTrue);
      expect(find.byType(FishMapWorkspace), findsOneWidget);
      expect(find.byKey(const Key('fish-companion-starting')), findsOneWidget);
      expect(serviceStarts, 1);
      expect(readinessChecks, 1);
      final fishElement = tester.element(find.byType(FishMapWorkspace));
      final fishWidget = tester.widget<FishMapWorkspace>(
        find.byType(FishMapWorkspace),
      );
      final fishState = tester.state(find.byType(FishCompanionView));
      expect(_topWorkspaceTickerEnabled(tester, 'fishMap'), isTrue);

      // Leaving while initialization is pending must not cancel/recreate Fish.
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpWorkspace(tester);
      expect(find.byType(FishMapWorkspace), findsNothing);
      expect(
        tester.element(find.byType(FishMapWorkspace, skipOffstage: false)),
        same(fishElement),
      );
      expect(_topWorkspaceTickerEnabled(tester, 'fishMap'), isFalse);
      expect(
        tester
            .widget<ExcludeFocus>(
              find.byKey(
                ApplicationWorkspace.focusGateKey('fishMap'),
                skipOffstage: false,
              ),
            )
            .excluding,
        isTrue,
      );
      pageTerminal.complete(FishCompanionPageStatus.ready);
      await _pumpWorkspace(tester);

      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(_workspaceTab('Fish Map'));
        await _pumpWorkspace(tester);
        expect(
          tester.element(find.byType(FishMapWorkspace)),
          same(fishElement),
        );
        expect(
          tester.widget<FishMapWorkspace>(find.byType(FishMapWorkspace)),
          same(fishWidget),
        );
        expect(tester.state(find.byType(FishCompanionView)), same(fishState));
        // FLUTTER_TEST never creates the native controller, so its placeholder
        // remains even after readiness completes. Check lifecycle, not native UI.
        expect(_topWorkspaceTickerEnabled(tester, 'fishMap'), isTrue);
        expect(serviceStarts, 1);
        expect(readinessChecks, 1);
        expect(fishService.disposeCount, 0);
        await tester.tap(_workspaceTab('Resource Map'));
        await _pumpWorkspace(tester);
        expect(tester.element(find.byType(BdoResourceMap)), same(mapElement));
        expect(tester.state(find.byType(BdoResourceMap)), same(mapState));
      }
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
      expect(fishService.disposeCount, 1);
    },
  );

  testWidgets(
    'Fish page mounts before bootstrap resolves and survives its workspace handoff',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final pendingApplication = Completer<ApplicationBundle>();
      final pageTerminal = Completer<FishCompanionPageStatus>();
      final fishService = _FakeFishCompanionServiceHandle();
      var fishServiceStarts = 0;
      var pageReadinessChecks = 0;
      bool? workspaceWasMountedAtStart;

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: pendingApplication.future,
          marketGateway: const EmptyMarketGateway(),
          fishCompanionRuntimeStarter: (_) async {
            fishServiceStarts += 1;
            workspaceWasMountedAtStart = find
                .byType(ApplicationWorkspace, skipOffstage: false)
                .evaluate()
                .isNotEmpty;
            return fishService;
          },
          fishCompanionPageReadinessOverride: () {
            pageReadinessChecks += 1;
            return pageTerminal.future;
          },
        ),
      );

      expect(fishServiceStarts, 0);
      expect(find.text('Preparing your planner'), findsOneWidget);
      expect(
        find.byType(ApplicationWorkspace, skipOffstage: false),
        findsNothing,
      );
      final prewarmedFishMap = find.byType(
        FishMapWorkspace,
        skipOffstage: false,
      );
      final prewarmedFishView = find.byType(
        FishCompanionView,
        skipOffstage: false,
      );
      expect(prewarmedFishMap, findsOneWidget);
      expect(prewarmedFishView, findsOneWidget);
      expect(find.byType(FishMapWorkspace), findsNothing);
      expect(tester.getSize(prewarmedFishMap), const Size(1500, 940));
      final prewarmedFishMapElement = tester.element(prewarmedFishMap);
      final prewarmedFishMapWidget = tester.widget<FishMapWorkspace>(
        prewarmedFishMap,
      );
      final prewarmedFishViewState = tester.state(prewarmedFishView);

      pendingApplication.complete(harness.bundle);
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(fishServiceStarts, 1);
      expect(
        workspaceWasMountedAtStart,
        isFalse,
        reason:
            'the service should use the bundle handoff before the first interactive workspace frame',
      );

      await _pumpWorkspace(tester);
      expect(find.byType(ApplicationWorkspace), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ApplicationWorkspace),
          matching: find.byType(FishMapWorkspace, skipOffstage: false),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.byType(FishMapWorkspace), findsNothing);
      final retainedFishMap = find.byType(
        FishMapWorkspace,
        skipOffstage: false,
      );
      final retainedFishView = find.byType(
        FishCompanionView,
        skipOffstage: false,
      );
      expect(tester.element(retainedFishMap), same(prewarmedFishMapElement));
      expect(
        tester.widget<FishMapWorkspace>(retainedFishMap),
        same(prewarmedFishMapWidget),
      );
      expect(
        tester.state(retainedFishView),
        same(prewarmedFishViewState),
        reason:
            'the Fish view lifecycle must be reparented instead of disposed '
            'and initialized again after bootstrap',
      );

      await tester.tap(_workspaceTab('Fish Map'));
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(FishMapWorkspace), findsOneWidget);
      expect(
        tester.state(find.byType(FishCompanionView)),
        same(prewarmedFishViewState),
      );
      expect(
        pageReadinessChecks,
        1,
        reason: 'moving and revealing the page must not initialize it again',
      );

      pageTerminal.complete(FishCompanionPageStatus.ready);
      await tester.pump();

      await _disposeWidgetHarness(tester, harness);
      expect(fishService.disposeCount, 1);
    },
  );

  testWidgets('app future updates retain the externally prewarmed Fish host', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final harness = await _createHarness(tester);
    final fishService = _FakeFishCompanionServiceHandle();
    var fishServiceStarts = 0;
    final runtimeHost = FishCompanionRuntimeHost.withStarter((_) async {
      fishServiceStarts += 1;
      return fishService;
    });

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        fishCompanionRuntimeHost: runtimeHost,
      ),
    );
    await _pumpWorkspace(tester);
    expect(fishServiceStarts, 1);
    expect(fishService.disposeCount, 0);
    final retainedFishElement = tester.element(
      find.byType(FishMapWorkspace, skipOffstage: false),
    );
    final retainedFishViewState = tester.state(
      find.byType(FishCompanionView, skipOffstage: false),
    );

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        fishCompanionRuntimeHost: runtimeHost,
      ),
    );
    await _pumpWorkspace(tester);

    expect(fishServiceStarts, 1);
    expect(
      fishService.disposeCount,
      0,
      reason: 'the same app-owned host must survive a bundle-future update',
    );
    expect(
      tester.state(find.byType(FishCompanionView, skipOffstage: false)),
      same(retainedFishViewState),
      reason: 'an unchanged external host must retain its initialized page',
    );
    expect(
      tester.element(find.byType(FishMapWorkspace, skipOffstage: false)),
      same(retainedFishElement),
    );

    await _disposeWidgetHarness(tester, harness);
    expect(fishService.disposeCount, 1);
  });

  testWidgets(
    'Fish readiness configuration replaces the page without restarting its host',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final fishService = _FakeFishCompanionServiceHandle();
      var fishServiceStarts = 0;
      final runtimeHost = FishCompanionRuntimeHost.withStarter((_) async {
        fishServiceStarts += 1;
        return fishService;
      });
      Future<FishCompanionPageStatus> firstReadiness() async =>
          FishCompanionPageStatus.ready;
      Future<FishCompanionPageStatus> replacementReadiness() async =>
          FishCompanionPageStatus.ready;

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          fishCompanionRuntimeHost: runtimeHost,
          fishCompanionPageReadinessOverride: firstReadiness,
        ),
      );
      await _pumpWorkspace(tester);
      final originalFishViewState = tester.state(
        find.byType(FishCompanionView, skipOffstage: false),
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          fishCompanionRuntimeHost: runtimeHost,
          fishCompanionPageReadinessOverride: replacementReadiness,
        ),
      );
      await _pumpWorkspace(tester);

      expect(fishServiceStarts, 1);
      expect(fishService.disposeCount, 0);
      expect(
        tester.state(find.byType(FishCompanionView, skipOffstage: false)),
        isNot(same(originalFishViewState)),
        reason:
            'FishCompanionView reads readiness only in initState, so changing '
            'that seam must replace the page and its GlobalKey',
      );

      await _disposeWidgetHarness(tester, harness);
      expect(fishService.disposeCount, 1);
    },
  );

  testWidgets(
    'an early Fish click opens immediately while the standalone page loads',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final fishService = _FakeFishCompanionServiceHandle();
      final pageTerminal = Completer<FishCompanionPageStatus>();

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          fishCompanionRuntimeStarter: (_) async => fishService,
          fishCompanionPageReadinessOverride: () => pageTerminal.future,
        ),
      );
      await _pumpWorkspace(tester);

      final plannerTab = _workspaceTab('Craft Planner');
      final fishMapTab = _workspaceTab('Fish Map');
      final eagerFishMap = find.byType(FishMapWorkspace, skipOffstage: false);
      final eagerElement = tester.element(eagerFishMap);
      final eagerWidget = tester.widget<FishMapWorkspace>(eagerFishMap);

      await tester.tap(fishMapTab);
      await tester.pump(const Duration(milliseconds: 160));

      expect(_isSelected(tester, plannerTab), isFalse);
      expect(_isSelected(tester, fishMapTab), isTrue);
      expect(find.byType(FishMapWorkspace), findsOneWidget);
      expect(tester.element(find.byType(FishMapWorkspace)), same(eagerElement));
      expect(
        find.byKey(const Key('fish-companion-starting')),
        findsOneWidget,
        reason:
            'the selected Fish tab owns its loading state instead of blocking '
            'the tab action',
      );

      pageTerminal.complete(FishCompanionPageStatus.ready);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      expect(_isSelected(tester, plannerTab), isFalse);
      expect(_isSelected(tester, fishMapTab), isTrue);
      expect(find.byType(FishMapWorkspace), findsOneWidget);
      expect(tester.element(find.byType(FishMapWorkspace)), same(eagerElement));
      expect(
        tester.widget<FishMapWorkspace>(find.byType(FishMapWorkspace)),
        same(eagerWidget),
        reason: 'readiness must not rebuild the already-selected Fish page',
      );

      await _disposeWidgetHarness(tester, harness);
      expect(fishService.disposeCount, 1);
    },
  );

  testWidgets('Fish page eagerly mounts offstage while peer workspaces remain lazy', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final harness = await _createHarness(tester);
    final tileClient = _localFailureTileClient();
    final fishService = _FakeFishCompanionServiceHandle();
    var fishServiceStarts = 0;
    addTearDown(tileClient.close);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        fishCompanionRuntimeStarter: (_) async {
          fishServiceStarts += 1;
          return fishService;
        },
      ),
    );
    await _pumpWorkspace(tester);
    expect(
      fishServiceStarts,
      1,
      reason:
          'the localhost service should already be warming during app bootstrap',
    );

    final plannerTab = _workspaceTab('Craft Planner');
    final mapTab = _workspaceTab('Resource Map');
    final gatheringTab = _workspaceTab('Gathering');
    final fishMapTab = _workspaceTab('Fish Map');
    expect(plannerTab, findsOneWidget);
    expect(mapTab, findsOneWidget);
    expect(gatheringTab, findsOneWidget);
    expect(fishMapTab, findsOneWidget);
    expect(_isSelected(tester, plannerTab), isTrue);
    expect(_isSelected(tester, mapTab), isFalse);
    expect(_isSelected(tester, gatheringTab), isFalse);
    expect(_isSelected(tester, fishMapTab), isFalse);
    expect(_visibleTabLabel(plannerTab, 'Craft Planner'), findsOneWidget);
    expect(_visibleTabLabel(mapTab, 'Resource Map'), findsNothing);
    expect(_visibleTabLabel(gatheringTab, 'Gathering'), findsNothing);
    expect(_visibleTabLabel(fishMapTab, 'Fish Map'), findsNothing);
    expect(tester.getSize(plannerTab).width, greaterThan(100));
    expect(tester.getSize(mapTab).width, 52);
    expect(tester.getSize(gatheringTab).width, 52);
    expect(tester.getSize(fishMapTab).width, 52);
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
      find.byKey(AppTitleTabStrip.artworkKey('Gathering')),
      findsOneWidget,
    );
    expect(find.byKey(AppTitleTabStrip.artworkKey('Fish Map')), findsOneWidget);
    expect(
      <String, String>{
        'Craft Planner': _workspaceTabAsset(tester, plannerTab),
        'Resource Map': _workspaceTabAsset(tester, mapTab),
        'Gathering': _workspaceTabAsset(tester, gatheringTab),
        'Fish Map': _workspaceTabAsset(tester, fishMapTab),
      },
      <String, String>{
        'Craft Planner':
            'packages/bdo_map_core/assets/images/node_icons/14.png',
        'Resource Map':
            'packages/bdo_map_core/assets/images/node_icons/gray/0.png',
        'Gathering':
            'packages/bdo_map_core/assets/images/node_icons/gray/6.png',
        'Fish Map':
            'packages/bdo_fishing_core/assets/fish_companion/static/fishystuff.png',
      },
    );
    expect(find.byType(PlannerView), findsOneWidget);
    expect(
      find.byType(ResourceMapWorkspace, skipOffstage: false),
      findsNothing,
      reason: 'the heavier map workspace should be created on first use',
    );
    expect(
      find.byType(GatheringWorkspace, skipOffstage: false),
      findsNothing,
      reason: 'Gathering should be created only when its tab is first used',
    );
    expect(
      find.byType(FishMapWorkspace, skipOffstage: false),
      findsOneWidget,
      reason:
          'the exact Fish page must begin loading behind the initial Planner tab',
    );
    expect(find.byType(FishMapWorkspace), findsNothing);
    expect(
      find.byType(FishCompanionView, skipOffstage: false),
      findsOneWidget,
      reason: 'the offstage workspace must mount the real standalone Fish view',
    );
    expect(
      find.byKey(const Key('fish-companion-starting'), skipOffstage: false),
      findsOneWidget,
    );
    expect(_topWorkspaceTickerEnabled(tester, 'fishMap'), isFalse);
    expect(
      tester
          .widget<ExcludeFocus>(
            find.byKey(
              ApplicationWorkspace.focusGateKey('fishMap'),
              skipOffstage: false,
            ),
          )
          .excluding,
      isTrue,
    );
    final eagerFishMapElement = tester.element(
      find.byType(FishMapWorkspace, skipOffstage: false),
    );
    final eagerFishMapWidget = tester.widget<FishMapWorkspace>(
      find.byType(FishMapWorkspace, skipOffstage: false),
    );

    final plannerElement = tester.element(find.byType(PlannerView));
    final plannerWidget = tester.widget<PlannerView>(find.byType(PlannerView));
    final plannerTarget = harness.bundle.controller.active.state.value.target;
    expect(
      find.byType(ResourceMapFrameCapture, skipOffstage: false),
      findsNothing,
      reason: 'No diagnostic mounts or captures before Resource is visited.',
    );
    expect(
      find.byType(ResourceMapRedrawDiagnostic, skipOffstage: false),
      findsNothing,
    );

    await tester.tap(mapTab);
    await _pumpUntilMapIsReady(tester);

    final frameCapture = find.byType(ResourceMapFrameCapture);
    final redrawDiagnostic = find.byType(ResourceMapRedrawDiagnostic);
    expect(
      redrawDiagnostic,
      resourceRedrawDiagnosticEnabled ? findsOneWidget : findsNothing,
    );
    if (resourceRedrawDiagnosticEnabled) {
      expect(
        tester.widget<ResourceMapRedrawDiagnostic>(redrawDiagnostic).active,
        isTrue,
      );
      expect(
        find.descendant(
          of: redrawDiagnostic,
          matching: find.byType(BdoResourceMap),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: redrawDiagnostic,
          matching: find.byType(AppTitleBar),
        ),
        findsNothing,
      );
    }
    expect(
      frameCapture,
      resourceFrameCaptureEnabled ? findsOneWidget : findsNothing,
      reason: 'Ordinary builds must retain the exact unwrapped Resource tree.',
    );
    if (resourceFrameCaptureEnabled) {
      expect(
        tester.widget<ResourceMapFrameCapture>(frameCapture).active,
        isTrue,
      );
      expect(
        find.descendant(
          of: frameCapture,
          matching: find.byType(BdoResourceMap),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: frameCapture, matching: find.byType(AppTitleBar)),
        findsNothing,
        reason: 'The title and other tabs are outside the capture boundary.',
      );
    }

    expect(_isSelected(tester, plannerTab), isFalse);
    expect(_isSelected(tester, mapTab), isTrue);
    expect(_isSelected(tester, gatheringTab), isFalse);
    expect(_isSelected(tester, fishMapTab), isFalse);
    expect(_visibleTabLabel(plannerTab, 'Craft Planner'), findsNothing);
    expect(_visibleTabLabel(mapTab, 'Resource Map'), findsOneWidget);
    expect(_visibleTabLabel(gatheringTab, 'Gathering'), findsNothing);
    expect(_visibleTabLabel(fishMapTab, 'Fish Map'), findsNothing);
    expect(tester.getSize(plannerTab).width, 52);
    expect(tester.getSize(mapTab).width, greaterThan(100));
    expect(tester.getSize(gatheringTab).width, 52);
    expect(tester.getSize(fishMapTab).width, 52);
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
      isTrue,
      reason: 'Map artwork retains the current shared item-quality frame.',
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
      find.byKey(const ValueKey<String>('resource-map-atlas-search-field')),
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
    expect(harness.bundle.controller.active.state.value.target, plannerTarget);
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

    final retainedMapElement = tester.element(
      find.byType(ResourceMapWorkspace),
    );
    await tester.tap(gatheringTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(_isSelected(tester, gatheringTab), isTrue);
    expect(_isSelected(tester, fishMapTab), isFalse);
    expect(find.byType(GatheringWorkspace), findsOneWidget);
    expect(
      tester.element(find.byType(FishMapWorkspace, skipOffstage: false)),
      same(eagerFishMapElement),
    );
    final gatheringElement = tester.element(find.byType(GatheringWorkspace));
    expect(_topWorkspaceTickerEnabled(tester, 'gathering'), isTrue);
    expect(
      tester
          .widget<ExcludeFocus>(
            find.byKey(ApplicationWorkspace.focusGateKey('gathering')),
          )
          .excluding,
      isFalse,
    );
    expect(
      tester
          .widget<ExcludeFocus>(
            find.byKey(
              ApplicationWorkspace.focusGateKey('resourceMap'),
              skipOffstage: false,
            ),
          )
          .excluding,
      isTrue,
    );
    expect(
      find.byKey(ApplicationWorkspace.gatheringContentClipKey),
      findsOneWidget,
    );
    expect(
      tester.element(find.byType(ResourceMapWorkspace, skipOffstage: false)),
      same(retainedMapElement),
    );
    expect(_topWorkspaceTickerEnabled(tester, 'resourceMap'), isFalse);

    await tester.tap(fishMapTab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(_isSelected(tester, gatheringTab), isFalse);
    expect(_isSelected(tester, fishMapTab), isTrue);
    expect(find.byType(GatheringWorkspace), findsNothing);
    expect(find.byType(FishMapWorkspace), findsOneWidget);
    expect(
      fishServiceStarts,
      1,
      reason: 'opening Fish Map must reveal the already-prewarmed page',
    );
    final fishMapElement = tester.element(find.byType(FishMapWorkspace));
    expect(fishMapElement, same(eagerFishMapElement));
    expect(
      tester.widget<FishMapWorkspace>(find.byType(FishMapWorkspace)),
      same(eagerFishMapWidget),
      reason: 'tab selection must reveal, not replace, the exact Fish page',
    );
    expect(_topWorkspaceTickerEnabled(tester, 'fishMap'), isTrue);
    expect(_topWorkspaceTickerEnabled(tester, 'gathering'), isFalse);
    expect(
      tester
          .widget<ExcludeFocus>(
            find.byKey(
              ApplicationWorkspace.focusGateKey('gathering'),
              skipOffstage: false,
            ),
          )
          .excluding,
      isTrue,
    );
    expect(
      tester
          .widget<ExcludeFocus>(
            find.byKey(ApplicationWorkspace.focusGateKey('fishMap')),
          )
          .excluding,
      isFalse,
    );
    expect(
      find.byKey(ApplicationWorkspace.fishMapContentClipKey),
      findsOneWidget,
    );

    await tester.tap(gatheringTab);
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester.element(find.byType(GatheringWorkspace)),
      same(gatheringElement),
    );
    expect(
      tester.element(find.byType(FishMapWorkspace, skipOffstage: false)),
      same(fishMapElement),
    );
    expect(_topWorkspaceTickerEnabled(tester, 'gathering'), isTrue);
    expect(_topWorkspaceTickerEnabled(tester, 'fishMap'), isFalse);

    await tester.tap(mapTab);
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester.element(find.byType(ResourceMapWorkspace)),
      same(retainedMapElement),
    );
    expect(_topWorkspaceTickerEnabled(tester, 'resourceMap'), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'snake meat',
      reason: 'visiting both peer tools must not reset the Resource Map',
    );
    expect(tester.takeException(), isNull);

    await _disposeWidgetHarness(tester, harness);
    expect(
      fishService.disposeCount,
      1,
      reason: 'the app bootstrap gate owns the prewarmed service lifetime',
    );
  });

  testWidgets(
    'Appearance changes recolour the retained Resource Map without changing its structure',
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
          enableOpportunityAutoCheck: false,
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
        tester.element(mapFinder).mapChrome.primary,
        SakuraNightGardenSpec.theme.palette.primary,
      );
      expect(
        ResourceMapChromeTheme.of(tester.element(mapFinder)).variant,
        ResourceMapChromeThemeVariant.fieldAtlas,
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
        reason: 'planner appearance must not recreate the map workspace',
      );
      expect(
        tester.element(mapFinder).mapChrome.primary,
        IlluminatedLedgerSpec.theme.palette.primary,
      );
      expect(tester.element(mapFinder).mapChrome.brightness, Brightness.light);
      expect(
        ResourceMapChromeTheme.of(tester.element(mapFinder)).variant,
        ResourceMapChromeThemeVariant.fieldAtlas,
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
        tester.element(mapFinder).mapChrome.primary,
        SakuraNightGardenSpec.theme.palette.primary,
      );
      expect(
        ResourceMapChromeTheme.of(tester.element(mapFinder)).variant,
        ResourceMapChromeThemeVariant.fieldAtlas,
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets('all title strips follow Appearance except independent Fish', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final harness = await _createHarness(tester);
    final tileClient = _localFailureTileClient();
    final fishService = _FakeFishCompanionServiceHandle();
    addTearDown(tileClient.close);
    harness.bundle.controller.updateDocument(
      (document) => AppearanceActions.selectSharedBackground(
        document,
        'sakura-night-garden',
      ),
      immediate: true,
    );
    final plannerAppearance =
        harness.bundle.controller.documentSnapshot.alchemy.appearance;

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        fishCompanionRuntimeStarter: (_) async => fishService,
        fishCompanionPageReadinessOverride: () async =>
            FishCompanionPageStatus.ready,
      ),
    );
    await _pumpWorkspace(tester);

    BoxDecoration titleDecoration() =>
        tester
                .widget<DecoratedBox>(find.byKey(AppTitleBar.materialKey))
                .decoration
            as BoxDecoration;

    final plannerDecoration = titleDecoration();
    expect(find.byType(AppTitleBarVisualScope), findsNothing);
    expect(plannerDecoration.image, isNotNull);
    expect(
      (plannerDecoration.image!.image as AssetImage).assetName,
      'assets/sakura/materials/blackened-cedar.png',
    );

    Future<void> expectWorkspaceTitle(
      String label,
      AppTitleBarVisual? expected,
    ) async {
      await tester.tap(_workspaceTab(label));
      for (var attempt = 0; attempt < 6; attempt++) {
        await tester.pump(const Duration(milliseconds: 80));
        if (_isSelected(tester, _workspaceTab(label)) == true) break;
      }
      if (expected == null) {
        expect(find.byType(AppTitleBarVisualScope), findsNothing);
        expect(titleDecoration().gradient, plannerDecoration.gradient);
        expect(titleDecoration().image, plannerDecoration.image);
      } else {
        final scope = tester.widget<AppTitleBarVisualScope>(
          find.byType(AppTitleBarVisualScope),
        );
        expect(scope.visual, same(expected));
        expect(titleDecoration().gradient, expected.titleGradient);
        final selectedTabDecoration =
            tester
                    .widget<AnimatedContainer>(
                      find.byKey(AppTitleTabStrip.surfaceKey(label)),
                    )
                    .decoration
                as BoxDecoration;
        expect(selectedTabDecoration.color, expected.tabSelectedSurface);
      }
      expect(
        harness.bundle.controller.documentSnapshot.alchemy.appearance,
        same(plannerAppearance),
        reason: 'top-level navigation must not write Planner appearance',
      );
    }

    await expectWorkspaceTitle('Resource Map', null);
    await expectWorkspaceTitle('Gathering', null);
    await expectWorkspaceTitle('Fish Map', AppTitleBarVisual.fishMap);

    await tester.tap(_workspaceTab('Craft Planner'));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(AppTitleBarVisualScope), findsNothing);
    final restoredPlannerDecoration = titleDecoration();
    expect(restoredPlannerDecoration.gradient, plannerDecoration.gradient);
    expect(restoredPlannerDecoration.image, plannerDecoration.image);
    expect(
      harness.bundle.controller.documentSnapshot.alchemy.appearance,
      same(plannerAppearance),
    );
    expect(tester.takeException(), isNull);

    await _disposeWidgetHarness(tester, harness);
    expect(fishService.disposeCount, 1);
  });

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
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('resource-map-field-desk')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-home-find-material')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const ValueKey<String>('resource-map-gather-plan-shortlist'))
            .hitTestable(),
      );
      await tester.pumpAndSettle();

      final rusalkaRow = find.byKey(
        const ValueKey<String>('resource-map-plan-need-item:821255'),
      );
      final homeScrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-atlas-dock')),
        matching: find.byType(Scrollable),
      );
      final neededHeading = find.text('Needed for your plan');
      await tester.pump();
      expect(neededHeading, findsOneWidget);
      expect(find.text('Alchemy · Perfume of Tenacity'), findsNothing);
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
          enableOpportunityAutoCheck: false,
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
          enableOpportunityAutoCheck: false,
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
      // This fixture must reach the market gateway: Silver Azalea has a
      // bundled NPC price and is deliberately excluded from market refreshes.
      await tester.enterText(find.byType(TextField), 'Ash Sap');
      await tester.pump();
      final refresh = tester
          .widget<BdoResourceMap>(mapFinder)
          .onRefreshMarketEvidence;
      expect(refresh, isNotNull);

      late String summary;
      await tester.runAsync(() async {
        summary = await refresh!(const <String>{'Ash Sap'});
      });
      await tester.pump();

      expect(summary, 'Market updated for 1 material(s).');
      expect(gateway.requests, hasLength(1));
      expect(gateway.requests.single.name, 'Ash Sap');
      expect(gateway.requests.single.id, '5001');
      final market = harness.bundle.controller.active.state.value.market;
      expect(market.prices['Ash Sap'], 24680);
      expect(market.stock['Ash Sap'], 135);
      expect(market.region, 'na');
      expect(market.fetchedAt, refreshedAt.millisecondsSinceEpoch);
      final persistedMarket =
          harness.bundle.controller.documentSnapshot.alchemy.market;
      expect(persistedMarket.prices['Ash Sap'], 24680);
      expect(persistedMarket.stock['Ash Sap'], 135);
      expect(persistedMarket.region, 'na');
      expect(persistedMarket.fetchedAt, refreshedAt.millisecondsSinceEpoch);

      expect(tester.element(mapFinder), same(mapElement));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Ash Sap',
      );
      final updatedMap = tester.widget<BdoResourceMap>(mapFinder);
      final evidence = updatedMap.marketOutputEvidenceByResourceId['item:5001'];
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
          enableOpportunityAutoCheck: false,
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

      expect(
        find.byKey(const ValueKey('resource-map-field-desk')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-home-find-material')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Snake Meat');
      await tester.pumpAndSettle();
      final snakeResult = find.byKey(
        ValueKey<String>('resource-map-search-result-resource-${snakeMeat.id}'),
      );
      expect(
        snakeResult,
        findsOneWidget,
        reason:
            'Visible result keys: ${tester.widgetList<ListTile>(find.byType(ListTile)).map((tile) => tile.key).join(', ')}',
      );
      await tester.tap(snakeResult);
      await tester.pumpAndSettle();
      final addFavorite = find.byKey(
        ValueKey<String>('resource-map-detail-favorite-${snakeMeat.id}'),
      );
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
      expect(addFavorite, findsOneWidget);

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
      expect(addFavorite, findsOneWidget);
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
          enableOpportunityAutoCheck: false,
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
    'map receives the planner substitute family and effective member ratios',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final alchemy = harness.bundle.controller.modes[CraftMode.alchemy]!;
      expect(alchemy.selectTarget("Clown's Blood"), isTrue);
      expect(alchemy.commitAmount('2'), isTrue);

      final plannerMaterial = alchemy.plan.value.missing.singleWhere(
        (material) => material.choice?.substituteGroup == 'Blood Group 1',
      );
      final plannerChoice = plannerMaterial.choice!;

      final tileClient = _localFailureTileClient();
      addTearDown(tileClient.close);
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
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
      final projectedNeed = map.plannerNeeds.singleWhere(
        (need) => need.name == plannerMaterial.name,
      );
      final family = projectedNeed.substituteFamily!;

      expect(family.parentName, plannerChoice.parentName);
      expect(family.originalName, plannerChoice.original);
      expect(family.familyName, plannerChoice.substituteGroup);
      expect(family.selectedName, plannerChoice.baseName);
      expect(family.members, plannerChoice.options);
      expect(
        family.members,
        containsAll(<String>[
          'Wolf Blood',
          'Flamingo Blood',
          'Rhino Blood',
          'Cheetah Dragon Blood',
        ]),
      );
      expect(family.ratios, <String, double>{
        'Wolf Blood': 1,
        'Flamingo Blood': 0.5,
        'Rhino Blood': 1,
        'Cheetah Dragon Blood': 0.5,
      });

      final groupedNeed = map.plannerNeedGroups
          .singleWhere((group) => group.id == 'alchemy')
          .materials
          .singleWhere((material) => material.need.name == plannerMaterial.name)
          .need;
      expect(groupedNeed.substituteFamily, isNotNull);
      expect(groupedNeed.substituteFamily!.members, family.members);
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
          enableOpportunityAutoCheck: false,
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
        find.byKey(
          const ValueKey('resource-map-search-result-resource-item:5402'),
        ),
        findsOneWidget,
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
          enableOpportunityAutoCheck: false,
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
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        resourceMapConfiguration: _testMapConfiguration(harness, tileClient),
      ),
    );
    await _pumpWorkspace(tester);

    expect(_isSelected(tester, _workspaceTab('Craft Planner')), isTrue);
    expect(_workspaceTab('Gathering'), findsOneWidget);
    expect(_workspaceTab('Fish Map'), findsOneWidget);
    expect(
      _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
      findsOneWidget,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
      findsNothing,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Gathering'), 'Gathering'),
      findsNothing,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Fish Map'), 'Fish Map'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(_workspaceTab('Resource Map'));
    await tester.pump();
    expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
    expect(_isSelected(tester, _workspaceTab('Gathering')), isFalse);
    expect(_isSelected(tester, _workspaceTab('Fish Map')), isFalse);
    expect(
      _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
      findsNothing,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
      findsOneWidget,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Gathering'), 'Gathering'),
      findsNothing,
    );
    expect(
      _visibleTabLabel(_workspaceTab('Fish Map'), 'Fish Map'),
      findsNothing,
    );
    await _pumpUntilMapIsReady(tester);

    expect(_isSelected(tester, _workspaceTab('Resource Map')), isTrue);
    expect(find.byType(BdoResourceMap), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('resource-map-atlas-search-field')),
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
      await tester.runAsync(loadMapMenuCaptureFonts);
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
        RepaintBoundary(
          key: const ValueKey('gather-checklist-capture'),
          child: BdoCraftPlannerApp(
            enableOpportunityAutoCheck: false,
            applicationFuture: Future.value(harness.bundle),
            marketGateway: const EmptyMarketGateway(),
            resourceMapConfiguration: _testMapConfiguration(
              harness,
              tileClient,
            ),
          ),
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
      expect(find.text('Add to to-do list'), findsOneWidget);

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
      final savedChecklist = BdoGatherChecklist.fromJson(
        resourceMap['gatherChecklist'],
      );
      expect((resourceMap['gatherChecklist'] as Map)['schemaVersion'], 2);
      expect(savedChecklist.entries.single.resourceId, 'item:5402');
      expect(savedChecklist.entries.single.displayName, 'Silver Azalea');
      expect(
        savedChecklist.entries.single.sourceKind,
        BdoGatherChecklistSourceKind.workerNode,
      );
      final demand = savedChecklist.entries.single.demands.single;
      expect(demand.materialName, 'Silver Azalea');
      expect(demand.plannerTarget, 'Pure Powder Reagent');
      expect(demand.neededQuantity, greaterThan(0));
      expect(_isSelected(tester, _workspaceTab('Craft Planner')), isTrue);
      expect(tester.takeException(), isNull);

      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      expect(
        find.byKey(const ValueKey('resource-map-field-desk')),
        findsOneWidget,
      );
      await tester.tap(find.text('To-do list'));
      await tester.pumpAndSettle();
      expect(find.text('Needed'), findsOneWidget);
      expect(find.text('Owned'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      final beforeOwned =
          modeController.state.value.inventory['Silver Azalea'] ?? 0;
      await tester.tap(
        find.byKey(
          const ValueKey('resource-map-gather-checklist-complete-item:5402'),
        ),
      );
      await tester.pump();
      expect(
        modeController.state.value.inventory['Silver Azalea'] ?? 0,
        beforeOwned,
      );
      await tester.tap(
        find.byKey(const ValueKey('gather-record-open:item:5402')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('gather-record-amount:item:5402')),
        '3',
      );
      await tester.tap(
        find.byKey(const ValueKey('gather-record-save:item:5402')),
      );
      await tester.pump();
      await tester.runAsync(harness.bundle.controller.flush);
      await tester.pumpAndSettle();
      for (final mode in harness.bundle.controller.modes.values) {
        expect(mode.state.value.inventory['Silver Azalea'], beforeOwned + 3);
      }
      expect(
        tester
            .widget<BdoResourceMap>(find.byType(BdoResourceMap))
            .gatherChecklistQuantities['item:5402']!
            .owned,
        beforeOwned + 3,
      );
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();
      await captureMapMenu(
        tester,
        boundary: find.byKey(const ValueKey('gather-checklist-capture')),
        name: 'gather-checklist-1200-normal',
      );
      await tester.tap(
        find.byKey(const ValueKey('gather-record-undo:item:5402')),
      );
      await tester.pump();
      await tester.runAsync(harness.bundle.controller.flush);
      await tester.pumpAndSettle();
      expect(
        modeController.state.value.inventory['Silver Azalea'] ?? 0,
        beforeOwned,
      );
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
          enableOpportunityAutoCheck: false,
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
      expect(
        find.byKey(const ValueKey<String>('resource-map-atlas-dock')),
        findsOneWidget,
      );
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
      expect(
        find.byKey(const ValueKey<String>('resource-map-atlas-dock')),
        findsOneWidget,
      );
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
          enableOpportunityAutoCheck: false,
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
        expect(_workspaceTab('Gathering'), findsOneWidget);
        expect(_workspaceTab('Fish Map'), findsOneWidget);
        expect(
          _visibleTabLabel(_workspaceTab('Craft Planner'), 'Craft Planner'),
          mapSelected ? findsNothing : findsOneWidget,
        );
        expect(
          _visibleTabLabel(_workspaceTab('Resource Map'), 'Resource Map'),
          mapSelected ? findsOneWidget : findsNothing,
        );
        expect(
          _visibleTabLabel(_workspaceTab('Gathering'), 'Gathering'),
          findsNothing,
        );
        expect(
          _visibleTabLabel(_workspaceTab('Fish Map'), 'Fish Map'),
          findsNothing,
        );
        expect(
          _isSelected(tester, _workspaceTab('Craft Planner')),
          !mapSelected,
        );
        expect(_isSelected(tester, _workspaceTab('Resource Map')), mapSelected);
        expect(_isSelected(tester, _workspaceTab('Gathering')), isFalse);
        expect(_isSelected(tester, _workspaceTab('Fish Map')), isFalse);
      }

      expectPersistentTabs(mapSelected: false);
      await tester.tap(_workspaceTab('Resource Map'));
      await _pumpUntilMapIsReady(tester);
      expectPersistentTabs(mapSelected: true);

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Snake Meat');
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('resource-map-atlas-search-field')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('search')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('resource-map-atlas-search-field')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);

      await tester.tap(searchField);
      await tester.pump();
      final snakeResult = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                ((widget.key! as ValueKey<String>).value).startsWith(
                  'resource-map-search-result-',
                ) &&
                find
                    .descendant(
                      of: find.byWidget(widget),
                      matching: find.text('Snake Meat'),
                    )
                    .evaluate()
                    .isNotEmpty,
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

      // Hosted task headers now have one back action; the user removed Home
      // and panel-minimize. Native window controls and standalone are unchanged.
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-atlas-workspace-minimize'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-home-button')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        findsNothing,
      );

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
        const ValueKey<String>('resource-map-home-find-material'),
      );
      expect(
        find.byKey(const ValueKey('resource-map-field-desk')),
        findsOneWidget,
      );
      await tester.tap(gatherCommand);
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        find.byKey(const ValueKey<String>('resource-map-material-categories')),
        findsOneWidget,
      );
      expectPersistentTabs(mapSelected: true);
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        find.byKey(const ValueKey<String>('resource-map-material-categories')),
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
        find.byKey(const ValueKey<String>('resource-map-atlas-dock')),
        findsNothing,
        reason: 'Home has no open workbench.',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-field-desk')),
        findsOneWidget,
        reason: 'The retained Codex Atlas rail remains available on home.',
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-sidebar-details')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-material-categories')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );
}

Finder _workspaceTab(String label) => find.descendant(
  of: find.byType(AppTitleTabStrip),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == label,
    description: '$label top-level workspace tab',
  ),
);

Finder _workspaceTabInkWell(String label) =>
    find.descendant(of: _workspaceTab(label), matching: find.byType(InkWell));

String _workspaceTabAsset(WidgetTester tester, Finder tab) {
  final image = tester.widget<Image>(
    find.descendant(of: tab, matching: find.byType(Image)),
  );
  final resized = image.image as ResizeImage;
  return (resized.imageProvider as AssetImage).assetName;
}

bool _topWorkspaceTickerEnabled(WidgetTester tester, String destination) =>
    tester
        .widget<TickerMode>(
          find.byKey(
            ApplicationWorkspace.tickerModeKey(destination),
            skipOffstage: false,
          ),
        )
        .enabled;

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

final class _FakeFishCompanionServiceHandle
    implements FishCompanionServiceHandle {
  @override
  final Directory root = Directory('unused-fish-service-fixture');

  @override
  final Directory personalDataRoot = Directory(
    'unused-fish-personal-data-fixture',
  );

  @override
  final Directory webViewDataRoot = Directory('unused-fish-webview-fixture');

  @override
  final Uri uri = Uri.parse('http://127.0.0.1:18765/');

  int disposeCount = 0;

  @override
  Future<void> checkpoint() async {}

  @override
  Future<void> shutdown() async {
    disposeCount += 1;
  }

  @override
  void dispose() {
    disposeCount += 1;
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

Future<ApplicationTestHarness> _createHarness(
  WidgetTester tester, {
  bool setupCompleted = true,
}) async {
  var harness = (await tester.runAsync(
    () => ApplicationTestHarness.create(setupCompleted: setupCompleted),
  ))!;
  await tester.runAsync(harness.disposeControllerOnly);
  await tester.runAsync(BdoResourceMapLoader.loadBundled);
  await tester.runAsync(BdoWorkerEconomicsLoader.loadBundled);
  await tester.runAsync(LodgingDataLoader.loadBundled);
  harness = harness.rebindControllerInCurrentZone();
  return harness;
}

void _expectNoMountedFish() {
  expect(find.byType(FishMapWorkspace, skipOffstage: false), findsNothing);
  expect(find.byType(FishCompanionView, skipOffstage: false), findsNothing);
  expect(
    find.byKey(ApplicationWorkspace.fishMapContentClipKey, skipOffstage: false),
    findsNothing,
  );
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
