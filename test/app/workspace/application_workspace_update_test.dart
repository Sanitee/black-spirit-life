import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/data/data.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets('production null-service path makes no updater channel calls', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    const channel = MethodChannel('com.blackspiritlife/updates');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return const <String, Object?>{'status': 'upToDate'};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: false,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(PlannerView), findsOneWidget);
    expect(calls, isEmpty);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('explicit Beta update opt-out never invokes updater operations', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final service = _DeferredUpdateService();

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: false,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(AppIdentity.inProcessBetaUpdatesEnabled, isFalse);
    expect(find.byType(PlannerView), findsOneWidget);
    expect(service.currentStatusCalls, 0);
    expect(service.checkCalls, 0);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets('each application start checks after a usable workspace frame', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final firstHarness = (await tester.runAsync(
      ApplicationTestHarness.create,
    ))!;
    final service = _DeferredUpdateService();

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(firstHarness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(PlannerView), findsOneWidget);
    expect(service.currentStatusCalls, 1);
    expect(service.currentStatusCompleted, isFalse);
    expect(service.checkCalls, 0);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);

    service.completeCurrentStatus();
    await tester.pump();
    await tester.pump();
    expect(service.checkCalls, 1);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(firstHarness.dispose);

    final secondHarness = (await tester.runAsync(
      ApplicationTestHarness.create,
    ))!;
    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(secondHarness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(PlannerView), findsOneWidget);
    expect(service.currentStatusCalls, 2);
    expect(service.checkCalls, 2);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(secondHarness.dispose);
    await service.dispose();
  });

  testWidgets('a visible toast clears a newly surfaced update notice', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(
        startupNotices: const <String>['Startup notice remains visible.'],
      ),
    ))!;
    final service = _DeferredUpdateService();
    final windowHost = _RecordingWindowHost(<String>[]);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.text('Startup notice remains visible.'), findsOneWidget);
    final beforeUpdate = tester.widget<SnackBar>(find.byType(SnackBar));
    expect((beforeUpdate.margin! as EdgeInsets).bottom, 20);

    service.emit(_AvailableUpdateService.available);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsOneWidget);
    expect(find.text('Startup notice remains visible.'), findsOneWidget);
    final afterUpdate = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(
      (afterUpdate.margin! as EdgeInsets).bottom,
      20 + BetaUpdateIndicator.height,
    );
    expect(windowHost.bottomInsets, <double>[BetaUpdateIndicator.height]);

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pump();
    await tester.pump();

    expect(
      tester.getSize(find.byKey(BetaUpdateIndicator.buttonKey)).height,
      64,
    );
    expect(windowHost.bottomInsets, <double>[BetaUpdateIndicator.height, 64]);
    final afterTextScaleChange = tester.widget<SnackBar>(find.byType(SnackBar));
    expect((afterTextScaleChange.margin! as EdgeInsets).bottom, 84);

    service.completeCurrentStatus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets('an unavailable update source stays silent at startup', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final service = _OfflineUpdateService();
    final windowHost = _RecordingWindowHost(<String>[]);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: 'https://updates.invalid/stable',
        enableBetaUpdates: true,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(PlannerView), findsOneWidget);
    expect(service.currentStatusCalls, 1);
    expect(service.checkCalls, 1);
    expect(find.text('Update could not be checked'), findsNothing);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);
    expect(windowHost.bottomInsets, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets('public build never exposes the developer update control', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final service = _DeferredUpdateService();
    final windowHost = _RecordingWindowHost(<String>[]);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: false,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    harness.bundle.controller.active.navigate('data');
    await tester.pumpAndSettle();
    final build = find.byKey(
      const ValueKey<String>('data-editor-unlock-build'),
    );
    await tester.ensureVisible(build);
    for (var tap = 0; tap < DataSessionController.editorUnlockTapCount; tap++) {
      await tester.tap(build);
    }
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('data-test-update')),
      findsNothing,
    );
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);
    expect(windowHost.bottomInsets, isEmpty);
    expect(windowHost.closeCalls, 0);
    expect(service.downloadCalls, 0);
    expect(service.applyCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets(
    'one click downloads, prepares, and closes for an available patch',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1575, 987));
      final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
      final service = _AvailableUpdateService();
      final windowHost = _RecordingWindowHost(<String>[]);
      final fishRuntimeHost = _RecordingFishRuntimeHost(
        failApplicationExit: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          updateService: service,
          updateSource: r'C:\private-beta-feed',
          enableBetaUpdates: true,
          windowHost: windowHost,
          fishCompanionRuntimeHost: fishRuntimeHost,
        ),
      );
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(find.textContaining('2.5 MB patch'), findsOneWidget);
      expect(windowHost.bottomInsets, <double>[BetaUpdateIndicator.height]);

      await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(service.downloadCalls, 1);
      expect(service.applyCalls, 1);
      expect(windowHost.closeCalls, 1);
      expect(fishRuntimeHost.strictFreezeCalls, 1);
      expect(fishRuntimeHost.applicationExitFreezeCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(windowHost.bottomInsets.last, 0);
      await tester.runAsync(harness.dispose);
      await service.dispose();
    },
  );

  testWidgets('ordinary close uses only the application-exit Fish barrier', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final windowHost = _RecordingWindowHost(<String>[]);
    final fishRuntimeHost = _RecordingFishRuntimeHost(failStrict: true);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        enableBetaUpdates: false,
        windowHost: windowHost,
        fishCompanionRuntimeHost: fishRuntimeHost,
      ),
    );
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final closePreparation = windowHost.prepareOrdinaryClose();
    await tester.pump();
    await closePreparation;

    expect(fishRuntimeHost.applicationExitFreezeCalls, 1);
    expect(fishRuntimeHost.strictFreezeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets(
    'ordinary close recovery stays single-flight until delayed Fish resume completes',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1575, 987));
      final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
      final windowHost = _RecordingWindowHost(
        <String>[],
        closeFlushTimeout: const Duration(milliseconds: 120),
      );
      final fishRuntimeHost = _DelayedCloseRecoveryFishRuntimeHost();

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          enableBetaUpdates: false,
          windowHost: windowHost,
          fishCompanionRuntimeHost: fishRuntimeHost,
        ),
      );
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      await tester.tap(find.byKey(AppTitleBar.captionGlyphKey('close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fishRuntimeHost.applicationExitFreezeCalls, 1);
      expect(fishRuntimeHost.resumeCalls, 1);
      expect(harness.bundle.controller.mutationsFrozen, isTrue);

      await tester.pump(const Duration(milliseconds: 30));
      expect(fishRuntimeHost.resumeCalls, 1);
      expect(
        tester
            .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
            .any((widget) => widget.absorbing),
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 130));
      expect(fishRuntimeHost.applicationExitFreezeCalls, 1);
      expect(fishRuntimeHost.resumeCalls, 1);
      expect(harness.bundle.controller.mutationsFrozen, isTrue);

      fishRuntimeHost.completeResume();
      await tester.pump();
      await tester.pump();
      expect(harness.bundle.controller.mutationsFrozen, isFalse);
      expect(
        tester
            .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
            .any((widget) => widget.absorbing),
        isFalse,
      );

      final retry = windowHost.prepareOrdinaryClose();
      await tester.pump();
      await retry;
      expect(fishRuntimeHost.applicationExitFreezeCalls, 2);
      expect(fishRuntimeHost.resumeCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(harness.dispose);
    },
  );

  testWidgets('a failed update download leaves no strip and reports a toast', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final service = _DownloadFailureUpdateService();
    final windowHost = _RecordingWindowHost(<String>[]);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsOneWidget);
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(service.downloadCalls, 1);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);
    expect(find.text('The update download failed.'), findsOneWidget);
    expect(windowHost.bottomInsets, <double>[BetaUpdateIndicator.height, 0]);
    expect(windowHost.closeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets(
    'restart is canceled before native apply when state cannot save',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1575, 987));
      var saveAttempts = 0;
      var harness = (await tester.runAsync(ApplicationTestHarness.create))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone(
        saveStateFactory: (_) => (state) async {
          saveAttempts += 1;
          throw StateError('injected update restart save failure');
        },
      );
      final service = _ReadyUpdateService();

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          updateService: service,
          updateSource: r'C:\private-beta-feed',
          enableBetaUpdates: true,
        ),
      );
      for (var index = 0; index < 4; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byKey(BetaUpdateIndicator.buttonKey), findsOneWidget);

      harness.bundle.controller.switchMode(CraftMode.processing);
      for (var index = 0; index < 4; index++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(harness.bundle.controller.saveError.value, isNotNull);

      await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(saveAttempts, greaterThanOrEqualTo(2));
      expect(service.applyCalls, 0);
      expect(
        find.textContaining(
          'Restart canceled because the latest planner state',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(harness.dispose);
      await service.dispose();
    },
  );

  testWidgets('restart saves once before one native apply and close', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final events = <String>[];
    final saveCompleter = Completer<PlannerState>();
    PlannerState? stateToSave;
    var harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone(
      saveStateFactory: (_) => (state) async {
        events.add('save-start');
        stateToSave = state;
        final saved = await saveCompleter.future;
        events.add('save-complete');
        return saved;
      },
    );
    final service = _ReadyUpdateService(events: events);
    final windowHost = _RecordingWindowHost(events);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    harness.bundle.controller.switchMode(CraftMode.processing);
    await tester.pump();
    expect(events, <String>['save-start']);

    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();

    expect(service.applyCalls, 0);
    expect(windowHost.closeCalls, 0);
    expect(events, <String>['save-start']);

    saveCompleter.complete(stateToSave!);
    for (var index = 0; index < 6; index++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(service.applyCalls, 1);
    expect(windowHost.closeCalls, 1);
    expect(events, <String>['save-start', 'save-complete', 'apply', 'close']);
    expect(harness.bundle.controller.mutationsFrozen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets('planner edits stay frozen while native prepare is pending', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    PlannerState? lastSaved;
    var harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone(
      saveStateFactory: (_) => (state) async {
        lastSaved = state;
        return state;
      },
    );
    final service = _GatedApplyUpdateService();
    final windowHost = _RecordingWindowHost(<String>[]);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(harness.bundle.controller.activeMode.value, CraftMode.alchemy);
    await tester.enterText(
      find.descendant(
        of: find.byKey(PlannerActionKeys.p02),
        matching: find.byType(EditableText),
      ),
      '37',
    );
    expect(harness.bundle.controller.active.state.value.want, isNot(37));
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();
    await tester.pump();

    expect(service.applyCalls, 1);
    expect(harness.bundle.controller.mutationsFrozen, isTrue);
    expect(harness.bundle.controller.active.state.value.want, 37);
    expect(lastSaved?.alchemy.want, 37);
    expect(
      tester
          .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
          .any((widget) => widget.absorbing),
      isTrue,
    );
    harness.bundle.controller.switchMode(CraftMode.processing);
    expect(harness.bundle.controller.activeMode.value, CraftMode.alchemy);
    expect(windowHost.closeCalls, 0);

    service.completePrepare();
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(windowHost.closeCalls, 1);
    expect(harness.bundle.controller.mutationsFrozen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });

  testWidgets('a rejected native prepare leaves the Beta open', (tester) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final service = _RejectedApplyUpdateService();
    final windowHost = _RecordingWindowHost(<String>[]);

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        updateService: service,
        updateSource: r'C:\private-beta-feed',
        enableBetaUpdates: true,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(service.applyCalls, 1);
    expect(windowHost.closeCalls, 0);
    expect(
      find.textContaining('Native update preparation was rejected'),
      findsWidgets,
    );
    expect(harness.bundle.controller.mutationsFrozen, isFalse);
    harness.bundle.controller.switchMode(CraftMode.processing);
    expect(harness.bundle.controller.activeMode.value, CraftMode.processing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
    await service.dispose();
  });
}

class _DeferredUpdateService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _events =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  final Completer<BetaUpdateSnapshot> _current =
      Completer<BetaUpdateSnapshot>();
  int currentStatusCalls = 0;
  int checkCalls = 0;
  int downloadCalls = 0;
  int applyCalls = 0;

  bool get currentStatusCompleted => _current.isCompleted;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _events.stream;

  void completeCurrentStatus() => _current.complete(const BetaUpdateSnapshot());

  void emit(BetaUpdateSnapshot snapshot) => _events.add(snapshot);

  @override
  Future<BetaUpdateSnapshot> currentStatus() {
    currentStatusCalls += 1;
    return _current.future;
  }

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async {
    checkCalls += 1;
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.upToDate);
  }

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async {
    downloadCalls += 1;
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.downloading);
  }

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async {
    applyCalls += 1;
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying);
  }

  @override
  Future<void> dispose() => _events.close();
}

