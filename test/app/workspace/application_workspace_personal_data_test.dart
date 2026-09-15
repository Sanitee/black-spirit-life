import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/features/data/data.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
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
      final fishRuntimeHost = _RecordingFishRuntimeHost(
        failApplicationExit: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          enableOpportunityAutoCheck: false,
          applicationFuture: Future<ApplicationBundle>.value(bundle),
          marketGateway: const EmptyMarketGateway(),
          enableBetaUpdates: false,
          windowHost: windowHost,
          fishCompanionRuntimeHost: fishRuntimeHost,
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
      expect(fishRuntimeHost.strictFreezeCalls, 1);
      expect(fishRuntimeHost.applicationExitFreezeCalls, 0);
      expect(await tester.runAsync(source.exists), isTrue);
      expect(
        tester
            .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
            .any((widget) => widget.absorbing),
        isTrue,
      );

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
  _RecordingWindowHost({this.failFirstClose = false});

  final bool failFirstClose;
  int closeCalls = 0;

  @override
  void installCloseRequestHandler(Future<void> Function()? handler) {}

  @override
  void removeCloseRequestHandler() {}

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> setBottomInset(double logicalPixels) async {}

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (failFirstClose && closeCalls == 1) {
      throw StateError('simulated close failure');
    }
  }
}

final class _RecordingFishRuntimeHost extends FishCompanionRuntimeHost {
  _RecordingFishRuntimeHost({this.failApplicationExit = false})
    : super.withStarter((_) async => _NoopFishCompanionServiceHandle());

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
