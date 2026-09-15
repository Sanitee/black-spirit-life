import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/features/data/data.dart';
import 'package:bdo_craft_planner_flutter/features/fishing/fishing.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_personal_store.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets(
    'ordinary close freezes every personal-data writer and resumes after host failure',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1575, 987));
      final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
      final closeGate = Completer<void>();
      final windowHost = _RecordingWindowHost(
        failFirstClose: true,
        firstCloseGate: closeGate,
        plannerFrozen: () => harness.bundle.controller.mutationsFrozen,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future<ApplicationBundle>.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
          enableBetaUpdates: false,
          enableOpportunityAutoCheck: false,
          windowHost: windowHost,
        ),
      );
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      await tester.tap(
        find.byKey(const ValueKey<String>('top-workspace-tab-gathering')),
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(GatheringWorkspace.masteryFieldKey)
            .evaluate()
            .isNotEmpty,
      );
      await tester.enterText(
        find.byKey(GatheringWorkspace.masteryFieldKey),
        '1775',
      );
      await tester.enterText(
        find.byKey(GatheringWorkspace.loadoutFieldKey),
        'Local gathering setup',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('top-workspace-tab-fishing')),
      );
      await _pumpUntil(
        tester,
        () => find.byKey(FishingWorkspace.addLoadoutKey).evaluate().isNotEmpty,
      );

      await tester.tap(find.byTooltip('Close'));
      await _pumpUntil(tester, () => windowHost.closeCalls == 1);
      await tester.pump();
      expect(windowHost.closeCalls, 1);
      expect(windowHost.plannerFrozenOnClose, isTrue);
      expect(harness.bundle.controller.mutationsFrozen, isTrue);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey<String>('application-mutation-guard')),
            )
            .absorbing,
        isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(FishingWorkspace.addLoadoutKey, skipOffstage: false),
            )
            .onPressed,
        isNull,
      );

      closeGate.complete();
      await _pumpUntil(
        tester,
        () => !harness.bundle.controller.mutationsFrozen,
      );
      await tester.pump();
      expect(harness.bundle.controller.mutationsFrozen, isFalse);
      expect(
        tester
            .widget<AbsorbPointer>(
              find.byKey(const ValueKey<String>('application-mutation-guard')),
            )
            .absorbing,
        isFalse,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('top-workspace-tab-gathering')),
      );
      await tester.pump();
      await tester.tap(find.byKey(GatheringWorkspace.saveProfileKey));
      await _pumpUntil(
        tester,
        () =>
            find.text('Gathering profile saved locally.').evaluate().isNotEmpty,
      );
      final gathering = await tester.runAsync(
        () => GatheringPersonalStore(
          harness.bundle.personalDataLocation.applicationDirectory,
        ).load(),
      );
      expect(gathering?.profile.mastery, 1775);

      await tester.tap(
        find.byKey(const ValueKey<String>('top-workspace-tab-fishing')),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(FishingWorkspace.addLoadoutKey))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byTooltip('Close'));
      await _pumpUntil(tester, () => windowHost.closeCalls == 2);
      expect(windowHost.closeCalls, 2);
      expect(windowHost.plannerFrozenOnClose, isTrue);
      expect(harness.bundle.controller.mutationsFrozen, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(harness.dispose);
    },
  );

  testWidgets('native close retries after a failed save preparation', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    var failWrites = true;
    var harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone(
      saveStateFactory: (repository) => (state) {
        if (failWrites) throw StateError('simulated planner write failure');
        repository.nativeStateFile.writeAsStringSync(
          repository.codec.encode(state),
          flush: true,
        );
        return SynchronousFuture(state);
      },
    );
    final windowHost = _RecordingWindowHost();

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future<ApplicationBundle>.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        enableBetaUpdates: false,
        enableOpportunityAutoCheck: false,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(windowHost.beforeClose, isNotNull);

    harness.bundle.controller.updateDocument(
      (state) => state.copyWith(showDeleteTools: !state.showDeleteTools),
      immediate: true,
    );
    final firstFailure = await _completeIo(tester, windowHost.beforeClose!());
    expect(firstFailure, isA<StateError>());
    expect(harness.bundle.controller.mutationsFrozen, isFalse);

    failWrites = false;
    final secondFailure = await _completeIo(tester, windowHost.beforeClose!());
    expect(secondFailure, isNull);
    expect(harness.bundle.controller.mutationsFrozen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('ordinary close blocks a previously opened personal-data move', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final source = harness.bundle.stateRepository.paths.applicationDirectory;
    final destination = Directory(
      '${harness.temporaryDirectory.path}${Platform.pathSeparator}blocked-move',
    );
    final location = _GatedPersonalDataLocation(source);
    final bundle = ApplicationBundle(
      catalog: harness.bundle.catalog,
      stateLoad: harness.bundle.stateLoad,
      stateRepository: harness.bundle.stateRepository,
      personalDataLocation: location,
      controller: harness.bundle.controller,
    );
    final closeGate = Completer<void>();
    final windowHost = _RecordingWindowHost(
      failFirstClose: true,
      firstCloseGate: closeGate,
    );

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future<ApplicationBundle>.value(bundle),
        marketGateway: const EmptyMarketGateway(),
        enableBetaUpdates: false,
        enableOpportunityAutoCheck: false,
        windowHost: windowHost,
      ),
    );
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    await tester.tap(find.byKey(ShellDestination.data.actionKey));
    await tester.pumpAndSettle();
    final move = tester
        .widget<DataView>(find.byType(DataView))
        .onMovePersonalData;
    expect(move, isNotNull);

    await tester.tap(find.byTooltip('Close'));
    await _pumpUntil(tester, () => windowHost.closeCalls == 1);
    expect(harness.bundle.controller.mutationsFrozen, isTrue);

    final moveFailure = await _completeIo(tester, move!(destination.path));
    expect(moveFailure, isA<StateError>());
    expect(location.moveStarted.isCompleted, isFalse);
    expect(windowHost.closeCalls, 1);
    expect(harness.bundle.controller.mutationsFrozen, isTrue);

    closeGate.complete();
    await _pumpUntil(tester, () => !harness.bundle.controller.mutationsFrozen);
    expect(location.moveStarted.isCompleted, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets(
    'personal-data move commits a focused edit and freezes through close',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1575, 987));
      var harness = (await tester.runAsync(ApplicationTestHarness.create))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone(
        saveStateFactory: (repository) => (state) {
          repository.nativeStateFile.writeAsStringSync(
            repository.codec.encode(state),
            flush: true,
          );
          return SynchronousFuture(state);
        },
      );

      final source = harness.bundle.stateRepository.paths.applicationDirectory;
      final destination = Directory(
        '${harness.temporaryDirectory.path}${Platform.pathSeparator}moved-profile',
      );
      final location = _GatedPersonalDataLocation(source);
      final bundle = ApplicationBundle(
        catalog: harness.bundle.catalog,
        stateLoad: harness.bundle.stateLoad,
        stateRepository: harness.bundle.stateRepository,
        personalDataLocation: location,
        controller: harness.bundle.controller,
      );
      final windowHost = _RecordingWindowHost(failFirstClose: true);

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future<ApplicationBundle>.value(bundle),
          marketGateway: const EmptyMarketGateway(),
          enableBetaUpdates: false,
          enableOpportunityAutoCheck: false,
          windowHost: windowHost,
        ),
      );
      for (var index = 0; index < 5; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      await tester.tap(find.byKey(ShellDestination.data.actionKey));
      await tester.pumpAndSettle();
      final mastery = find.descendant(
        of: find.byKey(const ValueKey<String>('D01')),
        matching: find.byType(TextField),
      );
      await tester.enterText(mastery, '2345');
      expect(
        harness.bundle.controller.documentSnapshot.alchemy.alchemyMastery,
        1900,
      );

      final move = tester
          .widget<DataView>(find.byType(DataView))
          .onMovePersonalData;
      expect(move, isNotNull);
      final closeAction = tester
          .widget<IconButton>(
            find.descendant(
              of: find.byTooltip('Close'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed;
      expect(closeAction, isNotNull);
      final moveFuture = move!(destination.path);
      var moveCompleted = false;
      Object? moveError;
      unawaited(
        moveFuture
            .then<void>((_) {
              moveCompleted = true;
            })
            .catchError((Object error) {
              moveError = error;
              moveCompleted = true;
            }),
      );
      await tester.pump();
      await tester.pump();
      expect(
        harness.bundle.controller.documentSnapshot.alchemy.alchemyMastery,
        2345,
      );
      expect(harness.bundle.controller.mutationsFrozen, isTrue);
      expect(location.moveStarted.isCompleted, isTrue);
      expect(windowHost.closeCalls, 0);
      expect(await tester.runAsync(source.exists), isTrue);
      expect(
        tester
            .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
            .any((widget) => widget.absorbing),
        isTrue,
      );

      // A stale title-bar callback can still arrive in the frame where the
      // move begins. Rejecting that close must not resume the move's writers.
      closeAction!();
      await tester.pump();
      await tester.pump();
      expect(windowHost.closeCalls, 0);
      expect(harness.bundle.controller.mutationsFrozen, isTrue);

      location.allowCompletion.complete();
      for (var index = 0; index < 20 && !moveCompleted; index++) {
        await tester.pump();
      }

      expect(moveError, isNull);
      expect(moveCompleted, isTrue);
      expect(windowHost.closeCalls, 1);
      expect(find.text('Restart Black Spirit Life'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('personal-data-restart-retry-close')),
        findsOneWidget,
      );
      expect(location.destinationPath, destination.path);
      expect(await tester.runAsync(source.exists), isTrue);
      final movedState = harness.bundle.stateRepository.codec.decode(
        (await tester.runAsync(
          harness.bundle.stateRepository.nativeStateFile.readAsString,
        ))!,
      );
      expect(movedState.alchemy.alchemyMastery, 2345);

      await tester.tap(
        find.byKey(const ValueKey<String>('personal-data-restart-retry-close')),
      );
      await tester.pump();
      expect(windowHost.closeCalls, 2);
      expect(find.text('Closing...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(harness.dispose);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

final class _GatedPersonalDataLocation implements PersonalDataLocationManager {
  _GatedPersonalDataLocation(this.applicationDirectory);

  @override
  final Directory applicationDirectory;

  @override
  bool get moveSupported => true;

  @override
  bool get requiresExistingProfile => true;

  final Completer<void> moveStarted = Completer<void>();
  final Completer<void> allowCompletion = Completer<void>();
  String? destinationPath;

  @override
  Future<Directory> resolveApplicationDirectory() async => applicationDirectory;

  @override
  Future<PersonalDataMoveResult> moveTo(String destinationPath) async {
    this.destinationPath = destinationPath;
    moveStarted.complete();
    await allowCompletion.future;
    return PersonalDataMoveResult(
      fromPath: applicationDirectory.path,
      toPath: destinationPath,
      cleanupPending: false,
    );
  }
}

final class _RecordingWindowHost extends WindowHostService {
  _RecordingWindowHost({
    this.failFirstClose = false,
    this.firstCloseGate,
    this.plannerFrozen,
  });

  final bool failFirstClose;
  final Completer<void>? firstCloseGate;
  final bool Function()? plannerFrozen;
  int closeCalls = 0;
  bool? plannerFrozenOnClose;
  Future<void> Function()? beforeClose;

  @override
  void installCloseRequestHandler(Future<void> Function()? handler) {
    beforeClose = handler;
  }

  @override
  void removeCloseRequestHandler() => beforeClose = null;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> setBottomInset(double logicalPixels) async {}

  @override
  Future<void> close() async {
    closeCalls += 1;
    plannerFrozenOnClose = plannerFrozen?.call();
    if (closeCalls == 1) {
      final gate = firstCloseGate;
      if (gate != null) await gate.future;
    }
    if (failFirstClose && closeCalls == 1) {
      throw StateError('simulated close failure');
    }
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var index = 0; index < 100 && !condition(); index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'Workspace operation did not settle.');
}

Future<Object?> _completeIo(WidgetTester tester, Future<void> work) async {
  var complete = false;
  Object? failure;
  unawaited(
    work.then<void>(
      (_) => complete = true,
      onError: (Object error, StackTrace _) {
        failure = error;
        complete = true;
      },
    ),
  );
  await _pumpUntil(tester, () => complete);
  await tester.pump();
  return failure;
}