class _OfflineUpdateService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _events =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  int currentStatusCalls = 0;
  int checkCalls = 0;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _events.stream;

  @override
  Future<BetaUpdateSnapshot> currentStatus() async {
    currentStatusCalls += 1;
    return const BetaUpdateSnapshot();
  }

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async {
    checkCalls += 1;
    return const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.offline,
      message: 'The update source is unavailable.',
    );
  }

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.offline);

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.error);

  @override
  Future<void> dispose() => _events.close();
}

class _ReadyUpdateService implements BetaUpdateService {
  _ReadyUpdateService({this.events});

  final StreamController<BetaUpdateSnapshot> _events =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  final List<String>? events;
  int applyCalls = 0;

  static const ready = BetaUpdateSnapshot(
    phase: BetaUpdatePhase.ready,
    currentVersion: '0.1.0-beta.1',
    targetVersion: '0.1.0-beta.2',
    progress: 1,
    message: 'The update is ready to install.',
  );

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _events.stream;

  @override
  Future<BetaUpdateSnapshot> currentStatus() async => ready;

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async => ready;

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async => ready;

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async {
    applyCalls += 1;
    events?.add('apply');
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying);
  }

  @override
  Future<void> dispose() => _events.close();
}

class _AvailableUpdateService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _events =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  int downloadCalls = 0;
  int applyCalls = 0;

  static const available = BetaUpdateSnapshot(
    phase: BetaUpdatePhase.available,
    currentVersion: '0.1.0-beta.5',
    targetVersion: '0.1.0-beta.6',
    sizeBytes: 2610822,
    fullSizeBytes: 66854193,
    deltaCount: 1,
  );

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _events.stream;

  @override
  Future<BetaUpdateSnapshot> currentStatus() async => available;

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async => available;

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async {
    downloadCalls += 1;
    return const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.ready,
      currentVersion: '0.1.0-beta.5',
      targetVersion: '0.1.0-beta.6',
      progress: 1,
    );
  }

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async {
    applyCalls += 1;
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying);
  }

  @override
  Future<void> dispose() => _events.close();
}

class _DownloadFailureUpdateService extends _AvailableUpdateService {
  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async {
    downloadCalls += 1;
    return const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.error,
      targetVersion: '0.1.0-beta.6',
      message: 'The update download failed.',
    );
  }
}

class _RecordingWindowHost extends WindowHostService {
  _RecordingWindowHost(
    this.events, {
    super.closeFlushTimeout,
  });

  final List<String> events;
  int closeCalls = 0;
  final List<double> bottomInsets = <double>[];
  Future<void> Function()? _beforeClose;

  @override
  void installCloseRequestHandler(Future<void> Function()? handler) {
    _beforeClose = handler;
  }

  @override
  void removeCloseRequestHandler() {
    _beforeClose = null;
  }

  Future<void> prepareOrdinaryClose() {
    final beforeClose = _beforeClose;
    if (beforeClose == null) {
      throw StateError('The workspace close handler is not installed.');
    }
    return beforeClose();
  }

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> setBottomInset(double logicalPixels) async {
    bottomInsets.add(logicalPixels);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    events.add('close');
  }
}

final class _RecordingFishRuntimeHost extends FishCompanionRuntimeHost {
  _RecordingFishRuntimeHost({
    this.failStrict = false,
    this.failApplicationExit = false,
  }) : super.withStarter((_) async => _NoopFishCompanionServiceHandle());

  final bool failStrict;
  final bool failApplicationExit;
  final FishCompanionServiceHandle _handle = _NoopFishCompanionServiceHandle();
  int strictFreezeCalls = 0;
  int applicationExitFreezeCalls = 0;

  @override
  Future<FishCompanionServiceHandle> ready() async => _handle;

  @override
  Future<void> prewarm() async {}

  @override
  Future<void> flushForLifecycle() async {}

  @override
  Future<void> freezeAndFlush() async {
    strictFreezeCalls += 1;
    if (failStrict) throw StateError('strict Fish freeze must not be used');
  }

  @override
  Future<void> freezeAndFlushForApplicationExit() async {
    applicationExitFreezeCalls += 1;
    if (failApplicationExit) {
      throw StateError('application-exit Fish freeze must not be used');
    }
  }

  @override
  Future<void> resumeAfterFailure() async {}

  @override
  void dispose() {}
}

final class _DelayedCloseRecoveryFishRuntimeHost
    extends FishCompanionRuntimeHost {
  _DelayedCloseRecoveryFishRuntimeHost()
    : super.withStarter((_) async => _NoopFishCompanionServiceHandle());

  final Completer<void> _resume = Completer<void>();
  final Completer<void> _firstApplicationExitFreeze = Completer<void>();
  int applicationExitFreezeCalls = 0;
  int resumeCalls = 0;

  @override
  Future<void> freezeAndFlushForApplicationExit() {
    applicationExitFreezeCalls += 1;
    if (applicationExitFreezeCalls == 1) {
      return _firstApplicationExitFreeze.future;
    }
    return Future<void>.value();
  }

  @override
  Future<void> resumeAfterFailure() async {
    resumeCalls += 1;
    await _resume.future;
  }

  void completeResume() => _resume.complete();

  @override
  void dispose() {}
}

final class _NoopFishCompanionServiceHandle
    implements FishCompanionServiceHandle {
  @override
  final Directory root = Directory('unused-fish-service-fixture');

  @override
  final Directory personalDataRoot = Directory('unused-fish-personal-fixture');

  @override
  final Directory webViewDataRoot = Directory('unused-fish-webview-fixture');

  @override
  final Uri uri = Uri.parse('http://127.0.0.1:18765/');

  @override
  Future<void> checkpoint() async {}

  @override
  Future<void> shutdown() async {}

  @override
  void dispose() {}
}

class _RejectedApplyUpdateService extends _ReadyUpdateService {
  @override
  Future<BetaUpdateSnapshot> restartAndApply() async {
    applyCalls += 1;
    return const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.error,
      message: 'Native update preparation was rejected.',
    );
  }
}

class _GatedApplyUpdateService extends _ReadyUpdateService {
  final Completer<BetaUpdateSnapshot> _prepare =
      Completer<BetaUpdateSnapshot>();

  @override
  Future<BetaUpdateSnapshot> restartAndApply() {
    applyCalls += 1;
    return _prepare.future;
  }

  void completePrepare() {
    _prepare.complete(
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying),
    );
  }
}
